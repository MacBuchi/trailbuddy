// Signalaufbereitung zur Laufzeit (#36, Konzept Airtime 3a und 9, Schritt
// 4; am Schalter der Rohdaten): `tool/sensor_fusion.py` in Dart, Zeile für Zeile — die
// drei Stufen Halterung, Lage-Filter (Mahony; der ESKF bleibt im Werkzeug
// als Gegenprobe) und Ereignisse. Reine Rechnung ohne Plattform: Der
// Logger (`sensor_log.dart`) füttert sie im Isolate des Dienstes, der
// Test mit derselben synthetischen Fahrt wie das Werkzeug
// (`test/rides/sensor_fusion_test.dart`), `tool/fusion_replay.dart` mit
// einer echten Datei.
//
// Drei Dinge, die man wissen muss:
// - **Gerechnet wird mit Verzug**: dv/dt schaut eine Sekunde voraus (GPS
//   kommt einmal je Sekunde), die Unsicherheit des Modells anderthalb.
//   Ein Wert wird erst verarbeitet, wenn ein GPS-Punkt 1,5 s nach ihm da
//   ist — so rechnet die App genau wie das Werkzeug über die ganze Datei,
//   und das Banner kommt 2–3 s nach dem Ereignis. Ein Sprung braucht dazu
//   die 3 s Tempo nach der Landung.
// - **Kein Zeitlimit für lange Wheelies**: Der Weg hält still, solange
//   die Front oben ist (nur aus einem ruhigen Weg), und verrutscht ist die
//   Halterung erst, wenn das Rad gekippt normal weiterfährt (Bremsen,
//   Antreten, Kurven), nicht nach einer festen Zeit. Gemeldet wird ein
//   Wheelie erst, wenn die Front unten ist; fällt vorher die Halterung
//   weg, war das Gekippte keiner.
// - **Die Halterung der letzten Fahrt** ([FusionMount]) startet die
//   nächste; fünf ruhige Sekunden daneben werfen sie wieder weg.
//
// Telefonachsen wie Android (x rechts, y den Bildschirm hoch, z heraus;
// in Ruhe +g nach oben), Radachsen x vorn, y links, z oben; Quaternionen
// nach Hamilton (w, x, y, z), q bildet Telefon auf Welt ab. Die Zeiten
// sind intern Sekunden ab [SensorFusion.originUs].
import 'dart:collection';
import 'dart:math' as math;

const kG = 9.80665;

// Ereignisse (Startwerte aus Konzept 2, gemessen in Schritt 3).
const kFusionWheelieTiltDeg = 15.0;
const kFusionWheelieMinS = 1.0;
const kFusionFlightG = 0.3;
const kFusionFlightMinMs = 150.0;

// Stoppie (Betreiber 2026-10-31): Startwerte, locker mit Absicht —
// gemessen wird mit den Banner-Antworten.
const kFusionStoppieTiltDeg = 10.0;
const kFusionStoppieMinS = 0.3;
const kFusionStoppieDecel = 1.0;

// Stufe 1, Halterung — je GPS-Punkt über die Sekunde davor.
const _mountMinMps = 2.2;
const _quietDvdt = 0.3;
const _quietYaw = 0.1;
const _quietForce = 0.6;
const _upTicks = 5;
const _upDecay = 0.995;
const _longDvdt = 0.8;
const _longYaw = 0.15;
const _leanYaw = 0.15;
const _fwdTicks = 5;
const _fwdConsistency = 0.5;
const _tiltedRad = 0.3;
const _slipRad = 0.5;
const _slipTicks = 5;

// Stufe 2, Lage-Filter.
const _accNoise = 6.0;
const _vibS = 0.25;
const _gateLow = 0.6, _gateHigh = 1.4;
const _mahonyKp = 2.0, _mahonyKi = 0.1;
const _mahonyFloor = 0.5;
const _modelTrust = 0.5;

// Stufe 3, Ereignisse.
const _tickS = 0.1;
const _roadS = 3.0;
const _holdDeg = 10.0;
const _ridingKmh = 8.0;
const _releaseDeg = 5.0;
const _flightSmoothS = 0.04;
const _landingWindowS = 0.3;
const _plausibleKmh = 10.0;
const _speedWindowS = 3.0;
const _peakMaxG = 8.0;
const _uprightAfterS = 1.0;
const _uprightPitchDeg = 30.0;
const _uprightRollDeg = 45.0;
const _stoppieMaxS = 3.0;
const _stoppieLandingS = 0.5;

/// Vorausschau: so weit muss das GPS einem Wert voraus sein.
const _lookAheadS = 1.5;

/// Ein Sensor, der ausbleibt (kein Kreisel), hält den anderen höchstens so
/// lange auf; ohne GPS rechnet die Fusion nach so viel Verzug trotzdem.
const _waitOtherS = 1.0;
const _maxLagS = 30.0;

typedef Vec = (double, double, double);
typedef _Quat = (double, double, double, double);
typedef _Mat = (Vec, Vec, Vec);

