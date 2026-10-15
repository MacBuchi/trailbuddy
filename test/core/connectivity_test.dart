import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/connectivity.dart';

void main() {
  group('startingWith', () {
    test('erst der jetzige Stand, dann die Wechsel', () async {
      final changes = StreamController<String>();
      final seen = <String>[];
      startingWith(Future.value('jetzt'), changes.stream).listen(seen.add);
      await pumpEventQueue();
      changes.add('danach');
      await pumpEventQueue();
      expect(seen, ['jetzt', 'danach']);
      await changes.close();
    });

    test('ein schnellerer Wechsel überholt den Stand', () async {
      final changes = StreamController<String>();
      final current = Completer<String>();
      final seen = <String>[];
      startingWith(current.future, changes.stream).listen(seen.add);
      changes.add('neu');
      await pumpEventQueue();
      current.complete('alt');
      await pumpEventQueue();
      expect(seen, ['neu']);
      await changes.close();
    });

    test('scheitert die Abfrage, kommen nur die Wechsel', () async {
      final changes = StreamController<String>();
      final seen = <String>[];
      startingWith(Future<String>.error(StateError('kein Kanal')), changes.stream)
          .listen(seen.add, onError: (Object e) => fail('$e'));
      await pumpEventQueue();
      changes.add('danach');
      await pumpEventQueue();
      expect(seen, ['danach']);
      await changes.close();
    });
  });

  // Der Fall aus dem Browser-Check von 0.102.0 (#153): Start ohne
  // Empfang, und der Strom meldet nur Wechsel (wie im Browser). Die
  // Rückkehr des Netzes muss ein Wechsel von „kein Netz" auf „verbunden"
  // sein — daran hängen Ausgangskorb und Neuladen (`map_screen.dart`).
  // Gefahren wird der ECHTE Provider, über die Kanäle des Plugins.
  testWidgets('Start ohne Empfang, Strom ohne Anfang: die Rückkehr ist ein Wechsel', (tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async => call.method == 'check' ? ['none'] : null);
    MockStreamHandlerEventSink? sink;
    messenger.setMockStreamHandler(const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
        MockStreamHandler.inline(onListen: (_, s) {
          sink = s;
        }));
    addTearDown(() {
      messenger.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/connectivity'), null);
      messenger.setMockStreamHandler(const EventChannel('dev.fluttercommunity.plus/connectivity_status'), null);
    });

    final container = ProviderContainer();
    final states = <bool>[];
    container.listen<bool>(noConnectivityProvider, (_, next) => states.add(next), fireImmediately: true);
    await tester.pump();
    expect(container.read(noConnectivityProvider), isTrue, reason: 'der Anfang ohne Wechsel');
    sink!.success(['wifi']);
    await tester.pump();
    expect(container.read(noConnectivityProvider), isFalse);
    await tester.pump();
    expect(states, [false, true, false]);
    container.dispose();
    await tester.pump(const Duration(seconds: 1));
  });
}
