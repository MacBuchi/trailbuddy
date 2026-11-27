# TrailBuddy — Arbeitsregeln für `ios/`

Teil der Root-`CLAUDE.md` (Index dort). Der Fahrplan fürs iPhone ist
#644; dort stehen Befunde, Messungen und die offenen Pakete. Hier steht
nur, was man beim Arbeiten an `ios/` wissen muss.

## Technik-Notizen

- **Das Projekt** (#644, seit 0.203.0): `flutter create --platforms=ios`,
  Kennung `de.mcbuchi.trailbuddy` wie auf Android, Ziel **iOS 15.0** (die
  höchste Untergrenze der Plugins: Firebase; das iPhone 8 des Betreibers
  hat iOS 16). Plugins kommen über **Swift Package Manager**
  (`FlutterGeneratedPluginSwiftPackage`), nicht über CocoaPods: Unter
  CocoaPods scheitert MapLibre 0.3.7+1 an einem doppelten Header
  (`MapLibreIos.h`, Befund in #644, Werkzeug `tool/ios_map_bench.sh`);
  unter SPM baut die ganze App ohne Eingriff. Es gibt keine Flavors —
  `appFlavor` ist leer, also gilt der GitHub-Kanal, und `updateChecksApply`
  bleibt ohnehin Android.
- **Kein Signier-Team im Repo.** `flutter create` schreibt das Team aus
  dem Schlüsselbund in `project.pbxproj`; es ist wieder herausgenommen.
  Wer auf ein Gerät installiert, legt `ios/Flutter/Local.xcconfig` mit
  `DEVELOPMENT_TEAM = <Team-ID>` an (ignoriert, von `Debug`/`Release.xcconfig`
  per `#include?` gelesen). `test/ios_support_test.dart` wacht darüber.
  Mit dem kostenlosen persönlichen Team läuft eine Installation 7 Tage.
- **`flutter pub get` trägt `ios/**` in `analysis_options.yaml` ein**
  (das SPM-Gerüst unter `ios/Flutter/ephemeral` enthält Dart) — die Zeile
  bleibt stehen, sonst taucht sie bei jedem als Änderung auf.
- **Was iOS NICHT verspricht** (`lib/core/platform_support.dart`,
  `isAndroidApp`): ganze Regionen, Downloads im Hintergrund,
  Push (`pushPlatformSupported` — ohne APNs und
  `GoogleService-Info.plist`; `push_devices.platform` kennt nur `android`
  und `web`), „In Navi-App öffnen" (`geo:` gibt es dort nicht ⇒
  Zwischenablage). Vorher hieß überall `!kIsWeb` „Android". Wer eines
  davon auf iOS freischaltet, zeigt es vorher am Gerät (#644, Phase 3/4)
  und passt `test/ios_support_test.dart` an.
- **`Info.plist`**: Texte für Standort beim Benutzen, Kamera und Mediathek
  (fehlt einer, beendet iOS die App beim ersten Zugriff), Sprachen `de`
  und `en`, URL-Schema = Bundle-Kennung für den Anmelde-Rücksprung
  (Android: `${applicationId}://login-callback`). Die Texte stehen seit
  0.204.0 je Sprache in `de.lproj`/`en.lproj/InfoPlist.strings` (A14),
  `Info.plist` trägt die englische Fassung (Entwicklungssprache);
  `ios_support_test` verlangt in beiden Dateien dieselben Schlüssel wie
  `Info.plist`. `UIBackgroundModes` mit genau `location` (die Fahrt, seit
  0.205.0) und `audio` (die Ansagen, seit 0.206.0, Nachweis unten) und
  KEIN `NSLocationAlways…` — der Test wacht über beides; ein weiterer
  Modus kommt nur mit seinem Nachweis.
- **Datenschutz-Manifest** (`PrivacyInfo.xcprivacy`, seit 0.204.0):
  dieselben Datenarten wie die Datensicherheit in `docs/play-console.md`,
  kein Tracking, Gründe für UserDefaults (CA92.1) und Dateizeiten
  (C617.1). Die Gerätekennung kommt erst mit Push dazu. Wer eine Datenart
  ergänzt, ändert Manifest, Play-Tabelle und `ios_support_test` zusammen.
- **Das Symbol** erzeugt `tool/brand_icons.py` (eine Größe, 1024 px,
  randlos) — nie von Hand tauschen. **Das Startfenster** ist der Grund der
  App ohne Zeichen (`LaunchBackground.colorset` hell/dunkel =
  `@color/ground` auf Android, wie dort vor Android 12; Design 1p), danach
  zeichnet der Splash der App. `ios_support_test` hält die Farben gleich.
- **CI** (`ci.yml`, „Build iOS (Simulator)"): auf `macos-latest` baut
  und STARTET `flutter test` die App im jüngsten iPhone-Simulator
  (`integration_test/ios_start_smoke_test.dart`, ohne Zugangsdaten):
  Anmeldung erreicht, eigene Kanäle antworten, die Ordner sind angelegt
  und von der Sicherung ausgenommen. Vorher 19–20 min je Lauf
  (2026-11-26), deshalb: kein eigener `flutter build` davor (7 min, kaum
  weiterverwendet), der Simulator bootet nach dem
  Einrichten (parallel bremste er den 3-Kern-Runner), und auf PRs läuft
  der Job nur, wenn iOS betroffen ist (`ios/`, pubspec, Integrationstests,
  `ci.yml`, `main.dart`, Plattform-Weichen) — auf `main` immer. Ein reiner
  Dart-PR, der den Start auf iOS bricht, fällt also erst auf `main` auf.
  Ein Cache für Xcodes DerivedData half nicht (942 MB geladen, trotzdem
  alles neu gebaut — Flutter legt `ios/Flutter/ephemeral` je Lauf neu an).
  Was bleibt: Boot ~4 min, Xcode ~6 min, Test ~1 min.
  Kein Pflicht-Check, bis der Betreiber ihn in den Branch-Schutz nimmt.
- **iPhone 8 / iOS 16: bauen mit Xcode 27, aufspielen mit Xcode 26**
  (#644, am Gerät 2026-11-26, iOS 16.7.10): Xcode 27 sieht Geräte unter
  iOS 17 nicht („Pairing State: unsupported"), seine Builds (Ziel iOS
  15.0) starten dort aber — der gemeldete dyld-Absturz trat beim Start
  nicht auf, Anmeldung und Karte gingen. Xcode 26.6 lässt sich auf
  macOS 27 nicht über den Installer einrichten, das entpackte `.xip` läuft
  aber daneben (`/Applications/Xcode-26.6.app`, iOS-Plattform per
  `xcodebuild -downloadPlatform iOS`). Umgeschaltet wird mit
  `xcode-select -s`; mit Xcode 26 findet `flutter devices` das Gerät, und
  `flutter run --release` installiert (oder `ios-deploy` aus
  `bin/cache/artifacts` mit einem Build von Xcode 27). Vier Fallen:
  - **`DEVELOPER_DIR` reicht nicht**: `hooks_runner` startet die
    Native-Asset-Hooks (`objective_c`) ohne die Umgebung
    (`includeParentEnvironment: false`), `xcrun` fällt auf `xcode-select`
    zurück und mischt das SDK von Xcode 27 mit dem clang von Xcode 26
    („unknown architecture" in den `.tbd`). Nach dem Umschalten
    `.dart_tool/hooks_runner/shared/objective_c` löschen.
  - **Kein Selbststart nach der Installation**: Für iOS 16.7 fehlen die
    DeviceSupport-Symbole (legt sonst die Xcode-Oberfläche an), also von
    Hand antippen; im Release-Modus ohne Folgen.
  - **Entwicklermodus am Gerät und ein Konto in Xcode** (die Konten
    teilen sich beide Fassungen; einzutragen in Xcode 27). Ohne Konto:
    „No Accounts" und kein Profil.
  - **`flutter attach` bricht ab** („connection to device ended too
    early", 2026-11-27). Die App schreibt die Adresse ihres VM-Service ins
    Systemprotokoll (`pymobiledevice3 syslog live`, „VM service is
    listening on …"); `pymobiledevice3 usbmux forward <port> <port>` holt
    den Port, dann geht der Service direkt (Bildzeiten aus der Timeline,
    Messung in #644). Die Karte zeichnet MapLibre selbst: Flutter-Frames
    messen nur, was darüber liegt.
- **Xcode 27 hat keine `Simulator.app` mehr** (es gibt `DeviceHub.app`).
  Starten und Bilder gehen über `xcrun simctl` (`install`, `launch`,
  `io … screenshot`); bedienen über einen Integrationstest
  (`flutter test integration_test/… -d <udid>`).
- **Anmelden bis zur Karte im Simulator** (seit 0.203.1,
  `integration_test/ios_signin_smoke_test.dart`): die echte App gegen das
  Live-Projekt mit dem Testkonto des Betreibers (`--dart-define=TB_MAIL`,
  `TB_PW`; ohne beide übersprungen, kein CI-Test). Prüft Login → Hülle →
  MapLibre-Platform-View ohne Rückfall auf flutter_map und ohne Ausnahme.
  Gegenproben (2026-11-25, iPhone 17, iOS 26.2): falsches Passwort und
  `objective_c` 9.6.3 — beide rot. Drei Fallen:
  - **`objective_c` ab 9.6.4** (direkt in `pubspec.yaml`,
    `test/dependency_floor_test.dart`): Bis 9.6.3 schlägt dessen
    Debug-Prüfung `_isValid` im arm64-Simulator fehl
    (dart-lang/native#3786), sobald `maplibre_ios` seine Platform View
    oder den Kartenzwischenspeicher anlegt — die Anmeldung klappte, die
    Karte blieb leer. Das war der „Login erreicht die Karte nicht"-Befund
    vom 2026-11-24.
  - **Der erste Start braucht gut 10 s bis zum Login**, und kurz steht
    nur ein Feld da — warten, bis E-Mail UND Passwort stehen.
  - **Die Bildschirmtastatur verdeckt „Anmelden"**; der Test schickt die
    Eingabetaste des Passworts. `xcrun simctl io … screenshot` zeigt
    während `flutter test` den Home-Bildschirm, nicht die App — was zu
    sehen ist, sagen die Finder.
- **Plattform-Weichen stehen nur in `lib/core/platform_support.dart`**
  (#644, seit 0.204.0; `ios_support_test` sucht in `lib/` nach
  `TargetPlatform.android/iOS` und `Platform.isAndroid/isIOS`). Zwei Arten:
  `isAndroidApp`/`isIosApp` lesen `defaultTargetPlatform` (Zusagen der App,
  im Test umschaltbar), `hasAndroidChannels`/`hasIosChannels` die Plattform
  des PROZESSES (`dart:io`, bedingter Import) — für Stellen, die einen
  eigenen nativen Kanal ansprechen. `flutter test` spielt Android, hat
  aber keine Kanäle: Mit `isAndroidApp` statt `Platform.isAndroid` fielen
  14 Flow-Tests an App-Links, Bildschirm und Garmin (beim Bau gefunden).
  Die Fähigkeits-Tabelle (Funktion × Android/iOS) steht in
  `ios_support_test`; wer etwas freischaltet, ändert dort die Spalte.
- **Keine iCloud-Sicherung von Fahrten, Korb und Zwischenspeichern**
  (#644, seit 0.204.0): iOS sichert `Application Support` ab Werk. EINE
  Liste in `lib/core/backup_exclusions.dart` (= die `file`-Einträge von
  `backup_rules.xml`, Test), `main()` schickt sie ohne Warten an
  `BackupExclusion.swift`, das die Ordner ANLEGT und `isExcludedFromBackup`
  setzt — ein Ordner, den es noch nicht gibt, trägt kein Merkmal, und vor
  der Anmeldung legt niemand sie an. **MapLibres Zwischenspeicher**
  (`<Bundle-ID>/.mapbox/cache.db`) nimmt MapLibre Native selbst aus
  (nachgewiesen: frische Installation ohne eigenen Eintrag). Zwei Fallen
  der Abfrage `notExcluded`: Das Merkmal steht am Ordner, nicht an der
  Datei darin (die Suche geht nach oben), und nur bis zum Container der
  App — darüber liegt im Simulator der Mac, dessen Simulator-Ordner selbst
  ausgenommen sind (die Prüfung sagte sonst immer ja). **Offen:**
  Sitzungs-Token und Einstellungen liegen in den `NSUserDefaults` und
  gehen mit in die Sicherung (Datenschutzerklärung sagt es; Schlüsselbund
  ist eine eigene Entscheidung in #644).
- **Der Anfragezähler auf iOS** (#596 H7, #644, seit 0.204.0):
  `HostRequestCounter.swift` hängt ein `URLProtocol` in MapLibres
  Sitzung (`MLNNetworkConfiguration.sharedManager.sessionConfiguration`,
  über die Laufzeit — der Runner bindet das Modul `MapLibre` nicht selbst
  ein). Derselbe Kanal und dieselbe Antwort wie `HostRequestCounter.kt`,
  dazu `install`/`installed`. Eingehängt aus `main()` im Debug-Build
  (`installNativeHostCounter`, vor `runApp`), sichtbar unter Profil →
  „Entwicklung" (`devToolsVisibleProvider`: auch iOS-Debug). **`#if DEBUG`
  greift im Runner nicht** — `SWIFT_ACTIVE_COMPILATION_CONDITIONS` ist
  nur im Testziel gesetzt; deshalb entscheidet Dart. Der Smoke-Test mit
  Testkonto prüft, dass MapLibre gezählt wird (Gegenprobe ohne `install`:
  rot).
- **Neue Dateien im Xcode-Projekt**: `project.pbxproj` hat zwei
  Sources- und zwei Resources-Phasen (App und `RunnerTests`); eine Datei
  in der Phase des Testziels baut, aber der App fehlt sie („Cannot find
  … in scope" erst beim nächsten vollständigen Bau). Die Phasen der App
  sind `97C146EA…` (Sources) und `97C146EC…` (Resources).
  `ios_support_test` prüft, dass jede eigene Datei dort steht.
- **Der GPX-Import auf iOS** (#644, seit 0.204.0): `file_selector_ios`
  liest nur UTIs und WARF bei einer Gruppe nur mit `mimeTypes` — der
  Import öffnete nie. Eine Gruppe für beide (`gpxPickerTypeGroups`:
  `*/*` für Android, `public.data` für iOS);
  `test/trails/gpx_picker_types_test.dart` ruft die echten Plattformteile
  auf.
- **Fahrt aufzeichnen auf iOS** (#644 Paket 3, seit 0.205.0;
  `lib/features/rides/ride_location.dart`, Plan im Kommentar vom
  2026-11-26): derselbe Weg wie auf Android — `flutter_foreground_task`
  startet für `RideTaskHandler` eine ZWEITE Engine, `serviceTick`, Brücke,
  Logger und Fusion bleiben dieselben. Fünf Dinge, die man wissen muss:
  - **Wach hält den Prozess nur der Standortstrom**, nicht das Paket:
    Dessen iOS-Teil ist eine Engine mit `NSTimer`, ohne Hintergrundaufgabe.
    `HeldFix` hält in der Dienst-Engine EINEN `getPositionStream`
    (`AppleSettings`: `allowBackgroundLocationUpdates`,
    `showBackgroundLocationIndicator` = der blaue Hinweis als
    Offenlegung, `pauseLocationUpdatesAutomatically: false`, `fitness`),
    begonnen in `onStart` — also im Vordergrund, sonst verweigert „Beim
    Benutzen" den Hintergrund. Der Takt liest den letzten frischen Punkt
    (≤ 10 s, jeden einmal) statt eines Einzel-Fixes. `geolocator_apple`
    hält je Engine einen Strom: Der Sensor-Logger bekommt denselben, mit
    denselben Einstellungen (`rideLocationSettings`).
  - **Die Dienst-Engine braucht den Rückruf** `setPluginRegistrantCallback`
    in `AppDelegate` (vor `super.application`), sonst hat sie keine
    Plugins. `import flutter_foreground_task` geht unter SPM.
  - **Wegwischen beendet die Fahrt**: `applicationWillTerminate` zerstört
    den Task, der Prozess ist weg, iOS startet nichts neu (das ginge nur
    mit „Immer" und Ortswechsel-Diensten — nicht versprochen). Die Leiste
    beim Start sagt es (`rideStartedIos`); beim nächsten Start nimmt
    `restore()` die Fahrt auf und meldet die Lücke ab `kRideGapNotice`
    (2 min, plattformübergreifend).
  - **Keine Meldung des Pakets** (`IOSNotificationOptions(showNotification:
    false)`): Sie wäre nur ein Banner. Die Mitteilungen unterwegs kommen
    über `flutter_local_notifications` (unten). Downloads (`dataSync`)
    starten auf iOS keinen Dienst.
  - **Sensoren**: `sensors_plus` liefert auf iOS dieselbe Achse
    (Unix-µs aus Systemstart + Sensorzeit). Licht, Nähe und Messbereich
    gibt es nicht (`tb_ambient` leer, kein Kanal `…/sensors` —
    Core Motion nennt keinen Messbereich, also auch kein Swift-Gegenstück;
    `ios_support_test` wacht) — „unbekannt", wie auf Android ohne Sensor.
  Bank: `tool/ios_ride_bench.sh <udid>` (Testkonto aus der Umgebung,
  erfundene Strecke über `simctl location`, App N s hinter der
  Einstellungen-App, `integration_test/ios_ride_background_test.dart`
  prüft die Punkte im Fenster). Bildschirm an: `ScreenAwake.swift`
  (`isIdleTimerDisabled`), Kanal und Vertrag wie Kotlin.
- **Mitteilungen, Ansagen und Navigation unterwegs** (#644 Paket 3b, seit
  0.206.0; Plan im Kommentar vom 2026-11-27). Sechs Dinge, die man wissen
  muss:
  - **Knöpfe hängen an Kategorien, gesetzt NUR beim `initialize`**
    (`ride_notice_darwin.dart`): je Knopfsatz eine, mit den Kennungen der
    Android-Knöpfe (Test), Beschriftung aus `serviceL10n()` beim
    Einrichten. Jede `show` trägt `iOS: rideNoticeDarwin(…)` — ohne käme die
    Mitteilung ohne Knöpfe. Nur „Ändern…" öffnet die App (`foreground`).
  - **Die Erlaubnis erst beim Start einer Fahrt**: `initialize` fragte ab
    Werk sofort (`request*Permission` = `true`), also beim App-Start —
    alle drei stehen auf `false`. `RideNotifier.start` fragt nach dem
    Standort (`rideNoticePermissionProvider`, Hinweis + Ton); eine
    Ablehnung hält die Fahrt nicht auf, dann fragt das Zerlege-Blatt.
  - **Ein Knopf ohne „App öffnen" antwortet in einer DRITTEN Engine** —
    der von `flutter_local_notifications` (`FlutterLocalNotificationsIsolate`),
    nicht im Dienst; wie auf Android ein eigenes Isolate. Dafür
    `FlutterLocalNotificationsPlugin.setPluginRegistrantCallback` und
    `UNUserNotificationCenter.current().delegate` in `AppDelegate`, beides
    vor `super.application`. Jede Engine außer dieser meldet das Plugin als
    App-Delegate an (App UND Dienst); am iPhone 8 (iOS 16.7, 2026-11-27)
    stand trotzdem jede Antwort GENAU EINMAL in der Fahrt („Trail ist
    frei" und „Stimmt" gesperrt gedrückt, App im Hintergrund). Die Knöpfe
    zeigt iOS erst nach etwa 1 s Halten auf EINER Mitteilung — Tippen
    öffnet die App, Wischen zeigt nur „Optionen"; ein Stapel geht beim
    ersten Halten nur auf.
  - **Die Stimme**: `packages/tb_voice/ios` (Swift, SPM), derselbe Kanal und
    Vertrag wie Java. `AVSpeechSynthesizer`, Sitzung je Satz `.playback` /
    `.voicePrompt` / `.duckOthers` + `.interruptSpokenAudioAndMixWithOthers`,
    danach frei mit `.notifyOthersOnDeactivation`. `TB-VOICE`-Zeilen im
    Systemprotokoll (Sitzung an oder Fehlercode, Beginn, Ende).
    **`UIBackgroundModes` `audio` ist nötig**: Im Simulator (iOS 26.2)
    bekam die Stimme die Sitzung im Hintergrund auch ohne ihn, am iPhone 8
    (iOS 16.7, 2026-11-27) nicht — jeder Satz bei gesperrtem Bildschirm
    endete mit `session error 561015905` (`'!pla'`, `cannotStartPlaying`),
    zu hören nur bei offener App. Mit `audio`: `session active
    app=background`, `start`, `done`, die Musik wird leiser und wieder
    laut. Der Simulator taugt für diese Frage also nicht.
  - **Navigation im Dienst** (`navServiceSupported`): derselbe gehaltene
    Strom wie die Fahrt (`HeldFix`, startet beim Tipp, also vorne). Ohne
    Benachrichtigung mit Rest und ohne „Navigation beenden" vom
    Sperrbildschirm — der Dienst hält den Takt und spricht, beendet wird
    in der App; Wegwischen beendet ihn (`restore` räumt auf).
  - **Die Bank** `tool/ios_ride_bench.sh --notice` (`TB_SERVICE_BENCH`,
    `lib/features/rides/service_bench.dart`, sonst eine Konstante): Der
    Dienst zeigt alle 30 s eine Frage an einen erfundenen Trail und spricht
    einen Satz; gefragt wird „vorläufig" (kein Dialog, den keine Hand
    wegtippt). **Falle: Der Simulator führt Mitteilungen auch OHNE
    Erlaubnis in `getActiveNotifications`** (`auth=false`) — der Test prüft
    deshalb die Erlaubnis mit. Knöpfe drücken kann die Bank nicht (dazu
    bräuchte es eine Bedienhilfe wie AXe oder XCUITest); das bleibt dem
    Gerät.
- **Die Garmin-Uhr** (#644 Paket 4, seit 0.207.0; Plan im Kommentar vom
  2026-11-27, Konzept-Garmin §3): `GarminBridge.swift` mit Kanal und
  Vertrag von `GarminBridge.kt`, nur in der Engine der App (wie Kotlin in
  `MainActivity`). Fünf Dinge, die man wissen muss:
  - **Das SDK als Paket der App**, nicht als Plugin: Ein Plugin käme auch
    in die Engine des Dienstes, und zwei Instanzen meldeten sich beim
    Einzelstück `ConnectIQ.sharedInstance()` an. `project.pbxproj` trägt
    die Paket-Referenz mit `exactVersion` 1.8.0, beide `Package.resolved`
    den Stand (`ios_support_test`). `ConnectIQ.framework` ist dynamisch und
    wird von Xcode eingebettet; das `-ObjC` aus Garmins Anleitung gilt für
    statisches Linken und fehlt bewusst — meldet das Gerät „unrecognized
    selector", kommt es dazu.
  - **Der Rücksprung aus Garmin Connect** kommt über Flutters
    Szenen-Rückruf (`registrar.addSceneDelegate`, `openURLContexts`, beim
    Kaltstart `willConnectTo`), nicht über den eigenen `SceneDelegate`:
    `FlutterSceneDelegate` deklariert die Methoden nicht öffentlich, ein
    Swift-`override` mit `super` ginge nicht. Eigenes Schema
    `trailbuddy-ciq` (nicht das der Anmeldung); `LSApplicationQueriesSchemes`
    `gcm-ciq` für „ist Garmin Connect da?".
  - **Keine Bluetooth-Frage vor „Uhr verbinden"**: `startSdk()` nur in
    `pick`, nach einem Rücksprung oder mit gespeicherter Uhr
    (`Application Support/garmin/device`, `NSKeyedArchiver`, ohne
    iCloud-Sicherung). `NSBluetoothAlwaysUsageDescription` in Plist und
    beiden `InfoPlist.strings`.
  - **`bluetooth-central` ist NICHT im Plist** — nach der Regel aus 3b erst
    mit Nachweis am Gerät (Route und Ansagen an die Uhr bei gesperrtem
    Bildschirm, Fahrt der Uhr im Hintergrund, nur mit `location` wach).
  - **Kein Prüfstand**: Der Connect-IQ-Simulator koppelt nur über adb.
    Der Start-Smoke prüft nur „ohne Garmin Connect: `connect: false`, kein
    Lauschen, kein `pick`" (Gegenprobe ohne `register`: rot). Garmin
    Connect verlangt iOS 18.2 (2026-11-27) — auf dem iPhone 8 nicht
    installierbar; der Rest braucht ein neueres iPhone mit der fēnix 6S
    (Betreiber, 2026-11-27).
