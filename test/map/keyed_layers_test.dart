// Die eigenen Ebenen auf der MapLibre-Karte werden nach KENNUNG
// abgeglichen, nicht nach Position (`keyed_layers.dart`, Feldbericht
// 2026-10-02). Das Paket hätte nach jeder vorn eingefügten Ebene — dem
// Leuchtrand beim Antippen, dem Genauigkeitskreis — jede Linie dahinter
// neu übertragen. Die Platform-View ist im Test nicht renderbar; geprüft
// werden der Plan und seine Ausführung gegen einen mitschreibenden Stil.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart' as ml;
import 'package:trailbuddy/features/map/contours.dart';
import 'package:trailbuddy/features/map/map_view/keyed_layers.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/map/map_view/maplibre_map_view.dart';

ml.Layer line(List<LatLng> pts, {Color color = const Color(0xFF1F6FD1)}) => RoundPolylineLayer(
      polylines: [
        ml.Feature(geometry: ml.LineString.build([for (final p in pts) ...[p.longitude, p.latitude]])),
      ],
      color: color,
      width: 4,
    );

const a = [LatLng(48, 9), LatLng(48.01, 9)];
const b = [LatLng(48, 9.1), LatLng(48.01, 9.1)];

/// Schreibt jeden Aufruf mit und führt die Reihenfolge der Ebenen wie
/// MapLibre: `belowLayerId` setzt darunter, sonst zuoberst.
class RecordingStyle implements ml.StyleController {
  final calls = <String>[];
  final order = <String>[];
  final sources = <String, String>{};
  String? failOn;

  void _maybeFail(String what) {
    if (failOn != null && what.contains(failOn!)) {
      failOn = null;
      throw StateError('Engine: $what');
    }
  }

  @override
  Future<void> addSource(ml.Source source) async {
    _maybeFail('addSource ${source.id}');
    if (sources.containsKey(source.id)) throw StateError('Quelle ${source.id} gibt es schon');
    sources[source.id] = (source as ml.GeoJsonSource).data;
    calls.add('addSource ${source.id}');
  }

  @override
  Future<void> addLayer(ml.StyleLayer layer, {String? belowLayerId, String? aboveLayerId, int? atIndex}) async {
    _maybeFail('addLayer ${layer.id}');
    if (order.contains(layer.id)) throw StateError('Ebene ${layer.id} gibt es schon');
    if (belowLayerId == null) {
      order.add(layer.id);
    } else {
      order.insert(order.indexOf(belowLayerId), layer.id);
    }
    calls.add('addLayer ${layer.id}${belowLayerId == null ? '' : ' unter $belowLayerId'}');
  }

  @override
  Future<void> updateGeoJsonSource({required String id, required String data}) async {
    sources[id] = data;
    calls.add('update $id');
  }

  @override
  Future<void> removeLayer(String id) async {
    order.remove(id);
    calls.add('removeLayer $id');
  }

