// Gesehenes auch für kleine Dateien (#596 H4, `docs/konzept-traffic.md`):
// Orte-Zellen, Namensdateien der Suche und Orte-Manifeste, die einmal vom
// Kartenhost kamen, bleiben auf dem Gerät liegen — Android als Dateien
// im App-Verzeichnis, im Browser in IndexedDB. Gedeckelt bei
// [kSeenHostFilesBytes], die älteste geht zuerst.
//
// Der Schlüssel ist der Pfad unter dem Host. Gebaute Dateien tragen den
// Bau im Pfad (`pois-<bau>/…`) und ändern sich nie — eine liegende ist
// nie veraltet. Ein Manifest hat keinen Bau im Pfad; wer es liest, gibt
// das Alter mit, das er noch annimmt ([kHostManifestMaxAge]).
import 'dart:async';
import 'dart:convert';

import 'package:idb_shim/idb_shim.dart';

import 'browser_db.dart';
import 'seen_host_files_web.dart'
    if (dart.library.io) 'seen_host_files_io.dart';

/// So viel dürfen die kleinen Dateien belegen. Eine Orte-Zelle hat ein
/// paar kB, eine Namensdatei bis ~1 MB, das Manifest 465 kB (2026-11-20).
const kSeenHostFilesBytes = 20 * 1024 * 1024;

/// So alt darf ein gemerktes Manifest sein, bevor die App den Host
/// wieder fragt — einmal am Tag (Konzept-Traffic H4). Ohne Netz gilt
/// auch ein älteres.
const kHostManifestMaxAge = Duration(hours: 24);

/// Geräumt wird bis auf diesen Anteil der Grenze.
const kSeenHostFilesEvictTo = 0.9;

/// Eine gemerkte Datei und wann sie vom Host kam.
typedef SeenHostFile = ({String text, DateTime at});

abstract class SeenHostFiles {
  /// Null: liegt nicht (oder der Speicher geht nicht auf). Wirft nie.
  Future<SeenHostFile?> read(String key);

  /// Wirft nie — ein Speicher, der nicht schreibt, kostet nur eine
  /// Anfrage beim nächsten Mal.
  Future<void> write(String key, String text);
}

/// Liest [key] aus [seen], wenn er nicht älter als [maxAge] ist (null:
/// jedes Alter).
Future<String?> readSeen(
  SeenHostFiles? seen,
  String key, {
  Duration? maxAge,
  DateTime Function() now = DateTime.now,
}) async {
  final file = await seen?.read(key);
  if (file == null) return null;
  if (maxAge != null && now().difference(file.at) > maxAge) return null;
  return file.text;
}

/// Ein Eintrag des Index: Größe und Zeit des Ablegens.
class SeenHostEntry {
  SeenHostEntry(this.bytes, this.at);
  final int bytes;
  final int at;
}

