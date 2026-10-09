// Bereiche zeichnen (Offline-Karten, Stufe C; Betreiber, 2026-09-28:
// „alle Kacheln, die umschlossen oder berührt von der gezeichneten
// Fläche sind, werden offline geladen … additiv … theoretisch auch ein
// subtraktiver Bereich"). Pur bis auf den Notifier am Ende: aus einem
// Fingerstrich die Kacheln bei [kAreaShapeZoom], und der Entwurf, der
// Striche addiert oder abzieht, bis er gespeichert wird.
//
// **Ein Strich ist eine Fläche.** Er wird geschlossen (Ende zum Anfang),
// und dazu gehört jede Kachel, die der Rand berührt oder die innen liegt.
// Ein offener Zickzack ergibt damit eine dünne Fläche — seine Kacheln
// sind die, über die er läuft. Das ist dieselbe Regel für beides, und sie
// macht den Radierer zu einem Werkzeug, das genau wegnimmt, worüber man
// gewischt hat.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../map/map_view/map_hit_test.dart' show kMercatorMaxLat;
import '../map/map_view/map_view.dart';
import 'area_overlay.dart' show mergeTileRects, offlineOverlayBox, rectRing, tileOutline;
import 'area_plan.dart';
import 'area_providers.dart' show storedAreasProvider;

/// Größer als so viele Kacheln (Rahmen des Strichs, bei Zoom 13) wird
/// ein Strich nicht ausgewertet: ein Kreis um halb Europa ist ein
/// Versehen, und ihn Kachel für Kachel zu prüfen hielte die Oberfläche an.
/// Weit über [kAreaMaxTiles], damit das Abziehen aus einem großen
/// Entwurf nicht daran scheitert.
const kAreaDrawMaxSpanTiles = 250000;

/// Wie viele Schritte ein Entwurf zurücknehmen kann.
const kAreaDraftHistory = 20;

/// Mehr Rechtecke als das zeichnet die Anzeige des Entwurfs nur im
/// Ausschnitt selbst, ohne Rand — nie gröber (wie die Maske).
const kAreaDraftMaxRects = 3000;


double _tileX(double lon, int n) => (lon + 180) / 360 * n;

double _tileY(double lat, int n) {
  final r = lat.clamp(-kMercatorMaxLat, kMercatorMaxLat) * math.pi / 180;
  return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n;
}

/// Die Kacheln bei [zoom] (Schlüssel wie [TileSetShape.keyOf]), die die
/// geschlossene Fläche [ring] berührt oder umschließt. Null, wenn der
/// Rahmen des Strichs mehr als [maxSpanTiles] Kacheln umfasst — leer bei
/// weniger als zwei Punkten.
Set<int>? tilesTouchedByRing(List<LatLng> ring,
    {int zoom = kAreaShapeZoom, int maxSpanTiles = kAreaDrawMaxSpanTiles}) {
  if (ring.length < 2) return <int>{};
  final n = 1 << zoom;
  final pts = [for (final p in ring) (x: _tileX(p.longitude, n), y: _tileY(p.latitude, n))];
  var minX = double.infinity, maxX = -double.infinity;
  var minY = double.infinity, maxY = -double.infinity;
  for (final p in pts) {
    minX = math.min(minX, p.x);
    maxX = math.max(maxX, p.x);
    minY = math.min(minY, p.y);
    maxY = math.max(maxY, p.y);
  }
  final span = (maxX.floor() - minX.floor() + 1) * (maxY.floor() - minY.floor() + 1);
  if (span > maxSpanTiles) return null;

  final keys = <int>{};
  void add(int x, int y) {
    if (x < 0 || y < 0 || x >= n || y >= n) return;
    keys.add(TileSetShape.keyOf(x, y, zoom));
  }

  // Der Rand: jede Kante in Schritten von höchstens einer Zehntelkachel
  // abgetastet. Eine Ecke, die eine Kachel um weniger streift, fehlt —
  // die harmlose Richtung.
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i], b = pts[(i + 1) % pts.length];
    final len = math.max((b.x - a.x).abs(), (b.y - a.y).abs());
    final steps = math.max(1, (len / 0.1).ceil());
    for (var k = 0; k <= steps; k++) {
      final f = k / steps;
      add((a.x + (b.x - a.x) * f).floor(), (a.y + (b.y - a.y) * f).floor());
    }
  }

  // Das Innere: je Kachelzeile die Schnittpunkte der Mittellinie mit den
  // Kanten (gerade-ungerade), dazwischen jede Kachel, deren Mitte innen
  // liegt. Was innen UND am Rand liegt, hat die Abtastung schon.
  for (var row = minY.floor(); row <= maxY.floor(); row++) {
    final yc = row + 0.5;
    final xs = <double>[];
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      if ((a.y <= yc) != (b.y <= yc)) {
        xs.add(a.x + (yc - a.y) * (b.x - a.x) / (b.y - a.y));
      }
    }
    xs.sort();
    for (var i = 0; i + 1 < xs.length; i += 2) {
      for (var col = (xs[i] - 0.5).ceil(); col <= (xs[i + 1] - 0.5).floor(); col++) {
        add(col, row);
      }
    }
  }
  return keys;
}


