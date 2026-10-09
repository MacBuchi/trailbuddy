// Die Hervorhebung gespeicherter Kacheln (Offline-Karten, Stufe B;
// Betreiber, 2026-09-28: „die offline Kacheln hervorgehoben darstellen
// bzw. die anderen ausgegraut"), pur: aus den gespeicherten Bereichen
// und dem Ausschnitt EIN Polygon — die Abdunkelung über dem Ausschnitt
// (und einem Rand darum herum, damit ein Wischen nicht sofort ins Helle
// führt), mit den gespeicherten Kacheln als Löchern.
//
// **Immer die echten Kacheln, bei JEDEM Kamera-Zoom** (seit 0.27.0,
// Betreiber, 2026-09-29: „die gespeicherten Kacheln verändern sich je
// Zoom — die Kacheln sind groß genug, dass man sie gleich in der
// Detailansicht zeigen kann"). Bis 0.26.x zeigte die Maske zwei Stufen
// über der Kamera, weit draußen also die groben Eltern, und die
// Hervorhebung sprang beim Zoomen. Jetzt ist es der Zoom des Bereichs
// (13, die Stufe der Formen). Damit weit draußen nicht tausende Löcher
// entstehen, fasst [mergeTileRects] zusammenhängende Kacheln zu
// Rechtecken zusammen — eine Fläche aus Kacheln bleibt eine Handvoll
// Rechtecke. Gerechnet wird aus den FORMEN im Index, nicht aus den
// Archiven.
//
// **Um den ganzen Bestand läuft ein durchgehender Rand** (Design Turn 2,
// seit 0.31.0): Helligkeit allein sagt „liegt", der Rand sagt „bis hier".
// Er ist der Umriss der Kachelmenge ([tileOutline]), nicht der Rand der
// Rechtecke — die Nähte zwischen zwei Rechtecken sähen sonst aus wie ein
// Gitter.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../map/map_view/map_view.dart';
import 'area_plan.dart';
import 'area_store.dart';

/// Die Abdunkelung: dunkel genug, dass der Unterschied sofort zu sehen
/// ist, hell genug, dass die Karte darunter lesbar bleibt.
const kOfflineDimColor = Color(0x66000000);

/// Der Rand um den Bestand: durchgehend, in der Textfarbe des App-Modus
/// (Design Turn 2: dunkel hell, hell `#131A16`) — die Farbe kommt vom
/// Aufrufer, die Breite steht hier.
const kOfflineOutlineWidth = 2.0;

/// Mehr Linienstücke als das bekommt ein Umriss nicht — weit draußen
/// wäre er ohnehin nur ein Saum um die Löcher; dann trägt die Helligkeit
/// allein.
const kOfflineOutlineMaxLines = 4000;

/// Mehr Rechtecke als das zeichnet die Maske nur im Ausschnitt selbst,
/// ohne den Rand darum — nie gröber: Die Kacheln sollen beim Zoomen
/// stehen bleiben.
const kOfflineOverlayMaxHoles = 3000;

/// Der Zoom, in dem ein Bereich hervorgehoben wird: seine feinste Stufe,
/// höchstens die der Formen.
int offlineOverlayZoomOf(StoredArea area) => math.min(area.maxZoom, kAreaShapeZoom);

/// Der Ausschnitt plus je eine Fensterbreite und -höhe Rand.
AreaBounds offlineOverlayBox(MapViewBounds view, {bool margin = true}) {
  final w = view.east - view.west, h = view.north - view.south;
  final f = margin ? 1.0 : 0.0;
  return AreaBounds(
    south: (view.south - f * h).clamp(-85.0, 85.0),
    west: (view.west - f * w).clamp(-180.0, 180.0),
    north: (view.north + f * h).clamp(-85.0, 85.0),
    east: (view.east + f * w).clamp(-180.0, 180.0),
  );
}

