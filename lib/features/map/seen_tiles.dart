// „Gesehenes bleibt liegen" im Browser (#155, Konzept offline-karten 3.2):
// Was die flutter_map-Engine vom Host geholt hat (Karte UND Wege), bleibt
// in IndexedDB liegen, höchstens [kSeenTilesCacheBytes], die am längsten
// nicht gebrauchte Kachel zuerst. Auf Android erledigt das MapLibres
// Ambient Cache (seit 0.99.0); dort gibt es keinen Speicher hier, und der
// flutter_map-Rückfall bleibt, wie er war.
//
// Der Schlüssel trägt den Dateinamen des Archivs (`dach-<build>.pmtiles`),
// und Dateien mit Datum sind unveränderlich. Eine liegende Kachel ist
// deshalb nie veraltet, und der Speicher wird ZUERST gefragt — auch mit
// Netz: Das spart je Kachel eine R2-Class-B-Anfrage (#55). Ein neuer Bau
// hat neue Schlüssel; die alten werden nicht mehr gebraucht und gehen
// als Erste.
import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart' show GZipDecoder;
import 'package:idb_shim/idb_shim.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../../data/browser_db.dart';
import 'online_map.dart' show kSeenTilesCacheBytes;
import 'pmtiles_tile_provider.dart';

/// Eine Kachel, wie sie im Archiv liegt: die Bytes komprimiert, denn so
/// rechnet auch die Obergrenze (gemessen an den Archivgrößen).
class SeenTile {
  const SeenTile(this.bytes, {required this.gzip});

  final Uint8List bytes;
  final bool gzip;

  Uint8List decoded() => gzip ? Uint8List.fromList(GZipDecoder().decodeBytes(bytes)) : bytes;
}

abstract class SeenTileStore {
  /// Null heißt: liegt nicht (oder der Speicher ist nicht zu öffnen).
  Future<SeenTile?> read(String key);

  /// Wirft nie — ein Speicher, der nicht schreibt, ist nur eine Kachel
  /// weniger ohne Empfang.
  Future<void> write(String key, SeenTile tile);
}

/// Wie oft „zuletzt gebraucht" höchstens neu geschrieben wird: Jede
/// gelesene Kachel einen Eintrag zu schreiben, kostete mehr als die
/// Reihenfolge wert ist.
const kSeenTileTouchInterval = Duration(hours: 1);

/// Geräumt wird bis auf diesen Anteil der Grenze, nicht bis knapp
/// darunter — sonst räumte jede neue Kachel die nächstälteste.
const kSeenTileEvictTo = 0.9;

class _Entry {
  _Entry(this.bytes, this.at, this.gzip);

  final int bytes;
  int at;
  final bool gzip;

  String encode() => '$bytes|$at|${gzip ? 1 : 0}';

  static _Entry? decode(Object? value) {
    if (value is! String) return null;
    final parts = value.split('|');
    if (parts.length != 3) return null;
    final n = int.tryParse(parts[0]);
    final at = int.tryParse(parts[1]);
    if (n == null || at == null) return null;
    return _Entry(n, at, parts[2] == '1');
  }
}

/// Der Speicher in IndexedDB. Der Index (Größe, Zeit, Kompression je
/// Kachel) wird beim ersten Zugriff einmal ganz gelesen — bei 100 MB ein
/// paar tausend kurze Texte —, danach kostet ein Fehlgriff nichts, und
/// geräumt wird aus dem Speicher heraus. Ein zweiter Tab führt seinen
/// eigenen Index: Was der eine schreibt, sieht der andere erst nach einem
/// Neuladen, und beide räumen nach ihrem Stand. Das kostet höchstens eine
/// Kachel, nie eine falsche.
class IdbSeenTileStore implements SeenTileStore {
  IdbSeenTileStore(IdbFactory factory, {this.capBytes = kSeenTilesCacheBytes, DateTime Function()? now})
      : _db = BrowserDb(factory),
        _now = now ?? DateTime.now;

  final BrowserDb _db;
  final int capBytes;
  final DateTime Function() _now;

  Future<Map<String, _Entry>?>? _index;
  int _total = 0;

  /// Scheitert das Öffnen (privater Modus, `file://`), bleibt der
  /// Speicher für diese Sitzung leer, statt es bei jeder Kachel neu zu
  /// versuchen.
  Future<Map<String, _Entry>?> _loaded() => _index ??= _load();

  Future<Map<String, _Entry>?> _load() async {
    try {
      final (keys, values) = await _db.readStore(kSeenTileIndexStore,
          (s) async => (await s.getAllKeys(), await s.getAll()));
      final index = <String, _Entry>{};
      for (var i = 0; i < keys.length && i < values.length; i++) {
        final entry = _Entry.decode(values[i]);
        if (entry != null) index['${keys[i]}'] = entry;
      }
      _total = index.values.fold(0, (sum, e) => sum + e.bytes);
      return index;
    } catch (_) {
      // Still degradieren: Ohne Speicher zeigt die Karte ohne Empfang die
      // Übersicht — wie vor #155.
      return null;
    }
  }

