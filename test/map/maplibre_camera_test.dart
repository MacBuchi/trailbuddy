// Die Kamera der MapLibre-Engine (#68): Die Platform-View läuft im
// Widget-Test nicht, also hält dieser Test die Zusage am Quelltext fest.
// MapLibre Android wirft in `animateCamera`/`easeCamera` bei einer Dauer
// ≤ 0 ms („Null duration passed into animateCamera", MapLibreMap.java),
// und `fitBounds` des Pakets läuft genau darüber. Zehn Berichte in
// 0.17–0.20, bei jedem Einpassen. Die Engine setzt die Kamera deshalb nur
// über `moveCamera` (ohne Dauer), die Einpass-Rechnung ist `cameraToFit`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File(
    'lib/features/map/map_view/maplibre_map_view.dart',
  ).readAsStringSync();
  // Kommentare zählen nicht — dort darf der alte Weg erklärt stehen.
  final code = src
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  test('kein fitBounds, kein animateCamera, keine Dauer von null', () {
    expect(code, isNot(contains('.fitBounds(')));
    expect(code, isNot(contains('.animateCamera(')));
    expect(code, isNot(contains('.easeCamera(')));
    expect(code, isNot(contains('Duration.zero')));
  });

  test(
    'eingepasst wird über die gemeinsame Rechnung, gesetzt über moveCamera',
    () {
      expect(code, contains('cameraToFit('));
      expect(code, contains('.moveCamera('));
      // Die Fassade zählt in 256er-Stufen, MapLibre in 512ern.
      expect(code, contains('zoom: zoom - 1'));
    },
  );
}
