# Routing-Messung (#35): tragen unsere Daten die eigene Engine?

*Messplan: `docs/konzept-routing.md` Abschnitt 6. Werkzeug:
`tool/route_measure.py` (Selbsttest in CI), Tirol-Lauf `route-measure.yml`
(Run 4 vom 2026-10-01, Kacheln `dach-20261001.pmtiles` vom eigenen Host,
offizielle Trails vom Daten-Branch, Höhen Copernicus GLO-90). Dieser
Bericht nennt Kennzahlen, keine Orte, keine Namen von Fahrten. Stand:
2026-10-02 — M1, M3 (Tirol-Hälfte) und M5 gemessen; M2, M4 und die
Kalibrierung aus dem lokalen Lauf an 47 Fahrten des Betreibers.*

## Ergebnis in fünf Sätzen

1. **Die z13-Kacheln tragen den Graphen — mit zwei Reparaturen beim
   Bauen** (M1): Ohne sie zerfällt das Wegenetz eines 20-km-Rahmens in
   500 bis 8 000 Stücke, die größte Komponente hält nur 50–80 % der
   Kantenlänge. Werden tote Enden innerhalb von 2 m an den nächsten
   anderen Weg gebunden (auch mitten in ein Segment) und Kreuzungen
   ohne gemeinsamen Knoten geteilt (gleiche Ebene, keine Brücke, kein
   Tunnel), hält die größte Komponente 95 / 97 / 98 % und trägt
   98 / 93 / 100 % der Trail-Enden. Beide Schwellen sind erfüllt.
2. **Ein größerer Verbindungsradius bringt nichts mehr**: 10 m statt
   2 m heben die größte Komponente um 0–2 Punkte und keinen Trail-End-
   Anschluss. 2 m bleibt.
3. **Das PilzBuddy-Gitter reicht fürs Routing nicht** (M3): 250-m-Waben
   mit 20-m-Stufen treffen die Abstiegsmeter der offiziellen Trails mit
   42 % Medianfehler und überschätzen sie um ein Viertel; das DEM
   direkt (90 m) trifft sie mit 5 % und zu zwei Dritteln innerhalb
   ±10 %. Weg B aus dem Konzept (Höhenkacheln je Bereich, 90 m, die
   Auflösung von Locus) ist gesetzt.
4. **Die Laufzeit ist unkritisch** (M5): Graph aus 25 000 Wegstücken in
   ~2 s, Dijkstra von 22 Trail-Enden mit 3-h-Budget in 3,7 s — in
   Python, auf dem Runner. Teuer ist nur das Lesen der Kacheln vom Host
   (18–22 s je 49 Kacheln über Range-Anfragen); auf dem Gerät liegen sie
   im gespeicherten Bereich.
5. **An den eigenen Fahrten** (M2, M4, Kalibrierung, 2026-10-02): Der
   Forstweg trägt die Aufstiege (36–55 %); die Steigrate dieses
   Fahrers liegt bei 320–400 hm/h, mit dem E-MTB nicht höher — die
   Vorgaben (450 / 850) bleiben, lernen soll die Kalibrierung. M4
   verfehlt die Schwelle (1 von 15 gleich), aber der Plan ist nach dem
   Modell nie langsamer als die Fahrt, und kein Kostenaufschlag rückt
   ihn näher an sie: Die Schwelle misst den gefahrenen Weg, nicht den
   besten.

## M1 — Zusammenhang des z13-Graphen

Drei 20-km-Rahmen um die dichtesten Gruppen offizieller Trails (Ötztal,
Kitzbüheler Alpen, Innsbruck — als Gegend, nicht als Trail). Je Rahmen
49 Kacheln; „Wegstücke" sind die nutzbaren Linien nach Klassentabelle
und Zuschnitt auf den Kachelrahmen (der Puffer der Kacheln fällt weg,
sonst läge jeder Weg nahe einer Grenze doppelt im Graphen).

| Rahmen | Wegstücke | Graph | Komponenten | größte (Länge) | Trail-Enden ≤ 30 m | davon an der größten |
|---|---|---|---|---|---|---|
| 1 | 3 035 | nur geteilte Knoten | 499 | 57 % | 63 / 64 | 60 / 64 (94 %) |
| | | + Enden ≤ 2 m verbunden | 83 | 95 % | 63 / 64 | 63 / 64 (98 %) |
| | | + Kreuzungen geteilt | 73 | 95 % | 63 / 64 | 63 / 64 (98 %) |
| | | ≤ 10 m + Kreuzungen | 56 | 97 % | 63 / 64 | 63 / 64 (98 %) |
| 2 | 13 706 | nur geteilte Knoten | 3 611 | 50 % | 43 / 46 | 22 / 46 (48 %) |
| | | + Enden ≤ 2 m verbunden | 392 | 97 % | 43 / 46 | 39 / 46 (85 %) |
| | | + Kreuzungen geteilt | 332 | 97 % | 43 / 46 | 43 / 46 (93 %) |
| | | ≤ 10 m + Kreuzungen | 349 | 98 % | 43 / 46 | 43 / 46 (93 %) |
| 3 | 24 722 | nur geteilte Knoten | 8 093 | 80 % | 44 / 44 | 34 / 44 (77 %) |
| | | + Enden ≤ 2 m verbunden | 989 | 98 % | 44 / 44 | 44 / 44 (100 %) |
| | | + Kreuzungen geteilt | 855 | 98 % | 44 / 44 | 44 / 44 (100 %) |
| | | ≤ 10 m + Kreuzungen | 903 | 98 % | 44 / 44 | 44 / 44 (100 %) |

Was die Diagnose dazu sagt:

