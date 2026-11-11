---
name: watch-bench
description: Die Uhr-App und die Strecke Handy ↔ Uhr prüfen, ohne dafür eine Fahrt zu brauchen — welche Stufe der Prüfleiter eine Änderung braucht, die Befehle dazu, die Gegenprobe und die bekannten Fallen von Simulator, Emulator und Gerät. Nutzen, sobald etwas in garmin/, lib/features/garmin/, GarminBridge.kt oder docs/watch_cases.json geändert wird, wenn ein Feldbefund an der Uhr nachzustellen ist, vor einer Beförderung, die die Uhr berührt, oder wenn „teste die Uhr", „Garmin-Simulator", „Tischabnahme" oder „Kettenstand" fällt.
---

# Die Uhr prüfen

Konzept: `docs/konzept-garmin.md` Abschnitt 12 (die Prüfleiter),
Szenarien: `docs/konzept-geraete.md` Abschnitt 9, Technik und Fallen der
Uhr-App: `garmin/CLAUDE.md` (vorher lesen). Reihenfolge der offenen
Arbeit: #501.

Das Ziel ist nicht „alles im Simulator": Im Feld soll nur noch gemessen
werden, nicht gesucht. Jeder Ablauf bekommt seine Prüfung auf der
niedrigsten Stufe, die ihn finden kann.

## 1. Erst der Fall, dann der Code

1. Den Fall in `docs/watch_cases.json` unter `faelle` eintragen
   (Kennung `<Issue>.<n>`, `erwartung`, und womit er geprüft wird: `uhr`
   = Name des Monkey-C-Tests, `handy` = Titel des Dart-Tests, `szenario`
   = Konsolenzeilen des Vorführmodus, `kette` = Name eines Schritts im
   Treiber des Kettenstands, `integration_test/watch_bench_test.dart`).
2. Ihn an den Schritt eines Szenarios F1–F8 hängen (`szenarien`), oder
   einen Schritt ergänzen. Was noch nicht geprüft werden kann, steht als
   `offen: [Issue]`, was nur am Gerät geht, als `geraet`.
3. `tool/garmin_bench.sh cases` — rot, wenn ein Schritt ohne Prüfung
   dasteht oder ein Fall auf einen Test zeigt, den es nicht gibt.

## 2. Welche Stufe

| Geändert | Mindestens | Befehl |
|---|---|---|
| Kodierung, Protokoll, Logik am Handy (`lib/features/garmin/`) | S0 | `tool/garmin_bench.sh cases` |
| Bausteine der Uhr (`NavTracker`, `RideLog`, `PhoneRoute`, `RideStats`, `NavRoute`) | S1 | `tool/garmin_bench.sh unit` |
| Tasten, Menüs, Fristen, Rückfrage (`WatchCore.mc`) | S2: Ereignis-Skript in `CoreTests.mc` gegen `FakeHost` | `tool/garmin_bench.sh unit` |
| Der Wirt (`TrailBuddyApp.mc`: Timer, GPS, Senden, Menüs) | S2 + Vorführmodus | `tool/garmin_bench.sh scenario` |
| Zeichnen (`NavView.mc`, `Ring.mc`) | Vorführmodus ansehen, Bildschirmfoto | `tool/garmin_build.sh --demo` |
| `GarminBridge.kt`, Kanal, SDK; Nachrichten zwischen beiden Apps | S5 | `tool/garmin_bench.sh chain` |
| R8-Regeln, Garmin Connect, Hintergrund | S6 | `tool/garmin_bench.sh device` |
| Eine Nachricht, die beide Seiten kennen müssen | S0 + S1, und der Test, der beide Dateien liest (`test/garmin/watch_route_test.dart`, `watch_ride_test.dart`) | `cases`, `unit` |
| Vor einer Beförderung mit Uhr-Anteil | S6 | `tool/garmin_bench.sh device` |

`tool/garmin_bench.sh all` fährt alles, was ohne Gerät und ohne
Emulator geht. S2 (Ablaufkern) steht seit #508, S5 (Kettenstand) seit
#527; S3 und S4 (Gesprächskatalog, Golden) sind geplant: #509, #511.

**Der Kettenstand** (`chain`, nur 💻): startet den ersten AVD ohne
Fenster (läuft schon ein Emulator, nimmt er den), baut die Uhr mit
`--bench`, startet den Simulator frisch, `adb forward`, dann den Treiber
(`flutter test integration_test/watch_bench_test.dart --flavor dev`,
Tethered) — und erst wenn der „sdk-up" schreibt, klickt er im Simulator
„adb Connection → Start" und lädt die Uhr-App. Ergebnis je Schritt
unten in der Ausgabe, Protokolle `build/garmin/chain.log` (Handy) und
`chain-sim.log` (Uhr, mit `bench rx/tx`). `chain --break` lässt die Uhr
nie `ok` senden und ist grün, wenn die Kette genau dort rot wird — nach
einer Änderung am Skript oder Treiber einmal fahren. Ein Lauf dauert mit
gebautem Treiber gut 3 min, der erste Bau einige Minuten mehr.

## 3. Gegenprobe

Ein grüner Test beweist nichts, bevor er einmal rot war. Je neuem Test:
die Regel im Code kurz entschärfen (Schwelle auf 0, Bedingung weg), der
Test muss rot werden, zurückbauen. Mit Dateikopie und `trap`, sonst
bleibt die entschärfte Fassung liegen. Im PR steht, was entschärft
wurde und welcher Test rot war.

## 4. Fallen

**Simulator (Connect IQ)**
- Er muss laufen und bereit sein, bevor `monkeydo -t` startet (gut 10 s
  nach dem Öffnen) — sonst wartet `monkeydo` ohne Ausgabe.
