// Die Blätter des Planers (#158 Schritt 5, seit 0.74.0 als Modus mit
// Leiste, `loop_tool_rail.dart`; Zustand in `loop_planner_controller.dart`):
//
// - **Anpassen** (Knopf im Kopf des Planers, #516): Rad, Zeit und
//   Höhenmeter, eingeklappt die Feinheiten (Wanderweg, Radius der Liste,
//   Vorlieben, Online ergänzen). Die Regler merkt sich das Gerät. Start
//   und Ziel stehen im Kopf (`loop_edit_bars.dart`).
// - **Liste** (Knopf „Liste"): die wählbaren Trails im Radius um den Start,
//   mit Haken, Stern („muss dabei sein"), „Alle" und „Keine". Gemeldete
//   stehen abseits; Uphill-Trails und Verbinder sind nicht wählbar — die
//   Runde nutzt sie von selbst bergauf (#185).
// - **Ergebnis** („Runde rechnen" / „Route rechnen" unten): kein Modal
//   (`map_panel.dart`), die Karte bleibt bedienbar; Fortschritt, der Grund, wenn es nicht geht,
//   oder Summen, Reihenfolge, Ausgelassene, „Als Fahrt speichern", „Als
//   GPX". Beim Ergebnis klappt es ein und die Karte passt die Runde
//   DARÜBER ein. Zu heißt: Ergebnis weg, Modus und Auswahl bleiben.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/l10n.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart' show AppFonts;
import '../../core/geo.dart' show formatMeters;
import '../../core/gpx_share.dart';
import '../../models/trail.dart';
import '../map/map_view/map_view.dart';
import '../garmin/watch_providers.dart' show watchSyncProvider;
import '../official/official_trails_source.dart';
import '../rides/ride_providers.dart';
import '../rides/ride_track.dart';
import '../trails/gpx.dart';
import '../trails/gpx_writer.dart';
import '../trails/trail_navigation.dart';
import '../trails/trail_providers.dart';
import 'loop_planner.dart';
import 'loop_planner_controller.dart';
import 'loop_planner_providers.dart';
import 'map_panel.dart';
import 'nav_providers.dart';
import 'nav_sections.dart';
import 'nav_view.dart' show NavStartButton, NavStartOptions, navStartChoiceOf;
import 'planning_graph.dart' show planningCoverageNote;
import 'road_graph.dart';
import 'road_graph_loader.dart' show kOnlineFillMaxTiles, kPlanMaxTiles;
import 'route_elevation.dart';
import 'route_profile.dart';
import 'route_search.dart' show steepNote;
import 'route_band.dart';
import 'route_vias.dart';
import 'via_handles.dart';
import 'trail_head_route.dart' show routeSeconds, routeTimeLabel;

/// Breite der leuchtenden Auswahl auf der Karte (#178) — breiter als eine
/// Verbindung, schmaler als der Leuchtrand des ausgewählten Trails (16).
/// Deckendes Lime mit dunkler Kontur wie dort (#233, wie #195): 55 %
/// Lime ohne Kontur ging im weißen Saum der Trails unter — gewählt war,
/// zu sehen war nichts.
const kLoopPickWidth = 12.0;

/// Wie weit neben einer Trail-Linie ein Tipp im Planer noch trifft (#375,
/// Betreiber 2026-10-18: nur auf der Linie selbst). Auf der normalen Karte
/// sind es `kMapTapSlopPx` (12) — dort hebt ein Tipp nur hervor, im Planer
/// ändert er die Auswahl, und am Pixel traf ein Tipp neben die Linie (auf
/// einen Weg, zum Wegtippen) mehrmals den Trail.
const kLoopTapSlopPx = 4.0;

/// Kontur der Auswahl; Pflicht-Trails tragen sie stärker und deckend.
const kLoopPickBorder = 2.0;
const kLoopPickBorderMandatory = 3.5;

/// Die Fahne des getippten Starts (#233): Lime auf hellem Grund braucht
/// einen dunklen Rand — acht scharfe Schatten ringsum als Kontur, ein
/// weicher als Schein. Mit [finish] die Zielfahne (#331), kariert, in
/// derselben Machart.
class LoopStartFlag extends StatelessWidget {
  const LoopStartFlag({super.key, this.size = 32, this.finish = false});

  final double size;
  final bool finish;

  static const _contour = AppColors.onBrand;

  @override
  Widget build(BuildContext context) => Icon(
        finish ? Icons.sports_score : Icons.flag,
        size: size,
        color: AppColors.brand,
        shadows: [
          for (final (dx, dy) in const [(-1.0, -1.0), (0.0, -1.5), (1.0, -1.0), (1.5, 0.0), (1.0, 1.0), (0.0, 1.5), (-1.0, 1.0), (-1.5, 0.0)])
            Shadow(color: _contour, offset: Offset(dx, dy)),
          Shadow(color: _contour.withValues(alpha: 0.6), blurRadius: 6),
        ],
      );
}

/// Ein vorab gesetzter Zwischenpunkt (#331 Schritt 4): eine Lime-Scheibe
/// mit der Nummer des Setzens — Marke wie die Fahnen, rund wie die
/// Gummipunkte (#234), damit man sieht, dass er zur Planung gehört. Die
/// Fläche ist 44 dp (Tippziel), sichtbar sind 26.
class LoopWaypointPin extends StatelessWidget {
  const LoopWaypointPin({super.key, required this.number});

  static const size = 44.0;
  static const _dot = 26.0;

  final int number;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: _dot,
          height: _dot,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.brand,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.onBrand, width: 2),
            boxShadow: const [BoxShadow(blurRadius: 4, offset: Offset(0, 1), color: Color(0x55000000))],
          ),
          child: Text('$number',
              style: AppFonts.numbers(Theme.of(context).textTheme.labelMedium)
                  .copyWith(color: AppColors.onBrand, fontWeight: FontWeight.w700, height: 1)),
        ),
      );
}

// ─── Anpassen ───────────────────────────────────────────────────────────

/// „Anpassen" aus dem Kopf des Planers (#516, Konzept-Routing 12.7): in
/// zwei Stufen — Rad, Zeit und Höhenmeter sofort, alles, was man einmal
/// stellt, eingeklappt unter „Feinheiten". Start, Ziel und Zwischenpunkte
/// stehen nicht mehr hier, sondern im Kopf und auf der Karte.
Future<void> showLoopParamsSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (context, scroll) => _ParamsSheet(scroll: scroll),
      ),
    );

