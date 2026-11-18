import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import 'pmtiles_tile_provider.dart';

/// Die mitgelieferte DACH-Übersicht (Protomaps-Basemap, Zoom 0–7, ~9 MB)
/// für die flutter_map-Engine: Renderthema plus Kachelquelle.
///
/// Sie ist die unterste Schicht der Karte, sobald kein Empfang besteht
/// oder die Online-Karte nicht aufgeht (`docs/konzept-offline-karten.md`,
/// Baustein 3.3): Dann kommt keine Kachel vom Host, und ohne sie läge
/// unter dem Finger nackter Landton. Seit Schritt 2 liest die Online-
/// Karte denselben Stil aus demselben Archivformat — die Übersicht darf
/// deshalb auch UNTER ihr liegen, es sind nicht mehr zwei Kartenstile
/// nebeneinander (PilzBuddy #137 galt für OSM-Raster über Protomaps).
class BaseMapStyle {
  const BaseMapStyle({required this.theme, required this.tileProviders});

  final vtr.Theme theme;
  final TileProviders tileProviders;
}

/// Der Stil, aus dem beide Engines lesen (siehe CLAUDE.md, erzeugte
/// Assets). Einmal geladen, für immer gecacht.
const kMapStyleAsset = 'assets/map_style/protomaps_light_de.json';
const kOverviewAsset = 'assets/offline_maps/overview_dach.pmtiles';

/// Öffnet die Übersicht — auf dem Telefon einmalig auf die Platte
/// materialisiert und faul gelesen, im Browser aus dem Speicher
/// (PilzBuddy 1.114.2: der Platten-Weg allein ließ die PWA das Asset
/// erfolgreich laden und eine Zeile später wegwerfen). null, wenn etwas
/// fehlt — die Übersicht ist Zugabe, nie Pflicht.
Future<PmTilesVectorTileProvider?> openBundledOverview() async {
  try {
    final data = await rootBundle.load(kOverviewAsset);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (kIsWeb) return await PmTilesVectorTileProvider.openBytes(bytes);
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/offline_maps/overview_dach.pmtiles');
    if (!await file.exists() || await file.length() != data.lengthInBytes) {
      await file.create(recursive: true);
      await file.writeAsBytes(bytes);
    }
    return await PmTilesVectorTileProvider.open(file.path);
  } catch (_) {
    // Still degradieren: Ohne Übersicht sieht man den Hintergrundton,
    // aber nie einen Fehler — dieselbe Regel wie beim Zwischenspeicher.
    return null;
  }
}

/// Die Naht für Tests: Der Harness hängt hier eine Quelle ohne Assets ein
/// (`rootBundle` liefert im Widget-Test nichts, und `path_provider` hat
/// dort keinen Kanal).
final overviewOpenerProvider =
    Provider<Future<PmTilesVectorTileProvider?> Function()>(
      (ref) => openBundledOverview,
    );

final _baseThemeProvider = FutureProvider<vtr.Theme>((ref) async {
  final text = await rootBundle.loadString(kMapStyleAsset);
  return vtr.ThemeReader().read(jsonDecode(text) as Map<String, dynamic>);
});

/// Dasselbe Thema ohne die `background`-Ebene — für die Online-Karte,
/// unter der die Übersicht liegt. Die Ebene malt deckend über die volle
/// Kachelfläche, auch für Kacheln ganz ohne Daten, und deckte sonst die
/// Übersicht genau dort zu, wo sie gebraucht wird. Das Asset bleibt
/// unangetastet, gefiltert wird beim Laden.
final baseThemeWithoutBackgroundProvider = FutureProvider<vtr.Theme>((
  ref,
) async {
  final text = await rootBundle.loadString(kMapStyleAsset);
  return vtr.ThemeReader().read(
    styleWithoutBackground(jsonDecode(text) as Map<String, dynamic>),
  );
});

/// Entfernt die `background`-Ebene aus einem Style-JSON (Kopie).
Map<String, dynamic> styleWithoutBackground(Map<String, dynamic> style) => {
  ...style,
  'layers': (style['layers'] as List)
      .where((layer) => (layer as Map)['type'] != 'background')
      .toList(),
};

final baseMapStyleProvider = FutureProvider<BaseMapStyle?>((ref) async {
  try {
    final overview = await ref.watch(overviewOpenerProvider)();
    if (overview == null) return null;
    ref.onDispose(overview.close);
    final theme = await ref.watch(_baseThemeProvider.future);
    return BaseMapStyle(
      theme: theme,
      tileProviders: TileProviders({'protomaps': overview}),
    );
  } catch (_) {
    return null;
  }
});
