# TrailBuddy — Arbeitsregeln für `lib/features/highlights/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Neuheiten, „Entdecken" und „Zeig es mir"** (#135, seit 0.64.0, Plan
  `docs/konzept-onboarding.md` 3.6; Vorlage PilzBuddy #596,
  `lib/features/highlights/`). EINE Liste (`kFeatureHighlights`), zwei
  Anzeigen: das Blatt nach einem Update (höchstens drei Highlights, die
  jüngsten zuerst; Tipps nie) und die Seite „Entdecken" (`/profile/discover`,
  alles, gruppiert nach Reiter). Sieben Dinge, die man wissen muss:
  - **Wer eine Funktion baut, bringt ihren Eintrag im selben PR mit** —
    Highlight, wenn sie ins Blatt gehört, sonst Tipp — UND ihre
    Vorführung in `highlight_demos.dart`, oder einen Satz im PR, warum
    nicht (erster Haken der PR-Vorlage). `highlight_demos_flow_test`
    verlangt eine Vorführung je Kennung und fährt JEDE aus „Entdecken"
    durch (Ziel gefunden, Blase im Bild, danach nichts offen, auch auf
    360×740); `feature_highlights_test` prüft Kennungen, `since` gegen
    `pubspec.yaml` und die Textlänge.
  - **`planHighlights` ist wörtlich PilzBuddys**, der Rückblick hängt
    deshalb an `mapTourSeen`: Vor 0.64.0 hat kein Gerät seine Version
    gemerkt. Tour gesehen ⇒ Bestandsnutzer ⇒ einmal „Das kann TrailBuddy
    inzwischen" mit `kRecapLead` vorn; nicht gesehen ⇒ frisch ⇒ nur
    merken, die Tour erklärt. **Gemerkt wird schon beim ersten Start**,
    auch wenn Hinweis oder Tour laufen — sonst hielte sich eine frische
    Installation nach der Tour für einen Bestandsnutzer.
  - **Nur ZEIGEN wartet** (`maybeShowHighlights(mayShow:)` am Ende von
    `_firstStart`): nicht, wenn in diesem Start der Hinweis oder die Tour
    kam, nicht während einer Fahrt (wer im Wald die App öffnet, will die
    Karte), nicht bei belegter Maschine. Nicht gezeigt heißt dann auch
    nicht gemerkt — das Blatt kommt beim nächsten ruhigen Start.
  - **Gemerkt wird VOR dem Zeigen**, nie ein älterer Stand über einen
    jüngeren (Rückschritt vom Vorabkanal). Ein weggewischtes Blatt kommt
    nicht wieder; „Entdecken" hat alles. Das Blatt ist EINE Seite, alle
    Einträge untereinander (PilzBuddy 1.204.1: blättern verlor den Rest).
  - **Eine Zeile im Blatt FÜHRT VOR** (`startHighlightDemo`), ohne
    Vorführung springt sie zum Ziel. Die Vorführungen übernehmen Schritte
    der Touren über ihren Titel (`_from`), statt sie abzuschreiben —
    ändert sich ein Tour-Text, zieht die Vorführung mit. Ersatzschritte
    mit `requires`/`unless` für das, was nicht jeder hat (kein Trail,
    kein eigener Trail, kein Buddy, Web ohne Aufzeichnung); genau einer
    läuft. Neu dafür: Anker `ProfileCoach.list`/`ProfileCoach.row(id)`
    (jede Profilzeile), `HelpCoach.*`, `SheetCoach.report`.
  - **Der Neu-Punkt ist gerätelokal** (`seenHighlightIds`,
    `seen_highlight_ids`) — eine Tabelle wäre eine Lesequittung. Gesetzt
    beim Öffnen von „Entdecken" (die Seite zeigt „Neu" noch in DIESEM
    Besuch) und für die Einträge, die das Blatt gezeigt hat. Die Zahl
    steht an der Profilzeile `discover`.
  - **Die Bilder stehen still** (`highlight_art.dart`: das echte Symbol
    auf einer Scheibe, die Serpentine daneben) — zwanzig bewegte Bilder
    in einer Liste wären Unruhe, und es gibt keinen Pilz-Buddy, der
    schaukeln könnte. Abmelden beendet eine laufende Tour oder Vorführung.
  Merker `highlightsSeenVersion` (`highlights_seen_version`, ohne Suffix,
  Reset-Konvention wie beim Hinweis). `FakeSettings.highlightsSeenVersion`
  steht auf `9999.0.0`, die App auf `null` — andersherum läge das Blatt
  über jedem Flow-Test; in der Gegenprobe (Vorgabe `null`) brechen
  50 Tests. **Die Run-Summary von `promote.yml` zeigt, was das Blatt
  bringt** (#152, `tool/highlights_preview.py`, PilzBuddy-Port): gelesen
  aus dem BEFÖRDERTEN Tag, gezählt ab dem letzten stabilen Stand, kein
  Tor. Anders als in PilzBuddy zwei Grenzen: Wer von einem Stand vor
  0.60.0 kommt (`TOUR_SINCE`), hat die Tour nie gesehen und bekommt die
  Willkommens-Tour statt eines Blatts; bis vor 0.64.0
  (`MEMORY_SINCE`) den Rückblick; erst danach ist „kein Highlight" eine
  Warnung. Wird ein Merker zurückgesetzt, ziehen die Konstanten mit.
  Der Selbsttest prüft auch die Verdrahtung in `promote.yml` — dort
  statt in `test/`, damit ein Werkzeug-PR keinen Bump braucht.
