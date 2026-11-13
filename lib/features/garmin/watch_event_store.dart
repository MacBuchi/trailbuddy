// Die Ablage der Uhr-Protokolle (#510): Die letzten [kWatchEventLogsKept]
// liegen auf dem Telefon neben den Fahrten (`rides/watch_events.json` —
// derselbe Ordner, dieselben Backup-Ausschlüsse), nie auf dem Server. Sie
// verlassen das Telefon nur, wenn der Nutzer eins an eine Fehlermeldung
// hängt (Feedback-Dialog).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../rides/ride_store.dart' show FileRideStore;
import 'watch_events.dart';

/// So viele Protokolle bleiben, die neuesten.
const kWatchEventLogsKept = 5;

abstract class WatchEventStore {
  /// Legt [log] ab; das älteste über [kWatchEventLogsKept] fällt weg.
  /// Dasselbe Protokoll zweimal (ein „hallo" kam doppelt) bleibt eins.
  /// Wirft nie.
  Future<void> add(WatchEventLog log);

  /// Das neueste, oder null. Wirft nie.
  Future<WatchEventLog?> latest();
}

class FileWatchEventStore implements WatchEventStore {
  FileWatchEventStore({Directory? baseDir}) : _baseDirOverride = baseDir;

  final Directory? _baseDirOverride;
  static const fileName = 'watch_events.json';
  Future<void> _lock = Future.value();

  Future<File> _file() async {
    final base = _baseDirOverride ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/${FileRideStore.dirName}');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$fileName');
  }

  Future<List<WatchEventLog>> _read() async {
    final f = await _file();
    if (!await f.exists()) return [];
    final raw = jsonDecode(await f.readAsString());
    if (raw is! List) return [];
    return [for (final j in raw) ?WatchEventLog.fromJson(j)];
  }

  @override
  Future<void> add(WatchEventLog log) {
    if (kIsWeb) return Future.value();
    final done = _lock.then((_) async {
      try {
        final logs = await _read();
        if (logs.any((l) => listEquals(l.events, log.events))) return;
        logs.add(log);
        logs.sort((a, b) => a.at.compareTo(b.at));
        while (logs.length > kWatchEventLogsKept) {
          logs.removeAt(0);
        }
        final f = await _file();
        final tmp = File('${f.path}.part');
        await tmp.writeAsString(jsonEncode([for (final l in logs) l.toJson()]), flush: true);
        await tmp.rename(f.path);
      } catch (_) {
        // Ein Protokoll ist Beiwerk: Ohne Platte gibt es eben keins.
      }
    });
    _lock = done;
    return done;
  }

  @override
  Future<WatchEventLog?> latest() async {
    if (kIsWeb) return null;
    try {
      await _lock;
      final logs = await _read();
      return logs.isEmpty ? null : logs.reduce((a, b) => b.at.isAfter(a.at) ? b : a);
    } catch (_) {
      // Kaputte oder fehlende Datei: dann eben keins.
      return null;
    }
  }
}

/// Für Tests und das Web: nur im Speicher.
class MemoryWatchEventStore implements WatchEventStore {
  final logs = <WatchEventLog>[];

  @override
  Future<void> add(WatchEventLog log) async {
    if (logs.any((l) => listEquals(l.events, log.events))) return;
    logs.add(log);
    if (logs.length > kWatchEventLogsKept) logs.removeAt(0);
  }

  @override
  Future<WatchEventLog?> latest() async => logs.isEmpty ? null : logs.last;
}

final watchEventStoreProvider = Provider<WatchEventStore>((ref) => FileWatchEventStore());

/// Das neueste Protokoll, wenn es jünger als [kWatchEventsOffer] ist —
/// sonst bietet der Feedback-Dialog nichts an.
final watchEventOfferProvider = FutureProvider.autoDispose<WatchEventLog?>((ref) async {
  final log = await ref.read(watchEventStoreProvider).latest();
  if (log == null || DateTime.now().difference(log.at) > kWatchEventsOffer) return null;
  return log;
});
