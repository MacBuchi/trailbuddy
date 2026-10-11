// Ein Neuladen behält, was gleich geblieben ist — als dasselbe Objekt
// (`trail_sharing.dart`, Feldbericht 2026-10-02). Daran hängen die
// Zwischenspeicher von Karte, Höhenprofil und Blatt.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/data/trail_cache.dart';
import 'package:trailbuddy/data/trail_sharing.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/trail.dart';
import 'package:trailbuddy/models/trail_merge.dart';

TrailRecording rec(String trailId, {double lat = 48, List<double>? ele}) => TrailRecording(
      id: 'r-$trailId',
      trailId: trailId,
      userId: 'me',
      source: RecordingSource.import,
      recordedAt: null,
      reversed: false,
      quality: 0.4,
      createdAt: DateTime.utc(2026, 1, 1),
      // Je Aufruf eine NEUE Liste, wie nach einem Abruf.
      points: [LatLng(lat, 9), LatLng(lat + 0.01, 9)],
      lengthM: 1100,
      ele: ele,
    );

TrailSnapshot snap({int rating = 3, double lat = 48}) => (
      recordings: [rec('a'), rec('b', lat: lat, ele: [500, 450])],
      details: [
        TrailDetails(trailId: 'a', userId: 'me', name: 'Hang', rating: rating, traits: {TrailTrait.flowy}),
        const TrailDetails(trailId: 'b', userId: 'me', name: 'Wald'),
      ],
      notes: [TrailNote(id: 'n1', trailId: 'b', userId: 'me', body: 'Baum', createdAt: DateTime.utc(2026, 9, 1))],
      reports: <TrailReport>[],
      merges: <TrailMerge>[],
    );

List<Trail> trailsOf(TrailSnapshot s, [List<Trail> previous = const []]) => buildTrails(
      recordings: s.recordings,
      details: s.details,
      notes: s.notes,
      reports: s.reports,
      myId: 'me',
      previous: previous,
    );

void main() {
  test('gleiche Zeilen bleiben dieselben Objekte, geänderte nicht', () {
    final first = snap();
    final second = shareSnapshot(first, snap(rating: 5));
    expect(second.recordings[0], same(first.recordings[0]));
    expect(second.recordings[1], same(first.recordings[1]));
    expect(second.details[1], same(first.details[1]));
    expect(second.notes[0], same(first.notes[0]));
    expect(second.details[0], isNot(same(first.details[0])), reason: 'der Stern hat sich geändert');
    expect(second.details[0].rating, 5);
    expect(sameSnapshot(first, second), isFalse);
    expect(sameSnapshot(second, shareSnapshot(second, snap(rating: 5))), isTrue,
        reason: 'nichts geändert ⇒ derselbe Stand, die Kopie bleibt liegen');
  });

  test('eine verschobene Linie oder andere Höhen sind eine andere Aufzeichnung', () {
    expect(sameRecording(rec('b'), rec('b')), isTrue);
    expect(sameRecording(rec('b'), rec('b', lat: 48.0001)), isFalse);
    expect(sameRecording(rec('b', ele: [1, 2]), rec('b', ele: [1, 3])), isFalse);
    expect(sameRecording(rec('b', ele: [1, 2]), rec('b')), isFalse);
  });

  test('ein unveränderter Trail kommt als derselbe Trail zurück — samt Höhenprofil', () {
    final s1 = snap();
    final t1 = trailsOf(s1);
    final b1 = t1.firstWhere((t) => t.id == 'b');
    expect(b1.elevation, isNotNull);
    final s2 = shareSnapshot(s1, snap(rating: 5));
    final t2 = trailsOf(s2, t1);
    expect(t2.firstWhere((t) => t.id == 'b'), same(b1));
    final a2 = t2.firstWhere((t) => t.id == 'a');
    expect(a2, isNot(same(t1.firstWhere((t) => t.id == 'a'))));
    expect(a2.rating, 5);
    expect(a2.points, same(t1.firstWhere((t) => t.id == 'a').points),
        reason: 'die Linie ist dieselbe Liste — Karte und MapLibre übertragen nichts neu');
  });

  test('ohne Vorstand und für ein anderes Konto wird nichts übernommen', () {
    final s = snap();
    expect(shareSnapshot(null, s), same(s));
    final mine = trailsOf(s);
    final other = buildTrails(recordings: s.recordings, details: s.details, myId: 'other', previous: mine);
    expect(other.first, isNot(same(mine.first)));
  });
}
