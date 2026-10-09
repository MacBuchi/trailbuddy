// #82: Gespeicherte Bereiche liegen IMMER auf der Karte, zuoberst — auch
// mit Empfang. Bis 0.36.x nur ohne Empfang und dann unter der Online-
// Karte: Bei schwachem Empfang meldete das Telefon ein Netz, die Online-
// Kacheln kamen nie, und die gespeicherten wurden nicht gefragt.
//
// Die MapLibre-Seite prüft `maplibre_style_provider_test.dart` an der
// Reihenfolge der Quellen; hier die flutter_map-Engine (Web und
// Rückfall) am Widget-Baum, und die Annahme, auf der beides ruht.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/core/connectivity.dart';
import 'package:trailbuddy/features/map/base_map_providers.dart';
import 'package:trailbuddy/features/map/map_view/flutter_map_view.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/map/online_map.dart';
import 'package:trailbuddy/features/map/way_layer.dart';
import 'package:trailbuddy/features/offline_areas/area_providers.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

/// Liefert nie etwas — der Test fragt die Schichtung, nicht die Kacheln.
class _NoTiles extends vmt.VectorTileProvider {
  @override
  Future<Uint8List> provide(vmt.TileIdentity tile) async =>
      throw vmt.ProviderException(message: 'leer', retryable: vmt.Retryable.none, statusCode: 404);

  @override
  int get minimumZoom => 0;

  @override
  int get maximumZoom => 13;

  @override
  vmt.TileOffset get tileOffset => vmt.TileOffset.DEFAULT;

  @override
  vmt.TileProviderType get type => vmt.TileProviderType.vector;
}

BaseMapStyle _style() => BaseMapStyle(
      theme: vtr.ThemeReader().read({
        'version': 8,
        'sources': {
          'protomaps': {'type': 'vector'},
        },
        'layers': [
          {
            'id': 'earth',
            'type': 'fill',
            'source': 'protomaps',
            'source-layer': 'earth',
            'paint': {'fill-color': '#e2dfda'},
          },
        ],
      }),
      tileProviders: vmt.TileProviders({'protomaps': _NoTiles()}),
    );

void main() {
  Future<({BaseMapStyle online, BaseMapStyle areas, BaseMapStyle ways, BaseMapStyle areaWays})> pump(
      WidgetTester tester,
      {required bool noConnectivity, bool withOverviews = false}) async {
    final online = _style();
    final areas = _style();
    final ways = _style();
    final areaWays = _style();
    const config = MapViewConfig(
      initialCenter: LatLng(47.6, 11.9),
      initialZoom: 12,
      minZoom: 3,
      maxZoom: 19,
      backgroundColor: AppColors.mapBackground,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        noConnectivityProvider.overrideWithValue(noConnectivity),
        onlineMapStyleProvider.overrideWith((ref) async => online),
        baseMapStyleProvider.overrideWith((ref) async => withOverviews ? _style() : null),
        areaOverviewStyleProvider.overrideWith((ref) async => withOverviews ? _style() : null),
        areaMapStyleProvider.overrideWith((ref) async => areas),
        onlineWaysStyleProvider.overrideWith((ref) async => ways),
        areaWaysStyleProvider.overrideWith((ref) async => areaWays),
      ],
      child: MaterialApp(
        home: FlutterMapView(
          config: config,
          controller: MapViewController(initialCenter: config.initialCenter, initialZoom: 12),
          layers: const MapViewLayers(),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    return (online: online, areas: areas, ways: ways, areaWays: areaWays);
  }

  List<Key?> tileLayerKeys(WidgetTester tester) =>
      tester.widgetList(find.byType(vmt.VectorTileLayer)).map((w) => w.key).toList();

  for (final noConnectivity in [false, true]) {
    testWidgets(
        'die Bereiche liegen über der Online-Karte (${noConnectivity ? 'ohne' : 'mit'} Empfang)',
        (tester) async {
      final s = await pump(tester, noConnectivity: noConnectivity);
      expect(tileLayerKeys(tester),
          [
            ValueKey(s.online.tileProviders),
            ValueKey(s.areas.tileProviders),
            ValueKey(s.ways.tileProviders),
            ValueKey(s.areaWays.tileProviders),
          ],
          reason: 'Reihenfolge = Schichtung: der Bereich über der Karte, die Wege (#212) über '
              'beiden — die deckende Fläche eines Bereichs deckte sie sonst zu —, die Wege '
              'der Bereiche zuoberst, wie die Bereiche über der Online-Karte');
      final area = tester.widget<vmt.VectorTileLayer>(
          find.byKey(ValueKey(s.areas.tileProviders)));
      expect(area.maximumTileSubstitutionDifference, 0,
          reason: 'eine gröbere Bereichskachel läge sonst über der schärferen Online-Kachel');
      // Die vmt-Schichten laufen mit Zeitgebern; abbauen, bevor der Test endet.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 1));
    });
  }

  // #220 Schritt 4: Die Übersicht einer Region liegt über der DACH-
  // Übersicht und unter allem anderen — und nur, solange die Übersicht
  // überhaupt gebraucht wird (hier: ohne Empfang).
  for (final noConnectivity in [false, true]) {
    testWidgets('die Übersichten der Regionen: ${noConnectivity ? 'über der DACH-Übersicht' : 'mit Empfang keine'}',
        (tester) async {
      await pump(tester, noConnectivity: noConnectivity, withOverviews: true);
      final keys = tileLayerKeys(tester);
      if (noConnectivity) {
        expect(keys.take(2), const [ValueKey('base-map'), ValueKey('region-overviews')]);
        final layer = tester.widget<vmt.VectorTileLayer>(find.byKey(const ValueKey('region-overviews')));
        expect(layer.layerMode, vmt.VectorTileLayerMode.raster);
      } else {
        expect(keys, isNot(contains(const ValueKey('region-overviews'))));
        expect(keys, isNot(contains(const ValueKey('base-map'))));
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 1));
    });
  }

  test('die Annahme dahinter: `earth` ist eine deckende Fläche ohne Transparenz', () {
    // Nur deshalb verdeckt eine Bereichskachel die Online-Karte darunter
    // vollständig, statt sie doppelt durchscheinen zu lassen. Wer den Stil
    // neu erzeugt und das ändert, muss #82 neu denken.
    final style = jsonDecode(File(kMapStyleAsset).readAsStringSync()) as Map<String, dynamic>;
    final layers = (style['layers'] as List).cast<Map<String, dynamic>>();
    final firstData = layers.firstWhere((l) => l['type'] != 'background');
    expect(firstData['id'], 'earth');
    expect(firstData['type'], 'fill');
    final paint = firstData['paint'] as Map<String, dynamic>;
    expect(paint.containsKey('fill-opacity'), isFalse);
    expect(paint['fill-color'], matches(RegExp(r'^#[0-9a-fA-F]{6}$')));
  });
}
