import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../l10n/l10n.dart';
import '../../models/trail.dart';

/// Wie stark ein eigener Wert verblasst, solange er noch nicht auf dem
/// Server liegt (#183): gesetzt, sichtbar, aber erkennbar „noch nicht
/// durch". Dieselbe Sprache wie die verblasste unbestätigte Meldung.
const kPendingValueOpacity = 0.5;

/// Die Zeile unter einer eigenen Angabe (S-Grad, Sterne), solange der
/// Beitrag unterwegs ist oder im Ausgangskorb wartet — sonst nichts. Nur
/// unter einer Auswahl, in der ein eigener Wert steht ([hasValue]): Unter
/// leeren Sternen hieße „wird übertragen" nichts.
/// Sagt, WARUM der Wert blass ist; Farbe allein wäre eine Behauptung, die
/// niemand lesen kann.
class PendingValueCaption extends StatelessWidget {
  const PendingValueCaption({super.key, required this.trail, required this.hasValue});
  final Trail trail;
  final bool hasValue;

  @override
  Widget build(BuildContext context) {
    if (!trail.pendingDetails || !hasValue) return const SizedBox.shrink();
    return Text(
      trail.sendingDetails ? context.l10n.sheetValueSending : context.l10n.sheetValueQueued,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.of(context).muted),
    );
  }
}
