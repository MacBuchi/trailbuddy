// Ein Bereich entsteht (Konzept 3.2): erst der PLAN — welche Kacheln,
// und wie viele Bytes das im Archiv des Hosts sind (jede Kachel nennt
// ihre Länge im Verzeichnis, „12,4 MB" ist eine Messung, keine
// Schätzung) —, dann der DOWNLOAD über den `tiles()`-Strom des Pakets
// (nach Hilbert-Kurve geclustert zerfällt ein Rechteck in wenige
// zusammenhängende Byte-Bereiche), dazu die Orte-Dateien der berührten
// Rasterzellen, am Ende EIN Archiv über den Schreiber, zurückgelesen als
// Gegenprobe, dann der Index.
//
// Seit 0.69.0 dazu die Höhenkacheln (docs/konzept-routing.md 2.6, Weg
// B): für jede z13-Kachel der Form die Kachel aus dem Höhenarchiv des
// Hosts, derselbe Weg (Verzeichnis nennt die Bytes, `tiles()`-Strom), am
// Ende ein ZWEITES Archiv neben dem Bereich. Ohne Höhen-Manifest oder
// Höhenarchiv kommt der Bereich ohne Höhen — das ist kein Fehler, und
// „Aktualisieren" holt sie später nach.
//
// Seit 0.90.0 ebenso die Wege (#212): Güte und Schwierigkeit aus dem
// Wege-Archiv des Hosts, je z13-Kachel der Form, als DRITTES Archiv. Der
// Bereich holt sie immer, auch wenn die Ebene gerade aus ist
// (Betreiber, 2026-10-08) — wer sie im Wald einschaltet, soll sie haben.
//
// Läuft im Main-Isolate; auf Android hält der KeepAlive-Koordinator den
// Prozess wach (Vordergrunddienst `dataSync`), im Browser der Tab. Wer
// abbricht, bekommt nichts Halbes: Geschrieben wird erst am Ende.
import 'dart:convert';
import 'dart:typed_data';

import 'package:pmtiles/pmtiles.dart';

import '../map/map_regions.dart' show kDachRegionId;
import '../map/online_map.dart';
import '../map/way_layer.dart';
import '../map/poi.dart';
import 'area_plan.dart';
import 'area_store.dart';
import 'height_tiles.dart';
import 'pmtiles_writer.dart';

/// Der Plan: was geholt würde, und wie viel das ist.
class AreaPlan {
  const AreaPlan({
    required this.shape,
    required this.bounds,
    required this.maxZoom,
    required this.tiles,
    required this.bytes,
    this.poiFiles,
    this.heightTiles = const [],
    this.heightBytes = 0,
    this.wayTiles = const [],
    this.wayBytes = 0,
    this.waysBuild,
    this.region = kDachRegionId,
  });

  /// Die Region des Hosts, gegen die gemessen wurde (#220).
  final String region;

  /// Die Form, die geplant wurde — wird mit dem Bereich gemerkt, damit
  /// „Aktualisieren" dieselbe Form noch einmal holt.
  final AreaShape shape;

  /// Die Hülle der Form: der Rahmen im Archiv-Header.
  final AreaBounds bounds;
  final int maxZoom;

  /// Die Kacheln, die das Archiv des Hosts wirklich hat (Kacheln ohne
  /// Eintrag — Meer außerhalb DACH — fehlen hier schon).
  final List<TileXYZ> tiles;

  /// Bytes im Archiv, Kachel für Kachel summiert.
  final int bytes;

  /// Die Orte-Dateien des Bereichs, schon beim Messen geholt (seit
  /// 0.27.0: der Dialog vor dem Speichern nennt die Zahl der Orte) — der
  /// Download nimmt sie, statt sie ein zweites Mal zu holen. Null: ohne
  /// Orte gemessen (kein Manifest).
  final Map<String, String>? poiFiles;

  /// Wie viele Orte in [poiFiles] stehen; null ohne Orte.
  int? get poiCount => poiFiles?.values.fold<int>(0, (sum, text) => sum + _countPois(text));

  /// Bytes der Orte-Dateien, als UTF-8 gezählt.
  int get poiBytes =>
      poiFiles == null ? 0 : poiFiles!.values.fold<int>(0, (sum, t) => sum + utf8.encode(t).length);

