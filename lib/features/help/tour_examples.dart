// Beispiele für die Reiter-Touren (#136, Plan `docs/konzept-onboarding.md`
// 3.5; Vorlage PilzBuddys `tour_examples.dart`) — was ein Konto ohne Trails
// oder Buddys während der Tour statt der leeren Liste sieht.
//
// Drei Regeln, und jede hat einen Test:
//
// - **Gezeichnet, nie gespeichert.** Kein `Trail`, keine `TrailRecording`,
//   keine `Friendship`, kein Provider: Die Beispiele sind Widgets aus
//   festen Texten. Ein Beispiel-Trail als Modell käme sonst in die Summe
//   im Kopf der Liste, in den Filter und auf die Karte.
// - **Immer „Beispiel"**, als Schild UND im Namen, auch für den
//   Bildschirmleser — wer nach der Tour „Buchenhang" sucht, hat sonst
//   etwas gesehen, das es nicht gibt.
// - **Nur während der Tour und nur, wo Echtes fehlt**
//   (`coachExamplesProvider`). Die Anker sind dieselben wie an der echten
//   Zeile und im echten Blatt.
import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/letter_avatar.dart';
import '../coach/coach.dart';
import '../trails/grade_shield.dart';
import 'map_tour.dart' show SheetCoach;
import 'tab_tours.dart';

const kExampleTrailKey = Key('tour-example-trail');
const kExampleTrailSheetKey = Key('tour-example-trail-sheet');
const kExampleBuddyKey = Key('tour-example-buddy');

/// Das Schild „Beispiel" (Design 12: `tertiaryContainer`).
class TourExampleBadge extends StatelessWidget {
  const TourExampleBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('tour-example-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('Beispiel',
          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onTertiaryContainer)),
    );
  }
}

// Ein Tipp tut nichts: Während der Tour schluckt die Überlagerung ihn
// ohnehin, und danach ist das Beispiel weg. Ein `null` machte die Knöpfe
// grau — dann sähe das Beispiel anders aus als das Echte.
void _nothing() {}

/// Die Beispielzeile im Reiter „Trails" — gebaut wie `_TrailTile`:
/// Streifen S1, Name, Zahlen in Mono, „MEIN", rechts das Schild.
class ExampleTrailTile extends StatelessWidget {
  const ExampleTrailTile({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: CoachAnchor(
        id: TrailsCoach.row,
        child: Card(
          key: kExampleTrailKey,
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14), side: BorderSide(color: palette.line)),
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            horizontalTitleGap: 12,
            minLeadingWidth: 4,
            leading: CoachAnchor(
              id: TrailsCoach.rowOwn,
              child: Container(
                width: 4,
                height: 40,
                decoration: BoxDecoration(color: palette.grade.s1, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            title: Text('Beispiel: Buchenhang',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            subtitle: Row(
              children: [
                Flexible(
                  child: Text('1,8 km · ↓ 210 Hm · MEIN',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.numbers(theme.textTheme.bodySmall).copyWith(color: palette.muted)),
                ),
                const SizedBox(width: 6),
                const TourExampleBadge(),
              ],
            ),
            trailing: const GradeShield(1),
            onTap: _nothing,
          ),
        ),
      ),
    );
  }
}

/// Öffnet das Beispiel-Blatt; gibt zurück, wie es zu schließen ist —
/// die Form einer Tour-Szene.
VoidCallback showExampleTrailSheet(BuildContext context) {
  final navigator = Navigator.of(context);
  var open = true;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _ExampleTrailSheet(),
  ).whenComplete(() => open = false);
  return () {
    if (open) navigator.pop();
  };
}

class _ExampleTrailSheet extends StatelessWidget {
  const _ExampleTrailSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: palette.muted);
    Widget tile(String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: palette.surface2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: muted),
                Text(value, style: AppFonts.numbers(theme.textTheme.titleLarge)),
              ],
            ),
          ),
        );
    return SafeArea(
      child: SingleChildScrollView(
        key: kExampleTrailSheetKey,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text('BEISPIEL: BUCHENHANG',
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 8),
                      const TourExampleBadge(),
                    ],
                  ),
                ),
                // Wie im echten Blatt (#224): Anfahrt und Schließen im Kopf.
                const CoachAnchor(
                  id: SheetCoach.navigate,
                  child: IconButton(
                    tooltip: 'Anfahrt',
                    onPressed: _nothing,
                    icon: Icon(Icons.directions_outlined),
                  ),
                ),
                const IconButton(
                  tooltip: 'Schließen',
                  onPressed: _nothing,
                  icon: Icon(Icons.close),
                ),
              ],
            ),
            Text('So sieht ein Trail aus, sobald du einen importiert oder '
                'aufgezeichnet hast.', style: muted),
            const SizedBox(height: 12),
            CoachAnchor(
              id: SheetCoach.metrics,
              child: Row(
                children: [
                  tile('LÄNGE', '1,8 km'),
                  const SizedBox(width: 8),
                  tile('HÖHE', '↓210'),
                  const SizedBox(width: 8),
                  tile('S-GRAD', 'S1'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            CoachAnchor(
              id: SheetCoach.ownGrade,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Deine Einschätzung', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (var g = 0; g <= 5; g++)
                        ChoiceChip(label: Text('S$g'), selected: g == 1, onSelected: (_) => _nothing()),
                    ],
                  ),
                ],
              ),
            ),
            const CoachAnchor(
              id: SheetCoach.contribution,
              child: TextButton(onPressed: _nothing, child: Text('Mein Beitrag')),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: CoachAnchor(
                    id: SheetCoach.addNote,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: _nothing,
                      icon: const Icon(Icons.add_comment_outlined),
                      label: const Text('Hinweis schreiben'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CoachAnchor(
                    id: SheetCoach.report,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: _nothing,
                      icon: const Icon(Icons.flag_outlined),
                      label: const Text('Melden'),
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: CoachAnchor(
                id: SheetCoach.export,
                child: TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: _nothing,
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Als GPX exportieren'),
                ),
              ),
            ),
            const SizedBox(height: 8),
            CoachAnchor(
              id: SheetCoach.trailHead,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _nothing,
                icon: const Icon(Icons.route_outlined),
                label: const Text('Zum Trailkopf'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Der Beispiel-Buddy unter „Meine Buddys" — gebaut wie `_BuddyRow`.
class ExampleBuddyTile extends StatelessWidget {
  const ExampleBuddyTile({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: AppPalette.of(context).muted);
    return CoachAnchor(
      id: BuddysCoach.row,
      child: Padding(
        key: kExampleBuddyKey,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            const LetterAvatar(name: 'Mira', colorKey: 'tour-example', size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Beispiel: Mira',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Row(
                    children: [
                      Text('3 gemeinsam', style: muted),
                      const SizedBox(width: 6),
                      const TourExampleBadge(),
                    ],
                  ),
                ],
              ),
            ),
            const CoachAnchor(
              id: BuddysCoach.alias,
              child: IconButton(
                tooltip: 'Alias vergeben',
                icon: Icon(Icons.edit_outlined),
                onPressed: _nothing,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
