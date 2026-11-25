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
  `isAndroidApp`): Fahrt aufzeichnen und Sensor-Rohdaten, ganze Regionen,
  der Navigationsdienst, Push (`pushPlatformSupported` — ohne APNs und
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
  `Info.plist`. Kein Standort im Hintergrund, keine `UIBackgroundModes`,
  solange die Fahrt fehlt.
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
- **CI** (`ci.yml`, „Build iOS (Simulator)"): `flutter build ios
  --simulator --debug` auf `macos-latest`, danach STARTET der Job die App
  im jüngsten iPhone-Simulator (`integration_test/ios_start_smoke_test.dart`,
  ohne Zugangsdaten): Anmeldung erreicht, eigene Kanäle antworten, die
  Ordner sind angelegt und von der Sicherung ausgenommen. Kein
  Pflicht-Check, bis der Betreiber ihn in den Branch-Schutz nimmt.
- **iPhone 8 / iOS 16 geht mit Xcode 27 nicht** (#644, 2026-11-25):
  Xcode 27 debuggt und installiert nur ab iOS 17 („Pairing State:
  unsupported"), und ein Bericht nennt einen Startabsturz von
  Xcode-27-Builds auf iOS 16. Ein zweites Xcode daneben läuft auf dem
  Rechner des Betreibers nicht; Geräte-Tests laufen auf dem iPad Air 4
  (iOS 26) und im Simulator, das iPhone 8 erst über einen Build mit
  Xcode 26 (Xcode Cloud, braucht das bezahlte Konto).
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

