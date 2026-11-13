// Steckt das Handy in der Hosentasche? (#491, `docs/recherche-sensorfusion.md`
// Abschnitt 11) — die Regel aus `tool/pocket_measure.py` in Dart, Zeile für
// Zeile, damit App und Werkzeug dieselbe Fahrt gleich einordnen.
//
// - je 10 s in Fahrt (> 8 km/h an beiden Enden, mehr als 100 Werte je
//   Sensor): Vibration = Streuung von |a|, Drehung = Effektivwert des
//   Kreisels nach 0,15 s Tiefpass;
// - ruhig = Vibration unter 4 m/s² (auf ruppigen Abfahrten dreht sich auch
//   das Rad selbst);
// - Tasche = Median der Drehung über die letzten zwölf ruhigen Fenster über
//   0,35 rad/s.
//
// Reine Rechnung, im Isolate des Dienstes neben der Fusion
// (`sensor_log.dart`). Die Fusion selbst bleibt unberührt (bitgleich zum
// Werkzeug); was in der Tasche gilt, entscheidet [pocketKeeps].
import 'dart:math' as math;

import 'sensor_fusion.dart';

const kPocketWindowS = 10.0;
const kPocketRidingKmh = 8.0;
const kPocketGyroLowPassS = 0.15;
const kPocketCalmVibration = 4.0;
const kPocketCalmWindows = 12;
const kPocketRotationRad = 0.35;

/// In der Tasche zählt ein Flug nur mit dieser Landung (Recherche 11: behält
/// alle sechs bestätigten Sprünge vom Lenker, verwirft alle „War keiner" aus
/// der Tasche).
const kPocketLandingG = 3.5;

/// Bleibt ein Ereignis, wenn das Handy in der Tasche steckt? Wheelie und
/// Stoppie nie — in der Tasche gibt es keine Achsen des Rads, das ist das
/// Bein. Ein Sprung nur mit harter Landung.
bool pocketKeeps(FusionEvent event) => switch (event) {
      WheelieEvent() || StoppieEvent() => false,
      JumpEvent(:final landingG) => landingG >= kPocketLandingG,
    };

/// Ein Fenster in Fahrt: Beginn (s ab dem ersten Beschleunigungswert),
/// Drehung (rad/s), Vibration (m/s²).
typedef PocketWindow = ({double startS, double rotation, double vibration});

/// Ordnet eine laufende Fahrt ein. Die Werte kommen je Sensor in zeitlicher
/// Reihenfolge, die Sensoren untereinander in Schüben — ein Fenster wird
/// erst abgeschlossen, wenn beide Sensoren und ein GPS-Punkt hinter seinem
/// Ende liegen.
class PocketWatch {
  double? _t0;
  double _start = 0.0;
  final _acc = <(double, double)>[]; // (t, |a|)
  final _gyro = <(double, double, double, double)>[];
  final _fixes = <(double, double)>[]; // (t, m/s)
  double _accLast = double.negativeInfinity, _gyroLast = double.negativeInfinity;
  final _calm = <double>[];

  /// Alle Fenster in Fahrt bisher — für den Test und das Werkzeug.
  final windows = <PocketWindow>[];

  /// `true` Tasche, `false` am Rad, `null` noch nicht entschieden (weniger
  /// als [kPocketCalmWindows] ruhige Fenster).
  bool? state;

  void addAccel(int tUs, double x, double y, double z) {
    final t = _time(tUs, first: true);
    if (t == null) return;
    _acc.add((t, math.sqrt(x * x + y * y + z * z)));
    _accLast = t;
    _close();
  }

  void addGyro(int tUs, double x, double y, double z) {
    final t = _time(tUs);
    if (t == null) return;
    _gyro.add((t, x, y, z));
    _gyroLast = t;
    _close();
  }

  void addGps(int tUs, double speedMps) {
    final t0 = _t0;
    if (t0 == null) {
      _early.add((tUs / 1e6, speedMps));
      return;
    }
    _fixes.add((tUs / 1e6 - t0, speedMps));
    _close();
  }

