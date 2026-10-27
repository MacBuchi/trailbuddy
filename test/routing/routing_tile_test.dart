// Vorgebackene Routing-Kacheln (#380, Konzept-Routing 11): das Format
// hin und zurück, „bergab" überlebt das Runden, fremde Fassungen heißen
// „kein Stück" — und ein Graph aus Stücken ist der Graph von heute: gleiche
// Wege, gleiche Höhen, gleiche Güte, Suchen mit denselben Kosten.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart' show TileXYZ;
import 'package:trailbuddy/features/offline_areas/height_tiles.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/road_graph_loader.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';
import 'package:trailbuddy/features/routing/route_search.dart';
import 'package:trailbuddy/features/routing/routing_tile.dart';

import '../fakes/fake_tiles.dart';
import '../fakes/graph_tiles.dart';

const _lat0 = 47.27, _lon0 = 11.39;
final _proj = FlatProjection(_lat0);
final _o = _proj.xy(const LatLng(_lat0, _lon0));

LatLng _p(double x, double y) => _proj.latLng(math.Point(_o.x + x, _o.y + y));

/// Ein Gitter über 3 × 3 Kacheln (z13 ist hier ~3,3 km breit): alle 600 m
/// eine Linie in jede Richtung, Forstwege und Wanderwege im Wechsel, eine
/// Straße diagonal hindurch (Kreuzungen ohne Knoten), eine Brücke darüber
/// (keine Kreuzung) und ein Weg, der 1 m vor einem anderen endet (tote
/// Enden). Fast jede Linie läuft über Kachelränder.
List<WayLine> _grid() {
  final out = <WayLine>[];
  for (var i = 0; i <= 12; i++) {
    final v = -3600.0 + i * 600;
    final cls = i.isEven ? WayClass.forstweg : WayClass.wanderweg;
    out.add(WayLine(cls: cls, oneway: false, points: [_p(v, -3600), _p(v + 37, 310), _p(v, 3600)]));
    out.add(WayLine(cls: cls, oneway: false, points: [_p(-3600, v), _p(290, v + 23), _p(3600, v)]));
  }
  out.add(WayLine(cls: WayClass.nebenstrasse, oneway: false, points: [_p(-3500, -3410), _p(3490, 3500)]));
  out.add(WayLine(cls: WayClass.hauptstrasse, oneway: true, level: 1, points: [_p(-3500, 3410), _p(3490, -3500)]));
  out.add(WayLine(cls: WayClass.radweg, oneway: false, points: [_p(-1000, 301), _p(-301, 1001)]));
  return out;
}

/// Die Höhen: ein Hang nach Norden mit Wellen, damit Kanten steigen,
/// fallen und steil werden.
double _height(LatLng p) {
  final xy = _proj.xy(p);
  final y = xy.y - _o.y, x = xy.x - _o.x;
  return 900 + y / 12 + 25 * math.sin(x / 300) + 15 * math.cos(y / 170);
}

