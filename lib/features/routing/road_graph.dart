// Der Wegegraph der Routing-Engine (docs/konzept-routing.md 2.7): aus
// der `roads`-Ebene der z13-Kacheln gespeicherter Bereiche, mit den drei
// gemessenen Reparaturen (M1, docs/routing-messung.md) — Zuschnitt jeder
// Kachel auf ihren Rahmen, tote Enden innerhalb von 2 m an den nächsten
// anderen Weg gebunden (auch mitten in ein Segment: der T-Knoten, den die
// Vereinfachung aus dem durchgehenden Weg entfernt hat), Kreuzungen ohne
// gemeinsamen Knoten geteilt, sofern beide Wege auf derselben Ebene
// liegen (Brücke, Tunnel). Ohne die beiden Reparaturen hielt die größte
// Komponente 50–80 % der Kantenlänge, mit ihnen 95–98 %.
//
// Port von `Graph`, `build_graph`, `find_crossings`, `clip_line` und
// `lines_from_tile` in `tool/route_measure.py` — das Werkzeug ist die
// Referenz; `test/routing/road_graph_test.dart` fährt dieselben Fälle
// (T-Knoten, Brücke über Kreuzung, Einbahn, Anheften).
//
// Rein: keine Widgets, kein Riverpod. Knoten und Segmente liegen in einem
// Gitter von [kGraphCellM], damit Join und Anheften lokale Abfragen
// bleiben — die erste Fassung des Werkzeugs sah jede Kante je totem Ende
// an, das waren Minuten statt Sekunden.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';
import 'package:vector_tile/vector_tile.dart';

import '../../core/line_geometry.dart';
import '../offline_areas/height_tiles.dart';
import 'route_profile.dart';

/// Tote Enden bis zu so vielen Metern werden angebunden (M1: 10 m
/// brachten nichts mehr).
const kGraphJoinM = 2.0;

/// Ein Trail-Ende wird bis zu so weit an den Graphen geheftet — die
/// GPS-Unschärfe eines Trailanfangs.
const kGraphAttachM = 30.0;

/// Zellgröße des Gitters über Knoten und Segmenten, in Metern.
const kGraphCellM = 50.0;

/// Der Zoom, aus dem die Wege kommen — derselbe wie beim Wege-Index.
const kRoadGraphZoom = 13;

/// Ein brauchbarer Weg aus einer Kachel, in Grad, auf die Kachel
/// zugeschnitten.
class WayLine {
  const WayLine({required this.cls, required this.oneway, required this.points, this.level = 0});

  final WayClass cls;

  /// Einbahn — nur auf Straßenklassen überhaupt gesetzt.
  final bool oneway;
  final List<LatLng> points;

  /// 1 Brücke, −1 Tunnel, 0 ebenerdig: Eine geometrische Kreuzung ist
  /// nur auf derselben Ebene eine Abzweigung.
  final int level;
}

/// Die brauchbaren Wege einer Kachel (`roads`, Linien), klassifiziert,
/// auf den Kachelrahmen zugeschnitten, doppelte Punkte entfernt. Eine
/// Kachel, die sich nicht lesen lässt, liefert keine Linien.
List<WayLine> wayLinesFromTile(Uint8List mvt, {required int z, required int x, required int y}) {
  final VectorTile tile;
  try {
    tile = VectorTile.fromBytes(bytes: mvt);
  } catch (_) {
    return const [];
  }
  final n = 1 << z;
  final out = <WayLine>[];
  for (final layer in tile.layers) {
    if (layer.name != 'roads') continue;
    final extent = layer.extent.toDouble();
    for (final f in layer.features) {
      if (f.type != VectorTileGeomType.LINESTRING) continue;
      final props = f.decodeProperties();
      final cls = classifyWay(
        kind: props['kind']?.dartStringValue,
        kindDetail: props['kind_detail']?.dartStringValue,
        access: props['access']?.dartStringValue,
        service: props['service']?.dartStringValue,
      );
      if (cls == null) continue;
      final oneway = _truthy(props['oneway']) && cls.isRoad;
      final level = _truthy(props['is_bridge'])
          ? 1
          : _truthy(props['is_tunnel'])
              ? -1
              : 0;
      for (final line in f.decodeLineString()) {
        final px = [for (final p in line) math.Point(p[0].toDouble(), p[1].toDouble())];
        for (final piece in clipToTile(px, extent)) {
          final pts = <LatLng>[];
          for (final p in piece) {
            final ll = _tileToLatLng(x + p.x / extent, y + p.y / extent, n);
            if (pts.isEmpty || pts.last != ll) pts.add(ll);
          }
          if (pts.length >= 2) out.add(WayLine(cls: cls, oneway: oneway, points: pts, level: level));
        }
      }
    }
  }
  return out;
}

