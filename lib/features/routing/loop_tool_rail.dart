// Die Werkzeugleiste des Planers (seit 0.74.0; Betreiber: „zum Planen
// links ein Menü in der Art wie rechts, mit Planer-Optionen") — derselbe
// Look wie die Leiste „Offline-Karten" (Design 3e: 52 dp, Knöpfe 44 dp, aktives
// Werkzeug in Gegenhelligkeit).
//
// Seit #516 (Konzept-Routing 12.7) trägt sie nur noch, was auf der Karte
// wählt, und jedes Werkzeug hat ein Wort: Punkt (Zwischenpunkt tippen),
// Gebiet (umfahren — ein Werkzeug, darunter der Umschalter dazu/weg,
// solange es scharf ist), Liste (Trails im Radius). Start, Ziel, Budget
// und das X stehen im Kopf, Zahl, „Leeren" und „Rechnen" in der
// Auswahlzeile unten (`loop_edit_bars.dart`). Trails wählt man außerdem
// direkt auf der Karte: ein Tipp an, ein Tipp ab.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../l10n/l10n.dart';
import '../coach/coach.dart';
import '../help/map_tour.dart' show MapCoach;
import '../map/map_buttons.dart';
import '../offline_areas/area_draw.dart' show AreaDrawTool;
import '../offline_areas/offline_tool_rail.dart' show kRailWidth;
import 'loop_planner_controller.dart';

class LoopToolRail extends ConsumerWidget {
  const LoopToolRail({super.key, required this.onList});

  final VoidCallback onList;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(loopPlannerProvider);
    final notifier = ref.read(loopPlannerProvider.notifier);
    final p = AppPalette.of(context);
    final l = context.l10n;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(color: p.text, height: 1.1);
    final drawing = session.drawTool != null;

    // Jedes Tippziel 44 dp (A13), auch der Umschalter des Gebiets.
    Widget button(String key, String tip, IconData icon, VoidCallback onPressed,
            {String? label, bool selected = false}) =>
        CoachAnchor(
          id: MapCoach.loopRailButton(key),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              key: ValueKey(key),
              tooltip: tip,
              isSelected: selected,
              iconSize: 22,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: kMapButtonSize, height: kMapButtonSize),
              style: IconButton.styleFrom(
                backgroundColor: selected ? p.text : null,
                foregroundColor: selected ? p.ground : p.text,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onPressed,
              icon: Icon(icon),
            ),
            // Das Wort unter dem Symbol (#516) — gelesen wird es, getippt
            // wird das Symbol; die Zeile gehört zur Tippfläche nicht dazu.
            if (label != null)
              ExcludeSemantics(
                child: Text(label, style: labelStyle, textAlign: TextAlign.center, maxLines: 1),
              ),
          ]),
        );

    const gap = SizedBox(height: 6);

    return Container(
      key: const ValueKey('loop-tool-rail'),
      width: kRailWidth,
      padding: const EdgeInsets.symmetric(vertical: 6),
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
            'loop-rail-waypoint',
            l.loopRailWaypoint,
            Icons.add_location_alt_outlined,
            session.pickingWaypoint ? notifier.cancelStartPick : notifier.armWaypointPick,
            label: l.loopRailPointLabel,
            selected: session.pickingWaypoint,
          ),
          gap,
          button(
            'loop-rail-area',
            l.loopRailArea,
            Icons.gesture,
            drawing ? notifier.disarmDraw : () => notifier.armDraw(AreaDrawTool.add),
            label: l.loopRailAreaLabel,
            selected: drawing,
          ),
          // Der Umschalter des Gebiets: nur, solange es scharf ist — dazu
          // ist die Vorgabe, weg der zweite Strich.
          if (drawing) ...[
            const SizedBox(height: 2),
            for (final (tool, key, tip, icon) in [
              (AreaDrawTool.add, 'loop-rail-area-add', l.loopRailAreaAdd, Icons.add_circle_outline),
              (AreaDrawTool.remove, 'loop-rail-area-remove', l.loopRailAreaRemove, Icons.remove_circle_outline),
            ])
              button(key, tip, icon, () {
                if (session.drawTool != tool) notifier.armDraw(tool);
              }, selected: session.drawTool == tool),
          ],
          gap,
          button('loop-rail-list', l.loopRailList, Icons.format_list_bulleted, onList, label: l.loopRailListLabel),
        ],
      ),
    );
  }
}
