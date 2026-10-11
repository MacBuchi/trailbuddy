// „Ist ein Duplikat von …" im Trail-Blatt (#107 Schritt 2, Konzept 6.1):
// den Partner wählen, festlegen, welcher bleibt, und sehen, was bei mir
// schon zusammengeführt ist — mit „Trennen" für die eigenen Zuordnungen.
//
// Kein Ausgangskorb, wie beim Löschen: Ohne Netz scheitert es sichtbar.
// Zusammenführen zieht Aufzeichnungen um und verändert, was Buddys sehen;
// ein Auftrag, der Tage später zuschlägt, wäre schlimmer als eine Meldung.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/geo.dart' show formatMeters;
import '../../core/read_after_write.dart';
import '../../models/trail.dart';
import '../friends/buddy_alias.dart';
import 'merge_proposal_card.dart';
import 'trail_merge_candidates.dart';
import 'trail_providers.dart';

/// Die Partner für „Ist ein Duplikat von …" — neu gerechnet, wenn sich das
/// Netz ändert, nicht bei jedem Aufbau des Blatts.
final mergeCandidatesProvider = Provider.family<List<MergeCandidate>, String>((ref, trailId) {
  final trail = ref.watch(trailByIdProvider(trailId));
  final all = ref.watch(trailsProvider).valueOrNull;
  if (trail == null || all == null) return const [];
  return mergeCandidates(trail, all);
});

/// Wie der Name eines Trails in einem Satz steht.
String _quoted(String name) => '„$name"';

/// Der Abschnitt im Trail-Blatt: die Duplikate, die bei mir unter diesem
/// Trail stehen, und der Knopf „Duplikat …", wenn ein Trail nah genug
/// daneben liegt. Ohne beides: nichts.
class TrailMergeSection extends ConsumerWidget {
  const TrailMergeSection({super.key, required this.trail});
  final Trail trail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (trail.pending) return const SizedBox.shrink();
    final candidates = ref.watch(mergeCandidatesProvider(trail.id));
    final proposals = ref.watch(mergeProposalsForProvider(trail.id));
    final names = ref.watch(buddyNamesViewProvider);
    final theme = Theme.of(context);
    String who(String userId) => names.of(
        userId, trail.details.where((d) => d.userId == userId).firstOrNull?.username);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // „Sind das dieselben?" (#107 Schritt 3) — zuoberst, es ist eine Frage.
        for (final p in proposals) MergeProposalCard(proposal: p, fromSheet: true),
        for (final m in trail.mergedFrom)
          Row(
            key: ValueKey('trail-merged-${m.id}'),
            children: [
              Icon(Icons.merge_type, size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Zusammengeführt: ${_quoted(m.name ?? 'Trail ohne Namen')} — '
                  '${m.byMe ? 'von dir' : 'von ${m.byUsers.map(who).join(', ')}'}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (m.byMe)
                TextButton(
                  key: ValueKey('trail-unmerge-${m.id}'),
                  onPressed: () => unmergeTrail(context, ref, m),
                  child: const Text('Trennen'),
                ),
            ],
          ),
        if (candidates.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('trail-merge'),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => declareDuplicate(context, ref, trail),
              icon: const Icon(Icons.merge_type, size: 18),
              label: const Text('Ist ein Duplikat …'),
            ),
          ),
      ],
    );
  }
}

/// „Ist ein Duplikat …": Partner wählen, dann festlegen, welcher bleibt,
/// dann zusammenführen.
Future<void> declareDuplicate(BuildContext context, WidgetRef ref, Trail trail) async {
  final candidates = ref.read(mergeCandidatesProvider(trail.id));
  if (candidates.isEmpty) return;
  final other = await showModalBottomSheet<Trail>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _CandidateList(trail: trail, candidates: candidates),
  );
  if (other == null || !context.mounted) return;
  await mergePair(context, ref, trail, other, closeSheet: true);
}

