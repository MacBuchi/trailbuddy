// Konto-Löschung: Bestätigung, Kaskade und der Weg zurück zum Login.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

Future<void> _openProfileBottom(WidgetTester tester) async {
  await openProfilePage(tester, 'account');
  // Bis ans Listenende scrollen — `scrollUntilVisible` schiebt den Eintrag
  // nur knapp ins Bild, wo er die untere Navigationsleiste überlappt.
  for (var i = 0; i < 6; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await settle(tester, frames: 4);
  }
}

void main() {
  testWidgets('Löschen entfernt Konto und alle abhängigen Daten', (
    tester,
  ) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testrail');
    final freund = backend.addUser(username: 'lilli92');
    backend.signInAs(me.id);
    backend.addFriendship(freund.id, me.id, status: 'accepted');
    backend.aliases[(owner: me.id, friend: freund.id)] = 'Lilli';
    await pumpApp(tester, backend);

    await _openProfileBottom(tester);
    await tester.tap(find.text('Konto löschen'));
    await settle(tester);
    expect(find.text('Konto endgültig löschen?'), findsOneWidget);

    // Solange der Benutzername nicht stimmt, bleibt der Knopf gesperrt.
    final deleteButton = find.widgetWithText(FilledButton, 'Endgültig löschen');
    expect(tester.widget<FilledButton>(deleteButton).onPressed, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, 'Benutzername'),
      'testrail',
    );
    await settle(tester, frames: 3);
    expect(tester.widget<FilledButton>(deleteButton).onPressed, isNotNull);

    await tester.tap(deleteButton);
    await settle(tester);

    // Kaskade wie im Schema: Nutzer, Freundschaften und Aliase sind weg …
    expect(backend.users.any((u) => u.id == me.id), isFalse);
    expect(backend.friendships, isEmpty);
    expect(backend.aliases, isEmpty);
    // … der Freund selbst bleibt natürlich bestehen.
    expect(backend.users.single.username, 'lilli92');
    // … und die App landet abgemeldet auf dem Login.
    expect(backend.currentUserId, isNull);
    expect(find.text('Anmelden'), findsOneWidget);
  });

  testWidgets('Falscher Benutzername löscht nichts', (tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testrail');
    backend.signInAs(me.id);
    await pumpApp(tester, backend);

    await _openProfileBottom(tester);
    await tester.tap(find.text('Konto löschen'));
    await settle(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Benutzername'),
      'testrailz',
    );
    await settle(tester, frames: 3);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Endgültig löschen'),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('Abbrechen'));
    await settle(tester);

    expect(backend.users, hasLength(1));
    expect(backend.currentUserId, me.id);
  });
}
