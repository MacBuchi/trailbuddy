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
import 'package:trailbuddy/features/map/host_requests.dart';
import 'package:trailbuddy/core/push_messaging.dart';
import 'package:trailbuddy/core/screen_awake_io.dart' show kScreenChannel;
import 'package:trailbuddy/features/garmin/garmin_bridge_io.dart'
    show kGarminChannel;
import 'package:trailbuddy/features/offline_areas/area_providers.dart';
import 'package:trailbuddy/features/rides/ride_providers.dart';
import 'package:trailbuddy/features/rides/sensor_log.dart' show kSensorChannel;
import 'package:trailbuddy/features/routing/nav_service.dart'
    show navServiceSupported;
import 'package:trailbuddy/features/routing/voice_service.dart'
    show kVoiceChannel;
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
            ios: true,
            read: () => read(rideRecordingAvailableProvider),
          ),
          'Sensor-Rohdaten': (
            android: true,
            ios: true,
            read: () => read(sensorLogAvailableProvider),
          ),
          // Paket 3b: derselbe gehaltene Standortstrom wie die Fahrt.
          'Navigation im Dienst': (
            android: true,
            ios: true,
            read: () => navServiceSupported,
          ),
          // Der iOS-Teil von tb_voice (AVSpeechSynthesizer).
          'Ansagen übers Ohr': (
            android: true,
            ios: true,
            read: () => read(voiceCuesAvailableProvider),
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
        // Die Garmin-Uhr (#644 Paket 4): Das SDK spricht selbst Bluetooth.
        'NSBluetoothAlwaysUsageDescription',
      ]) {
        expect(
          RegExp(
            '<key>$key</key>\\s*<string>[^<]{20,}</string>',
          ).hasMatch(plist),
          isTrue,
          reason: key,
        );
      }
      // Die Fahrt (#644, Paket 3): Standort im Hintergrund NUR über den
      // Hintergrundmodus und „Beim Benutzen" — kein „Immer". Dazu `audio`
      // für die Ansagen (Paket 3b): Am iPhone 8 (iOS 16.7) verweigerte die
      // Audio-Sitzung im Hintergrund ohne ihn jeden Satz ('!pla',
      // 2026-11-27). Sonst kein Modus (Abruf, Push), den die App nicht
      // nachweist.
      expect(plist, isNot(contains('NSLocationAlways')));
      final modes = RegExp(
        r'<key>UIBackgroundModes</key>\s*<array>(.*?)</array>',
        dotAll: true,
      ).firstMatch(plist);
      expect(modes, isNotNull);
      expect(
        RegExp(
          r'<string>(\w+)</string>',
        ).allMatches(modes![1]!).map((m) => m[1]).toList(),
        ['location', 'audio'],
      );
      expect(plist, isNot(contains('BGTaskSchedulerPermittedIdentifiers')));
    });

    test('der Standort-Text nennt die Fahrt im Hintergrund', () {
      // Ohne das wäre der blaue Hinweis bei gesperrtem Bildschirm eine
      // Überraschung — und die App-Prüfung fragt danach.
      expect(
        RegExp(
          r'<key>NSLocationWhenInUseUsageDescription</key>\s*<string>[^<]*background',
        ).hasMatch(plist),
        isTrue,
      );
      expect(
        File('ios/Runner/de.lproj/InfoPlist.strings').readAsStringSync(),
        contains('auch im Hintergrund'),
      );
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

  group('Anfragezähler auf iOS (#644)', () {
    test('main() hängt ihn ein, bevor eine Karte lädt — nur im Debug', () {
      final main = File('lib/main.dart').readAsStringSync();
      final install = main.indexOf('await installNativeHostCounter();');
      expect(install, greaterThan(0));
      expect(install, lessThan(main.indexOf('runApp(')));
      final dart = File(
        'lib/features/map/host_requests.dart',
      ).readAsStringSync();
      expect(dart, contains('enabled ?? (kDebugMode && hasIosChannels)'));
    });

    test('ohne Freigabe fragt niemand den Kanal', () async {
      var asked = false;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(kHostRequestsChannel, (call) async {
        asked = true;
        return true;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(kHostRequestsChannel, null),
      );
      expect(await installNativeHostCounter(enabled: false), isFalse);
      expect(asked, isFalse);
      expect(await installNativeHostCounter(enabled: true), isTrue);
      expect(asked, isTrue);
    });

    test('die Swift-Seite spricht denselben Kanal wie Kotlin', () {
      final swift = File(
        'ios/Runner/HostRequestCounter.swift',
      ).readAsStringSync();
      expect(swift, contains('"${kHostRequestsChannel.name}"'));
      for (final m in ['"counts"', '"reset"', '"install"', '"installed"']) {
        expect(swift, contains('case $m'), reason: m);
      }
      expect(swift, contains('"MLNNetworkConfiguration"'));
      expect(
        File('ios/Runner/AppDelegate.swift').readAsStringSync(),
        contains('HostRequestCounter.register'),
      );
      expect(
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
        contains('HostRequestCounter.swift in Sources'),
      );
    });

    test('„Entwicklung" im Profil auch im iOS-Debug-Build', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final c = ProviderContainer();
      addTearDown(c.dispose);
      // flutter test läuft im Debug-Modus.
      expect(c.read(devToolsVisibleProvider), kDebugMode);
    });
  });

  group('Fahrt aufzeichnen auf iOS (#644, Paket 3)', () {
    // Ohne Kommentare: Eine auskommentierte Zeile ist kein Aufruf.
    final delegate = File(
      'ios/Runner/AppDelegate.swift',
    ).readAsLinesSync().map((l) => l.split('//').first).join('\n');

    test('die Engine des Dienstes bekommt die Plugins der App', () {
      // Ohne den Rückruf startet flutter_foreground_task die zweite Engine
      // ohne Plugins: kein Standort, keine Sensoren, keine Brücke.
      expect(
        RegExp(
          r'SwiftFlutterForegroundTaskPlugin\.setPluginRegistrantCallback\s*\{\s*registry in\s*GeneratedPluginRegistrant\.register\(with: registry\)',
        ).hasMatch(delegate),
        isTrue,
      );
      // Gesetzt, BEVOR die App-Engine läuft (die Fahrt kann beim Start
      // wieder aufgenommen werden).
      expect(
        delegate.indexOf('setPluginRegistrantCallback'),
        lessThan(delegate.indexOf('super.application(')),
      );
    });

    test('Bildschirm an: derselbe Kanal und Vertrag wie Kotlin', () {
      final swift = File('ios/Runner/ScreenAwake.swift').readAsStringSync();
      final kotlin = File(
        'android/app/src/main/kotlin/de/mcbuchi/trailbuddy/MainActivity.kt',
      ).readAsStringSync();
      expect(swift, contains('"$kScreenChannel"'));
      expect(kotlin, contains('"$kScreenChannel"'));
      for (final code in [swift, kotlin]) {
        expect(code, contains('"keepOn"'));
        expect(code, contains('"on"'));
      }
      expect(swift, contains('isIdleTimerDisabled = on'));
      expect(delegate, contains('ScreenAwake.register'));
    });

    test('Knöpfe der Mitteilungen: die Engine des Pakets hat Plugins', () {
      // Ein Knopf ohne „App öffnen" antwortet in einer EIGENEN Engine von
      // flutter_local_notifications (Paket 3b) — ohne Rückruf ohne Plugins.
      expect(
        RegExp(
          r'FlutterLocalNotificationsPlugin\.setPluginRegistrantCallback\s*\{\s*registry in\s*GeneratedPluginRegistrant\.register\(with: registry\)',
        ).hasMatch(delegate),
        isTrue,
      );
      expect(
        RegExp(
          r'UNUserNotificationCenter\.current\(\)\.delegate\s*=\s*self',
        ).hasMatch(delegate),
        isTrue,
      );
      final superCall = delegate.indexOf('super.application(');
      expect(
        delegate.indexOf('FlutterLocalNotificationsPlugin'),
        lessThan(superCall),
      );
      expect(delegate.indexOf('.delegate = self'), lessThan(superCall));
    });

    test('Messbereich (…/sensors): bewusst unbekannt, kein Swift-Kanal', () {
      // Core Motion nennt keinen Messbereich; `readSensorRange` gibt ohne
      // Kanal '' zurück, und das heißt „unbekannt" (ios/CLAUDE.md).
      final swift = [
        for (final dir in ['ios/Runner', 'packages'])
          for (final f in Directory(dir).listSync(recursive: true))
            if (f is File && f.path.endsWith('.swift')) f.readAsStringSync(),
      ];
      expect(swift, isNotEmpty);
      for (final code in swift) {
        expect(code, isNot(contains(kSensorChannel)));
      }
    });
  });

  group('Ansagen auf iOS: tb_voice in Swift wie in Java (#644, Paket 3b)', () {
    // Ohne Kommentare: dort stehen dieselben Namen zur Erklärung.
    final swift = File(
      'packages/tb_voice/ios/tb_voice/Sources/tb_voice/TbVoicePlugin.swift',
    ).readAsLinesSync().map((l) => l.split('//').first).join('\n');
    final java = File(
      'packages/tb_voice/android/src/main/java/de/mcbuchi/trailbuddy/voice/TbVoicePlugin.java',
    ).readAsStringSync();

    test('derselbe Kanal, dieselbe Methode, dieselben Antworten', () {
      expect(swift, contains('"${kVoiceChannel.name}"'));
      expect(java, contains('"${kVoiceChannel.name}"'));
      for (final code in [swift, java]) {
        expect(code, contains('"speak"'));
        expect(code, contains('"text"'));
        expect(code, contains('"language"'));
      }
      // Leerer Text: false; sonst sofort true, der Satz läuft danach.
      expect(swift, matches(RegExp(r'isEmpty \{\s*result\(false\)')));
      expect(swift, contains('result(true)'));
      expect(swift, contains('FlutterMethodNotImplemented'));
    });

    test('Musik wird leiser, nicht gestoppt — und danach wieder laut', () {
      expect(swift, contains('.duckOthers'));
      expect(swift, contains('mode: .voicePrompt'));
      expect(swift, contains('.notifyOthersOnDeactivation'));
      expect(java, contains('AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK'));
    });

    test('ein Plugin (auch in der Engine des Dienstes), über SPM', () {
      final pubspec = File('packages/tb_voice/pubspec.yaml').readAsStringSync();
      expect(
        RegExp(r'ios:\s*\n\s*pluginClass: TbVoicePlugin').hasMatch(pubspec),
        isTrue,
      );
      expect(
        File('packages/tb_voice/ios/tb_voice/Package.swift').readAsStringSync(),
        contains('name: "tb_voice"'),
      );
      expect(swift, contains('class TbVoicePlugin: NSObject, FlutterPlugin'));
    });
  });

  group('Die Garmin-Uhr auf iOS: GarminBridge.swift wie Kotlin (#644, '
      'Paket 4)', () {
    // Ohne Kommentare: dort stehen dieselben Namen zur Erklärung.
    final swift = File(
      'ios/Runner/GarminBridge.swift',
    ).readAsLinesSync().map((l) => l.split('//').first).join('\n');
    final kotlin = File(
      'android/app/src/main/kotlin/de/mcbuchi/trailbuddy/GarminBridge.kt',
    ).readAsStringSync();
    final plist = File('ios/Runner/Info.plist').readAsStringSync();

    String body(String func) {
      final start = swift.indexOf('private func $func(');
      expect(start, greaterThan(-1), reason: func);
      final end = swift.indexOf('\n  private func ', start + 1);
      return swift.substring(start, end < 0 ? swift.length : end);
    }

    test('derselbe Kanal, dieselben Methoden und Rückrufe', () {
      expect(swift, contains('"$kGarminChannel"'));
      expect(kotlin, contains('"$kGarminChannel"'));
      for (final m in ['status', 'listen', 'open', 'send']) {
        expect(swift, contains('case "$m"'), reason: m);
        expect(kotlin, contains('"$m" ->'), reason: m);
      }
      // `pick` gibt es nur auf iOS: Dort sieht das SDK die Uhr nicht selbst.
      expect(swift, contains('case "pick"'));
      expect(kotlin, isNot(contains('"pick"')));
      for (final code in [swift, kotlin]) {
        expect(code, contains('invokeMethod("message"'));
        expect(code, contains('invokeMethod("device"'));
        expect(code, contains('"appId"'));
        expect(code, contains('"messages"'));
      }
      expect(swift, contains('"PICKED"'));
      expect(swift, contains('FlutterMethodNotImplemented'));
    });

    test('die Namen, auf die Dart hört, kommen auch aus Swift', () {
      // WatchSendResult.ok, die Wiederaufnahme (`_resumable`), WatchOpen,
      // WatchStatus und das neu Verbinden.
      for (final name in [
        'SUCCESS',
        'FAILURE_TIMEOUT',
        'FAILURE_DURING_TRANSFER',
        'APP_IS_ALREADY_RUNNING',
        'PROMPT_SHOWN_ON_DEVICE',
        'APP_IS_NOT_INSTALLED',
        'CONNECTED',
      ]) {
        expect(swift, contains('"$name"'), reason: name);
      }
      for (final key in ['connect', 'device', 'app', 'status', 'sent']) {
        expect(swift, contains('"$key":'), reason: key);
      }
      for (final app in ['installed', 'not_installed', 'unknown']) {
        expect(swift, contains('"$app"'), reason: app);
      }
      expect(swift, contains('"pick": true'));
      // Was die Dart-Seite wieder aufnimmt, muss aus der Abbildung der
      // iOS-Ergebnisse kommen (nicht nur aus der eigenen Frist).
      final sendName = swift.substring(
        swift.indexOf('static func sendName('),
        swift.indexOf('static func openName('),
      );
      expect(
        sendName,
        matches(RegExp(r'case \.failure_Timeout: return "FAILURE_TIMEOUT"')),
      );
      expect(
        sendName,
        matches(
          RegExp(
            r'case \.failure_MaxRetries, \.failure_DeviceIsBusy: return "FAILURE_DURING_TRANSFER"',
          ),
        ),
      );
      expect(sendName, contains('case .success: return "SUCCESS"'));
      // Dieselben Fristen wie Kotlin (20 s je Stück, 10 s beim Öffnen).
      expect(swift, contains('ackTimeout: TimeInterval = 20'));
      expect(swift, contains('openTimeout: TimeInterval = 10'));
      expect(kotlin, contains('ACK_TIMEOUT_MS = 20_000L'));
      expect(kotlin, contains('OPEN_TIMEOUT_MS = 10_000L'));
    });

    test('kein Bluetooth vor „Uhr verbinden": ohne Uhr startet kein SDK', () {
      // `startSdk()` legt den Bluetooth-Zugang an; ohne gewählte Uhr
      // fragen `status` und `listen`, ohne es aufzurufen.
      for (final func in ['status', 'listenOnly']) {
        final code = body(func);
        final guard = code.indexOf('guard let device = device');
        expect(guard, greaterThan(-1), reason: func);
        expect(code.indexOf('startSdk()'), greaterThan(guard), reason: func);
      }
      // Gestartet wird nur dort, nie beim Anlegen der Brücke.
      final init = swift.substring(
        swift.indexOf('private init('),
        swift.indexOf('private func handle('),
      );
      expect(init, isNot(contains('startSdk')));
      expect(init, isNot(contains('ConnectIQ.sharedInstance()')));
    });

    test('Garmin Connect fragen und dorthin zurück — eigenes Schema', () {
      expect(swift, contains('urlScheme = "trailbuddy-ciq"'));
      expect(swift, contains('connectScheme = "gcm-ciq"'));
      expect(
        RegExp(
          r'<key>CFBundleURLSchemes</key>\s*<array>\s*<string>trailbuddy-ciq</string>',
        ).hasMatch(plist),
        isTrue,
      );
      expect(
        RegExp(
          r'<key>LSApplicationQueriesSchemes</key>\s*<array>\s*<string>gcm-ciq</string>\s*</array>',
        ).hasMatch(plist),
        isTrue,
      );
      // Der Rücksprung kommt über Flutters Szenen-Rückruf, nicht über einen
      // eigenen SceneDelegate (der Anmelde-Rücksprung geht weiter).
      expect(swift, contains('registrar.addSceneDelegate(bridge)'));
      expect(swift, contains('openURLContexts'));
      expect(
        File('ios/Runner/AppDelegate.swift').readAsStringSync(),
        contains('GarminBridge.register(with: registrar)'),
      );
    });

    test('das SDK genau in 1.8.0, als Paket der App', () {
      final pbxproj = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      expect(
        pbxproj,
        contains(
          'repositoryURL = "https://github.com/garmin/connectiq-companion-app-sdk-ios"',
        ),
      );
      expect(
        RegExp(r'kind = exactVersion;\s*version = 1\.8\.0;').hasMatch(pbxproj),
        isTrue,
      );
      expect(pbxproj, contains('ConnectIQ in Frameworks'));
      for (final resolved in [
        'ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved',
        'ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved',
      ]) {
        final text = File(resolved).readAsStringSync();
        expect(
          RegExp(
            r'"connectiq-companion-app-sdk-ios"[\s\S]*?"version" : "1\.8\.0"',
          ).hasMatch(text),
          isTrue,
          reason: resolved,
        );
      }
    });
  });

  group('Datenschutz-Manifest und Texte (#644)', () {
    final privacy = File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync();

    test('kein Tracking, Datenarten wie im Play Store', () {
      expect(
        RegExp(r'<key>NSPrivacyTracking</key>\s*<false/>').hasMatch(privacy),
        isTrue,
      );
      final types = RegExp(
        r'<string>NSPrivacyCollectedDataType(?!Purpose)(\w+)</string>',
      ).allMatches(privacy).map((m) => m[1]).toSet();
      expect(types, {
        'PreciseLocation',
        'CoarseLocation',
        'EmailAddress',
        'Name',
        'UserID',
        'OtherUserContent',
        'PhotosorVideos',
        'EmailsOrTextMessages',
        'CrashData',
      });
      // Gerätekennung erst mit Push auf iOS.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(pushPlatformSupported, isFalse);
      expect(privacy, isNot(contains('DeviceID')));
      expect(
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
        contains('PrivacyInfo.xcprivacy in Resources'),
      );
    });

    test('Berechtigungstexte auf Deutsch und Englisch, gleiche Schlüssel', () {
      Set<String> keys(String lang) =>
          RegExp(r'^"(\w+)" = "[^"]{20,}";$', multiLine: true)
              .allMatches(
                File(
                  'ios/Runner/$lang.lproj/InfoPlist.strings',
                ).readAsStringSync(),
              )
              .map((m) => m[1]!)
              .toSet();
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      final asked = RegExp(
        r'<key>(NS\w+UsageDescription)</key>',
      ).allMatches(plist).map((m) => m[1]!).toSet();
      expect(keys('de'), asked);
      expect(keys('en'), asked);
      expect(
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
        contains('InfoPlist.strings in Resources'),
      );
    });
  });

  test('Startfenster: der Grund der App wie auf Android, ohne Bild', () {
    String ground(String values) =>
        RegExp(r'<color name="ground">#(\w{6})</color>')
            .firstMatch(
              File(
                'android/app/src/main/res/$values/colors.xml',
              ).readAsStringSync(),
            )![1]!
            .toUpperCase();
    final set = File(
      'ios/Runner/Assets.xcassets/LaunchBackground.colorset/Contents.json',
    ).readAsStringSync();
    String hex(String json) => RegExp(
      r'"red"\s*:\s*"0x(\w\w)",\s*"green"\s*:\s*"0x(\w\w)",\s*"blue"\s*:\s*"0x(\w\w)"',
    ).allMatches(json).map((m) => '${m[1]}${m[2]}${m[3]}'.toUpperCase()).join(',');
    expect(hex(set), '${ground('values')},${ground('values-night')}');
    expect(RegExp(r'"value"\s*:\s*"dark"').hasMatch(set), isTrue);
    final board = File(
      'ios/Runner/Base.lproj/LaunchScreen.storyboard',
    ).readAsStringSync();
    expect(
      board,
      contains('<color key="backgroundColor" name="LaunchBackground"/>'),
    );
    expect(board, isNot(contains('<imageView')));
  });

  test(
    'eigene Dateien stehen in den Build-Phasen der APP, nicht der Tests',
    () {
      final pbxproj = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      String phase(String id) {
        final start = RegExp(
          '$id /\\* \\w+ \\*/ = \\{',
        ).firstMatch(pbxproj)!.start;
        final at = pbxproj.indexOf('files = (', start);
        return pbxproj.substring(at, pbxproj.indexOf(');', at));
      }

      final sources = phase('97C146EA1CF9000F007C117D');
      final resources = phase('97C146EC1CF9000F007C117D');
      for (final f in [
        'BackupExclusion.swift',
        'HostRequestCounter.swift',
        'ScreenAwake.swift',
      ]) {
        expect(sources, contains('$f in Sources'), reason: f);
      }
      for (final f in ['PrivacyInfo.xcprivacy', 'InfoPlist.strings']) {
        expect(resources, contains('$f in Resources'), reason: f);
      }
    },
  );
}
