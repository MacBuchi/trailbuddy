import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vector_map_tiles/vector_map_tiles.dart' show TileProviders, VectorTileProvider;

import '../../core/connectivity.dart';
import '../../core/errors.dart';
import '../../core/settings.dart';
import '../offline_areas/height_tiles.dart' show kHeightGrid, kHeightTileZoom, kHeightsFormat;
import 'base_map_providers.dart';
import 'map_regions.dart';
import 'map_providers.dart';
import 'pmtiles_tile_provider.dart';
import 'seen_tiles.dart';
import 'seen_tiles_web.dart' if (dart.library.io) 'seen_tiles_io.dart';

/// Das Manifest des Kartenhosts (`dach.json`, geschrieben von
/// `map-data.yml`): welche Datei gerade gilt und bis zu welchem Zoom sie
/// reicht.
class MapManifest {
  const MapManifest({
    required this.file,
    required this.maxZoom,
    required this.bytes,
    required this.sourceBuild,
    this.dir = '',
  });

  final String file;
  final int maxZoom;
  final int bytes;

  /// Das Datum des Protomaps-Baus (`JJJJMMTT`) — der Kartenstand.
  final String sourceBuild;

  /// Der Ordner der Region auf dem Host (#220): leer für DACH (die
  /// Wurzel), sonst `<id>/`. [file] ist relativ dazu.
  final String dir;

  Uri get archiveUri => Uri.parse('$kMapTilesBase/$dir$file');

  /// Liest das Manifest; wirft bei allem, was nicht passt. Der Dateiname
  /// wird geprüft, weil er zu einem Pfad wird — DACH heißt `dach-…`, jede
  /// andere Region `map-…` in ihrem Ordner, und ein `/` kommt nie vor.
  /// [dir] kommt aus dem Regionen-Index, nicht aus dem Manifest; ein
  /// gemerktes trägt es mit.
  factory MapManifest.fromJson(Map<String, dynamic> j, {String dir = ''}) {
    final file = j['file'] as String;
    final folder = checkRegionDir(j['dir'] as String? ?? dir);
    final pattern = folder.isEmpty ? RegExp(r'^dach-\d{8}\.pmtiles$') : RegExp(r'^map-\d{8}\.pmtiles$');
    if (!pattern.hasMatch(file)) {
      throw FormatException('Unerwarteter Archivname: $file');
    }
    return MapManifest(
      file: file,
      maxZoom: j['maxzoom'] as int,
      bytes: j['bytes'] as int,
      sourceBuild: j['source_build'] as String,
      dir: folder,
    );
  }

  /// Zum Merken auf dem Gerät (#155) — liest sich mit [MapManifest.fromJson]
  /// zurück, mit derselben Prüfung. Der Ordner nur, wo es einen gibt: Für
  /// DACH bleibt der gemerkte Text, wie er vor #220 war.
  Map<String, dynamic> toJson() => {
        'file': file,
        'maxzoom': maxZoom,
        'bytes': bytes,
        'source_build': sourceBuild,
        if (dir.isNotEmpty) 'dir': dir,
      };
}

/// Prüft den Ordner einer Region (#220): leer oder `<id>/` mit 2–8
/// Kleinbuchstaben. Er wird Teil einer Adresse, also nie `..` oder ein
/// zweiter Schrägstrich.
String checkRegionDir(String dir) {
  if (dir.isEmpty || RegExp(r'^[a-z]{2,8}/$').hasMatch(dir)) return dir;
  throw FormatException('Unerwarteter Regionsordner: $dir');
}

/// Das Manifest der Höhenkacheln (`heights.json`, geschrieben von
/// `height-data.yml`): welche Datei gilt, mit welchem Format. Ein
/// Format, das die App nicht kennt, wird abgelehnt — dann gibt es keine
/// Höhen, keine falsch gelesenen.
class HeightsManifest {
  const HeightsManifest({
    required this.file,
    required this.bytes,
    required this.build,
    this.dir = '',
  });

  final String file;
  final int bytes;

  /// Das Datum des Baus (`JJJJMMTT`).
  final String build;

  /// Der Ordner der Region (#220), siehe [MapManifest.dir].
  final String dir;

  Uri get archiveUri => Uri.parse('$kMapTilesBase/$dir$file');

  factory HeightsManifest.fromJson(Map<String, dynamic> j, {String dir = ''}) {
    final file = j['file'] as String;
    final folder = checkRegionDir(dir);
    if (!RegExp(r'^heights-\d{8}\.pmtiles$').hasMatch(file)) {
      throw FormatException('Unerwarteter Archivname: $file');
    }
    if (j['format'] != kHeightsFormat || j['grid'] != kHeightGrid || j['zoom'] != kHeightTileZoom) {
      throw FormatException('Höhenformat ${j['format']}/${j['grid']}/${j['zoom']} unbekannt');
    }
    return HeightsManifest(file: file, bytes: j['bytes'] as int, build: j['build'] as String, dir: folder);
  }
}

