# TrailBuddy — Arbeitsregeln für `garmin/`

Teil der Root-`CLAUDE.md` (dort der Index aller Teildateien). Konzept:
`docs/konzept-garmin.md` — die Uhr ist Anzeige, kein Sensor (außer der
eigenen Spur, #484); keine Garmin-Aktivität, kein Netz, keine
Abbiegehinweise.

## Technik-Notizen

- **Prüfen über `tool/garmin_bench.sh`** (Skill `watch-bench`, Konzept
  12): `cases` (Feldszenarien F1–F8 in `docs/watch_cases.json` gegen die
  Fälle, `tool/watch_scenarios_check.py`), `unit`, `scenario`, `device`
  (Tischabnahme mit Logcat), `chain` (Kettenstand, #527: Emulator +
  Simulator über adb; `chain --break` muss rot werden; danach beendet
  das Skript den Simulator — ohne adb-Gegenseite öffnete er je
  Verbindungsversuch ein Fenster „ADB Disconnected.", über 20 nach einem
  Abend, abschalten lässt es sich nicht; `GARMIN_KEEP_SIM=1` hält ihn). Wer hier einen Ablauf ändert, trägt erst den Fall ein und hängt
  ihn an den Schritt eines Szenarios.
- **Bauen nur über `tool/garmin_build.sh`** (Connect-IQ-SDK aus dem
  SDK-Manager, Schlüssel `~/.connectiq/developer_key.der` beim Betreiber,
  nie im Repo). Es baut aus einer Kopie unter `build/garmin/src`:
  `--points N` setzt eine erfundene Testroute mit N Punkten ein,
  `--gpx DATEI` eine eigene (Koordinaten — bleibt unter `build/`),
  `--test` fährt die Unit-Tests im Simulator, `--demo` den Vorführmodus,
  `--run` die App im Simulator, `--store` das Store-Paket
  `build/garmin/trailbuddy.iq` (alle Uhren des Manifests, `-r`, ohne
  Testroute; `--store --run` zeigt diesen Zweig im Simulator). Auf die
  Uhr: die `.prg` per USB nach `GARMIN/APPS/`. CI („Analyze & Test")
  prüft `tool/garmin_route.py --self-test` und die Syntax der Skripte.
- **Unit-Tests in CI** (#512, T6): `watch-tests.yml` fährt
  `tool/garmin_sim.sh up <uhr>` + `unit` für jede Uhr des Manifests im
  Container (Bild des Dritten aus `tool/garmin_sim.Dockerfile`,
  öffentlich, ohne Garmin-Anmeldung; Wegwerf-Schlüssel), nur wenn
  `garmin/`, `lib/features/garmin/`, `docs/watch_cases.json`,
  `tool/garmin_*` oder `tool/watch_layout.*` sich ändern; Ergebnis je
  Uhr in der Run-Summary. Erster Lauf 2026-11-16: 9 Uhren × 80 Tests
  grün in ~5 min; Gegenprobe `OFF_ROUTE_FIXES` 1 ⇒ rot. **Kein
  Pflicht-Check**, bis er zwei Wochen stabil lief (`monkeydo -t` hängt
  gelegentlich) — erst dann Pfadfilter raus und in den Branch-Schutz.
  Eine neue Uhr im Manifest, die das Bild nicht kennt, macht den Job rot
  („kein Simulator").
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
  Memory" schon beim Laden (damals lagen rohe Daten und Felder kurz
  zusammen — seit 2026-11-05 nicht mehr, nachzumessen). Mit Ring und
  Seiten 76 KB bei 2000. **Überholt**: Neben dem heutigen Code stürzen
  2000 Punkte vom Handy beim Laden ab (Kettenstand 2026-11-13, `CHAIN_BIG`
  in `tool/garmin_bench.sh`); die Grenze `kWatchMaxPoints` ist seit
  0.169.1 800 — die größte, bei der die Uhr während der Fahrt noch eine
  zweite gleich große Route annimmt (Messwerte bei „Speicher neben der
  größten Route", #510). **Seit 1.8.0 700** (unten, „Ansagen und Buddys").
- **Das Gerät ist strenger als der Simulator** (CIQ_LOG.YML, fēnix 5,
  2026-11-05): Die Übersicht ohne Fix (200 Stücke je Durchgang, je Stück
  vier `sx`/`sy`) lief im Simulator, am Gerät brach sie bei jedem Start
  den Watchdog. Seitdem rechnet `overviewPoints` die Übersicht einmal je
  Route in Bildpunkte, und `seg` zeichnet je Bild höchstens `FRAME_SEGS`
  Striche. Ein Absturz am Gerät steht in `GARMIN/APPS/LOGS/CIQ_LOG.YML`
  (vor dem Sync lesen, danach heißt es `.BAK`) — mit Datei, Zeile und
  Funktion, sobald die `.prg` von `tool/garmin_build.sh` kommt.
- **Protokoll 2** (`PhoneRoute.mc`, Konzept 2): je Punkt eine Zahl
  `(dLat << 16) | dLon`, Höhen zu zweit, Stummel `[Punkt, gepackt]`.
  `unpackHi/Lo` maskieren, damit es nicht darauf ankommt, ob `>>` das
  Vorzeichen mitnimmt. `NavRoute` liest die Stücke über `RouteParts`
  einzeln (Speicher oder Liste), `fromDict` für Testroute und Tests.
  Die Grenze je Stück (`MAX_PART_INTS`) gilt nur für `take` — die
  Testroute ist EIN Stück mit 1560 Zahlen; galt sie für alles, lud die
  Uhr die Testroute alle 50 ms neu („Lade Route 0 %", ohne Ausweg,
  2026-11-05; Test `resourceRouteDecodes`).
- **`try/catch` fängt nur `Lang.Exception`** (`StorageFullException` …),
  nicht „Out of Memory", Watchdog, Index außerhalb oder falschen Typ —
  die beenden die App. Deshalb prüft `PhoneRoute.take` jedes Feld, bevor
  es etwas ablegt, und `NavRoute` jede Stück-Form beim Dekodieren.
- **`CrashGuard`** (`PhoneRoute.mc`): „risk" = Kennung der Route, solange
  sie neu ist; `onStop` und eine ruhige Minute löschen es. Steht es beim
  Start noch, zählt es; beim zweiten Mal in Folge ist die Route `bad`.
  Ein sauberer Lauf dazwischen setzt den Zähler zurück.
- **Simulator für `--test`**: Er muss laufen und bereit sein, bevor
  `monkeydo -t` startet (nach `open` gut 10 s) — sonst wartet `monkeydo`
  ohne Ausgabe. Die Konsole von `--demo` erreicht eine umgeleitete
  Ausgabe nicht; Speicherzahlen dort nur im Fenster.
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
  Im Speicher liegt je Stück nur `[pts, ele, br]`, der Kopf als `<fach>h`.
  Berechtigung `Communications` im Manifest. Die Fassung `PROTOCOL` liest
  `test/garmin/watch_route_test.dart` aus dieser Datei.
- **Abzweigungen vom Handy** (`br`, Konzept 2): kommen je Stück mit den
  Punkten, die sie tragen (Nummer der ganzen Linie), `NavRoute`
  dekodiert sie nach den Punkten ihres Stücks (`branchesOf`); `NavView`
  sieht beim Zeichnen alle an — `seg` schneidet
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
- **„Hallo"** (`sayHello` in `WatchCore`): beim Start und auf `q`
  vom Handy `{t: "hi", v, id, bad}` mit `PhoneRoute.currentId()` — der
  Kennung der GESPEICHERTEN Route, nicht der geladenen (eine fertig
  empfangene wartet vielleicht noch auf den Wechsel). Das Handy schickt
  daraufhin die aktuelle Route, wenn sie abweicht (Konzept 2, „Das Handy
  stößt an"). `test/garmin/watch_route_test.dart` hält `hi`/`q` mit
  Dart und Kotlin zusammen.
- **Die Position des Handys** (`phoneFix` in `WatchCore`, Konzept
  2): `{t: "p", la, lo}` gilt nur bis zum ersten eigenen Fix
  (`_ownFix`); sie geht durch den Tracker ohne Kurs und Tempo, ohne
  Vibrieren und ohne `RideStats`. Mit dem ersten eigenen Fix schickt die
  Uhr einmal `{t: "g"}` und legt einen NEUEN `NavTracker` an — sonst
  stünde „abseits" schon vom Handy her, und das Abkommen am eigenen GPS
  vibrierte nicht. `NavView.setState(…, phone)` zeichnet den Pfeil hohl
  mit „HANDY-GPS". Eine andere Fassung im ersten Stück ist `ver` (mit
  `v` in der Antwort), nicht `bad`.
- **`--test` hängt manchmal ohne Ausgabe** (2026-11-05): Der Bau gelingt,
  `monkeydo` schreibt nichts, auch mit vorher gestartetem Simulator.
  Dann `monkeydo`/`MonkeyDoDeux` und den Simulator beenden; eine
  Gegenprobe mit Dateikopie und `trap` zurückbauen, sonst bleibt die
  entschärfte Fassung liegen.
- **Bestwerte** (`RideStats.bests`, vierte Seite „Sprünge" in `NavView`,
  Zeile in der Zusammenfassung): nur im Speicher, bleiben über einen
  Routenwechsel. Die Seite gibt es erst, wenn welche kamen (`pages()`).
  Seit #514 (1.6.0) erscheint sie erst mit einem Zähler über 0
  (`RideStats.hasBests`) — `on` allein ist kein Bestwert. **`on`** in `b`
  zeichnet `NavView.drawDetect` (Punkt mit Bogen links am Rand der Karte,
  in Karte, freier Fahrt und eingepasster Übersicht); **`c`** ist ein
  Hinweis für 3 s über `NavView.cue` im Platz der Einblendung, nur wenn
  keine Frage steht (`WatchCore.handle`). Text aus `AirShort`/
  `WheelieShort`, „Stoppie" als Literal. `c` steht in `EventLog.IN_T`
  (Stelle 9, Code 33) — Dart und Werkzeug lesen die Zeile mit.
  **Seit #612 (1.10.0):** Mit `s` (Ereignisbeginn als Dezimaltext)
  hat das Schild 8 s Zeit für HOCH = Stimmt und RUNTER = Nein. Frist
  und Antworttyp `ca` liegen im Kern. Die Ansicht zeichnet Pfeile und
  Antworten am linken Rand neben den beiden Tasten.
  START/LAP bleiben für die Aufnahme, und eine Routenfrage geht vor.
  Alte Handys schicken `c` ohne `s` und zeigen wie bisher 3 s.
  Der Vorführmodus gibt dem Flug in Szene 1 die Kennung (`trail.png`
  zeigt die Felder) und „antwortet" in Szene 2 per `pageKey`: Ein
  beantwortbarer Hinweis hält den nächsten Hinweis 8 s zurück und
  stünde sonst über `abseits` und `angekommen`.
  Speicher (Kettenstand `CHAIN_BIG=800`, 2026-11-13): geladen 96,6 KB
  (vorher 95,8), nach dem Wechsel 97,4 KB (96,9), Spitze 102,1 KB von
  123,8 KB — +0,8 KB, der Wechsel gleich großer Routen geht weiter.
- **Ansagen und Buddys** (1.8.0, #525/#526/#519; Konzept 1): `c` mit
  `k` „tr" (Name `n`, Grad `g`) oder „bn" (Name) geht in
  `WatchCore.cue` — kurz vibrieren, `NavView.nameCue` 4 s; das Schild
  zeichnet `shieldLine(…, ini, pill)` (dieselbe Kürzung wie die
  Infofläche), auf „angekommen" nicht. `u` legt die Liste roh ab
  (`_buddies`, Empfangszeit); `showBuddies` rechnet sie je eigenem Fix in
  den Rahmen der Ansicht (Spur in der freien Fahrt, sonst Route — ein
  Routenwechsel ändert den Rahmen) und prüft jedes Feld (falscher Typ
  beendet die App). `u` steht in `EventLog.IN_T` (Stelle 10, Code 34).
  **Speicher war die Grenze**: Die Teile kosten im Gerätebau ~2,3 KB
  (Halbierung im Vorführmodus: Zeichnen 0,5, Kern 1,1, Rest 0,7; der
  Vorführ-Zusatz selbst 0,8) — ein eigenes `nameToast` mit Kürz-Schleife
  und `setBuddies`/`buddyCount` waren 0,5 KB davon und sind wieder
  raus. Schon `main` hatte beim Wechsel zweier 800-Punkte-Routen nur
  0,2 KB über der Schwelle von `PhoneRoute.take` (4 KB + 16 B je Zahl
  frei; Kettenstand 2026-11-18: geladen 99,1, mit Aufnahme 98,8 KB), mit
  den neuen Teilen `x` mem. Betreiber 2026-11-18: Grenze 700 — geladen
  99,3 KB, Wechsel geht, Spitze 103,7 von 123,8 KB, ~2 KB Luft (Debug-Bau,
  vor der Vorgabe `-r -O 2` unten). Wer an der Uhr etwas dazubaut, misst
  zuerst mit `tool/garmin_bench.sh chain`.
- **Gebaut wird wie das Store-Paket** (`-r -O 2`, seit 1.8.0;
  `--debug` für den alten Bau, Tests `-O 2`, `GARMIN_OPT` ersetzt die
  Schalter): Bis 1.7 liefen `.prg`, Vorführmodus und Kettenstand ohne
  Optimierer und mit Debug-Infos — gemessen wurde also ein Bau, den kein
  Nutzer fährt. Vorführmodus (1000 Punkte): 110,5 KB ohne, 109,2 mit
  `-O 2`, 105,9 mit `-r -O 2`. Kettenstand mit Aufnahme: 700 Punkte
  94,8 KB (vorher 99,4), 800 Punkte 96,5 KB und der Wechsel geht wieder
  (Spitze 100,8 von 123,8 KB). Die Adressen eines Absturzes in
  `CIQ_LOG.YML` löst die `trailbuddy.prg.debug.xml` neben der `.prg` auf
  (`pcToLineNum`), die schreibt `monkeyc` auch mit `-r` — also die Datei
  des Baus aufheben, der auf der Uhr ist. Die Bilder (`garmin/shots`)
  bleiben byte-gleich.
- **Rechnen je Fix und je Bild** (1.8.0): `NavTracker.searchBlock`
  vergleicht Quadrate, die Wurzel zieht `nearest` einmal am Ende (vorher
  je Segment in der Nähe; Gegenprobe ohne die Wurzel: 5 Tests rot).
  `NavView.turn` setzt die Drehung samt `cos/mpp` und `sin/mpp` einmal je
  Bild — `sx`/`sy` multiplizieren nur noch; wer `_mpp` ändert, ruft
  danach `turn`. `seg` merkt sich das Ende des letzten Strichs auf dem
  Schirm (`_pen*`): Schließt der nächste dort an — Linien in `range`,
  die Spur der freien Fahrt —, rechnet er nur den neuen Punkt um, statt
  jeden gemeinsamen Punkt zweimal. Zurückgesetzt bei jedem Bild und jeder
  Drehung. Nicht gemacht: x/y je Punkt in eine Zahl packen (−5 Byte je
  Punkt, aber Auspacken bei jedem Zugriff im Tracker und beim Zeichnen).
  Die Bilder (`garmin/shots`) zeigen die Buddys aus dem Vorführmodus; die
  Schilder nicht (die Karte steht nur in Szene 0–2, und die tragen die
  Sprung-Hinweise) — gesehen am 2026-11-18 mit einer Wegwerf-Fassung.
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
- **Der Start wartet aufs Handy** (`wait` in `WatchCore`, Betreiber
  2026-11-06): Mit verbundenem Handy lädt `initialize` NICHT die
  gespeicherte Route, sondern einen Platzhalter, und die Ansicht zeigt
  den Lader (`NavView.setWaiting`) mit der Fassung `v<VERSION>` (#592;
  „Lade Route … %" bleibt fürs Dekodieren). `n` vom Handy heißt „Route kommt"
  (Frist 45 s je Stück), `k` „deine ist aktuell" → `loadStored`; ohne
  Antwort nach `ANSWER_MS` = 8 s auch (3 s waren zu kurz: „hallo" hin
  und Antwort zurück messen 5–7 s, 2026-11-06). Der Takt ist der EINE Timer
  des Wirts (`WatchCore.pace`: 50 ms beim Laden und Warten, 250 ms für
  eine Frist, sonst keiner; `waitStep` zeichnet ein Bild je 100 ms) —
  ältere Uhren haben nur wenige Timer. Solange gewartet wird, zählen weder
  `onPosition` noch `phoneFix` (der Platzhalter ist „fertig").
- **Das Logo des Laders** (`resources/logo/logo.json`, Test
  `loaderLogoIsOrdered`): ERZEUGT von `tool/brand_icons.py`, nie von
  Hand; je Punkt zwei gepackte Zahlen (x/y, Radius/Weg in Zehntel) —
  halb so viel Speicher neben einer großen Route. Gezeichnet als
  `fillCircle` entlang der Mittellinie, ~90 Punkte zweimal je Bild;
  `_logo` fällt weg, sobald der Lader geht.
- **Beenden** (`e`, `quit` in `WatchCore`): `QuitDelegate` ruft
  `quit()` statt `System.exit()` — erst `transmit` ans Handy, zu im
  `EndAck` (`onComplete`/`onError` → `endSent`) oder nach `END_WAIT_MS` = 5 s.
  Sofort `System.exit()` verwürfe die Nachricht. Ein `e` vom Handy gilt
  nur für `_route.id`, die gespeicherte oder die wartende Kennung.
- **Akku und Speicher** auf der Seite „Berg" nur im Vorführmodus:
  `drawMeasure` gibt es zweimal, `(:demo)` und `(:nodemo)` — der
  normale Build schließt `demo` aus, `--demo` schließt `nodemo` aus.
- **Zwei Spalten der Zahlenseiten** bei `COL_X` = 54 px um die Mitte;
  unten (y 168–194) ist der Kreis noch ~190 px breit. Lange Namen in der
  Infofläche misst `shieldLine` gegen `chord` (Kreisbreite auf der Höhe
  der Zeile), erst kleinere Schrift, dann „…".
- **Entwurf** im Designer des Betreibers (privat, Link im PR #449-G1);
  das Aussehen steht in `docs/design/README.md` Abschnitt 15.
- **Der Bench-Bau** (`tool/garmin_build.sh --bench`, `(:bench)`/`(:nobench)`
  in `TrailBuddyApp.mc`, #527): sendet wirklich (`nosim`) und nimmt über
  den Kanal Ereignisse für den Ablaufkern an — `_k` Taste/Menüpunkt, `_f`
  Fixe, `_t` Zeitsprung (die Uhr des Wirts bekommt einen Versatz), `_x`
  „diese Art nicht senden" — und antwortet mit `_s` (Stand). Menüs zeigt
  er nicht an, `_s.menu` sagt, welches stünde. Der normale Bau schließt
  `bench` aus (`monkey.jungle`); wer `now`, `send`, `menu` oder `onPhone`
  ändert, ändert beide Fassungen. Der Treiber am Handy ist
  `integration_test/watch_bench_test.dart`.
- **Drei Annotationspaare, eine Zeile** (`tool/garmin_build.sh`, die
  letzte `base.excludeAnnotations` in der Jungle-Kopie gilt):
  `demo`/`nodemo` (Vorführmodus), `testroute`/`store` (Testroute oder
  freie Fahrt ohne Route, `fallbackRoute`), `nosim`/`sim`
  (Senden über Garmin Connect oder stumm), dazu `bench`/`nobench`
  (Kettenstand). `monkey.jungle` im Repo ist der Bau für die Uhr:
  `demo;store;sim;bench`.
- **Kein `transmit` im Simulator** (`transmit` in `TrailBuddyApp`,
  Betreiber 2026-11-07): Der Simulator meldet ein verbundenes Handy, und
  ohne ADB öffnete der erste `transmit` bei jedem `--test`/`--demo`/`--run`
  den Dialog „There is no data connection", der den Lauf anhielt. Für
  Simulator-Bauten ruft `transmit` nur `ack.onError()` (seit #484 — sonst
  wartete das Beenden auf ein `EndAck`, das nie kommt; die Fahrt bleibt
  dann in der Warteschlange). Gegenprobe: vorher 21-mal „transmit
  queue full" im Testlauf, danach 0. Eine Übertragung an ein Handy im
  Simulator braucht deshalb einen Bau mit `nosim`.
- **Store-Zweig ohne Route = freie Fahrt** (`_free`, #484): GPS an,
  kein `NavTracker` (der Platzhalter läge „abseits" und vibrierte),
  `phoneFix` zählt nicht; die Ansicht zeichnet `drawFree` (Spur aus dem
  Ring `RideLog.trackX/Y`, 300 Punkte, über `seg` mit `FRAME_SEGS`) und
  auf den Zahlenseiten keinen Ring. Eine Route vom Handy löst sie über
  `swapRoute`/`loadStored` ab. Der Schlüssel des Store-Pakets bleibt für
  immer derselbe — mit einem anderen nimmt der Store kein Update an
  (Sicherung: `docs/garmin-store.md`).
- **Die Fahrt auf der Uhr** (`source/RideLog.mc`, #484, Konzept 2a):
  `onPosition` gibt JEDEN eigenen Fix an `_log.add` (alle 5 s ein Punkt,
  ob Navigation oder freie Fahrt; die Position des Handys nie) — genommen
  wird er erst nach `start()` und nicht in der Pause (siehe „Aufzeichnung
  an der Uhr"). Stücke zu
  60 Punkten unter `w<id>_<k>`, das offene alle 12 Punkte neu mit `wo`;
  `RideLog.recover()` in `initialize` nimmt eine abgebrochene Fahrt in die
  Warteschlange `rq`. `finish()` in `closeDown` UND `onStop` (dort ein
  No-op, wenn schon beendet). Gelöscht wird NUR in `RideLog.ack` mit
  `id.equals(…)` — Gegenprobe 2026-11-07: ohne den Vergleich ist
  `rideLogDeletesOnlyOnAck` rot. Das Senden (`startUpload` →
  `sendRidePart` → `RideAck` → `rideSent`) geht Nachricht für Nachricht;
  beim Beenden stellt `armExit` die EINE Frist `exitAt` je Nachricht neu
  (`RIDE_WAIT_MS` = 20 s), ZURÜCK schließt sofort (`closing()`). Nicht
  senden, solange `_wait`/`_pendingId` (eine Route kommt). Die Spur der
  Ansicht ist ein eigener Ring, nicht die Stücke — gelesen wird aus dem
  Speicher nur beim Senden, Stück für Stück. Speicher im Simulator ohne
  Route: 56 KB von 124 KB (2026-11-07). Die Grenze `MAX_POINTS` = 6000
  ist ein Startwert bis zur Messung 8.6.
- **Unit-Tests auf allen Uhren des Manifests**: je Uhr den Simulator neu
  starten (nach einem Gerätewechsel schrieb `monkeydo` sonst nichts) und
  `GARMIN_DEVICE=<id> tool/garmin_build.sh --test`. Bilder der Uhr kommen
  aus dem Container (`tool/garmin_sim.sh shot`, siehe „Der Simulator im
  Container"); vom Mac-Simulator nur mit entsperrtem Schirm und nur vom
  Fenster (`screencapture -l <Fenster-ID>`, ungeprüft), nie vom ganzen
  Schirm.
- **Aufzeichnung an der Uhr** (Konzept-Garmin 0.6 und 1, Betreiber
  2026-11-07, „wie Garmin"): `NavDelegate` ruft `startKey`/`backKey`/
  `menuKey` des Ablaufkerns; START → `RideLog.start/pause/resume` (Stände `IDLE`,
  `RECORDING`, `PAUSED`), in der Pause das `Menu2` Weiter · Speichern ·
  Verwerfen (`MenuDelegate(:pause)`, Verwerfen fragt über
  `DiscardDelegate`), ZURÜCK = LAP → `RideLog.mark` (−1 ohne Punkt: „Warte
  auf GPS"), nach „Trail endet" Behalten · Verwerfen
  (`MenuDelegate(:trail)`, ZURÜCK behält). `closeDown(tellPhone, keep)`:
  `keep` false → `RideLog.discard`. `RideStats.counting` hält Strecke,
  Fahrzeit und bergauf vor START und in der Pause an. Marken unter
  `m<id>`, `drop` löscht sie mit; die erste Nachricht der Fahrt trägt
  `m`. Ans Handy `rs`, `rt` (nur beim Behalten), `re` (nur wenn START
  gedrückt war) — `test/garmin/watch_ride_test.dart` hält die Zeilen mit
  Dart zusammen. Gegenprobe 2026-11-07: ohne `!_active` in `add` und ohne
  `storeMarks` zwei Tests rot. Die Tasten im Mac-Simulator ließen sich
  von hier nicht drücken (Klick und Enter über System Events kamen nicht
  an) — die Abläufe prüft deshalb der Ablaufkern (`CoreTests.mc`). Im
  Container gehen sie (`tool/garmin_sim.sh press`, #533); am Gerät bleibt
  nur, ob die echten Tasten diese Wege nehmen.
- **Freie Fahrt fragt wieder** (`HELLO_AGAIN_MS` = 30 s, höchstens 20-mal,
  in `onPosition` vor der Qualitätsprüfung): Feldbefund 2026-11-07, Runde
  vom Handy, die Uhr blieb in der freien Fahrt (Konzept 8.8). Das Handy
  antwortet nur, wenn es einer Navigation folgt; sonst bleibt es still.
- **Der Ablaufkern** (`source/WatchCore.mc`, #508, Prüfleiter S2):
  Tasten, Menüs, Fristen und Nachrichten stehen dort; `TrailBuddyApp`
  ist nur der Wirt (`now`, `pace`, `connected`, `send`, `vibrate`,
  `menu`, `exit`, `gps`, `fallback`, `newView`, `compass` —
  gerufen ohne Typ, damit `FakeHost` in `CoreTests.mc` dieselben Namen
  nimmt). Die Delegaten rufen `watchCore()`. **Kein Timer im Kern**: jede
  Frist ist ein Zeitpunkt (`swapAt`, `exitAt`, …), `tick()` vergleicht
  ihn mit `now`; jedes Ereignis holt `now` vom Wirt. Ein Test stellt
  `FakeHost.t` vor und ruft `tick()` (`TestCore.run`). **Nach dem
  Wechsel der Route endet der Takt** (`tick` → `swapRoute`, `return`):
  Dekodierte er gleich weiter, hielte die alte Ansicht noch die alte
  Route — „Out of Memory" bei 1000 Punkten (Vorführmodus 2026-11-11,
  Fall 508.9; Gegenprobe: ohne das `return` ist
  `coreAsksThenTakesAfterDeadline` rot). Wer einen Ablauf ändert,
  schreibt erst das Ereignis-Skript. Messung 2026-11-11: Code +320 Byte
  im Release-Bau (Grenze aus #508: 2 KB).
- **Der Gesprächskatalog** (S3, #509; Konzept 12.2): Die Gespräche
  zwischen Handy und Uhr stehen in `docs/watch_cases.json`
  (`gespraeche`); `source/GeneratedTalks.mc` ist ERZEUGT
  (`python3 tool/watch_talks.py`, danach `tool/generated_assets.py
  --update`), nie von Hand. Der Spieler `TestTalk` (`CoreTests.mc`)
  tickt im Takt, den der Kern beim Wirt verlangt (`FakeHost.paceMs`) —
  mit festen 250 ms wie `TestCore.run` war eine Route nach 500 ms noch
  halb dekodiert, und ein Neustart verwarf sie über `loading`.
  Fehlermeldungen nennen Schritt, gesendete Arten und den Stand des
  Kerns. **`has` ist in Monkey C ein Schlüsselwort** (`obj has :sym`) —
  eine Funktion dieses Namens bricht den Bau mit „extraneous input".
- **Ein „schick" während des Wartens** (`_uploadLater` in `WatchCore`,
  Fall 509.7): `startUpload` darf nicht senden, solange eine Route kommt
  (`wait`, `pendingId`) — bis #509 verfiel das `wq` dann, die Fahrt ging
  erst beim nächsten Start. Jetzt merkt der Kern es sich und sendet am
  Ende von `loadStep`. Gegenprobe 2026-11-12: ohne das ist
  `talk_fahrt_wartet` rot.
- **Eine Taste, eine Bedeutung** (#513, E2 vom 2026-11-12): Bei einer
  Frage (`asking()` im Kern) heißt START ja (`swapAt = now`, Wechsel im
  nächsten Takt wie nach der Frist) und ZURÜCK nein — beides vor jeder
  anderen Bedeutung der Taste (`answerAsk`). Das Schild zeichnet
  `NavView.drawAsk` (Frist als Balken, JA rechts oben an START, NEIN
  rechts unten an ZURÜCK); groß „START = JA" nur bei der ersten Frage
  (`askSeen` im Speicher). Langes HOCH → `menuKey` → `menu(:action)`;
  die Punkte liefert `WatchCore.actions()` (nur, was gehen kann), damit
  sie ohne Gerät prüfbar sind. „Route beenden" (`endRoute`) schickt `e`,
  verwirft die gespeicherte Route und fährt frei weiter;
  `RideStats.carryFrom` hält Strecke, Zeit und bergauf über jeden
  Routenwechsel (vorher fingen sie bei einem Wechsel von vorn an). Der
  Zoom von selbst ist `NavView.autoZoom` (rein, mit Hysterese); eine
  Stufe von Hand gilt, bis `nextSection` einen anderen Trail nennt.
  Gegenprobe 2026-11-12: START = nein, ohne `carryFrom`, ohne die
  Hysterese hinaus und ohne den Rücksprung des Hand-Zooms ⇒ fünf Tests
  rot (`coreStartTakesNewLine`, `talk_frage_start_ja`,
  `coreEndRouteKeepsRecording`, `autoZoomHysteresis`,
  `manualZoomHoldsUntilHead`).
- **Speicher im Gerätebau** (#513, Vorführmodus 2026-11-12, 1000
  Punkte): Jede Funktion, Klasse, Konstante und jeder Text kostet im
  Debug-Bau (Gerät und `--demo`, ohne `-O`) dauerhaft Speicher neben der
  Route. #513 kam erst auf +3,4 KB (98,1 → 101,5 KB) und stürzte beim
  Wechsel nach der Frage im Lader ab (`drawLoader` lädt das Logo). Darum:
  ein `MenuDelegate(kind)` statt vier Klassen, Zoomstufen als Meter
  statt Wörter, die Schwellen von `autoZoom` als Zahlen statt
  Konstanten — jetzt 100,4 KB. Die eigentliche Ursache war die Spitze:
  WatchUi gibt die alte Ansicht erst nach dem nächsten Bild frei, und sie
  hielt ihre Route — deshalb lässt `swapRoute`/`endRoute` sie vorher
  über `NavView.forget(Platzhalter)` los. Gegenprobe: ohne `forget`
  Absturz beim Wechsel, mit ihm läuft er durch. `--demo --points 2000`
  stürzt schon auf `main` (0.168.3) beim Laden der Testroute ab
  (`fallback` → `fromDict`); die Grenze 2000 gilt für eine Route vom
  Handy, die stückweise kommt, nicht für die Testroute als Ressource.
- **Der Simulator im Container** (S1c, #533, `tool/garmin_sim.sh`; Bild
  in `tool/garmin_sim.Dockerfile`, per Digest festgenagelt): der
  Linux-Simulator unter Xvfb, das Bild direkt aus dem Bildspeicher
  (`-fbdir`, XWD → PNG über `tool/xwd_png.py`) — geht bei gesperrtem
  Mac, ohne SDK und ohne Schlüssel des Betreibers (der Container baut mit
  einem Wegwerf-Schlüssel). Das Bild ist von einem Dritten (SDK 9.2.0,
  der Mac hat 9.3.0): ein Unterschied zwischen beiden Simulatoren ist ein
  Befund. Was dort gilt (gemessen 2026-11-12):
  - **Tasten = Klicks aufs Gerätebild.** Lage der Tasten aus
    `simulator.json` des Geräts (`keys`), Lage des Gerätebilds im
    Bildschirm einmal je Start gesucht (`xwd_png.py --find`); langes HOCH
    ist der Eintrag `menu` (`isHold`), 1–2 s gedrückt. `xdotool key` ist
    kein Ersatz: `Return` und `Up` taten nichts.
  - **Sprache** steht in `/root/.Garmin/ConnectIQ/simulator.ini`
    (`Language=7` Deutsch, `4` Englisch) und wirkt beim Start des
    Simulators — kein Menüklick. **Konsole** nur mit `LANG=C.UTF-8`
    richtig (sonst `???` statt `→` und Umlauten; das Dockerfile setzt es).
  - **Port:** Startet der Simulator neu, solange 1234 noch belegt ist,
    lauscht er auf dem nächsten (bis 1238); `monkeydo` findet ihn dort.
  - **Menüleiste:** Einträge ohne Untermenü gehen über
    `garmin_sim.sh menu` (Tabelle im Skript, Zeilen 25 px, nur für das
    festgenagelte Bild); Untermenüs nicht. Xvfb ist 1200 px hoch, sonst
    rutscht „Settings" nach oben.
  - **Was `shots` nicht erreicht:** die eingepasste Übersicht (#498) —
    Szene 4 des Vorführmodus liegt hinter „angekommen", und die
    Zusammenfassung bleibt stehen; eine echte Tastenfolge mit Route vom
    Handy, GPS aus einer Datei (Simulation → Activity Data öffnet einen
    Dialog), die Kette über adb (#527, noch ungemessen).
  - **Bilder sind gleich** zwischen Läufen (Bytes, 28 von 28), wenn der
    Stempel fest ist (`GARMIN_STAMP` in `garmin_build.sh`) und jeder Lauf
    mit leerem App-Speicher beginnt (`run --fresh`; sonst steht „START =
    JA" nur beim ersten Mal). Nicht verglichen: Lader, „Berg" (Uhrzeit),
    Frage (Frist als Balken). **Referenzen** in `garmin/shots/` (Betreiber
    2026-11-12), nur von der Testroute: Wer das Zeichnen oder einen Text
    der Uhr ändert, fährt `tool/garmin_sim.sh shots --update` und
    committet die Bilder mit; `garmin_bench.sh all` vergleicht.
  - **Takt:** Eine Umwandlung XWD → PNG und jeder Python-Aufruf kosten
    unter Rosetta gut 1 s — `shots` kopiert im Moment nur den Bildspeicher
    und hält die Tastenlagen im Zwischenspeicher, sonst rutscht ein Bild
    in die nächste Szene. „abseits" holt die Karte nach vorn
    (`leftRoute`), auch von einer Zahlenseite.
  - **Befund A** (#533): Eine `.prg` vom Mac (SDK 9.3.0) läuft im
    Container gleich (100,4 KB im Vorführmodus, über den Routenwechsel);
    der Container-Bau (9.2.0) belegt ~0,7 KB weniger. Der „Out of
    Memory" vom Spike kam von einer `.prg` vor dem `forget`-Fix aus #513.
- **Der Ereignis-Rekorder** (`source/EventLog.mc`, #510, T4): je
  Ereignis EINE Zahl `(Code << 24) | Sekunden seit Start`, Code =
  `Art << 3 | Detail`; die Tabelle steht als Kommentar in `EventLog.mc`,
  in `tool/garmin_events.py` (`KINDS`) und in
  `lib/features/garmin/watch_events.dart` — `test/garmin/watch_events_test.dart`
  liest `IN_T`/`OUT_T`/`SIZE` aus der `.mc`-Datei. Aufgezeichnet wird im
  Kern über `ev(code)` mit **Zahlen statt Konstanten**: Die erste Fassung
  mit Konstanten und String-Arrays kostete im Vorführmodus +5,0 KB
  (99,6 → 104,6 KB, 1000 Punkte), die jetzige +3,45 KB (→ 103,1 KB):
  Ring 0,6 KB, 25 Aufrufstellen ~1,1 KB (rund 44 Byte je Aufruf im
  Debug-Bau), der Rest Code des Moduls. Gemessen im Container mit einer
  vorübergehenden Zeile `System.getSystemStats().usedMemory` im
  Vorführmodus; der Routenwechsel lief durch. Ein Fix steht nur, wenn
  seine Klasse wechselt (`fixEv`), Nachrichten nach ihrer Stelle in
  `IN_T`/`OUT_T` (`msgCode`). „evr" steht, solange die App läuft — steht
  es beim Start noch, wird „ev" zu „evc" (Absturz-Ring fürs „hallo",
  weg nach `n`/`k`/`wq` oder dem nächsten sauberen Ende); eine Fahrt
  nimmt den Ring als „ev_<id>" mit, `RideLog.drop` löscht ihn mit.
  `TestReplay.play` spielt einen Ring gegen einen frischen Kern:
  Eingaben werden gespielt, Folgen (Art 5, 6, 8, 10) abgewartet, alle
  5 s ein Fix der zuletzt gesehenen Klasse. Gegenprobe 2026-11-12: Ring
  ohne Deckel, Fix ohne Wechselprüfung, Wiedergabe ohne START ⇒
  `eventsRingHolds120`, `eventsFixOnlyOnChange`,
  `eventsReplayPauseDiscardNo` rot. **In einem `module` gibt es kein
  `hidden`** (Bau bricht mit „extraneous input 'hidden'").
  **Gespeichert wird bei Start, Taste und Menüpunkt** (`code < 24`), sonst
  alle 5 min: Nur alle 5 min hätte ein Absturz in den ersten Minuten
  nichts hinterlassen (der Kettenstand fand es). Gegenprobe: ohne die
  Bedingung ist `eventsCrashRingInHello` rot.
- **Der Kettenstand prüft das Protokoll** (#510, `tool/garmin_bench.sh
  chain`): `ev` an der Fahrt heil über Kotlin und SDK, Neustart nach
  sauberem Ende ohne, echter Absturz (`_z`: Index außerhalb) mit Ring im
  „hallo", nach `k` wieder ohne. Ein Neustart der Uhr-App ist ein
  **Neustart des ganzen Simulators** samt „adb Connection → Start" (Zeile
  `BENCH relaunch`, das Skript sieht sie) — ein zweites `monkeydo` im
  laufenden Simulator schreibt nichts und lädt nichts. Der Speicher der
  App bleibt dabei, wenn der Treiber vorher `_r` (oder `_z`) schickt:
  Merker `benchKeep` mit Zeit, gilt 2 min — ein alter aus einem
  abgebrochenen Lauf ließ sonst den nächsten mit altem Speicher beginnen.
  **Fixe mit Abstand zu `RideLog.MIN_POINTS`**: Mit 40 Fixen kamen mal 24,
  mal 23 Punkte an, und die Uhr verwarf die Fahrt still als zu kurz
  (zweimal „Fahrt hinüber FEHLT" ohne Fehler im Log); jetzt 60.
- **Speicher neben der größten Route im Kettenstand** (#510,
  2026-11-13): `_s` meldet `mem`, `peak` (je Takt gemessen, `(:bench)
  onTick`) und `tot`; der Treiber schickt am Ende eine Zickzack-Route mit
  `kWatchMaxPoints` Punkten samt Höhen, startet die Aufnahme und wechselt
  während der Fahrt auf eine zweite gleich große. `CHAIN_BIG=N
  tool/garmin_bench.sh chain` fährt nur diesen Teil mit N Punkten (gleich
  nach dem „hallo"); eine Ablehnung schreibt der Treiber mit Grund
  (`BENCH abgelehnt: mem`). **Genau N Rohpunkte schicken**: Mit mehr als
  `kWatchMaxPoints` verdoppelt `watchRouteOf` die Toleranz, und das
  gleichmäßige Zickzack fiel auf 23 Punkte — der erste Lauf war grün und
  hatte nichts gemessen. Gemessen (Bench-Bau, 123,8 KB für die App):
  | Punkte | Laden | belegt (Spitze) | Wechsel gleich groß |
  |---|---|---|---|
  | 2000, 1750 | „Out of Memory" in `PhoneRoute.get` — **auch auf `main` ohne Ring** | – | – |
  | 1500 | geht | 109,9 KB (112,6) | `x` mem |
  | 1250 | geht | 104,9 KB (111,1) | `x` mem |
  | 1000 | geht | 99,4–99,8 KB (102,4–106,2) | `x` mem |
  | 800 | geht | 95,8 KB (102,3) | geht, 96,9 KB |
  Der Ring kostet neben einer Route mit 1500 Punkten 4,2 KB (`main`
  105,7 KB, Spitze 108,9). Die Grenze der App sinkt deshalb auf 800
  (Betreiber, 2026-11-13); `x` mem ist der Schutz in `PhoneRoute.take`
  (4 KB + 16 B je Zahl frei), die alte Route bleibt.
- **Layoutzahlen aus EINER Quelle** (#511, S4): `tool/watch_layout.json`
  hält jede Lage, jeden Radius und jede Schriftstufe von `NavView.mc` und
  `Ring.mc` (240 px). In der `.mc` steht davor eine Marke `/*L:name*/`
  bzw. `/*F:name*/Graphics.FONT_…` — ein Kommentar statt einer Konstante,
  weil jede Konstante im Debug-Bau Speicher kostet. Wer eine Zahl ändert,
  ändert die JSON und läuft `python3 tool/watch_layout.py` (schreibt die
  Werte hinter die Marken); CI prüft mit `--check`, der Dart-Test auch.
  Eine neue Lage oder ein neuer Text in der Ansicht bekommt eine Marke
  und einen Eintrag, sonst sieht ihn das Abbild nicht.
- **Das Abbild der Ansicht** (`test/garmin/watch_twin.dart`, Test
  `watch_twin_test.dart`): zeichnet die Ansicht aus der JSON und den im
  Simulator gemessenen Schriftmaßen (`tool/watch_fonts/<gerät>.json`,
  `tool/watch_fonts.sh`: Unit-Test mit `getTextWidthInPixels` je Zeichen
  in einem eigenen kleinen Projekt — die Uhr-App bleibt unberührt). Fünf
  Geräte: fēnix 5S (218), 5 und 6S (240, Manifest), 6 (260), 6X Pro
  (280); andere Größen = Werte × Breite/240 (`overrides` je Breite gehen
  vor). Gemessen 2026-11-15: keine Unterschneidung (Satz = Summe der
  Zeichen), die Buchstaben stehen von Höhe − Ascent + 1 bis zur
  Grundlinie (Referenzbilder der fēnix 5); die 6S hat bei 240 px
  dieselben `tiny`/`small`/`large` wie die 5, aber ein kleineres `xtiny`
  (19 statt 26 px hoch, die Frage 166 statt 216 px breit) und
  `FONT_NUMBER_MEDIUM` 68 px mit Ascent 50. Je Gerät und Sprache ein Bogen aller Bilder
  (bildpunktgenau verglichen, selbst gerastert ohne Glättung — Skia
  rastert auf Mac und Linux nicht gleich) und ein Bericht, was nicht
  passt (`watch_twin/<gerät>.txt`, auch ein Golden). Nachziehen:
  `flutter test --update-goldens test/garmin/watch_twin_test.dart`. Wer
  die Ansicht in Monkey C ändert, zieht das Abbild mit; was der
  Simulator wirklich zeichnet, vergleichen weiterhin `garmin/shots`.
  Gefunden beim Bau: der Trailname maß gegen den Kreis der Anzeige statt
  der Karte (jetzt `MAP_R` auf Höhe der Grundlinie), die Frage war in
  `small` 250 px breit (jetzt `xtiny`) — beide behoben. Die übrigen fünf
  Befunde auf 240 px entschied der Betreiber am 2026-11-16 (#555) an
  Variantenbildern aus einer Kopie des Abbilds (Werte und Schalter
  überschrieben, Buchstaben aus `img.arial*` in die gemessenen Zellen
  skaliert — lesbar genug zum Entscheiden): Infofläche ab 160, ab 10 km
  ohne Nachkomma, freie Fahrt mit der Zeit in Zeile 1, „angekommen" ohne
  „N Trails" mit zweizeiligen Bestwerten, vor START unten nur ein grauer
  Punkt, kein „Speicher voll" auf „Fahrt", Frist-Balken 128. Seitdem sind
  die Berichte aller fünf Größen leer. Gelernt: Am unteren Rand zählt
  jeder Pixel Höhe doppelt — bei y 207 sind innerhalb `MAP_R` noch
  ~130 px frei, bei y 217 nur ~70.
- **Zeichen statt Wörter** (#558, 1.7.0): Die Geometrie der 13 Zeichen
  steht in `tool/watch_layout.json` (`symbols`), `tool/watch_layout.py`
  erzeugt `source/Symbols.mc` (nie von Hand, `--check` in CI); in
  `NavView.mc` steht vor der Nummer eine Marke `/*S:name*/`. Das Abbild
  zeichnet dieselben Befehle (`WatchTwin.sym`). **Speicher**: Je Zeichen
  gerade Zeichenbefehle kosteten im Vorführmodus +5 KB (101 → 106 KB, Seite
  „Berg", fēnix 5, 1000 Punkte) — jede Anweisung bleibt im Debug-Bau
  dauerhaft im Speicher. Deshalb je Zeichen EINE Zeichenkette (Art, Farbe,
  Zahlen als Zeichen ab „0") und ein kleiner Leser: +2 KB (103 KB). In
  einem `module` gibt es kein `hidden` (Bau bricht mit „extraneous input").
  `fillPolygon` verlangt `Array<[Numeric, Numeric]>`, kein
  `Array<Array<Number>>`. Die Zelle einer Zahlenseite ist EINE Zeile
  (`symCell`): Zeichen, 2 px, Wert in `FONT_MEDIUM`, Einheit klein auf
  derselben Grundlinie; 2 px statt 4, sonst reichte „23:59" auf der
  fēnix 5S über den Kreis. Offen: Lesbarkeit von Flugzeug (16 px) und
  Wegweiser/Fahne in der Sonne am Gerät, Kettenstand für den Speicher
  neben der größten Route.
  **Review 2026-11-16** (drei Befunde, erst im echten Simulator sichtbar):
  `drawCircle` bleibt auf der fēnix 5 trotz `setPenWidth(2)` 1 px dünn —
  ein Ring („o") ist deshalb ein gefüllter Kreis mit schwarzem Innenkreis
  (Zeichen stehen nur auf Schwarz). Das ▶ an der START-Taste liegt auf
  demselben Radius wie das „N": `drawNorth` weicht vor START und bei einer
  Frage 34 px nach innen aus. Der Vorführmodus schickt Bestwerte und in
  Szene 1 und 2 einen Hinweis (nur auf der Karte, nicht in Szene 0 — von
  dort blättert `shots` auf die Seiten), `shots` nimmt „spruenge" mit:
  Vorher sah Flugzeug, Wheelie, Stoppie und „×" nur das Abbild.
- **Die Ablage** (#515, 1.9.0; Konzept 2b): vier Fächer `s0`–`s3` für
  höchstens drei Routen (`SHELF_MAX`), die Liste `sl` je `[id, Fach, Name,
  Meter, bergauf]`, ein Stück mit `sh` geht nie in `cur`. Vier Fallen, je
  im Bau gefunden:
  - **`rp` trägt nur das erste Stück.** Das Fach merkt es sich unter
    `<fach>m` (mit Name, Länge, bergauf), und `shelfSlotFor` sucht ZUERST
    das Fach mit derselben Kennung, erst dann zählt „voll" — sonst sagte
    das zweite Stück einer Ersatzroute `x full` (`shelfFullAsksReplace`).
  - **`release` statt `clear`**, wo eine Route ihr Fach aufgibt (neue
    Route der Navigation, `drop`, `useShelf`): Ein Fach der Ablage bleibt.
    Aus der Ablage nimmt nur `unshelve` — beim Absturz (`CrashGuard`), bei
    `loading` beim Start, bei einer Route, die sich nicht dekodieren ließ,
    und auf `sd`. Gegenprobe 2026-11-18: `release` → `clear`, ohne
    `unshelve` beim Absturz, `sh` ohne `return` ⇒ `shelfSurvivesNavRoute`,
    `shelfSurvivesRestart`, `shelfTakesWithoutSwap` rot.
  - **Die Antwort ist `sh`, nicht `ok`**: `WatchSync` hört `ok` für seine
    Route, die Ablage `sh` (`lib/features/garmin/watch_shelf.dart`); das
    Handy schickt `sh` nur an `ver` ≥ 1.9.0 (`watchKnowsShelf`).
  - **Im Gespräch ist ein Wert ein Beispiel**: `l: []` im `sh` der Uhr
    kam beim Handy als leere Ablage an — das Gespräch „ablage" trägt
    deshalb einen Eintrag mit `$s`.
  Speicher (Kettenstand 2026-11-18, `CHAIN_BIG=700`): mit Aufnahme
  97,9 KB (vorher 94,8), Spitze 104,5 von 123,8 KB, der Wechsel geht. Die
  Ereignis-Art 11 „Ablage" (Code 88) speichert den Ring sofort wie eine
  Taste (`code >> 3 == 11` in `EventLog.rec`); Art 2 war voll.
  Handy-Seite: Aufträge in `rides/watch_shelf.json` (nicht in den
  Einstellungen — Haustür), gesendet beim „hallo", gelöscht erst mit `sh`;
  `put` mit laufender Uhr-App, deren „hallo" vor dem Lauf der App kam,
  fragt `q`. Der Harness hängt `MemoryWatchShelfStore` ein.
