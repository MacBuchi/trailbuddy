// Übernehmen für den Bestand (#102 Teil 2): Trails, die ich schon belegt
// habe, deren Beitrag aber noch am Namen eines Buddys hängt — im Blatt
// „Übernehmen", und im Import-Ergebnis für Kennungen, die im Netz schon
// sichtbar waren. Kein Rückfüllen auf dem Server (Konzept 12).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/trails/gpx_files.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/features/trails/trail_import_screen.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';
import 'trail_import_flow_test.dart' show gpx;

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late String annaId;
  late String roots;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    final ben = backend.addUser(username: 'ben');
    backend.addFriendship(anna.id, ben.id);
    backend.signInAs(anna.id);
    annaId = anna.id;
    trails = FakeTrailRepository(
      myId: () => backend.currentUserId ?? '',
      areFriends: backend.areFriends,
    );
    trails.usernames[ben.id] = 'ben';
    roots = trails.seedTrail(
      ben.id,
      name: 'Roots',
      grade: 2,
      traits: {TrailTrait.flowy},
    );
  });

  Future<void> openSheet(WidgetTester tester, String name) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, backend, trails: trails);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    await tester.tap(find.text(name));
    await settle(tester);
  }

  testWidgets(
    'im Blatt: „Übernehmen", vorbelegt aus dem Netz, speichern erst mit Sternen',
    (tester) async {
      // Anna ist Roots gefahren, früher ohne Übernahme: Beleg ja, Beitrag nein.
      trails.recordings.add(
        TrailRecording(
          id: 'rec-anna',
          trailId: roots,
          userId: annaId,
          source: RecordingSource.app,
          recordedAt: DateTime.utc(2026, 9, 1),
          reversed: false,
          quality: 0.4,
          createdAt: DateTime.utc(2026, 9, 1),
          points: trails.recordings.first.points,
          lengthM: 1000,
        ),
      );
      await openSheet(tester, 'Roots');
      final takeover = find.byKey(const ValueKey('trail-takeover'));
      await tester.ensureVisible(takeover);
      await tester.tap(takeover);
      await settle(tester);
      expect(
        find.byKey(const ValueKey('details-takeover-intro')),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextField, 'Roots'),
        findsOneWidget,
        reason: 'der Name des Buddys',
      );
      final save = find.byKey(const ValueKey('details-save'));
      expect(
        tester.widget<FilledButton>(save).onPressed,
        isNull,
        reason: 'übernehmen heißt bewerten',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('details-rating-5')),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('details-rating-5')));
      await settle(tester);
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.tap(save);
      await settle(tester, frames: 10);
      final mine = trails.details.singleWhere((d) => d.userId == annaId);
      expect(mine.name, 'Roots');
      expect(mine.grade, 2);
      expect(mine.traits, {TrailTrait.flowy});
      expect(mine.rating, 5);
      expect(
        find.byKey(const ValueKey('trail-takeover')),
        findsNothing,
        reason: 'jetzt ihr eigener',
      );
    },
  );

  testWidgets(
    'ohne eigenen Beleg und mit eigenem Namen gibt es kein „Übernehmen"',
    (tester) async {
      await openSheet(tester, 'Roots');
      expect(
        find.byKey(const ValueKey('trail-takeover')),
        findsNothing,
        reason: 'ohne Beleg kein Beitrag (Konzept 3)',
      );
    },
  );

  testWidgets(
    'Import: eine Kennung, die im Netz schon sichtbar war, bietet Übernehmen an',
    (tester) async {
      trails.matcher = (_) => roots;
      final files = [PickedFile.text('wurzel.gpx', gpx('Wurzeltrail', 1200))];
      await pumpApp(
        tester,
        backend,
        trails: trails,
        extraOverrides: [
          gpxPickerProvider.overrideWithValue(() async => files),
        ],
      );
      await openTab(tester, 'Trails');
      await tester.tap(find.byTooltip('GPX importieren'));
      await settle(tester);
      await tester.tap(find.text('GPX- oder Zip-Dateien wählen'));
      await settle(tester);
      await tester.tap(find.text('1 beisteuern'));
      await settle(tester, frames: 20);
      expect(find.byKey(ValueKey('import-takeover-$roots')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('import-takeover-open-$roots')));
      await settle(tester);
      // Der Name aus der Datei bleibt (der Import hat ihn schon übernommen),
      // Grad und Charakter kommen aus dem Netz, Sterne fehlen noch.
      expect(find.widgetWithText(TextField, 'Wurzeltrail'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('details-rating-3')),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('details-rating-3')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('details-save')));
      await settle(tester, frames: 10);
      final mine = trails.details.singleWhere((d) => d.userId == annaId);
      expect(mine.rating, 3);
      expect(mine.grade, 2);
      expect(mine.traits, {TrailTrait.flowy});
      expect(find.text('Übernommen.'), findsOneWidget);
    },
  );
}
