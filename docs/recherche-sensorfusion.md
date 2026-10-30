# Recherche: Signalaufbereitung für Airtime, Wheelie und Max G (#36)

*Stand 2026-10-30. Anlass: Die beiden ersten Messfahrten mit der Dev-App
(0.142.0, 0.143.0) zeigen, dass Rohwerte allein nicht tragen. Der
Betreiber (2026-10-30): „Erst an der Signalaufbereitung arbeiten, bevor
wir Sensor-Rohwerte für irgendwas benutzen — Kalman-Filter, um Gyro und
Beschleunigungssensor zu einem sinnvollen Fahrradmodell zusammenzubauen.
Das geht mit einer ordentlichen Recherche los."*

Dieses Dokument beantwortet sechs Fragen mit Quellen und endet mit einer
**empfohlenen Architektur**; was der Prototyp darauf auf den eigenen
Fahrten zeigt, steht in Abschnitt 7. Gebaut wird erst, wenn der Betreiber sie
abgenommen hat; danach folgen Prototyp in Python auf den vorhandenen
Fahrten, Messfahrten mit Ansage und die Portierung in die App
(`docs/konzept-airtime.md` §9).

## 0. Was die eigenen Fahrten schon zeigen

Zwei Fahrten am 2026-10-30, Straße, E-Bike, Telefon liegend in
Fahrtrichtung am Oberrohr (die Dateien bleiben auf dem Rechner des
Betreibers; hier nur Zählungen):

- **Die Rate ist ungleichmäßig**: angefragt 100 Hz, geliefert im Mittel
  ~118 Hz (Abstand 8,5 ms), in Schüben. Jede Rechnung nimmt den
  Zeitstempel des Sensors, nie eine feste Schrittweite.
- **Kein Abschneiden sichtbar**: Spitzen bis 15,4 g je Achse, ohne
  Häufung am Maximum; der Messbereich des Geräts liegt also bei
  mindestens ±16 g. Der Kreisel kam bis 290 °/s — weit unter den
  üblichen ±2000 °/s.
- **Die Neigung aus der geglätteten Beschleunigung trennt nicht**:
  Von 17 „Wheelies" der zweiten Fahrt kippten 13 in die Gegenrichtung
  (Front runter), alle in den letzten zwei Minuten, zusammen mit zwei
  Schlägen von 12–15 g. Die Regel kannte weder „vorn" noch den
  Unterschied zwischen Schwerkraft und Fahrdynamik.
- **Der Kreisel bestätigt echte Drehungen**: An den Stellen der langen
  Wheelies der ersten Fahrt zeigte die aufintegrierte Drehrate 25–45°
  um dieselbe Achse — Bremsen allein dreht das Telefon nicht.

## 1. Lage schätzen, wenn sich das Rad bewegt

**Das Problem.** Der Beschleunigungssensor misst die *spezifische
Kraft* f = a − g: im Stand nur die Schwerkraft, in Fahrt dazu
Bremsen, Antreten, Fliehkraft und Schläge. Jede Lage aus f allein ist in
Fahrt falsch; der Kreisel allein driftet (Bias). Die Fusion nimmt den
Kreisel für schnelle Änderungen und f als langsame Stütze — und die
Kunst liegt darin, f nur dann und nur so stark zu glauben, wie es
gerade Schwerkraft ist.

**Die Kandidaten:**

| Filter | Kern | Stärke | Schwäche |
|---|---|---|---|
| Komplementärfilter | Hochpass Kreisel + Tiefpass Beschleunigung | trivial | feste Grenzfrequenz, kein Bias |
| Mahony (2008) | Korrektur auf SO(3) mit PI-Regler, schätzt Gyro-Bias | wenige Zeilen, stabil bewiesen | feste Verstärkung, keine Unsicherheit |
| Madgwick | Gradientenabstieg | populär | wie Mahony; in Vergleichen mal besser, mal schlechter |
| EKF auf Quaternion | Kalman mit vollem Zustand | Unsicherheit je Schritt | Quaternion-Norm als Nebenbedingung |
| **Error-State-KF (ESKF)** | Nominal-Lage + kleiner Fehlerzustand (3 Winkel + 3 Bias) | sauber linearisiert, Standard in IMU-Navigation | etwas mehr Algebra |
| UKF | Sigma-Punkte | starke Nichtlinearität | Aufwand ohne Gewinn bei 6 Zuständen |

