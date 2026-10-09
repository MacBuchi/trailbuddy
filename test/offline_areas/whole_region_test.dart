// Die ganze Region (#229 Schritt 5, Konzept 8.2): ein Bereich mit der Form
// `RegionShape`. Was dabei anders ist als bei einem gezeichneten Bereich —
// Verweise gegen den Index statt gegen Millionen Kacheln, Entwurf und
// Radierer lassen sie aus, die Hervorhebung ist EIN Rechteck — und das
// Orte-Bündel, das statt zehntausender Dateien kommt.
import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/map/poi.dart';
import 'package:trailbuddy/features/offline_areas/area_draw.dart';
import 'package:trailbuddy/features/offline_areas/area_overlay.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/area_trim.dart';
import 'package:trailbuddy/features/offline_areas/poi_bundle.dart';
import 'package:trailbuddy/features/offline_areas/tile_refs.dart';
import 'package:trailbuddy/features/offline_areas/tile_store.dart';

const _box = AreaBounds(south: 47.0, west: 10.0, north: 48.5, east: 12.5);
const _region = RegionShape(region: 'dach', bounds: _box);
const _inner = RectShape(AreaBounds(south: 47.9, west: 11.6, north: 47.95, east: 11.7));

StoredArea _area(String id, AreaShape shape) => StoredArea(
      id: id,
      name: id,
      bounds: shape.hull,
      shape: shape,
      minZoom: 8,
      maxZoom: 10,
      build: '20260928',
      tiles: 1,
      bytes: 1,
      savedAt: DateTime.utc(2026, 9, 28),
      format: kStoredAreaFormat,
      complete: true,
    );

/// Ein Bündel wie `tool/poi_extract.py` es schreibt.
({Uint8List bytes, PoiBundle meta}) _bundle(String build, Map<String, String> files, {int? claim}) {
  final raw = StringBuffer('${jsonEncode({'build': build, 'files': claim ?? files.length, 'format': 1})}\n');
  for (final e in files.entries) {
    raw.write('${e.key}\t${e.value}');
  }
  final bytes = Uint8List.fromList(gzip.encode(utf8.encode(raw.toString())));
  return (
    bytes: bytes,
    meta: PoiBundle(
        file: 'bundle.tsv.gz',
        files: claim ?? files.length,
        bytes: bytes.length,
        sha256: crypto.sha256.convert(bytes).toString()),
  );
}

