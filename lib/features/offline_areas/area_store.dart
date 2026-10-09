// Die Ablage gespeicherter Bereiche (Konzept 3.2, seit 0.106.0 Abschnitt
// 8): der Index der Bereiche, die Orte-Dateien und die Übersichten der
// Regionen. Die Kacheln selbst liegen seit 0.106.0 (#229) NICHT mehr hier,
// sondern im Kachelspeicher (`tile_store.dart`) — je Region und Ebene
// jede Kachel einmal. Ein Bereich ist nur noch ein Verweis: Name, Region,
// Form. Auf dem Telefon Dateien unter `offline_maps/areas/` (vom Backup
// ausgenommen — jederzeit neu ladbar), im Browser IndexedDB
// (`area_store_idb.dart`), im Test der Speicher.
//
// Bereiche sind Absicht: Sie werden nie verdrängt, nur auf Wunsch
// gelöscht (Liste „Meine Bereiche").
//
// **Die Orte-Dateien liegen je Name EINMAL** (seit 0.106.0); ein Bereich
// nennt die Namen, die er braucht (`StoredArea.poiFiles`), und eine Datei
// geht erst, wenn kein Bereich sie mehr nennt (`tile_refs.dart`).
//
// **Der Altbestand** (bis 0.105.x: je Bereich ein Archiv für Karte, Höhen
// und Wege, Orte-Dateien je Bereich) bleibt lesbar, bis die Übernahme
// (`area_migration.dart`) ihn in den Kachelspeicher gelegt hat.
//
// Seit 0.105.0 liegt daneben die Übersicht einer Region (#220 Schritt 4,
// `docs/konzept-regionen.md` §5): Zoom 0–7 als EINE Datei je Region, die
// mit dem ersten Bereich dort kommt — DACH hat seine im Binary. Sie hat
// einen eigenen kleinen Index, weil sie keinem Bereich gehört, sondern
// allen einer Region; sie geht mit dem letzten von ihnen.
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../map/map_regions.dart' show kDachRegionId;
import 'area_plan.dart';
import 'area_store_web.dart' if (dart.library.io) 'area_store_io.dart';

/// Ein gespeicherter Bereich, wie der Index ihn führt.
class StoredArea {
  StoredArea({
    required this.id,
    required this.name,
    required this.bounds,
    AreaShape? shape,
    required this.minZoom,
    required this.maxZoom,
    required this.build,
    required this.tiles,
    required this.bytes,
    required this.savedAt,
    this.poiFiles = const [],
    this.poiBuild,
    this.heightTiles = 0,
    this.heightBytes = 0,
    this.heightsBuild,
    this.wayTiles = 0,
    this.wayBytes = 0,
    this.waysBuild,
    this.region = kDachRegionId,
    this.format = 1,
    this.complete = true,
  }) : shape = shape ?? RectShape(bounds);

  /// 2 ([kStoredAreaFormat]): ein Verweis auf den Kachelspeicher (seit
  /// 0.106.0). 1: ein Bereich mit eigenen Archiven, der noch übernommen
  /// wird — die Vorgabe, weil ein Index-Eintrag von vor 0.106.0 das Feld
  /// nicht kennt; wer einen Verweis anlegt, nennt das Format.
  final int format;

  bool get legacy => format < kStoredAreaFormat;

  /// Falsch, solange der Download des Bereichs nicht durch ist (Konzept
  /// 8.2): Der Verweis entsteht VOR dem Download, ein Abbruch lässt die
  /// geschriebenen Kacheln liegen, und „Fortsetzen" holt den Rest.
  final bool complete;

  final String id;
  final String name;

  /// Die Hülle der Form (Archiv-Header, „auf der Karte zeigen", der
  /// Vorfilter des Wege-Index). Innerhalb der Hülle kann eine Kachel
  /// FEHLEN (Form entlang der Trails) — wer eine braucht, fragt das
  /// Archiv, nicht den Rahmen.
  final AreaBounds bounds;

  /// Die Form, mit der der Bereich geplant wurde — „Aktualisieren" holt
  /// sie noch einmal. Einträge vor 0.24.0 tragen keine: Dort IST der
  /// Rahmen die Form.
  final AreaShape shape;
  final int minZoom;
  final int maxZoom;

  /// Der Kartenstand: `source_build` des Host-Manifests (`JJJJMMTT`).
  final String build;
  final int tiles;
  final int bytes;
  final DateTime savedAt;

