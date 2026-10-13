// Der Sicherheitshinweis (#131, Plan `docs/konzept-onboarding.md` 3.1).
//
// Eine Auskunft, kein Haftungsausschluss: TrailBuddy zeigt, was du und
// deine Buddys gefahren sind — nicht, ob ein Weg befahren werden darf.
// Einmal beim ersten Start, danach nachlesbar in der Kurzanleitung und
// unter „Über TrailBuddy".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/widgets/safety_note.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';
import '../fakes/l10n_de.dart';

void main() {
  FakeBackend loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testrail');
    backend.signInAs(me.id);
    return backend;
  }

  testWidgets('Beim ersten Start steht er da — und lässt sich weder '
      'wegtippen noch mit Zurück schließen', (tester) async {
    final settings = FakeSettings(safetyNoteSeen: false);
    await pumpApp(tester, loggedInBackend(), settings: settings);

    expect(find.text('Kurz vorweg'), findsOneWidget);
    expect(find.textContaining('eigene Verantwortung'), findsOneWidget);

    // Danebentippen darf ihn nicht schließen: Ein Hinweis, den ein
    // Fehlgriff wegräumt, ist nicht gezeigt worden.
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(find.text('Kurz vorweg'), findsOneWidget);

    // Die Zurück-Taste auch nicht.
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('Kurz vorweg'), findsOneWidget);

    await tester.tap(find.text('Verstanden'));
    await settle(tester);
    expect(find.text('Kurz vorweg'), findsNothing);
    expect(settings.safetyNoteSeen, isTrue, reason: 'einmal je Installation');
  });

  testWidgets('Beim zweiten Start nicht mehr', (tester) async {
    // Ein Hinweis, den man täglich wegklickt, wird zur Tapete. Dieselbe
    // Instanz wie beim ersten Start — so stellt der Harness den Neustart
    // nach.
    final settings = FakeSettings(safetyNoteSeen: false);
    await pumpApp(tester, loggedInBackend(), settings: settings);
    await tester.tap(find.text('Verstanden'));
    await settle(tester);

    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, loggedInBackend(), settings: settings);
    expect(find.text('Kurz vorweg'), findsNothing);
  });

  testWidgets('Ohne Anmeldung nicht — er gehört zur App, nicht zum Login',
      (tester) async {
    final settings = FakeSettings(safetyNoteSeen: false);
    await pumpApp(tester, FakeBackend(), settings: settings);
    expect(find.text('Kurz vorweg'), findsNothing);
    expect(settings.safetyNoteSeen, isFalse);
  });

  testWidgets('Dauerhaft nachlesbar in der Kurzanleitung', (tester) async {
    await pumpApp(tester, loggedInBackend());
    await openProfilePage(tester, 'help');

    expect(find.byType(SafetyNoteTile), findsOneWidget);
    expect(find.textContaining('Sperrungen'), findsOneWidget);
  });

  testWidgets('… und unter „Über TrailBuddy", als Dialog', (tester) async {
    await pumpApp(tester, loggedInBackend());
    await openProfilePage(tester, 'about');
    final row = find.byKey(const ValueKey('about-safety-note'));
    await scrollTo(tester, row);
    await tester.tap(row);
    await settle(tester);

    expect(find.widgetWithText(AlertDialog, l10nDe.safetyNoteTitle), findsOneWidget);
    expect(find.text(l10nDe.safetyNote), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await settle(tester);
    expect(find.text(l10nDe.safetyNote), findsNothing);
  });
}