class _ParamsSheet extends ConsumerWidget {
  const _ParamsSheet({required this.scroll});

  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(loopPlannerProvider);
    final notifier = ref.read(loopPlannerProvider.notifier);
    final prefs = session.prefs;
    final l = context.l10n;
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text(prefs.endMode == LoopEndMode.loop ? l.loopParamsTitle : l.routeParamsTitle,
            style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        SegmentedButton<RiderProfile>(
          key: const ValueKey('loop-profile'),
          segments: [for (final p in RiderProfile.values) ButtonSegment(value: p, label: Text(p.label(l)))],
          selected: {session.profile},
          showSelectedIcon: false,
          onSelectionChanged: (sel) => notifier.setProfile(sel.single),
        ),
        const SizedBox(height: 12),
        _LoopSlider(
          key: const ValueKey('loop-time'),
          label: l.loopMaxTime(loopHoursLabel(l, prefs.hours)),
          value: prefs.hours,
          min: LoopPrefs.minHours,
          max: LoopPrefs.maxHours,
          step: LoopPrefs.hoursStep,
          onChanged: (v) => notifier.setPrefs(prefs.copyWith(hours: v)),
        ),
        _LoopSlider(
          key: const ValueKey('loop-climb'),
          label: l.loopMaxClimb(prefs.climbM.round()),
          value: prefs.climbM,
          min: LoopPrefs.minClimb,
          max: LoopPrefs.maxClimb,
          step: LoopPrefs.climbStep,
          onChanged: (v) => notifier.setPrefs(prefs.copyWith(climbM: v)),
        ),
        // Was man einmal stellt (Konzept-Routing 12.7): eingeklappt.
        Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const ValueKey('loop-fine'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: Text(l.loopFine, style: theme.textTheme.titleSmall),
            children: [
              _LoopSlider(
                key: const ValueKey('loop-hiking'),
                label: prefs.hikingKm == 0 ? l.loopNoHiking : l.loopMaxHiking(formatMeters(prefs.hikingKm * 1000)),
                value: prefs.hikingKm,
                min: LoopPrefs.minHikingKm,
                max: LoopPrefs.maxHikingKm,
                step: LoopPrefs.hikingStep,
                onChanged: (v) => notifier.setPrefs(prefs.copyWith(hikingKm: v)),
              ),
              _LoopSlider(
                key: const ValueKey('loop-radius'),
                label: l.loopRadius(prefs.radiusKm.round()),
                value: prefs.radiusKm,
                min: LoopPrefs.minRadiusKm,
                max: LoopPrefs.maxRadiusKm,
                step: LoopPrefs.radiusStep,
                onChanged: (v) => notifier.setPrefs(prefs.copyWith(radiusKm: v)),
              ),
              const SizedBox(height: 4),
              Text(l.loopOnTheWay, style: theme.textTheme.titleSmall),
              // Zu einem Ziel sagt das der Stil im Ergebnis (#356 PR 7b).
              if (prefs.endMode != LoopEndMode.target)
                _PrefSwitch(
                  tileKey: const ValueKey('loop-easy-up'),
                  title: l.loopEasyUp,
                  on: l.loopEasyUpOn,
                  off: l.loopEasyUpOff,
                  value: prefs.easyUp,
                  onChanged: (v) => notifier.setPrefs(prefs.copyWith(easyUp: v)),
                ),
              _PrefSwitch(
                tileKey: const ValueKey('loop-pref-roads'),
                title: l.loopPrefRoads,
                on: l.loopPrefRoadsOn,
                off: l.loopPrefRoadsOff,
                value: prefs.route.avoidRoads,
                onChanged: (v) => notifier.setPrefs(prefs.copyWith(route: prefs.route.copyWith(avoidRoads: v))),
              ),
              _PrefSwitch(
                tileKey: const ValueKey('loop-pref-hiking'),
                title: l.loopPrefHiking,
                on: l.loopPrefHikingOn,
                off: l.loopPrefHikingOff,
                value: prefs.route.avoidHiking,
                onChanged: (v) => notifier.setPrefs(prefs.copyWith(route: prefs.route.copyWith(avoidHiking: v))),
              ),
              _PrefSwitch(
                tileKey: const ValueKey('loop-pref-steep'),
                title: l.loopPrefSteep,
                on: l.loopPrefSteepOn,
                off: l.loopPrefSteepOff,
                value: prefs.route.avoidSteep,
                onChanged: (v) => notifier.setPrefs(prefs.copyWith(route: prefs.route.copyWith(avoidSteep: v))),
              ),
              Text(
                l.loopPrefsNote,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                key: const ValueKey('loop-fill-online'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.loopFillOnline),
                subtitle: Text(prefs.fillOnline ? l.loopFillOnlineOn(kOnlineFillMaxTiles) : l.loopFillOnlineOff),
                value: prefs.fillOnline,
                onChanged: (v) => notifier.setPrefs(prefs.copyWith(fillOnline: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l.loopParamsExplain,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      ],
    );
  }
}

/// Ein Schalter der Vorlieben (#188): meiden (an) oder egal (aus), mit
/// einem Satz, was er gerade bewirkt.
class _PrefSwitch extends StatelessWidget {
  const _PrefSwitch({
    required this.tileKey,
    required this.title,
    required this.on,
    required this.off,
    required this.value,
    required this.onChanged,
  });

  final Key tileKey;
  final String title;
  final String on;
  final String off;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        key: tileKey,
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(value ? on : off),
        value: value,
        onChanged: onChanged,
      );
}

class _LoopSlider extends StatelessWidget {
  const _LoopSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: AppFonts.mono)),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: ((max - min) / step).round(),
          onChanged: onChanged,
        ),
      ]);
}

// ─── Liste ──────────────────────────────────────────────────────────────

/// Die Liste braucht einen Mittelpunkt: getippter Start oder Standort.
/// Ohne beides sagt eine Leiste, wie es weitergeht.
Future<void> showLoopListSheet(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final center = await ref.read(loopPlannerProvider.notifier).listCenter();
  if (!context.mounted) return;
  if (center == null) {
    messenger.showSnackBar(SnackBar(
        key: const ValueKey('loop-list-no-center'), content: Text(context.l10n.loopListNoCenter)));
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, scroll) => _ListSheet(scroll: scroll, center: center),
    ),
  );
}

