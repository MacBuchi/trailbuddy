// Kopf und Auswahlzeile der Bearbeitungsansicht des Planers (#516,
// Konzept-Routing 12.6/12.7). Der Kopf steht oben bei den Bannern: Start
// und Ziel als zwei Zeilen mit denselben Wörtern wie auf den Fahnen,
// darunter das Budget mit „Anpassen", rechts das X. Die Auswahlzeile steht
// unten, wo danach das Ergebnis steht: wie viel gewählt ist, „Leeren" und
// EIN Knopf mit Wort — „Runde rechnen" oder „Route rechnen". Was ein Tipp
// auf einen Trail geändert hat („… dazugenommen · Rückgängig", #375),
// sagt dieselbe Zeile; als Leiste verdeckte es Leiste und „Meine Position".
//
// „Runde | Route" ist keine eigene Einstellung: Sie folgt aus dem Ziel —
// zurück zum Start heißt Runde, alles andere Route (`LoopEndMode` bleibt,
// nur die Stelle der Wahl ist neu).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart' show AppFonts;
import '../../l10n/l10n.dart';
import '../coach/coach.dart';
import '../help/map_tour.dart' show MapCoach;
import '../trails/trail_providers.dart' show trailByIdProvider;
import 'loop_planner.dart' show LoopEndMode;
import 'loop_planner_controller.dart';
import 'loop_planner_sheet.dart' show LoopStartFlag, loopHoursLabel;

/// Die Fahnen des Planers sind antippbar (#516, Konzept-Routing 12.6): Ein
/// Tipp öffnet dieselbe Wahl wie ihre Zeile im Kopf.
enum LoopFlagHit { start, target }

/// Gibt es im Planer etwas zu rechnen? Trails, ein Ziel (die Route von A
/// nach B, #356) oder Zwischenpunkte (#395).
bool loopCanCompute(LoopSession s) =>
    !s.busy && (s.selected.isNotEmpty || s.prefs.endMode == LoopEndMode.target || s.waypoints.isNotEmpty);

/// Was der Planer rechnet, folgt aus dem Ziel: zurück zum Start ist eine
/// Runde, alles andere eine Route.
bool loopIsRoute(LoopSession s) => s.prefs.endMode != LoopEndMode.loop;

class LoopEditHeader extends ConsumerWidget {
  const LoopEditHeader({super.key, required this.onAdjust, required this.onClose, this.compact = false});

  final VoidCallback onAdjust;
  final VoidCallback onClose;

  /// Eine Zeile „Start → Ziel" und das X, solange ein Ergebnis offen ist:
  /// Die Karte passt die Route über dem Blatt ein, und die drei Zeilen
  /// lägen über ihrem oberen Drittel (im Flow-Test gefunden: ein
  /// Gummipunkt war nicht mehr zu greifen). Budget und „Anpassen" gehören
  /// zur Bearbeitung (Konzept-Routing 12.7); im Ergebnis rechnen Stil und
  /// Rad.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(loopPlannerProvider);
    final l = context.l10n;
    final theme = Theme.of(context);
    final targetTrail = s.targetTrailId == null ? null : ref.watch(trailByIdProvider(s.targetTrailId!));
    final startValue = s.start == null ? l.loopHeadMine : l.loopHeadPicked;
    final targetValue = switch (s.prefs.endMode) {
      LoopEndMode.loop => l.loopHeadTargetLoop,
      LoopEndMode.lastTrail => l.loopHeadTargetLast,
      LoopEndMode.target => s.target == null
          ? l.loopHeadTargetNone
          : s.targetMine
              ? l.loopHeadMine
              : targetTrail?.displayName(l) ?? l.loopHeadPicked,
    };
    final budget = l.loopHeadBudget(
        loopHoursLabel(l, s.prefs.hours), s.prefs.climbM.round(), s.profile.label(l));

