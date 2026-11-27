// Die Mitteilungen unterwegs auf dem iPhone (#644, Paket 3b): die Frage
// an einen Trail (#116) und die Airtime-Banner (#36) — dieselben
// Benachrichtigungen wie auf Android, mit den Einstellungen, die iOS
// braucht.
//
// **Knöpfe hängen auf iOS an einer Kategorie**, nicht an der einzelnen
// Mitteilung, und die Kategorien setzt `flutter_local_notifications` NUR
// beim `initialize`. Deshalb steht hier je Knopfsatz eine Kategorie, mit
// denselben Kennungen wie die `AndroidNotificationAction`s — der Weg der
// Antwort (`handleConfirmResponse`, `handleWheelieResponse`) bleibt einer.
//
// **Keine Frage nach der Erlaubnis beim Einrichten**: `initialize` fragte
// ab Werk sofort (Ton, Hinweis, Kennzeichen), also schon beim App-Start.
// Gefragt wird erst beim Start einer Fahrt ([requestRideNoticePermission]).
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../l10n/l10n.dart';
import 'ride_confirm.dart' show ConfirmChoice;
import 'wheelie_notify.dart';

/// Frage an einen Trail: „Stimmt" und „Ändern…".
const kConfirmCategory = 'tb.confirm';

/// Frage an einen Trail mit warnender Meldung: dazu „Trail ist frei".
const kConfirmFreeCategory = 'tb.confirm.free';

const kWheelieCategory = 'tb.wheelie';
const kJumpCategory = 'tb.jump';
const kStoppieCategory = 'tb.stoppie';

/// Die Mitteilung „… verpasst" mit drei Knöpfen.
const kMissedCategory = 'tb.missed';

/// Alle Mitteilungen einer Fahrt stehen als ein Stapel.
const kRideNoticeThread = 'ride';

/// Die Knopfsätze, je Kategorie in der Reihenfolge der Android-Knöpfe.
/// Nur „Ändern…" öffnet die App; alles andere antwortet im Hintergrund —
/// die Hand ist am Lenker.
List<DarwinNotificationCategory> rideNoticeCategories(AppLocalizations l) {
  DarwinNotificationAction plain(String id, String title) =>
      DarwinNotificationAction.plain(id, title);
  final change = DarwinNotificationAction.plain(
    ConfirmChoice.change.id,
    l.confirmChange,
    options: {DarwinNotificationActionOption.foreground},
  );
  final yes = plain(ConfirmChoice.confirm.id, l.confirmYes);
  return [
    DarwinNotificationCategory(kConfirmCategory, actions: [yes, change]),
    DarwinNotificationCategory(
      kConfirmFreeCategory,
      actions: [yes, plain(ConfirmChoice.free.id, l.confirmFree), change],
    ),
    DarwinNotificationCategory(
      kWheelieCategory,
      actions: [
        plain(kWheelieYes, l.wheelieNoticeYes),
        plain(kWheelieNo, l.wheelieNoticeNo),
      ],
    ),
    DarwinNotificationCategory(
      kJumpCategory,
      actions: [
        plain(kJumpYes, l.wheelieNoticeYes),
        plain(kJumpNo, l.wheelieNoticeNo),
      ],
    ),
    DarwinNotificationCategory(
      kStoppieCategory,
      actions: [
        plain(kStoppieYes, l.wheelieNoticeYes),
        plain(kStoppieNo, l.wheelieNoticeNo),
      ],
    ),
    DarwinNotificationCategory(
      kMissedCategory,
      actions: [
        plain(kWheelieMissed, l.wheelieMissedButton),
        plain(kJumpMissed, l.jumpMissedButton),
        plain(kStoppieMissed, l.stoppieMissedButton),
      ],
    ),
  ];
}

/// Die Einrichtung für iOS: Kategorien ja, Frage nach der Erlaubnis nein.
DarwinInitializationSettings rideNoticeDarwinSettings(AppLocalizations l) =>
    DarwinInitializationSettings(
      requestAlertPermission: false,
      requestSoundPermission: false,
      requestBadgePermission: false,
      notificationCategories: rideNoticeCategories(l),
    );

/// Eine Mitteilung der Fahrt auf iOS. Auch bei offener App ein Banner (wie
/// das Heads-up auf Android); [passive] nur in der Liste, ohne Ton — für
/// „… verpasst", das auf Android leise steht.
DarwinNotificationDetails rideNoticeDarwin(
  String category, {
  bool passive = false,
}) => DarwinNotificationDetails(
  categoryIdentifier: category,
  threadIdentifier: kRideNoticeThread,
  presentAlert: !passive,
  presentBanner: !passive,
  presentList: true,
  presentSound: !passive,
  interruptionLevel: passive
      ? InterruptionLevel.passive
      : InterruptionLevel.active,
);