**Was die Literatur zur Fremdbeschleunigung sagt:**

- Feste Verstärkungen leiden unter Fremdbeschleunigung — ein
  Komplementärfilter ist im Ruhigen gut, Mahony in der Dynamik besser,
  ein klarer Sieger zwischen Mahony und Madgwick fehlt (Ludwig &
  Burnham 2018; ASAT-Vergleich mit VN-100-Daten).
  *Nur Zusammenfassungen gelesen, wo nicht anders gesagt; die Formeln
  kommen für den Prototyp aus Solà (vollständig frei verfügbar).*
- Der gängige Ausweg ist **adaptiv**: die Messunsicherheit der
  Beschleunigung aufblähen, wenn ‖f‖ von g abweicht oder das Residuum
  groß ist (JSME 2006: Richtung der Fremdbeschleunigung aus dem
  Residuum; Makni/Fourati/Kibangou: Detektor statisch/dynamisch, dann
  Kovarianz der Fremdbeschleunigung schätzen; „Improved Complementary
  Filters … in Accelerated Motion": Verstärkung nach der Größe der
  Fremdbeschleunigung).
- **Besser als verwerfen ist abziehen**: Bei Fahrzeugen ist ein großer
  Teil der Fremdbeschleunigung *vorhersagbar* — Abschnitt 2.

**Aufwand in Dart.** Ein ESKF mit 6 Fehlerzuständen sind je Schritt ein
paar 6×6- und 3×6-Produkte; bei ~120 Hz unter 0,1 ms je Sekunde
Rechenzeit — vernachlässigbar neben dem Schreiben der Rohdaten. Kein
Paket nötig; die Formeln stehen vollständig bei Solà (2017).

## 2. Das Fahrradmodell als Stütze

Die Motorrad- und Zweiradliteratur löst genau unser Problem:
Lage (dort vor allem Roll/Schräglage) aus IMU **plus Tempo**, mit einem
**kinematischen Modell** statt eines vollen Fahrdynamikmodells (Mimmo &
Zanzi 2023, arXiv 2302.06265: zweistufiger Beobachter, Annahme
„koordinierter Manöver", auf der Rennstrecke erprobt; FME Transactions
2020: EKF mit kinematischem Modell der IMU, ausdrücklich ohne
vollständiges Motorradmodell; Sensors 2022, 22(22):8991: Zweirad, erst
Gierrate, dann Roll, mit Tempo als Eingang, Versuche mit einem
Fahrrad).

Das kinematische Modell im Radsystem (x vorn, y links, z oben):

- **längs**: a_x = dv/dt, v aus dem GPS (1 Hz, geglättet und
  abgeleitet);
- **quer**: a_y = v · ω_z — die Fliehkraft in der Kurve aus Tempo und
  Gierrate (Gierrate = Kreisel um die Hochachse);
- **hoch**: a_z ≈ 0 im Mittel (Rad bleibt auf dem Boden).

Damit wird aus der Messung f die erwartete Schwerkraft
g_erwartet = f − a_modell, und *die* stützt die Lage. Was das Modell
nicht erklärt (Schläge, Pedalieren, Wippen), bleibt im Residuum und
wird über die adaptive Unsicherheit aus Abschnitt 1 gedämpft.

**Gelände ist kein Wheelie.** Die Lage relativ zur Schwerkraft enthält
die Steigung des Wegs. Ein Wheelie ist Pitch *gegenüber dem Weg*:
Pitch − Steigung. Die Steigung kommt aus dem Tiefpass des Pitch über
einige Sekunden (dasselbe Prinzip wie die laufende Bezugslage aus
0.143.0, aber auf einer sauberen Größe) und kann gegen die GPS-Höhe
plausibilisiert werden (zu grob für Wheelies, gut für den Mittelwert).

**Roll gegen Pitch.** In der Kurve legt sich das Rad um die Längsachse
(Roll), beim Wheelie dreht es um die Querachse (Pitch). Mit bekanntem
„vorn" (Abschnitt 3) sind beide getrennte Größen; die Fliehkraft-
Korrektur sorgt dafür, dass eine Kurve nicht als Pitch durchschlägt.

