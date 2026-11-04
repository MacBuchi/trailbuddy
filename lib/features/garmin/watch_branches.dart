// Die Abzweigungen für die Uhr (docs/konzept-garmin.md, Abschnitte 1
// und 2; Betreiber 2026-11-04: „muss nicht der ganze Weg sein"): je
// Kreuzung der Route ein Stummel des abgehenden Wegs, 40 m. Man sieht,
// DASS man abbiegen kann und wohin die Route geht — kein Kartenbild, kein
// Abbiegehinweis (Entscheidung 3).
//
// Gerechnet wird im Rechen-Isolate des Planers ([WatchBranchesJob]) auf
// dem Graphen des Korridors unter der Linie: OSM-Wege und die Trails, die
// der Nutzer sieht (`loadPlanningGraph`), keine fremden (A1, A2). Pur und
// sendbar — keine Closures, kein Riverpod.
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../routing/graph_input.dart' show GraphJob;
import '../routing/loop_planner.dart' show LoopSearchCache;
import '../routing/road_graph.dart';

/// So lang ist ein Stummel (Konzept 1).
const kWatchBranchM = 40.0;

/// Ein Knoten so nah an der Linie ist eine Kreuzung DER Route.
const kWatchBranchNodeM = 8.0;

/// So weit vom Knoten prüft man, ob eine Kante der Route folgt …
const kWatchBranchProbeM = 15.0;

/// … und so nah an der Linie heißt „folgt".
const kWatchBranchOnRouteM = 6.0;

/// Kürzere Kanten zeigen keine Richtung — kein Stummel.
const kWatchBranchMinM = 10.0;

/// Mehr Stummel nimmt die Uhr nicht (Speicher, Messung 8.1): Darüber
/// bleibt jeder n-te, gleichmäßig über die Route.
const kWatchMaxBranches = 300;

/// Ein Stummel: an der Kreuzung [at], die am nächsten beim Punkt [index]
/// der Linie liegt (vor dem Vereinfachen), Ende [end]. Die Uhr setzt ihn
/// am Punkt der Linie an, mit dem Versatz [end] − [at] — bei einer
/// GPS-Fahrt liegt der Punkt ein paar Meter neben dem Knoten.
typedef WatchBranch = ({int index, LatLng at, LatLng end});

/// Die Stummel entlang [line] auf dem gehaltenen Graphen.
class WatchBranchesJob implements GraphJob<List<WatchBranch>> {
  const WatchBranchesJob(this.line);

  final List<LatLng> line;

  @override
  List<WatchBranch> runOn(RoadGraph g, LoopSearchCache cache) => watchBranchesOn(g, line);
}

/// Je Knoten mit drei und mehr Kanten, der höchstens [kWatchBranchNodeM]
/// neben [line] liegt und an dem mindestens eine Kante der Route folgt:
/// ein Stummel je Kante, die das nicht tut. Nach [WatchBranch.index]
/// sortiert — die Uhr hört beim Zeichnen nach vorn auf zu suchen.
List<WatchBranch> watchBranchesOn(RoadGraph g, List<LatLng> line) {
  if (line.length < 2) return const [];
  final route = _RouteIndex(g.proj.line(line));
  final out = <WatchBranch>[];
  final nodes = g.nodes;
  for (var n = 0; n < nodes.length; n++) {
    if (g.degree(n) < 3) continue;
    final p = nodes[n];
    final index = route.nearest(p.x, p.y, kWatchBranchNodeM);
    if (index == null) continue;
    final stubs = <LatLng>[];
    var follows = 0;
    for (var slot = g.adjFirst(n); slot >= 0; slot = g.adjNext(slot)) {
      final ei = slot >> 1;
      final a = g.edgeA(ei), b = g.edgeB(ei);
      if (a == b) continue; // Schleife: keine Richtung
      var xy = g.edgeXy(ei);
      if (b == n) xy = xy.reversed.toList();
      final len = _length(xy);
      if (len < kWatchBranchMinM) continue;
      final probe = _pointAlong(xy, math.min(kWatchBranchProbeM, len));
      if (route.distance(probe.x, probe.y, kWatchBranchOnRouteM) != null) {
        follows++;
      } else {
        stubs.add(g.proj.latLng(_pointAlong(xy, math.min(kWatchBranchM, len))));
      }
    }
    if (follows == 0) continue; // ein Weg daneben, nicht die Route
    final at = g.proj.latLng(p);
    for (final e in stubs) {
      out.add((index: index, at: at, end: e));
    }
  }
  out.sort((x, y) => x.index.compareTo(y.index));
  if (out.length <= kWatchMaxBranches) return out;
  final step = out.length / kWatchMaxBranches;
  return [for (var k = 0; k < kWatchMaxBranches; k++) out[(k * step).floor()]];
}

