// Gemerkte Startpunkte im Planer (#543, Schritt 3,
// `docs/konzept-startpunkte.md` 4, 5.1, 9): „Gemerkt" in Start und Ziel
// des Einstiegs, die Liste (eigene und fremde, nach Abstand, der zuletzt
// gewählte oben), die Vorbelegung nur vor Ort (300 m), „Start merken" und
// „Mein Standort merken" (privat, mit der Warnung vor der Haustür) in der
// Wahl des Starts, der Name im Kopf. Alle Koordinaten sind erfunden (A7).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/routing/loop_planner.dart' show LoopEndMode;
import 'package:trailbuddy/features/routing/loop_planner_controller.dart';
import 'package:trailbuddy/models/start_point.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/fake_settings.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late String annaId;
  late String benId;
  late FakeTrailRepository trails;
  late FakeSettings settings;

  // Zu Hause, der eigene Parkplatz 1,1 km nördlich, der eines Buddys
  // 2,2 km nördlich — erfundene Lagen.
  const home = LatLng(47.5, 10.5);
  const carPark = LatLng(47.51, 10.5);
  const buddyPark = LatLng(47.52, 10.5);

  setUp(() {
    backend = FakeBackend();
    annaId = backend.addUser(username: 'anna').id;
    benId = backend.addUser(username: 'ben').id;
    backend.addFriendship(annaId, benId);
    backend.signInAs(annaId);
    trails = FakeTrailRepository(
      myId: () => backend.currentUserId ?? '',
      areFriends: backend.areFriends,
    );
    trails.usernames[benId] = 'ben';
    trails.seedTrail(annaId, name: 'Roots');
    settings = FakeSettings();
  });

  StartPoint point(
    String owner,
    String clientId,
    String name,
    LatLng at, {
    TrailVisibility visibility = TrailVisibility.buddies,
  }) => StartPoint(
    clientId: clientId,
    userId: owner,
    name: name,
    lat: at.latitude,
    lon: at.longitude,
    visibility: visibility,
    createdAt: DateTime.utc(2026, 11, 16),
  );

  void seedPoints() {
    trails.startPoints
      ..add(
        point(
          annaId,
          'p-own',
          'Parkplatz Talboden',
          carPark,
          visibility: TrailVisibility.private,
        ),
      )
      ..add(point(benId, 'p-ben', 'Wanderparkplatz Alm', buddyPark));
  }

  Future<void> start(WidgetTester tester, {LatLng at = home}) async {
    await pumpApp(
      tester,
      backend,
      trails: trails,
      settings: settings,
      position: fakePosition(at.latitude, at.longitude),
    );
    await settle(tester, frames: 20);
    fakeMap(tester).move(at, 14);
    await settle(tester, frames: 20);
  }

  LoopSession session(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
  ).read(loopPlannerProvider);

  Future<void> tapKey(WidgetTester tester, String key, {int frames = 8}) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await settle(tester, frames: frames);
  }

  Future<void> openEntry(WidgetTester tester) async {
    await tapKey(tester, 'loop-button', frames: 12);
    expect(find.byKey(const ValueKey('loop-entry')), findsOneWidget);
  }

  ChoiceChip chip(WidgetTester tester, String key) =>
      tester.widget<ChoiceChip>(find.byKey(ValueKey(key)));

  testWidgets(
    'ohne gemerkte Punkte: „Gemerkt" beim Start erklärt und bietet den Standort an',
    (tester) async {
      await start(tester);
      await openEntry(tester);
      expect(chip(tester, 'loop-entry-start-me').selected, isTrue);
      expect(chip(tester, 'loop-entry-start-saved').selected, isFalse);
      // Beim Ziel nur mit Punkten — die leere Liste böte dort nichts an.
      await tester.tap(find.byKey(const ValueKey('loop-entry-route')));
      await settle(tester, frames: 8);
      await tapKey(tester, 'loop-pick-cancel');
      expect(
        find.byKey(const ValueKey('loop-entry-target-saved')),
        findsNothing,
      );

      await tapKey(tester, 'loop-entry-start-saved');
      expect(find.byKey(const ValueKey('start-point-none')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('start-point-remember-here')),
        findsOneWidget,
      );
      await tapKey(tester, 'start-point-remember-here', frames: 12);
      expect(
        find.byKey(const ValueKey('start-point-home-warning')),
        findsOneWidget,
        reason: 'privat, mit Warnung (4)',
      );
    },
  );

  testWidgets(
    'zu Hause: „Mein Standort" bleibt, die Liste wählt — der Name steht im Kopf',
    (tester) async {
      seedPoints();
      await start(tester);
      await openEntry(tester);
      expect(
        chip(tester, 'loop-entry-start-me').selected,
        isTrue,
        reason: '1,1 km weg: keine Vorbelegung (9.4)',
      );
      expect(session(tester).start, isNull);

      await tapKey(tester, 'loop-entry-start-saved');
      // Eigene und fremde, nach Abstand; der fremde trägt den Buddy.
      final own = find.byKey(ValueKey('start-point-choice-$annaId/p-own'));
      final ben = find.byKey(ValueKey('start-point-choice-$benId/p-ben'));
      expect(own, findsOneWidget);
      expect(ben, findsOneWidget);
      expect(
        tester.getTopLeft(own).dy,
        lessThan(tester.getTopLeft(ben).dy),
        reason: 'der nähere oben',
      );
      expect(find.text('1,1 km'), findsOneWidget);
      expect(find.text('2,2 km'), findsOneWidget);
      expect(find.text('von ben'), findsOneWidget);
      expect(find.text('privat'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('start-point-remember-here')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('start-point-none')), findsNothing);

      await tester.tap(ben);
      await settle(tester, frames: 8);
      final s = session(tester);
      expect(s.start, buddyPark);
      expect(s.startSaved, isTrue);
      expect(s.startName, 'Wanderparkplatz Alm');
      expect(chip(tester, 'loop-entry-start-saved').selected, isTrue);
      expect(chip(tester, 'loop-entry-start-map').selected, isFalse);
      expect(
        find.text('Wanderparkplatz Alm'),
        findsOneWidget,
        reason: 'die Wahl trägt den Namen',
      );
      expect(
        settings.lastStartPoint,
        '$benId/p-ben',
        reason: 'zuletzt gewählt (9.4)',
      );

      // In der Bearbeitung heißt der Start wie der Punkt; „Start merken"
      // fehlt an einem gemerkten Start.
      await tapKey(tester, 'loop-entry-self', frames: 10);
      final value = find.byKey(const ValueKey('loop-head-start-value'));
      expect(tester.widget<Text>(value).data, 'Wanderparkplatz Alm');
      await tapKey(tester, 'loop-head-start');
      expect(find.byKey(const ValueKey('loop-start-saved')), findsOneWidget);
      expect(find.byKey(const ValueKey('loop-start-remember')), findsNothing);

      // Ein Tipp auf die Karte ist ein getippter Start ohne Namen.
      await tapKey(tester, 'loop-pick');
      await tapMapAt(tester, home);
      await settle(tester, frames: 8);
      expect(session(tester).startSaved, isFalse);
      expect(session(tester).startName, isNull);
      expect(tester.widget<Text>(value).data, 'Auf der Karte gesetzt');
    },
  );

  testWidgets(
    'der zuletzt gewählte steht oben, auch wenn er weiter weg liegt',
    (tester) async {
      seedPoints();
      settings.lastStartPoint = '$benId/p-ben';
      await start(tester);
      await openEntry(tester);
      await tapKey(tester, 'loop-entry-start-saved');
      final own = find.byKey(ValueKey('start-point-choice-$annaId/p-own'));
      final ben = find.byKey(ValueKey('start-point-choice-$benId/p-ben'));
      expect(tester.getTopLeft(ben).dy, lessThan(tester.getTopLeft(own).dy));
    },
  );

  testWidgets(
    'am Parkplatz (100 m): der Punkt ist schon der Start, ohne „zuletzt gewählt"',
    (tester) async {
      seedPoints();
      await start(tester, at: const LatLng(47.5109, 10.5));
      await openEntry(tester);
      final s = session(tester);
      expect(s.start, carPark);
      expect(s.startSaved, isTrue);
      expect(chip(tester, 'loop-entry-start-saved').selected, isTrue);
      expect(find.text('Parkplatz Talboden'), findsOneWidget);
      expect(
        settings.lastStartPoint,
        isNull,
        reason: 'die Vorbelegung ist keine Wahl',
      );

      // Wer selbst „Mein Standort" wählt, bleibt dabei.
      await tapKey(tester, 'loop-entry-start-me');
      expect(session(tester).start, isNull);
      expect(session(tester).startSaved, isFalse);
    },
  );

  testWidgets('Route: ein gemerkter Punkt als Ziel', (tester) async {
    seedPoints();
    await start(tester);
    await openEntry(tester);
    await tester.tap(find.byKey(const ValueKey('loop-entry-route')));
    await settle(tester, frames: 8);
    // „Route" wartet gleich auf einen Tipp (12.3); abgebrochen kommt das
    // Blatt mit der Liste als anderem Weg.
    await tapKey(tester, 'loop-pick-cancel');
    await tapKey(tester, 'loop-entry-target-saved');
    await tester.tap(find.byKey(ValueKey('start-point-choice-$annaId/p-own')));
    await settle(tester, frames: 20);
    final s = session(tester);
    expect(s.target, carPark);
    expect(s.targetSaved, isTrue);
    expect(s.targetName, 'Parkplatz Talboden');
    expect(s.prefs.endMode, LoopEndMode.target);
    expect(s.pickingTarget, isFalse);
  });

  testWidgets(
    '„Mein Standort merken" ist privat und warnt; „Start merken" am getippten Start nicht',
    (tester) async {
      await start(tester);
      await openEntry(tester);
      await tapKey(tester, 'loop-entry-self', frames: 10);

      // Start am Standort: die Zeile heißt „Mein Standort merken".
      await tapKey(tester, 'loop-head-start');
      expect(find.text('Mein Standort merken'), findsOneWidget);
      await tapKey(tester, 'loop-start-remember');
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('start-point-shared')),
            )
            .value,
        isFalse,
        reason: 'privat vorbelegt (9.1)',
      );
      expect(
        find.byKey(const ValueKey('start-point-home-warning')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('start-point-name')),
        'Garage',
      );
      await settle(tester);
      await tapKey(tester, 'start-point-save', frames: 12);
      expect(trails.startPoints.single.name, 'Garage');
      expect(trails.startPoints.single.visibility, TrailVisibility.private);
      expect(trails.startPoints.single.position, home);

      // Ein getippter Start: „Start merken", Buddys vorbelegt, ohne Warnung.
      await tester.pump(
        const Duration(seconds: 5),
      ); // die Leiste „gemerkt" läge über der letzten Zeile
      await settle(tester);
      await tapKey(tester, 'loop-head-start');
      await tapKey(tester, 'loop-pick');
      await tapMapAt(tester, carPark);
      await settle(tester, frames: 8);
      await tapKey(tester, 'loop-head-start');
      expect(find.text('Start merken'), findsOneWidget);
      await tapKey(tester, 'loop-start-remember');
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('start-point-shared')),
            )
            .value,
        isTrue,
      );
      expect(
        find.byKey(const ValueKey('start-point-home-warning')),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const ValueKey('start-point-name')),
        'Talboden',
      );
      await settle(tester);
      await tapKey(tester, 'start-point-save', frames: 12);
      expect(
        trails.startPoints.map((p) => p.name),
        containsAll(['Garage', 'Talboden']),
      );
      final talboden = trails.startPoints.firstWhere(
        (p) => p.name == 'Talboden',
      );
      expect(talboden.visibility, TrailVisibility.buddies);
      expect(talboden.lat, closeTo(carPark.latitude, 1e-4));
    },
  );
}
