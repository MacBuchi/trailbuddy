// Fehlende Wege- und Höhenkacheln vom eigenen Kartenhost (#187, seit
// 0.78.0). Die Planung rechnet über die Kacheln der gespeicherten
// Bereiche; mit Empfang kommen die fehlenden aus DEMSELBEN Archiv, aus
// dem die Bereiche geschnitten sind (`dach-<build>.pmtiles`, Ebene
// `roads`), aus dem Höhenarchiv (`heights-<build>.pmtiles`) und seit
// #213 aus dem Wege-Archiv (`ways-<build>.pmtiles`, die Güte), per
// Range-Anfrage wie beim Speichern eines Bereichs. Kein neues Netzziel:
// Die Online-Karte holt dieselben Kacheln.
//
// Drei Regeln:
// - **Die letzte Quelle**: Gefragt wird nur nach Kacheln, die kein Bereich
//   hat, höchstens [kOnlineFillMaxTiles] je Planung (der Lader zählt).
//   Höhen nur für genau diese Kacheln — ein Bereich ohne Höhen (vor
//   0.69.0) bekommt hier keine nachgereicht, das macht „Aktualisieren".
// - **Nur für die Sitzung**: Die Kacheln liegen im Speicher
//   ([OnlineTileCache], höchstens [kOnlineCacheTiles] je Sorte), damit ein
//   zweiter Plan dieselbe Gegend nicht noch einmal holt. Behalten ist
//   #155 („Gesehenes bleibt liegen").
// - **Ein Netzfehler beendet das Nachladen**, er kippt die Planung nicht:
//   Was bis dahin da ist, reicht für einen Plan, und das Blatt sagt, über
//   wie viele Kacheln. Jeder Schritt hat eine Frist ([kOnlineFillTimeout]) —
//   „ein Balken, über den nichts kommt" ist im Wald der Normalfall.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' show ProviderException, TileIdentity;

import '../../core/errors.dart';
import '../map/online_map.dart';
import '../map/pmtiles_tile_provider.dart';
import '../offline_areas/area_plan.dart';
import '../offline_areas/area_providers.dart' show areaSourceOpenerProvider, areaWaysManifestLoaderProvider;
import '../offline_areas/height_tiles.dart';

/// Höchstens so lange wartet ein Schritt des Nachladens (Manifest, Archiv
/// öffnen, eine Kachel). Danach gilt das Netz als weg.
const kOnlineFillTimeout = Duration(seconds: 10);

/// So viele Kacheln je Sorte hält der Sitzungsspeicher, die ältesten
/// fallen zuerst. Eine Wegekachel bei z13 hat meist einige zehn KB.
const kOnlineCacheTiles = 300;

/// Die nachgeladenen Kacheln dieser Sitzung — im Speicher, nie auf der
/// Platte. Auch „der Host hat sie nicht" wird gemerkt (null).
class OnlineTileCache {
  // Dart-Maps behalten die Einfügereihenfolge: Der erste Schlüssel ist
  // der älteste.
  final _roads = <int, Uint8List?>{};
  final _heights = <int, HeightTile?>{};
  final _ways = <int, Uint8List?>{};

  static int _key(int x, int y) => (x << kHeightTileZoom) | y;

  bool hasRoads(TileXYZ t) => _roads.containsKey(_key(t.x, t.y));
  Uint8List? roads(TileXYZ t) => _roads[_key(t.x, t.y)];
  void putRoads(TileXYZ t, Uint8List? bytes) => _put(_roads, _key(t.x, t.y), bytes);

  bool hasHeights(int x, int y) => _heights.containsKey(_key(x, y));
  HeightTile? heights(int x, int y) => _heights[_key(x, y)];
  void putHeights(int x, int y, HeightTile? tile) => _put(_heights, _key(x, y), tile);

  bool hasWays(TileXYZ t) => _ways.containsKey(_key(t.x, t.y));
  Uint8List? ways(TileXYZ t) => _ways[_key(t.x, t.y)];
  void putWays(TileXYZ t, Uint8List? bytes) => _put(_ways, _key(t.x, t.y), bytes);

  int get length => _roads.length + _heights.length + _ways.length;

  static void _put<V>(Map<int, V> map, int key, V value) {
    map.remove(key);
    map[key] = value;
    while (map.length > kOnlineCacheTiles) {
      map.remove(map.keys.first);
    }
  }
}

