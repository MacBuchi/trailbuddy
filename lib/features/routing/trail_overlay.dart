// Die eigenen Trails auf dem Wegegraphen (#174, #185) — Feldbericht
// 0.73.0: „Man sollte nie rückwärts über einen Trail fahren, außer der
// Trail ist so attributiert" und „Uphill-Trails / Verbinder sollten
// belohnt werden, diese können auch mehrfach befahren werden".
//
// Der Graph kommt aus der Karte, und dort steht ein Singletrail oft als
// Pfad: Der Planer kletterte über ihn hinauf, gegen die Richtung, in der
// ihn alle fahren. Hier bekommt jede Kante, die auf einem sichtbaren Trail
// liegt, dessen Richtung:
// - **Abfahrt** (jeder Trail ohne Uphill/Verbindung unter den angezeigten
//   Merkmalen): gegen die Richtung gesperrt, außer „in beide Richtungen
//   fahrbar" (Patch 016). In Richtung bleibt sie ein Weg wie jeder.
// - **Uphill-Trail**: ein Verbinder in SEINER Richtung (bergauf),
//   dagegen gesperrt — außer in beide Richtungen fahrbar.
// - **Verbindung**: ein Verbinder in beide Richtungen.
// Ein Verbinder kostet weniger als Forstweg (`kTrailConnectorFactor`) und
// zählt nicht als Wanderweg. Mehrfach befahren darf man ihn, wie jeden
// Weg — Verbindungen werden nie bestraft, nur eine zweite ABFAHRT bringt
// weniger (`kLoopSecondPassShare`).
//
// Auf der Kante heißt: ≥ [kMatchCoverage] ihrer Proben (alle
// [kMatchSampleStepM]) liegen im Korridor von [kMatchCorridorM] — dieselben
// Schwellen wie der Abgleich und das Zerlege-Blatt (`line_geometry.dart`).
// Ein Forstweg, über den ein Trail nur 100 m seiner 2 km läuft, bleibt ein
// Forstweg. Die Richtung sagt die Lage der ersten und der letzten Probe
// entlang des Trails.
//
// Ein Verbinder, den die Karte nicht kennt (die meisten privaten Trails
// stehen nicht in OSM), kommt als EIGENE Kante dazu, von Anfang zu Ende,
// angeheftet in [kGraphAttachM]. Abfahrten brauchen das nicht: Die
// fährt der Planer als Halt, von Kopf zu Ende.
//
// Gesperrt (#434, Betreiber 2026-10-31): Ein Trail mit der Meldung
// „gesperrt" oder „zerstört" ([GraphTrail.closed]) und ein gesperrter
// Abschnitt der offiziellen Quelle (#41) sperren die Kanten unter sich in
// BEIDE Richtungen — [blockClosures], NACH dem Anheften der Enden. Eine
// gesperrte Abfahrt, die der Fahrer selbst wählt, fährt der Planer
// trotzdem: als Halt über ihre eigene Linie. Damit ihr Kopf und ihr Ende
// erreichbar bleiben, bleiben die Kanten in [kClosedEndOpenM] um beide
// Enden offen (in Trail-Richtung, wie jede Abfahrt).
//
// Rein: keine Widgets, kein Riverpod.
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../core/line_geometry.dart';
import 'road_graph.dart';
import 'route_profile.dart';

/// Was ein Trail für den Graphen ist.
enum TrailRole {
  /// Wird bergab gefahren — als Halt der Runde.
  downhill,

  /// Ein Uphill-Trail: Verbinder in seiner Richtung.
  uphill,

  /// Eine Verbindung: Verbinder in beide Richtungen.
  connector,
}

/// Ein Trail, wie der Graph ihn braucht: Punkte in Trail-Richtung, Rolle,
/// ob er in beide Richtungen fahrbar ist, und — für eine eigene Kante —
/// seine Höhenmeter in Trail-Richtung, wenn er welche hat.
class GraphTrail {
  const GraphTrail({
    required this.id,
    required this.name,
    required this.points,
    required this.role,
    this.twoWay = false,
    this.gainM,
    this.lossM,
    this.closed = false,
  });

  final String id;
  final String name;
  final List<LatLng> points;
  final TrailRole role;
  final bool twoWay;
  final double? gainM;
  final double? lossM;

  /// Gemeldet als gesperrt oder zerstört (#434): kein Weg für die
  /// Verbindungen, nur als selbst gewählter Halt.
  final bool closed;

