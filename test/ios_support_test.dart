// Das iPhone (#644): Was dort nicht am Gerät gezeigt ist, bietet die App
// nicht an. Bis hierher hieß „nicht im Browser" überall „Android" —
// diese Datei hält fest, dass iOS die Zusagen NICHT erbt, und dass das
// Projekt unter `ios/` nichts Privates trägt.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/backup_exclusions.dart';
import 'package:trailbuddy/core/platform_support.dart';
import 'package:trailbuddy/core/update_check.dart';
import 'package:trailbuddy/data/apk_installer.dart';
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

    // Die Fähigkeits-Tabelle (#644): jede Zeile eine Zusage, je Plattform
    // ein Wert. Wer etwas auf iOS freischaltet, ändert HIER die Spalte —
    // nach dem Nachweis am Gerät (ios/CLAUDE.md). Das Web steht nicht in
    // der Tabelle: `kIsWeb` ist auf der VM eine Konstante (test/web/).
    final capabilities =
        <String, ({bool android, bool ios, bool Function() read})>{
          'Fahrt aufzeichnen': (
            android: true,
            ios: false,
            read: () => read(rideRecordingAvailableProvider),
          ),
          'Sensor-Rohdaten': (
            android: true,
            ios: false,
            read: () => read(sensorLogAvailableProvider),
          ),
          'ganze Regionen': (
            android: true,
            ios: false,
            read: () => read(wholeRegionSupportedProvider),
          ),
          'Push': (
            android: true,
            ios: false,
            read: () => pushPlatformSupported,
          ),
          'Update-Hinweis (GitHub-APK)': (
            android: true,
            ios: false,
            read: () => updateChecksApply,
          ),
          'APK installieren': (
            android: true,
            ios: false,
            read: () => const ApkInstaller().supported,
          ),
        };
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      test('Fähigkeiten auf ${platform.name}', () {
        debugDefaultTargetPlatformOverride = platform;
        expect(isAndroidApp, platform == TargetPlatform.android);
        expect(isIosApp, platform == TargetPlatform.iOS);
        for (final MapEntry(key: name, value: c) in capabilities.entries) {
          final want = platform == TargetPlatform.android ? c.android : c.ios;
          expect(c.read(), want, reason: name);
        }
      });
    }

    test('die Kanäle der App fragen den Prozess, nicht die Spielplattform', () {
      // flutter test spielt Android, hat aber keine nativen Kanäle.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(hasAndroidChannels, Platform.isAndroid);
      expect(hasIosChannels, Platform.isIOS);
    });

    test('Plattform-Weichen stehen nur in platform_support.dart', () {
      final weiche = RegExp(
        r'TargetPlatform\.(android|iOS)\b|Platform\.is(Android|IOS)\b',
      );
      final allowed = {
        'lib/core/platform_support.dart',
        'lib/core/platform_host_io.dart',
      };
      final found = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (allowed.contains(f.path) || f.path.contains('/l10n/')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final code = lines[i].split('//').first;
          if (weiche.hasMatch(code)) found.add('${f.path}:${i + 1}');
        }
      }
      expect(found, isEmpty);
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

  group('Keine Cloud-Sicherung von Fahrten, Korb und Zwischenspeichern', () {
    Set<String> androidExcludes() =>
        RegExp(r'<exclude domain="file" path="([^"]+)"')
            .allMatches(
              File(
                'android/app/src/main/res/xml/backup_rules.xml',
              ).readAsStringSync(),
            )
            .map((m) => m[1]!)
            .toSet();

    test('EINE Liste für Android und iOS', () {
      expect({
        ...kBackupExcludedDirs,
        ...kBackupExcludedFiles,
      }, androidExcludes());
    });

    test('iOS bekommt die Pfade unter dem App-Verzeichnis', () async {
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(kBackupChannel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(kBackupChannel, null),
      );
      await excludeFromCloudBackup(
        supported: true,
        baseDir: () async => '/app',
      );
      expect(calls.single.method, 'exclude');
      final args = calls.single.arguments as Map;
      expect(args['dirs'], [for (final d in kBackupExcludedDirs) '/app/$d']);
      expect(args['files'], [for (final f in kBackupExcludedFiles) '/app/$f']);
    });

    test('ohne iOS-Kanäle fragt niemand den Kanal', () async {
      var asked = false;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(kBackupChannel, (call) async {
        asked = true;
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(kBackupChannel, null),
      );
      await excludeFromCloudBackup(
        supported: false,
        baseDir: () async => '/app',
      );
      expect(asked, isFalse);
    });

    test('ein Fehler der iOS-Seite hält den Start nicht auf', () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(kBackupChannel, (call) async {
        throw PlatformException(code: 'backup_exclude');
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(kBackupChannel, null),
      );
      Object? seen;
      await excludeFromCloudBackup(
        supported: true,
        baseDir: () async => '/app',
        onError: (e, _) => seen = e,
      );
      expect(seen, isA<PlatformException>());
    });

    test('die Swift-Seite kennt den Kanal und keinen Ordnernamen', () {
      final swift = File('ios/Runner/BackupExclusion.swift').readAsStringSync();
      expect(swift, contains('"${kBackupChannel.name}"'));
      expect(swift, contains('isExcludedFromBackup = true'));
      for (final name in [...kBackupExcludedDirs, ...kBackupExcludedFiles]) {
        expect(swift, isNot(contains('"$name"')), reason: name);
      }
      final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      expect(delegate, contains('BackupExclusion.register'));
      expect(
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
        contains('BackupExclusion.swift in Sources'),
      );
    });

    test('main() nimmt die Ordner beim Start aus', () {
      expect(
        File('lib/main.dart').readAsStringSync(),
        contains('unawaited(excludeFromCloudBackup());'),
      );
    });
  });
}