- `--test` hängt nach einem `--demo`-Lauf oder mit einem Simulator, der
  schon länger offen ist: Der Bau gelingt, danach kommt nichts.
  `garmin_bench.sh unit` merkt das (60 s ohne neue Zeile), startet den
  Simulator neu und versucht es einmal wieder — so gesehen am 2026-11-11.
  Wer `garmin_build.sh --test` direkt ruft, muss `monkeydo`,
  `MonkeyDoDeux` und den Simulator selbst beenden.
- Nach einem Gerätewechsel (`GARMIN_DEVICE`) den Simulator neu starten.
- Tasten lassen sich von außen nicht drücken (Klick und Enter über
  System Events kamen nicht an). Abläufe mit Tasten prüft der Ablaufkern
  (`CoreTests.mc`).
- Ein Simulator-Bau sendet nicht (`sim`): `send` ruft nur
  `ack.onError()`. Für eine echte Übertragung braucht es `nosim`.
- Der Simulator ist milder als die Uhr: Was dort unter dem Watchdog
  (120 000 Schritte je Ereignis) durchläuft, kann am Gerät abbrechen.
  Nach jeder Schleife über Punkte: `tool/garmin_build.sh --demo --points 2000`.
- Bildschirmfotos nur vom Fenster des Simulators (`screencapture -R`
  mit dessen Lage, vorher nach vorn holen), nie vom ganzen Schirm.

**Handy und adb**
- `adb` liegt oft nicht im PATH; `garmin_bench.sh` sucht es selbst, sonst
  `ADB=…` setzen. Bei zwei Telefonen `ANDROID_SERIAL`.
- Logcat-Marke `TB-GARMIN`: `open <Status>`, `send <Status> after n of
  m`, `receive <Art>`. Garmin Connect meldet `SUCCESS` auch für eine
  geschlossene Uhr-App — nur `receive ok` heißt angekommen.
- Tethered (`--dart-define=GARMIN_TETHERED=true`, `adb forward tcp:7381
  tcp:7381`, auch gegen den Android-Emulator): **die Reihenfolge zählt**
  — erst die Handy-App bis zum ersten `status` (das SDK lauscht), dann im
  Simulator „adb Connection → Start", dann die Uhr-App laden. Ein
  `nosim`-Bau, der vor der Verbindung startet, öffnet im Simulator einen
  Dialog, und danach nimmt er keine App mehr an (`monkeydo` wartet stumm).
- Im Tethered-Modus meldet der Simulator seine App ohne Kennung:
  `GarminBridge.kt` hört dort deshalb auf `IQApp("")` (seit 0.168.2,
  #527). `openApplication` sagt dort immer `APP_IS_NOT_INSTALLED` — kein
  Fehler im Kettenstand.
- Jede Nachricht kostet im Tethered-Modus einen festen Schlaf des SDK
  („Simulating BLE"): eine Route in zwei Stücken bis `ok` 9,1 s, sehr
  gleichmäßig (2026-11-11). Zeiten aus S5 sind keine Feldzeiten (8.2).
- Der Bench-Bau verarbeitet Fixe aus `_f` einen je 50 ms: Alle in einem
  Ereignis brachen den Watchdog (`NavTracker.update` über die Linie) —
  ein Fehler des Prüfstands, am Gerät kommt ein Fix je Ereignis.
- Hängt ein echtes Telefon mit am Rechner, jeden adb-Aufruf auf den
  Emulator festlegen (`ANDROID_SERIAL=emulator-5554`) — das Pixel mit dem
  echten Konto wird nur gemessen, nie beschrieben.
- Der Simulator-Weg zeigt keinen R8-Fehler. Eine Abnahme der Brücke
  braucht den Release-Bau, Garmin Connect und die echte Uhr.

**Die echte Uhr**
- Vor jedem Test den Build-Stempel ansehen (oben in der Übersicht vor
  dem ersten Fix). Ein alter Stempel heißt: Die neue `.prg` ist nicht
  drauf — sie wirkt erst nach dem Abstecken.
- Ohne GPS-Fix zeigt die Karte nur „Warte auf GPS": drinnen wirkt eine
  gespeicherte Route, als fehle sie.
- „IQ!" ist ein Absturz: `GARMIN/APPS/LOGS/CIQ_LOG.YML` lesen, BEVOR
  Garmin Connect synchronisiert (danach heißt sie `.BAK`).

**Daten**
- Nie eine echte Fahrt oder Route ins Repo, auch nicht als Testdatei
  (A7). Erfundene Spuren macht `tool/garmin_route.py`; eine eigene Route
  geht mit `tool/garmin_build.sh --gpx` und bleibt unter `build/`.
- Keine Koordinaten und keine Ortsnamen in Berichte, Issues oder PRs.

## 5. Ein Feldbefund

1. Aufschreiben, was der Fahrer tat und was die Uhr zeigte — als Folge
   von Ereignissen (Taste, Nachricht, Zeit), nicht als Erzählung.
2. Die niedrigste Stufe suchen, die es hätte finden können, und dort
   den Test bauen, der es nachstellt (erst rot).
3. Fall in `watch_cases.json`, Schritt im Szenario.
4. Fand es erst das Gerät oder das Feld, steht im PR, welches Loch in
   der Leiter das war.

## 6. Wohin das Ergebnis gehört

- Eine Messung: `docs/konzept-garmin.md` Abschnitt 8, mit Datum und
  Zahl, und der Haken in #501.
- Eine neue Falle: `garmin/CLAUDE.md` (Uhr) oder hier (Prüfstand).
- Ein offener Punkt: ins Issue, nicht in den Verlauf.
