# TrailBuddy — Arbeitsregeln für `lib/features/rides/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Fahrt aufzeichnen** (#28, `lib/features/rides/`, seit 0.13.0): die
  Pilztour aus PilzBuddy (#338/#342/#465 dort) ohne Leergang-Logik.
  Foreground-Service vom Typ `location` (`flutter_foreground_task`),
  **gemessen wird im Service-Isolate** (`ride_task_handler.dart`,
  `recordRideTick`), nicht im Main-Isolate — der stirbt beim Wegwischen,
  der Service nicht. JSON Lines unter `rides/` (Backup-Ausschluss),
  angehängt je Takt (5 s); Beenden benennt `active.jsonl` in
  `<id>.jsonl` um — die Fahrt bleibt als Ganzes auf dem Gerät, gelöscht
  wird nur auf Wunsch („Meine Fahrten" im Profil). Fünf Dinge, die man
  wissen muss:
  - **`initRideCommunication()` in `main()` ist die Rückrichtung.** Ohne
    sie meldet der Service jeden Punkt ins Leere, still, und die Karte
    kennt nur den ersten Fix — PilzBuddy #465, vier Wochen unbemerkt.
    `test/rides/ride_live_bridge_test.dart` prüft Rundlauf, Gegenprobe
    UND die Zeile.
  - **Die Brücke ist SharedPreferences** (`ride_dir`, `ride_uid`,
    `ride_active`): flache Werte, in beiden Isolaten lesbar. Der Pfad
    wird einmal drüben aufgelöst; im Service-Isolate gibt es kein
    Riverpod und keinen `ErrorSink`, `recordRideTick` fängt deshalb
    alles.
  - **Seit 0.19.0 ein Verbraucher von zweien** (`lib/features/keep_alive/`,
    PilzBuddys Koordinator #264/#338): Die Fahrt (`location`, mit Takt)
    und der Bereichs-Download (`dataSync`, ohne Takt) teilen sich den
    EINEN Service über den `KeepAliveCoordinator` — zwei `stop()` auf
    einem Service waren die Falle. Ändert sich die Typmenge, startet er
    den Service neu (`updateService` kann Typen nicht ändern); der Takt
    gehört dem Service-Isolate und hat genau einen Verbraucher. Das
    Manifest deklariert `dataSync|location` als Obermenge, genannt wird
    je Start nur, was der Lauf braucht. `test/keep_alive_test.dart`.
  - **Die GPS-Höhe wird ROH mitgeschrieben** (`RidePoint.altM`) und
    nirgends angezeigt: Ob sie als Höhenquelle taugt, wird gemessen,
    bevor eine Zahl daraus wird; Dateihöhen bleiben die Quelle.
  - **Kein Web.** `rideRecordingAvailableProvider` (= `!kIsWeb`)
    versteckt den Knopf; ein Tab im Hintergrund bekommt keine
    Positionen. Der Service-Import ist bedingt (`keep_alive_stub`).
  Manifest: `FOREGROUND_SERVICE(_LOCATION|_DATA_SYNC)`,
  `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED` entfernt, Service-Typ
  `dataSync|location`, Symbol `ic_notification.xml` (nur Alphakanal,
  PilzBuddy #331) über den Meta-Data-Namen
  `keepAliveNotificationIconMetaData` — der Manifest-Test hält alles
  zusammen. Ausdrücklich kein `ACCESS_BACKGROUND_LOCATION`:
  die Dauerbenachrichtigung ist die Offenlegung. Der Harness hängt
  `FakeRideStore`, `FakeRideFix`, `FakeRideServiceBridge` und
  `FakeRideService` ein, sonst ginge jeder Kartentest über `restore()`
  an `path_provider`.
- **Bestätigen durch Fahren** (#116, seit 0.52.0, `ride_confirm.dart`
  pur, `ride_confirm_notify.dart`, Wächter in `ride_task_handler.dart`):
  Wer aufzeichnet und AUF einen Trail mit unbestätigter Meldung oder
  unbestätigtem Zustand kommt, bekommt sofort eine lokale
  Benachrichtigung — Trailname, was gemeldet ist, Knöpfe „Stimmt",
  „Trail ist frei" (nur bei einer warnenden Meldung), „Ändern…". Kein
  Schema (Betreiber, 2026-09-30): Die Antwort IST eine bestätigte
  Meldung des Fahrers mit demselben Wert, über `report_trail` mit
  `on_site` — der Dienst hat ihn auf der Linie gesehen. Sechs Dinge,
  die man wissen muss:
  - **Eine Fahrt ohne Antwort bestätigt nichts** fremdes; Schritt 8 von
    `contribute_recording` (die EIGENE Meldung auf „offen") bleibt.
  - **Die App legt die Ziele ab, der Dienst liest sie**
    (`rides/confirm_targets.json`, mit Konto, per `.part` + `rename`):
    `confirmTargetsOf` nimmt dieselbe Regel wie die Anzeige
    (`shownReportsOf`, auch eigene), geschrieben beim Start, bei jedem
    Laden der Trails (Karte) und leer beim Beenden. Der Dienst liest nur
    neu, wenn sich die Datei ändert — nie die ganze `network.json` je
    Takt.
  - **Gefragt wird auf der Linie, nicht daneben** (`confirmPromptFor`):
    zwei aufeinanderfolgende Fixe ≤ 30 m Genauigkeit, beide ≤ 20 m von
    der Linie, ≥ 25 m auseinander — wer quert oder steht, wird nicht
    gefragt. Enger als „vor Ort" (200 m) mit Absicht.
  - **Fragen und Antworten stehen als Zeilen IN der Fahrt**
    (`ConfirmAsked` mit dem Wert von damals, `ConfirmAnswered`;
    `RidePoint.fromJson` lässt sie liegen). Je Trail und Fahrt einmal —
    auch über einen Neustart des Isolates, der Wächter liest die
    gestellten Fragen aus der Datei. Eine Antwort trägt den Beginn der
    Fahrt im Payload und landet nie in einer anderen.
  - **Zwei Wege für eine Antwort**: Knöpfe ohne Oberfläche laufen im
    Hintergrund-Isolate des Pakets (`rideConfirmBackgroundResponse`,
    `vm:entry-point`), „Ändern…" und der Tipp auf die Benachrichtigung
    im Main-Isolate (`rideConfirmTapsProvider`, `PushListener` öffnet
    `/trail/<id>`). Beide schreiben über `handleConfirmResponse` in die
    Datei. Gesendet wird beim Beenden (`RideNotifier.stop`, vor dem
    Blatt), je Trail die letzte Antwort, mit ihrer Zeit — ohne Netz in
    den Ausgangskorb. „Ändern…" und Unbeantwortetes schreiben nichts —
    die fragt das Zerlege-Blatt (seit 0.53.0, `splitQuestionFor`,
    `split_confirm_row.dart`): an der Zeile des wieder gefahrenen
    Trails, nur was VOR der Fahrt gemeldet war, nur mit Zeitstempeln,
    gesendet SOFORT beim Tipp mit der Zeit der Fahrt am Trail (nicht
    mit „Speichern" — die Antwort hängt nicht am Beisteuern). Wer
    unterwegs geantwortet hat, wird nicht noch einmal gefragt: Seine
    Meldung ist die jüngste bestätigte (auch wartend im Korb), die
    unbestätigte damit überholt.
  - **Kanal `trailbuddy_meldungen`** (IMPORTANCE_HIGH, derselbe wie
    Push) — die Dauerbenachrichtigung der Fahrt ist leise und zeigte
    kein Banner. `flutter_local_notifications` braucht Desugaring
    (`build.gradle.kts`), den `ActionBroadcastReceiver` im Manifest
    (ohne tut ein Knopf nichts, still) und bringt `VIBRATE` mit; der
    Manifest-Test hält alles zusammen. Der Harness überschreibt
    `rideConfirmTapsProvider`.
- **Das Zerlege-Blatt** (#29, Konzept 5.1, `ride_split.dart` pur,
  `road_index.dart`, `ride_split_sheet.dart`, seit 0.20.0): nach der
  Aufzeichnung, aus „Meine Fahrten" (Schere) und aus dem GPX-Import für
  Fahrten — EIN Blatt, EIN `SplitRequest`. Acht Dinge, die man wissen
  muss:
  - **Bekannt heißt: mit den Schwellen des Abgleichs gedeckt** (15 m,
    0,8, beidseitig, `kMatch*`), das Stück der Fahrt im Korridor wird
    als Aufzeichnung beigesteuert („wieder gefahren"), ohne Namen und
    ohne Beitrag — der Trail hat schon einen. Kein Fréchet auf dem
    Gerät: Verschmelzen tut der Server; was das Blatt „bekannt" nennt,
    soll er auch verschmelzen, sonst legte er still einen Trail daneben.
  - **Kandidaten brauchen die Wege, und die kommen NUR aus gespeicherten
    Bereichen** (`loadRoads`: z13-Kacheln der Fahrt, Ebene `roads`,
    Straße = `highway`/`major_road`/`medium_road`/`minor_road`/`other`
    plus `path`+`track`; Pfade, Fußwege, Schienen nicht). Jede Kachel
    muss in einem Bereich liegen — `partial` heißt unbekannt, kein halber
    Kandidat. Ohne Wege keine Kandidaten (Betreiber, 2026-09-28: keine
    Gefälle-allein-Regel), das Blatt sagt es und nennt den Weg.
    `vector_tile` ist dafür direkte Abhängigkeit (es steckt ohnehin in
    `vector_map_tiles`).
  - **Das Gefälle kommt aus der GPS-Höhe** (Median über 7 Punkte,
    Abfahrt von Gipfel bis Talsohle, Ende bei 15 m Gegenanstieg,
    mindestens 30 Hm und die Mindestlänge eines Trails, `kTrailMinLengthM`; > 70 % der 5-m-Abtastpunkte abseits;
    Enden auf die Straße gestutzt). Beigesteuert wird die GPS-Höhe
    NICHT (`SplitRequest.stripElevation`, #28-Regel); Dateihöhen einer
    GPX-Fahrt schon. Ein Höhengitter gibt es in TrailBuddy nicht — das
    Konzept sagt „Höhengitter, offline", gebaut ist die Höhe der Spur.
  - **Unscharfe Fixe (> 30 m) fallen vor allem weg** und werden gezählt;
    ein 15-m-Korridor gegen einen ±40-m-Fix ist Rauschen.
  - **Die Karte zeichnet die Vorschau** (`rideSplitPreviewProvider`,
    Fahrt blass, bekannt grün, Kandidat `MapPalette.candidate`, abgewählt
    gestrichelt); die Griffe sind ein `RangeSlider` je Kandidat, die
    Linie folgt. Aufgeräumt wird NACH dem `await` des Blatts, nicht im
    `dispose` (dort ist `ref` tot). Die Knöpfe stehen fest unter der
    faulen Liste — im Test muss man das Blatt hochziehen, bevor ein
    Kandidat gebaut ist (`sheetScrollTo`).
  - **Name, S-Grad und Charakter gehen in EINEM Schreibvorgang** in den
    eigenen Beitrag (`adoptDetails`, auch im Ausgangskorb:
    `ContributeJob.grade`/`.traits`; ein Auftrag von vor 0.35.0 hat
    keine `traits` und liest sich leer).
    Heimzone (300 m) ist ein Hinweis am Kandidaten, kein Riegel — und er
    folgt den Griffen (`homeZoneOf`), nicht dem gefundenen Stück.
  - **„Stück selbst wählen"** (#104, seit 0.47.0, `manualSection`): ein
    Kandidat über die ganze Fahrt, ohne Wege und ohne Höhen, für alles,
    was die Abfahrts-Suche nicht findet. Vorgewählt ohne die ersten und
    letzten 300 m (Heimzone); ist die Fahrt dafür zu kurz, die ganze.
    Kein Merkmal „neu" oder „selbst gebaut" (Konzept 7).
  - **Marken während der Aufnahme** (#105, seit 0.57.0, `RideMark`,
    `markedRanges`): ein 44-dp-Knopf über der Aufnahme, nur während der
    Fahrt (Fahne, dann Zielflagge mit Rand — `markedTrailOpen`, EINE
    Regel für Knopf und Blatt). Vier Dinge, die man wissen muss:
    - **Die Marke trägt NUR die Zeit**; das Blatt nimmt den zeitlich
      nächsten Punkt. Kein eigener Fix beim Tippen — den Ort misst der
      Takt ohnehin.
    - **Geschrieben aus dem Main-Isolate** (`appendMark`), nicht über
      den Service wie der Punkt (Abweichung von Rework 5.2): Getippt
      wird dort, und die Datei nimmt schon die Antworten aus #116 von
      dort an; ein Umweg über den Service könnte still verloren gehen.
      Der Zustand trägt die Marke erst, wenn die Datei sie genommen hat
      — sonst zeigte der Knopf eine Marke, die das Blatt nie sieht.
    - **Paare in zeitlicher Reihenfolge**: Beginn öffnet, Ende schließt,
      ein zweiter Beginn schließt den offenen dort, ein Ende ohne Beginn
      zählt nicht, offen gilt bis zum letzten Punkt. Ohne Zeiten keine.
    - **Die Marke schlägt die Heuristik**, wo sie sich überschneiden,
      und weicht nur einem bekannten Trail, der ≥ 0,8 des Stücks deckt
      (sonst ginge dieselbe Strecke zweimal hinaus). Kandidat mit
      `marked`, vorangehakt, Griffe über die ganze Fahrt (`spansRide`),
      ohne Wege und ohne Höhen.
