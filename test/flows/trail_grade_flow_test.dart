// Die Schwierigkeit (Issue #14, Teil 2): S0–S5 der Singletrail-Skala,
// von den Buddys eingeschätzt. Das Blatt zeigt Median, Spanne und Anzahl,
// die eigene Einschätzung geht mit einem Tipp, und die Skala ist überall
// dort erklärt, wo man einen Grad angibt.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/trails/singletrail_scale.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_trails.dart';
import '../fakes/l10n_de.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late String annaId;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    final bob = backend.addUser(username: 'bob');
    backend.addFriendship(anna.id, bob.id);
    backend.signInAs(anna.id);
    annaId = anna.id;
    trails = FakeTrailRepository(
        myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    trails.usernames[bob.id] = 'bob';
    final shared = trails.seedTrail(bob.id, name: 'Roots', grade: 2);
    trails.seedTrail(anna.id, trailId: shared);
    trails.seedTrail(bob.id, name: 'Bobs Flow', lat: 48.1, grade: 1);
  });

  Future<void> openTrail(WidgetTester tester, String name) async {
    await pumpApp(tester, backend, trails: trails);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    await tester.tap(find.text(name));
    await settle(tester);
  }

  testWidgets('eigene Einschätzung mit einem Tipp, zweiter Tipp nimmt sie zurück',
      (tester) async {
    await openTrail(tester, 'Roots');
    expect(findLabel('S2 · 1 Einschätzung'), findsOneWidget);
    expect(find.text('Deine Einschätzung'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('own-grade-4')));
    await tester.tap(find.byKey(const ValueKey('own-grade-4')));
    await settle(tester, frames: 20);
    expect(trails.details.singleWhere((d) => d.userId == annaId).grade, 4);
    // Median von [2, 4]: der schwerere; dazu die Spanne.
    expect(findLabel('S4 · S2–S4 · 2 Einschätzungen'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('own-grade-4')));
    await settle(tester, frames: 20);
    expect(trails.details.singleWhere((d) => d.userId == annaId).grade, isNull);
    expect(findLabel('S2 · 1 Einschätzung'), findsOneWidget);
  });

  testWidgets('wer hat was gesagt, und was S0 bis S5 heißt', (tester) async {
    await openTrail(tester, 'Roots');
    await tester.tap(find.byKey(const ValueKey('grade-chip')));
    await settle(tester);
    expect(find.text('bob'), findsOneWidget);
    expect(find.text(singletrailGrade(2).short(l10nDe)), findsOneWidget);

    await tester.tap(find.text('Was bedeuten S0 bis S5?'));
    await settle(tester);
    expect(find.text('Singletrail-Skala'), findsOneWidget);
    for (final g in kSingletrailScale) {
      expect(find.byKey(ValueKey('sts-${g.value}')), findsOneWidget);
    }
    expect(find.text(singletrailGrade(5).description(l10nDe)), findsOneWidget);
  });

  testWidgets('beim Angeben im Beitrag: Kurzfassung in der Auswahl, „?" öffnet die Skala',
      (tester) async {
    await openTrail(tester, 'Roots');
    await tester.ensureVisible(find.text('Mein Beitrag'));
    await tester.tap(find.text('Mein Beitrag'));
    await settle(tester);
    final dialog = find.byType(AlertDialog);
    // „Keine Angabe" über den Typ — das Feld ist eine Auswahl, kein Text.
    await tester.tap(find.widgetWithText(DropdownButtonFormField<int?>, 'Keine Angabe'));
    await settle(tester);
    expect(find.text('S3 · ${singletrailGrade(3).short(l10nDe)}'), findsWidgets);
    await tester.tap(find.text('S3 · ${singletrailGrade(3).short(l10nDe)}').last);
    await settle(tester);

    await tester.tap(find.descendant(
        of: dialog, matching: find.byTooltip('Singletrail-Skala erklären')));
    await settle(tester);
    expect(find.text('Singletrail-Skala'), findsOneWidget);
    expect(find.text(singletrailGrade(3).description(l10nDe)), findsOneWidget);
  });

  testWidgets('fremder Trail, den ich nicht gefahren bin: keine eigene Einschätzung',
      (tester) async {
    await openTrail(tester, 'Bobs Flow');
    expect(findLabel('S1 · 1 Einschätzung'), findsOneWidget);
    expect(find.text('Deine Einschätzung'), findsNothing);
    expect(find.byKey(const ValueKey('own-grade-1')), findsNothing);
  });
}
