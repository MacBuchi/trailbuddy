// Der Charakter aus dem Zerlege-Blatt (#72) auf allen Wegen in den
// eigenen Beitrag: direkt, über den Ausgangskorb, und ohne je eine
// eigene Angabe wegzunehmen.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/data/outbox.dart';
import 'package:trailbuddy/features/trails/gpx.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/features/trails/trail_providers.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_outbox.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

/// 1 200 m nach Norden, mit Zeiten — eine eigene Aufzeichnung.
GpxTrack track(String name) => GpxTrack(
  name: name,
  points: [
    for (var i = 0; i <= 60; i++)
      TrackPoint(
        48.0 + i * 20 / 111320.0,
        9.0,
        time: DateTime.utc(2026, 5, 1, 10).add(Duration(seconds: i * 4)),
      ),
  ],
);

void main() {
  late FakeBackend backend;
  late String annaId;
  late FakeTrailRepository trails;
  late FakeOutbox outbox;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    annaId = anna.id;
    trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '');
    outbox = FakeOutbox();
  });

  Future<ProviderContainer> start(WidgetTester tester) async {
    await pumpApp(tester, backend, trails: trails, outbox: outbox);
    await settle(tester, frames: 20);
    return ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
  }

  testWidgets(
    'ohne Netz reist der Charakter im Auftrag mit und kommt beim Nachholen an',
    (tester) async {
      final c = await start(tester);
      trails.failNextContribute = const SocketException('offline');
      late ContributeResult r;
      await tester.runAsync(() async {
        r = await c
            .read(trailsProvider.notifier)
            .contribute(
              track('Neue Linie'),
              source: RecordingSource.app,
              grade: 2,
              traits: {TrailTrait.flowy, TrailTrait.jumps},
            );
      });
      expect(r.queued, isTrue);
      final job = outbox.jobs.single as ContributeJob;
      expect(job.traits, {TrailTrait.flowy, TrailTrait.jumps});

      await tester.runAsync(() => c.read(trailsProvider.notifier).sendOutbox());
      await settle(tester, frames: 20);
      final mine = trails.details.singleWhere((d) => d.userId == annaId);
      expect(mine.name, 'Neue Linie');
      expect(mine.grade, 2);
      expect(mine.traits, {TrailTrait.flowy, TrailTrait.jumps});
    },
  );

  testWidgets('die Merkmale kommen dazu, eine eigene Angabe bleibt', (
    tester,
  ) async {
    final id = trails.seedTrail(
      annaId,
      name: 'Roots',
      traits: {TrailTrait.rocky},
    );
    final c = await start(tester);
    late bool wrote;
    await tester.runAsync(() async {
      wrote = await c
          .read(trailsProvider.notifier)
          .adoptDetails(id, 'anderer Name', traits: {TrailTrait.steep});
    });
    expect(wrote, isTrue);
    final mine = trails.details.singleWhere((d) => d.userId == annaId);
    expect(mine.traits, {TrailTrait.rocky, TrailTrait.steep});
    expect(mine.name, 'Roots', reason: 'ein eigener Name bleibt ohnehin');

    // Nichts Neues: kein Schreibvorgang.
    await tester.runAsync(() async {
      await c.read(trailsProvider.notifier).reloadAfterWrite('test');
      wrote = await c
          .read(trailsProvider.notifier)
          .adoptDetails(id, '', traits: {TrailTrait.rocky});
    });
    expect(wrote, isFalse);
  });
}
