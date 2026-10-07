// Die Blätter des Planers (#158 Schritt 5, seit 0.74.0 als Modus mit
// Leiste, `loop_tool_rail.dart`; Zustand in `loop_planner_controller.dart`):
//
// - **Parameter** (Knopf „Parameter" der Leiste): Start, Profil, die drei
//   Regler aus Konzept-Routing 2.3, „Start ist auch Ziel" und der Radius
//   der Trail-Liste. Die Regler merkt sich das Gerät.
// - **Liste** (Knopf „Liste"): die wählbaren Trails im Radius um den Start,
//   mit Haken, Stern („muss dabei sein"), „Alle" und „Keine". Gemeldete
//   stehen abseits; Uphill-Trails und Verbinder sind nicht wählbar — die
//   Runde nutzt sie von selbst bergauf (#185).
// - **Ergebnis** (Knopf „Rechnen"): kein Modal (`map_panel.dart`), die
//   Karte bleibt bedienbar; Fortschritt, der Grund, wenn es nicht geht,
//   oder Summen, Reihenfolge, Ausgelassene, „Als Fahrt speichern", „Als
//   GPX". Beim Ergebnis klappt es ein und die Karte passt die Runde
//   DARÜBER ein. Zu heißt: Ergebnis weg, Modus und Auswahl bleiben.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart' show AppFonts;
import '../../core/geo.dart' show formatMeters;
import '../../core/gpx_share.dart';
import '../../models/trail.dart';
import '../map/map_view/map_view.dart';
import '../rides/ride_providers.dart';
import '../rides/ride_track.dart';
import '../trails/gpx_writer.dart';
import '../trails/trail_providers.dart';
import 'loop_planner.dart';
import 'loop_planner_controller.dart';
import 'loop_planner_providers.dart';
import 'map_panel.dart';
import 'road_graph.dart';
import 'road_graph_loader.dart' show kOnlineFillMaxTiles;
import 'route_elevation.dart';
import 'route_profile.dart';
import 'route_search.dart' show steepNote;
import 'trail_head_route.dart' show routeTimeLabel;

/// Breite der leuchtenden Auswahl auf der Karte (#178) — breiter als eine
/// Verbindung, schmaler als der Leuchtrand des ausgewählten Trails (16).
/// Deckendes Lime mit dunkler Kontur wie dort (#233, wie #195): 55 %
/// Lime ohne Kontur ging im weißen Saum der Trails unter — gewählt war,
/// zu sehen war nichts.
const kLoopPickWidth = 12.0;

/// Kontur der Auswahl; Pflicht-Trails tragen sie stärker und deckend.
const kLoopPickBorder = 2.0;
const kLoopPickBorderMandatory = 3.5;

/// Die Fahne des getippten Starts (#233): Lime auf hellem Grund braucht
/// einen dunklen Rand — acht scharfe Schatten ringsum als Kontur, ein
/// weicher als Schein.
class LoopStartFlag extends StatelessWidget {
  const LoopStartFlag({super.key, this.size = 32});

  final double size;

  static const _contour = AppColors.onBrand;

  @override
  Widget build(BuildContext context) => Icon(
        Icons.flag,
        size: size,
        color: AppColors.brand,
        shadows: [
          for (final (dx, dy) in const [(-1.0, -1.0), (0.0, -1.5), (1.0, -1.0), (1.5, 0.0), (1.0, 1.0), (0.0, 1.5), (-1.0, 1.0), (-1.5, 0.0)])
            Shadow(color: _contour, offset: Offset(dx, dy)),
          Shadow(color: _contour.withValues(alpha: 0.6), blurRadius: 6),
        ],
      );
}

// ─── Parameter ──────────────────────────────────────────────────────────

