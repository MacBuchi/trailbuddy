// Die Wheelie-, Sprung- und Stoppie-Messung mit Rückmeldung (#36, Konzept
// Airtime 9, Schritte 2b, 4 und 4b; am Schalter der Rohdaten): Nach jedem erkannten
// Ereignis ein Banner mit „Stimmt" und „War keiner", dazu eine stehende
// Benachrichtigung mit „Wheelie verpasst", „Sprung verpasst" und „Stoppie
// verpasst" — mehr als drei Knöpfe zeigt Android nicht. Jede Antwort ist eine Zeile in den Rohdaten der Fahrt
// (`sensor_log.dart`), das Werkzeug (`tool/airtime_measure.py`) zählt
// daraus Treffer, Fehlalarme und Verpasste je Schwelle.
//
// Gezeigt wird aus dem Service-Isolate, beantwortet ohne Oberfläche — die
// Hand ist am Lenker. Der Weg ist der der Frage an einen Trail
// (`ride_confirm_notify.dart`): dasselbe Plugin, derselbe Kanal, derselbe
// Hintergrund-Empfänger, der hier nachfragt ([handleWheelieResponse]).
//
// Die Antwort hängt das Isolate des Pakets an die Datei, während der
// Logger im Dienst ebenfalls anhängt. Beide schreiben je Aufruf eine
// kurze Zeile mit `FileMode.append`; für ein Mess-Werkzeug reicht das.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../l10n/l10n.dart';
import 'ride_confirm_notify.dart';
import 'sensor_fusion.dart';
import 'sensor_log.dart';

const kWheelieYes = 'wheelie_yes';
const kWheelieNo = 'wheelie_no';
const kWheelieMissed = 'wheelie_missed';
const kJumpYes = 'jump_yes';
const kJumpNo = 'jump_no';
const kJumpMissed = 'jump_missed';
const kStoppieYes = 'stoppie_yes';
const kStoppieNo = 'stoppie_no';
const kStoppieMissed = 'stoppie_missed';

const _actions = {
  kWheelieYes, kWheelieNo, kWheelieMissed, kJumpYes, kJumpNo, kJumpMissed, //
  kStoppieYes, kStoppieNo, kStoppieMissed,
};
const _missedActions = {kWheelieMissed, kJumpMissed, kStoppieMissed};

/// Die stehende Benachrichtigung „Wheelie verpasst" — eine je Gerät.
const kWheelieMissedNotificationId = 0x57484c;

/// Was der Logger zeigt; im Test gegen eine Liste getauscht.
abstract class WheelieNotices {
  Future<void> wheelie(WheelieEvent event, {required String file});
  Future<void> jump(JumpEvent event, {required String file});
  Future<void> stoppie(StoppieEvent event, {required String file});
  Future<void> showMissed({required String file});
  Future<void> cancelMissed();

  static const WheelieNotices platform = _PlatformWheelieNotices();
}

String encodeWheeliePayload({required String file, int? startUs}) =>
    jsonEncode({'w': file, 's': ?startUs});

({String file, int? startUs})? decodeWheeliePayload(String? text) {
  if (text == null) return null;
  try {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) return null;
    final file = json['w'], start = json['s'];
    if (file is! String || (start != null && start is! int)) return null;
    return (file: file, startUs: start as int?);
  } catch (_) {
    return null;
  }
}

/// Je Wheelie eine eigene Kennung, damit ein zweites Banner das erste
/// nicht ersetzt — die Antwort kommt oft erst an der nächsten Ampel.
int wheelieNotificationId(int startUs) => (startUs ~/ 1000) & 0x7fffffff;

/// Ein Sprung und ein Wheelie in derselben Millisekunde ersetzen sich nicht.
int jumpNotificationId(int startUs) => (startUs ~/ 1000 + 1) & 0x7fffffff;

/// Ebenso ein Stoppie.
int stoppieNotificationId(int startUs) => (startUs ~/ 1000 + 2) & 0x7fffffff;

