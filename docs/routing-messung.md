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

## #329 — Der Stil „Bequem" (gemessen 2026-10-16, lokal, öffentliche Daten)

*`tool/route_measure.py tirol --frames 3` (Kacheln vom eigenen Host, Höhen
Copernicus GLO-90, Profil Bio, ohne Wege-Archiv), Abschnitt „Bequem gegen
MTB": vom Ende eines Trails zum Anfang eines anderen, Luftlinie etwa 1, 2
und 4 km (±50 %) — Ersatz für „von hier zum Trailkopf". 45, 54 und 57
Paare; je Paar dieselbe Suche im MTB-Stil und im Stil „Bequem".
Varianten über die Werte `EASY_CLIMB` (Steigaufschlag) und `EASY_STEEP`
(Steilfaktor auf Asphalt mindestens).*

| Stil | Asphalt 1 / 2 / 4 km | Höhenmeter gegen MTB | Steilmeter gegen MTB | längster Umweg |
|---|---|---|---|---|
| MTB (Vergleich) | 40 / 51 / 57 % | — | — | — |
| 0,5 / Asphalt ×1 (erster Entwurf) | 48 / 60 / 67 % | −0,5 / +2,9 / +0,4 % | +1 / +9 / +6 % | 126 % |
| 0,5 / ×3 | 42 / 59 / 64 % | −0,1 / +2,6 / +0,7 % | −6 / +8 / 0 % | 126 % |
| 1,0 / ×1 | 45 / 59 / 68 % | −2,2 / +2,2 / +0,2 % | +1 / +9 / +6 % | 126 % |
| 1,0 / ×3 | 43 / 59 / 65 % | −2,7 / +2,2 / −0,6 % | −6 / +8 / −1 % | 126 % |
| **1,5 / ×3 (gebaut)** | **41 / 56 / 66 %** | **−3,7 / −0,7 / −0,8 %** | **−6 / +7 / −1 %** | **38 %** |

Pfade (Wanderweg, Fußweg, Stufen) gebaut 10 / 8 / 5 % statt 11 / 12 / 7 %;
die Modellzeit sinkt in allen drei Gruppen um 1–4 %. Der Weg ändert sich
bei 19 / 22 / 44 Paaren, im Median 0 % länger.

**Gebaut: 1,5 mit Steilfaktor 3.** Der erste Entwurf nahm mehr Asphalt,
stieg aber MEHR: Eine steile Straße kostete nur ein Drittel einer
steilen Schotterrampe und war der billige Weg um einen Pfad herum. Erst
mit 1,5 und ×3 steigt der Stil in allen drei Entfernungen weniger als der
MTB-Stil und nimmt trotzdem mehr Asphalt; der längste Umweg sinkt von
126 % auf 38 %. Ehrlich: Die Verschiebung ist klein, weil diese Paare
Bergaufstiege zwischen Trails sind und dort selten eine zweite Straße
liegt — die Anfahrt aus dem Tal, für die der Stil gedacht ist, misst erst
das Gerät. Die steilen Meter bei 2 km bleiben +7 %: Wo der Stil einem
Wanderweg ausweicht, liegt die Ausweichstraße oft an derselben Flanke.

### An eigenen Anfahrten (gemessen 2026-10-16, lokal)

