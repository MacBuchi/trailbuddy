// Die Folgeansicht der Navigation (#232, #312; Konzept-Routing 9.2 und
// 9.9): eine Lage ÜBER der Karte, keine eigene Karte — dieselbe Fassade,
// derselbe Stil, dieselben Bereiche offline. Die Karte (`map_screen.dart`)
// dreht und folgt, hier stehen die Karten je Abschnitt, das Routenband,
// die Knöpfe und der Start-Dialog.
//
// „Was kommt als Nächstes?" statt „Wie weit noch?" (Entwurf 2026-10-12,
// Design 13): Oben steht der ABSCHNITT — die Anfahrt zum nächsten
// Trailkopf (km, hm, Rampe), der Moment am Trailkopf (Stufe, Charakter,
// Zustand, der Hinweis eines Buddys), der Trail selbst (Rest, bergab) —,
// unten die ganze Route als Band. Alle Flächen sind dunkel, in beiden
// Modi: Sie liegen über der hellen Karte, und in praller Sonne liest sich
// Lime auf Dunkel.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../core/geo.dart';
import '../../core/screen_awake.dart';
import '../../l10n/l10n.dart';
import '../map/map_buttons.dart';
import '../map/map_view/map_view.dart';
import '../trails/grade_shield.dart';
import '../trails/trail_condition.dart';
import '../trails/trail_report.dart' show reportAgeLabel;
import 'nav_providers.dart';
import 'route_progress.dart';

/// Die Farben der Folgeansicht: immer der dunkle Satz (Design 13).
const _p = AppColors.dark;

/// Radius der Karten, wie im Entwurf.
const _kCardRadius = 14.0;

/// Die Route auf der Karte: der gefahrene Teil blass, der Rest in der
/// Farbe des Ergebnisses mit weißem Saum, davor gestrichelt das Stück
/// „Zurück zur Route". Liegt unter dem Netz — Trails auf der Route
/// behalten ihre Farbe (Design 7).
List<MapViewPolyline> navRouteLines(NavSession session) {
  final c = AppColors.mapLines.ride;
  final along = session.state?.alongM ?? 0;
  final (done, rest) = session.route.splitAt(along);
  return [
    if (done.length >= 2) MapViewPolyline(points: done, color: c.withValues(alpha: 0.35), width: 5),
    MapViewPolyline(
      points: rest,
      color: c,
      width: 6,
      borderColor: AppColors.mapLines.halo,
      borderWidth: AppColors.mapLines.haloBorderWidth,
    ),
    if (session.rejoinLine case final back? when back.length >= 2)
      MapViewPolyline(
        points: back,
        color: c,
        width: 5,
        dash: const [10, 8],
        borderColor: AppColors.mapLines.halo,
        borderWidth: AppColors.mapLines.haloBorderWidth,
      ),
  ];
}

/// Was der Start-Dialog zurückgibt.
class NavStartChoice {
  const NavStartChoice({required this.record});

  /// Die Fahrt mit aufzeichnen (9.4).
  final bool record;
}

/// Vor dem Start: Aufzeichnen (nur wenn es geht und noch keine läuft)
/// und Bildschirm (nur wo es den Weg gibt). Vorgabe beider: an
/// (Betreiber, 2026-10-08). Null heißt abgebrochen. [summary] steht unter
/// dem Titel („2 Trails · 18,6 km").
Future<NavStartChoice?> showNavStartSheet(BuildContext context,
        {required String title, required bool canRecord, String? summary}) =>
    showModalBottomSheet<NavStartChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NavStartSheet(title: title, summary: summary, canRecord: canRecord),
    );

/// Der Untertitel des Start-Dialogs aus den Abschnitten: Trails und Länge.
String navStartSummary(AppLocalizations l, NavRequest request) {
  final route = NavRoute.of(request.points);
  if (route == null) return '';
  final trails = request.sections?.ridden.length ?? 0;
  return l.navStartSummary(trails, formatMeters(route.lengthM));
}

class _NavStartSheet extends ConsumerStatefulWidget {
  const _NavStartSheet({required this.title, required this.summary, required this.canRecord});

  final String title;
  final String? summary;
  final bool canRecord;

