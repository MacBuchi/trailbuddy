// Der Charakter eines Trails (#72): im Beitrag mehrfach wählbar, im Blatt
// die zwei häufigsten mit Anzahl, in der Liste als Symbole, und „Flowig"
// filtert Liste und Karte über dieselbe Regel.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/trails/trail_traits.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';
import '../fakes/l10n_de.dart';

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
    final roots = trails.seedTrail(bob.id,
        name: 'Roots', traits: {TrailTrait.rocky, TrailTrait.steep});
    trails.seedTrail(anna.id, trailId: roots);
    trails.seedTrail(bob.id,
        name: 'Hexentanz', lat: 48.1, traits: {TrailTrait.flowy, TrailTrait.jumps});
  });

  Set<String> drawn(WidgetTester tester) => {
        for (final l in fakeMapLayers(tester).polylines)
          if (l.hitValue is Trail) (l.hitValue as Trail).displayName(l10nDe),
      };

  testWidgets('im Beitrag gewählt, im Blatt gezählt, in der Liste als Symbol', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester, backend, trails: trails);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    // Die Liste zeigt die Symbole, je mit Wort für Bildschirmleser.
    final rootsTile = find.ancestor(of: find.text('Roots'), matching: find.byType(ListTile));
    expect(find.descendant(of: rootsTile, matching: find.byIcon(TrailTrait.rocky.icon)), findsOneWidget);
    expect(find.descendant(of: rootsTile, matching: find.byIcon(TrailTrait.steep.icon)), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Verblockt')), findsWidgets);
    semantics.dispose();

    await tester.tap(find.text('Roots'));
    await settle(tester);
    expect(find.text('Verblockt · 1'), findsOneWidget);
    expect(find.text('Steil · 1'), findsOneWidget);

    await tester.ensureVisible(find.text('Mein Beitrag'));
    await tester.tap(find.text('Mein Beitrag'));
    await settle(tester);
    expect(find.text('Charakter'), findsOneWidget);
    for (final t in TrailTrait.values) {
      expect(find.byKey(ValueKey('trait-${t.db}')), findsOneWidget, reason: t.db);
    }
    await tester.tap(find.byKey(const ValueKey('trait-rocky')));
    await tester.ensureVisible(find.byKey(const ValueKey('trait-natural')));
    await tester.tap(find.byKey(const ValueKey('trait-natural')));
    await settle(tester);
    await tester.tap(find.text('Speichern'));
    await settle(tester, frames: 20);

    expect(trails.details.singleWhere((d) => d.userId == annaId).traits,
        {TrailTrait.rocky, TrailTrait.natural});
    // Verblockt zwei Nennungen, dann Gleichstand Steil/Naturtrail: Steil
    // steht in der Reihenfolge vorn.
    expect(find.text('Verblockt · 2'), findsOneWidget);
    expect(find.text('Steil · 1'), findsOneWidget);
    expect(find.textContaining('Naturtrail ·'), findsNothing, reason: 'höchstens zwei');
  });

  testWidgets('„Flowig" filtert Liste und Karte, die Karte sagt es', (tester) async {
    await pumpApp(tester, backend, trails: trails);
    await settle(tester, frames: 20);
    expect(drawn(tester), {'Roots', 'Hexentanz'});

    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    await tester.tap(find.byKey(const ValueKey('trail-filter-flowy')));
    await settle(tester);
    expect(find.text('Roots'), findsNothing);
    expect(find.text('Hexentanz'), findsOneWidget);

    await openTab(tester, 'Karte');
    await settle(tester, frames: 20);
    expect(drawn(tester), {'Hexentanz'});
    expect(find.text('Gefiltert: Flowig'), findsOneWidget);
  });
}
