import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_info.dart';
import '../../core/app_theme.dart' show AppFonts;
import '../../core/errors.dart';
import '../../l10n/l10n.dart';
import '../../data/feedback_repository.dart';
import '../../data/outbox.dart';
import '../../data/providers.dart';
import '../garmin/watch_event_store.dart' show watchEventOfferProvider;
import '../garmin/watch_events.dart';
import '../trails/outbox_providers.dart';
import '../trails/trail_providers.dart' show newClientId, trailsProvider;

/// Die Glühbirne (PilzBuddy-Muster): ein Wunsch oder eine Fehlermeldung
/// an den Betreiber. Der Feedback-Bot macht daraus ein ÖFFENTLICHES
/// GitHub-Issue (`tool/feedback_bot.py`) — ohne Benutzernamen, aber mit
/// dem Text, wie er dasteht.
///
/// **Keine Trails hierhin.** Das Issue ist öffentlich, das Buddy-Netz
/// nicht; ein Trailname oder eine Ortsbeschreibung in einem Issue wäre
/// genau das, was das Community-Tor verhindern soll (Konzept 4). Der
/// Dialog sagt das vor dem Schreiben. Meldungen zu einem einzelnen Trail
/// bekommen einen eigenen Weg (Issue #7 für die Hinweise an Buddys).
Future<void> showFeedbackFlow(BuildContext context, WidgetRef ref) async {
  final input = await showDialog<FeedbackInput>(
    context: context,
    builder: (_) => const FeedbackDialog(),
  );
  if (input == null) return;
  // `await …future` und nicht `valueOrNull`: Beim ersten Lesen läuft
  // der Provider gerade erst an, die Version wäre sonst fast immer leer
  // (PilzBuddy #358). Ohne Version ist die Meldung trotzdem wertvoll.
  String? version;
  try {
    version = await ref.read(appVersionProvider.future);
  } catch (_) {
    // Kein Fehler des Nutzers und keiner, den jemand sucht.
  }
  // Der Auftrag entsteht VOR dem ersten Versuch (#218): Schon der erste
  // trägt die Kennung, und ein Nachholen nach abgerissener Antwort legt
  // keinen zweiten Eintrag an (Patch 018).
  final job = FeedbackJob(
    id: newClientId(),
    createdAt: DateTime.now().toUtc(),
    type: input.type,
    message: input.text,
    appVersion: version,
  );
  try {
    await ref
        .read(feedbackRepositoryProvider)
        .submit(input.type, input.text, appVersion: version, clientId: job.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(input.type == FeedbackType.bug
          ? context.l10n.feedbackThanksBug
          : context.l10n.feedbackThanksIdea),
    ));
  } catch (e, st) {
    // Ohne Empfang wartet der Text im Ausgangskorb (#218) — draußen
    // fällt einem etwas ein, und verworfen wäre es weg. Nur
    // `looksOffline`: Ein Serverfehler bleibt sichtbar. Liegt der Auftrag
    // nicht sicher (Web, volle Platte), kommt der Netzfehler wie bisher.
    if (looksOffline(e) && await _queue(ref, job)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.l10n.feedbackQueued),
      ));
      return;
    }
    logError('Feedback senden', e, st);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(friendlyError(context.l10n, e))));
  }
}

Future<bool> _queue(WidgetRef ref, FeedbackJob job) async {
  try {
    await ref.read(outboxJobsProvider.notifier).append(job);
    return true;
  } catch (_) {
    // Kein Korb: Der Aufrufer meldet den ursprünglichen Netzfehler.
    return false;
  }
}

/// Was der Dialog zurückgibt.
class FeedbackInput {
  const FeedbackInput(this.type, this.text);
  final FeedbackType type;
  final String text;
}

class FeedbackDialog extends ConsumerStatefulWidget {
  const FeedbackDialog({super.key});

