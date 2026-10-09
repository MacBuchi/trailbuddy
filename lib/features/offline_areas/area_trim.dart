// Kacheln aus gespeicherten Bereichen herausnehmen (seit 0.27.0; der
// Radierer der Werkzeugleiste auf hellen Kacheln, Betreiber, 2026-09-29).
// Ganz ohne Netz. Seit 0.106.0 (#229) schreibt er kein Archiv mehr neu:
// Er nimmt die Kacheln aus den FORMEN der Bereiche, und aus dem
// Kachelspeicher geht nur, was danach keine Form mehr deckt — eine Kachel,
// die ein zweiter Bereich auch braucht, bleibt (`tile_refs.dart`). Ein
// Bereich, der dabei leer wird, verschwindet ganz.
//
// Gerechnet wird in den Kacheln der Formen ([kAreaShapeZoom]): Eine
// gröbere Kachel (Zoom 8…12) bleibt, solange noch eine ihrer Kinder in
// einer Form liegt — sonst fehlte beim Herauszoomen die Übersicht über den
// Rest. Höhen und Wege folgen den Kacheln der Form bei Zoom 13.
import '../map/poi.dart';
import 'area_plan.dart';
import 'area_store.dart';
import 'tile_refs.dart';
import 'tile_store.dart';

/// Was mit EINEM Bereich passiert.
class AreaTrim {
  const AreaTrim({required this.area, required this.shape});

  final StoredArea area;

  /// Die neue Form; null heißt: der Bereich wird ganz gelöscht.
  final TileSetShape? shape;
}

/// Der Plan des Entfernens über alle betroffenen Bereiche.
class TrimPlan {
  const TrimPlan(this.trims, {this.orphans = (tiles: const <LayerOrphans>[], poiFiles: const <String>[])});

  final List<AreaTrim> trims;

  /// Was danach niemandem mehr gehört — das, was wirklich frei wird.
  final ({List<LayerOrphans> tiles, List<String> poiFiles}) orphans;

  bool get isEmpty => trims.isEmpty;

  /// Kartenkacheln, die vom Gerät gehen.
  int get freedTiles => orphanMapTiles(orphans);

  /// Frei werdende Bytes aller Ebenen (Karte, Höhen, Wege), aus dem Index
  /// gemessen.
  int get freedBytes => orphanBytes(orphans);
}

class AreaTrimmer {
  AreaTrimmer(this.store, this.tiles);

  final AreaStore store;
  final TileStore tiles;

  /// Der Bereich mit [shape] statt seiner Form — die Orte-Dateien nur noch
  /// für Zellen, die er noch berührt.
  static StoredArea _trimmed(StoredArea area, TileSetShape shape) {
    final wanted = {
      for (final c in shape.poiCells())
        for (final g in PoiGroup.values) poiCellFileName(c, g),
    };
    return area.copyWith(
      shape: shape,
      poiFiles: [for (final f in area.poiFiles) if (wanted.contains(f)) f],
    );
  }

  /// Was [removes] (Kacheln bei [kAreaShapeZoom]) mit den Bereichen
  /// macht. Gemessen, nicht geschätzt: Die frei werdenden Bytes kommen aus
  /// dem Index des Speichers.
  Future<TrimPlan> plan(List<StoredArea> areas, Set<int> removes) async {
    if (removes.isEmpty) return const TrimPlan([]);
    final trims = <AreaTrim>[];
    for (final area in areas) {
      // Die ganze Region geht nur im Ganzen (Konzept 8.2, Schritt 5): Als
      // Kachelmenge wäre sie hunderttausende Schlüssel.
      if (area.shape is RegionShape) continue;
      final keys = area.shape.keysAt(kAreaShapeZoom);
      if (!keys.any(removes.contains)) continue;
      final remaining = keys.difference(removes);
      trims.add(AreaTrim(
        area: area,
        shape: remaining.isEmpty ? null : TileSetShape(zoom: kAreaShapeZoom, keys: remaining),
      ));
    }
    if (trims.isEmpty) return const TrimPlan([]);
    final orphans = await orphansAfter(
      store: tiles,
      remaining: _after(areas, trims),
      regions: {for (final t in trims) t.area.region},
      gone: [for (final t in trims) t.area],
    );
    return TrimPlan(trims, orphans: orphans);
  }

  static List<StoredArea> _after(List<StoredArea> areas, List<AreaTrim> trims) {
    final byId = {for (final t in trims) t.area.id: t};
    final out = <StoredArea>[];
    for (final a in areas) {
      final t = byId[a.id];
      if (t == null) {
        out.add(a);
      } else if (t.shape case final shape?) {
        out.add(_trimmed(a, shape));
      }
    }
    return out;
  }

  /// Führt [plan] aus: erst der neue Index (die Formen), dann weg, was
  /// keine Form mehr deckt. Bricht es dazwischen ab, liegen Kacheln, die
  /// niemandem gehören — das nächste Löschen in der Region räumt sie mit.
  Future<void> apply(TrimPlan plan) async {
    if (plan.isEmpty) return;
    await store.saveIndex(_after(await store.list(), plan.trims));
    await removeOrphans(tiles, store, plan.orphans);
  }
}
