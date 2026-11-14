// Wie oft ich einen Trail gefahren bin (#516 Schritt 5, Konzept-Routing
// 12.4): je Fahrt einmal gerechnet, als Datei neben den Fahrten, nur die
// neuen nachgerechnet, gelöschte fallen heraus.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/rides/ride_providers.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/features/rides/trail_ride_counts.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/features/trails/trail_providers.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_rides.dart';

const _mPerDegLat = 111320.0;

LatLng _at(double m, {double eastDeg = 0}) => LatLng(48.0 + m / _mPerDegLat, 9.0 + eastDeg);

/// Ein Trail von [fromM] bis [toM] Meter nördlich von 48°/9°.
Trail _trail(String id, double fromM, double toM, {List<MergedTrail> mergedFrom = const []}) => Trail(
      id: id,
      myId: 'me',
      details: const [],
      mergedFrom: mergedFrom,
      recordings: [
        TrailRecording(
          id: 'rec-$id',
          trailId: id,
          userId: 'buddy',
          source: RecordingSource.import,
          recordedAt: null,
          reversed: false,
          quality: 0.5,
          createdAt: DateTime.utc(2026, 1, 1),
          points: [for (var m = fromM; m <= toM; m += 25) _at(m)],
          lengthM: toM - fromM,
        ),
      ],
    );

/// Eine Fahrt nach Norden über [toM] Meter; [eastDeg] legt sie abseits.
Ride _ride(String id, {double toM = 2000, double eastDeg = 0, bool planned = false}) {
  final t0 = DateTime.utc(2026, 11, 1, 10);
  final points = [
    for (var m = 0.0; m <= toM; m += 20)
      RidePoint(
          lat: _at(m, eastDeg: eastDeg).latitude,
          lng: _at(m, eastDeg: eastDeg).longitude,
          at: t0.add(Duration(seconds: (m / 5).round())),
          accuracyM: 5),
  ];
  return Ride(id: id, startedAt: t0, endedAt: points.last.at, points: points, planned: planned);
}

class _Trails extends TrailsNotifier {
  _Trails(this.trails);
  final List<Trail> trails;
  @override
  Future<List<Trail>> build() async => trails;
}

class _Rides extends RidesNotifier {
  _Rides(this.rides);
  final List<Ride> rides;
  @override
  Future<List<Ride>> build() async => rides;
}

void main() {
  final a = _trail('t-a', 200, 800), b = _trail('t-b', 1200, 1800);

  group('updateTrailRideCounts', () {
    test('je Fahrt die befahrenen Trails; geplante zählen nicht', () async {
      final next = await updateTrailRideCounts(TrailRideCounts.empty, rides: [
        _ride('r1'),
        _ride('r2', toM: 900),
        _ride('r3', planned: true),
        _ride('r4', eastDeg: 0.01),
      ], trails: [a, b]);
      expect(next, isNotNull);
      expect(next!.byRide.keys.toSet(), {'r1', 'r2', 'r4'});
      expect(next.of(a), 2);
      expect(next.of(b), 1);
      expect(next.countsFor([a, b]), {'t-a': 2, 't-b': 1});
    });

    test('nur neue Fahrten werden gerechnet, gelöschte fallen heraus, sonst null', () async {
      // Der alte Stand sagt, r1 fuhr B — gerechnet wird r1 nicht noch einmal.
      const old = TrailRideCounts({
        'r1': ['t-b'],
        'gone': ['t-a'],
      });
      var rides = 0;
      final next = await updateTrailRideCounts(old,
          rides: [_ride('r1'), _ride('r2', toM: 900)], trails: [a, b], between: () async => rides++);
      expect(rides, 1, reason: 'nur r2 ist neu');
      expect(next!.byRide, {
        'r1': ['t-b'],
        'r2': ['t-a'],
      });
      expect(await updateTrailRideCounts(next, rides: [_ride('r1'), _ride('r2', toM: 900)], trails: [a, b]), isNull);
    });

    test('ein zusammengeführtes Duplikat zählt für den Trail, jede Fahrt einmal', () {
      final merged = _trail('t-a', 200, 800, mergedFrom: const [MergedTrail(id: 't-old', byMe: false)]);
      const counts = TrailRideCounts({
        'r1': ['t-old'],
        'r2': ['t-a', 't-old'],
        'r3': ['t-b'],
      });
      expect(counts.of(merged), 2);
    });

    test('Datei hin und zurück; Unlesbares und eine andere Fassung sind leer', () {
      const counts = TrailRideCounts({
        'r1': ['t-a', 't-b'],
      });
      expect(TrailRideCounts.parse(counts.encode()).byRide, counts.byRide);
      expect(TrailRideCounts.parse(null).byRide, isEmpty);
      expect(TrailRideCounts.parse('{kaputt').byRide, isEmpty);
      expect(TrailRideCounts.parse('{"v":99,"rides":{"r1":["t-a"]}}').byRide, isEmpty);
    });
  });

  group('trailRideCountsProvider', () {
    ProviderContainer container(FakeRideStore store, List<Ride> rides, List<Trail> trails) {
      final c = ProviderContainer(overrides: [
        rideStoreProvider.overrideWithValue(store),
        ridesProvider.overrideWith(() => _Rides(rides)),
        trailsProvider.overrideWith(() => _Trails(trails)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('schreibt die Datei fort und liest sie beim nächsten Mal', () async {
      final store = FakeRideStore();
      final first = await container(store, [_ride('r1')], [a, b]).read(trailRideCountsProvider.future);
      expect(first.countsFor([a, b]), {'t-a': 1, 't-b': 1});
      expect(store.countWrites, 1);
      // Dieselben Fahrten: nichts zu schreiben, der Stand aus der Datei.
      final again = await container(store, [_ride('r1')], [a, b]).read(trailRideCountsProvider.future);
      expect(again.countsFor([a, b]), {'t-a': 1, 't-b': 1});
      expect(store.countWrites, 1);
    });

    test('ohne geladenes Netz wird nichts festgeschrieben', () async {
      final store = FakeRideStore();
      final counts = await container(store, [_ride('r1')], const []).read(trailRideCountsProvider.future);
      expect(counts.byRide, isEmpty);
      expect(store.countWrites, 0, reason: 'sonst zählte r1 für immer null');
    });
  });
}
