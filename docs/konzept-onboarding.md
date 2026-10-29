# TrailBuddy — Einführung: Tour, Kurzanleitung, Entdecken

*Plan vom 2026-09-30 zu #126 („Einführungskonzept wie PilzBuddy, für
PWA und Android“), verfolgt in #137. Vorlage ist PilzBuddys Bausteinpaar
aus #350 (Kurzanleitung, Kontexthilfe) und #596 (Hinweis-Maschine,
Touren je Reiter, Startseiten, Beispiele, „Entdecken“). Übernommen wird
die Mechanik samt ihren Regeln, der Inhalt wird für Trails neu
geschnitten. Die Entscheidungen des Betreibers stehen in Abschnitt 1,
die PR-Kette in Abschnitt 2, die Skripte in Abschnitt 4, die offenen
Punkte in Abschnitt 9.*

## 0. Ausgangslage

TrailBuddy erklärt sich heute mit drei Sätzen in Leerzuständen (Karte,
Trail-Liste, Buddys) und einem „Was ist neu“ aus `CHANGELOG.md`, das
nur auf Zuruf aus „Über TrailBuddy“ zu erreichen ist. Es gibt keinen
Merker „gesehen“, keinen Sicherheitshinweis und keine Anker an den
Knöpfen, auf die eine Tour zeigen könnte. Wer die App zum ersten Mal
öffnet, sieht eine leere Karte und vier Reiter.

PilzBuddy hat seit #350/#596 vier Bausteine, dokumentiert in dessen
`CLAUDE.md`:

- **A — Kontexthilfe ohne Maschinerie**: Leerzustände, die sagen, was
  hier erscheinen wird, und eine **Kurzanleitung** aus Widgets mit den
  echten Symbolen (kein `.md`-Asset — das läge im Binary, wäre für den
  Version Guard aber `*.md` und damit von der Bump-Pflicht ausgenommen).
- **B — die Hinweis-Maschine** (`coach.dart`): eine Überlagerung über
  allem, die Elemente ausspart, einen Ring auf das Gemeinte legt, eine
  gezeichnete Hand tippen lässt und Szenen (Menü, Blatt) selbst öffnet.
  Sie schluckt jeden Tipp (eine Vorführung löst nie etwas aus), nimmt
  die Zurück-Taste, solange sie läuft, und sagt ein fehlendes Ziel,
  statt es still zu überspringen.
