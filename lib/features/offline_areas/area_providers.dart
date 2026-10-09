// Die gespeicherten Bereiche in der App (Konzept 3.2): die Liste, der
// laufende Download (mit Fortschritt, Abbruch und dem Vordergrunddienst
// über den KeepAlive-Koordinator), und die geöffneten Archive für die
// Karte — für flutter_map als Kachelquellen, für MapLibre als Pfade.
//
// Die Bereiche liegen IMMER auf der Karte, zuoberst (#82) — in beiden
// Engines, mit und ohne Empfang. Bis 0.36.x waren sie nur die Karte,
// wenn kein Empfang bestand oder es kein Manifest gab, und dann UNTER
// der Online-Karte. Im Wald heißt das meist „schwacher Empfang": Das
// Telefon meldet ein Netz, die Online-Kacheln kommen nie, und die
// gespeicherten wurden gar nicht erst gefragt. Die Leiste „Ebenen" zeigte
// sie trotzdem als gespeichert.
//
// Das ist der lokale Vorrang aus Konzept 3.2, ohne Kachel-Lieferanten:
// Jede Kachel eines Bereichs trägt die deckende `earth`-Fläche des Stils
// und verdeckt die Online-Karte darunter vollständig; wo der Bereich keine
// Kachel hat, liefert sein Archiv nichts, und die Online-Karte scheint
// durch. Doppelt gezeichnet wird also nichts Sichtbares, nur die Online-
// Kachel unter dem Bereich umsonst geladen.
//
// Die Wege der Bereiche (#212, seit 0.90.0) liegen genauso IMMER über der
// Wege-Ebene vom Host: Ihre Bänder decken die Online-Striche darunter, wo
// derselbe Weg liegt — dieselbe Regel wie bei der Karte. Die Wege-Ebene
// selbst hat keine deckende Fläche; wo kein Bereich ist, scheint die
// Online-Ebene durch.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pmtiles/pmtiles.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../../core/connectivity.dart';
import '../../core/errors.dart';
import '../keep_alive/keep_alive.dart';
import '../../core/line_geometry.dart';
import '../map/base_map_providers.dart';
import '../map/map_regions.dart';
import '../map/online_map.dart';
import '../map/pmtiles_tile_provider.dart';
import '../map/poi.dart';
import '../map/poi_source.dart';
import '../map/way_layer.dart';
import 'area_downloader.dart';
import 'area_plan.dart';
import 'area_store.dart';
import 'area_trim.dart';
import 'height_tiles.dart';
import 'region_overview.dart';

/// Die Liste aus dem Index, in Speicherreihenfolge.
class StoredAreasNotifier extends AsyncNotifier<List<StoredArea>> {
  @override
  Future<List<StoredArea>> build() => ref.watch(areaStoreProvider).list();

  Future<void> refresh() async {
    state = AsyncData(await ref.read(areaStoreProvider).list());
    ref.invalidate(storedOverviewsProvider);
  }

  /// Löscht den Bereich — und mit dem letzten seiner Region deren
  /// Übersicht (#220 Schritt 4): Sie kam mit ihm, sie geht mit ihm.
  Future<void> delete(String id) async {
    await ref.read(areaStoreProvider).delete(id);
    await _dropOrphanOverviews();
    await refresh();
  }

  /// Nimmt die Übersicht einer Region von Hand weg; die Bereiche bleiben.
  /// Der nächste Bereich dort holt sie wieder.
  Future<void> deleteOverview(String region) async {
    await ref.read(areaStoreProvider).deleteOverview(region);
    await refresh();
  }

  Future<void> _dropOrphanOverviews() async {
    final store = ref.read(areaStoreProvider);
    final regions = {for (final a in await store.list()) a.region};
    for (final o in await store.overviews()) {
      if (!regions.contains(o.region)) await store.deleteOverview(o.region);
    }
  }

  /// Was das Entfernen von [removes] (Kacheln bei Zoom 13) aus den
  /// gespeicherten Bereichen macht — lokal gemessen, ohne Netz.
  Future<TrimPlan> planTrim(Set<int> removes) async =>
      AreaTrimmer(ref.read(areaStoreProvider)).plan(await future, removes);

