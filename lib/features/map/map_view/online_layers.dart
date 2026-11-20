// Im gespeicherten Bereich keine Online-Kachel (#596 H3, Android).
//
// MapLibre lädt Kacheln einer Quelle nur, solange eine Ebene an ihr hängt.
// Deckt der Kachelspeicher den Ausschnitt ganz, nimmt die MapLibre-Ansicht
// die Ebenen der Online-Karte und der Online-Wege aus dem Stil und setzt
// sie beim Verlassen an ihrer alten Stelle wieder ein — ohne `setStyle`,
// das das ganze Trail-Netz neu übertragen würde. `maplibre` 0.3.7+1 kennt
// keine Sichtbarkeit je Ebene (`StyleController`: nur add/remove), daher
// raus und rein.
//
// Hier steht alles PUR: welche Ebenen es betrifft, wann (mit Schwelle,
// damit es am Rand nicht hin und her springt), wohin eine Ebene zurück
// gehört, und die Übersetzung einer Stil-Ebene (JSON) in eine Ebene des
// Pakets. `OnlineLayerSwitch` führt es gegen den `StyleController` aus.
import 'dart:convert';

import 'package:maplibre/maplibre.dart' as ml;

import '../../../core/errors.dart';
import '../../offline_areas/area_coverage.dart';
import '../../offline_areas/area_plan.dart';
import '../way_layer.dart' show kWaysSourceId, kWaysZoom;
import 'map_view.dart';

/// Die Online-Karte: DACH (`online`) und die übrigen Regionen
/// (`online-<region>`), siehe `maplibre_style_provider.dart`.
bool isOnlineMapSource(String id) => id == 'online' || id.startsWith('online-');

/// Die Online-Wege: DACH und die übrigen Regionen — nicht die Wege der
/// Bereiche (`ways-area-<region>`), die liegen auf dem Gerät.
bool isOnlineWaysSource(String id) =>
    id == kWaysSourceId || id.startsWith('$kWaysSourceId-region-');

/// Welche Online-Ebenen gerade draußen sind.
typedef OnlineHidden = ({bool map, bool ways});

const kOnlineShown = (map: false, ways: false);

/// Um so viel seiner Größe je Seite muss der Speicher über den Ausschnitt
/// hinaus decken, damit die Online-Ebenen GEHEN …
const kOnlineHideMargin = 0.5;

/// … und erst wenn er nicht einmal um so viel deckt, KOMMEN sie wieder.
/// Dazwischen bleibt es, wie es ist: kein Hin und Her am Rand.
const kOnlineShowMargin = 0.25;

/// Die Kachelstufe, die MapLibre bei der 256er-Stufe [zoom256] von einer
/// Vektorquelle lädt: 512er-Kacheln, also eine Stufe darunter, abgerundet.
int vectorTileZoom(double zoom256) => (zoom256 - 1).floor().clamp(0, 30);

/// Was bei Stillstand gelten soll. [current] ist der Stand auf der Karte;
/// [onlineMaxZoom] die höchste Stufe der Online-Karte (darüber streckt
/// MapLibre deren Kacheln, fragt also diese Stufe).
OnlineHidden onlineHiddenFor({
  required List<CoverArea> areas,
  required MapViewBounds view,
  required double zoom256,
  required OnlineHidden current,
  int onlineMaxZoom = kAreaShapeZoom,
}) {
  if (areas.isEmpty) return kOnlineShown;
  final box = AreaBounds(
    south: view.south,
    west: view.west,
    north: view.north,
    east: view.east,
  );
  bool covered(bool hidden, int z, {bool ways = false}) => areasCover(
    areas,
    grownBy(box, hidden ? kOnlineShowMargin : kOnlineHideMargin),
    z,
    ways: ways,
  );

  final z = vectorTileZoom(zoom256);
  final mapZ = z < onlineMaxZoom ? z : onlineMaxZoom;
  final map = mapZ >= kAreaMinZoom && covered(current.map, mapZ);
  // Unter der Wege-Stufe fragt MapLibre die Wege gar nicht: Dann bleibt,
  // was ist — die Kacheln bei Stufe 13 für einen Zoom-8-Ausschnitt zu
  // zählen, wären zehntausende.
  final ways = z < kWaysZoom
      ? current.ways
      : covered(current.ways, kWaysZoom, ways: true);
  return (map: map, ways: ways);
}

/// Die Ebenen des Stils als JSON, unten zuerst.
List<Map<String, dynamic>> styleLayersOf(String style) => [
  for (final l
      in ((jsonDecode(style) as Map<String, dynamic>)['layers'] as List? ??
              const [])
          .cast<Map<String, dynamic>>())
    l,
];

/// Die Kennungen der Ebenen, die bei [hidden] draußen sind.
Set<String> hiddenLayerIds(
  List<Map<String, dynamic>> layers,
  OnlineHidden hidden,
) => {
  for (final l in layers)
    if (l['source'] case final String s
        when (hidden.map && isOnlineMapSource(s)) ||
            (hidden.ways && isOnlineWaysSource(s)))
      l['id'] as String,
};

/// Unter welche Ebene die Stil-Ebene Nummer [index] zurück gehört: unter
/// die nächste Ebene DES STILS danach, die nicht [missing] ist; gibt es
/// keine, unter [aboveStyle] (die unterste eigene Ebene der App, die über
/// dem Stil liegt); sonst null (zuoberst).
String? restoreBelow(
  List<String> styleOrder,
  int index,
  Set<String> missing, {
  String? aboveStyle,
}) {
  for (var i = index + 1; i < styleOrder.length; i++) {
    if (!missing.contains(styleOrder[i])) return styleOrder[i];
  }
  return aboveStyle;
}

