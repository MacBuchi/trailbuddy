// Die Suche: begrenzter Dijkstra, A* zum Ziel, Einbahn, Klassenaufschlag
// (der Forstweg gewinnt gegen die kürzere Bundesstraße), Budgetgrenze,
// und die Pfad-Zusammenfassung in beide Richtungen — dazu der Graph aus
// Bereichen über `loadRoadGraph` (vollständig, teilweise, gar nicht).
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/map/pmtiles_tile_provider.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/height_tiles.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';
import 'package:trailbuddy/features/rides/road_index.dart' show RoadCoverage;
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/road_graph_loader.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';
import 'package:trailbuddy/features/routing/route_search.dart';

import '../fakes/fake_tiles.dart';

/// Meter → Grad über DIESELBE Projektion wie der Graph, sonst sind
/// „1000 m" im Test 998,9 m im Graphen.
List<LatLng> _m(List<(double, double)> xy, {double lat0 = 47.5, double lon0 = 11.5}) {
  final proj = FlatProjection(lat0);
  final o = proj.xy(LatLng(lat0, lon0));
  return [for (final (x, y) in xy) proj.latLng(math.Point(o.x + x, o.y + y))];
}

WayLine _way(List<(double, double)> xy, {WayClass cls = WayClass.forstweg, bool oneway = false}) =>
    WayLine(cls: cls, oneway: oneway, points: _m(xy));

