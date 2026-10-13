// Duplikate zusammenführen (#107, Konzept 6.1): die Auflösung der
// Zuordnungen, ihr Anwenden in `buildTrails` und „grob beieinander".
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/trails/trail_merge_candidates.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/trail.dart';
import 'package:trailbuddy/models/trail_merge.dart';
import '../fakes/l10n_de.dart';

/// Eine Linie nach Norden ab [lat]/[lon] über [m] Meter, alle 50 m ein
/// Punkt; [eastM] verschiebt sie nach Osten.
List<LatLng> north(double m, {double lat = 48, double lon = 9, double eastM = 0, double fromM = 0}) {
  const perDegLat = 111320.0;
  final perDegLon = 111320.0 * 0.6691; // cos(48°)
  return [
    for (var d = fromM; d <= fromM + m + 0.001; d += 50)
      LatLng(lat + d / perDegLat, lon + eastM / perDegLon),
  ];
}

TrailRecording rec(String trailId, String userId,
        {List<LatLng>? points, bool reversed = false, DateTime? at, String? id}) =>
    TrailRecording(
      id: id ?? 'rec-$trailId-$userId',
      trailId: trailId,
      userId: userId,
      source: RecordingSource.import,
      recordedAt: null,
      reversed: reversed,
      quality: 0.4,
      createdAt: at ?? DateTime(2026, 1, 1),
      points: points ?? north(1000),
      lengthM: 1000,
    );

TrailMerge own(String from, String to, {bool reversed = false}) =>
    TrailMerge(trailId: from, sameAs: to, kind: TrailMergeKind.own, reversed: reversed);

TrailMerge folded(String from, String to, {List<String> by = const ['jan'], bool reversed = false}) =>
    TrailMerge(trailId: from, sameAs: to, kind: TrailMergeKind.folded, byUsers: by, reversed: reversed);

