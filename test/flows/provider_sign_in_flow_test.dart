// Anmelden über Google & Co. (#398) — komplette App gegen das
// In-Memory-Backend. Der echte Weg (Browser, Anbieter, Rücksprung,
// PKCE-Tausch) liegt in supabase_flutter und braucht die Anbieter-Apps;
// hier geht es um das, was die App daraus macht: welche Knöpfe sie zeigt,
// welchen Anbieter sie ruft, und wie das Konto danach aussieht.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/data/auth_repository.dart';
import 'package:trailbuddy/features/auth/username_step.dart';
import 'package:trailbuddy/features/map/map_screen.dart';
import 'package:trailbuddy/features/profile/profile_screen.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

final _field = find.byKey(const ValueKey('username-step-field'));

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
    expect(_button(SignInProvider.microsoft), findsNothing);
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

  testWidgets('Neues Konto über Google: erst der Name, dann die Karte, im '
      'Konto kein Passwort', (tester) async {
    final backend = FakeBackend()
      ..enabledSignInProviders = {SignInProvider.google}
      ..providerMetadata = {'full_name': 'Erika Muster', 'name': 'Erika Muster'};
    final settings = FakeSettings();
    await pumpApp(tester, backend, settings: settings);

    await _tap(tester, _button(SignInProvider.google));

    expect(backend.providerSignIns, [SignInProvider.google]);
    expect(find.byType(UsernameStep), findsOneWidget);
    expect(find.byType(MapScreen), findsNothing,
        reason: 'vor der Karte, also auch vor Hinweis und Tour');
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.widget<TextField>(_field).controller!.text, isEmpty,
        reason: 'Der Klarname des Anbieters wird nie vorgeschlagen — der '
            'Benutzername ist öffentlich.');

    await tester.enterText(_field, 'erika');
    await settle(tester);
    await _tap(tester, find.text('Weiter'));

    expect(find.byType(MapScreen), findsOneWidget);
    final user = backend.userById(backend.currentUserId!);
    expect(user.username, 'erika');
    expect(settings.usernameStepDoneFor, {user.id});

    await openProfilePage(tester, 'account');
    expect(find.byType(AccountScreen), findsOneWidget);
    expect(find.text('Angemeldet über Google'), findsOneWidget);
    expect(find.textContaining('neu@example.org'), findsOneWidget);
    expect(find.text('Passwort ändern'), findsNothing,
        reason: 'Ein Konto über einen Anbieter hat kein Passwort — der '
            'Dialog verlangte das aktuelle und käme nie durch.');
  });

  testWidgets('Der Nutzername bei GitHub steht vorbelegt, die Adresse von '
      'Microsoft nicht', (tester) async {
    final backend = FakeBackend()
      ..enabledSignInProviders = {SignInProvider.github}
      ..providerMetadata = {'user_name': 'trailfox', 'full_name': 'Erika Muster'};
    await pumpApp(tester, backend);
    await _tap(tester, _button(SignInProvider.github));
    expect(tester.widget<TextField>(_field).controller!.text, 'trailfox');

    await tester.pumpWidget(const SizedBox());
    final backend2 = FakeBackend()
      ..enabledSignInProviders = {SignInProvider.microsoft}
      ..providerMetadata = {'preferred_username': 'erika@example.org'};
    await pumpApp(tester, backend2);
    await _tap(tester, _button(SignInProvider.microsoft));
    expect(tester.widget<TextField>(_field).controller!.text, isEmpty,
        reason: 'eine Adresse als öffentlicher Name — usernameProblem');
  });

  testWidgets('Ein vergebener Name sagt es am Schritt, die Karte bleibt zu',
      (tester) async {
    final backend = FakeBackend()
      ..addUser(username: 'trailfox', email: 'fox@example.org')
      ..enabledSignInProviders = {SignInProvider.github}
      ..providerMetadata = {'user_name': 'trailfox'};
    await pumpApp(tester, backend);
    await _tap(tester, _button(SignInProvider.github));

    await _tap(tester, find.text('Weiter'));

    expect(find.text('Dieser Benutzername ist schon vergeben.'), findsOneWidget);
    expect(find.byType(UsernameStep), findsOneWidget);
    expect(find.byType(MapScreen), findsNothing);
  });

  testWidgets('„Später" behält den vergebenen Namen und fragt dieses Konto '
      'nicht wieder', (tester) async {
    final backend = FakeBackend()
      ..enabledSignInProviders = {SignInProvider.microsoft};
    final settings = FakeSettings();
    await pumpApp(tester, backend, settings: settings);
    await _tap(tester, _button(SignInProvider.microsoft));

    await _tap(tester, find.text('Später'));

    expect(find.byType(MapScreen), findsOneWidget);
    final user = backend.userById(backend.currentUserId!);
    expect(user.username, startsWith('trailbuddy_'));

    // Neustart: kein Schritt mehr, und kein Warten auf das Profil.
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, backend, settings: settings);
    expect(find.byType(UsernameStep), findsNothing);
    expect(find.byType(MapScreen), findsOneWidget);
  });

  testWidgets('Ohne Entscheidung kommt der Schritt beim Neustart wieder',
      (tester) async {
    final backend = FakeBackend()
      ..enabledSignInProviders = {SignInProvider.discord};
    final settings = FakeSettings();
    await pumpApp(tester, backend, settings: settings);
    await _tap(tester, _button(SignInProvider.discord));
    expect(find.byType(UsernameStep), findsOneWidget);

    // Wie ein Neuladen im Browser mitten im Schritt.
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, backend, settings: settings);
    expect(find.byType(UsernameStep), findsOneWidget);
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
    expect(find.byType(UsernameStep), findsNothing,
        reason: 'den Namen hat der Nutzer selbst gewählt');
    expect(find.byType(MapScreen), findsOneWidget);
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
