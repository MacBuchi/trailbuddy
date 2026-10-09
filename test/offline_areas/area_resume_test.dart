// Ein abgerissener Download macht von selbst weiter (0.108.2): Am Gerät
// brach „DACH ganz speichern" bei jedem Funkloch ab, bis jemand
// „Fortsetzen" tippte. Jetzt wartet er auf das Netz, plant neu (nur, was
// fehlt) und schreibt in DENSELBEN Bereich — über Mobilfunk nur, wenn er
// dort auch angefangen hat. Dazu: Die ganze Region misst unter dem
// Service, und ein Block, der steht, ohne zu reißen, zählt nach einer
// Frist als Funkloch.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/core/connectivity.dart';
import 'package:trailbuddy/core/settings.dart';
import 'package:trailbuddy/features/keep_alive/keep_alive.dart';
import 'package:trailbuddy/features/map/map_regions.dart';
import 'package:trailbuddy/features/map/online_map.dart';
import 'package:trailbuddy/features/offline_areas/area_downloader.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_providers.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';
import 'package:trailbuddy/features/offline_areas/region_overview.dart';
import 'package:trailbuddy/features/offline_areas/tile_store.dart';

import '../fakes/fake_keep_alive.dart';
import '../fakes/fake_settings.dart';

const _index = {
  'format': 1,
  'regions': [
    {
      'id': 'dach',
      'name': 'DACH',
      'bbox': [5.5, 45.5, 17.5, 55.5],
      'dir': '',
      'map': 'dach.json',
      'heights': 'heights.json',
      'ways': 'ways.json',
      'pois': 'pois.json',
      'overview': null,
    },
  ],
};

const _dachMap = MapManifest(file: 'dach-20261001.pmtiles', maxZoom: 13, bytes: 1, sourceBuild: '20261001');
const _box = AreaBounds(south: 47.60, west: 11.20, north: 48.20, east: 11.90);
const _whole = RegionShape(region: 'dach', bounds: _box);

final Uint8List _source = writePmTiles(
  tiles: [
    for (final t in tilesCovering(_box, maxZoom: 13))
      TileToWrite(t.z, t.x, t.y, Uint8List.fromList(utf8.encode('tile ${t.z}/${t.x}/${t.y} ${'x' * 40}'))),
  ],
  tileCompression: Compression.none,
  bounds: TileBounds(west: _box.west, south: _box.south, east: _box.east, north: _box.north),
);

/// Liest aus [_source]; [failures] Lesevorgänge im Datenteil (Offset > 0)
/// scheitern mit [error], danach geht alles. Geteilt über alle Archive,
/// die der Opener öffnet — wie ein Netz, das einmal reißt.
class _Flaky implements ReadAt {
  _Flaky(this.net);
  final _Net net;

  @override
  Future<http.ByteStream> readAt(int offset, int length) async {
    if (offset > 0 && net.failures > 0) {
      net.failures--;
      throw net.error;
    }
    return http.ByteStream.fromBytes(_slice(offset, length));
  }

  @override
  Future<void> close() async {}
}

Uint8List _slice(int offset, int length) =>
    Uint8List.sublistView(_source, offset, offset + length > _source.length ? _source.length : offset + length);

class _Net {
  int failures = 0;
  Object error = const SocketException('Verbindung abgerissen');
  int opened = 0;
  bool offline = false;
  bool mobile = false;
  final waits = <int>[];

  /// Was beim Warten passiert — die Welt draußen.
  void Function(int attempt)? onWait;
}

final _offline = StateProvider<bool>((ref) => false);
final _mobile = StateProvider<bool>((ref) => false);

