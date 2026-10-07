// Die geführte Tour über die Karte (#132, Plan `docs/konzept-onboarding.md`
// 3.2 und 4.1; Vorlage PilzBuddys `map_tour_flow_test.dart`).
//
// Die Zusagen, und keine davon ist der Wortlaut:
//
//   1. Sie startet aus der Kurzanleitung, läuft der Reihe nach und merkt
//      sich danach, dass sie gesehen wurde.
//   2. Aussparung und Ring sitzen auf den ECHTEN Widgets, auf einem
//      normalen und einem kleinen Schirm.
//   3. Sie FÜHRT VOR: Ebenen-Blatt, Offline-Leiste und Trail-Blatt gehen
//      auf — und wieder zu.
//   4. Tippen während der Vorführung löst nichts aus.
//   5. Zurück beendet die Tour, nicht die App — und danach gehört die
//      Taste wieder dem System.
//   6. Die Sprechblase liegt ganz im Bild und nie auf dem, was sie erklärt.
//   7. Ohne Trail fallen die beiden Trail-Schritte weg, der Zähler zählt
//      nur, was kommt.
//
// Nach jedem Schritt `settle` (8 × 100 ms): Die Maschine nimmt 400 ms
// nach einem neuen Schritt keinen Tipp an (Tippsperre).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/coach/coach.dart';
import 'package:trailbuddy/features/help/map_tour.dart';
import 'package:trailbuddy/features/map/map_legend.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

CoachPainter painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((c) => c.painter)
    .whereType<CoachPainter>()
    .single;

Rect union(Iterable<Rect> rects) => rects.reduce((a, b) => a.expandToInclude(b));

/// Knapp umfasst: Die Aussparung ist das Element plus 2 px Luft, gemessen
/// über Transformationen — auf Rundung genau.
bool covers(Rect lit, Rect widget) =>
    lit.inflate(0.5).contains(widget.topLeft) &&
    lit.inflate(0.5).contains(widget.bottomRight - const Offset(0.01, 0.01));

/// Die Schritte der Bedienung — ohne die Startseite davor (#133).
final kTourTitles = [for (final s in kMapTourScript.tourSteps) s.title];

final bubble = find.byKey(const ValueKey('coach-bubble'));

