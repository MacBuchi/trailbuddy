// Der Sicherheitshinweis (#131, Plan `docs/konzept-onboarding.md` 3.1).
//
// Kopie von PilzBuddys `safety_note.dart` (#110, Stand 0d2a533) mit neuem
// Wortlaut: Dort bestimmt die App keine Pilze, hier sagt sie nicht, ob ein
// Weg befahren werden darf. Dieselbe Form — ein Satz an EINER Stelle, ein
// Dialog beim ersten Start, eine Kachel für die Kurzanleitung.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_colors.dart';
import '../settings.dart';
import '../../l10n/l10n.dart';

/// Der Satz, um den es geht, steht in den ARB-Dateien (`safetyNote`,
/// Überschrift `safetyNoteTitle`; #209).
///
/// **Er steht an EINER Stelle**, weil er sonst an zweien auseinanderläuft:
/// der Dialog beim ersten Start, die Kachel in der Kurzanleitung und die
/// Zeile unter „Über TrailBuddy" sind dieselbe Aussage.
///
/// **Eine Auskunft, kein Haftungsausschluss** (Betreiber, Plan 9.1): erst,
/// was die App tut (zeigen, was du und deine Buddys gefahren sind), dann
/// die Grenze (nicht, ob ein Weg befahren werden darf). Der letzte Satz
/// gilt beiden Richtungen einer Meldung — eine gemeldete Sperre ist so
/// wenig eine amtliche wie das Fehlen einer Meldung eine Freigabe.

/// Hat dieses Gerät den Hinweis schon bestätigt? Gerätelokal
/// (`Settings.safetyNoteSeen`), einmal je Installation.
final safetyNoteSeenProvider = NotifierProvider<RememberedFlag, bool>(
  () => RememberedFlag(
    read: (s) => s.safetyNoteSeen,
    write: (s, v) => s.setSafetyNoteSeen(v),
    label: 'Sicherheitshinweis merken',
  ),
);

/// Die Kachel für dauerhafte Orte (Kurzanleitung).
///
/// Kein Dialog und kein Ausrufezeichen: Wer hier liest, sucht ohnehin
/// eine Erklärung. Auffällig durch die Warnfarbe, unaufdringlich genug,
/// um nicht zur Tapete zu werden. Ein Symbol statt PilzBuddys Emoji —
/// Emojis gibt es in TrailBuddys Oberfläche nicht (Design 6).
class SafetyNoteTile extends StatelessWidget {
  const SafetyNoteTile({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      key: const ValueKey('safety-note-tile'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.map.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_outlined, size: 20, color: palette.warningText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(context.l10n.safetyNote, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

/// Der einmalige Hinweis beim ersten Start.
///
/// **Einmal je Installation**, gerätelokal gemerkt. Ein Hinweis, den man
/// täglich wegklickt, wird zur Tapete; einer, den man einmal bewusst
/// bestätigt, bleibt hängen.
Future<void> showSafetyNoteDialog(BuildContext context) => showDialog<void>(
      context: context,
      // Nicht wegtippbar: Ein Hinweis, der sich durch einen Fehlgriff
      // neben den Dialog schließt, ist nicht gezeigt worden.
      barrierDismissible: false,
      builder: (context) => PopScope(
        // Auch die Zurück-Taste schließt ihn nicht — aus demselben Grund.
        canPop: false,
        child: AlertDialog(
          title: Text(context.l10n.safetyNoteDialogTitle),
          content: Text(context.l10n.safetyNote),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.safetyNoteConfirm),
            ),
          ],
        ),
      ),
    );
