import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../../l10n/l10n.dart';
import '../../models/trail.dart';
import 'map_view/map_hit_test.dart' show kMercatorMaxLat;
import 'map_view/map_view.dart';

const kTrailDetailZoom = 12.0;
const _cellSize = 64.0;
const _markerSize = 48.0;

class TrailHotspot {
  const TrailHotspot(this.center, this.counts, this.count);

  final LatLng center;
  // S0 to S5, followed by trails without a grade.
  final List<int> counts;
  final int count;
}

/// A world-anchored grid in 256-pixel Web Mercator zoom levels. Camera
/// movement within a zoom band can reuse the same markers and hit targets.
class TrailHotspotCache {
  List<Trail>? _trails;
  int? _zoom;
  List<MapViewMarker> _markers = const [];

  List<MapViewMarker> markers(List<Trail> trails, double zoom) {
    final band = zoom.floor();
    if (_zoom == band && listEquals(_trails, trails)) return _markers;
    _zoom = band;
    _trails = trails;
    final cellsAcross = (256 ~/ _cellSize) * (1 << band.clamp(0, 19));
    final counts = <(int, int), List<int>>{};
    final centers = <(int, int), LatLng>{};
    for (final trail in trails) {
      if (trail.pending || trail.points.length < 2) continue;
      final start = trail.start;
      final lat = start.latitude.clamp(-kMercatorMaxLat, kMercatorMaxLat);
      final sin = math.sin(lat * math.pi / 180);
      final x = (start.longitude + 180) / 360 * cellsAcross;
      final y =
          (0.5 - math.log((1 + sin) / (1 - sin)) / (4 * math.pi)) * cellsAcross;
      final cell = (x.floor(), y.floor());
      final grades = counts.putIfAbsent(cell, () => List.filled(7, 0));
      grades[trail.grade?.clamp(0, 5) ?? 6]++;
      centers.putIfAbsent(cell, () => start);
    }
    return _markers = [
      for (final MapEntry(key: cell, value: grades) in counts.entries)
        _marker(cell, cellsAcross, grades, centers[cell]!),
    ];
  }
}

MapViewMarker _marker(
  (int, int) cell,
  int cellsAcross,
  List<int> counts,
  LatLng focus,
) {
  final (x, y) = cell;
  final mercator = math.pi * (1 - 2 * (y + 0.5) / cellsAcross);
  final point = LatLng(
    (2 * math.atan(math.exp(mercator)) - math.pi / 2) * 180 / math.pi,
    (x + 0.5) / cellsAcross * 360 - 180,
  );
  final hotspot = TrailHotspot(
    focus,
    List.unmodifiable(counts),
    counts.fold(0, (total, count) => total + count),
  );
  return MapViewMarker(
    key: ValueKey(('trail-hotspot', cellsAcross, cell)),
    point: point,
    width: _markerSize,
    height: _markerSize,
    hitValue: hotspot,
    child: _HotspotBadge(hotspot),
  );
}

class _HotspotBadge extends StatelessWidget {
  const _HotspotBadge(this.hotspot);

  final TrailHotspot hotspot;

  @override
  Widget build(BuildContext context) {
    const palette = AppColors.light;
    return Semantics(
      label: context.l10n.trailHotspotCount(hotspot.count),
      excludeSemantics: true,
      child: CustomPaint(
        painter: _Ring(hotspot, palette.surface),
        child: Center(
          child: SizedBox(
            width: 32,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${hotspot.count}',
                style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Ring extends CustomPainter {
  const _Ring(this.hotspot, this.surface);

  final TrailHotspot hotspot;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(center, radius, Paint()..color = surface);
    final arc = Rect.fromCircle(center: center, radius: radius - 4);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    final segmented = hotspot.counts.where((count) => count > 0).length > 1;
    var angle = -math.pi / 2;
    for (var i = 0; i < hotspot.counts.length; i++) {
      final sweep = 2 * math.pi * hotspot.counts[i] / hotspot.count;
      if (sweep == 0) continue;
      paint.color = AppColors.mapGrades.of(i == 6 ? null : i);
      final gap = segmented ? math.min(0.05, sweep / 3) : 0.0;
      final start = angle + gap / 2;
      final length = sweep - gap;
      // S3–S5 share one color on the map. Keep their segments distinct
      // even when only one of the three grades is present.
      final dash = switch (i) {
        4 => 0.22,
        5 => 0.08,
        _ => length,
      };
      for (var offset = 0.0; offset < length; offset += dash + 0.1) {
        canvas.drawArc(
          arc,
          start + offset,
          math.min(dash, length - offset),
          false,
          paint,
        );
      }
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(_Ring oldDelegate) =>
      hotspot != oldDelegate.hotspot || surface != oldDelegate.surface;
}