class _ListSheet extends ConsumerWidget {
  const _ListSheet({required this.scroll, required this.center});

  final ScrollController scroll;
  final LatLng center;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final session = ref.watch(loopPlannerProvider);
    final notifier = ref.read(loopPlannerProvider.notifier);
    final trails = ref.watch(trailsProvider).valueOrNull ?? const <Trail>[];
    final radius = session.prefs.radiusKm;
    final pool = loopPoolOf(trails, center, reachM: radius * 1000);
    final ids = [for (final t in pool.inReach) t.id];
    // Gewählt, aber nicht in der Liste (Radius verkleinert, auf der Karte
    // getippt, #411): Sie zählen in der Leiste und im Rahmen mit, also
    // sagt die Liste, dass es sie gibt, und „Keine" nimmt auch sie weg.
    final listed = {...ids, for (final t in pool.warned) t.id};
    final outside = session.selected.where((id) => !listed.contains(id)).length;
    final l = context.l10n;
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text(l.loopListTitle(radius.round()), style: theme.textTheme.titleLarge),
        Text(
          session.start == null ? l.loopListAroundMe : l.loopListAroundStart,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
        Row(children: [
          TextButton(
            key: const ValueKey('loop-list-all'),
            onPressed: ids.isEmpty ? null : () => notifier.setSelected(ids, true),
            child: Text(l.loopListAll),
          ),
          TextButton(
            key: const ValueKey('loop-list-none'),
            onPressed: session.selected.isEmpty ? null : notifier.clearSelection,
            child: Text(l.loopListNone),
          ),
        ]),
        if (outside > 0)
          Text(
            key: const ValueKey('loop-list-outside'),
            l.loopListOutside(outside),
            style: theme.textTheme.bodySmall?.copyWith(color: palette.warningText),
          ),
        if (pool.inReach.isEmpty)
          Text(
            key: const ValueKey('loop-list-empty'),
            pool.warned.isEmpty ? l.loopListEmpty(radius.round()) : l.loopListOnlyWarned(radius.round()),
          ),
        for (final t in pool.inReach) _row(l, session, notifier, t),
        if (pool.warned.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(l.loopListWarned(pool.warned.length), style: theme.textTheme.titleMedium),
          Text(l.loopListWarnedHint,
              style: theme.textTheme.bodySmall?.copyWith(color: palette.warningText)),
          for (final t in pool.warned) _row(l, session, notifier, t),
        ],
        if (pool.connectors.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            key: const ValueKey('loop-connectors'),
            l.loopListConnectors(pool.connectors.length, pool.connectors.map((t) => t.displayName(l)).join(', ')),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
        ],
        if (pool.tooFar > 0) ...[
          const SizedBox(height: 4),
          Text(
            l.loopListTooFar(pool.tooFar),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
        ],
      ],
    );
  }

  Widget _row(AppLocalizations l, LoopSession session, LoopPlannerNotifier notifier, Trail t) {
    final on = session.selected.contains(t.id);
    final must = session.mandatory.contains(t.id);
    final parts = [
      formatMeters(t.lengthM),
      if (t.grade != null) 'S${t.grade}',
      if (t.rating != null) l.loopListStars(t.rating!),
    ];
    return CheckboxListTile(
      key: ValueKey('loop-trail-${t.id}'),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: on,
      onChanged: (v) => notifier.setSelected([t.id], v == true),
      title: Text(t.displayName(l), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(parts.join(' · ')),
      secondary: IconButton(
        key: ValueKey('loop-must-${t.id}'),
        tooltip: must ? l.loopMustOff : l.loopMust,
        icon: Icon(must ? Icons.star : Icons.star_border),
        onPressed: () => notifier.toggleMandatory(t.id),
      ),
    );
  }
}

// ─── Ergebnis ───────────────────────────────────────────────────────────

/// Rechnet und zeigt das Ergebnis am Scaffold der Karte. Zu heißt:
/// Ergebnis weg, der Modus bleibt. Ohne [compute] zeigt es, was schon
/// da ist („Rückgängig" nach dem Schließen, Konzept-Routing 10.5).
///
/// Mit [suggest] rechnet es den Vorschlag (#516 Schritt 4, „Runde
/// vorschlagen").
Future<void> showLoopResultPanel(ScaffoldState scaffold, {bool compute = true, bool suggest = false}) async {
  final container = ProviderScope.containerOf(scaffold.context, listen: false);
  final planner = container.read(loopPlannerProvider.notifier);
  if (compute) unawaited(suggest ? planner.suggest() : planner.compute());
  await showMapPanel(
    scaffold,
    initialSize: kMapPanelPool,
    builder: (context, scroll, panel) => _ResultPanel(scroll: scroll, panel: panel),
  );
  container.read(loopPlannerProvider.notifier).clearResult();
}

class _ResultPanel extends ConsumerStatefulWidget {
  const _ResultPanel({required this.scroll, required this.panel});

  final ScrollController scroll;
  final MapPanelController panel;

  @override
  ConsumerState<_ResultPanel> createState() => _ResultPanelState();
}

