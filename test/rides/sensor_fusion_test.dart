// Die Fusion der App gegen die synthetische Fahrt des Werkzeugs (#36
// Schritt 4): `synthetic()` aus `tool/sensor_fusion.py`, Zeile für Zeile,
// mit demselben Rauschen (`Noise`: xorshift32, vier Gleichverteilte) —
// beide sehen also dieselbe Fahrt. Die erwarteten Zeiten hat das Werkzeug
// mit Mahony gerechnet (2026-10-31); die Gegenprobe auf den echten Fahrten
// macht `tool/fusion_replay.dart`.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/rides/sensor_fusion.dart';

typedef _M = List<List<double>>;

_M _mm(_M a, _M b) => [
      for (var i = 0; i < 3; i++)
        [for (var j = 0; j < 3; j++) a[i][0] * b[0][j] + a[i][1] * b[1][j] + a[i][2] * b[2][j]]
    ];

_M _mt(_M a) => [
      for (var i = 0; i < 3; i++) [for (var j = 0; j < 3; j++) a[j][i]]
    ];

List<double> _mv(_M m, List<double> v) => [for (final r in m) r[0] * v[0] + r[1] * v[1] + r[2] * v[2]];

_M _rz(double a) => [
      [math.cos(a), -math.sin(a), 0.0],
      [math.sin(a), math.cos(a), 0.0],
      [0.0, 0.0, 1.0],
    ];

_M _ry(double a) => [
      [math.cos(a), 0.0, math.sin(a)],
      [0.0, 1.0, 0.0],
      [-math.sin(a), 0.0, math.cos(a)],
    ];

_M _rx(double a) => [
      [1.0, 0.0, 0.0],
      [0.0, math.cos(a), -math.sin(a)],
      [0.0, math.sin(a), math.cos(a)],
    ];

double _rad(double deg) => deg * math.pi / 180;

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

double _ramp(double t, double t0, double t1, [double rise = 0.3]) {
  if (t <= t0 || t >= t1) return 0;
  return math.min(1.0, math.min((t - t0) / rise, (t1 - t) / rise));
}

final _mount0 = _mm(_rz(_rad(140)), _rx(_rad(-35)));
final _mount1 = _mm(_rx(_rad(60)), _mount0);

