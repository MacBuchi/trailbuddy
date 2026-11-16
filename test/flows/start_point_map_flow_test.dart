// Gemerkte Startpunkte auf der Karte (#543, Schritt 2): langer Druck und
// Ort-Blatt merken einen Punkt, der Pin steht sofort; das Blatt am
// eigenen Pin schaltet, benennt um und löscht (mit Rückgängig); am Pin
// eines Buddys steht, von wem er ist, und nur „Als Startpunkt merken";
// ein eigener Punkt verdeckt den fremden am selben Platz; die Ebene ist
// abschaltbar. Alle Koordinaten sind erfunden (A7).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/map/poi.dart';
import 'package:trailbuddy/features/map/start_point_layer.dart';
import 'package:trailbuddy/models/start_point.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/fake_pois.dart';
import '../fakes/fake_settings.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late String annaId;
  late String benId;
  late FakeTrailRepository trails;

  const here = LatLng(47.5, 10.5);

  setUp(() {
    backend = FakeBackend();
    annaId = backend.addUser(username: 'anna').id;
    benId = backend.addUser(username: 'ben').id;
    backend.addFriendship(annaId, benId);
    backend.signInAs(annaId);
    trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    trails.usernames[benId] = 'ben';
    trails.seedTrail(annaId, name: 'Roots');
  });

  StartPoint point(String owner, String clientId, String name, LatLng at,
          {TrailVisibility visibility = TrailVisibility.buddies}) =>
      StartPoint(
          clientId: clientId,
          userId: owner,
          name: name,
          lat: at.latitude,
          lon: at.longitude,
          visibility: visibility,
          createdAt: DateTime.utc(2026, 11, 16));

  Future<void> start(WidgetTester tester, {FakeSettings? settings}) async {
    await pumpApp(tester, backend, trails: trails, settings: settings);
    await settle(tester, frames: 20);
    fakeMap(tester).move(here, 15);
    await settle(tester, frames: 20);
  }

  List<MapViewMarker> pins(WidgetTester tester) => [
        for (final m in fakeMapLayers(tester).markers)
          if (m.hitValue is StartPoint) m,
      ];

  testWidgets('langer Druck → „Als Startpunkt merken": Pin steht, Blatt schaltet, benennt um, löscht',
      (tester) async {
    await start(tester);
    expect(pins(tester), isEmpty);

    await longPressMapAt(tester, here);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('map-menu-remember')));
    await settle(tester);
    // Ohne Namen lässt sich nichts merken.
    final save = find.byKey(const ValueKey('start-point-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('start-point-name')), 'Parkplatz Talboden');
    await settle(tester);
    // Auf diesem Weg ab Werk „Buddys" (Konzept 4).
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('start-point-shared'))).value, isTrue);
    await tester.tap(save);
    await settle(tester, frames: 12);

    expect(trails.startPoints.single.name, 'Parkplatz Talboden');
    expect(trails.startPoints.single.visibility, TrailVisibility.buddies);
    expect(find.text('Startpunkt gemerkt.'), findsOneWidget);
    expect(pins(tester), hasLength(1));

    // Das Blatt am eigenen Pin.
    await tapMapAt(tester, pins(tester).single.point);
    await settle(tester);
    expect(find.byKey(const ValueKey('start-point-title')), findsOneWidget);
    expect(find.text('Deine Buddys sehen diesen Startpunkt.'), findsWidgets);
    expect(find.byKey(const ValueKey('start-point-remember-copy')), findsNothing);

    // Privat schalten — das Blatt zeigt es sofort.
    await tester.ensureVisible(find.byKey(const ValueKey('start-point-shared-switch')));
    await tester.tap(find.byKey(const ValueKey('start-point-shared-switch')));
    await settle(tester, frames: 12);
    expect(trails.startPoints.single.visibility, TrailVisibility.private);
    expect(find.text('Privat — nur du siehst ihn.'), findsWidgets);

    // Umbenennen.
    await tester.ensureVisible(find.byKey(const ValueKey('start-point-rename')));
    await tester.tap(find.byKey(const ValueKey('start-point-rename')));
    await settle(tester);
    expect(find.byKey(const ValueKey('start-point-shared')), findsNothing, reason: 'Umbenennen ohne Schalter');
    await tester.enterText(find.byKey(const ValueKey('start-point-name')), 'Wanderparkplatz');
    await tester.tap(find.byKey(const ValueKey('start-point-save')));
    await settle(tester, frames: 12);
    expect(trails.startPoints.single.name, 'Wanderparkplatz');
    expect(trails.startPoints.single.visibility, TrailVisibility.private, reason: 'Umbenennen lässt die Sichtbarkeit');

    // Löschen — und Rückgängig merkt ihn mit derselben client_id wieder.
    final clientId = trails.startPoints.single.clientId;
    await tester.ensureVisible(find.byKey(const ValueKey('start-point-delete')));
    await tester.tap(find.byKey(const ValueKey('start-point-delete')));
    await settle(tester, frames: 12);
    expect(trails.startPoints, isEmpty);
    expect(pins(tester), isEmpty);
    await tester.tap(find.text('Rückgängig'));
    await settle(tester, frames: 12);
    expect(trails.startPoints.single.clientId, clientId);
    expect(trails.startPoints.single.name, 'Wanderparkplatz');
    expect(pins(tester), hasLength(1));
  });

  testWidgets('Pin eines Buddys: „von ben", nur Start/Ziel/Navi und „Als Startpunkt merken"', (tester) async {
    trails.startPoints.add(point(benId, 'b1', 'Bens Parkplatz', here));
    // Privat: Anna sieht ihn nicht (RLS im Fake).
    trails.startPoints.add(point(benId, 'b2', 'Bens Garage', const LatLng(47.502, 10.502),
        visibility: TrailVisibility.private));
    await start(tester);
    expect(pins(tester), hasLength(1));

    await tapMapAt(tester, here);
    await settle(tester);
    expect(find.text('von ben'), findsOneWidget);
    expect(find.byKey(const ValueKey('start-point-as-start')), findsOneWidget);
    expect(find.byKey(const ValueKey('start-point-shared-switch')), findsNothing);
    expect(find.byKey(const ValueKey('start-point-delete')), findsNothing);

    // Übernehmen heißt: selbst neu merken, Name vorbelegt.
    await tester.ensureVisible(find.byKey(const ValueKey('start-point-remember-copy')));
    await tester.tap(find.byKey(const ValueKey('start-point-remember-copy')));
    await settle(tester);
    expect(find.widgetWithText(TextField, 'Bens Parkplatz'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('start-point-save')));
    await settle(tester, frames: 12);
    expect([for (final p in trails.startPoints) if (p.userId == annaId) p.name], ['Bens Parkplatz']);

    // Jetzt liegen eigener und fremder Punkt am selben Platz: Nur der
    // eigene steht (Konzept 9.3).
    final shown = pins(tester);
    expect(shown, hasLength(1));
    expect((shown.single.hitValue! as StartPoint).userId, annaId);
  });

  testWidgets('Ort-Blatt → „Als Startpunkt merken": Name und Lage des Ortes', (tester) async {
    const at = LatLng(47.501, 10.501);
    const spring = Poi(id: 'node/7', kind: PoiKind.drinkingWater, position: at, name: 'Hangbrunnen');
    await pumpApp(tester, backend, trails: trails, pois: FakePoiSource([spring]));
    await settle(tester, frames: 20);
    fakeMap(tester).move(at, 15);
    await settle(tester, frames: 40);
    await tapMapAt(tester, at);
    await settle(tester);
    final remember = find.byKey(const ValueKey('poi-remember-start'));
    await tester.ensureVisible(remember);
    await settle(tester, frames: 2);
    await tester.tap(remember);
    await settle(tester);
    expect(find.widgetWithText(TextField, 'Hangbrunnen'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('start-point-save')));
    await settle(tester, frames: 12);
    final saved = trails.startPoints.single;
    expect((saved.name, saved.lat, saved.lon, saved.userId), ('Hangbrunnen', at.latitude, at.longitude, annaId));
  });

  testWidgets('Ebene aus: keine Pins; wieder an: da', (tester) async {
    trails.startPoints.add(point(annaId, 'a1', 'Parkplatz Talboden', here));
    final settings = FakeSettings();
    await start(tester, settings: settings);
    expect(pins(tester), hasLength(1));

    await tester.tap(find.byTooltip('Kartenebenen'));
    await settle(tester);
    final toggle = find.byKey(const ValueKey('start-point-layer-switch'));
    await tester.ensureVisible(toggle);
    await settle(tester);
    await tester.tap(toggle);
    await settle(tester);
    expect(settings.startPointLayerEnabled, isFalse);
    expect(pins(tester), isEmpty);
    await tester.tap(toggle);
    await settle(tester);
    expect(pins(tester), hasLength(1));
  });

  testWidgets('weit draußen keine Pins', (tester) async {
    trails.startPoints.add(point(annaId, 'a1', 'Parkplatz Talboden', here));
    await start(tester);
    expect(pins(tester), hasLength(1));
    fakeMap(tester).move(here, kStartPointMinZoom - 1);
    await settle(tester, frames: 20);
    expect(pins(tester), isEmpty);
  });

  group('shownStartPoints', () {
    test('ein eigener verdeckt fremde innerhalb von 30 m, zwei fremde bleiben', () {
      final mine = point(annaId, 'a', 'Meiner', here);
      final near = point(benId, 'b', 'Nah', const LatLng(47.5002, 10.5)); // ~22 m
      final far = point(benId, 'c', 'Weiter', const LatLng(47.5004, 10.5)); // ~44 m
      expect([for (final p in shownStartPoints([mine, near, far], annaId)) p.name], ['Meiner', 'Weiter']);
      expect([for (final p in shownStartPoints([near, far], annaId)) p.name], ['Nah', 'Weiter']);
    });
  });
}