/// Index im Speicher, Räumen nach Alter — gemeinsam für alle Ablagen.
/// Die Ablage liefert nur Lesen, Schreiben, Löschen und den Index.
abstract class IndexedSeenHostFiles implements SeenHostFiles {
  IndexedSeenHostFiles({required this.capBytes, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final int capBytes;
  final DateTime Function() _now;

  Future<Map<String, SeenHostEntry>?>? _index;
  int _total = 0;

  /// Für Tests: so viele Bytes führt der Index.
  int get totalBytes => _total;

  Future<Map<String, SeenHostEntry>> loadIndex();
  Future<String?> readText(String key);
  Future<void> writeText(String key, String text, int at);
  Future<void> deleteKeys(List<String> keys);

  Future<Map<String, SeenHostEntry>?> _loaded() => _index ??= () async {
    try {
      final index = await loadIndex();
      _total = index.values.fold(0, (sum, e) => sum + e.bytes);
      return index;
    } catch (_) {
      // Kein Speicher (privater Modus, kein Verzeichnis): Die App fragt
      // wie vor #596 den Host — still, für diese Sitzung.
      return null;
    }
  }();

  @override
  Future<SeenHostFile?> read(String key) async {
    final index = await _loaded();
    final entry = index?[key];
    if (entry == null) return null;
    try {
      final text = await readText(key);
      if (text == null) {
        index!.remove(key);
        _total -= entry.bytes;
        return null;
      }
      return (text: text, at: DateTime.fromMillisecondsSinceEpoch(entry.at));
    } catch (_) {
      return null; // eine fehlende Datei, kein Fehlerbericht
    }
  }

  @override
  Future<void> write(String key, String text) async {
    final index = await _loaded();
    if (index == null) return;
    try {
      final at = _now().millisecondsSinceEpoch;
      final bytes = utf8.encode(text).length;
      await writeText(key, text, at);
      final before = index.remove(key);
      if (before != null) _total -= before.bytes;
      index[key] = SeenHostEntry(bytes, at);
      _total += bytes;
      if (_total > capBytes) await _evict(index);
    } catch (_) {
      // Voll oder geräumt: eine Anfrage mehr beim nächsten Mal.
    }
  }

  Future<void> _evict(Map<String, SeenHostEntry> index) async {
    final oldest = index.entries.toList()
      ..sort((a, b) => a.value.at.compareTo(b.value.at));
    final target = (capBytes * kSeenHostFilesEvictTo).floor();
    final gone = <String>[];
    for (final e in oldest) {
      if (_total <= target) break;
      gone.add(e.key);
      _total -= e.value.bytes;
      index.remove(e.key);
    }
    await deleteKeys(gone);
  }
}

/// Im Speicher — für Tests und als Ablage ohne Gerät.
class MemorySeenHostFiles extends IndexedSeenHostFiles {
  MemorySeenHostFiles({super.capBytes = kSeenHostFilesBytes, super.now});

  final texts = <String, String>{};

  @override
  Future<Map<String, SeenHostEntry>> loadIndex() async => {};

  @override
  Future<String?> readText(String key) async => texts[key];

  @override
  Future<void> writeText(String key, String text, int at) async =>
      texts[key] = text;

  @override
  Future<void> deleteKeys(List<String> keys) async {
    for (final k in keys) {
      texts.remove(k);
    }
  }
}

/// Im Browser: IndexedDB, der Index (`Bytes|Zeit`) neben den Texten.
class IdbSeenHostFiles extends IndexedSeenHostFiles {
  IdbSeenHostFiles(
    IdbFactory factory, {
    super.capBytes = kSeenHostFilesBytes,
    super.now,
  }) : _db = BrowserDb(factory);

  final BrowserDb _db;

  @override
  Future<Map<String, SeenHostEntry>> loadIndex() async {
    final (keys, values) = await _db.readStore(
      kSeenHostFileIndexStore,
      (s) async => (await s.getAllKeys(), await s.getAll()),
    );
    final index = <String, SeenHostEntry>{};
    for (var i = 0; i < keys.length && i < values.length; i++) {
      final v = values[i];
      if (v is! String) continue;
      final parts = v.split('|');
      if (parts.length != 2) continue;
      final n = int.tryParse(parts[0]), at = int.tryParse(parts[1]);
      if (n != null && at != null) index['${keys[i]}'] = SeenHostEntry(n, at);
    }
    return index;
  }

  @override
  Future<String?> readText(String key) async {
    final v = await _db.readStore(kSeenHostFileStore, (s) => s.getObject(key));
    return v is String ? v : null;
  }

  @override
  Future<void> writeText(String key, String text, int at) => _db.writeStores(
    [kSeenHostFileStore, kSeenHostFileIndexStore],
    (txn) async {
      await txn.objectStore(kSeenHostFileStore).put(text, key);
      await txn
          .objectStore(kSeenHostFileIndexStore)
          .put('${utf8.encode(text).length}|$at', key);
    },
  );

  @override
  Future<void> deleteKeys(List<String> keys) => _db.writeStores(
    [kSeenHostFileStore, kSeenHostFileIndexStore],
    (txn) async {
      for (final k in keys) {
        await txn.objectStore(kSeenHostFileStore).delete(k);
        await txn.objectStore(kSeenHostFileIndexStore).delete(k);
      }
    },
  );
}

/// Die Ablage der Plattform: Browser IndexedDB (ohne sie: keine),
/// sonst ein Ordner im App-Verzeichnis. Prüfbar, weil `kIsWeb` im Test
/// immer falsch ist.
SeenHostFiles? chooseSeenHostFiles({required bool web, IdbFactory? factory}) {
  if (web) return factory == null ? null : IdbSeenHostFiles(factory);
  return createDeviceSeenHostFiles();
}
