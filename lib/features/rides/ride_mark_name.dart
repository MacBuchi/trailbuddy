// Der Vorschlag für den Namen beim Tipp auf „Trail endet" (#486), pur.
//
// Wer unterwegs markiert, soll gleich danach sagen können, wie der Trail
// heißt — am Abend weiß er es bei fünf Stücken nicht mehr. Kennt die App
// die Strecke schon, schlägt sie den Namen vor: aus dem sichtbaren Netz
// (eigene und Buddy-Trails, nichts anderes, A2/A4) oder von einem Stück,
// das in DIESER Fahrt schon über dieselbe Strecke markiert und benannt
// wurde (zweimal gefahren). Gerechnet auf dem Gerät, ohne Netz (A8), mit
// denselben Regeln wie das Zerlege-Blatt.

import 'package:latlong2/latlong.dart';

import '../../core/line_geometry.dart';
import '../../models/trail.dart';
import '../trails/gpx.dart';
import '../trails/trail_geometry.dart';
import 'ride_split.dart';
import 'ride_track.dart';

/// Woher der Vorschlag kommt — die Zeile darüber sagt es dem Fahrer.
enum MarkNameSource { network, earlierInRide }

typedef MarkNameSuggestion = ({String name, MarkNameSource source});

/// Der Vorschlag für das Stück, das die letzte Marke in [marks] schließt
/// (ein Ende); null, wenn die Strecke weder im Netz noch früher in der
/// Fahrt liegt. Ein Trail ohne Namen schlägt nichts vor.
MarkNameSuggestion? suggestMarkName({
  required List<RidePoint> points,
  required List<RideMark> marks,
  required List<Trail> trails,
}) {
  final folded = foldRideMarks(marks);
  if (folded.isEmpty || folded.last.kind != RideMarkKind.end) return null;
  final kept = [
    for (final p in points)
      if (p.accuracyM <= kSplitMaxAccuracyM) TrackPoint(p.lat, p.lng, time: p.at),
  ];
  final ranges = markedRanges(kept, folded);
  if (ranges.isEmpty) return null;
  final current = ranges.last;
  final latLng = [for (final p in kept) LatLng(p.lat, p.lon)];
  final slice = latLng.sublist(current.from, current.to + 1);
  if (slice.length < 2) return null;

  // 1. Das Netz: dieselbe Deckung wie „bekannt" im Blatt.
  final proj = FlatProjection.around(slice);
  final xy = proj.line(slice);
  final lengthM = trackLengthM(kept.sublist(current.from, current.to + 1));
  if (lengthM > 0) {
    final known = [...knownTrailSectionsOf(slice, trails, proj: proj, xy: xy)]
      ..sort((a, b) => b.lengthM.compareTo(a.lengthM));
    for (final k in known) {
      final name = k.trail.name;
      if (name != null && k.lengthM / lengthM >= kMatchCoverage) {
        return (name: name, source: MarkNameSource.network);
      }
    }
  }

  // 2. Früher in dieser Fahrt, benannt, über dieselbe Strecke.
  for (final r in ranges.reversed.skip(1)) {
    final name = r.name;
    if (name == null) continue;
    final other = proj.line(latLng.sublist(r.from, r.to + 1));
    if (sameStretch(xy, other)) return (name: name, source: MarkNameSource.earlierInRide);
  }
  return null;
}
