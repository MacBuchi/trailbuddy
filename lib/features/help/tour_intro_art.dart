// Die Bilder der Tour-Startseiten (#133, Plan `docs/konzept-onboarding.md`
// 3.3 und 6; Form nach PilzBuddys `tour_intro_art.dart`, #596).
//
// **Neu gezeichnet, nicht kopiert** — PilzBuddy zeichnet Pilze. Hier ist
// das Motiv die Serpentine aus dem Logo (`LogoGeometry`), und die Farben
// sind die der App: die Marke für den Weg, die Pistenfarben für die
// Linien. Kein Foto, kein Lottie, keine Emojis (Design 6): Screenshots
// veralteten mit jeder Oberflächenänderung.
//
// Jede Szene steht auf derselben Bühne (240 × 150, Radius 20, Grund des
// Modus), damit die Startseiten zusammengehören. Bewegt wird nur, solange
// `TickerMode` an ist — die Startseite schaltet ihn bei „Animationen
// entfernen" ab, und dann steht das ENDBILD da (der Punkt am Ziel), nicht
// der Anfang.
import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/widgets/trailbuddy_logo.dart';
import '../trails/grade_shield.dart';

/// Die Bühne: abgerundeter Grund des Modus, darin die Szene.
class _Stage extends StatelessWidget {
  const _Stage({required this.painter});

  final CustomPainter painter;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 240,
    height: 150,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: ColoredBox(
        color: AppPalette.of(context).ground,
        child: CustomPaint(painter: painter),
      ),
    ),
  );
}

/// Wie weit der Punkt auf der Serpentine ist, 0…1, bei [t] (0…1, eine
/// Schleife von vier Sekunden): erst ein Moment am Start, dann weich die
/// Linie entlang, dann ein Moment am Ziel. Rein, damit ein Test den
/// Ablauf ohne Pixel prüft.
double introDriftAt(double t) {
  final x = t.clamp(0.0, 1.0);
  if (x < 0.1) return 0;
  if (x >= 0.8) return 1;
  // Kurveneingänge klemmen (CLAUDE.md, Bewegung): Gleitkomma ergibt hier
  // sonst Werte knapp über 1, und `Curve.transform` wirft darauf.
  return Curves.easeInOut.transform(((x - 0.1) / 0.7).clamp(0.0, 1.0));
}

/// Die Startseite „Willkommen bei TrailBuddy": die Serpentine in der
/// Marke, ein Punkt fährt sie ab.
Widget welcomeArt(BuildContext context) => const _WelcomeArt();

class _WelcomeArt extends StatefulWidget {
  const _WelcomeArt();

  @override
  State<_WelcomeArt> createState() => _WelcomeArtState();
}

class _WelcomeArtState extends State<_WelcomeArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    // Ohne Takt (reduzierte Bewegung) das Endbild: Punkt am Ziel.
    final moving = TickerMode.valuesOf(context).enabled;
    return AnimatedBuilder(
      animation: _loop,
      builder: (context, _) => _Stage(
        painter: _SerpentinePainter(
          progress: moving ? introDriftAt(_loop.value) : 1,
          road: p.brandMark,
          rider: p.text,
        ),
      ),
    );
  }
}

class _SerpentinePainter extends CustomPainter {
  const _SerpentinePainter({
    required this.progress,
    required this.road,
    required this.rider,
  });

  final double progress;
  final Color road;
  final Color rider;

  @override
  void paint(Canvas canvas, Size size) {
    // Das Logo in seinem 100er-Raster, mittig auf die Bühne gesetzt.
    const scale = 1.4;
    final geo = LogoGeometry.of(LogoSize.l);
    canvas.translate(size.width / 2 - 50 * scale, size.height / 2 - 50 * scale);
    canvas.scale(scale);
    canvas.drawPath(geo.range(0, geo.length), Paint()..color = road);
    // Die auslaufenden Striche wie im Logo, halb durchsichtig — dort fährt
    // niemand mehr.
    canvas.drawPath(
      geo.range(geo.length, geo.total),
      Paint()..color = road.withValues(alpha: 0.5),
    );
    final at = geo.pointAt(geo.length * progress);
    canvas.drawCircle(at, 5.5, Paint()..color = rider);
    canvas.drawCircle(at, 2.5, Paint()..color = road);
  }

  @override
  bool shouldRepaint(_SerpentinePainter old) =>
      old.progress != progress || old.road != road || old.rider != rider;
}

/// Die Startseite „Die Karte": drei Linienstücke in den Pistenfarben mit
/// weißem Saum auf dem Landton der Karte, am Anfang des mittleren das
/// Schild. Steht still — die Karte selbst bewegt sich auch nicht.
Widget mapArt(BuildContext context) => SizedBox(
  width: 240,
  height: 150,
  child: ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: const ColoredBox(
      color: AppColors.mapBackground,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _MapLinesPainter())),
          Positioned(
            left: 104,
            top: 88,
            child: GradeShield(1, fontSize: 12, palette: AppColors.mapGrades),
          ),
        ],
      ),
    ),
  ),
);