Future<void> showLoopParamsSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
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
    final start = session.start;
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text('Parameter der Runde', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(
          start == null
              ? 'Start: mein Standort'
              : 'Start: getippter Punkt (${start.latitude.toStringAsFixed(4)}, ${start.longitude.toStringAsFixed(4)})',
          key: const ValueKey('loop-start'),
          style: theme.textTheme.bodyMedium,
        ),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          TextButton.icon(
            key: const ValueKey('loop-pick'),
            onPressed: () {
              notifier.armStartPick();
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.touch_app_outlined),
            label: const Text('Auf der Karte tippen'),
          ),
          if (start != null)
            TextButton(
              key: const ValueKey('loop-start-me'),
              onPressed: notifier.useMyPosition,
              child: const Text('Mein Standort'),
            ),
        ]),
        const SizedBox(height: 8),
        SegmentedButton<RiderProfile>(
          key: const ValueKey('loop-profile'),
          segments: [for (final p in RiderProfile.values) ButtonSegment(value: p, label: Text(p.label))],
          selected: {session.profile},
          showSelectedIcon: false,
          onSelectionChanged: (sel) => notifier.setProfile(sel.single),
        ),
        const SizedBox(height: 12),
        _LoopSlider(
          key: const ValueKey('loop-time'),
          label: 'Höchstens ${_hoursLabel(prefs.hours)}',
          value: prefs.hours,
          min: LoopPrefs.minHours,
          max: LoopPrefs.maxHours,
          step: LoopPrefs.hoursStep,
          onChanged: (v) => notifier.setPrefs(prefs.copyWith(hours: v)),
        ),
        _LoopSlider(
          key: const ValueKey('loop-climb'),
          label: 'Höchstens ${prefs.climbM.round()} hm bergauf',
          value: prefs.climbM,
          min: LoopPrefs.minClimb,
          max: LoopPrefs.maxClimb,
          step: LoopPrefs.climbStep,
          onChanged: (v) => notifier.setPrefs(prefs.copyWith(climbM: v)),
        ),
        _LoopSlider(
          key: const ValueKey('loop-hiking'),
          label: prefs.hikingKm == 0 ? 'Kein Wanderweg' : 'Höchstens ${formatMeters(prefs.hikingKm * 1000)} Wanderweg',
          value: prefs.hikingKm,
          min: LoopPrefs.minHikingKm,
          max: LoopPrefs.maxHikingKm,
          step: LoopPrefs.hikingStep,
          onChanged: (v) => notifier.setPrefs(prefs.copyWith(hikingKm: v)),
        ),
        _LoopSlider(
          key: const ValueKey('loop-radius'),
          label: 'Trail-Liste: ${prefs.radiusKm.round()} km um den Start',
          value: prefs.radiusKm,
          min: LoopPrefs.minRadiusKm,
          max: LoopPrefs.maxRadiusKm,
          step: LoopPrefs.radiusStep,
          onChanged: (v) => notifier.setPrefs(prefs.copyWith(radiusKm: v)),
        ),
        SwitchListTile(
          key: const ValueKey('loop-return'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Start ist auch Ziel'),
          subtitle: Text(prefs.returnToStart ? 'Eine Runde' : 'Die Runde endet am letzten Trail'),
          value: prefs.returnToStart,
          onChanged: (v) => notifier.setPrefs(prefs.copyWith(returnToStart: v)),
        ),
        const SizedBox(height: 4),
        Text('Unterwegs', style: theme.textTheme.titleSmall),
        _PrefSwitch(
          tileKey: const ValueKey('loop-pref-roads'),
          title: 'Straßen meiden',
          on: 'Forstweg, Feldweg und Radweg vor Straße — je größer die Straße, desto stärker.',
          off: 'Straßen sind fast so gut wie Forstwege; nur große Straßen kosten noch etwas.',
          value: prefs.route.avoidRoads,
          onChanged: (v) => notifier.setPrefs(prefs.copyWith(route: prefs.route.copyWith(avoidRoads: v))),
        ),
        _PrefSwitch(
          tileKey: const ValueKey('loop-pref-hiking'),
          title: 'Wanderwege bergauf meiden',
          on: 'Bergauf lieber Forstweg als Pfad. Die Grenze oben gilt immer.',
          off: 'Ein Pfad bergauf ist kaum teurer als ein Forstweg. Die Grenze oben gilt immer.',
          value: prefs.route.avoidHiking,
          onChanged: (v) => notifier.setPrefs(prefs.copyWith(route: prefs.route.copyWith(avoidHiking: v))),
        ),
        _PrefSwitch(
          tileKey: const ValueKey('loop-pref-steep'),
          title: 'Steile Rampen meiden',
          on: 'Ab 10 % Steigung wird jeder Höhenmeter teurer, sehr steil sehr viel teurer — '
              'auf Schotter stärker als auf Asphalt.',
          off: 'Steile Rampen kosten nur noch ein Drittel des Aufschlags.',
          value: prefs.route.avoidSteep,
          onChanged: (v) => notifier.setPrefs(prefs.copyWith(route: prefs.route.copyWith(avoidSteep: v))),
        ),
        Text(
          'Gilt auch für den Weg zum Trail. Höhe, die eine Verbindung bergab verschenkt, kostet immer etwas.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          key: const ValueKey('loop-fill-online'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Fehlende Wege online ergänzen'),
          subtitle: Text(prefs.fillOnline
              ? 'Mit Empfang kommen Wege, die deine Bereiche nicht haben, vom Kartenhost — '
                  'höchstens $kOnlineFillMaxTiles Kacheln je Planung, nur für diese Sitzung.'
              : 'Gerechnet wird nur über deine Bereiche — wie ohne Empfang.'),
          value: prefs.fillOnline,
          onChanged: (v) => notifier.setPrefs(prefs.copyWith(fillOnline: v)),
        ),
        const SizedBox(height: 8),
        Text(
          'Die Runde nimmt die gewählten Trails bergab mit und verbindet sie über die Wege deiner '
          'gespeicherten Bereiche — offline, nach deinem Profil; mit Empfang ergänzt der Kartenhost, '
          'was fehlt. Gewählt wird auf der Karte (antippen), '
          'über die Liste oder ein umfahrenes Gebiet.',
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
    messenger.showSnackBar(const SnackBar(
        key: ValueKey('loop-list-no-center'),
        content: Text('Kein Standort — setz den Start auf der Karte, dann zeigt die Liste die Trails darum.')));
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
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text('Trails in ${radius.round()} km', style: theme.textTheme.titleLarge),
        Text(
          session.start == null
              ? 'Um deinen Standort — den Radius stellst du unter Parameter.'
              : 'Um den getippten Start — den Radius stellst du unter Parameter.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
        Row(children: [
          TextButton(
            key: const ValueKey('loop-list-all'),
            onPressed: ids.isEmpty ? null : () => notifier.setSelected(ids, true),
            child: const Text('Alle wählen'),
          ),
          TextButton(
            key: const ValueKey('loop-list-none'),
            onPressed: ids.isEmpty ? null : () => notifier.setSelected(ids, false),
            child: const Text('Keine'),
          ),
        ]),
        if (pool.inReach.isEmpty)
          Text(
            key: const ValueKey('loop-list-empty'),
            pool.warned.isEmpty
                ? 'In ${radius.round()} km liegt kein Trail.'
                : 'In ${radius.round()} km liegen nur gemeldete Trails.',
          ),
        for (final t in pool.inReach) _row(session, notifier, t),
        if (pool.warned.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Gemeldet (${pool.warned.length})', style: theme.textTheme.titleMedium),
          Text('Gesperrt, zerstört oder verändert — einzeln dazunehmbar.',
              style: theme.textTheme.bodySmall?.copyWith(color: palette.warningText)),
          for (final t in pool.warned) _row(session, notifier, t),
        ],
        if (pool.connectors.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            key: const ValueKey('loop-connectors'),
            'Bergauf nutzt die Runde ${pool.connectors.length == 1 ? 'den Uphill-Trail oder Verbinder' : 'die Uphill-Trails und Verbinder'} '
            '${pool.connectors.map((t) => t.displayName).join(', ')} von selbst — gern auch mehrmals.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
        ],
        if (pool.tooFar > 0) ...[
          const SizedBox(height: 4),
          Text(
            '${pool.tooFar} ${pool.tooFar == 1 ? 'Trail liegt' : 'Trails liegen'} weiter weg — '
            'auf der Karte antippen geht trotzdem.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
        ],
      ],
    );
  }

  Widget _row(LoopSession session, LoopPlannerNotifier notifier, Trail t) {
    final on = session.selected.contains(t.id);
    final must = session.mandatory.contains(t.id);
    final parts = [
      formatMeters(t.lengthM),
      if (t.grade != null) 'S${t.grade}',
      if (t.rating != null) '${t.rating} ${t.rating == 1 ? 'Stern' : 'Sterne'}',
    ];
    return CheckboxListTile(
      key: ValueKey('loop-trail-${t.id}'),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: on,
      onChanged: (v) => notifier.setSelected([t.id], v == true),
      title: Text(t.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(parts.join(' · ')),
      secondary: IconButton(
        key: ValueKey('loop-must-${t.id}'),
        tooltip: must ? 'Muss dabei sein — abwählen' : 'Muss dabei sein',
        icon: Icon(must ? Icons.star : Icons.star_border),
        onPressed: () => notifier.toggleMandatory(t.id),
      ),
    );
  }
}

