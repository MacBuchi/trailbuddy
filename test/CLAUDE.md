# TrailBuddy — Arbeitsregeln für `test/`

Teil der Root-`CLAUDE.md` (dort: Abschnitt „Tests" und der Index aller
Teildateien). Hier stehen die Fallen, die beim Schreiben von Tests schon je
eine Runde gekostet haben — still, ohne auf die Ursache zu zeigen. Die
meisten stehen ausführlich in der `CLAUDE.md` des Ordners, in dem der Code
liegt; hier nur, was man VOR dem ersten neuen Test wissen muss (#237).

## Dart-MCP zuerst

`.mcp.json` hängt den offiziellen Dart- und Flutter-MCP-Server ein
(`tool/dart_mcp.sh`, dort steht, welche Werkzeuge an sind und warum).
Gemessen am 2026-10-07 (Server 1.1.3):

- **`analyze_files`** statt `flutter analyze`: dieselben Befunde
  (Fehler UND Warnungen), ohne Befund 91 statt rund 2 000 Zeichen, eine
  Datei in ~3 s, sobald der Server warm ist (der erste Aufruf braucht bis
  zu einer Minute). **`paths` als `file://`-URI angeben** — ein relativer
  Pfad prüft still NICHTS und meldet „No errors" (bei der Gegenprobe so
  passiert). **Nie `applyFixes: true`**: Das schreibt Code um, wie das
  abgeschaltete `dart_fix`.
- **`run_tests`**: **`paths` RELATIV zur Wurzel** (`test/…`) — genau
  umgekehrt: eine `file://`-URI wird an die Wurzel gehängt und „Does not
  exist". Die Ausgabe ist so knapp wie `flutter test --reporter
  failures-only` (rot: 2 282 gegen 2 180 Zeichen) — der Gewinn gegenüber
  dem Reporter ist null, gegenüber dem Standard-Reporter klein. Wer den
  CLI-Weg nimmt, nimmt `--reporter failures-only`.
- **`lsp`** kann `hover`, `signatureHelp` und `resolveWorkspaceSymbol` —
  KEINE Verweise und keine Definition aus einer Stelle heraus.
  `resolveWorkspaceSymbol` nennt Datei und Zeilenbereich eines Symbols;
  danach nur diese Zeilen lesen statt der ganzen Datei.
- Vor dem Commit bleibt `flutter analyze` + `flutter test` der Maßstab — so
  prüft CI.

## Gegenprobe — bevor ein Test als Absicherung gilt

Kein Test gilt, bevor er einmal absichtlich rot war: die geschützte
Produktionsstelle entschärfen, Test rot sehen, zurückbauen, grün sehen.
**Zurückbauen per Dateikopie, nie per `git checkout --`**, solange im
Arbeitsverzeichnis Unkommittiertes liegt (in PilzBuddy zweimal Arbeit
verloren, hier einmal die frisch aufgeteilte `CLAUDE.md`). Die Gegenprobe
kann lügen: Der Aufbau erreicht die Stelle nicht (bleibt sie grün, zuerst
den TESTAUFBAU verdächtigen), die mutierte Bedingung war ohnehin
unerreichbar, oder der Test holt seine Eingabe aus der Konstante, die er
bewacht. Bei Merkern, die `FakeSettings` anders vorbelegt als die App,
steht die Zahl der brechenden Tests in der Ordner-`CLAUDE.md` — sie ist die
Gegenprobe der Vorgabe.

## Fallen im Harness

- **Ein zweiter `pumpApp` ist kein Kaltstart.** Derselbe `ProviderScope`
  behält seinen Container; vorher `await tester.pumpWidget(const
  SizedBox());` (`lib/data/CLAUDE.md`, Zwischenspeicher).
- **`FakeSettings` setzt die Einführung ab Werk auf „gesehen"**
  (`safetyNoteSeen`, `mapTourSeen`, `seenCoachTours`,
  `highlightsSeenVersion`), die App auf „neu". Tests für Hinweis, Touren
  und Neuheiten geben ihre `FakeSettings` ausdrücklich mit
  (`lib/features/help/CLAUDE.md`, `lib/features/highlights/CLAUDE.md`).
- **Touren: nach jedem Schritt `settle()`** — 400 ms Tippsperre; Schritte
  in `coach-bubble` suchen, Titel nie wie ein Text auf dem Schirm
  (`lib/features/coach/CLAUDE.md`).
- **Kein `pumpAndSettle`** bei Endlos-Animationen; die `settle()`-Helfer
  mit festen Frames nutzen.
- **Ein echter Isolate antwortet in der Test-Zone nie** — der Planer
  rechnet dort mit `InlineLoopPlanRunner`, die Kopie des Netzes in
  Häppchen statt im Isolate (`lib/features/routing/CLAUDE.md`,
  `lib/data/CLAUDE.md`).
- **MapLibre ist im Widget-Test nicht renderbar.** Tests fahren
  `FakeMapView` (Tipps über `tapMapAt`, dieselbe Trefferprüfung);
  `useRealMap: true` nur für Interna von flutter_map
  (`lib/features/map/CLAUDE.md`).
- **Zerlege-Blatt: erst hochziehen** (`sheetScrollTo`), bevor ein Kandidat
  in der faulen Liste gebaut ist (`lib/features/rides/CLAUDE.md`).
- *Die beiden folgenden aus PilzBuddy (#414, #367), dort je eine Runde:*
  **Bildschirmgröße über `tester.view`**, nicht `setSurfaceSize` (das
  ändert nur die Zeichenfläche, `MediaQuery` meldet weiter 800×600):
  `tester.view.physicalSize = …; tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);`
- **Plattform-Kanäle mocken** (`setMockMethodCallHandler`): Unter
  `FakeAsync` löst sich die Antwort eines nicht gemockten Kanals nie auf —
  der Knopf bleibt folgenlos, ohne Fehler.
- **Web-Zweige laufen nur unter dart2js** (`test/web/`, `@TestOn('browser')`,
  CI-Schritt „Web-Test auf dart2js"; lokal `CHROME_EXECUTABLE` auf das
  Chromium unter `/opt/pw-browsers` setzen, dann `flutter test --platform
  chrome test/web/`). Auf der VM ist `kIsWeb` falsch; die Speicher-Fassung
  von idb_shim gibt Werte anders zurück als der Browser. Der Runner
  liefert dort KEINE Assets (`rootBundle` endet im Timeout) — nur
  assetfreier Code. Ein grüner Lauf beweist nur etwas mit einem Nachweis,
  dass der Web-Weg lief (`idbFactoryBrowser.persistent`).

## Werkzeug

- Während der Arbeit nur die betroffenen Dateien testen; die ganze Suite
  einmal am Ende.
- Kein `dart format` (Root-`CLAUDE.md`).
- `flutter analyze`/`flutter test` haben `analysis_options.yaml` hier beim
  Messen NICHT verändert (anders als in PilzBuddy beobachtet). Steht die
  Datei trotzdem im Diff, ist es kein Teil der Änderung: `git restore`.
