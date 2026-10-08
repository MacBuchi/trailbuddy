// Der Style-Composer ist pure Logik ohne I/O — genau deshalb ist er hier
// vollständig prüfbar: Was er zusammensetzt, entscheidet, ob MapLibre
// überhaupt etwas rendert (in PilzBuddy scheiterte der erste Anlauf an
// einem Style, der vor seinen Quellen gebaut wurde).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/map/map_view/map_style_composer.dart';

/// Kleines Basis-Style-Dokument im Protomaps-Schema: eine background-Ebene,
/// eine Flächen-Ebene, eine Text-Ebene mit Schriften auch in einem
/// case-Ausdruck (so steckt es im echten Asset).
Map<String, dynamic> _baseStyle() => {
      'version': 8,
      'sources': {
        'protomaps': {'type': 'vector', 'url': 'https://example.invalid/x'},
      },
      'layers': [
        {
          'id': 'background',
          'type': 'background',
          'paint': {'background-color': '#cccccc'},
        },
        {'id': 'earth', 'type': 'fill', 'source': 'protomaps', 'source-layer': 'earth'},
        {
          'id': 'places',
          'type': 'symbol',
          'source': 'protomaps',
          'layout': {
            'text-font': [
              'case',
              ['==', ['get', 'kind'], 'city'],
              ['literal', 'Noto Sans Medium'],
              ['literal', 'Noto Sans Italic'],
            ],
          },
        },
      ],
    };

const _overview = MapStyleSource(
  id: 'overview',
  url: 'file:///data/app/offline_maps/overview_dach.pmtiles',
  minZoom: 0,
  maxZoom: 7,
);

const _online = MapStyleSource(
  id: 'online',
  url: 'https://tiles.example.org/trailbuddy/dach-20260928.pmtiles',
  minZoom: 0,
  maxZoom: 13,
);

const _osm = MapRasterSource(
  id: 'osm',
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  maxZoom: 19,
);

Map<String, dynamic> _compose({
  List<MapStyleSource> sources = const [_overview],
  List<MapRasterSource> raster = const [],
  List<String> extra = const [],
}) =>
    jsonDecode(composeMapLibreStyle(
      baseStyle: _baseStyle(),
      glyphsUrl: 'file:///glyphs/{fontstack}/{range}.pbf',
      backgroundColor: '#e2dfda',
      sources: sources,
      rasterSources: raster,
      extraAttributions: extra,
    )) as Map<String, dynamic>;

List<Map<String, dynamic>> _layers(Map<String, dynamic> style) =>
    (style['layers'] as List).cast<Map<String, dynamic>>();

