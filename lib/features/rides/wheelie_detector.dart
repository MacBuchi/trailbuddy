// Wheelie/Manual zur Laufzeit (#36, Konzept Airtime 2 und 9, Schritt 2b):
// dieselbe Regel wie `tool/airtime_measure.py`, nur fortlaufend statt über
// die ganze Datei. Reine Rechnung ohne Plattform — der Logger
// (`sensor_log.dart`) füttert sie im Isolate des Dienstes, der Test mit
// nachgebauten Reihen.
//
// Die Regel:
// - **Schwerkraft** = Mittel der Beschleunigung über [kWheelieLowpass],
//   alle 0,1 s ein Wert.
// - **Bezugslage** = Median der Schwerkraft der letzten
//   [kWheelieBaseWindow] in Fahrt (> [kWheelieMinKmh]) und nicht gekippt.
//   Das Skript nahm früher den Median der ganzen Fahrt; den kennt die App
//   erst am Ende. Vor [kWheelieWarmUp] Bezugswerten wird nichts erkannt.
// - **Wheelie** = Neigung gegen die Bezugslage ab [kWheelieTiltDeg], in
//   Fahrt; er endet unter [kWheelieReleaseDeg] (Hysterese: ein Wackeln an
//   der Schwelle macht nicht zwei Banner) oder unter dem Tempo. Er zählt
//   ab [kWheelieMinDuration].
// - **Länger als [kWheelieMaxDuration]** ist kein Wheelie, sondern eine
//   verrutschte Halterung: Die Bezugslage beginnt neu, gemeldet wird nichts.
//
// Das Tempo kommt aus dem GPS (1 s), die Länge = mittleres Tempo × Dauer.
import 'dart:math' as math;

const kWheelieTiltDeg = 15.0;
const kWheelieReleaseDeg = 10.0;
const kWheelieMinDuration = Duration(seconds: 1);
const kWheelieMaxDuration = Duration(seconds: 60);
const kWheelieMinKmh = 8.0;
const kWheelieLowpass = Duration(milliseconds: 500);
const kWheelieStep = Duration(milliseconds: 100);
const kWheelieBaseWindow = Duration(seconds: 60);
const kWheelieWarmUp = Duration(seconds: 10);

/// Ein erkannter Wheelie. [startUs] ist die Zeit des Sensors (µs seit
/// 1970) — dieselbe Achse wie die Zeilen der Rohdaten.
class WheelieEvent {
  const WheelieEvent(
      {required this.startUs, required this.duration, required this.lengthM, required this.maxTiltDeg});

  final int startUs;
  final Duration duration;
  final double lengthM;
  final double maxTiltDeg;
}

typedef _Vec = (double, double, double);

class WheelieDetector {
  final _window = <(int, _Vec)>[];
  double _sx = 0, _sy = 0, _sz = 0;
  int? _nextStepUs;

  final _base = <_Vec>[];
  _Vec? _baseUnit;
  int _sinceBase = 0;

  double? _speedMps;

  int? _startUs;
  int _lastTiltedUs = 0;
  double _maxTilt = 0;
  double _speedSum = 0;
  int _speedCount = 0;

  /// Läuft gerade einer? (für den Test)
  bool get inWheelie => _startUs != null;

  /// Die Bezugslage steht (für den Test).
  bool get ready => _baseUnit != null;

  void addSpeed(double mps) => _speedMps = mps.isFinite ? mps : null;

  /// Ein Wert des Beschleunigungssensors; gibt den Wheelie zurück, der mit
  /// ihm zu Ende ging.
  WheelieEvent? addAccel(int tUs, double x, double y, double z) {
    _window.add((tUs, (x, y, z)));
    _sx += x;
    _sy += y;
    _sz += z;
    while (tUs - _window.first.$1 > kWheelieLowpass.inMicroseconds) {
      final (_, (ox, oy, oz)) = _window.removeAt(0);
      _sx -= ox;
      _sy -= oy;
      _sz -= oz;
    }
    final next = _nextStepUs;
    if (next != null && tUs < next) return null;
    _nextStepUs = tUs + kWheelieStep.inMicroseconds;
    final n = _window.length;
    return _step(tUs, (_sx / n, _sy / n, _sz / n));
  }

  WheelieEvent? _step(int tUs, _Vec gravity) {
    final speed = _speedMps;
    final riding = speed != null && speed * 3.6 > kWheelieMinKmh;
    final unit = _unit(gravity);
    final base = _baseUnit;
    final tilt = base == null || unit == null ? 0.0 : _angleDeg(unit, base);

    final start = _startUs;
    if (start != null) {
      if (riding && tilt >= kWheelieReleaseDeg) {
        _lastTiltedUs = tUs;
        _maxTilt = math.max(_maxTilt, tilt);
        _speedSum += speed;
        _speedCount++;
        if (tUs - start > kWheelieMaxDuration.inMicroseconds) {
          // Verrutscht: neu lernen, nichts melden.
          _reset();
          _base.clear();
          _baseUnit = null;
        }
        return null;
      }
      final event = _finish(start);
      _reset();
      return event;
    }

    if (riding && base != null && tilt >= kWheelieTiltDeg) {
      _startUs = _lastTiltedUs = tUs;
      _maxTilt = tilt;
      _speedSum = speed;
      _speedCount = 1;
      return null;
    }
    if (riding && unit != null && tilt < kWheelieReleaseDeg) _learn(gravity);
    return null;
  }

  WheelieEvent? _finish(int start) {
    final duration = Duration(microseconds: _lastTiltedUs - start);
    if (duration < kWheelieMinDuration) return null;
    final meanSpeed = _speedCount == 0 ? 0.0 : _speedSum / _speedCount;
    return WheelieEvent(
        startUs: start,
        duration: duration,
        lengthM: meanSpeed * duration.inMicroseconds / 1e6,
        maxTiltDeg: _maxTilt);
  }

  void _reset() {
    _startUs = null;
    _maxTilt = 0;
    _speedSum = 0;
    _speedCount = 0;
  }

  void _learn(_Vec gravity) {
    final cap = kWheelieBaseWindow.inMicroseconds ~/ kWheelieStep.inMicroseconds;
    _base.add(gravity);
    if (_base.length > cap) _base.removeAt(0);
    final warm = kWheelieWarmUp.inMicroseconds ~/ kWheelieStep.inMicroseconds;
    if (_base.length < warm) return;
    // Einmal je Sekunde neu — 600 Werte sortieren kostet sonst je Schritt.
    if (_baseUnit != null && ++_sinceBase < 10) return;
    _sinceBase = 0;
    _baseUnit = _unit((
      _median([for (final v in _base) v.$1]),
      _median([for (final v in _base) v.$2]),
      _median([for (final v in _base) v.$3]),
    ));
  }
}

double _median(List<double> values) {
  values.sort();
  final m = values.length ~/ 2;
  return values.length.isOdd ? values[m] : (values[m - 1] + values[m]) / 2;
}

_Vec? _unit(_Vec v) {
  final n = math.sqrt(v.$1 * v.$1 + v.$2 * v.$2 + v.$3 * v.$3);
  return n == 0 ? null : (v.$1 / n, v.$2 / n, v.$3 / n);
}

double _angleDeg(_Vec a, _Vec b) {
  final dot = (a.$1 * b.$1 + a.$2 * b.$2 + a.$3 * b.$3).clamp(-1.0, 1.0);
  return math.acos(dot) * 180 / math.pi;
}