/// Wie ein Strich wirkt: dazu oder weg.
enum AreaDrawTool { add, remove }

/// Der Entwurf: was zum gespeicherten Bestand DAZUKOMMT und was davon
/// WEGFÄLLT (seit 0.27.0, Betreiber, 2026-09-29 — die Leiste bearbeitet
/// den ganzen Offline-Bestand, nicht nur einen neuen Bereich). Beides als
/// Kacheln bei [kAreaShapeZoom]; [adds] enthält nie eine gespeicherte,
/// [removes] nur gespeicherte Kacheln — dafür sorgt der Notifier.
@immutable
class AreaDraft {
  AreaDraft({Set<int> adds = const {}, Set<int> removes = const {}, this.history = const [], this.tool})
      : addShape = TileSetShape(zoom: kAreaShapeZoom, keys: Set.unmodifiable(adds)),
        removeShape = TileSetShape(zoom: kAreaShapeZoom, keys: Set.unmodifiable(removes));

  /// Was geladen wird — geht so in den Plan.
  final TileSetShape addShape;

  /// Was aus den gespeicherten Archiven herausgeschrieben wird.
  final TileSetShape removeShape;
  final List<({Set<int> adds, Set<int> removes})> history;
  final AreaDrawTool? tool;

  Set<int> get adds => addShape.keys;
  Set<int> get removes => removeShape.keys;
  bool get isEmpty => adds.isEmpty && removes.isEmpty;

  AreaDraft _with({AreaDrawTool? tool, bool clearTool = false}) => AreaDraft(
        adds: adds,
        removes: removes,
        history: history,
        tool: clearTool ? null : (tool ?? this.tool),
      );

  static bool _same(Set<int> a, Set<int> b) => a.length == b.length && a.containsAll(b);

  /// Ein neuer Stand; der alte wandert in die Geschichte. Ohne Änderung
  /// kein Schritt — „Rückgängig" soll immer etwas tun.
  AreaDraft _step(Set<int> nextAdds, Set<int> nextRemoves) {
    if (_same(nextAdds, adds) && _same(nextRemoves, removes)) return _with(clearTool: true);
    final h = [...history, (adds: adds, removes: removes)];
    return AreaDraft(
      adds: nextAdds,
      removes: nextRemoves,
      history: h.length > kAreaDraftHistory ? h.sublist(h.length - kAreaDraftHistory) : h,
    );
  }
}

/// Der gespeicherte Bestand als Kacheln bei [kAreaShapeZoom] — gegen ihn
/// rechnet der Entwurf („kommt dazu" nur, was nicht schon liegt).
///
/// Die ganze Region (`RegionShape`) steht NICHT darin — sie wären hundert-
/// tausende Schlüssel; gegen sie rechnet [storedRegionBoundsProvider].
final storedTileKeysProvider = Provider<Set<int>>((ref) {
  final areas = ref.watch(storedAreasProvider).valueOrNull ?? const [];
  return {
    for (final a in areas)
      if (a.shape is! RegionShape) ...a.shape.keysAt(kAreaShapeZoom),
  };
});

