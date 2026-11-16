// „Runden im Vergleich" (#549, Konzept-Routing 12.10 B; Entwurf
// `docs/design/planer-zeitskala/B-anteil-ueber-zeit.dc.html`): dieselben
// Stände wie die Leiste „andere Runden", als Kette über der Zeit —
// x = Zeit, y = Trail-Anteil. Der Ring um jeden Punkt sagt, wie viel vom
// Höhenmeter-Limit die Runde braucht, Form und Farbe darin den höchsten
// Grad; Gipfel stehen voll, die übrigen blass. „Auch über dem Limit"
// holt die Stände eines Greedy ohne Höhenmeter-Grenze dazu — hohl,
// gestrichelt, in der Warnfarbe; ihr Knopf hebt das Limit an, statt die
// Runde zu nehmen. Keine zweite Rechnung: Ein Tipp auf einen normalen
// Punkt ist [LoopPlannerNotifier.showState] wie auf der Leiste.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart' show AppFonts;
import '../../l10n/l10n.dart';
import '../trails/grade_shield.dart';
import 'loop_planner.dart';
import 'loop_planner_controller.dart';
import 'loop_planner_sheet.dart' show LoopBudgetScale;
import 'loop_state_strip.dart' show loopStripRange, loopStripVisible;
import 'trail_head_route.dart' show routeTimeLabel;

/// Höhe der Grafik.
const kLoopCompareChartH = 180.0;

/// Öffnet „Runden im Vergleich" über dem Ergebnis.
Future<void> showLoopCompare(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const FractionallySizedBox(heightFactor: 0.92, child: LoopCompareView()),
    );

/// Ein Punkt der Grafik: ein Stand der Leiste ([strip] = Index in
/// [LoopSession.strip]) oder einer über dem Limit ([over] = Index in
/// [LoopSession.over]).
typedef LoopComparePoint = ({LoopState state, int? strip, int? over});

/// Die Punkte der Grafik, nach Zeit: die Stände der Leiste und — mit dem
/// Schalter — die über dem Limit.
List<LoopComparePoint> loopComparePoints(LoopSession s, LoopBudget budget) {
  final out = <LoopComparePoint>[
    for (final i in loopStripVisible(budget, s.strip, s.stripPick)) (state: s.strip[i], strip: i, over: null),
    if (s.overOn)
      for (final (j, st) in (s.over ?? const <LoopState>[]).indexed) (state: st, strip: null, over: j),
  ];
  out.sort((a, b) => a.state.timeS.compareTo(b.state.timeS));
  return out;
}

/// Ein Gipfel: mehr Trail-Anteil als der Stand davor und der danach —
/// nur unter den Ständen der Leiste (die über dem Limit sind eine eigene
/// Kette).
bool loopCompareIsPeak(List<LoopState> chain, int k) {
  final v = chain[k].trailShare;
  final before = k > 0 ? chain[k - 1].trailShare : null;
  final after = k + 1 < chain.length ? chain[k + 1].trailShare : null;
  return (before == null || v > before) && (after == null || v > after);
}

class LoopCompareView extends ConsumerStatefulWidget {
  const LoopCompareView({super.key});

  @override
  ConsumerState<LoopCompareView> createState() => _LoopCompareViewState();
}

class _LoopCompareViewState extends ConsumerState<LoopCompareView> {
  /// Der gewählte Punkt über dem Limit; null heißt: der gezeigte Stand der
  /// Leiste.
  int? _over;
  var _closing = false;