/// Der Anker der Höhenlinien, wenn ein Teil des Stils draußen ist: Ist
/// [anchor] selbst draußen, die nächste Ebene danach, die es nicht ist.
String? presentAnchor(
  List<String> styleOrder,
  String? anchor,
  Set<String> hidden,
) {
  if (anchor == null || !hidden.contains(anchor)) return anchor;
  for (var i = styleOrder.indexOf(anchor) + 1; i < styleOrder.length; i++) {
    if (!hidden.contains(styleOrder[i])) return styleOrder[i];
  }
  return null;
}

/// Eine Ebene des Stils (JSON) als Ebene des Pakets — für das
/// Wiedereinsetzen. Null für Arten, die der Stil hier nicht hat.
ml.StyleLayer? styleLayerFromJson(Map<String, dynamic> j) {
  final id = j['id'] as String;
  final source = j['source'] as String?;
  if (source == null) return null;
  final sourceLayer = j['source-layer'] as String?;
  final paint = _props(j['paint']);
  final layout = _props(j['layout']);
  final minZoom = (j['minzoom'] as num?)?.toDouble() ?? 0;
  final maxZoom = (j['maxzoom'] as num?)?.toDouble() ?? 24;
  final filter = (j['filter'] as List?)?.cast<Object>();
  return switch (j['type']) {
    'fill' => ml.FillStyleLayer(
      id: id,
      sourceId: source,
      sourceLayerId: sourceLayer,
      paint: paint,
      layout: layout,
      minZoom: minZoom,
      maxZoom: maxZoom,
      filter: filter,
    ),
    'line' => ml.LineStyleLayer(
      id: id,
      sourceId: source,
      sourceLayerId: sourceLayer,
      paint: paint,
      layout: layout,
      minZoom: minZoom,
      maxZoom: maxZoom,
      filter: filter,
    ),
    'symbol' => ml.SymbolStyleLayer(
      id: id,
      sourceId: source,
      sourceLayerId: sourceLayer,
      paint: paint,
      layout: layout,
      minZoom: minZoom,
      maxZoom: maxZoom,
      filter: filter,
    ),
    'circle' => ml.CircleStyleLayer(
      id: id,
      sourceId: source,
      sourceLayerId: sourceLayer,
      paint: paint,
      layout: layout,
      minZoom: minZoom,
      maxZoom: maxZoom,
      filter: filter,
    ),
    _ => null,
  };
}

Map<String, Object> _props(Object? m) => {
  if (m is Map)
    for (final e in m.entries)
      if (e.value != null) e.key as String: e.value as Object,
};

/// Führt die Entscheidung gegen den Stil der Karte aus. Ein neuer Stil
/// (`setStyle`) bringt alle Ebenen zurück: danach [reset].
class OnlineLayerSwitch {
  OnlineHidden _hidden = kOnlineShown;

  /// Was gerade draußen ist.
  OnlineHidden get hidden => _hidden;

  String? _style;
  List<Map<String, dynamic>> _layers = const [];
  List<String> _order = const [];

  /// Die Kennungen, die gerade draußen sind.
  Set<String> get hiddenIds => hiddenLayerIds(_layers, _hidden);

  /// Die Reihenfolge des aktuellen Stils.
  List<String> get styleOrder => _order;

  /// Nach `setStyle`: Der neue Stil hat wieder alle Ebenen.
  void reset(String style) {
    _hidden = kOnlineShown;
    if (!identical(style, _style)) {
      _style = style;
      _layers = styleLayersOf(style);
      _order = [for (final l in _layers) l['id'] as String];
    }
  }

  /// Bringt die Karte auf [want]. [aboveStyle]: die unterste eigene
  /// Ebene der App über dem Stil. Ein Fehler wird gemeldet, und die
  /// Ebenen kommen alle zurück — lieber Online-Kacheln als Löcher.
  Future<void> apply(
    ml.StyleController style,
    OnlineHidden want, {
    String? aboveStyle,
  }) async {
    if (_style == null || want == _hidden) return;
    final missing = hiddenIds;
    final after = hiddenLayerIds(_layers, want);
    try {
      await _restore(style, missing.difference(after), missing, aboveStyle);
      for (final id in after.difference(missing)) {
        await style.removeLayer(id);
        missing.add(id);
      }
      _hidden = want;
    } catch (e, s) {
      logError('Online-Ebenen im Bereich umschalten', e, s);
      try {
        await _restore(style, missing, missing, aboveStyle);
      } catch (e, s) {
        logError('Online-Ebenen zurücksetzen', e, s);
      }
      _hidden = kOnlineShown;
    }
  }

  /// Setzt [ids] wieder ein, von oben nach unten: Die Ebene, unter die
  /// eine gehört, liegt dann schon wieder da. [missing] wird mitgeführt.
  Future<void> _restore(
    ml.StyleController style,
    Set<String> ids,
    Set<String> missing,
    String? aboveStyle,
  ) async {
    for (var index = _order.length - 1; index >= 0; index--) {
      final id = _order[index];
      if (!ids.contains(id) || !missing.contains(id)) continue;
      final layer = styleLayerFromJson(_layers[index]);
      if (layer != null) {
        await style.addLayer(
          layer,
          belowLayerId: restoreBelow(
            _order,
            index,
            missing,
            aboveStyle: aboveStyle,
          ),
        );
      }
      missing.remove(id);
    }
  }
}