/// Eine Linie des Wege-Archivs (#213, Format 2): Klasse `k`, an Pfaden
/// `u` (`mtb:scale:uphill`), in Grad.
class WayGradeLine {
  const WayGradeLine({required this.way, required this.points, this.uphill});

  final int way;
  final int? uphill;
  final List<LatLng> points;
}

/// Die Linien einer Kachel des Wege-Archivs (Ebene `ways`) — `ways_from_tile`
/// im Werkzeug. Nicht zugeschnitten: Der Puffer über den Rand schadet
/// beim Abgleich nicht, er hilft an der Kachelgrenze.
List<WayGradeLine> wayGradeLinesFromTile(Uint8List mvt, {required int z, required int x, required int y}) {
  final VectorTile tile;
  try {
    tile = VectorTile.fromBytes(bytes: mvt);
  } catch (_) {
    return const [];
  }
  final n = 1 << z;
  final out = <WayGradeLine>[];
  for (final layer in tile.layers) {
    if (layer.name != 'ways') continue;
    final extent = layer.extent.toDouble();
    for (final f in layer.features) {
      if (f.type != VectorTileGeomType.LINESTRING) continue;
      final props = f.decodeProperties();
      final k = props['k']?.dartIntValue?.toInt();
      if (k == null) continue;
      final u = props['u']?.dartIntValue?.toInt();
      for (final line in f.decodeLineString()) {
        final pts = [for (final p in line) _tileToLatLng(x + p[0] / extent, y + p[1] / extent, n)];
        if (pts.length >= 2) out.add(WayGradeLine(way: k, uphill: u, points: pts));
      }
    }
  }
  return out;
}

/// Klassen des Archivs je Wegart (#213): nur ein Forstweg nimmt eine
/// Forstweg-Klasse an, nur ein Wanderweg eine Pfad-Klasse.
const kWayTrackClasses = {1, 2, 3, 7};
const kWayPathClasses = {4, 5, 6, 8};

/// #211: Die Linien der Basiskarte liegen innerhalb 3 m ihres OSM-Wegs.
const kWayMatchM = 3.0;

/// So oft wird eine Kante abgetastet …
const kWaySampleM = 10.0;

/// … und so viel der Proben braucht eine Klasse, um die Kante zu benennen.
const kWayMajority = 0.5;

