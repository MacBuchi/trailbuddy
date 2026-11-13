// Die Taschenregel der App gegen das Werkzeug (#491): `synthetic()` aus
// `tool/pocket_measure.py`, Zeile für Zeile, mit demselben Rauschen
// (`Noise` aus `tool/sensor_fusion.py`) und ganzen Mikrosekunden — beide
// sehen dieselbe Fahrt. Die erwarteten Zahlen druckt
// `python3 tool/pocket_measure.py --fingerprint` (2026-11-13).
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/rides/pocket_watch.dart';
import 'package:trailbuddy/features/rides/sensor_fusion.dart';

/// Wie `Noise` im Werkzeug.
class _Noise {
  _Noise(int seed) : _x = (seed & 0xFFFFFFFF) == 0 ? 1 : seed & 0xFFFFFFFF;

  int _x;

  double uniform() {
    var x = _x;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _x = x;
    return x / 4294967296.0;
  }

  double gauss(double sigma) {
    final u = uniform() + uniform() + uniform() + uniform();
    return sigma * (u - 2.0) * math.sqrt(3.0);
  }
}

/// `synthetic()` des Werkzeugs, direkt in die Regel gespeist. GPS zuerst
/// (alle Punkte), dann die Sensoren — die Regel wartet ohnehin auf beide.
PocketWatch _ride({required bool pocket}) {
  final watch = PocketWatch();
  final noise = _Noise(491);
  // Die Achse beginnt mit dem ersten Beschleunigungswert (t = 0); GPS
  // davor gibt es hier nicht.
  watch.addAccel(0, 0, 0, 9.81 + noise.gauss(1.2));
  for (var s = 0; s <= 25 * 60; s++) {
    watch.addGps(s * 1000000, s >= 5 ? 6.0 : 0.0);
  }
  const n = 25 * 60 * 118;
  for (var i = 0; i < n; i++) {
    final tUs = (i * 1000000) ~/ 118;
    final t = tUs / 1e6;
    final rough = 600 <= t && t < 900;
    final pedalling = !rough;
    if (i > 0) {
      final vib = rough ? 6.0 : 1.2;
      watch.addAccel(tUs, 0, 0, 9.81 + noise.gauss(vib));
    }
    final (bx, by, bz) = rough
        ? (
            1.2 * math.sin(2 * math.pi * 0.7 * t),
            1.0 * math.sin(2 * math.pi * 1.1 * t + 1),
            0.8 * math.sin(2 * math.pi * 0.4 * t + 2)
          )
        : (0.1 * math.sin(2 * math.pi * 0.3 * t), 0.05 * math.sin(2 * math.pi * 0.5 * t), 0.0);
    final swing = pocket && pedalling ? 1.4 * math.sin(2 * math.pi * 1.3 * t) : 0.0;
    final gx = bx + swing + noise.gauss(0.3);
    final gy = by + noise.gauss(0.3);
    final gz = bz + noise.gauss(0.3);
    watch.addGyro(tUs, gx, gy, gz);
  }
  return watch;
}

void main() {
  // Die Zahlen des Werkzeugs: Fenster, Drehung, Vibration auf neun Stellen.
  const tool = {
    false: [
      (0, 10.0, 0.110848415, 1.177060342),
      (1, 20.0, 0.119409042, 1.203765380),
      (60, 610.0, 1.031992225, 5.683828236),
      (70, 710.0, 1.024166524, 5.592180872),
      (147, 1480.0, 0.113580007, 1.220078287),
    ],
    true: [
      (0, 10.0, 0.647441903, 1.177060342),
      (1, 20.0, 0.646756744, 1.203765380),
      (60, 610.0, 1.031992225, 5.683828236),
      (70, 710.0, 1.024166524, 5.592180872),
      (147, 1480.0, 0.662808569, 1.220078287),
    ],
  };

  for (final pocket in [false, true]) {
    test('${pocket ? 'Tasche' : 'am Rad'}: dieselben Fenster und Werte wie das Werkzeug', () {
      final watch = _ride(pocket: pocket);
      expect(watch.windows, hasLength(148));
      for (final (i, start, rotation, vibration) in tool[pocket]!) {
        final w = watch.windows[i];
        expect(w.startS, closeTo(start, 1e-9), reason: 'Fenster $i');
        expect(w.rotation, closeTo(rotation, 1e-9), reason: 'Drehung im Fenster $i');
        expect(w.vibration, closeTo(vibration, 1e-9), reason: 'Vibration im Fenster $i');
      }
      expect(watch.state, pocket);
    });
  }

  test('entschieden erst nach zwölf ruhigen Fenstern (120 s), nicht vorher', () {
    final watch = PocketWatch();
    // 115 s ruhig in der Tasche: elf Fenster in Fahrt, keine Entscheidung.
    void ride(int fromS, int toS) {
      for (var s = fromS; s <= toS; s++) {
        watch.addGps(s * 1000000, 6.0);
      }
      for (var i = fromS * 100; i < toS * 100; i++) {
        final t = i / 100;
        watch.addAccel(i * 10000, 0, 0, 9.81 + (i.isEven ? 0.5 : -0.5));
        watch.addGyro(i * 10000, 1.0 * math.sin(2 * math.pi * 1.3 * t), 0, 0);
      }
    }

    ride(0, 115);
    expect(watch.windows, hasLength(11));
    expect(watch.state, isNull);
    ride(115, 140);
    expect(watch.state, isTrue);
  });

  test('ruppige Fenster zählen nicht — eine Abfahrt am Lenker ist keine Tasche', () {
    final watch = PocketWatch();
    for (var s = 0; s <= 300; s++) {
      watch.addGps(s * 1000000, 6.0);
    }
    for (var i = 0; i < 300 * 100; i++) {
      final t = i / 100;
      // Starke Vibration (|a| springt ±6 m/s²) UND viel Drehung: ruppig.
      watch.addAccel(i * 10000, 0, 0, 9.81 + (i.isEven ? 6.0 : -6.0));
      watch.addGyro(i * 10000, 1.5 * math.sin(2 * math.pi * 0.7 * t), 0, 0);
    }
    expect(watch.windows, isNotEmpty);
    expect(watch.state, isNull, reason: 'kein ruhiges Fenster, keine Entscheidung');
  });

  test('in der Tasche bleiben nur Sprünge mit harter Landung', () {
    const w = WheelieEvent(startUs: 0, duration: Duration(seconds: 2), lengthM: 10, maxTiltDeg: 30);
    const s = StoppieEvent(startUs: 0, duration: Duration(seconds: 1), maxTiltDeg: 12, decel: 2, landingG: 4);
    const soft = JumpEvent(startUs: 0, duration: Duration(milliseconds: 200), landingG: 3.0, plausible: true, upright: true);
    const hard = JumpEvent(startUs: 0, duration: Duration(milliseconds: 200), landingG: 3.5, plausible: true, upright: true);
    expect(pocketKeeps(w), isFalse);
    expect(pocketKeeps(s), isFalse);
    expect(pocketKeeps(soft), isFalse);
    expect(pocketKeeps(hard), isTrue);
  });
}
