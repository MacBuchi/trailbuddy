// Die Frage an der Zeile eines wieder gefahrenen Trails im Zerlege-Blatt
// (#116, zweiter Teil): dieselbe Frage wie unterwegs — „Stimmt",
// „Trail ist frei", „Ändern…" —, hier mit Platz für den richtigen Wert.
//
// Gesendet wird SOFORT beim Tipp, nicht mit „Speichern": Die Antwort hängt
// nicht daran, ob das Stück beigesteuert wird, und ein weggewischtes
// Blatt soll sie nicht verlieren. „Vor Ort" war, wer den Trail gefahren
// ist; die Zeit ist die der Fahrt am Trail, nicht die des Tipps.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/errors.dart';
import '../../l10n/l10n.dart';
import '../../models/trail.dart';
import '../trails/trail_condition.dart';
import '../trails/trail_providers.dart';
import 'ride_confirm.dart';

class SplitConfirmRow extends ConsumerStatefulWidget {
  const SplitConfirmRow({super.key, required this.target, required this.rodeAt, required this.index});

  final ConfirmTarget target;
  final DateTime rodeAt;

  /// Für die Schlüssel: `split-confirm-<index>-…`.
  final int index;

  @override
  ConsumerState<SplitConfirmRow> createState() => _SplitConfirmRowState();
}

enum _Stage { ask, change, sending, sent, failed }

class _SplitConfirmRowState extends ConsumerState<SplitConfirmRow> {
  _Stage _stage = _Stage.ask;
  TrailStatus? _status;
  int? _condition;
  WriteOutcome? _outcome;

  String get _k => 'split-confirm-${widget.index}';

  @override
  void initState() {
    super.initState();
    _status = widget.target.status;
    _condition = widget.target.condition;
  }

  Future<void> _send({TrailStatus? status, int? condition}) async {
    setState(() => _stage = _Stage.sending);
    try {
      final outcome = await ref.read(trailsProvider.notifier).report(widget.target.trailId,
          status: status, condition: condition, onSite: true, at: widget.rodeAt);
      if (!mounted) return;
      setState(() {
        _outcome = outcome;
        _stage = _Stage.sent;
      });
    } catch (e, stackTrace) {
      logError('Zerlege-Blatt: Meldung bestätigen', e, stackTrace);
      if (!mounted) return;
      setState(() => _stage = _Stage.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final notice = confirmNoticeOf(context.l10n, widget.target);
    final muted = theme.textTheme.bodySmall?.copyWith(color: palette.muted);
    return Padding(
      padding: const EdgeInsets.only(left: 48, bottom: 8),
      child: switch (_stage) {
        _Stage.sent => Text(
            key: ValueKey('$_k-sent'),
            _outcome == WriteOutcome.queued
                ? context.l10n.confirmSentQueued
                : context.l10n.confirmSent,
            style: muted),
        _Stage.failed => Text(
            key: ValueKey('$_k-failed'),
            context.l10n.confirmFailed,
            style: muted?.copyWith(color: palette.warningText)),
        _Stage.sending => const LinearProgressIndicator(),
        _Stage.ask => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(notice.body, key: ValueKey('$_k-question'), style: muted),
              const SizedBox(height: 4),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final (choice, label) in notice.actions)
                  OutlinedButton(
                    key: ValueKey('$_k-${choice.id}'),
                    onPressed: () => switch (choice) {
                      ConfirmChoice.confirm =>
                        _send(status: widget.target.status, condition: widget.target.condition),
                      ConfirmChoice.free => _send(status: TrailStatus.open),
                      ConfirmChoice.change => setState(() => _stage = _Stage.change),
                    },
                    child: Text(label),
                  ),
              ]),
            ],
          ),
        _Stage.change => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.target.status != null) ...[
                Text(context.l10n.reportFieldLabel, style: muted),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final s in TrailStatus.values)
                    ChoiceChip(
                      key: ValueKey('$_k-status-${s.db}'),
                      label: Text(s.label),
                      selected: _status == s,
                      onSelected: (_) => setState(() => _status = s),
                    ),
                ]),
              ],
              if (widget.target.condition != null) ...[
                const SizedBox(height: 4),
                Text(context.l10n.reportCondition, style: muted),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final c in kTrailConditions)
                    ChoiceChip(
                      key: ValueKey('$_k-condition-${c.value}'),
                      label: Text(c.label(context.l10n)),
                      tooltip: c.description(context.l10n),
                      selected: _condition == c.value,
                      onSelected: (_) => setState(() => _condition = c.value),
                    ),
                ]),
              ],
              const SizedBox(height: 4),
              Row(children: [
                FilledButton.tonal(
                  key: ValueKey('$_k-submit'),
                  onPressed: () => _send(
                      status: widget.target.status != null ? _status : null,
                      condition: widget.target.condition != null ? _condition : null),
                  child: Text(context.l10n.reportSubmit),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() => _stage = _Stage.ask),
                  child: Text(context.l10n.commonBack),
                ),
              ]),
            ],
          ),
      },
    );
  }
}
