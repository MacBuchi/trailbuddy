import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/errors.dart' show logError;
import '../core/settings.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// Texte der Oberfläche in der Sprache der App (#209):
/// `context.l10n.previewRibbon`. Die Texte stehen in `app_de.arb`
/// (Vorlage) und `app_en.arb`; Regeln in `lib/l10n/CLAUDE.md`.
extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Die Wahl im Profil (#209, „Sprache"): wie das Gerät, Deutsch oder
/// Englisch. Gerätelokal wie das Erscheinungsbild.
enum AppLanguage {
  system(null),
  de(Locale('de')),
  en(Locale('en'));

  const AppLanguage(this.locale);

  /// `null` heißt: die des Geräts bzw. des Browsers, aufgelöst über
  /// [resolveAppLocale].
  final Locale? locale;

  static AppLanguage parse(String? name) =>
      values.where((l) => l.name == name).firstOrNull ?? system;
}

/// Der Name einer Sprache in sich selbst („Deutsch", „English") — so
/// findet man seine Sprache auch in einer App, die man nicht lesen kann.
/// Deshalb nicht aus den ARB-Dateien.
String languageName(Locale locale) => switch (locale.languageCode) {
      'de' => 'Deutsch',
      _ => 'English',
    };

/// Die Wahl im Profil, gemerkt in [Settings.language].
class LanguageNotifier extends Notifier<AppLanguage> {
  @override
  AppLanguage build() {
    final language = AppLanguage.parse(ref.read(settingsProvider).language);
    chosenAppLocale = language.locale;
    return language;
  }

  void set(AppLanguage language) {
    state = language;
    chosenAppLocale = language.locale;
    ref
        .read(settingsProvider)
        .setLanguage(language.name)
        .catchError((Object e, StackTrace s) => logError('Sprache merken', e, s));
  }
}

final languageProvider = NotifierProvider<LanguageNotifier, AppLanguage>(LanguageNotifier.new);

/// Die Sprache, in der die App läuft — `null` heißt: die des Geräts bzw.
/// des Browsers, aufgelöst über [resolveAppLocale].
///
/// Ein eigener Provider über [languageProvider]: Tests starten die App
/// damit unter einer festen Sprache (`test/l10n_test.dart`), ohne die
/// Einstellung anzufassen.
final appLocaleProvider = Provider<Locale?>((ref) => ref.watch(languageProvider).locale);

/// Die gewählte Sprache in DIESEM Isolate; `null` heißt: die des Geräts.
/// In der App setzt sie [LanguageNotifier], im Service-Isolate
/// [refreshServiceLocale] je Takt — dort gibt es kein Riverpod. EINE Regel
/// für Oberfläche und Dienst, damit Benachrichtigung und App nie
/// verschiedene Sprachen sprechen.
Locale? chosenAppLocale;

/// Die Texte außerhalb des Widget-Baums: Benachrichtigungen der Aufnahme
/// und der Navigation, die im Service-Isolate entstehen, und Notifier
/// ohne `BuildContext`. Dieselbe Wahl wie die App: [chosenAppLocale],
/// sonst die Gerätesprache über [resolveAppLocale].
AppLocalizations serviceL10n() => lookupAppLocalizations(chosenAppLocale ??
    resolveAppLocale(debugDeviceLocales ?? PlatformDispatcher.instance.locales));

/// Die Sprachen des Testgeräts für [serviceL10n]: `pumpApp` setzt sie mit
/// `localesTestValue` gleich. Ohne diese Naht läse der Dienst im Test das
/// echte `PlatformDispatcher.instance` — `en_US` unter dem deutschen
/// Testgerät.
@visibleForTesting
List<Locale>? debugDeviceLocales;

/// Liest im Service-Isolate die Wahl aus dem Profil nach. Derselbe
/// Schlüssel wie [Settings.language], direkt aus den SharedPreferences
/// (`reload`: die App schreibt in einem anderen Isolate). Wirft nie —
/// ohne Wert bleibt die letzte Wahl.
Future<void> refreshServiceLocale() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    chosenAppLocale = AppLanguage.parse(prefs.getString(kLanguageSettingKey)).locale;
  } catch (_) {
    // Der Dienst hat niemanden, der fängt; der nächste Takt versucht es.
  }
}

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
