// Die Wiedervorlage (#30): Reihenfolge, Abbruch ohne Netz, Zähler und
// endgültige Ablehnung — gegen das Fake-Repository, ohne Riverpod.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:trailbuddy/core/errors.dart';
import 'package:trailbuddy/data/outbox.dart';
import 'package:trailbuddy/data/outbox_runner.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_outbox.dart';
import '../fakes/fake_trails.dart';

/// [n] Punkte nach Norden, 100 m Abstand — lang genug für einen Trail.
List<double> line(int n, {double lon = 11.0}) =>
    [for (var i = 0; i < n; i++) ...[lon, 47.0 + i * 100 / 111195.0]];

void main() {
  final at = DateTime.utc(2026, 9, 28, 12);
  late FakeTrailRepository repo;
  late FakeOutbox box;
  late List<(String, String, int?, Set<TrailTrait>)> adopted;
  late OutboxRunner runner;

  ContributeJob job(String id,
          {List<double>? coords, String? name, Set<TrailTrait> traits = const {}}) =>
      ContributeJob(
      id: id,
      createdAt: at,
      coords: coords ?? line(5),
      source: RecordingSource.import,
      recordedAt: at,
      name: name ?? 'Trail $id',
      traits: traits);

  setUp(() {
    repo = FakeTrailRepository(myId: () => 'me');
    box = FakeOutbox();
    adopted = [];
    runner = OutboxRunner(
        repository: repo,
        outbox: box,
        adoptDetails: (trailId, name, grade, traits, link, rating) async =>
            adopted.add((trailId, name, grade, traits)));
  });

  test('sendet der Reihe nach, übernimmt den Namen, räumt den Korb', () async {
    await box.append(job('a'), uid: 'me');
    await box.append(job('b', coords: line(5, lon: 11.5), name: '  '), uid: 'me');
    final r = await runner.run(uid: 'me');
    expect(r, (sent: 2, remaining: 0, failed: 0));
    expect(repo.recordings.map((x) => x.id), ['rec-a', 'rec-b']);
    expect(adopted, [(repo.recordings.first.trailId, 'Trail a', null, const <TrailTrait>{})],
        reason: 'ein leerer Name wird nicht übernommen');
    expect(box.jobs, isEmpty);
    expect(box.replaces, 1, reason: 'EIN Schreibvorgang am Ende');
  });

  test('ohne Namen, aber mit Charakter: der Charakter wird trotzdem übernommen', () async {
    await box.append(job('c', name: '', traits: {TrailTrait.jumps}), uid: 'me');
    await runner.run(uid: 'me');
    expect(adopted.single.$4, {TrailTrait.jumps});
  });

  test('Beitrag von vor 0.49.0 samt Status und Hinweis', () async {
    // Der Trail muss sichtbar sein, sonst lehnt die RLS den Hinweis ab.
    final trailId = await repo.contribute(
        coords: line(5), source: RecordingSource.import, clientId: 'seed');
    await box.append(
        DetailsJob(
            id: 'd',
            createdAt: at,
            details: TrailDetails(trailId: trailId, userId: 'me', grade: 4),
            legacyStatus: TrailStatus.closed,
            legacyStatusAt: at,
            note: 'Baum quer'),
        uid: 'me');
    final r = await runner.run(uid: 'me');
    expect(r.sent, 1);
    expect(repo.details.singleWhere((d) => d.trailId == trailId).grade, 4);
    final report = repo.reports.single;
    expect(report.status, TrailStatus.closed);
    expect(report.reportedAt.toUtc(), at, reason: 'zur Zeit von damals, nicht zur Sendezeit');
    expect(repo.notes.single.body, 'Baum quer');
  });

  test('Meldung: geht mit der Zeit des Meldens raus, zweimal gesendet bleibt eine', () async {
    final trailId = await repo.contribute(
        coords: line(5), source: RecordingSource.import, clientId: 'seed');
    final job = ReportJob(
        id: 'r', createdAt: at, trailId: trailId, condition: 2, onSite: false, note: 'Wurzeln frei');
    await box.append(job, uid: 'me');
    expect((await runner.run(uid: 'me')).sent, 1);
    // Ein Abriss nach dem Senden: derselbe Auftrag noch einmal.
    await box.append(job, uid: 'me');
    await runner.run(uid: 'me');
    expect(repo.reports.where((r) => r.condition == 2), hasLength(1),
        reason: 'dieselbe client_id legt keine zweite Meldung an');
    expect(repo.reports.single.reportedAt.toUtc(), at);
    expect(repo.reports.single.confirmed, isTrue, reason: 'gefahren (Import mit Zeiten)');
  });


  test('kein Netz: Lauf endet, nichts gilt als gescheitert, Reihenfolge bleibt', () async {
    await box.append(job('a'), uid: 'me');
    await box.append(job('b', coords: line(5, lon: 11.5)), uid: 'me');
    repo.failNextContribute = const SocketException('offline');
    final r = await runner.run(uid: 'me');
    expect(r, (sent: 0, remaining: 2, failed: 0));
    expect(box.jobs.map((j) => j.id), ['a', 'b']);
    expect(box.jobs.every((j) => j.attempts == 0), isTrue);
    expect(repo.contributeCalls, 1, reason: 'nach dem Netzfehler wird nichts mehr versucht');
  });

  test('Tageslimit: wie kein Netz — morgen wieder', () async {
    await box.append(job('a'), uid: 'me');
    repo.failNextContribute = const DailyLimitException();
    final r = await runner.run(uid: 'me');
    expect(r, (sent: 0, remaining: 1, failed: 0));
    expect(box.jobs.single.attempts, 0);
  });

  test('Ablehnung des Servers ist endgültig; ein anderer Fehler zählt', () async {
    await box.append(job('a'), uid: 'me');
    await box.append(job('b', coords: line(5, lon: 11.5)), uid: 'me');
    repo.failNextContribute = const PostgrestException(message: 'nein', code: '42501');
    var r = await runner.run(uid: 'me');
    expect(r, (sent: 1, remaining: 1, failed: 1));
    expect(box.jobs.single.id, 'a');
    expect(box.jobs.single.failure, isNotNull);

    // Abgelehnte werden nicht mehr versucht.
    r = await runner.run(uid: 'me');
    expect(r, (sent: 0, remaining: 1, failed: 1));
    expect(repo.contributeCalls, 2);

    // Ein Fehler, der nicht eindeutig endgültig ist (zu kurze Linie im
    // Fake ist ein StateError): zählen, bis der Zähler voll ist.
    await box.append(job('c', coords: const [11.0, 47.0, 11.0, 47.0003]), uid: 'me'); // 33 m
    for (var i = 1; i <= OutboxRunner.maxAttempts; i++) {
      await runner.run(uid: 'me');
      final c = box.jobs.singleWhere((j) => j.id == 'c');
      expect(c.attempts, i);
      expect(c.failure, i < OutboxRunner.maxAttempts ? isNull : isNotNull);
    }
  });

  test('ein zweiter Lauf während des ersten tut nichts', () async {
    await box.append(job('a'), uid: 'me');
    final first = runner.run(uid: 'me');
    final second = await runner.run(uid: 'me');
    expect(second, (sent: 0, remaining: 0, failed: 0));
    expect((await first).sent, 1);
  });
}
