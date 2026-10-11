// „Noch gültig?" (#119): eigene Meldungen und Zustände, die älter als 30
// Tage sind, zur Durchsicht — Ja, Nein, Weiß nicht. Welche es sind,
// rechnet `still_valid.dart`; hier wird nur gezeigt und geantwortet.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../l10n/l10n.dart';
import '../../models/trail.dart';
import 'still_valid.dart';
import 'trail_condition.dart';
import 'trail_providers.dart';
import 'trail_report.dart' show reportAgeLabel, reportValueLabel;

class StillValidScreen extends ConsumerWidget {
  const StillValidScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questions = ref.watch(stillValidQuestionsProvider);
    final theme = Theme.of(context);
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.stillValidTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            l.stillValidIntro(kStillValidAfter.inDays, kStillValidSnooze.inDays),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          if (questions.isEmpty)
            Padding(
              key: const ValueKey('still-valid-empty'),
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(l.stillValidEmpty),
            ),
          for (final q in questions) _QuestionCard(q),
        ],
      ),
    );
  }
}

class _QuestionCard extends ConsumerStatefulWidget {
  const _QuestionCard(this.question);

  final StillValidQuestion question;

  @override
  ConsumerState<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends ConsumerState<_QuestionCard> {
  bool _busy = false;

  StillValidQuestion get q => widget.question;
  String get _key => '${q.trail.id}-${q.kind.name}';

  /// Eine Antwort ist eine neue Meldung (Rework Abschnitt 9): bestätigt
  /// wie immer — wer den Trail gefahren hat. Ohne Netz in den Korb.
  Future<void> _send({TrailStatus? status, int? condition}) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      final outcome = await ref
          .read(trailsProvider.notifier)
          .report(q.trail.id, status: status, condition: condition, onSite: false);
      messenger.showSnackBar(SnackBar(
          content: Text(outcome == WriteOutcome.queued
              ? l.stillValidQueued
              : l.stillValidUpdated)));
    } catch (e, st) {
      logError('Noch gültig? beantworten', e, st);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _yes() => q.kind == ReportKind.status
      ? _send(status: q.report.status)
      : _send(condition: q.report.condition);

  /// Nein: Eine Meldung ist vorbei („offen"); ein Zustand hat sich
  /// geändert — welcher es jetzt ist, sagt die Skala.
  Future<void> _no() async {
    if (q.kind == ReportKind.status) return _send(status: TrailStatus.open);
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.stillValidConditionTitle),
        children: [
          for (final c in kTrailConditions)
            SimpleDialogOption(
              key: ValueKey('still-valid-condition-${c.value}'),
              onPressed: () => Navigator.of(context).pop(c.value),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(c.label(context.l10n)),
                subtitle: Text(c.description(context.l10n)),
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    await _send(condition: picked);
  }

  void _dontKnow() => ref.read(stillValidSnoozesProvider.notifier).snooze(q.report.id);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final value = reportValueLabel(l, q.report), age = reportAgeLabel(l, q.report.reportedAt);
    return Card(
      key: ValueKey('still-valid-$_key'),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(q.trail.displayName),
              subtitle: Text(q.kind == ReportKind.status
                  ? l.stillValidStatusLine(value, age)
                  : l.stillValidConditionLine(value, age)),
              trailing: IconButton(
                tooltip: l.stillValidShowOnMap,
                icon: const Icon(Icons.map_outlined),
                onPressed: () => context.go('/trail/${q.trail.id}'),
              ),
            ),
            Text(l.stillValidQuestion, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonal(
                  key: ValueKey('still-valid-yes-$_key'),
                  onPressed: _busy ? null : _yes,
                  child: Text(l.stillValidYes),
                ),
                OutlinedButton(
                  key: ValueKey('still-valid-no-$_key'),
                  onPressed: _busy ? null : _no,
                  child: Text(q.kind == ReportKind.status ? l.stillValidNoReopen : l.stillValidNo),
                ),
                TextButton(
                  key: ValueKey('still-valid-unknown-$_key'),
                  onPressed: _busy ? null : _dontKnow,
                  child: Text(l.stillValidDontKnow),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