class _ResultPanelState extends ConsumerState<_ResultPanel> {
  LoopPlan? _fitted;
  final _buttonsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Steht schon ein Ergebnis, gleich einpassen.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFit(ref.read(loopPlannerProvider)));
  }

  /// Einmal je Ergebnis: einklappen, dann über dem Blatt einpassen.
  Future<void> _maybeFit(LoopSession s) async {
    final plan = s.plan;
    if (!mounted || plan == null || plan.outcome != LoopOutcome.ok || identical(plan, _fitted)) return;
    // Getunt (#234): Die Karte bleibt, wo der Finger den Punkt hingelegt hat.
    if (s.tuned) return;
    _fitted = plan;
    // Erst bauen lassen, dann messen, wie weit die Knöpfe reichen.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await widget.panel.resizeTo(_resultSize());
    if (!mounted) return;
    ref.read(mapFitRequestProvider.notifier).state = plan.points;
  }

  /// So weit eingeklappt, dass Summe, Profil und die Knöpfe ganz zu
  /// sehen sind — nie unter [kMapPanelResult], nie über
  /// [kMapPanelResultMax].
  double _resultSize() {
    final buttons = _buttonsKey.currentContext?.findRenderObject();
    final list = context.findRenderObject();
    final full = widget.panel.fullHeight;
    if (buttons is! RenderBox || list is! RenderBox || !buttons.attached || !list.attached || full == null) {
      return kMapPanelResult;
    }
    final needed = buttons.localToGlobal(Offset(0, buttons.size.height)).dy - list.localToGlobal(Offset.zero).dy + 12;
    return (needed / full).clamp(kMapPanelResult, kMapPanelResultMax);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(loopPlannerProvider, (_, next) => unawaited(_maybeFit(next)));
    final session = ref.watch(loopPlannerProvider);
    final plan = session.plan;
    final l = context.l10n;
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 24),
      children: [
        MapPanelHeader(
          title: switch (_namedTarget(session)) {
            final t? => l.routeNameTrailHead(t.displayName(l)),
            // Vor dem ersten Ergebnis zählt der Regler, danach das Gezeigte —
            // sonst hieß eine Route bis zum Ergebnis „Runde".
            null => (plan != null ? session.planEnd : session.prefs.endMode) == LoopEndMode.loop
                ? l.loopTitle
                : l.loopRouteTitle,
          },
          // Kein Untertitel: Die Summe steht direkt darunter, auch
          // eingeklappt — zweimal dieselben Zahlen nahmen dem Profil den
          // Platz.
          closeKey: const ValueKey('loop-close'),
          onClose: widget.panel.close,
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Eine Route (#356): Der Stil steht über allem und bleibt
              // stehen, während neu gerechnet wird — ein Wechsel rechnet
              // sofort (D3). Seit PR 7b auch mit Auswahl.
              if (session.prefs.endMode == LoopEndMode.target) ...[
                _styleSelector(context, session),
                const SizedBox(height: 12),
              ],
              ...switch (session.phase) {
              LoopPhase.locating => [_progress(l.routingLocating)],
              LoopPhase.loading => [_progressBar(context, l.routingLoadingWays, null, cancel: true)],
              LoopPhase.building => [_progressBar(context, l.loopBuildingGraph, session.progress, cancel: true)],
              LoopPhase.idle when session.changed => [_changedCard(context)],
              LoopPhase.computing || LoopPhase.idle => [
                  _progressBar(
                    context,
                    session.prefs.endMode == LoopEndMode.target ? l.routeComputing : l.loopComputing,
                    session.progress,
                    cancel: session.phase == LoopPhase.computing,
                  ),
                ],
              // Geht es nicht, bleibt zu einem Ziel die Navi-App (#151).
              LoopPhase.result => session.blocker != null || plan == null
                  ? [_blockerCard(context, session, session.blocker ?? LoopBlocker.failed), ?_external(context, session)]
                  : _result(context, session, plan),
            },
            ],
          ),
        ),
      ],
    );
  }

  Widget _styleSelector(BuildContext context, LoopSession session) {
    final l = context.l10n;
    return SegmentedButton<RouteMode>(
      key: const ValueKey('loop-route-mode'),
      segments: [
        ButtonSegment(value: RouteMode.direct, label: Text(l.routeModeDirect), icon: const Icon(Icons.straight)),
        ButtonSegment(value: RouteMode.fun, label: Text(l.routeModeFun), icon: const Icon(Icons.downhill_skiing)),
        ButtonSegment(value: RouteMode.easy, label: Text(l.routeModeEasy), icon: const Icon(Icons.directions_bike)),
      ],
      selected: {session.prefs.style},
      showSelectedIcon: false,
      onSelectionChanged: (sel) => unawaited(ref.read(loopPlannerProvider.notifier).setStyle(sel.single)),
    );
  }

  Widget _progress(String text) => Row(children: [
        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ]);

  /// Der Ladebalken (#356): Bau und Rechnung melden ihren Anteil aus dem
  /// Rechen-Isolate; ohne Meldung läuft er unbestimmt. Mit [cancel] steht
  /// „Abbrechen" daneben (#372) — X und Zurück schlössen den Planer.
  Widget _progressBar(BuildContext context, String text, double? value, {bool cancel = false}) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('loop-progress'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
          if (value != null) ...[
            const SizedBox(width: 12),
            Text(context.l10n.loopProgressPercent((value * 100).round()),
                style: AppFonts.numbers(theme.textTheme.bodyMedium)),
          ],
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: value, minHeight: 6),
            ),
          ),
          if (cancel) ...[
            const SizedBox(width: 8),
            TextButton(
              key: const ValueKey('loop-cancel'),
              onPressed: ref.read(loopPlannerProvider.notifier).cancel,
              child: Text(context.l10n.commonCancel),
            ),
          ],
        ]),
      ],
    );
  }

  Widget _notice(BuildContext context, String text) =>
      Text(key: const ValueKey('loop-notice'), text, style: Theme.of(context).textTheme.bodyMedium);

  Widget _blockerCard(BuildContext context, LoopSession session, LoopBlocker b) {
    final palette = AppPalette.of(context);
    return Card(
      key: const ValueKey('loop-blocker'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, color: palette.warningText),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _notice(context, _blockerText(context.l10n, session, b)),
              if (b == LoopBlocker.noTrailsInReach)
                if (ref.read(loopPlannerProvider.notifier).widerReachM case final wider?) _widerButton(context, wider),
            ]),
          ),
        ]),
      ),
    );
  }

  /// „Weiter suchen" (Konzept-Routing 12.5): derselbe Vorschlag aus dem
  /// nächsten Umkreis [wider].
  Widget _widerButton(BuildContext context, double wider) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('loop-wider'),
          onPressed: () => unawaited(ref.read(loopPlannerProvider.notifier).suggestWider()),
          icon: const Icon(Icons.zoom_out_map),
          label: Text(context.l10n.loopSuggestWider(loopReachLabel(wider))),
        ),
      );

  /// Eine Eingabe hat sich geändert (#356, D3): Die Linie ist weg, und
  /// gerechnet wird erst auf Wunsch — wer mehrere Trails dazunimmt, will
  /// nicht nach jedem Tipp warten.
  Widget _changedCard(BuildContext context) {
    final l = context.l10n;
    return Card(
      key: const ValueKey('loop-changed'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(l.loopChangedTitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(l.loopChangedText, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const ValueKey('loop-recompute'),
              onPressed: () => unawaited(ref.read(loopPlannerProvider.notifier).compute()),
              icon: const Icon(Icons.refresh),
              label: Text(l.loopRecompute),
            ),
          ),
        ]),
      ),
    );
  }

  bool _fitsBudget(LoopSummary s, LoopBudget b) =>
      s.timeS <= b.maxTimeS + 1 && s.gainM <= b.climbM + 1 && s.hikingM <= b.hikingM + 1;

  List<Widget> _result(BuildContext context, LoopSession session, LoopPlan plan) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final l = context.l10n;
    if (plan.outcome != LoopOutcome.ok) {
      return [
        _notice(context, _outcomeText(l, plan.outcome)),
        if (plan.excluded.isNotEmpty) ...[const SizedBox(height: 8), ..._excludedRows(context, plan)],
        ?_external(context, session),
      ];
    }
    final s = plan.summary!;
    final trails = ref.read(trailsProvider).valueOrNull ?? const <Trail>[];
    final byId = {for (final t in trails) t.id: t};
    final canRecord = ref.watch(rideRecordingAvailableProvider) && ref.watch(rideProvider) == null;
    // Das Budget, an dem eine Runde gerechnet wurde (Runde oder Ende am
    // letzten Trail); eine Route zu einem Ziel rechnet ohne Zeit als
    // Richtwert, die Skalen sagten dort nichts.
    final budget = !plan.isEmpty && !session.planBare && session.planEnd != LoopEndMode.target
        ? session.planBudget
        : null;
    final reach = session.suggestReachM;
    final wider = ref.read(loopPlannerProvider.notifier).widerReachM;
    return [
      // Der Planer hat selbst gewählt (#516 Schritt 4, Konzept-Routing
      // 12.4): Das Blatt sagt, dass es ein Vorschlag ist.
      if (reach != null) ...[
        Text(
          key: const ValueKey('loop-suggest'),
          l.loopSuggestLine({for (final st in plan.stops) st.trail.id}.length, loopReachLabel(reach)),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
      ],
      // Vier Kacheln statt eines Satzes (#517, Konzept-Geräte 5.2): Länge,
      // bergauf, auf Trails (ohne Trail — die Route von A nach B, #356 —
      // bergab), Zeit. Eine Runde trägt unter „Bergauf" und „Zeit" ihre
      // Skala (Konzept-Routing 12.5a): wie viel vom Limit, wo im Fenster.
      Row(
        key: const ValueKey('loop-summary'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, tile) in [
            _SummaryTile(key: const ValueKey('loop-tile-length'), label: l.loopTileLength, value: formatMeters(s.lengthM)),
            _SummaryTile(
              key: const ValueKey('loop-tile-climb'),
              label: l.loopTileClimb,
              value: '${s.gainM.round()} hm',
              trailing: budget == null ? null : l.loopTileOf('${budget.climbM.round()}'),
              scale: budget == null
                  ? null
                  : LoopBudgetScale(key: const ValueKey('loop-scale-climb'), value: s.gainM, mark: budget.climbM),
            ),
            plan.isEmpty
                ? _SummaryTile(
                    key: const ValueKey('loop-tile-descent'), label: l.loopTileDescent, value: '${s.lossM.round()} hm')
                : _SummaryTile(key: const ValueKey('loop-tile-trail'), label: l.loopTileTrail, value: formatMeters(s.trailM)),
            _SummaryTile(
              key: const ValueKey('loop-tile-time'),
              label: l.loopTileTime,
              value: budget == null ? routeTimeLabel(l, s.timeS) : l.loopTimeAbout(routeTimeLabel(l, s.timeS)),
              scale: budget == null
                  ? null
                  : LoopBudgetScale(
                      key: const ValueKey('loop-scale-time'),
                      value: s.timeS,
                      mark: budget.timeS,
                      windowFrom: budget.minTimeS,
                      windowTo: budget.maxTimeS),
            ),
          ].indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(child: tile),
          ],
        ],
      ),
      const SizedBox(height: 4),
      // Das Profil der Runde (#234) gleich unter der Summe, dann der Start —
      // eingeklappt ist das immer dasselbe Bild. Die Anmerkungen stehen
      // darunter (Feldbefund 2026-10-29: sie schoben das Profil aus dem
      // eingeklappten Blatt).
      RouteElevationProfile(plan.points, key: const ValueKey('loop-elevation')),
      const SizedBox(height: 8),
      // Ergebnis und Start in einem (#517): die gemerkten Schalter als
      // Chips, EIN Knopf — kein zweites Blatt mehr.
      NavStartOptions(
        canRecord: canRecord,
        onWatchFound: () => ref.read(watchSyncProvider.notifier).prepare(plan.points),
      ),
      const SizedBox(height: 8),
      KeyedSubtree(
        key: _buttonsKey,
        child: NavStartButton(
          buttonKey: 'loop-navigate',
          onPressed: () => ref.read(navRequestProvider.notifier).state = NavRequest(
              points: plan.points,
              title: _name(l, session, plan),
              sections: navSectionsOfLoop(context.l10n, plan,
                  trailById: trailByIdOf(ref), beyond: _targetTrail(session)),
              fromPlanner: true,
              profile: session.profile,
              routePrefs: session.prefs.planRoute,
              start: navStartChoiceOf(ref, canRecord: canRecord)),
        ),
      ),
      // Speichern und GPX darunter, beim Vorschlag zuerst „Bearbeiten":
      // in die Bearbeitung, mit den Trails des Vorschlags gewählt.
      Wrap(children: [
        if (reach != null)
          TextButton.icon(
            key: const ValueKey('loop-edit'),
            onPressed: widget.panel.close,
            icon: const Icon(Icons.edit_outlined),
            label: Text(l.loopSuggestEdit),
          ),
        TextButton.icon(
          key: const ValueKey('loop-save'),
          onPressed: () => _saveRide(session, plan),
          icon: const Icon(Icons.bookmark_add_outlined),
          label: Text(l.commonSave),
        ),
        TextButton.icon(
          key: const ValueKey('loop-gpx'),
          onPressed: () => _exportGpx(session, plan),
          icon: const Icon(Icons.share_outlined),
          label: Text(l.routingAsGpx),
        ),
        ?_external(context, session),
      ]),
      const SizedBox(height: 4),
      Text(
        key: const ValueKey('loop-details'),
        [
          if (!plan.isEmpty) l.loopDescents(s.trailLossM.round(), s.wastedLossM.round()),
          if (s.mix.isNotEmpty) wayMixLine(l, s.mix),
          // Die Schätzung kennt keine Pausen (Konzept-Routing 12.5) — als
          // Satz, seit die Reserve nicht mehr still in der Rechnung steckt.
          if (budget != null) l.loopNoBreaks,
        ].join(' · '),
        style: theme.textTheme.bodyMedium,
      ),
      // Unter dem Fenster (Konzept-Routing 12.5): bewusst, weil der
      // Trail-Anteil deutlich besser war (Betreiber, 2026-11-14) — oder
      // weil nichts mehr passte; dann beim Vorschlag „Weiter suchen" im
      // nächsten Umkreis. Beim Bearbeiten ist der Pool die Auswahl.
      if (budget != null && !session.tuned && s.timeS < budget.minTimeS) ...[
        const SizedBox(height: 4),
        Text(
          key: ValueKey(plan.shortForShare ? 'loop-short-share' : 'loop-short'),
          plan.shortForShare
              ? l.loopShortShareNote(loopHoursLabel(l, session.prefs.hours))
              : l.loopShortNote(loopHoursLabel(l, session.prefs.hours)),
          style: theme.textTheme.bodyMedium,
        ),
        if (!plan.shortForShare && wider != null) _widerButton(context, wider),
      ],
      if (session.planBare && session.prefs.style == RouteMode.easy) ...[
        const SizedBox(height: 4),
        Text(key: const ValueKey('loop-easy-note'), l.routeEasyNote, style: theme.textTheme.bodyMedium),
      ] else if (!session.planBare && session.prefs.planRoute.easy) ...[
        // Mit Auswahl rechnen nur die Verbindungen bequem (#356 PR 7b).
        const SizedBox(height: 4),
        Text(key: const ValueKey('loop-easy-note'), l.loopEasyUpNote, style: theme.textTheme.bodyMedium),
      ],
      if (!session.planBare &&
          session.planEnd == LoopEndMode.target &&
          session.prefs.style == RouteMode.direct &&
          !session.selected.every(session.mandatory.contains)) ...[
        const SizedBox(height: 4),
        Text(key: const ValueKey('loop-direct-note'), l.routeDirectStarredNote, style: theme.textTheme.bodyMedium),
      ],
      if (session.funEmpty) ...[
        const SizedBox(height: 4),
        Text(key: const ValueKey('loop-fun-empty'), l.routeFunEmpty, style: theme.textTheme.bodyMedium),
      ],
      if (closedStopNames(
        plan,
        {for (final t in trails) if (t.status.blocksRouting) t.id},
        ref.read(officialTrailsEnabledProvider) ? ref.read(officialTrailsControllerProvider).trails : const [],
      )
          case final closed when closed.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          key: const ValueKey('loop-closed'),
          l.loopClosedStops(closed.join(', ')),
          style: theme.textTheme.bodyMedium?.copyWith(color: palette.warningText),
        ),
      ],
      for (final snap in plan.snaps) ...[
        const SizedBox(height: 4),
        Text(
          key: ValueKey('loop-snap-${snap.role.name}-${snap.index}'),
          _snapText(l, plan, snap),
          style: theme.textTheme.bodyMedium,
        ),
      ],
      RouteTuneNote(
        tuned: session.tuned,
        onReset: () => unawaited(ref.read(loopPlannerProvider.notifier).resetTuning()),
        keyPrefix: 'loop',
      ),
      if (session.tuned && !_fitsBudget(s, session.planBudget))
        Text(
          key: const ValueKey('loop-tuned-over'),
          l.loopTunedOver,
          style: theme.textTheme.bodySmall?.copyWith(color: palette.warningText),
        ),
      if (s.trailUpM > 0) ...[
        const SizedBox(height: 4),
        Text(
          key: const ValueKey('loop-trail-up'),
          l.routingTrailUp(formatMeters(s.trailUpM), s.trailUpNames.join(', ')),
          style: theme.textTheme.bodyMedium,
        ),
      ],
      if (s.hikingM > 0) ...[
        const SizedBox(height: 8),
        Text(
          l.routingHikingWarning(formatMeters(s.hikingM)),
          style: theme.textTheme.bodyMedium?.copyWith(color: palette.warningText),
        ),
      ],
      if (session.coverage == null ? null : planningCoverageNote(l, session.coverage!, loop: true)
          case final note?) ...[
        const SizedBox(height: 8),
        Text(
          key: const ValueKey('loop-partial'),
          note,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      ],
      if (steepNote(l, s.steepM) case final note?) ...[
        const SizedBox(height: 8),
        Text(
          key: const ValueKey('loop-steep'),
          note,
          style: theme.textTheme.bodySmall?.copyWith(color: palette.warningText),
        ),
      ],
      if (!s.heightsComplete) ...[
        const SizedBox(height: 8),
        Text(
          l.routingHeightsIncomplete,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      ],
      // Das Rad rechnet sofort (D3) — wie im Blatt „Route".
      const SizedBox(height: 12),
      SegmentedButton<RiderProfile>(
        key: const ValueKey('loop-result-profile'),
        segments: [for (final p in RiderProfile.values) ButtonSegment(value: p, label: Text(p.label(l)))],
        selected: {session.profile},
        showSelectedIcon: false,
        onSelectionChanged: (sel) => unawaited(ref.read(loopPlannerProvider.notifier).switchProfile(sel.single)),
      ),
      if (plan.stops.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(l.loopOrder, style: theme.textTheme.titleMedium),
      ],
      for (var i = 0; i < plan.stops.length; i++)
        ListTile(
          key: ValueKey('loop-stop-$i'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(radius: 12, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
          title: Text(plan.stops[i].trail.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text([
            formatMeters(plan.stops[i].trail.lengthM),
            if (byId[plan.stops[i].trail.id]?.grade case final g?) 'S$g',
            if (plan.stops[i].secondPass) l.loopSecondPass,
          ].join(' · ')),
        ),
      // Was der spaßige Umweg nicht mitnahm, hat niemand gewählt.
      if (plan.excluded.isNotEmpty && !session.planBare) ...[
        const SizedBox(height: 8),
        Text(l.loopExcludedTitle, style: theme.textTheme.titleMedium),
        ..._excludedRows(context, plan),
      ],
      const SizedBox(height: 8),
      Text(
        l.routingNoTurnHints,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
      ),
    ];
  }

  List<Widget> _excludedRows(BuildContext context, LoopPlan plan) {
    final theme = Theme.of(context);
    final trails = ref.read(trailsProvider).valueOrNull ?? const <Trail>[];
    final byId = {for (final t in trails) t.id: t};
    return [
      for (final e in plan.excluded.entries)
        Text(
          key: ValueKey('loop-excluded-${e.key}'),
          context.l10n.loopExcludedRow(byId[e.key]?.displayName(context.l10n) ?? e.key, _exclusionText(context.l10n, e.value)),
          style: theme.textTheme.bodySmall,
        ),
    ];
  }

  /// Zu einem Ziel auch die Navi-App (#151) — wie bisher im Blatt „Route",
  /// auch wenn hier nichts zu rechnen ging; eine Runde hat kein Ziel, das
  /// sie bräuchte.
  Widget? _external(BuildContext context, LoopSession session) {
    final target = session.target;
    if (session.prefs.endMode != LoopEndMode.target || target == null) return null;
    final trail = session.targetTrailId == null ? null : trailByIdOf(ref)(session.targetTrailId!);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const ValueKey('loop-external'),
        onPressed: () => trail != null ? navigateToTrailHead(context, trail) : navigateToPoint(context, target),
        icon: const Icon(Icons.directions_outlined),
        label: Text(context.l10n.sheetNavigate),
      ),
    );
  }

  /// Der Trail, zu dessen Kopf die gezeigte Route führt („Zum Trailkopf").
  Trail? _targetTrail(LoopSession session) {
    final id = session.targetTrailId;
    if (id == null || session.planEnd != LoopEndMode.target) return null;
    return trailByIdOf(ref)(id);
  }

  /// Nach dem Trailkopf HEISST die Route nur ohne gewählte Trails — mit
  /// Auswahl sagen deren Namen mehr („Route: Hexentanz, Steinbruch").
  Trail? _namedTarget(LoopSession session) => session.planBare ? _targetTrail(session) : null;

  /// Der Name für Fahrt, GPX und Navigation: zum Trailkopf nach dem Trail,
  /// sonst nach den Trails der Planung.
  String _name(AppLocalizations l, LoopSession session, LoopPlan plan) => switch (_namedTarget(session)) {
        final t? => l.routeNameTrailHead(t.displayName(l)),
        null => loopName(l, plan, loop: session.planEnd == LoopEndMode.loop),
      };

  Future<void> _saveRide(LoopSession session, LoopPlan plan) async {
    if (plan.summary == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final now = DateTime.now().toUtc();
    final ride = await ref.read(ridesProvider.notifier).savePlanned(
          name: _name(l, session, plan),
          points: [
            for (final p in plan.points) RidePoint(lat: p.latitude, lng: p.longitude, at: now, accuracyM: 0),
          ],
          duration: Duration(seconds: routeSeconds(plan.summary!.timeS)),
          profile: session.profile.name,
        );
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
        content: Text(ride == null ? l.loopSaveFailed : l.routingSavedAsRide)));
  }

  void _exportGpx(LoopSession session, LoopPlan plan) {
    if (plan.summary == null) return;
    final track = GpxTrack(
        name: _name(context.l10n, session, plan),
        points: [for (final p in plan.points) TrackPoint(p.latitude, p.longitude)]);
    shareGpx(context, ref, fileName: gpxFileName(track.name), xml: writeGpx(name: track.name, points: track.points));
  }

  /// Eine Route ohne gewählten Trail (#356) hat ihre eigenen Sätze — sie
  /// nennen den Trailkopf oder das Ziel und die Navi-App, nicht „die Runde"
  /// und „weniger Trails".
  String _blockerText(AppLocalizations l, LoopSession session, LoopBlocker b) {
    final route = session.prefs.endMode == LoopEndMode.target && session.selected.isEmpty;
    return switch (b) {
      LoopBlocker.noTrails => l.loopBlockerNoTrails,
      LoopBlocker.noTrailsInReach => l.loopBlockerNoTrailsInReach(loopReachLabel(session.suggestReachM ?? kLoopReachM)),
      LoopBlocker.noPosition => route ? l.routeBlockerNoPosition : l.loopBlockerNoPosition,
      LoopBlocker.noTarget => l.loopBlockerNoTarget,
      LoopBlocker.noArea => !route
          ? l.loopBlockerNoArea
          : session.targetTrailId != null
              ? l.routeBlockerNoAreaTrailHead
              : l.routeBlockerNoAreaPoint,
      LoopBlocker.failed => route ? l.routeBlockerFailed : l.loopBlockerFailed,
      LoopBlocker.tooLarge => route
          ? l.routeBlockerTooLarge(session.coverage?.tilesNeeded ?? 0, kPlanMaxTiles)
          : l.loopBlockerTooLarge(session.coverage?.tilesNeeded ?? 0, kPlanMaxTiles),
    };
  }

  String _outcomeText(AppLocalizations l, LoopOutcome o) => switch (o) {
        LoopOutcome.ok => '',
        LoopOutcome.startOffNetwork => l.loopOutcomeStartOff(kGraphSnapM.round()),
        LoopOutcome.endOffNetwork => l.loopOutcomeEndOff(kGraphSnapM.round()),
        // Wird nie gezeigt: Ein getuntes Ergebnis, das nicht geht, ersetzt
        // das gezeigte nicht (#234).
        LoopOutcome.viaFailed => l.loopOutcomeViaFailed,
        LoopOutcome.empty => l.loopOutcomeEmpty,
      };

  String _snapText(AppLocalizations l, LoopPlan plan, PointSnap s) {
    final d = formatMeters(s.meters);
    String name() => plan.stops.firstWhere((t) => t.trail.id == s.trailId).trail.name;
    return switch (s.role) {
      SnapRole.start => l.loopSnapStart(d),
      SnapRole.end => l.loopSnapEnd(d),
      SnapRole.waypoint => l.loopSnapWaypoint(d),
      SnapRole.trailStart => l.loopSnapTrailStart(name(), d),
      SnapRole.trailEnd => l.loopSnapTrailEnd(name(), d),
    };
  }

    String _exclusionText(AppLocalizations l, LoopExclusion e) => switch (e) {
        LoopExclusion.tooFar => l.loopExclTooFar,
        LoopExclusion.offNetwork => l.loopExclOffNetwork(formatMeters(kGraphSnapM)),
        LoopExclusion.unreachable => l.loopExclUnreachable,
        LoopExclusion.budget => l.loopExclBudget,
      };
}

