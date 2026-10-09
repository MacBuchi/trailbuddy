# Offline-Karten: Bereiche statt Regionen

**Stand:** 2026-09-28 · **Issue:** #31 · **Entscheidungen offen:** siehe
Abschnitt 7. Ergänzt `docs/konzept-trails.md` (Abschnitt 8, „Offline-Karten
… komplett übernommen") um das, was PilzBuddy NICHT hat: dieselbe Karte
ohne Empfang im Browser wie auf Android.

## 1. Ausgangslage

- Die Karte lädt heute OSM-Rasterkacheln von `tile.openstreetmap.org`.
  Deren Nutzungsbedingungen verbieten Massendownload und Vorladen — ein
  Offline-Weg kann darauf nicht aufsetzen, auf keiner Plattform.
- PilzBuddys Offline-Karten sind Regionskarten (PMTiles je Bundesland,
  44 MB bis 2 GB) aus den Releases von `whitespring/project-nomad-maps-europe`,
  nur Android. Der Browser bekommt sie nicht: Release-Anhänge tragen
  keinen `access-control-allow-origin`-Header (PilzBuddy #365/#496).
- Gemessen in PilzBuddy (#496, 2026-09-22, `tool/map_tiles.py plan`
  gegen den täglichen Protomaps-Build): DACH als EIN PMTiles-Archiv ist
  bei Zoom 8 30,5 MB, bei Zoom 12 1,39 GB, bei Zoom 13 2,87 GB, bei
  Zoom 14 5,54 GB. `raw.githubusercontent.com` beantwortet Range-Anfragen
  mit CORS, nimmt aber keine Datei über 100 MB.
- Die Wege-Ebene der Protomaps-Kacheln trägt Forstwege
  (`kind == "path"`, `kind_detail == "track"`) ab Zoom 12 und Pfade,
  Fußwege, Radwege ab Zoom 13 (PilzBuddy `tool/transform_map_style.py`).
  Das Zerlege-Blatt (#29) braucht genau diese Ebene, um Singletrail von
  Forstweg zu unterscheiden — offline, weil die Fahrt im Wald endet.

## 2. Ziel

Ein Mechanismus für beide Plattformen: Der Nutzer wählt einen
**Bereich** auf der Karte („diesen Ausschnitt", „um meine Trails herum"),
die App holt die Kacheln dieses Bereichs bis Zoom 14 und legt sie lokal
ab. Ohne Empfang zeichnet die Karte aus dem Bereich; was nicht gespeichert
ist, bleibt die mitgelieferte DACH-Übersicht (Zoom 0–7). Orte (#12)
sind im Bereich mit dabei. Keine Regionen mit 900 MB, keine
Bundesland-Liste: Der Kartenausschnitt ist der Gebietswähler.

## 3. Bausteine

### 3.1 Eine Vektorquelle, für alle

Ein PMTiles-Archiv von DACH (Protomaps-Basiskarte, Zoom 0–14, ODbL,
Namensnennung wie bei PilzBuddy) auf einem Host, der **Range-Anfragen
und CORS** kann. Geschnitten in CI mit dem offiziellen `pmtiles extract`
aus dem täglichen Protomaps-Build, mit Datum im Manifest — nie mit einem
eigenen Schreiber, ein leicht kaputtes Archiv scheitert im Browser, nicht
in CI. Online liest die App kachelweise per Range direkt daraus
(`PmTilesArchive.fromUri`), ohne je das Ganze zu laden; die
OSM-Rasterkacheln entfallen damit auch online. Ein Netzhost weniger
(OSM), einer dazu (siehe 7).

### 3.2 Bereiche

- **Wahl**: der aktuelle Ausschnitt, oder die Kacheln entlang der
  eigenen Trails (seit 0.24.0: 1 km beiderseits, keine Kachel für das
  Land dazwischen — das Rechteck um alle Trails lief beim Betreiber
  auf 40 779 Kacheln, die Obergrenze sind 40 000). Die App zählt die
  Kacheln von Zoom 8 bis zum Zoom des Hosts auf, die die Form berühren;
  ein Archiv braucht kein Rechteck, sein Rahmen im Header ist die Hülle.
- **Sehen, was liegt** (seit 0.25.0, Stufe B; seit 0.27.0 als Leiste):
  Der Knopf „Offline-Karten" (bis 0.74.x der Ebenen-Knopf, #190) öffnet links eine schmale Werkzeugleiste und dunkelt
  die Karte ab, solange sie offen ist — hell bleibt, was gespeichert
  ist, IMMER in den Kacheln des Bereichs (Zoom 13), unabhängig vom
  Kamera-Zoom; zusammenhängende Kacheln als Rechtecke. Die Karte bleibt
  dabei bedienbar.
- **Zeichnen** (seit 0.26.0, Stufe C, #67): In derselben Leiste
  entsteht ein Entwurf: der aktuelle Ausschnitt, Fingerstriche (jeder
  eine geschlossene Fläche; jede Kachel, die sie berührt oder
  umschließt, kommt dazu oder fällt weg) und die Kacheln entlang der
  eigenen Trails. Seit 0.27.0 bearbeitet die Leiste den ganzen Bestand:
  Der Radierer über gespeicherten Kacheln markiert sie zum Entfernen.
  Hell ist gespeichert, grün schraffiert kommt dazu, rot gespiegelt
  schraffiert fällt weg (Betreiber, 2026-09-29). Speichern fragt nach und
  nennt, was geladen wird (Größe, Kacheln, Orte) und was frei wird;
  Entfernen schreibt die betroffenen Archive auf dem Gerät neu, ohne
  Netz. Schließen fragt nach, wenn der Entwurf nicht leer ist.
- **Größe vorher, exakt**: Das PMTiles-Verzeichnis nennt die Bytezahl
  jeder Kachel. „Diesen Bereich speichern — 12,4 MB" ist eine Messung,
  keine Schätzung. Faustzahl aus den PilzBuddy-Werten: 5,54 GB auf
  rund 700 000 km² sind im Mittel 8 KB je km² — ein Gebiet von 30 × 30 km
  etwa 7 MB, von 100 × 100 km etwa 80 MB; Städte liegen darüber,
  Bergwald darunter.
- **Holen**: Die Kacheln liegen im Archiv nach Hilbert-Kurve
  geclustert, ein Rechteck zerfällt in wenige zusammenhängende
  Byte-Bereiche — wenige große Range-Anfragen statt tausender kleiner.
  Auf Android mit dem Vordergrunddienst (`dataSync`), der dann mit der
  Fahrt den Koordinator aus PilzBuddy braucht; im Browser im Tab, mit
  Fortschritt und Abbruch.
- **Ablegen**: IndexedDB im Browser (Kachel-Schlüssel `z/x/y`, als
  Bytes), Dateien auf Android; ein `TileStore` mit derselben
  Schnittstelle. Der Kachel-Lieferant der Karte schaut erst lokal, dann
  ins Netz. Bereiche sind Absicht und werden **nicht verdrängt**, nur auf
  Wunsch gelöscht (Liste „Meine Bereiche" mit Größe und Stand).
- **Gesehenes bleibt liegen**: Zusätzlich bleibt jede online geholte
  Kachel liegen, mit Obergrenze und Verdrängung der
  ältesten — wer eine Gegend am Vorabend angesehen hat, hat sie im Wald.
  **Auf Android seit 0.99.0 (#155), anders als hier zuerst gedacht:**
  nicht im `TileStore` der Bereiche, sondern im Ambient Cache von
  MapLibre Native (`mbgl-offline.db`, vom Backup ausgenommen). Erst
  13.3 legt dort auch PMTiles-Bereiche ab (maplibre-native #4290); das
  Plugin 0.3.5 zieht 13.0, deshalb erzwingt Gradle 13.5.3 (geprüft: die
  Bindungen des Plugins finden dort jede Methode wieder). Ohne Empfang
  nennt der Stil die Archive aus dem zuletzt GEMERKTEN Manifest, über
  der Übersicht; MapLibre liefert die Kachel aus dem Cache, auch
  abgelaufen, und wo keine liegt, scheint die Übersicht durch. Die
  Obergrenze ist gemessen, nicht geraten (2026-10-08,
  `tool/map_tiles.py plan` gegen `dach-20261001.pmtiles`): 20 × 20 km
  über Zoom 8–13 kosten 2,9–4,1 MB, ein Tag mit viel Schieben über
  50 × 50 km grob 20–25 MB; 100 MB (Betreiber) tragen gut zwanzig
  solche Tage. **Im Browser seit 0.101.0** mit eigenem Kachelspeicher
  in IndexedDB (`seen_tiles.dart`): komprimiert wie im Archiv, Schlüssel
  `<archiv>/z/x/y`, dieselben 100 MB, die am längsten nicht gebrauchte
  Kachel zuerst. Weil Archive mit Datum unveränderlich sind, fragt der
  Lieferant ZUERST den Speicher, auch mit Netz — das spart je Kachel
  eine Range-Anfrage (#55); ohne frisches Manifest nimmt die Karte das
  gemerkte und zeigt, was liegt, über der Übersicht.
- **Der Browser darf räumen**: `navigator.storage.persist()` beim ersten
  Speichern eines Bereichs erfragen (Muster Ausgangskorb in PilzBuddy),
  nicht beim Start; Safari räumt nach sieben Tagen ohne Nutzung. Die
  Karte sagt, wenn ein Bereich fehlt, statt still grob zu werden.
- **Aktualität**: Ein Bereich trägt das Datum seines Archivs. Ein
  neuerer Schnitt wird angeboten, nicht aufgezwungen; nur im freien Netz
  (PilzBuddy #332: `isActiveNetworkMetered`, nicht „WLAN").
- **Höhen kommen mit** (seit 0.69.0, `docs/konzept-routing.md` 2.6):
  Für jede z13-Kachel des Bereichs eine Höhenkachel aus dem Archiv
  `heights-<build>.pmtiles` auf demselben Host (Copernicus DEM GLO-90,
  49 × 49 Proben in Metern), als zweites Archiv neben dem Bereich — ein
  bis zwei Prozent der Kartengröße. Gebraucht werden sie von der
  Routenplanung; ein Bereich ohne (vor 0.69.0, oder ohne Höhen-Manifest)
  ist weiter eine Karte, und „Aktualisieren" holt sie nach.

### 3.3 Engine und Übersicht

Wie in PilzBuddy: MapLibre hinter der Kartenfassade auf Android,
flutter_map mit Vektor-Renderer (`vector_map_tiles`) im Browser; der
Vorzeichenwechsel bei `alignment` (PilzBuddy #409) und der
`FiniteCameraConstraint` an jeder `MapOptions` kommen mit. Der Kartenstil
ist erzeugt (`transform_map_style.py`, Wächter `generated_assets.py`);
die Wege-Hervorhebung (`emphasize_paths`) ist hier keine Kosmetik —
Trails SIND die Wege. Die DACH-Übersicht (Zoom 0–7, rund 9 MB) liegt
als Asset im Binary und ist die unterste Ebene, sobald die Karte offline
ist oder ein Bereich aktiv ist — nie unter Onlinekacheln (PilzBuddy
#137).

### 3.4 Orte offline

Zwei Wege, die Reihenfolge ist eine **Messung**:

1. **Aus den Kacheln.** Die Protomaps-Ebene `pois` trägt `kind`-Werte;
   der erzeugte Stil kennt darunter `toilets`, `drinking_water`,
   `restaurant`, `cafe`, `bar`, `bench`, `peak`, `attraction`. Ob
   `alpine_hut`, `shelter`, `viewpoint`, `spring`, `pub`, `biergarten`,
   Radläden, Reparaturstationen, Ladesäulen und Parkplätze als eigene
   `kind`-Werte in den Kacheln stecken (und ab welchem Zoom), ist aus
   dem Stil nicht ablesbar — der Stil zeichnet eine Auswahl. Gemessen
   wird an einer echten Zoom-14-Kachel eines Testgebiets: `pmtiles tile`
   dekodieren, `kind`-Werte je Ebene zählen, gegen unsere 16 Arten
   halten. Deckt die Ebene die Arten ab, kommen die Orte mit dem Bereich
   mit, und Overpass ist für gespeicherte Bereiche überflüssig.
2. **Overpass je Zelle, gespeichert.** Fehlt Wesentliches (Quellen und
   Hütten sind die Kandidaten), bleiben die Overpass-Antworten je
   Rasterzelle und Gruppe mit Ablaufdatum (30 Tage) auf dem Gerät. Beim
   Speichern eines Bereichs werden seine Zellen für die eingeschalteten
   Gruppen mitgeholt — mit Deckel je Bereich (etwa 20 Zellen) und
   Pause zwischen den Anfragen; Overpass ist ein Freiwilligendienst
   (FOSSGIS), und ein Bereich von 100 × 100 km wäre sonst 80 Anfragen
   je Gruppe.

Beides gilt für Browser und Android gleich; die Zellen-Kopie hätte
dieselbe `TileStore`-Nachbarschaft in IndexedDB bzw. als Datei.

**Gemessen am 2026-09-28, und die Antwort ist keiner von beiden.** Weg 1
scheitert an der Quelle, nicht am Stil: Protomaps schreibt Hütte,
Gasthaus, Biergarten, Café, Trinkwasser, Wasserstelle, Unterstand,
Aussichtspunkt, Reparaturstation, Radladen, Toilette und Parkplatz erst
ab **Zoom 15** in die Kacheln (Punkte ohne Namen ab 16; nur Quellen ab
15 und Gipfel ab 13 liegen tiefer — nachgelesen in der
`Pois`-Ebene des Basemap-Profils). Unser Archiv endet bei 13, und bei
14 wäre es nicht anders. Selbst mit Zoom 15 zeigte der Stil sie erst ab
16 (`min_zoom + 1` in der Kachel) und nur als Text, ohne Sprites. Weg 2
hätte Overpass zur Dauerquelle gemacht, mit Kopien je Gerät.

**Weg 3, entschieden (Abschnitt 7): eine eigene Orte-Datei auf dem
Kartenhost.** `poi-data.yml` liest monatlich die Geofabrik-Extrakte
aller Länder im Kartenrahmen mit `osmium` (bis #73 nur DACH +
Liechtenstein, die Karte reichte aber bis Südtirol und ins Elsass),
`tool/poi_extract.py` behält die 15 Arten aus `tool/pois/kinds.json`
innerhalb desselben Rahmens wie Onlinekarte und Übersicht
(5,5–17,5° O, 45,5–55,5° N) und schreibt je Rasterzelle (das
Raster der App, 0,1° × 0,15°) und Gruppe eine kleine JSON-Datei nach
`tiles.mcbuchi.de/trailbuddy/pois-<build>/`, dazu `pois.json` mit dem
Bau und den Zellen, die Inhalt haben. Die App (seit 0.18.0) holt das
Manifest einmal je Lauf und dann nur die Dateien der berührten Zellen
für die eingeschalteten Gruppen. Was das bringt: kein fremder
Live-Dienst mehr, die Rasterzelle statt des genauen Ausschnitts als
einzige Information, die den Host erreicht, Edge-Cache für die kleinen
Dateien, und für Schritt 3 sind die Orte eines Bereichs schlicht die
Dateien seiner Zellen — dieselbe Ablage wie die Kacheln. Nadeln, Filter
und Blatt bleiben, wie sie sind.

### 3.5 Die Wege-Ebene für das Zerlege-Blatt

Das Zerlege-Blatt (#29, **seit 0.20.0**) liest aus den gespeicherten Kacheln die Ebene
`roads` (`kind == "path"` mit `kind_detail`, dazu `service`, `minor`) und
misst je Fahrtabschnitt den Abstand zur nächsten Straße oder zum
nächsten Forstweg. Das setzt voraus, dass der Bereich der Fahrt bis
Zoom 13 vorliegt — Zoom 14 als Ziel deckt das. Ohne gespeicherten Bereich
sagt das Blatt, dass es die Wege nicht kennt, und bietet nur an, was
ohne sie geht.

## 4. Was es kostet

| | Browser | Android |
|---|---|---|
| Speicher je Bereich | wenige bis einige Dutzend MB in IndexedDB | dasselbe als Dateien |
| Übersicht im Binary | ~9 MB im Web-Build (wie PilzBuddy: im Web über `fromBytes`) | ~9 MB im APK |
| Netz online | Range-Anfragen an den Vektor-Host statt OSM-Raster | dasselbe |
| Netz für den Bereich | einmalig, Größe vorher angezeigt | dasselbe, Vordergrunddienst |
| Höhen je Bereich | ~2,4 KB je z13-Kachel in den Alpen, ~1,4 KB im Flachland (gemessen 2026-10-01) | dasselbe |

Was die Karte über DACH hinaus kostet (Kanada, Europa, Welt bis z13;
Bucket, Runner, Bauzeit), steht gemessen in `docs/karte-welt-messung.md`
(#220, 18b in #156). Wie sie dorthin kommt — Regionen per
Konfiguration, Kanada südlich 55° N als erste, alles im
Free-Kontingent von R2 —, steht in `docs/konzept-regionen.md` (18c).

## 5. Was NICHT kommt

- Keine Bundesland-Regionen (PilzBuddys Katalog). Ein Mechanismus für
  beide Plattformen ist mehr wert als zwei Gebietsbegriffe.
- Kein eigener Kachel-Server, keine Serverlogik. Der Host liefert Bytes
  auf Range-Anfragen, mehr nicht.
- Keine OSM-Raster offline, auf keiner Plattform.

## 6. Reihenfolge

1. **Fassade und Engine** (aus #31, **seit 0.16.0**): `map_view/`,
   MapLibre auf Android, Vektor-Renderer im Web, erzeugter Stil mit
   Wege-Hervorhebung, Wächter für erzeugte Assets, DACH-Übersicht als
   unterste Ebene. Online noch gegen die bisherige Rasterquelle, offline
   die Übersicht.
2. **Host und Schnitt** (**seit 0.17.0**): `map-data.yml` schneidet
   DACH Zoom 0–13 aus dem täglichen Protomaps-Build, prüft den Auszug
   gegen die Quelle, lädt ihn nach Cloudflare R2
   (`tiles.mcbuchi.de/trailbuddy/dach-<build>.pmtiles`, Zeiger in
   `dach.json`) und liest die ÖFFENTLICHE Kopie wie die App zurück (206,
   `accept-ranges`, CORS, Stichprobe gegen die Quelle). Beide Engines
   lesen daraus; OSM ist aus der Datenschutzerklärung, Cloudflare drin.
   Monatlicher Lauf. Zoomziel 13 (Entscheidung, Abschnitt 7). Erster
   veröffentlichter Stand am 2026-09-28, siehe Abschnitt 7.
3. **Bereiche speichern** (**seit 0.19.0**): je Bereich ein
   PMTiles-Archiv aus dem eigenen Schreiber, Ablage als Datei bzw. in
   IndexedDB, Auswahl (Ausschnitt oder um die Trails), Größe vorher aus
   dem Verzeichnis, Fortschritt und Abbruch, Orte-Zellen mit dabei,
   Liste „Meine Bereiche" mit Aktualisieren und Löschen. „Gesehenes
   bleibt liegen" seit 0.99.0 (Android) und 0.101.0 (Browser). Noch
   offen aus 3.2: der Hinweis bei geräumtem Browser-Speicher
   (Abschnitt 7).
4. **Orte vom eigenen Host** (**seit 0.18.0**, Messung und Entscheidung
   in 3.4): `poi-data.yml`, `tool/poi_extract.py`, Manifest `pois.json`.
   Offline werden sie mit Schritt 3: die Dateien der Zellen eines
   Bereichs kommen mit dem Bereich mit.
5. **#29 mit der Wege-Ebene** (**seit 0.20.0**): `road_index.dart`
   liest die z13-Kacheln der Fahrt aus den Bereichen; jede Kachel muss
   in einem liegen, sonst gelten die Wege als unbekannt.

Jeder Schritt ein PR, jeder mit Datenschutzerklärung und CLAUDE.md im
selben PR, wo sich ein Netzziel oder eine Datenkategorie ändert.

## 7. Entscheidungen des Betreibers

**Entschieden am 2026-09-28:** Host ist **Cloudflare R2** (Bucket
`buddy-tiles`, mit Platz für PilzBuddy unter eigenem Präfix) hinter der
eigenen Domain `tiles.mcbuchi.de`; **Zoomziel 13** (Forstwege ab z12,
Pfade, Steige, Fußwege ab z13 in den Kacheln — PilzBuddy-Messung; der
erzeugte Stil zeichnet ab z14 nur noch kleine Bäche; 2,9 statt 5,5 GB;
der Schnitt lässt sich in CI jederzeit auf 14 wiederholen). Gemessen am
2026-09-28 an einer Zoom-13-Kachel des Protomaps-Tagesbaus im Gebiet der
Isartrails: `roads` trägt `path` mit `kind_detail` track, footway, path
und bridleway, dazu `pois` mit peak, protected_area, water und
`water` mit stream — die Wege sind bei 13 vollständig da; ob 14 mehr
Orte-Arten trägt, ist damit nicht entschieden (die 14er-Kachel deckt nur
ein Viertel der Fläche) und bleibt die Messung aus 3.4. Der Bucket hat
EU-Jurisdiktion (Standort WEUR); sein S3-Endpunkt trägt deshalb `.eu.`
Offen bleibt das iPhone im Browser. Die drei Ausgänge unten bleiben als Begründung
stehen.

**Erster Stand veröffentlicht am 2026-09-28** (dritter Lauf von
`map-data.yml`): `dach-20260928.pmtiles`, 2,8 GB, Zoom 0–13 aus dem
Protomaps-Tagesbau 20260928; 80 Kacheln des Auszugs und 40 der
öffentlichen Kopie byte-gleich mit der Quelle, 206 mit `accept-ranges`
und CORS-Header wie die App sie braucht. Die beiden Läufe davor haben
je einen Fehler gezeigt, der jetzt im Workflow benannt ist (#53 eine
Variable, die den eigenen Schritt nicht erreichte; #54 die
Bot-Challenge unten).

**Orte vom eigenen Host statt aus den Kacheln oder von Overpass**
(Betreiber, 2026-09-28: „Weg 3 finde ich auch am besten"): Die Messung
in 3.4 hat ergeben, dass die Kacheln die Orte erst ab Zoom 15 tragen;
ein Archiv bis 15 hätte jeden gespeicherten Bereich vervielfacht. Der
Betreiber hatte auf dem Pixel 7 Pro die Onlinekarte gutgeheißen und
Orte vermisst — ab Werk ist nur „Wasser" eingeschaltet, und die kamen
bis dahin live von Overpass.

**Schritt 3, gebaut am 2026-09-28 — drei Abweichungen von 3.2:**
(1) Die Ablage ist je Bereich EIN Archiv im PMTiles-Format, kein
Kachelspeicher je z/x/y: MapLibre liest `pmtiles://file://…` nativ,
der Canvas-Renderer dasselbe Archiv über den vorhandenen Adapter — ein
Format, kein zweiter Weg; der Schreiber auf dem Gerät ist die Ausnahme
von „nie mit einem eigenen Schreiber", weil dort kein `pmtiles extract`
läuft und jedes Archiv sofort zurückgelesen wird. (2) Die Bereiche sind
die Karte, sobald kein Empfang besteht oder es kein Manifest gibt —
nicht „erst lokal, dann Netz": MapLibre hat keinen Kachel-Lieferanten
für einen lokalen Vorrang, zwei Quellen mit demselben Inhalt zeichneten
doppelt; beide Engines eine Regel. **Korrigiert in 0.36.1 (#82):** Im
Wald heißt „kein Empfang" meist „ein Balken, über den nichts kommt" —
die Regel griff dort nicht, und gespeicherte Bereiche blieben leer.
Seither liegen sie immer zuoberst, und das IST der lokale Vorrang: Jede
Bereichskachel deckt mit ihrer `earth`-Fläche die Online-Karte darunter
zu, wo keine liegt, scheint diese durch. Sichtbar doppelt wird nichts. (3) Ein neuerer Kartenstand wird in
„Meine Bereiche" angeboten, unabhängig davon, ob das Netz frei ist —
wer tippt, entscheidet; `isActiveNetworkMetered` bräuchte einen
eigenen Plattform-Kanal. „Gesehenes bleibt liegen" gibt es seit 0.99.0
auf Android (MapLibres Ambient Cache) und seit 0.101.0 im Browser
(eigener Speicher in IndexedDB, #155, siehe 3.2). Noch nicht gebaut:
`navigator.storage.persist()`.

**Bot Fight Mode ist für die Zone `mcbuchi.de` AUS** (Betreiber,
2026-09-28, Issue #55). Cloudflares Free-Plan kennt den Schalter nur
zonenweit, ohne Ausnahme je Hostname, und er stellte dem CI-Runner
eine Managed Challenge (`403`, `cf-mitigated: challenge`, Ray-ID
`a423bd14c8a51492`) — die kann kein Client der App lösen, weder
`curl` noch MapLibre noch `PmTilesArchive.fromUri`. Der Schutz gegen
DDoS ist davon unberührt (eigener, immer aktiver Dienst). Was bleibt,
ist ein KOSTENrisiko, kein Sicherheitsrisiko: Das 2,8-GB-Archiv liegt
über der 512-MB-Grenze des Edge-Caches im Free-Plan, jede Range-Anfrage
geht also als Class-B-Operation an R2 (10 Mio. je Monat frei, danach
0,36 $ je Mio.; Egress bleibt frei). Dagegen stehen die drei Punkte in
#55: eine Rate-Limiting-Regel für `tiles.mcbuchi.de` mit GEMESSENER
Schwelle (nicht geraten — ein Kartenschwenk sind Dutzende Anfragen),
eine Nutzungsbenachrichtigung im Cloudflare-Konto, und dieser Absatz.
Wer den Schalter wieder umlegt, macht die Karte für alle aus, ohne
dass CI es vor dem nächsten Monatslauf sieht.

**Was im Bucket liegt, sagt `r2-inventory.yml`** (#230, seit dem
2026-10-08; monatlich am 4., nach den Datenläufen vom 1. bis 3., und
von Hand). Vier Workflows schreiben je einen datierten Stand plus
Manifest und räumen „alles außer den zwei neuesten" ab — nachgesehen
hat das niemand. Ein Lauf, der nach dem Hochladen und vor dem Manifest
abbricht, hinterlässt einen Stand, den keiner nennt, und dann sind „die
zwei neuesten" nicht mehr „der aktuelle und der davor".
`tool/r2_inventory.py` liest die Auflistung des ganzen Buckets und die
vier Manifeste AUS DEM BUCKET (nicht über den Edge-Cache) und schreibt
in die Run-Summary: je Familie die Stände mit Zustand (aktuell / davor /
veraltet / verwaist), was im Präfix keiner Familie gehört, doppelt
Abgelegtes (gleiche Größe und ETag), unfertige Multipart-Uploads und
die Summe gegen die 10 GB freien Speicher. Fremde Präfixe (PilzBuddy)
werden gezählt, nicht bewertet. **Er liest nur** — der Selbsttest
verbietet `rm`, `sync`, `put`/`delete` und ein `s3 cp` in den Bucket
im Workflow; was weg soll, entscheidet der Betreiber aus dem Bericht.
**Rot** wird der Lauf nur, wenn ein Manifest einen Stand nennt, den der
Bucket nicht vollständig hält (Datei fehlt, Größe oder Dateizahl weicht
ab): Dann liest die App einen kaputten Stand. Zwillinge zwischen dem
aktuellen und dem vorigen Stand einer Familie sind erwartbar (das DEM
ist statisch, die meisten Ort-Zellen bleiben gleich) und gehen mit dem
älteren Stand. Die Größen je Familie sind die Ausgangszahl für die
Messung jenseits von DACH (#220).

1. **Der Host.** Drei Ausgänge, wie in PilzBuddy #496 beschrieben:
   - **Objektspeicher (Cloudflare R2)**: kein Größenlimit je Datei, CORS
     und Range einstellbar, DACH Zoom 14 in EINER Datei. Kostet ein
     Konto, ein Upload-Secret in CI und einen neuen Netzhost in der
     Datenschutzerklärung (Besucher-IP geht an Cloudflare). Die
     Komplexität liegt in CI, nicht in der App. **Empfehlung.**
   - **GitHub raw, geschnitten**: kein neuer Anbieter, aber Dateien
     ≤ 100 MB heißt bei Zoom 14 rund 57 Stücke (bei Zoom 13 etwa 30) plus
     einen Gebietsindex in der App — Komplexität genau dort, wo ohne
     Empfang gearbeitet wird —, und ein Repo mit 5,5 GB liegt über
     GitHubs empfohlener Grenze.
   - **Zoomziel senken**: löst das Problem nicht, aus dem das hier
     entsteht (Wege ab Zoom 13).
2. **Zoomziel 14** — oder 13, wenn der Host es verlangt (Wege sind ab
   13 drin, feine Details ab 14).
3. **iPhone im Browser**: zählt es? Safari räumt IndexedDB nach sieben
   Tagen ohne Nutzung; die Karte kann es sagen, nicht verhindern.