  @override
  ConsumerState<_NavStartSheet> createState() => _NavStartSheetState();
}

class _NavStartSheetState extends ConsumerState<_NavStartSheet> {
  bool _record = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final screen = ref.watch(screenAwakeProvider).supported;
    final summary = widget.summary;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.navStartTitle, style: theme.textTheme.titleLarge),
            Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
            if (summary != null && summary.isNotEmpty)
              KeyedSubtree(
                  key: const ValueKey('nav-summary'),
                  child: Text(summary, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor))),
            const SizedBox(height: 8),
            if (widget.canRecord)
              SwitchListTile(
                key: const ValueKey('nav-record'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.navRecordTitle),
                subtitle: Text(l.navRecordSubtitle),
                value: _record,
                onChanged: (v) => setState(() => _record = v),
              ),
            if (screen)
              SwitchListTile(
                key: const ValueKey('nav-screen'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.navScreenTitle),
                subtitle: Text(l.navScreenSubtitle),
                value: ref.watch(navKeepScreenOnProvider),
                onChanged: (v) => ref.read(navKeepScreenOnProvider.notifier).set(v),
              ),
            const SizedBox(height: 8),
            Text(l.navStartHint, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('nav-go'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => Navigator.of(context).pop(NavStartChoice(record: widget.canRecord && _record)),
              icon: const Icon(Icons.navigation_outlined),
              label: Text(l.navStartButton),
            ),
          ],
        ),
      ),
    );
  }
}

/// Oben die Karte des Abschnitts, unten Band und Knöpfe; hält den
/// Bildschirm an, solange sie steht und der Schalter an ist.
///
/// [compact] ist die Fassung für das Bild-im-Bild (9.6): keine Knöpfe,
/// keine Karte als Leiste, die Zahlen klein über der Karte — und der
/// Bildschirm-Schalter gilt nicht, dann ist die Benachrichtigung die
/// Anzeige (9.4).
class NavOverlay extends ConsumerStatefulWidget {
  const NavOverlay({super.key, required this.session, required this.onStop, this.compact = false});

  final NavSession session;
  final VoidCallback onStop;
  final bool compact;

  @override
  ConsumerState<NavOverlay> createState() => _NavOverlayState();
}

class _NavOverlayState extends ConsumerState<NavOverlay> {
  // Beim Aufbau gegriffen: Im `dispose` ist `ref` nicht mehr zu lesen.
  late final ScreenAwake _screen = ref.read(screenAwakeProvider);

  @override
  void initState() {
    super.initState();
    if (ref.read(navKeepScreenOnProvider) && !widget.compact) unawaited(_screen.keepOn(true));
  }

  @override
  void didUpdateWidget(NavOverlay old) {
    super.didUpdateWidget(old);
    if (old.compact != widget.compact) {
      unawaited(_screen.keepOn(!widget.compact && ref.read(navKeepScreenOnProvider)));
    }
  }

