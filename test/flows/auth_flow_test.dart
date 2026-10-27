// Szenarien rund um Anmeldung, Registrierung und Abmeldung —
// komplette App gegen das In-Memory-Backend (siehe test/fakes/).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/widgets/form_notice.dart';
import 'package:trailbuddy/features/map/map_screen.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

/// Führt eine Registrierung bis zur Code-Eingabe durch — der Vorlauf, den
/// die Tests mit Bestätigungspflicht alle brauchen.
Future<void> _signUpWithConfirmation(WidgetTester tester) async {
  await tester.tap(find.text('Noch kein Konto? Registrieren'));
  await settle(tester);
  await tester.enterText(
      find.widgetWithText(TextField, 'Benutzername'), 'neuertrail');
  await tester.enterText(
      find.widgetWithText(TextField, 'E-Mail'), 'neu@example.org');
  await tester.enterText(
      find.widgetWithText(TextField, 'Passwort (mind. 8 Zeichen)'),
      'geheim123');
  await tester.tap(find.text('Konto erstellen'));
  await settle(tester);
}

void main() {
  testWidgets('Ausgeloggt startet die App auf dem Login-Screen',
      (tester) async {
    final backend = FakeBackend();
    await pumpApp(tester, backend);

    expect(find.text('Anmelden'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'E-Mail'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('Falsches Passwort zeigt eine verständliche Fehlermeldung',
      (tester) async {
    final backend = FakeBackend()..addUser(username: 'testrail');
    await pumpApp(tester, backend);

    await tester.enterText(
        find.widgetWithText(TextField, 'E-Mail'), 'testrail@example.org');
    await tester.enterText(
        find.widgetWithText(TextField, 'Passwort'), 'falsches-passwort');
    await tester.tap(find.text('Anmelden'));
    await settle(tester);

    expect(find.text('E-Mail oder Passwort falsch.'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await drainSnackbars(tester);
  });

  testWidgets('Login mit richtigen Daten führt zur Karte', (tester) async {
    final backend = FakeBackend()
      ..addUser(username: 'testrail', password: 'TrailTest#2026!');
    await pumpApp(tester, backend);

    await tester.enterText(
        find.widgetWithText(TextField, 'E-Mail'), 'testrail@example.org');
    await tester.enterText(
        find.widgetWithText(TextField, 'Passwort'), 'TrailTest#2026!');
    await tester.tap(find.text('Anmelden'));
    await settle(tester);

    expect(find.byType(MapScreen), findsOneWidget);
    expect(backend.currentUserId, isNotNull);
  });

  testWidgets('Registrierung meldet direkt an und landet auf der Karte',
      (tester) async {
    final backend = FakeBackend();
    await pumpApp(tester, backend);

    await tester.tap(find.text('Noch kein Konto? Registrieren'));
    await settle(tester);
    expect(find.text('Konto erstellen'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Benutzername'), 'neuertrail');
    await tester.enterText(
        find.widgetWithText(TextField, 'E-Mail'), 'neu@example.org');
    await tester.enterText(
        find.widgetWithText(TextField, 'Passwort (mind. 8 Zeichen)'),
        'geheim123');
    await tester.tap(find.text('Konto erstellen'));
    await settle(tester);

    expect(find.byType(MapScreen), findsOneWidget);
    expect(backend.users.single.username, 'neuertrail');
    expect(backend.currentUserId, backend.users.single.id);
  });

  testWidgets('Vergebener Benutzername wird beim Registrieren abgefangen',
      (tester) async {
    final backend = FakeBackend()..addUser(username: 'testrail');
    await pumpApp(tester, backend);

    await tester.tap(find.text('Noch kein Konto? Registrieren'));
    await settle(tester);
    // Nur anders geschrieben ist trotzdem vergeben: Der Name ist auch über
    // Groß-/Kleinschreibung hinweg einmalig — für die Buddy-Suche wären
    // „TestRail" und „testrail" dasselbe Konto.
    await tester.enterText(
        find.widgetWithText(TextField, 'Benutzername'), 'TestRail');
    await tester.enterText(
        find.widgetWithText(TextField, 'E-Mail'), 'zweit@example.org');
    await tester.enterText(
        find.widgetWithText(TextField, 'Passwort (mind. 8 Zeichen)'),
        'geheim123');
    await tester.tap(find.text('Konto erstellen'));
    await settle(tester);

    expect(find.text('Dieser Benutzername ist schon vergeben.'), findsOneWidget);
    expect(backend.users, hasLength(1));
    await drainSnackbars(tester);
  });

  testWidgets('Eine Mailadresse als Benutzername wird abgefangen',
      (tester) async {
    // Leute tragen beim Benutzernamen aus Versehen ihre Mailadresse ein —
    // kein Wunder, das Mail-Feld liegt direkt darunter. Der Name ist aber
    // öffentlich, und die Buddy-Suche baut gerade darauf, dass Adressen
    // NICHT öffentlich sind.
    final backend = FakeBackend();
    await pumpApp(tester, backend);

    await tester.tap(find.text('Noch kein Konto? Registrieren'));
    await settle(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Benutzername'), 'neuer@example.org');
    await tester.enterText(
        find.widgetWithText(TextField, 'E-Mail'), 'neuer@example.org');
    await tester.enterText(
        find.widgetWithText(TextField, 'Passwort (mind. 8 Zeichen)'),
        'geheim123');
    await tester.tap(find.text('Konto erstellen'));
    await settle(tester);

    expect(find.textContaining('E-Mail-Adresse'), findsOneWidget);
    expect(backend.users, isEmpty,
        reason: 'abgefangen heißt: es entsteht kein Konto');
    await drainSnackbars(tester);
  });

  testWidgets('Login- und Registrier-Felder hängen in einer AutofillGroup',
      (tester) async {
    // Ohne AutofillGroup meldet Flutter die Felder nicht beim Autofill-Dienst
    // an — Passwortmanager sehen das Formular dann gar nicht.
    void expectInAutofillGroup(String label) {
      expect(
        find.ancestor(
          of: find.widgetWithText(TextField, label),
          matching: find.byType(AutofillGroup),
        ),
        findsOneWidget,
        reason: 'Feld „$label" braucht eine AutofillGroup',
      );
    }

    final backend = FakeBackend();
    await pumpApp(tester, backend);

    expectInAutofillGroup('E-Mail');
    expectInAutofillGroup('Passwort');

    await tester.tap(find.text('Noch kein Konto? Registrieren'));
    await settle(tester);

    expectInAutofillGroup('Benutzername');
    expectInAutofillGroup('E-Mail');
    expectInAutofillGroup('Passwort (mind. 8 Zeichen)');
  });

  testWidgets('Abmelden führt zurück zum Login-Screen', (tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testrail');
    backend.signInAs(me.id);
    await pumpApp(tester, backend);
    expect(find.byType(MapScreen), findsOneWidget);

    await openTab(tester, 'Profil');
    await tester.tap(find.byTooltip('Abmelden'));
    await settle(tester);

    expect(find.text('Anmelden'), findsOneWidget);
    expect(backend.currentUserId, isNull);
  });

  group('Mit Bestätigungspflicht (Confirm email an)', () {
    testWidgets('Registrierung endet im Hinweis statt stumm stehenzubleiben',
        (tester) async {
      // Ohne Behandlung liefert signUp keine Sitzung, der Router bewegt
      // sich nicht und der Screen bliebe wortlos stehen.
      final backend = FakeBackend()..requireEmailConfirmation = true;
      await pumpApp(tester, backend);
      await _signUpWithConfirmation(tester);

      expect(find.text('Fast geschafft!'), findsOneWidget);
      expect(find.textContaining('neu@example.org'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Code aus der Mail'),
          findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing,
          reason: 'Ohne bestätigte Adresse gibt es keine Sitzung.');
      expect(backend.confirmationMails, ['neu@example.org']);
      expect(backend.currentUserId, isNull);
    });

    testWidgets('Der Code aus der Mail bestätigt und meldet direkt an',
        (tester) async {
      final backend = FakeBackend()..requireEmailConfirmation = true;
      await pumpApp(tester, backend);
      await _signUpWithConfirmation(tester);

      await tester.enterText(
          find.widgetWithText(TextField, 'Code aus der Mail'),
          FakeBackend.signupCode);
      await tester.tap(find.text('Adresse bestätigen'));
      await settle(tester);

      expect(find.byType(MapScreen), findsOneWidget,
          reason: 'verifyOTP liefert die Sitzung gleich mit.');
      expect(backend.users.single.emailConfirmed, isTrue);
    });

    // #399: wie beim Passwort-Reset — ein Neuladen des Browsers ruft kein
    // `dispose`, der Merker bleibt und bringt die Code-Eingabe zurück.
    testWidgets('Nach einem Neuladen steht die Code-Eingabe wieder da',
        (tester) async {
      final backend = FakeBackend()..requireEmailConfirmation = true;
      final before = FakeSettings();
      await pumpApp(tester, backend, settings: before);
      await _signUpWithConfirmation(tester);
      final remembered = before.pendingAuthCode;
      expect(remembered, isNotNull);
      expect(remembered, isNot(contains('geheim123')));

      await tester.pumpWidget(const SizedBox());
      final after = FakeSettings(pendingAuthCode: remembered);
      await pumpApp(tester, backend, settings: after);
      // Der Login-Screen davor darf den Merker der Registrierung nicht
      // mitnehmen, wenn er beim Wechsel verschwindet.
      await tester.tap(find.text('Noch kein Konto? Registrieren'));
      await settle(tester);

      expect(find.text('Fast geschafft!'), findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextField, 'Code aus der Mail'),
          FakeBackend.signupCode);
      await tester.tap(find.text('Adresse bestätigen'));
      await settle(tester);

      expect(find.byType(MapScreen), findsOneWidget);
      expect(after.pendingAuthCode, isNull);
    });

    testWidgets('Ein falscher Code lässt niemanden herein', (tester) async {
      final backend = FakeBackend()..requireEmailConfirmation = true;
      await pumpApp(tester, backend);
      await _signUpWithConfirmation(tester);

      await tester.enterText(
          find.widgetWithText(TextField, 'Code aus der Mail'), '000000');
      await tester.tap(find.text('Adresse bestätigen'));
      await settle(tester);

      expect(find.textContaining('Code ist falsch oder abgelaufen'),
          findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(backend.currentUserId, isNull);
      await drainSnackbars(tester);
    });

    testWidgets('Die Bestätigungsmail lässt sich erneut anfordern',
        (tester) async {
      final backend = FakeBackend()..requireEmailConfirmation = true;
      await pumpApp(tester, backend);
      await _signUpWithConfirmation(tester);

      // Direkt nach der Registrierung ist gerade eine Mail rausgegangen —
      // der Knopf wartet erst einmal ab.
      expect(find.textContaining('Erneut senden in'), findsOneWidget);
      await passResendCooldown(tester);

      await tester.tap(find.text('Mail nicht angekommen? Erneut senden'));
      await settle(tester);

      expect(backend.confirmationMails, ['neu@example.org', 'neu@example.org']);
      await drainSnackbars(tester);
    });

    testWidgets('Erneut senden und falscher Code sehen verschieden aus',
        (tester) async {
      // Vorher lief beides durch dieselbe SnackBar — Erfolg und Fehler
      // sollen sich unterscheiden lassen.
      final backend = FakeBackend()..requireEmailConfirmation = true;
      await pumpApp(tester, backend);
      await _signUpWithConfirmation(tester);
      await passResendCooldown(tester);

      await tester.tap(find.text('Mail nicht angekommen? Erneut senden'));
      await settle(tester);
      expect(tester.widget<FormNotice>(find.byType(FormNotice)).tone,
          NoticeTone.success);

      await tester.enterText(
          find.widgetWithText(TextField, 'Code aus der Mail'), '000000');
      await tester.tap(find.text('Adresse bestätigen'));
      await settle(tester);
      expect(tester.widget<FormNotice>(find.byType(FormNotice)).tone,
          NoticeTone.error);
    });

    testWidgets('Zu häufiges Erneut-Senden nennt das Rate-Limit',
        (tester) async {
      // Der Fall darf nicht als „Anmeldung fehlgeschlagen" ankommen —
      // mitten in der Registrierung.
      final backend = FakeBackend()
        ..requireEmailConfirmation = true
        ..confirmationMailLimit = 1;
      await pumpApp(tester, backend);
      await _signUpWithConfirmation(tester);
      await passResendCooldown(tester);

      await tester.tap(find.text('Mail nicht angekommen? Erneut senden'));
      await settle(tester);

      expect(find.textContaining('bitte eine Minute warten'), findsOneWidget);
      expect(find.textContaining('Anmeldung fehlgeschlagen'), findsNothing);
    });

    testWidgets('Anmeldung ohne Bestätigung nennt den echten Grund',
        (tester) async {
      // „E-Mail oder Passwort falsch" würde hier an der falschen Stelle
      // suchen lassen — das Passwort stimmt ja.
      final backend = FakeBackend()
        ..addUser(
            username: 'unbestaetigt',
            password: 'TrailTest#2026!',
            emailConfirmed: false);
      await pumpApp(tester, backend);

      await tester.enterText(find.widgetWithText(TextField, 'E-Mail'),
          'unbestaetigt@example.org');
      await tester.enterText(
          find.widgetWithText(TextField, 'Passwort'), 'TrailTest#2026!');
      await tester.tap(find.text('Anmelden'));
      await settle(tester);

      expect(find.textContaining('bestätige zuerst deine E-Mail-Adresse'),
          findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await drainSnackbars(tester);
    });
  });
}
