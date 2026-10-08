// Die Ablage gespeicherter Bereiche als Dateien (Android): Index
// `areas.json`, je Bereich `<id>.pmtiles` (geschrieben über `.part` +
// rename), `<id>.heights.pmtiles` für die Höhenkacheln,
// `<id>.ways.pmtiles` für die Wege und
// `<id>/pois/<datei>` für die Orte-Zellen. Unter
// `offline_maps/areas/` im App-Verzeichnis, also vom Backup ausgenommen.
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

  Future<File> _poi(String id, String name) async => File('${(await _dir()).path}/$id/pois/$name');

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
  Future<void> deleteHeights(String id) async => _remove(await _heights(id));

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
  Future<void> deleteWays(String id) async => _remove(await _ways(id));

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
  Future<void> putPoiFile(String id, String name, String text) async {
    final file = await _poi(id, name);
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  @override
  Future<String?> readPoiFile(String name) async {
    for (final area in await list()) {
      if (!area.poiFiles.contains(name)) continue;
      final file = await _poi(area.id, name);
      if (await file.exists()) return file.readAsString();
    }
    return null;
  }

  @override
  Future<void> delete(String id) async {
    final areas = await list();
    await saveIndex([for (final a in areas) if (a.id != id) a]);
    await _remove(await _archive(id));
    await _remove(await _heights(id));
    await _remove(await _ways(id));
    final poiDir = Directory('${(await _dir()).path}/$id');
    if (await poiDir.exists()) await poiDir.delete(recursive: true);
  }
}

AreaStore createAreaStore() => FileAreaStore();
