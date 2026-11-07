// „Unterwegs geladen" (#478): Was der Planer mit Empfang vom Host ergänzt
// (#187 — Wege-, Höhen- und Wege-Archiv-Kacheln bei z13), bleibt auf dem
// Gerät, statt mit der Sitzung zu verfallen. Die nächste Planung an
// derselben Stelle braucht dann kein Netz, und das Offline-Netz wächst
// mit dem, was man fährt — ohne eine Anfrage, die es heute nicht gibt
// (Betreiber, 2026-11-07: „möglichst wenig Cloudflare-R2-Traffic").
//
// Die Kacheln liegen im Kachelspeicher der Region (#229), mit ihrem Bau,
// wie die eines Bereichs. Gehalten werden sie von EINEM unsichtbaren
// Bereich je Region (`StoredArea.kept`, Form: Kachelmenge bei z13) — so
// nimmt das Löschen eines Bereichs oder der Radierer sie nicht als Waise
// mit (`tile_refs.dart`). Vier Regeln (Betreiber, 2026-11-07, im Issue):
// - **Aktualisiert beim Nutzen, nie im Ganzen**: Liest eine Planung mit
//   Empfang eine behaltene Kachel aus einem älteren Bau, holt sie genau
//   diese neu ([staleKeptTiles]); ohne Empfang gilt die alte.
//   „Aktualisieren" der Region lässt den Halter aus.
// - **Verdrängt nach letzter Nutzung**, nicht nach Ladezeit
//   ([StoredArea.keptUse]): Über [kKeptMaxBytes] fällt, was am längsten
//   nicht gebraucht wurde. Bereiche werden nie verdrängt, und eine Kachel,
//   die ein Bereich auch deckt, bleibt liegen.
// - **Kein eigenes Aussehen**: kein Rand auf der Karte, kein zweiter Typ
//   in der Liste — eine Zeile je Region in „Meine Bereiche" mit Größe und
//   „Leeren".
// - **Nur Routing-Kacheln** (z13): Der Halter holt nie andere Zoomstufen,
//   ist nie „unvollständig".
import 'dart:typed_data';

import '../../core/errors.dart';
import 'area_plan.dart';
import 'area_store.dart';
import 'tile_store.dart';

/// Die Kennung des Halters der Region [region].
String keptAreaId(String region) => '$kKeptAreaPrefix$region';

/// Der Halter der Region [region] in [areas]; null, wenn es keinen gibt.
StoredArea? keptAreaIn(Iterable<StoredArea> areas, String region) =>
    areas.where((a) => a.id == keptAreaId(region)).firstOrNull;

/// Was eine Planung für EINE z13-Kachel vom Host geholt hat — die Bytes,
/// wie sie im Archiv liegen (mit dessen Kompression), wie beim Speichern
/// eines Bereichs.
class KeptFetch {
  const KeptFetch(this.x, this.y, {required this.map, this.heights, this.ways});

  final int x;
  final int y;
  final Uint8List map;

  /// Die Höhenkachel dazu; null, wenn diese Planung keine geholt hat.
  final Uint8List? heights;

  /// Die Kachel des Wege-Archivs; null, wenn der Host dort nichts hat.
  final Uint8List? ways;

  int get key => TileSetShape.keyOf(x, y, kAreaShapeZoom);
  int get bytes => map.length + (heights?.length ?? 0) + (ways?.length ?? 0);
}

/// Die Bauten des Hosts, aus denen [KeptFetch] stammen.
typedef KeptBuilds = ({String map, String? heights, String? ways});

/// Die Schlüssel (bei [kAreaShapeZoom]), die ein Bereich der Region außer
/// dem Halter deckt — mit der ganzen Region `null` (alle).
Set<int>? _coveredByAreas(Iterable<StoredArea> areas, String region) {
  final out = <int>{};
  for (final a in areas) {
    if (a.kept || a.region != region) continue;
    if (a.shape is RegionShape) return null;
    if (a.minZoom > kAreaShapeZoom || a.maxZoom < kAreaShapeZoom) continue;
    out.addAll(a.shape.keysAt(kAreaShapeZoom));
  }
  return out;
}

/// Die behaltenen Kacheln im Rahmen [frame], die älter sind als der Bau
/// [mapBuild] des Hosts und die kein Bereich deckt (die holt
/// „Aktualisieren") — die nächsten zu [frame]s Reihenfolge zuerst, höchstens
/// [max]. Liest nur die Bauten dieser Kacheln. Wirft nie.
Future<List<TileXYZ>> staleKeptTiles({
  required TileStore tiles,
  required List<StoredArea> areas,
  required String region,
  required List<TileXYZ> frame,
  required String mapBuild,
  required int max,
}) async {
  final holder = keptAreaIn(areas, region);
  if (holder == null || max <= 0) return const [];
  final covered = _coveredByAreas(areas, region);
  if (covered == null) return const [];
  final mine = [
    for (final t in frame)
      if (holder.keptUse.containsKey(TileSetShape.keyOf(t.x, t.y, kAreaShapeZoom)) &&
          !covered.contains(TileSetShape.keyOf(t.x, t.y, kAreaShapeZoom)))
        t,
  ];
  if (mine.isEmpty) return const [];
  try {
    final builds = await tiles.builds(region, TileLayer.map, [for (final t in mine) tileIdOf(t)]);
    return [
      for (final t in mine)
        if (builds[tileIdOf(t)] case final b? when b.compareTo(mapBuild) < 0) t,
    ].take(max).toList();
  } catch (e, s) {
    logError('Behaltene Kacheln prüfen', e, s);
    return const [];
  }
}

