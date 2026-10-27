# TrailBuddy — Arbeitsregeln für `lib/features/routing/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Die Routing-Engine, Schritt 3: Graph, Profil, Suche** (seit 0.70.0,
  `lib/features/routing/`, Konzept-Routing 2.1–2.4, 2.7, 3.1; Port von
  `tool/route_measure.py`, mit dem die Engine gemessen wurde). Fünf
  Dinge, die man wissen muss:
  - **Das Werkzeug ist die Referenz, Zahl für Zahl.** `route_profile.dart`
    spiegelt `PROFILES`/`CLASSES`/`classify`/`edge_time_s`/`edge_cost_s`;
    `test/routing/route_profile_test.dart` hält die im Werkzeug
    gerechneten Kosten (elf Fälle) auf 1e-5 fest. Wer dort eine Zahl
    ändert, ändert sie hier im selben PR — sonst plant die App etwas
    anderes, als gemessen wurde.
  - **Die drei Graph-Regeln aus M1 stehen in `buildRoadGraph`**:
    Zuschnitt jeder Kachel auf ihren Rahmen (`clipToTile`, Liang–Barsky;
    der Puffer legte Wege doppelt), tote Enden ≤ 2 m an den nächsten
    ANDEREN Weg (die eigene Kante liegt bei Abstand 0 — ohne Ausschluss
    wird jeder T-Knoten übersprungen), Kreuzungen ohne Knoten nur auf
    derselben Ebene (`is_bridge`/`is_tunnel`). Einbahn gilt nur auf
    Straßenklassen (`WayClass.isRoad`).
  - **Der Test-Helfer rechnet Meter über DIESELBE Projektion wie der
    Graph** (`FlatProjection`, R = 6 371 km). Mit 111 320 m je Grad
    waren „1 000 m" im Graphen 998,9 m — fünf Tests rot um ein Promille.
  - **Höhen je Kante über `profileAlong` und `edgeClimb`** (`addClimbs`);
    eine Kante ohne Höhe bleibt flach und zählt (`edgesWithoutHeights`,
    `PathSummary.heightsComplete`). **Nicht `hysteresisClimb` allein**
    (bis 0.108.3): Die 10 m Hysterese sind für eine ganze Linie gemessen;
    je Kante verschluckten sie jede Kante darunter, und „Route hierher"
    zeigte 0 hm bergauf und bergab über einem steigenden Profil — samt
    zu kurzer Zeit und einem Planer, der sanfte lange Anstiege nicht ins
    Höhenbudget zählte. `edgeClimb` gibt den Rest bis zur letzten Probe
    dazu (Anstieg − Abstieg = Höhenunterschied der Kante), Spiegel
    `edge_climb` im Werkzeug; Test mit 16 Stücken zu 6 m in
    `road_graph_test`, Gegenprobe rot. Zahlen in
    `docs/routing-messung.md` von vor 0.108.4 sind mit der alten Zählung
    gerechnet. Dabei gefunden: Ein Punkt genau auf
    einer Kachelkante landet je nach letztem Bit in der Nachbarkachel,
    auch nördlich/westlich — `heightAt` liest seither die Nachbarn an
    BEIDEN Rändern.
  - **`loadRoadGraph` ist `loadRoads` für den Graphen**: dieselbe
    Deckungsregel (`partial` ⇒ kein Graph), Höhen aus dem Leser der
    Bereiche. Der Graph rechnet in Metern um die Mitte des Rahmens.
  Das Fahrerprofil (`RiderProfile`, `Settings.riderProfile`, Vorgabe
  Bio) steht im Profil als Seite „Fahrerprofil"; jede Fahrt merkt es
  sich beim Start im Kopf der Datei (`Ride.profile`).
- **Steile Anstiege** (#194, seit 0.80.0; Konzept-Routing 2.4,
  `docs/routing-messung.md`): Je Kante die Höhenmeter über
  `kSteepGrade` (15 %), in beide Richtungen (`GraphEdge.steepUp/
  steepDown`, `steepExcess` über `HeightReader.profileAlong`); sie kosten
  ihre Steigzeit noch einmal mal `WayClass.steep` (3 unbefestigt, 1
  Asphalt, 0 Stufen), als KOSTEN, nicht als Zeit. Drei Dinge, die man
  wissen muss:
  - **Höhen UND Positionen werden geglättet** (drei Proben): Der letzte
    Schritt einer Kante ist der Rest nach den vollen 50 m; nur die Höhen
    zu glätten legte dort einen ganzen Anstieg auf einen Meter (im Test
    gefunden). Ohne Glättung zählte das Rauschen des 90-m-Modells doppelt
    so viele Höhenmeter (Tirol-Lauf).
  - **Uphill-Trails und Verbinder tragen keinen Aufschlag**
    (`edgeCostFrom`); `PathSummary.steepM`/`LoopSummary.steepM` zählen
    nur, was der Aufschlag nicht vermeiden konnte, `steepNote` sagt es
    ab `kSteepNoteMinM` (5 hm) — ohne Zahl.
  - **Spiegel des Werkzeugs** (`STEEP_*`, `steep_excess`, `steep_cost_s`
    in `tool/route_measure.py`, Testvektoren in `route_profile_test`);
    `splitEdge` teilt die steilen Meter nach Länge wie die Höhen.
  **Seit 0.81.0 kostet das Gewicht, nicht die Schwelle** (#188):
  `steepWeight` (`GraphEdge.steepWUp/steepWDown`) zählt jeden Höhenmeter
  mal `steepWeightAt` seiner Steigung — ab 10 %, exponentiell (×3–4 je
  fünf Punkte), gedeckelt bei 30. Die 15 % bleiben, was `steepNote`
  „steil" nennt; zwei Felder je Kante, weil Anzeige und Kosten
  verschiedene Fragen beantworten.
- **Vorlieben und verschenkte Höhe** (#188, seit 0.81.0; Konzept-Routing
  2.4): `RoutePrefs` (Straßen, Wanderwege bergauf, steile Rampen; je
  meiden/egal) steht in `LoopPrefs.route` und kommt über
  `RiderParams.prefs` in die Kosten — `withPrefs` legt sie über das
  (kalibrierte) Profil, Planer und „Zum Trailkopf" lesen dieselben
  gemerkten Schalter. Vier Dinge, die man wissen muss:
  - **„Egal" ist nie null** (`kPrefAny*`: 35 % des Aufschlags über 1,
    30 % des Steil-Gewichts) — sonst nähme die Route bei gleicher Zeit
    die Hauptstraße statt des Forstwegs.
  - **Die Vorlieben gehören in den Schlüssel des Suchspeichers**
    (`_riderKey`): Wer umschaltet, rechnet neu; der Speicher hielte sonst
    Suchen mit den alten Kosten.
  - **Bergab auf einer Wegekante kostet `kDescentCost` (0,3) der
    Steigzeit**, auf Trails (`GraphEdge.trail`) und Verbindern nichts
    (`edgeCostS(descent:)`). Ein Test hält die Ausnahme fest, die
    Gegenprobe ist rot.
  - **Spiegel des Werkzeugs**: `PREF_*`, `pref_strength`,
    `DESCENT_COST`, `steep_weight` in `tool/route_measure.py`; die
    Zahlen in `route_profile_test` sind dort gerechnet.
