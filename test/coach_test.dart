// Die Hinweis-Maschine für sich (#596) — ohne App, damit ihre Zusagen
// nicht an zufälligen Maßen der Karte hängen.
//
// TrailBuddy (#132): Kopie von PilzBuddys `test/coach_test.dart` (Stand
// 0d2a533), dazu ein Test für die eine Erweiterung, `illustration`.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/coach/coach.dart';
import 'package:trailbuddy/l10n/l10n.dart';

CoachPainter painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((c) => c.painter)
    .whereType<CoachPainter>()
    .single;

Future<ProviderContainer> pumpCoach(WidgetTester tester, Widget home) async {
  final container = ProviderContainer();
  // Aufräumen läuft rückwärts: erst die Tour beenden, dann den Baum
  // abbauen, zuletzt den Container. Andersherum tickte die Überlagerung
  // eines gescheiterten Tests gegen einen entsorgten Container und riss
  // den nächsten Test mit.
  addTearDown(container.dispose);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  addTearDown(() => container.read(coachProvider.notifier).finish());
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      // Die Knöpfe der Maschine sprechen seit #209 aus den ARB-Dateien;
      // die Tests prüfen die deutschen.
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          CoachSemanticsGate(child: child!),
          CoachOverlay(onNavigate: (_) {}),
        ],
      ),
      home: Scaffold(body: home),
    ),
  ));
  return container;
}

