import 'dart:io';


import 'package:flutter_test/flutter_test.dart';
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
}