void main() {
  group('resolveMerges', () {
    final ages = {'A': DateTime(2026, 1, 1), 'B': DateTime(2026, 2, 1), 'C': DateTime(2026, 3, 1)};
    DateTime? ageOf(String id) => ages[id];

    test('nur eigene und stille Zuordnungen verschieben etwas', () {
      final r = resolveMerges([
        own('B', 'A'),
        const TrailMerge(trailId: 'C', sameAs: 'A', kind: TrailMergeKind.proposed, byUsers: ['jan']),
        const TrailMerge(trailId: 'A', sameAs: 'C', kind: TrailMergeKind.distinct),
        const TrailMerge(trailId: 'A', sameAs: 'C', kind: TrailMergeKind.overlap),
      ], ageOf: ageOf);
      expect(r.keys, ['B']);
      expect(r['B']!.to, 'A');
      expect(r['B']!.byMe, isTrue);
    });

    test('die eigene Zuordnung geht der eines Buddys vor', () {
      final r = resolveMerges([folded('B', 'C'), own('B', 'A')], ageOf: ageOf);
      expect(r['B']!.to, 'A');
      expect(r['B']!.byMe, isTrue);
    });

    test('mehrere fremde Ziele: mehr Erklärende, dann der ältere Trail', () {
      expect(resolveMerges([folded('C', 'B', by: ['jan', 'ute']), folded('C', 'A')], ageOf: ageOf)['C']!.to, 'B');
      expect(resolveMerges([folded('C', 'B'), folded('C', 'A')], ageOf: ageOf)['C']!.to, 'A');
    });

    test('Ketten gehen bis zum Ende, die Richtung mit', () {
      final r = resolveMerges([folded('C', 'B', reversed: true), own('B', 'A', reversed: true)], ageOf: ageOf);
      expect(r['C']!.to, 'A');
      expect(r['C']!.reversed, isFalse, reason: 'zweimal gedreht ist geradeaus');
      expect(r['C']!.byMe, isFalse);
      expect(r['C']!.byUsers, ['jan']);
      expect(r['B']!.reversed, isTrue);
    });

    test('Gegenrichtungen: der ältere Trail bleibt', () {
      final r = resolveMerges([folded('A', 'B', by: ['jan']), folded('B', 'A', by: ['ute'])], ageOf: ageOf);
      expect(r.keys, ['B']);
      expect(r['B']!.to, 'A');
    });

    test('ein Kreis über drei bricht an einer fremden Kante, nie an der eigenen', () {
      // A → C ist eigen, C → B und B → A sind fremd. Der älteste Trail mit
      // fremder Kante ist B (Feb.): B → A fällt, B bleibt stehen.
      final r = resolveMerges([own('A', 'C'), folded('C', 'B'), folded('B', 'A')], ageOf: ageOf);
      expect(r.containsKey('B'), isFalse);
      expect(r['A']!.to, 'B');
      expect(r['A']!.byMe, isTrue);
      expect(r['C']!.to, 'B');
    });
  });

  group('buildTrails mit Zuordnungen', () {
    test('ein Duplikat steht unter dem behaltenen Trail, mit seiner Richtung', () {
      final trails = buildTrails(
        myId: 'me',
        recordings: [
          rec('A', 'me'),
          rec('B', 'jan', reversed: false, at: DateTime(2026, 2, 1)),
        ],
        details: const [
          TrailDetails(trailId: 'A', userId: 'me', name: 'Hang'),
          TrailDetails(trailId: 'B', userId: 'jan', name: 'Hang (Jan)', grade: 2),
        ],
        notes: [TrailNote(id: 'n', trailId: 'B', userId: 'jan', body: 'Baum', createdAt: DateTime(2026, 9, 1))],
        reports: [
          TrailReport(id: 'r', trailId: 'B', userId: 'jan', kind: ReportKind.condition,
              condition: 4, confirmed: true, reportedAt: DateTime(2026, 9, 1)),
        ],
        merges: [own('B', 'A', reversed: true)],
      );
      expect(trails.map((t) => t.id), ['A']);
      final a = trails.single;
      expect(a.recordings, hasLength(2));
      final moved = a.recordings.firstWhere((r) => r.userId == 'jan');
      expect(moved.trailId, 'A');
      expect(moved.reversed, isTrue, reason: 'B läuft gegen A');
      expect(a.details.map((d) => d.userId), containsAll(['me', 'jan']));
      expect(a.grade, 2, reason: 'die Einschätzung von B zählt unter A');
      expect(a.notes.single.trailId, 'A');
      expect(a.reports.single.trailId, 'A');
      expect(a.displayName(l10nDe), 'Hang');
      expect(a.otherNames, ['Hang (Jan)']);
      expect(a.mergedFrom, [const MergedTrail(id: 'B', name: 'Hang (Jan)', byMe: true)]);
      expect(a.answersTo('B'), isTrue);
    });

    test('hat jemand an beiden einen Beitrag, gilt der am behaltenen', () {
      final a = buildTrails(
        myId: 'me',
        recordings: [rec('A', 'me'), rec('A', 'ute'), rec('B', 'ute', id: 'rec-B-ute')],
        details: const [
          TrailDetails(trailId: 'A', userId: 'ute', grade: 1),
          TrailDetails(trailId: 'B', userId: 'ute', grade: 4),
        ],
        merges: [folded('B', 'A', by: ['jan'])],
      ).single;
      expect(a.details.single.grade, 1);
      expect(a.mergedFrom.single.byMe, isFalse);
      expect(a.mergedFrom.single.byUsers, ['jan']);
    });

    test('ein Vorschlag verschiebt nichts', () {
      final trails = buildTrails(
        myId: 'me',
        recordings: [rec('A', 'me'), rec('B', 'me')],
        details: const [],
        merges: const [TrailMerge(trailId: 'B', sameAs: 'A', kind: TrailMergeKind.proposed, byUsers: ['jan'])],
      );
      expect(trails.map((t) => t.id).toSet(), {'A', 'B'});
    });

    test('ein unverändertes Neuladen gibt den zusammengeführten Trail als DENSELBEN zurück', () {
      final recs = [rec('A', 'me'), rec('B', 'jan')];
      const details = [TrailDetails(trailId: 'B', userId: 'jan', name: 'X')];
      final merges = [own('B', 'A')];
      final first = buildTrails(myId: 'me', recordings: recs, details: details, merges: merges);
      final second =
          buildTrails(myId: 'me', recordings: recs, details: details, merges: merges, previous: first);
      expect(identical(first.single, second.single), isTrue,
          reason: 'sonst rechnete jedes Neuladen Linie und Höhenprofil neu');
    });
  });

  group('grob beieinander (merge_near)', () {
    test('25 m daneben, ganz parallel: alles liegt nah (Block 25 in matcher_check)', () {
      expect(mergeNearShare(north(800), north(800, eastM: 25)), 1.0);
    });

    test('80 m daneben: nichts', () {
      expect(mergeNearShare(north(800), north(800, eastM: 80)), 0.0);
    });

    test('es zählt die KÜRZERE Linie: ein kurzes Stück auf einer langen ist ganz nah', () {
      expect(mergeNearShare(north(3000), north(400, fromM: 1000, eastM: 20)), 1.0);
      expect(mergeNearShare(north(400, fromM: 1000, eastM: 20), north(3000)), 1.0);
    });

    test('nur zur Hälfte nebeneinander: knapp über der Schwelle', () {
      // 500 m liegen nebeneinander, dazu die letzten Proben VOR dem Anfang
      // der zweiten Linie, die ihrem Anfangspunkt näher als 50 m sind.
      final share = mergeNearShare(north(1000), north(1000, fromM: 500, eastM: 10));
      expect(share, closeTo(0.55, 0.01));
      expect(mergeNearShare(north(1000), north(1000, fromM: 600, eastM: 10)), lessThan(kMergeNearShare));
    });

    test('die Partner: ohne sich selbst, nur grob beieinander, der höchste Anteil zuerst', () {
      final trails = buildTrails(myId: 'me', recordings: [
        rec('A', 'me', points: north(1000)),
        rec('B', 'me', points: north(1000, fromM: 450, eastM: 10)),
        rec('C', 'me', points: north(1000, eastM: 30)),
        rec('D', 'me', points: north(1000, eastM: 300)),
        rec('E', 'me', points: north(1000, fromM: 700, eastM: 10)),
      ], details: const []);
      final a = trails.firstWhere((t) => t.id == 'A');
      final found = mergeCandidates(a, trails);
      expect(found.map((c) => c.trail.id), ['C', 'B']);
      expect(found.first.share, 1.0);
    });

    test('wer bleibt: mehr Beitragende, dann der ältere', () {
      final trails = buildTrails(myId: 'me', recordings: [
        rec('A', 'me', at: DateTime(2026, 3, 1)),
        rec('B', 'me', at: DateTime(2026, 1, 1)),
        rec('B', 'jan', id: 'b2', at: DateTime(2026, 4, 1)),
        rec('C', 'me', at: DateTime(2026, 2, 1)),
      ], details: const []);
      Trail t(String id) => trails.firstWhere((x) => x.id == id);
      expect(defaultKeep(t('A'), t('B')).id, 'B', reason: 'zwei Beitragende gegen einen');
      expect(defaultKeep(t('A'), t('C')).id, 'C', reason: 'gleich viele: der ältere');
      expect(defaultKeep(t('C'), t('A')).id, 'C');
    });

    test('die Schwellen sind die der Datenbank', () {
      expect(kMergeNearM, 50);
      expect(kMergeNearShare, 0.5);
      expect(haversineM(48, 9, 48, 9), 0);
    });
  });
}
