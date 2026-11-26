// Was nie in eine Cloud-Sicherung geht (#644), EINE Liste für Android und
// iOS. Android liest sie nicht selbst — dort stehen dieselben Namen in
// `backup_rules.xml` und `full_backup_content.xml`, und
// `test/ios_support_test.dart` hält die drei zusammen. iOS sichert
// `Application Support` ab Werk in iCloud; die App setzt dort beim Start
// `isExcludedFromBackup` (`ios/Runner/BackupExclusion.swift`).
//
// Warum jeder Eintrag fehlt, steht in `backup_rules.xml`: Fahrten und
// Ausgangskorb verlassen das Gerät nie von selbst (Konzept, Entscheidung
// 4), Zwischenspeicher zeigen, wo man geschaut hat, Karten sprengen jede
// Grenze und sind neu ladbar.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'platform_support.dart';

/// Ordner unter dem App-Verzeichnis (`getApplicationSupportDirectory`).
/// iOS legt sie vorher an — ein Ordner, den es noch nicht gibt, kann
/// kein Merkmal tragen, und der erste Inhalt ginge sonst bis zum nächsten
/// Start in die Sicherung.
const kBackupExcludedDirs = [
  'offline_maps',
  'outbox',
  'trail_cache',
  'rides',
  'updates',
  'official_trails',
  'seen_host',
];

/// Einzelne Dateien dort (MapLibres Zwischenspeicher auf Android). Nur
/// gekennzeichnet, wenn es sie gibt. Auf iOS liegt er unter
/// `<Bundle-ID>/.mapbox/`, und den Ordner nimmt MapLibre Native selbst aus
/// (im Simulator nachgewiesen, `integration_test/ios_signin_smoke_test.dart`).
const kBackupExcludedFiles = ['mbgl-offline.db', 'mbgl-offline.db-journal'];

/// Der Kanal zur iOS-Seite; der Name steht in Swift gleich.
const kBackupChannel = MethodChannel('de.mcbuchi.trailbuddy/backup');

/// Beim Start: auf iOS alles aus [kBackupExcludedDirs],
/// und [kBackupExcludedFiles] von der Sicherung ausnehmen. Auf Android und im
/// Browser nichts (dort gelten die XML-Regeln bzw. gibt es keine
/// Sicherung). Ein Fehler wird gemeldet, hält aber nichts auf.
Future<void> excludeFromCloudBackup({
  bool? supported,
  Future<String> Function()? baseDir,
  MethodChannel channel = kBackupChannel,
  void Function(Object error, StackTrace stack)? onError,
}) async {
  if (!(supported ?? hasIosChannels)) return;
  try {
    final base =
        await (baseDir ??
            () async => (await getApplicationSupportDirectory()).path)();
    await channel.invokeMethod<void>('exclude', {
      'dirs': [for (final d in kBackupExcludedDirs) '$base/$d'],
      'files': [for (final f in kBackupExcludedFiles) '$base/$f'],
    });
  } catch (e, s) {
    (onError ?? _report)(e, s);
  }
}

void _report(Object e, StackTrace s) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: e,
      stack: s,
      library: 'backup_exclusions',
      context: ErrorDescription('beim Ausschluss aus der iCloud-Sicherung'),
    ),
  );
}