/// „3 h" oder „2 h 30" — die Zeit des Budgets, im Kopf und in „Anpassen".
String loopHoursLabel(AppLocalizations l, double h) {
  final whole = h.floor();
  final half = h - whole >= 0.5;
  return half ? l.routingTimeHoursMinutes(whole, 30) : l.routingTimeHours(whole);
}

/// „Forstweg 2,1 km · Nebenstraße 300 m" — die Klassen nach Länge; EINE
/// Fassung für Runde und Weg.
String wayMixLine(AppLocalizations l, Map<WayClass, double> mix) {
  final entries = mix.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return entries.map((e) => l.routingWayMix(e.key.label(l), formatMeters(e.value))).join(' · ');
}

/// Die gewählten Trails leuchten, solange der Planer offen ist und keine
/// Runde auf der Karte liegt (#178); ein Pflicht-Trail kräftiger.
List<MapViewPolyline> loopSelectionLines(Iterable<Trail> trails, LoopSession s) => [
      for (final t in trails)
        if (s.selected.contains(t.id) && t.points.length >= 2)
          MapViewPolyline(
            points: t.directedPoints,
            color: AppColors.brand,
            width: kLoopPickWidth,
            borderColor: AppColors.onBrand.withValues(alpha: s.mandatory.contains(t.id) ? 1 : 0.7),
            borderWidth: s.mandatory.contains(t.id) ? kLoopPickBorderMandatory : kLoopPickBorder,
          ),
    ];