  Future<void> applyTrim(TrimPlan plan) async {
    await AreaTrimmer(ref.read(areaStoreProvider)).apply(plan);
    // Der Radierer kann den letzten Bereich einer Region leeren.
    await _dropOrphanOverviews();
    await refresh();
  }
}

final storedAreasProvider =
    AsyncNotifierProvider<StoredAreasNotifier, List<StoredArea>>(StoredAreasNotifier.new);

/// Die gespeicherten Übersichten der Regionen (#220 Schritt 4).
final storedOverviewsProvider =
    FutureProvider<List<StoredOverview>>((ref) => ref.watch(areaStoreProvider).overviews());

/// Die Übersicht einer Region auf dem Host, für „Meine Bereiche" (Angebot,
/// wenn sie fehlt oder ein neuerer Bau da ist). Null für DACH (im Binary),
/// ohne Empfang und wenn der Index keine nennt.
final regionOverviewAvailableProvider = FutureProvider.family<OverviewManifest?, MapRegion>((ref, region) async {
  if (region.isDach || ref.watch(noConnectivityProvider)) return null;
  return RegionManifests(ref.watch(regionManifestLoaderProvider), region).overview();
});

/// Ob ein Bereich der Region [region] die Übersicht [available] mitbringen
/// soll: wenn sie nicht liegt oder älter ist. Eine Regel für Plan und
/// „Meine Bereiche".
bool overviewWanted(List<StoredOverview> stored, String region, OverviewManifest? available) {
  if (available == null) return false;
  final have = stored.where((o) => o.region == region).firstOrNull;
  return have == null || have.build.compareTo(available.sourceBuild) < 0;
}

/// Die Übersichten mit Pfad — für MapLibre (`file://`). Leer im Browser.
final areaOverviewPathsProvider = FutureProvider<List<({StoredOverview overview, String path})>>((ref) async {
  final overviews = await ref.watch(storedOverviewsProvider.future);
  final store = ref.watch(areaStoreProvider);
  return [
    for (final o in overviews)
      if (await store.overviewPath(o.region) case final path?) (overview: o, path: path),
  ];
});

/// Öffnet die Übersicht einer Region für die flutter_map-Engine — die
/// Naht für Tests.
final areaOverviewOpenerProvider =
    Provider<Future<PmTilesVectorTileProvider?> Function(AreaStore store, StoredOverview overview)>(
        (ref) => _openOverview);

Future<PmTilesVectorTileProvider?> _openOverview(AreaStore store, StoredOverview overview) async {
  final path = await store.overviewPath(overview.region);
  if (path != null) return PmTilesVectorTileProvider.open(path);
  final bytes = await store.readOverview(overview.region);
  if (bytes == null) return null;
  return PmTilesVectorTileProvider.openBytes(bytes);
}

/// Die Übersichten der Regionen als Schicht der flutter_map-Engine, über
/// der DACH-Übersicht und unter allem anderen — dieselbe Regel wie dort:
/// gezeigt nur, solange die Übersicht gebraucht wird. Thema OHNE
/// `background`, sonst deckte sie die DACH-Übersicht zu. Null ohne
/// gespeicherte.
final areaOverviewStyleProvider = FutureProvider<BaseMapStyle?>((ref) async {
  final overviews = await ref.watch(storedOverviewsProvider.future);
  if (overviews.isEmpty) return null;
  final store = ref.watch(areaStoreProvider);
  final open = ref.watch(areaOverviewOpenerProvider);
  final opened = <OpenedAreaArchive>[];
  for (final o in overviews) {
    try {
      final provider = await open(store, o);
      if (provider != null) opened.add((minZoom: 0, maxZoom: o.maxZoom, provider: provider));
    } catch (e, s) {
      logError('Übersicht einer Region öffnen', e, s);
    }
  }
  if (opened.isEmpty) return null;
  final multi = MultiAreaTileProvider(opened);
  ref.onDispose(multi.close);
  final theme = await ref.watch(baseThemeWithoutBackgroundProvider.future);
  return BaseMapStyle(theme: theme, tileProviders: TileProviders({'protomaps': multi}));
});

