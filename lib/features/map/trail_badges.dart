// Das Schild am Trailanfang auf der Karte (Design 4c, Schritt 6b): Form,
// Grad und die angezeigten Merkmale, in der Farbe der Linie — erst ab
// Zoom 13 (Entwurf), darunter stünden die Schilder übereinander. Pur bis
// auf das Widget; ein Tipp auf das Schild öffnet den Trail wie ein Tipp
// auf die Linie. Seit 0.66.0 daneben die Startmarke (#96; die Endmarke
// ist seit 0.74.2 weg, #179).
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../../models/trail.dart';
import '../coach/coach.dart';
import '../help/map_tour.dart' show MapCoach;
import '../trails/grade_shield.dart';
import 'map_view/map_view.dart';
import 'trail_end_marks.dart';

/// Ab dieser (gerechneten) Zoomstufe stehen die Schilder auf der Karte —
/// seit 0.74.2 eine Stufe näher als im Entwurf (#184, Feldbericht: bei 13
/// standen sie zu früh und deckten die Karte zu). Dieselbe Stufe wie die
/// Namen an der Linie (`kLineLabelMinZoom`).
const kTrailBadgeMinZoom = 14.0;

/// Die Peilung am Anfang in Grad (0 = Nord, im Uhrzeigersinn), gemessen
/// zu einem Punkt ~30 m weiter, damit ein Zacken am Anfang die Richtung
/// nicht umwirft; `null` ohne zweiten Punkt. Die Startmarke dreht ihren
/// Pfeil darauf, das Schild wählt daran seine Seite.
double? trailStartBearing(Trail t) {
  final pts = t.directedPoints;
  if (pts.length < 2) return null;
  const d = Distance();
  final start = pts.first;
  var probe = pts[1];
  for (final p in pts.skip(1)) {
    probe = p;
    if (d.as(LengthUnit.Meter, start, p) >= 30) break;
  }
  return d.bearing(start, probe);
}

/// Führt der Trail vom Anfang nach Norden (auf der Karte nach oben)? Dann
/// steht das Schild UNTER dem Anfang, sonst darüber — es soll neben der
/// Linie stehen, nicht auf ihr.
bool trailHeadsNorth(Trail t) {
  final bearing = trailStartBearing(t);
  return bearing != null && bearing.abs() < 90;
}

/// Anfang und Richtung (#96): je Trail eine Startmarke mit Pfeil in der
/// Farbe der Linie, ab derselben Zoomstufe wie die Schilder — darunter
/// lägen sie übereinander (und MapLibre setzt jeden Widget-Marker in
/// jedem Bild neu). Nicht antippbar; wartende Trails haben keine (ihre
/// Linie ist gestrichelt und trägt die Uhr). Kein Quadrat am Ende mehr
/// (#179).
///
/// Die Startmarke von [coachTrailId] trägt den Anker `MapCoach.trailStart`
/// für die Vorführung.
List<MapViewMarker> trailEndMarkers(
  Iterable<Trail> trails,
  MapViewCamera? camera, {
  String? coachTrailId,
}) {
  if (camera == null || camera.zoom < kTrailBadgeMinZoom) return const [];
  final out = <MapViewMarker>[];
  for (final t in trails) {
    if (t.pending || t.points.length < 2) continue;
    final dot = TrailStartDot(
      color: trailColorOf(t, AppColors.mapGrades),
      bearingDeg: trailStartBearing(t) ?? 0,
    );
    out.add(
      MapViewMarker(
        key: ValueKey('trail-start-${t.id}'),
        point: t.start,
        width: kTrailMarkSize,
        height: kTrailMarkSize,
        child: t.id == coachTrailId
            ? CoachAnchor(id: MapCoach.trailStart, child: dot)
            : dot,
      ),
    );
  }
  return out;
}

const _fontSize = 11.0;

/// Breite des Markerrahmens — die Fassade braucht sie vorab. Großzügig
/// geschätzt; das Schild steht darin zentriert, ein Rest bleibt leer.
double _badgeWidth(Trail t, bool uphill, List<TrailTrait> traits) {
  var w = _fontSize * 1.1 + 2; // Rand links und rechts
  if (uphill || t.grade != null) {
    w += _fontSize * (t.grade == 4 || t.grade == 5 ? 2.2 : 1.0);
  }
  if (t.grade != null) w += _fontSize * (0.35 + 1.4);
  w += traits.length * _fontSize * 1.5;
  return w + 8;
}

/// Die Schilder für die gezeigten Trails — leer unter [kTrailBadgeMinZoom]
/// und für Trails ohne Grad und ohne Merkmale. Wartende (Ausgangskorb)
/// bekommen keins: Sie haben noch keinen Beitrag.
///
/// Das Schild von [coachTrailId] trägt den Anker der Karten-Tour (#132,
/// `MapCoach.trailBadge`) — die Tour zeigt auf GENAU das Schild, dessen
/// Blatt sie danach öffnet.
List<MapViewMarker> trailBadgeMarkers(
  Iterable<Trail> trails,
  MapViewCamera? camera, {
  String? coachTrailId,
}) {
  if (camera == null || camera.zoom < kTrailBadgeMinZoom) return const [];
  return [
    for (final t in trails)
      if (hasTrailBadge(t)) _marker(t, anchored: t.id == coachTrailId),
  ];
}

/// Bekommt [t] ein Schild? Nicht wartend, mit Linie, mit Grad oder
/// Merkmalen — dieselbe Regel für die Marker und für die Tour.
bool hasTrailBadge(Trail t) =>
    !t.pending &&
    t.points.isNotEmpty &&
    (t.grade != null || t.topTraits.isNotEmpty);

MapViewMarker _marker(Trail t, {bool anchored = false}) {
  final uphill = isUphill(t);
  final traits = [
    for (final x in t.topTraits)
      if (!(uphill && x == TrailTrait.uphill)) x,
  ];
  final shield = GradeShield(
    t.grade,
    fontSize: _fontSize,
    uphill: uphill,
    traits: traits,
    palette: AppColors.mapGrades,
  );
  return MapViewMarker(
    key: ValueKey('trail-badge-${t.id}'),
    point: t.start,
    width: _badgeWidth(t, uphill, traits),
    height: _fontSize * 2.2,
    // Das Schild steht neben dem Anfang auf der Seite, von der die Linie
    // WEGführt: `topCenter` = darüber (der Punkt an der Unterkante),
    // `bottomCenter` = darunter. So bleibt der Anfang der Linie frei.
    alignment: trailHeadsNorth(t)
        ? Alignment.bottomCenter
        : Alignment.topCenter,
    hitValue: t,
    child: Center(
      child: anchored
          ? CoachAnchor(id: MapCoach.trailBadge, child: shield)
          : shield,
    ),
  );
}
