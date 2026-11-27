// Mitteilungen unterwegs auf dem iPhone (#644, Paket 3b): dieselben
// Knöpfe wie auf Android, als Kategorien beim Einrichten — und die Frage
// nach der Erlaubnis erst beim Start einer Fahrt, nie beim App-Start.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/rides/ride_confirm.dart';
import 'package:trailbuddy/features/rides/ride_confirm_notify.dart';
import 'package:trailbuddy/features/rides/ride_notice_darwin.dart';
import 'package:trailbuddy/features/rides/wheelie_notify.dart';

import '../fakes/l10n_de.dart';

const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

/// Die Knopf-Kennungen einer Android-Mitteilung im Quelltext, je Aufruf
/// von `show` in der Reihenfolge — die Gegenstelle der Kategorien.
List<List<String>> _androidActionIds(String file) {
  final source = File(file).readAsStringSync();
  return [
    for (final show in source.split('.show(').skip(1))
      [
        for (final m in RegExp(
          r'AndroidNotificationAction\(\s*([\w.]+),',
        ).allMatches(show.split('iOS:').first))
          m[1]!,
      ],
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('Einrichtung', () {
    final settings = rideNoticeDarwinSettings(l10nDe);

    test('fragt NICHT nach der Erlaubnis — das täte sonst der App-Start', () {
      expect(settings.requestAlertPermission, isFalse);
      expect(settings.requestSoundPermission, isFalse);
      expect(settings.requestBadgePermission, isFalse);
      expect(settings.requestProvisionalPermission, isFalse);
      expect(settings.requestCriticalPermission, isFalse);
      // Beide Plattformen aus EINER Einrichtung.
      expect(rideNoticeInitSettings(l10nDe).iOS, isNotNull);
      expect(rideNoticeInitSettings(l10nDe).android, isNotNull);
    });

    test('je Knopfsatz eine Kategorie mit den Kennungen von Android', () {
      final byId = {
        for (final c in rideNoticeCategories(l10nDe))
          c.identifier: [for (final a in c.actions) a.identifier],
      };
      expect(byId, {
        kConfirmCategory: ['confirm', 'change'],
        kConfirmFreeCategory: ['confirm', 'free', 'change'],
        kWheelieCategory: [kWheelieYes, kWheelieNo],
        kJumpCategory: [kJumpYes, kJumpNo],
        kStoppieCategory: [kStoppieYes, kStoppieNo],
        kMissedCategory: [kWheelieMissed, kJumpMissed, kStoppieMissed],
      });
      expect(
        [for (final c in ConfirmChoice.values) c.id],
        ['confirm', 'free', 'change'],
      );
      // Die Knöpfe der Airtime-Banner stehen im Quelltext wie hier.
      expect(_androidActionIds('lib/features/rides/wheelie_notify.dart'), [
        ['kWheelieYes', 'kWheelieNo'],
        ['kJumpYes', 'kJumpNo'],
        ['kStoppieYes', 'kStoppieNo'],
        ['kWheelieMissed', 'kJumpMissed', 'kStoppieMissed'],
      ]);
    });

    test('nur „Ändern…" öffnet die App, der Rest antwortet im Hintergrund', () {
      for (final c in rideNoticeCategories(l10nDe)) {
        for (final a in c.actions) {
          final opensApp = a.options.contains(
            DarwinNotificationActionOption.foreground,
          );
          expect(opensApp, a.identifier == 'change', reason: a.identifier);
        }
      }
    });

    test('die Knöpfe sprechen die Sprache der App', () {
      final confirm = rideNoticeCategories(
        l10nDe,
      ).firstWhere((c) => c.identifier == kConfirmFreeCategory);
      expect(
        [for (final a in confirm.actions) a.title],
        [l10nDe.confirmYes, l10nDe.confirmFree, l10nDe.confirmChange],
      );
    });

    test('jede Mitteilung der Fahrt trägt ihre iOS-Einstellung', () {
      // Ohne `iOS:` zeigte das Paket die Mitteilung zwar, aber ohne
      // Kategorie — also ohne Knöpfe.
      for (final file in [
        'lib/features/rides/ride_confirm_notify.dart',
        'lib/features/rides/wheelie_notify.dart',
      ]) {
        final source = File(file).readAsStringSync();
        final shows = '.show('.allMatches(source).length;
        expect(shows, greaterThan(0), reason: file);
        expect(
          RegExp(r'iOS:\s*rideNoticeDarwin\(').allMatches(source).length,
          shows,
          reason: file,
        );
      }
      final missed = rideNoticeDarwin(kMissedCategory, passive: true);
      expect(missed.presentBanner, isFalse);
      expect(missed.presentSound, isFalse);
      expect(missed.interruptionLevel, InterruptionLevel.passive);
      final question = rideNoticeDarwin(kConfirmCategory);
      expect(question.presentBanner, isTrue);
      expect(question.categoryIdentifier, kConfirmCategory);
      expect(question.threadIdentifier, kRideNoticeThread);
    });

    test('gefragt wird nur beim Start einer Fahrt', () {
      final callers = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final code = f
            .readAsLinesSync()
            .map((l) => l.split('//').first)
            .join('\n');
        if (code.contains('requestRideNoticePermission') ||
            code.contains('requestNotificationsPermission') ||
            RegExp(r'\.requestPermissions\(').hasMatch(code)) {
          callers.add(f.path);
        }
      }
      expect(callers.toSet(), {
        // Definiert hier …
        'lib/features/rides/ride_confirm_notify.dart',
        // … aufgerufen nur in `RideNotifier.start` (Naht).
        'lib/features/rides/ride_providers.dart',
      });
    });
  });

  group('auf dem iPhone über den Kanal des Pakets', () {
    final calls = <MethodCall>[];
    setUp(() {
      calls.clear();
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      IOSFlutterLocalNotificationsPlugin.registerWith();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'initialize' || 'requestPermissions' => true,
              _ => null,
            };
          });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null),
    );

    test(
      'Antippen in der App: eingerichtet mit Kategorien, ohne Frage',
      () async {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final sub = c.read(rideConfirmTapsProvider)().listen((_) {});
        addTearDown(sub.cancel);
        await pumpEventQueue();
        final init = calls.firstWhere((m) => m.method == 'initialize');
        final args = init.arguments as Map;
        expect(args['requestAlertPermission'], isFalse);
        expect(args['requestSoundPermission'], isFalse);
        expect(args['requestBadgePermission'], isFalse);
        expect([
          for (final c in args['notificationCategories'] as List)
            c['identifier'],
        ], containsAll([kConfirmCategory, kWheelieCategory, kMissedCategory]));
        expect(calls.where((m) => m.method == 'requestPermissions'), isEmpty);
      },
    );

    test('beim Start der Fahrt: Hinweis und Ton, kein Kennzeichen', () async {
      expect(await requestRideNoticePermission(), isTrue);
      final ask = calls.singleWhere((m) => m.method == 'requestPermissions');
      final args = ask.arguments as Map;
      expect(args['alert'], isTrue);
      expect(args['sound'], isTrue);
      expect(args['badge'], isFalse);
    });

    test('auf Android fragt hier niemand (das tut der Dienst)', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(await requestRideNoticePermission(), isNull);
      expect(calls, isEmpty);
    });
  });
}
