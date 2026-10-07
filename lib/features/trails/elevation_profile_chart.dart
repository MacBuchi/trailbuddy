import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import 'trail_elevation.dart';

/// Das Höhenprofil im Trail-Blatt: Fläche unter der Linie, Höhe links,
/// Strecke unten. Eigene Zeichnung statt Diagramm-Paket — es ist EIN
/// Linienzug, und ein Paket brächte Achsen, Legenden und Gesten mit, die
/// hier niemand braucht.
///
/// Die Zahlen daneben stehen als Text im Baum (Semantics), nicht nur im
/// Bild: Ein Bildschirmleser liest „Höhenprofil, 1 240 bis 820 Meter".
///
/// [compact] (#234, Ergebnis des Planers): niedriger und ohne die Zeile
/// „Start … km" darunter — die Länge steht dort schon in der Summe, und
/// das Profil zählt die Anschlüsse an Start und Ziel mit, die Summe nicht.
/// Zwei verschiedene Längen übereinander läsen sich wie ein Fehler.
class ElevationProfileChart extends StatelessWidget {
  const ElevationProfileChart(this.profile, {super.key, this.height = 96, this.compact = false});

  /// Höhe der Zeichnung in der kompakten Form.
  static const compactHeight = 64.0;

  final ElevationProfile profile;
  final double height;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.labelSmall;
    final muted = theme.colorScheme.onSurfaceVariant;
    final top = profile.maxM.round();
    final bottom = profile.minM.round();
    return Semantics(
      label: 'Höhenprofil, von ${profile.startM.round()} auf '
          '${profile.endM.round()} Meter, höchster Punkt $top, tiefster $bottom',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: compact ? compactHeight : height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 44,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    // Verkleinert statt überzulaufen: In der kompakten Form
                    // und mit großer Systemschrift passen zwei Zeilen sonst
                    // nicht neben die Zeichnung.
                    children: [
                      for (final t in ['$top m', '$bottom m'])
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(t, style: small?.copyWith(color: muted)),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: CustomPaint(
                    key: const ValueKey('elevation-profile'),
                    painter: ElevationProfilePainter(
                      profile,
                      line: AppPalette.of(context).map.mine,
                      fill: AppPalette.of(context).map.mine.withValues(alpha: 0.18),
                      grid: theme.colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!compact)
            Padding(
              padding: const EdgeInsets.only(left: 50, top: 2),
              child: Row(
                children: [
                  Text('Start', style: small?.copyWith(color: muted)),
                  const Spacer(),
                  Text(_km(profile.lengthM), style: small?.copyWith(color: muted)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _km(double m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';
}

/// Öffentlich für den Test: Er prüft die Abbildung, nicht die Pixel.
class ElevationProfilePainter extends CustomPainter {
  ElevationProfilePainter(this.profile,
      {required this.line, required this.fill, required this.grid});

  final ElevationProfile profile;
  final Color line;
  final Color fill;
  final Color grid;

  /// Die Punkte der Linie in Zeichenkoordinaten. Ein Trail, der kaum
  /// Höhe hat, wird nicht auf volle Höhe gestreckt: Mindestens 20 m
  /// Spanne, sonst sähe ein flacher Verbinder wie eine Steilwand aus.
  List<Offset> pointsFor(Size size) {
    final span = profile.maxM - profile.minM;
    final minSpan = span < 20 ? 20.0 : span;
    final base = profile.minM - (minSpan - span) / 2;
    return [
      for (var i = 0; i < profile.distM.length; i++)
        Offset(
          profile.distM[i] / profile.lengthM * size.width,
          size.height - (profile.eleM[i] - base) / minSpan * size.height,
        ),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final pts = pointsFor(size);
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), gridPaint);
    canvas.drawLine(Offset.zero, Offset(size.width, 0), gridPaint);
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    final area = Path.from(path)
      ..lineTo(pts.last.dx, size.height)
      ..lineTo(pts.first.dx, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(ElevationProfilePainter old) =>
      old.profile != profile || old.line != line || old.fill != fill || old.grid != grid;
}
