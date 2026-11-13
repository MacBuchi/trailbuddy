// Das Uhr-Protokoll (#510): Tabellen gegen die Uhr-Seite, Packen für den
// Feedback-Text, Ablage auf dem Telefon, Empfang mit Fahrt und „hallo".
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/settings.dart';
import 'package:trailbuddy/data/providers.dart';
import 'package:trailbuddy/features/garmin/garmin_bridge.dart';
import 'package:trailbuddy/features/garmin/watch_event_store.dart';
import 'package:trailbuddy/features/garmin/watch_events.dart';
import 'package:trailbuddy/features/garmin/watch_ride.dart';
import 'package:trailbuddy/features/garmin/watch_ride_inbox.dart';
import 'package:trailbuddy/features/rides/ride_providers.dart';
import 'package:trailbuddy/features/rides/ride_service.dart';

import '../fakes/fake_garmin.dart';
import '../fakes/fake_rides.dart';
import '../fakes/fake_settings.dart';

/// Der Ring aus `eventsReplayPauseDiscardNo` (CoreTests.mc) und dem
/// Selbsttest von `tool/garmin_events.py`: Start, Route geladen, START,
/// Aufnahme, Fix auf der Linie, START, Pause, `rp`, Verwerfen, Nein.
final kSample = [
  packWatchEvent(0, 0, 0), packWatchEvent(8, 4, 0), packWatchEvent(1, 0, 1), packWatchEvent(8, 1, 1),
  packWatchEvent(9, 1, 6), packWatchEvent(1, 0, 31), packWatchEvent(8, 2, 31), packWatchEvent(6, 0, 31),
  packWatchEvent(2, 2, 32), packWatchEvent(2, 4, 33),
];

/// Dieselbe Zeichenkette prüft `tool/garmin_events.py --self-test`.
const kSampleEncoded = 'ev1:AABEAAgBQQBJBQgZQgAwABIBFAE';

