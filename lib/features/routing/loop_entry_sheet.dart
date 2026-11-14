// Der Einstieg des Planers (#516, Konzept-Routing 12.3, Schritt 2 aus
// 12.9): Der Planer-Knopf fragt erst nach der Absicht, nicht nach
// Werkzeugen. EIN kleines Blatt unten, wo danach Auswahlzeile und
// Ergebnis stehen; es fragt von oben nach unten, und jede Zeile ist
// vorbelegt — wer einverstanden ist, tippt nur den Knopf.
//
// - **Runde**: Start (Standort · Karte) und Zeit; „Runde vorschlagen"
//   rechnet aus allen Trails im Umkreis der Zeit (12.4, Schritt 4).
//   Wer selbst wählen will, nimmt „Selbst zusammenstellen" oder
//   „Bearbeiten" am Vorschlag.
// - **Route**: Start und Ziel (Standort · Karte); sobald das Ziel steht,
//   rechnet die Karte (`entryRouteReady`). „Route" ohne Ziel wartet gleich
//   auf den Tipp — Planer → Route → Tipp: drei Tipps.
// - **„Auf der Karte wählen"** blendet das Blatt aus; oben steht das
//   Banner mit Abbrechen, wie in der Bearbeitung. Danach kommt es wieder.
// - **„Selbst zusammenstellen"** ist die Bearbeitung, leer wie bisher.
//
// - **Die Frage zum Limit** (#516 Schritt 6, 12.5a): Blieb sie im Blatt am
//   Ende der Fahrt unbeantwortet, steht sie hier EINMAL über dem Knopf —
//   gelesen und geleert beim Aufgehen.
//
// Kein Persistent Bottom Sheet wie das Ergebnis (12.3 sah es so vor): Es
// würde beim Tipp auf die Karte zu- und wieder aufgehen und die Karte
// darüber einpassen; als Karte im Body tritt es einfach zurück, wie die
// Auswahlzeile beim Zeichnen.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart' show AppFonts;
import '../../l10n/l10n.dart';
import '../coach/coach.dart';
import '../help/map_tour.dart' show MapCoach;
import '../map/position_provider.dart';
import '../rides/climb_limit_offer.dart' show ClimbLimitOffer;
import '../rides/climb_limit_row.dart';
import 'loop_planner.dart' show LoopPrefs;
import 'loop_planner_controller.dart';
import 'loop_planner_sheet.dart' show loopHoursLabel;

class LoopEntrySheet extends ConsumerStatefulWidget {
  const LoopEntrySheet({super.key, required this.onCompute, required this.onSuggest, required this.onClose});

  /// Die Route rechnen — dieselbe Stelle wie „Route rechnen" in der
  /// Auswahlzeile (das Ergebnis-Blatt geht auf).
  final VoidCallback onCompute;

  /// „Runde vorschlagen" (#516 Schritt 4): das Ergebnis-Blatt mit dem
  /// Vorschlag.
  final VoidCallback onSuggest;
  final VoidCallback onClose;

  @override
  ConsumerState<LoopEntrySheet> createState() => _LoopEntrySheetState();
}

class _LoopEntrySheetState extends ConsumerState<LoopEntrySheet> {
  /// „Mein Standort" als Ziel fand keinen Fix — der Satz steht, bis eine
  /// andere Wahl kommt.
  bool _noPosition = false;
  bool _locating = false;

  /// Die gemerkte Frage zum Limit, einmal gelesen (und damit geleert).
  late final ClimbLimitOffer? _climbOffer = takePendingClimbLimit(ref);

  LoopPlannerNotifier get _n => ref.read(loopPlannerProvider.notifier);

  void _setRoute(bool route) {
    setState(() => _noPosition = false);
    _n.setIntent(route: route);
    // Drei Tipps (12.3): Planer → Route → Tipp auf die Karte.
    if (route && ref.read(loopPlannerProvider).target == null) _n.armTargetPick();
  }

  Future<void> _targetMine() async {
    setState(() {
      _noPosition = false;
      _locating = true;
    });
    final fix = await ref.read(currentPositionProvider)();
    if (!mounted) return;
    setState(() => _locating = false);
    if (fix == null) {
      setState(() => _noPosition = true);
      return;
    }
    _n.takeTargetMine(LatLng(fix.latitude, fix.longitude));
    if (_n.entryRouteReady) widget.onCompute();
  }

  void _go() {
    final s = ref.read(loopPlannerProvider);
    if (!s.prefs.intentRoute) {
      widget.onSuggest();
    } else if (s.target == null) {
      _n.armTargetPick();
    } else if (s.targetMine && s.start == null) {
      _n.armStartPick();
    } else {
      widget.onCompute();
    }
  }

