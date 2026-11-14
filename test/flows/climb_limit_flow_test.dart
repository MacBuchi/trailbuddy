// Das Limit aus Fahrten (#516 Schritt 6, Konzept-Routing 12.5a): Nach einer
// Aufzeichnung über dem Höhenmeter-Limit steht EINE Zeile im Blatt am Ende
// der Fahrt; die Antwort gilt sofort, mit Rückgängig. Unbeantwortet steht
// sie einmal im Einstieg des Planers.
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trailbuddy/core/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/rides/climb_limit_offer.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/features/routing/loop_planner.dart';
import 'package:trailbuddy/features/routing/loop_planner_controller.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_rides.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

const _portName = 'flutter_foreground_task/isolateComPort';

void main() {
  late FakeBackend backend;
  late FakeRideStore store;
  late FakeRideFix fix;
  late FakeSettings settings;

  final t0 = DateTime.utc(2026, 11, 14, 9);

  /// Ein Anstieg über [gainM] mit [rateMPerH], alle 10 s ein Punkt, dann
  /// 60 m hinab (wie im Test des Rad-Vorschlags).
  List<RidePoint> climb(double gainM, double rateMPerH) {
    final n = (gainM / rateMPerH * 3600 / 10).round();
    return [
      for (var i = 0; i <= n + 30; i++)
        RidePoint(
          lat: 47.2 + i / 10000,
          lng: 11.4,
          at: t0.add(Duration(seconds: 10 * i)),
          accuracyM: 5,
          altM: i <= n ? 800 + gainM * i / n : 800 + gainM - 2.0 * (i - n),
        ),
    ];
  }

  setUp(() {
    backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'anna').id);
    store = FakeRideStore();
    fix = FakeRideFix();
    settings = FakeSettings();
  });

  tearDown(() => IsolateNameServer.removePortNameMapping(_portName));

  Future<void> pump(WidgetTester tester) => pumpApp(tester, backend,
      rideStore: store,
      rideFix: fix,
      rideBridge: FakeRideServiceBridge(),
      rideService: FakeRideService(),
      settings: settings);

  /// Aufzeichnen, die Spur liegt in der Datei, beenden — das Blatt steht.
  Future<void> ride(WidgetTester tester, List<RidePoint> pts) async {
    FlutterForegroundTask.initCommunicationPort();
    fix.next = pts.first;
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('ride-button')));
    await settle(tester);
    for (final p in pts.skip(1)) {
      await store.appendPoint(p);
    }
    await drainSnackbars(tester);
    await tester.tap(find.byKey(const ValueKey('ride-button')));
    await settle(tester);
    expect(find.text('Fahrt beendet'), findsOneWidget);
  }

  LoopPrefs prefs() => LoopPrefs.parse(settings.loopPlannerPrefs, RiderProfile.bio);

  testWidgets('über dem Limit: eine Zeile, Anheben gilt sofort, Rückgängig nimmt es zurück', (tester) async {
    await ride(tester, climb(1150, 400));
    expect(find.text('1100 hm geschafft — Limit fürs Bio-Bike von 800 auf 1100 hm anheben?'), findsOneWidget);
    expect(settings.climbLimitPending, isNotNull, reason: 'für den Einstieg des Planers gemerkt');

    await tester.tap(find.byKey(const ValueKey('climb-limit-raise')));
    await settle(tester);
    expect(prefs().climbBioM, 1100);
    expect(prefs().climbEbikeM, 1400, reason: 'das E-Bike behält seins');
    expect(settings.climbLimitPending, isNull, reason: 'beantwortet');
    expect(find.text('Limit fürs Bio-Bike jetzt 1100 hm'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('climb-limit-undo')));
    await settle(tester);
    expect(prefs().climbBioM, 800);
    expect(find.byKey(const ValueKey('climb-limit-raise')), findsOneWidget);
  });

  testWidgets('Nein wird gemerkt, und die gleiche Fahrt fragt nicht noch einmal', (tester) async {
    await ride(tester, climb(1150, 400));
    await tester.tap(find.byKey(const ValueKey('climb-limit-keep')));
    await settle(tester);
    expect(prefs().declinedBioM, 1100);
    expect(prefs().climbBioM, 800);
    expect(find.text('Limit fürs Bio-Bike bleibt bei 800 hm'), findsOneWidget);
  });

  testWidgets('unter dem Limit keine Zeile', (tester) async {
    await ride(tester, climb(850, 400));
    expect(find.byKey(const ValueKey('climb-limit')), findsNothing);
    expect(settings.climbLimitPending, isNull);
  });

  testWidgets('sah nach E-Bike aus: Ja ordnet die Fahrt um, unter dem E-Limit hebt es nichts', (tester) async {
    await ride(tester, climb(1150, 900));
    expect(find.text('1100 hm — sah nach E-Bike aus. War es eins?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('climb-limit-ebike-yes')));
    await settle(tester);
    expect(store.rides.single.profile, 'ebike');
    expect((prefs().climbBioM, prefs().climbEbikeM), (800, 1400));
    expect(find.text('Als E-Bike-Fahrt gespeichert'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('climb-limit-undo')));
    await settle(tester);
    expect(store.rides.single.profile, 'bio', reason: 'Rückgängig ordnet zurück');
  });

  testWidgets('Nein, Bio-Bike ist die Bestätigung: das Bio-Limit steigt ohne zweite Frage', (tester) async {
    await ride(tester, climb(1150, 900));
    await tester.tap(find.byKey(const ValueKey('climb-limit-ebike-no')));
    await settle(tester);
    expect(prefs().climbBioM, 1100);
    expect(store.rides.single.profile, 'bio');
  });

  testWidgets('unbeantwortet steht die Frage einmal im Einstieg des Planers', (tester) async {
    settings.climbLimitPending =
        const ClimbLimitOffer(rideId: 'r1', bike: RiderProfile.bio, climbM: 1100, toM: 1100).encode();
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('loop-button')));
    await settle(tester, frames: 10);
    expect(find.byKey(const ValueKey('loop-entry')), findsOneWidget);
    expect(find.byKey(const ValueKey('climb-limit')), findsOneWidget);
    expect(settings.climbLimitPending, isNull, reason: 'einmal — danach ist sie weg');

    await tester.tap(find.byKey(const ValueKey('climb-limit-raise')));
    await settle(tester);
    expect(prefs().climbBioM, 1100);

    await tester.tap(find.byKey(const ValueKey('loop-entry-close')));
    await settle(tester, frames: 10);
    await tester.tap(find.byKey(const ValueKey('loop-button')));
    await settle(tester, frames: 10);
    expect(find.byKey(const ValueKey('climb-limit')), findsNothing);
  });

  test('im Planer hat jedes Rad sein Limit: der Wechsel holt das andere, der Regler stellt das eigene', () {
    final c = ProviderContainer(overrides: [settingsProvider.overrideWithValue(settings)]);
    addTearDown(c.dispose);
    final n = c.read(loopPlannerProvider.notifier);
    n.setPrefs(c.read(loopPlannerProvider).prefs.copyWith(climbM: 1000));
    n.setProfile(RiderProfile.ebike);
    expect(c.read(loopPlannerProvider).prefs.climbM, 1400, reason: 'bis 0.176.0 blieb die 1000 stehen');
    n.setPrefs(c.read(loopPlannerProvider).prefs.copyWith(climbM: 1800));
    n.setProfile(RiderProfile.bio);
    expect(c.read(loopPlannerProvider).prefs.climbM, 1000);
    expect((prefs().climbBioM, prefs().climbEbikeM), (1000, 1800));
  });
}
