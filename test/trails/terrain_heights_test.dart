// Geländehöhen (#186): das Profil aus den Höhenkacheln, der Vergleich der
// Datei-Höhen mit dem Modell, und der Rundlauf Export → Import, in dem
// Modellhöhen nie als gemessene zurückkommen.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/offline_areas/height_tiles.dart';
import 'package:trailbuddy/features/trails/elevation_backfill.dart';
import 'package:trailbuddy/features/trails/gpx.dart';
import 'package:trailbuddy/features/trails/gpx_writer.dart';
import 'package:trailbuddy/features/trails/terrain_heights.dart';
import 'package:trailbuddy/features/trails/trail_export.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart' show RecordingSource;
import 'package:trailbuddy/features/trails/trail_import_screen.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_heights.dart';
import '../fakes/l10n_de.dart';

const _line = [LatLng(48.0, 9.0), LatLng(48.005, 9.0), LatLng(48.009, 9.0)];

Trail _trail({List<double>? ele}) => Trail(
      id: 't1',
      myId: 'me',
      recordings: [
        TrailRecording(
          id: 'r1',
          trailId: 't1',
          userId: 'me',
          source: RecordingSource.import,
          recordedAt: null,
          reversed: false,
          quality: 0.5,
          createdAt: DateTime(2026),
          points: _line,
          lengthM: 1000,
          ele: ele,
        ),
      ],
      details: const [TrailDetails(trailId: 't1', userId: 'me', name: 'Hang')],
    );

void main() {
  final reader = HeightReader([MemoryHeightSource(slopeHeightTiles())]);

  group('Profil aus dem Geländemodell', () {
    test('Proben alle 50 m, nach Norden bergab, gemessene Hysterese, kein steilstes Stück', () async {
      final p = (await terrainProfileOf(reader, _line))!;
      expect(p.fromTerrain, isTrue);
      expect(p.distM[1], closeTo(kClimbSampleM, 1e-6));
      expect(p.startM, greaterThan(p.endM + 50));
      expect(p.lossM, closeTo(p.startM - p.endM, 1e-6), reason: 'ein gleichmäßiger Hang hat keine Zacken');
      expect(p.gainM, 0);
      expect(p.steepestDescentPct, isNull, reason: 'ein 90-m-Raster kennt keine 50 m');
      final climb = (await reader.climbAlong(_line))!;
      expect(p.lossM, closeTo(climb.loss, 1e-6), reason: 'dieselbe Rechnung wie gemessen (climbAlong)');
    });

    test('fehlt eine Kachel, gibt es gar kein Profil', () async {
      const far = [LatLng(47.0, 11.0), LatLng(47.01, 11.0)];
      expect(await terrainProfileOf(reader, far), isNull);
      expect(await terrainHeightsAt(reader, [..._line, far.first]), isNull);
    });
  });

  group('Vergleich der Datei mit dem Modell', () {
    final model = [for (var i = 0; i < 100; i++) 900.0 - i];

    test('übliches Rauschen fällt nicht auf', () {
      final file = [for (var i = 0; i < 100; i++) model[i] + (i.isEven ? 12 : -9)];
      final c = compareToTerrain(file, model)!;
      expect(c.suspicious, isFalse);
    });

    test('ein Versatz der ganzen Spur fällt auf und wird benannt', () {
      final c = compareToTerrain([for (final m in model) m + 120], model)!;
      expect(c.offsetM, closeTo(120, 1e-9));
      expect(c.suspicious, isTrue);
      expect(c.reason(l10nDe), 'Die Höhen der Datei liegen im Mittel 120 m über dem Gelände.');
      expect(compareToTerrain([for (final m in model) m - 80], model)!.reason(l10nDe), contains('80 m unter'));
    });

    test('Sprünge fallen auf, auch ohne Versatz', () {
      final file = [for (var i = 0; i < 100; i++) model[i] + (i % 10 == 0 ? 400 : 0)];
      final c = compareToTerrain(file, model)!;
      expect(c.offsetSuspicious, isFalse);
      expect(c.spreadSuspicious, isTrue);
      expect(c.reason(l10nDe), startsWith('Die Höhen der Datei springen bis'));
    });

    test('ohne Paare kein Vergleich', () {
      expect(compareToTerrain(const [], const []), isNull);
      expect(compareToTerrain(const [1, 2], const [1]), isNull);
    });
  });

  group('Export mit Modellhöhen', () {
    test('ohne aufgezeichnete Höhen: Modellhöhen je Punkt, markiert', () async {
      final terrain = await terrainHeightsAt(reader, _line);
      final track = trailToGpx(_trail(), terrain: terrain);
      expect(track.terrainHeights, isTrue);
      expect(track.points.map((p) => p.ele), terrain);
    });

    test('aufgezeichnete Höhen gewinnen, eine unpassende Reihe wird nicht genommen', () {
      final recorded = trailToGpx(_trail(ele: [700, 650, 600]), terrain: [1, 2, 3]);
      expect(recorded.terrainHeights, isFalse);
      expect(recorded.points.map((p) => p.ele), [700, 650, 600]);
      final mismatch = trailToGpx(_trail(), terrain: [1, 2]);
      expect(mismatch.terrainHeights, isFalse);
      expect(mismatch.points.every((p) => p.ele == null), isTrue);
    });

    test('Rundlauf: die eigene Datei bringt keine Modellhöhen zurück', () async {
      final track = trailToGpx(_trail(), terrain: await terrainHeightsAt(reader, _line));
      final xml = writeGpx(name: track.name, points: track.points, terrainHeights: true);
      expect(xml, contains(kTrailBuddyGpxNamespace));
      expect(xml, contains('<ele>'), reason: 'andere Apps sehen die Höhen');

      final back = parseGpx(xml).single;
      expect(back.points.every((p) => p.ele == null), isTrue, reason: 'markiert ⇒ nicht gelesen');
      final c = ImportCandidate('x.gpx', back);
      expect(c.elevation, isNull);
      expect(c.checksTerrain, isFalse);
      final existing = findOwnRecording(back, _trail().recordings)!;
      expect(existing.canBackfill, isFalse, reason: 'kein Nachtragen aus Modellhöhen');

      // Gegenprobe: dieselbe Datei ohne Marke trägt ihre Höhen.
      final plain = parseGpx(writeGpx(name: track.name, points: track.points)).single;
      expect(plain.points.every((p) => p.ele != null), isTrue);
      expect(findOwnRecording(plain, _trail().recordings)!.canBackfill, isTrue);
    });
  });
}
