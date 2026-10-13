// Das Schild am Trailanfang (Design 4c, Schritt 6b): ab Zoom 14 (#184),
// am Anfang in Trail-Richtung, mit Grad und Merkmalen in der Farbe der
// Linie; ein Tipp öffnet den Trail. Dazu seit 0.66.0 die Startmarke (#96,
// Schritt 6c): dieselbe Zoomstufe, in Trail-Richtung, nicht antippbar,
// auch für Trails ohne Schild. Keine Endmarke mehr (#179).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/map/trail_badges.dart';
import 'package:trailbuddy/features/map/trail_end_marks.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';
import '../fakes/l10n_de.dart';

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late String hexentanz, rueckwaerts, nackt;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    hexentanz = trails.seedTrail(anna.id, name: 'Hexentanz', grade: 3, traits: {TrailTrait.rocky});
    // Gegen die Trail-Richtung aufgenommen: Anfang ist das Ende der Linie.
    rueckwaerts = trails.seedTrail(anna.id, name: 'Rückwärts', lat: 48.02, grade: 1, reversed: true);
    trails.seedTrail(anna.id, name: 'Auffahrt', lat: 48.04, traits: {TrailTrait.uphill});
    // Ohne Grad und ohne Merkmale: kein Schild.
    nackt = trails.seedTrail(anna.id, name: 'Nackt', lat: 48.06);
  });

  MapViewMarker? markerByKey(WidgetTester tester, String key) {
    for (final m in fakeMapLayers(tester).markers) {
      if (m.key == ValueKey(key)) return m;
    }
    return null;
  }

  MapViewMarker? badgeOf(WidgetTester tester, String name) {
    for (final m in fakeMapLayers(tester).markers) {
      if (m.hitValue is Trail && (m.hitValue as Trail).displayName(l10nDe) == name) return m;
    }
    return null;
  }

  testWidgets('erst ab Zoom 14, am Anfang in Trail-Richtung, nur mit etwas zu sagen', (tester) async {
    await pumpApp(tester, backend, trails: trails);
    await settle(tester, frames: 20);

    fakeMap(tester).move(const LatLng(48.03, 9.0), kTrailBadgeMinZoom - 1);
    await settle(tester);
    expect(badgeOf(tester, 'Hexentanz'), isNull, reason: 'darunter stünden die Schilder übereinander');
    expect(kTrailBadgeMinZoom, 14, reason: 'eine Stufe näher als der Entwurf (#184)');
    expect(kTrailBadgeMinZoom, kLineLabelMinZoom, reason: 'Schild und Name kommen zusammen');

    fakeMap(tester).move(const LatLng(48.03, 9.0), kTrailBadgeMinZoom);
    await settle(tester);
    expect(badgeOf(tester, 'Hexentanz')!.point, const LatLng(48.0, 9.0));
    expect(badgeOf(tester, 'Rückwärts')!.point, const LatLng(48.029, 9.0));
    // Neben der Linie, nicht auf ihr: Hexentanz führt nach Norden, das
    // Schild steht darunter; Rückwärts führt nach Süden, es steht darüber.
    expect(badgeOf(tester, 'Hexentanz')!.alignment, Alignment.bottomCenter);
    expect(badgeOf(tester, 'Rückwärts')!.alignment, Alignment.topCenter);
    expect(badgeOf(tester, 'Auffahrt'), isNotNull, reason: 'Uphill ohne Grad trägt den Pfeil');
    expect(badgeOf(tester, 'Nackt'), isNull);
    expect(findLabel('Schwierigkeit S3: verblockt, hohe Stufen, enge Kehren, Verblockt'), findsOneWidget);
    expect(findLabel('Uphill'), findsOneWidget);
  });

  testWidgets('Startmarke: ab Zoom 14, in Trail-Richtung, nicht antippbar — kein Ende mehr (#179)',
      (tester) async {
    await pumpApp(tester, backend, trails: trails);
    await settle(tester, frames: 20);

    fakeMap(tester).move(const LatLng(48.03, 9.0), kTrailBadgeMinZoom - 1);
    await settle(tester);
    expect(markerByKey(tester, 'trail-start-$hexentanz'), isNull, reason: 'weit draußen bleibt die Karte ruhig');

    fakeMap(tester).move(const LatLng(48.03, 9.0), kTrailBadgeMinZoom);
    await settle(tester);
    final start = markerByKey(tester, 'trail-start-$hexentanz')!;
    expect(start.point, const LatLng(48.0, 9.0));
    expect(start.hitValue, isNull, reason: 'ein Tipp dort trifft die Linie');
    expect(markerByKey(tester, 'trail-end-$hexentanz'), isNull, reason: 'das Quadrat am Ende ist weg (#179)');
    expect(start.alignment, Alignment.center);
    // Hexentanz führt nach Norden: der Pfeil zeigt nach oben.
    expect((start.child as TrailStartDot).bearingDeg, closeTo(0, 1));

    // Gegen die Richtung aufgenommen: Anfang und Ende sind vertauscht,
    // der Pfeil zeigt nach Süden.
    final rStart = markerByKey(tester, 'trail-start-$rueckwaerts')!;
    expect(rStart.point, const LatLng(48.029, 9.0));
    expect((rStart.child as TrailStartDot).bearingDeg.abs(), closeTo(180, 1));

    // Auch ohne Schild gibt es Anfang und Ende.
    expect(markerByKey(tester, 'trail-start-$nackt'), isNotNull);
    expect(find.byType(TrailStartDot), findsNWidgets(4));
    expect(findLabel('Trailanfang'), findsNWidgets(4));
  });

  testWidgets('ein Tipp auf das Schild wählt den Trail aus, ein Tipp auf die Schnellkarte öffnet ihn (#178)',
      (tester) async {
    await pumpApp(tester, backend, trails: trails);
    await settle(tester, frames: 20);
    fakeMap(tester).move(const LatLng(48.0, 9.0), 15);
    await settle(tester);
    final lines = fakeMapLayers(tester).polylines.length;

    await tester.tap(find.byKey(badgeOf(tester, 'Hexentanz')!.key!));
    await settle(tester);
    // Erst die Auswahl: Schnellkarte unten, der Trail leuchtet — noch kein Blatt.
    expect(find.byKey(const ValueKey('trail-quick-card')), findsOneWidget);
    expect(find.text('HEXENTANZ'), findsNothing);
    expect(fakeMapLayers(tester).polylines.length, lines + 1, reason: 'der Leuchtrand');
    // #195: deckendes Lime mit dunkler Kontur, breiter als Linie samt
    // weißem Saum, und darunter — sonst ginge es im Saum unter.
    final polys = fakeMapLayers(tester).polylines;
    final glow = polys.indexWhere((p) => p.color == AppColors.brand && p.hitValue == null);
    final line = polys.indexWhere((p) => p.hitValue is Trail && (p.hitValue as Trail).displayName(l10nDe) == 'Hexentanz');
    expect(glow, isNonNegative);
    expect(glow, lessThan(line), reason: 'das Leuchten liegt unter der Linie');
    double outer(MapViewPolyline p) => p.width + 2 * p.borderWidth;
    expect(polys[glow].width, greaterThanOrEqualTo(outer(polys[line]) + 8), reason: '4 px Lime je Seite');
    expect(polys[glow].borderWidth, greaterThan(0));
    expect(polys[glow].borderColor!.computeLuminance(), lessThan(0.05), reason: 'dunkle Kontur');
    expect(find.descendant(of: find.byKey(const ValueKey('trail-quick-card')), matching: find.text('Hexentanz')),
        findsOneWidget);

    // Ein Tipp daneben hebt die Auswahl auf.
    await tapMapAt(tester, const LatLng(48.5, 9.5));
    await settle(tester);
    expect(find.byKey(const ValueKey('trail-quick-card')), findsNothing);
    expect(fakeMapLayers(tester).polylines.length, lines);

    // Wieder auswählen, dann die Schnellkarte: das große Blatt.
    await tester.tap(find.byKey(badgeOf(tester, 'Hexentanz')!.key!));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('trail-quick-open')));
    await settle(tester);
    expect(find.text('HEXENTANZ'), findsOneWidget);
  });

  testWidgets('ein zweiter Tipp auf denselben Trail öffnet gleich das Blatt', (tester) async {
    await pumpApp(tester, backend, trails: trails);
    await settle(tester, frames: 20);
    fakeMap(tester).move(const LatLng(48.0, 9.0), 15);
    await settle(tester);
    await tester.tap(find.byKey(badgeOf(tester, 'Hexentanz')!.key!));
    await settle(tester);
    await tester.tap(find.byKey(badgeOf(tester, 'Hexentanz')!.key!));
    await settle(tester);
    expect(find.text('HEXENTANZ'), findsOneWidget);
  });
}
