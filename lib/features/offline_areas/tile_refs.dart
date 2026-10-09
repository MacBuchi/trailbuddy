// Bereiche als Verweise (#229, Konzept 8.2): Was liegen soll, ist die
// Vereinigung der Formen. Daraus folgen die Regeln des Betreibers —
// speichern lädt nur, was fehlt; löschen entfernt nur, was keine andere
// Form mehr deckt. Hier steht die eine Rechnung dafür, für Kacheln je
// Region und Ebene und für die Orte-Dateien.
//
// Je Zoom gilt dieselbe Regel wie beim Planen (`AreaShape.tiles`): Eine
// gröbere Kachel gehört zu einer Form, sobald die Form sie berührt — sonst
// fehlte beim Herauszoomen die Übersicht über den Rest. Unvollständige
// Bereiche zählen mit: Was ein abgebrochener Download schon geschrieben
// hat, gehört ihm, bis er gelöscht wird.
import '../map/way_layer.dart' show kWaysZoom;
import 'area_plan.dart';
import 'area_store.dart';
import 'height_tiles.dart' show kHeightTileZoom;
import 'tile_store.dart';

/// Die Zoomstufen, die ein Bereich in [layer] deckt.
({int min, int max}) zoomsOf(StoredArea area, TileLayer layer) => switch (layer) {
      TileLayer.map => (min: area.minZoom, max: area.maxZoom),
      TileLayer.heights => (min: kHeightTileZoom, max: kHeightTileZoom),
      TileLayer.ways => (min: kWaysZoom, max: kWaysZoom),
    };

/// Die Kachel-Ids, die [areas] in [layer] decken.
Set<int> referencedTileIds(Iterable<StoredArea> areas, TileLayer layer) {
  final out = <int>{};
  for (final a in areas) {
    final z = zoomsOf(a, layer);
    for (final t in a.shape.tiles(minZoom: z.min, maxZoom: z.max)) {
      out.add(tileIdOf(t));
    }
  }
  return out;
}

/// Was in einer Region und Ebene niemandem mehr gehört.
class LayerOrphans {
  const LayerOrphans(this.region, this.layer, this.ids, this.bytes);

  final String region;
  final TileLayer layer;
  final List<int> ids;
  final int bytes;
}

/// Was frei würde, wenn in den Regionen [regions] nur noch [remaining]
/// läge: je Region und Ebene die Kacheln, die keine der verbleibenden
/// Formen deckt, mit ihren Bytes aus dem Index — gemessen, nicht geschätzt.
/// Dazu die Orte-Dateien, die keiner der verbleibenden Bereiche nennt.
Future<({List<LayerOrphans> tiles, List<String> poiFiles})> orphansAfter({
  required TileStore store,
  required List<StoredArea> remaining,
  required Set<String> regions,
  Iterable<StoredArea> gone = const [],
}) async {
  final out = <LayerOrphans>[];
  for (final region in regions) {
    final here = [for (final a in remaining) if (a.region == region) a];
    for (final layer in TileLayer.values) {
      final index = await store.index(region, layer);
      if (index.isEmpty) continue;
      final keep = referencedTileIds(here, layer);
      final ids = <int>[];
      var bytes = 0;
      for (final e in index.entries) {
        if (keep.contains(e.key)) continue;
        ids.add(e.key);
        bytes += e.value.bytes;
      }
      if (ids.isNotEmpty) out.add(LayerOrphans(region, layer, ids, bytes));
    }
  }
  final named = {for (final a in remaining) ...a.poiFiles};
  final poi = {
    for (final a in gone)
      for (final f in a.poiFiles)
        if (!named.contains(f)) f,
  }.toList()
    ..sort();
  return (tiles: out, poiFiles: poi);
}

/// Nimmt weg, was [orphansAfter] gefunden hat.
Future<void> removeOrphans(
  TileStore store,
  AreaStore areas,
  ({List<LayerOrphans> tiles, List<String> poiFiles}) orphans,
) async {
  for (final o in orphans.tiles) {
    await store.remove(o.region, o.layer, o.ids);
  }
  if (orphans.poiFiles.isNotEmpty) await areas.deletePoiFiles(orphans.poiFiles);
}

int orphanBytes(({List<LayerOrphans> tiles, List<String> poiFiles}) orphans) =>
    orphans.tiles.fold(0, (s, o) => s + o.bytes);

int orphanMapTiles(({List<LayerOrphans> tiles, List<String> poiFiles}) orphans) =>
    orphans.tiles.where((o) => o.layer == TileLayer.map).fold(0, (s, o) => s + o.ids.length);

/// Die liegenden Kacheln aus einem Bau älter als [build], die eine Form
/// noch deckt (Konzept 8.2, „Alter je Kachel"): Kachel-Ids und ihre Bytes,
/// wie sie liegen. Was nicht liegt, ist nicht veraltet, sondern fehlt —
/// das holt „Fortsetzen", nicht „Aktualisieren". Ohne [build] (kein
/// Manifest) ist nichts veraltet.
({List<int> ids, int bytes}) staleTiles(Map<int, StoredTileInfo> index, Set<int> referenced, String? build) {
  if (build == null) return (ids: const <int>[], bytes: 0);
  final ids = <int>[];
  var bytes = 0;
  for (final id in referenced) {
    final have = index[id];
    if (have == null || have.build.compareTo(build) >= 0) continue;
    ids.add(id);
    bytes += have.bytes;
  }
  ids.sort();
  return (ids: ids, bytes: bytes);
}
