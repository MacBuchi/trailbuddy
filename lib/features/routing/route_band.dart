// Wie eine geplante Route auf der Karte liegt (#295, Betreiber
// 2026-10-11: „B+"): ein Band in Lime mit einem Rand in Moos, beide
// zusammen halb durchsichtig, unter dem Netz — Trails auf der Route
// behalten ihre Farbe (Design 7). Ein Stück, das die Route zweimal
// fährt (hin und zurück), liegt dichter: Es wird ein zweites Mal
// gezeichnet. Eine Linie mischt sich nicht mit sich selbst, deshalb
// erkennt [repeatedSegments] die Wiederholungen an den Punkten — die
// Engine baut die Route aus Kanten, und dieselbe Kante bringt dieselben
// Punkte mit. Das gilt auch für eine Route aus „Meine Fahrten", die
// keinen Graphen mehr kennt. Pur, ohne Flutter-Widgets.
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../map/map_view/map_view.dart';

/// Breite des Bands und seines Rands (je Seite), in Bildpunkten.
const kRouteBandWidth = 12.0;
const kRouteEdgeWidth = 1.5;

/// Deckkraft in der Vorschau (Runde, Weg zum Trail) und in der
/// Folgeansicht. 70 % statt 80 % ist am Gerät in der Sonne zu prüfen.
const kRoutePreviewOpacity = 0.55;
const kRouteFollowOpacity = 0.8;

/// Abstand der Pfeile und ihr Versatz nach rechts auf doppelten Stücken.
const kRouteArrowSpacing = 90.0;
const kRouteArrowOffset = 4.0;

/// Höhe eines Pfeils: zwei versetzte passen nebeneinander ins Band.
const kRouteArrowSize = 12.0;

/// Ein Abschnitt der Route mit dem, was die Vorschau über ihn weiß: ob er
/// über einen Wanderweg führt (gestrichelte Mittellinie) und was ein
/// Tipp auf ihn meldet (ein Zwischenpunkt, #234).
typedef RouteBandPiece = ({List<LatLng> points, bool hiking, Object? hitValue});

/// Je Segment (Punkt i bis i+1) der Linie: Liegt dasselbe Segment — in
/// welcher Richtung auch immer — schon früher auf der Linie?
List<bool> repeatedSegments(List<LatLng> points) {
  final seen = <(int, int, int, int)>{};
  return [
    for (var i = 0; i + 1 < points.length; i++) !seen.add(_segmentKey(points[i], points[i + 1])),
  ];
}

/// Je Segment: Liegt es mehr als einmal auf der Linie (die erste Fahrt
/// eingeschlossen)?
List<bool> doubledSegments(List<LatLng> points) {
  final count = <(int, int, int, int), int>{};
  final keys = [for (var i = 0; i + 1 < points.length; i++) _segmentKey(points[i], points[i + 1])];
  for (final k in keys) {
    count[k] = (count[k] ?? 0) + 1;
  }
  return [for (final k in keys) count[k]! > 1];
}

/// Auf rund 10 cm gerastert, ohne Richtung.
(int, int, int, int) _segmentKey(LatLng a, LatLng b) {
  final ka = ((a.latitude * 1e6).round(), (a.longitude * 1e6).round());
  final kb = ((b.latitude * 1e6).round(), (b.longitude * 1e6).round());
  final aFirst = ka.$1 < kb.$1 || (ka.$1 == kb.$1 && ka.$2 <= kb.$2);
  return aFirst ? (ka.$1, ka.$2, kb.$1, kb.$2) : (kb.$1, kb.$2, ka.$1, ka.$2);
}

/// Die zusammenhängenden Stücke der Linie, deren Segmente [keep] erfüllen.
List<List<LatLng>> _runsWhere(List<LatLng> points, List<bool> keep) {
  final out = <List<LatLng>>[];
  List<LatLng>? run;
  for (var i = 0; i < keep.length; i++) {
    if (!keep[i]) {
      run = null;
      continue;
    }
    if (run == null) {
      run = [points[i]];
      out.add(run);
    }
    run.add(points[i + 1]);
  }
  return out;
}

/// Die Stücke gleicher Art (doppelt ja/nein) in Reihenfolge, für die Pfeile.
List<(List<LatLng>, bool)> _runsByFlag(List<LatLng> points, List<bool> flag) {
  final out = <(List<LatLng>, bool)>[];
  for (var i = 0; i < flag.length; i++) {
    if (out.isEmpty || out.last.$2 != flag[i]) out.add(([points[i]], flag[i]));
    out.last.$1.add(points[i + 1]);
  }
  return out;
}

/// Das Band einer Route, unten zuerst:
/// 1. jede Stelle EINMAL (die Wiederholungen ausgelassen),
/// 2. die Wiederholungen noch einmal, als zweite Zeichnung — dort mischt
///    sich das Band mit sich selbst und liegt dichter,
/// 3. Wanderweg-Stücke aus [pieces] als dünne gestrichelte Mittellinie,
/// 4. die Pfeile in Fahrtrichtung, auf doppelten Stücken nach rechts
///    versetzt, damit Hin und Zurück nebeneinander stehen,
/// 5. unsichtbare Tippziele der [pieces], die eins tragen.
List<MapViewPolyline> routeBandLines(
  List<LatLng> points, {
  required double opacity,
  List<RouteBandPiece> pieces = const [],
}) {
  if (points.length < 2) return const [];
  final repeated = repeatedSegments(points);
  final doubled = doubledSegments(points);
  MapViewPolyline band(List<LatLng> pts, int pass) => MapViewPolyline(
        points: pts,
        color: AppColors.routeBand,
        width: kRouteBandWidth,
        borderColor: AppColors.routeEdge,
        borderWidth: kRouteEdgeWidth,
        opacity: opacity,
        pass: pass,
      );
  return [
    for (final run in _runsWhere(points, [for (final r in repeated) !r])) band(run, 0),
    for (final run in _runsWhere(points, repeated)) band(run, 1),
    for (final p in pieces)
      if (p.hiking && p.points.length >= 2)
        MapViewPolyline(
          points: p.points,
          color: AppColors.routeEdge,
          width: 2,
          dash: const [6, 6],
          opacity: opacity,
          pass: 2,
        ),
    for (final (run, twice) in _runsByFlag(points, doubled))
      MapViewPolyline(
        points: run,
        color: AppColors.routeArrow,
        width: 0,
        opacity: opacity,
        pass: 3,
        arrows: LineArrows(
          color: AppColors.routeArrow,
          spacing: kRouteArrowSpacing,
          offset: twice ? kRouteArrowOffset : 0,
          size: kRouteArrowSize,
        ),
      ),
    for (final p in pieces)
      if (p.hitValue != null && p.points.length >= 2)
        MapViewPolyline(
          points: p.points,
          color: AppColors.routeBand,
          width: 0,
          opacity: opacity,
          pass: 4,
          hitValue: p.hitValue,
        ),
  ];
}
