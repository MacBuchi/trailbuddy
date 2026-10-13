// Die Route auf der Fake-Karte lesen (#295): Seit dem Band ist sie keine
// einzelne Linie mehr, sondern Zeichnungen in Bandbreite, Pfeil-Linien
// und unsichtbare Tippziele (`route_band.dart`).
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/routing/route_band.dart';

import 'fake_map_view.dart';

/// Alle Zeichnungen des Bands; `pass == 1` sind die doppelten Stücke.
/// Durchsichtig: Die Auswahl im Planer ist ebenso breit und Lime, aber
/// deckend.
Iterable<MapViewPolyline> routeBand(WidgetTester tester) =>
    fakeMapLayers(tester).polylines.where((l) => l.width == kRouteBandWidth && l.opacity < 1);

/// Die ganze Route in Fahrtrichtung — die Pfeil-Linien decken sie lückenlos.
List<LatLng> routeWhole(WidgetTester tester) => [
      for (final l in fakeMapLayers(tester).polylines)
        if (l.arrows != null && l.color == AppColors.routeArrow) ...l.points,
    ];

/// Die Tippziele der Abschnitte (Zwischenpunkte, #234).
Iterable<MapViewPolyline> routeHits(WidgetTester tester) =>
    fakeMapLayers(tester).polylines.where((l) => l.width == 0 && l.hitValue != null);

/// Die gestrichelten Mittellinien über Wanderweg.
Iterable<MapViewPolyline> routeHiking(WidgetTester tester) =>
    fakeMapLayers(tester).polylines.where((l) => l.color == AppColors.routeEdge && l.dash != null);
