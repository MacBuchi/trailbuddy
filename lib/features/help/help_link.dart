import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/l10n.dart';

/// Der Knopf „Kurzanleitung" in den Leerzuständen (#131): Wer vor einer
/// leeren Liste steht, sucht genau die Erklärung, wie etwas hineinkommt.
///
/// `push` und nicht `go`: Die Anleitung liegt unter dem Profil, und
/// Zurück soll dahin führen, wo man herkam — nicht ins Profil.
class HelpLinkButton extends StatelessWidget {
  const HelpLinkButton({super.key});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('help-link'),
          onPressed: () => context.push('/profile/help'),
          icon: const Icon(Icons.help_outline),
          label: Text(context.l10n.helpTitle),
        ),
      );
}
