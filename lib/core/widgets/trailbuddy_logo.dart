import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_theme.dart';

part 'trailbuddy_logo_geometry.dart';

/// Optische Größe des Logos „Serpentine C3" (docs/design/trailbuddy-logo):
/// L ab 32 px mit zwei Endstrichen, M für 20–28 px mit einem, S bis 18 px
/// ohne Endstrich und mit längerem Auslauf. Kleiner gezeichnet würden die
/// Striche zu Krümeln, deshalb hat jede Größe ihre eigene Form.
enum LogoSize { l, m, s }

/// Die optische Größe für eine Kantenlänge in logischen Pixeln — die
/// Schwellen aus dem Handoff (`markSizeFor`).
LogoSize logoSizeFor(double px) => px >= 30
    ? LogoSize.l
    : px >= 19
    ? LogoSize.m
    : LogoSize.s;

/// Ein Endstrich: beginnt bei [c0] auf der Strecke (hinter der Mittellinie,
/// Lücke eingerechnet), [len] lang, waagerecht ab [x1] bei [y], Breite [w].
typedef LogoDash = ({double c0, double len, double x1, double y, double w});

/// Die Form des Logos als gefüllte FLÄCHE, keine Linie mit Strichstärke:
/// Stichproben der Mittellinie `[x, y, nx, ny, halbeBreiteLinks,
/// halbeBreiteRechts]` im 100er-Raster, gleicher Abstand, dazu die
/// Endstriche. Die Zahlen erzeugt `tool/brand_icons.py` aus
/// `tool/brand/logo_c3.json` — derselben Datei, aus der auch alle
/// App-Symbole entstehen.
class LogoGeometry {
  const LogoGeometry._({
    required this.length,
    required this.total,
    required this.dashes,
    required this.samples,
  });

  /// Länge der Mittellinie.
  final double length;

  /// Länge der ganzen Strecke, mit Lücken und Endstrichen.
  final double total;

  final List<LogoDash> dashes;
  final List<double> samples;

  static LogoGeometry of(LogoSize size) => switch (size) {
    LogoSize.l => _logoL,
    LogoSize.m => _logoM,
    LogoSize.s => _logoS,
  };

  /// Die Form, die für [px] logische Pixel Kantenlänge gemacht ist.
  static LogoGeometry forPixels(double px) => of(logoSizeFor(px));

  int get _n => samples.length ~/ 6 - 1;

  Offset _left(int i) {
    final o = i * 6;
    return Offset(
      samples[o] + samples[o + 2] * samples[o + 4],
      samples[o + 1] + samples[o + 3] * samples[o + 4],
    );
  }

  Offset _right(int i) {
    final o = i * 6;
    return Offset(
      samples[o] - samples[o + 2] * samples[o + 5],
      samples[o + 1] - samples[o + 3] * samples[o + 5],
    );
  }

  double _halfWidth(int i) => (samples[i * 6 + 4] + samples[i * 6 + 5]) / 2;

  /// Die Fläche des Abschnitts [a]…[b] der Strecke (0…[total]) mit runden
  /// Kappen in der Streckenbreite dort — daraus entstehen Logo
  /// (`range(0, total)`), das Einzeichnen des Loaders und das Zeichnen im
  /// Splash. Spiegel von `outline()` in `tool/brand_icons.py`.
  Path range(double a, double b) {
    final path = Path();
    final n = _n, ds = length / n;
    if (b > 0 && a < length) {
      final i0 = (math.max(0.0, a) / ds).round().clamp(0, n - 1);
      final i1 = math.max(
        i0 + 1,
        (math.min(length, b) / ds).round().clamp(0, n),
      );
      final start = _left(i0);
      path.moveTo(start.dx, start.dy);
      for (var i = i0 + 1; i <= i1; i++) {
        final p = _left(i);
        path.lineTo(p.dx, p.dy);
      }
      path.arcToPoint(
        _right(i1),
        radius: Radius.circular(_halfWidth(i1)),
        clockwise: false,
      );
      for (var i = i1 - 1; i >= i0; i--) {
        final p = _right(i);
        path.lineTo(p.dx, p.dy);
      }
      path.arcToPoint(
        start,
        radius: Radius.circular(_halfWidth(i0)),
        clockwise: false,
      );
      path.close();
    }
    for (final d in dashes) {
      final lo = math.max(a, d.c0), hi = math.min(b, d.c0 + d.len);
      if (hi < lo) continue;
      final r = d.w / 2;
      path.addRRect(
        RRect.fromLTRBR(
          d.x1 + lo - d.c0 - r,
          d.y - r,
          d.x1 + hi - d.c0 + r,
          d.y + r,
          Radius.circular(r),
        ),
      );
    }
    return path;
  }

