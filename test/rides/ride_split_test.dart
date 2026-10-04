// Die Zerlegung (#29), pur: eine Fahrt nach Norden — Anfahrt auf der
// Straße, Abfahrt abseits, Forstweg, ein bekannter Trail am Ende.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/rides/ride_split.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/features/rides/road_index.dart';
import 'package:trailbuddy/features/trails/gpx.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/trail.dart';

const _mPerDegLat = 111320.0;

/// Ein Punkt [m] Meter nördlich von 48°/9° (plus [eastM] östlich).
LatLng at(double m, {double eastM = 0}) =>
    LatLng(48.0 + m / _mPerDegLat, 9.0 + eastM / (_mPerDegLat * math.cos(48 * math.pi / 180)));

/// Die Fahrt: alle 20 m ein Punkt von 0 bis [lengthM], Höhe aus [ele].
List<TrackPoint> ride(double lengthM, double Function(double m) ele, {double? Function(double m)? east}) => [
      for (var m = 0.0; m <= lengthM; m += 20)
        TrackPoint(at(m, eastM: east?.call(m) ?? 0).latitude, at(m, eastM: east?.call(m) ?? 0).longitude,
            ele: ele(m), time: DateTime.utc(2026, 9, 28, 10).add(Duration(seconds: (m / 5).round()))),
    ];

/// Höhe: eben bis 400 m, dann 100 m Abfahrt bis 1 400 m, dann eben.
double profile(double m) => m < 400
    ? 500
    : m < 1400
        ? 500 - (m - 400) / 10
        : 400;

RoadLoadResult roads(List<List<LatLng>> lines) {
  final proj = FlatProjection(48.0);
  return (index: RoadIndex(lines, proj), coverage: RoadCoverage.complete, tilesNeeded: 1, tilesFound: 1);
}

const noRoads = (index: null, coverage: RoadCoverage.none, tilesNeeded: 1, tilesFound: 0);

/// Straße auf der Fahrt von 0 bis 400 m und von 1 400 m an — die Abfahrt
/// dazwischen ist frei.
RoadLoadResult roadsAroundDescent() => roads([
      [at(-50), at(400)],
      [at(1400), at(2500)],
    ]);

Trail trail(String id, double fromM, double toM, {double eastM = 0}) => Trail(
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
          points: [for (var m = fromM; m <= toM; m += 25) at(m, eastM: eastM)],
          lengthM: toM - fromM,
        ),
      ],
    );

