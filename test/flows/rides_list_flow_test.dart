// „Meine Fahrten" aufräumen (#228, #227) durch die echte Oberfläche: das
// Rad je Fahrt sehen und umstellen, nach links wischen löscht erst nach
// Nachfrage, langer Druck wählt mehrere — Rad setzen und Löschen für alle,
// und Zurück beendet zuerst die Auswahl (#175).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_rides.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late FakeRideStore store;

  Ride ride(int k, {String? profile = 'bio', bool planned = false, double hm = 0}) {
    final t0 = DateTime.utc(2026, 9, 20 + k, 9);
    final pts = [
      for (var i = 0; i <= 60; i++)
        RidePoint(lat: 47 + i / 10000, lng: 11, at: t0.add(Duration(seconds: 10 * i)), accuracyM: 5,
            altM: 500 + i * hm / 60),
    ];
    return Ride(
        id: '2026092${k}T090000Z',
        startedAt: t0,
        endedAt: pts.last.at,
        points: pts,
        profile: profile,
        planned: planned,
        name: planned ? 'Runde $k' : null);
  }

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    store = FakeRideStore()..uid = anna.id;
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, backend, rideStore: store);
    await openProfilePage(tester, 'rides');
    await settle(tester);
  }

  String? profileOf(String id) => store.rides.firstWhere((r) => r.id == id).profile;

  testWidgets('das Rad steht an der Fahrt und lässt sich umstellen (#228)', (tester) async {
    store.rides.addAll([ride(1), ride(2, profile: null, hm: 150), ride(3, planned: true)]);
    await open(tester);
    final chip = find.byKey(const ValueKey('ride-profile-20260921T090000Z'));
    expect(find.descendant(of: chip, matching: find.text('Bio-Bike')), findsOneWidget);
    // Ohne Profil (vor 0.70.0): „Rad wählen" mit dem Vorschlag — gesetzt
    // wird er nicht von selbst.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('ride-profile-20260922T090000Z')),
            matching: find.text('Rad wählen · passt zu E-Bike')),
        findsOneWidget);
    expect(profileOf('20260922T090000Z'), isNull);
    // Eine geplante Fahrt hat keinen Chip, ihr Rad steht im Text.
    await scrollTo(tester, find.byKey(const ValueKey('ride-20260923T090000Z')));
    expect(find.byKey(const ValueKey('ride-profile-20260923T090000Z')), findsNothing);
    expect(find.textContaining('· Bio-Bike'), findsOneWidget);
    await scrollTo(tester, chip);
    expect(tester.getSize(chip).height, greaterThanOrEqualTo(44));

    await tester.tap(chip);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('ride-profile-20260921T090000Z-ebike')));
    await settle(tester);
    expect(profileOf('20260921T090000Z'), 'ebike');
    expect(find.descendant(of: chip, matching: find.text('E-Bike')), findsOneWidget);
    expect(find.text('Fahrt als E-Bike eingeordnet.'), findsOneWidget);
    expect(find.text('Neu lernen'), findsOneWidget);
  });

  testWidgets('wischen fragt, „Abbrechen" behält, „Löschen" löscht (#227)', (tester) async {
    store.rides.addAll([ride(1), ride(2)]);
    await open(tester);
    final tile = find.byKey(const ValueKey('ride-20260921T090000Z'));
    await tester.drag(tile, const Offset(-600, 0));
    await settle(tester);
    expect(find.text('Fahrt löschen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await settle(tester);
    expect(store.rides, hasLength(2));
    expect(tile, findsOneWidget);

    await tester.drag(tile, const Offset(-600, 0));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('ride-delete-confirm')));
    await settle(tester);
    expect(store.rides.map((r) => r.id), ['20260922T090000Z']);
    expect(tile, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('langer Druck wählt mehrere: Rad für alle, löschen für alle, Zurück beendet', (tester) async {
    store.rides.addAll([ride(1), ride(2), ride(3), ride(4, planned: true)]);
    await open(tester);
    await tester.longPress(find.byKey(const ValueKey('ride-20260921T090000Z')));
    await settle(tester);
    expect(find.text('1 ausgewählt'), findsOneWidget);
    // In der Auswahl schaltet ein Tipp um, statt auf die Karte zu gehen.
    await tester.tap(find.byKey(const ValueKey('ride-20260922T090000Z')));
    await scrollTo(tester, find.byKey(const ValueKey('ride-20260924T090000Z')));
    await tester.tap(find.byKey(const ValueKey('ride-20260924T090000Z')));
    await settle(tester);
    expect(find.text('3 ausgewählt'), findsOneWidget);
    expect(find.byTooltip('Fahrt zerlegen'), findsNothing, reason: 'keine Schere in der Auswahl');

    // Rad für alle gemessenen — die geplante behält ihres.
    await tester.tap(find.byKey(const ValueKey('rides-selection-profile')));
    await settle(tester);
    await tester.tap(find.text('Als E-Bike'));
    await settle(tester);
    expect(profileOf('20260921T090000Z'), 'ebike');
    expect(profileOf('20260922T090000Z'), 'ebike');
    expect(profileOf('20260923T090000Z'), 'bio');
    expect(profileOf('20260924T090000Z'), 'bio');
    expect(find.text('2 Fahrten als E-Bike eingeordnet.'), findsOneWidget);
    expect(find.textContaining('ausgewählt'), findsNothing, reason: 'danach ist die Auswahl vorbei');

    // Zurück beendet die Auswahl und bleibt auf der Seite.
    await scrollTo(tester, find.byKey(const ValueKey('ride-20260923T090000Z')));
    await tester.longPress(find.byKey(const ValueKey('ride-20260923T090000Z')));
    await settle(tester);
    expect(find.text('1 ausgewählt'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.textContaining('ausgewählt'), findsNothing);
    expect(find.text('Meine Fahrten'), findsOneWidget);

    // Löschen für zwei, mit einer Nachfrage.
    await scrollTo(tester, find.byKey(const ValueKey('ride-20260921T090000Z')));
    await tester.longPress(find.byKey(const ValueKey('ride-20260921T090000Z')));
    await settle(tester);
    await scrollTo(tester, find.byKey(const ValueKey('ride-20260923T090000Z')));
    await tester.tap(find.byKey(const ValueKey('ride-20260923T090000Z')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('rides-selection-delete')));
    await settle(tester);
    expect(find.text('2 Fahrten löschen?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ride-delete-confirm')));
    await settle(tester);
    expect(store.rides.map((r) => r.id).toSet(), {'20260922T090000Z', '20260924T090000Z'});
    expect(find.textContaining('ausgewählt'), findsNothing);
  });
}
