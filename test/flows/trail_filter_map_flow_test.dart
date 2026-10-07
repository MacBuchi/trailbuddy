// Der Trail-Filter gilt für Liste UND Karte (#66, seit 0.33.0): EIN
// Provider, hier gesetzt heißt dort gesetzt. Auf der Karte meldet er sich
// mit einer Zeile und lässt sich dort zurücksetzen; ein Sprung auf einen
// ausgeblendeten Trail (Push) setzt ihn zurück und sagt es.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/map/map_screen.dart';
import 'package:trailbuddy/features/trails/trail_providers.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late String hexentanz;

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
    hexentanz = trails.seedTrail(bob.id, name: 'Hexentanz', lat: 48.01, grade: 4);
    trails.seedTrail(bob.id, name: 'Alter Weg', lat: 48.02);
  });

  /// Die Namen der Trails, die die Karte gerade zeichnet.
  Set<String> drawn(WidgetTester tester) => {
        for (final l in fakeMapLayers(tester).polylines)
          if (l.hitValue is Trail) (l.hitValue as Trail).displayName,
      };

  Finder banner() => find.byKey(const ValueKey('map-filter-banner'));

  testWidgets('in der Liste gesetzt, auf der Karte gezeichnet, gemeldet und dort zurückgesetzt',
      (tester) async {
    await pumpApp(tester, backend, trails: trails);
    await settle(tester, frames: 20);
    expect(drawn(tester), {'Roßkopf Süd', 'Hexentanz', 'Alter Weg'});
    expect(banner(), findsNothing, reason: 'ohne Filter keine Zeile');

    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    await setGradeRange(tester, max: 2);
    await openTab(tester, 'Karte');
    await settle(tester, frames: 20);

    expect(drawn(tester), {'Roßkopf Süd'}, reason: 'S4 und „ohne Einschätzung" fehlen');
    expect(banner(), findsOneWidget);
    expect(find.text('Gefiltert: bis S2'), findsOneWidget);
    expect(find.text('1 von 3 Trails'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('map-filter-reset')));
    await settle(tester, frames: 20);
    expect(banner(), findsNothing);
    expect(drawn(tester), hasLength(3));

    // Zurückgesetzt heißt: auch in der Liste.
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    expect(tester.widget<FilterChip>(find.byKey(const ValueKey('trail-filter-grade'))).selected, isFalse);
  });

  testWidgets('im Blatt der Karte gesetzt, gilt in der Liste', (tester) async {
    await pumpApp(tester, backend, trails: trails);
    await settle(tester, frames: 20);
    await tester.tap(find.byTooltip('Kartenebenen'));
    await settle(tester);
    await tester.tap(find.text('Von Buddys').last);
    await settle(tester);
    await tester.tapAt(const Offset(400, 20)); // Blatt schließen
    await settle(tester, frames: 20);
    expect(drawn(tester), {'Hexentanz', 'Alter Weg'});
    expect(find.text('Gefiltert: Von Buddys'), findsOneWidget);

    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    expect(find.text('Roßkopf Süd'), findsNothing);
    expect(find.text('Hexentanz'), findsOneWidget);
  });

  testWidgets('ein Sprung auf einen ausgeblendeten Trail setzt den Filter zurück und sagt es',
      (tester) async {
    await pumpApp(tester, backend, trails: trails);
    await settle(tester, frames: 20);
    final container = ProviderScope.containerOf(tester.element(find.byType(MapScreen)));
    container.read(trailListFilterProvider.notifier).state =
        container.read(trailListFilterProvider).copyWith(maxGrade: 2);
    await settle(tester, frames: 20);
    expect(drawn(tester), {'Roßkopf Süd'});

    // So landet eine Push-Meldung (`/trail/<id>`) auf der Karte.
    container.read(mapFocusTrailProvider.notifier).state = hexentanz;
    await settle(tester, frames: 20);
    expect(find.text('Filter zurückgesetzt, damit der Trail zu sehen ist.'), findsOneWidget);
    expect(drawn(tester), contains('Hexentanz'));
    expect(banner(), findsNothing);
  });
}