void main() {
  late _Net net;
  late MemoryAreaStore store;
  late FakeKeepAlive keepAlive;

  ProviderContainer make() {
    net = _Net();
    store = MemoryAreaStore();
    keepAlive = FakeKeepAlive();
    late ProviderContainer c;
    c = ProviderContainer(overrides: [
      noConnectivityProvider.overrideWith((ref) => ref.watch(_offline)),
      onMobileDataProvider.overrideWith((ref) => ref.watch(_mobile)),
      regionsLoaderProvider.overrideWithValue(() async => jsonEncode(_index)),
      mapManifestLoaderProvider.overrideWithValue(() async => _dachMap),
      regionManifestLoaderProvider.overrideWithValue((uri) async => null),
      overviewFetcherProvider.overrideWithValue((_, {onProgress, check}) async => null),
      poiBundleFetcherProvider.overrideWithValue((_, {onProgress, check}) async => null),
      areaPoiManifestLoaderProvider.overrideWithValue(() async => null),
      areaHeightsManifestLoaderProvider.overrideWithValue(() async => null),
      areaWaysManifestLoaderProvider.overrideWithValue(() async => null),
      areaSourceOpenerProvider.overrideWithValue((uri) {
        net.opened++;
        // ignore: invalid_use_of_visible_for_testing_member
        return PmTilesArchive.fromReadAt(_Flaky(net));
      }),
      areaStoreProvider.overrideWithValue(store),
      tileStoreProvider.overrideWithValue(MemoryTileStore()),
      keepAliveProvider.overrideWithValue(keepAlive),
      settingsProvider.overrideWithValue(FakeSettings()),
      areaResumeDelayProvider.overrideWithValue((attempt) async {
        net.waits.add(attempt);
        net.onWait?.call(attempt);
        c.read(_offline.notifier).state = net.offline;
        c.read(_mobile.notifier).state = net.mobile;
      }),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('ein Abriss: wartet, plant neu und schreibt in denselben Bereich', () async {
    final c = make();
    final notifier = c.read(areaDownloadProvider.notifier);
    final plan = await notifier.plan(_whole);
    final fractions = <double>[];
    var sawWaiting = false;
    c.listen(areaDownloadProvider, (_, s) {
      if (s.waiting) sawWaiting = true;
      final f = s.progress?.fraction;
      if (f != null && s.progress!.phase == AreaPhase.tiles) fractions.add(f);
    });
    net.failures = 1;
    final area = await notifier.start(plan, name: 'DACH komplett');
    expect(area, isNotNull);
    expect(area!.complete, isTrue);
    expect(net.waits, [0], reason: 'genau ein Warten');
    expect(sawWaiting, isTrue);
    expect(keepAlive.texts, contains('DACH komplett — wartet auf Empfang'));
    expect(await store.list(), hasLength(1), reason: 'kein zweiter Bereich');
    expect(c.read(areaDownloadProvider).phase, AreaDownloadPhase.done);
    expect(keepAlive.running, isFalse);
    expect(fractions.last, 1);
  });

  test('nach dem Wiederaufnehmen fällt der Anteil nicht auf null zurück', () async {
    final c = make();
    final notifier = c.read(areaDownloadProvider.notifier);
    // Ein Ausschnitt: 256 Kacheln je Block (die ganze Region nähme 2048).
    final plan = await notifier.plan(const RectShape(_box));
    expect(plan.tiles.length, greaterThan(256), reason: 'mehr als ein Block, sonst gibt es kein „schon geladen"');
    // Der erste Block geht durch, der zweite reißt.
    var armed = false;
    final fractions = <double>[];
    c.listen(areaDownloadProvider, (_, s) {
      final p = s.progress;
      if (p == null || p.phase != AreaPhase.tiles) return;
      fractions.add(p.fraction);
      if (p.done > 0 && !armed) {
        armed = true;
        net.failures = 1;
      }
    });
    final area = await notifier.start(plan, name: 'R');
    expect(area?.complete, isTrue);
    expect(net.waits, [0]);
    final afterFirst = fractions.firstWhere((f) => f > 0);
    final resumedAt = fractions.indexWhere((f) => f < afterFirst, fractions.indexOf(afterFirst));
    expect(resumedAt, -1, reason: 'kein Rückfall unter den schon geladenen Anteil: $fractions');
  });

  test('die Geduld gilt je Funkloch: wer vorankommt, darf wieder warten', () async {
    final c = make();
    final notifier = c.read(areaDownloadProvider.notifier);
    final plan = await notifier.plan(const RectShape(_box));
    // Erstes Funkloch fast bis zur Grenze, dann ein Block, dann ein zweites.
    net.failures = 1;
    var second = false;
    var secondWaits = 0;
    net.onWait = (attempt) {
      if (!second) {
        net.offline = net.waits.length < kAreaResumeAttempts - 1;
      } else {
        net.offline = secondWaits++ < 2;
      }
    };
    var resumed = false;
    c.listen(areaDownloadProvider, (_, s) {
      final p = s.progress;
      if (s.waiting) resumed = true;
      if (resumed && !second && p != null && p.phase == AreaPhase.tiles && p.done > 0 && !s.waiting) {
        second = true;
        net.failures = 1;
      }
    });
    final area = await notifier.start(plan, name: 'R');
    expect(second, isTrue, reason: 'das zweite Funkloch kam');
    expect(area?.complete, isTrue, reason: 'nach dem Block beginnt die Geduld von vorn');
    expect(net.waits.length, greaterThan(kAreaResumeAttempts));
  });

  test('ohne Empfang wird nicht neu geplant, mit Empfang sofort', () async {
    final c = make();
    final notifier = c.read(areaDownloadProvider.notifier);
    final plan = await notifier.plan(_whole);
    net.failures = 1;
    net.onWait = (attempt) => net.offline = attempt < 3;
    final openedBefore = net.opened;
    final area = await notifier.start(plan, name: 'R');
    expect(area?.complete, isTrue);
    expect(net.waits, [0, 1, 2, 3]);
    expect(net.opened - openedBefore, 3, reason: 'Versuch, neuer Plan, zweiter Versuch — im Funkloch nichts');
  });

  test('im WLAN begonnen, geht es nicht über Mobilfunk weiter — nach der Frist aufgeben', () async {
    final c = make();
    final notifier = c.read(areaDownloadProvider.notifier);
    final plan = await notifier.plan(_whole);
    net.failures = 1;
    net.mobile = true;
    final area = await notifier.start(plan, name: 'R');
    expect(area, isNull);
    expect(net.waits, hasLength(kAreaResumeAttempts));
    final state = c.read(areaDownloadProvider);
    expect(state.phase, AreaDownloadPhase.failed);
    expect(state.error, contains('„Fortsetzen"'));
    expect((await store.list()).single.complete, isFalse, reason: 'was liegt, bleibt');
    expect(keepAlive.running, isFalse);
  });

  test('über Mobilfunk begonnen, darf es dort weitergehen', () async {
    final c = make();
    c.read(_mobile.notifier).state = true;
    net.mobile = true;
    final notifier = c.read(areaDownloadProvider.notifier);
    final plan = await notifier.plan(_whole);
    net.failures = 1;
    final area = await notifier.start(plan, name: 'R');
    expect(area?.complete, isTrue);
    expect(net.waits, [0]);
  });

  test('Abbrechen während des Wartens beendet ihn, der Bereich bleibt unvollständig', () async {
    final c = make();
    final notifier = c.read(areaDownloadProvider.notifier);
    final plan = await notifier.plan(_whole);
    net.failures = 1;
    net.onWait = (_) => notifier.cancel();
    final area = await notifier.start(plan, name: 'R');
    expect(area, isNull);
    expect(c.read(areaDownloadProvider).phase, AreaDownloadPhase.idle);
    expect((await store.list()).single.complete, isFalse);
    expect(keepAlive.running, isFalse);
  });

  test('ein Fehler, der kein Funkloch ist, beendet ihn sofort', () async {
    final c = make();
    final notifier = c.read(areaDownloadProvider.notifier);
    final plan = await notifier.plan(_whole);
    net.failures = 1;
    net.error = const FormatException('kaputt');
    final area = await notifier.start(plan, name: 'R');
    expect(area, isNull);
    expect(net.waits, isEmpty);
    expect(c.read(areaDownloadProvider).phase, AreaDownloadPhase.failed);
  });

  test('die ganze Region misst unter dem Service, ein Ausschnitt nicht', () async {
    final c = make();
    final notifier = c.read(areaDownloadProvider.notifier);
    await notifier.plan(const RectShape(_box));
    expect(keepAlive.starts, 0);
    await notifier.plan(_whole);
    expect(keepAlive.starts, 1);
    expect(keepAlive.titles.last, 'Region wird gemessen');
    expect(keepAlive.running, isFalse, reason: 'nach dem Messen wieder aus');
  });

  test('ein Block, der steht, ohne zu reißen, zählt nach der Frist als Funkloch', () async {
    // ignore: invalid_use_of_visible_for_testing_member
    final source = await PmTilesArchive.fromReadAt(_Hanging());
    final downloader = AreaDownloader(
      archive: source,
      manifest: _dachMap,
      store: MemoryAreaStore(),
      tiles: MemoryTileStore(),
      fetchPoiFile: (_) async => null,
      stallTimeout: const Duration(milliseconds: 50),
    );
    final plan = await downloader.plan(const RectShape(_box));
    await expectLater(downloader.download(plan, name: 'R'), throwsA(isA<TimeoutException>()));
  });
}

/// Header und Verzeichnis kommen, der Datenteil nie.
class _Hanging implements ReadAt {
  @override
  Future<http.ByteStream> readAt(int offset, int length) async {
    if (offset == 0) return http.ByteStream.fromBytes(_slice(0, length));
    return http.ByteStream(StreamController<List<int>>().stream);
  }

  @override
  Future<void> close() async {}
}
