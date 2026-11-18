import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Schreibt gefangene Fehler in `public.error_reports`.
///
/// Android Vitals zeigt nur harte Abstürze auf Play-Installationen. Die
/// Lücke sind die abgefangenen Fehler: die App zeigt eine SnackBar und läuft
/// weiter — ohne diesen Weg erfährt niemand davon.
///
/// Bewusst genügsam: keine Breadcrumbs, keine Nutzerkennung über die
/// user_id hinaus, keine Koordinaten. Was die App über den Nutzer weiß,
/// gehört nicht in einen Fehlerbericht.
class ErrorReportRepository {
  ErrorReportRepository(this._client);

  final SupabaseClient _client;

  /// Gekürzt auf die Längen aus dem Schema. Ein Fehlertext kann in
  /// Ausnahmefällen Nutzdaten enthalten (z. B. eine Server-Meldung mit
  /// Query-Fragment) — die Grenzen halten das klein und die Tabelle schlank.
  static String? _clip(String? value, int max) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length <= max ? trimmed : trimmed.substring(0, max);
  }

  /// Ein Stack, gekürzt auf [max] Zeichen — ohne die eigenen Frames zu
  /// verlieren.
  ///
  /// Abgeschnitten wurde bis 0.74.0 von hinten: Ein tiefer Widget-Baum
  /// füllt die 4 000 Zeichen mit Framework-Frames, und der eine Frame aus
  /// `package:trailbuddy/`, nach dem der Digest sucht, lag dahinter. Jetzt
  /// bleibt der Anfang (wo es geschah), dann eine Zeile, wie viel fehlt,
  /// dann die eigenen Frames aus dem Rest (wie es dazu kam).
  @visibleForTesting
  static String? clipStack(String? stack, int max) {
    final trimmed = _clip(stack, 1 << 30);
    if (trimmed == null || trimmed.length <= max) return trimmed;
    final lines = trimmed.split('\n');
    final head = <String>[];
    var used = 0;
    var i = 0;
    // Gut die Hälfte für den Anfang; der Rest gehört den eigenen Frames.
    while (i < lines.length && used + lines[i].length + 1 <= max * 0.55) {
      head.add(lines[i]);
      used += lines[i].length + 1;
      i++;
    }
    final own = [
      for (final line in lines.skip(i))
        if (line.contains(_appFrame)) line,
    ];
    final marker =
        '… ${lines.length - i} Zeilen gekürzt'
        '${own.isEmpty ? '' : ', eigene davon:'}';
    final out = [...head, marker];
    used += marker.length + 1;
    for (final line in own) {
      if (used + line.length + 1 > max) break;
      out.add(line);
      used += line.length + 1;
    }
    final joined = out.join('\n');
    return joined.length <= max ? joined : joined.substring(0, max);
  }

  static const _appFrame = 'package:trailbuddy/';

  static String get _platform => kIsWeb ? 'web' : defaultTargetPlatform.name;

  Future<void> report(
    String context,
    Object error,
    StackTrace? stackTrace,
  ) async {
    final version = await PackageInfo.fromPlatform()
        .then<String?>((info) => info.version)
        // Version ist nice-to-have; ohne sie ist der Bericht immer noch
        // wertvoll, deshalb hier schlucken statt den Bericht fallen zu
        // lassen.
        .catchError((Object _) => null);

    await _client.from('error_reports').insert({
      'user_id': _client.auth.currentUser?.id,
      'context': _clip(context, 100),
      'error_type': error.runtimeType.toString(),
      'message': _clip(error.toString(), 1000),
      'stack': clipStack(stackTrace?.toString(), 4000),
      'app_version': version,
      'platform': _platform,
    });
  }

  /// Ein Beendigungsgrund aus Androids Historie (#40): Kontext `App-Ende`,
  /// der Grund als Typ, Speicherwerte als Meldung, der Thread-Dump bzw.
  /// das gelesene Tombstone als Stack. `created_at` ist der TODESzeitpunkt,
  /// nicht der Meldezeitpunkt — sonst landet ein Absturz von Freitagnacht
  /// im Digest der Folgewoche.
  Future<void> reportExit({
    required String reason,
    required String summary,
    required DateTime when,
    String? trace,
  }) async {
    final version = await PackageInfo.fromPlatform()
        .then<String?>((info) => info.version)
        .catchError((Object _) => null);

    await _client.from('error_reports').insert({
      'user_id': _client.auth.currentUser?.id,
      'context': 'App-Ende',
      'error_type': _clip(reason, 100),
      'message': _clip(summary, 1000),
      'stack': _clip(trace, 4000),
      'app_version': version,
      'platform': _platform,
      'created_at': when.toUtc().toIso8601String(),
    });
  }
}
