// Airtime unter Buddys (#36 Schritt 6): Schalter, Abgleich, Anzeige.
//
// **Wer nicht teilt, sieht auch nichts.** Bestwerte und Zähler der Buddys
// lädt die App nur, solange der eigene Schalter an ist — ein Spiel
// zwischen denen, die mitspielen, und die Funktion bleibt versteckt,
// solange der Test-Schalter sie versteckt (Betreiber, 2026-11-07).
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/settings.dart';
import '../../data/airtime_repository.dart';
import '../../data/providers.dart';
import '../trails/trail_providers.dart';
import 'airtime_share.dart';
import 'ride_providers.dart';

/// Teile ich Airtime mit Buddys? Nur, wo es den Test-Schalter gibt, und
/// nur, solange er an ist — ohne Erkennung gäbe es nichts zu teilen.
class AirtimeShareNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sensorLogProvider) && ref.read(settingsProvider).airtimeShareEnabled;

  /// Einschalten teilt beim nächsten Abgleich (sofort angestoßen).
  /// Ausschalten löscht das Geteilte auf dem Server — und scheitert
  /// sichtbar, ohne Netz: Der Schalter bliebe sonst aus, die Werte aber
  /// stünden weiter bei den Buddys.
  Future<void> set(bool value) async {
    if (!value) await ref.read(airtimeRepositoryProvider).deleteMine();
    await ref.read(settingsProvider).setAirtimeShareEnabled(value);
    // Die Anzeige hört auf diesen Zustand und lädt von selbst neu.
    state = value;
    if (value) unawaited(ref.read(airtimeSyncProvider).run());
  }
}

final airtimeShareProvider =
    NotifierProvider<AirtimeShareNotifier, bool>(AirtimeShareNotifier.new);

/// Was ich sehen darf: alle sichtbaren Bestwerte und Zähler. null, solange
/// ich nicht teile oder nicht angemeldet bin.
class AirtimeBoard {
  const AirtimeBoard({required this.bests, required this.counters});

  final List<TrailAirtime> bests;
  final List<AirtimeCounter> counters;

  AirtimeCounter? counterOf(String userId) =>
      counters.where((c) => c.userId == userId).firstOrNull;

  TrailAirtime? bestOf(String userId, String trailId) =>
      bests.where((b) => b.userId == userId && b.trailId == trailId).firstOrNull;
}

final airtimeBoardProvider = FutureProvider<AirtimeBoard?>((ref) async {
  if (!ref.watch(airtimeShareProvider)) return null;
  if (ref.watch(currentUserIdProvider) == null) return null;
  final repo = ref.read(airtimeRepositoryProvider);
  final (bests, counters) = await (repo.fetchBests(), repo.fetchCounters()).wait;
  return AirtimeBoard(bests: bests, counters: counters);
});

/// Rechnet aus den eigenen Fahrten, was geteilt wird, und schickt es.
/// Idempotent: Der Server behält das Bessere, der Zähler wird
/// überschrieben. Läuft nie doppelt — ein Anstoß während eines Laufs
/// rechnet danach noch einmal.
class AirtimeSync {
  AirtimeSync(this._ref);

  final Ref _ref;
  Future<void>? _running;
  var _again = false;

  /// Für Tests: wann gerechnet wird.
  DateTime Function() now = DateTime.now;

  Future<void> run() {
    if (_running != null) {
      _again = true;
      return _running!;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      await _once();
    } while (_again);
  }

  Future<void> _once() async {
    if (!_ref.read(airtimeShareProvider)) return;
    final uid = _ref.read(currentUserIdProvider);
    if (uid == null) return;
    try {
      final rides = await _ref.read(ridesProvider.future);
      final trails = await _ref.read(trailsProvider.future);
      final store = _ref.read(rideStoreProvider);
      final measured = <MeasuredRide>[
        for (final r in rides)
          if (!r.planned && !r.imported)
            (ride: r, log: await store.airtimeLog(r.id), measured: await store.sensorLogPath(r.id) != null),
      ];
      final share = computeAirtimeShare(rides: measured, trails: trails, now: now());
      final repo = _ref.read(airtimeRepositoryProvider);
      await repo.uploadBests(share.bests);
      await repo.setCounter(airDs: share.airDs, jumps: share.jumps, asOf: now(), titles: share.titles);
      _ref.invalidate(airtimeBoardProvider);
    } catch (e, s) {
      // Kein Ausgangskorb: Die Fahrten bleiben auf dem Gerät, der nächste
      // Anstoß (Start, neue Fahrt, Schalter) schickt alles noch einmal.
      // Geloggt, nicht gezeigt — ein Abgleich im Hintergrund hat keinen
      // Knopf, an dem ein Fehler stehen könnte.
      logError('Airtime abgleichen', e, s);
    }
  }
}

final airtimeSyncProvider = Provider<AirtimeSync>(AirtimeSync.new);

/// Stößt den Abgleich an: beim Start und sobald sich die eigenen Fahrten
/// ändern (eine neue Fahrt, eine gelöschte). Sitzt in der Hülle wie der
/// Ausgangskorb (`OutboxTrigger`).
class AirtimeSyncTrigger extends ConsumerStatefulWidget {
  const AirtimeSyncTrigger({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AirtimeSyncTrigger> createState() => _AirtimeSyncTriggerState();
}

class _AirtimeSyncTriggerState extends ConsumerState<AirtimeSyncTrigger> {
  @override
  void initState() {
    super.initState();
    if (ref.read(airtimeShareProvider)) unawaited(ref.read(airtimeSyncProvider).run());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(ridesProvider, (prev, next) {
      if (!next.hasValue || identical(prev?.valueOrNull, next.valueOrNull)) return;
      if (prev?.hasValue != true) return; // der erste Stand: schon beim Start
      if (ref.read(airtimeShareProvider)) unawaited(ref.read(airtimeSyncProvider).run());
    });
    return widget.child;
  }
}
