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
import 'loop_planner_sheet.dart' show loopPreviewLines;
import 'map_panel.dart';
import 'planning_graph.dart';
import 'ride_calibrator.dart';
import 'road_graph.dart';
import 'route_elevation.dart';
import 'route_profile.dart';
import 'route_search.dart' show steepNote;
import 'route_via_providers.dart';
import 'route_vias.dart';
import 'via_handles.dart';
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
  factory RouteTarget.trailHead(Trail t) => RouteTarget(point: t.start, title: t.displayName, trail: t);

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
    showRouteSheet(scaffold, RouteTarget.trailHead(trail), mode: mode);

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
  /// Wechsel von Profil oder Weg.
  Future<void> _replan() async {
    final graph = _loaded!.graph!;
    final from = _from!;
    setState(() => _phase = _Phase.computing);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final prefs = LoopPrefs.parse(ref.read(settingsProvider).loopPlannerPrefs, _profile);
    final rider = ref.read(calibratedRiderProvider(_profile)).withPrefs(prefs.route);
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
          pool: [for (final t in _funPool(from)) poolTrailOf(t)],
          returnToStart: false,
        );
        if (result.outcome == LoopOutcome.ok && !result.isEmpty) {
          fun = result;
        } else {
          funEmpty = true;
        }
      }
      if (!mounted) return;
      _tuneSeq++;
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
      if (lines.isEmpty) return;
      if (!_fitted) await widget.panel.resizeTo(kMapPanelResult);
      if (!mounted) return;
      ref.read(trailHeadPreviewProvider.notifier).state = lines;
      if (!_fitted) {
        _fitted = true;
        ref.read(mapFitRequestProvider.notifier).state = [for (final l in lines) ...l.points];
      }
    } catch (e, s) {
      logError('Route planen', e, s);
      if (!mounted) return;
      setState(() {
        _phase = _Phase.done;
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
    final prefs = LoopPrefs.parse(ref.read(settingsProvider).loopPlannerPrefs, _profile);
    final rider = ref.read(calibratedRiderProvider(_profile)).withPrefs(prefs.route);
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
          pool: [for (final t in _funPool(from)) poolTrailOf(t)],
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

  String get _rideName =>
      _isTrail ? 'Zum Trailkopf: ${widget.target.title}' : 'Route: ${widget.target.title}';

  List<LatLng>? get _points => _fun?.points ?? _plan?.route?.points;
  double? get _timeS => _fun?.summary?.timeS ?? _plan?.route?.summary.timeS;

  /// Den Weg als geplante Fahrt in „Meine Fahrten" (#158 Schritt 5) —
  /// damit er auf der Karte bleibt und als GPX wiederkommt.
  Future<void> _saveRide() async {
    final points = _points;
    if (points == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final now = DateTime.now().toUtc();
    final ride = await ref.read(ridesProvider.notifier).savePlanned(
          name: _rideName,
          points: [for (final p in points) RidePoint(lat: p.latitude, lng: p.longitude, at: now, accuracyM: 0)],
          duration: Duration(seconds: (_timeS ?? 0).round()),
          profile: _profile.name,
        );
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
        content: Text(ride == null
            ? 'Der Weg ließ sich nicht speichern.'
            : 'Als geplante Fahrt gespeichert — im Profil unter „Meine Fahrten".')));
  }

  void _exportGpx() {
    final points = _points;
    if (points == null) return;
    final track = GpxTrack(name: _rideName, points: [for (final p in points) TrackPoint(p.latitude, p.longitude)]);
    shareGpx(context, ref, fileName: gpxFileName(track.name), xml: writeGpx(name: track.name, points: track.points));
  }

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
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 24),
      children: [
        MapPanelHeader(
          title: _isTrail ? 'Zum Trailkopf' : 'Route hierher',
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
                  if (hasRoute) ...[
                    Expanded(
                      child: FilledButton.icon(
                        key: const ValueKey('trail-head-gpx'),
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        onPressed: _exportGpx,
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('Als GPX'),
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
                      label: const Text('Anfahrt'),
                    ),
                  ),
                ],
              ),
              if (hasRoute)
                TextButton.icon(
                  key: const ValueKey('trail-head-save'),
                  onPressed: _saveRide,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Als Fahrt speichern'),
                ),
              Text(
                'Ein Vorschlag aus Kartendaten, ohne Abbiegehinweise — fahre nach Sicht.',
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
    switch (_phase) {
      case _Phase.locating:
        return [_progress('Standort wird ermittelt …')];
      case _Phase.loading:
        return [_progress('Wege und Höhen aus deinen Bereichen werden gelesen …')];
      case _Phase.computing:
        return [_progress('Der Weg wird gerechnet …')];
      case _Phase.done:
        break;
    }
    final blocker = _blocker;
    if (blocker != null) return [_notice(context, _blockerText(blocker))];
    final plan = _plan!;
    final route = plan.route;
    if (route == null) return [_notice(context, _outcomeText(plan.outcome))];
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
      // Direkt oder spaßig (#176): derselbe Graph, eine andere Frage.
      SegmentedButton<RouteMode>(
        key: const ValueKey('route-mode'),
        segments: const [
          ButtonSegment(value: RouteMode.direct, label: Text('Direkt'), icon: Icon(Icons.straight)),
          ButtonSegment(value: RouteMode.fun, label: Text('Spaßig'), icon: Icon(Icons.downhill_skiing)),
        ],
        selected: {_mode},
        showSelectedIcon: false,
        onSelectionChanged: (sel) => _setMode(sel.single),
      ),
      const SizedBox(height: 12),
      Text(
        key: const ValueKey('trail-head-summary'),
        '${formatMeters(length)} · ${gain.round()} hm bergauf · '
        '${loss.round()} hm bergab · etwa ${routeTimeLabel(time)}',
        style: theme.textTheme.titleMedium?.copyWith(fontFamily: AppFonts.mono),
      ),
      const SizedBox(height: 4),
      if (fun != null) ...[
        Text(
          key: const ValueKey('route-fun-stops'),
          'Mit ${fun.stops.length == 1 ? 'dem Trail' : 'den Trails'} '
          '${fun.stops.map((s) => s.trail.name).toSet().join(', ')} · '
          '${formatMeters(fun.summary!.trailM)} Trail',
          style: theme.textTheme.bodyMedium,
        ),
        Text(_mixLine(fun.summary!.mix), style: theme.textTheme.bodyMedium),
      ] else
        Text(_mixLine(route.summary.mix), style: theme.textTheme.bodyMedium),
      // Das Profil des Wegs (#234), wie im Ergebnis der Runde.
      RouteElevationProfile(fun?.points ?? route.points, key: const ValueKey('trail-head-elevation')),
      RouteTuneNote(tuned: _tuned, onReset: () => unawaited(_replan()), keyPrefix: 'trail-head'),
      if (_mode == RouteMode.fun && _funEmpty) ...[
        const SizedBox(height: 8),
        Text(
          key: const ValueKey('route-fun-empty'),
          'Auf dem Weg dorthin passt kein Trail in den Umweg — das ist der direkte Weg.',
          style: theme.textTheme.bodyMedium,
        ),
      ],
      if (upM > 0) ...[
        const SizedBox(height: 4),
        Text('Bergauf ${formatMeters(upM)} über ${upNames.join(', ')}', style: theme.textTheme.bodyMedium),
      ],
      if (hiking > 0) ...[
        const SizedBox(height: 8),
        Text(
          'Davon ${formatMeters(hiking)} über Wanderweg, Fußweg oder Stufen — '
          'ob du dort fahren darfst, sagt die App nicht.',
          style: theme.textTheme.bodyMedium?.copyWith(color: palette.warningText),
        ),
      ],
      if (_loaded == null ? null : planningCoverageNote(_loaded!, what: 'der Weg') case final note?) ...[
        const SizedBox(height: 8),
        Text(
          key: const ValueKey('trail-head-partial'),
          note,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      ],
      if (steepNote(steep) case final note?) ...[
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
          'Nicht alle Wege haben Höhen — Höhenmeter und Zeit sind eine Untergrenze. '
          'Ein neu gespeicherter Bereich bringt sie mit.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      ],
      const SizedBox(height: 12),
      SegmentedButton<RiderProfile>(
        key: const ValueKey('trail-head-profile'),
        segments: [
          for (final p in RiderProfile.values) ButtonSegment(value: p, label: Text(p.label)),
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

  String get _goal => _isTrail ? 'zum Trailkopf' : 'zum Ziel';

  String _blockerText(_Blocker b) => switch (b) {
        _Blocker.noPosition => 'Kein Standort — ohne ihn gibt es keinen Startpunkt. Erlaube '
            'TrailBuddy den Standort, oder nimm „Anfahrt": Die Navi-App kennt den Weg auch.',
        _Blocker.noArea => 'Kein gespeicherter Bereich deckt den Weg von deinem Standort $_goal, und online '
            'kam kein Weg dazu (kein Empfang, oder „Fehlende Wege online ergänzen" in den Parametern des '
            'Planers ist aus). Speichere einen Bereich über den Knopf „Offline-Karten" auf der Karte.',
        _Blocker.failed => 'Der Weg ließ sich nicht rechnen — ein Fehler, der gemeldet ist. '
            'Nimm „Anfahrt", die Navi-App kennt den Weg auch.',
      };

  String _outcomeText(TrailHeadOutcome o) => switch (o) {
        TrailHeadOutcome.ok => '',
        TrailHeadOutcome.startOffNetwork =>
          'In ${kGraphAttachM.round()} m um deinen Standort liegt kein Weg aus der Karte.',
        TrailHeadOutcome.headOffNetwork => _isTrail
            ? 'In ${kGraphAttachM.round()} m um den Trailkopf liegt kein Weg aus der Karte.'
            : 'In ${kGraphAttachM.round()} m um das Ziel liegt kein Weg aus der Karte.',
        TrailHeadOutcome.viaOffNetwork => 'In ${kGraphAttachM.round()} m um einen Zwischenpunkt liegt kein Weg.',
        TrailHeadOutcome.noPath => 'Die Wege in deinen Bereichen verbinden Standort und '
            '${_isTrail ? 'Trailkopf' : 'Ziel'} nicht — vielleicht fehlt ein Stück Bereich dazwischen.',
      };
}

/// „Forstweg 2,1 km · Nebenstraße 300 m" — die Klassen nach Länge.
String _mixLine(Map<WayClass, double> mix) {
  final entries = mix.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return entries.map((e) => '${e.key.label} ${formatMeters(e.value)}').join(' · ');
}

/// Die Vorschau: je Abschnitt eine Linie in der Fahrt-Farbe, Wanderweg
/// und Co. gestrichelt — dieselbe Sprache wie die Fahrt, kein Tipp-Ziel.
/// Die Verbinder zu Standort und Trailkopf blass und dünn.
List<MapViewPolyline> previewLinesOf(TrailHeadRoute? route) {
  if (route == null) return const [];
  final c = AppColors.mapLines.ride;
  // Ein Teilstück (0): ein Tipp setzt dort einen Zwischenpunkt (#234).
  final hit = RouteLegHit(0, route.points);
  return [
    MapViewPolyline(
      points: route.points,
      color: c.withValues(alpha: 0.35),
      width: 2,
    ),
    for (final s in route.sections)
      MapViewPolyline(
        points: s.points,
        color: c,
        width: 5,
        dash: s.hiking ? const [10, 8] : null,
        borderColor: AppColors.mapLines.halo,
        borderWidth: AppColors.mapLines.haloBorderWidth,
        hitValue: hit,
      ),
  ];
}

/// Der spaßige Weg: dieselbe Sprache wie die Runde.
List<MapViewPolyline> funPreviewLines(LoopPlan plan) => loopPreviewLines(plan);