/// Benennt jeden Forstweg und Wanderweg des Graphen nach dem Wege-Archiv
/// (#213) — `add_way_quality` im Werkzeug: Proben alle [kWaySampleM], je
/// Probe die nächste Archivlinie derselben Wegart innerhalb [kWayMatchM];
/// eine Klasse mit mehr als [kWayMajority] der Proben wird
/// [GraphEdge.way], ebenso `u` ([GraphEdge.uphill]). Liefert, wie viele
/// Kanten eine Klasse bekamen.
int addWayQuality(RoadGraph g, Iterable<WayGradeLine> lines) {
  const cell = 25.0;
  final grid = <(int, int), List<int>>{};
  final segs = <(int, int?, math.Point<double>, math.Point<double>)>[];
  for (final l in lines) {
    if (!kWayTrackClasses.contains(l.way) && !kWayPathClasses.contains(l.way)) continue;
    final xy = g.proj.line(l.points);
    for (var i = 1; i < xy.length; i++) {
      final a = xy[i - 1], b = xy[i];
      final si = segs.length;
      segs.add((l.way, l.uphill, a, b));
      for (var cx = (math.min(a.x, b.x) / cell).floor(); cx <= (math.max(a.x, b.x) / cell).floor(); cx++) {
        for (var cy = (math.min(a.y, b.y) / cell).floor(); cy <= (math.max(a.y, b.y) / cell).floor(); cy++) {
          (grid[(cx, cy)] ??= []).add(si);
        }
      }
    }
  }
  if (segs.isEmpty) return 0;
  (int, int?)? nearest(math.Point<double> p, Set<int> kinds) {
    final cx = (p.x / cell).floor(), cy = (p.y / cell).floor();
    (double, int, int?)? best;
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        for (final si in grid[(cx + dx, cy + dy)] ?? const <int>[]) {
          final (k, u, a, b) = segs[si];
          if (!kinds.contains(k)) continue;
          final d = pointSegmentDistance(p, a, b);
          if (d <= kWayMatchM && (best == null || d < best.$1)) best = (d, k, u);
        }
      }
    }
    return best == null ? null : (best.$2, best.$3);
  }

  var named = 0;
  for (final e in g.edges) {
    final kinds = e.cls == WayClass.forstweg
        ? kWayTrackClasses
        : e.cls == WayClass.wanderweg
            ? kWayPathClasses
            : null;
    if (kinds == null) continue;
    final samples = resampleXy(g.proj.line(e.points), kWaySampleM);
    if (samples.isEmpty) continue;
    final ks = <int, int>{}, us = <int, int>{};
    for (final p in samples) {
      final hit = nearest(p, kinds);
      if (hit == null) continue;
      ks[hit.$1] = (ks[hit.$1] ?? 0) + 1;
      if (hit.$2 case final u?) us[u] = (us[u] ?? 0) + 1;
    }
    int? winner(Map<int, int> counts) {
      if (counts.isEmpty) return null;
      final top = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
      return top.value > kWayMajority * samples.length ? top.key : null;
    }

    e.way = winner(ks);
    e.uphill = winner(us);
    if (e.way != null) named++;
  }
  return named;
}

bool _truthy(VectorTileValue? v) {
  if (v == null) return false;
  if (v.dartBoolValue case final b?) return b;
  if (v.dartIntValue case final i?) return i.toInt() != 0;
  final s = v.dartStringValue;
  return s != null && s != '' && s != 'no' && s != 'false' && s != '0';
}

LatLng _tileToLatLng(double tx, double ty, int n) {
  final lon = tx / n * 360 - 180;
  final latRad = math.atan(_sinh(math.pi * (1 - 2 * ty / n)));
  return LatLng(latRad * 180 / math.pi, lon);
}

double _sinh(double v) => (math.exp(v) - math.exp(-v)) / 2;

/// Schneidet eine Linie in Kacheleinheiten auf [0, extent]² zu und
/// liefert die Stücke innerhalb. Kacheln tragen einen Puffer über ihren
/// Rand hinaus; ein Weg nahe der Grenze liegt in BEIDEN Nachbarn. Ohne
/// Zuschnitt hielte der Graph ihn doppelt; mit ihm enden beide Kacheln am
/// selben Grenzpunkt (± Quantisierung), und der Join bindet sie zusammen.
List<List<math.Point<double>>> clipToTile(List<math.Point<double>> line, double extent) {
  bool inside(math.Point<double> p) => p.x >= 0 && p.x <= extent && p.y >= 0 && p.y <= extent;

  (math.Point<double>, math.Point<double>)? cross(math.Point<double> a, math.Point<double> b) {
    // Liang–Barsky auf dem Kasten.
    var t0 = 0.0, t1 = 1.0;
    final dx = b.x - a.x, dy = b.y - a.y;
    for (final (p, q) in [(-dx, a.x), (dx, extent - a.x), (-dy, a.y), (dy, extent - a.y)]) {
      if (p == 0) {
        if (q < 0) return null;
        continue;
      }
      final r = q / p;
      if (p < 0) {
        if (r > t1) return null;
        t0 = math.max(t0, r);
      } else {
        if (r < t0) return null;
        t1 = math.min(t1, r);
      }
    }
    if (t0 > t1) return null;
    return (math.Point(a.x + t0 * dx, a.y + t0 * dy), math.Point(a.x + t1 * dx, a.y + t1 * dy));
  }

  final pieces = <List<math.Point<double>>>[];
  var cur = <math.Point<double>>[];
  for (var i = 1; i < line.length; i++) {
    final a = line[i - 1], b = line[i];
    final seg = cross(a, b);
    if (seg == null) {
      if (cur.length >= 2) pieces.add(cur);
      cur = [];
      continue;
    }
    final (p, q) = seg;
    if (cur.isEmpty || cur.last != p) {
      if (cur.isNotEmpty && inside(a) && cur.last != a) cur.add(a);
      if (cur.isEmpty) {
        cur = [p];
      } else if (cur.last != p) {
        if (cur.length >= 2) pieces.add(cur);
        cur = [p];
      }
    }
    cur.add(q);
  }
  if (cur.length >= 2) pieces.add(cur);
  return pieces;
}