/// Öffnet das Archiv des Hosts für den Download — die Naht für Tests.
final areaSourceOpenerProvider =
    Provider<Future<PmTilesArchive> Function(Uri)>((ref) => PmTilesArchive.fromUri);

/// Das Orte-Manifest für den Download — null, wenn keins da ist (dann
/// kommt der Bereich ohne Orte). Die Naht für Tests.
final areaPoiManifestLoaderProvider = Provider<Future<PoiManifest?> Function()>((ref) => () async {
      try {
        return await fetchPoiManifest(http.Client());
      } catch (_) {
        return null;
      }
    });

/// Holt eine Orte-Datei des Hosts für einen Bereich.
final areaPoiFileLoaderProvider =
    Provider<Future<String?> Function(PoiManifest manifest, String name)>(
        (ref) => (manifest, name) => fetchPoiFileFromHost(http.Client(), manifest, name));

/// Das Höhen-Manifest für den Download — null, wenn keins da ist (dann
/// kommt der Bereich ohne Höhen). Die Naht für Tests; der Harness setzt
/// sie auf null.
final areaHeightsManifestLoaderProvider =
    Provider<Future<HeightsManifest?> Function()>((ref) => () async {
          try {
            return await fetchHeightsManifest();
          } catch (_) {
            // Kein Bau, kein Netz, fremdes Format: ohne Höhen weiter.
            return null;
          }
        });

/// Das Wege-Manifest für den Download — unabhängig vom Schalter der
/// Ebene (Betreiber, 2026-10-08: ein Bereich holt die Wege immer). Null,
/// wenn keins da ist; die Naht für Tests, der Harness setzt sie auf null.
final areaWaysManifestLoaderProvider =
    Provider<Future<WaysManifest?> Function()>((ref) => () async {
          try {
            return await fetchWaysManifest();
          } catch (_) {
            // Kein Bau, kein Netz, fremdes Format: ohne Wege weiter.
            return null;
          }
        });

/// Ob der Host Wege hat, für „Meine Bereiche" (Knopf „Aktualisieren"
/// an Bereichen, die noch keine geholt haben) — je Region (#220). Ohne
/// Empfang keine Frage.
final areaWaysAvailableProvider = FutureProvider.family<WaysManifest?, MapRegion>((ref, region) async {
  if (ref.watch(noConnectivityProvider)) return null;
  if (region.isDach) return ref.watch(areaWaysManifestLoaderProvider)();
  return RegionManifests(ref.watch(regionManifestLoaderProvider), region).ways();
});

/// Die Manifeste, gegen die ein Bereich der Region [region] gemessen und
/// geladen wird (#220): für DACH die bisherigen Nähte, sonst die Dateien
/// im Ordner der Region. Jede Begleitebene darf fehlen — dann kommt der
/// Bereich ohne sie.
typedef AreaHostManifests = ({
  MapManifest? map,
  PoiManifest? pois,
  HeightsManifest? heights,
  WaysManifest? ways,
  OverviewManifest? overview,
});

Future<AreaHostManifests> _hostManifests(Ref ref, MapRegion region) async {
  final map = await ref.read(regionMapManifestProvider(region).future);
  if (region.isDach) {
    return (
      map: map,
      pois: await ref.read(areaPoiManifestLoaderProvider)(),
      heights: await ref.read(areaHeightsManifestLoaderProvider)(),
      ways: await ref.read(areaWaysManifestLoaderProvider)(),
      // Die DACH-Übersicht liegt im Binary.
      overview: null,
    );
  }
  final manifests = RegionManifests(ref.read(regionManifestLoaderProvider), region);
  final overview = await manifests.overview();
  return (
    map: map,
    pois: await manifests.pois(),
    heights: await manifests.heights(),
    ways: await manifests.ways(),
    // Nur, wenn sie noch nicht (oder älter) auf dem Gerät liegt.
    overview: overviewWanted(await ref.read(areaStoreProvider).overviews(), region.id, overview) ? overview : null,
  );
}