/// Schreibt die Antwort in die Rohdaten. `false`, wenn die
/// Benachrichtigung nicht von der Wheelie-Messung kam. Wirft nie.
Future<bool> handleWheelieResponse({
  required String? actionId,
  required String? payload,
  DateTime? now,
  Future<void> Function()? confirmMissed,
}) async {
  if (!_actions.contains(actionId)) return decodeWheeliePayload(payload) != null;
  try {
    final p = decodeWheeliePayload(payload);
    if (p == null) return true;
    final at = (now ?? DateTime.now()).toUtc();
    final start = p.startUs;
    final line = switch (actionId) {
      kWheelieMissed => wheelieMissedLine(at),
      kJumpMissed => jumpMissedLine(at),
      kStoppieMissed => stoppieMissedLine(at),
      _ when start == null => null,
      kWheelieYes || kWheelieNo => wheelieAnswerLine(at, startUs: start, yes: actionId == kWheelieYes),
      kStoppieYes || kStoppieNo => stoppieAnswerLine(at, startUs: start, yes: actionId == kStoppieYes),
      _ => jumpAnswerLine(at, startUs: start, yes: actionId == kJumpYes),
    };
    if (line == null) return true;
    await File(p.file).writeAsString(line, mode: FileMode.append, flush: true);
    if (_missedActions.contains(actionId)) {
      await (confirmMissed ?? () => _showMissed(file: p.file, notedAt: at))();
    }
  } catch (_) {
    // Messwerkzeug: Die Antwort fehlt dann in der Auswertung, sonst nichts.
  }
  return true;
}

/// Eine Antwort aus der offenen App (#36, die Live-Ansicht): dieselbe
/// Zeile wie der Knopf im Banner — und das Banner geht weg, sonst stünde
/// die Frage zweimal. Wirft nie.
Future<void> answerAirtimeInApp(
    {required String actionId, required String file, int? startUs, int? notificationId}) async {
  await handleWheelieResponse(actionId: actionId, payload: encodeWheeliePayload(file: file, startUs: startUs));
  if (notificationId == null) return;
  try {
    await initRideNotices();
    await rideNoticesPlugin.cancel(id: notificationId);
  } catch (_) {
    // Bleibt es stehen, schreibt ein Tipp darauf eine zweite Antwort; das
    // Werkzeug nimmt die letzte.
  }
}

String _num(AppLocalizations l, double v, int digits) {
  final text = v.toStringAsFixed(digits);
  return l.localeName.startsWith('de') ? text.replaceAll('.', ',') : text;
}

class _PlatformWheelieNotices implements WheelieNotices {
  const _PlatformWheelieNotices();

