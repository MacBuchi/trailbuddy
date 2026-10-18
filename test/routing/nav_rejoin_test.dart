// „Zurück zur Route" rechnet im Rechen-Isolate des Planers, mit Rad und
// Stil der Route (#356 PR 9, Konzept-Routing 10.6): Der Controller baut
// keinen Graphen mehr selbst, er schickt dem Runner die Bytes und dann
// eine Aufgabe. Ein zweiter Tipp im selben Rahmen baut nicht neu; das
// Ende der Navigation gibt den Runner frei. Ohne Profil an der Route
// (eine Fahrt aus „Meine Fahrten") gelten das aktuelle Rad und die
// gemerkten Vorlieben.
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/connectivity.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/core/settings.dart';
import 'package:trailbuddy/features/keep_alive/keep_alive.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/tile_store.dart';
import 'package:trailbuddy/features/rides/road_index.dart' show RoadCoverage;
import 'package:trailbuddy/features/routing/graph_input.dart';
import 'package:trailbuddy/features/routing/loop_plan_runner.dart';
import 'package:trailbuddy/features/routing/loop_planner.dart';
import 'package:trailbuddy/features/routing/nav_providers.dart';
import 'package:trailbuddy/features/routing/nav_service.dart';
import 'package:trailbuddy/features/routing/planning_graph.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';
import 'package:trailbuddy/features/routing/trail_head_route.dart';

import '../fakes/fake_keep_alive.dart';
import '../fakes/fake_rides.dart';
import '../fakes/fake_settings.dart';
import '../fakes/graph_tiles.dart';

const _lat0 = 47.5, _lon0 = 11.5;
final _proj = FlatProjection(_lat0);
final _o = _proj.xy(const LatLng(_lat0, _lon0));

LatLng _m(double x, double y) => _proj.latLng(math.Point(_o.x + x, _o.y + y));

/// Rechnet an Ort und Stelle, zählt Bauten und merkt sich jede Aufgabe.
class _SpyRunner implements LoopPlanRunner {
  final _inline = InlineLoopPlanRunner();
  final jobs = <Object>[];
  var builds = 0;
  var disposed = 0;

  @override
  Future<GraphReport> build(GraphInput input, {void Function(double value)? onProgress}) {
    builds++;
    return _inline.build(input, onProgress: onProgress);
  }

  @override
  bool get hasGraph => _inline.hasGraph;

  @override
  Future<LoopPlan> plan(LoopRequest request, {void Function(double value)? onProgress}) => run(request);

  @override
  Future<R> run<R>(GraphJob<R> job) {
    jobs.add(job);
    return _inline.run(job);
  }

