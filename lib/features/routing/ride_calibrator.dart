// Lernen aus den eigenen Fahrten (#158 Schritt 6): liest die Fahrten des
// Kontos vom Gerät, ordnet jede über den Wegegraphen ihres Korridors ein
// (eingeordnet wird, nicht geplant — ein Abschnitt in einer fehlenden
// Kachel ist „abseits" und zählt nicht) und rechnet je Profil die
// gelernten Werte (`ride_calibration.dart`, pur). Gemerkt in
// `Settings.riderCalibration`; die Planer lesen das Profil über
// [calibratedRiderProvider].
//
// Seit #356 PR 9 (Konzept-Routing 10.6) liest der UI-Isolate je Fahrt nur
// die Bytes der Kacheln, die die Linie berührt (`tilesAlong`, nicht ihr
// ganzer Rahmen), der Rechen-Isolate des Planers baut daraus den Graphen
// und ordnet die Fahrt ein ([CalibJob]) — der Haupt-Thread baut nichts
// mehr. Höchstens [kCalibMaxRides] Fahrten je Lauf, die jüngsten zuerst.
//
// Gelernt wird auf Knopfdruck (Profil, „Fahrerprofil"), nicht nach jeder
// Fahrt: Das Einordnen liest Kacheln aus den Bereichen, und ein Blatt,
// das nach drei Stunden Fahren erst einmal rechnet, wäre der falsche
// Moment. Fahrten ohne Profil (vor 0.70.0), geplante Fahrten und Fahrten
// ohne Höhen lernen nichts. Fahrten aus GPX-Dateien (#188) lernen mit,
// sobald sie mit Profil in „Meine Fahrten" liegen — ihre Höhen sind die
// der Datei.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/errors.dart';
import '../../core/line_geometry.dart';
import '../../core/settings.dart';
import '../../core/stall_watch.dart';
import '../../l10n/l10n.dart';
import '../../data/providers.dart';
import '../offline_areas/area_providers.dart';
import '../offline_areas/area_store.dart';
import '../rides/ride_providers.dart';
import 'graph_input.dart' show GraphInput;
import 'loop_plan_runner.dart';
import 'ride_calibration.dart';
import 'road_graph_loader.dart';
import 'route_profile.dart';

/// Was ein Lernlauf gesehen hat — für den Satz danach.
typedef LearnResult = ({
  int rides,
  int usable,
  int withoutArea,

  /// Brauchbare Fahrten jenseits von [kCalibMaxRides] — nicht angesehen.
  int skipped,
  Map<RiderProfile, int> ridesByProfile,
  Map<RiderProfile, int> sectionsByProfile,
});


class RiderCalibrationsNotifier extends Notifier<RiderCalibrations> {
  @override
  RiderCalibrations build() => RiderCalibrations.parse(ref.read(settingsProvider).riderCalibration);

  Future<void> _save(RiderCalibrations next) async {
    state = next;
    try {
      await ref.read(settingsProvider).setRiderCalibration(next.isEmpty ? null : next.encode());
    } catch (e, s) {
      logError('Kalibrierung merken', e, s);
    }
  }

  /// Zurück auf die Vorgaben eines Profils.
  Future<void> reset(RiderProfile p) => _save(state.without(p));

