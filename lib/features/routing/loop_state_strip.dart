// Die Leiste „andere Runden" im Ergebnis einer Runde (#549,
// Konzept-Routing 12.10 A; Entwurf `docs/design/planer-zeitskala/`).
// Jeder Stand des Greedy ist ein Stiel auf der Zeit: Höhe = Trail-Anteil,
// Kopf = höchster S-Grad als Form und Farbe. Tippen oder waagrecht Ziehen
// rastet auf den nächsten Stand — keine einzelnen Tippflächen, zwei Stände
// liegen oft nur Minuten auseinander (A13, Handschuh).
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart' show AppFonts;
import '../../l10n/l10n.dart';
import '../trails/grade_shield.dart';
import 'loop_planner.dart';
import 'trail_head_route.dart' show routeTimeLabel;

/// Höhe der Fläche mit den Stielen.
const kLoopStripChartH = 46.0;

/// Der sichtbare Bereich der Leiste: Zeit ± 2 × Fenster (bis dahin schaut
/// `chooseState` unter, bis dahin rechnet der Greedy über das Fenster).
/// Liegt der Vorschlag darunter (kein Stand im Fenster), reicht sie bis
/// zu ihm.
({double from, double to}) loopStripRange(LoopBudget budget, List<LoopState> states, int? pick) {
  var from = budget.floorTimeS;
  final to = budget.ceilTimeS;
  if (pick != null && pick < states.length) {
    from = math.min(from, states[pick].timeS - budget.windowS / 4);
  }
  return (from: math.max(0, from), to: to);
}

/// Die Stände, die auf der Leiste stehen (Index in [states]).
List<int> loopStripVisible(LoopBudget budget, List<LoopState> states, int? pick) {
  final r = loopStripRange(budget, states, pick);
  return [
    for (var i = 0; i < states.length; i++)
      if (i == pick || (states[i].timeS >= r.from - 1 && states[i].timeS <= r.to + 1)) i,
  ];
}

/// Der Satz unter der Leiste: was die gezeigte Runde vom Vorschlag
/// unterscheidet — jeder Stand ist der vorige plus EIN Trail.
String loopStripNote(AppLocalizations l, List<LoopState> states, int pick, int shown) {
  List<String> names(Iterable<int> idx) {
    final out = <String>[];
    for (final i in idx) {
      final n = states[i].addedName;
      if (n != null && n.isNotEmpty && !out.contains(n)) out.add(n);
    }
    return out;
  }

  if (shown == pick) {
    final last = states[pick].addedName;
    return last == null || last.isEmpty ? l.loopStripNotePickPlain : l.loopStripNotePick(last);
  }
  if (shown < pick) return l.loopStripShorter(names([for (var i = shown + 1; i <= pick; i++) i]).join(', '));
  return l.loopStripLonger(names([for (var i = pick + 1; i <= shown; i++) i]).join(', '));
}

class LoopStateStrip extends StatelessWidget {
  const LoopStateStrip({
    super.key,
    required this.states,
    required this.pick,
    required this.shown,
    required this.budget,
    required this.onShow,
  });

  final List<LoopState> states;

  /// Der Vorschlag des Planers.
  final int pick;

  /// Der gezeigte Stand.
  final int shown;
  final LoopBudget budget;
  final ValueChanged<int> onShow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(context);
    final l = context.l10n;
    final range = loopStripRange(budget, states, pick);
    final visible = loopStripVisible(budget, states, pick);
    final shares = [for (final i in visible) states[i].share];
    final lo = shares.reduce(math.min), hi = shares.reduce(math.max);
    final small = theme.textTheme.labelSmall?.copyWith(color: p.muted);
    final head = theme.textTheme.labelSmall?.copyWith(fontFamily: AppFonts.display, color: p.muted, letterSpacing: 0.8);
    final s = states[shown];
    final timeText = l.loopTimeAbout(routeTimeLabel(l, s.timeS));
    final share = (s.trailShare * 100).round();
    String describe(int i) => l.loopStripStateSemantics(routeTimeLabel(l, states[i].timeS), (states[i].trailShare * 100).round());
    final pos = visible.indexOf(shown);

    void showNearest(double dx, double width) {
      final t = range.from + (dx / width).clamp(0.0, 1.0) * (range.to - range.from);
      var best = visible.first;
      for (final i in visible) {
        if ((states[i].timeS - t).abs() < (states[best].timeS - t).abs()) best = i;
      }
      if (best != shown) onShow(best);
    }

