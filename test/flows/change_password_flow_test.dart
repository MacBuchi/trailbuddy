// Passwort ändern für Angemeldete.
//
// Der Reset auf dem Login-Screen hilft nur, wer ausgesperrt ist. Wer drin
// ist, ändert hier — und muss dafür sein aktuelles Passwort nennen, weil im
// Dashboard „Secure password change" aktiv ist. Der Fake spiegelt das; den
// echten Beweis führt nur ein Lauf gegen GoTrue.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

/// Öffnet den Dialog aus dem Profil-Tab. Die Liste baut nur, was im Bild
/// ist — der Eintrag muss also erst herangescrollt werden, bevor es ihn
/// überhaupt gibt.
Future<void> _openDialog(WidgetTester tester) async {
  await openProfilePage(tester, 'account');
  final tile = find.text('Passwort ändern');
  await scrollTo(tester, tile);
  await tester.tap(tile);
  await settle(tester);
}

Future<void> _fill(
  WidgetTester tester, {
  required String current,
  required String neu,
  String? repeat,
}) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'Aktuelles Passwort'),
    current,
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Neues Passwort (mind. 8 Zeichen)'),
    neu,
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Neues Passwort wiederholen'),
    repeat ?? neu,
  );
  await settle(tester);
}

Finder get _saveButton => find.widgetWithText(FilledButton, 'Speichern');

FakeBackend _signedIn({String password = 'AlterTrail#2026!'}) {
  final backend = FakeBackend();
  final me = backend.addUser(username: 'testrail', password: password);
  backend.signInAs(me.id);
  return backend;
}

void main() {
  testWidgets('Der Knopf bleibt gesperrt, bis die Eingaben stimmen', (
    tester,
  ) async {
    final backend = _signedIn();
    await pumpApp(tester, backend);
    await _openDialog(tester);

    expect(
      tester.widget<FilledButton>(_saveButton).onPressed,
      isNull,
      reason: 'Leer darf nichts passieren.',
    );

    // Zu kurz — die Mindestlänge gilt hier wie beim Reset.
    await _fill(tester, current: 'AlterTrail#2026!', neu: 'kurz');
    expect(tester.widget<FilledButton>(_saveButton).onPressed, isNull);

    // Lang genug, aber die Wiederholung passt nicht.
    await _fill(
      tester,
      current: 'AlterTrail#2026!',
      neu: 'NeuerTrail#2026!',
      repeat: 'NeuerTrail#2026',
    );
    expect(tester.widget<FilledButton>(_saveButton).onPressed, isNull);
    expect(find.text('Passwörter stimmen noch nicht überein'), findsOneWidget);

    await _fill(tester, current: 'AlterTrail#2026!', neu: 'NeuerTrail#2026!');
    expect(tester.widget<FilledButton>(_saveButton).onPressed, isNotNull);
  });

  testWidgets('Mit dem richtigen aktuellen Passwort greift die Änderung', (
    tester,
  ) async {
    final backend = _signedIn();
    await pumpApp(tester, backend);
    await _openDialog(tester);

    await _fill(tester, current: 'AlterTrail#2026!', neu: 'NeuerTrail#2026!');
    await tester.tap(_saveButton);
    await settle(tester);

    // Der Effekt, nicht nur der Aufruf.
    expect(backend.users.single.password, 'NeuerTrail#2026!');
    expect(
      find.widgetWithText(TextField, 'Aktuelles Passwort'),
      findsNothing,
      reason: 'Nach dem Speichern schließt der Dialog.',
    );
    expect(
      backend.currentUserId,
      isNotNull,
      reason: 'Wer sein Passwort ändert, bleibt angemeldet.',
    );
    await drainSnackbars(tester);
  });

  testWidgets('Ein falsches aktuelles Passwort meldet genau das — und '
      'meldet niemanden ab', (tester) async {
    final backend = _signedIn();
    await pumpApp(tester, backend);
    await _openDialog(tester);

    await _fill(tester, current: 'FalscherTrail#1', neu: 'NeuerTrail#2026!');
    await tester.tap(_saveButton);
    await settle(tester);

    expect(find.text('Das aktuelle Passwort stimmt nicht.'), findsOneWidget);
    expect(backend.users.single.password, 'AlterTrail#2026!');
    expect(
      backend.currentUserId,
      isNotNull,
      reason:
          'Die erneute Anmeldung scheitert — die laufende Sitzung darf '
          'davon nicht mitgerissen werden.',
    );
  });

  testWidgets('Dasselbe Passwort noch einmal wird abgelehnt', (tester) async {
    final backend = _signedIn();
    await pumpApp(tester, backend);
    await _openDialog(tester);

    await _fill(tester, current: 'AlterTrail#2026!', neu: 'AlterTrail#2026!');
    await tester.tap(_saveButton);
    await settle(tester);

    expect(find.textContaining('bisherige Passwort'), findsOneWidget);
  });

  testWidgets('Ein bekannt unsicheres Passwort wird abgelehnt', (tester) async {
    final backend = _signedIn();
    await pumpApp(tester, backend);
    await _openDialog(tester);

    await _fill(tester, current: 'AlterTrail#2026!', neu: 'passwort123');
    await tester.tap(_saveButton);
    await settle(tester);

    expect(find.textContaining('zu unsicher'), findsOneWidget);
    expect(backend.users.single.password, 'AlterTrail#2026!');
  });
}
