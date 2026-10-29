// Die Touren je Reiter (#136, Plan `docs/konzept-onboarding.md` 3.5, 4.2,
// 4.3; Vorlage PilzBuddys `tab_tours_flow_test.dart`).
//
// Die Zusagen:
//
//   1. Beim ersten Besuch des Reiters läuft seine Tour, danach nie wieder.
//   2. Ohne eigene Daten zeigt sie Beispiele — nur während der Tour, immer
//      als „Beispiel", und nichts davon landet im Fake-Repository.
//   3. Mit echten Daten kein Beispiel; die Tour zeigt auf die echte Zeile.
//   4. Karten-Tour und Hinweis gehen vor; beim ersten Start fragt die Kette
//      an jeder Grenze, „Später" beendet sie.
//   5. Überspringen im Blatt lässt nichts offen; die Blase liegt auf
//      360×740 im Bild.
//   6. Aus der Kurzanleitung neu startbar; jede Reiter-Tour steht in der
//      Fake-Vorgabe „gesehen".
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/coach/coach.dart';
import 'package:trailbuddy/features/help/map_tour.dart';
import 'package:trailbuddy/features/help/tab_tours.dart';
import 'package:trailbuddy/features/help/tour_examples.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';
import '../fakes/l10n_de.dart';

final intro = find.byKey(const ValueKey('coach-intro'));
final bubble = find.byKey(const ValueKey('coach-bubble'));

CoachPainter painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((c) => c.painter)
    .whereType<CoachPainter>()
    .single;

String shownTitle(WidgetTester tester) =>
    tester.widgetList<Text>(find.descendant(of: bubble, matching: find.byType(Text))).first.data!;