**Zustände.** Mindestens Lage (Quaternion, nominal) und Gyro-Bias (3);
die Lage der Halterung (Abschnitt 3) wird getrennt und langsam
geschätzt, nicht im schnellen Filter.

## 3. Halterung → Radachsen

Das Telefon liegt irgendwie am Rad: Die App weiß weder, welche Achse
„vorn" ist, noch ob es verkehrt herum liegt — genau daran scheiterte die
Kipprichtung der zweiten Fahrt. Die Fahrzeug-Telematik löst das
automatisch, meist in zwei Schritten (Patente zu Smartphone-in-Auto,
z. B. US 10,462,608 und US 10,876,859; dazu Arbeiten zur Ausrichtung
günstiger IMUs mit GNSS):

1. **„unten"** = Mittel der Schwerkraft bei ruhiger Geradeausfahrt
   (kleine Gierrate, gleichmäßiges Tempo) — im Mittel kein Netto-
   Beschleunigen, ebener Weg.
2. **„vorn"** = Richtung der Beschleunigung in der waagrechten Ebene
   bei Längsbeschleunigung ohne Kurve (GPS-Tempo ändert sich, Gierrate
   klein); das Vorzeichen aus dem Vorzeichen von dv/dt (Bremsen zeigt
   nach hinten).
3. **Verrutschen** erkennen: springt „unten" sprunghaft (Patente nennen
   etwa 1 rad), neu lernen — das ersetzt die 60-s-Regel aus 0.143.0.

Am Fahrrad kommen reichlich Brems- und Antrittsphasen vor; nach einer
Minute Fahrt sollte „vorn" stehen. **Damit entfällt das Lernen der
Richtung aus einem ersten „Stimmt".**

## 4. Was Android schon fusioniert

`TYPE_GAME_ROTATION_VECTOR` ist die Lage aus Kreisel und
Beschleunigung ohne Magnetfeld, vom Hersteller fusioniert; Pflicht ist
er nur als „SHOULD" (Android CDD 7.3), Güte und Verstärkung sind je
Gerät verschieden und nicht dokumentiert. Erfahrungen aus Fahrzeugen
sind schlecht: der fusionierte Linearbeschleunigungssensor gilt im Auto
als unbrauchbar, Fremdbeschleunigung und Vibration verfälschen die Lage
(Blog-Erfahrung, keine Studie); MbientLab-Nutzer berichten am Rad von
Spitzen in der eingebauten Fusion, ein eigener Komplementärfilter war
besser. Und: Er kennt kein Tempo — die Stütze aus Abschnitt 2 fehlt
ihm grundsätzlich.

`sensors_plus` bietet ihn nicht an; er bräuchte einen eigenen Kanal.
**Empfehlung: nicht als Grundlage.** Allenfalls später als
Vergleichsspalte im Logger, wenn der eigene Filter steht.

## 5. Ereignisse auf dem aufbereiteten Signal

- **Airtime**: Im freien Flug misst der Beschleunigungssensor ≈ 0 —
  unabhängig von der Lage. Die Flugphase selbst braucht deshalb kaum
  Fusion; sie braucht ein **gefiltertes ‖f‖** (Vibration, Federung) und
  eine saubere Landung. Die Literatur:
  - Schwellen im Zeitbereich trafen 100 % von 92 Sprüngen bei
    Halfpipe-Snowboard (SPIE 2007);
  - Kopf-IMU: „jump characteristic points" und Differenz der
    Beschleunigung davor/danach, mittlerer Fehler 0,033 s (4,8 %),
    besser als zwei Handelsgeräte, u. a. für MTB (Datensatz sport-iat
    4029614; Zeitschrift nicht geprüft);
  - Halfpipe 2024: U-Net schlägt Schwellen, Abweichung im Median wenige
    Millisekunden — Video als Sollwert, Sensoren am Unterschenkel
    (Gorges et al., Sensors 24:6773);
  - BMX-Beispiel: Ruck (Ableitung) klein = Flug (MathWorks-Blog).
  Die Fusion hilft bei der **Plausibilität**: Lage vor und nach dem Flug
  (Rad steht wieder aufrecht), Tempo davor und danach (GPS), und die
  Landung als Spitze in Rad-Hochachse statt als beliebiger Schlag.
