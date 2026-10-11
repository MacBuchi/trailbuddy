// „Sind das dieselben?" (#107 Schritt 3): welche Paare vorgeschlagen
// werden und wann „auf gemeinsamen Teil kürzen" dazukommt.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/trails/merge_proposals.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/trail.dart';
import 'package:trailbuddy/models/trail_merge.dart';

/// Eine Linie nach Norden über [m] Meter ab [fromM], alle 50 m ein Punkt;
/// [eastM] verschiebt sie nach Osten.
List<LatLng> north(double m, {double eastM = 0, double fromM = 0}) {
  const perDegLat = 111320.0;
  const perDegLon = 111320.0 * 0.6691;
  return [
    for (var d = fromM; d <= fromM + m + 0.001; d += 50) LatLng(48 + d / perDegLat, 9 + eastM / perDegLon),
  ];
}

TrailRecording rec(String trailId, String userId, List<LatLng> points, {DateTime? at}) => TrailRecording(
      id: 'rec-$trailId-$userId',
      trailId: trailId,
      userId: userId,
      source: RecordingSource.import,
      recordedAt: null,
      reversed: false,
      quality: 0.4,
      createdAt: at ?? DateTime(2026, 1, 1),
      points: points,
      lengthM: 1000,
    );

List<Trail> net(List<TrailRecording> recs) => buildTrails(myId: 'me', recordings: recs, details: const []);

void main() {
  test('eine Erklärung eines Buddys: der Vorschlag, mit wem und in welche Richtung', () {
    final trails = net([
      rec('B', 'me', north(1000, eastM: 20)),
      rec('A', 'jan', north(1000), at: DateTime(2025, 1, 1)),
    ]);
    final p = mergeProposals(trails, const [
      TrailMerge(trailId: 'B', sameAs: 'A', kind: TrailMergeKind.proposed, byUsers: ['jan', 'ute']),
    ]).single;
    expect(p.source, ProposalSource.declared);
    expect(p.duplicate.id, 'B');
    expect(p.target.id, 'A');
    expect(p.byUsers, ['jan', 'ute']);
    expect(p.share, 1.0);
    expect(p.involves('A'), isTrue);
    expect(p.otherThan('B').id, 'A');
    expect(p.trimmable, isNull, reason: 'gleich lang, nichts zu kürzen');
  });

  test('aus dem Abgleich nur, was grob beieinander liegt', () {
    final trails = net([
      rec('A', 'me', north(1000)),
      rec('B', 'jan', north(1000, eastM: 30)),
      // Eine Gabel: teilt nur das erste Drittel.
      rec('C', 'jan', [...north(300), const LatLng(48.0027, 9.01)]),
    ]);
    final found = mergeProposals(trails, const [
      TrailMerge(trailId: 'A', sameAs: 'B', kind: TrailMergeKind.overlap),
      TrailMerge(trailId: 'A', sameAs: 'C', kind: TrailMergeKind.overlap),
    ]);
    expect(found.map((p) => p.key), [pairKey('A', 'B')]);
    expect(found.single.source, ProposalSource.overlap);
  });

  test('ein Paar steht einmal, die Erklärung schlägt die Kante', () {
    final trails = net([rec('A', 'me', north(1000)), rec('B', 'jan', north(1000, eastM: 10))]);
    final found = mergeProposals(trails, const [
      TrailMerge(trailId: 'A', sameAs: 'B', kind: TrailMergeKind.overlap),
      TrailMerge(trailId: 'B', sameAs: 'A', kind: TrailMergeKind.proposed, byUsers: ['jan']),
    ]);
    expect(found, hasLength(1));
    expect(found.single.source, ProposalSource.declared);
  });

  test('Paare, die bei mir schon einer sind, oder Unbekanntes fallen weg', () {
    final trails = net([rec('A', 'me', north(1000))]);
    expect(
        mergeProposals(trails, const [
          TrailMerge(trailId: 'X', sameAs: 'A', kind: TrailMergeKind.proposed, byUsers: ['jan']),
          TrailMerge(trailId: 'A', sameAs: 'A', kind: TrailMergeKind.overlap),
        ]),
        isEmpty);
  });

  test('meine lange Fassung mit Anfahrt enthält den kurzen Trail: kürzen', () {
    final trails = net([
      // Meine Datei: 600 m Anfahrt, dann der Trail.
      rec('LANG', 'me', north(1600)),
      rec('KURZ', 'jan', north(1000, fromM: 600, eastM: 5)),
    ]);
    final p = mergeProposals(trails, const [
      TrailMerge(trailId: 'LANG', sameAs: 'KURZ', kind: TrailMergeKind.overlap),
    ]).single;
    expect(p.trimmable?.id, 'LANG');
  });

  test('liegen beide ganz aufeinander, ist keiner die lange Fassung: nichts zu kürzen', () {
    final trails = net([rec('A', 'me', north(1000)), rec('B', 'jan', north(1000, eastM: 5))]);
    final p = mergeProposals(trails, const [
      TrailMerge(trailId: 'A', sameAs: 'B', kind: TrailMergeKind.overlap),
    ]).single;
    expect(p.trimmable, isNull, reason: 'das ist ein Duplikat, keine Anfahrt');
  });

  test('kürzen nur an EIGENEN Trails', () {
    final trails = net([
      rec('LANG', 'jan', north(1600)),
      rec('KURZ', 'me', north(1000, fromM: 600, eastM: 5)),
    ]);
    final p = mergeProposals(trails, const [
      TrailMerge(trailId: 'KURZ', sameAs: 'LANG', kind: TrailMergeKind.overlap),
    ]).single;
    expect(p.trimmable, isNull);
  });

  test('lineCovers ist der Korridor des Abgleichs', () {
    expect(lineCovers(north(1000), north(1000, eastM: 10)), isTrue);
    expect(lineCovers(north(1000), north(1000, eastM: 20)), isFalse, reason: '15 m Korridor');
    expect(lineCovers(north(1000), north(1600)), isFalse);
    expect(lineCovers(north(1600), north(1000)), isTrue);
  });
}
