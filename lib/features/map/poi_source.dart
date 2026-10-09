import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/errors.dart';
import '../../core/line_geometry.dart';
import '../../core/settings.dart';
import '../offline_areas/area_store.dart';
import 'map_providers.dart';
import 'map_regions.dart';
import 'poi.dart';

/// Woher die Orte kommen. Eine Schnittstelle, damit Tests ein Fake
/// einhängen — kein Netz in Tests. Gefragt wird je ZELLE und Gruppe;
/// das ist die Einheit, in der der Host die Dateien hält.
abstract interface class PoiSource {
  Future<List<Poi>> fetch(List<PoiCell> cells, Set<PoiGroup> groups);
}

/// Die Orte vom eigenen Kartenhost (`tiles.mcbuchi.de`, seit 0.18.0;
/// vorher Overpass): erst einmal je App-Lauf das Manifest, dann je Zelle
/// und Gruppe die fertige Datei — nur für Zellen, die das Manifest
/// nennt, eine leere Zelle kostet keine Anfrage. Übertragen wird die
/// Rasterzelle (etwa 11 × 11 km), nie der genaue Ausschnitt, nie Trails,
/// Fahrten oder das Konto. Derselbe Host steht schon für die Karte in
/// der Datenschutzerklärung.
class HostPoiSource implements PoiSource {
  HostPoiSource({
    http.Client? client,
    Future<String?> Function(String name)? readLocal,
    Future<List<MapRegion>> Function()? regions,
  })  : _client = client ?? http.Client(),
        _readLocal = readLocal,
        _regions = regions;

  final http.Client _client;

  /// Die Orte-Dateien gespeicherter Bereiche (Konzept-Schritt 3): Was
  /// hier liegt, wird nie beim Host geholt — und ohne Netz ist es das,
  /// was die Karte zeigt.
  final Future<String?> Function(String name)? _readLocal;

  /// Die Regionen des Hosts (#220) — eine Zelle fragt das Manifest der
  /// Region, in deren Rahmen sie liegt. Ohne: DACH allein.
  final Future<List<MapRegion>> Function()? _regions;

  /// Die Manifeste dieses App-Laufs, je Region. Scheitert ein Abruf,
  /// fehlt es und der nächste Wunsch versucht es wieder.
  final _manifests = <String, PoiManifest>{};

  /// So viele Dateien auf einmal — ein Tablet auf Zoom 12 mit allen
  /// Gruppen braucht bis zu 64, die einzeln nacheinander eine Weile
  /// dauerten; alle zugleich wären ein Sturm auf den Host.
  static const _parallel = 6;

  static const _timeout = Duration(seconds: 20);

  /// Das Manifest der Region; null, wenn die Region keine Orte hat.
  Future<PoiManifest?> _loadManifest(MapRegion region) async {
    final cached = _manifests[region.id];
    if (cached != null) return cached;
    if (region.isDach) return _manifests[region.id] = await fetchPoiManifest(_client);
    final uri = region.manifestUri(RegionLayer.pois);
    if (uri == null) return null;
    final res = await _client.get(uri).timeout(_timeout);
    if (res.statusCode != 200) throw PoiUnavailable(res.statusCode);
    return _manifests[region.id] = PoiManifest.fromJson(
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
        dir: region.dir);
  }

  @override
  Future<List<Poi>> fetch(List<PoiCell> cells, Set<PoiGroup> groups) async {
    final out = <Poi>[];
    // Erst die gespeicherten Bereiche: Was dort liegt, braucht weder
    // Manifest noch Netz.
    final remaining = <(PoiCell, PoiGroup)>[];
    for (final c in cells) {
      for (final g in groups) {
        final local = await _readLocal?.call(poiCellFileName(c, g));
        if (local != null) {
          out.addAll(parsePoiFile(local));
        } else {
          remaining.add((c, g));
        }
      }
    }
    if (remaining.isEmpty) return out;
    // Je Zelle die Region, deren Rahmen sie schneidet (#220); eine Zelle
    // außerhalb aller fragt nichts.
    final regions = await (_regions?.call() ?? Future.value(const [kDachRegion]));
    final wanted = <(PoiManifest, PoiCell, PoiGroup)>[];
    final byRegion = <MapRegion, List<(PoiCell, PoiGroup)>>{};
    for (final (c, g) in remaining) {
      final b = poiCellsBounds([c]);
      final region = regionFor(regions, LatBox(b.s, b.w, b.n, b.e));
      if (region != null) (byRegion[region] ??= []).add((c, g));
    }
    for (final MapEntry(key: region, value: cells) in byRegion.entries) {
      final manifest = await _loadManifest(region);
      if (manifest == null) continue;
      for (final (c, g) in cells) {
        if (manifest.has(c, g)) wanted.add((manifest, c, g));
      }
    }
    for (var i = 0; i < wanted.length; i += _parallel) {
      final batch = wanted.sublist(i, math.min(i + _parallel, wanted.length));
      final results = await Future.wait([
        for (final (m, c, g) in batch) _fetchCell(m, c, g),
      ]);
      for (final r in results) {
        out.addAll(r);
      }
    }
    return out;
  }

