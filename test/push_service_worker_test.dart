// Der Web-Push hängt an Dingen, die nur im ausgelieferten Build falsch
// sein können (#34; PilzBuddy #277): dem Pfad des Workers, der
// Übergabe-Kennung, der Erlaubnisliste der Ziele — und daran, dass die
// Firebase-Konfiguration ganz oder gar nicht gesetzt ist.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/push_config.dart';
import 'package:trailbuddy/core/push_messaging.dart';
import 'package:trailbuddy/core/push_routes.dart';

void main() {
  test('Web-Push ist ganz oder gar nicht eingerichtet', () {
    // Beide Werte kommen aus derselben Firebase-Konsole; einer allein
    // wäre still nutzlos — `getToken` liefert dann nichts, ohne Meldung.
    expect(
      pushFirebaseOptions == null,
      pushWebVapidKey.isEmpty,
      reason:
          'FirebaseOptions und VAPID-Schlüssel gehören zusammen '
          'gesetzt (push_config.dart)',
    );
    if (pushWebVapidKey.isNotEmpty) {
      expect(
        pushWebVapidKey,
        startsWith('B'),
        reason:
            'ein VAPID-Schlüssel ist ein unkomprimierter '
            'P-256-Punkt in base64url — der beginnt mit B',
      );
      expect(
        pushWebVapidKey.length,
        greaterThan(80),
        reason: 'abgeschnitten kopiert? Vollständig sind es ~87 Zeichen',
      );
      expect(pushFirebaseOptions!.projectId, isNotEmpty);
    }
  });

  test('der Worker-Pfad ist relativ, nicht absolut', () {
    expect(
      webServiceWorkerPath,
      isNot(startsWith('/')),
      reason:
          'Ein absoluter Pfad zeigte auf den Origin-Root und damit '
          'ins Leere — die App liegt unter /trailbuddy/.',
    );
    expect(webServiceWorkerPath, isNot(contains('..')));
  });

  test('der Worker liegt in einem EIGENEN Verzeichnis', () {
    // `sw.js` (Offline-Start) hat den Basis-Scope. Registrierungen sind
    // über den Scope eindeutig: Läge unser Worker daneben, ersetzte er
    // beim ersten Einschalten der Benachrichtigungen den Offline-Start.
    expect(webServiceWorkerPath, contains('/'));
    expect(
      File('web/$webServiceWorkerPath').existsSync(),
      isTrue,
      reason: 'Der Worker wird aus web/ mit ausgeliefert.',
    );
  });

  String workerCode() => File('web/$webServiceWorkerPath')
      .readAsLinesSync()
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  test('der Worker lädt nichts nach (kein Firebase-SDK)', () {
    final code = workerCode();
    expect(code, isNot(contains('importScripts')));
    expect(
      code,
      isNot(contains('https://')),
      reason: 'kein fremder Ursprung im Worker',
    );
  });

  test('Worker und App meinen dieselbe Übergabe-Kennung', () {
    final match = RegExp(r"const BRIDGE = '([^']+)'").firstMatch(workerCode());
    expect(match?.group(1), kPushBridgeType);
  });

  test('der Worker öffnet die App unter dem Hash-Pfad', () {
    // Die App nutzt die Hash-Strategie; ein Pfad ohne `#` landete auf
    // GitHub Pages in einer 404.
    expect(workerCode(), contains(r'`${APP_BASE}#${route}`'));
  });

  group('pushRouteOf', () {
    const id = '11111111-0000-0000-0000-000000000001';

    test('ein Trail und die Liste sind erlaubt', () {
      expect(pushRouteOf({'route': '/trail/$id'}), '/trail/$id');
      expect(pushTrailIdOf('/trail/$id'), id);
      expect(pushRouteOf({'route': '/trails'}), '/trails');
      expect(pushTrailIdOf('/trails'), isNull);
    });

    test('alles andere bleibt liegen', () {
      for (final route in <Object?>[
        null,
        '',
        '/',
        '/profile',
        '/trail/abc',
        '/trail/$id/x',
        'https://example.org/trail/$id',
        '/trails?x=1',
        42,
      ]) {
        expect(pushRouteOf({'route': route}), isNull, reason: '$route');
      }
      expect(pushRouteOf({}), isNull);
    });
  });

  group('pushBridgeMessageOf', () {
    test('Meldung mit Titel, Text und Ziel', () {
      final m = pushBridgeMessageOf({
        'type': kPushBridgeType,
        'kind': 'message',
        'notification': {
          'title': 'Neuer Hinweis von einem Buddy',
          'body': 'Tippen zeigt den Trail',
        },
        'data': {'route': '/trail/x'},
      })!;
      expect(m.kind, 'message');
      expect(m.message.notification?.title, 'Neuer Hinweis von einem Buddy');
      expect(m.message.notification?.body, 'Tippen zeigt den Trail');
      expect(m.message.data, {'route': '/trail/x'});
    });

    test('Tipp ohne Meldung, nur das Ziel', () {
      final m = pushBridgeMessageOf({
        'type': kPushBridgeType,
        'kind': 'tap',
        'data': {'route': '/trail/x'},
      })!;
      expect(m.kind, 'tap');
      expect(m.message.notification, isNull);
      expect(m.message.data['route'], '/trail/x');
    });

    test('fremde Nachrichten bleiben liegen', () {
      // `sw.js` schickt der Seite eigene Nachrichten; keine davon darf
      // als Push gelten.
      for (final raw in <Object?>[
        null,
        'warm',
        {'type': 'warm'},
        {'isFirebaseMessaging': true, 'messageType': 'push-received'},
        {'type': kPushBridgeType},
      ]) {
        expect(pushBridgeMessageOf(raw), isNull, reason: '$raw');
      }
    });

    test('nur Zeichenketten in data — wie FCM sie liefert', () {
      final m = pushBridgeMessageOf({
        'type': kPushBridgeType,
        'kind': 'tap',
        'data': {'route': '/trail/x', 'n': 3, 'x': null},
      })!;
      expect(m.message.data, {'route': '/trail/x'});
    });
  });
}
