import 'package:flutter_map/flutter_map.dart';

import '../../core/errors.dart';

/// Verwirft Kamerabewegungen, deren Ergebnis nicht endlich ist (NaN oder
/// ±Infinity in Zoom, Center oder Rotation).
///
/// Jede Kamerabewegung — auch die aus Gesten — läuft durch
/// `MapOptions.cameraConstraint.constrain()`; gibt sie `null` zurück, bleibt
/// die Kamera auf dem letzten guten Zustand (`moveRaw` in flutter_maps
/// map_controller_impl.dart). Ohne diesen Wächter reicht EIN nicht-endlicher
/// Kamerazustand aus einem Gesten-Grenzfall, um beides auszulösen
/// (#151/#141, Beweiskette im Issue):
///
/// - `TileLayer` wirft „Infinity or NaN toInt" in der Kachelberechnung —
///   61 Feldberichte allein in KW30, und sichtbar als graue Flächen, weil
///   keine Kacheln mehr angefordert werden;
/// - `MarkerLayer` wiederholt jeden Marker über alle Weltkopien und prüft
///   den Abbruch per `Rect.overlaps` — mit NaN ist der IEEE-Vergleich immer
///   wahr, die Schleife endet nie, und der Allokationssturm (gemessen
///   ~150 MB/s, 134 MB → 3,8 GB in 24 s) erstickt den Haupt-Thread im GC:
///   die ANRs aus #151.
class FiniteCameraConstraint extends CameraConstraint {
  const FiniteCameraConstraint();

  /// Einmal pro Prozess melden, wenn der Wächter greift: der Beleg im
  /// Wochendigest, dass der Gesten-Grenzfall real auftritt — ohne bei einer
  /// kaputten Gesten-Serie den Digest zu fluten (Lehre aus #124/#136).
  static bool _reported = false;

  @override
  MapCamera? constrain(MapCamera camera) {
    if (camera.zoom.isFinite &&
        camera.center.latitude.isFinite &&
        camera.center.longitude.isFinite &&
        camera.rotation.isFinite) {
      return camera;
    }
    if (!_reported) {
      _reported = true;
      logError(
        'Kamera-Bewegung verworfen',
        StateError(
          'Nicht-endliche Kamera: zoom=${camera.zoom} '
          'center=${camera.center} rotation=${camera.rotation}',
        ),
        StackTrace.current,
      );
    }
    return null;
  }
}
