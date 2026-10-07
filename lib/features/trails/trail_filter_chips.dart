// Die Filter-Chips für Trails (#66) — EIN Widget für die Liste und das
// Blatt „Kartenebenen" der Karte, weil beide denselben Filter setzen
// (`trailListFilterProvider`). Zwei Fassungen wären zwei Meinungen
// darüber, was „bis S2" heißt.
//
// Der S-Grad ist seit #222 ein Bereich, den man einstellt (vorher fest
// „bis S2"): Der Chip zeigt ihn und öffnet ein Blatt mit Schiebern.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/trail.dart';
import 'singletrail_scale.dart';
import 'trail_list.dart';
import 'trail_providers.dart';
import 'trail_traits.dart';

/// Die Merkmale mit eigenem Filter-Chip — die aus dem Design (4e); der
/// Rest bleibt im Blatt sichtbar, filtert aber nicht, sonst wäre die
/// Chip-Reihe länger als der Schirm.
const kFilterTraits = [TrailTrait.flowy, TrailTrait.jumps];

class TrailFilterChips extends ConsumerWidget {
  const TrailFilterChips(
      {super.key, required this.showOwner, this.keyPrefix = 'trail', this.onMapChip = false});

  /// „Alle / Meine / Von Buddys" nur, wenn es beides gibt — sonst hätte
  /// eine Hälfte immer „keine Trails".
  final bool showOwner;

  /// Liste und Blatt können zugleich im Baum stehen (der Reiter bleibt
  /// eingehängt); getrennte Schlüssel halten sie auseinander.
  final String keyPrefix;

  /// „Auf der Karte" (#222) — nur in der Liste: Auf der Karte selbst
  /// hieße er „zeige, was du zeigst".
  final bool onMapChip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(trailListFilterProvider);
    void set(TrailListFilter f) => ref.read(trailListFilterProvider.notifier).state = f;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showOwner) ...[
          const SizedBox(height: 8),
          SegmentedButton<TrailOwnerFilter>(
            key: ValueKey('$keyPrefix-owner'),
            showSelectedIcon: false,
            segments: [
              for (final v in TrailOwnerFilter.values) ButtonSegment(value: v, label: Text(v.label)),
            ],
            selected: {filter.owner},
            onSelectionChanged: (s) => set(filter.copyWith(owner: s.first)),
          ),
        ],
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            // Erst, wenn die Karte einmal stand — vorher gibt es keinen
            // Ausschnitt, und der Chip leerte nur die Liste.
            if (onMapChip &&
                (ref.watch(trailListOnMapProvider) || ref.watch(mapVisibleBoundsProvider) != null))
              FilterChip(
                key: ValueKey('$keyPrefix-filter-on-map'),
                avatar: const Icon(Icons.crop_free, size: 18),
                label: const Text('Auf der Karte'),
                selected: ref.watch(trailListOnMapProvider),
                onSelected: (v) => ref.read(trailListOnMapProvider.notifier).state = v,
              ),
            FilterChip(
              key: ValueKey('$keyPrefix-filter-grade'),
              label: Text(filter.gradeActive ? filter.gradeText : 'S-Grad'),
              // Kein Häkchen: Der Chip öffnet ein Blatt, er schaltet nicht.
              showCheckmark: false,
              avatar: const Icon(Icons.tune, size: 18),
              selected: filter.gradeActive,
              onSelected: (_) => showGradeRangeSheet(context),
            ),
            FilterChip(
              key: ValueKey('$keyPrefix-filter-fresh'),
              label: const Text('Neuer Hinweis'),
              selected: filter.freshNotesOnly,
              onSelected: (v) => set(filter.copyWith(freshNotesOnly: v)),
            ),
            // Der Charakter (#72): die beiden Chips aus dem Design (4e).
            for (final t in kFilterTraits)
              TrailTraitChip(
                t,
                key: ValueKey('$keyPrefix-filter-${t.db}'),
                label: t == TrailTrait.jumps ? 'Jumps' : null,
                selected: filter.traits.contains(t),
                onSelected: (v) => set(filter.copyWith(
                    traits: v ? {...filter.traits, t} : ({...filter.traits}..remove(t)))),
              ),
            FilterChip(
              key: ValueKey('$keyPrefix-filter-reported'),
              label: const Text('Gemeldet'),
              selected: filter.reportedOnly,
              onSelected: (v) => set(filter.copyWith(reportedOnly: v)),
            ),
            // Rework E13: eigene Trails ohne eigene Sterne — dieselben, die
            // verblasste Sterne zeigen.
            FilterChip(
              key: ValueKey('$keyPrefix-filter-rating-open'),
              label: const Text('Bewertung offen'),
              selected: filter.ratingOpenOnly,
              onSelected: (v) => set(filter.copyWith(ratingOpenOnly: v)),
            ),
            // #119: eigene Angaben, die älter als 30 Tage sind — dieselben,
            // die die Seite „Noch gültig?" im Profil nennt. Nur, wenn es
            // welche gibt (oder der Filter an ist): Ein Chip, der immer nur
            // „keine Trails" liefert, kostet auf dem Telefon eine Zeile.
            if (filter.stillValidOnly || ref.watch(stillValidQuestionsProvider).isNotEmpty)
              FilterChip(
                key: ValueKey('$keyPrefix-filter-still-valid'),
                label: const Text('Noch gültig?'),
                selected: filter.stillValidOnly,
                onSelected: (v) => set(filter.copyWith(stillValidOnly: v)),
              ),
          ],
        ),
      ],
    );
  }
}

/// Das Blatt für den S-Grad-Bereich (#222): zwei Schieber über S0–S5, der
/// Filter folgt beim Ziehen — Liste und Karte dahinter zeigen sofort, was
/// übrig bleibt.
Future<void> showGradeRangeSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _GradeRangeSheet(),
    );

class _GradeRangeSheet extends ConsumerWidget {
  const _GradeRangeSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(trailListFilterProvider);
    void set(TrailListFilter f) => ref.read(trailListFilterProvider.notifier).state = f;
    final theme = Theme.of(context);
    final lo = singletrailGrade(filter.minGrade), hi = singletrailGrade(filter.maxGrade);
    // Scrollbar: Quer auf dem Telefon ist das Blatt höher als der Platz.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Schwierigkeit: ${filter.gradeText}',
                key: const ValueKey('grade-range-title'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            RangeSlider(
              key: const ValueKey('grade-range-slider'),
              min: kMinGrade.toDouble(),
              max: kMaxGrade.toDouble(),
              divisions: kMaxGrade - kMinGrade,
              values: RangeValues(filter.minGrade.toDouble(), filter.maxGrade.toDouble()),
              labels: RangeLabels(lo.label, hi.label),
              onChanged: (v) =>
                  set(filter.copyWith(minGrade: v.start.round(), maxGrade: v.end.round())),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final g in kSingletrailScale)
                    Text(g.label, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              lo == hi ? '${lo.label}: ${lo.short}' : '${lo.label}: ${lo.short}\n${hi.label}: ${hi.short}',
              style: theme.textTheme.bodyMedium,
            ),
            if (filter.gradeActive) ...[
              const SizedBox(height: 8),
              Text(
                'Trails, die noch niemand eingeschätzt hat, sind nicht dabei.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const ValueKey('grade-range-reset'),
                  onPressed: filter.gradeActive
                      ? () => set(filter.copyWith(minGrade: kMinGrade, maxGrade: kMaxGrade))
                      : null,
                  child: const Text('Alle Grade'),
                ),
                FilledButton(
                  key: const ValueKey('grade-range-done'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Fertig'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
