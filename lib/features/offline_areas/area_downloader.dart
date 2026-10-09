// Ein Bereich entsteht (Konzept 3.2, seit 0.106.0 Abschnitt 8): erst der
// PLAN — welche Kacheln die Form deckt, welche davon das Archiv des Hosts
// hat (jede Kachel nennt ihre Länge im Verzeichnis, „12,4 MB" ist eine
// Messung, keine Schätzung) und welche davon NOCH NICHT im Kachelspeicher
// liegen —, dann der DOWNLOAD genau dieser über den `tiles()`-Strom des
// Pakets (nach Hilbert-Kurve geclustert zerfällt eine Form in wenige
// zusammenhängende Byte-Bereiche), Block für Block in den Speicher.
//
// Seit #229 ist ein Bereich ein Verweis (Name, Region, Form) auf den
// Kachelspeicher je Region und Ebene: Zwei Bereiche über derselben Gegend
// teilen ihre Kacheln, und wer speichert, lädt nur, was fehlt. Der
// Verweis entsteht VOR dem Download als „unvollständig"; ein Abbruch, ein
// Funkloch lassen die geschriebenen Blöcke liegen, und „Fortsetzen" holt
// nur den Rest (Konzept 8.2). Erst wenn alles da ist, ist er vollständig.
//
// Dazu, wie bisher: die Höhenkacheln (seit 0.69.0) und die Wege (seit
// 0.90.0) je z13-Kachel der Form, über denselben Weg in ihre Ebene; die
// Orte-Dateien der berührten Rasterzellen (je Name einmal); seit 0.105.0
// die Übersicht der Region als ganze Datei, wenn sie fehlt. Ohne Höhen-
// oder Wege-Archiv kommt der Bereich ohne sie — kein Fehler, und
// „Aktualisieren" holt sie später nach.
//
// Läuft im Main-Isolate; auf Android hält der KeepAlive-Koordinator den
// Prozess wach (Vordergrunddienst `dataSync`), im Browser der Tab.
import 'dart:convert';
import 'dart:typed_data';

import '../../core/errors.dart';

import 'package:pmtiles/pmtiles.dart';

import '../map/map_regions.dart' show kDachRegionId;
import '../map/online_map.dart';
import '../map/way_layer.dart';
import '../map/poi.dart';
import 'area_plan.dart';
import 'area_store.dart';
import 'height_tiles.dart';
import 'region_overview.dart';
import 'tile_refs.dart';
import 'tile_store.dart';

/// Die Kacheln einer Ebene im Plan: was zu holen ist, was die Form deckt.
class LayerPlan {
  const LayerPlan({this.fetch = const [], this.fetchBytes = 0, this.covered = 0, this.coveredBytes = 0});

  static const none = LayerPlan();

  /// Was geholt wird — fehlt im Speicher (oder ist älter, beim
  /// Aktualisieren).
  final List<TileXYZ> fetch;
  final int fetchBytes;

  /// Was das Archiv des Hosts für die Form hat, ob es liegt oder nicht.
  final int covered;
  final int coveredBytes;

  /// Wie viele davon schon liegen.
  int get stored => covered - fetch.length;
}

/// Der Plan: was geholt würde, und wie viel das ist.
class AreaPlan {
  const AreaPlan({
    required this.shape,
    required this.bounds,
    required this.maxZoom,
    required this.map,
    this.poiFiles,
    this.poiNames = const [],
    this.heights = LayerPlan.none,
    this.ways = LayerPlan.none,
    this.waysBuild,
    this.region = kDachRegionId,
    this.overview,
  });

  /// Die Region des Hosts, gegen die gemessen wurde (#220).
  final String region;

  /// Die Übersicht der Region, die mitkommt (#220 Schritt 4) — null, wenn
  /// sie schon liegt, die Region keine hat (DACH: im Binary) oder der Host
  /// keine nennt.
  final OverviewManifest? overview;

  int get overviewBytes => overview?.bytes ?? 0;

