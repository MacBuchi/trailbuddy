# TrailBuddy — Arbeitsregeln für `lib/features/trails/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Importregel**: < 8 km und Verlust > 2 × Gewinn ⇒ Trail, sonst Fahrt.
  Eine Fahrt geht über die Schere im Import auf die Karte ins
  Zerlege-Blatt (#29, seit 0.20.0). Ohne Zeiten oder mit > 60 km/h
  Median ⇒ `planned`. **Fahrdatum** (#120, Patch 015, seit 0.58.0): Für
  eine geplante Datei trägt man im Import „Gefahren am …" ein (12 Uhr
  Ortszeit, höchstens heute; auch für die Schere, `SplitRequest.rodeAt`).
  Sie bleibt `planned` (Qualität 0,1, die Linie ist gezeichnet), aber
  `recorded_at` trägt das Datum — und „`planned` MIT Datum" IST
  „gefahren": `has_ridden` und Schritt 8 von `contribute_recording`
  zählen sie, auf dem Gerät `TrailRecording.ridden` (Spiegel für
  `hasRidden`, `onlyPlanned`, `allPlanned` und den Fake). Keine neue
  Quelle — ältere Clients kennen keinen neuen Wert; Patch 015 leert
  vorsorglich jedes Datum an bestehenden `planned`-Zeilen.
  `matcher_check.sql` Block 24.
- **Höhen** (Patch 002, #14): `trail_recordings.ele` trägt eine Höhe je
  Punkt der Linie oder ist leer — ganz oder gar nicht, der Check
  `trail_recordings_ele_check` hält Anzahl und Bereich fest. Vier Dinge,
  die man wissen muss:
  - **Die RPC entfernt doppelte Punkte SAMT Höhe** (Fensterfunktion statt
    `st_removerepeatedpoints`, das nur die Linie kürzte und die Höhen
    danach versetzt neben ihr herlaufen ließe). `matcher_check.sql`
    Block 16 prüft genau das.
  - **Die Vereinfachung vor dem Hochladen rechnet dreidimensional**
    (`simplify`, senkrechte Toleranz `kSimplifyVerticalM` = 2 m,
    gemessen): Ein gerades,
    welliges Stück verlöre sonst seine Wellen. Das Import-Blatt rechnet
    deshalb auf der VEREINFACHTEN Spur, damit es dieselbe Zahl sagt wie
    danach das Trail-Blatt.
  - **Hysterese `kElevationThresholdM` = 3 m**, gemessen an 578 Tracks
    (`docs/trail-abgleich-messung.md`, Abschnitt Höhen), Spiegel in
    `tool/elevation_measure.py` mit denselben Testvektoren; Werkzeug und
    Dart im selben PR ändern. Die Importregel „Abstieg > 2 × Anstieg"
    rechnet bewusst ROH — so ist sie gemessen.
  - **Angezeigt wird in Trail-Richtung, aus der besten Aufzeichnung MIT
    Höhen** (`Trail.elevation`), nicht zwingend aus der besten Linie.
    Ohne Höhen sagt das Blatt „Keine Höhenangaben", nie „0 Hm".
    Aufzeichnungen vor 0.3.0 haben keine.
  - **Nachtragen** (#16, Patch 003): Dieselbe Datei noch einmal
    importiert legt keine zweite Aufzeichnung an. Der Import sucht die
    gespeicherten Punkte der Reihe nach in der Datei (sie SIND
    Originalpunkte; neu vereinfachen ergäbe seit 0.3.0 eine andere
    Linie), Anfang und Ende müssen die der Datei sein
    (`elevation_backfill.dart`). `attach_elevation` prüft auf dem Server
    Punkt für Punkt ≤ 5 cm, nur eigene Aufzeichnungen ohne Höhen,
    überschreibt nie, zählt nicht ins Tageslimit. Schon mit Höhen
    Beigesteuertes steht im Import gesperrt da.
- **Schwierigkeit** (#14, Teil 2): Singletrail-Skala S0–S5 je Beitrag,
  angezeigt als Median (bei Gleichstand der SCHWERERE — im Zweifel die
  Warnung), Spanne und Anzahl. Die Beschreibungen stehen an EINER Stelle
  (`singletrail_scale.dart`, eigene Kurzfassungen, keine Zitate) und sind
  überall aufrufbar, wo man einen Grad angibt: Auswahl im Beitrag und
  Chips im Blatt. Die Einschätzung im Blatt gibt es nur für selbst
  belegte Trails (Konzept 3: ohne Beleg kein Beitrag).
- **Charakter** (#72, Patch 009, seit 0.34.0): Mehrfachwahl je Beitrag
  (`trail_details.traits`, sieben Merkmale: Flowig, Jump-Line, Verblockt,
  Steil, Uphill, Naturtrail, Verbindung), ersetzt die Einzelwahl „Art".
  Angezeigt die höchstens zwei häufigsten über alle sichtbaren Beiträge
  (`Trail.topTraits`, Gleichstand nach Reihenfolge von `TrailTrait`);
  Beschreibung und Symbol an EINER Stelle (`trail_traits.dart`, Symbole
  farblos — die Farbe gehört der Schwierigkeit). Die Filter „Flowig"/„Jumps"
  prüfen die ANGEZEIGTEN zwei, nicht jede Nennung. Vier Dinge, die man
  wissen muss:
  - **`kind` bleibt vorerst stehen** (erweitern → ausliefern →
    entfernen): Clients bis 0.33.0 lesen und schreiben weiter nur sie,
    ihre Änderungen erreichen `traits` nicht. Die App schreibt `kind` nicht
    mehr (`toRow`), sonst überschriebe sie, was ein alter Client liest.
    Entfernt wird die Spalte in einem eigenen Patch, wenn
    `minimum_supported_version` über 0.33.0 steht.
  - **Patch 009 übernimmt die alte Art** (flow → flowy, jump → jumps,
    tech → rocky, natural, connection) und `fromJson` fällt auf dieselbe
    Zuordnung zurück, wenn `traits` fehlt (Zwischenspeicher, Ausgangskorb
    von vor 0.34.0).
  - **Unbekannte Merkmale fallen beim Lesen weg**, statt zu werfen — ein
    neueres Merkmal darf eine ältere App nicht umwerfen. Der Check in der
    Datenbank lässt nur die sieben zu.
  - **Im Zerlege-Blatt seit 0.35.0**, dieselben Chips je Kandidat
    (`TrailTraitChip`). Die Merkmale KOMMEN DAZU (`adoptDetails`), nichts
    wird weggenommen: Das Blatt zeigt den bisherigen eigenen Charakter
    nicht, und verschmilzt der Server die Spur mit einem Trail, den ich
    schon beschrieben habe, soll eine Abfahrt meine Angabe nicht still
    ersetzen. Der Grad dagegen wird gesetzt (ein Wert, gerade gefahren).
- **Farbe = Schwierigkeit** (seit 0.42.0, Betreiber 2026-09-29): Linie
  auf der Karte, Streifen in der Liste und S-Grad-Schild tragen die
  Pistenfarbe des Medians (`GradePalette`: S0 grün, S1 blau, S2 rot, ab
  S3 schwarz — im Dunklen hell —, ohne Einschätzung grau; ab S4 der
  SAUM gestrichelt, seit 0.51.0 — die Linie selbst trägt den bestätigten
  Zustand: durchgezogen, bröckelig, gestrichelt, gestrichelt und
  verblasst, `trailLineStyleOf`; `MapViewPolyline.borderDash` ist das
  eigene Muster des Saums, in flutter_map eine eigene Linie darunter). **Uphill schlägt die Stufe**: Steht Uphill
  unter den angezeigten zwei Merkmalen, trägt der Trail Magenta (seit
  0.77.2, #195; davor Petrol, kaum von S0 zu unterscheiden) und das
  Schild einen Pfeil statt der Form (`trailColorOf`/`isUphill` in
  `grade_shield.dart`, eine Regel für Karte, Streifen, Schild). Wem ein Trail gehört, zeigt KEINE Farbe
  mehr, nur das Wort. Gemeldet und neuer Hinweis liegen als Leuchtrand
  um die Linie (gemeldet schlägt Hinweis), die Linie behält ihre Stufe.
  Die Karte nimmt immer `AppColors.mapGrades` (hell), die App
  `palette.grade`. `docs/design/README.md` Abschnitt 1–2 und 7.
- **Link zur Quelle** (#103, seit 0.48.0, Patch 012,
  `trail_link.dart`): `trail_details.link`, nur https ohne Query und
  Fragment — `sanitizeLink` in der App, `trail_details_link_check` in der
  Datenbank, der Fake spiegelt beides. Der Import nimmt `<link href>` der
  Spur, sonst aus `<metadata>`, über `linkFromFile` (ohne Gerätehersteller
  und Tourenportale, `kLinkIgnoredHosts`) und übernimmt ihn wie den Namen
  nur in einen Beitrag ohne Link (`adoptDetails`, `ContributeJob.link`).
  Das Blatt zeigt den Host (`linkHost`), geöffnet wird extern; die App
  ruft ihn nie ab. **Jeder, der `TrailDetails` neu baut** (Dialog, Fake),
  muss den Link mitgeben — sonst löscht Speichern ihn still.
  `matcher_check.sql` Block 22. **Umlaute** (#223, seit 0.83.4): Dart
  kodiert einen Host mit Umlauten mit Prozentzeichen („m%C3%BChle"),
  der Browser schickt Punycode. Gespeichert wird die Form des Browsers
  (Host über `hostToAscii` in `lib/core/idn.dart`, Pfad prozentkodiert),
  gezeigt die der Adresszeile (`linkHost`, `linkForDisplay` im
  Eingabefeld; nur Bytes über ASCII werden aufgelöst, „%20"/„%2F"
  bleiben). Alte Zeilen mit Prozent-Host zeigt `linkHost` ebenso
  lesbar; beim nächsten Speichern werden sie Punycode.
- **Hinweise für Buddys** (#7, Patch 004 + 005, `trail_notes.dart`):
  freier Text zu einem Trail („Baum liegt quer"). Schreiben darf, wer
  den Trail SIEHT (`app_internal.can_see_trail`, dieselbe Regel wie
  `recordings_select`); sehen der Autor und seine direkten Buddys, die
  den Trail sehen, nicht bei „privat" (`contributor_shares`); entfernen
  jeder, der den Hinweis sieht („erledigt"); KEIN Bearbeiten (das Alter
  soll stimmen). Aufbewahrung 90 Tage (`sweep_old_notes`, pg_cron), der
  jüngste je AUTOR und Trail bleibt — je Autor, weil „der jüngste über
  alle Netze" eine Rechnung über Netzgrenzen wäre (Konzept 12); das
  Blatt zeigt von den alten nur den jüngsten (`Trail.notesShown`). Ein
  Hinweis eines Buddys jünger als `kFreshNoteDays` (7), der auf diesem
  Gerät noch nicht im Blatt zu sehen war (`Settings.seenNoteIds`), hebt
  den Trail hervor — gelber Rand auf der Karte, gelb umrandete Karte mit „neuer
  Hinweis" in der Liste; eigene zählen nie. Beim Melden bietet der
  Dialog einen Hinweis an. Entscheidungen des Betreibers
  vom 2026-09-28; `matcher_check.sql` Block 20 prüft RLS und Aufräumen.
- **Bewertung, Meldung, Zustand** (#101, Patch 013, seit 0.49.0;
  `trail_report.dart`, `trail_condition.dart`, Rework Abschnitt 9).
  Die Bewertung (1–5 Sterne) steht im Beitrag (`trail_details.rating`),
  angezeigt als Median (bei Gleichstand der höhere) mit Anzahl; ein
  eigener Trail ohne eigene Bewertung zeigt verblasste Sterne
  (`Trail.ratingOpen`). Meldung (bis 0.48.0 „Status") und Zustand
  (1–5) sind ein VERLAUF in `trail_reports`. Sieben Dinge, die man
  wissen muss:
  - **Melden darf, wer den Trail SIEHT** (`can_see_trail`), nicht nur,
    wer ihn belegt hat — Abweichung von Konzept 3, vom Betreiber
    entschieden. Geschrieben wird NUR über `report_trail` (Definer, kein
    insert-Grant): **`confirmed` legt der Server fest** — gefahren
    (`has_ridden`: nicht `planned`, oder `planned` mit Fahrdatum) oder
    `on_site`. `grants_check.sql`
    wacht darüber, dass kein Client-Grant `confirmed` frei wählbar macht.
  - **„Vor Ort" prüft nur das Gerät**: ≤ `kOnSiteMaxM` (200 m) zur
    angezeigten Linie, mit EINEM Fix nach Tipp auf „Ich bin vor Ort"
    (`positionFixProvider` — nie beim Öffnen). An den Server geht das
    Ja/Nein, gespeichert wird dort nur `confirmed`, nie die Position.
  - **Angezeigt** (`shownReportsOf`): die jüngste bestätigte, dazu
    verblasst die jüngste unbestätigte, wenn sie jünger ist. Karte,
    Liste und Filter „Gemeldet" folgen NUR der bestätigten
    (`Trail.status`). Der Zustand gilt dauerhaft (keine 90-Tage-Grenze
    für die Anzeige). Push nur für bestätigte Meldungen, nie für den
    Zustand (`push_on_report` ersetzt `push_on_status`).
  - **90 Tage Verlauf** (`sweep_old_reports`, pg_cron), die jüngste je
    Person, Trail, Art und Bestätigung bleibt länger — die angezeigte
    muss auch nach einem Jahr da sein. Das Blatt zeigt den Verlauf mit
    Name bzw. Alias (`BuddyNames.of`).
  - **Eine Fahrt setzt die eigene Meldung zum FAHRDATUM auf „offen"**
    (`contribute_recording` Schritt 8, `recorded_at`, gekappt auf jetzt),
    nur wenn es eine eigene Meldung gibt, sie älter ist und kein
    bestätigtes „offen" ist; nie bei `planned`. `report_trail` kappt
    `reported_at` ebenfalls auf jetzt — eine Zeit in der Zukunft gewönne
    sonst jeden Vergleich.
  - **Alte Clients (bis 0.48.0)** lesen und schreiben weiter
    `trail_details.status`/`status_at`: `reports_from_details` macht
    daraus eine Meldung, `reports_to_details` schreibt eine BESTÄTIGTE
    Meldung an den Beitrag zurück; `pg_trigger_depth()` hält die beiden
    auseinander. Die App schreibt `status` nicht mehr (`toRow`), liest
    es nicht mehr. Entfernt wird es in einem eigenen Patch, wenn
    `minimum_supported_version` über 0.48.0 steht.
  - **Liste** (seit 0.50.0): Sterne in der Zeile, `TrailSort.rating`;
    Wörter aus `trailRowTags` — eine abweichende jüngere unbestätigte
    Meldung als „GESPERRT?" (gedämpft), der BESTÄTIGTE Zustand ab
    `kConditionWordMax` (2) als Wort hinter Meldung und Hinweis.
    `trail_condition.dart` bleibt ohne Widgets (die Liste rechnet damit),
    die Sterne stehen in `rating_stars.dart`.
  - **Ausgangskorb**: `ReportJob` trägt die Zeit des Meldens
    (`createdAt` → `reported_at`) und die `client_id` (eindeutig je
    Nutzer, Kennung und Art). Ein `DetailsJob` von vor 0.49.0 bringt
    seinen Status als `legacyStatus` mit und geht beim Nachholen als
    Meldung raus. `matcher_check.sql` Block 23, `push_flush_check.sh`
    Fall 3b.
  - **Noch gültig?** (#119, seit 0.58.0, `still_valid.dart` pur,
    `still_valid_screen.dart`, Profil-Zeile mit Zähler, Filter
    `stillValidOnly` — Zeile und Chip nur, wenn es etwas zu prüfen gibt
    bzw. der Filter an ist; sonst kostete der Chip eine Zeile): gefragt wird nach MEINER jüngsten Angabe je Art,
    wenn sie noch angezeigt wird (`shownStatus`/`shownCondition` — eine
    jüngere bestätigte eines Buddys überholt sie), bei einer Meldung nur,
    wenn sie warnt, und erst ab `kStillValidAfter` (30 Tage). Ja =
    derselbe Wert neu, Nein = „offen" bzw. die Skala, beides über
    `report` (bestätigt wie immer, ohne Netz in den Korb). „Weiß nicht"
    ruht `kStillValidSnooze` (14 Tage, Betreiber) und liegt NUR auf dem
    Gerät (`Settings.stillValidSnoozes`, `<Kennung>|<bis>`, Abgelaufenes
    fällt beim Schreiben weg) — eine Tabelle wäre eine Lesequittung.
    Liste und Karte reichen die ruhenden Angaben an `passesTrailFilter`
    (`snoozed`), damit Filter und Seite dasselbe sagen.
- **Suche, Filter, Sortierung der Trail-Liste** (#66, seit 0.32.0,
  `trail_list.dart` pur, `lib/core/search_text.dart`): fehlertolerant wie
  PilzBuddy #395 — `foldSearchText` (klein, ä/ae → a, ohne Leer- und
  Satzzeichen), erst Teiltreffer, NUR wenn der leer ausgeht der
  Tippfehler-Ausgleich (`nearContainsDistance`, nur der beste Abstand),
  und die Liste sagt dann „Meintest du …?". Gesucht wird über Namen und
  Buddy-Namen, nie über Hinweistexte. „bis S2" lässt Trails OHNE
  Einschätzung weg (im Zweifel die Warnung) und zählt sie. Filter und
  Sortierung gelten für die Sitzung. **Der Filter gilt seit 0.33.0 für
  Liste UND Karte** (Betreiber, 2026-09-29): EIN Provider
  (`trailListFilterProvider`), EINE Regel (`passesTrailFilter`), EIN
  Chip-Widget (`TrailFilterChips`, in der Liste und im Blatt „Ebenen").
  Suche und Sortierung bleiben in der Liste. Auf der Karte wirkt er NUR
  auf Zeichnen und Treffen — „Entlang meiner Trails", Einpassen, Fokus
  und das Zerlege-Blatt rechnen mit allen. Ein aktiver Filter meldet sich
  oben auf der Karte mit X (PilzBuddy #154: still ausblenden sieht aus
  wie fehlende Trails); ein Fokus-Sprung auf einen ausgeblendeten Trail
  (Push) setzt ihn zurück und sagt es. Die Banner oben stehen seither
  untereinander in EINER Spalte (Update, Ausgangskorb, Filter).
- **Übernehmen beim ersten Befahren** (#102, seit 0.55.0,
  `trail_takeover.dart` pur, Rework Abschnitt 1 und 9, E1/E2): Eine
  bekannte Zeile im Zerlege-Blatt OHNE eigenen Beitrag
  (`needsTakeOver`: `myDetails == null`, nicht wartend) klappt auf:
  Name, S-Grad, Charakter, Sterne, Zustand — vorbelegt mit der Anzeige
  (`takeOverOf`: `displayName`, Median-Grad, `topTraits`, Median-Sterne;
  Zustand nur der jüngste BESTÄTIGTE der letzten 90 Tage), sichtbar als
  „Vorschlag aus dem Netz". Drei Dinge, die man wissen muss:
  - **Pflicht mit Sternen (E2)**: Unbestätigt zählt die Zeile nicht
    (`_knownCounts`), bestätigen geht erst mit Sternen; „Alle
    übernehmen" bestätigt jede Zeile, die schon Sterne hat. Wer den
    Trail schon beschrieben hat, wird nie gefragt.
  - **EINE Schreibstelle**: `adoptDetails` übernimmt den fremden Namen,
    weil der eigene leer ist, und schreibt die Sterne nur in einen
    Beitrag ohne eigene (`ContributeJob.rating`, Auftrag von vor 0.55.0
    liest sich ohne). Der Zustand geht als Meldung an den bekannten
    Trail (`report`, `on_site`, Zeit der Fahrt dort) — nur mit
    Zeitstempeln.
  - **Kein Rückfüllen auf dem Server** — es kopierte Namen von außerhalb
    des Netzes (Konzept 12). Für den Bestand (seit 0.56.0): „Übernehmen"
    im Blatt, solange der eigene Beitrag keinen Namen hat
    (`offersTakeOver`; `showTrailDetailsDialog(takeOver: true)`, leere
    Felder aus `takeOverDetails`, Speichern erst mit Sternen), dieselbe
    Zeile im Import-Ergebnis für Kennungen, die vorher nur über Buddys
    sichtbar waren (erst NACH der RPC bekannt), und der Filter
    „Bewertung offen" (`ratingOpenOnly` = `Trail.ratingOpen`, dieselbe
    Regel wie die verblassten Sterne).
- **GPX-Export von Fahrten und Trails** (#150, seit 0.68.0; Konzept
  10.4 „Sicherung ist der GPX-Export", 13 „Integration heißt Datei").
  Writer `lib/features/trails/gpx_writer.dart` (neben dem Parser, er
  nimmt dessen `TrackPoint`; Rundlauf-Test gegen `parseGpx`), pur je
  Quelle `ride_export.dart` und `trail_export.dart`, Naht
  `lib/core/gpx_share.dart` (`gpxShareProvider`, im Harness ein
  Recorder). Einstiege: Menü an der Zeile in „Meine Fahrten", „Als GPX
  exportieren" im Trail-Blatt. Vier Dinge, die man wissen muss:
  - **Der Trail nimmt `best.ele`, nicht `Trail.elevation`.** Das
    Höhenprofil kann aus einer ANDEREN Aufzeichnung kommen als die
    Linie; an die Punkte der besten passen nur ihre eigenen Höhen.
    Punkte und Höhen drehen sich gemeinsam bei `reversed`.
  - **Nichts Fremdes in der Datei**: nur der eigene Link, keine
    Buddy-Namen, keine Hinweise; eine Fahrt ohne ihre Fragen, Antworten
    und Marken — die ganze Linie mit roher GPS-Höhe und Zeit.
  - **Im Browser ist `ShareResultStatus.unavailable` ein Erfolg**:
    `share_plus` lädt die Datei dann herunter. Das Einladungs-Muster
    („unavailable ⇒ Zwischenablage") passt hier nicht; die App sagt
    „wird heruntergeladen".
  - **Kein Netzziel, kein `path_provider`**: `XFile.fromData` legt
    `share_plus` selbst im Cache ab. Aber eine neue Richtung des
    Datenflusses — Datenschutzerklärung, Konzept 2 (Tabelle),
    `ride_track.dart` und `backup_rules.xml` sagen seither „nie von
    selbst"; `privacy_policy_test` prüft weiter den Teilstring.
- **Anfahrt zum Trailkopf** (#151, seit 0.67.0,
  `lib/features/trails/trail_navigation.dart`; Vorlage PilzBuddy #367):
  „Anfahrt" (seit 0.83.0 das Navi-Symbol im Kopf des Blatts, #224) reicht `Trail.start` als `geo:`-URI an
  Android, welche App ihn bekommt, entscheidet der System-Wähler. Drei
  Dinge, die man wissen muss:
  - **Ein `<queries>`-Eintrag VIEW/geo im Manifest.** Ohne ihn sieht
    die App ab Android 11 keinen Empfänger, der Wähler bleibt aus, und
    der Knopf fällt still auf die Zwischenablage zurück — ein Fehler,
    der wie eine Entscheidung aussieht. `test/android_manifest_test.dart`
    prüft ihn gegen `kGeoScheme` aus dem Dart-Code.
  - **Der Rückfall ist die Zwischenablage, nie ein Kartendienst**
    (Konzept 9) — auch im Browser. Ein `https://…`-Link wäre ein fester
    Empfänger, ein neues Netzziel und am Parkplatz ohne Empfang tot. Die
    App sagt, dass sie kopiert hat; klappt der Wähler auf, sagt sie
    nichts (die andere App steht im Vordergrund).
  - **Die Koordinate steht ZWEIMAL im URI**
    (`geo:<lat>,<lng>?q=<lat>,<lng>(<name>)`): Apps, die `q` lesen,
    setzen Pin und Titel; Apps, die es ignorieren, zentrieren auf den
    Pfad. `geo:0,0?q=…` schickt die zweite Gruppe in den Golf von
    Guinea. Der Platzhalter „Trail ohne Namen" wird nicht übergeben
    (`Trail.hasName`).
  Kein Netzziel, keine Berechtigung, keine Weitergabe im Sinne von Data
  Safety (nutzerinitiiert, der Wähler ist die Bestätigung).
- **Das Trail-Blatt schließt auf drei Wegen** (#215, seit 0.83.0,
  `showTrailSheet`): X im Kopf, Zurück, und Ziehen nach unten auf dem
  GANZEN Inhalt. Dafür steckt der Inhalt in einem
  `DraggableScrollableSheet` (auf `kTrailSheetInitialSize` 0,75, schließt
  unter `kTrailSheetMinSize` 0,3 über `shouldCloseOnMinExtent`), dessen
  Controller die Scrollfläche bekommt — ohne ihn nimmt die Scrollfläche
  jede senkrechte Geste, und nur der Griff schließt. `useSafeArea`, sonst
  läuft ein langes Blatt unter die Statusleiste, und der Griff ist
  unerreichbar. `test/flows/trail_sheet_close_flow_test.dart` (Gegenprobe
  ohne Controller: zwei Tests rot).
