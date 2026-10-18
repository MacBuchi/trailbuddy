// Die Trefferprüfung der Kartenfassade — pur und ohne Engine, geprüft in
// test/map/map_hit_test_test.dart.
//
// **Warum die Fassade das selbst tut:** flutter_map trifft Linien über
// `hitNotifier`, MapLibre kennt an seinen Style-Ebenen keine eigene
// Kennung. Zwei Engines, zwei Antworten auf „was habe ich angetippt" —
// oder EINE Rechnung in Dart, die beide füttern. Die Rechnung ist
// bewusst einfach: Web-Mercator ohne Drehung (die Karte dreht sich nicht,
// `InteractiveFlag.rotate` ist aus), Abstand in Bildpunkten.
import 'dart:math' as math;
import 'dart:ui';

import 'package:latlong2/latlong.dart';

import 'map_view.dart';

/// Wie nah ein Tipp an einer Linie liegen darf, in Bildpunkten — zur
/// halben Strichbreite dazu. Ein Finger ist kein Pixel.
const kMapTapSlopPx = 12.0;

/// Wie weit ein Tipp neben einem Marker liegen darf. Kleiner als bei
/// Linien: Ein Marker hat eine Fläche, eine Linie nicht.
const kMapMarkerSlopPx = 4.0;

/// Die Breite, an der Web-Mercator endet — jenseits davon läuft die
/// Projektion ins Unendliche.
const kMercatorMaxLat = 85.05112878;

double _mercY(double latDeg) {
  final lat = latDeg.clamp(-kMercatorMaxLat, kMercatorMaxLat) * math.pi / 180;
  return math.log(math.tan(math.pi / 4 + lat / 2));
}

/// Der Punkt auf der Kartenfläche, an dem [p] bei dieser Kamera liegt —
/// Web-Mercator, linear zwischen den Fensterkanten.
Offset projectToScreen(MapViewCamera camera, LatLng p) {
  final b = camera.bounds;
  final lonSpan = b.east - b.west;
  final yTop = _mercY(b.north);
  final ySpan = yTop - _mercY(b.south);
  final x = lonSpan == 0 ? 0.0 : (p.longitude - b.west) / lonSpan * camera.size.width;
  final y = ySpan == 0 ? 0.0 : (yTop - _mercY(p.latitude)) / ySpan * camera.size.height;
  return Offset(x, y);
}

/// Umkehrung von [projectToScreen]: die Stelle unter dem Punkt [at] der
/// Kartenfläche. Gebraucht beim Zeichnen eines Bereichs (Offline-Karten,
/// Stufe C) — der Strich entsteht in Bildpunkten über der Karte, die
/// Kacheln verlangen Grad. Dieselbe Rechnung wie die Trefferprüfung,
/// also auf beiden Engines dieselbe Antwort.
LatLng unprojectFromScreen(MapViewCamera camera, Offset at) {
  final b = camera.bounds;
  final w = camera.size.width, h = camera.size.height;
  final lon = w == 0 ? b.west : b.west + at.dx / w * (b.east - b.west);
  final yTop = _mercY(b.north);
  final y = h == 0 ? yTop : yTop - at.dy / h * (yTop - _mercY(b.south));
  final lat = (2 * math.atan(math.exp(y)) - math.pi / 2) * 180 / math.pi;
  return LatLng(lat, lon);
}

