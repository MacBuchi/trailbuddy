// Buddy in der Nähe (#526) — Zustand und Steuerung.
//
// **Wer was weiß.** Der Schalter „Buddys unterwegs" und „Zuhause" liegen
// nur auf dem Gerät (`Settings`), die zwei Schalter je Buddy auf dem
// Server (`buddy_nearby_prefs`, damit „sieht mich" dort wirkt). Ob gerade
// geteilt wird, rechnet [nearbyPauseProvider] rein aus Position, Fahrt,
// Vordergrund und den beiden Merkern; [NearbyEngine] macht daraus Kanal-
// Aufträge und Meldungen, gehalten von `NearbyHost` in `app.dart`.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/geo.dart';
import '../../core/read_after_write.dart';
import '../../core/settings.dart';
import '../../data/nearby_repository.dart';
import '../../data/providers.dart';
import '../garmin/watch_providers.dart' show watchSyncProvider;
import '../map/position_provider.dart';
import '../rides/ride_providers.dart';
import 'nearby_core.dart';

/// „Buddys unterwegs" — null, solange nie gefragt.
class BuddiesNearbyNotifier extends Notifier<bool?> {
  @override
  bool? build() => ref.read(settingsProvider).buddiesNearby;

  void set(bool value) {
    state = value;
    unawaited(ref
        .read(settingsProvider)
        .setBuddiesNearby(value)
        .catchError((Object e, StackTrace s) => logError('„Buddys unterwegs" merken', e, s)));
  }
}

final buddiesNearbyProvider =
    NotifierProvider<BuddiesNearbyNotifier, bool?>(BuddiesNearbyNotifier.new);

/// „Zuhause", nur auf dem Gerät.
class NearbyHomeNotifier extends Notifier<NearbyPoint?> {
  @override
  NearbyPoint? build() => parseNearbyHome(ref.read(settingsProvider).nearbyHome);

  void set(NearbyPoint? value) {
    state = value;
    unawaited(ref
        .read(settingsProvider)
        .setNearbyHome(value == null ? null : encodeNearbyHome(value))
        .catchError((Object e, StackTrace s) => logError('„Zuhause" merken', e, s)));
  }
}

final nearbyHomeProvider =
    NotifierProvider<NearbyHomeNotifier, NearbyPoint?>(NearbyHomeNotifier.new);

/// Ist die App gerade vorne? Gesetzt von `NearbyHost`
/// (`AppLifecycleListener`); ab Werk ja.
class AppForegroundNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool value) => state = value;
}

final appForegroundProvider =
    NotifierProvider<AppForegroundNotifier, bool>(AppForegroundNotifier.new);

/// Die eigene Position, ohne Fix null.
final nearbyPositionProvider = Provider<NearbyPoint?>((ref) {
  final p = ref.watch(positionStreamProvider).valueOrNull;
  return p == null ? null : (lat: p.latitude, lon: p.longitude);
});

/// Der Start der laufenden Aufzeichnung (der erste Punkt), sonst null.
final nearbyRideStartProvider = Provider<NearbyPoint?>((ref) {
  final ride = ref.watch(rideProvider);
  final first = ride?.points.firstOrNull;
  return first == null ? null : (lat: first.lat, lon: first.lng);
});

/// Warum gerade nicht geteilt wird, oder null — dann wird geteilt.
final nearbyPauseProvider = Provider<NearbyPause?>((ref) {
  final ride = ref.watch(rideProvider);
  final start = ref.watch(nearbyRideStartProvider);
  return nearbyPause(
    enabled: ref.watch(buddiesNearbyProvider),
    position: ref.watch(nearbyPositionProvider),
    home: ref.watch(nearbyHomeProvider),
    // Läuft die Fahrt, aber ohne Punkt: der erste Kilometer ab dem
    // nächsten Fix — bis dahin nicht teilen.
    rideStart: ride != null && start == null ? ref.watch(nearbyPositionProvider) : start,
    foreground: ref.watch(appForegroundProvider),
  );
});

