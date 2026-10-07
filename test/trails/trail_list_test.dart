// Suchen, Filtern, Sortieren der Trail-Liste (#66), pur.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/search_text.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/trails/trail_list.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/trail.dart';

TrailRecording rec(String trail, String user, {int day = 1, double lengthM = 1000, List<double>? ele}) =>
    TrailRecording(
      id: '$trail-$user-$day',
      trailId: trail,
      userId: user,
      source: RecordingSource.import,
      recordedAt: null,
      reversed: false,
      quality: 0.5,
      createdAt: DateTime(2026, 9, day),
      points: ele == null
          ? const [LatLng(48, 9), LatLng(48.01, 9)]
          : [for (var i = 0; i < ele.length; i++) LatLng(48 + i * 0.001, 9)],
      lengthM: lengthM,
      ele: ele,
    );

/// Ein Trail mit einem Beleg und einem Beitrag von [user].
Trail trail(String id, String name,
        {String user = 'me', String? username, int? grade, int day = 1, double lengthM = 1000,
        TrailStatus status = TrailStatus.open, List<double>? ele, List<TrailNote> notes = const []}) =>
    Trail(
      id: id,
      myId: 'me',
      recordings: [rec(id, user, day: day, lengthM: lengthM, ele: ele)],
      details: [
        TrailDetails(trailId: id, userId: user, username: username, name: name, grade: grade),
      ],
      notes: notes,
      reports: [
        if (status != TrailStatus.open)
          TrailReport(
              id: 'r-$id', trailId: id, userId: user, kind: ReportKind.status,
              status: status, confirmed: true, reportedAt: DateTime(2026, 1, day)),
      ],
    );

List<String> names(TrailListResult r) => [for (final t in r.trails) t.displayName];

