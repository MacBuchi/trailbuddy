// „Sind das dieselben?" (#107 Schritt 3, Konzept 6.1): der Vorschlag im
// Trail-Blatt und auf der Seite im Profil, mit vier Antworten —
// „Derselbe" (zusammenführen), „Verschieden" (merken, der Vorschlag kommt
// nicht wieder), „Beide ansehen" (beide Linien auf der Karte) und, wenn
// meine Linie die andere ganz enthält, „Auf gemeinsamen Teil kürzen"
// (das Zerlege-Blatt mit meiner Aufzeichnung). Welche Paare es gibt,
// rechnet `merge_proposals.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart' show StatefulNavigationShell;

import '../../core/errors.dart';
import '../../core/read_after_write.dart';
import '../../core/router_branches.dart';
import '../friends/buddy_alias.dart';
import '../rides/ride_split_sheet.dart' show SplitRequest, mapSplitRequestProvider;
import 'gpx.dart';
import 'merge_proposals.dart';
import 'trail_merge_sheet.dart' show mergePair;
import 'trail_providers.dart';

/// Alle Vorschläge zum angezeigten Netz.
final mergeProposalsProvider = Provider<List<MergeProposal>>((ref) {
  final trails = ref.watch(trailsProvider).valueOrNull;
  if (trails == null) return const [];
  return mergeProposals(trails, ref.watch(trailMergeRowsProvider));
});

/// Die Vorschläge, an denen [trailId] beteiligt ist — für sein Blatt.
final mergeProposalsForProvider = Provider.family<List<MergeProposal>, String>((ref, trailId) => [
      for (final p in ref.watch(mergeProposalsProvider))
        if (p.involves(trailId)) p,
    ]);

/// „Beide ansehen": Die Karte passt sich auf die beiden ein, hebt sie
/// hervor und sagt es oben, mit X zum Beenden.
final mapComparePairProvider = StateProvider<({String duplicate, String target})?>((ref) => null);

String _quoted(String name) => '„$name"';

/// Der Vorschlag als Karte. [fromSheet]: steht im Trail-Blatt, das bei
/// „Beide ansehen", „Kürzen" und nach dem Zusammenführen zugeht.
class MergeProposalCard extends ConsumerStatefulWidget {
  const MergeProposalCard({super.key, required this.proposal, this.fromSheet = false});

  final MergeProposal proposal;
  final bool fromSheet;

  @override
  ConsumerState<MergeProposalCard> createState() => _MergeProposalCardState();
}

class _MergeProposalCardState extends ConsumerState<MergeProposalCard> {
  bool _busy = false;

  MergeProposal get p => widget.proposal;

  String _lead() {
    final names = ref.watch(buddyNamesViewProvider);
    String who(String userId) {
      final d = [...p.duplicate.details, ...p.target.details].where((d) => d.userId == userId).firstOrNull;
      return names.of(userId, d?.username);
    }

    final pair = '${_quoted(p.duplicate.displayName)} und ${_quoted(p.target.displayName)}';
    return switch (p.source) {
      ProposalSource.declared => '${p.byUsers.map(who).join(', ')} '
          '${p.byUsers.length == 1 ? 'hält' : 'halten'} $pair für denselben Trail.',
      ProposalSource.overlap => '$pair liegen fast aufeinander — '
          '${(p.share * 100).round()} % der kürzeren Linie nebeneinander.',
    };
  }

