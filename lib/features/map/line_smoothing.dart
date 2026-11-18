// Glättung der Trail-Linien für die ANZEIGE (Betreiber, 2026-09-29:
// „smoother darstellen" — „aber nicht zu rechenintensiv"). Die
// gespeicherte Linie ist vereinfacht (Douglas-Peucker, `simplify`) und
// damit eckig — auf der Karte sah jede Kurve wie ein Knick aus. Chaikin
// schneidet die Ecken ab, bleibt dabei innerhalb der Hülle der Punkte und
// hält Anfang und Ende fest.
//
// NUR für das Bild: Abgleich, Länge, Höhen, Deckung und Zerlegung
// rechnen weiter mit den Originalpunkten. Die Trefferprüfung nimmt die
// geglättete Linie — getippt wird auf das, was man sieht.
//
// Was es kostet, ist gemessen (200 Trails à 2 km, 8 709 gespeicherte
// Punkte): Das Glätten selbst sind wenige Millisekunden, einmal je Laden.
// Teuer ist die ÜBERTRAGUNG an MapLibre (GeoJSON-Text) — deshalb
// schneidet die Glättung nur echte Ecken ([kSmoothMinTurnDeg]), statt
// jede Gerade zu verdoppeln, und die Engine überträgt eine unveränderte
// Linie gar nicht erst neu (`MapLibreLineCache`).
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Durchgänge: Bei zwei sah eine enge Kehre noch eckig aus (im Bild
/// nachgesehen, 2026-09-29), ab vier ändert sich nichts Sichtbares mehr.
const kLineSmoothingPasses = 3;

/// Nur Ecken, die mindestens so stark knicken, werden abgeschnitten — eine
/// fast gerade Stelle sieht man nicht, ihre zusätzlichen Punkte kosten
/// trotzdem Übertragung.
const kSmoothMinTurnDeg = 12.0;

/// Kürzere Abschnitte werden nicht weiter geteilt: darunter entstehen nur
/// Punkte, die auf keinem Bildschirm zu sehen sind.
const kSmoothMinSegmentM = 2.0;

List<LatLng> chaikinSmooth(
  List<LatLng> points, {
  int passes = kLineSmoothingPasses,
}) {
  var pts = points;
  for (var n = 0; n < passes && pts.length >= 3; n++) {
    final kx = math.cos(pts.first.latitude * math.pi / 180) * 111320;
    const ky = 110540.0;
    double dx(LatLng a, LatLng b) => (b.longitude - a.longitude) * kx;
    double dy(LatLng a, LatLng b) => (b.latitude - a.latitude) * ky;
    LatLng lerp(LatLng a, LatLng b, double t) => LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );

    final out = <LatLng>[pts.first];
    var changed = false;
    for (var i = 1; i < pts.length - 1; i++) {
      final p = pts[i - 1], v = pts[i], q = pts[i + 1];
      final ax = dx(p, v), ay = dy(p, v), bx = dx(v, q), by = dy(v, q);
      final la = math.sqrt(ax * ax + ay * ay),
          lb = math.sqrt(bx * bx + by * by);
      final turn = (la == 0 || lb == 0)
          ? 0.0
          : math.acos(((ax * bx + ay * by) / (la * lb)).clamp(-1.0, 1.0)) *
                180 /
                math.pi;
      if (turn < kSmoothMinTurnDeg ||
          la < kSmoothMinSegmentM ||
          lb < kSmoothMinSegmentM) {
        out.add(v);
        continue;
      }
      // Die Ecke v wird durch zwei Punkte je ein Viertel auf den
      // Nachbarabschnitten ersetzt — Chaikin, je Ecke gedacht.
      out
        ..add(lerp(v, p, 0.25))
        ..add(lerp(v, q, 0.25));
      changed = true;
    }
    out.add(pts.last);
    pts = out;
    if (!changed) break;
  }
  return pts;
}