- **Max G / Landung**: Spitzen bis 15,4 g ohne Abschneiden (Abschnitt
  0). Ein abgeschnittenes Signal unterschätzt Spitzen (Studie zu
  Messbereich und Abtastrate: −11 % durch Bereich, −11 % durch
  Abtastung, −18 % zusammen). Der Logger sollte den Messbereich des
  Sensors (`Sensor.getMaximumRange()`) in den Kopf schreiben — eine
  Zeile, später.
- **Wheelie**: Pitch gegenüber dem Weg (Abschnitt 2) über einer Schwelle
  und eine Mindestdauer, **nur Front hoch**. Ein Patent zur
  Wheelie-Erkennung am Fahrrad macht es genau so: Pitch aus der
  Drehrate um die Querachse, tiefpassgefiltert, Schwelle so gewählt,
  dass normales Bergauffahren darunter bleibt.
- **Schläge vs. Sprünge**: Ein Schlag ohne vorherige Flugphase ist kein
  Sprung (Konzept §2 bleibt); neu ist, dass ein Schlag die Lage nicht
  mehr verbiegt, weil die adaptive Unsicherheit ihn ausblendet.

## 6. Bewertung ohne Referenz-IMU

Eine zweite, bessere IMU am Rad gibt es nicht. Bewertet wird mit:

1. **Sollwerten aus der App** (0.143.0): „Stimmt" / „War keiner" je
   Banner, „Wheelie verpasst" — das Werkzeug zählt Treffer, Verpasste,
   Fehlalarme je Schwelle. Das gilt unabhängig vom Algorithmus und
   bewertet jeden künftigen Filter auf denselben Fahrten.
2. **Plausibilitätsproben**, auf jeder Fahrt automatisch:
   - im Stand: Lage = gelernte Halterung, Pitch ≈ Steigung;
   - Geradeausfahrt: Pitch gegenüber dem Weg innerhalb weniger Grad;
   - kräftiges Bremsen/Antreten (GPS dv/dt groß, Gierrate klein):
     **kein** Pitch-Ausschlag — die Probe, an der die Rohregel scheitert;
   - Kurve (Gierrate groß): Roll, kein Pitch;
   - Gyro-Bias konvergiert und bleibt klein.
3. **Synthetische Reihen** mit bekannter Wahrheit als Tests (Bremsen,
   Kurve, Wheelie, Bias, Verrutschen), in Python und später in Dart.

## Empfohlene Architektur

Drei Stufen, jede für sich testbar:

1. **Halterung** (langsam, Sekunden bis Minuten): lernt „unten" und
   „vorn" (Abschnitt 3), erkennt Verrutschen. Ergebnis: Drehung
   Telefon → Rad.
2. **Lage-Filter** (schnell, jeder Sensorwert): **Error-State-Kalman**
   nach Solà mit 6 Fehlerzuständen (3 Lagewinkel, 3 Gyro-Bias). Vorhersage
   mit dem Kreisel (echte Zeitstempel). Messung = Beschleunigung **minus
   Fahrradmodell** (dv/dt aus GPS längs, v·ω_z quer). Messunsicherheit
   adaptiv: wächst mit ‖f − a_modell‖ − g, mit der Vibrationsenergie und
   im Flug/bei Schlägen bis „ignorieren". Ergebnis: Pitch, Roll im
   Radsystem, Beschleunigung ohne Schwerkraft in Radachsen, eine
   Unsicherheit je Schritt.
3. **Ereignisse** (auf Stufe 2): Wheelie = Pitch gegenüber dem Weg
   (Tiefpass über einige Sekunden als Weg), nur Front hoch; Airtime =
   gefiltertes ‖f‖ unter der Schwelle, mit Plausibilität aus Lage und
   Tempo; Landung = Spitze in Rad-Hochachse.

**Mahony mit derselben Modellkorrektur** wird im Prototyp als
Vergleich mitgerechnet: Er ist ein Viertel des Codes. Gewinnt er auf den
Proben aus Abschnitt 6 gleich gut, nimmt die App ihn; sonst den ESKF —
der zusätzlich die Unsicherheit liefert, mit der sich Ereignisse in
unsicheren Momenten zurückhalten lassen.

**Verworfen:** Madgwick (gegenüber Mahony kein belegter Vorteil, kein
Bias-Integral in der Grundform); UKF (Aufwand ohne Gewinn bei 6
Zuständen); Androids Rotationsvektor als Grundlage (gerätabhängig, ohne
Tempo-Stütze; Abschnitt 4); ein volles Fahrdynamikmodell (die
Literatur kommt kinematisch aus).

