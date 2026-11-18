// Web-Stub des bedingten Imports in map_view.dart: Der Web-Build darf
// `package:maplibre` nie sehen (Android-Engine). Erreichbar ist dieser
// Pfad nicht — die Engine-Wahl prüft `!kIsWeb`, bevor sie hierher
// verzweigt — aber falls doch, rendert die flutter_map-Engine statt
// einer Exception: Die Karte ist Kernfunktion, kein Ort zum Werfen.
import 'package:flutter/widgets.dart';

import 'flutter_map_view.dart';
import 'map_view.dart';

Widget createMapLibreMapView({
  required MapViewConfig config,
  required MapViewController controller,
  required MapViewLayers layers,
}) => FlutterMapView(config: config, controller: controller, layers: layers);