  Future<List<Poi>> _fetchCell(PoiManifest m, PoiCell cell, PoiGroup g) async {
    final uri = Uri.parse('$kMapTilesBase/${m.folder}/${poiCellFileName(cell, g)}');
    final res = await _client.get(uri).timeout(_timeout);
    // Eine Datei, die das Manifest nennt und die nicht da ist: der Bau
    // wurde gerade abgelöst und das alte Präfix ist schon weg. Leer, und
    // beim nächsten App-Start gilt das neue Manifest.
    if (res.statusCode == 404) return const [];
    if (res.statusCode != 200) throw PoiUnavailable(res.statusCode);
    return parsePoiFile(res.body);
  }
}

/// Das Orte-Manifest vom Host; wirft [PoiUnavailable], solange keins
/// veröffentlicht ist. Geteilt mit dem Bereichs-Download, der dieselben
/// Dateien für seine Zellen holt.
Future<PoiManifest> fetchPoiManifest(http.Client client) async {
  final res = await client.get(Uri.parse(kPoiManifestUrl)).timeout(const Duration(seconds: 20));
  if (res.statusCode != 200) throw PoiUnavailable(res.statusCode);
  return PoiManifest.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
}

/// Eine Orte-Datei vom Host als Text — null bei 404 (die Zelle ist seit
/// dem Manifest verschwunden), [PoiUnavailable] bei allem anderen.
Future<String?> fetchPoiFileFromHost(http.Client client, PoiManifest manifest, String name) async {
  final res = await client
      .get(Uri.parse('$kMapTilesBase/${manifest.folder}/$name'))
      .timeout(const Duration(seconds: 20));
  if (res.statusCode == 404) return null;
  if (res.statusCode != 200) throw PoiUnavailable(res.statusCode);
  return res.body;
}

/// Der Orte-Host hat gerade keine Antwort (5xx, oder 404 auf das Manifest,
/// solange noch kein Bau veröffentlicht ist). Kein Fehler der App — die
/// Karte sagt es und fragt beim nächsten Verschieben wieder.
class PoiUnavailable implements Exception {
  const PoiUnavailable(this.statusCode);
  final int statusCode;
  @override
  String toString() => 'Der Orte-Host antwortet mit $statusCode';
}

final poiSourceProvider = Provider<PoiSource>((ref) => HostPoiSource(
    readLocal: ref.watch(areaStoreProvider).readPoiFile,
    regions: () => ref.read(mapRegionsProvider.future)));

/// Die eingeschalteten Gruppen — gerätelokal gemerkt, wie
/// [RememberedFlag]: Der Zustand springt sofort, das Merken läuft nach.
class PoiGroupsNotifier extends Notifier<Set<PoiGroup>> {
  @override
  Set<PoiGroup> build() {
    final saved = ref.read(settingsProvider).poiGroups;
    if (saved == null) return PoiGroup.initial;
    return {
      for (final name in saved)
        ...PoiGroup.values.where((g) => g.name == name),
    };
  }

  void toggle(PoiGroup group) {
    final next = {...state};
    if (!next.remove(group)) next.add(group);
    state = next;
    unawaited(ref
        .read(settingsProvider)
        .setPoiGroups([for (final g in PoiGroup.values) if (next.contains(g)) g.name])
        .catchError((Object e, StackTrace s) => logError('Orte-Filter merken', e, s)));
  }
}

final poiGroupsProvider =
    NotifierProvider<PoiGroupsNotifier, Set<PoiGroup>>(PoiGroupsNotifier.new);

/// Der Detailfilter: einzeln abgewählte Arten. Er blendet nur aus —
/// geladen wird weiter je Gruppe, damit Zwischenspeicher und Abfrage
/// nicht an jeder Art hängen und ein Wiedereinschalten sofort wirkt.
class PoiHiddenKindsNotifier extends Notifier<Set<PoiKind>> {
  @override
  Set<PoiKind> build() => {
        for (final name in ref.read(settingsProvider).poiHiddenKinds ?? const [])
          ...PoiKind.values.where((k) => k.name == name),
      };

