// Das Blatt „Route" (#158 Schritt 4, seit 0.74.0 allgemein, #176/#177): vom
// eigenen Standort zu einem Ziel — dem Kopf eines Trails („Zum Trailkopf")
// oder einem Punkt der Karte („Route bis hier", langer Druck) — über den
// Wegegraphen der gespeicherten Bereiche. Die Linie als Vorschau auf der
// Karte, darunter Länge, Höhenmeter, Zeit, der Mix der Wegklassen und der
// Satz zum Wanderweg. Dazu „Als GPX" (#150) und „Anfahrt" (#151) als die
// Übergabe, die auch ohne Bereich trägt.
//
// Zwei Wege (#176, Feldbericht 0.73.0: „Routenoption spaßig oder direkt"):
// - **Direkt**: der günstigste Weg (A*, Konzept-Routing 3.1).
// - **Spaßig**: der Rundenplaner mit Ziel (`planLoop(end:)`) — er nimmt
//   Abfahrten auf dem Weg mit, im Budget [kFunTimeFactor] × die direkte
//   Zeit (mindestens [kFunExtraS] mehr) und [kFunClimbFactor] × deren
//   Höhenmeter. Passt keine, steht der direkte Weg da, und das Blatt sagt
//   es.
//
// Vier Dinge, die man wissen muss:
// - **Kein Modal** (`map_panel.dart`): Runterziehen verkleinert, die
//   Karte darüber bleibt bedienbar; beim Ergebnis klappt das Blatt ein und
//   die Karte passt die Route DARÜBER ein.
// - **Der Fix kommt beim Öffnen, nicht beim Tipp** — das Blatt IST der
//   Tipp; `positionFixProvider` darf nach der Berechtigung fragen.
// - **Gerechnet wird über die Kacheln, die da sind** (`planning_graph.dart`);
//   ohne eine einzige gibt es keinen Weg, und das Blatt nennt den
//   Knopf „Offline-Karten".
// - **Profil und Weg lassen sich im Blatt umschalten**: Der Graph bleibt,
//   nur die Suche läuft neu.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/l10n.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart' show AppFonts;
import '../../core/errors.dart';
import '../../core/geo.dart' show formatMeters;
import '../../core/gpx_share.dart';
import '../../core/line_geometry.dart';
import '../../core/settings.dart';
import '../../models/trail.dart';
import '../map/map_view/map_view.dart';
import '../map/position_provider.dart';
import '../profile/profile_providers.dart';
import '../rides/ride_providers.dart';
import '../rides/ride_track.dart';
import '../trails/gpx.dart';
import '../trails/gpx_writer.dart';
import '../trails/trail_geometry.dart' show haversineM;
import '../trails/trail_navigation.dart';
import '../trails/trail_providers.dart';
import 'loop_planner.dart';
import 'loop_planner_providers.dart';
import 'loop_planner_sheet.dart' show loopPreviewLines, wayMixLine;
import 'map_panel.dart';
import 'nav_providers.dart';
import 'nav_sections.dart';
import 'planning_graph.dart';
import 'ride_calibrator.dart';
import 'road_graph.dart';
import 'route_elevation.dart';
import 'route_profile.dart';
import 'route_search.dart' show steepNote;
import 'route_via_providers.dart';
import 'route_vias.dart';
import 'via_handles.dart';
import 'route_band.dart';
import 'trail_head_providers.dart';
import 'trail_head_route.dart';

/// Spaßig darf so viel länger dauern als direkt — und mindestens so viel
/// mehr (sonst hätte ein 10-Minuten-Weg keinen Platz für einen Trail).
/// Startwerte, nicht gemessen.
const kFunTimeFactor = 1.6;
const kFunExtraS = 20 * 60.0;
const kFunClimbFactor = 1.5;
const kFunExtraClimbM = 200.0;

/// Wohin die Route führt.
class RouteTarget {
  const RouteTarget({required this.point, required this.title, this.trail});