/// Eine Kante: zwei Knoten, Klasse, Einbahn, Länge in Metern, Anstieg
/// und Abstieg in Kantenrichtung (a → b), die Punkte in Grad.
class GraphEdge {
  GraphEdge({
    required this.a,
    required this.b,
    required this.cls,
    required this.oneway,
    required this.points,
    required this.length,
    this.level = 0,
  });

  int a;
  int b;
  final WayClass cls;
  final bool oneway;

  /// Der Trail, auf dem die Kante liegt (#174, #185) — gesetzt von
  /// `applyTrails`, null für einen gewöhnlichen Weg.
  EdgeTrail? trail;

  /// Gesperrt in Kantenrichtung (a → b) bzw. dagegen: Ein Trail wird nie
  /// gegen seine Richtung gefahren, außer er ist in beide Richtungen
  /// fahrbar (#174). Wie die Einbahn, nur für jede Klasse.
  bool blockForward = false;
  bool blockBackward = false;

  /// Ein Uphill-Trail oder Verbinder (#185): Er ist der gewollte Weg
  /// bergauf — günstiger als Forstweg ([kTrailConnectorFactor]) und kein
  /// Wanderweg im Sinn des Budgets, auch wenn die Karte ihn so führt.
  bool get connector => trail?.connector ?? false;

  /// Zählt gegen „höchstens Wanderweg".
  bool get hiking => cls.hiking && !connector;
  List<LatLng> points;
  double length;
  final int level;

  double gain = 0;
  double loss = 0;

  /// Höhenmeter über [kSteepGrade] in Kantenrichtung (a → b) bzw.
  /// dagegen (#194, [steepExcess]) — sie kosten den Steilaufschlag.
  double steepUp = 0;
  double steepDown = 0;

  /// Gewichtete Steilmeter (#188, [steepWeight]) in Kantenrichtung bzw.
  /// dagegen — was der Steilaufschlag kostet.
  double steepWUp = 0;
  double steepWDown = 0;

  /// Der Anteil am Trage-Aufschlag ([kCarryCostS], #210): 1 für einen
  /// ganzen Weg, nach [RoadGraph.splitEdge] nach Länge geteilt.
  double carry = 1;

  /// Die Klasse im Wege-Archiv (#213, Format 2: 1–3 und 7 Forstweg, 4–6
  /// und 8 Pfad), null = unbekannt — gesetzt von [addWayQuality].
  int? way;

  /// `mtb:scale:uphill` 0–5 auf einem Pfad (#213), sonst null.
  int? uphill;

  /// Falsch, solange keine Höhen gelesen wurden oder eine Probe der Kante
  /// keine Höhe hatte — dann rechnet die Kante flach, und der Graph sagt
  /// es ([RoadGraph.edgesWithoutHeights]).
  bool hasHeights = false;
}

/// Was auf einer Kante liegt: welcher Trail und ob er ein Verbinder ist
/// (Uphill-Trail oder Verbindung, #185).
class EdgeTrail {
  const EdgeTrail({required this.id, required this.name, required this.connector});

  final String id;
  final String name;
  final bool connector;
}

/// Der Aufschlag auf einem Uphill-Trail oder Verbinder statt dem der
/// Wegklasse (#185, Feldbericht 0.73.0: „Uphill-Trails und Verbinder
/// sollten belohnt werden"): unter Forstweg (1,0), damit die Suche sie
/// vorzieht, wo sie hinführen. Ein Startwert, nicht gemessen — die Zeit
/// bleibt die der Klasse, nur die Wahl wird günstiger.
const kTrailConnectorFactor = 0.8;

