// Die Naht zur Garmin-Uhr (docs/konzept-garmin.md, Abschnitt 3): auf
// Android Garmins Companion-SDK über den Kanal in `GarminBridge.kt`, im
// Web keine Uhr (A9, wie das Aufzeichnen). Dieselbe Bauweise wie
// `lib/core/screen_awake.dart`: Der Web-Weg ist die Vorgabe,
// `dart.library.io` wählt den Kanal. Tests ersetzen [garminBridgeProvider].
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'garmin_bridge_web.dart' if (dart.library.io) 'garmin_bridge_io.dart';

/// Die Kennung der Uhr-App aus `garmin/manifest.xml`; ein Test hält beide
/// zusammen.
const kWatchAppId = 'BC6A9EE033EF433F803B4AF7D36E9667';

/// Gegen den Connect-IQ-Simulator am Rechner statt eine echte Uhr
/// (`adb forward tcp:7381 tcp:7381`, Dev-App mit
/// `--dart-define=GARMIN_TETHERED=true`): Das SDK spricht dann über adb.
const kGarminTethered = bool.fromEnvironment('GARMIN_TETHERED');

/// Liegt unsere App auf der Uhr? Eine per USB geladene Entwickler-App
/// meldet Garmin Connect nicht immer — dann [unknown].
enum WatchApp { installed, notInstalled, unknown }

/// Was die Brücke über die Uhr weiß.
class WatchStatus {
  const WatchStatus({this.connect = false, this.device, this.app = WatchApp.unknown});

  static const none = WatchStatus();

  /// Garmin Connect ist installiert (ohne geht nichts).
  final bool connect;

  /// Name der ersten verbundenen Uhr, oder null.
  final String? device;
  final WatchApp app;

  /// Der Schalter „Auf der Uhr zeigen" steht nur dann (Konzept 3): eine
  /// verbundene Uhr, auf der unsere App nicht sicher fehlt.
  bool get canShow => connect && device != null && app != WatchApp.notInstalled;

  static WatchStatus fromChannel(Object? raw) {
    if (raw is! Map) return none;
    final app = switch (raw['app']) {
      'installed' => WatchApp.installed,
      'not_installed' => WatchApp.notInstalled,
      _ => WatchApp.unknown,
    };
    final device = raw['device'];
    return WatchStatus(connect: raw['connect'] == true, device: device is String ? device : null, app: app);
  }
}

/// Wie das Senden ausging: `SUCCESS` oder der Name des ersten Fehlers aus
/// dem SDK (`FAILURE_MESSAGE_TOO_LARGE`, `FAILURE_DEVICE_NOT_CONNECTED` …),
/// und wie viele Nachrichten angekommen sind.
class WatchSendResult {
  const WatchSendResult(this.status, this.sent);

  final String status;
  final int sent;

  bool get ok => status == 'SUCCESS';

  static WatchSendResult fromChannel(Object? raw) {
    if (raw is! Map) return const WatchSendResult('FAILURE_UNKNOWN', 0);
    final status = raw['status'], sent = raw['sent'];
    return WatchSendResult(status is String ? status : 'FAILURE_UNKNOWN', sent is int ? sent : 0);
  }
}

/// Was `openApplication` sagt (Betreiber 2026-11-04: das Handy stößt die
/// Uhr-App an, wenn die Navigation mit „Auf der Uhr zeigen" beginnt).
enum WatchOpen {
  /// Die App läuft schon — senden.
  running,

  /// Die Uhr fragt „TrailBuddy öffnen?" — die Route geht, sobald die App
  /// startet und sich meldet (`hi`).
  prompted,

  /// Unsere App liegt nicht auf der Uhr.
  notInstalled,

  /// Keine Frage gezeigt, keine Antwort, kein SDK: trotzdem senden — eine
  /// per USB geladene App meldet Garmin Connect nicht immer.
  unknown;

  static WatchOpen fromChannel(Object? raw) => switch (raw) {
        'APP_IS_ALREADY_RUNNING' => running,
        'PROMPT_SHOWN_ON_DEVICE' => prompted,
        'APP_IS_NOT_INSTALLED' => notInstalled,
        _ => unknown,
      };
}

abstract interface class GarminBridge {
  /// Gibt es den Weg auf dieser Plattform? Sonst fragt niemand.
  bool get supported;

  /// Startet beim ersten Aufruf das SDK. Ein Fehler ist [WatchStatus.none].
  Future<WatchStatus> status();

  /// Der Reihe nach an die verbundene Uhr.
  Future<WatchSendResult> send(List<Map<String, Object>> messages);

  /// Die Uhr-App öffnen (Garmins Frage auf der Uhr, wenn sie nicht läuft).
  Future<WatchOpen> open();

  /// Das SDK starten und auf die verbundene Uhr lauschen, OHNE die Uhr-App
  /// zu öffnen (#484: beim Start der App, sobald einmal eine Uhr gesehen
  /// wurde — sie schickt ihre Fahrten). true, wenn eine Uhr verbunden ist.
  Future<bool> listen();

  /// Was die Uhr zurückschickt: „gespeichert" (`ok`) und „hallo" (`hi`,
  /// Konzept 2).
  Stream<Object?> get messages;

  /// Die Uhr ist (wieder) verbunden — Garmin Connect meldet es, kein
  /// Abfragen im Takt.
  Stream<void> get connected;
}

final garminBridgeProvider = Provider<GarminBridge>((ref) => createGarminBridge());
