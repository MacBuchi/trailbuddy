// Fahrten aus GPX-Dateien (#188), der reine Teil: Punkte mit Zeit und
// Datei-Höhe, „schon auf dem Gerät" über die Startsekunde, und beim
// Zerlegen zählt eine übernommene Fahrt wie die Datei, aus der sie kam.
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/rides/ride_import.dart';
import 'package:trailbuddy/features/rides/ride_split_sheet.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/features/trails/gpx.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';

void main() {
  final t0 = DateTime.utc(2026, 5, 1, 10);

  test('nur Punkte mit Zeit, mit der Höhe der Datei', () {
    final track = GpxTrack(
      name: 'Runde',
      points: [
        TrackPoint(48, 9, ele: 500, time: t0),
        const TrackPoint(48.001, 9, ele: 505),
        TrackPoint(48.002, 9, time: t0.add(const Duration(seconds: 10))),
      ],
    );
    final pts = ridePointsOf(track);
    expect(pts, hasLength(2));
    expect(pts.first.altM, 500);
    expect(pts.last.altM, isNull);
    expect(pts.last.at, t0.add(const Duration(seconds: 10)));
  });

  test(
    'schon auf dem Gerät: dieselbe Startsekunde, geplante Fahrten zählen nicht',
    () {
      RidePoint p(int s) => RidePoint(
        lat: 48,
        lng: 9,
        at: t0.add(Duration(milliseconds: s)),
        accuracyM: 5,
      );
      final recorded = Ride(
        id: 'a',
        startedAt: t0,
        endedAt: t0,
        points: [p(0), p(5000)],
      );
      final planned = Ride(
        id: 'b',
        startedAt: t0,
        endedAt: t0,
        points: [p(2000)],
        planned: true,
      );
      expect(
        rideOnDevice([p(400)], [recorded]),
        isTrue,
        reason: 'GPX schreibt ganze Sekunden',
      );
      expect(rideOnDevice([p(1500)], [recorded]), isFalse);
      expect(rideOnDevice([p(2000)], [planned]), isFalse);
      expect(rideOnDevice(const [], [recorded]), isFalse);
    },
  );

  test(
    'zerlegt wie die Datei: Quelle import, Datei-Höhen gehen mit, keine Streuung',
    () {
      final pts = [
        for (var i = 0; i < 3; i++)
          RidePoint(
            lat: 48 + i / 1000,
            lng: 9,
            at: t0.add(Duration(seconds: i * 5)),
            accuracyM: 0,
            altM: 500.0 + i,
          ),
      ];
      final imported = Ride(
        id: 'i',
        startedAt: t0,
        endedAt: t0,
        points: pts,
        imported: true,
        name: 'Runde',
      );
      final req = SplitRequest.fromRide(imported);
      expect(req.source, RecordingSource.import);
      expect(req.stripElevation, isFalse);
      expect(
        req.accuracyM,
        isNull,
        reason: 'die 0 der Datei hieße sonst „scharf"',
      );
      expect(req.track.name, 'Runde');
      expect(req.track.points.map((p) => p.ele), [500, 501, 502]);
      // Gegenprobe: die eigene Aufzeichnung bleibt bei GPS-Höhe und Streuung.
      final own = SplitRequest.fromRide(
        Ride(id: 'o', startedAt: t0, endedAt: t0, points: pts),
      );
      expect(own.source, RecordingSource.app);
      expect(own.stripElevation, isTrue);
      expect(own.accuracyM, hasLength(3));
    },
  );
}
