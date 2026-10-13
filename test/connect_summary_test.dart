// Die Zusammenfassung nach dem Verbinden (Konzept 6), pur: Was zählt als
// gemeinsam, neu von, neu für — und was nicht (privat, wartend).
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/friends/connect_summary.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/trail.dart';

import 'fakes/l10n_de.dart';

TrailRecording rec(String trailId, String user) => TrailRecording(
      id: 'r-$trailId-$user',
      trailId: trailId,
      userId: user,
      source: RecordingSource.import,
      recordedAt: null,
      reversed: false,
      quality: 0.4,
      createdAt: DateTime.utc(2026, 1, 1),
      points: const [LatLng(48, 9), LatLng(48.01, 9)],
      lengthM: 1100,
    );

Trail trail(String id, List<String> users, {TrailVisibility? myVisibility, bool pending = false}) => Trail(
      id: id,
      myId: 'me',
      pending: pending,
      recordings: [for (final u in users) rec(id, u)],
      details: [
        if (myVisibility != null) TrailDetails(trailId: id, userId: 'me', visibility: myVisibility),
      ],
    );

void main() {
  test('gemeinsam, neu von, neu für — privat und wartend zählen nicht', () {
    final before = [trail('shared', ['me']), trail('mine', ['me']), trail('secret', ['me'], myVisibility: TrailVisibility.private)];
    final after = [
      trail('shared', ['me', 'jan']),
      trail('mine', ['me']),
      trail('secret', ['me'], myVisibility: TrailVisibility.private),
      trail('jans', ['jan']),
      trail('jans2', ['jan']),
      // Ein Trail eines anderen Buddys, den ich schon sah: weder noch.
      trail('bens', ['ben']),
      // Wartet im Ausgangskorb: noch auf keiner Karte außer meiner.
      trail('queued', ['me'], pending: true),
    ];
    final s = summarizeConnection(before: before, after: after, myId: 'me', buddyId: 'jan');
    expect(s.shared, 1);
    expect(s.newFromBuddy, 2);
    expect(s.newForBuddy, 1);
    expect(s.sentence(l10nDe, 'Jan'), 'Mit Jan verbunden: 1 Trail gemeinsam, 2 neu von Jan, 1 neu für Jan.');
  });

  test('Mehrzahl und der leere Fall', () {
    final after = [trail('a', ['me', 'jan']), trail('b', ['me', 'jan'])];
    final s = summarizeConnection(before: after, after: after, myId: 'me', buddyId: 'jan');
    expect(s.sentence(l10nDe, 'Jan'), startsWith('Mit Jan verbunden: 2 Trails gemeinsam'));
    final empty = summarizeConnection(before: const [], after: const [], myId: 'me', buddyId: 'jan');
    expect(empty.isEmpty, isTrue);
    expect(empty.sentence(l10nDe, 'Jan'), contains('noch keine Trails'));
  });

  test('„n gemeinsam" je Buddy: nur Trails, die ich auch belegt habe; wartende nicht', () {
    final counts = sharedTrailCounts([
      trail('a', ['me', 'jan', 'mira']),
      trail('b', ['me', 'jan', 'jan']),
      trail('c', ['jan']),
      trail('d', ['me', 'mira'], pending: true),
    ], 'me');
    expect(counts, {'jan': 2, 'mira': 1});
  });
}
