# Gemerkte Startpunkte (#543)

*Angelegt am 2026-11-16 für #543. Idee des Betreibers vom 2026-11-13
zum Planer-Konzept (`konzept-routing.md` 12.3): „favorisierte
Startpunkte (Parkplätze) anlegen/auswählen, die ebenso geteilt werden
können mit Buddys … vereinfacht das Von-wo". Die Fragen in Abschnitt 0
und die Vorschläge in Abschnitt 9 hat der Betreiber am 2026-11-16
entschieden.*

## 0. Kurzfassung und Entscheidungen

Ein **Startpunkt** ist ein benannter Punkt, den jemand bewusst anlegt:
ein Parkplatz, der Eingang eines Trailcenters, die Bushaltestelle am
Talboden. Er macht die Frage „Von wo?" im Einstiegsblatt des Planers zu
einem Tipp, und Buddys bekommen ihn wie einen Trail mit.

Entschieden (Betreiber, 2026-11-16):

1. **Sichtbarkeit wie ein Trail-Beitrag**: Vorgabe „Buddys", je Punkt
   auf „privat" umschaltbar. Sehen können ihn nur direkte Buddys, und
   nichts wird weitergereicht (A2).
2. **Anzeige im Planer und auf der Karte**: im Planer als dritte Wahl in
   der Zeile „Start" (bei der Route auch „Ziel"), auf der Karte als Pin
   einer eigenen Ebene, die man unter „Ebenen" wie die Orte abschaltet.