/// Die Rahmen der gespeicherten ganzen Regionen: Was darin liegt, kommt
/// nicht dazu — es liegt schon. Der Radierer lässt sie aus; eine Region
/// geht nur im Ganzen (in „Meine Bereiche").
final storedRegionBoundsProvider = Provider<List<AreaBounds>>((ref) {
  final areas = ref.watch(storedAreasProvider).valueOrNull ?? const [];
  return [for (final a in areas) if (a.shape case final RegionShape r) r.bounds];
});

/// Liegt die Kachel [key] (bei [kAreaShapeZoom]) ganz in einem der
/// Rahmen [regions]?
bool insideRegions(int key, List<AreaBounds> regions) {
  if (regions.isEmpty) return false;
  const z = kAreaShapeZoom;
  final b = tileBounds(z, key >> z, key & ((1 << z) - 1));
  return regions.any((r) => b.south >= r.south && b.north <= r.north && b.west >= r.west && b.east <= r.east);
}

/// Der Entwurf — null heißt leer. Er lebt, solange die Werkzeugleiste
/// „Ebenen" offen ist; beim Schließen wird er verworfen (mit Rückfrage,
/// wenn etwas darin steht — map_screen.dart).
class AreaDraftNotifier extends Notifier<AreaDraft?> {
  @override
  AreaDraft? build() => null;

  AreaDraft get _draft => state ?? AreaDraft();

  /// Steht etwas im Entwurf, das noch nicht gespeichert ist?
  bool get hasChanges => !(state?.isEmpty ?? true);

  void start() => state ??= AreaDraft();

  /// Das Werkzeug für den NÄCHSTEN Strich; derselbe Knopf noch einmal
  /// nimmt es zurück. Nach dem Strich ist es wieder weg — die Karte lässt
  /// sich zwischen zwei Strichen verschieben, ohne umzuschalten.
  void arm(AreaDrawTool tool) {
    final d = _draft;
    state = d.tool == tool ? d._with(clearTool: true) : d._with(tool: tool);
  }

  void disarm() {
    final d = state;
    if (d != null && d.tool != null) state = d._with(clearTool: true);
  }

  /// Ein Strich: seine Kacheln dazu oder weg, je nach Werkzeug.
  void applyStroke(Set<int> stroke) {
    final d = state;
    if (d == null || d.tool == null) return;
    d.tool == AreaDrawTool.add ? addAll(stroke) : removeAll(stroke);
  }

  /// Dazu: was nicht schon liegt, kommt dazu; was wegfallen sollte, bleibt.
  void addAll(Set<int> keys) {
    final d = _draft;
    final stored = ref.read(storedTileKeysProvider);
    final regions = ref.read(storedRegionBoundsProvider);
    state = d._step(
      {...d.adds, ...keys.where((k) => !stored.contains(k) && !insideRegions(k, regions))},
      {...d.removes}..removeAll(keys),
    );
  }

  /// Weg: was dazukommen sollte, kommt nicht; was liegt, fällt weg.
  void removeAll(Set<int> keys) {
    final d = _draft;
    final stored = ref.read(storedTileKeysProvider);
    state = d._step(
      {...d.adds}..removeAll(keys),
      {...d.removes, ...keys.where(stored.contains)},
    );
  }

  void undo() {
    final d = state;
    if (d == null || d.history.isEmpty) return;
    final last = d.history.last;
    state = AreaDraft(adds: last.adds, removes: last.removes, history: d.history.sublist(0, d.history.length - 1));
  }

  void discard() => state = null;

  /// Nach dem Speichern: ein leerer Entwurf, die Leiste bleibt offen.
  void clear() => state = AreaDraft();

  /// Das Entfernen ist gespeichert, das Laden nicht: Nur „kommt dazu"
  /// bleibt offen (Rückgängig kann nicht hinter Gespeichertes zurück).
  void dropRemoves() {
    final d = state;
    if (d == null) return;
    state = AreaDraft(adds: d.adds);
  }
}

