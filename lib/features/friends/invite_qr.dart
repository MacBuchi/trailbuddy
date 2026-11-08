import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/app_colors.dart';
import '../../core/app_info.dart';
import '../../core/widgets/trailbuddy_logo.dart';
import '../../l10n/l10n.dart';

/// Größe des Codes und des Logo-Felds darin (#496).
///
/// Das Logo sitzt über den Modulen in der Mitte. Die Fehlerkorrektur H
/// ersetzt etwa 30 % der Codewörter; das Feld deckt nur rund ein Zehntel
/// der Fläche ab, damit der Code trotz Logo scanbar bleibt.
const double qrCodeSide = 220;
const double qrQuietZone = 10; // der Rand, den QrImageView frei lässt
const double qrLogoSide = 72;

/// Einladung zeigen (#496): QR für das Telefon nebenan, Text für alles andere.
///
/// Der QR trägt keine Versionsnummer und keinen Downloadlink — nur die
/// Invite-Adresse. Was darunter geladen wird, entscheidet `web/install.html`.
/// Deshalb bleibt jeder gezeigte QR gültig, auch wenn die App später im Play
/// Store steht (#39): dann führt [AppInfo.inviteUrl] dort hin, und kein QR
/// muss neu gemacht werden.
Future<void> showInviteDialog(
  BuildContext context, {
  required String? username,
  required Future<void> Function() shareText,
}) {
  final l = context.l10n;
  final palette = AppPalette.of(context);
  // Der QR hängt nicht am Erscheinungsbild: ein helles Muster auf dunklem
  // Grund wird im Zweifel nicht erkannt. Deshalb immer das helle Paar — wie
  // die Karte, die auch im dunklen Modus hell bleibt.
  final light = AppColors.light;
  final url = AppInfo.inviteUrl(username);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l.buddysInviteQrTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Die Größe steht außen: QrImageView misst sich selbst über einen
          // LayoutBuilder, und eine Column rechnet intrinsische Höhen.
          SizedBox(
            width: qrCodeSide,
            height: qrCodeSide,
            child: Stack(
              children: [
                QrImageView(
                  data: url,
                  backgroundColor: light.surface,
                  eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: light.text),
                  dataModuleStyle: QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: light.text,
                  ),
                  // H, nicht L: das Logo in der Mitte zerstört Module, und
                  // die Korrektur muss sie ersetzen können.
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                ),
                Positioned(
                  left: (qrCodeSide - qrLogoSide) / 2,
                  top: (qrCodeSide - qrLogoSide) / 2,
                  child: SizedBox.square(
                    dimension: qrLogoSide,
                    // Das Feld unter dem Logo bleibt hell: Module, die das
                    // Logo nicht malt, würden sonst wie Daten gelesen.
                    child: Container(
                      color: light.surface,
                      child: TrailBuddyMark(
                        size: qrLogoSide - 12,
                        color: light.brandMark,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(url, style: TextStyle(color: palette.muted)),
          const SizedBox(height: 8),
          Text(l.buddysInviteQrHint, style: TextStyle(color: palette.muted)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(l.commonClose),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(dialogContext);
            shareText();
          },
          child: Text(l.buddysInviteShareText),
        ),
      ],
    ),
  );
}