  /// Die Form, die geplant wurde — wird mit dem Bereich gemerkt, damit
  /// „Aktualisieren" dieselbe Form noch einmal holt.
  final AreaShape shape;

  /// Die Hülle der Form.
  final AreaBounds bounds;
  final int maxZoom;

  /// Die Kartenkacheln (Zoom 8 bis zum Zoom des Hosts).
  final LayerPlan map;

  /// Die Kartenkacheln, die geholt werden.
  List<TileXYZ> get tiles => map.fetch;

  /// Ihre Bytes, Kachel für Kachel aus dem Verzeichnis summiert.
  int get bytes => map.fetchBytes;

  /// Die Orte-Dateien, die geholt werden — schon beim Messen geholt (seit
  /// 0.27.0: der Dialog vor dem Speichern nennt die Zahl der Orte); der
  /// Download nimmt sie, statt sie ein zweites Mal zu holen. Null: ohne
  /// Orte gemessen (kein Manifest).
  final Map<String, String>? poiFiles;

  /// ALLE Orte-Dateien der Form, auch die schon liegenden — der Bereich
  /// nennt sie, damit sie mit dem letzten, der sie nennt, gehen.
  final List<String> poiNames;

  /// Wie viele Orte in [poiFiles] stehen; null ohne Orte.
  int? get poiCount => poiFiles?.values.fold<int>(0, (sum, text) => sum + _countPois(text));

  /// Bytes der Orte-Dateien, als UTF-8 gezählt.
  int get poiBytes =>
      poiFiles == null ? 0 : poiFiles!.values.fold<int>(0, (sum, t) => sum + utf8.encode(t).length);

  /// Die Höhenkacheln (z13). Leer ohne Höhenarchiv.
  final LayerPlan heights;

  List<TileXYZ> get heightTiles => heights.fetch;
  int get heightBytes => heights.fetchBytes;

  /// Die Form hat Höhen — geholt oder schon liegend.
  bool get hasHeights => heights.covered > 0;

  /// Die Wege-Kacheln (z13) — nur Kacheln mit getaggten Wegen, also oft
  /// weniger als die Form. [waysBuild] ist der Bau, gegen den gemessen
  /// wurde; null ohne Wege-Archiv.
  final LayerPlan ways;
  final String? waysBuild;

  List<TileXYZ> get wayTiles => ways.fetch;
  int get wayBytes => ways.fetchBytes;

  bool get hasWays => ways.covered > 0;

  /// Hat der Host hier überhaupt eine Karte?
  bool get hasMap => map.covered > 0;

  /// Liegt schon alles, was die Form braucht?
  bool get nothingToFetch =>
      map.fetch.isEmpty && heights.fetch.isEmpty && ways.fetch.isEmpty && (poiFiles?.isEmpty ?? true) && overview == null;

