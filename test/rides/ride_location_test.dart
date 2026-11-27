// Der Standort der Fahrt je Plattform (#644, Paket 3): Android fragt je
// Takt, iOS hält einen Strom und der Takt liest dessen letzten Punkt.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:trailbuddy/features/rides/ride_location.dart';

Position _at(DateTime t, {double lat = 7.001}) => Position(
  latitude: lat,
  longitude: 11.002,
  timestamp: t,
  accuracy: 5,
  altitude: 800,
  altitudeAccuracy: 3,
  heading: 0,
  headingAccuracy: 0,
  speed: 4,
  speedAccuracy: 1,
);

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('Einstellungen je Plattform', () {
    test('iOS: Hintergrund erlaubt, blauer Hinweis, kein Selbst-Pausieren', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final s = rideLocationSettings();
      expect(s, isA<AppleSettings>());
      s as AppleSettings;
      expect(s.allowBackgroundLocationUpdates, isTrue);
      expect(s.showBackgroundLocationIndicator, isTrue);
      expect(s.pauseLocationUpdatesAutomatically, isFalse);
      expect(s.activityType, ActivityType.fitness);
      expect(s.accuracy, LocationAccuracy.best);
    });

    test('Android: wie bisher, mit dem Abstand des Aufrufers', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final s = rideLocationSettings(interval: const Duration(seconds: 1));
      expect(s, isA<AndroidSettings>());
      expect(
        (s as AndroidSettings).intervalDuration,
        const Duration(seconds: 1),
      );
      expect(s.accuracy, LocationAccuracy.best);
    });
  });

  group('HeldFix (iOS)', () {
    late StreamController<Position> positions;
    late DateTime now;
    late int opened;
    late HeldFix held;

    setUp(() {
      positions = StreamController<Position>.broadcast();
      now = DateTime.utc(2026, 11, 26, 10);
      opened = 0;
      held = HeldFix(
        positions: () {
          opened++;
          return positions.stream;
        },
        now: () => now,
      );
    });

    tearDown(() async {
      await held.stop();
      await positions.close();
    });

    test('nimmt den letzten frischen Punkt, jeden nur einmal', () async {
      held.start();
      expect(await held.fix(), isNull, reason: 'noch kein Punkt');
      positions.add(_at(now.subtract(const Duration(seconds: 2))));
      positions.add(_at(now.subtract(const Duration(seconds: 1)), lat: 7.002));
      await Future<void>.delayed(Duration.zero);
      expect((await held.fix())!.latitude, 7.002);
      expect(await held.fix(), isNull, reason: 'derselbe Punkt zweimal');
      expect(opened, 1, reason: 'EIN Strom, kein neuer je Takt');
    });

    test('ein alter Punkt ist keine Messung', () async {
      held.start();
      positions.add(_at(now.subtract(const Duration(seconds: 11))));
      await Future<void>.delayed(Duration.zero);
      expect(await held.fix(), isNull);
    });

    test('ein Fehler beendet den Strom nicht', () async {
      held.start();
      positions.addError(const PermissionDeniedException('weg'));
      positions.add(_at(now));
      await Future<void>.delayed(Duration.zero);
      expect(await held.fix(), isNotNull);
      expect(held.running, isTrue);
    });

    test('endet der Strom, öffnet der nächste Takt einen neuen', () async {
      final first = StreamController<Position>();
      final h = HeldFix(
        positions: () {
          opened++;
          return opened == 1 ? first.stream : positions.stream;
        },
        now: () => now,
      );
      h.start();
      await first.close();
      await Future<void>.delayed(Duration.zero);
      expect(h.running, isFalse);
      await h.fix();
      expect(opened, 2);
      expect(h.running, isTrue);
      await h.stop();
    });

    test('stop schließt den Strom und vergisst den Punkt', () async {
      held.start();
      positions.add(_at(now));
      await Future<void>.delayed(Duration.zero);
      await held.stop();
      expect(held.running, isFalse);
      expect(positions.hasListener, isFalse);
    });
  });
}