  /// Der Punkt der Mittellinie bei [d] (0…[length]), zwischen den
  /// Stichproben gerade verbunden.
  Offset pointAt(double d) {
    final n = _n;
    final u = (d.clamp(0.0, length) / length) * n;
    final i = u.floor().clamp(0, n - 1);
    final f = u - i;
    final o = i * 6, q = o + 6;
    return Offset(
      samples[o] + (samples[q] - samples[o]) * f,
      samples[o + 1] + (samples[q + 1] - samples[o + 1]) * f,
    );
  }
}

/// Malt das Logo im 100er-Raster auf seine Fläche: den Abschnitt
/// [from]…[to] der Strecke in [color], darunter auf Wunsch die ganze Form
/// in [track]. Ohne [geometry] die optische Größe zur Kantenlänge.
class LogoPainter extends CustomPainter {
  const LogoPainter({
    required this.color,
    this.geometry,
    this.from = 0,
    this.to,
    this.track,
  });

  final Color color;
  final LogoGeometry? geometry;
  final double from;

  /// Ende des Abschnitts; ohne Wert das ganze Logo.
  final double? to;

  final Color? track;

  @override
  void paint(Canvas canvas, Size size) {
    final geo = geometry ?? LogoGeometry.forPixels(size.shortestSide);
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    if (track != null) {
      canvas.drawPath(geo.range(0, geo.total), Paint()..color = track!);
    }
    final end = to ?? geo.total;
    if (end > from) {
      canvas.drawPath(geo.range(from, end), Paint()..color = color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LogoPainter old) =>
      old.color != color ||
      old.geometry != geometry ||
      old.from != from ||
      old.to != to ||
      old.track != track;
}

/// Das Logo als Zeichen, eine Farbe. Ohne Farbe die Marke dieses Modus
/// ([AppPalette.brandMark]: Lime im Dunklen, Moos im Hellen). Die optische
/// Größe folgt [size], [logoSize] erzwingt eine.
class TrailBuddyMark extends StatelessWidget {
  const TrailBuddyMark({super.key, this.size = 64, this.color, this.logoSize});

  final double size;
  final Color? color;
  final LogoSize? logoSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'TrailBuddy',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: LogoPainter(
            color: color ?? AppPalette.of(context).brandMark,
            geometry: LogoGeometry.of(logoSize ?? logoSizeFor(size)),
          ),
        ),
      ),
    );
  }
}

/// Die Wortmarke „TRAIL" + „BUDDY", die zweite Hälfte in der Marke.
class TrailBuddyWordmark extends StatelessWidget {
  const TrailBuddyWordmark({super.key, this.fontSize = 44});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final style = TextStyle(
      fontFamily: AppFonts.display,
      fontWeight: FontWeight.w800,
      fontSize: fontSize,
      height: 1,
      color: p.text,
    );
    return Semantics(
      label: 'TrailBuddy',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            const TextSpan(text: 'TRAIL'),
            TextSpan(
              text: 'BUDDY',
              style: TextStyle(color: p.accentText),
            ),
          ],
        ),
      ),
    );
  }
}