  @override
  void dispose() {
    unawaited(_screen.keepOn(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(navKeepScreenOnProvider, (_, on) => unawaited(_screen.keepOn(on && !widget.compact)));
    final session = widget.session;
    final l = context.l10n;
    final keepOn = ref.watch(navKeepScreenOnProvider);
    final state = session.state;
    final arrived = state?.arrived ?? false;
    final off = !arrived && (state?.offRoute ?? false);
    if (widget.compact) return _PipNumbers(session: session);
    final phase = session.phase;
    // „Zurück zur Route" nur abseits (9.3) und solange kein Stück liegt.
    final offer = off && session.rejoin != NavRejoin.shown;
    // Fand „Zurück zur Route" nichts, sagt es die Ansicht in einem Satz (9.3).
    final note = switch (session.rejoin) {
      NavRejoin.noArea => l.navRejoinNoArea,
      NavRejoin.noPath => l.navRejoinNoPath,
      _ => null,
    };
    final Widget top;
    if (off && state != null) {
      top = _OffRouteCard(state: state, bearingDeg: session.bearingDeg);
    } else {
      top = switch (phase.kind) {
        NavPhaseKind.arrived => _ArrivedBar(onStop: widget.onStop),
        NavPhaseKind.atHead => _HeadCard(section: phase.section!),
        NavPhaseKind.onTrail => _TrailBar(phase: phase),
        NavPhaseKind.approach => _ApproachCard(phase: phase, session: session),
      };
    }
    return _NavTheme(
      child: Stack(children: [
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  top,
                  if (note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _NavCard(
                        key: const ValueKey('nav-rejoin-note'),
                        child: Text(
                          note,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _p.warningText, fontSize: 14, fontFamily: AppFonts.body),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!arrived && !off) ...[
                    _RouteBand(session: session),
                    const SizedBox(height: 10),
                  ],
                  if (offer) ...[
                    Center(child: _RejoinButton(computing: session.rejoin == NavRejoin.computing)),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      MapRoundButton(
                        key: const ValueKey('nav-north'),
                        dark: true,
                        tooltip: session.north ? l.navRotateTooltip : l.navNorthTooltip,
                        icon: Icons.explore_outlined,
                        active: session.north,
                        onPressed: () => ref.read(navigationProvider.notifier).toggleNorth(),
                      ),
                      if (_screen.supported) ...[
                        const SizedBox(width: 10),
                        MapRoundButton(
                          key: const ValueKey('nav-screen-toggle'),
                          dark: true,
                          tooltip: keepOn ? l.navScreenOffTooltip : l.navScreenTitle,
                          icon: keepOn ? Icons.light_mode : Icons.light_mode_outlined,
                          active: keepOn,
                          onPressed: () => ref.read(navKeepScreenOnProvider.notifier).set(!keepOn),
                        ),
                      ],
                      const Spacer(),
                      FilledButton.icon(
                        key: const ValueKey('nav-stop'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          backgroundColor: AppColors.brand,
                          foregroundColor: AppColors.onBrand,
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.fromLTRB(16, 0, 20, 0),
                        ),
                        onPressed: widget.onStop,
                        icon: const Icon(Icons.close, size: 18),
                        label: Text(l.navStop),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Die Schrift der Folgeansicht: hell auf Dunkel, egal welcher Modus —
/// ein Text ohne eigene Farbe wäre im Hellen schwarz auf Schwarz.
class _NavTheme extends StatelessWidget {
  const _NavTheme({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
        style: TextStyle(color: _p.text, fontFamily: AppFonts.body),
        child: IconTheme.merge(data: IconThemeData(color: _p.text), child: child),
      );
}

/// Die gemeinsame Hülle: dunkle Fläche, Rand, Radius 14, Schatten.
class _NavCard extends StatelessWidget {
  const _NavCard({super.key, required this.child, this.border, this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 10)});


  final Widget child;
  final BorderSide? border;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: _p.ground,
          borderRadius: BorderRadius.circular(_kCardRadius),
          border: Border.fromBorderSide(border ?? BorderSide(color: _p.line)),
          boxShadow: const [BoxShadow(blurRadius: 14, offset: Offset(0, 4), color: Color(0x40000000))],
        ),
        child: child,
      );
}

/// Beschriftung in Versalien, 11 px, gesperrt — wie „BIS ZUM TRAILKOPF".
class _Label extends StatelessWidget {
  const _Label(this.text, {this.color});


  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
            color: color ?? _p.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.9, height: 1.2),
      );
}

/// Der Name eines Trails in Barlow Condensed, Versalien.
class _TrailName extends StatelessWidget {
  const _TrailName(this.name, {this.size = 18});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
        name.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontFamily: AppFonts.display, fontWeight: FontWeight.w800, fontSize: size, height: 1, letterSpacing: 0.3),
      );
}

/// Eine große Zahl mit Einheit daneben: „2,4" + „km".
class _BigNumber extends StatelessWidget {
  const _BigNumber({super.key, required this.value, required this.unit, this.color});

  final String value;
  final String unit;
  final Color? color;

  static const size = 44.0;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(value,
              style: AppFonts.numbers(TextStyle(fontSize: size, height: 1, color: color ?? _p.text))
                  .copyWith(letterSpacing: -1)),
          const SizedBox(width: 4),
          Text(unit, style: TextStyle(fontSize: size * 0.34, fontWeight: FontWeight.w500, color: _p.muted)),
        ],
      );
}

/// „2,4 km" ⇒ („2,4", „km"); „758 m" ⇒ („758", „m").
(String, String) _splitUnit(AppLocalizations l, double meters) {
  final text = formatMeters(meters);
  final i = text.lastIndexOf(' ');
  final unit = text.substring(i + 1) == 'km' ? l.navUnitKm : l.navUnitM;
  return (text.substring(0, i), unit);
}

/// Die Anfahrt (9.9): km und hm bis zum nächsten Trailkopf — oder bis zum
/// Ziel —, das Mini-Profil mit der Rampe, der Wegmix.
class _ApproachCard extends StatelessWidget {
  const _ApproachCard({required this.phase, required this.session});

  final NavPhase phase;
  final NavSession session;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final section = phase.section;
    final (dist, unit) = _splitUnit(l, phase.distM);
    final climb = phase.climbM;
    final ramp = phase.ramp;
    final ways = section?.approachWays ?? const [];
    final wayLine = ways.isEmpty
        ? null
        : [
            ways.first.cls.label,
            for (final w in ways.skip(1).take(2)) l.navWayThen(formatMeters(w.lengthM), w.cls.label),
          ].join(', ');
    final along = session.state?.alongM ?? 0;
    final toM = section?.startM ?? session.route.lengthM;
    return _NavCard(
      key: const ValueKey('nav-approach'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _Label(section == null ? l.navToGoal : l.navToHead),
              const Spacer(),
              if (section != null) ...[
                GradeShield(section.grade, uphill: section.uphill, fontSize: 11, palette: _p.grade),
                const SizedBox(width: 6),
                Flexible(child: _TrailName(section.name)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              _BigNumber(key: const ValueKey('nav-dist'), value: dist, unit: unit),
              if (climb != null) ...[
                const SizedBox(width: 18),
                _BigNumber(
                    key: const ValueKey('nav-climb'),
                    value: '↑${climb.round()}',
                    unit: l.navUnitHm,
                    color: AppColors.brand),
              ],
            ],
          ),
          if (session.climbDistM != null && toM > along) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: CustomPaint(
                key: const ValueKey('nav-profile'),
                painter: _MiniProfilePainter(
                    distM: session.climbDistM!, eleM: session.climbEleM!, fromM: along, toM: toM),
                size: Size.infinite,
              ),
            ),
          ],
          if (wayLine != null || ramp != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (wayLine != null)
                  Expanded(
                      child: Text(wayLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: _p.muted))),
                if (ramp != null)
                  KeyedSubtree(
                    key: const ValueKey('nav-ramp'),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '■ ', style: TextStyle(color: _p.warningText)),
                        TextSpan(text: l.navRampAhead((ramp.grade * 100).round(), formatMeters(ramp.inM))),
                      ]),
                      style: TextStyle(fontSize: 12, color: _p.muted),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Das Mini-Profil der Anfahrt: Fläche in `surface2`, Linie in der Marke,
/// Rampen (ab [kNavRampGrade]) in Warnfarbe, ein Punkt am Stand.
class _MiniProfilePainter extends CustomPainter {
  const _MiniProfilePainter({required this.distM, required this.eleM, required this.fromM, required this.toM});

