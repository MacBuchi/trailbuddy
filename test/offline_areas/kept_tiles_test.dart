// „Unterwegs geladen" (#478): Was der Planer online ergänzt, bleibt im
// Kachelspeicher der Region, gehalten von einem unsichtbaren Bereich —
// verdrängt nach letzter Nutzung, nie im Ganzen aktualisiert, nie als
// Waise eines gelöschten Bereichs mitgenommen.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/kept_tiles.dart';
import 'package:trailbuddy/features/offline_areas/tile_refs.dart';
import 'package:trailbuddy/features/offline_areas/tile_store.dart';

void main() {
  // Ausgedachte Kacheln, keine echte Gegend.
  const x0 = 4300, y0 = 2800;
  int key(int dx) => TileSetShape.keyOf(x0 + dx, y0, kAreaShapeZoom);
  int id(int dx) => tileIdOf((z: kAreaShapeZoom, x: x0 + dx, y: y0));
  KeptFetch fetch(int dx, {int size = 100, bool heights = true}) => KeptFetch(x0 + dx, y0,
      map: Uint8List(size), heights: heights ? Uint8List(10) : null, ways: Uint8List(5));
  const builds = (map: '20261101', heights: '20261001', ways: '20261015');

  late MemoryAreaStore areas;
  late MemoryTileStore tiles;
  setUp(() {
    areas = MemoryAreaStore();
    tiles = MemoryTileStore();
  });

  StoredArea area(Set<int> keys, {String id = 'a'}) => StoredArea(
        id: id,
        name: 'Hausrunde',
        bounds: TileSetShape(zoom: kAreaShapeZoom, keys: keys).hull,
        shape: TileSetShape(zoom: kAreaShapeZoom, keys: keys),
        minZoom: 8,
        maxZoom: 14,
        build: '20261001',
        tiles: keys.length,
        bytes: 0,
        savedAt: DateTime.utc(2026, 10, 1),
        format: kStoredAreaFormat,
      );

  test('das Geholte liegt mit seinem Bau in allen drei Ebenen, gehalten von einem unsichtbaren Bereich', () async {
    final r = await keepOnlineTiles(
        areas: areas, tiles: tiles, region: 'dach', builds: builds, fetched: [fetch(0), fetch(1, heights: false)]);
    expect(r.relist, isTrue, reason: 'neu in der Region: Karte und Höhen lesen die Liste neu');
    expect((await tiles.index('dach', TileLayer.map))[id(0)]!.build, '20261101');
    expect((await tiles.index('dach', TileLayer.heights)).keys, [id(0)]);
    expect((await tiles.index('dach', TileLayer.ways))[id(1)]!.build, '20261015');

    final holder = (await areas.list()).single;
    expect(holder.kept, isTrue);
    expect(holder.id, keptAreaId('dach'));
    expect(visibleAreas([holder]), isEmpty, reason: 'kein Bereich, den man sieht');
    expect(holder.minZoom, kAreaShapeZoom);
    expect(holder.maxZoom, kAreaShapeZoom, reason: 'nur Routing-Kacheln, nie andere Zoomstufen');
    expect(holder.complete, isTrue);
    expect(holder.hasHeights && holder.hasWays, isTrue);
    expect(holder.keptUse, {key(0): 115, key(1): 105});
    expect(holder.bytes, 220);

    final again = await keepOnlineTiles(
        areas: areas, tiles: tiles, region: 'dach', builds: builds, fetched: [fetch(2)]);
    expect(again.relist, isFalse, reason: 'ein Halter mit Höhen und Wegen: kein neuer Stil');
  });

  test('die Nutzungsreihenfolge übersteht den Index', () async {
    await keepOnlineTiles(areas: areas, tiles: tiles, region: 'dach', builds: builds, fetched: [fetch(0), fetch(1)]);
    await keepOnlineTiles(areas: areas, tiles: tiles, region: 'dach', builds: builds, used: [key(0)]);
    final holder = (await areas.list()).single;
    expect(holder.keptUse.keys, [key(1), key(0)], reason: 'gebraucht wandert ans Ende');
    final read = StoredArea.fromJson(holder.toJson());
    expect(read.keptUse.keys, [key(1), key(0)]);
    expect(read.kept, isTrue);
  });

  test('verdrängt wird nach letzter Nutzung, nicht nach Ladezeit — eine Kachel eines Bereichs bleibt liegen', () async {
    Future<void> keep(List<KeptFetch> f, [List<int> used = const []]) =>
        keepOnlineTiles(areas: areas, tiles: tiles, region: 'dach', builds: builds, fetched: f, used: used, maxBytes: 350);
    await keep([fetch(0)]);
    await keep([fetch(1)]);
    await keep([fetch(2)]);
    // Die älteste (0) wurde eben gebraucht; die nächste ist 1.
    await keep([], [key(0)]);
    await keep([fetch(3)]);
    var holder = (await areas.list()).single;
    expect(holder.keptUse.keys, [key(2), key(0), key(3)]);
    expect(holder.bytes, lessThanOrEqualTo(350));
    final map = await tiles.index('dach', TileLayer.map);
    expect(map.containsKey(id(1)), isFalse, reason: 'verdrängt: aus allen Ebenen');
    expect((await tiles.index('dach', TileLayer.ways)).containsKey(id(1)), isFalse);
    expect(map.containsKey(id(0)), isTrue);

    // Deckt ein Bereich die nächste, die fällt, bleibt ihre Kachel liegen.
    await areas.saveIndex([...await areas.list(), area({key(2)})]);
    await keep([fetch(4)]);
    holder = (await areas.list()).firstWhere((a) => a.kept);
    expect(holder.keptUse.containsKey(key(2)), isFalse);
    expect((await tiles.index('dach', TileLayer.map)).containsKey(id(2)), isTrue, reason: 'Bereiche werden nie verdrängt');
  });

  test('eine Planung verdrängt nie, was sie selbst braucht', () async {
    await keepOnlineTiles(
        areas: areas, tiles: tiles, region: 'dach', builds: builds, fetched: [fetch(0), fetch(1)], maxBytes: 100);
    expect((await areas.list()).single.keptUse.length, 2);
  });

  test('ein gelöschter Bereich nimmt die behaltenen Kacheln nicht als Waisen mit', () async {
    await keepOnlineTiles(areas: areas, tiles: tiles, region: 'dach', builds: builds, fetched: [fetch(0)]);
    final a = area({key(0), key(1)});
    await tiles.put('dach', TileLayer.map, [StoreTile(13, x0 + 1, y0, Uint8List(3), '20261001')]);
    final remaining = [for (final x in await areas.list()) x];
    final orphans = await orphansAfter(store: tiles, remaining: remaining, regions: {'dach'}, gone: [a]);
    final ids = [for (final o in orphans.tiles) ...o.ids];
    expect(ids, contains(id(1)));
    expect(ids, isNot(contains(id(0))), reason: 'der Halter hält sie');
  });

  test('veraltet ist nur, was der Halter allein hält und älter ist als der Host', () async {
    await keepOnlineTiles(areas: areas, tiles: tiles, region: 'dach', builds: builds, fetched: [fetch(0), fetch(1), fetch(2)]);
    await tiles.put('dach', TileLayer.map, [StoreTile(13, x0 + 2, y0, Uint8List(3), '20261201')]);
    await areas.saveIndex([...await areas.list(), area({key(1)})]);
    final frame = [for (var dx = 0; dx < 4; dx++) (z: 13, x: x0 + dx, y: y0)];
    final stale = await staleKeptTiles(
        tiles: tiles, areas: await areas.list(), region: 'dach', frame: frame, mapBuild: '20261201', max: 10);
    expect(stale, [(z: 13, x: x0, y: y0)],
        reason: '1 deckt ein Bereich (das holt „Aktualisieren"), 2 ist neu, 3 liegt nicht');
    expect(
        await staleKeptTiles(
            tiles: tiles, areas: await areas.list(), region: 'dach', frame: frame, mapBuild: '20261201', max: 0),
        isEmpty);
    expect(
        await staleKeptTiles(
            tiles: tiles, areas: await areas.list(), region: 'dach', frame: frame, mapBuild: '20261101', max: 10),
        isEmpty,
        reason: 'gleicher Bau: nichts zu holen');
  });
}
