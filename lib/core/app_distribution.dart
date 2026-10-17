import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Über welchen Kanal dieser Build ausgeliefert wird.
///
/// Der Play Store verbietet Apps, sich selbst zu aktualisieren oder Nutzer
/// zu APK-Downloads zu schicken („Device and Network Abuse"). Im Play-Build
/// entfällt deshalb der komplette Update-Pfad — dort erledigt das der Store.
/// Die GitHub-APK behält den Hinweis, weil sie sonst niemand aktualisiert.
///
/// Gesetzt beim Bauen: `flutter build appbundle --dart-define=PLAY_BUILD=true`
/// (siehe `.github/workflows/release.yml`). Ohne das Flag gilt der
/// GitHub-Kanal — der Standard für lokale Builds und die veröffentlichte APK.
abstract final class AppDistribution {
  static const isPlayBuild = bool.fromEnvironment('PLAY_BUILD');

  /// Die Dev-App neben der echten (#356, D1): `flutter build apk
  /// --flavor dev`. Flutter reicht den Flavor als [appFlavor] durch. Sie
  /// kommt vom Rechner des Betreibers und hat keinen Update-Weg — ein
  /// Hinweis dort führte zur GitHub-APK, also zur ANDEREN App.
  static const isDevBuild = appFlavor == 'dev';

  /// Zeigt die App selbst auf Updates hin? Nur außerhalb des Play Stores
  /// und nicht in der Dev-App.
  static const showsUpdateHints = !isPlayBuild && !isDevBuild;

  /// Ist das der automatisch deployte Entwicklungsstand?
  ///
  /// Die Web-Vorschau entsteht bei JEDEM Merge auf `main` und liegt unter
  /// einer eigenen Adresse — anders als die Android-Vorabversionen, die
  /// immerhin signierte, getaggte Releases sind. Hier kann also auch ein
  /// halbfertiger Zwischenstand stehen.
  ///
  /// Gesetzt beim Bauen: `--dart-define=PREVIEW_BUILD=true` (siehe
  /// `.github/workflows/preview.yml`). Ohne das Flag gilt „echter Stand" —
  /// die harmlose Fehlerrichtung, denn ein fälschlich als Vorschau
  /// markierter Produktionsstand verunsichert, ein unmarkierter
  /// Entwicklungsstand täuscht.
  static const isPreviewBuild = bool.fromEnvironment('PREVIEW_BUILD');
}

/// Auf welchem Web-Kanal läuft diese App?
///
/// Als Provider, weil `kIsWeb` und [AppDistribution.isPreviewBuild] beide
/// `const` sind — im Test lässt sich keines von beiden umschalten, und
/// eine Zusage, die man nicht prüfen kann, ist keine.
enum WebChannel {
  /// Kein Web — auf Android gibt es weder Vorschau noch Verweis darauf.
  none,

  /// Die freigegebene Web-App unter der Adresse, die die Nutzer kennen.
  stable,

  /// Der automatisch deployte Entwicklungsstand.
  preview,
}

final webChannelProvider = Provider<WebChannel>((ref) {
  if (!kIsWeb) return WebChannel.none;
  return AppDistribution.isPreviewBuild
      ? WebChannel.preview
      : WebChannel.stable;
});