const Vec _zero = (0.0, 0.0, 0.0);
const Vec _ez = (0.0, 0.0, 1.0);

/// Was die Fusion meldet. [startUs] ist die Zeit des Sensors (µs seit
/// 1970) — dieselbe Achse wie die Zeilen der Rohdaten.
sealed class FusionEvent {
  const FusionEvent({required this.startUs, required this.duration});

  final int startUs;
  final Duration duration;
}

/// Front hoch gegen den Weg, ab [kFusionWheelieTiltDeg] für
/// [kFusionWheelieMinS]; [maxTiltDeg] ist die Spitze gegen den Weg.
class WheelieEvent extends FusionEvent {
  const WheelieEvent(
      {required super.startUs, required super.duration, required this.lengthM, required this.maxTiltDeg});

  final double lengthM;
  final double maxTiltDeg;
}

/// Gefilterter Betrag unter [kFusionFlightG] für [kFusionFlightMinMs];
/// [landingG] ist die Spitze in der Hochachse des Rads danach.
class JumpEvent extends FusionEvent {
  const JumpEvent(
      {required super.startUs,
      required super.duration,
      required this.landingG,
      required this.upright,
      required this.plausible});

  final double landingG;
  final bool upright;

  /// In Fahrt davor und danach, Spitze unter 8 g, Rad danach aufrecht.
  final bool plausible;
}

/// Front runter gegen den Weg, ab [kFusionStoppieTiltDeg], aus Fahrt und
/// beim Bremsen ([kFusionStoppieDecel]) für [kFusionStoppieMinS] bis 3 s;
/// [decel] ist das stärkste Bremsen (m/s², GPS), [landingG] die Spitze in
/// der Hochachse bis 0,5 s danach — das Hinterrad setzt auf.
class StoppieEvent extends FusionEvent {
  const StoppieEvent(
      {required super.startUs,
      required super.duration,
      required this.maxTiltDeg,
      required this.decel,
      required this.landingG});

  final double maxTiltDeg;
  final double decel;
  final double landingG;
}

/// Was gerade läuft, in der Reihenfolge des Vorrangs: in der Luft vor
/// Front oben vor Front unten.
enum FusionPhase { none, wheelie, stoppie, airborne }

/// Was das Modell zu einem Takt denkt (#36, die Live-Ansicht) — mit dem
/// Verzug der Fusion, also 1,5–2,5 s hinter der Uhr. [pitchDeg] ist NaN,
/// solange „vorn" nicht steht; [phaseStartUs] und [peakDeg] gehören zu
/// [phase] (bei [FusionPhase.airborne] ist [peakDeg] 0).
class FusionLive {
  const FusionLive({
    required this.tUs,
    required this.pitchDeg,
    required this.speedKmh,
    required this.upKnown,
    required this.phase,
    this.phaseStartUs,
    this.peakDeg = 0,
  });

  final int tUs;
  final double pitchDeg;
  final double speedKmh;
  final bool upKnown;
  final FusionPhase phase;
  final int? phaseStartUs;
  final double peakDeg;

  bool get mountReady => !pitchDeg.isNaN;
}

/// Die gelernte Halterung in Telefonachsen — gemerkt für die nächste Fahrt.
class FusionMount {
  const FusionMount({required this.up, required this.forward});

  final Vec up;
  final Vec forward;

  Map<String, Object> toJson() => {
        'up': [up.$1, up.$2, up.$3],
        'forward': [forward.$1, forward.$2, forward.$3],
      };

  static FusionMount? fromJson(Object? json) {
    if (json is! Map) return null;
    Vec? vec(Object? v) {
      if (v is! List || v.length != 3 || v.any((c) => c is! num)) return null;
      final n = [for (final c in v) (c as num).toDouble()];
      return _norm((n[0], n[1], n[2])) > 0.5 ? (n[0], n[1], n[2]) : null;
    }

    final up = vec(json['up']), forward = vec(json['forward']);
    return up == null || forward == null ? null : FusionMount(up: up, forward: forward);
  }
}

// ------------------------------------------------------------ Vektoren

Vec _add(Vec a, Vec b) => (a.$1 + b.$1, a.$2 + b.$2, a.$3 + b.$3);
Vec _sub(Vec a, Vec b) => (a.$1 - b.$1, a.$2 - b.$2, a.$3 - b.$3);
Vec _scale(Vec a, double k) => (a.$1 * k, a.$2 * k, a.$3 * k);
double _dot(Vec a, Vec b) => a.$1 * b.$1 + a.$2 * b.$2 + a.$3 * b.$3;
double _norm(Vec a) => math.sqrt(_dot(a, a));

Vec _cross(Vec a, Vec b) =>
    (a.$2 * b.$3 - a.$3 * b.$2, a.$3 * b.$1 - a.$1 * b.$3, a.$1 * b.$2 - a.$2 * b.$1);

