// Zurück nach Hierarchie (#175): erst schließt, was oben liegt — Blatt,
// Unterseite —, an der Wurzel eines anderen Reiters führt Zurück auf die
// Karte, und erst auf der Karte geht es an Android (das die App dann in
// den Hintergrund legt, `MainActivity.popSystemNavigator`).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:trailbuddy/features/help/help_screen.dart';
import 'package:trailbuddy/features/map/map_screen.dart';
import 'package:trailbuddy/features/profile/profile_screen.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;

  setUp(() {
    backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'anna').id);
  });

  int tab(WidgetTester tester) =>
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await settle(tester);
  }

  /// Zurück wie die Android-Taste; `true` heißt: die App hat es genommen.
  Future<bool> back(WidgetTester tester) async {
    final handled = await tester.binding.handlePopRoute();
    await settle(tester);
    return handled;
  }

  testWidgets(
    'an der Wurzel eines Reiters führt Zurück auf die Karte, erst dort an Android',
    (tester) async {
      await pumpApp(tester, backend);
      await settle(tester, frames: 20);
      for (final label in ['Trails', 'Buddys', 'Profil']) {
        await tapTab(tester, label);
        expect(tab(tester), isNot(0), reason: label);
        expect(
          await back(tester),
          isTrue,
          reason: '$label: die App nimmt Zurück',
        );
        expect(tab(tester), 0, reason: '$label: zurück auf der Karte');
      }
      // Auf der Karte, nichts offen: Zurück geht an das System.
      expect(await back(tester), isFalse);
      expect(
        find.byType(MapScreen),
        findsOneWidget,
        reason: 'die App steht noch',
      );
    },
  );

  testWidgets(
    'eine Unterseite schließt zuerst, dann der Reiter, dann die App',
    (tester) async {
      await pumpApp(tester, backend);
      await settle(tester, frames: 20);
      GoRouter.of(tester.element(find.byType(MapScreen))).go('/profile/help');
      await settle(tester);
      expect(find.byType(HelpScreen), findsOneWidget);

      expect(await back(tester), isTrue);
      expect(
        find.byType(HelpScreen),
        findsNothing,
        reason: 'die Kurzanleitung ist zu',
      );
      expect(tab(tester), 3, reason: 'noch im Profil');
      expect(find.byType(ProfileScreen), findsOneWidget);

      expect(await back(tester), isTrue);
      expect(tab(tester), 0, reason: 'auf der Karte');

      expect(await back(tester), isFalse);
    },
  );

  testWidgets('auf der Karte schließt Zurück erst das Blatt', (tester) async {
    await pumpApp(tester, backend);
    await settle(tester, frames: 20);
    await tester.tap(find.byTooltip('Kartenebenen'));
    await settle(tester);
    expect(
      find.byKey(const ValueKey('official-trails-switch')),
      findsOneWidget,
    );

    expect(await back(tester), isTrue);
    expect(find.byKey(const ValueKey('official-trails-switch')), findsNothing);
    expect(tab(tester), 0);

    expect(await back(tester), isFalse);
  });

  testWidgets(
    'ein Dialog über einem anderen Reiter schließt, ohne den Reiter zu wechseln',
    (tester) async {
      await pumpApp(tester, backend);
      await settle(tester, frames: 20);
      await tapTab(tester, 'Profil');
      // Ein Dialog liegt über dem ganzen Reiter (Wurzel-Navigator).
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(ProfileScreen)),
          builder: (_) => const AlertDialog(content: Text('Testdialog')),
        ),
      );
      await settle(tester);
      expect(find.text('Testdialog'), findsOneWidget);

      expect(await back(tester), isTrue);
      expect(find.text('Testdialog'), findsNothing);
      expect(tab(tester), 3, reason: 'erst der Dialog, der Reiter bleibt');

      expect(await back(tester), isTrue);
      expect(tab(tester), 0);
    },
  );
}
