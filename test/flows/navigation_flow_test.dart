// Die Folgeansicht der Navigation (#232, Konzept-Routing 9) durch die
// echte Oberfläche: aus „Meine Fahrten" auf die Karte, Start-Dialog mit
// Aufzeichnen und Bildschirm, die Karte dreht nach dem Kurs, die Leiste
// zählt herunter, abseits wird gewarnt, „Norden" nordet, am Ziel endet die
// Navigation nach einer Minute — die Aufzeichnung läuft weiter.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/screen_awake.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/features/routing/nav_providers.dart' show kNavArrivedLinger;

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/fake_rides.dart';
import '../fakes/test_app.dart';

class _FakeScreenAwake implements ScreenAwake {
  final calls = <bool>[];

  @override
  bool get supported => true;

  @override
  Future<void> keepOn(bool on) async => calls.add(on);
}

/// Eine geplante Runde nach Osten: 20 Abschnitte à 0,001° Länge.
const _lat = 47.0;
double _lng(int i) => 11 + i / 1000;

void main() {
  late FakeBackend backend;
  late FakeRideStore store;
  late FakeRideService service;
  late _FakeScreenAwake screen;
  late StreamController<Position?> fixes;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    store = FakeRideStore()..uid = anna.id;
    final t0 = DateTime.utc(2026, 10, 8, 9);
    store.rides.add(Ride(
      id: '20261008T090000Z',
      startedAt: t0,
      endedAt: t0.add(const Duration(hours: 1)),
      points: [for (var i = 0; i <= 20; i++) RidePoint(lat: _lat, lng: _lng(i), at: t0, accuracyM: 0)],
      planned: true,
      name: 'Hausrunde',
    ));
    service = FakeRideService();
    screen = _FakeScreenAwake();
    fixes = StreamController<Position?>.broadcast();
    addTearDown(fixes.close);
  });

  Future<void> fix(WidgetTester tester, double lat, double lng, {double heading = 90, double speed = 5}) async {
    fixes.add(fakePosition(lat, lng, heading: heading, speed: speed));
    await settle(tester, frames: 2);
  }

  Future<void> startFromRides(WidgetTester tester, {bool phone = false}) async {
    if (phone) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }
    // Standardgröße wie `ride_flow_test`: In der Testschrift ist die Karte
    // „Fahrt läuft …" auf 360 dp breiter als der Schirm.
    await pumpApp(tester, backend,
        rideStore: store,
        rideService: service,
        rideFix: FakeRideFix()..next = RidePoint(lat: _lat, lng: _lng(0), at: DateTime.now().toUtc(), accuracyM: 5),
        positionStream: fixes.stream,
        positionFix: FakePositionFix(fakePosition(_lat, _lng(0), heading: 90, speed: 0)),
        extraOverrides: [screenAwakeProvider.overrideWithValue(screen)]);
    await openProfilePage(tester, 'rides');
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('ride-menu-20261008T090000Z')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('ride-navigate-20261008T090000Z')));
    await settle(tester);
  }

  String textIn(String key) => [
        for (final t in find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)).evaluate())
          (t.widget as Text).data ?? ''
      ].join(' ');

  testWidgets('from „Meine Fahrten": turns with the course, counts down, warns off the route, ends at the goal',
      (tester) async {
    await startFromRides(tester);
    // Der Start-Dialog: beide Schalter an (Betreiber, 2026-10-08).
    expect(find.byKey(const ValueKey('nav-go')), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('nav-record'))).value, isTrue);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('nav-screen'))).value, isTrue);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester);

    // Auf der Karte: Leiste statt Knöpfen, die Aufzeichnung läuft, der
    // Bildschirm bleibt an.
    expect(find.byKey(const ValueKey('nav-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('layers-button')), findsNothing);
    expect(find.byKey(const ValueKey('feedback-button')), findsNothing);
    expect(service.starts, 1);
    expect(screen.calls, [true]);
    expect(textIn('nav-remaining'), contains('1,5 km'));
    // Im Stand gilt die Richtung der Linie: nach Osten, also Osten oben.
    expect(fakeMap(tester).bearing, closeTo(90, 1));
    expect(fakeMap(tester).zoom, 16);
    // Die Position steht im unteren Drittel: Die Mitte liegt östlich davon.
    expect(fakeMap(tester).center.longitude, greaterThan(_lng(0)));
    // Die Route liegt unter dem Netz in der Farbe des Ergebnisses.
    expect(fakeMapLayers(tester).polylines.where((l) => l.width == 6), hasLength(1));

    // Fahren: der Rest schrumpft, der gefahrene Teil wird blass.
    await fix(tester, _lat, _lng(10));
    expect(textIn('nav-remaining'), contains('758 m'));
    expect(fakeMapLayers(tester).polylines.where((l) => l.width == 5), hasLength(1));
    // Der GPS-Kurs gilt in Fahrt.
    await fix(tester, _lat, _lng(11), heading: 80);
    expect(fakeMap(tester).bearing, 80);

    // Abseits: ein Ausreißer zählt nicht, der zweite Fix in Folge schon.
    await fix(tester, _lat + 0.0006, _lng(12));
    expect(textIn('nav-off'), contains('zur Route'));
    await fix(tester, _lat + 0.0006, _lng(12));
    expect(textIn('nav-off'), contains('neben der Route'));
    expect(textIn('nav-off'), contains('67 m'));
    expect(find.byKey(const ValueKey('nav-off-arrow')), findsOneWidget);

    // „Norden": genordet, sofort.
    await tester.tap(find.byKey(const ValueKey('nav-north')));
    await settle(tester, frames: 2);
    expect(fakeMap(tester).bearing, 0);

    // Der Bildschirm-Schalter in der Ansicht merkt sich, was er tut.
    await tester.tap(find.byKey(const ValueKey('nav-screen-toggle')));
    await settle(tester, frames: 2);
    expect(screen.calls.last, isFalse);

    // Am Ziel: „Angekommen", nach einer Minute ist die Ansicht weg.
    await fix(tester, _lat, _lng(20));
    expect(find.byKey(const ValueKey('nav-arrived')), findsOneWidget);
    await tester.pump(kNavArrivedLinger);
    await settle(tester);
    expect(find.byKey(const ValueKey('nav-bar')), findsNothing);
    expect(find.byKey(const ValueKey('layers-button')), findsOneWidget);
    expect(fakeMap(tester).bearing, 0);
    // Die Aufzeichnung endet nicht mit der Navigation (9.4).
    expect(service.running, isTrue);
  });

  testWidgets('taps on the map do nothing while navigating; Beenden asks nothing', (tester) async {
    // Auf dem Telefon (360 dp): Leiste und Knöpfe passen, ohne Aufzeichnung.
    await startFromRides(tester, phone: true);
    await tester.tap(find.byKey(const ValueKey('nav-record')));
    await settle(tester, frames: 2);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester);
    expect(service.starts, 0, reason: 'Aufzeichnen war aus');
    expect(tester.getSize(find.byKey(const ValueKey('nav-stop'))).height, greaterThanOrEqualTo(44));
    expect(tester.getBottomRight(find.byKey(const ValueKey('nav-stop'))).dx, lessThanOrEqualTo(360));
    // Ein langer Druck öffnete sonst „Route ab hier" (#177).
    await longPressMapAt(tester, const LatLng(_lat, 11.005));
    await settle(tester);
    expect(find.text('Route ab hier'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('nav-stop')));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const ValueKey('nav-bar')), findsNothing);
    expect(screen.calls, [true, false]);
  });
}