3. **Anlegen auf vier Wegen**: aus dem Ort-Blatt („Als Startpunkt
   merken" an einem Parkplatz o. ä.), per langem Druck auf die Karte,
   aus dem Planer-Ergebnis („Start merken") und mit „Mein Standort
   merken", das vor der Haustür warnt (Abschnitt 4).

## 1. Was ein Startpunkt ist — und was nicht

- **Name, Lage, Sichtbarkeit.** Mehr nicht: kein Foto, keine Bewertung,
  kein Kommentar, kein Zustand. Der Name ist frei (1–60 Zeichen),
  vorbelegt aus dem Ort („Parkplatz Mühlbach") oder leer.
- **Er gehört dem, der ihn anlegt.** Anders als ein Trail gibt es keine
  besitzerlose Kennung und keinen Abgleich: Zwei Buddys, die denselben
  Parkplatz merken, haben zwei Punkte. Liegen ein eigener und ein
  fremder Punkt näher als 30 m beieinander, zeigt die Karte den eigenen,
  und die Liste im Planer nennt den Platz einmal mit dem eigenen Namen.
  So entsteht keine Zusammenführung und kein Zähler („3 Buddys parken
  hier"), den A1 ausschließt.
- **Nie aus Fahrten abgeleitet.** Kein „häufiger Start", kein Vorschlag
  aus den Anfängen aufgezeichneter Fahrten (A3, A7). Ein Startpunkt
  entsteht nur durch einen Tipp auf „Merken".
- **Kein Verweis auf den Ort der Karte.** Ein Startpunkt aus dem
  Ort-Blatt übernimmt Name und Lage, merkt sich aber keine OSM-Kennung:
  Die Ortsdateien werden monatlich neu gebaut (`lib/features/map/CLAUDE.md`,
  „Orte auf der Karte"), und ein Verweis wäre beim nächsten Bau tot.

## 2. Datenmodell

Neue Tabelle `public.start_points` (Patch 030), Struktur in
`schema.sql`, Eintrag in der Saat-Liste:

| Spalte | Typ | Bemerkung |
|---|---|---|
| `id` | `uuid` pk | `gen_random_uuid()` |
| `user_id` | `uuid` | → `profiles(id) on delete cascade` |
| `name` | `text` | `check (char_length(btrim(name)) between 1 and 60)` |
| `lat`, `lon` | `double precision` | mit Bereichs-Check; kein PostGIS nötig, nichts rechnet auf dem Server mit der Lage |
| `visibility` | `text` | `'buddies'` (Vorgabe) oder `'private'`, derselbe Check wie `trail_details.visibility` |
| `client_id` | `uuid` not null | der Schlüssel der App: unique je `user_id` (echter Constraint), Anlegen/Umbenennen/Umschalten sind ein Upsert darauf, Löschen ein Delete — so wiederholt der Ausgangskorb jeden Auftrag gefahrlos |
| `created_at`, `updated_at` | `timestamptz` | `updated_at` über `touch_updated_at()` |

**RLS:**

- `select`: `user_id = auth.uid()` oder (`visibility = 'buddies'` und
  `app_internal.are_friends(user_id, auth.uid())`). Endet die
  Freundschaft, sind die Punkte sofort weg; es braucht keinen Trigger.
- `insert`, `update`, `delete`: nur `user_id = auth.uid()`. Ein Buddy
  kann einen fremden Punkt weder umbenennen noch löschen; anders als
  beim Hinweis gibt es hier kein „erledigt".
- Grants: `select, insert, update, delete` an `authenticated`.
  `auto_expose_new_tables = false` lässt einen vergessenen Grant im Dry
  Run auffallen.
- **Obergrenze 100 je Konto**, geprüft per Trigger: Das schützt vor
  einem Ausgangskorb in einer Schleife, für den Gebrauch reicht es. Der
  Upsert auf einen vorhandenen Punkt zählt nicht mit, sonst ließe sich am
  Limit nichts umbenennen; die App prüft die Grenze schon vor dem Korb.

**Kontolöschung:** Die Punkte gehen per Cascade mit dem Profil. Sie
gehören in die Liste dessen, was `delete_own_account()` mitnimmt, und
damit auch in den Text der Datenschutzerklärung.

**`schema_check.sh`:** Er bekommt die Abfragen der App (Liste, Anlegen,
Umbenennen, Umschalten, Löschen) und die Gegenprobe, dass ein Fremder
ohne Freundschaft nichts sieht und ein Buddy keinen privaten Punkt.

## 3. Die Kernanforderungen

| | berührt? | wie |
|---|---|---|
| A1 | ja | keine Suche, keine Liste über Buddys hinaus, kein Zähler, keine Zusammenführung (1) |
| A2 | ja | RLS wie oben, nur direkte Buddys, Schalter „privat" am Punkt |
| A3 | ja | nie aus Fahrten; „Mein Standort merken" warnt und ist privat vorbelegt (4) |
| A4 | nein | kein Abgleich |
| A5 | nein | keine Kopplung |
| A6 | ja | neue Datenkategorie ⇒ `web/datenschutz.html`, `web/privacy.html`, `docs/play-console.md` im Schema-PR |
| A7 | ja | Tests mit erfundenen Koordinaten, keine echten Parkplätze des Betreibers |
| A8 | ja | Liste in der Offline-Kopie, Anlegen über den Ausgangskorb (6) |
| A9 | ja | Ebene über die Fassade, Kopie im Browser in IndexedDB |
| A10 | ja | Warnung vor der Haustür, kein Verbot |
| A11–A12 | nein | — |
| A13 | ja | Pins und Zeilen ≥ 44 dp; eigene und fremde Punkte unterscheiden sich durch die Form, die Farbe kommt aus der Palette |
| A14 | ja | jeder Text in `app_de.arb` und `app_en.arb` |

## 4. Anlegen

Alle vier Wege enden im selben kleinen Dialog: **Name** (vorbelegt,
wenn es einen gibt), **„Buddys sehen ihn"** als Schalter, **Merken**.

| Weg | Wo | Name vorbelegt | Schalter vorbelegt |
|---|---|---|---|
| Ort-Blatt | „Als Startpunkt merken" unter „Start im Planer" / „Ziel im Planer" | Name des Ortes, sonst seine Art („Parkplatz") | Buddys |
| Langer Druck | fünfter Eintrag im Menü: Start hier · Ziel hier · Zwischenpunkt hier · Mit der Navi-App hierher · **Als Startpunkt merken** | leer | Buddys |
| Planer-Ergebnis | „Start merken" an der Startzeile im Kopf (12.6), nur wenn der Start nicht schon ein gemerkter ist | Name des Starts, wenn es ein Ort war | Buddys |
| Mein Standort | im Einstiegsblatt unter der Liste der gemerkten Punkte: „Mein Standort merken" | leer | **privat** |

**Die Haustür.** „Mein Standort merken" ist der einzige Weg, auf dem
ein Punkt leicht dort entsteht, wo man wohnt. Deshalb steht der
Schalter dort auf „privat" (9), und unter dem Schalter
steht ein Satz: „Liegt der Punkt bei dir zu Hause? Dann lass ihn
privat — Buddys sähen sonst, wo du wohnst." Das ist eine Warnung und
kein Riegel (A10). Auf den anderen drei Wegen fehlt der Satz: Wer einen
Ort der Karte oder eine Stelle antippt, wählt den Punkt mit Absicht.

## 5. Anzeige

### 5.1 Im Planer

Die Zeile „Start" im Einstiegsblatt (`loop_entry_sheet.dart`,
`konzept-routing.md` 12.3) bekommt eine dritte Wahl:

```
Start   (•) Mein Standort
        ( ) Auf der Karte wählen
        ( ) Gemerkt  ▸  Parkplatz Mühlbach · 2,1 km
```

- **„Gemerkt"** gibt es nur, wenn es mindestens einen eigenen oder
  sichtbaren fremden Punkt gibt. Ein Tipp klappt eine Liste auf: eigene
  und fremde Punkte gemischt, sortiert nach Abstand vom Standort (ohne
  Standort von der Kartenmitte), mit dem Abstand rechts. Fremde Punkte
  tragen den Buddy-Namen (Alias, `buddyText`).
- **Vorbelegt ist ein gemerkter Punkt nur vor Ort**: Steht man
  höchstens 300 m davon entfernt, ist er die Wahl, und am Parkplatz
  bleibt es bei Planer → „Runde vorschlagen". Sonst bleibt „Mein
  Standort" vorn, und der zuletzt gewählte Punkt steht oben in der
  Liste (9).
- Bei der **Route** steht „Gemerkt" auch in der Zeile „Ziel".
- Ein gewählter Punkt ist für den Planer ein Start wie ein Ort
  (`takePlace`): die Lage, beschriftet mit dem Namen.

### 5.2 Auf der Karte

- Eine Ebene **„Startpunkte"** im Blatt „Ebenen", standardmäßig an,
  abschaltbar wie die Orte.
- **Pin**: eigenes Symbol (Vorschlag: Fahne auf einem Kreis, nicht das
  „P" der Parkplätze, damit der Punkt nicht wie ein Ort der Karte
  aussieht). Eigene Punkte in Markenfarbe, fremde in der Buddy-Farbe,
  dazu eine andere Form für A13 (eigene gefüllt, fremde mit Ring). Die
  Linienfarben der Karte bleiben hell (`AppColors.mapLines`). Das
  Aussehen legt der Bau-PR in `docs/design/README.md` fest.
- **Tipp auf den Pin** öffnet ein Blatt wie das Ort-Blatt: Name, „von
  <Buddy>" oder „privat"/„Buddys sehen ihn", dazu **Start im Planer ·
  Ziel im Planer · Mit der Navi-App hierher** (die Anfahrt mit dem Auto
  ist der häufigste Fall). Am eigenen Punkt kommen **Umbenennen ·
  Buddys sehen ihn (Schalter) · Löschen** dazu.

## 6. Offline und Web

- **Lesen**: Die Punkte kommen als vierter Teil in die Offline-Kopie
  des Netzes (`trail_cache/network.json`, `lib/data/CLAUDE.md`,
  „Zwischenspeicher des Netzes"), mit derselben Regel: Die Kopie liest
  nur `looksOffline`, sie wirft nie, und der Stand nennt sein Alter. So
  ist die Liste am Parkplatz ohne Empfang da (A8).
- **Schreiben**: Anlegen, Umbenennen, Umschalten und Löschen gehen über
  den Ausgangskorb, und die `client_id` macht das Wiederholen
  idempotent. Ein gerade angelegter Punkt steht sofort in der Liste und
  auf der Karte, ohne dass das Netz neu geladen wird („Speichern ohne
  Neuladen des Netzes").
- **Web**: Die Kopie liegt in IndexedDB wie die des Netzes. Die Ebene
  läuft über die Kartenfassade, also auf beiden Engines (A9).

## 7. Datenschutz und Play Console

Im Schema-PR (A6):

- `web/datenschutz.html` und `web/privacy.html`: eine neue Kategorie
  „Gemerkte Startpunkte (Name, Lage, Sichtbarkeit)". Zweck: Planen. Wer
  sie sieht: man selbst und, wenn nicht privat, die direkten Buddys.
  Gelöscht werden sie mit dem Punkt oder dem Konto.
- `docs/play-console.md`: Standort, genau, vom Nutzer eingegeben, mit
  Buddys geteilt, löschbar. Der Abschnitt zum Datenschutz nennt den
  Fall neben den Trail-Beiträgen.

## 8. Bewusst nicht

- kein Startpunkt aus Fahrten, kein „häufiger Start", kein Vorschlag
  „Hier hast du schon fünfmal geparkt" (A3);
- keine Suche nach Startpunkten, keine Liste über die eigenen Buddys
  hinaus, kein Zähler, keine Zusammenführung gleicher Plätze (A1);
- kein Weitergeben eines fremden Punktes (A2); wer ihn behalten will,
  merkt ihn selbst neu („Als Startpunkt merken" steht auch am fremden
  Pin);
- keine Fotos, Bewertungen, Öffnungszeiten oder Parkgebühren;
- kein Push, wenn ein Buddy einen Punkt anlegt;
- auf der Uhr erst mit dem Routenregal (#515), nicht in diesem Thema.

## 9. Entschieden nach dem Entwurf (Betreiber, 2026-11-16)

1. **„Mein Standort merken" ist privat vorbelegt** (4), alle anderen
   Wege stehen auf „Buddys": Eine verratene Haustür lässt sich nicht
   zurückholen, ein Tipp mehr kostet nichts.
2. **Obergrenze 100 je Konto** (2); wer sie erreicht, bekommt einen
   Satz statt eines Fehlers.
3. **Gleicher Platz innerhalb von 30 m**: Der eigene Punkt verdeckt den
   fremden, auf der Karte und in der Liste (1).
4. **Vorbelegt nur vor Ort**: Ein gemerkter Punkt steht in der Zeile
   „Start" nur dann vorn, wenn der Standort höchstens 300 m davon
   entfernt ist. Sonst bleibt „Mein Standort" vorn, und der zuletzt
   gewählte Punkt steht oben in der Liste „Gemerkt". Der erste Entwurf
   (zuletzt gewählter Punkt bis 50 km) hätte am Dienstag zu Hause still
   vom Parkplatz des Samstags gerechnet.

## 10. Umsetzung (je ein PR)

| Schritt | Inhalt | Typ |
|---|---|---|
| 1 | Patch 030 `start_points` + RLS + Grants + Trigger, `schema_check.sh`, Repository, Fakes mit RLS, Offline-Kopie, Ausgangskorb, Datenschutz/Play Console | `feat(db)` |
| 2 | Karte: Ebene, Pin, Blatt; Anlegen über Ort-Blatt und langen Druck; Design-README | `feat(map)` |
| 3 | Planer: „Gemerkt" in Start/Ziel, „Mein Standort merken", „Start merken" im Ergebnis; Neuheiten-Eintrag mit Vorführung | `feat(routing)` |

Umgebung: ☁️ Bau (der Schema-Dry-Run läuft in CI) · 📱 Abnahme mit zwei
Konten (sieht der Buddy den Punkt, den privaten nicht, nach dem
Entfreunden keinen mehr; Liste am Parkplatz ohne Netz).
