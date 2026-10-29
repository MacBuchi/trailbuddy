// Anmelden über Google & Co. (#398) — komplette App gegen das
// In-Memory-Backend. Der echte Weg (Browser, Anbieter, Rücksprung,
// PKCE-Tausch) liegt in supabase_flutter und braucht die Anbieter-Apps;
// hier geht es um das, was die App daraus macht: welche Knöpfe sie zeigt,
// welchen Anbieter sie ruft, und wie das Konto danach aussieht.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/data/auth_repository.dart';
import 'package:trailbuddy/features/map/map_screen.dart';
import 'package:trailbuddy/features/profile/profile_screen.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

Finder _button(SignInProvider p) => find.byKey(ValueKey('signin-${p.name}'));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

void main() {
  testWidgets('Ohne freigegebenen Anbieter sieht der Login aus wie zuvor',
      (tester) async {
    await pumpApp(tester, FakeBackend());

    expect(find.text('oder weiter mit'), findsNothing);
    for (final p in SignInProvider.values) {
      expect(_button(p), findsNothing);
    }
  });

  testWidgets('Nur die freigegebenen Anbieter bekommen einen Knopf, in Login '
      'und Registrierung', (tester) async {
    final backend = FakeBackend()
      ..enabledSignInProviders = {SignInProvider.github, SignInProvider.google};
    await pumpApp(tester, backend);

    expect(find.text('oder weiter mit'), findsOneWidget);
    expect(_button(SignInProvider.google), findsOneWidget);
    expect(_button(SignInProvider.github), findsOneWidget);
    expect(_button(SignInProvider.apple), findsNothing);
    expect(_button(SignInProvider.facebook), findsNothing);
    expect(find.byTooltip('Weiter mit Google'), findsOneWidget);
    // Reihenfolge wie im Enum, nicht wie in der Antwort: Google vor GitHub.
    expect(tester.getTopLeft(_button(SignInProvider.google)).dx,
        lessThan(tester.getTopLeft(_button(SignInProvider.github)).dx));

    await _tap(tester, find.text('Noch kein Konto? Registrieren'));
    expect(_button(SignInProvider.google), findsOneWidget);
    expect(_button(SignInProvider.github), findsOneWidget);
  });

  testWidgets('Ohne Netz gibt es nur die E-Mail', (tester) async {
    final backend = FakeBackend()
      ..enabledSignInProviders = {SignInProvider.google}
      ..offline = true;
    await pumpApp(tester, backend);

    expect(find.text('oder weiter mit'), findsNothing);
    expect(_button(SignInProvider.google), findsNothing);
  });

  testWidgets('Neues Konto über Google: Karte, einmal der Name, im Konto kein '
      'Passwort', (tester) async {
    final backend = FakeBackend()
      ..enabledSignInProviders = {SignInProvider.google};
    final settings = FakeSettings();
    await pumpApp(tester, backend, settings: settings);

    await _tap(tester, _button(SignInProvider.google));

    expect(backend.providerSignIns, [SignInProvider.google]);
    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.textContaining('Dein Benutzername ist trailbuddy_'),
        findsOneWidget);
    expect(settings.usernameHintSeen, isTrue);

    await _tap(tester, find.text('Ändern'));
    expect(find.byType(AccountScreen), findsOneWidget);
    expect(find.text('Angemeldet über Google'), findsOneWidget);
    expect(find.textContaining('neu@example.org'), findsOneWidget);
    expect(find.text('Passwort ändern'), findsNothing,
        reason: 'Ein Konto über einen Anbieter hat kein Passwort — der '
            'Dialog verlangte das aktuelle und käme nie durch.');
  });

  testWidgets('Der Namenshinweis kommt nur einmal', (tester) async {
    final backend = FakeBackend()
      ..enabledSignInProviders = {SignInProvider.apple};
    await pumpApp(tester, backend,
        settings: FakeSettings(usernameHintSeen: true));

    await _tap(tester, _button(SignInProvider.apple));

    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.textContaining('Dein Benutzername ist'), findsNothing);
  });

  testWidgets('Dieselbe Adresse wie ein E-Mail-Konto landet in diesem Konto',
      (tester) async {
    final backend = FakeBackend()
      ..addUser(username: 'testrail', email: 'testrail@example.org')
      ..enabledSignInProviders = {SignInProvider.microsoft}
      ..providerEmail = 'testrail@example.org';
    await pumpApp(tester, backend);

    await _tap(tester, _button(SignInProvider.microsoft));

    expect(backend.users, hasLength(1), reason: 'kein zweites Konto');
    expect(backend.currentUserId, backend.users.single.id);
    expect(find.textContaining('Dein Benutzername ist'), findsNothing,
        reason: 'den Namen hat der Nutzer selbst gewählt');
  });

  testWidgets('Geht der Browser nicht auf, sagt die App es', (tester) async {
    final backend = FakeBackend()
      ..enabledSignInProviders = {SignInProvider.discord}
      ..providerLaunchFails = true;
    await pumpApp(tester, backend);

    await _tap(tester, _button(SignInProvider.discord));

    expect(find.text('Die Anmeldeseite von Discord ließ sich nicht öffnen. '
        'Versuch es noch einmal.'), findsOneWidget);
    expect(backend.currentUserId, isNull);
  });
}
