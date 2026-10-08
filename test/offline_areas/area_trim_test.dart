// Kacheln aus gespeicherten Bereichen herausnehmen (0.27.0), gegen
// Archive aus dem eigenen Schreiber: Der Plan misst lokal, was frei wird;
// das Ausführen schreibt das Archiv ohne die Kacheln neu (der Leser beider
// Engines zählt es richtig), behält gröbere Kacheln, solange darunter
// etwas liegt, streicht Orte-Dateien leerer Zellen — und ein Bereich,
// der leer wird, verschwindet ganz.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/features/map/poi.dart';
import 'package:trailbuddy/features/map/way_layer.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/area_trim.dart';
import 'package:trailbuddy/features/offline_areas/height_tiles.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';

const _z = kAreaShapeZoom;

void main() {
  late MemoryAreaStore store;

  // Ein Bereich aus vier 13er-Kacheln in einer Reihe, gespeichert bis 13.
  final origin = tileAt(47.9, 11.6, _z);
  final x = origin.x, y = origin.y;
  final keys = {for (var i = 0; i < 4; i++) TileSetShape.keyOf(x + i, y, _z)};
  final shape = TileSetShape(zoom: _z, keys: keys);

  Future<StoredArea> seed(
      {String id = 'a',
      TileSetShape? s,
      List<String> poiFiles = const [],
      bool heights = false,
      Set<int> wayColumns = const {}}) async {
    final sh = s ?? shape;
    final tiles = sh.tiles(maxZoom: _z);
    var heightTiles = 0, heightBytes = 0;
    if (heights) {
      final z13 = sh.tiles(minZoom: kHeightTileZoom, maxZoom: kHeightTileZoom);
      final hb = writePmTiles(
        tiles: [
          for (final t in z13)
            TileToWrite(t.z, t.x, t.y, encodeHeightTile(List.filled(kHeightGrid * kHeightGrid, 700 + t.x % 50))),
        ],
        tileCompression: Compression.gzip,
        bounds: TileBounds(west: sh.hull.west, south: sh.hull.south, east: sh.hull.east, north: sh.hull.north),
        metadata: heightsMetadata('Bereich $id', '20261001'),
      );
      await store.putHeights(id, hb);
      heightTiles = z13.length;
      heightBytes = hb.length;
    }
    // Wege nur in den Spalten [wayColumns] (Versatz zu x) — wie im
    // Host-Archiv fehlen Kacheln ohne getaggte Wege.
    var wayTiles = 0, wayBytes = 0;
    if (wayColumns.isNotEmpty) {
      final wanted = [
        for (final t in sh.tiles(minZoom: kWaysZoom, maxZoom: kWaysZoom))
          if (wayColumns.contains(t.x - x)) t,
      ];
      final wb = writePmTiles(
        tiles: [for (final t in wanted) TileToWrite(t.z, t.x, t.y, Uint8List.fromList(utf8.encode('w${t.x}')))],
        tileCompression: Compression.none,
        bounds: TileBounds(west: sh.hull.west, south: sh.hull.south, east: sh.hull.east, north: sh.hull.north),
        metadata: waysMetadata('Bereich $id', '20261007'),
      );
      await store.putWays(id, wb);
      wayTiles = wanted.length;
      wayBytes = wb.length;
    }
    final bytes = writePmTiles(
      tiles: [
        for (final t in tiles) TileToWrite(t.z, t.x, t.y, Uint8List.fromList(utf8.encode('t${t.z}/${t.x}/${t.y}'))),
      ],
      tileCompression: Compression.none,
      bounds: TileBounds(west: sh.hull.west, south: sh.hull.south, east: sh.hull.east, north: sh.hull.north),
    );
    await store.putArchive(id, bytes);
    final area = StoredArea(
      id: id,
      name: 'Bereich $id',
      bounds: sh.hull,
      shape: sh,
      minZoom: 8,
      maxZoom: _z,
      build: '20260928',
      tiles: tiles.length,
      bytes: bytes.length,
      savedAt: DateTime.utc(2026, 9, 28),
      poiFiles: poiFiles,
      heightTiles: heightTiles,
      heightBytes: heightBytes,
      heightsBuild: heights ? '20261001' : null,
      wayTiles: wayTiles,
      wayBytes: wayBytes,
      waysBuild: wayColumns.isEmpty ? null : '20261007',
    );
    await store.saveIndex([...await store.list(), area]);
    return area;
  }

  setUp(() => store = MemoryAreaStore());

  test('zwei Kacheln raus: gemessen, neu geschrieben, gegengelesen', () async {
    final area = await seed();
    final trimmer = AreaTrimmer(store);
    final removes = {TileSetShape.keyOf(x + 2, y, _z), TileSetShape.keyOf(x + 3, y, _z)};
    final plan = await trimmer.plan([area], removes);
    expect(plan.trims, hasLength(1));
    // Zwei 13er-Kacheln; ihr 12er-Elternteil nur, wenn keine Geschwister
    // mehr darunter liegen.
    expect(plan.freedTiles, greaterThanOrEqualTo(2));
    expect(plan.freedBytes, greaterThan(0));

    await trimmer.apply(plan);
    final after = (await store.list()).single;
    final newShape = after.shape as TileSetShape;
    expect(newShape.keys, {TileSetShape.keyOf(x, y, _z), TileSetShape.keyOf(x + 1, y, _z)});
    expect(after.tiles, area.tiles - plan.freedTiles);
    expect(after.bytes, (await store.readArchive('a'))!.length);
    final archive = await PmTilesArchive.fromBytes((await store.readArchive('a'))!);
    expect(archive.header.numberOfAddressedTiles, after.tiles);
    // Die verbliebenen Kacheln kommen Byte für Byte wie vorher zurück,
    // samt ihrer gröberen Eltern bis Zoom 8.
    for (final t in newShape.tiles(maxZoom: _z)) {
      final got = utf8.decode((await archive.tile(tileIdOf(t))).compressedBytes());
      expect(got, 't${t.z}/${t.x}/${t.y}');
    }
    expect(await archive.lookup(tileIdOf((z: _z, x: x + 3, y: y))), isNull);
  });

  test('die Höhen folgen den Kacheln: zwei raus heißt zwei Höhenkacheln raus, alle raus heißt kein Höhenarchiv', () async {
    final area = await seed(heights: true);
    final trimmer = AreaTrimmer(store);
    final removes = {TileSetShape.keyOf(x + 2, y, _z), TileSetShape.keyOf(x + 3, y, _z)};
    final plan = await trimmer.plan([area], removes);
    final trim = plan.trims.single;
    expect(trim.keepHeights.map((t) => t.x).toSet(), {x, x + 1});
    final mapOnly = (await AreaTrimmer(store).plan([await seed(id: 'm')], removes)).freedBytes;
    expect(plan.freedBytes, greaterThan(mapOnly), reason: 'die Höhenbytes zählen mit');
    await trimmer.apply(plan);
    final after = (await store.list()).firstWhere((a) => a.id == 'a');
    expect(after.heightTiles, 2);
    expect(after.heightsBuild, '20261001');
    final hb = (await store.readHeights('a'))!;
    expect(after.heightBytes, hb.length);
    final archive = await PmTilesArchive.fromBytes(hb);
    expect(archive.header.numberOfAddressedTiles, 2);
    final source = ArchiveHeightSource(archive);
    expect((await source.tile(x, y))!.valueAt(0, 0), 700 + x % 50);
    expect(await source.tile(x + 3, y), isNull);
    await source.close();
    // Alles raus: Bereich weg, Höhen weg.
    final all = await trimmer.plan(await store.list(), keys);
    expect(all.trims.firstWhere((t) => t.area.id == 'a').freedBytes, after.bytes + after.heightBytes);
    await trimmer.apply(all);
    expect(await store.readHeights('a'), isNull);
    expect(await store.list(), isEmpty, reason: '„m" hat dieselbe Form und geht mit');
  });

  test('die Wege folgen den Kacheln (#212); bleibt keine, fällt nur ihr Archiv weg, der Bau bleibt', () async {
    final area = await seed(wayColumns: {0, 2});
    final trimmer = AreaTrimmer(store);
    final removes = {TileSetShape.keyOf(x + 2, y, _z), TileSetShape.keyOf(x + 3, y, _z)};
    final plan = await trimmer.plan([area], removes);
    expect(plan.trims.single.keepWays.map((t) => t.x).toSet(), {x});
    final mapOnly = (await AreaTrimmer(store).plan([await seed(id: 'm')], removes)).freedBytes;
    expect(plan.freedBytes, greaterThan(mapOnly), reason: 'die Wege-Bytes zählen mit');
    await trimmer.apply(plan);
    final after = (await store.list()).firstWhere((a) => a.id == 'a');
    expect(after.wayTiles, 1);
    final wb = (await store.readWays('a'))!;
    expect(after.wayBytes, wb.length);
    final archive = await PmTilesArchive.fromBytes(wb);
    expect(archive.header.numberOfAddressedTiles, 1);
    expect(utf8.decode((await archive.tile(ZXY(_z, x, y).toTileId())).compressedBytes()), 'w$x');
    await archive.close();

    // Die letzte Wege-Kachel raus, Kartenkachel x+1 bleibt.
    final last = await trimmer.plan([after], {TileSetShape.keyOf(x, y, _z)});
    await trimmer.apply(last);
    final rest = (await store.list()).firstWhere((a) => a.id == 'a');
    expect(rest.tiles, greaterThan(0));
    expect(rest.hasWays, isFalse);
    expect(rest.waysBuild, '20261007', reason: 'geholt ist geholt — kein Angebot zum Nachladen');
    expect(await store.readWays('a'), isNull);
  });

  test('bleibt keine Höhenkachel, verschwindet nur das Höhenarchiv, der Bereich bleibt', () async {
    // Ein Bereich aus zwei 13er-Kacheln, Höhen nur für eine davon.
    final two = TileSetShape(zoom: _z, keys: {TileSetShape.keyOf(x, y, _z), TileSetShape.keyOf(x + 1, y, _z)});
    final area = await seed(id: 'h', s: two);
    final hb = writePmTiles(
      tiles: [TileToWrite(_z, x + 1, y, encodeHeightTile(List.filled(kHeightGrid * kHeightGrid, 5)))],
      tileCompression: Compression.gzip,
      bounds: const TileBounds(west: 11, south: 47, east: 12, north: 48),
    );
    await store.putHeights('h', hb);
    await store.saveIndex([
      StoredArea(
        id: 'h', name: area.name, bounds: area.bounds, shape: two, minZoom: 8, maxZoom: _z,
        build: area.build, tiles: area.tiles, bytes: area.bytes, savedAt: area.savedAt,
        heightTiles: 1, heightBytes: hb.length, heightsBuild: '20261001',
      ),
    ]);
    final trimmer = AreaTrimmer(store);
    await trimmer.apply(await trimmer.plan(await store.list(), {TileSetShape.keyOf(x + 1, y, _z)}));
    final after = (await store.list()).single;
    expect(after.hasHeights, isFalse);
    expect(after.heightsBuild, isNull);
    expect(await store.readHeights('h'), isNull);
    expect(await store.readArchive('h'), isNotNull);
  });

  test('eine Kachel, die keine Form hat, fasst der Plan nicht an', () async {
    final area = await seed();
    final plan = await AreaTrimmer(store).plan([area], {TileSetShape.keyOf(x + 20, y, _z)});
    expect(plan.isEmpty, isTrue);
  });

  test('alles raus: der Bereich verschwindet samt Archiv', () async {
    final area = await seed();
    await seed(id: 'b', s: TileSetShape(zoom: _z, keys: {TileSetShape.keyOf(x + 40, y, _z)}));
    final trimmer = AreaTrimmer(store);
    final plan = await trimmer.plan(await store.list(), keys);
    expect(plan.trims.single.shape, isNull);
    expect(plan.freedBytes, area.bytes);
    await trimmer.apply(plan);
    expect((await store.list()).map((a) => a.id), ['b'], reason: 'der andere bleibt');
    expect(await store.readArchive('a'), isNull);
  });

  test('Orte-Dateien bleiben nur für Zellen, die der Bereich noch berührt', () async {
    // Zwei Bereichshälften in verschiedenen Orte-Zellen: weit genug
    // auseinander, dass sie sicher in verschiedenen Zellen liegen.
    final far = tileAt(47.9, 11.9, _z);
    final twoCells = TileSetShape(zoom: _z, keys: {
      TileSetShape.keyOf(x, y, _z),
      TileSetShape.keyOf(far.x, far.y, _z),
    });
    final cellsNear = TileSetShape(zoom: _z, keys: {TileSetShape.keyOf(x, y, _z)}).poiCells();
    final cellsFar = TileSetShape(zoom: _z, keys: {TileSetShape.keyOf(far.x, far.y, _z)}).poiCells();
    final files = [
      for (final c in {...cellsNear, ...cellsFar}) poiCellFileName(c, PoiGroup.water),
    ];
    final area = await seed(s: twoCells, poiFiles: files);
    final trimmer = AreaTrimmer(store);
    await trimmer.apply(await trimmer.plan([area], {TileSetShape.keyOf(far.x, far.y, _z)}));
    final after = (await store.list()).single;
    expect(after.poiFiles, [for (final c in cellsNear) poiCellFileName(c, PoiGroup.water)]);
  });

  test('ein Rahmen-Bereich wird zur Kachelmenge ohne die herausgenommenen', () async {
    final rect = tileBounds(_z, x, y);
    const id = 'r';
    final rectShape = RectShape(AreaBounds(
        south: rect.south + 1e-6, west: rect.west + 1e-6, north: rect.north - 1e-6,
        east: tileBounds(_z, x + 2, y).east - 1e-6));
    final tiles = rectShape.tiles(maxZoom: _z);
    await store.putArchive(
        id,
        writePmTiles(
          tiles: [for (final t in tiles) TileToWrite(t.z, t.x, t.y, Uint8List.fromList([t.z, t.x % 256, t.y % 256]))],
          tileCompression: Compression.none,
          bounds: TileBounds(west: rect.west, south: rect.south, east: rect.east, north: rect.north),
        ));
    final area = StoredArea(
      id: id,
      name: 'Rahmen',
      bounds: rectShape.bounds,
      shape: rectShape,
      minZoom: 8,
      maxZoom: _z,
      build: '20260928',
      tiles: tiles.length,
      bytes: 1,
      savedAt: DateTime.utc(2026, 9, 28),
    );
    await store.saveIndex([area]);
    final trimmer = AreaTrimmer(store);
    await trimmer.apply(await trimmer.plan([area], {TileSetShape.keyOf(x + 1, y, _z)}));
    final after = (await store.list()).single;
    expect(after.shape, isA<TileSetShape>());
    expect((after.shape as TileSetShape).keys, {TileSetShape.keyOf(x, y, _z), TileSetShape.keyOf(x + 2, y, _z)});
  });
}
