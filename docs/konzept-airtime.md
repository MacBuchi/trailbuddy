# Konzept: Trail-Werte und Airtime unter Buddys (#36)

*Stand 2026-10-30, Entscheidungen des Betreibers vom 2026-10-16 in
Abschnitt 11, Punkt 5 neu entschieden am 2026-10-30. Baut auf `konzept-trails.md`
Abschnitt 7 und 9 und auf den Kernanforderungen (`anforderungen.md`,
A1–A3, A6, A10, A11) auf; das Aussehen kommt aus dem Navi-Entwurf
(`docs/design/navi/`, Betreiber 2026-10-13: „Trail-Werte … kommen mit
#36"). Gebaut wird nichts, bevor die Schwellen aus Abschnitt 8 gemessen sind.*

## 0. Worum es geht, in fünf Sätzen

Während einer Fahrt misst das Telefon auf Trails drei Werte: **Airtime**
(Sprünge aus der Schwerelosigkeit im Beschleunigungssensor), **Max G**
(die härteste Landung) und **Manual** (Vorderrad hoch, aus dem Kreisel,
nur mit Lenkerhalterung). Gemessen und gespeichert wird auf dem Gerät,
die Werte hängen an der Fahrt wie heute die Bestätigungen (#116). Zum
Server geht — wenn der Fahrer es will — **ein Bestwert je Trail** und
**ein Airtime-Zähler der letzten 30 Tage**, beide auf dem Gerät
gerechnet; kein Verlauf und keine Fahrt. Sehen können das nur direkte
Buddys. Daraus werden eine **Rangliste unter Buddys je Trail** und
**Titel** wie „Segelflieger" oder „Bruchpilot" (Betreiber,
2026-10-16), die sich ausdrücklich als Spiel ausgeben, nicht als
Rekord. Es gibt kein Netz-Ranking und keinen Wert, den jemand
außerhalb des eigenen Buddy-Kreises sieht.

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
  Landung. Anders als die Dauer eines Sprungs ist das nicht trivial
  (Betreiber, 2026-10-16): Ein abgesetzter Rucksack, ein umfallendes
  Rad, ein Telefon, das auf den Boden fällt, sind ein harter Stoß nach
  einer Flugphase. Gezählt wird eine Landung deshalb nur, wenn sie
  **plausibel** ist — alle vier Bedingungen:
  1. **vorher geflogen**: eine erkannte Flugphase (Airtime-Regel) endet
     im Stoß;
  2. **in Fahrt davor und danach**: GPS-Tempo ≥ 10 km/h in den 3 s
     vor dem Absprung UND in den 3 s nach der Landung — wer absetzt,
     umfällt oder stürzt, steht danach;
  3. **auf der Linie**: beide Fixe ≤ 20 m vom Trail (Regel aus
     Abschnitt 3);
  4. **im Rahmen**: Spitze unter einer Obergrenze (Startwert 8 g) —
     darüber ist es ein Aufschlag des Telefons, kein Rad.
  Schläge ohne vorherige Flugphase (Wurzel, Stufe) zählen nie; sonst
  misst der Wert den Untergrund. Bedingung 2 trennt nebenbei Sturz von
  Landung — ein Sturz wird nicht als Wert gezeigt.
- **Manual**: Neigung über 15° gegen die Fahrposition bei Fahrt
  (> 8 km/h), Länge in Metern aus GPS-Tempo × Zeit (Entwurf, Zustand
  „Manual erkannt"). Nur mit Lenkerhalterung: In der Tasche kippt das
  Telefon nicht mit dem Rad. **Wheelie und Manual sind für den Sensor
  dasselbe** (Vorderrad hoch); ob dabei getreten wird, sieht das Telefon
  am Lenker kaum, getrennt wird deshalb nicht. In v1 (Betreiber,
  2026-10-30): je Fahrt und Trail ein **Zähler** und der **längste in
  Metern**, als Zahl nur auf dem Gerät (Abschnitt 4). Ein Kippen in der
  Kurve dreht das Telefon um eine andere Achse als ein Wheelie — ob
  sich beides trennen lässt, zeigt die Messung (8.2).
  **Die Übergangsregel** (0.143.0, `wheelie_detector.dart` und gleich
  im Werkzeug; wird mit Schritt 4 in Abschnitt 9 durch den Pitch aus
  Abschnitt 3a ersetzt): Schwerkraft = Mittel über 0,5 s; die
  Fahrposition = Median der letzten 60 s in Fahrt und nicht gekippt,
  frühestens nach 10 s davon (das Ende der Fahrt kennt die App nicht);
  Ende unter 10° (Hysterese, ein Wackeln an der Schwelle bleibt EIN
  Wheelie) oder unter dem Tempo; ab 1 s; über 60 s gilt es als
  verrutschte Halterung — neu lernen, nichts zählen.
- **Nur auf Trails** und nur, wenn eingeschaltet („Trail-Werte messen"
  im Start-Blatt). Auf der Anfahrt läuft kein Sensor — das spart Akku
  und macht aus einem Bordstein keinen Sprung.

Alle Schwellen oben sind Startwerte aus der Literatur und dem Entwurf,
**keine gemessenen** — Abschnitt 8. Und alle gelten für die
**aufbereiteten** Größen aus Abschnitt 3a, nicht für Rohwerte: Die
zwei ersten Messfahrten (2026-10-30) haben gezeigt, dass die geglättete
Beschleunigung Bremsen, Kurve und Schlag nicht von Neigung trennt.

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

## 3a. Signalaufbereitung (entschieden 2026-10-30)

Erst aufbereiten, dann erkennen (Betreiber, 2026-10-30). Die Recherche
mit Quellen und verworfenen Alternativen steht in
`docs/recherche-sensorfusion.md`; die Architektur ist abgenommen. Drei
Stufen, jede für sich testbar:

1. **Halterung**: lernt die Lage des Telefons am Rad selbst — „unten"
   aus der Schwerkraft bei ruhiger Geradeausfahrt, „vorn" aus der
   Beschleunigung beim Bremsen und Antreten (Vorzeichen aus dem
   GPS-Tempo), erkennt Verrutschen. Damit ist die Kipprichtung bekannt:
   nur Front hoch ist ein Wheelie.
2. **Lage-Filter**: Error-State-Kalman (6 Fehlerzustände: Lage, Gyro-
   Bias), Vorhersage mit dem Kreisel und den echten Zeitstempeln; die
   Beschleunigung stützt die Lage erst, nachdem das **Fahrradmodell**
   abgezogen ist (längs dv/dt aus GPS, quer Tempo × Gierrate); was es
   nicht erklärt (Schlag, Flug, Vibration), wird über eine adaptive
   Unsicherheit ausgeblendet. Ergebnis: Pitch und Roll im Radsystem,
   Beschleunigung ohne Schwerkraft in Radachsen, eine Unsicherheit.
   Mahony mit derselben Korrektur läuft im Prototyp als Vergleich — ist
   er gleich gut, nimmt die App den einfacheren.
3. **Ereignisse**: Wheelie = Pitch gegenüber dem Weg (Weg = Mittel des
   Pitch über einige Sekunden); Airtime = gefilterter Betrag unter der
   Schwelle, plausibel über Lage und Tempo davor und danach; Landung =
   Spitze in Rad-Hochachse.

Bewertet wird mit den Antworten auf die Banner (Schritt 2b in
Abschnitt 9) und mit Proben auf jeder Fahrt: im Stand die Halterung,
beim kräftigen Bremsen **kein** Pitch, in der Kurve Roll statt Pitch.

## 4. Was das Gerät verlässt

Der eine Datensatz, der zum Server geht, ist **der eigene Bestwert je
Trail**:

| Feld | Bedeutung |
|---|---|
| Nutzer, Trail | wer, auf welchem Trail (Trail-Kennung, besitzerlos) |
| Airtime je Durchfahrt | die beste Summe einer Durchfahrt, in Zehntelsekunden |
| längster Sprung | der längste einzelne, in Zehntelsekunden |
| Monat | wann der Bestwert entstand — ein Monat, kein Tag |

Dazu **je Nutzer eine Zeile** mit dem **Airtime-Zähler der letzten
30 Tage** (Betreiber, 2026-10-16: „ein Airtime Counter im rollenden
Monat"), über alle Trails:

| Feld | Bedeutung |
|---|---|
| Nutzer | wer |
| Airtime 30 Tage | Summe aller gezählten Sprünge der letzten 30 Tage, in Sekunden |
| Stand | der Tag, an dem das Gerät den Wert zuletzt gerechnet hat |
| Titel | die Titel, die das Gerät gerade vergibt (Abschnitt 5) |

- **Das Gerät rechnet das Fenster, nicht der Server.** Es summiert aus
  seinen eigenen Fahrten und schickt EINE Zahl, überschrieben bei jeder
  Fahrt und beim Öffnen der App. Tagessummen auf dem Server würden
  verraten, an welchen Tagen jemand gefahren ist (A3); eine Zahl mit
  Stand verrät nur, dass er in den letzten 30 Tagen gefahren ist.
- **Ein alter Stand altert sichtbar**: Wer die App länger nicht öffnet,
  dessen Zähler zeigen Buddys mit „Stand 12.10." — das Fenster rückt
  nicht ohne sein Gerät weiter. Nach 30 Tagen ohne neuen Stand zeigt
  die App ihn nicht mehr.
- **Keine Zeitreihe, keine Fahrt, kein Ort am Sprung.** „Bei km 2,1"
  aus dem Entwurf bleibt auf dem Gerät.
- **Max G und Manual bleiben als Werte auf dem Gerät** (entschieden,
  Frage 2): Max G als Rangliste belohnt harte Landungen — genau das
  Risiko aus 1.3; Manual misst nur, wer einen Lenkerhalter hat. Was
  von Max G geteilt wird, ist höchstens ein Titel, nie die Zahl.
- **Ein Wert wird nur besser oder gelöscht**: Hochladen nur, wenn der
  neue Bestwert den alten schlägt; „Meinen Beitrag löschen" am Trail
  löscht ihn mit (`supabase/CLAUDE.md`, „Beitrag löschen").
- **Sichtbar** für den Nutzer selbst und für direkte Buddys; der
  Bestwert je Trail nur für Buddys, die den Trail selbst sehen (A2) — dieselbe RLS-Form wie die Bewertungen am
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
- **Der Zähler der letzten 30 Tage** steht an jedem Buddy (Buddy-Liste
  und Profil des Buddys: „Airtime 30 Tage: 42 s") und im eigenen
  Profil. Eine sortierte Bestenliste daraus gibt es nicht — er ist ein
  Wert am Buddy, kein Wettbewerb über das Netz.
- **Titel statt Tabellen** (Betreiber, 2026-10-16: „so was wie
  Bruchpilot und Segelflieger"): ein Abzeichen am Buddy, mit
  Augenzwinkern. Das Gerät vergibt sie aus den EIGENEN Werten und
  schickt nur den Namen des Titels mit (Abschnitt 4); Vergleiche
  zwischen Buddys rechnet die App des Betrachters aus dem, was sie
  sieht. Startliste — Namen und Schwellen nach der Messung, die Liste
  ist offen:

  | Titel | wofür | aus |
  |---|---|---|
  | Segelflieger | ein einzelner Sprung ≥ 1,0 s in den letzten 30 Tagen | Airtime |
  | Vielflieger | die meisten Sprünge unter den eigenen Buddys im Fenster | Airtime-Zähler (beim Betrachter gerechnet) |
  | Bruchpilot | eine plausible Landung über einer hohen Schwelle (Startwert 4 g) | Max G, nur der Titel |
  | Bodenpersonal | im Fenster gefahren, aber kein Sprung | Airtime |
  | Trailkönig | Platz 1 der Airtime auf einem Trail unter den eigenen Buddys | Bestwert je Trail (beim Betrachter) |

  „Bruchpilot" ist der Weg, Max G spielerisch zu zeigen, ohne die Zahl
  zu teilen: Ein Titel belohnt eine harte Landung einmal, eine
  Rangliste jedes Mal mehr. Der Titel kommt erst, wenn die
  Plausibilisierung aus Abschnitt 2 gemessen ist.
- Wer will, sieht in „Meine Fahrten" seine eigenen Werte je Fahrt —
  das ist ein Tagebuch, keine Rangliste.
- **Bio und E-MTB werden nicht getrennt**: Airtime hängt am Fahrer und
  an der Line, kaum am Motor (Frage 4 als Kontrolle).
- **Kein Push für Ranglisten oder Titel**: „Jan hat dich überholt" wäre
  genau die Aufmerksamkeit, die Konzept 7 nicht will.

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
  Trail, der Zähler der letzten 30 Tage und die Titel gehen weg
  (Abschnitt 4). Das steht so in der
  Datenschutzerklärung, in beiden Sprachen.
- **Opt-in, zweimal**: Messen ist aus, bis der Fahrer es einschaltet;
  den Bestwert zu teilen ist ein eigener Schalter (Frage 1) — wer nur
  für sich misst, schickt nichts.
- **Nutzungsbedingungen**: Satz zum Risiko und dass Werte geschätzt
  sind; kommt mit der rechtlichen Prüfung (#39), vor dem Store.
- **Löschen**: Konto löschen nimmt Bestwerte, Zähler und Titel mit,
  „Meinen Beitrag löschen" den Bestwert an dem Trail; Teilen
  ausschalten löscht Zähler und Titel; die Werte in den Fahrten löscht, wer die Fahrt löscht.

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
   als Gegenprobe und zehn Würfe des Telefons auf eine Jacke. Für die
   Plausibilisierung von Max G dazu: Rucksack mit Telefon absetzen,
   Rad mit Telefon am Lenker umfallen lassen, Telefon aus der Hand
   fallen lassen — je fünfmal; keiner davon darf als Landung zählen.
   Für Wheelie/Manual (Lenkerhalterung): zehn Wheelies oder Manuals mit
   geschätzter Länge, dazu enge Kurven und ein an den Baum gelehntes Rad
   als Gegenprobe — keines davon darf als Wheelie zählen.
3. **Auswertung auf dem Rechner** (`tool/airtime_measure.py`, seit
   0.142.0): Flugphasen je g-Grenze und Mindestdauer, je Phase die
   Landespitze und ob sie plausibel ist (Tempo vorher und nachher,
   Obergrenze; „auf der Linie" bleibt der App); Wheelies je Kippwinkel
   und Mindestdauer mit Länge und Kippachse; `--from`/`--to` schneidet
   ein Stück der Fahrt heraus (Jump-Line, Gegenprobe), `--list` nennt
   jedes Ereignis. Ausgabe nur Zeiten ab Dateibeginn, Dauern und
   Zählungen. Treffer und Fehlalarme gegen die gezählten Sprünge je
   Halterung; Akku je Stunde mit und ohne Sensor (Ladestand am Anfang
   und Ende der Fahrt notieren).
4. **Schwellen gelten, wenn** auf der Gegenprobe keine Fehlalarme
   liegen (auch keine Landung aus den Absetz- und Umfall-Proben), auf der
   Jump-Line ≥ 90 % der gezählten Sprünge gefunden
   werden und der Akku je Stunde um höchstens 5 Prozentpunkte stärker
   sinkt als ohne Sensor. Sonst fällt die Halterung, die es nicht
   schafft, aus der Tabelle in Abschnitt 2.

Umgebung: 📱 Fahrten · 💻 Auswertung (eigene Fahrten) · ☁️ Werkzeug.

**Erste Fahrt** (2026-10-30, Straße, E-Bike, Telefon liegend in
Fahrtrichtung am Oberrohr, 17 min): 111 Hz, eine Lücke über 100 ms —
der Sensor liefert im Dienst (ob der Bildschirm aus war, ist nicht
notiert). Bei 15°/1 s 17 Wheelies und Manuals von 1 bis 28 s, fast alle
um dieselbe Achse (die Querachse des Telefons); der Kreisel zeigt an
denselben Stellen eine echte Drehung von 25–45°, Bremsen allein wäre
keine. Manuals kamen auch bei über 35 km/h. Ohne Zählung des Fahrers
lässt sich daraus keine Trefferquote ablesen — deshalb die Rückmeldung
am Gerät (Schritt 2b).

**Der Logger** (0.142.0, `lib/features/rides/sensor_log.dart`): Schalter
„Sensor-Rohdaten mitschreiben" unter „Über TrailBuddy", nur in der
Dev-App (Flavor `dev`, `android/CLAUDE.md`). Gilt ab der nächsten
Fahrt; der Dienst schreibt Beschleunigung (mit Schwerkraft) und Kreisel
mit 100 Hz und GPS jede Sekunde nach `rides/sensors/<Fahrt>.csv`
(~30 MB je Stunde), „Meine Fahrten" → „Sensordaten teilen" bringt die
Datei an den Rechner.

## 9. Umsetzung in Schritten (je ein PR)

1. **Sensor im Dienst** und 2. **Rohdaten-Logger** in EINEM PR
   (0.142.0): Der Logger ist die Probe — `sensors_plus` im Isolate des
   Vordergrund-Dienstes; ob er bei ausgeschaltetem Bildschirm liefert,
   zeigt die Datei der ersten Fahrt am Gerät (Lücken über 100 ms nennt
   das Werkzeug). Ergebnis in `lib/features/rides/CLAUDE.md`. Dann die
   Messung aus Abschnitt 8.
   2b. **Wheelie mit Rückmeldung** (0.143.0, nur Dev-App, am Schalter
   der Rohdaten): Die Regel aus Abschnitt 2 läuft zur Laufzeit im
   Dienst; nach jedem Wheelie ein Banner („Stimmt" / „War keiner"),
   während der Fahrt eine stehende Benachrichtigung mit „Wheelie
   verpasst". Ereignis und Antworten sind Zeilen der Rohdaten (`e`, `l`,
   `m`); das Werkzeug zählt daraus je Schwelle Treffer, Verpasste und
   Fehlalarme — die Zählung von Hand aus 8.2 entfällt für Wheelies.
Ab hier nach der Signalaufbereitung (Abschnitt 3a), bewusst in wenigen,
großen Schritten (Betreiber, 2026-10-30: „nicht zu feingliedrig, wir
wollen auch fertig werden"):

3. **Fusion offline** (ein PR; ☁️ Code, 💻 Auswertung):
   `tool/sensor_fusion.py` mit allen drei Stufen aus 3a (ESKF und
   Mahony zum Vergleich), `tool/airtime_measure.py --fused` rechnet
   Wheelie, Flug und Landung darauf, Selbsttests in CI. Ergebnis auf den
   vorhandenen Fahrten als Zählungen in
   `docs/recherche-sensorfusion.md`. Fertig, wenn die Proben aus 3a auf
   den Fahrten bestehen und die Fehlalarme der Übergangsregel (Front
   runter, Schläge) verschwinden.
   **Gleichzeitig 📱**: Fahrten mit Ansage und der Dev-App 0.143.0,
   jedes Banner beantworten — fünfmal kräftig bremsen und antreten,
   enge Kurven, 5–10 Wheelies/Manuals, Bordstein hoch und runter,
   absteigen und schieben, Rad anlehnen; Bildschirm aus, Akku vorher
   und nachher.
4. **Fusion in der Dev-App** (ein PR): die drei Stufen in Dart, rein
   und mit denselben synthetischen Reihen wie das Werkzeug geprüft;
   Wheelie auf dem Pitch gegenüber dem Weg, dazu Sprung und Landung —
   mit Bannern wie 2b („Sprung erkannt", „Stimmt" / „War keiner",
   „Sprung verpasst"), der Messbereich des Sensors in den Kopf der
   Rohdaten. Gegenprobe: Dart und Werkzeug finden auf den Messfahrten
   dieselben Ereignisse.
   **Danach 📱**: Abnahmefahrten nach Abschnitt 8 (Jump-Line,
   Gegenproben-Trail, Absetzen und Umfallen); die Schwellen gelten nach
   8.4, gezählt aus den Banner-Antworten.
5. **Trail-Werte in der App** (ein PR, vorher 3 und 4): Schalter und
   Halterung im Start-Blatt, nur auf Trails, Ereigniszeilen in der
   Fahrt; Werte-Kacheln, AIR-Toast, „Trail geschafft", Zerlege-Blatt,
   Bild-im-Bild, Benachrichtigung — alles lokal, noch nichts geteilt.
6. **Bestwert, Zähler, Rangliste und Titel** (ein PR, vorher 5 und 6):
   Patch mit den zwei Tabellen und RLS, Hochladen über den
   Ausgangskorb, Zeile im Trail-Blatt, Zähler am Buddy,
   Datenschutzerklärung, `play-console.md`, Zusammenführen (#107) nimmt
   die Bestwerte mit; Segelflieger, Vielflieger, Bodenpersonal,
   Trailkönig — Bruchpilot erst, wenn die Max-G-Plausibilisierung
   gemessen ist.

Schritte 5 und 6 sind sichtbare Funktionen: je ein Eintrag in
`kFeatureHighlights` mit Vorführung. Schritte 3 und 4 betreffen nur das
Werkzeug und die Dev-App.

## 10. Risiken, benannt

- **Der Sensor läuft im Dienst nicht** (Schritt 1) ⇒ nativer Teil im
  Android-Dienst; mehr Aufwand, kein Grund zum Abbruch.
- **Fehlalarme auf ruppigen Trails** ⇒ ein Sprung ohne Flugphase ist
  keiner; die Gegenprobe in Abschnitt 8 ist Pflicht.
- **Max G aus Absetzen, Umfallen, Fallenlassen** ⇒ die vier
  Bedingungen aus Abschnitt 2; scheitern sie in der Messung, gibt es
  „Bruchpilot" nicht und Max G bleibt eine eigene Kachel.
- **Akku**: 100 Hz über Stunden. Nur auf Trails messen hält den Anteil
  klein (Trails sind ein Bruchteil einer Runde).
- **Schummeln** ist trivial und wird nicht verhindert — nur unter
  Buddys, die sich kennen, ist das ein Witz, kein Betrug.
- **Risiko-Anreiz**: Rangliste nur auf Airtime je Durchfahrt, nicht auf
  Max G; kein Push; der Satz beim Einschalten.

## 11. Entscheidungen des Betreibers (2026-10-16)

Alle sechs entschieden; die Vorschläge stehen dabei, damit die nächste
Diskussion nicht bei null beginnt.

1. **Was teilen?** Bestwert je Trail mit Monat, eigener Schalter — wie
   vorgeschlagen; **dazu** ein Airtime-Zähler je Buddy über die letzten
   30 Tage („Jeder Buddy hat vielleicht auch einen Airtime Counter im
   rollenden Monat"), auf dem Gerät gerechnet (Abschnitt 4). Verworfen:
   jede Durchfahrt mit Datum (ein Verlauf, nah an A3); gar nichts
   teilen.
2. **Welche Werte?** Airtime in Rangliste und Zähler; Max G und Manual
   bleiben als Zahlen auf dem Gerät. **Neu:** spielerische Titel wie
   „Bruchpilot" und „Segelflieger" (Abschnitt 5) — Max G nur als Titel
   und nur plausibilisiert, weil „Rucksack absetzen, Fahrrad fällt um
   usw." sonst als Landung zählen.
3. **Welche Airtime zählt?** Die Summe („Airtime die Summe").
4. **Bio und E-MTB gemeinsam** — wie vorgeschlagen.
5. **Wheelie/Manual in v1** (neu entschieden 2026-10-30; am 2026-10-16
   noch „nicht in v1"): Zähler und längster in Metern, nur mit
   Lenkerhalterung, bleibt als Zahl auf dem Gerät wie Max G (Abschnitt
   2). Verworfen: der längste Wheelie als geteilter Bestwert mit
   Rangliste — er misst nur, wer einen Lenkerhalter hat.
6. **Wann?** Nach 🚀 A und den ersten Testern — wie vorgeschlagen.
