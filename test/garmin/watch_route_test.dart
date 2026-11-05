// Die Nachrichten an die Uhr (#449 G2, docs/konzept-garmin.md 2): dieselbe
// Form wie `tool/garmin_route.py` und `garmin/source/NavRoute.mc`, Stücke,
// die sich wieder zusammensetzen, höchstens 2000 Punkte, die Trails als
// Abschnitte, die Bestwerte der Erkennung.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/garmin/garmin_bridge.dart';
import 'package:trailbuddy/features/garmin/garmin_bridge_io.dart' show kGarminChannel;
import 'package:trailbuddy/features/garmin/watch_route.dart';
import 'package:trailbuddy/features/offline_areas/height_tiles.dart' show hysteresisClimb, kClimbHysteresisM;
import 'package:trailbuddy/features/rides/sensor_fusion.dart';
import 'package:trailbuddy/features/rides/trail_values.dart';
import 'package:trailbuddy/features/routing/nav_sections.dart';
import 'package:trailbuddy/features/trails/trail_elevation.dart';

// Erfunden, am Äquator (nie echte Koordinaten im Repo).
const _line = [LatLng(0, 0), LatLng(0.0003, 0.0002), LatLng(0.0006, 0), LatLng(0.0009, 0.0002)];

NavTrailSection _trail(double from, double to, {int? grade, bool uphill = false, bool beyond = false, String name = 'X'}) =>
    NavTrailSection(startM: from, endM: to, trailId: name, name: name, grade: grade, uphill: uphill, beyondRoute: beyond);

