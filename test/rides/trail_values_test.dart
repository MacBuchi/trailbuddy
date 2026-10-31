import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/rides/sensor_fusion.dart';
import 'package:trailbuddy/features/rides/sensor_log.dart';
import 'package:trailbuddy/features/rides/trail_values.dart';

import '../fakes/l10n_de.dart';

const _s = 1000000;

void main() {
  group('parseAirtimeLog', () {
    test('liest die Zeilen, die der Logger schreibt, und nimmt die letzte Antwort', () {
      final at = DateTime.utc(2026, 10, 31, 12);
      final text = [
        wheelieEventLine(const WheelieEvent(
            startUs: 10 * _s, duration: Duration(milliseconds: 1500), lengthM: 9.4, maxTiltDeg: 31)),
        jumpEventLine(const JumpEvent(
            startUs: 20 * _s, duration: Duration(milliseconds: 620), landingG: 2.9, upright: true, plausible: true)),
        stoppieEventLine(const StoppieEvent(
            startUs: 30 * _s, duration: Duration(milliseconds: 900), maxTiltDeg: 17, decel: 1.8, landingG: 1.7)),
        jumpAnswerLine(at, startUs: 20 * _s, yes: false),
        // Umentschieden: „Stimmt" nach „War keiner" zählt wieder.
        stoppieAnswerLine(at, startUs: 30 * _s, yes: false),
        stoppieAnswerLine(at, startUs: 30 * _s, yes: true),
        // Dieselbe Kennung als Wheelie-Antwort trifft den Sprung nicht.
        wheelieAnswerLine(at, startUs: 30 * _s, yes: false),
        'j,40000000,0.5', // nach einem Prozess-Kill halb geschrieben
      ].join();
      final log = parseAirtimeLog(text);
      expect(log.events, hasLength(3));
      final w = log.events[0] as WheelieEvent, j = log.events[1] as JumpEvent, s = log.events[2] as StoppieEvent;
      expect((w.startUs, w.duration.inMilliseconds, w.lengthM, w.maxTiltDeg), (10 * _s, 1500, 9.4, 31.0));
      expect((j.landingG, j.plausible, j.duration.inMilliseconds), (2.9, true, 620));
      expect((s.maxTiltDeg, s.decel, s.landingG), (17.0, 1.8, 1.7));
      expect(log.kept, [w, s], reason: 'der Sprung war keiner');
    });
  });

  group('TrailValues.of', () {
    const events = <FusionEvent>[
      JumpEvent(startUs: 10 * _s, duration: Duration(milliseconds: 500), landingG: 2.5, upright: true, plausible: true),
      JumpEvent(startUs: 12 * _s, duration: Duration(milliseconds: 800), landingG: 3.1, upright: true, plausible: true),
      // Abgesetzt oder umgefallen: zählt nicht, auch nicht für Max G.
      JumpEvent(startUs: 14 * _s, duration: Duration(milliseconds: 900), landingG: 7.9, upright: false, plausible: false),
      WheelieEvent(startUs: 15 * _s, duration: Duration(seconds: 2), lengthM: 7.6, maxTiltDeg: 25),
      WheelieEvent(startUs: 16 * _s, duration: Duration(seconds: 1), lengthM: 3.0, maxTiltDeg: 20),
      StoppieEvent(startUs: 17 * _s, duration: Duration(milliseconds: 700), maxTiltDeg: 12, decel: 2, landingG: 1.5),
      StoppieEvent(startUs: 18 * _s, duration: Duration(milliseconds: 400), maxTiltDeg: 19, decel: 3, landingG: 1.9),
      JumpEvent(startUs: 30 * _s, duration: Duration(seconds: 1), landingG: 2, upright: true, plausible: true),
    ];

    test('zählt nur plausible Sprünge, im Fenster, beide Ränder eingeschlossen', () {
      final v = TrailValues.of(events, fromUs: 10 * _s, toUs: 18 * _s);
      expect(v.jumps, 2);
      expect(v.airS, closeTo(1.3, 1e-9));
      expect(v.longestJumpS, 0.8);
      expect(v.maxG, 3.1);
      expect((v.wheelies, v.longestWheelieM), (2, 7.6));
      expect((v.stoppies, v.longestStoppieS, v.steepestStoppieDeg), (2, 0.7, 19.0));
    });

    test('ohne Ereignis im Fenster leer und ohne Max G', () {
      final v = TrailValues.of(events, fromUs: 19 * _s, toUs: 29 * _s);
      expect(v.isEmpty, isTrue);
      expect(v.maxG, isNull);
      expect(trailValuesLine(l10nDe, v), isNull);
    });

    test('die Zeile nennt nur, was es gab, in deutscher Schreibweise', () {
      expect(trailValuesLine(l10nDe, TrailValues.of(events, fromUs: 10 * _s, toUs: 18 * _s)),
          'Air 1,3 s (2×) · 3,1 G · Wheelie 2× (bis 8 m) · Stoppie 2×');
      expect(trailValuesLine(l10nDe, TrailValues.of(events, fromUs: 15 * _s, toUs: 16 * _s)), 'Wheelie 2× (bis 8 m)');
    });
  });

  test('Kanal und Datei zusammen: jedes Ereignis einmal, die Antwort der App gilt', () {
    const a = WheelieEvent(startUs: 1, duration: Duration(seconds: 1), lengthM: 5, maxTiltDeg: 20);
    const b = JumpEvent(startUs: 2, duration: Duration(milliseconds: 400), landingG: 2, upright: true, plausible: true);
    final saved = const AirtimeLog(events: [a, b]).withAnswer(b, yes: false);
    final live = AirtimeLog.empty.withEvent(b).withEvent(b).withAnswer(a, yes: false);
    final both = saved.merge(live);
    expect(both.events, [a, b]);
    expect(both.kept, isEmpty);
    expect(both.withAnswer(b, yes: true).kept, [b], reason: '„Stimmt" danach nimmt es zurück');
  });

  test('die Ereignis-Datei liegt neben den Rohdaten', () {
    expect(sensorEventsPath('/a/rides/sensors/20261031T120000Z.csv'), '/a/rides/sensors/20261031T120000Z.events.csv');
  });
}
