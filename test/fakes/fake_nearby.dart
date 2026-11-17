import 'dart:async';

import 'package:trailbuddy/data/nearby_repository.dart';

import 'fake_backend.dart';

/// Buddy in der Nähe im Speicher (Patch 031). Spiegelt die Policies auf
/// `realtime.messages`: Zuhören geht nur bei direkten Buddys, die einen
/// nicht über „sieht mich" ausgeschlossen haben ([hiddenBy]: Besitzer →
/// ausgeschlossene). [cellsOf] ist, was jeder gerade in seinen Kanal
/// gelegt hat; ein Test setzt die Zellen der Buddys mit [setCell].
class FakeNearbyRepository implements NearbyRepository {
  FakeNearbyRepository(this.backend);

  final FakeBackend backend;

  final cellsOf = <String, String>{};
  final hiddenBy = <String, Set<String>>{};
  final prefs = <String, NearbyPref>{};
  final listening = <String>{};
  final shared = <String?>[];
  bool offline = false;

  final _cells = StreamController<NearbyCellEvent>.broadcast();

  String? get _uid => backend.currentUserId;

  bool _mayRead(String owner) {
    final me = _uid;
    if (me == null) return false;
    return backend.areFriends(owner, me) && !(hiddenBy[owner]?.contains(me) ?? false);
  }

  /// Ein Buddy legt [cell] in seinen Kanal (null: geht weg).
  void setCell(String buddyId, String? cell) {
    if (cell == null) {
      cellsOf.remove(buddyId);
    } else {
      cellsOf[buddyId] = cell;
    }
    if (listening.contains(buddyId)) _cells.add((buddyId: buddyId, cell: cell));
  }

  @override
  Future<List<NearbyPref>> fetchPrefs() async {
    backend.failIfOffline();
    return prefs.values.toList();
  }

  @override
  Future<void> setPref(NearbyPref pref) async {
    backend.failIfOffline();
    if (!pref.hidden && !pref.muted) {
      prefs.remove(pref.buddyId);
    } else {
      prefs[pref.buddyId] = pref;
    }
    final me = _uid;
    if (me != null) {
      final set = hiddenBy.putIfAbsent(me, () => <String>{});
      pref.hidden ? set.add(pref.buddyId) : set.remove(pref.buddyId);
    }
  }

  @override
  Stream<NearbyCellEvent> get cells => _cells.stream;

  @override
  Future<void> share(String? cell) async {
    if (cell != null && offline) throw StateError('kein Empfang');
    final me = _uid;
    if (me == null) return;
    if (shared.isEmpty || shared.last != cell) shared.add(cell);
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
        _cells.add((buddyId: id, cell: null));
      }
    }
    for (final id in buddyIds) {
      if (listening.contains(id) || offline || !_mayRead(id)) continue;
      listening.add(id);
      _cells.add((buddyId: id, cell: cellsOf[id]));
    }
  }

  @override
  Future<void> close() async {
    await share(null);
    await listen(const {});
  }
}
