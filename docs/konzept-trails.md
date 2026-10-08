# TrailBuddy — Konzept: Trails, Duplikate und das Community-Tor

*Entwurf vom 2026-09-27, vor jeder Umsetzung. Die acht Entscheidungen
in Abschnitt 10 hat der Betreiber am selben Tag getroffen; das
Dokument ist damit die Grundlage für Phase 0. Deutsch, weil es ein
Arbeitspapier für den Betreiber ist; auf GitHub wird Englisch
gesprochen (Commits, Issues, PRs — Regel aus PilzBuddy).*

## 0. Kurzfassung

Das Buddy-Prinzip von PilzBuddy trägt für Trails nur zur Hälfte: Ein
Pilz-Spot ist ein privates Objekt mit einem Besitzer, ein Trail ist ein
Objekt auf dem Boden, das viele Leute kennen und jeder anders nennt.
Das Konzept löst das mit einer Trennung, die es in PilzBuddy nicht
gibt:

1. **Trail, Fahrt und Aufzeichnung sind drei verschiedene Dinge.** Ein
   Trail ist ein Stück Weg mit Anfang, Ende und Richtung. Eine Fahrt ist
   das, was das GPS an einem Tag aufgezeichnet hat (Haustür bis
   Haustür). Eine Aufzeichnung ist der Ausschnitt einer Fahrt, der einen
   Trail belegt. **Fahrten verlassen das Gerät nie.**
2. **Es gibt eine globale Trail-Datenbank, aber der Trail hat keinen
   Besitzer und keine Eigenschaften.** Der kanonische Trail ist nur eine
   Kennung. Alles Sichtbare — Linie, Name, Beschreibung, Schwierigkeit —
   ist ein **Beitrag** eines Nutzers zu dieser Kennung.
3. **Sichtbarkeit ist eine eigene Schicht:** Du siehst einen Trail genau
   dann, wenn du ihn selbst gefahren bist (eigener Beitrag) oder ein
   direkter Buddy ihn gefahren ist. Was du siehst, ist AUSSCHLIESSLICH
   aus diesen sichtbaren Beiträgen gerechnet. Sehen ist nicht
   Weitergeben; nur Gefahrenes wird weitergegeben.
4. **Duplikate werden beim Beitrag erkannt, serverseitig, still und
   gegen ALLE Trails** — nicht nur gegen das eigene Netz. Das ist
   leak-frei, weil der Abgleich nur bestätigt, was der Beitragende schon
   in der Hand hat: Wer eine Linie hochlädt, die einen Trail zu 80 %
   trifft, kennt den Trail. Er erfährt dabei nichts, was er nicht schon
   wusste — nicht einmal, OB andere den Trail haben.
5. **Beim Verbinden gibt es keinen Konflikt mehr, sondern eine
   Verschmelzung:** gemeinsame Trails werden EIN Trail mit zwei Namen,
   der Rest kommt dazu.
6. **Das Tor ist sozial, nicht technisch.** Es leistet Datensparsamkeit
   (keine öffentliche Karte, kein Verzeichnis, nichts ohne Buddys), es
   leistet keinen Schutz gegen jemanden mit Absicht. Das Konzept sagt,
   was die Plattform deshalb nicht tut (Abschnitt 7).

## 1. Warum das PilzBuddy-Modell hier nicht trägt

In PilzBuddy ist die Welt einfach: Ein Spot gehört einem Nutzer, der
teilt ihn mit Buddys, Funde hängen am Spot. Zwei Nutzer, die dieselbe
Stelle kennen, legen zwei Spots an — das kommt vor, ist aber selten
(Fundstellen sind privat) und es gibt dafür „Zusammenführen" im
Spot-Blatt.

Bei Trails ist die Dublette der Normalfall, nicht die Ausnahme:

- **Jeder Ortsansässige hat die meisten Trails seiner Gegend.** Zwei
  Leute aus derselben Stadt, die sich verbinden, haben 80 % Überlappung.
  Mit dem Spot-Modell hätte jeder danach jeden Trail doppelt auf der
  Karte, mit zwei Namen und zwei Bewertungen.
- **Ein Trail hat keinen natürlichen Besitzer.** Wer ihn zuerst
  hochgeladen hat, ist eine Zufallsfrage und keine Grundlage für „wessen
  Name gilt" oder „wer darf ihn löschen".
- **Das Löschen eines Beitrags darf den Trail nicht löschen**, wenn
  andere ihn belegen — und umgekehrt darf ein Nutzer nach DSGVO seine
  eigene Aufzeichnung zurückziehen.
- **Ein Trail ist eine Linie, kein Punkt.** „Derselbe Ort" ist bei
  Punkten ein Radius (in PilzBuddy 20 m). Bei Linien ist es eine
  Ähnlichkeitsfrage mit Teilüberlappungen, Abzweigungen, Gegenrichtung.

Die Antwort ist die Trennung von Identität (Trail) und Aussage
(Beitrag), wie sie OpenStreetMap zwischen `way` und GPS-Trace macht, und
wie Strava sie zwischen Segment und Aktivität macht.

## 2. Begriffe

