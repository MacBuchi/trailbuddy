// Airtime unter Buddys (#36 Schritt 6), pur: was das Gerät aus seinen
// Fahrten teilt, und was der Betrachter daraus macht.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/data/airtime_repository.dart';
import 'package:trailbuddy/features/rides/airtime_share.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/features/rides/sensor_fusion.dart';
import 'package:trailbuddy/features/rides/trail_values.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/trail.dart';

const _mPerDegLat = 111320.0;

LatLng _at(double m) => LatLng(48.0 + m / _mPerDegLat, 9.0);

/// Ein Trail von [fromM] bis [toM] Meter nördlich von 48°/9°.
Trail _trail(String id, double fromM, double toM) => Trail(
      id: id,
      myId: 'me',
      details: const [],
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

/// Eine Fahrt nach Norden, 0 bis 2 000 m, 5 m/s, alle 20 m ein Punkt.
Ride _ride(String id, DateTime t0, {bool planned = false}) {
  final points = [
    for (var m = 0.0; m <= 2000; m += 20)
      RidePoint(lat: _at(m).latitude, lng: _at(m).longitude, at: t0.add(Duration(seconds: (m / 5).round())), accuracyM: 5),
  ];
  return Ride(id: id, startedAt: t0, endedAt: points.last.at, points: points, planned: planned);
}

/// Ein Sprung bei Meter [m] der Fahrt ab [t0].
JumpEvent _jump(DateTime t0, double m, int ms, {bool plausible = true}) => JumpEvent(
    startUs: t0.add(Duration(seconds: (m / 5).round())).microsecondsSinceEpoch,
    duration: Duration(milliseconds: ms),
    landingG: 2.5,
    upright: plausible,
    plausible: plausible);

void main() {
  final now = DateTime(2026, 11, 7, 12);
  final trails = [_trail('t-a', 200, 800), _trail('t-b', 1200, 1800)];

  group('computeAirtimeShare', () {
    test('Bestwert je Trail: Summe je Durchfahrt, längster Sprung, Monat des Besten', () {
      final oct = DateTime(2026, 10, 2, 10), nov = DateTime(2026, 11, 3, 10);
      final share = computeAirtimeShare(trails: trails, now: now, rides: [
        // Oktober: auf A 0,6 + 0,9 s, auf B 1,2 s; ein Sprung vor dem Trail zählt nicht.
        (
          ride: _ride('r1', oct),
          log: AirtimeLog(events: [_jump(oct, 100, 800), _jump(oct, 300, 600), _jump(oct, 600, 900), _jump(oct, 1500, 1200)]),
          measured: true,
        ),
        // November: auf A nur 1,0 s (schlechter), aber ein Sprung von 1,0 s ist länger.
        (ride: _ride('r2', nov), log: AirtimeLog(events: [_jump(nov, 400, 1000)]), measured: true),
      ]);
      final a = share.bests.singleWhere((b) => b.trailId == 't-a');
      final b = share.bests.singleWhere((b) => b.trailId == 't-b');
      expect((a.airDs, a.longestDs, a.month), (15, 10, DateTime(2026, 10)), reason: 'Monat des besten Durchgangs');
      expect((b.airDs, b.longestDs), (12, 12));
      // Fenster: nur die Novemberfahrt liegt in den 30 Tagen.
      expect((share.airDs, share.jumps), (10, 1));
      expect(share.titles, {AirtimeTitle.glider}, reason: 'ein Sprung von 1,0 s im Fenster');
    });

    test('„War keiner" und unplausibel zählen nicht; ohne Sprung kein Bestwert', () {
      final t0 = DateTime(2026, 11, 1, 10);
      final real = _jump(t0, 300, 700);
      final share = computeAirtimeShare(trails: trails, now: now, rides: [
        (
          ride: _ride('r1', t0),
          log: AirtimeLog(events: [real, _jump(t0, 400, 900, plausible: false)]).withAnswer(real, yes: false),
          measured: true,
        ),
      ]);
      expect(share.bests, isEmpty);
      expect((share.airDs, share.jumps), (0, 0));
      expect(share.titles, {AirtimeTitle.groundCrew}, reason: 'gemessen gefahren, aber kein Sprung');
    });

    test('Bodenpersonal nur mit Messung; alte, geplante und übernommene Fahrten zählen nicht ins Fenster', () {
      final old = DateTime(2026, 9, 1, 10);
      final share = computeAirtimeShare(trails: trails, now: now, rides: [
        (ride: _ride('r1', old), log: AirtimeLog(events: [_jump(old, 300, 1100)]), measured: true),
        (ride: _ride('r2', DateTime(2026, 11, 2)), log: AirtimeLog.empty, measured: false),
        (ride: _ride('r3', DateTime(2026, 11, 2), planned: true), log: AirtimeLog.empty, measured: true),
      ]);
      expect(share.bests.single.airDs, 11, reason: 'der Bestwert bleibt, auch älter als 30 Tage');
      expect((share.airDs, share.jumps), (0, 0));
      expect(share.titles, isEmpty, reason: 'im Fenster nichts gemessen, und der lange Sprung ist zu alt');
    });

    test('die Riegel des Servers gelten schon auf dem Gerät', () {
      final t0 = DateTime(2026, 11, 1, 10);
      final share = computeAirtimeShare(trails: trails, now: now, rides: [
        (ride: _ride('r1', t0), log: AirtimeLog(events: [_jump(t0, 300, 70000)]), measured: true),
      ]);
      expect((share.bests.single.airDs, share.bests.single.longestDs), (700, kJumpMaxDs));
    });
  });

  group('Betrachter', () {
    TrailAirtime best(String user, String trail, int ds, {int month = 10}) =>
        TrailAirtime(userId: user, trailId: trail, airDs: ds, longestDs: 1, month: DateTime(2026, month));

    test('Rangliste: Summe zuerst, Gleichstand teilt den Platz, der frühere Monat steht vorn', () {
      final r = trailAirtimeRanking(
          [best('jan', 't', 51), best('me', 't', 43, month: 11), best('mira', 't', 43, month: 9), best('jan', 'x', 99)],
          't');
      expect([for (final x in r) (x.place, x.best.userId)], [(1, 'jan'), (2, 'mira'), (2, 'me')]);
    });

    test('gezeigt: die ersten drei und der eigene Platz dahinter', () {
      final r = trailAirtimeRanking([for (var i = 0; i < 5; i++) best('u$i', 't', 50 - i), best('me', 't', 10)], 't');
      expect([for (final x in airtimeRankingShown(r, 'me')) x.best.userId], ['u0', 'u1', 'u2', 'me']);
      expect(airtimeRankingShown(r, 'u1'), hasLength(3));
    });

    test('Trailkönig nur, wo mindestens zwei Werte stehen', () {
      expect(trailKingCounts([best('jan', 'a', 50), best('me', 'a', 40), best('me', 'b', 30), best('jan', 'c', 9), best('me', 'c', 9)]),
          {'jan': 2, 'me': 1});
    });

    test('Vielflieger: die meisten Sprünge unter frischen Zählern, ab zwei Zählern', () {
      AirtimeCounter c(String u, int jumps, {DateTime? asOf}) =>
          AirtimeCounter(userId: u, airDs: jumps * 5, jumps: jumps, asOf: asOf ?? DateTime(2026, 11, 6));
      expect(frequentFlyers([c('jan', 30), c('me', 12)], now), {'jan'});
      expect(frequentFlyers([c('jan', 30, asOf: DateTime(2026, 9, 1)), c('me', 12)], now), isEmpty,
          reason: 'Jans Stand ist älter als 30 Tage — allein ist man kein Vielflieger');
      expect(frequentFlyers([c('jan', 0), c('me', 0)], now), isEmpty);
      expect(airtimeCounterFresh(c('x', 1, asOf: DateTime(2026, 10, 8)), now), isTrue);
      expect(airtimeCounterFresh(c('x', 1, asOf: DateTime(2026, 10, 7)), now), isFalse);
    });
  });
}
