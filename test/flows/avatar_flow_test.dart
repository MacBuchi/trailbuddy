import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/widgets/letter_avatar.dart';
import 'package:trailbuddy/core/widgets/rider_avatar.dart';
import 'package:trailbuddy/features/friends/conversation_screen.dart';
import 'package:trailbuddy/features/friends/friends_screen.dart'
    show messageButtonKey;
import 'package:trailbuddy/features/profile/avatar_editor_screen.dart';
import 'package:trailbuddy/models/avatar_config.dart';
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
    for (final invalid in [
      {...bikePark.toJson(), 'v': 2},
      {...bikePark.toJson(), 'hair': 'unknown'},
      {...bikePark.toJson(), 'skin': 42},
      {...bikePark.toJson(), 'extra': 'outside the catalog'},
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

    await tapText('Avatar bearbeiten');
    expect(draft(), isNull);
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
    expect(me.avatarConfig, selected);
    await tapText('Speichern');
    expect(find.byType(AvatarEditorScreen), findsNothing);
    expect(me.avatarConfig, isNull);
    expect(find.byType(LetterAvatar), findsOneWidget);
  });

  testWidgets(
    'only confirmed buddies show the selected portrait in list and chat',
    (tester) async {
      final backend = FakeBackend();
      final me = backend.addUser(username: 'rider');
      final buddy = backend.addUser(username: 'ava')..avatarConfig = bikePark;
      final pending = backend.addUser(username: 'ben')..avatarConfig = bikePark;
      backend.addFriendship(me.id, buddy.id);
      backend.addFriendship(me.id, pending.id, status: 'pending');
      backend.signInAs(me.id);
      await pumpApp(tester, backend);
      await openTab(tester, 'Buddys');

      expect(find.byType(AvatarPortrait), findsOneWidget);
      final openChat = find.byKey(messageButtonKey(buddy.id));
      await tester.ensureVisible(openChat);
      await settle(tester);
      await tester.tap(openChat);
      await settle(tester);
      expect(find.byType(ConversationScreen), findsOneWidget);
      expect(find.byType(AvatarPortrait), findsOneWidget);
    },
  );
}
