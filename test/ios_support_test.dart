// Das iPhone (#644): Was dort nicht am Gerät gezeigt ist, bietet die App
// nicht an. Bis hierher hieß „nicht im Browser" überall „Android" —
// diese Datei hält fest, dass iOS die Zusagen NICHT erbt, und dass das
// Projekt unter `ios/` nichts Privates trägt.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/platform_support.dart';
import 'package:trailbuddy/core/push_messaging.dart';
import 'package:trailbuddy/features/offline_areas/area_providers.dart';
import 'package:trailbuddy/features/rides/ride_providers.dart';
import 'package:trailbuddy/features/trails/trail_navigation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('Plattform-Schalter', () {
    bool read(ProviderListenable<bool> p) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return c.read(p);
    }

    test('Android behält Fahrt, Sensoren, ganze Regionen und Push', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(isAndroidApp, isTrue);
      expect(isIosApp, isFalse);
      expect(read(rideRecordingAvailableProvider), isTrue);
      expect(read(sensorLogAvailableProvider), isTrue);
      expect(read(wholeRegionSupportedProvider), isTrue);
      expect(pushPlatformSupported, isTrue);
    });

    test('iOS verspricht nichts davon, bis das Gerät es zeigt', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(isAndroidApp, isFalse);
      expect(isIosApp, isTrue);
      expect(read(rideRecordingAvailableProvider), isFalse);
      expect(read(sensorLogAvailableProvider), isFalse);
      expect(read(wholeRegionSupportedProvider), isFalse);
      expect(pushPlatformSupported, isFalse);
    });

    test(
      'Push auf iOS: „nicht eingerichtet", ohne Firebase zu fragen',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        // Ginge der Aufruf an Firebase, hinge er im Test am fehlenden Kanal
        // oder liefe in den catch-Zweig (unavailable: false).
        final result = await requestPushToken();
        expect(result.token, isNull);
        expect(result.unavailable, isTrue);
        expect(result.denied, isFalse);
        expect(await initialPushMessage(), isNull);
        expect(await pushTaps().isEmpty, isTrue);
        expect(await pushMessages().isEmpty, isTrue);
      },
    );

    test(
      '„In Navi-App öffnen": auf iOS kein geo:, sondern die Zwischenablage',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        final clipboard = <String>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        var launched = 0;
        final outcome = await openInNavigationApp(
          lat: 7,
          lng: 11,
          launch: (_) async {
            launched++;
            return true;
          },
        );
        expect(launched, 0);
        expect(outcome, NavigationOutcome.copiedNoApp);
        expect(clipboard, ['7.000000, 11.000000']);
      },
    );
  });

  group('Das Projekt unter ios/', () {
    final pbxproj = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final plist = File('ios/Runner/Info.plist').readAsStringSync();

    test('kein Signier-Team im öffentlichen Repo', () {
      // `flutter create` schreibt das Team aus dem Schlüsselbund hinein;
      // es gehört in die ignorierte ios/Flutter/Local.xcconfig.
      expect(pbxproj, isNot(contains('DEVELOPMENT_TEAM')));
      for (final name in ['Debug', 'Release']) {
        final config = File('ios/Flutter/$name.xcconfig').readAsStringSync();
        expect(config, contains('#include? "Local.xcconfig"'), reason: name);
        expect(
          RegExp(r'^\s*DEVELOPMENT_TEAM\s*=', multiLine: true).hasMatch(config),
          isFalse,
          reason: name,
        );
      }
      expect(
        File('ios/.gitignore').readAsStringSync(),
        contains('Flutter/Local.xcconfig'),
      );
    });

    test('dieselbe Kennung wie auf Android, Ziel iOS 15', () {
      final ids = RegExp(
        r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);',
      ).allMatches(pbxproj).map((m) => m[1]).toSet();
      expect(ids, {
        'de.mcbuchi.trailbuddy',
        'de.mcbuchi.trailbuddy.RunnerTests',
      });
      final targets = RegExp(
        r'IPHONEOS_DEPLOYMENT_TARGET = ([^;]+);',
      ).allMatches(pbxproj).map((m) => m[1]).toSet();
      expect(targets, {'15.0'});
    });

    test('Rücksprung der Anmeldung über die Bundle-Kennung', () {
      // Android: android:scheme="${applicationId}" host="login-callback".
      expect(plist, contains('<string>login-callback</string>'));
      expect(plist, contains('<string>\$(PRODUCT_BUNDLE_IDENTIFIER)</string>'));
    });

    test('jede Berechtigung, die ein Plugin auf iOS fragt, hat ihren Text', () {
      // Standort (Karte), Kamera und Mediathek (Foto am Hinweis). Fehlt
      // ein Text, beendet iOS die App beim ersten Zugriff.
      for (final key in [
        'NSLocationWhenInUseUsageDescription',
        'NSCameraUsageDescription',
        'NSPhotoLibraryUsageDescription',
      ]) {
        expect(
          RegExp(
            '<key>$key</key>\\s*<string>[^<]{20,}</string>',
          ).hasMatch(plist),
          isTrue,
          reason: key,
        );
      }
      // Kein Standort im Hintergrund, solange die Fahrt auf iOS fehlt.
      expect(plist, isNot(contains('NSLocationAlways')));
      expect(plist, isNot(contains('UIBackgroundModes')));
    });

    test('beide Sprachen der Oberfläche sind angemeldet', () {
      expect(
        RegExp(
          r'<key>CFBundleLocalizations</key>\s*<array>\s*<string>de</string>\s*<string>en</string>',
        ).hasMatch(plist),
        isTrue,
      );
      expect(plist, contains('<string>TrailBuddy</string>'));
    });
  });
}
