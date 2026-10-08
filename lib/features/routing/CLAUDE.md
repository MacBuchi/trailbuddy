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
  - **Höhen je Kante über `HeightReader.climbAlong`** (`addClimbs`); eine
    Kante ohne Höhe bleibt flach und zählt (`edgesWithoutHeights`,
    `PathSummary.heightsComplete`). Dabei gefunden: Ein Punkt genau auf
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
  pur, `trail_head_sheet.dart`, `trail_head_providers.dart`): im
  Trail-Blatt neben „Anfahrt", vom eigenen Standort zum Anfang des
  Trails über den Graphen der Bereiche (A*). Vier Dinge, die man wissen
  muss:
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
  „Navigation rund"). Sechs Dinge, die man wissen muss:
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
    bleibt stehen, solange Start und Trails dieselben sind.
  - **Der getippte Start ist ein Dialog mit der Karte**
    (`LoopSession.pickingStart`, oberster Knopf der Leiste oder „Auf der
    Karte tippen" in den Parametern): oben ein Banner mit Abbrechen, der
    nächste Tipp — auch auf eine Linie — ist der Start (Fahne in der
    Marke, `_takeLoopStart`); Zurück bricht ab. Keine eigene
    Zeichenfläche: Ein Tipp ist eine Geste, die die Fassade schon hat.
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
    Trails auflegen laufen weiter im UI-Isolate. **Seit 0.80.2 behält
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
    nicht schon beim Laden gewählt war.
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
    läsen sich wie ein Fehler. Während gelesen wird, steht der Platz
    schon da, damit die Knöpfe nicht rutschen.
  - **`trail-head-profile` ist der Bio/E-Bike-Schalter**, das Profil heißt
    `trail-head-elevation` (im Planer `loop-elevation`, `loop-profile` ist
    dort ebenfalls der Schalter) — beim Bau kollidiert und nur als
    „Duplicate keys" sichtbar.
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
    Fahrt den Graphen ihrer Bereiche — `loadRoadGraph(requireComplete:
    false)` liefert dafür auch einen halben Graphen (Abschnitte in
    fehlenden Kacheln sind „abseits" und zählen nicht); geplant wird
    nie auf einem halben. Geplante Fahrten, Fahrten ohne Profil (vor
    0.70.0) und ohne Höhen lernen nichts; der Satz danach sagt, was
    gezählt hat.
  - **Gerätelokal** (`Settings.riderCalibration`, JSON je Profil,
    `RiderCalibrations.encode/parse`, Unlesbares ⇒ Vorgaben); nie aus
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
    Planung plus ihre Höhenkacheln (R2-Class-B, #55), 10 s Frist je
    Schritt, ein Netzfehler beendet nur das Nachladen; nur für die
    Sitzung im Speicher (`OnlineTileCache`, Behalten ist #155);
    abschaltbar über `LoopPrefs.fillOnline` („Fehlende Wege online
    ergänzen", gilt auch für den Weg zum Trail). Was das Blatt dazu sagt,
    steht an EINER Stelle (`planningCoverageNote`). Der Harness hat kein
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
