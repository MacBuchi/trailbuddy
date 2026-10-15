import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../l10n/l10n.dart';
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
/// Statt dessen trägt die kompakte Form eine km-Skala ([axisTicks], #332):
/// Teilstriche sind keine Summe, sie widersprechen ihr nicht.
///
/// [onScrub] (#332): Tippen oder waagrecht Ziehen meldet die Stelle in
/// Metern ab Start; [cursorM] zeichnet sie als senkrechten Strich mit
/// Punkt und schreibt Strecke und Höhe dazu. Die Karte zeigt dieselbe
/// Stelle mit einem Symbol auf der Linie (`route_elevation.dart`).
class ElevationProfileChart extends StatelessWidget {
  const ElevationProfileChart(this.profile,
      {super.key, this.height = 96, this.compact = false, this.cursorM, this.onScrub});

  /// Höhe der Zeichnung in der kompakten Form.
  static const compactHeight = 64.0;

  final ElevationProfile profile;
  final double height;
  final bool compact;
  final double? cursorM;
  final ValueChanged<double>? onScrub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.labelSmall;
    final muted = theme.colorScheme.onSurfaceVariant;
    final top = profile.maxM.round();
    final bottom = profile.minM.round();
    return Semantics(
      label: context.l10n.elevationProfileSemantics(
          profile.startM.round(), profile.endM.round(), top, bottom),
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
                  child: LayoutBuilder(builder: (context, box) {
                    final paint = CustomPaint(
                      key: const ValueKey('elevation-profile'),
                      size: Size.infinite,
                      painter: ElevationProfilePainter(
                        profile,
                        line: AppPalette.of(context).map.mine,
                        fill: AppPalette.of(context).map.mine.withValues(alpha: 0.18),
                        grid: theme.colorScheme.outlineVariant,
                        ticksM: compact ? axisTicks(profile.lengthM) : const [],
                        cursorM: cursorM,
                        cursor: theme.colorScheme.onSurface,
                      ),
                    );
                    final cursor = cursorM;
                    final chart = cursor == null
                        ? paint
                        : Stack(fit: StackFit.expand, children: [
                            paint,
                            // Strecke und Höhe an der Stelle, oben in der
                            // Ecke, die der Strich nicht überdeckt.
                            Align(
                              alignment: cursor > profile.lengthM / 2 ? Alignment.topLeft : Alignment.topRight,
                              child: Text(
                                key: const ValueKey('elevation-cursor-label'),
                                '${_km(cursor)} · ${profile.eleAt(cursor).round()} m',
                                style: small?.copyWith(color: theme.colorScheme.onSurface),
                              ),
                            ),
                          ]);
                    final scrub = onScrub;
                    if (scrub == null) return chart;
                    void at(double x) => scrub((x / box.maxWidth).clamp(0.0, 1.0) * profile.lengthM);
                    return GestureDetector(
                      key: const ValueKey('elevation-scrub'),
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => at(d.localPosition.dx),
                      onHorizontalDragStart: (d) => at(d.localPosition.dx),
                      onHorizontalDragUpdate: (d) => at(d.localPosition.dx),
                      child: chart,
                    );
                  }),
                ),
              ],
            ),
          ),
          if (compact)
            Padding(
              padding: const EdgeInsets.only(left: 50, top: 2),
              child: _Axis(profile.lengthM, style: small?.copyWith(color: muted)),
            ),
          if (!compact)
            Padding(
              padding: const EdgeInsets.only(left: 50, top: 2),
              child: Row(
                children: [
                  Text(context.l10n.elevationStart, style: small?.copyWith(color: muted)),
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

/// Die Teilstriche der km-Skala in Metern ab Start, ohne die 0: der
/// kleinste glatte Schritt mit höchstens fünf Strichen. Ganze Kilometer
/// ab 1 km Schritt, darunter Meter — so braucht kein Strich ein Komma.
List<double> axisTicks(double lengthM) {
  const steps = [250.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0, 50000.0, 100000.0];
  final step = steps.firstWhere((s) => lengthM / s <= 5, orElse: () => steps.last);
  return [for (var m = step; m <= lengthM + 0.001; m += step) m];
}

/// Die Beschriftung unter den Teilstrichen; die Einheit steht nur am
/// letzten.
class _Axis extends StatelessWidget {
  const _Axis(this.lengthM, {this.style});

  final double lengthM;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final ticks = axisTicks(lengthM);
    final km = ticks.isNotEmpty && ticks.first >= 1000;
    String label(double m) => km ? '${(m / 1000).round()}' : '${m.round()}';
    return SizedBox(
      key: const ValueKey('elevation-axis'),
      height: 14,
      child: LayoutBuilder(builder: (context, box) {
        Widget at(double m, String text) {
          final x = m / lengthM * box.maxWidth;
          // Am rechten Rand rechtsbündig, sonst mittig unter dem Strich —
          // nie über den Rand hinaus.
          final right = x > box.maxWidth - 24;
          return Positioned(
            left: right ? null : (x - 20).clamp(0.0, box.maxWidth),
            right: right ? box.maxWidth - x : null,
            width: right ? null : 40,
            top: 0,
            child: Text(text, style: style, textAlign: x < 20 ? TextAlign.left : TextAlign.center, maxLines: 1),
          );
        }

        return Stack(clipBehavior: Clip.none, children: [
          at(0, '0'),
          for (final (i, m) in ticks.indexed)
            at(m, i == ticks.length - 1 ? '${label(m)} ${km ? 'km' : 'm'}' : label(m)),
        ]);
      }),
    );
  }
}

/// Öffentlich für den Test: Er prüft die Abbildung, nicht die Pixel.
class ElevationProfilePainter extends CustomPainter {
  ElevationProfilePainter(this.profile,
      {required this.line,
      required this.fill,
      required this.grid,
      this.ticksM = const [],
      this.cursorM,
      this.cursor = const Color(0xFF000000)});

  final ElevationProfile profile;
  final Color line;
  final Color fill;
  final Color grid;

  /// Teilstriche an der Grundlinie, Meter ab Start ([axisTicks]).
  final List<double> ticksM;

  /// Die gewählte Stelle (#332), Meter ab Start.
  final double? cursorM;
  final Color cursor;

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
    for (final m in ticksM) {
      final x = m / profile.lengthM * size.width;
      canvas.drawLine(Offset(x, size.height), Offset(x, size.height - 4), gridPaint);
    }
    final c = cursorM;
    if (c != null) {
      final p = pointAt(size, c);
      canvas.drawLine(Offset(p.dx, 0), Offset(p.dx, size.height), Paint()..color = cursor..strokeWidth = 1.5);
      canvas.drawCircle(p, 4.5, Paint()..color = cursor);
      canvas.drawCircle(p, 2.5, Paint()..color = line);
    }
  }

  /// Der Punkt der Linie an der Stelle [alongM] in Zeichenkoordinaten.
  Offset pointAt(Size size, double alongM) {
    final span = profile.maxM - profile.minM;
    final minSpan = span < 20 ? 20.0 : span;
    final base = profile.minM - (minSpan - span) / 2;
    return Offset(alongM / profile.lengthM * size.width,
        size.height - (profile.eleAt(alongM) - base) / minSpan * size.height);
  }

  @override
  bool shouldRepaint(ElevationProfilePainter old) =>
      old.profile != profile ||
      old.line != line ||
      old.fill != fill ||
      old.grid != grid ||
      old.cursorM != cursorM ||
      old.cursor != cursor ||
      !listEquals(old.ticksM, ticksM);
}
