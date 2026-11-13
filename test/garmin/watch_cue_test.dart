// Sprung und Wheelie an der Uhr (#514, Konzept-Garmin 11): `on` in den
// Bestwerten, solange das Handy mit gelernter Halterung erkennt, und ein
// kurzer Hinweis `c` je Ereignis — höchstens einer je 10 s, keiner, der
// beim Absenden älter als 8 s ist. Die Seite der Uhr prüft der Ablaufkern
// (`CoreTests.mc`, `cue*`) und der Gesprächskatalog (`sprung-hinweis`).
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/garmin/watch_route.dart';
import 'package:trailbuddy/features/rides/airtime_live.dart';
import 'package:trailbuddy/features/rides/airtime_message.dart';
import 'package:trailbuddy/features/rides/sensor_fusion.dart';
import 'package:trailbuddy/features/rides/trail_values.dart' show AirtimeLog;

import 'watch_phone.dart';

const _file = '/rides/sensors/r1.csv';

FusionLive _tick(int tUs, {bool mount = true}) => FusionLive(
    tUs: tUs, pitchDeg: mount ? 2 : double.nan, speedKmh: 15, upKnown: mount, phase: FusionPhase.none);

JumpEvent _jump(int startUs, {int ms = 900, bool plausible = true}) => JumpEvent(
    startUs: startUs, duration: Duration(milliseconds: ms), landingG: 2.4, upright: true, plausible: plausible);

