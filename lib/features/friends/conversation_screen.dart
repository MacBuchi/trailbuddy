// Der Verlauf mit einem Buddy (#34, Vorlage PilzBuddy #564) — so einfach
// wie möglich: eine Liste, ein Feld, ein Knopf.
//
// **Die Grenze steht da, bevor man an sie stößt.** Bei offener Anfrage
// sagt die Zeile über dem Feld, wie viele Nachrichten noch gehen; bei
// null ist das Feld zu und sagt warum. Die Datenbank prüft trotzdem
// selbst (`may_message`) — die Zahl hier ist die Ansage, nicht die
// Sperre.
//
// **Ohne Empfang scheitert das Senden sichtbar**, und der Text bleibt
// im Feld. Kein Ausgangskorb für Nachrichten: Eine Nachricht, die Tage
// später ankommt, wäre schlimmer als eine, die sagt, dass sie nicht
// ankam.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/app_colors.dart';
import '../../core/errors.dart';
import '../../data/message_repository.dart';
import '../../data/providers.dart';
import '../../l10n/l10n.dart';
import '../../models/buddy_message.dart';
import '../coach/coach.dart';
import '../help/tab_tours.dart' show BuddysCoach;
import 'buddy_alias.dart';
import 'buddy_alias_dialog.dart';
import 'friend_providers.dart';
import 'message_providers.dart';

