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
  Grenze für G2: 2000 Punkte.
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
  Anstieg ist gezeichnet (`numberLine`). Unten wird der Kreis schnell
  schmal: Die Infofläche beginnt bei y 168, die Position steht bei y 128.
- **Startsymbol** `resources/drawables/launcher_icon.png` kommt aus
  `tool/brand_icons.py` (40 px), Prüfsumme in `tool/generated_assets.json`.
- **Die Testroute** `resources/route/route.json` ist erfunden
  (`tool/garmin_route.py --points 1000`, am Äquator, `rel: true`): Die Uhr
  verankert sie am ersten GPS-Fix. Nie eine echte Route hier ablegen.
- **Entwurf** im Designer des Betreibers (privat, Link im PR #449-G1);
  das Aussehen steht in `docs/design/README.md` Abschnitt 15.