void main() {
  group('pur', () {
    test('erkennt nur mit gelernter Halterung und frischem Takt', () {
      const now = 100000000;
      expect(watchDetecting(null, now), isFalse);
      expect(watchDetecting(_tick(now - 1000000, mount: false), now), isFalse, reason: 'Halterung lernt noch');
      expect(watchDetecting(_tick(now - 1000000), now), isTrue);
      expect(watchDetecting(_tick(now - kWatchDetectFresh.inMicroseconds), now), isTrue);
      expect(watchDetecting(_tick(now - kWatchDetectFresh.inMicroseconds - 1), now), isFalse,
          reason: 'die Takte bleiben aus');
    });

    test('Hinweis: Flugzeit und Stoppie in ms, Wheelie in Metern; zu alt oder unplausibel nicht', () {
      const now = 100000000;
      expect(watchCueOf(_jump(now - 3000000), now), {'t': kWatchCue, 'k': 'air', 'v': 900});
      expect(
          watchCueOf(
              const WheelieEvent(
                  startUs: 90000000, duration: Duration(seconds: 3), lengthM: 12.4, maxTiltDeg: 30),
              now),
          {'t': kWatchCue, 'k': 'wh', 'v': 12});
      expect(
          watchCueOf(
              const StoppieEvent(
                  startUs: 95000000,
                  duration: Duration(milliseconds: 700),
                  maxTiltDeg: 15,
                  decel: 2,
                  landingG: 1.5),
              now),
          {'t': kWatchCue, 'k': 'st', 'v': 700});
      // Das Ende zählt, nicht der Beginn: 8 s nach der Landung noch, danach nicht.
      final edge = now - kWatchCueMaxAge.inMicroseconds - 900000;
      expect(watchCueOf(_jump(edge), now), isNotNull);
      expect(watchCueOf(_jump(edge - 1), now), isNull);
      expect(watchCueOf(_jump(now - 3000000, plausible: false), now), isNull);
    });

    test('Bestwerte tragen `on`; ohne Ereignis gibt es sie nur mit Erkennung', () {
      expect(watchBestsOf(AirtimeLog.empty), isNull);
      expect(watchBestsOf(AirtimeLog.empty, on: true),
          {'t': kWatchBests, 'on': 1, 'jn': 0, 'ja': 0, 'wn': 0, 'wl': 0, 'wa': 0, 'sn': 0});
    });
  });

  group('am Handy mit Uhr', () {
    late WatchPhone phone;

    Future<void> stored(WidgetTester tester) async {
      phone = WatchPhone()..bridge.autoStore = true;
      await phone.open();
      phone.navigate();
      for (var i = 0; i < 200 && phone.sync.phase.name != 'stored'; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(phone.sync.phase.name, 'stored');
    }

    AirtimeLiveNotifier live() => phone.c.read(airtimeLiveProvider.notifier);
    List<Map<String, Object>> of(String t) => [for (final m in phone.sent) if (m['t'] == t) m];

    testWidgets('an mit gelernter Halterung, aus, sobald die Takte ausbleiben', (tester) async {
      await stored(tester);
      expect(of('b'), isEmpty, reason: 'ohne Erkennung und ohne Ereignis keine Bestwerte');

      live().accept(encodeAirtimeLive(_file, [_tick(phone.clockUs - 1500000, mount: false)]));
      await tester.pump();
      expect(of('b'), isEmpty, reason: 'die Halterung lernt noch: kein Zeichen an der Uhr');

      live().accept(encodeAirtimeLive(_file, [_tick(phone.clockUs - 1500000)]));
      await tester.pump();
      expect(of('b').single['on'], 1);

      // Weitere Takte ändern nichts: kein zweites `b`.
      phone.clockUs += 1000000;
      live().accept(encodeAirtimeLive(_file, [_tick(phone.clockUs - 1500000)]));
      await tester.pump();
      expect(of('b'), hasLength(1));

      // Dann nichts mehr — der Takt des Handys merkt es binnen 2 s.
      phone.clockUs += kWatchDetectFresh.inMicroseconds;
      await tester.pump(const Duration(seconds: 2));
      expect(of('b').last['on'], 0);
      expect(of('b'), hasLength(2));
      phone.c.dispose();
    });

    testWidgets('ein Sprung: Hinweis und Bestwerte in einer Sendung; der nächste binnen 10 s nur als Bestwert',
        (tester) async {
      await stored(tester);
      live().accept(encodeAirtimeLive(_file, [_tick(phone.clockUs - 1500000)]));
      await tester.pump();

      live().accept(encodeAirtimeEvent(_file, _jump(phone.clockUs - 3000000)));
      await tester.pump();
      final batch = phone.bridge.sent.last;
      expect(batch.map((m) => m['t']), ['c', 'b'], reason: 'der Hinweis zuerst');
      expect(batch.first, {'t': 'c', 'k': 'air', 'v': 900});
      expect(batch.last['jn'], 1);

      phone.clockUs += 6000000;
      live().accept(encodeAirtimeLive(_file, [_tick(phone.clockUs - 1500000)]));
      live().accept(encodeAirtimeEvent(_file, _jump(phone.clockUs - 3000000, ms: 1200)));
      await tester.pump();
      expect(of('c'), hasLength(1), reason: 'binnen 10 s kein zweiter Hinweis');
      expect(of('b').last['ja'], 1200);

      phone.clockUs += 5000000;
      live().accept(encodeAirtimeLive(_file, [_tick(phone.clockUs - 1500000)]));
      live().accept(encodeAirtimeEvent(_file, _jump(phone.clockUs - 3000000, ms: 700)));
      await tester.pump();
      expect(of('c'), hasLength(2));
      expect(of('c').last['v'], 700);
      phone.c.dispose();
    });

    testWidgets('ein Ereignis, das erst spät ankommt (die App ging auf), wird kein Hinweis', (tester) async {
      await stored(tester);
      live().accept(encodeAirtimeLive(_file, [_tick(phone.clockUs - 1500000)]));
      live().accept(encodeAirtimeEvent(_file, _jump(phone.clockUs - 20000000)));
      await tester.pump();
      expect(of('c'), isEmpty);
      expect(of('b').last['jn'], 1, reason: 'der Bestwert zählt trotzdem');
      phone.c.dispose();
    });
  });
}
