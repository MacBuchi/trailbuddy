# TrailBuddy — Arbeitsregeln für `lib/l10n/`

Teil der Root-`CLAUDE.md` (dort der Index aller Teildateien).

## Sprachen der Oberfläche (#209)

Deutsch und Englisch über Flutters `gen-l10n`. Die Texte stehen in
`app_de.arb` (**Vorlage** — die App ist deutsch gewachsen, jeder neue Text
entsteht zuerst dort) und `app_en.arb`; gelesen mit `context.l10n.<key>`
(`l10n.dart`). Konfiguration in `l10n.yaml` im Wurzelordner.

- **Die erzeugten Dateien sind nicht eingecheckt** (`.gitignore`).
  `flutter pub get`, `flutter test` und jeder Build erzeugen sie aus den
  ARB-Dateien (`generate: true`); jeder CI-Job ruft vorher `pub get`. Eine
  eingecheckte Kopie veraltete still, sobald jemand eine ARB-Datei ändert
  und den Lauf vergisst. Folge: In einem frischen Checkout meldet der
  Analyzer `app_localizations.dart` als fehlend, bis `pub get` lief.
- **Bis die Übersetzung trägt, bleibt die App deutsch.** `appLocaleProvider`
  liefert fest `Locale('de')`. Die Texte ziehen Bereich für Bereich um
  (Stufen in #209: Karte, Trails, Fahrten und Planer, Buddys und Profil,
  Touren und Hilfe); erst danach wird die Vorgabe `null` und die App folgt
  dem Gerät bzw. Browser. Folgte sie schon vorher, sähe ein englisches
  Telefon eine halb übersetzte App.
- **Rückfall ist Englisch**, nicht die erste unterstützte Sprache
  (`resolveAppLocale`): `fr` ⇒ Englisch, `fr, de` ⇒ Deutsch.
- **Das Testgerät spricht Deutsch.** `pumpApp` setzt
  `platformDispatcher.localesTestValue` auf `de_DE` (Parameter
  `deviceLocales`); ab Werk meldet flutter_test `en_US`, und sobald die
  App dem Gerät folgt, fände kein Flow-Test mehr seine deutschen Texte.
  Ein Test unter Englisch übergibt `appLocaleProvider`
  (`test/l10n_test.dart`).
- **Ein Test mit eigenem `MaterialApp`** (ohne `pumpApp`), der ein
  umgezogenes Widget baut, braucht
  `localizationsDelegates: AppLocalizations.localizationsDelegates` —
  sonst wirft `AppLocalizations.of` (`nullable-getter: false`).
- **Jeder Schlüssel braucht in der Vorlage `@key.description`** — sie ist
  alles, was die übersetzende Person vom Ort des Textes weiß.
  `test/l10n_test.dart` prüft das, dieselben Schlüssel in beiden Dateien
  und dieselben Platzhalter.
- **Touren und Vorführungen** übernehmen Schritte über `_from(…, title)`
  mit dem deutschen Titel. Beim Umzug von `lib/features/help/` und
  `highlights/` müssen sie über einen Schlüssel zueinander finden, nicht
  über den Text (#209, Stufe f).
- Was die App NICHT über ARB übersetzt: die Push-Texte aus `push_flush`
  (Server, braucht die Sprache des Empfängers), die Kanalnamen in
  `android/…/strings.xml`, Changelog, Hilfe- und Rechtsseiten — offen in
  #209.