/// Kacheln EINES Zooms zu Rechtecken: erst je Zeile die Läufe
/// nebeneinander, dann gleiche Läufe übereinander. Keine Überlappung,
/// keine Lücke — die Vereinigung ist genau die Kachelmenge.
List<AreaBounds> mergeTileRects(Iterable<TileXYZ> tiles) {
  final byRow = <int, List<int>>{};
  var z = -1;
  for (final t in tiles) {
    z = t.z;
    (byRow[t.y] ??= []).add(t.x);
  }
  if (byRow.isEmpty) return const [];
  // Läufe je Zeile: (x0, x1).
  final rows = byRow.keys.toList()..sort();
  final open = <(int, int), int>{}; // Lauf → Zeile, in der er beginnt
  final out = <AreaBounds>[];
  void close((int, int) run, int y0, int y1) {
    final nw = tileBounds(z, run.$1, y0);
    final se = tileBounds(z, run.$2, y1);
    out.add(AreaBounds(south: se.south, west: nw.west, north: nw.north, east: se.east));
  }

  int? prevRow;
  for (final y in rows) {
    final xs = byRow[y]!..sort();
    final runs = <(int, int)>{};
    var a = xs.first, b = xs.first;
    for (final x in xs.skip(1)) {
      if (x == b) continue;
      if (x == b + 1) {
        b = x;
      } else {
        runs.add((a, b));
        a = b = x;
      }
    }
    runs.add((a, b));
    // Läufe, die in dieser Zeile nicht weitergehen (oder nach einer
    // Lückenzeile), schließen.
    for (final run in open.keys.toList()) {
      if (prevRow != y - 1 || !runs.contains(run)) {
        close(run, open.remove(run)!, prevRow!);
      }
    }
    for (final run in runs) {
      open.putIfAbsent(run, () => y);
    }
    prevRow = y;
  }
  for (final e in open.entries) {
    close(e.key, e.value, prevRow!);
  }
  return out;
}

List<LatLng> rectRing(AreaBounds b) => [
      LatLng(b.north, b.west),
      LatLng(b.north, b.east),
      LatLng(b.south, b.east),
      LatLng(b.south, b.west),
    ];

/// Die Maske für [areas] im Ausschnitt [view] — null nur, wenn der
/// Ausschnitt leer ist. Ohne Bereiche ist alles dunkel: Das IST die
/// Aussage.
MapViewPolygon? offlineCoverageMask(List<StoredArea> areas, MapViewBounds view) =>
    offlineCoverage(areas, view).mask;

/// Maske UND durchgehender Rand um den Bestand, im selben Rahmen (mit
/// Rand, weit draußen ohne). Der Rand fehlt ohne Bereiche, ohne
/// [outlineColor] und über [kOfflineOutlineMaxLines].
({MapViewPolygon? mask, List<MapViewPolyline> outline}) offlineCoverage(
    List<StoredArea> areas, MapViewBounds view,
    {Color? outlineColor}) {
  if (view.east <= view.west || view.north <= view.south) return (mask: null, outline: const []);
  var box = offlineOverlayBox(view);
  var regions = _regionRects(areas, box);
  var byZoom = _tilesByZoom(areas, box, regions);
  var holes = _holes(byZoom);
  if (holes.length > kOfflineOverlayMaxHoles) {
    box = offlineOverlayBox(view, margin: false);
    regions = _regionRects(areas, box);
    byZoom = _tilesByZoom(areas, box, regions);
    holes = _holes(byZoom);
  }
  holes = [...holes, for (final r in regions) rectRing(r)];
  final outline = <MapViewPolyline>[];
  if (outlineColor != null) {
    for (final tiles in byZoom.values) {
      final lines = tileOutline(tiles, box);
      if (lines == null) {
        outline.clear();
        break;
      }
      for (final l in lines) {
        outline.add(MapViewPolyline(points: l, color: outlineColor, width: kOfflineOutlineWidth));
      }
    }
  }
  return (
    mask: MapViewPolygon(points: rectRing(box), holes: holes, fillColor: kOfflineDimColor),
    outline: outline,
  );
}

List<List<LatLng>> _holes(Map<int, Set<TileXYZ>> byZoom) => [
      for (final tiles in byZoom.values)
        for (final r in mergeTileRects(tiles)) rectRing(r),
    ];

/// Die ganzen Regionen (Schritt 5) im Ausschnitt [box]: je EIN Rechteck,
/// auf das Kachelraster von [kAreaShapeZoom] gerastet — als Kacheln wären
/// es weit draußen hunderttausende.
List<AreaBounds> _regionRects(List<StoredArea> areas, AreaBounds box) {
  final out = <AreaBounds>[];
  for (final a in areas) {
    if (a.shape case final RegionShape r) {
      final b = r.bounds;
      if (!b.intersects(box)) continue;
      const z = kAreaShapeZoom;
      final nw = tileAt(math.min(b.north, box.north), math.max(b.west, box.west), z);
      final se = tileAt(math.max(b.south, box.south), math.min(b.east, box.east), z);
      final top = tileBounds(z, nw.x, nw.y), bottom = tileBounds(z, se.x, se.y);
      out.add(AreaBounds(south: bottom.south, west: top.west, north: top.north, east: bottom.east));
    }
  }
  return out;
}

