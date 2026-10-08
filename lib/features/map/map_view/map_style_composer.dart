// Baut das Style-Dokument der MapLibre-Engine — PUR, ohne I/O, damit
// vollständig testbar (test/map/map_style_composer_test.dart). Wer hier
// etwas falsch zusammensetzt, bekommt keine Fehlermeldung, sondern eine
// leere Karte. Pfade, Zoombereiche und Farben liefert der Aufrufer
// (maplibre_style_provider.dart übernimmt das Lesen von Platte).
import 'dart:convert';

/// Eine PMTiles-Quelle für den Style: Adresse (`file://…` auf Platte oder
/// `https://…` beim Host) plus Zoombereich.
///
/// Der Zoombereich kommt IMMER aus dem Archiv-Header, nie aus den
/// eingebetteten JSON-Metadaten — die lügen (0–15 bei einem 0–7-Extract).
/// Ohne korrektes `maxzoom` hält MapLibre Kacheln bis z22 für vorhanden,
/// fragt sie an, bekommt nichts — und die Karte ist ab der ersten
/// fehlenden Stufe LEER statt hochskaliert.
class MapStyleSource {
  const MapStyleSource({
    required this.id,
    required this.url,
    required this.minZoom,
    required this.maxZoom,
    this.labelsOnTop = true,
  });

  final String id;

  /// `file:///…` oder `https://…`; MapLibre bekommt `pmtiles://` davor.
  final String url;
  final int minZoom;
  final int maxZoom;

  /// Ob die Beschriftungen (Symbol-Ebenen) dieser Quelle über die
  /// [MapStyleOverlay]s gehoben werden (Feldbericht 0.98.0: die Namen lagen
  /// unter den Wegen). Nein nur für die Übersicht: Ihre Zoom-7-Kacheln
  /// ließen gestreckte Straßennamen über der Detailkarte stehen.
  final bool labelsOnTop;
}

/// Eine Online-Raster-Quelle (Kachel-URL-Vorlage, z. B. OSM).
class MapRasterSource {
  const MapRasterSource({
    required this.id,
    required this.urlTemplate,
    required this.maxZoom,
  });

  final String id;
  final String urlTemplate;
  final int maxZoom;
}

/// Eine Vektorquelle mit EIGENEN Ebenen statt denen der Basiskarte — die
/// Wege-Ebene (#212). Liegt über allen Kartenquellen, also auch über den
/// gespeicherten Bereichen, deren deckende Fläche sie sonst zudeckte.
class MapStyleOverlay {
  const MapStyleOverlay({required this.source, required this.layers});

  final MapStyleSource source;

  /// Die fertigen Ebenen; ihr `source` ist [MapStyleSource.id].
  final List<Map<String, dynamic>> layers;
}

const kMapAttribution = '© OpenStreetMap contributors · Protomaps';