/// Eine Form außerhalb aller Regionen des Hosts (#220): Dort gibt es
/// nichts zu speichern. Die Oberfläche sagt es in einem Satz.
class OutsideRegions implements Exception {
  const OutsideRegions(this.names);

  /// Die Regionen, die es gibt, für den Satz.
  final List<String> names;

  String get message => 'Hier gibt es keine Karte zum Speichern — Karten gibt es für ${names.join(', ')}.';

  @override
  String toString() => message;
}

/// Höhen aus den gespeicherten Bereichen — der erste Bereich, der die
/// Kachel hat, liefert. Beobachten öffnet die Archive (nur Verzeichnisse,
/// Kacheln kommen beim Lesen); wer nichts rechnet, beobachtet nicht.
final areaHeightReaderProvider = FutureProvider<HeightReader>((ref) async {
  final areas = await ref.watch(storedAreasProvider.future);
  final store = ref.watch(areaStoreProvider);
  final sources = <HeightTileSource>[];
  for (final area in areas) {
    if (!area.hasHeights) continue;
    final path = await store.heightsPath(area.id);
    if (path != null) {
      sources.add(ArchiveHeightSource(await PmTilesArchive.from(path)));
      continue;
    }
    final bytes = await store.readHeights(area.id);
    if (bytes != null) sources.add(ArchiveHeightSource(await PmTilesArchive.fromBytes(bytes)));
  }
  final reader = HeightReader(sources);
  ref.onDispose(reader.close);
  return reader;
});

enum AreaDownloadPhase { idle, planning, running, done, failed }

/// Der Zustand des einen laufenden Downloads (es gibt höchstens einen).
@immutable
class AreaDownloadState {
  const AreaDownloadState({
    this.phase = AreaDownloadPhase.idle,
    this.name,
    this.plan,
    this.progress,
    this.result,
    this.error,
  });

  final AreaDownloadPhase phase;
  final String? name;
  final AreaPlan? plan;
  final AreaProgress? progress;
  final StoredArea? result;
  final String? error;

  bool get busy => phase == AreaDownloadPhase.planning || phase == AreaDownloadPhase.running;
}

class AreaDownloadNotifier extends Notifier<AreaDownloadState> {
  static const _keepAliveKey = 'area';
  bool _cancelled = false;

  @override
  AreaDownloadState build() => const AreaDownloadState();

  /// Der Plan für [shape]: wirft [AreaTooLarge], liefert Kacheln, Bytes
  /// und — seit 0.27.0 — die Orte samt Anzahl (der Dialog vor dem
  /// Speichern nennt sie; der Download holt sie dann nicht noch einmal).
  /// Braucht das Manifest — ohne Empfang gibt es keinen Plan.
  Future<AreaPlan> plan(AreaShape shape) async {
    // Ohne Empfang kennt die App vielleicht nur DACH — „hier gibt es keine
    // Karte" wäre dann eine falsche Auskunft über Kanada.
    if (ref.read(noConnectivityProvider)) throw StateError('Kein Kartenhost erreichbar');
    final regions = await ref.read(mapRegionsProvider.future);
    final hull = shape.hull;
    // Die Region nach der Lage (#220): die erste, deren Rahmen die Form
    // schneidet. Regionen überlappen nie, und ein Bereich ist klein.
    final region = regionFor(regions, LatBox(hull.south, hull.west, hull.north, hull.east));
    if (region == null) throw OutsideRegions([for (final r in regions) r.name]);
    final hosts = await _hostManifests(ref, region);
    final manifest = hosts.map;
    if (manifest == null) throw StateError('Kein Kartenhost erreichbar');
    state = const AreaDownloadState(phase: AreaDownloadPhase.planning);
    final archive = await ref.read(areaSourceOpenerProvider)(manifest.archiveUri);
    PmTilesArchive? heights;
    PmTilesArchive? ways;
    try {
      final poiManifest = hosts.pois;
      final fetchPoi = ref.read(areaPoiFileLoaderProvider);
      final heightsManifest = hosts.heights;
      heights = await _openSide(heightsManifest?.archiveUri, 'Höhenarchiv öffnen');
      final waysManifest = hosts.ways;
      ways = await _openSide(waysManifest?.archiveUri, 'Wege-Archiv öffnen');
      final downloader = AreaDownloader(
          archive: archive,
          manifest: manifest,
          store: ref.read(areaStoreProvider),
          poiManifest: poiManifest,
          fetchPoiFile: (fileName) =>
              poiManifest == null ? Future.value(null) : fetchPoi(poiManifest, fileName),
          heights: heights,
          heightsManifest: heightsManifest,
          ways: ways,
          waysManifest: waysManifest,
          region: region.id,
          overview: hosts.overview,
          fetchOverview: ref.read(overviewFetcherProvider));
      final plan = await downloader.plan(shape, withPois: true);
      state = AreaDownloadState(phase: AreaDownloadPhase.idle, plan: plan);
      return plan;
    } catch (e) {
      state = const AreaDownloadState();
      rethrow;
    } finally {
      await archive.close();
      await heights?.close();
      await ways?.close();
    }
  }