    return Container(
      key: const ValueKey('loop-strip'),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(l.loopStripTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: head),
            ),
            const SizedBox(width: 6),
            Text(
              l.loopStripTarget(routeTimeLabel(l, budget.timeS), '${(budget.windowS / 60).round()}'),
              style: small,
            ),
          ]),
          // Platz für „VORSCHLAG" über dem höchsten Stiel.
          const SizedBox(height: 12),
          Semantics(
            label: l.loopStripSemantics(pos + 1, visible.length, describe(shown)),
            onIncrease: pos + 1 < visible.length ? () => onShow(visible[pos + 1]) : null,
            onDecrease: pos > 0 ? () => onShow(visible[pos - 1]) : null,
            excludeSemantics: true,
            child: LayoutBuilder(builder: (context, c) {
              final w = c.maxWidth;
              double x(double t) => ((t - range.from) / (range.to - range.from)).clamp(0.0, 1.0) * w;
              double stemH(double v) =>
                  hi - lo < 1e-6 ? kLoopStripChartH * 0.5 : 8 + (v - lo) / (hi - lo) * (kLoopStripChartH - 14);
              final winFrom = x(budget.minTimeS), winTo = x(budget.maxTimeS);
              return GestureDetector(
                key: const ValueKey('loop-strip-chart'),
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onTapDown: (d) => showNearest(d.localPosition.dx, w),
                onHorizontalDragUpdate: (d) => showNearest(d.localPosition.dx, w),
                child: SizedBox(
                  height: kLoopStripChartH,
                  width: w,
                  child: Stack(clipBehavior: Clip.none, children: [
                    // Das Fenster um die Zeit und die Zeit selbst — wie die
                    // Skala bisher (Konzept-Routing 12.5a).
                    Positioned(
                      left: winFrom,
                      width: math.max(0, winTo - winFrom),
                      top: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: p.brandMark.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    Positioned(
                      left: x(budget.timeS) - 1,
                      width: 2,
                      top: 0,
                      bottom: 0,
                      child: ColoredBox(color: p.text.withValues(alpha: 0.5)),
                    ),
                    Positioned(left: 0, right: 0, bottom: 0, height: 1, child: ColoredBox(color: p.line)),
                    for (final i in visible)
                      ..._stem(
                        context,
                        key: i,
                        x: x(states[i].timeS),
                        h: stemH(states[i].share),
                        grade: states[i].grade,
                        isPick: i == pick,
                        isShown: i == shown,
                        p: p,
                      ),
                  ]),
                ),
              );
            }),
          ),
          _Axis(from: range.from, to: range.to, style: AppFonts.numbers(small)),
          const SizedBox(height: 4),
          Wrap(
            key: const ValueKey('loop-strip-line'),
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(timeText, style: AppFonts.numbers(theme.textTheme.bodyMedium)),
              Text('  ·  ', style: TextStyle(color: p.muted)),
              Text(l.loopStripShare(share), style: theme.textTheme.bodyMedium),
              if (s.grade != null) ...[
                Text('  ·  ${l.loopStripUpTo} ', style: theme.textTheme.bodyMedium),
                GradeShield(s.grade, fontSize: 11),
              ],
            ],
          ),
          Text(
            loopStripNote(l, states, pick, shown),
            key: const ValueKey('loop-strip-note'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: p.muted),
          ),
        ],
      ),
    );
  }

  List<Widget> _stem(BuildContext context,
      {required int key,
      required double x,
      required double h,
      required int? grade,
      required bool isPick,
      required bool isShown,
      required AppPalette p}) {
    const headSize = 11.0;
    final color = p.grade.of(grade);
    final headW = grade == null ? headSize : gradeShapeWidth(grade, headSize);
    return [
      Positioned(
        key: ValueKey('loop-strip-stem-$key'),
        left: x - 1,
        width: 2,
        bottom: 0,
        height: h,
        child: ColoredBox(color: isShown ? p.accentText : p.muted.withValues(alpha: 0.6)),
      ),
      // Der Kopf: höchster Grad als Form; der gezeigte Stand im Ring der
      // Marke.
      Positioned(
        left: x - headW / 2 - 3,
        bottom: h - 3,
        child: Container(
          key: isShown ? const ValueKey('loop-strip-shown') : null,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: isShown ? p.accentText : Colors.transparent, width: 1.5),
          ),
          child: grade == null
              ? Container(
                  width: headSize,
                  height: headSize,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: p.muted),
                )
              : GradeShape(grade, size: headSize, color: color),
        ),
      ),
      if (isPick)
        Positioned(
          key: const ValueKey('loop-strip-pick'),
          left: x - 40,
          width: 80,
          bottom: h + 10,
          child: Text(
            context.l10n.loopStripPick,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(fontFamily: AppFonts.display, color: p.accentText, fontWeight: FontWeight.w700, letterSpacing: 0.8, fontSize: 10),
          ),
        ),
    ];
  }
}

/// Die Zeitachse unter der Leiste: halbe oder ganze Stunden, je nach Breite
/// des Bereichs.
class _Axis extends StatelessWidget {
  const _Axis({required this.from, required this.to, required this.style});

  final double from, to;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final span = to - from;
    final step = span > 3 * 3600 ? 3600.0 : (span > 1.25 * 3600 ? 1800.0 : 900.0);
    final ticks = <double>[];
    for (var t = (from / step).ceil() * step; t <= to; t += step) {
      ticks.add(t);
    }
    String label(double t) {
      final min = (t / 60).round();
      final h = min ~/ 60, m = min % 60;
      return m == 0 ? '$h h' : '$h:${m.toString().padLeft(2, '0')}';
    }

    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return SizedBox(
        height: 14,
        child: Stack(clipBehavior: Clip.none, children: [
          for (final t in ticks)
            Positioned(
              left: ((t - from) / span * w - 20).clamp(0.0, w - 40),
              width: 40,
              child: Text(label(t), textAlign: TextAlign.center, maxLines: 1, style: style),
            ),
        ]),
      );
    });
  }
}