/// Zwei Trails zusammenführen: erst „Welcher bleibt?" ([preset] oder
/// [defaultKeep]), dann `merge_own_into`. [closeSheet]: Der Aufruf kommt
/// aus dem Trail-Blatt, das danach zugeht — wie nach dem Löschen; stand es
/// für das Duplikat, gibt es den Trail bei mir nicht mehr. Gibt zurück, ob
/// zusammengeführt wurde.
Future<bool> mergePair(BuildContext context, WidgetRef ref, Trail a, Trail b,
    {Trail? preset, bool closeSheet = false}) async {
  final keep = await showDialog<Trail>(
    context: context,
    builder: (_) => _KeepDialog(a: a, b: b, preset: preset),
  );
  if (keep == null || !context.mounted) return false;
  final duplicate = keep.id == a.id ? b : a;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  try {
    final result = await ref.read(trailsProvider.notifier).mergeInto(duplicate.id, keep.id);
    if (closeSheet) navigator.pop();
    messenger.showSnackBar(SnackBar(
        content: Text('Zusammengeführt — ${_quoted(keep.displayName)} bleibt'
            '${result.fresh ? '' : staleAfterWriteHint}')));
    return true;
  } on MergeRejectedException catch (e) {
    // Kein Fehlerbericht: Der Server hat entschieden, nichts ist kaputt.
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
  } catch (e, st) {
    logError('Duplikat zusammenführen', e, st);
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
  return false;
}

/// „Trennen": die eigene Zuordnung lösen.
Future<void> unmergeTrail(BuildContext context, WidgetRef ref, MergedTrail m) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Wieder trennen?'),
      content: Text('${_quoted(m.name ?? 'Trail ohne Namen')} erscheint wieder als eigener '
          'Trail, wo jemand anderes etwas daran hat. Deine eigenen Aufzeichnungen, '
          'dein Beitrag und deine Hinweise bleiben hier.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const ValueKey('trail-unmerge-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Trennen'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final fresh = await ref.read(trailsProvider.notifier).unmerge(m.id);
    messenger.showSnackBar(
        SnackBar(content: Text('Getrennt${fresh ? '' : staleAfterWriteHint}')));
  } catch (e, st) {
    logError('Zusammenführung lösen', e, st);
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}

/// Die Trails, die nah genug daneben liegen, der höchste Anteil zuerst.
class _CandidateList extends StatelessWidget {
  const _CandidateList({required this.trail, required this.candidates});
  final Trail trail;
  final List<MergeCandidate> candidates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('Derselbe Trail wie …', style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Hier stehen Trails, die grob neben ${_quoted(trail.displayName)} liegen — '
              'mindestens die Hälfte der kürzeren Linie höchstens '
              '${kMergeNearM.round()} m daneben.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in candidates)
                  ListTile(
                    key: ValueKey('merge-candidate-${c.trail.id}'),
                    title: Text(c.trail.displayName),
                    subtitle: Text('${formatMeters(c.trail.lengthM)} · '
                        '${(c.share * 100).round()} % liegen nebeneinander · '
                        '${_contributors(c.trail)}'),
                    onTap: () => Navigator.of(context).pop(c.trail),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _contributors(Trail t) {
  final n = visibleContributors(t);
  if (t.isOwn) return n == 1 ? 'nur deiner' : 'deiner und ${n - 1} weitere';
  return n == 1 ? '1 Buddy' : '$n Buddys';
}

/// „Welcher bleibt?" — vorbelegt mit [preset], sonst [defaultKeep].
class _KeepDialog extends StatefulWidget {
  const _KeepDialog({required this.a, required this.b, this.preset});
  final Trail a;
  final Trail b;
  final Trail? preset;

  @override
  State<_KeepDialog> createState() => _KeepDialogState();
}

class _KeepDialogState extends State<_KeepDialog> {
  late Trail _keep = widget.preset ?? defaultKeep(widget.a, widget.b);

  @override
  Widget build(BuildContext context) {
    final duplicate = _keep.id == widget.a.id ? widget.b : widget.a;
    final buddiesSee = duplicate.recordings.any((r) => r.userId != duplicate.myId);
    return AlertDialog(
      title: const Text('Welcher Trail bleibt?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<String>(
              groupValue: _keep.id,
              onChanged: (id) => setState(() => _keep = id == widget.a.id ? widget.a : widget.b),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final t in [widget.a, widget.b])
                    RadioListTile<String>(
                      key: ValueKey('merge-keep-${t.id}'),
                      value: t.id,
                      contentPadding: EdgeInsets.zero,
                      title: Text(t.displayName),
                      subtitle: Text(_contributors(t)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Deine Aufzeichnungen, dein Beitrag, deine Hinweise und Meldungen ziehen von '
              '${_quoted(duplicate.displayName)} nach ${_quoted(_keep.displayName)}; '
              'Name und Einschätzung von ${_quoted(_keep.displayName)} gelten, leere Felder '
              'füllt das Duplikat. '
              '${buddiesSee ? 'Buddys, die beide sehen und am Duplikat nichts haben, sehen es '
                  'ebenfalls darunter; wer selbst etwas daran hat, entscheidet selbst.' : ''}',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const ValueKey('merge-confirm'),
          onPressed: () => Navigator.of(context).pop(_keep),
          child: const Text('Zusammenführen'),
        ),
      ],
    );
  }
}
