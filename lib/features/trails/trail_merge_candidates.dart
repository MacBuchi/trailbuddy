// „Ist ein Duplikat von …" (#107, Konzept 6.1): welche Trails als Partner
// in Frage kommen, und welcher von zweien bleibt. Pur, ohne Widgets.
//
// „Grob beieinander" ist die Schwelle des Betreibers (2026-10-11):
// mindestens die Hälfte der kürzeren Linie höchstens 50 m neben der
// anderen — bewusst weiter als der 15-m-Korridor des Abgleichs, gemeint
// sind genau die Paare knapp daneben. Spiegel von `app_internal.merge_near`
// (Patch 019): dieselben Zahlen, dieselbe Abtastung, dieselbe Wahl der
// Linie (die beste sichtbare, `Trail.points`). Wer sie ändert, ändert
// beide; der Server prüft beim Zusammenführen noch einmal.
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../core/line_geometry.dart';
import '../../models/trail.dart';

/// Abstand, bis zu dem ein Punkt der kürzeren Linie „neben" der anderen
/// liegt (`merge_near`: `near_m`). Geschätzt, nicht gemessen.
const kMergeNearM = 50.0;

/// So viel der kürzeren Linie muss neben der anderen liegen
/// (`merge_near`: `near_share`). Geschätzt, nicht gemessen.
const kMergeNearShare = 0.5;

/// Welcher Anteil der KÜRZEREN der beiden Linien höchstens [kMergeNearM]
/// neben der anderen liegt — abgetastet alle [kMatchSampleStepM] Meter
/// wie im Abgleich. 0 für eine leere Linie.
double mergeNearShare(List<LatLng> a, List<LatLng> b) {
  if (a.length < 2 || b.length < 2) return 0;
  final proj = FlatProjection.around([...a, ...b]);
  final xa = proj.line(a), xb = proj.line(b);
  final (short, other) = _length(xa) <= _length(xb) ? (xa, xb) : (xb, xa);
  final samples = resampleXy(short, kMatchSampleStepM);
  return coverageWithin(samples, SegmentGrid([other], kMergeNearM), kMergeNearM);
}

double _length(List<math.Point<double>> xy) {
  var sum = 0.0;
  for (var i = 1; i < xy.length; i++) {
    sum += xy[i - 1].distanceTo(xy[i]);
  }
  return sum;
}

/// Ein Trail, der als Partner von „Ist ein Duplikat von …" in Frage
/// kommt, mit seinem Anteil ([mergeNearShare]).
typedef MergeCandidate = ({Trail trail, double share});

/// Die Partner für [trail] unter [all], der beste zuerst: sichtbar, nicht
/// wartend (ohne Server-Kennung gibt es nichts zusammenzuführen) und grob
/// beieinander. Ein Rahmen-Vorfilter hält die Rechnung bei großen Netzen
/// auf den Nachbarn.
List<MergeCandidate> mergeCandidates(Trail trail, Iterable<Trail> all) {
  if (trail.pending) return const [];
  final box = LatBox.of(trail.points);
  final out = <MergeCandidate>[];
  for (final t in all) {
    if (t.id == trail.id || t.pending) continue;
    if (!box.near(LatBox.of(t.points), kMergeNearM)) continue;
    final share = mergeNearShare(trail.points, t.points);
    if (share >= kMergeNearShare) out.add((trail: t, share: share));
  }
  return out
    ..sort((a, b) {
      final c = b.share.compareTo(a.share);
      return c != 0 ? c : a.trail.displayName.compareTo(b.trail.displayName);
    });
}

/// Wie viele Menschen an [t] sichtbar beitragen — Aufzeichnung oder
/// Beitrag.
int visibleContributors(Trail t) =>
    {for (final r in t.recordings) r.userId, for (final d in t.details) d.userId}.length;

/// Wann [t] angelegt wurde: seine älteste sichtbare Aufzeichnung.
DateTime firstSeen(Trail t) =>
    t.recordings.map((r) => r.createdAt).reduce((a, b) => a.isBefore(b) ? a : b);

/// Welcher von [a] und [b] bleibt, wenn der Nutzer nichts anderes wählt
/// (Betreiber, 2026-10-11): der mit mehr sichtbaren Beiträgen, bei
/// Gleichstand der ältere — dann bleibt, was die meisten schon kennen.
Trail defaultKeep(Trail a, Trail b) {
  final c = visibleContributors(a).compareTo(visibleContributors(b));
  if (c != 0) return c > 0 ? a : b;
  return firstSeen(b).isBefore(firstSeen(a)) ? b : a;
}