  void toggle(PoiKind kind) {
    final next = {...state};
    if (!next.remove(kind)) next.add(kind);
    state = next;
    unawaited(ref
        .read(settingsProvider)
        .setPoiHiddenKinds([for (final k in PoiKind.values) if (next.contains(k)) k.name])
        .catchError((Object e, StackTrace s) => logError('Orte-Detailfilter merken', e, s)));
  }
}

final poiHiddenKindsProvider =
    NotifierProvider<PoiHiddenKindsNotifier, Set<PoiKind>>(PoiHiddenKindsNotifier.new);

/// Was geladen ist, je Rasterzelle und Gruppe.
@immutable
class PoiState {
  const PoiState({this.byCell = const {}, this.unavailable = false});

  final Map<PoiCell, Map<PoiGroup, List<Poi>>> byCell;

  /// Die letzte Abfrage kam nicht durch.
  final bool unavailable;

  /// Die Orte der [groups] in den [cells].
  List<Poi> inCells(Iterable<PoiCell> cells, Set<PoiGroup> groups) => [
        for (final c in cells)
          for (final g in groups) ...?byCell[c]?[g],
      ];
}

/// Lädt fehlende Zellen nach und merkt sich, was schon da ist — für die
/// Laufzeit der App, nicht auf dem Gerät. Eine Zelle je Gruppe wird genau
/// einmal gefragt; wer zurückschwenkt, fragt nicht erneut.
class PoiController extends Notifier<PoiState> {
  bool _busy = false;
  ({List<PoiCell> cells, Set<PoiGroup> groups})? _queued;

  /// Merkt sich so viele Zellen, danach wird vergessen, was nicht gerade
  /// gebraucht wird (ein langer Tag Kartenschieben quer durch die Alpen).
  static const _maxCells = 400;

  @override
  PoiState build() => const PoiState();

  /// Sorgt dafür, dass [cells] für [groups] geladen sind. Läuft schon
  /// eine Abfrage, wird nur der jüngste Wunsch vorgemerkt.
  Future<void> ensure(List<PoiCell> cells, Set<PoiGroup> groups) async {
    if (_busy) {
      _queued = (cells: cells, groups: groups);
      return;
    }
    _busy = true;
    try {
      await _load(cells, groups);
      while (_queued != null) {
        final q = _queued!;
        _queued = null;
        await _load(q.cells, q.groups);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _load(List<PoiCell> cells, Set<PoiGroup> groups) async {
    if (cells.isEmpty || cells.length > kPoiMaxCells) return;
    final missingCells = <PoiCell>{};
    final missingGroups = <PoiGroup>{};
    for (final c in cells) {
      for (final g in groups) {
        if (state.byCell[c]?[g] == null) {
          missingCells.add(c);
          missingGroups.add(g);
        }
      }
    }
    if (missingCells.isEmpty) return;
    final List<Poi> pois;
    try {
      pois = await ref
          .read(poiSourceProvider)
          .fetch(missingCells.toList(), missingGroups);
    } on PoiUnavailable {
      state = PoiState(byCell: state.byCell, unavailable: true);
      return;
    } catch (e, s) {
      // Ein Funkloch ist auf dem Trail der Normalfall und kein Bericht
      // wert; alles andere (kaputte Antwort) wird gemeldet. Angezeigt
      // wird beides gleich, und beim nächsten Verschieben geht's weiter.
      if (!looksOffline(e)) logError('Orte laden', e, s);
      state = PoiState(byCell: state.byCell, unavailable: true);
      return;
    }
    var byCell = {
      for (final e in state.byCell.entries) e.key: {...e.value},
    };
    if (byCell.length > _maxCells) {
      byCell = {
        for (final e in byCell.entries)
          if (cells.contains(e.key)) e.key: e.value,
      };
    }
    // Der Rahmen umfasst auch Zellen, die gar nicht fehlten — für die
    // gilt nur, was sie noch nicht hatten; Vorhandenes bleibt, wie es war.
    final fresh = <PoiCell, Map<PoiGroup, List<Poi>>>{
      for (final c in missingCells)
        c: {
          for (final g in missingGroups)
            if (byCell[c]?[g] == null) g: <Poi>[],
        },
    };
    for (final p in pois) {
      fresh[poiCellOf(p.position)]?[p.group]?.add(p);
    }
    for (final e in fresh.entries) {
      (byCell[e.key] ??= {}).addAll(e.value);
    }
    state = PoiState(byCell: byCell);
  }
}

final poiControllerProvider =
    NotifierProvider<PoiController, PoiState>(PoiController.new);