  final List<double> distM;
  final List<double> eleM;
  final double fromM;
  final double toM;

  @override
  void paint(Canvas canvas, Size size) {
    final xs = <double>[], ys = <double>[];
    double eleAt(double m) {
      for (var i = 1; i < distM.length; i++) {
        if (distM[i] >= m) {
          final span = distM[i] - distM[i - 1];
          final t = span <= 0 ? 0.0 : ((m - distM[i - 1]) / span).clamp(0.0, 1.0);
          return eleM[i - 1] + (eleM[i] - eleM[i - 1]) * t;
        }
      }
      return eleM.last;
    }

    xs.add(fromM);
    ys.add(eleAt(fromM));
    for (var i = 0; i < distM.length; i++) {
      if (distM[i] > fromM && distM[i] < toM) {
        xs.add(distM[i]);
        ys.add(eleM[i]);
      }
    }
    xs.add(toM);
    ys.add(eleAt(toM));
    final span = toM - fromM;
    if (span <= 0 || xs.length < 2) return;
    var lo = ys.reduce(math.min), hi = ys.reduce(math.max);
    if (hi - lo < 20) {
      final mid = (hi + lo) / 2;
      lo = mid - 10;
      hi = mid + 10;
    }
    Offset at(int i) => Offset(
          (xs[i] - fromM) / span * size.width,
          size.height - 3 - (ys[i] - lo) / (hi - lo) * (size.height - 6),
        );
    final fill = Path()..moveTo(0, size.height);
    for (var i = 0; i < xs.length; i++) {
      final o = at(i);
      fill.lineTo(o.dx, o.dy);
    }
    fill
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = _p.surface2);
    final line = Paint()
      ..color = AppColors.brand
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final ramp = Paint()
      ..color = _p.warningText
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < xs.length; i++) {
      final dx = xs[i] - xs[i - 1];
      final steep = dx > 0 && (ys[i] - ys[i - 1]) / dx >= kNavRampGrade;
      canvas.drawLine(at(i - 1), at(i), steep ? ramp : line);
    }
    canvas.drawCircle(at(0), 4, Paint()..color = _p.text);
  }

  @override
  bool shouldRepaint(_MiniProfilePainter old) =>
      old.fromM != fromM || old.toM != toM || !identical(old.distM, distM) || !identical(old.eleM, eleM);
}

