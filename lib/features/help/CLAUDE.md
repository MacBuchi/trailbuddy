# TrailBuddy — Arbeitsregeln für `lib/features/help/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Einführung: Kurzanleitung, Sicherheitshinweis, Kontexthilfe**
  (#131, seit 0.59.0, Plan `docs/konzept-onboarding.md` 3.1; Vorlage
  PilzBuddy #350 Baustein A). `lib/features/help/help_screen.dart`
  (Route `/profile/help`, Zeile „Kurzanleitung" im Profil) und
  `lib/core/widgets/safety_note.dart`. Sechs Dinge, die man wissen muss:
  - **Die Anleitung sind Widgets, kein `.md`-Asset**: nur so zeigt sie
    die ECHTEN Symbole (das Schild ist `GradeShield`), und ein Asset unter
    `assets/` wäre für den Version Guard `*.md`, also bump-frei, obwohl es
    im Binary liegt. Keine `web/anleitung.html` (Betreiber: zwei Stellen,
    und die PWA IST die App).
  - **Sechs Abschnitte sind die Obergrenze**, offen als `kHelpSteps`,
    damit `test/help_texts_test.dart` einen EINZELNEN Abschnitt prüft.
    „Die Karte lesen" beschreibt die Regeln aus `docs/design/README.md`
    Abschnitt 2 (Farbe = Schwierigkeit, Linienart = Zustand, S4/S5 auf dem
    Saum) — ändert sich dort etwas, zieht der Satz im selben PR mit.
  - **„Meldung" ist eine Konstante** (`kReportFieldLabel` in
    `trail_report.dart`, die Beschriftung im Melde-Dialog) und steht so im
    Text; der Test verbietet zusätzlich das alte „Status". Abweichung vom
    Plan, der sie in `trail_details_dialog.dart` vermutete: Die Meldung
    ist seit 0.49.0 nicht mehr im Beitrag, sondern im Melde-Dialog.
  - **Der Hinweis steht an EINER Stelle** (`kSafetyNote`): Dialog beim
    ersten Start, Kachel oben in der Kurzanleitung, Zeile unter „Über
    TrailBuddy" (über `showInfoText`). Der Dialog ist weder wegtippbar noch
    mit Zurück zu schließen (`PopScope`); gezeigt aus dem Post-Frame von
    `MapScreen` (`_firstStart`), also nur angemeldet und nie hinter der
    Update-Sperre. Gemerkt wird VOR dem Zeigen.
  - **Merker `safetyNoteSeen` (`safety_note_seen`) ohne Suffix.** Sollen
    alle ihn noch einmal sehen, bekommt der Schlüssel `_2`, der alte wird
    weiter GELESEN (wie PilzBuddys `legacyMapTourSeen`), und ein
    `settings_tour_reset_test` kommt mit. Dieselbe Regel gilt für die
    Merker der Touren (ab #132).
  - **`FakeSettings.safetyNoteSeen` steht auf `true`, die App auf
    `false`.** Andersherum läge über jedem Flow-Test der Dialog — in der
    Gegenprobe gemessen: 169 Tests brechen. Tests für den
    Hinweis geben ihre `FakeSettings` ausdrücklich mit.
  Die Leerzustände von Karte (die Karte selbst ist tippbar), Trails,
  Buddys und „Meine Fahrten" führen in die Kurzanleitung
  (`HelpLinkButton`, `push` — Zurück führt dahin, wo man herkam).
- **Die Karten-Tour beim ersten Start** (#133, seit 0.61.0, Plan
  `docs/konzept-onboarding.md` 3.3). Beim ersten Start liegt über der
  Karte erst der Sicherheitshinweis, dann — im SELBEN Start — die
  Willkommensseite (`kWelcomeIntro`, Bild `welcomeArt`) mit der
  Karten-Tour dahinter (`kWelcomeTourScript`, `startWelcomeTour`). Aus der
  Kurzanleitung beginnt dieselbe Tour mit ihrer eigenen Startseite „Die
  Karte" (`kMapIntro`, Bild `mapArt`). Fünf Dinge, die man wissen muss:
  - **Hinweis und Tour im selben Start** — Abweichung von PilzBuddy (dort
    liegt ein Start dazwischen); der Betreiber will „Hinweis vor der
    ersten Tour". Der Auslöser ist `_firstStart` im Post-Frame von
    `MapScreen`: erst `await showSafetyNoteDialog`, dann die Tour, und die
    nur, wenn die Maschine frei ist (`busy`).
  - **„Nicht jetzt" ist kein Gesehen**: Die Startseite fragt beim
    nächsten Start wieder, jedes Mal; Zurück auf der Startseite heißt
    „Nicht jetzt", ein Tipp daneben tut nichts. Gemerkt wird erst am Ende
    (durchgesehen ODER übersprungen).
  - **Die Willkommens-Tour hat keinen Weg in die Kurzanleitung am Ende**
    — ab #136 hängt `startWelcomeTour` die Reiter-Touren an, die Kette
    liefe sonst gleichzeitig in die Kurzanleitung.
  - **Keine Rückkehrer-Startseite** (anders als PilzBuddy): TrailBuddy hat
    noch keinen Merker-Reset. Kommt einer (`map_tour_seen_2`), braucht es
    PilzBuddys `legacyMapTourSeen` und `kReturningIntro`.
  - **Die Bilder sind gezeichnet** (`tour_intro_art.dart`): das Logo
    (`LogoGeometry`, Größe L) auf dem Grund des Modus, ein Punkt fährt
    die Mittellinie ab (`pointAt`)
    (`introDriftAt`, rein und ohne Pixel geprüft); ohne Takt
    (`TickerMode` aus bei „Animationen entfernen") steht das Endbild —
    der Punkt am Ziel, nicht am Start. `mapArt` steht still auf dem
    Landton der Karte, mit den Pistenfarben und dem echten `GradeShield`.
  `FakeSettings.mapTourSeen` steht auf `true`; in der Gegenprobe (Vorgabe
  `false`) brechen 180 Tests. Tests für die Tour setzen den Merker
  ausdrücklich (`map_tour_flow_test` setzt ihn NACH dem Start zurück,
  sonst liefe die Willkommens-Tour vor der aus der Kurzanleitung).
- **Die Tour im Zerlege-Blatt** (#134, seit 0.62.0, Plan
  `docs/konzept-onboarding.md` 3.4/4.4; `lib/features/help/split_tour.dart`,
  Merker `seen_tours.dart`). Sechs Dinge, die man wissen muss:
  - **Nur im Blatt einer eigenen Aufzeichnung** (`SplitRequest.rideId`,
    also nach dem Beenden ODER aus „Meine Fahrten"), nie aus dem
    GPX-Import; einmal (`seenCoachTours` enthält `split`), „Nicht jetzt"
    fragt beim nächsten Blatt wieder. Erwogen wird sie EINMAL je Blatt,
    sobald die Zerlegung steht (`_considerTour`), und nur, wenn die
    Maschine frei ist.
  - **Jede Fahrt sieht anders aus**: Fast jeder Schritt hängt an
    `requires` (bekannte Zeile, Übernahme, Nachfrage, Kandidat, Heimzone,
    „Wege unbekannt", „Stück selbst wählen"). Die Anker sitzen nur an der
    ERSTEN Zeile ihrer Art (`_anchorIf`).
  - **Während dieser Tour baut die faule Liste ALLES**
    (`scrollCacheExtent`, nur solange `split` läuft): Sonst gäbe es die
    Zeilen unter dem Rand nicht, `requires` hielte sie für fehlend, und
    der Schritt fiele still weg.
  - **Die Maschine prüft seither auch das Fenster der Liste**
    (`_revealOffscreen` in `coach.dart`, Abweichung von PilzBuddy): Die
    Liste endet über festen Knöpfen, eine Zeile knapp darunter lag im
    Bild, aber verdeckt, und wurde nie hergescrollt. Ebenso `minRoom`
    260 statt 240 (größerer Titel). PilzBuddy hat denselben Fehler in
    Blättern mit festen Knöpfen — beim nächsten Anfassen dort mitziehen.
  - **Beim Kandidaten nur die Griffe aussparen**, nicht die Karte: Mit
    Grad und Charakter ist sie so hoch, dass auf 360×740 keine Blase mehr
    daneben passt.
  - **Aus der Kurzanleitung** (nur Android): „Tour: Fahrt zerlegen"
    bestellt die Tour (`requestedSplitTourProvider`, läuft auch, wenn sie
    gesehen ist) und öffnet die jüngste Fahrt über denselben Weg wie
    „Meine Fahrten"; ohne Fahrt ist der Knopf aus und sagt, warum.
  Merker `seenCoachTours` (`seen_coach_tours`, Stringliste, sortiert
  geschrieben, ohne Suffix); `FakeSettings` setzt ab Werk alle Touren
  (`split`, `trails`, `buddys`). Gegenprobe siehe nächster Abschnitt.
- **Touren je Reiter, Kette und Beispiele** (#136, seit 0.63.0, Plan
  `docs/konzept-onboarding.md` 3.5/4.2/4.3; `lib/features/help/tab_tours.dart`,
  `tour_examples.dart`). Trails und Buddys bekommen je eine kurze Tour
  beim ersten Besuch; keine Profil-Tour (Plan 3.5). Sieben Dinge, die man
  wissen muss:
  - **Nur wenn der Reiter SICHTBAR ist** (`TabTourStarter`, `TickerMode`,
    den go_router für verdeckte Reiter abschaltet) und die Maschine frei;
    Karten-Tour und Hinweis gehen vor. Eine bestellte Tour
    (`requestedTabTourProvider`, aus der Kurzanleitung) wartet ebenfalls,
    bis ihr Reiter zu sehen ist — Flow-Test mit Gegenprobe.
  - **Die Kette** hängt `startWelcomeTour(ref, router)` (seit #136 in
    `tab_tours.dart`) an die Karten-Tour: an jeder Grenze eine Startseite
    als Frage („Weiter mit den Trails?", „Später"/„Weiter"). „Später"
    beendet die Kette und ist kein Gesehen; in derselben Sitzung fragt der
    Reiter dann nicht wieder (`declinedTabToursProvider`, nur im Speicher).
  - **Beispiele: gezeichnet, nie gespeichert** — `ExampleTrailTile`,
    `showExampleTrailSheet`, `ExampleBuddyTile` sind Widgets aus festen
    Texten, kein `Trail`, keine `Friendship`, kein Provider. Immer
    „Beispiel" (Schild UND Name), nur während einer Tour mit `examples`
    (`coachExamplesProvider`) und nur, wo Echtes fehlt. Der Flow-Test
    prüft, dass danach nichts im Fake liegt und keine Summe erscheint.
  - **Dieselben Anker wie das Echte**: `trails.row` sitzt auf der Zeile
    des Trails, dessen Blatt die Tour öffnet (der erste EIGENE, sonst der
    erste), `trails.row.own` auf ihrem Streifen, nur wenn er mir gehört —
    daran hängen „Deine Einschätzung" und „Was du beisteuerst", die im
    Blatt eines Buddy-Trails fehlen. Die Blatt-Anker (`sheet.*`) teilt
    die Trails-Tour mit der Karten-Tour.
  - **Szene `trails.sheet`** meldet `TrailsScreen` an: das echte Blatt oder
    das Beispiel-Blatt. Die offenen Anfragen (an mich UND von mir) sind
    EIN Anker (`buddys.requests`), der Schritt fällt ohne sie weg.
  - **Beispiele nur an Skripten MIT Startseite**: Sie erscheinen ein Bild
    nach dem Start, und ein erster Schritt mit `requires` fiele sonst
    sofort weg (PilzBuddy-Regel, Test).
  - **`FakeSettings.seenCoachTours` enthält alle Touren**; in der
    Gegenprobe (leer) brechen 87 Tests.
