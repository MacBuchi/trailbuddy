// Lernen aus den eigenen Fahrten (#158 Schritt 6): liest die Fahrten des
// Kontos vom Gerät, ordnet jede über den Wegegraphen ihrer Bereiche ein
// (`loadRoadGraph` mit `requireComplete: false` — eingeordnet wird, nicht
// geplant) und rechnet je Profil die gelernten Werte (`ride_calibration.dart`,
// pur). Gemerkt in `Settings.riderCalibration`; die Planer lesen das
// Profil über [calibratedRiderProvider].
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
import '../../data/providers.dart';
import '../offline_areas/area_providers.dart';
import '../offline_areas/area_store.dart';
import '../rides/ride_providers.dart';
import 'ride_calibration.dart';
import 'road_graph_loader.dart';
import 'route_profile.dart';

/// Was ein Lernlauf gesehen hat — für den Satz danach.
typedef LearnResult = ({
  int rides,
  int usable,
  int withoutArea,
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

  /// Liest alle Fahrten des Kontos und lernt je Profil neu; ein Profil
  /// ohne brauchbare Fahrt behält, was es hatte.
  Future<LearnResult> learn() async {
    final uid = ref.read(currentUserIdProvider);
    final samples = {for (final p in RiderProfile.values) p: <CalibSample>[]};
    final rides = {for (final p in RiderProfile.values) p: 0};
    var usable = 0, withoutArea = 0, total = 0;
    if (uid == null) {
      return (rides: 0, usable: 0, withoutArea: 0, ridesByProfile: rides, sectionsByProfile: const <RiderProfile, int>{});
    }
    final all = await ref.read(rideStoreProvider).list(uid: uid);
    List<StoredArea> areas;
    try {
      areas = await ref.read(storedAreasProvider.future);
    } catch (_) {
      areas = const [];
    }
    final store = ref.read(areaStoreProvider);
    final open = ref.read(areaArchiveOpenerProvider);
    for (final ride in all) {
      total++;
      final profile = RiderProfile.values.where((p) => p.name == ride.profile).firstOrNull;
      if (ride.planned || profile == null || ride.points.length < kCalibWindow) continue;
      if (ride.points.any((p) => p.altM == null)) continue;
      usable++;
      final box = LatBox.of([for (final p in ride.points) LatLng(p.lat, p.lng)]);
      RoadGraphLoadResult roads;
      try {
        roads = await loadRoadGraph(
          areas: areas,
          box: box,
          open: (a) => open(store, a),
          marginM: kCalibCorridorM * 2,
          requireComplete: false,
          sourceKey: (a) => a.region,
        );
      } catch (e, s) {
        logError('Wege zum Lernen lesen', e, s);
        continue;
      }
      if (roads.graph == null) {
        withoutArea++;
        continue;
      }
      final found = calibSamplesOf(ride, roads.graph);
      if (found.isEmpty) continue;
      samples[profile]!.addAll(found);
      rides[profile] = rides[profile]! + 1;
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
    return (rides: total, usable: usable, withoutArea: withoutArea, ridesByProfile: rides, sectionsByProfile: sections);
  }
}

/// Der Satz nach einem Lernlauf — EINER für das Fahrerprofil und den
/// GPX-Import, der danach gleich lernen lässt.
String learnResultText(LearnResult r) {
  final learned = [
    for (final p in RiderProfile.values)
      if ((r.ridesByProfile[p] ?? 0) > 0)
        '${p.label} aus ${r.ridesByProfile[p]} ${r.ridesByProfile[p] == 1 ? 'Fahrt' : 'Fahrten'} '
            '(${r.sectionsByProfile[p] ?? 0} Aufstiege)',
  ];
  if (r.rides == 0) {
    return 'Keine Fahrt auf diesem Gerät — gelernt wird aus deinen Aufzeichnungen '
        'und aus Fahrten, die du per GPX-Import übernommen hast.';
  }
  if (r.usable == 0) {
    return 'Keine Fahrt mit Profil und Höhen — Aufzeichnungen seit 0.70.0 tragen '
        'beides, ältere Fahrten übernimmst du per GPX-Import mit Profil.';
  }
  if (learned.isEmpty) {
    return r.withoutArea == r.usable
        ? 'Kein gespeicherter Bereich deckt deine Fahrten — ohne Wege lässt sich kein Aufstieg einordnen.'
        : 'Kein Aufstieg über 100 Höhenmeter am Stück gefunden — nichts zu lernen.';
  }
  return 'Gelernt: ${learned.join(' · ')}.';
}

final riderCalibrationsProvider =
    NotifierProvider<RiderCalibrationsNotifier, RiderCalibrations>(RiderCalibrationsNotifier.new);

/// Das Profil, mit dem die Planer rechnen: die Vorgaben, überlagert von
/// dem, was aus den Fahrten gelernt ist.
final calibratedRiderProvider = Provider.family<RiderParams, RiderProfile>(
    (ref, p) => CalibratedRider(p, ref.watch(riderCalibrationsProvider).of(p)));
