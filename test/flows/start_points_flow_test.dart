// Gemerkte Startpunkte im Notifier (#543, Schritt 1 — noch ohne
// Oberfläche): Merken steht sofort da und liest nur die Startpunkte nach,
// nicht das Netz; ohne Netz wartet es im Ausgangskorb und geht danach
// hinaus; die Obergrenze sagt es, bevor etwas wartet; und am Parkplatz
// ohne Empfang kommt die Liste aus der Kopie (A8).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/errors.dart';
import 'package:trailbuddy/data/outbox.dart';
import 'package:trailbuddy/features/trails/trail_providers.dart';
import 'package:trailbuddy/models/start_point.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_outbox.dart';
import '../fakes/fake_trail_cache.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late String annaId;
  late FakeTrailRepository trails;
  late FakeTrailCache cache;
  late FakeOutbox outbox;

  setUp(() {
    backend = FakeBackend();
    annaId = backend.addUser(username: 'anna').id;
    backend.signInAs(annaId);
    trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '');
    trails.seedTrail(annaId, name: 'Roots');
    cache = FakeTrailCache();
    outbox = FakeOutbox();
  });

  StartPoint parking(String clientId, {String name = 'Parkplatz Talboden'}) => StartPoint(
      clientId: clientId, userId: annaId, name: name, lat: 47.5, lon: 10.5, createdAt: DateTime.utc(2026, 11, 16));

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp).first));

  Future<ProviderContainer> start(WidgetTester tester) async {
    await pumpApp(tester, backend, trails: trails, trailCache: cache, outbox: outbox);
    await settle(tester, frames: 12);
    return containerOf(tester);
  }

  testWidgets('merken: sofort da, nachgelesen werden nur die Startpunkte', (tester) async {
    final c = await start(tester);
    expect(c.read(startPointsProvider), isEmpty);
    final lines = trails.recordingFetches;
    final points = trails.startPointFetches;

    final outcome = await tester.runAsync(
        () => c.read(trailsProvider.notifier).saveStartPoint(parking('p1', name: '  Parkplatz Talboden  ')));
    await settle(tester, frames: 6);
    expect(outcome, WriteOutcome.done);
    expect(trails.startPoints.single.name, 'Parkplatz Talboden', reason: 'gekürzt wie in der Datenbank');
    final shown = c.read(startPointsProvider).single;
    expect((shown.key, shown.pending), ('$annaId/p1', false));
    expect(trails.recordingFetches, lines, reason: 'ein Startpunkt ändert keine Linie');
    expect(trails.startPointFetches, points + 1);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(cache.snapshot!.startPoints.single.name, 'Parkplatz Talboden',
        reason: 'die Kopie trägt ihn mit — am Parkplatz ohne Empfang');

    await tester.runAsync(() => c.read(trailsProvider.notifier).deleteStartPoint('p1'));
    await settle(tester, frames: 6);
    expect(trails.startPoints, isEmpty);
    expect(c.read(startPointsProvider), isEmpty);
  });

  testWidgets('ohne Netz: wartet sichtbar im Korb und geht danach hinaus', (tester) async {
    final c = await start(tester);
    trails.failNextStartPointWrite = const SocketException('offline');
    final outcome = await tester.runAsync(() => c.read(trailsProvider.notifier).saveStartPoint(parking('p1')));
    await settle(tester, frames: 6);
    expect(outcome, WriteOutcome.queued);
    expect(trails.startPoints, isEmpty);
    expect((outbox.jobs.single as StartPointJob).point.clientId, 'p1');
    expect(c.read(startPointsProvider).single.pending, isTrue, reason: 'steht schon da, als wartend');

    final lines = trails.recordingFetches;
    final result = await tester.runAsync(() => c.read(trailsProvider.notifier).sendOutbox());
    await settle(tester, frames: 6);
    expect(result?.sent, 1);
    expect(outbox.jobs, isEmpty);
    expect(trails.startPoints.single.clientId, 'p1');
    expect(c.read(startPointsProvider).single.pending, isFalse);
    expect(trails.recordingFetches, lines, reason: 'nach einem Startpunkt kein ganzes Neuladen');
  });

  testWidgets('die Obergrenze sagt es, bevor ein Auftrag wartet', (tester) async {
    for (var i = 0; i < kStartPointMax; i++) {
      trails.startPoints.add(parking('voll$i', name: 'P$i'));
    }
    final c = await start(tester);
    expect(c.read(startPointsProvider), hasLength(kStartPointMax));
    trails.failNextStartPointWrite = const SocketException('offline');
    final error = await tester.runAsync(() async {
      try {
        await c.read(trailsProvider.notifier).saveStartPoint(parking('neu'));
        return null;
      } catch (e) {
        return e;
      }
    });
    expect(error, isA<StartPointLimitException>());
    expect(outbox.jobs, isEmpty, reason: 'kein Auftrag, den der Server sicher ablehnt');
    // Umbenennen geht auch am Limit.
    trails.failNextStartPointWrite = null;
    await tester.runAsync(() => c.read(trailsProvider.notifier).saveStartPoint(parking('voll0', name: 'Neu')));
    expect(trails.startPoints.first.name, 'Neu');
  });

  testWidgets('Kaltstart ohne Empfang: die Startpunkte aus der Kopie', (tester) async {
    trails.startPoints.add(parking('p1'));
    await start(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(cache.snapshot!.startPoints, hasLength(1));

    await tester.pumpWidget(const SizedBox());
    final backend2 = FakeBackend();
    final anna = backend2.addUser(username: 'anna');
    backend2.signInAs(anna.id);
    cache.uid = anna.id;
    trails = FakeTrailRepository(myId: () => backend2.currentUserId ?? '')
      ..failFetch = const SocketException('offline');
    await pumpApp(tester, backend2, trails: trails, trailCache: cache, outbox: outbox);
    await settle(tester, frames: 12);
    final shown = containerOf(tester).read(startPointsProvider);
    expect(shown.map((p) => p.name), ['Parkplatz Talboden']);
    expect(shown.single.visibility, TrailVisibility.buddies);
  });
}