  bool get connector => role != TrailRole.downhill;

  /// Gegen die Trail-Richtung gesperrt? Eine Verbindung nie, sonst nur,
  /// wenn der Trail nicht in beide Richtungen fahrbar ist.
  bool get blocksReverse => role != TrailRole.connector && !twoWay;
}

/// Was [applyTrails] getan hat — für Tests und das Blatt.
typedef TrailOverlayResult = ({int edgesOnTrails, int blocked, int addedEdges});

/// Legt [trails] auf [g]: markiert die Kanten auf ihnen (Richtung,
/// Verbinder) und fügt Verbinder ein, die die Karte nicht kennt. Vor dem
/// Anheften der Trail-Enden und Startpunkte aufrufen — `splitEdge` gibt
/// die Markierung an beide Hälften weiter.
TrailOverlayResult applyTrails(RoadGraph g, List<GraphTrail> trails) {
  final prepared = <_Prepared>[];
  for (final t in trails) {
    if (t.points.length < 2) continue;
    prepared.add(_prepare(g, t));
  }
  var onTrails = 0, blocked = 0;
  // 1. Die Kanten der Karte, die auf einem Trail liegen.
  final edgeCount = g.edges.length;
  for (var ei = 0; ei < edgeCount; ei++) {
    final e = g.edges[ei];
    final exy = g.proj.line(e.points);
    final box = _Box.of(exy);
    // Erst der Rahmen, dann die Proben: Die meisten Kanten liegen weit
    // weg von jedem Trail.
    final near = [for (final p in prepared) if (p.box.near(box, kMatchCorridorM)) p];
    if (near.isEmpty) continue;
    final samples = resampleXy(exy, kMatchSampleStepM);
    _Prepared? best;
    var bestCov = 0.0;
    for (final p in near) {
      final cov = coverageWithin(samples, p.grid, kMatchCorridorM);
      if (cov >= kMatchCoverage && cov > bestCov) {
        best = p;
        bestCov = cov;
      }
    }
    if (best == null) continue;
    onTrails++;
    final t = best.trail;
    e.trail = EdgeTrail(id: t.id, name: t.name, connector: t.connector);
    if (!t.blocksReverse) continue;
    // Die Richtung: Wo entlang des Trails liegen erste und letzte Probe?
    final from = best.position(samples.first), to = best.position(samples.last);
    if ((to - from).abs() < kMatchSampleStepM) continue; // quer oder zu kurz
    if (to > from) {
      e.blockBackward = true;
    } else {
      e.blockForward = true;
    }
    blocked++;
  }
  // 2. Verbinder, die die Karte nicht führt: eine eigene Kante.
  var added = 0;
  for (final p in prepared) {
    final t = p.trail;
    if (!t.connector || t.closed) continue;
    var covered = 0;
    for (final s in p.samples) {
      if (g.nearest(g.proj.latLng(s), kMatchCorridorM) != null) covered++;
    }
    if (p.samples.isNotEmpty && covered / p.samples.length >= kMatchCoverage) continue;
    final a = g.attach(t.points.first), b = g.attach(t.points.last);
    if (a == null || b == null || a == b) continue;
    final ei = g.addEdge(a, b, WayClass.wanderweg, false, [g.nodeLatLng[a], ...t.points, g.nodeLatLng[b]]);
    final e = g.edges[ei]..trail = EdgeTrail(id: t.id, name: t.name, connector: true);
    if (t.gainM != null && t.lossM != null) {
      e
        ..gain = t.gainM!
        ..loss = t.lossM!
        ..hasHeights = true;
    }
    if (t.blocksReverse) e.blockBackward = true;
    added++;
  }
  return (edgesOnTrails: onTrails, blocked: blocked, addedEdges: added);
}

/// So weit um Kopf und Ende eines gesperrten Trails bleiben die Kanten auf
/// ihm offen ([blockClosures]) — die Stummel, an denen seine Enden hängen.
/// Durchfahren lässt sich der Trail über sie nicht.
const kClosedEndOpenM = 30.0;

