// Die Übernahme des Altbestands (#229, Konzept 8.5): Bereiche bis 0.105.x
// trugen eigene Archive. Die erste Liste nach dem Update legt jede Kachel
// mit dem Bau ihres Bereichs in den Kachelspeicher, die Orte-Dateien unter
// ihren Namen, macht den Eintrag zum Verweis und löscht erst dann den
// Altbestand — ohne Netz. Geht es schief, bleibt der Eintrag, wie er war.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/core/errors.dart';
import 'package:trailbuddy/features/map/way_layer.dart';
import 'package:trailbuddy/features/offline_areas/area_migration.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/height_tiles.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';
import 'package:trailbuddy/features/offline_areas/tile_store.dart';

const _b = AreaBounds(south: 47.9, west: 11.6, north: 47.95, east: 11.7);

Uint8List _archive(List<TileXYZ> tiles, String tag, {Compression compression = Compression.none}) => writePmTiles(
      tiles: [
        for (final t in tiles)
          TileToWrite(t.z, t.x, t.y,
              t.x.isOdd && tag == 'leer' ? Uint8List(0) : Uint8List.fromList(utf8.encode('$tag ${t.z}/${t.x}/${t.y}'))),
      ],
      tileCompression: compression,
      bounds: TileBounds(west: _b.west, south: _b.south, east: _b.east, north: _b.north),
    );

StoredArea _legacy(String id, {String region = 'dach', bool heights = false, bool ways = false, List<String> pois = const []}) =>
    StoredArea(
      id: id,
      name: 'Alt $id',
      bounds: _b,
      minZoom: 8,
      maxZoom: 12,
      build: '20260928',
      tiles: 1,
      bytes: 1,
      savedAt: DateTime.utc(2026, 9, 28),
      poiFiles: pois,
      heightTiles: heights ? 1 : 0,
      heightsBuild: heights ? '20261001' : null,
      wayTiles: ways ? 1 : 0,
      waysBuild: ways ? '20261007' : null,
      region: region,
    );

void main() {
  late MemoryAreaStore store;
  late MemoryTileStore tiles;

  setUp(() {
    store = MemoryAreaStore();
    tiles = MemoryTileStore();
  });

  test('Karte, Höhen, Wege und Orte in den Speicher, mit dem Bau des Bereichs; danach ist der Altbestand weg', () async {
    const shape = RectShape(_b);
    final map = shape.tiles(maxZoom: 12);
    final z13 = shape.tiles(minZoom: kHeightTileZoom, maxZoom: kHeightTileZoom);
    await store.putArchive('a', _archive(map, 'karte'));
    await store.putHeights('a', _archive(z13, 'hoehe', compression: Compression.gzip));
    await store.putWays('a', _archive(z13.take(2).toList(), 'weg'));
    await store.putLegacyPoiFile('a', '479_77.water.json', '{"pois":[]}');
    await store.saveIndex([_legacy('a', heights: true, ways: true, pois: const ['479_77.water.json'])]);

    final after = await migrateLegacyAreas(store, tiles);

    final area = after.single;
    expect(area.legacy, isFalse);
    expect(area.format, kStoredAreaFormat);
    expect(area.complete, isTrue);
    expect(area.shape, isA<RectShape>(), reason: 'die Form bleibt, wie sie ist');
    final index = await tiles.index('dach', TileLayer.map);
    expect(index.length, map.length);
    expect({for (final i in index.values) i.build}, {'20260928'});
    final t = map.last;
    expect(utf8.decode((await tiles.read('dach', TileLayer.map, t.z, t.x, t.y))!), 'karte ${t.z}/${t.x}/${t.y}');
    final heights = await tiles.index('dach', TileLayer.heights);
    expect(heights.length, z13.length);
    expect({for (final i in heights.values) i.build}, {'20261001'}, reason: 'Höhen tragen ihren eigenen Bau');
    expect((await tiles.index('dach', TileLayer.ways)).length, 2);
    expect(await store.readPoiFile('479_77.water.json'), '{"pois":[]}');
    // Der Altbestand ist weg — erst NACH der Übernahme.
    expect(store.archives, isEmpty);
    expect(store.heights, isEmpty);
    expect(store.ways, isEmpty);
    expect(store.legacyPoiFiles, isEmpty);
    // Ein zweiter Lauf tut nichts.
    final puts = tiles.puts;
    await migrateLegacyAreas(store, tiles);
    expect(tiles.puts, puts);
  });

  test('leere Kacheln (0 Bytes) kommen mit, ohne den Mehrfach-Leser des Pakets', () async {
    final map = const RectShape(_b).tiles(maxZoom: 12);
    await store.putArchive('a', _archive(map, 'leer'));
    await store.saveIndex([_legacy('a')]);
    await migrateLegacyAreas(store, tiles);
    final index = await tiles.index('dach', TileLayer.map);
    expect(index.length, map.length);
    expect(index.values.where((i) => i.bytes == 0), isNotEmpty);
  });

  test('ein kaputtes Archiv: der Eintrag bleibt Altbestand, der nächste Start versucht es wieder', () async {
    final reported = <Object>[];
    setErrorSink((context, error, stack) => reported.add(error));
    addTearDown(() => setErrorSink(null));
    await store.putArchive('kaputt', Uint8List.fromList([1, 2, 3]));
    await store.putArchive('gut', _archive(const RectShape(_b).tiles(maxZoom: 12), 'karte'));
    await store.saveIndex([_legacy('kaputt'), _legacy('gut')]);
    final after = await migrateLegacyAreas(store, tiles);
    expect({for (final a in after) a.id: a.legacy}, {'kaputt': true, 'gut': false},
        reason: 'ein Bereich, der nicht geht, hält die anderen nicht auf');
    expect(await store.readArchive('kaputt'), isNotNull, reason: 'nicht gelöscht, was nicht übernommen ist');
    expect(reported, hasLength(1));
  });

  test('ein Eintrag ohne Archiv wird zum Verweis ohne Kacheln', () async {
    await store.saveIndex([_legacy('leer', region: 'ca')]);
    final after = await migrateLegacyAreas(store, tiles);
    expect(after.single.legacy, isFalse);
    expect(await tiles.index('ca', TileLayer.map), isEmpty);
  });

  test('die Region eines Bereichs ist die Region seiner Kacheln', () async {
    await store.putArchive('k', _archive(const RectShape(_b).tiles(maxZoom: 12), 'karte'));
    await store.saveIndex([_legacy('k', region: 'ca')]);
    await migrateLegacyAreas(store, tiles);
    expect(await tiles.index('ca', TileLayer.map), isNotEmpty);
    expect(await tiles.index('dach', TileLayer.map), isEmpty);
    expect(kWaysZoom, kHeightTileZoom, reason: 'beide Begleitebenen bei z13 — die Übernahme nimmt dieselben Kacheln');
  });
}