/// Abseits schlägt alles: Rand in Warnfarbe, der große Pfeil zur Linie,
/// der Abstand (9.3).
class _OffRouteCard extends StatelessWidget {
  const _OffRouteCard({required this.state, required this.bearingDeg});

  final NavState state;
  final double bearingDeg;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // Der Pfeil zeigt zur Linie voraus — gedreht gegen die Karte, damit er
    // auf dem Schirm stimmt.
    final deg = bearingDegrees(
            state.position.latitude, state.position.longitude, state.rejoin.latitude, state.rejoin.longitude) -
        bearingDeg;
    return _NavCard(
      key: const ValueKey('nav-off'),
      border: BorderSide(color: _p.warningText, width: 2),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Transform.rotate(
            key: const ValueKey('nav-off-arrow'),
            angle: deg * math.pi / 180,
            child: Icon(Icons.navigation, size: 44, color: _p.warningText),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Label(l.navOffRoute, color: _p.warningText),
                const SizedBox(height: 2),
                Text(formatMeters(state.offM),
                    style: AppFonts.numbers(const TextStyle(fontSize: 36, height: 1)).copyWith(letterSpacing: -1)),
                const SizedBox(height: 2),
                Text(l.navOffRouteHint, style: TextStyle(fontSize: 12, color: _p.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ein Chip auf der Trailkopf-Karte: Fläche `surface2`, Radius 8.
class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.mono = false});

  final String text;
  final bool mono;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(color: _p.surface2, borderRadius: BorderRadius.circular(8)),
        child: Text(text,
            style: mono
                ? AppFonts.numbers(const TextStyle(fontSize: 12))
                : const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

/// Der Moment vor dem Droppen (9.9): Stufe, Länge, Charakter, Zustand —
/// und der Hinweis eines Buddys, bevor man ihn braucht.
class _HeadCard extends StatelessWidget {
  const _HeadCard({required this.section});

  final NavTrailSection section;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final note = section.note;
    final condition = section.condition;
    return _NavCard(
      key: const ValueKey('nav-head'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Label(l.navAtHead, color: AppColors.brand),
          const SizedBox(height: 10),
          Row(
            children: [
              GradeShield(section.grade, uphill: section.uphill, fontSize: 13, palette: _p.grade),
              const SizedBox(width: 8),
              Expanded(child: _TrailName(section.name, size: 26)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (section.lengthM > 0) _Chip(formatMeters(section.lengthM), mono: true),
              if (section.lossM case final loss? when loss > 0) _Chip('↓${loss.round()} ${l.navUnitHm}', mono: true),
              if (section.traits.isNotEmpty) _Chip(section.traits.map((t) => t.label).join(' · ')),
              if (condition != null && section.conditionAt != null)
                _Chip(l.navConditionChip(trailCondition(condition).label(l), reportAgeLabel(l, section.conditionAt!))),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: 10),
            Container(
              key: const ValueKey('nav-head-note'),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                border: Border.all(color: _p.noteText, width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Label(l.navNoteHeader((note.author ?? l.sheetBuddy).toUpperCase(),
                      reportAgeLabel(l, note.createdAt).toUpperCase()),
                      color: _p.noteText),
                  const SizedBox(height: 2),
                  Text(note.body, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 1.35)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Auf dem Trail wird die Leiste schmal: Rest des Trails, bergab, der
/// Balken in Stufenfarbe, der Hinweis als Zeile.
class _TrailBar extends StatelessWidget {
  const _TrailBar({required this.phase});

  final NavPhase phase;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final section = phase.section!;
    final note = section.note;
    final done = section.lengthM <= 0 ? 0.0 : (1 - phase.distM / section.lengthM).clamp(0.0, 1.0);
    final color = section.uphill ? _p.grade.uphill : _p.grade.of(section.grade);
    final numbers = AppFonts.numbers(const TextStyle(fontSize: 20, height: 1));
    final unit = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _p.muted, fontFamily: AppFonts.body);
    return _NavCard(
      key: const ValueKey('nav-trail'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GradeShield(section.grade, uphill: section.uphill, fontSize: 11, palette: _p.grade),
              const SizedBox(width: 7),
              Expanded(child: _TrailName(section.name, size: 20)),
              const SizedBox(width: 10),
              KeyedSubtree(
                key: const ValueKey('nav-trail-rest'),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: formatMeters(phase.distM)),
                    if (phase.lossM case final loss?) ...[
                      const TextSpan(text: '   '),
                      TextSpan(text: '↓${loss.round()}'),
                      TextSpan(text: ' ${l.navUnitHm}', style: unit),
                    ],
                  ]),
                  style: numbers,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Stack(children: [
                Container(color: _p.line),
                FractionallySizedBox(widthFactor: done, child: Container(color: color)),
              ]),
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 8),
            KeyedSubtree(
              key: const ValueKey('nav-trail-note'),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: '${note.author ?? l.sheetBuddy}: ',
                      style: AppFonts.numbers(TextStyle(fontSize: 12, color: _p.noteText))),
                  TextSpan(text: note.body),
                ]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, height: 1.3),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Die ganze Route als Band (9.9): Anfahrten hell, der gefahrene Teil
/// dunkel, Trails in Stufenfarbe, der Stand als Strich in der Marke;
/// darunter die Namen, wo sie Platz haben.
class _RouteBand extends StatelessWidget {
  const _RouteBand({required this.session});

  final NavSession session;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final route = session.route;
    final along = session.state?.alongM ?? 0;
    final trails = session.sections.ridden.toList();
    final total = route.lengthM;
    // Die Stücke: Anfahrt, Trail, Anfahrt, …, bis zum Ziel.
    final parts = <({double from, double to, NavTrailSection? trail})>[];
    var cursor = 0.0;
    for (final t in trails) {
      if (t.startM > cursor) parts.add((from: cursor, to: t.startM, trail: null));
      parts.add((from: t.startM, to: math.max(t.endM, t.startM), trail: t));
      cursor = math.max(t.endM, cursor);
    }
    if (cursor < total || parts.isEmpty) parts.add((from: cursor, to: total, trail: null));
    final climb = session.remainingClimbM;
    final remaining = climb == null
        ? l.navBandRemaining(formatMeters(session.remainingM))
        : l.navBandRemainingClimb(formatMeters(session.remainingM), climb.round());
    final head = [
      route.isLoop ? l.navBandLoop : l.navBandRoute,
      if (trails.isNotEmpty) l.navBandTrails(trails.length),
    ].join(' · ');
    return _NavCard(
      key: const ValueKey('nav-band'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: _Label(head)),
              KeyedSubtree(
                  key: const ValueKey('nav-remaining'),
                  child: Text(remaining, style: AppFonts.numbers(const TextStyle(fontSize: 12)))),
            ],
          ),
          const SizedBox(height: 7),
          LayoutBuilder(builder: (context, c) {
            final width = c.maxWidth;
            double x(double m) => total <= 0 ? 0 : (m / total).clamp(0.0, 1.0) * width;
            return SizedBox(
              height: 14,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned(
                  top: 3,
                  left: 0,
                  right: 0,
                  height: 8,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(children: [
                      for (final p in parts)
                        Positioned(
                          left: x(p.from),
                          width: math.max(0, x(p.to) - x(p.from) - (p == parts.last ? 0 : 2)),
                          top: 0,
                          bottom: 0,
                          child: ColoredBox(
                            color: p.trail != null
                                ? (p.trail!.uphill ? _p.grade.uphill : _p.grade.of(p.trail!.grade))
                                : (p.to <= along ? _p.line : _p.map.ride),
                          ),
                        ),
                    ]),
                  ),
                ),
                Positioned(
                  left: x(along) - 2,
                  top: 0,
                  width: 4,
                  height: 14,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ]),
            );
          }),
          const SizedBox(height: 4),
          LayoutBuilder(builder: (context, c) {
            final width = c.maxWidth;
            double x(double m) => total <= 0 ? 0 : (m / total).clamp(0.0, 1.0) * width;
            final style = TextStyle(fontSize: 11, color: _p.muted);
            return SizedBox(
              height: 14,
              child: Stack(children: [
                for (final p in parts)
                  if (p.trail != null && x(p.to) - x(p.from) >= 40)
                    Positioned(
                      left: x(p.from),
                      width: x(p.to) - x(p.from),
                      child: Text(p.trail!.name, maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: style),
                    ),
                Positioned(right: 0, child: Text(l.navBandGoal, style: style)),
              ]),
            );
          }),
        ],
      ),
    );
  }
}

/// Das Fenster ist ~150 dp breit: die Zahlen ohne Beschriftung in einer
/// Zeile, abseits der Abstand in Warnfarbe; am Ziel ein Wort.
class _PipNumbers extends StatelessWidget {
  const _PipNumbers({required this.session});

