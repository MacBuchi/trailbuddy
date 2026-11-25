import 'package:flutter/services.dart';

import 'tombstone.dart';
import '../core/platform_support.dart';

/// Der Kanal zu `MainActivity.kt`; `test/android_manifest_test.dart` hält
/// beide Seiten zusammen — ein Tippfehler antwortet stumm mit „kein Kanal".
const kExitInfoChannel = 'de.mcbuchi.trailbuddy/exit_info';

/// Ein Eintrag aus Androids Beendigungs-Historie.
class AppExit {
  const AppExit({
    required this.timestamp,
    required this.reason,
    this.description,
    this.rssKb = 0,
    this.pssKb = 0,
    this.importance = 0,
    this.hasTrace = false,
  });

  /// Wann der Prozess starb.
  final DateTime timestamp;

  /// `ANR`, `CRASH`, `CRASH_NATIVE`, `LOW_MEMORY`, `USER_REQUESTED` …
  final String reason;

  final String? description;
  final int rssKb;
  final int pssKb;
  final int importance;

  /// Liegt zu diesem Eintrag ein Dump bereit? Beim ANR ein Text, beim
  /// nativen Absturz ab API 31 ein Tombstone (#394).
  final bool hasTrace;

  /// Ein normales Beenden ist kein Fehler und gehört nicht gemeldet —
  /// sonst füllt jedes Wegwischen aus der Übersicht den Wochendigest
  /// (dieselbe Lehre wie #124/#136).
  bool get isFailure => const {
    'ANR',
    'CRASH',
    'CRASH_NATIVE',
    'LOW_MEMORY',
    'EXCESSIVE_RESOURCE_USAGE',
    'INITIALIZATION_FAILURE',
  }.contains(reason);

  /// Was im Bericht steht: RSS ist der wichtigste Wert — bei #142 zeigten
  /// 1,7–1,9 GB die Ursache, bevor irgendein Stacktrace gelesen war.
  ///
  /// Eine 0 heißt bei Android NICHT „hat keinen Speicher gebraucht", sondern
  /// „wurde nicht gemessen": Stirbt der Prozess, bevor das System eine
  /// Stichprobe genommen hat, bleiben beide Werte leer (Doku zu `getRss()`
  /// und `getPss()`). Als „0 MB" gedruckt liest sich das wie eine Messung —
  /// in #151 stand genau das im Bericht, während `dumpsys` 1,7–1,9 GB
  /// zeigte, und der Speicher schied als Ursache aus, ohne je gemessen
  /// worden zu sein.
  String get summary {
    final parts = <String>[
      if (description != null && description!.isNotEmpty) description!,
      'RSS ${_megabytes(rssKb)}',
      'PSS ${_megabytes(pssKb)}',
      'importance $importance',
    ];
    return parts.join(' · ');
  }

  static String _megabytes(int kb) =>
      kb > 0 ? '${(kb / 1024).round()} MB' : 'unbekannt';

  static AppExit? fromMap(Map<Object?, Object?> map) {
    final timestamp = map['timestamp'];
    final reason = map['reasonName'];
    if (timestamp is! int || reason is! String) return null;
    return AppExit(
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
      reason: reason,
      description: map['description'] as String?,
      rssKb: (map['rssKb'] as int?) ?? 0,
      pssKb: (map['pssKb'] as int?) ?? 0,
      importance: (map['importance'] as int?) ?? 0,
      hasTrace: map['hasTrace'] == true,
    );
  }
}

/// Warum die App beim letzten Mal beendet wurde (#40, PilzBuddy #147).
///
/// Android führt diese Liste selbst; eine App darf ihre eigenen Einträge ab
/// Version 11 ohne Berechtigung lesen. Das ist die einzige Quelle, die auch
/// ANRs und Abstürze erfasst — `error_reports` sieht nur, was die App
/// überlebt, und Android Vitals gibt es erst mit Play und nur dort.
///
/// Auf Web und älteren Androids liefert das schlicht nichts; der Aufrufer
/// merkt keinen Unterschied.
class ExitInfoRepository {
  ExitInfoRepository({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(kExitInfoChannel);

  final MethodChannel _channel;

  bool get _supported =>
      isAndroidApp;

  /// Die letzten Beendigungen, neueste zuerst.
  Future<List<AppExit>> recentExits({int limit = 10}) async {
    if (!_supported) return const [];
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('exitReasons', {
        'limit': limit,
      });
      return (raw ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map(AppExit.fromMap)
          .whereType<AppExit>()
          .toList();
    } catch (_) {
      // Diagnose darf den Start nie gefährden: Fehlt der Kanal (alter
      // Build, anderes Gerät), ist die Liste eben leer.
      return const [];
    }
  }

  /// Der Dump zum Eintrag, oder null.
  ///
  /// Zwei Sorten, eine Rückgabe: Beim ANR liefert Android Text, beim
  /// nativen Absturz seit API 31 ein Tombstone als Protobuf (#394). Das
  /// kommt roh über den Kanal und wird HIER gelesen — die native Seite
  /// hat keinen Test, `formatTombstone` sehr wohl.
  Future<String?> traceFor(AppExit exit) async {
    if (!_supported || !exit.hasTrace) return null;
    try {
      final raw = await _channel.invokeMethod<Object?>('exitTrace', {
        'timestamp': exit.timestamp.millisecondsSinceEpoch,
      });
      return switch (raw) {
        final String text => text,
        final Uint8List bytes => formatTombstone(bytes),
        // Ein alter Build auf einem neuen Gerät (oder umgekehrt) kann
        // etwas Drittes schicken. Kein Grund für einen Fehler — der
        // Eintrag selbst ist schon die halbe Antwort.
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }
}