double _length(List<math.Point<double>> xy) {
  var s = 0.0;
  for (var i = 1; i < xy.length; i++) {
    s += xy[i].distanceTo(xy[i - 1]);
  }
  return s;
}

math.Point<double> _pointAlong(List<math.Point<double>> xy, double m) {
  var left = m;
  for (var i = 1; i < xy.length; i++) {
    final a = xy[i - 1], b = xy[i];
    final d = a.distanceTo(b);
    if (d >= left && d > 0) {
      final t = left / d;
      return math.Point(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y));
    }
    left -= d;
  }
  return xy.last;
}

/// Die Segmente der Linie in einem 25-m-Gitter — für „wie weit neben der
/// Route" und „welcher Punkt der Route", ohne über die ganze Linie zu
/// laufen.
class _RouteIndex {
  _RouteIndex(this.xy) {
    for (var i = 0; i + 1 < xy.length; i++) {
      final a = xy[i], b = xy[i + 1];
      final x0 = (math.min(a.x, b.x) / _cell).floor(), x1 = (math.max(a.x, b.x) / _cell).floor();
      final y0 = (math.min(a.y, b.y) / _cell).floor(), y1 = (math.max(a.y, b.y) / _cell).floor();
      for (var cx = x0; cx <= x1; cx++) {
        for (var cy = y0; cy <= y1; cy++) {
          (_cells[(cx, cy)] ??= []).add(i);
        }
      }
    }
  }

  static const _cell = 25.0;
  final List<math.Point<double>> xy;
  final _cells = <(int, int), List<int>>{};

  /// Abstand zur Linie, wenn höchstens [radius] (≤ eine Zelle), sonst null.
  double? distance(double x, double y, double radius) => _hit(x, y, radius)?.$1;

  /// Der nächste Punkt der Linie am nächsten Segment, wenn die Linie
  /// höchstens [radius] entfernt ist.
  int? nearest(double x, double y, double radius) {
    final hit = _hit(x, y, radius);
    if (hit == null) return null;
    final (_, i, t) = hit;
    return t < 0.5 ? i : i + 1;
  }

  (double, int, double)? _hit(double x, double y, double radius) {
    final cx = (x / _cell).floor(), cy = (y / _cell).floor();
    (double, int, double)? best;
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        final segs = _cells[(cx + dx, cy + dy)];
        if (segs == null) continue;
        for (final i in segs) {
          final a = xy[i], b = xy[i + 1];
          final ex = b.x - a.x, ey = b.y - a.y;
          final l2 = ex * ex + ey * ey;
          final t = l2 == 0 ? 0.0 : (((x - a.x) * ex + (y - a.y) * ey) / l2).clamp(0.0, 1.0);
          final qx = a.x + t * ex - x, qy = a.y + t * ey - y;
          final d = math.sqrt(qx * qx + qy * qy);
          // Bei gleichem Abstand das frühere Segment: Eine Runde berührt
          // dieselbe Kreuzung zweimal, der Stummel gehört zum ersten Mal.
          if (d <= radius && (best == null || d < best.$1)) best = (d, i, t);
        }
      }
    }
    return best;
  }
}
