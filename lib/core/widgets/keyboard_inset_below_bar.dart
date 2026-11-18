import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Zieht vom Tastatur-Inset ab, was die Reiterleiste darunter schon
/// verdeckt.
///
/// Die Hülle (`AppShell`) weicht der Tastatur NICHT aus, ihr Body
/// endet also dauerhaft über der Reiterleiste. `viewInsets.bottom` misst
/// die Tastatur aber vom Bildschirmrand aus. Ein Scaffold im Reiter, der
/// ausweicht, schrumpfte deshalb um die volle Tastaturhöhe, obwohl sein
/// unterer Rand schon um die Höhe der Leiste (samt Systemleiste) höher
/// liegt — das Eingabefeld stand eine Leistenhöhe über der Tastatur.
/// Gemessen in PilzBuddy, betrifft jeden Reiter mit Textfeld.
///
/// Gemessen statt angenommen: Der Abstand ist die Differenz zwischen
/// Bildschirmhöhe und der Höhe, die dieses Widget bekommt. Eine feste
/// Leistenhöhe wäre bei jeder Theme-Änderung und jeder Systemleiste
/// still falsch.
///
/// Im Browser gilt dasselbe: Die Web-Engine hält bei offener Tastatur die
/// volle Höhe fest und meldet die Tastatur als `viewInsets`
/// (`_handleBrowserResize` in `window.dart` der Engine).
class KeyboardInsetBelowBar extends StatelessWidget {
  const KeyboardInsetBelowBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Hier gelesen, nicht im LayoutBuilder: So baut das Widget neu, wenn
    // die Tastatur kommt oder geht.
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final covered = media.size.height - constraints.maxHeight;
        final inset = keyboardInsetBelow(media.viewInsets.bottom, covered);
        if (inset == media.viewInsets.bottom) return child;
        return MediaQuery(
          data: media.copyWith(
            viewInsets: media.viewInsets.copyWith(bottom: inset),
          ),
          child: child,
        );
      },
    );
  }
}

/// Das Inset, das oberhalb eines Bereichs übrig bleibt, dessen unterer
/// Rand [covered] über dem Bildschirmrand liegt. Nie negativ: Ist die
/// Tastatur niedriger als die Leiste, muss nichts ausweichen.
double keyboardInsetBelow(double keyboard, double covered) {
  if (!covered.isFinite || covered <= 0) return keyboard;
  return math.max(0, keyboard - covered);
}
