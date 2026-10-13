// Die Kontexthilfe für neue Nutzer (#131, Plan `docs/konzept-onboarding.md`
// 3.1; Vorlage PilzBuddy #350, Baustein A).
//
// Festgehalten werden nicht Wortlaute, sondern drei Zusagen: Jeder
// Leerzustand führt in die Kurzanleitung; der leere Kartenzustand
// verschwindet mit dem ersten Trail von selbst; und die Kurzanleitung ist
// auch ohne Leerzustand erreichbar — wer Trails hat, sieht keinen mehr.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/help/help_screen.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';
import '../fakes/l10n_de.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testrail');
    backend.signInAs(me.id);
    return (backend, me);
  }

  final hint = find.byKey(const ValueKey('map-empty-hint'));

  testWidgets('Die leere Karte führt auf Tipp in die Kurzanleitung', (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);

    expect(hint, findsOneWidget);
    await tester.tap(hint);
    await settle(tester);
    expect(find.byType(HelpScreen), findsOneWidget);
    expect(find.text('Trails importieren'), findsOneWidget);

    // Zurück führt auf die Karte, nicht ins Profil (`push`).
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(hint, findsOneWidget);
  });

  testWidgets('Mit dem ersten Trail verschwindet der Hinweis', (tester) async {
    final (backend, me) = loggedInBackend();
    final trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    trails.seedTrail(me.id, name: 'Hang');
    await pumpApp(tester, backend, trails: trails);

    expect(hint, findsNothing);
  });

  testWidgets('Die Kurzanleitung steht im Profil und nennt sechs Schritte', (tester) async {
    final (backend, me) = loggedInBackend();
    final trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    trails.seedTrail(me.id, name: 'Hang');
    await pumpApp(tester, backend, trails: trails);

    await openProfilePage(tester, 'help');

    // Gescrollt statt geraten: Sechs Abschnitte passen auf keinen
    // Testschirm, und `ListView` baut nur, was in Sichtweite ist.
    final seen = <String>{};
    for (var i = 0; i < 10; i++) {
      for (final step in helpSteps(l10nDe)) {
        if (find
            .descendant(of: find.byType(HelpScreen), matching: find.text(step.title))
            .evaluate()
            .isNotEmpty) {
          seen.add(step.title);
        }
      }
      await tester.drag(find.byKey(const ValueKey('help-list')), const Offset(0, -250));
      await settle(tester, frames: 4);
    }
    expect(seen, containsAll(helpSteps(l10nDe).map((s) => s.title)));
  });

  testWidgets('Auf einem kleinen Telefon läuft nichts über', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openProfilePage(tester, 'help');
    for (var i = 0; i < 10; i++) {
      await tester.drag(find.byKey(const ValueKey('help-list')), const Offset(0, -250));
      await settle(tester, frames: 4);
    }
    expect(tester.takeException(), isNull);
  });

  for (final (label, open) in <(String, Future<void> Function(WidgetTester))>[
    ('Trails', (tester) => openTab(tester, 'Trails')),
    ('Buddys', (tester) => openTab(tester, 'Buddys')),
    ('Meine Fahrten', (tester) => openProfilePage(tester, 'rides')),
  ]) {
    testWidgets('Der Leerzustand von „$label" führt in die Kurzanleitung', (tester) async {
      final (backend, _) = loggedInBackend();
      await pumpApp(tester, backend);
      await open(tester);

      final link = find.byKey(const ValueKey('help-link'));
      await scrollTo(tester, link);
      await tester.tap(link);
      await settle(tester);
      expect(find.byType(HelpScreen), findsOneWidget);
    });
  }
}