  /// Der Kopf eines Trails.
  factory RouteTarget.trailHead(AppLocalizations l, Trail t) =>
      RouteTarget(point: t.start, title: t.displayName(l), trail: t);

  final LatLng point;
  final String title;
  final Trail? trail;
}

/// Zeigt das Blatt am Scaffold der Karte; die Vorschau lebt mit dem Blatt
/// und wird HIER geleert, nach dem `await`.
Future<void> showRouteSheet(ScaffoldState scaffold, RouteTarget target, {RouteMode mode = RouteMode.direct}) async {
  final container = ProviderScope.containerOf(scaffold.context, listen: false);
  await showMapPanel(
    scaffold,
    initialSize: 0.5,
    builder: (context, scroll, panel) => _RouteSheet(target: target, mode: mode, scroll: scroll, panel: panel),
  );
  container.read(trailHeadPreviewProvider.notifier).state = const [];
  container.read(routeViaProvider.notifier).end(ViaOwner.route);
}

/// „Zum Trailkopf" — der bisherige Einstieg.
Future<void> showTrailHeadSheet(ScaffoldState scaffold, Trail trail, {RouteMode mode = RouteMode.direct}) =>
    showRouteSheet(scaffold, RouteTarget.trailHead(scaffold.context.l10n, trail), mode: mode);

enum _Phase { locating, loading, computing, done }

/// Was die Rechnung ergeben hat, bevor es einen Graphen gab.
enum _Blocker { noPosition, noArea, failed }

class _RouteSheet extends ConsumerStatefulWidget {
  const _RouteSheet({required this.target, required this.mode, required this.scroll, required this.panel});

  final RouteTarget target;
  final RouteMode mode;
  final ScrollController scroll;
  final MapPanelController panel;

  @override
  ConsumerState<_RouteSheet> createState() => _RouteSheetState();
}

class _RouteSheetState extends ConsumerState<_RouteSheet> {
  _Phase _phase = _Phase.locating;
  _Blocker? _blocker;
  PlanningGraph? _loaded;
  LatLng? _from;
  late RiderProfile _profile;
  late RouteMode _mode;
  TrailHeadPlan? _plan;

  /// Der spaßige Weg, wenn er Trails mitnimmt; sonst null (dann zeigt das
  /// Blatt den direkten und sagt, warum).
  LoopPlan? _fun;
  bool _funEmpty = false;
  bool _fitted = false;

  /// Die Zwischenpunkte, mit denen das gezeigte Ergebnis gerechnet ist
  /// (#234), und ob es von Hand getunt ist.
  RouteVias _vias = RouteVias.none;
  bool _tuned = false;
  int _tuneSeq = 0;

  bool get _isTrail => widget.target.trail != null;

  @override
  void initState() {
    super.initState();
    _profile = ref.read(riderProfileProvider);
    _mode = widget.mode;
    WidgetsBinding.instance.addPostFrameCallback((_) => _compute());
  }

  Future<void> _compute() async {
    try {
      final fix = await ref.read(positionFixProvider)();
      if (!mounted) return;
      if (fix == null) {
        setState(() {
          _phase = _Phase.done;
          _blocker = _Blocker.noPosition;
        });
        return;
      }
      final from = LatLng(fix.latitude, fix.longitude);
      setState(() {
        _from = from;
        _phase = _Phase.loading;
      });
      final loaded = await ref.read(planningGraphLoaderProvider)(LatBox.of([
        from,
        widget.target.point,
        // Die Trails, die der spaßige Weg mitnehmen darf, gleich mit —
        // ein Wechsel auf „Spaßig" lädt dann nicht neu.
        ..._funPool(from).expand((t) => t.points),
      ]), fillOnline: LoopPrefs.parse(ref.read(settingsProvider).loopPlannerPrefs, _profile).fillOnline);
      if (!mounted) return;
      if (loaded.graph == null) {
        setState(() {
          _phase = _Phase.done;
          _blocker = _Blocker.noArea;
        });
        return;
      }
      _loaded = loaded;
      await _replan();
    } catch (e, s) {
      logError('Route planen', e, s);
      if (!mounted) return;
      setState(() {
        _phase = _Phase.done;
        _blocker = _Blocker.failed;
      });
    }
  }