  /// Die Höhenkacheln (z13), die das Höhenarchiv des Hosts für die Form
  /// hat, und ihre Bytes aus dessen Verzeichnis. Leer ohne Höhenarchiv.
  final List<TileXYZ> heightTiles;
  final int heightBytes;

  bool get hasHeights => heightTiles.isNotEmpty;

  /// Die Wege-Kacheln (z13), die das Wege-Archiv des Hosts für die Form
  /// hat — nur Kacheln mit getaggten Wegen, also oft weniger als die
  /// Form. [waysBuild] ist der Bau, gegen den gemessen wurde; null ohne
  /// Wege-Archiv.
  final List<TileXYZ> wayTiles;
  final int wayBytes;
  final String? waysBuild;

  bool get hasWays => wayTiles.isNotEmpty;

  /// Alles zusammen, was auf das Gerät kommt.
  int get totalBytes => bytes + poiBytes + heightBytes + wayBytes;

  static int _countPois(String text) {
    try {
      return parsePoiFile(text).length;
    } catch (_) {
      // Eine Datei, die sich nicht lesen lässt, liest auch die Karte
      // nicht — sie zählt als leer, statt das Messen zu kippen.
      return 0;
    }
  }
}

/// Mehr Kacheln als [kAreaMaxTiles]: kleiner wählen oder zwei Bereiche.
class AreaTooLarge implements Exception {
  const AreaTooLarge(this.tiles);
  final int tiles;
  @override
  String toString() => 'Bereich zu groß: $tiles Kacheln';
}

/// Vom Nutzer abgebrochen — kein Fehler, nichts geschrieben.
class AreaCancelled implements Exception {
  const AreaCancelled();
}

/// Der Fortschritt: [done] von [total] in der Phase (Kacheln, dann Orte).
class AreaProgress {
  const AreaProgress({required this.phase, required this.done, required this.total});
  final AreaPhase phase;
  final int done;
  final int total;

  double get fraction => total == 0 ? 1 : done / total;
}

enum AreaPhase { tiles, pois, heights, ways, writing }

class AreaDownloader {
  AreaDownloader({
    required this.archive,
    required this.manifest,
    required this.store,
    required this.fetchPoiFile,
    this.poiManifest,
    this.heights,
    this.heightsManifest,
    this.ways,
    this.waysManifest,
    this.chunkSize = 256,
    this.now,
    this.region = kDachRegionId,
  });

  /// Die Region, aus deren Archiven der Bereich kommt (#220).
  final String region;

  /// Das Archiv des Hosts, über Range-Anfragen geöffnet.
  final PmTilesArchive archive;
  final MapManifest manifest;
  final AreaStore store;

  /// Holt eine Orte-Datei des Hosts (`pois-<build>/<name>`), null bei 404.
  final Future<String?> Function(String name) fetchPoiFile;

  /// Das Orte-Manifest — null heißt: keine Orte zum Bereich (noch kein
  /// Bau veröffentlicht).
  final PoiManifest? poiManifest;

  /// Das Höhenarchiv des Hosts, über Range-Anfragen geöffnet — null
  /// heißt: der Bereich kommt ohne Höhen.
  final PmTilesArchive? heights;
  final HeightsManifest? heightsManifest;

  /// Das Wege-Archiv des Hosts — null heißt: der Bereich kommt ohne Wege.
  final PmTilesArchive? ways;
  final WaysManifest? waysManifest;

  /// So viele Kachel-Ids je `tiles()`-Aufruf: Das Paket liest je
  /// Aufruf alle zusammenhängenden Bereiche PARALLEL — ein ganzer
  /// Bereich auf einmal wäre ein Sturm aus Range-Anfragen.
  final int chunkSize;

  final DateTime Function()? now;

