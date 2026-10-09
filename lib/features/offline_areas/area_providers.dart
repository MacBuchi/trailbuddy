// Die gespeicherten Bereiche in der App (Konzept 3.2): die Liste, der
// laufende Download (mit Fortschritt, Abbruch und dem Vordergrunddienst
// über den KeepAlive-Koordinator), und der Kachelspeicher für die Karte —
// für flutter_map als Kachelquellen, für MapLibre als Pfade.
//
// Seit 0.106.0 (#229, Konzept 8) sind Bereiche Verweise auf EINEN
// Kachelspeicher je Region und Ebene: Die Karte hat eine Quelle je Region,
// nicht eine je Bereich; Löschen nimmt nur, was kein anderer Bereich deckt
// (`tile_refs.dart`), und beim ersten Laden der Liste wird der Altbestand
// übernommen (`area_migration.dart`).
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
import 'area_migration.dart';
import 'area_plan.dart';
import 'area_store.dart';
import 'area_trim.dart';
import 'height_tiles.dart';
import 'region_overview.dart';
import 'tile_refs.dart';
import 'tile_store.dart';
import 'tile_store_sources.dart';

/// Die Liste aus dem Index, in Speicherreihenfolge.
class StoredAreasNotifier extends AsyncNotifier<List<StoredArea>> {
  /// Beim ersten Lesen wird der Altbestand übernommen (#229) — lokal,
  /// einmal; danach ist es ein Blick in den Index.
  @override
  Future<List<StoredArea>> build() =>
      migrateLegacyAreas(ref.watch(areaStoreProvider), ref.watch(tileStoreProvider));

  Future<void> refresh() async {
    state = AsyncData(await ref.read(areaStoreProvider).list());
    ref.invalidate(storedOverviewsProvider);
  }

  /// Löscht den Bereich — seine Kacheln nur, soweit kein anderer Bereich
  /// sie deckt (#229) — und mit dem letzten seiner Region deren Übersicht
  /// (#220 Schritt 4): Sie kam mit ihm, sie geht mit ihm.
  Future<void> delete(String id) async {
    final store = ref.read(areaStoreProvider);
    final gone = (await store.list()).where((a) => a.id == id).toList();
    await store.delete(id);
    if (gone.isNotEmpty) {
      final tiles = ref.read(tileStoreProvider);
      final orphans = await orphansAfter(
          store: tiles, remaining: await store.list(), regions: {gone.first.region}, gone: gone);
      await removeOrphans(tiles, store, orphans);
    }
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
      AreaTrimmer(ref.read(areaStoreProvider), ref.read(tileStoreProvider)).plan(await future, removes);

  Future<void> applyTrim(TrimPlan plan) async {
    await AreaTrimmer(ref.read(areaStoreProvider), ref.read(tileStoreProvider)).apply(plan);
    // Der Radierer kann den letzten Bereich einer Region leeren.
    await _dropOrphanOverviews();
    await refresh();
  }
}

final storedAreasProvider =
    AsyncNotifierProvider<StoredAreasNotifier, List<StoredArea>>(StoredAreasNotifier.new);

/// Was ein Bereich ALLEIN belegt (#229): die Bytes, die sein Löschen frei
/// gäbe — Kacheln, die ein anderer Bereich auch deckt, zählen nicht.
/// Gemessen aus dem Index des Speichers, für „Meine Bereiche".
final areaExclusiveBytesProvider = FutureProvider.family<int, String>((ref, id) async {
  final areas = await ref.watch(storedAreasProvider.future);
  final area = areas.where((a) => a.id == id).firstOrNull;
  if (area == null) return 0;
  final orphans = await orphansAfter(
    store: ref.watch(tileStoreProvider),
    remaining: [for (final a in areas) if (a.id != id) a],
    regions: {area.region},
    gone: [area],
  );
  return orphanBytes(orphans);
});

/// Was alle Bereiche zusammen belegen — jede liegende Kachel einmal, über
/// alle Regionen und Ebenen (ohne die kleinen Orte-Dateien).
final areaStoredBytesProvider = FutureProvider<int>((ref) async {
  final areas = await ref.watch(storedAreasProvider.future);
  final tiles = ref.watch(tileStoreProvider);
  var total = 0;
  for (final region in areaRegionsOf(areas)) {
    for (final layer in TileLayer.values) {
      for (final info in (await tiles.index(region, layer)).values) {
        total += info.bytes;
      }
    }
  }
  return total;
});

/// Die Regionen, in denen Bereiche liegen — je eine Quelle auf der Karte.
List<String> areaRegionsOf(List<StoredArea> areas) => {for (final a in areas) a.region}.toList()..sort();

/// Der höchste Zoom der Bereiche einer Region (der des Hosts beim Laden).
int areaMaxZoomIn(List<StoredArea> areas, String region) =>
    areas.where((a) => a.region == region).fold(kAreaMinZoom, (m, a) => a.maxZoom > m ? a.maxZoom : m);

/// Das Alter je Kachel, je Region zusammengefasst (Konzept 8.2, Schritt 4):
/// wie viele Kacheln die Formen der Region decken und wie viele davon aus
/// einem älteren Bau stammen als der des Hosts — aus dem Index, ohne Netz,
/// gegen die Manifeste, die die App ohnehin hat. Ohne Manifest einer Ebene
/// zählt sie nicht als veraltet.
@immutable
class RegionTileAge {
  const RegionTileAge({required this.tiles, required this.stale, required this.staleBytes, this.build});