/// Ein Treffer auf einer Kante: Abstand, Kante, Segment, Anteil im
/// Segment, Punkt.
typedef EdgeHit = ({double d, int edge, int seg, double t, LatLng at});

class RoadGraph {
  RoadGraph(double lat0) : proj = FlatProjection(lat0);

  final FlatProjection proj;
  final nodes = <math.Point<double>>[];
  final nodeLatLng = <LatLng>[];
  final edges = <GraphEdge>[];
  final adj = <List<int>>[];
  final _key = <(int, int), int>{};
  final _nodeCells = <(int, int), List<int>>{};
  final _segCells = <(int, int), List<(int, int)>>{};

  /// Steigt mit jeder Änderung an Knoten oder Kanten (neuer Knoten, neue
  /// Kante, Teilung). Wer Suchergebnisse über eine Rechnung hinaus behält
  /// (`LoopSearchCache`, #188), prüft sie daran: Nach einer Teilung zeigen
  /// gemerkte Vorgänger auf eine Kante, die jetzt woanders endet.
  int revision = 0;

  static (int, int) _cell(math.Point<double> p) => ((p.x / kGraphCellM).floor(), (p.y / kGraphCellM).floor());

  static (int, int) _keyOf(LatLng p) => ((p.longitude * 1e6).round(), (p.latitude * 1e6).round());

  /// Der Knoten an [p] — zwei Punkte auf derselben Mikrograd-Koordinate
  /// sind EIN Knoten (so teilen zwei Linien ihren Scheitel).
  int node(LatLng p) {
    final key = _keyOf(p);
    final existing = _key[key];
    if (existing != null) return existing;
    final i = nodes.length;
    revision++;
    _key[key] = i;
    final xy = proj.xy(p);
    nodes.add(xy);
    nodeLatLng.add(p);
    adj.add([]);
    (_nodeCells[_cell(xy)] ??= []).add(i);
    return i;
  }