/// Die Vorschau: das Band der Route (#295) unter dem Netz — die
/// Trail-Linien behalten ihre Farbe, das Band an ihren Seiten sagt
/// „dabei". Wanderweg-Verbindungen gestrichelt in der Mitte; ein Tipp auf
/// eine Verbindung setzt einen Zwischenpunkt (#234).
List<MapViewPolyline> loopPreviewLines(LoopPlan plan) {
  if (plan.outcome != LoopOutcome.ok) return const [];
  final legs = legLinesOf([
    for (final s in plan.sections)
      if (s.leg != null) (s.leg!, s.points),
  ]);
  return routeBandLines(plan.points, opacity: kRoutePreviewOpacity, pieces: [
    for (final s in plan.sections)
      if (!s.isTrail)
        (points: s.points, hiking: s.hiking, hitValue: s.leg == null ? null : RouteLegHit(s.leg!, legs[s.leg]!)),
  ]);
}

/// Eine Kachel der Summe (#517): Beschriftung klein, Zahl in Mono; bei
/// einer Runde rechts neben der Beschriftung das Limit ([trailing]) und
/// unter der Zahl die Skala ([scale], Konzept-Routing 12.5a).
class _SummaryTile extends StatelessWidget {
  const _SummaryTile({super.key, required this.label, required this.value, this.trailing, this.scale});