/// [slipPitch]: Die Halterung kippt bei 150 s um 40° Front hoch statt um
/// die Querachse des Telefons — sieht aus wie ein Wheelie.
List<(String, double, List<double>)> _synthetic({bool slipPitch = false}) {
  final mount1 = slipPitch ? _mm(_mount0, _ry(_rad(40))) : _mount1;
  final rnd = _Noise(1);
  const hz = 120.0;
  const bias = [0.02, -0.012, 0.015];

  double speed(double t) {
    var v = 6.0;
    for (final t0 in const [20, 30, 40, 215, 230, 240, 250]) {
      if (t0 <= t && t < t0 + 2) {
        v -= 2.0 * (t - t0);
      } else if (t0 + 2 <= t && t < t0 + 4) {
        v -= 4.0 - 2.0 * (t - t0 - 2);
      }
    }
    if (60 <= t && t < 62) {
      v -= 3.0 * (t - 60);
    } else if (62 <= t && t < 64) {
      v -= 6.0 - 3.0 * (t - 62);
    }
    if (410 <= t && t < 411.5) {
      v -= 3.0 * (t - 410);
    } else if (411.5 <= t && t < 414) {
      v -= 4.5 - 1.8 * (t - 411.5);
    }
    return v;
  }

  (_M, double, double, double) attitude(double t) {
    final yawRate = 0.6 * math.min(1.0, math.max(0.0, math.min(t - 70, 80 - t)));
    final yaw = t > 70 ? 0.6 * (math.max(0.0, math.min(t, 80.0) - 70) - 0.5) : 0.0;
    final v = speed(t);
    final roll = -math.atan2(v * yawRate, kG);
    final pitch = _rad(25) * _ramp(t, 90, 92) -
        _rad(20) * _ramp(t, 110, 112.5) +
        _rad(10) * _ramp(t, 128, 145, 3.0) +
        _rad(18) * _ramp(t, 135, 137) +
        _rad(22) * _ramp(t, 280, 282) +
        _rad(40) * _ramp(t, 310, 400, 1.0) -
        _rad(18) * _ramp(t, 410.3, 411.6);
    return (_mm(_mm(_rz(yaw), _ry(-pitch)), _rx(roll)), v, yaw, yawRate);
  }

  final out = <(String, double, List<double>)>[];
  const dt = 1 / hz;
  final n = (420 * hz).toInt();
  var prev = attitude(0).$1;
  for (var i = 1; i < n; i++) {
    final t = i * dt;
    final (rWb, v, yaw, yawRate) = attitude(t);
    final dv = (speed(t + dt) - speed(t - dt)) / (2 * dt);
    var fW = [
      dv * math.cos(yaw) - v * yawRate * math.sin(yaw),
      dv * math.sin(yaw) + v * yawRate * math.cos(yaw),
      kG,
    ];
    if (100.0 <= t && t < 100.5) {
      fW = [0.0, 0.0, 0.0];
    } else if (100.5 <= t && t < 100.55) {
      fW = _mv(rWb, [0.0, 0.0, 3 * kG]);
    } else if (411.6 <= t && t < 411.65) {
      fW = _mv(rWb, [0.0, 0.0, 1.8 * kG]);
    }
    final m = t >= 150 ? mount1 : _mount0;
    final fP = _mv(m, _mv(_mt(rWb), fW));
    final rel = _mm(_mt(prev), rWb);
    final wB = [rel[2][1] - rel[1][2], rel[0][2] - rel[2][0], rel[1][0] - rel[0][1]]
        .map((c) => c * 0.5 / dt)
        .toList();
    final wP = [for (final (k, c) in _mv(m, wB).indexed) c + bias[k]];
    prev = rWb;
    final noise = 100.0 <= t && t < 100.5 ? 0.05 : 1.0;
    out.add(('a', t, [for (final c in fP) c + rnd.gauss(noise)]));
    out.add(('w', t + 0.002, [for (final c in wP) c + rnd.gauss(0.01)]));
    if (i % hz.toInt() == 0) out.add(('g', t, [v]));
  }
  return out;
}

final _ride = _synthetic();

int _us(double t) => (t * 1e6).round();

/// Füttert die Fahrt; [accelAhead] Werte der Beschleunigung kommen je
/// Schub vor dem Kreisel an, wie der Kanal des Sensors sie liefert.
(SensorFusion, List<FusionEvent>) _run(
    {FusionMount? carried, int accelAhead = 0, List<(String, double, List<double>)>? ride}) {
  final fusion = SensorFusion(carried: carried, originUs: 0);
  final events = <FusionEvent>[];
  final held = <(String, double, List<double>)>[];
  void feed((String, double, List<double>) s) {
    final (kind, t, v) = s;
    events.addAll(switch (kind) {
      'a' => fusion.addAccel(_us(t), v[0], v[1], v[2]),
      'w' => fusion.addGyro(_us(t), v[0], v[1], v[2]),
      _ => fusion.addGps(_us(t), v[0]),
    });
  }

  for (final s in ride ?? _ride) {
    if (accelAhead == 0 || s.$1 == 'a') {
      feed(s);
      continue;
    }
    held.add(s);
    if (held.length >= accelAhead) {
      held.forEach(feed);
      held.clear();
    }
  }
  held.forEach(feed);
  events.addAll(fusion.finish());
  return (fusion, events);
}

double _s(int us) => us / 1e6;

FusionMount _mount(_M m) {
  final up = _mv(m, [0.0, 0.0, 1.0]), fwd = _mv(m, [1.0, 0.0, 0.0]);
  return FusionMount(up: (up[0], up[1], up[2]), forward: (fwd[0], fwd[1], fwd[2]));
}