  /// Die Orte-Dateien, die mit dem Bereich liegen (`<zeile>_<spalte>.<gruppe>.json`).
  final List<String> poiFiles;

  /// Der Bau der Orte (`pois.json` → `build`), null ohne Orte.
  final String? poiBuild;

  /// Die Höhenkacheln im zweiten Archiv des Bereichs (seit 0.69.0,
  /// `height_tiles.dart`): wie viele, wie groß, aus welchem Bau
  /// (`heights.json` → `build`). 0 heißt: ohne Höhen gespeichert — vor
  /// 0.69.0 oder ohne Höhen-Manifest; „Aktualisieren" holt sie nach.
  final int heightTiles;
  final int heightBytes;
  final String? heightsBuild;

  bool get hasHeights => heightTiles > 0;

  /// Die Wege-Kacheln im dritten Archiv (seit 0.90.0, #212): Güte und
  /// Schwierigkeit für die Ebene „Wege" ohne Empfang. [waysBuild] steht,
  /// sobald beim Speichern ein Wege-Manifest da war — auch mit 0 Kacheln
  /// (ein Bereich, in dem OSM nichts weiß); null heißt: vor 0.90.0 oder
  /// ohne Manifest gespeichert, „Aktualisieren" holt sie nach.
  final int wayTiles;
  final int wayBytes;
  final String? waysBuild;

  bool get hasWays => wayTiles > 0;

  /// Die Region des Hosts, aus der der Bereich stammt (#220,
  /// `map_regions.dart`) — gegen ihre Manifeste wird er aktualisiert.
  /// Einträge vor 0.104.0 tragen keine: Dort war es DACH.
  final String region;

  /// Was der Bereich beim Speichern deckte, ohne die kleinen
  /// Orte-Dateien — nicht, was er ALLEIN belegt: Bereiche teilen Kacheln
  /// (`areaExclusiveBytesProvider`).
  int get totalBytes => bytes + heightBytes + wayBytes;

  StoredArea copyWith({
    String? name,
    AreaShape? shape,
    String? build,
    int? tiles,
    int? bytes,
    DateTime? savedAt,
    List<String>? poiFiles,
    String? poiBuild,
    int? heightTiles,
    int? heightBytes,
    String? heightsBuild,
    int? wayTiles,
    int? wayBytes,
    String? waysBuild,
    int? format,
    bool? complete,
  }) =>
      StoredArea(
        id: id,
        name: name ?? this.name,
        bounds: shape?.hull ?? bounds,
        shape: shape ?? this.shape,
        minZoom: minZoom,
        maxZoom: maxZoom,
        build: build ?? this.build,
        tiles: tiles ?? this.tiles,
        bytes: bytes ?? this.bytes,
        savedAt: savedAt ?? this.savedAt,
        poiFiles: poiFiles ?? this.poiFiles,
        poiBuild: poiBuild ?? this.poiBuild,
        heightTiles: heightTiles ?? this.heightTiles,
        heightBytes: heightBytes ?? this.heightBytes,
        heightsBuild: heightsBuild ?? this.heightsBuild,
        wayTiles: wayTiles ?? this.wayTiles,
        wayBytes: wayBytes ?? this.wayBytes,
        waysBuild: waysBuild ?? this.waysBuild,
        region: region,
        format: format ?? this.format,
        complete: complete ?? this.complete,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'bounds': bounds.toJson(),
        'shape': shape.toJson(),
        'min_zoom': minZoom,
        'max_zoom': maxZoom,
        'build': build,
        'tiles': tiles,
        'bytes': bytes,
        'saved_at': savedAt.toUtc().toIso8601String(),
        'poi_files': poiFiles,
        'poi_build': poiBuild,
        'height_tiles': heightTiles,
        'height_bytes': heightBytes,
        'heights_build': heightsBuild,
        'way_tiles': wayTiles,
        'way_bytes': wayBytes,
        'ways_build': waysBuild,
        'region': region,
        'format': format,
        'complete': complete,
      };

