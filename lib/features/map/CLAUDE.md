# TrailBuddy — Arbeitsregeln für `lib/features/map/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Orte auf der Karte** (#12, `lib/features/map/poi*.dart`): seit
  0.18.0 als fertige Dateien vom EIGENEN Kartenhost (Konzept
  `docs/konzept-offline-karten.md` 3.4, Weg 3 — Betreiber, 2026-09-28),
  vorher live von `overpass-api.de`. `poi-data.yml` (monatlich am 2.,
  von Hand mit `plan`/`publish`) liest die Geofabrik-Extrakte aller
  Länder im Kartenrahmen (seit #73: DACH, Liechtenstein, Norditalien,
  Ostfrankreich, Benelux, Dänemark, Südschweden, Tschechien, Polen,
  Slowakei, Ungarn, Slowenien, Kroatien) mit `osmium`, filtert jedes
  gleich nach dem Download vor (eins nach dem anderen, sonst reicht die
  Platte nicht), `tool/poi_extract.py` behält die 15 Arten IM RAHMEN
  (`--bbox`, `POI_BBOX` = `DACH_BBOX` der Karte = Rahmen der Übersicht,
  ein Test hält alle drei zusammen) und schreibt je Rasterzelle und Gruppe EINE Datei
  (`pois-<build>/<zeile>_<spalte>.<gruppe>.json`) plus das Manifest
  `pois.json`, das den Bau und die Zellen mit Inhalt nennt; Upload nach
  R2 neben das Archiv, dann Rücklesen der öffentlichen Kopie mit
  Origin-Header und Byte-Vergleich je Gruppe. Fünf Dinge, die man wissen
  muss:
  - **Warum nicht aus den Kacheln:** Protomaps schreibt Hütte,
    Gasthaus, Trinkwasser & Co. erst ab Zoom 15 in die Kacheln (in der
    Quelle nachgelesen, 2026-09-28), unser Archiv endet bei 13, und der
    Stil zeigte sie ohnehin erst ab 16 und nur als Text. Ein
    Zoom-15-Archiv wäre ein Vielfaches je gespeichertem Bereich.
  - **Die Arten stehen ZWEIMAL** — `PoiKind` in `poi.dart` und
    `tool/pois/kinds.json` für das Werkzeug; `test/map/poi_test.dart`
    hält Reihenfolge, Regeln und Gruppen zusammen. Die ERSTE passende
    Art gewinnt (Biergarten vor Gasthaus: `biergarten=yes`); Parkplätze
    ohne `access=private/no`; Ladesäulen nur mit `bicycle=yes`.
  - **Das Manifest gilt je App-Lauf, eine Zelle je Gruppe wird einmal
    gefragt**, und nur, wenn das Manifest sie nennt — eine leere Zelle
    kostet keine Anfrage. Erst ab Zoom 12, Raster 0,1° × 0,15° (dasselbe
    `floor()` auf denselben Doubles in Dart und Python); der Filter ist
    gerätelokal (`Settings.poiGroups`, Vorgabe nur „Wasser"). Ist alles
    aus, geht KEINE Anfrage raus. Die kleinen Dateien liegen im
    Edge-Cache (anders als das Archiv, #55); kein neues Netzziel, der
    Host steht schon in der Datenschutzerklärung.
  - **Ohne veröffentlichten Bau gibt es keine Orte**: 404 auf das
    Manifest heißt „Orte gerade nicht erreichbar", bis `poi-data.yml`
    einmal auf `main` gelaufen ist. Ein Bau mit unter 100 000 Orten
    wird nicht veröffentlicht (kaputter Extrakt); der vorige Bau bleibt
    einen Lauf lang liegen.
  - Der Test-Harness hängt `FakePoiSource` ein, weil die Karte beim
    Einpassen auf einen Trail über Zoom 12 liegt. Die Nadeln liegen über
    den Trail-Linien (Fassade) und tragen nie eine der Trail-Farben; das
    Kuchenstück ist gezeichnet (`PoiGlyph`). Der Detailfilter
    (`Settings.poiHiddenKinds`) blendet nur aus, geladen wird je Gruppe.
- **Glatte Linien und Namen am Trail** (seit 0.44.0, Betreiber
  2026-09-29): Die Trail-Linien werden fürs BILD mit Chaikin geglättet
  (`line_smoothing.dart`, drei Durchgänge, NUR an Ecken ab 12° und
  Abschnitten ab 2 m, Anfang und Ende fest, einmal je Trail im
  Karten-Screen gemerkt); Abgleich, Länge, Höhen, Deckung und
  Zerlegung rechnen weiter mit den Originalpunkten, die Trefferprüfung
  mit der geglätteten Linie. MapLibre zeichnet Linien mit runden Ecken
  (`RoundPolylineLayer` — das Paket setzt kein `line-join`, spitz auf
  Gehrung sah jede Kehre wie ein Knick aus). Der Name steht ab Zoom 14
  (`kLineLabelMinZoom`, 256er; seit 0.74.2 dieselbe Stufe wie die
  Schilder, #184) AUF der Mittellinie (seit 0.74.2, #181 — daneben las
  er sich wie der Name des Nachbarwegs; kein `text-offset`; der weiße Saum
  `kLineLabelHaloWidth`, 2,5 px statt 1,5, hält ihn auf jeder
  Linienfarbe lesbar — beide Engines lesen die Zahl): MapLibre als Symbol-Ebene
  `symbol-placement: line` über allen Linien (`LineLabelLayer`, Kollision
  und Wiederholung macht MapLibre), **Schrift `noto-sans-medium`** — der
  Glyphen-Ordner, nicht „Noto Sans Medium" (der Stil wird umgeschrieben,
  diese Ebene nicht; der falsche Name lässt den Text still weg, ein Test
  prüft den Ordner). flutter_map kann keinen Text auf einem Pfad: einmal
  in der Mitte, gedreht, nie kopfüber (`lineLabelAnchor`).
  **Flüssig bleibt es, weil nichts unnötig übertragen wird** (gemessen
  2026-09-29, 200 Trails à 2 km): Das Glätten sind wenige ms einmal je
  Laden; teuer war die Übertragung an MapLibre (GeoJSON-Text, 30–60 ms auf
  dem Rechner), und die lief bei JEDEM Neuaufbau des Karten-Screens —
  jede Positionsmeldung, jeder Kamera-Stillstand. `MapLibreLineCache`
  gibt für eine unveränderte Gruppe (Stil, DIESELBEN Punktlisten, Namen)
  die alten Ebenen-Objekte zurück, das Paket überträgt dann nichts
  (0,2 ms). Die Glättung nur an Ecken hält die Punkte beim 2,5-Fachen
  statt beim 7,7-Fachen. Wer die Punktlisten je Aufbau neu anlegt, hebt
  den Cache aus — der Test in `trail_line_look_test.dart` hält es fest.
  Seit 0.82.1 hängt die Glättung an der PUNKTLISTE, nicht am Trail, und
  die Ebenen gleicht `keyed_layers.dart` ab (siehe „Speichern ohne
  Neuladen des Netzes").
- **Eigene Position** (`lib/features/map/position_provider.dart`,
  PilzBuddy-Muster): Der Strom (`positionStreamProvider`) fragt NIE nach
  der Berechtigung, nur der Knopf „Meine Position" über
  `positionFixProvider` — kein Systemdialog beim Start (Play: Prominent
  Disclosure). Nur Vordergrund (`ACCESS_FINE/COARSE_LOCATION`, kein
  Background); die Position verlässt das Gerät nicht. Punkt in
  `MapPalette.ride` (nicht Blau — Blau heißt S1), Punkt und
  Kreis fangen keine Tipps ab. Gesten drehen die Karte nie
  (`InteractiveFlag.rotate` aus, MapLibre `rotate: false`); gedreht wird
  nur über `MapViewController.move(bearing:)` in der Folgeansicht der
  Navigation (#232, `lib/features/routing/CLAUDE.md`), und JEDE andere
  Bewegung und jedes Einpassen nordet wieder ein. Gedreht meldet
  flutter_map ein größeres Sichtfenster (die Hülle des gedrehten
  Rechtecks), die gerechnete Zoomstufe liegt dann bis etwa eine Stufe
  zu tief — für Orte und offizielle Trails egal, für Taps nicht: Die
  sind in der Folgeansicht aus. Der Harness hängt `fakePosition` /
  `FakePositionFix` ein, für Fixe nacheinander `positionStream`
  (Broadcast — `ref.invalidate` abonniert neu).
- **Karten-Engine und Fassade** (#31 Schritt 1, `lib/features/map/map_view/`,
  seit 0.16.0; PilzBuddy als Vorlage): `MapScreen` beschreibt nur noch,
  WAS die Karte zeigt (`MapViewLayers`: Kreise < Linien < Marker), und
  greift über `MapViewController` auf die Kamera zu. WIE gerendert wird,
  entscheidet `mapViewBuilderProvider`: **Android MapLibre** (nativer
  GPU-Renderer, `maplibre` 0.3.5 exakt gepinnt), **Web flutter_map** —
  ohne Schalter, `kIsWeb` ist eine Kompilierzeit-Konstante. Web sieht
  `package:maplibre` nie (bedingter Import, ein Test hält es fest).
  `flutter_map_view.dart` bleibt im Android-Build: Baut der
  MapLibre-Style nicht, fällt die Ansicht darauf zurück — ohne Style
  lieber die alte Karte als gar keine. Sechs Dinge, die man wissen muss:
  - **Tipps löst die FASSADE auf, nicht die Engine**
    (`map_hit_test.dart`, pur). TrailBuddys Inhalt sind Linien, und die
    beiden Engines treffen Linien verschieden. EINE Rechnung in Dart
    (Web-Mercator ohne Drehung, 12 px plus halbe Strichbreite) gibt auf
    beiden dieselbe Antwort: Linien zuerst (oberste gewinnt: Netz über
    offiziellen Trails), dann Marker. Die Nadeln tragen deshalb KEINEN
    `GestureDetector` mehr; `hitValue` ist ein `Trail`, `OfficialTrail`
    oder `Poi`, die Fahrt und der Positionspunkt haben keinen.
  - **Marker liegen immer ÜBER den Linien** — MapLibre kann Widgets nur
    über Style-Ebenen zeichnen, flutter_map folgt, damit beide Engines
    dasselbe Bild zeigen. Was ein Tipp trifft, entscheidet trotzdem die
    Prüfung, nicht die Zeichenreihenfolge (Abweichung von „Nadeln unter
    den Linien" aus #12).
  - **Die Kamera setzt MapLibre nur über `moveCamera`** (#68, seit
    0.26.1): `fitBounds` und `animateCamera` des Pakets laufen auf
    Android über `MapLibreMap.animateCamera`, und das WIRFT bei einer
    Dauer ≤ 0 ms („Null duration passed into animateCamera") — so kam
    jedes Einpassen von 0.17 bis 0.26 als Fehlerbericht an. Eingepasst
    wird mit `cameraToFit` (pur, `map_hit_test.dart`, Mitte in Mercator,
    Obergrenze in EINEM Schritt), dieselbe Rechnung fährt der Fake.
    `test/map/maplibre_camera_test.dart` hält am Quelltext fest, dass
    die Engine weder `fitBounds` noch `animateCamera` noch
    `Duration.zero` benutzt. Wer eine Animation will: Dauer > 0.
  - **Die Zoomstufe wird GERECHNET, nie gemeldet** (`MapViewCamera.zoom`
    aus Fenster und Pixelbreite, 256er-Web-Mercator). MapLibre zählt in
    512er-Kacheln, flutter_map in 256ern; dieselbe Zahl hieße zwei
    Maßstäbe (PilzBuddy 1.98.0). Orte (ab 12) und offizielle Trails
    (ab 8) hängen an der gerechneten. Die MapLibre-Seite rechnet an
    `initZoom`/`minZoom`/`maxZoom` und in `zoom` je eins um.
  - **Orte und offizielle Trails laden bei Kamera-STILLSTAND**
    (`onCameraIdle` → `_camera` im Screen → `poiCellsFor` /
    `officialViewFor`, pur), kurz verzögert, je Ausschnitt EIN Versuch.
    Sie sind keine Ebenen innerhalb der Engine mehr (`MapCamera.of` gibt
    es in MapLibre nicht).
  - **MapLibre trägt Farbe, Breite und Strich am LAYER**, deshalb
    gruppiert `polylineLayers` nach Stil (ein Netz kann hunderte Trails
    haben; PilzBuddy legt eine Ebene je Linie an, das trägt hier nicht);
    ein Rand wird zu einer breiteren Ebene darunter, ein Strichmuster in
    Bildpunkten zu Vielfachen der Breite. Der Genauigkeitskreis ist ein
    Polygon in Metern — `circle-radius` wäre ein Pixelmaß. `alignment`
    wird gespiegelt (PilzBuddy #409: bei `topCenter` hängt die Nadel
    sonst 40 px unter ihrem Ort). Marker werden bei Idle auf das
    Sichtfenster plus 25 % gefiltert (`visibleMarkers`), weil
    `WidgetLayer` jeden Marker in jedem Frame positioniert.
  - **Die Onlinekarte ist EIN Archiv auf dem eigenen Host** (#31
    Schritt 2, seit 0.17.0; `online_map.dart`, `map_providers.dart`):
    DACH als Protomaps-Basiskarte bis Zoom 13 auf Cloudflare R2 hinter
    `tiles.mcbuchi.de/trailbuddy/`, geschnitten, geprüft und
    hochgeladen von `map-data.yml` (monatlich und von Hand;
    `tool/map_tiles.py` prüft den Auszug gegen die Quelle UND die
    öffentliche Kopie über Range-Anfragen wie die App). Die App holt
    erst `dach.json` (den Zeiger auf `dach-<build>.pmtiles`) und liest
    dann kachelweise per Range — im Web `PmTilesArchive.fromUri`, in
    MapLibre `pmtiles://https://…`. Dateien mit Datum sind unveränderlich,
    nur der Zeiger wechselt: Eine Sitzung merkt sich Verzeichnisse, und
    ein überschriebenes Archiv ließe die Versätze in eine andere Datei
    zeigen; der vorige Stand bleibt einen Lauf lang liegen. Kein
    OSM-Raster mehr, auf keiner Plattform. Ohne Empfang wird das Manifest
    gar nicht erst geholt; ohne Manifest (Host weg, Datei kaputt) ist die
    Übersicht die Karte — still, und nur ein Fehler, der nicht nach
    Funkloch aussieht, wird gemeldet. **Das Manifest hat eine Frist**
    (#183, `kMapManifestTimeout`, 10 s), und der MapLibre-Stil wartet
    darauf nur `kMapManifestPatience` (1,5 s, `withinOrNull` in
    `lib/core/patience.dart`), dann zeichnet er die Übersicht und baut bei
    spätem Manifest neu — bei „Netz gemeldet, nichts kommt durch" stand
    die Karte vorher leer, bis das System den Abruf abbrach. Beobachtet
    wird dort `mapManifestProvider.future`, nicht der Zustand: Ein
    Zustandswechsel mitten im ersten Aufbau ließ dessen `.future` ohne
    Zuhörer nie fertig werden. Die Adresse ist eine KONSTANTE, keine
    Konfiguration: `test/release_workflow_test.dart` hält
    `kMapTilesBase` und `PUBLIC_BASE` im Workflow zusammen,
    `test/privacy_policy_test.dart` die Erklärung. R2-Zugang: die drei
    Secrets `R2_*` (API-Token, Object Read & Write auf den Bucket);
    fehlen sie, sagt es die Run-Summary. Bucket `buddy-tiles` mit
    Präfix je App — PilzBuddy kann später denselben Host nutzen. **Der
    Bucket hat EU-Jurisdiktion, und sein S3-Endpunkt heißt deshalb
    `<account>.eu.r2.cloudflarestorage.com`** — ohne `.eu` findet der
    Upload den Bucket nicht (Betreiber, 2026-09-28). **Bot Fight Mode
    ist für die Zone `mcbuchi.de` AUS** (#55): Im Free-Plan gilt er
    zonenweit ohne Ausnahme je Hostname und stellte dem Runner eine
    Managed Challenge (`403`, `cf-mitigated: challenge`), die kein
    Client der App lösen kann; der Verify-Schritt nennt sie seither mit
    Ray-ID. DDoS-Schutz ist davon unberührt. Was bleibt, ist ein
    Kostenrisiko (das Archiv ist zu groß für den Edge-Cache, jede
    Range-Anfrage ist eine R2-Class-B-Operation) — die Rate-Limiting-
    Regel und die Nutzungsbenachrichtigung stehen in #55, die Zahlen in
    `docs/konzept-offline-karten.md` Abschnitt 7.
  - **Der Stil ist ERZEUGT, die Übersicht auch** (`assets/map_style/`,
    `assets/offline_maps/overview_dach.pmtiles`, Zoom 0–7, ~9 MB;
    Glyphs `assets/map_glyphs/`, SIL OFL). `tool/transform_map_style.py`
    (u. a. `emphasize_paths`: Forstwege und Pfade als eigene Ebenen —
    Trails SIND die Wege) muss ein Fixpunkt bleiben;
    `tool/generated_assets.py --check` prüft Prüfsummen und Fixpunkt in
    CI, nach echtem Neu-Erzeugen `--update` im selben Commit. Die
    Übersicht liegt unter der Onlinekarte, sobald kein Empfang besteht
    ODER es keine Onlinekarte gibt (beide Engines dieselbe Regel); seit
    Schritt 2 ist das derselbe Stil aus demselben Format, PilzBuddys
    #137 (zwei Kartenstile nebeneinander) gilt hier nicht mehr. Auf dem
    Telefon aus einer materialisierten Datei, im Browser aus dem
    Speicher (`fromBytes`). `latlong2` 0.9 und `archive` 3.x, weil
    `pmtiles` 1.x daran hängt.
  Widget-Tests fahren `FakeMapView` (`test/fakes/fake_map_view.dart`):
  Marker-Kinder in einem `Wrap`, Kamera synchron simuliert, Tipps über
  DIESELBE Trefferprüfung (`tapMapAt`, `fakeMapLayers`);
  `useRealMap: true` pumpt die flutter_map-Engine für deren Interna. Die
  MapLibre-Platform-View ist im Widget-Test nicht renderbar — ihr Gate
  ist das Gerät, geprüft sind Composer, Style-Provider, Trefferprüfung
  und die Textzusagen (`test/map/`).
- **Die Tastatur überlagert, sie schiebt nicht** (seit 0.82.1, Feldbericht
  2026-10-02 „abgestürzt beim Eintragen von Trail-Details"; PilzBuddy
  #397): `resizeToAvoidBottomInset: false` an der Hülle (`router.dart`)
  UND am Scaffold der Karte. Die Karte hat kein Textfeld, alle liegen in
  Dialogen und Blättern darüber; ausweichend schrumpfte sie Bild für Bild
  der Tastatur-Animation, und mit ihr die native Fläche von MapLibre. Im
  Digest 2026-W40 stand dazu ein ANR aus 0.82.0 (Haupt-Thread in einem
  Systemaufruf, RSS 868 MB) — der Zusammenhang ist möglich, nicht
  belegt, und Sterne öffnen keine Tastatur (siehe darüber). Ein neues Textfeld IM Body der Karte müsste sein Inset selbst
  einrechnen. `test/flows/keyboard_inset_flow_test.dart` (Gegenprobe
  ohne die Zeile: rot).
- **Die Legende auf der Karte** (#182, seit 0.77.0,
  `lib/features/map/map_legend.dart`; Feldwunsch „ausklappbar, aber kaum
  sichtbar"): zu eine 16 dp schmale Lasche links mittig (Trefferfläche
  44 dp), auf die Proben untereinander. Vier Dinge, die man wissen muss:
  - **Eine Liste** (`legendSamples`) mit denselben Farben und Mustern
    wie die Karte (`mapGrades`, `mapLines`, `kLineDash*`,
    `kHaloDashExpert`) — ändert sich dort ein Muster, zieht sie mit. Auf
    dem Landton der Karte, auch in der dunklen App. **Wörter = Bedeutung**
    (#231, seit 0.83.5, Betreiber: Variante A): Gruppen-Überschriften
    (`legendGroupTitle`), beim Zustand die Wörter des Melde-Dialogs statt
    des Aussehens. Tour-Schritt 3 und „Die Karte lesen" verbinden beides
    („bröckelig heißt ausgefahren"); `map_tour_flow_test` hält Legende
    und Tour zusammen.
  - **Auf oder zu merkt das Gerät** (`Settings.mapLegendOpen`,
    `map_legend_open`, Vorgabe zu; `FakeSettings` ebenso).
  - **Eine offene Leiste hat den Platz** (Offline-Karten, Planer) und
    ein scharfes Zeichenwerkzeug auch; danach steht die Legende wieder,
    wie sie war.
  - **124 dp breit, weil die Blase der Tour daneben passen muss**
    (Schritt 3 leuchtet sie aus; die Blase braucht 200 dp, auf einem
    360-dp-Telefon). `test/flows/map_legend_flow_test.dart` misst sie
    hochkant und quer.
- **Die Ebene „Wege"** (#212 PR 2, seit 0.89.0, `way_layer.dart`;
  Aussehen `docs/design/README.md` 5a): Forstweg-Güte und
  Pfad-Schwierigkeit aus OSM, ein drittes Archiv vom eigenen Host
  (`ways.json` → `ways-<build>.pmtiles`, gebaut von `way-data.yml` /
  `tool/way_archive.py`). Ab Werk an, Schalter „Wege" in „Kartenebenen"
  (`Settings.wayLayerEnabled`, `way_layer_enabled`). Fünf Dinge, die man
  wissen muss:
  - **Das Format steht zweimal** — `kWaysFormat`/`kWaysZoom`/
    `kWaysLayer`/`kWaysKey` hier, `FORMAT`/`ZOOM`/`LAYER`/`KEY` und die
    Klassen-Codes im Werkzeug; `test/release_workflow_test.dart` und
    `test/map/way_layer_test.dart` halten beide Seiten zusammen. Ein
    fremdes Format lehnt das Manifest ab ⇒ keine Ebene. **Seit 0.91.0
    Format 2** (#213): 7 „Forstweg sehr schlecht" (grade5, `smoothness`
    ab bad, `surface=mud`) und 8 „Pfad sehr schwer" (ab S4/T4), an
    Pfaden `u` = `mtb:scale:uphill` für das Routing; 1–6 behielten ihre
    Codes. Deshalb zeichnet die App alte Bereichs-Archive (Format 1,
    0.90.0) unverändert richtig, nur gröber — die werden beim Öffnen
    nicht geprüft. Umgekehrt sehen Apps bis 0.90.0 nach dem Neubau von
    `way-data.yml` keine Ebene mehr (Manifest abgelehnt, still).
  - **Nur Zoom 13 im Archiv**: Darunter zeigt keine Engine etwas
    (MapLibre-Quelle min = max = 13, vector_map_tiles liefert unter dem
    `minimumZoom` des Providers leere Kacheln), darüber wird
    hochskaliert. Keine Ersatzkachel (`maximumTileSubstitutionDifference: 0`).
  - **Über ALLEN Kartenquellen, unter den Trails** — auch über den
    gespeicherten Bereichen, deren deckende `earth`-Fläche sie sonst
    zudeckte. MapLibre: `MapStyleOverlay` im Composer nach allen
    Vektorquellen; flutter_map: eigene `VectorTileLayer` nach der der
    Bereiche. `area_layer_order_test` und `maplibre_style_provider_test`
    halten beide fest.
  - **Zwei Fassungen derselben Tabelle** (`wayStyleLayers(dashes:)`):
    MapLibre mit Band und Strich, flutter_map ohne Strich, weil
    `vector_tile_renderer` `line-dasharray` verwirft — dort trägt die
    Helligkeit (`webColor`). Wer eine Klasse ändert, prüft beide und die
    Breite gegen die Basislinie (Test liest den Stil). **Forstwege sind
    seit 0.98.0 eine Doppellinie** (#263): ein heller, deckender
    Mittelstreifen (`kWayTrackCore`, `kWayCoreShare`) auf dem Strich, in
    BEIDEN Engines — `vector_tile_renderer` kennt weder `line-offset`
    noch `line-opacity`, zwei versetzte oder halb durchsichtige Linien
    gingen dort nicht.
  - **Das Wege-Manifest wartet so lange wie das der Karte** und
    gleichzeitig (`patiently` in `maplibre_style_provider.dart`); kommt es
    später, baut der Stil neu. 404 (noch kein Bau), fremdes Format und
    Funkloch gehen still durch, damit nicht jede Installation im Digest
    steht, solange `way-data.yml` nicht veröffentlicht hat. Der Harness
    hängt `waysManifestLoaderProvider` auf null — ohne die Zeile fragte
    jeder Kartentest den Host. Offline kommen die Wege aus den
    gespeicherten Bereichen (seit 0.90.0, `lib/features/offline_areas/CLAUDE.md`),
    als oberste Wege-Quelle in beiden Engines.
