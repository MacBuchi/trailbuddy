// Messung, kein Test (#380): Was kostet ein vorgebackener Graph je
// z13-Kachel an Bytes, und wie schnell setzt das Telefon daraus den
// Graphen eines Rahmens zusammen — gegen den Bau von heute aus den
// Zeichenkacheln (Konzept-Routing 11)?
//
// Läuft NICHT in CI (kein `_test.dart`), sondern von Hand, über echte
// Kacheln vom Host, die `tool/routing_tiles.py sample` geholt hat:
//   python3 tool/routing_tiles.py sample --out DIR
//   TB_TILES_DIR=DIR flutter test tool/routing_tiles_measure.dart
// Die Zahlen gehören nach docs/routing-messung.md („#380").
//
// Drei Wege über dieselben Kacheln:
//  1. HEUTE: `buildRoadGraphFrom` über alle Kacheln des Rahmens — was der
//     Rechen-Isolate des Planers je Planung tut.
//  2. BACKEN (Workflow oder Gerät, Konzept-Routing 11.4): je Kachel derselbe Bau über NUR ihre Wege
//     (Höhen und Wege-Archiv der Nachbarn dazu), dann in ein kompaktes
//     Binärformat ([_encode]); tote Enden am Kachelrand werden markiert.
//  3. ZUSAMMENSETZEN (das Telefon): die Stücke dekodieren, Knoten über
//     ihre Mikrograd teilen ([RoadGraph.node]), nur die markierten Enden
//     an den Nachbarn binden (dieselbe 2-m-Regel wie heute).
// Danach vergleicht es die beiden Graphen (Zahl, Länge, Zusammenhang,
// Höhen) und die Kosten von 40 Suchen zwischen festen Knotenpaaren.
//
// Seit 0.136.0 liegen Format, Backen und Zusammensetzen in lib/
// (`routing_tile.dart`, #380); dieses Skript ruft sie, statt eine eigene
// Kopie zu führen, und misst nur noch. Es liegt nicht unter test/: Dort
// löste es den Version Guard aus, obwohl es nie ins Binary geht
// (`flutter test` nimmt die Datei auch hier).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/offline_areas/height_tiles.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/road_graph_loader.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';
import 'package:trailbuddy/features/routing/route_search.dart';
import 'package:trailbuddy/features/routing/routing_tile.dart';

const _z = 13;

