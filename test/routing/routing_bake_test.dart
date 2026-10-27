// Backen im Hintergrund (#380, Konzept-Routing 11.4 Weg C): Nach dem
// Speichern backt der Dienst die Stücke aller z13-Kacheln des Bereichs —
// die erste Planung danach backt nichts mehr. Er wartet, solange der
// Planer rechnet, lässt sich abbrechen und macht später dort weiter, wo
// er stand; die ganze Region backt er nicht.
import 'dart:async';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/connectivity.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/keep_alive/keep_alive.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/tile_store.dart';
import 'package:trailbuddy/features/routing/loop_plan_runner.dart';
import 'package:trailbuddy/features/routing/planning_graph.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/route_profile.dart' show WayClass;
import 'package:trailbuddy/features/routing/routing_bake.dart';
import 'package:trailbuddy/features/routing/routing_tile.dart';
import 'package:trailbuddy/features/trails/trail_providers.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_keep_alive.dart';
import '../fakes/graph_tiles.dart';

const _lat0 = 48.0, _lon0 = 9.0;
final _proj = FlatProjection(_lat0);
final _o = _proj.xy(const LatLng(_lat0, _lon0));

LatLng _m(double x, double y) => _proj.latLng(math.Point(_o.x + x, _o.y + y));

class _NoTrails extends TrailsNotifier {
  @override
  Future<List<Trail>> build() async => const [];
}

