// Regionen des Kartenhosts (#220, `docs/konzept-regionen.md` Abschnitt 5):
// Eine Region ist ein Rahmen mit eigenen Archiven — Karte, Höhen, Wege,
// Orte. Welche es gibt, sagt der Index `regions.json`; die App wählt die
// Region nach der Lage (Betreiber, 2026-10-08: „automatisch, kein
// Wähler"). DACH kennt sie OHNE Index: Ihre Pfade liegen seit 0.18.0 an
// der Wurzel, und ohne Index (kein Empfang, Host weg, fremdes Format)
// ist die App, was sie bis 0.103 war.
//
// Drei Regeln:
// - **DACH kommt aus dem Binary, nie aus dem Index.** Die Zeile `dach`
//   im Index wird geprüft und dann übergangen; für DACH bleiben die
//   bisherigen Provider (`mapManifestProvider` & Co.) die Quelle. Alles
//   andere hängt sich daneben.
// - **Der Index ist streng.** Jeder Pfad wird gegen die eine Form
//   geprüft, die `tool/regions.py` schreibt — er wird zu einer Adresse.
//   Passt eine Zeile nicht, gilt der ganze Index nicht (dann der
//   gemerkte, sonst DACH allein): Lieber eine Region zu wenig als eine
//   halb gelesene.
// - **Regionen überlappen nie** (geprüft wie im Werkzeug). Eine Kachel
//   gehört deshalb der ersten Region, deren Rahmen sie schneidet.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../../core/connectivity.dart';
import '../../core/errors.dart';
import '../../core/line_geometry.dart';
import '../../core/patience.dart';
import '../../core/settings.dart';
import 'map_providers.dart';
import 'online_map.dart';
import 'poi.dart';
import 'way_layer.dart';

/// Die Ebenen einer Region, wie sie im Index heißen.
enum RegionLayer { map, heights, ways, pois, overview }

const kDachRegionId = 'dach';

/// Eine Region des Kartenhosts.
class MapRegion {
  const MapRegion({
    required this.id,
    required this.name,
    required this.box,
    required this.dir,
    required this.manifests,
  });

  /// 2–8 Kleinbuchstaben (`dach`, `ca`).
  final String id;

  /// Der Name für die Oberfläche („Kanada").
  final String name;

  /// Der Rahmen in Grad.
  final LatBox box;

  /// Der Ordner auf dem Host: leer für DACH, sonst `<id>/`.
  final String dir;

  /// Die Manifeste, die es gibt, relativ zum Host.
  final Map<RegionLayer, String> manifests;

  bool get isDach => id == kDachRegionId;

  Uri? manifestUri(RegionLayer layer) =>
      manifests[layer] == null ? null : Uri.parse('$kMapTilesBase/${manifests[layer]}');

  bool contains(LatLng p) =>
      p.latitude >= box.s && p.latitude <= box.n && p.longitude >= box.w && p.longitude <= box.e;

  /// Schneidet [o] den Rahmen (Rand eingeschlossen)?
  bool intersects(LatBox o) => !(o.e < box.w || o.w > box.e || o.n < box.s || o.s > box.n);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'bbox': [box.w, box.s, box.e, box.n],
        'dir': dir,
        for (final layer in RegionLayer.values) layer.name: manifests[layer],
      };

  @override
  bool operator ==(Object other) => other is MapRegion && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;

  @override
  String toString() => 'MapRegion($id)';
}

/// DACH, wie die App es seit 0.18.0 kennt: Pfade an der Wurzel. Der
/// Rahmen ist der aus `tool/regions.json` (`--self-test` dort hält ihn
/// gegen die Workflows fest, `test/map/map_regions_test.dart` gegen
/// diese Zeile).
const kDachRegion = MapRegion(
  id: kDachRegionId,
  name: 'DACH',
  box: LatBox(45.5, 5.5, 55.5, 17.5),
  dir: '',
  manifests: {
    RegionLayer.map: 'dach.json',
    RegionLayer.heights: 'heights.json',
    RegionLayer.ways: 'ways.json',
    RegionLayer.pois: 'pois.json',
  },
);

/// Wo ein Manifest einer Region liegen MUSS — dieselbe Regel wie
/// `manifest_path` in `tool/regions.py`.
String? expectedManifestPath(String id, RegionLayer layer) {
  if (id == kDachRegionId) return kDachRegion.manifests[layer];
  return '$id/${layer.name}.json';
}

