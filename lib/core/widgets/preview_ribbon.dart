import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../app_distribution.dart';

/// Markiert den automatisch deployten Entwicklungsstand (Vorschau-Kanal).
///
/// **Die wichtigere Hälfte des Vorschau-Kanals.** Der Verweis im Profil
/// führt hierher; dieser Streifen sorgt dafür, dass auch merkt, wer über
/// ein Lesezeichen, einen Link oder eine Suchmaschine hier landet. Ohne
/// ihn wäre die Vorschau von der echten App nicht zu unterscheiden — und
/// jemand meldete Fehler aus Code, den es so nie gegeben hat.
///
/// Als schmaler Streifen ÜBER dem Inhalt und nicht als Eckband: Ein
/// `Banner` in der Ecke läge über der Knopfspalte der Karte
/// und verdeckte dort Bedienelemente. Der Streifen kostet Höhe, und das
/// ist der ehrlichere Preis.
///
/// Im normalen Build ist er ein reiner Durchreicher. Über
/// [webChannelProvider] und nicht über die Konstante direkt: Die ist
/// `const` und im Test nicht umschaltbar — ein Streifen, dessen
/// Vorhandensein man nicht prüfen kann, ist keine Zusage.
class PreviewRibbon extends ConsumerWidget {
  const PreviewRibbon({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(webChannelProvider) != WebChannel.preview) return child;
    return Column(
      children: [
        Material(
          color: const Color(0xFF8A5A00),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.science_outlined,
                      size: 13, color: Colors.white),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      context.l10n.previewRibbon,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
