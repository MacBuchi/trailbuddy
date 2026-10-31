// Das Trail-Blatt nach Design 1i/4f (seit 0.39.0): Titel in Versalien,
// drei Kennzahl-Kacheln nebeneinander, darunter seit 0.49.0 (#101)
// Bewertung und Zustand, eine neue Meldung gelb gerahmt, unten „Melden"
// (Lime, ganze Breite — seit #433 EIN Knopf), „Karte" darunter.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/app_colors.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  testWidgets('Kacheln, gerahmter Hinweis und die Aktionen unten', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    final bob = backend.addUser(username: 'bob');
    backend.addFriendship(anna.id, bob.id);
    backend.signInAs(anna.id);
    final trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    trails.usernames[bob.id] = 'bob';
    final id = trails.seedTrail(bob.id, name: 'Rosskopf Süd', grade: 2, ele: [900, 700, 480]);
    trails.seedNote(bob.id, id, 'Baum liegt quer', at: DateTime.now());

    await pumpApp(tester, backend, trails: trails);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    await tester.tap(find.text('Rosskopf Süd'));
    await settle(tester);

    expect(find.text('ROSSKOPF SÜD'), findsOneWidget);
    final tiles = [
      find.byKey(const ValueKey('metric-length')),
      find.byKey(const ValueKey('metric-elevation')),
      find.byKey(const ValueKey('grade-chip')),
    ];
    final xs = [for (final t in tiles) tester.getCenter(t).dx];
    expect(xs, orderedEquals([...xs]..sort()), reason: 'Länge, Höhe, S-Grad von links nach rechts');
    expect({for (final t in tiles) tester.getCenter(t).dy.round()}, hasLength(1),
        reason: 'in EINER Reihe');
    expect(findLabel('↓ 420 Hm · ↑ 0 Hm'), findsOneWidget);
    expect(findLabel('S2 · 1 Einschätzung'), findsOneWidget);
    // Die zweite Reihe (Rework E8): Bewertung und Zustand, unter der ersten.
    final rating = find.byKey(const ValueKey('metric-rating'));
    final condition = find.byKey(const ValueKey('metric-condition'));
    expect(tester.getCenter(rating).dy, closeTo(tester.getCenter(condition).dy, 1));
    expect(tester.getCenter(rating).dx, lessThan(tester.getCenter(condition).dx));
    expect(tester.getTopLeft(rating).dy, greaterThan(tester.getBottomLeft(tiles.first).dy),
        reason: 'unter Länge, Höhe, S-Grad');
    expect(findLabel('Noch keine Bewertung'), findsOneWidget);
    expect(findLabel('Kein Zustand gemeldet'), findsOneWidget);

    final note = tester.widget<Container>(find.ancestor(
        of: find.text('Baum liegt quer'), matching: find.byWidgetPredicate((w) => w is Container && w.key != null)));
    final border = (note.decoration! as BoxDecoration).border! as Border;
    expect(border.top.color, AppColors.light.map.note, reason: 'neue Meldung: gelber Rahmen');

    final report = find.byKey(const ValueKey('trail-report'));
    expect(tester.widget(report), isA<FilledButton>(), reason: 'die Hauptaktion in Lime');
    expect(find.byKey(const ValueKey('add-note')), findsNothing, reason: 'ein Knopf, nicht zwei');
    final sheetWidth = tester.getSize(find.byKey(const ValueKey('trail-reports'))).width;
    expect(tester.getSize(report).width, closeTo(sheetWidth, 1), reason: 'ganze Breite (A13)');
    final map = find.byKey(const ValueKey('trail-show-on-map'));
    expect(tester.getTopLeft(map).dy, greaterThan(tester.getBottomLeft(report).dy),
        reason: 'zur Karte in einer eigenen Zeile');
    expect(tester.getTopLeft(report).dy, greaterThan(tester.getBottomLeft(find.text('Baum liegt quer')).dy),
        reason: 'unter den Meldungen');
  });
}
