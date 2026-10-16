# Konzept: Trail-Werte und Airtime unter Buddys (#36)

*Stand 2026-10-16, Entwurf zur Entscheidung. Baut auf `konzept-trails.md`
Abschnitt 7 und 9 und auf den Kernanforderungen (`anforderungen.md`,
A1–A3, A6, A10, A11) auf; das Aussehen kommt aus dem Navi-Entwurf
(`docs/design/navi/`, Betreiber 2026-10-13: „Trail-Werte … kommen mit
#36"). Gebaut wird nichts, bevor die Fragen in Abschnitt 11 entschieden
und die Schwellen aus Abschnitt 8 gemessen sind.*

## 0. Worum es geht, in fünf Sätzen

Während einer Fahrt misst das Telefon auf Trails drei Werte: **Airtime**
(Sprünge aus der Schwerelosigkeit im Beschleunigungssensor), **Max G**
(die härteste Landung) und **Manual** (Vorderrad hoch, aus dem Kreisel,
nur mit Lenkerhalterung). Gemessen und gespeichert wird auf dem Gerät,
die Werte hängen an der Fahrt wie heute die Bestätigungen (#116). Zum
Server geht — wenn der Fahrer es will — **ein Bestwert je Trail**, kein
Verlauf und keine Fahrt; sehen können ihn nur direkte Buddys, die den
Trail selbst sehen. Daraus wird eine **Rangliste unter Buddys je
Trail**, die sich ausdrücklich als Spiel ausgibt, nicht als Rekord. Es
gibt keine Rangliste über Trails hinweg, kein Netz-Ranking und keinen
Wert, den jemand außerhalb des eigenen Buddy-Kreises sieht.

## 1. Randbedingungen (verbindlich, schon entschieden)

1. **Nur unter Buddys** (Konzept 7, A11): nie global, nie über das
   eigene Netz hinaus, keine serverseitige Auswertung über Nutzer
   hinweg (Konzept 12 — auf dem dezentralen Weg ginge sie gar nicht).
2. **Ein Spiel, kein Leistungsnachweis**: Das Telefon zu werfen ist ein
   Sprung von 0,5 s. Die Oberfläche sagt das an jeder Rangliste
   („Spiel, kein Rekord" — so steht es im Entwurf 1a).
3. **Ein Anreiz zu Risiko**: Das gehört in die Nutzungsbedingungen
   (rechtliche Prüfung, #39) und in einen Satz beim ersten Einschalten
   (A10: gesagt, nicht gesperrt).
4. **Fahrten verlassen das Gerät nie** (A3). Ein Bestwert je Trail ist
   keine Fahrt — er wächst nicht mit gefahrener Zeit und trägt keinen
   Ort außer dem Trail, den der Buddy ohnehin sieht. Ein Verlauf je
   Fahrt wäre eine; den gibt es nicht.

## 2. Was gemessen wird, und wo das Telefon steckt

Die Halterung entscheidet, was überhaupt messbar ist (Entwurf 1e,
„Wo ist dein Handy?"):

| Wert | Lenker | Hosentasche | Rucksack |
|---|---|---|---|
| Airtime | ● | ● | ◐ (der Körper federt mit) |
| Max G | ● | ● | – (Rucksack dämpft) |
| Manual | ● | – | – |

- **Airtime**: Betrag der Beschleunigung nahe 0 (Startwert < 0,3 g)
  länger als 150 ms (Konzept 9) ⇒ ein Sprung; seine Dauer ist die Zeit
  bis zum Stoß der Landung. Je Trail-Durchfahrt: Summe, Anzahl,
  längster Sprung.
- **Max G**: Spitze des Betrags innerhalb von 300 ms nach einer
  Landung, gefiltert gegen Schläge (Wurzel, Stufe) ohne vorherige
  Flugphase. Nur Landungen zählen, sonst misst der Wert den Untergrund.
- **Manual**: Neigung über 15° gegen die Fahrposition bei Fahrt
  (> 8 km/h), Länge in Metern aus GPS-Tempo × Zeit (Entwurf, Zustand
  „Manual erkannt"). Nur mit Lenkerhalterung: In der Tasche kippt das
  Telefon nicht mit dem Rad.
- **Nur auf Trails** und nur, wenn eingeschaltet („Trail-Werte messen"
  im Start-Blatt). Auf der Anfahrt läuft kein Sensor — das spart Akku
  und macht aus einem Bordstein keinen Sprung.

Alle Schwellen oben sind Startwerte aus der Literatur und dem Entwurf,
**keine gemessenen** — Abschnitt 8.

## 3. Wie gemessen wird

- **Im Dienst, nicht in der Oberfläche.** Die Fahrt misst im
  Service-Isolate (`lib/features/rides/CLAUDE.md`, „Fahrt
  aufzeichnen"), die Navigation auch; der Sensor muss dort laufen,
  sonst endet die Messung, sobald man die App wegwischt. Ob ein
  Sensor-Plugin (`sensors_plus` o. ä.) im Isolate des Vordergrund-
  Dienstes Ereignisse liefert, ist **die erste Frage an die Technik**
  (Schritt 1 in Abschnitt 9); geht es nicht, braucht es einen kleinen
  nativen Teil im Dienst.
- **100 Hz, ohne neue Berechtigung.** Android drosselt ohne
  `HIGH_SAMPLING_RATE_SENSORS` auf 200 Hz; 100 Hz reichen für Flugphasen
  ab 150 ms. Keine Berechtigung im Manifest, kein neuer Dialog.
- **Ausgewertet wird laufend, gespeichert wird das Ergebnis.** Kein
  Rohstrom auf der Platte (eine Stunde bei 100 Hz wären ~40 MB), sondern
  je Ereignis eine Zeile in der Fahrt (`AirEvent`, `LandingEvent`,
  `ManualEvent` mit Zeit, Dauer bzw. Wert, Trail), wie heute
  `ConfirmAsked`. `RidePoint.fromJson` lässt fremde Zeilen schon liegen.
- **Auf dem Trail heißt auf der Linie**: dieselbe Regel wie bei
  „Bestätigen durch Fahren" (`confirmPromptFor`: zwei Fixe ≤ 20 m von
  der Linie, ≥ 25 m auseinander), und vorbei, wenn der Fahrer die Linie
  verlässt oder ihr Ende erreicht. Die Ziele legt die App wie bei #116
  als Datei ab, der Dienst liest sie.
- **Kein Web.** Ein Browser-Tab im Hintergrund bekommt weder Positionen
  noch Sensoren; das Web zeigt die Rangliste, misst aber nicht.

## 4. Was das Gerät verlässt

Der eine Datensatz, der zum Server geht, ist **der eigene Bestwert je
Trail**:

| Feld | Bedeutung |
|---|---|
| Nutzer, Trail | wer, auf welchem Trail (Trail-Kennung, besitzerlos) |
| Airtime je Durchfahrt | die beste Summe einer Durchfahrt, in Zehntelsekunden |
| längster Sprung | der längste einzelne, in Zehntelsekunden |
| Monat | wann der Bestwert entstand — ein Monat, kein Tag |

- **Keine Zeitreihe, keine Fahrt, kein Ort am Sprung.** „Bei km 2,1"
  aus dem Entwurf bleibt auf dem Gerät.
- **Max G und Manual bleiben auf dem Gerät** (Vorschlag, Frage 2): Max G
  als Rangliste belohnt harte Landungen — genau das Risiko aus 1.3;
  Manual misst nur, wer einen Lenkerhalter hat.
- **Ein Wert wird nur besser oder gelöscht**: Hochladen nur, wenn der
  neue Bestwert den alten schlägt; „Meinen Beitrag löschen" am Trail
  löscht ihn mit (`supabase/CLAUDE.md`, „Beitrag löschen").
- **Sichtbar** für den Nutzer selbst und für direkte Buddys, die den
  Trail selbst sehen (A2) — dieselbe RLS-Form wie die Bewertungen am
  Trail. Nie transitiv, nie für Fremde, kein Zähler, wie viele Werte
  ein Trail hat (A1, A4).
- **Duplikate zusammenführen** (#107) nimmt die Bestwerte mit: Der
  behaltene Trail bekommt den besseren Wert je Nutzer.

Das ist eine neue Tabelle und eine neue Datenkategorie: Patch,
`schema.sql`, Saat-Liste, `schema_check.sh`, Datenschutzerklärung in
beiden Sprachen und `docs/play-console.md` im selben PR (A6).

## 5. Die Rangliste

- **Je Trail, unter Buddys**: im Trail-Blatt eine Zeile „Airtime unter
  Buddys" mit Platz, Name (Alias) und Wert — höchstens die ersten drei
  und der eigene Platz. Am Ende des Trails im Blatt „Trail geschafft"
  (N2): „#2 hinter Jan (5,1 s) — Spiel, kein Rekord" (Entwurf 1a).
- **Gewertet wird die Airtime je Durchfahrt**, nicht der längste
  Sprung: Die Summe belohnt eine flüssige Jump-Line, der längste
  Sprung den einen großen Drop (Frage 3).
- **Keine Rangliste über Trails hinweg**, kein „König des Monats",
  keine Bestenliste im Profil. Wer will, sieht in „Meine Fahrten" seine
  eigenen Werte je Fahrt — das ist ein Tagebuch, keine Rangliste.
- **Bio und E-MTB werden nicht getrennt**: Airtime hängt am Fahrer und
  an der Line, kaum am Motor (Frage 4 als Kontrolle).
- **Kein Push für Ranglisten**: „Jan hat dich überholt" wäre genau die
  Aufmerksamkeit, die Konzept 7 nicht will.

## 6. Oberfläche (aus dem Navi-Entwurf)

- **Start-Blatt (1e)**: Schalter „Trail-Werte messen — Airtime, G und
  Manual, nur auf Trails", darunter die Wahl der Halterung mit der
  Tabelle aus Abschnitt 2 (● ◐ –). Beim ersten Einschalten der Satz zum
  Risiko (1.3).
- **Auf dem Trail (Folgeansicht)**: unten die Werte-Kacheln AIRTIME,
  MAX G, MANUAL; ein Sprung blendet 2 s lang „AIR 0,8 s · 2,9 G
  Landung" ein (AIR-Toast); ein laufender Manual zeigt Meter und den
  Strich des Bestwerts.
- **Trail geschafft (N2)**: drei Kacheln mehr (AIRTIME mit Anzahl und
  längstem, MAX G, MANUAL) und die Rangzeile; heute hat das Blatt drei
  von sechs Kacheln.
- **Bild-im-Bild und Benachrichtigung (N3)**: zweite Zeile „Air 2,4 s ·
  max 3,1 G · Manual 7,6 m" auf dem Trail.
- **Aufzeichnen ohne Navigation**: dieselben Werte in der laufenden
  Fahrt und im Zerlege-Blatt je Trail-Zeile.
- Bewegung und Farben nach `docs/design/README.md`; eine Abweichung
  ändert die Datei im selben PR.

## 7. Datenschutz und Recht

- **Sensordaten werden auf dem Gerät ausgewertet**; nur der Bestwert je
  Trail geht weg (Abschnitt 4). Das steht so in der
  Datenschutzerklärung, in beiden Sprachen.
- **Opt-in, zweimal**: Messen ist aus, bis der Fahrer es einschaltet;
  den Bestwert zu teilen ist ein eigener Schalter (Frage 1) — wer nur
  für sich misst, schickt nichts.
- **Nutzungsbedingungen**: Satz zum Risiko und dass Werte geschätzt
  sind; kommt mit der rechtlichen Prüfung (#39), vor dem Store.
- **Löschen**: Konto löschen und „Meinen Beitrag löschen" nehmen die
  Bestwerte mit; die Werte in den Fahrten löscht, wer die Fahrt löscht.

## 8. Messplan (vor dem Bau der Erkennung)

Wie beim Routing: erst messen, dann Schwellen setzen
(`docs/trail-abgleich-messung.md`, `docs/routing-messung.md` als
Muster).

1. **Rohdaten-Logger als Entwicklerschalter** (nur in der
   Vorabversion, nur lokal): schreibt 100 Hz Beschleunigung und Kreisel
   plus GPS in eine Datei neben der Fahrt; Export als Datei für den
   Rechner des Betreibers — nie ins Repo (A7).
2. **Fahrten mit Ansage**: der Betreiber fährt eine bekannte Jump-Line
   mit Lenkerhalterung und mit Hosentasche, zählt die Sprünge und
   schätzt die längsten; dazu ein Trail ohne Sprünge (Wurzeln, Stufen)
   als Gegenprobe und zehn Würfe des Telefons auf eine Jacke.
3. **Auswertung auf dem Rechner** (`tool/airtime_measure.py`): Treffer,
   Fehlalarme und Dauerfehler je Schwelle (g-Grenze, Mindestdauer) und
   je Halterung; Akku je Stunde mit und ohne Sensor.
4. **Schwellen gelten, wenn** auf der Gegenprobe keine Fehlalarme
   liegen, auf der Jump-Line ≥ 90 % der gezählten Sprünge gefunden
   werden und der Akku je Stunde um höchstens 5 Prozentpunkte stärker
   sinkt als ohne Sensor. Sonst fällt die Halterung, die es nicht
   schafft, aus der Tabelle in Abschnitt 2.

Umgebung: 📱 Fahrten · 💻 Auswertung (eigene Fahrten) · ☁️ Werkzeug.

## 9. Umsetzung in Schritten (je ein PR)

1. **Sensor im Dienst** (Probe, kein Bump falls nur Werkzeug): Liefert
   ein Sensor-Plugin im Isolate des Vordergrund-Dienstes Ereignisse,
   auch bei ausgeschaltetem Bildschirm? Ergebnis in
   `lib/features/rides/CLAUDE.md`.
2. **Rohdaten-Logger** (Entwicklerschalter, Vorabversion) — dann die
   Messung aus Abschnitt 8.
3. **Erkennung auf dem Gerät**: Airtime, Max G, Manual als reine
   Funktionen mit Tests gegen die gemessenen Aufzeichnungen (als
   synthetische Reihen nachgebaut, keine echten Dateien im Repo);
   Ereigniszeilen in der Fahrt; Schalter und Halterung im Start-Blatt.
4. **Anzeige**: Werte-Kacheln, AIR-Toast, „Trail geschafft", Zerlege-
   Blatt, Bild-im-Bild, Benachrichtigung — alles lokal, noch nichts
   geteilt.
5. **Bestwert und Rangliste**: Patch mit Tabelle und RLS, Hochladen
   über den Ausgangskorb, Zeile im Trail-Blatt, Datenschutzerklärung,
   `play-console.md`, Zusammenführen (#107) nimmt sie mit.

Schritte 3–5 sind sichtbare Funktionen: je ein Eintrag in
`kFeatureHighlights` mit Vorführung.

## 10. Risiken, benannt

- **Der Sensor läuft im Dienst nicht** (Schritt 1) ⇒ nativer Teil im
  Android-Dienst; mehr Aufwand, kein Grund zum Abbruch.
- **Fehlalarme auf ruppigen Trails** ⇒ ein Sprung ohne Flugphase ist
  keiner; die Gegenprobe in Abschnitt 8 ist Pflicht.
- **Akku**: 100 Hz über Stunden. Nur auf Trails messen hält den Anteil
  klein (Trails sind ein Bruchteil einer Runde).
- **Schummeln** ist trivial und wird nicht verhindert — nur unter
  Buddys, die sich kennen, ist das ein Witz, kein Betrug.
- **Risiko-Anreiz**: Rangliste nur auf Airtime je Durchfahrt, nicht auf
  Max G; kein Push; der Satz beim Einschalten.

## 11. Offene Entscheidungen des Betreibers

Jede mit Empfehlung; entschieden wird im Issue (#36), dieses Dokument
zieht nach.

1. **Was teilen?** (a) Bestwert je Trail mit Monat, eigener Schalter
   — *empfohlen*; (b) jede Durchfahrt mit Datum (mehr Spiel, aber ein
   Verlauf, wer wann wo war — nah an A3); (c) gar nichts teilen, nur
   eigene Werte und ein Bild zum Verschicken per Nachricht (#34).
2. **Welche Werte in die Rangliste?** Nur Airtime — *empfohlen*; Max G
   und Manual bleiben eigene Werte auf dem Gerät. Alternative: alle
   drei je eigene Rangliste.
3. **Welche Airtime zählt?** Summe je Durchfahrt — *empfohlen*, wie im
   Entwurf; Alternative: längster Sprung.
4. **Bio und E-MTB gemeinsam?** Ja — *empfohlen*; getrennt nur, wenn
   die Messung zeigt, dass der Motor die Airtime merklich ändert.
5. **Manual überhaupt in v1?** Erst nach Airtime und Max G —
   *empfohlen*: braucht den Kreisel, eine Lenkerhalterung und eine
   eigene Messung; die Kachel bleibt bis dahin aus.
6. **Wann?** Nach 🚀 A und den ersten Testern — *empfohlen*: ohne
   Buddys mit der App gibt es keine Rangliste, und die Messung braucht
   Fahrten mit Ansage (📱).
