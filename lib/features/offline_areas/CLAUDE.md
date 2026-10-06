# TrailBuddy — Arbeitsregeln für `lib/features/offline_areas/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

  - **Gespeicherte Bereiche** (Konzept-Schritt 3, seit 0.19.0,
    `lib/features/offline_areas/`): Ein Bereich ist EIN PMTiles-Archiv
    (Zoom 8 bis zum Zoom des Hosts), geschrieben auf dem Gerät von
    `pmtiles_writer.dart` aus Kacheln, die die App per Range aus dem
    Host-Archiv geholt hat (Bytes unverändert, dieselbe Kompression) —
    der eigene Schreiber ist hier erlaubt, weil kein `pmtiles extract`
    auf dem Gerät läuft und der Download jedes Archiv sofort mit dem
    Leser beider Engines zurückliest (Zählung und Stichprobe). Ablage
    je Plattform (`AreaStore`): Dateien unter `offline_maps/areas/`
    (Android, Backup-Ausschluss), IndexedDB über `idb_shim` im Browser
    (Besitzer von Name und Version: `lib/data/browser_db.dart`), der
    Speicher im Test. Sechs Dinge, die man wissen muss:
    - **Die Größe ist gemessen, nicht geschätzt**: `plan()` schlägt jede
      Kachel im Verzeichnis nach und summiert die Längen; Obergrenze
      `kAreaMaxTiles` (40 000) je Bereich.
    - **Ein Bereich hat eine FORM, kein Rechteck** (`AreaShape`, seit
      0.24.0): `RectShape` für den Ausschnitt, `TileSetShape` für
      „Entlang meiner Trails" — die Kacheln bei `kAreaShapeZoom` (13),
      denen ein Trail näher als `kAreaTrailsCorridorKm` (1 km) kommt
      (`AreaShape.alongLines`, abgetastet je halben Korridor, Quadrat
      statt Kreis), andere Zooms als Eltern/Kinder daraus. Anlass: Das
      Rechteck um alle Trails lief beim Betreiber auf 40 779 Kacheln.
      Die Form steht im Index (`shape`; Einträge davor: der Rahmen IST
      die Form), „Aktualisieren" plant sie neu; `bounds` ist nur die
      Hülle — innerhalb kann eine Kachel FEHLEN, der Wege-Index fragt
      deshalb das Archiv (`ProviderException` ⇒ nicht gedeckt). Die
      Orte-Zellen kommen aus der Form, nicht aus der Hülle.
    - **Die Werkzeugleiste „Offline-Karten" zeigt, was liegt** (Stufe B
      seit 0.25.0, seit 0.27.0 als Leiste; `offline_tool_rail.dart`,
      `area_overlay.dart` pur). Der Knopf „Offline-Karten" (rechts, wie
      alle Kartenknöpfe; bis 0.74.x der Ebenen-Knopf, #190) öffnet links
      eine schmale Leiste — das halbhohe Blatt davor deckte die Karte zu
      (Betreiber, 2026-09-29). Fünf Dinge, die man wissen muss:
      - **Solange sie offen ist** (`offlineOverlayProvider`), liegt EIN
        Polygon unter allem (`MapViewPolygon`, Löcher auf beiden
        Engines): Ausschnitt plus eine Fensterbreite Rand abgedunkelt,
        die gespeicherten Kacheln als Löcher, aus den FORMEN im Index.
        Ohne Bereiche ist alles dunkel — das IST die Aussage. Um den
        ganzen Bestand läuft seit 0.31.0 ein durchgehender Rand in der
        Textfarbe des App-Modus (`offlineCoverage`, `tileOutline`: der
        Umriss der Kachelmenge, Läufe je Gitterlinie, keine Nähte
        zwischen den Rechtecken; kein Rand am Bildrand, wo der Nachbar
        nicht gefragt wurde).
      - **Immer die Kacheln des Bereichs, nie abhängig vom Kamera-Zoom**
        (`offlineOverlayZoomOf` = min(Zoom des Bereichs, 13)). Bis 0.26.x
        waren es zwei Stufen über der Kamera, und die Hervorhebung sprang
        beim Zoomen. Damit weit draußen nicht tausende Löcher entstehen,
        fasst `mergeTileRects` Kacheln zu Rechtecken zusammen (Läufe je
        Zeile, gleiche Läufe übereinander); über `kOfflineOverlayMaxHoles`
        fällt nur der Rand weg, nie die Stufe.
      - **Schließen ist EIN Weg** (`_closeTools`): X, Knopf und
        Zurück-Taste (`PopScope`, `canPop` nur bei geschlossener Leiste);
        mit Änderungen im Entwurf fragt `confirmDiscardDraft`.
      - **Die Leiste steht mittig links** zwischen den Bannern (oben
        56 dp) und Maßstab/Quellenhinweis (unten 64 dp), seit 0.30.0 im
        Look aus Design 3e: 52 dp breit (`kRailWidth`), Knöpfe 44 dp
        (`kMapButtonSize`, Handschuh) mit `MaterialTapTargetSize.shrinkWrap`
        — sonst polstert Material auf 48 dp —, Gruppen durch 8 dp Luft,
        aktives Werkzeug in Gegenhelligkeit, Speichern Lime, der Zähler in
        Mono darunter. Auf einem kleinen Telefon hochkant (360 × 740)
        passt sie ganz, darunter scrollt sie (der Layout-Test misst auf
        Telefonmaß, `tapRail` scrollt auf 800 × 600). Solange sie offen
        ist, rücken Maßstab und Quellenhinweis neben sie
        (`MapViewConfig.bottomLeftInset`); flutter_map zeigt seinen
        Hinweis deshalb links wie MapLibre. Rechts stehen die runden
        Kartenknöpfe (`map_buttons.dart`): Kartenebenen, Offline-Karten,
        Runde, Position (44 dp), unten die Aufnahme (60 dp, Lime; läuft
        die Fahrt Orange mit Stop). Ein offenes Menü markiert seinen Knopf
        mit Rand in der Marke. Die Glühbirne steht seit 0.75.0 abseits,
        oben rechts neben den Bannern (#180); die Banner halten rechts
        IMMER `kBannerRightInset` (52 dp) frei, auch ohne Banner, damit
        nichts unter ihr liegt. `test/map/map_shell_test.dart` hält es hell
        und dunkel fest, samt 8 dp Luft zwischen dem X des Filter-Banners
        und der Glühbirne.
      - **Speichern ist ein Dialog** (`showSaveDraftDialog`): misst
        Kacheln, Bytes UND Orte (`AreaPlan.poiFiles`, die Zellendateien
        kommen schon beim Messen — das Manifest nennt keine Anzahl — und
        der Download holt sie nicht noch einmal), fragt nach dem Namen,
        lädt mit Fortschritt und Abbruch. Orte und offizielle Trails
        stehen NICHT in der Leiste (seit 0.75.0, #190; Betreiber: „genested
        ist UX-Gift"): Der Knopf „Kartenebenen" öffnet ihr Blatt
        (`showMapLayersSheet`) direkt, über jeder Leiste, ohne sie zu
        ändern.
    - **Bereiche zeichnen und bearbeiten** (Stufe C, #67, seit 0.26.0;
      seit 0.27.0 gegen den ganzen Bestand; `area_draw.dart` pur +
      Notifier, `area_draw_overlay.dart`, `area_trim.dart`): Die Leiste
      füllt einen ENTWURF aus ZWEI Mengen bei `kAreaShapeZoom` — was
      dazukommt (`adds`, nie eine gespeicherte Kachel) und was wegfällt
      (`removes`, nur gespeicherte), gerechnet gegen
      `storedTileKeysProvider` (Vereinigung aller Formen,
      `AreaShape.keysAt`). Stift/Ausschnitt/Trails fügen hinzu und nehmen
      ein Wegfallen zurück, der Radierer umgekehrt. Sechs Dinge, die man
      wissen muss:
      - **Die Darstellung hat EINE Regel** (Design Turn 2, seit 0.31.0;
        davor grün dazu, rot weg): Helligkeit = gespeichert, Schraffur +
        gestrichelter Rand = offene Änderung, und die Schraffur hat
        immer die Gegenhelligkeit ihres Grunds — „kommt dazu" hell `/`
        auf dunkel (`kAreaInkLight`), „fällt weg" dunkel gespiegelt `\`
        auf hell (`kAreaInkDark`); den Grund liefert die Maske, eine
        Tönung gibt es nicht (`draftLayers`). Keine neue Farbe: Grün
        heißt „mein Trail". Die Schraffur sind LINIEN (`hatchLines`),
        kein Füllmuster: Ein Muster bräuchte in MapLibre ein Bild im
        Stil. Sie hängen am Weltraster der Kamera-Zoomstufe
        (x ± y = k · 7 px), bleiben beim Verschieben stehen und werden
        bei Stillstand neu gerechnet; über `kAreaHatchMaxLines` gilt der
        Rückfall 2e — halbe Tönung, nur der Rand unterscheidet. Der
        Strich beim Zeichnen folgt derselben Regel (hell dazu, dunkel
        weg, mit Saum in der Gegenhelligkeit). Die Linien tragen keine
        Kennung und liegen unter allen Trails — ein Tipp geht hindurch.
      - **Entfernen braucht kein Netz** (`AreaTrimmer`): Das eigene
        Archiv wird ohne die Kacheln neu geschrieben (derselbe
        Schreiber, gegengelesen, bevor es das alte ersetzt), eine
        gröbere Kachel bleibt, solange darunter noch etwas liegt; die
        Form wird zur `TileSetShape`, Orte-Dateien leerer Zellen fallen
        aus dem Index (die Datei bleibt liegen, gelesen wird nur, was
        der Index nennt). Leer ⇒ der Bereich wird gelöscht. Gespeichert
        wird ERST das Entfernen (lokal), DANN das Laden; scheitert das
        Laden, bleibt im Entwurf nur „kommt dazu" (`dropRemoves`).
      - **Ein Strich ist eine Fläche**: geschlossen (Ende zum Anfang),
        dazu jede Kachel, die der Rand berührt oder die innen liegt
        (`tilesTouchedByRing`: Rand in Zehntelkachel-Schritten
        abgetastet, Inneres je Zeile gerade-ungerade). Ein offener
        Zickzack ist damit eine dünne Fläche; der Radierer nimmt genau
        weg, worüber er läuft. Rahmen über `kAreaDrawMaxSpanTiles` ⇒
        null und ein Satz, keine hängende Rechnung.
      - **Die Zeichenfläche ist ein Flutter-Widget ÜBER der Karte, keine
        Geste der Engine**: Sie liegt nur, solange ein Werkzeug auf
        seinen EINEN Strich wartet, fängt dann jede Berührung ab (die
        Karte steht still, die Kamera vom letzten Stillstand stimmt
        also) und rechnet mit `unprojectFromScreen` — der Umkehrung der
        Trefferprüfung, auf beiden Engines dieselbe Antwort. Nach dem
        Strich ist das Werkzeug weg und die Karte frei; die Fassade
        brauchte dafür keine Gesten-Schnittstelle.
      - **Der Entwurf lebt mit der Leiste**: Schließen verwirft ihn (mit
        Rückfrage), damit auch ein armiertes Werkzeug — sonst stünde die
        Karte fest. Gezeigt wird er nur mit Leiste.
      - **Schraffur je Rechteck, Rand je Umriss** (`mergeTileRects`,
        `tileOutline`), IMMER bei Zoom 13 wie die Maske — ein Rand je
        Rechteck sähe aus wie ein Gitter. MapLibre gruppiert Flächen und
        Linien nach Stil in je EINE Ebene (`polygonLayers`,
        `polylineLayers`).
      - **Gespeichert wird über den Dialog**: „Lädt … · Kacheln · Orte"
        (Netz) und „Gibt … frei · Kacheln" (lokal gemessen); ein Name nur,
        wenn etwas dazukommt. Danach leert der Karten-Screen den Entwurf
        (`clear`), die Leiste bleibt offen.
    - **Die Orte kommen mit**: die Zellendateien aller Gruppen, die das
      Orte-Manifest für den Rahmen nennt; `HostPoiSource` liest sie
      ZUERST (`readLocal`), was lokal liegt, braucht weder Manifest noch
      Netz.
    - **Die Bereiche liegen IMMER auf der Karte, zuoberst** (#82, seit
      0.36.1), mit und ohne Empfang, in beiden Engines (MapLibre: eine
      `file://`-Quelle je Bereich NACH der Online-Quelle; flutter_map:
      `MultiAreaTileProvider` als letzte Kachelschicht, ohne
      Ersatzkachel). Bis 0.36.0 waren sie nur die Karte ohne Empfang oder
      ohne Manifest — im Wald heißt das meist „ein Balken, über den nichts
      kommt": Das Telefon meldete Netz, die Online-Kacheln kamen nie, die
      gespeicherten wurden nicht gefragt, und die Leiste zeigte sie
      trotzdem als gespeichert. Das ist der lokale Vorrang aus Konzept
      3.2, ohne Kachel-Lieferanten: Jede Bereichskachel trägt die
      deckende `earth`-Fläche (Test: `area_layer_order_test.dart`) und
      verdeckt die Online-Karte darunter; wo der Bereich keine Kachel
      hat, liefert sein Archiv nichts. Doppelt gezeichnet wird nichts
      Sichtbares, nur die Online-Kachel darunter umsonst geladen. Das
      Archiv-Format war NICHT die Ursache: MapLibre 13.0 entpackt
      Verzeichnis und Kacheln nur bei gzip und liest „none" roh
      (nachgesehen im nativen Code).
    - **Der Download läuft im Main-Isolate**, auf Android unter dem
      KeepAlive-Koordinator (`dataSync`); Abbruch zwischen den Blöcken,
      geschrieben wird erst am Ende — ein Abbruch hinterlässt nichts.
    - **Bereiche werden nie verdrängt**, nur in „Meine Bereiche"
      gelöscht; ein neuerer Kartenstand wird dort angeboten (Knopf,
      derselbe Rahmen unter derselben Id), nicht aufgezwungen und nicht
      an „freies Netz" gebunden — wer tippt, entscheidet.
    - **„Gesehenes bleibt liegen" (Konzept 3.2) gibt es noch nicht**:
      kein Kachel-Zwischenspeicher der Online-Karte. Ein eigener Schritt.
    Der Einstieg ist seit 0.75.0 der eigene Knopf „Offline-Karten"
    (#190; bis dahin der Ebenen-Knopf, weil die Spalte auf einem kleinen
    Telefon quer überlief — der Platz kam mit der Glühbirne frei, die
    nach oben rechts zog, und die Spalte skaliert seit 0.72.0 ohnehin). Der Harness
    hängt `MemoryAreaStore` und `FakeKeepAlive` ein; die Test-Karte
    fordert nach `move`/`fit` einen Frame an (sonst kam der Stillstand
    erst beim nächsten zufälligen Neuzeichnen, und ein Test prüfte den
    alten Ausschnitt). `test/flows/offline_areas_flow_test.dart` fährt
    Leiste, Download, Liste, Löschen und Aktualisieren gegen ein
    Quellarchiv aus dem
    eigenen Schreiber.
- **Höhenkacheln je Bereich** (Routing Schritt 2, seit 0.69.0,
  `docs/konzept-routing.md` 2.6; `tool/height_tiles.py`,
  `height-data.yml`, `lib/features/offline_areas/height_tiles.dart`):
  je z13-Kachel ein 49 × 49-Raster in ganzen Metern aus dem Copernicus-
  DEM GLO-90, als EIN PMTiles-Archiv `heights-<build>.pmtiles` mit
  Manifest `heights.json` auf dem Kartenhost; ein Bereich holt seine
  Kacheln beim Speichern über denselben Range-Weg und legt sie als
  ZWEITES Archiv neben sich (`AreaStore.putHeights`,
  `StoredArea.heightTiles`). Sechs Dinge, die man wissen muss:
  - **Nicht 1 Byte je Zelle**, wie die Schätzung im Konzept sagte: Das
    hielte in einer Alpenkachel nur 8-m-Stufen — die Treppen, an denen
    das Hex-Gitter in M3 gescheitert ist (42 % statt 5 % Medianfehler).
    int16, Delta, gzip: gemessen 2,4 KB je Kachel in den Alpen, 1,4 KB
    im Flachland; ganz DACH 140 MiB auf dem Host (95 494 Kacheln,
    `heights-20261001.pmtiles`, gemessen beim ersten `publish`).
  - **Format und Konstanten stehen ZWEIMAL** — `FORMAT/GRID/ZOOM/NODATA`
    im Werkzeug, `kHeightsFormat/kHeightGrid/kHeightTileZoom/kHeightNoData`
    in Dart. `test/release_workflow_test.dart` hält sie zusammen, und
    beide Seiten kodieren dasselbe Fixture-Raster zu denselben Bytes
    (erste acht Bytes und FNV-1a als Konstante in Self-Test und
    `height_tiles_test.dart`). Ein fremdes Format im Manifest heißt
    „keine Höhen", nie „irgendwie lesen".
  - **Das Paket entpackt die Kachel, nicht der Leser**: Die Kompression
    steht im Archiv-Header (gzip), `Tile.bytes()` liefert die
    Delta-Bytes. `HeightTile.decode` nimmt GENAU 4 802 Bytes — ein
    zweites gunzip war der erste Fehler beim Bau, drei Tests rot.
  - **Ränder sind geteilt**: Probe i/48 mit BEIDEN Rändern, die
    Ostzeile einer Kachel ist die Westzeile der nächsten; ein Punkt
    genau auf der Kante gehört rechnerisch der östlichen/südlichen
    Kachel, und fehlt die, liest `HeightReader.heightAt` die andere an
    ihrem Rand (dieselbe Zahl). Ohne diese Regel war der Trailkopf am
    Ostrand eines Bereichs „ohne Höhe".
  - **numpy nur im Bau**: 98 640 Kacheln × 2 401 Proben sind 237 Mio.
    bilineare Ablesungen, und der Float-Prädiktor der COG-Kacheln in
    einer Byteschleife dauerte Stunden. Der Self-Test läuft in ci.yml
    ohne numpy (stdlib, wie jedes Werkzeug), `height-data.yml` fährt
    ihn MIT numpy vor dem Bau — dort wird geprüft, dass beide Pfade
    dieselben Zahlen liefern. In der letzten Pixelreihe einer 1°-Zelle
    hält die Abtastung den letzten Pixel, statt in die Nachbarzelle zu
    greifen: ein DEM-Pixel Unschärfe je Zellgrenze, in beiden Pfaden
    gleich, dokumentiert.
  - **Anstieg/Abstieg alle 50 m mit 10 m Hysterese** (`climbAlong`,
    Spiegel von `climb_along` im Messwerkzeug, Testvektoren geteilt),
    nicht die 3 m der aufgezeichneten Höhen. Null, sobald eine Probe
    keine Höhe hat — ein halber Anstieg wäre eine erfundene Zahl.
  **Seit 0.79.0 auch für Trails ohne Höhen** (#186,
  `lib/features/trails/terrain_heights.dart`; Betreiber: „gezeigt, nie
  gespeichert"). Vier Dinge, die man wissen muss:
  - **Eine Naht, drei Abnehmer** (`TerrainHeights`): Bereiche zuerst,
    mit Empfang der Host über `OnlineHeights` (dieselbe Klasse wie die
    Planung, ohne deren „nur nachgeladene Kacheln"). Das Blatt
    (`terrainProfileProvider`, nur beobachtet, wenn der Trail keine
    Höhen hat), der Export und der Import lesen hier.
  - **Das Profil rechnet wie gemessen**: Proben alle 50 m, 10 m
    Hysterese (`ElevationProfile.terrain`, `hysteresisClimb`), kein
    steilstes Stück. Die Kachel trägt „≈", das Profil
    `kTerrainLabel`. Liste, Sortierung und Planer lesen weiter nur
    aufgezeichnete Höhen — dort hieße es Netz je Zeile.
  - **Markiert hinaus, nie zurück herein**: Der Export schreibt
    `<extensions><tb:elevationSource>terrain` (Namensraum
    `urn:trailbuddy:gpx:1`, keine Adresse), `parseGpx` liest die Höhen
    einer so markierten Spur gar nicht erst. Sonst schriebe ein
    Re-Import der eigenen Datei Modellhöhen als gemessene
    (`attach_elevation`, Beisteuern). Rundlauf-Test in
    `terrain_heights_test.dart` mit Gegenprobe.
  - **Der Import vergleicht** (`compareToTerrain`): Versatz (Median)
    über `kTerrainOffsetMaxM` (50 m) oder Streuung (95. Perzentil)
    über `kTerrainSpreadMaxM` (80 m) ⇒ „Höhen der Datei verwerfen,
    Geländemodell anzeigen", vorgewählt; dann geht `uploadTrack` ohne
    Höhen hinauf, ein Nachtragen entfällt, und die Einordnung
    Trail/Fahrt rechnet ohne Höhen. GESETZT, nicht gemessen — der
    Feldtest (#188) prüft sie. Beisteuern wartet auf laufende
    Vergleiche (Flow-Test mit Gegenprobe).
  Entfernen von Kacheln (Radierer) schreibt das Höhenarchiv genauso neu
  wie das Kartenarchiv (`AreaTrimmer._rewriteHeights`); bleibt keine,
  fällt nur das Höhenarchiv weg. Der Harness setzt beide Höhen-Loader
  auf null — der Dialog sagt dann „ohne Höhen", und der Flow-Test
  erwartet genau das. Sichtbar wird von den Höhen noch nichts, deshalb
  kein Eintrag in „Entdecken"; der kommt mit dem Planer (Schritt 3–5).