class _MapLinesPainter extends CustomPainter {
  const _MapLinesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const g = AppColors.mapGrades;
    final halo = AppColors.mapLines.halo!;
    void line(List<Offset> pts, Color color) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i + 1 < pts.length; i += 2) {
        path.quadraticBezierTo(
          pts[i].dx,
          pts[i].dy,
          pts[i + 1].dx,
          pts[i + 1].dy,
        );
      }
      Paint stroke(Color c, double w) => Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = c;
      canvas.drawPath(path, stroke(halo, 9));
      canvas.drawPath(path, stroke(color, 5));
    }

    line(const [
      Offset(18, 30),
      Offset(70, 20),
      Offset(96, 58),
      Offset(120, 92),
      Offset(170, 70),
    ], g.s0);
    line(const [Offset(110, 120), Offset(150, 40), Offset(214, 36)], g.s1);
    line(const [Offset(30, 130), Offset(60, 88), Offset(100, 110)], g.s2);
  }

  @override
  bool shouldRepaint(_MapLinesPainter old) => false;
}

/// Die Startseite „Deine erste Fahrt zerlegen" (#134): eine Fahrt als
/// blasse Linie, darin ein bekanntes Stück in Grün und ein Kandidat in
/// seiner Farbe mit den beiden Griffen — dieselben Farben wie die
/// Vorschau auf der Karte (`ride_split_sheet.dart`). Steht still.
Widget splitArt(BuildContext context) => SizedBox(
  width: 240,
  height: 150,
  child: ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: const ColoredBox(
      color: AppColors.mapBackground,
      child: CustomPaint(painter: _SplitPainter()),
    ),
  ),
);

class _SplitPainter extends CustomPainter {
  const _SplitPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const m = AppColors.mapLines;
    final ride = Path()
      ..moveTo(20, 120)
      ..cubicTo(60, 40, 90, 140, 125, 80)
      ..cubicTo(150, 35, 190, 110, 222, 32);
    final metric = ride.computeMetrics().first;
    Paint stroke(Color c, double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..color = c;
    Path part(double a, double b) =>
        metric.extractPath(metric.length * a, metric.length * b);

    canvas.drawPath(ride, stroke(m.halo!, 8));
    canvas.drawPath(ride, stroke(m.ride.withValues(alpha: 0.45), 4));
    for (final (a, b, color) in [
      (0.12, 0.42, m.mine),
      (0.58, 0.88, m.candidate),
    ]) {
      canvas.drawPath(part(a, b), stroke(m.halo!, 10));
      canvas.drawPath(part(a, b), stroke(color, 6));
    }
    // Die Griffe des Kandidaten.
    for (final t in [0.58, 0.88]) {
      final at = metric.getTangentForOffset(metric.length * t)!.position;
      canvas.drawCircle(at, 7, Paint()..color = Colors.white);
      canvas.drawCircle(at, 7, stroke(m.candidate, 3));
    }
  }

  @override
  bool shouldRepaint(_SplitPainter old) => false;
}

/// Die Startseite „Deine Trails" (#136): drei Zeilen wie in der Liste —
/// Streifen in den Pistenfarben, ein Balken als Name, das Schild rechts.
Widget trailsArt(BuildContext context) {
  final p = AppPalette.of(context);
  Widget row(Color stripe, double name, int grade) => Container(
    height: 32,
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: p.surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: p.line),
    ),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: stripe,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: name,
          height: 8,
          decoration: BoxDecoration(
            color: p.muted.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const Spacer(),
        GradeShield(grade, fontSize: 10),
      ],
    ),
  );
  return SizedBox(
    width: 240,
    height: 150,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: ColoredBox(
        color: p.ground,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Column(
            children: [
              row(p.grade.s1, 90, 1),
              row(p.grade.s2, 120, 2),
              row(p.grade.s0, 70, 0),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Die Startseite „Deine Buddys" (#136): zwei Spuren laufen zu einer
/// zusammen — das Motiv von 1s („Buddy verbunden"), hier stehend.
Widget buddysArt(BuildContext context) =>
    const _Stage(painter: _MergePainter());

class _MergePainter extends CustomPainter {
  const _MergePainter();

  @override
  void paint(Canvas canvas, Size size) {
    Paint stroke(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = c;
    const m = AppColors.mapLines;
    final left = Path()
      ..moveTo(24, 30)
      ..cubicTo(70, 30, 90, 75, 130, 75);
    final right = Path()
      ..moveTo(24, 120)
      ..cubicTo(70, 120, 90, 75, 130, 75);
    canvas.drawPath(left, stroke(m.mine));
    canvas.drawPath(right, stroke(m.buddy));
    canvas.drawLine(
      const Offset(130, 75),
      const Offset(206, 75),
      stroke(AppColors.brand),
    );
    canvas.drawCircle(
      const Offset(214, 75),
      8,
      Paint()..color = AppColors.brand,
    );
  }

  @override
  bool shouldRepaint(_MergePainter old) => false;
}