  /// Ein Begleitarchiv des Hosts (Höhen, Wege) — null ohne Manifest, und
  /// null, wenn es nicht aufgeht: Ein Bereich ohne Höhen oder Wege ist
  /// besser als keiner.
  Future<PmTilesArchive?> _openSide(Uri? uri, String what) async {
    if (uri == null) return null;
    try {
      return await ref.read(areaSourceOpenerProvider)(uri);
    } catch (e, s) {
      if (!looksOffline(e)) logError(what, e, s);
      return null;
    }
  }

  /// Holt und speichert. Läuft im Main-Isolate; der Koordinator hält
  /// den Prozess auf Android wach. Ein Fehler landet im Zustand (die
  /// Oberfläche zeigt ihn), nie beim Aufrufer.
  Future<StoredArea?> start(AreaPlan plan, {required String name, String? id}) async {
    if (state.busy) return null;
    _cancelled = false;
    final regions = await ref.read(mapRegionsProvider.future);
    final region = regions.where((r) => r.id == plan.region).firstOrNull;
    final hosts = region == null ? null : await _hostManifests(ref, region);
    final manifest = hosts?.map;
    if (manifest == null) {
      state = AreaDownloadState(phase: AreaDownloadPhase.failed, error: 'Kein Kartenhost erreichbar', plan: plan);
      return null;
    }
    state = AreaDownloadState(phase: AreaDownloadPhase.running, name: name, plan: plan);
    final coordinator = ref.read(keepAliveCoordinatorProvider);
    await coordinator.start(_keepAliveKey, '$name — 0 %', title: 'Bereich wird gespeichert');
    PmTilesArchive? archive;
    PmTilesArchive? heights;
    PmTilesArchive? ways;
    try {
      archive = await ref.read(areaSourceOpenerProvider)(manifest.archiveUri);
      final poiManifest = hosts!.pois;
      final fetchPoi = ref.read(areaPoiFileLoaderProvider);
      final heightsManifest = hosts.heights;
      heights = plan.hasHeights ? await _openSide(heightsManifest?.archiveUri, 'Höhenarchiv öffnen') : null;
      final waysManifest = hosts.ways;
      // Gegen den Bau, mit dem gemessen wurde: Ein neuerer Bau hätte
      // andere Kacheln, als der Plan nennt.
      ways = plan.hasWays && waysManifest?.build == plan.waysBuild
          ? await _openSide(waysManifest?.archiveUri, 'Wege-Archiv öffnen')
          : null;
      final downloader = AreaDownloader(
        archive: archive,
        manifest: manifest,
        store: ref.read(areaStoreProvider),
        poiManifest: poiManifest,
        fetchPoiFile: (fileName) => poiManifest == null ? Future.value(null) : fetchPoi(poiManifest, fileName),
        heights: heights,
        heightsManifest: heightsManifest,
        ways: ways,
        waysManifest: waysManifest,
        region: plan.region,
        // Die Übersicht, die gemessen wurde — Dateien mit Datum ändern sich nicht.
        overview: plan.overview,
        fetchOverview: ref.read(overviewFetcherProvider),
      );
      final area = await downloader.download(
        plan,
        name: name,
        id: id,
        isCancelled: () => _cancelled,
        onProgress: (p) {
          state = AreaDownloadState(phase: AreaDownloadPhase.running, name: name, plan: plan, progress: p);
          final percent = (p.fraction * 100).round();
          final text = switch (p.phase) {
            AreaPhase.tiles => '$name — $percent %',
            AreaPhase.pois => '$name — Orte',
            AreaPhase.heights => '$name — Höhen',
            AreaPhase.ways => '$name — Wege',
            AreaPhase.overview => '$name — Übersicht',
            AreaPhase.writing => '$name — wird geschrieben',
          };
          unawaited(coordinator.update(_keepAliveKey, text));
        },
      );
      await ref.read(storedAreasProvider.notifier).refresh();
      state = AreaDownloadState(phase: AreaDownloadPhase.done, name: name, plan: plan, result: area);
      return area;
    } on AreaCancelled {
      state = const AreaDownloadState();
      return null;
    } catch (e, s) {
      if (!looksOffline(e)) logError('Bereich speichern', e, s);
      state = AreaDownloadState(
          phase: AreaDownloadPhase.failed,
          name: name,
          plan: plan,
          error: looksOffline(e)
              ? 'Die Verbindung ist abgerissen. Nichts gespeichert — noch einmal versuchen, sobald Empfang da ist.'
              : 'Der Bereich ließ sich nicht speichern.');
      return null;
    } finally {
      await archive?.close();
      await heights?.close();
      await ways?.close();
      await coordinator.stop(_keepAliveKey);
    }
  }