void main() {
  group('Tabellen', () {
    test('die Arten der Nachrichten stehen wie in EventLog.mc', () {
      final mc = File('garmin/source/EventLog.mc').readAsStringSync();
      expect(mc, contains('const IN_T = "$kWatchEventsIn";'));
      expect(mc, contains('const OUT_T = "$kWatchEventsOut";'));
      expect(mc, contains('const SIZE = $kWatchEventsMax;'));
      final py = File('tool/garmin_events.py').readAsStringSync();
      expect(py, contains(kSampleEncoded), reason: 'Python liest dieselbe Form');
    });

    test('Nachrichten nach Art und Stelle, unbekannte als ?', () {
      expect(watchEventParts(packWatchEvent(3, 1, 0)), (kind: 'in', detail: 'wq'));
      expect(watchEventParts(packWatchEvent(4, 0, 0)), (kind: 'in', detail: 'b'));
      expect(watchEventParts(packWatchEvent(4, 7, 0)), (kind: 'in', detail: '?'));
      expect(watchEventParts(packWatchEvent(5, 0, 0)), (kind: 'out', detail: 'hi'));
      expect(watchEventParts(packWatchEvent(5, 7, 0)), (kind: 'out', detail: 're'));
      expect(watchEventParts(packWatchEvent(6, 3, 0)), (kind: 'out', detail: 'w'));
      expect(watchEventParts(packWatchEvent(1, 2, 0)), (kind: 'key', detail: '2'));
    });

    test('packen und entpacken, auch mit Vorzeichen', () {
      for (final (k, d, s) in [(0, 1, 0), (10, 3, 0xFFFFFF), (31, 7, 5)]) {
        expect(unpackWatchEvent(packWatchEvent(k, d, s)), (kind: k, detail: d, sec: s));
      }
      expect(packWatchEvent(31, 7, 5), isNegative);
    });

    test('nur eine Liste aus Zahlen, höchstens 120', () {
      expect(watchEventsOf([1, 2]), [1, 2]);
      expect(watchEventsOf(null), isNull);
      expect(watchEventsOf([]), isNull);
      expect(watchEventsOf([1, 'x']), isNull);
      expect(watchEventsOf(List.filled(121, 1)), isNull);
    });
  });

  group('Feedback-Text', () {
    test('die Probe: dieselbe Zeichenkette wie in Python', () {
      expect(encodeWatchEvents(kSample), kSampleEncoded);
      expect(decodeWatchEvents('Uhr-Protokoll (10 Schritte): $kSampleEncoded'), kSample);
    });

    test('120 Ereignisse über Stunden passen neben einen Text', () {
      final ring = [for (var i = 0; i < 120; i++) packWatchEvent(i % 11, i % 8, i * 600)];
      final s = encodeWatchEvents(ring);
      expect(s.length, lessThan(650));
      expect(decodeWatchEvents(s), ring);
    });

    test('kaputt ist null', () {
      expect(decodeWatchEvents('kein Protokoll'), isNull);
      expect(decodeWatchEvents('ev1:AA'), isNull);
    });
  });

  group('Ablage', () {
    test('die letzten fünf, ohne Doppel, das neueste zuerst', () async {
      final dir = await Directory.systemTemp.createTemp('watch_events');
      addTearDown(() => dir.delete(recursive: true));
      final store = FileWatchEventStore(baseDir: dir);
      expect(await store.latest(), isNull);
      final t0 = DateTime.utc(2026, 11, 12);
      for (var i = 0; i < 7; i++) {
        await store.add(WatchEventLog(at: t0.add(Duration(hours: i)), fromCrash: i.isOdd, events: [i + 1]));
      }
      await store.add(WatchEventLog(at: t0.add(const Duration(hours: 9)), fromCrash: true, events: [7]));
      final latest = await store.latest();
      expect(latest!.events, [7]);
      expect(latest.at, t0.add(const Duration(hours: 6)), reason: 'dasselbe Protokoll bleibt eins');
      final raw = File('${dir.path}/rides/watch_events.json').readAsStringSync();
      expect(RegExp('"ev"').allMatches(raw).length, kWatchEventLogsKept);
    });
  });

  group('Empfang', () {
    late FakeGarminBridge bridge;
    late MemoryWatchEventStore events;
    late ProviderContainer container;

    setUp(() {
      bridge = FakeGarminBridge.connected();
      events = MemoryWatchEventStore();
      container = ProviderContainer(overrides: [
        garminBridgeProvider.overrideWithValue(bridge),
        rideStoreProvider.overrideWithValue(FakeRideStore()),
        rideFixProvider.overrideWithValue(FakeRideFix().call),
        rideServiceBridgeProvider.overrideWithValue(FakeRideServiceBridge()),
        rideServiceProvider.overrideWithValue(FakeRideService()),
        ridePermissionProvider.overrideWithValue(() async => null),
        settingsProvider.overrideWithValue(FakeSettings()),
        currentUserIdProvider.overrideWithValue('me'),
        watchEventStoreProvider.overrideWithValue(events),
      ]);
      addTearDown(container.dispose);
    });

    Future<void> flush() => Future<void>.delayed(Duration.zero);

    test('„hallo" nach einem Absturz legt das Protokoll ab, ohne ev nichts', () async {
      await container.read(watchRideInboxProvider.notifier).start();
      bridge.answer({'t': 'hi', 'v': 2});
      await flush();
      expect(events.logs, isEmpty);
      bridge.answer({'t': 'hi', 'v': 2, 'ev': kSample});
      await flush();
      expect(events.logs.single.fromCrash, isTrue);
      expect(events.logs.single.events, kSample);
    });

    test('die Fahrt bringt ihr Protokoll in der ersten Nachricht', () async {
      await container.read(watchRideInboxProvider.notifier).start();
      final points = [for (var i = 0; i < 40; i++) (i * 250, 100, 1700000000 + i * 5, 4000, 0)];
      bridge.answer({'t': kWatchRide, 'id': '1700000000', 'p': 0, 'n': 1, 'c': encodeWatchRide(points),
          'ev': kSample});
      await flush();
      await flush();
      expect(events.logs.single.fromCrash, isFalse);
      expect(events.logs.single.events, kSample);
    });
  });
}