  /// Liegende Kacheln der Karte, die eine Form der Region deckt.
  final int tiles;

  /// Davon veraltet, über alle Ebenen (Karte, Höhen, Wege).
  final int stale;

  /// Ihre Bytes, wie sie liegen — der Ersatz kommt beim Planen.
  final int staleBytes;

  /// Der Kartenstand des Hosts; null ohne Manifest.
  final String? build;
}

final regionTileAgeProvider = FutureProvider.family<RegionTileAge, MapRegion>((ref, region) async {
  final areas = [
    for (final a in await ref.watch(storedAreasProvider.future))
      if (a.region == region.id) a,
  ];
  final tiles = ref.watch(tileStoreProvider);
  final map = await ref.watch(regionMapManifestProvider(region).future);
  final heights = await ref.watch(regionHeightsManifestProvider(region).future);
  final ways = await ref.watch(areaWaysAvailableProvider(region).future);
  var stored = 0, stale = 0, staleBytes = 0;
  for (final (layer, build) in [
    (TileLayer.map, map?.sourceBuild),
    (TileLayer.heights, heights?.build),
    (TileLayer.ways, ways?.build),
  ]) {
    final index = await tiles.index(region.id, layer);
    if (index.isEmpty) continue;
    final referenced = referencedIn(areas, layer, index);
    if (layer == TileLayer.map) stored = referenced.where(index.containsKey).length;
    final s = staleTiles(index, referenced, build);
    stale += s.ids.length;
    staleBytes += s.bytes;
  }
  return RegionTileAge(tiles: stored, stale: stale, staleBytes: staleBytes, build: map?.sourceBuild);
});

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

/// Holt das Orte-Bündel einer Region als ganze Datei (Schritt 5) — die
/// Naht für Tests; der Harness setzt sie auf eine, die nichts holt.
final poiBundleFetcherProvider = Provider<OverviewFetcher>((ref) => fetchOverviewFile);

/// Ob „Ganze Region speichern" angeboten wird: nur auf dem Telefon
/// (Betreiber, 2026-10-09 — DACH sind rund 3,2 GB, das passt nicht
/// verlässlich in einen Browser). Die Naht für Tests.
final wholeRegionSupportedProvider = Provider<bool>((ref) => !kIsWeb);

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

/// Höhen aus den gespeicherten Bereichen — je Region der Kachelspeicher
/// (#229). Kacheln kommen beim Lesen; wer nichts rechnet, beobachtet nicht.
final areaHeightReaderProvider = FutureProvider<HeightReader>((ref) async {
  final areas = await ref.watch(storedAreasProvider.future);
  final tiles = ref.watch(tileStoreProvider);
  final sources = <HeightTileSource>[
    for (final region in areaRegionsOf([for (final a in areas) if (a.hasHeights) a])) StoreHeightSource(tiles, region),
  ];
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
    this.refreshing = false,
    this.waiting = false,
  });

