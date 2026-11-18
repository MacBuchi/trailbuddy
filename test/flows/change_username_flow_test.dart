// Benutzername ändern.
//
// Der Name ist eine suchbare Identität (Buddy-Suche), und er ist auch
// über Groß-/Kleinschreibung hinweg einmalig. Der Fake spiegelt genau
// das; den echten Beweis führt der unique-Index in der Datenbank.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

Future<void> _openDialog(WidgetTester tester) async {
  await openProfilePage(tester, 'account');
  final tile = find.text('Benutzername ändern');
  await scrollTo(tester, tile);
  await tester.tap(tile);
  await settle(tester);
}

Finder get _field => find.widgetWithText(TextField, 'Neuer Benutzername');

/// Text INNERHALB des Dialogs — der Bildschirm dahinter redet mit.
Finder dialogText(String part) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.textContaining(part),
);
Finder get _saveButton => find.widgetWithText(FilledButton, 'Speichern');

void main() {
  testWidgets('Umbenennen greift wirklich — im Profilkopf und im Backend', (
    tester,
  ) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testrail');
    backend.signInAs(me.id);
    await pumpApp(tester, backend);
    await _openDialog(tester);

    await tester.enterText(_field, 'flowtrailer');
    await settle(tester);
    await tester.tap(_saveButton);
    await settle(tester);

    // Der Effekt, nicht nur der Aufruf.
    expect(backend.users.single.username, 'flowtrailer');
    expect(
      find.widgetWithText(TextField, 'Neuer Benutzername'),
      findsNothing,
      reason: 'Nach dem Speichern schließt der Dialog.',
    );
    // Die Kachel auf der Seite „Konto" zeigt den aktuellen Namen (seit
    // 0.41.0 steht sie nicht mehr unter dem Profilkopf).
    for (var i = 0; i < 6 && find.text('flowtrailer').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 400));
      await settle(tester, frames: 4);
    }
    expect(
      find.text('flowtrailer'),
      findsWidgets,
      reason:
          'Die Kachel muss den neuen Namen sofort zeigen — '
          'Read-after-write, kein alter Zwischenstand.',
    );
    await drainSnackbars(tester);
  });

  testWidgets('Der Knopf bleibt gesperrt für zu kurz und für unverändert', (
    tester,
  ) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testrail');
    backend.signInAs(me.id);
    await pumpApp(tester, backend);
    await _openDialog(tester);

    // Vorbefüllt mit dem aktuellen Namen: unverändert gibt es nichts zu
    // speichern.
    expect(tester.widget<FilledButton>(_saveButton).onPressed, isNull);

    await tester.enterText(_field, 'ab');
    await settle(tester);
    expect(
      tester.widget<FilledButton>(_saveButton).onPressed,
      isNull,
      reason: 'Mindestlänge wie bei der Registrierung.',
    );

    await tester.enterText(_field, 'abc');
    await settle(tester);
    expect(tester.widget<FilledButton>(_saveButton).onPressed, isNotNull);
  });

  testWidgets('Ein nur anders geschriebener Name ist vergeben', (tester) async {
    // Ohne die case-insensitive Prüfung stünden live zwei für Suchende
    // gleiche Konten in der Tabelle.
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testrail');
    backend.addUser(username: 'Flowtrailer');
    backend.signInAs(me.id);
    await pumpApp(tester, backend);
    await _openDialog(tester);

    await tester.enterText(_field, 'flowtrailer');
    await settle(tester);
    await tester.tap(_saveButton);
    await settle(tester);

    expect(
      find.text('Dieser Benutzername ist schon vergeben.'),
      findsOneWidget,
    );
    expect(
      backend.userById(me.id).username,
      'testrail',
      reason: 'Ein abgelehnter Wechsel darf nichts ändern.',
    );
  });

  testWidgets('Abbrechen ändert nichts', (tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testrail');
    backend.signInAs(me.id);
    await pumpApp(tester, backend);
    await _openDialog(tester);

    await tester.enterText(_field, 'anderername');
    await settle(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Abbrechen'));
    await settle(tester);

    expect(backend.users.single.username, 'testrail');
  });

  testWidgets('Eine Mailadresse lässt sich nicht als Name speichern', (
    tester,
  ) async {
    // Dieselbe Prüfung wie bei der Registrierung — und sie muss auch
    // hier stehen: Wer den Namen später ändert, hat dasselbe Feld und
    // dieselbe Verwechslungsgefahr.
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testrail');
    backend.signInAs(me.id);
    await pumpApp(tester, backend);
    await _openDialog(tester);

    await tester.enterText(_field, 'trailfreund@example.org');
    await settle(tester);

    // Der Grund steht AM FELD. Ein „Speichern", das ohne Erklärung tot
    // ist, sieht aus wie ein Fehler der App.
    //
    // Der Finder hängt am Dialog, nicht am Bildschirm: Im Profil
    // dahinter steht die Kachel „E-Mail-Adresse ändern", und die trägt
    // dieselben Wörter.
    expect(dialogText('E-Mail-Adresse'), findsOneWidget);
    expect(tester.widget<FilledButton>(_saveButton).onPressed, isNull);

    // Und mit einem echten Namen geht es sofort weiter — der Dialog
    // klemmt nicht fest.
    await tester.enterText(_field, 'flowtrailer');
    await settle(tester);
    expect(dialogText('E-Mail-Adresse'), findsNothing);
    expect(tester.widget<FilledButton>(_saveButton).onPressed, isNotNull);
  });
}
