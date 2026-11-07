// Der Namensvorschlag nach „Trail endet" (#486), pur: aus dem sichtbaren
// Netz oder von früher in derselben Fahrt.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/rides/ride_mark_name.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/trail.dart';

const _mPerDegLat = 111320.0;

LatLng at(double m, {double eastM = 0}) =>
    LatLng(48.0 + m / _mPerDegLat, 9.0 + eastM / (_mPerDegLat * math.cos(48 * math.pi / 180)));

final t0 = DateTime.utc(2026, 11, 7, 10);

/// Dieselbe Abfahrt zweimal (Punkte 0–50 und 102–152), dazwischen der
/// Anstieg 300 m östlich; alle 4 s ein Punkt. Punkt 160 ist unscharf.
List<RidePoint> twice() {
  final out = <RidePoint>[];
  void leg(double from, double to, double eastM) {
    final step = from < to ? 20.0 : -20.0;
    for (var m = from; step > 0 ? m <= to : m >= to; m += step) {
      final p = at(m, eastM: eastM);
      out.add(RidePoint(
          lat: p.latitude, lng: p.longitude, at: t0.add(Duration(seconds: 4 * out.length)), accuracyM: 5));
    }
  }
  leg(0, 1000, 0);
  leg(1000, 0, 300);
  leg(0, 1000, 2);
  return out;
}

RideMark mark(RideMarkKind kind, int i, [String? name]) =>
    RideMark(kind: kind, at: t0.add(Duration(seconds: 4 * i)), name: name);

Trail named(String name, double fromM, double toM, {double eastM = 0}) => Trail(
      id: 't-$name',
      myId: 'me',
      details: [TrailDetails(trailId: 't-$name', userId: 'buddy', name: name)],
      recordings: [
        TrailRecording(
          id: 'rec-$name',
          trailId: 't-$name',
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
  test('liegt das Stück auf einem sichtbaren Trail, steht sein Name da', () {
    final s = suggestMarkName(
      points: twice(),
      marks: [mark(RideMarkKind.start, 5), mark(RideMarkKind.end, 45)],
      trails: [named('Anstieg', 900, 100, eastM: 300), named('Hexenstieg', 100, 900)],
    );
    expect(s?.name, 'Hexenstieg');
    expect(s?.source, MarkNameSource.network);
  });

  test('nur ein Stück des Trails gefahren: kein Vorschlag', () {
    // Markiert 100–900 m, der Trail läuft weiter bis 3 km.
    final s = suggestMarkName(
      points: twice(),
      marks: [mark(RideMarkKind.start, 5), mark(RideMarkKind.end, 45)],
      trails: [named('Lang', 100, 3000)],
    );
    expect(s, isNull);
    // Umgekehrt: Der Trail (300–700 m) ist nur die Hälfte des Markierten.
    expect(
        suggestMarkName(
          points: twice(),
          marks: [mark(RideMarkKind.start, 5), mark(RideMarkKind.end, 45)],
          trails: [named('Kurz', 300, 700)],
        ),
        isNull,
        reason: 'ein Trail im Stück ist nicht das Stück');
  });

  test('zweimal gefahren: der Name von vorhin', () {
    final points = twice();
    final marks = [
      mark(RideMarkKind.start, 5),
      mark(RideMarkKind.end, 45, 'Hausrunde'),
      mark(RideMarkKind.start, 107),
      mark(RideMarkKind.end, 147),
    ];
    final s = suggestMarkName(points: points, marks: marks, trails: const []);
    expect(s?.name, 'Hausrunde');
    expect(s?.source, MarkNameSource.earlierInRide);
    // Der Anstieg dazwischen ist eine andere Strecke.
    expect(
        suggestMarkName(points: points, marks: [...marks.take(2), mark(RideMarkKind.start, 56), mark(RideMarkKind.end, 96)], trails: const []),
        isNull);
  });

  test('ohne Ende als letzte Marke kein Vorschlag', () {
    expect(
        suggestMarkName(points: twice(), marks: [mark(RideMarkKind.start, 5)], trails: [named('Hexenstieg', 100, 900)]),
        isNull);
  });
}