void main() {
  final dir = Platform.environment['TB_TILES_DIR'];
  test('Routing-Kacheln: Größe und Zusammensetzen', () {
    if (dir == null) {
      // ignore: avoid_print
      print('TB_TILES_DIR fehlt — erst `python3 tool/routing_tiles.py sample --out DIR`.');
      return;
    }
    final frames = Directory(dir).listSync().whereType<Directory>().toList()..sort((a, b) => a.path.compareTo(b.path));
    var warm = false;
    for (final f in frames) {
      final frame = _Frame.read(f);
      if (!warm) {
        // Code warm (JIT): ein kleiner Rahmen auf beiden Wegen.
        _measure(frame.sub(3), quiet: true);
        warm = true;
      }
      _measure(frame);
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}

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

  /// Die mittleren [n] × [n] Kacheln.
  _Frame sub(int n) {
    final xs = tiles.map((t) => t.$1).toSet().toList()..sort();
    final ys = tiles.map((t) => t.$2).toSet().toList()..sort();
    final x0 = xs[(xs.length - n) ~/ 2], y0 = ys[(ys.length - n) ~/ 2];
    final keep = [
      for (final t in tiles)
        if (t.$1 >= x0 && t.$1 < x0 + n && t.$2 >= y0 && t.$2 < y0 + n) t
    ];
    return _Frame('$name-$n', keep, roads, ways, heights);
  }

  RoadTileBytes road((int, int) t) => (tile: (z: _z, x: t.$1, y: t.$2), bytes: roads[t]!);

  HeightTiles heightsAround(Iterable<(int, int)> ts) => HeightTiles({
        for (final t in ts)
          for (var dx = -1; dx <= 1; dx++)
            for (var dy = -1; dy <= 1; dy++)
              HeightTiles.keyOf(t.$1 + dx, t.$2 + dy): ?heights[(t.$1 + dx, t.$2 + dy)],
      });

  List<RoadTileBytes> waysAround(Iterable<(int, int)> ts) {
    final want = {
      for (final t in ts)
        for (var dx = -1; dx <= 1; dx++)
          for (var dy = -1; dy <= 1; dy++) (t.$1 + dx, t.$2 + dy)
    };
    return [
      for (final w in want)
        if (ways[w] case final b?) (tile: (z: _z, x: w.$1, y: w.$2), bytes: b)
    ];
  }

  double get lat0 {
    final ys = tiles.map((t) => t.$2).toList()..sort();
    return _tileLat(ys[ys.length ~/ 2] + 0.5);
  }
}

double _tileLat(num y) {
  final n = math.pi - 2 * math.pi * y / (1 << _z);
  return 180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
}

void _measure(_Frame f, {bool quiet = false}) {
  void out(String s) {
    // ignore: avoid_print
    if (!quiet) print(s);
  }

  final present = [for (final t in f.tiles) if (f.roads.containsKey(t)) t];
  final sw = Stopwatch()..start();

  // Jede Zeit ist das Beste aus [runs] Läufen — einzelne Läufe streuen
  // am Rechner um das Doppelte (GC).
  final runs = quiet ? 1 : 3;

  // 1. Heute: ein Bau über den ganzen Rahmen.
  late RoadGraph today;
  var todayMs = 1 << 30;
  for (var i = 0; i < runs; i++) {
    sw.reset();
    today = buildRoadGraphFrom(
      roads: [for (final t in present) f.road(t)],
      ways: f.waysAround(present).where((w) => present.contains((w.tile.x, w.tile.y))).toList(),
      heights: f.heightsAround(present),
      lat0: f.lat0,
    ).graph;
    todayMs = math.min(todayMs, sw.elapsedMilliseconds);
  }

  // 2. Backen je Kachel.
  final pieces = <(int, int), Uint8List>{};
  final bakeMs = <int>[];
  for (final t in present) {
    sw.reset();
    final g = buildRoadGraphFrom(
      roads: [f.road(t)],
      ways: f.waysAround([t]),
      heights: f.heightsAround([t]),
      lat0: _tileLat(t.$2 + 0.5),
    ).graph;
    pieces[t] = encodePiece(g, t.$1, t.$2);
    bakeMs.add(sw.elapsedMilliseconds);
  }

  // 3. Zusammensetzen.
  late RoadGraph stitched;
  var decodeMs = 1 << 30, stitchMs = 1 << 30;
  for (var i = 0; i < runs; i++) {
    sw.reset();
    final decoded = [for (final t in present) decodePiece(pieces[t]!)!];
    final d = sw.elapsedMilliseconds;
    stitched = stitchPieces(decoded, f.lat0).graph;
    if (sw.elapsedMilliseconds < stitchMs) {
      stitchMs = sw.elapsedMilliseconds;
      decodeMs = d;
    }
  }

  // Größen.
  int sumOf(Iterable<Uint8List> xs) => xs.fold(0, (s, b) => s + b.length);
  final raw = sumOf(pieces.values);
  final gz = sumOf([for (final b in pieces.values) Uint8List.fromList(gzip.encode(b))]);
  final roadsGz = sumOf([for (final t in present) Uint8List.fromList(gzip.encode(f.roads[t]!))]);
  final waysGz = sumOf([
    for (final t in present)
      if (f.ways[t] case final b?) Uint8List.fromList(gzip.encode(b))
  ]);
  final heightsB = present.where(f.heights.containsKey).length * kHeightGrid * kHeightGrid * 2;
  final sizes = [for (final b in pieces.values) gzip.encode(b).length]..sort();
  String kb(int b) => (b / 1024).toStringAsFixed(0);
  String mb(int b) => (b / (1 << 20)).toStringAsFixed(2);
  bakeMs.sort();

  out('## ${f.name}: ${present.length} Kacheln');
  out('| | heute | gestückelt |');
  out('|---|---|---|');
  out('| Bau / Zusammensetzen (bester von $runs) | $todayMs ms | $stitchMs ms (davon dekodieren $decodeMs ms) |');
  out('| Knoten | ${today.nodes.length} | ${stitched.nodes.length} |');
  out('| Kanten | ${today.edges.length} | ${stitched.edges.length} |');
  out('| Länge | ${(today.totalLength / 1000).toStringAsFixed(1)} km | ${(stitched.totalLength / 1000).toStringAsFixed(1)} km |');
  out('| größte Komponente | ${(100 * today.largestComponentShare).toStringAsFixed(2)} % | ${(100 * stitched.largestComponentShare).toStringAsFixed(2)} % |');
  out('| Kanten ohne Höhen | ${today.edgesWithoutHeights} | ${stitched.edgesWithoutHeights} |');
  out('| Anstieg gesamt | ${_sum(today, (e) => e.gain + e.loss).toStringAsFixed(0)} m | ${_sum(stitched, (e) => e.gain + e.loss).toStringAsFixed(0)} m |');
  out('| Kanten mit Wegegüte | ${today.edges.where((e) => e.way != null).length} | ${stitched.edges.where((e) => e.way != null).length} |');
  out('');
  out('Größe: Routing-Kacheln ${mb(raw)} MB roh, **${mb(gz)} MB gzip** '
      '(je Kachel Median ${kb(sizes[sizes.length ~/ 2])} KB, 90 % ${kb(sizes[sizes.length * 9 ~/ 10])} KB, '
      'größte ${kb(sizes.last)} KB); zum Vergleich Kartenkacheln gzip ${mb(roadsGz)} MB, '
      'Wege-Archiv ${mb(waysGz)} MB, Höhen ${mb(heightsB)} MB.');
  out('Innere Linienpunkte ${present.isEmpty ? 0 : today.edges.fold<int>(0, (s, e) => s + e.points.length - 2)}.');
  out('Backen je Kachel: Median ${bakeMs[bakeMs.length ~/ 2]} ms, 90 % ${bakeMs[bakeMs.length * 9 ~/ 10]} ms, '
      'Summe ${(bakeMs.fold(0, (s, v) => s + v) / 1000).toStringAsFixed(1)} s.');
  out(_compareEdges(today, stitched));
  out(_compareSearches(today, stitched));
  out('');
}

/// Kante für Kante: dieselben Enden (Mikrograd) und Punktzahl gelten als
/// dieselbe Kante; dann Güte und Anstieg vergleichen.
String _compareEdges(RoadGraph a, RoadGraph b) {
  String key(GraphEdge e) {
    final p = e.points;
    final x = '${_micro(p.first.longitude)},${_micro(p.first.latitude)}';
    final y = '${_micro(p.last.longitude)},${_micro(p.last.latitude)}';
    return '${x.compareTo(y) < 0 ? '$x $y' : '$y $x'} ${p.length} ${e.cls.index}';
  }

  final bm = <String, GraphEdge>{for (final e in b.edges) key(e): e};
  var same = 0, way = 0, wayLost = 0, climb = 0;
  var lostM = 0.0, gotM = 0.0;
  for (final e in a.edges) {
    if (e.way != null) gotM += e.length;
  }
  for (final e in a.edges) {
    final o = bm[key(e)];
    if (o == null) continue;
    same++;
    if (o.way != e.way) {
      way++;
      if (o.way == null) {
        wayLost++;
        lostM += e.length;
      }
    }
    if ((o.gain + o.loss - e.gain - e.loss).abs() > 0.5) climb++;
  }
  return 'Kanten wiedergefunden: $same von ${a.edges.length}; davon andere Wegegüte $way '
      '($wayLost ohne, ${(100 * lostM / gotM).toStringAsFixed(2)} % der benannten Länge), anderer Anstieg (> 0,5 m) $climb.';
}

double _sum(RoadGraph g, double Function(GraphEdge e) f) => g.edges.fold(0.0, (s, e) => s + f(e));

/// 40 Suchen zwischen festen Knotenpaaren der größten Komponente von
/// HEUTE; im gestückelten Graphen vom nächsten Knoten (≤ 5 m) aus.
String _compareSearches(RoadGraph a, RoadGraph b) {
  final comp = a.components().first;
  final nodes = <int>{for (final ei in comp) a.edgeA(ei)}.toList()..sort();
  final rnd = math.Random(380);
  final diffs = <double>[];
  var missing = 0;
  for (var i = 0; i < 40; i++) {
    final s = nodes[rnd.nextInt(nodes.length)], t = nodes[rnd.nextInt(nodes.length)];
    final ca = dijkstra(a, s, RiderProfile.bio, target: t).costTo(t);
    final sb = b.nearestNode(a.nodes[s], 5), tb = b.nearestNode(a.nodes[t], 5);
    final cb = sb == null || tb == null ? null : dijkstra(b, sb, RiderProfile.bio, target: tb).costTo(tb);
    if (ca == null || cb == null) {
      missing++;
      continue;
    }
    diffs.add(ca == 0 ? 0 : (cb - ca).abs() / ca);
  }
  diffs.sort();
  String pct(double v) => '${(100 * v).toStringAsFixed(2)} %';
  return 'Suchen (40 Paare, Bio): Kosten-Abweichung Median ${pct(diffs[diffs.length ~/ 2])}, '
      '90 % ${pct(diffs[diffs.length * 9 ~/ 10])}, größte ${pct(diffs.last)}'
      '${missing > 0 ? ', $missing ohne Weg in einem der beiden' : ''}.';
}

int _micro(double deg) => (deg * 1e6).round();
