// Die Höhenlinien (#271) ohne Karte: Fenster, Weltraster, Glätten am Rand,
// Dichte aus dem Gelände, Hauptlinien, und dass sich Nachbarlinien nie
// kreuzen.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/map/contour_layer.dart';
import 'package:trailbuddy/features/map/contour_providers.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/offline_areas/height_tiles.dart';

const _s = kContourStepsPerTile;

/// Eine Kachel aus einer Höhenfunktion über dem Weltraster.
HeightTile _tile(int x, int y, int Function(int gx, int gy) h) => HeightTile(Int16List.fromList([
      for (var r = 0; r < kHeightGrid; r++)
        for (var c = 0; c < kHeightGrid; c++) h(x * _s + c, y * _s + r),
    ]));

/// Die Kacheln eines Fensters (plus Rand) aus [h].
Map<({int x, int y}), HeightTile> _tiles(ContourWindow w, int Function(int gx, int gy) h, {int pad = 1}) => {
      for (var y = w.y0 - pad; y <= w.y1 + pad; y++)
        for (var x = w.x0 - pad; x <= w.x1 + pad; x++) (x: x, y: y): _tile(x, y, h),
    };

/// Weltraster-Koordinate eines Punkts (Umkehrung von `contourLonAt` /
/// `contourLatAt`).
({double gx, double gy}) _grid(LatLng p) {
  const n = (1 << kHeightTileZoom) * _s;
  final gx = (p.longitude + 180) / 360 * n;
  final lat = p.latitude * math.pi / 180;
  final gy = (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * n;
  return (gx: gx, gy: gy);
}

final _origin = heightTileOf(const LatLng(47.3, 11.4));
final _window = ContourWindow(_origin.x, _origin.y, _origin.x + 2, _origin.y + 2);

void main() {
  group('Fenster', () {
    test('die Kacheln des Ausschnitts, mit Rand an der Kante', () {
      final t = heightTileOf(const LatLng(47.3, 11.4));
      // Ein Ausschnitt mitten in einer Kachel: genau diese.
      final inner = ContourWindow.covering(west: 11.401, east: 11.402, south: 47.2999, north: 47.3);
      expect(inner.tileCount, 1);
      expect((inner.x0, inner.y0), (t.x, t.y));
      // Der Westrand knapp hinter einer Kachelkante: die Nachbarin kommt mit.
      final westEdge = contourLonAt((t.x * _s).toDouble() + 0.5);
      final edge = ContourWindow.covering(west: westEdge, east: westEdge + 0.001, south: 47.2999, north: 47.3);
      expect(edge.x0, t.x - 1, reason: 'unter $kContourMarginSamples Proben Rand ⇒ Nachbarkachel');
    });

    test('Gleichheit nach Wert — Riverpod rechnet beim Schieben nicht neu', () {
      expect(const ContourWindow(1, 2, 3, 4), const ContourWindow(1, 2, 3, 4));
      expect(const ContourWindow(1, 2, 3, 4).hashCode, const ContourWindow(1, 2, 3, 4).hashCode);
      const b = MapViewBounds(west: 11.40, east: 11.45, south: 47.28, north: 47.30);
      const b2 = MapViewBounds(west: 11.4001, east: 11.4501, south: 47.2801, north: 47.3001);
      expect(contourInputOf((bounds: b, metersPerPixel: 10.0)), contourInputOf((bounds: b2, metersPerPixel: 10.02)),
          reason: 'ein wenig geschoben: dasselbe Fenster, derselbe gerasterte Maßstab');
    });

    test('der Ausdünnfaktor teilt 48 und hält das Budget', () {
      for (final n in [1, 3, 8, 11, 20]) {
        final f = contourSampleFactor(ContourWindow(0, 0, n - 1, 0));
        expect(_s % f, 0, reason: '$n Kacheln');
        expect(n * _s ~/ f + 1, lessThanOrEqualTo(kContourSampleBudget));
      }
      expect(contourSampleFactor(const ContourWindow(0, 0, 3, 3)), 1);
    });
  });

  group('Feld', () {
    test('liest die Proben exakt, auch über geteilte Kanten', () {
      int h(int gx, int gy) => (gx % 1000) + 2 * (gy % 1000);
      final tiles = _tiles(_window, h, pad: 0);
      final field = contourFieldFrom(_window, (x, y) => tiles[(x: x, y: y)], smooth: false);
      expect(field.cols, 3 * _s + 1);
      for (final (c, r) in [(0, 0), (48, 0), (49, 7), (96, 96), (144, 144)]) {
        expect(field.values[r * field.cols + c], h(field.gx0 + c, field.gy0 + r), reason: 'Probe $c/$r');
      }
    });

    test('fehlt eine Kachel, liest die Nachbarin die Kante', () {
      int h(int gx, int gy) => 500 + (gx % 100);
      final tiles = _tiles(_window, h, pad: 0)..remove((x: _origin.x + 1, y: _origin.y));
      final field = contourFieldFrom(_window, (x, y) => tiles[(x: x, y: y)], smooth: false);
      // Spalte 48 ist die Westkante der fehlenden Kachel = Ostkante der ersten.
      expect(field.values[5 * field.cols + 48], h(field.gx0 + 48, field.gy0 + 5));
      // Mitten in der fehlenden Kachel: nichts.
      expect(field.values[5 * field.cols + 70], kContourNoData);
    });

    test('nach dem Glätten hat jede Probe in jedem Fenster denselben Wert', () {
      int h(int gx, int gy) => 1000 + ((gx * 7 + gy * 13) % 97) + (gx ~/ 3);
      final a = ContourWindow(_origin.x, _origin.y, _origin.x + 1, _origin.y + 1);
      final b = ContourWindow(_origin.x + 1, _origin.y, _origin.x + 2, _origin.y + 1);
      final tiles = _tiles(_window, h);
      final fa = contourFieldFrom(a, (x, y) => tiles[(x: x, y: y)]);
      final fb = contourFieldFrom(b, (x, y) => tiles[(x: x, y: y)]);
      var compared = 0;
      for (var r = 0; r < fa.rows; r++) {
        for (var gx = fb.gx0; gx < fa.gx0 + fa.cols; gx++) {
          final va = fa.values[r * fa.cols + (gx - fa.gx0)];
          final vb = fb.values[r * fb.cols + (gx - fb.gx0)];
          expect(va, vb, reason: 'Probe $gx/$r');
          compared++;
        }
      }
      expect(compared, greaterThan(fa.rows * 40), reason: 'die gemeinsame Kachel wurde wirklich verglichen');
    });
  });

  group('Regeln', () {
    test('die Hauptlinien: mindestens alle 100 m, höchstens jede zweite', () {
      expect(contourIndexStepM(10), 100);
      expect(contourIndexStepM(20), 100);
      expect(contourIndexStepM(50), 100);
      expect(contourIndexStepM(100), 200);
      expect(contourIndexStepM(200), 400);
    });

    test('die Äquidistanz folgt dem Gelände', () {
      expect(contourEquidistanceM(reliefPerPixel: 0.3), 10);
      expect(contourEquidistanceM(reliefPerPixel: 2), 50);
      expect(contourEquidistanceM(reliefPerPixel: 4.5), 100);
      expect(contourEquidistanceM(reliefPerPixel: 20), isNull, reason: 'selbst 200 m wären eine Schraffur');
    });

    test('flach nah dran feiner als steil weit draußen; zu steil ⇒ Grund statt Linien', () {
      final tiles = {
        for (final slope in [2, 30])
          slope: _tiles(_window, (gx, gy) => 3000 - slope * (gy - _window.y0 * _s), pad: 0),
      };
      ({TerrainContours? contours, ContourGap? gap}) run(int slope, double mpp) => computeContours(ContourJob(
          field: contourFieldFrom(_window, (x, y) => tiles[slope]![(x: x, y: y)]),
          metersPerPixel: mpp,
          key: 'k'));
      expect(run(2, 3).contours!.equidistanceM, 10);
      expect(run(30, 8).contours!.equidistanceM, 100);
      expect(run(30, 12).contours!.equidistanceM, 200);
      expect(run(30, 30).gap, ContourGap.tooFarOut);
      expect(computeContours(ContourJob(field: contourFieldFrom(_window, (x, y) => null), metersPerPixel: 5, key: 'k')).gap,
          ContourGap.noHeights);
    });
  });

  group('Linien', () {
    test('ein Kegel: Ringe um die Spitze, Nachbarstufen kreuzen sich nie', () {
      final cx = (_window.x0 + 1.5) * _s, cy = (_window.y0 + 1.5) * _s;
      int h(int gx, int gy) => (1500 - 7 * math.sqrt(math.pow(gx - cx, 2) + math.pow(gy - cy, 2))).round();
      final tiles = _tiles(_window, h);
      final r = computeContours(ContourJob(
          field: contourFieldFrom(_window, (x, y) => tiles[(x: x, y: y)]), metersPerPixel: 4, key: 'k'));
      final c = r.contours!;
      expect(c.equidistanceM, 10);
      final radii = <int, ({double min, double max})>{};
      for (final line in c.lines) {
        for (final p in line.points) {
          final g = _grid(p);
          final d = math.sqrt(math.pow(g.gx - cx, 2) + math.pow(g.gy - cy, 2));
          final was = radii[line.level];
          radii[line.level] = (min: math.min(was?.min ?? d, d), max: math.max(was?.max ?? d, d));
        }
      }
      final levels = radii.keys.toList()..sort();
      expect(levels.length, greaterThan(8));
      for (var i = 1; i < levels.length; i++) {
        // Höher heißt näher an der Spitze — ganz innerhalb der tieferen Stufe.
        expect(radii[levels[i]]!.max, lessThan(radii[levels[i - 1]]!.min),
            reason: '${levels[i]} m liegt ganz innerhalb von ${levels[i - 1]} m');
      }
      // Und der Ring liegt, wo er hingehört (Radius = (1500 − Stufe) / 7).
      for (final l in levels.where((l) => l < 1400)) {
        final want = (1500 - l) / 7;
        expect(radii[l]!.min, greaterThan(want - 1.5), reason: '$l m');
        expect(radii[l]!.max, lessThan(want + 1.5), reason: '$l m');
      }
      expect(c.lines.where((l) => l.index).map((l) => l.level % 100).toSet(), {0});
    });

    test('Zahlen nur an Hauptlinien, nie kopfüber', () {
      int h(int gx, int gy) => 2000 - 5 * (gy - _window.y0 * _s);
      final tiles = _tiles(_window, h);
      final c = computeContours(ContourJob(
              field: contourFieldFrom(_window, (x, y) => tiles[(x: x, y: y)]), metersPerPixel: 4, key: 'k'))
          .contours!;
      final labels = contourLabels(c.lines, metersPerPixel: c.metersPerPixel);
      expect(labels, isNotEmpty);
      for (final l in labels) {
        expect(l.level % contourIndexStepM(c.equidistanceM), 0);
        expect(l.angleRadians.abs(), lessThanOrEqualTo(math.pi / 2));
      }
    });
  });

  test('der Maßstab: Meter je Pixel aus Fenster und Breite', () {
    final mpp = groundResolution(west: 11.0, east: 11.01, south: 47.0, north: 47.0, widthPixels: 400);
    expect(mpp, closeTo(0.01 * 111320 * math.cos(47 * math.pi / 180) / 400, 1e-9));
    expect(contourScaleStep(10.0), closeTo(contourScaleStep(10.02), 1e-12));
    expect(contourScaleStep(10.0), isNot(closeTo(contourScaleStep(12.0), 1e-6)));
  });
}