final areaDraftProvider = NotifierProvider<AreaDraftNotifier, AreaDraft?>(AreaDraftNotifier.new);

/// Die Kacheln bei [zoom], die [bounds] berühren — der „Schnappschuss"
/// des Ausschnitts. Null über [maxSpanTiles] (weit draußen wäre das halb
/// Mitteleuropa bei Zoom 13).
Set<int>? tilesInBounds(AreaBounds bounds,
    {int zoom = kAreaShapeZoom, int maxSpanTiles = kAreaDrawMaxSpanTiles}) {
  if (countTilesCovering(bounds, minZoom: zoom, maxZoom: zoom) > maxSpanTiles) return null;
  return {
    for (final t in tilesCovering(bounds, minZoom: zoom, maxZoom: zoom)) TileSetShape.keyOf(t.x, t.y, zoom),
  };
}

// ---- Die Darstellung offener Änderungen ----------------------------------
//
// Design Turn 2 (seit 0.31.0; davor grün dazu, rot weg): **Helligkeit =
// was auf dem Gerät liegt, Schraffur + gestrichelter Rand = offene
// Änderung.** Die Schraffur hat immer die Gegenhelligkeit ihres Grunds,
// deshalb reicht EINE Regel für beide Richtungen, und es braucht keine
// neue Farbe — Grün heißt „mein Trail", Rot gibt es auf der Karte nicht.
//
// | Zustand     | Grund       | Schraffur | Rand         |
// |-------------|-------------|-----------|--------------|
// | kommt dazu  | dunkel      | hell `/`  | hell, gestr. |
// | fällt weg   | hell        | dunkel `\` | dunkel, gestr. |
//
// Den Grund liefert die Maske (area_overlay.dart): Was dazukommt, liegt
// noch nicht und ist deshalb abgedunkelt; was wegfällt, liegt noch und
// ist hell. Hier kommt nur die Zeichnung obendrauf.
//
// Die Schraffur sind LINIEN, keine Füllmuster: Ein Muster bräuchte in
// MapLibre ein eigenes Bild im Stil, Linien können beide Engines. Sie
// hängen am Weltraster der Kamera-Zoomstufe (x ± y = k · Abstand in
// Weltpixeln), damit sie beim Verschieben stehen bleiben und nur beim
// Zoomen neu gerechnet werden.

/// Hell: Schraffur, Rand und Strich auf dunklem Grund („kommt dazu").
const kAreaInkLight = Color(0xE6FFFFFF);

/// Dunkel: Schraffur, Rand und Strich auf hellem Grund („fällt weg") —
/// der Textton des hellen Modus.
const kAreaInkDark = Color(0xD9131A16);

/// Abstand der Schraffurlinien in Bildpunkten (Design: ~7 px).
const kAreaHatchSpacingPx = 7.0;

/// Breite einer Schraffurlinie.
const kAreaHatchWidth = 1.5;

/// Der gestrichelte Rand um eine offene Änderung.
const kAreaChangeBorderWidth = 2.0;
const kAreaChangeBorderDash = [6.0, 4.0];

/// Mehr Linien als das zeichnet die Schraffur nicht — dann gilt der
/// Rückfall 2e: eine halbe Abdunkelung (dazu: halb aufgehellt, weg: halb
/// abgedunkelt), und nur der Rand unterscheidet (weit draußen wäre die
/// Schraffur ohnehin ein Grauschleier).
const kAreaHatchMaxLines = 2500;

/// Rückfall 2e: „kommt dazu" hellt die Abdunkelung zur Hälfte auf …
const kAreaAddHalfTone = Color(0x33FFFFFF);

/// … „fällt weg" dunkelt das Helle zur Hälfte ab.
const kAreaRemoveHalfTone = Color(0x33000000);