  final AreaDownloadPhase phase;

  /// Wartet ein abgerissener Download auf Empfang (seit 0.108.2)?
  final bool waiting;

  /// Läuft „Aktualisieren" einer Region statt eines Bereichs (Schritt 4)?
  final bool refreshing;
  final String? name;
  final AreaPlan? plan;
  final AreaProgress? progress;
  final StoredArea? result;
  final String? error;

  bool get busy => phase == AreaDownloadPhase.planning || phase == AreaDownloadPhase.running;
}

/// So oft wartet ein abgerissener Download auf das Netz, bevor er aufgibt
/// — mit [areaResumeDelayProvider] zusammen rund 37 Minuten.
const kAreaResumeAttempts = 40;

/// Die Pause vor dem [attempt]-ten Wiederaufnehmen: 5, 10, 20, 40 s,
/// danach jede Minute. Die Naht für Tests.
final areaResumeDelayProvider = Provider<Future<void> Function(int attempt)>(
    (ref) => (attempt) => Future.delayed(Duration(seconds: attempt >= 4 ? 60 : 5 << attempt)));

class AreaDownloadNotifier extends Notifier<AreaDownloadState> {
  static const _keepAliveKey = 'area';
  bool _cancelled = false;

  /// Hat der laufende Versuch mindestens einen Block abgelegt?
  bool _progressed = false;

  @override
  AreaDownloadState build() => const AreaDownloadState();

  /// Der Plan für [shape]: wirft [AreaTooLarge], liefert Kacheln, Bytes
  /// und — seit 0.27.0 — die Orte samt Anzahl (der Dialog vor dem
  /// Speichern nennt sie; der Download holt sie dann nicht noch einmal).
  /// Braucht das Manifest — ohne Empfang gibt es keinen Plan. Gezählt
  /// wird nur, was im Kachelspeicher fehlt (#229); mit [refresh] auch,
  /// was aus einem älteren Bau liegt (Aktualisieren).
  ///
  /// Die ganze Region misst unter dem Service (seit 0.108.2): Das Messen
  /// liest das ganze Verzeichnis des Hosts, und wer dabei die App wechselt,
  /// fände sie sonst eingefroren vor.
  Future<AreaPlan> plan(AreaShape shape, {bool refresh = false}) async {
    if (shape is! RegionShape) return _plan(shape, refresh: refresh);
    final coordinator = ref.read(keepAliveCoordinatorProvider);
    await coordinator.start(_keepAliveKey, 'Größe wird gemessen', title: 'Region wird gemessen');
    try {
      return await _plan(shape, refresh: refresh);
    } finally {
      await coordinator.stop(_keepAliveKey);
    }
  }

