// Die Fahrt von der Uhr (#484): Form der Nachrichten wie
// `garmin/source/RideLog.mc`, Zusammensetzen, Ablegen und Quittieren —
// quittiert wird nur, was auf dem Handy liegt (oder schon lag). Alle
// Koordinaten erfunden, am Äquator.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/settings.dart';
import 'package:trailbuddy/data/providers.dart';
import 'package:trailbuddy/features/garmin/garmin_bridge.dart';
import 'package:trailbuddy/features/garmin/watch_providers.dart';
import 'package:trailbuddy/features/garmin/watch_ride.dart';
import 'package:trailbuddy/features/garmin/watch_ride_inbox.dart';
import 'package:trailbuddy/features/garmin/watch_route.dart';
import 'package:trailbuddy/features/rides/ride_import.dart';
import 'package:trailbuddy/features/rides/ride_providers.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';

import '../fakes/fake_garmin.dart';
import '../fakes/fake_rides.dart';
import '../fakes/fake_settings.dart';

/// [n] Punkte alle 5 s, je 250 · 1e-5° nach Norden, Höhe steigt um 5 dm.
List<(int, int, int, int, int)> ridePoints(int n, {int t0 = 1700000000, int acc = 0}) =>
    [for (var i = 0; i < n; i++) (i * 250, 100, t0 + i * 5, 4000 + i * 5, acc)];

Map<String, Object> rideMessage(String id, int p, int n, List<List<int>> chunks) =>
    {'t': kWatchRide, 'id': id, 'p': p, 'n': n, 'c': chunks};

RidePoint at(int s) => RidePoint(
    lat: 0, lng: 0, at: DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true), accuracyM: 5);

