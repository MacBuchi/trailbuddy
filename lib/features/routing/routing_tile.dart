// Vorgebackene Routing-Kacheln (#380, Konzept-Routing 11): je z13-Kachel
// das fertige Stück des Graphen, gebaut von DENSELBEN Funktionen wie der
// Graph eines Rahmens ([buildRoadGraph], [addClimbsFrom],
// [addWayQuality]) — nur über die Wege der einen Kachel. Der Planer setzt
// den Graphen aus solchen Stücken zusammen ([stitchPieces]), statt ihn je
// Planung aus den Zeichenkacheln zu bauen; gemessen 8- bis 10-mal
// schneller, dieselben Wege (`docs/routing-messung.md`, „#380").
//
// Gebacken wird auf dem Gerät (Betreiber, 2026-10-18: „für alle offline
// Kacheln … auf dem Handy direkt"), im Rechen-Isolate des Planers, und
// das Stück geht in den Kachelspeicher der Region (`TileLayer.routing`).
// Was NICHT hineingehört (11.2): Kosten (Rad, Stil, Vorlieben,
// Kalibrierung rechnen auf dem Gerät aus Klasse, Güte und Höhen), Trails,
// Start, Ziel — nur öffentliche Daten Dritter (OSM, Copernicus).
//
// Rein: keine Widgets, kein Riverpod, kein Isolate, kein Speicher — im
// Browser läuft dieselbe Datei an Ort und Stelle.
//
// **Das Format** (11.3), alles Varints, ZigZag wo es negativ wird:
//   Kopf: Format, Fassung der Bauregeln, Kachel x, y, Zahl der Knoten
//   Knoten: Mikrograd Länge/Breite als Differenz zum vorigen, der erste
//     zur Nordwestecke der Kachel
//   Randknoten: Zahl, dann Nummern als Differenz — tote Enden ≤ 2 m vom
//     Kachelrand, gebunden erst beim Zusammensetzen
//   Kanten: Zahl, dann je Kante ein Kopf (Klasse in 4 Bit, dann je ein
//     Bit Einbahn, Höhen, und welche der seltenen Felder folgen), a als
//     Differenz zum b der vorigen Kante, b als Differenz zu a, Anstieg
//     und Abstieg in Zentimetern ([_cmLoss]), nur wenn gesetzt: Ebene,
//     Wegegüte, uphill, steil auf/ab und Steilgewicht auf/ab in
//     Dezimetern, Tragen × 1000; dann die inneren Punkte
// Länge und Meter-Lage rechnet das Zusammensetzen selbst, in der
// Projektion des Rahmens.
//
// **Im Web** rechnet dart2js Bit-Operationen auf 32 Bit: Kein `<<` über
// Bit 31 — der Leser und der Schreiber rechnen mit Multiplikation und
// Division (`test/web/routing_tile_browser_test.dart`).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart' show GZipDecoder, GZipEncoder;
import 'package:latlong2/latlong.dart';

import '../../core/stall_watch.dart';
import '../offline_areas/height_tiles.dart';
import 'plan_progress.dart';
import 'road_graph.dart';
import 'road_graph_loader.dart' show RoadTileBytes;
import 'route_profile.dart';

/// Die Nummer des Formats im Kopf. Eine andere heißt „kein Stück" — das
/// Gerät backt neu (11.5).
const kRoutingTileFormat = 1;

/// Die Fassung der Bauregeln. Hochzählen, wer eine der Regeln ändert, die
/// ein Stück festschreibt: die M1-Regeln ([buildRoadGraph], [kGraphJoinM],
/// Kreuzungen je Ebene), die Wegegüte ([kWayMatchM], [kWaySampleM],
/// [kWayMajority]), die Höhenproben ([kClimbSampleM],
/// [kClimbHysteresisM], [kSteepGrade], [kSteepSmooth]), die Kurve
/// [steepWeightAt] und die Klassen aus [classifyWay].
/// `test/routing/routing_tile_test.dart` hält die Liste fest. Die KOSTEN
/// (`edgeCostS`, Stil, Vorlieben) stehen nicht darauf: Sie rechnen beim
/// Planen aus dem Stück.
const kRoutingTileVersion = 1;

/// Der Zoom der Stücke — derselbe wie der des Graphen.
const kRoutingTileZoom = kRoadGraphZoom;