  final String label;
  final String value;
  final String? trailing;
  final Widget? scale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.labelSmall?.copyWith(color: theme.hintColor);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 8, 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: small)),
            if (trailing case final t?) ...[
              const SizedBox(width: 4),
              Expanded(
                child: Text(t,
                    maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: AppFonts.numbers(small)),
              ),
            ],
          ]),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, maxLines: 1, style: AppFonts.numbers(theme.textTheme.titleMedium)),
          ),
          if (scale case final w?) ...[const SizedBox(height: 3), w],
        ],
      ),
    );
  }
}

/// Die Skala unter einer Kachel (Konzept-Routing 12.5a): gefüllt bis
/// [value], ein Strich bei [mark] (das Limit, die gewählte Zeit) und — bei
/// der Zeit — das Fenster [windowFrom]…[windowTo] als helleres Feld. Läuft
/// der Wert über das Ende des Erlaubten (das Limit, oder das Fenster), ist
/// die Füllung in der Warnfarbe: Form (der Strich mitten in der Füllung)
/// UND Farbe, A13.
class LoopBudgetScale extends StatelessWidget {
  const LoopBudgetScale({super.key, required this.value, required this.mark, this.windowFrom, this.windowTo});

  final double value;
  final double mark;
  final double? windowFrom;
  final double? windowTo;

