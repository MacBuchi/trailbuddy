// E-Mail-Adresse ändern.
//
// Die Adresse ist die Konto-Identität: Buddy-Suche und Reset-Code hängen
// an ihr. Der Wechsel verlangt das aktuelle Passwort und die Codes aus
// BEIDEN Postfächern — der Fake spiegelt genau die Semantik, die gegen
// echtes GoTrue gemessen wurde: ein Code allein ändert nichts.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

Future<void> _openDialog(WidgetTester tester) async {
  await openProfilePage(tester, 'account');
  final tile = find.text('E-Mail-Adresse ändern');
  await scrollTo(tester, tile);
  await tester.tap(tile);
  await settle(tester);
}

Future<void> _requestChange(
  WidgetTester tester, {
  String password = 'geheim123',
  String newEmail = 'neu@example.org',
}) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'Aktuelles Passwort'),
    password,
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Neue E-Mail-Adresse'),
    newEmail,
  );
  await settle(tester);
  await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
  await settle(tester);
}

FakeBackend _signedIn() {
  final backend = FakeBackend();
  final me = backend.addUser(username: 'testrail', email: 'alt@example.org');
  backend.signInAs(me.id);
  return backend;
}

void main() {
  testWidgets('Der komplette Wechsel: Passwort, beide Codes, neue Adresse', (
    tester,
  ) async {
    final backend = _signedIn();
    await pumpApp(tester, backend);
    await _openDialog(tester);

    expect(
      find.text('Bisher: alt@example.org'),
      findsOneWidget,
      reason: 'Wovon gewechselt wird, muss dastehen.',
    );
    await _requestChange(tester);

    // Codephase: beide Codes, feste Beschriftung je Postfach.
    expect(find.textContaining('Zwei Mails sind unterwegs'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Code an die bisherige Adresse'),
      backend.emailChangeOldCode,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Code an die neue Adresse'),
      backend.emailChangeNewCode,
    );
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Bestätigen'));
    await settle(tester);

    expect(backend.users.single.email, 'neu@example.org');
    expect(find.text('Deine E-Mail-Adresse ist geändert.'), findsOneWidget);
    expect(
      backend.currentUserId,
      isNotNull,
      reason:
          'Der Wechsel bringt eine frische Sitzung — er darf '
          'niemanden aussperren.',
    );
    expect(
      find.text('neu@example.org'),
      findsOneWidget,
      reason:
          'Die Kachel muss die neue Adresse SOFORT zeigen — ohne den '
          'authState-Draht stünde die alte da, bis irgendetwas anderes '
          'neu baute.',
    );
    await drainSnackbars(tester);
  });

  testWidgets('Ein falsches aktuelles Passwort stößt nichts an', (
    tester,
  ) async {
    final backend = _signedIn();
    await pumpApp(tester, backend);
    await _openDialog(tester);

    await _requestChange(tester, password: 'falsch888');

    expect(find.text('Das aktuelle Passwort stimmt nicht.'), findsOneWidget);
    expect(
      backend.pendingEmailChange,
      isNull,
      reason:
          'Ohne Passwort keine Mails — sonst könnte ein gestohlenes '
          'Session-Token den Umzug anstoßen.',
    );
    expect(
      find.widgetWithText(TextField, 'Aktuelles Passwort'),
      findsOneWidget,
      reason: 'Der Dialog bleibt in der ersten Phase.',
    );
  });

  testWidgets('Eine vergebene Adresse wird beim Namen genannt', (tester) async {
    final backend = _signedIn();
    backend.addUser(username: 'anderer', email: 'belegt@example.org');
    await pumpApp(tester, backend);
    await _openDialog(tester);

    await _requestChange(tester, newEmail: 'belegt@example.org');

    expect(
      find.text('Für diese Adresse gibt es schon ein Konto.'),
      findsOneWidget,
    );
  });

  testWidgets('Ein Code allein ändert nichts — auch nicht mit einem '
      'falschen zweiten', (tester) async {
    final backend = _signedIn();
    await pumpApp(tester, backend);
    await _openDialog(tester);
    await _requestChange(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Code an die bisherige Adresse'),
      backend.emailChangeOldCode,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Code an die neue Adresse'),
      '000000',
    );
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Bestätigen'));
    await settle(tester);

    expect(find.textContaining('falsch oder abgelaufen'), findsOneWidget);
    expect(
      backend.users.single.email,
      'alt@example.org',
      reason:
          'Genau die Zusicherung von Secure email change: ein '
          'Postfach allein reicht nicht.',
    );
  });

  testWidgets('Abbrechen in der Codephase lässt die Adresse stehen', (
    tester,
  ) async {
    final backend = _signedIn();
    await pumpApp(tester, backend);
    await _openDialog(tester);
    await _requestChange(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Abbrechen'));
    await settle(tester);

    expect(backend.users.single.email, 'alt@example.org');
  });
}
