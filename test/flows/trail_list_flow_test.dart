// Suche, Filter und Sortierung im Reiter „Trails" (#66): fehlertolerant
// wie in PilzBuddy, und die Liste sagt, wenn sie rät.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/trails/trail_providers.dart';
import 'package:trailbuddy/features/trails/trails_screen.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    final bob = backend.addUser(username: 'bob');
    backend.addFriendship(anna.id, bob.id);
    backend.signInAs(anna.id);
    trails = FakeTrailRepository(
        myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    trails.usernames[bob.id] = 'bob';
    trails.seedTrail(anna.id, name: 'Roßkopf Süd', grade: 1);
    trails.seedTrail(bob.id, name: 'Hexentanz', lat: 48.1, grade: 4);
    trails.seedTrail(bob.id, name: 'Alter Weg', lat: 48.2);
  });

  Future<void> open(WidgetTester tester) async {
    await pumpApp(tester, backend, trails: trails);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('trail-search')), text);
    await settle(tester);
  }

  FilterChip chip(WidgetTester tester, String key) => tester.widget<FilterChip>(find.byKey(ValueKey(key)));

  String summary(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('trail-search-summary'))).textSpan!.toPlainText();

  testWidgets('Suche ohne Umlaut findet den Trail, ein Tippfehler wird als Vermutung gezeigt',
      (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('trail-search-summary')), findsNothing,
        reason: 'ohne Suche keine Zeile über der Liste');

    await type(tester, 'rosskopf sued');
    expect(find.text('Roßkopf Süd'), findsOneWidget);
    expect(find.text('Hexentanz'), findsNothing);
    expect(summary(tester), 'Ein Trail gefunden.');

    await type(tester, 'bob');
    expect(find.text('Hexentanz'), findsOneWidget, reason: 'gesucht wird auch nach dem Buddy');
    expect(find.text('Roßkopf Süd'), findsNothing);

    await type(tester, 'Hexntanz');
    expect(find.text('Hexentanz'), findsOneWidget);
    expect(summary(tester), 'Kein Trail heißt so. Meintest du …?');

    await tester.tap(find.byTooltip('Suche leeren'));
    await settle(tester);
    expect(find.text('Alter Weg'), findsOneWidget);
    expect(find.text('Roßkopf Süd'), findsOneWidget);
  });

  testWidgets('S-Grad-Bereich blendet Ungeschätztes aus und sagt es; Meine/Von Buddys', (tester) async {
    await open(tester);
    expect(chip(tester, 'trail-filter-grade').label, isA<Text>()
        .having((t) => t.data, 'Text', 'S-Grad'));
    await setGradeRange(tester, max: 2);
    expect(find.text('Roßkopf Süd'), findsOneWidget);
    expect(find.text('Hexentanz'), findsNothing, reason: 'S4');
    expect(find.text('Alter Weg'), findsNothing, reason: 'ohne Einschätzung');
    expect(summary(tester), 'Ein Trail gefunden. Ein Trail ohne Einschätzung ist nicht dabei.');
    expect((chip(tester, 'trail-filter-grade').label as Text).data, 'bis S2');

    // Der Bereich ist einstellbar (#222), nicht nur „bis S2".
    await setGradeRange(tester, min: 3, max: 5);
    expect(find.text('Roßkopf Süd'), findsNothing, reason: 'S1');
    expect(find.text('Hexentanz'), findsOneWidget);
    expect((chip(tester, 'trail-filter-grade').label as Text).data, 'ab S3');

    await setGradeRange(tester);
    expect(chip(tester, 'trail-filter-grade').selected, isFalse);
    expect(find.text('Alter Weg'), findsOneWidget, reason: 'S0–S5 lässt Ungeschätzte durch');
    await tester.tap(find.text('Von Buddys').first);
    await settle(tester);
    expect(find.text('Roßkopf Süd'), findsNothing);
    expect(find.text('Hexentanz'), findsOneWidget);
    expect(find.text('Alter Weg'), findsOneWidget);
  });

  testWidgets('„Auf der Karte" (#222): nur, was im Ausschnitt liegt — die Karte meldet ihn',
      (tester) async {
    await open(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(TrailsScreen)));
    final camera = tester.state<FakeMapViewState>(find.byType(FakeMapView, skipOffstage: false)).camera;
    expect(container.read(mapVisibleBoundsProvider), isNotNull,
        reason: 'die Karte schreibt ihren Ausschnitt beim Stillstand');
    expect(container.read(mapVisibleBoundsProvider)!.north, camera.bounds.north);

    // Ein Ausschnitt um den Roßkopf (48.0) — Hexentanz (48.1) und Alter
    // Weg (48.2) liegen nördlich davon.
    container.read(mapVisibleBoundsProvider.notifier).state =
        const MapViewBounds(west: 8.9, east: 9.1, south: 47.95, north: 48.05);
    await tester.tap(find.byKey(const ValueKey('trail-filter-on-map')));
    await settle(tester);
    expect(find.text('Roßkopf Süd'), findsOneWidget);
    expect(find.text('Hexentanz'), findsNothing);
    expect(find.text('Alter Weg'), findsNothing);
    expect(summary(tester), 'Ein Trail gefunden.');
    expect(container.read(trailListFilterProvider).isActive, isFalse,
        reason: 'gilt nur für die Liste — die Karte meldet keinen Filter');

    // Die Karte bewegt sich, die Liste folgt.
    container.read(mapVisibleBoundsProvider.notifier).state =
        const MapViewBounds(west: 8.9, east: 9.1, south: 48.05, north: 48.15);
    await settle(tester);
    expect(find.text('Roßkopf Süd'), findsNothing);
    expect(find.text('Hexentanz'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('trail-filter-on-map')));
    await settle(tester);
    expect(find.text('Roßkopf Süd'), findsOneWidget);
    expect(find.byKey(const ValueKey('trail-search-summary')), findsNothing);
  });

  testWidgets('sortieren nach Name', (tester) async {
    // Telefonhöhe: Seit die Zeilen Karten sind (0.38.0), baut die faule
    // Liste auf der 800×600-Vorgabe die dritte nicht mehr. Etwas höher als
    // ein Telefon, seit „Auf der Karte" dazukam (#222): Die Testschrift
    // ist breiter als Barlow, jeder Chip steht dort in einer eigenen Zeile.
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('trail-sort')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('trail-sort-name')));
    await settle(tester);
    final alter = tester.getTopLeft(find.text('Alter Weg')).dy;
    final hexe = tester.getTopLeft(find.text('Hexentanz')).dy;
    expect(alter, lessThan(hexe));
    expect(find.byTooltip('Sortieren: Name'), findsOneWidget);
  });
}