final onlineTileCacheProvider = Provider<OnlineTileCache>((ref) => OnlineTileCache());

/// Höhenkacheln vom Host, über den Sitzungsspeicher — für die Planung
/// (nur die Kacheln, die sie vom Host hat, [allow]) und für das Profil
/// eines Trails ohne aufgezeichnete Höhen (#186, jede Kachel). Öffnet das
/// Archiv erst, wenn eine Kachel nicht im Speicher liegt; ein Fehler
/// beendet das Fragen für dieses Objekt.
class OnlineHeights implements HeightTileSource {
  OnlineHeights({
    required this.open,
    required this.cache,
    this.allow,
    this.timeout = kOnlineFillTimeout,
  });

  /// Öffnet das Höhenarchiv des Hosts; null ohne Manifest oder Bau.
  final Future<PmTilesArchive?> Function() open;
  final OnlineTileCache cache;

  /// Nur Kacheln, für die das gilt; ohne: jede.
  final bool Function(int x, int y)? allow;
  final Duration timeout;

  Future<PmTilesArchive?>? _archive;
  bool _failed = false;

  /// Wie viele Kacheln über das Netz kamen (nicht aus dem Speicher).
  int requests = 0;

  @override
  Future<HeightTile?> tile(int x, int y) async {
    if (allow != null && !allow!(x, y)) return null;
    if (cache.hasHeights(x, y)) return cache.heights(x, y);
    if (_failed) return null;
    try {
      final archive = await (_archive ??= open().timeout(timeout));
      if (archive == null) {
        _failed = true;
        return null;
      }
      final id = ZXY(kHeightTileZoom, x, y).toTileId();
      HeightTile? tile;
      requests++;
      if (await archive.lookup(id).timeout(timeout) != null) {
        try {
          tile = HeightTile.decode((await archive.tile(id).timeout(timeout)).bytes());
        } on FormatException {
          tile = null;
        }
      }
      cache.putHeights(x, y, tile);
      return tile;
    } catch (e, s) {
      // Ohne Höhen rechnet die Suche flach bzw. zeigt das Blatt kein
      // Profil — kein Grund, mehr zu kippen. Gemeldet nur, was nicht nach
      // Funkloch aussieht.
      if (!looksOffline(e)) logError('Höhen online nachladen', e, s);
      _failed = true;
      return null;
    }
  }

  @override
  Future<void> close() async {
    try {
      await (await _archive)?.close();
    } catch (_) {
      // Nie geöffnet oder schon weg — nichts zu schließen.
    }
  }
}

/// Eine Planung lang: öffnet die Archive des Hosts erst, wenn eine Kachel
/// fehlt, und schließt sie danach ([close]).
class OnlineFill {
  OnlineFill({
    required this.openRoads,
    required Future<PmTilesArchive?> Function() openHeights,
    required this.cache,
    this.openWays,
    this.timeout = kOnlineFillTimeout,
  }) {
    _heights = OnlineHeights(
      open: openHeights,
      cache: cache,
      allow: (x, y) => _fetched.contains(OnlineTileCache._key(x, y)),
      timeout: timeout,
    );
  }

  /// Öffnet das Kartenarchiv des Hosts; null ohne Manifest.
  final Future<PmTilesVectorTileProvider?> Function() openRoads;

  /// Öffnet das Wege-Archiv des Hosts (#213); null ohne Manifest oder
  /// ohne Naht — dann bleibt die Güte der nachgeladenen Kacheln unbekannt.
  final Future<PmTilesVectorTileProvider?> Function()? openWays;
  final OnlineTileCache cache;
  final Duration timeout;

  Future<PmTilesVectorTileProvider?>? _roads;
  Future<PmTilesVectorTileProvider?>? _ways;
  late final OnlineHeights _heights;

  /// Die Kacheln, die diese Planung vom Host hat — nur für sie fragt
  /// [heights] das Höhenarchiv.
  final _fetched = <int>{};

  /// Wie viele Höhenkacheln über das Netz kamen (nicht aus dem Speicher).
  int get heightRequests => _heights.requests;