  void _indexSegments(int ei) {
    final pts = proj.line(edges[ei].points);
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i], b = pts[i + 1];
      for (var cx = (math.min(a.x, b.x) / kGraphCellM).floor(); cx <= (math.max(a.x, b.x) / kGraphCellM).floor(); cx++) {
        for (var cy = (math.min(a.y, b.y) / kGraphCellM).floor(); cy <= (math.max(a.y, b.y) / kGraphCellM).floor(); cy++) {
          (_segCells[(cx, cy)] ??= []).add((ei, i));
        }
      }
    }
  }

  double _lengthOf(List<LatLng> points) {
    final xy = proj.line(points);
    var sum = 0.0;
    for (var i = 1; i < xy.length; i++) {
      sum += xy[i - 1].distanceTo(xy[i]);
    }
    return sum;
  }

  int addEdge(int a, int b, WayClass cls, bool oneway, List<LatLng> points, {int level = 0}) {
    final e = GraphEdge(a: a, b: b, cls: cls, oneway: oneway, points: points, length: _lengthOf(points), level: level);
    edges.add(e);
    revision++;
    final ei = edges.length - 1;
    adj[a].add(ei);
    adj[b].add(ei);
    _indexSegments(ei);
    return ei;
  }

  int degree(int n) => adj[n].length;

  /// Teilt die Kante [ei] an Segment [seg], Anteil [t], beim Punkt [at];
  /// der erste Teil behält [ei] (seine Gittereinträge bleiben gültig —
  /// das Segment wird nur kürzer), der Rest wird eine neue Kante.
  /// Liefert den Knoten an der Teilung.
  int splitEdge(int ei, int seg, LatLng at) {
    final e = edges[ei];
    final mid = node(at);
    if (mid == e.a || mid == e.b) return mid;
    final first = [...e.points.sublist(0, seg + 1), at];
    final second = [at, ...e.points.sublist(seg + 1)];
    final oldB = e.b;
    adj[oldB].remove(ei);
    e.points = first;
    e.b = mid;
    e.length = _lengthOf(first);
    adj[mid].add(ei);
    final ni = addEdge(mid, oldB, e.cls, e.oneway, second, level: e.level);
    // Die zweite Hälfte erbt, was auf der Kante liegt — sonst ließe ein
    // angehefteter Trailkopf den Rest eines Trails rückwärts befahrbar.
    edges[ni]
      ..trail = e.trail
      ..blockForward = e.blockForward
      ..blockBackward = e.blockBackward
      ..hasHeights = e.hasHeights
      ..way = e.way
      ..uphill = e.uphill;
    // Der Trage-Aufschlag gehört der ganzen Treppe, nicht jeder Hälfte.
    final carryShare = e.length + edges[ni].length == 0 ? 0.0 : edges[ni].length / (e.length + edges[ni].length);
    edges[ni].carry = e.carry * carryShare;
    e.carry = e.carry * (1 - carryShare);
    if (e.gain > 0 || e.loss > 0 || e.steepUp > 0 || e.steepDown > 0 || e.steepWUp > 0 || e.steepWDown > 0) {
      // Höhen anteilig nach Länge — genauer weiß es niemand, und flach
      // wäre falscher.
      final total = e.length + edges[ni].length;
      final share = total == 0 ? 0.0 : edges[ni].length / total;
      edges[ni]
        ..gain = e.gain * share
        ..loss = e.loss * share
        ..steepUp = e.steepUp * share
        ..steepDown = e.steepDown * share
        ..steepWUp = e.steepWUp * share
        ..steepWDown = e.steepWDown * share;
      e
        ..gain = e.gain * (1 - share)
        ..loss = e.loss * (1 - share)
        ..steepUp = e.steepUp * (1 - share)
        ..steepDown = e.steepDown * (1 - share)
        ..steepWUp = e.steepWUp * (1 - share)
        ..steepWDown = e.steepWDown * (1 - share);
    }
    return mid;
  }

  int? nearestNode(math.Point<double> p, double radius, {int exclude = -1}) {
    final (cx, cy) = _cell(p);
    final reach = (radius / kGraphCellM).ceil();
    int? best;
    var bestD = radius;
    for (var dx = -reach; dx <= reach; dx++) {
      for (var dy = -reach; dy <= reach; dy++) {
        for (final n in _nodeCells[(cx + dx, cy + dy)] ?? const <int>[]) {
          if (n == exclude) continue;
          final d = nodes[n].distanceTo(p);
          if (d <= bestD) {
            best = n;
            bestD = d;
          }
        }
      }
    }
    return best;
  }

  /// Der nächste Kantenpunkt innerhalb von [radius] Metern, oder null.
  EdgeHit? nearest(LatLng p, double radius, {Set<int> excludeEdges = const {}}) {
    final xy = proj.xy(p);
    final (cx, cy) = _cell(xy);
    final reach = (radius / kGraphCellM).ceil();
    EdgeHit? best;
    final seen = <(int, int)>{};
    for (var dx = -reach; dx <= reach; dx++) {
      for (var dy = -reach; dy <= reach; dy++) {
        for (final (ei, i) in _segCells[(cx + dx, cy + dy)] ?? const <(int, int)>[]) {
          if (excludeEdges.contains(ei) || !seen.add((ei, i))) continue;
          final pts = edges[ei].points;
          if (i + 1 >= pts.length) continue; // veraltet nach einer Teilung
          final a = proj.xy(pts[i]), b = proj.xy(pts[i + 1]);
          final (d, t) = _pointSegment(xy, a, b);
          if (d <= radius && (best == null || d < best.d)) {
            final px = math.Point(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y));
            best = (d: d, edge: ei, seg: i, t: t, at: proj.latLng(px));
          }
        }
      }
    }
    return best;
  }

  static (double, double) _pointSegment(math.Point<double> p, math.Point<double> a, math.Point<double> b) {
    final dx = b.x - a.x, dy = b.y - a.y;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) return (p.distanceTo(a), 0.0);
    final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / len2).clamp(0.0, 1.0);
    final q = math.Point(a.x + t * dx, a.y + t * dy);
    return (p.distanceTo(q), t);
  }

  /// Der Knoten für ein Trail-Ende: ein vorhandener innerhalb von
  /// [radius], sonst ein neuer auf der nächsten Kante innerhalb von
  /// [radius], sonst null („nicht erreichbar").
  int? attach(LatLng p, {double radius = kGraphAttachM}) {
    final n = nearestNode(proj.xy(p), radius);
    if (n != null) return n;
    final hit = nearest(p, radius);
    if (hit == null) return null;
    return splitEdge(hit.edge, hit.seg, hit.at);
  }

  /// Zusammenhangskomponenten als Kantenlisten, längste zuerst.
  List<List<int>> components() {
    final parent = List<int>.generate(nodes.length, (i) => i);
    int find(int i) {
      while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
      }
      return i;
    }

    for (final e in edges) {
      final ra = find(e.a), rb = find(e.b);
      if (ra != rb) parent[ra] = rb;
    }
    final comp = <int, List<int>>{};
    for (var i = 0; i < edges.length; i++) {
      (comp[find(edges[i].a)] ??= []).add(i);
    }
    double lengthOf(List<int> es) => es.fold(0.0, (s, i) => s + edges[i].length);
    return comp.values.toList()..sort((x, y) => lengthOf(y).compareTo(lengthOf(x)));
  }

  double get totalLength => edges.fold(0.0, (s, e) => s + e.length);

  /// Anteil der Kantenlänge in der größten Komponente — die Zahl aus M1.
  double get largestComponentShare {
    final total = totalLength;
    if (total == 0) return 0;
    final largest = components().firstOrNull;
    return largest == null ? 0 : largest.fold(0.0, (s, i) => s + edges[i].length) / total;
  }

  int get edgesWithoutHeights => edges.where((e) => !e.hasHeights).length;
}