/// Die Schraffurlinien über [rects] bei [zoom] (256er-Stufen): `/` für
/// „kommt dazu", gespiegelt `\` für „fällt weg". Null über [maxLines].
List<List<LatLng>>? hatchLines(List<AreaBounds> rects, double zoom,
    {required bool mirrored, double spacingPx = kAreaHatchSpacingPx, int maxLines = kAreaHatchMaxLines}) {
  final world = 256 * math.pow(2, zoom).toDouble();
  double wx(double lon) => (lon + 180) / 360 * world;
  double wy(double lat) {
    final r = lat.clamp(-kMercatorMaxLat, kMercatorMaxLat) * math.pi / 180;
    return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * world;
  }

  LatLng back(double x, double y) {
    final n = math.pi * (1 - 2 * y / world);
    final lat = math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi;
    return LatLng(lat, x / world * 360 - 180);
  }

  final out = <List<LatLng>>[];
  for (final r in rects) {
    final x0 = wx(r.west), x1 = wx(r.east), y0 = wy(r.north), y1 = wy(r.south);
    // `/` auf dem Schirm (y nach unten): x + y = c. Gespiegelt: x − y = c.
    final cMin = mirrored ? x0 - y1 : x0 + y0;
    final cMax = mirrored ? x1 - y0 : x1 + y1;
    for (var c = (cMin / spacingPx).ceil() * spacingPx; c <= cMax; c += spacingPx) {
      final double xa, xb;
      if (mirrored) {
        xa = math.max(x0, c + y0);
        xb = math.min(x1, c + y1);
      } else {
        xa = math.max(x0, c - y1);
        xb = math.min(x1, c - y0);
      }
      if (xb <= xa) continue;
      final ya = mirrored ? xa - c : c - xa;
      final yb = mirrored ? xb - c : c - xb;
      out.add([back(xa, ya), back(xb, yb)]);
      if (out.length > maxLines) return null;
    }
  }
  return out;
}

/// Die offenen Änderungen auf der Karte: je Seite die Schraffur in der
/// Gegenhelligkeit und ein gestrichelter Rand um die Kachelmenge — IMMER
/// bei [kAreaShapeZoom] wie die Maske, im Ausschnitt mit Rand. Flächen
/// gibt es nur im Rückfall 2e (zu viele Linien).
({List<MapViewPolygon> polygons, List<MapViewPolyline> lines}) draftLayers(
    AreaDraft draft, MapViewCamera camera) {
  final view = camera.bounds;
  if (draft.isEmpty || view.east <= view.west || view.north <= view.south) {
    return (polygons: const [], lines: const []);
  }
  final polygons = <MapViewPolygon>[];
  final hatches = <MapViewPolyline>[];
  final borders = <MapViewPolyline>[];
  for (final (shape, ink, halfTone, mirrored) in [
    (draft.addShape, kAreaInkLight, kAreaAddHalfTone, false),
    (draft.removeShape, kAreaInkDark, kAreaRemoveHalfTone, true),
  ]) {
    if (shape.keys.isEmpty) continue;
    var box = offlineOverlayBox(view);
    var tiles = shape.tilesWithin(box, kAreaShapeZoom);
    var rects = mergeTileRects(tiles);
    if (rects.length > kAreaDraftMaxRects) {
      box = offlineOverlayBox(view, margin: false);
      tiles = shape.tilesWithin(box, kAreaShapeZoom);
      rects = mergeTileRects(tiles);
    }
    if (rects.isEmpty) continue;
    final hatched = hatchLines(rects, camera.zoom, mirrored: mirrored);
    if (hatched == null) {
      for (final r in rects) {
        polygons.add(MapViewPolygon(points: rectRing(r), fillColor: halfTone));
      }
    } else {
      for (final l in hatched) {
        hatches.add(MapViewPolyline(points: l, color: ink, width: kAreaHatchWidth));
      }
    }
    for (final l in tileOutline(tiles, box) ?? const <List<LatLng>>[]) {
      borders.add(MapViewPolyline(
          points: l, color: ink, width: kAreaChangeBorderWidth, dash: kAreaChangeBorderDash));
    }
  }
  // Die Ränder über der Schraffur: Sie sagen „bis hier", auch wo die
  // Schraffur weggefallen ist.
  return (polygons: polygons, lines: [...hatches, ...borders]);
}
