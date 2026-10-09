// Kacheln aus gespeicherten Bereichen herausnehmen (seit 0.27.0; der
// Radierer der Werkzeugleiste auf hellen Kacheln, Betreiber, 2026-09-29).
// Ganz ohne Netz: Die App liest das eigene Archiv, schreibt es ohne die
// wegfallenden Kacheln neu (derselbe Schreiber wie beim Download) und
// liest es mit dem Leser beider Engines gegen. Ein Bereich, der dabei
// leer wird, verschwindet ganz.
//
// Gerechnet wird in den Kacheln der Formen ([kAreaShapeZoom]): Eine
// gröbere Kachel (Zoom 8…12) bleibt, solange noch eine ihrer Kinder im
// Bereich liegt — sonst fehlte beim Herauszoomen die Übersicht über den
// Rest. Die Begleitarchive (Höhen, seit 0.90.0 Wege) folgen den Kacheln
// der Form bei Zoom 13.
import 'dart:typed_data';

import 'package:pmtiles/pmtiles.dart';

import '../map/poi.dart';
import '../map/way_layer.dart';
import 'area_plan.dart';
import 'area_store.dart';
import 'height_tiles.dart';
import 'pmtiles_writer.dart';

/// Was mit EINEM Bereich passiert.
class AreaTrim {
  const AreaTrim({
    required this.area,
    required this.shape,
    required this.keep,
    required this.freedTiles,
    required this.freedBytes,
    this.keepHeights = const [],
    this.keepWays = const [],
  });

  final StoredArea area;

  /// Die neue Form; null heißt: der Bereich wird ganz gelöscht.
  final TileSetShape? shape;

  /// Die Kacheln, die im Archiv bleiben (alle Zooms).
  final List<TileXYZ> keep;
  final int freedTiles;

  /// Frei werdende Bytes aller Archive (Karte, Höhen, Wege).
  final int freedBytes;

  /// Die Höhenkacheln, die im zweiten Archiv bleiben (leer: keine mehr,
  /// oder der Bereich hatte nie welche).
  final List<TileXYZ> keepHeights;

  /// Die Wege-Kacheln, die im dritten Archiv bleiben.
  final List<TileXYZ> keepWays;
}

/// Der Plan des Entfernens über alle betroffenen Bereiche.
class TrimPlan {
  const TrimPlan(this.trims);

  final List<AreaTrim> trims;

  bool get isEmpty => trims.isEmpty;
  int get freedTiles => trims.fold(0, (s, t) => s + t.freedTiles);
  int get freedBytes => trims.fold(0, (s, t) => s + t.freedBytes);
}

class AreaTrimmer {
  AreaTrimmer(this.store);

  final AreaStore store;

  Future<PmTilesArchive> _open(StoredArea area) async {
    final path = await store.archivePath(area.id);
    if (path != null) return PmTilesArchive.from(path);
    final bytes = await store.readArchive(area.id);
    if (bytes == null) throw StateError('Archiv von ${area.name} fehlt');
    return PmTilesArchive.fromBytes(bytes);
  }

  late final _heights = _SideArchive(
    label: 'Höhen',
    zoom: kHeightTileZoom,
    has: (a) => a.hasHeights,
    path: store.heightsPath,
    read: store.readHeights,
    put: store.putHeights,
    delete: store.deleteHeights,
    metadata: (a) => heightsMetadata(a.name, a.heightsBuild),
  );

  late final _ways = _SideArchive(
    label: 'Wege',
    zoom: kWaysZoom,
    has: (a) => a.hasWays,
    path: store.waysPath,
    read: store.readWays,
    put: store.putWays,
    delete: store.deleteWays,
    metadata: (a) => waysMetadata(a.name, a.waysBuild),
  );

  /// Das Begleitarchiv, null wenn der Bereich keins trägt — ein Index,
  /// der eins nennt, dessen Datei fehlt, zählt wie keins (es ist
  /// nachladbar).
  Future<PmTilesArchive?> _openSide(_SideArchive side, StoredArea area) async {
    if (!side.has(area)) return null;
    final path = await side.path(area.id);
    if (path != null) return PmTilesArchive.from(path);
    final bytes = await side.read(area.id);
    return bytes == null ? null : PmTilesArchive.fromBytes(bytes);
  }