/// Was der Bau gemacht hat — die Zahlen, die M1 je Lauf nennt.
typedef GraphBuild = ({RoadGraph graph, int joins, int crossings});

/// Baut den Graphen aus Wegen (Konzept-Routing 2.7): ein Knoten, wo zwei
/// Linien einen Scheitel teilen, plus Linienenden; dann jedes tote Ende
/// innerhalb von [joinM] an den nächsten anderen Weg gebunden; dann
/// (wenn [splitCrossings]) jede Kreuzung zweier Wege derselben Ebene
/// ohne gemeinsamen Knoten geteilt.
GraphBuild buildRoadGraph(Iterable<WayLine> lines,
    {required double lat0, double joinM = kGraphJoinM, bool splitCrossings = true}) {
  final counts = <(int, int), int>{};
  final all = lines.toList();
  for (final l in all) {
    for (final p in l.points) {
      final k = RoadGraph._keyOf(p);
      counts[k] = (counts[k] ?? 0) + 1;
    }
  }
  final g = RoadGraph(lat0);
  for (final l in all) {
    final cut = [0];
    for (var i = 1; i < l.points.length - 1; i++) {
      if ((counts[RoadGraph._keyOf(l.points[i])] ?? 0) >= 2) cut.add(i);
    }
    cut.add(l.points.length - 1);
    for (var c = 0; c + 1 < cut.length; c++) {
      final piece = l.points.sublist(cut[c], cut[c + 1] + 1);
      final a = g.node(piece.first), b = g.node(piece.last);
      if (a == b && piece.length < 3) continue;
      g.addEdge(a, b, l.cls, l.oneway, piece, level: l.level);
    }
  }
  var joins = 0;
  if (joinM > 0) {
    final count = g.nodes.length; // neue Knoten aus Teilungen brauchen keinen Join
    for (var n = 0; n < count; n++) {
      if (g.degree(n) != 1) continue;
      var target = g.nearestNode(g.nodes[n], joinM, exclude: n);
      if (target == null) {
        // Die eigene Kante liegt bei Abstand 0 — ohne Ausschluss würde
        // jeder T-Knoten ohne Scheitel übersprungen (so im ersten CI-Lauf
        // des Werkzeugs: 554 statt 11 000 Anbindungen).
        final hit = g.nearest(g.nodeLatLng[n], joinM, excludeEdges: g.adj[n].toSet());
        if (hit == null) continue;
        target = g.splitEdge(hit.edge, hit.seg, hit.at);
      }
      if (target != n) {
        g.addEdge(n, target, g.edges[g.adj[n].first].cls, false, [g.nodeLatLng[n], g.nodeLatLng[target]]);
        joins++;
      }
    }
  }
  var crossings = 0;
  if (splitCrossings) {
    for (final c in findCrossings(g)) {
      // Erst die eine Kante teilen (attach legt den Knoten an), dann die
      // andere am selben Punkt — der Knotenschlüssel macht beide eins.
      final mid = g.attach(c.at, radius: 0.5);
      if (mid == null) continue;
      final hit = g.nearest(c.at, 0.5, excludeEdges: g.adj[mid].toSet());
      if (hit == null) continue;
      g.splitEdge(hit.edge, hit.seg, c.at);
      crossings++;
    }
  }
  return (graph: g, joins: joins, crossings: crossings);
}

