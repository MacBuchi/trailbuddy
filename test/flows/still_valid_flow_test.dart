// „Noch gültig?" (#119) einmal durch: der Zähler im Profil, die Seite mit
// Ja / Nein / Weiß nicht, und derselbe Satz als Filter in der Liste.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late FakeSettings settings;
  late String annaId;
  late String hang;
  late String wald;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    annaId = anna.id;
    settings = FakeSettings();
    trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '');
    final old = DateTime.now().subtract(const Duration(days: 45));
    // Zwei eigene Trails mit alten Angaben, einer mit einer frischen.
    hang = trails.seedTrail(annaId, name: 'Hang', source: RecordingSource.app);
    trails.seedReport(annaId, hang, status: TrailStatus.closed, at: old);
    wald = trails.seedTrail(
      annaId,
      name: 'Waldweg',
      lat: 48.1,
      source: RecordingSource.app,
    );
    trails.seedReport(
      annaId,
      wald,
      condition: 2,
      at: old.add(const Duration(days: 1)),
    );
    final neu = trails.seedTrail(
      annaId,
      name: 'Neu',
      lat: 48.2,
      source: RecordingSource.app,
    );
    trails.seedReport(
      annaId,
      neu,
      status: TrailStatus.closed,
      at: DateTime.now(),
    );
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, backend, trails: trails, settings: settings);
    await settle(tester, frames: 10);
  }

  testWidgets('Profil zählt, Ja bestätigt, Nein wählt den neuen Zustand', (
    tester,
  ) async {
    await pump(tester);
    await openTab(tester, 'Profil');
    expect(find.text('2 Angaben zu prüfen'), findsOneWidget);
    await openProfilePage(tester, 'still-valid');
    expect(find.text('Hang'), findsOneWidget);
    expect(find.text('Waldweg'), findsOneWidget);
    expect(find.text('Neu'), findsNothing, reason: 'jünger als 30 Tage');
    expect(
      find.textContaining('Meldung: Gesperrt · vor 45 Tagen'),
      findsOneWidget,
    );

    // Ja: dieselbe Meldung noch einmal — bestätigt, Anna ist ihn gefahren.
    final before = trails.reports.length;
    await tester.tap(find.byKey(ValueKey('still-valid-yes-$hang-status')));
    await settle(tester, frames: 10);
    final fresh = trails.reports.last;
    expect(trails.reports.length, before + 1);
    expect(
      (fresh.trailId, fresh.status, fresh.confirmed),
      (hang, TrailStatus.closed, true),
    );
    expect(
      find.text('Hang'),
      findsNothing,
      reason: 'beantwortet: die Frage ist weg',
    );

    // Nein beim Zustand: die Skala, dann der neue Wert.
    await tester.tap(find.byKey(ValueKey('still-valid-no-$wald-condition')));
    await settle(tester);
    expect(find.text('Wie ist er jetzt?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('still-valid-condition-4')));
    await settle(tester, frames: 10);
    expect(
      (trails.reports.last.trailId, trails.reports.last.condition),
      (wald, 4),
    );
    expect(find.byKey(const ValueKey('still-valid-empty')), findsOneWidget);
  });

  testWidgets('Nein bei einer Meldung heißt: wieder offen', (tester) async {
    await pump(tester);
    await openProfilePage(tester, 'still-valid');
    await tester.tap(find.byKey(ValueKey('still-valid-no-$hang-status')));
    await settle(tester, frames: 10);
    expect(
      (trails.reports.last.trailId, trails.reports.last.status),
      (hang, TrailStatus.open),
    );
  });

  testWidgets(
    'Weiß nicht ändert nichts am Server und ruht 14 Tage — auch nach dem Neustart',
    (tester) async {
      await pump(tester);
      await openProfilePage(tester, 'still-valid');
      final before = trails.reports.length;
      await tester.tap(
        find.byKey(ValueKey('still-valid-unknown-$hang-status')),
      );
      await settle(tester);
      expect(
        trails.reports.length,
        before,
        reason: 'keine Meldung, kein Server-Zustand',
      );
      expect(find.text('Hang'), findsNothing);
      expect(settings.stillValidSnoozes, hasLength(1));
      final until = DateTime.parse(
        settings.stillValidSnoozes!.single.split('|').last,
      );
      expect(
        until.difference(DateTime.now().toUtc()).inDays,
        inInclusiveRange(13, 14),
      );

      // Neustart mit denselben Einstellungen: weiter nur der Zustand.
      await pump(tester);
      await openTab(tester, 'Profil');
      expect(find.text('1 Angabe zu prüfen'), findsOneWidget);
    },
  );

  testWidgets('der Filter „Noch gültig?" in der Liste zeigt dieselben Trails', (
    tester,
  ) async {
    await pump(tester);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 10);
    final chip = find.byKey(const ValueKey('trail-filter-still-valid'));
    await scrollTo(tester, chip);
    await tester.tap(chip);
    await settle(tester, frames: 10);
    expect(find.text('Hang'), findsOneWidget);
    expect(find.text('Waldweg'), findsOneWidget);
    expect(find.text('Neu'), findsNothing);
  });
}
