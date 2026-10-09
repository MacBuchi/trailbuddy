// Der Kachelspeicher (#229): MBTiles auf dem Telefon, IndexedDB im
// Browser (hier die Speicher-Fassung derselben Implementierung) und der
// Test-Speicher halten dieselben Zusagen — Index ohne Bytes, Ersetzen
// statt Doppeln, Entfernen, Regionen und Ebenen getrennt. Für MBTiles
// dazu, was MapLibre aus der Datei liest: TMS-Zeile, `format`,
// `minzoom`/`maxzoom`.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_shim.dart';
import 'package:pmtiles/pmtiles.dart' show ZXY;
import 'package:sqlite3/sqlite3.dart';
import 'package:trailbuddy/features/offline_areas/tile_store.dart';
import 'package:trailbuddy/features/offline_areas/tile_store_idb.dart';
import 'package:trailbuddy/features/offline_areas/tile_store_io.dart';

Uint8List _bytes(int n, [int fill = 7]) => Uint8List.fromList(List.filled(n, fill));

int _id(int z, int x, int y) => ZXY(z, x, y).toTileId();

void main() {
  final stores = <String, Future<(TileStore, Future<void> Function())> Function()>{
    'Speicher': () async => (MemoryTileStore(), () async {}),
    'IndexedDB': () async => (IdbTileStore(newIdbFactoryMemory()), () async {}),
    'MBTiles': () async {
      final dir = await Directory.systemTemp.createTemp('tile_store_test');
      final store = SqliteTileStore(baseDir: dir);
      return (
        store,
        () async {
          store.close();
          await dir.delete(recursive: true);
        }
      );
    },
  };

  for (final MapEntry(key: name, value: make) in stores.entries) {
    group(name, () {
      test('ablegen, lesen, Index ohne Bytes, ersetzen statt doppeln', () async {
        final (store, done) = await make();
        try {
          expect(await store.index('dach', TileLayer.map), isEmpty);
          expect(await store.read('dach', TileLayer.map, 13, 4380, 2860), isNull);
          await store.put('dach', TileLayer.map, [
            StoreTile(13, 4380, 2860, _bytes(10), '20261001'),
            StoreTile(8, 136, 89, _bytes(4), '20261001'),
          ]);
          expect(await store.read('dach', TileLayer.map, 13, 4380, 2860), _bytes(10));
          final index = await store.index('dach', TileLayer.map);
          expect(index.keys.toSet(), {_id(13, 4380, 2860), _id(8, 136, 89)});
          expect(index[_id(13, 4380, 2860)]!.bytes, 10);
          expect(index[_id(13, 4380, 2860)]!.build, '20261001');
          // Dieselbe Kachel aus einem neueren Bau ersetzt die alte.
          await store.put('dach', TileLayer.map, [StoreTile(13, 4380, 2860, _bytes(12, 9), '20261101')]);
          final after = await store.index('dach', TileLayer.map);
          expect(after, hasLength(2));
          expect(after[_id(13, 4380, 2860)]!.build, '20261101');
          expect(await store.read('dach', TileLayer.map, 13, 4380, 2860), _bytes(12, 9));
        } finally {
          await done();
        }
      });

      test('Regionen und Ebenen sind getrennt', () async {
        final (store, done) = await make();
        try {
          await store.put('dach', TileLayer.map, [StoreTile(13, 1, 2, _bytes(3), 'a')]);
          await store.put('dach', TileLayer.ways, [StoreTile(13, 1, 2, _bytes(5), 'b')]);
          await store.put('ca', TileLayer.map, [StoreTile(13, 1, 2, _bytes(6), 'c')]);
          expect((await store.index('dach', TileLayer.map))[_id(13, 1, 2)]!.build, 'a');
          expect((await store.index('dach', TileLayer.ways))[_id(13, 1, 2)]!.build, 'b');
          expect((await store.index('ca', TileLayer.map))[_id(13, 1, 2)]!.build, 'c');
          expect(await store.index('ca', TileLayer.heights), isEmpty);
          expect(await store.read('ca', TileLayer.map, 13, 1, 2), _bytes(6));
        } finally {
          await done();
        }
      });

      test('entfernen nimmt nur, was genannt ist; Fehlendes ist kein Fehler', () async {
        final (store, done) = await make();
        try {
          await store.put('dach', TileLayer.heights, [
            StoreTile(13, 10, 20, _bytes(3), 'h'),
            StoreTile(13, 11, 20, _bytes(3), 'h'),
          ]);
          await store.remove('dach', TileLayer.heights, [_id(13, 10, 20), _id(13, 99, 99)]);
          expect((await store.index('dach', TileLayer.heights)).keys, [_id(13, 11, 20)]);
          expect(await store.read('dach', TileLayer.heights, 13, 10, 20), isNull);
          await store.remove('ca', TileLayer.heights, [_id(13, 1, 1)]);
        } finally {
          await done();
        }
      });

      test('keine Region, die kein Dateiname sein darf', () async {
        final (store, done) = await make();
        try {
          expect(() => store.index('../x', TileLayer.map), throwsArgumentError);
        } finally {
          await done();
        }
      });
    });
  }

  test('MBTiles: die Datei, wie MapLibre sie liest', () async {
    final dir = await Directory.systemTemp.createTemp('tile_store_mbtiles');
    final store = SqliteTileStore(baseDir: dir);
    try {
      expect(await store.path('dach', TileLayer.map), isNull, reason: 'Lesen legt keine Datei an');
      await store.index('dach', TileLayer.map);
      expect(await store.path('dach', TileLayer.map), isNull);
      await store.put('dach', TileLayer.map, [
        StoreTile(13, 4380, 2860, _bytes(10), '20261001'),
        StoreTile(8, 136, 89, _bytes(4), '20261001'),
      ]);
      final path = await store.path('dach', TileLayer.map);
      expect(path, '${dir.path}/dach/map.mbtiles');
      // Die Abfrage von mbtiles_file_source.cpp, mit TMS-Zeile.
      final db = sqlite3.open(path!, mode: OpenMode.readOnly);
      try {
        final row = (1 << 13) - 1 - 2860;
        final hit = db.select(
            'SELECT tile_data FROM tiles where zoom_level = 13 AND tile_column = 4380 AND tile_row = $row');
        expect(hit, hasLength(1));
        expect(hit.first.columnAt(0), _bytes(10));
        final meta = {for (final r in db.select('SELECT name, value FROM metadata')) r.columnAt(0): r.columnAt(1)};
        expect(meta['format'], 'pbf');
        expect(meta['minzoom'], '8');
        expect(meta['maxzoom'], '13');
        expect(db.select('PRAGMA journal_mode').first.columnAt(0), 'wal');
      } finally {
        db.close();
      }
      // Höhen sind keine Vektorkacheln.
      await store.put('dach', TileLayer.heights, [StoreTile(13, 1, 1, _bytes(2), 'h')]);
      final h = sqlite3.open((await store.path('dach', TileLayer.heights))!, mode: OpenMode.readOnly);
      try {
        expect(h.select("SELECT value FROM metadata WHERE name = 'format'").first.columnAt(0), isNot('pbf'));
      } finally {
        h.close();
      }
      // Leer bleibt die Datei liegen (MapLibre hält ihren Pfad offen).
      await store.remove('dach', TileLayer.map, [_id(13, 4380, 2860), _id(8, 136, 89)]);
      expect(await store.index('dach', TileLayer.map), isEmpty);
      expect(await store.path('dach', TileLayer.map), path);
    } finally {
      store.close();
      await dir.delete(recursive: true);
    }
  });

  test('MBTiles: Entfernen gibt Platz frei', () async {
    final dir = await Directory.systemTemp.createTemp('tile_store_vacuum');
    final store = SqliteTileStore(baseDir: dir);
    try {
      await store.put('dach', TileLayer.map, [
        for (var x = 0; x < 200; x++) StoreTile(13, x, 7, _bytes(20000, x % 251), 'b'),
      ]);
      store.close();
      final file = File('${dir.path}/dach/map.mbtiles');
      final full = await file.length();
      await store.remove('dach', TileLayer.map, [for (var x = 0; x < 200; x++) _id(13, x, 7)]);
      store.close();
      expect(await file.length(), lessThan(full ~/ 4), reason: 'auto_vacuum = INCREMENTAL');
    } finally {
      store.close();
      await dir.delete(recursive: true);
    }
  });

  test('gzip erkennen und auspacken', () {
    final packed = Uint8List.fromList(gzip.encode([1, 2, 3]));
    expect(isGzip(packed), isTrue);
    expect(unpackStoredTile(packed), [1, 2, 3]);
    expect(unpackStoredTile(Uint8List.fromList([1, 2, 3])), [1, 2, 3]);
  });
}