  void _close() {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).maybePop();
  }

  void _select(LoopComparePoint pt) {
    final n = ref.read(loopPlannerProvider.notifier);
    if (pt.over != null) {
      setState(() => _over = pt.over);
      return;
    }
    setState(() => _over = null);
    unawaited(n.showState(pt.strip!));
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(loopPlannerProvider);
    final l = context.l10n;
    final theme = Theme.of(context);
    final p = AppPalette.of(context);
    // Die Planung ist weg (neu gerechnet ohne Stände, geschlossen): Der
    // Vergleich hat nichts mehr zu zeigen.
    if (!session.hasStrip) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _close();
      });
      return const SizedBox.shrink();
    }
    final budget = session.planBudget;
    final over = session.overOn ? (session.over ?? const <LoopState>[]) : const <LoopState>[];
    final overSel = _over != null && _over! < over.length ? _over : null;
    final points = loopComparePoints(session, budget);
    final chain = [
      for (final pt in points)
        if (pt.strip != null) pt.state,
    ];
    final LoopComparePoint shown = overSel != null
        ? points.firstWhere((pt) => pt.over == overSel)
        : points.firstWhere((pt) => pt.strip == session.stripShown);
    final small = theme.textTheme.labelSmall?.copyWith(color: p.muted);
    final head = theme.textTheme.labelSmall?.copyWith(fontFamily: AppFonts.display, color: p.muted, letterSpacing: 0.8);

    return Padding(
      key: const ValueKey('loop-compare'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.loopCompareTitle,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(fontFamily: AppFonts.display, color: p.accentText, letterSpacing: 1)),
                Text(
                  l.loopCompareTarget(routeTimeLabel(l, budget.timeS), budget.climbM.round()),
                  style: theme.textTheme.titleMedium?.copyWith(fontFamily: AppFonts.display),
                ),
              ]),
            ),
            IconButton(
              key: const ValueKey('loop-compare-close'),
              tooltip: l.loopCompareClose,
              onPressed: _close,
              icon: const Icon(Icons.close),
            ),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Text(l.loopCompareAxis, style: head)),
                    Text(l.loopCompareWindow((budget.windowS / 60).round()), style: small),
                  ]),
                  const SizedBox(height: 6),
                  _Chart(
                    points: points,
                    chain: chain,
                    budget: budget,
                    pick: session.stripPick!,
                    shown: shown,
                    onSelect: _select,
                  ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 14, runSpacing: 2, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CustomPaint(painter: _RingPainter(fraction: 0.7, track: p.line, fill: p.brandMark)),
                      ),
                      const SizedBox(width: 6),
                      Flexible(child: Text(l.loopCompareLegendRing, style: small)),
                    ]),
                    Text(l.loopCompareLegendShape, style: small),
                  ]),
                ]),
              ),
              const SizedBox(height: 10),
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, children: [
                FilterChip(
                  key: const ValueKey('loop-compare-over'),
                  label: Text(l.loopCompareOver),
                  selected: session.overOn,
                  onSelected: session.overBusy
                      ? null
                      : (on) {
                          if (!on) setState(() => _over = null);
                          unawaited(ref.read(loopPlannerProvider.notifier).setOverLimit(on));
                        },
                ),
                if (session.overBusy)
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                else if (session.overOn && over.isEmpty)
                  Text(l.loopCompareOverNone, key: const ValueKey('loop-compare-over-none'), style: small),
              ]),
              const SizedBox(height: 10),
              _Card(
                point: shown,
                isPick: shown.strip == session.stripPick,
                isPeak: shown.strip != null && loopCompareIsPeak(chain, chain.indexOf(shown.state)),
                limit: budget.climbM,
              ),
            ]),
          ),
          const SizedBox(height: 8),
          if (shown.over != null)
            FilledButton(
              key: const ValueKey('loop-compare-raise'),
              onPressed: () {
                final n = ref.read(loopPlannerProvider.notifier);
                final st = shown.state;
                _close();
                unawaited(n.raiseLimitFor(st));
              },
              child: Text(l.loopCompareRaise(ref.read(loopPlannerProvider.notifier).limitFor(shown.state).round())),
            )
          else
            FilledButton(
              key: const ValueKey('loop-compare-take'),
              onPressed: _close,
              child: Text(l.loopCompareTake),
            ),
          if (shown.strip != session.stripPick)
            TextButton(
              key: const ValueKey('loop-compare-back'),
              onPressed: () {
                setState(() => _over = null);
                unawaited(ref.read(loopPlannerProvider.notifier).showState(session.stripPick!));
              },
              child: Text(l.loopCompareBack),
            ),
        ],
      ),
    );
  }
}

