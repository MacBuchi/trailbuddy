// Die Ablage gespeicherter Bereiche als Dateien (Android): Index
// `areas.json`, die Orte-Dateien je Name einmal unter `pois/<datei>`, dazu
// je Region `overview-<region>.pmtiles` mit dem Index `overviews.json`.
// Der Altbestand bis 0.105.x: je Bereich `<id>.pmtiles`,
// `<id>.heights.pmtiles`, `<id>.ways.pmtiles` und `<id>/pois/<datei>`.
// Unter `offline_maps/areas/` im App-Verzeichnis, also vom Backup
// ausgenommen; die Kacheln liegen seit 0.106.0 nebenan im Kachelspeicher
// (`tile_store_io.dart`, `offline_maps/store/`).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'area_store.dart';

class FileAreaStore implements AreaStore {
  FileAreaStore({Directory? baseDir}) : _baseDir = baseDir;

  Directory? _baseDir;

  Future<Directory> _dir() async {
    final cached = _baseDir;
    if (cached != null) return cached;
    final support = await getApplicationSupportDirectory();
    return _baseDir = Directory('${support.path}/offline_maps/areas');
  }

  Future<File> _index() async => File('${(await _dir()).path}/areas.json');

  Future<File> _archive(String id) async => File('${(await _dir()).path}/$id.pmtiles');

  Future<File> _heights(String id) async => File('${(await _dir()).path}/$id.heights.pmtiles');

  Future<File> _ways(String id) async => File('${(await _dir()).path}/$id.ways.pmtiles');

  Future<File> _overviewIndex() async => File('${(await _dir()).path}/overviews.json');

  Future<File> _overview(String region) async => File('${(await _dir()).path}/overview-$region.pmtiles');

  Future<File> _legacyPoi(String id, String name) async => File('${(await _dir()).path}/$id/pois/$name');

  Future<File> _poi(String name) async {
    // Der Name wird Teil eines Pfads.
    if (name.contains('/') || name.startsWith('.')) throw ArgumentError.value(name, 'name');
    return File('${(await _dir()).path}/pois/$name');
  }

  @override
  Future<List<StoredArea>> list() async {
    final file = await _index();
    if (!await file.exists()) return const [];
    try {
      final json = jsonDecode(await file.readAsString()) as List;
      return [for (final j in json) StoredArea.fromJson(j as Map<String, dynamic>)];
    } catch (_) {
      // Ein unlesbarer Index heißt keine Bereiche, nicht Absturz: Die
      // Archive liegen weiter da, der nächste gespeicherte Bereich
      // schreibt den Index neu.
      return const [];
    }
  }

  @override
  Future<void> saveIndex(List<StoredArea> areas) async {
    final file = await _index();
    await file.parent.create(recursive: true);
    final part = File('${file.path}.part');
    await part.writeAsString(jsonEncode([for (final a in areas) a.toJson()]));
    await part.rename(file.path);
  }

  @override
  Future<void> putArchive(String id, Uint8List bytes) => _write(_archive(id), bytes);

  Future<void> _write(Future<File> target, Uint8List bytes) async {
    final file = await target;
    await file.parent.create(recursive: true);
    // `.part` + rename: Ein Prozess-Kill mitten im Schreiben hinterlässt
    // kein halbes Archiv unter dem echten Namen.
    final part = File('${file.path}.part');
    await part.writeAsBytes(bytes, flush: true);
    await part.rename(file.path);
  }

  Future<void> _remove(File file) async {
    if (await file.exists()) await file.delete();
    final part = File('${file.path}.part');
    if (await part.exists()) await part.delete();
  }

  @override
  Future<void> putHeights(String id, Uint8List bytes) => _write(_heights(id), bytes);

  @override
  Future<String?> heightsPath(String id) async {
    final file = await _heights(id);
    return await file.exists() ? file.path : null;
  }

  @override
  Future<Uint8List?> readHeights(String id) async {
    final file = await _heights(id);
    return await file.exists() ? await file.readAsBytes() : null;
  }

  @override
  Future<void> putWays(String id, Uint8List bytes) => _write(_ways(id), bytes);

  @override
  Future<String?> waysPath(String id) async {
    final file = await _ways(id);
    return await file.exists() ? file.path : null;
  }

  @override
  Future<Uint8List?> readWays(String id) async {
    final file = await _ways(id);
    return await file.exists() ? await file.readAsBytes() : null;
  }

  @override
  Future<String?> archivePath(String id) async {
    final file = await _archive(id);
    return await file.exists() ? file.path : null;
  }

  @override
  Future<Uint8List?> readArchive(String id) async {
    final file = await _archive(id);
    return await file.exists() ? await file.readAsBytes() : null;
  }

  @override
  Future<void> putPoiFile(String name, String text) async {
    final file = await _poi(name);
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  @override
  Future<String?> readPoiFile(String name) async {
    final file = await _poi(name);
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> deletePoiFiles(Iterable<String> names) async {
    for (final n in names) {
      await _remove(await _poi(n));
    }
  }

  @override
  Future<void> putLegacyPoiFile(String id, String name, String text) async {
    final file = await _legacyPoi(id, name);
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  @override
  Future<String?> readLegacyPoiFile(String id, String name) async {
    final file = await _legacyPoi(id, name);
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> delete(String id) async {
    final areas = await list();
    await saveIndex([for (final a in areas) if (a.id != id) a]);
    await deleteLegacy(id);
  }

  @override
  Future<void> deleteLegacy(String id) async {
    await _remove(await _archive(id));
    await _remove(await _heights(id));
    await _remove(await _ways(id));
    final poiDir = Directory('${(await _dir()).path}/$id');
    if (await poiDir.exists()) await poiDir.delete(recursive: true);
  }

  @override
  Future<List<StoredOverview>> overviews() async {
    final file = await _overviewIndex();
    if (!await file.exists()) return const [];
    try {
      final json = jsonDecode(await file.readAsString()) as List;
      return [for (final j in json) StoredOverview.fromJson(j as Map<String, dynamic>)];
    } catch (_) {
      // Wie beim Index der Bereiche: unlesbar heißt keine, nicht Absturz.
      return const [];
    }
  }

  Future<void> _saveOverviews(List<StoredOverview> all) async {
    final file = await _overviewIndex();
    await file.parent.create(recursive: true);
    final part = File('${file.path}.part');
    await part.writeAsString(jsonEncode([for (final o in all) o.toJson()]));
    await part.rename(file.path);
  }

  @override
  Future<void> putOverview(StoredOverview overview, Uint8List bytes) async {
    await _write(_overview(overview.region), bytes);
    await _saveOverviews(replaceOverview(await overviews(), overview.region, overview));
  }

  @override
  Future<String?> overviewPath(String region) async {
    final file = await _overview(region);
    return await file.exists() ? file.path : null;
  }

  @override
  Future<Uint8List?> readOverview(String region) async {
    final file = await _overview(region);
    return await file.exists() ? await file.readAsBytes() : null;
  }

  @override
  Future<void> deleteOverview(String region) async {
    await _saveOverviews(replaceOverview(await overviews(), region));
    await _remove(await _overview(region));
  }
}

AreaStore createAreaStore() => FileAreaStore();
