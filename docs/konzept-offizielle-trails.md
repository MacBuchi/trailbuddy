# Offizielle Trails — Konzept (Issue #13)

*Stand 2026-09-28. Entscheidungen des Betreibers in Abschnitt 2, die
Bestandsaufnahme der Quellen in Abschnitt 4, Zurückgestelltes in
Abschnitt 6.*

## 1. Kurzfassung

Offiziell ausgewiesene Singletrails und Bikeparks — vom Land, von einem
Verein mit Genehmigung, vom Betreiber eines Bikeparks — erscheinen als
**eigene Ebene** auf der Karte, getrennt von den Trails des Buddy-Netzes.
Ein CI-Job holt die Quellen täglich, filtert auf Singletrails, bringt
sie in ein gemeinsames Format und veröffentlicht sie als statische
GeoJSON-Dateien je Region. Die App lädt die Region, die sie gerade zeigt,
merkt sie sich und zeichnet sie als abschaltbare Ebene mit eigenem Blatt
und Quellenangabe. Keine Tabelle, keine RLS, kein Abgleich: Die Daten
sind öffentlich, und das Buddy-Modell bleibt unberührt.

## 2. Entscheidungen des Betreibers (2026-09-28)

1. **Eigene Ebene, CI baut Dateien.** Verworfen: ein offizielles Konto
   in der Datenbank (Abschnitt 3) und Live-Abfragen aus der App wie bei
   den Orten (mehrere fremde Server sähen den Kartenausschnitt, jede
   Quelle bräuchte eine eigene Anbindung im Client).
2. **Nur Singletrails und Bikeparks.** Ausgeschilderte Touren über
   Forstwege bleiben draußen: Sie sind nach der Importregel Fahrten, und
   ein Trail des Netzes wäre darin immer nur ein „Teil".
3. **Regionen, gewünscht:** Tirol, Vorarlberg, Schweiz,
   Baden-Württemberg — dort ausdrücklich auch Vereins-Trails
   (Trailsurfers Baden-Württemberg e.V., Bikeländ Eberbach, Flowtrail
   Mosbach und weitere dieser Art). Was davon heute verwendbar ist:
   Abschnitt 4.
4. **Kein OpenStreetMap als Quelle — Klasse statt Masse.** Nur, was
   eine zuständige Stelle ausweist oder betreibt: eine Behörde, ein
   Verein mit Genehmigung, ein Bikepark. Lieber eine dünne Ebene, auf
   die man sich verlassen kann, als eine volle mit Unbekanntem.
5. **Die Ebene ist beim ersten Start an.**

## 3. Warum kein offizielles Konto

