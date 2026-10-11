// Quellenhinweis der MapLibre-Karte. Nicht der des Pakets
// (`SourceAttribution`): Der sammelt die Angabe JEDER Quelle aus der
// nativen Karte, und jeder gespeicherte Bereich ist eine eigene Quelle mit
// eigener Angabe im Archiv — mit drei Bereichen stand dieselbe Zeile
// dreimal da. Hier steht jede Angabe einmal, wie bei flutter_map.
import 'package:flutter/material.dart';

import '../../../core/app_colors.dart';
import '../map_buttons.dart';
import '../../../l10n/l10n.dart';

/// Die Zeilen des Hinweises: Karte und Daten fest, dazu [extra] (die
/// Quellen der offiziellen Trails), jede genau einmal.
List<String> mapAttributionLines(List<String> extra) => {
      'MapLibre',
      '© OpenStreetMap-Mitwirkende (ODbL)',
      'Protomaps',
      ...extra,
    }.toList();

/// Ein „i" unten links; ein Tipp klappt die Zeilen daneben auf.
class MapAttribution extends StatefulWidget {
  const MapAttribution({super.key, required this.lines, this.leftInset = 0});

  final List<String> lines;
  final double leftInset;

  @override
  State<MapAttribution> createState() => _MapAttributionState();
}

class _MapAttributionState extends State<MapAttribution> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: EdgeInsets.only(left: widget.leftInset),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const ValueKey('map-attribution'),
                tooltip: context.l10n.mapAttributionTooltip,
                iconSize: 18,
                style: IconButton.styleFrom(
                  fixedSize: const Size.square(kMapButtonSize),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                // Die Karte ist immer hell (AppColors.mapBackground).
                color: AppColors.light.muted,
                onPressed: () => setState(() => _open = !_open),
                icon: const Icon(Icons.info_outline),
              ),
              if (_open)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      widget.lines.join(' · '),
                      style: TextStyle(fontSize: 12, color: p.text),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