/// Der Bau eines Stücks im Kachelspeicher: Format, Fassung und die Bauten
/// der drei Quellkacheln (Karte, Höhen, Wege-Archiv; `-` für fehlend). Ein
/// Stück ist frisch, solange dieser Text gleich bleibt — ändert sich eine
/// Quelle („Aktualisieren"), backt das Gerät die Kachel neu, ohne Netz.
String pieceBuild({required String map, String? heights, String? ways}) =>
    'r$kRoutingTileFormat.$kRoutingTileVersion:$map:${heights ?? '-'}:${ways ?? '-'}';

/// Ein Stück als Bytes — was über die Isolate-Grenze und in den Speicher
/// geht, gepackt ([packPiece]) wie die übrigen Ebenen des Kachelspeichers.
typedef RoutingPiece = ({int x, int y, Uint8List bytes});

/// Packt ein Stück für den Speicher (gzip, wie Karte und Wege dort liegen
/// — gemessen etwa halb so groß, `docs/routing-messung.md` „#380").
/// Ohne Zeitstempel: `GZipEncoder` schreibt die Uhrzeit in den Kopf
/// (Bytes 4–7), gleiche Stücke hießen sonst je Sekunde anders; 0 heißt in
/// gzip „keine Zeit".
Uint8List packPiece(Uint8List raw) => Uint8List.fromList(GZipEncoder().encode(raw)!)..fillRange(4, 8, 0);

/// Liest ein gepacktes oder rohes Stück; null wie [decodePiece].
DecodedPiece? unpackPiece(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
    final List<int> raw;
    try {
      raw = GZipDecoder().decodeBytes(bytes);
    } catch (_) {
      // Kaputt gepackt ist wie kaputt geschrieben: kein Stück, neu backen.
      return null;
    }
    return decodePiece(Uint8List.fromList(raw));
  }
  return decodePiece(bytes);
}

/// Backt je Kachel in [roads] ein gepacktes Stück: [buildRoadGraph] über NUR ihre
/// Wege, Höhen aus [heights] (null: flach), die Güte aus den Kacheln des
/// Wege-Archivs in [ways] um sie herum (3 × 3). Jede Wege-Kachel wird
/// einmal dekodiert und von allen Nachbarn geteilt.
List<RoutingPiece> bakeTiles({
  required List<RoadTileBytes> roads,
  List<RoadTileBytes> ways = const [],
  HeightTiles? heights,
}) {
  final grades = <int, List<WayGradeLine>>{};
  for (final w in ways) {
    grades[_key(w.tile.x, w.tile.y)] = wayGradeLinesFromTile(w.bytes, z: w.tile.z, x: w.tile.x, y: w.tile.y);
  }
  final out = <RoutingPiece>[];
  for (var i = 0; i < roads.length; i++) {
    final r = roads[i];
    final x = r.tile.x, y = r.tile.y;
    out.add((
      x: x,
      y: y,
      bytes: PlanProgress.part(i / roads.length, (i + 1) / roads.length, () {
        final around = [
          for (var dx = -1; dx <= 1; dx++)
            for (var dy = -1; dy <= 1; dy++) ...?grades[_key(x + dx, y + dy)],
        ];
        return packPiece(bakeTile(x: x, y: y, road: r.bytes, ways: around, heights: heights));
      }),
    ));
  }
  return out;
}

/// Das Stück der Kachel [x]/[y] aus ihren Wege-Bytes [road]: derselbe Bau
/// wie für einen Rahmen, in der Projektion um die Mitte der Kachel.
Uint8List bakeTile({
  required int x,
  required int y,
  required Uint8List road,
  Iterable<WayGradeLine> ways = const [],
  HeightTiles? heights,
}) {
  final lines = wayLinesFromTile(road, z: kRoutingTileZoom, x: x, y: y);
  final g = buildRoadGraph(lines, lat0: _tileLat(y + 0.5)).graph;
  if (heights != null) addClimbsFrom(g, heights);
  final grades = ways.toList();
  if (grades.isNotEmpty) addWayQuality(g, grades);
  return encodePiece(g, x, y);
}

int _key(int x, int y) => x * (1 << kRoutingTileZoom) + y;

// ------------------------------------------------------------- Schreiben

class _Writer {
  final _b = BytesBuilder(copy: false);

  void u(int v) {
    assert(v >= 0);
    while (v >= 0x80) {
      _b.addByte(0x80 | v % 0x80);
      v ~/= 0x80;
    }
    _b.addByte(v);
  }

