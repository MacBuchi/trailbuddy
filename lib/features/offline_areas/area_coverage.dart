// Deckt der Kachelspeicher einen Ausschnitt ganz? (#596 H3)
//
// PUR, ohne Speicher und ohne Karte: Die Antwort kommt aus den FORMEN der
// fertigen Bereiche, nicht aus dem Index der Datei. Eine Form nennt je
// Zoom genau die Kacheln, die der Download geholt hat (`AreaShape.tiles`,
// dieselbe Rechnung wie beim Planen), und jede liegende Kachel ist die
// ganze Kachel des Hosts — auch eine Zoom-8-Kachel, die die Form nur am
// Rand berührt.
import 'dart:math' as math;

import 'area_plan.dart';
import 'area_store.dart';

/// Was ein Bereich zur Deckung beiträgt.
typedef CoverArea = ({AreaShape shape, int minZoom, int maxZoom, bool ways});

/// Die Bereiche, deren Kacheln sicher liegen: fertig geladen, schon im
/// Kachelspeicher (kein Altbestand) und keine Halter „Unterwegs geladen"
/// (deren Kacheln sind lückenhaft, #478).
List<CoverArea> coverAreasOf(Iterable<StoredArea> areas) => [
  for (final a in visibleAreas(areas))
    if (a.complete && !a.legacy)
      (
        shape: a.shape,
        minZoom: a.minZoom,
        maxZoom: a.maxZoom,
        ways: a.wayTiles > 0,
      ),
];

/// Liegt bei Zoom [z] jede Kachel, die [box] berührt, in einem der
/// [areas]? [ways]: nur Bereiche mit Wegen zählen, ohne Blick auf ihren
/// Kartenzoom (Wege gibt es auf einer einzigen Stufe).
bool areasCover(
  List<CoverArea> areas,
  AreaBounds box,
  int z, {
  bool ways = false,
}) {
  final have = <int>{};
  for (final a in areas) {
    if (ways) {
      if (!a.ways) continue;
    } else if (z < a.minZoom || z > a.maxZoom) {
      continue;
    }
    for (final t in a.shape.tilesWithin(box, z)) {
      have.add(TileSetShape.keyOf(t.x, t.y, z));
    }
  }
  if (have.isEmpty) return false;
  final nw = tileAt(box.north, box.west, z);
  final se = tileAt(box.south, box.east, z);
  for (var x = nw.x; x <= se.x; x++) {
    for (var y = nw.y; y <= se.y; y++) {
      if (!have.contains(TileSetShape.keyOf(x, y, z))) return false;
    }
  }
  return true;
}

/// [box] um [margin] seiner Breite und Höhe je Seite größer — der Rand,
/// den die Karte beim nächsten Schwenk zuerst zeigt.
AreaBounds grownBy(AreaBounds box, double margin) {
  final dLat = (box.north - box.south) * margin;
  final dLon = (box.east - box.west) * margin;
  return AreaBounds(
    south: math.max(-85, box.south - dLat),
    west: math.max(-180, box.west - dLon),
    north: math.min(85, box.north + dLat),
    east: math.min(180, box.east + dLon),
  );
}
