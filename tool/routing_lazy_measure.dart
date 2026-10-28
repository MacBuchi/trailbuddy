// Messung, kein Test (#381): Wie viele Kacheln des Rahmens erreichen die
// Suchen einer Planung wirklich? Nur was keine Suche erreicht, könnte ein
// Nachladen beim Suchen einsparen — und was die Suchen ÜBER den Rahmen
// hinaus erreichen würden, müsste es zusätzlich laden.
//
// Läuft NICHT in CI (kein `_test.dart`), sondern von Hand, über echte
// Kacheln vom Host, die `tool/routing_tiles.py sample` geholt hat — mit
// 15 × 15 Kacheln, damit die Reichweite Platz hat:
//   python3 tool/routing_tiles.py sample --out DIR --size 15
//   TB_TILES_DIR=DIR flutter test tool/routing_lazy_measure.dart
// Die Zahlen gehören nach docs/routing-messung.md („#381").
//
// Je Rahmen backt das Skript alle Kacheln zu Stücken und setzt sie zum
// Graphen zusammen (`routing_tile.dart`, der Weg des Planers seit
// 0.136.0). Dann je Fall: Start in der Mitte, Trails mit Anfang und Ende
// auf zufälligen Knoten der größten Komponente in [radius] um den Start,
// der Rahmen der App daraus (`roadGraphTiles(Box, kTrailHeadMarginM)`,
// ohne Verbinder — der echte Rahmen ist eher größer). Gesucht wird wie
// `planLoop` (`_Planner._search`): je eine begrenzte Suche vom Start und
// von jedem Trail-Ende, Grenze das Zeitbudget in Kosten. Gezählt wird die
// Vereinigung der Kacheln, in denen eine Suche einen Knoten erreicht hat
// — einmal im Rahmen, einmal darüber hinaus (gesucht wird auf dem ganzen
// 15 × 15-Graphen).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/offline_areas/height_tiles.dart';
import 'package:trailbuddy/features/routing/road_graph_loader.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';
import 'package:trailbuddy/features/routing/route_search.dart';
import 'package:trailbuddy/features/routing/routing_tile.dart';
import 'package:trailbuddy/features/routing/trail_head_route.dart' show kTrailHeadMarginM;

const _z = 13;

void main() {
  final dir = Platform.environment['TB_TILES_DIR'];
  test('Nachladen beim Suchen: erreichte Kacheln je Planung', () {
    if (dir == null) {
      // ignore: avoid_print
      print('TB_TILES_DIR fehlt — erst `python3 tool/routing_tiles.py sample --out DIR --size 15`.');
      return;
    }
    final frames = Directory(dir).listSync().whereType<Directory>().toList()..sort((a, b) => a.path.compareTo(b.path));
    _out('| Rahmen | Fall | Rahmen-Kacheln | erreicht im Rahmen | erreicht darüber hinaus | Suchen | Zusammensetzen ganz / erreicht |');
    _out('|---|---|---:|---:|---:|---:|---:|');
    for (final f in frames) {
      _measure(_Frame.read(f));
    }
  }, timeout: const Timeout(Duration(minutes: 60)));
}

// ignore: avoid_print
void _out(String s) => print(s);

class _Frame {
  _Frame(this.name, this.tiles, this.roads, this.ways, this.heights);

  final String name;
  final List<(int, int)> tiles;
  final Map<(int, int), Uint8List> roads, ways;
  final Map<(int, int), HeightTile> heights;

  static _Frame read(Directory d) {
    final meta = jsonDecode(File('${d.path}/frame.json').readAsStringSync()) as Map<String, dynamic>;
    final tiles = [for (final t in meta['tiles'] as List) ((t as List)[0] as int, t[1] as int)];
    Map<(int, int), Uint8List> load(String kind, String ext) => {
          for (final t in tiles)
            if (File('${d.path}/$kind/${t.$1}_${t.$2}.$ext').existsSync())
              t: File('${d.path}/$kind/${t.$1}_${t.$2}.$ext').readAsBytesSync(),
        };
    final h = load('heights', 'bin');
    return _Frame(meta['frame'] as String, tiles, load('roads', 'mvt'), load('ways', 'mvt'),
        {for (final e in h.entries) e.key: HeightTile.decode(e.value)});
  }

  HeightTiles heightsAround((int, int) t) => HeightTiles({
        for (var dx = -1; dx <= 1; dx++)
          for (var dy = -1; dy <= 1; dy++)
            HeightTiles.keyOf(t.$1 + dx, t.$2 + dy): ?heights[(t.$1 + dx, t.$2 + dy)],
      });

  List<RoadTileBytes> waysAround((int, int) t) => [
        for (var dx = -1; dx <= 1; dx++)
          for (var dy = -1; dy <= 1; dy++)
            if (ways[(t.$1 + dx, t.$2 + dy)] case final b?) (tile: (z: _z, x: t.$1 + dx, y: t.$2 + dy), bytes: b)
      ];