  /// Die Abfahrten, die der spaßige Weg mitnehmen darf: in Reichweite des
  /// Starts, nicht weiter vom Ziel als der Start selbst plus 3 km, ohne
  /// Meldung — und nie der Ziel-Trail selbst (den fährt man danach).
  List<Trail> _funPool(LatLng from) {
    final trails = ref.read(trailsProvider).valueOrNull ?? const <Trail>[];
    final reach = haversineM(from.latitude, from.longitude, widget.target.point.latitude,
            widget.target.point.longitude) +
        3000;
    final pool = loopPoolOf(trails, from);
    bool near(LatLng p) =>
        haversineM(p.latitude, p.longitude, widget.target.point.latitude, widget.target.point.longitude) <= reach;
    return [
      for (final t in pool.inReach)
        if (t.id != widget.target.trail?.id && near(t.start) && near(t.end)) t,
    ];
  }

  /// Die Suche auf dem stehenden Graphen — beim ersten Mal und bei jedem
  /// Wechsel von Profil oder Weg. Eine spätere Rechnung (schneller
  /// Wechsel) überholt die frühere, auch einen laufenden Zug (`_tuneSeq`).
  Future<void> _replan() async {
    final graph = _loaded!.graph!;
    final from = _from!;
    final seq = ++_tuneSeq;
    setState(() => _phase = _Phase.computing);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || seq != _tuneSeq) return;
    final l = context.l10n;
    final prefs = LoopPrefs.parse(ref.read(settingsProvider).loopPlannerPrefs, _profile);
    final rider = _rider(prefs);
    try {
      final plan = planTrailHeadRoute(graph, from, widget.target.point, rider);
      LoopPlan? fun;
      var funEmpty = false;
      final direct = plan.route;
      if (_mode == RouteMode.fun && direct != null) {
        final result = planLoop(
          graph,
          start: from,
          end: widget.target.point,
          profile: rider,
          budget: _funBudget(direct, prefs),
          pool: [for (final t in _funPool(from)) poolTrailOf(l, t)],
          returnToStart: false,
        );
        if (result.outcome == LoopOutcome.ok && !result.isEmpty) {
          fun = result;
        } else {
          funEmpty = true;
        }
      }
      if (!mounted || seq != _tuneSeq) return;
      setState(() {
        _phase = _Phase.done;
        _plan = plan;
        _fun = fun;
        _funEmpty = funEmpty;
        _blocker = null;
        _vias = RouteVias.none;
        _tuned = false;
      });
      final lines = fun != null ? funPreviewLines(fun) : previewLinesOf(plan.route);
      // Frei gerechnet: Zwischenpunkte fangen neu an (#234).
      if (lines.isNotEmpty) {
        ref.read(routeViaProvider.notifier).begin(ViaOwner.route);
      } else {
        ref.read(routeViaProvider.notifier).end(ViaOwner.route);
      }
      if (lines.isEmpty) {
        // Kein Weg: Die Linie der vorigen Rechnung gehört nicht mehr dazu.
        ref.read(trailHeadPreviewProvider.notifier).state = const [];
        return;
      }
      if (!_fitted) await widget.panel.resizeTo(kMapPanelResult);
      if (!mounted || seq != _tuneSeq) return;
      ref.read(trailHeadPreviewProvider.notifier).state = lines;
      if (!_fitted) {
        _fitted = true;
        ref.read(mapFitRequestProvider.notifier).state = [for (final l in lines) ...l.points];
      }
    } catch (e, s) {
      logError('Route planen', e, s);
      if (!mounted || seq != _tuneSeq) return;
      // Das Blatt sagt „ging nicht" — dann liegt auch keine alte Linie mehr
      // auf der Karte, und es gibt keine Punkte zum Ziehen.
      ref.read(trailHeadPreviewProvider.notifier).state = const [];
      ref.read(routeViaProvider.notifier).end(ViaOwner.route);
      setState(() {
        _phase = _Phase.done;
        _plan = null;
        _fun = null;
        _blocker = _Blocker.failed;
      });
    }
  }

  LoopBudget _funBudget(TrailHeadRoute direct, LoopPrefs prefs) {
    final t = direct.summary.timeS, c = direct.summary.gainM;
    return LoopBudget(
      timeS: math.max(t * kFunTimeFactor, t + kFunExtraS) / (1 - kLoopTimeReserve),
      climbM: math.max(c * kFunClimbFactor, c + kFunExtraClimbM),
      hikingM: math.max(prefs.hikingKm * 1000, direct.summary.hikingM),
    );
  }

  /// Dieselbe Route durch [vias] (#234): der direkte Weg mit Punkten im
  /// einen Teilstück, der spaßige mit fester Folge der Trails. Das
  /// Ergebnis bleibt stehen, bis das neue da ist; geht es nicht, kommen
  /// die alten Punkte zurück.
  Future<void> _retune(RouteVias vias) async {
    final graph = _loaded?.graph;
    final from = _from;
    final direct = _plan?.route;
    if (graph == null || from == null || direct == null || _phase != _Phase.done) {
      ref.read(routeViaProvider.notifier).reject(_vias);
      return;
    }
    final seq = ++_tuneSeq;
    // Ein Bild, damit der Punkt dort steht, wo er losgelassen wurde.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || seq != _tuneSeq) return;
    final l = context.l10n;
    final prefs = LoopPrefs.parse(ref.read(settingsProvider).loopPlannerPrefs, _profile);
    final rider = _rider(prefs);
    try {
      final fun = _fun;
      TrailHeadPlan? plan;
      LoopPlan? tunedFun;
      if (fun != null) {
        tunedFun = planLoop(
          graph,
          start: from,
          end: widget.target.point,
          profile: rider,
          budget: _funBudget(direct, prefs),
          pool: [for (final t in _funPool(from)) poolTrailOf(l, t)],
          returnToStart: false,
          tune: LoopTune.of(fun, vias),
        );
        if (tunedFun.outcome != LoopOutcome.ok) tunedFun = null;
      } else {
        plan = planTrailHeadRoute(graph, from, widget.target.point, rider, via: vias.of(0));
        if (plan.route == null) plan = null;
      }
      if (!mounted || seq != _tuneSeq) return;
      if (plan == null && tunedFun == null) {
        ref.read(routeViaProvider.notifier).reject(_vias);
        return;
      }
      setState(() {
        if (plan != null) _plan = plan;
        if (tunedFun != null) _fun = tunedFun;
        _vias = vias;
        _tuned = true;
      });
      ref.read(trailHeadPreviewProvider.notifier).state =
          tunedFun != null ? funPreviewLines(tunedFun) : previewLinesOf(plan!.route);
    } catch (e, s) {
      logError('Route tunen', e, s);
      if (!mounted || seq != _tuneSeq) return;
      ref.read(routeViaProvider.notifier).reject(_vias);
    }
  }

  String get _rideName {
    final l = context.l10n;
    return _isTrail ? l.routeNameTrailHead(widget.target.title) : l.routeNamePoint(widget.target.title);
  }

  List<LatLng>? get _points => _fun?.points ?? _plan?.route?.points;

  /// Die Abschnitte für die Navigation (9.9): beim spaßigen Weg die Trails
  /// der Runde, sonst der Ziel-Trail hinter dem Ende der Linie.
  NavSections _navSections() {
    final fun = _fun;
    if (fun != null) return navSectionsOfLoop(context.l10n, fun, trailById: trailByIdOf(ref));
    final route = _plan?.route;
    final target = widget.target.trail;
    if (route == null || target == null) return NavSections.none;
    return navSectionsOfTrailHead(context.l10n, route, target);
  }
  double? get _timeS => _fun?.summary?.timeS ?? _plan?.route?.summary.timeS;

  /// Den Weg als geplante Fahrt in „Meine Fahrten" (#158 Schritt 5) —
  /// damit er auf der Karte bleibt und als GPX wiederkommt.
  Future<void> _saveRide() async {
    final points = _points;
    if (points == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final now = DateTime.now().toUtc();
    final ride = await ref.read(ridesProvider.notifier).savePlanned(
          name: _rideName,
          points: [for (final p in points) RidePoint(lat: p.latitude, lng: p.longitude, at: now, accuracyM: 0)],
          duration: Duration(seconds: routeSeconds(_timeS ?? 0)),
          profile: _profile.name,
        );
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
        content: Text(ride == null ? l.routeSaveFailed : l.routingSavedAsRide)));
  }

  void _exportGpx() {
    final points = _points;
    if (points == null) return;
    final track = GpxTrack(name: _rideName, points: [for (final p in points) TrackPoint(p.latitude, p.longitude)]);
    shareGpx(context, ref, fileName: gpxFileName(track.name), xml: writeGpx(name: track.name, points: track.points));
  }

  /// Das (kalibrierte) Rad mit den gemerkten Vorlieben; „Bequem" legt den
  /// Stil darüber (#329) — Tempo und Zeit bleiben die des Rads.
  RiderParams _rider(LoopPrefs prefs) => ref
      .read(calibratedRiderProvider(_profile))
      .withPrefs(_mode == RouteMode.easy ? prefs.route.copyWith(easy: true) : prefs.route);

  void _setMode(RouteMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    if (_loaded?.graph != null && _from != null) unawaited(_replan());
  }

  @override
  Widget build(BuildContext context) {
    // Die Karte ändert die Punkte, hier wird gerechnet (#234).
    ref.listen(routeViaProvider, (_, next) {
      if (next == null || next.owner != ViaOwner.route || next.vias == _vias) return;
      unawaited(_retune(next.vias));
    });
    final target = widget.target;
    final hasRoute = _points != null;
    final l = context.l10n;
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 24),
      children: [
        MapPanelHeader(
          title: _isTrail ? l.routeTitleTrailHead : l.routeTitlePoint,
          subtitle: target.title,
          closeKey: const ValueKey('trail-head-close'),
          onClose: widget.panel.close,
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ..._body(context),
              const SizedBox(height: 16),
              Row(
                children: [
                  // „Navigieren" vorn (#232): die eigene Folgeansicht; die
                  // Navi-App bleibt „Anfahrt" daneben.
                  if (hasRoute) ...[
                    Expanded(
                      child: FilledButton.icon(
                        key: const ValueKey('trail-head-follow'),
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        onPressed: () => ref.read(navRequestProvider.notifier).state =
                            NavRequest(points: _points!, title: _rideName, sections: _navSections()),
                        icon: const Icon(Icons.navigation_outlined),
                        label: Text(l.commonNavigate),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('trail-head-navigate'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: () => target.trail != null
                          ? navigateToTrailHead(context, target.trail!)
                          : navigateToPoint(context, target.point),
                      icon: const Icon(Icons.directions_outlined),
                      label: Text(l.sheetNavigate),
                    ),
                  ),
                ],
              ),
              if (hasRoute)
                Wrap(children: [
                  TextButton.icon(
                    key: const ValueKey('trail-head-save'),
                    onPressed: _saveRide,
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: Text(l.routeSaveAsRide),
                  ),
                  TextButton.icon(
                    key: const ValueKey('trail-head-gpx'),
                    onPressed: _exportGpx,
                    icon: const Icon(Icons.share_outlined),
                    label: Text(l.routingAsGpx),
                  ),
                ]),
              Text(
                l.routingNoTurnHints,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _body(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    switch (_phase) {
      case _Phase.locating:
        return [_progress(l.routingLocating)];
      case _Phase.loading:
        return [_progress(l.routingLoadingWays)];
      case _Phase.computing:
        return [_progress(l.routeComputing)];
      case _Phase.done:
        break;
    }
    final blocker = _blocker;
    if (blocker != null) return [_notice(context, _blockerText(l, blocker))];
    final plan = _plan!;
    final route = plan.route;
    if (route == null) return [_notice(context, _outcomeText(l, plan.outcome))];
    final palette = AppPalette.of(context);
    final fun = _fun;
    final length = fun?.summary?.lengthM ?? route.summary.lengthM;
    final gain = fun?.summary?.gainM ?? route.summary.gainM;
    final loss = fun?.summary?.lossM ?? route.summary.lossM;
    final time = fun?.summary?.timeS ?? route.summary.timeS;
    final hiking = fun?.summary?.hikingM ?? route.summary.hikingM;
    final complete = fun?.summary?.heightsComplete ?? route.summary.heightsComplete;
    final steep = fun?.summary?.steepM ?? route.summary.steepM;
    final upM = fun?.summary?.trailUpM ?? route.summary.trailUpM;
    final upNames = fun?.summary?.trailUpNames ?? {for (final s in route.sections) if (s.trail?.connector ?? false) s.trail!.name}.toList();
    return [
      // Direkt, spaßig oder bequem (#176, #329): derselbe Graph, eine
      // andere Frage.
      SegmentedButton<RouteMode>(
        key: const ValueKey('route-mode'),
        segments: [
          ButtonSegment(value: RouteMode.direct, label: Text(l.routeModeDirect), icon: const Icon(Icons.straight)),
          ButtonSegment(value: RouteMode.fun, label: Text(l.routeModeFun), icon: const Icon(Icons.downhill_skiing)),
          ButtonSegment(value: RouteMode.easy, label: Text(l.routeModeEasy), icon: const Icon(Icons.directions_bike)),
        ],
        selected: {_mode},
        showSelectedIcon: false,
        onSelectionChanged: (sel) => _setMode(sel.single),
      ),
      const SizedBox(height: 12),
      Text(
        key: const ValueKey('trail-head-summary'),
        l.routeSummary(formatMeters(length), gain.round(), loss.round(), routeTimeLabel(l, time)),
        style: theme.textTheme.titleMedium?.copyWith(fontFamily: AppFonts.mono),
      ),
      const SizedBox(height: 4),
      if (fun != null) ...[
        Text(
          key: const ValueKey('route-fun-stops'),
          l.routeFunStops(fun.stops.length, fun.stops.map((s) => s.trail.name).toSet().join(', '),
              formatMeters(fun.summary!.trailM)),
          style: theme.textTheme.bodyMedium,
        ),
        Text(wayMixLine(l, fun.summary!.mix), style: theme.textTheme.bodyMedium),
      ] else
        Text(wayMixLine(l, route.summary.mix), style: theme.textTheme.bodyMedium),
      // Das Profil des Wegs (#234), wie im Ergebnis der Runde.
      RouteElevationProfile(fun?.points ?? route.points, key: const ValueKey('trail-head-elevation')),
      RouteTuneNote(tuned: _tuned, onReset: () => unawaited(_replan()), keyPrefix: 'trail-head'),
      if (_mode == RouteMode.easy) ...[
        const SizedBox(height: 8),
        Text(key: const ValueKey('route-easy-note'), l.routeEasyNote, style: theme.textTheme.bodyMedium),
      ],
      if (_mode == RouteMode.fun && _funEmpty) ...[
        const SizedBox(height: 8),
        Text(
          key: const ValueKey('route-fun-empty'),
          l.routeFunEmpty,
          style: theme.textTheme.bodyMedium,
        ),
      ],
      if (upM > 0) ...[
        const SizedBox(height: 4),
        Text(l.routingTrailUp(formatMeters(upM), upNames.join(', ')), style: theme.textTheme.bodyMedium),
      ],
      if (hiking > 0) ...[
        const SizedBox(height: 8),
        Text(
          l.routingHikingWarning(formatMeters(hiking)),
          style: theme.textTheme.bodyMedium?.copyWith(color: palette.warningText),
        ),
      ],
      if (_loaded == null ? null : planningCoverageNote(l, _loaded!, loop: false) case final note?) ...[
        const SizedBox(height: 8),
        Text(
          key: const ValueKey('trail-head-partial'),
          note,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      ],
      if (steepNote(l, steep) case final note?) ...[
        const SizedBox(height: 8),
        Text(
          key: const ValueKey('trail-head-steep'),
          note,
          style: theme.textTheme.bodySmall?.copyWith(color: palette.warningText),
        ),
      ],
      if (!complete) ...[
        const SizedBox(height: 8),
        Text(
          l.routingHeightsIncomplete,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      ],
      const SizedBox(height: 12),
      SegmentedButton<RiderProfile>(
        key: const ValueKey('trail-head-profile'),
        segments: [
          for (final p in RiderProfile.values) ButtonSegment(value: p, label: Text(p.label(l))),
        ],
        selected: {_profile},
        showSelectedIcon: false,
        onSelectionChanged: (sel) {
          _profile = sel.single;
          unawaited(_replan());
        },
      ),
    ];
  }

  Widget _progress(String text) => Row(
        children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      );

  Widget _notice(BuildContext context, String text) => Text(
        key: const ValueKey('trail-head-notice'),
        text,
        style: Theme.of(context).textTheme.bodyMedium,
      );

  String _blockerText(AppLocalizations l, _Blocker b) => switch (b) {
        _Blocker.noPosition => l.routeBlockerNoPosition,
        _Blocker.noArea => _isTrail ? l.routeBlockerNoAreaTrailHead : l.routeBlockerNoAreaPoint,
        _Blocker.failed => l.routeBlockerFailed,
      };

  String _outcomeText(AppLocalizations l, TrailHeadOutcome o) => switch (o) {
        TrailHeadOutcome.ok => '',
        TrailHeadOutcome.startOffNetwork => l.routeOutcomeStartOff(kGraphAttachM.round()),
        TrailHeadOutcome.headOffNetwork => _isTrail
            ? l.routeOutcomeHeadOff(kGraphAttachM.round())
            : l.routeOutcomeTargetOff(kGraphAttachM.round()),
        TrailHeadOutcome.viaOffNetwork => l.routeOutcomeViaOff(kGraphAttachM.round()),
        TrailHeadOutcome.noPath => _isTrail ? l.routeOutcomeNoPathTrailHead : l.routeOutcomeNoPathPoint,
      };
}

/// Die Vorschau: das Band der Route (#295), Wanderweg und Co. gestrichelt
/// in der Mitte. Ein Tipp setzt einen Zwischenpunkt (#234) — es gibt ein
/// Teilstück (0).
List<MapViewPolyline> previewLinesOf(TrailHeadRoute? route) {
  if (route == null) return const [];
  final hit = RouteLegHit(0, route.points);
  return routeBandLines(route.points, opacity: kRoutePreviewOpacity, pieces: [
    for (final s in route.sections) (points: s.points, hiking: s.hiking, hitValue: hit),
  ]);
}

/// Der spaßige Weg: dieselbe Sprache wie die Runde.
List<MapViewPolyline> funPreviewLines(LoopPlan plan) => loopPreviewLines(plan);