const kMessageFieldKey = Key('message-field');
const kMessageSendKey = Key('message-send');
const kMessageLimitKey = Key('message-limit');
Key messageBubbleKey(String id) => ValueKey('message-$id');

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({super.key, required this.otherId});

  final String otherId;

  @override
  ConsumerState<ConversationScreen> createState() =>
      _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _controller = TextEditingController();
  bool _sending = false;

  /// Nachrichten, für die „gelesen" schon einmal versucht wurde.
  ///
  /// **Die Sperre gegen eine Endlosschleife**, gefunden in der
  /// Gegenprobe: Der Bildschirm markiert bei jeder neuen Liste, was
  /// ungelesen ist. Bewirkt das Markieren nichts (null Zeilen, ohne
  /// Fehler), lädt die Liste neu, zeigt weiter Ungelesenes — und der
  /// nächste Versuch startet. Im Feld hieße das Anfragen ohne Ende.
  /// Jede Nachricht bekommt deshalb genau einen Versuch je Öffnen.
  final _readAttempted = <String>{};

  @override
  void initState() {
    super.initState();
    // Frisch holen beim Öffnen — es gibt keine Live-Verbindung, und wer
    // den Verlauf öffnet, will den neuesten Stand. Danach gelesen
    // markieren.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.invalidate(messagesProvider);
      await _markRead();
    });
  }

  Future<void> _markRead() async {
    try {
      final uid = ref.read(currentUserIdProvider) ?? '';
      final all = await ref.read(messagesProvider.future);
      final fresh = [
        for (final m in all)
          if (m.senderId == widget.otherId &&
              m.isUnreadFor(uid) &&
              !_readAttempted.contains(m.id))
            m.id,
      ];
      if (fresh.isEmpty) return;
      _readAttempted.addAll(fresh);
      await ref.read(messagesProvider.notifier).markRead(widget.otherId);
    } catch (_) {
      // Still: Der Punkt bleibt stehen, das nächste Öffnen versucht es
      // wieder. Kein Grund, beim Lesen eine Fehlermeldung zu zeigen.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    try {
      await ref.read(messagesProvider.notifier).send(widget.otherId, text);
      _controller.clear();
    } on MessageRejectedException {
      messenger.showSnackBar(SnackBar(content: Text(l.messagesRejected)));
      // Die Anfrage ist womöglich weg — die Liste soll es zeigen.
      ref.invalidate(friendshipsProvider);
    } catch (e, s) {
      logError('Nachricht senden', e, s);
      messenger.showSnackBar(
          SnackBar(content: Text(l.messagesNotSent(friendlyError(l, e)))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(BuddyMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.messagesDeleteTitle),
        content: Text(context.l10n.messagesDeleteBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.messagesDeleteConfirm)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    try {
      await ref.read(messagesProvider.notifier).delete(message.id);
    } catch (e, s) {
      logError('Nachricht zurücknehmen', e, s);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(l, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final uid = ref.watch(currentUserIdProvider) ?? '';
    final friendships =
        ref.watch(friendshipsProvider).valueOrNull ?? const [];
    final friendship = friendshipWith(friendships, uid, widget.otherId);
    final all = ref.watch(messagesProvider).valueOrNull ?? const [];
    final messages = conversationWith(all, uid, widget.otherId);
    final names = ref.watch(buddyNamesViewProvider);
    final username = friendship?.otherUsername(uid) ?? 'Buddy';
    final alias = names.aliasOf(widget.otherId);
    final name = alias ?? username;
    final left = friendship == null ? 0 : messagesLeft(friendship, all, uid);
    final time = DateFormat(l.messagesTimePattern, l.localeName);

    // Neu Eingetroffenes auch als gelesen markieren, solange der
    // Verlauf offen ist.
    ref.listen(messagesProvider, (_, next) {
      if (next.valueOrNull?.any((m) =>
              m.senderId == widget.otherId && m.isUnreadFor(uid)) ??
          false) {
        _markRead();
      }
    });

    final String? limitLine = switch ((friendship, left)) {
      (null, _) => l.messagesLimitGone,
      (_, null) => null,
      (_, 0) => l.messagesLimitUsed(kPendingMessageLimit),
      (final f?, final n?) => f.isIncomingFor(uid)
          ? l.messagesLeftIncoming(n)
          : l.messagesLeftOutgoing(n, name),
    };
    final canWrite = friendship != null && left != 0;

    return Scaffold(
      // Mit Alias beide Namen, wie in der Buddy-Liste.
      appBar: AppBar(
        title: alias == null
            ? Text(name)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(alias),
                  Text(username, style: theme.textTheme.bodySmall),
                ],
              ),
        actions: [
          // Einen Alias gibt es nur für bestätigte Buddys (fa_insert).
          if (friendship?.isAccepted ?? false)
            AliasButton(friendId: widget.otherId, username: username),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(messagesProvider);
                await ref.read(messagesProvider.future);
              },
              child: ListView(
                reverse: true,
                padding: const EdgeInsets.all(12),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(l.messagesNote(kMessageDays),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall),
                  ),
                  for (final m in messages.reversed)
                    _Bubble(
                      key: messageBubbleKey(m.id),
                      message: m,
                      mine: m.isMine(uid),
                      time: time.format(m.createdAt.toLocal()),
                      onLongPress: m.isMine(uid) ? () => _delete(m) : null,
                    ),
                  if (messages.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l.messagesEmpty(name),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppPalette.of(context).muted),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (limitLine != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(limitLine,
                  key: kMessageLimitKey, style: theme.textTheme.bodySmall),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: CoachAnchor(
                      id: BuddysCoach.chatInput,
                      child: TextField(
                        key: kMessageFieldKey,
                        controller: _controller,
                        enabled: canWrite,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: kMessageMaxLength,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: l.messagesHint,
                          border: const OutlineInputBorder(),
                          counterText: '',
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    key: kMessageSendKey,
                    tooltip: l.messagesSend,
                    onPressed: canWrite && !_sending ? _send : null,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.message,
    required this.mine,
    required this.time,
    this.onLongPress,
  });

  final BuddyMessage message;
  final bool mine;
  final String time;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78),
          // Eigene eine Stufe heller, die des Buddys mit Rand — die Seite
          // sagt schon die Ausrichtung, die Fläche bestätigt sie nur.
          decoration: BoxDecoration(
            color: mine ? palette.surface2 : palette.surface,
            borderRadius: BorderRadius.circular(14),
            border: mine ? null : Border.all(color: palette.line),
          ),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(message.body),
              const SizedBox(height: 2),
              Text(time,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: palette.muted)),
            ],
          ),
        ),
      ),
    );
  }
}
