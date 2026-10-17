// Fehlende Kacheln vom Host (#187): der Sitzungsspeicher (ein zweiter Plan
// fragt nicht noch einmal), Höhen auch für Kacheln aus Bereichen ohne
// Höhen (#322, bis zur Grenze), der Satz
// im Blatt und der Schalter in den Reglern.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/features/map/pmtiles_tile_provider.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/height_tiles.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';
import 'package:trailbuddy/features/rides/road_index.dart' show RoadCoverage;
import 'package:trailbuddy/features/routing/loop_planner.dart';
import 'package:trailbuddy/features/routing/online_fill.dart';
import 'package:trailbuddy/features/routing/planning_graph.dart';
import 'package:trailbuddy/features/routing/road_graph_loader.dart' show kOnlineFillMaxTiles;
import 'package:trailbuddy/features/routing/route_profile.dart';

import '../fakes/fake_tiles.dart';

import '../fakes/l10n_de.dart';

void main() {
  final t = tileAt(48.0, 9.0, 13);
  final here = (z: 13, x: t.x, y: t.y);
  final elsewhere = (z: 13, x: t.x + 1, y: t.y);
  final mvt = mvtTile([road([(0, 2048), (4096, 2048)], 'path', kindDetail: 'track')]);

  Uint8List roadsArchive() => writePmTiles(
        tiles: [TileToWrite(13, t.x, t.y, mvt)],
        tileCompression: Compression.none,
        bounds: const TileBounds(west: 8.9, south: 47.9, east: 9.1, north: 48.1),
      );

  Uint8List heightsArchive() => writePmTiles(
        tiles: [
          for (final x in [t.x, t.x + 1])
            TileToWrite(kHeightTileZoom, x, t.y,
                encodeHeightTile([for (var i = 0; i < kHeightGrid * kHeightGrid; i++) 640])),
        ],
        tileCompression: Compression.gzip,
        bounds: const TileBounds(west: 8.9, south: 47.9, east: 9.1, north: 48.1),
        metadata: heightsMetadata('Test', '20261001'),
      );

  group('OnlineFill', () {
    late int roadOpens, heightOpens;
    late OnlineTileCache cache;

    OnlineFill fill() => OnlineFill(
          openRoads: () async {
            roadOpens++;
            return PmTilesVectorTileProvider.openBytes(roadsArchive());
          },
          openHeights: () async {
            heightOpens++;
            return PmTilesArchive.fromBytes(heightsArchive());
          },
          cache: cache,
        );

    setUp(() {
      roadOpens = 0;
      heightOpens = 0;
      cache = OnlineTileCache();
    });

    test('die Kachel kommt vom Host, ein zweiter Plan nimmt sie aus dem Speicher', () async {
      final first = fill();
      expect(await first.fetch(here), mvt);
      expect(await first.fetch(elsewhere), isNull, reason: 'außerhalb des Archivs: 404, kein Fehler');
      await first.close();
      expect(roadOpens, 1);

      final second = fill();
      expect(await second.fetch(here), mvt);
      expect(await second.fetch(elsewhere), isNull, reason: 'auch „hat er nicht" ist gemerkt');
      await second.close();
      expect(roadOpens, 1, reason: 'kein zweites Öffnen, keine zweite Anfrage');
    });

    test('Höhen für nachgeladene Kacheln immer, für andere bis zur Grenze (#322)', () async {
      final f = fill();
      final reader = HeightReader([f.heights]);
      expect((await reader.tileAt(t.x, t.y))!.at(0.5, 0.5), 640,
          reason: 'Wege aus einem Bereich ohne Höhen: die Höhe kommt trotzdem');
      await f.fetch(here);
      expect((await HeightReader([f.heights]).tileAt(t.x, t.y))!.at(0.5, 0.5), 640);
      expect(f.heightRequests, 1, reason: 'die zweite aus dem Speicher');
      expect(heightOpens, 1);
      await f.close();
    });

    test('die Grenze zählt nur Kacheln außerhalb der nachgeladenen, der Speicher zählt nie', () async {
      final h = OnlineHeights(
        open: () async => PmTilesArchive.fromBytes(heightsArchive()),
        cache: cache,
        allow: (x, y) => x == t.x + 1,
        maxRequests: 1,
      );
      expect(await h.tile(t.x, t.y), isNotNull, reason: 'die erste außerhalb');
      expect(await HeightReader([h]).tileAt(t.x, t.y - 1), isNull, reason: 'über der Grenze: keine Anfrage');
      expect(h.requests, 1);
      expect(await h.tile(t.x + 1, t.y), isNotNull, reason: 'nachgeladen: immer');
      expect(await h.tile(t.x, t.y), isNotNull, reason: 'aus dem Speicher, auch über der Grenze');
      expect(h.requests, 2);
      await h.close();
    });

    test('ohne Manifest: ein Fehler, nach dem der Lader aufhört', () async {
      final f = OnlineFill(openRoads: () async => null, openHeights: () async => null, cache: cache);
      expect(f.fetch(here), throwsStateError);
      await f.close();
    });

    test('der Speicher ist begrenzt, die ältesten fallen zuerst', () {
      for (var i = 0; i <= kOnlineCacheTiles; i++) {
        cache.putRoads((z: 13, x: i, y: 0), Uint8List(1));
      }
      expect(cache.hasRoads((z: 13, x: 0, y: 0)), isFalse);
      expect(cache.hasRoads((z: 13, x: kOnlineCacheTiles, y: 0)), isTrue);
      expect(cache.length, kOnlineCacheTiles);
    });
  });

  group('planningCoverageNote', () {
    PlanningGraph g({required int found, int needed = 10, int online = 0, bool capped = false, bool broken = false}) =>
        PlanningGraph(
          coverage: found == needed ? RoadCoverage.complete : RoadCoverage.partial,
          tilesFound: found,
          tilesNeeded: needed,
          tilesOnline: online,
          onlineCapped: capped,
          onlineBroken: broken,
        );

    test('alles aus den Bereichen: kein Satz', () {
      expect(planningCoverageNote(l10nDe, g(found: 10), loop: true), isNull);
    });

    test('vollständig dank Netz: sagt es, und was ohne Empfang wäre', () {
      expect(planningCoverageNote(l10nDe, g(found: 10, online: 12), loop: true),
          '12 Kacheln online nachgeladen — ohne Empfang ginge die Runde so nicht.');
      expect(planningCoverageNote(l10nDe, g(found: 10, online: 1), loop: false),
          '1 Kachel online nachgeladen — ohne Empfang ginge der Weg so nicht.');
    });

    test('ein Teil: offline wie bisher, online mit dem Grund für den Rest', () {
      expect(planningCoverageNote(l10nDe, g(found: 4), loop: true), contains('kann kürzer sein'));
      expect(planningCoverageNote(l10nDe, g(found: 8, online: 4, capped: true), loop: true),
          contains('mehr als $kOnlineFillMaxTiles holt eine Planung nicht'));
      expect(planningCoverageNote(l10nDe, g(found: 8, online: 4, broken: true), loop: true),
          contains('riss die Verbindung ab'));
      expect(planningCoverageNote(l10nDe, g(found: 8, online: 4), loop: true), contains('außerhalb der Karte'));
    });
  });

  test('der Schalter steht in den Reglern: ab Werk an, gemerkt, ältere Einträge lesen sich als an', () {
    const p = RiderProfile.bio;
    expect(LoopPrefs.defaults(p).fillOnline, isTrue);
    expect(LoopPrefs.parse('h=3.0;c=800.0;w=1.0;r=1;k=12.0', p).fillOnline, isTrue, reason: 'vor 0.78.0');
    final off = LoopPrefs.defaults(p).copyWith(fillOnline: false);
    expect(off.encode(), contains(';o=0'));
    expect(LoopPrefs.parse(off.encode(), p).fillOnline, isFalse);
  });

  test('die Vorlieben (#188) stehen in den Reglern: ab Werk meiden, gemerkt, ältere Einträge meiden', () {
    const p = RiderProfile.bio;
    expect(LoopPrefs.defaults(p).route, const RoutePrefs());
    expect(LoopPrefs.parse('h=3.0;c=800.0;w=1.0;r=1;k=12.0;o=1', p).route, const RoutePrefs(), reason: 'vor 0.81.0');
    for (final r in const [
      RoutePrefs(avoidRoads: false),
      RoutePrefs(avoidHiking: false),
      RoutePrefs(avoidSteep: false),
      RoutePrefs(avoidRoads: false, avoidHiking: false, avoidSteep: false),
    ]) {
      final prefs = LoopPrefs.defaults(p).copyWith(route: r);
      expect(LoopPrefs.parse(prefs.encode(), p).route, r);
      expect(LoopPrefs.parse(prefs.encode(), p).fillOnline, isTrue);
    }
  });
}
