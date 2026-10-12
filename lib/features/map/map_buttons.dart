// Die Knöpfe über der Karte (Design Turn 3, Spezifikation 3e): rund, 44 px
// — Mindest-Trefferfläche, auch mit Handschuh —, Fläche mit feinem Rand und
// Schatten, damit sie auf jedem Kartengrund stehen. Ein Knopf, dessen Menü
// gerade offen ist, trägt einen Rand in der Marke: So sieht man, zu welchem
// Knopf die linke Leiste gehört.
import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../l10n/l10n.dart';

/// Kantenlänge der runden Kartenknöpfe und der Leistenknöpfe.
const kMapButtonSize = 44.0;

/// So viel Platz halten die Banner oben rechts frei (#180): die Glühbirne
/// samt 8 dp Luft. Konstant, auch ohne Banner — nichts springt, wenn eines
/// kommt.
const kBannerRightInset = kMapButtonSize + 8;

/// Der Aufnahmeknopf ist größer: die Hauptaktion der Karte.
const kRecordButtonSize = 60.0;

const _shadow = [BoxShadow(blurRadius: 6, offset: Offset(0, 2), color: Color(0x33000000))];

class MapRoundButton extends StatelessWidget {
  const MapRoundButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.dark = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  /// Sein Menü ist offen: Rand in der Marke.
  final bool active;

  /// Immer dunkel, egal welcher Modus — die Folgeansicht der Navigation
  /// (Design 13: Leisten im Nav-Modus dunkel über der hellen Karte).
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final p = dark ? AppColors.dark : AppPalette.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: _shadow),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        isSelected: active,
        icon: Icon(icon, size: 22),
        style: IconButton.styleFrom(
          fixedSize: const Size.square(kMapButtonSize),
          minimumSize: const Size.square(kMapButtonSize),
          padding: EdgeInsets.zero,
          // 44 ist schon die Trefferfläche; Material polsterte sonst auf 48.
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: p.surface,
          foregroundColor: p.text,
          side: BorderSide(
            color: active ? p.brandMark : p.line,
            width: active ? 2.5 : 1,
          ),
        ),
      ),
    );
  }
}

/// Aufnahme: Lime mit dunklem Punkt; läuft die Fahrt, Orange mit
/// Stop-Quadrat.
class RecordButton extends StatelessWidget {
  const RecordButton({super.key, required this.recording, required this.onPressed});

  final bool recording;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final bg = recording ? AppColors.mapLines.warning : AppColors.brand;
    final fg = recording ? Colors.white : AppColors.onBrand;
    return DecoratedBox(
      decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: _shadow),
      child: IconButton(
        tooltip: recording ? context.l10n.rideStopTooltip : context.l10n.rideRecordTooltip,
        onPressed: onPressed,
        icon: Icon(recording ? Icons.stop_rounded : Icons.circle, size: recording ? 30 : 22),
        style: IconButton.styleFrom(
          fixedSize: const Size.square(kRecordButtonSize),
          minimumSize: const Size.square(kRecordButtonSize),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: bg,
          foregroundColor: fg,
        ),
      ),
    );
  }
}