/// Die Kamera, die alle [points] mit [padding] Rand in eine Fläche der
/// Größe [size] bringt — Mitte in Web-Mercator (nicht das Mittel der
/// Breiten), Zoom in 256er-Stufen wie die Fassade, auf [minZoom]…[maxZoom]
/// begrenzt. Ein einzelner Punkt oder eine leere Fläche ergibt
/// [maxZoom] um den Punkt.
///
/// Gerechnet statt der Engine überlassen (#68): MapLibres `fitBounds`
/// läuft auf Android über `animateCamera`, und das wirft bei einer Dauer
/// von 0 ms („Null duration passed into animateCamera"). Mit dieser
/// Rechnung setzt die Engine die Kamera ohne Animation, in EINEM
/// Schritt samt Obergrenze — und der Fake der Tests rechnet dasselbe.
///
/// [bottomInset] ist die Höhe, die unten verdeckt ist (ein offenes Blatt
/// über der Karte): Die Punkte kommen dann in die Fläche DARÜBER, die
/// Mitte rückt um die halbe Höhe nach Süden. Ohne sie lag eine geplante
/// Runde unter dem Planer-Blatt (Feldbericht 0.73.0).
({LatLng center, double zoom}) cameraToFit(
  List<LatLng> points,
  Size size, {
  required double padding,
  required double maxZoom,
  double minZoom = 0,
  double bottomInset = 0,
}) {
  var s = 90.0, n = -90.0, w = 180.0, e = -180.0;
  for (final p in points) {
    s = math.min(s, p.latitude);
    n = math.max(n, p.latitude);
    w = math.min(w, p.longitude);
    e = math.max(e, p.longitude);
  }
  final yN = _mercY(n), yS = _mercY(s);
  final yMid = (yN + yS) / 2;
  final inset = bottomInset.clamp(0.0, math.max(0.0, size.height - 2 * padding - 1)).toDouble();
  final usableW = size.width - 2 * padding, usableH = size.height - 2 * padding - inset;
  var zoom = maxZoom;
  if (usableW > 0 && usableH > 0) {
    final lonSpan = e - w, ySpan = yN - yS;
    if (lonSpan > 0) {
      zoom = math.min(zoom, math.log(usableW * 360 / (256 * lonSpan)) / math.ln2);
    }
    if (ySpan > 0) {
      zoom = math.min(zoom, math.log(usableH * 2 * math.pi / (256 * ySpan)) / math.ln2);
    }
  }
  final z = zoom.clamp(minZoom, maxZoom).toDouble();
  // Die sichtbare Mitte liegt [inset]/2 Pixel über der Bildmitte — die
  // Kamera also um so viel südlicher (Mercator-y wächst nach Norden).
  final yCenter = yMid - (inset / 2) / (256 * math.pow(2, z) / (2 * math.pi));
  final center = LatLng((2 * math.atan(math.exp(yCenter)) - math.pi / 2) * 180 / math.pi, (w + e) / 2);
  return (center: center, zoom: z);
}

/// Abstand von [p] zur Strecke [a]–[b].
double distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// Die Fläche eines Markers auf dem Schirm — dieselbe Rechnung wie
/// flutter_maps `Marker.alignment`: `topCenter` hängt den Marker über den
/// Punkt, `center` mittig darauf.
Rect markerRect(MapViewCamera camera, MapViewMarker m) {
  final pt = projectToScreen(camera, m.point);
  final left = pt.dx - m.width + 0.5 * m.width * (m.alignment.x + 1);
  final top = pt.dy - m.height + 0.5 * m.height * (m.alignment.y + 1);
  return Rect.fromLTWH(left, top, m.width, m.height);
}

/// Was ein Tipp trifft: Linien zuerst (die oberste zuletzt gezeichnete
/// gewinnt), dann Marker (ebenso), sonst null. Ohne `hitValue` zählt
/// nichts — die Fahrt und der Positionspunkt sind Kulisse.
Object? resolveMapTap(MapViewLayers layers, MapTap tap) {
  final camera = tap.camera;
  final at = tap.screenPoint;
  for (final line in layers.polylines.reversed) {
    final value = line.hitValue;
    if (value == null || line.points.length < 2) continue;
    final slop = line.hitSlop + line.width / 2 + line.borderWidth;
    Offset prev = projectToScreen(camera, line.points.first);
    for (var i = 1; i < line.points.length; i++) {
      final next = projectToScreen(camera, line.points[i]);
      if (distanceToSegment(at, prev, next) <= slop) return value;
      prev = next;
    }
  }
  for (final marker in layers.markers.reversed) {
    final value = marker.hitValue;
    if (value == null) continue;
    if (markerRect(camera, marker).inflate(kMapMarkerSlopPx).contains(at)) {
      return value;
    }
  }
  return null;
}

/// Filtert Marker auf das Sichtfenster plus Rand — für die
/// MapLibre-Engine, deren `WidgetLayer` JEDEN übergebenen Marker in jedem
/// Frame auf dem UI-Isolate positioniert (PilzBuddy: der Grund, warum der
/// Spike nur −28 % Haupt-Thread-Last brachte). [margin] ist der Puffer je
/// Seite als Anteil der Fensterspanne: Ohne ihn ploppen Marker beim
/// Wischen am Rand auf. Die Reihenfolge bleibt, sie ist die Stapelung.
List<MapViewMarker> visibleMarkers(
  List<MapViewMarker> markers,
  MapViewBounds bounds, {
  double margin = 0.25,
}) {
  final lonPad = (bounds.east - bounds.west) * margin;
  final latPad = (bounds.north - bounds.south) * margin;
  final west = bounds.west - lonPad;
  final east = bounds.east + lonPad;
  final south = bounds.south - latPad;
  final north = bounds.north + latPad;
  return [
    for (final marker in markers)
      if (marker.point.longitude >= west &&
          marker.point.longitude <= east &&
          marker.point.latitude >= south &&
          marker.point.latitude <= north)
        marker,
  ];
}
