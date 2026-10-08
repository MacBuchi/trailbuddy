# Karte über DACH hinaus: Messung

*Punkt 18b aus dem Fahrplan #156, Issue #220. Gemessen am 2026-10-08
aus einer Cloud-Sitzung gegen den Protomaps-Tagesbau `20261007` (Planet,
z0–15, 128,8 GB Kacheldaten) mit `tool/map_tiles.py plan`: Es liest nur
Header und Verzeichnisse — bis z13 sind das 34 MB in 318 Anfragen, die
Kacheln selbst nie. Ländergrenzen aus Natural Earth 1:50 m (v5.1.2,
gemeinfrei). Wiederholbar in CI: `map-data.yml`, Modus `plan`, Eingabe
`plan_select` (z. B. `ISO_A2_EH=CA` oder `world`); Wege und Orte mit
`way-data.yml` / `poi-data.yml`, Modus `plan`, `plan_region = canada`
(seit 18c heißt die Eingabe `region`, Wert `ca`, und schneidet bei
55° N — `docs/konzept-regionen.md`).*

## Ergebnis in fünf Sätzen

1. **Kanada bis z13 sind 4,3 GB Karte** — das 1,6-Fache des heutigen
   DACH-Rechtecks (2,61 GB, veröffentlicht 2,8 GB), obwohl es 22-mal so
   viele z13-Kacheln sind: Der Norden ist leer, und gleiche Kacheln
   stehen im Archiv nur einmal.
2. **Europa ohne Russland sind 10,3 GB, die ganze Welt 33,3 GB.** Mit
   der Vorgängerdatei, die jeder Lauf für laufende Sitzungen behält, ist
   das Doppelte belegt.
3. **Speicher kostet fast nichts, die Grenze ist der Runner.** R2 nimmt
   jenseits der 10 freien GB 0,015 $ je GB und Monat — die Welt doppelt
   sind rund 1 $ im Monat. Aber ein Standard-Runner hat laut GitHub
   14 GB garantierten Plattenplatz, und `pmtiles extract` schreibt die
   ganze Datei, bevor sie hochgeladen wird: Kanada passt, Europa knapp,
   die Welt nicht ohne Plattenaufräumen, größeren Runner oder 💻.
4. **Die Höhen sind der eigentliche Brocken.** Kanada hat 2,16 Mio.
   z13-Landkacheln (DACH-Rechteck: 98 640) in 2 242 DEM-Zellen (DACH
   ~140): geschätzt 3–5 GB und — linear vom DACH-Lauf (17 min)
   hochgerechnet — 4,5 bis 6 Stunden Bau, also an der 6-h-Grenze eines
   Jobs. Das braucht Aufteilung in mehrere Jobs oder 💻.
