// Das Namensfeld nach „Trail endet" (#486, Betreiber 2026-11-07: geht
// von selbst auf). Auf dem Trail, mit Handschuh: ein Feld, ein großer
// Knopf „Speichern", daneben „Speichern, nächster beginnt" für zwei
// Trails am Stück, „Später" (Name im Zerlege-Blatt) und „Verwerfen" für
// eine versehentliche Marke. Ein Vorschlag aus dem Netz oder von früher
// in der Fahrt steht schon im Feld; dann geht die Tastatur nicht auf.

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import 'ride_mark_name.dart';

/// Was der Fahrer im Namensfeld gewählt hat.
sealed class MarkNameChoice {
  const MarkNameChoice();
}

/// Name speichern; [next] heißt: gleich der nächste Trail.
class MarkNameSaved extends MarkNameChoice {
  const MarkNameSaved(this.name, {this.next = false});
  final String name;
  final bool next;
}

/// Ohne Namen weiter — das Blatt fragt nach der Fahrt.
class MarkNameLater extends MarkNameChoice {
  const MarkNameLater();
}

/// Die Marke war ein Versehen: Beginn und Ende zurücknehmen.
class MarkNameDiscarded extends MarkNameChoice {
  const MarkNameDiscarded();
}

/// Höhe der Knöpfe: A13 verlangt 44 dp, mit Handschuh lieber mehr.
const _kButtonHeight = 52.0;

Future<MarkNameChoice> showMarkNameDialog(BuildContext context, {MarkNameSuggestion? suggestion}) async {
  final choice = await showDialog<MarkNameChoice>(
    context: context,
    builder: (_) => _MarkNameDialog(suggestion: suggestion),
  );
  return choice ?? const MarkNameLater();
}

class _MarkNameDialog extends StatefulWidget {
  const _MarkNameDialog({this.suggestion});

  final MarkNameSuggestion? suggestion;

  @override
  State<_MarkNameDialog> createState() => _MarkNameDialogState();
}

class _MarkNameDialogState extends State<_MarkNameDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.suggestion?.name ?? '');

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save({bool next = false}) {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(MarkNameSaved(name, next: next));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final suggestion = widget.suggestion;
    final canSave = _name.text.trim().isNotEmpty;
    const tall = Size.fromHeight(_kButtonHeight);
    return AlertDialog(
      title: Text(l.rideMarkNameTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (suggestion != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(switch (suggestion.source) {
                  MarkNameSource.network => l.rideMarkNameFromNetwork,
                  MarkNameSource.earlierInRide => l.rideMarkNameFromRide,
                }),
              ),
            TextField(
              key: const ValueKey('ride-mark-name'),
              controller: _name,
              autofocus: suggestion == null,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(labelText: l.detailsName, counterText: ''),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('ride-mark-name-save'),
              style: FilledButton.styleFrom(minimumSize: tall),
              onPressed: canSave ? _save : null,
              child: Text(l.rideMarkNameSave),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('ride-mark-name-next'),
              style: OutlinedButton.styleFrom(minimumSize: tall),
              onPressed: canSave ? () => _save(next: true) : null,
              child: Text(l.rideMarkNameSaveNext),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    key: const ValueKey('ride-mark-name-discard'),
                    style: TextButton.styleFrom(minimumSize: tall),
                    onPressed: () => Navigator.of(context).pop(const MarkNameDiscarded()),
                    child: Text(l.rideMarkNameDiscard),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    key: const ValueKey('ride-mark-name-later'),
                    style: TextButton.styleFrom(minimumSize: tall),
                    onPressed: () => Navigator.of(context).pop(const MarkNameLater()),
                    child: Text(l.rideMarkNameLater),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