/// Die Regionen AUSSER DACH aus dem Index; wirft bei allem, was nicht
/// passt.
List<MapRegion> parseRegionIndex(Object? json) {
  if (json is! Map || json['format'] != 1) throw const FormatException('Regionen-Index: Format');
  final rows = json['regions'];
  if (rows is! List) throw const FormatException('Regionen-Index: keine Liste');
  final ids = <String>{};
  final out = <MapRegion>[];
  for (final row in rows) {
    if (row is! Map) throw const FormatException('Regionen-Index: Zeile');
    final id = row['id'];
    if (id is! String || !RegExp(r'^[a-z]{2,8}$').hasMatch(id) || !ids.add(id)) {
      throw FormatException('Regionen-Index: Kennung $id');
    }
    final name = row['name'];
    if (name is! String || name.trim().isEmpty) throw FormatException('Regionen-Index: Name von $id');
    final bbox = row['bbox'];
    if (bbox is! List || bbox.length != 4 || bbox.any((v) => v is! num)) {
      throw FormatException('Regionen-Index: Rahmen von $id');
    }
    final [w, s, e, n] = [for (final v in bbox) (v as num).toDouble()];
    if (!(w >= -180 && e <= 180 && s >= -90 && n <= 90 && w < e && s < n)) {
      throw FormatException('Regionen-Index: Rahmen von $id');
    }
    if (row['dir'] != (id == kDachRegionId ? '' : '$id/')) {
      throw FormatException('Regionen-Index: Ordner von $id');
    }
    final manifests = <RegionLayer, String>{};
    for (final layer in RegionLayer.values) {
      final path = row[layer.name];
      if (path == null) continue;
      if (path != expectedManifestPath(id, layer)) {
        throw FormatException('Regionen-Index: ${layer.name} von $id');
      }
      manifests[layer] = path as String;
    }
    if (!manifests.containsKey(RegionLayer.map)) throw FormatException('Regionen-Index: $id ohne Karte');
    // DACH liegt im Binary; die Zeile ist geprüft, gilt aber nicht.
    if (id == kDachRegionId) continue;
    final region = MapRegion(id: id, name: name, box: LatBox(s, w, n, e), dir: '$id/', manifests: manifests);
    for (final other in [kDachRegion, ...out]) {
      if (other.intersects(region.box)) throw FormatException('Regionen-Index: $id überlappt ${other.id}');
    }
    out.add(region);
  }
  return out;
}

/// Die Regionen außer DACH als Text zum Merken — liest sich mit
/// [parseRegionIndex] zurück.
String encodeRegions(List<MapRegion> extra) =>
    jsonEncode({'format': 1, 'regions': [for (final r in extra) r.toJson()]});

List<MapRegion>? rememberedRegions(String? json) {
  if (json == null) return null;
  try {
    return parseRegionIndex(jsonDecode(json));
  } catch (_) {
    // Ein gemerkter Index, den diese Fassung nicht mehr liest, ist keiner.
    return null;
  }
}

/// Holt den Index; null bei 404 (es gibt keinen — DACH allein), wirft bei
/// allem anderen.
Future<String?> fetchRegionsIndex() async {
  final response = await http.get(Uri.parse(kRegionsIndexUrl)).timeout(kMapManifestTimeout);
  if (response.statusCode == 404) return null;
  if (response.statusCode != 200) throw http.ClientException('Regionen-Index: HTTP ${response.statusCode}');
  return utf8.decode(response.bodyBytes);
}

/// Die Naht für Tests (kein Netz); der Harness setzt sie auf null.
final regionsLoaderProvider = Provider<Future<String?> Function()>((ref) => fetchRegionsIndex);

/// Alle Regionen, DACH zuerst. Ohne Empfang oder wenn der Index nicht
/// kommt: der gemerkte, sonst DACH allein. Hängt am Empfang, damit seine
/// Rückkehr neu fragt.
final mapRegionsProvider = FutureProvider<List<MapRegion>>((ref) async {
  final settings = ref.watch(settingsProvider);
  List<MapRegion> known() => [kDachRegion, ...?rememberedRegions(settings.seenRegions)];
  if (ref.watch(noConnectivityProvider)) return known();
  try {
    final text = await ref.watch(regionsLoaderProvider)();
    if (text == null) return const [kDachRegion];
    final extra = parseRegionIndex(jsonDecode(text));
    final json = encodeRegions(extra);
    if (json != settings.seenRegions) {
      unawaited(settings.setSeenRegions(json).catchError((Object e, StackTrace s) => logError('Regionen merken', e, s)));
    }
    return [kDachRegion, ...extra];
  } catch (e, s) {
    // Ein Funkloch, ein fehlender Index (HTTP-Status) oder ein Format, das
    // diese Fassung nicht kennt, sind kein Bericht wert — sonst stünde
    // jede alte Installation im Wochendigest, sobald der Index wächst.
    if (!looksOffline(e) && e is! FormatException && e is! http.ClientException) {
      logError('Regionen laden', e, s);
    }
    return known();
  }
});

