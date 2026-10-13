// Der S-Grad als Form (Design Turn 4, Abschnitt 7): ein farbloses Schild
// mit Form und „S3". Die Form trägt die Stufe auch für den, der die Zahl
// nicht liest — wie die Pistenzeichen im Skigebiet:
//
//   S0 ○  S1 ●  S2 ■  S3 ◆  S4 ◆◆  S5 ◆◆▮
//
// In der Pistenfarbe der Stufe (seit 0.42.0 trägt die Farbe überall die
// Schwierigkeit, `GradePalette`): grün, blau, rot, ab S3 schwarz — im
// Dunklen die helleren Töne, S3+ dann hell, sonst verschwände es. Die
// Form sagt die Stufe trotzdem auch ohne Farbe.
import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../l10n/l10n.dart';
import '../../models/trail.dart';
import 'singletrail_scale.dart';
import 'trail_traits.dart';

/// Die Farbe eines Trails — EINE Regel für Karte, Streifen und Schild:
/// Uphill (unter den angezeigten zwei Merkmalen, wie die Filter) trägt
/// die Uphill-Farbe, sonst die Stufe des Medians.
Color trailColorOf(Trail t, GradePalette p) => isUphill(t) ? p.uphill : p.of(t.grade);

/// Uphill heißt: unter den ANGEZEIGTEN Merkmalen (`topTraits`) — dieselbe
/// Lesart wie die Filter „Flowig"/„Jumps"; eine einzelne Nennung unter
/// vielen färbt keinen Trail um.
bool isUphill(Trail t) => t.topTraits.contains(TrailTrait.uphill);

/// Wie eine Trail-Linie auf der Karte gezeichnet wird, außer der Farbe
/// (Rework E9, #101): Die Farbe ist die Schwierigkeit, der ZUSTAND ist
/// die Art der Linie, und S4/S5 stehen im SAUM. Eine Regel für beide
/// Engines; [TrailLineStyle.opacity] multipliziert die Farbe.
typedef TrailLineStyle = ({List<double>? dash, double opacity, List<double>? haloDash});

/// Bröckelig: lange Striche, kurze Lücken — Zustand 3.
const kLineDashWorn = [10.0, 3.0];

/// Gestrichelt — Zustand 2 und 1 (1 zusätzlich verblasst).
const kLineDashRough = [5.0, 5.0];

/// Wartet im Ausgangskorb (#30): eine Zusage, die noch nicht eingelöst ist.
const kLineDashPending = [12.0, 8.0];

/// Der Saum ab S4 — gestrichelt wie eine Skiroute. Bis 0.50.0 war es die
/// Linie selbst; die trägt jetzt den Zustand.
const kHaloDashExpert = [6.0, 4.0];

/// Ab dieser Stufe trägt der Saum sein Muster.
const kExpertGrade = 4;

TrailLineStyle trailLineStyleOf(Trail t) {
  final haloDash = (t.grade ?? 0) >= kExpertGrade ? kHaloDashExpert : null;
  if (t.pending) return (dash: kLineDashPending, opacity: 0.6, haloDash: haloDash);
  // Nur ein BESTÄTIGTER Zustand verändert die Linie — ein unbestätigter
  // steht verblasst im Blatt, auf der Karte wäre er eine Behauptung.
  return switch (t.shownCondition.confirmed?.condition) {
    3 => (dash: kLineDashWorn, opacity: 1.0, haloDash: haloDash),
    2 => (dash: kLineDashRough, opacity: 1.0, haloDash: haloDash),
    1 => (dash: kLineDashRough, opacity: 0.45, haloDash: haloDash),
    _ => (dash: null, opacity: 1.0, haloDash: haloDash),
  };
}

/// Das Schild zu einem Grad 0–5 — auf der Karte am Trailanfang auch mit
/// den Charakter-Symbolen (Design 4c) und ohne Grad, wenn es Merkmale
/// gibt. Ohne Grad, Uphill und Merkmale: nichts.
class GradeShield extends StatelessWidget {
  const GradeShield(this.grade,
      {super.key, this.fontSize = 12, this.uphill = false, this.traits = const [], this.palette});

  final int? grade;

  /// Uphill-Trail: Uphill-Farbe und ein Pfeil statt der Form; der Grad
  /// bleibt dabei, er sagt, wie technisch die Auffahrt ist.
  final bool uphill;

  /// Charakter-Symbole hinter dem Grad (nur auf der Karte, wo keine
  /// Zeile daneben steht). Uphill fällt hier weg — das sagt der Pfeil.
  final List<TrailTrait> traits;