  /// Liest die Fahrten des Kontos und lernt je Profil neu; ein Profil
  /// ohne brauchbare Fahrt behält, was es hatte.
  Future<LearnResult> learn() async {
    final uid = ref.read(currentUserIdProvider);
    final samples = {for (final p in RiderProfile.values) p: <CalibSample>[]};
    final rides = {for (final p in RiderProfile.values) p: 0};
    var withoutArea = 0;
    if (uid == null) {
      return (
        rides: 0,
        usable: 0,
        withoutArea: 0,
        skipped: 0,
        ridesByProfile: rides,
        sectionsByProfile: const <RiderProfile, int>{}
      );
    }
    final all = await ref.read(rideStoreProvider).list(uid: uid);
    // Brauchbar: gemessen, mit Profil, lang genug, mit Höhen. Davon die
    // jüngsten [kCalibMaxRides].
    final usable = [
      for (final ride in all)
        if (!ride.planned &&
            RiderProfile.values.any((p) => p.name == ride.profile) &&
            ride.points.length >= kCalibWindow &&
            !ride.points.any((p) => p.altM == null))
          ride,
    ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final taken = usable.take(kCalibMaxRides).toList();
    List<StoredArea> areas;
    try {
      areas = await ref.read(storedAreasProvider.future);
    } catch (_) {
      areas = const [];
    }
    final store = ref.read(areaStoreProvider);
    final open = ref.read(areaArchiveOpenerProvider);
    final runner = ref.read(loopPlanRunnerFactoryProvider)();
    try {
      for (final ride in taken) {
        final profile = RiderProfile.values.firstWhere((p) => p.name == ride.profile);
        final line = [for (final p in ride.points) LatLng(p.lat, p.lng)];
        List<CalibSample> found;
        try {
          final read = await StallWatch.time('calib.graph', () => readRoadTiles(
            areas: areas,
            box: LatBox.of(line),
            open: (a) => open(store, a),
            marginM: kCalibCorridorM * 2,
            only: tilesAlong(line, kCalibCorridorM * 2),
            sourceKey: (a) => a.region,
          ));
          if (read.tilesFound == 0) {
            withoutArea++;
            continue;
          }
          // Keine Höhen und keine Trails: Eingeordnet wird nur die
          // Wegklasse unter der Linie, die Höhen sind die der Fahrt.
          final box = LatBox.of(line);
          await runner.build(GraphInput(roads: read.roads, lat0: (box.s + box.n) / 2));
          found = await StallWatch.time('calib.samples', () => runner.run(CalibJob(ride)));
        } catch (e, s) {
          logError('Fahrt zum Lernen einordnen', e, s);
          continue;
        }
        if (found.isEmpty) continue;
        samples[profile]!.addAll(found);
        rides[profile] = rides[profile]! + 1;
      }
    } finally {
      runner.dispose();
    }
    var next = state;
    final sections = <RiderProfile, int>{};
    for (final p in RiderProfile.values) {
      if (samples[p]!.isEmpty) continue;
      final c = calibrateFrom(samples[p]!, rides: rides[p]!);
      sections[p] = c.sections;
      next = next.withProfile(p, c);
    }
    await _save(next);
    return (
      rides: all.length,
      usable: usable.length,
      withoutArea: withoutArea,
      skipped: usable.length - taken.length,
      ridesByProfile: rides,
      sectionsByProfile: sections
    );
  }
}

/// Der Satz nach einem Lernlauf — EINER für das Fahrerprofil und den
/// GPX-Import, der danach gleich lernen lässt.
String learnResultText(AppLocalizations l, LearnResult r) {
  final learned = [
    for (final p in RiderProfile.values)
      if ((r.ridesByProfile[p] ?? 0) > 0)
        l.learnPart(p.label(l), r.ridesByProfile[p]!, r.sectionsByProfile[p] ?? 0),
  ];
  if (r.rides == 0) return l.learnNoRides;
  if (r.usable == 0) return l.learnNoUsable;
  final seen = r.usable - r.skipped;
  if (learned.isEmpty) return r.withoutArea == seen ? l.learnNoArea : l.learnNoClimb;
  final done = l.learnDone(learned.join(' · '));
  return r.skipped == 0 ? done : '$done ${l.learnSkipped(r.skipped, kCalibMaxRides)}';
}

final riderCalibrationsProvider =
    NotifierProvider<RiderCalibrationsNotifier, RiderCalibrations>(RiderCalibrationsNotifier.new);

/// Das Profil, mit dem die Planer rechnen: die Vorgaben, überlagert von
/// dem, was aus den Fahrten gelernt ist.
final calibratedRiderProvider = Provider.family<RiderParams, RiderProfile>(
    (ref, p) => CalibratedRider(p, ref.watch(riderCalibrationsProvider).of(p)));
