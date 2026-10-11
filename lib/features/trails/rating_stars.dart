import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../l10n/l10n.dart';
import '../../models/trail.dart';

/// Die Sterne einer Bewertung: [value] volle von [kRatingMax]. [faded]
/// zeigt die verblassten Sterne eines eigenen, noch nicht bewerteten
/// Trails (Rework E4) — oder eines unbestätigten Werts.
class RatingStars extends StatelessWidget {
  const RatingStars(this.value, {super.key, this.size = 16, this.faded = false});

  final int? value;
  final double size;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final full = value ?? 0;
    final color = faded ? palette.muted.withValues(alpha: 0.5) : palette.accentText;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= kRatingMax; i++)
          Icon(i <= full ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size, color: color),
      ],
    );
  }
}

/// Fünf Sterne zum Antippen; ein Tipp auf den gewählten nimmt ihn zurück.
/// Die Schlüssel heißen `<keyPrefix>-<n>`.
class RatingPicker extends StatelessWidget {
  const RatingPicker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.keyPrefix,
    this.size = 28,
    this.faded = false,
  });

  final int? value;
  final ValueChanged<int?>? onChanged;
  final String keyPrefix;
  final double size;

  /// Verblasst: vorbelegt, noch nicht bestätigt.
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = faded ? palette.muted : palette.accentText;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= kRatingMax; i++)
          IconButton(
            key: ValueKey('$keyPrefix-$i'),
            visualDensity: VisualDensity.compact,
            tooltip: context.l10n.ratingStarTooltip(i, kRatingMax),
            onPressed: onChanged == null ? null : () => onChanged!(value == i ? null : i),
            icon: Icon(
              value != null && i <= value! ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: color,
            ),
          ),
      ],
    );
  }
}
