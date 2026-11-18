import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/widgets/trailbuddy_logo.dart';
import 'feature_highlights.dart';

/// Das Bild zu einem Eintrag (#135): das ECHTE Symbol der Funktion auf
/// einer Scheibe, unten rechts die Serpentine aus dem Logo.
///
/// **Aus Widgets gebaut, nicht aus Screenshots** — ein Screenshot veraltet
/// mit jeder Änderung an der Oberfläche; das Symbol hier IST das auf dem
/// Knopf. Anders als bei PilzBuddy steht es still: Es gibt keinen
/// Pilz-Buddy, der schaukeln könnte, und zwanzig bewegte Bilder in
/// „Entdecken" wären Unruhe. Damit gilt die Regel für reduzierte Bewegung
/// von selbst.
class HighlightArt extends StatelessWidget {
  const HighlightArt({super.key, required this.highlight, this.size = 64});

  final FeatureHighlight highlight;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final s = size;
    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.surface2,
              border: Border.all(color: p.line, width: s * 0.03),
            ),
            alignment: const Alignment(-0.12, -0.12),
            child: ExcludeSemantics(
              child: Icon(highlight.icon, size: s * 0.42, color: p.accentText),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: ExcludeSemantics(
              child: Container(
                padding: EdgeInsets.all(s * 0.04),
                decoration: BoxDecoration(
                  color: p.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: p.line),
                ),
                child: TrailBuddyMark(size: s * 0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