  /// GPS vor dem ersten Beschleunigungswert, in Sekunden seit 1970 — erst
  /// mit ihm steht die Achse.
  final _early = <(double, double)>[];

  /// Die Zeit relativ zum ersten Beschleunigungswert — wie `read` im
  /// Werkzeug. Kreisel davor zählt nicht.
  double? _time(int tUs, {bool first = false}) {
    final t = tUs / 1e6;
    var t0 = _t0;
    if (t0 == null) {
      if (!first) return null;
      _t0 = t0 = t;
      _fixes.addAll([for (final (ft, v) in _early) (ft - t0, v)]);
      _early.clear();
    }
    return t - t0;
  }

  /// Das Tempo zur Zeit [t] in km/h: der letzte Punkt davor (oder genau
  /// dann), vor dem ersten der erste — `Speed.at` im Werkzeug.
  double _kmh(double t) {
    if (_fixes.isEmpty) return 0.0;
    var i = 0;
    while (i + 1 < _fixes.length && _fixes[i + 1].$1 <= t) {
      i++;
    }
    if (_fixes[i].$1 > t) i = 0;
    return _fixes[i].$2 * 3.6;
  }

  void _close() {
    while (true) {
      final end = _start + kPocketWindowS;
      // Beide Sensoren hinter dem Ende, und ein GPS-Punkt danach: Später
      // kommt nichts mehr in dieses Fenster, und das Tempo am Ende steht.
      if (_accLast < end || _gyroLast < end) return;
      if (_fixes.isEmpty || _fixes.last.$1 <= end) return;
      _window(_start, end);
      _start = end;
    }
  }

  void _window(double t, double end) {
    final a = [for (final s in _acc) if (s.$1 >= t && s.$1 < end) s.$2];
    final w = [for (final s in _gyro) if (s.$1 >= t && s.$1 < end) s];
    _acc.removeWhere((s) => s.$1 < end);
    _gyro.removeWhere((s) => s.$1 < end);
    final riding = a.length > 100 &&
        w.length > 100 &&
        _kmh(t) > kPocketRidingKmh &&
        _kmh(end) > kPocketRidingKmh;
    // Den letzten Punkt vor dem nächsten Fenster behalten — das Tempo an
    // dessen Anfang.
    while (_fixes.length > 1 && _fixes[1].$1 <= end) {
      _fixes.removeAt(0);
    }
    if (!riding) return;
    final rotation = pocketRotation(w);
    final vibration = pocketVibration(a);
    windows.add((startS: t, rotation: rotation, vibration: vibration));
    if (vibration < kPocketCalmVibration) _calm.add(rotation);
    if (_calm.length >= kPocketCalmWindows) {
      state = _median(_calm.sublist(_calm.length - kPocketCalmWindows)) > kPocketRotationRad;
    }
  }
}

/// Effektivwert des Kreisels nach dem Tiefpass (rad/s) — `rotation` im
/// Werkzeug.
double pocketRotation(List<(double, double, double, double)> gyro) {
  if (gyro.isEmpty) return double.nan;
  var (ta, lx, ly, lz) = gyro.first;
  var total = 0.0;
  for (final (t, x, y, z) in gyro) {
    final k = math.min(1.0, math.max(0.0, t - ta) / kPocketGyroLowPassS);
    lx = lx + k * (x - lx);
    ly = ly + k * (y - ly);
    lz = lz + k * (z - lz);
    ta = t;
    total += lx * lx + ly * ly + lz * lz;
  }
  return math.sqrt(total / gyro.length);
}

/// Streuung der Beträge (Populations-Standardabweichung) — `vibration` im
/// Werkzeug.
double pocketVibration(List<double> norms) {
  if (norms.length < 2) return double.nan;
  var sum = 0.0;
  for (final n in norms) {
    sum += n;
  }
  final mean = sum / norms.length;
  var sq = 0.0;
  for (final n in norms) {
    sq += (n - mean) * (n - mean);
  }
  return math.sqrt(sq / norms.length);
}

double _median(List<double> values) {
  final s = [...values]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}
