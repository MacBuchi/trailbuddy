// Der S-Grad als Form (Design Turn 4, Schritt 6a): Schild in Liste,
// Blatt und Erklärblatt.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/trails/grade_shield.dart';
import 'package:trailbuddy/features/trails/trail_traits.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  test('die Form wird mit dem Grad nicht schmaler, S4 und S5 tragen mehr', () {
    final widths = [for (var g = 0; g <= 5; g++) gradeShapeWidth(g, 10)];
    expect(widths.sublist(0, 4), everyElement(10));
    expect(widths[4], greaterThan(widths[3]));
    expect(widths[5], greaterThan(widths[4]));
  });

  (FakeBackend, FakeTrailRepository) setup() {
    final backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    final trails = FakeTrailRepository(
      myId: () => backend.currentUserId ?? '',
      areFriends: backend.areFriends,
    );
    trails.seedTrail(
      anna.id,
      name: 'Steiler Hang mit sehr langem Namen',
      grade: 5,
      traits: {TrailTrait.rocky, TrailTrait.steep},
    );
    trails.seedTrail(anna.id, name: 'Ohne Grad', lat: 48.1);
    return (backend, trails);
  }

  testWidgets(
    'Liste: Schild rechts oben mit Form und Satz — ohne Einschätzung keins, '
    'und auf 360 dp läuft nichts über',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2220);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final (backend, trails) = setup();
      await pumpApp(tester, backend, trails: trails);
      await openTab(tester, 'Trails');
      await settle(tester, frames: 20);

      final shields = find.byKey(const ValueKey('grade-shield'));
      expect(shields, findsOneWidget, reason: 'nur der Trail mit Einschätzung');
      expect(
        findLabel('Schwierigkeit S5: extrem, kaum fahrbar'),
        findsOneWidget,
      );
      // Die Zahl steht nicht mehr doppelt in der Zahlenzeile.
      expect(find.textContaining('· S5'), findsNothing);
      // Rechts oben: über den Charakter-Symbolen, am rechten Rand der Karte.
      final shield = tester.getRect(shields);
      final icon = tester.getRect(find.byIcon(TrailTrait.rocky.icon));
      expect(shield.bottom, lessThanOrEqualTo(icon.top));
      expect(shield.right, greaterThan(300));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Blatt: Schild neben dem Namen, derselbe Median wie in der Kachel',
    (tester) async {
      final (backend, trails) = setup();
      await pumpApp(tester, backend, trails: trails);
      await openTab(tester, 'Trails');
      await settle(tester, frames: 20);
      await tester.tap(find.text('Steiler Hang mit sehr langem Namen'));
      await settle(tester);

      final title = tester.getRect(
        find.byKey(const ValueKey('trail-sheet-title')),
      );
      final shield = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byKey(const ValueKey('grade-shield')),
      );
      expect(shield, findsOneWidget);
      expect(tester.getRect(shield).left, greaterThan(title.right - 1));
      expect(findLabel('S5 · 1 Einschätzung'), findsOneWidget);
    },
  );
}
