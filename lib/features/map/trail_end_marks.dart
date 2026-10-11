// Anfang und Richtung eines Trails auf der Karte (#96): am Anfang eine
// Scheibe in der Trail-Farbe mit weißem Pfeil in Fahrtrichtung, mit
// weißem Saum wie die Linie, klein (14 px), NICHT antippbar: Ein Tipp
// dort trifft die Linie ohnehin (12 px Toleranz), und ein zweiter Treffer
// je Trail machte die Marker-Liste zweideutig.
//
// Das Quadrat am Ende ist seit 0.74.2 weg (#179, Feldbericht: „überflüssig
// und eher störend"): Wo der Trail endet, sagt die Linie selbst, und der
// Pfeil am Anfang trägt die Richtung.
//
// Bewusst kein Pin und keine Fahne: Die Fahne gehört dem Marken-Knopf
// der Aufnahme (Design 6), eine Nadel den Orten. Gezeichnet, nicht als
// Symbolschrift — die Pfeilform in Barlow fehlt, und ein Glyph ließe sich
// nicht auf die Peilung drehen.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

/// Kantenlänge der Marke auf der Karte (Bildpunkte).
const kTrailMarkSize = 14.0;

/// Die Startmarke: Scheibe mit Pfeil, gedreht auf [bearingDeg] (0 = Nord,
/// im Uhrzeigersinn wie ein Kompass).
class TrailStartDot extends StatelessWidget {
  const TrailStartDot({super.key, required this.color, required this.bearingDeg});

  final Color color;
  final double bearingDeg;

  @override
  Widget build(BuildContext context) => Semantics(
        label: context.l10n.mapTrailStart,
        child: CustomPaint(
          size: const Size.square(kTrailMarkSize),
          painter: _StartPainter(color, bearingDeg),
        ),
      );
}

class _StartPainter extends CustomPainter {
  const _StartPainter(this.color, this.bearingDeg);

  final Color color;
  final double bearingDeg;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = Colors.white);
    canvas.drawCircle(c, r - 1.5, Paint()..color = color);
    // Der Pfeil: Spitze voraus, Basis hinten, gedreht auf die Peilung.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(bearingDeg * math.pi / 180);
    final path = Path()
      ..moveTo(0, -r * 0.62)
      ..lineTo(r * 0.5, r * 0.3)
      ..lineTo(0, r * 0.08)
      ..lineTo(-r * 0.5, r * 0.3)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StartPainter old) => old.color != color || old.bearingDeg != bearingDeg;
}
