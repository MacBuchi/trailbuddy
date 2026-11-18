// Der Update-Hinweis im Profil und der Vorab-Kanal.
//
// Der Weg vom Hinweis bis zum System-Installer (In-App-Download) ist in
// TrailBuddy noch nicht gebaut; hier steht, was es schon gibt: der
// Versionsvergleich, die APK-Erkennung, die Statuszeile unter „Über
// TrailBuddy" und der Schalter, der den Kanal umlegt.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/update_check.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

const _info = UpdateInfo(
  latestVersion: '9.9.9',
  downloadUrl: 'https://example.invalid/trailbuddy-v9.9.9.apk',
  releaseNotes: 'Karte wird schneller',
);

void main() {
  group('Versionsvergleich', () {
    test('vergleicht numerisch je Segment', () {
      expect(isNewerVersion('1.10.0', '1.9.2'), isTrue);
      expect(isNewerVersion('1.9.2', '1.10.0'), isFalse);
      expect(isNewerVersion('1.0.0', '1.0.0'), isFalse);
      expect(isNewerVersion('2.0.0', '1.99.99'), isTrue);
    });

    test('ignoriert Vorab- und Build-Suffixe statt daran zu scheitern', () {
      // `int.tryParse('1-rc1')` wäre null und fiele still auf 0 zurück.
      expect(isNewerVersion('1.5.1-rc1', '1.5.0'), isTrue);
      expect(isNewerVersion('1.5.1+42', '1.5.1'), isFalse);
    });

    test('erkennt nur die APK dieses Projekts', () {
      expect(isApkAsset('trailbuddy-v1.2.3.apk'), isTrue);
      expect(isApkAsset('andere-app-v1.2.3.apk'), isFalse);
      expect(isApkAsset('trailbuddy-v1.2.3.aab'), isFalse);
    });

    test('nimmt aus der Release-Liste den ersten veröffentlichten Stand', () {
      final release = firstPublishedRelease([
        {'tag_name': 'v2.0.0', 'draft': true},
        'kein Release',
        {'tag_name': 'v1.9.0', 'draft': false, 'prerelease': true},
        {'tag_name': 'v1.8.0'},
      ]);
      expect(release?['tag_name'], 'v1.9.0');
      expect(firstPublishedRelease([]), isNull);
    });
  });

  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testrail');
    backend.signInAs(me.id);
    return (backend, me);
  }

  Future<void> openAbout(WidgetTester tester) async {
    await openProfilePage(tester, 'about');
  }

  testWidgets('Ein verfügbares Update steht in der Statuszeile', (
    tester,
  ) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(
      tester,
      backend,
      extraOverrides: [
        updateInfoProvider.overrideWith((ref) => Future.value(_info)),
      ],
    );

    await openAbout(tester);
    expect(find.textContaining('Neueste Version: v9.9.9'), findsOneWidget);
  });

  testWidgets('Ohne Update sagt die Zeile das auch', (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, appVersion: '1.2.3');

    await openAbout(tester);
    expect(find.textContaining('Version 1.2.3'), findsOneWidget);
    expect(find.textContaining('auf dem aktuellen Stand'), findsOneWidget);
  });

  testWidgets('Der Schalter „Vorabversionen erhalten" wird gemerkt', (
    tester,
  ) async {
    // Im Test gilt Android ohne Play-Flag, also läuft der Update-Weg —
    // und nur dann darf der Schalter überhaupt dastehen.
    final (backend, _) = loggedInBackend();
    final settings = FakeSettings();
    await pumpApp(tester, backend, settings: settings);

    await openAbout(tester);
    final tile = find.widgetWithText(SwitchListTile, 'Vorabversionen erhalten');
    await scrollTo(tester, tile);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);

    await tester.tap(tile);
    await settle(tester);

    expect(
      settings.prereleaseUpdatesEnabled,
      isTrue,
      reason:
          'Der Schalter merkt sich selbst — ein zweiter Schritt, den '
          'man vergessen kann, wäre der Fehler, der erst beim nächsten '
          'Start auffällt.',
    );
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);

    // Und der Neustart liest ihn wieder.
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, backend, settings: settings);
    await openAbout(tester);
    await scrollTo(tester, tile);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
  });
}
