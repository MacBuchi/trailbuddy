// Die echte App startet auf dem iOS-Simulator (#644) — ohne Zugangsdaten,
// deshalb in CI (ci.yml, „Build iOS (Simulator)"). Der Kompilier-Check
// allein bewies nicht, dass sie dort läuft. Geprüft wird:
//
// - der Start erreicht die Anmeldung, ohne Ausnahme;
// - die eigenen Kanäle der App antworten (BackupExclusion.swift,
//   HostRequestCounter.swift, GarminBridge.swift — dieselben Namen wie in
//   Kotlin); die Uhr ohne Garmin Connect: „keine", ohne „Uhr verbinden";
// - Fahrten, Korb und Zwischenspeicher sind von der iCloud-Sicherung
//   ausgenommen (dieselbe Liste wie backup_rules.xml).
//
// Bis zur Karte geht `ios_signin_smoke_test.dart` (braucht das Testkonto).
// Gegenproben (2026-11-26): `BackupExclusion.register` im AppDelegate
// entfernt ⇒ rot; `excludeFromCloudBackup` aus main() ⇒ rot.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:trailbuddy/core/backup_exclusions.dart';
import 'package:trailbuddy/features/garmin/garmin_bridge.dart';
import 'package:trailbuddy/features/garmin/garmin_bridge_io.dart'
    show kGarminChannel;
import 'package:trailbuddy/features/map/host_requests.dart';
import 'package:trailbuddy/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Start bis zur Anmeldung, Kanäle und Backup-Ausschluss', (
    tester,
  ) async {
    await app.main();

    // Der erste Start braucht im Simulator gut 10 s bis zum Login, in CI
    // länger; E-Mail UND Passwort abwarten.
    final fields = find.byType(TextField);
    var ok = false;
    for (var i = 0; i < 90 * 4 && !ok; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      ok = fields.evaluate().length >= 2;
    }
    expect(ok, isTrue, reason: 'keine Anmeldung');
    expect(tester.takeException(), isNull);

    // main() hat den Zähler eingehängt (Debug) — die Swift-Seite sagt es.
    expect(await kHostRequestsChannel.invokeMethod<bool>('installed'), isTrue);

    // Die Uhr (#644 Paket 4): Im Simulator gibt es kein Garmin Connect —
    // die Swift-Seite antwortet „nicht da", ohne das SDK zu starten, und
    // ohne gewählte Uhr lauscht sie nicht.
    const garmin = MethodChannel(kGarminChannel);
    final status = WatchStatus.fromChannel(
      await garmin.invokeMethod<Object?>('status', {'appId': kWatchAppId}),
    );
    expect(status.connect, isFalse);
    expect(status.canPick, isFalse);
    expect(
      await garmin.invokeMethod<bool>('listen', {'appId': kWatchAppId}),
      isFalse,
    );
    expect(await garmin.invokeMethod<bool>('pick'), isFalse);

    // Der Ausschluss läuft ohne Warten an; kurz Zeit geben.
    final base = (await getApplicationSupportDirectory()).path;
    final dirs = [for (final d in kBackupExcludedDirs) '$base/$d'];
    List<String>? open;
    bool allThere() => dirs.every((d) => Directory(d).existsSync());
    for (var i = 0; i < 40; i++) {
      open = await kBackupChannel.invokeListMethod<String>('notExcluded', [
        ...dirs,
        // Ein Ordner, den es nicht gibt, ist nie „offen".
        '$base/gibt-es-nicht',
      ]);
      // Angelegt UND ausgenommen: dann ist nichts mehr offen.
      if (open != null && open.isEmpty && allThere()) break;
      await tester.pump(const Duration(milliseconds: 250));
    }
    // Vor der Anmeldung legt niemand diese Ordner an — der Ausschluss tut
    // es, damit schon ihr erster Inhalt ausgenommen ist. Ohne diese Zeile
    // wäre „nichts offen" auch ohne Ausschluss wahr (Gegenprobe gefunden).
    expect(allThere(), isTrue, reason: 'Ordner nicht angelegt');
    expect(open, isEmpty);
    // Und der Gegencheck der Abfrage selbst: der Ordner der App ist es
    // nicht (sonst sagte sie immer „ausgenommen").
    expect(
      await kBackupChannel.invokeListMethod<String>('notExcluded', [base]),
      [base],
    );
  });
}
