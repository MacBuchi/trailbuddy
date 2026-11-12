// Das Handy für die Gespräche mit der Uhr (#509, Prüfleiter S3): EIN
// Container mit allem, was Navigation, freie Fahrt und die Fahrten der Uhr
// brauchen — `watch_talks_test.dart` spielt den Katalog dagegen,
// `watch_channel_test.dart` die gemessenen Feldbefunde. Alles erfunden:
// die Route nach Norden um 47,5/11,5, ein Trail bei 48/9.
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/connectivity.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/core/settings.dart';
import 'package:trailbuddy/data/providers.dart';
import 'package:trailbuddy/features/garmin/garmin_bridge.dart';
import 'package:trailbuddy/features/garmin/watch_branches.dart' show WatchBranch;
import 'package:trailbuddy/features/garmin/watch_free.dart' show lineLengthM;
import 'package:trailbuddy/features/garmin/watch_providers.dart';
import 'package:trailbuddy/features/garmin/watch_ride_inbox.dart';
import 'package:trailbuddy/features/keep_alive/keep_alive.dart';
import 'package:trailbuddy/features/offline_areas/area_providers.dart' show areaHeightReaderProvider;
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/height_tiles.dart' show HeightReader, MemoryHeightSource;
import 'package:trailbuddy/features/offline_areas/tile_store.dart';
import 'package:trailbuddy/features/rides/airtime_live.dart';
import 'package:trailbuddy/features/rides/ride_providers.dart';
import 'package:trailbuddy/features/rides/ride_service.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/features/rides/road_index.dart' show RoadCoverage;
import 'package:trailbuddy/features/rides/sensor_fusion.dart' show JumpEvent;
import 'package:trailbuddy/features/rides/trail_values.dart' show AirtimeLog;
import 'package:trailbuddy/features/routing/graph_input.dart';
import 'package:trailbuddy/features/routing/loop_plan_runner.dart';
import 'package:trailbuddy/features/routing/nav_providers.dart';
import 'package:trailbuddy/features/routing/nav_service.dart';
import 'package:trailbuddy/features/routing/planning_graph.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/route_profile.dart' show WayClass;
import 'package:trailbuddy/features/routing/route_progress.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart' show RecordingSource;
import 'package:trailbuddy/features/trails/trail_providers.dart' show trailRepositoryProvider;
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_garmin.dart';
import '../fakes/fake_heights.dart';
import '../fakes/fake_keep_alive.dart';
import '../fakes/fake_rides.dart';
import '../fakes/fake_settings.dart';
import '../fakes/fake_trails.dart' show FakeTrailRepository;
import '../fakes/graph_tiles.dart';

const _lat0 = 47.5, _lon0 = 11.5;
final _proj = FlatProjection(_lat0);
final _o = _proj.xy(const LatLng(_lat0, _lon0));

/// [x] m nach Osten, [y] m nach Norden von 47,5/11,5.
LatLng phoneM(double x, double y) => _proj.latLng(math.Point(_o.x + x, _o.y + y));

WayLine _way(List<(double, double)> xy) =>
    WayLine(cls: WayClass.forstweg, oneway: false, points: [for (final (x, y) in xy) phoneM(x, y)]);

/// Die Route der Navigation: nach Norden, leicht geknickt — eine gerade
/// Linie fiele beim Vereinfachen auf zwei Punkte, und „halb so groß“ hätte
/// dieselbe Kennung.
final phoneRoute = [phoneM(0, 0), phoneM(40, 500), phoneM(0, 1000), phoneM(40, 1500), phoneM(0, 2000), phoneM(0, 2500)];
/// Eine lange Route, die zwei Stücke braucht (`kWatchPartInts`): 1200
/// Punkte im Zickzack nach Norden, 30 m hin und her — das Vereinfachen
/// lässt die Zacken stehen.
List<LatLng> longPhoneRoute() => [for (var i = 0; i < 1200; i++) phoneM(i.isEven ? 0 : 30, i * 2.0)];

final phoneSections = NavSections([
  const NavTrailSection(startM: 1500, endM: 2500, trailId: 't', name: 'Talweg', grade: 2),
]);

/// Ein Trail für die freie Fahrt: 48,000 → 48,010 auf 9,000 (≈ 1,1 km).
Trail freeTrail() {
  final pts = [for (var i = 0; i < 11; i++) LatLng(48.0 + 0.001 * i, 9.0)];
  return Trail(
    id: 'nah',
    myId: 'me',
    details: [const TrailDetails(trailId: 'nah', userId: 'me', name: 'Nah')],
    recordings: [
      TrailRecording(
        id: 'rec-nah',
        trailId: 'nah',
        userId: 'me',
        source: RecordingSource.import,
        recordedAt: null,
        reversed: false,
        quality: 0.9,
        createdAt: DateTime(2026, 1, 1),
        points: pts,
        lengthM: lineLengthM(pts),
        ele: List<double>.filled(pts.length, 600),
      ),
    ],
  );
}