/// Die Grafik: Kette der Stände, Ring = Höhenmeter am Limit, Form = Grad.
/// Tippen oder Ziehen rastet auf den nächsten Punkt (A13: Punkte liegen
/// oft eng, keine einzelnen Tippflächen).
class _Chart extends StatelessWidget {
  const _Chart({
    required this.points,
    required this.chain,
    required this.budget,
    required this.pick,
    required this.shown,
    required this.onSelect,
  });

  final List<LoopComparePoint> points;
  final List<LoopState> chain;
  final LoopBudget budget;
  final int pick;
  final LoopComparePoint shown;
  final ValueChanged<LoopComparePoint> onSelect;

  static const _ring = 15.0, _axisW = 28.0, _pad = 18.0;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = AppPalette.of(context);
    final theme = Theme.of(context);
    final small = AppFonts.numbers(theme.textTheme.labelSmall?.copyWith(color: p.muted));
    final range = loopStripRange(budget, [for (final pt in points) pt.state], null);
    final from = math.min(range.from, points.first.state.timeS - budget.windowS / 4);
    final to = math.max(range.to, points.last.state.timeS);
    final shares = [for (final pt in points) pt.state.trailShare];
    var lo = ((shares.reduce(math.min) - 0.02) * 20).floorToDouble() / 20;
    var hi = ((shares.reduce(math.max) + 0.02) * 20).ceilToDouble() / 20;
    if (hi - lo < 0.1) hi = lo + 0.1;
    lo = math.max(0, lo);
    hi = math.min(1, math.max(hi, lo + 0.1));
    final step = hi - lo > 0.3 ? 0.1 : 0.05;
    final ticks = [for (var v = lo; v <= hi + 1e-9; v += step) v];
    final pos = points.indexOf(shown);
    String describe(LoopState s) => l.loopComparePointSemantics(
        routeTimeLabel(l, s.timeS), (s.trailShare * 100).round(), s.climbM.round(), budget.climbM.round());

