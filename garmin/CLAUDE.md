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
  Simulator über adb; `chain --break` muss rot werden). Wer hier einen Ablauf ändert, trägt erst den Fall ein und hängt
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
  Uhr: die `.prg` per USB nach `GARMIN/APPS/`. CI baut die Uhr-App nicht (SDK nur mit Garmin-Anmeldung);
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
  Memory" schon beim Laden (damals lagen rohe Daten und Felder kurz
  zusammen — seit 2026-11-05 nicht mehr, nachzumessen). Mit Ring und
  Seiten 76 KB bei 2000. **Überholt**: Neben dem heutigen Code stürzen
  2000 Punkte vom Handy beim Laden ab (Kettenstand 2026-11-13, `CHAIN_BIG`
  in `tool/garmin_bench.sh`); die Grenze `kWatchMaxPoints` ist seit
  0.169.1 800 — die größte, bei der die Uhr während der Fahrt noch eine
  zweite gleich große Route annimmt (Messwerte bei „Speicher neben der
  größten Route", #510).
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
  den Lader (`NavView.setWaiting`). `n` vom Handy heißt „Route kommt"
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
