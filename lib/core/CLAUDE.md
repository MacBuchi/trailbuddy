# TrailBuddy — Arbeitsregeln für `lib/core/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Bewegung** (Design 1p–1t, seit 0.45.0, `lib/core/widgets/motion.dart`,
  `start_splash.dart`): Splash, Loader, Ring um den Punkt während der
  Fahrt, „zwei Spuren werden eine" beim Verbinden, atmender Rand bei
  neuem Hinweis (nur in der Liste — auf der Karte hieße Atmen, die
  Linien je Bild neu an MapLibre zu übertragen). Jede Animation liest
  `reduceMotion(context)` und zeigt dann das Endbild ohne Takt; die
  Keyframes stehen als pure Funktionen daneben und sind ohne Pixel
  geprüft. **Kurveneingänge klemmen**: `(1 − 0,7) / 0,3` ist in
  Gleitkomma 1,0000000000000002, und `Curve.transform` wirft darauf
  (im Test gefunden). Der Splash liegt ÜBER der App, immer im selben
  `Stack` — fiele der nach dem Splash weg, hinge die App um; der Test
  prüft das an einem Kind OHNE GlobalKey (mit einem wäre die Gegenprobe
  grün geblieben). Der Harness schaltet ihn ab
  (`startSplashEnabledProvider`), sonst schluckte er die ersten Tipps
  jedes Flow-Tests. **Die Uhr des Splashs ist gedeckelt** (#217, seit
  0.83.1, `splashAdvance`): je Bild höchstens `kSplashMaxStep` (50 ms) —
  ein `AnimationController` rechnet nach Wanduhr, und jedes Bild, das die
  Startarbeit darunter aufhielt, ließ die Zeichnung springen. Solange er
  deckt, steht die App in einem `Offstage` (immer DASSELBE, nur der
  Schalter wechselt): gebaut und ausgelegt wird sie, gerastert nicht.
  Danach steht das Bild `kSplashHold` (0,6 s) und blendet über
  `kSplashFade` (1 s) aus (#235); ein Tipp über `kSplashSkipFade`.
  Gemessen auf dem Gerät ist das NICHT — kein Gerät am Rechner; was die
  Startarbeit im Einzelnen kostet, zeigt erst ein Profil-Build. **Der Loader zeichnet je Durchlauf das GANZE
  Zeichen** (seit 0.65.1, `loaderAt`): einzeichnen, stehen, zurück in die
  Spur blenden, 1,4 s. Der Läufer davor zeigte nie das ganze Zeichen und
  wirkte langsam (Betreiber). Ausgeblendet wird nur über dem ganzen
  Zeichen — der Test prüft jeden Zeitpunkt, die Gegenprobe (Ausblenden
  0,3 s früher) ist rot. Und knapp unter 1 zählt als fertig: `t ·
  Periode` landet sonst bei 849,999… ms, und am Übergang fehlt ein
  Hauch vom letzten Strich (im Test gefunden).
- **Zurück nach Hierarchie** (#175, seit 0.76.0): Erst schließt, was
  oben liegt (Dialog, Blatt, Unterseite — der Navigator des Reiters bzw.
  der Wurzel-Navigator, go_router fragt sie in dieser Reihenfolge), auf
  der Karte danach Leiste, Planer und Auswahl (`PopScope` in
  `MapScreen`); an der Wurzel eines anderen Reiters führt Zurück auf die
  Karte (`PopScope` in `AppShell`, `router.dart`). Erst auf der Karte
  geht es an Android, und `MainActivity.popSystemNavigator` legt die App
  dann mit `moveTaskToBack` in den Hintergrund — ohne die Überschreibung
  ruft Flutter `finish()`, und die Karte startete von vorn. Der
  Manifest-Test liest die Kotlin-Zeilen,
  `test/flows/back_navigation_flow_test.dart` den Weg in Dart (Gegenprobe
  ohne die Regel: drei Tests rot).
- **Push** (#34, seit 0.23.0, Patch 008 und 014; PilzBuddy #277/#564 als
  Vorlage): eine Meldung, wenn ein Buddy einen Trail meldet (nur
  BESTÄTIGTE Meldungen, seit Patch 013) oder einen Hinweis schreibt —
  an die direkten Buddys des Autors, die
  den Trail und seinen Beitrag sehen (`app_internal.push_recipients`,
  Spiegel von `td_friend_select`/`notes_select`; je Buddy-Beziehung
  eine Zeile im Korb, keine Rechnung über alle, Konzept 12). Acht Dinge,
  die man wissen muss:
  - **Die Meldung trägt Inhalt, aber nie einen Ort** (seit 0.54.0,
    Patch 014, Betreiber 2026-09-30: „anonym genug"): Trailname, Name
    des Buddys, Statuswort und beim Hinweis dessen Text (140 Zeichen) —
    jeweils so, wie der EMPFÄNGER es sieht: `trail_name_for` spiegelt
    `Trail.displayName` (eigener Name, sonst der des ältesten sichtbaren
    Beitrags), `push_name_for` nimmt den Alias des Empfängers
    (`friend_aliases`, Besitzer = Empfänger), sonst den Benutzernamen.
    Nie eine Koordinate, nie der Zustand. Einzelner Anlass: „Anni meldet
    „Hang" als gesperrt" / „Anni zu „Hang"" + Text; mehrere an einem
    Trail: „„Hang": 1 Meldung und 1 Hinweis" / „von Anni und Ben";
    mehrere Trails: Anzahlen, „An 2 Trails · von …". Der Korb merkt sich
    dafür `sender_ids`, `events` und den jüngsten `note_id` (ein
    zurückgezogener Hinweis nimmt seine Zeile mit). Ziel bleibt die
    opake Kennung als `route` (`/trail/<uuid>`, bei mehreren
    `/trails`). Der Text steht an EINER Stelle, in `push_flush`;
    `tool/push_flush_check.sh` prüft ihn Wort für Wort, dazu dass kein
    fremder Alias und keine Koordinate in der Nutzlast steht.
    Datenschutzerklärung und Profil-Schalter sagen dasselbe.
  - **Entprellt**: (Empfänger, Art, Trail) ist der Schlüssel in
    `app_internal.push_outbox`, fünf Minuten Ruhe, gedeckelt auf 30
    Minuten; je Empfänger EINE Meldung je Lauf. Ein erneutes Melden
    desselben Status (nur `status_at`) löst nichts aus; zurück auf
    „offen" schon (die gute Nachricht). Privat heißt: niemand.
  - **Ohne Vault-Geheimnisse räumt `push_flush` nur ab** — die drei
    Geheimnisse (`push_functions_url`, `push_job_secret`,
    `push_service_key`) legt der Betreiber im SQL-Editor an (Anleitung in
    patch_008); die Function braucht `FCM_SERVICE_ACCOUNT` (base64) und
    `PUSH_JOB_SECRET` per `supabase secrets set`. `send-push` deployt
    NUR `deploy-functions.yml` (Repo-Secret `SUPABASE_ACCESS_TOKEN`,
    sonst sichtbar übersprungen) — der Schema Check spielt keine
    Functions ein. `tool/push_flush_check.sh` ruft den Versand im Dry
    Run WIRKLICH auf (zurückgerollt): PL/pgSQL prüft den Rumpf erst beim
    Aufruf, und live läuft er jede Minute.
  - **Firebase ist eingerichtet** (seit 0.37.0, Projekt
    `trailbuddy-6207b`, nur Cloud Messaging, ohne Analytics).
    `android/app/google-services.json` liegt im Repo — ihr Inhalt ist
    öffentlich (steckt in jeder APK), sie wird aus der Konsole GEHOLT,
    nie editiert; der Manifest-Test prüft den Paketnamen darin. Das
    Gradle-Plugin wird nur mit der Datei angewendet, ein Build ohne sie
    läuft weiter. Das Web liest Web-App und VAPID-Schlüssel aus
    `lib/core/push_config.dart` (öffentlich wie der Publishable Key;
    beide gehören zusammen gesetzt, Test). Fehlende Konfiguration ist
    kein Fehlerbericht (`isMissingFirebaseConfig`: `[core/…]` UND die
    native `PlatformException` „Failed to load FirebaseOptions" — die
    zweite kam bis 0.36.x in den Wochendigest). Der Versand braucht
    zusätzlich die Vault- und Function-Geheimnisse oben und ein deploytes
    `send-push`; ohne sie meldet der Testknopf einen Fehler, und der Job
    räumt nur ab. **Live eingerichtet seit 2026-09-29** (Testnachricht
    auf Android und im Web angekommen): Function-Secrets und Vault über
    die Management-API gesetzt, dasselbe Job-Geheimnis an beiden Stellen
    (liegt beim Betreiber, nie im Repo). Das Repo-Secret
    `SUPABASE_ACCESS_TOKEN` ist ein Token des Zweitkontos mit 7 Tagen
    Laufzeit — danach überspringt `deploy-functions.yml` sichtbar; ein
    neues Token braucht es erst, wenn sich `supabase/functions/` ändert.
    Probe ohne Meldung: `send-push` ohne Ausweis ⇒ 401, mit
    `x-push-secret` und `{"messages":[]}` ⇒ 200.
  - **Das Ziel ist eine Route, keine Seite**: `/trail/:id` setzt den
    Fokus-Wunsch (`mapFocusTrailProvider`) und landet auf der Karte; die
    Karte löst ihn beim Aufbau ODER sobald der Trail geladen ist
    (`_pendingFocus`) — beim Kaltstart aus einer Push kommt der Wunsch
    vor den Trails. Der Web-Worker öffnet die App unter `#/trail/<id>`.
    Erlaubnisliste in `push_routes.dart`; alles andere bleibt liegen.
  - **Der Schalter zeigt das ERGEBNIS, nicht den Wunsch**
    (`PushEnabledNotifier`): Ablehnung, Funkloch und fehlende
    Konfiguration bekommen je ihren Satz. Gemerkt wird nur das Token
    (`Settings.pushToken`); die Wahrheit ist die Zeile in `push_devices`
    (Token = Schlüssel, Kontowechsel zieht sie um).
  - **Android**: Kanal `trailbuddy_meldungen` (Manifest, `strings.xml`,
    `MainActivity.onCreate`, IMPORTANCE_HIGH — die Stufe lässt sich
    nachträglich NICHT ändern, wer sie ändern will, braucht eine neue
    ID), Symbol nur Alphakanal, Tönung `notification_color`. Der
    Manifest-Test hält alles zusammen. Im Vordergrund zeigt Android
    nichts — `PushListener` (in `app.dart`, über dem `UpdateGate`) zeigt
    die Leiste, erst `clearSnackBars`, dann zeigen.
  - **Web**: eigener Worker `web/push/firebase-messaging-sw.js` ohne
    Firebase-SDK, Scope `push/` (der Basis-Scope gehört `sw.js`), Fokus
    statt Sichtbarkeit und nur DIESE App (`APP_BASE`), Übergabe
    `trailbuddy-push` (`kPushBridgeType`, ein Test hält beide zusammen).
    `tool/check_push_worker.mjs` prüft ihn im echten Chrome (Job „Build
    Web"). `www.gstatic.com` ist `afterConsent` im Datenschutz-Wächter.