- **Tote Enden** im strengen Graphen: 2 174 / 13 448 / 25 375. Davon
  liegt der nächste andere Weg bei 42 / 37 / 44 % innerhalb von 2 m —
  das sind die Kachelgrenzen UND die T-Kreuzungen, deren Knoten die
  Vereinfachung aus dem durchgehenden Weg entfernt hat. 26 / 24 / 12 %
  liegen weiter als 30 m weg: echte Sackgassen (Forstwege enden im
  Wald, Zufahrten am Haus).
- **Kreuzungen ohne gemeinsamen Knoten**: 417 / 1 983 / 4 019 je Rahmen.
  Sie sind der Hebel für die Trail-Enden in Rahmen 2 (85 → 93 %); für
  die Kantenlänge tun sie wenig, weil die 2-m-Verbindung die meisten
  Stücke schon erreicht.
- **Kleinstteile** unter 200 m nach allen Reparaturen: 33 / 270 / 802
  Komponenten, zusammen 0 / 0 / 1 % der Länge — Stichwege hinter
  Privatstraßen und Zufahrten, die die Klassentabelle verwirft. Kein
  Routing-Verlust.
- **Nicht angeschlossene Trail-Enden** (1 / 3 / 0): kein Weg innerhalb
  von 30 m — Trails, die an einer Bergstation oder auf einer Wiese
  beginnen. Der Planer sagt dann „nicht erreichbar".

Die drei Zahlen, die das Ergebnis erst herstellten, stehen im
Werkzeug und gehören in die Dart-Engine (Schritt 3):

1. **Zuschnitt auf den Kachelrahmen**, damit der Puffer der Kacheln
   keinen Weg doppelt legt; die beiden Enden an der Grenze bindet die
   Verbindung.
2. **Verbindung ≤ 2 m, auch mitten in ein Segment.** Der erste Lauf
   verband nur Knoten mit Knoten (554 Verbindungen, wo 11 000 Enden in
   Reichweite lagen) — die Suche nach dem nächsten Segment fand das
   eigene, in Abstand 0, und übersprang den Fall. Ein Selbsttest hält
   die T-Kreuzung seither fest.
3. **Kreuzungen teilen**, aber nur auf derselben Ebene: Die Kacheln
   tragen `is_bridge` und `is_tunnel`, und eine Brücke über eine Straße
   ist keine Kreuzung.

## M3 — Höhen (Tirol-Hälfte, gemessen 2026-10-01)

168 der 181 offiziellen Trails nennen Abstiegsmeter. Entlang ihrer
Linie, 50-m-Abtastung, 10 m Hysterese, gegen die Zahl der Quelle (die
ist selbst gerechnet — eine Bodenwahrheit sind erst die GPX-Höhen des
lokalen Laufs):

| Höhenquelle | Medianfehler | 90. Perzentil | innerhalb ±10 % | Median DEM/Quelle |
|---|---|---|---|---|
| DEM direkt (Copernicus GLO-90, 90 m, bilinear) | 5 % | 53 % | 67 % | 0,99 |
| Gitter A simuliert (250-m-Waben, Mittel, 20-m-Stufen) | 42 % | 167 % | 15 % | 1,25 |

Hysterese 3 / 5 / 10 / 20 m am DEM direkt: Medianfehler 6 / 5 / 5 / 5 %,
Verhältnis 1,01 / 1,00 / 0,99 / 0,98 — 10 m bleibt. Je Rahmen streut
der Median zwischen 4 % (Kitzbühel) und 18 % (Innsbruck, n = 21); die
Zahl über alle 168 ist die belastbare. Der DEM-Leser wurde an drei
bekannten Höhen geprüft (Innsbruck 581 m zu 574, Patscherkofel 2240 zu
2246, Hafelekar 2273 zu 2334 — an einem Grat glättet eine 90-m-Zelle den
Gipfel, das ist die Auflösung, kein Lesefehler).

Warum das Gitter durchfällt, obwohl die Waben-MITTEL stimmen: Entlang
einer Linie springt der Wert an jeder Wabengrenze um ganze 20-m-Stufen,
und in Kehren liegen Anfang und Ende einer Kehre oft in derselben Wabe
— das Höhenprofil wird eine Treppe, deren Stufen die Hysterese nicht
mehr als Rauschen erkennt. Für die Pilzampel (Temperaturkorrektur je
Spot) ist dasselbe Gitter richtig; für Routing ist die Linie die
Einheit, nicht der Punkt.

**Folge für Schritt 2 des Plans:** Höhenkacheln vom eigenen Host, 1 Byte
je 90-m-Zelle, gezippt ~3 KB je z13-Kachel, geladen mit dem Bereich wie
die Orte-Zellen. Kein neues Netzziel.

## M5 — Laufzeit (Python auf dem Runner)

| Rahmen | Kacheln lesen (Host, Range) | Graph bauen (zweimal) | Höhen je Kante | Dijkstra von allen Trail-Enden, 3 h | erreichbare Trail-Anfänge je Ende |
|---|---|---|---|---|---|
| 1 (3 035 Wegstücke) | 19,4 s | 0,60 s | 13,7 s (4 DEM-Kacheln geholt) | 0,38 s (31 Läufe) | Median 27, max 30 |
| 2 (13 706) | 18,7 s | 2,42 s | 3,8 s | 1,32 s (21) | Median 12, max 16 |
| 3 (24 722) | 18,2 s | 4,28 s | 0,9 s | 3,70 s (22) | Median 18, max 21 |

Graph plus Dijkstra liegen in Python bei 0,7–6 s je Rahmen; die
Schwelle „< 2 s auf dem Rechner" hält der dichteste Rahmen damit nicht,
die „< 5 s auf dem Telefon" ist für die Dart-Engine (AOT, ohne die
Diagnose-Varianten) zu messen — Schritt 3. Das Lesen der Kacheln ist auf
dem Gerät kein Thema (gespeicherter Bereich, keine Range-Anfragen); die
DEM-Zeit ist der Download der Copernicus-Kacheln, nicht die Rechnung.

## Beispiel-Aufstiege (zum Ansehen)