/// Das Manifest der Übersicht einer Region (#220 Schritt 4,
/// `<id>/overview.json`, geschrieben von `map-data.yml` im selben Lauf wie
/// die Karte): Zoom 0–7 als EINE Datei, die mit dem ersten Bereich der
/// Region ganz geladen wird. DACH hat keins — seine Übersicht liegt im
/// Binary —, deshalb gibt es sie nur in einem Regionsordner.
class OverviewManifest {
  const OverviewManifest({
    required this.file,
    required this.bytes,
    required this.sha256,
    required this.maxZoom,
    required this.sourceBuild,
    required this.dir,
  });

  final String file;
  final int bytes;

  /// Die Prüfsumme der Datei (hex) — die ganze Datei kommt in einem Stück,
  /// und gelesen wird sie erst, wenn sie stimmt.
  final String sha256;
  final int maxZoom;

  /// Der Protomaps-Bau (`JJJJMMTT`), derselbe wie der der Karte.
  final String sourceBuild;
  final String dir;

  Uri get archiveUri => Uri.parse('$kMapTilesBase/$dir$file');

  /// Wirft bei allem, was nicht passt — Name und Ordner werden Teil einer
  /// Adresse, und eine Übersicht an der Wurzel gibt es nicht.
  factory OverviewManifest.fromJson(Map<String, dynamic> j, {String dir = ''}) {
    final file = j['file'] as String;
    final folder = checkRegionDir(dir);
    if (folder.isEmpty) throw const FormatException('Eine Übersicht gibt es nur im Ordner einer Region');
    if (!RegExp(r'^overview-\d{8}\.pmtiles$').hasMatch(file)) {
      throw FormatException('Unerwarteter Archivname: $file');
    }
    final sha = j['sha256'] as String;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) throw FormatException('Unerwartete Prüfsumme: $sha');
    final maxZoom = j['maxzoom'] as int;
    if (maxZoom < 0 || maxZoom > 10) throw FormatException('Unerwarteter Zoom der Übersicht: $maxZoom');
    return OverviewManifest(
      file: file,
      bytes: j['bytes'] as int,
      sha256: sha,
      maxZoom: maxZoom,
      sourceBuild: j['source_build'] as String,
      dir: folder,
    );
  }
}

/// Holt das Höhen-Manifest vom Host; wirft bei allem, was nicht passt.
Future<HeightsManifest?> fetchHeightsManifest() async {
  final response = await http.get(Uri.parse(kHeightsManifestUrl));
  if (response.statusCode != 200) {
    throw http.ClientException('Höhen-Manifest: HTTP ${response.statusCode}');
  }
  return HeightsManifest.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
}

final heightsManifestLoaderProvider =
    Provider<Future<HeightsManifest?> Function()>((ref) => fetchHeightsManifest);

/// Das Höhen-Manifest — oder null: kein Empfang, Host nicht erreichbar,
/// noch kein Bau, unbekanntes Format. Null heißt: Ein Bereich kommt ohne
/// Höhen, und die Liste bietet keine an.
final heightsManifestProvider = FutureProvider<HeightsManifest?>((ref) async {
  if (ref.watch(noConnectivityProvider)) return null;
  try {
    return await ref.watch(heightsManifestLoaderProvider)();
  } catch (e, s) {
    if (!looksOffline(e) && e is! FormatException) logError('Höhen-Manifest laden', e, s);
    return null;
  }
});

/// Höchstens so lange wartet der Abruf des Manifests (#183). Ohne Grenze
/// hing er bei „Netz gemeldet, aber nichts kommt durch" (ein Balken im
/// Wald) bis zum Abbruch durch das System — eine halbe Minute und mehr.
/// Danach gilt „kein Manifest": die Übersicht, und mit der Rückkehr des
/// Netzes ein neuer Versuch.
const kMapManifestTimeout = Duration(seconds: 10);

/// Wie lange der MapLibre-Stil beim Aufbau auf das Manifest wartet, bevor
/// er mit der Übersicht beginnt (#183). Kommt es später, baut der Stil
/// neu und wechselt auf die Online-Karte. Kurz genug, dass die Karte im
/// Funkloch sofort etwas zeigt, lang genug, dass sie mit Netz nicht erst
/// die Übersicht und dann die Online-Karte zeichnet.
const kMapManifestPatience = Duration(milliseconds: 1500);