  factory StoredArea.fromJson(Map<String, dynamic> j) => StoredArea(
        id: j['id'] as String,
        name: j['name'] as String,
        bounds: AreaBounds.fromJson(j['bounds'] as Map<String, dynamic>),
        shape: j['shape'] == null ? null : AreaShape.fromJson(j['shape'] as Map<String, dynamic>),
        minZoom: j['min_zoom'] as int,
        maxZoom: j['max_zoom'] as int,
        build: j['build'] as String,
        tiles: j['tiles'] as int,
        bytes: j['bytes'] as int,
        savedAt: DateTime.parse(j['saved_at'] as String),
        poiFiles: (j['poi_files'] as List? ?? const []).cast<String>(),
        poiBuild: j['poi_build'] as String?,
        heightTiles: j['height_tiles'] as int? ?? 0,
        heightBytes: j['height_bytes'] as int? ?? 0,
        heightsBuild: j['heights_build'] as String?,
        wayTiles: j['way_tiles'] as int? ?? 0,
        wayBytes: j['way_bytes'] as int? ?? 0,
        waysBuild: j['ways_build'] as String?,
        region: j['region'] as String? ?? kDachRegionId,
        format: j['format'] as int? ?? 1,
        complete: j['complete'] as bool? ?? true,
      );
}

/// Das Format eines Index-Eintrags, den 0.106.0 schreibt.
const kStoredAreaFormat = 2;

/// Die gespeicherte Übersicht einer Region (Zoom 0–[maxZoom]).
class StoredOverview {
  const StoredOverview({
    required this.region,
    required this.build,
    required this.bytes,
    required this.maxZoom,
    required this.savedAt,
  });

  /// Die Kennung der Region (`ca`) — nie DACH.
  final String region;

  /// Der Protomaps-Bau (`JJJJMMTT`).
  final String build;
  final int bytes;
  final int maxZoom;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
        'region': region,
        'build': build,
        'bytes': bytes,
        'max_zoom': maxZoom,
        'saved_at': savedAt.toUtc().toIso8601String(),
      };

  factory StoredOverview.fromJson(Map<String, dynamic> j) {
    final region = j['region'] as String;
    // Die Kennung wird Teil eines Dateinamens.
    if (!RegExp(r'^[a-z]{2,8}$').hasMatch(region)) throw FormatException('Region $region');
    return StoredOverview(
      region: region,
      build: j['build'] as String,
      bytes: j['bytes'] as int,
      maxZoom: j['max_zoom'] as int,
      savedAt: DateTime.parse(j['saved_at'] as String),
    );
  }
}

/// Was die Ablage kann: der Index, die Orte-Dateien, die Übersichten —
/// und lesend der Altbestand bis 0.105.x.
abstract interface class AreaStore {
  Future<List<StoredArea>> list();

  /// Schreibt den Index ganz neu — die eine Stelle, an der ein Bereich
  /// sichtbar wird oder verschwindet.
  Future<void> saveIndex(List<StoredArea> areas);

  /// Eine Orte-Datei (`<zeile>_<spalte>.<gruppe>.json`), je Name EINMAL;
  /// eine liegende wird ersetzt.
  Future<void> putPoiFile(String name, String text);

  /// Die Orte-Datei [name], null, wenn sie nicht liegt.
  Future<String?> readPoiFile(String name);

  /// Nimmt Orte-Dateien weg — die, die kein Bereich mehr nennt.
  Future<void> deletePoiFiles(Iterable<String> names);

  /// Nimmt den Eintrag aus dem Index und den Altbestand des Bereichs
  /// weg. Die Kacheln im Speicher räumt, wer löscht (`tile_refs.dart`):
  /// Sie können einem anderen Bereich gehören.
  Future<void> delete(String id);

  // --- Altbestand (bis 0.105.x): je Bereich eigene Archive -------------
  //
  // Geschrieben nur noch von Tests (als Bestand, den die Übernahme
  // vorfindet); gelesen von der Übernahme.

  Future<void> putArchive(String id, Uint8List bytes);

  /// Der Pfad des Archivs auf der Platte, null im Browser.
  Future<String?> archivePath(String id);

  /// Die Bytes des Archivs — der Weg im Browser; null, wenn es fehlt.
  Future<Uint8List?> readArchive(String id);

  Future<void> putHeights(String id, Uint8List bytes);
  Future<String?> heightsPath(String id);
  Future<Uint8List?> readHeights(String id);

  Future<void> putWays(String id, Uint8List bytes);
  Future<String?> waysPath(String id);
  Future<Uint8List?> readWays(String id);

  /// Die Orte-Datei [name] im Ordner des Bereichs [id].
  Future<void> putLegacyPoiFile(String id, String name, String text);
  Future<String?> readLegacyPoiFile(String id, String name);