  /// Welche Kacheln eines Begleitarchivs bleiben und wie viele Bytes
  /// frei werden: eine Kachel je z13-Kachel, die in [shape] bleibt.
  Future<({List<TileXYZ> keep, int freed})> _planSide(
      _SideArchive side, StoredArea area, TileSetShape? shape) async {
    final keep = <TileXYZ>[];
    var freed = 0;
    final archive = await _openSide(side, area);
    if (archive == null) return (keep: keep, freed: freed);
    try {
      final wanted = shape?.tiles(minZoom: side.zoom, maxZoom: side.zoom).toSet() ?? const {};
      for (final t in area.shape.tiles(minZoom: side.zoom, maxZoom: side.zoom)) {
        final entry = await archive.lookup(tileIdOf(t));
        if (entry == null) continue;
        if (wanted.contains(t)) {
          keep.add(t);
        } else {
          freed += entry.length;
        }
      }
    } finally {
      await archive.close();
    }
    return (keep: keep, freed: freed);
  }

  /// Was [removes] (Kacheln bei [kAreaShapeZoom]) mit den Bereichen
  /// macht. Gemessen, nicht geschätzt: Die frei werdenden Bytes kommen
  /// aus dem Verzeichnis des jeweiligen Archivs.
  Future<TrimPlan> plan(List<StoredArea> areas, Set<int> removes) async {
    final trims = <AreaTrim>[];
    if (removes.isEmpty) return const TrimPlan([]);
    for (final area in areas) {
      final keys = area.shape.keysAt(kAreaShapeZoom);
      if (!keys.any(removes.contains)) continue;
      final remaining = keys.difference(removes);
      final shape = remaining.isEmpty ? null : TileSetShape(zoom: kAreaShapeZoom, keys: remaining);
      final wanted = shape?.tiles(minZoom: area.minZoom, maxZoom: area.maxZoom).toSet() ?? const <TileXYZ>{};
      final archive = await _open(area);
      try {
        final keep = <TileXYZ>[];
        var freedTiles = 0, freedBytes = 0;
        for (final t in area.shape.tiles(minZoom: area.minZoom, maxZoom: area.maxZoom)) {
          final entry = await archive.lookup(tileIdOf(t));
          if (entry == null) continue; // lag nie im Archiv
          if (wanted.contains(t)) {
            keep.add(t);
          } else {
            freedTiles++;
            freedBytes += entry.length;
          }
        }
        // Höhen und Wege folgen den Kacheln der Form.
        final heights = await _planSide(_heights, area, shape);
        final ways = await _planSide(_ways, area, shape);
        trims.add(AreaTrim(
          area: area,
          shape: keep.isEmpty ? null : shape,
          keep: keep,
          freedTiles: freedTiles,
          freedBytes: keep.isEmpty ? area.totalBytes : freedBytes + heights.freed + ways.freed,
          keepHeights: keep.isEmpty ? const [] : heights.keep,
          keepWays: keep.isEmpty ? const [] : ways.keep,
        ));
      } finally {
        await archive.close();
      }
    }
    return TrimPlan(trims);
  }

