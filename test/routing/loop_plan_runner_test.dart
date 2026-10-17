// Der Rechen-Isolate des Planers (#188, #356 PR 8): baut den Graphen
// drüben aus Kachel-Bytes, rechnet dasselbe wie an Ort und Stelle, hält
// den Graphen, meldet Fehler und erholt sich nach dem Freigeben.
//
// Echte Isolate — deshalb `test`, nicht `testWidgets` (in der Zone mit
// falscher Uhr antwortet keiner; der Harness nimmt die Inline-Fassung).
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/offline_areas/height_tiles.dart';
import 'package:trailbuddy/features/routing/graph_input.dart';
import 'package:trailbuddy/features/routing/loop_plan_runner.dart';
import 'package:trailbuddy/features/routing/loop_plan_runner_io.dart';
import 'package:trailbuddy/features/routing/loop_planner.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';

import '../fakes/graph_tiles.dart';

const _lat0 = 47.5, _lon0 = 11.5;
final _proj = FlatProjection(_lat0);
final _o = _proj.xy(const LatLng(_lat0, _lon0));

List<LatLng> _m(List<(double, double)> xy) => [for (final (x, y) in xy) _proj.latLng(math.Point(_o.x + x, _o.y + y))];

/// Das Quadrat aus `loop_planner_test.dart`: 1 km Forstweg je Kante,
/// nach Norden 100 hm hinauf — als Kacheln, wie der Lader sie liest, mit
/// einer Höhenfläche, die 100 m je km steigt.
GraphInput _square() {
  WayLine way(List<(double, double)> xy) => WayLine(cls: WayClass.forstweg, oneway: false, points: _m(xy));
  final roads = roadTilesOf([
    way([(0, 0), (0, 1000)]),
    way([(0, 1000), (1000, 1000)]),
    way([(1000, 1000), (1000, 0)]),
    way([(1000, 0), (0, 0)]),
  ]);
  return GraphInput(
    roads: roads,
    heights: heightTilesOf([for (final r in roads) r.tile], (p) => 1000 + (_proj.xy(p).y - _o.y) / 10),
    lat0: _lat0,
  );
}

PoolTrail _trail(String id, (double, double) from, (double, double) to) => PoolTrail(
      id: id,
      name: id,
      points: _m([from, ((from.$1 + to.$1) / 2, (from.$2 + to.$2) / 2), to]),
      lengthM: 1000,
      grade: 2,
      lossM: 100,
    );

LoopRequest _request({RiderParams profile = RiderProfile.bio}) => LoopRequest(
      start: _m([(5, 0)]).single,
      profile: profile,
      budget: const LoopBudget(timeS: 3 * 3600, climbM: 800, hikingM: 2000),
      pool: [_trail('A', (10, 990), (990, 10)), _trail('B', (1010, 990), (1010, 10))],
      searchBudget: const Duration(milliseconds: 50),
    );

/// Ein Profil, das beim ersten Blick der Suche wirft — sendbar, weil es
/// nur eine gewöhnliche Klasse ist.
class _BrokenRider implements RiderParams {
  const _BrokenRider();
  @override
  RiderProfile get profile => RiderProfile.bio;
  @override
  double get climbTrackMPerH => throw StateError('kaputtes Profil');
  @override
  double get climbPathMPerH => throw StateError('kaputtes Profil');
  @override
  double get pushRateMPerH => throw StateError('kaputtes Profil');
  @override
  double get vFlatKmh => throw StateError('kaputtes Profil');
  @override
  double get vPathUpKmh => throw StateError('kaputtes Profil');
  @override
  double get vPushKmh => throw StateError('kaputtes Profil');
  @override
  double get vDownKmh => throw StateError('kaputtes Profil');
  @override
  double get pathUpFactor => throw StateError('kaputtes Profil');
  @override
  double get pathDownFactor => throw StateError('kaputtes Profil');
  @override
  double get budgetClimbM => throw StateError('kaputtes Profil');
  @override
  RoutePrefs get prefs => const RoutePrefs();
}

/// Eine Aufgabe, die nur sagt, wo sie lief — und wie viele Kanten der
/// Graph dort hat.
class _WhereJob implements GraphJob<(String, int)> {
  const _WhereJob();

  @override
  (String, int) runOn(RoadGraph g, LoopSearchCache cache) => (Isolate.current.debugName ?? '', g.edges.length);
}

