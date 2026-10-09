// Die Ablage gespeicherter Bereiche: Dateien (Android), IndexedDB
// (Browser, hier die Speicher-Fassung derselben Implementierung) und der
// Test-Speicher verhalten sich gleich — Index, Archiv, Orte-Dateien,
// Löschen nimmt den Eintrag und den Altbestand; die Orte-Dateien liegen
// seit 0.106.0 je Name einmal.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_shim.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/area_store_idb.dart';
import 'package:trailbuddy/features/offline_areas/area_store_io.dart';

StoredArea _area(String id, {List<String> poiFiles = const [], int heightTiles = 0}) => StoredArea(
      id: id,
      name: 'Bereich $id',
      bounds: const AreaBounds(south: 47.9, west: 11.6, north: 47.95, east: 11.7),
      minZoom: 8,
      maxZoom: 13,
      build: '20260928',
      tiles: 42,
      bytes: 1234567,
      savedAt: DateTime.utc(2026, 9, 28, 18),
      poiFiles: poiFiles,
      heightTiles: heightTiles,
      heightBytes: heightTiles * 2500,
      heightsBuild: heightTiles == 0 ? null : '20261001',
    );

void main() {
  test('StoredArea überlebt JSON Feld für Feld', () {
    final a = _area('a1', poiFiles: const ['479_77.water.json'], heightTiles: 3);
    final back = StoredArea.fromJson(a.toJson());
    expect(back.heightTiles, 3);
    expect(back.heightBytes, 7500);
    expect(back.heightsBuild, '20261001');
    expect(back.hasHeights, isTrue);
    expect(back.id, 'a1');
    expect(back.name, a.name);
    expect(back.bounds.north, a.bounds.north);
    expect(back.maxZoom, 13);
    expect(back.build, '20260928');
    expect(back.tiles, 42);
    expect(back.bytes, 1234567);
    expect(back.savedAt, a.savedAt);
    expect(back.poiFiles, ['479_77.water.json']);
    expect(back.poiBuild, isNull);
  });

  test('ein Index-Eintrag ohne Höhen (vor 0.69.0) lädt als Bereich ohne Höhen', () {
    final json = _area('alt').toJson()
      ..remove('height_tiles')
      ..remove('height_bytes')
      ..remove('heights_build');
    final back = StoredArea.fromJson(json);
    expect(back.hasHeights, isFalse);
    expect(back.heightBytes, 0);
    expect(back.heightsBuild, isNull);
  });

  test('Wege (#212): Rundlauf, und ein Eintrag von vor 0.90.0 lädt ohne Wege und ohne Bau', () {
    final a = StoredArea.fromJson({
      ..._area('w').toJson(),
      'way_tiles': 5,
      'way_bytes': 900,
      'ways_build': '20261007',
    });
    final back = StoredArea.fromJson(a.toJson());
    expect([back.wayTiles, back.wayBytes, back.waysBuild, back.hasWays], [5, 900, '20261007', true]);
    expect(back.totalBytes, 1234567 + 900);
    final old = _area('alt').toJson()
      ..remove('way_tiles')
      ..remove('way_bytes')
      ..remove('ways_build');
    final oldBack = StoredArea.fromJson(old);
    expect([oldBack.hasWays, oldBack.wayBytes, oldBack.waysBuild], [false, 0, null]);
  });

  test('ein Index-Eintrag ohne Form (vor 0.24.0) lädt mit dem Rahmen als Form', () {
    final json = _area('alt').toJson()..remove('shape');
    final back = StoredArea.fromJson(json);
    expect(back.shape, isA<RectShape>());
    expect((back.shape as RectShape).bounds.north, back.bounds.north);
    expect(back.toJson()['shape'], isNotNull, reason: 'beim nächsten Schreiben trägt er sie');
  });

  test('Format und Zustand (#229): Rundlauf; ein Eintrag von vor 0.106.0 ist Altbestand und vollständig', () {
    final ref = _area('r').copyWith(format: kStoredAreaFormat, complete: false);
    final back = StoredArea.fromJson(ref.toJson());
    expect([back.format, back.legacy, back.complete], [kStoredAreaFormat, false, false]);
    final old = StoredArea.fromJson(_area('alt').toJson()
      ..remove('format')
      ..remove('complete'));
    expect([old.format, old.legacy, old.complete], [1, true, true]);
  });

  Future<void> exercise(AreaStore store, {required bool hasPath}) async {
    expect(await store.list(), isEmpty);
    // Die Orte-Dateien je Name EINMAL (#229), unabhängig vom Bereich.
    await store.putPoiFile('479_77.water.json', '{"pois":[]}');
    await store.putPoiFile('479_78.water.json', '{"pois":[1]}');
    await store.saveIndex([_area('a1', poiFiles: const ['479_77.water.json'])]);
    expect((await store.list()).single.id, 'a1');
    expect(await store.readPoiFile('479_77.water.json'), '{"pois":[]}');
    expect(await store.readPoiFile('0_0.food.json'), isNull);
    await store.deletePoiFiles(['479_78.water.json']);
    expect(await store.readPoiFile('479_78.water.json'), isNull);
    expect(await store.readPoiFile('479_77.water.json'), '{"pois":[]}', reason: 'nur, was genannt ist');
    // Der Altbestand: drei Archive und Orte je Bereich, lesbar bis zur Übernahme.
    final bytes = Uint8List.fromList(List.generate(300, (i) => i % 251));
    final heights = Uint8List.fromList(List.generate(120, (i) => 255 - i % 200));
    final ways = Uint8List.fromList(List.generate(80, (i) => i));
    await store.putArchive('a1', bytes);
    await store.putHeights('a1', heights);
    await store.putWays('a1', ways);
    await store.putLegacyPoiFile('a1', '479_77.water.json', '{"alt":1}');
    expect(await store.readArchive('a1'), bytes);
    expect((await store.archivePath('a1')) != null, hasPath);
    expect(await store.readHeights('a1'), heights);
    expect((await store.heightsPath('a1')) != null, hasPath);
    expect(await store.readWays('a1'), ways);
    expect((await store.waysPath('a1')) != null, hasPath);
    expect(await store.readLegacyPoiFile('a1', '479_77.water.json'), '{"alt":1}');
    expect(await store.readPoiFile('479_77.water.json'), '{"pois":[]}', reason: 'Altbestand und neue Ablage getrennt');
    // Nach der Übernahme geht der Altbestand, der Eintrag bleibt.
    await store.putArchive('a2', bytes);
    await store.deleteLegacy('a1');
    expect((await store.list()).single.id, 'a1');
    expect(await store.readArchive('a1'), isNull);
    expect(await store.archivePath('a1'), isNull);
    expect(await store.readHeights('a1'), isNull);
    expect(await store.readWays('a1'), isNull);
    expect(await store.readLegacyPoiFile('a1', '479_77.water.json'), isNull);
    expect(await store.readArchive('a2'), isNotNull, reason: 'nur der genannte Bereich');
    // Löschen nimmt den Eintrag; die Orte-Datei räumt, wer löscht (tile_refs).
    await store.saveIndex([_area('a1', poiFiles: const ['479_77.water.json']), _area('a2')]);
    await store.delete('a1');
    expect((await store.list()).map((a) => a.id), ['a2']);
    expect(await store.readPoiFile('479_77.water.json'), isNotNull);
  }

  test('Dateien auf dem Telefon', () async {
    final dir = await Directory.systemTemp.createTemp('areas');
    addTearDown(() => dir.delete(recursive: true));
    await exercise(FileAreaStore(baseDir: dir), hasPath: true);
    expect(await File('${dir.path}/a2.pmtiles').exists(), isTrue);
    expect(await File('${dir.path}/a2.pmtiles.part').exists(), isFalse);
    expect(await File('${dir.path}/a1.heights.pmtiles').exists(), isFalse);
    expect(await File('${dir.path}/a1.ways.pmtiles').exists(), isFalse);
    expect(await File('${dir.path}/pois/479_77.water.json').exists(), isTrue);
    expect(() => FileAreaStore(baseDir: dir).putPoiFile('../x.json', ''), throwsArgumentError);
    // Ein kaputter Index heißt keine Bereiche, kein Absturz.
    await File('${dir.path}/areas.json').writeAsString('{');
    expect(await FileAreaStore(baseDir: dir).list(), isEmpty);
  });

  test('IndexedDB im Browser (dieselbe Implementierung im Speicher)', () async {
    await exercise(IdbAreaStore(newIdbFactoryMemory()), hasPath: false);
  });

  test('der Test-Speicher', () async {
    await exercise(MemoryAreaStore(), hasPath: false);
  });
}