Vec _unit(Vec a) {
  final n = _norm(a);
  return n > 1e-12 ? _scale(a, 1.0 / n) : _zero;
}

double _angle(Vec a, Vec b) => math.acos(_dot(_unit(a), _unit(b)).clamp(-1.0, 1.0));

Vec _mv(_Mat m, Vec v) => (_dot(m.$1, v), _dot(m.$2, v), _dot(m.$3, v));

/// mᵀ v.
Vec _mtv(_Mat m, Vec v) => (
      m.$1.$1 * v.$1 + m.$2.$1 * v.$2 + m.$3.$1 * v.$3,
      m.$1.$2 * v.$1 + m.$2.$2 * v.$2 + m.$3.$2 * v.$3,
      m.$1.$3 * v.$1 + m.$2.$3 * v.$2 + m.$3.$3 * v.$3,
    );

// ---------------------------------------------------------- Quaternionen

_Quat _qmul(_Quat p, _Quat q) {
  final (pw, px, py, pz) = p;
  final (qw, qx, qy, qz) = q;
  return (
    pw * qw - px * qx - py * qy - pz * qz,
    pw * qx + px * qw + py * qz - pz * qy,
    pw * qy - px * qz + py * qw + pz * qx,
    pw * qz + px * qy - py * qx + pz * qw,
  );
}

/// Die Drehung um den Vektor v (Achse × Winkel).
_Quat _qexp(Vec v) {
  final a = _norm(v);
  if (a < 1e-12) return (1.0, v.$1 / 2, v.$2 / 2, v.$3 / 2);
  final s = math.sin(a / 2) / a;
  return (math.cos(a / 2), v.$1 * s, v.$2 * s, v.$3 * s);
}

_Quat _qnorm(_Quat q) {
  final n = math.sqrt(q.$1 * q.$1 + q.$2 * q.$2 + q.$3 * q.$3 + q.$4 * q.$4);
  return (q.$1 / n, q.$2 / n, q.$3 / n, q.$4 / n);
}

_Mat _qrot(_Quat q) {
  final (w, x, y, z) = q;
  return (
    (1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)),
    (2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)),
    (2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)),
  );
}

/// Die Lage, deren Welt-z das gemessene Oben f ist (Gier bei 0).
_Quat _qFromGravity(Vec f) {
  final u = _unit(f);
  final axis = _cross(u, _ez);
  final s = _norm(axis);
  if (s < 1e-9) return u.$3 > 0 ? (1.0, 0.0, 0.0, 0.0) : (0.0, 1.0, 0.0, 0.0);
  return _qexp(_scale(axis, math.atan2(s, _dot(u, _ez)) / s));
}

// ------------------------------------------------------ Stufe 1: Halterung

/// Telefon → Radachsen, gelernt beim Fahren (Konzept 3a, Recherche 3).
class _Mount {
  _Mount(FusionMount? carried) {
    _reset();
    if (carried != null) _carry(carried);
  }

  Vec? up;
  Vec? fwd;
  Vec? left;
  double? upAt, fwdAt;
  final slips = <double>[];
  bool carried = false;
  double? droppedAt;
  bool _confirming = false;
  int _unconfirmed = 0;

  Vec _upSum = _zero;
  int _upN = 0;
  Vec _fwdSum = _zero;
  double _fwdAbs = 0;
  int _fwdN = 0;
  int _slipN = 0;

  void _reset() {
    _upSum = _zero;
    _upN = 0;
    _fwdSum = _zero;
    _fwdAbs = 0;
    _fwdN = 0;
    _slipN = 0;
  }

  /// Gewichtet wie die ersten Sekunden des Lernens: Ein paar ruhige
  /// Sekunden und Kurven dieser Fahrt schieben sie schon.
  void _carry(FusionMount m) {
    final u = _unit(m.up);
    up = u;
    _upSum = _scale(u, _upTicks.toDouble());
    _upN = _upTicks;
    _fwdSum = _scale(_unit(_sub(m.forward, _scale(u, _dot(m.forward, u)))), _fwdTicks.toDouble());
    _fwdAbs = _fwdTicks.toDouble();
    _fwdN = _fwdTicks;
    _orthogonalise();
    carried = _confirming = true;
    _unconfirmed = 0;
  }

  bool get ready => fwd != null;

  void _drop() {
    up = fwd = left = null;
    _reset();
  }