  /// Nur die Übersicht einer Region holen (#220 Schritt 4) — aus „Meine
  /// Bereiche", wenn sie fehlt (von Hand gelöscht, beim Speichern nicht
  /// gekommen) oder ein neuerer Bau da ist, ohne einen Bereich neu zu
  /// laden. Ein Fehler landet im Zustand, wie beim Bereich.
  Future<bool> fetchOverview(MapRegion region) async {
    if (state.busy || region.isDach) return false;
    _cancelled = false;
    final name = 'Übersicht ${region.name}';
    final manifest = ref.read(noConnectivityProvider)
        ? null
        : await RegionManifests(ref.read(regionManifestLoaderProvider), region).overview();
    if (manifest == null) {
      state = const AreaDownloadState(phase: AreaDownloadPhase.failed, error: 'Kein Kartenhost erreichbar');
      return false;
    }
    state = AreaDownloadState(phase: AreaDownloadPhase.running, name: name);
    final coordinator = ref.read(keepAliveCoordinatorProvider);
    await coordinator.start(_keepAliveKey, '$name — 0 %', title: 'Übersicht wird gespeichert');
    try {
      final bytes = await ref.read(overviewFetcherProvider)(
        manifest.archiveUri,
        check: () {
          if (_cancelled) throw const AreaCancelled();
        },
        onProgress: (done, total) {
          final p = AreaProgress(phase: AreaPhase.overview, done: done, total: total > 0 ? total : manifest.bytes);
          state = AreaDownloadState(phase: AreaDownloadPhase.running, name: name, progress: p);
          unawaited(coordinator.update(_keepAliveKey, '$name — ${(p.fraction * 100).round()} %'));
        },
      );
      if (bytes == null) throw const OverviewMismatch('nicht auf dem Host');
      await checkOverview(manifest, bytes);
      await ref.read(areaStoreProvider).putOverview(
          StoredOverview(
            region: region.id,
            build: manifest.sourceBuild,
            bytes: bytes.length,
            maxZoom: manifest.maxZoom,
            savedAt: DateTime.now().toUtc(),
          ),
          bytes);
      await ref.read(storedAreasProvider.notifier).refresh();
      state = AreaDownloadState(phase: AreaDownloadPhase.done, name: name);
      return true;
    } on AreaCancelled {
      state = const AreaDownloadState();
      return false;
    } catch (e, s) {
      if (!looksOffline(e)) logError('Übersicht speichern', e, s);
      state = AreaDownloadState(
          phase: AreaDownloadPhase.failed,
          name: name,
          error: looksOffline(e)
              ? 'Die Verbindung ist abgerissen. Nichts gespeichert — noch einmal versuchen, sobald Empfang da ist.'
              : 'Die Übersicht ließ sich nicht speichern.');
      return false;
    } finally {
      await coordinator.stop(_keepAliveKey);
    }
  }

