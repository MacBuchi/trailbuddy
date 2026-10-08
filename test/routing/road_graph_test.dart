// Der Wegegraph (Konzept-Routing 2.7): Kacheln werden zu klassifizierten,
// zugeschnittenen Linien; tote Enden binden sich an (auch mitten in ein
// Segment, der T-Knoten), Kreuzungen auf derselben Ebene teilen sich,
// Brücken nicht; Einbahn nur auf Straßen; Trail-Enden heften sich an;
// Höhen kommen je Kante aus den Höhenkacheln. Dieselben Fälle wie der
// Self-Test des Werkzeugs.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/height_tiles.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';

import '../fakes/fake_tiles.dart';

/// Eine Linie in Metern um (47,5° N, 11,5° O) als Grad.
/// Meter → Grad über DIESELBE Projektion wie der Graph, sonst sind
/// „1000 m" im Test 998,9 m im Graphen.
List<LatLng> _m(List<(double, double)> xy, {double lat0 = 47.5, double lon0 = 11.5}) {
  final proj = FlatProjection(lat0);
  final o = proj.xy(LatLng(lat0, lon0));
  return [for (final (x, y) in xy) proj.latLng(math.Point(o.x + x, o.y + y))];
}

WayLine _way(List<(double, double)> xy, {WayClass cls = WayClass.forstweg, bool oneway = false, int level = 0}) =>
    WayLine(cls: cls, oneway: oneway, points: _m(xy), level: level);