  /// Ein GPS-Abschnitt: f, w und das Welt-Oben u des Filters (in
  /// Telefonachsen) sind Mittel darüber. `true` = verrutscht (oder die
  /// mitgebrachte Halterung passt nicht): Der Filter beginnt neu.
  bool step(double t, Vec f, Vec w, double v0, double v1, double dt, Vec? u) {
    final speed = (v0 + v1) / 2;
    final dvdt = (v1 - v0) / dt;
    final up = this.up;
    final yaw = up != null ? _dot(w, up).abs() : _norm(w);
    if (up != null && u != null && _dot(u, up) < 0) u = null;
    if (speed < _mountMinMps) return false;
    final tilt = up != null ? _angle(f, up) : 0.0;
    final quiet = dvdt.abs() < _quietDvdt && yaw < _quietYaw && (_norm(f) - kG).abs() < _quietForce;
    if (_confirming && quiet) {
      // Die mitgebrachte Halterung gilt, wenn ruhiges Fahren zu ihr passt.
      if (tilt <= _tiltedRad) {
        _confirming = false;
      } else {
        if (++_unconfirmed >= _upTicks) {
          droppedAt = t;
          _confirming = false;
          _drop();
          return true;
        }
        return false;
      }
    }
    if (tilt > _slipRad) {
      // Ein Wheelie hält 40° auch minutenlang und endet mit einer Drehung
      // zurück; eine verrutschte Halterung bleibt gekippt, während das Rad
      // normal weiterfährt. Ruhig geradeaus sagt nichts — ein langer
      // Wheelie sieht genauso aus.
      if ((dvdt.abs() > _longDvdt && _norm(w) < _longYaw) || yaw > _leanYaw) {
        if (++_slipN >= _slipTicks) {
          slips.add(t);
          _drop();
          return true;
        }
      }
      return false;
    }
    if (tilt > _tiltedRad) return false;
    if (quiet) {
      _slipN = 0;
      _upSum = _add(_scale(_upSum, _upDecay), _unit(f));
      _upN++;
      if (_upN >= _upTicks) {
        upAt ??= t; // das erste Mal; ein Verrutschen setzt es nicht zurück
        this.up = _unit(_upSum);
        _orthogonalise();
      }
    } else if (up != null && dvdt.abs() > _longDvdt && _norm(w) < _longYaw) {
      // Bremsen zeigt nach hinten. Jede Drehung verdirbt es, nicht nur die
      // Gier: Auf rauem Grund nickt und rollt das Rad beim Bremsen.
      final h = _sub(f, _scale(up, _dot(f, up)));
      _learn(t, _scale(h, dvdt), dvdt.abs() * _norm(h));
    } else if (up != null && u != null && yaw > _leanYaw) {
      // Kurve: Das Rad legt sich hinein, das Welt-Oben kippt vom Telefon
      // aus nach außen — in der Linkskurve (Gier > 0) nach rechts.
      // Schräglage × Tempo × Gierrate zeigt nach vorn, in denselben
      // Einheiten wie das Bremsen.
      final h = _sub(u, _scale(up, _dot(u, up)));
      final turn = speed * _dot(w, up);
      _learn(t, _scale(_cross(up, h), turn * kG), turn.abs() * kG * _norm(h));
    }
    return false;
  }

  void _learn(double t, Vec term, double size) {
    _fwdSum = _add(_fwdSum, term);
    _fwdAbs += size;
    _fwdN++;
    if (_fwdN >= _fwdTicks && _norm(_fwdSum) > _fwdConsistency * _fwdAbs) {
      fwdAt ??= t;
      _orthogonalise();
    }
  }

  void _orthogonalise() {
    final up = this.up;
    if (up == null || _fwdN < _fwdTicks || _norm(_fwdSum) <= _fwdConsistency * _fwdAbs) return;
    final h = _sub(_fwdSum, _scale(up, _dot(_fwdSum, up)));
    fwd = _unit(h);
    left = _cross(up, fwd!);
  }
}

// ------------------------------------------------- Stufe 2: Lage-Filter

/// Mahony et al. 2008 mit Bias-Integral; das Gewicht der Korrektur kommt
/// aus derselben adaptiven Unsicherheit wie im Kalman-Filter des Werkzeugs.
class _Mahony {
  _Mahony(Vec f0) : q = _qFromGravity(f0);

  _Quat q;
  Vec b = _zero;
  Vec _e = _zero;
  double k = 0;

  void reset(Vec f) => q = _qFromGravity(f);

  void predict(Vec w, double dt) {
    final u = _add(_sub(w, b), _scale(_e, _mahonyKp * k));
    b = _sub(b, _scale(_e, _mahonyKi * k * dt));
    q = _qnorm(_qmul(q, _qexp(_scale(u, dt))));
  }

  _Mat rot() => _qrot(q);

  void update(Vec f, double rVar) {
    final v = _mtv(rot(), _ez); // geschätztes Oben in Telefonachsen
    _e = _cross(_unit(f), v);
    final extra = math.max(0.0, rVar - _accNoise * _accNoise);
    k = _mahonyFloor * _mahonyFloor / (_mahonyFloor * _mahonyFloor + extra);
  }
}

// ------------------------------------------------------------------- GPS

/// Tempo aus den Punkten, dazwischen linear; dv/dt schaut 1 s voraus.
class _Gps {
  final _times = <double>[];
  final _speeds = <double>[];

  int get length => _times.length;
  bool get isEmpty => _times.isEmpty;
  double get lastT => _times.last;
  double timeAt(int i) => _times[i];
  double speedAt(int i) => _speeds[i];

