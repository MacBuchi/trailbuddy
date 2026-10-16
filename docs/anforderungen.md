# TrailBuddy — Kernanforderungen

*Angelegt am 2026-10-16 für #221 (Wunsch des Betreibers aus der App,
0.82.1: „Neue Funktionen als auch Bugfixes sollten diese bei der
Konzepterstellung schon berücksichtigen"). Die Datei erfindet nichts
Neues: Sie zieht die Regeln zusammen, die schon im Konzept, im Design
und in den Entscheidungen des Betreibers stehen, und sagt zu jeder, wo
sie herkommt und was sie heute prüft.*

## Wie man sie benutzt

- **Vor dem Bauen** — beim Plan zu einem Issue, auch bei einem
  Fehler — die Liste einmal durchgehen: Welche Anforderung berührt die
  Änderung? Die Nummern (A1 …) gehören in den Plan, wenn eine berührt
  ist.
- **Widerspricht eine Änderung einer Anforderung**, wird nicht still
  gebaut: Entweder ändert sich der Plan, oder der Betreiber entscheidet
  die Ausnahme — dann ändern sich diese Datei UND die Quelle (meist
  `konzept-trails.md`) im selben PR. So kam z. B. der Navigationsmodus
  zu A12 (#232).
- **Im PR** bestätigt die Checkliste der Vorlage
  (`.github/pull_request_template.md`), dass die Liste geprüft wurde.
- **Maßgeblich bleibt die Quelle.** Steht hier etwas anderes als im
  Konzept oder im Design, gilt die Quelle, und diese Datei wird
  nachgezogen.

„Geprüft durch" nennt, was heute in CI über die Regel wacht. Wo dort
„Review" steht, wacht nur der Mensch — dort lohnt das genaue Hinsehen.

## Vertrauen und Daten

**A1 — Nichts ist öffentlich.** Keine Karte für alle, keine Suche nach
Trails, kein Verzeichnis, keine Aggregation über das eigene Netz hinaus
(keine Heatmap, keine Zähler, keine „beliebten Trails in der Nähe").
Ohne Buddys ist die Karte leer bis auf das Eigene; Buddys findet man
nur über den exakten Namen oder die E-Mail, ohne Liste.
*Quelle:* Konzept 0 (6), 7, 13 (1).
*Geprüft durch:* RLS in `supabase/schema.sql` (Schema Dry Run,
`tool/schema_check.sh`), die Fakes in `test/fakes/` spiegeln sie.

**A2 — Sichtbar ist nur Eigenes und das direkter Buddys; nur
Gefahrenes wandert weiter.** Nichts transitiv, kein „Weitergeben auf
Tastendruck". Was man sieht, ist ausschließlich aus sichtbaren
Beiträgen gerechnet.
*Quelle:* Konzept 0 (3), 10.1.
*Geprüft durch:* RLS, `fake_trails.dart`, `tool/matcher_check.sql`.

**A3 — Trail ≠ Fahrt ≠ Aufzeichnung; Fahrten verlassen das Gerät
nie.** Eine Fahrt beginnt an der Haustür. Es gibt keine Tabelle für
Fahrten, Sicherung ist der GPX-Export; zum Server geht nur der
Ausschnitt, der einen Trail belegt.
*Quelle:* Konzept 0 (1), 10.4, 13 (4).
*Geprüft durch:* Review — eine neue Tabelle oder ein Upload, der mit
gefahrener Zeit wächst, ist eine Konzeptänderung.

**A4 — Der Abgleich verrät nichts.** Er läuft still auf dem Server
gegen alle Trails und bestätigt nur, was der Beitragende schon in der
Hand hat; keine Antwort, kein Fehler und keine Zeitspanne darf sagen,
OB andere einen Trail haben.
*Quelle:* Konzept 0 (4), 4.6.
*Geprüft durch:* `tool/matcher_check.sql`, `trails` ohne Client-Grant
(`supabase/CLAUDE.md`).

**A5 — Integration per Datei, nie per Konto.** GPX hinein und hinaus,
Übergabe an die Navi-App des Nutzers; keine Kopplung an Komoot,
Outdooractive, Strava, Garmin oder Trailforks.
*Quelle:* Konzept 13, #156 (Positionierung).
*Geprüft durch:* `test/privacy_policy_test.dart` (jeder Host), Review
von `pubspec.yaml` (kein OAuth-Paket).

**A6 — Kein Netzziel, keine Berechtigung, keine Datenkategorie ohne
Erklärung.** Jeder neue Host steht in `web/datenschutz.html` und
`web/privacy.html`, jede neue Berechtigung oder Datenkategorie
zusätzlich in `docs/play-console.md` — im selben PR.
*Quelle:* `web/CLAUDE.md`, Konzept 7.
*Geprüft durch:* `test/privacy_policy_test.dart`,
`test/android_manifest_test.dart`.

**A7 — Nichts Privates ins Repo.** Keine GPX- oder Zip-Dateien, keine
Koordinaten in Berichten, keine absoluten Pfade oder privaten
Mailadressen des Betreibers. Messberichte nennen Kennzahlen.
*Quelle:* Root-`CLAUDE.md`, Konzept 10.5.
*Geprüft durch:* `tool/private_info_check.py` (CI).

## Verhalten der App

**A8 — Offline zuerst.** Was im Wald gebraucht wird, geht ohne Netz:
Karte und Trails der gespeicherten Bereiche, Aufzeichnen, Routing über
die Kacheln auf dem Gerät. Ein Beitrag ohne Netz wartet im Ausgangskorb
und geht nicht verloren; ein Netzfehler zeigt den letzten Stand mit
seinem Datum statt einer leeren Seite.
*Quelle:* Konzept 13 (4), `konzept-offline-karten.md`,
`lib/data/CLAUDE.md` (Ausgangskorb, Zwischenspeicher).
*Geprüft durch:* Tests unter `test/outbox/` und `test/offline_areas/`;
die Prüfung im Browser bzw. am Gerät ohne Netz (📱).

**A9 — Web ist gleichwertig.** Jede Funktion läuft auf beiden
Karten-Engines (MapLibre auf Android, flutter_map im Web); nur das
Aufzeichnen bleibt Android.
*Quelle:* Konzept 10.8.
*Geprüft durch:* „Build Web" in CI, `FakeMapView` in den Tests; Review,
ob eine neue Kartenfunktion über die Fassade läuft
(`lib/features/map/CLAUDE.md`).

**A10 — Im Zweifel die Warnung, aber kein Riegel.** Wo die App
unsicher ist, zeigt sie die vorsichtigere Aussage: bei Gleichstand der
schwerere S-Grad, ohne Einschätzung fällt ein Trail aus einem engen
S-Filter. Risiken
(Schutzgebiet, Sperrung, Sicherheitshinweis) werden gesagt, nicht
gesperrt — keine Bevormundung, aber auch kein Schweigen.
*Quelle:* Konzept 7, `lib/features/trails/CLAUDE.md` (Schwierigkeit,
Filter), `lib/features/help/CLAUDE.md` (Sicherheitshinweis).
*Geprüft durch:* die Tests der jeweiligen Stelle; Review bei jeder
neuen Anzeige von Schwierigkeit oder Zustand.

**A11 — Die Plattform lädt nicht zum Falschen ein.** Keine
Bau-Features (kein „Trail im Bau", keine Arbeitseinsätze), kein Status
„legal/illegal" am Trail, Rankings und Airtime nur unter Buddys, nie
global.
*Quelle:* Konzept 7, 9.
*Geprüft durch:* Review.

**A12 — Navigation zeigt, sie sagt nicht an.** Keine Abbiegehinweise,
keine Sprachausgabe; der Navigationsmodus zeigt Route, Position und
Abstand. Geplant wird nur über Kacheln, die auf dem Gerät liegen. Die eine
Planungsfunktion ist der Trail-zuerst-Planer.
*Quelle:* Konzept 13, `konzept-routing.md` (Nicht-Ziele).
*Geprüft durch:* Review.

## Bedienung und Aussehen

**A13 — Mit Handschuhen und in der Sonne bedienbar.** Tippziele
mindestens 44 dp; hell und dunkel, Farben nur aus `AppPalette` bzw.
`AppColors`, Text in Markenfarben über `accentText`/`warningText`/
`buddyText`. Die Karte ist immer hell. Die Farbe eines Trails sagt
seine Schwierigkeit, der Charakter ist Symbol, nie Farbe. Jede
Animation ist aus, wenn das System es will.
*Quelle:* `docs/design/README.md` (1, 2, 6, 9), Root-`CLAUDE.md`
(Code-Konventionen).
*Geprüft durch:* Widget-Tests der Stelle; Review gegen das Design, die
Abnahme am Gerät (📱).

**A14 — Jeder Text in beiden Sprachen.** Kein UI-Text im Code, jeder
Schlüssel in `app_de.arb` (Vorlage) und `app_en.arb`; jeder Changelog-
Block in beiden Dateien; die Rechtsseiten in beiden Fassungen.
*Quelle:* `lib/l10n/CLAUDE.md`, #209.
*Geprüft durch:* `test/l10n_test.dart`, `test/changelog_test.dart`,
`test/privacy_policy_test.dart`.

## Pflege

Eine Anforderung kommt dazu oder fällt weg nur mit einer Entscheidung
des Betreibers — dann im selben PR wie die Quelle, die sie trägt. Eine
neue Prüfung, die eine „Review"-Zeile ablöst, trägt man unter
„Geprüft durch" ein.