  void cancel() => _cancelled = true;

  void reset() {
    if (!state.busy) state = const AreaDownloadState();
  }
}

final areaDownloadProvider =
    NotifierProvider<AreaDownloadNotifier, AreaDownloadState>(AreaDownloadNotifier.new);

/// Die Archive der Bereiche mit Pfad — für MapLibre (`file://`). Leer im
/// Browser (dort gibt es keine Pfade, und keine MapLibre-Engine).
final areaArchivePathsProvider = FutureProvider<List<({StoredArea area, String path})>>((ref) async {
  final areas = await ref.watch(storedAreasProvider.future);
  final store = ref.watch(areaStoreProvider);
  return [
    for (final area in areas)
      if (await store.archivePath(area.id) case final path?) (area: area, path: path),
  ];
});

/// Öffnet ein gespeichertes Archiv für die flutter_map-Engine — die
/// Naht für Tests.
final areaArchiveOpenerProvider =
    Provider<Future<PmTilesVectorTileProvider?> Function(AreaStore store, StoredArea area)>(
        (ref) => _openArea);

Future<PmTilesVectorTileProvider?> _openArea(AreaStore store, StoredArea area) async {
  final path = await store.archivePath(area.id);
  if (path != null) return PmTilesVectorTileProvider.open(path);
  final bytes = await store.readArchive(area.id);
  if (bytes == null) return null;
  return PmTilesVectorTileProvider.openBytes(bytes);
}

/// Ein geöffnetes Archiv eines Bereichs mit seinem Zoombereich — das
/// Kartenarchiv (Zoom 8 bis zum Zoom des Hosts) oder die Wege (nur 13).
typedef OpenedAreaArchive = ({int minZoom, int maxZoom, PmTilesVectorTileProvider provider});

/// Mehrere Bereiche als EINE Kachelquelle: Die erste, die die Kachel
/// hat, liefert; keine ⇒ 404 wie bei einer Kachel außerhalb.
class MultiAreaTileProvider extends VectorTileProvider {
  MultiAreaTileProvider(this._areas) : assert(_areas.isNotEmpty);

  final List<OpenedAreaArchive> _areas;

  Future<void> close() async {
    for (final a in _areas) {
      await a.provider.close();
    }
  }

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    ProviderException? last;
    for (final a in _areas) {
      if (tile.z < a.minZoom || tile.z > a.maxZoom) continue;
      try {
        return await a.provider.provide(tile);
      } on ProviderException catch (e) {
        last = e;
      }
    }
    throw last ??
        ProviderException(
            message: 'Kachel ${tile.key()} in keinem Bereich', retryable: Retryable.none, statusCode: 404);
  }

  @override
  int get minimumZoom => _areas.map((a) => a.minZoom).reduce((a, b) => a < b ? a : b);

  @override
  int get maximumZoom => _areas.map((a) => a.maxZoom).reduce((a, b) => a > b ? a : b);

  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;

  @override
  TileProviderType get type => TileProviderType.vector;
}