/// Sperrt die Kanten auf gesperrten Trails ([GraphTrail.closed]) und unter
/// gesperrten Abschnitten der offiziellen Quelle ([closures], #41) in beide
/// Richtungen (#434) — außer den Stummeln in [kClosedEndOpenM] um Kopf und
/// Ende jedes Trails. Nach [applyTrails] UND dem Anheften der Enden
/// aufrufen: Erst dann sind die Stummel eigene Kanten. Auf der Linie heißt wie dort: ≥ [kMatchCoverage] der
/// Proben im Korridor. Gibt die Zahl der gesperrten Kanten zurück.
int blockClosures(RoadGraph g, List<GraphTrail> trails, {List<List<LatLng>> closures = const []}) {
  final byId = {for (final t in trails) if (t.points.length >= 2) t.id: t};
  final prepared = <String, _Prepared>{};
  final lines = [
    for (final c in closures)
      if (c.length >= 2) g.proj.line(c),
  ];
  if (!byId.values.any((t) => t.closed) && lines.isEmpty) return 0;
  final linesGrid = lines.isEmpty ? null : SegmentGrid(lines, 50);
  final lineBoxes = [for (final l in lines) _Box.of(l)];
  var count = 0;
  final edgeCount = g.edges.length;
  for (var ei = 0; ei < edgeCount; ei++) {
    final e = g.edges[ei];
    final t = byId[e.trail?.id];
    final exy = g.proj.line(e.points);
    List<math.Point<double>>? samples;
    var block = t?.closed ?? false;
    if (!block && linesGrid != null) {
      final box = _Box.of(exy);
      if (lineBoxes.any((b) => b.near(box, kMatchCorridorM))) {
        samples = resampleXy(exy, kMatchSampleStepM);
        block = coverageWithin(samples, linesGrid, kMatchCorridorM) >= kMatchCoverage;
      }
    }
    if (!block) continue;
    // Die Stummel um Kopf und Ende eines Trails bleiben offen — auch unter
    // einer offiziellen Sperre: Sonst wäre er als selbst gewählter Halt
    // nicht mehr zu erreichen.
    if (t != null) {
      final p = prepared[t.id] ??= _prepare(g, t);
      samples ??= resampleXy(exy, kMatchSampleStepM);
      final from = p.position(samples.first), to = p.position(samples.last);
      final len = p.cum.last;
      if (math.max(from, to) <= kClosedEndOpenM || math.min(from, to) >= len - kClosedEndOpenM) continue;
    }
    e
      ..blockForward = true
      ..blockBackward = true;
    count++;
  }
  return count;
}

_Prepared _prepare(RoadGraph g, GraphTrail t) {
  final xy = g.proj.line(t.points);
  return _Prepared(t, xy, resampleXy(xy, kMatchSampleStepM), _cumulative(xy), SegmentGrid([xy], 50));
}

List<double> _cumulative(List<math.Point<double>> xy) {
  final out = <double>[0];
  for (var i = 1; i < xy.length; i++) {
    out.add(out.last + xy[i - 1].distanceTo(xy[i]));
  }
  return out;
}

class _Box {
  _Box(this.minX, this.minY, this.maxX, this.maxY);

  factory _Box.of(List<math.Point<double>> pts) {
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (final p in pts) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
    }
    return _Box(minX, minY, maxX, maxY);
  }

  final double minX, minY, maxX, maxY;

  bool near(_Box o, double d) =>
      !(maxX + d < o.minX || o.maxX + d < minX || maxY + d < o.minY || o.maxY + d < minY);
}

class _Prepared {
  _Prepared(this.trail, this.xy, this.samples, this.cum, this.grid) : box = _Box.of(xy);

  final GraphTrail trail;
  final List<math.Point<double>> xy;
  final List<math.Point<double>> samples;
  final List<double> cum;
  final SegmentGrid grid;
  final _Box box;

  /// Wie weit entlang des Trails der nächste Punkt zu [p] liegt, in Metern.
  double position(math.Point<double> p) {
    var bestD = double.infinity, bestPos = 0.0;
    for (var i = 1; i < xy.length; i++) {
      final a = xy[i - 1], b = xy[i];
      final dx = b.x - a.x, dy = b.y - a.y;
      final len2 = dx * dx + dy * dy;
      final t = len2 == 0 ? 0.0 : (((p.x - a.x) * dx + (p.y - a.y) * dy) / len2).clamp(0.0, 1.0);
      final q = math.Point(a.x + t * dx, a.y + t * dy);
      final d = p.distanceTo(q);
      if (d < bestD) {
        bestD = d;
        bestPos = cum[i - 1] + t * math.sqrt(len2);
      }
    }
    return bestPos;
  }
}
