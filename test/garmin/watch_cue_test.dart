// Sprung und Wheelie an der Uhr (#514, Konzept-Garmin 11): `on` in den
// Bestwerten, solange das Handy erkennt, und ein
// kurzer Hinweis `c` je Ereignis — höchstens einer je 10 s, keiner, der
// beim Absenden älter als 8 s ist. Die Seite der Uhr prüft der Ablaufkern
// (`CoreTests.mc`, `cue*`) und der Gesprächskatalog (`sprung-hinweis`).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/garmin/watch_route.dart';
import 'package:trailbuddy/features/rides/airtime_live.dart';
import 'package:trailbuddy/features/rides/airtime_message.dart';
import 'package:trailbuddy/features/rides/pocket_watch.dart'
    show kPocketLandingG;
import 'package:trailbuddy/features/rides/sensor_fusion.dart';
import 'package:trailbuddy/features/rides/trail_values.dart' show AirtimeLog;
import 'package:trailbuddy/features/rides/wheelie_notify.dart'
    show answerAirtimeInApp;
import 'package:trailbuddy/features/rides/sensor_log.dart'
    show sensorEventsPath;

import 'watch_phone.dart';

const _file = '/rides/sensors/r1.csv';

FusionLive _tick(int tUs, {bool mount = true}) => FusionLive(
  tUs: tUs,
  pitchDeg: mount ? 2 : double.nan,
  speedKmh: 15,
  upKnown: mount,
  phase: FusionPhase.none,
);

JumpEvent _jump(int startUs, {int ms = 900, bool plausible = true}) =>
    JumpEvent(
      startUs: startUs,
      duration: Duration(milliseconds: ms),
      landingG: 2.4,
      upright: true,
      plausible: plausible,
    );

