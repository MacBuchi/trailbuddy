// Woher die Ortsnamen der Suche kommen (#576, Stufe 2): online EINE
// Namensdatei vom eigenen Kartenhost, gewählt nach den ersten zwei bis
// vier Buchstaben des längsten getippten Worts — nur dieser Schlüssel
// steht in der Adresse, nie die Eingabe, nie der Ausschnitt. Ohne Netz
// (oder ohne Index auf dem Host) die Ortsnamen-Zellen der gespeicherten
// Bereiche.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/line_geometry.dart';
import '../../data/seen_host_files.dart';
import '../offline_areas/area_providers.dart' show storedAreasProvider;
import '../offline_areas/area_store.dart';
import 'map_providers.dart';
import 'map_regions.dart';
import 'place.dart';
import 'poi.dart';
import 'poi_source.dart';
import 'host_requests.dart';

/// Was eine Suche nach Ortsnamen ergab: die Kandidaten (gefiltert wird in
/// `mapSearchOf`) und ob sie aus den gespeicherten Bereichen statt vom
/// Host kommen.
typedef PlaceLookup = ({List<Place> places, bool offline});

const PlaceLookup kNoPlaces = (places: <Place>[], offline: false);

abstract interface class PlaceSource {
  /// Die Ortsnamen, unter denen [query] zu suchen ist — die ganze
  /// Namensdatei seines Schlüssels. [center] wählt die Region (#220).
  /// Ohne [online] nur, was das Gerät hat (gespeicherte Bereiche und
  /// schon einmal geholte Namensdateien) — keine Anfrage. Online wird nur
  /// nach einem Tipp gesucht (#596 H5, Betreiber 2026-11-20).
  Future<PlaceLookup> lookup(String query, LatLng center, {bool online});
}

class HostPlaceSource implements PlaceSource {
  HostPlaceSource({
    http.Client? client,
    required Future<List<MapRegion>> Function() regions,
    required Future<List<String>> Function() storedNames,
    required Future<String?> Function(String name) readLocal,
    SeenHostFiles? seen,
    PoiManifests? manifests,
  }) : _client = client ?? hostClient(),
       _regions = regions,
       _storedNames = storedNames,
       _readLocal = readLocal,
       _seen = seen {
    _manifests = manifests ?? PoiManifests(client: _client, seen: seen);
  }

  final http.Client _client;
  final Future<List<MapRegion>> Function() _regions;

  /// Die Namen der Ortsnamen-Zellen aller gespeicherten Bereiche.
  final Future<List<String>> Function() _storedNames;
  final Future<String?> Function(String name) _readLocal;

  /// Was schon einmal vom Host kam (#596 H4).
  final SeenHostFiles? _seen;
  late final PoiManifests _manifests;

  /// Namensdateien dieses App-Laufs, je `<ordner>/names/<schlüssel>.json`
  /// — wer weitertippt, bleibt meist im selben Schlüssel und fragt nicht
  /// neu.
  final _files = <String, List<Place>>{};

  /// Laufende Abrufe je Namensdatei: Beim Tippen fragten bis #596 alle
  /// Buchstaben desselben Schlüssels einzeln (sechsmal im ersten Test).
  final _inflight = <String, Future<List<Place>>>{};

  /// Gelesene Zellen der Bereiche, je Dateiname.
  final _stored = <String, List<Place>>{};

  @override
  Future<PlaceLookup> lookup(
    String query,
    LatLng center, {
    bool online = false,
  }) async {
    final word = longestPlaceWord(query);
    if (word == null) return kNoPlaces;
    final local = await _fromStored(word);
    MapRegion? region;
    try {
      region = regionFor(
        await _regions(),
        LatBox(
          center.latitude,
          center.longitude,
          center.latitude,
          center.longitude,
        ),
      );
      if (region == null) return (places: local, offline: false);
      if (!online) {
        return (places: await _withSeen(local, region, query), offline: false);
      }
      final m = await _manifests.of(region);
      // Ein Bau ohne Ortsnamen (vor #576): was liegt.
      if (m == null || m.placeNames.isEmpty) {
        return (places: local, offline: false);
      }
      final key = placeNameKey(query, m.placeNames);
      if (key == null) return (places: local, offline: false);
      return (places: _merge(local, await _file(m, key)), offline: false);
    } on Exception {
      // Funkloch, Zeitüberschreitung, Host ohne 200, kaputte Datei: Die
      // Suche geht mit dem weiter, was das Gerät hat — und sagt es.
      final places = region == null
          ? local
          : await _withSeen(local, region, query);
      return (places: places, offline: online);
    }
  }

