// Die Werkzeugleiste des Planers (seit 0.74.0; Betreiber: „zum Planen
// links ein Menü in der Art wie rechts, mit Planer-Optionen") — derselbe
// Look wie die Leiste „Offline-Karten" (Design 3e: 52 dp, Knöpfe 44 dp, aktives
// Werkzeug in Gegenhelligkeit, Hauptaktion Lime, Zähler in Mono). Der
// Runden-Knopf rechts öffnet sie, derselbe Knopf, das X und Zurück
// schließen sie.
//
// Von oben: Start (getippt oder Standort), Parameter (das Blatt mit den
// Reglern), Liste (Trails im Radius), Gebiet dazu / Gebiet weg (gezeichnet,
// wie bei den Bereichen), Auswahl leeren — dann Rechnen mit der Zahl der
// gewählten Trails darunter, und Schließen. Trails wählt man außerdem
// direkt auf der Karte: ein Tipp an, ein Tipp ab.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../l10n/l10n.dart';
import '../coach/coach.dart';
import '../help/map_tour.dart' show MapCoach;
import '../map/map_buttons.dart';
import '../offline_areas/area_draw.dart' show AreaDrawTool;
import '../offline_areas/offline_tool_rail.dart' show kRailWidth, compactCount;
import 'loop_planner_controller.dart';

class LoopToolRail extends ConsumerWidget {
  const LoopToolRail({
    super.key,
    required this.onParams,
    required this.onList,
    required this.onCompute,
    required this.onClose,
  });

  final VoidCallback onParams;
  final VoidCallback onList;
  final VoidCallback onCompute;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(loopPlannerProvider);
    final notifier = ref.read(loopPlannerProvider.notifier);
    final p = AppPalette.of(context);
    final l = context.l10n;
    final countStyle = AppFonts.numbers(Theme.of(context).textTheme.labelMedium);
    final count = session.selected.length;

    Widget button(String key, String tip, IconData icon, VoidCallback? onPressed,
            {bool selected = false, bool primary = false}) =>
        CoachAnchor(
          id: MapCoach.loopRailButton(key),
          child: IconButton(
            key: ValueKey(key),
            tooltip: tip,
            isSelected: selected,
            iconSize: 22,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: kMapButtonSize, height: kMapButtonSize),
            style: IconButton.styleFrom(
              backgroundColor: selected
                  ? p.text
                  : primary && onPressed != null
                      ? AppColors.brand
                      : null,
              foregroundColor: selected
                  ? p.ground
                  : primary && onPressed != null
                      ? AppColors.onBrand
                      : p.text,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onPressed,
            icon: Icon(icon),
          ),
        );

    const gap = SizedBox(height: 8);

    return Container(
      key: const ValueKey('loop-tool-rail'),
      width: kRailWidth,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(kRailWidth / 2),
        border: Border.all(color: p.line),
        boxShadow: const [BoxShadow(blurRadius: 8, offset: Offset(0, 2), color: Color(0x33000000))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            'loop-rail-start',
            session.start == null ? l.loopRailStartMine : l.loopRailStartPicked,
            session.start == null ? Icons.my_location : Icons.flag_outlined,
            session.pickingStart ? notifier.cancelStartPick : notifier.armStartPick,
            selected: session.pickingStart,
          ),
          button('loop-rail-params', l.loopRailParams, Icons.tune, onParams),
          gap,
          button('loop-rail-list', l.loopRailList, Icons.format_list_bulleted, onList),
          button('loop-rail-area-add', l.loopRailAreaAdd, Icons.add_circle_outline,
              () => notifier.armDraw(AreaDrawTool.add),
              selected: session.drawTool == AreaDrawTool.add),
          button('loop-rail-area-remove', l.loopRailAreaRemove, Icons.remove_circle_outline,
              () => notifier.armDraw(AreaDrawTool.remove),
              selected: session.drawTool == AreaDrawTool.remove),
          button('loop-rail-clear', l.loopRailClear, Icons.deselect, count == 0 ? null : notifier.clearSelection),
          gap,
          button(
            'loop-rail-compute',
            count == 0 ? l.loopRailComputeNone : l.loopRailCompute(count),
            Icons.alt_route,
            count == 0 || session.busy ? null : onCompute,
            primary: true,
          ),
          const SizedBox(height: 2),
          Text(count == 0 ? '–' : compactCount(count), key: const ValueKey('loop-rail-count'),
              style: countStyle.copyWith(color: p.text)),
          gap,
          button('loop-rail-close', l.loopRailClose, Icons.close, onClose),
        ],
      ),
    );
  }
}
