import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../map/map_view/map_view.dart';
import 'route_band_geometry.dart';

/// Breite des Bands und seines Rands (je Seite), in Bildpunkten.
const kRouteBandWidth = 12.0;
const kRouteEdgeWidth = 1.5;

/// Deckkraft in der Vorschau (Runde, Weg zum Trail) und in der
/// Folgeansicht: die kommenden 500 Routenmeter verblassen.
const kRoutePreviewOpacity = 0.55;
const kRouteFollowOpacity = 0.90;
const kRouteFarOpacity = 0.35;
const kRouteFadeM = 500.0;
double routeOpacityAt(double aheadM) =>
    kRouteFollowOpacity +
    (kRouteFarOpacity - kRouteFollowOpacity) *
        (aheadM / kRouteFadeM).clamp(0, 1);

/// Abstand der Pfeile und ihr Versatz nach rechts auf doppelten Stücken.
const kRouteArrowSpacing = 90.0;
const kRouteArrowOffset = 4.0;

/// Höhe eines Pfeils: zwei versetzte passen nebeneinander ins Band.
const kRouteArrowSize = 12.0;

/// Ein Abschnitt der Route mit dem, was die Vorschau über ihn weiß: ob er
/// über einen Wanderweg führt (gestrichelte Mittellinie) und was ein
/// Tipp auf ihn meldet (ein Zwischenpunkt, #234).
typedef RouteBandPiece = ({List<LatLng> points, bool hiking, Object? hitValue});

Iterable<BandRange> _visible(
  double start,
  double end,
  List<BandRange> gaps,
) sync* {
  for (final gap in gaps) {
    if (gap.end <= start) continue;
    if (gap.start >= end) break;
    if (gap.start > start) yield (start: start, end: gap.start);
    start = math.max(start, gap.end);
  }
  if (start < end) yield (start: start, end: end);
}

/// Generate visible passages in original route metres. The two engines
/// consume identical clipped geometry, including at self-intersections.
List<MapViewPolyline> routeBandLines(
  List<LatLng> points, {
  required double opacity,
  double zoom = 16,
  double? alongM,
  List<RouteBandPiece> pieces = const [],
}) {
  final geometry = RouteBandGeometry.of(points);
  if (geometry == null) return const [];
  final route = geometry.route, length = route.lengthM;
  final start = (alongM ?? 0).clamp(0.0, length);
  final gaps = geometry.hidden(start, zoom);
  final lines = <MapViewPolyline>[];
  const blockM = 2000.0;
  if (start > 0) {
    for (final r in _visible(
      0,
      start,
      geometry.hidden(start, zoom, history: true),
    )) {
      var a = r.start;
      while (a < r.end) {
        final block = (a / blockM).floor();
        final b = math.min(r.end, (block + 1) * blockM);
        lines.add(
          MapViewPolyline(
            points: geometry.slice(a, b, cache: b != start),
            color: AppColors.routeEdge.withValues(alpha: 0.25),
            width: 3,
            pass: -100000 - block,
          ),
        );
        a = b;
      }
    }
  }
  for (final range in _visible(start, length, gaps)) {
    var a = range.start;
    while (a < range.end) {
      final fading = alongM != null && a < start + kRouteFadeM;
      // 32 steps: adjacent alpha values differ by less than 2%.
      final step = fading
          ? math.min(32, ((a - start) * 32 / kRouteFadeM + 1e-8).floor() + 1)
          : 0;
      final next = fading
          ? start + step * kRouteFadeM / 32
          : ((a / blockM).floor() + 1) * blockM;
      final b = math.min(next, range.end);
      if (b <= a) break;
      lines.add(
        MapViewPolyline(
          points: geometry.slice(
            a,
            b,
            cache: !fading && (alongM == null || a != start),
          ),
          width: kRouteBandWidth,
          borderWidth: kRouteEdgeWidth,
          color: AppColors.routeBand,
          borderColor: AppColors.routeEdge,
          buttEnds: true,
          pass: 10 + (a / blockM).floor(),
          endOpacity: fading ? routeOpacityAt(b - start) : null,
          opacity: alongM == null
              ? opacity
              : fading
              ? routeOpacityAt(a - start)
              : kRouteFarOpacity,
        ),
      );
      a = b;
    }
  }
  // Match sections in itinerary order, even on a repeated leg.
  var cursor = 0;
  final hits = <MapViewPolyline>[];
  for (final piece in pieces) {
    if (piece.points.length < 2) continue;
    var i = cursor;
    while (i < route.points.length && route.points[i] != piece.points.first) {
      i++;
    }
    if (i == route.points.length) continue;
    final from = route.cumM[i];
    for (final p in piece.points.skip(1)) {
      if (i + 1 < route.points.length && route.points[i + 1] == p) i++;
    }
    cursor = i;
    if (!piece.hiking && piece.hitValue == null) continue;
    for (final r in _visible(from, route.cumM[i], gaps)) {
      final pts = geometry.slice(r.start, r.end, cache: true);
      if (piece.hiking) {
        lines.add(
          MapViewPolyline(
            points: pts,
            color: AppColors.routeEdge,
            width: 2,
            dash: const [6, 6],
            opacity: opacity,
            pass: 2,
          ),
        );
      }
      if (piece.hitValue != null) {
        hits.add(
          MapViewPolyline(
            points: pts,
            color: AppColors.routeBand,
            width: 0,
            hitValue: piece.hitValue,
            pass: 4,
          ),
        );
      }
    }
  }
  final arrowGaps = geometry.hidden(start, zoom, shared: false);
  final shared = geometry.sharedAhead(start);
  // Long arrow features are divided at whole multiples of their spacing.
  // A fix then replaces just the active part of the arrow source.
  final metresPerPixel =
      156543.03392 *
      math.cos(route.points.first.latitude * math.pi / 180) /
      math.pow(2, zoom);
  final arrowBlock = math.max(1.0, metresPerPixel * kRouteArrowSpacing * 32);
  void arrows(double from, double to, bool twice) {
    for (final r in _visible(from, to, arrowGaps)) {
      var a = r.start;
      while (a < r.end) {
        final block = (a / arrowBlock + 1e-10).floor();
        final b = math.min(r.end, (block + 1) * arrowBlock);
        if (b <= a) break;
        lines.add(
          MapViewPolyline(
            points: geometry.slice(a, b, cache: a != start || start == 0),
            color: AppColors.routeArrow,
            width: 0,
            pass: -10 - block,
            arrows: LineArrows(
              color: AppColors.routeArrow,
              spacing: kRouteArrowSpacing,
              offset: twice ? kRouteArrowOffset : 0,
              size: kRouteArrowSize,
            ),
          ),
        );
        a = b;
      }
    }
  }

  var at = start;
  for (final r in shared) {
    arrows(at, r.start, false);
    arrows(r.start, r.end, true);
    at = r.end;
  }
  arrows(at, length, false);
  return [...lines, ...hits.reversed];
}