  /// [local] plus die gemerkte Namensdatei zu [query], wenn das gemerkte
  /// Manifest sie nennt — ohne Anfrage.
  Future<List<Place>> _withSeen(
    List<Place> local,
    MapRegion region,
    String query,
  ) async {
    final m = await _manifests.of(region, local: true);
    if (m == null || m.placeNames.isEmpty) return local;
    final key = placeNameKey(query, m.placeNames);
    if (key == null) return local;
    final id = _fileKey(m, key);
    final cached = _files[id];
    if (cached != null) return _merge(local, cached);
    final text = await readSeen(_seen, id);
    if (text == null) return local;
    try {
      return _merge(local, _files[id] = parsePlaceFile(text));
    } on FormatException {
      return local;
    }
  }

  static String _fileKey(PoiManifest m, String key) =>
      '${m.folder}/names/$key.json';

  static List<Place> _merge(List<Place> a, List<Place> b) {
    if (a.isEmpty) return b;
    final ids = {for (final p in b) p.id};
    return [
      ...b,
      for (final p in a)
        if (!ids.contains(p.id)) p,
    ];
  }

  Future<List<Place>> _file(PoiManifest m, String key) {
    final id = _fileKey(m, key);
    final cached = _files[id];
    if (cached != null) return Future.value(cached);
    return _inflight[id] ??= _fetchFile(id).whenComplete(() {
      // Ein Block, kein Pfeil: `remove` gäbe die Future selbst zurück,
      // und `whenComplete` wartete auf sich selbst.
      _inflight.remove(id);
    });
  }

  Future<List<Place>> _fetchFile(String id) async {
    final seen = await readSeen(_seen, id);
    if (seen != null) {
      try {
        return _files[id] = parsePlaceFile(seen);
      } on FormatException {
        // kaputt abgelegt: neu vom Host
      }
    }
    final res = await _client
        .get(Uri.parse('$kMapTilesBase/$id'))
        .timeout(const Duration(seconds: 20));
    // Genannt, aber nicht da: der Bau wurde gerade abgelöst.
    if (res.statusCode == 404) return const [];
    if (res.statusCode != 200) throw PoiUnavailable(res.statusCode);
    final places = _files[id] = parsePlaceFile(res.body);
    unawaited(_seen?.write(id, res.body));
    return places;
  }

  /// Die Ortsnamen der Bereiche mit einem Wort, das wie [word] beginnt —
  /// dieselbe Auswahl, die die Namensdatei des Hosts träfe.
  Future<List<Place>> _fromStored(String word) async {
    final prefix = word.substring(0, 2);
    final out = <Place>[];
    final seen = <String>{};
    for (final name in await _storedNames()) {
      var places = _stored[name];
      if (places == null) {
        final text = await _readLocal(name);
        if (text == null) continue;
        try {
          places = _stored[name] = parsePlaceFile(text);
        } on FormatException {
          continue; // eine kaputte Zelle kostet nur ihre Namen
        }
      }
      for (final p in places) {
        if (placeHasWordStarting(p, prefix) && seen.add(p.id)) out.add(p);
      }
    }
    return out;
  }
}

final placeSourceProvider = Provider<PlaceSource>(
  (ref) => HostPlaceSource(
    regions: () => ref.read(mapRegionsProvider.future),
    readLocal: ref.watch(areaStoreProvider).readPoiFile,
    seen: ref.watch(seenHostFilesProvider),
    manifests: ref.watch(poiManifestsProvider),
    storedNames: () async {
      final areas = await ref.read(storedAreasProvider.future);
      return {
        for (final a in areas)
          for (final n in a.poiFiles)
            if (isPlaceCellFileName(n)) n,
      }.toList();
    },
  ),
);