5. **Class-B-Operationen hängen nicht an der Region, sondern an den
   Nutzern**: Jede Kachel ist eine Range-Anfrage, egal wie groß das
   Archiv ist. Gemessen werden kann das nur im Cloudflare-Dashboard
   (#55); hier ändert sich nichts daran.

## Karte: Bytes je Zoom

Kumuliert, Kacheldaten ohne Verzeichnisse (die kommen beim fertigen
Archiv dazu: DACH-Rechteck 2,61 GB gemessen, 2,8 GB veröffentlicht).

| bis Zoom | DACH-Rechteck (heute) | DE+AT+CH | Kanada | Europa ohne RU | Welt |
|---|---:|---:|---:|---:|---:|
| z5 | 0,9 MB | 0,9 MB | 2,5 MB | 3,1 MB | 14 MB |
| z6 | 1,9 MB | 1,5 MB | 8,4 MB | 8,1 MB | 43 MB |
| z7 | 8,6 MB | 6,2 MB | 34 MB | 42 MB | 180 MB |
| z8 | 28 MB | 20 MB | 96 MB | 143 MB | 532 MB |
| z10 | 237 MB | 152 MB | 568 MB | 1,04 GB | 3,52 GB |
| z11 | 555 MB | 358 MB | 1,15 GB | 2,31 GB | 7,45 GB |
| z12 | 1,27 GB | 849 MB | 2,18 GB | 5,18 GB | 16,5 GB |
| **z13** | **2,61 GB** | **1,72 GB** | **4,30 GB** | **10,3 GB** | **33,3 GB** |

Drei Dinge, die man daraus lesen kann:

- **Das DACH-Rechteck ist zu 34 % Nachbarland** (2,61 gegen 1,72 GB).
  Das ist gewollt (#73: Südtirol, Elsass, Tschechien), zeigt aber, was
  Regionen nach Ländergrenzen sparen würden.
- **Die oberste Stufe ist überall die halbe Rechnung**: z13 allein
  sind bei DACH 51 %, bei Kanada 49 %, bei der Welt 51 % der Datei.
  Ein Zoom weniger halbiert also jede Region — die Welt bis z12 wären
  16,5 GB.
- **Eine Übersicht bis z7 passt für Kanada (34 MB) und Europa (42 MB)
  nicht mehr ins Binary** wie heute die DACH-Übersicht (8,6 MB). Die
  Welt bis z5 wären 14 MB, bis z6 43 MB.

## Die anderen Ebenen einer Region

| Ebene | heute | Werkzeug nimmt eine Region? | Kanada |
|---|---|---|---|
| Karte | `map-data.yml`, Rechteck | `pmtiles extract --region` kann Polygone; der Workflow gibt heute nur `--bbox` | 4,3 GB, Schnitt ~2,5 min (DACH: 2,8 GB in 90 s, Upload 37 s) |
| Höhen | `height-data.yml`, Rechteck, 147 MB | nur `--bbox`; Kanadas Rechteck schlösse die Nordstaaten der USA ein — braucht eine Polygon-Auswahl oder eine Liste von DEM-Zellen | 2,16 Mio. Kacheln, ~3–5 GB, 4,5–6 h — Aufteilung nötig |
| Wege | `way-data.yml`, Geofabrik-Auszüge + Rechteck, 126 MB | ja: der **Auszug** bestimmt das Gebiet, das Rechteck schneidet nur zu. `north-america/canada` existiert bei Geofabrik | **4,1 MB**, 19 398 Kacheln, 62 235 benotete Wege — rund 3 % des DACH-Archivs; Auszug + Filter 7 min, Bau 12 s |
| Orte | `poi-data.yml`, dieselben Auszüge, 165 MB | ja, wie Wege | **21,9 MB**, 254 320 Orte in 10 730 Dateien; Auszug + Filter 19 min, Bau 13 s |
| Übersicht | im Binary, DACH z0–7, 8,6 MB | `pmtiles extract --bbox` | 34 MB bis z7 — als Download je Region statt im Binary |

**In der App ist alles DACH**: `dach.json` als feste Manifest-Adresse
(`map_providers.dart`), dazu `heights.json`, `ways.json`, `pois.json`
ohne Regionsbezug und `overview_dach.pmtiles` als Asset. Das ist der
Umbau von 18c (ein Manifest je Region).

## Wege und Orte für Kanada

Gemessen am 2026-10-08 in CI (`way-data.yml` Lauf 37854995432,
`poi-data.yml` Lauf 37854998079, beide `mode = plan`,
`plan_region = canada`): Geofabrik-Auszug `north-america/canada`, Rechteck
−141,1 / 41,6 / −52,5 / 83,2, nichts hochgeladen.

- **Wege: 4,1 MB statt 119 MB in DACH.** 62 235 Wege tragen eine
  verwertbare Note (`tracktype`, `sac_scale`, `mtb:scale` …), 9 854
  weitere sind Kandidaten ohne. Der vorgefilterte Auszug hat 12,9 MB.
  Das heißt nicht, dass Kanada keine Wege hat — die Grundkarte zeichnet
  sie —, sondern dass sie dort kaum benotet sind. Die Ebene „Wege" und
  die Preise der Planung für Wegqualität (#213) hätten in Kanada also
  fast überall „unbekannt" und damit wenig zu sagen; das Archiv selbst
  kostet nichts.
- **Orte: 21,9 MB, 254 320 Orte** in 10 730 Zellendateien (DACH-Rechteck
  heute 165 MB im Bucket). 63 % davon sind Parkplätze (159 607), dann
  Restaurants (32 667), Toiletten (15 113), Unterstände (13 578) und
  Cafés (12 546); Trinkwasser 6 784, Reparaturstationen 901,
  Radläden 953. Die Mindestzahl des DACH-Laufs (100 000) würde Kanada
  also auch erfüllen.
- **Zeit**: Der Download des Auszugs ist der Hauptteil (7 bzw. 19 min),
  der Bau dauert Sekunden. Beides passt bequem in einen Job.

## Speicher im Bucket

Stand 2026-10-08 (erster Lauf von `r2-inventory.yml`, #230): 6,2 GB von
10 GB frei, davon Karte 2 × 2,8 GB. Eine zweite Region in DACH-Größe
sprengt das Freikontingent; Kanada mit Karte (2 × 4,3 GB) und Höhen
(~3–5 GB) liegt bei rund 12–14 GB zusätzlich, also etwa 0,15 $ im
Monat über dem Freikontingent. Speicher entscheidet also nichts — Runner, Bauzeit und die
Class-B-Frage (#55) schon.

Was daraus gebaut wird, steht in `docs/konzept-regionen.md` (18c): Kanada
südlich 55° N (1,99 GB Karte, gemessen wie oben), damit DACH und Kanada
zusammen im Free-Kontingent bleiben.

## Was diese Messung NICHT sagt

- **Class-B je Sitzung**: braucht echte Sitzungen und das Dashboard.
- **Der Rand**: Regionen werden bei z10 gerastert (`REGION_COVER_ZOOM`),
  eine Region ist also bis zu eine z10-Kachel breiter als ihre Grenze —
  bei Kanada 2,34 statt 2,16 Mio. z13-Kacheln (+8 %). Die Zahlen oben
  sind damit eher zu groß als zu klein, und `pmtiles extract --region`
  schneidet genauer.

## Wiederholen

Lokal oder in der Cloud (Natural Earth als GeoJSON daneben legen):

    python3 tool/map_tiles.py plan --source https://build.protomaps.com/<JJJJMMTT>.pmtiles \
        --region ne_50m_admin_0_countries.geojson --select ISO_A2_EH=CA --maxzoom 13

In CI: `map-data.yml` von Hand, `mode = plan`, `plan_select =
ISO_A2_EH=CA` (oder `world`), `plan_zooms = 12 13`. Die Grenzdatei ist
dort per Tag und Prüfsumme festgenagelt.