/// Das Wege-Archiv dazu: jeder Forstweg Klasse 3, jeder Wanderweg 6 mit
/// `u` 2 — je Kachel zugeschnitten wie die Karte.
List<RoadTileBytes> _waysOf(List<WayLine> lines, Iterable<TileXYZ> tiles) {
  const n = 1 << kRoadGraphZoom;
  math.Point<double> px(LatLng p, TileXYZ t) {
    final xf = (p.longitude + 180) / 360 * n;
    final lat = p.latitude * math.pi / 180;
    final yf = (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * n;
    return math.Point((xf - t.x) * kTileExtent, (yf - t.y) * kTileExtent);
  }

  return [
    for (final t in tiles)
      (
        tile: t,
        bytes: waysTile([
          for (final l in lines)
            if (l.cls == WayClass.forstweg || l.cls == WayClass.wanderweg)
              for (final piece in clipToTile([for (final p in l.points) px(p, t)], kTileExtent.toDouble()))
                (
                  k: l.cls == WayClass.forstweg ? 3 : 6,
                  u: l.cls == WayClass.forstweg ? null : 2,
                  px: [for (final q in piece) (q.x.round(), q.y.round())],
                ),
        ]),
      ),
  ];
}

typedef _Frame = ({List<RoadTileBytes> roads, List<RoadTileBytes> ways, HeightTiles heights});

_Frame _frame() {
  final lines = _grid();
  final roads = roadTilesOf(lines);
  final tiles = [for (final r in roads) r.tile];
  return (roads: roads, ways: _waysOf(lines, tiles), heights: heightTilesOf(tiles, _height));
}

RoadGraph _today(_Frame f) => buildRoadGraphFrom(roads: f.roads, ways: f.ways, heights: f.heights, lat0: _lat0).graph;

RoadGraph _stitched(_Frame f) {
  final pieces = bakeTiles(roads: f.roads, ways: f.ways, heights: f.heights);
  return stitchPieces([for (final p in pieces) unpackPiece(p.bytes)!], _lat0).graph;
}

double _sum(RoadGraph g, double Function(GraphEdge e) f) => g.edges.fold(0.0, (s, e) => s + f(e));

void main() {
  group('Format', () {
    test('hin und zurück: dieselben Knoten, Kanten, Werte und Punkte', () {
      final f = _frame();
      // Die Kachel mit den Knicken des Gitters (innere Punkte).
      final mid = _tileOf(_p(0, 310));
      final r = f.roads.firstWhere((r) => (r.tile.x, r.tile.y) == mid);
      final g = buildRoadGraphFrom(roads: [r], ways: f.ways, heights: f.heights, lat0: _lat0).graph;
      final piece = decodePiece(encodePiece(g, r.tile.x, r.tile.y))!;
      expect((piece.x, piece.y), (r.tile.x, r.tile.y));
      expect(piece.nodes, hasLength(g.nodes.length));
      expect(piece.edges, hasLength(g.edges.length));
      for (var n = 0; n < g.nodes.length; n++) {
        expect(piece.nodes[n].latitude, closeTo(g.nodeLatLng[n].latitude, 1e-6));
        expect(piece.nodes[n].longitude, closeTo(g.nodeLatLng[n].longitude, 1e-6));
      }
      var pixelPoints = 0;
      for (var i = 0; i < g.edges.length; i++) {
        final e = g.edges[i], p = piece.edges[i];
        expect((p.a, p.b, p.cls, p.oneway, p.level, p.hasHeights), (e.a, e.b, e.cls, e.oneway, e.level, e.hasHeights));
        expect((p.way, p.uphill), (e.way, e.uphill));
        expect(p.gainCm / 100, closeTo(e.gain, 0.006));
        expect(p.steepDm[2] / 10, closeTo(e.steepWUp, 0.06));
        expect(p.inner, hasLength(e.points.length - 2));
        for (var k = 0; k < p.inner.length; k++) {
          // Punkte auf dem Raster kommen bitgleich zurück, die übrigen auf
          // ein Mikrograd.
          if (p.inner[k] == e.points[k + 1]) pixelPoints++;
          expect(p.inner[k].latitude, closeTo(e.points[k + 1].latitude, 1e-6));
          expect(p.inner[k].longitude, closeTo(e.points[k + 1].longitude, 1e-6));
        }
      }
      expect(pixelPoints, greaterThan(0), reason: 'innere Punkte liegen auf dem Raster der Karte');
      expect(g.edges.where((e) => e.way != null), isNotEmpty, reason: 'das Gitter trägt Wegegüte');
      expect(g.edges.where((e) => e.steepWUp > 0), isNotEmpty, reason: 'das Gitter hat steile Stücke');
    });

    test('„bergab" bleibt bergab — auch bei 3 mm Abstieg über 2 mm Anstieg', () {
      // edgeTimeS nimmt die Abfahrt, sobald der Abstieg den Anstieg
      // übersteigt; schlicht gerundet wären beide 0 cm (Gegenprobe: rot).
      final g = RoadGraph(_lat0);
      final a = g.node(_p(0, 0)), b = g.node(_p(100, 0)), c = g.node(_p(200, 0));
      g.edges[g.addEdge(a, b, WayClass.forstweg, false, [_p(0, 0), _p(100, 0)])]
        ..hasHeights = true
        ..gain = 0.002
        ..loss = 0.003;
      g.edges[g.addEdge(b, c, WayClass.forstweg, false, [_p(100, 0), _p(200, 0)])]
        ..hasHeights = true
        ..gain = 0.004
        ..loss = 0.003;
      final t = _tileOf(_p(0, 0));
      final back = stitchPieces([decodePiece(encodePiece(g, t.$1, t.$2))!], _lat0).graph;
      expect(back.edges[0].loss > back.edges[0].gain, isTrue);
      expect(back.edges[1].loss > back.edges[1].gain, isFalse);
    });

    test('fremdes Format, fremde Fassung oder kaputte Bytes: kein Stück', () {
      final f = _frame();
      final r = f.roads.first;
      final g = buildRoadGraphFrom(roads: [r], lat0: _lat0).graph;
      final bytes = encodePiece(g, r.tile.x, r.tile.y);
      expect(decodePiece(bytes), isNotNull);
      expect(decodePiece(Uint8List.fromList([kRoutingTileFormat + 1, ...bytes.skip(1)])), isNull);
      expect(decodePiece(Uint8List.fromList([bytes[0], kRoutingTileVersion + 1, ...bytes.skip(2)])), isNull);
      expect(decodePiece(Uint8List.sublistView(bytes, 0, bytes.length - 3)), isNull);
      expect(decodePiece(Uint8List.fromList([...bytes, 0])), isNull);
      expect(decodePiece(Uint8List(0)), isNull);
    });

    test('der Bau eines Stücks nennt Format, Fassung und die drei Quellen', () {
      expect(pieceBuild(map: '20261008', heights: '20261009', ways: '20261010'),
          'r$kRoutingTileFormat.$kRoutingTileVersion:20261008:20261009:20261010');
      expect(pieceBuild(map: '20261008'), 'r$kRoutingTileFormat.$kRoutingTileVersion:20261008:-:-');
    });

    test('die Bauregeln, die ein Stück festschreibt — wer eine ändert, zählt kRoutingTileVersion hoch', () {
      // Diese Liste ist absichtlich eine Kopie: Ändert sich hier eine
      // Zahl, liegen auf den Geräten Stücke nach den alten Regeln. Dann
      // kRoutingTileVersion hochzählen UND die Zahl hier nachziehen.
      // Die Kosten (edgeCostS, Stil, Vorlieben) gehören NICHT hierher.
      expect(kRoutingTileVersion, 1);
      expect(kGraphJoinM, 2.0);
      expect(kWayMatchM, 3.0);
      expect(kWaySampleM, 10.0);
      expect(kWayMajority, 0.5);
      expect(kClimbSampleM, 50.0);
      expect(kClimbHysteresisM, 10.0);
      expect(kSteepGrade, 0.15);
      expect(kSteepSmooth, 3);
      final weights = [for (final g in [0.05, 0.1, 0.15, 0.2, 0.3, 0.5]) steepWeightAt(g)];
      const weightsV1 = [0.0, 0.0, 0.14316144883776383, 0.5727698527388965, 5.730676979816826, 30.0];
      for (var i = 0; i < weights.length; i++) {
        expect(weights[i], closeTo(weightsV1[i], 1e-9));
      }
      expect(
          [
            for (final (kind, detail) in [
              ('major_road', 'primary'),
              ('medium_road', null),
              ('minor_road', 'service'),
              ('path', 'track'),
              ('path', 'path'),
              ('path', 'steps'),
              ('path', 'cycleway'),
              ('path', 'footway'),
              ('highway', 'motorway'),
            ])
              classifyWay(kind: kind, kindDetail: detail)?.name,
          ],
          _classesV1);
    });
  });

  group('zusammengesetzt gegen gebaut', () {
    test('dieselben Wege, Höhen und Güte', () {
      final f = _frame();
      expect(f.roads.length, greaterThanOrEqualTo(9), reason: 'das Gitter liegt über mehreren Kacheln');
      final a = _today(f), b = _stitched(f);
      expect(b.totalLength, closeTo(a.totalLength, a.totalLength * 1e-4));
      expect(b.components().length, a.components().length);
      expect(b.largestComponentShare, closeTo(a.largestComponentShare, 1e-4));
      expect(_sum(b, (e) => e.gain + e.loss), closeTo(_sum(a, (e) => e.gain + e.loss), 0.01 * _sum(a, (e) => e.gain + e.loss)));
      expect(b.edgesWithoutHeights, a.edgesWithoutHeights);
      double named(RoadGraph g) => _sum(g, (e) => e.way == null ? 0 : e.length);
      expect(named(b), closeTo(named(a), named(a) * 0.01));
    });

    test('Suchen kosten dasselbe (Median unter 0,1 %, keine über 2 %)', () {
      final f = _frame();
      final a = _today(f), b = _stitched(f);
      final comp = a.components().first;
      final nodes = <int>{for (final ei in comp) a.edgeA(ei)}.toList()..sort();
      final rnd = math.Random(380);
      final diffs = <double>[];
      for (var i = 0; i < 30; i++) {
        final s = nodes[rnd.nextInt(nodes.length)], t = nodes[rnd.nextInt(nodes.length)];
        final ca = dijkstra(a, s, RiderProfile.bio, target: t).costTo(t);
        final sb = b.nearestNode(a.nodes[s], 1), tb = b.nearestNode(a.nodes[t], 1);
        expect((sb, tb), isNot(contains(null)));
        final cb = dijkstra(b, sb!, RiderProfile.bio, target: tb).costTo(tb!);
        expect((ca == null), cb == null);
        if (ca == null || cb == null || ca == 0) continue;
        diffs.add((cb - ca).abs() / ca);
      }
      diffs.sort();
      expect(diffs, hasLength(greaterThan(20)));
      expect(diffs[diffs.length ~/ 2], lessThan(0.001));
      expect(diffs.last, lessThan(0.02));
    });

    test('eine Linie über den Kachelrand bleibt verbunden', () {
      // Ein Weg, der genau über eine Kachelgrenze läuft und dort nichts
      // kreuzt: zwei Stücke, beim Zusammensetzen EINE Komponente.
      final t = _tileOf(_p(0, 0));
      final edgeLon = tileLatLng(t.$1 + 1.0, t.$2 + 0.5);
      final line = [
        LatLng(edgeLon.latitude, edgeLon.longitude - 0.01),
        LatLng(edgeLon.latitude + 0.0003, edgeLon.longitude + 0.01),
      ];
      final roads = roadTilesOf([WayLine(cls: WayClass.forstweg, oneway: false, points: line)]);
      expect(roads, hasLength(2));
      final pieces = [for (final p in bakeTiles(roads: roads)) unpackPiece(p.bytes)!];
      final g = stitchPieces(pieces, _lat0).graph;
      expect(g.components(), hasLength(1));
      expect(g.totalLength, closeTo(buildRoadGraphFrom(roads: roads, lat0: _lat0).graph.totalLength, 0.5));
    });

    test('ein totes Ende 1 m vor der Nachbarkachel wird dort gebunden', () {
      // Der Randknoten (Gegenprobe: ohne Randliste zwei Komponenten).
      final t = _tileOf(_p(0, 0));
      final border = tileLatLng(t.$1 + 1.0, t.$2 + 0.5);
      final mLon = 111320 * math.cos(border.latitude * math.pi / 180);
      final a = WayLine(cls: WayClass.forstweg, oneway: false, points: [
        LatLng(border.latitude, border.longitude - 0.01),
        LatLng(border.latitude, border.longitude - 1 / mLon),
      ]);
      final b = WayLine(cls: WayClass.forstweg, oneway: false, points: [
        LatLng(border.latitude - 0.005, border.longitude + 0.2 / mLon),
        LatLng(border.latitude + 0.005, border.longitude + 0.2 / mLon),
      ]);
      final roads = roadTilesOf([a, b]);
      final pieces = [for (final p in bakeTiles(roads: roads)) unpackPiece(p.bytes)!];
      expect(pieces.expand((p) => p.border), isNotEmpty);
      final g = stitchPieces(pieces, _lat0).graph;
      expect(g.components(), hasLength(1));
    });
  });
}

(int, int) _tileOf(LatLng p) {
  const n = 1 << kRoadGraphZoom;
  final xf = (p.longitude + 180) / 360 * n;
  final lat = p.latitude * math.pi / 180;
  final yf = (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * n;
  return (xf.floor(), yf.floor());
}

const _classesV1 = <String?>[
  'bundesstrasse',
  'landstrasse',
  'zufahrt',
  'forstweg',
  'wanderweg',
  'stufen',
  'radweg',
  'fussweg',
  null,
];
