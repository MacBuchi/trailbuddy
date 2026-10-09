// Die Übernahme des Altbestands (#229, Konzept 8.5): Bis 0.105.x trug
// jeder Bereich eigene Archive (Karte, Höhen, Wege) und eigene
// Orte-Dateien. Beim ersten Start der neuen Fassung liest die App sie
// LOKAL aus — ohne Netz — und legt jede Kachel mit dem Bau ihres Bereichs
// in den Kachelspeicher, jede Orte-Datei unter ihren Namen.
//
// Erst wenn alle Kacheln eines Bereichs im Speicher stehen und eine
// Stichprobe stimmt, wird sein Eintrag zum Verweis und sein Altbestand
// gelöscht. Scheitert es, bleibt der Eintrag, wie er war, und der nächste
// Start versucht es wieder — was schon geschrieben ist, liegt dann schon
// (Ersetzen statt Doppeln). Die Formen bleiben, wie sie sind.
import 'dart:typed_data';

import 'package:pmtiles/pmtiles.dart';

import '../../core/errors.dart';
import 'area_plan.dart';
import 'area_store.dart';
import 'height_tiles.dart' show kHeightTileZoom;
import 'tile_store.dart';
import '../map/way_layer.dart' show kWaysZoom;

/// Übernimmt jeden Bereich im Altformat und liefert den Index danach.
Future<List<StoredArea>> migrateLegacyAreas(AreaStore store, TileStore tiles, {int chunkSize = 256}) async {
  final legacy = [for (final a in await store.list()) if (a.legacy) a];
  for (final area in legacy) {
    try {
      await _migrate(store, tiles, area, chunkSize);
      final now = await store.list();
      await store.saveIndex([for (final a in now) a.id == area.id ? a.copyWith(format: kStoredAreaFormat) : a]);
      await store.deleteLegacy(area.id);
    } catch (e, s) {
      logError('Bereich in den Kachelspeicher übernehmen', e, s);
    }
  }
  return store.list();
}

Future<void> _migrate(AreaStore store, TileStore tiles, StoredArea area, int chunkSize) async {
  await _copy(
    await _open(store.archivePath(area.id), store.readArchive(area.id)),
    tiles,
    area.region,
    TileLayer.map,
    area.shape.tiles(minZoom: area.minZoom, maxZoom: area.maxZoom),
    area.build,
    chunkSize,
  );
  if (area.hasHeights) {
    await _copy(
      await _open(store.heightsPath(area.id), store.readHeights(area.id)),
      tiles,
      area.region,
      TileLayer.heights,
      area.shape.tiles(minZoom: kHeightTileZoom, maxZoom: kHeightTileZoom),
      area.heightsBuild ?? area.build,
      chunkSize,
    );
  }
  if (area.hasWays) {
    await _copy(
      await _open(store.waysPath(area.id), store.readWays(area.id)),
      tiles,
      area.region,
      TileLayer.ways,
      area.shape.tiles(minZoom: kWaysZoom, maxZoom: kWaysZoom),
      area.waysBuild ?? area.build,
      chunkSize,
    );
  }
  for (final name in area.poiFiles) {
    final text = await store.readLegacyPoiFile(area.id, name);
    if (text != null) await store.putPoiFile(name, text);
  }
}

/// Das Archiv aus dem Pfad (Telefon) oder den Bytes (Browser); null, wenn
/// es fehlt — ein Index, der ein Archiv nennt, das nicht da ist, hat
/// nichts zu übernehmen.
Future<PmTilesArchive?> _open(Future<String?> path, Future<Uint8List?> bytes) async {
  final p = await path;
  if (p != null) return PmTilesArchive.from(p);
  final b = await bytes;
  return b == null ? null : PmTilesArchive.fromBytes(b);
}

Future<void> _copy(PmTilesArchive? archive, TileStore tiles, String region, TileLayer layer,
    List<TileXYZ> wanted, String build, int chunkSize) async {
  if (archive == null) return;
  try {
    final byId = <int, TileXYZ>{};
    final empty = <StoreTile>[];
    for (final t in wanted) {
      final id = tileIdOf(t);
      final entry = await archive.lookup(id);
      if (entry == null) continue;
      // Eine leere Kachel (0 Bytes) lässt der Mehrfach-Leser des Pakets
      // nicht zu (`Range`: begin < end) — sie ist leer, also ohne Lesen.
      if (entry.length == 0) {
        empty.add(StoreTile(t.z, t.x, t.y, Uint8List(0), build));
      } else {
        byId[id] = t;
      }
    }
    if (empty.isNotEmpty) await tiles.put(region, layer, empty);
    final ids = byId.keys.toList()..sort();
    StoreTile? probe;
    for (var start = 0; start < ids.length; start += chunkSize) {
      final chunk = ids.sublist(start, start + chunkSize > ids.length ? ids.length : start + chunkSize);
      final block = <StoreTile>[];
      await for (final tile in archive.tiles(chunk)) {
        final t = byId[tile.id]!;
        block.add(StoreTile(t.z, t.x, t.y, Uint8List.fromList(tile.compressedBytes()), build));
      }
      await tiles.put(region, layer, block);
      probe ??= block.isEmpty ? null : block.first;
    }
    if (probe != null) {
      final back = await tiles.read(region, layer, probe.z, probe.x, probe.y);
      if (back == null || back.length != probe.bytes.length) {
        throw StateError('Kachel ${probe.z}/${probe.x}/${probe.y} kam nicht im Speicher an');
      }
      for (var i = 0; i < back.length; i++) {
        if (back[i] != probe.bytes[i]) throw StateError('Kachel ${probe.z}/${probe.x}/${probe.y} kam anders an');
      }
    }
  } finally {
    await archive.close();
  }
}