  /// Nimmt Archive und Orte-Ordner des Bereichs weg, den Index-Eintrag
  /// nicht — nach der Übernahme.
  Future<void> deleteLegacy(String id);

  // --- Die Übersichten der Regionen (seit 0.105.0), ein eigener Index ---

  Future<List<StoredOverview>> overviews();

  /// Legt die Übersicht einer Region ab (ersetzt eine ältere): erst die
  /// Datei, dann der Index.
  Future<void> putOverview(StoredOverview overview, Uint8List bytes);

  /// Pfad auf dem Telefon, Bytes im Browser — wie beim Kartenarchiv.
  Future<String?> overviewPath(String region);
  Future<Uint8List?> readOverview(String region);

  /// Nimmt Datei und Index-Eintrag weg.
  Future<void> deleteOverview(String region);
}

/// Die Übersichten im Index ohne [region], mit [add] am Ende — für alle
/// drei Ablagen dieselbe Regel.
List<StoredOverview> replaceOverview(List<StoredOverview> all, String region, [StoredOverview? add]) =>
    [for (final o in all) if (o.region != region) o, ?add];

/// Im Speicher — für Tests und als Rückfall ohne Speicher.
class MemoryAreaStore implements AreaStore {
  List<StoredArea> areas = [];
  final archives = <String, Uint8List>{};
  final heights = <String, Uint8List>{};
  final ways = <String, Uint8List>{};
  final legacyPoiFiles = <String, Map<String, String>>{};
  final poiFiles = <String, String>{};
  List<StoredOverview> overviewIndex = [];
  final overviewBytes = <String, Uint8List>{};

  @override
  Future<List<StoredArea>> list() async => List.unmodifiable(areas);

  @override
  Future<void> saveIndex(List<StoredArea> areas) async => this.areas = List.of(areas);

  @override
  Future<void> putPoiFile(String name, String text) async => poiFiles[name] = text;

  @override
  Future<String?> readPoiFile(String name) async => poiFiles[name];

  @override
  Future<void> deletePoiFiles(Iterable<String> names) async {
    for (final n in names) {
      poiFiles.remove(n);
    }
  }

  @override
  Future<void> delete(String id) async {
    areas = [for (final a in areas) if (a.id != id) a];
    await deleteLegacy(id);
  }

  @override
  Future<void> putArchive(String id, Uint8List bytes) async => archives[id] = bytes;

  @override
  Future<String?> archivePath(String id) async => null;

  @override
  Future<Uint8List?> readArchive(String id) async => archives[id];

  @override
  Future<void> putHeights(String id, Uint8List bytes) async => heights[id] = bytes;

  @override
  Future<String?> heightsPath(String id) async => null;

  @override
  Future<Uint8List?> readHeights(String id) async => heights[id];

  @override
  Future<void> putWays(String id, Uint8List bytes) async => ways[id] = bytes;

  @override
  Future<String?> waysPath(String id) async => null;

  @override
  Future<Uint8List?> readWays(String id) async => ways[id];

  @override
  Future<void> putLegacyPoiFile(String id, String name, String text) async =>
      (legacyPoiFiles[id] ??= {})[name] = text;

  @override
  Future<String?> readLegacyPoiFile(String id, String name) async => legacyPoiFiles[id]?[name];

  @override
  Future<void> deleteLegacy(String id) async {
    archives.remove(id);
    heights.remove(id);
    ways.remove(id);
    legacyPoiFiles.remove(id);
  }

  @override
  Future<List<StoredOverview>> overviews() async => List.unmodifiable(overviewIndex);

  @override
  Future<void> putOverview(StoredOverview overview, Uint8List bytes) async {
    overviewBytes[overview.region] = bytes;
    overviewIndex = replaceOverview(overviewIndex, overview.region, overview);
  }

  @override
  Future<String?> overviewPath(String region) async => null;

  @override
  Future<Uint8List?> readOverview(String region) async => overviewBytes[region];

  @override
  Future<void> deleteOverview(String region) async {
    overviewIndex = replaceOverview(overviewIndex, region);
    overviewBytes.remove(region);
  }
}

/// Die Ablage der Plattform: Dateien auf dem Telefon, IndexedDB im
/// Browser. Tests hängen `MemoryAreaStore` ein.
final areaStoreProvider = Provider<AreaStore>((ref) => createAreaStore());
