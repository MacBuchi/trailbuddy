// Die I/O-Schicht über dem puren Style-Composer: materialisiert Glyphs und
// Übersichtskarte aus den Assets, liest den Zoombereich aus dem
// Archiv-Header und setzt daraus das Style-Dokument der MapLibre-Engine
// zusammen.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pmtiles/pmtiles.dart';

import '../../../core/app_colors.dart';
import '../../../core/connectivity.dart';
import '../../../core/errors.dart';
import '../../../core/patience.dart';
import '../../../core/settings.dart';
import '../../offline_areas/area_providers.dart';
import '../../official/official_trails_source.dart';
import '../base_map_providers.dart';
import '../online_map.dart';
import '../way_layer.dart';
import 'map_style_composer.dart';

/// Die fünf Unicode-Bereiche, die für deutsche Kartenbeschriftung reichen.
const _glyphRanges = ['0-255', '256-511', '512-767', '7680-7935', '8192-8447'];
const _fontStacks = ['noto-sans-regular', 'noto-sans-medium'];

/// Alle Plattenzugriffe des Style-Providers — als Klasse, damit Tests sie
/// durch eine Fake ersetzen können; echte Dateien und Platform-Channels
/// gibt es im Widget-Test nicht.
class MapLibreStyleIo {
  /// Der erzeugte Protomaps-Basis-Style (dasselbe Asset wie beim
  /// Canvas-Renderer — eine Quelle der Wahrheit für beide Engines).
  Future<String> loadBaseStyle() => rootBundle.loadString(kMapStyleAsset);

  /// Kopiert ein Asset ins App-Verzeichnis, wenn es dort fehlt oder eine
  /// andere Größe hat — MapLibre kann keine `asset://`-URLs lesen (kein
  /// Byte-Range auf Assets), es braucht echte Dateien.
  Future<File> _materialize(String assetPath, File target) async {
    final data = await rootBundle.load(assetPath);
    if (!await target.exists() || await target.length() != data.lengthInBytes) {
      await target.create(recursive: true);
      await target.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    }
    return target;
  }

  /// Materialisiert die DACH-Übersicht und liefert ihren Pfad. Derselbe
  /// Zielpfad wie `openBundledOverview` beim Canvas-Renderer — beide
  /// Engines teilen sich die eine Datei auf Platte.
  Future<String> materializeOverview() async {
    final dir = await getApplicationSupportDirectory();
    final file = await _materialize(
        kOverviewAsset, File('${dir.path}/offline_maps/overview_dach.pmtiles'));
    return file.path;
  }

  /// Materialisiert die Glyph-PBFs und liefert die Glyphs-URL-Vorlage.
  Future<String> materializeGlyphs() async {
    final dir = await getApplicationSupportDirectory();
    for (final stack in _fontStacks) {
      for (final range in _glyphRanges) {
        await _materialize('assets/map_glyphs/$stack/$range.pbf',
            File('${dir.path}/map_glyphs/$stack/$range.pbf'));
      }
    }
    return 'file://${dir.path}/map_glyphs/{fontstack}/{range}.pbf';
  }

  /// Liest min/max Zoom aus dem PMTiles-ARCHIV-HEADER — nie aus den
  /// eingebetteten Metadaten (siehe MapStyleSource).
  Future<({int min, int max})> readZoomRange(String path) async {
    final archive = await PmTilesArchive.fromFile(File(path));
    try {
      return (min: archive.header.minZoom, max: archive.header.maxZoom);
    } finally {
      await archive.close();
    }
  }
}

final maplibreStyleIoProvider = Provider<MapLibreStyleIo>((ref) => MapLibreStyleIo());