*`tool/route_measure.py rides` an den 30 Strava-Fahrten von #213
(Betreiber, 2026-10-16: „Passt"), Trails der Sammlung (584), Kacheln
vom Host, Höhen Copernicus GLO-90. Dieselben Fälle wie M4: Fahrtstart →
erster bekannter Trailkopf, die Fahrt auf den Graphen gelegt, dazu
beide Stile für dieselben Endpunkte. Die Fahrten lagen nur auf dem
Rechner des Laufs; hier stehen Kennzahlen, keine Orte.*

| Gruppe | Weg | Länge | Asphalt | Forstweg | Pfad | bergauf | steil |
|---|---|---|---|---|---|---|---|
| Bio (17) | gefahren | 138,6 km | 32 % | 54 % | 14 % | 3975 hm | 62 hm |
| | MTB | 124,9 km | 22 % | 76 % | 2 % | 3341 hm | 13 hm |
| | **Bequem** | 129,3 km | **33 %** | 66 % | 1 % | 3366 hm | 10 hm |
| E-MTB (7) | gefahren | 39,5 km | 34 % | 56 % | 10 % | 1233 hm | 20 hm |
| | MTB | 39,9 km | 24 % | 75 % | 1 % | 1006 hm | 2 hm |
| | **Bequem** | 39,6 km | **45 %** | 54 % | 1 % | 994 hm | 2 hm |

**Die Werte bleiben.** Der Betreiber fährt zum ersten Trail zu einem
Drittel auf Asphalt; der MTB-Stil plant ein Viertel weniger davon, der
Stil „Bequem" trifft das Drittel beim Bio-Rad fast genau und liegt beim
E-MTB darüber — ohne mehr zu steigen (Bio +0,7 %, E −1 % gegen MTB) und
mit weniger steilen Metern. Beide Pläne steigen 15–20 % weniger als die
Fahrten, und keiner trifft den gefahrenen Weg (2 von 17, 0 von 7 gleich
bei 15 m und 0,8 beidseitig): Die Fahrten sind keine kürzesten
Anfahrten — Umwege, Pfade, die man schon als Teil der Runde fährt
(14 % Pfad gefahren gegen 1–2 % geplant). Wer näher an die gefahrenen
Höhenmeter kommt, ist deshalb kein Maß (Bequem 3 von 17 bzw. 2 von 7).
Ehrlich: Die Fahrten waren MTB-Runden, keine bewusst bequemen
Anfahrten; was der Stil im Tal tut, sieht weiter erst das Gerät.

## #356 — Werkzeug für die Abnahme, und was der Rechner schon zeigt (2026-10-17)

Vor der Freigabe 🚀 A soll die Routenplanung die Oberfläche nie
anhalten (Konzept-Routing 10.6/10.7). Gemessen wird das am Pixel des
Betreibers mit der Dev-App (`android/CLAUDE.md`) und dem Stall-Wächter
(`lib/core/stall_watch.dart`, `lib/core/CLAUDE.md`). Hier stehen das
Verfahren, die Zahlen vom Rechner und die Tabelle für das Gerät.

### Am Rechner: das Skript mit Kreuzungen

`test/routing/perf_loop_planner_measure.dart` baut seit #356 wie die App
mit Kreuzungsteilung; eine dritte Schar Nebenstraßen liegt eine halbe
Masche versetzt, damit `findCrossings` wirklich teilt (vorher
`splitCrossings: false` — #354 war so nie gemessen). Gitter 25 × 25 km,
JIT, alle Zeiten in ms, Spalten wie bei #188/0.80.2:

| Trails | Budget | Kanten | Kreuzungen | Graph bauen | Trails auflegen | an Ort und Stelle | Isolate, 1. Rechnung: Dauer / Pause | dieselbe noch einmal | ein Trail weniger | Halte |
|---|---|---|---|---|---|---|---|---|---|---|
| 12 | Bio 3 h / 1 000 hm | 62 625 | 15 500 | 1 472 | 33 | 275 | 2 128 / 1 798 | 0 / 0 | 0 / 0 | 2 |
| 30 | Bio 3 h / 1 000 hm | 62 625 | 15 500 | 1 427 | 34 | 544 | 2 402 / 1 785 | 1 / 1 | 1 / 1 | 2 |
| 40 | Bio 5 h / 1 600 hm | 62 625 | 15 500 | 1 445 | 36 | 1 444 | 3 153 / 1 786 | 2 / 2 | 1 / 1 | 4 |
| 60 | E-Bike 5 h / 2 500 hm | 62 625 | 15 500 | 1 501 | 50 | 2 177 | 4 118 / 1 803 | 8 / 5 | 13 / 5 | 8 |

Zwei Befunde, beide schon ohne Gerät:

1. **Das Senden des Graphen ist jetzt die längste Pause**: 1,8 s im
   UI-Isolate bei 62 600 Kanten (0.80.1: ~0,3 s bei 31 500). Die Pause
   wächst mit dem Graphen, nicht mit der Auswahl — genau die Lücke, die
   #356 PR 8 schließt (Graph im Isolate bauen, nichts senden).
2. **Der Bau selbst liegt bei ~1,5 s** auf dem Rechner, davon der größte
   Teil in den 15 500 Teilungen; auf dem Telefon ein Vielfaches, im
   UI-Isolate. Ein echter z13-Rahmen hat weniger Kreuzungen ohne Knoten
   als dieses Gitter (jede Masche zweimal); die Zahl für das Gerät kommt
   aus der Tabelle unten.

**Der Fall aus #354 ist im JIT nicht zu sehen.** Mit dem verschachtelten
Record-Schlüssel baute das 15-km-Gitter in 497 statt 470 ms; langsam war
er nur im AOT-Build (VM-Typprüfung). Der CI-Test
(`test/routing/graph_build_budget_test.dart`, relativ zu einer
Vergleichsarbeit, rot erst über 15-fach UND 20 s) fängt deshalb nur, was
überall langsam ist — Gegenprobe: `findCrossings` ohne Gitter (alle Paare)
22 s, 57,7-fach, rot. Den AOT-Fall sieht nur der Wächter am Gerät.

### Am Gerät: Verfahren

```
flutter build apk --release --flavor dev --target-platform android-arm64 \
  --dart-define=STALL_WATCH=true
flutter install --flavor dev
adb logcat -c && adb logcat -s flutter | grep TB-
adb shell dumpsys meminfo de.mcbuchi.trailbuddy.dev | grep TOTAL   # vor und nach
```

Je Szenario: die `TB-TIME`-Zeile des Schritts, die längste
`TB-STALL gap` samt Marken, `TOTAL PSS` vorher/nachher, und die Kacheln
aus dem Blatt („x von y Kacheln"). Ein gespeicherter Bereich um die
Gegend, Online-Ergänzung aus (Parameter des Planers), damit das Netz
nicht mitmisst; danach Szenario 2 einmal mit Empfang. Keine Orte in
diesen Bericht — nur Kennzahlen.

| # | Szenario | `TB-TIME` | längste Lücke [Marken] | PSS vorher → nachher | Kacheln |
|---|---|---|---|---|---|
| 1 | Kaltstart bis Karte ruhig (Grundrauschen) | – (Activity 550 ms) | 114 ms | – → 223 MB | – |
| 2 | Planer: erste Runde, dichte Gegend, 12 Trails, Radius 12 km | `graph.load` 99 ms, `graph.build` 13,3 s, `plan.loop` 7,2 s | 137 ms | 590 → 663 MB | 24 |
| 2′ | wie 2, aber 54 Trails | `graph.build` 12,3 s, `plan.loop` 32,3 s | 317 ms [nach dem Ergebnis] | 592 → 989 MB | 24 |
| 3 | dieselbe, ein Trail abgewählt („Neu rechnen") | `plan.loop` 734 ms | 154 ms | 904 → 945 MB | 24 |
| 4 | Planer: Radius 30 km, 97 Trails (großer Rahmen) | `graph.load` 389–473 ms, `graph.build` 41–44 s, `plan.loop` 94–114 s | 433–521 ms [`graph.load`] | 664 → 1 626 MB, 981 → 1 757 MB | 117 von 120 |
| 5 | „Zum Trailkopf" direkt, kurz | `graph.load` 41 ms, `graph.build` 5,0 s | keine ≥ 100 ms [`route.direct` 138 ms] | 686 → 596 MB | 6 |
| 6 | dasselbe spaßig | – | keine ≥ 100 ms [`route.fun` 263 ms] | ~594 MB | 6 |
| 7 | dasselbe bequem | – | keine ≥ 100 ms [`route.direct` 170 ms] | ~590 MB | 6 |
| 8 | Navigation abseits, „Zurück zur Route" | nicht gemessen | | | |
| 9 | „Aus meinen Fahrten lernen", ≥ 20 Fahrten | nicht gemessen (Testkonto ohne Fahrten) | | | |

Gemessen 2026-10-18 am Pixel XL (Android 10) mit 0.131.2-dev, ein
gespeicherter Bereich, Online-Ergänzung aus. Kein ANR, kein Absturz,
auch nicht in Szenario 4. `graph.build` ist die Summe der Teilmarken im
Rechen-Isolate (in 2′: decode 0,7 · nodes 1,2 · joins 2,3 · crossings
3,1 · climbs 1,1 · wayQuality 3,4 · trails 0,4 s; in 4 allein wayQuality
15,5–17 s). Die Kachelzahl stammt aus einer Zusatzzeile `TB-INFO
graph.tiles` des Wächters. Szenario 5 lief mit einer Route von gut 1 km
statt 5 km: Auf eine Straße setzen ließ sich der Start per adb nur im
eng gezoomten Ausschnitt.

**Befunde am Gerät:**

1. **Der Bau kostet auf diesem Gerät ~0,33 s je Kachel** (6 Kacheln 5 s,
   24 Kacheln 12–13 s, 72 Kacheln 23 s, 120 Kacheln 41–44 s). Das Budget
   „erste Runde < 5 s" hält damit nur ein Rahmen von etwa 8–15 Kacheln —
   kleiner als jede echte Runde mit Radius 12 km. Die Oberfläche steht
   dabei nicht; es ist nur die Wartezeit.
2. **Die längsten Lücken im UI-Isolate** liegen bis 24 Kacheln bei
   114–154 ms, mit vielen Trails nach dem Ergebnis bei 317 ms und beim
   Lesen von 120 Kacheln (`graph.load`) bei 433–521 ms. Das Budget
   „≤ 200 ms" reißt also erst der große Rahmen und das Zeichnen großer
   Ergebnisse.
3. **Der Speicher reißt das Budget „+300 MB"**: 24 Kacheln mit 54 Trails
   +400 MB, 120 Kacheln +780 bis +960 MB.
4. **Rechnen nach dem Bau ist schnell**: ein Trail weniger 0,7 s, Routen
   direkt/spaßig/bequem 0,14–0,26 s, alles im Budget.
5. **72 Kacheln waren kein „Gebiet zu groß"** (Route vom weit entfernten
   Gerätestandort zum Trailkopf, 23 s Bau), weil die Grenze noch bei 300
   steht.

**`kPlanMaxTiles`** (#356 PR 8) kommt aus 2 und 4: die Kachelzahl, bei
der `graph.load` + `graph.build` auf dem Pixel noch unter 5 s bleibt
(das Budget der ersten Runde), abgerundet; darüber sagt der Planer
„Gebiet zu groß". Bis zur Messung stand ein vorläufiger Wert von 300
(~55 × 55 km bei 47° N) in `road_graph_loader.dart`.
Szenario 4 darf das Budget reißen — es ist die Messung der Grenze.
**Stand 2026-10-18:** Die Messung oben gibt für 5 s nur 8–15 Kacheln
her; das hätte den Planer auf diesem Gerät praktisch abgeschaltet. Der
Betreiber hat entschieden: „Wenn es einen Ladebalken gibt, ist eine
längere Berechnungsdauer ok." Seit 0.132.0 melden Bau und Runde ihren
Fortschritt, und die Grenze kommt vom Speicher: **`kPlanMaxTiles` = 120**,
die größte gemessene Zahl, die ohne Absturz lief (117 Kacheln, bis
1,76 GB). 300 Kacheln hätten nach derselben Steigung weit über 2 GB
gebraucht.

### Am Rechner, nach PR 8: der Bau drüben (2026-10-18)

Seit 0.131.1 schickt der UI-Isolate nur noch Bytes (Kacheln, Höhenraster,
Trails — `GraphInput`), der Rechen-Isolate dekodiert und baut
(`buildGraphFrom`). Dasselbe Skript, dasselbe Gitter, jetzt als z13-Kacheln
kodiert (`test/fakes/graph_tiles.dart`); JIT, Zeiten in ms. „An Ort und
Stelle" ist der Bau samt Dekodieren im UI-Isolate — was die Oberfläche
bis 0.131.0 stand —, „Bau drüben" Dauer / längste Pause des UI-Takts (die
Pause ist das Senden der Bytes):

| Trails | Budget | Kanten | Kreuzungen | Bytes | an Ort und Stelle: bauen | an Ort und Stelle: rechnen | Bau drüben: Dauer / Pause | 1. Rechnung: Dauer / Pause | dieselbe noch einmal | ein Trail weniger | Halte |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 12 | Bio 3 h / 1 000 hm | 65 390 | 15 500 | 544 KB | 570 | 221 | 541 / 23 | 163 / 5 | 0 / 0 | 0 / 0 | 1 |
| 30 | Bio 3 h / 1 000 hm | 65 390 | 15 500 | 544 KB | 467 | 421 | 514 / 25 | 367 / 7 | 0 / 0 | 0 / 0 | 1 |
| 40 | Bio 5 h / 1 600 hm | 65 390 | 15 500 | 544 KB | 480 | 1 306 | 488 / 25 | 1 283 / 22 | 2 / 2 | 1 / 1 | 4 |
| 60 | E-Bike 5 h / 2 500 hm | 65 390 | 15 500 | 544 KB | 490 | 2 537 | 520 / 13 | 3 082 / 29 | 9 / 5 | 10 / 5 | 8 |

Drei Befunde:

1. **Die längste Pause im UI-Isolate ist von 1,8 s auf ~25 ms gefallen**
   (Bau drüben, Spalte „Pause"): 544 KB Bytes zu senden kostet nichts
   Sichtbares; der Graph mit seinen 65 000 Kanten wird nie mehr kopiert.
   Die Pausen der Rechnungen sind unverändert (5–29 ms).
2. **Der Bau selbst ist nicht teurer geworden** (~0,5 s drüben wie an Ort
   und Stelle, Dekodieren der Kacheln eingeschlossen) — er liegt nur
   woanders. Was er auf dem Pixel im AOT-Build kostet (#354), misst
   Szenario 2/4; die Grenze `kPlanMaxTiles` kommt von dort.
3. **Die Kanten sind 65 390 statt 62 625**: Das Gitter liegt jetzt in
   Kacheln, und der Zuschnitt auf den Kachelrahmen teilt jede Linie an
   jeder Kachelgrenze — wie im echten Archiv. Die Halte und Minuten der
   Pläne sind davon unberührt.


## #376 — Der Suchspeicher, kompakt (gemessen 2026-10-18, am Rechner)

Am Pixel wuchs der zusätzliche Speicher mit der Zahl der Trails, nicht
nur mit dem Rahmen (24 Kacheln: 12 Trails +73 MB, 54 Trails +400 MB).
Die Ursache war `LoopSearchCache`: Er behält je Startknoten (Start und
jedes Trail-Ende, dazu manchmal die Fassung ohne Wanderweg) die ganze
begrenzte Suche, und die lag in drei Hash-Maps über jeden erreichten
Knoten (Kosten, Anstieg, Vorgänger als Record), rund 100 Byte je Knoten.
Bei 3–5 h Budget erreicht jede Suche fast den ganzen Rahmen.

Seit 0.133.2 hält `SearchResult` drei Felder nur über die erreichten
Knoten (Kennung, Kosten, Vorgängerkante; 16 Byte je Knoten, binär
gesucht); den Anstieg rechnet `climbTo` aus dem Pfad. Während der Suche
gibt es Felder über den ganzen Graphen, aber nur für die eine Suche, die
gerade läuft.

`perf_loop_planner_measure.dart` zeigt jetzt die gelaufenen Suchen, die
gemerkten Knoten, die Verbindungen samt Linienpunkten und den Zuwachs
des RSS während der ersten Rechnung an Ort und Stelle (der Prozess als
Ganzes, mit GC also ungenau, aber in der Größenordnung). Dasselbe Gitter
wie oben, JIT, Zeiten in ms:

| Trails | Suchen | gemerkte Knoten | Verbindungen / Punkte | RSS vorher | RSS nachher | rechnen vorher | rechnen nachher | 1. Rechnung drüben vorher | nachher |
|---|---|---|---|---|---|---|---|---|---|
| 12 | 12 | 171 322 | 46 / 1 965 | +25 MB | +8 MB | 307 | 148 | 512 | 121 |
| 30 | 28 | 353 885 | 113 / 5 315 | +10 MB | +14 MB | 956 | 236 | 781 | 241 |
| 40 | 41 | 1 102 711 | 385 / 38 964 | +185 MB | +20 MB | 2 261 | 792 | 1 561 | 803 |
| 60 | 60 | 2 016 633 | 1 110 / 116 699 | +401 MB | +48 MB | 2 851 | 1 387 | 4 770 | 1 334 |

Die Pläne sind identisch: dieselben Trails in derselben Reihenfolge,
Zeit, Anstieg und Länge auf die letzte Stelle gleich (beide Fassungen
nacheinander gerechnet und verglichen). Die Verbindungen samt Linien
(höchstens 117 000 Punkte, wenige MB) bleiben gemerkt; sie sind nicht der
Speicherfresser. Schneller ist es nebenbei auch geworden, weil Felder
billiger sind als Hash-Maps. Am Gerät steht noch aus: PSS in den
Szenarien 2′ und 4 (#376).

## #379 — Kantenkosten einmal je Plan (gemessen 2026-10-18, am Rechner)

Jede Suche des Planers rechnete die Kosten jeder Kante bei jedem Schritt
neu aus dem Profil (`edgeCostFrom`: Klasse, Steigzeit, Steilaufschlag,
Wegegüte, Vorlieben). Das Profil steht für eine Rechnung fest, und der
Planer sucht je Trail-Ende über den halben Rahmen. Seit 0.133.3 rechnet
`EdgeCosts` die Kosten jeder Kante in beiden Richtungen einmal in ein
Feld (zwei Zahlen je Kante, bei 65 000 Kanten rund 1 MB); es hängt am
Suchspeicher und gilt wie er nur für denselben Stand des Graphen.

Dasselbe Skript, je zwei Läufe, Zeiten in ms (JIT):

| Trails | rechnen an Ort und Stelle vorher | nachher | 1. Rechnung drüben vorher | nachher |
|---|---|---|---|---|
| 12 | 143–153 | 90–93 | 98–108 | 64–70 |
| 30 | 194–212 | 120–136 | 199–208 | 115–121 |
| 40 | 662–697 | 379–384 | 685–731 | 392–413 |
| 60 | 1 219–1 224 | 702–725 | 1 198–1 277 | 713–724 |

Etwa 40 % weniger für die erste Rechnung; die gemerkten Suchen danach
waren schon schnell und bleiben es. Die Pläne sind identisch (Trails,
Reihenfolge, Zeit, Anstieg, Länge auf die letzte Stelle), weil dieselbe
Funktion dieselben Zahlen liefert, nur früher.

## #377 — Suchen beim letzten Trailkopf anhalten (gemessen 2026-10-18, am Rechner; nicht gebaut)

Die Annahme des Issues: Jede Suche des Planers (eine vom Start, eine je
Trail-Ende) läuft über den ganzen Rahmen, gebraucht werden nur die
Kosten zu den Trailköpfen und zum Ziel. Gebaut zur Probe:
`dijkstra(targets:)` hält an, sobald jeder Kopf und das Ziel fest sind,
das Ergebnis behält nur die festen Knoten; der Suchspeicher merkt sich
die Ziele je Suche und sucht neu, wenn eine spätere Auswahl neue Köpfe
fragt. Die Pläne blieben identisch.

`perf_loop_planner_measure.dart`, je zwei Läufe, Zeiten in ms (JIT):

| Trails | gemerkte Knoten vorher | nachher | 1. Rechnung drüben vorher | nachher |
|---|---|---|---|---|
| 12 | 171 322 | 171 322 | 61–72 | 76 |
| 30 | 353 885 | 353 885 | 131–133 | 152–160 |
| 40 | 1 102 711 | 1 094 782 | 359–397 | 466–473 |
| 60 | 2 016 633 | 1 862 109 | 719–842 | 810–837 |

Kein Gewinn. Gezählt im Lauf mit 60 Trails: Von 141 Suchen hielten
nur 58 vorzeitig an. Die übrigen endeten schon an der Kostengrenze
(das Zeitbudget in Kosten-Einheiten, Konzept-Routing 3.1) — mindestens
ein Kopf liegt jenseits davon und gilt als nicht erreichbar, also läuft
die Suche bis an die Grenze, nicht an den Rand des Rahmens. Und wo sie
anhält, liegt der fernste Kopf fast an der Grenze. Die Suchen sind
schon heute durch das Budget begrenzt, nicht durch den Rahmen.

Verworfen (Betreiber, 2026-10-18). Eine engere Grenze je Suche aus dem
Restbudget (Budget minus Kosten vom Start bis zum Trail-Ende) würde
mehr sparen, ändert aber Pläne, weil Kosten und Zeit nicht gleich
zählen (Verbinder ×0,8) — das wäre eine eigene Entscheidung. Der Hebel
bleibt die Struktur: #378 (Graph in typisierten Feldern) und #380
(vorgerechnete Routing-Kacheln).

## #378 — Der Graph in typisierten Feldern, Schritt 1: das Gitter (gemessen 2026-10-18, am Rechner)

Vor dem Umbau gemessen, wo der Speicher eines gebauten Graphen liegt —
mit `perf_graph_memory_measure.dart` (neu; Heap nach GC über den
VM-Service, `flutter test --enable-vmservice`, der RSS schwankt dafür zu
stark). Dasselbe Gitter wie oben, 34 391 Knoten, 65 390 Kanten,
146 155 Linienpunkte:

| Klasse | vorher | nachher |
|---|---|---|
| Heap des Graphen | 94,1 MB | 53,9 MB |
| `_Record` | 35,1 MB (1 150 059) | 1,4 MB (44 979) |
| `_List` | 30,1 MB (296 709) | 14,1 MB (106 158) |
| `_GrowableList` | 8,9 MB (290 550) | 3,0 MB (99 786) |
| `_Int32List` | – | 15,3 MB (10) |
| `GraphEdge` | 11,0 MB | 11,0 MB |
| `LatLng` | 2,6 MB | 2,6 MB |

Der größte Posten waren nicht Kanten und Knoten, sondern das Gitter
über den Segmenten (`_segCells`, 50-m-Zellen): je Segment und Zelle ein
Record `(Kante, Segment)`, je Zelle eine Liste, je Zelle ein
Record-Schlüssel — gut 1 Mio. Records. Seit 0.133.4 hält `_CellGrid`
die Einträge in typisierten Feldern (je Zelle eine verkettete Liste in
Reihenfolge des Eintragens, die Zellen in Reihenfolge ihres ersten
Eintrags — wie die Hash-Map vorher), der Zellschlüssel ist eine Zahl
relativ zur ersten Zelle, damit er auf dem Telefon (31-Bit-Smi) kein
Objekt wird. Ebenso das Knotengitter. Der Knotenschlüssel (Mikrograd)
bleibt ein Record: Als eine Zahl bräuchte er rund 57 Bit, im Web sind
Zahlen nur bis 2^53 genau.

Weil Abfragen und `findCrossings` dieselben Kandidaten in derselben
Reihenfolge sehen, sind die Graphen und Pläne identisch:
`perf_loop_planner_measure.dart`, je zwei Läufe vorher und nachher mit
Fingerabdruck (Trails, Reihenfolge, Zeit, Anstieg, Länge, Kanten,
Kreuzungen) — gleich auf die letzte Stelle. Zeiten in ms (JIT):

| Trails | Bau an Ort und Stelle vorher | nachher | Bau drüben vorher (Dauer / Pause) | nachher |
|---|---|---|---|---|
| 12 | 540–545 | 477–498 | 538–543 / 23–24 | 434–435 / 10–11 |
| 30 | 438–445 | 383–387 | 492–501 / 23–27 | 377–382 / 9–10 |
| 40 | 429–489 | 383–389 | 525–603 / 26–31 | 391–396 / 7–11 |
| 60 | 461–485 | 398–420 | 509–514 / 23–25 | 402–404 / 10–12 |

Der Bau ist etwa 20 % schneller, und die längste Pause des UI-Takts
während des Baus drüben halbiert sich (weniger Müll im Heap, den sich
die Isolates einer Gruppe teilen). Die Rechnungen danach liegen im
Rauschen.

Was bleibt (nächste Schritte von #378): die Kanten als Objekte
(`GraphEdge`, 11 MB), ihre Linien als Listen von `LatLng` (`_List`,
`LatLng`) und die Nachbarlisten. Am Gerät steht der Heap in den
Szenarien 2′ und 4 noch aus.

## #378 — Der Graph in typisierten Feldern, Schritt 2: Kanten, Linien, Nachbarn, Zellen (gemessen 2026-10-18, am Rechner)

Was nach Schritt 1 blieb, liegt jetzt auch in typisierten Feldern
(`road_graph.dart`, seit 0.133.5):

- **Kanten**: Knoten a/b, Klasse, Schalter (Einbahn, Sperren, Höhen),
  Ebene, Wegeklasse, Länge, Höhen und Trage-Anteil je Kante in einem
  Feld; `GraphEdge` ist nur noch eine Sicht (Graph + Nummer), die
  `edges[i]` je Zugriff anlegt.
- **Linien**: alle Punkte hintereinander in einem Speicher, in Grad UND
  in Metern (die Projektion wird nicht mehr bei jeder Abfrage neu
  gerechnet); eine Kante ist ein Abschnitt. Eine Teilung schreibt den
  Teilungspunkt in den ersten Teil und hängt den zweiten hinten an.
- **Nachbarn**: je Kante zwei Plätze (am Knoten a und b), je Knoten eine
  verkettete Liste in Reihenfolge des Eintragens. Die Suche läuft direkt
  darüber (`adjFirst`/`adjNext`, `edgeA`/`edgeB`, `openFrom`), ohne
  Sicht je Kante.
- **Gitter**: Ein Segment ist die Nummer seines ersten Punkts (eine Zahl
  statt zwei), die Zellen findet eine Tabelle mit offener Adressierung
  statt einer `Map<int, int>` über 250 000 Zellen.
- Nach dem Bau kürzt `compact()` jedes Feld auf seine Länge; danach
  wachsen sie um ein Viertel, nicht aufs Doppelte (sonst legte das erste
  Anheften jedes große Feld noch einmal an).

Die Reihenfolge der Nachbarn und der Gittereinträge ist dieselbe wie
vorher — beides entscheidet bei gleichen Kosten bzw. Abständen.
Nachgewiesen mit einem Fingerabdruck (FNV über Text, `Object.hash` ist je
Prozess anders geseedet), den beide Mess-Skripte jetzt ausgeben: Graph
(Kanten mit Knoten, Klasse, Länge, Höhen, Punkten; Nachbarlisten) und
Plan (Reihenfolge, Zeit, Anstieg, Länge auf die letzte Stelle, Linie) —
vorher und nachher gleich, je zwei Läufe.

Heap eines Graphen (`perf_graph_memory_measure.dart`, 34 391 Knoten,
65 390 Kanten):

| Klasse | Schritt 1 | Schritt 2 |
|---|---|---|
| Heap des Graphen | 53,9 MB | 33,3 MB |
| `_Int32List` | 15,3 MB | 14,3 MB |
| `_Float64List` | – | 13,3 MB |
| `_List` | 14,1 MB (106 390) | 2,1 MB (6 458) |
| `GraphEdge` | 11,0 MB | – |
| `_Uint32List` | 3,1 MB | 0,6 MB |
| `_GrowableList` | 3,0 MB | – |
| `LatLng` | 2,6 MB | – |
| `Point`, `_Double` | 2,0 MB | – |

Zeiten in ms (JIT, `perf_loop_planner_measure.dart`, je zwei Läufe):

| Trails | Bau an Ort und Stelle vorher | nachher | Bau drüben vorher (Dauer / Pause) | nachher | erste Rechnung drüben vorher | nachher |
|---|---|---|---|---|---|---|
| 12 | 467–491 | 433–448 | 423–434 / 10–12 | 358–360 / 6–7 | 66–72 | 52 |
| 30 | 372–399 | 345–347 | 388–408 / 11 | 325–331 / 6 | 115 | 90–95 |
| 40 | 398–400 | 334–338 | 384–410 / 10–11 | 332–335 / 5–7 | 383–409 | 286–287 |
| 60 | 396–428 | 351–359 | 396–405 / 12 | 352 / 6–7 | 689–698 | 531–536 |

Der Graph braucht 38 % weniger Heap, der Bau ist gut 10 % schneller, die
längste Pause des UI-Takts beim Bau drüben halbiert sich noch einmal, und
die erste Rechnung ist 20–25 % schneller (die Suche liest Kanten und
Nachbarn ohne Objekt je Schritt). Der Rest des Heaps sind die Felder
selbst: Linienpunkte (4 × 8 Byte je Punkt), Kantenwerte (9 × 8 Byte je
Kante) und das Segmentgitter (gut 1 Mio. Einträge). Weniger ginge nur
mit gröberen Zahlen (Float32, Mikrograd als Int32) — das änderte die
Pläne im Grenzfall und gehört zu #380, wo die Kacheln ohnehin ein
eigenes Format bekommen.

Im Web (dart2js) baut `test/web/road_graph_browser_test.dart` einen
Graphen mit Kreuzungen, Join, Anheften und Suche und vergleicht mit den
Zahlen der VM; Gegenprobe: eine Zellsuche, die nur x vergleicht, wird
dort rot. Am Gerät stehen die Szenarien 2′ und 4 noch aus.

## #380 — Routing-Kacheln: Größe und Zusammensetzen (gemessen 2026-10-18, am Rechner, öffentliche Daten)

Frage aus `konzept-routing.md` 11: Wie groß ist das fertige Graphstück
je z13-Kachel, und wie schnell setzt der Planer daraus den Graphen
zusammen — gegen den Bau von heute? Drei Rahmen zu 11 × 11 Kacheln (die
Grenze des Planers, `kPlanMaxTiles`) um öffentliche Ortsmitten:
Innsbruck (Alpental, steil), Freiburg (Mittelgebirge, viele Forstwege),
Zürich (dichte Stadt). Kacheln vom eigenen Host, wie ein Bereich sie
liest: `python3 tool/routing_tiles.py sample --out DIR` (Karte
`dach-20261001`, Wege `ways-20261008`, Höhen `heights-20261001`), dann
`TB_TILES_DIR=DIR flutter test tool/routing_tiles_measure.dart`
(JIT, Zeiten das Beste aus drei Läufen).

Das Skript baut auf drei Wegen: **heute** `buildRoadGraphFrom` über den
ganzen Rahmen; **backen** dieselbe Funktion je Kachel über nur ihre
Wege (Höhen und Wege-Archiv der Nachbarn dazu), dann ins Format aus 11.3;
**zusammensetzen** die Stücke dekodieren, Knoten über ihre Mikrograd
teilen, die markierten Randknoten mit der 2-m-Regel binden.

| | Innsbruck | Freiburg | Zürich |
|---|---:|---:|---:|
| Kanten (heute) | 100 767 | 195 653 | 379 198 |
| **Bau heute** | 1 560 ms | 3 217 ms | 4 386 ms |
| **Zusammensetzen** (davon dekodieren) | **161 ms** (33) | **321 ms** (70) | **521 ms** (95) |
| Faktor | 9,7 | 10,0 | 8,4 |
| Backen je Kachel, Median / 90 % | 13 / 35 ms | 36 / 57 ms | 39 / 63 ms |
| Backen, Summe aller Kacheln | 2,1 s | 4,7 s | 5,1 s |
| **Routing-Kacheln gzip** (roh) | **1,40 MB** (1,75) | **2,38 MB** (3,02) | **4,12 MB** (5,28) |
| je Kachel Median / 90 % / größte | 6 / 32 / 106 KB | 17 / 33 / 120 KB | 28 / 61 / 113 KB |
| Kartenkacheln z13 gzip (alle Ebenen) | 2,25 MB | 4,03 MB | 4,49 MB |
| Wege-Archiv / Höhen | 0,37 / 0,55 MB | 0,63 / 0,55 MB | 0,54 / 0,55 MB |

Derselbe Graph? Länge 7 856,9 → 7 857,0 km, 15 909,8 → 15 910,2 km,
19 646,3 → 19 647,0 km; größte Komponente gleich (96,19 / 98,97 /
97,59 %); keine Kante ohne Höhen; Anstieg und Abstieg zusammen höchstens
0,005 % anders. 99,7–99,9 % der Kanten finden sich mit denselben Enden
und Punktzahl wieder; davon tragen 0,01–0,02 % der benannten Länge keine
Wegegüte mehr (überwiegend 0–2-m-Bindungen am Kachelrand, die heute die
Güte des Wegs daneben bekommen). Die Kosten von 40 Suchen zwischen
festen Knotenpaaren (Bio) weichen im Median 0,01 / 0,02 / 0,03 % ab,
in 90 % unter 0,08 / 0,28 / 0,12 %, höchstens 0,23 / 1,19 / 0,30 %.

Vier Dinge, die die Messung gezeigt hat:

1. **Das Zusammensetzen ist nicht der teure Teil, das Einfügen ist es.**
   Dekodieren kostet ein Fünftel; der Rest ist `addEdge` samt
   Segmentgitter und die Bindung am Rand. Kreuzungen, tote Enden in der
   Kachel, Höhen und Wegegüte — am Pixel zusammen der größte Teil der
   41–44 s (#356; allein die Güte 15–17 s) — fallen ganz weg.
2. **Die Rundung der Höhen kippte „bergab"** (im ersten Lauf): `edgeTimeS`
   rechnet mit der Abfahrtsgeschwindigkeit, sobald der Abstieg den
   Anstieg übersteigt, auch um Millimeter. Auf Dezimeter gerundet
   wurden 9 mm Abstieg zu null, flache Straßen fuhren flach, und Suchen
   wichen bis 2,1 % ab. Zentimeter mit festgehaltener Richtung: Median
   0,41 → 0,02 % (Freiburg).
3. **Die Kantenwerte sind der größte Teil des Formats.** Erst mit
   16 Byte je Kante (alle Felder immer) waren es 2,95 MB gzip (Freiburg);
   mit Bits für die seltenen Felder und Knoten als Differenz 2,60 MB;
   mit den inneren Punkten in Pixeln der Kartenkachel (verlustfrei, sie
   liegen auf deren Raster; 0,88 statt 1,18 MB roh) 2,38 MB. Roh bleiben
   je Kante rund 8 Byte Werte und 3–5 Byte Punkte.
4. **Backen je Kachel kostet zusammen etwas mehr als ein Bau** (1,2- bis
   1,4-mal): Jede Kachel liest Höhen und Wege-Archiv ihrer acht Nachbarn
   mit. Für den Workflow egal, auf dem Gerät (Weg B) teilbar.

Hochgerechnet (Schätzung, nicht gemessen): z13 der DACH-Karte sind
1,34 GB (`docs/karte-welt-messung.md`), mal 60–90 % ⇒ 0,8–1,2 GB
Routing-Kacheln; Kanada 0,5–0,8 GB. Am Pixel war der Bau gut zehnmal
langsamer als hier (120 Kacheln 41–44 s); kippt das Verhältnis nicht,
wären es dort 4–5 s statt 41–44 s. Gemessen wird das am Gerät, sobald
das Zusammensetzen in der App steht (Konzept-Routing 11.6).

## #381 — Kacheln beim Suchen nachladen (gemessen 2026-10-28, in der Cloud, öffentliche Daten; Empfehlung: nicht bauen)

Die Frage des Issues: Der Planer setzt den ganzen Rahmen zusammen, bevor
die erste Suche läuft — auch Ecken, die keine Suche erreicht. Lohnt es
sich, Kacheln erst zu laden, wenn eine Suchfront ihren Rand erreicht
(wie BRouter)? Gespart würde nur, was KEINE Suche einer Planung
erreicht; was die Suchen über den Rahmen hinaus erreichen, müsste das
Nachladen zusätzlich holen.

`tool/routing_lazy_measure.dart` über drei Rahmen zu 15 × 15 Kacheln
(`python3 tool/routing_tiles.py sample --out DIR --size 15`, dieselben
Ortsmitten und Bauten wie „#380"): alle Kacheln gebacken und
zusammengesetzt wie seit 0.136.0, Start in der Mitte, Trails mit
Anfang und Ende auf zufälligen Knoten im Radius, der Rahmen der App
daraus (`roadGraphTiles(…, kTrailHeadMarginM)`, ohne Verbinder — der
echte ist eher größer). Gesucht wird wie `planLoop`: je eine begrenzte
Suche vom Start und von jedem Trail-Ende, Grenze das Zeitbudget, auf
dem GANZEN 15 × 15-Graphen. Gezählt: Kacheln mit einem erreichten
Knoten. „+" heißt: Die Suchen erreichen den Rand des Beispiels, die
Zahl darüber hinaus ist eine Untergrenze. Zusammensetzen das Beste aus
drei Läufen (JIT).

| Rahmen | Fall | Rahmen-Kacheln | erreicht im Rahmen | erreicht darüber hinaus | Zusammensetzen ganz / nur erreicht |
|---|---|---:|---:|---:|---:|
| Freiburg | 12 Trails in 5 km, Bio 2 h | 12 | 12 (100 %) | 124+ | 156 / 101 ms |
| Freiburg | 12 Trails in 5 km, Bio 3 h | 12 | 12 (100 %) | 169+ | 116 / 171 ms |
| Freiburg | 30 Trails in 8 km, Bio 3 h | 30 | 30 (100 %) | 169+ | 282 / 288 ms |
| Freiburg | 30 Trails in 12 km, Bio 3 h | 56 | 56 (100 %) | 150+ | 560 / 489 ms |
| Freiburg | 40 Trails in 12 km, Bio 5 h | 72 | 72 (100 %) | 176+ | 550 / 514 ms |
| Freiburg | 60 Trails in 12 km, E-MTB 5 h | 72 | 72 (100 %) | 183+ | 577 / 555 ms |
| Innsbruck | 12 Trails in 5 km, Bio 2 h | 20 | 17 (85 %) | 29+ | 174 / 158 ms |
| Innsbruck | 12 Trails in 5 km, Bio 3 h | 12 | 12 (100 %) | 43+ | 125 / 114 ms |
| Innsbruck | 30 Trails in 8 km, Bio 3 h | 35 | 28 (80 %) | 35+ | 223 / 205 ms |
| Innsbruck | 30 Trails in 12 km, Bio 3 h | 49 | 40 (82 %) | 43+ | 256 / 270 ms |
| Innsbruck | 40 Trails in 12 km, Bio 5 h | 42 | 36 (86 %) | 75+ | 227 / 209 ms |
| Innsbruck | 60 Trails in 12 km, E-MTB 5 h | 63 | 62 (98 %) | 119+ | 319 / 335 ms |
| Zürich | 12 Trails in 5 km, Bio 2 h | 15 | 15 (100 %) | 94+ | 406 / 377 ms |
| Zürich | 12 Trails in 5 km, Bio 3 h | 12 | 12 (100 %) | 167+ | 266 / 275 ms |
| Zürich | 30 Trails in 8 km, Bio 3 h | 36 | 36 (100 %) | 180+ | 637 / 609 ms |
| Zürich | 30 Trails in 12 km, Bio 3 h | 72 | 72 (100 %) | 166+ | 1 034 / 1 120 ms |
| Zürich | 40 Trails in 12 km, Bio 5 h | 72 | 72 (100 %) | 181+ | 1 044 / 1 028 ms |
| Zürich | 60 Trails in 12 km, E-MTB 5 h | 72 | 72 (100 %) | 183+ | 1 058 / 1 046 ms |

Drei Dinge, die die Messung gezeigt hat:

1. **Die Suchen erreichen den Rahmen fast ganz** — im Mittelgebirge und
   in der Stadt immer 100 %, im Alpental 80–98 % (die Hänge über der
   Talsohle). Zu sparen bleibt höchstens ein Fünftel der Kacheln, und
   das Zusammensetzen der erreichten Kacheln allein ist im Rauschen
   gleich teuer (± 10 %); die Ecken, die keine Suche erreicht, sind die
   leeren.
2. **Ohne Rahmen würden die Suchen ein Vielfaches laden.** Mit 2–5 h
   Budget reicht jede Suche weit über den Rahmen hinaus — bis an den
   Rand des 15 × 15-Beispiels (~50 km), also 30 bis über 180 Kacheln
   mehr. Heute begrenzt der Rahmen die Suchen, nicht das Budget. Ein
   Nachladen ohne Rahmen müsste `kPlanMaxTiles` (120) fast immer
   reißen; mit Rahmen bleibt es der Rahmen von heute. Die Route ohne
   Trail (`kRouteDirectBudget`, 24 h) wäre ohne Rahmen ganz unbegrenzt.
3. **Der teure Teil ist weg.** Seit #380 kostet der ganze Rahmen am
   Rechner 0,1–1,1 s; hochgerechnet auf den Pixel (Faktor ~10, #380)
   1–10 s im ungünstigsten Fall (Stadt, 72 Kacheln). Davon spart das
   Nachladen nach Punkt 1 nichts Messbares — der Umbau (Suche neu
   starten oder fortsetzen, `RoadGraph.revision` und `EdgeCosts` beim
   Anhängen, Trails und Anheften je neuer Kachel, Pläne nicht mehr
   identisch) brächte also keinen Gewinn.

Empfehlung: nicht bauen (wie #377). Ob der Rahmen auf dem Pixel nach
#380 schnell genug ist, zeigen die Szenarien 2′/4 (15h1); bleibt dort
das Zusammensetzen der teure Teil, ist der Hebel ein engerer Rahmen oder
eine Grenze je Suche, nicht das Nachladen.
