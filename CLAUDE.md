# TrailBuddy — Arbeitsregeln

Flutter-App (Android + Web): Mountainbike-Trails, die man mit seinen Buddys
teilt. Supabase-Backend (Auth + PostgreSQL mit PostGIS, Freigabe-Regeln
komplett über RLS in `supabase/schema.sql`), Riverpod ohne Codegen,
go_router, deutsche UI-Strings direkt im Code. Schwesterprojekt von
PilzBuddy (`MacBuchi/pilzbuddy`): Stack, CI-Muster und viele Bausteine sind
von dort kopiert (Stand 1.213.0), bewusst kopiert und NICHT als gemeinsames
Paket herausgezogen — erst wenn TrailBuddy steht, sieht man, was wirklich
gleich geblieben ist.

**Das Konzept ist maßgeblich:** `docs/konzept-trails.md` (Trail ≠ Fahrt ≠
Aufzeichnung, besitzerlose Trail-Kennung, Sichtbarkeit nur aus eigenen und
Buddy-Beiträgen, stiller globaler Abgleich, das Community-Tor, die
Entscheidungen des Betreibers in Abschnitt 10, die Regel für den
dezentralen Weg in Abschnitt 12). Die Schwellen des Abgleichs sind gemessen
(`docs/trail-abgleich-messung.md`), nicht geraten. Wer Code ändert, der dem
Konzept widerspricht, ändert das Konzept im selben PR — oder den Code.
**Der Fahrplan ist #156** (Betreiber, 2026-10-05): Reihenfolge, Stand und
die Einordnung neuer Issues werden dort direkt gepflegt, ohne PR; jedes
eingeplante Issue hängt als Sub-Issue daran. `konzept-trails.md` §11 nennt
nur die Phasen — ein PR dort nur, wenn eine Phase dazukommt oder wegfällt.
**Jeder offene Punkt trägt seine Umgebung** (Betreiber, 2026-10-07;
Legende im Kopf von #156): ☁️ Cloud-Sitzung, 💻 Rechner des Betreibers,
⚙️ nur als Workflow, 📱 Abnahme am Gerät, 👤 Entscheidung/Dashboard —
mehrere heißen „bauen hier, messen/abnehmen dort". Wer ein Issue
einplant, setzt den Tag; wer merkt, dass er nicht stimmt, korrigiert ihn
dort. Die Cloud hat Flutter (= CI), Chromium und Postgres + PostGIS
(`tool/schema_local_test.sh`), aber **keinen** Docker-Stack (PostgREST
und GoTrue erst im Dry Run), kein Gerät, keine Secrets und nichts
Privates des Betreibers (Fahrten, DocuHub); Workflow-Artefakte sind von
dort nicht abrufbar, Logs und Run-Summary schon.
Das Rework vom 2026-09-30 (`docs/konzept-rework.md`, #109) plant die
nächsten Schritte am Modell; gebaut wird es Schritt für Schritt, und
jeder zieht `konzept-trails.md` nach. Die Einführung (Tour, Kurzanleitung,
„Entdecken“; `docs/konzept-onboarding.md`, #137) übernimmt PilzBuddys
Mechanik aus #350/#596 und schneidet den Inhalt für Trails neu — sechs
gestapelte PRs, die Regeln für Anker, Merker und Beispiele stehen dort.
Die Routing-Engine (#35, #158) hat ihren Plan und ihr
Anforderungsprofil in `docs/konzept-routing.md` — eigene Engine, kein
BRouter (Betreiber, 2026-10-01); gebaut wird erst nach der Messung aus
dessen Abschnitt 6.
Offizielle Trails (#13) sind eine getrennte Ebene mit eigenem Konzept:
`docs/konzept-offizielle-trails.md`. Gebaut von `official-trails.yml`
(`tool/official_trails.py`, Quellen in `tool/official/sources.json`)
auf den Branch `official-trails-data` — nie als Release (die
Update-Prüfung nähme es im Vorab-Kanal für eine App-Version). Dort
liegen nur öffentliche Daten Dritter, keine Nutzerdaten.

**Das Aussehen steht in `docs/design/README.md`** (Farben hell/dunkel,
Schriften, Logo, Offline-Kachel-Regel, Kartenleisten, S-Grad als Form,
Bewegung, Reihenfolge der Umsetzung). Wie beim Konzept: Wer im Code davon
abweicht, ändert die Datei im selben PR. Alle App-Symbole erzeugt
`tool/brand_icons.py` aus EINER Geometrie (Logo „Serpentine C3" seit
0.65.0: gefüllte Fläche mit Anliegern, drei optische Größen L/M/S, die
Stichproben in `tool/brand/logo_c3.json`, Handoff in
`docs/design/trailbuddy-logo/` — Design-README Abschnitt 4); das Skript
schreibt auch die Dart-Geometrie
(`lib/core/widgets/trailbuddy_logo_geometry.dart`). Nie ein Symbol von
Hand tauschen, auch nicht gegen die fertigen Bilder des Handoffs.

**Nichts Privates in dieses Repo — es ist öffentlich.** Keine absoluten
Pfade des Betreiber-Rechners, keine privaten Mailadressen, keine GPX- oder
Zip-Dateien (eine Fahrt beginnt an der Haustür), keine Koordinaten in
Berichten. `tool/private_info_check.py` prüft das in CI. Ausnahme ist nur,
was öffentlich sein MUSS (Impressum, Datenschutzerklärung).

`AGENTS.md` ist ein Symlink auf diese Datei (CI prüft das). Was für Claude in
`CLAUDE.local.md` steht, gehört für Codex in die persönliche
`~/.codex/AGENTS.md`, nie ins Repo.

## Workflow

- Kein direkter Push auf `main`: Feature-Branch → PR → CI grün → Squash-Merge.
  (Branch-Schutz und Squash-Vorgabe: Repo-Einstellungen, vom Betreiber.)
- **Conventional Commits** für Commit- und PR-Titel:
  `<typ>(<bereich>): <was>`, Typen `feat`, `fix`, `perf`, `refactor`,
  `docs`, `test`, `ci`, `build`, `chore`; der Bereich ist optional
  (`import`, `trails`, `map`, `auth`, `web`, `db` …). Der PR-Titel IST der
  Commit auf `main` (Squash-Merge, Vorgabe „Pull request title"), also
  zählt er, nicht die Commits auf dem Branch. Auf GitHub Englisch
  (Commits, PRs, Issues); Deutsch für UI-Strings, Nutzer-Doku und die
  Kommunikation mit dem Betreiber.
- **Semantic Versioning** in `pubspec.yaml` (`MAJOR.MINOR.PATCH+BUILD`),
  abgeleitet aus dem Typ des PRs — dieselbe Praxis wie PilzBuddy:
  - `feat` ⇒ MINOR (`0.1.1 → 0.2.0`), `fix`/`perf` ⇒ PATCH
    (`0.1.0 → 0.1.1`). Andere Typen bumpen nur, wenn sie ins Binary
    gehen (Version Guard), dann als PATCH.
  - `BUILD` steigt bei JEDEM Bump um eins und nie zurück — Android
    lehnt eine APK mit kleinerem `versionCode` ab.
  - **Vor 1.0.0** ist MAJOR 0 und ein Bruch trotzdem nur MINOR. 1.0.0
    kommt mit dem Play-Store-Eintrag (Konzept 10, Punkt 7), nicht mit
    einer Schemaänderung: Ältere Clients schützt
    `minimum_supported_version`, nicht die Versionsnummer.
  - Mehrere Themen in einem PR: der höchste Typ entscheidet.
- **Version Guard** (ci.yml): Code-Änderung ohne Bump in `pubspec.yaml`
  blockiert den Merge, sobald es einen Release-Tag gibt. Ausgenommen sind
  `*.md` (außer `CHANGELOG.md`, die liegt als Asset im Binary), `.github/`,
  `tool/`, `supabase/`, `docs/`, `.claude/`, `.codex/`, `.mcp.json`. Er prüft, DASS gebumpt wurde; WELCHE Stelle
  nach den Regeln oben, ist Sache des PRs.
- **Changelog**: `CHANGELOG.md` wird in der App unter „Was ist neu" gezeigt.
  `test/changelog_test.dart` verlangt die pubspec-Version darin. Erlaubte
  Auszeichnung wie in PilzBuddy: `##`, kursive Metazeile, Absätze,
  `-`-Listen, `**fett**`, nackte URLs.
- **Release-Kanäle** (release.yml): Ein Bump auf `main` taggt `v<version>`
  und baut die signierte APK als **Prerelease**. **Kein Keystore, kein
  Tag**: Fehlen die Secrets `ANDROID_KEYSTORE_*`, tut der Workflow sichtbar
  nichts (Run-Summary) — und zwar VOR dem Taggen, damit kein Tag ohne
  Release entsteht. **`promote.yml`** (von Hand) macht ein Prerelease
  zu „latest" (erst dann meldet sich die App) und baut aus DEMSELBEN Tag
  die Web-App samt Rechtsseiten auf `gh-pages` (Pages: Branch
  `gh-pages`, Wurzel). Ohne Beförderung gibt es kein Web — und keine
  erreichbare Datenschutzerklärung. **Pages unterscheidet Groß- und
  Kleinschreibung**: Das Repo heißt deshalb `trailbuddy` (klein), passend
  zu `--base-href /trailbuddy/` und den Links in `AppInfo`; GitHub, API
  und raw.githubusercontent.com sind davon nicht betroffen.
  **`preview.yml`** deployt jeden Merge auf `main` als Web-Vorschau nach
  `MacBuchi/trailbuddy-preview` (→ https://macbuchi.github.io/trailbuddy-preview/,
  der Link „Entwicklungsversion öffnen" im Profil). Eigenes Repo, weil
  `promote.yml` den Pages-Branch je Beförderung neu anlegt und weil ein
  eigener Origin einen eigenen `localStorage` hat (Sitzung, Einstellungen)
  — deshalb dort neu anmelden. `--dart-define=PREVIEW_BUILD=true`
  schaltet den Streifen „Entwicklungsstand" und dreht den
  Profil-Verweis um; `--base-href /trailbuddy-preview/` muss zum Link
  passen (falsch ⇒ weiße Seite ohne Fehler). Zugang ist ein Deploy Key
  (`PREVIEW_DEPLOY_KEY`, öffentlicher Teil im Vorschau-Repo mit
  Schreibrecht), kein PAT; fehlt er, sagt es die Run-Summary mit den
  Schritten. `test/release_workflow_test.dart` wacht über Flag, base-href
  und Ziel-Repo.
- **Schema Dry Run** (ci.yml, Pflicht-Check): lokaler Supabase-Stack auf
  dem Runner (`supabase/config.toml`, Portblock **5452x**), beide Wege —
  Bestand (Basis-Schema + neue Patches) und Frischinstallation (leere
  Datenbank, `db_migrate.sh` spielt `schema.sql` ein — derselbe Zweig wie
  beim ersten Lauf gegen das leere Live-Projekt) —, danach
  `tool/schema_check.sh` (App-Queries gegen das Schema),
  `tool/matcher_check.sql` (der Abgleich mit echten Linien) und
  `tool/auth_reset_check.sh` (Auth-Flows gegen echtes GoTrue).
  Ohne Docker lokal: `tool/schema_local_test.sh` (Postgres + PostGIS,
  Frischinstallation; mit `TB_BASE_SCHEMA=<schema.sql von main>` und
  `TB_PATCHES` der Bestandsweg, `TB_SEED`/`TB_AFTER` für Daten vor und
  Prüfungen nach dem Patch, `TB_DUMP` für den Schema-Vergleich beider
  Wege). PostgREST und GoTrue sieht erst der Dry Run in CI.
  `auto_expose_new_tables = false`: Ein vergessener Grant fällt im Dry Run
  auf, statt still von der Vorgabe ersetzt zu werden.
- **Schema Check** (ci.yml, `needs: schema-dry-run`): erst danach wird die
  Live-Datenbank angefasst — `db_migrate.sh` spielt neue Patches ein (auf
  einem LEEREN Projekt vorher `schema.sql`; halb eingerichtet ⇒ Abbruch
  statt Raten), dann `schema_check.sh` gegen das Live-Schema. Braucht das
  Secret `SUPABASE_DB_URL` (Session-Pooler-URI inkl. Passwort). Der
  Release-Workflow wiederholt beides vor dem Bauen. **Nie Schema von Hand
  im Dashboard ändern** — der Weg ist immer ein `patch_NNN`.
- **Live-Projekt wach halten** (`keepalive.yml`, Mo + Do): Der Free-Plan
  pausiert nach ~1 Woche ohne Zugriff. Der Lauf fährt `schema_check.sh`
  gegen live und ist damit zugleich Drift-Wächter. Wer ihn abschaltet,
  riskiert eine tote App. Das Projekt liegt im Zweitkonto des Betreibers
  (Konzept, Punkt 9; wem Konto und Mails gehören: DocuHub).
- **Patches**: `supabase/patch_NNN_*.sql` + Struktur in `schema.sql` + Eintrag
  in der Saat-Liste, alles im selben PR; ein eingespielter Patch wird nie
  wieder angefasst (`tool/patch_guard.sh`). Baseline ist 0: Es gibt keine
  von Hand eingespielten Patches.
- **Supabase-Konfiguration der App**: `lib/core/supabase_config.dart` liest
  `SUPABASE_URL`/`SUPABASE_KEY` aus `--dart-define`, Vorgabe ist das
  Live-Projekt (Publishable Key ist öffentlich; niemals den
  service_role-Key). Gegen den lokalen Stack per `--dart-define` bauen.

## Technik-Notizen — Index

Die Technik-Notizen liegen seit dem 2026-10-06 NEBEN DEM CODE, je Ordner
eine `CLAUDE.md` (vorher 130 KB in dieser Datei, in jeder Sitzung ganz
geladen; #237, Vorlage PilzBuddy #670). Claude Code lädt eine Teildatei
von selbst, sobald eine Datei in ihrem Ordner gelesen wird. **Wer an einem
Thema arbeitet, dessen Ordner er noch nicht geöffnet hat — und Codex
immer —, liest die Teildatei vorher.** `tool/agent_docs.py` (CI, „Analyze &
Test“) hält Index und Dateien zusammen und diese Datei unter ihrer
Größengrenze. Neues Wissen gehört in die Teildatei des Ordners, in dem der
Code liegt — nicht wieder hierher.

| Datei | Themen |
|---|---|
| `supabase/CLAUDE.md` | Der Abgleich läuft in der Datenbank · `trails` hat keinen Client-Grant · Beitrag löschen |
| `lib/features/trails/CLAUDE.md` | Importregel · Höhen · Schwierigkeit · Charakter · Farbe = Schwierigkeit · Link zur Quelle · Hinweise für Buddys · Bewertung, Meldung, Zustand · Suche, Filter, Sortierung der Trail-Liste · Übernehmen beim ersten Befahren · GPX-Export von Fahrten und Trails · Anfahrt zum Trailkopf |
| `lib/features/map/CLAUDE.md` | Orte auf der Karte · Glatte Linien und Namen am Trail · Eigene Position · Karten-Engine und Fassade (#31) · Die Tastatur überlagert, sie schiebt nicht · Die Legende auf der Karte · Die Ebene „Wege" (#212) · Gesehenes bleibt liegen (#155) · Höhenlinien (#271) · Regionen des Kartenhosts (#220) |
| `lib/features/offline_areas/CLAUDE.md` | Gespeicherte Bereiche, Werkzeugleiste, Zeichnen (#67, #82) · Höhenkacheln je Bereich (`tool/height_tiles.py`, `height-data.yml`) · Bereiche je Region · Übersicht je Region (#220) |
| `lib/features/official/CLAUDE.md` | Offizielle Trails in der App |
| `lib/features/friends/CLAUDE.md` | Nach dem Annehmen einer Buddy-Anfrage |
| `lib/features/rides/CLAUDE.md` | Fahrt aufzeichnen · Bestätigen durch Fahren · Das Zerlege-Blatt |
| `lib/features/routing/CLAUDE.md` | Die Routing-Engine, Schritt 3: Graph, Profil, Suche · Steile Anstiege · Vorlieben und verschenkte Höhe · „Zum Trailkopf" · Der Rundenplaner · Kalibrierung aus eigenen Fahrten · Navigation rund · Die Folgeansicht der Navigation |
| `lib/data/CLAUDE.md` | Ausgangskorb · Zwischenspeicher des Netzes · Speichern ohne Neuladen des Netzes · Beendigungsgründe |
| `lib/core/CLAUDE.md` | Bewegung · Zurück nach Hierarchie · Push (#34; auch `push_flush`, `send-push`, Web-Worker, Android-Kanal) |
| `lib/features/coach/CLAUDE.md` | Die Hinweis-Maschine und die Karten-Tour |
| `lib/features/help/CLAUDE.md` | Einführung: Kurzanleitung, Sicherheitshinweis, Kontexthilfe · Die Karten-Tour beim ersten Start · Die Tour im Zerlege-Blatt · Touren je Reiter, Kette und Beispiele |
| `lib/features/highlights/CLAUDE.md` | Neuheiten, „Entdecken" und „Zeig es mir" |
| `lib/features/feedback/CLAUDE.md` | Feedback (die Glühbirne) · Fehlerbericht-Digest (`tool/feedback_bot.py`) |
| `web/CLAUDE.md` | Kein Netzziel ohne Datenschutzerklärung · Web (Service Worker, Build) |
| `android/CLAUDE.md` | Android (Flavors, Backup-Ausschlüsse) · Play Store vorbereitet, nicht eingereicht |
| `test/CLAUDE.md` | Dart-MCP (`analyze_files`, `run_tests`, `lsp`: Pfad-Fallen, Messung) · Gegenprobe · Fallen im Harness (pumpApp, FakeSettings, Touren, Isolates, FakeMapView) |

Was es bewusst noch nicht gibt:

- **Noch nicht da, bewusst** (jeweils eigener PR, Muster in PilzBuddy):
  Nachrichten zwischen Buddys (#34, Rest),
  Meldung zu einem einzelnen Trail.

## Code-Konventionen

Wie PilzBuddy: Business-Logik in Repositories, Mutationen per
`reloadAfterWrite` (am Trail-Netz gezielt per `_rereadAfterWrite`, siehe
„Speichern ohne Neuladen des Netzes" in `lib/data/CLAUDE.md`), `mounted` nach jedem `await`, `requireUid` statt
`currentUser!.id`, `catch (_) {}` nur mit Grund. Farben aus
`lib/core/app_colors.dart` (Marke Lime `AppColors.brand`, hell und dunkel
als `AppPalette`, gelesen mit `AppPalette.of(context)`; Text in Marke,
Warnung, Buddy über `accentText`/`warningText`/`buddyText` — die
Linienfarben reichen im Hellen als Text nicht). **Die Karte ist immer
hell**: Linien nehmen `AppColors.mapLines` (heller Satz, weißer Saum),
nicht den Modus der App. Schriften als Assets (`AppFonts`: Barlow,
Barlow Condensed für Titel, JetBrains Mono für Zahlen), kein
`google_fonts`. Theme in `lib/core/app_theme.dart`, Modus aus
`Settings.appearance` (Profil, „Erscheinungsbild").

## Tests

`flutter analyze` + `flutter test` nach jeder Änderung, **kein `dart
format .`**. Harness `test/fakes/test_app.dart` (`pumpApp`) gegen die Fakes
in `test/fakes/`, die die RLS-Regeln spiegeln (`fake_trails.dart` für die
Trail-Sichtbarkeit). Kein Netz in Tests; Kartenkacheln kommen aus dem
Fake-Tile-Provider.

**Agenten-Werkzeug** (#237): `.mcp.json` hängt den offiziellen Dart- und
Flutter-MCP-Server ein (`tool/dart_mcp.sh`, für Codex `.codex/config.toml`);
wie man ihn benutzt und wo er still nichts prüft, steht in `test/CLAUDE.md`.
`.claude/settings.json` startet jede Sitzung mit dem Lagebild
(`tool/session_status.py`) und gibt lesende Befehle frei; der Skill
`trail-issue` führt vom Issue zum PR.

## Compact instructions

Kontext und Sitzungen (#237, aus PilzBuddy #671). `/compact` und `/clear`
kann nur der Betreiber auslösen; `tool/context_nudge.py` sagt ihm, wann es
sich lohnt (Kontext ab 200k je 100k-Stufe, nach über 60 min Pause, nach
`gh pr create`). Der Agent wiederholt den Rat am Ende einer Antwort, wenn
die Aufgabe damit abgeschlossen ist. Faustregel: **Aufgabe fertig →
`/clear`** (kostet nichts; Ordner-`CLAUDE.md` und Lagebild bringen den
Kontext neu mit). **Kein `/rename` davor** (Betreiber, 2026-10-07): Ein
Name spart nichts, er macht in der Kommandozeile nur einen alten Verlauf
über `/resume` auffindbar; in einer Cloud-Sitzung gibt es das nicht, und
nach `/clear` trüge die nächste Aufgabe den alten Namen. Was offen bleibt,
gehört ins Issue, in den PR oder nach #156. **Gleiche Aufgabe, Kontext zu groß →
`/compact`** (liest selbst den ganzen Verlauf, ist also nicht gratis).

Beim Zusammenfassen BEHALTEN: Issue- und PR-Nummern, Branch, jede
Entscheidung und Vorgabe des Betreibers im Wortlaut, offene Punkte und
Zusagen („melde mich, wenn …"), geänderte Dateien, welche Tests und
Gegenproben gelaufen sind und mit welchem Ergebnis, Messwerte.
WEGLASSEN: Dateiinhalte und Tool-Ausgaben, die sich neu lesen lassen,
verworfene Suchwege, Inhalte der Ordner-`CLAUDE.md` (laden neu).
