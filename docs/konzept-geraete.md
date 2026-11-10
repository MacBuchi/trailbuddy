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
| E2 | Tastenkarte „eine Taste, eine Bedeutung" (`konzept-garmin.md` 11) | annehmen; ändert Entscheidung 6 nur bei der Frage (START = ja) und beim langen HOCH |
| E3 | Routenablage auf der Uhr (vorher synchronisiert, ohne Handy wählbar) | ja, Größe nach Messung 8.6 |
| E4 | Buddys unterwegs sehen („Gruppenfahrt", Abschnitt 6) | offen — berührt A1, A3, A6 und den Satz „Kein Live-Standort" in `play-console.md` |
| E5 | Eigener BLE-Lagesensor als nächstes Messgerät | ja, vor jedem Versuch mit einer Uhr |
| E6 | fēnix 5 Plus und neuer als Lagesensor am Lenker | nur als Experiment nach E5; ändert Entscheidung 1 in `konzept-garmin.md` |

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
| Fahrt läuft | Navigation und Aufzeichnung haben getrennte Enden (9.4); „Beenden" in der Folgeansicht beendet nur die Navigation. „Trail beginnt" ist eine Fahne ohne Wort. |

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
- **Fahrt läuft**: die heutige Folgeansicht, dazu eine Zeile mit dem
  Stand (Aufnahme, Uhr, Sprünge an) und „Trail beginnt" als Knopf. Ein
  Ende „Fahrt beenden", das fragt, wenn nur die Navigation enden soll.
- **Wo das Handy steckt**, fragt die App nicht dreifach: „am Rad" (Lenker
  oder Rahmen — die Halterung lernt die Fusion ohnehin selbst,
  `FusionMount`) oder „in der Tasche". Nur am Rad gibt es Sprünge und
  Wheelies (#491), und nur dann zeigt die Uhr ihr Zeichen
  (`konzept-garmin.md` 11).

Die Regeln aus `konzept-routing.md` 10.4/10.5 bleiben; kommt der Kopf,
ändern sich dort 4 und 10.2 im selben PR.

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

1. Testbarkeit der Uhr-App (`konzept-garmin.md` 12, T1–T5).
2. Bedienkonzept 2.0 der Uhr (`konzept-garmin.md` 11), darauf gebaut.
3. Umkreis (#500) und Routenablage (E3).
4. Planer-Kopf und „Ergebnis und Start in einem" am Handy (Abschnitt 5)
   — unabhängig von der Uhr, kann parallel zu 1 laufen.
5. Schnittstelle „Begleitgerät" (Abschnitt 2), wenn das zweite Gerät
   wirklich kommt — nicht vorher.
6. Lagesensor (E5), danach E6; Buddys (E4) nach der Entscheidung.