void main() {
  group('Form', () {
    test('Packen und Entpacken: Lage, Zeit, Höhe in dm, Genauigkeit, über Stücke', () {
      final pts = [
        ...ridePoints(70),
        // Sinkende Höhe und schlechtere Genauigkeit kommen mit Vorzeichen zurück.
        (70 * 250, 100, 1700000350, 3500, 1),
      ];
      final chunks = encodeWatchRide(pts);
      expect(chunks.length, 2);
      expect(chunks[0].length, 5 + 2 * 59);
      final decoded = decodeWatchRide(chunks)!;
      expect(decoded.length, 71);
      expect(decoded.first.lat, 0);
      expect(decoded.first.lng, closeTo(0.001, 1e-9));
      expect(decoded.first.at, DateTime.utc(2023, 11, 14, 22, 13, 20));
      expect(decoded.first.altM, 400);
      expect(decoded.first.accuracyM, 5);
      expect(decoded[61].lat, closeTo(0.1525, 1e-9));
      expect(decoded[61].at.difference(decoded[60].at), const Duration(seconds: 5));
      expect(decoded.last.altM, 350);
      expect(decoded.last.accuracyM, 15);
    });

    test('unlesbare Stücke: null', () {
      expect(decodeWatchRide([
        [0, 0, 1700000000, 0]
      ]), isNull);
      expect(decodeWatchRide([
        [9000001, 0, 1700000000, 0, 0]
      ]), isNull);
      // Die Zeit läuft rückwärts.
      final back = encodeWatchRide([(0, 0, 1700000100, 0, 0), (10, 0, 1700000000, 0, 0)]);
      expect(decodeWatchRide(back), isNull);
    });

    test('Nachricht der Uhr: nur in der richtigen Form', () {
      final c = encodeWatchRide(ridePoints(3));
      expect(watchRidePartOf(rideMessage('17', 0, 1, c))?.chunks, c);
      expect(watchRidePartOf({'t': 'w', 'id': '17', 'p': 1, 'n': 1, 'c': c}), isNull);
      expect(watchRidePartOf({'t': 'w', 'id': '17', 'p': 0, 'n': 1, 'c': [
        [1, 2, 'x', 4, 5]
      ]}), isNull);
      expect(watchRidePartOf({'t': 'ok', 'id': '17'}), isNull);
      expect(watchHelloOf({'t': 'hi', 'v': 2, 'rq': ['17', 18, '19']}).rides, ['17', '19']);
      expect(watchRideAckOf('17'), {'t': 'wk', 'id': '17'});
      expect(watchRidePull, {'t': 'wq'});
    });

    test('Uhr und Dart sprechen dieselben Arten', () {
      final app = File('garmin/source/TrailBuddyApp.mc').readAsStringSync();
      expect(app, contains('"$kWatchRidePull".equals(t)'));
      expect(app, contains('"$kWatchRideAck".equals(t)'));
      expect(app, contains('msg["rq"] = rq'));
      final log = File('garmin/source/RideLog.mc').readAsStringSync();
      expect(log, contains('{"t" => "$kWatchRide", "id" => id, "p" => p, "n" => messageCount(entry), "c" => c}'));
      expect(log, contains('static const CHUNK_POINTS = 60;'));
      final kotlin = File('android/app/src/main/kotlin/de/mcbuchi/trailbuddy/GarminBridge.kt').readAsStringSync();
      expect(kotlin, contains('"listen" ->'));
      final io = File('lib/features/garmin/garmin_bridge_io.dart').readAsStringSync();
      expect(io, contains("invokeMethod<bool>('listen'"));
    });
  });

  group('doppelt', () {
    test('eine eigene Fahrt über mindestens die halbe Zeit deckt die der Uhr', () {
      final watch = [at(1000), at(2000)];
      Ride ride(int a, int b, {bool planned = false}) => Ride(
          id: '$a', startedAt: at(a).at, endedAt: at(b).at, points: [at(a), at(b)], planned: planned);
      expect(rideOverlaps(watch, [ride(1400, 3000)]), isTrue);
      expect(rideOverlaps(watch, [ride(1600, 3000)]), isFalse);
      expect(rideOverlaps(watch, [ride(0, 1100)]), isFalse);
      // Eine geplante Fahrt ist keine Messung.
      expect(rideOverlaps(watch, [ride(900, 2100, planned: true)]), isFalse);
    });
  });

  group('Ablegen', () {
    late FakeGarminBridge bridge;
    late FakeRideStore store;
    late FakeSettings settings;
    late ProviderContainer container;

    ProviderContainer make({String? uid = 'me'}) {
      final c = ProviderContainer(overrides: [
        garminBridgeProvider.overrideWithValue(bridge),
        rideStoreProvider.overrideWithValue(store),
        settingsProvider.overrideWithValue(settings),
        currentUserIdProvider.overrideWithValue(uid),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    setUp(() {
      bridge = FakeGarminBridge.connected();
      store = FakeRideStore();
      settings = FakeSettings();
      container = make();
    });

    Future<void> flush() => Future<void>.delayed(Duration.zero);

    test('ohne bekannte Uhr lauscht der Start nicht', () async {
      await container.read(watchRideInboxProvider.notifier).startIfKnown();
      expect(bridge.listens, 0);
      settings.watchSeen = true;
      await container.read(watchRideInboxProvider.notifier).startIfKnown();
      expect(bridge.listens, 1);
      // Gefragt wird die Uhr nicht: Ihre App meldet sich selbst.
      expect(bridge.sent, isEmpty);
    });

    test('das Startblatt merkt sich die Uhr', () async {
      await container.read(watchStatusProvider.future);
      expect(settings.watchSeen, isTrue);
      expect(bridge.listens, 1);
    });

    test('„hallo" mit wartenden Fahrten: schick', () async {
      await container.read(watchRideInboxProvider.notifier).start();
      bridge.answer({'t': 'hi', 'v': 2});
      await flush();
      expect(bridge.rideAnswers, isEmpty);
      bridge.answer({'t': 'hi', 'v': 2, 'rq': ['1700000000']});
      await flush();
      expect(bridge.rideAnswers, [watchRidePull]);
    });

    test('zusammengesetzt, abgelegt, erst dann quittiert — und nur einmal', () async {
      await container.read(watchRideInboxProvider.notifier).start();
      final chunks = encodeWatchRide(ridePoints(400));
      expect(chunks.length, 7);
      bridge.answer(rideMessage('1700000000', 1, 2, chunks.sublist(6)));
      await flush();
      expect(bridge.rideAnswers, isEmpty);
      expect(store.rides, isEmpty);
      bridge.answer(rideMessage('1700000000', 0, 2, chunks.sublist(0, 6)));
      await flush();
      await flush();
      expect(store.rides.length, 1);
      final ride = store.rides.single;
      expect(ride.points.length, 400);
      expect(ride.fromWatch, isTrue);
      expect(ride.imported, isTrue);
      expect(ride.profile, isNotNull);
      expect(bridge.rideAnswers, [watchRideAckOf('1700000000')]);
      expect(container.read(watchRideInboxProvider), 1);
      // Dieselbe Fahrt noch einmal (das Quittieren ging verloren): kein
      // zweiter Eintrag, aber wieder quittiert.
      bridge.answer(rideMessage('1700000000', 0, 1, chunks));
      await flush();
      await flush();
      expect(store.rides.length, 1);
      expect(bridge.rideAnswers.length, 2);
      expect(container.read(watchRideInboxProvider), 1);
    });

    test('scheitert das Ablegen, bleibt die Fahrt auf der Uhr', () async {
      store.failOnImport = true;
      await container.read(watchRideInboxProvider.notifier).start();
      bridge.answer(rideMessage('1700000000', 0, 1, encodeWatchRide(ridePoints(40))));
      await flush();
      await flush();
      expect(store.rides, isEmpty);
      expect(bridge.rideAnswers, isEmpty);
    });

    test('ohne Anmeldung kein Ablegen und kein Quittieren', () async {
      final signedOut = make(uid: null);
      await signedOut.read(watchRideInboxProvider.notifier).start();
      bridge.answer(rideMessage('1700000000', 0, 1, encodeWatchRide(ridePoints(40))));
      await flush();
      await flush();
      expect(store.rides, isEmpty);
      expect(bridge.rideAnswers, isEmpty);
    });

    test('hat das Handy selbst aufgezeichnet, bleibt es bei dessen Fahrt', () async {
      final mine = [for (var i = 0; i < 40; i++) at(1700000000 + i * 5)];
      store.uid = 'me';
      store.rides.add(Ride(id: 'phone', startedAt: mine.first.at, endedAt: mine.last.at, points: mine));
      await container.read(watchRideInboxProvider.notifier).start();
      bridge.answer(rideMessage('1700000003', 0, 1, encodeWatchRide(ridePoints(40, t0: 1700000003))));
      await flush();
      await flush();
      expect(store.rides.length, 1);
      expect(bridge.rideAnswers, [watchRideAckOf('1700000003')]);
      expect(container.read(watchRideInboxProvider), 0);
    });
  });
}
