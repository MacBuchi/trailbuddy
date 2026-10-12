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
- **Stand der Stufen:** (a) Gerüst 0.113.1; (b) Karte, Kartenknöpfe und
  Blätter 0.113.2 — alles unter `lib/features/map/` samt Blatt
  „Kartenebenen", Orte-Blatt, Legende und den Leisten des Karten-Screens
  (auch die des Planers, der Fahrt und des Ausgangskorbs, die dort
  stehen); (c) Trails, Trail-Blatt und Import 0.113.3 — alles unter
  `lib/features/trails/` (Liste, Filter, Blatt, Hinweise, Meldungen,
  „Noch gültig?", Zusammenführen, GPX-Import, Singletrail-Skala). Noch
  deutsch, weil außerhalb: die Getter `TrailTrait`/`TrailStatus`/
  `TrailVisibility.label` in `lib/models/trail.dart`, `staleAfterWriteHint`, `kQueuedHint` und `friendlyError` in
  `lib/core/`, die Meldungen von `GpxFormatException`; (d1) Fahrten,
  Zerlege-Blatt und die Texte des Dienstes 0.113.4 — alles unter
  `lib/features/rides/`, dazu `RiderProfile.label(l)` und
  `learnResultText`. (d2) Rundenplaner, Weg zum Trailkopf und Navigation
  folgt. Noch keiner Stufe zugeordnet:
  `lib/features/offline_areas/` und `lib/features/official/` (das Blatt
  eines offiziellen Trails).
- **Texte des Dienstes** (Benachrichtigung der Aufnahme, Fragen
  unterwegs, später die der Navigation) entstehen im Service-Isolate,
  ohne `BuildContext` und ohne Riverpod. Sie holen ihre Texte über
  `serviceL10n()` (`l10n.dart`), das dieselbe Regel liest wie
  `appLocaleProvider`: `pinnedAppLocale`, sonst die Gerätesprache. Eine
  Stelle für beide, damit Benachrichtigung und App nie verschiedene
  Sprachen sprechen (`test/l10n_test.dart`). Ein Sprachschalter im
  Profil müsste seine Wahl dem Dienst mitgeben. Die Kanalnamen in
  `strings.xml` (`kConfirmChannelName`) bleiben außerhalb (#209 offen).
- **Datumsmuster stehen in den ARB-Dateien** (`ridesDatePattern`,
  `splitDatePattern`), gelesen mit `DateFormat(l.xxxPattern,
  l.localeName)` — so bleibt das deutsche Bild Zeichen für Zeichen, und
  Englisch bekommt seine Reihenfolge. Zahlen (`formatMeters` mit Komma)
  und die Einheiten `min`/`h` sind noch nicht nach Sprache formatiert.
- **Was deutsch bleibt, auch nach dem Umzug:** die `label:` von
  `RememberedFlag`, `openHostArchive`, `_moveNow` und Co. — das sind
  Kontexte für `error_reports` (Wochendigest des Betreibers), keine
  Oberfläche. Ebenso Ausnahmetexte (`StateError`, `toString` von
  Fehlern).
- **Enums mit Namen auf dem Schirm** (`PoiGroup`, `PoiKind`, `WayClass`)
  tragen keinen Text mehr im Konstruktor, sondern `label(l)` mit einem
  `switch` — gen-l10n kennt keinen Zugriff über den Namen, und der
  `switch` ist erschöpfend: Eine neue Art ohne Text baut nicht.
- **Pure Helfer, die Text bauen, nehmen `AppLocalizations l` als ersten
  Parameter** (`legendSamples`, `legendGroupTitle`, `contourStatusText`).
  Ihre Tests holen die deutschen Texte aus `l10nDe`
  (`test/fakes/l10n_de.dart`).
- **Platzhalter bekommen fertig formatierte Werte**, solange ihr Helfer
  noch nicht umgezogen ist: `formatMeters`, `rideDurationLabel`,
  `formatRideDate`, `formatBytes` und `formatCachedAt` (Datum als
  `28.9., 10:12`) sind deutsch, bis ihre Stufe kommt (d; `formatMeters`
  liegt in `lib/core/geo.dart` und gehört keiner Stufe).
  Ein Satz mit Zahl ist ein ICU-Plural in der ARB-Datei, nie
  `n == 1 ? 'Trail' : 'Trails'` im Code.
- **Kein Zweig aus einem einzelnen Wort** (`=0{MEIN}`, `select`):
  `test/l10n_test.dart` liest Platzhalter mit einem einfachen Muster und
  hielte `{MEIN}` für einen. Stattdessen zwei Schlüssel und die Wahl im
  Code (`listTagMine` / `listTagMineWithBuddies`) oder ganze Sätze je Fall
  (`heightsReason*`).
- **Touren und Vorführungen** übernehmen Schritte über `_from(…, title)`
  mit dem deutschen Titel. Beim Umzug von `lib/features/help/` und
  `highlights/` müssen sie über einen Schlüssel zueinander finden, nicht
  über den Text (#209, Stufe f).
- Was die App NICHT über ARB übersetzt: die Push-Texte aus `push_flush`
  (Server, braucht die Sprache des Empfängers), die Kanalnamen in
  `android/…/strings.xml`, Changelog, Hilfe- und Rechtsseiten — offen in
  #209.
