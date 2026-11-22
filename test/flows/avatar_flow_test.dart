import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;
import 'package:trailbuddy/core/widgets/letter_avatar.dart';
import 'package:trailbuddy/core/widgets/rider_avatar.dart';
import 'package:trailbuddy/features/friends/conversation_screen.dart';
import 'package:trailbuddy/features/friends/friend_providers.dart';
import 'package:trailbuddy/features/friends/friends_screen.dart'
    show messageButtonKey;
import 'package:trailbuddy/features/profile/avatar_editor_screen.dart';
import 'package:trailbuddy/models/avatar_config.dart';
import 'package:trailbuddy/models/buddy_message.dart';
import 'package:trailbuddy/models/friendship.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  final bikePark = AvatarConfig.standard
      .withPart(AvatarPart.headwear, 'fullface')
      .withPart(AvatarPart.expression, 'wink');

  test('every option round-trips and invalid profiles fall back', () {
    for (final part in AvatarPart.values) {
      for (final option in part.options) {
        final config = bikePark.withPart(part, option);
        expect(AvatarConfig.tryParse(config.toJson()), config);
      }
    }
    expect(AvatarConfig.fromProfile({'avatar': 0}), isNull);
    expect(bikePark.toJson(), isNot(contains('goggleTint')));
    expect(
      AvatarConfig.tryParse(bikePark.toJson())?[AvatarPart.goggleTint],
      'mirrored',
    );
    for (final invalid in [
      {...bikePark.toJson(), 'v': 2},
      {...bikePark.toJson(), 'hair': 'unknown'},
      {...bikePark.toJson(), 'skin': 42},
      {...bikePark.toJson(), 'extra': 'outside the catalog'},
      {...bikePark.toJson(), 'goggleTint': 'unknown'},
      {...bikePark.toJson(), 'goggleTint': null},
      bikePark.toJson()..remove('headwear'),
    ]) {
      expect(AvatarConfig.tryParse(invalid), isNull);
    }
    final encoded = {
      'profile_avatars': {'config': bikePark.toJson()},
    };
    expect(AvatarConfig.fromProfile(encoded), bikePark);
    expect(
      FriendshipEntry.fromJson({
        'id': 'relationship',
        'status': 'pending',
        'requester_id': 'first',
        'addressee_id': 'second',
        'addressee': encoded,
      }).otherAvatar('first'),
      isNull,
    );
  });

  testWidgets('draft, retry, save, cancel, and reset in the profile', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(850, 950);
    addTearDown(tester.view.reset);
    final backend = FakeBackend();
    final me = backend.addUser(username: 'rider');
    backend.signInAs(me.id);
    await pumpApp(tester, backend);
    await openTab(tester, 'Profil');

    Future<void> tapText(String label) async {
      await tester.tap(find.text(label));
      await settle(tester);
    }

    final preview = find.byKey(const ValueKey('avatar-preview'));
    AvatarConfig? draft() => tester.widget<RiderAvatar>(preview).config;
    final headwear = find.byKey(const ValueKey('avatar-headwear-trail'));
    final color = find.byKey(const ValueKey('avatar-gearColor-blue'));

    await tapText('Avatar bearbeiten');
    expect(draft(), isNull);
    expect(headwear, findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Speichern'))
          .onPressed,
      isNull,
    );
    await tapText('Abbrechen');
    expect(me.avatarConfig, isNull);

    await tapText('Avatar bearbeiten');
    await tapText('Bikepark');
    expect(draft()?[AvatarPart.headwear], 'fullface');
    expect(me.avatarConfig, isNull);
    final selected = draft();

    backend.offline = true;
    await tapText('Speichern');
    expect(
      find.textContaining('Avatar konnte nicht gespeichert werden'),
      findsOneWidget,
    );
    expect(draft(), selected);
    expect(me.avatarConfig, isNull);
    backend.offline = false;
    await tapText('Speichern');
    expect(find.byType(AvatarEditorScreen), findsNothing);
    expect(me.avatarConfig, selected);
    expect(find.byType(AvatarPortrait), findsOneWidget);

    await tapText('Avatar bearbeiten');
    await tapText('Trailrunde');
    await tapText('Abbrechen');
    expect(find.byType(AvatarEditorScreen), findsNothing);
    expect(me.avatarConfig, selected);

    await tapText('Avatar bearbeiten');
    final reset = find.text('Zu Initialen zurück');
    await tester.scrollUntilVisible(reset, 300);
    await tester.tap(reset);
    await settle(tester);
    expect(draft(), isNull);
    expect(headwear, findsNothing);
    expect(me.avatarConfig, selected);
    await tapText('Speichern');
    expect(find.byType(AvatarEditorScreen), findsNothing);
    expect(me.avatarConfig, isNull);
    expect(find.byType(LetterAvatar), findsOneWidget);

    await tapText('Avatar bearbeiten');
    await tapText('Feierabendrunde');
    expect(draft()?[AvatarPart.headwear], 'none');
    expect(color, findsNothing);
    Future<void> tapOption(String key) async {
      final option = find.byKey(ValueKey('avatar-$key'));
      await tester.tap(option.hitTestable());
      await settle(tester);
    }

    await tapOption('headwear-trail');
    await tapOption('gearColor-blue');
    await tapOption('headwear-none');
    expect(color, findsNothing);
    await tapOption('headwear-trail');
    await tester.scrollUntilVisible(color, 120);
    expect(tester.widget<ChoiceChip>(color).selected, isTrue);

    for (final (part, value) in [
      (AvatarPart.hair, 'bun'),
      (AvatarPart.beard, 'goatee'),
      (AvatarPart.glasses, 'goggles'),
      (AvatarPart.goggleTint, 'clear'),
    ]) {
      final style = find.byKey(ValueKey('avatar-${part.name}-$value'));
      await tester.scrollUntilVisible(style.hitTestable(), 120);
      if (part != AvatarPart.glasses) {
        expect(
          find.descendant(of: style, matching: find.byType(AvatarPortrait)),
          findsOneWidget,
        );
      }
      await tester.tap(style.hitTestable());
      await settle(tester);
      expect(draft()?[part], value);
    }
    final customized = draft();
    await tapText('Speichern');
    expect(me.avatarConfig, customized);
    await tapText('Avatar bearbeiten');
    expect(draft(), customized);
  });

  testWidgets(
    'warm chats refresh only their relationship and still fetch and read messages',
    (tester) async {
      final backend = FakeBackend();
      final me = backend.addUser(username: 'rider');
      final buddy = backend.addUser(username: 'ava')..avatarConfig = bikePark;
      final pending = backend.addUser(username: 'ben')..avatarConfig = bikePark;
      final relationship = backend.addFriendship(buddy.id, me.id);
      final second = backend.addUser(username: 'cam');
      backend.addFriendship(me.id, second.id);
      backend.addFriendship(me.id, pending.id, status: 'pending');
      backend.signInAs(me.id);
      await pumpApp(tester, backend);
      await openTab(tester, 'Buddys');

      expect(find.byType(AvatarPortrait), findsOneWidget);
      final openChat = find.byKey(messageButtonKey(buddy.id));
      Future<void> enterChat() async {
        await tester.ensureVisible(openChat);
        await settle(tester);
        await tester.tap(openChat);
        await settle(tester);
      }

      final initialFriendshipReads = backend.friendshipListReads;
      final initialMessageReads = backend.messageListReads;
      final now = DateTime.now();
      backend.messages.add(
        BuddyMessage(
          id: 'new-message',
          senderId: buddy.id,
          recipientId: me.id,
          body: 'Nachricht nach dem Laden',
          createdAt: now,
          expiresAt: now.add(const Duration(days: 1)),
        ),
      );

      await enterChat();
      expect(find.byType(ConversationScreen), findsOneWidget);
      expect(find.byType(AvatarPortrait), findsOneWidget);
      expect(find.text('Nachricht nach dem Laden'), findsOneWidget);
      expect(backend.markReadCalls, 1);
      expect(backend.messages.single.readAt, isNotNull);
      expect(backend.messageListReads, greaterThan(initialMessageReads));

      void backToList() => GoRouter.of(
        tester.element(find.byType(ConversationScreen)),
      ).go('/friends');
      backToList();
      await settle(tester);
      final firstEntryMessageReads = backend.messageListReads;
      await enterChat();
      expect(backend.friendshipListReads, initialFriendshipReads);
      expect(backend.friendshipPairReads, [buddy.id, buddy.id]);
      expect(backend.messageListReads, greaterThan(firstEntryMessageReads));
      expect(backend.markReadCalls, 1);

      // The other person ends the friendship while this list is still warm.
      backToList();
      await settle(tester);
      await FakeFriendRepository(backend).remove(relationship);
      await enterChat();
      expect(find.byType(AvatarPortrait), findsNothing);
      expect(
        tester.widget<TextField>(find.byKey(kMessageFieldKey)).enabled,
        isFalse,
      );
      expect(backend.friendshipListReads, initialFriendshipReads);
    },
  );

  test('cold friendship lookup uses only the initial list', () async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'rider');
    final buddy = backend.addUser(username: 'ava')..avatarConfig = bikePark;
    backend.addFriendship(me.id, buddy.id);
    backend.signInAs(me.id);
    addTearDown(backend.dispose);
    final container = ProviderContainer(overrides: overridesFor(backend));
    addTearDown(container.dispose);

    await container.read(friendshipsProvider.notifier).revalidateWith(buddy.id);
    final entries = await container.read(friendshipsProvider.future);
    expect(entries.single.otherUsername(me.id), buddy.username);
    expect(entries.single.otherAvatar(me.id), bikePark);
    expect(backend.friendshipListReads, 1);
    expect(backend.friendshipPairReads, isEmpty);
  });

  for (final action in ['remove', 'block', 'switch account']) {
    test('a pending lookup cannot restore an avatar after $action', () async {
      final backend = FakeBackend();
      final me = backend.addUser(username: 'rider');
      final buddy = backend.addUser(username: 'ava')..avatarConfig = bikePark;
      final other = backend.addUser(username: 'cam');
      final relationship = backend.addFriendship(me.id, buddy.id);
      backend.signInAs(me.id);
      addTearDown(backend.dispose);
      final container = ProviderContainer(overrides: overridesFor(backend));
      addTearDown(container.dispose);
      final notifier = container.read(friendshipsProvider.notifier);
      await container.read(friendshipsProvider.future);

      final gate = Completer<void>();
      backend.friendshipPairReadGate = gate.future;
      final stale = notifier.revalidateWith(buddy.id);
      expect(backend.friendshipPairReads, [buddy.id]);
      switch (action) {
        case 'remove':
          await notifier.remove(relationship);
        case 'block':
          await container.read(blocksProvider.notifier).block(buddy.id);
        case 'switch account':
          backend.setCurrentUser(other, AuthChangeEvent.signedIn);
          await Future<void>.delayed(Duration.zero);
          await container.read(friendshipsProvider.future);
      }
      gate.complete();
      await stale;
      expect(container.read(friendshipsProvider).valueOrNull, isEmpty);
    });
  }
}