## Offen für die Messung

Stand nach dem Prototyp (Abschnitt 7):

- ~~Wie schnell „vorn" auf normalen Fahrten steht~~ — nach 65–80 s
  Fahrt, getragen von den Kurven, nicht vom Bremsen (7.2). Ob es beim
  Schieben oder Tragen kippt, ist offen.
- ~~Wie gut dv/dt aus 1-Hz-GPS ist~~ — zu schwach, um „vorn" allein zu
  lernen; als Abzug mit Unsicherheit taugt es (7.2, 7.4).
- Die Zeitkonstante „Weg" für den Wheelie-Pitch: 3 s gesetzt, gegen
  Sollwerte noch nicht gemessen (die Banner der zweiten Fahrt sind
  unbeantwortet).
- Die Vibrationsenergie am Lenker gegenüber dem Oberrohr.
- Hosentasche: keine feste Halterung — Stufe 1 findet dann nichts; dort
  bleibt nur Airtime (Konzept §2).
- Sprünge: Auf beiden Fahrten keiner; Flug und Landung sind nur
  synthetisch geprüft.

## 7. Ergebnis des Prototyps (2026-10-30, Konzept §9 Schritt 3)

`tool/sensor_fusion.py` baut die drei Stufen der Architektur, mit ESKF
und Mahony nebeneinander; `tool/airtime_measure.py <Datei> --fused`
rechnet Wheelies, Flüge und Proben darauf. Die Selbsttests (in CI)
fahren eine synthetische Fahrt mit bekannter Wahrheit: schräg montiertes
Telefon, Gyro-Bias, Rauschen, Bremsen ohne Pitch, Kurve mit Schräglage,
Wheelies auf ebener Strecke und am Hang, Nase runter, ein Sprung,
Verrutschen der Halterung. Ausgewertet auf den beiden Fahrten vom
2026-10-30 (17 und 23 min, Straße, E-Bike, Oberrohr) — hier nur
Zählungen und Winkel.

### 7.1 Die Referenz ist der Kreisel

Sollwerte aus der App gibt es für diese Fahrten nicht: Die 17 Banner der
zweiten Fahrt sind alle unbeantwortet, die erste Fahrt lief vor 0.143.0.
Abschnitt 6.1 fällt also aus. Dafür zeigte sich der Kreisel des Telefons
als viel besser als angenommen: Mittel im Stand 0,035 °/s, die Lage nur
aus dem Kreisel liegt nach 20 s im Median 2° neben der Schwerkraft. Die
Lage von vor 3 s, mit dem Kreisel allein weitergedreht, ist damit für
jede schnelle Änderung — Bremsen, Kurve, Wheelie — die Wahrheit auf
etwa 0,2°. Ein Filter, der die Beschleunigung ganz ignorierte, bestünde
diese Probe auch; deshalb gehören der Pitch gegenüber dem Weg beim
Geradeausfahren (ohne Wheelies) und der geschätzte Bias dazu.

| p95 in Grad | F1 ESKF | F1 Mahony | F1 roh | F2 ESKF | F2 Mahony | F2 roh |
|---|---|---|---|---|---|---|
| Pitch beim Bremsen/Antreten, gegen Kreisel | 1,1 | 0,7 | 10,2 | 0,7 | 0,2 | 16,1 |
| Pitch in Kurven, gegen Kreisel | 0,7 | 0,8 | 14,3 | 1,0 | 0,8 | 14,6 |
| Roll in Kurven, gegen Kreisel | 0,7 | 0,9 | 22,8 | 0,7 | 0,7 | 29,8 |
| Pitch über die ganze Fahrt, gegen Kreisel | 0,6 | 0,7 | 7,9 | 0,7 | 0,7 | 8,8 |
| Pitch geradeaus, gegen den Weg | 2,0 | 1,8 | – | 1,6 | 1,5 | – |
| Gyro-Bias am Ende (°/s) | 0,08 | 0,93 | – | 0,21 | 0,21 | – |

„Roh" ist die Neigung aus der 0,5 s geglätteten Beschleunigung (die
Regel bis 0.143.0), aber schon mit der gelernten Halterung. Brems-Momente
mit GPS-dv/dt über 1,5 m/s² und ohne Kurve gab es nur wenige (0,4 s und
1,7 s); Kurven reichlich (über 150 s je Fahrt).

