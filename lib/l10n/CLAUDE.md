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
  `learnResultText`; (d2, Teil 1) die Folgeansicht der Navigation
  0.114.0 (`nav_view.dart`, mit dem Umbau nach Abschnitten, #312);
  (d2, Teil 2) Rundenplaner samt Leiste, Blatt „Route" (Zum Trailkopf,
  Route hierher), Navi-Auswahl, Zwischenpunkte und die letzten
  Dienst-Texte der Navigation 0.117.1 — damit ist
  `lib/features/routing/` ganz umgezogen (Schlüssel `loop*`, `route*`,
  `routing*`, `navChoice*`); `WayClass.label(l)` und `NavChoice.label(l)`
  als `switch`; (e1) Buddys 0.117.2 — alles unter `lib/features/friends/`
  (Liste, Anfragen, Karte „Mit … verbunden", Alias-Dialog, Verlauf;
  Schlüssel `buddys*`, `alias*`, `messages*`), dazu der Einladungstext
  (`AppInfo.inviteText(l, …)`) und `ConnectSummary.sentence(l, …)`. Die
  Leiste nach einem abgelehnten Senden kommt aus `messagesRejected`; das
  `toString` von `MessageRejectedException` bleibt deutsch (Ausnahmetext).
  (e2) Profil 0.117.3 — alles unter `lib/features/profile/` (Liste und
  Kopf, Konto mit Passwort, E-Mail, Name, andere Geräte und Löschen,
  Benachrichtigungen, Erscheinungsbild, Fahrerprofil, „Über TrailBuddy“;
  Schlüssel `profile*`, `account*`, `riderProfile*`, `push*`, `about*`)
  und die Reiterleiste in `router.dart` (`tab*`). Die Meldungen von
  `PushEnabledNotifier.set(l, …)`/`sendTest(l)` nehmen `l` wie die puren
  Helfer. Unter Englisch heißen die Reiter anders: Tests rufen
  `openTab(tester, 'Profile')` bzw. `openProfilePage(…, tab: 'Profile')`.
  Noch deutsch, weil in `lib/core/` und mit dem Login geteilt:
  `changePasswordErrorMessage`, `emailChangeErrorMessage`,
  `usernameProblem`, `usernameChangeErrorMessage`. (f1) Hinweis, Hilfe
  und Touren 0.117.4 — die Knöpfe der Hinweis-Maschine (`coach*`), der
  Sicherheitshinweis (`safetyNote*`), die Kurzanleitung (`help*`) und alle
  Touren samt Beispielen (`tourMap*`, `tourWelcome*`, `tourSplit*`,
  `tourTrails*`, `tourBuddys*`, `tourExample*`). Die Skripte sind seither
  Funktionen von `l` (`mapTourScript(l)`, `helpSteps(l)` …), die Starter
  nehmen `l` als ersten Parameter. (f2) „Entdecken“, das Neuheiten-Blatt
  und die Vorführungen 0.117.5 — Titel und Text jedes Eintrags in
  `kFeatureHighlights` (`highlight<Kennung>Title`/`…Text`; die Felder
  sind Funktionen von `l`, die Liste deshalb `final` statt `const`), die
  eigenen Schritte der Vorführungen (`demo<Kennung>[N]Title`/`…Text`,
  die geteilten Ersatzschritte `_noTrailYet(l)` und Co. als Funktionen),
  Blatt und Seite (`discover*`, `highlightSheet*`), die Gruppen über
  `HighlightTab.label(l)` aus `tab*`. `tool/highlights_preview.py` liest
  die Titel seither aus der `app_de.arb` des beförderten Tags (`--arb`).
  (g1) Offline-Karten 0.117.7 — alles unter
  `lib/features/offline_areas/` („Meine Bereiche“ mit Region, Übersicht
  und „ganze Region“, die Leiste, „Entwurf verwerfen?“, der
  Speichern-Dialog samt Fortschritt, der Hinweis beim Zeichnen;
  Schlüssel `areas*`, `areaRail*`, `areaDiscard*`, `areaSave*`,
  `areaProgress*`, `areaDrawHint*`). Der Download-Notifier hat keinen
  `BuildContext`: Benachrichtigung (`areaNotice*`), Fehler im Zustand
  (`areaError*`) und die Namen „Übersicht …“/„Karte …“ kommen aus
  `serviceL10n()`, wie bei der Aufnahme. `OutsideRegions.message(l)`
  nimmt `l`; ihr `toString` ist kein Satz mehr. Der Namensvorschlag
  „Bereich vom …“ nimmt sein Datumsmuster aus `areaSaveDatePattern`.
  (g2) Anmelden, Registrieren und offizielle Trails 0.117.8 — alles unter
  `lib/features/auth/` (Schlüssel `login*`, `signup*`, `auth*`) und das
  Blatt eines offiziellen Trails samt „Auch ausgeschildert als …" im
  Trail-Blatt (`official*`). Mit umgezogen, weil Login und Profil sie
  teilen: die Fehlertexte in `lib/core/errors.dart` (`loginErrorMessage`,
  `resetErrorMessage`, `signupErrorMessage`, `confirmErrorMessage`,
  `emailChangeErrorMessage`, `changePasswordErrorMessage`,
  `usernameChangeErrorMessage` — alle mit `l` als erstem Parameter;
  `authError*`), `usernameProblem(l, …)` (`username*`), Passwortfeld und
  „Erneut senden in … s" (`password*`, `resendIn`). Der Stand der Quelle
  kommt aus `formatIsoDate(l, …)` mit `officialDatePattern`; ein Test
  ohne Widget-Baum ruft dafür `initializeDateFormatting` (die App lädt
  die Datumsdaten über die Material-Delegates). Noch deutsch: der
  Ersatzname „Ohne Namen" beim Lesen der Quelldatei. (h) Kern und
  Trail-Modell 0.117.9 — `friendlyError(l, e)` (`error*`; ohne Kontext
  — Ausgangskorb, Planer-Graph, Ziele der Fahrt-Fragen — über
  `serviceL10n()`), die Hinweise nach dem Speichern (`doneOrStale(l, …)`
  bzw. `l.staleAfterWrite`, `l.queuedHint`), `TrailTrait`/`TrailStatus`/
  `TrailVisibility.label(l)` als `switch`, `Trail.displayName(l)`
  (`trailUnnamed`), Update-Sperre (`updateRequired*`, `updateAction*`),
  „Foto anhängen“ (`photo*`), GPX-Export (`gpxDownloading`,
  `gpxExportFailed`) und Ladeanimation. **Ein Getter wurde zur Methode —
  in einem String meldet der Analyzer das nicht**: `'${t.label}'` wäre
  still der Tear-off („Closure: …“); jede Stelle ist von Hand gesucht.
  Sortieren und Vergleichen nehmen `Trail.name` (ohne Platzhalter) bzw.
  `compareTrailNames` — Trails ohne Namen hinten, in jeder Sprache;
  Pfade ohne Sprache (`trailSearchTexts`, `navigationLabelOf`, Export,
  Übernehmen) ebenso `name`. `PhotoPipelineException` und
  `GpxFormatException` tragen statt eines Satzes ihre Art und
  `userMessage(l)`/`message(l)`; `toString` bleibt der technische Text
  für den Digest. Pure Helfer, die einen Trailnamen weiterreichen,
  nehmen `l` vorn (`poolTrailOf`, `graphTrailsOf`, `navSectionsOf*`,
  `confirmTargetsOf`, `splitQuestionFor`, `RouteTarget.trailHead`).
  Vor dem Lösen der Sprache bleiben (i): Feedback-Dialog, Update-Banner,
  der Titel „Was ist neu“ und die Beschriftungen des Dateidialogs im
  Import. Namen von Runde und Weg (`loopName`, `routeName*`) gehen
  in die gespeicherte Fahrt und die GPX-Datei — sie bleiben in der
  Sprache, in der geplant wurde.
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
- **Touren und Vorführungen** finden zueinander über `CoachStep.id`
  (`_from(mapTourScript(l), 'map.layers')`), nie über den Titel — der ist
  je Sprache ein anderer. `help_texts_test` verlangt an jedem Tour-Schritt
  eine Kennung, eindeutig je Skript und in beiden Sprachen dieselbe.
- Was die App NICHT über ARB übersetzt: die Push-Texte aus `push_flush`
  (Server, braucht die Sprache des Empfängers), die Kanalnamen in
  `android/…/strings.xml`, Changelog, Hilfe- und Rechtsseiten — offen in
  #209.
