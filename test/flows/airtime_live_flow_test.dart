// Die Live-Ansicht der Erkennung (#36, Betreiber 2026-10-31) durch die
// echte Karte: Was der Dienst schickt (`airtime_message.dart`), zeigt ein
// kleines Fenster über der Karte — Winkel, Zustand, laufende Zeit mit
// Spitze —, abgespielt nach der Zeit der Takte; ein fertiges Ereignis
// fragt dort „Stimmt" / „War keiner", und die Antwort geht denselben Weg
// wie der Knopf im Banner.
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/map/map_screen.dart';
import 'package:trailbuddy/features/rides/airtime_live.dart';
import 'package:trailbuddy/features/rides/airtime_message.dart';
import 'package:trailbuddy/features/rides/ride_providers.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/features/rides/sensor_fusion.dart';
import 'package:trailbuddy/features/rides/wheelie_notify.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_rides.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

void main() {
  const file = '/data/rides/sensors/20261031T090000Z.csv';
  final t0 = DateTime.utc(2026, 10, 31, 9).microsecondsSinceEpoch;

  FusionLive tick(double s,
          {double pitch = 2, FusionPhase phase = FusionPhase.none, double? phaseStart, double peak = 0}) =>
      FusionLive(
          tUs: t0 + (s * 1e6).round(),
          pitchDeg: pitch,
          speedKmh: 18,
          upKnown: true,
          phase: phase,
          phaseStartUs: phaseStart == null ? null : t0 + (phaseStart * 1e6).round(),
          peakDeg: peak);

  group('Nachrichten', () {
    test('Takte und Ereignisse kommen an, wie sie losgingen', () {
      final live = decodeAirtimeMessage(encodeAirtimeLive(file, [
        tick(1, pitch: 24.34, phase: FusionPhase.wheelie, phaseStart: 0.5, peak: 27.06),
        FusionLive(tUs: t0, pitchDeg: double.nan, speedKmh: 0, upKnown: false, phase: FusionPhase.none),
      ])) as AirtimeLiveMessage;
      expect(live.file, file);
      final a = live.ticks.first, b = live.ticks.last;
      expect((a.tUs, a.pitchDeg, a.phase, a.phaseStartUs, a.peakDeg, a.speedKmh, a.upKnown),
          (t0 + 1000000, 24.3, FusionPhase.wheelie, t0 + 500000, 27.1, 18.0, true));
      expect(b.mountReady, isFalse);
      expect(b.upKnown, isFalse);

      for (final event in <FusionEvent>[
        WheelieEvent(startUs: t0, duration: const Duration(milliseconds: 1800), lengthM: 12.4, maxTiltDeg: 33.6),
        JumpEvent(startUs: t0, duration: const Duration(milliseconds: 480), landingG: 3.2, upright: true, plausible: false),
        StoppieEvent(
            startUs: t0, duration: const Duration(milliseconds: 900), maxTiltDeg: 17.2, decel: 1.8, landingG: 1.9),
      ]) {
        final back = (decodeAirtimeMessage(encodeAirtimeEvent(file, event)) as AirtimeEventMessage).event;
        expect(back.runtimeType, event.runtimeType);
        expect((back.startUs, back.duration), (event.startUs, event.duration));
      }
      final jump = (decodeAirtimeMessage(encodeAirtimeEvent(file,
              JumpEvent(startUs: t0, duration: Duration.zero, landingG: 3.2, upright: true, plausible: false)))
          as AirtimeEventMessage)
          .event as JumpEvent;
      expect(jump.plausible, isFalse);
    });

    test('Punkte der Fahrt und kaputte Nachrichten sind keine', () {
      expect(decodeAirtimeMessage('{"lat":1}'), isNull);
      expect(decodeAirtimeMessage(42), isNull);
      expect(decodeAirtimeMessage('air:live:{kaputt'), isNull);
      expect(decodeAirtimeMessage('air:event:{"k":"x","f":"a","s":1,"d":1}'), isNull);
    });
  });

  group('Fenster über der Karte', () {
    late FakeBackend backend;
    late FakeRideStore store;
    late FakeRideServiceBridge bridge;
    late FakeRideFix fix;
    late int now;
    late List<({String actionId, String file, int? startUs, int? notificationId})> answers;

    setUp(() {
      backend = FakeBackend();
      final anna = backend.addUser(username: 'anna');
      backend.signInAs(anna.id);
      store = FakeRideStore()..uid = anna.id;
      bridge = FakeRideServiceBridge();
      fix = FakeRideFix()..next = RidePoint(lat: 47.2, lng: 11.4, at: DateTime.utc(2026, 10, 31, 9), accuracyM: 5);
      now = t0;
      answers = [];
    });

    tearDown(() => IsolateNameServer.removePortNameMapping('flutter_foreground_task/isolateComPort'));

    Future<ProviderContainer> startRide(WidgetTester tester) async {
      FlutterForegroundTask.initCommunicationPort();
      await pumpApp(tester, backend,
          settings: FakeSettings(sensorLogEnabled: true),
          rideStore: store,
          rideBridge: bridge,
          rideFix: fix,
          extraOverrides: [
            sensorLogAvailableProvider.overrideWithValue(true),
            airtimeClockProvider.overrideWithValue(() => now),
            airtimeAnswerProvider.overrideWithValue(
                ({required String actionId, required String file, int? startUs, int? notificationId}) async {
              answers.add((actionId: actionId, file: file, startUs: startUs, notificationId: notificationId));
            }),
          ]);
      await tester.tap(find.byKey(const ValueKey('ride-button')));
      await settle(tester);
      return ProviderScope.containerOf(tester.element(find.byType(MapScreen)));
    }

    final window = find.byKey(const ValueKey('airtime-live-window'));
    String text(String key) => (find.byKey(ValueKey(key)).evaluate().single.widget as Text).data!;

    testWidgets('leer, bis der Dienst schickt; dann Winkel, Zustand und Zeit nach der Uhr der Takte',
        (tester) async {
      final container = await startRide(tester);
      expect(bridge.sensorLog, isTrue);
      expect(window, findsNothing, reason: 'noch kein Takt da');

      // Ein Schub von 1 s, 2 s hinter der Uhr: ruhig, dann Front hoch —
      // über denselben Port wie in echt, damit der Weg vom Dienst in die
      // Karte mitgeprüft ist (unter Fake-Zeit käme er nie an).
      now = t0 + 3000000;
      await tester.runAsync(() async {
        FlutterForegroundTask.sendDataToMain(encodeAirtimeLive(file, [
          for (var i = 0; i < 10; i++)
            i < 5
                ? tick(1 + i / 10)
                : tick(1 + i / 10, pitch: 20.0 + i, phase: FusionPhase.wheelie, phaseStart: 1.5, peak: 20.0 + i),
        ]));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
      expect(container.read(rideProvider)!.points, hasLength(1), reason: 'kein Punkt der Fahrt daraus');
      expect(window, findsOneWidget);
      expect(text('airtime-live-angle'), '2°', reason: 'der älteste Takt zuerst');
      expect(text('airtime-live-status'), 'fährt');

      // Verzug 2 s + 0,2 s Zuschlag: nach 1 s auf der Uhr ist der Takt bei
      // 1,8 s dran.
      now += 1000000;
      await tester.pump(const Duration(milliseconds: 16));
      expect(text('airtime-live-angle'), '28°');
      expect(text('airtime-live-status'), 'Front oben');
      expect(text('airtime-live-running'), '0,3 s · max 28°');
      expect(find.textContaining('Verzug'), findsOneWidget);

      // Ans Ende gespielt: Der Ticker hört auf, die Karte kommt zur Ruhe.
      now += 2000000;
      await tester.pump(const Duration(milliseconds: 16));
      expect(text('airtime-live-angle'), '29°');
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('ohne gelernte Halterung kein Winkel, sondern was noch fehlt', (tester) async {
      final container = await startRide(tester);
      container.read(airtimeLiveProvider.notifier).accept(encodeAirtimeLive(file, [
            FusionLive(tUs: t0, pitchDeg: double.nan, speedKmh: 12, upKnown: false, phase: FusionPhase.none),
          ]));
      await tester.pump();
      expect(text('airtime-live-angle'), '–°');
      expect(text('airtime-live-status'), 'Halterung lernt: kurz ruhig fahren');
    });

    testWidgets('ein Ereignis fragt im Fenster; die Antwort geht wie im Banner, das Banner geht weg',
        (tester) async {
      final container = await startRide(tester);
      final live = container.read(airtimeLiveProvider.notifier);
      live.accept(encodeAirtimeLive(file, [tick(1)]));
      final wheelie = WheelieEvent(
          startUs: t0 + 1000000, duration: const Duration(milliseconds: 1800), lengthM: 12, maxTiltDeg: 34);
      final stoppie = StoppieEvent(
          startUs: t0 + 9000000, duration: const Duration(milliseconds: 900), maxTiltDeg: 17, decel: 1.8, landingG: 2);
      live.accept(encodeAirtimeEvent(file, wheelie));
      live.accept(encodeAirtimeEvent(file, stoppie));
      await tester.pump();
      expect(find.text('Wheelie erkannt'), findsOneWidget, reason: 'der älteste zuerst');
      expect(find.text('1,8 s · 12 m · 34° — stimmt das?'), findsOneWidget);
      expect(find.text('+1 weitere'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('airtime-live-yes')));
      await settle(tester);
      expect(answers.single,
          (actionId: kWheelieYes, file: file, startUs: wheelie.startUs, notificationId: wheelieNotificationId(wheelie.startUs)));
      expect(find.text('Stoppie erkannt'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('airtime-live-no')));
      await settle(tester);
      expect(answers.last.actionId, kStoppieNo);
      expect(answers.last.notificationId, stoppieNotificationId(stoppie.startUs));
      expect(find.byKey(const ValueKey('airtime-live-question')), findsNothing);

      // „Sprung verpasst" aus dem Menü (die SnackBar vom Start der Fahrt
      // vorher weg).
      await drainSnackbars(tester);
      await tester.tap(find.byKey(const ValueKey('airtime-live-missed')));
      await settle(tester);
      await tester.tap(find.text('Sprung verpasst').last);
      await settle(tester);
      expect(answers.last, (actionId: kJumpMissed, file: file, startUs: null, notificationId: null));
      expect(find.textContaining('Verpasst gemerkt um'), findsOneWidget);
    });

    testWidgets('verkleinert zum Knopf mit der Zahl der offenen Fragen; mit der Fahrt ist es weg',
        (tester) async {
      final container = await startRide(tester);
      final live = container.read(airtimeLiveProvider.notifier);
      live.accept(encodeAirtimeLive(file, [tick(1)]));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('airtime-live-collapse')));
      await settle(tester);
      expect(window, findsNothing);
      live.accept(encodeAirtimeEvent(
          file, JumpEvent(startUs: t0, duration: const Duration(milliseconds: 400), landingG: 2, upright: true, plausible: true)));
      await tester.pump();
      expect(find.descendant(of: find.byType(Badge), matching: find.text('1')), findsOneWidget);
      final expand = find.byKey(const ValueKey('airtime-live-expand'));
      expect(tester.getSize(expand).shortestSide, greaterThanOrEqualTo(44), reason: 'A13');
      await tester.tap(expand);
      await settle(tester);
      expect(window, findsOneWidget);
      expect(find.text('Sprung erkannt'), findsOneWidget);

      await container.read(rideProvider.notifier).stop();
      await settle(tester);
      expect(container.read(airtimeLiveProvider).active, isFalse);
      expect(window, findsNothing);
    });
  });
}