  Future<void> _same() async {
    setState(() => _busy = true);
    // Vorbelegt: wohin der Buddy es gelegt hat; aus dem Abgleich der mit
    // mehr Beiträgen, sonst der ältere (`defaultKeep`, schon im Vorschlag).
    await mergePair(context, ref, p.duplicate, p.target, preset: p.target, closeSheet: widget.fromSheet);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _distinct() async {
    final messenger = ScaffoldMessenger.of(context);
    final a = p.duplicate.id, b = p.target.id;
    // VOR dem Schreiben geholt: Danach ist der Vorschlag weg, diese Karte
    // abgebaut — und „Rückgängig" griffe auf ein totes `ref`.
    final notifier = ref.read(trailsProvider.notifier);
    setState(() => _busy = true);
    try {
      final fresh = await notifier.markDistinct(a, b);
      messenger.showSnackBar(SnackBar(
        content: Text('Gemerkt: verschiedene Trails${fresh ? '' : staleAfterWriteHint}'),
        action: SnackBarAction(
          label: 'Rückgängig',
          onPressed: () async {
            try {
              await notifier.unmarkDistinct(a, b);
            } catch (e, st) {
              logError('Verschieden zurücknehmen', e, st);
              messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
            }
          },
        ),
      ));
    } on MergeRejectedException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } catch (e, st) {
      logError('Verschieden merken', e, st);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Erst das Blatt zu, dann der Reiter, dann der Wunsch — wie „Zum
  /// Trailkopf" (PilzBuddy #345).
  void _toMap(void Function() wish) {
    final shell = StatefulNavigationShell.maybeOf(context);
    if (widget.fromSheet) Navigator.of(context).pop();
    shell?.goBranch(kMapBranchIndex);
    wish();
  }

  void _compare() => _toMap(() => ref.read(mapComparePairProvider.notifier).state =
      (duplicate: p.duplicate.id, target: p.target.id));

  /// „Auf gemeinsamen Teil kürzen": meine lange Aufzeichnung ins
  /// Zerlege-Blatt — der Teil, der auf dem anderen liegt, steht dort als
  /// bekannt und geht als Beleg an ihn; danach bietet das Blatt an, die
  /// lange Fassung zu löschen.
  void _trim() {
    final own = p.trimmable!;
    final rec = own.recordings.where((r) => r.userId == own.myId).toList()
      ..sort((a, b) => b.quality.compareTo(a.quality));
    final r = rec.first;
    final pts = r.reversed ? r.points.reversed.toList() : r.points;
    final ele = r.ele == null ? null : (r.reversed ? r.ele!.reversed.toList() : r.ele!);
    final request = SplitRequest(
      track: GpxTrack(
        name: own.displayName,
        points: [for (var i = 0; i < pts.length; i++) TrackPoint(pts[i].latitude, pts[i].longitude, ele: ele?[i])],
      ),
      source: r.source,
      replacesTrailId: own.id,
    );
    _toMap(() => ref.read(mapSplitRequestProvider.notifier).state = request);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: ValueKey('merge-proposal-${p.key}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              const Icon(Icons.merge_type, size: 18),
              const SizedBox(width: 6),
              Text('Sind das dieselben?', style: theme.textTheme.titleSmall),
            ]),
            const SizedBox(height: 4),
            Text(_lead(), style: theme.textTheme.bodySmall),
            Wrap(
              spacing: 4,
              children: [
                FilledButton.tonal(
                  key: ValueKey('merge-proposal-same-${p.key}'),
                  onPressed: _busy ? null : _same,
                  child: const Text('Derselbe'),
                ),
                TextButton(
                  key: ValueKey('merge-proposal-distinct-${p.key}'),
                  onPressed: _busy ? null : _distinct,
                  child: const Text('Verschieden'),
                ),
                TextButton(
                  key: ValueKey('merge-proposal-compare-${p.key}'),
                  onPressed: _busy ? null : _compare,
                  child: const Text('Beide ansehen'),
                ),
                if (p.trimmable != null)
                  TextButton(
                    key: ValueKey('merge-proposal-trim-${p.key}'),
                    onPressed: _busy ? null : _trim,
                    child: const Text('Auf gemeinsamen Teil kürzen'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Die Seite im Profil: alle Vorschläge untereinander.
class MergeProposalsScreen extends ConsumerWidget {
  const MergeProposalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proposals = ref.watch(mergeProposalsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sind das dieselben?')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            'Trails, die fast aufeinander liegen — ein Buddy hält sie für denselben, '
            'oder der Abgleich hat sie nebeneinander gefunden. „Verschieden" merkt '
            'sich die App, der Vorschlag kommt dann nicht wieder.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          if (proposals.isEmpty)
            const Padding(
              key: ValueKey('merge-proposals-empty'),
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Nichts zu prüfen — keine doppelten Trails in Sicht.'),
            ),
          for (final p in proposals) MergeProposalCard(proposal: p),
        ],
      ),
    );
  }
}
