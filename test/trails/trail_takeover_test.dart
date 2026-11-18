// Übernehmen beim ersten Befahren (#102): Die Vorbelegung IST die
// Anzeige — Name, Median-S-Grad, Charakter, Median-Sterne der sichtbaren
// Beiträge; der Zustand nur als jüngster bestätigter der letzten 90 Tage.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart'
    show RecordingSource;
import 'package:trailbuddy/features/trails/trail_takeover.dart';
import 'package:trailbuddy/models/trail.dart';

void main() {
  final now = DateTime.utc(2026, 9, 30, 12);
  TrailRecording rec(String user) => TrailRecording(
    id: 'r-$user',
    trailId: 't',
    userId: user,
    source: RecordingSource.import,
    recordedAt: null,
    reversed: false,
    quality: 0.4,
    createdAt: DateTime.utc(2026),
    points: const [LatLng(47, 11), LatLng(47.01, 11)],
    lengthM: 1000,
  );
  TrailReport cond(
    int value, {
    required bool confirmed,
    required int daysAgo,
  }) => TrailReport(
    id: 'c-$value-$daysAgo',
    trailId: 't',
    userId: 'ben',
    kind: ReportKind.condition,
    condition: value,
    confirmed: confirmed,
    reportedAt: now.subtract(Duration(days: daysAgo)),
  );
  Trail trail({
    List<TrailDetails> details = const [],
    List<TrailReport> reports = const [],
  }) => buildTrails(
    recordings: [rec('ben'), rec('me')],
    details: details,
    myId: 'me',
    reports: reports,
  ).single;

  test('Vorbelegung aus dem, was ich sehe', () {
    final t = trail(
      details: const [
        TrailDetails(
          trailId: 't',
          userId: 'ben',
          name: 'Roots',
          grade: 2,
          rating: 5,
          traits: {TrailTrait.flowy, TrailTrait.rocky},
        ),
        TrailDetails(
          trailId: 't',
          userId: 'cleo',
          grade: 3,
          rating: 3,
          traits: {TrailTrait.flowy},
        ),
      ],
    );
    expect(needsTakeOver(t), isTrue);
    final p = takeOverOf(t, now: now);
    expect(p.name, 'Roots');
    expect(p.grade, 3, reason: 'Median, bei Gleichstand der schwerere');
    expect(p.rating, 5, reason: 'Median, bei Gleichstand der höhere');
    expect(p.traits, {TrailTrait.flowy, TrailTrait.rocky});
    expect(p.condition, isNull);
  });

  test(
    'ohne Namen im Netz bleibt das Feld leer — kein „Trail ohne Namen" als Name',
    () {
      expect(takeOverOf(trail(), now: now).name, '');
    },
  );

  test('Zustand: nur der jüngste BESTÄTIGTE der letzten 90 Tage', () {
    expect(
      takeOverOf(
        trail(reports: [cond(2, confirmed: true, daysAgo: 10)]),
        now: now,
      ).condition,
      2,
    );
    expect(
      takeOverOf(
        trail(reports: [cond(2, confirmed: true, daysAgo: 91)]),
        now: now,
      ).condition,
      isNull,
    );
    expect(
      takeOverOf(
        trail(reports: [cond(2, confirmed: false, daysAgo: 1)]),
        now: now,
      ).condition,
      isNull,
    );
  });

  test('wer schon einen Beitrag hat, übernimmt nicht noch einmal', () {
    final t = trail(
      details: const [TrailDetails(trailId: 't', userId: 'me')],
    );
    expect(needsTakeOver(t), isFalse);
  });
}
