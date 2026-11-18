// Die Hervorhebung gespeicherter Kacheln, pur: eine Maske über dem
// Ausschnitt mit Rand, die gespeicherten Kacheln als Löcher — seit 0.27.0
// IMMER beim Zoom des Bereichs (13), unabhängig von der Kamera, und
// zusammenhängende Kacheln als Rechtecke. Dazu seit 0.31.0 (Design Turn 2)
// ein durchgehender Rand um den ganzen Bestand.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/offline_areas/area_overlay.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';

StoredArea _area(String id, AreaShape shape, {int maxZoom = 13}) => StoredArea(
  id: id,
  name: id,
  bounds: shape.hull,
  shape: shape,
  minZoom: 8,
  maxZoom: maxZoom,
  build: '20260928',
  tiles: 1,
  bytes: 1,
  savedAt: DateTime.utc(2026, 9, 28),
);

const _view = MapViewBounds(
  south: 47.90,
  west: 11.60,
  north: 47.95,
  east: 11.70,
);

/// Die Kacheln bei [z], die die Löcher der Maske decken — jede genau
/// einmal, sonst schlägt der Test fehl.
Set<TileXYZ> _covered(List<List<LatLng>> holes, int z) {
  final out = <TileXYZ>{};
  for (final h in holes) {
    final b = AreaBounds(
      south: h[2].latitude,
      west: h[0].longitude,
      north: h[0].latitude,
      east: h[1].longitude,
    );
    final inner = AreaBounds(
      south: b.south + 1e-7,
      west: b.west + 1e-7,
      north: b.north - 1e-7,
      east: b.east - 1e-7,
    );
    for (final t in tilesCovering(inner, minZoom: z, maxZoom: z)) {
      expect(out.add(t), isTrue, reason: 'Kachel $t liegt in zwei Löchern');
    }
  }
  return out;
}

