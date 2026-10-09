# Regionen per Konfiguration

**Stand:** 2026-10-08 · **Issue:** #220 · **Fahrplan:** 18c in #156 ·
**Grundlage:** die Messung `docs/karte-welt-messung.md` (18b). Ergänzt
`docs/konzept-offline-karten.md`: Dort steht, wie die Karte ohne Empfang
funktioniert, hier, wie sie über DACH hinaus kommt. Kanada ist die erste
Region außerhalb Europas.

## 1. Was der Betreiber entschieden hat (2026-10-08)

1. **Die App wählt die Region selbst.** Jede Region ist eine eigene
   Kartenquelle mit ihren Grenzen; die Karte zeigt, was im Bild liegt,
   und ein gespeicherter Bereich lädt aus der Region, in der er liegt.
   Es gibt keinen Regionswähler und keinen neuen Gebietsbegriff in der
   Oberfläche. Das ist dieselbe Linie wie `konzept-offline-karten.md`
   §5 („ein Mechanismus für beide Plattformen ist mehr wert als zwei
   Gebietsbegriffe").
2. **Die Höhen baut CI, notfalls in Teilen.** Wiederholbar aus der
   Cloud, nicht einmalig auf dem Rechner des Betreibers.
3. **Die Übersicht kommt je Region als Download.** Die DACH-Übersicht
   bleibt im Binary. Jede andere Region bringt ihre Übersicht z0–7 mit
   dem ersten gespeicherten Bereich dort mit, und „Meine Bereiche" zeigt
   sie mit Größe und Löschen-Knopf.
4. **Alles bleibt im Free-Kontingent von R2** (10 GB-Monat Speicher).
   Das entscheidet den Zuschnitt von Kanada (Abschnitt 3).

## 2. Was eine Region ist

Eine Region ist eine Zeile in **`tool/regions.json`**, der einen Quelle
für alle Workflows:

| Feld | Bedeutung | DACH | Kanada |
|---|---|---|---|
| `id` | Kennung, Pfad auf dem Host | `dach` | `ca` |
| `name` | Anzeige in „Meine Bereiche" | DACH | Kanada |
| `bbox` | Rahmen W,S,E,N — für die App und als Zuschnitt der Begleitebenen | 5,5 / 45,5 / 17,5 / 55,5 | −133,2 / 41,6 / −52,6 / 55,0 |
| `map` | Zuschnitt der Karte: Rechteck oder Ländergrenze (Natural Earth, festgenagelt wie in `map-data.yml`) mit Breitengrad-Kappe | Rechteck | `ISO_A2_EH=CA`, südlich 55° N |
| `extracts` | Geofabrik-Auszüge für Wege und Orte | die heutige Liste (#73) | `north-america/canada` |
| `overview` | Übersicht z0–7: mitgeliefert oder vom Host | mitgeliefert | Host, ganz Kanada |
| `day` | Tag im Monat, an dem neu gebaut wird | 1. | 15. |

Drei Regeln, die daraus folgen:

- **Regionen überschneiden sich nicht.** Ein Punkt gehört höchstens zu
  einer Region; für einen Bereich zählt seine Mitte. Kommen später zwei
  Nachbarn dazu (z. B. DACH und Frankreich), wird die Grenze zwischen
  ihnen gezogen, nicht doppelt gebaut.
- **Die Werkzeuge bleiben, wie sie sind.** `map_tiles.py`,
  `height_tiles.py`, `way_archive.py`, `poi_extract.py` nehmen schon
  heute ein Rechteck oder eine Region (18b). Die Workflows lesen nur
  ihre Eingaben aus `tool/regions.json` statt aus festen `DACH_BBOX`-Zeilen;
  `test/release_workflow_test.dart` hält Datei und Workflows zusammen.
- **Ein Lauf baut eine Region.** Jeder Workflow bekommt die Eingabe
  `region` (von Hand) und einen Zeitplan je Region. So liegt nie mehr
  als eine Vorgängerdatei gleichzeitig im Bucket (Abschnitt 3), und ein
  kaputter Kanada-Lauf fasst DACH nicht an.

## 3. Was in 10 GB passt

Gemessen am 2026-10-08 aus der Cloud gegen den Protomaps-Bau `20261007`
(`tool/map_tiles.py plan --region`, Natural Earth 1:50 m, mit
`shapely` am Breitengrad gekappt):

| Kanada bis z13 | z13-Kacheln | Karte |
|---|---:|---:|
| ganz (18b) | 2,16 Mio. | 4,30 GB |
| südlich 62° N | 867 000 | 3,03 GB |
| südlich 60° N | 744 000 | 2,75 GB |
| südlich 55° N | 470 000 | **1,99 GB** |

Der Norden ist viel Fläche für wenig Karte: Nördlich von 55° N liegen
78 % der Kacheln, aber nur 58 % der Bytes. **Gewählt ist 55° N**
(Betreiber, 2026-10-08: „Nur Südkanada ist für Trails relevant"). Drin
liegen alle bekannten Trailgebiete — North Shore, Squamish, Whistler,
Kamloops, die Kootenays, Canmore und Bragg Creek, Prince George
(53,9° N), Smithers (54,8° N), dazu der besiedelte Süden von Ontario
und Québec, die Seeprovinzen und die Insel Neufundland. Draußen bleiben
die Territorien, Labrador und der Norden der Provinzen. Die Übersicht z0–7 deckt trotzdem ganz Kanada
(34 MB): Auch nördlich davon zeigt die Karte Land, Wasser, Orte und
große Straßen in groben Zügen, nur keine Bereiche und keinen Planer.
Die Kappe ist eine Zahl in `tool/regions.json`; wer später Whitehorse
will, setzt sie auf 61° N und misst den Bucket nach.

Der Bucket im Dauerzustand, je Ebene eine Datei:

| | DACH | Kanada (bis 55° N) |
|---|---:|---:|
| Karte | 2,8 GB | 2,0 GB |
| Höhen | 0,15 GB | ~0,52 GB (gemessen: 6 DEM-Zellen gebaut, 1 190 B je Kachel, 458 736 Kacheln im Polygon) |
| Wege | 0,13 GB | 0,005 GB |
| Orte | 0,17 GB | 0,02 GB |
| Übersicht | im Binary | 0,034 GB |
| **zusammen** | **3,3 GB** | **~2,6 GB** |

**Rund 5,9 GB im Dauerzustand.** Das reicht nur, wenn sich eine Regel
ändert: Heute bleibt die Vorgängerdatei einen ganzen Lauf lang liegen,
also einen Monat (`map-data.yml`, „sessions in flight keep the previous
file"). Mit Kanada wären das zwei Karten je Region und zusammen gut
11 GB.

**Neu: Die Vorgängerdatei geht nach zwei Tagen.** Eine Sitzung, die ihre
Verzeichnisse gemerkt hat, lebt Stunden, nicht Wochen; nach dem Wechsel
des Zeigers holt jede neue Sitzung das neue Manifest. `r2-prune.yml`
(täglich) löscht, was `tool/r2_inventory.py prune` aus derselben Analyse
wie das Inventar (#230) nennt: ältere Bauten sofort, den Vorgänger,
sobald der aktuelle Bau 48 h oben ist, und Waisen (hochgeladen, aber nie
im Manifest), sobald sie selbst 48 h alt sind. Eine Familie, deren
Manifest nichts nennt, was im Bucket liegt, fasst er nicht an — ohne
aktuellen Bau gibt es keinen Bezugspunkt. Gelöscht wird nach Schlüssel,
nie nach Präfix, und danach schreibt er den Index neu.

R2 rechnet Speicher als Monatsmittel ab (GB-Monat). Zwei Tage mit der
Vorgängerkarte einer Region kosten im Mittel rund 0,15–0,2 GB. Weil die
Regionen an verschiedenen Tagen bauen (Abschnitt 2), liegt nie mehr als
eine Vorgängerdatei gleichzeitig da: **Spitze ~8,7 GB für zwei Tage,
Mittel ~6,2 GB.** Das Monats-Inventar (#230) zeigt den Stand; wird es
knapp, ist die nächste Stellschraube der Breitengrad, nicht der Zoom —
z13 braucht der Planer für sein Wegenetz (#158).

**Die Höhen passen damit in einen Job.** `height_tiles.py plan` aus der
Cloud (2026-10-08, sechs Zellen in Saskatchewan gebaut): 458 736 Kacheln
in 663 DEM-Zellen, rund 520 MB, 72–127 min je nach Netz — gegen 17 min
für DACH. Die Teilung, die der Betreiber für 4,5–6 h freigegeben hat,
ist also erst nötig, wenn ein Lauf an die 5 h des Jobs kommt. Dann baut
ein Matrix-Job je Breitenstreifen ein Archiv, und das Manifest nennt die
Teile.

**Nebenbefund beim Messen:** Der DEM-Bucket antwortete für Zellen, die er
listet, gelegentlich mit 404 (N53 W108, beim nächsten Versuch 206). Das
Werkzeug merkte sich jede 404 dauerhaft als „Meer", ein Flackern wurde so
zum Loch in den Höhen. Seit 18c gleicht es eine 404 mit der Liste des
Buckets ab: nicht gelistet ist Meer, gelistet wird wiederholt, und eine
Zelle, die nie kommt, bricht den Lauf ab.

## 4. Auf dem Host

Die alten Pfade bleiben, wie sie sind: Apps bis 0.103 lesen `dach.json`,
`pois.json`, `heights.json` und `ways.json` an der Wurzel, und das tun
sie weiter. Neu dazu kommt:

```
trailbuddy/regions.json             der Index: id, name, bbox, Manifeste
trailbuddy/ca/map.json              → ca/map-<build>.pmtiles
trailbuddy/ca/heights.json          → ca/heights-<build>.pmtiles
trailbuddy/ca/ways.json             → ca/ways-<build>.pmtiles
trailbuddy/ca/pois.json             → ca/pois-<build>/…
trailbuddy/ca/overview.json         → ca/overview-<build>.pmtiles
```

DACH steht im Index mit seinen alten Pfaden. `regions.json` schreibt der
letzte Schritt jedes Laufs neu, und zwar nur mit den Regionen, deren
Kartenmanifest wirklich da ist: Eine Region, die nie veröffentlicht
wurde, gibt es für die App nicht. Kein neues Netzziel (derselbe Host),
also keine Änderung an der Datenschutzerklärung; sie nennt den Host und
nicht die Region.

Die Manifeste behalten ihre Form, und **`file` (bei den Orten `prefix`)
gilt relativ zum Ordner des Manifests**: `ca/map.json` nennt
`map-<build>.pmtiles`, nicht `ca/map-…`. Für DACH ist der Ordner die
Wurzel, die alten Manifeste ändern sich also nicht, und die
Namensprüfung der App braucht nur die neuen Namen (`map-`, `overview-`)
zuzulassen — nie einen Schrägstrich. Das Unterverzeichnis kommt aus dem
Index (`dir`).

## 5. In der App

Gebaut in 0.104.0 (Schritt 3) und 0.105.0 (Schritt 4, die Übersicht je
Region). Alles hängt an EINEM Provider, `mapRegionsProvider` in
`lib/features/map/map_regions.dart` (der Index mit derselben Frist wie
das Kartenmanifest, gemerkt in `Settings.seenRegions`). **DACH kommt
immer aus dem Binary** (`kDachRegion`, alte Pfade an der Wurzel), auch
wenn der Index es nennt; für DACH bleiben die bisherigen Provider die
Quelle. Ohne Index, also ohne Empfang, vor dem ersten Abruf, bei
kaputtem Host oder fremdem Format, gilt der gemerkte Index, sonst DACH
allein: Die App benimmt sich dann wie 0.103.

- **Der Index ist streng.** Jeder Pfad muss genau der sein, den
  `tool/regions.py` schreibt (`<id>/<ebene>.json`, Ordner `<id>/`), die
  Rahmen dürfen sich nicht schneiden. Passt eine Zeile nicht, gilt der
  ganze Index nicht — lieber eine Region zu wenig als eine halb gelesene.
- **Online-Karte:** eine Quelle je Region, jede mit ihrem `bbox` als
  `bounds` (MapLibre: `online` für DACH, `online-<id>` daneben).
  MapLibre fragt außerhalb davon nichts, und die Range-Anfragen einer
  Region beginnen erst, wenn sie im Bild ist. flutter_map hat EINE
  Kachelquelle, die je Kachel das Archiv der Region fragt, deren Rahmen
  sie schneidet (`RegionTileProvider`); mit nur einer bekannten Region
  ist es deren Archiv selbst. Index und Manifeste anderer Regionen
  warten so lange wie das DACH-Manifest (#183, `regionsPatiently`) —
  DACH wartet nie auf sie.
- **Wege, Höhen, Orte, Nachladen des Planers (#187):** je Position die
  Region, in der sie liegt. Das Raster der Orte (0,1° × 0,15°) und die
  z13-Kacheln von Wegen und Höhen sind weltweit dieselben, es ändert
  sich also nur, welches Manifest gefragt wird. Wege als eigene Quelle
  `ways-region-<id>`; Höhen über `RegionHeights` (je Kachel); die Orte
  je Zelle; der Planer nach dem Rahmen der Planung. Außerhalb aller
  Regionen fragt keine Ebene.
- **Gespeicherte Bereiche:** `StoredArea` trägt `region` (fehlt das
  Feld, gilt `dach`, alle Bereiche vor 0.104.0). Geplant, geladen und
  aktualisiert wird gegen die Manifeste DIESER Region; die Region ist
  die, deren Rahmen die Form schneidet. Außerhalb aller sagt der Dialog
  in einem Satz, für welche Regionen es Karten gibt (`OutsideRegions`).
  Ein Bereich, der über den Rand seiner Region reicht, wird nicht
  geteilt; was jenseits liegt, fehlt im Archiv, und die Größe vorher
  sagt es schon richtig, weil sie aus dem Verzeichnis kommt.
- **Übersicht je Region** (Schritt 4, seit 0.105.0,
  `lib/features/offline_areas/region_overview.dart`): Der erste Bereich
  in einer Region ohne mitgelieferte Übersicht lädt sie dazu, ebenso
  einer, wenn der Host einen neueren Bau nennt (Größe im Dialog). Sie
  kommt als GANZE Datei (ein Abruf statt tausender Range-Anfragen) und
  wird erst abgelegt, wenn Länge, `sha256` und Archiv-Header zum
  Manifest passen; passt sie nicht, kommt der Bereich ohne sie. Sie
  liegt neben den Bereichen (`overview-<id>.pmtiles`, also in denselben
  Backup-Ausschlüssen), mit eigenem kleinen Index, weil sie keinem
  Bereich gehört. „Meine Bereiche" zeigt sie als eigene Zeile mit
  Löschen und — fehlt sie oder ist sie älter — einem Knopf, der NUR sie
  holt. Gelöscht wird sie mit dem letzten Bereich der Region (auch über
  den Radierer) oder von Hand. Auf der Karte liegt sie über der
  DACH-Übersicht und unter allem anderen, nach derselben Regel wie
  diese: solange es kein frisches Kartenmanifest DIESER Region gibt
  (MapLibre `overview-<id>`, flutter_map eine eigene Schicht ohne
  `background`).
- **Gesehenes bleibt liegen (#155):** Die Schlüssel tragen den
  Archivnamen samt Ordner der Region — der Browser-Speicher und MapLibres
  Ambient Cache unterscheiden die Regionen also von selbst. Gemerkt wird
  das Manifest je Region (`Settings.seenRegionManifests`, für DACH
  weiter `seenMapManifest`/`seenWaysManifest`).

Was sich NICHT ändert: Trails, Fahrten, Abgleich und Buddys kennen keine
Regionen. Ein Trail in Kanada ist ein Trail wie jeder andere; ohne
Kartenregion dort hätte er bisher nur keine Karte unter sich gehabt.

## 6. Reihenfolge

1. **Dieses Konzept** (docs, kein Bump).
2. **`tool/regions.json` und die Workflows** (`.github/`, `tool/`, kein
   Bump): Eingabe `region` und ein zweiter Zeitplan je Workflow (Kanada
   am 15. bis 17.), Kanada mit Polygon und Kappe (`map_tiles.py check
   --region` prüft den Schnitt nur INNERHALB des Polygons, wo jeder
   ehrliche Schnitt gleich ist; `height_tiles.py --region`), Übersicht
   im selben Lauf wie die Karte, `regions.json` auf dem Host,
   `r2-prune.yml`. DACH baut danach byte-gleich weiter (gleiche Pfade,
   gleiche Box; `tool/regions.py --self-test` hält Datei und Workflows
   zusammen). Danach veröffentlicht der Betreiber Kanada (`publish`, die
   R2-Secrets hat nur CI); die Höhen von Hand, wie für DACH. Das
   DACH-Manifest trägt danach zusätzlich `region`, das ältere Apps
   überlesen.
3. **Die App liest Regionen** (feat ⇒ MINOR, 0.104.0): Index, Quellen je
   Region, Begleitebenen je Position, `StoredArea.region`. Tests mit zwei
   Regionen (`test/map/map_regions_test.dart`); mit nur DACH im Index
   dasselbe Bild wie 0.103 — der Harness hat keinen Index, und jeder
   Bestandstest lief unverändert.
4. **Die Übersicht je Region** (feat ⇒ MINOR, 0.105.0): Download mit
   dem ersten Bereich, Zeile in „Meine Bereiche", Backup-Ausschluss.
5. **18d (#229) danach:** eine ganze Region auf einmal speichern —
   dafür ändert sich §5 von `konzept-offline-karten.md`, nicht hier.

Nach 3 und 4 ist 🚀 C fällig, zusammen mit 18d.

## 7. Offen

- **Höhen in Kanada**: aus der Cloud hochgerechnet 520 MB und 72–127 min;
  der erste echte Lauf in CI sagt die Zahl, die zählt. Kommt er an die
  5 h des Jobs, kommt die Teilung.
- **Wege in Kanada** sagen wenig (3 % benotet, 18b). Sie werden trotzdem
  gebaut, weil sie fast nichts kosten und die Ebene sonst ein Sonderfall
  wäre; die Legende sagt ohnehin „unbekannt".
- **Class-B-Operationen** wachsen mit den Nutzern, nicht mit den
  Regionen (#55). Daran ändert dieses Konzept nichts.
