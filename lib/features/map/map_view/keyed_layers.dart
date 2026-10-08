// Die eigenen Ebenen auf der MapLibre-Karte — abgeglichen nach KENNUNG,
// nicht nach Position (Feldbericht 2026-10-02: Hänger nach „Mein Beitrag").
//
// Das Paket gleicht `MapLibreMap.layers` nach dem INDEX ab: Ebene i des
// neuen Aufbaus gegen Ebene i des alten. Kommt vorne eine Ebene dazu —
// der Leuchtrand beim Antippen eines Trails, der Genauigkeitskreis, eine
// Fläche der Werkzeugleiste, ein Trail, der beim Speichern blass wird und
// damit eine neue Stilgruppe aufmacht —, rutscht alles dahinter eine Stelle
// weiter, und das Paket überträgt JEDE folgende Ebene neu: den ganzen
// GeoJSON-Text des Netzes, auf dem Haupt-Thread, entfernt und neu
// angelegt. Gemessen an 600 Trails 33 MB Text und knapp 1 s, schon auf
// dem Rechner.
//
// Hier hat jede Ebene eine Kennung (Stil und Fach, siehe
// `maplibre_map_view.dart`) und einen festen Platz auf der Karte (`slot`,
// daraus Quellen- und Ebenen-Kennung). Neu heißt hinzufügen, und zwar
// UNTER die nächste vorhandene Ebene der gewünschten Reihenfolge; weg heißt
// entfernen; geändert heißt nur die Quelle neu befüllen, oder bei anderem
// Stil die Ebene an derselben Stelle neu anlegen. Was gleich ist, kostet
// nichts.
//
// [planLayerOps] ist rein und ohne Karte geprüft; [KeyedLayerSync] führt
// die Schritte gegen den `StyleController` aus.
import 'package:maplibre/maplibre.dart' as ml;

import '../../../core/errors.dart';

/// Eine Ebene mit ihrer Kennung. Die Reihenfolge einer Liste ist die
/// Zeichenreihenfolge, unten zuerst.
typedef KeyedLayer = ({String key, ml.Layer layer});

/// Ein Schritt gegen die Karte.
sealed class LayerOp {
  const LayerOp(this.slot, this.layer);
  final int slot;
  final ml.Layer layer;
}

/// Quelle und Ebene anlegen, unter [belowSlot] (null: zuoberst).
class AddLayerOp extends LayerOp {
  const AddLayerOp(super.slot, super.layer, {this.belowSlot, this.belowLayer});
  final int? belowSlot;
  final ml.Layer? belowLayer;
}

/// Nur die Daten der Quelle neu — Stil und Platz bleiben.
class UpdateSourceOp extends LayerOp {
  const UpdateSourceOp(super.slot, super.layer);
}

/// Anderer Stil unter derselben Kennung: die Ebene neu anlegen, an ihrer
/// Stelle; die Quelle nur, wenn sich auch die Daten geändert haben.
class RestyleOp extends LayerOp {
  const RestyleOp(super.slot, super.layer, {required this.updateSource, this.belowSlot, this.belowLayer});
  final bool updateSource;
  final int? belowSlot;
  final ml.Layer? belowLayer;
}

/// Ebene und Quelle entfernen.
class RemoveLayerOp extends LayerOp {
  const RemoveLayerOp(super.slot, super.layer);
}

/// Was auf der Karte liegt: Kennung → Platz und zuletzt übertragene Ebene.
typedef OnMap = Map<String, ({int slot, ml.Layer layer})>;

/// Paint, Layout und Zoomgrenzen — was die Ebene selbst ausmacht, ohne
/// ihre Daten. `Layer.==` des Pakets vergleicht nur Daten und Zoom.
String layerStyleOf(ml.Layer layer) =>
    '${layer.runtimeType}|${layer.getPaint()}|${layer.getLayout()}|${layer.minZoom}|${layer.maxZoom}';

/// Die Schritte von [onMap] zu [desired]; [onMap] ist danach der neue
/// Stand. [nextSlot] vergibt freie Plätze.
///
/// Die Reihenfolge der Schritte IST die Ausführungsreihenfolge: erst alles
/// Entfernen, dann von oben nach unten — so liegt die Ebene, unter die eine
/// neue gehört, schon da. Vorhandene Ebenen werden nicht umsortiert: Die
/// Reihenfolge der Bänder (Flächen, Kreise, Linien, Namen) ändert sich nie,
/// innerhalb der Trail-Linien ist sie gleichgültig.
List<LayerOp> planLayerOps(OnMap onMap, List<KeyedLayer> desired, int Function() nextSlot) {
  final ops = <LayerOp>[];
  final wanted = <String>{};
  final unique = <KeyedLayer>[];
  for (final d in desired) {
    // Doppelte Kennungen dürfen nicht vorkommen; wenn doch, gewinnt die
    // erste — eine zweite Ebene mit derselben Quelle gäbe es nicht.
    if (wanted.add(d.key)) unique.add(d);
  }
  for (final key in onMap.keys.toList()) {
    if (!wanted.contains(key)) {
      final gone = onMap.remove(key)!;
      ops.add(RemoveLayerOp(gone.slot, gone.layer));
    }
  }
  int? belowSlot;
  ml.Layer? belowLayer;
  for (final d in unique.reversed) {
    final old = onMap[d.key];
    if (old == null) {
      final slot = nextSlot();
      ops.add(AddLayerOp(slot, d.layer, belowSlot: belowSlot, belowLayer: belowLayer));
      onMap[d.key] = (slot: slot, layer: d.layer);
    } else if (!identical(old.layer, d.layer)) {
      final sameData = identical(old.layer.list, d.layer.list);
      final sameStyle = layerStyleOf(old.layer) == layerStyleOf(d.layer);
      if (!sameStyle) {
        ops.add(RestyleOp(old.slot, d.layer,
            updateSource: !sameData, belowSlot: belowSlot, belowLayer: belowLayer));
      } else if (!sameData) {
        ops.add(UpdateSourceOp(old.slot, d.layer));
      }
      onMap[d.key] = (slot: old.slot, layer: d.layer);
    }
    belowSlot = onMap[d.key]!.slot;
    belowLayer = onMap[d.key]!.layer;
  }
  return ops;
}

