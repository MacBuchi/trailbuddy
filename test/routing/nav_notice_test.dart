// Die Navigation im Dienst (#232 Schritt 2, Konzept-Routing 9.5): die
// Routen-Datei, der Text der Benachrichtigung, der Takt mit eigenen
// Fixen — und „Navigation beenden" ohne App. Die Brücke liegt in
// SharedPreferences (mockbar wie in `ride_task_handler_test`), die Datei
// in einem echten Verzeichnis.
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailbuddy/features/rides/ride_service.dart';
import 'package:trailbuddy/features/rides/ride_task_handler.dart';
import 'package:trailbuddy/features/routing/nav_notice.dart';
import 'package:trailbuddy/features/routing/route_progress.dart';

/// Eine gerade Linie nach Osten: 20 Abschnitte à 0,001° (≈ 76 m).
const _lat = 47.0;
double _lng(int i) => 11 + i / 1000;
final _points = [for (var i = 0; i <= 20; i++) LatLng(_lat, _lng(i))];

Position _at(double lat, double lng) => Position(
    latitude: lat, longitude: lng, timestamp: DateTime.utc(2026, 10, 8, 9), accuracy: 5, altitude: 0,
    altitudeAccuracy: 0, heading: 90, headingAccuracy: 0, speed: 5, speedAccuracy: 0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory base;
  var rev = 0;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('nav_notice');
    addTearDown(() => base.delete(recursive: true));
    SharedPreferences.setMockInitialValues({});
    resetNavTick();
    rev = 0;
  });

  /// Was die App beim Start tut (`PlatformNavServiceBridge.arm`).
  Future<void> arm(NavRouteData route, {bool active = true}) async {
    final file = navRouteFile(base.path);
    await file.parent.create(recursive: true);
    await file.writeAsString(route.encode());
    await FlutterForegroundTask.saveData(key: kRideDataDir, value: base.path);
    await FlutterForegroundTask.saveData(key: kNavDataRev, value: ++rev);
    await FlutterForegroundTask.saveData(key: kNavDataActive, value: active);
  }

  group('NavRouteData', () {
    test('round trip with and without the height profile', () {
      final plain = NavRouteData.decode(NavRouteData(points: _points, title: 'Hausrunde').encode())!;
      expect(plain.points, _points);
      expect(plain.title, 'Hausrunde');
      expect(plain.climbDistM, isNull);
      final withClimb = NavRouteData.decode(NavRouteData(
              points: _points, title: 'x', startAlongM: 120, climbDistM: [0, 50], climbEleM: [600, 640])
          .encode())!;
      expect(withClimb.startAlongM, 120);
      expect(withClimb.climbEleM, [600, 640]);
    });

    test('anything odd reads as no route — half a route would be worse', () {
      expect(NavRouteData.decode('kaputt'), isNull);
      expect(NavRouteData.decode('{"v":2,"pts":[[47,11],[47,11.1]]}'), isNull);
      expect(NavRouteData.decode('{"v":1,"pts":[[47.0,11.0]]}'), isNull);
    });
  });

  group('navNoticeText', () {
    NavState state({double remaining = 12400, double off = 4, bool offRoute = false, bool arrived = false}) =>
        NavState(
            alongM: 0,
            remainingM: remaining,
            offM: off,
            offRoute: offRoute,
            arrived: arrived,
            headingDeg: 0,
            position: _points.first,
            rejoin: _points.first);

    test('the bar as one line (9.5)', () {
      expect(navNoticeText(state(), climbM: 640.4), 'Noch 12,4 km · 640 hm · auf der Route');
      expect(navNoticeText(state(off: 45, offRoute: true), climbM: 640),
          'Noch 12,4 km · 640 hm · 45 m neben der Route');
      // Ohne Höhenprofil nur km.
      expect(navNoticeText(state(remaining: 800)), 'Noch 800 m · auf der Route');
      expect(navNoticeText(state(arrived: true)), 'Angekommen');
    });

    test('the title says when the ride is recorded too', () {
      expect(navNoticeTitle(recording: false), 'Navigation');
      expect(navNoticeTitle(recording: true), contains('Fahrt wird aufgezeichnet'));
    });
  });

  group('navTick', () {
    test('computes from its own fixes and writes the notification', () async {
      await arm(NavRouteData(points: _points, title: 'Hausrunde'));
      final shown = <String>[];
      final s = await navTick(
          fix: () async => _at(_lat, _lng(10)),
          recording: false,
          show: (title, text) async => shown.add('$title | $text'));
      expect(s, isNotNull);
      expect(shown.single, 'Navigation | Noch 758 m · auf der Route');
      // Der Stand liegt in der Brücke — eine neu gestartete App geht dort weiter.
      expect(await FlutterForegroundTask.getData<double>(key: kNavDataAlong), closeTo(758, 5));
    });

    test('the same line again (heights arrived) keeps the stand; a new line starts over', () async {
      // Hin und zurück auf derselben Linie: Ohne gemerkten Stand fände
      // die Suche auf dem Rückweg die Hinfahrt.
      final back = [..._points, for (var i = 19; i >= 0; i--) LatLng(_lat, _lng(i))];
      await arm(NavRouteData(points: back, title: 'hin und zurück'));
      final shown = <String>[];
      Future<void> show(String title, String text) async => shown.add(text);
      for (final i in [10, 18, 20]) {
        await navTick(fix: () async => _at(_lat, _lng(i)), recording: false, show: show);
      }
      // Jetzt auf dem Rückweg bei 18: 2 Abschnitte zurück gefahren.
      await arm(NavRouteData(points: back, title: 'hin und zurück', climbDistM: [0, 3000], climbEleM: [500, 600]));
      await navTick(fix: () async => _at(_lat, _lng(18)), recording: false, show: show);
      expect(shown.last, startsWith('Noch 1,4 km'), reason: 'Stand blieb auf dem Rückweg');
      expect(shown.last, contains('hm'), reason: 'das Profil kam dazu');

      await arm(NavRouteData(points: _points, title: 'neu'));
      await navTick(fix: () async => _at(_lat, _lng(18)), recording: false, show: show);
      expect(shown.last, startsWith('Noch 152 m'));
    });

    test('without a navigation the GPS is not even asked', () async {
      await arm(NavRouteData(points: _points, title: 'x'), active: false);
      var asked = 0;
      final s = await navTick(
          fix: () async {
            asked++;
            return _at(_lat, _lng(1));
          },
          recording: false,
          show: (_, _) async {});
      expect(s, isNull);
      expect(asked, 0);
    });

    test('arrived and the minute is up: it ends itself, even without the app', () async {
      await arm(NavRouteData(points: _points, title: 'x'));
      var now = DateTime.utc(2026, 10, 8, 9);
      var ended = 0;
      Future<void> tick() => navTick(
          fix: () async => _at(_lat, _lng(20)),
          recording: false,
          show: (_, _) async {},
          onLingered: () async => ended++,
          now: () => now);
      await tick();
      expect(ended, 0);
      now = now.add(kNavArrivedLinger - const Duration(seconds: 5));
      await tick();
      expect(ended, 0);
      now = now.add(const Duration(seconds: 5));
      await tick();
      expect(ended, 1);
    });
  });

  test('serviceTick: ride and navigation share ONE fix per tick', () async {
    await arm(NavRouteData(points: _points, title: 'x'));
    await FlutterForegroundTask.saveData(key: kRideDataActive, value: true);
    var asked = 0;
    await serviceTick(fix: () async {
      asked++;
      return _at(_lat, _lng(2));
    });
    expect(asked, 1);
  });

  group('stopNavFromService', () {
    test('without a ride: bridge off, file gone, the whole service ends', () async {
      await arm(NavRouteData(points: _points, title: 'x'));
      var stopped = 0;
      await stopNavFromService(stopService: () async => stopped++, showRide: (_, _) async => fail('keine Fahrt'));
      expect(await FlutterForegroundTask.getData<bool>(key: kNavDataActive), isFalse);
      expect(navRouteFile(base.path).existsSync(), isFalse);
      expect(stopped, 1);
    });

    test('with a ride: the service stays and shows the ride again', () async {
      await arm(NavRouteData(points: _points, title: 'x'));
      await FlutterForegroundTask.saveData(key: kRideDataActive, value: true);
      final shown = <String>[];
      await stopNavFromService(
          stopService: () async => fail('die Fahrt braucht den Dienst'),
          showRide: (title, text) async => shown.add(title));
      expect(shown, [kRideNoticeTitle]);
    });
  });
}
