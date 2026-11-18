// Linienart = Zustand, Saum = S4/S5 (Rework E9, #101): EINE Regel für
// beide Engines, ohne Pixel geprüft.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/map/map_view/maplibre_map_view.dart';
import 'package:trailbuddy/features/trails/grade_shield.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/trail.dart';

TrailRecording _rec() => TrailRecording(
  id: 'r',
  trailId: 't',
  userId: 'me',
  source: RecordingSource.app,
  recordedAt: null,
  reversed: false,
  quality: 0.6,
  createdAt: DateTime(2026, 9, 1),
  points: const [LatLng(48, 9), LatLng(48.01, 9)],
  lengthM: 1000,
);

Trail _trail({
  int? grade,
  int? condition,
  bool confirmed = true,
  bool pending = false,
}) => Trail(
  id: 't',
  myId: 'me',
  pending: pending,
  recordings: [_rec()],
  details: [TrailDetails(trailId: 't', userId: 'me', grade: grade)],
  reports: [
    if (condition != null)
      TrailReport(
        id: 'c',
        trailId: 't',
        userId: 'me',
        kind: ReportKind.condition,
        condition: condition,
        confirmed: confirmed,
        reportedAt: DateTime(2026, 9, 20),
      ),
  ],
);

void main() {
  test(
    'Zustand: durchgezogen → bröckelig → gestrichelt → gestrichelt und verblasst',
    () {
      for (final c in [null, 5, 4]) {
        final s = trailLineStyleOf(_trail(condition: c));
        expect((s.dash, s.opacity), (null, 1.0), reason: 'Zustand $c');
      }
      expect(trailLineStyleOf(_trail(condition: 3)).dash, kLineDashWorn);
      expect(trailLineStyleOf(_trail(condition: 2)).dash, kLineDashRough);
      final worst = trailLineStyleOf(_trail(condition: 1));
      expect(worst.dash, kLineDashRough);
      expect(worst.opacity, lessThan(1));
      expect(
        kLineDashWorn,
        isNot(kLineDashRough),
        reason: 'bröckelig und gestrichelt unterscheidbar',
      );
    },
  );

  test('ein unbestätigter Zustand ändert die Linie nicht', () {
    expect(
      trailLineStyleOf(_trail(condition: 1, confirmed: false)).dash,
      isNull,
    );
  });

  test('S4/S5 im Saum, unabhängig vom Zustand; darunter kein Muster', () {
    expect(trailLineStyleOf(_trail(grade: 3)).haloDash, isNull);
    expect(trailLineStyleOf(_trail(grade: 4)).haloDash, kHaloDashExpert);
    final both = trailLineStyleOf(_trail(grade: 5, condition: 2));
    expect(both.haloDash, kHaloDashExpert);
    expect(both.dash, kLineDashRough, reason: 'Saum und Linie sagen je ihres');
  });

  test('wartend: gestrichelt und blass wie bisher', () {
    final s = trailLineStyleOf(_trail(pending: true, condition: 3));
    expect(s.dash, kLineDashPending);
    expect(s.opacity, 0.6);
  });

  test('MapLibre: der Saum bekommt sein eigenes Muster, die Linie ihres', () {
    final layers = mapLibrePolylineLayers([
      const MapViewPolyline(
        points: [LatLng(48, 9), LatLng(48.01, 9)],
        color: Color(0xFF131A16),
        borderColor: Color(0xFFFFFFFF),
        borderWidth: 2,
        borderDash: kHaloDashExpert,
      ),
    ], null);
    final lines = layers.whereType<RoundPolylineLayer>().toList();
    expect(lines, hasLength(2));
    expect(
      lines.first.dashArray,
      isNotNull,
      reason: 'der Saum darunter, gestrichelt',
    );
    expect(lines.last.dashArray, isNull, reason: 'die Linie durchgezogen');
  });

  test(
    'ein anderes Saum-Muster ist ein anderer Stil (eigene Ebene in MapLibre)',
    () {
      const a = MapViewPolyline(
        points: [],
        color: Color(0xFF000000),
        borderColor: Color(0xFFFFFFFF),
        borderWidth: 2,
      );
      const b = MapViewPolyline(
        points: [],
        color: Color(0xFF000000),
        borderColor: Color(0xFFFFFFFF),
        borderWidth: 2,
        borderDash: kHaloDashExpert,
      );
      expect(a.styleKey, isNot(b.styleKey));
    },
  );
}