| Begriff | Bedeutet | Wem gehört es | Verlässt das Gerät |
|---|---|---|---|
| **Fahrt** | Eine GPS-Aufzeichnung von Start bis Ziel, mit Zeiten. | dem Nutzer, gerätelokal | **nie von selbst** (nur als GPX-Export von Hand, #150) |
| **Aufzeichnung** | Ein Ausschnitt einer Fahrt (oder einer importierten GPX-Datei), der einen Trail belegt: Linie, Zeitpunkt, Richtung, GPS-Qualität. | dem Nutzer | ja, an den Server |
| **Trail** | Die Kennung für „dieses Stück Weg auf dem Boden". Trägt selbst nichts Sichtbares. | niemandem | — |
| **Beitrag** | Alles, was ein Nutzer über einen Trail sagt: Name, Beschreibung, S-Grad, Typ, Status, Sichtbarkeit. Genau einer je Nutzer und Trail. | dem Nutzer | ja |
| **Netz** | Die Trails, die ich sehe: eigene Beiträge plus Beiträge direkter Buddys. | — | — |

Im Deutschen der Oberfläche heißt ein Trail „Trail"; „Strecke" oder
„Abfahrt" wären enger (nicht jeder Trail geht bergab).

## 3. Datenmodell

Supabase/Postgres wie in PilzBuddy, dazu **PostGIS** (auf Supabase
verfügbar, Erweiterung einschalten). Skizze, kein fertiges Schema:

```sql
-- Die Kennung. Bewusst ohne Name, ohne Besitzer, ohne created_at in der
-- API-Sicht: Nichts in dieser Zeile darf verraten, dass jemand anderes
-- den Trail schon hatte.
create table public.trails (
  id uuid primary key default gen_random_uuid()
);

-- Ein Beleg: „ich bin das gefahren". Geometrie in WGS84.
create table public.trail_recordings (
  id uuid primary key default gen_random_uuid(),
  trail_id uuid not null references public.trails(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  geom geography(LineString, 4326) not null,
  recorded_at timestamptz,             -- null bei Import ohne Zeiten
  -- 'planned': importierte Datei ohne Zeiten oder mit unplausiblen
  -- Geschwindigkeiten — eine geplante Route, keine Fahrt. Zählt als
  -- Beitrag (Entscheidung 2), mit Qualität nahe null.
  source text not null check (source in ('app', 'import', 'planned')),
  reversed boolean not null default false,  -- gegen die Trail-Richtung gefahren
  quality real not null,               -- 0..1, siehe 4.5
  created_at timestamptz not null default now(),
  client_id uuid,                      -- Ausgangskorb, Idempotenz wie PilzBuddy Patch 016
  ele real[]                           -- Höhe je Punkt oder null (Patch 002, #14)
);
create index trail_recordings_geom_gix on public.trail_recordings using gist (geom);
create index trail_recordings_trail_idx on public.trail_recordings (trail_id);
create index trail_recordings_user_idx on public.trail_recordings (user_id);

-- Was ein Nutzer über einen Trail sagt. Genau eine Zeile je Nutzer und
-- Trail. Entsteht mit der ersten Aufzeichnung.
create table public.trail_details (
  trail_id uuid not null references public.trails(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text,
  description text,
  grade smallint check (grade between 0 and 5),   -- Singletrail-Skala S0–S5
  -- Charakter (#72, Patch 009): Mehrfachwahl statt der früheren Einzelwahl
  -- „Art“ (kind, bleibt für Clients bis 0.33.0 und wird später entfernt).
  traits text[] not null default '{}'
    check (traits <@ array['flowy', 'jumps', 'rocky', 'steep', 'uphill', 'natural', 'connection']),
  rating smallint check (rating between 1 and 5),  -- Bewertung, Patch 013
  visibility text not null default 'buddies' check (visibility in ('buddies', 'private')),
  -- status/status_at: veraltet seit Patch 013, nur noch für alte Clients
  status text not null default 'open' check (status in ('open', 'closed', 'destroyed', 'changed')),
  status_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (trail_id, user_id)
);

-- Meldung und Zustand als Verlauf (Patch 013, #101): schreiben nur über
-- report_trail(), das `confirmed` festlegt (gefahren oder vor Ort).
create table public.trail_reports (
  id uuid primary key default gen_random_uuid(),
  trail_id uuid not null references public.trails(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('status', 'condition')),
  status text,            -- bei 'status': open, closed, destroyed, changed
  condition smallint,     -- bei 'condition': 1–5
  confirmed boolean not null,
  reported_at timestamptz not null,
  created_at timestamptz not null default now(),
  client_id uuid          -- Ausgangskorb, Idempotenz
);

-- Unsichtbare Nachbarschaft für später (Abschnitt 4.4): „Trail A
-- überlappt Trail B zu 45 %". Kein Client liest diese Tabelle.
create table app_internal.trail_overlaps (
  a uuid references public.trails(id) on delete cascade,
  b uuid references public.trails(id) on delete cascade,
  coverage_ab real, coverage_ba real,
  primary key (a, b)
);
```

**Die Sichtbarkeitsregel**, formal:

> Nutzer U sieht Trail T, wenn es eine Aufzeichnung zu T von U gibt,
> oder eine Aufzeichnung zu T von einem Buddy B, dessen Beitrag zu T die
> Sichtbarkeit `buddies` hat.

Als RLS auf `trail_recordings` und `trail_details` (Muster
`are_friends` aus PilzBuddy, Patch 006/011):

```sql
create policy recordings_select on public.trail_recordings for select
  using (user_id = auth.uid()
     or (app_internal.are_friends(user_id, auth.uid())
         and app_internal.contributor_shares(user_id, trail_id)));
```

Die Tabelle `trails` selbst braucht keine eigene Sicht: Der Client
fragt nie „welche Trails gibt es", sondern „welche Aufzeichnungen und
Beiträge sehe ich" und gruppiert nach `trail_id`. **Alles, was auf der
Karte steht, ist aus sichtbaren Beiträgen gerechnet:**

- **Linie** = die Aufzeichnung mit der höchsten Qualität unter den
  sichtbaren. Wer allein ist, sieht seine eigene; wer Buddys hat, sieht
  vielleicht deren bessere. Kein Mittelwert (siehe 4.5).
- **Länge** = aus dieser Linie. **Höhenmeter, mittleres Gefälle,
  steilstes Stück und Profil** = aus den Höhen der besten sichtbaren
  Aufzeichnung, die welche HAT (eine je Punkt, Patch 002) — nicht
  zwingend derselben wie die Linie, sonst blieben Trails mit einer alten
  Aufzeichnung ohne Höhen für immer ohne Zahlen. Immer in
  Trail-Richtung (4.3): Eine gegen die Richtung gefahrene Aufzeichnung
  wird umgedreht. Gezählt wird mit Hysterese (eine Höhenänderung erst ab
  einer Schwelle), gemessen an echten Aufzeichnungen
  (`tool/elevation_measure.py`, `docs/trail-abgleich-messung.md`).
  **Korrektur vom 2026-09-27:** Hier stand „plus dem Höhengitter"; das
  PilzBuddy-Gitter hat 90-m-Waben und 20-m-Stufen und ist für einen
  3-km-Trail mit Kehren zu grob. Es bleibt der spätere Rückfall für
  Dateien ohne Höhen. **Nachtragen (#16):** Wer die Originaldatei einer
  eigenen Aufzeichnung ohne Höhen noch einmal importiert, bekommt die
  Höhen an die BESTEHENDE Aufzeichnung (`attach_elevation`, nur wenn die
  Linie Punkt für Punkt dieselbe ist) — kein zweiter Beleg, kein neuer
  Abgleich, nicht im Tageslimit.
  **Geländemodell (#186, seit 0.79.0; Betreiber 2026-10-02: „gezeigt,
  nie gespeichert"):** Hat keine sichtbare Aufzeichnung Höhen, rechnet
  das Blatt das Profil aus den Höhenkacheln (Copernicus GLO-90, Bereiche
  zuerst, mit Empfang der Host), alle 50 m mit 10 m Hysterese wie in
  der Messung M3 (~5 % Medianfehler im Abstieg), beschriftet „Höhen aus
  dem Geländemodell (90 m)", ohne steilstes Stück. Der GPX-Export trägt
  diese Höhen, markiert in `<extensions>`; der Import liest markierte
  Höhen nie (kein Nachtragen, kein Beisteuern). Und der Import
  vergleicht die Höhen einer Datei mit dem Modell: Versatz (Median)
  über 50 m oder Streuung (95. Perzentil) über 80 m ⇒ er bietet das
  Verwerfen an, vorgewählt; die Spur geht dann ohne Höhen hinauf.
  Beide Schwellen sind gesetzt, nicht gemessen — der Feldtest (#188)
  prüft sie mit.
- **Name** = eigener Name, sonst der Name des ältesten sichtbaren
  Beitrags; die anderen als „auch: …" (Muster Buddy-Alias in PilzBuddy).
- **Schwierigkeit** = Median der sichtbaren S-Grade (Singletrail-Skala,
  von den Buddys eingeschätzt; bei gerader Anzahl der schwerere), mit
  Spanne.
- **Meldung** (bis 0.48.0 „Status"; Rework E7) = offen, gesperrt,
  zerstört, verändert. **Seit 0.49.0 (#101, Patch 013) kein Teil des
  Beitrags mehr**, sondern ein Verlauf (`trail_reports`): Melden darf
  jeder, der den Trail SIEHT (Regel der Hinweise, `can_see_trail`) —
  Abweichung von „ohne Beleg kein Beitrag", entschieden am 2026-09-30.
  Angezeigt wird die **jüngste bestätigte** Meldung mit ihrem Alter
  („gesperrt, gemeldet vor 14 Monaten"), dazu verblasst die **jüngste
  unbestätigte, wenn sie jünger ist** („zu bestätigen"); eine ältere
  unbestätigte ist überholt. Karte, Liste und Filter „Gemeldet" folgen
  nur der bestätigten. Kein automatisches Verfallen.
  **Bestätigt** ist eine Meldung, wenn der Meldende den Trail zu diesem
  Zeitpunkt gefahren hat (eine Aufzeichnung, die nicht `planned` ist)
  oder vor Ort war: ≤ 200 m zur Linie, geprüft auf dem Gerät nach einem
  Tipp auf „Ich bin vor Ort". Zum Server geht nur das Ja/Nein, und
  gespeichert wird dort nur das Ergebnis `confirmed` (der Server rechnet
  es in `report_trail`, Security Definer — ein Client kann sich nicht
  selbst bestätigen). Push nur für bestätigte Meldungen.
  **Eine Fahrt setzt die eigene Meldung auf „offen"** — wer den Trail
  fährt, hat ihn befahrbar vorgefunden —, und zwar **zum Fahrdatum**
  (`recorded_at`, seit 0.49.0): Eine GPX-Datei von 2024 verdrängt keine
  Meldung von gestern. Nur, wenn der Fahrende schon etwas gemeldet hat;
  bei Widerspruch zwischen Buddys gewinnt die jüngste bestätigte, ohne
  Abstimmung. **Ausnahme seit 0.46.1 (#100, Patch 011):** eine geplante
  Aufzeichnung (`planned`, Datei ohne Fahrzeiten) — sie belegt nicht,
  dass jemand den Trail befahrbar vorgefunden hat.
  **Seit 0.58.0 (#120, Patch 015)** kann man für eine solche Datei beim
  Import „Gefahren am …" eintragen: Sie bleibt `planned` (die Linie ist
  gezeichnet, Qualität 0,1), trägt das Datum aber in `recorded_at` und
  zählt damit als gefahren — für „bestätigt" (`has_ridden`) und für das
  Zurücksetzen zum Fahrdatum.
  **Noch gültig?** (#119, seit 0.58.0): Meldungen werden nicht still
  weggeräumt. Wer gemeldet hat, sieht im Profil (und über den Filter
  „Noch gültig?") seine warnenden Meldungen und Zustände, die älter als
  30 Tage sind und noch angezeigt werden: Ja meldet denselben Wert
  erneut, Nein meldet „offen" bzw. fragt den neuen Zustand, Weiß nicht
  lässt alles und fragt nach 14 Tagen wieder — gemerkt nur auf dem
  Gerät.
  **Bestätigen durch Fahren** (#116, seit 0.52.0): Wer aufzeichnet und
  auf einem Trail mit unbestätigter Meldung oder unbestätigtem Zustand
  fährt, wird per lokaler Benachrichtigung gefragt (geprüft auf dem
  Gerät, auf der Linie, nicht nur in der Nähe). Die Antwort ist eine
  eigene, bestätigte Meldung des Fahrers („vor Ort") — kein eigenes
  Merkmal, sichtbar nur in seinem Netz. Eine Fahrt ohne Antwort
  bestätigt keine fremde Meldung.
  Übergangene Fragen stehen nach der Fahrt im Zerlege-Blatt an der
  Zeile des Trails (seit 0.53.0) — nur für das, was vor der Fahrt
  gemeldet war.
  **Aufbewahrt 90 Tage** (`sweep_old_reports`), damit man nachsehen
  kann, wer was gemeldet hat (Name bzw. Alias im Blatt); die jüngste
  bestätigte und die jüngste unbestätigte je Person, Trail und Art
  bleiben länger — die angezeigte muss auch nach einem Jahr noch da
  sein. Alte Clients (bis 0.48.0) lesen und schreiben weiter
  `trail_details.status`; Trigger gleichen in beide Richtungen ab
  (erweitern → ausliefern → entfernen).
- **Zustand** (#101, Patch 013) = 1–5, von „kaum fahrbar" bis „top
  gepflegt" (`trail_condition.dart`), im selben Verlauf wie die Meldung
  und nach derselben Regel bestätigt und angezeigt: die jüngste
  bestätigte Angabe, **dauerhaft** mit ihrem Alter (Betreiber,
  2026-09-30), dazu verblasst eine jüngere unbestätigte. Beschreibt
  den Zustand, nie eine Maßnahme (Konzept 7). Keine Push.
- **Bewertung** (#101, Patch 013) = 1–5 Sterne je Beitrag
  (`trail_details.rating`), also nur mit eigenem Beleg; angezeigt der
  Median der sichtbaren Beiträge (bei Gleichstand der höhere) mit
  Anzahl, auf dem Gerät gerechnet. Ein eigener Trail ohne eigene
  Bewertung zeigt verblasste Sterne.
- **Link zur Quelle** (#103, Patch 012, seit 0.48.0) = eigener Link,
  sonst der des ältesten sichtbaren Beitrags, der einen hat — wie der
  Name, nur ohne „auch: …". Nur https, ohne Query und Fragment (Check in
  der Datenbank; Freigabelinks tragen dort Tokens). Der Import schlägt
  ihn aus dem `<link>` der GPX-Datei vor (Spur vor `<metadata>`), außer
  von Geräteherstellern und Tourenportalen (`kLinkIgnoredHosts`: der
  eigene Aktivitätslink verriete Buddys das eigene Konto dort), und
  übernimmt ihn wie den Namen nur in einen Beitrag ohne Link. Die App
  ruft ihn nie selbst ab.
- **Hinweise** (#7, entschieden am 2026-09-28) = freier Text zum
  Trail, der das Warum trägt, das der Status nicht sagen kann („Baum
  liegt quer nach der zweiten Kehre"). Eine eigene Liste, neueste
  zuerst, mit Alter, kein Bearbeiten. **Schreiben darf jeder, der den
  Trail sieht** — anders als Name, Grad und Status braucht ein Hinweis
  keinen eigenen Beleg: Wer vor dem Baum steht, muss den Trail nicht
  aufgezeichnet haben. Sehen der Autor und seine direkten Buddys, die
  den Trail auch sehen; nicht bei „privat", keine Transitivität.
  **Entfernen darf jeder, der ihn sieht** — „erledigt" sagt, wer am
  Trail war. Nach 90 Tagen räumt der Server auf; der jüngste Hinweis
  eines Autors zu einem Trail bleibt, bis ihn jemand entfernt (je Autor,
  weil „der jüngste über alle Netze" eine Rechnung über Netzgrenzen
  wäre). Beim Melden wird einer angeboten. Die App hebt
  Trails mit einem neuen, noch nicht gelesenen Hinweis eines Buddys aus
  den letzten sieben Tagen in Karte und Liste hervor; was gelesen ist,
  weiß nur das Gerät. **Seit 0.23.0 (#34) dazu eine Push-Meldung** für
  bestätigte Meldungen und neue Hinweise — an die direkten Buddys des Autors,
  die den Trail und seinen Beitrag sehen (dieselben Regeln wie die
  Sichtbarkeit, je Buddy-Beziehung eine Zeile, keine Rechnung über alle;
  Abschnitt 12). **Seit 0.54.0 (Patch 014) mit Inhalt** (Betreiber,
  2026-09-30: „anonym genug"): Trailname und Name des Buddys so, wie der
  Empfänger sie sieht (sein Name für den Trail, sein Alias für den
  Buddy), das Statuswort, beim Hinweis der Text (140 Zeichen); nie eine
  Koordinate, nie der Zustand. Ziel bleibt die opake Trail-Kennung.

Eine zentrale Sicht (`trails_visible`) rechnet das serverseitig, damit
Karte, Liste und Blatt dieselbe Antwort geben — dieselbe Regel wie in
PilzBuddy „Fläche, Legende und Blatt müssen dasselbe sagen".

**Löschen und DSGVO.** Ein Nutzer löscht seine Aufzeichnungen und
seinen Beitrag; der Trail bleibt, solange ein anderer Beitrag existiert,
und verschwindet mit dem letzten (Aufräumjob, kein Cascade vom Beitrag
zur Kennung). Gebaut seit 0.46.0: „Löschen" im Trail-Blatt ruft
`withdraw_contribution` (Patch 010), das eigene Aufzeichnungen, eigene
Hinweise und den eigenen Beitrag in EINER Transaktion löscht — einzeln
nacheinander stünde „privat" kurz nicht mehr da, und die eigenen Zeilen
wären für Buddys sichtbar. Kontolöschung kaskadiert wie in PilzBuddy. Eine
Aufzeichnung ist ein Bewegungsprofil-Ausschnitt und damit
personenbezogen; sie steht in der Datenschutzerklärung als eigene
Kategorie. Fahrten sind gar nicht erst auf dem Server.

## 4. Duplikate: der Abgleich

### 4.1 Eingang

Der Abgleich bekommt eine **Kandidatenlinie** (Abschnitt 5 sagt, wie
sie entsteht): eine Polyline mit 20 bis einigen tausend Punkten, mit
oder ohne Zeitstempel, mit oder ohne Genauigkeitsangabe je Punkt. Er
läuft in EINER Security-Definer-Funktion `contribute_recording(geom,
source, recorded_at, client_id)` auf dem Server: Der Client kann nicht
gegen fremde Trails vergleichen, weil er sie nicht sehen darf, und
genau deshalb muss es die Datenbank tun. Die Funktion legt die
Aufzeichnung an, hängt sie an einen bestehenden oder neuen Trail und
gibt **nur die Trail-Kennung** zurück. Ob sie neu ist, sagt sie nicht.

### 4.2 Drei Stufen

1. **Vorfilter, billig:** PostGIS `ST_DWithin` auf der Hülle — alle
   Trails, deren beste Aufzeichnung dem Kandidaten irgendwo näher als
   der Korridor kommt. GiST-Index, Millisekunden.
2. **Deckungsgrad, beide Richtungen:** Beide Linien werden auf 5 m
   abgetastet. `cov(A→B)` = Anteil der Punkte von A, die näher als der
   Korridor `d` an B liegen; ebenso `cov(B→A)`. Das ist mit
   `ST_Buffer`/`ST_Intersection` direkt in SQL zu haben.
3. **Reihenfolge, gegen Serpentinen:** Ein Trail mit Kehren hat
   parallele Schenkel im Abstand von 10 bis 20 m — ein Korridortest
   allein hält den benachbarten Schenkel eines ANDEREN Trails für
   Deckung. Deshalb für die Kandidaten aus Stufe 2 zusätzlich die
   diskrete Fréchet-Distanz auf den abgetasteten Punkten, **die im
   Korridor liegen** — beide Seiten vorher beschnitten. Sie verlangt,
   dass die Punkte in derselben REIHENFOLGE nah beieinander liegen. Das
   Maximum über ALLE Punkte wäre falsch: Ein einzelner GPS-Sporn oder
   ein grob gezeichneter Bogen sagt nichts über die Reihenfolge, treibt
   das Maximum aber auf 40–90 m (gemessen an namensgleichen Trails).
   Als SQL unpraktisch — das ist PL/pgSQL oder eine Edge Function; bei
   ≤ 1200 Punkten je Linie ist O(n·m) kein Problem.

**Schwellen, gemessen am 2026-09-27** (`docs/trail-abgleich-messung.md`,
584 Tracks des Betreibers):

| Größe | Wert | Grund |
|---|---|---|
| Korridor `d` | 15 m | GPS unter Blätterdach liegt 10–20 m daneben; 10 und 15 m liefern dieselben Gleich-Paare, ab 20 m kommen Gabeln als „gleich" dazu. |
| Deckung „gleich" | ≥ 0,8 beidseitig | Die Verteilung hat eine Lücke: 26 Paare unter 0,7, 7 über 0,9, 4 dazwischen — und die sind Trail und Variante. |
| Fréchet „gleich" | ≤ 2·d, **auf den Punkten im Korridor** | Alle Gleichen ≤ 19,4 m, der nächste Wert 84 m. Ohne den Zuschnitt treibt ein einzelner Sporn das Maximum auf 40–90 m bei namensgleichen Trails. |
| Mindestlänge Trail | 50 m | Darunter ist es eine Zufahrt oder ein Fragment. Gemessen war 150 m (12 von 584 Dateien darunter); kurze echte Stücke — Jump-Line, Steilpassage zwischen zwei Forstwegen — fielen damit weg, deshalb 50 m seit Patch 017 (Betreiber, 2026-10-04). Das kürzeste Fragment im Bestand (13 m) bleibt darunter. |
| Abtastung | 5 m | Kehren mit 10 m Radius bleiben sichtbar; Locus-Exporte sind auf 13 m gedünnt, gezeichnete Routen haben 100-m-Schenkel. |

### 4.3 Richtung

Ein Trail hat eine Richtung — die des ersten Beitrags. Wird dieselbe
Linie in Gegenrichtung gefahren (Deckung ≥ 0,8, Fréchet auf der
umgedrehten Linie), ist es **derselbe Trail** mit `reversed = true` an
der Aufzeichnung. Ein Trail, der in beiden Richtungen belegt ist, gilt
als beidseitig befahrbar; das ist für das spätere Routing die
entscheidende Information (Abschnitt 9). Zwei Trail-Kennungen für zwei
Richtungen wären zwei Namen für einen Weg.

### 4.4 Die vier Fälle — und was v1 davon macht

Kandidat K gegen bestehenden Trail T:

| Fall | Deckung | Bedeutet | v1 |
|---|---|---|---|
| gleich | K→T ≥ 0,8 und T→K ≥ 0,8 | derselbe Trail | **anhängen** |
| K liegt in T | K→T ≥ 0,8, T→K < 0,8 | jemand ist nur einen Teil gefahren | anhängen als Teilbeleg, wenn K→T ≥ 0,9 und K ≥ 50 % von T; sonst neuer Trail + Overlap-Link |
| T liegt in K | T→K ≥ 0,8, K→T < 0,8 | Kandidat enthält T und mehr | **neuer Trail + Overlap-Link** |
| Gabel | beide zwischen 0,3 und 0,8 | gemeinsames Stück, dann Abzweig | **neuer Trail + Overlap-Link** |

Die Entscheidung für v1 ist bewusst konservativ: **Nur „gleich" wird
verschmolzen, alles andere wird ein neuer Trail mit einer unsichtbaren
Nachbarschaftskante** (`app_internal.trail_overlaps`). Zwei Gründe:

- **Zerschneiden nach fremden Grenzen wäre ein Leak.** Enthält meine
  40-km-Fahrt einen Trail, den nur andere kennen, und der Server
  schnitte den Kandidaten an dessen Anfang und Ende auf, dann wüsste
  ich danach, WO ein fremder Trail beginnt und endet. Deshalb gilt:
  **Schnittvorschläge kommen nur aus eigenen Daten und aus dem
  sichtbaren Netz, nie aus fremden Trails.**
- **Eine falsche Verschmelzung ist teurer als eine Dublette.** Zwei
  Trails, die eigentlich einer sind, kann man später zusammenführen
  (Werkzeug wie „Spots zusammenführen" in PilzBuddy, nur innerhalb des
  eigenen Netzes, wo beide sichtbar sind). Einen falsch verschmolzenen
  Trail wieder zu trennen, ist eine Handarbeit mit Datenverlust.

Die Overlap-Kanten sind der Vorrat für später: Wenn zwei Nutzer sich
verbinden und die App zwei sichtbare Trails mit einer Kante findet,
kann sie „Sind das dieselben?" fragen — dann kennen beide Seiten beide
Linien, und der Vorschlag verrät nichts.

### 4.5 Kanonische Linie und Qualität

Es gibt keine gemittelte Linie. Jede Aufzeichnung bekommt eine
**Qualität** 0..1 aus: Anteil der Punkte mit Genauigkeit ≤ 15 m, keine
Lücke > 10 s bzw. > 50 m, Punktdichte, Quelle (`app` vor `import` ohne
Zeiten). Die Linie, die ein Nutzer sieht, ist die beste unter den ihm
SICHTBAREN Aufzeichnungen. Ein Mittelwert über mehrere Linien ist
eine spätere Verbesserung, wenn es Messungen gibt, dass er etwas
bringt — und er müsste dann ebenfalls nur über sichtbare Beiträge
gerechnet werden.

### 4.6 Warum das leak-frei ist — und was trotzdem verborgen bleibt

Das Argument in einem Satz: **Der Abgleich beantwortet nur die Frage
„ist meine Linie ein bekannter Trail" mit einer Kennung, und diese
Kennung sagt mir nichts, solange kein Buddy Beiträge dazu hat.**

Prüfung der Angriffe:

- **Sondieren:** Ein Fremder lädt Linien entlang aller Forstwege eines
  Reviers hoch. Er bekommt je Linie eine Kennung — für neue wie für
  bekannte Trails dieselbe Sorte Antwort. Er sieht keine Zähler
  („3 Buddys kennen das"), keine fremden Namen, keine fremde Linie,
  kein Erstellungsdatum. Was er sehen könnte, hat er selbst geliefert.
  Um einen Trail zu „treffen", müsste er zu 80 % innerhalb 15 m auf
  ihm fahren — dann kennt er ihn.
- **Rate:** 500 Aufzeichnungen je Nutzer in 24 Stunden (Patch 006, #23)
  — genug für einen ganzen Bestand am Stück (gemessen: 454 Trails), und
  eine Grenze für die Last, die ein Konto erzeugen kann. **Korrektur
  vom 2026-09-28:** Hier standen 50 mit der Begründung „auch für einen
  Bestandsimport an einem Abend"; der gemessene Bestand hätte damit zehn
  Tage gebraucht. Gegen das Sondieren hilft die Zahl ohnehin wenig — was
  es verbirgt, verbirgt der Abgleich selbst (oben); sie schützt die
  Datenbank (Kosten: `docs/trail-abgleich-messung.md`, „Tageslimit").
- **Synthetische GPX:** Ein Import ohne Zeitstempel oder mit
  unplausiblen Geschwindigkeiten wird als „geplant" gespeichert
  (`source = 'planned'`), bekommt Qualität nahe null und steht in der
  Anzeige so da; ein Import mit Zeiten als „importiert". Beides gilt
  als Beitrag — der Nutzer hat die Linie, mehr beweist auch eine
  App-Aufzeichnung nicht. Die Linie eines Buddys mit echter
  Aufzeichnung gewinnt in der Anzeige immer. Das Blatt nennt seit
  0.46.1 (#100), wer einen Trail nur geplant hat, und sagt es für den
  ganzen Trail, wenn jeder sichtbare Beleg geplant ist; einen Status
  setzt ein geplanter Import nicht zurück (3) — außer mit
  eingetragenem Fahrdatum (seit 0.58.0, #120).

Was DESHALB nie an den Client geht: Zähler über alle Beiträge, das
Alter der Kennung, die Overlap-Tabelle, irgendeine Aggregation über
Nutzer außerhalb des Netzes. Ein Wächter-Test wie `schema_check.sh` in
PilzBuddy prüft, dass `trails` und `app_internal.*` für `anon` und
`authenticated` gar keine Grants tragen.

### 4.7 Offline

Der Abgleich braucht den Server. Ohne Empfang landet die Aufzeichnung
im Ausgangskorb (PilzBuddy-Baustein) und der Trail steht als
„wartend" auf der Karte, mit der eigenen Linie. Beim Nachholen bekommt
er seine Kennung; die eigene Sicht ändert sich dabei nur, wenn ein
Buddy eine bessere Linie hat.

## 5. Wie Trails entstehen

Drei Wege, davon zwei in v1.

### 5.1 In der App aufzeichnen

Der Aufzeichnungs-Baustein aus PilzBuddy (Pilztour: Foreground-Service
vom Typ `location`, Messung im Service-Isolate, JSON Lines auf der
Platte, prozesssicher) wird zur **Fahrt**. Am Ende zeigt ein Blatt die
Fahrt auf der Karte, zerlegt in Abschnitte:

- **Bekannte Trails** aus dem sichtbaren Netz (Abgleich lokal gegen den
  Zwischenspeicher, dieselben Schwellen) — vorangehakt, „wieder
  gefahren" wird als Aufzeichnung beigesteuert (das aktualisiert
  Qualität und Status).
- **Kandidaten** für neue Trails, vorgeschlagen aus eigenen Daten:
  Abschnitte mit anhaltendem Gefälle (Höhengitter, offline) UND abseits
  von Forst- und Fahrstraßen. Letzteres ist aus den Offline-Kacheln zu
  haben — die PMTiles-Straßenebene kennt `track`, `service`, `road`;
  ein Abschnitt, der zu > 70 % mehr als 15 m von all dem entfernt
  liegt, ist Singletrail oder Wiese. Heuristik, kein Urteil: Der Nutzer
  schneidet mit zwei Griffen zu, benennt, wählt S-Grad und Charakter
  (seit 0.35.0), oder verwirft.
- **Rest** (Anfahrt, Forstweg, Straße) wird nicht angeboten.

Die Fahrt bleibt danach als Ganzes auf dem Gerät (Statistik, eigene
Historie), gelöscht wird nichts ohne Nachfrage. **Heimzone:** Kandidaten,
die innerhalb 300 m vom Start- oder Endpunkt der Fahrt beginnen oder
enden, werden markiert („beginnt nahe deinem Start") — kein Riegel, ein
Hinweis, weil ein Trail durchaus an der Haustür beginnen kann.

**Gebaut in 0.20.0 (#29), mit drei Abweichungen vom Text oben:**
(1) Das Gefälle kommt nicht aus einem Höhengitter — das hat TrailBuddy
nicht —, sondern aus der GPS-Höhe der Aufzeichnung (geglättet), bei
GPX-Fahrten aus der Datei; beigesteuert wird die GPS-Höhe nicht (#28).
(2) „Abseits von Forst- und Fahrstraßen" liest die App ausschließlich
aus gespeicherten Bereichen (Zoom 13); ohne Bereich über der ganzen
Fahrt gibt es keine Kandidaten, und das Blatt sagt es — keine
Gefälle-allein-Regel (Betreiber, 2026-09-28). (3) Der lokale Abgleich
für „bekannt" rechnet die beidseitige Deckung, keinen Fréchet: Ob
verschmolzen wird, entscheidet weiter allein der Server.

**Seit 0.47.0 (#104): „Stück selbst wählen".** Die Heuristik findet nur
Abfahrten; eine Jump-Line, ein flacher Flowtrail, ein Uphill oder ein
Trail mit Forstweg-Stück wurde kein Kandidat. Ein Knopf unter den
Kandidaten legt einen Kandidaten über die GANZE Fahrt an (dieselben
Griffe, Name, S-Grad, Charakter), ohne gespeicherten Bereich und ohne
Höhen. Vorgewählt ist die Fahrt ohne ihre ersten und letzten 300 m
(Heimzone): Eine Fahrt beginnt an der Haustür. Der Heimzonen-Hinweis
gilt seither für die aktuellen Griffe, nicht für das gefundene Stück.

**Seit 0.57.0 (#105): Marken während der Aufnahme.** Über dem
Aufnahmeknopf steht während einer Fahrt eine Fahne: erster Tipp „Trail
beginnt", zweiter „Trail endet" (der Knopf trägt dazwischen einen Rand).
Die Marke ist eine Zeile mit Zeit in der Fahrt-Datei und verlässt das
Gerät nie. Jedes Paar wird im Zerlege-Blatt ein vorangehakter Kandidat
— ohne gespeicherten Bereich und ohne Höhen, denn der Fahrer stand dort.
Er schlägt die Heuristik, wo beide sich überschneiden, und weicht nur
einem bekannten Trail, der ihn deckt; eine offene Marke gilt bis zum
Ende der Fahrt.

**Seit 0.55.0 (#102): Übernehmen beim ersten Befahren.** Wer einen
bekannten Trail fährt, zu dem er noch KEINEN eigenen Beitrag hat, macht
ihn sich im Zerlege-Blatt zu eigen: Name, S-Grad, Charakter und Sterne
vorbelegt mit dem, was sein Netz zeigt („Vorschlag aus dem Netz"), der
Zustand mit dem jüngsten bestätigten der letzten 90 Tage. Ohne
Bestätigung — und ohne Sterne — wird das Stück nicht beigesteuert
(Rework E1/E2). Danach ist es ein vollständiger eigener Beitrag: Er
hängt nicht mehr am Beitrag eines Buddys, der gelöscht oder entfreundet
werden kann. Für den Bestand (seit 0.56.0) ohne Rückfüllen auf dem
Server: „Übernehmen" im Trail-Blatt, dieselbe Zeile im Import-Ergebnis
und der Filter „Bewertung offen".

### 5.2 GPX-Import (der Bestand)

Der Grund, warum das Konzept vor dem Code stehen muss: Die ersten
Nutzer bringen Sammlungen mit. Der Import nimmt eine oder viele
Dateien und entscheidet je Datei:

- **Kurz und überwiegend bergab** (< 8 km, Höhenverlust > 2× Gewinn,
  aus dem Höhengitter oder den Höhen in der Datei) ⇒ ist ein Trail, wird
  direkt Kandidat; Name aus `<name>` der Datei vorgeschlagen. Die 8 km
  sind gemessen: Alpine Trails sind 3 bis 8 km lang, Fahrten beginnen
  im Bestand bei 8 km; die wenigen langen Abfahrten darüber gehen als
  Fahrt durchs Zerlege-Blatt, der harmlose Fehler.
- **Sonst** ⇒ ist eine Fahrt, geht durch dasselbe Blatt wie 5.1 (seit
  0.20.0: die Schere neben der Spur im Import führt auf die Karte).

Dann für jeden bestätigten Kandidaten `contribute_recording`. Zwanzig
Dateien sind zwanzig Aufrufe; das Ergebnis ist eine Karte, auf der
Trails, die Buddys schon haben, verschmolzen sind, und alle anderen als
eigene stehen. **Einen Import „konfliktfrei" zu machen, ist damit keine
Oberfläche, sondern eine Eigenschaft des Modells.**

### 5.3 Von Hand zeichnen — nicht in v1

Ein Trail ohne Aufzeichnung ist eine Behauptung ohne Beleg und würde
das „nur Gefahrenes wird weitergegeben" unterlaufen. Später denkbar
für Korrekturen an einer bestehenden Linie, nicht zum Anlegen.

## 6. Freundschaft: was beim Verbinden passiert

Nichts, was gelöst werden müsste. Nach dem Annehmen:

- Trails, die beide belegt haben, sind EIN Trail auf beiden Karten, mit
  beiden Namen („Hexentanz · auch: Roots").
- Trails, die nur einer belegt hat, erscheinen beim anderen neu.
- Eine Zusammenfassung nach dem Annehmen — nicht davor —: „14 Trails
  gemeinsam, 8 neu von Jan, 5 neu für Jan". Vor dem Annehmen wäre die
  Zahl ein Orakel über den Bestand eines Fremden. (Seit 0.22.0, #33
  Teil 1: gerechnet auf dem Gerät aus dem sichtbaren Stand vor und nach
  dem Neuladen; „neu für Jan" sind eigene, nicht private Trails ohne
  seinen Beleg — was er über andere Buddys schon sah, ist von hier aus
  nicht zu wissen.)
- Overlap-Kanten zwischen zwei jetzt sichtbaren Trails werden als
  Vorschlag gezeigt: „Sind das dieselben? Beide Linien ansehen".

Beim **Entfreunden** verschwinden die Trails, die nur über diesen
Buddy sichtbar waren; eigene Beiträge bleiben, auch die zu Trails, die
der Buddy zuerst hatte. Symmetrisch zu PilzBuddy: jeder behält, was er
selbst eingetragen hat.

**Keine Transitivität.** Buddys von Buddys sehen nichts. Ein Trail
wandert nur weiter, wenn jemand ihn FÄHRT und damit einen eigenen
Beitrag hat. Das ist die eine Regel, die das Tor trägt: Ein Netz von
1 000 Leuten mit Weitergabe von Gesehenem wäre eine öffentliche Karte
mit Anmeldung.

Ein Beitrag mit Sichtbarkeit `private` ist nur für den Nutzer selbst —
für Trails, die man kennt und niemandem zeigen will. Wer einen privaten
Trail fährt und selbst beiträgt, sieht ihn natürlich; der private
Beitrag des anderen bleibt dabei unsichtbar.

## 7. Das Tor: was die Community leistet — und was nicht

Regeln, die aus dem Modell folgen und alle mit RLS erzwungen sind:

- **Keine öffentliche Karte, keine Suche nach Trails, kein
  Verzeichnis.** Ohne Buddys ist die Karte leer bis auf das Eigene.
- **Buddy-Suche nur über exakten Nutzernamen oder E-Mail**, ohne Liste
  (PilzBuddy-Muster, kein Orakel).
- **Nur Gefahrenes wird weitergegeben, nichts transitiv.**
- **Aggregationen über das Netz hinaus gibt es nicht.** Keine „beliebte
  Trails in deiner Nähe", keine Heatmap, keine Zähler.
- **Einladung** als Bequemlichkeit (Link, der eine Buddy-Anfrage
  vorausfüllt), nicht als Pflicht: Eine Pflicht-Einladung hält niemanden
  ab, der jemanden kennt, und sperrt alle aus, die niemanden kennen —
  und die haben ohnehin eine leere Karte.

Was das Tor **nicht** ist, muss ebenso klar sein, sonst baut man ein
Versprechen, das nicht hält:

- Es hält **Neugier** ab, nicht **Absicht**. Wer einen Trail finden
  will, kann sich ein Rad leihen und ihn fahren — dann hat er ihn, mit
  Recht. Das Modell macht das Finden nicht leichter als ohne App, und
  das ist der ehrliche Anspruch: **Die App darf niemandem einen Trail
  zeigen, den er nicht ohnehin schon kennt oder von einem Freund gezeigt
  bekommt.** Mehr Schutz als eine WhatsApp-Gruppe kann sie nicht
  bieten, weniger darf sie nicht bieten.
- Es ist **kein Rechtsschutz** für den Betreiber. Wenn die Plattform
  dazu einlädt, Wege zu zeigen, die nach Landesrecht nicht befahren
  werden dürfen, kann das den Betreiber treffen (Stichwort
  Störerhaftung), und die Datenschutzerklärung muss die Aufzeichnungen
  als Bewegungsdaten benennen. Das ist keine Rechtsberatung; die
  Empfehlung ist eine juristische Prüfung der Nutzungsbedingungen VOR
  dem ersten Nutzer, der nicht der Betreiber selbst ist.

Daraus folgen Dinge, die die Plattform **bewusst nicht tut**:

- **Keine Bau-Features.** Kein „Trail im Bau", kein Bautagebuch, keine
  Aufrufe zu Arbeitseinsätzen. Das Anlegen von Trails ist in allen
  DACH-Ländern der Punkt, an dem aus einer Grauzone eine Straftat wird
  — das Befahren vorhandener Wege ist es meist nicht (die Regeln
  unterscheiden sich je Bundesland: „geeignete Wege" in Bayern,
  2-Meter-Regel in Baden-Württemberg, „feste Wege" in NRW).
- **Schutzgebiete werden gesagt, nicht gesperrt.** Das
  Schutzgebiets-Gitter aus PilzBuddy (Naturschutzgebiete, Nationalparks,
  Kernzonen; 250-m-Waben; DACH) läuft hier mit: Ein Kandidat, der ein
  Schutzgebiet quert, bekommt beim Anlegen einen Satz („liegt
  wahrscheinlich in einem Naturschutzgebiet — dort ist Radfahren abseits
  der Wege meist verboten"). Kein Riegel, keine Rückfrage, dieselbe
  Linie wie in PilzBuddy: keine Bevormundung, aber auch kein Schweigen.
- **Kein Status „legal/illegal" am Trail.** Die App kann es nicht
  wissen, und ein solches Feld wäre entweder immer „unbekannt" oder ein
  Geständnis in einer Datenbank. Was es gibt: „gesperrt" als
  Statusmeldung eines Nutzers, damit Buddys nicht in eine Sperrung
  fahren.
- **Rankings bleiben im Netz.** Strava hat vorgeführt, was ein
  öffentliches Segment auf einem geduldeten Trail bewirkt: Es zieht
  Aufmerksamkeit an, auch die falsche. Ein Airtime-Ranking (Abschnitt 9)
  ist deshalb nur unter Buddys sichtbar, nie global.

## 8. Was von PilzBuddy übernommen wird

Das Projekt beginnt nicht bei null. Der Stack bleibt derselbe (Flutter
für Android und Web, Supabase, Riverpod ohne Codegen, go_router,
deutsche UI-Strings im Code, RLS als einzige Rechtequelle), und ein
großer Teil der Infrastruktur ist eins zu eins übertragbar:

| Baustein | Aus PilzBuddy | Für TrailBuddy |
|---|---|---|
| Auth, Profil, Passwort/E-Mail-Flows, Konto löschen | komplett | unverändert |
| Freundschaften, `are_friends`, Alias, Nachrichten, Push | komplett | unverändert; Alias wird zum Muster für Trail-Namen |
| RLS-Muster, Schema-Patches, Schema Check, Dry Run, Patch-Wächter | CI und `tool/` | unverändert, plus PostGIS im lokalen Stack |
| Version Guard, Release-Kanäle, Vorabversionen, Web-Vorschau, Service Worker | komplett | unverändert |
| Feedback-Bot, Fehlerberichte, Beendigungsgründe, Wochendigest | komplett | unverändert |
| Offline-Karten (PMTiles-Regionen, DACH-Übersicht, Foreground-Service für Downloads) | komplett | unverändert; die Wege-Ebene wird dazu für die Kandidaten-Heuristik gelesen |
| Tour-Aufzeichnung (Service-Isolate, JSON Lines, Brücke) | `lib/features/tour/` | wird zur Fahrt; Leergang-Logik entfällt |
| Ausgangskorb (Idempotenz per `client_id`) | `lib/data/outbox*.dart` | Aufträge: Aufzeichnung beitragen, Beitrag ändern |
| Höhengitter (Copernicus DEM, 20-m-Stufen, DACH, offline) | `elevation-data.yml` | Kandidaten-Heuristik, später Routing, Rückfall für Dateien ohne Höhen — für die Höhenmeter je Trail zu grob (siehe 3) |
| Höhenlinien auf der Karte | `elevation_contours.dart` | unverändert |
| Schutzgebiets-Gitter | `protected_areas.dart` | Hinweis beim Anlegen |
| Erklär-Tour, Neuheiten, Kurzanleitung | Hinweis-Maschine | Skripte neu, Maschine gleich |
| Kartenfassade (MapLibre Android, flutter_map Web), Linienzüge | `map_view/` | Trails als Linien; die Fassade kann das seit 1.126.0 |

Nicht übernommen: Ampel, Arten, GBIF, Regen, Wald, Fundfotos,
iNaturalist — alles, was Pilz ist.

**Zwei Warnungen dazu:**

- **Kopieren, nicht extrahieren.** Die Versuchung, ein gemeinsames
  `buddy_core`-Paket herauszuziehen, ist groß und in diesem Moment
  falsch: Erst wenn TrailBuddy steht, sieht man, was WIRKLICH gleich
  geblieben ist. Ein Paket, das vorher entsteht, bremst beide Apps bei
  jeder Änderung. Kopie, mit Vermerk der Quellversion (1.213.0), und in
  einem halben Jahr die Frage neu stellen.
- **`CLAUDE.md` nicht kopieren.** Die Datei in PilzBuddy ist die
  Geschichte dieses einen Projekts. TrailBuddy bekommt eine eigene, die
  klein anfängt und nur trägt, was hier entschieden wurde — und eine
  davon ist die Regel „nichts Privates ins Repo", die sofort gilt.

**Neu** gegenüber PilzBuddy: PostGIS und Geometrie-Abgleich in der
Datenbank; Trails als Vektordaten offline auf der Karte (der
Zwischenspeicher hält Linien statt Punkte — GeoJSON-Text, dasselbe
IndexedDB/Datei-Muster); GPX-Parser (für Import und Export; PilzBuddy
hat einen Export, kein Import von Tracks); die Zerlegung von Fahrten.

## 9. Später: Routing und Airtime — nur die Randbedingungen

Beides wird nicht jetzt gebaut. Festzuhalten ist, was das Datenmodell
dafür heute schon tragen muss, damit es später nicht umgebaut wird.

**Routenvorschläge nach Höhenmetern oder Zeit.** Ein Router braucht
einen Graphen: Kanten mit Länge, Höhenmetern, Richtung und Kosten.
Trails sind die Kanten, die es sonst nirgends gibt; das Verbindungsnetz
kommt aus OSM (die PMTiles-Regionen tragen die Wege, aber nicht als
Graph — ein Graph muss aus den Kacheln oder aus einem OSM-Auszug
gebaut werden). Das Modell trägt deshalb ab v1 die **Richtung** und die
**beidseitige Befahrbarkeit** je Trail (4.3). Was es NICHT trägt und
später kommt: Knoten an Trail-Anfang und -Ende, Anschluss an das
Wegenetz. Kandidaten für die Maschine: BRouter (offline-fähig auf
Android, eigene Profile, Java), ein eigener A* über einen regionalen
Graphen (klein, aber Arbeit), Valhalla auf einem Server (kostet, und im
Funkloch tot). Entscheidung nach einer Messung, nicht vorher. Der
Zeit-Eingang ist ohne Nutzerprofil grob (Aufstieg 400–600 hm/h, Abfahrt
nach Trail-Länge), wird mit eigenen Fahrten kalibrierbar — die liegen
ja auf dem Gerät.

**Anfahrt vor Routing** (2026-10-01, #151). Bis die Messung aus Phase 4
steht, übergibt die App den Trailkopf an eine Navi-App des Nutzers
(`geo:`-URI, Systemwähler, Koordinate zweimal im URI — PilzBuddy #367).
Das ist keine Routenplanung und behauptet keine; es beantwortet die
Frage, die im Alltag zuerst kommt, und braucht kein Netzziel. Der
Rückfall ist die Zwischenablage, nie ein fester Kartendienst.

**Der Planer ist Trail-zuerst, nicht A-nach-B** (Betreiber, 2026-10-01,
#158): „möglichst uphill Höhenmeter-effizient viele Trails
unterbringen" — eine Runde ab Startpunkt mit Höhenmeter- oder
Zeitbudget, die möglichst viele sichtbare Trails in ihrer Richtung
bergab mitnimmt. Aufstiege werden nach Wegklasse bewertet: Schotter und
Forstweg sind die Grundlinie, Wanderwege erlaubt mit Aufschlag, Straßen
stark belastet, nie ausgeschlossen. Bergab auf einem Trail ist der
Gewinn, bergab auf der Straße verschenkte Höhe. Das ist ein
Prize-Collecting-Problem, auf dem Telefon lösbar: kürzeste Aufstiege
zwischen allen Trail-Enden über den Wegegraphen, dann eine Verkettung
unter dem Budget. Keine Abbiegehinweise — die Runde geht als GPX
(#150) an die Navi-App. Drei Voraussetzungen, die das Modell heute nicht
hat: ein Höhengitter für die Wege (PilzBuddys `elevation_grid.py` als
Vorlage), der Graph aus den `roads`-Kacheln der gespeicherten Bereiche
(der Wege-Index des Zerlege-Blatts liest sie schon) und die Wegklasse je
Kante. Gerechnet wird nur auf dem Gerät über die eigenen sichtbaren
Trails (12); eine geplante Runde ist eine `planned`-Fahrt (5.2) und
wandert erst gefahren weiter (10.1). Das Werkzeug sagt, wo es über einen
Wanderweg plant, und nie, dass ein Weg befahren werden darf (7).
Seit 0.74.0 (Feldbericht, #174 #178 #185): Welche Trails in die Runde
sollen, wählt der Fahrer — Tipp auf der Karte, Liste im Radius oder ein
umfahrenes Gebiet; ab Werk ist nichts gewählt. Kein Trail wird gegen
seine Richtung gefahren, auch nicht als Aufstieg, außer ein Beitrag sagt
„in beide Richtungen fahrbar" (Patch 016). Uphill-Trails und Verbinder
sind der bevorzugte Weg bergauf, keine Abfahrten. Einzelheiten:
`docs/konzept-routing.md` 2.7 und 4.

**Die Engine ist eine eigene, kein BRouter** (Betreiber, 2026-10-01).
Anforderungsprofil (Bio-Bike/E-Bike, Zeitmodell, Budgets, Wegklassen
und Kosten), Algorithmus, Schrittfolge und der neu geschnittene
Messplan stehen in `docs/konzept-routing.md`; die Frage von #35 heißt
seither nicht mehr „welche Engine?", sondern „tragen unsere Kacheln
den Graphen?" (dort Abschnitt 6).

**Airtime und Ranking.** Sprünge lassen sich aus dem
Beschleunigungssensor lesen (Freifallphase: Betrag der Beschleunigung
nahe 0 für > 150 ms), Zuordnung zum Trail über die laufende Fahrt. Drei
Randbedingungen: Ranking nur unter Buddys (7); Manipulation ist
trivial (Telefon werfen) und deshalb ist es ein Spiel, kein
Leistungsnachweis — die Oberfläche sagt das; und es ist ein Anreiz zu
Risiko, das gehört in die Nutzungsbedingungen. Das Modell braucht dafür
eine Tabelle Ereignis-je-Fahrt-und-Trail, nichts davon in v1.

## 10. Entscheidungen des Betreibers (2026-09-27)

Alle acht sind entschieden; die verworfenen Alternativen stehen dabei,
damit die nächste Diskussion nicht bei null beginnt.

1. **Sichtbarkeit: nur Gefahrenes wandert weiter.** Ich sehe eigene
   Beiträge und die meiner direkten Buddys; weitergeben kann nur, wer
   selbst einen Beleg hat. Verworfen: „Weitergeben auf Tastendruck"
   (Kette unbegrenzt, der Erstbeitragende sieht nicht, wo sein Trail
   landet) und Transitivität (öffentliche Karte mit Anmeldung).
2. **Importierte Trails sind gleichwertig, mit Kennzeichnung.** Import
   mit Zeiten heißt „importiert", ohne Zeiten oder mit unplausiblen
   Geschwindigkeiten „geplant" (`source`, 3); beides mit niedrigerer
   Qualität als eine App-Aufzeichnung. Verworfen: Import nur für sich
   selbst (zwei Klassen von Trails, Start mit leerem Netz über Monate)
   und kein Import (ignoriert den Bestand).
3. **Offen registrieren, leere Karte, Einladung optional.** Wie
   PilzBuddy; ein Einladungslink füllt nur eine Buddy-Anfrage vor. Das
   Tor sitzt in der Sichtbarkeit, nicht an der Tür. Verworfen:
   Pflicht-Einladung (Play-Review braucht Testzugänge, Einladungskette
   ist eine weitere personenbezogene Tabelle) und Bürgen-Modell.
4. **Keine Fahrten in der Cloud in v1.** Fahrten bleiben auf dem
   Gerät, Sicherung ist der GPX-Export; Gerätewechsel heißt Fahrten
   weg, Trails bleiben. Verworfen für jetzt: private Sicherung (erste
   Tabelle, die mit gefahrener Zeit wächst; Bewegungsprofile unter
   Verantwortung des Betreibers). Eine spätere private Tabelle ändert
   nichts am Sichtbarkeitsmodell, die Tür bleibt offen.
5. **Die Messung läuft mit den Locus-Tracks des Betreibers** (GPX,
   gezippt; Zeiten und Höhen sind dabei). Die Sonderfälle — derselbe
   Trail mehrfach, Kehren, parallele Trails, Gegenrichtung, Fahrt mit
   mehreren Trails — sind im Bestand weitgehend enthalten. **Die
   Dateien gehören nicht ins Repo** (öffentlich; eine Fahrt beginnt an
   der Haustür): Sie liegen im DocuHub oder in einem lokalen Ordner, den
   das Werkzeug über eine Umgebungsvariable findet (Muster `KEYS_DIR`).
   Der Messbericht nennt Kennzahlen, keine Koordinaten und keine
   Ortsnamen; ein Wächter wie `private_info_test.dart` kommt von Anfang
   an mit. Das Werkzeug liest direkt aus dem Zip.
6. **Statusmeldungen in v1**, alle vier Werte, mit Datum; der jüngste
   gewinnt, alle bleiben sichtbar, eine neue Aufzeichnung setzt den
   eigenen Status auf „offen" (3) — eine geplante nicht (seit 0.46.1). Verworfen: nur gesperrt/offen, oder
   später.
7. **Rechtliche Prüfung vor dem Play-Store-Eintrag.** Bis dahin nur
   persönlich bekannte Nutzer über die GitHub-APK. Nutzungsbedingungen
   und Datenschutzerklärung werden vorher als Entwurf aus dem Konzept
   vorbereitet, aufbauend auf PilzBuddy, damit der Prüfende etwas in der
   Hand hat. Die Grenze, an der aus einem privaten Werkzeug eine
   Plattform wird, ist der erste Nutzer über einen Einladungslink, den
   der Betreiber nicht selbst verschickt hat — die liegt vor dem
   Play-Store und ist bewusst in Kauf genommen.
8. **Web voll wie PilzBuddy, von Anfang an**: Import, Liste, Blatt,
   Buddys, Status UND Offline-Karten samt IndexedDB-Zwischenspeicher
   für Trails; nur das Aufzeichnen bleibt Android. Folgen: Jede
   Kartenfunktion läuft ab v1 auf beiden Engines (MapLibre, flutter_map),
   Trails als Linien im Web brauchen den GeoJSON-Zwischenspeicher ab
   v1, und für die Offline-Karten im Web gilt die bekannte Grenze
   (100 MB je Datei auf raw.githubusercontent.com, DACH als eine Datei
   nur bis z8; `docs/offline-karten-web.md` in PilzBuddy). Verworfen:
   Web nur zum Pflegen ohne Offline, oder Android zuerst.
9. **Entschieden (2026-09-27): Zweitkonto, Free-Plan.** Das Live-Projekt
   liegt in einem eigenen Supabase-Konto des Betreibers; wem Konto,
   Token und Mails gehören, steht im DocuHub. Vor dem Play-Store-Eintrag
   bleibt der Transfer in eine Pro-Organisation die Option. Pausieren
   verhindert `keepalive.yml`. Die Abwägung davor: Der Free-Plan erlaubt zwei
   aktive Projekte je Konto, gezählt über alle Organisationen mit Owner-
   oder Admin-Rolle; beide sind belegt. Wege: Pro-Plan für die eine
   Organisation (hebt auch PilzBuddys Free-Grenzen), ein Projekt
   pausieren, oder ein Zweitkonto für den Start mit späterem
   Project-Transfer nach Pro vor dem Play-Store-Eintrag — das Zweitkonto
   umgeht die Regel eher, als sie zu nutzen, und braucht einen Eintrag im
   DocuHub, wem Token und Mails gehören.

## 11. Fahrplan

*Offizielle Trails (Behörden, Vereine, Bikeparks) sind eine getrennte
Ebene außerhalb dieses Modells: `docs/konzept-offizielle-trails.md`
(#13).*

*Rework vom 2026-09-30 (Besitz des Namens, geplante Importe, Spaß und
Zustand, Link, Stück selbst wählen, Zwillinge, Zusammenführen):
`docs/konzept-rework.md`, verfolgt in #109. Einführung (Kurzanleitung,
Touren, „Entdecken"): `docs/konzept-onboarding.md`, #137. Jeder Schritt
zieht die betroffene Stelle im Konzept im selben PR nach.*

**Der lebende Fahrplan ist #156** (Betreiber, 2026-10-05): Reihenfolge,
Stand und die Einordnung neuer Issues werden dort gepflegt, direkt und
ohne PR — die Historie des Issues ist der Nachweis, und jedes eingeplante
Issue hängt als Sub-Issue daran. Hier steht nur, welche Phasen es gibt
und wofür sie stehen. Ein PR an diesem Abschnitt braucht es nur, wenn
eine Phase dazukommt oder wegfällt — nicht für eine neue Issue-Nummer,
ein Häkchen oder eine neue Reihenfolge.

- **Phase 0 — Messen, bevor gebaut wird. ERLEDIGT** (2026-09-27):
  `tool/trail_match.py` gegen 584 Tracks, `docs/trail-abgleich-messung.md`.
- **Phase 1 — Grundgerüst. ERLEDIGT:** Auth, Buddys, Karte, Schema,
  Abgleich, GPX-Import, Trail-Blatt, Hinweise, Höhen.
- **Phase 2 — Aufzeichnen. ERLEDIGT:** Fahrt-Aufzeichnung, Zerlege-Blatt,
  Ausgangskorb auf Android.
- **Rework. ERLEDIGT bis auf den Abgleich:** Mehrere Aufzeichnungen je
  Trail, Zusammenführen und kurze Importe stutzen warten auf Daten
  mehrerer Nutzer.
- **Einführung. ERLEDIGT:** Kurzanleitung, Touren, „Entdecken", Marke.
- **Phase 3 — Offline und Austausch. ZUM TEIL:** Offline-Karten mit
  eigenem Host, Zwischenspeicher, Push, Gesehenes bleibt liegen (Android
  und Browser, #155), Ausgangskorb und Zwischenspeicher auch im Browser
  (#153). Offen: Nachrichten.
- **Phase 3b — Alltagstauglich, vor Testern außerhalb der Buddys.
  ERLEDIGT bis auf Freigabe und Tester.**
- **Phase 4 — Der Trail-zuerst-Planer. ERLEDIGT bis auf den Feldtest**
  (9, `docs/konzept-routing.md`); danach der Ausbau aus den
  Feldberichten (Höhenprofil im Ergebnis, ziehbare Zwischenpunkte).
- **Feldberichte vor der Freigabe** — jede Runde Rückmeldungen aus dem
  Feld zu einem Stand (zuletzt 0.73.0 und 0.82): Fehler und kleine
  Bedienwünsche, abgearbeitet vor der nächsten Freigabe.
- **Navigationsmodus** (neu am 2026-10-05, #232): eine Ansicht zum
  Abfahren einer geplanten Route — Karte dreht mit, eigene Position,
  Route und Abstand zur Linie, Dauerbenachrichtigung, Bild-im-Bild über
  anderen Apps. Ohne Abbiegehinweise und Sprachausgabe (13). Erst der
  Abschnitt im Routing-Konzept, dann der Bau.
- **Wegqualität** (neu am 2026-10-02): Güteklasse, Belag und
  Schwierigkeit der Wege messen, als Archiv auf dem eigenen Host
  ausliefern, auf der Karte zeigen und im Routing bepreisen.
- **Karte über DACH hinaus** (neu am 2026-10-05): erst den Bestand auf
  dem Host prüfen und messen, was Europa bzw. die Welt kostet; dann
  Regionen über eine Konfiguration und das Herunterladen einer ganzen
  Region (ändert `docs/konzept-offline-karten.md` 5).
- **Phase 5 — Community.** Airtime und Ranking unter Buddys, Fotos am
  Trail.
- **Englisch:** die Oberfläche nach der Sprache des Geräts — vor Testern
  außerhalb des deutschsprachigen Raums und vor dem Store-Eintrag.
- **Play Store:** rechtliche Prüfung, Store-Grafiken, Pro-Plan,
  AAB-Probe, 1.0.0. Danach die Entscheidung zum dezentralen Weg (12).
- **Arbeitsweise** (neu am 2026-10-05): Kernanforderungen als eigene
  Datei, gegen die jedes Konzept und jeder Fix geprüft wird (#221), und
  sparsamere Werkzeuge für die Entwicklung (#219).

Was als Nächstes kommt, steht oben in #156.

## 12. Dezentral: der offene Weg

*Frage des Betreibers am 2026-09-27: „Würde ein dezentraler Ansatz
funktionieren?" Die Antwort ist eine Entwurfsregel, keine Entscheidung
für v1.*

Drei Formen von „dezentral", zwei davon scheiden aus:

- **Echtes Peer-to-Peer, Telefon zu Telefon**: nein. Ein Telefon ist
  nie verlässlich online, Android friert Hintergrundprozesse ein, hinter
  Mobilfunk-NAT findet sich kein Gerät ohne Vermittler, der Web-Client
  hätte keinen Platz. Jedes mobile P2P-Projekt endet bei einem
  Relay-Server, also bei einem Betreiber.
- **Föderation, jede Gruppe ihr Server**: nein. Niemand betreibt einen
  Server für zwanzig Leute, und Trail-Netze leben davon, dass sich
  Gruppen überlappen.
- **Local-first mit einem Relay, das nichts lesen kann**: ja, das trägt.
  Die Daten liegen auf den Geräten; der Server speichert nur
  Ende-zu-Ende-verschlüsselte Blobs je Buddy-Beziehung und stellt sie
  zu. Der Betreiber sieht weder Geometrie noch Namen noch Status.

**Warum die dritte Form zum Motiv passt:** RLS schützt vor anderen
Nutzern. Verschlüsselung schützt zusätzlich vor dem Betreiber selbst,
vor einem Einbruch in die Datenbank und vor einer Herausgabeanordnung —
es gibt keinen Honigtopf, den jemand ausleeren könnte. Für eine
Plattform, deren Tor „nur wer es kennt, sieht es" heißt, ist das der
konsequente Endpunkt.

**Was es kostet, benannt:**

- **Der globale Abgleich (4.4) fällt weg.** Ein Server, der nichts
  lesen kann, findet keine Dubletten über Netze hinweg. Dedup läuft dann
  auf dem Gerät gegen das sichtbare Netz; beim Verbinden zweier Buddys
  werden die Bestände gegeneinander abgeglichen und die Kennungen
  ausgehandelt (die kleinere gewinnt, wie bei einem CRDT). Machbar: Es
  sind Hunderte Trails, und das Messwerkzeug hat 584 in fünf Sekunden
  verglichen. Die unsichtbaren Overlap-Kanten gibt es dann nicht — der
  einzige echte Verlust.
- **Die Datenbankseite aus PilzBuddy wird Ballast.** RLS, Policies,
  Schema Check, Patches: alles auf einen Server gebaut, der liest. Auth,
  Buddys, Offline-Karten, Aufzeichnung, Ausgangskorb, Feedback-Bot und
  CI bleiben.
- **Schlüssel sind ein eigenes Produkt.** Gerät verloren heißt Daten
  verloren, sofern keine Wiederherstellung ein Geheimnis irgendwo
  ablegt; Zweitgerät und Web-Client brauchen Schlüsseltransfer; Push
  trägt keinen Inhalt. Das ist die Arbeit, an der Messenger Jahre
  sitzen, und sie käme vor dem ersten Trail.
- **Nie möglich:** alles, was der Server über Nutzer hinweg rechnen
  müsste — Rankings, Community-Statistik, Moderation. Für dieses Konzept
  kein Verlust, denn genau das soll es nicht geben.

**Offene Frage des Betreibers, später anzusehen:** Kommen auf diesem
Weg Aktualisierungen — ein Trail-Status, eine neue Aufzeichnung — bei
allen Buddys an? Die kurze Antwort ist ja, aber anders als über eine
RPC: Der Server kann nichts auswerten, also fächert das GERÄT auf. Eine
Statusmeldung wird je Buddy-Beziehung einmal verschlüsselt und in dessen
Postfach gelegt, wie eine Nachricht; bei dreißig Buddys sind das dreißig
kleine Blobs. Ein inhaltsloser Push weckt die App, die holt ab. Der Preis
ist, dass Zustellung an Buddys hängt, die die App lange nicht öffnen —
ihre Postfächer wachsen, eine Frist räumt ab. Was ein Server hier NICHT
kann: nachträglich einem neuen Buddy den ganzen Bestand geben; das muss
das Gerät des Bestandsinhabers tun, wenn es online ist. Genau das ist
beim Verbinden ohnehin der Moment des Abgleichs.

**Die Regel für v1, damit der Weg offen bleibt:**

> Kein Feature darf darauf bauen, dass der Server über Netzgrenzen
> hinweg liest — mit genau einer Ausnahme, dem stillen Abgleich aus 4.4.
> Alles Sichtbare wird aus eigenen und Buddy-Beiträgen gerechnet, nie
> aus einer Aggregation über alle.

Das Konzept erfüllt sie heute schon (3, 6, 7). Solange sie hält, ist der
Wechsel auf ein verschlüsseltes Relay ein Umbau der Speicherschicht,
kein Neubau. Wird das Motiv „der Betreiber soll nichts herausgeben
können" wichtiger als der bequeme Start, ist das die Variante, die es
einlöst. Wer ein Feature vorschlägt, das die Regel bricht, schreibt
dazu, dass es diesen Weg schließt.

## 13. Abgrenzung und Integration (2026-10-01)

*Frage des Betreibers: Worin liegt der Mehrwert gegenüber Komoot und
Trailforks, und soll die App Outdooractive oder Komoot einbinden?
Entschieden am 2026-10-01: GPX-Brücke und Navi-Übergabe, keine
Konto-Kopplung.*

**Was TrailBuddy ist.** Das Netz für die Trails, die niemand auf
Trailforks oder Komoot stellt. Vier Dinge, die die großen Apps nicht
tun und nicht tun werden:

1. **Nichts ist öffentlich.** Sichtbar ist nur, was man selbst oder ein
   direkter Buddy gefahren hat (0, 7). Es gibt keine Karte für alle,
   keine Suche, keine Heatmap — und deshalb auch kein öffentliches
   Segment auf einem geduldeten Trail.
2. **Trail ≠ Fahrt.** Der Trail ist die Einheit, nicht die Tour; nur
   Gefahrenes wandert weiter (10.1). Komoot kennt Touren, Trailforks
   kennt öffentliche Trails; keines kennt „mein Trail, bei meinen
   Buddys".
3. **Zustand unter Buddys.** Meldung und Zustand mit Push, Bestätigen
   durch Fahren, „noch gültig?" — die Information, die auf einem
   inoffiziellen Trail sonst nur per Chat kursiert.
4. **Fahrten verlassen das Gerät nie** (10.4), die Karte kommt vom
   eigenen Host, offline zuerst.

**Was sie bewusst nicht ist.** Keine Navigation mit Abbiegehinweisen,
keine Entdeckungs-Plattform für fremde Gegenden, kein Tourenarchiv in
der Cloud, keine Statistik über alle. **Seit 2026-10-05 mit einer Ausnahme**
(Betreiber, #232): ein Navigationsmodus, der eine Route ZEIGT — Karte
dreht mit, eigene Position, Route und Abstand zur Linie, eine
Dauerbenachrichtigung und ein Bild-im-Bild-Fenster über anderen Apps.
Abbiegehinweise und Sprachausgabe gibt es weiter nicht; die Übergabe an
die Navi-App (#151, GPX) bleibt der Weg für alles darüber hinaus. Die
Grenzen stehen in `docs/konzept-routing.md` bei den Nicht-Zielen. **Die eine Planungsfunktion ist
der Trail-zuerst-Planer** (9, #158), weil ihn keine andere App hat:
Komoot und Outdooractive planen von A nach B über öffentliche Wege,
Trailforks zeigt Trails — keine davon plant „eine Runde mit möglichst
vielen MEINER Trails und möglichst wenig verschenktem Aufstieg". Wer das will, hat Komoot,
Outdooractive oder Trailforks — und soll sie NEBEN TrailBuddy benutzen
können, ohne dass eine der beiden Seiten etwas über die andere erfährt.

**Integration heißt Datei, nicht Konto.** GPX hinein gibt es (5.2);
GPX hinaus seit 0.68.0 (#150: Fahrten als Sicherung, Trails als Brücke);
die Anfahrt übergibt #151 an die Navi-App des Nutzers. Der Fluss, den
das trägt: Trails als GPX exportieren → in Komoot oder Outdooractive die
Verbindung planen → die geplante Tour als Fahrt importieren → das
Zerlege-Blatt sagt, welche Stücke bekannte Trails sind. TrailBuddy
behält die Trails, die andere App die Straßen dazwischen.

**Warum keine Konto-Kopplung.** Komoot und Outdooractive öffnen ihre
Schnittstellen nur Partnern mit Vertrag; Strava verlangt seit 06/2026
eine Gebühr und verbietet, fremde Aktivitäten anzuzeigen; Trailforks
gibt Daten nur share-alike für kostenlose Apps heraus (Stand 2026-10-01,
Websuche). Und unabhängig davon: Jede Kopplung trüge Trails auf eine
öffentliche Plattform — genau der Fall, den 7 ausschließt. Ein Link auf
das eigene Komoot- oder Strava-Konto fällt beim Vorschlag aus der Datei
weg (`kLinkIgnoredHosts`, Rework 4); von Hand bleibt er erlaubt, als
Aussage eines Nutzers.

**Prüfbar.** `test/privacy_policy_test.dart` kennt jeden Host; eine
Kopplung brächte einen neuen und ein OAuth-Paket in `pubspec.yaml`. Wer
eines davon vorschlägt, ändert diesen Abschnitt im selben PR.
