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
import '../../core/read_after_write.dart';
import '../../core/settings.dart';
import '../../data/nearby_repository.dart';
import '../../data/providers.dart';
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

/// Macht aus dem Zustand Kanal-Aufträge und Meldungen. Ohne Riverpod und
/// ohne Widgets, damit der Test die Uhr und die Reihenfolge in der Hand
/// hat. Aufträge laufen nacheinander; ein Fehler (kein Empfang) heißt nur
/// „beim nächsten Abgleich wieder".
class NearbyEngine {
  NearbyEngine(this._repo, {required this.onNotice, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now {
    _sub = _repo.cells.listen(_onCell);
  }

  final NearbyRepository _repo;

  /// Ein Buddy ist in dieser Fahrt zum ersten Mal in der Nähe.
  final void Function(String buddyId) onNotice;

  final DateTime Function() _clock;

  /// So oft wird die Zelle neu gesetzt, auch ohne Wechsel — nach einer
  /// abgerissenen Verbindung trüge der Kanal sie sonst nicht mehr.
  static const retrack = Duration(minutes: 5);

  /// So oft wird abgelehnten oder abgerissenen Buddy-Kanälen neu
  /// beigetreten.
  static const relisten = Duration(minutes: 2);

  late final StreamSubscription<NearbyCellEvent> _sub;
  final _log = NearbyNoticeLog();
  final _cells = <String, NearbyCell>{};
  Future<void> _chain = Future.value();

  NearbyCell? _mine;
  String? _trackedCell;
  DateTime? _trackedAt;
  Set<String> _listened = const {};
  DateTime? _listenedAt;
  /// null, solange die Schalter je Buddy nicht geladen sind — dann wird
  /// niemand gemeldet (ein stummer Buddy käme sonst beim Start durch).
  Set<String>? _muted;
  Object? _session;
  bool _closed = false;

  /// Der neue Stand. [mine] null heißt: nicht teilen, nicht zuhören;
  /// [muted] null heißt: Schalter je Buddy noch nicht geladen.
  Future<void> sync({
    required NearbyCell? mine,
    required Set<String> buddies,
    required Set<String>? muted,
    required Object? session,
  }) {
    _chain = _chain.then((_) => _sync(mine, buddies, muted, session));
    return _chain;
  }

  Future<void> _sync(NearbyCell? mine, Set<String> buddies, Set<String>? muted, Object? session) async {
    if (_closed) return;
    _mine = mine;
    _muted = muted;
    _session = session;
    final now = _clock();
    try {
      if (mine == null) {
        if (_trackedCell != null) {
          _trackedCell = null;
          await _repo.share(null);
        }
      } else if (mine.encode() != _trackedCell ||
          _trackedAt == null ||
          now.difference(_trackedAt!) >= retrack) {
        await _repo.share(mine.encode());
        _trackedCell = mine.encode();
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
    for (final id in _cells.keys.toList()) {
      _check(id);
    }
  }

  void _onCell(NearbyCellEvent e) {
    final cell = NearbyCell.tryParse(e.cell);
    if (cell == null) {
      _cells.remove(e.buddyId);
      return;
    }
    _cells[e.buddyId] = cell;
    _check(e.buddyId);
  }

  void _check(String id) {
    final mine = _mine;
    final theirs = _cells[id];
    if (mine == null || theirs == null) return;
    final muted = _muted;
    if (muted == null || !_listened.contains(id) || muted.contains(id)) return;
    if (!mine.isNearTo(theirs)) return;
    if (_log.firstTime(id, _session)) onNotice(id);
  }

  Future<void> close() async {
    await _chain;
    _closed = true;
    await _sub.cancel();
    try {
      await _repo.share(null);
      await _repo.listen(const {});
    } catch (_) {
      // Beim Schließen ohne Empfang: Presence geht mit der Verbindung.
    }
  }
}
