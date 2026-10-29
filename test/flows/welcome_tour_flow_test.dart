// Die Karten-Tour beim ersten Start (#133, Plan `docs/konzept-onboarding.md`
// 3.3; Vorlage PilzBuddys `map_tour_flow_test.dart`, Startseite).
//
// Die Zusagen:
//
//   1. Beim ersten Start: Sicherheitshinweis, DANN im selben Start die
//      Willkommensseite (Abweichung von PilzBuddy, dort liegt ein Start
//      dazwischen — der Betreiber will „Hinweis vor der ersten Tour").
//   2. „Tour starten" führt der Reihe nach durch die Karten-Schritte,
//      danach ist sie gesehen und kommt nie wieder.
//   3. „Nicht jetzt" ist ein Gesehen (#417): beim nächsten Start nichts;
//      die Startseite sagt, wo die Tour liegt.
//   4. Die Startseite verlangt eine Wahl: ein Tipp daneben tut nichts,
//      Zurück heißt „Nicht jetzt".
//   5. Beides gesehen ⇒ nichts liegt über der Karte.
//   6. Am Ende der Willkommens-Tour kein Weg in die Kurzanleitung — ab
//      #136 geht die Kette in die Reiter weiter.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/coach/coach.dart';
import 'package:trailbuddy/features/help/map_tour.dart';
import 'package:trailbuddy/features/help/tour_intro_art.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';
import '../fakes/l10n_de.dart';

final intro = find.byKey(const ValueKey('coach-intro'));
final bubble = find.byKey(const ValueKey('coach-bubble'));

void main() {
  FakeBackend signedIn() {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testrail').id);
    return backend;
  }

  /// Die Schritte ohne Trail: Schild und Blatt fallen weg.
  final titles = [
    for (final s in welcomeTourScript(l10nDe).tourSteps)
      if (s.title != 'Das Schild am Anfang' && s.title != 'Das Blatt zum Trail') s.title
  ];

  testWidgets('erster Start: erst der Hinweis, dann im selben Start die '
      'Willkommensseite', (tester) async {
    final settings = FakeSettings(safetyNoteSeen: false, mapTourSeen: false);
    await pumpApp(tester, signedIn(), settings: settings);

    expect(find.text('Kurz vorweg'), findsOneWidget);
    expect(intro, findsNothing, reason: 'zwei Überlagerungen gleichzeitig wären keine');
    await tester.tap(find.text('Verstanden'));
    await settle(tester);

    expect(intro, findsOneWidget, reason: 'ohne einen Start dazwischen');
    expect(find.text('Willkommen bei TrailBuddy'), findsOneWidget);
    expect(find.text('Tour starten'), findsOneWidget);
  });

  testWidgets('„Tour starten": der Reihe nach, dann nie wieder', (tester) async {
    final settings = FakeSettings(mapTourSeen: false);
    await pumpApp(tester, signedIn(), settings: settings);
    expect(intro, findsOneWidget);
    // Die Tippsperre (400 ms nach jedem neuen Schritt).
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('coach-intro-start')));
    await settle(tester);

    for (final title in titles) {
      expect(find.descendant(of: bubble, matching: find.text(title)), findsOneWidget, reason: title);
      final last = title == titles.last;
      if (last) {
        expect(find.descendant(of: bubble, matching: find.text('Kurzanleitung')), findsNothing,
            reason: 'beim ersten Start geht es danach mit den Reitern weiter (#136)');
      }
      await tester.tap(find.descendant(of: bubble, matching: find.text(last ? 'Los geht\'s' : 'Weiter')));
      await settle(tester);
    }
    expect(settings.mapTourSeen, isTrue);
    expect(bubble, findsNothing);

    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, signedIn(), settings: settings);
    expect(intro, findsNothing);
  });

  testWidgets('„Nicht jetzt" ist gemerkt: beim nächsten Start nichts (#417)', (tester) async {
    final settings = FakeSettings(mapTourSeen: false);
    await pumpApp(tester, signedIn(), settings: settings);
    await settle(tester);
    expect(find.textContaining('im Profil unter „Kurzanleitung“'), findsOneWidget,
        reason: 'die Startseite sagt, wo die Tour später liegt');
    await tester.tap(find.byKey(const ValueKey('coach-intro-later')));
    await settle(tester);
    expect(intro, findsNothing);
    expect(settings.mapTourSeen, isTrue);

    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, signedIn(), settings: settings);
    await settle(tester);
    expect(find.text('Willkommen bei TrailBuddy'), findsNothing);
    expect(intro, findsNothing);
  });

  testWidgets('die Startseite verlangt eine Wahl: ein Tipp daneben tut '
      'nichts, Zurück heißt „Nicht jetzt"', (tester) async {
    final settings = FakeSettings(mapTourSeen: false);
    await pumpApp(tester, signedIn(), settings: settings);
    await settle(tester);
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    expect(intro, findsOneWidget);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await settle(tester);
    expect(intro, findsNothing);
    expect(settings.mapTourSeen, isTrue, reason: 'Zurück heißt „Nicht jetzt", und das ist gemerkt');
  });

  testWidgets('beides gesehen: nichts über der Karte', (tester) async {
    await pumpApp(tester, signedIn(),
        settings: FakeSettings(safetyNoteSeen: true, mapTourSeen: true));
    expect(find.text('Kurz vorweg'), findsNothing);
    expect(intro, findsNothing);
    expect(bubble, findsNothing);
  });

  testWidgets('aus der Kurzanleitung beginnt sie mit „Die Karte"', (tester) async {
    await pumpApp(tester, signedIn());
    await openProfilePage(tester, 'help');
    final start = find.byKey(const ValueKey('help-map-tour'));
    await tester.scrollUntilVisible(start, 300,
        scrollable: find.descendant(of: find.byKey(const ValueKey('help-list')), matching: find.byType(Scrollable)));
    await settle(tester);
    await tester.tap(start);
    await settle(tester);
    expect(find.text('Die Karte'), findsOneWidget);
    expect(find.text('Willkommen bei TrailBuddy'), findsNothing);
  });

  testWidgets('auf einem kleinen Schirm bleibt die Wahl im Bild', (tester) async {
    tester.view.physicalSize = const Size(360, 560) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, signedIn(), settings: FakeSettings(mapTourSeen: false));
    final start = tester.getRect(find.byKey(const ValueKey('coach-intro-start')));
    expect((Offset.zero & const Size(360, 560)).contains(start.bottomRight - const Offset(1, 1)), isTrue);
    expect(tester.takeException(), isNull);
  });

  group('das Bild der Willkommensseite', () {
    test('der Punkt fährt die Serpentine einmal ab und steht am Ziel', () {
      expect(introDriftAt(0), 0);
      expect(introDriftAt(0.05), 0, reason: 'ein Moment am Start');
      expect(introDriftAt(0.85), 1, reason: 'ein Moment am Ziel');
      expect(introDriftAt(1), 1);
      var last = 0.0;
      for (var t = 0.0; t <= 1; t += 0.01) {
        final v = introDriftAt(t);
        expect(v, inInclusiveRange(0, 1));
        expect(v, greaterThanOrEqualTo(last), reason: 'nie zurück, t=$t');
        last = v;
      }
    });

    testWidgets('bei reduzierter Bewegung steht das Endbild', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpApp(tester, signedIn(), settings: FakeSettings(mapTourSeen: false));
      expect(intro, findsOneWidget);
      // Kein Takt läuft: dasselbe Bild über Sekunden.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  });
}
