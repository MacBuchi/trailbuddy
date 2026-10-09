// Der Kachelspeicher auf dem Telefon: je Region und Ebene EINE
// MBTiles-Datei unter `offline_maps/store/<region>/<ebene>.mbtiles` (im
// selben Backup-Ausschluss wie `offline_maps/`). MapLibre liest
// `mbtiles://` nativ (nachgesehen in 13.5.3,
// `platform/default/src/mbgl/storage/mbtiles_file_source.cpp`): Es fragt
// `SELECT tile_data FROM tiles WHERE zoom_level … tile_column … tile_row`
// mit der TMS-Zeile, öffnet die Datei NUR LESEND und hält sie offen,
// entpackt gzip selbst und braucht aus `metadata` `format = pbf` sowie
// `minzoom`/`maxzoom`. Die eigene Spalte `build` fragt es nicht.
//
// Drei Dinge, die man wissen muss:
// - **WAL**, damit MapLibre weiterliest, während die App schreibt; nach
//   dem Schreiben eines Blocks bleibt die Datei konsistent lesbar.
// - **Die Datei wird nie gelöscht**, auch leer nicht: MapLibre hält ihren
//   Pfad offen, und eine neu angelegte Datei unter demselben Namen sähe
//   es nicht. `auto_vacuum = INCREMENTAL` gibt den Platz nach dem
//   Entfernen trotzdem frei.
// - **Alles synchron im Main-Isolate** (das Paket `sqlite3` ruft über
//   FFI): ein Block sind 256 Kacheln, wenige MB — kurz genug, und ein
//   Isolate müsste die Bytes erst hinüberkopieren.
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pmtiles/pmtiles.dart' show ZXY;
import 'package:sqlite3/sqlite3.dart';

import 'tile_store.dart';

class SqliteTileStore implements TileStore {
  SqliteTileStore({Directory? baseDir}) : _baseDir = baseDir;

  Directory? _baseDir;
  final _dbs = <String, Database>{};

  Future<Directory> _dir() async {
    final cached = _baseDir;
    if (cached != null) return cached;
    final support = await getApplicationSupportDirectory();
    return _baseDir = Directory('${support.path}/offline_maps/store');
  }

  Future<File> _file(String region, TileLayer layer) async =>
      File('${(await _dir()).path}/${checkStoreRegion(region)}/${layer.name}.mbtiles');

  /// Die geöffnete Datei; mit [create] legt sie sie an, sonst null, wenn
  /// es sie nicht gibt.
  Future<Database?> _db(String region, TileLayer layer, {bool create = false}) async {
    final file = await _file(region, layer);
    final open = _dbs[file.path];
    if (open != null) return open;
    if (!create && !await file.exists()) return null;
    await file.parent.create(recursive: true);
    final db = sqlite3.open(file.path);
    // Vor der ersten Tabelle — danach wirkt es erst nach einem VACUUM.
    db.execute('PRAGMA auto_vacuum = INCREMENTAL');
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('CREATE TABLE IF NOT EXISTS metadata (name TEXT PRIMARY KEY, value TEXT)');
    db.execute('CREATE TABLE IF NOT EXISTS tiles ('
        'zoom_level INTEGER NOT NULL, tile_column INTEGER NOT NULL, tile_row INTEGER NOT NULL, '
        'tile_data BLOB NOT NULL, build TEXT NOT NULL, '
        'PRIMARY KEY (zoom_level, tile_column, tile_row))');
    final meta = db.prepare('INSERT OR IGNORE INTO metadata (name, value) VALUES (?, ?)');
    try {
      meta.execute(['name', 'trailbuddy-$region-${layer.name}']);
      // Höhen sind keine Vektorkacheln; MapLibre liest diese Datei nie.
      meta.execute(['format', layer == TileLayer.heights ? 'x-trailbuddy-heights' : 'pbf']);
    } finally {
      meta.close();
    }
    return _dbs[file.path] = db;
  }

  static int _row(int z, int y) => (1 << z) - 1 - y;

  @override
  Future<Map<int, StoredTileInfo>> index(String region, TileLayer layer) async {
    final db = await _db(region, layer);
    if (db == null) return const {};
    final rows = db.select('SELECT zoom_level, tile_column, tile_row, length(tile_data), build FROM tiles');
    return {
      for (final r in rows)
        ZXY(r.columnAt(0) as int, r.columnAt(1) as int, _row(r.columnAt(0) as int, r.columnAt(2) as int))
                .toTileId():
            StoredTileInfo(r.columnAt(3) as int, r.columnAt(4) as String),
    };
  }

  @override
  Future<Uint8List?> read(String region, TileLayer layer, int z, int x, int y) async {
    final db = await _db(region, layer);
    if (db == null) return null;
    final rows = db.select(
        'SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?', [z, x, _row(z, y)]);
    if (rows.isEmpty) return null;
    final value = rows.first.columnAt(0);
    return value is Uint8List ? value : Uint8List.fromList(value as List<int>);
  }

  @override
  Future<void> put(String region, TileLayer layer, List<StoreTile> tiles) async {
    if (tiles.isEmpty) return;
    final db = (await _db(region, layer, create: true))!;
    final insert = db.prepare('INSERT OR REPLACE INTO tiles '
        '(zoom_level, tile_column, tile_row, tile_data, build) VALUES (?, ?, ?, ?, ?)');
    db.execute('BEGIN');
    try {
      for (final t in tiles) {
        insert.execute([t.z, t.x, _row(t.z, t.y), t.bytes, t.build]);
      }
      _updateZoomRange(db);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      insert.close();
    }
  }

  /// `minzoom`/`maxzoom` aus dem, was liegt — MapLibre liest sie einmal
  /// beim Öffnen der Quelle.
  void _updateZoomRange(Database db) {
    final range = db.select('SELECT MIN(zoom_level), MAX(zoom_level) FROM tiles').first;
    if (range.columnAt(0) == null) return;
    final set = db.prepare('INSERT OR REPLACE INTO metadata (name, value) VALUES (?, ?)');
    try {
      set.execute(['minzoom', '${range.columnAt(0)}']);
      set.execute(['maxzoom', '${range.columnAt(1)}']);
    } finally {
      set.close();
    }
  }

  @override
  Future<void> remove(String region, TileLayer layer, Iterable<int> tileIds) async {
    final db = await _db(region, layer);
    if (db == null) return;
    final ids = tileIds.toList();
    if (ids.isEmpty) return;
    final delete = db.prepare('DELETE FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?');
    db.execute('BEGIN');
    try {
      for (final id in ids) {
        final t = ZXY.fromTileId(id);
        delete.execute([t.z, t.x, _row(t.z, t.y)]);
      }
      _updateZoomRange(db);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      delete.close();
    }
    // Gibt die frei gewordenen Seiten an das Dateisystem zurück — sonst
    // stünde „gibt … frei" über einer Datei, die gleich groß bleibt.
    db.execute('PRAGMA incremental_vacuum');
  }

  @override
  Future<String?> path(String region, TileLayer layer) async {
    final file = await _file(region, layer);
    return await file.exists() ? file.path : null;
  }

  /// Schließt alle Dateien — für Tests; die App hält sie offen.
  void close() {
    for (final db in _dbs.values) {
      db.close();
    }
    _dbs.clear();
  }
}

TileStore createTileStore() => SqliteTileStore();