  void add(double t, double speed) {
    if (speed.isNaN || (_times.isNotEmpty && t <= _times.last)) return;
    _times.add(t);
    _speeds.add(speed);
  }

  /// Die ältesten [n] Punkte weg — sie liegen weit hinter der Rechnung.
  void drop(int n) {
    _times.removeRange(0, n);
    _speeds.removeRange(0, n);
  }

  /// Erster Index mit Zeit > t (Pythons `bisect_right`).
  int _right(double t) {
    var lo = 0, hi = _times.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_times[mid] <= t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Erster Index mit Zeit ≥ t (`bisect_left`).
  int _left(double t) {
    var lo = 0, hi = _times.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_times[mid] < t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  double speed(double t) {
    final i = _right(t);
    if (i == 0) return _speeds.isEmpty ? double.nan : _speeds.first;
    if (i == _times.length) return _speeds.last;
    final t0 = _times[i - 1], t1 = _times[i], s0 = _speeds[i - 1], s1 = _speeds[i];
    return t1 > t0 ? s0 + (s1 - s0) * (t - t0) / (t1 - t0) : s1;
  }

  double dvdt(double t) => (speed(t + 1.0) - speed(t - 1.0)) / 2.0;

  double dvdtChange(double t) => dvdt(t + 0.5) - dvdt(t - 0.5);

  bool riding(double start, double end, double kmh) {
    final i = _left(start), j = _right(end);
    if (j <= i) return false;
    var low = double.infinity;
    for (var k = i; k < j; k++) {
      low = math.min(low, _speeds[k]);
    }
    return low * 3.6 >= kmh;
  }
}

// --------------------------------------------------------------- Fusion

class _Stoppie {
  _Stoppie(this.t0, this.t1, this.tEnd, this.peakDeg, this.decel, this.landing);

  final double t0, t1, tEnd, peakDeg, decel;
  double landing;
}

class _Flight {
  _Flight(this.t0, this.t1, this.peak);

  final double t0, t1;
  double peak;
  bool peakDone = false;
}

/// Die Fusion EINER Fahrt, fortlaufend gefüttert.
class SensorFusion {
  SensorFusion({FusionMount? carried, this.originUs}) : _mount = _Mount(carried);

  /// Nullpunkt der internen Zeit; ohne Angabe der erste Wert.
  int? originUs;

  final _Mount _mount;
  final _gps = _Gps();
  final _acc = ListQueue<(double, Vec)>();
  final _gyro = ListQueue<(double, Vec)>();
  double _accNewest = double.negativeInfinity, _gyroNewest = double.negativeInfinity;
  final _out = <FusionEvent>[];

  _Mahony? _filter;
  int _fixI = 0;
  Vec _sumF = _zero, _sumW = _zero, _sumU = _zero;
  int _nF = 0, _nW = 0;
  Vec _wLast = _zero;
  double? _tW, _tA;
  double _vibMean = kG, _vibVar = 0;
  double _nextTick = 0;

  // Stufe 3.
  double? _road;
  double _calm = 0;
  bool _holding = false;
  final _ticks = ListQueue<(double, double, double)>(); // t, Pitch gegen den Weg, Roll
  double? _wStart;
  double _wLast2 = 0, _wPeak = 0, _wSpeedSum = 0;
  int _wSpeedN = 0;
  final _window = ListQueue<(double, double)>();
  double _windowSum = 0;
  double? _flightStart;
  final _flights = <_Flight>[];
  double? _sStart;
  double _sLast = 0, _sPeak = 0, _sLow = 0, _sLanding = 0;
  final _stoppies = <_Stoppie>[];

  /// Für den Test und die Nachrechnung.
  int updates = 0, rejected = 0;

  /// Je Takt ein [FusionLive], abgeholt mit [takeLive] — die Fusion
  /// rechnet in Schüben (je GPS-Punkt eine Sekunde), die Live-Ansicht
  /// spielt sie nach der Zeit ab. Nur, solange [keepLive] an ist; sonst
  /// sammelte sich eine Stunde Takte an.
  bool keepLive = false;
  final _live = <FusionLive>[];

  List<FusionLive> takeLive() {
    if (_live.isEmpty) return const [];
    final out = List<FusionLive>.of(_live);
    _live.clear();
    return out;
  }

  /// Die Halterung, sobald „vorn" steht — für die nächste Fahrt.
  FusionMount? get mount {
    final up = _mount.up, fwd = _mount.fwd;
    return up == null || fwd == null ? null : FusionMount(up: up, forward: fwd);
  }

  bool get mountCarried => _mount.carried;
  double? get mountDroppedAt => _mount.droppedAt;
  double? get upAt => _mount.upAt;
  double? get forwardAt => _mount.fwdAt;
  List<double> get slips => List.unmodifiable(_mount.slips);

  double _t(int us) => (us - (originUs ??= us)) / 1e6;

  int _us(double t) => originUs! + (t * 1e6).round();

  List<FusionEvent> addAccel(int tUs, double x, double y, double z) {
    final t = _t(tUs);
    _acc.add((t, (x, y, z)));
    _accNewest = math.max(_accNewest, t);
    return _pump();
  }

  List<FusionEvent> addGyro(int tUs, double x, double y, double z) {
    final t = _t(tUs);
    _gyro.add((t, (x, y, z)));
    _gyroNewest = math.max(_gyroNewest, t);
    return _pump();
  }

  List<FusionEvent> addGps(int tUs, double speedMps) {
    _gps.add(_t(tUs), speedMps);
    return _pump();
  }

  /// Ende der Fahrt: alles Gepufferte rechnen, offene Sprünge mit dem
  /// abschließen, was da ist. Ein laufender Wheelie zählt nicht.
  List<FusionEvent> finish() {
    _pump(all: true);
    for (final f in _flights) {
      _finishFlight(f);
    }
    _flights.clear();
    _stoppies.forEach(_emitStoppie);
    _stoppies.clear();
    return _take();
  }

  List<FusionEvent> _take() {
    if (_out.isEmpty) return const [];
    final events = List<FusionEvent>.of(_out);
    _out.clear();
    return events;
  }

  List<FusionEvent> _pump({bool all = false}) {
    final limit = _gps.isEmpty ? double.negativeInfinity : _gps.lastT - _lookAheadS;
    final newest = math.max(_accNewest, _gyroNewest);
    while (_acc.isNotEmpty || _gyro.isNotEmpty) {
      final bool takeGyro;
      if (_acc.isNotEmpty && _gyro.isNotEmpty) {
        takeGyro = _gyro.first.$1 <= _acc.first.$1;
      } else {
        // Der andere Sensor ist noch unterwegs — warten, außer er bleibt aus.
        final head = _acc.isNotEmpty ? _acc.first.$1 : _gyro.first.$1;
        final own = _acc.isNotEmpty ? _accNewest : _gyroNewest;
        if (!all && own - head < _waitOtherS) break;
        takeGyro = _gyro.isNotEmpty;
      }
      final t = takeGyro ? _gyro.first.$1 : _acc.first.$1;
      if (!all && t >= limit && newest - t < _maxLagS) break;
      _mountSteps(t);
      if (takeGyro) {
        _onGyro(_gyro.removeFirst());
      } else {
        _onAccel(_acc.removeFirst());
      }
    }
    if (_fixI > 200) {
      _gps.drop(100);
      _fixI -= 100;
    }
    return _take();
  }

  /// Stufe 1 einmal je GPS-Punkt, über die Sekunde davor.
  void _mountSteps(double t) {
    while (_fixI < _gps.length && _gps.timeAt(_fixI) <= t) {
      if (_fixI > 0 && _nF > 0 && _nW > 0) {
        final t0 = _gps.timeAt(_fixI - 1), t1 = _gps.timeAt(_fixI);
        if (t1 - t0 > 0 && t1 - t0 <= 3.0) {
          final f = _scale(_sumF, 1 / _nF);
          final filter = _filter;
          if (_mount.step(t1, f, _scale(_sumW, 1 / _nW), _gps.speedAt(_fixI - 1), _gps.speedAt(_fixI),
              t1 - t0, filter != null ? _unit(_sumU) : null)) {
            filter?.reset(f);
          }
        }
      }
      _sumF = _sumW = _sumU = _zero;
      _nF = _nW = 0;
      _fixI++;
    }
  }

  void _onGyro((double, Vec) sample) {
    final (t, w) = sample;
    _wLast = w;
    _sumW = _add(_sumW, w);
    _nW++;
    final filter = _filter, tW = _tW;
    if (filter != null && tW != null) {
      final dt = t - tW;
      if (dt > 0 && dt < 0.1) filter.predict(w, dt);
    }
    _tW = t;
  }

  void _onAccel((double, Vec) sample) {
    final (t, f) = sample;
    _sumF = _add(_sumF, f);
    _nF++;
    final fn = _norm(f);
    final tA = _tA;
    final dt = tA == null ? 0.0 : (t - tA).clamp(0.0, 0.1);
    _tA = t;
    final k = math.min(1.0, dt / _vibS);
    _vibMean += k * (fn - _vibMean);
    _vibVar += k * ((fn - _vibMean) * (fn - _vibMean) - _vibVar);
    var filter = _filter;
    if (filter == null) {
      filter = _filter = _Mahony(f);
      _nextTick = t;
    }
    var r = filter.rot();
    _sumU = _add(_sumU, r.$3);
    final speed = _gps.speed(t);
    final dvdt = _gps.dvdt(t);
    final yaw = _dot(_sub(_wLast, filter.b), r.$3);
    var aP = _zero;
    // Ohne „vorn" lässt sich das Modell nicht abziehen, seine Größe aber
    // kennt man: bis dahin ganz als Rauschen zählen.
    final unknown = _mount.ready || speed.isNaN ? 0.0 : dvdt * dvdt + (speed * yaw) * (speed * yaw);
    final fwd = _mount.fwd;
    if (fwd != null && !speed.isNaN) {
      final fw = _mv(r, fwd);
      final flat = (fw.$1, fw.$2, 0.0);
      if (_norm(flat) > 1e-12) {
        final fh = _unit(flat);
        final aW = _add(_scale(fh, dvdt), _scale((-fh.$2, fh.$1, 0.0), speed * yaw));
        aP = _mtv(r, aW);
      }
    }
    final fc = _sub(f, aP);
    final fcn = _norm(fc) / kG;
    if (_gateLow < fcn && fcn < _gateHigh) {
      final res = _norm(fc) - kG;
      // Auch das Modell ist unsicher: dv/dt ist über zwei Sekunden
      // geglättet und kommt beim Wechsel Bremsen → Antreten zu spät.
      final change = _gps.dvdtChange(t);
      final model = _modelTrust * _norm(aP);
      filter.update(fc,
          _accNoise * _accNoise + _vibVar + (2 * res) * (2 * res) + model * model + change * change + unknown);
      updates++;
    } else {
      rejected++;
      filter.k = 0;
    }
    final up = _mount.up;
    _flightSample(t, fn / kG, (up != null ? _dot(f, up) : fn) / kG);
    if (t >= _nextTick) {
      _nextTick = t + _tickS;
      var pitch = double.nan, roll = double.nan;
      final left = _mount.left;
      if (fwd != null && left != null) {
        r = filter.rot();
        pitch = _deg(math.asin(_dot(r.$3, fwd).clamp(-1.0, 1.0)));
        roll = _deg(math.asin(_dot(r.$3, left).clamp(-1.0, 1.0)));
      }
      _tick(t, pitch, roll, speed, dvdt);
      if (keepLive) _live.add(_snapshot(t, speed));
    }
    _settleFlights();
  }

  /// Nur lesend: ändert nichts an der Rechnung, Dart bleibt = Werkzeug.
  FusionLive _snapshot(double t, double speed) {
    final rel = _ticks.isEmpty ? double.nan : _ticks.last.$2;
    final flight = _flightStart, wheelie = _wStart, stoppie = _sStart;
    final (phase, start, peak) = flight != null
        ? (FusionPhase.airborne, flight, 0.0)
        : wheelie != null
            ? (FusionPhase.wheelie, wheelie, _wPeak)
            : stoppie != null
                ? (FusionPhase.stoppie, stoppie, _sPeak)
                : (FusionPhase.none, null, 0.0);
    return FusionLive(
        tUs: _us(t),
        pitchDeg: rel,
        speedKmh: speed.isNaN ? 0 : speed * 3.6,
        upKnown: _mount.up != null,
        phase: phase,
        phaseStartUs: start == null ? null : _us(start),
        peakDeg: peak);
  }

  // ------------------------------------------------------- Stufe 3

  void _tick(double t, double pitch, double roll, double speed, double dvdt) {
    // Der Weg folgt dem Pitch über [_roadS] in Fahrt und hält still,
    // solange die Front oben ist — so lange sie oben ist. Aber nur aus
    // einem ruhigen Weg (Pitch [_roadS] lang innerhalb [_holdDeg]): Nach
    // „Front runter" hinkt der Weg unten nach, und das Zurückkommen der
    // Front ist kein Wheelie — ohne Zeitlimit ließe so ein Halten nie los.
    var rel = double.nan;
    if (pitch.isNaN) {
      _road = null;
      _calm = 0;
      _holding = false;
    } else {
      final road = _road ??= pitch;
      rel = pitch - road;
      _holding = rel >= _holdDeg && (_holding || _calm >= _roadS);
      _calm = rel.abs() < _holdDeg ? _calm + _tickS : 0.0;
      if (speed * 3.6 > _ridingKmh && !_holding) _road = road + (pitch - road) * _tickS / _roadS;
    }
    _ticks.add((t, rel, roll));
    while (t - _ticks.first.$1 > 15) {
      _ticks.removeFirst();
    }

    _stoppieTick(t, rel, dvdt);

    final riding = !speed.isNaN && speed * 3.6 > _ridingKmh;
    final start = _wStart;
    if (start != null) {
      if (rel.isNaN) {
        // Die Halterung ist weg: Das Gekippte war kein Wheelie.
        _wStart = null;
        return;
      }
      if (rel >= kFusionWheelieTiltDeg - _releaseDeg) {
        // Langsamer werden mit der Front oben beendet ihn nicht, es zählt
        // nur nicht mit: Ein Wheelie endet mit der Front unten. Früher
        // gemeldet, käme eine verrutschte Halterung bei jedem Bremsen als
        // Wheelie, bevor das Verrutschen feststeht.
        if (riding) {
          _wLast2 = t;
          _wPeak = math.max(_wPeak, rel);
          _wSpeedSum += speed;
          _wSpeedN++;
        }
        return;
      }
      final duration = _wLast2 - start;
      if (kFusionWheelieMinS <= duration) {
        _out.add(WheelieEvent(
            startUs: _us(start),
            duration: Duration(microseconds: (duration * 1e6).round()),
            lengthM: _wSpeedSum / _wSpeedN * duration,
            maxTiltDeg: _wPeak));
      }
      _wStart = null;
      return;
    }
    if (riding && !rel.isNaN && rel >= kFusionWheelieTiltDeg) {
      _wStart = _wLast2 = t;
      _wPeak = rel;
      _wSpeedSum = speed;
      _wSpeedN = 1;
    }
  }

  /// Wie der Wheelie, nur mit der Front unten; das Tempo zählt eine
  /// Sekunde vor dem Beginn — ein Stoppie endet oft im Stehen.
  void _stoppieTick(double t, double rel, double dvdt) {
    final start = _sStart;
    if (start != null) {
      if (rel.isNaN) {
        _sStart = null;
        return;
      }
      if (rel <= -(kFusionStoppieTiltDeg - _releaseDeg)) {
        _sLast = t;
        _sPeak = math.max(_sPeak, -rel);
        _sLow = math.min(_sLow, dvdt);
        return;
      }
      final duration = _sLast - start;
      if (kFusionStoppieMinS <= duration && duration <= _stoppieMaxS && _sLow <= -kFusionStoppieDecel) {
        _stoppies.add(_Stoppie(start, _sLast, t, _sPeak, -_sLow, _sLanding));
      }
      _sStart = null;
      return;
    }
    if (!rel.isNaN && rel <= -kFusionStoppieTiltDeg && _gps.speed(t - 1.0) * 3.6 > _ridingKmh) {
      _sStart = _sLast = t;
      _sPeak = -rel;
      _sLow = dvdt;
      _sLanding = 0;
    }
  }

  void _emitStoppie(_Stoppie s) => _out.add(StoppieEvent(
      startUs: _us(s.t0),
      duration: Duration(microseconds: ((s.t1 - s.t0) * 1e6).round()),
      maxTiltDeg: s.peakDeg,
      decel: s.decel,
      landingG: s.landing));

  void _flightSample(double t, double fn, double fz) {
    // Die Landung eines Stoppies: vom Beginn (ohne den Wert, der ihn
    // auslöste — wie im Werkzeug) bis 0,5 s nach dem Ende.
    if (_sStart != null) _sLanding = math.max(_sLanding, fz);
    _stoppies.removeWhere((s) {
      if (t - s.tEnd > _stoppieLandingS) {
        _emitStoppie(s);
        return true;
      }
      s.landing = math.max(s.landing, fz);
      return false;
    });

    _window.add((t, fn));
    _windowSum += fn;
    while (t - _window.first.$1 > _flightSmoothS) {
      _windowSum -= _window.removeFirst().$2;
    }
    for (final f in _flights) {
      if (f.peakDone) continue;
      if (t - f.t1 > _landingWindowS) {
        f.peakDone = true;
      } else {
        f.peak = math.max(f.peak, fz);
      }
    }
    final low = _windowSum / _window.length < kFusionFlightG;
    final start = _flightStart;
    if (low && start == null) _flightStart = t;
    if (!low && start != null) {
      if ((t - start) * 1000 >= kFusionFlightMinMs) _flights.add(_Flight(start, t, math.max(0.0, fz)));
      _flightStart = null;
    }
  }

  /// Ein Sprung ist fertig, wenn die Landespitze vorbei ist, ein Takt eine
  /// Sekunde danach steht und das GPS die 3 s nach der Landung kennt.
  void _settleFlights() {
    if (_flights.isEmpty) return;
    final lastTick = _ticks.isEmpty ? double.negativeInfinity : _ticks.last.$1;
    final lastFix = _gps.isEmpty ? double.negativeInfinity : _gps.lastT;
    _flights.removeWhere((f) {
      final ready = f.peakDone && lastTick >= f.t1 + _uprightAfterS && lastFix > f.t1 + _speedWindowS;
      if (ready) _finishFlight(f);
      return ready;
    });
  }

  void _finishFlight(_Flight f) {
    final before = _gps.riding(f.t0 - _speedWindowS, f.t0, _plausibleKmh);
    final after = _gps.riding(f.t1, f.t1 + _speedWindowS, _plausibleKmh);
    var upright = true;
    if (_ticks.isNotEmpty) {
      final at = f.t1 + _uprightAfterS;
      final tick = _ticks.firstWhere((x) => x.$1 >= at, orElse: () => _ticks.last);
      if (!tick.$2.isNaN) upright = tick.$2.abs() < _uprightPitchDeg && tick.$3.abs() < _uprightRollDeg;
    }
    _out.add(JumpEvent(
        startUs: _us(f.t0),
        duration: Duration(microseconds: ((f.t1 - f.t0) * 1e6).round()),
        landingG: f.peak,
        upright: upright,
        plausible: before && after && f.peak < _peakMaxG && upright));
  }
}

double _deg(double rad) => rad * 180 / math.pi;