    Widget row(String key, Widget leading, String label, String value, VoidCallback onTap) => InkWell(
          key: ValueKey(key),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(children: [
              SizedBox(width: 32, child: Center(child: leading)),
              SizedBox(
                width: 44,
                child: Text(label, style: theme.textTheme.labelLarge),
              ),
              Expanded(
                child: Text(value,
                    key: ValueKey('$key-value'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium),
              ),
              const Icon(Icons.chevron_right, size: 20),
            ]),
          ),
        );

    final close = IconButton(
      key: const ValueKey('loop-head-close'),
      tooltip: l.loopRailClose,
      onPressed: onClose,
      icon: const Icon(Icons.close),
    );

    if (compact) {
      Widget half(String key, Widget flag, String value, VoidCallback onTap) => Expanded(
            child: InkWell(
              key: ValueKey(key),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(children: [
                  flag,
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(value,
                        key: ValueKey('$key-value'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium),
                  ),
                ]),
              ),
            ),
          );
      return CoachAnchor(
        id: MapCoach.loopHead,
        child: Card(
          key: const ValueKey('loop-head'),
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(children: [
              half('loop-head-start', const LoopStartFlag(size: 18), startValue, () => showLoopStartChoice(context)),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.arrow_forward, size: 16)),
              half('loop-head-target', const LoopStartFlag(size: 18, finish: true), targetValue,
                  () => showLoopTargetChoice(context)),
              close,
            ]),
          ),
        ),
      );
    }

    return CoachAnchor(
      id: MapCoach.loopHead,
      child: Card(
        key: const ValueKey('loop-head'),
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 0, 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                row('loop-head-start', const LoopStartFlag(size: 20), l.loopHeadStart, startValue,
                    () => showLoopStartChoice(context)),
                row('loop-head-target', const LoopStartFlag(size: 20, finish: true), l.loopHeadTarget, targetValue,
                    () => showLoopTargetChoice(context)),
                Row(children: [
                  const SizedBox(width: 32 + 44),
                  Expanded(
                    child: Text(budget,
                        key: const ValueKey('loop-head-budget'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.numbers(theme.textTheme.bodySmall)),
                  ),
                  CoachAnchor(
                    id: MapCoach.loopRailButton('loop-adjust'),
                    child: TextButton(
                      key: const ValueKey('loop-adjust'),
                      style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                      onPressed: onAdjust,
                      child: Text(l.loopHeadAdjust),
                    ),
                  ),
                ]),
              ]),
            ),
            close,
          ]),
        ),
      ),
    );
  }
}

/// Die Wahl des Starts — aus dem Kopf und von der Startfahne.
Future<void> showLoopStartChoice(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Consumer(builder: (context, ref, _) {
        final s = ref.watch(loopPlannerProvider);
        final n = ref.read(loopPlannerProvider.notifier);
        final l = context.l10n;
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _ChoiceTile(
              key: const ValueKey('loop-start-me'),
              icon: Icons.my_location,
              text: l.loopHeadMine,
              chosen: s.start == null,
              onTap: () {
                Navigator.of(context).pop();
                if (s.start != null) n.useMyPosition();
              },
            ),
            _ChoiceTile(
              key: const ValueKey('loop-pick'),
              icon: Icons.touch_app_outlined,
              text: l.loopHeadPickOnMap,
              chosen: s.start != null,
              onTap: () {
                Navigator.of(context).pop();
                n.armStartPick();
              },
            ),
          ]),
        );
      }),
    );

