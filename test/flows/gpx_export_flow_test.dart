// GPX hinaus (#150), durch die echte Oberfläche: der Trail aus dem Blatt
// (in Trail-Richtung, mit den Höhen der besten Aufzeichnung, nur der
// eigene Link, keine Buddy-Namen), die Fahrt aus „Meine Fahrten" (ganz,
// mit roher Höhe). Das Teilen-Blatt ist über `gpxShareProvider` ein
// Recorder; im Browser-Fall sagt die App, dass heruntergeladen wird.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/gpx_share.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/features/trails/gpx.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_rides.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late String annaId, bobId;
  late List<({String fileName, String xml})> shared;
  var outcome = GpxShareOutcome.shared;

  Future<GpxShareOutcome> recorder({
    required String fileName,
    required String xml,
  }) async {
    shared.add((fileName: fileName, xml: xml));
    return outcome;
  }

  setUp(() {
    shared = [];
    outcome = GpxShareOutcome.shared;
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    final bob = backend.addUser(username: 'bobby');
    backend.addFriendship(anna.id, bob.id);
    backend.signInAs(anna.id);
    annaId = anna.id;
    bobId = bob.id;
    trails = FakeTrailRepository(
      myId: () => backend.currentUserId ?? '',
      areFriends: backend.areFriends,
    );
    trails.usernames[bob.id] = 'bobby';
  });

  Future<void> openSheet(
    WidgetTester tester,
    String name, {
    FakeRideStore? store,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(
      tester,
      backend,
      trails: trails,
      rideStore: store,
      extraOverrides: [gpxShareProvider.overrideWithValue(recorder)],
    );
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    await tester.tap(find.text(name));
    await settle(tester);
  }

  testWidgets(
    'Trail: in Trail-Richtung, Höhen der besten Linie, nur der eigene Link',
    (tester) async {
      // Bobs Aufzeichnung ist die beste und lief GEGEN die Richtung; Annas
      // Beitrag trägt den eigenen Link, Bobs einen anderen.
      final id = trails.seedTrail(
        bobId,
        name: 'Rosskopf Süd',
        lat: 7.0,
        quality: 0.9,
        ele: [900, 700, 480],
        reversed: true,
        link: 'https://www.bob.example/x',
      );
      trails.seedTrail(
        annaId,
        trailId: id,
        lat: 7.0,
        quality: 0.3,
        link: 'https://www.anna.example/roots',
      );
      await openSheet(tester, 'Rosskopf Süd');
      await tester.ensureVisible(find.byKey(const ValueKey('trail-export')));
      await tester.tap(find.byKey(const ValueKey('trail-export')));
      await settle(tester);

      expect(shared, hasLength(1));
      expect(shared.single.fileName, 'trailbuddy-rosskopf-sued.gpx');
      final track = parseGpx(shared.single.xml).single;
      expect(track.name, 'Rosskopf Süd');
      expect(track.link, 'https://www.anna.example/roots');
      // Gespeichert ist 7.0 → 7.009 mit 900 → 480; in Trail-Richtung umgekehrt.
      expect(track.points.map((p) => p.lat), [
        closeTo(7.009, 1e-6),
        closeTo(7.005, 1e-6),
        closeTo(7.0, 1e-6),
      ]);
      expect(track.points.map((p) => p.ele), [480, 700, 900]);
      expect(
        shared.single.xml,
        isNot(contains('bobby')),
        reason: 'kein Buddy-Name in der Datei',
      );
      expect(shared.single.xml, isNot(contains('bob.example')));
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'Fahrt: ganz, mit roher Höhe; im Browser sagt die App „wird heruntergeladen"',
    (tester) async {
      final t0 = DateTime.utc(2026, 9, 28, 9, 0);
      final store = FakeRideStore()..uid = annaId;
      store.rides.add(
        Ride(
          id: '20260928T090000Z',
          startedAt: t0,
          endedAt: t0.add(const Duration(minutes: 40)),
          points: [
            for (var i = 0; i < 3; i++)
              RidePoint(
                lat: 7.0 + i * 0.001,
                lng: 9.0,
                at: t0.add(Duration(seconds: 5 * i)),
                accuracyM: 8,
                altM: 600.0 + i,
              ),
          ],
        ),
      );
      outcome = GpxShareOutcome.downloaded;
      await pumpApp(
        tester,
        backend,
        trails: trails,
        rideStore: store,
        extraOverrides: [gpxShareProvider.overrideWithValue(recorder)],
      );
      await openProfilePage(tester, 'rides');
      await settle(tester);
      await tester.tap(find.byTooltip('Mehr'));
      await settle(tester);
      await tester.tap(find.text('Als GPX exportieren'));
      await settle(tester);

      expect(shared, hasLength(1));
      expect(shared.single.fileName, 'trailbuddy-fahrt-20260928t090000z.gpx');
      final track = parseGpx(shared.single.xml).single;
      expect(track.points.length, 3);
      expect(track.points.map((p) => p.ele), [600, 601, 602]);
      expect(track.points.first.time, t0);
      expect(find.textContaining('wird heruntergeladen'), findsOneWidget);
    },
  );
}
