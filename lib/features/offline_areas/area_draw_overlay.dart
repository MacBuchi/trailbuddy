// Die Zeichenfläche über der Karte (Offline-Karten, Stufe C): liegt nur
// dort, solange ein Werkzeug auf den nächsten Strich wartet, fängt dann
// JEDE Berührung ab (die Karte darunter steht still — sonst verschöbe der
// Strich die Karte, die er gerade beschreibt) und meldet den fertigen
// Strich als Kacheln. Danach ist das Werkzeug weg und die Karte wieder
// frei (area_draw.dart).
//
// Gerechnet wird mit der Kamera vom letzten Stillstand: Während die
// Fläche liegt, kann sich die Karte nicht bewegen, die Kamera stimmt
// also. Die Umrechnung ist die der Trefferprüfung (map_hit_test.dart),
// auf beiden Engines dieselbe.
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../core/app_colors.dart';
import '../../l10n/l10n.dart';
import '../map/map_view/map_hit_test.dart';
import '../map/map_view/map_view.dart';
import 'area_draw.dart';

/// Ein Punkt kommt erst dazu, wenn der Finger so weit gewandert ist —
/// sonst hätte ein langsamer Strich tausende Punkte.
const kAreaStrokeStepPx = 4.0;

class AreaDrawOverlay extends StatefulWidget {
  const AreaDrawOverlay({
    super.key,
    required this.camera,
    required this.tool,
    this.onStroke,
    this.onRing,
    this.hint,
  }) : assert(onStroke != null || onRing != null);

  final MapViewCamera camera;
  final AreaDrawTool tool;

  /// Die Kacheln des Strichs — null, wenn er zu groß war.
  final void Function(Set<int>? keys)? onStroke;

  /// Der Strich selbst als geschlossener Ring in Grad — für den Planer,
  /// der damit Trails wählt (seit 0.74.0), statt Kacheln.
  final void Function(List<LatLng> ring)? onRing;

  /// Die Zeile oben; ohne: die der Bereiche.
  final String? hint;

  @override
  State<AreaDrawOverlay> createState() => _AreaDrawOverlayState();
}

class _AreaDrawOverlayState extends State<AreaDrawOverlay> {
  final _points = <Offset>[];

  void _add(Offset p) {
    if (_points.isEmpty || (p - _points.last).distance >= kAreaStrokeStepPx) {
      setState(() => _points.add(p));
    }
  }

  void _end() {
    final pts = List.of(_points);
    setState(_points.clear);
    if (pts.length < 2) return;
    final ring = [for (final p in pts) unprojectFromScreen(widget.camera, p)];
    if (widget.onRing != null) {
      widget.onRing!(ring);
    } else {
      widget.onStroke!(tilesTouchedByRing(ring));
    }
  }

  @override
  Widget build(BuildContext context) {
    final add = widget.tool == AreaDrawTool.add;
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          key: const ValueKey('area-draw-surface'),
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _add(d.localPosition),
          onPanUpdate: (d) => _add(d.localPosition),
          onPanEnd: (_) => _end(),
          onPanCancel: () => setState(_points.clear),
          child: CustomPaint(
            painter: _StrokePainter(
              List.of(_points),
              // Die Regel der Kacheln (Turn 2): dazu hell, weg dunkel.
              color: add ? kAreaInkLight : kAreaInkDark,
            ),
          ),
        ),
        IgnorePointer(
          child: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              // Eine Zeile, was der nächste Strich tut (Design 3e) — nur
              // solange ein Werkzeug scharf ist.
              child: Container(
                key: const ValueKey('area-draw-hint'),
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: AppPalette.of(context).surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppPalette.of(context).line),
                  boxShadow: const [
                    BoxShadow(blurRadius: 6, offset: Offset(0, 2), color: Color(0x33000000)),
                  ],
                ),
                child: Text(
                  widget.hint ??
                      (add ? context.l10n.areaDrawHintAdd : context.l10n.areaDrawHintRemove),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.points, {required this.color});

  final List<Offset> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    // Geschlossen gezeigt, wie er gerechnet wird: Ende zum Anfang.
    final closed = Path.from(path)..close();
    canvas.drawPath(closed, Paint()..color = color.withValues(alpha: 0.15));
    // Darunter ein Saum in der Gegenhelligkeit: Der Strich läuft über
    // Abgedunkeltes UND Helles und soll auf beidem stehen.
    final halo = color.computeLuminance() > 0.5 ? kAreaInkDark : kAreaInkLight;
    for (final (c, w) in [(halo.withValues(alpha: 0.6), 5.0), (color, 3.0)]) {
      canvas.drawPath(
        path,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_StrokePainter old) => old.points.length != points.length || old.color != color;
}