  @override
  Future<void> wheelie(WheelieEvent event, {required String file}) async {
    try {
      await initRideNotices();
      final l = serviceL10n();
      final body = l.wheelieNoticeBody(
          _num(l, event.duration.inMilliseconds / 1000, 1),
          _num(l, event.lengthM, 0),
          _num(l, event.maxTiltDeg, 0));
      await rideNoticesPlugin.show(
        id: wheelieNotificationId(event.startUs),
        title: l.wheelieNoticeTitle,
        body: body,
        payload: encodeWheeliePayload(file: file, startUs: event.startUs),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            kConfirmChannelId,
            kConfirmChannelName,
            importance: Importance.high,
            priority: Priority.high,
            when: event.startUs ~/ 1000,
            showWhen: true,
            actions: [
              AndroidNotificationAction(kWheelieYes, l.wheelieNoticeYes, cancelNotification: true),
              AndroidNotificationAction(kWheelieNo, l.wheelieNoticeNo, cancelNotification: true),
            ],
          ),
        ),
      );
    } catch (_) {
      // Kein Kanal, keine Berechtigung: Der Wheelie steht trotzdem in der
      // Datei, nur ohne Antwort.
    }
  }

  @override
  Future<void> jump(JumpEvent event, {required String file}) async {
    try {
      await initRideNotices();
      final l = serviceL10n();
      final seconds = _num(l, event.duration.inMilliseconds / 1000, 2);
      final g = _num(l, event.landingG, 1);
      await rideNoticesPlugin.show(
        id: jumpNotificationId(event.startUs),
        title: l.jumpNoticeTitle,
        body: event.plausible ? l.jumpNoticeBody(seconds, g) : l.jumpNoticeBodyImplausible(seconds, g),
        payload: encodeWheeliePayload(file: file, startUs: event.startUs),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            kConfirmChannelId,
            kConfirmChannelName,
            importance: Importance.high,
            priority: Priority.high,
            when: event.startUs ~/ 1000,
            showWhen: true,
            actions: [
              AndroidNotificationAction(kJumpYes, l.wheelieNoticeYes, cancelNotification: true),
              AndroidNotificationAction(kJumpNo, l.wheelieNoticeNo, cancelNotification: true),
            ],
          ),
        ),
      );
    } catch (_) {
      // Wie beim Wheelie: Der Sprung steht trotzdem in der Datei.
    }
  }

  @override
  Future<void> stoppie(StoppieEvent event, {required String file}) async {
    try {
      await initRideNotices();
      final l = serviceL10n();
      final body = l.stoppieNoticeBody(_num(l, event.duration.inMilliseconds / 1000, 1),
          _num(l, event.maxTiltDeg, 0), _num(l, event.decel, 1));
      await rideNoticesPlugin.show(
        id: stoppieNotificationId(event.startUs),
        title: l.stoppieNoticeTitle,
        body: body,
        payload: encodeWheeliePayload(file: file, startUs: event.startUs),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            kConfirmChannelId,
            kConfirmChannelName,
            importance: Importance.high,
            priority: Priority.high,
            when: event.startUs ~/ 1000,
            showWhen: true,
            actions: [
              AndroidNotificationAction(kStoppieYes, l.wheelieNoticeYes, cancelNotification: true),
              AndroidNotificationAction(kStoppieNo, l.wheelieNoticeNo, cancelNotification: true),
            ],
          ),
        ),
      );
    } catch (_) {
      // Wie beim Wheelie: Der Stoppie steht trotzdem in der Datei.
    }
  }

  @override
  Future<void> showMissed({required String file}) => _showMissed(file: file);

  @override
  Future<void> cancelMissed() async {
    try {
      await initRideNotices();
      await rideNoticesPlugin.cancel(id: kWheelieMissedNotificationId);
    } catch (_) {
      // Bleibt sie stehen, schreibt ein Tipp in die Datei der letzten Fahrt.
    }
  }
}

/// Die stehende Benachrichtigung; nach einem Tipp mit der Uhrzeit, damit
/// man sieht, dass er angekommen ist.
Future<void> _showMissed({required String file, DateTime? notedAt}) async {
  try {
    await initRideNotices();
    final l = serviceL10n();
    final local = notedAt?.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final body = local == null
        ? l.wheelieMissedBody
        : l.wheelieMissedNoted('${two(local.hour)}:${two(local.minute)}:${two(local.second)}');
    await rideNoticesPlugin.show(
      id: kWheelieMissedNotificationId,
      title: l.wheelieMissedTitle,
      body: body,
      payload: encodeWheeliePayload(file: file),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          kConfirmChannelId,
          kConfirmChannelName,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          silent: true,
          actions: [
            AndroidNotificationAction(kWheelieMissed, l.wheelieMissedButton, cancelNotification: false),
            AndroidNotificationAction(kJumpMissed, l.jumpMissedButton, cancelNotification: false),
            AndroidNotificationAction(kStoppieMissed, l.stoppieMissedButton, cancelNotification: false),
          ],
        ),
      ),
    );
  } catch (_) {
    // Ohne den Knopf fehlen nur die verpassten Wheelies in der Auswertung.
  }
}