  /// Alles zusammen, was auf das Gerät kommt.
  int get totalBytes => bytes + poiBytes + heightBytes + wayBytes + overviewBytes;

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

/// Vom Nutzer abgebrochen — kein Fehler; was schon geschrieben ist, bleibt
/// (der Bereich steht als unvollständig in „Meine Bereiche").
class AreaCancelled implements Exception {
  const AreaCancelled();
}

/// Eine geschriebene Kachel kam aus dem Speicher anders zurück.
class AreaVerifyFailed implements Exception {
  const AreaVerifyFailed(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Der Fortschritt: [done] von [total] in der Phase (Kacheln, dann Orte).
class AreaProgress {
  const AreaProgress({required this.phase, required this.done, required this.total});
  final AreaPhase phase;
  final int done;
  final int total;

  double get fraction => total == 0 ? 1 : done / total;
}

/// „Aktualisieren" einer Region (Konzept 8.2, Schritt 4): die liegenden
/// Kacheln, die eine Form der Region deckt und die aus einem älteren Bau
/// stammen als der des Hosts — über alle Bereiche zusammen, jede Kachel
/// einmal. Was fehlt, ist nicht veraltet; das holt „Fortsetzen" eines
/// Bereichs.
class RegionRefreshPlan {
  const RegionRefreshPlan({
    required this.region,
    this.map = LayerPlan.none,
    this.heights = LayerPlan.none,
    this.ways = LayerPlan.none,
    this.drop = const {},
    this.poiNames = const [],
  });

  final String region;

  /// Je Ebene: [LayerPlan.fetch] wird neu geholt (Bytes aus dem
  /// Verzeichnis des neuen Baus), [LayerPlan.covered] sind die veralteten
  /// Kacheln, wie sie liegen.
  final LayerPlan map;
  final LayerPlan heights;
  final LayerPlan ways;

  /// Veraltete Kacheln, die der neue Bau nicht mehr hat (Wege ohne Tags,
  /// eine Kachel am Rand) — sie gehen, sonst blieben sie für immer alt.
  final Map<TileLayer, List<int>> drop;

  /// Die Orte-Dateien von Bereichen mit älterem Orte-Bau.
  final List<String> poiNames;

  /// Wie viele Kacheln veraltet sind, über alle Ebenen.
  int get staleTiles => map.covered + heights.covered + ways.covered;

  /// Was neu geholt wird, über alle Ebenen (ohne die kleinen Orte-Dateien).
  int get fetchBytes => map.fetchBytes + heights.fetchBytes + ways.fetchBytes;

  bool get isEmpty => staleTiles == 0 && poiNames.isEmpty;
}

enum AreaPhase { tiles, pois, heights, ways, overview, writing }

class AreaDownloader {
  AreaDownloader({
    required this.archive,
    required this.manifest,
    required this.store,
    required this.tiles,
    required this.fetchPoiFile,
    this.poiManifest,
    this.heights,
    this.heightsManifest,
    this.ways,
    this.waysManifest,
    this.chunkSize = 256,
    this.now,
    this.region = kDachRegionId,
    this.overview,
    this.fetchOverview,
  });

  /// Die Region, aus deren Archiven der Bereich kommt (#220).
  final String region;

  /// Die Übersicht der Region, wenn sie mitkommen soll (#220 Schritt 4),
  /// und wie sie geholt wird.
  final OverviewManifest? overview;
  final OverviewFetcher? fetchOverview;

  /// Das Archiv des Hosts, über Range-Anfragen geöffnet.
  final PmTilesArchive archive;
  final MapManifest manifest;

  /// Der Index der Bereiche und die Orte-Dateien.
  final AreaStore store;

  /// Der Kachelspeicher (#229).
  final TileStore tiles;

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

  /// So viele Kachel-Ids je `tiles()`-Aufruf — und je Block, der in den
  /// Speicher geht: Das Paket liest je Aufruf alle zusammenhängenden
  /// Bereiche PARALLEL, ein ganzer Bereich auf einmal wäre ein Sturm aus
  /// Range-Anfragen.
  final int chunkSize;

  final DateTime Function()? now;

  /// Was eine Ebene für [wanted] holen würde: die Kacheln, die der Host
  /// hat, abzüglich der liegenden. Mit [refreshBefore] zählt eine liegende
  /// Kachel aus einem älteren Bau als fehlend (Aktualisieren).
  Future<LayerPlan> _planLayer(PmTilesArchive source, TileLayer layer, Iterable<TileXYZ> wanted,
      {String? refreshBefore}) async {
    final index = await tiles.index(region, layer);
    final fetch = <TileXYZ>[];
    var fetchBytes = 0, covered = 0, coveredBytes = 0;
    for (final t in wanted) {
      final id = tileIdOf(t);
      final entry = await source.lookup(id);
      if (entry == null) continue; // Meer, außerhalb, ohne getaggte Wege
      covered++;
      coveredBytes += entry.length;
      final have = index[id];
      if (have != null && (refreshBefore == null || have.build.compareTo(refreshBefore) >= 0)) continue;
      fetch.add(t);
      fetchBytes += entry.length;
    }
    return LayerPlan(fetch: fetch, fetchBytes: fetchBytes, covered: covered, coveredBytes: coveredBytes);
  }

  /// Der Plan für [shape]. Mit [refresh] holt er auch liegende Kacheln
  /// älterer Bauten neu und die Orte-Dateien der Form noch einmal —
  /// „Aktualisieren".
  Future<AreaPlan> plan(AreaShape shape, {bool withPois = false, bool refresh = false}) async {
    final maxZoom = manifest.maxZoom;
    final count = shape.countTiles(maxZoom: maxZoom);
    if (count > kAreaMaxTiles) throw AreaTooLarge(count);
    final map = await _planLayer(archive, TileLayer.map, shape.tiles(maxZoom: maxZoom),
        refreshBefore: refresh ? manifest.sourceBuild : null);
    final h = heights;
    final heightPlan = h == null
        ? LayerPlan.none
        : await _planLayer(h, TileLayer.heights, shape.tiles(minZoom: kHeightTileZoom, maxZoom: kHeightTileZoom),
            refreshBefore: refresh ? heightsManifest?.build : null);
    final w = ways;
    final wayPlan = w == null
        ? LayerPlan.none
        : await _planLayer(w, TileLayer.ways, shape.tiles(minZoom: kWaysZoom, maxZoom: kWaysZoom),
            refreshBefore: refresh ? waysManifest?.build : null);
    final names = _poiNames(shape);
    return AreaPlan(
      shape: shape,
      bounds: shape.hull,
      maxZoom: maxZoom,
      map: map,
      poiFiles: withPois ? await _fetchPois(names, refresh: refresh) : null,
      poiNames: names,
      heights: heightPlan,
      ways: wayPlan,
      waysBuild: w == null ? null : waysManifest?.build,
      region: region,
      overview: fetchOverview == null ? null : overview,
    );
  }

  /// Die Orte-Dateien der Form, alle Gruppen, die das Manifest nennt —
  /// alle Gruppen, damit der Filter offline umschaltbar bleibt; die Dateien
  /// sind klein. Die Zellen kommen aus der FORM, nicht aus der Hülle.
  List<String> _poiNames(AreaShape shape) {
    final pm = poiManifest;
    if (pm == null) return const [];
    return [
      for (final cell in shape.poiCells())
        for (final g in PoiGroup.values)
          if (pm.has(cell, g)) poiCellFileName(cell, g),
    ];
  }

  /// Holt die Orte-Dateien [names], die noch nicht liegen (mit [refresh]
  /// alle). Null ohne Manifest.
  Future<Map<String, String>?> _fetchPois(List<String> names,
      {bool refresh = false, void Function(int done, int total)? onProgress, void Function()? check}) async {
    if (poiManifest == null) return null;
    final wanted = [
      for (final n in names)
        if (refresh || await store.readPoiFile(n) == null) n,
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

  /// Holt [wanted] aus [source] in Blöcken und legt jeden Block sofort
  /// in [layer] ab — die Bytes des Hosts unverändert, mit dessen
  /// Kompression. Nach jedem Block eine Gegenprobe: die mittlere Kachel
  /// kommt aus dem Speicher Byte für Byte zurück.
  Future<int> _fetchInto(PmTilesArchive source, TileLayer layer, List<TileXYZ> wanted, String build,
      {required void Function() check, required void Function(int done, int total) onProgress}) async {
    final byId = {for (final t in wanted) tileIdOf(t): t};
    final ids = byId.keys.toList()..sort();
    var done = 0;
    onProgress(0, ids.length);
    for (var start = 0; start < ids.length; start += chunkSize) {
      check();
      final chunk = ids.sublist(start, start + chunkSize > ids.length ? ids.length : start + chunkSize);
      final block = <StoreTile>[];
      // Eine leere Kachel (0 Bytes) lässt der Mehrfach-Leser des Pakets
      // nicht zu (`Range`: begin < end) — sie ist leer, also ohne Lesen.
      final read = <int>[];
      for (final id in chunk) {
        if ((await source.lookup(id))?.length == 0) {
          final t = byId[id]!;
          block.add(StoreTile(t.z, t.x, t.y, Uint8List(0), build));
        } else {
          read.add(id);
        }
      }
      if (read.isNotEmpty) {
        await for (final tile in source.tiles(read)) {
          final t = byId[tile.id]!;
          block.add(StoreTile(t.z, t.x, t.y, Uint8List.fromList(tile.compressedBytes()), build));
        }
      }
      if (block.isEmpty) continue;
      await tiles.put(region, layer, block);
      final probe = block[block.length ~/ 2];
      final back = await tiles.read(region, layer, probe.z, probe.x, probe.y);
      if (back == null || !_same(back, probe.bytes)) {
        throw AreaVerifyFailed('Kachel ${probe.z}/${probe.x}/${probe.y} kommt aus dem Speicher anders zurück');
      }
      done += block.length;
      onProgress(done, ids.length);
    }
    return done;
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Holt und speichert den Bereich; wirft [AreaCancelled], sobald
  /// [isCancelled] wahr sagt (geprüft zwischen den Blöcken). Mit [id]
  /// wird ein liegender Bereich fortgesetzt oder aktualisiert.
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

    final at = (now ?? DateTime.now)().toUtc();
    final areaId = id ?? _newId(at);
    final existing = (await store.list()).where((a) => a.id == areaId).firstOrNull;
    final pm = poiManifest;
    // Der Verweis zuerst (Konzept 8.2): Was ab jetzt geschrieben wird,
    // gehört ihm. Ein liegender Bereich behält seinen Zustand — ein
    // abgebrochenes Aktualisieren lässt ihn vollständig, nur mit älteren
    // Kacheln dazwischen.
    final area = (existing ??
            StoredArea(
              id: areaId,
              name: name,
              bounds: plan.bounds,
              minZoom: kAreaMinZoom,
              maxZoom: plan.maxZoom,
              build: manifest.sourceBuild,
              tiles: 0,
              bytes: 0,
              savedAt: at,
              region: plan.region,
              format: kStoredAreaFormat,
              complete: false,
            ))
        .copyWith(
      name: name,
      shape: plan.shape,
      poiFiles: {...?existing?.poiFiles, ...plan.poiNames}.toList()..sort(),
      format: kStoredAreaFormat,
    );
    await _saveEntry(area);

    await _fetchInto(archive, TileLayer.map, plan.tiles, manifest.sourceBuild,
        check: check,
        onProgress: (done, total) =>
            onProgress?.call(AreaProgress(phase: AreaPhase.tiles, done: done, total: total)));

    // Die Orte: vom Messen mitgebracht oder jetzt geholt.
    final poiFiles = plan.poiFiles ??
        await _fetchPois(
              plan.poiNames,
              check: check,
              onProgress: (done, total) =>
                  onProgress?.call(AreaProgress(phase: AreaPhase.pois, done: done, total: total)),
            ) ??
        const <String, String>{};
    for (final e in poiFiles.entries) {
      await store.putPoiFile(e.key, e.value);
    }

    // Die Höhen: nur, wenn der Plan welche hat UND das Archiv noch da ist.
    final h = heights;
    final heightsFetched = plan.heightTiles.isEmpty || h != null;
    if (h != null && plan.heightTiles.isNotEmpty) {
      await _fetchInto(h, TileLayer.heights, plan.heightTiles, heightsManifest?.build ?? manifest.sourceBuild,
          check: check,
          onProgress: (done, total) =>
              onProgress?.call(AreaProgress(phase: AreaPhase.heights, done: done, total: total)));
    }

    // Die Wege ebenso. Ist das Archiv beim Download nicht mehr da, kommt
    // der Bereich ohne Wege und ohne Bau — „Aktualisieren" holt sie nach.
    final w = ways;
    final wayBuild = plan.waysBuild ?? waysManifest?.build;
    var waysFetched = plan.wayTiles.isEmpty;
    if (w != null && plan.wayTiles.isNotEmpty && wayBuild != null) {
      await _fetchInto(w, TileLayer.ways, plan.wayTiles, wayBuild,
          check: check,
          onProgress: (done, total) =>
              onProgress?.call(AreaProgress(phase: AreaPhase.ways, done: done, total: total)));
      waysFetched = true;
    }

    // Die Übersicht der Region (#220 Schritt 4), als ganze Datei. Eine
    // Datei, die nicht zu ihrem Manifest passt, kostet nur die Übersicht —
    // der nächste Bereich der Region versucht es wieder.
    final ov = plan.overview;
    final fetch = fetchOverview;
    if (ov != null && fetch != null) {
      final got = await fetch(ov.archiveUri,
          check: check,
          onProgress: (done, total) => onProgress?.call(
              AreaProgress(phase: AreaPhase.overview, done: done, total: total > 0 ? total : ov.bytes)));
      if (got != null) {
        try {
          await checkOverview(ov, got);
          await store.putOverview(
              StoredOverview(
                region: plan.region,
                build: ov.sourceBuild,
                bytes: got.length,
                maxZoom: ov.maxZoom,
                savedAt: (now ?? DateTime.now)().toUtc(),
              ),
              got);
        } on OverviewMismatch catch (e, s) {
          logError('Übersicht der Region ${plan.region} prüfen', e, s);
        }
      }
    }

    check();
    final done = area.copyWith(
      build: manifest.sourceBuild,
      tiles: plan.map.covered,
      bytes: plan.map.coveredBytes,
      savedAt: (now ?? DateTime.now)().toUtc(),
      poiBuild: plan.poiNames.isEmpty ? area.poiBuild : pm?.build,
      heightTiles: heightsFetched ? plan.heights.covered : area.heightTiles,
      heightBytes: heightsFetched ? plan.heights.coveredBytes : area.heightBytes,
      heightsBuild: heightsFetched && plan.hasHeights ? heightsManifest?.build : area.heightsBuild,
      wayTiles: waysFetched ? plan.ways.covered : area.wayTiles,
      wayBytes: waysFetched ? plan.ways.coveredBytes : area.wayBytes,
      // Geholt ist geholt: Ein Bau bleibt, auch wenn das Manifest gerade fehlt.
      waysBuild: waysFetched ? (plan.waysBuild ?? area.waysBuild) : area.waysBuild,
      complete: true,
    );
    await _saveEntry(done);
    return done;
  }

  /// Der Plan für „Aktualisieren" der Region aus [areas] (die anderer
  /// Regionen fallen weg): je Ebene die veralteten Kacheln der Formen
  /// (`staleTiles`), gemessen mit den Längen im Verzeichnis des neuen
  /// Baus. Eine Ebene ohne Archiv oder Manifest bleibt, wie sie ist.
  Future<RegionRefreshPlan> planRefresh(List<StoredArea> areas) async {
    final here = [for (final a in areas) if (a.region == region) a];
    final drop = <TileLayer, List<int>>{};
    Future<LayerPlan> layer(PmTilesArchive? source, TileLayer l, String? build) async {
      if (source == null || build == null) return LayerPlan.none;
      final stale = staleTiles(await tiles.index(region, l), referencedTileIds(here, l), build);
      final fetch = <TileXYZ>[];
      final gone = <int>[];
      var bytes = 0;
      for (final id in stale.ids) {
        final entry = await source.lookup(id);
        if (entry == null) {
          gone.add(id);
          continue;
        }
        final t = ZXY.fromTileId(id);
        fetch.add((z: t.z, x: t.x, y: t.y));
        bytes += entry.length;
      }
      if (gone.isNotEmpty) drop[l] = gone;
      return LayerPlan(fetch: fetch, fetchBytes: bytes, covered: stale.ids.length, coveredBytes: stale.bytes);
    }

    final map = await layer(archive, TileLayer.map, manifest.sourceBuild);
    final heightPlan = await layer(heights, TileLayer.heights, heightsManifest?.build);
    final wayPlan = await layer(ways, TileLayer.ways, waysManifest?.build);
    final pm = poiManifest;
    final poiNames = pm == null
        ? const <String>[]
        : ({
            for (final a in here)
              if (a.poiBuild == null || a.poiBuild!.compareTo(pm.build) < 0) ...a.poiFiles,
          }.toList()
          ..sort());
    return RegionRefreshPlan(
        region: region, map: map, heights: heightPlan, ways: wayPlan, drop: drop, poiNames: poiNames);
  }

  /// Holt, was [plan] nennt, in den Speicher der Region — keine Liste von
  /// Bereichen, kein neuer Verweis. Erst wenn alles da ist, tragen die
  /// Bereiche der Region den neuen Bau; ein Abbruch lässt das schon
  /// Geholte liegen, und die Zählung zeigt danach nur noch den Rest.
  Future<List<StoredArea>> refreshRegion(
    RegionRefreshPlan plan, {
    void Function(AreaProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    void check() {
      if (isCancelled?.call() ?? false) throw const AreaCancelled();
    }

    void progress(AreaPhase phase, int done, int total) =>
        onProgress?.call(AreaProgress(phase: phase, done: done, total: total));

    await _fetchInto(archive, TileLayer.map, plan.map.fetch, manifest.sourceBuild,
        check: check, onProgress: (d, t) => progress(AreaPhase.tiles, d, t));
    final h = heights;
    final hb = heightsManifest?.build;
    if (h != null && hb != null && plan.heights.fetch.isNotEmpty) {
      await _fetchInto(h, TileLayer.heights, plan.heights.fetch, hb,
          check: check, onProgress: (d, t) => progress(AreaPhase.heights, d, t));
    }
    final w = ways;
    final wb = waysManifest?.build;
    if (w != null && wb != null && plan.ways.fetch.isNotEmpty) {
      await _fetchInto(w, TileLayer.ways, plan.ways.fetch, wb,
          check: check, onProgress: (d, t) => progress(AreaPhase.ways, d, t));
    }
    for (final e in plan.drop.entries) {
      await tiles.remove(region, e.key, e.value);
    }
    final poiFiles = plan.poiNames.isEmpty
        ? const <String, String>{}
        : await _fetchPois(plan.poiNames,
                refresh: true, check: check, onProgress: (d, t) => progress(AreaPhase.pois, d, t)) ??
            const <String, String>{};
    for (final e in poiFiles.entries) {
      await store.putPoiFile(e.key, e.value);
    }

    check();
    // Alles da: Die Bereiche der Region tragen jetzt den neuen Bau.
    final pm = poiManifest;
    final refreshedPois = {...plan.poiNames};
    final all = await store.list();
    final updated = [
      for (final a in all)
        if (a.region != region)
          a
        else
          a.copyWith(
            build: a.build.compareTo(manifest.sourceBuild) < 0 ? manifest.sourceBuild : null,
            heightsBuild: hb != null && a.heightsBuild != null && a.heightsBuild!.compareTo(hb) < 0 ? hb : null,
            waysBuild: wb != null && a.waysBuild != null && a.waysBuild!.compareTo(wb) < 0 ? wb : null,
            poiBuild: pm != null && a.poiFiles.isNotEmpty && a.poiFiles.every(refreshedPois.contains) &&
                    (a.poiBuild == null || a.poiBuild!.compareTo(pm.build) < 0)
                ? pm.build
                : null,
          ),
    ];
    await store.saveIndex(updated);
    return [for (final a in updated) if (a.region == region) a];
  }

  Future<void> _saveEntry(StoredArea area) async {
    final all = await store.list();
    final i = all.indexWhere((a) => a.id == area.id);
    await store.saveIndex(i < 0 ? [...all, area] : [...all.sublist(0, i), area, ...all.sublist(i + 1)]);
  }

  String _newId(DateTime at) => 'area-${at.millisecondsSinceEpoch.toRadixString(36)}';
}