  /// Der Farbsatz; Vorgabe der des App-Modus. Die Karte gibt
  /// [AppColors.mapGrades] mit — sie ist immer hell.
  final GradePalette? palette;

  /// Schriftgröße von „S3"; die Form wächst mit.
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final p = palette ?? AppPalette.of(context).grade;
    final ink = p.ink;
    final g = grade == null ? null : singletrailGrade(grade!);
    final shownTraits = [for (final t in traits) if (!(uphill && t == TrailTrait.uphill)) t];
    if (g == null && !uphill && shownTraits.isEmpty) return const SizedBox.shrink();
    final label = [
      if (uphill) context.l10n.gradeUphill,
      if (g != null) context.l10n.gradeShieldSemantics(g.label, g.short(context.l10n)),
      for (final t in shownTraits) t.label(context.l10n),
    ].join(', ');
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: fontSize * 0.55, vertical: fontSize * 0.2),
        decoration: BoxDecoration(
          color: uphill ? p.uphill : p.of(grade),
          borderRadius: BorderRadius.circular(fontSize * 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (uphill)
              UphillArrow(size: fontSize * 0.8, color: ink)
            else if (grade != null)
              GradeShape(grade!, size: fontSize * 0.75, color: ink),
            if (grade != null) ...[
              SizedBox(width: fontSize * 0.35),
              Text(gradeLabel(grade!),
                  style: AppFonts.numbers(TextStyle(fontSize: fontSize, height: 1.2))
                      .copyWith(color: ink)),
            ],
            for (final t in shownTraits) ...[
              SizedBox(width: fontSize * 0.35),
              Icon(t.icon, size: fontSize * 1.15, color: ink),
            ],
          ],
        ),
      ),
    );
  }
}

/// Nur die Form eines Grads, ohne Schild — für Stellen, die ihren
/// eigenen Grund haben (Erklärblatt).
class GradeShape extends StatelessWidget {
  const GradeShape(this.grade, {super.key, required this.size, required this.color});

  final int grade;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(gradeShapeWidth(grade, size), size),
        painter: _GradeShapePainter(grade, color),
      );
}

/// Breite der Form bei Höhe [size]: eine Einheit, zwei Rauten bei S4,
/// dazu ein Balken bei S5.
double gradeShapeWidth(int grade, double size) => switch (grade) {
      4 => size * 2 + size * 0.15,
      5 => size * 2 + size * 0.15 + size * 0.2 + size * 0.3,
      _ => size,
    };

class _GradeShapePainter extends CustomPainter {
  _GradeShapePainter(this.grade, this.color);

  final int grade;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.height;
    final fill = Paint()..color = color;
    final center = Offset(u / 2, u / 2);
    Path diamond(double left) => Path()
      ..moveTo(left + u / 2, 0)
      ..lineTo(left + u, u / 2)
      ..lineTo(left + u / 2, u)
      ..lineTo(left, u / 2)
      ..close();
    switch (grade) {
      case 0:
        final w = u * 0.16;
        canvas.drawCircle(
            center,
            u / 2 - w / 2,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = w);
      case 1:
        canvas.drawCircle(center, u / 2, fill);
      case 2:
        // Etwas kleiner als die Einheit: Ein Quadrat mit voller Kante
        // wirkt neben dem Kreis zu schwer.
        final inset = u * 0.08;
        canvas.drawRect(Rect.fromLTRB(inset, inset, u - inset, u - inset), fill);
      case 3:
        canvas.drawPath(diamond(0), fill);
      default:
        canvas.drawPath(diamond(0), fill);
        canvas.drawPath(diamond(u + u * 0.15), fill);
        if (grade >= 5) {
          final left = u * 2 + u * 0.15 + u * 0.2;
          canvas.drawRect(Rect.fromLTWH(left, 0, u * 0.3, u), fill);
        }
    }
  }

  @override
  bool shouldRepaint(_GradeShapePainter old) => old.grade != grade || old.color != color;
}

/// Der Pfeil bergauf (↗) — gezeichnet wie die Formen, Barlow hat ihn
/// nicht.
class UphillArrow extends StatelessWidget {
  const UphillArrow({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _UphillArrowPainter(color),
      );
}

class _UphillArrowPainter extends CustomPainter {
  _UphillArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width;
    final w = u * 0.2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final inset = w / 2;
    canvas.drawLine(Offset(inset, u - inset), Offset(u - inset, inset), paint);
    canvas.drawPath(
        Path()
          ..moveTo(u * 0.42, inset)
          ..lineTo(u - inset, inset)
          ..lineTo(u - inset, u * 0.58),
        paint);
  }

  @override
  bool shouldRepaint(_UphillArrowPainter old) => old.color != color;
}
