// Anmelden bis zur Karte auf dem iOS-Simulator (#644): die echte App gegen
// das Live-Projekt, mit dem Testkonto des Betreibers. Kein CI-Test — ohne
// Zugangsdaten wird er übersprungen. Aufruf (siehe ios/CLAUDE.md):
//
//   flutter test integration_test/ios_signin_smoke_test.dart -d <udid> \
//     --dart-define=TB_MAIL=… --dart-define=TB_PW=…
//
// Geprüft wird: Login erscheint, Anmeldung führt zur Hülle, die Karte ist
// die MapLibre-Platform-View (kein Rückfall auf flutter_map) und beim
// Anlegen fliegt keine Ausnahme. Gegenprobe: falsches Passwort ⇒ der Test
// scheitert mit „E-Mail oder Passwort falsch." im Bild; `objective_c`
// 9.6.3 ⇒ Assertion aus `maplibre_ios` beim Anlegen der Karte.
//
// Achtung: `xcrun simctl io … screenshot` sieht die App dieses Laufs
// nicht; was zu sehen ist, sagen die Finder.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show FlutterMap;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre/maplibre.dart' as ml;
import 'package:trailbuddy/main.dart' as app;

const _mail = String.fromEnvironment('TB_MAIL');
const _pw = String.fromEnvironment('TB_PW');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Anmelden führt zur MapLibre-Karte',
    skip: _mail.isEmpty || _pw.isEmpty,
    (tester) async {
      await app.main();

      Future<bool> waitUntil(bool Function() ok, {int seconds = 40}) async {
        for (var i = 0; i < seconds * 4; i++) {
          if (ok()) return true;
          await tester.pump(const Duration(milliseconds: 250));
        }
        return ok();
      }

      Future<bool> waitFor(Finder f, {int seconds = 40}) =>
          waitUntil(() => f.evaluate().isNotEmpty, seconds: seconds);

      // Der erste Start braucht im Simulator gut 10 s bis zum Login.
      final fields = find.byType(TextField);
      // E-Mail und Passwort — vorher steht kurz nur ein Feld da.
      expect(
        await waitUntil(() => fields.evaluate().length >= 2),
        isTrue,
        reason: 'kein Login',
      );
      await tester.enterText(fields.at(0), _mail);
      await tester.enterText(fields.at(1), _pw);
      // Über die Eingabetaste des Passworts, nicht den Knopf: Die
      // Bildschirmtastatur des Simulators kann ihn verdecken.
      await tester.testTextInput.receiveAction(TextInputAction.done);

      // Beim ersten Start steht der Sicherheitshinweis vor der Karte.
      final safety = find.text('Verstanden');
      if (await waitFor(safety, seconds: 20)) {
        await tester.tap(safety.first);
      }

      final hasMap = await waitFor(find.byType(ml.MapLibreMap));
      final shown = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .whereType<String>()
          .join(' | ');
      expect(hasMap, isTrue, reason: 'keine MapLibre-Karte; im Bild: $shown');
      // Ein paar Sekunden laufen lassen: Die Platform View wird erst nach
      // dem ersten Bild angelegt, dort lag der Fehler mit objective_c 9.6.3.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.byType(UiKitView), findsOneWidget);
      expect(find.byType(FlutterMap), findsNothing, reason: 'Rückfall');
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
