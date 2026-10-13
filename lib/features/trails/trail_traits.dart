// Der Charakter eines Trails (#72): Beschreibung und Symbol je Merkmal —
// an EINER Stelle wie die Singletrail-Skala (`singletrail_scale.dart`).
// Auswahl im Beitrag, Chips im Blatt, Symbole in der Liste und die
// Filter-Chips lesen von hier; zwei Fassungen wären zwei Meinungen
// darüber, was „verblockt" heißt.
import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../l10n/l10n.dart';
import '../../models/trail.dart';

extension TrailTraitView on TrailTrait {
  /// Ein paar Wörter: was man dort erwartet (Design Turn 4).
  /// #209: aus den ARB-Dateien.
  String description(AppLocalizations l) => switch (this) {
        TrailTrait.flowy => l.traitFlowyDescription,
        TrailTrait.jumps => l.traitJumpsDescription,
        TrailTrait.rocky => l.traitRockyDescription,
        TrailTrait.steep => l.traitSteepDescription,
        TrailTrait.uphill => l.traitUphillDescription,
        TrailTrait.natural => l.traitNaturalDescription,
        TrailTrait.connection => l.traitConnectionDescription,
      };

  /// Das Symbol — farblos: Die Farbe sagt, was ICH mit dem Trail zu tun
  /// habe (Design), nicht, wie er ist.
  IconData get icon => switch (this) {
        TrailTrait.flowy => Icons.waves,
        TrailTrait.jumps => Icons.flight_takeoff,
        TrailTrait.rocky => Icons.landslide_outlined,
        TrailTrait.steep => Icons.trending_down,
        TrailTrait.uphill => Icons.trending_up,
        TrailTrait.natural => Icons.forest_outlined,
        TrailTrait.connection => Icons.alt_route,
      };
}

/// Ein Merkmal zum Wählen: Symbol, Wort, Beschreibung als Tooltip. Gewählt
/// ist es in der Marke gefüllt — die gedeckte Auswahlfarbe des Themes
/// allein war im Dunklen kaum vom Rest zu unterscheiden, und ein Haken
/// verdrängte das Symbol, an dem man das Merkmal erkennt.
class TrailTraitChip extends StatelessWidget {
  const TrailTraitChip(this.trait,
      {super.key, required this.selected, required this.onSelected, this.label});

  final TrailTrait trait;
  final bool selected;
  /// null sperrt den Chip (etwa während gespeichert wird).
  final ValueChanged<bool>? onSelected;

  /// Ein kürzeres Wort als [TrailTrait.label] („Jumps" in den Filtern).
  final String? label;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.onBrand : null;
    return Tooltip(
      message: trait.description(context.l10n),
      child: FilterChip(
        avatar: Icon(trait.icon, size: 18, color: fg),
        label: Text(label ?? trait.label(context.l10n), style: fg == null ? null : TextStyle(color: fg)),
        selected: selected,
        selectedColor: AppColors.brand,
        side: selected ? const BorderSide(color: AppColors.brand) : null,
        showCheckmark: false,
        onSelected: onSelected,
      ),
    );
  }
}

/// Die [Trail.topTraits] als Symbole, je mit dem Wort für Bildschirmleser.
class TrailTraitIcons extends StatelessWidget {
  const TrailTraitIcons(this.traits, {super.key, this.size = 18, this.color});

  final List<TrailTrait> traits;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in traits)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Tooltip(
                message: t.label(context.l10n),
                child: Icon(t.icon, size: size, color: color, semanticLabel: t.label(context.l10n)),
              ),
            ),
        ],
      );
}