// ─── Ergebnis ───────────────────────────────────────────────────────────

/// Rechnet und zeigt das Ergebnis am Scaffold der Karte. Zu heißt:
/// Ergebnis weg, der Modus bleibt.
Future<void> showLoopResultPanel(ScaffoldState scaffold) async {
  final container = ProviderScope.containerOf(scaffold.context, listen: false);
  unawaited(container.read(loopPlannerProvider.notifier).compute());
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
    _fitted = plan;
    await widget.panel.resizeTo(kMapPanelResult);
    if (!mounted) return;
    ref.read(mapFitRequestProvider.notifier).state = plan.points;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(loopPlannerProvider, (_, next) => unawaited(_maybeFit(next)));
    final session = ref.watch(loopPlannerProvider);
    final plan = session.plan;
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 24),
      children: [
        MapPanelHeader(
          title: 'Runde',
          subtitle: plan?.summary == null ? null : _shortSummary(plan!.summary!),
          closeKey: const ValueKey('loop-close'),
          onClose: widget.panel.close,
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: switch (session.phase) {
              LoopPhase.locating => [_progress('Standort wird ermittelt …')],
              LoopPhase.loading => [_progress('Wege und Höhen aus deinen Bereichen werden gelesen …')],
              LoopPhase.computing || LoopPhase.idle => [_progress('Die Runde wird gerechnet …')],
              LoopPhase.result => session.blocker != null || plan == null
                  ? [_blockerCard(context, session.blocker ?? LoopBlocker.failed)]
                  : _result(context, session, plan),
            },
          ),
        ),
      ],
    );
  }

  Widget _progress(String text) => Row(children: [
        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ]);

  Widget _notice(BuildContext context, String text) =>
      Text(key: const ValueKey('loop-notice'), text, style: Theme.of(context).textTheme.bodyMedium);

  Widget _blockerCard(BuildContext context, LoopBlocker b) {
    final palette = AppPalette.of(context);
    return Card(
      key: const ValueKey('loop-blocker'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, color: palette.warningText),
          const SizedBox(width: 10),
          Expanded(child: _notice(context, _blockerText(b))),
        ]),
      ),
    );
  }

  String _shortSummary(LoopSummary s) =>
      '${formatMeters(s.lengthM)} · ${s.gainM.round()} hm · etwa ${routeTimeLabel(s.timeS)}';

  List<Widget> _result(BuildContext context, LoopSession session, LoopPlan plan) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    if (plan.outcome != LoopOutcome.ok) {
      return [
        _notice(context, _outcomeText(plan.outcome)),
        if (plan.excluded.isNotEmpty) ...[const SizedBox(height: 8), ..._excludedRows(context, plan)],
      ];
    }
    final s = plan.summary!;
    final trails = ref.read(trailsProvider).valueOrNull ?? const <Trail>[];
    final byId = {for (final t in trails) t.id: t};
    return [
      Text(
        key: const ValueKey('loop-summary'),
        '${formatMeters(s.lengthM)} · ${s.gainM.round()} hm bergauf · '
        '${formatMeters(s.trailM)} Trail · etwa ${routeTimeLabel(s.timeS)}',
        style: theme.textTheme.titleMedium?.copyWith(fontFamily: AppFonts.mono),
      ),
      const SizedBox(height: 4),
      Text(
        '${s.trailLossM.round()} hm bergab auf Trails · ${s.wastedLossM.round()} hm verschenkt'
        '${s.mix.isEmpty ? '' : ' · ${_mixLine(s.mix)}'}',
        style: theme.textTheme.bodyMedium,
      ),
      // Das Profil der Runde (#234) gleich darunter, kompakt: Eingeklappt
      // gehört es mit Summe und Knöpfen zu dem, was zu sehen ist.
      RouteElevationProfile(plan.points, key: const ValueKey('loop-elevation')),
      // Die Knöpfe gleich unter den Summen: Eingeklappt sind sie zu sehen,
      // die Runde darüber.
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: FilledButton.icon(
            key: const ValueKey('loop-save'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => _saveRide(session, plan),
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('Als Fahrt speichern'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('loop-gpx'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => _exportGpx(plan),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Als GPX'),
          ),
        ),
      ]),
      if (s.trailUpM > 0) ...[
        const SizedBox(height: 4),
        Text(
          key: const ValueKey('loop-trail-up'),
          'Bergauf ${formatMeters(s.trailUpM)} über ${s.trailUpNames.join(', ')}',
          style: theme.textTheme.bodyMedium,
        ),
      ],
      if (s.hikingM > 0) ...[
        const SizedBox(height: 8),
        Text(
          'Davon ${formatMeters(s.hikingM)} über Wanderweg, Fußweg oder Stufen — '
          'ob du dort fahren darfst, sagt die App nicht.',
          style: theme.textTheme.bodyMedium?.copyWith(color: palette.warningText),
        ),
      ],
      if (session.coverageNote case final note?) ...[
        const SizedBox(height: 8),
        Text(
          key: const ValueKey('loop-partial'),
          note,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      ],
      if (steepNote(s.steepM) case final note?) ...[
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
          'Nicht alle Wege haben Höhen — Höhenmeter und Zeit sind eine Untergrenze. '
          'Ein neu gespeicherter Bereich bringt sie mit.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      ],
      const SizedBox(height: 12),
      Text('In dieser Reihenfolge', style: theme.textTheme.titleMedium),
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
            if (plan.stops[i].secondPass) 'noch einmal',
          ].join(' · ')),
        ),
      if (plan.excluded.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Nicht hineingepasst', style: theme.textTheme.titleMedium),
        ..._excludedRows(context, plan),
      ],
      const SizedBox(height: 8),
      Text(
        'Ein Vorschlag aus Kartendaten, ohne Abbiegehinweise — fahre nach Sicht.',
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
          '${byId[e.key]?.displayName ?? e.key} — ${_exclusionText(e.value)}',
          style: theme.textTheme.bodySmall,
        ),
    ];
  }

  Future<void> _saveRide(LoopSession session, LoopPlan plan) async {
    if (plan.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final now = DateTime.now().toUtc();
    final ride = await ref.read(ridesProvider.notifier).savePlanned(
          name: loopName(plan),
          points: [
            for (final p in plan.points) RidePoint(lat: p.latitude, lng: p.longitude, at: now, accuracyM: 0),
          ],
          duration: Duration(seconds: plan.summary!.timeS.round()),
          profile: session.profile.name,
        );
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
        content: Text(ride == null
            ? 'Die Runde ließ sich nicht speichern.'
            : 'Als geplante Fahrt gespeichert — im Profil unter „Meine Fahrten".')));
  }

  void _exportGpx(LoopPlan plan) {
    if (plan.isEmpty) return;
    final track = loopToGpx(plan);
    shareGpx(context, ref, fileName: gpxFileName(track.name), xml: writeGpx(name: track.name, points: track.points));
  }

  String _blockerText(LoopBlocker b) => switch (b) {
        LoopBlocker.noTrails => 'Noch kein Trail gewählt — tippe Trails auf der Karte an, nimm die Liste '
            'oder umfahre ein Gebiet.',
        LoopBlocker.noPosition => 'Kein Standort — ohne ihn gibt es keinen Startpunkt. Erlaube '
            'TrailBuddy den Standort, oder setz den Start über den obersten Knopf der Leiste.',
        LoopBlocker.noArea => 'Kein gespeicherter Bereich deckt die Runde, und online kam kein Weg dazu '
            '(kein Empfang, oder „Fehlende Wege online ergänzen" ist aus). Speichere einen Bereich über '
            'den Knopf „Offline-Karten" auf der Karte — dann geht es auch ohne Empfang.',
        LoopBlocker.failed => 'Die Runde ließ sich nicht rechnen — ein Fehler, der gemeldet ist. '
            'Versuch es mit weniger Trails noch einmal.',
      };

  String _outcomeText(LoopOutcome o) => switch (o) {
        LoopOutcome.ok => '',
        LoopOutcome.startOffNetwork => 'In ${kGraphAttachM.round()} m um den Start liegt kein Weg aus der Karte.',
        LoopOutcome.endOffNetwork => 'In ${kGraphAttachM.round()} m um das Ziel liegt kein Weg aus der Karte.',
        LoopOutcome.empty => 'Kein gewählter Trail passt in die Runde — die Gründe stehen je Trail. '
            'Mehr Zeit oder Höhenmeter unter Parameter, oder ein anderer Start.',
      };

  String _exclusionText(LoopExclusion e) => switch (e) {
        LoopExclusion.tooFar => 'zu weit vom Start',
        LoopExclusion.offNetwork => 'Anfang oder Ende liegt an keinem Weg der Karte',
        LoopExclusion.unreachable => 'von den Wegen deiner Bereiche aus nicht erreichbar',
        LoopExclusion.budget => 'passt nicht ins Budget',
      };
}