void main() {
  void useScreen(WidgetTester tester, Size size) {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  late FakeBackend backend;
  late FakeTrailRepository trails;

  setUp(() {
    backend = FakeBackend();
    final me = backend.addUser(username: 'testrail');
    backend.signInAs(me.id);
    trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    trails.seedTrail(me.id, name: 'Hexentanz', grade: 2, traits: {TrailTrait.flowy});
  });

  /// Die Tour starten, wie ein Nutzer es tut: Profil, Kurzanleitung,
  /// „Tour auf der Karte zeigen".
  Future<void> startFromHelp(WidgetTester tester) async {
    await openProfilePage(tester, 'help');
    final start = find.byKey(const ValueKey('help-map-tour'));
    // Die Liste der Kurzanleitung, nicht `Scrollable.first` — das kann
    // die Liste eines verdeckten Reiters sein.
    await tester.scrollUntilVisible(start, 300,
        scrollable: find.descendant(of: find.byKey(const ValueKey('help-list')), matching: find.byType(Scrollable)));
    await settle(tester);
    await tester.tap(start);
    await settle(tester);
    // Seit #133 beginnt sie mit ihrer Startseite „Die Karte".
    expect(find.text('Die Karte'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('coach-intro-start')));
    await settle(tester);
  }

  Future<FakeSettings> pumpAndStart(WidgetTester tester, {bool withTrail = true}) async {
    // Schon gesehen — sonst liefe seit #133 die Willkommens-Tour von
    // selbst. Danach zurückgesetzt, damit der Test sieht, dass die Tour
    // aus der Kurzanleitung den Merker wieder setzt.
    final settings = FakeSettings();
    await pumpApp(tester, backend, trails: withTrail ? trails : null, settings: settings);
    await settle(tester, frames: 20);
    settings.mapTourSeen = false;
    await startFromHelp(tester);
    return settings;
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.descendant(of: bubble, matching: find.text('Weiter')));
    await settle(tester);
  }

  /// Nichts wurde ausgelöst oder offen gelassen: keine Leiste, kein Blatt.
  void nothingOpen() {
    expect(find.byKey(const ValueKey('offline-tool-rail')), findsNothing, reason: 'Leiste noch offen');
    expect(find.byType(BottomSheet), findsNothing, reason: 'ein Blatt ist noch offen');
  }

  testWidgets('aus der Kurzanleitung: der Reihe nach, dann gesehen', (tester) async {
    final settings = await pumpAndStart(tester);

    for (final title in kTourTitles) {
      expect(find.descendant(of: bubble, matching: find.text(title)), findsOneWidget,
          reason: 'Schritt „$title"');
      await tester.tap(find.descendant(
          of: bubble, matching: find.text(title == kTourTitles.last ? 'Los geht\'s' : 'Weiter')));
      await settle(tester);
    }
    expect(settings.mapTourSeen, isTrue);
    expect(bubble, findsNothing);
    nothingOpen();
  });

  testWidgets('Aussparung und Ring sitzen auf den echten Widgets', (tester) async {
    for (final size in [const Size(412, 915), const Size(360, 740)]) {
      useScreen(tester, size);
      await tester.pumpWidget(const SizedBox());
      await pumpAndStart(tester);
      final at = ' bei ${size.width}×${size.height}';

      // 1 — das Schild am Anfang.
      final badge = find.byWidgetPredicate((w) => w is CoachAnchor && w.id == MapCoach.trailBadge);
      expect(badge, findsOneWidget, reason: 'genau ein Schild trägt den Anker$at');
      expect(covers(painter(tester).lit.single, tester.getRect(badge)), isTrue, reason: 'Schild$at');

      await next(tester); // 2 — das Blatt
      expect(find.byKey(const ValueKey('trail-sheet-title')), findsOneWidget, reason: 'Blatt offen$at');
      expect(find.text('HEXENTANZ'), findsOneWidget, reason: 'das Blatt DES Schilds$at');
      expect(covers(painter(tester).lit.single, tester.getRect(find.byKey(const ValueKey('metric-length')))),
          isTrue, reason: 'Kacheln$at');

      await next(tester); // 3 — die Legende auf der Karte (#182), aufgeklappt
      expect(find.byType(BottomSheet), findsNothing, reason: 'das Blatt ist wieder zu$at');
      final legend = find.byKey(const ValueKey('map-legend-panel'));
      expect(legend, findsOneWidget, reason: 'die Szene klappt sie auf$at');
      expect(covers(painter(tester).lit.single, tester.getRect(legend)), isTrue, reason: 'Legende$at');

      await next(tester); // 4 — Kartenebenen
      expect(find.byKey(const ValueKey('map-legend-panel')), findsNothing, reason: 'wieder zu$at');
      expect(find.byKey(const ValueKey('map-legend-tab')), findsOneWidget, reason: 'die Lasche$at');
      final layers = tester.getRect(find.byKey(const ValueKey('layers-button')));
      expect(covers(painter(tester).lit.single, layers), isTrue, reason: 'Knopfspalte$at');
      expect(painter(tester).ring.single, rectMoreOrLessEquals(layers), reason: 'Ring auf Kartenebenen$at');

      await next(tester); // 5 — das Blatt „Kartenebenen", direkt (#190)
      expect(find.byKey(const ValueKey('official-trails-switch')), findsOneWidget, reason: 'Ebenen-Blatt$at');
      expect(find.byKey(const ValueKey('offline-tool-rail')), findsNothing, reason: 'ohne Leiste$at');
      expect(
          painter(tester).lit.any((r) => r.contains(tester.getCenter(find.byKey(const ValueKey('official-trails-switch'))))),
          isTrue,
          reason: 'Schalter ausgespart$at');

      await next(tester); // 6 — der Knopf „Offline-Karten"
      expect(find.byType(BottomSheet), findsNothing, reason: 'das Blatt ist wieder zu$at');
      expect(painter(tester).ring.single,
          rectMoreOrLessEquals(tester.getRect(find.byKey(const ValueKey('offline-button')))),
          reason: 'Ring auf Offline-Karten$at');

      await next(tester); // 7 — die Leiste
      expect(find.byKey(const ValueKey('offline-tool-rail')), findsOneWidget, reason: 'Leiste offen$at');
      expect(covers(painter(tester).lit.single, tester.getRect(find.byKey(const ValueKey('offline-tool-rail')))),
          isTrue, reason: 'Leiste ausgespart$at');
      expect(painter(tester).ring.single,
          rectMoreOrLessEquals(tester.getRect(find.byKey(const ValueKey('area-draw-add')))),
          reason: 'Ring auf dem Stift$at');

      await next(tester); // 8 — Position und Glühbirne
      nothingOpen();
      expect(
          union(painter(tester).ring),
          rectMoreOrLessEquals(union([
            tester.getRect(find.byKey(const ValueKey('feedback-button'))),
            tester.getRect(find.byKey(const ValueKey('locate-button'))),
          ])),
          reason: 'Ring auf Glühbirne und Position$at');

      await next(tester); // 9 — Aufnahme
      expect(painter(tester).ring.single, rectMoreOrLessEquals(tester.getRect(find.byKey(const ValueKey('ride-button')))),
          reason: 'Ring auf der Aufnahme$at');

      await next(tester); // 10 — die Bereiche unten
      final bar = find.byType(NavigationBar);
      final rings = painter(tester).ring;
      expect(rings, hasLength(3));
      for (final label in ['Trails', 'Buddys', 'Profil']) {
        final c = tester.getCenter(find.descendant(of: bar, matching: find.text(label)));
        expect(rings.any((r) => r.contains(c)), isTrue, reason: '$label$at');
      }
      final map = tester.getCenter(find.descendant(of: bar, matching: find.text('Karte')));
      expect(rings.any((r) => r.contains(map)), isFalse, reason: 'auf der Karte steht man schon$at');
      await tester.tap(find.descendant(of: bubble, matching: find.text('Los geht\'s')));
      await settle(tester);
    }
  });

  testWidgets('Tippen während der Vorführung löst nichts aus', (tester) async {
    // Die Überlagerung schluckt jeden Tipp: Ein Tipp auf den Schalter im
    // Ebenen-Blatt schaltet nichts um, es geht nur weiter.
    final settings = await pumpAndStart(tester);
    for (var i = 0; i < 4; i++) {
      await next(tester);
    }
    expect(find.byKey(const ValueKey('official-trails-switch')), findsOneWidget);
    await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('official-trails-switch'))));
    await settle(tester);
    expect(settings.officialTrailsEnabled, isTrue, reason: 'der Schalter ist nicht umgelegt');
    expect(find.descendant(of: bubble, matching: find.text(kTourTitles[5])), findsOneWidget,
        reason: 'nur einen Schritt weiter');
  });

  testWidgets('Überspringen im Ebenen-Blatt lässt nichts offen', (tester) async {
    final settings = await pumpAndStart(tester);
    for (var i = 0; i < 4; i++) {
      await next(tester);
    }
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.descendant(of: bubble, matching: find.text('Überspringen')));
    await settle(tester);
    expect(settings.mapTourSeen, isTrue, reason: 'Überspringen zählt wie Durchsehen');
    expect(bubble, findsNothing);
    nothingOpen();
  });

  testWidgets('die Zurück-Taste beendet die Tour, nicht die App — danach '
      'gehört sie wieder dem System', (tester) async {
    // Direkt gestartet, nicht über die Kurzanleitung: Sonst läge im
    // Profil-Reiter noch eine Seite, und Zurück hätte etwas zu tun, das
    // mit der Tour nichts zu tun hat.
    final settings = FakeSettings();
    await pumpApp(tester, backend, trails: trails, settings: settings);
    await settle(tester, frames: 20);
    settings.mapTourSeen = false;
    expect(await tester.binding.handlePopRoute(), isFalse, reason: 'ohne Tour: bis zum System');
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
        .read(coachProvider.notifier)
        .start(kMapTourScript, onDone: () => settings.mapTourSeen = true);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('coach-intro-start')));
    await settle(tester);
    await next(tester); // das Trail-Blatt ist offen
    expect(await tester.binding.handlePopRoute(), isTrue);
    await settle(tester);
    expect(bubble, findsNothing);
    expect(settings.mapTourSeen, isTrue);
    nothingOpen();
    expect(find.byKey(const ValueKey('layers-button')), findsOneWidget, reason: 'die App steht noch');
    expect(await tester.binding.handlePopRoute(), isFalse, reason: 'danach nicht mehr abgefangen');
  });

  testWidgets('die Sprechblase liegt ganz im Bild und nie auf dem, was sie '
      'erklärt', (tester) async {
    for (final size in [const Size(412, 915), const Size(360, 740)]) {
      useScreen(tester, size);
      await tester.pumpWidget(const SizedBox());
      await pumpAndStart(tester);
      for (final title in kTourTitles) {
        final at = 'Schritt „$title" bei ${size.width}×${size.height}';
        expect(find.descendant(of: bubble, matching: find.text(title)), findsOneWidget, reason: at);
        final b = tester.getRect(bubble);
        final screen = Offset.zero & size;
        expect(screen.contains(b.topLeft) && screen.contains(b.bottomRight - const Offset(1, 1)), isTrue,
            reason: '$at: Blase $b außerhalb');
        final p = painter(tester);
        for (final r in [...p.lit, ...p.ring]) {
          expect(b.overlaps(r), isFalse, reason: '$at: Blase $b deckt $r zu');
        }
        if (title == kTourTitles.last) break;
        await next(tester);
      }
      await tester.tap(find.descendant(of: bubble, matching: find.text('Los geht\'s')));
      await settle(tester);
    }
  });

  testWidgets('ohne Trail fallen Schild und Blatt weg, der Zähler zählt '
      'nur, was kommt', (tester) async {
    await pumpAndStart(tester, withTrail: false);
    expect(find.descendant(of: bubble, matching: find.text('Farbe heißt Schwierigkeit')), findsOneWidget);
    expect(find.text('1 von ${kTourTitles.length - 2}'), findsOneWidget);
  });

  testWidgets('der letzte Schritt führt zurück in die Kurzanleitung', (tester) async {
    final settings = await pumpAndStart(tester);
    for (var i = 0; i < kTourTitles.length - 1; i++) {
      await next(tester);
    }
    expect(find.descendant(of: bubble, matching: find.text('Überspringen')), findsNothing);
    await tester.tap(find.descendant(of: bubble, matching: find.text('Kurzanleitung')));
    await settle(tester);
    expect(find.textContaining('Das Wichtigste in sechs Schritten'), findsOneWidget);
    expect(settings.mapTourSeen, isTrue);
    expect(bubble, findsNothing);
  });

  testWidgets('ein zweiter Tipp gleich danach überspringt nichts', (tester) async {
    // PilzBuddy, Feldmeldung 2026-09-25: Nach „Weiter" steht die neue
    // Blase woanders, und ein nachwackelnder Finger landete auf IHREM
    // „Weiter". Die Tippsperre fängt das.
    await pumpAndStart(tester);
    await tester.tap(find.descendant(of: bubble, matching: find.text('Weiter')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(const Offset(5, 300));
    await tester.pump(const Duration(milliseconds: 60));
    await settle(tester);
    expect(find.descendant(of: bubble, matching: find.text(kTourTitles[1])), findsOneWidget);
  });

  test('die Leiste benennt ihre Knöpfe so, wie das Skript sie sucht', () {
    expect(MapCoach.railButton('area-draw-add'), MapCoach.railDraw);
  });

  test('die Legende nennt, was die Kurzanleitung nennt', () {
    // Die Legende nennt die Bedeutung, die Tour verbindet sie mit dem
    // Aussehen (#231).
    final tour = kMapTourScript.steps.firstWhere((s) => s.title == 'Farbe heißt Schwierigkeit').text;
    for (final label in ['S0', 'S3', 'S4/S5', 'Uphill', 'ausgefahren', 'abgerockt', 'kaum fahrbar', 'Meldung',
      'neuer Hinweis', 'offizieller Trail']) {
      expect([for (final s in legendSamples()) s.label], contains(label));
    }
    for (final word in ['ausgefahren', 'abgerockt', 'kaum fahrbar', 'Meldung', 'neuer Hinweis']) {
      expect(tour, contains(word), reason: word);
    }
  });
}