/// Die Regionen, ohne die Karte auf den Index warten zu lassen (#183):
/// Kommt er nicht binnen [patience], gelten die gemerkten (sonst DACH
/// allein), und ein später, ANDERER Index baut den Aufrufer neu. Für die
/// Stile beider Engines — dort zeichnet nichts, bevor sie fertig sind.
Future<List<MapRegion>> regionsPatiently(Ref ref, {Duration patience = kMapManifestPatience}) async {
  var current = true;
  ref.onDispose(() => current = false);
  final future = ref.watch(mapRegionsProvider.future);
  var arrived = false;
  final watched = future.whenComplete(() => arrived = true);
  final value = await withinOrNull(watched, patience);
  if (value != null) return value;
  final fallback = [kDachRegion, ...?rememberedRegions(ref.read(settingsProvider).seenRegions)];
  if (!arrived) {
    unawaited(watched.then((late) {
      if (current && !listEquals(late, fallback)) ref.invalidateSelf();
    }));
  }
  return fallback;
}

/// Der Rahmen einer Kachel (Web-Mercator) in Grad.
LatBox tileBox(int z, int x, int y) {
  final n = 1 << z;
  double lat(int row) => math.atan((math.exp(math.pi * (1 - 2 * row / n)) - math.exp(-math.pi * (1 - 2 * row / n))) / 2) * 180 / math.pi;
  return LatBox(lat(y + 1), x / n * 360 - 180, lat(y), (x + 1) / n * 360 - 180);
}

/// Die Archive mehrerer Regionen als EINE Kachelquelle für flutter_map
/// (#220): Je Kachel fragt die erste Region, deren Rahmen sie schneidet;
/// keine ⇒ 404 wie eine Kachel außerhalb. So bleibt es eine Schicht mit
/// einem Thema, und in Kanada geht keine Anfrage an das DACH-Archiv.
class RegionTileProvider extends VectorTileProvider {
  RegionTileProvider(this.parts) : assert(parts.isNotEmpty);

  final List<({LatBox box, VectorTileProvider provider})> parts;

  VectorTileProvider? providerFor(TileIdentity tile) {
    final box = tileBox(tile.z, tile.x, tile.y);
    for (final p in parts) {
      if (!(box.e < p.box.w || box.w > p.box.e || box.n < p.box.s || box.s > p.box.n)) return p.provider;
    }
    return null;
  }

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    final provider = providerFor(tile);
    if (provider == null || tile.z < provider.minimumZoom || tile.z > provider.maximumZoom) {
      throw ProviderException(
          message: 'Kachel ${tile.key()} in keiner Region', retryable: Retryable.none, statusCode: 404);
    }
    return await provider.provide(tile);
  }

  @override
  int get minimumZoom => parts.map((p) => p.provider.minimumZoom).reduce(math.min);

  @override
  int get maximumZoom => parts.map((p) => p.provider.maximumZoom).reduce(math.max);

  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;

  @override
  TileProviderType get type => TileProviderType.vector;
}

/// Die Region, in der [p] liegt — null außerhalb aller.
MapRegion? regionAt(List<MapRegion> regions, LatLng p) {
  for (final r in regions) {
    if (r.contains(p)) return r;
  }
  return null;
}

/// Die erste Region, deren Rahmen [box] schneidet — null außerhalb aller.
MapRegion? regionFor(List<MapRegion> regions, LatBox box) {
  for (final r in regions) {
    if (r.intersects(box)) return r;
  }
  return null;
}

/// Holt eine JSON-Datei vom Host; null bei 404 (noch kein Bau), wirft bei
/// allem anderen.
Future<Map<String, dynamic>?> fetchHostJson(Uri uri) async {
  final response = await http.get(uri).timeout(kMapManifestTimeout);
  if (response.statusCode == 404) return null;
  if (response.statusCode != 200) throw http.ClientException('${uri.path}: HTTP ${response.statusCode}', uri);
  return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
}

/// Die Manifeste der Regionen außer DACH — die Naht für Tests. Der
/// Harness setzt sie auf null.
final regionManifestLoaderProvider =
    Provider<Future<Map<String, dynamic>?> Function(Uri)>((ref) => fetchHostJson);

/// Ein Manifest einer Region außer DACH über [load]; null ohne Ebene,
/// ohne Bau, bei fremdem Format oder Netzfehler. Gemeldet wird nur, was
/// nicht danach aussieht.
Future<T?> loadRegionManifest<T>(
  Future<Map<String, dynamic>?> Function(Uri) load,
  MapRegion region,
  RegionLayer layer,
  T Function(Map<String, dynamic> json, String dir) parse,
) async {
  final uri = region.manifestUri(layer);
  if (uri == null) return null;
  try {
    final json = await load(uri);
    return json == null ? null : parse(json, region.dir);
  } catch (e, s) {
    if (!looksOffline(e) && e is! FormatException && e is! http.ClientException) {
      logError('Manifest ${layer.name} der Region ${region.id} laden', e, s);
    }
    return null;
  }
}

