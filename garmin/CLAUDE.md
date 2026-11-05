# TrailBuddy — Arbeitsregeln für `garmin/`

Teil der Root-`CLAUDE.md` (dort der Index aller Teildateien). Konzept:
`docs/konzept-garmin.md` — die Uhr ist Anzeige, kein Sensor; keine
Garmin-Aktivität, kein Netz, keine Abbiegehinweise.

## Technik-Notizen

- **Bauen nur über `tool/garmin_build.sh`** (Connect-IQ-SDK aus dem
  SDK-Manager, Schlüssel `~/.connectiq/developer_key.der` beim Betreiber,
  nie im Repo). Es baut aus einer Kopie unter `build/garmin/src`:
  `--points N` setzt eine erfundene Testroute mit N Punkten ein,
  `--gpx DATEI` eine eigene (Koordinaten — bleibt unter `build/`),
  `--test` fährt die Unit-Tests im Simulator, `--demo` den Vorführmodus,
  `--run` die App im Simulator. Auf die Uhr: die `.prg` per USB nach
  `GARMIN/APPS/`. CI baut die Uhr-App nicht (SDK nur mit Garmin-Anmeldung);
  CI prüft `tool/garmin_route.py --self-test` und die Syntax des Skripts.
- **Watchdog: 120 000 Bytecode-Schritte je Ereignis** (`simulator.json`
  der fēnix 5, `watchdogCount`). Ohne Gegenmaßnahme trafen ihn bei 1000
  Punkten nacheinander: Dekodieren (`climbOf`), Zeichnen aller Stücke, die
  Suche über die ganze Linie. Deshalb: `NavRoute.decodeStep` in Häppchen
  zu 300 Punkten über einen Timer (die Ansicht zeigt „Lade Route …"),
  Blöcke zu 32 Punkten mit Hülle (`bMinX` …), Zeichnen nur aus Blöcken im
  Quadrat ±135 px um die Position und mit 4 px Mindestabstand, Suche
  zuerst im Block mit der nächsten Hülle. Wer eine Schleife über alle
  Punkte schreibt, die je Fix oder je Bild läuft, baut den Absturz wieder
  ein — mit `--demo --points 2000` prüfen.
- **Speicher** (Messung 8.1 im Simulator, 124 KB für die App): gut 20 Byte
  je Punkt auf ~29 KB Grundlast; 2000 Punkte 70 KB, ab 3000 „Out of
  Memory" schon beim Laden (rohe Daten und Felder liegen kurz zusammen).
  Grenze für G2: 2000 Punkte. Mit Ring und Seiten 76 KB bei 2000.
- **Unit-Tests** (`source/Tests.mc`): Jede Funktion mit `(:test)` muss
  `(logger as Logger) as Boolean` sein — Hilfsfunktionen liegen deshalb im
  Modul `TestRoutes`, das `(:test)` trägt. Gegenprobe gefahren
  (2026-11-04): `OFF_ROUTE_FIXES` auf 1 und das Vibrieren ohne Sperre ⇒
  zwei Tests rot.
- **Der Vorführmodus** (`(:demo)`, nur mit `--demo`): spielt im Simulator
  reihum Anfahrt, Trail, abseits, angekommen und schreibt den Speicher in
  die Konsole von `monkeydo`. `monkey.jungle` schließt `demo` aus; das
  Skript hängt für `--demo` `base.excludeAnnotations = nodemo` an die
  Kopie an.
- **Farben** (`source/Colors.mc`): je die nächste der 64 MIP-Farben
  (CIELAB) zur App-Farbe im Kommentar; `tool/garmin_route.py --self-test`
  rechnet das gegen `lib/core/app_colors.dart` nach. Karte hell (Satz
  `mapGrades`), Infofläche schwarz mit dem dunklen Satz (`gradeOnDark`).
  `dark.line` ist auf MIP schwarz und damit unsichtbar — dafür `555555`.
- **Schrift**: Die Systemschrift hat keinen Pfeil „↑" — der Pfeil vor dem
  Anstieg ist gezeichnet (`numberLine`, `climbText`). Die Zahlenschrift
  (`FONT_NUMBER_*`) hat kein Komma und kein „%": große Zahlen ganzzahlig,
  die Einheit steht klein darüber.
- **Ring** (`source/Ring.mc`): `drawArc` zählt 0° bei 3 Uhr und gegen
  den Uhrzeigersinn, `TbRing.deg` rechnet den Anteil der Route um; gleiche
  Winkel überspringt `arc()` (sonst zeichnet die Uhr einen vollen Kreis).
  Was auf der Karte bis an den Rand reicht (N, Schilder, Pfeil zurück),
  bleibt innerhalb `TbRing.MAP_R`.
- **Zahlen der Seiten** (`source/RideStats.mc`): nur im Speicher, nichts
  gespeichert (A3). Gegenprobe 2026-11-04: Tempo-Schwelle und Hysterese
  auf 0 ⇒ beide RideStats-Tests rot. Unten wird der Kreis schnell
  schmal: Die Infofläche beginnt bei y 168, die Position steht bei y 128.
- **Startsymbol** `resources/drawables/launcher_icon.png` kommt aus
  `tool/brand_icons.py` (40 px), Prüfsumme in `tool/generated_assets.json`.
- **Die Testroute** `resources/route/route.json` ist erfunden
  (`tool/garmin_route.py --points 1000`, am Äquator, `rel: true`): Die Uhr
  verankert sie am ersten GPS-Fix. Nie eine echte Route hier ablegen.
- **Die Route vom Handy** (G2, `source/PhoneRoute.mc`): Stücke gehen
  sofort in `Application.Storage`, zwei Fächer „a"/„b", `cur` zeigt erst
  nach dem letzten Stück um — eine halbe Übertragung lässt die
  gespeicherte heil. Beim Start lädt `startRoute()` die gespeicherte;
  `loading` steht bis zum Ende des Dekodierens — steht es beim nächsten
  Start noch, ist die Route verworfen (sonst stürzte die App bei jedem
  Start). Beim Wechsel geht die alte Route ZUERST (`swapRoute`: kleine
  Platzhalter-Route, dann laden), beide zusammen passten nicht in 124 KB.
  Berechtigung `Communications` im Manifest. Die Fassung `PROTOCOL` liest
  `test/garmin/watch_route_test.dart` aus dieser Datei.
- **Abzweigungen vom Handy** (`br`, Konzept 2): kommen je Stück mit den
  Punkten, die sie tragen (Nummer der ganzen Linie), `PhoneRoute.append`
  hängt sie an; `NavView` sieht beim Zeichnen alle an — `seg` schneidet
  mit vier Vergleichen aus, 300 Stummel sind ~6 000 Schritte. Eine
  Grenze nach Weg entlang der Route wäre an Serpentinen falsch (ein Punkt
  1,5 km später liegt 50 m daneben).
- **`==` vergleicht Zeichenketten als Objekte**, nicht nach Inhalt: Eine
  Kennung aus `Application.Storage` oder einer Nachricht ist nie `==` dem
  Literal. Immer `"r".equals(t)` bzw. `id.equals(…)` — so lief die
  Zusammensetzung der Stücke zuerst ins Leere (jedes Stück begann das
  Fach neu), der Test `phoneRouteStoresOnlyWhenComplete` fand es.
- **`Test.assertEqual(x, null)` wirft** („Failed invoking <symbol>": es
  ruft `equals` auf dem Wert) — für null `Test.assert(x == null)`. Nach
  so einem Fehler hing der Simulator beim nächsten `--test`: Prozesse
  `monkeydo`/`simulator` beenden, dann neu.
- **„Hallo"** (`sayHello` in `TrailBuddyApp`): beim Start und auf `q`
  vom Handy `{t: "hi", v, id}` mit `PhoneRoute.currentId()` — der
  Kennung der GESPEICHERTEN Route, nicht der geladenen (eine fertig
  empfangene wartet vielleicht noch auf den Wechsel). Das Handy schickt
  daraufhin die aktuelle Route, wenn sie abweicht (Konzept 2, „Das Handy
  stößt an"). `test/garmin/watch_route_test.dart` hält `hi`/`q` mit
  Dart und Kotlin zusammen.
- **Bestwerte** (`RideStats.bests`, vierte Seite „Sprünge" in `NavView`,
  Zeile in der Zusammenfassung): nur im Speicher, bleiben über einen
  Routenwechsel. Die Seite gibt es erst, wenn welche kamen (`pages()`).
- **Die Übersicht ohne Fix** (`drawOverview`): Rahmen aus den Hüllen
  der Blöcke (≤ 63 Vergleiche), dann nur jeder `stride`-te Punkt
  (`OVERVIEW_SEGS` = 200 Stücke je Linie) — `range()` mit großem
  `_reach` liefe über alle Punkte und je Bild an den Watchdog.
- **Der Build-Stempel** (`Rez.Strings.BuildStamp`, oben in der
  Übersicht ohne Fix): `tool/garmin_build.sh` schreibt ihn in die Kopie
  (`resources/strings/build.xml`: Commit, „+" mit Änderungen unter
  `garmin/`, Datum und Uhrzeit); im Repo steht der Platzhalter „dev".
  Connect IQ kann die Version der App zur Laufzeit nicht lesen. Steht
  auf der Uhr ein alter Stempel, ist die neue `.prg` nicht drauf.
- **Akku und Speicher** auf der Seite „Berg" nur im Vorführmodus:
  `drawMeasure` gibt es zweimal, `(:demo)` und `(:nodemo)` — der
  normale Build schließt `demo` aus, `--demo` schließt `nodemo` aus.
- **Zwei Spalten der Zahlenseiten** bei `COL_X` = 54 px um die Mitte;
  unten (y 168–194) ist der Kreis noch ~190 px breit. Lange Namen in der
  Infofläche misst `shieldLine` gegen `chord` (Kreisbreite auf der Höhe
  der Zeile), erst kleinere Schrift, dann „…".
- **Entwurf** im Designer des Betreibers (privat, Link im PR #449-G1);
  das Aussehen steht in `docs/design/README.md` Abschnitt 15.