  /// Führt [plan] aus: je Bereich neu schreiben oder löschen, dann EIN
  /// neuer Index.
  Future<void> apply(TrimPlan plan) async {
    if (plan.isEmpty) return;
    final updated = <String, StoredArea?>{};
    for (final trim in plan.trims) {
      final area = trim.area;
      final shape = trim.shape;
      if (shape == null) {
        await store.delete(area.id);
        updated[area.id] = null;
        continue;
      }
      final archive = await _open(area);
      final Uint8List bytes;
      try {
        final ids = {for (final t in trim.keep) tileIdOf(t): t};
        final kept = <TileToWrite>[];
        final sorted = ids.keys.toList()..sort();
        for (var start = 0; start < sorted.length; start += 256) {
          final chunk = sorted.sublist(start, start + 256 > sorted.length ? sorted.length : start + 256);
          await for (final tile in archive.tiles(chunk)) {
            final t = ids[tile.id]!;
            kept.add(TileToWrite(t.z, t.x, t.y, Uint8List.fromList(tile.compressedBytes())));
          }
        }
        final hull = shape.hull;
        bytes = writePmTiles(
          tiles: kept,
          tileCompression: archive.header.tileCompression,
          bounds: TileBounds(west: hull.west, south: hull.south, east: hull.east, north: hull.north),
          metadata: {
            'name': area.name,
            'source_build': area.build,
            'attribution': '© OpenStreetMap contributors · Protomaps (ODbL)',
          },
        );
        if (kept.length != trim.keep.length) {
          throw StateError('${area.name}: ${kept.length} statt ${trim.keep.length} Kacheln gelesen');
        }
      } finally {
        await archive.close();
      }
      // Gegenlesen, bevor das alte Archiv ersetzt wird.
      final check = await PmTilesArchive.fromBytes(bytes);
      try {
        if (check.header.numberOfAddressedTiles != trim.keep.length) {
          throw StateError('${area.name}: neues Archiv zählt falsch');
        }
      } finally {
        await check.close();
      }
      await store.putArchive(area.id, bytes);
      final heightBytes = await _rewriteSide(_heights, area, trim.shape!, trim.keepHeights);
      final wayBytes = await _rewriteSide(_ways, area, trim.shape!, trim.keepWays);
      // Orte-Dateien nur noch für Zellen, die der Bereich noch berührt.
      final cells = shape.poiCells().toSet();
      final wantedPoi = {
        for (final c in cells)
          for (final g in PoiGroup.values) poiCellFileName(c, g),
      };
      updated[area.id] = StoredArea(
        id: area.id,
        name: area.name,
        bounds: shape.hull,
        shape: shape,
        minZoom: area.minZoom,
        maxZoom: area.maxZoom,
        build: area.build,
        tiles: trim.keep.length,
        bytes: bytes.length,
        savedAt: area.savedAt,
        poiFiles: [for (final f in area.poiFiles) if (wantedPoi.contains(f)) f],
        poiBuild: area.poiBuild,
        heightTiles: trim.keepHeights.length,
        heightBytes: heightBytes,
        heightsBuild: trim.keepHeights.isEmpty ? null : area.heightsBuild,
        wayTiles: trim.keepWays.length,
        wayBytes: wayBytes,
        // Der Bau bleibt auch ohne Wege-Kachel: geholt ist geholt.
        waysBuild: area.waysBuild,
        region: area.region,
      );
    }
    final next = <StoredArea>[
      for (final a in await store.list())
        if (!updated.containsKey(a.id)) a else if (updated[a.id] != null) updated[a.id]!,
    ];
    await store.saveIndex(next);
  }

  /// Schreibt ein Begleitarchiv ohne die wegfallenden Kacheln neu (oder
  /// nimmt es weg, wenn keine bleibt); liefert seine neue Größe.
  Future<int> _rewriteSide(_SideArchive side, StoredArea area, TileSetShape shape, List<TileXYZ> keep) async {
    final archive = await _openSide(side, area);
    if (archive == null) return 0;
    if (keep.isEmpty) {
      await archive.close();
      await side.delete(area.id);
      return 0;
    }
    final Uint8List bytes;
    try {
      final ids = {for (final t in keep) tileIdOf(t): t};
      final kept = <TileToWrite>[];
      final sorted = ids.keys.toList()..sort();
      for (var start = 0; start < sorted.length; start += 256) {
        final chunk = sorted.sublist(start, start + 256 > sorted.length ? sorted.length : start + 256);
        await for (final tile in archive.tiles(chunk)) {
          final t = ids[tile.id]!;
          kept.add(TileToWrite(t.z, t.x, t.y, Uint8List.fromList(tile.compressedBytes())));
        }
      }
      final hull = shape.hull;
      bytes = writePmTiles(
        tiles: kept,
        tileCompression: archive.header.tileCompression,
        bounds: TileBounds(west: hull.west, south: hull.south, east: hull.east, north: hull.north),
        metadata: side.metadata(area),
      );
      if (kept.length != keep.length) {
        throw StateError('${area.name}: ${kept.length} statt ${keep.length} Kacheln (${side.label}) gelesen');
      }
    } finally {
      await archive.close();
    }
    final check = await PmTilesArchive.fromBytes(bytes);
    try {
      if (check.header.numberOfAddressedTiles != keep.length) {
        throw StateError('${area.name}: neues Archiv (${side.label}) zählt falsch');
      }
    } finally {
      await check.close();
    }
    await side.put(area.id, bytes);
    return bytes.length;
  }
}

/// Ein Begleitarchiv des Bereichs (Höhen, Wege): eine Kachel je
/// z13-Kachel der Form, eigene Ablage-Wege.
class _SideArchive {
  const _SideArchive({
    required this.label,
    required this.zoom,
    required this.has,
    required this.path,
    required this.read,
    required this.put,
    required this.delete,
    required this.metadata,
  });

  final String label;
  final int zoom;
  final bool Function(StoredArea area) has;
  final Future<String?> Function(String id) path;
  final Future<Uint8List?> Function(String id) read;
  final Future<void> Function(String id, Uint8List bytes) put;
  final Future<void> Function(String id) delete;
  final Map<String, dynamic> Function(StoredArea area) metadata;
}
