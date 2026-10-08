// „Zeig es mir" (#135) — jede Vorführung aus „Entdecken" heraus, in der
// echten App (Vorlage PilzBuddys `highlight_demos_flow_test.dart`).
//
// Für JEDEN Eintrag:
//   1. Es gibt eine Vorführung, und sie zeigt mindestens einen Schritt.
//   2. Jeder gezeigte Schritt findet sein Ziel.
//   3. Die Blase liegt ganz im Bild.
//   4. Danach ist nichts mehr offen und nichts ausgelöst.
//   5. Was nicht jeder hat, hat einen Ersatzschritt.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/router.dart';
import 'package:trailbuddy/features/coach/coach.dart';
import 'package:trailbuddy/features/highlights/feature_highlights.dart';
import 'package:trailbuddy/features/highlights/highlight_demos.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

final bubble = find.byKey(const ValueKey('coach-bubble'));

CoachPainter painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((c) => c.painter)
    .whereType<CoachPainter>()
    .single;

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;

  FakeBackend world({bool trail = true, bool buddy = true}) {
    backend = FakeBackend();
    final me = backend.addUser(username: 'testrail').id;
    backend.signInAs(me);
    trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    if (trail) trails.seedTrail(me, name: 'Hexentanz', grade: 2, traits: {TrailTrait.flowy});
    if (buddy) backend.addFriendship(me, backend.addUser(username: 'mira').id);
    return backend;
  }

  Future<void> openDiscover(WidgetTester tester) async {
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
        .read(routerProvider)
        .go('/profile/discover');
    await settle(tester);
  }

  Future<List<String>> run(WidgetTester tester, String id) async {
    await openDiscover(tester);
    final button = find.byKey(ValueKey('show-$id'));
    // Mehr als die Vorgabe von 50 Zügen: Auf 360×740 ist „Entdecken" seit
    // 0.93.0 länger als 50 × 300 px — der letzte Eintrag kam nie ins Bild.
    await tester.scrollUntilVisible(button, 300, maxScrolls: 120,
        scrollable: find.descendant(of: find.byKey(const ValueKey('discover-list')), matching: find.byType(Scrollable)));
    await tester.ensureVisible(button);
    await settle(tester, frames: 3);
    await tester.tap(button);
    await settle(tester);

    final script = kHighlightDemos[id]!.script;
    final shown = <String>[];
    for (var i = 0; i < 12 && bubble.evaluate().isNotEmpty; i++) {
      final step = script.steps
          .firstWhere((s) => find.descendant(of: bubble, matching: find.text(s.title)).evaluate().isNotEmpty);
      shown.add(step.title);
      for (var f = 0; f < 40 && painter(tester).lit.length != step.lit.length; f++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(painter(tester).lit, hasLength(step.lit.length), reason: '$id, „${step.title}": Ziel nicht gefunden');
      final screen = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
      final box = tester.getRect(bubble);
      expect(screen.contains(box.topLeft) && screen.contains(box.bottomRight - const Offset(1, 1)), isTrue,
          reason: '$id, „${step.title}": Blase $box außerhalb');
      final last = find.descendant(of: bubble, matching: find.text('Los geht\'s'));
      await tester.tap(last.evaluate().isNotEmpty ? last : find.descendant(of: bubble, matching: find.text('Weiter')));
      await settle(tester);
    }
    expect(bubble, findsNothing, reason: '$id: läuft noch');
    expect(find.byType(BottomSheet), findsNothing, reason: '$id: Blatt offen');
    expect(find.byType(Dialog), findsNothing, reason: '$id: Dialog offen');
    expect(find.byKey(const ValueKey('offline-tool-rail')), findsNothing, reason: '$id: Leiste offen');
    return shown;
  }

  test('jeder Eintrag hat eine Vorführung, und keine ist leer', () {
    expect(kHighlightDemos.keys.toSet(), {for (final h in kFeatureHighlights) h.id});
    for (final demo in kHighlightDemos.values) {
      expect(demo.script.steps, isNotEmpty, reason: demo.script.id);
    }
  });

  for (final h in kFeatureHighlights) {
    testWidgets('„${h.title}": vorgeführt, danach nichts offen', (tester) async {
      await pumpApp(tester, world(), trails: trails);
      expect(await run(tester, h.id), isNotEmpty, reason: h.id);
    });
  }

  testWidgets('auf 360×740 findet jede ihr Ziel, im Bild', (tester) async {
    tester.view.physicalSize = const Size(360, 740) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    for (final h in kFeatureHighlights) {
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, world(), trails: trails);
      expect(await run(tester, h.id), isNotEmpty, reason: h.id);
    }
  });

  testWidgets('ohne Trail: der Ersatzschritt am Import-Symbol', (tester) async {
    await pumpApp(tester, world(trail: false), trails: trails);
    expect(await run(tester, 'trail-notes'), ['Erst einen Trail holen']);
  });

  testWidgets('ohne Buddy: das Suchfeld statt des Stifts', (tester) async {
    await pumpApp(tester, world(buddy: false), trails: trails);
    expect(await run(tester, 'buddy-alias'), ['Erst einen Buddy finden']);
  });

  testWidgets('Melden: endet im echten Blatt, und das geht wieder zu', (tester) async {
    await pumpApp(tester, world(), trails: trails);
    expect(await run(tester, 'reports'), ['Einen Trail öffnen', 'Hier melden']);
  });

  testWidgets('die Tour des Reiters fällt nicht über die Vorführung her', (tester) async {
    await pumpApp(tester, world(), trails: trails, settings: FakeSettings(seenCoachTours: const {'split'}));
    final shown = await run(tester, 'reports');
    expect(shown.first, 'Einen Trail öffnen');
    await settle(tester);
    expect(bubble, findsNothing, reason: 'keine Tour hinterher');
  });
}
