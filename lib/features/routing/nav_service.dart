// Die App-Seite der Dauerbenachrichtigung (#232 Schritt 2,
// Konzept-Routing 9.5): Routen-Datei und Brücke scharf schalten, den
// Dienst als Melder am Koordinator halten. Was im Dienst passiert, steht
// in `nav_notice.dart`.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/errors.dart';
import '../keep_alive/keep_alive.dart';
import '../rides/ride_providers.dart' show kRideTickInterval;
import '../rides/ride_task_handler.dart' show kRideDataDir;
import 'nav_notice.dart';

/// Die Brücke zum Dienst-Isolate. Eigene Naht wie `RideServiceBridge`:
/// Dahinter stecken `path_provider` und SharedPreferences, im
/// Widget-Test gibt es beide nicht.
abstract interface class NavServiceBridge {
  /// Legt die Route ab (`.part` + `rename`) und schaltet die Brücke an.
  /// Ein zweiter Aufruf mit derselben Linie (das Höhenprofil kam dazu)
  /// lässt dem Dienst seinen Stand.
  Future<void> arm(NavRouteData route);

  /// Brücke aus, Datei weg.
  Future<void> disarm();

  /// Eine Navigation, die der Dienst weiterführt, während die App neu
  /// startet — mit dem Stand, den er zuletzt gerechnet hat. Null, wenn
  /// keine läuft (auch nach einem Neustart des Geräts: dann steht die
  /// Brücke noch an, der Dienst aber nicht).
  Future<NavRouteData?> restore();
}

class PlatformNavServiceBridge implements NavServiceBridge {
  const PlatformNavServiceBridge();

  /// Im Browser gibt es keinen Dienst und keine Benachrichtigung (9.5).
  bool get _supported => !kIsWeb;

  @override
  Future<void> arm(NavRouteData route) async {
    if (!_supported) return;
    try {
      final base = (await getApplicationSupportDirectory()).path;
      final file = navRouteFile(base);
      await file.parent.create(recursive: true);
      final part = File('${file.path}.part');
      await part.writeAsString(route.encode(), flush: true);
      // Umbenennen statt überschreiben: Der Dienst liest dieselbe Datei
      // aus einem anderen Isolate und soll nie eine halbe sehen.
      await part.rename(file.path);
      final rev = await FlutterForegroundTask.getData<int>(key: kNavDataRev) ?? 0;
      await FlutterForegroundTask.saveData(key: kRideDataDir, value: base);
      await FlutterForegroundTask.saveData(key: kNavDataRev, value: rev + 1);
      await FlutterForegroundTask.saveData(key: kNavDataActive, value: true);
    } catch (e, stackTrace) {
      // Ohne Datei bleibt die Benachrichtigung beim Wartetext; die
      // Folgeansicht läuft trotzdem.
      logError('Navigation: Route für den Dienst ablegen', e, stackTrace);
    }
  }

  @override
  Future<void> disarm() async {
    if (!_supported) return;
    try {
      await FlutterForegroundTask.saveData(key: kNavDataActive, value: false);
      final file = navRouteFile((await getApplicationSupportDirectory()).path);
      if (await file.exists()) await file.delete();
    } catch (e, stackTrace) {
      logError('Navigation: Route des Dienstes löschen', e, stackTrace);
    }
  }

  @override
  Future<NavRouteData?> restore() async {
    if (!_supported) return null;
    try {
      if (await FlutterForegroundTask.getData<bool>(key: kNavDataActive) != true) return null;
      final file = navRouteFile((await getApplicationSupportDirectory()).path);
      if (!await FlutterForegroundTask.isRunningService || !await file.exists()) {
        // Liegen geblieben (Neustart des Geräts, Absturz): aufräumen statt
        // Stunden später eine alte Route aufzumachen.
        await disarm();
        return null;
      }
      final route = NavRouteData.decode(await file.readAsString());
      if (route == null) return null;
      final along = await FlutterForegroundTask.getData<double>(key: kNavDataAlong);
      return along == null ? route : route.withStart(along);
    } catch (e, stackTrace) {
      logError('Navigation: laufende Navigation zurückholen', e, stackTrace);
      return null;
    }
  }
}

final navServiceBridgeProvider = Provider<NavServiceBridge>((ref) => const PlatformNavServiceBridge());

/// Die Navigation als Melder am EINEN Dienst (9.5): Typ `location`, Takt
/// wie die Fahrt, ein Knopf „Navigation beenden". Kein zweiter Dienst,
/// keine zweite Benachrichtigung.
class NavKeepAlive {
  const NavKeepAlive(this._coordinator);

  static const key = 'nav';

  final KeepAliveCoordinator _coordinator;

  Future<void> start() async {
    await _coordinator.start(key, kNavNoticeWaiting,
        title: navNoticeTitle(recording: false),
        types: const {KeepAliveType.location},
        buttons: const [(id: kNavStopButton, text: kNavStopButtonText)]);
    await _coordinator.setRepeat(key, kRideTickInterval);
  }

  Future<void> stop() async {
    await _coordinator.setRepeat(key, null);
    await _coordinator.stop(key);
  }
}

final navKeepAliveProvider =
    Provider<NavKeepAlive>((ref) => NavKeepAlive(ref.watch(keepAliveCoordinatorProvider)));
