import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/l10n.dart';

/// Öffentliche Links der App — für Einladungen und Hilfetexte.
class AppInfo {
  static const webAppUrl = 'https://macbuchi.github.io/trailbuddy/';
  static const githubUrl = 'https://github.com/MacBuchi/TrailBuddy';
  static const apkDownloadUrl =
      'https://github.com/MacBuchi/TrailBuddy/releases/latest';

  /// Der automatisch deployte Entwicklungsstand der Web-App.
  ///
  /// Eigenes Repo und damit eigener Origin — bewusst, aus zwei Gründen:
  /// Der Pages-Branch wird bei jeder Beförderung mit `force_orphan` neu
  /// angelegt (ein Unterordner überlebte das nicht), und ein geteilter
  /// Origin hieße geteilter `localStorage` — die Vorschau benutzte also
  /// Sitzung und Einstellungen der echten App. Deshalb ist dort eine
  /// eigene Anmeldung nötig, und darauf muss der Hinweis hinweisen.
  static const previewAppUrl =
      'https://macbuchi.github.io/trailbuddy-preview/';

  /// Play-Store-Eintrag (applicationId aus android/app/build.gradle.kts).
  /// Nur für Play-Builds: dort sind Verweise auf APK-Downloads unzulässig.
  static const playStoreUrl =
      'https://play.google.com/store/apps/details?id=de.mcbuchi.trailbuddy';

  /// Platzhalter, wenn sich die installierte Version nicht ermitteln lässt.
  /// Wer damit rechnet, darf daraus keine Entscheidung ableiten — siehe
  /// `updateRequiredProvider`, der in dem Fall bewusst nicht sperrt.
  static const unknownVersion = '–';

  /// Liegen als statische Seiten neben der Web-App (`web/*.html`) und sind
  /// damit auch ohne installierte App erreichbar — für die Konto-Löschung
  /// verlangt Google Play genau das.
  static const privacyUrl =
      'https://macbuchi.github.io/trailbuddy/datenschutz.html';
  static const deleteAccountUrl =
      'https://macbuchi.github.io/trailbuddy/konto-loeschen.html';

  /// Die Anbieterkennzeichnung nach § 5 DDG.
  ///
  /// Sie muss „leicht erkennbar, unmittelbar erreichbar und ständig
  /// verfügbar" sein — und das gilt für die App genauso wie für die
  /// Seite. Deshalb steht sie nicht nur im Web, sondern auch als Zeile
  /// im Profil neben der Datenschutzerklärung.
  static const impressumUrl =
      'https://macbuchi.github.io/trailbuddy/impressum.html';

  /// Englische Höflichkeitsübersetzungen der drei Rechtsseiten (#209);
  /// verbindlich bleibt die deutsche Fassung, beide verweisen
  /// aufeinander.
  static const privacyUrlEn =
      'https://macbuchi.github.io/trailbuddy/privacy.html';
  static const deleteAccountUrlEn =
      'https://macbuchi.github.io/trailbuddy/delete-account.html';
  static const impressumUrlEn =
      'https://macbuchi.github.io/trailbuddy/imprint.html';

  /// Die Rechtsseite in der Sprache der Oberfläche: Deutsch bleibt
  /// Deutsch, alles andere bekommt die englische Fassung — dieselbe
  /// Regel wie bei der App-Sprache.
  static String privacyUrlFor(Locale locale) =>
      locale.languageCode == 'de' ? privacyUrl : privacyUrlEn;
  static String impressumUrlFor(Locale locale) =>
      locale.languageCode == 'de' ? impressumUrl : impressumUrlEn;

  static String inviteText(AppLocalizations l, String? username) =>
      username != null && username.isNotEmpty
          ? l.buddysInviteTextWithName(webAppUrl, apkDownloadUrl, username)
          : l.buddysInviteText(webAppUrl, apkDownloadUrl);
}

/// Installierte App-Version für die „Über"-Sektion im Profil.
final appVersionProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  } catch (_) {
    return AppInfo.unknownVersion;
  }
});
