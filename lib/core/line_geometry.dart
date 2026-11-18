// Die ebene Linien-Geometrie, die der Abgleich auf dem Gerät braucht —
// EINE Fassung für „Auch ausgeschildert als …" (`official_match.dart`)
// und das Zerlege-Blatt (`ride_split.dart`, #29). Bis 0.19.0 lag sie
// privat im ersten; das zweite hätte sie kopiert, und zwei Fassungen der
// Korridor-Rechnung wären zwei Meinungen darüber, was „im Korridor" heißt.
//
// Spiegel von `project`, `resample` und `SegmentGrid` in
// `tool/trail_match.py`. Was hier rechnet, entscheidet nichts über
// Verschmelzen — das tut der Server. Es sagt nur, was der Nutzer ohnehin
// auf der Karte sieht: ob zwei Linien aufeinanderliegen.
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

const _earthRadiusM = 6371000.0;

/// Die Schwellen des Abgleichs, wie `contribute_recording` und
/// `tool/trail_match.py` sie tragen (`DEFAULT_D`, `DEFAULT_COV`, `STEP`):
/// Korridor, Deckungsanteil, Abtastschritt. Gemessen an 584 Tracks
/// (`docs/trail-abgleich-messung.md`). Ändern sich die Zahlen dort, ändern
/// sie sich hier im selben PR — das Blatt soll nichts als „wieder
/// gefahren" zeigen, was der Server dann als neuen Trail anlegt.
const kMatchCorridorM = 15.0;
const kMatchCoverage = 0.8;
const kMatchSampleStepM = 5.0;

/// Eben um eine Breite — auf den Metern eines Trails genau genug, wie im
/// Werkzeug (`project`).
class FlatProjection {
  FlatProjection(double lat0) : _k = math.cos(lat0 * math.pi / 180);

  /// Um die mittlere Breite von [points].
  factory FlatProjection.around(Iterable<LatLng> points) {
    var sum = 0.0;
    var n = 0;
    for (final p in points) {
      sum += p.latitude;
      n++;
    }
    return FlatProjection(n == 0 ? 0 : sum / n);
  }

  final double _k;

  math.Point<double> xy(LatLng p) => math.Point(
    p.longitude * math.pi / 180 * _earthRadiusM * _k,
    p.latitude * math.pi / 180 * _earthRadiusM,
  );

  List<math.Point<double>> line(Iterable<LatLng> points) => [
    for (final p in points) xy(p),
  ];

  /// Die Umkehrung von [xy] — für Proben entlang einer Linie, die eine
  /// Höhe brauchen (`height_tiles.dart`), wie `climb_along` im Werkzeug.
  LatLng latLng(math.Point<double> p) => LatLng(
    p.y / _earthRadiusM * 180 / math.pi,
    p.x / (_earthRadiusM * _k) * 180 / math.pi,
  );
}

/// Ein Rahmen in Grad, für den groben Vorfilter vor jeder Rechnung.
class LatBox {
  const LatBox(this.s, this.w, this.n, this.e);
  final double s, w, n, e;

  static LatBox of(Iterable<LatLng> pts) {
    var s = 90.0, w = 180.0, n = -90.0, e = -180.0;
    for (final p in pts) {
      s = math.min(s, p.latitude);
      n = math.max(n, p.latitude);
      w = math.min(w, p.longitude);
      e = math.max(e, p.longitude);
    }
    return LatBox(s, w, n, e);
  }

  /// Liegt [o] ganz in diesem Rahmen?
  bool contains(LatBox o) => o.s >= s && o.n <= n && o.w >= w && o.e <= e;

  /// Kommen sich die Rahmen auf [marginM] nahe?
  bool near(LatBox o, double marginM) {
    final dLat = marginM / 111320.0;
    final dLon = marginM / (111320.0 * math.cos((s + n) / 2 * math.pi / 180));
    return !(n + dLat < o.s ||
        o.n + dLat < s ||
        e + dLon < o.w ||
        o.e + dLon < w);
  }
}

