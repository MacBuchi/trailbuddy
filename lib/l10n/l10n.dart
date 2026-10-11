import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// Texte der Oberfläche in der Sprache der App (#209):
/// `context.l10n.previewRibbon`. Die Texte stehen in `app_de.arb`
/// (Vorlage) und `app_en.arb`; Regeln in `lib/l10n/CLAUDE.md`.
extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Die Sprache, in der die App läuft — `null` heißt: die des Geräts bzw.
/// des Browsers, aufgelöst über [resolveAppLocale].
///
/// **Bis die Übersetzung trägt, bleibt die App deutsch** (#209, Stufe a).
/// Die Texte ziehen Bereich für Bereich in die ARB-Dateien um; folgte die
/// App schon jetzt der Gerätesprache, sähe ein englisches Telefon eine
/// halb übersetzte App. Erst wenn alle Bereiche umgezogen sind, wird die
/// Vorgabe `null` — ein Sprachschalter im Profil setzte dann hier an.
///
/// Ein Provider und keine Konstante: Nur so kann ein Test die App unter
/// einer anderen Sprache starten (`test/l10n_test.dart`).
final appLocaleProvider = Provider<Locale?>((ref) => const Locale('de'));

/// Wählt aus den bevorzugten Sprachen des Geräts die der App: die erste,
/// die die App kann; sonst Englisch.
///
/// Englisch und nicht Deutsch als Rückfall (#209: was nicht Deutsch ist,
/// wird Englisch): Wer sein Telefon auf Französisch stellt, liest Englisch
/// eher als Deutsch. Flutters eigene Auflösung nähme hier die erste
/// unterstützte Sprache, also Deutsch. Steht Deutsch weiter hinten in
/// der Liste (`fr`, `de`), gewinnt aber Deutsch — die Person hat es selbst
/// genannt.
Locale resolveAppLocale(Iterable<Locale>? preferred) {
  for (final locale in preferred ?? const <Locale>[]) {
    for (final supported in AppLocalizations.supportedLocales) {
      if (supported.languageCode == locale.languageCode) return supported;
    }
  }
  return const Locale('en');
}