void main() {
  test(
    'Rechtecke aus Kacheln: genau die Menge, ohne Überlappung, zusammengefasst',
    () {
      final origin = tileAt(47.9, 11.6, 13);
      final x = origin.x, y = origin.y;
      // Ein 4×3-Block, darunter eine versetzte Zeile, daneben eine einzelne.
      final tiles = {
        for (var i = 0; i < 4; i++)
          for (var j = 0; j < 3; j++) (z: 13, x: x + i, y: y + j),
        (z: 13, x: x + 1, y: y + 3),
        (z: 13, x: x + 2, y: y + 3),
        (z: 13, x: x + 7, y: y),
      };
      final rects = mergeTileRects(tiles);
      expect(rects, hasLength(3), reason: 'Block, versetzte Zeile, Einzelne');
      final ring = [for (final r in rects) rectRing(r)];
      expect(_covered(ring, 13), tiles);
      // Eine Lückenzeile trennt gleiche Läufe.
      final gap = mergeTileRects({
        (z: 13, x: x, y: y),
        (z: 13, x: x, y: y + 2),
      });
      expect(gap, hasLength(2));
      expect(mergeTileRects(const []), isEmpty);
    },
  );

  test(
    'die Maske deckt den Ausschnitt mit Rand, die Löcher sind die gespeicherten Kacheln',
    () {
      const rect = RectShape(
        AreaBounds(south: 47.91, west: 11.62, north: 47.93, east: 11.66),
      );
      final mask = offlineCoverageMask([_area('r', rect)], _view)!;
      expect(mask.fillColor, kOfflineDimColor);
      final box = offlineOverlayBox(_view);
      expect(
        mask.points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b),
        closeTo(box.north, 1e-9),
      );
      expect(box.west, closeTo(11.50, 1e-9), reason: 'eine Fensterbreite Rand');
      expect(_covered(mask.holes, 13), rect.tilesWithin(box, 13).toSet());
      expect(mask.holes, hasLength(1), reason: 'ein Rahmen ist ein Rechteck');
    },
  );

  test('die Hervorhebung hängt NICHT am Kamera-Zoom (0.27.0)', () {
    // Derselbe Bereich, ein weiter und ein enger Ausschnitt: dieselben
    // Kacheln bei Zoom 13, nie ihre Eltern.
    const rect = RectShape(
      AreaBounds(south: 47.91, west: 11.62, north: 47.93, east: 11.66),
    );
    const wide = MapViewBounds(
      south: 47.0,
      west: 11.0,
      north: 48.5,
      east: 12.5,
    );
    final far = offlineCoverageMask([_area('r', rect)], wide)!;
    final near = offlineCoverageMask([_area('r', rect)], _view)!;
    expect(_covered(far.holes, 13), _covered(near.holes, 13));
  });

  test(
    'zwei Bereiche: dieselbe Kachel nur einmal, und ein alter Bereich zeigt seine feinsten',
    () {
      const a = RectShape(
        AreaBounds(south: 47.91, west: 11.62, north: 47.93, east: 11.66),
      );
      const b = RectShape(
        AreaBounds(south: 47.92, west: 11.64, north: 47.94, east: 11.68),
      );
      final both = offlineCoverageMask([_area('a', a), _area('b', b)], _view)!;
      final box = offlineOverlayBox(_view);
      expect(_covered(both.holes, 13), {
        ...a.tilesWithin(box, 13),
        ...b.tilesWithin(box, 13),
      });
      // Ein Bereich nur bis Zoom 10 hat keine 13er-Kacheln — seine 10er
      // sind die Löcher.
      final coarse = offlineCoverageMask([_area('c', a, maxZoom: 10)], _view)!;
      expect(_covered(coarse.holes, 10), a.tilesWithin(box, 10).toSet());
    },
  );

  test('ohne Bereiche ist alles dunkel; ein leerer Ausschnitt gibt nichts', () {
    final mask = offlineCoverageMask(const [], _view)!;
    expect(mask.holes, isEmpty);
    expect(
      offlineCoverageMask(
        const [],
        const MapViewBounds(south: 1, west: 1, north: 1, east: 1),
      ),
      isNull,
    );
  });

  test('eine Kachelmenge zeigt nur ihre Kacheln, nicht die Hülle', () {
    final line = [
      for (var i = 0; i <= 10; i++) LatLng(47.90 + i * 0.004, 11.62),
    ];
    final far = [
      for (var i = 0; i <= 10; i++) LatLng(47.90 + i * 0.004, 11.69),
    ];
    final shape = AreaShape.alongLines([line, far])!;
    final mask = offlineCoverageMask([_area('t', shape)], _view)!;
    final box = offlineOverlayBox(_view);
    expect(_covered(mask.holes, 13), shape.tilesWithin(box, 13).toSet());
    expect(
      _covered(mask.holes, 13).length,
      lessThan(RectShape(shape.hull).tilesWithin(box, 13).length),
    );
  });

  test('ganz DACH als ein Bereich: ein Rechteck, auch weit draußen', () {
    // Bis 0.26.x wich die Maske dafür auf gröbere Stufen aus; zusammengefasst
    // ist ein Rahmen immer EIN Loch.
    const dach = RectShape(
      AreaBounds(south: 45.5, west: 5.5, north: 55.5, east: 17.5),
    );
    const wide = MapViewBounds(south: 46, west: 6, north: 55, east: 17);
    final mask = offlineCoverageMask([_area('d', dach)], wide)!;
    expect(mask.holes, hasLength(1));
  });

  group('Rand um den Bestand (Design Turn 2)', () {
    final origin = tileAt(47.92, 11.64, 13);
    final x = origin.x, y = origin.y;
    // Ein großer Rahmen, damit kein Nachbar außerhalb liegt.
    const box = AreaBounds(south: 47.0, west: 11.0, north: 48.5, east: 12.5);

    /// Die Länge des Umrisses in Kachelkanten.
    int edges(List<List<LatLng>> lines) {
      final w = tileBounds(13, x, y).east - tileBounds(13, x, y).west;
      final h = tileBounds(13, x, y).north - tileBounds(13, x, y).south;
      var n = 0.0;
      for (final l in lines) {
        n +=
            (l[1].longitude - l[0].longitude).abs() / w +
            (l[1].latitude - l[0].latitude).abs() / h;
      }
      return n.round();
    }

    test('ein Block hat vier Linien, keine Nähte im Innern', () {
      final block = {
        for (var i = 0; i < 4; i++)
          for (var j = 0; j < 3; j++) (z: 13, x: x + i, y: y + j),
      };
      final lines = tileOutline(block, box)!;
      expect(lines, hasLength(4), reason: 'je Seite ein Lauf');
      expect(edges(lines), 2 * (4 + 3));
    });

    test(
      'ein Loch im Bestand bekommt seinen eigenen Rand, eine L-Form ihre Stufe',
      () {
        final ring = {
          for (var i = 0; i < 3; i++)
            for (var j = 0; j < 3; j++)
              if (i != 1 || j != 1) (z: 13, x: x + i, y: y + j),
        };
        expect(edges(tileOutline(ring, box)!), 12 + 4);
        final l = {
          (z: 13, x: x, y: y),
          (z: 13, x: x, y: y + 1),
          (z: 13, x: x + 1, y: y + 1),
        };
        expect(tileOutline(l, box), hasLength(6));
      },
    );

    test(
      'am Rand des Rahmens kein Rand: Was dahinter liegt, ist nicht gefragt',
      () {
        final tiles = {(z: 13, x: x, y: y), (z: 13, x: x + 1, y: y)};
        final b = tileBounds(13, x, y);
        // Der Rahmen endet in der linken Kachel.
        final tight = AreaBounds(
          south: b.south - 0.1,
          west: b.west + 1e-6,
          north: b.north + 0.1,
          east: b.east + 0.5,
        );
        expect(
          edges(tileOutline(tiles, tight)!),
          edges(tileOutline(tiles, box)!) - 1,
        );
        expect(tileOutline(tiles, box, maxLines: 1), isNull);
        expect(tileOutline(const [], box), isEmpty);
      },
    );

    test(
      'auf der Karte: in der Farbe des Aufrufers, durchgehend, ohne Kennung; ohne Bereich keiner',
      () {
        final a = tileBounds(13, x, y);
        final cov = offlineCoverage(
          [_area('r', RectShape(a))],
          _view,
          outlineColor: const Color(0xFF131A16),
        );
        expect(cov.outline, hasLength(4));
        for (final l in cov.outline) {
          expect(l.color, const Color(0xFF131A16));
          expect(
            l.dash,
            isNull,
            reason: 'durchgehend — gestrichelt heißt „offene Änderung"',
          );
          expect(l.hitValue, isNull, reason: 'ein Tipp geht hindurch');
        }
        expect(
          offlineCoverage([_area('r', RectShape(a))], _view).outline,
          isEmpty,
          reason: 'ohne Farbe kein Rand',
        );
        expect(
          offlineCoverage(const [], _view, outlineColor: Colors.white).outline,
          isEmpty,
        );
      },
    );
  });
}
