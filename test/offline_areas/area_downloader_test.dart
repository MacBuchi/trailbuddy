// Der Download eines Bereichs (Konzept 3.2, seit 0.106.0 Abschnitt 8),
// gegen ein Quellarchiv aus dem eigenen Schreiber: Der Plan zählt und
// misst — nur, was im Kachelspeicher fehlt —, der Download holt über den
// `tiles()`-Strom und legt Block für Block in den Speicher (#229), nimmt
// die Orte-Zellen mit, meldet Fortschritt, und ein Abbruch lässt einen
// unvollständigen Bereich zurück, den „Fortsetzen" zu Ende holt.
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
import 'package:trailbuddy/features/offline_areas/tile_store.dart';
import 'package:trailbuddy/features/offline_areas/tile_store_sources.dart';

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
  late MemoryTileStore tiles;
  late List<String> poiAsked;

  setUp(() async {
    source = await _source();
    store = MemoryAreaStore();
    tiles = MemoryTileStore();
    poiAsked = [];
  });

  AreaDownloader make(
          {PoiManifest? poiManifest,
          PmTilesArchive? heights,
          PmTilesArchive? ways,
          MapManifest manifest = _manifest,
          TileStore? into}) =>
      AreaDownloader(
        archive: source,
        manifest: manifest,
        store: store,
        tiles: into ?? tiles,
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
    expect(plan.map.covered, plan.tiles.length, reason: 'leerer Speicher: alles fehlt');
    expect(plan.map.coveredBytes, expected);
    expect(plan.hasMap, isTrue);
    // Außerhalb der Quelle: keine Kachel, keine Bytes — kein Fehler.
    final sea = await make().plan(const RectShape(AreaBounds(south: 30, west: -30, north: 30.1, east: -29.9)));
    expect(sea.tiles, isEmpty);
    expect(sea.bytes, 0);
    expect(sea.hasMap, isFalse);
  });

  test('eine Kachelmenge holt genau ihre Kacheln und nur die Orte-Zellen der Kacheln', () async {
    // Zwei Trails weit auseinander: Der Speicher trägt zwei Streifen, die
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
    expect((await tiles.index('dach', TileLayer.map)).length, plan.tiles.length);
    // Der Index-Rundlauf behält die Form — „Aktualisieren" braucht sie.
    final back = StoredArea.fromJson(area.toJson());
    expect((back.shape as TileSetShape).keys, shape.keys);
    expect(back.bounds.west, closeTo(hull.west, 1e-9));
  });

  test('zu groß wird abgelehnt, bevor eine Kachel nachgeschlagen ist', () async {
    const dach = AreaBounds(south: 45.5, west: 5.5, north: 55.5, east: 17.5);
    final downloader = make(
        manifest: const MapManifest(file: 'dach-20260928.pmtiles', maxZoom: 13, bytes: 1, sourceBuild: '20260928'));
    expect(() => downloader.plan(const RectShape(dach)), throwsA(isA<AreaTooLarge>()));
  });

  test('der Download legt jede Kachel in den Speicher, dazu Orte-Zellen und Index', () async {
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
    expect(area.format, kStoredAreaFormat);
    expect(area.complete, isTrue);
    // Der Bereich nennt alle Zellen der Form, die das Manifest kennt; die
    // 404 (Einkehr) kommt nicht auf das Gerät.
    expect(area.poiFiles, [
      for (final c in cells) poiCellFileName(c, PoiGroup.water),
      poiCellFileName(cells.first, PoiGroup.food),
    ]..sort());
    expect(poiAsked, hasLength(cells.length + 1));
    expect(await store.readPoiFile(poiCellFileName(cells.first, PoiGroup.water)), contains('"pois"'));
    expect(await store.readPoiFile(poiCellFileName(cells.first, PoiGroup.food)), isNull);

    // Der Speicher: jede geplante Kachel, Byte für Byte wie die Quelle,
    // mit dem Bau des Hosts.
    final index = await tiles.index('dach', TileLayer.map);
    expect(index.length, plan.tiles.length);
    for (final t in plan.tiles) {
      final id = tileIdOf(t);
      expect(await tiles.read('dach', TileLayer.map, t.z, t.x, t.y), (await source.tile(id)).compressedBytes());
      expect(index[id]!.build, '20260928');
    }
    expect(area.bytes, plan.bytes);
    expect((await store.list()).single.id, area.id);
    expect(store.archives, isEmpty, reason: 'kein Archiv je Bereich mehr');
    // In Blöcken (chunkSize 7), nicht auf einmal.
    expect(tiles.puts, (plan.tiles.length / 7).ceil());

    // Der Fortschritt: Kacheln, dann Orte, monoton.
    expect(progress.first.phase, AreaPhase.tiles);
    expect(progress.where((p) => p.phase == AreaPhase.tiles).last.done, plan.tiles.length);
    expect(progress.any((p) => p.phase == AreaPhase.pois), isTrue);
  });

  test('ein zweiter Bereich über derselben Gegend lädt nur, was fehlt (#229)', () async {
    final downloader = make();
    const inner = RectShape(_bounds);
    const outer = RectShape(AreaBounds(south: 47.85, west: 11.5, north: 48.0, east: 11.8));
    final first = await downloader.plan(inner);
    await downloader.download(first, name: 'Innen');
    final second = await downloader.plan(outer);
    final all = outer.tiles(maxZoom: 10).toSet();
    final have = inner.tiles(maxZoom: 10).toSet();
    expect(second.map.covered, all.length);
    expect(second.tiles.toSet(), all.difference(have), reason: 'liegende Kacheln kommen nicht noch einmal');
    expect(second.map.stored, have.length);
    final puts = tiles.puts;
    final area = await downloader.download(second, name: 'Außen');
    expect(tiles.puts - puts, (second.tiles.length / 7).ceil());
    expect(area.tiles, all.length, reason: 'der Bereich deckt alles, auch das Geteilte');
    expect((await tiles.index('dach', TileLayer.map)).length, all.length, reason: 'jede Kachel einmal');
    // Liegt schon alles: nichts zu laden, aber ein Verweis.
    final again = await downloader.plan(inner);
    expect(again.tiles, isEmpty);
    expect(again.nothingToFetch, isTrue);
    expect(again.hasMap, isTrue);
  });

  test('Aktualisieren holt die Kacheln älterer Bauten neu, je Kachel', () async {
    final downloader = make();
    const shape = RectShape(_bounds);
    await downloader.download(await downloader.plan(shape), name: 'A', id: 'x');
    const newer = MapManifest(file: 'dach-20261101.pmtiles', maxZoom: 10, bytes: 1, sourceBuild: '20261101');
    final fresh = make(manifest: newer);
    expect((await fresh.plan(shape)).tiles, isEmpty, reason: 'ohne Aktualisieren fehlt nichts');
    final plan = await fresh.plan(shape, refresh: true);
    expect(plan.tiles.length, plan.map.covered, reason: 'jede liegende Kachel ist älter');
    final area = await fresh.download(plan, name: 'A', id: 'x');
    expect(area.build, '20261101');
    expect({for (final i in (await tiles.index('dach', TileLayer.map)).values) i.build}, {'20261101'});
    expect((await fresh.plan(shape, refresh: true)).tiles, isEmpty, reason: 'jetzt ist keine älter');
  });

  const newer = MapManifest(file: 'dach-20261101.pmtiles', maxZoom: 10, bytes: 1, sourceBuild: '20261101');

  test('Aktualisieren je Region (#229 Schritt 4): jede veraltete Kachel einmal, danach tragen alle Bereiche den Bau',
      () async {
    final downloader = make();
    const inner = RectShape(_bounds);
    const outer = RectShape(AreaBounds(south: 47.85, west: 11.5, north: 48.0, east: 11.8));
    await downloader.download(await downloader.plan(inner), name: 'Innen', id: 'i');
    await downloader.download(await downloader.plan(outer), name: 'Außen', id: 'o');
    final union = {...inner.tiles(maxZoom: 10), ...outer.tiles(maxZoom: 10)};
    final fresh = make(manifest: newer);
    final plan = await fresh.planRefresh(await store.list());
    expect(plan.map.covered, union.length, reason: 'die Vereinigung, nicht die Summe der Bereiche');
    expect(plan.map.fetch.toSet(), union);
    expect(plan.map.fetchBytes, greaterThan(0), reason: 'gemessen am Verzeichnis des neuen Baus');
    expect(plan.staleTiles, union.length);
    final puts = tiles.puts;
    final updated = await fresh.refreshRegion(plan);
    expect(tiles.puts - puts, (union.length / 7).ceil(), reason: 'jede Kachel einmal geholt');
    expect({for (final i in (await tiles.index('dach', TileLayer.map)).values) i.build}, {'20261101'});
    expect({for (final a in updated) a.build}, {'20261101'});
    expect({for (final a in await store.list()) a.build}, {'20261101'});
    expect((await fresh.planRefresh(await store.list())).isEmpty, isTrue, reason: 'jetzt ist keine älter');
  });

  test('ein abgebrochenes Aktualisieren lässt das Geholte liegen, die Bereiche behalten ihren Bau', () async {
    final downloader = make();
    const shape = RectShape(AreaBounds(south: 47.5, west: 11.0, north: 48.2, east: 12.0));
    await downloader.download(await downloader.plan(shape), name: 'Groß', id: 'g');
    final fresh = make(manifest: newer);
    final plan = await fresh.planRefresh(await store.list());
    expect(plan.map.fetch.length, greaterThan(14));
    var calls = 0;
    await expectLater(fresh.refreshRegion(plan, isCancelled: () => ++calls > 2), throwsA(isA<AreaCancelled>()));
    final builds = [for (final i in (await tiles.index('dach', TileLayer.map)).values) i.build];
    expect(builds.where((b) => b == '20261101').length, 14, reason: 'zwei Blöcke à 7 sind neu');
    expect((await store.list()).single.build, '20260928', reason: 'erst wenn alles da ist, gilt der neue Bau');
    final rest = await fresh.planRefresh(await store.list());
    expect(rest.map.covered, plan.map.covered - 14, reason: 'nur noch der Rest ist veraltet');
  });

  test('eine veraltete Kachel, die der neue Bau nicht mehr hat, geht beim Aktualisieren', () async {
    // Wege-Kacheln eines älteren Baus; der neue (20261007) hat nur jede zweite Spalte.
    final shape = const RectShape(_bounds);
    final z13 = shape.tiles(minZoom: kWaysZoom, maxZoom: kWaysZoom);
    await tiles.put('dach', TileLayer.ways, [for (final t in z13) StoreTile(t.z, t.x, t.y, Uint8List(3), '20261001')]);
    await store.saveIndex([
      StoredArea(
        id: 'w',
        name: 'Wege',
        bounds: _bounds,
        shape: shape,
        minZoom: 8,
        maxZoom: 10,
        build: '20260928',
        tiles: 0,
        bytes: 0,
        savedAt: DateTime.utc(2026, 9, 28),
        waysBuild: '20261001',
        format: kStoredAreaFormat,
        complete: true,
      ),
    ]);
    final downloader = make(ways: await _waysSource());
    final plan = await downloader.planRefresh(await store.list());
    final kept = {for (final t in z13) if (t.x.isEven) t};
    expect(plan.ways.covered, z13.length);
    expect(plan.ways.fetch.toSet(), kept);
    expect(plan.drop[TileLayer.ways]?.length, z13.length - kept.length);
    final updated = await downloader.refreshRegion(plan);
    final index = await tiles.index('dach', TileLayer.ways);
    expect(index.length, kept.length, reason: 'was der Host nicht mehr hat, bleibt nicht für immer alt liegen');
    expect({for (final i in index.values) i.build}, {'20261007'});
    expect(updated.single.waysBuild, '20261007');
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
      tiles: tiles,
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
    // Eine liegende Orte-Datei kommt beim nächsten Bereich nicht noch einmal.
    final next = await downloader.plan(const RectShape(_bounds), withPois: true);
    expect(next.poiFiles, isEmpty);
    expect(next.poiNames, area.poiFiles);
    expect(poiAsked, hasLength(1));
    // Ohne Orte gemessen: keine Zahl.
    expect((await make().plan(const RectShape(_bounds))).poiCount, isNull);
  });

  test('mit Höhenarchiv: der Plan zählt die Höhenkacheln der z13-Form, der Download legt sie in ihre Ebene', () async {
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
    expect(area.heightBytes, expected);
    expect((await tiles.index('dach', TileLayer.heights)).length, z13.length);
    // Gelesen wie die Routenplanung: Höhe aus dem Speicher der Region.
    final reader = HeightReader([StoreHeightSource(tiles, 'dach')]);
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

  test('ohne Höhenarchiv: kein Höhenplan, nichts in der Ebene, der Index sagt 0', () async {
    final downloader = make();
    final plan = await downloader.plan(const RectShape(_bounds));
    expect(plan.hasHeights, isFalse);
    expect(plan.heightBytes, 0);
    final area = await downloader.download(plan, name: 'Ohne Höhen');
    expect(area.hasHeights, isFalse);
    expect(await tiles.index('dach', TileLayer.heights), isEmpty);
  });

  test('mit Wege-Archiv (#212): nur die z13-Kacheln, die der Host hat, in ihre Ebene', () async {
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
    expect(area.wayBytes, expected);
    expect(area.totalBytes, area.bytes + area.wayBytes);
    // Die Kachel kommt Byte für Byte, wie der Host sie hatte.
    final probe = plan.wayTiles.first;
    final stored = await tiles.read('dach', TileLayer.ways, probe.z, probe.x, probe.y);
    expect(utf8.decode(unpackStoredTile(stored!)), 'w${probe.x}/${probe.y}');
    expect((await tiles.index('dach', TileLayer.ways))[tileIdOf(probe)]!.build, '20261007');
    final json = StoredArea.fromJson(area.toJson());
    expect(json.wayTiles, area.wayTiles);
    expect(json.wayBytes, area.wayBytes);
    expect(json.waysBuild, '20261007');
  });

  test('Wege-Archiv ohne Kachel im Bereich: nichts in der Ebene, aber der Bau gilt als geholt', () async {
    final ways = await _waysSource(only: const {});
    addTearDown(ways.close);
    final downloader = make(ways: ways);
    final plan = await downloader.plan(const RectShape(_bounds));
    expect(plan.hasWays, isFalse);
    final area = await downloader.download(plan, name: 'Leer');
    expect(area.hasWays, isFalse);
    expect(area.waysBuild, '20261007', reason: 'sonst böte „Meine Bereiche" ewig „Wege verfügbar" an');
    expect(await tiles.index('dach', TileLayer.ways), isEmpty);
  });

  test('ein zweiter Bereich mit derselben Id ersetzt den ersten im Index', () async {
    final downloader = make();
    final plan = await downloader.plan(const RectShape(_bounds));
    await downloader.download(plan, name: 'A', id: 'x');
    await downloader.download(plan, name: 'B', id: 'x');
    final areas = await store.list();
    expect(areas.map((a) => a.name), ['B']);
  });

  test('Abbruch: der Bereich bleibt unvollständig mit dem, was liegt; Fortsetzen holt nur den Rest', () async {
    final downloader = make();
    final plan = await downloader.plan(const RectShape(AreaBounds(south: 47.5, west: 11.0, north: 48.2, east: 12.0)));
    expect(plan.tiles.length, greaterThan(14), reason: 'mindestens drei Blöcke');
    var calls = 0;
    await expectLater(
        downloader.download(plan, name: 'Abbruch', id: 'p', isCancelled: () => ++calls > 2),
        throwsA(isA<AreaCancelled>()));
    final pending = (await store.list()).single;
    expect(pending.id, 'p');
    expect(pending.complete, isFalse, reason: 'der Verweis entsteht VOR dem Download');
    expect(pending.format, kStoredAreaFormat);
    final kept = (await tiles.index('dach', TileLayer.map)).length;
    expect(kept, 14, reason: 'zwei Blöcke à 7 sind geschrieben und bleiben');
    // Fortsetzen: derselbe Plan noch einmal holt nur, was fehlt.
    final rest = await downloader.plan(pending.shape);
    expect(rest.tiles.length, plan.tiles.length - kept);
    final done = await downloader.download(rest, name: 'Abbruch', id: 'p');
    expect(done.complete, isTrue);
    expect(done.tiles, plan.tiles.length, reason: 'gedeckt ist alles, auch das vor dem Abbruch');
    expect((await tiles.index('dach', TileLayer.map)).length, plan.tiles.length);
  });

  test('eine Kachel, die anders aus dem Speicher kommt, bricht den Download ab', () async {
    final broken = _BrokenTileStore();
    final downloader = make(into: broken);
    final plan = await downloader.plan(const RectShape(_bounds));
    await expectLater(downloader.download(plan, name: 'Kaputt'), throwsA(isA<AreaVerifyFailed>()));
    expect((await store.list()).single.complete, isFalse);
  });
}

/// Ein Speicher, der beim Lesen ein Byte kippt.
class _BrokenTileStore extends MemoryTileStore {
  @override
  Future<Uint8List?> read(String region, TileLayer layer, int z, int x, int y) async {
    final bytes = await super.read(region, layer, z, x, y);
    if (bytes == null) return null;
    return Uint8List.fromList([...bytes]..[0] ^= 1);
  }
}
