// Die Schnellkarte (#178, Feldbericht 0.73.0: „Wenn man einen Trail
// auswählt, sollte er auf der Karte hervorgehoben werden und nur ein
// Miniatur-Popup kommen. Ein weiterer Klick auf die Miniatur öffnet erst
// das große Trail-Infoblatt. Das irritiert den Nutzer weniger").
//
// Ein Tipp auf einen Trail der Karte wählt ihn aus: Er leuchtet, unten
// steht diese Karte — Schild, Name, Länge, Sterne und das Navi-Symbol
// (#176). Ein Tipp auf die Karte öffnet das Blatt; ein Tipp daneben,
// das X oder Zurück heben die Auswahl auf. Die Karte bleibt dabei frei:
// verschieben, zoomen, einen anderen Trail antippen.
import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/geo.dart' show formatMeters;
import '../../models/trail.dart';
import '../routing/navigate_choice.dart';
import '../trails/grade_shield.dart';
import '../../l10n/l10n.dart';

class TrailQuickCard extends StatelessWidget {
  const TrailQuickCard({super.key, required this.trail, required this.onOpen, required this.onClose});

  final Trail trail;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final parts = [
      formatMeters(trail.lengthM),
      if (trail.rating != null) '${trail.rating} ★',
      if (trail.status.warns) trail.status.label,
    ];
    return Card(
      key: const ValueKey('trail-quick-card'),
      margin: EdgeInsets.zero,
      elevation: 6,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('trail-quick-open'),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 0, 6),
          child: Row(
            children: [
              if (trail.grade != null)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GradeShield(trail.grade!, fontSize: 13, uphill: isUphill(trail)),
                ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(trail.displayName,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                    Text(
                      parts.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: trail.status.warns ? palette.warningText : theme.hintColor),
                    ),
                  ],
                ),
              ),
              if (!trail.pending) TrailNavButton(trail),
              const Icon(Icons.chevron_right),
              IconButton(
                key: const ValueKey('trail-quick-close'),
                tooltip: context.l10n.mapQuickCardClose,
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
