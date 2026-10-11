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
import '../../l10n/l10n.dart';
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
    final l = context.l10n;
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
                  l.mergeMergedFrom(m.name ?? l.mergeUnnamedTrail,
                      m.byMe ? l.mergeByMe : l.mergeByUsers(m.byUsers.map(who).join(', '))),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (m.byMe)
                TextButton(
                  key: ValueKey('trail-unmerge-${m.id}'),
                  onPressed: () => unmergeTrail(context, ref, m),
                  child: Text(l.mergeUnmerge),
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
              label: Text(l.mergeDeclare),
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
  final l = context.l10n;
  try {
    final result = await ref.read(trailsProvider.notifier).mergeInto(duplicate.id, keep.id);
    if (closeSheet) navigator.pop();
    messenger.showSnackBar(SnackBar(
        content: Text('${l.mergeDone(keep.displayName)}'
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
  final l = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l.mergeUnmergeTitle),
      content: Text(l.mergeUnmergeBody(m.name ?? l.mergeUnnamedTrail)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('trail-unmerge-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l.mergeUnmerge),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final fresh = await ref.read(trailsProvider.notifier).unmerge(m.id);
    messenger.showSnackBar(
        SnackBar(content: Text('${l.mergeUnmerged}${fresh ? '' : staleAfterWriteHint}')));
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
    final l = context.l10n;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(l.mergeCandidatesTitle, style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              l.mergeCandidatesIntro(trail.displayName, kMergeNearM.round()),
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
                    subtitle: Text(l.mergeCandidateSubtitle(formatMeters(c.trail.lengthM),
                        (c.share * 100).round(), _contributors(l, c.trail))),
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

String _contributors(AppLocalizations l, Trail t) {
  final n = visibleContributors(t);
  if (t.isOwn) return l.mergeContributorsOwn(n - 1);
  return l.mergeContributorsBuddies(n);
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
    final l = context.l10n;
    final body = l.mergeKeepBody(duplicate.displayName, _keep.displayName);
    return AlertDialog(
      title: Text(l.mergeKeepTitle),
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
                      subtitle: Text(_contributors(l, t)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(buddiesSee ? '$body ${l.mergeKeepBuddies}' : body),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('merge-confirm'),
          onPressed: () => Navigator.of(context).pop(_keep),
          child: Text(l.mergeConfirm),
        ),
      ],
    );
  }
}
