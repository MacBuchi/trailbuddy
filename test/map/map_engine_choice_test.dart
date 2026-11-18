// Die Engine-Wahl der MapView-Fassade: **Android MapLibre, Web
// flutter_map** — ohne Schalter dazwischen (PilzBuddy hat seinen nach
// zehn stillen Wochendigests ausgebaut, #433). Was NICHT verschwindet, ist
// `flutter_map_view.dart`: Der Android-Build trägt es weiter, weil die
// MapLibre-Ansicht selbst darauf zurückfällt, wenn der Style nicht baut.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/map/map_view/maplibre_map_view.dart';

void main() {
  const config = MapViewConfig(
    initialCenter: LatLng(48.8, 10.5),
    initialZoom: 6,
    minZoom: 3,
    maxZoom: 19,
    backgroundColor: AppColors.mapBackground,
  );

  test('Android bekommt MapLibre', () {
    // `kIsWeb` ist eine Kompilierzeit-Konstante, und dieser Test läuft
    // auf der VM — dort ist sie falsch, die Fassade wählt also den
    // Android-Zweig. Der Web-Zweig ist von hier aus nicht erreichbar.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = MapViewController(
      initialCenter: config.initialCenter,
      initialZoom: 6,
    );
    expect(
      container.read(mapViewBuilderProvider)(
        config,
        controller,
        const MapViewLayers(),
      ),
      isA<MapLibreMapView>(),
    );
  });

  test('die alte Engine bleibt als Rückfall IM Android-Build', () {
    final native = File(
      'lib/features/map/map_view/maplibre_map_view.dart',
    ).readAsStringSync();
    expect(
      native,
      contains('return FlutterMapView('),
      reason: 'ohne Style lieber die alte Karte als gar keine',
    );
  });

  test('der Web-Build sieht package:maplibre nie', () {
    // Der bedingte Import ist die Zusage — ein direkter Import irgendwo
    // sonst in lib/ zöge das native Paket in den Web-Build.
    final facade = File(
      'lib/features/map/map_view/map_view.dart',
    ).readAsStringSync();
    expect(
      facade,
      // Leerraum frei: Wie `dart format` den Import umbricht, ist egal.
      matches(
        RegExp(
          r"import 'maplibre_view_stub\.dart'\s+"
          r"if \(dart\.library\.io\) 'maplibre_map_view\.dart';",
        ),
      ),
    );
    final importers = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains("package:maplibre/"))
        .map((f) => f.path.replaceAll('\\', '/'))
        .toList();
    expect(importers..sort(), [
      // Der Abgleich der Ebenen (Feldbericht 2026-10-02) — gebraucht NUR
      // von der MapLibre-Engine, also ebenfalls hinter dem bedingten Import.
      'lib/features/map/map_view/keyed_layers.dart',
      'lib/features/map/map_view/maplibre_map_view.dart',
    ]);
    final keyedUsers = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains("keyed_layers.dart'"))
        .map((f) => f.path.replaceAll('\\', '/'))
        .toList();
    expect(keyedUsers, ['lib/features/map/map_view/maplibre_map_view.dart']);
  });

  test('beide Engines verankern den Quellenhinweis unten links', () {
    // Am Quelltext, nicht am Widget-Baum: Die MapLibre-Strecke ist eine
    // native GL-Fläche und im Widget-Test nicht aufbaubar.
    final classic = File(
      'lib/features/map/map_view/flutter_map_view.dart',
    ).readAsStringSync();
    final native = File(
      'lib/features/map/map_view/maplibre_map_view.dart',
    ).readAsStringSync();
    expect(classic, contains('RichAttributionWidget('));
    expect(classic, isNot(contains('AttributionAlignment.bottomRight')));
    // MapLibre: der eigene, entdoppelte Hinweis (MapAttribution steht
    // unten links), nicht der des Pakets.
    expect(native, contains('MapAttribution('));
    expect(native, isNot(contains('ml.SourceAttribution(')));
  });

  test('MapLibre-Marker spiegeln die Ausrichtung (PilzBuddy #409)', () {
    // Beide Pakete nehmen ein `Alignment` und rechnen es umgekehrt: Bei
    // `topCenter` liegt der Punkt in flutter_map an der UNTERKANTE der
    // Nadel, in MapLibre an der Oberkante. Die Fassade folgt flutter_map,
    // die MapLibre-Seite muss spiegeln — sonst hängt jede Nadel 40 px
    // unter ihrem Ort.
    final native = File(
      'lib/features/map/map_view/maplibre_map_view.dart',
    ).readAsStringSync();
    expect(native, contains('alignment: marker.alignment * -1'));
  });
}