  /// Die Wegekachel [t] — aus dem Speicher oder vom Host. Null: Der Host
  /// hat sie nicht. Wirft bei Netzfehler oder Frist; der Lader hört dann
  /// auf zu fragen.
  Future<Uint8List?> fetch(TileXYZ t) async {
    if (cache.hasRoads(t)) {
      final cached = cache.roads(t);
      if (cached != null) _fetched.add(OnlineTileCache._key(t.x, t.y));
      return cached;
    }
    final archive = await (_roads ??= openRoads().timeout(timeout));
    if (archive == null) throw StateError('Kein Kartenhost');
    Uint8List? bytes;
    try {
      bytes = await archive.provide(TileIdentity(t.z, t.x, t.y)).timeout(timeout);
    } on ProviderException catch (e) {
      // 404: außerhalb des Archivs (Meer, Ausland). Alles andere ist kein
      // „hat er nicht", sondern ein Fehler.
      if (e.statusCode != 404) rethrow;
      bytes = null;
    }
    cache.putRoads(t, bytes);
    if (bytes != null) _fetched.add(OnlineTileCache._key(t.x, t.y));
    return bytes;
  }

  /// Die Kachel [t] des Wege-Archivs (#213) — nur für Kacheln, die diese
  /// Planung vom Host hat (der Lader fragt nur nach denen). Null: keine
  /// getaggten Wege dort (das Archiv hat Lücken) oder kein Archiv. Wirft
  /// bei Netzfehler oder Frist.
  Future<Uint8List?> fetchWays(TileXYZ t) async {
    if (cache.hasWays(t)) return cache.ways(t);
    final open = openWays;
    if (open == null) return null;
    final archive = await (_ways ??= open().timeout(timeout));
    if (archive == null) return null;
    Uint8List? bytes;
    try {
      bytes = await archive.provide(TileIdentity(t.z, t.x, t.y)).timeout(timeout);
    } on ProviderException catch (e) {
      if (e.statusCode != 404) rethrow;
      bytes = null;
    }
    cache.putWays(t, bytes);
    return bytes;
  }

  /// Höhen für die nachgeladenen Kacheln — die letzte Quelle des Lesers.
  /// Geschlossen wird über [close], einmal für beide Archive.
  HeightTileSource get heights => _NoClose(_heights);

  Future<void> close() async {
    for (final archive in [_roads, _ways]) {
      try {
        await (await archive)?.close();
      } catch (_) {
        // Nie geöffnet oder schon weg — nichts zu schließen.
      }
    }
    await _heights.close();
  }
}

class _NoClose implements HeightTileSource {
  _NoClose(this._inner);
  final HeightTileSource _inner;

  @override
  Future<HeightTile?> tile(int x, int y) => _inner.tile(x, y);

  @override
  Future<void> close() async {}
}

/// Öffnet das Höhenarchiv des Hosts über sein Manifest; null ohne.
Future<PmTilesArchive?> Function() _openHostHeights(Ref ref) => () async {
      final manifest = await ref.read(heightsManifestProvider.future);
      if (manifest == null) return null;
      return ref.read(areaSourceOpenerProvider)(manifest.archiveUri);
    };

/// Baut das Nachladen für eine Planung aus den Manifesten des Hosts —
/// die Naht, die Tests ersetzen.
final onlineFillFactoryProvider = Provider<OnlineFill Function()>((ref) => () => OnlineFill(
      openRoads: () async {
        final manifest = await ref.read(mapManifestProvider.future);
        if (manifest == null) return null;
        return ref.read(onlineArchiveOpenerProvider)(manifest.archiveUri);
      },
      openHeights: _openHostHeights(ref),
      openWays: () async {
        // Unabhängig vom Schalter der Ebene, wie die Bereiche (#212 PR 3).
        final manifest = await ref.read(areaWaysManifestLoaderProvider)();
        if (manifest == null) return null;
        return ref.read(onlineArchiveOpenerProvider)(manifest.archiveUri);
      },
      cache: ref.read(onlineTileCacheProvider),
    ));

/// Höhen vom Host für jede Kachel (#186) — dieselbe Naht für Tests. Der
/// Aufrufer schließt die Quelle nach Gebrauch.
final onlineHeightsFactoryProvider = Provider<OnlineHeights Function()>(
    (ref) => () => OnlineHeights(open: _openHostHeights(ref), cache: ref.read(onlineTileCacheProvider)));