void main() {
  test('Median glättet einen Ausreißer weg, ein Mittel täte es nicht', () {
    final ele = <double>[500, 500, 500, 540, 500, 500, 500];
    final s = smoothElevation(ele, 5);
    expect(s[3], 500);
    expect(smoothElevation([1, 2], 5), [1, 2]);
  });

  test('Abfahrten: Gipfel bis Talsohle, Gegensteigungen unter 15 m gehören dazu', () {
    // 0..10: eben; 10..40: bergab 100 m mit einer Delle; 40..50: bergauf.
    final ele = <double>[
      for (var i = 0; i <= 10; i++) 600,
      for (var i = 1; i <= 15; i++) 600 - i * 4.0,
      for (var i = 1; i <= 3; i++) 540 + i * 3.0, // kleine Gegensteigung (9 m)
      for (var i = 1; i <= 12; i++) 549 - i * 4.0,
      for (var i = 1; i <= 10; i++) 501 + i * 5.0,
    ];
    final runs = descentRuns(ele);
    expect(runs, hasLength(1));
    final (s, e) = runs.single;
    expect(s, 10, reason: 'am letzten Punkt des Gipfels');
    expect(ele[e], 501, reason: 'an der Talsohle');
    // Zwei kleine Wellen von 20 m sind keine Abfahrt.
    expect(descentRuns([500, 480, 500, 480, 500]), isEmpty);
    expect(descentRuns([500]), isEmpty);
  });

  test('die Abfahrt abseits der Straße wird Kandidat, Straße und Forstweg nicht', () {
    final pts = ride(2000, profile);
    final split = splitRide(points: pts, trails: const [], roads: roadsAroundDescent());
    expect(split.hasElevation, isTrue);
    expect(split.roads, RoadCoverage.complete);
    expect(split.known, isEmpty);
    expect(split.candidates, hasLength(1));
    final c = split.candidates.single;
    expect(c.lengthM, inInclusiveRange(900, 1000));
    expect(c.lossM, inInclusiveRange(85, 100));
    expect(c.offRoadShare, greaterThan(kSplitOffRoadShare));
    expect(c.nearHome, isFalse);
    // Die Griffe sitzen an der Straße: Der erste Punkt liegt hinter den
    // 400 m Anfahrt, der letzte vor dem Forstweg.
    expect(split.points[c.start].lat, greaterThan(at(400).latitude - 1e-9));
    expect(split.points[c.end].lat, lessThan(at(1420).latitude));
    expect(split.restM, inInclusiveRange(1000, 1100));
  });

  test('dieselbe Abfahrt auf der Straße ist kein Kandidat', () {
    final pts = ride(2000, profile);
    final all = roads([
      [at(-50), at(2500)],
    ]);
    expect(splitRide(points: pts, trails: const [], roads: all).candidates, isEmpty);
  });

  test('ohne Wege keine Kandidaten, ohne Höhen auch nicht', () {
    final pts = ride(2000, profile);
    final s1 = splitRide(points: pts, trails: const [], roads: noRoads);
    expect(s1.candidates, isEmpty);
    expect(s1.roads, RoadCoverage.none);
    final flat = [for (final p in pts) TrackPoint(p.lat, p.lon, time: p.time)];
    final s2 = splitRide(points: flat, trails: const [], roads: roadsAroundDescent());
    expect(s2.hasElevation, isFalse);
    expect(s2.candidates, isEmpty);
  });

  test('Heimzone: ein Kandidat, der nahe am Ziel endet, wird markiert', () {
    // Die Fahrt endet 100 m nach der Abfahrt.
    final pts = ride(1500, profile);
    final split = splitRide(points: pts, trails: const [], roads: roadsAroundDescent());
    expect(split.candidates.single.nearEnd, isTrue);
    expect(split.candidates.single.nearStart, isFalse);
  });

  test('ein Trail des Netzes unter der Fahrt ist „bekannt", und frei bleibt der Rest', () {
    // Der Trail liegt 1 600–1 900 m, 3 m neben der Fahrt.
    final t = trail('t1', 1600, 1900, eastM: 3);
    final pts = ride(2000, profile);
    final split = splitRide(points: pts, trails: [t], roads: roadsAroundDescent());
    expect(split.known, hasLength(1));
    final k = split.known.single;
    expect(k.trail.id, 't1');
    expect(k.lengthM, inInclusiveRange(280, 340));
    expect(split.candidates, hasLength(1), reason: 'die Abfahrt davor bleibt Kandidat');
    expect(split.candidates.single.end, lessThan(k.start));
    // Ein Trail weit daneben wird nicht bekannt.
    final far = trail('t2', 1600, 1900, eastM: 60);
    expect(splitRide(points: pts, trails: [far], roads: noRoads).known, isEmpty);
    // Ein Trail, der nur zur Hälfte unter der Fahrt liegt, auch nicht.
    final half = trail('t3', 1800, 2400, eastM: 3);
    expect(splitRide(points: pts, trails: [half], roads: noRoads).known, isEmpty);
  });

  test('unscharfe Punkte fallen weg und werden gezählt', () {
    final pts = ride(600, (_) => 500);
    final acc = [for (var i = 0; i < pts.length; i++) i == 3 ? 80.0 : 5.0];
    final split = splitRide(points: pts, accuracyM: acc, trails: const [], roads: noRoads);
    expect(split.droppedInaccurate, 1);
    expect(split.points, hasLength(pts.length - 1));
    expect(split.totalM, inInclusiveRange(590, 610));
  });

  test('selbst gewählt (#104): Griffe über die ganze Fahrt, vorgewählt ohne die Heimzone', () {
    // Eben, ohne Wege: Die Suche findet nichts, selbst wählen geht trotzdem.
    final split = splitRide(points: ride(2000, (_) => 500), trails: const [], roads: noRoads);
    expect(split.candidates, isEmpty);
    final m = manualSection(split)!;
    expect(m.section.manual, isTrue);
    expect((m.section.start, m.section.end), (0, split.points.length - 1),
        reason: 'die Griffe reichen über die ganze Fahrt');
    expect(m.section.offRoadShare, isNull, reason: 'kein Urteil über Wege');
    // Punkte alle 20 m: die ersten und letzten 300 m fallen aus der Vorwahl.
    expect(m.start, 16);
    expect(m.end, split.points.length - 1 - 16);
    final home = homeZoneOf(split, m.start, m.end);
    expect(home.nearStart || home.nearEnd, isFalse);
    expect(homeZoneOf(split, 0, m.end).nearStart, isTrue, reason: 'der Hinweis folgt den Griffen');
  });

  test('selbst gewählt: kurze Runde behält die ganze Fahrt, zu kurz gibt es nicht', () {
    // 500 m: ohne 2 × 300 m bliebe nichts — die Griffe stehen an den Enden.
    final short = manualSection(splitRide(points: ride(500, (_) => 500), trails: const [], roads: noRoads))!;
    expect((short.start, short.end), (0, 25));
    expect(manualSection(splitRide(points: ride(40, (_) => 500), trails: const [], roads: noRoads)), isNull,
        reason: 'kürzer als ein Trail (50 m)');
  });

  group('Marken (#105)', () {
    // Punkte alle 20 m, alle 4 s — Punkt i liegt bei 4·i s nach dem Start.
    final t0 = DateTime.utc(2026, 9, 28, 10);
    RideMark begins(int s) => RideMark(kind: RideMarkKind.start, at: t0.add(Duration(seconds: s)));
    RideMark ends(int s) => RideMark(kind: RideMarkKind.end, at: t0.add(Duration(seconds: s)));

    test('gepaart in zeitlicher Reihenfolge, je Marke der zeitlich nächste Punkt', () {
      final pts = ride(2000, (_) => 500);
      // 41 s liegt näher an Punkt 10 (40 s) als an 11 (44 s).
      expect(markedRanges(pts, [ends(81), begins(41)]), [(10, 20)],
          reason: 'die Reihenfolge der Liste zählt nicht, die Zeit schon');
      expect(markedRanges(pts, [begins(40), begins(120), ends(200)]), [(10, 30), (30, 50)],
          reason: 'ein zweiter Beginn schließt den ersten dort — zwei Trails hintereinander');
      expect(markedRanges(pts, [ends(40)]), isEmpty, reason: 'ein Ende ohne Beginn zählt nicht');
      expect(markedRanges(pts, [begins(360)]), [(90, pts.length - 1)],
          reason: 'eine offene Marke gilt bis zum letzten Punkt');
      expect(markedRanges(pts, [begins(40), ends(41)]), isEmpty, reason: 'ein Punkt ist kein Stück');
      final untimed = [for (final p in pts) TrackPoint(p.lat, p.lon)];
      expect(markedRanges(untimed, [begins(40), ends(80)]), isEmpty, reason: 'ohne Zeiten keine Marken');
    });

    test('ein markiertes Stück wird Kandidat — ohne Wege und ohne Höhen', () {
      final flat = [for (final p in ride(2000, (_) => 500)) TrackPoint(p.lat, p.lon, time: p.time)];
      final split = splitRide(points: flat, trails: const [], roads: noRoads, marks: [begins(80), ends(240)]);
      final c = split.candidates.single;
      expect(c.marked, isTrue);
      expect(c.spansRide, isTrue, reason: 'die Griffe reichen über die ganze Fahrt');
      expect((c.start, c.end), (20, 60));
      expect(c.lengthM, closeTo(800, 5));
      expect(c.lossM, isNull);
      expect(c.offRoadShare, isNull, reason: 'kein Urteil über Wege');
      expect(split.restM, closeTo(1200, 10));
    });

    test('die Marke schlägt die Suche, wo beide sich überschneiden', () {
      final pts = ride(2000, profile);
      final found = splitRide(points: pts, trails: const [], roads: roadsAroundDescent()).candidates.single;
      expect(found.marked, isFalse);
      // Markiert: 600–1 200 m, mitten in der gefundenen Abfahrt.
      final split = splitRide(
          points: pts, trails: const [], roads: roadsAroundDescent(), marks: [begins(120), ends(240)]);
      expect(split.candidates, hasLength(1));
      expect(split.candidates.single.marked, isTrue);
      expect((split.candidates.single.start, split.candidates.single.end), (30, 60));
      // Daneben (1 500–1 800 m) bleiben beide, nach dem Anfang sortiert.
      final both = splitRide(
          points: pts, trails: const [], roads: roadsAroundDescent(), marks: [begins(300), ends(360)]);
      expect([for (final c in both.candidates) c.marked], [false, true]);
    });

    test('deckt ein bekannter Trail das markierte Stück, steht nur seine Zeile da', () {
      final pts = ride(2000, (_) => 500);
      final t = trail('t1', 1000, 1600, eastM: 3);
      final split = splitRide(points: pts, trails: [t], roads: noRoads, marks: [begins(200), ends(320)]);
      expect(split.known.single.trail.id, 't1');
      expect(split.candidates, isEmpty, reason: 'sonst ginge dieselbe Strecke zweimal hinaus');
      // Reicht die Marke weit darüber hinaus, bleibt sie Kandidat.
      final longer = splitRide(points: pts, trails: [t], roads: noRoads, marks: [begins(40), ends(320)]);
      expect(longer.candidates.single.marked, isTrue);
    });
  });
}
