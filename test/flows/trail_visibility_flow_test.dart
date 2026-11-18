// Die Sichtbarkeitsregel des Konzepts (3 und 6), wie die App sie zeigt:
// eigene Belege, Belege direkter Buddys, nichts von Fremden; ein Trail
// mit zwei Namen; eine Statusmeldung mit Datum.
import 'package:flutter/material.dart';
import 'package:trailbuddy/models/trail.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late String annaId;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    final bob = backend.addUser(username: 'bob');
    final carl = backend.addUser(username: 'carl');
    backend.addFriendship(anna.id, bob.id);
    backend.signInAs(anna.id);
    annaId = anna.id;
    trails = FakeTrailRepository(
      myId: () => backend.currentUserId ?? '',
      areFriends: backend.areFriends,
    );
    trails.usernames[bob.id] = 'bob';
    trails.usernames[carl.id] = 'carl';
    // Ein Trail, den Bob zuerst belegt hat („Roots") und Anna danach
    // („Hexentanz"); Bobs zweiter Trail; Carls Trail, den niemand sehen darf.
    final shared = trails.seedTrail(bob.id, name: 'Roots');
    trails.seedTrail(anna.id, name: 'Hexentanz', trailId: shared);
    trails.seedTrail(
      bob.id,
      name: 'Bobs Flow',
      lat: 48.1,
      status: TrailStatus.closed,
      statusAt: DateTime.now().subtract(const Duration(days: 40)),
    );
    trails.seedTrail(carl.id, name: 'Geheim', lat: 48.2);
  });

  testWidgets('Liste: eigener Name gewinnt, Buddy-Trail steht, Fremdes fehlt', (
    tester,
  ) async {
    await pumpApp(tester, backend, trails: trails);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);

    expect(find.text('Meine Trails (1)'), findsOneWidget);
    expect(find.text('Hexentanz'), findsOneWidget);
    expect(find.text('Roots'), findsNothing);
    expect(find.text('Von Buddys (1)'), findsOneWidget);
    expect(find.text('Bobs Flow'), findsOneWidget);
    expect(find.textContaining('GESPERRT'), findsOneWidget);
    expect(find.text('Geheim'), findsNothing);

    // Das Blatt nennt den zweiten Namen und den Buddy.
    await tester.tap(find.text('Hexentanz'));
    await settle(tester);
    expect(find.text('auch: Roots'), findsOneWidget);
    expect(find.textContaining('1 Buddy (bob)'), findsOneWidget);
    expect(find.text('Mein Beitrag'), findsOneWidget);

    // Ein Buddy-Trail, den ich nicht gefahren bin: kein eigener Beitrag.
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    await tester.tap(find.text('Bobs Flow'));
    await settle(tester);
    expect(
      find.textContaining('du bist ihn noch nicht gefahren'),
      findsOneWidget,
    );
    expect(find.textContaining('gemeldet vor 40 Tagen'), findsOneWidget);
    expect(find.text('Mein Beitrag'), findsNothing);
  });

  testWidgets('Karte zeichnet genau die sichtbaren Trails', (tester) async {
    await pumpApp(tester, backend, trails: trails);
    await settle(tester, frames: 20);
    final lines = fakeMapLayers(
      tester,
    ).polylines.where((p) => p.hitValue is Trail);
    expect(lines.length, 2);
    expect(lines.map((p) => (p.hitValue as Trail).id).toSet(), hasLength(2));
  });

  testWidgets('Melden: die Meldung steht im Verlauf, der Beitrag bleibt', (
    tester,
  ) async {
    await pumpApp(tester, backend, trails: trails);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    await tester.tap(find.text('Hexentanz'));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('trail-report')));
    await tester.tap(find.byKey(const ValueKey('trail-report')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('report-status-destroyed')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('report-submit')));
    await settle(tester, frames: 20);

    final r = trails.reports.where((r) => r.userId == annaId).single;
    expect(r.status, TrailStatus.destroyed);
    expect(
      trails.details.where((d) => d.userId == annaId).single.name,
      'Hexentanz',
      reason: 'Melden fasst den Beitrag nicht an',
    );
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('Gemeldet'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('status-chip')), findsOneWidget);
  });

  testWidgets('privater Beitrag des Buddys: sein Beleg verschwindet', (
    tester,
  ) async {
    final bobId = backend.users.firstWhere((u) => u.username == 'bob').id;
    final d = trails.details.firstWhere(
      (x) => x.userId == bobId && x.name == 'Bobs Flow',
    );
    trails.details.remove(d);
    trails.details.add(d.copyWith(visibility: TrailVisibility.private));
    await pumpApp(tester, backend, trails: trails);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    expect(find.text('Bobs Flow'), findsNothing);
    expect(find.text('Hexentanz'), findsOneWidget);
  });
}
