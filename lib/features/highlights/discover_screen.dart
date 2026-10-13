// „Entdecken" (#135; Vorlage PilzBuddys `discover_screen.dart`, #596): alle
// Funktionen und Tipps, nach Reiter gruppiert.
//
// **Die Seite, die bleibt.** Das Blatt nach einem Update ist einmal da und
// dann weg; hier steht alles dauerhaft — auch die Tipps, die nie ins Blatt
// kommen.
//
// **Der Neu-Punkt wird beim ÖFFNEN gelöscht, gezeigt wird er trotzdem.**
// Die Menge wird beim ersten Aufbau festgehalten und erst danach als
// gesehen gemerkt — sonst verschwände der Punkt, bevor man ihn sieht.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../l10n/l10n.dart';
import '../coach/coach.dart';
import 'feature_highlights.dart';
import 'highlight_art.dart';
import 'highlight_demos.dart';
import 'highlight_sheet.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  late final Set<String> _unseen = {
    for (final h in kFeatureHighlights)
      if (!ref.read(seenHighlightIdsProvider).contains(h.id)) h.id,
  };

  @override
  void initState() {
    super.initState();
    // Nach dem Bild: Ein Provider darf während `build` nicht verändert werden.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(seenHighlightIdsProvider.notifier).markSeen(kFeatureHighlights.map((h) => h.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.discoverTitle)),
      body: ListView(
        key: const ValueKey('discover-list'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            context.l10n.discoverLead,
            style: theme.textTheme.bodyMedium?.copyWith(color: AppPalette.of(context).muted),
          ),
          for (final tab in HighlightTab.values) ..._section(context, tab),
        ],
      ),
    );
  }

  List<Widget> _section(BuildContext context, HighlightTab tab) {
    // Highlights vor Tipps, sonst die Reihenfolge der Liste.
    final entries = [
      ...kFeatureHighlights.where((h) => h.tab == tab && h.kind == HighlightKind.highlight),
      ...kFeatureHighlights.where((h) => h.tab == tab && h.kind == HighlightKind.tip),
    ];
    if (entries.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 4),
        child: Text(tab.label(context.l10n).toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppPalette.of(context).muted)),
      ),
      for (final h in entries)
        _Entry(
          key: ValueKey('discover-${h.id}'),
          highlight: h,
          unseen: _unseen.contains(h.id),
          onTry: () => context.go(h.target),
          onShow: switch (highlightDemos(context.l10n)[h.id]) {
            null => null,
            final demo => () => startHighlightDemo(GoRouter.of(context), ref.read(coachProvider.notifier), demo),
          },
        ),
    ];
  }
}

class _Entry extends StatelessWidget {
  const _Entry({super.key, required this.highlight, required this.unseen, required this.onTry, this.onShow});

  final FeatureHighlight highlight;
  final bool unseen;
  final VoidCallback onTry;

  /// „Zeig es mir" — die Vorführung (`highlight_demos.dart`).
  final VoidCallback? onShow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTip = highlight.kind == HighlightKind.tip;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HighlightArt(highlight: highlight, size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(highlight.title(context.l10n), style: theme.textTheme.titleSmall),
                          if (isTip) _Badge(context.l10n.discoverBadgeTip),
                          if (unseen) _Badge(context.l10n.discoverBadgeNew, strong: true),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(highlight.text(context.l10n), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              children: [
                if (highlightDemos(context.l10n)[highlight.id] case final demo?)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: GesturePreview(gesture: demo.gesture, size: 40),
                  ),
                // `Wrap`, keine `Row`: Zwei deutsche Beschriftungen passen bei
                // 360 px nicht nebeneinander (PilzBuddy: 162 px Überlauf).
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 4,
                    children: [
                      TextButton(onPressed: onTry, child: Text(context.l10n.discoverTry)),
                      if (onShow != null)
                        FilledButton.tonalIcon(
                          key: ValueKey('show-${highlight.id}'),
                          onPressed: onShow,
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: Text(context.l10n.discoverShowMe),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

/// „Tipp" gedämpft, „Neu" in der Marke — Lime heißt „für dich".
class _Badge extends StatelessWidget {
  const _Badge(this.label, {this.strong = false});

  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: strong ? AppColors.brand : p.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: strong ? AppColors.onBrand : p.muted)),
    );
  }
}
