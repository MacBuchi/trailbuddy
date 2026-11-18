// Den eigenen Beitrag löschen (Konzept 4, „Löschen und DSGVO", Patch 010):
// Aufzeichnungen, Einschätzung und Hinweise gehen in einem Schritt; der
// Trail bleibt, solange ein Buddy ihn belegt. Ohne Netz scheitert es
// sichtbar — kein Ausgangskorb für Löschaufträge.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late String annaId, bobId;
  late String roots, solo;

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
    roots = trails.seedTrail(bob.id, name: 'Roots');
    trails.seedTrail(anna.id, trailId: roots, grade: 2);
    solo = trails.seedTrail(anna.id, name: 'Solo', lat: 48.2);
    trails.seedTrail(bob.id, name: 'Bobs Flow', lat: 48.1);
    trails.seedNote(anna.id, roots, 'Annas Hinweis');
    trails.seedNote(bob.id, roots, 'Bobs Hinweis');
  });

  final withdraw = find.byKey(const ValueKey('trail-withdraw'));
  final confirm = find.byKey(const ValueKey('trail-withdraw-confirm'));

  Future<void> openTrail(WidgetTester tester, String name) async {
    await pumpApp(tester, backend, trails: trails);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    await tester.scrollUntilVisible(
      find.text(name),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text(name));
    await settle(tester);
  }

  Future<void> tapWithdraw(WidgetTester tester) async {
    await tester.ensureVisible(withdraw);
    await tester.tap(withdraw);
    await settle(tester);
  }

  testWidgets('eigener Trail allein: nach dem Löschen ist er weg', (
    tester,
  ) async {
    await openTrail(tester, 'Solo');
    await tapWithdraw(tester);
    expect(
      find.textContaining('verschwindet von deiner Karte'),
      findsOneWidget,
    );
    await tester.tap(confirm);
    await settle(tester, frames: 20);

    expect(find.text('Beitrag gelöscht'), findsOneWidget);
    expect(withdraw, findsNothing, reason: 'das Blatt ist zu');
    expect(find.text('Solo'), findsNothing);
    expect(trails.recordings.where((r) => r.trailId == solo), isEmpty);
    expect(trails.details.where((d) => d.trailId == solo), isEmpty);
  });

  testWidgets(
    'geteilter Trail: meine Zeilen gehen, der Trail und Bobs bleiben',
    (tester) async {
      await openTrail(tester, 'Roots');
      await tapWithdraw(tester);
      expect(find.textContaining('bleibt für deine Buddys'), findsOneWidget);
      await tester.tap(confirm);
      await settle(tester, frames: 20);

      expect(
        find.text('Roots'),
        findsOneWidget,
        reason: 'Bob belegt ihn weiter',
      );
      bool mine(String userId) => userId == annaId;
      expect(
        trails.recordings.where((r) => r.trailId == roots && mine(r.userId)),
        isEmpty,
      );
      expect(
        trails.details.where((d) => d.trailId == roots && mine(d.userId)),
        isEmpty,
      );
      expect(
        trails.notes.where((n) => n.trailId == roots).map((n) => n.userId),
        [bobId],
      );
      expect(trails.recordings.where((r) => r.trailId == roots), hasLength(1));

      // Wieder offen: Er ist nicht mehr meiner, also kein Löschen.
      await tester.tap(find.text('Roots'));
      await settle(tester);
      expect(withdraw, findsNothing);
    },
  );

  testWidgets('nur über einen Buddy gesehen: kein Löschen', (tester) async {
    await openTrail(tester, 'Bobs Flow');
    expect(withdraw, findsNothing);
  });

  testWidgets('Abbrechen lässt alles stehen', (tester) async {
    await openTrail(tester, 'Solo');
    await tapWithdraw(tester);
    await tester.tap(find.text('Abbrechen'));
    await settle(tester);
    expect(withdraw, findsOneWidget, reason: 'das Blatt bleibt offen');
    expect(trails.recordings.where((r) => r.trailId == solo), hasLength(1));
  });

  testWidgets('ohne Netz: sichtbarer Fehler, nichts gelöscht, Blatt bleibt', (
    tester,
  ) async {
    trails.failNextWithdraw = const SocketException('kein Netz');
    await openTrail(tester, 'Solo');
    await tapWithdraw(tester);
    await tester.tap(confirm);
    await settle(tester, frames: 20);
    expect(find.text('Beitrag gelöscht'), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(withdraw, findsOneWidget);
    expect(trails.recordings.where((r) => r.trailId == solo), hasLength(1));
  });
}