/// Führt [planLayerOps] gegen die Karte aus. Ein neuer Stil (`setStyle`)
/// nimmt alle eigenen Ebenen mit — danach [reset] und neu abgleichen.
class KeyedLayerSync {
  /// [firstSlot] trennt zwei Abgleiche auf derselben Karte: Die Kennungen
  /// der Ebenen kommen aus dem Platz (`maplibre-layer-<slot>`), und die
  /// Höhenlinien (#271) haben einen eigenen Abgleich unter der Wege-Ebene.
  KeyedLayerSync({int firstSlot = 0}) : _slots = firstSlot;

  final OnMap _onMap = {};
  int _slots;

  /// Die Kennungen des letzten Wunschs, unten zuerst.
  List<String> _order = const [];

  /// Die Ebenen-Kennung der UNTERSTEN eigenen Ebene, die schon auf der
  /// Karte liegt — null ohne.
  String? get bottomLayerId {
    for (final key in _order) {
      final on = _onMap[key];
      if (on != null) return on.layer.getLayerId(on.slot);
    }
    return null;
  }

  /// Wie viele Schritte der letzte Abgleich brauchte — für Tests und die
  /// Messung, nicht für die Logik.
  int lastOps = 0;

  /// Läuft gerade ein Abgleich, wartet der nächste Wunsch, und nur der
  /// jüngste zählt.
  bool _running = false;
  ({ml.StyleController style, List<KeyedLayer> desired, String? below})? _queued;

  /// Zählt die Stile: Ein Abgleich, der noch gegen den alten Stil läuft,
  /// hört auf, sobald ein neuer geladen ist — sonst schriebe er in den
  /// Stand des neuen.
  int _epoch = 0;

  /// Nach einem neuen Stil liegt nichts Eigenes mehr auf der Karte.
  void reset() {
    _epoch++;
    _onMap.clear();
  }

  /// [below]: Die oberste Ebene des Wunschs liegt unter dieser Ebene des
  /// Stils statt zuoberst (die Höhenlinien unter den Wegen).
  Future<void> sync(ml.StyleController style, List<KeyedLayer> desired, {String? below}) async {
    _queued = (style: style, desired: desired, below: below);
    if (_running) return;
    _running = true;
    try {
      for (var next = _queued; next != null; next = _queued) {
        _queued = null;
        await _apply(next.style, next.desired, next.below);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _apply(ml.StyleController style, List<KeyedLayer> desired, String? below) async {
    final epoch = _epoch;
    _order = [for (final d in desired) d.key];
    final ops = planLayerOps(_onMap, desired, () => _slots++);
    lastOps = ops.length;
    for (final op in ops) {
      if (epoch != _epoch) return;
      try {
        await _run(style, op, below);
      } catch (e, s) {
        if (epoch != _epoch) return;
        logError('Kartenebene abgleichen', e, s);
        // Was halb liegt, wird beim nächsten Abgleich neu angelegt — unter
        // einem neuen Platz, damit keine Kennung doppelt vergeben wird.
        _onMap.removeWhere((_, v) => v.slot == op.slot);
        await _quietly(() => style.removeLayer(op.layer.getLayerId(op.slot)));
        await _quietly(() => style.removeSource(op.layer.getSourceId(op.slot)));
      }
    }
  }

  static Future<void> _run(ml.StyleController style, LayerOp op, String? below) async {
    final layer = op.layer;
    final slot = op.slot;
    String data() => ml.FeatureCollection(layer.list).toText();
    switch (op) {
      case AddLayerOp(:final belowSlot, :final belowLayer):
        await style.addSource(ml.GeoJsonSource(id: layer.getSourceId(slot), data: data()));
        await style.addLayer(layer.createStyleLayer(slot),
            belowLayerId: belowSlot == null ? below : belowLayer!.getLayerId(belowSlot));
      case UpdateSourceOp():
        await style.updateGeoJsonSource(id: layer.getSourceId(slot), data: data());
      case RestyleOp(:final updateSource, :final belowSlot, :final belowLayer):
        await style.removeLayer(layer.getLayerId(slot));
        if (updateSource) await style.updateGeoJsonSource(id: layer.getSourceId(slot), data: data());
        await style.addLayer(layer.createStyleLayer(slot),
            belowLayerId: belowSlot == null ? below : belowLayer!.getLayerId(belowSlot));
      case RemoveLayerOp():
        await style.removeLayer(layer.getLayerId(slot));
        await style.removeSource(layer.getSourceId(slot));
    }
  }

  static Future<void> _quietly(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {
      // Aufräumen nach einem Fehler: Was nicht (mehr) da ist, muss nicht weg.
    }
  }
}