/// Die Bereiche als Kartenschicht der flutter_map-Engine — null, wenn
/// es keine gibt oder keines aufgeht. Thema OHNE `background`, damit die
/// Übersicht darunter durchscheint, wo kein Bereich liegt.
final areaMapStyleProvider = FutureProvider<BaseMapStyle?>((ref) async {
  final areas = await ref.watch(storedAreasProvider.future);
  if (areas.isEmpty) return null;
  final store = ref.watch(areaStoreProvider);
  final open = ref.watch(areaArchiveOpenerProvider);
  final opened = <OpenedAreaArchive>[];
  for (final area in areas) {
    try {
      final provider = await open(store, area);
      if (provider != null) opened.add((minZoom: area.minZoom, maxZoom: area.maxZoom, provider: provider));
    } catch (e, s) {
      logError('Bereich öffnen', e, s);
    }
  }
  if (opened.isEmpty) return null;
  final multi = MultiAreaTileProvider(opened);
  ref.onDispose(multi.close);
  final theme = await ref.watch(baseThemeWithoutBackgroundProvider.future);
  return BaseMapStyle(theme: theme, tileProviders: TileProviders({'protomaps': multi}));
});

/// Die Wege-Archive der Bereiche mit Pfad — für MapLibre (`file://`),
/// leer, solange die Ebene aus ist. Leer im Browser.
final areaWaysPathsProvider = FutureProvider<List<({StoredArea area, String path})>>((ref) async {
  if (!ref.watch(wayLayerEnabledProvider)) return const [];
  final areas = await ref.watch(storedAreasProvider.future);
  final store = ref.watch(areaStoreProvider);
  return [
    for (final area in areas)
      if (area.hasWays)
        if (await store.waysPath(area.id) case final path?) (area: area, path: path),
  ];
});

/// Öffnet das Wege-Archiv eines Bereichs für die flutter_map-Engine —
/// die Naht für Tests.
final areaWaysOpenerProvider =
    Provider<Future<PmTilesVectorTileProvider?> Function(AreaStore store, StoredArea area)>(
        (ref) => _openWays);

Future<PmTilesVectorTileProvider?> _openWays(AreaStore store, StoredArea area) async {
  final path = await store.waysPath(area.id);
  if (path != null) return PmTilesVectorTileProvider.open(path);
  final bytes = await store.readWays(area.id);
  if (bytes == null) return null;
  return PmTilesVectorTileProvider.openBytes(bytes);
}

/// Die Wege der Bereiche als Ebene der flutter_map-Engine — über der
/// Wege-Ebene vom Host, mit demselben Thema (Quelle [kWaysSourceId]).
/// Null, wenn die Ebene aus ist oder kein Bereich Wege trägt.
final areaWaysStyleProvider = FutureProvider<BaseMapStyle?>((ref) async {
  if (!ref.watch(wayLayerEnabledProvider)) return null;
  final areas = await ref.watch(storedAreasProvider.future);
  final store = ref.watch(areaStoreProvider);
  final open = ref.watch(areaWaysOpenerProvider);
  final opened = <OpenedAreaArchive>[];
  for (final area in areas) {
    if (!area.hasWays) continue;
    try {
      final provider = await open(store, area);
      if (provider != null) opened.add((minZoom: kWaysZoom, maxZoom: kWaysZoom, provider: provider));
    } catch (e, s) {
      logError('Wege eines Bereichs öffnen', e, s);
    }
  }
  if (opened.isEmpty) return null;
  final multi = MultiAreaTileProvider(opened);
  ref.onDispose(multi.close);
  return BaseMapStyle(theme: wayTheme(), tileProviders: TileProviders({kWaysSourceId: multi}));
});

/// „Auf der Karte zeigen" aus der Liste: der Wunsch, den die Karte beim
/// nächsten Aufbau einpasst und dann zurücksetzt.
final mapFocusAreaProvider = StateProvider<StoredArea?>((ref) => null);

/// Solange die Werkzeugleiste „Ebenen" offen ist (seit 0.27.0; davor das
/// Blatt „Offline-Karten"): Die Karte dunkelt alles ab, was nicht
/// gespeichert ist, und der Entwurf liegt schraffiert darüber.
final offlineOverlayProvider = StateProvider<bool>((ref) => false);