/// „Gesehenes bleibt liegen" (#155, Konzept offline-karten 3.2): So viel
/// darf MapLibre auf Android von der Online-Karte und den Wegen behalten,
/// die älteste Kachel geht zuerst. Gemessen am 2026-10-08 auf
/// `dach-20261001.pmtiles`: ein Ausschnitt von 20 × 20 km über Zoom 8–13
/// kostet 2,9–4,1 MB (Alpen, Schwarzwald, Stadtrand), ein Tag mit viel
/// Schieben über 50 × 50 km grob 20–25 MB — 100 MB tragen also gut
/// zwanzig solche Tage (Betreiber, 2026-10-08; das Konzept hatte 200 MB
/// geschätzt).
const kSeenTilesCacheBytes = 100 * 1024 * 1024;

/// Holt das Manifest vom Host — die Naht, die Tests ersetzen (kein Netz).
Future<MapManifest?> fetchMapManifest() async {
  final response = await http.get(Uri.parse(kMapManifestUrl)).timeout(kMapManifestTimeout);
  if (response.statusCode != 200) {
    throw http.ClientException('Manifest: HTTP ${response.statusCode}');
  }
  return MapManifest.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
}

final mapManifestLoaderProvider =
    Provider<Future<MapManifest?> Function()>((ref) => fetchMapManifest);

/// Das Manifest — oder null: kein Empfang (dann wird gar nicht erst
/// gefragt), Host nicht erreichbar, Datei kaputt. Null heißt für beide
/// Engines: die mitgelieferte Übersicht ist die Karte.
///
/// Hängt am `noConnectivityProvider`, damit die Rückkehr des Netzes einen
/// neuen Versuch auslöst. Ein Fehler wird nur gemeldet, wenn er nicht
/// nach Funkloch aussieht — sonst füllte jeder Wald den Wochendigest.
final mapManifestProvider = FutureProvider<MapManifest?>((ref) async {
  if (ref.watch(noConnectivityProvider)) return null;
  try {
    return await ref.watch(mapManifestLoaderProvider)();
  } catch (e, s) {
    if (!looksOffline(e)) logError('Karten-Manifest laden', e, s);
    return null;
  }
});

/// Öffnet das Online-Archiv über Range-Anfragen — die Naht für Tests.
final onlineArchiveOpenerProvider =
    Provider<Future<PmTilesVectorTileProvider> Function(Uri)>(
        (ref) => PmTilesVectorTileProvider.openUri);

/// Der Speicher gesehener Kacheln (#155) — im Browser IndexedDB, sonst
/// keiner (Android: MapLibres Ambient Cache). Die Naht für Tests.
final seenTileStoreProvider = Provider<SeenTileStore?>((ref) => createSeenTileStore());

