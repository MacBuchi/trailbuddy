# TrailBuddy auf der Garmin-Uhr — Konzept

*Angelegt am 2026-11-03. Anlass: Der Betreiber will das Handy nicht mehr
ans Rad kleben und unterwegs nicht herauskramen; die Uhr am Lenker oder
am Handgelenk soll die Navigation zeigen. Erstes Gerät ist die fēnix 5
des Betreibers. Dieses Dokument kommt vor dem ersten Code.*

## 0. Entscheidungen des Betreibers (2026-11-03)

1. **Die Uhr ist Anzeige, nicht Sensor.** Die fēnix 5 hat keinen
   Kreisel, nur Beschleunigung, Magnetfeld und Barometer; ohne Kreisel
   gibt es im Flug keine Lage und beim Bremsen keine verlässliche
   (`docs/recherche-sensorfusion.md`, Abschnitt 2). Messen bleibt Sache
   des Handys, später eines eigenen Lenkergeräts.
2. **A5 bekommt eine Ausnahme wie bei #398.** Die Uhr-App läuft über
   Connect IQ: Die Garmin-Connect-App auf dem Handy reicht die
   Nachrichten an die Uhr weiter. Das ist keine Kopplung — TrailBuddy
   hat kein Garmin-Konto und schickt Garmin nichts über Trails, Fahrten
   oder Buddys; die Uhr-App zeichnet keine Garmin-Aktivität auf (die
   ginge sonst an Garmin Connect, Abschnitt 4).
3. **A12 bekommt einen Satz für die Uhr: Vibrieren beim Abkommen.** Die
   Uhr zeigt wie der Navigationsmodus der App (Route, Position, Abstand)
   und vibriert zusätzlich, wenn man die Route verlässt. Das ist eine
   Warnung, kein Abbiegehinweis: keine Meter bis zum Abzweig, kein
   Vibrieren vor einer Kreuzung, kein Ton. Die App selbst bleibt still.
4. **Der Code liegt in `garmin/` in diesem Repo.** Dann ändern sich
   Protokoll, Android-Brücke und Uhr-App im selben PR.

## 1. Was die Uhr zeigt

