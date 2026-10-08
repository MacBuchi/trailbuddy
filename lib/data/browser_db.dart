// Die eine IndexedDB-Datenbank der App im Browser — ein Speicher je
// Zweck (PilzBuddy `browser_db.dart`). Name und Version haben EINEN
// Besitzer: Öffnete ein Speicher v1 und ein anderer v2, blockierte der
// Upgrade im selben Tab, dauerhaft, ohne Fehlermeldung. Ein neuer
// Speicher heißt: hier eintragen, [kBrowserDbVersion] erhöhen.
import 'package:idb_shim/idb_shim.dart';

const kBrowserDbName = 'trailbuddy';

/// v1: gespeicherte Kartenbereiche (Konzept-Schritt 3).
/// v2: gesehene Kacheln der Online-Karte (#155).
/// v3: Ausgangskorb und Kopie des Netzes (#153).
const kBrowserDbVersion = 3;

/// Der Index der Bereiche (ein Eintrag, die Liste als JSON-Text).
const kAreaIndexStore = 'area_index';

/// Die Archive je Bereich (Schlüssel: Bereichs-Id, Wert: Bytes).
const kAreaArchiveStore = 'area_archives';

/// Die Orte-Dateien der Bereiche (Schlüssel `<id>/<datei>`, Wert: Text).
const kAreaPoiStore = 'area_pois';

/// Gesehene Kacheln (Schlüssel `<archiv>/z/x/y`, Wert: Bytes, wie im
/// Archiv komprimiert) — `seen_tiles.dart`.
const kSeenTileStore = 'seen_tiles';

/// Ihr Index (gleicher Schlüssel, Wert: Text `Bytes|Zeit|gzip`) — klein,
/// beim ersten Zugriff ganz gelesen, damit ein Fehlgriff nichts kostet.
const kSeenTileIndexStore = 'seen_tile_index';

/// Der Ausgangskorb (ein Eintrag `jobs`, derselbe JSON-Text wie
/// `outbox/jobs.json` auf Android) — `outbox_idb.dart`.
const kOutboxStore = 'outbox';

/// Die Kopie des Netzes (ein Eintrag `network`, derselbe JSON-Text wie
/// `trail_cache/network.json`) — `trail_cache_idb.dart`.
const kTrailCacheStore = 'trail_cache';

const _stores = [
  kAreaIndexStore,
  kAreaArchiveStore,
  kAreaPoiStore,
  kSeenTileStore,
  kSeenTileIndexStore,
  kOutboxStore,
  kTrailCacheStore,
];

/// EINE Verbindung je Sitzung, egal wie viele Speicher sie benutzen.
class BrowserDb {
  BrowserDb(this._factory);

  final IdbFactory _factory;
  Database? _db;

  Future<Database> open() async {
    final open = _db;
    if (open != null) return open;
    final db = await _factory.open(kBrowserDbName, version: kBrowserDbVersion, onUpgradeNeeded: _upgrade);
    try {
      // Ein zweiter Tab, der auf eine neue Version hebt, bleibt sonst
      // hängen, solange diese Verbindung offen ist — stumm.
      db.onVersionChange.listen((_) {
        _db = null;
        db.close();
      });
    } catch (_) {
      // Die Speicher-Fassung von idb_shim (im Test) wirft hier „not
      // implemented yet" — die Absicherung ist ein Zusatz, keine Bedingung.
    }
    return _db = db;
  }

  void forget() => _db = null;

  Future<T> readStore<T>(String store, Future<T> Function(ObjectStore) action) =>
      _inStore(store, idbModeReadOnly, action);

  Future<T> writeStore<T>(String store, Future<T> Function(ObjectStore) action) =>
      _inStore(store, idbModeReadWrite, action);

  Future<T> _inStore<T>(String store, String mode, Future<T> Function(ObjectStore) action) async {
    final db = await open();
    final txn = db.transaction(store, mode);
    try {
      final result = await action(txn.objectStore(store));
      await txn.completed;
      return result;
    } catch (e) {
      forget();
      rethrow;
    }
  }

  static void _upgrade(VersionChangeEvent event) {
    final db = event.database;
    for (final store in _stores) {
      if (!db.objectStoreNames.contains(store)) db.createObjectStore(store);
    }
  }
}
