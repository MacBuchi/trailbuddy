// Airtime unter Buddys (#36 Schritt 6, Patch 029): Anna teilt, Bob auch.
// Der Abgleich beim Start schickt Annas Bestwert und Zähler; das
// Trail-Blatt zeigt die Rangliste, der Buddys-Reiter Zähler und Titel.
// Ab Werk ist alles aus, und Ausschalten löscht das Geteilte.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/data/airtime_repository.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/features/rides/sensor_fusion.dart';
import 'package:trailbuddy/features/rides/trail_values.dart';

import '../fakes/fake_airtime.dart';
import '../fakes/fake_backend.dart';
import '../fakes/fake_rides.dart';
import '../fakes/fake_settings.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late FakeAirtimeRepository airtime;
  late FakeRideStore store;
  late String annaId, bobId, roots;
  final today = DateTime.now();
  final t0 = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 2)).add(const Duration(hours: 10));

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    final bob = backend.addUser(username: 'bob');
    backend.addFriendship(anna.id, bob.id);
    backend.signInAs(anna.id);
    annaId = anna.id;
    bobId = bob.id;
    trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    trails.usernames[bob.id] = 'bob';
    // Bobs Trail, 48,000° bis 48,009° auf 9°.
    roots = trails.seedTrail(bob.id, name: 'Roots');
    airtime = FakeAirtimeRepository(backend, trails: trails);
    airtime.bests.add(TrailAirtime(userId: bob.id, trailId: roots, airDs: 51, longestDs: 12, month: DateTime(2026, 10)));
    airtime.counters.add(AirtimeCounter(
        userId: bob.id, airDs: 420, jumps: 30, asOf: DateTime(today.year, today.month, today.day), titles: {AirtimeTitle.glider}));
    // Annas Fahrt über Roots, 5 s je 20 m; zwei Sprünge auf dem Trail.
    store = FakeRideStore()..uid = anna.id;
    final points = <RidePoint>[];
    for (var i = 0; i <= 80; i++) {
      points.add(RidePoint(lat: 47.9985 + i * 0.00018, lng: 9.0, at: t0.add(Duration(seconds: 5 * i)), accuracyM: 5));
    }
    store.rides.add(Ride(id: 'r1', startedAt: t0, endedAt: points.last.at, points: points));
    int us(int s) => t0.add(Duration(seconds: s)).microsecondsSinceEpoch;
    store.airtimeLogs['r1'] = AirtimeLog(events: [
      JumpEvent(startUs: us(100), duration: const Duration(milliseconds: 600), landingG: 2.4, upright: true, plausible: true),
      JumpEvent(startUs: us(200), duration: const Duration(milliseconds: 900), landingG: 2.9, upright: true, plausible: true),
    ]);
    store.sensorLogs['r1'] = '/sensors/r1.csv';
  });

  testWidgets('geteilt: der Start schickt Bestwert und Zähler, Blatt und Buddys zeigen den Vergleich', (tester) async {
    await pumpApp(tester, backend,
        trails: trails,
        rideStore: store,
        airtime: airtime,
        settings: FakeSettings(sensorLogEnabled: true, airtimeShareEnabled: true));
    await settle(tester, frames: 20);

    final mine = airtime.bests.singleWhere((b) => b.userId == annaId);
    expect((mine.trailId, mine.airDs, mine.longestDs, mine.month), (roots, 15, 9, DateTime(t0.year, t0.month)));
    final counter = airtime.counters.singleWhere((c) => c.userId == annaId);
    expect((counter.airDs, counter.jumps), (15, 2));
    expect(counter.titles, isEmpty, reason: 'kein Sprung über 1 s, aber gesprungen');

    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    await tester.tap(find.text('Roots'));
    await settle(tester);
    final panel = find.byKey(const ValueKey('airtime-panel'));
    await tester.ensureVisible(panel);
    expect(find.descendant(of: panel, matching: find.text('AIRTIME UNTER BUDDYS')), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.text('Spiel, kein Rekord')), findsOneWidget);
    expect(find.descendant(of: find.byKey(ValueKey('airtime-rank-$bobId')), matching: find.text('5,1 s')), findsOneWidget);
    final me = find.byKey(ValueKey('airtime-rank-$annaId'));
    expect(find.descendant(of: me, matching: find.text('Du')), findsOneWidget);
    expect(find.descendant(of: me, matching: find.text('1,5 s')), findsOneWidget);
    expect(find.descendant(of: me, matching: find.text('2')), findsOneWidget, reason: 'Platz 2 hinter Bob');
    expect(find.text('Airtime je Durchfahrt · dein längster Sprung 0,9 s'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Schließen').first);
    await tester.tap(find.byTooltip('Schließen').first);
    await settle(tester);
    await openTab(tester, 'Buddys');
    await settle(tester);
    final bob = find.byKey(ValueKey('buddy-airtime-$bobId'));
    expect(find.descendant(of: bob, matching: find.text('Airtime 30 Tage 42,0 s')), findsOneWidget);
    for (final t in ['SEGELFLIEGER', 'VIELFLIEGER', 'TRAILKÖNIG · 1']) {
      expect(find.descendant(of: bob, matching: find.text(t)), findsOneWidget, reason: t);
    }
    final card = find.byKey(const ValueKey('my-airtime-card'));
    expect(find.descendant(of: card, matching: find.text('1,5 s')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('2 Sprünge')), findsOneWidget);
  });

  testWidgets('ab Werk aus: nichts geht hinaus, nichts wird gezeigt, der Schalter wartet auf die Erkennung',
      (tester) async {
    await pumpApp(tester, backend, trails: trails, rideStore: store, airtime: airtime);
    await settle(tester, frames: 20);
    expect(airtime.uploadCalls, 0);
    expect(airtime.counters.where((c) => c.userId == annaId), isEmpty);

    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    await tester.tap(find.text('Roots'));
    await settle(tester);
    expect(find.byKey(const ValueKey('airtime-panel')), findsNothing, reason: 'wer nicht teilt, sieht nichts');
    await tester.ensureVisible(find.byTooltip('Schließen').first);
    await tester.tap(find.byTooltip('Schließen').first);
    await settle(tester);

    await openProfilePage(tester, 'about');
    expect(find.byKey(const ValueKey('airtime-share-switch')), findsNothing, reason: 'nur unter der Erkennung');
    await scrollTo(tester, find.byKey(const ValueKey('sensor-log-switch')));
    await tester.tap(find.byKey(const ValueKey('sensor-log-switch')));
    await settle(tester);
    final share = find.byKey(const ValueKey('airtime-share-switch'));
    await scrollTo(tester, share);
    expect(tester.widget<SwitchListTile>(share).value, isFalse);
    await tester.tap(share);
    await settle(tester, frames: 20);
    expect(tester.widget<SwitchListTile>(share).value, isTrue);
    expect(airtime.bests.where((b) => b.userId == annaId), hasLength(1), reason: 'Einschalten gleicht sofort ab');
  });

  testWidgets('Ausschalten löscht das Geteilte; ohne Netz bleibt der Schalter an und sagt es', (tester) async {
    final settings = FakeSettings(sensorLogEnabled: true, airtimeShareEnabled: true);
    await pumpApp(tester, backend, trails: trails, rideStore: store, airtime: airtime, settings: settings);
    await settle(tester, frames: 20);
    expect(airtime.counters.where((c) => c.userId == annaId), hasLength(1));

    await openProfilePage(tester, 'about');
    final share = find.byKey(const ValueKey('airtime-share-switch'));
    await scrollTo(tester, share);
    backend.offline = true;
    await tester.tap(share);
    await settle(tester);
    expect(tester.widget<SwitchListTile>(share).value, isTrue);
    expect(find.text('Ausschalten braucht Netz — deine Werte bleiben geteilt, bis es klappt.'), findsOneWidget);
    expect(settings.airtimeShareEnabled, isTrue);
    await drainSnackbars(tester);

    backend.offline = false;
    await tester.tap(share);
    await settle(tester);
    expect(tester.widget<SwitchListTile>(share).value, isFalse);
    expect(settings.airtimeShareEnabled, isFalse);
    expect(airtime.bests.where((b) => b.userId == annaId), isEmpty);
    expect(airtime.counters.where((c) => c.userId == annaId), isEmpty);
    expect(airtime.bests.where((b) => b.userId == bobId), hasLength(1), reason: 'Bobs Werte bleiben');
  });
}
