// Der Dialog „Alias vergeben" — aus der Buddy-Liste; wer ihn an einer
// zweiten Stelle braucht, ruft [showAliasDialog] statt zu kopieren.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../data/friend_repository.dart';
import '../../l10n/l10n.dart';
import 'buddy_alias.dart';

const kAliasFieldKey = Key('alias-field');
const kAliasSaveKey = Key('alias-save');
Key aliasButtonKey(String friendId) => ValueKey('alias-button-$friendId');

/// Der Knopf, der den Dialog öffnet.
class AliasButton extends ConsumerWidget {
  const AliasButton(
      {super.key, required this.friendId, required this.username});

  final String friendId;
  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alias = ref.watch(buddyNamesViewProvider).aliasOf(friendId);
    return IconButton(
      key: aliasButtonKey(friendId),
      tooltip: alias == null ? context.l10n.aliasSet : context.l10n.aliasChange,
      icon: const Icon(Icons.edit_outlined),
      onPressed: () => showAliasDialog(context, ref,
          friendId: friendId, username: username),
    );
  }
}

Future<void> showAliasDialog(BuildContext context, WidgetRef ref,
    {required String friendId, required String username}) async {
  final current = ref.read(buddyNamesViewProvider).aliasOf(friendId);
  final text = await showDialog<String>(
    context: context,
    builder: (_) => _AliasDialog(username: username, current: current),
  );
  if (text == null || text.trim() == (current ?? '')) return;
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(buddyAliasesProvider.notifier).set(friendId, text);
  } catch (e, st) {
    logError('Alias speichern', e, st);
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}

class _AliasDialog extends StatefulWidget {
  const _AliasDialog({required this.username, required this.current});

  final String username;
  final String? current;

  @override
  State<_AliasDialog> createState() => _AliasDialogState();
}

class _AliasDialogState extends State<_AliasDialog> {
  late final _controller = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.aliasTitle(widget.username)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: kAliasFieldKey,
            controller: _controller,
            autofocus: true,
            maxLength: kAliasMaxLength,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: l.aliasLabel,
              hintText: l.aliasHint,
            ),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
          const SizedBox(height: 4),
          Text(
            // Die zwei Fragen, die man sich dabei stellt: Sieht er das?
            // Und was, wenn er sich umbenennt?
            l.aliasNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.commonCancel)),
        FilledButton(
            key: kAliasSaveKey,
            onPressed: () => Navigator.of(context).pop(_controller.text),
            child: Text(l.commonSave)),
      ],
    );
  }
}
