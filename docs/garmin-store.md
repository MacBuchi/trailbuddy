# Connect-IQ-Store — Ausfüllhilfe und Ablauf

Wie `docs/play-console.md`, aber für die Uhr-App (`garmin/`,
`docs/konzept-garmin.md` Abschnitt 5). Entscheidung des Betreibers vom
2026-11-07: **erst als Beta-App**, für die **240er-Familie**, das
Store-Paket **ohne Testroute**.

> **Warum das hier steht:** Ändern sich Berechtigungen im Manifest, die
> Uhrenliste oder das, was die Uhr ans Handy schickt, gehört diese Datei
> in denselben PR — dann sieht man beim Review, dass der Eintrag im Store
> nachzuziehen ist.

Stand: 7. November 2026. **Noch nicht hochgeladen.**

---

## 1. Vor dem ersten Hochladen (👤 Betreiber)

1. **Den Schlüssel sichern.** `~/.connectiq/developer_key.der` (und
   `.pem`) signiert das Paket. Jedes Update im Store muss mit
   DEMSELBEN Schlüssel signiert sein — geht er verloren, braucht es eine
   neue App mit neuer Kennung, und alle Nutzer müssen neu installieren.
   Sicherung privat beim Betreiber (Passwort-Manager/DocuHub), **nie in
   dieses Repo**.
2. **Die App-Kennung bleibt.** `BC6A9EE033EF433F803B4AF7D36E9667` im
   Manifest ist auch `kWatchAppId` in `lib/features/garmin/garmin_bridge.dart`
   (Test in `test/garmin/watch_route_test.dart`). Nie ändern — dann
   fände die Handy-App die Uhr-App aus dem Store nicht.
3. **Datenschutzerklärung öffentlich machen.** Der Eintrag verlinkt
   `https://macbuchi.github.io/trailbuddy/datenschutz.html`. Die
   öffentliche Fassung kommt aus der letzten Beförderung (0.142.0) und hat
   den Abschnitt „Garmin-Uhr" noch nicht (er kam mit 0.150.0). Vorher also
   eine aktuelle Fassung mit `promote.yml` befördern.
4. **Entwicklerkonto** bei Garmin (Connect IQ Developer, kostenlos) mit
   dem Garmin-Konto, das auch die fēnix 5 trägt — die Beta sieht nur
   dieses Konto.

## 2. Paket bauen (💻)

