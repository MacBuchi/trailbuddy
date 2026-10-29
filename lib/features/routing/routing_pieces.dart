// Die vorgebackenen Stücke des Planers im Kachelspeicher (#380,
// Konzept-Routing 11.4 Weg B): Vor dem Lesen fragt der Lader je Kachel des
// Rahmens, ob ein FRISCHES Stück liegt — frisch heißt, sein Bau
// ([pieceBuild]) nennt dieselben Bauten von Karte, Höhen und Wege-Archiv,
// die jetzt im Speicher liegen. Solche Kacheln liest er nicht mehr; der
// Rest wird im Rechen-Isolate gebacken, und die neuen Stücke legt
// [PieceLookup.keep] danach in den Speicher.
//
// Zwei Regeln, die man wissen muss:
// - **Gespeichert wird nur, was aus dem Speicher kam.** Eine online
//   ergänzte Kachel (#187) hat keinen Bau im Speicher und keinen Bereich,
//   der sie hält; ihr Stück gilt nur für die Sitzung ([PieceLookup.session],
//   gehängt an die Bytes aus `OnlineTileCache` — dieselbe Kachel kommt dort
//   als dasselbe Objekt zurück).
// - **Fehlt eine Quelle im Speicher, steht `-` im Bau** (keine Höhen, kein
//   Wege-Archiv). Kommt sie mit „Aktualisieren" dazu, ist das Stück alt und
//   wird neu gebacken — ohne Netz.
//
// Der UI-Isolate liest hier nur Bauten und Bytes; dekodiert und gebacken
// wird drüben (`graph_input.dart`). Jeder Fehler hier kostet nur die
// Abkürzung, nie die Planung: Dann wird eben alles gebacken.
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../offline_areas/area_plan.dart' show TileXYZ, tileIdOf;
import '../offline_areas/tile_store.dart';
import 'graph_input.dart';
import 'road_graph_loader.dart' show RoadTileBytes;
import 'routing_tile.dart';

/// Was der Lader über die Stücke seines Rahmens weiß.
class PieceLookup {
  PieceLookup._(this._store, this._session, this.fresh, this._targets);

  /// Ohne Speicher oder ohne Bereich im Rahmen: nichts gefunden, nichts
  /// zu speichern.
  PieceLookup.none(this._session)
      : _store = null,
        fresh = const {},
        _targets = const {};

  final TileStore? _store;
  final Expando<Uint8List> _session;

  /// Die frischen Stücke aus dem Speicher, je Kachel.
  final Map<(int, int), RoutingPiece> fresh;

  /// Wohin ein neu gebackenes Stück gehört: Region und Bau — nur Kacheln,
  /// deren Wege aus dem Speicher kommen.
  final Map<(int, int), ({String region, String build})> _targets;

  /// Liegt eine Kachel im Speicher ohne frisches Stück? Kacheln ohne
  /// Karte zählen nicht — sie haben nie eins, und das Backen im
  /// Hintergrund (`routing_bake.dart`) liefe sonst bei jedem Start an.
  bool get pending => _targets.isNotEmpty;

  /// Die Bytes der Kacheln, die gebacken werden ohne Platz im Speicher
  /// (online ergänzt) — ihr Stück hängt an genau diesem Objekt.
  final _online = <(int, int), Uint8List>{};

  /// Teilt [roads] in die zu backenden und die, für die in dieser Sitzung
  /// schon ein Stück entstand (online ergänzte Kacheln, [_session]).
  ({List<RoadTileBytes> roads, List<RoutingPiece> pieces}) split(List<RoadTileBytes> roads) {
    final bake = <RoadTileBytes>[];
    final pieces = <RoutingPiece>[];
    for (final r in roads) {
      final xy = (r.tile.x, r.tile.y);
      if (_targets.containsKey(xy)) {
        bake.add(r);
        continue;
      }
      final known = _session[r.bytes];
      if (known != null) {
        pieces.add((x: r.tile.x, y: r.tile.y, bytes: known));
      } else {
        _online[xy] = r.bytes;
        bake.add(r);
      }
    }
    return (roads: bake, pieces: pieces);
  }

