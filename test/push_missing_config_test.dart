// Ein Build ohne Firebase-Konfiguration ist „noch nicht eingerichtet",
// kein Fehler des Geräts — und kein Eintrag im Wochendigest (#62: bis
// 0.36.x kam „Failed to load FirebaseOptions from resource" als
// Fehlerbericht an, weil nur die Dart-Form `[core/…]` erkannt wurde).
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/push_messaging.dart';

void main() {
  test('beide Formen der fehlenden Konfiguration werden erkannt', () {
    expect(
      isMissingFirebaseConfig(
        FirebaseException(plugin: 'core', code: 'no-app'),
      ),
      isTrue,
    );
    // Die native Form, wörtlich aus FlutterFirebaseCorePlugin.kt.
    expect(
      isMissingFirebaseConfig(
        PlatformException(
          code: 'java.lang.Exception',
          message:
              'Failed to load FirebaseOptions from resource. '
              'Check that you have defined values.xml correctly.',
        ),
      ),
      isTrue,
    );
  });

  test('echte Fehler bleiben Fehler', () {
    expect(
      isMissingFirebaseConfig(
        FirebaseException(plugin: 'messaging', code: 'unknown'),
      ),
      isFalse,
    );
    expect(
      isMissingFirebaseConfig(
        PlatformException(code: 'network', message: 'timeout'),
      ),
      isFalse,
    );
    expect(isMissingFirebaseConfig(StateError('kaputt')), isFalse);
  });
}
