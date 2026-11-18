// Wo ein Linienname auf der flutter_map-Engine steht: EINMAL, in der Mitte
// der Linie (nach Länge), gedreht wie das Stück dort — und nie auf dem
// Kopf. MapLibre setzt Namen selbst entlang der Linie (`symbol-placement:
// line`); flutter_map kann keinen Text auf einem Pfad, deshalb dieser
// gedrehte Marker wie in PilzBuddy (Höhenlinien). Pur, damit ein Test ohne
// Karte prüfen kann, wo und wie schräg der Name steht.
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Punkt und Drehwinkel (Bogenmaß, im Uhrzeigersinn auf dem Bildschirm)
/// für den Namen einer Linie; null für weniger als zwei Punkte.
({LatLng point, double angle})? lineLabelAnchor(List<LatLng> points) {
  if (points.length < 2) return null;
  // In Web-Mercator rechnen: Dort stimmt der Winkel mit dem Bildschirm
  // überein (y wächst nach unten), in Grad wäre er in hohen Breiten schief.
  math.Point<double> project(LatLng p) {
    final x = p.longitude / 360 + 0.5;
    final s = math.sin(p.latitude * math.pi / 180);
    final y = 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi);
    return math.Point(x, y);
  }

  final proj = [for (final p in points) project(p)];
  final seg = <double>[];
  var total = 0.0;
  for (var i = 1; i < proj.length; i++) {
    final d = proj[i].distanceTo(proj[i - 1]);
    seg.add(d);
    total += d;
  }
  if (total == 0) return null;
  var rest = total / 2;
  var i = 0;
  while (i < seg.length - 1 && rest > seg[i]) {
    rest -= seg[i];
    i++;
  }
  final t = seg[i] == 0 ? 0.0 : (rest / seg[i]).clamp(0.0, 1.0);
  final a = points[i], b = points[i + 1];
  final point = LatLng(
    a.latitude + (b.latitude - a.latitude) * t,
    a.longitude + (b.longitude - a.longitude) * t,
  );
  var angle = math.atan2(proj[i + 1].y - proj[i].y, proj[i + 1].x - proj[i].x);
  // Nie auf dem Kopf: Zeigt das Stück nach links, liest man es andersherum.
  if (angle > math.pi / 2) angle -= math.pi;
  if (angle < -math.pi / 2) angle += math.pi;
  return (point: point, angle: angle);
}