void main() {
  test('die Form überlebt den Index', () {
    final back = AreaShape.fromJson(jsonDecode(jsonEncode(_region.toJson())) as Map<String, dynamic>);
    expect(back, isA<RegionShape>());
    expect((back as RegionShape).region, 'dach');
    expect(back.bounds.toJson(), _box.toJson());
  });

  test('mit der ganzen Region gehört ihr jede liegende Kachel — gegen den Index, nicht gegen ihre Kacheln', () {
    final index = {1: const StoredTileInfo(1, '20260901'), 99999999: const StoredTileInfo(1, '20260901')};
    expect(coversWholeRegion([_area('r', _region)]), isTrue);
    expect(referencedIn([_area('r', _region)], TileLayer.map, index), {1, 99999999});
    expect(referencedIn([_area('a', _inner)], TileLayer.map, index), isNot(contains(99999999)));
    expect(staleTiles(index, referencedIn([_area('r', _region)], TileLayer.map, index), '20261001').ids.length, 2);
  });

  test('Löschen: neben der Region gibt ein Bereich nichts frei; die Region gibt frei, was er nicht deckt', () async {
    final tiles = MemoryTileStore();
    final all = _region.tiles(maxZoom: 10);
    await tiles.put('dach', TileLayer.map, [for (final t in all) StoreTile(t.z, t.x, t.y, Uint8List(10), '20260928')]);
    final region = _area('r', _region), inner = _area('a', _inner);
    final withoutInner = await orphansAfter(store: tiles, remaining: [region], regions: {'dach'}, gone: [inner]);
    expect(orphanBytes(withoutInner), 0, reason: 'die Region deckt alles');
    final withoutRegion = await orphansAfter(store: tiles, remaining: [inner], regions: {'dach'}, gone: [region]);
    expect(orphanMapTiles(withoutRegion), all.length - _inner.tiles(maxZoom: 10).length);
  });

  test('der Radierer lässt die Region aus — sie geht nur im Ganzen', () async {
    final trimmer = AreaTrimmer(MemoryAreaStore(), MemoryTileStore());
    final keys = _inner.keysAt(kAreaShapeZoom);
    final plan = await trimmer.plan([_area('r', _region), _area('a', _inner)], keys);
    expect([for (final t in plan.trims) t.area.id], ['a']);
  });

  test('der Entwurf: was ganz in einer gespeicherten Region liegt, kommt nicht dazu', () {
    final inside = _inner.keysAt(kAreaShapeZoom).first;
    const far = RectShape(AreaBounds(south: 50.0, west: 5.0, north: 50.01, east: 5.01));
    expect(insideRegions(inside, [_box]), isTrue);
    expect(insideRegions(far.keysAt(kAreaShapeZoom).first, [_box]), isFalse);
    expect(insideRegions(inside, const []), isFalse);
  });

  test('die Hervorhebung: die Region ist EIN Loch, ein Bereich darin kein zweites', () {
    const view = MapViewBounds(south: 46.0, west: 9.0, north: 49.5, east: 13.5);
    final c = offlineCoverage([_area('r', _region), _area('a', _inner)], view);
    expect(c.mask!.holes, hasLength(1), reason: 'zwei Löcher übereinander füllten sich wieder');
    final hole = c.mask!.holes.single;
    final south = hole.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    final north = hole.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    expect(south, lessThanOrEqualTo(_box.south));
    expect(north, greaterThanOrEqualTo(_box.north));
    expect(north - _box.north, lessThan(0.05), reason: 'auf das Kachelraster gerastet, nicht größer');
    // Ein Ausschnitt ganz in der Region: ein Loch über alles, kein Zerfall in Kacheln.
    const inside = MapViewBounds(south: 47.5, west: 11.0, north: 47.6, east: 11.1);
    expect(offlineCoverage([_area('r', _region)], inside).mask!.holes, hasLength(1));
    expect(const LatLng(47.55, 11.05), isNotNull);
  });

  group('Orte-Bündel', () {
    const files = {
      '476_74.water.json': '{"format":1,"pois":[]}\n',
      '-12_-940.food.json': '{"format":1,"pois":[{"id":"n1"}]}\n',
    };

    test('liefert jede Zellendatei Byte für Byte, mit Zeilenende', () async {
      final b = _bundle('20261009', files);
      final got = {await for (final (n, t) in readPoiBundle(b.bytes, b.meta, '20261009')) n: t};
      expect(got, files);
    });

    test('Länge, Prüfsumme, Bau und Zahl müssen stimmen', () async {
      final b = _bundle('20261009', files);
      Future<void> fails(Uint8List bytes, PoiBundle meta, String build) =>
          expectLater(readPoiBundle(bytes, meta, build).toList(), throwsA(isA<PoiBundleMismatch>()));
      await fails(Uint8List.fromList([...b.bytes, 0]), b.meta, '20261009');
      final flipped = Uint8List.fromList(b.bytes)..[20] ^= 1;
      await fails(flipped, b.meta, '20261009');
      await fails(b.bytes, b.meta, '20261001');
      final short = _bundle('20261009', files, claim: 3);
      await fails(short.bytes, short.meta, '20261009');
    });

    test('ein fremder Dateiname wird nie ein Pfad', () async {
      final b = _bundle('20261009', {'../x.water.json': '{}\n'});
      await expectLater(readPoiBundle(b.bytes, b.meta, '20261009').toList(), throwsA(isA<PoiBundleMismatch>()));
    });

    test('das Manifest liest das Bündel, ein kaputtes Feld heißt: keins', () {
      final base = {'format': 1, 'build': '20261009', 'prefix': 'pois-20261009', 'cells': <String, Object>{}};
      final ok = PoiManifest.fromJson({
        ...base,
        'bundle': {'file': 'bundle.tsv.gz', 'files': 2, 'bytes': 10, 'raw_bytes': 20, 'sha256': 'a' * 64},
      });
      expect(ok.bundle?.files, 2);
      expect(PoiManifest.fromJson({...base, 'bundle': {'file': '../x.gz', 'files': 2, 'bytes': 1, 'sha256': 'a' * 64}}).bundle,
          isNull);
      expect(PoiManifest.fromJson(base).bundle, isNull);
    });
  });
}
