import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../l10n/l10n.dart';
import 'grade_shield.dart';

/// Die Singletrail-Skala (STS), S0 bis S5: die in DACH übliche Angabe,
/// wie schwierig ein Trail FAHRTECHNISCH ist — bei guten Bedingungen,
/// nicht, wie anstrengend er ist. Die Texte sind eigene Kurzfassungen,
/// keine Zitate.
///
/// EINE Quelle für alle Stellen, die einen Grad zeigen oder abfragen:
/// Auswahl im Beitrag, Chips im Blatt, Erklärblatt. Zwei Fassungen der
/// Beschreibung wären zwei Meinungen darüber, was S2 heißt.
class SingletrailGrade {
  const SingletrailGrade(this.value);

  final int value;

  /// Ein paar Wörter für Auswahllisten: „S2 · größere Wurzeln, Stufen"
  /// (#209: aus den ARB-Dateien).
  String short(AppLocalizations l) => switch (value) {
        0 => l.scaleS0Short,
        1 => l.scaleS1Short,
        2 => l.scaleS2Short,
        3 => l.scaleS3Short,
        4 => l.scaleS4Short,
        5 => l.scaleS5Short,
        _ => throw StateError('Kein S-Grad: $value'),
      };

  /// Ein bis zwei Sätze für das Erklärblatt.
  String description(AppLocalizations l) => switch (value) {
        0 => l.scaleS0Description,
        1 => l.scaleS1Description,
        2 => l.scaleS2Description,
        3 => l.scaleS3Description,
        4 => l.scaleS4Description,
        5 => l.scaleS5Description,
        _ => throw StateError('Kein S-Grad: $value'),
      };

  String get label => 'S$value';
}

const kSingletrailScale = <SingletrailGrade>[
  SingletrailGrade(0),
  SingletrailGrade(1),
  SingletrailGrade(2),
  SingletrailGrade(3),
  SingletrailGrade(4),
  SingletrailGrade(5),
];

SingletrailGrade singletrailGrade(int value) =>
    kSingletrailScale.firstWhere((g) => g.value == value);

/// Das Erklärblatt. [highlight] hebt eine Stufe hervor (die, die gerade
/// gewählt ist oder gezeigt wird).
Future<void> showSingletrailScaleSheet(BuildContext context, {int? highlight}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SingletrailScaleSheet(highlight: highlight),
  );
}

class SingletrailScaleSheet extends StatelessWidget {
  const SingletrailScaleSheet({super.key, this.highlight});

  final int? highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.scaleSheetTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              l.scaleSheetIntro,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            for (final g in kSingletrailScale)
              Container(
                key: ValueKey('sts-${g.value}'),
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: g.value == highlight
                      ? AppPalette.of(context).map.mine.withValues(alpha: 0.12)
                      : null,
                  border: Border.all(
                      color: g.value == highlight
                          ? AppPalette.of(context).map.mine
                          : theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Die Form des Schilds, damit man sie hier lernt.
                    // Feste Spalte, damit die Texte fluchten; das breiteste
                    // Schild (S5) schrumpft notfalls, statt überzulaufen.
                    SizedBox(
                      width: 76,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: GradeShield(g.value, fontSize: 13),
                        ),
                      ),
                    ),
                    Expanded(child: Text(g.description(l))),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Text(
              l.scaleSheetFooter,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Der kleine Knopf „?", der das Erklärblatt öffnet — neben jeder Stelle,
/// an der man einen Grad angibt.
class SingletrailScaleButton extends StatelessWidget {
  const SingletrailScaleButton({super.key, this.highlight});

  final int? highlight;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: context.l10n.scaleExplain,
        icon: const Icon(Icons.help_outline),
        onPressed: () => showSingletrailScaleSheet(context, highlight: highlight),
      );
}
