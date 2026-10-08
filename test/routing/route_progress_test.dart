import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/routing/route_progress.dart';

// Erfundene Lage (einstellige Breite), Meter über latlong2 abgesetzt.
const _origin = LatLng(5, 5);
const _d = Distance();

/// [m] Meter nach Osten und [n] Meter nach Norden vom Ursprung.
LatLng _at(double m, [double n = 0]) => _d.offset(_d.offset(_origin, m, 90), n, 0);

void main() {
  group('NavRoute', () {
    test('lengths, points along and the bearing of the line', () {
      final r = NavRoute.of([_at(0), _at(1000), _at(1000, 500)])!;
      expect(r.lengthM, closeTo(1500, 5)); // Haversine gegen Vincenty: ein Promille
      expect(r.pointAt(500).longitude, closeTo(_at(500).longitude, 1e-5));
      expect(r.bearingAt(200), closeTo(90, 0.5));
      expect(r.bearingAt(1200), closeTo(0, 0.5));
      expect(r.isLoop, isFalse);
      // Ein Anschluss von 10 m zurück dreht die Richtung nicht um.
      final hook = NavRoute.of([_at(10), _at(0), _at(500)])!;
      expect(hook.bearingAt(0), closeTo(90, 0.5));
      // Am Ende das letzte Stück.
      expect(r.bearingAt(1500), closeTo(0, 0.5));
    });

    test('splits into the ridden part and the rest, meeting at the place', () {
      final r = NavRoute.of([_at(0), _at(500), _at(1000)])!;
      final (done, rest) = r.splitAt(700);
      expect(done, hasLength(3));
      expect(rest, hasLength(2));
      expect(done.last, rest.first);
      expect(rest.last, _at(1000));
      final (none, all) = r.splitAt(0);
      expect(none, hasLength(1));
      expect(all, hasLength(4));
    });

    test('no line without length', () {
      expect(NavRoute.of([_at(0)]), isNull);
      expect(NavRoute.of([_at(0), _at(0)]), isNull);
    });
  });

  group('routeProgress', () {
    test('projects onto the line and measures the distance to it', () {
      final r = NavRoute.of([_at(0), _at(1000)])!;
      final fix = routeProgress(r, _at(400, 20));
      expect(fix.alongM, closeTo(400, 1));
      expect(fix.offM, closeTo(20, 0.5));
    });

    test('out and back on the same way: the window keeps the way out', () {
      // 1 km hin und dieselben Punkte zurück — 5 m daneben liegt man auf
      // beiden Richtungen gleich nah.
      final r = NavRoute.of([_at(0), _at(500), _at(1000), _at(500, 1), _at(0, 1)])!;
      final out = routeProgress(r, _at(300, 3), lastAlongM: 200);
      expect(out.alongM, closeTo(300, 2));
      // Kurz vor der Wende, auf dem Rückweg: Der Stand von dort zählt.
      final back = routeProgress(r, _at(300, 3), lastAlongM: 1650);
      expect(back.alongM, closeTo(1700, 3));
    });

    test('searches the whole line once the window finds nothing near', () {
      final r = NavRoute.of([_at(0), _at(3000)])!;
      // Abgekürzt: 2 km weiter vorne, weit hinter dem Fenster.
      final fix = routeProgress(r, _at(2500, 5), lastAlongM: 100);
      expect(fix.alongM, closeTo(2500, 5));
      expect(fix.offM, closeTo(5, 0.5));
    });

    test('off the route: the distance is to the whole line, the place stays', () {
      // Ein Haken: Hinweg nach Osten, zurück 100 m nördlich.
      final r = NavRoute.of([_at(0), _at(1000), _at(1000, 100), _at(0, 100)])!;
      // 60 m nördlich vom Hinweg, 40 m südlich vom Rückweg — abseits von
      // beiden. Der Stand bleibt auf dem Hinweg, der Abstand ist 40 m.
      final fix = routeProgress(r, _at(300, 60), lastAlongM: 300);
      expect(fix.offM, closeTo(40, 0.5));
      expect(fix.alongM, closeTo(300, 1));
    });
  });

  group('NavTracker', () {
    test('remaining distance, and off route only after two fixes', () {
      final t = NavTracker(NavRoute.of([_at(0), _at(2000)])!);
      var s = t.update(_at(500, 2));
      expect(s.remainingM, closeTo(1500, 2));
      expect(s.offRoute, isFalse);
      s = t.update(_at(600, 50));
      expect(s.offM, closeTo(50, 0.5));
      expect(s.offRoute, isFalse, reason: 'ein einzelner Ausreißer ist keine Abweichung');
      s = t.update(_at(650, 50));
      expect(s.offRoute, isTrue);
      // Der Pfeil zeigt auf die Linie voraus.
      expect(s.rejoin.latitude, closeTo(_at(700).latitude, 1e-5));
      s = t.update(_at(700, 3));
      expect(s.offRoute, isFalse);
    });

    test('heading: GPS course only when moving, otherwise the line', () {
      final t = NavTracker(NavRoute.of([_at(0), _at(2000)])!);
      expect(t.update(_at(100), headingDeg: 200, speedMps: 0.5).headingDeg, closeTo(90, 0.5));
      expect(t.update(_at(120), headingDeg: 80, speedMps: 5).headingDeg, 80);
      // Im Stand bleibt der letzte Kurs, auch wenn das GPS etwas anderes sagt.
      expect(t.update(_at(121), headingDeg: 270, speedMps: 0.2).headingDeg, 80);
      expect(t.update(_at(122), headingDeg: -1, speedMps: 4).headingDeg, 80);
    });

    test('arrives at the end of a line', () {
      final t = NavTracker(NavRoute.of([_at(0), _at(1000)])!);
      expect(t.update(_at(900)).arrived, isFalse);
      expect(t.update(_at(985, 4)).arrived, isTrue);
      // Bleibt angekommen, auch wenn man am Ziel herumfährt.
      expect(t.update(_at(940, 4)).arrived, isTrue);
    });

    test('a loop does not arrive at its start', () {
      final loop = NavRoute.of([_at(0), _at(1000), _at(1000, 1000), _at(0, 1000), _at(0, 10)])!;
      expect(loop.isLoop, isTrue);
      final t = NavTracker(loop);
      expect(t.update(_at(0, 2)).arrived, isFalse);
      expect(t.update(_at(500)).arrived, isFalse);
      expect(t.update(_at(1000, 500)).arrived, isFalse);
      expect(t.update(_at(500, 1000)).arrived, isFalse);
      expect(t.update(_at(0, 600)).arrived, isFalse);
      expect(t.update(_at(0, 20)).arrived, isTrue);
    });
  });

  test('climbAfter counts only what is still ahead', () {
    final dist = <double>[0, 100, 200, 300, 400];
    final ele = <double>[100, 150, 120, 180, 180];
    expect(climbAfter(dist, ele, 0), closeTo(110, 0.01));
    // Ab 250 m: von 150 m Höhe (zwischen 120 und 180) auf 180 m.
    expect(climbAfter(dist, ele, 250), closeTo(30, 0.01));
    expect(climbAfter(dist, ele, 400), 0);
    expect(climbAfter(null, null, 0), isNull);
  });

  test('followCenter puts the position a sixth of the height ahead', () {
    final c = followCenter(_origin, 0, 16, 600);
    expect(c.longitude, closeTo(_origin.longitude, 1e-9));
    // 100 px bei Zoom 16 auf Breite 5: ≈ 2,38 m je Pixel.
    expect(_d(_origin, c), closeTo(100 * 156543.03392 * 0.99619 / 65536, 0.5));
    expect(c.latitude, greaterThan(_origin.latitude));
  });
}
