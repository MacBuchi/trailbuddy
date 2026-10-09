// Die Ablage gespeicherter Bereiche im Browser: IndexedDB über
// `idb_shim`. Ein Archiv liegt als EIN Bytes-Eintrag, gelesen mit
// `PmTilesArchive.fromBytes` (im Browser gibt es keine faule Datei; ein
// Bereich von einigen Dutzend MB liegt dann im Speicher — der Preis der
// Plattform, PilzBuddy 1.114.2). Der Browser darf seinen Speicher räumen;
// beim ersten Speichern eines Bereichs bittet die Oberfläche einmal um
// `navigator.storage.persist()` (Konzept 3.2).
import 'dart:convert';
import 'dart:typed_data';

import 'package:idb_shim/idb_shim.dart';

import '../../data/browser_db.dart';
import 'area_store.dart';

class IdbAreaStore implements AreaStore {
  IdbAreaStore(IdbFactory factory) : _db = BrowserDb(factory);

  final BrowserDb _db;

  static const _indexKey = 'areas';

  // Die Übersichten der Regionen (seit 0.105.0): ihr Index im selben
  // Speicher wie der der Bereiche, die Bytes bei den Archiven — kein neuer
  // Speicher, keine neue DB-Version. Kein Bereich heißt so: Deren Ids
  // tragen keinen Schrägstrich.
  static const _overviewIndexKey = 'overviews';
  static String _overviewKey(String region) => 'overview/$region';

  @override
  Future<List<StoredArea>> list() async {
    try {
      final text = await _db.readStore(kAreaIndexStore, (s) => s.getObject(_indexKey));
      if (text is! String) return const [];
      return [for (final j in jsonDecode(text) as List) StoredArea.fromJson(j as Map<String, dynamic>)];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> saveIndex(List<StoredArea> areas) => _db.writeStore(kAreaIndexStore,
      (s) => s.put(jsonEncode([for (final a in areas) a.toJson()]), _indexKey));

  @override
  Future<void> putArchive(String id, Uint8List bytes) =>
      _db.writeStore(kAreaArchiveStore, (s) => s.put(bytes, id));

  @override
  Future<String?> archivePath(String id) async => null;

  @override
  Future<Uint8List?> readArchive(String id) async {
    final value = await _db.readStore(kAreaArchiveStore, (s) => s.getObject(id));
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    return null;
  }

  // Die Höhen liegen im selben Speicher wie die Archive, unter einem
  // eigenen Schlüssel — kein neuer Speicher, keine neue DB-Version.
  static String _heightsKey(String id) => '$id/heights';

  @override
  Future<void> putHeights(String id, Uint8List bytes) =>
      _db.writeStore(kAreaArchiveStore, (s) => s.put(bytes, _heightsKey(id)));

  @override
  Future<String?> heightsPath(String id) async => null;

  @override
  Future<Uint8List?> readHeights(String id) async {
    final value = await _db.readStore(kAreaArchiveStore, (s) => s.getObject(_heightsKey(id)));
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    return null;
  }

  @override
  Future<void> deleteHeights(String id) =>
      _db.writeStore(kAreaArchiveStore, (s) => s.delete(_heightsKey(id)));

  // Die Wege ebenso (seit 0.90.0, #212).
  static String _waysKey(String id) => '$id/ways';

  @override
  Future<void> putWays(String id, Uint8List bytes) =>
      _db.writeStore(kAreaArchiveStore, (s) => s.put(bytes, _waysKey(id)));

  @override
  Future<String?> waysPath(String id) async => null;

  @override
  Future<Uint8List?> readWays(String id) async {
    final value = await _db.readStore(kAreaArchiveStore, (s) => s.getObject(_waysKey(id)));
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    return null;
  }

  @override
  Future<void> deleteWays(String id) =>
      _db.writeStore(kAreaArchiveStore, (s) => s.delete(_waysKey(id)));

  @override
  Future<void> putPoiFile(String id, String name, String text) =>
      _db.writeStore(kAreaPoiStore, (s) => s.put(text, '$id/$name'));

  @override
  Future<String?> readPoiFile(String name) async {
    for (final area in await list()) {
      if (!area.poiFiles.contains(name)) continue;
      final value = await _db.readStore(kAreaPoiStore, (s) => s.getObject('${area.id}/$name'));
      if (value is String) return value;
    }
    return null;
  }

  @override
  Future<void> delete(String id) async {
    final areas = await list();
    final gone = areas.where((a) => a.id == id).toList();
    await saveIndex([for (final a in areas) if (a.id != id) a]);
    await _db.writeStore(kAreaArchiveStore, (s) => s.delete(id));
    await _db.writeStore(kAreaArchiveStore, (s) => s.delete(_heightsKey(id)));
    await _db.writeStore(kAreaArchiveStore, (s) => s.delete(_waysKey(id)));
    for (final area in gone) {
      for (final name in area.poiFiles) {
        await _db.writeStore(kAreaPoiStore, (s) => s.delete('${area.id}/$name'));
      }
    }
  }

  @override
  Future<List<StoredOverview>> overviews() async {
    try {
      final text = await _db.readStore(kAreaIndexStore, (s) => s.getObject(_overviewIndexKey));
      if (text is! String) return const [];
      return [for (final j in jsonDecode(text) as List) StoredOverview.fromJson(j as Map<String, dynamic>)];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveOverviews(List<StoredOverview> all) => _db.writeStore(
      kAreaIndexStore, (s) => s.put(jsonEncode([for (final o in all) o.toJson()]), _overviewIndexKey));

  @override
  Future<void> putOverview(StoredOverview overview, Uint8List bytes) async {
    await _db.writeStore(kAreaArchiveStore, (s) => s.put(bytes, _overviewKey(overview.region)));
    await _saveOverviews(replaceOverview(await overviews(), overview.region, overview));
  }

  @override
  Future<String?> overviewPath(String region) async => null;

  @override
  Future<Uint8List?> readOverview(String region) async {
    final value = await _db.readStore(kAreaArchiveStore, (s) => s.getObject(_overviewKey(region)));
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    return null;
  }

  @override
  Future<void> deleteOverview(String region) async {
    await _saveOverviews(replaceOverview(await overviews(), region));
    await _db.writeStore(kAreaArchiveStore, (s) => s.delete(_overviewKey(region)));
  }
}
