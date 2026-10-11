// Duplikate zusammenführen (#107 Schritt 2, Konzept 6.1): „Ist ein
// Duplikat …" im Trail-Blatt, was danach bei mir und bei Buddys steht, und
// „Trennen". Kein Ausgangskorb — ohne Netz scheitert es sichtbar.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/errors.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

/// 25 m nach Osten bei 48° N, in Grad.
const east25m = 25 / (111320 * 0.6691);

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late String annaId, bobId, carlaId;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    final bob = backend.addUser(username: 'bob');
    final carla = backend.addUser(username: 'carla');
    backend.addFriendship(anna.id, bob.id);
    backend.addFriendship(anna.id, carla.id);
    backend.addFriendship(bob.id, carla.id);
    annaId = anna.id;
    bobId = bob.id;
    carlaId = carla.id;
    trails = FakeTrailRepository(
        myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    trails.usernames
      ..[anna.id] = 'anna'
      ..[bob.id] = 'bob'
      ..[carla.id] = 'carla';
  });

  final mergeButton = find.byKey(const ValueKey('trail-merge'));
  final confirm = find.byKey(const ValueKey('merge-confirm'));

  Future<void> openTrail(WidgetTester tester, String name) async {
    await pumpApp(tester, backend, trails: trails);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    await tester.scrollUntilVisible(find.text(name), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text(name));
    await settle(tester);
  }

  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.tap(f);
    await settle(tester);
  }

  testWidgets('eigenes Import-Duplikat: zusammenführen, der ältere bleibt, alles Eigene zieht um',
      (tester) async {
    backend.signInAs(annaId);
    final hang = trails.seedTrail(annaId, name: 'Hang', grade: 2);
    final copy = trails.seedTrail(annaId, name: 'Hang (Import)', lon: 9 + east25m, rating: 4);
    trails.seedNote(annaId, copy, 'Wurzeln nass');

    await openTrail(tester, 'Hang (Import)');
    await tapVisible(tester, mergeButton);
    expect(find.text('Derselbe Trail wie …'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('merge-candidate-$hang')));
    await settle(tester);

    // Vorbelegt: gleich viele Beitragende, also der ältere.
    expect(find.text('Welcher Trail bleibt?'), findsOneWidget);
    final keepHang = tester.widget<RadioListTile<String>>(find.byKey(ValueKey('merge-keep-$hang')));
    expect(keepHang.value, hang);
    expect(find.textContaining('ziehen von „Hang (Import)" nach „Hang"'), findsOneWidget);
    await tester.tap(confirm);
    await settle(tester, frames: 20);

    expect(find.textContaining('Zusammengeführt — „Hang" bleibt'), findsOneWidget);
    expect(mergeButton, findsNothing, reason: 'das Blatt ist zu');
    expect(find.text('Hang (Import)'), findsNothing);
    expect(find.text('Hang'), findsOneWidget);
    expect(trails.recordings.where((r) => r.trailId == copy), isEmpty);
    expect(trails.recordings.where((r) => r.trailId == hang), hasLength(2));
    expect(trails.notes.single.trailId, hang);
    final mine = trails.details.where((d) => d.userId == annaId).toList();
    expect(mine, hasLength(1));
    expect(mine.single.name, 'Hang', reason: 'der behaltene gewinnt');
    expect(mine.single.grade, 2);
    expect(mine.single.rating, 4, reason: 'leere Felder füllt das Duplikat');
    expect(trails.aliases.single.trailId, copy);
  });

  testWidgets('selbst wählen, welcher bleibt', (tester) async {
    backend.signInAs(annaId);
    final hang = trails.seedTrail(annaId, name: 'Hang');
    final copy = trails.seedTrail(annaId, name: 'Hang neu', lon: 9 + east25m);

    await openTrail(tester, 'Hang');
    await tapVisible(tester, mergeButton);
    await tester.tap(find.byKey(ValueKey('merge-candidate-$copy')));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('merge-keep-$copy')));
    await settle(tester);
    await tester.tap(confirm);
    await settle(tester, frames: 20);

    expect(find.text('Hang neu'), findsOneWidget);
    expect(find.text('Hang'), findsNothing);
    expect(trails.aliases.single.trailId, hang);
  });

  testWidgets('kein Trail nah genug daneben: kein Knopf', (tester) async {
    backend.signInAs(annaId);
    trails.seedTrail(annaId, name: 'Hang');
    trails.seedTrail(annaId, name: 'Weit weg', lon: 9.01);
    await openTrail(tester, 'Hang');
    expect(find.text('Hang'), findsWidgets);
    expect(mergeButton, findsNothing);
  });

  testWidgets('ein Buddy, der beide sieht und am Duplikat nichts hat, sieht es darunter',
      (tester) async {
    // Bob hat „Wald", Carla „Wald unten" knapp daneben, Anna beide.
    final wald = trails.seedTrail(bobId, name: 'Wald');
    final unten = trails.seedTrail(carlaId, name: 'Wald unten', lon: 9 + east25m);
    trails.seedTrail(annaId, trailId: unten);
    backend.signInAs(annaId);
    await trails.mergeInto(duplicateId: unten, targetId: wald);

    backend.signInAs(bobId);
    await openTrail(tester, 'Wald');
    expect(find.text('Wald unten'), findsNothing, reason: 'still darunter, ohne Frage');
    expect(find.byKey(ValueKey('trail-merged-$unten')), findsOneWidget);
    expect(find.textContaining('Zusammengeführt: „Wald unten" — von anna'), findsOneWidget);
    expect(find.byKey(ValueKey('trail-unmerge-$unten')), findsNothing,
        reason: 'lösen kann nur, wer zugeordnet hat');
  });

  testWidgets('wer am Duplikat selbst etwas hat, behält es (Vorschlag erst in Schritt 3)',
      (tester) async {
    final wald = trails.seedTrail(bobId, name: 'Wald');
    final unten = trails.seedTrail(carlaId, name: 'Wald unten', lon: 9 + east25m);
    trails.seedTrail(annaId, trailId: unten);
    backend.signInAs(annaId);
    await trails.mergeInto(duplicateId: unten, targetId: wald);

    backend.signInAs(carlaId);
    await pumpApp(tester, backend, trails: trails);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    expect(find.text('Wald unten'), findsOneWidget);
  });

  testWidgets('Trennen: das Duplikat erscheint wieder, meine Aufzeichnung bleibt', (tester) async {
    final wald = trails.seedTrail(annaId, name: 'Wald');
    final unten = trails.seedTrail(carlaId, name: 'Wald unten', lon: 9 + east25m);
    trails.seedTrail(annaId, trailId: unten);
    backend.signInAs(annaId);
    await trails.mergeInto(duplicateId: unten, targetId: wald);

    await openTrail(tester, 'Wald');
    expect(find.text('Wald unten'), findsNothing);
    expect(find.textContaining('Zusammengeführt: „Wald unten" — von dir'), findsOneWidget);
    await tapVisible(tester, find.byKey(ValueKey('trail-unmerge-$unten')));
    expect(find.text('Wieder trennen?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('trail-unmerge-confirm')));
    await settle(tester, frames: 20);

    expect(find.text('Getrennt'), findsOneWidget);
    expect(trails.aliases, isEmpty);
    expect(trails.recordings.where((r) => r.trailId == wald && r.userId == annaId), hasLength(2),
        reason: 'umgezogene eigene Aufzeichnungen bleiben');
    await tester.tap(find.byIcon(Icons.close));
    await settle(tester);
    expect(find.text('Wald unten'), findsOneWidget, reason: 'Carla hat etwas daran');
  });

  testWidgets('der Server lehnt ab: der Grund, kein Fehlerbericht', (tester) async {
    final reported = <String>[];
    setErrorSink((context, _, _) => reported.add(context));
    addTearDown(() => setErrorSink(null));
    backend.signInAs(annaId);
    trails.seedTrail(annaId, name: 'Hang');
    final copy = trails.seedTrail(annaId, name: 'Hang (Import)', lon: 9 + east25m);
    trails.failNextMerge = const MergeRejectedException(MergeRejection.notNear);

    await openTrail(tester, 'Hang');
    await tapVisible(tester, mergeButton);
    await tester.tap(find.byKey(ValueKey('merge-candidate-$copy')));
    await settle(tester);
    await tester.tap(confirm);
    await settle(tester, frames: 20);

    expect(find.textContaining('nicht nah genug beieinander'), findsOneWidget);
    expect(trails.aliases, isEmpty);
    expect(reported, isNot(contains('Duplikat zusammenführen')));
  });

  testWidgets('ohne Netz: sichtbarer Fehler, nichts zusammengeführt, Blatt bleibt', (tester) async {
    backend.signInAs(annaId);
    trails.seedTrail(annaId, name: 'Hang');
    final copy = trails.seedTrail(annaId, name: 'Hang (Import)', lon: 9 + east25m);
    trails.failNextMerge = const SocketException('kein Netz');

    await openTrail(tester, 'Hang');
    await tapVisible(tester, mergeButton);
    await tester.tap(find.byKey(ValueKey('merge-candidate-$copy')));
    await settle(tester);
    await tester.tap(confirm);
    await settle(tester, frames: 20);

    expect(find.textContaining('Keine Verbindung'), findsOneWidget);
    expect(mergeButton, findsOneWidget, reason: 'das Blatt bleibt offen');
    expect(trails.aliases, isEmpty);
    expect(trails.recordings.where((r) => r.trailId == copy), hasLength(1));
  });
}
