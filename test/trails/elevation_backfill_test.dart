// Höhen nachtragen (#16): Die gespeicherte Linie wird in der Datei
// wiedergefunden, auch wenn eine neue Vereinfachung eine andere ergäbe.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/trails/elevation_backfill.dart';
import 'package:trailbuddy/features/trails/gpx.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/trail.dart';

/// 1 200 m nach Norden, schnurgerade, aber gewellt (±5 m): 2D bleiben
/// zwei Punkte, 3D (seit 0.3.0) viele.
List<TrackPoint> wavy() => [
  for (var i = 0; i <= 60; i++)
    TrackPoint(
      48.0 + i * 20 / 111320.0,
      9.0,
      ele: 600 - i * 1.5 + (i.isEven ? 5 : -5),
    ),
];

List<TrackPoint> withoutEle(List<TrackPoint> pts) => [
  for (final p in pts) TrackPoint(p.lat, p.lon, time: p.time),
];

TrailRecording rec(
  List<TrackPoint> pts, {
  String id = 'r1',
  List<double>? ele,
}) => TrailRecording(
  id: id,
  trailId: 't1',
  userId: 'me',
  source: RecordingSource.import,
  recordedAt: null,
  reversed: false,
  quality: 0.4,
  createdAt: DateTime(2026),
  points: [for (final p in pts) LatLng(p.lat, p.lon)],
  lengthM: trackLengthM(pts),
  ele: ele,
);

void main() {
  final raw = wavy();
  // So hat ein Client vor 0.3.0 hochgeladen: ohne Höhen, also 2D.
  final old = simplify(withoutEle(raw));

  test('die alte Linie ist nicht die neue Vereinfachung', () {
    expect(old, hasLength(2));
    expect(simplify(raw).length, greaterThan(2));
  });

  test('die gespeicherten Punkte werden der Reihe nach wiedergefunden', () {
    final found = storedLineInTrack(rec(old).points, raw)!;
    expect(found, hasLength(2));
    expect(found.first.ele, raw.first.ele);
    expect(found.last.ele, raw.last.ele);

    final mid = [raw[0], raw[30], raw[60]];
    expect(storedLineInTrack(rec(mid).points, raw)!.map((p) => p.ele), [
      raw[0].ele,
      raw[30].ele,
      raw[60].ele,
    ]);
  });

  test('ein eigenes Teilstück ist nicht die ganze Datei', () {
    expect(storedLineInTrack(rec([raw[0], raw[10]]).points, raw), isNull);
    expect(storedLineInTrack(rec([raw[20], raw[60]]).points, raw), isNull);
  });

  test('ein fehlender oder vertauschter Punkt: nicht dieselbe Datei', () {
    final shifted = [raw[0], TrackPoint(raw[30].lat + 1e-5, 9.0), raw[60]];
    expect(storedLineInTrack(rec(shifted).points, raw), isNull);
    expect(storedLineInTrack(rec(old.reversed.toList()).points, raw), isNull);
  });

  test('eigene Aufzeichnung ohne Höhen + Datei mit Höhen ⇒ nachtragen', () {
    final track = GpxTrack(name: 'Welle', points: raw);
    final hit = findOwnRecording(track, [
      rec([raw[0], raw[10]], id: 'anders'),
      rec(old),
    ])!;
    expect(hit.recording.id, 'r1');
    expect(hit.canBackfill, isTrue);
    expect(hit.eles, [raw.first.ele, raw.last.ele]);
  });

  test('schon mit Höhen, oder die Datei hat keine ⇒ nichts nachzutragen', () {
    final withHeights = findOwnRecording(GpxTrack(name: 'W', points: raw), [
      rec(old, ele: [1, 2]),
    ])!;
    expect(withHeights.canBackfill, isFalse);
    final noEle = findOwnRecording(
      GpxTrack(name: 'W', points: withoutEle(raw)),
      [rec(old)],
    )!;
    expect(noEle.canBackfill, isFalse);
  });

  test('eine andere Spur trifft nichts', () {
    final other = [
      for (final p in raw) TrackPoint(p.lat, p.lon + 0.01, ele: p.ele),
    ];
    expect(
      findOwnRecording(GpxTrack(name: 'X', points: other), [rec(old)]),
      isNull,
    );
  });
}
