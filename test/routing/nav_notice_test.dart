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
import 'package:flutter/widgets.dart' show Locale;
import 'package:trailbuddy/core/settings.dart' show kLanguageSettingKey;
import 'package:trailbuddy/l10n/l10n.dart' show chosenAppLocale;
import 'package:trailbuddy/features/rides/ride_task_handler.dart';
import 'package:trailbuddy/features/rides/sensor_fusion.dart';
import 'package:trailbuddy/features/rides/trail_values.dart';
import 'package:trailbuddy/features/routing/nav_notice.dart';
import 'package:trailbuddy/features/routing/route_progress.dart';
import '../fakes/l10n_de.dart';

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
    // Die Texte des Dienstes folgen der Wahl im Profil (#209); hier hat
    // sie „Deutsch" gesagt — der Dienst liest sie je Takt nach.
    SharedPreferences.setMockInitialValues({kLanguageSettingKey: 'de'});
    chosenAppLocale = const Locale('de');
    addTearDown(() => chosenAppLocale = null);
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

    test('Fassung 2 trägt die Abschnitte; eine Datei der Fassung 1 liest sich ohne (#312)', () {
      final sections = NavSections([
        const NavTrailSection(startM: 300, endM: 1100, trailId: 't1', name: 'Rosskopf Süd', grade: 2, lossM: 420),
      ]);
      final back = NavRouteData.decode(NavRouteData(points: _points, title: 'x', sections: sections).encode())!;
      expect(back.sections.trails, hasLength(1));
      expect(back.sections.trails.single.name, 'Rosskopf Süd');
      expect(back.sections.trails.single.endM, 1100);
      expect(back.sections.trails.single.lossM, 420);
      final v1 = NavRouteData.decode('{"v":1,"title":"x","pts":[[47.0,11.0],[47.0,11.1]]}')!;
      expect(v1.sections.isEmpty, isTrue);
      // Ein kaputter Abschnitt fällt weg, die Route bleibt.
      final odd = NavRouteData.decode('{"v":2,"title":"x","pts":[[47.0,11.0],[47.0,11.1]],"secs":[[5,2,"t","n"]]}')!;
      expect(odd.sections.isEmpty, isTrue);
    });

    test('anything odd reads as no route — half a route would be worse', () {
      expect(NavRouteData.decode('kaputt'), isNull);
      expect(NavRouteData.decode('{"v":3,"pts":[[47,11],[47,11.1]]}'), isNull);
      expect(NavRouteData.decode('{"v":1,"pts":[[47.0,11.0]]}'), isNull);
    });
  });

  group('navNotice (zwei Zeilen, #312 N3)', () {
    NavState state({double along = 0, double remaining = 12400, double off = 4, bool offRoute = false, bool arrived = false}) =>
        NavState(
            alongM: along,
            remainingM: remaining,
            offM: off,
            offRoute: offRoute,
            arrived: arrived,
            headingDeg: 0,
            position: _points.first,
            rejoin: _points.first,
            moving: true);
    const trail = NavTrailSection(startM: 2400, endM: 4200, trailId: 't', name: 'Rosskopf Süd', grade: 2);

    test('Anfahrt: oben bis zum Trailkopf, unten Rampe und Route', () {
      final n = navNotice(
          l10nDe,
          state(),
          const NavPhase(
              kind: NavPhaseKind.approach, section: trail, distM: 2400, climbM: 310.4, ramp: (grade: 0.14, inM: 1100)),
          recording: false);
      expect(n.title, '2,4 km · ↑310 hm bis Rosskopf Süd');
      expect(n.text, 'Rampe 14 % in 1,1 km · auf der Route');
      // Ohne Profil nur km; ohne Trail bis zum Ziel.
      expect(navNotice(l10nDe, state(), const NavPhase(kind: NavPhaseKind.approach, section: trail, distM: 800),
              recording: false)
          .title, '800 m bis Rosskopf Süd');
      expect(navNotice(l10nDe, state(), const NavPhase(kind: NavPhaseKind.approach, distM: 800, climbM: 40),
              recording: false)
          .title, '800 m · ↑40 hm bis zum Ziel');
    });

    test('auf dem Trail, am Kopf, abseits, mit Aufzeichnung, angekommen', () {
      expect(
          navNotice(l10nDe, state(along: 2400),
                  const NavPhase(kind: NavPhaseKind.onTrail, section: trail, distM: 1800, lossM: 240), recording: false)
              .title,
          'Rosskopf Süd · noch 1,8 km · ↓240 hm');
      expect(navNotice(l10nDe, state(), const NavPhase(kind: NavPhaseKind.atHead, section: trail, distM: 20),
              recording: false)
          .title, 'Am Trailkopf · Rosskopf Süd');
      final off = navNotice(
          l10nDe,
          state(off: 120, offRoute: true),
          const NavPhase(kind: NavPhaseKind.approach, section: trail, distM: 2400, ramp: (grade: 0.14, inM: 1100)),
          recording: true);
      expect(off.text, '120 m neben der Route · Fahrt wird aufgezeichnet',
          reason: 'abseits zählt keine Rampe; die Aufzeichnung steht immer da');
      final arrived =
          navNotice(l10nDe, state(arrived: true), const NavPhase(kind: NavPhaseKind.arrived, distM: 0), recording: false);
      expect(arrived.title, 'Angekommen');
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
      expect(shown.single, '758 m bis zum Ziel | auf der Route');
      // Der Stand liegt in der Brücke — eine neu gestartete App geht dort weiter.
      expect(await FlutterForegroundTask.getData<double>(key: kNavDataAlong), closeTo(758, 5));
    });

    test('the same line again (heights arrived) keeps the stand; a new line starts over', () async {
      // Hin und zurück auf derselben Linie: Ohne gemerkten Stand fände
      // die Suche auf dem Rückweg die Hinfahrt.
      final back = [..._points, for (var i = 19; i >= 0; i--) LatLng(_lat, _lng(i))];
      await arm(NavRouteData(points: back, title: 'hin und zurück'));
      final shown = <String>[];
      Future<void> show(String title, String text) async => shown.add(title);
      for (final i in [10, 18, 20]) {
        await navTick(fix: () async => _at(_lat, _lng(i)), recording: false, show: show);
      }
      // Jetzt auf dem Rückweg bei 18: 2 Abschnitte zurück gefahren.
      await arm(NavRouteData(points: back, title: 'hin und zurück', climbDistM: [0, 3000], climbEleM: [500, 600]));
      await navTick(fix: () async => _at(_lat, _lng(18)), recording: false, show: show);
      expect(shown.last, startsWith('1,4 km'), reason: 'Stand blieb auf dem Rückweg');
      expect(shown.last, contains('hm'), reason: 'das Profil kam dazu');

      await arm(NavRouteData(points: _points, title: 'neu'));
      await navTick(fix: () async => _at(_lat, _lng(18)), recording: false, show: show);
      expect(shown.last, startsWith('152 m'));
    });

    test('Fassung 2: the notice names the trail ahead, then the trail itself (#312 N3)', () async {
      await arm(NavRouteData(
          points: _points,
          title: 'Hausrunde',
          sections: NavSections([const NavTrailSection(startM: 600, endM: 1200, trailId: 't', name: 'Rosskopf Süd')])));
      final shown = <String>[];
      Future<void> show(String title, String text) async => shown.add('$title | $text');
      await navTick(fix: () async => _at(_lat, _lng(2)), recording: true, show: show);
      expect(shown.last, startsWith('448 m bis Rosskopf Süd | auf der Route · Fahrt wird aufgezeichnet'));
      await navTick(fix: () async => _at(_lat, _lng(10)), recording: false, show: show);
      expect(shown.last, startsWith('Rosskopf Süd · noch 442 m | auf der Route'));
    });

    test('#36 Schritt 5: on the trail the notice carries the values since entering it', () async {
      await arm(NavRouteData(
          points: _points,
          title: 'Hausrunde',
          sections: NavSections([const NavTrailSection(startM: 600, endM: 1200, trailId: 't', name: 'Rosskopf Süd')])));
      final shown = <String>[];
      Future<void> show(String title, String text) async => shown.add(text);
      final enter = DateTime.utc(2026, 10, 31, 10);
      var log = AirtimeLog.empty.withEvent(JumpEvent(
          startUs: enter.microsecondsSinceEpoch - 1000000,
          duration: const Duration(seconds: 1),
          landingG: 2,
          upright: true,
          plausible: true));
      Future<void> tick(int i, DateTime at) =>
          navTick(fix: () async => _at(_lat, _lng(i)), recording: false, show: show, now: () => at, events: () => log);
      await tick(2, enter.subtract(const Duration(minutes: 1)));
      expect(shown.last, 'auf der Route', reason: 'vor dem Trail keine Werte');
      await tick(9, enter);
      expect(shown.last, 'auf der Route', reason: 'der Sprung kam vor der Einfahrt');
      log = log.withEvent(JumpEvent(
          startUs: enter.microsecondsSinceEpoch + 5000000,
          duration: const Duration(milliseconds: 700),
          landingG: 3.1,
          upright: true,
          plausible: true));
      await tick(10, enter.add(const Duration(seconds: 10)));
      expect(shown.last, 'auf der Route · Air 0,7 s (1×) · 3,1 G');
      await tick(18, enter.add(const Duration(seconds: 40)));
      expect(shown.last, 'auf der Route', reason: 'hinter dem Trail wieder ohne');
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
      expect(shown, [l10nDe.rideNoticeTitle]);
    });

    test('reads the language from the profile before it speaks (#209)', () async {
      await arm(NavRouteData(points: _points, title: 'x'));
      await FlutterForegroundTask.saveData(key: kRideDataActive, value: true);
      // Die App hat auf Englisch umgestellt, das Isolate hatte noch Deutsch.
      await (await SharedPreferences.getInstance()).setString(kLanguageSettingKey, 'en');
      final shown = <String>[];
      await stopNavFromService(
          stopService: () async => fail('die Fahrt braucht den Dienst'),
          showRide: (title, text) async => shown.add(title));
      expect(shown, ['Recording a ride']);
    });
  });
}