  @override
  Future<void> removeSource(String id) async {
    sources.remove(id);
    calls.add('removeSource $id');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('planLayerOps', () {
    var slots = 0;
    int next() => slots++;
    setUp(() => slots = 0);

    test('am Anfang wird alles angelegt, jede Ebene unter die nächste', () {
      final onMap = <String, ({int slot, ml.Layer layer})>{};
      final l1 = line(a), l2 = line(b);
      final ops = planLayerOps(onMap, [(key: 'x', layer: l1), (key: 'y', layer: l2)], next);
      expect(ops, hasLength(2));
      expect(ops.every((o) => o is AddLayerOp), isTrue);
      // Von oben nach unten: erst y (zuoberst), dann x darunter.
      expect((ops[0] as AddLayerOp).belowSlot, isNull);
      expect((ops[1] as AddLayerOp).belowSlot, ops[0].slot);
    });

    test('derselbe Stand kostet nichts', () {
      final onMap = <String, ({int slot, ml.Layer layer})>{};
      final l1 = line(a), l2 = line(b);
      planLayerOps(onMap, [(key: 'x', layer: l1), (key: 'y', layer: l2)], next);
      expect(planLayerOps(onMap, [(key: 'x', layer: l1), (key: 'y', layer: l2)], next), isEmpty);
    });

    test('eine Ebene VORN dazu ist genau ein Schritt — nichts dahinter wandert', () {
      final onMap = <String, ({int slot, ml.Layer layer})>{};
      final trails = [for (var i = 0; i < 20; i++) (key: 'line:$i', layer: line(a))];
      planLayerOps(onMap, trails, next);
      final glow = line(a, color: const Color(0xFFC6F432));
      final ops = planLayerOps(onMap, [(key: 'glow', layer: glow), ...trails], next);
      expect(ops, hasLength(1));
      final add = ops.single as AddLayerOp;
      expect(add.belowSlot, onMap['line:0']!.slot, reason: 'unter den Trails, nicht zuoberst');
      // Und wieder weg: ein Schritt.
      final back = planLayerOps(onMap, trails, next);
      expect(back.single, isA<RemoveLayerOp>());
    });

    test('neue Daten: nur die Quelle; anderer Stil: die Ebene an ihrer Stelle', () {
      final onMap = <String, ({int slot, ml.Layer layer})>{};
      final l1 = line(a), l2 = line(b);
      planLayerOps(onMap, [(key: 'x', layer: l1), (key: 'y', layer: l2)], next);
      final data = planLayerOps(onMap, [(key: 'x', layer: line(a)), (key: 'y', layer: l2)], next);
      expect(data.single, isA<UpdateSourceOp>());
      final red = line(a, color: const Color(0xFFC62828));
      final style = planLayerOps(onMap, [(key: 'x', layer: red), (key: 'y', layer: l2)], next);
      final restyle = style.single as RestyleOp;
      expect(restyle.updateSource, isTrue);
      expect(restyle.belowSlot, onMap['y']!.slot);
    });
  });

  group('die Ebenen der Karte', () {
    List<MapViewPolyline> trails(int n, {int? changed, bool glow = false}) => [
          if (glow)
            const MapViewPolyline(points: a, color: Color(0xFFC6F432), width: 10),
          for (var i = 0; i < n; i++)
            MapViewPolyline(
              points: _lines[i],
              color: i == changed ? const Color(0xFFC62828) : const Color(0xFF1F6FD1),
              label: 'Trail $i',
            ),
        ];

    test('ein Trail ändert die Farbe und einer wird ausgewählt: wenige Schritte, nicht das Netz', () {
      final cache = MapLibreLineCache();
      final onMap = <String, ({int slot, ml.Layer layer})>{};
      var slots = 0;
      final first = mapLibreKeyedLayers(MapViewLayers(polylines: trails(60)), cache);
      planLayerOps(onMap, first, () => slots++);
      final keys = {for (final k in first) k.key};
      expect(keys, hasLength(first.length), reason: 'jede Kennung einmal');

      final again = mapLibreKeyedLayers(MapViewLayers(polylines: trails(60)), cache);
      expect(planLayerOps(onMap, again, () => slots++), isEmpty, reason: 'neuer Aufbau, gleiche Linien');

      final next = mapLibreKeyedLayers(MapViewLayers(polylines: trails(60, changed: 7, glow: true)), cache);
      final ops = planLayerOps(onMap, next, () => slots++);
      // Leuchtrand dazu, die rote Gruppe dazu, das alte Fach der blauen neu.
      expect(ops.length, lessThanOrEqualTo(3), reason: '$ops');
      expect(ops.whereType<RemoveLayerOp>(), isEmpty);
      final touched = [for (final o in ops) o.layer.list.length].fold<int>(0, (s, n) => s + n);
      expect(touched, lessThan(20), reason: 'übertragen werden einzelne Fächer, nicht 60 Linien');
    });

    test('die Fächer verteilen sich, auch bei regelmäßig liegenden Linien', () {
      final buckets = {for (final l in _lines) lineBucketOf(l)};
      expect(buckets.length, greaterThanOrEqualTo(kLineBuckets - 1));
      expect(lineBucketOf(_lines[3]), lineBucketOf([..._lines[3]]), reason: 'dieselbe Linie, dasselbe Fach');
    });

    test('der Genauigkeitskreis verschiebt keine Linie', () {
      final cache = MapLibreLineCache();
      final onMap = <String, ({int slot, ml.Layer layer})>{};
      var slots = 0;
      planLayerOps(onMap, mapLibreKeyedLayers(MapViewLayers(polylines: trails(30)), cache), () => slots++);
      final withCircle = mapLibreKeyedLayers(
          MapViewLayers(
              polylines: trails(30),
              circles: const [MapViewCircle(center: LatLng(48, 9), radiusM: 20, fillColor: Color(0x33000000))]),
          cache);
      final ops = planLayerOps(onMap, withCircle, () => slots++);
      expect(ops.single, isA<AddLayerOp>());
    });
  });

  group('KeyedLayerSync', () {
    test('legt an, gleicht ab, und nach einem neuen Stil alles noch einmal', () async {
      final style = RecordingStyle();
      final sync = KeyedLayerSync();
      final l1 = line(a), l2 = line(b);
      await sync.sync(style, [(key: 'x', layer: l1), (key: 'y', layer: l2)]);
      expect(style.order, ['maplibre-layer-1', 'maplibre-layer-0'], reason: 'x unter y');
      expect(style.sources.keys, unorderedEquals(['maplibre-source-0', 'maplibre-source-1']));

      style.calls.clear();
      await sync.sync(style, [(key: 'x', layer: l1), (key: 'y', layer: l2)]);
      expect(style.calls, isEmpty);

      await sync.sync(style, [(key: 'y', layer: l2)]);
      expect(style.calls, ['removeLayer maplibre-layer-1', 'removeSource maplibre-source-1']);

      // `setStyle`: Die Karte hat nichts Eigenes mehr.
      final fresh = RecordingStyle();
      sync.reset();
      await sync.sync(fresh, [(key: 'x', layer: l1), (key: 'y', layer: l2)]);
      expect(fresh.order, hasLength(2));
    });

    test('Höhenlinien (#271): eigener Abgleich unter dem Anker, nie über den Trails', () async {
      final style = RecordingStyle();
      style.order.addAll(['earth', 'ways/track', 'labels']);
      final trails = KeyedLayerSync();
      final contours = KeyedLayerSync(firstSlot: kContourFirstSlot);
      await trails.sync(style, [(key: 'x', layer: line(a))]);
      final layers = contourKeyedLayers(const MapViewContours(key: 'k1', lines: [
        ContourLine(level: 500, points: a, cells: 9),
        ContourLine(level: 600, points: b, cells: 9, index: true),
      ]));
      await contours.sync(style, layers, below: 'ways/track');
      final ids = [for (final k in layers) 'maplibre-layer-${kContourFirstSlot + layers.length - 1 - layers.indexOf(k)}'];
      expect(style.order.sublist(1, 4), unorderedEquals(ids), reason: 'zwischen Fläche und Wegen');
      expect(style.order.indexOf('ways/track'), greaterThan(style.order.indexOf(ids.first)));
      expect(style.order.last, 'maplibre-layer-0', reason: 'die Trails bleiben zuoberst');
      // Neue Linien: nur die Quellen, nichts wandert.
      style.calls.clear();
      await contours.sync(
          style,
          contourKeyedLayers(const MapViewContours(key: 'k2', lines: [
            ContourLine(level: 500, points: b, cells: 9),
            ContourLine(level: 600, points: a, cells: 9, index: true),
          ])),
          below: 'ways/track');
      expect(style.calls.every((c) => c.startsWith('update ')), isTrue, reason: '${style.calls}');
      // Ohne Anker unter die unterste eigene Ebene, nicht zuoberst.
      final bare = RecordingStyle();
      final t2 = KeyedLayerSync();
      await t2.sync(bare, [(key: 'x', layer: line(a))]);
      await KeyedLayerSync(firstSlot: kContourFirstSlot).sync(bare, layers, below: t2.bottomLayerId);
      expect(bare.order.last, 'maplibre-layer-0');
    });

    test('scheitert ein Schritt, wird er gemeldet und beim nächsten Mal neu angelegt', () async {
      final style = RecordingStyle()..failOn = 'addLayer';
      final sync = KeyedLayerSync();
      final l1 = line(a);
      await sync.sync(style, [(key: 'x', layer: l1)]);
      expect(style.order, isEmpty);
      expect(style.sources, isEmpty, reason: 'die halbe Quelle ist wieder weg');
      await sync.sync(style, [(key: 'x', layer: l1)]);
      expect(style.order, hasLength(1));
    });
  });
}

final _lines = [
  for (var i = 0; i < 60; i++) [LatLng(47 + i * 0.013, 9 + i * 0.017), LatLng(47.01 + i * 0.013, 9 + i * 0.017)],
];
