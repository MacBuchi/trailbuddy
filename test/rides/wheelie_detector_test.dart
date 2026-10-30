// Wheelie zur Laufzeit (#36): dieselbe Regel wie `tool/airtime_measure.py`,
// gegen nachgebaute Reihen — 100 Hz, Handy liegend, GPS je Sekunde.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/rides/wheelie_detector.dart';

const g = 9.80665;
const t0 = 1700000000000000;

/// Fährt [seconds] und gibt jeden erkannten Wheelie zurück. [tilt] sagt je
/// Zeitpunkt die Neigung um die x-Achse in Grad, [speed] das Tempo in m/s.
List<WheelieEvent> ride(WheelieDetector d, double seconds,
    {double Function(double t)? tilt, double Function(double t)? speed, double from = 0}) {
  final out = <WheelieEvent>[];
  for (var i = 0; i < seconds * 100; i++) {
    final t = i / 100;
    if (i % 100 == 0) d.addSpeed(speed?.call(t) ?? 5.0);
    final a = (tilt?.call(t) ?? 0) * math.pi / 180;
    final e = d.addAccel(t0 + ((from + t) * 1e6).round(), 0, g * math.sin(a), g * math.cos(a));
    if (e != null) out.add(e);
  }
  return out;
}

double wheelieAt(double t, double from, double to, [double deg = 25]) =>
    t >= from && t < to ? deg : 0;

void main() {
  test('ein Wheelie in Fahrt: Beginn, Dauer, Länge aus dem Tempo, größte Neigung', () {
    final d = WheelieDetector();
    final found = ride(d, 40, tilt: (t) => wheelieAt(t, 20, 23));
    expect(found, hasLength(1));
    final w = found.single;
    expect((w.startUs - t0) / 1e6, closeTo(20.2, 0.3), reason: 'Mittel über 0,5 s');
    expect(w.duration.inMilliseconds / 1000, closeTo(3.0, 0.3));
    expect(w.lengthM, closeTo(5.0 * w.duration.inMicroseconds / 1e6, 0.01));
    expect(w.maxTiltDeg, closeTo(25, 0.5));
    expect(d.inWheelie, isFalse);
  });

  test('vor der Bezugslage nichts — sie braucht 10 s Fahrt', () {
    final d = WheelieDetector();
    expect(ride(d, 15, tilt: (t) => wheelieAt(t, 4, 7)), isEmpty);
    expect(d.ready, isTrue);
  });

  test('zu kurz, zu flach oder im Stand: kein Wheelie', () {
    expect(ride(WheelieDetector(), 40, tilt: (t) => wheelieAt(t, 20, 20.6)), isEmpty,
        reason: 'unter 1 s');
    expect(ride(WheelieDetector(), 40, tilt: (t) => wheelieAt(t, 20, 25, 12)), isEmpty,
        reason: 'unter 15°');
    expect(
        ride(WheelieDetector(), 40,
            tilt: (t) => wheelieAt(t, 25, 30), speed: (t) => t >= 22 ? 0 : 5),
        isEmpty,
        reason: 'angelehnt an den Baum');
  });

  test('Wackeln um die Schwelle ist EIN Wheelie, kein zweites Banner', () {
    // 16° und 12° im Wechsel je halbe Sekunde: unter 15, aber über 10.
    final found = ride(WheelieDetector(), 40,
        tilt: (t) => t >= 20 && t < 24 ? ((t * 2).floor().isEven ? 16 : 12) : 0);
    expect(found, hasLength(1));
    expect(found.single.duration.inMilliseconds / 1000, greaterThan(3.0));
  });

  test('länger als eine Minute ist eine verrutschte Halterung: neu lernen, nichts melden', () {
    final d = WheelieDetector();
    // Ab 20 s liegt das Handy um 25° anders und bleibt so.
    final found = ride(d, 150, tilt: (t) => t >= 20 ? 25 : 0);
    expect(found, isEmpty);
    expect(d.inWheelie, isFalse);
    expect(d.ready, isTrue, reason: 'die neue Lage ist die Bezugslage');
    // Ein Wheelie gegen die neue Lage zählt wieder.
    final after = ride(d, 40, from: 150, tilt: (t) => t >= 20 && t < 23 ? 50 : 25);
    expect(after, hasLength(1));
  });
}
