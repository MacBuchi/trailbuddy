// Das Blatt nach einem Update (#135; Kopie von PilzBuddys
// `highlight_sheet.dart`, #596, mit TrailBuddys Wörtern und Farben).
//
// **Eine Seite, alle Neuheiten untereinander.** Stehen alle drei auf einem
// Blick, ist nach dem Antippen einer Zeile nichts verloren (PilzBuddy hat
// das Blättern in 1.204.1 abgeschafft, nachdem Nutzer den Rest verloren).
//
// **Gemerkt wird VOR dem Zeigen.** Ein Blatt, das der Prozess-Kill oder ein
// Wegwischen mitten im Lesen beendet, käme sonst bei jedem Start wieder.
// Verpasst ist nichts: „Entdecken" hat alles.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/app_info.dart';
import '../../core/errors.dart';
import '../../core/settings.dart';
import '../../core/widgets/sheet_close_button.dart';
import '../../l10n/l10n.dart';
import '../coach/coach.dart';
import '../help/map_tour.dart';
import '../rides/ride_providers.dart' show rideProvider;
import 'feature_highlights.dart';
import 'highlight_art.dart';
import 'highlight_demos.dart';

/// Welche Einträge schon angesehen wurden — der Neu-Punkt in „Entdecken".
class SeenHighlightIds extends Notifier<Set<String>> {
  @override
  Set<String> build() => ref.read(settingsProvider).seenHighlightIds;

  void markSeen(Iterable<String> ids) {
    final next = {...state, ...ids};
    if (next.length == state.length) return;
    state = next;
    unawaited(ref
        .read(settingsProvider)
        .setSeenHighlightIds(next)
        .catchError((Object e, StackTrace s) => logError('Neuheiten gesehen merken', e, s)));
  }
}

final seenHighlightIdsProvider = NotifierProvider<SeenHighlightIds, Set<String>>(SeenHighlightIds.new);

/// Wie viele Einträge in „Entdecken" noch nicht angesehen sind.
final unseenHighlightCountProvider = Provider<int>((ref) {
  final seen = ref.watch(seenHighlightIdsProvider);
  return kFeatureHighlights.where((h) => !seen.contains(h.id)).length;
});

/// Beim Start der Karte: entscheiden, merken, gegebenenfalls zeigen.
///
/// [mayShow] ist `false`, wenn in diesem Start schon etwas anderes über der
/// Karte liegt (Sicherheitshinweis, Karten-Tour). Gerechnet wird trotzdem:
/// Eine frische Installation muss ihre Version schon beim ERSTEN Start
/// merken, sonst hielte sie sich nach der Tour für einen Bestandsnutzer.
Future<void> maybeShowHighlights(BuildContext context, WidgetRef ref, {required bool mayShow}) async {
  final settings = ref.read(settingsProvider);
  final String current;
  try {
    current = await ref.read(appVersionProvider.future);
  } catch (e, s) {
    logError('Neuheiten: Version lesen', e, s);
    return;
  }
  if (!context.mounted) return;
  final plan = planHighlights(
    current: current,
    seenVersion: settings.highlightsSeenVersion,
    mapTourSeen: ref.read(mapTourSeenProvider),
  );
  switch (plan) {
    case HighlightNothing():
      return;
    case HighlightRecord(:final version):
      await _record(settings, version);
    case HighlightShow():
      // Nicht zeigen heißt hier auch nicht merken: Der Rückblick wartet auf
      // den nächsten ruhigen Start. Eine laufende Fahrt zählt wie ein
      // Overlay — wer im Wald die App öffnet, will die Karte.
      if (!mayShow || ref.read(rideProvider) != null || ref.read(coachProvider.notifier).busy) return;
      await _record(settings, plan.version);
      if (!context.mounted) return;
      ref.read(seenHighlightIdsProvider.notifier).markSeen(plan.pages.map((h) => h.id));
      await showHighlightSheet(context, plan);
  }
}

Future<void> _record(Settings settings, String version) => settings
    .setHighlightsSeenVersion(version)
    .catchError((Object e, StackTrace s) => logError('Neuheiten-Stand merken', e, s));

Future<void> showHighlightSheet(BuildContext context, HighlightShow plan) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => HighlightSheet(plan: plan),
    );

class HighlightSheet extends ConsumerWidget {
  const HighlightSheet({super.key, required this.plan});

  final HighlightShow plan;

  /// Erst den Router greifen, dann schließen: Danach ist der Kontext des
  /// Blatts nicht mehr eingehängt.
  static void _go(BuildContext context, String location) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(location);
  }

  /// Eine Zeile führt VOR, nicht nur hin.
  static void _show(BuildContext context, WidgetRef ref, FeatureHighlight h) {
    final demo = highlightDemos(context.l10n)[h.id];
    if (demo == null) {
      _go(context, h.target);
      return;
    }
    final router = GoRouter.of(context);
    final coach = ref.read(coachProvider.notifier);
    Navigator.of(context).pop();
    unawaited(startHighlightDemo(router, coach, demo));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.recap ? 'Das kann TrailBuddy inzwischen' : 'Neu in TrailBuddy',
                  key: const ValueKey('highlight-sheet-title'),
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SheetCloseButton(),
            ],
          ),
          const SizedBox(height: 4),
          for (final h in plan.pages)
            _Row(key: ValueKey('highlight-row-${h.id}'), highlight: h, onTap: () => _show(context, ref, h)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => _go(context, '/profile/discover'),
                  child: Text(plan.more > 0 ? '${plan.more} weitere entdecken' : 'Alle Funktionen und Tipps'),
                ),
                TextButton(
                  onPressed: () => _go(context, '/profile/changelog'),
                  child: const Text('Alle Änderungen'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Fertig'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Eine Neuheit als Zeile: Bild, Titel, Text — die ganze Zeile führt es vor.
class _Row extends StatelessWidget {
  const _Row({super.key, required this.highlight, required this.onTap});

  final FeatureHighlight highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HighlightArt(highlight: highlight, size: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(highlight.title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(highlight.text, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 8, top: 4),
              child: Icon(Icons.play_circle_outline,
                  color: AppPalette.of(context).accentText, semanticLabel: 'Zeig es mir'),
            ),
          ],
        ),
      ),
    );
  }
}
