// Die Ablage gespeicherter Bereiche (Konzept 3.2): je Bereich EIN
// PMTiles-Archiv (Zoom 8 bis zum Zoom des Hosts), seit 0.69.0 ein
// zweites mit den Höhenkacheln (`height_tiles.dart`), seit 0.90.0 ein
// drittes mit den Wegen (`way_layer.dart`, #212), die Orte-Dateien
// seiner Rasterzellen und ein Eintrag im Index. Auf dem Telefon Dateien
// unter `offline_maps/areas/` (vom Backup ausgenommen — jederzeit neu
// ladbar, und ein Bereich sprengt Googles 25 MB), im Browser IndexedDB
// (`area_store_idb.dart`), im Test der Speicher.
//
// Bereiche sind Absicht: Sie werden nie verdrängt, nur auf Wunsch
// gelöscht (Liste „Meine Bereiche").
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  }) : shape = shape ?? RectShape(bounds);

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

  /// Alles, was der Bereich auf dem Gerät belegt (ohne die kleinen
  /// Orte-Dateien).
  int get totalBytes => bytes + heightBytes + wayBytes;

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
      );
}

/// Was die Ablage kann. Archive kommen als Ganzes (ein Bereich ist
/// Dutzende bis wenige hundert MB; geschrieben wird einmal, am Ende des
/// Downloads); gelesen wird auf dem Telefon über den PFAD (MapLibre und
/// `FileAt` lesen faul), im Browser über die Bytes.
abstract interface class AreaStore {
  Future<List<StoredArea>> list();

  /// Schreibt den Index ganz neu — die eine Stelle, an der ein Bereich
  /// sichtbar wird oder verschwindet.
  Future<void> saveIndex(List<StoredArea> areas);

  Future<void> putArchive(String id, Uint8List bytes);

  /// Der Pfad des Archivs auf der Platte, null im Browser.
  Future<String?> archivePath(String id);

  /// Die Bytes des Archivs — der Weg im Browser; null, wenn es fehlt.
  Future<Uint8List?> readArchive(String id);

  Future<void> putPoiFile(String id, String name, String text);

  /// Die Orte-Datei [name] aus irgendeinem Bereich, der sie trägt.
  Future<String?> readPoiFile(String name);

  /// Das zweite Archiv eines Bereichs: seine Höhenkacheln (seit 0.69.0).
  /// Dieselben Wege wie beim Kartenarchiv — Pfad auf dem Telefon, Bytes
  /// im Browser.
  Future<void> putHeights(String id, Uint8List bytes);
  Future<String?> heightsPath(String id);
  Future<Uint8List?> readHeights(String id);

  /// Nimmt nur die Höhen weg (der Bereich bleibt) — wenn das Entfernen
  /// von Kacheln keine Höhenkachel übrig lässt.
  Future<void> deleteHeights(String id);

  /// Das dritte Archiv: die Wege (seit 0.90.0, #212), dieselben Wege wie
  /// bei den Höhen.
  Future<void> putWays(String id, Uint8List bytes);
  Future<String?> waysPath(String id);
  Future<Uint8List?> readWays(String id);
  Future<void> deleteWays(String id);

  /// Löscht Archiv, Höhen, Wege, Orte-Dateien und den Index-Eintrag.
  Future<void> delete(String id);
}

/// Im Speicher — für Tests und als Rückfall ohne Speicher.
class MemoryAreaStore implements AreaStore {
  List<StoredArea> areas = [];
  final archives = <String, Uint8List>{};
  final heights = <String, Uint8List>{};
  final ways = <String, Uint8List>{};
  final poiFiles = <String, Map<String, String>>{};

  @override
  Future<List<StoredArea>> list() async => List.unmodifiable(areas);

  @override
  Future<void> saveIndex(List<StoredArea> areas) async => this.areas = List.of(areas);

  @override
  Future<void> putArchive(String id, Uint8List bytes) async => archives[id] = bytes;

  @override
  Future<String?> archivePath(String id) async => null;

  @override
  Future<Uint8List?> readArchive(String id) async => archives[id];

  @override
  Future<void> putPoiFile(String id, String name, String text) async =>
      (poiFiles[id] ??= {})[name] = text;

  @override
  Future<String?> readPoiFile(String name) async {
    for (final area in areas) {
      final text = poiFiles[area.id]?[name];
      if (text != null && area.poiFiles.contains(name)) return text;
    }
    return null;
  }

  @override
  Future<void> putHeights(String id, Uint8List bytes) async => heights[id] = bytes;

  @override
  Future<String?> heightsPath(String id) async => null;

  @override
  Future<Uint8List?> readHeights(String id) async => heights[id];

  @override
  Future<void> deleteHeights(String id) async => heights.remove(id);

  @override
  Future<void> putWays(String id, Uint8List bytes) async => ways[id] = bytes;

  @override
  Future<String?> waysPath(String id) async => null;

  @override
  Future<Uint8List?> readWays(String id) async => ways[id];

  @override
  Future<void> deleteWays(String id) async => ways.remove(id);

  @override
  Future<void> delete(String id) async {
    areas = [for (final a in areas) if (a.id != id) a];
    archives.remove(id);
    heights.remove(id);
    ways.remove(id);
    poiFiles.remove(id);
  }
}

/// Die Ablage der Plattform: Dateien auf dem Telefon, IndexedDB im
/// Browser. Tests hängen `MemoryAreaStore` ein.
final areaStoreProvider = Provider<AreaStore>((ref) => createAreaStore());
