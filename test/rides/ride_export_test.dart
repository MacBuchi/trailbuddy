// Eine Fahrt als GPX (#150): alle Punkte mit roher GPS-Höhe und Zeit,
// nichts aus den Fragen und Antworten der Fahrt.
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/rides/ride_confirm.dart';
import 'package:trailbuddy/features/rides/ride_export.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/features/trails/gpx.dart';
import 'package:trailbuddy/features/trails/gpx_writer.dart';

void main() {
  final t0 = DateTime.utc(2026, 9, 28, 9, 0);
  RidePoint pt(int i, {double? alt}) => RidePoint(
    lat: 7.0 + i * 0.001,
    lng: 9.0,
    at: t0.add(Duration(seconds: 5 * i)),
    accuracyM: 8,
    altM: alt,
  );

  test('eine geplante Fahrt (#158 Schritt 5): ihr Name, keine Zeiten', () {
    final ride = Ride(
      id: 'planned',
      startedAt: t0,
      endedAt: t0.add(const Duration(hours: 2)),
      points: [pt(0), pt(1)],
      planned: true,
      name: 'Runde: Hang, Steinbruch',
    );
    final track = rideToGpx(ride);
    expect(track.name, 'Runde: Hang, Steinbruch');
    expect(track.points.map((p) => p.time), [
      null,
      null,
    ], reason: 'lauter gleiche Zeiten läse jede App als Stillstand');
    expect(rideExportName(ride), 'Runde: Hang, Steinbruch');
  });

  test('alle Punkte, rohe Höhe als ele, Zeit je Punkt', () {
    final ride = Ride(
      id: '20260928T090000Z',
      startedAt: t0,
      endedAt: t0.add(const Duration(minutes: 1)),
      points: [pt(0, alt: 612.3), pt(1), pt(2, alt: 598.0)],
      events: [
        ConfirmAsked(trailId: 'trail-geheim', name: 'Geheimer Hang', at: t0),
      ],
      marks: [RideMark(kind: RideMarkKind.start, at: t0)],
    );
    final track = rideToGpx(ride);
    expect(track.name, startsWith('Fahrt 2026-09-28'));
    expect(track.link, isNull);
    expect(track.points.length, 3);
    expect(track.points.map((p) => p.ele), [612.3, null, 598.0]);
    expect(track.points[1].time, t0.add(const Duration(seconds: 5)));
    expect(rideExportFileName(ride), 'trailbuddy-fahrt-20260928t090000z.gpx');

    final xml = writeGpx(name: track.name, points: track.points);
    expect(
      xml,
      isNot(contains('Geheimer Hang')),
      reason: 'Trailnamen aus Fragen gehören nicht in die Datei',
    );
    expect(xml, isNot(contains('trail-geheim')));
    final back = parseGpx(xml).single;
    expect(back.points.map((p) => p.ele), [612.3, null, 598.0]);
    expect(back.points.last.time, t0.add(const Duration(seconds: 10)));
  });
}