void main() {
  const bio = RiderProfile.bio;

  test('der Forstweg gewinnt gegen die kürzere Bundesstraße, und der Pfad ist die Linie', () {
    // Start (0,0) → Ziel (1000,0): Bundesstraße direkt (1 km, ×4), Forstweg
    // über (500, 300) (≈ 1,17 km, ×1).
    final g = buildRoadGraph([
      _way([(0, 0), (1000, 0)], cls: WayClass.bundesstrasse),
      _way([(0, 0), (500, 300), (1000, 0)]),
    ], lat0: 47.5).graph;
    final src = g.attach(_m([(0, 0)]).single)!, dst = g.attach(_m([(1000, 0)]).single)!;
    final r = shortestPath(g, src, dst, bio)!;
    expect(g.edges[r.edges.single].cls, WayClass.forstweg);
    final s = summarizePath(g, r.edges, src, bio);
    expect(s.lengthM, closeTo(2 * math.sqrt(500 * 500 + 300 * 300), 1));
    expect(s.mix.keys, [WayClass.forstweg]);
    expect(s.points.first.longitude, closeTo(_m([(0, 0)]).single.longitude, 1e-9));
    expect(s.points.last.longitude, closeTo(_m([(1000, 0)]).single.longitude, 1e-9));
    expect(s.heightsComplete, isFalse, reason: 'keine Höhen gelesen');
    expect(s.hikingM, 0);
    // Zeit = Strecke / 15 km/h ohne Höhen.
    expect(s.timeS, closeTo(s.lengthM / (15 / 3.6), 1e-6));
  });

  test('Steilaufschlag (#194): die steile Abkürzung verliert, bergab und auf dem Uphill-Trail nicht', () {
    // (0,0) → (0,600): direkt 600 m Forstweg mit 140 hm, davon 60 über 15 %
    // — gewichtet (#188) jeder der 140 hm mit seinen 23 %, rund 150;
    // der Umweg über (400, 300) hat 1 000 m und 140 hm, nirgends steil.
    final g = buildRoadGraph([
      _way([(0, 0), (0, 600)]),
      _way([(0, 0), (400, 300), (0, 600)]),
    ], lat0: 47.5).graph;
    final a = g.attach(_m([(0, 0)]).single)!, b = g.attach(_m([(0, 600)]).single)!;
    final direct = g.edges.indexWhere((e) => e.points.length == 2);
    for (final (i, e) in g.edges.indexed) {
      final up = e.a == a; // a → b ist bergauf
      e
        ..gain = up ? (i == direct ? 140 : 140 * e.length / 1000) : 0
        ..loss = up ? 0 : (i == direct ? 140 : 140 * e.length / 1000)
        ..hasHeights = true;
      if (i == direct) {
        if (up) {
          e
            ..steepUp = 60
            ..steepWUp = 140 * steepWeightAt(140 / 600);
        } else {
          e
            ..steepDown = 60
            ..steepWDown = 140 * steepWeightAt(140 / 600);
        }
      }
    }
    final up = shortestPath(g, a, b, bio)!;
    expect(up.edges, isNot([direct]), reason: '140 hm mit 23 % kosten gut eine Stunde — mehr als 400 m Umweg');
    expect(summarizePath(g, up.edges, a, bio).steepM, 0);
    expect(shortestPath(g, b, a, bio)!.edges, [direct], reason: 'bergab ist die Steilheit kein Aufschlag');

    // Ohne die steilen Meter wäre die Abkürzung die Wahl.
    final e = g.edges[direct];
    final steep = (e.steepWUp, e.steepWDown);
    e
      ..steepWUp = 0
      ..steepWDown = 0;
    expect(shortestPath(g, a, b, bio)!.edges, [direct]);
    // Mit „Steile Rampen: egal" (#188) bleibt ein Drittel — für 23 %
    // immer noch zu viel, die Abkürzung verliert weiter.
    e
      ..steepWUp = steep.$1
      ..steepWDown = steep.$2;
    expect(shortestPath(g, a, b, bio.withPrefs(const RoutePrefs(avoidSteep: false)))!.edges, isNot([direct]));

    // Als Uphill-Trail gewollt: kein Aufschlag, die Abkürzung ist der Weg.
    e.trail = const EdgeTrail(id: 'up', name: 'Uphill', connector: true);
    final viaTrail = shortestPath(g, a, b, bio)!;
    expect(viaTrail.edges, [direct]);
    expect(summarizePath(g, viaTrail.edges, a, bio).steepM, 0, reason: 'der Uphill-Trail zählt nicht als steil');
  });

  test('Stufen bergauf (#210): die kurze Treppe verliert gegen 900 m Forstweg, bergab nicht', () {
    // (0,0) → (0,20): 20 m Stufen mit 4 hm, oder 900 m Forstweg über
    // (450, 10) mit denselben 4 hm. Ohne Aufschlag 216 s gegen 248 s —
    // die Treppe gewänne; mit ihm 276 s.
    final g = buildRoadGraph([
      _way([(0, 0), (0, 20)], cls: WayClass.stufen),
      _way([(0, 0), (450, 10), (0, 20)]),
    ], lat0: 47.5).graph;
    final a = g.attach(_m([(0, 0)]).single)!, b = g.attach(_m([(0, 20)]).single)!;
    final flight = g.edges.indexWhere((e) => e.cls == WayClass.stufen);
    for (final e in g.edges) {
      final up = e.a == a; // a → b ist bergauf, beide Wege 4 hm
      e
        ..gain = up ? 4 : 0
        ..loss = up ? 0 : 4
        ..hasHeights = true;
    }
    expect(edgeCostFrom(g, flight, a, bio).cost, closeTo(276.0, 1e-6));
    expect(shortestPath(g, a, b, bio)!.edges, isNot(contains(flight)), reason: 'hinauf wird getragen');
    expect(shortestPath(g, b, a, bio)!.edges, [flight], reason: 'hinunter kein Aufschlag');

    // Geteilt (ein Trailkopf auf der Treppe) bleibt es EIN Aufschlag.
    final mid = g.splitEdge(flight, 0, _m([(0, 10)]).single);
    final halves = [for (final (i, e) in g.edges.indexed) if (e.cls == WayClass.stufen) i];
    expect(halves, hasLength(2));
    expect(g.edges[halves[0]].carry + g.edges[halves[1]].carry, closeTo(1.0, 1e-9));
    expect(edgeCostFrom(g, halves[0], a, bio).cost + edgeCostFrom(g, halves[1], mid, bio).cost, closeTo(276.0, 1e-6),
        reason: 'die Hälften kosten zusammen, was die Treppe kostete');
    expect(shortestPath(g, a, b, bio)!.edges.every((i) => g.edges[i].cls == WayClass.forstweg), isTrue);
  });

  test('der Satz zu steilen Stücken erst ab ein paar Höhenmetern (#194)', () {
    expect(steepNote(0), isNull);
    expect(steepNote(kSteepNoteMinM - 0.1), isNull);
    expect(steepNote(kSteepNoteMinM), contains('über 15 %'));
  });

  test('Einbahn: hin über die Straße, zurück nur über den Umweg', () {
    final g = buildRoadGraph([
      _way([(0, 0), (1000, 0)], cls: WayClass.nebenstrasse, oneway: true),
      _way([(0, 0), (500, 400), (1000, 0)]),
    ], lat0: 47.5).graph;
    final a = g.attach(_m([(0, 0)]).single)!, b = g.attach(_m([(1000, 0)]).single)!;
    expect(g.edges[shortestPath(g, a, b, bio)!.edges.single].cls, WayClass.nebenstrasse);
    expect(g.edges[shortestPath(g, b, a, bio)!.edges.single].cls, WayClass.forstweg);
  });

  test('Vorlieben (#188): „Straßen egal" nimmt die kürzere Hauptstraße, „meiden" den Forstweg', () {
    // Hauptstraße direkt 1 km (×2,5, egal ×1,525), Forstweg über (500, 300)
    // ≈ 1,17 km (×1).
    final g = buildRoadGraph([
      _way([(0, 0), (1000, 0)], cls: WayClass.hauptstrasse),
      _way([(0, 0), (500, 300), (1000, 0)]),
    ], lat0: 47.5).graph;
    final src = g.attach(_m([(0, 0)]).single)!, dst = g.attach(_m([(1000, 0)]).single)!;
    expect(g.edges[shortestPath(g, src, dst, bio)!.edges.single].cls, WayClass.forstweg);
    final any = bio.withPrefs(const RoutePrefs(avoidRoads: false));
    expect(g.edges[shortestPath(g, src, dst, any)!.edges.single].cls, WayClass.forstweg,
        reason: 'egal ist nicht null: 1,525 × 1 km sind mehr als 1,17 km Forstweg');
    // Bei 1,7 km Forstweg kippt es (1,525 km gegen 1,72 km, meiden 2,5 km).
    final g2 = buildRoadGraph([
      _way([(0, 0), (1000, 0)], cls: WayClass.hauptstrasse),
      _way([(0, 0), (500, 700), (1000, 0)]),
    ], lat0: 47.5).graph;
    final s2 = g2.attach(_m([(0, 0)]).single)!, d2 = g2.attach(_m([(1000, 0)]).single)!;
    expect(g2.edges[shortestPath(g2, s2, d2, bio)!.edges.single].cls, WayClass.forstweg);
    expect(g2.edges[shortestPath(g2, s2, d2, any)!.edges.single].cls, WayClass.hauptstrasse);
  });

  test('Verschenkte Höhe (#188) kostet auf einer Verbindung, auf einem Trail nicht', () {
    final g = buildRoadGraph([_way([(0, 0), (1000, 0)])], lat0: 47.5).graph;
    final e = g.edges.single
      ..gain = 0
      ..loss = 100
      ..hasHeights = true;
    final from = e.a; // in Kantenrichtung: 100 hm bergab
    final plain = 1000 / (25 / 3.6);
    expect(edgeCostFrom(g, 0, from, bio).cost, closeTo(plain + 100 * kDescentCost * 3600 / 450, 1e-6));
    e.trail = const EdgeTrail(id: 't', name: 'Abfahrt', connector: false);
    expect(edgeCostFrom(g, 0, from, bio).cost, closeTo(plain, 1e-6), reason: 'dafür ist der Trail da');
  });

  test('das Budget begrenzt die Reichweite; Anstieg wird mitgezählt', () {
    final g = buildRoadGraph([
      _way([(0, 0), (1000, 0), (2000, 0), (3000, 0)]),
    ], lat0: 47.5).graph;
    final split = [for (final x in [0, 1000, 2000, 3000]) g.attach(_m([(x.toDouble(), 0)]).single)!];
    for (final e in g.edges) {
      e
        ..gain = 100
        ..loss = 0
        ..hasHeights = true;
    }
    // Je Kante 1 km und 100 hm: 1040 s. Mit 2500 s Budget sind zwei
    // Kanten drin, die dritte nicht.
    final r = dijkstra(g, split[0], bio, limit: 2500);
    expect(r.reached(split[2]), isTrue);
    expect(r.reached(split[3]), isFalse);
    expect(r.climb[split[2]], closeTo(200, 1e-9));
    expect(r.dist[split[2]], closeTo(2080, 1e-6));
    // Zurück: bergab, Strecke mit 25 km/h, dazu kostet jeder verschenkte
    // Höhenmeter 0,3 seiner Steigzeit (#188).
    final back = dijkstra(g, split[3], bio);
    expect(back.dist[split[0]], closeTo(3 * 1000 / (25 / 3.6) + 300 * kDescentCost * 3600 / 450, 1e-6));
    expect(back.climb[split[0]], 0);
    final s = summarizePath(g, back.pathTo(split[0])!, split[3], bio);
    expect(s.gainM, 0);
    expect(s.lossM, closeTo(300, 1e-9));
    expect(s.heightsComplete, isTrue);
  });

  test('kein Weg: null', () {
    final g = buildRoadGraph([_way([(0, 0), (100, 0)]), _way([(500, 0), (600, 0)])], lat0: 47.5).graph;
    expect(shortestPath(g, 0, 2, bio), isNull);
    expect(dijkstra(g, 0, bio).pathTo(2), isNull);
  });

  group('loadRoadGraph', () {
    // Eine z13-Kachel um 48,0° N / 9,0° O mit einem Forstweg quer durch
    // und einem Trail-Ende daneben; ein Bereich trägt sie.
    final t = tileAt(48.0, 9.0, 13);
    final tile = mvtTile([
      road([(0, 2048), (4096, 2048)], 'path', kindDetail: 'track'),
      road([(2048, 0), (2048, 4096)], 'minor_road', kindDetail: 'residential'),
    ]);
    final bounds = tileBounds(13, t.x, t.y);
    final box = LatBox(bounds.south + 1e-4, bounds.west + 1e-4, bounds.north - 1e-4, bounds.east - 1e-4);

    Future<MemoryAreaStore> seed({required bool withTile}) async {
      final store = MemoryAreaStore();
      final tiles = [
        if (withTile) TileToWrite(13, t.x, t.y, tile),
        TileToWrite(12, t.x >> 1, t.y >> 1, Uint8List.fromList([1])),
      ];
      final bytes = writePmTiles(
        tiles: tiles,
        tileCompression: Compression.none,
        bounds: TileBounds(west: bounds.west, south: bounds.south, east: bounds.east, north: bounds.north),
      );
      await store.putArchive('a', bytes);
      await store.saveIndex([
        StoredArea(
          id: 'a',
          name: 'a',
          bounds: bounds,
          minZoom: 12,
          maxZoom: 13,
          build: '20260928',
          tiles: tiles.length,
          bytes: bytes.length,
          savedAt: DateTime.utc(2026, 10, 1),
        ),
      ]);
      return store;
    }

    Future<PmTilesVectorTileProvider?> Function(StoredArea) openFrom(MemoryAreaStore store) => (a) async {
          final bytes = await store.readArchive(a.id);
          return bytes == null ? null : PmTilesVectorTileProvider.openBytes(bytes);
        };

    test('vollständig: der Graph steht, die Kreuzung ist geteilt, Höhen aus dem Leser', () async {
      final store = await seed(withTile: true);
      final values = [for (var i = 0; i < kHeightGrid * kHeightGrid; i++) 700];
      final heights = HeightReader([
        MemoryHeightSource({(x: t.x, y: t.y): HeightTile(Int16List.fromList(values))}),
      ]);
      final r = await loadRoadGraph(areas: await store.list(), box: box, open: openFrom(store), heights: heights);
      expect(r.coverage, RoadCoverage.complete);
      expect(r.tilesFound, 1);
      expect(r.crossings, 1);
      final g = r.graph!;
      expect(g.edges, hasLength(4));
      expect(r.edgesWithoutHeights, 0);
      expect(g.components(), hasLength(1));
      // Von der West- zur Ostkante über die Kreuzung.
      final src = g.attach(LatLng((bounds.north + bounds.south) / 2, bounds.west))!;
      final dst = g.attach(LatLng((bounds.north + bounds.south) / 2, bounds.east))!;
      final p = shortestPath(g, src, dst, bio)!;
      expect(p.edges, hasLength(2));
      expect(summarizePath(g, p.edges, src, bio).gainM, 0);
    });

    test('ohne Höhenleser zählt jede Kante als ohne Höhe', () async {
      final store = await seed(withTile: true);
      final r = await loadRoadGraph(areas: await store.list(), box: box, open: openFrom(store));
      expect(r.coverage, RoadCoverage.complete);
      expect(r.edgesWithoutHeights, r.graph!.edges.length);
    });

    test('fehlt die Kachel, gibt es keinen Graphen — und ohne Bereich auch nicht', () async {
      final store = await seed(withTile: false);
      final r = await loadRoadGraph(areas: await store.list(), box: box, open: openFrom(store));
      expect(r.coverage, RoadCoverage.none);
      expect(r.graph, isNull);
      final empty = await loadRoadGraph(areas: const [], box: box, open: openFrom(store));
      expect(empty.coverage, RoadCoverage.none);
      // Ein Rahmen über zwei Kacheln, nur eine da: teilweise, kein Graph.
      final full = await seed(withTile: true);
      final wide = LatBox(bounds.south + 1e-4, bounds.west + 1e-4, bounds.north - 1e-4, bounds.east + 0.01);
      final partial = await loadRoadGraph(areas: await full.list(), box: wide, open: openFrom(full));
      expect(partial.coverage, RoadCoverage.partial);
      expect(partial.graph, isNull);
      expect(partial.tilesNeeded, 2);
      expect(partial.tilesFound, 1);
    });

    group('online ergänzt (#187)', () {
      // Ein Rahmen über drei Kacheln nebeneinander, die mittlere ist [t].
      final west = tileBounds(13, t.x - 1, t.y), east = tileBounds(13, t.x + 1, t.y);
      final three = LatBox(bounds.south + 1e-4, west.west + 1e-4, bounds.north - 1e-4, east.east - 1e-4);

      test('ohne Bereich: alles vom Host, und der Graph steht', () async {
        final asked = <({int x, int y})>[];
        final r = await loadRoadGraph(
          areas: const [],
          box: box,
          open: (_) async => null,
          fetchOnline: (k) async {
            asked.add((x: k.x, y: k.y));
            return tile;
          },
        );
        expect(asked, [(x: t.x, y: t.y)]);
        expect(r.coverage, RoadCoverage.complete);
        expect(r.tilesOnline, 1);
        expect(r.graph!.edges, hasLength(4));
      });

      test('gefragt wird nur, was kein Bereich hat — die nächsten zur Mitte zuerst', () async {
        final store = await seed(withTile: true);
        final asked = <int>[];
        final r = await loadRoadGraph(
          areas: await store.list(),
          box: three,
          open: openFrom(store),
          maxOnline: 1,
          fetchOnline: (k) async {
            asked.add(k.x);
            return tile;
          },
        );
        // Die mittlere liegt im Bereich; von den beiden äußeren holt die
        // Grenze genau eine.
        expect(asked, hasLength(1));
        expect(asked.single, isNot(t.x));
        expect(r.tilesNeeded, 3);
        expect(r.tilesFound, 2);
        expect(r.tilesOnline, 1);
        expect(r.onlineCapped, isTrue);
        expect(r.coverage, RoadCoverage.partial);
      });

      test('ohne Bereich und mit Grenze: die Kachel in der Mitte zuerst', () async {
        final asked = <int>[];
        await loadRoadGraph(
          areas: const [],
          box: three,
          open: (_) async => null,
          maxOnline: 1,
          fetchOnline: (k) async {
            asked.add(k.x);
            return tile;
          },
        );
        expect(asked, [t.x]);
      });

      test('ein Netzfehler beendet das Nachladen, der Plan bleibt', () async {
        final store = await seed(withTile: true);
        var calls = 0;
        final r = await loadRoadGraph(
          areas: await store.list(),
          box: three,
          open: openFrom(store),
          requireComplete: false,
          fetchOnline: (k) async {
            calls++;
            throw TimeoutException('kein Netz');
          },
        );
        expect(calls, 1, reason: 'nach dem ersten Fehler fragt der Lader nicht weiter');
        expect(r.onlineBroken, isTrue);
        expect(r.tilesOnline, 0);
        expect(r.tilesFound, 1);
        expect(r.graph, isNotNull);
      });

      test('was der Host nicht hat (null), zählt nicht als gefunden', () async {
        final r = await loadRoadGraph(
          areas: const [],
          box: box,
          open: (_) async => null,
          fetchOnline: (_) async => null,
        );
        expect(r.coverage, RoadCoverage.none);
        expect(r.graph, isNull);
        expect(r.tilesOnline, 0);
        expect(r.onlineBroken, isFalse);
      });
    });
  });
}