/// Setzt aus dem erzeugten Protomaps-Basis-Style und den Quellen EIN
/// Style-Dokument zusammen: eine background-Ebene im Landton, dann für
/// jede Vektorquelle alle Nicht-background-Ebenen des Basis-Styles, dann
/// die [overlays] mit ihren eigenen Ebenen, dann die Beschriftungen der
/// Quellen mit [MapStyleSource.labelsOnTop] in Quellen-Reihenfolge —
/// Namen stehen über den Wegen, nicht darunter; dieselben Namen aus
/// Online-Karte und Bereich verdrängt MapLibres Kollisionsprüfung —, dann
/// die Rasterquellen als oberste Kartenschicht — wo eine Online-Kachel
/// lädt, deckt sie den fremden Kartenstil darunter ab (PilzBuddy #137).
///
/// Die background-Ebene des Basis-Styles wird bewusst NICHT je Quelle
/// übernommen: Sie malt deckend über die volle Kachelfläche.
///
/// [extraAttributions] (die Behörden hinter den offiziellen Trails) hängen
/// an der ERSTEN Quelle mit — das Attributions-Widget zeigt je Quelle
/// ihren Text, mehr Stellen gibt es im Style-Schema nicht.
String composeMapLibreStyle({
  required Map<String, dynamic> baseStyle,
  required String glyphsUrl,
  required String backgroundColor,
  required List<MapStyleSource> sources,
  List<MapRasterSource> rasterSources = const [],
  List<MapStyleOverlay> overlays = const [],
  List<String> extraAttributions = const [],
}) {
  final baseLayers = baseStyle['layers'] as List<dynamic>? ?? const [];

  // Attribution nur an der ERSTEN Quelle mit diesem Text: Vier Quellen
  // ergäben sonst vier identische Zeilen übereinander. Rechtlich genügt
  // eine.
  final seenAttributions = <String>{};
  String? attributionOnce(String text) {
    if (!seenAttributions.add(text)) return null;
    final extras = seenAttributions.length == 1 ? extraAttributions : const <String>[];
    return [text, ...extras].join(' · ');
  }

  final styleSources = <String, dynamic>{};
  final layers = <Map<String, dynamic>>[
    {
      'id': 'hintergrund',
      'type': 'background',
      'paint': {'background-color': backgroundColor},
    },
  ];

  final labels = <Map<String, dynamic>>[];
  for (final source in sources) {
    final attribution = attributionOnce(kMapAttribution);
    styleSources[source.id] = {
      'type': 'vector',
      'url': 'pmtiles://${source.url}',
      'minzoom': source.minZoom,
      'maxzoom': source.maxZoom,
      'attribution': ?attribution,
    };
    for (final layer in _layersFor(baseLayers, source.id)) {
      (source.labelsOnTop && layer['type'] == 'symbol' ? labels : layers).add(layer);
    }
  }

  for (final overlay in overlays) {
    final source = overlay.source;
    final attribution = attributionOnce(kMapAttribution);
    styleSources[source.id] = {
      'type': 'vector',
      'url': 'pmtiles://${source.url}',
      'minzoom': source.minZoom,
      'maxzoom': source.maxZoom,
      'attribution': ?attribution,
    };
    layers.addAll(overlay.layers);
  }
  layers.addAll(labels);

  for (final raster in rasterSources) {
    final attribution = attributionOnce(kMapAttribution);
    styleSources[raster.id] = {
      'type': 'raster',
      'tiles': [raster.urlTemplate],
      // OSM liefert 256er-Kacheln; MapLibres Standard sind 512 — ohne
      // die Angabe läge die Beschriftungsgröße eine Zoomstufe daneben.
      'tileSize': 256,
      'maxzoom': raster.maxZoom,
      'attribution': ?attribution,
    };
    layers.add({'id': raster.id, 'type': 'raster', 'source': raster.id});
  }

  return jsonEncode({
    ...baseStyle,
    'glyphs': glyphsUrl,
    'sources': styleSources,
    'layers': layers,
  });
}

/// Kopiert alle Nicht-background-Ebenen des Basis-Styles auf eine Quelle
/// um: Id mit Quellen-Präfix (Ids müssen im Style eindeutig sein),
/// `source` umgehängt, Schriften umgeschrieben.
List<Map<String, dynamic>> _layersFor(List<dynamic> baseLayers, String sourceId) => [
      for (final layer in baseLayers.cast<Map<String, dynamic>>())
        if (layer['type'] != 'background')
          {
            ...(_rewriteFonts(layer)! as Map<String, dynamic>),
            'id': '$sourceId/${layer['id']}',
            'source': sourceId,
          },
    ];

/// Ersetzt die Schriftnamen des Protomaps-Styles durch die selbst
/// erzeugten Stacks aus `assets/map_glyphs/`. Rekursiv über das ganze
/// Ebenen-Objekt, weil `text-font` auch in einem `case`-Ausdruck stecken
/// kann. Italic gibt es als eigenen Stack nicht — Regular ist die
/// ehrliche Näherung (Kartenbeschriftung, kein Fließtext).
Object? _rewriteFonts(Object? node) {
  if (node is String) {
    if (node == 'Noto Sans Medium') return 'noto-sans-medium';
    if (node == 'Noto Sans Regular' || node == 'Noto Sans Italic') {
      return 'noto-sans-regular';
    }
    return node;
  }
  if (node is List) return node.map(_rewriteFonts).toList();
  if (node is Map) {
    return <String, dynamic>{
      for (final e in node.entries) e.key as String: _rewriteFonts(e.value),
    };
  }
  return node;
}