void main() {
  test('dieselben Ereignisse wie das Werkzeug', () {
    final (fusion, events) = _run();
    final wheelies = events.whereType<WheelieEvent>().toList();
    // Das Werkzeug (Mahony): 90,20/1,60 · 135,30/1,50 · 280,27/1,56 · 310,48/89,27 s.
    const expected = [(90.20, 1.60), (135.30, 1.50), (280.27, 1.56), (310.48, 89.27)];
    expect(wheelies, hasLength(4), reason: '$wheelies');
    for (final (i, (start, duration)) in expected.indexed) {
      expect(_s(wheelies[i].startUs), closeTo(start, 0.11), reason: 'Wheelie $i');
      expect(wheelies[i].duration.inMicroseconds / 1e6, closeTo(duration, 0.11), reason: 'Wheelie $i');
    }
    expect(wheelies.last.maxTiltDeg, closeTo(40.6, 1), reason: 'der lange, 40°');
    expect(wheelies.last.lengthM, closeTo(6 * 89.27, 5));

    final jumps = events.whereType<JumpEvent>().toList();
    expect(jumps, hasLength(1));
    expect(_s(jumps.single.startUs), closeTo(100.025, 0.01));
    expect(jumps.single.duration.inMilliseconds, closeTo(475, 10));
    expect(jumps.single.landingG, closeTo(3.22, 0.1));
    expect(jumps.single.plausible, isTrue);

    // Werkzeug (Mahony): 410,48 s, 0,93 s, 17,2°, 1,8 m/s², Landung 1,85 g.
    // Front runter bei 110 s ohne Bremsen und hartes Bremsen bei 60 s
    // ohne Neigung bleiben still.
    final stoppies = events.whereType<StoppieEvent>().toList();
    expect(stoppies, hasLength(1), reason: '$stoppies');
    final s = stoppies.single;
    expect(_s(s.startUs), closeTo(410.48, 0.11));
    expect(s.duration.inMicroseconds / 1e6, closeTo(0.93, 0.11));
    expect(s.maxTiltDeg, closeTo(17.2, 0.3));
    expect(s.decel, closeTo(1.8, 0.05));
    expect(s.landingG, closeTo(1.85, 0.05));

    // Verrutscht bei 150 s, gesehen erst beim Bremsen ab 215 s (Werkzeug: 231 s).
    expect(fusion.slips, hasLength(1));
    expect(fusion.slips.single, closeTo(231, 1));
    expect(fusion.upAt, lessThanOrEqualTo(20));
    expect(fusion.forwardAt, lessThanOrEqualTo(45));
  });

  test('die Halterung nach dem Verrutschen ist die neue', () {
    final (fusion, _) = _run();
    final m = fusion.mount!;
    final up1 = _mv(_mount1, [0.0, 0.0, 1.0]), fwd1 = _mv(_mount1, [1.0, 0.0, 0.0]);
    double angle(Vec a, List<double> b) =>
        math.acos((a.$1 * b[0] + a.$2 * b[1] + a.$3 * b[2]).clamp(-1.0, 1.0)) * 180 / math.pi;
    expect(angle(m.up, up1), lessThan(4));
    expect(angle(m.forward, fwd1), lessThan(8));
  });

  test('verrutscht Front hoch: kein Wheelie, wenn das Bremsen das Verrutschen zeigt', () {
    final (fusion, events) = _run(ride: _synthetic(slipPitch: true));
    expect(fusion.slips, hasLength(1));
    final starts = [for (final w in events.whereType<WheelieEvent>()) _s(w.startUs)];
    expect(starts.where((t) => t >= 140 && t <= 235), isEmpty, reason: '$starts');
    // Danach fehlt die Zeit, „vorn" neu zu lernen (nur eine Bremsung bei 250 s).
    expect(starts, [closeTo(90.2, 0.11), closeTo(135.3, 0.11)], reason: 'die echten davor bleiben');
  });

  test('die Live-Ansicht liest nur mit: dieselben Ereignisse, je Takt ein Zustand', () {
    final (_, plain) = _run();
    final fusion = SensorFusion(originUs: 0)..keepLive = true;
    final events = <FusionEvent>[];
    final live = <FusionLive>[];
    for (final (kind, t, v) in _ride) {
      events.addAll(switch (kind) {
        'a' => fusion.addAccel(_us(t), v[0], v[1], v[2]),
        'w' => fusion.addGyro(_us(t), v[0], v[1], v[2]),
        _ => fusion.addGps(_us(t), v[0]),
      });
      live.addAll(fusion.takeLive());
    }
    events.addAll(fusion.finish());
    live.addAll(fusion.takeLive());
    String key(FusionEvent e) => '${e.runtimeType} ${e.startUs} ${e.duration.inMicroseconds}';
    expect(events.map(key), plain.map(key));

    // Rund 10 Hz über die Fahrt, in der Zeit aufsteigend.
    expect(live.length, inInclusiveRange(_ride.last.$2 * 10 - 100, _ride.last.$2 * 10 + 1));
    for (var i = 1; i < live.length; i++) {
      expect(live[i].tUs, greaterThan(live[i - 1].tUs));
    }
    // Ohne gelernte Halterung kein Winkel; danach einer.
    expect(live.first.mountReady, isFalse);
    expect(live.first.upKnown, isFalse);
    FusionLive at(double s) => live.firstWhere((l) => l.tUs >= _us(s));
    expect(at(60).mountReady, isTrue);
    // Mitten im langen Wheelie (310,5–399,8 s, 40°): Phase, Beginn, Spitze.
    final mid = at(350);
    expect(mid.phase, FusionPhase.wheelie);
    expect(_s(mid.phaseStartUs!), closeTo(310.48, 0.11));
    expect(mid.pitchDeg, closeTo(40, 3));
    expect(mid.peakDeg, greaterThanOrEqualTo(mid.pitchDeg));
    // Der Sprung (100,0–100,5 s) in der Luft, der Stoppie (410,5 s) mit der Front unten.
    expect(at(100.3).phase, FusionPhase.airborne);
    final stoppie = at(410.9);
    expect(stoppie.phase, FusionPhase.stoppie);
    expect(stoppie.pitchDeg, lessThan(-kFusionStoppieTiltDeg + 5));
    expect(at(200).phase, FusionPhase.none);
    // Ohne Ansicht sammelt sich nichts an.
    final quiet = SensorFusion(originUs: 0);
    for (final (kind, t, v) in _ride.take(20000)) {
      if (kind == 'a') quiet.addAccel(_us(t), v[0], v[1], v[2]);
    }
    expect(quiet.takeLive(), isEmpty);
  });

  test('Schübe des Sensors ändern nichts', () {
    final (_, plain) = _run();
    final (_, bursts) = _run(accelAhead: 25);
    String key(FusionEvent e) => '${e.runtimeType} ${e.startUs} ${e.duration.inMicroseconds}';
    expect(bursts.map(key), plain.map(key));
  });

  test('die Halterung der letzten Fahrt: passend bleibt sie, falsch fällt sie', () {
    final (right, rightEvents) = _run(carried: _mount(_mount0));
    expect(right.mountCarried, isTrue);
    expect(right.mountDroppedAt, isNull);
    expect(rightEvents.whereType<WheelieEvent>(), hasLength(4));

    final (wrong, wrongEvents) = _run(carried: _mount(_mm(_rx(_rad(90)), _mount0)));
    expect(wrong.mountDroppedAt, lessThanOrEqualTo(10));
    expect(wrong.forwardAt, lessThanOrEqualTo(45));
    expect(wrongEvents.whereType<WheelieEvent>(), hasLength(4));
  });

  test('FusionMount als JSON', () {
    const m = FusionMount(up: (0.0, 0.6, 0.8), forward: (1.0, 0.0, 0.0));
    final back = FusionMount.fromJson(m.toJson())!;
    expect(back.up, m.up);
    expect(back.forward, m.forward);
    expect(FusionMount.fromJson({'up': [0, 0], 'forward': [1, 0, 0]}), isNull);
    expect(FusionMount.fromJson('kaputt'), isNull);
  });
}