- **Touren**: eine Karten-Tour beim ersten Start mit Startseite, danach
  je Reiter eine kurze Tour beim ersten Besuch, in einer Kette
  („Weiter mit …?“). „Nicht jetzt“ ist ein Gesehen (Betreiber,
  2026-10-29, #417 — vorher fragte die Tour bei jedem Start wieder);
  jede Tour bleibt in der Kurzanleitung startbar. Für leere Konten
  gezeichnete Beispiele, immer als „Beispiel“ markiert, nie gespeichert.
- **Entdecken**: alle Funktionen als Liste je Reiter, ein Blatt „Neu in
  …“ nach einem Update, und je Eintrag eine Vorführung („Zeig es mir“)
  auf der Maschine. Jede Feature-PR bringt Eintrag und Vorführung mit.

## 1. Entscheidungen des Betreibers (2026-09-30)

1. **Alles aus PilzBuddy, in Stufen.** Jede Stufe ein eigener PR, für
   sich nutzbar.
2. **Doku nur in der App.** Kurzanleitung als Widgets; keine
   `web/anleitung.html` (zwei Stellen zu pflegen, und die PWA IST die
   App).
3. **Ein Sicherheitshinweis vor der ersten Tour**, einmalig, später
   unter „Über TrailBuddy“ nachlesbar.
4. **Beispiele für leere Konten** während der Tour: ein gezeichneter
   Beispiel-Trail (Zeile und Blatt) und ein Beispiel-Buddy.

Empfehlung, die der Betreiber mitträgt — Mechanik gleich, Inhalt anders:

- **Die Tour erklärt Wege, nicht Reiter.** PilzBuddys Karte ist selbst
  Inhalt; TrailBuddys Karte ist am Anfang leer. Die Willkommensseite
  nennt die drei Wege, auf denen Trails hierher kommen (GPX importieren,
  Fahrt aufzeichnen, Buddys verbinden), dann zeigt die Tour, was die
  Karte zeigt.
- **Eine Tour im Zerlege-Blatt nach der ersten Aufzeichnung** statt
  einer Profil-Tour: Das ist der Moment, in dem man Hilfe braucht.
- **Die Skripte beschreiben den Stand nach dem Rework**
  (`konzept-rework.md`, #109). Während dieser Plan entstand, ist es
  gelandet (#118–#130, `main` auf 0.58.0): Status heißt „Meldung“, dazu
  Zustand und Bewertung, die Linienart auf der Karte (#122), die
  Übernahme beim ersten Befahren (#127/#128), Markierungen beim
  Aufzeichnen (#129). Keine Stufe wartet mehr darauf; Kurzanleitung und
  Touren nennen, was gebaut ist, nicht, was geplant war.
- **Keine Rückkehrer-Startseite.** PilzBuddy unterscheidet „Willkommen“
  und „Rückblick“ nur wegen seiner Merker-Resets. TrailBuddy hat kein
  Altschlüssel-Erbe; alle heutigen Tester sehen die Tour einmal.
- **„Entdecken“ zuletzt, aber ja.** Bei diesem Releasetakt ist das
  Blatt nach dem Update das Nützlichste; die Pflicht „Eintrag +
  Vorführung je Feature-PR“ kommt mit PilzBuddys Ausweg im PR-Template
  („oder ein Satz, warum nicht“).

Zwei Grundsätze für die Kette:

- **Kopieren, nicht teilen** (`CLAUDE.md`): `coach.dart` hängt nur an
  Riverpod und den Farben und wird wörtlich übernommen; das Review ist
  ein `diff` gegen PilzBuddy, der nur die Anpassungen zeigt. Skripte,
  Kurzanleitung, Bilder und Beispiele sind neu, aber in derselben Form.
- **Ordner wie PilzBuddy**: `lib/features/coach/`, `lib/features/help/`,
  `lib/features/highlights/`. NICHT `lib/features/tour/` — das ist dort
  die GPS-„Pilztour“, das Gegenstück hier heißt `lib/features/rides/`.
  Routen englisch wie die bestehenden: `/profile/help`,
  `/profile/discover`.

## 2. Die PR-Kette

| # | Issue | Titel (= Squash-Commit) | Sichtbar | Wartet auf |
|---|---|---|---|---|
| 1 | #131 | `feat(help): Kurzanleitung, Sicherheitshinweis und Kontexthilfe` | Kurzanleitung im Profil, Hinweis beim ersten Start, Leerzustände verlinken | — |
| 2 | #132 | `feat(coach): Hinweis-Maschine und Karten-Tour aus der Kurzanleitung` | Knopf „Tour auf der Karte zeigen“ führt vor | PR 1 |
| 3 | #133 | `feat(help): Karten-Tour beim ersten Start mit Startseite` | Willkommen + Tour nach dem Hinweis | PR 2 |
| 4 | #134 | `feat(help): Tour zum Zerlegen der ersten Fahrt` (Android) | Erklärung im Zerlege-Blatt, einmalig | PR 3 |
| 5 | #136 | `feat(help): Touren für Trails und Buddys mit Beispielen` | Kette nach der Karten-Tour, Beispiele für leere Konten | PR 3 |
| 6 | #135 | `feat(highlights): Entdecken, Neuheiten nach Updates und „Zeig es mir“` | Blatt nach Update, „Entdecken“ mit Neu-Punkt, Vorführungen | PR 5 |

Jeder PR ist `feat` ⇒ MINOR, nächste freie Nummer beim Rebase, BUILD +1
(`main` steht bei 0.58.0+67). Jeder PR bringt mit: `CHANGELOG.md`-Block,
Technik-Notiz in `CLAUDE.md`, `docs/design/README.md` wo das Aussehen
betroffen ist, `flutter analyze` + `flutter test`,
`tool/private_info_check.py` nach `git add`, eine Gegenprobe (ein Test
bewusst rot) im PR-Text. Keine neuen Netzziele. Die Stufen bauen
aufeinander auf und werden gestapelt; nach jedem Squash des Betreibers
`git rebase --onto origin/main <alte Basis>`.

**Warum PR 2 Maschine UND Karten-Tour enthält:** Die Maschine allein
geht ins Binary (Bump) und bräuchte einen Changelog-Block ohne sichtbare
Änderung. Mit dem Karten-Skript und dem Knopf in der Kurzanleitung hat
sie Nutzen, und der Flow-Test der Tour steht schon. Auto-Start,
Startseite und Kette kommen in PR 3.

## 3. Die Stufen im Einzelnen

### 3.1 Kurzanleitung, Sicherheitshinweis, Kontexthilfe (PR 1)

- `lib/features/help/help_screen.dart`: `HelpStep{icon: Widget, title,
  text}`, öffentliches `kHelpSteps` (sechs Abschnitte, Obergrenze — eine
  Anleitung, die man scrollen muss, liest niemand zu Ende), `HelpScreen`
  mit `SafetyNoteTile` oben. Die sechs Abschnitte:
  1. **Trails importieren** — GPX/Zip aus anderen Apps; kurz und bergab
     wird ein Trail, eine Runde eine Fahrt, die über die Schere ins
     Zerlege-Blatt geht. Nur Trails gehen zu Buddys.
  2. **Die Karte lesen** (Symbol: das echte `GradeShield`) — Farbe =
     Schwierigkeit wie im Skigebiet, grau ohne Einschätzung, Magenta
     Uphill. Die Art der Linie ist der Zustand: durchgezogen gepflegt,
     bröckelig ausgefahren, gestrichelt abgerockt, verblasst kaum
     fahrbar (Design-README Abschnitt 2, seit 0.51.0). Der Saum: weiß
     gestrichelt bei S4/S5, orange bei einer Meldung, gelb bei einem
     neuen Hinweis. Violett gestrichelt sind offizielle Trails. Das
     Schild am Anfang, ein Tipp öffnet das Blatt.
  3. **Fahrt aufzeichnen und zerlegen (Android-App)** — auch in der PWA
     zeigen, mit dem Zusatz.
  4. **Buddys und Sichtbarkeit** — nur direkte Buddys, keine öffentliche
     Karte, gleiche Trails werden EIN Trail mit zwei Namen, „Nur für
     mich“.
  5. **Mein Beitrag** — Name, S-Grad, Charakter, Meldung, Sichtbarkeit,
     Beschreibung, Link, dazu Zustand und Bewertung; Hinweise leuchten
     gelb. „Meldung“ ist seit #118 die Beschriftung des Dialogs;
     `help_texts_test` prüft das Wort gegen dessen Konstante, damit der
     Test bricht, nicht der Text, wenn es sich noch einmal ändert.
     **Gebaut abweichend:** Die Konstante heißt `kReportFieldLabel` und
     liegt in `trail_report.dart` — die Meldung steht seit 0.49.0 nicht
     mehr im Beitrags-Dialog, sondern in „Melden“.
  6. **Ohne Empfang** — Zwischenspeicher, Ausgangskorb, Bereiche unter
     „Ebenen“, „Meine Bereiche“.
- `lib/core/widgets/safety_note.dart`: Kopie von PilzBuddy mit neuem
  Wortlaut (Entwurf): „Du fährst auf eigene Verantwortung. TrailBuddy
  zeigt, was du und deine Buddys gefahren sind — es sagt nicht, ob ein
  Weg befahren werden darf oder gerade sicher ist. Beachte Sperrungen,
  Wegeregeln und Naturschutz vor Ort. Eine Meldung eines Buddys ist
  keine Freigabe, und keine Meldung heißt nicht, dass alles frei ist.“
  Dialog „Kurz vorweg“ / „Verstanden“, nicht wegtippbar. Kachel in
  `warningText`, Symbol `warning_amber_outlined` statt Emoji.
- Merker `safetyNoteSeen` (`safety_note_seen`) in `Settings`, Provider
  als `RememberedFlag` (Muster `officialTrailsEnabledProvider`).
- Karte: der Hinweis im vorhandenen Post-Frame-Callback von
  `MapScreen`; `_EmptyHint` wird tippbar und führt zur Kurzanleitung.
  Leerzustände von Trails, Buddys, Fahrten bekommen einen Knopf
  „Kurzanleitung“.
- Profil: Zeile `help` „Kurzanleitung — Das Wichtigste in sechs
  Schritten“ über „Über TrailBuddy“; dort eine Zeile
  „Sicherheitshinweis“ über `showInfoText` (`info_button.dart`, erster
  Einsatz — „Dialog, kein Tooltip“). Route `help` unter `/profile`.
- Tests: `onboarding_flow_test`, `safety_note_flow_test`,
  `help_texts_test` (sechs Abschnitte, Titel einmalig, Abschnitt 2
  nennt „S0“ und den Saum, der Hinweis „Verantwortung“ und
  „Sperrungen“ — nicht Zeichen für Zeichen).

### 3.2 Hinweis-Maschine und Karten-Tour aus der Kurzanleitung (PR 2)

- `lib/features/coach/coach.dart`: Kopie von PilzBuddys `coach.dart`.
  Nur diese Anpassungen: Ring, Finger und Ärmel in `AppColors.brand`
  statt Waldgrün; Blase in `AppPalette.surface` mit Rand `line`, Zähler
  in `AppFonts.numbers`; `reduceMotion(context)` aus `motion.dart`
  statt `MediaQuery.disableAnimationsOf`; Kopfkommentar auf #126 und
  den PilzBuddy-Stand der Kopie. Keys und Beschriftungen unverändert
  (`coach-intro`, `coach-intro-start`, `coach-intro-later`,
  `coach-bubble`, `coach-target-lost`; „Zeig's mir“, „Nicht jetzt“,
  „Weiter“, „Los geht's“, „Überspringen“). **Eine Erweiterung:**
  `CoachStep.illustration` — ein Widget unter dem Blasentext. Grund:
  Trail-Linien sind Engine-Polylinien, keine Widgets; der Schritt
  „Farbe heißt Schwierigkeit“ kann nichts aussparen und braucht eine
  gezeichnete Mini-Legende in der Blase. **Seit 0.77.0 (#182)** gibt es
  die Legende auf der Karte; der Schritt klappt sie über die Szene
  `MapCoach.legend` auf und leuchtet sie aus, die Mini-Legende ist weg
  (`illustration` bleibt als Möglichkeit der Maschine).
- `lib/features/help/map_tour.dart`: Anker-Kennungen (`NavCoach`,
  `MapCoach`, `SheetCoach` — das Trail-Blatt teilt sich PR 5 mit der
  Karte), `kMapTourScript`, `kNavStep`, `startMapTour`,
  `mapTourSeenProvider`. Noch ohne Startseite: ohne `art` beginnt die
  Tour beim ersten Schritt. **Gebaut abweichend:**
  `safetyNoteSeenProvider` bleibt in `safety_note.dart` — der Merker
  gehört zum Hinweis, nicht zur Tour.
- Einbau in `lib/app.dart`:

  ```dart
  builder: (context, child) => StartSplash(
    child: Stack(fit: StackFit.expand, children: [
      CoachSemanticsGate(
        child: PreviewRibbon(child: PushListener(child: UpdateGate(child: child!))),
      ),
      CoachOverlay(
        onNavigate: (route) => router.push(route),
        backButtonDispatcher: router.backButtonDispatcher,
      ),
    ]),
  ),
  ```

  Der Splash bleibt ganz außen: Er liegt 1,45 s über allem und
  schluckt Tipps; Hinweis und Startseite darunter sind statisch,
  nichts geht verloren. Sperrt der `UpdateGate`, wird `MapScreen` nie
  gebaut, also keine Tour. Update-Banner und Push-Leiste liegen
  während einer Tour im Dunkel, nicht tippbar — hinnehmbar. Der
  Auslöser sitzt in `MapScreen`, also nur angemeldet. Die Zurück-Taste
  gehört der Maschine, solange sie läuft, danach wieder dem System —
  beide Richtungen im Flow-Test.
- Anker (Schema `<bereich>.<element>`, Szenen `<bereich>.<szene>`,
  verschachtelt mit `/`; Konstanten je Bereich, damit Skript und Widget
  dieselben Wörter benutzen):
  - `nav.bar`, `nav.map/trails/buddys/profile` — die `NavigationBar`
    in `AppShell` (`router.dart`).
  - `map.buttons` (die Knopfspalte), `map.feedback` (Glühbirne, bekommt
    `key: feedback-button`; seit 0.75.0 oben rechts, nicht mehr in der
    Spalte, #180), `map.layers` (Kartenebenen), `map.offline`
    (Offline-Karten, seit 0.75.0, #190), `map.locate` (bekommt
    `key: locate-button`), `map.record` (nur Android ⇒ `requires`).
  - `map.trailBadge` — das erste Schild aus `trailBadgeMarkers`. Auf
    Android zeichnet MapLibre die Marker über `WidgetLayer` als
    Flutter-Widgets, der Anker sitzt also auf beiden Engines
    (Gerätecheck trotzdem).
  - `map.rail` — die Leiste, und generisch je Knopf `map.rail.<key>`
    in der Knopf-Fabrik von `offline_tool_rail.dart`.
  - `map.filter.official`, `map.filter.pois`, `map.filter.trails` im
    Blatt „Kartenebenen" (`poi_layer.dart`).
  - `sheet.metrics`, `sheet.grade`, `sheet.ownGrade`,
    `sheet.contribution` („Mein Beitrag“ bekommt
    `key: trail-contribution`), `sheet.addNote`, `sheet.showOnMap` im
    Trail-Blatt.
  - Szenen in `MapScreen.initState`: `map.rail` (`_openTools` /
    `_closeTools`), `map.layersSheet` (`showMapLayersSheet`; bis 0.74.x
    `map.rail/filter` auf der Leiste),
    `map.trailSheet` (`showTrailSheet` mit dem ersten sichtbaren Trail;
    ohne Trail fällt der Schritt weg). Abmelden in `dispose`. **Gebaut:**
    Schild und Blatt zeigen DENSELBEN Trail (der erste gezeichnete mit
    Schild); Schritt 2 fällt über `unless: [map.empty]` weg — der leere
    Kartenzustand ist ein Anker, denn der Anker im Blatt entsteht erst
    mit der Szene und darf nicht in `requires` stehen.
- Kurzanleitung: Knopf „Tour auf der Karte zeigen“ → `context.go('/')`,
  `startMapTour(ref)`. Merker `mapTourSeen` (`map_tour_seen`).
- PR-Template: Haken „UI, auf die eine Tour zeigt, geändert? Anker noch
  da; `map_tour_flow_test` grün.“
- Tests: `coach_test` (Kopie: Messung unter `Transform.scale`, Szenen,
  „Ziel verloren“, `requires`, verschachtelt, Zähler, reduzierte
  Bewegung, Semantics-Gate, `FingerMotion` pur) und
  `map_tour_flow_test` (Start aus der Kurzanleitung; Aussparung und
  Ring auf den echten Widgets, normal und 360×740; Leiste und
  Filter-Blatt gehen auf und zu; Tippen löst nichts aus; Zurück beendet
  die Tour, nicht die App; Blase im Bild und nie auf dem Erklärten).
  `settle` (8 × 100 ms) deckt die Tippsperre von 400 ms.

### 3.3 Karten-Tour beim ersten Start mit Startseite (PR 3)

- `lib/features/help/tour_intro_art.dart` (neu, nicht kopierbar —
  PilzBuddy zeichnet Pilze): Bühne 240 × 150, Radius 20, Grund
  `AppPalette.ground`, Motiv die Serpentine (`logoPath()`).
  `welcomeArt`: Serpentine in der Marke, ein Punkt läuft die Linie
  entlang (4 s Schleife); `mapArt`: drei Linienstücke in den
  Pistenfarben mit weißem Saum und einem Schild. Keyframe pur
  `introDriftAt(t)`, Test ohne Pixel; bei reduzierter Bewegung das
  Endbild.
- `kWelcomeIntro` (Titel „Willkommen bei TrailBuddy“, `startLabel`
  „Tour starten“), `kWelcomeTourScript = [kWelcomeIntro,
  ...kMapTourScript.tourSteps]` ohne `endLink` (die Kette geht ab PR 5
  weiter), `startWelcomeTour(ref, router)`.
  **Gebaut:** `kMapTourScript` bekommt dafür seine eigene Startseite
  `kMapIntro` („Die Karte“, `mapArt`) für den Start aus der
  Kurzanleitung — erst damit ist `tourSteps` etwas anderes als `steps`.
  `startWelcomeTour(ref)` ohne Router: Den braucht erst die Kette in
  PR 5. Die Tour startet nur, wenn die Maschine frei ist (`busy`).
- **Hinweis und Tour im selben Start** (Abweichung von PilzBuddy, dort
  liegt ein Start dazwischen — der Betreiber will „Hinweis vor der
  ersten Tour“, nicht „einen Start dazwischen“):

  ```dart
  var overlayShown = true;
  if (!ref.read(safetyNoteSeenProvider)) {
    ref.read(safetyNoteSeenProvider.notifier).set(true);
    await showSafetyNoteDialog(context);
    if (!mounted) return;
  }
  if (!ref.read(mapTourSeenProvider)) {
    startWelcomeTour(ref, GoRouter.of(context));
  } else {
    overlayShown = false;
  }
  // PR 6: unawaited(maybeShowHighlights(context, ref, mayShow: !overlayShown));
  ```

- Tests: erster Start (Startseite, „Tour starten“, der Reihe nach,
  dann nie wieder; „Nicht jetzt“ ist seit #417 ein Gesehen, beim
  nächsten Start kommt nichts; Zurück auf der Startseite heißt „Nicht
  jetzt“), Hinweis vor Tour im selben Start, beides gesehen ⇒ nichts.

### 3.4 Tour zum Zerlegen der ersten Fahrt (PR 4, Android)

- `lib/features/help/split_tour.dart`: `kSplitTourScript` (id `split`)
  mit Startseite „Deine erste Fahrt zerlegen“: bekannte Trails „wieder
  gefahren“, Kandidaten mit Griffen, Grad und Charakter, der
  Heimzonen-Hinweis, „Stück selbst wählen“, die Bewertung beim ersten
  Befahren eines Buddy-Trails (#127/#128), die Nachfrage zu
  unbestätigten Meldungen (#124), dann „beisteuern“. Ohne Wege ein
  Ersatzschritt „Erst einen Bereich speichern“. Alles über `requires`,
  weil jede Fahrt anders aussieht.
- Anker im Zerlege-Blatt je Zeile und Knopf; ein `SheetTourStarter`
  startet einmalig und NUR nach einer Aufzeichnung (Quelle des
  `SplitRequest`), nicht beim Import. Merker: `seenCoachTours` enthält
  `split`.
- Kurzanleitung: „Tour: Fahrt zerlegen“ (nur Android), öffnet die
  letzte Fahrt aus „Meine Fahrten“; ohne Fahrt deaktiviert mit
  Erklärung.
- Test `split_tour_flow_test` mit `FakeRideStore` und einer Fahrt
  (`ride_split_flow_test` als Vorlage; `sheetScrollTo` vor dem
  Kandidaten).
- **Gebaut (0.62.0), mit Abweichungen:** Die Tour startet im Blatt JEDER
  eigenen Aufzeichnung (`rideId`), also auch aus „Meine Fahrten", nicht
  nur direkt nach dem Beenden — beides ist „nach einer Aufzeichnung“.
  `SeenCoachTours` liegt in `seen_tours.dart` (PR 5 benutzt es mit).
  Beim Kandidaten sind nur die Griffe ausgespart, nicht die ganze Karte
  (zu hoch für 360×740). Damit `requires` Zeilen unter dem Rand sieht,
  baut die Liste während der Tour alles; die Maschine prüft beim
  Hinscrollen seither auch das Fenster der Liste (Abweichung von
  PilzBuddys `coach.dart`, im Dateikopf genannt).

### 3.5 Touren für Trails und Buddys mit Beispielen (PR 5)

- `lib/features/help/tab_tours.dart` nach PilzBuddy-Vorlage:
  Skripte, `kTabTours = [(trails, '/trails'), (buddys, '/friends')]`,
  `SeenCoachTours`, `RequestedTabTour`, `DeclinedTabTours` (nur im
  Speicher — in derselben Sitzung nicht bei jedem Reiterwechsel
  fragen), `startWelcomeTour` zieht hierher und bekommt die Kette
  („Weiter mit den Trails?“ / „Weiter mit den Buddys?“, Weiter/Später),
  `TabTourStarter` (nur sichtbar über `TickerMode`, nur wenn die
  Maschine frei ist, Karten-Tour und Hinweis gehen vor).
- `lib/features/help/tour_examples.dart`: `TourExampleBadge`
  („Beispiel“, auch als Semantics-Label), `ExampleTrailTile` (wie die
  echte Zeile: Streifen S1, „Beispiel: Buchenhang“, „1,8 km · 210 hm“,
  „MEIN“, Schild), `showExampleTrailSheet` (Kacheln, Höhenprofil,
  Einschätzung, „Mein Beitrag“, „Hinweis schreiben“ — alle Knöpfe ohne
  Wirkung, dieselben `sheet.*`-Anker), `ExampleBuddyTile` („Beispiel:
  Mira“, „3 gemeinsam“, Stift). Drei Regeln: **gezeichnet, nie
  gespeichert** (kein `Trail`-Objekt, kein Provider — ein Beispiel als
  Modell landete in Summe, Filter und Karte); **immer „Beispiel“**;
  **nur während der Tour und nur, wo Echtes fehlt**
  (`coachExamplesProvider`).
- Anker: `trails.list`, `trails.row` (erste Zeile), `trails.search`,
  `trails.sort`, `trails.chips`, `trails.import` (bekommt
  `key: trail-import-button`), Szene `trails.sheet`; `buddys.invite`
  (bekommt `key: invite-button`), `buddys.search`, `buddys.requests`,
  `buddys.row`, `buddys.alias`.
- Kurzanleitung: „Tour: Trails“, „Tour: Buddys“ über
  `requestedTabTourProvider`. Merker `seenCoachTours`
  (`seen_coach_tours`, Stringliste, sortiert geschrieben).
- **Keine Profil-Tour**: `kNavStep` nennt das Profil, die Kurzanleitung
  liegt dort, und PR 6 führt jede Profil-Funktion vor. Eine dritte
  Frage in der Kette verlängerte den ersten Start, ohne etwas zu
  zeigen, das man nicht erraten kann.
- **Gebaut (0.63.0), mit Abweichungen:** Anker `trails.row.own` (auf dem
  Streifen der Zeile, nur wenn der Trail mir gehört): Die Blatt-Anker
  „Einschätzung“ und „Mein Beitrag“ entstehen erst mit der Szene und
  können nicht in `requires` stehen — die Zeile trägt deshalb die
  Bedingung. Die Tour öffnet den ersten EIGENEN Trail, sonst den ersten.
  `trails.sort` ist gesetzt, der Schritt „Suchen und eingrenzen“ spart
  aber nur Suche und Chips aus (die Sortierung sitzt in derselben Zeile
  wie die Suche). Offene Anfragen an mich und von mir sind EIN Anker.
  Das Beispiel-Blatt zeigt Kacheln, Einschätzung, „Mein Beitrag“,
  „Hinweis schreiben“ und „Melden“, kein Höhenprofil.
- Tests: `tab_tours_flow_test` (erster Besuch; Beispiele ohne Daten,
  und nichts landet im Fake-Repository; mit echtem Trail kein
  Beispiel; ein verdeckter Reiter startet nichts; die Karten-Tour geht
  vor; Überspringen im Blatt lässt nichts offen; 360×740; Neustart aus
  der Kurzanleitung; jede Reiter-Tour steht in der Fake-Vorgabe), die
  Kette in `onboarding_flow_test`.

### 3.6 Entdecken, Neuheiten nach Updates, „Zeig es mir“ (PR 6)

- `lib/features/highlights/feature_highlights.dart`: Strukturkopie
  (`HighlightKind`, `HighlightTab` Karte/Trails/Buddys/Profil,
  `FeatureHighlight`, `kRecapLead`, höchstens drei Einträge im Blatt,
  `planHighlights` wörtlich; `isNewerVersion` gibt es in
  `update_check.dart`). Erste Einträge für Bestehendes, `since` aus
  `CHANGELOG.md` abgelesen: Karte `grade-colors`, `official-trails`,
  `pois`, `offline-areas`, `ride-record`, `my-position`; Trails
  `import-split`, `pick-section`, `trail-link`, `trail-notes`,
  `grade-votes`, `traits`, `visibility`, `planned` und die
  Rework-Einträge (`rating`, `condition`, `reports`); Buddys
  `buddy-alias`, `invite`, `connect-merge`; Profil `appearance`,
  `notifications`, `prerelease`. Je Eintrag: Highlight (ins Blatt nach
  dem Update) oder Tipp (nur in „Entdecken“).
- `highlight_sheet.dart` (Kopie; der Riegel „laufende Pilztour“ wird
  „laufende Fahrt“ — wer im Wald die App öffnet, will die Karte),
  `discover_screen.dart`, `highlight_art.dart` (echtes Symbol plus
  Serpentine), `highlight_demos.dart` (je Kennung eine Vorführung auf
  den Ankern aus PR 2 und 5, Ersatzschritte mit `unless`/`requires` —
  ohne Trail „Erst einen Trail importieren“ am Import-Symbol). Route
  `/profile/discover`.
- Profil: Zeile `discover` „Entdecken — Was TrailBuddy kann“ mit
  Neu-Punkt; Anker `profile.list` und `profile.<id>`. Kurzanleitung:
  „Funktionen und Tipps entdecken“. Karte: `maybeShowHighlights` nach
  Hinweis und Tour. Abmelden beendet eine laufende Tour.
- Merker `highlightsSeenVersion` (`highlights_seen_version`) und
  `seenHighlightIds` (`seen_highlight_ids`).
- PR-Template: „Visible feature? Entry in `kFeatureHighlights` plus its
  demo — or one sentence why not.“ Dieselbe Regel in `CLAUDE.md`. Die
  Vorschau der Neuheiten in der Run-Summary von `promote.yml`
  (PilzBuddys `tool/highlights_preview.py`) kam mit #152.
- Tests: `feature_highlights_test` (Kennungen einmalig, `since` ≤
  pubspec, Texte ≤ 3 Sätze, Ziel beginnt mit `/`, die
  `planHighlights`-Fälle), `feature_highlights_flow_test` (Bestand
  ohne Merker: Rückblick einmal; frische Installation: nie; Overlay
  offen: das Blatt wartet; nach Update „Neu in TrailBuddy“; Neu-Punkt),
  `highlight_demos_flow_test` (JEDE Vorführung: mindestens ein
  Schritt, jedes Ziel gefunden, Blase im Bild, danach nichts offen;
  360×740).
- **Gebaut abweichend** (0.64.0): Die Einträge sind 13 Highlights und
  13 Tipps. `condition` steht nicht allein, sondern in `reports` — Meldung
  und Zustand sind ein Dialog, zwei Einträge führten zum selben Knopf.
  Dazu kamen, was seit dem Plan gebaut wurde: `still-valid` (0.58.0),
  `marks` (0.57.0), `takeover` (0.55.0), `kurzanleitung` (0.59.0) und
  `tours` (0.63.0). **`prerelease` fehlt mit Absicht**: Der Schalter
  steht nur im GitHub-Build (`updateChecksApply`), ein Eintrag, den im
  Web und im Play-Build niemand findet, wäre ein Versprechen, das nicht
  hält. Das Bild steht still (kein Pilz-Buddy, der schaukeln könnte;
  zwanzig bewegte Bilder in einer Liste wären Unruhe). Neue Anker für die
  Vorführungen: `profile.list`/`profile.<id>`, `help.list`/`help.tabTours`
  und `sheet.report` am Melde-Knopf des Blatts.

## 4. Die Skripte

Schritttitel dürfen nicht lauten wie etwas auf dem Schirm (ein Test
fände sonst das Element statt der Blase): also nicht „Ebenen und Orte“,
nicht „Meine Position“, nicht „Mein Beitrag“, nicht „Buddy finden“.
Texte folgen `konzept-trails.md`: Trail ≠ Fahrt ≠ Aufzeichnung;
sichtbar = eigene Beiträge + direkte Buddys; nichts wird über Netze
hinweg gerechnet; Fahrt und Position verlassen das Gerät nie.

### 4.1 Karten-Tour (`map`, Endlink „Kurzanleitung“)

| # | Titel | Kern des Textes | ausgespart / Ring | Szene, Geste, Bedingung |
|---|---|---|---|---|
| 0 | **Willkommen bei TrailBuddy** (Startseite, ab PR 3) | Hier liegen die Trails, die du gefahren bist, und die deiner Buddys — sonst niemandes. Drei Wege bringen Trails hierher: GPX importieren, eine Fahrt aufzeichnen, Buddys verbinden. | — | `welcomeArt` |
| 1 | **Das Schild am Anfang** | Am Anfang jedes Trails steht sein Schild mit Grad und Charakter. Ein Tipp darauf — oder auf die Linie — öffnet das Blatt. | Schild | Tippen; nur mit Trail |
| 2 | **Das Blatt zum Trail** | Länge, Höhenmeter und die Schwierigkeit, wie dein Netz sie sieht — ein Tipp auf den Grad zeigt, wer wie eingeschätzt hat. | Kachelzeile | Szene Trail-Blatt; nur mit Trail |
| 3 | **Farbe heißt Schwierigkeit** | Jede Linie trägt die Schwierigkeit ihres Trails wie eine Piste: grün S0, blau S1, rot S2, schwarz ab S3. Wie die Linie gezeichnet ist, sagt den Zustand — durchgezogen gepflegt, gestrichelt abgerockt. Ein orangener Saum: ein Buddy hat etwas gemeldet; ein gelber: ein neuer Hinweis. Magenta ist Uphill, Violett gestrichelt ein offizieller Trail. | die Legende auf der Karte (seit 0.77.0, #182; vorher nichts) | die aufgeklappte Legende (vorher Mini-Legende in der Blase) |
| 4 | **Was die Karte zeigt** (seit 0.75.0, #190; vorher „Hinter dem Ebenen-Knopf") | Der oberste Knopf: welche Trails die Karte zeigt, die offiziellen Trails der Region und Orte wie Einkehr, Wasser und Rad-Service. | Knopfspalte / Kartenebenen | — |
| 5 | **Orte und offizielle Trails wählen** | Offizielle Trails an oder aus, Orte nach Gruppe. Was hier aus ist, bleibt aus, bis du es wieder einschaltest. | Schalter und Gruppen | Szene Blatt „Kartenebenen" |
| 6 | **Karten ohne Empfang** | Der Knopf darunter holt die Karte aufs Gerät — für unterwegs, wo kein Netz ist. | Knopfspalte / Offline-Karten | — |
| 7 | **Die Werkzeugleiste** | Hier zeichnest du einen Bereich, den die App für unterwegs speichert, oder nimmst einen weg; „Meine Bereiche“ verwaltet sie. | Leiste / Stift | Szene Leiste |
| 8 | **Zu dir und zu uns** | Der Positionsknopf holt die Karte zu dir — dein Standort verlässt das Gerät nie. Oben rechts die Glühbirne: Idee oder Fehler melden, das wird ein öffentlicher Eintrag auf GitHub. | Knopfspalte und Glühbirne / Position, Glühbirne | — |
| 9 | **Eine Fahrt aufzeichnen** | Der große Knopf zeichnet eine Fahrt auf — Haustür bis Haustür, nur auf deinem Gerät, auch ohne Empfang. Danach zerlegst du sie in Trails; erst die kommen zu deinen Buddys. | Knopfspalte / Aufnahme | nur Android |
| 10 | **Unten die Bereiche** | Trails: alle als Liste, suchen und filtern. Buddys: wer deine Trails sieht — und du ihre. Profil: Import, Fahrten, Bereiche und die Kurzanleitung. | Leiste unten / drei Reiter | — |

Für ein leeres Konto fallen 1 und 2 still weg; der Zähler zählt nur,
was kommt.

### 4.2 Trails-Tour (`trails`, mit Beispielen)

| # | Titel | Kern des Textes | ausgespart | Szene, Bedingung |
|---|---|---|---|---|
| 0 | **Deine Trails** (Startseite) | Alle Trails deines Netzes als Liste: was du gefahren bist und was Buddys beisteuern. Hier findest du einen Trail schneller als auf der Karte. | — | `trailsArt` |
| 1 | **Eine Zeile lesen** | Streifen und Schild tragen die Schwierigkeit; das Wort sagt, wessen Trail es ist — MEIN oder die Namen deiner Buddys. Ein Tipp öffnet das Blatt. | erste Zeile | Tippen |
| 2 | **Zahlen und Profil** | Länge, Höhenmeter, Grad und das Höhenprofil. Ein Tipp auf den Grad zeigt alle Einschätzungen — und was S0 bis S5 bedeuten. | Kachelzeile | Szene Blatt |
| 3 | **Deine Einschätzung** | Deinen eigenen S-Grad tippst du hier an. Angezeigt wird, was dein Netz sagt — nicht nur du. | Einschätzung | Szene Blatt; nur eigener Trail oder Beispiel |
| 4 | **Was du beisteuerst** | Name, Charakter, Meldung, Zustand, Bewertung, Sichtbarkeit, Beschreibung und Link — dein Beitrag zum Trail. „Nur für mich“ hält ihn vor Buddys verborgen. | „Mein Beitrag“ | Szene Blatt; Wortlaut nach #118 |
| 5 | **Etwas Aktuelles erzählen** | Ein Hinweis meldet, was gerade ist: umgestürzter Baum, neue Sprünge. Buddys sehen ihn mit gelbem Saum, bis sie ihn gelesen haben. | „Hinweis schreiben“ | Szene Blatt |
| 6 | **Suchen und eingrenzen** | Gesucht wird über Name und Buddy; die Chips zeigen nur Meine oder Von Buddys, leichte, frische oder gemeldete Trails. Die Sortierung daneben. | Suche, Sortierung, Chips | — |
| 7 | **GPX hereinholen** | Das Symbol oben rechts liest GPX- oder Zip-Dateien aus anderen Apps. Kurz und bergab wird ein Trail, eine ganze Runde eine Fahrt — die zerlegst du dann in Trails. | Import-Symbol | — |

### 4.3 Buddys-Tour (`buddys`, mit Beispielen)

| # | Titel | Kern des Textes | ausgespart | Bedingung |
|---|---|---|---|---|
| 0 | **Deine Buddys** (Startseite) | Wer deine Trails sieht — und du seine. Nur direkte Buddys, nichts darüber hinaus; eine öffentliche Karte gibt es nicht. | — | `buddysArt` (zwei Spuren werden eine, Motiv 1s) |
| 1 | **Jemanden einladen** | Schickt einen Link zu TrailBuddy über deine Messenger-App — mit deinem Benutzernamen, damit man dich gleich findet. | Einladen-Symbol | — |
| 2 | **Nach Buddys suchen** | Gefunden wird über den Benutzernamen oder die genaue E-Mail-Adresse. Trails seht ihr voneinander erst, wenn die Anfrage angenommen ist. | Suchfeld | — |
| 3 | **Offene Anfragen** | Anfragen an dich stehen hier mit Annehmen und Ablehnen; gesendete lassen sich zurückziehen. | Abschnitt Anfragen | nur mit Anfragen |
| 4 | **Ein Buddy in der Liste** | „n gemeinsam“ zählt Trails, die ihr beide kennt. Der Stift gibt dem Buddy einen Namen, den nur du siehst. | erste Zeile / Stift | nur mit Buddy oder Beispiel |
| 5 | **Beim Verbinden** | Verbindet ihr euch, werden gleiche Trails EIN Trail mit zwei Namen, der Rest kommt dazu. Trennt ihr euch, verschwinden seine Trails wieder von deiner Karte. | nichts | — |

### 4.4 Zerlege-Tour (`split`, Android)

Startseite „Deine erste Fahrt zerlegen“, dann je nach Fahrt: „Wieder
gefahren“ (bekannte Trails), „Ein Kandidat“ (Griffe, Grad, Charakter,
Heimzone), „Stück selbst wählen“, „Jetzt deiner“ (die Bewertung, mit
der ein Buddy-Trail beim ersten Befahren zum eigenen wird, #127), „Gilt
das noch?“ (die Nachfrage zu unbestätigten Meldungen, #124), „Was zu
Buddys geht“ (nur die gewählten Stücke, nie die Fahrt). Ohne Wege der
Ersatzschritt „Erst einen Bereich speichern“. Genauer Wortlaut beim
Bau, am Blatt, wie es dann aussieht.

## 5. Merker (alle gerätelokal, im `Settings`-Muster)

| Getter | Schlüssel | Typ | Fake-Vorgabe | PR |
|---|---|---|---|---|
| `safetyNoteSeen` | `safety_note_seen` | bool | `true` | 1 |
| `mapTourSeen` | `map_tour_seen` | bool | `true` | 2 |
| `seenCoachTours` | `seen_coach_tours` | Stringliste (`trails`, `buddys`, `split`) | alle | 4/5 |
| `highlightsSeenVersion` | `highlights_seen_version` | String | `9999.0.0` | 6 |
| `seenHighlightIds` | `seen_highlight_ids` | Stringliste | leer | 6 |

- **Ohne Suffix starten.** PilzBuddys `_2`/`_3` sind die Narben zweier
  Resets. Die Konvention steht in `CLAUDE.md`: Sollen alle die Tour
  noch einmal sehen, bekommt der Schlüssel `_2`; der alte wird weiter
  GELESEN (`legacyMapTourSeen`), damit `planHighlights` einen
  Bestandsnutzer nicht für eine Neuinstallation hält; ein
  `settings_tour_reset_test` kommt dann mit.
- **Die Fake-Vorgabe ist „alles gesehen“.** Jeder Flow-Test pumpt die
  App auf die Karte; mit `false` läge über jedem der Dialog oder die
  Startseite, und der erste Tipp träfe die Überlagerung (PilzBuddy hat
  13 Brüche gemessen; hier wären es praktisch alle). Tests für Hinweis,
  Tour und Blatt geben ihre `FakeSettings` ausdrücklich mit. Gegenprobe
  je PR: Vorgabe einmal drehen, Brüche zählen, Zahl in die
  Technik-Notiz.
- Nach einer Neuinstallation läuft die Tour wieder; meldet sich ein
  anderer Nutzer auf demselben Gerät an, nicht — beides angenommen.

## 6. Aussehen (`docs/design/README.md`, neuer Abschnitt 12)

- **Abdunkelung** Schwarz mit 65 %, Aussparung in der Form des
  Elements, 2 px Luft, Radius 12. Kein Vergrößern — der Fehler der
  ersten PilzBuddy-Tour, die runde Löcher je Knopf schnitt, die in den
  Nachbarn griffen.
- **Ring = Marke**: außen Weiß 90 % 5 px, innen Lime 3 px, pulsiert
  3 → 7 px in 1,8 s. Der Ring heißt „hier, für dich“ und ist nie eine
  Bedeutungsfarbe der Karte. Lime kollidiert nicht: S0 ist ein anderes
  Grün, und „mein“ ist seit 0.42.0 ein Wort, keine Farbe. Orange
  (Meldung), Gelb (Hinweis), Magenta (Uphill), Violett (offiziell), Blau
  (S1) bleiben den Linien.
- **Hand** gezeichnet, Ärmel und Punkt in der Marke, Kontur schwarz;
  heran, drücken, abheben (Wischen: rechts nach links), Keyframes pur.
- **Blase** auf `surface` mit Rand `line`, Radius 12, Pfeil zum Ziel;
  Titel Barlow Condensed, Text `bodyMedium`, Zähler „2 von 7“ in
  JetBrains Mono; „Überspringen“ als Text, „Weiter“/„Los geht's“
  gefüllt in Lime. Erst messen, dann setzen: neben ein hohes schmales
  Ziel, ins Bild geschoben ohne Pfeil, wenn es sein muss.
- **Startseite**: Karte mit Bild 240 × 150 auf `ground`, Titel
  `headlineSmall`, zwei Sätze, die Wahl „Nicht jetzt“ / „Zeig's mir“
  (in der Kette „Später“ / „Weiter“). Bilder aus der Serpentine und
  den Pistenfarben — kein Foto, kein Lottie, keine Emojis.
- **Beispiel-Schild** „Beispiel“ auf `tertiaryContainer` an Zeile und
  Blatt, auch für den Bildschirmleser.
- **Reduzierte Bewegung**: Ring steht, Hand steht in der
  Druckstellung, das Startseiten-Bild steht mit dem Punkt am Ziel.
  Während einer Tour blendet die Maschine alles darunter für TalkBack
  aus; die Blase ist eine Live-Region.
- Abschnitt 9 (Bewegung) bekommt die Zeilen 1u Ring, 1v Hand, 1w
  Startseiten-Bild; Abschnitt 8 (Screens) Kurzanleitung, „Entdecken“
  und das Neuheiten-Blatt; Abschnitt 11 die Zeilen je PR.

## 7. Prüfung je Stufe

Immer: `flutter analyze`, `flutter test`, `tool/private_info_check.py`
nach `git add`; `changelog_test` und `privacy_policy_test` grün; die
Gegenprobe im PR-Text.

- **PR 1**: die drei neuen Tests, `profile_screen_test` mit der Zeile
  „Kurzanleitung“. Von Hand auf Android und in der PWA: Dialog nicht
  wegtippbar, „Verstanden“ merkt; Kurzanleitung auf 360 × 740 ohne
  Überlauf; jeder Leerzustand führt zur Kurzanleitung.
- **PR 2**: `coach_test`, `map_tour_flow_test`. Von Hand: Tour aus der
  Kurzanleitung auf Android (die MapLibre-Platform-View wird
  abgedunkelt, der Schild-Anker sitzt) und in der PWA (Schritt 8
  fehlt, der Zähler stimmt); Zurück beendet die Tour und ist danach
  wieder normal; Leiste und Filter-Blatt gehen auf und zu;
  „Animationen entfernen“ bzw. `prefers-reduced-motion`; TalkBack:
  nur die Blase ist fokussierbar, ein neuer Schritt wird angesagt.
- **PR 3**: erster Start nach gelöschten App-Daten: Splash → Hinweis →
  Willkommen → Tour; „Nicht jetzt“ fragt seit #417 nicht wieder.
- **PR 4**: Aufzeichnung beenden → Blatt → Tour einmalig; die Schere im
  Import startet sie nicht.
- **PR 5**: ein leeres Konto sieht die Beispiele nur während der Tour
  und nirgends danach (Liste, Karte, Summe, Filter).
- **PR 6**: Update aus dem Vorab-Kanal zeigt „Neu in TrailBuddy“, eine
  frische Installation nichts; jede Vorführung endet in der Funktion
  und lässt nichts offen.

## 8. Was TrailBuddy anders macht als PilzBuddy

Zum Nachschlagen, wenn jemand die beiden Kopien vergleicht:

| Thema | PilzBuddy | TrailBuddy | Warum |
|---|---|---|---|
| Erste Tour | erklärt die Karte und ihre Ebenen | erklärt die drei Wege zu Trails, dann die Karte | die Karte ist am Anfang leer |
| Hinweis und Tour | Hinweis beim ersten, Tour beim zweiten Start | beides im selben Start | Betreiber: Hinweis VOR der ersten Tour, kein Start dazwischen |
| Rückkehrer-Startseite | ja (Merker-Resets) | nein | kein Altschlüssel-Erbe |
| Touren je Reiter | Spots, Pilze, Buddys | Trails, Buddys — und eine im Zerlege-Blatt | das Blatt ist der Moment, in dem man Hilfe braucht; das Profil erklärt sich selbst |
| Blase | Text | Text plus optionale Illustration | Trail-Linien sind keine Widgets |
| Ringfarbe | Waldgrün | Lime (Marke) | Grün hieße hier S0 |
| Merker-Schlüssel | mit Suffix `_3` | ohne Suffix | noch kein Reset; Konvention dokumentiert |
| Routen | `/profile/anleitung`, `/profile/entdecken` | `/profile/help`, `/profile/discover` | die Routen sind hier englisch |

## 9. Offene Punkte für den Betreiber (Empfehlung in Klammern)

1. Wortlaut des Sicherheitshinweises in 3.1 — Auskunft, kein
   Haftungsausschluss — (bestätigen).
2. Hinweis und Tour im selben Start — (ja).
3. Alle heutigen Tester sehen die Tour nach PR 3 einmal — (ja,
   gewollt).
4. ~~Schon jetzt „Meldung“ in der Kurzanleitung, bevor #118 gemergt
   ist~~ — erledigt, #118 ist gemergt; der Test hält Beschriftung und
   Text weiter zusammen.
5. Zerlege-Tour (PR 4) — oder reicht die Vorführung `import-split` aus
   PR 6? — (eigene Tour).
6. PR 2 als ein PR mit ~1500 Zeilen Kopie, Review per Diff gegen
   PilzBuddy — oder Maschine allein mit dem Changelog-Satz „Grundlage
   für die Touren“? — (ein PR).
7. Folge-Issue für die Neuheiten-Vorschau in der Run-Summary von
   `promote.yml` — (ja, später).
