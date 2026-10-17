// Die Kalibrierung pur (#158 Schritt 6): Aufstiegsabschnitte wie im
// Werkzeug, die Klassenzuordnung entlang der Spur, der Median je Gruppe
// mit Mindestzahl und Spanne, der Rundlauf durch die Einstellung und das
// Profil mit gelernten Werten.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/features/routing/ride_calibration.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';

List<LatLng> _m(List<(double, double)> xy, {double lat0 = 47.5, double lon0 = 11.5}) {
  final proj = FlatProjection(lat0);
  final o = proj.xy(LatLng(lat0, lon0));
  return [for (final (x, y) in xy) proj.latLng(math.Point(o.x + x, o.y + y))];
}

WayLine _way(List<(double, double)> xy, {WayClass cls = WayClass.forstweg}) =>
    WayLine(cls: cls, oneway: false, points: _m(xy));

void main() {
  test('Aufstiegsabschnitte wie ride_sections: ab 100 hm, Ende nach 15 m Abfall', () {
    // 0 → 120 (Aufstieg), 120 → 80 (Abfall 40: Ende — nach der Glättung
    // bleiben davon 15), 80 → 130 (nur 50: zu wenig). Ein Abfall von 20
    // rohen Metern überlebt den Median über sieben Punkte nicht, der
    // Aufstieg liefe dann bis zum Schluss durch — wie im Werkzeug.
    final ele = <double>[
      for (var i = 0; i <= 24; i++) i * 5.0,
      for (var i = 1; i <= 8; i++) 120 - i * 5.0,
      for (var i = 1; i <= 10; i++) 80 + i * 5.0,
    ];
    final s = ascentSections(ele);
    expect(s, hasLength(1));
    expect(s.single.start, 0);
    // Der Median über 7 Punkte kappt den Gipfel auf 110 (ab Index 22) und
    // hebt den Start auf 7,5 — wie im Werkzeug, das dieselbe Glättung fährt.
    expect(s.single.top, 22);
    expect(s.single.gainM, closeTo(102.5, 1e-9));
    expect(ascentSections(List.filled(20, 500.0)), isEmpty);
    expect(ascentSections([1, 2, 3]), isEmpty, reason: 'kürzer als das Fenster');
  });

  test('Klassenmix entlang der Spur: Forstweg unten, Wanderweg oben, abseits daneben', () {
    final g = buildRoadGraph([
      _way([(0, 0), (0, 500)]),
      _way([(0, 500), (0, 1000)], cls: WayClass.wanderweg),
    ], lat0: 47.5).graph;
    final mix = classMixAlong(g, _m([(3, 0), (3, 500), (3, 1000), (200, 1000)]));
    expect(mix[WayClass.forstweg], closeTo(500, 10));
    expect(mix[WayClass.wanderweg], closeTo(500, 10));
    // Die ersten 15 m des Querstücks liegen noch im Korridor des Wegendes.
    expect(mix[null], closeTo(185, 15), reason: 'abseits: weiter als 15 m von jedem Weg');
  });

  test('Messungen einer Fahrt: Rate je dominanter Klasse, flache Stücke als km/h', () {
    final g = buildRoadGraph([_way([(0, -2000), (0, 2000)])], lat0: 47.5).graph;
    // 1 km bergauf 150 hm in 10 min (900 hm/h), dann 1 km flach in 4 min (15 km/h).
    final t0 = DateTime.utc(2026, 10, 1, 9);
    final pts = <RidePoint>[];
    for (var i = 0; i <= 100; i++) {
      final ll = _m([(0, i * 10.0)]).single;
      pts.add(RidePoint(lat: ll.latitude, lng: ll.longitude, at: t0.add(Duration(seconds: i * 6)), accuracyM: 5, altM: 500 + i * 1.5));
    }
    for (var i = 1; i <= 100; i++) {
      final ll = _m([(0, 1000 + i * 10.0)]).single;
      pts.add(RidePoint(lat: ll.latitude, lng: ll.longitude, at: t0.add(Duration(seconds: 600 + i * 24 ~/ 10)), accuracyM: 5, altM: 650));
    }
    final ride = Ride(id: 'r', startedAt: t0, endedAt: pts.last.at, points: pts, profile: 'bio');
    final samples = calibSamplesOf(ride, g);
    final climbs = samples.where((s) => !s.flat).toList();
    expect(climbs, hasLength(1));
    expect(climbs.single.group, CalibGroup.track);
    expect(climbs.single.value, closeTo(900, 20));
    final flats = samples.where((s) => s.flat).toList();
    expect(flats, hasLength(1));
    expect(flats.single.value, closeTo(15, 1));
    // Ohne Graphen keine Messung, ohne Höhen auch nicht.
    expect(calibSamplesOf(ride, null), isEmpty);
    final noAlt = Ride(id: 'n', startedAt: t0, endedAt: t0, points: [
      for (final p in pts) RidePoint(lat: p.lat, lng: p.lng, at: p.at, accuracyM: 5),
    ]);
    expect(calibSamplesOf(noAlt, g), isEmpty);
  });

  test('calibrateFrom: Median je Gruppe, erst ab drei Messungen, nur in der Spanne', () {
    final now = DateTime.utc(2026, 10, 1);
    final c = calibrateFrom([
      const CalibSample.climb(CalibGroup.track, 500),
      const CalibSample.climb(CalibGroup.track, 600),
      const CalibSample.climb(CalibGroup.track, 400),
      const CalibSample.climb(CalibGroup.track, 9000), // GPS-Sprung: außerhalb
      const CalibSample.climb(CalibGroup.path, 300),
      const CalibSample.climb(CalibGroup.path, 320),
      const CalibSample.flat(14),
      const CalibSample.flat(16),
      const CalibSample.flat(15),
    ], rides: 4, now: now);
    expect(c.climbTrackMPerH, 500);
    expect(c.climbPathMPerH, isNull, reason: 'nur zwei Messungen');
    expect(c.pushRateMPerH, isNull);
    expect(c.vFlatKmh, 15);
    expect(c.rides, 4);
    expect(c.sections, 6);
    expect(c.at, now);
    expect(c.isEmpty, isFalse);
    expect(calibrateFrom(const [], rides: 0).isEmpty, isTrue);
  });

  test('Rundlauf durch die Einstellung, zurücksetzen je Profil, Unlesbares heißt Vorgaben', () {
    final now = DateTime.utc(2026, 10, 1, 12);
    final all = const RiderCalibrations()
        .withProfile(RiderProfile.bio, RiderCalibration(climbTrackMPerH: 520, vFlatKmh: 14, rides: 3, sections: 5, at: now))
        .withProfile(RiderProfile.ebike, const RiderCalibration(climbPathMPerH: 700, rides: 1, sections: 3));
    final back = RiderCalibrations.parse(all.encode());
    expect(back.of(RiderProfile.bio).climbTrackMPerH, 520);
    expect(back.of(RiderProfile.bio).vFlatKmh, 14);
    expect(back.of(RiderProfile.bio).climbPathMPerH, isNull);
    expect(back.of(RiderProfile.bio).rides, 3);
    expect(back.of(RiderProfile.bio).at, now);
    expect(back.of(RiderProfile.ebike).climbPathMPerH, 700);
    expect(back.without(RiderProfile.bio).of(RiderProfile.bio).isEmpty, isTrue);
    expect(back.without(RiderProfile.bio).of(RiderProfile.ebike).isEmpty, isFalse);
    expect(RiderCalibrations.parse(null).isEmpty, isTrue);
    expect(RiderCalibrations.parse('kaputt{').isEmpty, isTrue);
    expect(RiderCalibrations.parse('[1,2]').isEmpty, isTrue);
  });

  test('Gespeichertes außerhalb der Spanne gilt als nicht gelernt — keine Division durch null (#356)', () {
    final back = RiderCalibrations.parse(
        '{"bio":{"track":0,"path":-5,"push":99999,"flat":0,"rides":2,"sections":3},'
        '"ebike":{"track":"x","flat":12.5}}');
    final bio = back.of(RiderProfile.bio);
    expect(bio.climbTrackMPerH, isNull);
    expect(bio.climbPathMPerH, isNull);
    expect(bio.pushRateMPerH, isNull);
    expect(bio.vFlatKmh, isNull);
    expect(bio.rides, 2, reason: 'die Zählung bleibt, nur die Zahlen fallen auf die Vorgabe');
    expect(back.of(RiderProfile.ebike).climbTrackMPerH, isNull);
    expect(back.of(RiderProfile.ebike).vFlatKmh, 12.5);
    final rider = CalibratedRider(RiderProfile.bio, bio);
    final t = edgeTimeS(rider, WayClass.forstweg, lengthM: 1000, gainM: 100, lossM: 0);
    expect(t.isFinite, isTrue);
  });

  test('CalibratedRider: gelernte Werte überlagern, der Rest bleibt Vorgabe', () {
    const rider = CalibratedRider(RiderProfile.bio, RiderCalibration(climbTrackMPerH: 520, vFlatKmh: 14));
    expect(rider.profile, RiderProfile.bio);
    expect(rider.climbTrackMPerH, 520);
    expect(rider.vFlatKmh, 14);
    expect(rider.climbPathMPerH, RiderProfile.bio.climbPathMPerH);
    expect(rider.pathUpFactor, RiderProfile.bio.pathUpFactor);
    expect(rider.budgetClimbM, RiderProfile.bio.budgetClimbM);
    // Das Zeitmodell rechnet mit der gelernten Rate: 100 hm Forstweg.
    final learned = edgeTimeS(rider, WayClass.forstweg, lengthM: 0, gainM: 100, lossM: 0);
    final stock = edgeTimeS(RiderProfile.bio, WayClass.forstweg, lengthM: 0, gainM: 100, lossM: 0);
    expect(learned, closeTo(100 / 520 * 3600, 1e-6));
    expect(learned, lessThan(stock), reason: '520 hm/h ist schneller als die Vorgabe 450 — also kürzer');
  });
}
