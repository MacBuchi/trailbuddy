<p><strong>Deutsch</strong> · <a href="README.en.md" lang="en">English</a></p>

# TrailBuddy

<img src="store/play_icon_512.png" alt="TrailBuddy-Logo" width="64">

TrailBuddy ist eine Mountainbike-App für dein persönliches Trail-Netz. Du teilst
gefahrene Trails mit deinen Buddys, entdeckst ihre Beiträge und planst damit
deine nächste Runde.

[**Web-App öffnen**](https://macbuchi.github.io/trailbuddy/) ·
[**Android-App installieren**](https://macbuchi.github.io/trailbuddy/install.html) ·
[**Garmin-Uhr-App**](#garmin)

<p>
  <img src="docs/readme/android.webp" alt="Android-App mit farbigen Trails nach Schwierigkeit auf der Karte" width="211">
  <img src="docs/readme/web.webp" alt="Web-App mit Schwierigkeit und Höhenprofil des Canadian Trail" width="540">
</p>

*Android und Web mit Demodaten.*

## Android und Web im Vergleich

| Funktion | Android | Web |
| --- | --- | --- |
| Trail-Karte, Suche und Filter | ✓ | ✓ |
| Trails aus GPX-Dateien importieren | ✓ | ✓ |
| Buddys und Nachrichten | ✓ | ✓ |
| Trail-Zustand und Meldungen mit Foto | ✓ | ✓ |
| Runden und Routen planen | ✓ | ✓ |
| Offline-Karten | Eigene Bereiche und ganze Regionen | Eigene Bereiche im Browser |
| GPS-Fahrt aufzeichnen | ✓ | — |
| Sensor-Erkennung für Wheelies, Sprünge und Stoppies (Test) | ✓ | — |
| Garmin-Uhr verbinden | ✓ | — |

## Was TrailBuddy ausmacht

### Mit Buddys schreiben

Verabrede dich direkt im Buddy-Chat, etwa für die nächste Runde, einen
Treffpunkt oder eine Empfehlung für den besten Einstieg. Den Chat öffnest
du über die Sprechblase neben dem jeweiligen Buddy.

<img src="docs/readme/chat.webp" alt="Buddy-Chat mit einer Verabredung für eine Tour und einem Treffpunkt" width="211">

### Zustand und Hinweise am Trail teilen

Bewerte den Trail und schätze seine Schwierigkeit ein. Liegt nach dem
Sturm ein Baum quer oder ist der Trail wieder offen, kannst du das direkt
am Trail melden. Ein kurzer Text und ein Foto zeigen deinen Buddys, was sie
vor Ort erwartet.

<img src="docs/readme/report.webp" alt="Trail-Meldung mit Statusauswahl, Beispielhinweis und Schaltfläche zum Anhängen eines Fotos" width="388">

### MTB-Runden mit eigener Trail-Logik planen

Wähle Start, Zeit und Höhenmeter und vergleiche Rundenvorschläge nach
Fahrzeit, Anstieg und Schwierigkeit. TrailBuddy baut die Trails deines Netzes
in die Route ein. Abfahrtstrails plant es in Fahrtrichtung, sofern sie
nicht ausdrücklich in beiden Richtungen fahrbar sind. Markierte
Uphill-Trails und Verbindungen kommen als Zubringer infrage.

<img src="docs/readme/planner.webp" alt="Rundenplaner mit drei Trails auf der Karte, 12,5 Kilometern Strecke und alternativen Runden auf der Zeitskala" width="228">

### Offline-Karte und Routing zusammen speichern

Zeichne den gewünschten Bereich auf der Karte ein. Wo verfügbar, lädt
TrailBuddy auch Höhen-, Orts- und Wegedaten. Mit den gespeicherten Wegedaten
kannst du innerhalb des Bereichs auch ohne Empfang planen. Überlappende
Bereiche teilen sich Kacheln, und weitere Downloads holen nur fehlende
Daten nach.
Unter Android kannst du auch ganze Kartenregionen herunterladen.

<img src="docs/readme/offline.webp" alt="Offline-Download mit Vorschau für Speicherbedarf, Kacheln, Orte, Höhen und Wege" width="228">

## Nur auf Android

### Fahrt aufzeichnen und Sprünge erkennen

Zeichne deine GPS-Spur auch bei ausgeschaltetem Bildschirm auf. Nach der
Fahrt kannst du einzelne Abschnitte als Trails übernehmen und mit Buddys
teilen. Die optionale **Sensor-Erkennung (Test)** unter „Über TrailBuddy“
sucht während der Fahrt nach Wheelies, Sprüngen und Stoppies. In der
Live-Ansicht kannst du erkannte Ereignisse bestätigen oder verwerfen.

<p>
  <img src="docs/readme/ride.webp" alt="Laufende GPS-Aufzeichnung mit gefahrener Strecke auf der Android-Karte" width="211">
  <img src="docs/readme/airtime.webp" alt="Live-Ansicht der Sensor-Erkennung mit einem simulierten Wheelie und Tasten zum Bestätigen oder Verwerfen" width="260">
</p>

*Fahrtaufzeichnung und Sensor-Ansicht mit simulierten Messdaten.*

## Garmin

<p>
  <img src="garmin/shots/fenix5/deu/trail.png" alt="Route und verbleibende Trail-Strecke auf der fēnix 5" width="144">
  <img src="garmin/shots/fenix5/deu/abseits.png" alt="Abseitswarnung mit Abstand zur Route" width="144">
  <img src="garmin/shots/fenix5/deu/aufnahme.png" alt="Laufende Aufzeichnung auf der Garmin-Uhr" width="144">
</p>

[Alle Garmin-Ansichten auf Deutsch](garmin/shots/fenix5/deu).

Die Connect-IQ-App zeigt die vom Android-Handy gesendete Route an und
vibriert beim Verlassen der Route. Sie kann eine Fahrt auch ohne Handy
aufzeichnen und sie später über Garmin Connect an TrailBuddy auf dem
Android-Handy übertragen.

Die Uhr-App wurde auf der fēnix 5 am Gerät geprüft. Die weiteren Build-Ziele
stehen im [Garmin-Manifest](garmin/manifest.xml). Für die Einrichtung per USB
siehe die [Bau- und Installationshinweise](garmin/CLAUDE.md#technik-notizen).

## Mehr über TrailBuddy

[Was ist neu?](CHANGELOG.md) ·
[Roadmap](https://github.com/MacBuchi/trailbuddy/issues/520) ·
[Trail-Konzept](docs/konzept-trails.md) ·
[Für Mitwirkende](CLAUDE.md)