  final NavSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final state = session.state;
    final climb = session.remainingClimbM;
    final off = state?.offRoute ?? false;
    final style = theme.textTheme.labelLarge?.copyWith(fontFamily: AppFonts.mono, color: _p.text);
    final arrived = state?.arrived ?? false;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: DecoratedBox(
          key: const ValueKey('nav-pip'),
          decoration: BoxDecoration(
            color: _p.ground.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: arrived
                  ? Text(l.navArrivedTitle, style: style)
                  : Text.rich(
                      TextSpan(children: [
                        TextSpan(text: formatMeters(session.remainingM)),
                        if (climb != null) TextSpan(text: ' · ${climb.round()} ${l.navUnitHm}'),
                        if (off && state != null)
                          TextSpan(text: ' · ${l.navPipOff(formatMeters(state.offM))}', style: TextStyle(color: _p.warningText)),
                      ]),
                      style: style,
                      maxLines: 1,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RejoinButton extends ConsumerWidget {
  const _RejoinButton({required this.computing});

  final bool computing;

  @override
  Widget build(BuildContext context, WidgetRef ref) => FilledButton.icon(
        key: const ValueKey('nav-rejoin'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          backgroundColor: _p.surface2,
          foregroundColor: AppColors.brand,
          disabledBackgroundColor: _p.surface2,
          disabledForegroundColor: _p.muted,
          shape: StadiumBorder(side: BorderSide(color: _p.line)),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
        onPressed: computing ? null : () => unawaited(ref.read(navigationProvider.notifier).rejoin()),
        icon: computing
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.u_turn_left),
        label: Text(context.l10n.navRejoin),
      );
}

class _ArrivedBar extends StatelessWidget {
  const _ArrivedBar({required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return _NavCard(
      key: const ValueKey('nav-arrived'),
      padding: EdgeInsets.zero,
      // Ein eigenes Material: Die Kachel malt ihre Tinte auf das nächste,
      // und das läge sonst unter der dunklen Fläche.
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(_kCardRadius),
        child: ListTile(
          leading: const Icon(Icons.sports_score, color: AppColors.brand),
          title: Text(l.navArrivedTitle, style: TextStyle(color: _p.text)),
          subtitle: Text(l.navArrivedSubtitle, style: TextStyle(color: _p.muted)),
          onTap: onStop,
        ),
      ),
    );
  }
}