  void _hours(double delta) {
    final prefs = ref.read(loopPlannerProvider).prefs;
    final h = (prefs.hours + delta).clamp(LoopPrefs.minHours, LoopPrefs.maxHours).toDouble();
    if (h != prefs.hours) _n.setPrefs(prefs.copyWith(hours: h));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(loopPlannerProvider);
    final l = context.l10n;
    final theme = Theme.of(context);
    final route = s.prefs.intentRoute;

    Widget label(String text) => SizedBox(width: 52, child: Text(text, style: theme.textTheme.labelLarge));

    Widget choice(String key, String text, bool chosen, VoidCallback onTap) => ChoiceChip(
          key: ValueKey(key),
          label: Text(text),
          selected: chosen,
          onSelected: (_) => onTap(),
          materialTapTargetSize: MaterialTapTargetSize.padded,
        );

    Widget line(String name, List<Widget> chips) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            label(name),
            Expanded(child: Wrap(spacing: 8, runSpacing: 0, children: chips)),
          ]),
        );

    final startLine = line(l.loopHeadStart, [
      choice('loop-entry-start-me', l.loopHeadMine, s.start == null, () {
        setState(() => _noPosition = false);
        if (s.start != null) _n.useMyPosition();
      }),
      choice('loop-entry-start-map', l.loopEntryPickOnMap, s.start != null, () {
        setState(() => _noPosition = false);
        _n.armStartPick();
      }),
    ]);

    final timeLine = Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        label(l.loopEntryTime),
        IconButton.filledTonal(
          key: const ValueKey('loop-entry-less'),
          tooltip: l.loopEntryLess,
          iconSize: 28,
          constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
          onPressed: s.prefs.hours > LoopPrefs.minHours ? () => _hours(-LoopPrefs.hoursStep) : null,
          icon: const Icon(Icons.remove),
        ),
        Expanded(
          child: Text(
            l.loopEntryHours(loopHoursLabel(l, s.prefs.hours)),
            key: const ValueKey('loop-entry-hours'),
            textAlign: TextAlign.center,
            style: AppFonts.numbers(theme.textTheme.titleMedium),
          ),
        ),
        IconButton.filledTonal(
          key: const ValueKey('loop-entry-more'),
          tooltip: l.loopEntryMore,
          iconSize: 28,
          constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
          onPressed: s.prefs.hours < LoopPrefs.maxHours ? () => _hours(LoopPrefs.hoursStep) : null,
          icon: const Icon(Icons.add),
        ),
      ]),
    );

    final targetLine = line(l.loopHeadTarget, [
      choice('loop-entry-target-me', l.loopHeadMine, s.targetMine, () {
        if (!_locating) unawaited(_targetMine());
      }),
      choice('loop-entry-target-map', l.loopEntryPickOnMap, s.target != null && !s.targetMine, () {
        setState(() => _noPosition = false);
        _n.armTargetPick();
      }),
    ]);

    return CoachAnchor(
      id: MapCoach.loopEntry,
      child: Card(
        key: const ValueKey('loop-entry'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(l.loopEntryTitle, style: theme.textTheme.titleMedium)),
              IconButton(
                key: const ValueKey('loop-entry-close'),
                tooltip: l.loopRailClose,
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                      value: false,
                      icon: const Icon(Icons.loop),
                      label: Text(l.loopEntryLoop, key: const ValueKey('loop-entry-loop'))),
                  ButtonSegment(
                      value: true,
                      icon: const Icon(Icons.place_outlined),
                      label: Text(l.loopEntryRoute, key: const ValueKey('loop-entry-route'))),
                ],
                selected: {route},
                showSelectedIcon: false,
                onSelectionChanged: (v) => _setRoute(v.first),
              ),
            ),
            startLine,
            if (route) targetLine else timeLine,
            if (_noPosition)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: Text(l.loopEntryNoPosition,
                    key: const ValueKey('loop-entry-no-position'),
                    style: theme.textTheme.bodySmall?.copyWith(color: AppPalette.of(context).warningText)),
              ),
            if (_climbOffer != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: ClimbLimitRow(offer: _climbOffer),
              ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                key: const ValueKey('loop-entry-go'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: AppColors.brand,
                  foregroundColor: AppColors.onBrand,
                ),
                onPressed: _locating ? null : _go,
                icon: Icon(route ? Icons.alt_route : Icons.touch_app_outlined),
                label: Text(route ? l.loopRailComputeRoute : l.loopEntrySuggest),
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: TextButton(
                key: const ValueKey('loop-entry-self'),
                onPressed: _n.leaveEntry,
                child: Text(l.loopEntrySelf),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
