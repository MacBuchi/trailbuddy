// #103: Ein Link zur Quelle im eigenen Beitrag — aus der GPX-Datei
// übernommen, im Blatt als Host gezeigt, in „Mein Beitrag" änderbar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/trails/gpx_files.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';
import 'trail_elevation_flow_test.dart' show gpx, importFiles;

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late String annaId, bobId;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    final bob = backend.addUser(username: 'bob');
    backend.addFriendship(anna.id, bob.id);
    backend.signInAs(anna.id);
    annaId = anna.id;
    bobId = bob.id;
    trails = FakeTrailRepository(
      myId: () => backend.currentUserId ?? '',
      areFriends: backend.areFriends,
    );
    trails.usernames[bob.id] = 'bob';
  });

  testWidgets('Import übernimmt den Link der Spur, ohne Query', (tester) async {
    final file = gpx('Wurzeltrail').replaceFirst(
      '<trk>',
      '<trk><link href="https://www.verein.example/strecken?share=geheim"/>',
    );
    await importFiles(
      tester,
      [PickedFile.text('w.gpx', file)],
      backend,
      trails,
    );
    await tester.tap(find.text('1 beisteuern'));
    await settle(tester, frames: 20);
    final mine = trails.details.singleWhere((d) => d.userId == annaId);
    expect(mine.link, 'https://www.verein.example/strecken');
  });

  testWidgets(
    'Blatt zeigt den Link des Buddys; der eigene gewinnt, http wird abgelehnt',
    (tester) async {
      final t = trails.seedTrail(
        bobId,
        name: 'Roots',
        link: 'https://www.verein.example/roots',
      );
      trails.seedTrail(annaId, trailId: t);
      await pumpApp(tester, backend, trails: trails);
      await openTab(tester, 'Trails');
      await settle(tester, frames: 20);
      await tester.tap(find.text('Roots'));
      await settle(tester);
      expect(find.byKey(const ValueKey('trail-link')), findsOneWidget);
      expect(find.text('verein.example'), findsOneWidget);

      await tester.ensureVisible(find.text('Mein Beitrag'));
      await tester.tap(find.text('Mein Beitrag'));
      await settle(tester);
      final field = find.byKey(const ValueKey('details-link'));
      await tester.ensureVisible(field);
      await tester.enterText(field, 'http://anderer.example');
      await tester.tap(find.text('Speichern'));
      await settle(tester);
      expect(
        find.text('Nur https-Adressen, ohne Leerzeichen'),
        findsOneWidget,
        reason: 'der Dialog bleibt offen',
      );

      await tester.enterText(field, 'anderer.example/seite');
      await tester.tap(find.text('Speichern'));
      await settle(tester, frames: 20);
      expect(
        trails.details.singleWhere((d) => d.userId == annaId).link,
        'https://anderer.example/seite',
      );
      expect(
        find.text('anderer.example'),
        findsOneWidget,
        reason: 'der eigene gewinnt',
      );
    },
  );

  testWidgets(
    '#174: „In beide Richtungen fahrbar" im Beitrag — und der Link bleibt dabei stehen',
    (tester) async {
      final t = trails.seedTrail(
        annaId,
        name: 'Flach',
        link: 'https://www.verein.example/flach',
      );
      await pumpApp(tester, backend, trails: trails);
      await openTab(tester, 'Trails');
      await settle(tester, frames: 20);
      await tester.tap(find.text('Flach'));
      await settle(tester);
      await tester.ensureVisible(find.text('Mein Beitrag'));
      await tester.tap(find.text('Mein Beitrag'));
      await settle(tester);
      final toggle = find.byKey(const ValueKey('details-two-way'));
      await tester.ensureVisible(toggle);
      expect(
        tester.widget<SwitchListTile>(toggle).value,
        isFalse,
        reason: 'Vorgabe: nur in Trail-Richtung',
      );
      await tester.tap(toggle);
      await settle(tester, frames: 2);
      await tester.tap(find.text('Speichern'));
      await settle(tester, frames: 20);
      final mine = trails.details.singleWhere(
        (d) => d.trailId == t && d.userId == annaId,
      );
      expect(mine.twoWay, isTrue);
      expect(mine.link, 'https://www.verein.example/flach');
    },
  );
}
