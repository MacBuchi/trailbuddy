// Im gespeicherten Bereich keine Online-Kachel (#596 H3): Deckt der
// Kachelspeicher den Ausschnitt, nimmt die MapLibre-Ansicht die Ebenen der
// Online-Karte und der Online-Wege heraus und setzt sie beim Verlassen an
// ihrer Stelle wieder ein. Die Platform-View ist im Test nicht renderbar;
// geprüft werden Deckung, Entscheidung, Plan und Ausführung gegen einen
// mitschreibenden Stil. Ob MapLibre dann wirklich nichts lädt, zeigt der
// Zähler am Gerät.
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre/maplibre.dart' as ml;
import 'package:trailbuddy/features/map/map_view/map_style_composer.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/map/map_view/online_layers.dart';
import 'package:trailbuddy/features/map/way_layer.dart';
import 'package:trailbuddy/features/offline_areas/area_coverage.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';

import '../fakes/recording_style.dart';

/// Ein gespeicherter Bereich, Karte ab Zoom 8 bis 13, mit Wegen.
const area = AreaBounds(south: 47.0, west: 10.0, north: 47.4, east: 10.6);

CoverArea cover(AreaShape shape, {bool ways = true}) =>
    (shape: shape, minZoom: kAreaMinZoom, maxZoom: 13, ways: ways);

final areas = [cover(const RectShape(area))];

/// Ein Ausschnitt um [lat]/[lon], [span] Grad breit und hoch.
MapViewBounds view(double lat, double lon, {double span = 0.02}) =>
    MapViewBounds(
      west: lon - span / 2,
      east: lon + span / 2,
      south: lat - span / 2,
      north: lat + span / 2,
    );

/// Die Nordkante der obersten Kachel des Bereichs bei Zoom 13: Ein
/// Rahmen holt die GANZE Kachel, die seinen Rand berührt, gedeckt ist
/// also bis hier, nicht nur bis zum Rahmen.
double get top {
  final t = tileAt(area.north, 10.3, 13);
  return tileBounds(13, t.x, t.y).north;
}

AreaBounds box(MapViewBounds v) =>
    AreaBounds(south: v.south, west: v.west, north: v.north, east: v.east);

/// Ein Stil wie in der App, aus dem echten Composer: Online-Karte DACH und
/// eine zweite Region, darüber der Bereich, dann Online-Wege und die Wege
/// des Bereichs, die Namen zuoberst.
String composedStyle() => composeMapLibreStyle(
  baseStyle: {
    'version': 8,
    'layers': [
      {'id': 'background', 'type': 'background'},
      {
        'id': 'earth',
        'type': 'fill',
        'source-layer': 'earth',
        'paint': {'fill-color': '#e0e0d0'},
      },
      {
        'id': 'paths',
        'type': 'line',
        'source-layer': 'roads',
        'minzoom': 12,
        'filter': [
          '==',
          ['get', 'kind'],
          'path',
        ],
        'paint': {
          'line-width': [
            'interpolate',
            ['linear'],
            ['zoom'],
            12,
            1,
            16,
            3,
          ],
        },
      },
      {
        'id': 'places',
        'type': 'symbol',
        'source-layer': 'places',
        'layout': {
          'text-field': ['get', 'name'],
          'text-font': ['Noto Sans Regular'],
        },
      },
    ],
  },
  glyphsUrl: 'file:///glyphs/{fontstack}/{range}.pbf',
  backgroundColor: '#f0efe8',
  sources: const [
    MapStyleSource(
      id: 'online',
      url: 'https://host/a.pmtiles',
      minZoom: 0,
      maxZoom: 13,
    ),
    MapStyleSource(
      id: 'online-ca',
      url: 'https://host/b.pmtiles',
      minZoom: 0,
      maxZoom: 13,
    ),
    MapStyleSource(
      id: 'area-dach',
      url: 'mbtiles:///store/map.mbtiles',
      minZoom: 8,
      maxZoom: 13,
    ),
  ],
  overlays: [
    MapStyleOverlay(
      source: const MapStyleSource(
        id: kWaysSourceId,
        url: 'https://host/w.pmtiles',
        minZoom: kWaysZoom,
        maxZoom: kWaysZoom,
      ),
      layers: wayStyleLayers(kWaysSourceId, dashes: true),
    ),
    MapStyleOverlay(
      source: const MapStyleSource(
        id: '$kWaysSourceId-area-dach',
        url: 'mbtiles:///store/ways.mbtiles',
        minZoom: kWaysZoom,
        maxZoom: kWaysZoom,
      ),
      layers: wayStyleLayers('$kWaysSourceId-area-dach', dashes: true),
    ),
  ],
);