  void s(int v) => u(v >= 0 ? v * 2 : -v * 2 - 1);

  Uint8List done() => _b.takeBytes();
}

int _micro(double deg) => (deg * 1e6).round();
int _dm(double m) => (m * 10).round();
int _cm(double m) => (m * 100).round();

/// Der Abstieg in Zentimetern — nie so gerundet, dass „bergab" kippt:
/// `edgeTimeS` nimmt die Abfahrtsgeschwindigkeit, sobald der Abstieg den
/// Anstieg übersteigt, auch um Millimeter. Auf Dezimeter gerundet fuhren
/// flache Straßen mit 9 mm Abstieg in der Messung plötzlich flach, und
/// Suchen wichen bis 2 % ab (`routing/CLAUDE.md`, „Bergab ist eine Stufe").
int _cmLoss(double gain, double loss) {
  final g = _cm(gain), l = _cm(loss);
  if (loss > gain && l <= g) return g + 1;
  if (loss <= gain && l > g) return g;
  return l;
}

/// Das Ausmaß der Kartenkacheln: Die inneren Punkte einer Kante liegen
/// auf ihrem Raster und sind in Pixeln verlustfrei und kürzer.
const _extent = 4096;

/// Der Punkt in Pixeln der Kachel [x]/[y] — null, wenn er nicht auf dem
/// Raster liegt (mit [exact] false: gerundet).
(int, int)? _pixel(LatLng p, int x, int y, {bool exact = true}) {
  final n = 1 << kRoutingTileZoom;
  final tx = (p.longitude + 180) / 360 * n;
  final r = p.latitude * math.pi / 180;
  final ty = (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n;
  final fx = (tx - x) * _extent, fy = (ty - y) * _extent;
  final ix = fx.round(), iy = fy.round();
  if (exact && ((fx - ix).abs() > 1e-3 || (fy - iy).abs() > 1e-3)) return null;
  return (ix, iy);
}

/// Derselbe Weg wie `wayLinesFromTile` von Kachelpixeln zu Grad — damit
/// ein Punkt bitgleich zurückkommt.
LatLng _fromPixel(int ix, int iy, int x, int y) {
  final n = 1 << kRoutingTileZoom;
  final tx = x + ix / _extent, ty = y + iy / _extent;
  final lat = math.atan(_sinh(math.pi * (1 - 2 * ty / n))) * 180 / math.pi;
  return LatLng(lat, tx / n * 360 - 180);
}

double _sinh(double v) => (math.exp(v) - math.exp(-v)) / 2;

double _tileLat(num y) {
  final n = math.pi - 2 * math.pi * y / (1 << kRoutingTileZoom);
  return 180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
}

double _tileLon(num x) => x / (1 << kRoutingTileZoom) * 360 - 180;

/// Schreibt den Graphen [g] der Kachel [x]/[y] als Stück.
Uint8List encodePiece(RoadGraph g, int x, int y) {
  final w = _Writer()
    ..u(kRoutingTileFormat)
    ..u(kRoutingTileVersion)
    ..u(x)
    ..u(y)
    ..u(g.nodes.length);
  var plon = _micro(_tileLon(x)), plat = _micro(_tileLat(y));
  final nodes = g.nodeLatLng;
  for (var n = 0; n < nodes.length; n++) {
    final p = nodes[n];
    final lon = _micro(p.longitude), lat = _micro(p.latitude);
    w
      ..s(lon - plon)
      ..s(lat - plat);
    plon = lon;
    plat = lat;
  }
  // Randknoten: tote Enden nahe am Rand der Kachel — nur sie bindet das
  // Zusammensetzen an die Nachbarn.
  final west = _tileLon(x), east = _tileLon(x + 1);
  final north = _tileLat(y), south = _tileLat(y + 1);
  final border = <int>[];
  for (var n = 0; n < nodes.length; n++) {
    if (g.degree(n) != 1) continue;
    final p = nodes[n];
    final mLon = 111320 * math.cos(p.latitude * math.pi / 180);
    final d = [
      (p.longitude - west) * mLon,
      (east - p.longitude) * mLon,
      (north - p.latitude) * 111320,
      (p.latitude - south) * 111320,
    ].reduce(math.min);
    if (d <= kGraphJoinM + 0.5) border.add(n);
  }
  w.u(border.length);
  var prev = 0;
  for (final n in border) {
    w.u(n - prev);
    prev = n;
  }
  final edges = g.edges;
  w.u(edges.length);
  var prevB = 0;
  for (var ei = 0; ei < edges.length; ei++) {
    final e = edges[ei];
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
      ..u(_cmLoss(e.gain, e.loss));
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
    final pts = e.points;
    w.u(pts.length - 2);
    if (pts.length <= 2) continue;
    // Eine Kennung sagt, ob alle inneren Punkte auf dem Pixelraster liegen
    // (1, Pixel ab Knoten a), sonst Mikrograd (0) — Punkte aus Teilungen
    // liegen daneben.
    final pix = [for (var i = 1; i < pts.length - 1; i++) _pixel(pts[i], x, y)];
    if (pix.every((p) => p != null)) {
      w.u(1);
      // Bezug ist Knoten a, wie ihn der Leser kennt: in Mikrograd.
      final a = LatLng(_micro(pts.first.latitude) / 1e6, _micro(pts.first.longitude) / 1e6);
      var (px, py) = _pixel(a, x, y, exact: false)!;
      for (final p in pix) {
        w
          ..s(p!.$1 - px)
          ..s(p.$2 - py);
        (px, py) = p;
      }
    } else {
      w.u(0);
      var lon = _micro(pts.first.longitude), lat = _micro(pts.first.latitude);
      for (var i = 1; i < pts.length - 1; i++) {
        final px = _micro(pts[i].longitude), py = _micro(pts[i].latitude);
        w
          ..s(px - lon)
          ..s(py - lat);
        lon = px;
        lat = py;
      }
    }
  }
  return w.done();
}

// ---------------------------------------------------------------- Lesen

class _Reader {
  _Reader(this._d);
  final Uint8List _d;
  var _i = 0;

  int u() {
    var v = 0, mul = 1;
    // Höchstens sieben Bytes (49 Bit) — im Web sind Zahlen bis 2^53 genau.
    for (var k = 0; k < 7; k++) {
      final b = _d[_i++];
      v += (b & 0x7f) * mul;
      if (b < 0x80) return v;
      mul *= 0x80;
    }
    throw const FormatException('Varint zu lang');
  }

  int s() {
    final v = u();
    return v.isEven ? v ~/ 2 : -((v + 1) ~/ 2);
  }

  bool get atEnd => _i == _d.length;
}

/// Eine Kante eines gelesenen Stücks.
class PieceEdge {
  const PieceEdge({
    required this.a,
    required this.b,
    required this.cls,
    required this.oneway,
    required this.hasHeights,
    required this.level,
    required this.way,
    required this.uphill,
    required this.gainCm,
    required this.lossCm,
    required this.steepDm,
    required this.carry,
    required this.inner,
  });

  final int a, b;
  final WayClass cls;
  final bool oneway, hasHeights;
  final int level;
  final int? way, uphill;
  final int gainCm, lossCm;

  /// Steil auf, ab, Gewicht auf, ab — in Dezimetern.
  final List<int> steepDm;

  /// Tragen × 1000.
  final int carry;
  final List<LatLng> inner;
}

/// Ein gelesenes Stück.
class DecodedPiece {
  const DecodedPiece({required this.x, required this.y, required this.nodes, required this.border, required this.edges});

  final int x, y;
  final List<LatLng> nodes;
  final List<int> border;
  final List<PieceEdge> edges;
}

/// Liest ein Stück. Null bei einem anderen Format, einer anderen Fassung
/// der Bauregeln oder kaputten Bytes — das heißt „kein Stück", das Gerät
/// backt neu (11.5), nie ein Absturz.
DecodedPiece? decodePiece(Uint8List bytes) {
  try {
    final r = _Reader(bytes);
    if (r.u() != kRoutingTileFormat || r.u() != kRoutingTileVersion) return null;
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
      if (prev >= count) return null;
      border.add(prev);
    }
    final edges = <PieceEdge>[];
    var prevB = 0;
    for (var i = r.u(); i > 0; i--) {
      final head = r.u();
      final a = prevB + r.s();
      final b = a + r.s();
      if (a < 0 || b < 0 || a >= count || b >= count) return null;
      prevB = b;
      final gain = r.u(), loss = r.u();
      final level = head & 1 << 6 != 0 ? r.s() : 0;
      final way = head & 1 << 7 != 0 ? r.u() : null;
      final uphill = head & 1 << 8 != 0 ? r.u() : null;
      final steep = head & 1 << 9 != 0 ? [r.u(), r.u(), r.u(), r.u()] : const [0, 0, 0, 0];
      final carry = head & 1 << 10 != 0 ? r.u() : 1000;
      final cls = head & 15;
      if (cls >= WayClass.values.length) return null;
      final inner = <LatLng>[];
      final n = r.u();
      if (n > 0) {
        if (r.u() == 1) {
          var (px, py) = _pixel(nodes[a], x, y, exact: false)!;
          for (var k = n; k > 0; k--) {
            px += r.s();
            py += r.s();
            inner.add(_fromPixel(px, py, x, y));
          }
        } else {
          var plon = _micro(nodes[a].longitude), plat = _micro(nodes[a].latitude);
          for (var k = n; k > 0; k--) {
            plon += r.s();
            plat += r.s();
            inner.add(LatLng(plat / 1e6, plon / 1e6));
          }
        }
      }
      edges.add(PieceEdge(
        a: a,
        b: b,
        cls: WayClass.values[cls],
        oneway: head & 1 << 4 != 0,
        hasHeights: head & 1 << 5 != 0,
        level: level,
        way: way,
        uphill: uphill,
        gainCm: gain,
        lossCm: loss,
        steepDm: steep,
        carry: carry,
        inner: inner,
      ));
    }
    if (!r.atEnd) return null;
    return DecodedPiece(x: x, y: y, nodes: nodes, border: border, edges: edges);
  } on RangeError {
    return null;
  } on FormatException {
    return null;
  }
}