- **Der Stil „Bequem"** (#329, seit 0.127.0; Konzept-Routing 2.4,
  Messung in `docs/routing-messung.md`): dritter `RouteMode` im Blatt
  „Zum Trailkopf"/„Route hierher" und `NavChoice.easy` am Navi-Symbol —
  NUR die Anfahrt; im Planer seit 0.129.0 als Stil der Route OHNE
  gewählten Trail (#356, siehe „Die Route von A nach B"), seit 0.131.0
  auch mit Auswahl und als Schalter „Bergauf bequem" der Runde (siehe
  „Stile mit Auswahl"). Drei Dinge, die man wissen muss:
  - **Ein Stil, kein Rad**: `RoutePrefs.easy`, vom Blatt je Rechnung über
    die gemerkten Vorlieben gelegt (`_rider`), nie gemerkt. Er ersetzt
    nur KOSTEN (`WayClass.easy`, `kEasyClimb`, `kEasySteep`, `kEasyWay`);
    Zeit und Kalibrierung bleiben die des Rads. Weil `prefs` im
    Schlüssel des Suchspeichers steht, rechnet ein Wechsel neu.
  - **Steil auf Asphalt kostet im Stil wie unbefestigt**: Mit dem Faktor
    1 der MTB-Tabelle wich der Stil auf steile Straßen aus und stieg im
    Tirol-Lauf mehr als der MTB-Stil.
  - **Spiegel des Werkzeugs** (`EASY_*`, `is_easy`, `easy_climb_cost_s`,
    `steep_cost_s(easy=)`, Vergleich `easy_comparison` im Tirol-Bericht);
    Vektoren in `route_profile_test`, die Umweg-Suche in
    `route_search_test`, die Verdrahtung im Blatt in
    `trail_head_flow_test` (flach: Forstweg ×1,15 gegen Nebenstraße
    ×1,0 — Gegenprobe ohne `easy` im Blatt rot).
- **Stufen bergauf werden getragen** (#210, seit 0.87.0): Eine
  Stufen-Kante, die steigt, kostet `kCarryCostS` (60 s) obendrauf,
  unabhängig von der Länge (`carryCostS`, `edgeCostS(carry:)`). Zwei
  Dinge, die man wissen muss:
  - **Der Aufschlag hängt am Weg, nicht an jedem Stück.**
    `GraphEdge.carry` ist 1 und wird von `splitEdge` nach Länge geteilt
    wie die Höhen — ein fester Betrag je Kante wäre sonst nach dem
    Anheften eines Trailkopfs doppelt da, und die Route hinge davon ab,
    welche Trails gewählt sind. Kreuzungen beim Bau des Graphen teilen
    dagegen echt: Eine Treppe, die einen Weg quert, kostet zweimal.
  - **Spiegel des Werkzeugs**: `CARRY_S`, `carry_cost_s`, `Edge.carry`
    in `tool/route_measure.py`; die Zahlen in `route_profile_test` und
    die Suche „Treppe gegen 900 m Forstweg" sind dort gerechnet.
- **Wegegüte** (#213, seit 0.92.0; Konzept-Routing 2.4, Messung in
  `docs/routing-messung.md`): `wayCostS` (Spiegel von `way_cost_s`,
  Vektoren in `route_profile_test`) bepreist Forstwege 3/7 und Pfade 6/8
  bzw. `mtb:scale:uphill` bergauf, als Kosten. Vier Dinge, die man
  wissen muss:
  - **Die Güte kommt per Geometrie an die Kante** (`addWayQuality`,
    3 m, Proben je 10 m, Mehrheit > 50 %), nicht über eine OSM-Kennung —
    die Basiskarte hat keine. Nur ein Forstweg nimmt eine Forstweg-Klasse,
    nur ein Wanderweg eine Pfad-Klasse; Fußwege tragen im Archiv nichts.
  - **Zwei Quellen wie die Kacheln** (`loadRoadGraph(openWays:,
    fetchWaysOnline:)`): das dritte Archiv der Bereiche
    (`areaWaysOpenerProvider`), für online nachgeladene Kacheln das
    Wege-Archiv vom Host (`OnlineFill.fetchWays`, Manifest über
    `areaWaysManifestLoaderProvider`, also unabhängig vom Schalter der
    Ebene). Jeder Fehler kostet nur die Güte, nie den Graphen; das
    Archiv hat Lücken, eine fehlende Kachel heißt „nichts bekannt".
  - **`splitEdge` vererbt `way`/`uphill`** an beide Hälften (Test in
    `road_graph_test`) — sonst verlöre ein angehefteter Trailkopf die
    Güte des Rests.
  - **Alte Bereiche (Format 1, 0.90.0)** haben grade5 in Klasse 3 und
    T4+ in 6: Sie planen dort milder, bis „Aktualisieren" das neue
    Archiv holt. Der Isolate des Planers bekommt die Felder mit der
    Kopie des Graphen, ohne eigene Serialisierung.
- **„Zum Trailkopf"** (Schritt 4, seit 0.71.0, `trail_head_route.dart`
  pur, `trail_head_providers.dart`): im Trail-Blatt neben „Anfahrt", vom
  eigenen Standort zum Anfang des Trails über den Graphen der Bereiche
  (A*). **Seit 0.130.0 rechnet das der Planer** (#356 PR 7, siehe „Ein
  Planer für alle Einstiege"); das eigene Blatt `trail_head_sheet.dart`
  ist weg, `planTrailHeadRoute` rechnet nur noch „Zurück zur Route". Was
  unten steht, gilt sinngemäß weiter. Vier Dinge, die man wissen muss:
  - **Das Blatt stellt einen WUNSCH, die Karte löst ihn ein**
    (`trailHeadRequestProvider`, Muster `mapFocusTrailProvider`): Das
    Trail-Blatt kann über dem Reiter „Trails" offen sein, die Vorschau
    gehört aber auf die Karte. Erst das Blatt zu, dann der Reiter, dann
    der Wunsch; `MapScreen` öffnet das Blatt „Zum Trailkopf" nach dem
    nächsten Bild und passt die Kamera EINMAL auf die Linie ein — nicht
    bei jedem Profilwechsel. Die Vorschau (`trailHeadPreviewProvider`)
    lebt mit dem Blatt und wird nach dem `await` geleert, nicht im
    `dispose` (dort ist `ref` tot — wie beim Zerlege-Blatt).
  - **Der Fix kommt beim Öffnen des Blatts**, über `positionFixProvider`
    — das Blatt IST der Tipp, ein zweiter Knopf davor wäre eine Hürde.
    Ohne Standort kein Startpunkt, und das Blatt sagt es und bietet die
    Anfahrt an. Ein getippter Startpunkt kommt mit dem Planer (Schritt 5).
  - **Gerechnet wird aus den Bereichen** (Nicht-Ziel „kein Routing
    über fremde Gegenden"; seit 0.78.0 mit Empfang ergänzt vom Host, #187); seit 0.74.0 über die Kacheln, die da sind,
    auch bei `partial` (siehe „Navigation rund"); der Rahmen aus
    Standort und Kopf bekommt `kTrailHeadMarginM` (500 m) Rand, sonst
    wäre er bei zwei Punkten auf einer Linie null Meter breit. Ohne
    Höhen im Bereich rechnet die Suche flach und das Blatt nennt die
    Zahlen eine Untergrenze. Wanderweg im Weg steht als Satz dabei (die
    App urteilt nicht über Erlaubnis, Konzept 7), die Linie ist dort
    gestrichelt.
  - **Die Linie trägt die Verbinder** (Standort → erster Wegpunkt,
    letzter → Trailkopf), Länge und Zeit nicht: Sie sind der Anschluss,
    keine Strecke. Die GPX-Spur (`trailHeadToGpx`) hat keine Höhen — die
    Engine kennt sie je Kante, nicht je Punkt. „Als Fahrt speichern"
    gibt es seit 0.72.0 (geplante Fahrt, siehe Rundenplaner).
  Nebenbefund: Der Schritttitel der Vorführung `navigate` hieß „Zum
  Trailkopf" — seit es den Knopf gibt, wäre das ein Text auf dem Schirm;
  jetzt „In die Navi-App".
- **Der Rundenplaner** (Schritt 5, seit 0.72.0, `loop_planner.dart` pur,
  `loop_planner_sheet.dart`, `loop_planner_providers.dart`; Konzept-
  Routing 1, 2.3, 3, 4): eigener Kartenknopf „Runde planen" zwischen
  „Ebenen" und „Meine Position"; bis 0.73.0 drei Stufen im Blatt (Regler
  → Pool → Ergebnis), seit 0.74.0 ein Modus mit Leiste links (siehe
  „Navigation rund"). Sieben Dinge, die man wissen muss:
  - **Die Zielfunktion ist Trail-Meter je ZEITzuwachs**, nicht je
    Kostenzuwachs (Konzept-Routing 3.2 sagte „Kosten"): Die Zeit ist das
    Budget, die Kosten entscheiden nur, welcher Weg zwischen zwei
    Punkten gewählt wird. Lexikografisch danach weniger Aufstieg, dann
    weniger verschenkte Höhe (`_Route.beats`). Zweite Abfahrt eines
    Trails nur mit 4–5 Sternen (30 %, `kLoopSecondPassShare`), höchstens
    zwei Durchgänge; Pflicht-Trails zuerst und nie entfernt.
  - **„Höchstens Wanderweg" ist keine Nachprüfung.** Die günstigste
    Verbindung läuft oft über den Wanderweg; sprengt die Runde das
    Budget, bekommt die Verbindung mit dem meisten Wanderweg ihre
    Fassung OHNE (`dijkstra(allow:)`, zweite Suche je Startknoten, erst
    bei Bedarf), bis es passt. Ohne die Regel ließ „kein Wanderweg"
    einen Trail aus, zu dem drei Seiten Forstweg führten — im
    Planer-Test gefunden. Dijkstra-Grenze ist das ZEITbudget in
    Kosten-Einheiten: Eine Verbindung, deren Kosten über dem ganzen
    Zeitbudget liegen, gilt als nicht erreichbar.
  - **Der Pool schneidet bei 12 km** (`kLoopReachM`, beide Enden
    Luftlinie vom Start) und zählt den Rest; gemeldete Trails stehen
    abseits und abgewählt (Entscheidung 8.8), wartende gar nicht. Der
    Graph-Rahmen ist Start plus alle gewählten Trails plus 500 m; er
    bleibt stehen, solange Start und Trails darin liegen — seit 0.132.2
    (#370) gehört der Start nicht mehr in den Schlüssel: Er darf
    `kPlanStartSlackM` (250 m, die Hälfte des Leserands) neben dem
    Rahmen liegen, `planLoop` heftet ihn je Rechnung an. Bis dahin baute
    jeder neue Fix des Standorts neu (am Pixel 12–44 s je „Neu
    rechnen"); Flow-Test „#370", Gegenprobe mit dem alten Controller rot.
  - **Der getippte Start ist ein Dialog mit der Karte**
    (`LoopSession.pickingStart`, oberster Knopf der Leiste oder „Auf der
    Karte tippen" in den Parametern): oben ein Banner mit Abbrechen, der
    nächste Tipp — auch auf eine Linie — ist der Start (Fahne in der
    Marke, `_takeLoopStart`); Zurück bricht ab. Keine eigene
    Zeichenfläche: Ein Tipp ist eine Geste, die die Fassade schon hat.
  - **Das Ende der Fahrt** (#331, seit 0.123.0): `LoopEndMode` (Runde,
    letzter Trail, Ziel) statt des Schalters „Start ist auch Ziel",
    gemerkt in `LoopPrefs` unter dem alten Schlüssel `r` (1/0 wie bisher,
    2 = Ziel — ältere Apps lesen 2 als Runde, und seit #356 PR 5 auch
    diese: Das Ziel gilt nur für die Sitzung, ein Planer mit „Zum Ziel"
    ohne Ziel konnte nach dem Neustart nichts rechnen; geschrieben wird
    die 2 weiter, für den einen Planer aus Konzept-Routing 10.2). Das Ziel
    (`LoopSession.target`, `pickingTarget`) ist ein Tipp wie der Start
    (`takePick` nimmt beide), nur für die Sitzung; ohne Ziel heißt es
    `LoopBlocker.noTarget`. Der Graph-Rahmen schließt das Ziel ein.
    **Der Name hängt an der GERECHNETEN Planung** (`LoopSession.planEnd`),
    nicht am Regler: „Runde" nur bei `loop`, sonst „Route" (Blatt, Fahrt,
    GPX, Navigation). Das Tunen rechnet mit dem Ziel der gezeigten
    Planung (`_planTarget`), auch wenn inzwischen ein neues getippt ist.
    Fahnen: getippter Start, sonst — mit Ergebnis — Anfang der Linie;
    Zielfahne (`LoopStartFlag(finish: true)`) am Ende der Linie, wenn sie
    nicht am Start endet, vor dem Rechnen am getippten Ziel.
    **Der Trailkopf aus dem Trail-Blatt** (seit 0.124.0, #331 Schritt 2):
    „Start im Planer"/„Ziel im Planer" stellen einen Wunsch
    (`loopTrailHeadRequestProvider`, Muster `trailHeadRequestProvider`),
    die Karte öffnet den Planer und ruft `takeTrailHead` — als Start
    kommt der Trail in die Auswahl (nur wählbare Abfahrten), als Ziel
    schaltet sie auf `LoopEndMode.target` (gemerkt wie über die
    Parameter) und wählt nichts. Danach passt die Karte den Trail ein:
    Das Blatt kann aus der Liste kommen. Anker `SheetCoach.plan` steht
    auch im Beispielblatt der Touren.
    **Ein Ort als Start oder Ziel** (seit 0.125.0, #331 Schritt 3): Das
    Ort-Blatt (`showPoiSheet(onPlan:)`) liegt schon auf der Karte, also
    kein Wunsch-Provider: Die Karte öffnet den Planer und ruft
    `takePlace` (auch der Kern von `takeTrailHead`), ohne einzupassen.
    Wartet der Planer auf einen Tipp, gibt `_onHit` für einen `Poi`
    dessen Lage statt der Fingerstelle — der Test tippt dafür absichtlich
    daneben. Im Flow-Test den Ort per `tapMapAt` treffen, nicht per
    `tester.tap` auf die Nadel: Bei offenem Planer meldet `tap()` die
    Nadel an falscher Stelle (0,0-nah) und trifft nichts.
    **Zwischenpunkte vor dem Planen** (seit 0.126.0, #331 Schritt 4;
    Betreiber 2026-10-16: „Planer wählt" die Reihenfolge): Tipps wie Start
    und Ziel (`pickingWaypoint`, `takePick`) oder ein Ort
    (`LoopPlaceRole.waypoint`), nur für die Sitzung. In der Engine sind sie
    Halte ohne Länge im Pool (`PoolTrail.waypoint`, Kennung
    `kLoopWaypointPrefix` + Nummer): eingesetzt VOR den Pflicht-Trails und
    ohne Budgetprüfung (`mustFit: false`), nie wieder entfernt, nie als
    Kandidat der lokalen Suche. Jeder Halt teilt die Fahrt in ein
    Teilstück mehr — so greifen die Gummipunkte (#234) weiter;
    `LoopPlan.order` trägt die Halte für `LoopTune`, `stops` nur die
    Trails, und die Gründe (`excluded`) nennen nie eine Punkt-Kennung.
    Liegt ein Punkt abseits oder unerreichbar: `LoopOutcome.viaFailed`.
    Getunt rechnet der Controller mit den Punkten der GEZEIGTEN Planung
    (`_planWaypoints`), wie beim Ziel. Die Nadeln (`LoopWaypointPin`, 44 dp
    Tippfläche) tragen `LoopWaypointHit`; ein Tipp nimmt den Punkt weg,
    mit Rückgängig.
    **Ein Tipp auf einen Trail trifft im Planer nur die Linie selbst**
    (#375, seit 0.134.1; Betreiber 2026-10-18, Option 1 von dreien):
    `MapViewPolyline.hitSlop` ist dort `kLoopTapSlopPx` (4 px statt
    `kMapTapSlopPx` 12, je zur halben Breite und dem Rand) — am Pixel
    traf ein Tipp auf den Weg daneben oder zum Wegtippen mehrmals den
    Trail. Jeder Wechsel sagt es (`loop-toggled`, „dazugenommen" /
    „weggelassen") mit Rückgängig (`loop-toggled-undo`,
    `restoreSelection` mit Auswahl UND Sternen von vorher, `persist:
    false` wie jede Leiste mit Aktion, #371). Das Schild am Trailanfang
    bleibt ein Treffer wie bisher. Im Parameter-Blatt-Test liegt der Hinweis nach dem
    Scrollen außerhalb des Bildes — `skipOffstage: false`.
    **Gesetzte Punkte springen auf den Weg** (seit 0.134.0, #374):
    `planLoop` heftet Start, Ziel und vorab gesetzte Zwischenpunkte mit
    `RoadGraph.snap` an (bis `kGraphSnapM` = 200 m, erst `attach` in
    30 m, sonst der nächste Kantenpunkt), seit 0.135.0 (#394) auch die
    Trail-Enden (`SnapRole.trailStart/trailEnd` mit `trailId`; das
    Blatt nennt nur Trails, die mitfahren — `_withSnaps` filtert).
    Gezogene Gummipunkte (`pathThrough`) bleiben bei `attach`.
    **`buildGraphFrom` heftet die Abfahrten ebenso mit `snap` an** — mit
    `attach` dort teilte die erste Rechnung die Kante, `RoadGraph.revision`
    stieg, und der Suchspeicher verfiel (Test im Runner-Test, Gegenprobe
    rot). **Nur Zwischenpunkte, kein Trail, kein Ziel** (#395, seit
    0.135.0): `planLoop(bare: true)` mit `kRouteDirectBudget`, Runde oder
    Ende am letzten Punkt nach `LoopEndMode`; die Leiste gibt „Rechnen"
    dafür frei (`loopRailComputePoints`) — bis dahin war der Knopf ohne
    Trail gesperrt, und der Controller hätte `noTrails` gesagt. Was über 30 m
    sprang, steht in `LoopPlan.snaps` (Rolle, Ort, Meter, Index des
    Zwischenpunkts); die Linie beginnt und endet am gesprungenen Punkt.
    Der Controller legt nach der Rechnung getippten Start, Ziel und
    Punkte dorthin — per `copyWith`, nicht `_edit`, sonst hieße der
    Sprung „Auswahl geändert" —, der Standort bleibt. Getunt rechnet
    `_planRequest` mit den alten Punkten, die springen dann gleich; ein
    „Neu rechnen" nimmt die neuen, und der Satz entfällt.
  - **Die geplante Fahrt** (`Ride.planned`, `Ride.name`,
    `RideStore.savePlanned`, Datei am Stück über `.part` + `rename`):
    Punkte ohne Zeit und Höhe, `endedAt` = Schätzung; in „Meine Fahrten"
    mit Name, „Geplant am …", OHNE Schere (zerlegt wird, was gefahren
    wurde); der GPX-Export lässt die Zeiten weg (lauter gleiche Zeiten
    läse jede App als Stillstand). Auch „Zum Trailkopf" legt seinen Weg
    so ab.
  - **Die Regler merkt sich das Gerät** (`Settings.loopPlannerPrefs`,
    `LoopPrefs.encode/parse`, je Wert auf seine Spanne geklemmt); das
    Höhenbudget folgt dem Profilwechsel nur, solange es auf der Vorgabe
    des alten Profils steht. **Gerechnet wird seit 0.80.1 in einem
    dauerhaften Rechen-Isolate** (#188, `loop_plan_runner.dart`):
    `Isolate.run` je Rechnung half kaum — das Senden kopiert den Graphen
    im UI-Isolate (0,3–0,6 s Pause). Der Graph geht deshalb EINMAL
    hinüber, jede weitere Rechnung schickt nur eine `LoopRequest`;
    drüben wird angeheftet, der Graph des Controllers bleibt
    unverändert. Schließen des Planers gibt den Isolate frei
    (`dispose`), Schließen des Ergebnisses verwirft eine laufende
    Rechnung (`_generation`). Im Web und im Harness rechnet
    `InlineLoopPlanRunner` an Ort und Stelle — ein echter Isolate
    antwortet in der Test-Zone nie (`loopPlanRunnerFactoryProvider`).
    Gemessen in `docs/routing-messung.md` („#188"); Graph bauen und
    Trails auflegen laufen weiter im UI-Isolate — seit Flutter 3.29 ist
    das auf Android der Haupt-Thread, eine lange Rechnung dort ist ein
    ANR (0.127.0: 36 s in `loadRoadGraph` → `findCrossings`, #354).
    **Gemessen wird das am Gerät, nicht im Test** (#356 PR 4): Der Fall aus
    #354 war nur im AOT-Build langsam, im JIT der Tests gleich schnell. Die
    Schritte tragen Marken des Stall-Wächters (`lib/core/CLAUDE.md`);
    `graph_build_budget_test` fängt nur, was überall kippt (relativ, rot
    über 15-fach UND 20 s), und `perf_loop_planner_measure.dart` baut seit
    #356 mit Kreuzungsteilung — dort zeigte sich das Senden des Graphen
    als längste Pause (1,8 s bei 62 600 Kanten, `docs/routing-messung.md`).
    **Seit 0.131.1 wird der Graph im Rechen-Isolate GEBAUT** (#356 PR 8,
    Konzept-Routing 10.6): Der UI-Isolate sammelt nur Bytes —
    `readRoadTiles` (Wege- und Wege-Archiv-Kacheln, nichts dekodiert),
    `HeightTiles.read` (die Höhenraster der gefundenen Kacheln, denn
    drüben gibt es weder Kachelspeicher noch Netz), `graphTrailsOf` — als
    `GraphInput` (`graph_input.dart`, rein); der Runner baut daraus
    (`build`, `buildGraphFrom`: dekodieren, `buildRoadGraph`,
    `addClimbsFrom` synchron, Güte, Trails auflegen, Enden anheften) und
    behält den Graphen, `plan` schickt nur noch die Anfrage. Der
    Controller hält KEINEN `RoadGraph` mehr, nur Rahmen, Start und
    Schalter des gebauten (`_graphBox`, `_hasGraph` fragt den Runner);
    nach „Rückgängig" baut der neue Runner aus denselben Bytes
    denselben Graphen (die Zwischenpunkte sind Koordinaten).
    `graph_isolation_test` wacht strukturell (Controller und Lader ohne
    `buildRoadGraph`/`applyTrails`/`RoadGraph`, die Naht ohne Flutter,
    Riverpod, Isolate, Speicher), der Runner-Test am Namen des Isolates.
    Gemessen (`routing-messung.md`, „nach PR 8"): die Pause im UI-Isolate
    von 1,8 s auf ~25 ms (544 KB Bytes statt 65 000 Kanten), der Bau
    selbst gleich teuer, nur woanders. **Vor dem Lesen zählt der Lader**
    (`kPlanMaxTiles` = 120, gemessen am Pixel: die Grenze setzt der
    Speicher, nicht die Zeit — bis 0.131.x vorläufig 300;
    `LoopBlocker.tooLarge`, `loopBlockerTooLarge`/`routeBlockerTooLarge`
    mit Zahlen und Rat), und **Verbinder kommen nur in der Nähe der
    Anker in den Rahmen** (`kPlanConnectorMarginM`, 3 km um Start, Ziel,
    Zwischenpunkte, gewählte Trails und die des Umwegs; bis 0.131.0 alle
    im Radius der Liste — ein 60 × 60-km-Rahmen für eine 12-km-Runde).
    **Seit 0.132.0 gibt es einen Ladebalken** (Betreiber 2026-10-18: mit
    Balken darf es länger dauern): `PlanProgress` (`plan_progress.dart`)
    ist wie der Stall-Wächter ein statischer Melder je Isolate; nur
    innerhalb von `PlanProgress.run` meldet er, sonst ist jeder Aufruf ein
    Vergleich mit null. Bau-Schritte teilen sich den Balken mit
    `part(from, to, …)` nach den Zeiten am Pixel, lange Schleifen melden
    mit `steps` (nur jede 64./128./256. Runde); `planLoop` meldet je
    Suche (eine vom Start, eine je Trail-Ende, gekappt bei 95 %). Der
    Isolate schickt `(id, double)` höchstens einmal je Prozent;
    `build`/`plan` nehmen `onProgress`, die übrigen Aufträge melden
    nichts. Der Controller hat dafür die Phase `building` und
    `LoopSession.progress` (jeder Phasenwechsel setzt ihn zurück).
    **„Abbrechen" daneben** (#372, seit 0.133.0, `loop-cancel`) beim
    Laden, Bauen und Rechnen: `cancel()` zählt die Generation hoch und
    gibt beim Bauen oder Rechnen den Runner frei — eine Suche lässt sich
    im Isolate nicht anhalten, nur der Isolate töten; die wartenden
    Aufträge scheitern still. Danach steht das Blatt auf „Auswahl
    geändert" (D3), die nächste Rechnung baut neu. Beim Laden bleibt der
    Runner: Er hält dann noch den Graphen des alten Rahmens.
    **Seit 0.131.2 rechnet der Runner jede `GraphJob`** (#356 PR 9,
    `graph_input.dart`): `run(job)` schickt die Aufgabe hinüber, `runOn`
    läuft drüben auf dem gehaltenen Graphen — die Runde (`LoopRequest`),
    „Zurück zur Route" (`TrailHeadJob` in `trail_head_route.dart`) und
    das Einordnen einer Fahrt (`CalibJob` in `ride_calibration.dart`);
    Eingaben und Ergebnis müssen sendbar sein (keine Closures). Die
    Kalibrierung legt sich je Lauf EINEN Runner an und baut je Fahrt neu
    (`readRoadTiles(only: tilesAlong(...))` — nur die Kacheln unter der
    Linie, mit 30 m Rand; `kCalibMaxRides` = 20, die jüngsten);
    `loadRoadGraph` baut im aufrufenden Isolate und hat nur noch Tests
    als Aufrufer. `NavController` hält für „Zurück zur Route" einen
    eigenen Runner samt Rahmen (`kNavRejoinGraphMarginM` = 2 km Rand;
    ein Tipp im Rahmen baut nicht neu; `stop` gibt ihn frei) und rechnet
    mit `NavSession.profile`/`routePrefs`, die das Ergebnis-Blatt über
    `NavRequest` mitgibt (`session.prefs.planRoute`) — ohne (Fahrt aus
    „Meine Fahrten", Wiederaufnahme nach Neustart: `NavRouteData` trägt
    kein Profil) das aktuelle Rad mit `LoopPrefs.route`.
    `graph_isolation_test` bewacht seitdem auch `ride_calibrator.dart`
    und `nav_providers.dart` (dort darf kein `RoadGraph` und kein
    `loadRoadGraph(` mehr stehen), `nav_rejoin_test` die Aufgabe mit Rad
    und Stil, `tiles_along_test` den Korridor. **„Suche Standort …"**
    (`nav-searching`) steht als Leiste, solange `positionFixProvider`
    beim Start der Navigation aussteht; `FakePositionFix.gate` hält den
    Fix im Test. Tests, die Kacheln brauchen, kodieren
    sie mit `test/fakes/graph_tiles.dart` (`roadTilesOf`, `heightTilesOf`);
    `_HeldRunner` im Flow-Test baut sofort inline und hält nur `plan`.
    **Keine verschachtelten Records als Schlüssel oder Element in
    heißen Schleifen** (`Set<((int, int), (int, int))>`): Jedes `add`
    fällt in die langsame Typprüfung der VM (`SlowTypeTest` →
    `DRT_TypeCheck`), gemessen gut zehnmal langsamer als derselbe
    Schlüssel flach als `(int, int, int, int)`; flache Records sind so
    schnell wie eine Klasse. **Seit 0.80.2 behält
    der Planer seine Suchen** (`LoopSearchCache`, je Runner einer): Die
    begrenzten Dijkstras je Trail-Ende waren auch im Isolate der teure
    Teil (40 Trails: 1,6 s je weiterer Rechnung, jetzt ≤ 35 ms). Gültig
    nur für DENSELBEN Graphen in DEMSELBEN Stand (`RoadGraph.revision`
    — eine Teilung beim Anheften ließe gemerkte Vorgänger ins Leere
    zeigen), dieselben Profilwerte und dasselbe Zeitbudget; alles andere
    leert ihn, und er hält nur einen Stand. Damit eine neue Auswahl
    keine Kante teilt, heftet `loadPlanningGraph` die Enden JEDER
    Abfahrt im Rahmen schon beim Laden an, und der Controller lädt nur
    neu, wenn ein gewählter Trail aus dem geladenen Rahmen ragt
    (`_graphBox`, `LatBox.contains`) — bis 0.80.1 bei jeder Kennung, die
    nicht schon beim Laden gewählt war. **Eine gemerkte Suche ist
    kompakt** (#376, seit 0.133.2): `SearchResult` hält Kennung, Kosten
    und Vorgängerkante nur der erreichten Knoten in typisierten Feldern
    (16 Byte je Knoten, binär gesucht), den Anstieg rechnet `climbTo` aus
    dem Pfad. Bis 0.133.1 lagen drei Hash-Maps darin, rund 100 Byte je
    Knoten. Bei 3–5 h Budget erreicht jede Suche fast den ganzen Rahmen,
    mit 60 Trails am Rechner waren das +401 MB, jetzt +48 MB, bei
    identischen Plänen (`docs/routing-messung.md`, „#376").
    **Die Kosten jeder Kante rechnet der Planer einmal je Stand** (#379,
    seit 0.133.3): `EdgeCosts` (in `route_search.dart`, beide Richtungen
    in einem Feld) hängt am Suchspeicher und wird mit ihm leer;
    `dijkstra(costs:)` liest daraus. Ändert sich der Graph danach doch
    (`RoadGraph.revision`, eine Teilung kürzt eine Kante), rechnet `of`
    wieder selbst — sonst kostete die gekürzte Hälfte wie die ganze
    Kante. Die erste Rechnung braucht etwa 40 % weniger Zeit, die Pläne
    sind identisch.
    **Der Graph liegt in typisierten Feldern** (#378, Gitter seit
    0.133.4, alles andere seit 0.133.5): Knoten, Kantenwerte,
    Linienpunkte (Grad UND Meter) und Nachbarn sind Felder in
    `RoadGraph`; `GraphEdge`, `edges`, `nodes`, `nodeLatLng` und `adj`
    sind Sichten, die je Zugriff ein Objekt bzw. eine Liste anlegen.
    **Heiße Schleifen lesen direkt** (`adjFirst`/`adjNext` mit Kante =
    Platz >> 1, `edgeA`/`edgeB`, `openFrom`, `nodeDistance`, `edgeXy`) —
    `g.adj[n]` im Dijkstra legte je Schritt eine Liste an. Eine Sicht auf
    `points` gilt im Stand ihres Aufrufs; eine Teilung schreibt den
    Teilungspunkt in den ersten Teil. Das Segmentgitter trägt je Segment
    die Nummer seines ersten Punkts (`_pedge` nennt die Kante), die
    Zellen findet eine Tabelle mit offener Adressierung; Zellkoordinaten
    bleiben absolut (um 26 000/105 000, auch auf dem Telefon kleine
    Smis), die Streuung ist im Web (2^53, 32-Bit-Bitoperationen) genau
    genug. Der Knotenschlüssel aus Mikrograd bleibt ein Record: als EINE
    Zahl bräuchte er rund 57 Bit, im Web sind es 53. 94 → 54 → 33 MB
    Heap je Graph, Pläne identisch; im Web prüft
    `test/web/road_graph_browser_test.dart` gegen die Zahlen der VM.
    **Die Reihenfolge ist Teil des Verhaltens**: Nachbarn in Reihenfolge
    des Eintragens (Teilung nimmt den Platz am alten Ende heraus und hängt
    ihn am neuen hinten an — wie `remove`/`add` vorher), Zellen in
    Reihenfolge des ersten Eintrags, Einträge in Reihenfolge des
    Eintragens — bei gleichen Kosten entscheidet die Suche nach der
    Nachbarreihenfolge, bei gleichem Abstand gewinnt in `nearest` der
    erste Treffer, und `findCrossings` teilt in der gefundenen
    Reihenfolge. Wer umbaut, hält das und prüft mit den Fingerabdrücken
    beider Mess-Skripte (Graph: `perf_graph_memory_measure.dart`, nur mit
    `--enable-vmservice`, Heap nach GC und Klassen; Plan:
    `perf_loop_planner_measure.dart`) — FNV über Text, weil `Object.hash`
    je Prozess anders geseedet ist. Nach dem Bau kürzt `compact()` die
    Felder; danach wachsen sie um ein Viertel, nicht aufs Doppelte.
  Die Kurzanleitung hat sechs Abschnitte als Obergrenze; der Planer
  steht als Satz in „Fahrt aufzeichnen und zerlegen". Vorführung
  `loop-planner` über Szene `MapCoach.loopSheet` und Anker
  `kLoopNextAnchor` im Blatt. **Der fünfte Knopf ließ die Knopfspalte
  auf einem kleinen Telefon QUER überlaufen** (640 × 360, 28 px —
  `trail_elevation_flow_test`); die Spalte steckt seither in
  `Flexible` + `FittedBox(scaleDown)` und skaliert nur dort herunter,
  hochkant bleiben es 44 px (`map_shell_test`). Das Konzept hatte
  genau diese Messung verlangt.
- **Höhenprofil im Ergebnis** (#234, seit 0.88.0, `route_elevation.dart`):
  „Runde" und „Zum Trailkopf"/„Route hierher" zeigen unter der Summe
  `ElevationProfileChart(compact: true)` entlang der GEZEICHNETEN Linie
  (`plan.points`, beim spaßigen Weg `fun.points`). Drei Dinge, die man
  wissen muss:
  - **Die Höhen kommen nicht aus der Engine**, sondern aus dem
    Geländemodell entlang der Linie (`lineProfileProvider` in
    `terrain_heights.dart`, Proben alle 50 m, Bereiche zuerst, mit Empfang
    der Sitzungsspeicher des Hosts — dort liegen die Kacheln der Planung
    schon). Die Engine kennt Höhen nur je Kante; ein Profil daraus wäre je
    Kante eine Gerade. Fehlt eine Kachel, gibt es kein Profil, nie ein
    halbes.
  - **Kompakt heißt ohne „Start … km"**: Das Profil zählt die Anschlüsse
    an Start und Ziel mit, die Summe nicht — zwei Längen übereinander
    läsen sich wie ein Fehler. Seit 0.122.0 (#332) steht dort statt
    dessen eine km-Skala (`axisTicks`: glatter Schritt, höchstens fünf
    Striche, ganze km oder Meter, nie ein Komma) — Teilstriche sind keine
    Summe. Während gelesen wird, steht der Platz schon da (Profil plus
    Skala), damit die Knöpfe nicht rutschen.
  - **Ziehen im Profil (#332, seit 0.122.0)**: Tippen oder waagrecht
    Ziehen setzt `routeProfileCursorProvider` (Meter im Profil + Ort auf
    der Linie, anteilig über `NavRoute.pointAt` umgerechnet, weil das
    Profil entlang seiner 50-m-Proben misst); die Karte zeigt dort
    `RouteCursorSymbol` (Marker `route-profile-cursor`). **Die Kamera
    folgt NICHT** (Betreiber, 2026-10-15: „zentrieren ist vielleicht
    nicht ideal und zu viel Unruhe, stattdessen sollte … die ganze
    Strecke im Bild zentriert sein und ein Icon … bewegt sich beim
    Ziehen auf der Strecke"). Die Stelle bleibt nach dem Loslassen
    stehen; neue Linie oder Abbau des Profils räumen sie (per Mikrotakt —
    Riverpod verbietet Schreiben im Abbau; den Griff in `initState`
    holen, im `dispose` ist `ref` schon tot). Die Karte zeigt das Symbol
    zusätzlich nur, solange ein Ergebnis auf ihr liegt: Das Blatt baut
    erst nach dem Schließen ab.
  - **`trail-head-profile` ist der Bio/E-Bike-Schalter**, das Profil heißt
    `trail-head-elevation` (im Planer `loop-elevation`, `loop-profile` ist
    dort ebenfalls der Schalter) — beim Bau kollidiert und nur als
    „Duplicate keys" sichtbar.
- **Zwischenpunkte zum Ziehen** (#234, seit 0.93.0, `route_vias.dart`
  pur, `route_via_providers.dart`, `via_handles.dart`; Konzept-Routing
  4): Tipp auf eine Verbindung setzt einen Punkt, Ziehen verschiebt,
  Tipp entfernt. Fünf Dinge, die man wissen muss:
  - **Die Karte ändert, der Besitzer rechnet** (`routeViaProvider`,
    `ViaOwner.loop`, bis 0.129 auch `route`): Planer (bis 0.129 auch Blatt „Route") hören auf die
    Punkte und rechnen, sobald sie von denen ihres gezeigten Ergebnisses
    abweichen. Geht es nicht, stellen sie die alten zurück (`reject`,
    `rejections` zählt — die Karte zeigt `via-rejected`). Ein späterer
    Zug verwirft das Ergebnis eines früheren (`_tuneSeq`).
  - **Marker nehmen keine Gesten an** (beide Engines), deshalb liegen
    über der Karte nur 44-dp-Griffe an der Lage vom letzten Stillstand
    (`ViaHandles`, ein `Stack` ohne Hintergrund: alles andere geht zur
    Karte durch). `DragStartBehavior.down`: Ohne kam der Punkt um die
    Schwelle der Geste zu kurz an (im Flow-Test gefunden, Gegenprobe rot).
  - **Getunt heißt feste Folge** (`planLoop(tune:)`, `LoopTune.of`): kein
    Greedy, keine lokale Suche, keine Budgets; `LoopSection.leg` sagt,
    zu welchem Teilstück eine Verbindung gehört, der Tipp trägt die ganze
    Linie des Teilstücks (`RouteLegHit`) für die Reihenfolge.
  - **Das Anheften der Punkte teilt Kanten** — im Rechen-Isolate verfällt
    damit der Suchspeicher (`RoadGraph.revision`), und die erste freie
    Rechnung nach „Zurücksetzen" dauert so lange wie die erste überhaupt.
  - **Eingepasst wird nicht neu**, solange getunt ist (`LoopSession.tuned`):
    Die Karte bleibt, wo der Finger den Punkt hingelegt hat. Eingeklappt
    liegt „Zurücksetzen" unter dem Rand des Blatts — die Flow-Tests ziehen
    es vorher hoch.
- **Kalibrierung aus eigenen Fahrten** (Schritt 6, seit 0.73.0,
  `ride_calibration.dart` pur, `ride_calibrator.dart`; Konzept-Routing
  2.1, Entscheidung 8.1 „Vorgaben zuerst, Lernen je Profil"). Fünf
  Dinge, die man wissen muss:
  - **Das Zeitmodell rechnet mit `RiderParams`, nicht mit dem Enum.**
    `RiderProfile` implementiert die Schnittstelle (Vorgaben),
    `CalibratedRider` überlagert sie mit den gelernten Werten; Suche,
    Planer und „Zum Trailkopf" nehmen `RiderParams`, die Blätter lesen
    `calibratedRiderProvider(profile)`. Die Zahlen des Enums bleiben
    der Spiegel des Werkzeugs (`route_profile_test`).
  - **Spiegel des Werkzeugs, nicht neu erfunden**: `ascentSections` ist
    `ride_sections` (100 hm, 15 m, Fenster 7 — derselbe Median wie das
    Zerlege-Blatt, `smoothElevation`), `classMixAlong` ist
    `class_mix_along` (5 m, 15 m). Der Median über sieben Punkte kappt
    Anfang und Gipfel: 150 hm in 10 min werden 855 hm/h, nicht 900 —
    im Flow-Test gefunden und so erwartet, weil das Werkzeug dasselbe
    misst. Dazu die Flachgeschwindigkeit (nicht im Werkzeug): Stücke
    zwischen den Aufstiegen, ≥ 500 m, Steigung unter 2 %, auf
    Forstweg/Straße.
  - **Erst ab drei Messungen und nur in der Spanne** (`kCalibMinSections`,
    150–1 500 hm/h, 8–30 km/h): Eine Fahrt mit hängendem GPS wäre sonst
    die neue Wahrheit. Was fehlt, bleibt Vorgabe, und die Anzeige sagt
    je Zahl „(gelernt)".
  - **Auf Knopfdruck, nicht nach jeder Fahrt**: Das Einordnen baut je
    Fahrt einen Graphen aus den Kacheln unter ihrer Linie (seit 0.131.2
    im Rechen-Isolate, Korridor statt Rahmen, höchstens 20 Fahrten — oben
    bei #356 PR 9), auch einen halben (Abschnitte in fehlenden Kacheln
    sind „abseits" und zählen nicht); geplant wird nie auf einem halben.
    Geplante Fahrten, Fahrten ohne Profil (vor 0.70.0) und ohne Höhen
    lernen nichts; der Satz danach sagt, was gezählt hat.
  - **Gerätelokal** (`Settings.riderCalibration`, JSON je Profil,
    `RiderCalibrations.encode/parse`, Unlesbares ⇒ Vorgaben; seit
    0.127.2 auch jede Zahl außerhalb der Spanne — eine gespeicherte 0
    teilte im Zeitmodell durch null, #356); nie aus
    Fahrten anderer (Konzept 12). Zurücksetzen je Profil.
  - **Fahrten aus GPX lernen mit** (#188, seit 0.82.0,
    `ride_import.dart` pur): Der Import bietet aufgezeichnete Fahrten
    (`TrackKind.ride` mit Zeiten) für „Meine Fahrten" an, mit EINEM
    gewählten Profil für den Stapel (`RidesNotifier.saveImported`,
    `RideStore.saveImported`, Kopf `imported: true` und Name, Kennung aus
    dem ersten Punkt). Doppelt heißt: dieselbe Startsekunde wie eine
    gemessene Fahrt (`rideOnDevice`) — auch die eigene, als GPX
    exportierte Aufzeichnung. Eine übernommene Fahrt zerlegt sich wie die
    Datei (`SplitRequest.fromRide`: Quelle `import`, Datei-Höhen gehen
    mit, keine Streuung — gespeichert ist sie als 0). Danach „lernen" im
    Import selbst, derselbe Satz wie im Profil (`learnResultText`). Nur
    Android, wie „Meine Fahrten".
- **Navigation rund** (seit 0.74.0, Feldbericht zu 0.73.0, #174 #176
  #177 #178 #185; `docs/konzept-routing.md` 2.7, 4). Sieben Dinge, die
  man wissen muss:
  - **Die Routen-Blätter sind kein Modal** (`map_panel.dart`): ein
    Persistent Bottom Sheet am Scaffold der Karte (`_scaffoldKey` in
    `MapScreen`, `showLoopPlannerSheet`/`showRouteSheet` nehmen den
    `ScaffoldState`). Runterziehen verkleinert, schließt nie —
    `shouldCloseOnMinExtent: false` ist die tragende Zeile, ohne sie
    schließt das Scaffold ein Persistent Sheet ganz unten (im Test
    gefunden, genau der Feldbericht). Die verdeckte Höhe steht in
    `mapPanelInsetProvider`; eingepasst wird nur noch auf WUNSCH des
    Blatts (`mapFitRequestProvider`, nach dem Einklappen), in die Fläche
    darüber (`cameraToFit(bottomInset:)`, höchstens 55 % gelten als
    verdeckt — ganz aufgezogen gäbe es Länderzoom).
  - **Geplant wird über die vorhandenen Kacheln** (`planning_graph.dart`,
    `loadRoadGraph(requireComplete: false)`): Das Rechteck um Start und
    Trails füllt ein Bereich „Entlang meiner Trails" nie, bis 0.73.0
    scheiterte die Planung deshalb fast immer. Das Blatt sagt „x von y
    Kacheln". **Mit Empfang kommen die fehlenden vom Host** (#187, seit
    0.78.0, `online_fill.dart`): letzte Quelle hinter den Bereichen,
    nächst der Mitte zuerst, höchstens `kOnlineFillMaxTiles` (75) je
    Planung plus ihre Höhenkacheln (R2-Class-B, #55) — **und seit
    0.117.6 bis `kOnlineHeightsMaxTiles` (75) Höhenkacheln für Wege aus
    Bereichen OHNE Höhen** (#322: alte Bereiche vor 0.69.0, „ganze
    Region" noch beim Laden; bis dahin „0 hm bergauf", das Profil
    darunter voller Berge, weil es jede Kachel fragt, und die Suche
    rechnete flach), 10 s Frist je
    Schritt, ein Netzfehler beendet nur das Nachladen; nur für die
    Sitzung im Speicher (`OnlineTileCache`, Behalten ist #155);
    abschaltbar über `LoopPrefs.fillOnline` („Fehlende Wege online
    ergänzen", gilt auch für den Weg zum Trail); seit 0.104.0 aus der
    Region, deren Rahmen die Planung schneidet (#220,
    `onlineFillFactoryProvider(box)`; außerhalb aller nichts). Was das Blatt dazu sagt,
    steht an EINER Stelle (`planningCoverageNote`); der Planer merkt
    sich dafür den geladenen Graphen (`LoopSession.coverage`), den Satz
    baut erst das Blatt — in seiner Sprache (#209). Der Harness hat kein
    Manifest, also kein Nachladen; Tests ersetzen
    `onlineFillFactoryProvider`. Was aufhält, steht OBEN (`loop-blocker`); Rechnen läuft in
    `try`, ein Fehler ist ein Satz plus `logError`, und vor der Rechnung
    gibt es ein Bild Kreisel (`endOfFrame`).
  - **Trails auf dem Graphen** (`trail_overlay.dart`, `applyTrails`):
    Abfahrten gegen ihre Richtung gesperrt (`GraphEdge.blockForward/
    blockBackward`, geprüft in `edgeOpenFrom` neben der Einbahn), außer
    „in beide Richtungen fahrbar" (Patch 016, `Trail.twoWay`: die eigene
    Angabe, sonst die Mehrheit, Gleichstand nein). Uphill-Trails und
    Verbindungen sind Verbinder (`kTrailConnectorFactor` 0,8, kein
    Wanderweg), fehlen sie in OSM, werden sie eine eigene Kante; sie
    stehen nicht mehr im Pool (`loopPoolOf(...).connectors`).
    `splitEdge` gibt Trail, Sperre und Höhen (anteilig) an BEIDE Hälften
    — bis 0.73.0 verlor die zweite Hälfte ihre Höhen.
  - **Direkt oder Spaßig** (`RouteMode` in `trail_head_providers.dart`,
    `trailHeadRequestProvider` trägt seither `(trailId, mode)`): Spaßig
    ist `planLoop(end:)` im Budget `kFun*` aus der direkten Route;
    `RouteTarget` nimmt auch einen Punkt („Route hierher").
  - **Navi-Symbol** (`navigate_choice.dart`, `TrailNavButton`) an der
    Listenzeile (links vom Schild, das am Rand bleibt — Design 4e) und
    auf der Schnellkarte; `Settings.navDefault` (`FakeSettings`: null).
    Das Auswahlblatt ist `isScrollControlled` — mit vier erklärten Zeilen
    lag der Haken auf 360 × 800 sonst unter dem Rand.
  - **Langer Druck** (`MapViewConfig.onLongPress`, MapLibre
    `MapEventLongClick`, flutter_map `onLongPress`, Fake `longPressMapAt`):
    IMMER der Punkt, auch auf einer Linie.
  - **Auswählen statt öffnen** (`_selectedTrailId`, `TrailQuickCard`):
    Leuchtrand unter dem Netz (seit 0.77.2 deckendes Lime mit dunkler
    Kontur, `kSelectionGlowWidth`/`kSelectionGlowBorder` — #195: der
    halbdurchsichtige ging im weißen Saum unter), Schnellkarte unten links neben der
    Knopfspalte, nicht solange ein Routen-Blatt offen ist; Zurück und
    ein Tipp ins Leere heben auf, ein zweiter Tipp auf denselben Trail
    öffnet das Blatt. Im Planer geht der Tipp an den Planer. Die Touren
    öffnen das Blatt weiter direkt über ihre Szene.
  - **Der Planer ist ein Modus mit Leiste links** (Betreiber, nach dem
    ersten Entwurf mit Stufen-Blatt): `LoopToolRail` am Platz der
    Leiste „Ebenen" (nie beide zugleich), Zustand in
    `loopPlannerProvider` (`LoopSession`: Auswahl, Pflicht, Start,
    Zeichenwerkzeug, Parameter, Phase, Grund, Ergebnis) — Leiste, Karte
    und Blätter lesen dieselbe Wahrheit. Tipp auf einen Trail = an/ab,
    ab Werk nichts gewählt; Liste (Radius `LoopPrefs.radiusKm`, 2–30 km,
    begrenzt NUR die Liste) und Gebiet (`AreaDrawOverlay(onRing:)`,
    `trailsInRing`: Mehrheit der Punkte drin) sind zwei weitere Wege zur
    selben Menge. Die Auswahl leuchtet seit 0.83.3 deckend mit dunkler
    Kontur (`kLoopPickWidth`/`kLoopPickBorder`, #233 — dieselbe Falle wie
    #195: halbdurchsichtiges Lime verschwand im weißen Saum, der Feldbericht
    hielt das Umfahren für wirkungslos); die Fahne ist `LoopStartFlag`. Rechnen öffnet das Ergebnis-Blatt
    (`showLoopResultPanel`); zu = Ergebnis weg, Modus bleibt
    (`closeMapPanel` schließt es mit, wenn der Planer zugeht). Szene der
    Touren: `MapCoach.loopRail`, Anker je Knopf
    `MapCoach.loopRailButton(key)`.
  - **Ändern, Zurück, Schließen** (#356 PR 5, seit 0.128.0;
    Konzept-Routing 10.4/10.5, D3). Vier Dinge, die man wissen muss:
    - **Jede Eingabe geht über `_edit`** (Auswahl, Stern, Start, Ziel,
      Zwischenpunkte, Regler, Rad): Plan weg, `_generation` hoch, Phase
      `idle`, und lag schon etwas im Blatt, `LoopSession.changed` — das
      Blatt zeigt `loop-changed` mit `loop-recompute`, gerechnet wird nie
      von selbst. Bis 0.127.4 blieb die Phase `result` ohne Plan stehen,
      und das Blatt nannte es einen gemeldeten Fehler.
    - **Zurück nimmt das Blatt nicht selbst**: `canPop: false` am
      `PopScope` der Karte geht vor dem lokalen Verlauf des Persistent
      Sheet. Die Stufen stehen deshalb ausdrücklich im Handler (Tippen,
      Zeichnen, `_loopPanelOpen`, Planer).
    - **Zu heißt aufgeräumt, mit „Rückgängig"**: `close()` leert Auswahl,
      Start, Ziel und Zwischenpunkte und gibt `LoopClosed` zurück (samt
      Graph — getunte Punkte zeigen auf seine Knoten); `restore` und
      `showLoopResultPanel(compute: false)` holen beides ohne neue
      Rechnung zurück. Startet die Navigation, gibt es keine Meldung.
    - **Das Fahrerprofil hört mit** (`ref.listen(riderProfileProvider)`):
      ein anderes Rad in den Einstellungen erreicht den offenen Planer.
    In den Flow-Tests liegt bei offenem Ergebnis die untere Hälfte der
    Leiste (Rechnen, X) unter dem Blatt — erst einklappen oder
    `loop-recompute` im Blatt nehmen.
  - **Die Route von A nach B** (#356 PR 6, seit 0.129.0,
    `route_result.dart` pur; Konzept-Routing 10.2): „Zum Ziel" ohne
    gewählten Trail rechnet die Route im Stil `LoopPrefs.style` (`y=d/f/e`,
    gemerkt). Vier Dinge, die man wissen muss:
    - **Es ist `planLoop(bare: true)`**, kein zweiter Rechenweg: leerer
      Pool, `kRouteDirectBudget` (nur die Grenze der Suchen), das Ergebnis
      ein `LoopPlan` ohne Halt. Ohne `bare` hieße „nur Zwischenpunkte"
      weiter `LoopOutcome.empty` — eine Runde braucht einen Trail. So
      rechnet die Route im Isolate, mit Zwischenpunkten (der Planer wählt
      die Folge, D4) und ziehbaren Punkten wie die Runde.
    - **Spaßig sind zwei Rechnungen**: erst direkt, dann mit
      `funPoolOf` im `funBudgetOf` aus dessen Summen; nimmt sie keinen
      Trail mit, bleibt der direkte (`LoopSession.funEmpty`). Die Zahlen
      `kFun*` liest auch das Blatt „Route" von dort. Die Trails des Umwegs
      stehen immer im Graph-Rahmen, ein Stilwechsel lädt nicht neu.
    - **Getunt wird mit der Rechnung der GEZEIGTEN Planung**
      (`_planRequest.withTune`) — Pool, Stil, Rad, Ziel und Punkte von
      damals; das ersetzt `_planTarget`/`_planWaypoints`.
    - **Stil und Rad im Ergebnis rechnen sofort** (`setStyle`,
      `switchProfile`, D3; `loop-route-mode`, `loop-result-profile`), alle
      anderen Eingaben sagen „Auswahl geändert". Der Stil steht über der
      Phase und bleibt beim Rechnen stehen.
  - **Stile mit Auswahl** (#356 PR 7b, seit 0.131.0; Konzept-Routing
    10.2, D5). Drei Dinge, die man wissen muss:
    - **Die Kosten kommen aus EINER Stelle**: `LoopPrefs.planRoute` —
      zu einem Ziel `easy` nach dem Stil, sonst nach `easyUp` (`u=1`,
      gemerkt; „Bergauf bequem" gilt für Runde UND „am letzten Trail").
      `RoutePrefs.easy` ändert nur Wegekosten; die Trails selbst rechnen
      ihre Zeit nach S-Grad, „die Trails bleiben Trails".
    - **Direkt mit Auswahl ist `bare: true` mit den Pflicht-Trails als
      Pool** und `kRouteDirectBudget` — kein Budget, der Planer wählt nur
      die Folge (D4). Ohne Stern ist es die Route von A nach B; das Blatt
      sagt es (`loop-direct-note`). Spaßig und Bequem rechnen mit der
      ganzen Auswahl und den Budgets des Planers, wie das alte „Zum Ziel".
    - **Die Suchgrenze ist das Zeitbudget in Kosten**: Bequem kostet je
      Höhenmeter mehr, eine Verbindung erreicht die Grenze also früher
      als im MTB-Stil. Im Feld beobachten, ob Bequem mit Auswahl öfter
      „nicht erreichbar" sagt.
  - **Ein Planer für alle Einstiege** (#356 PR 7a, seit 0.130.0;
    Konzept-Routing 10.3–10.5). Fünf Dinge, die man wissen muss:
    - **Ein fertiger Auftrag ist `beginRoute`**: frischer Planer (der
      alte geht über `close()`), Ziel gesetzt, Start am Standort — außer
      im offenen Planer war einer getippt, den reicht `_planRoute` als
      `start:` weiter (#373, 0.133.1),
      `LoopSession.quick`; die Karte rechnet gleich danach
      (`_planRoute` in `MapScreen`). Einstiege: Trail-Blatt „Zum
      Trailkopf" und Navi-Symbol über `trailHeadRequestProvider` (Stil
      aus `NavChoice.style`, ohne gemerkten der des Planers), langer
      Druck „Route bis hier", Ort-Blatt „Route hierher"
      (`showPoiSheet(onRoute:)`). Mit Auswahl oder Zwischenpunkten fragt
      die Karte vorher (`loop-replace`).
    - **Schnell zu hängt an `quick`**: `_edit` setzt es zurück, Stil und
      Rad im Ergebnis (`setStyle`, `switchProfile`) behalten es. Geht das
      Ergebnis-Blatt zu (X oder Zurück) und `quick` steht, schließt
      `_showLoopResult` den ganzen Planer ohne „Rückgängig" und wählt den
      Trail wieder, der vorher ausgewählt war. Ersetzt ein neuer Auftrag
      das offene Blatt, wartet `_planRoute` dessen Ende ab
      (`_replacingPlan`) — sonst räumte das späte `clearResult` die neue
      Rechnung mit weg.
    - **Der Ziel-Trail ist `targetTrailId`** (aus `takeTrailHead(asTarget:)`
      und `beginRoute(trailId:)`, ein getipptes Ziel leert ihn): Die
      Navigation kennt ihn hinter dem Ende (`navSectionsOfLoop(beyond:)`,
      ersetzt `navSectionsOfTrailHead`), der spaßige Umweg nimmt ihn
      nicht (`funPoolOf(exceptId:)`), und OHNE Auswahl heißt die Fahrt
      „Zum Trailkopf: …" — mit Auswahl sagen deren Namen mehr.
    - **Nach der Navigation zurück zum Ergebnis**: `NavRequest.fromPlanner`
      (nur das Ergebnis-Blatt setzt es); `_startNavigation` behält den
      `LoopClosed`, das Ende der Navigation holt ihn mit
      `restore(quick: true)` und `compute: false` zurück. Aus „Meine
      Fahrten" und „zuletzt navigiert" bleibt die normale Karte.
    - **Eine Route hat ihre eigenen Sätze**: ohne Auswahl nennen die
      Gründe den Trailkopf oder das Ziel und die Navi-App
      (`routeBlocker*`), und „Anfahrt" (`loop-external`) steht auch
      dann, wenn nichts zu rechnen ging. Schlüssel bleiben `loop-*`
      (Betreiber, 2026-10-17) — `trail-head-*` gibt es nicht mehr.
    In den Flow-Tests nach `ensureVisible` ein `settle`: Ein neues
    Ergebnis klappt das Blatt ein, und ein Tipp an der alten Stelle traf
    sonst die Karte (oder schloss im schlimmsten Fall das Blatt).
- **Die Folgeansicht der Navigation** (#232 Schritt 1a, seit 0.94.0,
  `route_progress.dart` pur, `nav_providers.dart`, `nav_view.dart`;
  Konzept-Routing 9). Fünf Dinge, die man wissen muss:
  - **Der Wunsch kommt von außen, die Karte löst ein**
    (`navRequestProvider`, Muster `trailHeadRequestProvider`): Ergebnis-
    Blätter und „Meine Fahrten" stellen ihn, `MapScreen` fragt
    (`showNavStartSheet`: Aufzeichnen nur ohne laufende Fahrt, Bildschirm
    nur mit `ScreenAwake.supported`), holt den EINEN Fix und schließt
    Blatt, Planer und Auswahl. Ohne Fix keine Navigation.
  - **Der Stand sucht zuerst im Fenster voraus** (800 m, 30 m zurück),
    erst dann die ganze Linie; abseits bleibt der Stand des Fensters und
    nur der Abstand ist der zur ganzen Linie — sonst spränge eine Runde
    hin und zurück auf die Rückfahrt (`route_progress_test`, Gegenprobe
    ohne Fenster: rot).
  - **Die Richtung ohne GPS-Kurs ist die der Linie über 50 m voraus**
    (`kNavHeadingLookM`), nicht die des ersten Abschnitts: „Zum
    Trailkopf" beginnt oft mit ein paar Metern Anschluss zurück, und die
    Karte stand auf dem Kopf (im Flow-Test gefunden).
  - **Die Überlagerung ist NICHT positioniert** (`NavOverlay` direkt im
    Stack): Solange sie läuft, fehlen die übrigen Leisten, und mit
    `Positioned.fill` allein schrumpfte der Stack auf die Größe der
    Fake-Karte — die Knöpfe lagen oben links (im Flow-Test gefunden).
  - **Höhenmeter, die noch kommen**, aus dem Geländemodell entlang der
    Linie (`TerrainHeights.profile`, beim Start einmal gelesen,
    `climbAfter` mit derselben Hysterese wie das Ergebnis); fehlt eine
    Kachel, zeigt die Leiste nur km. Bildschirm an über
    `lib/core/screen_awake.dart` (Android `FLAG_KEEP_SCREEN_ON` per Kanal
    `de.mcbuchi.trailbuddy/screen`, Web Screen Wake Lock, neu geholt beim
    Zurückkommen in den Tab), gemerkt in `Settings.navKeepScreenOn`
    (Vorgabe an, `FakeSettings` ebenso).
  - **„Zurück zur Route" und „zuletzt navigiert"** (Schritt 1b, seit
    0.95.0): `NavController.rejoin` rechnet mit `planTrailHeadRoute` vom
    Standort zum Punkt `kNavRejoinTargetM` (200 m) voraus — seit 0.131.2
    im Rechen-Isolate mit Rad und Stil der Route (#356 PR 9, oben); das
    Ergebnis fällt weg, sobald
    ein Fix wieder auf der Linie liegt — auch wenn er während der
    Rechnung kommt (`after.rejoin != computing` ⇒ verworfen). Ohne Graph
    oder mit dem Standort an keinem Weg heißt es `noArea`, sonst `noPath`;
    die Leiste sagt es (`nav-rejoin-note`), der Knopf bleibt für einen
    zweiten Versuch. `lastNavProvider` merkt die Route beim Beenden NUR IM
    SPEICHER (Haustür; Einstellungen gingen in die Sicherung) samt Stand
    (`NavTracker(startAlongM:)`) — auf einer geraden Linie findet die
    Suche über die ganze Linie den Stand ohnehin, sichtbar wird es erst
    hin und zurück (`route_progress_test`).
- **Navigation nach Abschnitten** (#312 N1, seit 0.114.0,
  `nav_sections.dart` pur, Phasen in `route_progress.dart`, Ansicht
  `nav_view.dart`; Konzept-Routing 9.9, Design 13). Sieben Dinge, die man
  wissen muss:
  - **Die Lage eines Trails auf der Linie wird GESUCHT, nicht
    aufsummiert** (`_locate`): `plan.points` trägt vor und hinter den
    Abschnitten des Planers noch Anschlussstücke, Längen zu addieren
    läge daneben. Gesucht wird vorwärts ab dem letzten Treffer — eine
    Runde, die eine Stelle zweimal berührt, verwechselt die zweite sonst
    mit der ersten.
  - **Der Ziel-Trail des Trailkopf-Wegs liegt HINTER dem Ende**
    (`beyondRoute`, Start = Ende = Länge): Er zählt im Band nicht, die
    Anfahrt-Karte nennt ihn, und „angekommen" wird zur Trailkopf-Karte.
  - **Fahrten bekommen ihre Trails aus dem Netz** (`navSectionsOfLine`
    über `knownTrailSectionsOf`, die öffentlich gemachte Suche des
    Zerlege-Blatts — gleiche Schwellen, gleiche Lückenregel); das tut
    `MapScreen._startNavigation`, wenn die Anfrage keine Abschnitte
    hat. Im Web ohne Netz: keine Abschnitte, die Anfahrt zählt bis zum
    Ziel, das Band steht trotzdem.
  - **Am Trailkopf heißt stehen** (`NavState.moving`, dieselben 2 m/s
    wie der Kurs): 100 m davor bis 30 m dahinter. Wer mit Tempo über
    den Kopf rollt, sieht sofort die Trail-Leiste — sonst flackerte
    die Karte bei jedem Trail, der auf der Durchfahrt liegt.
  - **Alle Texte der Ansicht aus ARB** (Stufe d2 von #209, Navigation
    vorgezogen): `navToHead`, `navBandLoop` … Pure Helfer mit Text
    (`navStartSummary`) nehmen `AppLocalizations`. Die Farben sind der
    dunkle Satz FEST (`AppColors.dark`), in beiden Modi; ein Text ohne
    eigene Farbe wäre im Hellen schwarz auf Schwarz — deshalb
    `_NavTheme` um die ganze Lage. Schlüssel für Tests: `nav-approach`,
    `nav-off`, `nav-head`, `nav-trail`, `nav-band`, `nav-remaining`
    (im Band), `nav-dist`/`nav-climb`/`nav-ramp` (Anfahrt). Eine
    Routen-Datei der Fassung 2 trägt `secs`; der Dienst liest sie, nutzt
    sie aber erst mit N3.
  - **„Trail geschafft" (N2, seit 0.115.0) rechnet `NavTrailWatch`**
    (pur, in `route_progress.dart`) je Fix im Controller; die Bilanz
    hängt an `NavSession.trailDone`, ein Timer im Controller nimmt sie
    nach `kNavTrailDoneLinger` wieder weg (`dismissTrailDone`, auch
    „Weiter"). Die Zeit ist die des GPS-Fixes (`onFix(at:)`), nicht
    `DateTime.now()` — im Harness tragen die Fixe eine eigene Zeit
    (`fakePosition(at:)`). Das Blatt (`nav-done`, Zustände
    `nav-done-condition-<n>`, `nav-done-next`) meldet beim Tipp sofort,
    wie `SplitConfirmRow`.
  - **Fenster und Benachrichtigung nach Abschnitten (N3, seit
    0.116.0)**: `_PipCard` (`nav-pip`) ersetzt die Zahlenzeile; jede
    Zeile steckt in `FittedBox(scaleDown)` — ohne lief sie bei 150 dp um
    96 px über (Gegenprobe im Flow-Test mit 450 × 600 px bei 3×).
    `NavNoticeWatcher.phaseOf` rechnet die Phase aus `secs`,
    `navNotice` macht daraus Titel und Text über `serviceL10n()`.
    „Minimieren" fragt `pipSupportedProvider`; jede Kanal-Methode, die
    Dart ruft, muss in `MainActivity` stehen (`android_manifest_test`),
    sonst endet sie still in `notImplemented`.
- **Das Band der Route** (#295, seit 0.117.0, `route_band.dart` pur;
  Design 2 „B+"): Runde, „Zum Trailkopf" und Folgeansicht zeichnen über
  `routeBandLines`. Drei Dinge, die man wissen muss:
  - **Doppelt wird an den PUNKTEN erkannt** (`repeatedSegments`,
    `doubledSegments`: dasselbe Segment in beliebiger Richtung, auf
    10 cm gerastert), nicht am Graphen — dieselbe Kante bringt dieselben
    Punkte mit, und eine Route aus „Meine Fahrten" kennt keinen Graphen
    mehr. Gezeichnet wird jede Stelle einmal (`pass` 0), die
    Wiederholungen noch einmal (`pass` 1); in der Folgeansicht nur der
    Rest, also dicht nur, was noch zweimal kommt.
  - **Tippziele sind eigene Linien der Breite 0** (zuoberst), Wanderweg
    eine gestrichelte Mittellinie in Moos: Das Band selbst ist nach
    Wiederholung geschnitten, nicht nach Abschnitten.
  - **Tests lesen die Route über `test/fakes/route_lines.dart`**
    (`routeBand`, `routeWhole` aus den Pfeil-Linien, `routeHits`): Die
    Auswahl im Planer ist ebenso 12 px breit und Lime, aber deckend —
    ohne `opacity < 1` hielt der Test sie für das Band.
- **Die Navigation im Dienst** (#232 Schritt 2, seit 0.96.0,
  `nav_notice.dart` im Service-Isolate, `nav_service.dart` in der App;
  Konzept-Routing 9.5). Fünf Dinge, die man wissen muss:
  - **Ein dritter Melder am EINEN Dienst** (`NavKeepAlive`, Schlüssel
    `nav`, Typ `location`, Knopf `kNavStopButton`): Der Takt gilt seither
    JE MELDER (`KeepAliveCoordinator.setRepeat(key, …)`, es gilt der
    kürzeste) — bis 0.95.0 gab es einen, und das Ende der Fahrt hätte der
    Navigation den Takt genommen. Knöpfe je Melder; `null` an
    `updateService` ließe dem Paket die alten, deshalb immer eine Liste.
  - **Die Route geht als Datei hinüber** (`rides/nav_route.json`, `.part`
    + `rename`), gelesen wird nur bei neuer Fassung `nav_rev` in der
    Brücke — nicht je Takt. Dieselbe Linie noch einmal (das Höhenprofil
    kam nach) behält im Dienst ihren Stand; eine neue fängt neu an
    (`nav_notice_test`, Gegenprobe rot).
  - **Ein Fix je Takt für Fahrt UND Navigation** (`serviceTick` in
    `ride_task_handler.dart`); gefragt wird erst, wenn eines von beiden
    läuft. Der Text („Noch 12,4 km · 640 hm · auf der Route") wird je
    Takt geschrieben und überschreibt, was der Koordinator gesetzt hat —
    auch den Fortschritt eines Downloads, bis zu dessen nächstem Prozent.
  - **„Navigation beenden" geht ohne App** (`stopNavFromService`):
    Brücke aus, Datei weg, ohne Fahrt der ganze Dienst. Lebt die App,
    beendet sie über die Nachricht `kNavMessageStop` wie mit dem Knopf;
    der Koordinator erneuert den Dienst dann über `start`, nicht
    `update` — ein laufender Download stünde sonst ohne Dienst da, und
    zwar mit den Typen der Übrigen, nicht mit `location`. Eine Minute
    nach „Angekommen" endet die Navigation auch im Dienst.
  - **Startet die App neu, während der Dienst navigiert**, holt
    `MapScreen` sie ohne Rückfrage zurück (`NavServiceBridge.restore`,
    Stand `nav_along`); steht die Brücke an, läuft aber kein Dienst
    (Neustart des Geräts), wird aufgeräumt statt geöffnet. Der Harness
    hängt `FakeNavServiceBridge` ein — ohne ginge jeder Navigations-Test
    an `path_provider`.
- **Bild-im-Bild** (#232 Schritt 3, seit 0.97.0, `lib/core/picture_in_picture*.dart`,
  Kanal `de.mcbuchi.trailbuddy/pip` in `MainActivity`; Konzept-Routing
  9.6). Vier Dinge:
  - **Erlaubt nur, solange navigiert wird**: `MapScreen` ruft
    `allow(true/false)` beim Wechsel von `navigationProvider` zwischen
    null und nicht null — auch eine nach dem Neustart zurückgeholte
    Navigation kommt so hin. Ab Android 12 geht es über
    `setAutoEnterEnabled` von selbst ins Fenster, darunter in
    `onUserLeaveHint`; ohne `FEATURE_PICTURE_IN_PICTURE` (Go-Geräte) gar
    nicht.
  - **Klein heißt `pipModeProvider`**: `NavOverlay(compact: true)` zeigt
    unten den Abschnitt (`nav-pip`, seit 0.116.0; bis dahin die Zahlen in
    einer Zeile), die Hülle (`AppShell`) lässt die
    Reiterleiste weg, und der Bildschirm-Schalter gilt nicht (9.4).
    Beim Kleinwerden geht es auf die Karte (`go('/')`).
  - **„Beenden" im Fenster** ist eine `RemoteAction` mit einem Broadcast
    nur an die App (`setPackage`, Empfänger `RECEIVER_NOT_EXPORTED`); er
    kommt als `stop` über den Kanal und endet wie der Knopf. Endet die
    Navigation, während die App klein ist, macht `allow(false)` das
    Fenster zu (`moveTaskToBack`) — es zeigte sonst eine Karte ohne Route.
  - **Kein Test-Netz für Kotlin**: `android_manifest_test` hält Kanalname,
    `supportsPictureInPicture`, die configChanges und das Fehlen von
    `SYSTEM_ALERT_WINDOW` fest; ob es kompiliert, sagt nur
    `flutter build apk --debug --flavor github`.
- **„Bergab" ist eine Stufe, keine Kurve** (gefunden bei #380,
  `docs/routing-messung.md`): `edgeTimeS` nimmt die
  Abfahrtsgeschwindigkeit, sobald `lossM > gainM` — auch um Millimeter.
  Wer Höhen je Kante rundet oder in ein anderes Format bringt
  (Routing-Kacheln, Konzept-Routing 11.3), hält die Richtung dieses
  Vergleichs fest; auf Dezimeter gerundet fuhren flache Straßen mit
  9 mm Abstieg plötzlich flach, und Suchen wichen bis 2 % ab.
- **Vorgebackene Routing-Kacheln** (#380, seit 0.136.0;
  Konzept-Routing 11, `routing_tile.dart` rein, `routing_pieces.dart`
  im UI-Isolate). Der Planer und „Zurück zur Route" bauen den Graphen
  nicht mehr in einem Stück: Je z13-Kachel backt der Rechen-Isolate
  EINMAL ein Stück (`bakeTiles`, dieselben Funktionen wie der Bau eines
  Rahmens, über NUR die Wege dieser Kachel), der UI-Isolate legt es in
  den Kachelspeicher (`TileLayer.routing`), und jede weitere Planung
  setzt aus Stücken zusammen (`stitchPieces`: gleiche Mikrograd sind
  ein Knoten, dann nur die Randknoten mit der 2-m-Regel). Sechs Dinge,
  die man wissen muss:
  - **Frisch heißt: derselbe Bau** (`pieceBuild`:
    `r<Format>.<Fassung>:<Karte>:<Höhen>:<Wege>`, `-` für fehlend).
    `findPieces` fragt je Kachel des Rahmens nur die Bauten
    (`TileStore.builds`), nicht den ganzen Index — der einer ganzen
    Region hätte Millionen Zeilen. „Aktualisieren" ändert einen Bau, das
    Stück ist alt und wird ohne Netz neu gebacken.
  - **Wer eine Bauregel ändert, zählt `kRoutingTileVersion` hoch**
    (M1-Regeln, `kGraphJoinM`, Wegegüte, Höhenproben, `steepWeightAt`,
    `classifyWay`). `routing_tile_test` hält die Werte als Kopie fest und
    wird rot, sobald sich einer ändert — dann Fassung hoch UND Kopie
    nachziehen. Die KOSTEN gehören nicht dazu: Sie rechnen aus dem Stück.
  - **„Bergab" überlebt das Runden** (`_cmLoss`, siehe „Bergab ist eine
    Stufe" oben); Anstieg und Abstieg in Zentimetern, die Richtung des
    Vergleichs bleibt — in beide Richtungen.
  - **Gespeichert wird nur, was aus dem Speicher kam.** Online ergänzte
    Kacheln (#187) backen nur für die Sitzung: `routingPieceSessionProvider`
    ist ein `Expando` an den Bytes aus `OnlineTileCache` (dieselbe Kachel
    kommt dort als dasselbe Objekt zurück). Ein Stück, das drüben nicht
    lesbar ist, steht in `GraphReport.broken`, `keep` nimmt es aus dem
    Speicher.
  - **`GraphInput.bake`** schaltet den Weg; ohne baut `buildGraphFrom`
    wie bis 0.135 in einem Stück. Die Kalibrierung bleibt dort (sie
    liest keine Höhen — ihr Stück trüge „ohne Höhen" und wäre neben
    gespeicherten Höhen sofort alt), ebenso die Mess-Skripte.
  - **Im Web** rechnen Schreiber und Leser der Varints mit Multiplikation
    statt `<<` (dart2js: 32 Bit); `test/web/routing_tile_browser_test.dart`
    vergleicht Backen, Packen und Zusammensetzen mit Zahlen der VM.
  - **Im Hintergrund nach dem Speichern** (seit 0.137.0,
    `routing_bake.dart`, Weg C): `AreaDownloadNotifier` ruft
    `routingBakeProvider.bakeAreas` nach dem Speichern eines Bereichs und
    nach „Aktualisieren" (alle Bereiche der Region). Je Block
    `findPieces` → `readRoadTiles` mit `only` = Block + Ring und
    `covered` = frische Stücke + Ring (der Ring liefert nur das
    Wege-Archiv) → `LoopPlanRunner.bake` im EIGENEN Runner →
    `PieceLookup.keepPieces`. Wartet vor jedem Block, solange der Planer
    rechnet (`routingBakePlannerBusyProvider`). Die ganze Region,
    unvollständige, übernommene und Bereiche unter z13 backen nicht
    (`RoutingBakeNotifier.bakes`). Wer `LoopPlanRunner` implementiert
    (auch Test-Spione), braucht `bake`. Der Strukturtest
    (`graph_isolation_test`) sucht `bakeTile` auch in Kommentaren —
    dort heißt es „das Backen".
  `tool/routing_tiles_measure.dart` war der Prototyp; gemessen am Gerät
  wird nach dem Merge (Szenarien 2′ und 4 aus #356, Konzept 11.6).