  Future<AreaPlan> plan(AreaShape shape, {bool withPois = false}) async {
    final maxZoom = manifest.maxZoom;
    final count = shape.countTiles(maxZoom: maxZoom);
    if (count > kAreaMaxTiles) throw AreaTooLarge(count);
    final wanted = shape.tiles(maxZoom: maxZoom);
    final present = <TileXYZ>[];
    var bytes = 0;
    for (final t in wanted) {
      final entry = await archive.lookup(tileIdOf(t));
      if (entry == null) continue;
      present.add(t);
      bytes += entry.length;
    }
    final heightTiles = <TileXYZ>[];
    var heightBytes = 0;
    final h = heights;
    if (h != null) {
      for (final t in shape.tiles(minZoom: kHeightTileZoom, maxZoom: kHeightTileZoom)) {
        final entry = await h.lookup(tileIdOf(t));
        if (entry == null) continue;
        heightTiles.add(t);
        heightBytes += entry.length;
      }
    }
    final wayTiles = <TileXYZ>[];
    var wayBytes = 0;
    final w = ways;
    if (w != null) {
      for (final t in shape.tiles(minZoom: kWaysZoom, maxZoom: kWaysZoom)) {
        final entry = await w.lookup(tileIdOf(t));
        if (entry == null) continue; // keine getaggten Wege in der Kachel
        wayTiles.add(t);
        wayBytes += entry.length;
      }
    }
    return AreaPlan(
      shape: shape,
      bounds: shape.hull,
      maxZoom: maxZoom,
      tiles: present,
      bytes: bytes,
      poiFiles: withPois ? await _fetchPois(shape) : null,
      heightTiles: heightTiles,
      heightBytes: heightBytes,
      wayTiles: wayTiles,
      wayBytes: wayBytes,
      waysBuild: w == null ? null : waysManifest?.build,
      region: region,
    );
  }

  /// Holt die Kacheln [wanted] aus [source] in Blöcken — die Bytes des
  /// Hosts unverändert (mit dessen Kompression), der Schreiber trägt
  /// dieselbe in den Header.
  Future<List<TileToWrite>> _fetchTiles(PmTilesArchive source, List<TileXYZ> wanted,
      {required void Function() check, required void Function(int done, int total) onProgress}) async {
    final byId = {for (final t in wanted) tileIdOf(t): t};
    final ids = byId.keys.toList()..sort();
    final fetched = <TileToWrite>[];
    onProgress(0, ids.length);
    for (var start = 0; start < ids.length; start += chunkSize) {
      check();
      final chunk = ids.sublist(start, start + chunkSize > ids.length ? ids.length : start + chunkSize);
      await for (final tile in source.tiles(chunk)) {
        final t = byId[tile.id]!;
        fetched.add(TileToWrite(t.z, t.x, t.y, Uint8List.fromList(tile.compressedBytes())));
      }
      onProgress(fetched.length, ids.length);
    }
    return fetched;
  }

  /// Die Orte der berührten Zellen, alle Gruppen — was das Manifest
  /// nennt. Alle Gruppen, damit der Filter offline umschaltbar bleibt;
  /// die Dateien sind klein. Die Zellen kommen aus der FORM, nicht aus
  /// der Hülle: Entlang der Trails sind das die Zellen der Kacheln, nicht
  /// alles dazwischen. Null ohne Manifest.
  Future<Map<String, String>?> _fetchPois(AreaShape shape,
      {void Function(int done, int total)? onProgress, void Function()? check}) async {
    final pm = poiManifest;
    if (pm == null) return null;
    final wanted = [
      for (final cell in shape.poiCells())
        for (final g in PoiGroup.values)
          if (pm.has(cell, g)) poiCellFileName(cell, g),
    ];
    final files = <String, String>{};
    onProgress?.call(0, wanted.length);
    for (final fileName in wanted) {
      check?.call();
      final text = await fetchPoiFile(fileName);
      if (text != null) files[fileName] = text;
      onProgress?.call(files.length, wanted.length);
    }
    return files;
  }