  @override
  ConsumerState<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends ConsumerState<FeedbackDialog> {
  FeedbackType _type = FeedbackType.feature;
  final _text = TextEditingController();
  /// Das Uhr-Protokoll hängt an (#510) — nur bei einer Fehlermeldung, nur
  /// auf Wunsch, nie von selbst.
  bool _attachWatch = false;

  bool get _canSend => _text.text.trim().length >= kFeedbackMinChars;

  /// Die Zeile, die an den Text kommt, oder null.
  String? _watchLine(AppLocalizations l, WatchEventLog? log) {
    if (!_attachWatch || _type != FeedbackType.bug || log == null) return null;
    return '${l.feedbackWatchLogLine(log.events.length)} ${encodeWatchEvents(log.events)}';
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final waiting = [
      for (final j in ref.watch(outboxJobsProvider).valueOrNull ?? const <OutboxJob>[])
        if (j is FeedbackJob) j,
    ];
    final watchLog = _type == FeedbackType.bug ? ref.watch(watchEventOfferProvider).valueOrNull : null;
    final watchLine = _watchLine(l, watchLog);
    // `feedback.message` hat höchstens 2000 Zeichen — das Protokoll zählt mit.
    final maxText = 2000 - (watchLine == null ? 0 : watchLine.length + 2);
    return AlertDialog(
      title: Text(l.feedbackTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final job in waiting) _WaitingFeedback(job),
            if (waiting.isNotEmpty) const SizedBox(height: 12),
            SegmentedButton<FeedbackType>(
              segments: [
                ButtonSegment(
                    value: FeedbackType.feature,
                    icon: const Icon(Icons.lightbulb_outline),
                    label: Text(l.feedbackTypeIdea)),
                ButtonSegment(
                    value: FeedbackType.bug,
                    icon: const Icon(Icons.bug_report_outlined),
                    label: Text(l.feedbackTypeBug)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 12),
            Text(
              _type == FeedbackType.bug ? l.feedbackBugPrompt : l.feedbackIdeaPrompt,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              maxLines: 4,
              maxLength: maxText,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText:
                    _type == FeedbackType.bug ? l.feedbackBugLabel : l.feedbackIdeaLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.public, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l.feedbackPublicNote,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            if (watchLog != null) ...[
              const SizedBox(height: 8),
              _WatchLogOffer(
                log: watchLog,
                attached: _attachWatch,
                onChanged: (v) => setState(() => _attachWatch = v),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: _canSend
              ? () {
                  var text = _text.text.trim();
                  if (text.length > maxText) text = text.substring(0, maxText);
                  Navigator.of(context).pop(
                      FeedbackInput(_type, watchLine == null ? text : '$text\n\n$watchLine'));
                }
              : null,
          child: Text(l.feedbackSend),
        ),
      ],
    );
  }
}

/// Eine eigene Meldung, die noch im Ausgangskorb liegt (#218). Sie hängt
/// an keinem Trail, also ist die Glühbirne der Ort, an dem man sie sieht
/// — und an dem man über eine abgelehnte entscheidet.
class _WaitingFeedback extends ConsumerWidget {
  const _WaitingFeedback(this.job);

  final FeedbackJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final failed = job.failure != null;
    final text = job.message.length > 80 ? '${job.message.substring(0, 80)} …' : job.message;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final notifier = ref.read(outboxJobsProvider.notifier);
    return Card(
      key: ValueKey('feedback-waiting-${job.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(failed ? Icons.error_outline : Icons.schedule, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  failed ? l.feedbackRejected('${job.failure}') : l.feedbackWaiting,
                  style: theme.textTheme.labelMedium,
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(text, style: muted),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: ValueKey('feedback-discard-${job.id}'),
                  onPressed: () => notifier.discard(job.id),
                  child: Text(l.feedbackDiscard),
                ),
                if (failed)
                  TextButton(
                    key: ValueKey('feedback-retry-${job.id}'),
                    onPressed: () async {
                      // Vor dem `await` gegriffen: Ist der Dialog danach zu,
                      // ist dieses `ref` schon abgebaut.
                      final trails = ref.read(trailsProvider.notifier);
                      await notifier.retry(job.id);
                      await trails.sendOutbox();
                    },
                    child: Text(l.feedbackRetry),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Das Uhr-Protokoll zum Anhängen (#510): Schalter, was drin steht, und
/// die Liste Zeile für Zeile — der Nutzer sieht, was öffentlich wird,
/// bevor er sendet (A6).
class _WatchLogOffer extends StatelessWidget {
  const _WatchLogOffer({required this.log, required this.attached, required this.onChanged});

  final WatchEventLog log;
  final bool attached;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          key: const ValueKey('feedback-watch-log'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: attached,
          onChanged: (v) => onChanged(v ?? false),
          title: Text(l.feedbackWatchLogAttach),
          subtitle: Text(
            l.feedbackWatchLogInfo(log.events.length, log.fromCrash ? 'crash' : 'ride'),
            style: muted,
          ),
        ),
        ExpansionTile(
          key: const ValueKey('feedback-watch-log-list'),
          tilePadding: EdgeInsets.zero,
          title: Text(l.feedbackWatchLogShow, style: theme.textTheme.labelLarge),
          children: [
            for (final v in log.events)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${unpackWatchEvent(v).sec.toString().padLeft(6)} s  ${watchEventLabel(l, v)}',
                  style: muted?.copyWith(fontFamily: AppFonts.mono),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Eine Zeile des Uhr-Protokolls in der Sprache der App.
String watchEventLabel(AppLocalizations l, int v) {
  final p = watchEventParts(v);
  final d = 'd${p.detail}';
  return switch (p.kind) {
    'start' => l.watchEvStart(d),
    'key' => l.watchEvKey(d),
    'menu' => l.watchEvMenu(d),
    'in' => l.watchEvIn(p.detail),
    'out' => l.watchEvOut(p.detail),
    'sent' => l.watchEvSent(d),
    'state' => l.watchEvState(d),
    'fix' => l.watchEvFix(d),
    'due' => l.watchEvDue(d),
    _ => '? ${unpackWatchEvent(v).kind}.${p.detail}',
  };
}
