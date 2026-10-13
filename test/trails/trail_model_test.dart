import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/trail.dart';
import '../fakes/l10n_de.dart';

TrailRecording rec(String trail, String user,
        {double quality = 0.5, int day = 1, List<LatLng>? pts, List<double>? ele,
        bool reversed = false, RecordingSource source = RecordingSource.import, DateTime? rodeAt}) =>
    TrailRecording(
      id: '$trail-$user-$day',
      trailId: trail,
      userId: user,
      source: source,
      recordedAt: rodeAt,
      reversed: reversed,
      quality: quality,
      createdAt: DateTime(2026, 1, day),
      points: pts ?? const [LatLng(48, 9), LatLng(48.01, 9)],
      lengthM: 1000,
      ele: ele,
    );

TrailDetails det(String trail, String user, {String? name, int? grade, int? rating}) =>
    TrailDetails(trailId: trail, userId: user, name: name, grade: grade, rating: rating);

var _reportN = 0;
TrailReport rep(String trail, String user, DateTime at,
        {TrailStatus? status, int? condition, bool confirmed = true}) =>
    TrailReport(
      id: 'r${_reportN++}',
      trailId: trail,
      userId: user,
      kind: status != null ? ReportKind.status : ReportKind.condition,
      status: status,
      condition: condition,
      confirmed: confirmed,
      reportedAt: at,
    );