/// Meine Schalter je Buddy (buddyId → Schalter), vom Server.
class NearbyPrefsNotifier extends AsyncNotifier<Map<String, NearbyPref>>
    with ReadAfterWrite<Map<String, NearbyPref>> {
  @override
  Future<Map<String, NearbyPref>> build() async {
    ref.watch(currentUserIdProvider);
    if (ref.read(currentUserIdProvider) == null) return {};
    final list = await ref.read(nearbyRepositoryProvider).fetchPrefs();
    return {for (final p in list) p.buddyId: p};
  }

  /// Schreibt beide Schalter; wirft — das Blatt zeigt den Fehler.
  Future<void> set(NearbyPref pref) async {
    await ref.read(nearbyRepositoryProvider).setPref(pref);
    await reloadAfterWrite('Schalter „Buddys unterwegs" neu laden');
  }
}

final nearbyPrefsProvider =
    AsyncNotifierProvider<NearbyPrefsNotifier, Map<String, NearbyPref>>(NearbyPrefsNotifier.new);

/// „Live mit Buddys" (#519, E4) — je Fahrt, ab Werk aus, und mit dem
/// Ende der Fahrt vorbei: Der Zustand hängt am Beginn der Aufzeichnung,
/// eine neue Fahrt (oder keine) baut ihn neu, also aus.
class LiveShareNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(rideProvider.select((r) => r?.startedAt));
    return false;
  }

  void set(bool value) {
    if (ref.read(rideProvider) == null) return;
    state = value;
  }
}

final liveShareProvider = NotifierProvider<LiveShareNotifier, bool>(LiveShareNotifier.new);

/// Was ich gerade von den Buddys weiß — gesetzt von `NearbyHost` aus der
/// Engine, nur im Speicher.
class BuddySightingsNotifier extends Notifier<List<BuddySighting>> {
  @override
  List<BuddySighting> build() {
    ref.watch(currentUserIdProvider);
    return const [];
  }

  void set(List<BuddySighting> value) {
    state = value;
    // Die genauen Positionen auch an die Uhr (#519), wenn sie da ist.
    ref.read(watchSyncProvider.notifier).buddiesChanged(value);
  }
}

final buddySightingsProvider =
    NotifierProvider<BuddySightingsNotifier, List<BuddySighting>>(BuddySightingsNotifier.new);

/// Wer hat mich als Homie gewählt (Patch 032)? Ohne Empfang niemand —
/// dann zeigt die Karte eben keine Zelle.
final homieOwnersProvider = FutureProvider<Set<String>>((ref) async {
  ref.watch(currentUserIdProvider);
  if (ref.read(currentUserIdProvider) == null) return const {};
  return ref.read(nearbyRepositoryProvider).fetchHomieOwners();
});

/// Die Uhr der Karte: alle 30 s, damit „zuletzt vor …" weiterzählt und
/// Altes verschwindet. Nur, solange jemand zu sehen ist.
final buddyMapClockProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 30), (_) => DateTime.now());
});

/// Was die Karte zeigt — [buddyMapEntries] auf dem aktuellen Stand.
final buddyMapEntriesProvider = Provider.autoDispose<List<BuddyMapEntry>>((ref) {
  final sightings = ref.watch(buddySightingsProvider);
  if (sightings.isEmpty) return const [];
  return buddyMapEntries(
    sightings,
    homieOwners: ref.watch(homieOwnersProvider).valueOrNull ?? const {},
    now: ref.watch(buddyMapClockProvider).valueOrNull ?? DateTime.now(),
  );
});