  /// Legt die Stücke aus [report] ab: in den Speicher, wo die Kachel aus
  /// ihm kam (je Region ein Block), sonst an die Bytes der Sitzung. Nimmt
  /// Stücke, die sich drüben nicht lesen ließen, aus dem Speicher. Wirft
  /// nie — ein Fehler kostet nur die Abkürzung beim nächsten Mal.
  Future<void> keep(GraphReport report) => keepPieces(report.baked, broken: report.broken);

  /// Dasselbe ohne Bericht — für das Backen im Hintergrund
  /// (`routing_bake.dart`), das keinen Graphen baut.
  Future<void> keepPieces(List<RoutingPiece> baked, {List<(int, int)> broken = const []}) async {
    final byRegion = <String, List<StoreTile>>{};
    for (final p in baked) {
      final xy = (p.x, p.y);
      final target = _targets[xy];
      if (target != null) {
        (byRegion[target.region] ??= []).add(StoreTile(kRoutingTileZoom, p.x, p.y, p.bytes, target.build));
      } else if (_online[xy] case final bytes?) {
        _session[bytes] = p.bytes;
      }
    }
    final store = _store;
    if (store == null) return;
    try {
      for (final e in byRegion.entries) {
        await store.put(e.key, TileLayer.routing, e.value);
      }
      final gone = <String, List<int>>{};
      for (final (x, y) in broken) {
        final region = _regionOf[(x, y)];
        if (region == null) continue;
        (gone[region] ??= []).add(tileIdOf((z: kRoutingTileZoom, x: x, y: y)));
      }
      for (final e in gone.entries) {
        await store.remove(e.key, TileLayer.routing, e.value);
      }
    } catch (e, s) {
      logError('Routing-Kacheln speichern', e, s);
    }
  }

  /// Die Region jedes frischen Stücks — für [keep], wenn eins kaputt war.
  final _regionOf = <(int, int), String>{};
}

/// Sucht die frischen Stücke für [tiles] in den Regionen [regions] (in
/// dieser Reihenfolge; eine Kachel gehört der ersten, die ihre Wege hat).
/// Liest je Region und Ebene nur die Bauten dieser Kacheln
/// ([TileStore.builds]), dann die Bytes der frischen Stücke.
Future<PieceLookup> findPieces(
    TileStore store, Iterable<String> regions, List<TileXYZ> tiles, Expando<Uint8List> session) async {
  final fresh = <(int, int), RoutingPiece>{};
  final targets = <(int, int), ({String region, String build})>{};
  final lookup = PieceLookup._(store, session, fresh, targets);
  final ids = {for (final t in tiles) tileIdOf(t): t};
  try {
    for (final region in regions) {
      final open = [
        for (final e in ids.entries)
          if (!targets.containsKey((e.value.x, e.value.y))) e.key,
      ];
      if (open.isEmpty) break;
      final map = await store.builds(region, TileLayer.map, open);
      if (map.isEmpty) continue;
      final heights = await store.builds(region, TileLayer.heights, map.keys);
      final ways = await store.builds(region, TileLayer.ways, map.keys);
      final pieces = await store.builds(region, TileLayer.routing, map.keys);
      for (final MapEntry(key: id, value: mapBuild) in map.entries) {
        final t = ids[id]!;
        final build = pieceBuild(map: mapBuild, heights: heights[id], ways: ways[id]);
        targets[(t.x, t.y)] = (region: region, build: build);
        if (pieces[id] != build) continue;
        final bytes = await store.read(region, TileLayer.routing, kRoutingTileZoom, t.x, t.y);
        if (bytes == null) continue;
        fresh[(t.x, t.y)] = (x: t.x, y: t.y, bytes: bytes);
        lookup._regionOf[(t.x, t.y)] = region;
      }
    }
  } catch (e, s) {
    // Ohne Abkürzung wird gebacken wie beim ersten Mal; die Planung steht.
    logError('Routing-Kacheln suchen', e, s);
    fresh.clear();
    targets.clear();
  }
  // Wer ein frisches Stück hat, wird nicht gebacken und braucht kein Ziel.
  for (final xy in fresh.keys) {
    targets.remove(xy);
  }
  return lookup;
}

/// Die Stücke online ergänzter Kacheln für die Sitzung — gehängt an die
/// Bytes, die `OnlineTileCache` je Kachel als dasselbe Objekt liefert.
final routingPieceSessionProvider = Provider<Expando<Uint8List>>((ref) => Expando('routing-pieces'));
