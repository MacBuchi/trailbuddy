import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/widgets/rider_avatar.dart';
import 'package:trailbuddy/features/nearby/buddy_map_layer.dart';
import 'package:trailbuddy/features/profile/avatar_editor_screen.dart';
import 'package:trailbuddy/l10n/app_localizations.dart';
import 'package:trailbuddy/models/avatar_config.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  testWidgets('all avatar options at live marker, chat and editor sizes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 800);
    addTearDown(tester.view.reset);
    final backend = FakeBackend();
    final me = backend.addUser(username: 'rider');
    backend.signInAs(me.id);
    await pumpApp(tester, backend);
    await openTab(tester, 'Profil');
    await tester.tap(find.text('Avatar bearbeiten'));
    await settle(tester);

    final presets = tester
        .widgetList<AvatarPortrait>(
          find.descendant(
            of: find.byType(AvatarEditorScreen),
            matching: find.byType(AvatarPortrait),
          ),
        )
        .map((portrait) => portrait.config)
        .toList();
    expect(presets, hasLength(8));
    final portraits = [
      ...presets,
      for (final (hair, beard) in [
        ('sidePart', 'mustache'),
        ('undercut', 'goatee'),
        ('fringe', 'handlebar'),
        ('bun', 'shortBoxed'),
        ('ponytail', 'long'),
        ('mohawk', 'chinstrap'),
      ])
        AvatarConfig.standard
            .withPart(AvatarPart.headwear, 'none')
            .withPart(AvatarPart.hair, hair)
            .withPart(AvatarPart.beard, beard),
      for (final tint in AvatarPart.goggleTint.options)
        presets[1].withPart(AvatarPart.goggleTint, tint),
    ];
    for (final part in AvatarPart.values) {
      expect(
        portraits.map((config) => config[part]).toSet(),
        part.options.toSet(),
      );
    }

    const fixture = ValueKey('avatar-portrait-comparison');
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Center(
          child: RepaintBoundary(
            key: fixture,
            child: ColoredBox(
              color: const Color(0xFFF1F0E9),
              child: SizedBox(
                width: 768,
                child: Wrap(
                  children: [
                    for (final config in portraits)
                      SizedBox(
                        width: 96,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox.square(
                              dimension: BuddyDisc.extent,
                              child: BuddyDisc(
                                initial: 'R',
                                live: true,
                                avatar: config,
                              ),
                            ),
                            RiderAvatar(
                              name: 'Rider',
                              config: config,
                              size: 32,
                            ),
                            const SizedBox(height: 12),
                            RiderAvatar(
                              name: 'Rider',
                              config: config,
                              size: 88,
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byKey(fixture),
      matchesGoldenFile('goldens/avatar_portraits.png'),
    );
  });
}
