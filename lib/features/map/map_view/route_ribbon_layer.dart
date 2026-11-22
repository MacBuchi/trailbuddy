// Paint a connected route as a single stroke with round joins. Apply the
// distance fade to the finished edge and fill together: individual bordered
// polylines would draw transverse edges at every colour stop.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'map_view.dart';

class RouteRibbonLayer extends StatelessWidget {
  const RouteRibbonLayer(this.lines, {super.key});
  final List<MapViewPolyline> lines;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return IgnorePointer(
      child: MobileLayerTransformer(
        child: CustomPaint(
          size: camera.size,
          painter: _RibbonPainter(lines, camera),
        ),
      ),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  _RibbonPainter(this.lines, this.camera);
  final List<MapViewPolyline> lines;
  final MapCamera camera;

  @override
  void paint(Canvas canvas, Size size) {
    final viewport = Offset.zero & size;
    for (var i = 0; i < lines.length;) {
      final first = i++;
      while (i < lines.length &&
          lines[i - 1].points.last == lines[i].points.first) {
        i++;
      }
      _paintPass(canvas, viewport, lines.getRange(first, i));
    }
  }

  void _paintPass(
    Canvas canvas,
    Rect viewport,
    Iterable<MapViewPolyline> pass,
  ) {
    final style = pass.first;
    final width = style.width + 2 * style.borderWidth;
    final path = Path();
    final segments = <(List<Offset>, double, double)>[];
    for (final line in pass) {
      final pts = line.points.map(camera.getOffsetFromOrigin).toList();
      if (segments.isEmpty) path.moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      segments.add((pts, line.opacity, line.endOpacity ?? line.opacity));
    }
    final bounds = path.getBounds().inflate(width).intersect(viewport);
    if (bounds.isEmpty) return;
    final faded = segments.any(
      (s) => s.$2 != style.opacity || s.$3 != style.opacity,
    );
    final white = Colors.white;
    canvas.saveLayer(
      bounds,
      Paint()..color = white.withValues(alpha: faded ? 1 : style.opacity),
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    if (style.borderColor case final edge?) {
      canvas.drawPath(
        path,
        stroke
          ..color = edge
          ..strokeWidth = width,
      );
    }
    canvas.drawPath(
      path,
      stroke
        ..color = style.color
        ..strokeWidth = style.width,
    );
    if (faded) {
      // The mask is intentionally wider than the stroke. Its only visible
      // contribution is opacity; its caps and joins cannot leave hairlines.
      canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.dstIn);
      final mask = Paint()
        ..strokeWidth = width + 4
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.src;
      for (final (points, start, end) in segments) {
        final lengths = [
          for (var i = 1; i < points.length; i++)
            (points[i] - points[i - 1]).distance,
        ];
        final total = lengths.fold(0.0, (sum, len) => sum + len);
        if (total == 0) continue;
        var walked = 0.0;
        for (var i = 0; i < lengths.length; i++) {
          final a = points[i], b = points[i + 1];
          final from = ui.lerpDouble(start, end, walked / total)!;
          walked += lengths[i];
          if (lengths[i] == 0 ||
              !Rect.fromPoints(a, b).inflate(width).overlaps(bounds))
            continue;
          final to = ui.lerpDouble(start, end, walked / total)!;
          mask.shader = from == to
              ? null
              : ui.Gradient.linear(a, b, [
                  white.withValues(alpha: from),
                  white.withValues(alpha: to),
                ]);
          mask.color = white.withValues(alpha: from == to ? from : 1);
          canvas.drawLine(a, b, mask);
          mask.shader?.dispose();
        }
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RibbonPainter oldDelegate) =>
      oldDelegate.camera != camera || oldDelegate.lines != lines;
}
