import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/map/place.dart';
import 'package:trailbuddy/features/map/place_source.dart';
import 'package:trailbuddy/features/map/poi.dart';
import 'package:trailbuddy/features/map/poi_source.dart';

/// Orte aus dem Speicher statt vom Kartenhost — kein Netz in Tests. Merkt
/// sich jede Abfrage, damit Tests zählen können, WANN gefragt wird (und
/// wann gerade nicht: unterhalb Zoom 12, alles aus).
class FakePoiSource implements PoiSource {
  FakePoiSource([List<Poi>? pois]) : pois = pois ?? [];

  final List<Poi> pois;

  /// Je Abfrage der Rahmen um die gefragten Zellen.
  final calls = <({double s, double w, double n, double e})>[];
  final cellsAsked = <List<PoiCell>>[];
  final groupsAsked = <Set<PoiGroup>>[];

  /// Gesetzt: Die nächste Abfrage scheitert damit.
  Object? failWith;

  @override
  Future<List<Poi>> fetch(List<PoiCell> cells, Set<PoiGroup> groups) async {
    final box = poiCellsBounds(cells);
    calls.add(box);
    cellsAsked.add(cells);
    groupsAsked.add(groups);
    final f = failWith;
    if (f != null) {
      failWith = null;
      throw f;
    }
    return [
      for (final p in pois)
        if (groups.contains(p.group) &&
            p.position.latitude >= box.s &&
            p.position.latitude <= box.n &&
            p.position.longitude >= box.w &&
            p.position.longitude <= box.e)
          p,
    ];
  }
}

/// Ortsnamen ohne Netz (#576 Stufe 2): liefert, was der Host liefern
/// würde — die Einträge mit einem Wort, das wie das längste getippte Wort
/// beginnt (zwei Buchstaben, wie eine ungeteilte Namensdatei). Merkt sich
/// jede Anfrage; [offline] spielt den Rückfall auf gespeicherte Bereiche.
class FakePlaceSource implements PlaceSource {
  FakePlaceSource([List<Place>? places, List<Place>? stored])
    : places = places ?? [],
      stored = stored ?? [];

  /// Der Index des Hosts — nur mit `online` (#596 H5).
  final List<Place> places;

  /// Was die gespeicherten Bereiche mitbringen — immer.
  final List<Place> stored;
  final queries = <String>[];

  /// Die Eingaben, zu denen online gefragt wurde.
  final onlineQueries = <String>[];
  bool offline = false;

  @override
  Future<PlaceLookup> lookup(
    String query,
    LatLng center, {
    bool online = false,
  }) async {
    queries.add(query);
    final word = longestPlaceWord(query);
    if (word == null) return kNoPlaces;
    final prefix = word.substring(0, 2);
    if (online) onlineQueries.add(query);
    final from = online && !offline ? [...stored, ...places] : stored;
    return (
      places: [
        for (final p in from)
          if (placeHasWordStarting(p, prefix)) p,
      ],
      offline: online && offline,
    );
  }
}
