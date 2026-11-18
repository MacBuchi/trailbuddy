// Der Wege-Index (#29): Was aus einer Kachel eine Straße ist, wo sie in
// Grad liegt, und wann die gespeicherten Bereiche eine Fahrt decken.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/map/pmtiles_tile_provider.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';
import 'package:trailbuddy/features/rides/road_index.dart';

import '../fakes/fake_tiles.dart';

void main() {
  // Die z13-Kachel um 48,0° N / 9,0° O.
  final t = tileAt(48.0, 9.0, 13);

  test('Straße ist, was fährt — Pfade und Schienen nicht', () {
    expect(isRoadFeature(kind: 'highway', kindDetail: 'motorway'), isTrue);
    expect(isRoadFeature(kind: 'minor_road', kindDetail: 'service'), isTrue);
    expect(isRoadFeature(kind: 'other', kindDetail: 'road'), isTrue);
    expect(
      isRoadFeature(kind: 'path', kindDetail: 'track'),
      isTrue,
      reason: 'Forstweg',
    );
    expect(
      isRoadFeature(kind: 'path', kindDetail: 'path'),
      isFalse,
      reason: 'der Kandidat selbst',
    );
    expect(isRoadFeature(kind: 'path', kindDetail: 'footway'), isFalse);
    expect(isRoadFeature(kind: 'rail', kindDetail: null), isFalse);
    expect(isRoadFeature(kind: null, kindDetail: null), isFalse);
  });

  test('Kachel-Pixel werden zu Grad, nur die Straßen der roads-Ebene', () {
    final bytes = mvtTile([
      road([(0, 0), (4096, 4096)], 'minor_road'),
      road([(100, 200), (300, 200)], 'path', kindDetail: 'track'),
      road([(500, 500), (600, 600)], 'path', kindDetail: 'footway'),
      road([(0, 0), (10, 10)], 'minor_road', layer: 'water'),
    ]);
    final lines = roadLinesFromTile(bytes, z: 13, x: t.x, y: t.y);
    expect(lines, hasLength(2));
    // Die Diagonale beginnt in der Nordwest-Ecke der Kachel und endet in
    // der Südost-Ecke — beide Ecken liegen an der Kante zur Nachbarkachel.
    final nw = lines.first.first, se = lines.first.last;
    expect(nw.latitude, greaterThan(se.latitude));
    expect(nw.longitude, lessThan(se.longitude));
    expect(
      tileAt(nw.latitude - 1e-6, nw.longitude + 1e-6, 13),
      equals((x: t.x, y: t.y)),
    );
    expect(
      tileAt(se.latitude + 1e-6, se.longitude - 1e-6, 13),
      equals((x: t.x, y: t.y)),
    );
    // Etwa 5 km Kachelkante bei z13 auf 48° — die Diagonale ist länger.
    final d = const Distance().distance(nw, se);
    expect(d, inInclusiveRange(4000, 8000));
  });

  test('kaputte Bytes: keine Linien, kein Fehler', () {
    expect(
      roadLinesFromTile(
        Uint8List.fromList(utf8.encode('nicht protobuf')),
        z: 13,
        x: 1,
        y: 1,
      ),
      isEmpty,
    );
  });

  group('loadRoads', () {
    final proj = FlatProjection(48.0);
    final tileBytes = mvtTile([
      road([(0, 2048), (4096, 2048)], 'minor_road'),
    ]);
    const wide = AreaBounds(south: 47.9, west: 8.9, north: 48.1, east: 9.1);

    StoredArea area(String id, {int maxZoom = 13, AreaBounds? bounds}) =>
        StoredArea(
          id: id,
          name: id,
          bounds: bounds ?? wide,
          minZoom: 8,
          maxZoom: maxZoom,
          build: '20260928',
          tiles: 1,
          bytes: 1,
          savedAt: DateTime.utc(2026, 9, 28),
        );

    Future<PmTilesVectorTileProvider?> opener(MemoryAreaStore store) =>
        Future.value(null);

    Future<MemoryAreaStore> storeWith(
      List<TileXYZ> tiles, {
      int maxZoom = 13,
    }) async {
      final store = MemoryAreaStore();
      await store.putArchive(
        'a',
        writePmTiles(
          tiles: [for (final z in tiles) TileToWrite(z.z, z.x, z.y, tileBytes)],
          tileCompression: Compression.none,
          bounds: TileBounds(
            west: wide.west,
            south: wide.south,
            east: wide.east,
            north: wide.north,
          ),
        ),
      );
      await store.saveIndex([area('a', maxZoom: maxZoom)]);
      return store;
    }

    Future<PmTilesVectorTileProvider?> Function(StoredArea) openFrom(
      MemoryAreaStore store,
    ) => (a) async {
      final bytes = await store.readArchive(a.id);
      return bytes == null ? null : PmTilesVectorTileProvider.openBytes(bytes);
    };

    test(
      'eine Fahrt ganz in einer gespeicherten Kachel: Wege bekannt',
      () async {
        final store = await storeWith([(z: 13, x: t.x, y: t.y)]);
        // Ein Kasten von 200 m mitten in der Kachel.
        const box = LatBox(47.999, 8.999, 48.001, 9.001);
        final r = await loadRoads(
          areas: await store.list(),
          box: box,
          open: openFrom(store),
          projection: proj,
        );
        expect(r.coverage, RoadCoverage.complete);
        expect(r.tilesNeeded, 1);
        expect(r.index, isNotNull);
        expect(r.index!.isEmpty, isFalse);
        // Die Straße läuft waagerecht durch die Kachelmitte; 100 m
        // darüber ist keine Straße.
        final onRoad = roadLinesFromTile(
          tileBytes,
          z: 13,
          x: t.x,
          y: t.y,
        ).first.first;
        expect(r.index!.nearRoad(proj.xy(onRoad)), isTrue);
        expect(
          r.index!.nearRoad(
            proj.xy(LatLng(onRoad.latitude + 100 / 111320.0, onRoad.longitude)),
          ),
          isFalse,
        );
      },
    );

    test('eine Kachel fehlt: teilweise, also keine Wege', () async {
      final store = await storeWith([(z: 13, x: t.x, y: t.y)]);
      // Über die Kachelkante nach Osten hinaus.
      const box = LatBox(47.999, 8.999, 48.001, 9.06);
      final r = await loadRoads(
        areas: await store.list(),
        box: box,
        open: openFrom(store),
        projection: proj,
      );
      expect(r.coverage, RoadCoverage.partial);
      expect(r.tilesNeeded, greaterThan(r.tilesFound));
      expect(r.index, isNull);
    });

    test('ohne Bereich, oder mit einem bis Zoom 12: nichts bekannt', () async {
      const box = LatBox(47.999, 8.999, 48.001, 9.001);
      final none = await loadRoads(
        areas: const [],
        box: box,
        open: (_) async => null,
        projection: proj,
      );
      expect(none.coverage, RoadCoverage.none);

      final shallow = await storeWith([(z: 13, x: t.x, y: t.y)], maxZoom: 12);
      final r = await loadRoads(
        areas: await shallow.list(),
        box: box,
        open: openFrom(shallow),
        projection: proj,
      );
      expect(
        r.coverage,
        RoadCoverage.none,
        reason: 'Pfade stehen erst ab z13 in den Kacheln',
      );
      await opener(shallow);
    });
  });
}
