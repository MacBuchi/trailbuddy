// Benachrichtigung bei einer Nachricht (#34 Stufe 2, Patch 022; Vorlage
// PilzBuddy #564) — was die App mit
// ihr tut: im Vordergrund zeigen (außer im selben Verlauf), beim Tipp
// den Verlauf öffnen, und nie einem Ziel folgen, das nicht auf der
// Erlaubnisliste steht.
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/push_messaging.dart';
import 'package:trailbuddy/core/push_routes.dart';
import 'package:trailbuddy/data/message_repository.dart';
import 'package:trailbuddy/features/friends/conversation_screen.dart';
import 'package:trailbuddy/features/friends/friends_screen.dart';
import 'package:trailbuddy/models/buddy_message.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  const bertId = 'bbbbbbbb-0000-4000-8000-00000000000b';

  late FakeBackend backend;
  late FakeUser me;
  late StreamController<RemoteMessage> foreground;
  late StreamController<RemoteMessage> taps;

  setUp(() {
    backend = FakeBackend();
    me = backend.addUser(username: 'testrail');
    // Mit echter UUID: Die Erlaubnisliste nimmt nur diese Form an, und
    // die Fake-Kennungen („user-2") hätten sie nie bestanden.
    backend.users.add(FakeUser(
        id: bertId, email: 'bert@example.org', password: 'pw12345678',
        username: 'bert'));
    backend.signInAs(me.id);
    backend.addFriendship(me.id, bertId);
    foreground = StreamController<RemoteMessage>.broadcast();
    taps = StreamController<RemoteMessage>.broadcast();
    addTearDown(foreground.close);
    addTearDown(taps.close);
  });

  RemoteMessage pushFromBert(String text) => RemoteMessage(
        notification: RemoteNotification(title: 'bert', body: text),
        data: const {'route': '/friends/chat/$bertId'},
      );

  void arrive(String text) {
    final now = DateTime.now();
    backend.messages.add(BuddyMessage(
      id: 'm-${backend.messages.length}',
      senderId: bertId,
      recipientId: me.id,
      body: text,
      createdAt: now,
      expiresAt: now.add(const Duration(days: kMessageDays)),
    ));
  }

  Future<void> start(WidgetTester tester,
      {RemoteMessage? initial}) =>
      pumpApp(tester, backend, extraOverrides: [
        pushMessageListenerProvider.overrideWithValue(() => foreground.stream),
        pushTapListenerProvider.overrideWithValue(() => taps.stream),
        pushInitialMessageProvider.overrideWithValue(() async => initial),
      ]);

  test('nur der Verlauf mit einem Buddy ist ein erlaubtes Ziel', () {
    expect(pushRouteOf(const {'route': '/friends/chat/$bertId'}),
        '/friends/chat/$bertId');
    for (final route in [
      '/profile',
      '/friends/chat/bert',
      '/friends/chat/$bertId/../../profile',
      'https://example.org/friends/chat/$bertId',
      '/friends/chat/$bertId?x=1',
    ]) {
      expect(pushRouteOf({'route': route}), isNull, reason: route);
    }
    expect(pushRouteOf(const {}), isNull);
    expect(pushRouteOf(const {'route': 42}), isNull);
  });

  testWidgets('im Vordergrund: Leiste mit „Öffnen", die in den Verlauf '
      'führt — und der Reiter-Punkt kommt sofort', (tester) async {
    await start(tester);
    arrive('Hast du Zeit?');
    foreground.add(pushFromBert('Hast du Zeit?'));
    await settle(tester, frames: 12);

    expect(find.text('Hast du Zeit?'), findsOneWidget);
    expect(find.byKey(const Key('buddys-unread-badge')), findsWidgets,
        reason: 'die Liste ist nach der Meldung neu geholt');
    await tester.tap(find.text('Öffnen'));
    await settle(tester, frames: 16);
    expect(find.byKey(kMessageFieldKey), findsOneWidget);
    expect(find.text('Hast du Zeit?'), findsOneWidget,
        reason: 'jetzt im Verlauf, die Leiste ist weg');
    expect(backend.messages.single.readAt, isNotNull);
  });

  testWidgets('im selben Verlauf: keine Leiste, die Nachricht steht '
      'einfach da', (tester) async {
    await start(tester);
    await openTab(tester, 'Buddys');
    await tester.tap(find.byKey(messageButtonKey(bertId)));
    await settle(tester, frames: 12);

    arrive('Bin gleich da');
    foreground.add(pushFromBert('Bin gleich da'));
    await settle(tester, frames: 16);

    expect(find.text('Öffnen'), findsNothing);
    expect(find.text('Bin gleich da'), findsOneWidget,
        reason: 'einmal — im Verlauf, nicht noch einmal als Leiste');
  });

  testWidgets('Tipp auf die Meldung öffnet den Verlauf', (tester) async {
    await start(tester);
    arrive('Treffpunkt Trailkopf');
    taps.add(pushFromBert('Treffpunkt Trailkopf'));
    await settle(tester, frames: 16);

    expect(find.byKey(kMessageFieldKey), findsOneWidget);
    expect(find.text('Treffpunkt Trailkopf'), findsOneWidget);
  });

  testWidgets('auch wenn die App erst durch den Tipp startet',
      (tester) async {
    arrive('Guten Morgen');
    await start(tester, initial: pushFromBert('Guten Morgen'));
    await settle(tester, frames: 16);

    expect(find.byKey(kMessageFieldKey), findsOneWidget);
    expect(find.text('Guten Morgen'), findsOneWidget);
  });

  testWidgets('ein fremdes Ziel wird nicht verfolgt', (tester) async {
    await start(tester);
    taps.add(const RemoteMessage(
        notification: RemoteNotification(title: 'x', body: 'y'),
        data: {'route': '/profile'}));
    await settle(tester, frames: 12);

    expect(find.byKey(kMessageFieldKey), findsNothing);
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 0,
        reason: 'die Karte steht weiter vorne — nichts wurde geöffnet');
  });
}
