import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/trails/gpx.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';

/// Eine Linie nach Norden, `lengthM` lang, `stepM` je Punkt, mit linearer
/// Höhe von `eleStart` nach `eleEnd` und optional Zeiten für `kmh`.
List<TrackPoint> line(double lengthM,
    {double stepM = 10, double? eleStart, double? eleEnd, double? kmh}) {
  final n = (lengthM / stepM).round();
  const degPerM = 1 / 111320.0;
  return [
    for (var i = 0; i <= n; i++)
      TrackPoint(
        48.0 + i * stepM * degPerM,
        9.0,
        ele: eleStart == null || eleEnd == null
            ? null
            : eleStart + (eleEnd - eleStart) * i / n,
        time: kmh == null
            ? null
            : DateTime.utc(2026).add(
                Duration(milliseconds: (i * stepM / (kmh / 3.6) * 1000).round())),
      ),
  ];
}

void main() {
  test('Länge und Höhen werden gezählt', () {
    final pts = line(1000, eleStart: 600, eleEnd: 500);
    // 1° Breite sind 111 195 m (Haversine), das Gitter rechnet mit 111 320.
    expect(trackLengthM(pts), closeTo(1000, 5));
    final el = elevationGainLoss(pts)!;
    expect(el.gain, closeTo(0, 1e-6));
    expect(el.loss, closeTo(100, 1e-6));
    expect(elevationGainLoss(line(100)), isNull);
  });

  test('Importregel: kurz und bergab ist ein Trail, lang ist eine Fahrt', () {
    expect(classifyTrack(line(1000, eleStart: 600, eleEnd: 500)), TrackKind.trail);
    expect(classifyTrack(line(1000, eleStart: 500, eleEnd: 600)), TrackKind.ride);
    // Gemessen: alpine Trails bis 8 km, darüber Fahrten.
    expect(classifyTrack(line(7000, stepM: 50, eleStart: 2000, eleEnd: 1300)),
        TrackKind.trail);
    expect(classifyTrack(line(9000, stepM: 50, eleStart: 2000, eleEnd: 1300)),
        TrackKind.ride);
    // Ohne Höhen entscheidet die Länge — im Zweifel Trail.
    expect(classifyTrack(line(1000)), TrackKind.trail);
    // Mindestlänge 50 m (Patch 017): eine kurze Jump-Line ist ein Trail.
    expect(classifyTrack(line(60)), TrackKind.trail);
    expect(classifyTrack(line(40)), TrackKind.fragment);
  });

  test('geplant: ohne Zeiten oder mit 200 km/h, gefahren mit 18 km/h', () {
    expect(looksPlanned(line(1000)), isTrue);
    expect(looksPlanned(line(1000, kmh: 200)), isTrue);
    expect(looksPlanned(line(1000, kmh: 18)), isFalse);
    expect(sourceOf(line(1000, kmh: 18)), RecordingSource.import);
  });

  test('Vereinfachung behält Enden und Ecken, wirft Zwischenpunkte weg', () {
    final straight = line(1000, stepM: 5);
    final s = simplify(straight);
    expect(s.length, 2);
    expect(s.first.lat, straight.first.lat);
    expect(s.last.lat, straight.last.lat);
    // Eine Ecke 50 m nach Osten bleibt erhalten.
    final corner = [
      ...line(500, stepM: 5),
      const TrackPoint(48.005, 9.001),
      ...line(500, stepM: 5).map((p) => TrackPoint(p.lat + 0.0045, 9.0)),
    ];
    expect(simplify(corner).length, greaterThanOrEqualTo(3));
    expect(flatCoords(s), [9.0, 48.0, 9.0, s.last.lat]);
  });
}