// ------------------------------------------------------- Zusammensetzen

/// Was [stitchPieces] gebaut hat.
typedef StitchedGraph = ({RoadGraph graph, int joins});

/// Setzt den Graphen aus [pieces] zusammen, in Metern um [lat0]: Knoten
/// mit denselben Mikrograd sind einer ([RoadGraph.node]), danach werden
/// nur die Randknoten mit derselben 2-m-Regel wie beim Bau gebunden
/// (`_joinDeadEnds`) — mehr ist das Zusammensetzen nicht (11.2).
StitchedGraph stitchPieces(List<DecodedPiece> pieces, double lat0) {
  final g = RoadGraph(lat0);
  final border = <int>[];
  for (var pi = 0; pi < pieces.length; pi++) {
    if (pi & 15 == 0) PlanProgress.steps(pi, pieces.length);
    final p = pieces[pi];
    final ids = [for (final n in p.nodes) g.node(n)];
    for (final e in p.edges) {
      final a = ids[e.a], b = ids[e.b];
      if (a == b && e.inner.isEmpty) continue;
      final ei = g.addEdge(a, b, e.cls, e.oneway, [p.nodes[e.a], ...e.inner, p.nodes[e.b]], level: e.level);
      g.edges[ei]
        ..hasHeights = e.hasHeights
        ..way = e.way
        ..uphill = e.uphill
        ..gain = e.gainCm / 100
        ..loss = e.lossCm / 100
        ..steepUp = e.steepDm[0] / 10
        ..steepDown = e.steepDm[1] / 10
        ..steepWUp = e.steepDm[2] / 10
        ..steepWDown = e.steepDm[3] / 10
        ..carry = e.carry / 1000;
    }
    for (final n in p.border) {
      border.add(ids[n]);
    }
  }
  final joins = StallWatch.mark('graph.joins', () {
    var joins = 0;
    for (final n in border) {
      if (g.degree(n) != 1) continue;
      var target = g.nearestNode(g.nodes[n], kGraphJoinM, exclude: n);
      if (target == null) {
        final hit = g.nearest(g.nodeLatLng[n], kGraphJoinM, excludeEdges: g.adj[n].toSet());
        if (hit == null) continue;
        target = g.splitEdge(hit.edge, hit.seg, hit.at);
      }
      if (target == n) continue;
      final ei =
          g.addEdge(n, target, g.edges[g.adjFirst(n) >> 1].cls, false, [g.nodeLatLng[n], g.nodeLatLng[target]]);
      g.edges[ei].hasHeights = true; // ≤ 2 m, flach
      joins++;
    }
    return joins;
  });
  g.compact();
  return (graph: g, joins: joins);
}
