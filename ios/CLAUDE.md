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
  (Android: `${applicationId}://login-callback`). Die Berechtigungstexte
  sind bisher nur deutsch (offen: `InfoPlist.strings` je Sprache, A14).
  Kein Standort im Hintergrund, keine `UIBackgroundModes`, solange die
  Fahrt fehlt.
- **Das Symbol** erzeugt `tool/brand_icons.py` (eine Größe, 1024 px,
  randlos) — nie von Hand tauschen. Der Startschirm ist noch Flutters
  leere Vorlage.
- **CI** (`ci.yml`, „Build iOS (Simulator)"): `flutter build ios
  --simulator --debug` auf `macos-latest`. Ein Kompilier-Check, kein
  Beweis, dass die App dort läuft; kein Pflicht-Check, bis der Betreiber
  ihn in den Branch-Schutz nimmt.
- **Xcode 27 hat keine `Simulator.app` mehr** (es gibt `DeviceHub.app`).
  Starten und Bilder gehen über `xcrun simctl` (`install`, `launch`,
  `io … screenshot`); bedienen über einen Integrationstest
  (`flutter test integration_test/… -d <udid>`).