void main() {
  group('areasCover', () {
    test('ein Ausschnitt mitten im Bereich ist gedeckt', () {
      expect(areasCover(areas, box(view(47.2, 10.3)), 13), isTrue);
    });

    test('über den Rand hinaus nicht', () {
      // Bis an die Kante der Randkachel gedeckt (der Ausschnitt muss den
      // Rahmen noch berühren — sonst sagt `tilesWithin` vorsichtig nein).
      expect(areasCover(areas, box(view(top - 0.025, 10.3)), 13), isTrue);
      expect(areasCover(areas, box(view(top + 0.005, 10.3)), 13), isFalse);
    });

    test('unter dem kleinsten Zoom des Bereichs nicht', () {
      expect(areasCover(areas, box(view(47.2, 10.3)), 7), isFalse);
    });

    test('ohne Bereich nicht', () {
      expect(areasCover(const [], box(view(47.2, 10.3)), 13), isFalse);
    });

    test('zwei Bereiche decken zusammen, was keiner allein deckt', () {
      const west = AreaBounds(south: 47.0, west: 10.0, north: 47.4, east: 10.3);
      const east = AreaBounds(south: 47.0, west: 10.3, north: 47.4, east: 10.6);
      final two = [cover(const RectShape(west)), cover(const RectShape(east))];
      final across = box(view(47.2, 10.3, span: 0.2));
      expect(areasCover([two.first], across, 13), isFalse);
      expect(areasCover(two, across, 13), isTrue);
    });

    test('eine Kachelmenge mit Loch deckt das Loch nicht', () {
      final all = const RectShape(area).keysAt(kAreaShapeZoom);
      final hole = tileAt(47.2, 10.3, kAreaShapeZoom);
      final shape = TileSetShape(
        zoom: kAreaShapeZoom,
        keys: all..remove(TileSetShape.keyOf(hole.x, hole.y, kAreaShapeZoom)),
      );
      expect(areasCover([cover(shape)], box(view(47.2, 10.3)), 13), isFalse);
      // Eine Stufe gröber liegt die Elternkachel trotzdem — ganz.
      expect(
        areasCover([cover(shape)], box(view(47.2, 10.3, span: 0.002)), 12),
        isTrue,
      );
    });

    test('Wege zählen nur aus Bereichen mit Wegen', () {
      final noWays = [cover(const RectShape(area), ways: false)];
      final b = box(view(47.2, 10.3));
      expect(areasCover(noWays, b, kWaysZoom, ways: true), isFalse);
      expect(areasCover(areas, b, kWaysZoom, ways: true), isTrue);
    });

    test('nur fertige Bereiche aus dem Kachelspeicher, kein Halter', () {
      StoredArea stored(String id, {bool complete = true, int format = 2}) =>
          StoredArea(
            id: id,
            name: id,
            bounds: area,
            minZoom: kAreaMinZoom,
            maxZoom: 13,
            build: '20261101',
            tiles: 1,
            bytes: 1,
            savedAt: DateTime(2026, 11, 20),
            format: format,
            complete: complete,
            wayTiles: 1,
          );
      final list = coverAreasOf([
        stored('fertig'),
        stored('halb', complete: false),
        stored('alt', format: 1),
        stored('${kKeptAreaPrefix}dach'),
      ]);
      expect(list, hasLength(1));
      expect(list.single.ways, isTrue);
    });
  });

  group('onlineHiddenFor', () {
    test('im Bereich bei Zoom 14 gehen Karte und Wege', () {
      expect(
        onlineHiddenFor(
          areas: areas,
          view: view(47.2, 10.3),
          zoom256: 14.5,
          current: kOnlineShown,
        ),
        (map: true, ways: true),
      );
    });

    test('über Zoom 13 hinaus gilt Stufe 13 (MapLibre streckt sie)', () {
      expect(
        onlineHiddenFor(
          areas: areas,
          view: view(47.2, 10.3, span: 0.002),
          zoom256: 18,
          current: kOnlineShown,
        ).map,
        isTrue,
      );
    });

    test('unter Zoom 8 des Bereichs bleibt die Karte online', () {
      expect(
        onlineHiddenFor(
          areas: areas,
          view: view(47.2, 10.3, span: 0.05),
          zoom256: 8.5,
          current: kOnlineShown,
        ).map,
        isFalse,
      );
    });

    test('unter der Wege-Stufe bleiben die Wege, wie sie sind', () {
      for (final ways in [true, false]) {
        expect(
          onlineHiddenFor(
            areas: areas,
            view: view(47.2, 10.3, span: 0.1),
            zoom256: 11,
            current: (map: false, ways: ways),
          ).ways,
          ways,
        );
      }
    });

    test('ohne Bereich ist alles online', () {
      expect(
        onlineHiddenFor(
          areas: const [],
          view: view(47.2, 10.3),
          zoom256: 14,
          current: (map: true, ways: true),
        ),
        kOnlineShown,
      );
    });

    test('am Rand eine Schwelle: kein Hin und Her', () {
      // 0.02° hoch: Ein Viertel Rand reicht 0.015° über die Mitte, die
      // Hälfte 0.02°. Bei top − 0.0175 deckt der Speicher das eine, nicht
      // das andere.
      final edge = view(top - 0.0175, 10.3);
      expect(
        onlineHiddenFor(
          areas: areas,
          view: edge,
          zoom256: 14.5,
          current: kOnlineShown,
        ).map,
        isFalse,
        reason: 'online: erst mit halber Größe Rand gehen sie',
      );
      expect(
        onlineHiddenFor(
          areas: areas,
          view: edge,
          zoom256: 14.5,
          current: (map: true, ways: true),
        ).map,
        isTrue,
        reason: 'draußen: mit einem Viertel Rand bleiben sie draußen',
      );
      expect(
        onlineHiddenFor(
          areas: areas,
          view: view(top - 0.005, 10.3),
          zoom256: 14.5,
          current: (map: true, ways: true),
        ).map,
        isFalse,
        reason: 'näher am Rand kommen sie wieder',
      );
    });
  });

  group('welche Ebenen und wohin zurück', () {
    final layers = styleLayersOf(composedStyle());

    test('Online-Karte beider Regionen und Online-Wege, nie der Bereich', () {
      final hidden = hiddenLayerIds(layers, (map: true, ways: true));
      final sources = {
        for (final l in layers)
          if (hidden.contains(l['id'])) l['source'],
      };
      expect(sources, {'online', 'online-ca', kWaysSourceId});
      expect(
        hiddenLayerIds(layers, (map: true, ways: false)).every(
          (id) => layers.any(
            (l) =>
                l['id'] == id && (l['source'] as String).startsWith('online'),
          ),
        ),
        isTrue,
      );
      expect(hiddenLayerIds(layers, kOnlineShown), isEmpty);
    });

    test('eine Ebene gehört unter die nächste vorhandene des Stils', () {
      const order = ['a', 'b', 'c', 'd'];
      expect(restoreBelow(order, 0, {'b'}), 'c');
      expect(restoreBelow(order, 3, const {}, aboveStyle: 'trail'), 'trail');
      expect(restoreBelow(order, 2, {'d'}), isNull);
    });

    test('der Anker der Höhenlinien weicht auf die nächste Ebene aus', () {
      const order = ['a', 'b', 'c'];
      expect(presentAnchor(order, 'b', {'b'}), 'c');
      expect(presentAnchor(order, 'b', const {}), 'b');
      expect(presentAnchor(order, 'c', {'c'}), isNull);
      expect(presentAnchor(order, null, {'b'}), isNull);
    });

    test('jede Art kommt mit Quelle, Filter, Zoom und Ausdrücken zurück', () {
      for (final j in layers) {
        if (j['type'] == 'background') continue;
        final l = styleLayerFromJson(j)!;
        expect(l.id, j['id']);
        expect((l as ml.StyleLayerWithSource).sourceId, j['source']);
        expect(l.sourceLayerId, j['source-layer']);
        expect(l.filter, j['filter']);
        expect(l.minZoom, (j['minzoom'] as num?)?.toDouble() ?? 0);
        expect(l.paint, j['paint'] ?? const {});
        expect(l.layout, j['layout'] ?? const {});
      }
      expect(
        styleLayerFromJson(layers.firstWhere((l) => l['id'] == 'online/paths')),
        isA<ml.LineStyleLayer>(),
      );
      expect(
        styleLayerFromJson(
          layers.firstWhere((l) => l['id'] == 'online/places'),
        ),
        isA<ml.SymbolStyleLayer>(),
      );
    });
  });

  group('OnlineLayerSwitch', () {
    late String style;
    late List<String> styleOrder;
    late RecordingStyle map;
    late OnlineLayerSwitch online;

    setUp(() {
      style = composedStyle();
      styleOrder = [for (final l in styleLayersOf(style)) l['id'] as String];
      map = RecordingStyle()..order.addAll([...styleOrder, 'trail-0']);
      online = OnlineLayerSwitch()..reset(style);
    });

    test('raus und wieder rein: dieselbe Reihenfolge wie vorher', () async {
      await online.apply(map, (map: true, ways: true), aboveStyle: 'trail-0');
      final out = hiddenLayerIds(styleLayersOf(style), (map: true, ways: true));
      expect(out, isNotEmpty);
      expect(map.order.toSet().intersection(out), isEmpty);
      expect(map.order, contains('area-dach/earth'));
      expect(online.hidden, (map: true, ways: true));

      await online.apply(map, kOnlineShown, aboveStyle: 'trail-0');
      expect(map.order, [...styleOrder, 'trail-0']);
      expect(online.hidden, kOnlineShown);
    });

    test('nur die Wege zurück, die Karte bleibt draußen', () async {
      await online.apply(map, (map: true, ways: true), aboveStyle: 'trail-0');
      await online.apply(map, (map: true, ways: false), aboveStyle: 'trail-0');
      final mapIds = hiddenLayerIds(styleLayersOf(style), (
        map: true,
        ways: false,
      ));
      expect(map.order, [
        for (final id in styleOrder)
          if (!mapIds.contains(id)) id,
        'trail-0',
      ]);
    });

    test('derselbe Stand kostet nichts', () async {
      await online.apply(map, (map: true, ways: true));
      final calls = map.calls.length;
      await online.apply(map, (map: true, ways: true));
      expect(map.calls, hasLength(calls));
    });

    test(
      'ein neuer Stil hat wieder alles, nichts wird doppelt angelegt',
      () async {
        await online.apply(map, (map: true, ways: true), aboveStyle: 'trail-0');
        map.order
          ..clear()
          ..addAll(styleOrder);
        online.reset(style);
        expect(online.hidden, kOnlineShown);
        expect(online.hiddenIds, isEmpty);
        await online.apply(map, kOnlineShown);
        expect(map.order, styleOrder);
      },
    );

    test('scheitert das Einsetzen, kommen alle Ebenen zurück', () async {
      await online.apply(map, (map: true, ways: true), aboveStyle: 'trail-0');
      map.failOn = 'online/paths';
      await online.apply(map, kOnlineShown, aboveStyle: 'trail-0');
      expect(online.hidden, kOnlineShown);
      expect(map.order, [...styleOrder, 'trail-0']);
    });
  });
}