  @override
  void dispose() {
    disposed++;
    _inline.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SpyRunner spy;
  late List<LatBox> loaded;
  late FakeSettings settings;

  /// Ein Forstweg 2 km nach Norden; die Route liegt ab 1 km auf ihm.
  ProviderContainer container() {
    spy = _SpyRunner();
    loaded = [];
    final input = GraphInput(
      roads: roadTilesOf([
        WayLine(cls: WayClass.forstweg, oneway: false, points: [_m(0, 0), _m(0, 1000), _m(0, 2000)]),
      ]),
      lat0: _lat0,
    );
    final c = ProviderContainer(overrides: [
      settingsProvider.overrideWithValue(settings),
      navServiceBridgeProvider.overrideWithValue(FakeNavServiceBridge()),
      keepAliveProvider.overrideWithValue(FakeKeepAlive()),
      areaStoreProvider.overrideWithValue(MemoryAreaStore()),
      tileStoreProvider.overrideWithValue(MemoryTileStore()),
      connectivityProvider.overrideWith((ref) => Stream.value(const [ConnectivityResult.none])),
      loopPlanRunnerFactoryProvider.overrideWithValue(() => spy),
      planningGraphLoaderProvider.overrideWithValue((box, {fillOnline = true}) async {
        loaded.add(box);
        return PlanningGraph(input: input, coverage: RoadCoverage.complete, tilesFound: 1, tilesNeeded: 1);
      }),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() => settings = FakeSettings());

  final route = [_m(0, 1000), _m(0, 1500), _m(0, 2000)];

  test('rechnet drüben mit Rad und Stil der Route; ein zweiter Tipp im Rahmen baut nicht neu', () async {
    final c = container();
    final nav = c.read(navigationProvider.notifier);
    expect(nav.start(route, 'Test', profile: RiderProfile.ebike, routePrefs: const RoutePrefs(easy: true)), isTrue);
    // 300 m südlich des Anfangs: abseits.
    nav.onFix(_m(0, 700));
    await nav.rejoin();
    final session = c.read(navigationProvider)!;
    expect(session.rejoin, NavRejoin.shown);
    expect(session.rejoinLine!.first, _m(0, 700));
    expect(spy.builds, 1);
    final job = spy.jobs.single as TrailHeadJob;
    expect(job.profile.prefs.easy, isTrue, reason: 'der Stil der Route');
    expect(job.profile.climbTrackMPerH, RiderProfile.ebike.climbTrackMPerH, reason: 'das Rad der Route');
    // Der Rahmen hat Rand: Standort und Ziel liegen weit drin.
    expect(loaded.single.n - loaded.single.s, greaterThan(2 * kNavRejoinGraphMarginM / 111320));

    // Ein Stück weiter, noch im Rahmen: derselbe Graph.
    nav.onFix(_m(0, 750));
    await nav.rejoin();
    expect(spy.builds, 1);
    expect(spy.jobs, hasLength(2));
    expect(loaded, hasLength(1));

    nav.stop();
    expect(spy.disposed, 1);
  });

  test('ohne Profil an der Route: das aktuelle Rad und die gemerkten Vorlieben', () async {
    settings.riderProfile = 'bio';
    settings.loopPlannerPrefs = LoopPrefs.defaults(RiderProfile.bio)
        .copyWith(route: const RoutePrefs(avoidRoads: false), style: RouteMode.easy)
        .encode();
    final c = container();
    final nav = c.read(navigationProvider.notifier);
    nav.start(route, 'Fahrt');
    nav.onFix(_m(0, 700));
    await nav.rejoin();
    expect(c.read(navigationProvider)!.rejoin, NavRejoin.shown);
    final job = spy.jobs.single as TrailHeadJob;
    expect(job.profile.climbTrackMPerH, RiderProfile.bio.climbTrackMPerH);
    expect(job.profile.prefs.avoidRoads, isFalse, reason: 'die gemerkten Vorlieben');
    expect(job.profile.prefs.easy, isFalse, reason: 'der gemerkte Stil gilt dem Planer, nicht einer fremden Route');
  });

  test('ohne Kachel um Standort und Ziel: kein Bereich, und nichts gebaut', () async {
    final c = ProviderContainer(overrides: [
      settingsProvider.overrideWithValue(settings),
      navServiceBridgeProvider.overrideWithValue(FakeNavServiceBridge()),
      keepAliveProvider.overrideWithValue(FakeKeepAlive()),
      areaStoreProvider.overrideWithValue(MemoryAreaStore()),
      tileStoreProvider.overrideWithValue(MemoryTileStore()),
      connectivityProvider.overrideWith((ref) => Stream.value(const [ConnectivityResult.none])),
      loopPlanRunnerFactoryProvider.overrideWithValue(() => spy = _SpyRunner()),
      planningGraphLoaderProvider.overrideWithValue((box, {fillOnline = true}) async => PlanningGraph.none),
    ]);
    addTearDown(c.dispose);
    final nav = c.read(navigationProvider.notifier);
    nav.start(route, 'Test');
    nav.onFix(_m(0, 700));
    await nav.rejoin();
    expect(c.read(navigationProvider)!.rejoin, NavRejoin.noArea);
    expect(spy.builds, 0);
    expect(spy.jobs, isEmpty);
  });
}
