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
(`docs/konzept-routing.md` 9.2), geschnitten für 240 × 240 Pixel MIP
(64 Farben, in der Sonne gut lesbar, kein Touch):

- **Die Route als Linie**, gedreht in Fahrtrichtung: in Bewegung nach
  dem GPS-Kurs, im Stand nach dem Kompass der Uhr — die fēnix 5 hat
  einen Magnetfeldsensor, und gerade an einer Kreuzung im Stand kennt
  das GPS die Richtung nicht. In der Mitte die eigene Position.
- **Die Trails der Route in ihrer Farbe** (S-Grad, Design 2): auf MIP
  die nächste der 64 Farben zu `AppColors.mapLines`; geprüft am Gerät,
  nicht nur im Simulator.
- **Unten eine Zeile**: Rest-km und Rest-hm; auf einem Trail dessen
  Name. Abseits statt dessen der Abstand zur Linie in Warnfarbe und ein
  Pfeil zum nächsten Punkt voraus (wie 9.3).
- **„Angekommen"** wie in der App (unter 30 m vom Ende bzw. letzter
  Abschnitt einer Runde).
- **Vibrieren beim Abkommen** (Entscheidung 3): einmal, wenn „abseits"
  beginnt — dieselbe Regel wie 9.3 (mehr als 30 m neben der Linie, zwei
  Fixe in Folge). Kein zweites Vibrieren, bis man wieder auf der Linie
  war; nichts beim Zurückkommen, nichts vor Abzweigen.
- **Tasten**: hoch/runter zoomt (drei Stufen), START schaltet zwischen
  Karte und einer Zahlenseite (Tempo, Zeit, Höhe), ZURÜCK beendet nach
  Rückfrage. Tippziele gibt es nicht; A13 heißt hier: große Schrift,
  kräftige Linien.

Kein Kartenbild: Die fēnix 5 hat keine Karten, und Kacheln passen nicht
in den Speicher einer App (Abschnitt 7). Gezeigt werden nur Route und
Trails der Route.

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
- Kopf: Protokollversion, Länge, Höhenmeter, eine Kennung der Route.

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
  Tests; die Uhr-Seite hat Monkey-C-Unit-Tests (`barreltest`/`(:test)`)
  für Dekodierung und Abseits-Regel.

## 7. Grenzen der fēnix 5

Aus der Gerätedatei des SDK 9.3.0 und der Uhr selbst:

- Connect IQ 3.1 (Uhr: VM 3.1.9).
- Speicher je App-Art: Uhr-App 128 KB, Widget 64 KB, Datenfeld 32 KB.
  Deshalb eine **Uhr-App**: Nur sie hat genug Platz, eigenes GPS und
  Nachrichten vom Handy.
- Display 240 × 240, MIP, rund.
- Die Uhr erscheint am Rechner als Laufwerk (Massenspeicher); gekoppelt
  wird mit der Garmin-Connect-App.

## 8. Messplan (📱, an der fēnix 5)

1. **Speicher**: Wie viele Punkte passen in die 128 KB, mit Ansicht?
   Gemessen mit Routen von 500, 1000, 2000 und 4000 Punkten.
2. **Übertragung**: größte Nachricht, die ankommt; Dauer für eine
   typische Runde.
3. **Akku**: Prozent je Stunde mit GPS jede Sekunde und Anzeige an.
4. **Lesbarkeit**: die S-Farben auf MIP in der Sonne.
5. **Abseits**: Die 30-m-Regel mit dem GPS der Uhr — löst sie im Wald
   falsch aus? Das ist der Startwert, wie in der App.

## 9. Umsetzung in Schritten (je ein PR)

1. **G1 — Uhr-App mit fester Testroute** (`garmin/`, kein Bump): Ansicht,
   Drehung, Abseits-Regel, Vibrieren, Speicher; Messung 1 und 3 bis 5.
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
- A12: zeigt; vibriert beim Abkommen (Entscheidung 3).
- A13: große Schrift, MIP-Farben am Gerät geprüft.
- A14: Texte der Uhr-App in beiden Sprachen.
