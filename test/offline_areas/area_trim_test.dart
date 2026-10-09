// Kacheln aus gespeicherten Bereichen herausnehmen (0.27.0, seit 0.106.0
// über den Kachelspeicher, #229): Der Plan misst lokal, was frei wird —
// nur, was danach keine Form mehr deckt; das Ausführen verkleinert die
// Formen und nimmt genau diese Kacheln aus dem Speicher, behält gröbere
// Kacheln, solange darunter etwas liegt, und Kacheln, die ein anderer
// Bereich auch braucht; streicht Orte-Dateien leerer Zellen — und ein
// Bereich, der leer wird, verschwindet ganz.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/map/poi.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/area_trim.dart';
import 'package:trailbuddy/features/offline_areas/tile_store.dart';

const _z = kAreaShapeZoom;

void main() {
  late MemoryAreaStore store;
  late MemoryTileStore tiles;

  final origin = tileAt(47.9, 11.6, _z);
  final x = origin.x, y = origin.y;
  int k(int dx) => TileSetShape.keyOf(x + dx, y, _z);
  TileSetShape row(Iterable<int> dxs) => TileSetShape(zoom: _z, keys: {for (final d in dxs) k(d)});

  /// Ein Bereich als Verweis, seine Kacheln im Speicher (Zoom 8–13, je
  /// Kachel 10 Bytes), auf Wunsch mit Höhen und Wegen.
  Future<StoredArea> seed(
      {String id = 'a',
      TileSetShape? s,
      List<String> poiFiles = const [],
      bool heights = false,
      Set<int> wayColumns = const {}}) async {
    final sh = s ?? row([0, 1, 2, 3]);
    final mapTiles = sh.tiles(maxZoom: _z);
    await tiles.put('dach', TileLayer.map, [
      for (final t in mapTiles) StoreTile(t.z, t.x, t.y, Uint8List(10), '20260928'),
    ]);
    final z13 = sh.tiles(minZoom: _z, maxZoom: _z);
    if (heights) {
      await tiles.put('dach', TileLayer.heights, [
        for (final t in z13) StoreTile(t.z, t.x, t.y, Uint8List(100), '20261001'),
      ]);
    }
    final ways = [for (final t in z13) if (wayColumns.contains(t.x - x)) t];
    await tiles.put('dach', TileLayer.ways, [
      for (final t in ways) StoreTile(t.z, t.x, t.y, Uint8List(7), '20261007'),
    ]);
    for (final f in poiFiles) {
      await store.putPoiFile(f, '{"pois":[]}');
    }
    final area = StoredArea(
      id: id,
      name: 'Bereich $id',
      bounds: sh.hull,
      shape: sh,
      minZoom: 8,
      maxZoom: _z,
      build: '20260928',
      tiles: mapTiles.length,
      bytes: mapTiles.length * 10,
      savedAt: DateTime.utc(2026, 9, 28),
      poiFiles: poiFiles,
      heightTiles: heights ? z13.length : 0,
      heightBytes: heights ? z13.length * 100 : 0,
      heightsBuild: heights ? '20261001' : null,
      wayTiles: ways.length,
      wayBytes: ways.length * 7,
      waysBuild: wayColumns.isEmpty ? null : '20261007',
      format: kStoredAreaFormat,
    );
    await store.saveIndex([...await store.list(), area]);
    return area;
  }

  Future<Set<int>> ids(TileLayer layer) async => (await tiles.index('dach', layer)).keys.toSet();
  int id(int z, int dx) => tileIdOf((z: z, x: (x + dx) >> (_z - z), y: y >> (_z - z)));

  setUp(() {
    store = MemoryAreaStore();
    tiles = MemoryTileStore();
  });

  test('zwei Kacheln raus: gemessen aus dem Index, aus dem Speicher genommen, die Form schrumpft', () async {
    final area = await seed();
    final trimmer = AreaTrimmer(store, tiles);
    final plan = await trimmer.plan([area], {k(2), k(3)});
    expect(plan.trims, hasLength(1));
    // Zwei 13er-Kacheln; ihr 12er-Elternteil nur, wenn keine Geschwister
    // mehr darunter liegen.
    expect(plan.freedTiles, greaterThanOrEqualTo(2));
    expect(plan.freedBytes, plan.freedTiles * 10);

    final before = await ids(TileLayer.map);
    await trimmer.apply(plan);
    final after = (await store.list()).single;
    final newShape = after.shape as TileSetShape;
    expect(newShape.keys, {k(0), k(1)});
    final left = await ids(TileLayer.map);
    expect(left, {for (final t in newShape.tiles(maxZoom: _z)) tileIdOf(t)},
        reason: 'die verbliebenen samt ihrer gröberen Eltern bis Zoom 8');
    expect(before.length - left.length, plan.freedTiles);
    expect(left.contains(id(_z, 3)), isFalse);
  });

  test('eine Kachel, die ein anderer Bereich auch deckt, bleibt liegen (#229)', () async {
    final a = await seed(id: 'a', s: row([0, 1]));
    await seed(id: 'b', s: row([1, 2]));
    final trimmer = AreaTrimmer(store, tiles);
    // x+1 aus beiden wäre der Radierer über beiden; hier nur x aus A.
    final plan = await trimmer.plan(await store.list(), {k(0)});
    expect(plan.trims.single.area.id, a.id);
    await trimmer.apply(plan);
    final left = await ids(TileLayer.map);
    expect(left.contains(id(_z, 0)), isFalse);
    expect(left.contains(id(_z, 1)), isTrue, reason: 'gehört auch B');
    expect(left.contains(id(_z, 2)), isTrue);
  });

  test('die Höhen folgen den Kacheln: zwei raus heißt zwei Höhenkacheln raus, alle raus heißt keine', () async {
    final area = await seed(heights: true);
    final trimmer = AreaTrimmer(store, tiles);
    final plan = await trimmer.plan([area], {k(2), k(3)});
    expect(plan.freedBytes, plan.freedTiles * 10 + 2 * 100, reason: 'die Höhenbytes zählen mit');
    await trimmer.apply(plan);
    expect(await ids(TileLayer.heights), {id(_z, 0), id(_z, 1)});
    // Alles raus: Bereich weg, Höhen weg.
    final all = await trimmer.plan(await store.list(), {k(0), k(1)});
    expect(all.trims.single.shape, isNull);
    await trimmer.apply(all);
    expect(await ids(TileLayer.heights), isEmpty);
    expect(await ids(TileLayer.map), isEmpty);
    expect(await store.list(), isEmpty);
  });

  test('die Wege folgen den Kacheln (#212); bleibt keine, bleibt der Bau', () async {
    final area = await seed(wayColumns: {0, 2});
    final trimmer = AreaTrimmer(store, tiles);
    final plan = await trimmer.plan([area], {k(2), k(3)});
    expect(plan.freedBytes, plan.freedTiles * 10 + 7, reason: 'eine Wege-Kachel zählt mit');
    await trimmer.apply(plan);
    expect(await ids(TileLayer.ways), {id(_z, 0)});
    final after = (await store.list()).single;
    await trimmer.apply(await trimmer.plan([after], {k(0)}));
    final rest = (await store.list()).single;
    expect(await ids(TileLayer.ways), isEmpty);
    expect(rest.waysBuild, '20261007', reason: 'geholt ist geholt — kein Angebot zum Nachladen');
  });

  test('eine Kachel, die keine Form hat, fasst der Plan nicht an', () async {
    final area = await seed();
    final plan = await AreaTrimmer(store, tiles).plan([area], {k(20)});
    expect(plan.isEmpty, isTrue);
  });

  test('alles raus: der Bereich verschwindet samt Kacheln, der andere bleibt', () async {
    await seed();
    await seed(id: 'b', s: row([40]));
    final trimmer = AreaTrimmer(store, tiles);
    final plan = await trimmer.plan(await store.list(), {k(0), k(1), k(2), k(3)});
    expect(plan.trims.single.shape, isNull);
    await trimmer.apply(plan);
    expect((await store.list()).map((a) => a.id), ['b']);
    expect(await ids(TileLayer.map), {for (final t in row([40]).tiles(maxZoom: _z)) tileIdOf(t)});
  });

  test('Orte-Dateien bleiben nur für Zellen, die ein Bereich noch berührt', () async {
    // Zwei Bereichshälften in verschiedenen Orte-Zellen: weit genug
    // auseinander, dass sie sicher in verschiedenen Zellen liegen.
    final far = tileAt(47.9, 11.9, _z);
    final twoCells = TileSetShape(zoom: _z, keys: {k(0), TileSetShape.keyOf(far.x, far.y, _z)});
    final cellsNear = row([0]).poiCells();
    final cellsFar = TileSetShape(zoom: _z, keys: {TileSetShape.keyOf(far.x, far.y, _z)}).poiCells();
    final near = [for (final c in cellsNear) poiCellFileName(c, PoiGroup.water)];
    final farFiles = [for (final c in cellsFar) poiCellFileName(c, PoiGroup.water)];
    final area = await seed(s: twoCells, poiFiles: [...near, ...farFiles]);
    final trimmer = AreaTrimmer(store, tiles);
    await trimmer.apply(await trimmer.plan([area], {TileSetShape.keyOf(far.x, far.y, _z)}));
    final after = (await store.list()).single;
    expect(after.poiFiles, near);
    expect(await store.readPoiFile(farFiles.first), isNull, reason: 'niemand nennt sie mehr');
    expect(await store.readPoiFile(near.first), isNotNull);
  });

  test('ein Rahmen-Bereich wird zur Kachelmenge ohne die herausgenommenen', () async {
    final rect = tileBounds(_z, x, y);
    final rectShape = RectShape(AreaBounds(
        south: rect.south + 1e-6, west: rect.west + 1e-6, north: rect.north - 1e-6,
        east: tileBounds(_z, x + 2, y).east - 1e-6));
    final mapTiles = rectShape.tiles(maxZoom: _z);
    await tiles.put('dach', TileLayer.map, [
      for (final t in mapTiles) StoreTile(t.z, t.x, t.y, Uint8List(3), '20260928'),
    ]);
    final area = StoredArea(
      id: 'r',
      name: 'Rahmen',
      bounds: rectShape.bounds,
      shape: rectShape,
      minZoom: 8,
      maxZoom: _z,
      build: '20260928',
      tiles: mapTiles.length,
      bytes: 1,
      savedAt: DateTime.utc(2026, 9, 28),
      format: kStoredAreaFormat,
    );
    await store.saveIndex([area]);
    final trimmer = AreaTrimmer(store, tiles);
    await trimmer.apply(await trimmer.plan([area], {k(1)}));
    final after = (await store.list()).single;
    expect(after.shape, isA<TileSetShape>());
    expect((after.shape as TileSetShape).keys, {k(0), k(2)});
  });
}
