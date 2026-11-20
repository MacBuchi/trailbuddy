// Die Ablage gesehener Host-Dateien auf dem Gerät (#596 H4) — eigene
// Datei, weil `dart:io` im Web nicht kompiliert.
import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'seen_host_files.dart';

SeenHostFiles? createDeviceSeenHostFiles() => DirSeenHostFiles(
  () async =>
      Directory('${(await getApplicationSupportDirectory()).path}/seen_host'),
);

/// Auf Android: eine Datei je Schlüssel in [directory] (Name ist der
/// kodierte Schlüssel, flach — kein Pfad aus dem Netz wird ein Ordner).
/// Die Zeit ist die der Datei; geschrieben wird über `.part` + `rename`.
class DirSeenHostFiles extends IndexedSeenHostFiles {
  DirSeenHostFiles(
    this.directory, {
    super.capBytes = kSeenHostFilesBytes,
    super.now,
  });

  final Future<Directory> Function() directory;
  Directory? _dir;

  Future<Directory> _open() async {
    final d = _dir ??= await directory();
    if (!d.existsSync()) await d.create(recursive: true);
    return d;
  }

  File _file(Directory d, String key) =>
      File('${d.path}/${Uri.encodeComponent(key)}');

  @override
  Future<Map<String, SeenHostEntry>> loadIndex() async {
    final d = await _open();
    final index = <String, SeenHostEntry>{};
    await for (final f in d.list()) {
      if (f is! File) continue;
      final name = f.uri.pathSegments.last;
      if (name.endsWith('.part')) {
        unawaited(f.delete().then((_) {}, onError: (Object _) {}));
        continue;
      }
      final stat = await f.stat();
      index[Uri.decodeComponent(name)] = SeenHostEntry(
        stat.size,
        stat.modified.millisecondsSinceEpoch,
      );
    }
    return index;
  }

  @override
  Future<String?> readText(String key) async {
    final f = _file(await _open(), key);
    if (!f.existsSync()) return null;
    return f.readAsString();
  }

  @override
  Future<void> writeText(String key, String text, int at) async {
    final f = _file(await _open(), key);
    final part = File('${f.path}.part');
    await part.writeAsString(text, flush: true);
    await part.setLastModified(DateTime.fromMillisecondsSinceEpoch(at));
    await part.rename(f.path);
  }

  @override
  Future<void> deleteKeys(List<String> keys) async {
    final d = await _open();
    for (final k in keys) {
      try {
        await _file(d, k).delete();
      } catch (_) {
        // schon weg
      }
    }
  }
}
