import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../keep_alive/keep_alive.dart';

/// Der Foreground-Service der Fahrt (#28): hält den Prozess wach und
/// trägt das Isolate, in dem gemessen wird. Die Dauerbenachrichtigung IST
/// die Offenlegung gegenüber dem Nutzer — deshalb kein
/// `ACCESS_BACKGROUND_LOCATION`.
///
/// Seit Konzept-Schritt 3 EIN Verbraucher von zweien: Die Fahrt und der
/// Bereichs-Download teilen sich den Service über den
/// [KeepAliveCoordinator] (PilzBuddy #264) — zwei `stop()` auf einem
/// Service waren die Falle, die das Ende eines Downloads die Fahrt
/// beenden ließ.
abstract interface class RideService {
  /// Startet den Service mit dem Mess-Takt [every]; läuft er schon,
  /// werden nur die Texte erneuert.
  Future<void> start({required String title, required String text, required Duration every});

  Future<void> stop();
}

/// Titel und Text der Fahrt — die App setzt sie beim Start, der Dienst
/// beim Ende einer Navigation, die über einer Fahrt lief (#232).
const kRideNoticeTitle = 'Fahrt wird aufgezeichnet';
const kRideNoticeText = 'TrailBuddy zeichnet deinen Weg auf. Die Fahrt bleibt auf dem Gerät.';

/// Legt den Port an, über den das Service-Isolate den Main-Isolate
/// erreicht. **Gehört in `main()`, vor `runApp`** — ohne ihn ist die
/// Rückrichtung stumm: `sendDataToMain` findet `null` und verwirft die
/// Meldung, ohne Fehler, ohne Spur (PilzBuddy #465, vier Wochen lang).
void initRideCommunication() => initKeepAliveCommunication();

/// Die Fahrt als Melder am Koordinator: Typ `location`, mit Takt — die
/// Messung läuft IM Service-Isolate.
class CoordinatedRideService implements RideService {
  const CoordinatedRideService(this._coordinator);

  static const _key = 'ride';

  final KeepAliveCoordinator _coordinator;

  @override
  Future<void> start({required String title, required String text, required Duration every}) async {
    await _coordinator.start(_key, text, title: title, types: const {KeepAliveType.location});
    await _coordinator.setRepeat(_key, every);
  }

  @override
  Future<void> stop() async {
    await _coordinator.setRepeat(_key, null);
    await _coordinator.stop(_key);
  }
}

/// Tests überschreiben den Provider (`FakeRideService`).
final rideServiceProvider = Provider<RideService>(
    (ref) => CoordinatedRideService(ref.watch(keepAliveCoordinatorProvider)));
