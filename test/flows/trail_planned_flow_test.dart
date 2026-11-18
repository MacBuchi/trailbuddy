// #100: Eine Datei ohne Fahrzeiten ist eine Behauptung, keine Fahrt. Das
// Blatt sagt, wer einen Trail nur geplant hat (Konzept 4.6).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    final bob = backend.addUser(username: 'bob');
    backend.addFriendship(anna.id, bob.id);
    backend.signInAs(anna.id);
    trails = FakeTrailRepository(
      myId: () => backend.currentUserId ?? '',
      areFriends: backend.areFriends,
    );
    trails.usernames[bob.id] = 'bob';
    // Bob hat „Vereinslinie" nur als Datei, Anna ist sie gefahren.
    final shared = trails.seedTrail(
      bob.id,
      name: 'Vereinslinie',
      source: RecordingSource.planned,
    );
    trails.seedTrail(anna.id, trailId: shared);
    // „Gefahren" ist ganz normal.
    trails.seedTrail(bob.id, name: 'Gefahren', lat: 48.2);
    // „Aus Datei" kennt niemand aus einer Fahrt.
    trails.seedTrail(
      bob.id,
      name: 'Aus Datei',
      lat: 48.1,
      source: RecordingSource.planned,
    );
  });

  Future<void> openSheet(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await settle(tester);
  }

  testWidgets('das Blatt nennt, wer nur geplant hat', (tester) async {
    // Hoch genug, dass die Liste alle drei Zeilen baut.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester, backend, trails: trails);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);

    await openSheet(tester, 'Vereinslinie');
    expect(find.text('Nur geplant, nicht gefahren: bob.'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);

    await openSheet(tester, 'Aus Datei');
    expect(find.byKey(const ValueKey('trail-planned')), findsOneWidget);
    expect(
      find.textContaining(
        'Jeder Beleg hier kommt aus einer Datei ohne Fahrzeiten',
      ),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);

    await openSheet(tester, 'Gefahren');
    expect(find.byKey(const ValueKey('trail-planned')), findsNothing);
  });
}