void main() {
  test('dieselbe Kodierung wie tool/garmin_route.py (encode, gerechnet 2026-11-04)', () {
    // python3 -c "import garmin_route as g; print(g.encode([(0,0),(0.0003,0.0002),
    //   (0.0006,0),(0.0009,0.0002)], ele=[700.2,712.8,705.1,690.3], sections=[[1,3,2,'X']]))"
    final heights = ElevationProfile.of(_line, [700.2, 712.8, 705.1, 690.3])!;
    final route = watchRouteOf(_line, NavSections([_trail(36, 110, grade: 2)]), heights: heights)!;
    final json = route.toJson();
    expect(json['pts'], [0, 0, 30, 20, 30, -20, 30, 20]);
    expect(json['ele'], [700, 713, 705, 690]);
    expect(json['sec'], [
      [1, 3, 2, 'X']
    ]);
    expect(json['v'], kWatchProtocol);
    expect(json['rel'], false);
  });

  test('Kuppen auf gerader Linie: die Uhr zählt dieselben Höhenmeter wie das Handy (#449, 2026-11-05)', () {
    // Gerade nach Norden, 2 km, alle 10 m ein Punkt — Douglas-Peucker
    // behielte nur Anfang und Ende. Drei Kuppen zu 60 m, dazwischen Rauschen
    // unter der Hysterese.
    final line = [for (var i = 0; i <= 200; i++) LatLng(i * 0.00009, 0)];
    final ele = [
      for (var i = 0; i <= 200; i++) 500 + 60 * math.sin(i / 200 * 3 * math.pi).abs() + (i.isEven ? 2.0 : 0.0)
    ];
    final heights = ElevationProfile.of(line, ele)!;
    final route = watchRouteOf(line, NavSections(const []), heights: heights)!;
    final (phone, _) = hysteresisClimb(heights.eleM, kClimbHysteresisM);
    // So zählt die Uhr (`climbAt` in NavRoute.mc): dieselbe Hysterese über
    // die Höhen IHRER Punkte.
    final (watch, _) = hysteresisClimb([for (final h in route.ele!) h.toDouble()], kClimbHysteresisM);
    expect(phone, closeTo(180, 3));
    expect(watch, closeTo(phone, 3), reason: 'Gipfel und Senken bleiben beim Vereinfachen stehen');
    expect(route.pointCount, lessThan(20), reason: 'nur die Wendepunkte kommen dazu, nicht jede Zacke');
  });

  test('die Stücke setzen sich in ihrer Reihenfolge wieder zur Route zusammen', () {
    final line = [for (var i = 0; i < 700; i++) LatLng(i * 0.0003, i.isEven ? 0 : 0.0003)];
    final heights = ElevationProfile.of(line, [for (var i = 0; i < 700; i++) 500.0 + i])!;
    final route = watchRouteOf(line, NavSections([_trail(100, 900, grade: 1)]), heights: heights)!;
    expect(route.pointCount, 700, reason: 'jede Ecke ist 30 m weit — nichts zu vereinfachen');
    final parts = route.parts(maxInts: 300);
    expect(parts.length, greaterThan(1));
    final pts = <int>[], ele = <int>[];
    for (final (i, p) in parts.indexed) {
      expect(p['t'], kWatchRoutePart);
      expect(p['id'], route.id);
      expect(p['p'], i);
      expect(p['n'], parts.length);
      expect((p['pts'] as List).length + (p['ele'] as List).length, lessThanOrEqualTo(300));
      expect(p.containsKey('sec'), i == 0, reason: 'Kopf und Trails nur im ersten Stück');
      pts.addAll((p['pts'] as List).cast());
      ele.addAll((p['ele'] as List).cast());
    }
    expect(pts, route.pts);
    expect(ele, route.ele);
  });

  test('mehr als 2000 Punkte: stärker vereinfacht, bis es passt', () {
    // Zickzack mit 8 m Ausschlag: Bei 5 m bliebe jeder Punkt.
    final line = [for (var i = 0; i < 5000; i++) LatLng(i * 0.0001, i.isEven ? 0 : 0.0001)];
    final route = watchRouteOf(line, NavSections.none)!;
    expect(route.pointCount, lessThanOrEqualTo(kWatchMaxPoints));
    expect(route.pointCount, greaterThan(1));
    final first = route.pts.take(2).toList();
    expect(first, [0, 0], reason: 'Anfang bleibt');
  });

  test('Abschnitte: Grad 0–3 (ab S3 schwarz), Uphill und ohne Grad -1, der Trail hinter dem Ende fehlt', () {
    final route = watchRouteOf(
        _line,
        NavSections([
          _trail(0, 36, grade: 5, name: 'A'),
          _trail(36, 72, uphill: true, grade: 1, name: 'B'),
          _trail(72, 110, name: 'Ein sehr langer Name für einen Trail'),
          _trail(110, 110, grade: 0, beyond: true, name: 'Kopf'),
        ]))!;
    expect(route.sec.map((s) => s[2]), [3, -1, -1]);
    expect(route.sec.map((s) => s[3]), ['A', 'B', 'Ein sehr langer Name fü…']);
    expect(route.sec.map((s) => [s[0], s[1]]), [
      [0, 1],
      [1, 2],
      [2, 3]
    ]);
    expect(route.ele, isNull, reason: 'ohne Höhen kein `ele`');
    expect(route.toJson().containsKey('ele'), isFalse);
  });

  test('die Kennung hängt nur an den Zahlen der Linie', () {
    final a = watchRouteOf(_line, NavSections.none)!;
    final b = watchRouteOf(_line, NavSections([_trail(0, 50, grade: 1)]))!;
    final c = watchRouteOf(_line.reversed.toList(), NavSections.none)!;
    expect(a.id, b.id);
    expect(a.id, isNot(c.id));
    expect(a.id, matches(RegExp(r'^[0-9a-f]{8}$')));
  });

  test('Bestwerte: nur Zahlen, ohne „War keiner" und ohne unplausible Sprünge', () {
    expect(watchBestsOf(AirtimeLog.empty), isNull);
    const w1 = WheelieEvent(startUs: 1, duration: Duration(seconds: 3), lengthM: 18.4, maxTiltDeg: 31);
    const w2 = WheelieEvent(startUs: 2, duration: Duration(seconds: 5), lengthM: 40, maxTiltDeg: 55);
    const j1 = JumpEvent(startUs: 3, duration: Duration(milliseconds: 620), landingG: 3, upright: true, plausible: true);
    const j2 = JumpEvent(startUs: 4, duration: Duration(milliseconds: 1900), landingG: 1, upright: true, plausible: false);
    final log = const AirtimeLog(events: [w1, w2, j1, j2]).withAnswer(w2, yes: false);
    expect(watchBestsOf(log), {'t': kWatchBests, 'jn': 1, 'ja': 620, 'wn': 1, 'wl': 18, 'wa': 31, 'sn': 0});
  });

  test('die Antwort der Uhr: nur „gespeichert" mit Kennung', () {
    expect(watchStoredId({'t': 'ok', 'id': 'abc'}), 'abc');
    expect(watchStoredId({'t': 'b', 'id': 'abc'}), isNull);
    expect(watchStoredId('ok'), isNull);
  });

  test('der Schalter steht nur mit verbundener Uhr, auf der unsere App nicht sicher fehlt', () {
    expect(WatchStatus.fromChannel({'connect': false}).canShow, isFalse);
    expect(WatchStatus.fromChannel({'connect': true}).canShow, isFalse);
    expect(WatchStatus.fromChannel({'connect': true, 'device': 'fēnix 5', 'app': 'installed'}).canShow, isTrue);
    expect(WatchStatus.fromChannel({'connect': true, 'device': 'fēnix 5', 'app': 'unknown'}).canShow, isTrue);
    expect(WatchStatus.fromChannel({'connect': true, 'device': 'fēnix 5', 'app': 'not_installed'}).canShow, isFalse);
    expect(WatchStatus.fromChannel(null).canShow, isFalse);
  });

  test('App-Kennung, Kanal und Grenzen stehen gleich in Uhr, Kotlin und Dart', () {
    final manifest = File('garmin/manifest.xml').readAsStringSync();
    expect(manifest, contains('id="$kWatchAppId"'));
    final kotlin = File('android/app/src/main/kotlin/de/mcbuchi/trailbuddy/GarminBridge.kt').readAsStringSync();
    expect(kotlin, contains('"$kGarminChannel"'));
    final app = File('garmin/source/PhoneRoute.mc').readAsStringSync();
    expect(app, contains('PROTOCOL = $kWatchProtocol'));
    expect(manifest, contains('<iq:uses-permission id="Communications"/>'));
  });

  test('#449: „hallo", Frage und Öffnen sprechen Uhr, Kotlin und Dart gleich', () {
    final watch = File('garmin/source/TrailBuddyApp.mc').readAsStringSync();
    expect(watch, contains('"t" => "$kWatchHello"'));
    expect(watch, contains('"$kWatchQuery".equals(t)'));
    final kotlin = File('android/app/src/main/kotlin/de/mcbuchi/trailbuddy/GarminBridge.kt').readAsStringSync();
    expect(kotlin, contains('"open" ->'));
    // Kotlin reicht den Namen aus `IQDeviceStatus` weiter, Dart hört auf CONNECTED.
    expect(kotlin, contains('invokeMethod("device", status.name)'));
    final io = File('lib/features/garmin/garmin_bridge_io.dart').readAsStringSync();
    expect(io, contains("call.method == 'device' && call.arguments == 'CONNECTED'"));
    expect(watchQuery, {'t': 'q'});
    expect(watchHelloOf({'t': 'hi', 'id': 'ab12', 'v': 1}), (hello: true, id: 'ab12'));
    expect(watchHelloOf({'t': 'hi', 'v': 1}), (hello: true, id: null));
    expect(watchHelloOf({'t': 'ok', 'id': 'ab12'}).hello, isFalse);
    expect(WatchOpen.fromChannel('PROMPT_SHOWN_ON_DEVICE'), WatchOpen.prompted);
    expect(WatchOpen.fromChannel('APP_IS_ALREADY_RUNNING'), WatchOpen.running);
    expect(WatchOpen.fromChannel('APP_IS_NOT_INSTALLED'), WatchOpen.notInstalled);
    expect(WatchOpen.fromChannel('TIMEOUT'), WatchOpen.unknown);
  });
}
