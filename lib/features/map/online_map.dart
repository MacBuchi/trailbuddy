import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vector_map_tiles/vector_map_tiles.dart' show TileProviders;

import '../../core/connectivity.dart';
import '../../core/errors.dart';
import '../offline_areas/height_tiles.dart' show kHeightGrid, kHeightTileZoom, kHeightsFormat;
import 'base_map_providers.dart';
import 'map_providers.dart';
import 'pmtiles_tile_provider.dart';

/// Das Manifest des Kartenhosts (`dach.json`, geschrieben von
/// `map-data.yml`): welche Datei gerade gilt und bis zu welchem Zoom sie
/// reicht.
class MapManifest {
  const MapManifest({
    required this.file,
    required this.maxZoom,
    required this.bytes,
    required this.sourceBuild,
  });

  final String file;
  final int maxZoom;
  final int bytes;

  /// Das Datum des Protomaps-Baus (`JJJJMMTT`) — der Kartenstand.
  final String sourceBuild;

  Uri get archiveUri => Uri.parse('$kMapTilesBase/$file');

  /// Liest das Manifest; wirft bei allem, was nicht passt. Der Dateiname
  /// wird geprüft, weil er zu einem Pfad wird.
  factory MapManifest.fromJson(Map<String, dynamic> j) {
    final file = j['file'] as String;
    if (!RegExp(r'^dach-\d{8}\.pmtiles$').hasMatch(file)) {
      throw FormatException('Unerwarteter Archivname: $file');
    }
    return MapManifest(
      file: file,
      maxZoom: j['maxzoom'] as int,
      bytes: j['bytes'] as int,
      sourceBuild: j['source_build'] as String,
    );
  }

  /// Zum Merken auf dem Gerät (#155) — liest sich mit [MapManifest.fromJson]
  /// zurück, mit derselben Prüfung.
  Map<String, dynamic> toJson() =>
      {'file': file, 'maxzoom': maxZoom, 'bytes': bytes, 'source_build': sourceBuild};
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
  });

  final String file;
  final int bytes;

  /// Das Datum des Baus (`JJJJMMTT`).
  final String build;

  Uri get archiveUri => Uri.parse('$kMapTilesBase/$file');

  factory HeightsManifest.fromJson(Map<String, dynamic> j) {
    final file = j['file'] as String;
    if (!RegExp(r'^heights-\d{8}\.pmtiles$').hasMatch(file)) {
      throw FormatException('Unerwarteter Archivname: $file');
    }
    if (j['format'] != kHeightsFormat || j['grid'] != kHeightGrid || j['zoom'] != kHeightTileZoom) {
      throw FormatException('Höhenformat ${j['format']}/${j['grid']}/${j['zoom']} unbekannt');
    }
    return HeightsManifest(file: file, bytes: j['bytes'] as int, build: j['build'] as String);
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

/// Die Online-Vektorkarte für die flutter_map-Engine: Archiv vom Host
/// plus das Thema OHNE `background`-Ebene, damit die Übersicht darunter
/// durchscheint, wo eine Kachel (noch) fehlt. Null, solange es kein
/// Manifest gibt oder das Archiv nicht aufgeht — dann bleibt die
/// Übersicht die Karte, ohne Fehlermeldung.
final onlineMapStyleProvider = FutureProvider<BaseMapStyle?>((ref) async {
  final manifest = await ref.watch(mapManifestProvider.future);
  if (manifest == null) return null;
  try {
    final archive = await ref.watch(onlineArchiveOpenerProvider)(manifest.archiveUri);
    ref.onDispose(archive.close);
    final theme = await ref.watch(baseThemeWithoutBackgroundProvider.future);
    return BaseMapStyle(theme: theme, tileProviders: TileProviders({'protomaps': archive}));
  } catch (e, s) {
    if (!looksOffline(e)) logError('Online-Karte öffnen', e, s);
    return null;
  }
});
