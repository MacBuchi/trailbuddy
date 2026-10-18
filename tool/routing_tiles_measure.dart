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
// Der Prototyp liegt bewusst hier, nicht in lib/: Das Format ist ein
// Vorschlag, gebaut wird erst nach den Entscheidungen des Betreibers.
// Und nicht unter test/: Dort löste er den Version Guard aus, obwohl er
// nie ins Binary geht (`flutter test` nimmt die Datei auch hier).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/offline_areas/height_tiles.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/road_graph_loader.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';
import 'package:trailbuddy/features/routing/route_search.dart';

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

double _tileLon(num x) => x / (1 << _z) * 360 - 180;

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
    pieces[t] = _encode(g, t);
    bakeMs.add(sw.elapsedMilliseconds);
  }

  final parts = Map.of(_parts);
  _parts.clear();
  final pixelEdges = _pixelEdges;
  _pixelEdges = 0;

  // 3. Zusammensetzen.
  late RoadGraph stitched;
  var decodeMs = 1 << 30, stitchMs = 1 << 30;
  for (var i = 0; i < runs; i++) {
    sw.reset();
    final decoded = [for (final t in present) _decode(pieces[t]!)];
    final d = sw.elapsedMilliseconds;
    stitched = _stitch(decoded, f.lat0);
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
  out('Anteile roh: ${[for (final e in parts.entries) '${e.key} ${mb(e.value)} MB'].join(', ')}; '
      'Kanten mit Punkten in Pixeln $pixelEdges; innere Linienpunkte ${present.isEmpty ? 0 : today.edges.fold<int>(0, (s, e) => s + e.points.length - 2)}.');
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

// ------------------------------------------------------------- Format
//
// Ein Stück je Kachel, alles Varints (ZigZag, wo es negativ wird):
//   Kopf: Format (2), Kachel x, y, Zahl der Knoten
//   Knoten: Mikrograd Länge/Breite, als Differenz zum vorigen
//   Randknoten: Zahl, dann Nummern als Differenz — tote Enden ≤ 2 m vom
//     Kachelrand, die erst beim Zusammensetzen gebunden werden
//   Kanten: Zahl, dann je Kante ein Kopf (Klasse in 4 Bit, dann je ein
//     Bit Einbahn, Höhen, und welche der seltenen Felder folgen), a als
//     Differenz zum b der vorigen Kante, b als Differenz zu a, Anstieg und
//     Abstieg in Zentimetern (die Richtung von „bergab" bleibt erhalten,
//     [_cmLoss]); nur wenn gesetzt: Ebene, Wegegüte, uphill, steil auf/ab
//     und Steilgewicht auf/ab in Dezimetern, Tragen × 1000; dann die Zahl
//     der inneren Punkte und die Punkte als Mikrograd-Differenz ab Knoten a
// Länge und Meter-Lage rechnet das Telefon beim Einfügen selbst (eine
// Projektion je Rahmen); Kosten stehen NICHT darin — ein anderes Profil,
// ein anderer Stil, eine geänderte Zahl im Kostenmodell braucht so keinen
// neuen Bau, nur eine andere Ableitung der Klasse oder Güte.

/// Bytes je Teil des Formats, über alle Stücke (für den Bericht).
final _parts = <String, int>{};

class _Writer {
  final _b = BytesBuilder(copy: false);
  int get length => _b.length;
  void mark(String part, int from) => _parts[part] = (_parts[part] ?? 0) + _b.length - from;
  void u(int v) {
    while (v >= 0x80) {
      _b.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    _b.addByte(v);
  }

  void s(int v) => u(v >= 0 ? v << 1 : ((-v) << 1) - 1);
  Uint8List done() => _b.takeBytes();
}

class _Reader {
  _Reader(this._d);
  final Uint8List _d;
  var _i = 0;
  int u() {
    var v = 0, shift = 0;
    while (true) {
      final b = _d[_i++];
      v |= (b & 0x7f) << shift;
      if (b < 0x80) return v;
      shift += 7;
    }
  }

  int s() {
    final v = u();
    return v.isEven ? v >> 1 : -((v + 1) >> 1);
  }
}

int _micro(double deg) => (deg * 1e6).round();

const _extent = 4096;
var _pixelEdges = 0;

/// Der Punkt in Pixeln der Kachel [t] (Ausmaß [_extent]) — null, wenn er
/// nicht auf dem Raster liegt (mit [exact] false: gerundet).
(int, int)? _pixel(LatLng p, (int, int) t, {bool exact = true}) {
  final n = 1 << _z;
  final tx = (p.longitude + 180) / 360 * n;
  final r = p.latitude * math.pi / 180;
  final ty = (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n;
  final fx = (tx - t.$1) * _extent, fy = (ty - t.$2) * _extent;
  final ix = fx.round(), iy = fy.round();
  if (exact && ((fx - ix).abs() > 1e-3 || (fy - iy).abs() > 1e-3)) return null;
  return (ix, iy);
}

LatLng _fromPixel(int ix, int iy, (int, int) t) {
  final n = 1 << _z;
  final tx = t.$1 + ix / _extent, ty = t.$2 + iy / _extent;
  final lat = math.atan(_sinh(math.pi * (1 - 2 * ty / n))) * 180 / math.pi;
  return LatLng(lat, tx / n * 360 - 180);
}

double _sinh(double v) => (math.exp(v) - math.exp(-v)) / 2;
int _dm(double m) => (m * 10).round();
int _cm(double m) => (m * 100).round();

/// Der Abstieg in Zentimetern — aber nie so gerundet, dass „bergab"
/// kippt: `edgeTimeS` nimmt die Abfahrtsgeschwindigkeit, sobald der
/// Abstieg den Anstieg übersteigt, auch um Millimeter (im ersten Lauf
/// dieser Messung gefunden: auf Dezimeter gerundet fuhren flache Straßen
/// mit 9 mm Abstieg plötzlich mit Flachgeschwindigkeit, Suchen wichen
/// bis 2 % ab).
int _cmLoss(GraphEdge e) {
  final g = _cm(e.gain), l = _cm(e.loss);
  return e.loss > e.gain && l <= g ? g + 1 : l;
}

Uint8List _encode(RoadGraph g, (int, int) t) {
  final w = _Writer()
    ..u(2)
    ..u(t.$1)
    ..u(t.$2)
    ..u(g.nodes.length);
  var at = w.length;
  var plon = _micro(_tileLon(t.$1)), plat = _micro(_tileLat(t.$2));
  for (final p in g.nodeLatLng) {
    final lon = _micro(p.longitude), lat = _micro(p.latitude);
    w
      ..s(lon - plon)
      ..s(lat - plat);
    plon = lon;
    plat = lat;
  }
  // Randknoten: tote Enden nahe am Rand der Kachel.
  final west = _tileLon(t.$1), east = _tileLon(t.$1 + 1);
  final north = _tileLat(t.$2), south = _tileLat(t.$2 + 1);
  final border = <int>[];
  for (var n = 0; n < g.nodes.length; n++) {
    if (g.degree(n) != 1) continue;
    final p = g.nodeLatLng[n];
    final mLon = 111320 * math.cos(p.latitude * math.pi / 180);
    final d = [
      (p.longitude - west) * mLon,
      (east - p.longitude) * mLon,
      (north - p.latitude) * 111320,
      (p.latitude - south) * 111320,
    ].reduce(math.min);
    if (d <= kGraphJoinM + 0.5) border.add(n);
  }
  w.mark('Knoten', at);
  at = w.length;
  w.u(border.length);
  var prev = 0;
  for (final n in border) {
    w.u(n - prev);
    prev = n;
  }
  w.mark('Randknoten', at);
  w.u(g.edges.length);
  var prevB = 0;
  for (final e in g.edges) {
    at = w.length;
    final steep = e.steepUp + e.steepDown + e.steepWUp + e.steepWDown > 0;
    final carry = (e.carry * 1000).round();
    w
      ..u(e.cls.index |
          (e.oneway ? 1 << 4 : 0) |
          (e.hasHeights ? 1 << 5 : 0) |
          (e.level != 0 ? 1 << 6 : 0) |
          (e.way != null ? 1 << 7 : 0) |
          (e.uphill != null ? 1 << 8 : 0) |
          (steep ? 1 << 9 : 0) |
          (carry != 1000 ? 1 << 10 : 0))
      ..s(e.a - prevB)
      ..s(e.b - e.a)
      ..u(_cm(e.gain))
      ..u(_cmLoss(e));
    prevB = e.b;
    if (e.level != 0) w.s(e.level);
    if (e.way case final v?) w.u(v);
    if (e.uphill case final v?) w.u(v);
    if (steep) {
      w
        ..u(_dm(e.steepUp))
        ..u(_dm(e.steepDown))
        ..u(_dm(e.steepWUp))
        ..u(_dm(e.steepWDown));
    }
    if (carry != 1000) w.u(carry);
    w.mark('Kantenwerte', at);
    at = w.length;
    final pts = e.points;
    w.u(pts.length - 2);
    // Innere Punkte liegen auf dem Pixelraster der Kartenkachel (Ausmaß
    // 4096) — in Pixeln verlustfrei und kürzer als in Mikrograd. Eine
    // Kennung davor sagt, ob es für die ganze Kante gilt (1), sonst
    // Mikrograd (0).
    final pix = [for (var i = 1; i < pts.length - 1; i++) _pixel(pts[i], t)];
    if (pix.isEmpty) {
      // keine inneren Punkte, keine Kennung
    } else if (pix.every((p) => p != null)) {
      _pixelEdges++;
      w.u(1);
      // Bezug ist Knoten a, wie ihn der Leser kennt: in Mikrograd.
      final a = LatLng(_micro(pts.first.latitude) / 1e6, _micro(pts.first.longitude) / 1e6);
      var (px, py) = _pixel(a, t, exact: false)!;
      for (final p in pix) {
        w
          ..s(p!.$1 - px)
          ..s(p.$2 - py);
        (px, py) = p;
      }
    } else {
      w.u(0); // Kennung: Mikrograd folgen
      var lon = _micro(pts.first.longitude), lat = _micro(pts.first.latitude);
      for (var i = 1; i < pts.length - 1; i++) {
        final x = _micro(pts[i].longitude), y = _micro(pts[i].latitude);
        w
          ..s(x - lon)
          ..s(y - lat);
        lon = x;
        lat = y;
      }
    }
    w.mark('Linienpunkte', at);
  }
  return w.done();
}

typedef _Edge = ({
  int a,
  int b,
  int flags,
  int level,
  int way,
  int uphill,
  List<int> climb,
  int carry,
  List<LatLng> inner,
});

typedef _Piece = ({List<LatLng> nodes, List<int> border, List<_Edge> edges});

_Piece _decode(Uint8List bytes) {
  final r = _Reader(bytes);
  if (r.u() != 2) throw const FormatException('Format');
  final x = r.u(), y = r.u();
  final count = r.u();
  var lon = _micro(_tileLon(x)), lat = _micro(_tileLat(y));
  final nodes = <LatLng>[];
  for (var i = 0; i < count; i++) {
    lon += r.s();
    lat += r.s();
    nodes.add(LatLng(lat / 1e6, lon / 1e6));
  }
  final border = <int>[];
  var prev = 0;
  for (var i = r.u(); i > 0; i--) {
    prev += r.u();
    border.add(prev);
  }
  final edges = <_Edge>[];
  var prevB = 0;
  for (var i = r.u(); i > 0; i--) {
    final head = r.u();
    final a = prevB + r.s();
    final b = a + r.s();
    prevB = b;
    final gain = r.u(), loss = r.u();
    final level = head & 1 << 6 != 0 ? r.s() : 0;
    final way = head & 1 << 7 != 0 ? r.u() : -1;
    final uphill = head & 1 << 8 != 0 ? r.u() : -1;
    final climb = [gain, loss, ...head & 1 << 9 != 0 ? [r.u(), r.u(), r.u(), r.u()] : const [0, 0, 0, 0]];
    final carry = head & 1 << 10 != 0 ? r.u() : 1000;
    final flags = (head & 15) | (head & 1 << 4 != 0 ? 16 : 0) | (head & 1 << 5 != 0 ? 32 : 0);
    final inner = <LatLng>[];
    final count = r.u();
    if (count > 0 && r.u() == 1) {
      var (px, py) = _pixel(nodes[a], (x, y), exact: false)!;
      for (var k = count; k > 0; k--) {
        px += r.s();
        py += r.s();
        inner.add(_fromPixel(px, py, (x, y)));
      }
    } else {
      var plon = _micro(nodes[a].longitude), plat = _micro(nodes[a].latitude);
      for (var k = count; k > 0; k--) {
        plon += r.s();
        plat += r.s();
        inner.add(LatLng(plat / 1e6, plon / 1e6));
      }
    }
    edges.add((
      a: a,
      b: b,
      flags: flags,
      level: level,
      way: way,
      uphill: uphill,
      climb: climb,
      carry: carry,
      inner: inner,
    ));
  }
  return (nodes: nodes, border: border, edges: edges);
}

RoadGraph _stitch(List<_Piece> pieces, double lat0) {
  final g = RoadGraph(lat0);
  final border = <int>[];
  for (final p in pieces) {
    final ids = [for (final n in p.nodes) g.node(n)];
    for (final e in p.edges) {
      final ei = g.addEdge(ids[e.a], ids[e.b], WayClass.values[e.flags & 15], e.flags & 16 != 0,
          [p.nodes[e.a], ...e.inner, p.nodes[e.b]],
          level: e.level);
      g.edges[ei]
        ..hasHeights = e.flags & 32 != 0
        ..way = e.way < 0 ? null : e.way
        ..uphill = e.uphill < 0 ? null : e.uphill
        ..gain = e.climb[0] / 100
        ..loss = e.climb[1] / 100
        ..steepUp = e.climb[2] / 10
        ..steepDown = e.climb[3] / 10
        ..steepWUp = e.climb[4] / 10
        ..steepWDown = e.climb[5] / 10
        ..carry = e.carry / 1000;
    }
    for (final n in p.border) {
      border.add(ids[n]);
    }
  }
  // Dieselbe Regel wie `_joinDeadEnds` beim Bau, nur für die Randknoten:
  // ein totes Ende ≤ 2 m an den nächsten anderen Weg.
  for (final n in border) {
    if (g.degree(n) != 1) continue;
    var target = g.nearestNode(g.nodes[n], kGraphJoinM, exclude: n);
    if (target == null) {
      final hit = g.nearest(g.nodeLatLng[n], kGraphJoinM, excludeEdges: g.adj[n].toSet());
      if (hit == null) continue;
      target = g.splitEdge(hit.edge, hit.seg, hit.at);
    }
    if (target != n) {
      final ei =
          g.addEdge(n, target, g.edges[g.adjFirst(n) >> 1].cls, false, [g.nodeLatLng[n], g.nodeLatLng[target]]);
      g.edges[ei].hasHeights = true; // ≤ 2 m, flach
    }
  }
  g.compact();
  return g;
}