void main() {
  group('pur', () {
    test('erkennt bei frischem Takt auch ohne gelernte Halterung', () {
      const now = 100000000;
      expect(watchDetecting(null, now), isFalse);
      expect(watchDetecting(_tick(now - 1000000, mount: false), now), isTrue);
      expect(watchDetecting(_tick(now - 1000000), now), isTrue);
      expect(
        watchDetecting(_tick(now - kWatchDetectFresh.inMicroseconds), now),
        isTrue,
      );
      expect(
        watchDetecting(_tick(now - kWatchDetectFresh.inMicroseconds - 1), now),
        isFalse,
        reason: 'die Takte bleiben aus',
      );
    });

    test(
      'Hinweis: Flugzeit und Stoppie in ms, Wheelie in Metern; zu alt oder unplausibel nicht',
      () {
        const now = 100000000;
        expect(watchCueOf(_jump(now - 3000000), now), {
          't': kWatchCue,
          'k': 'air',
          'v': 900,
          's': '97000000',
        });
        expect(
          watchCueOf(
            const WheelieEvent(
              startUs: 90000000,
              duration: Duration(seconds: 3),
              lengthM: 12.4,
              maxTiltDeg: 30,
            ),
            now,
          ),
          {'t': kWatchCue, 'k': 'wh', 'v': 12, 's': '90000000'},
        );
        expect(
          watchCueOf(
            const StoppieEvent(
              startUs: 95000000,
              duration: Duration(milliseconds: 700),
              maxTiltDeg: 15,
              decel: 2,
              landingG: 1.5,
            ),
            now,
          ),
          {'t': kWatchCue, 'k': 'st', 'v': 700, 's': '95000000'},
        );
        // Das Ende zählt, nicht der Beginn: 8 s nach der Landung noch, danach nicht.
        final edge = now - kWatchCueMaxAge.inMicroseconds - 900000;
        expect(watchCueOf(_jump(edge), now), isNotNull);
        expect(watchCueOf(_jump(edge - 1), now), isNull);
        expect(watchCueOf(_jump(now - 3000000, plausible: false), now), isNull);
      },
    );

    test(
      'in der Tasche (#612): nur Sprünge mit harter Landung, auch unplausibel',
      () {
        const now = 100000000;
        JumpEvent jump({required double g, bool plausible = true}) => JumpEvent(
          startUs: now - 3000000,
          duration: const Duration(milliseconds: 900),
          landingG: g,
          upright: true,
          plausible: plausible,
        );
        final hard = jump(g: kPocketLandingG);
        expect(watchCueOf(hard, now, pocket: true), {
          't': kWatchCue,
          'k': 'air',
          'v': 900,
          's': '97000000',
        });
        expect(
          watchCueOf(jump(g: kPocketLandingG - 0.1), now, pocket: true),
          isNull,
          reason: 'weiche Landung: das Bein, kein Sprung',
        );
        expect(
          watchCueOf(jump(g: 4, plausible: false), now, pocket: true),
          isNotNull,
          reason: 'in der Tasche soll man ihn bewerten',
        );
        expect(
          watchCueOf(jump(g: 4, plausible: false), now),
          isNull,
          reason: 'am Lenker bleibt ein unplausibler Sprung stumm',
        );
        for (final e in const [
          WheelieEvent(
            startUs: 97000000,
            duration: Duration(seconds: 2),
            lengthM: 9,
            maxTiltDeg: 30,
          ),
          StoppieEvent(
            startUs: 97000000,
            duration: Duration(milliseconds: 700),
            maxTiltDeg: 15,
            decel: 2,
            landingG: 5,
          ),
        ]) {
          expect(watchCueOf(e, now, pocket: true), isNull);
        }
      },
    );

    test(
      'Bestwerte tragen `on`; ohne Ereignis gibt es sie nur mit Erkennung',
      () {
        expect(watchBestsOf(AirtimeLog.empty), isNull);
        expect(watchBestsOf(AirtimeLog.empty, on: true), {
          't': kWatchBests,
          'on': 1,
          'jn': 0,
          'ja': 0,
          'wn': 0,
          'wl': 0,
          'wa': 0,
          'sn': 0,
        });
      },
    );
  });

  testWidgets('Uhr und Live-Ansicht schreiben dieselbe Sprungantwort', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('watch-answer-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = '${dir.path}/ride.csv';
    final writes = <Future<void> Function()>[];
    final phone = WatchPhone(
      overrides: [
        airtimeAnswerProvider.overrideWithValue(({
          required actionId,
          required file,
          startUs,
          notificationId,
        }) async {
          writes.add(
            () => answerAirtimeInApp(
              actionId: actionId,
              file: file,
              startUs: startUs,
              notificationId: notificationId,
            ),
          );
        }),
      ],
    );
    await phone.open();
    addTearDown(phone.c.dispose);
    final live = phone.c.read(airtimeLiveProvider.notifier);
    final event = _jump(phone.clockUs - 3000000);
    live.accept(encodeAirtimeEvent(file, event));
    final message = {
      't': kWatchCueAnswer,
      'k': 'air',
      's': event.startUs.toString(),
      'y': 0,
    };
    phone.bridge.answer({...message, 'k': 'wh'});
    phone.bridge.answer({...message, 's': '1700000000000000'});
    await tester.pump();
    expect(phone.c.read(airtimeLiveProvider).pending, [isA<JumpEvent>()]);
    expect(File(file).existsSync(), isFalse);

    expect(writes, isEmpty);
    phone.bridge.answer(message);
    await tester.pump();
    expect(writes, hasLength(1));
    expect(phone.c.read(airtimeLiveProvider).log.kept, isEmpty);
    await live.answer(event, yes: true);
    expect(writes, hasLength(2));

    final written = await tester.runAsync(() async {
      for (final write in writes) {
        await write();
      }
      return [
        await File(file).readAsLines(),
        await File(sensorEventsPath(file)).readAsLines(),
      ];
    });
    final raw = written!.first;
    expect(written.last, raw);
    expect(raw.map((line) => line.split(',').first), ['k', 'k']);
    expect(raw.map((line) => line.split(',')[2]), [
      event.startUs.toString(),
      event.startUs.toString(),
    ]);
    expect(raw.map((line) => line.split(',').last), ['0', '1']);
    final state = phone.c.read(airtimeLiveProvider);
    expect(state.pending, isEmpty);
    expect(state.log.kept, [isA<JumpEvent>()]);
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
    List<Map<String, Object>> of(String t) => [
      for (final m in phone.sent)
        if (m['t'] == t) m,
    ];

    testWidgets('an beim ersten Takt, aus, sobald die Takte ausbleiben', (
      tester,
    ) async {
      await stored(tester);
      expect(
        of('b'),
        isEmpty,
        reason: 'ohne Erkennung und ohne Ereignis keine Bestwerte',
      );

      live().accept(
        encodeAirtimeLive(_file, [
          _tick(phone.clockUs - 1500000, mount: false),
        ]),
      );
      await tester.pump();
      expect(of('b').single['on'], 1);

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

    testWidgets(
      'ein Sprung: Hinweis und Bestwerte in einer Sendung; der nächste binnen 10 s nur als Bestwert',
      (tester) async {
        await stored(tester);
        live().accept(
          encodeAirtimeLive(_file, [_tick(phone.clockUs - 1500000)]),
        );
        await tester.pump();

        live().accept(
          encodeAirtimeEvent(_file, _jump(phone.clockUs - 3000000)),
        );
        await tester.pump();
        final batch = phone.bridge.sent.last;
        expect(batch.map((m) => m['t']), [
          'c',
          'b',
        ], reason: 'der Hinweis zuerst');
        expect(batch.first, {
          't': 'c',
          'k': 'air',
          'v': 900,
          's': (phone.clockUs - 3000000).toString(),
        });
        expect(batch.last['jn'], 1);

        phone.clockUs += 6000000;
        live().accept(
          encodeAirtimeLive(_file, [_tick(phone.clockUs - 1500000)]),
        );
        live().accept(
          encodeAirtimeEvent(_file, _jump(phone.clockUs - 3000000, ms: 1200)),
        );
        await tester.pump();
        expect(
          of('c'),
          hasLength(1),
          reason: 'binnen 10 s kein zweiter Hinweis',
        );
        expect(of('b').last['ja'], 1200);

        phone.clockUs += 5000000;
        live().accept(
          encodeAirtimeLive(_file, [_tick(phone.clockUs - 1500000)]),
        );
        live().accept(
          encodeAirtimeEvent(_file, _jump(phone.clockUs - 3000000, ms: 700)),
        );
        await tester.pump();
        expect(of('c'), hasLength(2));
        expect(of('c').last['v'], 700);
        phone.c.dispose();
      },
    );

    testWidgets(
      'ein Ereignis, das erst spät ankommt (die App ging auf), wird kein Hinweis',
      (tester) async {
        await stored(tester);
        live().accept(
          encodeAirtimeLive(_file, [_tick(phone.clockUs - 1500000)]),
        );
        live().accept(
          encodeAirtimeEvent(_file, _jump(phone.clockUs - 20000000)),
        );
        await tester.pump();
        expect(of('c'), isEmpty);
        expect(of('b').last['jn'], 1, reason: 'der Bestwert zählt trotzdem');
        phone.c.dispose();
      },
    );
  });
}