void main() {
  late MemoryTileStore tiles;
  late MemoryAreaStore areas;
  late int mapTiles;
  late List<(int, int)> roadsXY;
  late StoredArea area;
  var busy = false;
  late FakeKeepAlive keepAlive;
  late Future<void> Function({required bool planner}) pause;

  /// Ein Kreuz aus Forstwegen über 9 km, im Speicher der Region `dach`
  /// mit einem Bereich, der es deckt — mehrere Blöcke zu 4 × 4 Kacheln.
  Future<void> seed({AreaShape? shape}) async {
    final lines = [
      WayLine(cls: WayClass.forstweg, oneway: false, points: [_m(-9000, 0), _m(9000, 0)]),
      WayLine(cls: WayClass.forstweg, oneway: false, points: [_m(0, -9000), _m(0, 9000)]),
    ];
    final encoded = roadTilesOf(lines);
    mapTiles = encoded.length;
    roadsXY = [for (final r in encoded) (r.tile.x, r.tile.y)];
    await tiles.put('dach', TileLayer.map, [
      for (final r in encoded) StoreTile(13, r.tile.x, r.tile.y, r.bytes, '20261001'),
    ]);
    final box = LatBox.of([_m(-9500, -9500), _m(9500, 9500)]);
    area = StoredArea(
      id: 'a',
      name: 'Kreuz',
      bounds: AreaBounds(south: box.s, west: box.w, north: box.n, east: box.e),
      shape: shape,
      minZoom: 13,
      maxZoom: 13,
      build: '20261001',
      tiles: encoded.length,
      bytes: 1,
      savedAt: DateTime.utc(2026, 10, 1),
      format: kStoredAreaFormat,
    );
    await areas.saveIndex([area]);
  }

  setUp(() {
    tiles = MemoryTileStore();
    areas = MemoryAreaStore();
    busy = false;
    keepAlive = FakeKeepAlive();
    pause = ({required bool planner}) async {};
  });

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      areaStoreProvider.overrideWithValue(areas),
      tileStoreProvider.overrideWithValue(tiles),
      trailsProvider.overrideWith(_NoTrails.new),
      connectivityProvider.overrideWith((ref) => Stream.value(const [ConnectivityResult.none])),
      keepAliveProvider.overrideWithValue(keepAlive),
      loopPlanRunnerFactoryProvider.overrideWithValue(InlineLoopPlanRunner.new),
      routingBakePlannerBusyProvider.overrideWithValue(() => busy),
      routingBakePauseProvider.overrideWithValue(({required bool planner}) => pause(planner: planner)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Future<int> stored() async => (await tiles.index('dach', TileLayer.routing)).length;

  test('nach dem Speichern liegt jedes Stück — die erste Planung backt nichts mehr', () async {
    await seed();
    final c = container();
    final bake = c.read(routingBakeProvider.notifier);
    bake.bakeAreas([area]);
    expect(c.read(routingBakeProvider).running, isTrue);
    await bake.idle;
    expect(c.read(routingBakeProvider).running, isFalse);
    expect(keepAlive.starts, 1, reason: 'unter dem Vordergrunddienst');
    expect(keepAlive.titles.first, 'Preparing the planner');
    expect(keepAlive.running, isFalse, reason: 'danach wieder aus');
    expect(bake.baked, mapTiles, reason: 'jede Kachel mit Wegen einmal');
    expect(await stored(), mapTiles);
    final index = await tiles.index('dach', TileLayer.routing);
    expect(index.values.map((i) => i.build).toSet(), {pieceBuild(map: '20261001')});

    final loaded = await c.read(planningGraphLoaderProvider)(LatBox.of([_m(-4000, -4000), _m(4000, 4000)]),
        fillOnline: false);
    expect(loaded.input!.roads, isEmpty, reason: 'keine Wege-Kachel mehr gelesen');
    final report = await InlineLoopPlanRunner().build(loaded.input!);
    expect(report.baked, isEmpty, reason: 'nichts zu backen');
    expect(report.stitched, loaded.tilesFound);

    // Ein zweites Mal: alles frisch, nichts gebacken.
    bake.bakeAreas([area]);
    await bake.idle;
    expect(bake.baked, mapTiles);
  });

  test('dasselbe Stück wie beim Backen in der Planung', () async {
    await seed();
    final c = container();
    final bake = c.read(routingBakeProvider.notifier);
    bake.bakeAreas([area]);
    await bake.idle;
    final fromBake = {
      for (final (x, y) in roadsXY) (x, y): await tiles.read('dach', TileLayer.routing, 13, x, y),
    };
    // Dieselben Kacheln über den Lader gebacken (Weg B).
    await tiles.remove('dach', TileLayer.routing, [for (final (x, y) in roadsXY) tileIdOf((z: 13, x: x, y: y))]);
    final loaded = await c.read(planningGraphLoaderProvider)(LatBox.of([_m(-9000, -9000), _m(9000, 9000)]),
        fillOnline: false);
    final report = await InlineLoopPlanRunner().build(loaded.input!);
    final fromPlan = {for (final p in report.baked) (p.x, p.y): p.bytes};
    expect(fromPlan.keys.toSet(), fromBake.keys.toSet());
    for (final MapEntry(key: xy, value: bytes) in fromBake.entries) {
      final a = unpackPiece(bytes!)!, b = unpackPiece(fromPlan[xy]!)!;
      expect((a.nodes.length, a.edges.length, a.border.length), (b.nodes.length, b.edges.length, b.border.length),
          reason: 'Kachel $xy');
    }
  });

  test('wartet, solange der Planer rechnet', () async {
    await seed();
    busy = true;
    var waits = 0;
    final release = Completer<void>();
    pause = ({required bool planner}) async {
      if (!planner) return;
      waits++;
      if (waits == 3) {
        busy = false;
        release.complete();
      }
    };
    final c = container();
    final bake = c.read(routingBakeProvider.notifier);
    bake.bakeAreas([area]);
    await release.future;
    expect(bake.baked, 0, reason: 'nichts gebacken, solange der Planer rechnet');
    await bake.idle;
    expect(waits, 3);
    expect(bake.baked, mapTiles);
  });

  test('Abbrechen lässt liegen, was fertig ist — das nächste Mal geht es dort weiter', () async {
    await seed();
    final c = container();
    final bake = c.read(routingBakeProvider.notifier);
    var blocks = 0;
    pause = ({required bool planner}) async {
      if (!planner && ++blocks == 1) bake.cancel();
    };
    bake.bakeAreas([area]);
    await bake.idle;
    final first = bake.baked;
    expect(first, inExclusiveRange(0, mapTiles), reason: 'nach dem ersten Block abgebrochen');
    expect(await stored(), first);
    expect(c.read(routingBakeProvider).running, isFalse);

    blocks = 99;
    bake.bakeAreas([area]);
    await bake.idle;
    expect(bake.baked, mapTiles, reason: 'nur der Rest, nichts doppelt');
    expect(await stored(), mapTiles);
  });

  test('die ganze Region backt nicht im Hintergrund', () async {
    await seed(shape: const RegionShape(region: 'dach', bounds: AreaBounds(south: 47, west: 8, north: 49, east: 10)));
    final c = container();
    final bake = c.read(routingBakeProvider.notifier);
    bake.bakeAreas([area]);
    expect(c.read(routingBakeProvider).running, isFalse);
    await bake.idle;
    expect(await stored(), 0);
  });
}
