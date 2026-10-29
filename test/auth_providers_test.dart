import 'dart:io';


import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trailbuddy/data/auth_repository.dart';

void main() {
  test('/settings: nur, was dort true ist, unter GoTrues Namen (#398)', () {
    // Gekürzt aus der Antwort eines echten GoTrue — Microsoft heißt
    // `azure`, LinkedIn `linkedin_oidc`, und `email` ist kein Anbieter.
    final body = {
      'external': {
        'email': true,
        'google': true,
        'azure': true,
        'linkedin_oidc': true,
        'linkedin': true,
        'github': false,
        'facebook': 'true',
      },
      'disable_signup': false,
    };
    expect(AuthRepository.parseEnabledProviders(body), {
      SignInProvider.google,
      SignInProvider.microsoft,
      SignInProvider.linkedin,
    });
  });

  test('fremde Antwort ⇒ keine Knöpfe', () {
    expect(AuthRepository.parseEnabledProviders(null), isEmpty);
    expect(AuthRepository.parseEnabledProviders([1, 2]), isEmpty);
    expect(AuthRepository.parseEnabledProviders({'external': 'x'}), isEmpty);
  });

  test('jedes Zeichen liegt als Asset bereit', () {
    // Ein fehlendes SVG fiele erst am Gerät auf (leerer Knopf).
    for (final p in SignInProvider.values) {
      expect(
          File('assets/auth/${p.name}.svg').existsSync(), isTrue, reason: p.name);
    }
  });

  test('Nur OAuth-Fehler des Rücksprungs zählen, nicht eine abgelaufene '
      'Sitzung (#398)', () {
    expect(
        AuthRepository.isProviderReturnError(
            const AuthException('OAuth state has expired', code: 'server_error')),
        isTrue);
    expect(
        AuthRepository.isProviderReturnError(
            const AuthException('denied', code: 'access_denied')),
        isTrue);
    expect(
        AuthRepository.isProviderReturnError(
            const AuthException('Session expired.', code: 'session_expired')),
        isFalse);
    expect(AuthRepository.isProviderReturnError(Exception('x')), isFalse);
  });

  test('Der nachspielende Auth-Stream liefert jeden Rücksprung-Fehler nur '
      'einmal', () async {
    final client = SupabaseClient('http://localhost:1', 'key');
    final repo = AuthRepository(client);
    // ignore: invalid_use_of_internal_member
    client.auth.notifyException(
        const AuthException('OAuth state has expired', code: 'server_error'));

    final first = await repo.providerReturnErrors.first;
    expect(first.message, 'OAuth state has expired');

    // Ein zweiter Hörer (Login nach der Registrierung wieder offen) bekommt
    // denselben Fehler vom ReplaySubject nachgespielt — aber nicht gezeigt.
    final again = <AuthException>[];
    final sub = repo.providerReturnErrors.listen(again.add);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(again, isEmpty);
    await client.dispose();
  });
}