### 7.2 Halterung

- **„Unten"** stand nach 23 s Fahrt (Fahrt 1) bzw. 277 s (Fahrt 2,
  die langsam begann).
- **„Vorn" aus dem Bremsen allein stand auf keiner der beiden Fahrten
  sicher**: zu wenige kräftige Brems- und Antrittsphasen, die Richtung
  aus 1-Hz-GPS schwankt (Konsistenz 0,3–0,55), und das Schlussstück der
  zweiten Fahrt drehte das Vorzeichen sogar um. Neu ist deshalb ein
  zweiter Hinweis, den jede Kurve liefert: Das Rad legt sich hinein, der
  Kreisel sieht die Welt-Senkrechte zur Außenseite kippen, die Gierrate
  sagt, welche Seite außen ist — daraus „links" und damit „vorn". Mit
  beidem stand „vorn" nach 88 s bzw. 358 s, also 65–80 s nach „unten",
  Konsistenz 0,9, auf 1° bzw. 5° an der Richtung, die die Drehachse der
  langen Wheelies vorgibt.
- **Verrutschen**: Die 3-s-Regel las jeden langen Wheelie (10–28 s bei
  35–44°) als verrutschte Halterung — neun Mal auf Fahrt 1. Jetzt erst
  nach 60 s Abweichung, wie die 60-s-Regel der App; gekippte Sekunden
  (über 17°) lernen weder „unten" noch „vorn". Danach 0 Mal.

### 7.3 Ereignisse

- **Fahrt 1**: 12 Wheelies bei 15°/1 s gegen den Weg, beide Filter mit
  denselben Anfängen (±0,1 s), 1,5–23,6 s lang, 28–53°. Es sind genau
  die 12 der 17 aus der Rohregel, deren Kreisel-Drehung (25–43°) zur
  gelernten Vorwärtsrichtung passt. Weg sind vier vor dem Stehen von
  „vorn" und einer mit Front runter.
- **Fahrt 2**: 1 Wheelie statt 17 (39°, 1 s, im Schlussstück). Weg sind
  die übrigen 12 des Schlussstücks (Drehungen von 24–97°, meist um die
  Längsachse — Rollen, Hantieren oder Tragen, kein Wheelie), einer mit
  nur 3,5° Kreisel-Drehung (Fehlalarm der Rohregel) — aber auch drei
  echte lange Wheelies in den ersten sechs Minuten, die vor dem Stehen
  von „vorn" lagen.
- **Flüge**: keine Sprünge gefahren; je Fahrt 0–1 Phase unter 0,3 g
  über 150 ms, keine plausibel (die eine endete mit 12 g bei unklarem
  Tempo).

### 7.4 Folgerungen für Schritt 4

1. **Mahony in die App.** Auf allen Proben gleich gut wie der ESKF (Regel
   aus der Architektur: dann der einfachere). Der ESKF hält den Bias
   ruhiger (0,08 statt 0,93 °/s auf Fahrt 1); zeigen die Abnahmefahrten
   Drift, wird gewechselt — das Werkzeug rechnet beide weiter.
2. **Die Halterung von der letzten Fahrt mitnehmen**, mit „unten" in den
   ersten Sekunden bestätigen; sonst gehen Wheelies der ersten ein bis
   zwei Minuten verloren (Fahrt 2: drei).
3. **Eine Sekunde Vorlauf**: dv/dt kommt aus 1-Hz-GPS und wird zentriert
   gebildet; die App rechnet auf einem Puffer von 1–2 s, das Banner kommt
   so viel später. Ein Versatz der GPS-Zeitstempel (Kreuzkorrelation:
   schwaches Maximum bei +0,75–1 s) ist nicht eingerechnet.
4. **Werte**: Der Kreisel trägt (Rauschen 0,005 rad/s/√Hz, Bias-Wandern
   1e-6), die Beschleunigung stützt nur langsam (Boden 6 m/s² beim
   ESKF; Mahony Kp 2, Ki 0,1 mit eigenem Gewicht); das Fahrradmodell
   wird abgezogen, seine eigene Unsicherheit (halber Betrag, Änderung
   von dv/dt) zählt als Rauschen, und bevor „vorn" steht, zählt das
   ganze Modell als Rauschen.