void main() {
  group('wayLinesFromTile', () {
    final t = tileAt(48.0, 9.0, 13);

    test('klassifiziert, liest Einbahn, Brücke, Tunnel und Zugang, lässt Gesperrtes weg', () {
      final bytes = mvtTile([
        road([(100, 100), (2000, 100)], 'path', kindDetail: 'track'),
        road([(100, 500), (2000, 500)], 'minor_road', kindDetail: 'residential', extra: {'oneway': true}),
        road([(100, 900), (2000, 900)], 'path', kindDetail: 'path', extra: {'oneway': true}),
        road([(100, 1300), (2000, 1300)], 'major_road', kindDetail: 'secondary', extra: {'is_bridge': true}),
        road([(100, 1700), (2000, 1700)], 'minor_road', kindDetail: 'service', extra: {'is_tunnel': true}),
        road([(100, 2100), (2000, 2100)], 'path', kindDetail: 'track', extra: {'access': 'private'}),
        road([(100, 2500), (2000, 2500)], 'highway', kindDetail: 'motorway'),
        road([(100, 2900), (2000, 2900)], 'minor_road', kindDetail: 'service', extra: {'service': 'driveway'}),
        road([(100, 3300), (2000, 3300)], 'path', kindDetail: 'track', layer: 'water'),
      ]);
      final lines = wayLinesFromTile(bytes, z: 13, x: t.x, y: t.y);
      expect(lines.map((l) => l.cls), [
        WayClass.forstweg,
        WayClass.nebenstrasse,
        WayClass.wanderweg,
        WayClass.hauptstrasse,
        WayClass.zufahrt,
      ]);
      expect(lines.map((l) => l.oneway), [false, true, false, false, false],
          reason: 'Einbahn nur auf Straßenklassen');
      expect(lines.map((l) => l.level), [0, 0, 0, 1, -1]);
      expect(lines.first.points, hasLength(2));
      expect(tileAt(lines.first.points.first.latitude, lines.first.points.first.longitude, 13), (x: t.x, y: t.y));
    });

    test('der Puffer über den Kachelrand wird abgeschnitten, Stücke innerhalb bleiben', () {
      final bytes = mvtTile([
        // Von links außerhalb quer durch bis rechts außerhalb: EIN Stück
        // von Kante zu Kante.
        road([(-300, 2000), (4400, 2000)], 'path', kindDetail: 'track'),
        // Hinaus und wieder hinein: zwei Stücke.
        road([(1000, 1000), (1000, -200), (2000, -200), (2000, 1000)], 'path', kindDetail: 'track'),
        // Ganz außerhalb: nichts.
        road([(-200, -200), (-100, -100)], 'path', kindDetail: 'track'),
      ]);
      final lines = wayLinesFromTile(bytes, z: 13, x: t.x, y: t.y);
      expect(lines, hasLength(3));
      final b = tileBounds(13, t.x, t.y);
      for (final l in lines) {
        for (final p in l.points) {
          expect(p.longitude, inInclusiveRange(b.west - 1e-9, b.east + 1e-9));
          expect(p.latitude, inInclusiveRange(b.south - 1e-9, b.north + 1e-9));
        }
      }
      expect(lines.first.points.first.longitude, closeTo(b.west, 1e-9));
      expect(lines.first.points.last.longitude, closeTo(b.east, 1e-9));
    });

    test('kaputte Bytes: keine Linien, kein Fehler', () {
      expect(wayLinesFromTile(Uint8List.fromList([1, 2, 3]), z: 13, x: 1, y: 1), isEmpty);
    });

    test('clipToTile in Kacheleinheiten', () {
      final pieces = clipToTile([const math.Point(-10.0, 50.0), const math.Point(110.0, 50.0)], 100);
      expect(pieces, hasLength(1));
      expect(pieces.single.first, const math.Point(0.0, 50.0));
      expect(pieces.single.last, const math.Point(100.0, 50.0));
      expect(clipToTile([const math.Point(-10.0, -10.0), const math.Point(-5.0, -5.0)], 100), isEmpty);
    });
  });

  group('buildRoadGraph', () {
    test('zwei Linien mit gemeinsamem Scheitel teilen einen Knoten; ohne Join zwei Komponenten', () {
      final a = _way([(0, 0), (100, 0), (200, 0)]);
      final b = _way([(100, 0), (100, 100)]); // teilt den Scheitel bei (100, 0)
      final c = _way([(300, 0), (300, 100)]); // ganz woanders
      final build = buildRoadGraph([a, b, c], lat0: 47.5, joinM: 0, splitCrossings: false);
      final g = build.graph;
      expect(g.edges, hasLength(4), reason: 'a wird am Scheitel geteilt');
      expect(g.components(), hasLength(2));
      expect(build.joins, 0);
      expect(g.largestComponentShare, closeTo(300 / 400, 1e-6));
    });

    test('T-Knoten: ein totes Ende 1 m neben einem Segment ohne Scheitel wird angebunden', () {
      final through = _way([(0, 0), (200, 0)]);
      final stub = _way([(100, 1), (100, 100)]);
      final strict = buildRoadGraph([through, stub], lat0: 47.5, joinM: 0, splitCrossings: false);
      expect(strict.graph.components(), hasLength(2));
      final joined = buildRoadGraph([through, stub], lat0: 47.5);
      expect(joined.joins, 1);
      expect(joined.graph.components(), hasLength(1));
      // Das Segment wurde geteilt: drei Wegkanten plus die Anbindung.
      expect(joined.graph.edges, hasLength(4));
      // 10 m weg: kein Join bei 2 m.
      final far = buildRoadGraph([through, _way([(100, 10), (100, 100)])], lat0: 47.5);
      expect(far.joins, 0);
      expect(far.graph.components(), hasLength(2));
    });

    test('Kreuzung ohne Knoten wird geteilt — nicht aber unter einer Brücke', () {
      final ew = _way([(0, 0), (200, 0)]);
      final ns = _way([(100, -100), (100, 100)]);
      final crossed = buildRoadGraph([ew, ns], lat0: 47.5);
      expect(crossed.crossings, 1);
      expect(crossed.graph.components(), hasLength(1));
      expect(crossed.graph.edges, hasLength(4));
      final bridge = buildRoadGraph([ew, _way([(100, -100), (100, 100)], level: 1)], lat0: 47.5);
      expect(bridge.crossings, 0);
      expect(bridge.graph.components(), hasLength(2));
    });

    test('Einbahn bleibt an der Kante, Länge in Metern', () {
      final g = buildRoadGraph([_way([(0, 0), (300, 400)], cls: WayClass.nebenstrasse, oneway: true)], lat0: 47.5).graph;
      expect(g.edges.single.oneway, isTrue);
      expect(g.edges.single.length, closeTo(500, 0.5));
      expect(g.edges.single.cls, WayClass.nebenstrasse);
    });

    test('attach: Knoten im Umkreis, sonst neuer Knoten auf der Kante, sonst null', () {
      final g = buildRoadGraph([_way([(0, 0), (1000, 0)])], lat0: 47.5).graph;
      // 5 m neben dem Anfang: der Anfangsknoten.
      expect(g.attach(_m([(3, 4)]).single), 0);
      // 20 m neben der Mitte: ein neuer Knoten auf der Kante.
      final mid = g.attach(_m([(500, 20)]).single);
      expect(mid, isNotNull);
      expect(g.nodes[mid!].x, closeTo(g.proj.xy(_m([(500, 0)]).single).x, 0.5));
      expect(g.edges, hasLength(2));
      expect(g.edges[0].length + g.edges[1].length, closeTo(1000, 0.5));
      // 100 m daneben: nichts.
      expect(g.attach(_m([(500, 100)]).single), isNull);
    });
  });

  test('addClimbs liest Anstieg und Abstieg je Kante, markiert Kanten ohne Höhe', () async {
    // Eine Höhenkachel: Ebene, 1 m je Probe nach Osten (48 m über die Kachel).
    final origin = tileAt(47.5, 11.5, kHeightTileZoom);
    final values = [
      for (var j = 0; j < kHeightGrid; j++)
        for (var i = 0; i < kHeightGrid; i++) 1000 + i * 10,
    ];
    final reader = HeightReader([
      MemoryHeightSource({(x: origin.x, y: origin.y): HeightTile(Int16List.fromList(values))}),
    ]);
    final b = tileBounds(kHeightTileZoom, origin.x, origin.y);
    final midLat = (b.north + b.south) / 2;
    final inside = WayLine(cls: WayClass.forstweg, oneway: false, points: [LatLng(midLat, b.west), LatLng(midLat, b.east)]);
    final outside = WayLine(cls: WayClass.forstweg, oneway: false, points: [LatLng(midLat, b.east + 0.05), LatLng(midLat, b.east + 0.06)]);
    final g = buildRoadGraph([inside, outside], lat0: midLat).graph;
    await addClimbs(g, reader);
    final e = g.edges.firstWhere((e) => e.hasHeights);
    expect(e.gain, closeTo(480, 3));
    expect(e.loss, closeTo(0, 1));
    expect(e.steepUp, 0, reason: '14,5 % liegt unter der Steilgrenze');
    expect(g.edgesWithoutHeights, 1);
  });

  test('addClimbs zählt die Höhenmeter über der Steilgrenze je Richtung (#194)', () async {
    // 25 m je Probe nach Osten: gut 36 % über die ganze Kachel.
    final origin = tileAt(47.5, 11.5, kHeightTileZoom);
    final values = [
      for (var j = 0; j < kHeightGrid; j++)
        for (var i = 0; i < kHeightGrid; i++) 1000 + i * 25,
    ];
    final reader = HeightReader([
      MemoryHeightSource({(x: origin.x, y: origin.y): HeightTile(Int16List.fromList(values))}),
    ]);
    final b = tileBounds(kHeightTileZoom, origin.x, origin.y);
    final midLat = (b.north + b.south) / 2;
    final g = buildRoadGraph([
      WayLine(cls: WayClass.forstweg, oneway: false, points: [LatLng(midLat, b.west), LatLng(midLat, b.east)]),
    ], lat0: midLat).graph;
    await addClimbs(g, reader);
    final e = g.edges.single;
    final grade = e.gain / e.length;
    expect(grade, closeTo(0.363, 0.01));
    // Alles über 15 % — bis auf die halben Endschritte der Glättung.
    expect(e.steepUp, closeTo((grade - kSteepGrade) * e.length, (grade - kSteepGrade) * kClimbSampleM * 1.01));
    expect(e.steepUp, lessThan((grade - kSteepGrade) * e.length));
    expect(e.steepDown, 0);
    // Gewichtet (#188): fast jeder Höhenmeter mit dem Gewicht seiner 36 %.
    expect(e.steepWUp, closeTo(e.gain * steepWeightAt(grade), e.gain * steepWeightAt(grade) * 0.1));
    expect(e.steepWDown, 0);

    // Geteilt: beide Hälften tragen ihren Anteil.
    final whole = e.steepUp;
    final wholeW = e.steepWUp;
    g.attach(LatLng(midLat, (b.west + b.east) / 2));
    expect(g.edges, hasLength(2));
    expect(g.edges.fold<double>(0, (s, e) => s + e.steepUp), closeTo(whole, 1e-6));
    expect(g.edges.first.steepUp, closeTo(g.edges.last.steepUp, whole * 0.02));
    expect(g.edges.fold<double>(0, (s, e) => s + e.steepWUp), closeTo(wholeW, 1e-6));
  });

  group('Wegegüte (#213) — dieselben Fälle wie der Self-Test des Werkzeugs', () {
    WayGradeLine grade(int k, List<(double, double)> xy, {int? u}) => WayGradeLine(way: k, uphill: u, points: _m(xy));

    RoadGraph graph() {
      final g = RoadGraph(47.5);
      final track = _m([(0, 0), (150, 0)]), path = _m([(150, 0), (300, 0)]), road = _m([(0, 33), (300, 33)]);
      g.addEdge(g.node(track.first), g.node(track.last), WayClass.forstweg, false, track);
      g.addEdge(g.node(path.first), g.node(path.last), WayClass.wanderweg, false, path);
      g.addEdge(g.node(road.first), g.node(road.last), WayClass.nebenstrasse, false, road);
      return g;
    }

    test('ein Forstweg nimmt die Klasse in 3 m, ein halber Pfad ist keine Mehrheit, Straßen nie', () {
      final g = graph();
      final named = addWayQuality(g, [
        grade(7, [(0, 1.1), (150, 1.1)]),
        grade(8, [(150, 0), (225, 0)], u: 3),
        grade(6, [(190, 4.4), (300, 4.4)]),
        grade(5, [(0, 34.1), (300, 34.1)]),
      ]);
      expect(named, 1);
      expect([for (final e in g.edges) e.way], [7, null, null]);
    });

    test('der größte Teil eines Pfads: Klasse und Uphill-Grad; ein Forstweg nimmt nie eine Pfad-Klasse', () {
      final g = graph();
      addWayQuality(g, [grade(8, [(150, 0), (298, 0)], u: 3), grade(4, [(0, 0), (150, 0)])]);
      expect(g.edges[1].way, 8);
      expect(g.edges[1].uphill, 3);
      expect(g.edges[0].way, isNull);
      g.splitEdge(1, 0, _m([(225, 0)]).single);
      expect([for (final e in g.edges) if (e.cls == WayClass.wanderweg) (e.way, e.uphill)], [(8, 3), (8, 3)],
          reason: 'eine Teilung behält Klasse und Uphill-Grad');
    });

    test('liest die Kachel des Wege-Archivs: k, u und die Lage', () {
      final t = tileAt(48.0, 9.0, 13);
      final lines = wayGradeLinesFromTile(
          waysTile([
            (k: 7, u: null, px: [(0, 2048), (4096, 2048)]),
            (k: 8, u: 4, px: [(2048, 0), (2048, 4096)]),
          ]),
          z: 13,
          x: t.x,
          y: t.y);
      expect([for (final l in lines) (l.way, l.uphill)], [(7, null), (8, 4)]);
      final b = tileBounds(13, t.x, t.y);
      expect(lines.first.points.first.longitude, closeTo(b.west, 1e-9));
      expect(lines.first.points.last.longitude, closeTo(b.east, 1e-9));
      expect(wayGradeLinesFromTile(Uint8List.fromList([1, 2, 3]), z: 13, x: t.x, y: t.y), isEmpty);
    });
  });
}