Eine Ansicht, angelehnt an die Folgeansicht der App
(`docs/konzept-routing.md` 9.2 und 9.9, Design 13), geschnitten für
240 × 240 Pixel MIP (64 Farben, in der Sonne gut lesbar, kein Touch).
Entwurf im Designer am 2026-11-04 (Betreiber: „nutze den Designer, um
das Garmin-App-Design zu optimieren"): helle Karte wie in der App, darunter eine
dunkle Infofläche, „Was kommt als Nächstes?" statt „Wie weit noch?".

- **Die Route als Band**, gedreht in Fahrtrichtung: in Bewegung nach
  dem GPS-Kurs, im Stand nach dem Kompass der Uhr — die fēnix 5 hat
  einen Magnetfeldsensor, und gerade an einer Kreuzung im Stand kennt
  das GPS die Richtung nicht. Die eigene Position steht im unteren Teil
  der Karte (y 128 von 240), damit mehr voraus zu sehen ist; der
  gefahrene Teil ist eine dünne Linie in Moos (Design 2, „B+"). Am
  Rand ein „N" für Norden.
- **Die Trails der Route in ihrer Farbe** (S-Grad, Design 2), am
  Trailkopf voraus ihr Schild als Form (○ ● ■ ◆, Design 6): auf MIP
  die nächste der 64 Farben zu `AppColors.mapGrades`; geprüft am Gerät,
  nicht nur im Simulator.
- **Abzweigungen an Kreuzungen** (Betreiber, 2026-11-04: „muss nicht
  der ganze Weg sein"): je Kreuzung der Route ein Stummel des
  abgehenden Wegs, 40 m, dünn in Grau unter dem Band. Man sieht, DASS
  man abbiegen kann und wohin die Route geht — ohne Kartenbild und ohne
  Abbiegehinweis (Entscheidung 3).
- **Unten die Infofläche** (schwarz, ab y 168 — darunter wird der Kreis
  zu schmal für zwei Zeilen): vor einem Trail dessen Schild und Name,
  darunter Weg und Anstieg bis zum Trailkopf; auf dem Trail Schild,
  Name, ein Balken des gefahrenen Anteils in S-Farbe und der Rest; ohne
  Trail voraus „BIS ZUM ZIEL" mit Rest-km und Rest-hm. Abseits wird die
  Fläche zur Warnfarbe mit dem Abstand, dazu ein gestrichelter Strich
  und ein Pfeil zum Punkt der Linie 50 m voraus (wie 9.3).
- **„Angekommen"** wie in der App (unter 30 m vom Ende bzw. letzter
  Abschnitt einer Runde), mit Länge und Höhenmetern der Route.
- **Vibrieren beim Abkommen** (Entscheidung 3): einmal, wenn „abseits"
  beginnt — dieselbe Regel wie 9.3 (mehr als 30 m neben der Linie, zwei
  Fixe in Folge). Kein zweites Vibrieren, bis man wieder auf der Linie
  war; nichts beim Zurückkommen, nichts vor Abzweigen.
- **Tasten**: hoch/runter zoomt (drei Stufen: 1, 2,5 und 6 m je Pixel),
  START schaltet zwischen Karte und einer dunklen Zahlenseite (Tempo,
  Zeit, Höhe, Rest; klein Akku und Speicher für die Messungen), ZURÜCK
  beendet nach Rückfrage. Tippziele gibt es nicht; A13 heißt hier:
  große Schrift, kräftige Linien.

Kein Kartenbild: Die fēnix 5 hat keine Karten, und Kacheln passen nicht
in den Speicher einer App (Abschnitt 7). Gezeigt werden nur Route,
Trails der Route und die Stummel der Abzweigungen.

## 2. Was auf die Uhr geht

Dasselbe, was der Navigationsmodus navigiert (9.1): ein Planer-Ergebnis,
eine geplante oder eine eigene Fahrt. Beim Start der Navigation in der
App steht, wenn eine Uhr verbunden ist, ein Schalter „Auf der Uhr
zeigen" (Vorgabe an). Dann schickt die App die Route einmal; die Uhr
legt sie in ihren eigenen Speicher und navigiert **ab da selbst** — mit
eigenem GPS, ohne Handy, ohne Netz (A8). Das Handy darf in der Tasche
bleiben, schlafen oder die Verbindung verlieren.

Was die Nachricht trägt:

- die Linie, vereinfacht (Douglas-Peucker, Startwert 5 m) und als
  Ganzzahlen in Schritten von 1e-5° gegen den Vorgänger; Höhen in
  Metern, falls vorhanden;
- die Abschnitte: von Punkt, bis Punkt, S-Grad, Name — nur die Trails
  DIESER Route, die der Nutzer in der App ohnehin sieht (A1, A2);
- die Abzweigungen: je Kreuzung der Route der Punkt und das Ende eines
  40-m-Stummels des abgehenden Wegs, aus dem Wegegraphen des Planers
  (OSM-Wege und eigene Trails, keine fremden — A1, A2);
- Kopf: Protokollversion, Länge, Höhenmeter, eine Kennung der Route.

Die Form steht in `garmin/source/NavRoute.mc` (Schlüssel `v`, `id`,
`pts`, `ele`, `sec`, `br`); G1 liest sie schon aus der Ressource,
`tool/garmin_route.py` schreibt sie. **Höchstens 2000 Punkte**
(Messung 8.1): darüber vereinfacht die App stärker, bis es passt.

Die Uhr schickt zurück: „angekommen und gespeichert" mit der Kennung,
sonst nichts. Keine Position, keine Fahrt (A3).

## 3. Der Weg vom Handy zur Uhr

- **Android**: das Connect-IQ-Companion-SDK von Garmin, eingebunden als
  kleine native Brücke (Kotlin, `MethodChannel`), wie die anderen
  Dienste unter `android/`. Voraussetzung ist die Garmin-Connect-App,
  mit der die Uhr gekoppelt ist. Fehlt sie oder ist keine Uhr da,
  erscheint der Schalter nicht.
- **Web**: keine Uhr. Wie das Aufzeichnen bleibt das Android (A9).
- **Nachrichten klein halten.** Wie groß eine Nachricht werden darf und
  wie lange die Übertragung dauert, ist zu messen (Abschnitt 8);
  notfalls geht die Route in Stücken mit Laufnummer.
- **Ohne eigene App, per Datei**: Die App kann die Route heute schon als
  GPX exportieren. Über USB in `GARMIN/NEWFILES/` macht die Uhr daraus
  einen eigenen Kurs und navigiert mit Garmins Navigation. Das bleibt
  der Weg für Uhren ohne unsere App und für alle, die Garmin Connect
  nicht wollen; die Kurzanleitung nennt ihn, wenn die Uhr-App kommt.
  Eine Connect-IQ-App selbst kann keine Dateien vom Laufwerk lesen —
  für sie geht es nur über Connect IQ.

## 4. Was die Uhr bewusst nicht tut

- **Keine Garmin-Aktivität** (`ActivityRecording`): Sie ginge beim
  nächsten Abgleich an Garmin Connect, und eine Fahrt beginnt an der
  Haustür (A3, A5). Aufgezeichnet wird wie bisher auf dem Handy.
- **Kein Netz von der Uhr aus** (`makeWebRequest`): kein neuer Host
  (A6), keine Daten an uns oder Dritte.
- **Keine Sensor-Rohdaten**, keine Airtime, keine Sprünge
  (Entscheidung 1).
- **Keine Buddy-Daten über die Route hinaus**, keine Meldungen, keine
  Hinweise — das bleibt in der App.
- **Keine Abbiegehinweise** (Entscheidung 3, A12).

## 5. Verteilung

1. **Erst nur der Betreiber**: Die Uhr-App wird lokal gebaut und per
   USB in `GARMIN/APPS/` kopiert. Der Entwicklerschlüssel liegt beim
   Betreiber, nie im Repo (A7).
2. **Dann der Connect-IQ-Store** — eigene Entscheidung des Betreibers,
   wenn die Uhr-App am Gerät abgenommen ist: Entwicklerkonto, App-ID,
   Prüfung durch Garmin. Mit der Android-Brücke kommen in denselben PR
   der Satz zur Garmin-Connect-App in `web/datenschutz.html` und
   `web/privacy.html` und die Paket-Sichtbarkeit in `docs/play-console.md`
   (A6).

## 6. Code und Build

- `garmin/`: `manifest.xml`, `monkey.jungle`, `source/`, `resources/`
  mit Texten auf Deutsch und Englisch (A14), Geräte in der
  Produktliste des Manifests — zuerst `fenix5`, weitere Uhren erst nach
  einem Test im Simulator.
- **Bauen** lokal mit dem Connect-IQ-SDK (`monkeyc`), dazu ein Skript
  `tool/garmin_build.sh`. Ob CI die Uhr-App mitbauen kann, hängt daran,
  ob sich das SDK ohne Garmin-Anmeldung laden lässt — offen, bis es
  probiert ist.
- **Version Guard**: Die Uhr-App ist nicht im APK; `garmin/` wird wie
  `tool/` ausgenommen. Die Android-Brücke ist es nicht, sie bumpt.
- **Tests**: Die Protokoll-Kodierung ist eine pure Dart-Funktion mit
  Tests; die Uhr-Seite hat Monkey-C-Unit-Tests (`(:test)`,
  `tool/garmin_build.sh --test` im Simulator) für Dekodierung,
  Abseits-Regel, Vibrieren, Ankunft und Suche.
- **Vorführmodus** `tool/garmin_build.sh --demo`: im Simulator ohne
  GPS reihum Anfahrt, Trail, abseits, angekommen, mit dem Speicher in
  der Konsole. Im normalen Build schließt `monkey.jungle` ihn aus.

## 7. Grenzen der fēnix 5

Aus der Gerätedatei des SDK 9.3.0 und der Uhr selbst:

- Connect IQ 3.1 (Uhr: VM 3.1.9).
- Speicher je App-Art: Uhr-App 128 KB, Widget 64 KB, Datenfeld 32 KB.
  Deshalb eine **Uhr-App**: Nur sie hat genug Platz, eigenes GPS und
  Nachrichten vom Handy.
- Display 240 × 240, MIP, rund, 64 Farben, keine Glättung. Schriften
  Roboto Condensed (26–37 px) und Chronos für Zahlen (bis 58 px).
- **Watchdog: 120 000 Bytecode-Schritte je Ereignis.** Schon 1000
  Punkte in einem Zug zu dekodieren löste ihn aus, ebenso das Zeichnen
  aller Stücke und die Suche über die ganze Linie. Deshalb dekodiert
  die Uhr in Häppchen zu 300 Punkten (Timer, „Lade Route …"), und
  Zeichnen wie Suche gehen über Blöcke zu 32 Punkten mit Hülle.
- Die Uhr erscheint am Rechner als Laufwerk (Massenspeicher); gekoppelt
  wird mit der Garmin-Connect-App.

## 8. Messplan (📱, an der fēnix 5)

1. **Speicher**: Wie viele Punkte passen in die 128 KB, mit Ansicht?
   Gemessen mit Routen von 500, 1000, 2000 und 4000 Punkten.
   **Im Simulator gemessen (2026-11-04, G1)**, 124 KB frei für die App:
   500 Punkte 39 KB, 1000 Punkte 49 KB, 2000 Punkte 70 KB — gut 20 Byte
   je Punkt auf ~29 KB Grundlast. 3000 und 4000 Punkte: „Out of Memory"
   schon beim Laden, weil rohe Daten und dekodierte Felder kurz
   zusammen im Speicher liegen. Grenze für G2: 2000 Punkte (Abschnitt
   2). Am Gerät nachmessen.
2. **Übertragung**: größte Nachricht, die ankommt; Dauer für eine
   typische Runde.
3. **Akku**: Prozent je Stunde mit GPS jede Sekunde und Anzeige an.
4. **Lesbarkeit**: die S-Farben auf MIP in der Sonne.
5. **Abseits**: Die 30-m-Regel mit dem GPS der Uhr — löst sie im Wald
   falsch aus? Das ist der Startwert, wie in der App.

## 9. Umsetzung in Schritten (je ein PR)

1. **G1 — Uhr-App mit fester Testroute** (`garmin/`, kein Bump): Ansicht,
   Drehung, Abseits-Regel, Vibrieren, Speicher; Messung 1 und 3 bis 5.
   Gebaut am 2026-11-04: erfundene Runde mit Trails und Abzweigungen,
   am ersten GPS-Fix verankert; eine eigene Route geht mit
   `tool/garmin_build.sh --gpx` (ohne Abschnitte, nur unter `build/`).
   Messung 1 im Simulator erledigt, 3 bis 5 am Gerät offen.
2. **G2 — Protokoll und Android-Brücke** (`feat`, Bump): Kodierung in
   Dart, Brücke, Schalter „Auf der Uhr zeigen", Datenschutz und
   Play-Console; Messung 2.
3. **G3 — Abnahme am Gerät** (📱) und die Entscheidung zum Store.

## 10. Abgleich mit den Kernanforderungen

- A1, A2: nur die Trails der Route, die der Nutzer schon sieht.
- A3: keine Fahrt von der Uhr, keine Garmin-Aktivität.
- A5: Ausnahme nach Entscheidung 2.
- A6: Datenschutz und Play-Console mit G2.
- A7: Schlüssel und Testrouten nie im Repo; die Testroute in G1 ist
  erfunden.
- A8: Die Uhr navigiert nach der Übertragung ohne Handy.
- A9: nur Android, wie das Aufzeichnen.
- A12: zeigt; vibriert beim Abkommen (Entscheidung 3). Die Stummel der
  Abzweigungen sind Anzeige wie die Karte, kein Abbiegehinweis.
- A13: große Schrift, MIP-Farben am Gerät geprüft.
- A14: Texte der Uhr-App in beiden Sprachen.