  @override
  Future<SeenTile?> read(String key) async {
    final index = await _loaded();
    final entry = index?[key];
    if (entry == null) return null;
    try {
      final value = await _db.readStore(kSeenTileStore, (s) => s.getObject(key));
      final bytes = value is Uint8List ? value : (value is List<int> ? Uint8List.fromList(value) : null);
      if (bytes == null) {
        // Index ohne Bytes (ein anderer Tab hat geräumt): vergessen.
        index!.remove(key);
        _total -= entry.bytes;
        return null;
      }
      final now = _now().millisecondsSinceEpoch;
      if (now - entry.at > kSeenTileTouchInterval.inMilliseconds) {
        entry.at = now;
        unawaited(_db
            .writeStore(kSeenTileIndexStore, (s) => s.put(entry.encode(), key))
            .then((_) {}, onError: (Object _) {}));
      }
      return SeenTile(bytes, gzip: entry.gzip);
    } catch (_) {
      // Ein Lesefehler ist eine fehlende Kachel, kein Fehlerbericht —
      // dieselbe Regel wie beim Öffnen.
      return null;
    }
  }

  @override
  Future<void> write(String key, SeenTile tile) async {
    final index = await _loaded();
    if (index == null) return;
    try {
      final entry = _Entry(tile.bytes.length, _now().millisecondsSinceEpoch, tile.gzip);
      await _db.writeStore(kSeenTileStore, (s) => s.put(tile.bytes, key));
      await _db.writeStore(kSeenTileIndexStore, (s) => s.put(entry.encode(), key));
      final before = index[key];
      if (before != null) _total -= before.bytes;
      index[key] = entry;
      _total += entry.bytes;
      if (_total > capBytes) await _evict(index);
    } catch (_) {
      // Voll (QuotaExceeded) oder geräumt: eine Kachel weniger ohne
      // Empfang, nicht mehr.
    }
  }

  Future<void> _evict(Map<String, _Entry> index) async {
    final oldest = index.entries.toList()..sort((a, b) => a.value.at.compareTo(b.value.at));
    final target = (capBytes * kSeenTileEvictTo).floor();
    final gone = <String>[];
    for (final e in oldest) {
      if (_total <= target) break;
      gone.add(e.key);
      _total -= e.value.bytes;
      index.remove(e.key);
    }
    await _db.writeStore(kSeenTileIndexStore, (s) async {
      for (final key in gone) {
        await s.delete(key);
      }
    });
    await _db.writeStore(kSeenTileStore, (s) async {
      for (final key in gone) {
        await s.delete(key);
      }
    });
  }

  /// Für Tests: so viele Bytes führt der Index.
  int get totalBytes => _total;
}

/// Der Kachel-Lieferant der Online-Karte im Browser: erst der Speicher,
/// dann der Host. Ohne [online] (kein frisches Manifest, Host weg) liefert
/// er nur, was liegt, und wo nichts liegt, scheint die Übersicht durch.
class SeenTilesVectorTileProvider extends VectorTileProvider {
  SeenTilesVectorTileProvider({
    required this.archive,
    required this.store,
    required this.online,
    required int minZoom,
    required int maxZoom,
  })  : _minZoom = minZoom,
        _maxZoom = maxZoom;

  /// Der Dateiname des Archivs — der erste Teil jedes Schlüssels.
  final String archive;
  final SeenTileStore store;
  final PmTilesVectorTileProvider? online;
  final int _minZoom;
  final int _maxZoom;

  /// Nur ohne [online]: Die Karte zeigt dann gesehene Kacheln über der
  /// Übersicht, nicht statt ihr.
  bool get seenOnly => online == null;

  String keyOf(TileIdentity tile) => '$archive/${tile.z}/${tile.x}/${tile.y}';

  Future<void> close() async => online?.close();

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    final key = keyOf(tile);
    final seen = await store.read(key);
    if (seen != null) return seen.decoded();
    final online = this.online;
    if (online == null) {
      throw ProviderException(
        message: 'Kachel ${tile.key()} nicht gesehen',
        retryable: Retryable.none,
        statusCode: 404,
      );
    }
    final raw = await online.rawTile(tile);
    unawaited(store.write(key, raw));
    return raw.decoded();
  }

  @override
  int get minimumZoom => _minZoom;

  @override
  int get maximumZoom => _maxZoom;

  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;

  @override
  TileProviderType get type => TileProviderType.vector;
}
