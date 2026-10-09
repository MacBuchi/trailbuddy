import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../core/errors.dart';
import '../rides/ride_task_handler.dart';
import 'keep_alive.dart';

/// Der Einstiegspunkt des Service-Isolates. Der Service hat genau EINEN,
/// also trägt ein Handler beide Fälle: Für einen Bereichs-Download tut er
/// nichts (der läuft im Main-Isolate, gebraucht wird die Prozess-
/// Priorität), für eine Fahrt misst er — solange die Brücke
/// (`kRideDataActive`) „aktiv" sagt.
@pragma('vm:entry-point')
void startKeepAliveService() => FlutterForegroundTask.setTaskHandler(RideTaskHandler());

void initKeepAliveCommunicationImpl() => FlutterForegroundTask.initCommunicationPort();

/// Der Manifest-Eintrag, unter dem das Symbol der Meldung steht. Das
/// Plugin sucht das Drawable NUR über diesen Namen; ein Tippfehler auf
/// einer Seite liefert stumm die Ressourcen-id 0 — und damit das
/// Launcher-Icon als weißen Klotz (PilzBuddy #331). Ein Test hält den
/// Namen hier und im Manifest zusammen.
const keepAliveNotificationIconMetaData = 'de.mcbuchi.trailbuddy.RIDE_NOTIFICATION_ICON';

class _ForegroundKeepAlive implements KeepAlive {
  static const _serviceId = 2801;
  bool _initialized = false;

  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// `allowWakeLock`: Ohne ihn schläft die CPU zwischen den Takten, und
  /// die Fahrt bekäme ihre Messungen gebündelt beim nächsten Aufwachen.
  /// `allowWifiLock` für den Download.
  static ForegroundTaskOptions _options(Duration? every) => ForegroundTaskOptions(
        eventAction: every == null
            ? ForegroundTaskEventAction.nothing()
            : ForegroundTaskEventAction.repeat(every.inMilliseconds),
        allowWakeLock: true,
        allowWifiLock: true,
      );

  void _initOnce() {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        // Die Kanal-ID bleibt die der Fahrt: Eine neue legte einen zweiten
        // Eintrag in den Systemeinstellungen an und ließe den alten als
        // Leiche zurück. Name und Beschreibung nennen beide Nutzer.
        channelId: 'ride_recording',
        channelName: 'Fahrt und Downloads',
        channelDescription:
            'Läuft, solange eine Fahrt aufgezeichnet oder ein Kartenbereich gespeichert wird.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: _options(null),
    );
    _initialized = true;
  }

  /// Leer heißt „keine Knöpfe" — `null` ließe dem Paket die alten.
  static List<NotificationButton> _buttons(List<KeepAliveButton> buttons) =>
      [for (final b in buttons) NotificationButton(id: b.id, text: b.text)];

  @override
  Future<void> start(String title, String text, Set<KeepAliveType> types,
      {List<KeepAliveButton> buttons = const []}) async {
    if (!_supported) return;
    try {
      _initOnce();
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
            notificationTitle: title, notificationText: text, notificationButtons: _buttons(buttons));
        return;
      }
      // Ohne die Berechtigung läuft der Service trotzdem, nur ohne
      // sichtbare Meldung — ein abgelehnter Dialog ist kein Grund
      // abzubrechen.
      await FlutterForegroundTask.requestNotificationPermission();
      // Seit flutter_foreground_task 9 WIRFT `startService` nicht mehr,
      // ein Fehlschlag kommt nur im Ergebnis — bis 0.108.0 ging er hier
      // still unter.
      final result = await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        // Je Start entschieden: Ein Download nennt `dataSync`, eine Fahrt
        // `location`. Einen Typ zu nennen, den dieser Lauf nicht braucht,
        // wäre gegenüber Play eine falsche Angabe; das Manifest deklariert
        // beide als Obermenge dessen, was vorkommen KANN.
        serviceTypes: [
          for (final type in types)
            switch (type) {
              KeepAliveType.dataSync => ForegroundServiceTypes.dataSync,
              KeepAliveType.location => ForegroundServiceTypes.location,
            },
        ],
        notificationIcon: const NotificationIcon(metaDataName: keepAliveNotificationIconMetaData),
        notificationTitle: title,
        notificationText: text,
        notificationButtons: _buttons(buttons),
        callback: startKeepAliveService,
      );
      if (result case ServiceRequestFailure(:final error)) {
        logError('Foreground-Service starten', error, StackTrace.current);
      }
    } catch (e, stackTrace) {
      logError('Foreground-Service starten', e, stackTrace);
    }
  }

  @override
  Future<void> update(String title, String text, {List<KeepAliveButton> buttons = const []}) async {
    if (!_supported) return;
    try {
      if (!await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.updateService(
          notificationTitle: title, notificationText: text, notificationButtons: _buttons(buttons));
    } catch (e, stackTrace) {
      logError('Foreground-Service: Meldung aktualisieren', e, stackTrace);
    }
  }

  @override
  Future<void> setRepeat(Duration? every) async {
    if (!_supported) return;
    try {
      if (!await FlutterForegroundTask.isRunningService) return;
      // Anders als die Typen lässt sich der Takt am laufenden Service
      // ändern — deshalb braucht die Fahrt dafür keinen Neustart.
      await FlutterForegroundTask.updateService(foregroundTaskOptions: _options(every));
    } catch (e, stackTrace) {
      logError('Foreground-Service: Takt setzen', e, stackTrace);
    }
  }

  @override
  Future<void> stop() async {
    if (!_supported) return;
    try {
      if (!await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.stopService();
    } catch (e, stackTrace) {
      logError('Foreground-Service beenden', e, stackTrace);
    }
  }
}

KeepAlive createKeepAlive() => _ForegroundKeepAlive();