/// Schnittpunkt zweier Strecken, wenn sie sich in ihrem Inneren kreuzen,
/// sonst null. Kollineare Überlappungen zählen nicht als Kreuzung.
math.Point<double>? properCrossing(
    math.Point<double> a, math.Point<double> b, math.Point<double> c, math.Point<double> d) {
  final rx = b.x - a.x, ry = b.y - a.y;
  final qx = d.x - c.x, qy = d.y - c.y;
  final den = rx * qy - ry * qx;
  if (den.abs() < 1e-9) return null;
  final acx = c.x - a.x, acy = c.y - a.y;
  final t = (acx * qy - acy * qx) / den;
  final u = (acx * ry - acy * rx) / den;
  const eps = 1e-3;
  if (t > eps && t < 1 - eps && u > eps && u < 1 - eps) {
    return math.Point(a.x + t * rx, a.y + t * ry);
  }
  return null;
}

/// Kreuzungen zweier Wege derselben Ebene ohne gemeinsamen Knoten —
/// über das Segmentgitter, also praktisch linear.
List<({LatLng at, int edgeA, int edgeB})> findCrossings(RoadGraph g) {
  final out = <({LatLng at, int edgeA, int edgeB})>[];
  final seen = <((int, int), (int, int))>{};
  for (final segs in g._segCells.values) {
    for (var i = 0; i < segs.length; i++) {
      final (ea, ia) = segs[i];
      final pa = g.edges[ea].points;
      if (ia + 1 >= pa.length) continue;
      final a = g.proj.xy(pa[ia]), b = g.proj.xy(pa[ia + 1]);
      for (var j = i + 1; j < segs.length; j++) {
        final (eb, ib) = segs[j];
        if (eb == ea) continue;
        final pb = g.edges[eb].points;
        if (ib + 1 >= pb.length || g.edges[ea].level != g.edges[eb].level) continue;
        final key = ea < eb || (ea == eb && ia < ib) ? ((ea, ia), (eb, ib)) : ((eb, ib), (ea, ia));
        if (!seen.add(key)) continue;
        final hit = properCrossing(a, b, g.proj.xy(pb[ib]), g.proj.xy(pb[ib + 1]));
        if (hit == null) continue;
        out.add((at: g.proj.latLng(hit), edgeA: ea, edgeB: eb));
      }
    }
  }
  return out;
}

/// Liest je Kante Anstieg und Abstieg aus den Höhenkacheln (alle 50 m,
/// 10 m Hysterese — `HeightReader.climbAlong`). Eine Kante ohne Höhe an
/// einer Probe bleibt flach und ist als solche markiert.
Future<void> addClimbs(RoadGraph g, HeightReader heights) async {
  for (final e in g.edges) {
    final profile = await heights.profileAlong(e.points);
    if (profile == null) {
      e.hasHeights = false;
      continue;
    }
    final (gain, loss) = hysteresisClimb(profile.heights, kClimbHysteresisM);
    final steep = steepExcess(profile.heights, profile.stepsM);
    final weighted = steepWeight(profile.heights, profile.stepsM);
    e
      ..gain = gain
      ..loss = loss
      ..steepUp = steep.up
      ..steepDown = steep.down
      ..steepWUp = weighted.up
      ..steepWDown = weighted.down
      ..hasHeights = true;
  }
}