Aus einem sauberen Stand von `main` (sonst steht im Build-Stempel ein „+"):

```sh
tool/garmin_build.sh --store        # → build/garmin/trailbuddy.iq
tool/garmin_build.sh --store --run  # derselbe Zweig im Simulator (fēnix 5)
```

Vorher je Uhr die Unit-Tests: `GARMIN_DEVICE=<id> tool/garmin_build.sh
--test`, Simulator je Uhr neu gestartet (`garmin/CLAUDE.md`). Stand
2026-11-07: alle neun Uhren 22/22 grün.

Das Paket enthält: alle Uhren aus `garmin/manifest.xml`, ohne
Debug-Infos (`-r`), ohne Testroute und ohne Vorführmodus. Ohne Route vom
Handy beginnt die freie Fahrt (#484): GPS, die eigene Spur, Tempo und
Höhenmeter; aufgezeichnet wird wie immer, die Fahrt geht beim Beenden
ans Handy oder wartet auf der Uhr.

## 3. Hochladen als Beta (👤, dann 📱)

1. Im Developer-Bereich des Connect-IQ-Store eine neue App anlegen,
   `trailbuddy.iq` hochladen und als **Beta** markieren.
2. Versionsnummer im Formular: **1.0.0** für die erste Fassung. Sie ist
   unabhängig von der App-Version in `pubspec.yaml` (die Uhr-App ist
   nicht im APK).
3. Auf der fēnix 5 die per USB geladene `.prg` aus `GARMIN/APPS/`
   löschen, sonst laufen zwei Fassungen mit derselben Kennung. Dann über
   die Connect-IQ-App auf dem Handy installieren, wie ein Nutzer.
4. Abnahme am Gerät: Start ohne Handy (Hinweis, kein GPS), Navigation in
   der App mit „Auf der Uhr zeigen" (Route kommt, Wechsel, Abseits
   vibriert), Beenden auf beiden Seiten.
5. Läuft es, dasselbe Paket öffentlich einreichen; Garmin prüft es vor
   der Freigabe.

## 4. Eintrag im Store

**Name:** TrailBuddy

**Kategorie:** Navigation (falls nur Sport-Kategorien angeboten werden:
Radfahren)

**Kurzbeschreibung (DE):**
Deine Route aus der TrailBuddy-App am Handgelenk: Karte, Trails,
Abweichung, Anstieg.

**Kurzbeschreibung (EN):**
Your route from the TrailBuddy app on your wrist: map, trails, off-route
alert, climb.

**Beschreibung (DE):**

```
TrailBuddy zeigt die Route, die du in der TrailBuddy-App (Android)
navigierst, auf deiner Uhr — gedacht für Mountainbike-Trails.

- Karte mit der Route, den Trails darauf in ihrer Schwierigkeitsfarbe
  und den Abzweigungen an den Kreuzungen
- Vibration, wenn du von der Route abkommst
- Weg und Anstieg bis zum nächsten Trail und bis zum Ziel
- Seiten mit Tempo, Strecke, Höhenmetern und Puls
- Nach der Übertragung navigiert die Uhr auch ohne Handy weiter
- Freie Fahrt ohne Route: eigene Spur, Tempo, Strecke, Höhenmeter
- Aufzeichnung mit START, Pause-Menü mit Verwerfen, Trails markieren mit
  der Runden-Taste; die Fahrt geht beim nächsten Kontakt an die
  TrailBuddy-App auf dem Handy

Voraussetzung: die TrailBuddy-App auf einem Android-Handy und Garmin
Connect. Die Uhr-App legt keine Garmin-Aktivität an und hat keine
Verbindung ins Netz; eine Fahrt bleibt auf der Uhr, bis sie auf dem
Handy ist, die Route, bis die nächste sie ersetzt.
```

**Beschreibung (EN):**

```
TrailBuddy shows the route you navigate in the TrailBuddy app (Android)
on your watch — made for mountain bike trails.

- Map with the route, the trails on it in their difficulty colour and
  the branches at junctions
- Vibrates when you leave the route
- Distance and climb to the next trail and to the finish
- Pages with speed, distance, elevation gain and heart rate
- Once transferred, the watch keeps navigating without the phone
- Free ride without a route: your own track, speed, distance, climb
- Recording with START, pause menu with discard, trail marks with the
  lap button; the ride goes to the TrailBuddy app on the phone the next
  time they meet

Requires the TrailBuddy app on an Android phone and Garmin Connect. The
watch app creates no Garmin activity and has no internet connection; a
ride stays on the watch until it is on the phone, the route until the
next one replaces it.
```

**Datenschutz-Link:** `https://macbuchi.github.io/trailbuddy/datenschutz.html`
(englisch: `…/privacy.html`)

**Symbol:** `web/icons/Icon-512.png` — erzeugt von `tool/brand_icons.py`,
nie von Hand ersetzen.

**Bildschirmfotos:** aus dem Simulator, nur mit der erfundenen Testroute
(`tool/garmin_build.sh --demo`): Karte, Fahrt, Berg, Ankunft. Nie mit
einer echten Route (`--gpx`), eine Fahrt beginnt an der Haustür.

## 5. Was neu ist — Text fürs Update-Formular (👤)

Der Text kommt beim Hochladen einer neuen Fassung in das „What's new"-Feld.
Die Versionsnummer im Formular ist die der Uhr-App aus `garmin/VERSION`, nicht
die aus `pubspec.yaml`. Garmin nimmt kein Update mit derselben Nummer an: jede
hochgeladene Fassung braucht eine höhere. Semver dabei — neue Funktion Minor
(1.4.0), Fix und Feinschliff Patch (1.3.1); die Nummer steigt mit jedem Paket,
auch wenn inhaltlich dasselbe drin steht.

**1.3.1 (DE)** — nur was seit 1.3.0 anders ist, das Alte steht schon in der
Store-Beschreibung:

```
- Keine erfundene Testroute mehr im Paket: ohne Linie startet die Uhr in der
  freien Fahrt — GPS an, die eigene Spur der letzten 25 Minuten dünn in Moos,
  unten „Freie Fahrt“ mit Strecke, Minuten und Anstieg.
- Hat das Handy kein Navigationsziel, sucht es den Trail, dessen Linie am
  nächsten an der Uhr liegt (800 m Reichweite, mindestens 250 m lang), und
  schickt sie als Linie; die Uhr nimmt sie still. Liegt nichts da, bleibt sie
  bei ihrer eigenen Spur.
- Driftet die Uhr von so einer Linie ab, sagt sie es dem Handy, und das schickt
  den nächsten Trail in Reichweite — die Uhr fragt vorher, ob sie ihn nimmt.
- Die gezeichnete Spur zeigt auch, was vor START oder in einer Pause gelaufen
  ist; gespeichert wird weiterhin erst ab START.
```

**1.3.1 (EN):**

```
- The package ships no invented test route: with no line in the watch it starts
  free riding — GPS on, its own track of the last 25 minutes drawn faint moss,
  “Free riding” at the bottom with distance, minutes and climb.
- When the phone has no navigation target it looks for the trail whose line is
  nearest to the watch (800 m range, at least 250 m long) and sends it as a
  line; the watch takes it quietly. Nothing in range, nothing sent.
- When the watch drifts off such a line it tells the phone, and the phone sends
  the next trail in range — the watch asks first whether it should take it.
- The drawn track also shows what ran before START or during a pause; storage
  still only begins at START.
```

## 6. Berechtigungen (falls der Store danach fragt)

| Berechtigung | Wofür |
|---|---|
| `Positioning` | GPS der Uhr: eigene Position auf der Route, Abseits-Regel, die Fahrt auf der Uhr (geht nur ans eigene Handy) |
| `Sensor` | Puls vom Handgelenk, Kompass, Höhe vom Barometer — angezeigt; nur die Höhe geht in die Fahrt auf der Uhr, der Puls nie |
| `Communications` | Route und Bestwerte vom Handy empfangen, „gespeichert"/„beendet", die Fahrt mit ihren Trail-Marken und Start/Trail/Ende der Aufzeichnung (nur Uhrzeiten, seit 1.2.0) zurück — nur mit der TrailBuddy-App, kein Netz |

## 7. Uhren im Paket

fēnix 5, 5X, 5 Plus, 5X Plus, 5S Plus, 6S, Forerunner 935, 945, 945 LTE —
alle 240 × 240 px MIP mit fünf Tasten (die Ansicht ist darauf fest
gebaut). Am Gerät abgenommen: fēnix 5. Andere Größen erst mit einem
Layout, das aus der Bildschirmgröße rechnet (Konzept 6).
