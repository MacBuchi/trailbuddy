/// Licht- und Näherungssensor für die Sensor-Rohdaten (#491). Nur Android;
/// anderswo und ohne Sensor ein leerer Strom. Die Werte tragen die Zeit
/// des Sensors in µs seit 1970 an erster Stelle (wie `sensors_plus`).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Die Namen stehen auch in `TbAmbientPlugin.java`;
/// `android_manifest_test` hält beide zusammen.
const kAmbientLightChannel = 'de.mcbuchi.trailbuddy/ambient_light';
const kAmbientProximityChannel = 'de.mcbuchi.trailbuddy/ambient_proximity';

/// `[t_us, lux]` bei jeder Änderung.
Stream<List<double>> ambientLightStream() => _stream(kAmbientLightChannel);

/// `[t_us, Abstand cm, größter Abstand cm]` bei jeder Änderung.
Stream<List<double>> ambientProximityStream() =>
    _stream(kAmbientProximityChannel);

Stream<List<double>> _stream(String name) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return const Stream.empty();
  }
  return EventChannel(name).receiveBroadcastStream().map(
    (v) => [for (final x in v as List) (x as num).toDouble()],
  );
}