Future<void> frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('misst über die ganze Transformation, nicht nur die Position',
      (tester) async {
    // Die Knopfleiste der Karte steckt in einem `FittedBox(scaleDown)`.
    // `localToGlobal(Offset.zero) & size` nähme dort die Position richtig
    // und die UNverkleinerte Größe — im Test der Karte ist die Leiste
    // nie verkleinert (auch nicht bei 360×560 gemessen), deshalb steht
    // die Zusage hier.
    final container = await pumpCoach(
      tester,
      Center(
        child: Transform.scale(
          scale: 0.5,
          child: const CoachAnchor(
              id: 'box', child: SizedBox(key: Key('box'), width: 200, height: 80)),
        ),
      ),
    );
    container.read(coachProvider.notifier).start(const CoachScript(
        id: 't', steps: [CoachStep(title: 'T', text: 'x', lit: ['box'])]));
    await frames(tester);
    final lit = painter(tester).lit.single;
    final real = tester.getRect(find.byKey(const Key('box')));
    expect(real.width, 100, reason: 'die Vorgabe: halb so groß');
    expect(lit, rectMoreOrLessEquals(real));
  });

  testWidgets('eine Szene wird geöffnet und am Ende wieder geschlossen',
      (tester) async {
    final container = await pumpCoach(tester, const SizedBox.expand());
    var opened = 0;
    var closed = 0;
    container.read(coachRegistryProvider).registerScene('s', () async {
      opened++;
      return () => closed++;
    });
    container.read(coachProvider.notifier).start(const CoachScript(id: 't', steps: [
      CoachStep(title: 'A', text: 'x', scene: 's'),
      CoachStep(title: 'B', text: 'x', scene: 's'),
      CoachStep(title: 'C', text: 'x'),
    ]));
    await frames(tester);
    expect((opened, closed), (1, 0));
    container.read(coachProvider.notifier).next(); // dieselbe Szene
    await frames(tester);
    expect((opened, closed), (1, 0), reason: 'geteilt, nicht neu geöffnet');
    container.read(coachProvider.notifier).next(); // keine Szene mehr
    await frames(tester);
    expect((opened, closed), (1, 1));

    container.read(coachProvider.notifier).start(const CoachScript(
        id: 't', steps: [CoachStep(title: 'A', text: 'x', scene: 's')]));
    await frames(tester);
    container.read(coachProvider.notifier).finish();
    await frames(tester);
    expect((opened, closed), (2, 2), reason: 'Überspringen schließt auch');
  });

  testWidgets('fehlt das Ziel dauerhaft, sagt die Blase es — statt still '
      'weiterzuspringen', (tester) async {
    // Bis 1.208.x ging die Tour nach ~2 s von selbst weiter. Auf einem
    // Gerät, das ein Blatt langsamer öffnet, sah das aus wie ein
    // übersprungener Schritt (Feldmeldung 2026-09-25).
    final container = await pumpCoach(tester, const SizedBox.expand());
    var done = false;
    container.read(coachProvider.notifier).start(
        const CoachScript(id: 't', steps: [
          CoachStep(title: 'A', text: 'x', lit: ['gibt-es-nicht']),
        ]),
        onDone: () => done = true);
    await frames(tester, 3);
    expect(find.text('A'), findsOneWidget);
    expect(find.byKey(const ValueKey('coach-target-lost')), findsNothing,
        reason: 'nicht gleich — eine Szene braucht einen Moment');
    await tester.pump(const Duration(seconds: 4));
    await frames(tester, 130);
    expect(done, isFalse);
    expect(find.text('A'), findsOneWidget, reason: 'der Schritt bleibt');
    expect(find.byKey(const ValueKey('coach-target-lost')), findsOneWidget);
  });

  testWidgets('ein Schritt ohne sein Ziel fällt sofort weg', (tester) async {
    // `requires`: Die erste Zeile einer leeren Liste gibt es nicht — der
    // Schritt darüber soll nicht zwei Sekunden auf nichts zeigen.
    final container = await pumpCoach(
        tester,
        const Center(
            child: CoachAnchor(
                id: 'da', child: SizedBox(width: 50, height: 50))));
    container.read(coachProvider.notifier).start(const CoachScript(id: 't', steps: [
      CoachStep(title: 'A', text: 'x', lit: ['da']),
      CoachStep(
          title: 'B', text: 'x', lit: ['fehlt'], requires: ['fehlt']),
      CoachStep(title: 'C', text: 'x', lit: ['da'], requires: ['da']),
    ]));
    await frames(tester);
    container.read(coachProvider.notifier).next();
    await frames(tester, 2);
    expect(find.text('B'), findsNothing);
    expect(find.text('C'), findsOneWidget);
  });

  testWidgets('eine innere Szene lässt die äußere offen', (tester) async {
    // Artseite und darauf der Meldedialog: Der Dialog darf die Seite
    // nicht schließen, und zurück zur Seite schließt nur den Dialog.
    final container = await pumpCoach(tester, const SizedBox.expand());
    final log = <String>[];
    final registry = container.read(coachRegistryProvider);
    for (final id in ['a', 'a/b']) {
      registry.registerScene(id, () async {
        log.add('auf $id');
        return () => log.add('zu $id');
      });
    }
    container.read(coachProvider.notifier).start(const CoachScript(id: 't', steps: [
      CoachStep(title: 'A', text: 'x', scene: 'a'),
      CoachStep(title: 'B', text: 'x', scene: 'a/b'),
      CoachStep(title: 'C', text: 'x', scene: 'a'),
    ]));
    await frames(tester);
    container.read(coachProvider.notifier).next();
    await frames(tester);
    container.read(coachProvider.notifier).next();
    await frames(tester);
    container.read(coachProvider.notifier).finish();
    await frames(tester);
    expect(log, ['auf a', 'auf a/b', 'zu a/b', 'zu a']);
  });

  testWidgets('eine Szene, die sich erst später anmeldet, geht trotzdem auf',
      (tester) async {
    // Die innere Szene meldet ihr Besitzer an, und der entsteht erst,
    // wenn die äußere steht — etwa ein Knopf AUF der Seite, die die
    // äußere Szene öffnet.
    final container = await pumpCoach(tester, const SizedBox.expand());
    final registry = container.read(coachRegistryProvider);
    var inner = 0;
    registry.registerScene('a', () async {
      Future<void>.delayed(const Duration(milliseconds: 100), () {
        registry.registerScene('a/b', () async {
          inner++;
          return () {};
        });
      });
      return () {};
    });
    container.read(coachProvider.notifier).start(const CoachScript(
        id: 't', steps: [CoachStep(title: 'A', text: 'x', scene: 'a/b')]));
    await frames(tester, 10);
    expect(inner, 1);
  });

  testWidgets('der Zähler und „Los geht\'s" zählen nur, was läuft',
      (tester) async {
    final container = await pumpCoach(
        tester,
        const Center(
            child: CoachAnchor(
                id: 'da', child: SizedBox(width: 50, height: 50))));
    container.read(coachProvider.notifier).start(const CoachScript(id: 't', steps: [
      CoachStep(title: 'A', text: 'x', lit: ['da']),
      CoachStep(title: 'B', text: 'x', lit: ['da']),
      // Ersatzschritt, der hier wegfällt — B ist also der letzte.
      CoachStep(title: 'C', text: 'x', unless: ['da']),
    ]));
    await frames(tester);
    expect(find.text('1 von 2'), findsOneWidget);
    container.read(coachProvider.notifier).next();
    await frames(tester);
    expect(find.text('2 von 2'), findsOneWidget);
    expect(find.text('Los geht\'s'), findsOneWidget);
  });

  testWidgets('„Animationen entfernen": Ring und Hand stehen still',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final container = await pumpCoach(
        tester,
        const Center(
            child: CoachAnchor(
                id: 'da', child: SizedBox(width: 50, height: 50))));
    container.read(coachProvider.notifier).start(const CoachScript(
        id: 't',
        steps: [
          CoachStep(
              title: 'A', text: 'x', lit: ['da'], gesture: CoachGesture.tap)
        ]));
    await frames(tester);
    final seen = <(double, double)>{};
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 150));
      final finger = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<FingerPainter>()
          .single;
      seen.add((painter(tester).pulse, finger.t));
    }
    expect(seen, {(0.0, gestureStillFrame(CoachGesture.tap))});
  });

  testWidgets('der Bildschirmleser sieht während der Tour nur die Blase',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final container = await pumpCoach(
        tester,
        Center(
            child: CoachAnchor(
                id: 'da',
                child: ElevatedButton(
                    onPressed: () {}, child: const Text('Darunter')))));
    expect(find.semantics.byLabel('Darunter'), findsOneWidget);
    container.read(coachProvider.notifier).start(const CoachScript(
        id: 't', steps: [CoachStep(title: 'Oben', text: 'x', lit: ['da'])]));
    await frames(tester);
    expect(find.semantics.byLabel('Darunter'), findsNothing,
        reason: 'ein Knopf, der unter der Tour keinen Tipp annimmt');
    expect(find.semantics.byLabel(RegExp('Oben')), findsOneWidget);
    expect(
        find.byWidgetPredicate(
            (w) => w is Semantics && (w.properties.liveRegion ?? false)),
        findsOneWidget,
        reason: 'ein neuer Schritt wird angesagt');
    container.read(coachProvider.notifier).finish();
    await frames(tester);
    expect(find.semantics.byLabel('Darunter'), findsOneWidget,
        reason: 'danach wieder da');
    semantics.dispose();
  });

  testWidgets('die Illustration steht in der Blase, unter dem Text',
      (tester) async {
    // TrailBuddys Erweiterung: Trail-Linien sind keine Widgets, der
    // Schritt „Farbe heißt Schwierigkeit" zeigt deshalb ein Bild in der
    // Blase statt einer Aussparung.
    final container = await pumpCoach(tester, const SizedBox.expand());
    container.read(coachProvider.notifier).start(const CoachScript(id: 't', steps: [
      CoachStep(
          title: 'A',
          text: 'Text',
          illustration: SizedBox(key: Key('bild'), width: 40, height: 20)),
    ]));
    await frames(tester);
    final bubble = find.byKey(const ValueKey('coach-bubble'));
    expect(find.descendant(of: bubble, matching: find.byKey(const Key('bild'))), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const Key('bild'))).dy,
        greaterThan(tester.getBottomLeft(find.text('Text')).dy));
    expect(painter(tester).lit, isEmpty, reason: 'nichts ausgespart');
  });

  group('die Hand', () {
    test('gedrückt wird AUF dem Ziel', () {
      for (final g in [CoachGesture.tap, CoachGesture.longPress]) {
        final pressed = [
          for (var t = 0.0; t <= 1; t += 0.01) FingerMotion.of(g, t)
        ].where((m) => m.pressed).toList();
        expect(pressed, isNotEmpty, reason: '$g');
        for (final m in pressed) {
          expect(m.tipShift, Offset.zero, reason: '$g');
          expect(m.lift, 0, reason: '$g: gedrückt heißt aufgesetzt');
        }
      }
    });

    test('der lange Druck hält deutlich länger als der Tipp', () {
      int pressedSteps(CoachGesture g) => [
            for (var t = 0.0; t <= 1; t += 0.01) FingerMotion.of(g, t)
          ].where((m) => m.pressed).length;
      expect(pressedSteps(CoachGesture.longPress),
          greaterThan(3 * pressedSteps(CoachGesture.tap)));
    });

    test('Wischen läuft von rechts nach links über das Ziel', () {
      final pressed = [
        for (var t = 0.0; t <= 1; t += 0.01)
          FingerMotion.of(CoachGesture.swipe, t)
      ].where((m) => m.pressed).toList();
      expect(pressed.first.tipShift.dx, greaterThan(30));
      expect(pressed.last.tipShift.dx, lessThan(-30));
      for (var i = 1; i < pressed.length; i++) {
        expect(pressed[i].tipShift.dx,
            lessThanOrEqualTo(pressed[i - 1].tipShift.dx));
      }
    });

    test('zwischen zwei Durchläufen ist sie weg — kein Sprung', () {
      for (final g in [
        CoachGesture.tap,
        CoachGesture.longPress,
        CoachGesture.swipe
      ]) {
        expect(FingerMotion.of(g, 0).opacity, 0, reason: '$g');
        expect(FingerMotion.of(g, 1).opacity, 0, reason: '$g');
      }
    });

    test('zeichnet in jeder Phase ohne Fehler', () {
      for (final g in CoachGesture.values) {
        for (var t = 0.0; t <= 1; t += 0.05) {
          final recorder = ui.PictureRecorder();
          FingerPainter(gesture: g, t: t)
              .paint(Canvas(recorder), const Size(120, 120));
          recorder.endRecording().dispose();
        }
      }
    });
  });
}
