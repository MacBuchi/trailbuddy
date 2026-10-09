// Der Kachelspeicher im Browser (#229): IndexedDB über `idb_shim`, zwei
// Speicher mit demselben Schlüssel `<region>/<ebene>/<kachel-id>` — die
// Bytes und ein kleiner Index (`Bytes|Bau`), damit „was liegt" ohne die
// Bytes beantwortet wird. Geschrieben in EINER Transaktion über beide.
// Läuft auf der VM gegen `newIdbFactoryMemory()` (Tests), im Browser gegen
// die echte IndexedDB (`tile_store_web.dart`).
import 'dart:typed_data';

import 'package:idb_shim/idb_shim.dart';
import 'package:pmtiles/pmtiles.dart' show ZXY;

import '../../data/browser_db.dart';
import 'tile_store.dart';

class IdbTileStore implements TileStore {
  IdbTileStore(IdbFactory factory) : _db = BrowserDb(factory);

  final BrowserDb _db;

  static String _prefix(String region, TileLayer layer) => '${checkStoreRegion(region)}/${layer.name}/';

  static KeyRange _range(String prefix) => KeyRange.bound(prefix, '$prefix￿');

  @override
  Future<Map<int, StoredTileInfo>> index(String region, TileLayer layer) async {
    final prefix = _prefix(region, layer);
    final (keys, values) = await _db.readStore(kAreaTileIndexStore,
        (s) async => (await s.getAllKeys(_range(prefix)), await s.getAll(_range(prefix))));
    final out = <int, StoredTileInfo>{};
    for (var i = 0; i < keys.length && i < values.length; i++) {
      final id = int.tryParse('${keys[i]}'.substring(prefix.length));
      final text = values[i];
      if (id == null || text is! String) continue;
      final cut = text.indexOf('|');
      final bytes = cut < 0 ? null : int.tryParse(text.substring(0, cut));
      if (bytes == null) continue;
      out[id] = StoredTileInfo(bytes, text.substring(cut + 1));
    }
    return out;
  }

  @override
  Future<Uint8List?> read(String region, TileLayer layer, int z, int x, int y) async {
    final key = '${_prefix(region, layer)}${ZXY(z, x, y).toTileId()}';
    final value = await _db.readStore(kAreaTileStore, (s) => s.getObject(key));
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    return null;
  }

  @override
  Future<void> put(String region, TileLayer layer, List<StoreTile> tiles) async {
    if (tiles.isEmpty) return;
    final prefix = _prefix(region, layer);
    await _db.writeStores([kAreaTileStore, kAreaTileIndexStore], (txn) async {
      final data = txn.objectStore(kAreaTileStore);
      final index = txn.objectStore(kAreaTileIndexStore);
      for (final t in tiles) {
        final key = '$prefix${t.id}';
        await data.put(t.bytes, key);
        await index.put('${t.bytes.length}|${t.build}', key);
      }
    });
  }

  @override
  Future<void> remove(String region, TileLayer layer, Iterable<int> tileIds) async {
    final ids = tileIds.toList();
    if (ids.isEmpty) return;
    final prefix = _prefix(region, layer);
    await _db.writeStores([kAreaTileStore, kAreaTileIndexStore], (txn) async {
      final data = txn.objectStore(kAreaTileStore);
      final index = txn.objectStore(kAreaTileIndexStore);
      for (final id in ids) {
        await data.delete('$prefix$id');
        await index.delete('$prefix$id');
      }
    });
  }

  @override
  Future<String?> path(String region, TileLayer layer) async => null;
}
