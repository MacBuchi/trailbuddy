# TrailBuddy — Arbeitsregeln für `lib/data/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Ausgangskorb** (#30, `lib/data/outbox*.dart` +
  `lib/features/trails/outbox_providers.dart`, seit 0.14.0; PilzBuddy
  #267 als Vorlage): Genau VIER Aufträge — Aufzeichnung beisteuern
  (`ContributeJob`, die Linie so, wie sie an die RPC ging, plus Name),
  eigenen Beitrag speichern (`DetailsJob`), melden (`ReportJob`, seit
  0.49.0, samt Hinweis — „gesperrt" meldet man am Trail) und Feedback
  (`FeedbackJob`, seit 0.86.0, #218). Alles
  andere (Höhen nachtragen, Hinweise allein, Löschen) scheitert weiter
  sichtbar. **Feedback ist ein Auftrag, keine eigene Warteschlange**:
  derselbe Korb, dasselbe Banner, dieselben Auslöser, `outbox/` steht
  schon in den Backup-Ausschlüssen — eine zweite Warteschlange wäre
  derselbe Mechanismus zweimal. Er hängt an keinem Trail: `withPendingJobs`
  gibt bei einem reinen Feedback-Korb das Netz als DIESELBE Liste zurück,
  `_applyPending` überschreibt damit keinen Fehlerzustand, und
  `sendOutbox` lädt nur neu, wenn ein Trail-Auftrag hinausging (Test
  zählt die Abrufe). Wartendes und Abgelehntes zeigt die Glühbirne, das
  Banner verweist dorthin. Sechs Dinge, die man wissen muss:
  - **Nur `looksOffline` führt in den Korb** (`_queueIfOffline`). Ein
    Serverfehler muss sichtbar scheitern — sonst sammelte der Korb still
    Aufträge, die nie durchgehen, und ein kaputtes Deployment bliebe
    unbemerkt. Ein Flow-Test hält es fest.
  - **Der Korb wirft beim Schreiben** (`.part` + `rename`, nichts
    geschluckt): Er trägt das Original. Landet der Auftrag nicht auf der
    Platte, meldet die App den ursprünglichen Netzfehler weiter.
  - **Der Auftrag entsteht VOR dem ersten Sendeversuch**, mit der
    `client_id` — so trägt schon der erste Versuch die Kennung, und ein
    Abriss nach dem Insert legt beim Nachholen keine zweite Aufzeichnung
    an (`contribute_recording` antwortet auf eine bekannte Kennung mit
    der Trail-Kennung von damals).
  - **Wartende Trails stehen auf Karte und Liste** (`withPendingJobs`,
    `Trail.pending`): gestrichelt, Uhr statt Route, „Wartet auf
    Übertragung" — sonst steuert man dieselbe Datei zweimal bei. Ohne
    Server-Kennung gibt es dort keinen Beitrag, keinen Hinweis, keine
    Einschätzung; das Blatt sagt es. Ein wartender Beitrag überlagert
    die eigene Zeile (`Trail.pendingDetails`). Ein Korb-Wechsel lädt NICHT
    neu vom Server (`_applyPending` legt den Korb auf den letzten
    Stand) — der Auftrag entsteht ja gerade, weil es kein Netz gibt.
  - **Die Wiedervorlage** (`OutboxRunner`, Riverpod-frei) schreibt den
    Korb am Ende EINMAL neu. Kein Netz, keine Sitzung und das Tageslimit
    brechen den Lauf ab, ohne den Zähler anzufassen; eine Ablehnung des
    Servers (`PostgrestException`, `WriteRejectedException`) ist sofort
    endgültig, alles andere nach fünf Anläufen. Abgelehnte bleiben
    stehen, bis jemand entscheidet („Erneut versuchen" / „Aus dem
    Ausgangskorb entfernen"). Angestoßen beim Kartenstart, bei der
    Rückkehr der Verbindung (`noConnectivityProvider`,
    `connectivity_plus`) und auf Tippen im Banner — NICHT am App-Resume.
  - **Was gerade gesendet wird, steht schon da** (#183, seit 0.77.1):
    `saveDetails` und `report` legen ihren Auftrag VOR dem Sendeversuch
    als „unterwegs" auf die Anzeige (`_sending`, `withPendingJobs(sending:)`,
    `Trail.sendingDetails`, `TrailReport.sending`) und nehmen ihn erst
    nach Schreiben UND Neuladen herunter — vorher erschien ein S-Grad erst
    nach fünf Abrufen. Der eigene Wert ist blass (`kPendingValueOpacity`,
    `PendingValueCaption`: „wird übertragen …", im Korb „nur auf dem
    Gerät — wartet auf Übertragung"). Ohne Netz liegt der Auftrag im Korb,
    BEVOR er hier herunterkommt (kein Flackern, keine doppelte Meldung:
    `_composeWith` zählt einen Auftrag, der in beiden steht, nur im
    Korb); ein Serverfehler nimmt den Wert sichtbar zurück. Das ist kein
    optimistisches Update an Read-after-write vorbei: Der Wert ist als
    nicht übertragen gekennzeichnet, und der Server-Stand kommt danach
    wie immer durch Neuladen. `test/flows/write_feedback_flow_test.dart`.
  - **Im Browser liegt der Korb in IndexedDB** (#153, seit 0.102.0,
    `outbox_idb.dart`, siehe unten „Korb und Kopie im Browser"). Nur ohne
    IndexedDB (privater Modus, `file://`) gilt `NoOutbox`: `append`
    wirft, der Netzfehler kommt wie vor #30. `outbox/` steht in beiden
    Backup-Ausschlüssen; beim Abmelden bleibt der Korb liegen — er ist an
    das Konto gebunden (`uid` im Kopf), ein fremdes sieht nichts. Der
    Harness hängt `FakeOutbox` (mit `durable`) und einen
    `connectivityProvider` ohne Wechsel ein.
- **Zwischenspeicher des Netzes** (#32, `lib/data/trail_cache.dart`, seit
  0.15.0; PilzBuddy `spot_cache.dart` als Vorlage): Beim erfolgreichen
  Abruf schreibt `fetchWithCache` die drei Tabellen als EINE JSON-Datei
  (`trail_cache/network.json`, Zeilenform wie vom Netz, gelesen von
  denselben `fromJson`; die Encoder stehen daneben, ein Test prüft den
  Rundlauf Feld für Feld). Vier Dinge, die man wissen muss:
  - **Nur `looksOffline` liest die Kopie** (PilzBuddy #80). Ein
    Serverfehler bleibt sichtbar — sonst zeigte die App bei kaputtem
    Deployment wochenlang einen alten Stand als aktuellen.
  - **Eine Kopie wirft nie.** `write` schluckt volle Platte und fehlende
    Rechte, `read` Unlesbares — anders als der Ausgangskorb, der das
    Original trägt.
  - **Der Stand sagt sein Alter** (`trailsCachedAtProvider`): Karte
    („Kein Empfang — Trails vom …") und Liste. `null` heißt frisch.
  - **Beim Kaltstart wartet die App nur kurz aufs Netz** (#183, seit
    0.77.1, `fetchWithCacheQuick`): postgrest wiederholt ein GET bei
    JEDEM Netzfehler dreimal mit 1, 2 und 4 s Pause — ohne Empfang kam
    die Kopie so erst nach rund 7 s, bei einem Balken ohne Daten später.
    Jetzt: Antwort in `kTrailsNetworkPatience` (1,5 s; 0, wenn
    `noConnectivityProvider` schon „kein Netz" sagt) ⇒ wie bisher; sonst
    sofort die Kopie, und das Netz läuft weiter. Kommt es, ersetzt es die
    Kopie (und schreibt sie neu); gibt es auf, bleibt die Kopie; ein
    Serverfehler setzt `AsyncError` über die Kopie. Solange es läuft,
    sagen die Hinweise „das Netz antwortet noch" statt „Kein Empfang"
    (`trailsAwaitNetworkProvider`). Ohne Kopie wird gewartet. Nur der
    ERSTE Abruf je Konto (`_shownFor`) — ein Neuladen nach dem Schreiben
    muss sagen, ob es frisch ist. Kehrt die Verbindung zurück und steht
    noch die Kopie, lädt die Karte neu. Im Test: Ein zweites `pumpApp`
    behält den ProviderScope und ist KEIN Kaltstart — vorher
    `pumpWidget(SizedBox())`.
  - **Abmelden und Kontolöschung räumen die Kopie ab** (Profil), der
    Ausgangskorb bleibt. Im Browser liegt die Kopie seit 0.102.0 in
    IndexedDB (`trail_cache_idb.dart`); Warteschlange, Generationen und
    „wirft nie" stehen EINMAL in `QueuedTrailCache`, Datei und IndexedDB
    liefern nur Text. Der Harness hängt `FakeTrailCache` ein.
- **Korb und Kopie im Browser** (#153, seit 0.102.0; PilzBuddy #385/#386
  als Vorlage): `chooseOutbox`/`chooseTrailCache` entscheiden
  (prüfbar — `kIsWeb` ist im Test immer falsch), `browserIdbFactory()`
  in `browser_storage.dart` liefert den Zugang. Fünf Dinge, die man
  wissen muss:
  - **Name und Version der Datenbank besitzt `browser_db.dart`** (v3:
    `outbox`, `trail_cache` neben Bereichen und gesehenen Kacheln). Zwei
    Speicher mit verschiedenen Versionen blockierten den Upgrade im
    selben Tab, dauerhaft und stumm.
  - **Abgelegt wird derselbe JSON-TEXT wie in der Datei**, je Speicher
    unter einem festen Schlüssel (`jobs`, `network`), das Konto IM
    Eintrag. Als Objekt käme `Map<String, Object?>` zurück, und das ist
    dem `Map<String, dynamic>` der `fromJson` nicht zuweisbar.
  - **Nie die Speicher-Fassung als Rückfall**: `browserIdbFactory()` ist
    `idbFactoryNative` oder `null`, nicht `idbFactoryBrowser` (der fällt
    still auf den Speicher zurück, wenn der native Zugang wirft). Ein
    Korb, der jeden Neustart vergisst, sähe aus wie einer, der bleibt.
    Gesehene Kacheln und Bereiche nehmen noch `idbFactoryBrowser` — in
    idb_shim 2.9.9 liefert der in jedem Browser mit IndexedDB dieselbe
    native Fassung; umgestellt wird beim nächsten Anfassen.
  - **Der Browser darf räumen, deshalb bittet der KORB um Dauer**: einmal
    je Sitzung beim ersten `append` (`navigator.storage.persist()`), nie
    beim Start (Firefox fragt nach), NICHT abgewartet — eine unbeantwortete
    Nachfrage hielte sonst das Ablegen auf. Abgelegt wird auch bei
    Ablehnung; `outboxDurableProvider` (nur solange etwas wartet, neu bei
    jeder Korb-Änderung) lässt das Korb-Banner es sagen („Dein Browser
    sichert diesen Speicher nicht zu …"). Die Kopie bittet nicht: Sie ist
    nur eine Kopie.
  - **Geprüft im echten Chrome**: `test/web/outbox_trail_cache_browser_test.dart`
    (dart2js) verlangt `persistent` des Zugangs — ein stiller Rückfall auf
    den Speicher sähe sonst grün aus (Gegenprobe gefahren). Die Logik
    prüfen `test/outbox/outbox_idb_test.dart` und
    `test/trails/trail_cache_idb_test.dart` auf der VM mit
    `newIdbFactoryMemory()`; `test/fakes/broken_idb_factory.dart` steht
    für „kein IndexedDB".
- **Speichern ohne Neuladen des Netzes** (seit 0.82.1, Feldbericht
  2026-10-02 „abgestürzt beim Eintragen von Trail-Details, z. B. URL oder
  Sterne"; im Digest 2026-W40 ein ANR aus 0.82.0, Haupt-Thread 5 s in
  einem Systemaufruf, RSS 868 MB). Gemessen an 600 Trails
  (`test/perf/network_reload_measure.dart`, kein `_test`, auf dem
  Rechner): Ein Stern kostete den Haupt-Thread 0,3 s Netz lesen, 0,9 s
  Karte (alles neu geglättet, 33 MB GeoJSON an MapLibre) und 0,7 s Kopie
  schreiben — teils mehrmals je Speichern. Jetzt 60 ms und 0 Byte an
  MapLibre; ein S-Grad, der die Linienfarbe ändert, zwei Fächer. Ob das
  der ANR war, ist nicht belegt; die Kosten sind es. Vier Teile, jeder
  mit eigenem Test:
  - **Nachgelesen wird, was geschrieben wurde** (`_rereadAfterWrite` in
    `TrailsNotifier`): `saveDetails` liest die Beiträge, `report` die
    Meldungen (und Hinweise, wenn einer dabei war), `addNote`/`deleteNote`
    die Hinweise. Read-after-write bleibt — nur nicht mehr für jede Linie.
    Die Zusagen sind die von `reloadAfterWrite` (wirft nicht, `false` heißt
    „geschrieben, Anzeige alt", Fehler mit Kontext nach `error_reports`).
    Stammt der Stand aus der Kopie oder gibt es keinen, lädt es ganz neu.
    Die Kopie wird dann mit dem Zeitpunkt des letzten GANZEN Abrufs
    geschrieben — die Linien darin sind nicht jünger.
    `contribute`, `withdraw` und der Ausgangskorb laden weiter ganz.
    `write_feedback_flow_test` zählt die Linien-Abrufe (Gegenprobe: rot).
  - **Unverändertes bleibt dasselbe Objekt** (`lib/data/trail_sharing.dart`):
    `shareSnapshot` tauscht jede gleiche Zeile gegen die vom letzten Mal
    („gleich" = dieselbe Zeile wie in der Kopie, Linien Punkt für Punkt),
    `buildTrails(previous:)` gibt einen Trail mit lauter gleichen Objekten
    als denselben Trail zurück. Daran hängen `Trail.best` und
    `Trail.elevation` (beide `late final`), die geglättete Linie
    (`_smoothCache` an `t.points`), die Ebenen in `MapLibreLineCache` und
    die Deckung im Blatt (`OfficialSignposts`).
  - **Die Ebenen nach Kennung, nicht nach Position**
    (`lib/features/map/map_view/keyed_layers.dart`): Das Paket gleicht
    `MapLibreMap.layers` nach dem INDEX ab — eine vorn eingefügte Ebene
    (Leuchtrand beim Antippen, Genauigkeitskreis, eine neue Stilgruppe,
    weil ein Trail beim Speichern blass wird) ließ es JEDE folgende neu
    übertragen und neu anlegen. Die Engine gibt dem Paket deshalb
    `layers: const []` und gleicht selbst ab: Kennung je Stil und Fach
    (`line:<Stil>#<Fach>:<Teil>`, `labels#<Fach>`, `poly:…`, `circle:<i>`),
    fester Platz (`maplibre-source/layer-<slot>`), neu = unter die
    nächste vorhandene Ebene, geändert = nur die Quelle (oder bei anderem
    Stil die Ebene an ihrer Stelle), weg = entfernen. `onStyleLoaded`
    (auch nach `setStyle`) setzt zurück und legt alles neu an; ein
    gescheiterter Schritt wird gemeldet und beim nächsten Abgleich unter
    neuem Platz neu angelegt. **Fächer** (`kLineBuckets` = 8,
    `lineBucketOf`: erster Punkt, gemischt gehasht — eine bloße Summe legte
    regelmäßig liegende Linien alle in ein Fach): Eine Änderung überträgt
    ein Achtel einer Farbe, nicht die Farbe. `keyed_layers_test.dart`
    prüft Plan und Ausführung gegen einen mitschreibenden Stil; die
    Platform-View selbst sieht nur das Gerät.
  - **Die Kopie in Häppchen, nacheinander, nicht abgewartet**
    (`encodeTrailCacheInSlices`, 4 ms je Häppchen, dazwischen ein Takt der
    Ereignisschleife; `FileTrailCache` reiht Schreiben und Löschen
    hintereinander, ein überholtes Schreiben fällt weg, ein Löschen beim
    Abmelden gewinnt). Kein Isolate: Das Kopieren des Stands hinüber
    kostete wieder den Haupt-Thread, und in der Test-Zone antwortet keins
    (hier beim Messen erneut gesehen). `fetchWithCache` wartet nicht mehr
    darauf — die Kopie ist für das NÄCHSTE Mal.
  Offen, bewusst: Ein GANZES Neuladen (Start, Zurückkehren des Netzes,
  Ausgangskorb) liest und parst das Netz weiter auf dem Haupt-Thread
  (0,3 s bei 600 Trails); die Karte überträgt danach dank Teilen nichts.
- **Beendigungsgründe** (#40, seit 0.21.0; PilzBuddy #147/#394 als
  Vorlage): Beim Start liest die App über den MethodChannel
  `de.mcbuchi.trailbuddy/exit_info` (`kExitInfoChannel`) Androids eigene
  Historie (`getHistoricalProcessExitReasons`, ab Android 11, keine
  Berechtigung) und meldet ANR, Absturz, nativen Absturz, Speicher-Kill
  nach `error_reports` — Kontext `App-Ende`, `created_at` ist der
  TODESzeitpunkt. Beim ANR mit dem Haupt-Thread-Abschnitt des Dumps, beim
  nativen Absturz mit dem Tombstone (ab API 31), das **in Dart gelesen
  wird** (`lib/data/tombstone.dart`, wirft nie), nicht in Kotlin:
  `MainActivity.kt` ist die einzige Datei ohne Test-Netz und reicht die
  Bytes nur durch; der Manifest-Test verbietet dort ein
  `Tombstone.parseFrom`. Normale Beendigungen (`USER_REQUESTED`,
  `EXIT_SELF` …) werden NICHT gemeldet, sonst füllt jedes Wegwischen den
  Digest. Ein Merker im App-Verzeichnis (`last_exit_report`) verhindert
  Doppelmeldungen; sein Verlust kostet eine doppelte Zeile.
  `getRss()`/`getPss()` liefern kB, `AppExit.summary` rechnet EINMAL in
  MB um, und 0 heißt „nicht gemessen", nicht „0 MB". Web und Android < 11
  liefern nichts. Tests: `test/exit_reporting_test.dart`,
  `test/tombstone_test.dart`.