String _hoursLabel(double h) {
  final whole = h.floor();
  final half = h - whole >= 0.5;
  return half ? '$whole h 30 min' : '$whole h';
}

/// „Forstweg 2,1 km · Nebenstraße 300 m" — die Klassen nach Länge.
String _mixLine(Map<WayClass, double> mix) {
  final entries = mix.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return entries.map((e) => '${e.key.label} ${formatMeters(e.value)}').join(' · ');
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

/// Die Vorschau: die ganze Linie blass, Verbindungen in der Fahrt-Farbe
/// (Wanderweg gestrichelt), die Trails als breiter Saum darunter — die
/// Trail-Linien selbst behalten ihre Farbe, der Saum sagt „dabei".
List<MapViewPolyline> loopPreviewLines(LoopPlan plan) {
  if (plan.outcome != LoopOutcome.ok) return const [];
  final c = AppColors.mapLines.ride;
  return [
    MapViewPolyline(points: plan.points, color: c.withValues(alpha: 0.35), width: 2),
    for (final s in plan.sections)
      if (s.isTrail)
        MapViewPolyline(points: s.points, color: c.withValues(alpha: 0.45), width: 9)
      else
        MapViewPolyline(
          points: s.points,
          color: c,
          width: 5,
          dash: s.hiking ? const [10, 8] : null,
          borderColor: AppColors.mapLines.halo,
          borderWidth: AppColors.mapLines.haloBorderWidth,
        ),
  ];
}