  (int, int) get centre {
    final xs = tiles.map((t) => t.$1).toList()..sort();
    final ys = tiles.map((t) => t.$2).toList()..sort();
    return (xs[xs.length ~/ 2], ys[ys.length ~/ 2]);
  }
}

double _tileLat(num y) {
  final n = math.pi - 2 * math.pi * y / (1 << _z);
  return 180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
}

(int, int) _tileOf(LatLng p) {
  final n = 1 << _z;
  final x = ((p.longitude + 180) / 360 * n).floor();
  final r = p.latitude * math.pi / 180;
  final y = ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n).floor();
  return (x, y);
}

void _measure(_Frame f) {
  final present = [for (final t in f.tiles) if (f.roads.containsKey(t)) t];
  final lat0 = _tileLat(f.centre.$2 + 0.5);

  // Backen je Kachel wie der Rechen-Isolate (Höhen und Wege-Archiv der
  // Nachbarn dazu), dann dekodiert bereithalten.
  final pieces = <(int, int), DecodedPiece>{};
  for (final t in present) {
    final g = buildRoadGraphFrom(
      roads: [(tile: (z: _z, x: t.$1, y: t.$2), bytes: f.roads[t]!)],
      ways: f.waysAround(t),
      heights: f.heightsAround(t),
      lat0: _tileLat(t.$2 + 0.5),
    ).graph;
    pieces[t] = decodePiece(encodePiece(g, t.$1, t.$2))!;
  }
  final g = stitchPieces([for (final t in present) pieces[t]!], lat0).graph;

  // Kachel je Knoten, einmal.
  final tileOfNode = [for (final p in g.nodeLatLng) _tileOf(p)];
  final comp = <int>{for (final ei in g.components().first) ...[g.edgeA(ei), g.edgeB(ei)]}.toList()..sort();
  final c = f.centre;
  final mid = LatLng(_tileLat(c.$2 + 0.5), (c.$1 + 0.5) / (1 << _z) * 360 - 180);
  final start = g.nearestNode(g.proj.xy(mid), 2000)!;
  final startXy = g.nodes[start];

  int stitchMs(Iterable<(int, int)> ts) {
    final list = [for (final t in ts) ?pieces[t]];
    var best = 1 << 30;
    for (var i = 0; i < 3; i++) {
      final sw = Stopwatch()..start();
      stitchPieces(list, lat0);
      best = math.min(best, sw.elapsedMilliseconds);
    }
    return best;
  }

  for (final (count, radiusM, profile, hours) in const [
    (12, 5000.0, RiderProfile.bio, 2),
    (12, 5000.0, RiderProfile.bio, 3),
    (30, 8000.0, RiderProfile.bio, 3),
    (30, 12000.0, RiderProfile.bio, 3),
    (40, 12000.0, RiderProfile.bio, 5),
    (60, 12000.0, RiderProfile.ebike, 5),
  ]) {
    final rnd = math.Random(381 + count + radiusM.round() + hours);
    final near = [
      for (final n in comp)
        if (g.nodes[n].distanceTo(startXy) < radiusM) n
    ];
    final tails = <int>[];
    final points = <LatLng>[g.nodeLatLng[start]];
    while (tails.length < count) {
      final head = near[rnd.nextInt(near.length)];
      final a = rnd.nextDouble() * 2 * math.pi, d = 1000 + rnd.nextDouble() * 1000;
      final h = g.nodes[head];
      final tail = g.nearestNode(math.Point(h.x + d * math.cos(a), h.y + d * math.sin(a)), 300);
      if (tail == null || tail == head) continue;
      tails.add(tail);
      points
        ..add(g.nodeLatLng[head])
        ..add(g.nodeLatLng[tail]);
    }
    final frame = {for (final t in roadGraphTiles(LatBox.of(points), kTrailHeadMarginM)) (t.x, t.y)};

    final costs = EdgeCosts(g, profile);
    final reached = <(int, int)>{};
    final sources = [start, ...tails];
    for (final s in sources) {
      final r = dijkstra(g, s, profile, limit: hours * 3600.0, costs: costs);
      for (var n = 0; n < g.nodes.length; n++) {
        if (r.reached(n)) reached.add(tileOfNode[n]);
      }
    }
    final inFrame = reached.where(frame.contains).toSet();
    final beyond = reached.length - inFrame.length;
    // Rand des Beispiels erreicht ⇒ „darüber hinaus" ist eine Untergrenze.
    final xs = f.tiles.map((t) => t.$1), ys = f.tiles.map((t) => t.$2);
    final edge = reached.any((t) =>
        t.$1 == xs.reduce(math.min) || t.$1 == xs.reduce(math.max) || t.$2 == ys.reduce(math.min) || t.$2 == ys.reduce(math.max));
    final pct = (100 * inFrame.length / frame.length).round();
    _out('| ${f.name} | $count Trails in ${(radiusM / 1000).round()} km, ${profile.name} $hours h '
        '| ${frame.length} | ${inFrame.length} ($pct %) | $beyond${edge ? '+' : ''} | ${sources.length} '
        '| ${stitchMs(frame)} / ${stitchMs(inFrame)} ms |');
  }
}
