// Der Download eines Bereichs (Konzept 3.2), gegen ein Quellarchiv aus
// dem eigenen Schreiber: Der Plan zählt und misst, der Download holt
// über den `tiles()`-Strom, legt ein Archiv ab, das der Leser beider
// Engines öffnet, nimmt die Orte-Zellen mit, meldet Fortschritt, und ein
// Abbruch hinterlässt nichts.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/features/map/online_map.dart';
import 'package:trailbuddy/features/map/poi.dart';
import 'package:trailbuddy/features/map/way_layer.dart';
import 'package:trailbuddy/features/offline_areas/area_downloader.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/height_tiles.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';

const _manifest = MapManifest(
  file: 'dach-20260928.pmtiles',
  maxZoom: 10,
  bytes: 1,
  sourceBuild: '20260928',
);

/// Ein Quellarchiv: Zoom 8–10 über einem Rechteck, das größer ist als
/// der Bereich, den die Tests speichern.
Future<PmTilesArchive> _source() async {
  const wide = AreaBounds(south: 47.0, west: 10.0, north: 48.5, east: 12.5);
  final tiles = [
    for (final t in tilesCovering(wide, maxZoom: 10))
      TileToWrite(t.z, t.x, t.y, Uint8List.fromList(utf8.encode('t${t.z}/${t.x}/${t.y}' * (1 + t.x % 4)))),
  ];
  final bytes = writePmTiles(
      tiles: tiles,
      tileCompression: Compression.none,
      bounds: const TileBounds(west: 10, south: 47, east: 12.5, north: 48.5));
  return PmTilesArchive.fromBytes(bytes);
}

const _boundsSouth = 47.9, _boundsWest = 11.6;
const _bounds = AreaBounds(south: _boundsSouth, west: _boundsWest, north: 47.95, east: 11.7);

const _heightsManifest = HeightsManifest(file: 'heights-20261001.pmtiles', bytes: 1, build: '20261001');

/// Das Höhenarchiv des Hosts: eine Ebene (Höhe = 1000 + x-Versatz), z13
/// über demselben Rechteck wie die Karte, gzip wie das Werkzeug.
Future<PmTilesArchive> _heightsSource() async {
  const wide = AreaBounds(south: 47.0, west: 10.0, north: 48.5, east: 12.5);
  final origin = tileAt(47.0, 10.0, kHeightTileZoom);
  final tiles = [
    for (final t in tilesCovering(wide, minZoom: kHeightTileZoom, maxZoom: kHeightTileZoom))
      TileToWrite(t.z, t.x, t.y, encodeHeightTile([
        for (var j = 0; j < kHeightGrid; j++)
          for (var i = 0; i < kHeightGrid; i++) 1000 + (t.x - origin.x) * 10 + i ~/ 8,
      ])),
  ];
  return PmTilesArchive.fromBytes(writePmTiles(
      tiles: tiles,
      tileCompression: Compression.gzip,
      bounds: const TileBounds(west: 10, south: 47, east: 12.5, north: 48.5),
      metadata: heightsMetadata('Host', '20261001')));
}

const _waysManifest = WaysManifest(file: 'ways-20261007.pmtiles', bytes: 1, build: '20261007');

/// Das Wege-Archiv des Hosts: z13, aber nur jede zweite Spalte — Kacheln
/// ohne getaggte Wege fehlen im echten Archiv auch. Mit [only] nur die
/// Kacheln, die es nennt (leer: ein Archiv, das hier nichts hat).
Future<PmTilesArchive> _waysSource({Set<TileXYZ>? only}) async {
  const wide = AreaBounds(south: 47.0, west: 10.0, north: 48.5, east: 12.5);
  final tiles = [
    for (final t in tilesCovering(wide, minZoom: kWaysZoom, maxZoom: kWaysZoom))
      if (only == null ? t.x.isEven : only.contains(t))
        TileToWrite(t.z, t.x, t.y, Uint8List.fromList(utf8.encode('w${t.x}/${t.y}'))),
  ];
  return PmTilesArchive.fromBytes(writePmTiles(
      tiles: tiles.isEmpty ? [TileToWrite(kWaysZoom, 0, 0, Uint8List.fromList([1]))] : tiles,
      tileCompression: Compression.gzip,
      bounds: const TileBounds(west: 10, south: 47, east: 12.5, north: 48.5),
      metadata: waysMetadata('Host', '20261007')));
}

