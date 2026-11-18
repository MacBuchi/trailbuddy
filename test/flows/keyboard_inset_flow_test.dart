// Die Tastatur überlagert die Karte, sie schiebt sie nicht (Feldbericht
// 2026-10-02, PilzBuddy #397).
//
// Die Textfelder liegen alle ÜBER der Karte — „Mein Beitrag", das
// Zerlege-Blatt, der Name eines Bereichs. Der Scaffold der Karte schrumpfte
// trotzdem ab Werk um `viewInsets.bottom`, Bild für Bild der
// Tastatur-Animation, und mit ihm die native Fläche von MapLibre — Arbeit
// für nichts, gefunden beim Hänger nach dem Eintragen von Details.
//
// Die Tests stellen den Zustand direkt her: ein Fenster mit gesetztem
// `viewInsets.bottom`. Gemessen wird der Body, nicht der Scaffold — der
// RAHMEN eines Scaffolds bleibt groß, auch wenn er seinen Body schrumpft.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/map/map_screen.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;

  setUp(() {
    backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'anna').id);
  });

  /// Ein Telefon mit offener Tastatur: 800 physische Pixel bei dpr 2,625
  /// sind rund 305 dp.
  void keyboardOpen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    tester.view.viewInsets = const FakeViewPadding(bottom: 800);
    addTearDown(tester.view.reset);
  }

  testWidgets('die Karte reicht bis an die Reiterleiste, auch mit Tastatur', (
    tester,
  ) async {
    keyboardOpen(tester);
    await pumpApp(tester, backend);
    await settle(tester, frames: 20);

    // Der Body des Karten-Scaffolds: der Stapel, in dem `MapView` liegt.
    // `MapView` selbst hat im Test keine Fläche (die Fake-Karte ist ein
    // `Wrap` ihrer Marker).
    final map = tester.getRect(
      find
          .ancestor(
            of: find.descendant(
              of: find.byType(MapScreen),
              matching: find.byType(MapView),
            ),
            matching: find.byType(Stack),
          )
          .first,
    );
    final bar = tester.getRect(find.byType(NavigationBar));

    expect(map.height, greaterThan(0), reason: 'die Karte ist gemessen');
    expect(
      map.bottom,
      moreOrLessEquals(bar.top, epsilon: 0.5),
      reason:
          'mit ausweichendem Scaffold endete sie eine Tastaturhöhe '
          'über der Reiterleiste',
    );
  });
}
