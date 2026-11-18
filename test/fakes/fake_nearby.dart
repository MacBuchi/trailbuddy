import 'dart:async';

import 'package:trailbuddy/data/nearby_repository.dart';

import 'fake_backend.dart';

/// Buddy in der Nähe im Speicher (Patch 031). Spiegelt die Policies auf
/// `realtime.messages`: Zuhören geht nur bei direkten Buddys, die einen
/// nicht über „sieht mich" ausgeschlossen haben ([hiddenBy]: Besitzer →
/// ausgeschlossene). [cellsOf] ist, was jeder gerade in seinen Kanal
/// gelegt hat; ein Test setzt die Zellen der Buddys mit [setCell].
///
/// Gruppenfahrt (Patch 032): Paarkanäle nur zwischen direkten Buddys, von
/// denen keiner den anderen ausgeschlossen hat ([pairs]); was der Buddy
/// dort setzt, kommt über [setPosition]; was ich hinauslege, steht in
/// [liveSent]. Homies: [homieBy] (Besitzer → gewählte).
class FakeNearbyRepository implements NearbyRepository {
  FakeNearbyRepository(this.backend);

  final FakeBackend backend;

  final cellsOf = <String, String>{};
  final liveOf = <String, bool>{};
  final homieBy = <String, Set<String>>{};
  final pairs = <String>{};
  final positionsOf = <String, LivePositionEvent>{};
  final liveSent = <({double lat, double lon})>[];
  final sharedLive = <bool>[];
  final hiddenBy = <String, Set<String>>{};
  final prefs = <String, NearbyPref>{};
  final listening = <String>{};
  final shared = <String?>[];
  bool offline = false;

  final _cells = StreamController<NearbyCellEvent>.broadcast();
  final _positions = StreamController<LivePositionEvent>.broadcast();

  /// `app_internal.may_live`: beide Buddys, keiner hat den anderen
  /// ausgeschlossen.
  bool _mayLive(String other) {
    final me = _uid;
    if (me == null) return false;
    return backend.areFriends(other, me) &&
        !(hiddenBy[other]?.contains(me) ?? false) &&
        !(hiddenBy[me]?.contains(other) ?? false);
  }

  /// Ein Buddy legt im Paarkanal seine genaue Position ab (null: geht).
  void setPosition(String buddyId, double? lat, double? lon, {DateTime? at}) {
    final e = (
      buddyId: buddyId,
      lat: lat,
      lon: lon,
      at: lat == null ? null : (at ?? DateTime.now()).toUtc(),
    );
    if (lat == null) {
      positionsOf.remove(buddyId);
    } else {
      positionsOf[buddyId] = e;
    }
    if (pairs.contains(buddyId)) _positions.add(e);
  }

  String? get _uid => backend.currentUserId;

  bool _mayRead(String owner) {
    final me = _uid;
    if (me == null) return false;
    return backend.areFriends(owner, me) &&
        !(hiddenBy[owner]?.contains(me) ?? false);
  }

  /// Ein Buddy legt [cell] in seinen Kanal (null: geht weg).
  void setCell(String buddyId, String? cell, {bool live = false}) {
    if (cell == null) {
      cellsOf.remove(buddyId);
      liveOf.remove(buddyId);
    } else {
      cellsOf[buddyId] = cell;
      liveOf[buddyId] = live;
    }
    if (listening.contains(buddyId)) {
      _cells.add((buddyId: buddyId, cell: cell, live: cell != null && live));
    }
  }

  @override
  Future<List<NearbyPref>> fetchPrefs() async {
    backend.failIfOffline();
    return prefs.values.toList();
  }

  @override
  Future<void> setPref(NearbyPref pref) async {
    backend.failIfOffline();
    if (pref.isDefault) {
      prefs.remove(pref.buddyId);
    } else {
      prefs[pref.buddyId] = pref;
    }
    final me = _uid;
    if (me != null) {
      final set = hiddenBy.putIfAbsent(me, () => <String>{});
      pref.hidden ? set.add(pref.buddyId) : set.remove(pref.buddyId);
      final homies = homieBy.putIfAbsent(me, () => <String>{});
      pref.homie ? homies.add(pref.buddyId) : homies.remove(pref.buddyId);
    }
  }

  @override
  Future<Set<String>> fetchHomieOwners() async {
    backend.failIfOffline();
    final me = _uid;
    if (me == null) return const {};
    return {
      for (final e in homieBy.entries)
        if (e.value.contains(me) &&
            backend.areFriends(e.key, me) &&
            !(hiddenBy[e.key]?.contains(me) ?? false))
          e.key,
    };
  }

  @override
  Stream<LivePositionEvent> get positions => _positions.stream;

  @override
  Future<void> livePairs(Set<String> buddyIds) async {
    for (final id in pairs.toList()) {
      if (!buddyIds.contains(id)) {
        pairs.remove(id);
        _positions.add((buddyId: id, lat: null, lon: null, at: null));
      }
    }
    for (final id in buddyIds) {
      if (pairs.contains(id) || offline || !_mayLive(id)) continue;
      pairs.add(id);
      final pos = positionsOf[id];
      if (pos != null) _positions.add(pos);
    }
  }

  @override
  Future<void> trackLive(double lat, double lon, DateTime at) async {
    if (offline) throw StateError('kein Empfang');
    if (pairs.isEmpty) return;
    liveSent.add((lat: lat, lon: lon));
  }

  @override
  Stream<NearbyCellEvent> get cells => _cells.stream;

  @override
  Future<void> share(String? cell, {bool live = false}) async {
    if (cell != null && offline) throw StateError('kein Empfang');
    final me = _uid;
    if (me == null) return;
    if (shared.isEmpty || shared.last != cell) shared.add(cell);
    if (cell != null) sharedLive.add(live);
    if (cell == null) {
      cellsOf.remove(me);
    } else {
      cellsOf[me] = cell;
    }
  }

  @override
  Future<void> listen(Set<String> buddyIds) async {
    for (final id in listening.toList()) {
      if (!buddyIds.contains(id)) {
        listening.remove(id);
        _cells.add((buddyId: id, cell: null, live: false));
      }
    }
    for (final id in buddyIds) {
      if (listening.contains(id) || offline || !_mayRead(id)) continue;
      listening.add(id);
      _cells.add((buddyId: id, cell: cellsOf[id], live: liveOf[id] ?? false));
    }
  }

  @override
  Future<void> close() async {
    await livePairs(const {});
    await share(null);
    await listen(const {});
  }
}
