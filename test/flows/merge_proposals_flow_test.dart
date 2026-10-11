// „Sind das dieselben?" (#107 Schritt 3, Konzept 6.1): der Vorschlag im
// Trail-Blatt und im Profil, „Derselbe", „Verschieden" mit Rückgängig,
// „Beide ansehen" auf der Karte und „Auf gemeinsamen Teil kürzen".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/trails/merge_proposals.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

/// Meter nach Osten bei 48° N, in Grad.
double east(double m) => m / (111320 * 0.6691);

/// Eine Linie nach Norden über [m] Meter ab [fromM], alle 50 m ein Punkt.
List<LatLng> north(double m, {double eastM = 0, double fromM = 0}) => [
      for (var d = fromM; d <= fromM + m + 0.001; d += 50) LatLng(48 + d / 111320, 9 + east(eastM)),
    ];

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late String annaId, bobId;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    final bob = backend.addUser(username: 'bob');
    backend.addFriendship(anna.id, bob.id);
    annaId = anna.id;
    bobId = bob.id;
    backend.signInAs(annaId);
    trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    trails.usernames
      ..[anna.id] = 'anna'
      ..[bob.id] = 'bob';
  });

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
    await settle(tester, frames: 12);
  }

  /// Bob hält Annas „Wald unten" für ein Duplikat seines „Wald".
  ({String wald, String unten}) declared() {
    final wald = trails.seedTrail(bobId, name: 'Wald');
    final unten = trails.seedTrail(annaId, name: 'Wald unten', lon: 9 + east(25));
    trails.seedAlias(bobId, unten, wald);
    return (wald: wald, unten: unten);
  }

  testWidgets('ein Buddy hält meinen Trail für ein Duplikat: Vorschlag, „Derselbe" führt zusammen',
      (tester) async {
    final ids = declared();
    final key = pairKey(ids.wald, ids.unten);
    await openTrail(tester, 'Wald unten');
    expect(find.textContaining('bob hält „Wald unten" und „Wald" für denselben Trail'), findsOneWidget);
    await tapVisible(tester, find.byKey(ValueKey('merge-proposal-same-$key')));
    final keep = tester.widget<RadioListTile<String>>(find.byKey(ValueKey('merge-keep-${ids.wald}')));
    expect(keep.value, ids.wald);
    expect(find.text('Welcher Trail bleibt?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('merge-confirm')));
    await settle(tester, frames: 20);

    expect(find.textContaining('Zusammengeführt — „Wald" bleibt'), findsOneWidget);
    expect(find.text('Wald unten'), findsNothing);
    expect(trails.aliases.where((a) => a.userId == annaId).single.sameAs, ids.wald);
    expect(trails.recordings.where((r) => r.userId == annaId).single.trailId, ids.wald);
  });

  testWidgets('„Verschieden": der Vorschlag ist weg, „Rückgängig" holt ihn zurück', (tester) async {
    final ids = declared();
    final key = pairKey(ids.wald, ids.unten);
    await openTrail(tester, 'Wald unten');
    await tapVisible(tester, find.byKey(ValueKey('merge-proposal-distinct-$key')));
    expect(find.textContaining('Gemerkt: verschiedene Trails'), findsOneWidget);
    expect(find.byKey(ValueKey('merge-proposal-$key')), findsNothing);
    expect(trails.distinct.single.userId, annaId);

    await tester.tap(find.text('Rückgängig'));
    await settle(tester, frames: 20);
    expect(trails.distinct, isEmpty);
    expect(find.byKey(ValueKey('merge-proposal-$key')), findsOneWidget);
  });

  testWidgets('im Profil: Zeile mit Zahl und die Seite mit dem Vorschlag', (tester) async {
    final ids = declared();
    await pumpApp(tester, backend, trails: trails);
    await openTab(tester, 'Profil');
    await settle(tester, frames: 20);
    final row = find.text('1 Paar zu prüfen');
    await tester.scrollUntilVisible(row, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(row);
    await settle(tester);
    expect(find.byKey(ValueKey('merge-proposal-${pairKey(ids.wald, ids.unten)}')), findsOneWidget);
  });

  testWidgets('ohne Vorschlag keine Profilzeile', (tester) async {
    trails.seedTrail(annaId, name: 'Hang');
    await pumpApp(tester, backend, trails: trails);
    await openTab(tester, 'Profil');
    await settle(tester, frames: 20);
    expect(find.text('Sind das dieselben?'), findsNothing);
  });

  testWidgets('aus dem Abgleich: nur, was grob beieinander liegt', (tester) async {
    final hang = trails.seedTrail(annaId, name: 'Hang');
    final daneben = trails.seedTrail(bobId, name: 'Hang (Bob)', lon: 9 + east(20));
    final weit = trails.seedTrail(bobId, name: 'Weit', lon: 9 + east(300));
    trails.seedOverlap(hang, daneben);
    trails.seedOverlap(hang, weit);
    await openTrail(tester, 'Hang');
    expect(find.textContaining('liegen fast aufeinander'), findsOneWidget);
    expect(find.byKey(ValueKey('merge-proposal-${pairKey(hang, daneben)}')), findsOneWidget);
    expect(find.byKey(ValueKey('merge-proposal-${pairKey(hang, weit)}')), findsNothing);
  });

  testWidgets('„Beide ansehen": die Karte zeigt beide, oben steht es, X beendet', (tester) async {
    final ids = declared();
    await openTrail(tester, 'Wald unten');
    await tapVisible(tester, find.byKey(ValueKey('merge-proposal-compare-${pairKey(ids.wald, ids.unten)}')));
    await settle(tester, frames: 12);
    expect(find.byKey(const ValueKey('merge-compare-banner')), findsOneWidget);
    expect(find.textContaining('„Wald unten" und „Wald"'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('merge-compare-close')));
    await settle(tester);
    expect(find.byKey(const ValueKey('merge-compare-banner')), findsNothing);
  });

  testWidgets('meine lange Fassung enthält den Trail: kürzen im Zerlege-Blatt, dann die lange löschen',
      (tester) async {
    TrailRecording rec(String trailId, String userId, List<LatLng> pts) => TrailRecording(
          id: 'rec-$trailId',
          trailId: trailId,
          userId: userId,
          source: RecordingSource.import,
          recordedAt: null,
          reversed: false,
          quality: 0.4,
          createdAt: DateTime(2026, 1, 1),
          points: pts,
          lengthM: 1600,
        );
    trails.recordings
      ..add(rec('LANG', annaId, north(1600)))
      ..add(rec('KURZ', bobId, north(1000, fromM: 600, eastM: 5)));
    trails.details
      ..add(TrailDetails(trailId: 'LANG', userId: annaId, name: 'Mit Anfahrt'))
      ..add(TrailDetails(trailId: 'KURZ', userId: bobId, name: 'Kurz'))
      // Anna kennt „Kurz" schon: dann fragt das Blatt nicht nach dem Übernehmen.
      ..add(TrailDetails(trailId: 'KURZ', userId: annaId, name: 'Kurz'));
    trails.seedOverlap('LANG', 'KURZ');
    // Der Abgleich hängt das Stück an „Kurz".
    trails.matcher = (_) => 'KURZ';

    await openTrail(tester, 'Mit Anfahrt');
    await tapVisible(tester, find.byKey(ValueKey('merge-proposal-trim-${pairKey('KURZ', 'LANG')}')));
    await settle(tester, frames: 20);
    expect(find.text('Fahrt zerlegen'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('split-submit')));
    await settle(tester, frames: 20);

    expect(find.text('Die lange Fassung löschen?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('split-trim-withdraw')));
    await settle(tester, frames: 20);
    expect(trails.recordings.where((r) => r.trailId == 'LANG'), isEmpty);
    expect(trails.recordings.where((r) => r.trailId == 'KURZ' && r.userId == annaId), hasLength(1));
  });
}