bool _within(TileXYZ t, List<AreaBounds> rects) {
  if (rects.isEmpty) return false;
  final b = tileBounds(t.z, t.x, t.y);
  const eps = 1e-9;
  return rects.any((r) =>
      b.south >= r.south - eps && b.north <= r.north + eps && b.west >= r.west - eps && b.east <= r.east + eps);
}

/// Die Kacheln der Bereiche in [box], je Zoom gesammelt: Bereiche mit
/// verschiedenem Zoom (ein alter bis 10) liegen sonst doppelt übereinander.
/// Was in einer ganzen Region liegt, fällt weg — ihr Rechteck ist schon
/// ein Loch, und zwei Löcher übereinander füllten sich wieder.
Map<int, Set<TileXYZ>> _tilesByZoom(List<StoredArea> areas, AreaBounds box, List<AreaBounds> regions) {
  final byZoom = <int, Set<TileXYZ>>{};
  for (final a in areas) {
    if (a.shape is RegionShape) continue;
    final z = offlineOverlayZoomOf(a);
    if (z < a.minZoom) continue;
    (byZoom[z] ??= {}).addAll(a.shape.tilesWithin(box, z).where((t) => !_within(t, regions)));
  }
  return byZoom;
}

/// Der Umriss einer Kachelmenge EINES Zooms: jede Kachelkante, auf deren
/// anderer Seite keine Kachel der Menge liegt, zu geraden Läufen
/// zusammengefasst (eine Linie je Lauf, nicht je Kante). Kanten zu einem
/// Nachbarn außerhalb von [box] fehlen — was dort liegt, ist nicht
/// gefragt worden, und ein Rand am Bildrand wäre erfunden. Null über
/// [maxLines].
List<List<LatLng>>? tileOutline(Iterable<TileXYZ> tiles, AreaBounds box,
    {int maxLines = kOfflineOutlineMaxLines}) {
  final set = <(int, int)>{};
  var z = -1;
  for (final t in tiles) {
    z = t.z;
    set.add((t.x, t.y));
  }
  if (set.isEmpty) return const [];
  final nw = tileAt(box.north, box.west, z);
  final se = tileAt(box.south, box.east, z);
  bool known(int x, int y) => x >= nw.x && x <= se.x && y >= nw.y && y <= se.y;

  // Waagerechte Kanten je Gitterlinie y (die Oberkante der Zeile y), als
  // Spalten x; senkrechte je Gitterlinie x, als Zeilen y.
  final horizontal = <int, List<int>>{};
  final vertical = <int, List<int>>{};
  for (final (x, y) in set) {
    if (!set.contains((x, y - 1)) && known(x, y - 1)) (horizontal[y] ??= []).add(x);
    if (!set.contains((x, y + 1)) && known(x, y + 1)) (horizontal[y + 1] ??= []).add(x);
    if (!set.contains((x - 1, y)) && known(x - 1, y)) (vertical[x] ??= []).add(y);
    if (!set.contains((x + 1, y)) && known(x + 1, y)) (vertical[x + 1] ??= []).add(y);
  }

  final n = 1 << z;
  double lon(int x) => x / n * 360 - 180;
  double lat(int y) => tileBounds(z, 0, y).north;
  final out = <List<LatLng>>[];
  // Aufeinanderfolgende Kanten derselben Linie zu einem Lauf.
  bool runs(Map<int, List<int>> edges, List<LatLng> Function(int line, int a, int b) segment) {
    for (final e in edges.entries) {
      final at = e.value..sort();
      var a = at.first, b = at.first;
      for (final v in at.skip(1)) {
        if (v == b + 1) {
          b = v;
          continue;
        }
        out.add(segment(e.key, a, b + 1));
        a = b = v;
      }
      out.add(segment(e.key, a, b + 1));
      if (out.length > maxLines) return false;
    }
    return true;
  }

  if (!runs(horizontal, (y, a, b) => [LatLng(lat(y), lon(a)), LatLng(lat(y), lon(b))])) return null;
  if (!runs(vertical, (x, a, b) => [LatLng(lat(a), lon(x)), LatLng(lat(b), lon(x))])) return null;
  return out;
}
