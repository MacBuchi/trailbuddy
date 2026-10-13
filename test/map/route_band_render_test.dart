// Ein durchsichtiges Band mit Rand und Pfeilen (#295) in beiden Engines:
// MapLibre legt den Rand NEBEN die Linie (`line-gap-width`), beide mit
// derselben Deckkraft, die Pfeile als Symbole darüber; flutter_map
// gruppiert in Läufe, die je als eine Fläche verblassen. Ohne Pixel.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show PolylineLayer;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/map/map_view/flutter_map_view.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/map/map_view/maplibre_map_view.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

const _pts = [LatLng(48, 9), LatLng(48, 9.01)];
const _band = MapViewPolyline(
  points: _pts,
  color: Color(0xFFB6F04A),
  width: 12,
  borderColor: Color(0xFF4F8A10),
  borderWidth: 1.5,
  opacity: 0.55,
);
const _arrows = MapViewPolyline(
  points: _pts,
  color: Color(0xFF3D6E0B),
  width: 0,
  opacity: 0.55,
  pass: 3,
  arrows: LineArrows(color: Color(0xFF3D6E0B), offset: 4, size: 12),
);
const _trail = MapViewPolyline(points: _pts, color: Color(0xFF131A16), borderColor: Color(0xFFFFFFFF), borderWidth: 2);

void main() {
  test('MapLibre: Rand neben der Linie, gleiche Deckkraft, keine deckende Ebene darunter', () {
    final layers = mapLibrePolylineLayers([_band], null);
    expect(layers.whereType<RoundPolylineLayer>(), isEmpty);
    final lines = layers.whereType<FadedLineLayer>().toList();
    expect(lines, hasLength(2));
    final edge = lines.first.getPaint(), band = lines.last.getPaint();
    expect(edge['line-gap-width'], 12, reason: 'der Rand umschließt das Band, statt darunter zu liegen');
    expect(edge['line-width'], 1.5);
    expect(edge['line-opacity'], 0.55);
    expect(band['line-opacity'], 0.55);
    expect(band.containsKey('line-gap-width'), isFalse);
    expect(band['line-color'], '#b6f04a');
  });

  test('MapLibre: Pfeile als Symbole entlang der Linie, nicht aufrecht, rechts versetzt', () {
    final layers = mapLibrePolylineLayers([_arrows], null);
    expect(layers.whereType<FadedLineLayer>(), isEmpty, reason: 'Breite 0: kein Strich');
    final arrow = layers.whereType<LineArrowLayer>().single.getLayout();
    expect(arrow['symbol-placement'], 'line');
    expect(arrow['text-field'], kLineArrowGlyph);
    expect(arrow['text-keep-upright'], isFalse);
    expect(arrow['text-ignore-placement'], isTrue, reason: 'Schilder und Namen der Trails bleiben');
    expect((arrow['text-offset'] as List)[1], greaterThan(0.1), reason: 'rechts der Fahrtrichtung');
  });

  test('eine zweite Zeichnung ist ein eigener Stil — eigene Ebene, mischt sich', () {
    const again = MapViewPolyline(
        points: _pts, color: Color(0xFFB6F04A), width: 12, borderColor: Color(0xFF4F8A10), borderWidth: 1.5,
        opacity: 0.55, pass: 1);
    expect(_band.styleKey, isNot(again.styleKey));
    expect(mapLibrePolylineLayers([_band, again], null).whereType<FadedLineLayer>(), hasLength(4));
  });

  test('deckende Linien bleiben, wie sie waren', () {
    final layers = mapLibrePolylineLayers([_trail], null);
    expect(layers.whereType<RoundPolylineLayer>(), hasLength(2));
    expect(layers.whereType<FadedLineLayer>(), isEmpty);
  });

  test('flutter_map: Läufe nach Deckkraft und Zeichnung, nach Pfeilen ein Schnitt', () {
    const again = MapViewPolyline(points: _pts, color: Color(0xFFB6F04A), width: 12, opacity: 0.55, pass: 1);
    final runs = polylineRuns([_band, _band, again, _arrows, _trail, _trail]);
    expect(runs.map((r) => r.length), [2, 1, 1, 2]);
    expect(polylineRuns([_trail, _trail, _trail]), hasLength(1), reason: 'das Netz bleibt EINE Ebene');
  });

  test('flutter_map: Pfeile im festen Bildpunkt-Abstand, mit der Richtung des Stücks', () {
    final places = lineArrowPlaces(const [Offset(0, 0), Offset(100, 0), Offset(100, 200)], 90);
    expect(places.map((p) => p.at), const [Offset(45, 0), Offset(100, 35), Offset(100, 125)]);
    expect(places.first.dir, const Offset(1, 0));
    expect(places.last.dir, const Offset(0, 1));
    expect(lineArrowPlaces(const [Offset(0, 0)], 90), isEmpty);
  });

  testWidgets('flutter_map: das Band verblasst als EINE Fläche, das Netz bleibt deckend', (tester) async {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'anna').id);
    await pumpApp(tester, backend, extraOverrides: [
      mapViewBuilderProvider.overrideWithValue((config, controller, layers) => FlutterMapView(
            config: config,
            controller: controller,
            layers: const MapViewLayers(polylines: [_band, _arrows, _trail]),
          )),
    ]);
    await settle(tester, frames: 10);
    final faded = find.ancestor(of: find.byType(PolylineLayer), matching: find.byType(Opacity));
    expect(tester.widget<Opacity>(faded.first).opacity, 0.55);
    final layers = tester.widgetList<PolylineLayer>(find.byType(PolylineLayer)).toList();
    final band = layers.singleWhere((l) => l.polylines.any((p) => p.color == _band.color));
    expect(band.polylines.single.borderColor, _band.borderColor, reason: 'Rand und Band deckend, dann zusammen verblasst');
    expect(band.polylines.single.color.a, 1);
    final net = layers.singleWhere((l) => l.polylines.any((p) => p.color == _trail.color));
    expect(find.ancestor(of: find.byWidget(net), matching: find.byType(Opacity)), findsNothing);
    expect(tester.takeException(), isNull, reason: 'die Pfeile malen ohne Fehler');
  });
}
