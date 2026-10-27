// Der Kachelspeicher (#229, `docs/konzept-offline-karten.md` Abschnitt 8):
// je Region und Ebene (Karte, Höhen, Wege) EIN Speicher, in dem jede
// Kachel genau einmal liegt — mit den Bytes aus dem Host-Archiv
// (unverändert, dieselbe Kompression) und dem Bau, aus dem sie stammt.
// Bereiche sind nur noch Verweise darauf (Name, Region, Form); was liegen
// soll, ist die Vereinigung ihrer Formen (`tile_refs.dart`).
//
// Auf dem Telefon MBTiles (SQLite) je Region und Ebene, weil MapLibre
// `mbtiles://` nativ liest — eine Quelle je Region statt einer je Bereich
// (`tile_store_io.dart`). Im Browser IndexedDB (`tile_store_idb.dart`),
// im Test der Speicher hier unten.
import 'dart:typed_data';

import 'package:archive/archive.dart' show GZipDecoder;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmtiles/pmtiles.dart' show ZXY;

import 'tile_store_web.dart' if (dart.library.io) 'tile_store_io.dart';

/// Die Ebenen, die ein Bereich mitbringt. Der Name wird Teil eines
/// Dateinamens (`map.mbtiles`) und eines Schlüssels.
///
/// [routing] ist die einzige, die nie vom Host kommt (#380): die
/// vorgebackenen Stücke des Planer-Graphen (`routing_tile.dart`), gebacken
/// auf dem Gerät aus den drei anderen. Der Download plant sie nicht, und
/// „veraltet / Aktualisieren" zählt sie nicht — ein Stück, dessen
/// Quellkachel sich ändert, backt der Planer ohne Netz neu. Verwiesen wird
/// sie wie die Höhen (z13), also gehen verwaiste Stücke mit dem Bereich.
enum TileLayer { map, heights, ways, routing }

/// Was der Index über eine liegende Kachel weiß — ohne ihre Bytes.
class StoredTileInfo {
  const StoredTileInfo(this.bytes, this.build);

  /// Ihre Größe, wie sie liegt (komprimiert).
  final int bytes;

  /// Der Bau des Host-Archivs, aus dem sie kam (`JJJJMMTT`) — das Alter
  /// je Kachel (Konzept 8.2).
  final String build;
}

/// Eine Kachel, die in den Speicher geht.
class StoreTile {
  const StoreTile(this.z, this.x, this.y, this.bytes, this.build);

  final int z;
  final int x;
  final int y;

  /// Die Bytes aus dem Host-Archiv, mit dessen Kompression.
  final Uint8List bytes;
  final String build;

  int get id => ZXY(z, x, y).toTileId();
}

/// Eine Region wird Teil eines Dateinamens und eines Schlüssels — nur
/// Kleinbuchstaben, wie der Index des Hosts sie vergibt.
final _regionId = RegExp(r'^[a-z]{2,8}$');

String checkStoreRegion(String region) {
  if (!_regionId.hasMatch(region)) throw ArgumentError.value(region, 'region', 'keine Region');
  return region;
}

abstract interface class TileStore {
  /// Alle liegenden Kacheln der Region in [layer], nach Kachel-Id
  /// (`ZXY.toTileId`) — leer, wenn dort nichts liegt.
  Future<Map<int, StoredTileInfo>> index(String region, TileLayer layer);

  /// Die Bytes einer Kachel, wie sie liegen (komprimiert); null, wenn sie
  /// nicht liegt.
  Future<Uint8List?> read(String region, TileLayer layer, int z, int x, int y);

  /// Der Bau der Kacheln mit diesen Ids, soweit sie liegen — für wenige
  /// Kacheln, ohne den ganzen [index] einer Region zu lesen (der Planer
  /// fragt je Planung die Kacheln seines Rahmens, #380).
  Future<Map<int, String>> builds(String region, TileLayer layer, Iterable<int> tileIds);

  /// Legt [tiles] ab, ersetzt liegende mit derselben Id — in EINER
  /// Transaktion: Ein Abbruch lässt den Block ganz oder gar nicht da.
  Future<void> put(String region, TileLayer layer, List<StoreTile> tiles);

  /// Nimmt die Kacheln mit diesen Ids weg; fehlende sind kein Fehler.
  Future<void> remove(String region, TileLayer layer, Iterable<int> tileIds);

  /// Der Pfad der MBTiles-Datei für MapLibre — nur auf dem Telefon, nur
  /// wenn sie existiert.
  Future<String?> path(String region, TileLayer layer);
}

/// Ob die Bytes gzip sind (Protomaps schreibt gzip; MapLibre und der
/// Leser hier erkennen es an denselben zwei Bytes).
bool isGzip(Uint8List bytes) => bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;

/// Die Kachel ausgepackt, wie Renderer und Höhenleser sie brauchen.
Uint8List unpackStoredTile(Uint8List bytes) =>
    isGzip(bytes) ? Uint8List.fromList(GZipDecoder().decodeBytes(bytes)) : bytes;

/// Im Speicher — für Tests und als Rückfall.
class MemoryTileStore implements TileStore {
  final _tiles = <String, Map<int, ({Uint8List bytes, String build})>>{};

  static String _key(String region, TileLayer layer) => '${checkStoreRegion(region)}/${layer.name}';

  /// Wie oft [put] gerufen wurde — für Tests, die Blöcke zählen.
  int puts = 0;

  @override
  Future<Map<int, StoredTileInfo>> index(String region, TileLayer layer) async => {
        for (final e in (_tiles[_key(region, layer)] ?? const {}).entries)
          e.key: StoredTileInfo(e.value.bytes.length, e.value.build),
      };

  @override
  Future<Uint8List?> read(String region, TileLayer layer, int z, int x, int y) async =>
      _tiles[_key(region, layer)]?[ZXY(z, x, y).toTileId()]?.bytes;

  @override
  Future<Map<int, String>> builds(String region, TileLayer layer, Iterable<int> tileIds) async {
    final m = _tiles[_key(region, layer)] ?? const {};
    return {
      for (final id in tileIds)
        if (m[id] case final t?) id: t.build,
    };
  }

  @override
  Future<void> put(String region, TileLayer layer, List<StoreTile> tiles) async {
    puts++;
    final m = _tiles.putIfAbsent(_key(region, layer), () => {});
    for (final t in tiles) {
      m[t.id] = (bytes: t.bytes, build: t.build);
    }
  }

  @override
  Future<void> remove(String region, TileLayer layer, Iterable<int> tileIds) async {
    final m = _tiles[_key(region, layer)];
    if (m == null) return;
    for (final id in tileIds) {
      m.remove(id);
    }
  }

  @override
  Future<String?> path(String region, TileLayer layer) async => null;
}

/// Der Speicher der Plattform: MBTiles auf dem Telefon, IndexedDB im
/// Browser. Tests hängen [MemoryTileStore] ein.
final tileStoreProvider = Provider<TileStore>((ref) => createTileStore());
