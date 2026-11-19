// Blockieren und Melden (#584, Patch 033; Google-Play-Richtlinie „User
// Generated Content"). Die Regeln stehen nur in der Datenbank: Blockieren
// beendet die Beziehung und verwirft jede neue Anfrage still, gemeldet
// wird in eine Tabelle, die nur der Betreiber liest. Hier stehen nur die
// Rückfragen und das Menü, die an mehreren Stellen gleich sein müssen —
// Buddy-Zeile, Anfrage, Verlauf, eine einzelne Nachricht.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../l10n/l10n.dart';
import '../../models/friendship.dart';
import '../../data/providers.dart';
import 'friend_providers.dart';

/// So lang darf die Notiz einer Meldung sein — der Check im Schema.
const kReportNoteMaxLength = 500;

/// Fragt nach und blockiert [otherId]. `true`, wenn blockiert ist.
Future<bool> confirmBlock(
  BuildContext context,
  WidgetRef ref, {
  required String otherId,
  required String name,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.safetyBlockTitle(name)),
      content: Text(context.l10n.safetyBlockBody(name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.l10n.safetyBlockConfirm),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  try {
    await ref.read(blocksProvider.notifier).block(otherId);
    messenger.showSnackBar(SnackBar(content: Text(l.safetyBlocked(name))));
    return true;
  } catch (e, s) {
    logError('Blockieren', e, s);
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(l, e))));
    return false;
  }
}

/// Der Melde-Dialog für eine Person oder — mit [messageId] — eine
/// Nachricht von ihr. `true`, wenn danach auch blockiert ist.
Future<bool> showReportDialog(
  BuildContext context,
  WidgetRef ref, {
  required String otherId,
  required String name,
  String? messageId,
}) async {
  final result = await showDialog<_ReportInput>(
    context: context,
    builder: (context) =>
        _ReportDialog(name: name, isMessage: messageId != null),
  );
  if (result == null || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  try {
    await ref
        .read(friendRepositoryProvider)
        .report(
          otherId,
          messageId: messageId,
          reason: result.reason,
          note: result.note,
        );
  } catch (e, s) {
    logError('Melden', e, s);
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(l, e))));
    return false;
  }
  if (!result.alsoBlock) {
    messenger.showSnackBar(SnackBar(content: Text(l.safetyReported)));
    return false;
  }
  try {
    await ref.read(blocksProvider.notifier).block(otherId);
    messenger.showSnackBar(
      SnackBar(content: Text(l.safetyReportedAndBlocked(name))),
    );
    return true;
  } catch (e, s) {
    logError('Blockieren nach dem Melden', e, s);
    messenger.showSnackBar(
      SnackBar(content: Text('${l.safetyReported} ${friendlyError(l, e)}')),
    );
    return false;
  }
}

class _ReportInput {
  const _ReportInput(this.reason, this.note, this.alsoBlock);

  final ReportReason reason;
  final String? note;
  final bool alsoBlock;
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.name, required this.isMessage});

  final String name;
  final bool isMessage;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  ReportReason? _reason;
  bool _alsoBlock = false;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String _label(ReportReason r) => switch (r) {
    ReportReason.spam => context.l10n.safetyReasonSpam,
    ReportReason.abuse => context.l10n.safetyReasonAbuse,
    ReportReason.inappropriate => context.l10n.safetyReasonInappropriate,
    ReportReason.other => context.l10n.safetyReasonOther,
  };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(
        widget.isMessage
            ? l.safetyReportMessageTitle(widget.name)
            : l.safetyReportTitle(widget.name),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.safetyReportIntro(widget.name)),
            const SizedBox(height: 8),
            RadioGroup<ReportReason>(
              groupValue: _reason,
              onChanged: (r) => setState(() => _reason = r),
              child: Column(
                children: [
                  for (final r in ReportReason.values)
                    RadioListTile<ReportReason>(
                      value: r,
                      title: Text(_label(r)),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                ],
              ),
            ),
            TextField(
              key: const Key('report-note'),
              controller: _note,
              maxLength: kReportNoteMaxLength,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(labelText: l.safetyReportNote),
            ),
            CheckboxListTile(
              value: _alsoBlock,
              onChanged: (v) => setState(() => _alsoBlock = v ?? false),
              title: Text(l.safetyReportAlsoBlock),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          key: const Key('report-send'),
          onPressed: _reason == null
              ? null
              : () => Navigator.of(context).pop(
                  _ReportInput(
                    _reason!,
                    _note.text.trim().isEmpty ? null : _note.text.trim(),
                    _alsoBlock,
                  ),
                ),
          child: Text(l.safetyReportSend),
        ),
      ],
    );
  }
}

enum _MoreAction { remove, report, block }

/// Das Menü „Mehr" an einer Buddy-Zeile oder Anfrage: Entfernen (wenn
/// [onRemove] gesetzt ist), Melden, Blockieren.
class SafetyMenuButton extends ConsumerWidget {
  const SafetyMenuButton({
    super.key,
    required this.otherId,
    required this.name,
    this.onRemove,
    this.removeLabel,
    this.onBlocked,
  });

  final String otherId;
  final String name;
  final VoidCallback? onRemove;
  final String? removeLabel;

  /// Nach dem Blockieren (auch über „Melden" mit „Auch blockieren") — der
  /// Verlauf schließt sich dann, es gibt ihn nicht mehr.
  final VoidCallback? onBlocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return PopupMenuButton<_MoreAction>(
      tooltip: l.safetyMore(name),
      icon: const Icon(Icons.more_vert),
      onSelected: (action) {
        switch (action) {
          case _MoreAction.remove:
            onRemove?.call();
          case _MoreAction.report:
            showReportDialog(
              context,
              ref,
              otherId: otherId,
              name: name,
            ).then((blocked) => blocked ? onBlocked?.call() : null);
          case _MoreAction.block:
            confirmBlock(
              context,
              ref,
              otherId: otherId,
              name: name,
            ).then((blocked) => blocked ? onBlocked?.call() : null);
        }
      },
      itemBuilder: (context) => [
        if (onRemove != null)
          PopupMenuItem(
            value: _MoreAction.remove,
            child: Text(removeLabel ?? l.buddysRemoveTooltip),
          ),
        PopupMenuItem(value: _MoreAction.report, child: Text(l.safetyReport)),
        PopupMenuItem(value: _MoreAction.block, child: Text(l.safetyBlock)),
      ],
    );
  }
}
