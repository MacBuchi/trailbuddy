// Firebase ohne iOS (#668): Push gibt es auf dem iPhone nicht
// (`pushPlatformSupported`, #644), trotzdem holte und kompilierte Xcode das
// ganze firebase-ios-sdk. `tool/firebase_overrides.py` legt eine Kopie der
// beiden Pakete ohne die Plattform ios an; hier steht, dass sie greift und
// dieselbe Fassung bleibt.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const packages = ['firebase_core', 'firebase_messaging'];
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final lock = File('pubspec.lock').readAsStringSync();

  String? versionIn(String yaml) =>
      RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(yaml)?[1];

  for (final name in packages) {
    group(name, () {
      final dir = 'packages/overrides/$name';
      final override = File('$dir/pubspec.yaml').readAsStringSync();

      test('die App zeigt per Override auf die Kopie', () {
        expect(
          RegExp(
            r'^dependency_overrides:\n(?:  .*\n|    .*\n)*'
            '  $name:\\n    path: ${RegExp.escape(dir)}\\n',
            multiLine: true,
          ).hasMatch(pubspec),
          isTrue,
        );
        expect(
          RegExp(
            '^  $name:\\n(?:    .*\\n)*?    source: path\$',
            multiLine: true,
          ).hasMatch(lock),
          isTrue,
          reason: 'pubspec.lock nimmt die Kopie',
        );
      });

      test('ohne ios, macos und windows, mit android und web', () {
        final platforms = override.substring(
          override.indexOf('    platforms:'),
        );
        for (final p in ['ios', 'macos', 'windows']) {
          expect(platforms, isNot(contains('      $p:')), reason: p);
        }
        expect(platforms, contains('      android:'));
        expect(platforms, contains('      web:'));
        expect(Directory('$dir/ios').existsSync(), isFalse);
        expect(Directory('$dir/android').existsSync(), isTrue);
        expect(
          override,
          startsWith('# ERZEUGT von tool/firebase_overrides.py'),
        );
      });

      test('dieselbe Fassung, die die App verlangt', () {
        // `^a.b.c` in den Abhängigkeiten: Die Kopie muss darin liegen — ein
        // Firebase-Update ohne neue Kopie fiele sonst still zurück.
        final want = RegExp(
          '^  $name: \\^(\\S+)',
          multiLine: true,
        ).firstMatch(pubspec)![1]!;
        final have = versionIn(override)!;
        final w = want.split('.').map(int.parse).toList();
        final h = have.split(RegExp(r'[.+]')).take(3).map(int.parse).toList();
        expect(h[0], w[0], reason: 'Hauptfassung $have zu ^$want');
        expect(
          h[1] > w[1] || (h[1] == w[1] && h[2] >= w[2]),
          isTrue,
          reason: '$have zu ^$want',
        );
      });
    });
  }

  test('Xcode holt kein Firebase mehr', () {
    for (final f in [
      'ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved',
      'ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved',
    ]) {
      final resolved = File(f).readAsStringSync();
      expect(resolved, isNot(contains('firebase')), reason: f);
      expect(resolved, contains('connectiq-companion-app-sdk-ios'), reason: f);
    }
  });
}