  /// Das Ende des Erlaubten: das Fenster, sonst das Limit.
  double get limit => windowTo ?? mark;

  /// Über dem Erlaubten — getunt oder mit Pflicht-Trails.
  bool get over => value > limit + 1;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return SizedBox(
      height: 6,
      width: double.infinity,
      child: CustomPaint(
        painter: _ScalePainter(
          value: value,
          mark: mark,
          windowFrom: windowFrom,
          windowTo: windowTo,
          track: p.line,
          fill: over ? p.warningText : p.brandMark,
          tick: p.text,
        ),
      ),
    );
  }
}

class _ScalePainter extends CustomPainter {
  _ScalePainter({
    required this.value,
    required this.mark,
    required this.windowFrom,
    required this.windowTo,
    required this.track,
    required this.fill,
    required this.tick,
  });

  final double value, mark;
  final double? windowFrom, windowTo;
  final Color track, fill, tick;

  @override
  void paint(Canvas canvas, Size size) {
    final end = math.max(math.max(mark, windowTo ?? 0), value);
    if (end <= 0) return;
    double x(double v) => (v / end).clamp(0.0, 1.0) * size.width;
    const barH = 4.0;
    final top = (size.height - barH) / 2;
    final r = const Radius.circular(barH / 2);
    canvas.drawRRect(RRect.fromLTRBR(0, top, size.width, top + barH, r), Paint()..color = track);
    if (windowFrom != null && windowTo != null) {
      canvas.drawRect(Rect.fromLTRB(x(math.max(0, windowFrom!)), top, x(windowTo!), top + barH),
          Paint()..color = fill.withValues(alpha: 0.3));
    }
    canvas.drawRRect(RRect.fromLTRBR(0, top, x(value), top + barH, r), Paint()..color = fill);
    final m = x(mark);
    canvas.drawRect(Rect.fromLTRB(m - 1, 0, m + 1, size.height), Paint()..color = tick);
  }

  @override
  bool shouldRepaint(_ScalePainter old) =>
      old.value != value ||
      old.mark != mark ||
      old.windowFrom != windowFrom ||
      old.windowTo != windowTo ||
      old.fill != fill ||
      old.track != track ||
      old.tick != tick;
}

/// Ein Umkreis des Vorschlags (#516 Schritt 4): ganze Kilometer ohne
/// „,0" („10 km", „6,5 km").
String loopReachLabel(double m) => formatMeters(m).replaceAll(',0 km', ' km');