void main() {
  test('nach Namen sortiert, Trails ohne Namen hinten — in jeder Sprache', () {
    Trail t(String id, String? name) => Trail(
        id: id, myId: 'me', recordings: [rec(id, 'me')], details: [if (name != null) det(id, 'me', name: name)]);
    final sorted = [t('a', null), t('b', 'wald'), t('c', 'Ahorn')]..sort(compareTrailNames);
    expect([for (final x in sorted) x.id], ['c', 'b', 'a'],
        reason: 'vorher stand „Trail ohne Namen" unter T — die Reihenfolge hinge an der Sprache');
  });

  test('geplant: nur wer ausschließlich Dateien ohne Fahrzeiten beigesteuert hat (#100)', () {
    const planned = RecordingSource.planned;
    final t = Trail(
      id: 't',
      myId: 'me',
      recordings: [
        rec('t', 'me', source: planned),
        rec('t', 'a', source: planned, day: 2),
        rec('t', 'a', day: 3),
        rec('t', 'b', source: planned, day: 4),
      ],
      details: const [],
    );
    expect(t.onlyPlanned('me'), isTrue);
    expect(t.onlyPlanned('a'), isFalse, reason: 'eine gefahrene Aufzeichnung reicht');
    expect(t.onlyPlanned('b'), isTrue);
    expect(t.onlyPlanned('nobody'), isFalse, reason: 'ohne Beleg kein „geplant"');
    expect(t.allPlanned, isFalse);
    final onlyPlans = Trail(
        id: 't', myId: 'me', recordings: [rec('t', 'me', source: planned)], details: const []);
    expect(onlyPlans.allPlanned, isTrue);
  });

  test('geplant MIT eingetragenem Fahrdatum ist gefahren (#120, Patch 015)', () {
    const planned = RecordingSource.planned;
    final t = Trail(
      id: 't',
      myId: 'me',
      recordings: [rec('t', 'me', source: planned, rodeAt: DateTime.utc(2026, 9, 12, 10))],
      details: const [],
    );
    expect(t.recordings.single.ridden, isTrue);
    expect(t.onlyPlanned('me'), isFalse, reason: 'das Blatt sagt nicht mehr „nur geplant"');
    expect(t.allPlanned, isFalse);
    expect(t.hasRidden('me'), isTrue, reason: 'Meldungen dazu sind bestätigt — wie has_ridden');
    expect(rec('t', 'x', source: planned).ridden, isFalse);
    expect(rec('t', 'x').ridden, isTrue);
  });

  test('#174 in beide Richtungen: die eigene Angabe, sonst die Mehrheit, im Zweifel nein', () {
    Trail t(List<TrailDetails> details) =>
        Trail(id: 't1', myId: 'me', recordings: [rec('t1', 'anna')], details: details);
    TrailDetails d(String user, bool twoWay) => TrailDetails(trailId: 't1', userId: user, twoWay: twoWay);
    expect(t(const []).twoWay, isFalse);
    expect(t([d('anna', true)]).twoWay, isTrue);
    expect(t([d('anna', true), d('bob', false)]).twoWay, isFalse, reason: 'Gleichstand: die Richtung gilt');
    expect(t([d('anna', true), d('bob', true), d('cleo', false)]).twoWay, isTrue);
    expect(t([d('anna', true), d('bob', true), d('me', false)]).twoWay, isFalse, reason: 'meine Angabe für meine Planung');
    expect(t([d('anna', false), d('me', true)]).twoWay, isTrue);
    // Zeile: geschrieben und gelesen, ältere Zeilen ohne Spalte heißen nein.
    final row = d('me', true).toRow();
    expect(row['two_way'], isTrue);
    expect(TrailDetails.fromJson({...row, 'trail_id': 't1', 'user_id': 'me'}).twoWay, isTrue);
    expect(TrailDetails.fromJson(const {'trail_id': 't1', 'user_id': 'me'}).twoWay, isFalse);
    expect(d('me', true).copyWith(name: 'X').twoWay, isTrue, reason: 'copyWith verliert es nicht');
  });

  test('eigener Name vor dem des ältesten Beitrags, Rest als „auch"', () {
    final t = Trail(
      id: 't1',
      myId: 'me',
      recordings: [rec('t1', 'anna', day: 1), rec('t1', 'bob', day: 5), rec('t1', 'me', day: 9)],
      details: [det('t1', 'bob', name: 'Roots'), det('t1', 'anna', name: 'Hexentanz')],
    );
    expect(t.displayName(l10nDe), 'Hexentanz');
    expect(t.otherNames, ['Roots']);
    final mine = Trail(
      id: 't1',
      myId: 'me',
      recordings: t.recordings,
      details: [...t.details, det('t1', 'me', name: 'Mein Weg')],
    );
    expect(mine.displayName(l10nDe), 'Mein Weg');
    expect(mine.otherNames, containsAll(['Roots', 'Hexentanz']));
  });

  test('beste Linie ist die mit der höchsten Qualität, bei Gleichstand die ältere', () {
    final a = rec('t', 'a', quality: 0.4, day: 1, pts: const [LatLng(1, 1), LatLng(1, 2)]);
    final b = rec('t', 'b', quality: 0.6, day: 2, pts: const [LatLng(2, 2), LatLng(2, 3)]);
    final c = rec('t', 'c', quality: 0.6, day: 3);
    expect(Trail(id: 't', myId: 'x', recordings: [a, c, b], details: const []).best.id, b.id);
  });

  test('jüngste bestätigte Meldung gewinnt, Median der S-Grade, Buddys gezählt', () {
    final t = Trail(
      id: 't',
      myId: 'me',
      recordings: [rec('t', 'me'), rec('t', 'a'), rec('t', 'b')],
      details: [
        det('t', 'a', grade: 2),
        det('t', 'b', grade: 3),
        det('t', 'me', grade: 5),
      ],
      reports: [
        rep('t', 'a', DateTime(2026, 3, 1), status: TrailStatus.closed),
        rep('t', 'b', DateTime(2026, 4, 1), status: TrailStatus.open),
      ],
    );
    expect(t.status, TrailStatus.open);
    expect(t.grade, 3);
    expect(t.buddyIds, {'a', 'b'});
    expect(t.isOwn, isTrue);
  });

  group('Meldung und Zustand (#101)', () {
    Trail withReports(List<TrailReport> reports) => Trail(
          id: 't', myId: 'me', recordings: [rec('t', 'me')], details: const [], reports: reports);

    test('die jüngste bestätigte, dazu eine jüngere unbestätigte', () {
      final closed = rep('t', 'a', DateTime(2026, 9, 1), status: TrailStatus.closed);
      final openLater = rep('t', 'b', DateTime(2026, 9, 10), status: TrailStatus.open, confirmed: false);
      final t = withReports([closed, openLater]);
      expect(t.shownStatus.confirmed, closed);
      expect(t.shownStatus.unconfirmed, openLater);
      expect(t.status, TrailStatus.closed, reason: 'Karte und Liste folgen der bestätigten');
    });

    test('eine ältere unbestätigte ist überholt und fällt weg', () {
      final old = rep('t', 'b', DateTime(2026, 8, 1), status: TrailStatus.destroyed, confirmed: false);
      final closed = rep('t', 'a', DateTime(2026, 9, 1), status: TrailStatus.closed);
      final t = withReports([old, closed]);
      expect(t.shownStatus.unconfirmed, isNull);
      expect(t.shownStatus.confirmed, closed);
    });

    test('nur unbestätigt: die Karte bleibt ohne Warnung, das Blatt zeigt sie', () {
      final t = withReports([rep('t', 'b', DateTime(2026, 9, 1), status: TrailStatus.closed, confirmed: false)]);
      expect(t.status, TrailStatus.open);
      expect(t.shownStatus.unconfirmed?.status, TrailStatus.closed);
    });

    test('Zustand: der jüngste bestätigte steht dauerhaft, auch nach einem Jahr', () {
      final t = withReports([
        rep('t', 'a', DateTime(2025, 6, 1), condition: 2),
        rep('t', 'b', DateTime(2025, 5, 1), condition: 5),
      ]);
      expect(t.shownCondition.confirmed?.condition, 2);
      expect(t.reportsShown(now: DateTime(2026, 9, 30)).map((r) => r.condition), [2],
          reason: 'außerhalb der 90 Tage bleibt nur, was angezeigt wird');
    });

    test('Verlauf: 90 Tage, neueste zuerst', () {
      final now = DateTime(2026, 9, 30);
      final t = withReports([
        rep('t', 'a', DateTime(2026, 9, 1), status: TrailStatus.closed),
        rep('t', 'a', DateTime(2026, 9, 20), status: TrailStatus.open),
        rep('t', 'b', DateTime(2026, 5, 1), status: TrailStatus.changed),
      ]);
      expect(t.reportsShown(now: now).map((r) => r.status),
          [TrailStatus.open, TrailStatus.closed]);
    });
  });

  group('Bewertung (#101)', () {
    test('Median, bei Gleichstand der höhere', () {
      final t = Trail(id: 't', myId: 'me', recordings: [rec('t', 'me'), rec('t', 'a')], details: [
        det('t', 'me', rating: 2),
        det('t', 'a', rating: 4),
      ]);
      expect(t.rating, 4);
      expect(t.ratingVotes, hasLength(2));
      expect(t.ratingOpen, isFalse);
    });

    test('belegt, aber nicht bewertet: Bewertung offen (verblasste Sterne)', () {
      final t = Trail(id: 't', myId: 'me', recordings: [rec('t', 'me'), rec('t', 'a')], details: [
        det('t', 'me'),
        det('t', 'a', rating: 5),
      ]);
      expect(t.rating, 5);
      expect(t.ratingOpen, isTrue);
      final buddyOnly = Trail(id: 't', myId: 'me', recordings: [rec('t', 'a')], details: [det('t', 'a')]);
      expect(buddyOnly.ratingOpen, isFalse, reason: 'ohne eigenen Beleg keine eigene Bewertung');
    });

    test('ein Wert außerhalb 1–5 fällt beim Lesen weg', () {
      final d = TrailDetails.fromJson({'trail_id': 't', 'user_id': 'a', 'rating': 7});
      expect(d.rating, isNull);
    });
  });

  test('gefahren heißt: eine Aufzeichnung, die nicht nur geplant ist', () {
    final t = Trail(id: 't', myId: 'me', recordings: [
      rec('t', 'me', source: RecordingSource.planned),
      rec('t', 'a'),
    ], details: const []);
    expect(t.hasRidden('me'), isFalse);
    expect(t.hasRidden('a'), isTrue);
  });

  test('eine Meldung unbekannter Art liest sich als nichts', () {
    expect(
        TrailReport.fromJson({
          'id': 'x', 'trail_id': 't', 'user_id': 'a', 'kind': 'weather',
          'confirmed': true, 'reported_at': '2026-09-30T08:00:00Z',
        }),
        isNull);
    expect(
        TrailReport.fromJson({
          'id': 'x', 'trail_id': 't', 'user_id': 'a', 'kind': 'condition', 'condition': 9,
          'confirmed': true, 'reported_at': '2026-09-30T08:00:00Z',
        }),
        isNull);
  });

  test('buildTrails gruppiert und lässt Beiträge ohne Beleg weg', () {
    final trails = buildTrails(
      recordings: [rec('t1', 'me'), rec('t2', 'a')],
      details: [det('t1', 'me', name: 'B-Trail'), det('t2', 'a', name: 'A-Trail'), det('t3', 'a', name: 'Geist')],
      myId: 'me',
    );
    expect(trails.map((t) => t.displayName(l10nDe)), ['A-Trail', 'B-Trail']);
  });

  test('fromJson nimmt GeoJSON als Text und als Objekt', () {
    final base = {
      'id': 'r', 'trail_id': 't', 'user_id': 'u', 'source': 'planned',
      'reversed': true, 'quality': 0.1, 'created_at': '2026-01-01T00:00:00Z',
      'length_m': 12.5,
    };
    final asText = TrailRecording.fromJson({...base,
        'geojson': '{"type":"LineString","coordinates":[[9.0,48.0],[9.1,48.1]]}'});
    final asMap = TrailRecording.fromJson({...base,
        'geojson': {'type': 'LineString', 'coordinates': [[9.0, 48.0], [9.1, 48.1]]}});
    for (final r in [asText, asMap]) {
      expect(r.points, const [LatLng(48, 9), LatLng(48.1, 9.1)]);
      expect(r.source, RecordingSource.planned);
      expect(r.reversed, isTrue);
    }
  });

  test('Höhen: aus der besten Aufzeichnung MIT Höhen, in Trail-Richtung', () {
    // Die beste Linie (0,6) ist alt und ohne Höhen; die Höhen kommen aus
    // der schlechteren, und die ist gegen die Richtung gefahren.
    final t = buildTrails(recordings: [
      rec('t', 'me', quality: 0.6),
      rec('t', 'bob', quality: 0.4, day: 2, ele: [500, 620], reversed: true),
    ], details: const [], myId: 'me').single;
    expect(t.best.userId, 'me');
    expect(t.elevationRecording!.userId, 'bob');
    expect(t.elevation!.lossM, 120, reason: 'bergauf gefahren, bergab gemeint');
    expect(t.elevation!.gainM, 0);
    expect(buildTrails(recordings: [rec('u', 'me')], details: const [], myId: 'me')
        .single.elevation, isNull);
  });

  test('fromJson liest ele nur, wenn es zu den Punkten passt', () {
    Map<String, dynamic> row(Object? ele) => {
          'id': 'r', 'trail_id': 't', 'user_id': 'u', 'source': 'import',
          'recorded_at': null, 'reversed': false, 'quality': 0.4,
          'created_at': '2026-09-27T10:00:00Z', 'length_m': 1000,
          'geojson': '{"type":"LineString","coordinates":[[9,48],[9,48.01]]}',
          'ele': ele,
        };
    expect(TrailRecording.fromJson(row([500, 480.5])).ele, [500, 480.5]);
    expect(TrailRecording.fromJson(row(null)).ele, isNull);
    expect(TrailRecording.fromJson(row([500])).ele, isNull,
        reason: 'eine verschobene Reihe wäre schlimmer als keine');
  });

  test('Schwierigkeit: Spanne, Einzelstimmen, Gleichstand zum schwereren', () {
    final t = buildTrails(recordings: [
      rec('t', 'me'),
      rec('t', 'a', day: 2),
      rec('t', 'b', day: 3),
      rec('t', 'c', day: 4),
    ], details: [
      det('t', 'me', grade: 1),
      det('t', 'a', grade: 2),
      det('t', 'b', grade: 3),
      det('t', 'c'),
    ], myId: 'me').single;
    expect(t.gradeRange, (min: 1, max: 3));
    expect(t.gradeVotes.map((d) => d.userId), ['me', 'a', 'b'],
        reason: 'ohne Angabe zählt nicht, älteste Beiträge zuerst');
    expect(t.grade, 2);
    final even = buildTrails(recordings: [rec('u', 'me'), rec('u', 'a')],
        details: [det('u', 'me', grade: 2), det('u', 'a', grade: 3)], myId: 'me').single;
    expect(even.grade, 3, reason: 'bei Gleichstand gewinnt die Warnung');
    expect(buildTrails(recordings: [rec('v', 'me')], details: [det('v', 'me')], myId: 'me')
        .single.gradeRange, isNull);
  });

  test('Hinweise: neueste zuerst, „neu" nur von Buddys, 7 Tage, ungesehen', () {
    final now = DateTime(2026, 9, 28, 12);
    TrailNote note(String user, int daysAgo) => TrailNote(
          id: '$user-$daysAgo',
          trailId: 't',
          userId: user,
          body: 'Baum quer',
          createdAt: now.subtract(Duration(days: daysAgo)),
        );
    Trail trail(List<TrailNote> notes) => buildTrails(
          recordings: [rec('t', 'me'), rec('t', 'bob')],
          details: const [],
          notes: [...notes, note('bob', 1).copyTrail('anderer')],
          myId: 'me',
        ).singleWhere((t) => t.id == 't');

    final t = trail([note('bob', 9), note('me', 0), note('bob', 3)]);
    expect(t.notes, hasLength(3), reason: 'Hinweise anderer Trails bleiben dort');
    expect(t.notesShown(now: now).map((n) => n.id), ['me-0', 'bob-3', 'bob-9']);
    expect(t.hasFreshNote(now: now), isTrue);
    expect(t.hasFreshNote(now: now, seen: {'bob-3'}), isFalse,
        reason: 'im Blatt gesehen: nicht mehr hervorgehoben');
    expect(trail([note('me', 0), note('bob', 8)]).hasFreshNote(now: now), isFalse,
        reason: 'der eigene zählt nicht, der alte ist nicht mehr neu');
  });

  test('nach 90 Tagen nur noch der jüngste', () {
    final now = DateTime(2026, 9, 28, 12);
    TrailNote note(String user, int daysAgo) => TrailNote(
          id: '$user-$daysAgo',
          trailId: 't',
          userId: user,
          body: 'x',
          createdAt: now.subtract(Duration(days: daysAgo)),
        );
    Trail trail(List<TrailNote> notes) => Trail(
        id: 't', myId: 'me', recordings: [rec('t', 'me')], details: const [], notes: notes);

    expect(trail([note('bob', 200), note('anna', 120), note('bob', 95)])
            .notesShown(now: now)
            .map((n) => n.id),
        ['bob-95'], reason: 'alle alt: der jüngste bleibt stehen');
    expect(trail([note('bob', 200), note('anna', 10), note('bob', 89)])
            .notesShown(now: now)
            .map((n) => n.id),
        ['anna-10', 'bob-89']);
  });

  test('Namen aus Dateien passen in den Check der Datenbank', () {
    expect(clampTrailName('  Wurzeltrail '), 'Wurzeltrail');
    final exact = 'x' * kTrailNameMaxLength;
    expect(clampTrailName(exact), exact);
    final words = List.filled(20, 'Wort').join(' ');   // 99 Zeichen
    final cut = clampTrailName(words);
    expect(cut.length, lessThanOrEqualTo(kTrailNameMaxLength));
    expect(cut, endsWith('Wort…'), reason: 'am Wortende gekürzt');
    final blob = 'y' * 120;
    expect(clampTrailName(blob), '${'y' * (kTrailNameMaxLength - 1)}…');
  });

  test('TrailNote.fromJson liest den Autor aus dem Embed', () {
    final n = TrailNote.fromJson({
      'id': 'n1',
      'trail_id': 't',
      'user_id': 'u',
      'body': 'Neuer Drop am Ende',
      'created_at': '2026-09-28T10:00:00Z',
      'author': {'username': 'bob'},
    });
    expect(n.username, 'bob');
    expect(n.body, 'Neuer Drop am Ende');
    expect(n.createdAt.isUtc, isFalse);
  });
}

extension on TrailNote {
  TrailNote copyTrail(String trailId) => TrailNote(
      id: '$id-x', trailId: trailId, userId: userId, body: body, createdAt: createdAt);
}