/// Ein Sprung liegt vor: Die Bestwerte gehen nach dem „gespeichert“ hin.
class _Jumped extends AirtimeLiveNotifier {
  @override
  AirtimeLiveState build() {
    super.build();
    return const AirtimeLiveState(
        log: AirtimeLog(events: [
      JumpEvent(startUs: 1000000, duration: Duration(milliseconds: 600), landingG: 2.5, upright: true, plausible: true),
    ]));
  }
}

/// Das Handy mit Uhr: Navigation (Graph mit zwei parallelen Wegen für das
/// Umplanen ab der Uhr), freie Fahrt, die Fahrten der Uhr.
class WatchPhone {
  WatchPhone({FakeGarminBridge? bridge, this.trails = const [], this.jumped = false, this.branches})
      : bridge = bridge ?? FakeGarminBridge.connected();

  final FakeGarminBridge bridge;
  final List<Trail> trails;
  final bool jumped;

  /// Die Abzweigungen; ab Werk gleich leer — ein Test setzt eine langsame.
  final Future<List<WatchBranch>> Function(List<LatLng> line)? branches;

  final settings = FakeSettings();
  final store = FakeRideStore();
  final fix = FakeRideFix();
  final service = FakeRideService();
  late final ProviderContainer c;

  /// Den Container bauen, den Abgleich mit der Uhr und das Hören auf ihre
  /// Fahrten anwerfen.
  Future<void> open() async {
    final input = GraphInput(
      roads: roadTilesOf([
        _way([(0, 0), (0, 1500), (0, 2500)]),
        _way([(300, 0), (300, 1500), (300, 2500)]),
        _way([(0, 0), (300, 0)]),
        _way([(300, 1500), (0, 1500)]),
      ]),
      lat0: _lat0,
    );
    final repo = FakeTrailRepository(myId: () => 'me')
      ..recordings.addAll([for (final t in trails) ...t.recordings])
      ..details.addAll([for (final t in trails) ...t.details]);
    store.uid = 'me';
    c = ProviderContainer(overrides: [
      garminBridgeProvider.overrideWithValue(bridge),
      settingsProvider.overrideWithValue(settings),
      currentUserIdProvider.overrideWithValue('me'),
      // Navigation und Umplanen.
      navServiceBridgeProvider.overrideWithValue(FakeNavServiceBridge()),
      keepAliveProvider.overrideWithValue(FakeKeepAlive()),
      areaStoreProvider.overrideWithValue(MemoryAreaStore()),
      tileStoreProvider.overrideWithValue(MemoryTileStore()),
      connectivityProvider.overrideWith((ref) => Stream.value(const [ConnectivityResult.none])),
      noConnectivityProvider.overrideWithValue(true),
      loopPlanRunnerFactoryProvider.overrideWithValue(InlineLoopPlanRunner.new),
      planningGraphLoaderProvider.overrideWithValue((box, {fillOnline = true}) async =>
          PlanningGraph(input: input, coverage: RoadCoverage.complete, tilesFound: 1, tilesNeeded: 1)),
      areaHeightReaderProvider.overrideWith((ref) async => HeightReader([MemoryHeightSource(slopeHeightTiles())])),
      watchBranchesLoaderProvider.overrideWithValue(branches ?? (line) async => const <WatchBranch>[]),
      // Freie Fahrt.
      trailRepositoryProvider.overrideWithValue(repo),
      // Die Fahrten der Uhr und die Aufzeichnung auf ihr START.
      rideStoreProvider.overrideWithValue(store),
      rideFixProvider.overrideWithValue(fix.call),
      rideServiceBridgeProvider.overrideWithValue(FakeRideServiceBridge()),
      rideServiceProvider.overrideWithValue(service),
      ridePermissionProvider.overrideWithValue(() async => null),
      if (jumped) airtimeLiveProvider.overrideWith(_Jumped.new),
    ]);
    c.read(watchSyncProvider);
    await c.read(watchRideInboxProvider.notifier).start();
  }

  /// Navigation mit „Auf der Uhr zeigen“, ein Fix auf der Route.
  void navigate({List<LatLng>? route}) {
    c.read(watchSyncProvider.notifier).follow(true);
    final nav = c.read(navigationProvider.notifier);
    nav.start(route ?? phoneRoute, 'Hausrunde', sections: phoneSections);
    nav.onFix(phoneM(0, 100), headingDeg: 0, speedMps: 5);
  }

  void endNavigation() => c.read(navigationProvider.notifier).stop();

  /// Alles, was das Handy sendete, der Reihe nach.
  List<Map<String, Object>> get sent => [for (final batch in bridge.sent) ...batch];

  WatchSyncState get sync => c.read(watchSyncProvider);
}

/// [n] Punkte einer erfundenen Fahrt der Uhr, alle 5 s, am Äquator.
List<(int, int, int, int, int)> watchRidePoints(int n, {int t0 = 1700000000}) =>
    [for (var i = 0; i < n; i++) (i * 250, 100, t0 + i * 5, 4000 + i * 5, 0)];

RidePoint ridePointAt(int s) =>
    RidePoint(lat: 0, lng: 0, at: DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true), accuracyM: 5);