void main() {
  test('die Eingabe trägt das Quadrat: vier Kanten, Höhen aus dem Raster', () async {
    final built = buildGraphFrom(_square());
    expect(built.graph.edges, hasLength(4));
    expect(built.report.edgesWithoutHeights, 0);
    final up = built.graph.edges.where((e) => e.gain > 90 && e.loss < 5);
    final down = built.graph.edges.where((e) => e.loss > 90 && e.gain < 5);
    expect(up, hasLength(1), reason: 'die Westkante steigt nach Norden');
    expect(down, hasLength(1), reason: 'die Ostkante fällt nach Süden');
  });

  test('baut drüben und rechnet dasselbe wie an Ort und Stelle', () async {
    final inline = InlineLoopPlanRunner();
    final inlineReport = await inline.build(_square());
    final want = await inline.plan(_request());
    expect(want.outcome, LoopOutcome.ok);
    final runner = IsolateLoopPlanRunner();
    addTearDown(runner.dispose);
    expect(runner.hasGraph, isFalse);
    final report = await runner.build(_square());
    expect(runner.hasGraph, isTrue);
    expect((report.nodes, report.edges), (inlineReport.nodes, inlineReport.edges));
    expect(report.builtIn, isNot(Isolate.current.debugName), reason: 'gebaut im Rechen-Isolate, nicht hier');
    expect(inlineReport.builtIn, 'inline');
    final plan = await runner.plan(_request());
    expect(plan.outcome, LoopOutcome.ok);
    expect(plan.stops.map((s) => s.trail.id), want.stops.map((s) => s.trail.id));
    expect(plan.summary!.trailM, want.summary!.trailM);
    expect(plan.summary!.gainM, want.summary!.gainM);
    expect(plan.summary!.timeS, want.summary!.timeS);
    expect(plan.points.length, want.points.length);
  });

  test('#356 PR 9: jede Aufgabe läuft drüben, auf dem gehaltenen Graphen', () async {
    final runner = IsolateLoopPlanRunner();
    addTearDown(runner.dispose);
    await expectLater(runner.run(const _WhereJob()), throwsStateError, reason: 'ohne Bau kein Graph');
    await runner.build(_square());
    final (where, edges) = await runner.run(const _WhereJob());
    expect(where, 'loop-planner');
    expect(where, isNot(Isolate.current.debugName));
    expect(edges, 4);
    final inline = InlineLoopPlanRunner();
    await inline.build(_square());
    expect(await inline.run(const _WhereJob()), (Isolate.current.debugName ?? '', 4));
  });

  test('ohne Bau keine Rechnung; ein zweiter Bau ersetzt den ersten', () async {
    final runner = IsolateLoopPlanRunner();
    addTearDown(runner.dispose);
    expect(() => runner.plan(_request()), throwsStateError);
    await runner.build(_square());
    await runner.plan(_request());
    await runner.plan(_request());
    expect(runner.builds, 1);
    await runner.build(_square());
    expect(runner.builds, 2);
    expect((await runner.plan(_request())).outcome, LoopOutcome.ok);
  });

  test('ein Fehler in der Rechnung kommt als Fehler an, der Isolate rechnet weiter', () async {
    final runner = IsolateLoopPlanRunner();
    addTearDown(runner.dispose);
    await runner.build(_square());
    await expectLater(runner.plan(_request(profile: const _BrokenRider())),
        throwsA(isA<RemoteError>().having((e) => e.toString(), 'Meldung', contains('kaputtes Profil'))));
    expect(runner.hasGraph, isTrue);
    final plan = await runner.plan(_request());
    expect(plan.outcome, LoopOutcome.ok);
    expect(runner.builds, 1);
  });

  test('ein kaputter Eingang lässt den Bau scheitern, nicht den Isolate', () async {
    final runner = IsolateLoopPlanRunner();
    addTearDown(runner.dispose);
    // Eine Höhenkachel ohne Raster: Die erste Probe greift ins Leere.
    final square = _square();
    final broken = GraphInput(
        roads: square.roads,
        heights: HeightTiles({for (final k in square.heights!.tiles.keys) k: HeightTile(Int16List(1))}),
        lat0: _lat0);
    await expectLater(runner.build(broken), throwsA(isA<RemoteError>()));
    expect(runner.hasGraph, isFalse);
    await runner.build(_square());
    expect((await runner.plan(_request())).outcome, LoopOutcome.ok);
  });

  test('Freigeben während des Starts lässt den Bau scheitern, der nächste legt neu an', () async {
    final runner = IsolateLoopPlanRunner();
    final pending = runner.build(_square());
    runner.dispose();
    await expectLater(pending, throwsA(isA<StateError>()));
    await runner.build(_square());
    expect((await runner.plan(_request())).outcome, LoopOutcome.ok);
    runner.dispose();
  });

  test('Freigeben nach einem Bau: der Graph ist weg, der nächste Bau legt neu an', () async {
    final runner = IsolateLoopPlanRunner();
    await runner.build(_square());
    runner.dispose();
    expect(runner.hasGraph, isFalse);
    expect(() => runner.plan(_request()), throwsStateError);
    await runner.build(_square());
    expect((await runner.plan(_request())).outcome, LoopOutcome.ok);
    expect(runner.builds, 2);
    runner.dispose();
  });

  test('auf dem Telefon ist der Planer-Runner der Rechen-Isolate', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final runner = container.read(loopPlanRunnerFactoryProvider)();
    addTearDown(runner.dispose);
    expect(runner, isA<IsolateLoopPlanRunner>());
  });
}