/// CSS-Farbwert für den Style — aus derselben Konstante wie die
/// flutter_map-Engine, damit die Landflächen beider Engines gleich aussehen.
String cssColor(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Das fertige Style-Dokument — oder null, wenn etwas fehlt: Dann fällt die
/// MapLibre-Engine auf flutter_map zurück (maplibre_map_view.dart).
///
/// Die Quellen-Wahl folgt EXAKT der flutter_map-Engine, von unten nach
/// oben: die Übersicht, wenn kein Empfang besteht oder es kein Manifest
/// gibt; die Online-Karte vom Host (`pmtiles://https://…`, Range-Anfragen
/// macht maplibre-native selbst), sobald das Manifest da ist; und IMMER
/// die gespeicherten Bereiche zuoberst, je Bereich eine `file://`-Quelle
/// (#82, `area_providers.dart`), darüber die Wege (#212, `way_layer.dart`)
/// vom Host und darüber die Wege der Bereiche, je Bereich eine
/// `file://`-Quelle — unter den Trails, die als eigene Ebenen danach kommen. Ein Wechsel erzeugt einen neuen
/// Style-String; die Engine spielt ihn per `setStyle` ein.
///
/// „Gesehenes bleibt liegen" (#155): Kommt kein frisches Manifest (kein
/// Empfang, ein Balken ohne Daten, Host weg), nennt der Stil die Archive
/// aus dem zuletzt GEMERKTEN Manifest, über der Übersicht. MapLibre liest
/// dann aus seinem Zwischenspeicher, was schon einmal geladen war (seit
/// 13.3 auch PMTiles-Bereiche, `android/app/build.gradle.kts`); wo nichts
/// liegt, scheint die Übersicht durch.
final maplibreStyleProvider = FutureProvider<String?>((ref) async {
  final noConnectivity = ref.watch(noConnectivityProvider);
  // Nicht unbegrenzt auf das Manifest warten (#183): MapLibre zeichnet
  // erst mit dem Stil, und bei einem Balken ohne Daten stand die Karte
  // sonst leer, bis der Abruf aufgab. Nach [kMapManifestPatience] kommt
  // die Übersicht, und ein spätes Manifest baut den Stil neu.
  //
  // Beobachtet wird das FUTURE, nicht der Zustand: Der wechselt beim
  // Eintreffen, der Stil baute dann mitten im ersten Aufbau neu — und
  // dessen `.future` erfüllte sich ohne Zuhörer nie (im Test gefunden).
  //
  // Dieselbe Geduld gilt für die Wege (#212), gleichzeitig gemessen: Ein
  // langsamer Wege-Host hält die Karte nicht länger auf als die Karte
  // selbst, und ein spätes Wege-Manifest baut den Stil neu.
  var current = true;
  ref.onDispose(() => current = false);
  Future<T?> patiently<T>(Future<T?> future) {
    var arrived = false;
    final watched = future.whenComplete(() => arrived = true);
    return withinOrNull(watched, kMapManifestPatience).then((value) {
      if (!arrived) {
        unawaited(watched.then((late) {
          if (current && late != null) ref.invalidateSelf();
        }));
      }
      return value;
    });
  }

  final manifestWait = patiently(ref.watch(mapManifestProvider.future));
  final waysWait = patiently(ref.watch(waysManifestProvider.future));
  final fresh = await manifestWait;
  final freshWays = await waysWait;
  final settings = ref.watch(settingsProvider);
  final manifest = fresh ?? _remembered(settings.seenMapManifest, MapManifest.fromJson);
  final ways = freshWays ??
      (ref.watch(wayLayerEnabledProvider)
          ? _remembered(settings.seenWaysManifest, WaysManifest.fromJson)
          : null);
  if (fresh != null) {
    _remember(settings.seenMapManifest, fresh.toJson(), settings.setSeenMapManifest);
  }
  if (freshWays != null) {
    _remember(settings.seenWaysManifest, freshWays.toJson(), settings.setSeenWaysManifest);
  }
  final io = ref.watch(maplibreStyleIoProvider);
  // Die Quellenangabe der Behörden — nur solange die Ebene an ist und
  // eine ihrer Regionen geladen. `select` auf den Text: Der Controller
  // ändert sich bei jedem Nachladen, der Text selten.
  final officialCredits = ref.watch(officialTrailsEnabledProvider)
      ? ref.watch(officialTrailsControllerProvider.select((s) => [
            for (final src in s.loadedSources) '${src.attribution} (${src.license})',
          ].join('\u0000')))
      : '';
  try {
    final base = jsonDecode(await io.loadBaseStyle()) as Map<String, dynamic>;
    final glyphsUrl = await io.materializeGlyphs();

    final sources = <MapStyleSource>[];
    // Die Übersicht liegt unter allem, solange kein FRISCHES Manifest da
    // ist — auch unter einem gemerkten: Dessen Kacheln kommen nur aus dem
    // Zwischenspeicher, und wo keine liegt, wäre sonst nackter Landton.
    if (noConnectivity || fresh == null) {
      final overviewPath = await io.materializeOverview();
      final overviewZoom = await io.readZoomRange(overviewPath);
      sources.add(MapStyleSource(
        id: 'overview',
        url: 'file://$overviewPath',
        minZoom: overviewZoom.min,
        maxZoom: overviewZoom.max,
      ));
    }
    if (manifest != null) {
      // Frisch oder gemerkt (#155), siehe oben.
      // Zoombereich aus dem Manifest, nicht aus dem Archiv-Header: Den
      // zu lesen wäre eine Range-Anfrage, die die Engine gleich selbst
      // macht. `map-data.yml` schreibt beide aus derselben Bestellung.
      sources.add(MapStyleSource(
        id: 'online',
        url: manifest.archiveUri.toString(),
        minZoom: 0,
        maxZoom: manifest.maxZoom,
      ));
    }
    // Die gespeicherten Bereiche (Zoom 8 aufwärts) zuoberst, mit und ohne
    // Empfang (#82): Ihre deckende `earth`-Fläche verdeckt darunter die
    // Online-Karte, wo eine Kachel liegt — auch dann, wenn die Online-
    // Kachel im Funkloch nie kommt oder MapLibre eine gröbere aus dem
    // Zwischenspeicher darüber streckt. Wo keine liegt, liefert das
    // Archiv nichts, und die Online-Karte scheint durch.
    // Zoombereich aus dem Index, nicht aus dem Header: Der Download hat
    // beide aus demselben Plan geschrieben.
    // Ein Bereich, der nicht lesbar ist, nimmt der Karte nicht den Rest:
    // gemeldet, und weiter ohne ihn.
    try {
      for (final entry in await ref.watch(areaArchivePathsProvider.future)) {
        sources.add(MapStyleSource(
          id: 'area-${entry.area.id}',
          url: 'file://${entry.path}',
          minZoom: entry.area.minZoom,
          maxZoom: entry.area.maxZoom,
        ));
      }
    } catch (e, stackTrace) {
      logError('Bereiche für den Style lesen', e, stackTrace);
    }
    // Die Wege der Bereiche über denen vom Host, mit und ohne Empfang —
    // dieselbe Regel wie bei der Karte: Ihre Bänder decken die Striche
    // darunter, wo derselbe Weg liegt.
    final areaWays = <MapStyleOverlay>[];
    try {
      for (final entry in await ref.watch(areaWaysPathsProvider.future)) {
        final id = '$kWaysSourceId-area-${entry.area.id}';
        areaWays.add(MapStyleOverlay(
          source: MapStyleSource(id: id, url: 'file://${entry.path}', minZoom: kWaysZoom, maxZoom: kWaysZoom),
          layers: wayStyleLayers(id, dashes: true),
        ));
      }
    } catch (e, stackTrace) {
      logError('Wege der Bereiche für den Style lesen', e, stackTrace);
    }

    return composeMapLibreStyle(
      baseStyle: base,
      glyphsUrl: glyphsUrl,
      backgroundColor: cssColor(AppColors.mapBackground.toARGB32()),
      sources: sources,
      overlays: [
        if (ways != null)
          MapStyleOverlay(
            source: MapStyleSource(
              id: kWaysSourceId,
              url: ways.archiveUri.toString(),
              minZoom: kWaysZoom,
              maxZoom: kWaysZoom,
            ),
            layers: wayStyleLayers(kWaysSourceId, dashes: true),
          ),
        ...areaWays,
      ],
      extraAttributions: officialCredits.isEmpty ? const [] : officialCredits.split('\u0000'),
    );
  } catch (e, stackTrace) {
    logError('MapLibre-Style bauen', e, stackTrace);
    return null;
  }
});

/// Liest ein gemerktes Manifest (#155) — mit derselben Prüfung wie vom
/// Host. Was nicht mehr passt (ein anderes Wege-Format nach einem Update),
/// heißt still „keins".
T? _remembered<T>(String? json, T Function(Map<String, dynamic>) parse) {
  if (json == null) return null;
  try {
    return parse(jsonDecode(json) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

/// Merkt ein frisches Manifest, nur wenn es sich geändert hat (einmal im
/// Monat, nicht bei jedem Neubau des Stils).
void _remember(String? before, Map<String, dynamic> manifest, Future<void> Function(String) write) {
  final json = jsonEncode(manifest);
  if (json == before) return;
  unawaited(write(json).catchError((Object e, StackTrace s) => logError('Karten-Manifest merken', e, s)));
}