/// Punkte alle [step] Meter entlang der Linie, erster und letzter
/// eingeschlossen (`resample` im Werkzeug): Die Stützpunkte allein
/// verfehlten die Linie zwischen ihnen.
List<math.Point<double>> resampleXy(List<math.Point<double>> xy, double step) {
  if (xy.length < 2) return [...xy];
  final out = [xy.first];
  var carry = 0.0;
  for (var i = 1; i < xy.length; i++) {
    final a = xy[i - 1], b = xy[i];
    final seg = a.distanceTo(b);
    if (seg == 0) continue;
    var pos = step - carry;
    while (pos <= seg) {
      final t = pos / seg;
      out.add(math.Point(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y)));
      pos += step;
    }
    carry = seg - (pos - step);
  }
  if (out.last != xy.last) out.add(xy.last);
  return out;
}

typedef LineSegment = (math.Point<double>, math.Point<double>);

/// Gitter über die Strecken einer oder mehrerer Linien, für „liegt ein
/// Punkt im Korridor?" ohne jede Strecke anzufassen.
class SegmentGrid {
  SegmentGrid(List<List<math.Point<double>>> lines, this.cell) {
    for (final l in lines) {
      for (var i = 1; i < l.length; i++) {
        final a = l[i - 1], b = l[i];
        final seg = (a, b);
        for (
          var cx = (math.min(a.x, b.x) / cell).floor();
          cx <= (math.max(a.x, b.x) / cell).floor();
          cx++
        ) {
          for (
            var cy = (math.min(a.y, b.y) / cell).floor();
            cy <= (math.max(a.y, b.y) / cell).floor();
            cy++
          ) {
            (_cells[(cx, cy)] ??= []).add(seg);
          }
        }
      }
    }
  }

  final double cell;
  final _cells = <(int, int), List<LineSegment>>{};

  bool get isEmpty => _cells.isEmpty;

  bool within(math.Point<double> p, double d) {
    final cx = (p.x / cell).floor(), cy = (p.y / cell).floor();
    final reach = (d / cell).ceil();
    for (var dx = -reach; dx <= reach; dx++) {
      for (var dy = -reach; dy <= reach; dy++) {
        for (final (a, b)
            in _cells[(cx + dx, cy + dy)] ?? const <LineSegment>[]) {
          if (pointSegmentDistance(p, a, b) <= d) return true;
        }
      }
    }
    return false;
  }
}

/// Anteil der [samples], die näher als [d] an [grid] liegen.
double coverageWithin(
  List<math.Point<double>> samples,
  SegmentGrid grid,
  double d,
) {
  if (samples.isEmpty) return 0;
  var inside = 0;
  for (final p in samples) {
    if (grid.within(p, d)) inside++;
  }
  return inside / samples.length;
}

double pointSegmentDistance(
  math.Point<double> p,
  math.Point<double> a,
  math.Point<double> b,
) {
  final dx = b.x - a.x, dy = b.y - a.y;
  final len2 = dx * dx + dy * dy;
  if (len2 == 0) return p.distanceTo(a);
  final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / len2).clamp(0.0, 1.0);
  return p.distanceTo(math.Point(a.x + t * dx, a.y + t * dy));
}

/// Kürzester Abstand von [p] zur Linie [line] in Metern, null ohne Linie.
double? distanceToLineM(LatLng p, List<LatLng> line) {
  if (line.isEmpty) return null;
  final proj = FlatProjection(p.latitude);
  final q = proj.xy(p);
  final xy = proj.line(line);
  if (xy.length == 1) return q.distanceTo(xy.first);
  var best = double.infinity;
  for (var i = 1; i < xy.length; i++) {
    best = math.min(best, pointSegmentDistance(q, xy[i - 1], xy[i]));
  }
  return best;
}
