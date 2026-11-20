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
  Future<PlaceLookup> lookup(String query, LatLng center);
}

class HostPlaceSource implements PlaceSource {
  HostPlaceSource({
    http.Client? client,
    required Future<List<MapRegion>> Function() regions,
    required Future<List<String>> Function() storedNames,
    required Future<String?> Function(String name) readLocal,
  }) : _client = client ?? hostClient(),
       _regions = regions,
       _storedNames = storedNames,
       _readLocal = readLocal;

  final http.Client _client;
  final Future<List<MapRegion>> Function() _regions;

  /// Die Namen der Ortsnamen-Zellen aller gespeicherten Bereiche.
  final Future<List<String>> Function() _storedNames;
  final Future<String?> Function(String name) _readLocal;

  final _manifests = <String, PoiManifest>{};

  /// Namensdateien dieses App-Laufs, je `<ordner>/<schlüssel>` — wer
  /// weitertippt, bleibt meist im selben Schlüssel und fragt nicht neu.
  final _files = <String, List<Place>>{};

  /// Gelesene Zellen der Bereiche, je Dateiname.
  final _stored = <String, List<Place>>{};

  @override
  Future<PlaceLookup> lookup(String query, LatLng center) async {
    final word = longestPlaceWord(query);
    if (word == null) return kNoPlaces;
    try {
      final regions = await _regions();
      final region = regionFor(
        regions,
        LatBox(
          center.latitude,
          center.longitude,
          center.latitude,
          center.longitude,
        ),
      );
      final m = region == null ? null : await _manifest(region);
      // Ein Bau ohne Ortsnamen (vor #576) oder keine Region: was liegt.
      if (m == null || m.placeNames.isEmpty) {
        return (places: await _fromStored(word), offline: false);
      }
      final key = placeNameKey(query, m.placeNames);
      if (key == null) return kNoPlaces;
      return (places: await _file(m, key), offline: false);
    } on Exception {
      // Funkloch, Zeitüberschreitung, Host ohne 200, kaputte Datei: Die
      // Suche geht mit dem weiter, was die Bereiche mitgebracht haben —
      // und sagt es.
      return (places: await _fromStored(word), offline: true);
    }
  }

  Future<PoiManifest?> _manifest(MapRegion region) async {
    final cached = _manifests[region.id];
    if (cached != null) return cached;
    final m = await fetchRegionPoiManifest(_client, region);
    if (m != null) _manifests[region.id] = m;
    return m;
  }

  Future<List<Place>> _file(PoiManifest m, String key) async {
    final id = '${m.folder}/$key';
    final cached = _files[id];
    if (cached != null) return cached;
    final res = await _client
        .get(Uri.parse('$kMapTilesBase/${m.folder}/names/$key.json'))
        .timeout(const Duration(seconds: 20));
    // Genannt, aber nicht da: der Bau wurde gerade abgelöst.
    if (res.statusCode == 404) return const [];
    if (res.statusCode != 200) throw PoiUnavailable(res.statusCode);
    return _files[id] = parsePlaceFile(res.body);
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
