# Geräte und Rollen — Konzept (Vorschlag)

*Angelegt am 2026-11-10. Anlass (Betreiber): Die Uhr-App „läuft noch nicht
so rund", Bedienung und Testsetup sind durchwachsen, und das Zielbild
reicht weiter als „Handy ↔ fēnix 5": Uhr optional und auch allein, Handy
als Hauptgerät der Planung, später ein Lagesensor mit oder ohne Display,
Buddys auf der Anzeige. Dieses Dokument ist ein **Vorschlag**. Es ändert
keine Kernanforderung und keine Entscheidung in `konzept-garmin.md`; was
davon gilt, entscheidet der Betreiber in Abschnitt 0. Gebaut ist davon
nichts.*

Die Entwürfe dazu liegen im Designer („TrailBuddy Uhr 2.0", privat, Link
im PR): Tastenkarte, die Bildschirme der Uhr, vier des Handys.

## 0. Offene Entscheidungen des Betreibers

| Nr. | Frage | Vorschlag |
|---|---|---|
| E1 | Reihenfolge: erst Testbarkeit, dann Bedienung? | Ja — `konzept-garmin.md` 12, T1 vor allem anderen |
| E2 | Tastenkarte „eine Taste, eine Bedeutung" (`konzept-garmin.md` 11) | **angenommen** (Betreiber, 2026-11-12); ändert Entscheidung 6 nur bei der Frage (START = ja) und beim langen HOCH — gebaut in #513 |
| E3 | Routenablage auf der Uhr (vorher synchronisiert, ohne Handy wählbar) | ja, Größe nach Messung 8.6 |
| E4 | Buddys unterwegs sehen („Gruppenfahrt", Abschnitt 6) | offen — berührt A1, A3, A6 und den Satz „Kein Live-Standort" in `play-console.md` |
| E5 | Eigener BLE-Lagesensor als nächstes Messgerät | ja, vor jedem Versuch mit einer Uhr |
| E6 | fēnix 5 Plus und neuer als Lagesensor am Lenker | nur als Experiment nach E5; ändert Entscheidung 1 in `konzept-garmin.md` |
| E7 | Ansagen übers Ohr (Abschnitt 9, F6/F7; #525) | ja, als Schalter und **ohne Abbiegeansagen** — ändert A12 |
| E8 | „Buddy in der Nähe" einmal je Fahrt (Abschnitt 9, F8; #526) | ja, in der groben Form: Zelle statt Position, nichts gespeichert — berührt A1, A3, A6 |
| E9 | Reihenfolge weiterer Geräte (Abschnitt 11) | erst Kachel und Benachrichtigung am Handy, dann Garmin Edge und neuere Uhren, dann Wear OS |

## 1. Rollen statt Geräte

Heute steht im Code, wer was tut: Das Handy plant, misst und zeigt, die
Uhr zeigt und zeichnet ihre Spur auf. Künftig wählt eine Fahrt, welches
Gerät welche Rolle hat.

| Rolle | Was sie tut | Wer sie haben kann |
|---|---|---|
| **Planer** | rechnet Route, Runde, Umplanung; kennt Netz und Kacheln | nur das Handy (die Engine passt nicht in 124 KB) |
| **Anzeige** | zeigt Position, Linie, Trails im Umkreis, Buddys | Handy, Uhr, Sensor mit Display |
| **Aufzeichner** | GPS-Spur und Trail-Marken | Handy oder Uhr (heute schon beide) |
| **Lagesensor** | Lage und Beschleunigung für Airtime, Wheelie, Stoppie | Handy am Rad, BLE-Sensor, evtl. Uhr ab 5 Plus |

Daraus die Aufstellungen, die es geben soll:

- **Nur die Uhr.** Freie Fahrt mit dem zuletzt geladenen Umkreis, oder
  eine vorher synchronisierte Route aus der Ablage der Uhr. Die Fahrt
  wartet aufs Handy (heute: `RideLog`).
- **Handy in der Tasche, Uhr am Lenker oder Arm.** Das Handy plant und
  plant um, die Uhr zeigt und zeichnet auf. Lage misst niemand (#491).
- **Handy am Rad** (Lenker oder Rahmen). Wie heute: Planer, Aufzeichner
  und Lagesensor in einem; am Lenker auch Anzeige, am Rahmen zeigt die
  Uhr.
- **Handy in der Tasche, Sensor am Rahmen.** Das Handy liest den Sensor
  über Bluetooth; ein Display am Sensor ist eine zweite Anzeige.
- **Uhr und Sensor ohne Handy.** Erst ab fēnix 5 Plus möglich
  (Abschnitt 4), und nur, wenn die Erkennung auf Sensor oder Uhr läuft.

## 2. Die Schnittstelle „Begleitgerät"

`GarminBridge` (`lib/features/garmin/garmin_bridge.dart`) ist schon eine
schmale Schnittstelle: `status`, `send`, `open`, `listen`, dazu die
Ströme `messages` und `connected`. Vorschlag: Sie wird zur Schnittstelle
eines Begleitgeräts mit mehreren Transporten — Connect IQ für Garmin,
später Bluetooth direkt für ein eigenes Gerät. Der Inhalt von Protokoll 2
(Linie in Stücken, Abschnitte, Stummel, Kopf, künftig das Fenster `w`)
ist geräteneutral; an Garmin hängt nur die Stückgröße und die Laufzeit.

Was jedes Begleitgerät beim „hallo" sagen muss: seine Fassung (heute
`v`), was es kann (Anzeige, Aufzeichner, Lagesensor) und wie viel es
fasst (Punkte, Stücke). Das Handy entscheidet danach, was es schickt —
statt wie heute aus der Fassung der Uhr-App zu schließen.

## 3. Die Uhr allein

- **Routenablage** (E3): mehrere fertige Routen im Speicher der Uhr,
  am Handy ausgewählt („Auf die Uhr legen"), an der Uhr im Aktionsmenü
  gestartet. Heute gibt es zwei Fächer für den Wechsel, keine Ablage.
  Wie viele passen, sagt erst Messung 8.6 (`konzept-garmin.md`).
- **Der Umkreis bleibt liegen.** Das Fenster aus #500 (800 m, Trails in
  S-Farbe, Wege dorthin) überlebt das Schließen der App; ohne Handy
  zeigt die freie Fahrt das zuletzt geladene.
- **Planen an der Uhr heißt: Aufträge auslösen.** „Zum nächsten Trail",
  „Runde ab hier", „Zurück zum Start", „Trail überspringen" gehen als
  Auftrag ans Handy, das rechnet und die Linie schickt. Ohne Handy
  bleiben Ablage und Umkreis.

## 4. Lagesensor: was die Plattform hergibt

Bei Garmin nachgeschlagen am 2026-11-10 (API-Dokumentation, je die
Liste der unterstützten Geräte):

| Fähigkeit | Seit | fēnix 5 | fēnix 5 Plus und neuer |
|---|---|---|---|
| Kreisel (`Sensor.GyroscopeData`) | API 3.3 | nein | ja |
| Bluetooth als Zentrale (`BluetoothLowEnergy`) | API 3.1 | nein | ja |
| Nachricht vom Handy weckt die App (`Background.registerForPhoneAppMessageEvent`) | API 3.2 | nein | ja |

Quellen: https://developer.garmin.com/connect-iq/api-docs/Toybox/Sensor/GyroscopeData.html ,
https://developer.garmin.com/connect-iq/api-docs/Toybox/BluetoothLowEnergy.html ,
https://developer.garmin.com/connect-iq/api-docs/Toybox/Background.html

Was daraus folgt:

- Die fēnix 5 bleibt Anzeige und Aufzeichner (Entscheidung 1 in
  `konzept-garmin.md` gilt für sie unverändert).
- Eine Uhr kann einen Bluetooth-Sensor **lesen**, sich aber nicht selbst
  als Sensor anbieten: Das Modul kennt nur die Rolle der Zentrale.
  Rohdaten von der Uhr zum Handy gingen also nur über Connect IQ, mit
  rund 3,5 s je Nachricht (`konzept-garmin.md` 2) — unbrauchbar. Eine
  Uhr als Lagesensor müsste **selbst erkennen** und nur Ereignisse
  schicken, in 124 KB und am Lenker statt am Handgelenk.
- Ein eigener Sensor am Rahmen ist der direkte Weg (E5): Das Handy liest
  ihn ohne Umweg, die Signalaufbereitung aus
  `docs/recherche-sensorfusion.md` bleibt, wo sie ist, und die Halterung
  ist fest — das löst auch #491 (Handy in der Hosentasche).

Nicht geprüft: Abtastraten und Genauigkeit des Kreisels einer fēnix 5
Plus, und ob die Erkennung dort in den Speicher passt. Das wäre der
Inhalt des Experiments E6.

## 5. Handy: Planen und Losfahren — abgeglichen mit der App

*Stand 0.168.0, angesehen am 2026-11-10 im Test-Harness (echte
Oberfläche, Schriften und Blätter; die Karte ist dort leer): Karte,
Planer-Leiste, Parameter, Liste, Ergebnis, Start-Blatt, Folgeansicht mit
Trail-Werten, Aufzeichnung und „Fahrt beendet". Nicht am Gerät.*

### 5.1 Was heute hakt

| Wo | Befund |
|---|---|
| Karte | Fünf runde Knöpfe ohne Beschriftung; „Planen" (Gabel-Symbol) und „Aufzeichnen" (Lime-Punkt) erklären sich nicht, und nichts sagt, dass beide zu einer Fahrt gehören. |
| Planer-Leiste | Neun Symbole ohne Wort (Start, Zwischenpunkt, Parameter, Liste, Gebiet +, Gebiet −, Auswahl leeren, Rechnen, Schließen). Der eine Knopf, auf den alles zuläuft, ist ein Symbol unter acht anderen. |
| Runde oder Route | Die wichtigste Wahl steht im Parameter-Blatt unter vier Reglern und heißt „Ende der Fahrt" (`konzept-routing.md` 10.2 nennt das selbst). In der Leiste ist sie nicht zu sehen. |
| Parameter | Ein Blatt über drei Bildschirmhöhen: Start, Rad, vier Regler, Ende, Zwischenpunkte, vier Schalter, Online-Ergänzen, Erklärtext. Was man jedes Mal anfasst (Zeit, Höhenmeter), steht neben dem, was man einmal einstellt. |
| Ergebnis | Die Summe bricht als ein Satz in Mono über zwei Zeilen; „Navigieren" öffnet ein ZWEITES Blatt mit Schaltern und dem eigentlichen Startknopf — zwei Bestätigungen bis zur Fahrt. |
| Meldungen | „… dazugenommen · Rückgängig" liegt über dem unteren Ende der Leiste und über „Meine Position". |
| Fahrt läuft | Navigation und Aufzeichnung haben getrennte Enden (9.4); „Beenden" in der Folgeansicht beendet nur die Navigation. „Trail beginnt" ist eine Fahne ohne Wort. **Gebaut in 0.171.0 (#517):** ein Ende mit Frage, Stand-Zeile, Fahne mit Wort. |

Was gut ist und bleibt: die Folgeansicht (dunkle Karten, Band, Kacheln
AIRTIME · MAX G · WHEELIE · STOPPIE), das Ergebnis über der Karte, Tipp
auf den Trail als Auswahl, die Regeln aus 10.4/10.5.

### 5.2 Vorschlag (Entwürfe im Designer)

- **Ein Kopf im Planer** statt des Blatts für das Wichtigste: oben
  „Runde | Route zu einem Ziel", darunter eine Zeile mit dem Budget
  („ab Standort · 3 h · 800 hm · Bio") und „Anpassen".
- **Die Leiste trägt nur, was man auf der Karte tut**, mit Wort: Start,
  Punkt, Gebiet, Liste (bei „Route" dazu Ziel). „Leeren" und der Zähler
  stehen unten bei der Auswahl.
- **Ein Knopf mit Wort**: unten „Runde rechnen" / „Route rechnen", dort,
  wo danach das Ergebnis steht.
- **„Anpassen" in zwei Stufen**: Zeit, Höhenmeter, Rad sofort; Wanderweg,
  Radius, Vorlieben und Online-Ergänzen unter „Feinheiten", eingeklappt.
- **Ergebnis und Start in einem**: Summe als vier Kacheln, Profil, die
  gemerkten Schalter als Chips (Aufzeichnen, Uhr, Bildschirm), EIN Knopf
  „Fahrt starten". Speichern, „Auf die Uhr" (E3) und GPX darunter.
  **Gebaut in 0.171.0 (#517)**, ohne „Auf die Uhr" (wartet auf E3,
  #515); das eingeklappte Ergebnis darf dafür bis 60 % hoch werden
  (vorher 55 %).
- **Fahrt läuft**: die heutige Folgeansicht, dazu eine Zeile mit dem
  Stand (Aufnahme, Uhr, Sprünge an) und „Trail beginnt" als Knopf. Ein
  Ende „Fahrt beenden", das fragt, wenn nur die Navigation enden soll.
- **Wo das Handy steckt**, fragt die App nicht dreifach: „am Rad" (Lenker
  oder Rahmen — die Halterung lernt die Fusion ohnehin selbst,
  `FusionMount`) oder „in der Tasche". Nur am Rad gibt es Wheelies und
  Stoppies, in der Tasche Sprünge nur mit harter Landung, und erkennt
  die App die Tasche selbst, gilt das auch ohne Angabe (#491,
  `recherche-sensorfusion.md` 11). **Gebaut in 0.171.0** als Chip
  „Handy am Rad / in der Tasche" (nur mit Erkennung und Aufzeichnen) und
  als Regel im Dienst (`pocket_watch.dart`, bitgleich zu
  `tool/pocket_measure.py`); in der Tasche wird keine Halterung geladen
  oder gespeichert. Das Zeichen der Uhr kommt nur mit
  gelernter Halterung (`konzept-garmin.md` 11).

Die Regeln aus `konzept-routing.md` 10.4/10.5 bleiben; kommt der Kopf,
ändern sich dort 4 und 10.2 im selben PR.

**Stand 2026-11-13:** Die drei Planer-Punkte oben (Kopf, Leiste, ein
Knopf, „Anpassen") sind in `konzept-routing.md` 12 weitergedacht und
dort maßgeblich — statt „Runde | Route" stehen Start und Ziel als zwei
Zeilen im Kopf, und davor kommt ein Einstieg mit Vorschlag (Betreiber:
„für den initialen Vorschlag sollte es sehr einfach mit wenigen Klicks
gehen"). „Ergebnis und Start in einem" ist mit 0.171.0 gebaut (#517).

## 6. Buddys unterwegs — „Gruppenfahrt" (E4, nicht entschieden)

Der Wunsch: Buddys auf der Karte des Handys und auf der Uhr sehen, ein-
und ausschaltbar. Heute gilt das Gegenteil — `play-console.md` sagt
„Kein Live-Standort", A3 sagt „Fahrten verlassen das Gerät nie". Ein
Vorschlag, der so wenig wie möglich davon aufgibt:

- **Je Fahrt, nie dauerhaft**: ein Schalter im Blatt „Fahrt", Vorgabe
  aus. Mit dem Ende der Fahrt ist es vorbei.
- **Nur direkte Buddys, die ebenfalls eingeschaltet haben** (A2,
  gegenseitig).
- **Flüchtig**: die letzte Position über einen Echtzeit-Kanal, keine
  Tabelle, kein Verlauf (A3: keine Tabelle für Fahrten).
- **Nicht ab der Haustür**: erst ab einem Abstand vom Startpunkt.
- **Ohne Netz ehrlich** (A8): „zuletzt vor 4 min" statt eines Punkts,
  der stillsteht.
- **Auf der Uhr** als Scheibe mit Anfangsbuchstaben im Umkreis-Fenster —
  eine Form, keine Farbe, denn Farbe heißt Schwierigkeit (A13).

Kommt es, ändern sich im selben PR `anforderungen.md` (A1, A3, A6),
`konzept-trails.md`, beide Datenschutzseiten und `play-console.md`.

## 7. Abgleich mit den Kernanforderungen

- A1, A2: unverändert, außer E4 (dort benannt).
- A3: Routenablage und Umkreis sind keine Fahrten; die Fahrt der Uhr
  bleibt, wie sie ist. E4 berührt A3.
- A5: Ein eigener Sensor ist ein Gerät, kein Konto.
- A6: Bluetooth direkt heißt eine neue Berechtigung — Datenschutz und
  `play-console.md` im selben PR.
- A8: Jede Aufstellung muss ohne Netz fahren können; die Uhr allein auch
  ohne Handy.
- A9: Begleitgeräte bleiben Android, wie das Aufzeichnen.
- A12: Aufträge an der Uhr lösen Planung aus, keine Ansagen.
- A13: Buddys als Form; Tasten statt Tippziele an der Uhr.

## 8. Reihenfolge

Neu geordnet am 2026-11-11 nach den Feldszenarien (Abschnitt 9); die
gepflegte Fassung steht in #501.

1. Testbarkeit der Uhr-App: Ablaufkern (#508), dann Kettenstand und
   Tischabnahme (#527), Gesprächskatalog und Kanalmodell (#509) — die
   Prüfleiter in `konzept-garmin.md` 12.
2. Handy in der Tasche (#524): erst messen. Es entscheidet, wie F3 und F4
   überhaupt gehen.
3. Bedienkonzept 2.0 der Uhr (#513, `konzept-garmin.md` 11).
4. Umkreis-Fenster (#522), Routenablage (#515, E3), Aufträge ans Handy
   (#523).
5. Planer-Kopf und „Ergebnis und Start in einem" am Handy (Abschnitt 5,
   #516, #517) — unabhängig von der Uhr, kann parallel zu 1 laufen.
6. Ansagen (#525, E7) und der Hinweis für Sprünge an der Uhr (#514).
7. Buddy in der Nähe (#526, E8), danach erst die Gruppenfahrt (#519, E4).
8. Schnittstelle „Begleitgerät" (Abschnitt 2), wenn das zweite Gerät
   wirklich kommt — nicht vorher. Lagesensor (E5), danach E6.

## 9. Feldszenarien aus Nutzersicht

*Durchgespielt am 2026-11-11 (Betreiber: „die einzelnen Szenarien
durchspielen, die man im Feld hat, und aus Nutzersicht bewerten").
Maßstab ist nicht, ob der Code da ist, sondern ob jemand, der die App
nicht gebaut hat, damit losfährt und ankommt. Jeder Schritt der
Szenarien steht mit seiner Prüfung in `docs/watch_cases.json`
(`szenarien`); `tool/watch_scenarios_check.py` hält das in CI zusammen.*

### F1 — Nur die Uhr, Fahrt aufzeichnen

Uhr-App öffnen, START, fahren, LAP am Trail, START → Speichern; zu Hause
holt das Handy die Fahrt.

- **Stand:** gebaut (#484, #489).
- **Aus Nutzersicht:** trägt. Dass erst START aufzeichnet, sagt die Uhr
  („START: AUFNAHME", Anstoß nach zehn schnellen Fixen). Schwach ist das
  Ende: Die Fahrt „wartet aufs Handy", und wer die App am Handy nie
  öffnet, sieht sie nie — das Handy lauscht erst ab dem Start der App.
- **Offen:** Menüs am Gerät abnehmen (bisher nur im Vorführmodus),
  Speicher 8.6, Akku 8.3.

### F2 — Route vorplanen, auf die Uhr spielen, ohne Handy fahren

- **Stand:** halb. Die Uhr behält die EINE Route der letzten am Handy
  gestarteten Navigation und lädt sie ohne Handy.
- **Aus Nutzersicht:** nicht auffindbar. Man muss am Abend die Navigation
  starten, damit die Route hinübergeht, und sie dann beenden — das errät
  niemand. Es gibt keine Auswahl, kein „Auf die Uhr legen", und an der
  Uhr keinen Weg, eine Route zu starten.
- **Widerspruch im Konzept:** `konzept-garmin.md` 2 will die Linie „in
  Teilen um den Fortschritt" schicken. Das braucht das Handy unterwegs.
  Regel (dort nachgetragen): Teile nur mit verbundenem Handy; was in der
  Ablage liegt, liegt ganz.
- **Abseits ohne Handy:** Pfeil zurück und eingepasste Übersicht, kein
  Umplanen — das muss die Uhr sagen („ohne Handy"), statt zu schweigen.
- **Trägt:** #515 (Ablage, E3).

### F3 — Handy in der Tasche, Uhr am Lenker, einfach fahren

Der Betreiber: „Auf der Uhr sieht man die Trails und Wege dazu (nicht nur
Stummel), um da einfach hinzukommen."

- **Stand:** halb. Die Uhr bekommt die EINE nächste Trail-Linie in 800 m
  (#506) und fragt, bevor sie eine andere nimmt.
- **Aus Nutzersicht:** Man sieht einen Trail, nicht das Netz, und keinen
  Weg dorthin. Zwischen zwei Trails ist das Blatt die eigene Spur.
- **Die eigentliche Unbekannte:** ob das Handy in der Tasche überhaupt
  antwortet. Ohne laufende Aufzeichnung hält nichts die App wach
  (Messung 8.7, Feldbefund 8.8). Bevor der Umkreis gebaut wird, muss das
  gemessen sein (#524) — sonst baut man eine Ansicht, die im Feld leer
  bleibt.
- **Trägt:** #522 (Umkreis-Fenster mit Wegen, bleibt nach dem Schließen
  liegen), #524.

### F4 — Handy in der Tasche, Uhr, Route oder Runde

- **Stand:** gebaut — Route in Stücken, Abzweig-Stummel, Vibrieren beim
  Abkommen, Umplanen ab der Position der Uhr mit Rückfrage (#501).
- **Aus Nutzersicht:** Der Kern stimmt. Zwei Dinge stören: Während der
  Rückfrage heißt START „nein" (überall sonst „ja"), und „Speichern"
  beendet die Navigation. Beides löst das Bedienkonzept 2.0 (#513, E2).
- **Offen:** die Rückfrage am Gerät (8.10), die Ursache von 8.8 nie mit
  Logcat bestätigt, und wie F3 die Frage aus #524.

### F5 — Handy am Lenker oder Rahmen, mit oder ohne Uhr, Wheelie und Sprünge

Der Betreiber: „Wheelie-Detektor nutzen (nur mit Aufzeichnung? Was ist
intuitiv?)"

- **Stand:** halb. Die Erkennung läuft mit der Aufzeichnung im Dienst,
  die Live-Ansicht zeigt sie; die Uhr bekommt nur Bestwerte, und nur bei
  offener App.
- **Vorschlag — kein eigener Modus.** Intuitiv ist: Wer fährt, startet
  eine Fahrt; alles Weitere ergibt sich.
  - Die Erkennung gehört zu JEDER aufgezeichneten Fahrt, freie Fahrt wie
    Route. Ohne Aufzeichnung gibt es sie nicht — die Antwort darauf ist
    ein Start mit einem Tipp (und START an der Uhr), kein zweiter
    Schalter „nur Wheelie".
  - „Am Rad" fragt die App nicht ab, sie erkennt es: Hat die Fusion die
    Halterung gelernt (`FusionLive.mountReady`), steht in der Zeile des
    Fahrt-Stands „Sprünge an". Gebaut (0.171.0) mit drei Wörtern statt
    zwei: „Sprünge an", „Halterung lernt" (noch keine — am Anfang jeder
    Fahrt ohne mitgebrachte) und „Tasche: nur Sprünge"; in der Tasche
    fehlen Wheelie- und Stoppie-Kachel mit Grund („nur am Rad"), nicht
    mit einer Null (#491, #494).
  - Wer nichts gespeichert haben will, verwirft am Ende. Eine Fahrt ohne
    Speichern ist kein eigener Modus.
  - Die Uhr zeigt dasselbe Zeichen und den Hinweis für 3 s (#514); dafür
    muss die Erkennung auch bei gesperrtem Bildschirm melden.
- **Trägt:** #517 (ein Blatt, ein Ende, am Rad oder in der Tasche), #514,
  #491.

### F6 — Nur das Handy in der Tasche, Navigation übers Ohr

- **Stand:** fehlt, und **A12 verbietet es** („keine Sprachausgabe").
- **Aus Nutzersicht:** Ohne Uhr und mit dem Handy im Rucksack ist die
  Navigation heute blind — man muss anhalten und das Handy herausholen.
  Das ist das Szenario, in dem die App am wenigsten hilft.
- **Vorschlag (E7):** Ansagen als Schalter, Vorgabe aus: Abkommen und
  Zurückkommen, „Trail …, S2, in 200 Metern", Trail geschafft,
  angekommen. Sprachausgabe des Geräts (kein neuer Host, geht ohne Netz),
  Musik wird leiser statt zu stoppen. Mit Bildschirm an zeigt die
  vorhandene Abschnittskarte dasselbe.
- **Bewusst nicht:** Abbiegeansagen. Der Graph kennt Kreuzungen nicht
  verlässlich, und auf einem Trail löste jede Kehre eine aus
  (`konzept-routing.md` 9.6, #415). „Du bist abgekommen" ist eine
  Warnung, die stimmt; „in 50 Metern links" wäre eine Anweisung, die oft
  nicht stimmt.
- **Trägt:** #525.

### F7 — Ansage der Trails beim Befahren

- **Stand:** fehlt.
- **Vorschlag:** dieselbe Maschine wie F6, auch in der freien Fahrt: Wer
  in einen bekannten Trail einfährt, hört Name und Grad — das Handy
  findet die nächste Linie schon (`watch_free.dart`). An der Uhr ein
  kurzes Vibrieren und das Namensschild, kein Ton.
- **Was daraus mehr macht als eine Ansage:** die frische Meldung eines
  Buddys zum Trail voraus (Abschnitt 10).
- **Trägt:** #525.

### F8 — Ein Buddy fährt auch gerade in der Nähe

Der Betreiber: „5 km Umkreis? Einmal pro Fahrt reicht."

- **Stand:** fehlt; berührt A1, A3, A6 und den Satz „Kein Live-Standort"
  in `play-console.md`.
- **Vorschlag (E8) — sagen, nicht zeigen:** beide haben „Buddys
  unterwegs" eingeschaltet; nur während einer Aufzeichnung und erst ab
  1 km vom Start; das Handy meldet eine grobe Zelle (rund 5 km), nie
  eine Position; keine Tabelle, kein Verlauf. Ein Hinweis je Buddy und
  Fahrt: „Max ist auch gerade unterwegs — in der Nähe." Kein Abstand,
  keine Richtung, kein Punkt auf der Karte; wer sich treffen will,
  schreibt (#34).
- **Warum so:** Aus einer Zelle wird keine Spur, und es entsteht nichts,
  das mit gefahrener Zeit wächst. Das ist die kleinste Form, die den
  Moment liefert („der ist ja auch hier!"), und die Stufe vor der
  Gruppenfahrt (Abschnitt 6, #519).
- **Trägt:** #526.

### Was über alle Szenarien auffällt

- **Die Uhr schweigt, wenn das Handy fehlt.** In F2, F3 und F4 gibt es
  Zustände, in denen das Handy nicht antwortet und die Uhr einfach beim
  Alten bleibt. Regel für alle neuen Fälle: Die Uhr sagt, womit sie
  rechnet („Handy antwortet nicht", „ohne Handy").
- **Der Start einer Fahrt ist an zu vielen Stellen** (Karte, Planer,
  Startblatt, Uhr) und heißt überall anders. #517 und #513 müssen
  dieselben Wörter benutzen: „Fahrt starten", „Fahrt beenden".
- **Kein Szenario war bisher von Anfang bis Ende geprüft** — nur seine
  Bausteine. Das ist der Grund für die Szenario-Liste in
  `watch_cases.json`.

## 10. Begeisterung (Vorschläge, nicht entschieden)

*Betreiber, 2026-11-11: „Wir brauchen Begeisterungsfeatures, die das
Trailfahren und die Apps spannend machen." Gesucht ist, was nur
TrailBuddy kann — ein privates Netz mit Zustand unter Buddys —, nicht,
was Strava besser macht. Je Vorschlag die berührte Anforderung.*

| Vorschlag | Was der Fahrer erlebt | Anforderungen |
|---|---|---|
| **Zustand per Taste an der Uhr** | Nach „Trail endet" eine Wahl: gut · nass · Hindernis. Die Meldung entsteht, ohne das Handy herauszuholen — und der nächste Buddy hat sie. | A2 (nur Buddys), A10; geht als Eintrag „Melden" (#433) |
| **Frische Meldung voraus** | Vor dem Trailkopf: „Baum quer — Max, vor drei Tagen", als Schild an der Uhr und als Ansage. | A2, A12 mit E7 |
| **Buddy in der Nähe** (F8) | „Max ist auch gerade unterwegs." | E8 |
| **„Trail geschafft"** | Zeit gegen die eigene Bestzeit, Airtime, dazu der Vergleich unter Buddys („2 s hinter Max"). | A11 erlaubt Rankings unter Buddys; A3: die Zeit ist ein Wert am Trail, keine Fahrt |
| **Neu von deinen Buddys** | Beim Start: „Zwei Trails von Max in der Nähe, die du noch nicht gefahren bist" — und an der Uhr der Auftrag „Zum nächsten neuen Trail" (#523). | A1: nur das eigene Netz, keine „beliebten Trails" |
| **Heimweg und Tageslicht** | „Rückweg 55 min, Sonne noch 40 min" — einmal, wenn es knapp wird. | A8 (rechnet ohne Netz), A10 (sagen, nicht sperren) |
| **Rückblick-Karte** | Nach der Fahrt ein Bild zum Zeigen: befahrene Trails als Schilder, Höhenmeter, Airtime — ohne Karte, ohne Ort. | A3, A7: nichts, woraus eine Fahrt wird |
| **Seiten von selbst** | Bergab die Karte groß, bergauf die Bergseite, am Trailkopf der Trail. | A13; gehört zum Bedienkonzept 2.0 |
| **Erstbefahrung** | „Du bist der Erste aus deinem Netz, der diesen Trail seit dem Winter fährt." | A1, A2: gezählt wird nur im eigenen Netz |

Die ersten beiden stärken, was es nirgends sonst gibt: Zustand unter
Buddys, in dem Moment, in dem man ihn braucht und in dem man ihn weiß.
Sie brauchen keine neue Datenkategorie.

Bewusst nicht dabei: globale Bestenlisten, Kronen, „beliebt in deiner
Gegend" (A1, A11) und alles, was eine Fahrt hochlädt (A3).

## 11. Weitere Geräte und Anzeigen

*Betreiber, 2026-11-11: „dokumentieren, welche Widgets außer der
Garmin-App noch sinnvoll möglich sind (falls die Garmin-App rund ist),
z. B. Samsung-Uhr." Reihenfolge ist Entscheidung E9. Die Gerätezahlen
stammen aus den Gerätedateien des Connect-IQ-SDK 9.3.0
(`compiler.json`), nachgesehen am 2026-11-11; die übrigen Angaben aus
den verlinkten Quellen desselben Tags. Gebaut ist davon nichts.*

### 11.1 Am Handy, ohne neues Gerät

Am billigsten und für jeden Nutzer, auch ohne Uhr:

- **Kachel in den Schnelleinstellungen** „Fahrt starten / anhalten" —
  ein Wisch statt App öffnen, Karte, Knopf.
- **Die Benachrichtigung der Fahrt als Stand**: nächster Trail, Rest,
  Aufnahme läuft. Android 16 kennt dafür fortschrittsbezogene
  Benachrichtigungen, die als „Live Update" oben stehen können; die
  Freigabe dafür und die Verfügbarkeit je Gerät sind vor dem Bau zu
  prüfen.
- **Startbild-Widget**: „Fahrt starten" und der Zustand der eigenen
  Trails (letzte Meldung). Kein Standort, keine Karte.
- **Tasten am Kopfhörer** für „Trail beginnt / endet" — passt zu F6.

### 11.2 Garmin: Edge und neuere Uhren

Derselbe Code, dieselbe Brücke, derselbe Store-Eintrag.

| Gerät | Anzeige | Speicher einer Uhr-App | Connect IQ |
|---|---|---|---|
| fēnix 5 (heute) | 240 × 240 MIP | 128 KB | 3.1 |
| fēnix 5 Plus | 240 × 240 MIP | 1280 KB | 3.3 |
| fēnix 6 Pro | 260 × 260 MIP | 1280 KB | 3.4 |
| fēnix 7 / fēnix 8 Solar | 260 × 260 MIP | 768 KB | 5.2 / 6.0 |
| Forerunner 965 | 454 × 454 AMOLED | 768 KB | 5.2 |
| Edge 530 / 540 / 840 | 246 × 322 LCD | 1024 KB | 3.3 / 6.0 |
| Edge MTB | 240 × 320 LCD | 1024 KB | 6.0 |
| Edge 1040 | 282 × 470 LCD | 1024 KB | 6.0 |

- **Der Speicher ist das Ergebnis:** Fast alles, was die Uhr-App heute
  eng macht (2000 Punkte, „beide Routen passen nicht zusammen", der
  Umkreis nur mit Budget), ist eine Grenze der fēnix 5 und ihrer
  Geschwister ohne „Plus" — schon die 5 Plus hat das Zehnfache. Die
  Grenzen gehören deshalb ins „hallo" der Uhr (Abschnitt 2: „wie viel es
  fasst"), nicht in Konstanten.
- **Ein Edge sitzt am Lenker** — für Mountainbiker der naheliegendste
  Schritt, und es gibt ein Modell eigens für MTB. Hochformat, teils mit
  Touch.
- **Voraussetzung:** das Layout aus einer Quelle (#511); heute rechnet
  die Ansicht mit festen 240 Pixeln (`konzept-garmin.md` 6).
- **Ab Connect IQ 3.2** kann eine Nachricht vom Handy die App wecken
  (Abschnitt 4) — das entschärft F3/F4 auf allem außer der fēnix 5.
- **Ein Datenfeld** in Garmins eigener Aktivität („nächster Trail in
  …") wäre möglich (32–256 KB), hieße aber: Die Fahrt ist eine
  Garmin-Aktivität und geht an Garmin Connect. Das widerspricht A3/A5 —
  nur als bewusste Entscheidung des Nutzers, nicht als Vorgabe.

### 11.3 Wear OS (Samsung Galaxy Watch, Pixel Watch)

- **Eigene App**, kein gemeinsamer Code mit Monkey C; die Ansicht ließe
  sich aus dem Dart-Abbild (#511) ableiten, der Ablauf aus dem
  Gesprächskatalog (#509).
- **Der Kanal ist direkt:** die Data-Layer-API von Wear OS zwischen Uhr
  und gekoppeltem Handy, über die Google-Play-Dienste, ohne App eines
  Dritten dazwischen. Paketname und Signatur müssen auf beiden Geräten
  dieselben sein.
  https://developer.android.com/training/wearables/data/overview
- **Mehr Flächen:** Kachel und Zifferblatt-Komplikation („nächster
  Trail", „Aufnahme läuft") neben der App.
- **Testbar ohne Hardware:** Uhr-Emulator, gekoppelt mit dem
  Handy-Emulator — die Prüfleiter gälte von Anfang an.
- **Zu klären vor dem Bau:** A6 (die Play-Dienste als Weg zur Uhr sind
  eine neue Datenstrecke und gehören in die Datenschutzseiten), Akku mit
  GPS, und ob eine Uhr ohne Tasten im Dreck bedienbar ist (A13).
- **Setzt voraus:** die Schnittstelle „Begleitgerät" (Abschnitt 2).

### 11.4 Hammerhead Karoo

Ein Radcomputer auf Android-Basis mit einem Erweiterungs-SDK
(`karoo-ext`); Apps lassen sich als APK über die Begleit-App aufspielen,
die Bibliothek des Herstellers verlangt einen Lizenzvertrag. Entwickler
berichten, dass eine Erweiterung nicht in die Karte des Geräts zeichnen
kann — für TrailBuddy wäre es also eine eigene Seite, kein Overlay.
Kleine Nutzergruppe; nur, wenn ein Tester eines hat.
https://support.hammerhead.io/hc/en-us/articles/31150180125083-Hammerhead-Extensions

### 11.5 Nicht sinnvoll

- **Apple Watch:** setzt eine iOS-App voraus; TrailBuddy ist Android und
  Web (A9).
- **Ältere Samsung-Uhren mit Tizen**, **Zepp OS (Amazfit)**: eigene
  Welten mit kleiner Gruppe und je eigener Begleit-App.
- **Suunto, Coros, Polar, Wahoo:** kein offenes SDK für eigene Apps mit
  Karte und Nachrichten vom Handy (aus dem Kopf, nicht nachgeschlagen —
  vor einer Absage an einen Nutzer prüfen). Für sie bleibt der Weg per
  Datei: GPX-Export (A5).

### 11.6 Vorschlag zur Reihenfolge (E9)

1. Kachel und Benachrichtigung am Handy — klein, nützt jedem.
2. Garmin Edge und die neueren Uhren, sobald #511 steht — derselbe Code.
3. Wear OS — erst, wenn die Garmin-App rund ist und die Schnittstelle
   „Begleitgerät" steht; die größte neue Gruppe, aber eine zweite
   Codebasis.
