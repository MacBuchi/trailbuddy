// Die vorgebackenen Stücke durch den echten Lader (#380, Konzept-Routing
// 11.4 Weg B): Die erste Planung backt jede Kachel und legt die Stücke in
// den Kachelspeicher; die zweite in denselben Kacheln liest keine
// Wege-Kachel mehr und backt nichts — auch mit einem neuen Runner („nach
// dem Neustart"). Ändert sich eine Quellkachel, ist ihr Stück alt und wird
// ohne Netz neu gebacken; ein kaputtes Stück geht aus dem Speicher.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/connectivity.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/height_tiles.dart';
import 'package:trailbuddy/features/offline_areas/tile_store.dart';
import 'package:trailbuddy/features/routing/graph_input.dart';
import 'package:trailbuddy/features/routing/loop_plan_runner.dart';
import 'package:trailbuddy/features/routing/planning_graph.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/route_profile.dart' show WayClass;
import 'package:trailbuddy/features/routing/routing_pieces.dart';
import 'package:trailbuddy/features/routing/routing_tile.dart';
import 'package:trailbuddy/features/trails/trail_providers.dart';
import 'package:trailbuddy/models/trail.dart';

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
  late List<RoadTileBytesLike> roads;

  Future<void> putHeights(String build) async {
    final h = heightTilesOf([for (final r in roads) (z: 13, x: r.x, y: r.y)], (p) => 500 + (_proj.xy(p).y - _o.y) / 10);
    await tiles.put('dach', TileLayer.heights, [
      for (final r in roads) StoreTile(13, r.x, r.y, encodeHeightTile(h.tileAt(r.x, r.y)!.values), build),
    ]);
  }

  /// Ein Kreuz aus Forstwegen über mehrere Kacheln, im Speicher der Region
  /// `dach` mit einem Bereich, der es deckt.
  Future<void> seed({bool heights = false}) async {
    final lines = [
      WayLine(cls: WayClass.forstweg, oneway: false, points: [_m(-3000, 0), _m(3000, 0)]),
      WayLine(cls: WayClass.forstweg, oneway: false, points: [_m(0, -3000), _m(0, 3000)]),
    ];
    final encoded = roadTilesOf(lines);
    roads = [for (final r in encoded) (x: r.tile.x, y: r.tile.y)];
    await tiles.put('dach', TileLayer.map, [
      for (final r in encoded) StoreTile(13, r.tile.x, r.tile.y, r.bytes, '20261001'),
    ]);
    if (heights) await putHeights('20261009');
    final box = LatBox.of([_m(-3500, -3500), _m(3500, 3500)]);
    await areas.saveIndex([
      StoredArea(
        id: 'a',
        name: 'Kreuz',
        bounds: AreaBounds(south: box.s, west: box.w, north: box.n, east: box.e),
        minZoom: 13,
        maxZoom: 13,
        build: '20261001',
        tiles: encoded.length,
        bytes: 1,
        savedAt: DateTime.utc(2026, 10, 1),
        format: kStoredAreaFormat,
        heightsBuild: heights ? '20261009' : null,
        heightTiles: heights ? encoded.length : 0,
      ),
    ]);
  }

  setUp(() {
    tiles = MemoryTileStore();
    areas = MemoryAreaStore();
  });

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      areaStoreProvider.overrideWithValue(areas),
      tileStoreProvider.overrideWithValue(tiles),
      trailsProvider.overrideWith(_NoTrails.new),
      connectivityProvider.overrideWith((ref) => Stream.value(const [ConnectivityResult.none])),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  final box = LatBox.of([_m(-1000, -1000), _m(1000, 1000)]);

  /// Lädt, baut an Ort und Stelle und legt ab — wie der Controller.
  Future<(PlanningGraph, GraphReport)> plan(ProviderContainer c) async {
    final loaded = await c.read(planningGraphLoaderProvider)(box, fillOnline: false);
    final report = await InlineLoopPlanRunner().build(loaded.input!);
    await loaded.keep(report);
    return (loaded, report);
  }

  test('die erste Planung backt und legt ab, die zweite setzt nur zusammen — auch nach dem Neustart', () async {
    await seed();
    final c = container();
    final (first, firstReport) = await plan(c);
    expect(first.input!.bake, isTrue);
    expect(first.input!.pieces, isEmpty);
    expect(firstReport.baked, hasLength(first.tilesFound));
    final stored = await tiles.index('dach', TileLayer.routing);
    expect(stored, hasLength(first.tilesFound));
    expect(stored.values.map((i) => i.build).toSet(), {pieceBuild(map: '20261001')});

    final (second, secondReport) = await plan(c);
    expect(second.input!.roads, isEmpty, reason: 'keine Wege-Kachel gelesen');
    expect(second.input!.pieces, hasLength(first.tilesFound));
    expect(secondReport.baked, isEmpty, reason: 'nichts gebacken');
    expect((secondReport.nodes, secondReport.edges), (firstReport.nodes, firstReport.edges));
    expect(second.tilesFound, first.tilesFound, reason: 'Stücke zählen als gefunden');

    // „Nach dem Neustart": ein neuer Container über demselben Speicher.
    final (third, thirdReport) = await plan(container());
    expect(third.input!.roads, isEmpty);
    expect(thirdReport.baked, isEmpty);
  });

  test('eine geänderte Quellkachel macht das Stück alt — neu gebacken, ohne Netz', () async {
    await seed(heights: true);
    final c = container();
    final (first, report) = await plan(c);
    expect(report.edgesWithoutHeights, 0);
    expect((await tiles.index('dach', TileLayer.routing)).values.first.build,
        pieceBuild(map: '20261001', heights: '20261009'));
    // „Aktualisieren" bringt neue Höhen: Jedes Stück ist alt.
    await putHeights('20261020');
    final (second, again) = await plan(c);
    expect(second.input!.pieces, isEmpty);
    expect(again.baked, hasLength(first.tilesFound));
    expect({for (final i in (await tiles.index('dach', TileLayer.routing)).values) i.build},
        {pieceBuild(map: '20261001', heights: '20261020')});
  });

  test('ein Stück, das sich nicht lesen lässt, fehlt nur einmal — es geht aus dem Speicher', () async {
    await seed();
    final c = container();
    final (first, _) = await plan(c);
    final c0 = tileAt(_lat0, _lon0, 13);
    final r = roads.firstWhere((t) => (t.x, t.y) == (c0.x, c0.y));
    await tiles.put('dach', TileLayer.routing, [StoreTile(13, r.x, r.y, Uint8List.fromList([1, 2, 3]), pieceBuild(map: '20261001'))]);
    final (_, broken) = await plan(c);
    expect(broken.broken, [(r.x, r.y)]);
    expect((await tiles.index('dach', TileLayer.routing)), hasLength(first.tilesFound - 1));
    final (third, healed) = await plan(c);
    expect(healed.baked, hasLength(1), reason: 'die eine Kachel wird neu gebacken');
    expect(third.input!.roads, hasLength(1));
  });

  test('online ergänzt: das Stück gilt nur für die Sitzung, gehängt an die Bytes aus dem Zwischenspeicher', () async {
    final session = Expando<Uint8List>();
    final online = roadTilesOf([
      WayLine(cls: WayClass.forstweg, oneway: false, points: [_m(-500, 0), _m(500, 0)]),
    ]);
    final first = PieceLookup.none(session).split(online);
    expect(first.roads, hasLength(online.length), reason: 'beim ersten Mal wird gebacken');
    final lookup = PieceLookup.none(session)..split(online);
    final report = buildGraphFrom(GraphInput(roads: online, lat0: _lat0, bake: true)).report;
    await lookup.keep(report);
    final again = PieceLookup.none(session).split(online);
    expect(again.roads, isEmpty, reason: 'dieselben Bytes: das Stück der Sitzung');
    expect(again.pieces, hasLength(online.length));
    // Andere Bytes derselben Kachel (ein neuer Abruf): wieder backen.
    final copy = [for (final r in online) (tile: r.tile, bytes: Uint8List.fromList(r.bytes))];
    expect(PieceLookup.none(session).split(copy).roads, hasLength(online.length));
  });
}

typedef RoadTileBytesLike = ({int x, int y});