Ende eines Trails zum nächsten Anfang eines anderen, Profil Bio-Bike,
Kostentabelle aus dem Konzept:

| Luftlinie | Weg | bergauf | bergab | Wanderweg | Zeit | Klassenmix |
|---|---|---|---|---|---|---|
| 0,9 km | 4,2 km | 509 hm | 14 hm | 0 | 85 min | Zufahrt 4,2 km |
| 2,3 km | 4,8 km | 491 hm | 22 hm | 0,8 km | 91 min | Forstweg 2,5, Nebenstraße 1,4, Wanderweg 0,8 |
| 1,2 km | 1,9 km | 210 hm | 11 hm | 0,1 km | 37 min | Forstweg 1,8 |
| 0,4 km | 2,1 km | 145 hm | 15 hm | 0,2 km | 28 min | Forstweg 1,4, Bundesstraße 0,3, Wanderweg 0,2 |
| 0,6 km | 2,7 km | 116 hm | 0 hm | 1,2 km | 31 min | Wanderweg 1,1, Nebenstraße 0,9, Bundesstraße 0,4 |

Die Wege sehen aus wie Wege, die man fährt: Forststraße und Almzufahrt
zuerst, Wanderweg dort, wo es kürzer ist als der Umweg, Bundesstraße nur
als Brücke über wenige hundert Meter. Ob das stimmt, sagt M4.

## #194 — Steile Anstiege (Run 7 vom 2026-10-02)

Feldbericht aus 0.74.0: „Super steile Anstiege (falls nicht zum
deklarierten Uphill-Trail gehörend) sollten bestraft werden, insbesondere
wenn kein Asphalt sondern nur Weg." Gemessen wird, wie steil die Klassen
auf dem DEM sind und was ein Aufschlag ab einer Grenze an den
Beispiel-Aufstiegen ändert. Höhen alle 50 m je Kante, in ihrer
Aufwärtsrichtung; „geglättet" heißt Höhen UND Positionen über drei Proben
gemittelt (`steep_excess`). Rahmen 2 und 3:

| Klasse | Steigung Median / 90. / 99. Perzentil | hm über 15 %, roh / geglättet | über 20 %, geglättet |
|---|---|---|---|
| Forstweg | 9 / 18 / 29–30 % | 22–23 % / 10 % | 3–4 % |
| Zufahrt | 7–8 / 15–16 / 26–28 % | 16–21 % / 6–7 % | 2–3 % |
| Nebenstraße | 7 / 14–15 / 25 % | 12–15 % / 4–6 % | 1 % |
| Wanderweg | 13–14 / 30–36 / 51–66 % | 39–47 % / 29–36 % | 18–25 % |

Vier Dinge daraus:

1. **Roh doppelt so viel wie geglättet** — auf allen Klassen. Ein Weg
   liegt ein paar Meter neben seiner Linie im 90-m-Modell, und quer zu
   einer steilen Flanke ist das allein schon einige Prozent je
   50-m-Schritt. Gerechnet wird geglättet.
2. **15 % trifft das steilste Zehntel der Forstweg-Höhenmeter**, auf
   Straßen ein Zwanzigstel; das 90. Perzentil der Forstwege liegt bei
   18 %. Das ist „sehr steil" für eine Forststraße, und das DEM glättet
   eine echte Rampe eher flacher, als sie ist. **Grenze 15 %**
   (`STEEP_GRADE`, `kSteepGrade`).
3. **Der Aufschlag**: Jeder Höhenmeter über der Grenze kostet seine
   Steigzeit noch einmal, mal drei auf Schotter und Pfad, mal eins auf
   Asphalt, auf Stufen nichts (dort wird ohnehin geschoben). Bio auf
   Forstweg: 24 s je steilem Höhenmeter. Kosten, keine Minuten — das
   Zeitmodell bleibt, was die Fahrten kalibrieren.
4. **Die Wirkung**: 3 bzw. 4 von 15 Beispiel-Aufstiegen nehmen einen
   anderen Weg, die steilen Höhenmeter sinken um ein Drittel (291 → 202,
   228 → 161). Wo sich der Weg ändert, wird er im Median 20–31 % länger,
   höchstens 41–52 % — das Beispiel „1,9 km, 210 hm" wird „2,7 km,
   226 hm" mit der Hälfte der steilen Meter. Wanderwege sind von sich aus
   steil (ein Drittel ihrer Höhenmeter über 15 %); der Aufschlag macht
   sie bergauf noch einmal teurer, zusätzlich zu ×1,4.