Der Vorschlag im Issue war ein TrailBuddy-Konto, das CI mit offiziellen
Trails füllt. Als **Buddy aller** geht das nicht: Wer Buddy ist, sieht
nach der Sichtbarkeitsregel (Konzept 3) die Aufzeichnungen seiner Buddys
— ein Konto, das mit allen befreundet ist, sähe alles, und ein
abgeflossener Schlüssel dieses Kontos läge offen. Bliebe eine
Sonderregel „offizielle Aufzeichnungen sieht jeder". Dann liefen
fremdlizenzierte Linien durch den Abgleich und würden mit Beiträgen von
Nutzern zu einer Trail-Kennung verschmolzen: Lizenzpflichten (Quellen-
angabe je Linie) wandern in die Trail-Tabellen, und wenn eine Quelle
einen Trail umbenennt, verlegt oder streicht, trifft das eine Kennung,
an der Beiträge von Nutzern hängen. Konzept 3 („sichtbar ist, was
jemand GEFAHREN ist") gälte nicht mehr. Die getrennte Ebene hat keinen
dieser Nachteile.

## 4. Quellen — Bestandsaufnahme (2026-09-28)

**Entscheidung des Betreibers:** Zuerst kommt nur, was es offiziell
gibt und wir ohne Rückfrage verwenden dürfen. Vereine, Bikeparks und
Anfragen (SchweizMobil) sind zurückgestellt.

Geprüft an den Daten selbst (Kataloge der Länder, WFS abgerufen und
ausgezählt; Kennzahlen, keine Koordinaten):

| Quelle | Lizenz | Singletrails | Befund |
|---|---|---|---|
| **Tirol — „Radrouten in Tirol"** (Land Tirol, Waldschutz; data.gv.at) | **CC0** | **238** (`ROUTEN_TYP = Single Trail`) | Freigegebene Singletrails nach dem Tiroler MTB-Modell, je mit Name, Schwierigkeit (leicht 90 · mittelschwierig 102 · schwierig 46), Länge, Höhenmetern und **Status offen/gesperrt** (heute 16 gesperrt). Länge: Median 0,9 km, p90 4,2 km; 156 abfahrtsdominiert. Hauptroute 185, Variante 53. Stand der jüngsten Zeile: 23.09.2026. Zugang: WFS (GeoJSON) und GPX-Zip. |
| Vorarlberg — `vogis:mountainbike_strecken` (VOGIS) | CC BY 4.0 | 19 Stücke, zusammen ~750 m | Das Mountainbikenetz unterscheidet Asphalt, Schotter, Schiebe-/Tragestrecke und Singletrail, aber die Singletrail-Stücke sind Verbindungen im Routennetz (Median 19 m), keine Trails. **Nicht verwendbar.** |
| Schweiz — Mountainbikeland (ASTRA, SchweizMobil) | frei, Quellenangabe Pflicht | **ja, als Abschnitte**: 4802, ~1390 km (`MTBWeg.IsSTrail`); Bikepark 45 Abschnitte, ~8 km | **Korrektur:** Der Kartendienst zeigt nur Route, Routennummer und Segment; der Download (Shapefile, Ebene `MTBWeg`) hat das Merkmal. Aber: Abschnitte von Routen ohne Namen, meist ohne Schwierigkeit, Median 163 m — **Verwendung unklar** (ein Trail wäre erst eine Kette von Abschnitten). |
| Schweiz — Sperrungen/Umleitungen Mountainbikeland | frei | — | Täglich; für später (Abschnitt 7). |
| Bayern — Freizeitwege, „Mountainbikewege" | CC BY 4.0 | — | Ausgeschilderte Routen, keine Singletrails. |
| Baden-Württemberg | — | — | Kein amtlicher Datensatz zu MTB-Strecken gefunden (GovData, daten.bw). Legale Trails gibt es hier über Vereine — zurückgestellt. |

Ausgeschlossen: **Trailforks** (Daten nur für nicht-kommerzielle,
„share-alike"-Nutzung mit Registrierung, keine Kopie für
nicht-persönliche Zwecke), **OpenStreetMap** (Entscheidung 4),
Tourenportale (Outdooractive, Komoot, Bergfex — keine offenen Daten).

**Folge: Der Start ist Tirol allein.** 238 Singletrails, gemeinfrei,
mit Schwierigkeit und einem amtlichen Status. Die Quellen mit unklarer
Verwendung (Schweiz, Vorarlberg, Bayern, Vereine) liegen samt Notizen
beim Betreiber (Nextcloud), nicht im Repo. Zwei Dinge fürs Bauen:

- **Abschnitte, nicht Trails.** Die 238 Zeilen sind ABSCHNITTE: Eine
  `ROUTENNUMMER` ist ein Trail aus Hauptroute und Varianten (185
  Nummern). Die Pipeline macht daraus ein Feature je Nummer (Teile in
  `sections`: Variante ja/nein, gesperrt ja/nein) und fügt nichts über
  Nummern hinweg zusammen — das wäre eine Behauptung über die Quelle.
  Ein Trail, der insgesamt unter der Mindestlänge des Abgleichs
  (150 m, seit Patch 017 50 m) bleibt, fällt weg. Stand 2026-09-28: **181 Trails**, 4
  weggelassen.
- **Der Status ist amtlich.** „gesperrt" kommt vom Land und wird so
  angezeigt — als Aussage der Quelle, nicht als Statusmeldung eines
  Buddys (Konzept 3). Das Blatt sagt, von wem die Sperre kommt.

## 5. Aufbau

### 5.1 Der CI-Job

- `tool/official/sources.json` — die Quellenliste: Kennung, Name,
  Region, Lizenz, Quellenangabe (Wortlaut), Abrufweg, Filter auf
  Singletrails, bei Vereinen der Verweis auf die Erlaubnis (Datum; das
  Schreiben selbst liegt im DocuHub, nicht im Repo).
- `tool/official_trails.py` (nur Standardbibliothek, wie die anderen
  Werkzeuge) holt jede Quelle, filtert, bringt sie in das Format unten,
  vereinfacht die Linien (dieselbe Toleranz wie der Import) und schreibt
  je Region eine Datei plus einen Index.
- `official-trails.yml`, täglich (seit #41 — Sperren veralten schneller
  als Trails) und von Hand auslösbar. Ergebnis
  ist der Branch **`official-trails-data`** (nur Daten, nie von Hand),
  die App liest ihn über `raw.githubusercontent.com` — der Host kommt
  mit der App-Ebene in die Datenschutzerklärung. **Nicht als Release:**
  Die Update-Prüfung nimmt im Vorab-Kanal das jüngste Release der Liste,
  ein Daten-Release stünde dort als „neueste Version". Gepusht wird nur
  bei Änderung (kein Zeitstempel des Laufs in den Dateien).
- **Wächter:** Eine Quelle, die nicht antwortet, behält ihre letzte
  Datei (Run-Summary sagt es). Eine Quelle, die plötzlich mehr als ein
  Drittel ihrer Trails verliert, wird NICHT veröffentlicht — ein
  kaputter Export soll keine Region leeren. Ebenso wenig eine Quelle,
  die auf einmal mehr als ein Drittel ihrer Trails sperrt (#41): Der Lauf
  wird rot, und erst nach einem Blick in die Quelle veröffentlicht ihn
  ein Handlauf mit `allow_mass_closure` (ein Saisonende ist ein echter
  Fall). Ein Statuswert, den der Leser nicht kennt, lässt die frühere
  Datei stehen und macht den Lauf rot — als „offen" gelesen, gäbe ein
  umbenanntes Feld still jede Sperre frei, und das ist die teure
  Richtung. Jede Datei trägt Stand und Quelle.
- `--self-test` mit kleinen Beispieldaten je Leser, in CI (Tool
  self-tests) und vor jedem Lauf.

### 5.2 Das Format

Eine GeoJSON-FeatureCollection je Region, jedes Feature eine
`MultiLineString` (Hauptroute und Varianten als Teile, `sections` sagt
je Teil `variant` und `closed`; `status` ist `open`, `partly_closed`
oder `closed`) mit:

| Feld | Inhalt |
|---|---|
| `id` | `quelle:originalkennung`, stabil über Läufe |
| `name` | wie in der Quelle |
| `kind` | `trail` oder `bikepark` |
| `difficulty` | Originalwert der Quelle (z. B. „rot") |
| `level` | vereinheitlicht: `easy`, `medium`, `hard`, `expert`, oder leer |
| `source` | Kennung aus `sources.json` |
| `updated` | Stand der Quelle |

Der Index (`index.json`) nennt je Region Datei, Rahmen (Bounding Box),
Anzahl, Stand und die Quellen mit Lizenz und Quellenangabe.

**Keine S-Grade.** Die Farbskalen der Quellen sind keine
Singletrail-Skala; umgerechnet würde eine Einschätzung behauptet, die
niemand abgegeben hat. Das Blatt zeigt den Originalwert.

### 5.3 In der App

- Eine Ebene „Offizielle Trails", ein- und ausschaltbar (Vorgabe: an,
  Entscheidung 5), gerätelokal wie der Orte-Filter.
- Geladen wird eine Region erst ab Zoom 8 und erst, wenn der Ausschnitt
  ihren Rahmen berührt; gemerkt auf dem Gerät, neu geholt, wenn der
  Index einen neuen Stand nennt. Ohne Netz gilt der gemerkte Stand, auch
  ein älterer. (Umgesetzt in 0.10.0, `lib/features/official/`.)
- **Eigene Linienart**, gestrichelt und in einer Farbe, die keine
  Trail-Farbe ist (Grün, Blau, Orange sagen, was ICH mit einem Trail zu
  tun habe). Unter den Trails des Netzes, über den Orten.
- Ein Tipp öffnet ein eigenes Blatt: Name, Art, Schwierigkeit laut
  Quelle, Stand, Quellenangabe mit Lizenz, Link zur Quelle. Keine
  Beiträge, keine Hinweise, kein Status — dafür gibt es die Trails des
  Netzes.
- **„Auch ausgeschildert als …"** im Trail-Blatt, wenn ein Trail des
  Netzes eine offizielle Linie deckt — gerechnet auf dem Gerät mit
  derselben Deckung wie der Abgleich (Korridor 15 m, ≥ 0,8). Beide
  Linien sieht der Nutzer ohnehin; über Netzgrenzen geht nichts
  (Konzept 12).
- Die Quellenangaben der geladenen Regionen stehen in der
  Karten-Attribution, solange die Ebene an ist.
- Gesperrte Teile sind grau, nicht orange: Orange ist die Meldung eines
  Buddys. Das Blatt nennt Status und Schwierigkeit immer mit der Quelle,
  eine Sperre mit deren Stand („Gesperrt laut Land Tirol, Stand
  28.09.2026" — der jüngste Stand der Abschnitte des Trails).
- **Sperre im Trail-Blatt** (#41): Deckt ein Trail des Netzes eine
  offizielle Linie mit Sperre, warnt die Zeile nur, wenn ein gesperrter
  Abschnitt AUF dem Trail liegt — gedeckt zu 0,8 oder auf mindestens
  50 m (ein Queren deckt im Korridor höchstens rund 30 m). Dann grau mit
  Sperrsymbol: „gesperrt laut …, Stand …" (bei „teilweise gesperrt":
  „Abschnitt gesperrt …"). Liegt die Sperre woanders (meist eine
  Variante), sagt die Zeile „anderer Abschnitt gesperrt laut …" und
  warnt nicht.

## 6. Zurückgestellt (Entscheidung 2026-09-28)

1. **Vereine und Bikeparks** (Baden-Württemberg: Trailsurfers,
   Bikeländ Eberbach, Flowtrail Mosbach): nur mit schriftlicher
   Erlaubnis. Eine Mustermail an Vereine und an SchweizMobil liegt beim
   Betreiber; die Zusagen kämen in den DocuHub.
2. **Schweiz:** Singletrails als Daten nur auf Nachfrage bei
   SchweizMobil.
3. **Rechtlich** (Konzept 7) bleibt beim Bauen zu beachten: Die Ebene
   sagt „ausgewiesen laut Quelle", nie etwas über andere Trails — ein
   Satz im Blatt, keine Kennzeichnung der übrigen als „inoffiziell".

## 7. Später

- **Sperrungen** aus offiziellen Quellen als Warnung an offiziellen
  Linien und im Trail-Blatt — **für Tirol gebaut** (#41, 0.103.0, siehe
  5.1 und 5.3). Die Schweiz (Sperrungen/Umleitungen Mountainbikeland,
  täglich) folgt erst mit ihren Trails, also nach Abschnitt 6.2: Eine
  Sperre ohne die Linie, an der sie gilt, hat keinen Ort.
- Weitere Regionen, sobald eine Quelle die Bedingungen aus Abschnitt 4
  erfüllt.

## 8. Fahrplan

1. Dieses Konzept mit Bestandsaufnahme (Issue #13).
2. Pipeline mit Tirol: WFS abrufen, auf `Single Trail` filtern, Format,
   Wächter, Self-Test.
3. Ebene in der App mit Blatt, amtlichem Status und Quellenangabe;
   Datenschutzerklärung (`raw.githubusercontent.com`). **Erledigt,
   0.10.0.**
4. „Auch ausgeschildert als …" im Trail-Blatt. **Erledigt, 0.11.0**:
   drei Sätze je nach Richtung der Deckung („auch ausgeschildert als",
   „Teil des offiziellen Trails", „enthält den offiziellen Trail"),
   ohne Fréchet — es wird nichts verschmolzen. Varianten zählen nicht
   gegen „derselbe"; eine amtliche Sperre steht mit Quelle dabei.
5. Sperren der Quelle mit Stand, Warnung im Trail-Blatt nur, wenn der
   gesperrte Abschnitt darauf liegt; täglicher Lauf, Wächter gegen
   Massensperren und unbekannte Statuswerte. **Erledigt, 0.103.0** (#41).
6. Weitere Quellen, sobald eine die Bedingungen erfüllt; Vereine und
   Schweiz nach Abschnitt 6.