/// Liest ein gemerktes Manifest (#155) — mit derselben Prüfung wie vom
/// Host. Was nicht mehr passt (ein anderes Wege-Format nach einem Update),
/// heißt still „keins".
T? rememberedManifest<T>(String? json, T Function(Map<String, dynamic>) parse) {
  if (json == null) return null;
  try {
    return parse(jsonDecode(json) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

/// Merkt ein frisches Manifest, nur wenn es sich geändert hat (einmal im
/// Monat, nicht bei jedem Neubau des Stils). Beide Engines schreiben
/// dieselben Schlüssel mit demselben Text.
void rememberManifest(String? before, Map<String, dynamic> manifest, Future<void> Function(String) write) {
  final json = jsonEncode(manifest);
  if (json == before) return;
  unawaited(write(json).catchError((Object e, StackTrace s) => logError('Karten-Manifest merken', e, s)));
}

/// Öffnet ein Archiv des Hosts für flutter_map — mit Speicher gesehener
/// Kacheln, wo es einen gibt (#155). Ohne frisches Manifest ([fresh]
/// false) oder wenn das Archiv nicht aufgeht, liefert der Speicher allein
/// ([SeenTilesVectorTileProvider.seenOnly]). Null: nichts zu zeigen.
Future<VectorTileProvider?> openHostArchive(
  Ref ref, {
  required String file,
  required Uri uri,
  required bool fresh,
  required int minZoom,
  required int maxZoom,
  required String label,
}) async {
  final store = ref.watch(seenTileStoreProvider);
  PmTilesVectorTileProvider? online;
  if (fresh) {
    try {
      online = await ref.watch(onlineArchiveOpenerProvider)(uri);
    } catch (e, s) {
      if (!looksOffline(e)) logError(label, e, s);
      if (store == null) return null;
    }
  }
  if (store == null) {
    if (online != null) ref.onDispose(online.close);
    return online;
  }
  final provider = SeenTilesVectorTileProvider(
      archive: file, store: store, online: online, minZoom: minZoom, maxZoom: maxZoom);
  ref.onDispose(provider.close);
  return provider;
}

/// Ob eine Quelle nur gesehene Kacheln liefert — dann liegt die Übersicht
/// darunter (dieselbe Regel wie im MapLibre-Stil: Übersicht, solange kein
/// FRISCHES Manifest da ist). Bei mehreren Regionen (#220) zählt jede.
bool seenOnlyProviders(TileProviders providers) => providers.tileProviderBySource.values.any((p) =>
    (p is SeenTilesVectorTileProvider && p.seenOnly) ||
    (p is RegionTileProvider &&
        p.parts.any((part) => part.provider is SeenTilesVectorTileProvider &&
            (part.provider as SeenTilesVectorTileProvider).seenOnly)));

/// Mehrere Regionen zu EINER Quelle (#220): mit nur einer bekannten
/// Region ihr Archiv selbst — die Karte bis 0.103 —, sonst der Verteiler
/// nach Lage. Null ohne ein einziges Archiv.
VectorTileProvider? regionSource(
    List<MapRegion> regions, List<({MapRegion region, VectorTileProvider? provider})> opened) {
  final parts = [
    for (final o in opened)
      if (o.provider case final provider?) (box: o.region.box, provider: provider),
  ];
  if (parts.isEmpty) return null;
  if (regions.length == 1) return parts.single.provider;
  return RegionTileProvider(parts);
}

/// Das Archiv der Online-Karte EINER Region für flutter_map — frisch,
/// im Browser sonst das gemerkte (#155, je Region). Null: nichts zu zeigen.
Future<VectorTileProvider?> _regionMapArchive(Ref ref, MapRegion region) async {
  final fresh = await ref.watch(regionMapManifestProvider(region).future);
  MapManifest? manifest = fresh;
  if (ref.watch(seenTileStoreProvider) != null) {
    final settings = ref.watch(settingsProvider);
    if (region.isDach) {
      if (fresh != null) {
        rememberManifest(settings.seenMapManifest, fresh.toJson(), settings.setSeenMapManifest);
      }
      manifest ??= rememberedManifest(settings.seenMapManifest, MapManifest.fromJson);
    } else {
      if (fresh != null) rememberRegionManifest(settings, region, RegionLayer.map, fresh.toJson());
      manifest ??= rememberedRegionManifest(settings, region, RegionLayer.map, MapManifest.fromJson);
    }
  }
  if (manifest == null) return null;
  return openHostArchive(ref,
      // Der Schlüssel der gesehenen Kacheln trägt den Ordner mit: Zwei
      // Regionen dürfen gleich datierte Dateien haben.
      file: '${manifest.dir}${manifest.file}',
      uri: manifest.archiveUri,
      fresh: fresh != null,
      minZoom: 0,
      maxZoom: manifest.maxZoom,
      label: 'Online-Karte öffnen');
}

/// Die Online-Vektorkarte für die flutter_map-Engine: Archiv vom Host
/// plus das Thema OHNE `background`-Ebene, damit die Übersicht darunter
/// durchscheint, wo eine Kachel (noch) fehlt. Null, solange es kein
/// Manifest gibt oder das Archiv nicht aufgeht — dann bleibt die
/// Übersicht die Karte, ohne Fehlermeldung.
///
/// Im Browser (#155) mit Speicher gesehener Kacheln: Ohne frisches
/// Manifest nimmt sie das gemerkte und zeigt, was liegt, über der
/// Übersicht.
///
/// Je Region ein Archiv (#220), zu einer Quelle verteilt nach Lage
/// ([regionSource]).
final onlineMapStyleProvider = FutureProvider<BaseMapStyle?>((ref) async {
  try {
    // DACH sofort, die übrigen, sobald der Index da ist — DACH wartet nie
    // auf den Index.
    final (dach, regions) = await (_regionMapArchive(ref, kDachRegion), regionsPatiently(ref)).wait;
    final opened = [
      (region: kDachRegion, provider: dach),
      for (final region in regions)
        if (!region.isDach) (region: region, provider: await _regionMapArchive(ref, region)),
    ];
    final archive = regionSource(regions, opened);
    if (archive == null) return null;
    final theme = await ref.watch(baseThemeWithoutBackgroundProvider.future);
    return BaseMapStyle(theme: theme, tileProviders: TileProviders({'protomaps': archive}));
  } catch (e, s) {
    if (!looksOffline(e)) logError('Online-Karte öffnen', e, s);
    return null;
  }
});
