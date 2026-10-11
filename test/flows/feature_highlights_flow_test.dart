// Neuheiten nach Updates und „Entdecken" in der App (#135).
//
// Die Zusagen:
//   1. Bestand ohne Merker: einmal der Rückblick, danach nicht wieder.
//   2. Frische Installation: nie ein Blatt — aber die Version ist gemerkt.
//   3. Liegt schon etwas über der Karte (Hinweis, Tour), wartet das Blatt.
//   4. Nach einem Update: „Neu in TrailBuddy" mit den neuen Highlights.
//   5. „Entdecken" im Profil mit Neu-Punkt, der beim Öffnen verschwindet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/highlights/discover_screen.dart';
import 'package:trailbuddy/features/highlights/feature_highlights.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

final title = find.byKey(const ValueKey('highlight-sheet-title'));

void main() {
  FakeBackend signedIn() {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testrail').id);
    return backend;
  }

  testWidgets('Bestand ohne Merker: einmal der Rückblick', (tester) async {
    final settings = FakeSettings(highlightsSeenVersion: null);
    await pumpApp(tester, signedIn(), settings: settings, appVersion: '0.64.0');
    expect(find.text('Das kann TrailBuddy inzwischen'), findsOneWidget);
    for (final id in kRecapLead) {
      expect(find.byKey(ValueKey('highlight-row-$id')), findsOneWidget, reason: id);
    }
    expect(settings.highlightsSeenVersion, '0.64.0', reason: 'gemerkt vor dem Zeigen');
    await tester.tap(find.text('Fertig'));
    await settle(tester);
    expect(title, findsNothing);

    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, signedIn(), settings: settings, appVersion: '0.64.0');
    expect(title, findsNothing, reason: 'nicht wieder');
  });

  testWidgets('frische Installation: kein Blatt, aber gemerkt', (tester) async {
    final settings = FakeSettings(mapTourSeen: false, highlightsSeenVersion: null);
    await pumpApp(tester, signedIn(), settings: settings, appVersion: '0.64.0');
    expect(title, findsNothing);
    expect(find.text('Willkommen bei TrailBuddy'), findsOneWidget, reason: 'die Tour erklärt');
    expect(settings.highlightsSeenVersion, '0.64.0',
        reason: 'sonst hielte sie sich nach der Tour für einen Bestandsnutzer');
  });

  testWidgets('liegt der Hinweis über der Karte, wartet das Blatt', (tester) async {
    final settings = FakeSettings(safetyNoteSeen: false, highlightsSeenVersion: '0.50.0');
    await pumpApp(tester, signedIn(), settings: settings, appVersion: '0.64.0');
    await tester.tap(find.text('Verstanden'));
    await settle(tester);
    expect(title, findsNothing);
    expect(settings.highlightsSeenVersion, '0.50.0', reason: 'nicht gezeigt heißt nicht gemerkt');
  });

  testWidgets('nach einem Update: „Neu in TrailBuddy"', (tester) async {
    await pumpApp(tester, signedIn(),
        settings: FakeSettings(highlightsSeenVersion: '0.56.0'), appVersion: '0.58.0');
    expect(find.text('Neu in TrailBuddy'), findsOneWidget);
    expect(find.byKey(const ValueKey('highlight-row-still-valid')), findsOneWidget);
    expect(find.byKey(const ValueKey('highlight-row-marks')), findsOneWidget);
    expect(find.byKey(const ValueKey('highlight-row-takeover')), findsNothing, reason: 'schon gesehen (0.55.0)');
  });

  testWidgets('„Entdecken" im Profil: Neu-Punkt, der beim Öffnen verschwindet', (tester) async {
    final settings = FakeSettings();
    await pumpApp(tester, signedIn(), settings: settings);
    await openTab(tester, 'Profil');
    final badge = find.byKey(const ValueKey('profile-discover-badge'));
    await scrollTo(tester, badge);
    expect(find.descendant(of: badge, matching: find.text('${kFeatureHighlights.length}')), findsOneWidget);

    await openProfilePage(tester, 'discover');
    expect(find.byType(DiscoverScreen), findsOneWidget);
    expect(find.text('Neu'), findsWidgets, reason: 'beim Öffnen noch zu sehen');
    await settle(tester);
    expect(settings.seenHighlightIds, hasLength(kFeatureHighlights.length));
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(badge, findsNothing);
  });

  testWidgets('„Entdecken" auf 360×740 ohne Überlauf, jede Gruppe da', (tester) async {
    tester.view.physicalSize = const Size(360, 740) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, signedIn());
    await openProfilePage(tester, 'discover');
    final seen = <String>{};
    // Wischen, bis jeder Eintrag einmal gebaut war — eine feste Zahl
    // Wischer reichte nicht mehr, sobald die Liste wuchs (#107).
    for (var i = 0; i < 200 && seen.length < kFeatureHighlights.length; i++) {
      for (final h in kFeatureHighlights) {
        if (find.byKey(ValueKey('discover-${h.id}')).evaluate().isNotEmpty) seen.add(h.id);
      }
      await tester.drag(find.byKey(const ValueKey('discover-list')), const Offset(0, -300));
      await settle(tester, frames: 3);
    }
    expect(seen, kFeatureHighlights.map((h) => h.id).toSet());
    expect(tester.takeException(), isNull);
  });
}