void main() {
  test('genau eine background-Ebene, zuerst und im Landton', () {
    final layers = _layers(_compose());
    expect(layers.where((l) => l['type'] == 'background'), hasLength(1),
        reason: 'Die background-Ebene des Basis-Styles darf nicht je Quelle '
            'dupliziert werden — sie würde alles darunter zudecken.');
    expect(layers.first['type'], 'background');
    expect(layers.first['paint'], {'background-color': '#e2dfda'});
  });

  test('Vektorquellen: pmtiles-URL (Datei oder Host), Zoombereich, Ebenen umgehängt', () {
    final style = _compose(sources: const [_overview, _online]);
    final sources = style['sources'] as Map<String, dynamic>;
    expect(sources.keys, ['overview', 'online'], reason: 'Reihenfolge = Schichtung');
    final overview = sources['overview'] as Map<String, dynamic>;
    expect(overview['url'], 'pmtiles://file:///data/app/offline_maps/overview_dach.pmtiles');
    expect(overview['minzoom'], 0);
    expect(overview['maxzoom'], 7);
    expect(overview['attribution'], '© OpenStreetMap contributors · Protomaps');
    final online = sources['online'] as Map<String, dynamic>;
    expect(online['url'], 'pmtiles://https://tiles.example.org/trailbuddy/dach-20260928.pmtiles');
    expect(online['maxzoom'], 13);
    expect(online.containsKey('attribution'), isFalse, reason: 'nur an der ersten Quelle');
    expect(sources.containsKey('protomaps'), isFalse, reason: 'ersetzt, nicht ergänzt');
    final ids = _layers(style).map((l) => l['id']).toList();
    expect(ids, [
      'hintergrund',
      'overview/earth',
      'overview/places',
      'online/earth',
      'online/places',
    ]);
    expect(_layers(style)[3]['source'], 'online');
  });

  test('Schriftnamen werden auf die eigenen Stacks umgeschrieben — auch im case', () {
    final places = _layers(_compose()).last;
    final font = (places['layout'] as Map)['text-font'];
    expect(jsonEncode(font), contains('noto-sans-medium'));
    expect(jsonEncode(font), contains('noto-sans-regular'));
    expect(jsonEncode(font), isNot(contains('Noto Sans')));
    expect(_compose()['glyphs'], 'file:///glyphs/{fontstack}/{range}.pbf');
  });

  test('Raster-Quelle: 256er-Kacheln, oberste Kartenschicht, Attribution nur EINMAL', () {
    final style = _compose(raster: const [_osm]);
    final sources = style['sources'] as Map<String, dynamic>;
    final osm = sources['osm'] as Map<String, dynamic>;
    expect(osm['type'], 'raster');
    expect(osm['tileSize'], 256);
    expect(osm['maxzoom'], 19);
    expect(osm.containsKey('attribution'), isFalse,
        reason: 'dieselbe Attribution steht schon an der Übersicht');
    expect(_layers(style).last, {'id': 'osm', 'type': 'raster', 'source': 'osm'},
        reason: 'wo eine Online-Kachel lädt, deckt sie den fremden Stil darunter ab');
  });

  test('nur Raster (Online-Normalfall): keine Vektor-Ebenen, Attribution am Raster', () {
    final style = _compose(sources: const [], raster: const [_osm]);
    expect(_layers(style).map((l) => l['id']), ['hintergrund', 'osm']);
    final osm = (style['sources'] as Map)['osm'] as Map;
    expect(osm['attribution'], contains('OpenStreetMap'));
  });

  test('die Quellen der offiziellen Trails hängen an der ersten Quelle mit', () {
    final style = _compose(raster: const [_osm], extra: const ['Land Tirol (CC BY 4.0)']);
    final overview = (style['sources'] as Map)['overview'] as Map;
    expect(overview['attribution'], '© OpenStreetMap contributors · Protomaps · Land Tirol (CC BY 4.0)');
    final osm = (style['sources'] as Map)['osm'] as Map;
    expect(osm.containsKey('attribution'), isFalse);
  });

  test('Höhenlinien (#271) gehören unter Wege, Namen und Raster — über jede Kartenfläche', () {
    String compose({bool ways = true, bool raster = false}) => composeMapLibreStyle(
          baseStyle: _baseStyle(),
          glyphsUrl: 'file:///glyphs/{fontstack}/{range}.pbf',
          backgroundColor: '#e2dfda',
          sources: const [
            MapStyleSource(id: 'online', url: 'https://example.invalid/a.pmtiles', minZoom: 0, maxZoom: 13),
            MapStyleSource(id: 'area-1', url: 'file:///b.pmtiles', minZoom: 8, maxZoom: 13),
          ],
          rasterSources: raster
              ? const [MapRasterSource(id: 'osm', urlTemplate: 'https://example.invalid/{z}/{x}/{y}.png', maxZoom: 19)]
              : const [],
          overlays: ways
              ? const [
                  MapStyleOverlay(
                    source: MapStyleSource(id: 'ways', url: 'https://example.invalid/w.pmtiles', minZoom: 13, maxZoom: 13),
                    layers: [
                      {'id': 'ways/track', 'type': 'line', 'source': 'ways', 'source-layer': 'ways'},
                    ],
                  ),
                ]
              : const [],
        );
    for (final (ways, raster) in [(true, false), (false, false), (true, true)]) {
      final style = compose(ways: ways, raster: raster);
      final layers = _layers(jsonDecode(style) as Map<String, dynamic>);
      final anchor = contourAnchorIn(style, overlayPrefix: 'ways');
      expect(anchor, isNotNull, reason: 'Wege $ways, Raster $raster');
      final at = layers.indexWhere((l) => l['id'] == anchor);
      // Darüber nur Wege, Namen und Raster …
      for (final l in layers.skip(at)) {
        expect(l['type'] == 'symbol' || l['type'] == 'raster' || (l['source'] as String?)?.startsWith('ways') == true,
            isTrue, reason: '${l['id']} über dem Anker');
      }
      // … darunter die letzte Fläche der obersten Kartenquelle (der Bereich).
      expect(layers[at - 1]['type'], isNot('symbol'));
      expect(layers[at - 1]['source'], 'area-1', reason: 'über den deckenden Flächen der Bereiche (#82)');
    }
  });
}