/// Legt [fetched] in den Speicher der Region [region] und merkt sich, dass
/// die Planung [used] gebraucht hat (Schlüssel bei [kAreaShapeZoom]; nur
/// die des Halters zählen). Wächst der Halter über [maxBytes], fallen die
/// am längsten ungenutzten Kacheln, außer denen dieser Planung — aus dem
/// Speicher nur, wenn kein Bereich sie deckt.
///
/// Gibt zurück, ob die Liste der Bereiche neu zu lesen ist ([relist]: der
/// Halter ist neu oder hat erstmals Höhen oder Wege — Karte, Höhen- und
/// Wegeleser fragen den Speicher der Region nur dann) und wie viele
/// Kacheln fielen. Wirft bei einem Fehler des Speichers.
Future<({bool relist, int evicted})> keepOnlineTiles({
  required AreaStore areas,
  required TileStore tiles,
  required String region,
  required KeptBuilds builds,
  List<KeptFetch> fetched = const [],
  Iterable<int> used = const [],
  int maxBytes = kKeptMaxBytes,
  DateTime? now,
}) async {
  final all = await areas.list();
  final holder = keptAreaIn(all, region);
  final usedNow = {for (final k in used) if (holder?.keptUse.containsKey(k) ?? false) k};
  if (fetched.isEmpty && usedNow.isEmpty) return (relist: false, evicted: 0);

  if (fetched.isNotEmpty) {
    await tiles.put(region, TileLayer.map, [
      for (final f in fetched) StoreTile(kAreaShapeZoom, f.x, f.y, f.map, builds.map),
    ]);
    final hb = builds.heights;
    final heights = [
      for (final f in fetched)
        if (f.heights case final h? when hb != null) StoreTile(kAreaShapeZoom, f.x, f.y, h, hb),
    ];
    if (heights.isNotEmpty) await tiles.put(region, TileLayer.heights, heights);
    final wb = builds.ways;
    final ways = [
      for (final f in fetched)
        if (f.ways case final w? when wb != null) StoreTile(kAreaShapeZoom, f.x, f.y, w, wb),
    ];
    if (ways.isNotEmpty) await tiles.put(region, TileLayer.ways, ways);
  }

  // Die Reihenfolge der letzten Nutzung: Gebrauchtes und Geholtes ans Ende.
  final use = <int, int>{...?holder?.keptUse};
  for (final k in usedNow) {
    final b = use.remove(k)!;
    use[k] = b;
  }
  for (final f in fetched) {
    final old = use.remove(f.key);
    // Neu geholt ohne Höhen: die liegenden Höhen bleiben und zählen mit.
    use[f.key] = f.heights == null && old != null && old > f.bytes ? old : f.bytes;
  }

  final mine = {...usedNow, for (final f in fetched) f.key};
  var total = use.values.fold(0, (s, b) => s + b);
  final gone = <int>[];
  for (final k in use.keys.toList()) {
    if (total <= maxBytes) break;
    if (mine.contains(k)) continue;
    total -= use.remove(k)!;
    gone.add(k);
  }
  if (gone.isNotEmpty) {
    final covered = _coveredByAreas(all, region);
    final ids = [
      for (final k in gone)
        if (covered != null && !covered.contains(k))
          tileIdOf((z: kAreaShapeZoom, x: k >> kAreaShapeZoom, y: k & ((1 << kAreaShapeZoom) - 1))),
    ];
    if (ids.isNotEmpty) {
      for (final layer in TileLayer.values) {
        await tiles.remove(region, layer, ids);
      }
    }
  }

  final at = now ?? DateTime.now();
  final shape = TileSetShape(zoom: kAreaShapeZoom, keys: use.keys.toSet());
  String newer(String? a, String b) => a != null && a.compareTo(b) > 0 ? a : b;
  final hasHeights = (holder?.hasHeights ?? false) || (builds.heights != null && fetched.any((f) => f.heights != null));
  final hasWays = (holder?.hasWays ?? false) || (builds.ways != null && fetched.any((f) => f.ways != null));
  final next = StoredArea(
    id: keptAreaId(region),
    name: 'kept',
    bounds: shape.hull,
    shape: shape,
    minZoom: kAreaShapeZoom,
    maxZoom: kAreaShapeZoom,
    build: fetched.isEmpty ? holder!.build : newer(holder?.build, builds.map),
    tiles: use.length,
    bytes: total,
    savedAt: holder?.savedAt ?? at,
    // Was „hat Höhen/Wege" an einem Bereich heißt — die Leser fragen den
    // Speicher der Region nur dann; eine fehlende Kachel ist dort „nichts".
    heightTiles: hasHeights ? use.length : 0,
    heightsBuild: builds.heights == null ? holder?.heightsBuild : newer(holder?.heightsBuild, builds.heights!),
    wayTiles: hasWays ? use.length : 0,
    waysBuild: builds.ways == null ? holder?.waysBuild : newer(holder?.waysBuild, builds.ways!),
    region: region,
    format: kStoredAreaFormat,
    keptUse: use,
  );
  final i = all.indexWhere((a) => a.id == next.id);
  await areas.saveIndex(i < 0 ? [...all, next] : [...all.sublist(0, i), next, ...all.sublist(i + 1)]);
  final relist = holder == null || holder.hasHeights != next.hasHeights || holder.hasWays != next.hasWays;
  return (relist: relist, evicted: gone.length);
}