void main() {
  late PmTilesArchive source;
  late MemoryAreaStore store;
  late List<String> poiAsked;

  setUp(() async {
    source = await _source();
    store = MemoryAreaStore();
    poiAsked = [];
  });

  AreaDownloader make({PoiManifest? poiManifest, PmTilesArchive? heights, PmTilesArchive? ways}) =>
      AreaDownloader(
        archive: source,
        manifest: _manifest,
        store: store,
        poiManifest: poiManifest,
        heights: heights,
        heightsManifest: heights == null ? null : _heightsManifest,
        ways: ways,
        waysManifest: ways == null ? null : _waysManifest,
        fetchPoiFile: (name) async {
          poiAsked.add(name);
          return name.endsWith('.water.json') ? '{"format":1,"pois":[]}' : null;
        },
        chunkSize: 7,
        now: () => DateTime.utc(2026, 9, 28, 19),
      );

  test('der Plan zählt die Kacheln des Hosts und summiert ihre Bytes', () async {
    final plan = await make().plan(const RectShape(_bounds));
    expect(plan.maxZoom, 10);
    expect(plan.tiles, isNotEmpty);
    var expected = 0;
    for (final t in plan.tiles) {
      expected += (await source.lookup(tileIdOf(t)))!.length;
    }
    expect(plan.bytes, expected);
    // Außerhalb der Quelle: keine Kachel, keine Bytes — kein Fehler.
    final sea = await make().plan(const RectShape(AreaBounds(south: 30, west: -30, north: 30.1, east: -29.9)));
    expect(sea.tiles, isEmpty);
    expect(sea.bytes, 0);
  });

  test('eine Kachelmenge holt genau ihre Kacheln und nur die Orte-Zellen der Kacheln', () async {
    // Zwei Trails weit auseinander: Das Archiv trägt zwei Streifen, die
    // Orte-Zellen sind die der Kacheln, nicht die des Rahmens dazwischen.
    final near = [for (var i = 0; i <= 5; i++) LatLng(47.90 + i * 0.005, 11.60)];
    final far = [for (var i = 0; i <= 5; i++) LatLng(47.90 + i * 0.005, 12.40)];
    final shape = AreaShape.alongLines([near, far])!;
    final hull = shape.hull;
    final allCells = poiCellsCovering(hull.south, hull.west, hull.north, hull.east);
    final poiManifest = PoiManifest(
      build: '20260928',
      prefix: 'pois-20260928',
      cells: {PoiGroup.water: allCells.toSet()},
    );
    final downloader = make(poiManifest: poiManifest);
    final plan = await downloader.plan(shape);
    expect(plan.shape, same(shape));
    expect(plan.tiles.toSet(), shape.tiles(maxZoom: 10).toSet(),
        reason: 'die Quelle deckt die Streifen ganz');
    final area = await downloader.download(plan, name: 'Zwei Streifen');
    expect(area.shape, isA<TileSetShape>());
    expect(area.tiles, plan.tiles.length);
    expect(area.poiFiles.length, shape.poiCells().length);
    expect(area.poiFiles.length, lessThan(allCells.length));
    // Der Index-Rundlauf behält die Form — „Aktualisieren" braucht sie.
    final back = StoredArea.fromJson(area.toJson());
    expect((back.shape as TileSetShape).keys, shape.keys);
    expect(back.bounds.west, closeTo(hull.west, 1e-9));
  });

  test('zu groß wird abgelehnt, bevor eine Kachel nachgeschlagen ist', () async {
    const dach = AreaBounds(south: 45.5, west: 5.5, north: 55.5, east: 17.5);
    final downloader = AreaDownloader(
        archive: source,
        manifest: const MapManifest(file: 'dach-20260928.pmtiles', maxZoom: 13, bytes: 1, sourceBuild: '20260928'),
        store: store,
        fetchPoiFile: (_) async => null);
    expect(() => downloader.plan(const RectShape(dach)), throwsA(isA<AreaTooLarge>()));
  });

  test('der Download legt ein lesbares Archiv ab, samt Orte-Zellen und Index', () async {
    final cells = poiCellsCovering(_bounds.south, _bounds.west, _bounds.north, _bounds.east);
    final poiManifest = PoiManifest(
      build: '20260928',
      prefix: 'pois-20260928',
      cells: {PoiGroup.water: cells.toSet(), PoiGroup.food: {cells.first}},
    );
    final downloader = make(poiManifest: poiManifest);
    final plan = await downloader.plan(const RectShape(_bounds));
    final progress = <AreaProgress>[];
    final area = await downloader.download(plan, name: 'Isartrails', onProgress: progress.add);

    expect(area.name, 'Isartrails');
    expect(area.tiles, plan.tiles.length);
    expect(area.build, '20260928');
    expect(area.minZoom, kAreaMinZoom);
    expect(area.maxZoom, 10);
    expect(area.savedAt, DateTime.utc(2026, 9, 28, 19));
    expect(area.poiBuild, '20260928');
    // Wasser für jede Zelle, Einkehr nur für die eine; die 404 fehlen.
    expect(area.poiFiles, [
      for (final c in cells) poiCellFileName(c, PoiGroup.water),
    ]..sort());
    expect(poiAsked, hasLength(cells.length + 1));
    expect(await store.readPoiFile(poiCellFileName(cells.first, PoiGroup.water)), contains('"pois"'));

    // Das Archiv: jede geplante Kachel, Byte für Byte wie die Quelle.
    final stored = await PmTilesArchive.fromBytes((await store.readArchive(area.id))!);
    expect(stored.header.numberOfAddressedTiles, plan.tiles.length);
    for (final t in plan.tiles) {
      final id = tileIdOf(t);
      expect((await stored.tile(id)).compressedBytes(), (await source.tile(id)).compressedBytes());
    }
    expect(area.bytes, greaterThan(0));
    expect((await store.list()).single.id, area.id);

    // Der Fortschritt: Kacheln, dann Orte, dann Schreiben, monoton.
    expect(progress.first.phase, AreaPhase.tiles);
    expect(progress.where((p) => p.phase == AreaPhase.tiles).last.done, plan.tiles.length);
    expect(progress.any((p) => p.phase == AreaPhase.pois), isTrue);
    expect(progress.last.phase, AreaPhase.writing);
  });

  test('Messen mit Orten (0.27.0): zählt die Orte, und der Download holt sie nicht noch einmal', () async {
    final cells = poiCellsCovering(_bounds.south, _bounds.west, _bounds.north, _bounds.east);
    final poiManifest = PoiManifest(
      build: '20260928',
      prefix: 'pois-20260928',
      cells: {PoiGroup.water: {cells.first}},
    );
    const two = '{"format":1,"pois":['
        '{"id":"n1","kind":"spring","lat":47.91,"lng":11.61},'
        '{"id":"n2","kind":"spring","lat":47.92,"lng":11.62},'
        '{"id":"n3","kind":"unbekannt","lat":47.92,"lng":11.62}]}';
    final downloader = AreaDownloader(
      archive: source,
      manifest: _manifest,
      store: store,
      poiManifest: poiManifest,
      fetchPoiFile: (name) async {
        poiAsked.add(name);
        return two;
      },
    );
    final plan = await downloader.plan(const RectShape(_bounds), withPois: true);
    expect(plan.poiCount, 2, reason: 'eine unbekannte Art zählt nicht, wie auf der Karte');
    expect(plan.poiBytes, utf8.encode(two).length);
    expect(plan.totalBytes, plan.bytes + plan.poiBytes);
    expect(poiAsked, hasLength(1));
    final area = await downloader.download(plan, name: 'Mit Orten');
    expect(poiAsked, hasLength(1), reason: 'die Dateien kamen schon mit dem Plan');
    expect(area.poiFiles, [poiCellFileName(cells.first, PoiGroup.water)]);
    // Ohne Orte gemessen: keine Zahl.
    expect((await make().plan(const RectShape(_bounds))).poiCount, isNull);
  });

  test('mit Höhenarchiv: der Plan zählt die Höhenkacheln der z13-Form, der Download legt das zweite Archiv ab', () async {
    final heights = await _heightsSource();
    addTearDown(heights.close);
    final downloader = make(heights: heights);
    const shape = RectShape(_bounds);
    final plan = await downloader.plan(shape);
    final z13 = shape.tiles(minZoom: kHeightTileZoom, maxZoom: kHeightTileZoom);
    expect(plan.heightTiles.toSet(), z13.toSet(), reason: 'eine Höhenkachel je z13-Kachel der Form');
    expect(plan.hasHeights, isTrue);
    var expected = 0;
    for (final t in plan.heightTiles) {
      expected += (await heights.lookup(tileIdOf(t)))!.length;
    }
    expect(plan.heightBytes, expected);
    expect(plan.totalBytes, plan.bytes + plan.heightBytes, reason: 'ohne Orte gemessen');

    final progress = <AreaProgress>[];
    final area = await downloader.download(plan, name: 'Mit Höhen', onProgress: progress.add);
    expect(progress.map((p) => p.phase), contains(AreaPhase.heights));
    expect(area.heightTiles, z13.length);
    expect(area.heightsBuild, '20261001');
    final stored = await store.readHeights(area.id);
    expect(stored, isNotNull);
    expect(area.heightBytes, stored!.length);
    // Gelesen wie die Routenplanung es tun wird: Höhe aus dem Bereich.
    final reader = HeightReader([ArchiveHeightSource(await PmTilesArchive.fromBytes(stored))]);
    addTearDown(reader.close);
    final origin = tileAt(47.0, 10.0, kHeightTileZoom);
    final probe = tileAt(_bounds.south, _bounds.west, kHeightTileZoom);
    final h = await reader.heightAt(const LatLng(_boundsSouth, _boundsWest));
    expect(h, isNotNull);
    expect(h, closeTo(1000 + (probe.x - origin.x) * 10, 7));
    // Der Index-Rundlauf trägt die Höhen.
    final back = StoredArea.fromJson(area.toJson());
    expect(back.hasHeights, isTrue);
    expect(back.heightTiles, area.heightTiles);
  });

  test('ohne Höhenarchiv: kein Höhenplan, kein zweites Archiv, der Index sagt 0', () async {
    final downloader = make();
    final plan = await downloader.plan(const RectShape(_bounds));
    expect(plan.hasHeights, isFalse);
    expect(plan.heightBytes, 0);
    final area = await downloader.download(plan, name: 'Ohne Höhen');
    expect(area.hasHeights, isFalse);
    expect(await store.readHeights(area.id), isNull);
    expect(store.heights, isEmpty);
  });

  test('derselbe Bereich unter derselben Id ohne Höhen neu geholt verliert sein Höhenarchiv', () async {
    final heights = await _heightsSource();
    addTearDown(heights.close);
    final withH = make(heights: heights);
    await withH.download(await withH.plan(const RectShape(_bounds)), name: 'A', id: 'x');
    expect(await store.readHeights('x'), isNotNull);
    final without = make();
    await without.download(await without.plan(const RectShape(_bounds)), name: 'A', id: 'x');
    expect(await store.readHeights('x'), isNull);
    expect((await store.list()).single.hasHeights, isFalse);
  });

  test('mit Wege-Archiv (#212): nur die z13-Kacheln, die der Host hat, als drittes Archiv', () async {
    final ways = await _waysSource();
    addTearDown(ways.close);
    final downloader = make(ways: ways);
    const shape = RectShape(_bounds);
    final plan = await downloader.plan(shape);
    final z13 = shape.tiles(minZoom: kWaysZoom, maxZoom: kWaysZoom);
    expect(plan.wayTiles.toSet(), {for (final t in z13) if (t.x.isEven) t},
        reason: 'Kacheln ohne getaggte Wege fehlen im Host-Archiv und im Plan');
    expect(plan.wayTiles.length, lessThan(z13.length));
    expect(plan.hasWays, isTrue);
    expect(plan.waysBuild, '20261007');
    var expected = 0;
    for (final t in plan.wayTiles) {
      expected += (await ways.lookup(tileIdOf(t)))!.length;
    }
    expect(plan.wayBytes, expected);
    expect(plan.totalBytes, plan.bytes + plan.wayBytes, reason: 'ohne Orte und Höhen gemessen');

    final progress = <AreaProgress>[];
    final area = await downloader.download(plan, name: 'Mit Wegen', onProgress: progress.add);
    expect(progress.map((p) => p.phase), contains(AreaPhase.ways));
    expect(area.wayTiles, plan.wayTiles.length);
    expect(area.waysBuild, '20261007');
    final stored = await store.readWays(area.id);
    expect(stored, isNotNull);
    expect(area.wayBytes, stored!.length);
    expect(area.totalBytes, area.bytes + area.wayBytes);
    // Die Kachel kommt Byte für Byte, wie der Host sie hatte.
    final back = await PmTilesArchive.fromBytes(stored);
    addTearDown(back.close);
    final probe = plan.wayTiles.first;
    expect(utf8.decode((await back.tile(tileIdOf(probe))).compressedBytes()), 'w${probe.x}/${probe.y}');
    final json = StoredArea.fromJson(area.toJson());
    expect(json.wayTiles, area.wayTiles);
    expect(json.wayBytes, area.wayBytes);
    expect(json.waysBuild, '20261007');
  });

  test('Wege-Archiv ohne Kachel im Bereich: kein drittes Archiv, aber der Bau gilt als geholt', () async {
    final ways = await _waysSource(only: const {});
    addTearDown(ways.close);
    final downloader = make(ways: ways);
    final plan = await downloader.plan(const RectShape(_bounds));
    expect(plan.hasWays, isFalse);
    final area = await downloader.download(plan, name: 'Leer');
    expect(area.hasWays, isFalse);
    expect(area.waysBuild, '20261007', reason: 'sonst böte „Meine Bereiche" ewig „Wege verfügbar" an');
    expect(store.ways, isEmpty);
  });

  test('ohne Wege-Archiv: kein Bau, und ein neu geholter Bereich verliert seine alten Wege', () async {
    final ways = await _waysSource();
    addTearDown(ways.close);
    final withW = make(ways: ways);
    await withW.download(await withW.plan(const RectShape(_bounds)), name: 'A', id: 'x');
    expect(await store.readWays('x'), isNotNull);
    final without = make();
    final area = await without.download(await without.plan(const RectShape(_bounds)), name: 'A', id: 'x');
    expect(area.waysBuild, isNull);
    expect(await store.readWays('x'), isNull);
    expect((await store.list()).single.hasWays, isFalse);
  });

  test('ein zweiter Bereich mit derselben Id ersetzt den ersten im Index', () async {
    final downloader = make();
    final plan = await downloader.plan(const RectShape(_bounds));
    await downloader.download(plan, name: 'A', id: 'x');
    await downloader.download(plan, name: 'B', id: 'x');
    final areas = await store.list();
    expect(areas.map((a) => a.name), ['B']);
  });

  test('Abbruch: nichts geschrieben, nichts im Index', () async {
    final downloader = make();
    final plan = await downloader.plan(const RectShape(_bounds));
    var calls = 0;
    await expectLater(
        downloader.download(plan, name: 'Abbruch', isCancelled: () => ++calls > 1),
        throwsA(isA<AreaCancelled>()));
    expect(store.archives, isEmpty);
    expect(await store.list(), isEmpty);
  });
}