    return Semantics(
      label: l.loopCompareSemantics(pos + 1, points.length, describe(shown.state)),
      onIncrease: pos + 1 < points.length ? () => onSelect(points[pos + 1]) : null,
      onDecrease: pos > 0 ? () => onSelect(points[pos - 1]) : null,
      excludeSemantics: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth - _axisW;
          double x(double t) => _axisW + _pad + (t - from) / (to - from) * (w - 2 * _pad);
          double y(double v) => _pad + (hi - v) / (hi - lo) * (kLoopCompareChartH - 2 * _pad);
          Offset at(LoopState s) => Offset(x(s.timeS), y(s.trailShare));
          void nearest(Offset o) {
            var best = points.first;
            for (final pt in points) {
              if ((at(pt.state) - o).distance < (at(best.state) - o).distance) best = pt;
            }
            if (!identical(best, shown)) onSelect(best);
          }

          return GestureDetector(
            key: const ValueKey('loop-compare-chart'),
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => nearest(d.localPosition),
            onPanUpdate: (d) => nearest(d.localPosition),
            child: SizedBox(
              height: kLoopCompareChartH,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ChartPainter(
                      gridYs: [for (final v in ticks) y(v)],
                      left: _axisW,
                      windowFrom: x(budget.minTimeS),
                      windowTo: x(budget.maxTimeS),
                      target: x(budget.timeS),
                      chain: [for (final s in chain) at(s)],
                      overChain: [
                        for (final pt in points)
                          if (pt.over != null) at(pt.state),
                      ],
                      grid: p.line,
                      window: p.brandMark.withValues(alpha: 0.12),
                      targetColor: p.text.withValues(alpha: 0.5),
                      chainColor: p.muted,
                      warning: p.warningText,
                    ),
                  ),
                ),
                for (final (k, v) in ticks.indexed)
                  Positioned(
                    key: ValueKey('loop-compare-tick-$k'),
                    left: 0,
                    width: _axisW - 4,
                    top: y(v) - 7,
                    child: Text('${(v * 100).round()}', textAlign: TextAlign.right, style: small),
                  ),
                for (final pt in points)
                  _point(context, pt, at(pt.state), p,
                      faded: !identical(pt, shown) &&
                          (pt.over != null || !loopCompareIsPeak(chain, chain.indexOf(pt.state)))),
              ]),
            ),
          );
        }),
        Padding(
          padding: const EdgeInsets.only(left: _axisW),
          child: _TimeAxis(from: from, to: to, pad: _pad, style: small),
        ),
      ]),
    );
  }

  Widget _point(BuildContext context, LoopComparePoint pt, Offset c, AppPalette p, {required bool faded}) {
    final s = pt.state;
    final isShown = identical(pt, shown);
    final isPick = pt.strip == pick;
    final isOver = pt.over != null;
    final key = isOver ? 'over-${pt.over}' : '${pt.strip}';
    const d = _ring * 2;
    return Positioned(
      key: ValueKey('loop-compare-point-$key'),
      left: c.dx - _ring - 4,
      top: c.dy - _ring - 4,
      width: d + 8,
      height: d + 8,
      child: Opacity(
        opacity: faded ? 0.5 : 1,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          if (isShown)
            Container(
              key: const ValueKey('loop-compare-shown'),
              width: d + 8,
              height: d + 8,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: p.text, width: 2)),
            ),
          SizedBox(
            width: d,
            height: d,
            child: CustomPaint(
              painter: _RingPainter(
                fraction: budget.climbM <= 0 ? 0 : s.climbM / budget.climbM,
                track: p.line,
                fill: isOver || s.climbM > budget.climbM + 1 ? p.warningText : p.brandMark,
                dashed: isOver,
                inner: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          if (isOver)
            SizedBox(
              width: 10,
              height: 10,
              child: CustomPaint(painter: _RingPainter(fraction: 1, track: p.warningText, fill: p.warningText, dashed: true)),
            )
          else if (s.grade case final g?)
            GradeShape(g, size: g >= 4 ? 6 : 10, color: p.grade.of(g))
          else
            Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: p.muted)),
          if (isPick)
            Positioned(
              key: const ValueKey('loop-compare-pick'),
              top: -12,
              child: Text(
                context.l10n.loopStripPick,
                maxLines: 1,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontFamily: AppFonts.display,
                    color: p.accentText,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    fontSize: 10),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Die Karte zum gezeigten Punkt.
class _Card extends ConsumerWidget {
  const _Card({required this.point, required this.isPick, required this.isPeak, required this.limit});

  final LoopComparePoint point;
  final bool isPick, isPeak;
  final double limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final p = AppPalette.of(context);
    final s = point.state;
    final isOver = point.over != null;
    final sub = isOver
        ? l.loopCompareOverBy((s.climbM - limit).round())
        : isPick
            ? l.loopStripNotePickPlain
            : isPeak
                ? l.loopComparePeak
                : l.loopCompareDip;
    final label = theme.textTheme.labelSmall?.copyWith(color: p.muted);
    final value = AppFonts.numbers(theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700));
    Widget cell(String name, Widget child) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(name, style: label), const SizedBox(height: 2), child],
        );
    return Container(
      key: const ValueKey('loop-compare-card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (s.addedName case final name? when name.isNotEmpty) ...[
            Flexible(
              child: Text(
                l.loopCompareAdded(name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(fontFamily: AppFonts.display),
              ),
            ),
            const SizedBox(width: 6),
            GradeShield(s.addedGrade, fontSize: 11),
          ],
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              sub,
              key: const ValueKey('loop-compare-sub'),
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(color: isOver ? p.warningText : p.muted),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: cell(l.loopTileTime, Text(routeTimeLabel(l, s.timeS), style: value))),
          Expanded(child: cell(l.loopTileTrail, Text('${(s.trailShare * 100).round()} %', style: value))),
          Expanded(
            child: cell(
              l.loopTileClimb,
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${s.climbM.round()}', style: value.copyWith(color: isOver ? p.warningText : null)),
                const SizedBox(height: 3),
                LoopBudgetScale(value: s.climbM, mark: limit),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: cell(l.loopCompareGrade, s.grade == null ? Text('–', style: value) : GradeShield(s.grade))),
        ]),
      ]),
    );
  }
}