MapManifest _map(Map<String, dynamic> j, String dir) => MapManifest.fromJson(j, dir: dir);
WaysManifest _ways(Map<String, dynamic> j, String dir) => WaysManifest.fromJson(j, dir: dir);
HeightsManifest _heights(Map<String, dynamic> j, String dir) => HeightsManifest.fromJson(j, dir: dir);
PoiManifest _pois(Map<String, dynamic> j, String dir) => PoiManifest.fromJson(j, dir: dir);
OverviewManifest _overview(Map<String, dynamic> j, String dir) => OverviewManifest.fromJson(j, dir: dir);

/// Das Karten-Manifest einer Region — für DACH der bisherige Provider.
final regionMapManifestProvider = FutureProvider.family<MapManifest?, MapRegion>((ref, region) {
  if (region.isDach) return ref.watch(mapManifestProvider.future);
  if (ref.watch(noConnectivityProvider)) return Future.value(null);
  return loadRegionManifest(ref.watch(regionManifestLoaderProvider), region, RegionLayer.map, _map);
});

/// Das Wege-Manifest einer Region für die EBENE — null, solange sie aus
/// ist (für DACH der bisherige Provider, der dieselbe Regel hat).
final regionWaysManifestProvider = FutureProvider.family<WaysManifest?, MapRegion>((ref, region) {
  if (region.isDach) return ref.watch(waysManifestProvider.future);
  if (!ref.watch(wayLayerEnabledProvider) || ref.watch(noConnectivityProvider)) return Future.value(null);
  return loadRegionManifest(ref.watch(regionManifestLoaderProvider), region, RegionLayer.ways, _ways);
});

/// Das Höhen-Manifest einer Region — für DACH der bisherige Provider.
final regionHeightsManifestProvider = FutureProvider.family<HeightsManifest?, MapRegion>((ref, region) {
  if (region.isDach) return ref.watch(heightsManifestProvider.future);
  if (ref.watch(noConnectivityProvider)) return Future.value(null);
  return loadRegionManifest(ref.watch(regionManifestLoaderProvider), region, RegionLayer.heights, _heights);
});

/// Die Manifeste einer Region außer DACH für einen Bereich oder das
/// Nachladen — gelesen, nicht beobachtet, und die Wege unabhängig vom
/// Schalter (wie für DACH, Betreiber 2026-10-08).
class RegionManifests {
  RegionManifests(this._load, this.region) : assert(!region.isDach);

  final Future<Map<String, dynamic>?> Function(Uri) _load;
  final MapRegion region;

  Future<MapManifest?> map() => loadRegionManifest(_load, region, RegionLayer.map, _map);
  Future<WaysManifest?> ways() => loadRegionManifest(_load, region, RegionLayer.ways, _ways);
  Future<HeightsManifest?> heights() => loadRegionManifest(_load, region, RegionLayer.heights, _heights);
  Future<PoiManifest?> pois() => loadRegionManifest(_load, region, RegionLayer.pois, _pois);

  /// Die Übersicht der Region (Schritt 4) — null, wenn der Index keine
  /// nennt oder noch keine gebaut ist.
  Future<OverviewManifest?> overview() => loadRegionManifest(_load, region, RegionLayer.overview, _overview);
}

/// „Gesehenes bleibt liegen" je Region (#155): das gemerkte Manifest
/// [layer] der Region außer DACH, mit derselben Prüfung wie vom Host.
T? rememberedRegionManifest<T>(Settings settings, MapRegion region, RegionLayer layer,
    T Function(Map<String, dynamic> json, {String dir}) parse) {
  final all = _seenRegionManifests(settings);
  final json = all['${region.id}/${layer.name}'];
  if (json is! Map<String, dynamic>) return null;
  try {
    return parse(json, dir: region.dir);
  } catch (_) {
    return null;
  }
}

/// Merkt ein frisches Manifest einer Region außer DACH, nur wenn es sich
/// geändert hat.
void rememberRegionManifest(Settings settings, MapRegion region, RegionLayer layer, Map<String, dynamic> manifest) {
  final all = _seenRegionManifests(settings);
  final key = '${region.id}/${layer.name}';
  if (jsonEncode(all[key]) == jsonEncode(manifest)) return;
  all[key] = manifest;
  unawaited(settings
      .setSeenRegionManifests(jsonEncode(all))
      .catchError((Object e, StackTrace s) => logError('Manifest einer Region merken', e, s)));
}

Map<String, dynamic> _seenRegionManifests(Settings settings) {
  final text = settings.seenRegionManifests;
  if (text == null) return {};
  try {
    return Map<String, dynamic>.of(jsonDecode(text) as Map<String, dynamic>);
  } catch (_) {
    return {};
  }
}
