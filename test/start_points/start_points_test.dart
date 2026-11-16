// Gemerkte Startpunkte (#543, Schritt 1): die Aufträge im Korb, die
// Wiedervorlage, die Anzeige samt wartender Aufträge und die Sichtregel
// des Fakes (Spiegel von `sp_select`, Patch 030). Erfundene Koordinaten
// (A7). Die echte RLS prüft `tool/matcher_check.sql` Block 33.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/data/outbox.dart';
import 'package:trailbuddy/data/outbox_runner.dart';
import 'package:trailbuddy/features/trails/outbox_providers.dart';
import 'package:trailbuddy/models/start_point.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_outbox.dart';
import '../fakes/fake_trails.dart';

void main() {
  final at = DateTime.utc(2026, 11, 16, 9);

  StartPoint point(String clientId,
          {String userId = 'me', String name = 'Parkplatz', TrailVisibility vis = TrailVisibility.buddies}) =>
      StartPoint(
          clientId: clientId, userId: userId, name: name, lat: 47.5, lon: 10.5, visibility: vis, createdAt: at);

  group('Ausgangskorb', () {
    test('beide Auftragsarten überstehen die Ablage', () {
      final jobs = [
        StartPointJob(id: 'j1', createdAt: at, point: point('p1', name: 'Talboden', vis: TrailVisibility.private)),
        StartPointDeleteJob(id: 'j2', createdAt: at, clientId: 'p1', attempts: 2, failure: 'nein'),
      ];
      final back = decodeOutbox(encodeOutbox(jobs, uid: 'me'), uid: 'me');
      final save = back[0] as StartPointJob;
      expect(save.id, 'j1');
      expect(save.point.clientId, 'p1');
      expect(save.point.userId, 'me');
      expect(save.point.name, 'Talboden');
      expect((save.point.lat, save.point.lon), (47.5, 10.5));
      expect(save.point.visibility, TrailVisibility.private);
      expect(save.point.pending, isFalse);
      final del = back[1] as StartPointDeleteJob;
      expect((del.clientId, del.attempts, del.failure), ('p1', 2, 'nein'));
      expect(isTrailJob(save) || isTrailJob(del), isFalse);
    });

    test('ein Startpunkt-Auftrag ohne Punkt fällt einzeln weg', () {
      final text = encodeOutbox([StartPointDeleteJob(id: 'ok', createdAt: at, clientId: 'p1')], uid: 'me')
          .replaceFirst('"jobs":[', '"jobs":[{"kind":"start_point","id":"x","created_at":"2026-11-16T09:00:00Z","point":{"name":""}},');
      final back = decodeOutbox(text, uid: 'me');
      expect(back.map((j) => j.id), ['ok']);
    });
  });

  group('Wiedervorlage', () {
    late FakeTrailRepository repo;
    late FakeOutbox box;
    late OutboxRunner runner;

    setUp(() {
      repo = FakeTrailRepository(myId: () => 'me');
      box = FakeOutbox();
      final backend = FakeBackend()..signInAs('me');
      runner = OutboxRunner(
          repository: repo,
          feedback: FakeFeedbackRepository(backend),
          outbox: box,
          adoptDetails: (_, _, _, _, _, _) async {});
    });

    test('anlegen, umbenennen, löschen — der Reihe nach, und zweimal ist einmal', () async {
      await box.append(StartPointJob(id: 'a', createdAt: at, point: point('p1', name: 'Erst')), uid: 'me');
      await box.append(StartPointJob(id: 'b', createdAt: at, point: point('p1', name: 'Dann')), uid: 'me');
      await box.append(StartPointJob(id: 'c', createdAt: at, point: point('p2')), uid: 'me');
      await box.append(StartPointDeleteJob(id: 'd', createdAt: at, clientId: 'p2'), uid: 'me');
      expect(await runner.run(uid: 'me'), (sent: 4, remaining: 0, failed: 0));
      expect(repo.startPoints.map((p) => (p.clientId, p.name)), [('p1', 'Dann')]);
      // Ein Abriss nach dem Schreiben: derselbe Auftrag noch einmal legt nichts doppelt an.
      await box.append(StartPointJob(id: 'b', createdAt: at, point: point('p1', name: 'Dann')), uid: 'me');
      await box.append(StartPointDeleteJob(id: 'd', createdAt: at, clientId: 'p2'), uid: 'me');
      expect(await runner.run(uid: 'me'), (sent: 2, remaining: 0, failed: 0));
      expect(repo.startPoints, hasLength(1));
    });

    test('ohne Netz bleibt der Auftrag, das Limit lehnt endgültig ab', () async {
      repo.failNextStartPointWrite = const SocketException('offline');
      await box.append(StartPointJob(id: 'a', createdAt: at, point: point('p1')), uid: 'me');
      expect(await runner.run(uid: 'me'), (sent: 0, remaining: 1, failed: 0));
      expect(box.jobs.single.attempts, 0, reason: 'kein Netz zählt nicht');

      for (var i = 0; i < kStartPointMax; i++) {
        repo.startPoints.add(point('voll$i'));
      }
      expect(await runner.run(uid: 'me'), (sent: 0, remaining: 1, failed: 1));
      expect(box.jobs.single.failure, contains('100'),
          reason: 'ein Satz statt eines Fehlercodes (Konzept 9.2)');
    });
  });

  group('Anzeige mit dem Korb', () {
    // Bobs Punkt mit DERSELBEN client_id zuerst: Die Kennung ist nur je
    // Konto eindeutig, ein Auftrag trifft nur den eigenen.
    final server = [point('p1', userId: 'bob', name: 'Bobs Platz'), point('p1', name: 'Talboden')];

    test('ohne Startpunkt-Aufträge dieselbe Liste', () {
      final feedbackOnly = <OutboxJob>[];
      expect(withPendingStartPoints(server, feedbackOnly, myId: 'me'), same(server));
    });

    test('anlegen, ändern, löschen stehen sofort da — nur am EIGENEN Punkt', () {
      final shown = withPendingStartPoints(server, [
        StartPointJob(id: 'a', createdAt: at, point: point('p2', name: 'Neu')),
        StartPointJob(id: 'b', createdAt: at, point: point('p1', name: 'Umbenannt')),
        StartPointDeleteJob(id: 'c', createdAt: at, clientId: 'p2'),
        StartPointJob(id: 'e', createdAt: at, point: point('p3', name: 'Abgelehnt')).copyWith(failure: 'nein'),
      ], myId: 'me', sending: {'b'});
      expect(shown.map((p) => (p.key, p.name, p.pending, p.sending)), [
        ('bob/p1', 'Bobs Platz', false, false),
        ('me/p1', 'Umbenannt', true, true),
      ]);
    });
  });

  group('Sichtregel des Fakes (sp_select)', () {
    test('eigene, geteilte von Buddys; private und Fremde nicht', () async {
      final friends = {('me', 'bob')};
      final repo = FakeTrailRepository(
          myId: () => 'me', areFriends: (a, b) => friends.contains((a, b)) || friends.contains((b, a)))
        ..usernames['bob'] = 'bob';
      repo.startPoints.addAll([
        point('p1', vis: TrailVisibility.private),
        point('b1', userId: 'bob'),
        point('b2', userId: 'bob', vis: TrailVisibility.private),
        point('g1', userId: 'gina'),
      ]);
      final seen = await repo.fetchStartPoints();
      expect(seen.map((p) => p.key), ['me/p1', 'bob/b1']);
      expect(seen[1].username, 'bob');
      friends.clear();
      expect((await repo.fetchStartPoints()).map((p) => p.key), ['me/p1'],
          reason: 'nach dem Entfreunden sofort nichts mehr');
    });

    test('Buddys können fremde Punkte weder ändern noch löschen', () async {
      final repo = FakeTrailRepository(myId: () => 'bob');
      repo.startPoints.add(point('p1'));
      await repo.deleteStartPoint('p1');
      await repo.saveStartPoint(point('p1', name: 'Übernommen'));
      expect(repo.startPoints.map((p) => p.key), ['me/p1', 'bob/p1'],
          reason: 'ein Upsert legt Bob einen EIGENEN Punkt an');
      expect(repo.startPoints.first.name, 'Parkplatz');
    });
  });

  test('Namen kürzt das Gerät wie die Datenbank, in Codepunkten', () {
    expect(clampStartPointName('  Parkplatz  '), 'Parkplatz');
    expect(clampStartPointName('   '), '');
    final long = '${'a' * 59}🚲🚲';
    expect(clampStartPointName(long), '${'a' * 59}🚲');
    expect(clampStartPointName(long).runes.length, kStartPointNameMaxLength);
  });
}