5. **Rechenzeit**: reines Python 15–19 s je Fahrt für beide Filter und
   alle Schwellen; in Dart auf dem Gerät vernachlässigbar.

## Quellen

- R. Mahony, T. Hamel, J.-M. Pflimlin: Nonlinear Complementary Filters
  on the Special Orthogonal Group. IEEE TAC 53(5), 2008,
  doi:10.1109/TAC.2008.923738 — https://hal.archives-ouvertes.fr/hal-00488376
- J. Solà: Quaternion kinematics for the error-state Kalman filter.
  arXiv:1711.02508 — https://arxiv.org/abs/1711.02508
- N. Mimmo, M. Zanzi: High-Performance Motorbike Lean Angle Estimation.
  arXiv:2302.06265 — https://arxiv.org/abs/2302.06265
- Roll-Schätzung mit EKF ohne vollständiges Motorradmodell, FME
  Transactions 2020 — https://iris.unimore.it/handle/11380/1200349
- Estimating the Roll Angle for a Two-Wheeled Single-Track Vehicle
  Using a Kalman Filter. Sensors 22(22):8991, 2022 —
  https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9694013/
- S. Ludwig, K. Burnham: Comparison of Euler Estimate using Extended
  Kalman Filter, Madgwick and Mahony on Quadcopter Flight Data. ICUAS
  2018 — https://web.cs.ndsu.nodak.edu/~siludwig/Publish/papers/ICUAS2018.pdf
- Vergleich Komplementärfilter/Mahony mit VN-100-Daten (ASAT) —
  https://asat.journals.ekb.eg/article_194138_73f3764b1f11e55c532a08eabb6a5e26.pdf
- Improved Complementary Filters for Estimation of Heading and Attitude
  Angles in Accelerated Motion — https://maj.ihu.ac.ir/article_207940_en.html
- Zwei-Schritt-EKF, der die Kovarianz nach der Richtung der
  Fremdbeschleunigung anpasst, JSME Int. J. C 49(1):172, 2006 (Titel
  hier sinngemäß) —
  https://www.jstage.jst.go.jp/article/jsmec/49/1/49_1_172/_article
- Makni, Fourati, Kibangou: Energy-aware Adaptive Attitude Estimation
  Under External Acceleration for Pedestrian Navigation —
  https://hal.archives-ouvertes.fr/hal-01241403
- Android CDD 7.3 Sensoren —
  https://android.googlesource.com/platform/compatibility/cdd/+/android-cts-9.0_r3/7_hardware-compatibility/7_3_sensors.md
- Smartphone-Ausrichtung im Fahrzeug (Patente): US 10,462,608 —
  https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/10462608 ;
  US 10,876,859 —
  https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/10876859
- Wheelie-Erkennung am Fahrrad aus Pitch-Drehrate (Patent US 11,772,730) —
  https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/11772730
- Erfahrungen mit eingebauter Fusion am Rad (MbientLab-Forum) —
  https://mbientlab.com/community/discussion/comment/5692
- Gorges et al.: IMU Airtime Detection in Snowboard Halfpipe. Sensors
  24:6773, 2024 — https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11548732/
- Reliable jump detection for snow sports with low-cost MEMS inertial
  sensors (Sports Technology) — https://lida.sport-iat.de/twm/Record/4026432?lng=en
- Air-time-Algorithmus mit „jump characteristic points" (u. a. MTB) —
  https://lida.sport-iat.de/twm/Record/4029614?lng=en
- Halfpipe-Snowboard, Schwellen im Zeitbereich (SPIE 6799, 2007) —
  https://neurophotonics.spiedigitallibrary.org/conference-proceedings-of-spie/6799/679917/Feature-extraction-of-performance-variables-in-elite-half-pipe-snowboarding/10.1117/12.759259.full
- BMX-Airtime aus dem Ruck (MathWorks-Blog) —
  https://blogs.mathworks.com/community/2023/02/02/acquiring-and-analyzing-sensor-data-with-matlab-mobile-and-matlab-online/
- Spitzen unter Messbereich und Abtastrate —
  https://lida.sport-iat.de/ta/Record/4043300
- Messbereich von Handy-Sensoren (Forum, anekdotisch) —
  https://phyphox.org/forums/printthread.php?tid=1449
