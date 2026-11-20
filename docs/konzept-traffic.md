# Konzept: Anfragen an den Kartenhost sparen

Stand 2026-11-20, Anlass: der erste Test der Ortsnamen-Suche (#576,
Stufe 2). Dort ging dieselbe Namensdatei beim Tippen sechsmal raus. Der
Betreiber dazu (2026-11-20): „Wie können wir den Traffic so minimieren,
damit es skalierbar bleibt, ohne dass die Kosten explodieren. Wenn man
ein Gebiet offline geladen hat, erwarte ich, dass gar keine Anfrage
rausgeht. Auch bei Suchen nach POI und so weiter.“

**Abgeschlossen am 2026-11-20** (#596): H1, H3, H4, H5 und H7 sind
gebaut und gemessen, H6 fällt weg, H2 ist mit einer Schwelle
zurückgestellt (#606). Die Abschnitte unten bleiben als Begründung
stehen.

Betroffen ist nur `tiles.mcbuchi.de` (Cloudflare R2 hinter der eigenen
Domain). Supabase hat eigene Kontingente und bekommt bei Bedarf ein
eigenes Konzept; die offiziellen Trails kommen von GitHub und kosten
nichts.

## 1. Regeln (Ziel)

1. **Im gespeicherten Bereich geht keine Anfrage an den Kartenhost.**
   Das gilt für Karte, Wege, Höhen, Höhenlinien, Orte und Suche — auch
   mit Netz. Das ist A8 („Offline zuerst“) zu Ende gedacht.
2. **Was einmal geholt wurde, wird nicht noch einmal geholt**, solange
   der Bau gleich ist. Gebaute Dateien tragen ein Datum und ändern sich
   nie. Ein Manifest fragt die App höchstens einmal am Tag.
3. **Was doch zum Host geht, beantwortet der Edge-Cache von Cloudflare**,
   nicht R2. Jede Antwort aus R2 ist eine Class-B-Operation: 10 Mio. je
   Monat frei, danach 0,36 $ je Mio. Egress ist frei. Die Kosten wachsen
   also mit den R2-Treffern, nicht mit den Bytes.
4. **Gemessen, nicht geschätzt**: Jeder Schritt unten hat eine Zahl
   vorher und nachher.

## 2. Bestand (gemessen 2026-11-20 mit `curl` gegen den Host)

| Weg | Wie | Edge-Cache | Im Bereich lokal? | Über die Sitzung hinaus gemerkt? |
|---|---|---|---|---|
| Karte (`dach-<bau>.pmtiles`, 2,8 GB) | Range je Kachel | **nein** (`DYNAMIC`; über 512 MB, die Grenze des Free-Plans) | Android: **nein**, die Online-Quelle steht neben `area-<region>` im Stil und lädt trotzdem. Web: ja (Speicher zuerst) | Android: Ambient Cache 100 MB. Web: IndexedDB 100 MB |
| Wege (`ways-<bau>.pmtiles`) | Range je Kachel | **nein** (`DYNAMIC`, Endung) | Android: **nein** (wie die Karte). Web: ja | wie die Karte |
| Höhen (`heights-<bau>.pmtiles`, 147 MB) | Range je Kachel | **nein** (`DYNAMIC`, Endung) | ja (`StoreHeightSource`) | **nein**, nur `OnlineTileCache` je Sitzung; der Planer behält bis 50 MB (#478) |
| Manifeste (`dach.json`, `ways.json`, `heights.json`, `regions.json`, `pois.json`) | je App-Start | **nein** (`DYNAMIC`, `.json` cacht Cloudflare nicht) | — | gemerkt nur Karte und Wege (`seenMapManifest`) |
| `pois.json` | je App-Start, **465 kB** (Zellenlisten aller Gruppen und Ortsnamen) | **nein** | — | nein |
| Orte-Zellen (`<z>_<s>.<gruppe>.json`) | je Zelle und Gruppe | **nein** | ja, wenn die Datei im Bereich liegt | **nein**, nur `PoiController` im Speicher |
| Namensdateien (`names/<schlüssel>.json`) | je Schlüssel | **nein** | **nein**: erst der Host, der Bereich nur bei Netzfehler | **nein**; dazu doppelte Anfragen beim Tippen |
| Bündel (`bundle.tsv.gz`) | einmal je ganzer Region | ja (`HIT`) | — | — |

Der Kern (vor H1): **Kaum etwas kam aus dem Edge-Cache.** Die Notiz
„die kleinen Dateien liegen im Edge-Cache“ in `lib/features/map/CLAUDE.md`
stimmt nicht. Cloudflare cacht ab Werk nur bestimmte Endungen, und
`.json` und `.pmtiles` gehören nicht dazu.

## 3. Hebel, nach Wirkung je Aufwand

**H1 — Cache-Regel für den Host** (👤 Dashboard, wenige Minuten; danach
☁️ Doku). Cloudflare → Zone `mcbuchi.de` → Caching → Cache Rules: für
`tiles.mcbuchi.de/trailbuddy/*` „Eligible for cache“, TTL vom Ursprung
übernehmen. Die Header setzen die Workflows schon richtig (gebaute
Dateien `immutable`, Manifeste 300 s). Danach kommen alle Manifeste und
Zellen- und Namensdateien aus der Edge, dazu die Höhen- und
Wege-Archive, die unter 512 MB liegen. R2 sieht dann je Rechenzentrum
und Datei einen Fehlgriff statt jeder Anfrage. Prüfen: `cf-cache-status:
HIT` beim zweiten Abruf. Größter Effekt, kein Code.

**Gesetzt am 2026-11-20** (Betreiber): Regel „trailbuddy tiles",
`http.host eq "tiles.mcbuchi.de"` und Pfad ab `/trailbuddy/`, „Eligible
for cache", Edge TTL „Use cache-control header if present, bypass cache
if not" (eine Datei ohne Header bleibt ungecacht wie vorher, statt still
zwei Stunden alt zu werden), Browser TTL „Respect origin TTL". Geprüft
mit `curl`, zweiter Abruf: `HIT` für alle fünf Manifeste, Orte-Zelle,
Namensdatei, und — als Range über 16 kB — für `heights-<bau>.pmtiles`
und `ways-<bau>.pmtiles`. Cloudflare bedient Range-Anfragen also aus
einem gecachten Archiv unter 512 MB; das ist die erste Frage von H2.
`dach-<bau>.pmtiles` (2,8 GB) steht auf `BYPASS`. Die CORS-Antwort ist
`*` für jede Herkunft, eine gecachte Antwort passt also zu jedem Origin.

**H2 — Karte in Stücke unter 512 MB** (⚙️ `map-data.yml`, ☁️ App). Das
2,8-GB-Archiv kann Cloudflare nie cachen, jede Kachel geht an R2. Wird es
in Stücke unter 512 MB geschnitten (z. B. Zoom 0–10 als ein Stück, 11–13
nach Fläche), greift H1 auch dort. Die App wählt das Stück je Kachel wie
heute die Region. Vorher **messen**: ob Cloudflare Range-Anfragen aus
einem gecachten großen Objekt bedient, wie oft es wieder verdrängt wird
und wie viel ein erster Fehlgriff kostet. Die Alternative, ein Worker
vor R2, ist im Free-Plan auf 100 000 Aufrufe am Tag begrenzt und
skaliert deshalb nicht kostenlos.

**Zurückgestellt (Betreiber, 2026-11-20) → #606.** Gemessen: Eine
Range-Anfrage an `dach-<bau>.pmtiles` kommt als `BYPASS`, jede
Kartenkachel außerhalb eines Bereichs ist also ein R2-Abruf. Das Konto
stand am 2026-11-20 aber bei 23 050 Class-B-Operationen im Monat, 0,23 %
der freien 10 Mio. (Class A 73 630 von 1 Mio., Speicher 6,12 von 10 GB).
Dagegen stünde ein Stil mit dem ganzen Protomaps-Ebenensatz je Stück.
Gebaut wird, wenn Class B über 3 Mio. im Monat steigt oder vor dem
Play-Store-Eintrag. Näher an der Grenze liegt der Speicher.

**H3 — Android: keine Online-Kachel im Bereich** (☁️ bauen, 📱 messen).
MapLibre lädt nur Kacheln einer Quelle, deren Ebenen sichtbar sind. Ist
der Ausschnitt beim aktuellen Zoom ganz von gespeicherten Kacheln
gedeckt (der Index ist bekannt), schaltet die App die Ebenen der
Online-Karte und der Online-Wege unsichtbar, ohne den Stil neu zu
bauen, und beim Verlassen wieder sichtbar. Im Web ist das schon so (der
Speicher kommt zuerst). **Gebaut seit 0.193.1** (Spike 2026-11-20:
`maplibre` 0.3.7+1 kennt keine Sichtbarkeit je Ebene; Betreiber:
„Ebenen raus/rein“ statt Neuaufbau des Stils oder Schalter je Region).
Die Ebenen gehen aus dem Stil und kommen an ihre Stelle zurück,
gedeckt heißt aus den Formen der fertigen Bereiche, mit einer Schwelle
am Rand (`lib/features/map/CLAUDE.md`, „Im Bereich keine
Online-Ebenen“). Gemessen am Pixel XL (2026-11-20, Dev-App 0.193.1):
im Bereich zwei Zoomstufen und vier Schwenks 0 Anfragen (Grundlinie:
6 fürs Zoomen), mit „Wege“ an acht Schwenks bei 100 m Maßstab 0; vom
Überblick bis 100 m hinein einmalig 1 Karte und 2 Wege, die schon
laufen, bevor die Kamera stillsteht. Hinaus kommt die Online-Karte
zurück (25 Kacheln auf ~16 Schwenks), mit Namen über den Wegen. Am
Pixel 7 Pro mit ganz DACH gespeichert: vier lange Schwenks bei 300 m
Maßstab, Wege an, 0 Anfragen; eine ganze Region deckt wie ein
gezeichneter Bereich.

**H4 — Gesehenes auch für kleine Dateien** (☁️; **gebaut seit 0.192.2**
für Orte-Zellen, Namensdateien und Orte-Manifeste, `lib/data/seen_host_files.dart`;
**seit 0.193.0** auch die Manifeste von Karte, Wegen, Höhen, Regionen
und der übrigen Regionen, `lib/features/map/host_manifests.dart`, und
die Höhenkacheln von Trail-Profil, Export, Import und Höhenlinien, die
ohne Netz aus der Ablage kommen). Orte-Zellen,
Namensdateien und Höhenkacheln, die vom Host kamen, landen in einem
Speicher auf dem Gerät: Android Dateien, Browser IndexedDB, Schlüssel mit
Bau, Deckel z. B. 20 MB, die älteste geht zuerst. Dasselbe Muster wie
„Gesehenes bleibt liegen“ (#155). Ein neuer Bau macht die alten
Schlüssel wertlos, sie gehen als Erste. Manifeste: das letzte merken und
höchstens alle 24 h neu fragen, sofort bei „Aktualisieren“ in „Meine
Bereiche“. Mit H1 sinken die R2-Kosten schon; H4 spart dazu die
Anfragen selbst und macht die App ohne Netz vollständiger.

**H5 — Suche offline zuerst** (☁️; **gebaut seit 0.192.2**). Ortsnamen: erst die Zellen der
gespeicherten Bereiche. Gibt es dort einen Treffer, geht nichts raus.
Sonst fragt die App den Host, eine Anfrage je Schlüssel, laufende
Anfragen werden geteilt und das Ergebnis gemerkt (H4). **Entschieden
(Betreiber, 2026-11-20: „Erst nach Tipp weiter suchen“):** Ohne lokalen
Treffer fragt die App nicht von selbst. Unter den Treffern steht eine
Zeile „Weitere Orte online suchen“, erst ihr Tipp schickt den Schlüssel
an den Host. Ohne gespeicherten Bereich gilt dasselbe: Online gesucht
wird immer nur auf Tipp. Orte (POIs) in
der Suche: wie heute erst der Bereich; Zellen außerhalb gehen über H4.
Mit hinein gehören die Funde aus dem Test: Ein Name, der genau der
Eingabe entspricht oder mit ihr beginnt, kommt zuerst, und das Ziel
bekommt eine kurze Nadel (Design-README). **Seit 0.193.0** gilt der
Rang nur bis 30 km von der Kartenmitte (`kMapSearchRankNearM`, Fund der
Grundlinie, Betreiber 2026-11-20), weiter weg zählt die Entfernung.
Bereiche von vor dem Orts-Index bekommen ihre Ortsnamen-Zellen über
„Aktualisieren" in „Meine Bereiche" (`missingPlaceFiles`), nie
ungefragt.

~~**H6 — `pois.json` verkleinern**~~ — **fällt weg** (Betreiber,
2026-11-20). Gemessen auf der Leitung: Cloudflare liefert die Datei
komprimiert, rund 90 kB mit gzip (Android, Darts `HttpClient`) und 31 kB
mit Brotli (Browser); seit H4 höchstens einmal am Tag. Ein neues Format
in Werkzeug und App samt zweitem Manifest für alte Apps lohnt für etwa
80 kB am Tag nicht. Der alte Plan: 465 kB bei jedem
App-Start, für Zellenlisten, die erst gebraucht werden, wenn eine Zelle
fehlt. Die Listen kommen in eine eigene Datei je Gruppe, oder das
Manifest trägt nur eine Bitmap des Rasters. Mit H4 (24 h) ist das nur
noch einmal am Tag fällig; trotzdem lohnt es sich wegen des
Datenvolumens am Handy.

**H7 — Zähler und Grundlinie** (☁️ Zähler, 📱 messen, 👤 Dashboard).
Vor allem anderen:
- In der Dev-App unter Profil → Entwicklung ein Zähler „Anfragen an den
  Kartenhost je Art seit Start“ (Karte, Wege, Höhen, Manifest, Orte,
  Namen). Damit eine feste Runde am Gerät messen: Karte schwenken im
  Bereich und außerhalb, suchen, planen. **Gebaut seit 0.192.1**
  (auch in der Web-Vorschau; auf Android zählt die Dev-App zusätzlich,
  was MapLibre über OkHttp lädt — `lib/features/map/CLAUDE.md`,
  „Anfragen an den Kartenhost zählen"). Grundlinie am Gerät
  2026-11-20 (in #596).
- Am Konto: R2-Class-B je Monat und die Cache-Quote aus Cloudflare
  Analytics. Abgelesen 2026-11-20: siehe H2 und Abschnitt 5;
  `r2-inventory.yml` listet nur Dateien, keine Operationen.
- Die Rate-Limiting-Regel aus #55 bekommt ihre Schwelle aus diesen
  Zahlen.

## 4. Grobe Rechnung (wird durch H7 ersetzt)

Ein Kartenschwenk sind Dutzende Kacheln, Karte und Wege zusammen grob
100 Anfragen je Minute Kartennutzung. Ohne H1/H2 ist jede davon eine
Class-B-Operation. 10 Mio. freie Operationen sind dann etwa 100 000
Minuten im Monat: 1 000 aktive Nutzer mit je 30 Minuten liegen mit
3 Mio. darunter, 10 000 Nutzer kämen auf etwa 10 $ im Monat, linear
steigend. Mit H1 bis H4 zahlt man nur noch Fehlgriffe der Edge und erste
Besuche. Wiederholte Fahrten im eigenen Revier kosten dann nichts mehr,
und das ist der Normalfall bei Trails.

## 5. Reihenfolge für die nächste Sitzung

1. ~~**H1** (👤, 5 min) — der Betreiber setzt die Cache-Regel, ich prüfe
   mit `curl` (`HIT`) und korrigiere die Notiz in `lib/features/map/CLAUDE.md`.~~
   2026-11-20, siehe H1.
2. ~~**H7** Zähler (☁️), dann die Grundlinie am Gerät (📱).~~ 0.192.1,
   Grundlinie 2026-11-20.
3. ~~**H5** mit den Testfunden (doppelte Anfragen, Reihenfolge, Nadel) und
   **H4** — ein PR, ein Bump.~~ 0.192.2; der Rest von H4 (Höhenkacheln
   für das Trail-Profil, Manifeste von Karte, Wegen, Höhen und Regionen)
   und die zwei Suchfunde der Grundlinie: 0.193.0.
4. ~~**H3** Spike (📱), dann bauen.~~ 0.193.1; Messung am Gerät.
5. ~~**H2** Messung (⚙️), dann entscheiden.~~ Zurückgestellt → #606.
6. ~~**H6**.~~ Fällt weg.

Fertig, wenn: (a) in einem gespeicherten Bereich zählt der Zähler beim
Schwenken, Suchen und Planen **0** Anfragen an den Kartenhost; (b) ein
zweiter Besuch eines gesehenen Ausschnitts kostet 0 Anfragen; ~~(c) die
Cache-Quote in Cloudflare liegt bei den kleinen Dateien über 90 %~~ —
mit einem Tester nicht messbar: Mit H4 geht jede Datei einmal als Miss
raus und bleibt dann auf dem Gerät, die Quote misst also nur, was sich
Geräte teilen. Stattdessen (c): **keine kleine Datei geht als
`DYNAMIC` oder `BYPASS` raus, und ein zweiter Client bekommt dieselbe
Datei als `HIT`.**

Erfüllt am 2026-11-20: (a) Pixel XL im Bereich und Pixel 7 Pro mit ganz
DACH, 0 Anfragen beim Schwenken; (b) mit H4; (c) Cloudflare zeigte bei
den kleinen Dateien nur noch Miss und Hit, zwei zufällige Orte-Zellen
kamen beim zweiten Abruf als `HIT`. Seit demselben Tag ist Smart Tiered
Cache an (Caching → Tiered Cache, kostenlos): Die Rechenzentren teilen
sich eine obere Ebene, die R2 fragt.