Uphill-Trails und Verbinder tragen keinen Aufschlag — sie sind der
Anstieg, den jemand gewählt hat (#185). Der Feldtest (#188) prüft Grenze
und Faktoren mit.

## #188 — Rechenzeit des Planers (Dart, 2026-10-02)

Der Rundenplaner rechnete bis 0.80.0 im UI-Isolate. Gemessen mit
`test/routing/perf_loop_planner_measure.dart` (von Hand, nicht in CI) auf
einem erfundenen Netz in der Größe des dichtesten Tirol-Rahmens: Gitter
25 × 25 km, 200 m Maschenweite, 31 500 Kanten, Forstweg/Wanderweg/
Nebenstraße im Wechsel, Höhen aus einer glatten Hügelfläche; die Trails
steigen das Gitter hinab, gestreut über 12 km um den Start. Rechner, JIT —
eine untere Grenze für das Telefon. Alle Zeiten in ms; „Pause" ist die
längste Lücke eines 4-ms-Takts im UI-Isolate, also das, was man als
stehende Karte sieht.

| Trails | Budget | Graph bauen | Trails auflegen | an Ort und Stelle (= Pause) | Isolate, 1. Rechnung: Dauer / Pause | Isolate, weitere: Dauer / Pause | Halte |
|---|---|---|---|---|---|---|---|
| 12 | Bio 3 h / 1 000 hm | 248 | 48 | 290 | 562 / 276 | 207 / 11 | 1 |
| 30 | Bio 3 h / 1 000 hm | 209 | 41 | 466 | 906 / 352 | 521 / 23 | 1 |
| 40 | Bio 5 h / 1 600 hm | 304 | 53 | 1 171 | 1 822 / 301 | 1 586 / 31 | 4 |
| 60 | E-Bike 5 h / 2 500 hm | 112 | 52 | 2 351 | 2 351 / 289 | 2 005 / 23 | 8 |

Drei Befunde:

1. **Die Rechnung wächst mit der Auswahl**, nicht mit dem Netz: je
   Trail-Ende ein begrenzter Dijkstra über das ganze Budget, dazu 300 ms
   lokale Suche (fester Deckel). Ab 30–40 Trails steht die Oberfläche auf
   dem Rechner über eine Sekunde, auf dem Telefon länger — die Schwelle
   aus #188 („spürbar") ist damit ohne Gerät überschritten.
2. **`Isolate.run` je Rechnung hilft kaum**: Das Senden kopiert den
   Graphen IM UI-Isolate, und das allein sind 0,3–0,6 s Pause. Deshalb
   ein dauerhafter Rechen-Isolate (`loop_plan_runner.dart`, seit 0.80.1):
   Der Graph geht einmal hinüber (~0,3 s Pause, einmal je geladenem
   Graphen), jede weitere Rechnung schickt nur Start, Budget, Profil und
   Trails — 11–31 ms Pause, unabhängig von der Auswahl.
3. **Was bleibt, ist das Laden**: Graph bauen (0,1–0,3 s) und Trails
   auflegen (≤ 0,1 s) laufen weiter im UI-Isolate, dazu das einmalige
   Senden. Sie hinüberzunehmen hieße, die Kacheln roh zu schicken und
   drüben zu dekodieren — erst, wenn das Telefon dort eine Pause zeigt.

Die Halte sind wenige, weil die Hügelfläche steil und das Budget knapp
ist; gemessen wird die Zeit, nicht die Güte der Runde.

### Gemerkte Suchen (0.80.2)

Befund 1 galt auch im Isolate: Die weitere Rechnung kostete fast so viel
wie die erste, weil jede Rechnung ihre Dijkstras neu lief. Seit 0.80.2
behält der Isolate sie (`LoopSearchCache` in `loop_planner.dart`), solange
Graph, Graph-Stand, Profilwerte und Zeitbudget dieselben sind. Dieselbe
Messung, dazu eine dritte Rechnung mit einem Trail weniger (Abwählen):

| Trails | an Ort und Stelle | Isolate, 1. Rechnung: Dauer / Pause | dieselbe noch einmal: Dauer / Pause | ein Trail weniger: Dauer / Pause |
|---|---|---|---|---|
| 12 | 275 | 626 / 334 | 1 / 1 | 1 / 1 |
| 30 | 377 | 758 / 212 | 2 / 2 | 2 / 2 |
| 40 | 1 181 | 1 544 / 303 | 5 / 5 | 5 / 5 |
| 60 | 1 910 | 2 206 / 251 | 35 / 4 | 30 / 4 |

Die erste Rechnung bleibt, wie sie war — sie IST die Suche. Danach
bleiben nur das Bewerten der Folgen und die lokale Suche, und die
konvergiert hier lange vor ihrem Deckel von 300 ms. Ein Trail DAZU aus
dem geladenen Rahmen kostet ebenso wenig: Seine Enden sind beim Laden
angeheftet (`loadPlanningGraph`), sein Anheften teilt also keine Kante,
und der Speicher bleibt gültig. Neu suchen müssen ein anderes Profil,
ein anderes Zeitbudget (die Grenze der Suche) und ein neuer Start.

## M2 / M4 / Kalibrierung — eigene Fahrten (2026-10-02)

`tool/route_measure.py rides` an 47 Fahrten des Betreibers mit Zeit und
Höhe (2019–2025), Kacheln `dach-20261001.pmtiles` vom Host, Höhen
Copernicus GLO-90, Trails aus der Sammlung (584). Eingeteilt nach der
Sportart, die Strava zu jeder Fahrt führt — die Geschwindigkeit allein
hielt fünf E-MTB-Fahrten für Bio-Fahrten:

| Gruppe | Fahrten | Profil |
|---|---|---|
| E-MTB (Strava `EMountainBikeRide`/`EBikeRide`) | 10 | `ebike` |
| Bio, von Strava bestätigt (`MountainBikeRide`/`Ride`) | 7 | `bio` |
| Bio, 2019–2021 (vor dem ersten E-Bike) | 30 | `bio` |

Weggelassen: Wanderungen (18), kaputte Dateien (3), gezeichnete Spuren
mit fester Geschwindigkeit (4) und fünf Fahrten, deren Rad sich nicht
sicher zuordnen ließ. Die Fahrten lagen nur auf dem Rechner des Laufs;
hier stehen Kennzahlen, keine Orte.

### Kalibrierung — Steigrate je dominanter Klasse

Steigrate = Höhenmeter eines Aufstiegs (≥ 100 hm am Stück) durch die
Zeit vom Fuß bis zum Gipfel, **Pausen eingeschlossen** — so rechnet
auch die Kalibrierung in der App (`ride_calibration.dart`), die Zahlen
sind vergleichbar.

| Gruppe | Forstweg (Median) | Straße | Wanderweg | Vorgabe Forstweg / Pfad |
|---|---|---|---|---|
| E-MTB | **333 hm/h** (12 Aufstiege) | 408 (3) | 356 (1) | 850 / 650 |
| Bio, bestätigt | **319 hm/h** (12) | 198 (2) | 396 (1) | 450 / 350 |
| Bio, 2019–2021 | **399 hm/h** (32) | 373 (10) | 355 (7) | 450 / 350 |

Für DIESEN Fahrer schätzt das E-Bike-Profil die Aufstiege rund 2,5-mal
zu schnell, das Bio-Profil um ein Achtel bis ein Drittel. Mit dem E-MTB
steigt er kaum schneller als mit dem Bio-Rad. **Die Vorgaben bleiben**:
850 hm/h sind für sportliche E-MTB-Fahrer realistisch, ein Fahrer ist
kein Maßstab — dafür gibt es die Kalibrierung (Schritt 6). Die lernt
aber nur aus Fahrten, die in der App aufgezeichnet wurden; diese 47
Fahrten zählen dort nicht. Offen: importierte Fahrten mit gewähltem
Profil zur Kalibrierung zulassen.

### M2 — Klassenmix der eigenen Aufstiege

| Klasse | E-MTB (17 Aufstiege) | Bio bestätigt (16) | Bio 2019–2021 (57) |
|---|---|---|---|
| forstweg | 55 % | 55 % | 36 % |
| hauptstrasse | 14 % | 15 % | 17 % |
| nebenstrasse | 13 % | 10 % | 14 % |
| wanderweg | 9 % | 14 % | 15 % |
| abseits (kein Weg in 15 m) | 2 % | 1 % | 7 % |
| Rest (zufahrt, radweg, fussweg, stufen, bundesstrasse) | je ≤ 2 % | je ≤ 4 % | je ≤ 5 % |

Der Forstweg trägt die Aufstiege, wie Tabelle 2.4 annimmt; Straßen und
Wanderwege teilen sich den Rest zu etwa gleichen Teilen.

### M4 — Aufstiegstreue: nach der Schwelle nicht bestanden

Vom Fahrtstart zum ersten bekannten Trailkopf (mindestens 300 m
entfernt): 15 Fälle (E-MTB 3, Bio bestätigt 1, Bio 2019–2021 11), der
A* findet jedes Mal einen Weg, **gleich (15 m, 0,8 beidseitig) ist
einer**. Die Schwelle (≥ 70 %) ist klar verfehlt. Die Deckung liegt im
Median bei 0,15, und das liegt nicht an der Kostentabelle:

| Variante (Aufschlag) | gleich | Deckung (Median der kleineren) | Planer: forst / haupt / wander / neben |
|---|---|---|---|
| heute (Hauptstraße 2,5; Wanderweg bergauf 1,4 Bio, 2,0 E) | 1 / 15 | 0,15 | 47 / 8 / 4 / 30 % |
| Hauptstraße 1,6 / 1,2 / 1,0 | 1 / 15 | 0,15 | 39–33 / 20–42 / 1–2 / 29–15 % |
| Wanderweg 1,2·1,6 / 1,0·1,2 / 1,0·1,0 | 1 / 15 | 0,15 | 46–47 / 5–6 / 7–9 / 28–31 % |
| Hauptstraße 1,2 + Wanderweg 1,0·1,2 | 1 / 15 | 0,15 | 39 / 31 / 3 / 17 % |
| alle Faktoren 1,0 (nur Zeit) | 1 / 15 | 0,16 | 32 / 38 / 2 / 21 % |
| **gefahren** | | | **31 / 24 / 18 / 16 %** |

Billigere Hauptstraßen verschieben den Mix des Planers zur Straße, die
Deckung mit der Fahrt bleibt dieselbe; die Wanderwege, auf denen der
Fahrer bergauf fährt, liegen gar nicht auf den schnellen Wegen. **Die
Tabelle bleibt.**

Die Gegenprobe: Die Fahrt selbst auf den Graphen gelegt (der günstigste
Weg über die Kanten, die sie in 25 m Abstand abfährt) und nach DEMSELBEN
Zeitmodell gerechnet:

- Modellzeit gefahren / geplant: Median **1,27**, kleinster 1,00,
  größter 1,91; ≤ 1,10 bei 4, ≤ 1,20 bei 6 von 15. Der Planer ist in
  keinem Fall langsamer und nie mehr als 7 % länger.
- Acht Fahrten verlassen den Graphen stückweise (Wege, die in den
  Kacheln fehlen, oder ein GPS weiter als 25 m daneben); die Kosten
  dort zählen tausendfach, die Zeit normal.
- Die längste „Auffahrt" ist 32 km lang — eine Tour, die erst später
  an einen bekannten Trail kommt, keine Anfahrt.

### Welche Einstellung passt zu den Fahrten?

Umgekehrt gefragt: Unter welchen Aufschlägen ist die gefahrene Strecke
(auf dem Graphen, Stücke außerhalb zu ihren echten Kosten) am wenigsten
teurer als der Plan? Kosten gefahren / geplant über die 15 Fälle:

| Variante | Median | Mittel | ≤ 1,10 | ≤ 1,20 |
|---|---|---|---|---|
| heute | 1,55 | 1,59 | 3 | 4 |
| ohne Steil-Aufschlag | 1,54 | 1,61 | 2 | 3 |
| Steil ab 12 % / ab 20 % | 1,55 / 1,54 | 1,58 / 1,58 | 2 / 3 | 4 / 4 |
| Steil-Faktor 1/1 (Belag egal) / 6/2 (doppelt) | 1,54 / 1,55 | 1,58 / 1,59 | 3 / 2 | 4 / 4 |
| Hauptstraße 1,2 / 1,0 | 1,44 / 1,48 | 1,52 / 1,53 | 3 / 3 | 4 / 4 |
| Nebenstraße und Zufahrt 1,0 | 1,63 | 1,59 | 3 | 4 |
| Wanderweg bergauf 1,0 Bio / 1,2 E | 1,53 | 1,57 | 1 | 3 |
| Hauptstraße 1,2 + Wanderweg 1,0/1,2 + Nebenstraße 1,0 | 1,36 | 1,46 | 1 | 4 |
| dasselbe ohne Steil-Aufschlag | 1,35 | 1,44 | 2 | 5 |

Der Steil-Aufschlag verschiebt nichts (± 0,01) — auf diesen Auffahrten
entscheidet er nicht, er bleibt für die Rampen, gegen die er gebaut ist
(#194). Billigere Straßen und Wanderwege passen etwas besser zu diesem
Fahrer, um ein Zehntel; der größte Teil des Abstands bleibt — Umwege,
die kein Aufschlag erklärt. Für eine neue Vorgabe für alle reichen
15 Fälle eines Fahrers nicht; es ist Geschmack, und Geschmack gehört
in einfache Einstellungen des Planers statt in die Tabelle.

### Die Strafkurven (0.81.0)

Der Betreiber darauf: „meiden / egal passt für die erste Version … eher
bestimmte Bestrafungsfunktionen" — Straße teurer als Radweg und
Feldweg, bergab teurer, sehr steil bergauf exponentiell teurer.
Gebaut (Konzept-Routing 2.4): Steil-Gewicht ab 10 % (×3–4 je fünf
Punkte), verschenkte Höhe 0,3 der Steigzeit, und drei Schalter, deren
„egal" 35 % (Straßen, Wanderweg bergauf) bzw. 30 % (steil) des
Aufschlags lässt. Dieselbe Gegenprobe:

| Variante | Median | Mittel | ≤ 1,20 | Planer: forst / haupt / wander / neben |
|---|---|---|---|---|
| bis 0.80.x | 1,55 | 1,59 | 4 | 47 / 8 / 4 / 30 % |
| 0.81.0, alles meiden, ohne verschenkte Höhe | 1,55 | 1,65 | 4 | 47 / 8 / 3 / 31 % |
| 0.81.0, alles meiden (Vorgabe) | 1,52 | 1,62 | 4 | 47 / 8 / 3 / 31 % |
| verschenkte Höhe 0,5 statt 0,3 | 1,50 | 1,63 | 4 | 49 / 7 / 3 / 30 % |
| Straßen egal | **1,38** | 1,56 | 5 | 39 / 20 / 1 / 29 % |
| Wanderwege bergauf egal | 1,49 | 1,58 | 4 | 47 / 5 / 7 / 30 % |
| steile Rampen egal | 1,51 | 1,58 | 4 | 48 / 7 / 4 / 31 % |
| alles egal | 1,56 | 1,52 | 3 | 39 / 19 / 2 / 30 % |

Die Vorgabe plant fast wie bisher (der Planer-Mix ist derselbe), die
Kurven verschieben die Wahl erst dort, wo es steil wird. Für diesen
Fahrer passt „Straßen egal" am besten; die Vorgabe bleibt „meiden",
weil 15 Fälle eines Fahrers keine Vorgabe für alle tragen.

Der Betreiber dazu: „Meine gefahrene Route ist ja auch nicht unbedingt
das Optimum." M4 fragt, ob der Planer DEN gefahrenen Weg findet; das
misst die Gewohnheit des Fahrers (Umwege, eine schönere Auffahrt, ein
Ziel vor dem Trail), nicht die Güte des Plans. Was die Messung zeigen
kann, zeigt sie: Der Plan ist nach dem Modell schneller und nicht
länger, und kein Aufschlag der Tabelle rückt ihn näher an die Fahrt.
Ob er sich fahren lässt, sagt der Feldtest (#188), nicht diese Zahl.

## #211 — Wege-Tags in DACH (gemessen 2026-10-08, lokal)

*Werkzeug `tool/way_tags.py` (Selbsttest in CI), lokal gefahren
(Betreiber, 2026-10-07: Geofabrik ist aus der Cloud gesperrt, jeder
CI-Lauf wären 4 GB Download). Geofabrik-Auszüge vom 2026-10-07: DE, AT,
CH, LI, IT-Nordost; Grundkarte `dach-20261001.pmtiles`, Höhen
`heights-20261001.pmtiles` vom eigenen Host. Vier 20-km-Rahmen:
Schwarzwald, Harz, Tirol, Berner Oberland. Die Auszüge überlappen an den
Grenzen um wenige Kilometer; für Anteile spielt das keine Rolle.*

### Ergebnis

1. **Die Wegqualität der Forstwege ist da, die Schwierigkeit der Pfade
   nicht.** `tracktype` trägt 83 % der Forstweg-Länge (DE 86, AT 78,
   CH 83, IT-NO 55 %), in der Hälfte der 0,5°-Zellen 72–89 %. Auf Pfaden
   trägt `sac_scale` 22 % (DE 8, AT 46, CH 36 %) und `mtb:scale` 10 %;
   in der mittleren Zelle 6 bzw. 7 %. `smoothness` ist überall dünn
   (Forstweg 8 %, Pfad 11 %).
2. **Der Abgleich gelingt über die Geometrie**: Die Pfad- und
   Forstweglinien der Grundkarte finden zu 97–100 % schon innerhalb 3 m
   einen OSM-Weg derselben Klasse, 99–100 % der Graphkanten (80 % ihrer
   Länge im Korridor). Beide stammen aus demselben OSM; 8 m bringen
   nichts dazu. Umgekehrt fehlen der Karte vor allem städtische
   Fußwege (Tirol 62 %, Gehsteige). **Der Graph bleibt der der
   Grundkarte; die Tags kommen per Geometrie dazu.**
3. **Größe**: Ein z13-Archiv nur der getaggten Wege (Tags als kleine
   Zahlen, Geometrie auf 1 Kacheleinheit vereinfacht) kostet je Rahmen
   das 0,6- bis 2,1-Fache der Höhenkacheln desselben Rahmens, für DACH
   hochgerechnet **rund 200 MiB** (über das Verhältnis zu den 140 MiB
   Höhen 207 MiB, über Bytes je Weg-km 195 MiB). Alle Wege mit Klasse
   (Variante b) wären nur 10–45 % mehr — wird nicht gebraucht, siehe 2.
4. **Für #212**: trägt — Forstweg-Güte auf der Karte ist in DACH flächig
   möglich; die Wegschwierigkeit nur dort, wo gemappt (Alpen ja,
   Mittelgebirge kaum). Das Archiv ist größer als die Höhen; vor dem Bau
   prüfen, was es kleiner macht (nur `tracktype`/`sac_scale`/`mtb:scale`,
   gröbere Vereinfachung, z12). **Für #213**: Forstweg nach `tracktype`
   zu bepreisen trägt; auf Pfaden ist „unbekannt" der Normalfall und
   muss den heutigen Preis behalten.

### Abdeckung (Anteil der Länge)

| Wegart | km (alle) | Tag | DE | AT | CH | IT-NO | alle |
|---|---:|---|---:|---:|---:|---:|---:|
| track | 1 632 026 | tracktype | 86 % | 78 % | 83 % | 55 % | 83 % |
| | | surface | 53 % | 25 % | 36 % | 35 % | 47 % |
| | | smoothness | 10 % | 3 % | 4 % | 6 % | 8 % |
| path | 433 761 | sac_scale | 8 % | 46 % | 36 % | 45 % | 22 % |
| | | mtb:scale | 9 % | 8 % | 12 % | 18 % | 10 % |
| | | mtb:scale:uphill | 2 % | 3 % | 3 % | 5 % | 2 % |
| | | trail_visibility | 10 % | 29 % | 14 % | 27 % | 15 % |
| | | surface | 72 % | 37 % | 32 % | 36 % | 57 % |
| footway | 185 889 | surface | 64 % | 59 % | 51 % | 47 % | 61 % |
| cycleway | 29 977 | surface | 87 % | 85 % | 83 % | 70 % | 81 % |
| steps | 5 094 | surface | 56 % | 47 % | 39 % | 36 % | 51 % |

`bridleway` (3 235 km) trägt fast nur `surface`; `sac_scale` und
`mtb:scale` auf Fußwegen sind 0 %.

### Werte (Anteil der getaggten Länge)

- `tracktype`: grade1 14 %, grade2 29 %, grade3 27 %, grade4 18 %,
  grade5 13 % — fast ein Drittel der getaggten Forstwege ist grade4/5.
- `sac_scale` auf Pfaden: T1 34 %, T2 46 %, T3 12 %, T4–T6 7 %.
- `mtb:scale` auf Pfaden: 0 26 %, 1 38 %, 2 23 %, 3 9 %, 4–6 5 %;
  `:uphill` 0–5 fast gleich verteilt (11 000 km).
- `smoothness` auf Forstwegen: bad und schlechter 60 %.
- `surface` auf Forstwegen: natürlich 39 %, Schotter 25 %, befestigt
  19 %, verdichtet 17 %.

### Größe je Rahmen (z13, gzip)

| Rahmen | Weg-km | nur getaggt | alle Wege | Höhen | getaggt / Höhen |
|---|---:|---:|---:|---:|---:|
| Schwarzwald | 2 839 | 221 KiB | 248 KiB | 137 KiB | 161 % |
| Harz | 1 962 | 175 KiB | 192 KiB | 110 KiB | 158 % |
| Tirol | 2 658 | 264 KiB | 320 KiB | 124 KiB | 212 % |
| Berner Oberland | 1 034 | 82 KiB | 121 KiB | 130 KiB | 63 % |

Die Höhen zählen die ganzen Randkacheln, die Wege nur bis zum Rahmen;
das Verhältnis ist also eher etwas zu klein als zu groß.

## #212 — Das Wege-Archiv, kleiner gemacht (gemessen 2026-10-08, lokal)

*`tool/way_archive.py build` auf denselben Auszügen wie #211 (DE, AT, CH,
LI, IT-Nordost), ganze Länder statt Rahmen. Gebaut wird später von
`way-data.yml` über die ganze Box der Karte, mit denselben Auszügen wie
die Orte.*

Was #211 „vor dem Bau prüfen" verlangte, ist umgesetzt: Nur Wege mit
Güte, und von den Tags nur EINE Zahl, die Klasse (Forstweg gut/mittel/
schlecht aus `tracktype`, Pfad leicht/mittel/schwer aus `mtb:scale`,
sonst `sac_scale`). Damit ist je Kachel und Klasse ein Objekt übrig, und
die Variante aus #211 (rund 200 MiB) schrumpft auf weniger als die Hälfte:

| Variante | Größe | Kacheln | Punkte | Anteil an den Höhen |
|---|---:|---:|---:|---:|
| z13, Vereinfachung 1,5 Einheiten (≈ 1,8 m) | 92,3 MB | 53 615 | 37,3 Mio. | 63 % |
| z13, Vereinfachung 3 Einheiten (≈ 3,6 m) | 80,8 MB | 53 615 | 29,6 Mio. | 55 % |
| z12, Vereinfachung 1,5 Einheiten (≈ 2,4 m) | 65,6 MB | 13 779 | 29,0 Mio. | 45 % |

4,19 Mio. Wege mit Güte, 77 000 mit einem Wert, der keiner ist; knapp
5 Minuten, 2,2 GB Speicher. Höhen zum Vergleich: 146,8 MB für die ganze
Box (95 494 Kacheln).

**Gewählt: z13 mit 1,5.** Dieselbe Zoomstufe wie Höhen, Bereichsform und
Straßengraph — #213 hängt die Güte Kachel für Kachel an die Kanten. Die
gröbere Vereinfachung spart 12 %, läge aber mit 3,6 m außerhalb des
3-m-Korridors, in dem #211 die Grundkarte gefunden hat. z12 spart mehr,
lädt aber bei einem schmalen Bereich entlang der Trails die vierfache
Fläche mit. Mit den Nachbarländern der Box wird es mehr; `way-data.yml`
veröffentlicht nichts, was größer ist als die Höhen.

**Format 2 (#213, 2026-10-08, lokal auf denselben Auszügen):** dazu
„Forstweg sehr schlecht" (grade5, `smoothness` ab bad, `surface=mud`),
„Pfad sehr schwer" (ab S4/T4) und `mtb:scale:uphill` als zweite Zahl an
Pfaden. 4,19 Mio. Wege mit Güte (+4 300), **93,2 MB** (+1 %), 53 620
Kacheln. Von 200 zufällig gelesenen Kacheln tragen 179 die Klasse 7
(grade4: 177, Pfad sehr schwer: 15) — grade5 und holprige Forstwege
sind also kein Randfall.

## Was aus dem Werkzeug bleibt

- Der MVT-Decoder, der COG-Leser, Klassentabelle, Zeitmodell, Graph
  (Zuschnitt, Verbindung, Kreuzungen), Dijkstra und A* sind die Referenz
  für die Dart-Engine (Schritt 3); Werkzeug und Dart ändern sich im
  selben PR, wie bei `trail_match.py`.
- Vier CI-Läufe bis zum Ergebnis: Lauf 1 hing in einer O(N·E)-Suche
  (Zellenraster seither), Lauf 3 zeigte den Verbindungs-Fehler, Lauf 4
  ist dieser Bericht. Die Reihenfolge steht hier, damit die nächste
  Messung nicht dieselben Umwege geht.

## #213 — Wegegüte im Routing (gemessen 2026-10-08, lokal)

*`tool/route_measure.py ways` an 30 Fahrten des Betreibers aus Strava
(Betreiber, 2026-10-08: „Nutze Strava MCP, da hast du Fahrten und die
sind gelabelt"; die 47 Fahrten von #188 lagen nicht mehr vor): 21 mit
`MountainBikeRide`, 9 mit `EMountainBikeRide`/`EBikeRide`, 2022–2026,
je mindestens 250 hm und rund 15 hm/km — die flachen Pendelfahrten sagen
über Anstiege nichts. Kacheln `dach-20261001.pmtiles` vom Host, Wege-Archiv
Format 2 aus dem lokalen Bau (93,2 MB), Trails der Sammlung (584). Die
Fahrten lagen nur auf dem Rechner des Laufs; hier stehen Kennzahlen,
keine Orte.*

Drei Viertel der Forstweg- und Pfadkanten in den Rahmen tragen eine
Klasse (Bio 76 %).

### Wie die Aufstiege fahren

Länge der Aufstiege (≥ 100 hm am Stück) je Weg, gegen die Länge des
Netzes in denselben Rahmen:

| Weg | Bio: Aufstiege / Netz | E: Aufstiege / Netz |
|---|---:|---:|
| Forstweg gut | 53 % / 28 % | 53 % / 26 % |
| Forstweg mittel | 2 % / 6 % | 3 % / 5 % |
| Forstweg schlecht | 0 % / 9 % | 1 % / 10 % |
| Forstweg sehr schlecht | 3 % / 10 % | 2 % / 9 % |
| Pfad leicht | 4 % / 2 % | 3 % / 2 % |
| Pfad mittel, schwer, sehr schwer | 0 % / 0 % | 0 % / 1 % |
| Pfad ohne Schwierigkeit | 8 % / 6 % | 3 % / 6 % |
| Straßen, Radwege, Rest | 24 % / 39 % | 29 % / 40 % |

**Der Fahrer meidet schlechte Forstwege bergauf**: Sie sind ein Fünftel
des Netzes und tragen 3 % der Aufstiege; gute Forstwege doppelt so viel,
wie ihr Anteil am Netz erwarten ließe. Schwere Pfade kommen in diesen
Gegenden kaum vor (keine `sac_scale` im Mittelgebirge, #211) — dazu
sagt die Messung nichts, der Preis dort ist gesetzt.

### Kosten gefahren / geplant

Wie bei den Strafkurven (0.81.0): Fahrtstart → erster bekannter
Trailkopf, die Fahrt auf dem Graphen gegen den Plan, je Variante; dazu
der Anteil schlechter und sehr schlechter Forstwege an der Länge, die
der Plan bergauf fährt.

| Variante | Bio (17 Fälle): Median / Plan anders / schlecht bergauf | E (7 Fälle) |
|---|---|---|
| ohne Wegegüte (bis 0.91) | 1,37 / – / 8 % | 1,30 / – / 10 % |
| **Vorschlag (gebaut)** | **1,36 / 10 / 4 %** | **1,28 / 3 / 4 %** |
| sehr schlecht ×1,5 (schlecht ×1,15) | 1,33 / 8 / 4 % | 1,29 / 3 / 4 % |
| sehr schlecht ×3 (schlecht ×1,6) | 1,43 / 11 / 3 % | 1,27 / 3 / 4 % |
| nur Forstwege, Pfade ohne Aufschlag | 1,36 / 10 / 4 % | 1,28 / 3 / 4 % |
| Pfade doppelt geschoben | 1,36 / 10 / 4 % | 1,28 / 3 / 4 % |

Gefahren: schlecht + sehr schlecht bergauf Bio 8 %, E 3 % dieser Fälle.

**Gebaut: der Vorschlag** (Steigteil ×2 und Strecke ×1,3 auf sehr
schlechten, ×1,3 und ×1,15 auf schlechten Forstwegen; Pfade ab S3/T3
geschoben, ab S4/T4 doppelt; `mtb:scale:uphill` vor der Klasse). Er
halbiert die schlechten Forstwege im Plan, auf den Anteil, den der
Fahrer selbst fährt, und lässt die Kosten der Fahrt gegen den Plan, wie
sie waren — die Wegegüte ändert, WELCHER Forstweg hinaufführt, nicht
den Umweg, den M4 seit #188 zeigt. ×3 wird bei Bio schlechter (1,43),
×1,5 ändert weniger Pläne. Die Pfad-Varianten unterscheiden sich hier
nicht, weil die Pfade dieser Fahrten ungetaggt sind.