  /// Holt und speichert den Bereich; wirft [AreaCancelled], sobald
  /// [isCancelled] wahr sagt (geprüft zwischen den Blöcken).
  Future<StoredArea> download(
    AreaPlan plan, {
    required String name,
    String? id,
    void Function(AreaProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    void check() {
      if (isCancelled?.call() ?? false) throw const AreaCancelled();
    }

    final fetched = await _fetchTiles(archive, plan.tiles,
        check: check,
        onProgress: (done, total) =>
            onProgress?.call(AreaProgress(phase: AreaPhase.tiles, done: done, total: total)));

    // Die Orte: vom Messen mitgebracht oder jetzt geholt.
    final poiFiles = plan.poiFiles ??
        await _fetchPois(
              plan.shape,
              check: check,
              onProgress: (done, total) =>
                  onProgress?.call(AreaProgress(phase: AreaPhase.pois, done: done, total: total)),
            ) ??
        const <String, String>{};
    final pm = poiManifest;

    // Die Höhen: nur, wenn der Plan welche hat UND das Archiv noch da ist.
    final h = heights;
    final heightTiles = h == null || plan.heightTiles.isEmpty
        ? const <TileToWrite>[]
        : await _fetchTiles(h, plan.heightTiles,
            check: check,
            onProgress: (done, total) =>
                onProgress?.call(AreaProgress(phase: AreaPhase.heights, done: done, total: total)));

    // Die Wege ebenso. Ist das Archiv beim Download nicht mehr da, kommt
    // der Bereich ohne Wege und ohne Bau — „Aktualisieren" holt sie nach.
    final w = ways;
    final wayTiles = w == null || plan.wayTiles.isEmpty
        ? const <TileToWrite>[]
        : await _fetchTiles(w, plan.wayTiles,
            check: check,
            onProgress: (done, total) =>
                onProgress?.call(AreaProgress(phase: AreaPhase.ways, done: done, total: total)));
    final waysBuild = plan.wayTiles.isEmpty || wayTiles.isNotEmpty ? plan.waysBuild : null;

    check();
    onProgress?.call(const AreaProgress(phase: AreaPhase.writing, done: 0, total: 1));
    final areaId = id ?? _newId();
    final bytes = writePmTiles(
      tiles: fetched,
      tileCompression: archive.header.tileCompression,
      bounds: TileBounds(
          west: plan.bounds.west, south: plan.bounds.south, east: plan.bounds.east, north: plan.bounds.north),
      metadata: {
        'name': name,
        'source_build': manifest.sourceBuild,
        'attribution': '© OpenStreetMap contributors · Protomaps (ODbL)',
      },
    );
    await store.putArchive(areaId, bytes);
    await _verify(areaId, fetched);
    var heightBytes = 0;
    if (heightTiles.isNotEmpty) {
      final hb = writePmTiles(
        tiles: heightTiles,
        tileCompression: h!.header.tileCompression,
        bounds: TileBounds(
            west: plan.bounds.west, south: plan.bounds.south, east: plan.bounds.east, north: plan.bounds.north),
        metadata: heightsMetadata(name, heightsManifest?.build),
      );
      await store.putHeights(areaId, hb);
      await _verifyHeights(areaId, heightTiles);
      heightBytes = hb.length;
    } else {
      // Ein Bereich, der unter derselben Id neu geholt wird, trägt keine
      // Höhen aus dem alten Stand weiter — der Index sagt 0, das Archiv
      // ist weg.
      await store.deleteHeights(areaId);
    }
    var wayBytes = 0;
    if (wayTiles.isNotEmpty) {
      final wb = writePmTiles(
        tiles: wayTiles,
        tileCompression: w!.header.tileCompression,
        bounds: TileBounds(
            west: plan.bounds.west, south: plan.bounds.south, east: plan.bounds.east, north: plan.bounds.north),
        metadata: waysMetadata(name, waysBuild),
      );
      await store.putWays(areaId, wb);
      await _verifyWays(areaId, wayTiles);
      wayBytes = wb.length;
    } else {
      await store.deleteWays(areaId);
    }
    for (final e in poiFiles.entries) {
      await store.putPoiFile(areaId, e.key, e.value);
    }

    final area = StoredArea(
      id: areaId,
      name: name,
      shape: plan.shape,
      bounds: plan.bounds,
      minZoom: kAreaMinZoom,
      maxZoom: plan.maxZoom,
      build: manifest.sourceBuild,
      tiles: fetched.length,
      bytes: bytes.length,
      savedAt: (now ?? DateTime.now)().toUtc(),
      poiFiles: poiFiles.keys.toList()..sort(),
      poiBuild: poiFiles.isEmpty ? null : pm?.build,
      heightTiles: heightTiles.length,
      heightBytes: heightBytes,
      heightsBuild: heightTiles.isEmpty ? null : heightsManifest?.build,
      wayTiles: wayTiles.length,
      wayBytes: wayBytes,
      waysBuild: waysBuild,
      region: plan.region,
    );
    final others = [for (final a in await store.list()) if (a.id != areaId) a];
    await store.saveIndex([...others, area]);
    return area;
  }

  /// Die Gegenprobe: Das gespeicherte Archiv öffnet sich mit dem Leser,
  /// den beide Engines benutzen, zählt alle Kacheln und liefert eine
  /// Stichprobe Byte für Byte. Ein Archiv, das hier scheitert, wird nie
  /// in den Index eingetragen.
  Future<void> _verify(String areaId, List<TileToWrite> fetched) async {
    final path = await store.archivePath(areaId);
    final PmTilesArchive stored;
    if (path != null) {
      stored = await PmTilesArchive.from(path);
    } else {
      final bytes = await store.readArchive(areaId);
      if (bytes == null) throw StateError('Archiv nach dem Schreiben nicht lesbar');
      stored = await PmTilesArchive.fromBytes(bytes);
    }
    await _verifyStored(stored, fetched);
  }

  /// Dieselbe Gegenprobe für das Höhenarchiv, dazu: Die Stichprobe
  /// ENTPACKT sich zu einer Höhenkachel — ein Archiv aus Bytes, die der
  /// Leser nicht versteht, wäre sonst ein gespeicherter Fehler.
  Future<void> _verifyHeights(String areaId, List<TileToWrite> fetched) async {
    final path = await store.heightsPath(areaId);
    final PmTilesArchive stored;
    if (path != null) {
      stored = await PmTilesArchive.from(path);
    } else {
      final bytes = await store.readHeights(areaId);
      if (bytes == null) throw StateError('Höhenarchiv nach dem Schreiben nicht lesbar');
      stored = await PmTilesArchive.fromBytes(bytes);
    }
    await _verifyStored(stored, fetched);
    final source = ArchiveHeightSource(stored);
    try {
      final probe = fetched[fetched.length ~/ 2];
      if (await source.tile(probe.x, probe.y) == null) {
        throw StateError('Höhenkachel ${probe.x}/${probe.y} lässt sich nicht lesen');
      }
    } finally {
      await source.close();
    }
  }

  /// Dieselbe Gegenprobe für das Wege-Archiv.
  Future<void> _verifyWays(String areaId, List<TileToWrite> fetched) async {
    final path = await store.waysPath(areaId);
    final PmTilesArchive stored;
    if (path != null) {
      stored = await PmTilesArchive.from(path);
    } else {
      final bytes = await store.readWays(areaId);
      if (bytes == null) throw StateError('Wege-Archiv nach dem Schreiben nicht lesbar');
      stored = await PmTilesArchive.fromBytes(bytes);
    }
    await _verifyStored(stored, fetched);
  }

  Future<void> _verifyStored(PmTilesArchive stored, List<TileToWrite> fetched) async {
    try {
      if (stored.header.numberOfAddressedTiles != fetched.length) {
        throw StateError('Archiv zählt ${stored.header.numberOfAddressedTiles} statt ${fetched.length} Kacheln');
      }
      for (final probe in [fetched.first, fetched[fetched.length ~/ 2], fetched.last]) {
        final tile = await stored.tile(ZXY(probe.z, probe.x, probe.y).toTileId());
        final got = tile.compressedBytes();
        if (got.length != probe.bytes.length) {
          throw StateError('Kachel ${probe.z}/${probe.x}/${probe.y} kommt anders zurück');
        }
        for (var i = 0; i < got.length; i++) {
          if (got[i] != probe.bytes[i]) {
            throw StateError('Kachel ${probe.z}/${probe.x}/${probe.y} kommt anders zurück');
          }
        }
      }
    } finally {
      await stored.close();
    }
  }

  String _newId() {
    final at = (now ?? DateTime.now)().toUtc();
    return 'area-${at.millisecondsSinceEpoch.toRadixString(36)}';
  }
}