/// Macht aus dem Zustand Kanal-Aufträge und Meldungen. Ohne Riverpod und
/// ohne Widgets, damit der Test die Uhr und die Reihenfolge in der Hand
/// hat. Aufträge laufen nacheinander; ein Fehler (kein Empfang) heißt nur
/// „beim nächsten Abgleich wieder".
///
/// Seit #519 führt sie auch, was ich von jedem Buddy weiß
/// ([BuddySighting]: Zelle, Live, genaue Position) und hält die
/// Paarkanäle — mit genau den Buddys, die [livePairsFor] nennt.
class NearbyEngine {
  NearbyEngine(this._repo, {required this.onNotice, this.onSightings, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now {
    _sub = _repo.cells.listen(_onCell);
    _posSub = _repo.positions.listen(_onPosition);
  }

  final NearbyRepository _repo;

  /// Ein Buddy ist in dieser Fahrt zum ersten Mal in der Nähe.
  final void Function(String buddyId) onNotice;

  /// Was ich von den Buddys weiß, hat sich geändert (für die Karte).
  final void Function(List<BuddySighting> sightings)? onSightings;

  final DateTime Function() _clock;

  /// So oft wird die Zelle neu gesetzt, auch ohne Wechsel — nach einer
  /// abgerissenen Verbindung trüge der Kanal sie sonst nicht mehr.
  static const retrack = Duration(minutes: 5);

  /// So oft wird abgelehnten oder abgerissenen Buddy-Kanälen neu
  /// beigetreten.
  static const relisten = Duration(minutes: 2);

  /// Die genaue Position geht höchstens so oft hinaus …
  static const liveEvery = Duration(seconds: 15);

  /// … oder sofort, wenn ich mich so weit bewegt habe.
  static const liveMoveMeters = 40.0;

  late final StreamSubscription<NearbyCellEvent> _sub;
  late final StreamSubscription<LivePositionEvent> _posSub;
  final _log = NearbyNoticeLog();
  final _sightings = <String, BuddySighting>{};
  Future<void> _chain = Future.value();

  NearbyCell? _mine;
  bool _live = false;
  NearbyPoint? _position;
  String? _trackedCell;
  bool _trackedLive = false;
  DateTime? _trackedAt;
  Set<String> _listened = const {};
  DateTime? _listenedAt;
  Set<String> _pairs = const {};
  DateTime? _pairedAt;
  NearbyPoint? _liveSentAt;
  DateTime? _liveSentTime;
  /// null, solange die Schalter je Buddy nicht geladen sind — dann wird
  /// niemand gemeldet (ein stummer Buddy käme sonst beim Start durch).
  Set<String>? _muted;
  Object? _session;
  bool _closed = false;

  /// Der neue Stand. [mine] null heißt: nicht teilen, nicht zuhören;
  /// [muted] null heißt: Schalter je Buddy noch nicht geladen; [live]:
  /// „Live mit Buddys" ist in der laufenden Fahrt an, [position] die
  /// genaue Position dazu.
  Future<void> sync({
    required NearbyCell? mine,
    required Set<String> buddies,
    required Set<String>? muted,
    required Object? session,
    bool live = false,
    NearbyPoint? position,
  }) {
    _chain = _chain.then((_) => _sync(mine, buddies, muted, session, live && mine != null, position));
    return _chain;
  }

  Future<void> _sync(
      NearbyCell? mine, Set<String> buddies, Set<String>? muted, Object? session, bool live, NearbyPoint? position) async {
    if (_closed) return;
    _mine = mine;
    _muted = muted;
    _session = session;
    _live = live;
    _position = position;
    final now = _clock();
    try {
      if (mine == null) {
        if (_trackedCell != null) {
          _trackedCell = null;
          await _repo.share(null);
        }
      } else if (mine.encode() != _trackedCell ||
          live != _trackedLive ||
          _trackedAt == null ||
          now.difference(_trackedAt!) >= retrack) {
        await _repo.share(mine.encode(), live: live);
        _trackedCell = mine.encode();
        _trackedLive = live;
        _trackedAt = now;
      }
    } catch (_) {
      // Kein Empfang (A8): nichts geteilt; der nächste Abgleich versucht es.
      _trackedCell = null;
    }
    final want = mine == null ? const <String>{} : buddies;
    if (!setEquals(want, _listened) ||
        (want.isNotEmpty && (_listenedAt == null || now.difference(_listenedAt!) >= relisten))) {
      _listened = Set.of(want);
      _listenedAt = now;
      try {
        await _repo.listen(want);
      } catch (_) {
        // Wie oben: ohne Empfang hört niemand zu.
      }
    }
    // Wer nicht teilt, sieht auch nichts (#526: wer nicht teilt, hört nicht
    // zu) — und wer kein Buddy mehr ist, fällt heraus.
    final before = _sightings.length;
    _sightings.removeWhere((id, _) => mine == null || !buddies.contains(id));
    if (_sightings.length != before) _emit();
    for (final id in _sightings.keys.toList()) {
      _check(id);
    }
    await _updatePairs(now);
  }

  Future<void> _updatePairs(DateTime now) async {
    if (_closed) return;
    final want = livePairsFor(
      mine: _mine,
      myLive: _live,
      sightings: [for (final s in _sightings.values) if (_listened.contains(s.buddyId)) s],
    );
    if (!setEquals(want, _pairs) ||
        (want.isNotEmpty && (_pairedAt == null || now.difference(_pairedAt!) >= relisten))) {
      final dropped = _pairs.difference(want);
      _pairs = Set.of(want);
      _pairedAt = now;
      try {
        await _repo.livePairs(want);
      } catch (_) {
        // Ohne Empfang kein Paarkanal; der nächste Abgleich versucht es.
      }
      // Wer nicht mehr in der Nähe ist (oder Live aus hat), bekommt nichts
      // mehr — und ich zeige seine genaue Position nicht weiter.
      for (final id in dropped) {
        final s = _sightings[id];
        if (s != null) _sightings[id] = s.copyWith(position: () => null, positionAt: () => null, positionPresent: false);
      }
      if (dropped.isNotEmpty) _emit();
    }
    final pos = _position;
    if (want.isEmpty || pos == null) {
      _liveSentAt = null;
      _liveSentTime = null;
      return;
    }
    final last = _liveSentAt;
    final moved = last == null ? double.infinity : distanceMeters(last.lat, last.lon, pos.lat, pos.lon);
    if (moved >= liveMoveMeters || _liveSentTime == null || now.difference(_liveSentTime!) >= liveEvery) {
      _liveSentAt = pos;
      _liveSentTime = now;
      try {
        await _repo.trackLive(pos.lat, pos.lon, now);
      } catch (_) {
        // Wie oben.
      }
    }
  }

  void _onCell(NearbyCellEvent e) {
    final cell = NearbyCell.tryParse(e.cell);
    final old = _sightings[e.buddyId];
    if (cell == null) {
      if (old == null) return;
      _sightings[e.buddyId] = old.copyWith(
        cellPresent: false,
        cellGoneAt: () => old.cellPresent ? _clock() : old.cellGoneAt,
        live: false,
      );
    } else {
      _sightings[e.buddyId] = (old ?? BuddySighting(buddyId: e.buddyId))
          .copyWith(cell: () => cell, cellPresent: true, cellGoneAt: () => null, live: e.live);
      _check(e.buddyId);
    }
    _emit();
    _chain = _chain.then((_) => _updatePairs(_clock()));
  }

  void _onPosition(LivePositionEvent e) {
    final old = _sightings[e.buddyId];
    if (old == null) return;
    final lat = e.lat, lon = e.lon, at = e.at;
    if (lat == null || lon == null || at == null) {
      if (!old.positionPresent) return;
      _sightings[e.buddyId] = old.copyWith(positionPresent: false);
    } else {
      // Nie in der Zukunft — eine vorgehende Uhr machte sonst „frisch".
      final now = _clock();
      _sightings[e.buddyId] = old.copyWith(
        position: () => (lat: lat, lon: lon),
        positionAt: () => at.isAfter(now) ? now : at,
        positionPresent: true,
      );
    }
    _emit();
  }

  void _emit() => onSightings?.call(List.unmodifiable(_sightings.values));

  void _check(String id) {
    final mine = _mine;
    final theirs = _sightings[id];
    if (mine == null || theirs == null || !theirs.cellPresent || theirs.cell == null) return;
    final muted = _muted;
    if (muted == null || !_listened.contains(id) || muted.contains(id)) return;
    if (!mine.isNearTo(theirs.cell!)) return;
    if (_log.firstTime(id, _session)) onNotice(id);
  }

  Future<void> close() async {
    await _chain;
    _closed = true;
    await _sub.cancel();
    await _posSub.cancel();
    try {
      await _repo.livePairs(const {});
      await _repo.share(null);
      await _repo.listen(const {});
    } catch (_) {
      // Beim Schließen ohne Empfang: Presence geht mit der Verbindung.
    }
  }
}
