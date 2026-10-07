import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_info.dart';
import '../../core/errors.dart';
import '../../data/feedback_repository.dart';
import '../../data/outbox.dart';
import '../../data/providers.dart';
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
          ? 'Danke für die Meldung — wir schauen uns das an!'
          : 'Danke für deinen Wunsch!'),
    ));
  } catch (e, st) {
    // Ohne Empfang wartet der Text im Ausgangskorb (#218) — draußen
    // fällt einem etwas ein, und verworfen wäre es weg. Nur
    // `looksOffline`: Ein Serverfehler bleibt sichtbar. Liegt der Auftrag
    // nicht sicher (Web, volle Platte), kommt der Netzfehler wie bisher.
    if (looksOffline(e) && await _queue(ref, job)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Kein Empfang — wird gesendet, sobald wieder Netz da ist.'),
      ));
      return;
    }
    logError('Feedback senden', e, st);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(friendlyError(e))));
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

  bool get _canSend => _text.text.trim().length >= kFeedbackMinChars;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final waiting = [
      for (final j in ref.watch(outboxJobsProvider).valueOrNull ?? const <OutboxJob>[])
        if (j is FeedbackJob) j,
    ];
    return AlertDialog(
      title: const Text('Wünsch dir was!'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final job in waiting) _WaitingFeedback(job),
            if (waiting.isNotEmpty) const SizedBox(height: 12),
            SegmentedButton<FeedbackType>(
              segments: const [
                ButtonSegment(
                    value: FeedbackType.feature,
                    icon: Icon(Icons.lightbulb_outline),
                    label: Text('Idee')),
                ButtonSegment(
                    value: FeedbackType.bug,
                    icon: Icon(Icons.bug_report_outlined),
                    label: Text('Fehler')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 12),
            Text(
              _type == FeedbackType.bug
                  ? 'Was funktioniert nicht? Beschreib kurz, was du gemacht '
                      'hast und was stattdessen passiert ist.'
                  : 'TrailBuddy ist noch ganz frisch — was fehlt dir, was '
                      'nervt, was wäre praktisch?',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              maxLines: 4,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText:
                    _type == FeedbackType.bug ? 'Was ist passiert?' : 'Dein Wunsch',
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
                    'Wird als öffentlicher Eintrag auf GitHub angelegt — '
                    'ohne deinen Namen, aber mit diesem Text. Bitte keine '
                    'Trailnamen, Orte oder Wegbeschreibungen.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
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
          onPressed: _canSend
              ? () => Navigator.of(context)
                  .pop(FeedbackInput(_type, _text.text.trim()))
              : null,
          child: const Text('Senden'),
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
                  failed ? 'Nicht angenommen: ${job.failure}' : 'Wartet auf Übertragung',
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
                  child: const Text('Verwerfen'),
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
                    child: const Text('Erneut versuchen'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
