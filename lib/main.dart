import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/app_theme.dart';
import 'core/errors.dart';
import 'core/settings.dart';
import 'core/stall_watch.dart';
import 'core/supabase_config.dart';
import 'data/error_report_repository.dart';
import 'data/exit_info_repository.dart';
import 'data/exit_reporting.dart';
import 'features/rides/ride_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Nur mit --dart-define=STALL_WATCH=true (Dev-App, #356): misst Hänger.
  StallWatch.start();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  final reports = ErrorReportRepository(Supabase.instance.client);
  // Absichtlich ohne await: das Melden darf den Programmfluss weder
  // aufhalten noch scheitern lassen. Fehler beim Melden werden geschluckt —
  // sie hier zu loggen wäre eine Endlosschleife.
  //
  // Im Web nur, wenn die App NICHT von der eigenen Maschine kommt
  // ([reportsFromHost]) — sonst schreiben Testläufe in die echte Tabelle.
  if (!kIsWeb || reportsFromHost(Uri.base.host)) {
    setErrorSink((context, error, stackTrace) {
      reports.report(context, error, stackTrace).catchError((Object _) {});
    });
  }

  // Warum die App beim letzten Mal beendet wurde (#40): ANR, Absturz,
  // Speichermangel aus Androids eigener Historie, nachträglich gemeldet.
  // Ohne await und ohne Wirkung auf den Start; auf Web und Android < 11
  // liefert die Historie nichts. Dieselbe Bedingung wie der Sink oben —
  // ein Testlauf von der eigenen Maschine schreibt nichts.
  if (!kIsWeb || reportsFromHost(Uri.base.host)) {
    unawaited(ExitReporter(exits: ExitInfoRepository(), reports: reports).reportPending());
  }

  // Auch nicht gefangene Fehler melden. Android Vitals sieht davon nur die
  // Play-Installationen; Web und die GitHub-APK bleiben sonst blind.
  //
  // `worthReporting` siebt vorher aus, was hier regelmäßig landet, ohne dass
  // etwas kaputt ist (Abfragen nach dem Abmelden, fehlender Empfang) — dann
  // auch nicht ins Log: Bei Hunderten Fällen pro Woche wäre es dort genauso
  // Rauschen wie in der Datenbank. Nur diese globalen Handler filtern; ein
  // `logError` mit eigenem Kontext meldet weiterhin alles.
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    previousOnError?.call(details);
    if (worthReporting(details.exception)) {
      logError('Flutter-Fehler', details.exception, flutterErrorStack(details));
    }
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    if (worthReporting(error)) logError('Unbehandelter Fehler', error, stack);
    return false; // false: Standardbehandlung nicht unterdrücken.
  };

  // Vor runApp, damit die Einstellungen schon im ersten Frame gelten. Der
  // Aufruf liest eine kleine lokale Datei — er darf den Start aufhalten,
  // ein sichtbares Umschalten nicht.
  final settings = PrefsSettings(await SharedPreferences.getInstance());

  // Der Port, über den das Service-Isolate der Fahrt seine Messpunkte
  // an die Karte meldet (#28). Ohne diese Zeile ist die Rückrichtung
  // stumm — PilzBuddy #465. `test/rides/ride_live_bridge_test.dart`
  // prüft, dass sie hier steht.
  initRideCommunication();

  registerFontLicenses();

  runApp(ProviderScope(
    overrides: [settingsProvider.overrideWithValue(settings)],
    child: const TrailBuddyApp(),
  ));
}