  Future<AreaPlan> _plan(AreaShape shape, {bool refresh = false, bool quiet = false}) async {
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
    if (!quiet) state = const AreaDownloadState(phase: AreaDownloadPhase.planning);
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
          tiles: ref.read(tileStoreProvider),
          poiManifest: poiManifest,
          fetchPoiFile: (fileName) =>
              poiManifest == null ? Future.value(null) : fetchPoi(poiManifest, fileName),
          heights: heights,
          heightsManifest: heightsManifest,
          ways: ways,
          waysManifest: waysManifest,
          region: region.id,
          overview: hosts.overview,
          fetchOverview: ref.read(overviewFetcherProvider),
          fetchPoiBundle: ref.read(poiBundleFetcherProvider));
      final plan = await downloader.plan(shape, withPois: true, refresh: refresh);
      if (!quiet) state = AreaDownloadState(phase: AreaDownloadPhase.idle, plan: plan);
      return plan;
    } catch (e) {
      if (!quiet) state = const AreaDownloadState();
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
  /// Oberfläche zeigt ihn), nie beim Aufrufer. Mit [refresh] plant ein
  /// Wiederaufnehmen wie „Aktualisieren".
  ///
  /// **Reißt die Verbindung ab, wartet er und macht von selbst weiter**
  /// (seit 0.108.2, wie PilzBuddys Karten-Download): Die ganze Region sind
  /// Gigabytes, und ein Funkloch oder WLAN-Wechsel unterwegs beendete
  /// sie bis dahin, bis jemand „Fortsetzen" tippte. Weiter geht es mit
  /// demselben Bereich und einem neuen Plan (nur, was fehlt). Über
  /// Mobilfunk nur, wenn er dort auch angefangen hat — gefragt wurde nach
  /// dem Netz beim Tippen. Nach [kAreaResumeAttempts] Versuchen ohne Netz
  /// gibt er auf; ein anderer Fehler beendet ihn sofort, wie bisher.
  Future<StoredArea?> start(AreaPlan plan, {required String name, String? id, bool refresh = false}) async {
    if (state.busy) return null;
    _cancelled = false;
    // Die Id steht vorher fest: Ein Wiederaufnehmen schreibt in DENSELBEN
    // Bereich, nicht in einen zweiten.
    final areaId = id ?? newAreaId(DateTime.now().toUtc());
    final allowMobile = ref.read(onMobileDataProvider);
    final coordinator = ref.read(keepAliveCoordinatorProvider);
    await coordinator.start(_keepAliveKey, '$name — 0 %', title: 'Bereich wird gespeichert');
    try {
      var current = plan;
      var waits = 0;
      while (true) {
        state = AreaDownloadState(phase: AreaDownloadPhase.running, name: name, plan: current, progress: state.progress);
        Object error;
        StackTrace trace;
        _progressed = false;
        try {
          final area = await _downloadOnce(current, name: name, id: areaId, coordinator: coordinator);
          if (area == null) {
            state = AreaDownloadState(
                phase: AreaDownloadPhase.failed, error: 'Kein Kartenhost erreichbar', plan: current);
            return null;
          }
          await ref.read(storedAreasProvider.notifier).refresh();
          state = AreaDownloadState(phase: AreaDownloadPhase.done, name: name, plan: current, result: area);
          return area;
        } on AreaCancelled {
          return await _cancelledDownload();
        } catch (e, s) {
          error = e;
          trace = s;
        }
        // Ist dieser Versuch vorangekommen, beginnt die Geduld von vorn —
        // die Grenze gilt für ein Funkloch, nicht für alle zusammen.
        if (_progressed) waits = 0;
        if (!looksOffline(error) || _cancelled) {
          if (_cancelled) return await _cancelledDownload();
          return await _failedDownload(error, trace, name: name, plan: current);
        }
        // Warten, bis das Netz zurück ist, dann neu planen (nur, was fehlt).
        AreaPlan? next;
        while (next == null) {
          if (waits >= kAreaResumeAttempts) return await _failedDownload(error, trace, name: name, plan: current);
          state = AreaDownloadState(
              phase: AreaDownloadPhase.running, name: name, plan: current, progress: state.progress, waiting: true);
          unawaited(coordinator.update(_keepAliveKey, '$name — wartet auf Empfang'));
          await ref.read(areaResumeDelayProvider)(waits++);
          if (_cancelled) return await _cancelledDownload();
          if (ref.read(noConnectivityProvider) || (!allowMobile && ref.read(onMobileDataProvider))) continue;
          try {
            next = await _plan(current.shape, refresh: refresh, quiet: true);
          } catch (e, s) {
            // Ohne Empfang wirft das Messen ein StateError („kein Host") —
            // weiter warten; alles andere ist kein Funkloch.
            if (!looksOffline(e) && e is! StateError) return await _failedDownload(e, s, name: name, plan: current);
          }
        }
        current = next;
      }
    } finally {
      await coordinator.stop(_keepAliveKey);
    }
  }

  Future<StoredArea?> _cancelledDownload() async {
    // Was schon geschrieben ist, bleibt (Konzept 8.2): Der Bereich steht
    // als unvollständig in der Liste, „Fortsetzen" holt den Rest.
    await ref.read(storedAreasProvider.notifier).refresh();
    state = const AreaDownloadState();
    return null;
  }

  Future<StoredArea?> _failedDownload(Object e, StackTrace s, {required String name, required AreaPlan plan}) async {
    if (!looksOffline(e)) logError('Bereich speichern', e, s);
    await ref.read(storedAreasProvider.notifier).refresh();
    state = AreaDownloadState(
        phase: AreaDownloadPhase.failed,
        name: name,
        plan: plan,
        error: looksOffline(e)
            ? 'Die Verbindung ist abgerissen. Was schon geladen ist, bleibt — „Fortsetzen" in '
                '„Meine Bereiche" holt den Rest, sobald Empfang da ist.'
            : 'Der Bereich ließ sich nicht ganz speichern. Was schon geladen ist, bleibt.');
    return null;
  }

  /// Ein Versuch: Archive öffnen, laden, schließen. Null, wenn der
  /// Kartenhost der Region kein Manifest liefert.
  Future<StoredArea?> _downloadOnce(AreaPlan plan,
      {required String name, required String id, required KeepAliveCoordinator coordinator}) async {
    final regions = await ref.read(mapRegionsProvider.future);
    final region = regions.where((r) => r.id == plan.region).firstOrNull;
    final hosts = region == null ? null : await _hostManifests(ref, region);
    final manifest = hosts?.map;
    if (manifest == null) return null;
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
        tiles: ref.read(tileStoreProvider),
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
          fetchPoiBundle: ref.read(poiBundleFetcherProvider),
      );
      return await downloader.download(
        plan,
        name: name,
        id: id,
        isCancelled: () => _cancelled,
        onProgress: (raw) {
          if (raw.done > 0) _progressed = true;
          // Der Anteil der Karte zählt, was schon liegt, mit (seit
          // 0.108.2): Nach einem Wiederaufnehmen plant der Download nur
          // den Rest, und die Meldung fiele sonst auf 0 % zurück.
          final have = plan.map.coveredBytes - plan.map.fetchBytes;
          final p = raw.phase == AreaPhase.tiles && plan.map.coveredBytes > 0 && raw.totalBytes > 0
              ? AreaProgress(
                  phase: raw.phase,
                  done: raw.done,
                  total: raw.total,
                  doneBytes: have + raw.doneBytes,
                  totalBytes: have + raw.totalBytes)
              : raw;
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
    } finally {
      await archive?.close();
      await heights?.close();
      await ways?.close();
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

  /// Die Archive des Hosts für die Region [region], als Downloader — oder
  /// null ohne Kartenmanifest. Wer ihn bekommt, schließt [close].
  Future<({AreaDownloader downloader, Future<void> Function() close})?> _regionDownloader(MapRegion region) async {
    final hosts = await _hostManifests(ref, region);
    final manifest = hosts.map;
    if (manifest == null) return null;
    final archive = await ref.read(areaSourceOpenerProvider)(manifest.archiveUri);
    final heights = await _openSide(hosts.heights?.archiveUri, 'Höhenarchiv öffnen');
    final ways = await _openSide(hosts.ways?.archiveUri, 'Wege-Archiv öffnen');
    final poiManifest = hosts.pois;
    final fetchPoi = ref.read(areaPoiFileLoaderProvider);
    return (
      downloader: AreaDownloader(
        archive: archive,
        manifest: manifest,
        store: ref.read(areaStoreProvider),
        tiles: ref.read(tileStoreProvider),
        poiManifest: poiManifest,
        fetchPoiFile: (fileName) => poiManifest == null ? Future.value(null) : fetchPoi(poiManifest, fileName),
        heights: heights,
        heightsManifest: hosts.heights,
        ways: ways,
        waysManifest: hosts.ways,
        region: region.id,
      ),
      close: () async {
        await archive.close();
        await heights?.close();
        await ways?.close();
      },
    );
  }

  /// Was „Aktualisieren" der Region [region] holen würde (Konzept 8.2,
  /// Schritt 4) — gemessen gegen das Verzeichnis des neuen Baus. Braucht
  /// Empfang wie jeder Plan.
  Future<RegionRefreshPlan> planRegionRefresh(MapRegion region) async {
    if (ref.read(noConnectivityProvider)) throw StateError('Kein Kartenhost erreichbar');
    final host = await _regionDownloader(region);
    if (host == null) throw StateError('Kein Kartenhost erreichbar');
    try {
      return await host.downloader.planRefresh(await ref.read(storedAreasProvider.future));
    } finally {
      await host.close();
    }
  }

  /// Holt die veralteten Kacheln der Region — unter dem Koordinator wie
  /// ein Bereich, mit Fortschritt und Abbruch. Ein Abbruch lässt das schon
  /// Geholte liegen; ein Fehler landet im Zustand.
  Future<bool> startRegionRefresh(MapRegion region, RegionRefreshPlan plan) async {
    if (state.busy) return false;
    _cancelled = false;
    final name = 'Karte ${region.name}';
    state = AreaDownloadState(phase: AreaDownloadPhase.running, name: name, refreshing: true);
    final coordinator = ref.read(keepAliveCoordinatorProvider);
    await coordinator.start(_keepAliveKey, '$name — 0 %', title: 'Karte wird aktualisiert');
    Future<void> Function()? close;
    try {
      final host = await _regionDownloader(region);
      if (host == null) throw StateError('Kein Kartenhost erreichbar');
      close = host.close;
      await host.downloader.refreshRegion(
        plan,
        isCancelled: () => _cancelled,
        onProgress: (p) {
          state = AreaDownloadState(phase: AreaDownloadPhase.running, name: name, progress: p, refreshing: true);
          unawaited(coordinator.update(_keepAliveKey, '$name — ${(p.fraction * 100).round()} %'));
        },
      );
      await ref.read(storedAreasProvider.notifier).refresh();
      state = AreaDownloadState(phase: AreaDownloadPhase.done, name: name);
      return true;
    } on AreaCancelled {
      await ref.read(storedAreasProvider.notifier).refresh();
      state = const AreaDownloadState();
      return false;
    } catch (e, s) {
      if (!looksOffline(e)) logError('Region aktualisieren', e, s);
      await ref.read(storedAreasProvider.notifier).refresh();
      state = AreaDownloadState(
          phase: AreaDownloadPhase.failed,
          name: name,
          error: looksOffline(e)
              ? 'Die Verbindung ist abgerissen. Was schon neu geladen ist, bleibt — „Aktualisieren" '
                  'holt den Rest, sobald Empfang da ist.'
              : 'Die Karte ließ sich nicht ganz aktualisieren. Was schon neu geladen ist, bleibt.');
      return false;
    } finally {
      await close?.call();
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

/// Der Kartenspeicher je Region mit Pfad — für MapLibre (`mbtiles://`,
/// #229): EINE Quelle je Region statt einer je Bereich. Leer im Browser
/// (dort gibt es keine Pfade, und keine MapLibre-Engine).
final areaMapPathsProvider =
    FutureProvider<List<({String region, String path, int minZoom, int maxZoom})>>((ref) async {
  final areas = await ref.watch(storedAreasProvider.future);
  final tiles = ref.watch(tileStoreProvider);
  return [
    for (final region in areaRegionsOf(areas))
      if (await tiles.path(region, TileLayer.map) case final path?)
        (region: region, path: path, minZoom: kAreaMinZoom, maxZoom: areaMaxZoomIn(areas, region)),
  ];
});

/// Die Kartenkacheln eines Bereichs als Quelle — der Speicher SEINER
/// Region; zwei Bereiche einer Region liefern dieselbe Antwort. Die Naht
/// für Tests und für die Leser im Dart-Code (Wege-Index, Planer).
final areaArchiveOpenerProvider =
    Provider<Future<ClosableVectorTileProvider?> Function(AreaStore store, StoredArea area)>((ref) {
  final tiles = ref.watch(tileStoreProvider);
  return (store, area) async =>
      StoreTileProvider(tiles, area.region, TileLayer.map, minZoom: area.minZoom, maxZoom: area.maxZoom);
});

/// Ein geöffnetes Archiv mit seinem Zoombereich — eine Region der
/// Bereiche (Zoom 8 bis zum Zoom des Hosts), ihre Wege (nur 13) oder eine
/// Übersicht.
typedef OpenedAreaArchive = ({int minZoom, int maxZoom, ClosableVectorTileProvider provider});

/// Mehrere Quellen als EINE: Die erste, die die Kachel hat, liefert;
/// keine ⇒ 404 wie bei einer Kachel außerhalb.
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

/// Die Bereiche als Kartenschicht der flutter_map-Engine — je Region der
/// Speicher; null, wenn es keine gibt. Thema OHNE `background`, damit die
/// Übersicht darunter durchscheint, wo kein Bereich liegt.
final areaMapStyleProvider = FutureProvider<BaseMapStyle?>((ref) async {
  final areas = await ref.watch(storedAreasProvider.future);
  if (areas.isEmpty) return null;
  final tiles = ref.watch(tileStoreProvider);
  final opened = <OpenedAreaArchive>[
    for (final region in areaRegionsOf(areas))
      (
        minZoom: kAreaMinZoom,
        maxZoom: areaMaxZoomIn(areas, region),
        provider: StoreTileProvider(tiles, region, TileLayer.map,
            minZoom: kAreaMinZoom, maxZoom: areaMaxZoomIn(areas, region)),
      ),
  ];
  final multi = MultiAreaTileProvider(opened);
  ref.onDispose(multi.close);
  final theme = await ref.watch(baseThemeWithoutBackgroundProvider.future);
  return BaseMapStyle(theme: theme, tileProviders: TileProviders({'protomaps': multi}));
});

/// Der Wege-Speicher je Region mit Pfad — für MapLibre (`mbtiles://`),
/// leer, solange die Ebene aus ist. Leer im Browser.
final areaWaysPathsProvider = FutureProvider<List<({String region, String path})>>((ref) async {
  if (!ref.watch(wayLayerEnabledProvider)) return const [];
  final areas = await ref.watch(storedAreasProvider.future);
  final tiles = ref.watch(tileStoreProvider);
  return [
    for (final region in areaRegionsOf([for (final a in areas) if (a.hasWays) a]))
      if (await tiles.path(region, TileLayer.ways) case final path?) (region: region, path: path),
  ];
});

/// Die Wege eines Bereichs als Quelle — der Speicher seiner Region. Die
/// Naht für Tests und die Wegegüte des Planers.
final areaWaysOpenerProvider =
    Provider<Future<ClosableVectorTileProvider?> Function(AreaStore store, StoredArea area)>((ref) {
  final tiles = ref.watch(tileStoreProvider);
  return (store, area) async =>
      area.hasWays ? StoreTileProvider(tiles, area.region, TileLayer.ways, minZoom: kWaysZoom, maxZoom: kWaysZoom) : null;
});

/// Die Wege der Bereiche als Ebene der flutter_map-Engine — über der
/// Wege-Ebene vom Host, mit demselben Thema (Quelle [kWaysSourceId]).
/// Null, wenn die Ebene aus ist oder kein Bereich Wege trägt.
final areaWaysStyleProvider = FutureProvider<BaseMapStyle?>((ref) async {
  if (!ref.watch(wayLayerEnabledProvider)) return null;
  final areas = await ref.watch(storedAreasProvider.future);
  final regions = areaRegionsOf([for (final a in areas) if (a.hasWays) a]);
  if (regions.isEmpty) return null;
  final tiles = ref.watch(tileStoreProvider);
  final multi = MultiAreaTileProvider([
    for (final region in regions)
      (
        minZoom: kWaysZoom,
        maxZoom: kWaysZoom,
        provider: StoreTileProvider(tiles, region, TileLayer.ways, minZoom: kWaysZoom, maxZoom: kWaysZoom),
      ),
  ]);
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
