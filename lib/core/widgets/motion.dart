// Bewegung (Design Turn 1p–1t, docs/design/README.md Abschnitt 9): die
// gemeinsamen Bausteine. Jede Animation ist aus, wenn das System es will
// — dann steht das Endbild da, nie ein halbes.
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../app_colors.dart';
import 'trailbuddy_logo.dart';

/// „Animationen entfernen" (Android) bzw. „Bewegung reduzieren" im Browser.
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Ein Durchlauf des Loaders: Das Zeichen zeichnet sich ganz ein, steht
/// kurz und blendet zurück in die Spur — 0,85 s + 0,2 s + 0,35 s.
///
/// Bis 0.65.0 lief statt dessen ein Läufer von 40 Einheiten hindurch
/// (1,5 s + 0,5 s Pause). Man sah damit nie das ganze Zeichen, immer nur
/// ein Stück davon, und das wirkte langsam und unfertig (Betreiber,
/// 2026-10-01: „läuft recht langsam und nicht vollständig durch").
const kLoaderDrawMs = 850;
const kLoaderHoldMs = 200;
const kLoaderFadeMs = 350;

/// Stand des Loaders bei [t] (0…1 über [TrailLoader.period]) auf einer
/// Strecke der Länge [total] (mit Endstrichen): bis wohin das Zeichen
/// steht (`to`) und wie deckend es über der Spur liegt (`opacity`). Pur,
/// damit ein Test ohne Pixel prüfen kann, dass jeder Durchlauf das ganze
/// Zeichen zeigt, bevor er ausblendet.
({double to, double opacity}) loaderAt(double t, double total) {
  final ms = t.clamp(0.0, 1.0) * TrailLoader.period.inMilliseconds;
  // Kurveneingänge klemmen: Gleitkomma liegt sonst knapp über 1, und die
  // Kurve lehnt das ab. Und knapp darunter ist auch fertig — sonst fehlt
  // am Übergang zum Stehen ein Hauch vom letzten Strich.
  final x = ms / kLoaderDrawMs;
  final draw = x >= 1 - 1e-9 ? 1.0 : Curves.easeInOut.transform(x.clamp(0.0, 1.0));
  final fade = ((ms - kLoaderDrawMs - kLoaderHoldMs) / kLoaderFadeMs).clamp(0.0, 1.0);
  return (to: draw * total, opacity: 1 - Curves.easeIn.transform(fade));
}

/// Der Loader: das Logo als Spur, darauf läuft ein Stück in der Marke.
/// Ersetzt die ganzseitigen Kreisel; in Knöpfen bleibt der kleine Kreisel
/// — 16 px Serpentine liest niemand.
class TrailLoader extends StatefulWidget {
  const TrailLoader({super.key, this.size = 56});

  final double size;

  static const period = Duration(milliseconds: kLoaderDrawMs + kLoaderHoldMs + kLoaderFadeMs);

  @override
  State<TrailLoader> createState() => _TrailLoaderState();
}

class _TrailLoaderState extends State<TrailLoader> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: TrailLoader.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _controller
        ..stop()
        // Still: das ganze Zeichen, nie ein halbes.
        ..value = (kLoaderDrawMs + kLoaderHoldMs / 2) / TrailLoader.period.inMilliseconds;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final geo = LogoGeometry.forPixels(widget.size);
    return Semantics(
      label: context.l10n.loaderSemantics,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final s = loaderAt(_controller.value, geo.total);
              return CustomPaint(
                painter: LogoPainter(
                  geometry: geo,
                  color: p.brandMark.withValues(alpha: s.opacity),
                  track: p.line,
                  to: s.to,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Der Loader mittig in der verfügbaren Fläche — der häufigste Fall.
class CenteredTrailLoader extends StatelessWidget {
  const CenteredTrailLoader({super.key});

  @override
  Widget build(BuildContext context) => const Center(child: TrailLoader());
}

/// Schein des Leuchtrands bei [t] (0…1…0 über eine Periode, `ease-in-out`
/// wie im Entwurf): innen 2 → 6 px, außen 0 → 14 px (Design 1t).
({double inner, double outer}) glowAt(double t) {
  final e = Curves.easeInOut.transform(t.clamp(0, 1));
  return (inner: 2 + 4 * e, outer: 14 * e);
}

/// Der gelbe Leuchtrand atmet (1t) — um eine Karte mit neuem Hinweis,
/// nur solange er ungesehen ist (der Aufrufer entscheidet, ob er da ist).
/// Bei reduzierter Bewegung steht der ruhige, schwache Schein.
class BreathingGlow extends StatefulWidget {
  const BreathingGlow({super.key, required this.color, required this.radius, required this.child});

  final Color color;
  final double radius;
  final Widget child;

  static const period = Duration(milliseconds: 1800);

  @override
  State<BreathingGlow> createState() => _BreathingGlowState();
}

class _BreathingGlowState extends State<BreathingGlow> with SingleTickerProviderStateMixin {
  // Eine Periode ist hin UND zurück: 0,9 s ein, 0,9 s aus.
  late final _controller = AnimationController(
      vsync: this, duration: BreathingGlow.period ~/ 2);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final g = glowAt(_controller.value);
          return DecoratedBox(
            key: const ValueKey('breathing-glow'),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              boxShadow: [
                BoxShadow(color: widget.color, blurRadius: g.inner),
                if (g.outer > 0) BoxShadow(color: widget.color.withValues(alpha: 0.6), blurRadius: g.outer),
              ],
            ),
            child: child,
          );
        },
      );
}