void main() {
  group('Falten (PilzBuddy #395)', () {
    test('Umlaut, ae/oe/ue, ß, Leer- und Satzzeichen führen auf denselben Schlüssel', () {
      expect(foldSearchText('Roßkopf Süd'), 'roskopfsud');
      expect(foldSearchText('Rosskopf-Sued'), 'roskopfsud');
      expect(foldSearchText('ROSSKOPF sud!'), 'roskopfsud');
    });

    test('Tippfehler: Abstand zu einem Teilstück, nicht zum ganzen Wort', () {
      expect(nearContainsDistance('roskopf', 'roskopfsudtrail'), 0);
      expect(nearContainsDistance(foldSearchText('Rosskopf'), foldSearchText('Roßkopf Süd')), 0);
      expect(nearContainsDistance('rokopf', 'roskopfsud'), 1);
      expect(searchTypoTolerance(3), -1, reason: 'unter vier Zeichen wird nicht geraten');
      expect(searchTypoTolerance(5), 1);
      expect(searchTypoTolerance(9), 2);
    });
  });

  group('Suche', () {
    final list = [
      trail('a', 'Roßkopf Süd', day: 3),
      trail('b', 'Hexentanz', user: 'jan', username: 'jan_mtb', day: 5),
      trail('c', 'Kandel Freeride', day: 1),
    ];

    test('Teiltreffer über den gefalteten Namen und über den Buddy', () {
      expect(names(trailListOf(list, query: 'rosskopf sued')), ['Roßkopf Süd']);
      expect(names(trailListOf(list, query: 'jan')), ['Hexentanz'], reason: 'gesucht wird auch nach dem Buddy');
      expect(trailListOf(list, query: 'kandel').isGuess, isFalse);
    });

    test('leere Suche zeigt alles', () {
      expect(trailListOf(list).trails, hasLength(3));
      expect(trailListOf(list, query: '  - ').trails, hasLength(3));
    });

    test('kein Teiltreffer ⇒ geraten, nur der nächste, und die Oberfläche erfährt es', () {
      final r = trailListOf(list, query: 'Hexntanz');
      expect(names(r), ['Hexentanz']);
      expect(r.isGuess, isTrue);
      final none = trailListOf(list, query: 'xyzzyqq');
      expect(none.trails, isEmpty);
      expect(none.isGuess, isTrue);
      expect(trailListOf(list, query: 'hxt').trails, isEmpty, reason: 'zu kurz zum Raten');
    });

    test('Hinweistexte sind kein Suchtext', () {
      final withNote = trail('n', 'Roots', notes: [
        TrailNote(id: 'n1', trailId: 'n', userId: 'jan', body: 'Baum liegt quer', createdAt: DateTime(2026, 9, 1)),
      ]);
      expect(trailListOf([withNote], query: 'Baum').isGuess, isTrue);
    });
  });

  group('Filter', () {
    final now = DateTime(2026, 9, 20);
    final list = [
      trail('m', 'Mein Flow', grade: 1),
      trail('b', 'Buddy Steil', user: 'jan', grade: 4),
      trail('u', 'Ungeschätzt'),
      trail('r', 'Gesperrt', user: 'jan', grade: 2, status: TrailStatus.closed),
      trail('h', 'Mit Hinweis', user: 'jan', grade: 0, notes: [
        TrailNote(id: 'h1', trailId: 'h', userId: 'jan', body: 'x', createdAt: DateTime(2026, 9, 19)),
      ]),
    ];

    test('Meine / Von Buddys', () {
      expect(names(trailListOf(list, filter: const TrailListFilter(owner: TrailOwnerFilter.mine))),
          unorderedEquals(['Mein Flow', 'Ungeschätzt']));
      expect(trailListOf(list, filter: const TrailListFilter(owner: TrailOwnerFilter.buddies)).trails, hasLength(3));
    });

    test('bis S2: ohne Einschätzung NICHT dabei — und gezählt', () {
      final r = trailListOf(list, filter: const TrailListFilter(maxGrade: 2), sort: TrailSort.name);
      expect(names(r), ['Gesperrt', 'Mein Flow', 'Mit Hinweis']);
      expect(r.hiddenUngraded, 1);
    });

    test('Grad-Bereich (#222): beide Enden eingeschlossen, untere Grenze wirkt', () {
      String grades(TrailListFilter f) => [
            for (final t in trailListOf(list, filter: f, sort: TrailSort.grade).trails) t.grade
          ].join(',');
      final all = grades(const TrailListFilter());
      expect(all.split(',').where((g) => g.isNotEmpty), isNotEmpty);
      for (final (lo, hi) in [(0, 2), (2, 5), (1, 1), (3, 4)]) {
        final f = TrailListFilter(minGrade: lo, maxGrade: hi);
        for (final t in trailListOf(list, filter: f).trails) {
          expect(t.grade, inInclusiveRange(lo, hi), reason: '$lo–$hi: ${t.displayName}');
        }
        final expected = list.where((t) => t.grade != null && t.grade! >= lo && t.grade! <= hi);
        expect(trailListOf(list, filter: f).trails.toSet(), expected.toSet(), reason: '$lo–$hi');
      }
      expect(const TrailListFilter(minGrade: 0, maxGrade: 5).isActive, isFalse,
          reason: 'S0–S5 schränkt nichts ein — Ungeschätzte bleiben');
      expect(trailListOf(list, filter: const TrailListFilter(minGrade: 0, maxGrade: 5)).trails,
          hasLength(list.length));
    });

    test('Grad-Bereich in Worten', () {
      expect(const TrailListFilter(maxGrade: 2).gradeText, 'bis S2');
      expect(const TrailListFilter(minGrade: 3).gradeText, 'ab S3');
      expect(const TrailListFilter(minGrade: 1, maxGrade: 3).gradeText, 'S1–S3');
      expect(const TrailListFilter(minGrade: 2, maxGrade: 2).gradeText, 'nur S2');
      expect(const TrailListFilter().gradeText, 'S0–S5');
    });

    test('neuer Hinweis und gemeldet', () {
      expect(names(trailListOf(list, filter: const TrailListFilter(freshNotesOnly: true), now: now)),
          ['Mit Hinweis']);
      expect(trailListOf(list,
              filter: const TrailListFilter(freshNotesOnly: true), now: now, seenNotes: {'h1'}).trails,
          isEmpty, reason: 'gesehen ist nicht mehr neu');
      expect(names(trailListOf(list, filter: const TrailListFilter(reportedOnly: true))), ['Gesperrt']);
    });

    test('Bewertung offen (#102, E13): eigene Trails ohne eigene Sterne', () {
      final rated = Trail(
        id: 's',
        myId: 'me',
        recordings: [rec('s', 'me')],
        details: const [TrailDetails(trailId: 's', userId: 'me', name: 'Bewertet', rating: 4)],
      );
      const f = TrailListFilter(ratingOpenOnly: true);
      expect(names(trailListOf([...list, rated], filter: f)).toSet(), {'Mein Flow', 'Ungeschätzt'},
          reason: 'Buddy-Trails und bewertete fallen weg');
      expect(f.isActive, isTrue);
      expect(f.describe(), 'Bewertung offen');
    });

    test('geraten wird nur unter dem, was die Filter übrig lassen', () {
      final r = trailListOf(list, query: 'Buddy Stel', filter: const TrailListFilter(owner: TrailOwnerFilter.mine));
      expect(r.trails, isEmpty);
    });

    test('describe nennt, was gefiltert ist — für die Zeile auf der Karte', () {
      expect(const TrailListFilter().describe(), '');
      expect(const TrailListFilter(owner: TrailOwnerFilter.mine, maxGrade: 2, reportedOnly: true).describe(),
          'Meine · bis S2 · gemeldet');
    });

    test('passesTrailFilter ist dieselbe Regel wie die Liste', () {
      const f = TrailListFilter(minGrade: 1, maxGrade: 2);
      final kept = trailListOf(list, filter: f, now: now).trails.toSet();
      for (final t in list) {
        expect(passesTrailFilter(t, f, now: now), kept.contains(t), reason: t.displayName);
      }
    });

    test('isActive', () {
      expect(const TrailListFilter().isActive, isFalse);
      expect(const TrailListFilter(maxGrade: 2).isActive, isTrue);
      expect(const TrailListFilter(minGrade: 1).isActive, isTrue);
    });
  });

  group('Auf der Karte (#222)', () {
    // Der Beleg läuft von 48.00 nach 48.01 auf 9.0 — ein gerades Stück
    // mit nur zwei Punkten, wie eine vereinfachte Linie.
    final t = trail('a', 'Gerade');
    const inside = MapViewBounds(west: 8.99, east: 9.01, south: 47.99, north: 48.02);
    const middle = MapViewBounds(west: 8.99, east: 9.01, south: 48.004, north: 48.006);
    const beside = MapViewBounds(west: 9.01, east: 9.02, south: 47.99, north: 48.02);
    const north = MapViewBounds(west: 8.99, east: 9.01, south: 48.02, north: 48.03);

    test('ein Punkt im Ausschnitt oder eine Strecke, die ihn quert', () {
      expect(trailInBounds(t, inside), isTrue);
      expect(trailInBounds(t, middle), isTrue, reason: 'hineingezoomt: nur die Mitte sichtbar');
      expect(trailInBounds(t, beside), isFalse);
      expect(trailInBounds(t, north), isFalse);
    });

    test('außerhalb zählt auch nicht als ungeschätzt', () {
      final r = trailListOf([t, trail('b', 'Geschätzt', grade: 1)],
          onMap: north, filter: const TrailListFilter(maxGrade: 2));
      expect(r.trails, isEmpty);
      expect(r.hiddenUngraded, 0);
      expect(trailListOf([t], onMap: inside, filter: const TrailListFilter(maxGrade: 2)).hiddenUngraded, 1);
    });
  });

  group('Sortierung', () {
    final list = [
      trail('a', 'Alpha', day: 2, lengthM: 800, grade: 3, ele: [900, 800]),
      trail('b', 'beta', day: 9, lengthM: 2500, ele: [1000, 700]),
      trail('c', 'Gamma', day: 5, lengthM: 1200, grade: 1),
    ];

    test('zuletzt aktiv, Name (ohne Groß/Klein), Länge', () {
      expect(names(trailListOf(list)), ['beta', 'Gamma', 'Alpha']);
      expect(names(trailListOf(list, sort: TrailSort.name)), ['Alpha', 'beta', 'Gamma']);
      expect(names(trailListOf(list, sort: TrailSort.length)), ['beta', 'Gamma', 'Alpha']);
    });

    test('Abfahrt und Schwierigkeit: fehlende Werte immer ans Ende', () {
      expect(names(trailListOf(list, sort: TrailSort.descent)), ['beta', 'Alpha', 'Gamma']);
      expect(names(trailListOf(list, sort: TrailSort.grade)), ['Gamma', 'Alpha', 'beta']);
    });

    test('Bewertung: die beste zuerst, ohne Bewertung ans Ende (#101)', () {
      Trail rated(String id, String name, int? rating) => Trail(
            id: id, myId: 'me', recordings: [rec(id, 'me')],
            details: [TrailDetails(trailId: id, userId: 'me', name: name, rating: rating)]);
      expect(
          names(trailListOf([rated('a', 'Alpha', 3), rated('b', 'Beta', null), rated('c', 'Gamma', 5)],
              sort: TrailSort.rating)),
          ['Gamma', 'Alpha', 'Beta']);
    });

    test('ein neuer Hinweis macht einen Trail „zuletzt aktiv"', () {
      final noted = trail('d', 'Delta', day: 1, notes: [
        TrailNote(id: 'd1', trailId: 'd', userId: 'jan', body: 'x', createdAt: DateTime(2026, 9, 12)),
      ]);
      expect(names(trailListOf([...list, noted])).first, 'Delta');
    });
  });

  group('Wort der Zeile (Design 1j)', () {
    String nameOf(String id, String? username) => username ?? 'Buddy';
    List<String> tags(Trail t, {bool fresh = false}) =>
        [for (final x in trailRowTags(t, freshNote: fresh, nameOf: nameOf)) x.text];

    Trail shared(List<(String, String?)> users) => Trail(
          id: 't',
          myId: 'me',
          recordings: [for (final (u, _) in users) rec('t', u)],
          details: [
            for (final (u, n) in users) TrailDetails(trailId: 't', userId: u, username: n, name: 'X'),
          ],
        );

    test('ohne Zustand die Beziehung: MEIN, MEIN · n BUDDYS, Namen der Buddys', () {
      expect(tags(trail('a', 'A')), ['MEIN']);
      expect(tags(shared([('me', null), ('jan', 'jan'), ('mira', 'mira')])), ['MEIN · 2 BUDDYS']);
      expect(tags(shared([('me', null), ('jan', 'jan')])), ['MEIN · 1 BUDDY']);
      expect(tags(shared([('jan', 'jan'), ('mira', 'mira')])), ['JAN, MIRA']);
      expect(tags(shared([('jan', 'jan'), ('mira', 'mira'), ('tom', 'tom')])), ['JAN, MIRA +1'],
          reason: 'höchstens zwei Namen, sonst läuft die Zeile über');
    });

    test('ein Zustand schlägt die Beziehung, mehrere stehen nebeneinander', () {
      expect(tags(trail('a', 'A', status: TrailStatus.closed)), ['GESPERRT']);
      expect(tags(trail('a', 'A', user: 'jan', username: 'jan'), fresh: true), ['NEUER HINWEIS']);
      expect(tags(trail('a', 'A', status: TrailStatus.destroyed), fresh: true),
          ['ZERSTÖRT', 'NEUER HINWEIS']);
    });

    Trail reported(List<TrailReport> reports) => Trail(
        id: 't', myId: 'me', recordings: [rec('t', 'me')],
        details: const [TrailDetails(trailId: 't', userId: 'me', name: 'X')], reports: reports);
    TrailReport status(TrailStatus s, int day, {bool confirmed = true}) => TrailReport(
        id: 's$day', trailId: 't', userId: 'jan', kind: ReportKind.status, status: s,
        confirmed: confirmed, reportedAt: DateTime(2026, 9, day));
    TrailReport condition(int c, int day, {bool confirmed = true}) => TrailReport(
        id: 'c$day', trailId: 't', userId: 'jan', kind: ReportKind.condition, condition: c,
        confirmed: confirmed, reportedAt: DateTime(2026, 9, day));

    test('unbestätigt: gedämpft mit Fragezeichen, und nur, wenn es etwas anderes sagt (#101)', () {
      final t = reported([status(TrailStatus.closed, 1), status(TrailStatus.open, 5, confirmed: false)]);
      expect(trailRowTags(t, freshNote: false, nameOf: nameOf),
          [(text: 'GESPERRT', kind: TrailRowTagKind.warning), (text: 'OFFEN?', kind: TrailRowTagKind.unconfirmed)]);
      expect(tags(reported([status(TrailStatus.closed, 5, confirmed: false)])), ['GESPERRT?'],
          reason: 'ohne bestätigte Meldung keine Warnung, nur die Frage');
    });

    test('Zustand 1–2 als Wort hinter Meldung und Hinweis, 3–5 nicht (Rework E9)', () {
      expect(tags(reported([condition(2, 3)])), ['ABGEROCKT']);
      expect(tags(reported([status(TrailStatus.changed, 2), condition(1, 3)]), fresh: true),
          ['VERÄNDERT', 'NEUER HINWEIS', 'KAUM FAHRBAR']);
      expect(tags(reported([condition(3, 3)])), ['MEIN']);
      expect(tags(reported([condition(1, 3, confirmed: false)])), ['MEIN'],
          reason: 'ein unbestätigter Zustand steht nur im Blatt');
    });

    test('wartend: nur das Warten — eine Ablehnung als Satz, nicht in Versalien', () {
      final waiting = Trail(
          id: 'p', myId: 'me', recordings: [rec('p', 'me')], details: const [], pending: true);
      expect(trailRowTags(waiting, freshNote: true, nameOf: nameOf).single,
          (text: 'WARTET AUF ÜBERTRAGUNG', kind: TrailRowTagKind.pending));
      final rejected = Trail(
          id: 'p', myId: 'me', recordings: [rec('p', 'me')], details: const [],
          pending: true, pendingFailure: 'Zu kurz für einen Trail.');
      expect(trailRowTags(rejected, freshNote: false, nameOf: nameOf).single,
          (text: 'Zu kurz für einen Trail.', kind: TrailRowTagKind.failure));
    });
  });
}