/// Die Wahl des Ziels — aus dem Kopf und von der Zielfahne. Sie ist
/// zugleich „Runde oder Route" (Konzept-Routing 12.6).
Future<void> showLoopTargetChoice(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Consumer(builder: (context, ref, _) {
        final s = ref.watch(loopPlannerProvider);
        final n = ref.read(loopPlannerProvider.notifier);
        final l = context.l10n;
        final mode = s.prefs.endMode;
        void setMode(LoopEndMode m) {
          if (mode != m) n.setPrefs(s.prefs.copyWith(endMode: m));
        }

        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _ChoiceTile(
              key: const ValueKey('loop-end-loop'),
              icon: Icons.loop,
              text: l.loopHeadTargetLoop,
              chosen: mode == LoopEndMode.loop,
              onTap: () {
                Navigator.of(context).pop();
                setMode(LoopEndMode.loop);
              },
            ),
            _ChoiceTile(
              key: const ValueKey('loop-pick-target'),
              icon: Icons.touch_app_outlined,
              text: l.loopHeadPickOnMap,
              chosen: mode == LoopEndMode.target,
              onTap: () {
                Navigator.of(context).pop();
                setMode(LoopEndMode.target);
                n.armTargetPick();
              },
            ),
            _ChoiceTile(
              key: const ValueKey('loop-end-last'),
              icon: Icons.last_page,
              text: l.loopHeadTargetLast,
              chosen: mode == LoopEndMode.lastTrail,
              onTap: () {
                Navigator.of(context).pop();
                setMode(LoopEndMode.lastTrail);
              },
            ),
          ]),
        );
      }),
    );

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({super.key, required this.icon, required this.text, required this.chosen, required this.onTap});

  final IconData icon;
  final String text;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(text),
        trailing: chosen ? const Icon(Icons.check) : null,
        selected: chosen,
        onTap: onTap,
      );
}

/// Was die Auswahlzeile gerade meldet: ein Tipp auf einen Trail oder
/// „Leeren", mit Rückgängig.
typedef LoopBarNote = ({String text, VoidCallback undo});

class LoopSelectionBar extends ConsumerWidget {
  const LoopSelectionBar({super.key, required this.onCompute, required this.onClear, this.note});

  final VoidCallback onCompute;
  final VoidCallback onClear;
  final LoopBarNote? note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(loopPlannerProvider);
    final l = context.l10n;
    final theme = Theme.of(context);
    final trails = s.selected.length;
    final points = s.waypoints.length;
    final empty = trails == 0 && points == 0;
    final count = [
      if (trails > 0) l.loopBarTrails(trails),
      if (points > 0) l.loopBarPoints(points),
    ].join(' · ');
    final note = this.note;
    return CoachAnchor(
      id: MapCoach.loopBar,
      child: Card(
        key: const ValueKey('loop-bar'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (note != null)
              Row(key: const ValueKey('loop-toggled'), children: [
                Expanded(child: Text(note.text, style: theme.textTheme.bodyMedium)),
                TextButton(
                  key: const ValueKey('loop-toggled-undo'),
                  onPressed: note.undo,
                  child: Text(l.commonUndo),
                ),
              ])
            else if (empty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  loopIsRoute(s) ? l.mapLoopHintRoute : l.mapLoopHint,
                  key: const ValueKey('loop-hint'),
                  style: theme.textTheme.bodySmall,
                ),
              )
            else
              Row(children: [
                Expanded(
                  child: Text(count,
                      key: const ValueKey('loop-bar-count'), style: AppFonts.numbers(theme.textTheme.bodyMedium)),
                ),
                TextButton(key: const ValueKey('loop-clear'), onPressed: onClear, child: Text(l.loopBarClear)),
              ]),
            const SizedBox(height: 4),
            CoachAnchor(
              id: MapCoach.loopRailButton('loop-compute'),
              child: FilledButton.icon(
                key: const ValueKey('loop-compute'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: AppColors.brand,
                  foregroundColor: AppColors.onBrand,
                ),
                onPressed: loopCanCompute(s) ? onCompute : null,
                icon: const Icon(Icons.alt_route),
                label: Text(loopIsRoute(s) ? l.loopRailComputeRoute : l.loopComputeLoop),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Wie lange die Auswahlzeile meldet, was ein Tipp geändert hat (#516) —
/// so lange wie eine SnackBar ohne Aktion.
const kLoopNoteDuration = Duration(seconds: 4);

/// Abstand der Planer-Leiste zum Kopf oben und zur Auswahlzeile unten
/// (#516): Der Kopf ist drei Zeilen hoch, die Zeile ein Satz und ein Knopf.
const kLoopRailTopInset = 176.0;
const kLoopRailBottomInset = 136.0;
