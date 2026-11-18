import 'dart:convert';

// Der Ausgangskorb (#30): Aufträge überstehen die Ablage, fremde Konten
// sehen nichts, Unlesbares fällt einzeln weg — und die Datei schreibt
// über `.part` + `rename`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/data/outbox.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/trail.dart';

void main() {
  final at = DateTime.utc(2026, 9, 28, 12);
  final contribute = ContributeJob(
    id: 'job-1',
    createdAt: at,
    coords: const [11.0, 47.0, 11.001, 47.001, 11.002, 47.002],
    eles: const [900, 890, 880],
    source: RecordingSource.import,
    recordedAt: at.subtract(const Duration(days: 3)),
    name: 'Wurzeltrail',
    link: 'https://verein.example/trails/wurzel',
    grade: 2,
    traits: const {TrailTrait.steep, TrailTrait.flowy},
    rating: 5,
  );
  final details = DetailsJob(
    id: 'job-2',
    createdAt: at,
    details: const TrailDetails(
      trailId: 'trail-9',
      userId: 'me',
      name: 'Roots',
      grade: 3,
      traits: {TrailTrait.rocky, TrailTrait.steep},
      rating: 4,
      link: 'https://verein.example/roots',
    ),
  );
  final report = ReportJob(
    id: 'job-3',
    createdAt: at,
    trailId: 'trail-9',
    status: TrailStatus.closed,
    condition: 2,
    onSite: true,
    note: 'Baum liegt quer',
  );

  test('alle drei Auftragsarten überstehen die Ablage unverändert', () {
    final back = decodeOutbox(
      encodeOutbox([contribute, details, report], uid: 'me'),
      uid: 'me',
    );
    expect(back, hasLength(3));
    final c = back[0] as ContributeJob;
    expect(c.id, 'job-1');
    expect(c.coords, contribute.coords);
    expect(c.eles, contribute.eles);
    expect(c.source, RecordingSource.import);
    expect(c.recordedAt, contribute.recordedAt);
    expect(c.name, 'Wurzeltrail');
    expect(c.grade, 2);
    expect(c.traits, {TrailTrait.flowy, TrailTrait.steep});
    expect(
      c.copyWith(attempts: 1).traits,
      c.traits,
      reason: 'copyWith verliert den Charakter nicht',
    );
    expect(c.link, 'https://verein.example/trails/wurzel');
    expect(
      c.copyWith(attempts: 1).link,
      c.link,
      reason: 'copyWith verliert den Link nicht',
    );
    expect(c.rating, 5);
    expect(
      c.copyWith(attempts: 1).rating,
      5,
      reason: 'copyWith verliert die Sterne nicht (#102)',
    );
    final d = back[1] as DetailsJob;
    expect(d.details.trailId, 'trail-9');
    expect(d.details.grade, 3);
    expect(d.details.traits, {TrailTrait.rocky, TrailTrait.steep});
    expect(d.details.link, 'https://verein.example/roots');
    expect(d.details.rating, 4);
    expect(
      d.legacyStatus,
      isNull,
      reason: 'ein neuer Beitrag trägt keine Meldung mehr',
    );
    final r = back[2] as ReportJob;
    expect(r.trailId, 'trail-9');
    expect(r.status, TrailStatus.closed);
    expect(r.condition, 2);
    expect(r.onSite, isTrue);
    expect(r.createdAt, at, reason: 'die Zeit des Meldens geht mit');
    expect(r.note, 'Baum liegt quer');
    expect(
      r.copyWith(attempts: 1).condition,
      2,
      reason: 'copyWith verliert den Zustand nicht',
    );
  });

  test('ein Beitrag von vor 0.49.0 bringt seinen Status als Meldung mit', () {
    final raw = jsonEncode({
      'uid': 'me',
      'jobs': [
        {
          'kind': 'details',
          'id': 'old',
          'created_at': at.toIso8601String(),
          'details': {
            'trail_id': 'trail-9',
            'user_id': 'me',
            'visibility': 'buddies',
            'status': 'closed',
            'status_at': at.toIso8601String(),
          },
          'note': 'Baum quer',
        },
      ],
    });
    final back = decodeOutbox(raw, uid: 'me').single as DetailsJob;
    expect(back.legacyStatus, TrailStatus.closed);
    expect(back.legacyStatusAt, at);
    expect(back.note, 'Baum quer');
    // Und so bleibt es auch nach einem weiteren Ablegen.
    final again =
        decodeOutbox(encodeOutbox([back], uid: 'me'), uid: 'me').single
            as DetailsJob;
    expect(again.legacyStatus, TrailStatus.closed);
  });

  test(
    'ein Auftrag von vor 0.35.0 (ohne traits) liest sich mit leerem Charakter',
    () {
      final raw = encodeOutbox([
        contribute,
      ], uid: 'me').replaceAll(RegExp(r',"traits":\[[^\]]*\]'), '');
      expect(raw, isNot(contains('traits')));
      final back = decodeOutbox(raw, uid: 'me').single as ContributeJob;
      expect(back.traits, isEmpty);
      expect(back.grade, 2);
    },
  );

  test(
    'ein Auftrag von vor 0.55.0 (ohne rating) liest sich ohne Sterne, eine fremde Zahl auch',
    () {
      final raw = encodeOutbox([contribute], uid: 'me');
      expect(
        (decodeOutbox(raw.replaceAll(',"rating":5', ''), uid: 'me').single
                as ContributeJob)
            .rating,
        isNull,
      );
      expect(
        (decodeOutbox(
                  raw.replaceAll('"rating":5', '"rating":9'),
                  uid: 'me',
                ).single
                as ContributeJob)
            .rating,
        isNull,
      );
    },
  );

  test('ein Auftrag von vor 0.48.0 (ohne link) liest sich ohne Link', () {
    final raw = encodeOutbox([
      contribute,
    ], uid: 'me').replaceAll(RegExp(r',"link":"[^"]*"'), '');
    expect(raw, isNot(contains('"link"')));
    expect((decodeOutbox(raw, uid: 'me').single as ContributeJob).link, isNull);
  });

  test('Zähler und Ablehnung reisen mit; retry löscht die Ablehnung', () {
    final failed = contribute.copyWith(attempts: 3, failure: 'zu kurz');
    final back = decodeOutbox(
      encodeOutbox([failed], uid: 'me'),
      uid: 'me',
    ).single;
    expect(back.attempts, 3);
    expect(back.failure, 'zu kurz');
    final retried = back.copyWith(attempts: 0, clearFailure: true);
    expect(retried.attempts, 0);
    expect(retried.failure, isNull);
  });

  test('fremdes Konto sieht nichts, Unlesbares fällt einzeln weg', () {
    final text = encodeOutbox([contribute, details], uid: 'me');
    expect(decodeOutbox(text, uid: 'someone'), isEmpty);
    expect(decodeOutbox('kaputt', uid: 'me'), isEmpty);
    // Ein unbekannter Typ und eine Linie mit ungerader Koordinatenzahl
    // fallen weg, der gültige Auftrag bleibt.
    final mixed =
        '{"uid":"me","jobs":[{"kind":"teleport","id":"x","created_at":"2026-09-28T12:00:00Z"},'
        '{"kind":"contribute","id":"y","created_at":"2026-09-28T12:00:00Z","coords":[11,47,11.1],"source":"import"},'
        '${_json(contribute)}]}';
    final back = decodeOutbox(mixed, uid: 'me');
    expect(back.map((j) => j.id), ['job-1']);
  });

  test('Höhen ohne passende Anzahl machen den Auftrag ungültig', () {
    final bad =
        '{"uid":"me","jobs":[{"kind":"contribute","id":"z","created_at":"2026-09-28T12:00:00Z",'
        '"coords":[11,47,11.1,47.1],"eles":[900],"source":"import"}]}';
    expect(decodeOutbox(bad, uid: 'me'), isEmpty);
  });

  group('FileOutbox', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('outbox_'));
    tearDown(() async => dir.delete(recursive: true));

    test('anhängen, lesen, ersetzen — und keine .part bleibt liegen', () async {
      final box = FileOutbox(baseDir: dir);
      expect(await box.read(uid: 'me'), isEmpty);
      await box.append(contribute, uid: 'me');
      await box.append(details, uid: 'me');
      // Frische Instanz: der Neustart ist der Fall, für den es die Datei gibt.
      final back = await FileOutbox(baseDir: dir).read(uid: 'me');
      expect(back.map((j) => j.id), ['job-1', 'job-2']);
      expect(await box.read(uid: 'someone'), isEmpty);
      await box.replaceAll([details], uid: 'me');
      expect((await box.read(uid: 'me')).map((j) => j.id), ['job-2']);
      final files = dir.listSync(recursive: true).map((f) => f.path).toList();
      expect(files.where((p) => p.endsWith('.part')), isEmpty);
      expect(
        files.any((p) => p.endsWith('${FileOutbox.dirName}/jobs.json')),
        isTrue,
      );
    });

    test('anhängen wirft, wenn sich nichts schreiben lässt', () async {
      await File('${dir.path}/blocked').writeAsString('x');
      final box = FileOutbox(baseDir: Directory('${dir.path}/blocked'));
      expect(
        box.append(contribute, uid: 'me'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  test('ohne Korb (Web) wirft anhängen, lesen ist leer', () async {
    const box = NoOutbox();
    expect(await box.read(uid: 'me'), isEmpty);
    expect(
      box.append(contribute, uid: 'me'),
      throwsA(isA<OutboxUnavailable>()),
    );
  });
}

String _json(OutboxJob job) => encodeOutbox(
  [job],
  uid: 'me',
).replaceFirst('{"uid":"me","jobs":[', '').replaceFirst(RegExp(r'\]\}$'), '');
