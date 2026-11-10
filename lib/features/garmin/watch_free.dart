// Die freie Fahrt (Konzept 2, #484): die Uhr hat keine Linie und rollt
// einfach durch die Gegend. Sie meldet ihren Stand (`g`), das Handy sucht
// den Trail in Reichweite, der am nächsten liegt, und schickt ihn als
// Linie — dieselbe Maschinerie wie die Navigation (Protokoll 2, Abschnitte,
// Höhen). Liegt nichts in Reichweite, bleibt die Uhr bei ihrer eigenen Spur.
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart' as geo;
import '../../models/trail.dart';
import '../routing/nav_sections.dart';

/// Näher als das liegt kein Trail für die Uhr in Reichweite.
const kWatchFreeRadiusM = 800.0;

/// Weniger als das ist kein Trail, sondern ein Stummel: die Uhr bekäme eine
/// Linie, die nach zwei Kurven endet.
const kWatchFreeMinM = 250.0;

/// Länge einer Linie in Metern.
double lineLengthM(List<LatLng> line) {
  var m = 0.0;
  for (var i = 1; i < line.length; i++) {
    m += geo.distanceMeters(line[i - 1].latitude, line[i - 1].longitude, line[i].latitude, line[i].longitude);
  }
  return m;
}

typedef NearestLine = ({Trail trail, List<LatLng> points, double distanceM, double lengthM});

/// Der Trail, dessen Linie der Uhr am nächsten liegt — und die Linie so,
/// dass sie dort anfängt, wo die Uhr steht. null, wenn keiner in Reichweite
/// liegt oder keiner lang genug ist.
NearestLine? nearestTrailLine(
    List<Trail> trails, LatLng at, {double radiusM = kWatchFreeRadiusM}) {
  Trail? best;
  List<LatLng>? line;
  double bestD = double.infinity;
  for (final t in trails) {
    final pts = t.directedPoints;
    if (pts.length < 2) continue;
    int near = 0;
    double d = double.infinity;
    for (var i = 0; i < pts.length; i++) {
      final dd = geo.distanceMeters(at.latitude, at.longitude, pts[i].latitude, pts[i].longitude);
      if (dd < d) {
        d = dd;
        near = i;
      }
    }
    if (d > radiusM || d >= bestD) continue;
    // Weitergeht es in beide Richtungen; die längere ist die Linie.
    final forward = pts.sublist(near);
    final back = pts.sublist(0, near + 1).reversed.toList();
    final take = forward.length >= back.length ? forward : back;
    if (take.length < 2) continue;
    final length = lineLengthM(take);
    if (length < kWatchFreeMinM) continue;
    best = t;
    line = take;
    bestD = d;
  }
  if (best == null || line == null) return null;
  return (trail: best, points: line, distanceM: bestD, lengthM: lineLengthM(line));
}

/// Die Abschnitte dazu: der ganze Rest der Linie ist genau dieser Trail.
NavSections freeSections(Trail trail, List<LatLng> line) => NavSections([
      NavTrailSection(
        startM: 0,
        endM: lineLengthM(line),
        trailId: trail.id,
        name: trail.name ?? '',
      ),
    ]);
