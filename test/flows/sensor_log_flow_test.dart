// Sensor-Rohdaten mitschreiben (#36, Messplan 8.1), durch die echte
// Oberfläche: Den Schalter gibt es nur in der Dev-App
// (`sensorLogAvailableProvider`), er wird gemerkt, die nächste Fahrt
// trägt ihn über die Brücke in den Dienst, und „Meine Fahrten" gibt die
// Datei über das Teilen-Blatt heraus.
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/gpx_share.dart';
import 'package:trailbuddy/features/rides/ride_providers.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_rides.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late FakeRideStore store;
  late FakeRideServiceBridge bridge;
  late FakeRideFix fix;
  late FakeSettings settings;
  late List<({String path, String fileName})> shared;

  final t0 = DateTime.utc(2026, 10, 30, 9);
  const rideId = '20261030T090000Z';

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    store = FakeRideStore()..uid = anna.id;
    store.rides.add(Ride(id: rideId, startedAt: t0, endedAt: t0.add(const Duration(minutes: 30)), points: [
      for (var i = 0; i < 3; i++)
        RidePoint(lat: 7.0 + i * 0.001, lng: 9.0, at: t0.add(Duration(seconds: 5 * i)), accuracyM: 8),
    ]));
    bridge = FakeRideServiceBridge();
    fix = FakeRideFix();
    settings = FakeSettings();
    shared = [];
  });

  tearDown(() => IsolateNameServer.removePortNameMapping('flutter_foreground_task/isolateComPort'));

  Future<void> pump(WidgetTester tester, {required bool dev}) => pumpApp(tester, backend,
      settings: settings,
      rideStore: store,
      rideBridge: bridge,
      rideFix: fix,
      extraOverrides: [
        sensorLogAvailableProvider.overrideWithValue(dev),
        sensorLogShareProvider.overrideWithValue(({required String path, required String fileName}) async {
          shared.add((path: path, fileName: fileName));
        }),
      ]);

  final toggle = find.byKey(const ValueKey('sensor-log-switch'));

  Future<void> openRideMenu(WidgetTester tester) async {
    await openProfilePage(tester, 'rides');
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('ride-menu-$rideId')));
    await settle(tester);
  }

  testWidgets('in der echten App: kein Schalter, kein Menüpunkt, die Fahrt schreibt nichts mit',
      (tester) async {
    settings.sensorLogEnabled = true; // einmal in der Dev-App gesetzt — zählt hier nicht
    FlutterForegroundTask.initCommunicationPort();
    fix.next = RidePoint(lat: 47.2, lng: 11.4, at: t0, accuracyM: 5);
    await pump(tester, dev: false);
    await tester.tap(find.byKey(const ValueKey('ride-button')));
    await settle(tester);
    expect(bridge.armed, isTrue);
    expect(bridge.sensorLog, isFalse);

    await openRideMenu(tester);
    expect(find.text('Als GPX exportieren'), findsOneWidget);
    expect(find.text('Sensordaten teilen'), findsNothing);
  });

  testWidgets('in der echten App: kein Schalter unter „Über TrailBuddy"', (tester) async {
    await pump(tester, dev: false);
    await openProfilePage(tester, 'about');
    expect(find.text('Vorabversionen erhalten'), findsOneWidget);
    expect(toggle, findsNothing);
  });

  testWidgets('Dev-App: Schalter gemerkt, die Fahrt nimmt ihn mit in den Dienst', (tester) async {
    FlutterForegroundTask.initCommunicationPort();
    fix.next = RidePoint(lat: 47.2, lng: 11.4, at: t0, accuracyM: 5);
    await pump(tester, dev: true);
    await openProfilePage(tester, 'about');
    await scrollTo(tester, toggle);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.tap(toggle);
    await settle(tester);
    expect(settings.sensorLogEnabled, isTrue);

    await openTab(tester, 'Karte');
    await tester.tap(find.byKey(const ValueKey('ride-button')));
    await settle(tester);
    expect(bridge.armed, isTrue);
    expect(bridge.sensorLog, isTrue, reason: 'der Dienst liest den Schalter aus der Brücke');
  });

  testWidgets('Dev-App: „Sensordaten teilen" gibt die Datei heraus, ohne Datei sagt es das',
      (tester) async {
    await pump(tester, dev: true);
    await openRideMenu(tester);
    await tester.tap(find.text('Sensordaten teilen'));
    await settle(tester);
    expect(shared, isEmpty);
    expect(find.text('Zu dieser Fahrt gibt es keine Sensordaten.'), findsOneWidget);

    store.sensorLogs[rideId] = '/data/rides/sensors/$rideId.csv';
    await drainSnackbars(tester);
    await tester.tap(find.byKey(const ValueKey('ride-menu-$rideId')));
    await settle(tester);
    await tester.tap(find.text('Sensordaten teilen'));
    await settle(tester);
    expect(shared.single.path, '/data/rides/sensors/$rideId.csv');
    expect(shared.single.fileName, 'trailbuddy-sensors-$rideId.csv');
  });
}
