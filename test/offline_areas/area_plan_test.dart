// Die Planung eines Bereichs (Konzept 3.2): Welche Kacheln ein Rahmen
// berührt, die Obergrenze, der Rand um die Trails, die Größenangabe.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';

void main() {
  test('Kachel einer Koordinate: bekannte Werte, Ränder geklemmt', () {
    // Der Ursprung der Karte liegt oben links; die Mitte ist Kachel n/2.
    expect(tileAt(0, 0, 1), (x: 1, y: 1));
    expect(tileAt(85, -180, 3), (x: 0, y: 0));
    expect(tileAt(-85, 179.999, 3), (x: 7, y: 7));
    // Ein Punkt im Alpenvorland bei Zoom 13 (nachgerechnet mit der
    // Slippy-Map-Formel).
    expect(tileAt(47.9, 11.6, 13), (x: 4359, y: 2851));
  });

  test(
    'ein Rahmen berührt je Zoom ein Rechteck aus Kacheln; die Ids sind Hilbert-Ids',
    () {
      const bounds = AreaBounds(
        south: 47.9,
        west: 11.6,
        north: 47.95,
        east: 11.7,
      );
      final tiles = tilesCovering(bounds, minZoom: 12, maxZoom: 13);
      expect(tiles.where((t) => t.z == 12).length, greaterThanOrEqualTo(2));
      expect(
        tiles.where((t) => t.z == 13).length,
        greaterThan(tiles.where((t) => t.z == 12).length),
      );
      expect(
        tiles.length,
        countTilesCovering(bounds, minZoom: 12, maxZoom: 13),
      );
      for (final t in tiles) {
        expect(ZXY.fromTileId(tileIdOf(t)), ZXY(t.z, t.x, t.y));
      }
      // Bei Zoom 8 beginnt der Bereich: darunter liegt die Übersicht.
      expect(
        tilesCovering(bounds, maxZoom: 8).every((t) => t.z == kAreaMinZoom),
        isTrue,
      );
    },
  );

  test('ganz DACH überschreitet die Obergrenze, ein Wochenendgebiet nicht', () {
    const dach = AreaBounds(south: 45.5, west: 5.5, north: 55.5, east: 17.5);
    expect(countTilesCovering(dach, maxZoom: 13), greaterThan(kAreaMaxTiles));
    const weekend = AreaBounds(
      south: 47.4,
      west: 11.0,
      north: 47.9,
      east: 11.8,
    );
    expect(countTilesCovering(weekend, maxZoom: 13), lessThan(kAreaMaxTiles));
  });

  test(
    'der Rahmen um Punkte trägt den Rand, und ohne Punkte gibt es keinen',
    () {
      final b = AreaBounds.around(const [
        LatLng(47.9, 11.6),
        LatLng(47.95, 11.7),
      ])!;
      expect(b.south, lessThan(47.9));
      expect(b.north, greaterThan(47.95));
      expect(b.west, lessThan(11.6));
      expect(b.east, greaterThan(11.7));
      // 2 km sind ~0,018° Breite.
      expect(47.9 - b.south, closeTo(2 / 111, 1e-6));
      expect(b.contains(const LatLng(47.92, 11.65)), isTrue);
      expect(
        b.intersects(
          const AreaBounds(south: 48.5, west: 11, north: 49, east: 12),
        ),
        isFalse,
      );
      expect(AreaBounds.around(const []), isNull);
      expect(AreaBounds.fromJson(b.toJson()).north, b.north);
    },
  );

  group('Kachelmenge entlang der Trails (0.24.0)', () {
    // Ein Trail von 5 km, Nord–Süd, bei 47,9° N — und einer 60 km weiter
    // östlich. Ein Rahmen um beide wäre 60 km breit; die Kacheln entlang
    // der Trails sind zwei schmale Streifen.
    final near = [
      for (var i = 0; i <= 10; i++) LatLng(47.90 + i * 0.0045, 11.60),
    ];
    final far = [
      for (var i = 0; i <= 10; i++) LatLng(47.90 + i * 0.0045, 12.40),
    ];

    test(
      'nur die Kacheln, denen ein Trail nahe kommt — nicht das Land dazwischen',
      () {
        final shape = AreaShape.alongLines([near, far])!;
        final rect = RectShape(AreaBounds.around([...near, ...far])!);
        final along = shape.countTiles(maxZoom: 13);
        // Bei Zoom 13 (rund 3 km je Kachel) sind es zwei schmale Streifen
        // gegen 60 × 9 km; über alle Zooms nähern sich beide an, weil die
        // groben Kacheln so oder so dazugehören.
        expect(
          shape.countTiles(minZoom: 13, maxZoom: 13),
          lessThan(rect.countTiles(minZoom: 13, maxZoom: 13) ~/ 4),
          reason: 'zwei Streifen gegen ein 60 km breites Rechteck',
        );
        expect(along, lessThan(rect.countTiles(maxZoom: 13) ~/ 2));
        expect(shape.tiles(maxZoom: 13).length, along);
        // Jede Kachel bei Zoom 13 liegt nahe an einem der beiden Trails,
        // und jeder Trailpunkt liegt in einer Kachel der Menge.
        final z13 = shape.tiles(minZoom: 13, maxZoom: 13);
        for (final p in [...near, ...far]) {
          final t = tileAt(p.latitude, p.longitude, 13);
          expect(z13, contains((z: 13, x: t.x, y: t.y)));
        }
        for (final t in z13) {
          final b = tileBounds(13, t.x, t.y);
          expect(
            b.west < 11.7 || b.east > 12.3,
            isTrue,
            reason: 'Kachel mitten im Dazwischen: $t',
          );
        }
      },
    );

    test('Eltern darunter, Kinder darüber, gezählt wie geliefert', () {
      final shape = AreaShape.alongLines([near])!;
      final z12 = shape.tiles(minZoom: 12, maxZoom: 12).toSet();
      for (final t in shape.tiles(minZoom: 13, maxZoom: 13)) {
        expect(z12, contains((z: 12, x: t.x >> 1, y: t.y >> 1)));
      }
      final z14 = shape.tiles(minZoom: 14, maxZoom: 14);
      expect(z14.length, shape.keys.length * 4);
      expect(
        shape.countTiles(minZoom: 8, maxZoom: 14),
        shape.tiles(minZoom: 8, maxZoom: 14).length,
      );
      // Keine Kachel doppelt.
      final all = shape.tiles(maxZoom: 14);
      expect(all.toSet().length, all.length);
    });

    test('Hülle, Orte-Zellen und JSON-Rundlauf', () {
      final shape = AreaShape.alongLines([near])!;
      final hull = shape.hull;
      expect(hull.south, lessThan(47.90));
      expect(hull.north, greaterThan(47.945));
      expect(hull.west, lessThan(11.60));
      expect(hull.east, greaterThan(11.60));
      // Die Zellen der Kacheln, nicht die der Hülle — hier dasselbe,
      // bei zwei fernen Trails weniger.
      final cells = shape.poiCells();
      expect(cells, isNotEmpty);
      final two = AreaShape.alongLines([near, far])!;
      expect(
        two.poiCells().length,
        lessThan(RectShape(two.hull).poiCells().length),
      );
      final back = AreaShape.fromJson(shape.toJson());
      expect(back, isA<TileSetShape>());
      expect((back as TileSetShape).keys, shape.keys);
      expect(back.zoom, kAreaShapeZoom);
      expect(
        AreaShape.fromJson(
          const RectShape(
            AreaBounds(south: 1, west: 2, north: 3, east: 4),
          ).toJson(),
        ),
        isA<RectShape>(),
      );
      // Ohne Punkte keine Form; eine Kachel bleibt eine Kachel.
      expect(AreaShape.alongLines([[]]), isNull);
      expect(
        AreaShape.alongLines([
          const [LatLng(47.9, 11.6)],
        ])!.keys,
        isNotEmpty,
      );
    });

    test('tileBounds ist die Umkehrung von tileAt', () {
      final t = tileAt(47.9, 11.6, 13);
      final b = tileBounds(13, t.x, t.y);
      expect(b.contains(const LatLng(47.9, 11.6)), isTrue);
      expect(tileAt(b.north - 1e-9, b.west + 1e-9, 13), (x: t.x, y: t.y));
      expect(tileAt(b.south + 1e-9, b.east - 1e-9, 13), (x: t.x, y: t.y));
    });
  });

  test('Größen lesbar, deutsch', () {
    expect(formatBytes(512000), '512 kB');
    expect(formatBytes(12400000), '12,4 MB');
    expect(formatBytes(2800000000), '2,80 GB');
  });
}