class _TimeAxis extends StatelessWidget {
  const _TimeAxis({required this.from, required this.to, required this.pad, required this.style});

  final double from, to, pad;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final span = to - from;
    final step = span > 3 * 3600 ? 3600.0 : (span > 1.25 * 3600 ? 1800.0 : 900.0);
    final ticks = <double>[
      for (var t = (from / step).ceil() * step; t <= to; t += step) t,
    ];
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
              left: (pad + (t - from) / span * (w - 2 * pad) - 20).clamp(0.0, w - 40),
              width: 40,
              child: Text(label(t), textAlign: TextAlign.center, maxLines: 1, style: style),
            ),
        ]),
      );
    });
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.gridYs,
    required this.left,
    required this.windowFrom,
    required this.windowTo,
    required this.target,
    required this.chain,
    required this.overChain,
    required this.grid,
    required this.window,
    required this.targetColor,
    required this.chainColor,
    required this.warning,
  });

  final List<double> gridYs;
  final double left, windowFrom, windowTo, target;
  final List<Offset> chain, overChain;
  final Color grid, window, targetColor, chainColor, warning;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final y in gridYs) {
      canvas.drawLine(Offset(left, y), Offset(size.width, y), line);
    }
    canvas.drawRRect(
      RRect.fromLTRBR(math.max(left, windowFrom), 0, math.min(size.width, windowTo), size.height, const Radius.circular(6)),
      Paint()..color = window,
    );
    canvas.drawRect(Rect.fromLTWH(target - 1, 0, 2, size.height), Paint()..color = targetColor);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    if (chain.length > 1) {
      canvas.drawPath(Path()..addPolygon(chain, false), stroke..color = chainColor);
    }
    if (overChain.length > 1) {
      stroke.color = warning;
      for (var k = 0; k + 1 < overChain.length; k++) {
        _dashed(canvas, overChain[k], overChain[k + 1], stroke);
      }
    }
  }

  static void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    final d = (b - a).distance;
    if (d <= 0) return;
    final u = (b - a) / d;
    for (var t = 0.0; t < d; t += 8) {
      canvas.drawLine(a + u * t, a + u * math.min(d, t + 4), paint);
    }
  }

  @override
  bool shouldRepaint(_ChartPainter o) =>
      o.gridYs != gridYs ||
      o.chain != chain ||
      o.overChain != overChain ||
      o.windowFrom != windowFrom ||
      o.windowTo != windowTo ||
      o.target != target ||
      o.grid != grid ||
      o.warning != warning;
}

/// Ein Ring, gefüllt bis [fraction] (im Uhrzeigersinn ab 12 Uhr);
/// gestrichelt für einen Stand über dem Limit; mit [inner] als Scheibe
/// darin, auf der die Form steht.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.track, required this.fill, this.dashed = false, this.inner});

  final double fraction;
  final Color track, fill;
  final bool dashed;
  final Color? inner;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final width = math.max(1.5, size.shortestSide * 0.13);
    final r = size.shortestSide / 2 - width / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    if (dashed) {
      paint.color = fill;
      const n = 12;
      for (var k = 0; k < n; k++) {
        canvas.drawArc(rect, -math.pi / 2 + k * 2 * math.pi / n, math.pi / n, false, paint);
      }
    } else {
      canvas.drawCircle(c, r, paint..color = track);
      final f = fraction.clamp(0.0, 1.0);
      if (f > 0) canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * f, false, paint..color = fill);
    }
    if (inner case final i?) canvas.drawCircle(c, r - width / 2, Paint()..color = i);
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.fraction != fraction || o.track != track || o.fill != fill || o.dashed != dashed || o.inner != inner;
}
