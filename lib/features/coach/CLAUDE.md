# TrailBuddy — Arbeitsregeln für `lib/features/coach/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Die Hinweis-Maschine und die Karten-Tour** (#132, seit 0.60.0, Plan
  `docs/konzept-onboarding.md` 3.2/4.1; Vorlage PilzBuddy #596).
  `lib/features/coach/coach.dart` ist eine WÖRTLICHE Kopie von PilzBuddys
  Datei (Stand 0d2a533); das Review ist ein `diff` gegen sie, der nur die
  Anpassungen im Kopfkommentar zeigt (Marke statt Waldgrün, Blase auf
  `surface`/`line`, Zähler in Mono, `reduceMotion`, Hand-Kontur `onBrand`)
  plus EINE Erweiterung: `CoachStep.illustration`. Die Tour steht in
  `lib/features/help/map_tour.dart` (`kMapTourScript`, zehn Schritte;
  beim ersten Start siehe nächster Abschnitt). Sieben
  Dinge, die man wissen muss:
  - **Die Maschine liegt über allem, aber UNTER dem Splash**
    (`app.dart`: `StartSplash` → `Stack[CoachSemanticsGate(…), CoachOverlay]`).
    Sie schluckt jeden Tipp und meldet sich, solange sie läuft, beim
    Zurück-Verteiler des Routers mit Vorrang an — danach wieder ab (beide
    Richtungen im Flow-Test).
  - **Anker haben Kennungen, eine Stelle je Bereich**: `NavCoach`,
    `MapCoach`, `SheetCoach` in `map_tour.dart`. Die Knöpfe der
    Werkzeugleiste heißen generisch `map.rail.<ValueKey>` (in der
    Knopf-Fabrik von `offline_tool_rail.dart`) — ein neuer Knopf ist
    sofort ein Anker. Das Trail-Blatt teilt seine Anker (`sheet.*`) mit
    der Trails-Tour (#136).
  - **Szenen meldet `MapScreen` an** (`_registerCoachScenes`, abgemeldet
    in `dispose`): `map.rail` öffnet die Leiste und verwirft den leeren
    Entwurf danach selbst (NICHT über `_closeTools`, das bei einem
    Entwurf nachfragte), `map.layersSheet` das Blatt „Kartenebenen"
    (seit 0.75.0 eigenständig, #190; vorher `map.rail/filter` auf der
    Leiste), `map.trailSheet` das Blatt von `_coachTrail`.
  - **Schild und Blatt zeigen denselben Trail**: `_coachTrail` ist der
    erste gezeichnete mit Schild (`hasTrailBadge`, dieselbe Regel wie die
    Marker), sonst der erste gezeichnete; nur SEIN Schild trägt den
    Anker (`trailBadgeMarkers(coachTrailId:)`). Auf Android sind die
    Schilder Flutter-Widgets in MapLibres `WidgetLayer`, der Anker sitzt
    also auf beiden Engines; MapLibre filtert Marker außerhalb des
    Fensters weg — dann fällt Schritt 1 über `requires` weg.
  - **Ohne Trail fallen zwei Schritte weg**: Schritt 1 über
    `requires: [map.trailBadge]`, Schritt 2 über `unless: [map.empty]`
    (der leere Kartenzustand ist ein Anker). Der Anker IM Blatt darf
    nicht in `requires` stehen — er entsteht erst mit der Szene.
  - **Die Linien sind keine Widgets — die Legende schon.** Schritt 3
    klappt die Legende auf der Karte auf (Szene `MapCoach.legend`, seit
    0.77.0, #182) und leuchtet sie aus; bis 0.76.x stand eine gezeichnete
    Mini-Legende in der Blase (`CoachStep.illustration` bleibt als
    Möglichkeit der Maschine).
  - **Schritttitel nie wie ein Text auf dem Schirm** („Ebenen und Orte",
    „Meine Position", „Mein Beitrag" sind verboten) — der Test fände das
    Element statt der Blase; Tests suchen deshalb in `coach-bubble`.
    Nach jedem Schritt `settle()`: 400 ms Tippsperre. Merker
    `mapTourSeen` (`map_tour_seen`, ohne Suffix, Reset-Konvention wie
    beim Hinweis); `FakeSettings.mapTourSeen` steht auf `true` (Gegenprobe
    siehe nächster Abschnitt).
