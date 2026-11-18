import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/errors.dart';
import 'error_report_repository.dart';
import 'exit_info_repository.dart';

/// Meldet nachträglich, warum die App beim letzten Mal beendet wurde
/// (#40, PilzBuddy #147).
///
/// Der Ablauf: beim Start Androids Historie lesen, alles überspringen, was
/// schon gemeldet wurde oder kein Fehler war, den Rest nach `error_reports`
/// schreiben und den neuesten Zeitpunkt merken.
///
/// Warum eine Datei und keine Datenbank für den Merker: `path_provider`
/// nutzt die App ohnehin (Offline-Karten), eine Zeile mit einer Zahl braucht
/// nichts weiter, und ein verlorener Merker kostet höchstens eine doppelte
/// Meldung — kein Grund für eine neue Abhängigkeit.
class ExitReporter {
  ExitReporter({
    required ExitInfoRepository exits,
    required ErrorReportRepository reports,
    Future<Directory> Function()? directory,
  }) : _exits = exits,
       _reports = reports,
       _directory = directory ?? getApplicationSupportDirectory;

  final ExitInfoRepository _exits;
  final ErrorReportRepository _reports;
  final Future<Directory> Function() _directory;

  static const _markerName = 'last_exit_report';

  /// Einmal beim Start aufrufen. Wirft nie: Eine Diagnose, die den Start
  /// gefährdet, ist schlimmer als gar keine.
  Future<void> reportPending() async {
    try {
      final exits = await _exits.recentExits();
      if (exits.isEmpty) return;

      final since = await _lastReported();
      // Älteste zuerst, damit der Merker am Ende auf dem Neuesten steht,
      // selbst wenn eine Meldung dazwischen scheitert.
      final pending =
          exits.where((e) => e.isFailure && e.timestamp.isAfter(since)).toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      for (final exit in pending) {
        await _reports.reportExit(
          reason: exit.reason,
          summary: exit.summary,
          when: exit.timestamp,
          trace: await _exits.traceFor(exit),
        );
        await _remember(exit.timestamp);
      }

      // Auch ohne meldbare Einträge den Merker nachziehen: Sonst wird die
      // Historie bei jedem Start erneut durchgesehen.
      if (pending.isEmpty) {
        final newest = exits
            .map((e) => e.timestamp)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        if (newest.isAfter(since)) await _remember(newest);
      }
    } catch (e, stackTrace) {
      // Nur loggen: Der Weg hierher ist Diagnose, kein Kernpfad.
      logError('Beendigungsgrund melden', e, stackTrace);
    }
  }

  Future<DateTime> _lastReported() async {
    try {
      final file = File('${(await _directory()).path}/$_markerName');
      if (!await file.exists()) return DateTime.fromMillisecondsSinceEpoch(0);
      final millis = int.tryParse((await file.readAsString()).trim());
      return DateTime.fromMillisecondsSinceEpoch(millis ?? 0);
    } catch (_) {
      // Ohne Merker lieber doppelt melden als gar nicht.
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  Future<void> _remember(DateTime when) async {
    try {
      final file = File('${(await _directory()).path}/$_markerName');
      await file.writeAsString('${when.millisecondsSinceEpoch}');
    } catch (_) {
      // Siehe oben: eine doppelte Meldung ist der harmlosere Ausgang.
    }
  }
}
