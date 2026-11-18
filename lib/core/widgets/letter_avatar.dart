import 'package:flutter/material.dart';

import '../app_colors.dart';

/// Ein Avatar mit dem ersten Buchstaben des Namens — als abgerundetes
/// Quadrat (Design 1k/1l).
///
/// Bewusst schlicht: TrailBuddy hat (noch) keinen Avatar-Katalog, und ein
/// Bild, das jeder gleich hätte, sagte weniger als der Buchstabe. Das Feld
/// `avatar` am Profil bleibt dafür frei — kommt ein Katalog, tauscht man
/// dieses Widget an EINER Stelle, nicht in jeder Liste.
///
/// Die Fläche: Lime für mich selbst (ohne [colorKey]), für andere eine
/// von [AppColors.avatarFills], fest je Nutzer-id — Lime heißt „mein",
/// wie auf der Karte, und steht deshalb nie an einem Buddy.
class LetterAvatar extends StatelessWidget {
  const LetterAvatar({
    super.key,
    required this.name,
    this.size = 40,
    this.colorKey,
  });

  final String name;
  final double size;

  /// Die Nutzer-id eines ANDEREN; `null` heißt: das bin ich.
  final String? colorKey;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final letter = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: avatarFillFor(colorKey),
        // 12 bei 40 dp — mit der Größe mitwachsend.
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontFamily: 'BarlowCondensed',
          fontSize: size * 0.5,
          fontWeight: FontWeight.w800,
          color: AppColors.onBrand,
          height: 1,
        ),
      ),
    );
  }
}

/// Die Fläche zu einer Nutzer-id: fest (nicht `String.hashCode`, das
/// über Läufe nicht zugesagt ist), `null` ist Lime.
Color avatarFillFor(String? key) {
  if (key == null) return AppColors.brand;
  var sum = 0;
  for (final c in key.codeUnits) {
    sum = (sum * 31 + c) & 0x3fffffff;
  }
  return AppColors.avatarFills[sum % AppColors.avatarFills.length];
}
