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
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';
import 'package:vector_tile/vector_tile.dart';

import '../../core/line_geometry.dart';
import '../../core/stall_watch.dart';
import '../offline_areas/height_tiles.dart';
import 'plan_progress.dart';
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
  for (var i = 0; i < g.edges.length; i++) {
    final e = g.edges[i];
    if (i & 127 == 0) PlanProgress.steps(i, g.edges.length);
    final kinds = e.cls == WayClass.forstweg
        ? kWayTrackClasses
        : e.cls == WayClass.wanderweg
            ? kWayPathClasses
            : null;
    if (kinds == null) continue;
    final samples = resampleXy(g.edgeXy(i), kWaySampleM);
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
///
/// Eine Sicht auf die Felder des Graphen (#378), kein eigener Speicher:
/// Bis 0.133.x war jede Kante ein Objekt mit eigener Punktliste, rund
/// 170 Byte plus Liste. [RoadGraph.edges] legt die Sicht bei jedem
/// Zugriff neu an — billig, aber in heißen Schleifen lesen die Suchen
/// direkt ([RoadGraph.edgeA], [RoadGraph.adjFirst]).
class GraphEdge {
  GraphEdge._(this._g, this.index);

  final RoadGraph _g;

  /// Die Kantennummer im Graphen.
  final int index;

  int get a => _g._ea[index];
  int get b => _g._eb[index];
  WayClass get cls => WayClass.values[_g._ecls[index]];
  bool get oneway => _g._flag(index, _kOneway);

  /// Der Trail, auf dem die Kante liegt (#174, #185) — gesetzt von
  /// `applyTrails`, null für einen gewöhnlichen Weg.
  EdgeTrail? get trail => _g._etrail[index];
  set trail(EdgeTrail? v) => _g._etrail[index] = v;

  /// Gesperrt in Kantenrichtung (a → b) bzw. dagegen: Ein Trail wird nie
  /// gegen seine Richtung gefahren, außer er ist in beide Richtungen
  /// fahrbar (#174). Wie die Einbahn, nur für jede Klasse.
  bool get blockForward => _g._flag(index, _kBlockForward);
  set blockForward(bool v) => _g._setFlag(index, _kBlockForward, v);
  bool get blockBackward => _g._flag(index, _kBlockBackward);
  set blockBackward(bool v) => _g._setFlag(index, _kBlockBackward, v);

  /// Ein Uphill-Trail oder Verbinder (#185): Er ist der gewollte Weg
  /// bergauf — günstiger als Forstweg ([kTrailConnectorFactor]) und kein
  /// Wanderweg im Sinn des Budgets, auch wenn die Karte ihn so führt.
  bool get connector => trail?.connector ?? false;

  /// Zählt gegen „höchstens Wanderweg".
  bool get hiking => cls.hiking && !connector;

  /// Darf die Kante von Knoten [from] aus befahren werden?
  /// ([RoadGraph.openFrom]).
  bool openFrom(int from) => _g.openFrom(index, from);

  /// Die Punkte in Grad — eine Sicht auf den Punktspeicher im Stand des
  /// Aufrufs (eine spätere Teilung kürzt die Kante, nicht diese Liste).
  List<LatLng> get points => _EdgePoints(_g, _g._eoff[index], _g._ecnt[index]);
  double get length => _g._elen[index];
  int get level => _g._elevel[index];

  double get gain => _g._egain[index];
  set gain(double v) => _g._egain[index] = v;
  double get loss => _g._eloss[index];
  set loss(double v) => _g._eloss[index] = v;

  /// Höhenmeter über [kSteepGrade] in Kantenrichtung (a → b) bzw.
  /// dagegen (#194, [steepExcess]) — sie kosten den Steilaufschlag.
  double get steepUp => _g._esteepUp[index];
  set steepUp(double v) => _g._esteepUp[index] = v;
  double get steepDown => _g._esteepDown[index];
  set steepDown(double v) => _g._esteepDown[index] = v;

  /// Gewichtete Steilmeter (#188, [steepWeight]) in Kantenrichtung bzw.
  /// dagegen — was der Steilaufschlag kostet.
  double get steepWUp => _g._esteepWUp[index];
  set steepWUp(double v) => _g._esteepWUp[index] = v;
  double get steepWDown => _g._esteepWDown[index];
  set steepWDown(double v) => _g._esteepWDown[index] = v;

  /// Der Anteil am Trage-Aufschlag ([kCarryCostS], #210): 1 für einen
  /// ganzen Weg, nach [RoadGraph.splitEdge] nach Länge geteilt.
  double get carry => _g._ecarry[index];
  set carry(double v) => _g._ecarry[index] = v;

  /// Die Klasse im Wege-Archiv (#213, Format 2: 1–3 und 7 Forstweg, 4–6
  /// und 8 Pfad), null = unbekannt — gesetzt von [addWayQuality].
  int? get way => _g._eway[index] < 0 ? null : _g._eway[index];
  set way(int? v) => _g._eway[index] = v ?? -1;

  /// `mtb:scale:uphill` 0–5 auf einem Pfad (#213), sonst null.
  int? get uphill => _g._euphill[index] < 0 ? null : _g._euphill[index];
  set uphill(int? v) => _g._euphill[index] = v ?? -1;

  /// Falsch, solange keine Höhen gelesen wurden oder eine Probe der Kante
  /// keine Höhe hatte — dann rechnet die Kante flach, und der Graph sagt
  /// es ([RoadGraph.edgesWithoutHeights]).
  bool get hasHeights => _g._flag(index, _kHasHeights);
  set hasHeights(bool v) => _g._setFlag(index, _kHasHeights, v);

  @override
  bool operator ==(Object other) => other is GraphEdge && identical(other._g, _g) && other.index == index;

  @override
  int get hashCode => index;
}

const _kOneway = 1, _kBlockForward = 2, _kBlockBackward = 4, _kHasHeights = 8;

/// Eine Liste nur zum Lesen — die Sichten auf die Felder des Graphen.
abstract class _ReadOnlyList<T> extends ListBase<T> {
  @override
  set length(int _) => throw UnsupportedError('Sicht auf den Graphen');

  @override
  void operator []=(int i, T v) => throw UnsupportedError('Sicht auf den Graphen');
}

/// Die Punkte einer Kante, gelesen aus dem Punktspeicher.
class _EdgePoints extends _ReadOnlyList<LatLng> {
  _EdgePoints(this._g, this._off, this.length);

  final RoadGraph _g;
  final int _off;

  @override
  final int length;

  @override
  LatLng operator [](int i) {
    RangeError.checkValidIndex(i, this, null, length);
    return LatLng(_g._plat[_off + i], _g._plon[_off + i]);
  }
}

class _Edges extends _ReadOnlyList<GraphEdge> {
  _Edges(this._g);

  final RoadGraph _g;

  @override
  int get length => _g._edgeCount;

  @override
  GraphEdge operator [](int i) {
    RangeError.checkValidIndex(i, this, null, length);
    return GraphEdge._(_g, i);
  }
}

class _Nodes extends _ReadOnlyList<math.Point<double>> {
  _Nodes(this._g);

  final RoadGraph _g;

  @override
  int get length => _g._nodeCount;

  @override
  math.Point<double> operator [](int i) {
    RangeError.checkValidIndex(i, this, null, length);
    return math.Point(_g._nx[i], _g._ny[i]);
  }
}

class _NodeLatLngs extends _ReadOnlyList<LatLng> {
  _NodeLatLngs(this._g);

  final RoadGraph _g;

  @override
  int get length => _g._nodeCount;

  @override
  LatLng operator [](int i) {
    RangeError.checkValidIndex(i, this, null, length);
    return LatLng(_g._nlat[i], _g._nlon[i]);
  }
}

/// Die Nachbarkanten je Knoten als Liste — für Tests und seltene
/// Abfragen; die Suche geht über [RoadGraph.adjFirst]/[RoadGraph.adjNext].
class _Adjacency extends _ReadOnlyList<List<int>> {
  _Adjacency(this._g);

  final RoadGraph _g;

  @override
  int get length => _g._nodeCount;

  @override
  List<int> operator [](int n) {
    RangeError.checkValidIndex(n, this, null, length);
    return [for (var s = _g.adjFirst(n); s >= 0; s = _g.adjNext(s)) s >> 1];
  }
}

/// Wächst ein Feld über [need] hinaus, um ein Viertel — nicht aufs
/// Doppelte: Nach [RoadGraph.compact] heftet das Laden noch Trail-Enden
/// an, und ein Verdoppeln legte dafür jedes große Feld noch einmal an.
int _grownLength(int length, int need) => need <= length ? length : need + (need >> 2) + 64;

Int32List _growI32(Int32List l, int need) {
  final n = _grownLength(l.length, need);
  return n == l.length ? l : (Int32List(n)..setRange(0, l.length, l));
}

Float64List _growF64(Float64List l, int need) {
  final n = _grownLength(l.length, need);
  return n == l.length ? l : (Float64List(n)..setRange(0, l.length, l));
}

Uint8List _growU8(Uint8List l, int need) {
  final n = _grownLength(l.length, need);
  return n == l.length ? l : (Uint8List(n)..setRange(0, l.length, l));
}

Int8List _growI8(Int8List l, int need) {
  final n = _grownLength(l.length, need);
  return n == l.length ? l : (Int8List(n)..setRange(0, l.length, l));
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

/// Ein Gitter über Zahlen (#378) — Knoten je Zelle oder Segmente je Zelle
/// (die Nummer des ersten Linienpunkts im Punktspeicher). In typisierten
/// Feldern statt `Map<(int, int), List<(int, int)>>`: Bis 0.133.3 hielt
/// allein das Segmentgitter gut 1 Mio. Records und je Zelle eine Liste,
/// rund 65 der 92 MB eines Rahmens mit 65 000 Kanten.
///
/// Die Einträge einer Zelle sind eine verkettete Liste in Reihenfolge des
/// Eintragens, die Zellen sind in Reihenfolge ihres ersten Eintrags
/// nummeriert — wie die Hash-Map bis 0.133.3. Abfragen und
/// [findCrossings] sehen also dieselben Kandidaten in derselben
/// Reihenfolge, und bei gleichem Abstand gewinnt derselbe Treffer.
///
/// Die Zellen findet eine eigene Tabelle mit offener Adressierung
/// ([_slots], Zellnummer + 1, 0 = frei): Eine `Map<int, int>` hielt für
/// 250 000 Zellen eines 25-km-Rahmens rund 10 MB; die Tabelle hält je
/// Platz eine Zahl und je Zelle ihre Koordinaten.
class _CellGrid {
  var _cellCount = 0;
  var _cx = Int32List(0), _cy = Int32List(0), _head = Int32List(0), _tail = Int32List(0);
  var _slots = Int32List(0);
  var _next = Int32List(0), _value = Int32List(0);
  var _entries = 0;

  /// Streuung über beide Koordinaten. Die Faktoren bleiben klein genug,
  /// dass das Produkt auch im Web (Zahlen bis 2^53) genau ist; nur die
  /// unteren Bits zählen.
  static int _hash(int cx, int cy) => (cx * 73856093) ^ (cy * 19349663);

  /// Die Zelle ([cx], [cy]), oder −1.
  int _find(int cx, int cy) {
    if (_cellCount == 0) return -1;
    final mask = _slots.length - 1;
    var i = _hash(cx, cy) & mask;
    while (true) {
      final c = _slots[i] - 1;
      if (c < 0) return -1;
      if (_cx[c] == cx && _cy[c] == cy) return c;
      i = (i + 1) & mask;
    }
  }

  void _place(int c) {
    final mask = _slots.length - 1;
    var i = _hash(_cx[c], _cy[c]) & mask;
    while (_slots[i] != 0) {
      i = (i + 1) & mask;
    }
    _slots[i] = c + 1;
  }

  /// Wie viele Zellen etwas halten.
  int get cellCount => _cellCount;

  void add(int cx, int cy, int value) {
    final k = _entries++;
    if (k >= _next.length) {
      _next = _growI32(_next, k + 1);
      _value = _growI32(_value, k + 1);
    }
    _next[k] = -1;
    _value[k] = value;
    final c = _find(cx, cy);
    if (c >= 0) {
      _next[_tail[c]] = k;
      _tail[c] = k;
      return;
    }
    final nc = _cellCount++;
    if (nc >= _cx.length) {
      _cx = _growI32(_cx, nc + 1);
      _cy = _growI32(_cy, nc + 1);
      _head = _growI32(_head, nc + 1);
      _tail = _growI32(_tail, nc + 1);
    }
    _cx[nc] = cx;
    _cy[nc] = cy;
    _head[nc] = k;
    _tail[nc] = k;
    // Höchstens drei Viertel belegt, sonst doppelt so viele Plätze.
    if (4 * _cellCount > 3 * _slots.length) {
      var size = _slots.isEmpty ? 64 : _slots.length;
      while (4 * _cellCount > 3 * size) {
        size *= 2;
      }
      _slots = Int32List(size);
      for (var i = 0; i < _cellCount; i++) {
        _place(i);
      }
    } else {
      _place(nc);
    }
  }

  /// Der erste Eintrag der Zelle ([cx], [cy]), oder −1.
  int first(int cx, int cy) {
    final c = _find(cx, cy);
    return c < 0 ? -1 : _head[c];
  }

  /// Der erste Eintrag der Zelle Nummer [cell] (0 bis [cellCount] − 1).
  int firstOfCell(int cell) => _head[cell];

  /// Kürzt die Felder auf ihre Länge ([RoadGraph.compact]); die Tabelle
  /// der Plätze bleibt, wie sie ist.
  void compact() {
    _cx = _cx.sublist(0, _cellCount);
    _cy = _cy.sublist(0, _cellCount);
    _head = _head.sublist(0, _cellCount);
    _tail = _tail.sublist(0, _cellCount);
    _next = _next.sublist(0, _entries);
    _value = _value.sublist(0, _entries);
  }

  /// Der Eintrag nach [entry] in seiner Zelle, oder −1.
  int next(int entry) => _next[entry];

  /// Was eingetragen ist: der Knoten oder der erste Punkt des Segments.
  int value(int entry) => _value[entry];
}

/// Ein Treffer auf einer Kante: Abstand, Kante, Segment, Anteil im
/// Segment, Punkt.
typedef EdgeHit = ({double d, int edge, int seg, double t, LatLng at});

class RoadGraph {
  RoadGraph(double lat0) : proj = FlatProjection(lat0);

  final FlatProjection proj;

  // Der Speicher (#378): Knoten, Kanten und Linienpunkte in typisierten
  // Feldern statt als Objekte — so halten es BRouter, GraphHopper und
  // OSRM. Die Felder wachsen beim Bau und werden danach auf ihre Länge
  // gekürzt ([compact]).

  // Knoten: Lage in Metern (Projektion) und in Grad, je Knoten die erste
  // und letzte Nachbarkante und ihre Zahl.
  var _nodeCount = 0;
  var _nx = Float64List(0), _ny = Float64List(0), _nlat = Float64List(0), _nlon = Float64List(0);
  var _adjHead = Int32List(0), _adjTail = Int32List(0), _deg = Int32List(0);

  // Kanten. Jede hat zwei Nachbar-Plätze — 2·ei am Knoten a, 2·ei+1 am
  // Knoten b —, je Knoten eine verkettete Liste in Reihenfolge des
  // Eintragens ([adjFirst], [adjNext]); so sieht die Suche die Kanten in
  // derselben Reihenfolge wie die Listen bis 0.133.x.
  var _edgeCount = 0;
  var _ea = Int32List(0), _eb = Int32List(0), _eoff = Int32List(0), _ecnt = Int32List(0);
  var _adjNext = Int32List(0);
  var _ecls = Uint8List(0), _eflags = Uint8List(0);
  var _elevel = Int8List(0), _eway = Int8List(0), _euphill = Int8List(0);
  var _elen = Float64List(0), _egain = Float64List(0), _eloss = Float64List(0);
  var _esteepUp = Float64List(0), _esteepDown = Float64List(0);
  var _esteepWUp = Float64List(0), _esteepWDown = Float64List(0);
  var _ecarry = Float64List(0);
  final _etrail = <EdgeTrail?>[];

  // Linienpunkte aller Kanten hintereinander, in Grad und in Metern; eine
  // Kante ist ein Abschnitt (_eoff, _ecnt). Eine Teilung schreibt den
  // Teilungspunkt in den ersten Teil und hängt den zweiten hinten an.
  // Das Segmentgitter trägt je Segment die Nummer seines ersten Punkts;
  // _pedge nennt die Kante dazu, den Index im Abschnitt gibt _eoff.
  var _pointCount = 0;
  var _plat = Float64List(0), _plon = Float64List(0), _px = Float64List(0), _py = Float64List(0);
  var _pedge = Int32List(0);

  final _key = <(int, int), int>{};
  final _nodeCells = _CellGrid();
  final _segCells = _CellGrid();

  /// Die Knoten in Metern (Projektion [proj]).
  late final List<math.Point<double>> nodes = _Nodes(this);

  /// Die Knoten in Grad.
  late final List<LatLng> nodeLatLng = _NodeLatLngs(this);

  /// Die Kanten, je Zugriff eine Sicht ([GraphEdge]).
  late final List<GraphEdge> edges = _Edges(this);

  /// Die Nachbarkanten je Knoten, je Zugriff eine neue Liste.
  late final List<List<int>> adj = _Adjacency(this);

  /// Steigt mit jeder Änderung an Knoten oder Kanten (neuer Knoten, neue
  /// Kante, Teilung). Wer Suchergebnisse über eine Rechnung hinaus behält
  /// (`LoopSearchCache`, #188), prüft sie daran: Nach einer Teilung zeigen
  /// gemerkte Vorgänger auf eine Kante, die jetzt woanders endet.
  int revision = 0;

  bool _flag(int ei, int bit) => _eflags[ei] & bit != 0;
  void _setFlag(int ei, int bit, bool on) => _eflags[ei] = on ? _eflags[ei] | bit : _eflags[ei] & ~bit;

  /// Knoten a und b der Kante [ei] — ohne Sicht, für die Suche.
  int edgeA(int ei) => _ea[ei];
  int edgeB(int ei) => _eb[ei];

  /// Der erste Nachbar-Platz am Knoten [n], oder −1; die Kante ist
  /// `platz >> 1`, ihr Ende an [n] ist a, wenn der Platz gerade ist —
  /// außer auf einer Schleife, dort sind es beide.
  int adjFirst(int n) => _adjHead[n];

  /// Der Platz nach [slot] in der Liste seines Knotens, oder −1.
  int adjNext(int slot) => _adjNext[slot];

  /// Darf die Kante [ei] von Knoten [from] aus befahren werden? Einbahn
  /// (nur Straßen) und Trail-Richtung (#174) sperren je eine Richtung.
  bool openFrom(int ei, int from) {
    final forward = _ea[ei] == from;
    final f = _eflags[ei];
    if (f & _kOneway != 0 && !forward) return false;
    return forward ? f & _kBlockForward == 0 : f & _kBlockBackward == 0;
  }

  /// Luftlinie in Metern zwischen Knoten [n] und dem Punkt ([x], [y]).
  double nodeDistance(int n, double x, double y) {
    final dx = _nx[n] - x, dy = _ny[n] - y;
    return math.sqrt(dx * dx + dy * dy);
  }

  math.Point<double> _pointXy(int k) => math.Point(_px[k], _py[k]);

  /// Die Punkte der Kante [ei] in Metern — aus dem Speicher, ohne
  /// erneute Projektion.
  List<math.Point<double>> edgeXy(int ei) {
    final off = _eoff[ei];
    return [for (var i = 0; i < _ecnt[ei]; i++) math.Point(_px[off + i], _py[off + i])];
  }

  static (int, int) _cell(math.Point<double> p) => ((p.x / kGraphCellM).floor(), (p.y / kGraphCellM).floor());

  /// Mikrograd, als Record: Zu EINER Zahl gepackt bräuchte er rund 57 Bit,
  /// im Web (dart2js) sind Zahlen nur bis 2^53 genau (#378).
  static (int, int) _keyOf(LatLng p) => ((p.longitude * 1e6).round(), (p.latitude * 1e6).round());

  /// Der Knoten an [p] — zwei Punkte auf derselben Mikrograd-Koordinate
  /// sind EIN Knoten (so teilen zwei Linien ihren Scheitel).
  int node(LatLng p) {
    final key = _keyOf(p);
    final existing = _key[key];
    if (existing != null) return existing;
    final i = _nodeCount++;
    revision++;
    _key[key] = i;
    final xy = proj.xy(p);
    if (i >= _nx.length) {
      _nx = _growF64(_nx, i + 1);
      _ny = _growF64(_ny, i + 1);
      _nlat = _growF64(_nlat, i + 1);
      _nlon = _growF64(_nlon, i + 1);
      _adjHead = _growI32(_adjHead, i + 1);
      _adjTail = _growI32(_adjTail, i + 1);
      _deg = _growI32(_deg, i + 1);
    }
    _nx[i] = xy.x;
    _ny[i] = xy.y;
    _nlat[i] = p.latitude;
    _nlon[i] = p.longitude;
    _adjHead[i] = -1;
    _adjTail[i] = -1;
    _deg[i] = 0;
    final (cx, cy) = _cell(xy);
    _nodeCells.add(cx, cy, i);
    return i;
  }

  /// Hängt einen Punkt der Kante an, die als nächste angelegt wird
  /// ([_edgeCount]).
  void _addPoint(double lat, double lon, double x, double y) {
    final k = _pointCount++;
    if (k >= _plat.length) {
      _plat = _growF64(_plat, k + 1);
      _plon = _growF64(_plon, k + 1);
      _px = _growF64(_px, k + 1);
      _py = _growF64(_py, k + 1);
      _pedge = _growI32(_pedge, k + 1);
    }
    _pedge[k] = _edgeCount;
    _plat[k] = lat;
    _plon[k] = lon;
    _px[k] = x;
    _py[k] = y;
  }

  void _addLatLng(LatLng p) {
    final xy = proj.xy(p);
    _addPoint(p.latitude, p.longitude, xy.x, xy.y);
  }

  /// Hängt [slot] an die Nachbarliste von [n].
  void _link(int n, int slot) {
    _adjNext[slot] = -1;
    if (_adjHead[n] < 0) {
      _adjHead[n] = slot;
    } else {
      _adjNext[_adjTail[n]] = slot;
    }
    _adjTail[n] = slot;
    _deg[n]++;
  }

  /// Nimmt [slot] aus der Nachbarliste von [n]; die Reihenfolge der
  /// übrigen bleibt.
  void _unlink(int n, int slot) {
    var prev = -1;
    for (var s = _adjHead[n]; s >= 0; s = _adjNext[s]) {
      if (s == slot) {
        final next = _adjNext[s];
        if (prev < 0) {
          _adjHead[n] = next;
        } else {
          _adjNext[prev] = next;
        }
        if (_adjTail[n] == s) _adjTail[n] = prev;
        _deg[n]--;
        return;
      }
      prev = s;
    }
  }

  void _indexSegments(int ei) {
    final off = _eoff[ei];
    for (var i = 0; i < _ecnt[ei] - 1; i++) {
      final ax = _px[off + i], ay = _py[off + i], bx = _px[off + i + 1], by = _py[off + i + 1];
      for (var cx = (math.min(ax, bx) / kGraphCellM).floor(); cx <= (math.max(ax, bx) / kGraphCellM).floor(); cx++) {
        for (var cy = (math.min(ay, by) / kGraphCellM).floor(); cy <= (math.max(ay, by) / kGraphCellM).floor(); cy++) {
          _segCells.add(cx, cy, off + i);
        }
      }
    }
  }

  /// Die Länge des Punktabschnitts ab [off] mit [count] Punkten — dieselbe
  /// Rechnung wie `distanceTo` über die projizierten Punkte.
  double _lengthOf(int off, int count) {
    var sum = 0.0;
    for (var i = off + 1; i < off + count; i++) {
      final dx = _px[i - 1] - _px[i], dy = _py[i - 1] - _py[i];
      sum += math.sqrt(dx * dx + dy * dy);
    }
    return sum;
  }

  int addEdge(int a, int b, WayClass cls, bool oneway, List<LatLng> points, {int level = 0}) {
    final off = _pointCount;
    for (final p in points) {
      _addLatLng(p);
    }
    return _addEdgeAt(a, b, cls.index, oneway ? _kOneway : 0, level, off, points.length);
  }

  /// Legt eine Kante über die schon gespeicherten Punkte ab [off] an.
  int _addEdgeAt(int a, int b, int cls, int flags, int level, int off, int count) {
    final ei = _edgeCount++;
    if (ei >= _ea.length) {
      final need = ei + 1;
      _ea = _growI32(_ea, need);
      _eb = _growI32(_eb, need);
      _eoff = _growI32(_eoff, need);
      _ecnt = _growI32(_ecnt, need);
      _adjNext = _growI32(_adjNext, 2 * _ea.length);
      _ecls = _growU8(_ecls, need);
      _eflags = _growU8(_eflags, need);
      _elevel = _growI8(_elevel, need);
      _eway = _growI8(_eway, need);
      _euphill = _growI8(_euphill, need);
      _elen = _growF64(_elen, need);
      _egain = _growF64(_egain, need);
      _eloss = _growF64(_eloss, need);
      _esteepUp = _growF64(_esteepUp, need);
      _esteepDown = _growF64(_esteepDown, need);
      _esteepWUp = _growF64(_esteepWUp, need);
      _esteepWDown = _growF64(_esteepWDown, need);
      _ecarry = _growF64(_ecarry, need);
    }
    _ea[ei] = a;
    _eb[ei] = b;
    _eoff[ei] = off;
    _ecnt[ei] = count;
    _ecls[ei] = cls;
    _eflags[ei] = flags;
    _elevel[ei] = level;
    _eway[ei] = -1;
    _euphill[ei] = -1;
    _elen[ei] = _lengthOf(off, count);
    _egain[ei] = 0;
    _eloss[ei] = 0;
    _esteepUp[ei] = 0;
    _esteepDown[ei] = 0;
    _esteepWUp[ei] = 0;
    _esteepWDown[ei] = 0;
    _ecarry[ei] = 1;
    _etrail.add(null);
    revision++;
    _link(a, 2 * ei);
    _link(b, 2 * ei + 1);
    _indexSegments(ei);
    return ei;
  }

  int degree(int n) => _deg[n];

  /// Teilt die Kante [ei] an Segment [seg], Anteil [t], beim Punkt [at];
  /// der erste Teil behält [ei] (seine Gittereinträge bleiben gültig —
  /// das Segment wird nur kürzer), der Rest wird eine neue Kante.
  /// Liefert den Knoten an der Teilung.
  int splitEdge(int ei, int seg, LatLng at) {
    final mid = node(at);
    final oldB = _eb[ei];
    if (mid == _ea[ei] || mid == oldB) return mid;
    final off = _eoff[ei], count = _ecnt[ei];
    final atXy = proj.xy(at);
    // Der zweite Teil hinten an: der Teilungspunkt, dann der Rest.
    final secondOff = _pointCount;
    _addPoint(at.latitude, at.longitude, atXy.x, atXy.y);
    for (var i = off + seg + 1; i < off + count; i++) {
      _addPoint(_plat[i], _plon[i], _px[i], _py[i]);
    }
    // Der erste Teil endet am Teilungspunkt — an seiner Stelle im Speicher.
    final end = off + seg + 1;
    _plat[end] = at.latitude;
    _plon[end] = at.longitude;
    _px[end] = atXy.x;
    _py[end] = atXy.y;
    _unlink(oldB, 2 * ei + 1);
    _ecnt[ei] = seg + 2;
    _eb[ei] = mid;
    _elen[ei] = _lengthOf(off, seg + 2);
    _link(mid, 2 * ei + 1);
    // Die zweite Hälfte erbt, was auf der Kante liegt — sonst ließe ein
    // angehefteter Trailkopf den Rest eines Trails rückwärts befahrbar.
    final ni = _addEdgeAt(mid, oldB, _ecls[ei], _eflags[ei], _elevel[ei], secondOff, count - seg);
    _etrail[ni] = _etrail[ei];
    _eway[ni] = _eway[ei];
    _euphill[ni] = _euphill[ei];
    final firstLen = _elen[ei], secondLen = _elen[ni];
    // Der Trage-Aufschlag gehört der ganzen Treppe, nicht jeder Hälfte.
    final carryShare = firstLen + secondLen == 0 ? 0.0 : secondLen / (firstLen + secondLen);
    _ecarry[ni] = _ecarry[ei] * carryShare;
    _ecarry[ei] = _ecarry[ei] * (1 - carryShare);
    if (_egain[ei] > 0 ||
        _eloss[ei] > 0 ||
        _esteepUp[ei] > 0 ||
        _esteepDown[ei] > 0 ||
        _esteepWUp[ei] > 0 ||
        _esteepWDown[ei] > 0) {
      // Höhen anteilig nach Länge — genauer weiß es niemand, und flach
      // wäre falscher.
      final total = firstLen + secondLen;
      final share = total == 0 ? 0.0 : secondLen / total;
      for (final f in [_egain, _eloss, _esteepUp, _esteepDown, _esteepWUp, _esteepWDown]) {
        f[ni] = f[ei] * share;
        f[ei] = f[ei] * (1 - share);
      }
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
        for (var k = _nodeCells.first(cx + dx, cy + dy); k >= 0; k = _nodeCells.next(k)) {
          final n = _nodeCells.value(k);
          if (n == exclude) continue;
          final d = nodeDistance(n, p.x, p.y);
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
    final seen = <int>{};
    for (var dx = -reach; dx <= reach; dx++) {
      for (var dy = -reach; dy <= reach; dy++) {
        for (var k = _segCells.first(cx + dx, cy + dy); k >= 0; k = _segCells.next(k)) {
          final o = _segCells.value(k);
          final ei = _pedge[o], i = o - _eoff[ei];
          if (excludeEdges.contains(ei) || !seen.add(o)) continue;
          if (i + 1 >= _ecnt[ei]) continue; // veraltet nach einer Teilung
          final ax = _px[o], ay = _py[o], bx = _px[o + 1], by = _py[o + 1];
          final (d, t) = _pointSegment(xy.x, xy.y, ax, ay, bx, by);
          if (d <= radius && (best == null || d < best.d)) {
            final px = math.Point(ax + t * (bx - ax), ay + t * (by - ay));
            best = (d: d, edge: ei, seg: i, t: t, at: proj.latLng(px));
          }
        }
      }
    }
    return best;
  }

  /// Abstand von (px, py) zur Strecke a–b und der Anteil des Fußpunkts —
  /// dieselbe Rechnung wie bis 0.133.x über `math.Point`.
  static (double, double) _pointSegment(double px, double py, double ax, double ay, double bx, double by) {
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) {
      final ex = px - ax, ey = py - ay;
      return (math.sqrt(ex * ex + ey * ey), 0.0);
    }
    final t = (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0);
    final qx = ax + t * dx, qy = ay + t * dy;
    final ex = px - qx, ey = py - qy;
    return (math.sqrt(ex * ex + ey * ey), t);
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

  /// Kürzt alle Felder auf ihre Länge — nach dem Bau, wenn das Wachsen
  /// vorbei ist. Spätere Kanten (Anheften) lassen sie wieder wachsen.
  void compact() {
    final n = _nodeCount, e = _edgeCount, p = _pointCount;
    _nx = _nx.sublist(0, n);
    _ny = _ny.sublist(0, n);
    _nlat = _nlat.sublist(0, n);
    _nlon = _nlon.sublist(0, n);
    _adjHead = _adjHead.sublist(0, n);
    _adjTail = _adjTail.sublist(0, n);
    _deg = _deg.sublist(0, n);
    _ea = _ea.sublist(0, e);
    _eb = _eb.sublist(0, e);
    _eoff = _eoff.sublist(0, e);
    _ecnt = _ecnt.sublist(0, e);
    _adjNext = _adjNext.sublist(0, 2 * e);
    _ecls = _ecls.sublist(0, e);
    _eflags = _eflags.sublist(0, e);
    _elevel = _elevel.sublist(0, e);
    _eway = _eway.sublist(0, e);
    _euphill = _euphill.sublist(0, e);
    _elen = _elen.sublist(0, e);
    _egain = _egain.sublist(0, e);
    _eloss = _eloss.sublist(0, e);
    _esteepUp = _esteepUp.sublist(0, e);
    _esteepDown = _esteepDown.sublist(0, e);
    _esteepWUp = _esteepWUp.sublist(0, e);
    _esteepWDown = _esteepWDown.sublist(0, e);
    _ecarry = _ecarry.sublist(0, e);
    _plat = _plat.sublist(0, p);
    _plon = _plon.sublist(0, p);
    _px = _px.sublist(0, p);
    _py = _py.sublist(0, p);
    _pedge = _pedge.sublist(0, p);
    _nodeCells.compact();
    _segCells.compact();
  }

  /// Zusammenhangskomponenten als Kantenlisten, längste zuerst.
  List<List<int>> components() {
    final parent = List<int>.generate(_nodeCount, (i) => i);
    int find(int i) {
      while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
      }
      return i;
    }

    for (var ei = 0; ei < _edgeCount; ei++) {
      final ra = find(_ea[ei]), rb = find(_eb[ei]);
      if (ra != rb) parent[ra] = rb;
    }
    final comp = <int, List<int>>{};
    for (var i = 0; i < _edgeCount; i++) {
      (comp[find(_ea[i])] ??= []).add(i);
    }
    double lengthOf(List<int> es) => es.fold(0.0, (s, i) => s + _elen[i]);
    return comp.values.toList()..sort((x, y) => lengthOf(y).compareTo(lengthOf(x)));
  }

  double get totalLength {
    var sum = 0.0;
    for (var i = 0; i < _edgeCount; i++) {
      sum += _elen[i];
    }
    return sum;
  }

  /// Anteil der Kantenlänge in der größten Komponente — die Zahl aus M1.
  double get largestComponentShare {
    final total = totalLength;
    if (total == 0) return 0;
    final largest = components().firstOrNull;
    return largest == null ? 0 : largest.fold(0.0, (s, i) => s + _elen[i]) / total;
  }

  int get edgesWithoutHeights {
    var n = 0;
    for (var i = 0; i < _edgeCount; i++) {
      if (!_flag(i, _kHasHeights)) n++;
    }
    return n;
  }
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
  // Die drei Schritte als Marken (#356): Der Stall-Wächter nennt den,
  // der den Takt aufhielt.
  final g = PlanProgress.part(0, 0.19, () => StallWatch.mark('graph.nodes', () {
    final counts = <(int, int), int>{};
    final all = lines.toList();
    for (final l in all) {
      for (final p in l.points) {
        final k = RoadGraph._keyOf(p);
        counts[k] = (counts[k] ?? 0) + 1;
      }
    }
    final g = RoadGraph(lat0);
    for (var li = 0; li < all.length; li++) {
      final l = all[li];
      if (li & 255 == 0) PlanProgress.steps(li, all.length);
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
    return g;
  }));
  final joins =
      joinM > 0 ? PlanProgress.part(0.19, 0.54, () => StallWatch.mark('graph.joins', () => _joinDeadEnds(g, joinM))) : 0;
  final crossings =
      splitCrossings ? PlanProgress.part(0.54, 1, () => StallWatch.mark('graph.crossings', () => _splitCrossings(g))) : 0;
  g.compact();
  return (graph: g, joins: joins, crossings: crossings);
}

/// Bindet jedes tote Ende innerhalb von [joinM] an den nächsten anderen
/// Weg (Regel 2 aus M1); gibt die Zahl der Anbindungen.
int _joinDeadEnds(RoadGraph g, double joinM) {
  var joins = 0;
  final count = g.nodes.length; // neue Knoten aus Teilungen brauchen keinen Join
  for (var n = 0; n < count; n++) {
    if (n & 255 == 0) PlanProgress.steps(n, count);
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
      g.addEdge(n, target, g.edges[g.adjFirst(n) >> 1].cls, false, [g.nodeLatLng[n], g.nodeLatLng[target]]);
      joins++;
    }
  }
  return joins;
}

/// Teilt jede Kreuzung zweier Wege derselben Ebene ohne gemeinsamen
/// Knoten (Regel 3 aus M1); gibt die Zahl der Teilungen.
int _splitCrossings(RoadGraph g) {
  var crossings = 0;
  final found = PlanProgress.part(0, 0.6, () => findCrossings(g));
  for (var k = 0; k < found.length; k++) {
    final c = found[k];
    if (k & 63 == 0) PlanProgress.report(0.6 + 0.4 * k / found.length);
    // Erst die eine Kante teilen (attach legt den Knoten an), dann die
    // andere am selben Punkt — der Knotenschlüssel macht beide eins.
    final mid = g.attach(c.at, radius: 0.5);
    if (mid == null) continue;
    final hit = g.nearest(c.at, 0.5, excludeEdges: g.adj[mid].toSet());
    if (hit == null) continue;
    g.splitEdge(hit.edge, hit.seg, c.at);
    crossings++;
  }
  return crossings;
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
///
/// Der Schlüssel in `seen` ist FLACH: Ein verschachtelter Record
/// (`((int, int), (int, int))`) fällt bei jedem `add` in die langsame
/// Typprüfung der VM (gemessen gut zehnmal langsamer) — so lag 0.127.0
/// mit 36 s Rechnen im UI-Isolate im ANR (#354).
List<({LatLng at, int edgeA, int edgeB})> findCrossings(RoadGraph g) {
  final out = <({LatLng at, int edgeA, int edgeB})>[];
  // Ein Segment ist die Nummer seines ersten Punkts (eindeutig je Kante
  // und Index), das Paar also zwei Zahlen, geordnet nach Kante.
  final seen = <(int, int)>{};
  final grid = g._segCells;
  final cells = grid.cellCount;
  final segs = <int>[];
  for (var cell = 0; cell < cells; cell++) {
    if (cell & 255 == 0) PlanProgress.steps(cell + 1, cells);
    segs.clear();
    for (var k = grid.firstOfCell(cell); k >= 0; k = grid.next(k)) {
      segs.add(grid.value(k));
    }
    for (var i = 0; i < segs.length; i++) {
      final oa = segs[i];
      final ea = g._pedge[oa];
      if (oa - g._eoff[ea] + 1 >= g._ecnt[ea]) continue;
      final a = g._pointXy(oa), b = g._pointXy(oa + 1);
      for (var j = i + 1; j < segs.length; j++) {
        final ob = segs[j];
        final eb = g._pedge[ob];
        if (eb == ea) continue;
        if (ob - g._eoff[eb] + 1 >= g._ecnt[eb] || g._elevel[ea] != g._elevel[eb]) continue;
        final key = ea < eb ? (oa, ob) : (ob, oa);
        if (!seen.add(key)) continue;
        final hit = properCrossing(a, b, g._pointXy(ob), g._pointXy(ob + 1));
        if (hit == null) continue;
        out.add((at: g.proj.latLng(hit), edgeA: ea, edgeB: eb));
      }
    }
  }
  return out;
}

/// Liest je Kante Anstieg und Abstieg aus den Höhenkacheln (alle 50 m,
/// 10 m Hysterese plus der Rest bis zum Ende — [edgeClimb]). Eine Kante
/// ohne Höhe an einer Probe bleibt flach und ist als solche markiert.
Future<void> addClimbs(RoadGraph g, HeightReader heights) async {
  for (final e in g.edges) {
    _applyProfile(e, await heights.profileAlong(e.points));
  }
}

/// [addClimbs] aus vorab gelesenen Kacheln, synchron — der Weg im
/// Rechen-Isolate des Planers (#356 PR 8), dieselben Zahlen.
void addClimbsFrom(RoadGraph g, HeightTiles heights) {
  for (var i = 0; i < g.edges.length; i++) {
    if (i & 255 == 0) PlanProgress.steps(i, g.edges.length);
    _applyProfile(g.edges[i], heights.profileAlong(g.edges[i].points));
  }
}

void _applyProfile(GraphEdge e, ({List<double> heights, List<double> stepsM})? profile) {
  if (profile == null) {
    e.hasHeights = false;
    return;
  }
  final (gain, loss) = edgeClimb(profile.heights, kClimbHysteresisM);
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
