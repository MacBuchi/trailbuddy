// Das „i" neben einer Überschrift (Betreiber, 2026-09-22: „nutze evtl
// info icon, kann direkt in der ersten Zeile sein und dann einfach den
// Text überlagert einblenden").
//
// **Es ersetzt einen Absatz, keine Warnung.** Was hier hinter einen Tipp
// wandert, erklärt, wie etwas gemeint ist — welche Arten der Reiter
// zeigt, was ein Filter ausblendet. Eine Einstufung, ein
// Verwechslungspartner oder der Grund, warum etwas gesperrt ist, gehören
// NICHT hierher: Dieselbe Trennlinie wie beim Einklappen der Merkmale
// und beim `_PhotoNote`, und aus demselben Grund — eine eingeklappte
// Warnung ist Deko.
//
// **Der Text kommt als Dialog, nicht als Tooltip.** Ein Tooltip
// verschwindet beim Loslassen und lässt sich nicht lesen, wenn er länger
// als eine Zeile ist; ein Dialog schließt über x, Zurück-Geste und einen
// Tipp daneben — dieselben drei Wege wie überall sonst.
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

/// Öffnet [text] als überlagerten Kasten.
Future<void> showInfoText(
  BuildContext context, {
  required String title,
  required String text,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(text)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.commonClose),
        ),
      ],
    ),
  );
}

/// Das „i", das [text] einblendet.
class InfoButton extends StatelessWidget {
  const InfoButton({super.key, required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.info_outline, size: 20),
      tooltip: title,
      // **44 bleiben 44**, wie beim x am Kopf eines Blatts. Die Zeile
      // wird dadurch höher als ihr Text — und das ist der Preis dafür,
      // dass der Knopf im Gehen zu treffen ist. Gespart wird an dem
      // Absatz, den er ersetzt, nicht an seiner Trefferfläche.
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.standard,
      onPressed: () => showInfoText(context, title: title, text: text),
    );
  }
}
