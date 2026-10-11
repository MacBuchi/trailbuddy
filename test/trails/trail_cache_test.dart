// Die Kopie des Netzes (#32): Rundlauf Feld für Feld, fremdes Konto,
// Datei über `.part` + `rename` — und die Regel „nur ohne Empfang".
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/data/trail_cache.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/trail.dart';
import 'package:trailbuddy/models/trail_merge.dart';

import '../fakes/fake_trail_cache.dart';

void main() {
  final at = DateTime.utc(2026, 9, 28, 10);
  final recording = TrailRecording(
    id: 'rec-1',
    trailId: 'trail-1',
    userId: 'me',
    source: RecordingSource.app,
    recordedAt: at.subtract(const Duration(days: 2)).toLocal(),
    reversed: true,
    quality: 0.6,
    createdAt: at.toLocal(),
    points: const [LatLng(47.0, 11.0), LatLng(47.001, 11.001), LatLng(47.002, 11.0)],
    lengthM: 250.5,
    ele: const [900, 890, 880],
  );
  final noEle = TrailRecording(
    id: 'rec-2', trailId: 'trail-1', userId: 'bob', source: RecordingSource.planned,
    recordedAt: null, reversed: false, quality: 0.1, createdAt: at.toLocal(),
    points: const [LatLng(47.0, 11.0), LatLng(47.001, 11.001)], lengthM: 140,
  );
  final details = TrailDetails(
    trailId: 'trail-1', userId: 'bob', username: 'bob', name: 'Roots',
    description: 'wurzelig', grade: 3, traits: const {TrailTrait.rocky, TrailTrait.steep},
    rating: 4, twoWay: true, link: 'https://verein.example/roots',
    visibility: TrailVisibility.buddies, updatedAt: at.toLocal(),
  );
  final note = TrailNote(
      id: 'note-1', trailId: 'trail-1', userId: 'bob', body: 'Baum quer',
      createdAt: at.toLocal(), username: 'bob');
  final statusReport = TrailReport(
      id: 'rep-1', trailId: 'trail-1', userId: 'bob', kind: ReportKind.status,
      status: TrailStatus.closed, confirmed: true, reportedAt: at.toLocal(), username: 'bob');
  final conditionReport = TrailReport(
      id: 'rep-2', trailId: 'trail-1', userId: 'carla', kind: ReportKind.condition,
      condition: 2, confirmed: false, reportedAt: at.toLocal());
  final snapshot = (
    recordings: [recording, noEle],
    details: [details],
    notes: [note],
    reports: [statusReport, conditionReport],
    merges: [
      const TrailMerge(trailId: 'trail-2', sameAs: 'trail-1', kind: TrailMergeKind.folded,
          reversed: true, byUsers: ['bob', 'carla']),
      const TrailMerge(trailId: 'trail-1', sameAs: 'trail-3', kind: TrailMergeKind.distinct),
    ],
  );

  test('Rundlauf: die Kopie liest sich wie das Netz', () {
    final back = decodeTrailCache(encodeTrailCache(uid: 'me', snapshot: snapshot, savedAt: at), uid: 'me')!;
    expect(back.savedAt, at.toLocal());
    final r = back.snapshot.recordings[0];
    expect(r.id, 'rec-1');
    expect(r.trailId, 'trail-1');
    expect(r.userId, 'me');
    expect(r.source, RecordingSource.app);
    expect(r.recordedAt, recording.recordedAt);
    expect(r.reversed, isTrue);
    expect(r.quality, 0.6);
    expect(r.createdAt, recording.createdAt);
    expect(r.points, recording.points);
    expect(r.lengthM, 250.5);
    expect(r.ele, [900, 890, 880]);
    final r2 = back.snapshot.recordings[1];
    expect(r2.recordedAt, isNull);
    expect(r2.ele, isNull);
    expect(r2.source, RecordingSource.planned);
    final d = back.snapshot.details.single;
    expect(d.username, 'bob');
    expect(d.name, 'Roots');
    expect(d.description, 'wurzelig');
    expect(d.grade, 3);
    expect(d.traits, {TrailTrait.rocky, TrailTrait.steep});
    expect(d.link, 'https://verein.example/roots');
    expect(d.rating, 4);
    expect(d.twoWay, isTrue);
    expect(d.updatedAt, details.updatedAt);
    final s1 = back.snapshot.reports[0];
    expect(s1.id, 'rep-1');
    expect(s1.kind, ReportKind.status);
    expect(s1.status, TrailStatus.closed);
    expect(s1.confirmed, isTrue);
    expect(s1.reportedAt, statusReport.reportedAt);
    expect(s1.username, 'bob');
    final s2 = back.snapshot.reports[1];
    expect(s2.kind, ReportKind.condition);
    expect(s2.condition, 2);
    expect(s2.confirmed, isFalse);
    expect(s2.username, isNull);
    final n = back.snapshot.notes.single;
    expect(n.body, 'Baum quer');
    expect(n.username, 'bob');
    expect(n.createdAt, note.createdAt);
    // Die Zuordnungen von Duplikaten (#107): ohne sie stünde ein
    // zusammengeführter Trail ohne Empfang wieder doppelt da.
    final m1 = back.snapshot.merges[0];
    expect(m1.trailId, 'trail-2');
    expect(m1.sameAs, 'trail-1');
    expect(m1.kind, TrailMergeKind.folded);
    expect(m1.reversed, isTrue);
    expect(m1.byUsers, ['bob', 'carla']);
    final m2 = back.snapshot.merges[1];
    expect(m2.kind, TrailMergeKind.distinct);
    expect(m2.reversed, isFalse);
    expect(m2.byUsers, isEmpty);
  });

  test('eine Kopie von vor 0.109.0 (ohne Zuordnungen) liest sich ohne Zuordnungen', () {
    final text = encodeTrailCache(uid: 'me', snapshot: snapshot, savedAt: at)
        .replaceAll(RegExp(r',"merges":\[.*\]\}$'), '}');
    expect(text, isNot(contains('merges')));
    final back = decodeTrailCache(text, uid: 'me')!;
    expect(back.snapshot.merges, isEmpty);
    expect(back.snapshot.reports, hasLength(2));
  });

  test('eine Kopie von vor 0.49.0 (ohne Meldungen) liest sich ohne Meldungen', () {
    final text = encodeTrailCache(uid: 'me', snapshot: snapshot, savedAt: at)
        .replaceAll(RegExp(r',"reports":\[.*\]\}$'), '}');
    expect(text, isNot(contains('reports')));
    final back = decodeTrailCache(text, uid: 'me')!;
    expect(back.snapshot.reports, isEmpty);
    expect(back.snapshot.details.single.name, 'Roots');
  });

  test('fremdes Konto und Unlesbares ergeben keine Kopie', () {
    final text = encodeTrailCache(uid: 'me', snapshot: snapshot, savedAt: at);
    expect(decodeTrailCache(text, uid: 'someone'), isNull);
    expect(decodeTrailCache('kaputt', uid: 'me'), isNull);
    expect(decodeTrailCache('{"uid":"me"}', uid: 'me'), isNull);
  });

  test('in Häppchen geschrieben ist es derselbe Text (Feldbericht 2026-10-02)', () async {
    final whole = encodeTrailCache(uid: 'me', snapshot: snapshot, savedAt: at);
    // Ohne Rechenzeit je Häppchen gibt es nach JEDER Linie den Haupt-Thread frei.
    expect(await encodeTrailCacheInSlices(uid: 'me', snapshot: snapshot, savedAt: at, slice: Duration.zero), whole);
    expect(await encodeTrailCacheInSlices(uid: 'me', snapshot: snapshot, savedAt: at), whole);
  });

  group('FileTrailCache', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('trail_cache_'));
    tearDown(() async => dir.delete(recursive: true));

    test('schreiben, lesen, löschen — keine .part bleibt liegen', () async {
      final cache = FileTrailCache(baseDir: dir);
      expect(await cache.read(uid: 'me'), isNull);
      await cache.write(uid: 'me', snapshot: snapshot, savedAt: at);
      final back = await FileTrailCache(baseDir: dir).read(uid: 'me');
      expect(back!.snapshot.recordings, hasLength(2));
      expect(await cache.read(uid: 'someone'), isNull);
      final files = dir.listSync(recursive: true).map((f) => f.path).toList();
      expect(files.where((p) => p.endsWith('.part')), isEmpty);
      await cache.clear();
      expect(await cache.read(uid: 'me'), isNull);
    });

    test('Schreiben nacheinander: ein Löschen danach gewinnt, und das letzte Schreiben', () async {
      final cache = FileTrailCache(baseDir: dir);
      // Das Abmelden kommt, während die Kopie noch geschrieben wird: Sie
      // darf danach nicht wieder dastehen.
      unawaited(cache.write(uid: 'me', snapshot: snapshot, savedAt: at));
      await cache.clear();
      expect(await cache.read(uid: 'me'), isNull);
      unawaited(cache.write(uid: 'me', snapshot: snapshot, savedAt: at));
      await cache.write(uid: 'other', snapshot: snapshot, savedAt: at);
      expect(await cache.read(uid: 'me'), isNull, reason: 'das ältere Schreiben ist übersprungen');
      expect(await cache.read(uid: 'other'), isNotNull);
      final files = dir.listSync(recursive: true).map((f) => f.path).toList();
      expect(files.where((p) => p.endsWith('.part')), isEmpty);
    });

    test('schreiben wirft nie, auch wenn es nicht geht', () async {
      await File('${dir.path}/blocked').writeAsString('x');
      final cache = FileTrailCache(baseDir: Directory('${dir.path}/blocked'));
      await cache.write(uid: 'me', snapshot: snapshot, savedAt: at);
      expect(await cache.read(uid: 'me'), isNull);
    });
  });

  group('fetchWithCache', () {
    test('Netz geht: frisch, und die Kopie wird geschrieben', () async {
      final cache = FakeTrailCache();
      final r = await fetchWithCache(fetch: () async => snapshot, cache: cache, uid: 'me', now: at);
      expect(r.cachedAt, isNull);
      expect(r.snapshot.recordings, hasLength(2));
      expect(cache.writes, 1);
      expect(cache.savedAt, at);
    });

    test('kein Netz: die Kopie, mit ihrem Alter', () async {
      final cache = FakeTrailCache()
        ..uid = 'me'
        ..snapshot = snapshot
        ..savedAt = at;
      final r = await fetchWithCache(
          fetch: () async => throw const SocketException('offline'),
          cache: cache, uid: 'me', now: at.add(const Duration(hours: 3)));
      expect(r.cachedAt, at);
      expect(r.snapshot.details.single.name, 'Roots');
      expect(cache.writes, 0);
    });

    test('kein Netz und keine Kopie: der Netzfehler', () async {
      expect(
          fetchWithCache(
              fetch: () async => throw const SocketException('offline'),
              cache: FakeTrailCache(), uid: 'me', now: at),
          throwsA(isA<SocketException>()));
    });

    test('ein Serverfehler wird NICHT aus der Kopie bedient', () async {
      final cache = FakeTrailCache()
        ..uid = 'me'
        ..snapshot = snapshot
        ..savedAt = at;
      expect(
          fetchWithCache(
              fetch: () async => throw StateError('42501: RLS'),
              cache: cache, uid: 'me', now: at),
          throwsA(isA<StateError>()));
    });
  });

  // Der Kaltstart (#183): ohne Empfang kam die Kopie erst nach den
  // Wiederholungen von postgrest (rund 7 s). Jetzt nach einer kurzen Frist.
  group('fetchWithCacheQuick', () {
    const patience = Duration(milliseconds: 50);
    FakeTrailCache filled() => FakeTrailCache()
      ..uid = 'me'
      ..snapshot = snapshot
      ..savedAt = at;

    ({List<TrailSnapshot> late, List<Object> errors, List<String> offline, List<String> waiting})
        calls() => (late: [], errors: [], offline: [], waiting: []);

    Future<TrailSnapshotResult> run(
      Future<TrailSnapshot> Function() fetch,
      FakeTrailCache cache,
      ({List<TrailSnapshot> late, List<Object> errors, List<String> offline, List<String> waiting})
          c, {
      Duration p = patience,
    }) =>
        fetchWithCacheQuick(
          fetch: fetch,
          cache: cache,
          uid: 'me',
          now: at,
          patience: p,
          onLate: c.late.add,
          onLateOffline: () => c.offline.add('offline'),
          onLateError: (e, _) => c.errors.add(e),
          onStillWaiting: () => c.waiting.add('waiting'),
        );

    test('das Netz antwortet in der Frist: frisch, wie bisher', () async {
      final cache = filled();
      final c = calls();
      final r = await run(() async => snapshot, cache, c);
      expect(r.cachedAt, isNull);
      expect(cache.writes, 1);
      expect(c.late, isEmpty);
    });

    test('schnell abgelehnt (Flugmodus): die Kopie, wie bisher', () async {
      final c = calls();
      final r = await run(() async => throw const SocketException('offline'), filled(), c);
      expect(r.cachedAt, at);
      expect(c.offline, isEmpty, reason: 'kein später Ausgang — das Netz ist schon fertig');
      expect(c.waiting, isEmpty, reason: 'sonst hieße es „das Netz antwortet noch"');
    });

    test('das Netz zögert: SOFORT die Kopie, der frische Stand kommt nach', () async {
      final net = Completer<TrailSnapshot>();
      final cache = filled();
      final c = calls();
      final watch = Stopwatch()..start();
      final r = await run(() => net.future, cache, c);
      expect(r.cachedAt, at);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      expect(c.waiting, hasLength(1));
      expect(cache.writes, 0);
      net.complete(snapshot);
      await pumpEventQueue();
      expect(c.late, hasLength(1));
      expect(cache.writes, 1, reason: 'die Kopie ist neu, bevor der frische Stand gezeigt wird');
    });

    test('das Netz zögert und gibt dann auf: die Kopie bleibt', () async {
      final net = Completer<TrailSnapshot>();
      final c = calls();
      await run(() => net.future, filled(), c);
      net.completeError(const SocketException('offline'));
      await pumpEventQueue();
      expect(c.offline, hasLength(1));
      expect(c.late, isEmpty);
      expect(c.errors, isEmpty);
    });

    test('das Netz zögert und antwortet mit einem Serverfehler: der wird gemeldet', () async {
      final net = Completer<TrailSnapshot>();
      final c = calls();
      await run(() => net.future, filled(), c);
      net.completeError(StateError('42501: RLS kaputt'));
      await pumpEventQueue();
      expect(c.errors.single, isA<StateError>());
    });

    test('ohne Kopie wird gewartet — eine leere Karte vorab wäre keine Antwort', () async {
      final net = Completer<TrailSnapshot>();
      final c = calls();
      var done = false;
      final result = run(() => net.future, FakeTrailCache(), c).then((r) {
        done = true;
        return r;
      });
      await Future<void>.delayed(patience * 3);
      expect(done, isFalse);
      net.complete(snapshot);
      expect((await result).cachedAt, isNull);
      expect(c.late, isEmpty);
    });

    test('ohne Kopie und das Netz gibt auf: der Netzfehler', () async {
      final net = Completer<TrailSnapshot>();
      final result = run(() => net.future, FakeTrailCache(), calls());
      await Future<void>.delayed(patience * 2);
      net.completeError(const SocketException('offline'));
      await expectLater(result, throwsA(isA<SocketException>()));
    });

    test('ohne Empfang gemeldet (Frist 0): die Kopie, ohne zu warten', () async {
      final net = Completer<TrailSnapshot>();
      final r = await run(() => net.future, filled(), calls(), p: Duration.zero);
      expect(r.cachedAt, at);
    });
  });
}