void main() {
  late FakeBackend backend;
  late String me;
  late FakeTrailRepository trails;

  setUp(() {
    backend = FakeBackend();
    me = backend.addUser(username: 'testrail').id;
    backend.signInAs(me);
    trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
  });

  /// Karten-Tour und Hinweis gesehen, die Reiter-Touren nicht.
  FakeSettings tabsFresh() => FakeSettings(seenCoachTours: const {'split'});

  /// Durch die laufende Tour tippen und die Titel der Blasen sammeln.
  Future<List<String>> runThrough(WidgetTester tester) async {
    final seen = <String>[];
    for (var i = 0; i < 12 && bubble.evaluate().isNotEmpty; i++) {
      seen.add(shownTitle(tester));
      final done = find.descendant(of: bubble, matching: find.text('Los geht\'s'));
      await tester.tap(done.evaluate().isNotEmpty ? done : find.descendant(of: bubble, matching: find.text('Weiter')));
      await settle(tester);
    }
    return seen;
  }

  testWidgets('Trails ohne Trail: Beispiele während der Tour, danach weg — '
      'und nichts gespeichert', (tester) async {
    final settings = tabsFresh();
    await pumpApp(tester, backend, trails: trails, settings: settings);
    await openTab(tester, 'Trails');

    expect(find.text('Deine Trails'), findsOneWidget, reason: 'die Startseite');
    await tester.tap(find.byKey(const ValueKey('coach-intro-start')));
    await settle(tester);
    expect(find.byKey(kExampleTrailKey), findsOneWidget);
    expect(find.byKey(const Key('tour-example-badge')), findsWidgets);
    expect(find.text('Beispiel: Buchenhang'), findsOneWidget, reason: 'auch im Namen');

    final titles = await runThrough(tester);
    expect(titles, [
      'Eine Zeile lesen',
      'Zahlen und Profil',
      'Deine Einschätzung',
      'Was du beisteuerst',
      'Etwas Aktuelles erzählen',
      'Suchen und eingrenzen',
      'GPX hereinholen',
    ]);
    expect(settings.seenCoachTours, contains('trails'));
    expect(find.byKey(kExampleTrailKey), findsNothing, reason: 'nach der Tour ist das Beispiel weg');
    expect(find.byKey(kExampleTrailSheetKey), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(trails.recordings, isEmpty, reason: 'nichts landet im Fake-Repository');
    expect(trails.details, isEmpty);
    expect(trails.contributeCalls, 0);
    expect(find.byKey(const ValueKey('trails-total')), findsNothing, reason: 'keine Summe über ein Beispiel');
    expect(find.textContaining('Noch keine Trails'), findsOneWidget);

    await openTab(tester, 'Karte');
    await openTab(tester, 'Trails');
    expect(intro, findsNothing, reason: 'nie wieder');
  });

  testWidgets('mit einem eigenen Trail: kein Beispiel, das echte Blatt', (tester) async {
    trails.seedTrail(me, name: 'Hexentanz', grade: 2);
    await pumpApp(tester, backend, trails: trails, settings: tabsFresh());
    await openTab(tester, 'Trails');
    await tester.tap(find.byKey(const ValueKey('coach-intro-start')));
    await settle(tester);
    expect(find.byKey(kExampleTrailKey), findsNothing);
    final row = find.byWidgetPredicate((w) => w is CoachAnchor && w.id == TrailsCoach.row);
    expect(find.descendant(of: row, matching: find.text('Hexentanz')), findsOneWidget);
    await tester.tap(find.descendant(of: bubble, matching: find.text('Weiter')));
    await settle(tester);
    expect(find.text('HEXENTANZ'), findsOneWidget, reason: 'das echte Blatt');
    expect(find.byKey(const ValueKey('trail-contribution')), findsOneWidget);
  });

  testWidgets('ein Buddy-Trail: Einschätzung und Beitrag fallen weg', (tester) async {
    final ben = backend.addUser(username: 'ben').id;
    backend.addFriendship(me, ben);
    trails.seedTrail(ben, name: 'Bens Hang', grade: 1);
    await pumpApp(tester, backend, trails: trails, settings: tabsFresh());
    await openTab(tester, 'Trails');
    await tester.tap(find.byKey(const ValueKey('coach-intro-start')));
    await settle(tester);
    final titles = await runThrough(tester);
    expect(titles, isNot(contains('Deine Einschätzung')));
    expect(titles, isNot(contains('Was du beisteuerst')));
    expect(titles, contains('Etwas Aktuelles erzählen'));
  });

  testWidgets('Überspringen im Blatt lässt nichts offen; die Blase liegt '
      'auf 360×740 im Bild', (tester) async {
    tester.view.physicalSize = const Size(360, 740) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, backend, trails: trails, settings: tabsFresh());
    await openTab(tester, 'Trails');
    await tester.tap(find.byKey(const ValueKey('coach-intro-start')));
    await settle(tester);
    for (var i = 0; i < 3; i++) {
      final b = tester.getRect(bubble);
      final screen = Offset.zero & const Size(360, 740);
      expect(screen.contains(b.topLeft) && screen.contains(b.bottomRight - const Offset(1, 1)), isTrue,
          reason: '„${shownTitle(tester)}": Blase $b außerhalb');
      for (final r in [...painter(tester).lit, ...painter(tester).ring]) {
        expect(b.overlaps(r), isFalse, reason: '„${shownTitle(tester)}": Blase $b deckt $r zu');
      }
      await tester.tap(find.descendant(of: bubble, matching: find.text('Weiter')));
      await settle(tester);
    }
    expect(find.byKey(kExampleTrailSheetKey), findsOneWidget, reason: 'das Beispiel-Blatt ist offen');
    await tester.tap(find.descendant(of: bubble, matching: find.text('Überspringen')));
    await settle(tester);
    expect(find.byKey(kExampleTrailSheetKey), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Buddys ohne Buddy: der Beispiel-Buddy, nichts gespeichert', (tester) async {
    final settings = tabsFresh();
    await pumpApp(tester, backend, trails: trails, settings: settings);
    await openTab(tester, 'Buddys');
    expect(find.text('Deine Buddys'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('coach-intro-start')));
    await settle(tester);
    expect(find.byKey(kExampleBuddyKey), findsOneWidget);
    final titles = await runThrough(tester);
    expect(titles, ['Jemanden einladen', 'Nach Buddys suchen', 'Ein Buddy in der Liste', 'Beim Verbinden'],
        reason: 'ohne offene Anfragen fällt der Schritt weg');
    expect(settings.seenCoachTours, contains('buddys'));
    expect(find.byKey(kExampleBuddyKey), findsNothing);
    expect(backend.friendships, isEmpty, reason: 'nichts landet im Fake');
    expect(backend.aliases, isEmpty);
  });

  testWidgets('offene Anfragen: der Schritt ist dabei', (tester) async {
    final mira = backend.addUser(username: 'mira').id;
    backend.addFriendship(mira, me, status: 'pending');
    await pumpApp(tester, backend, trails: trails, settings: tabsFresh());
    await openTab(tester, 'Buddys');
    await tester.tap(find.byKey(const ValueKey('coach-intro-start')));
    await settle(tester);
    expect(await runThrough(tester), contains('Offene Anfragen'));
  });

  testWidgets('die Karten-Tour geht vor: erster Start, dann die Kette — '
      '„Später" beendet sie', (tester) async {
    final settings = FakeSettings(mapTourSeen: false, seenCoachTours: const {'split'});
    await pumpApp(tester, backend, trails: trails, settings: settings);
    expect(find.text('Willkommen bei TrailBuddy'), findsOneWidget, reason: 'nicht die Trails-Tour');
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('coach-intro-start')));
    await settle(tester);
    await runThrough(tester);
    expect(settings.mapTourSeen, isTrue);

    await settle(tester, frames: 6);
    expect(find.text('Weiter mit den Trails?'), findsOneWidget, reason: 'die Kette fragt');
    expect(find.text('Später'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('coach-intro-start')));
    await settle(tester);
    expect(find.byKey(kExampleTrailKey), findsOneWidget, reason: 'auf dem Reiter Trails, mit Beispiel');
    await runThrough(tester);
    expect(settings.seenCoachTours, contains('trails'));

    await settle(tester, frames: 6);
    expect(find.text('Weiter mit den Buddys?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('coach-intro-later')));
    await settle(tester);
    expect(intro, findsNothing);
    expect(settings.seenCoachTours, contains('buddys'), reason: '„Später" ist gemerkt (#417)');
  });

  testWidgets('„Nicht jetzt" ist gemerkt, auch über einen Neustart (#417)', (tester) async {
    final settings = tabsFresh();
    await pumpApp(tester, backend, trails: trails, settings: settings);
    await openTab(tester, 'Trails');
    await tester.tap(find.byKey(const ValueKey('coach-intro-later')));
    await settle(tester);
    await openTab(tester, 'Karte');
    await openTab(tester, 'Trails');
    expect(intro, findsNothing);
    expect(settings.seenCoachTours, contains('trails'));

    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, backend, trails: trails, settings: settings);
    await openTab(tester, 'Trails');
    expect(intro, findsNothing, reason: 'kein Kaltstart fragt wieder');
  });

  testWidgets('ein verdeckter Reiter startet nichts', (tester) async {
    // Der Reiter Trails ist gebaut (einmal besucht) und liegt verdeckt im
    // IndexedStack. Baut er sich neu — hier über eine bestellte Tour —,
    // darf auf der Karte nichts aufgehen; erst wenn er sichtbar ist.
    await pumpApp(tester, backend, trails: trails);
    await openTab(tester, 'Trails');
    await openTab(tester, 'Karte');
    ProviderScope.containerOf(tester.element(find.byType(NavigationBar)))
        .read(requestedTabTourProvider.notifier)
        .request(trailsTourScript(l10nDe).id);
    await settle(tester, frames: 12);
    expect(intro, findsNothing, reason: 'nicht über der Karte');
    await openTab(tester, 'Trails');
    expect(find.text('Deine Trails'), findsOneWidget, reason: 'erst auf dem Reiter');
  });

  testWidgets('aus der Kurzanleitung neu startbar, auch wenn gesehen', (tester) async {
    await pumpApp(tester, backend, trails: trails);
    await openProfilePage(tester, 'help');
    final start = find.byKey(const ValueKey('tab-tour-trails'));
    await tester.scrollUntilVisible(start, 300,
        scrollable: find.descendant(of: find.byKey(const ValueKey('help-list')), matching: find.byType(Scrollable)));
    await settle(tester);
    await tester.tap(start);
    await settle(tester);
    expect(find.text('Deine Trails'), findsOneWidget);
  });

  test('jede Reiter-Tour steht in der Fake-Vorgabe „gesehen"', () {
    // Sonst läge über jedem Flow-Test, der einen Reiter öffnet, die Tour.
    for (final script in tabTourScripts(l10nDe)) {
      expect(FakeSettings().seenCoachTours, contains(script.id), reason: script.id);
    }
    expect(tabTourScripts(l10nDe).every((s) => s.examples && s.steps.first.isIntro), isTrue,
        reason: 'Beispiele nur an Skripten MIT Startseite');
  });

  test('die Kette und die Karten-Tour teilen ihre Schritte', () {
    expect(welcomeTourScript(l10nDe).endLink, isNull);
    expect(tabTours(l10nDe).map((t) => t.$1.id), ['trails', 'buddys']);
    expect(trailsTourScript(l10nDe).steps.first.chainTitle, 'Weiter mit den Trails?');
  });

  test('Beispiele gibt es nur als Widgets', () {
    // Kein Modell: kein Trail, keine Aufzeichnung (Plan 3.5, „gezeichnet,
    // nie gespeichert").
    expect(const ExampleTrailTile(), isNot(isA<Trail>()));
  });
}
