// Die Suche auf der Karte (#576): über das, was die App schon hat — die
// Trails des eigenen Netzes, die gemerkten Startpunkte und die Orte
// (POIs) der Rasterzellen um die Kartenmitte — und (Stufe 2) über die
// Ortsnamen aus dem eigenen Index auf dem Kartenhost (`place.dart`).
// Kein fremder Suchdienst; gesucht wird wie in der Trail-Liste
// (`lib/core/search_text.dart`): erst Teiltreffer, NUR wenn keiner der
// vier Abschnitte einen hat, der Tippfehler-Ausgleich, und die
// Oberfläche sagt dann, dass sie rät.
import 'package:latlong2/latlong.dart';

import '../../core/search_text.dart';
import '../../models/start_point.dart';
import '../../models/trail.dart';
import '../trails/trail_list.dart' show trailSearchTexts;
import 'place.dart';
import 'poi.dart';

/// So viele Treffer je Abschnitt — die nächsten zuerst. Mehr liest auf
/// einem Telefon niemand, und „Wasser" fände sonst jeden Brunnen der
/// Umgebung.
const kMapSearchMaxTrails = 20;
const kMapSearchMaxStartPoints = 10;
const kMapSearchMaxPois = 20;
const kMapSearchMaxPlaces = 20;

/// So nah fliegt die Karte an einen Ort oder Startpunkt heran (256er-Zoom,
/// wie `MapViewCamera.zoom`) — die Orte zeigt sie ab 12, die Namen am
/// Trail ab 14.
const kMapSearchFlyZoom = 15.0;

/// So lange steht die Nadel am Ziel eines Ortsnamens (#596) — lang genug,
/// um nach dem Flug hinzusehen; ein Tipp auf die Karte nimmt sie früher.
const kMapSearchPinDuration = Duration(seconds: 6);

/// Was die Suche zeigt, je Abschnitt nach Entfernung zur Kartenmitte.
typedef MapSearchResult = ({
  List<Trail> trails,
  List<StartPoint> startPoints,
  List<Poi> pois,
  List<Place> places,

  /// Kein Teiltreffer — die Treffer sind die nächsten Namen per
  /// Tippfehler-Ausgleich. Die Oberfläche MUSS das sagen.
  bool isGuess,
});

const MapSearchResult kEmptyMapSearch = (
  trails: <Trail>[],
  startPoints: <StartPoint>[],
  pois: <Poi>[],
  places: <Place>[],
  isGuess: false,
);

/// Die Texte eines Startpunkts: sein Name und, bei einem fremden, wer ihn
/// gemerkt hat.
List<String> startPointSearchTexts(StartPoint p) => [p.name, ?p.username];

/// Die Texte eines Ortes: sein Name und seine Art in der Sprache der
/// Oberfläche — „Trinkwasser" findet den Brunnen ohne Namen.
List<String> poiSearchTexts(Poi p, String Function(PoiKind) kindLabel) => [
  ?p.name,
  kindLabel(p.kind),
];

/// Sucht [query] in [trails], [startPoints], [pois] und [places]. Leere
/// Eingabe ⇒ nichts (die Suche ist kein Verzeichnis, A1). Eine Hütte, die
/// schon unter den Orten steht, fehlt unter den Ortsnamen.
MapSearchResult mapSearchOf({
  required String query,
  required LatLng center,
  required List<Trail> trails,
  required List<StartPoint> startPoints,
  required List<Poi> pois,
  List<Place> places = const [],
  required String Function(PoiKind) kindLabel,
}) {
  final needle = foldSearchText(query);
  if (needle.isEmpty) return kEmptyMapSearch;

  final t = _distances(trails, needle, trailSearchTexts);
  final s = _distances(startPoints, needle, startPointSearchTexts);
  final p = _distances(pois, needle, (x) => poiSearchTexts(x, kindLabel));
  final poiIds = {for (final x in pois) x.id};
  final n = _distances(
    [
      for (final x in places)
        if (!poiIds.contains(x.id)) x,
    ],
    needle,
    placeSearchTexts,
  );

  // Teiltreffer haben den Abstand 0. Gibt es irgendwo einen, gelten nur
  // sie; sonst der kleinste Abstand über ALLE Abschnitte — wer „Rosskopg"
  // tippt, will den Roßkopf, nicht dazu den nächstbesten Brunnen.
  final all = [...t.values, ...s.values, ...p.values, ...n.values];
  if (all.isEmpty) return kEmptyMapSearch;
  final best = all.reduce((a, b) => a < b ? a : b);
  List<T> keep<T>(Map<T, int> d) => [
    for (final e in d.entries)
      if (e.value == best) e.key,
  ];

  const distance = Distance();
  double trailM(Trail x) => _nearestM(x.points, center);
  double away(LatLng at) => distance.as(LengthUnit.Meter, center, at);
  List<T> order<T>(
    Map<T, int> d,
    List<String> Function(T) texts,
    double Function(T) meters,
    int max,
  ) => _nearestFirst(
    keep(d),
    (x) => matchRank(needle, texts(x)),
    meters,
  ).take(max).toList();
  return (
    trails: order(t, trailSearchTexts, trailM, kMapSearchMaxTrails),
    startPoints: order(
      s,
      startPointSearchTexts,
      (x) => away(x.position),
      kMapSearchMaxStartPoints,
    ),
    pois: order(
      p,
      (x) => poiSearchTexts(x, kindLabel),
      (x) => away(x.position),
      kMapSearchMaxPois,
    ),
    places: order(
      n,
      placeSearchTexts,
      (x) => away(x.position),
      kMapSearchMaxPlaces,
    ),
    isGuess: best > 0,
  );
}

final _wordBreak = RegExp(r"[\s\-/,.()'’]+");

/// Wie gut [texts] die gefaltete Eingabe [needle] treffen (#596, Fund aus
/// dem Test von #576): 0 genau, 1 der Text beginnt mit ihr, 2 ein Wort
/// darin, 3 sonst. Erst danach zählt die Entfernung — wer „Au" tippt,
/// will Au, nicht das nähere Pfaffenau.
int matchRank(String needle, List<String> texts) {
  var best = 3;
  for (final text in texts) {
    final hay = foldSearchText(text);
    if (hay == needle) return 0;
    if (hay.startsWith(needle)) {
      best = 1;
    } else if (best > 2 &&
        text
            .split(_wordBreak)
            .any((w) => foldSearchText(w).startsWith(needle))) {
      best = 2;
    }
  }
  return best;
}

/// Je Eintrag der beste Abstand: 0 für einen Teiltreffer, sonst der
/// Editierabstand, solange er in der Toleranz liegt. Was weiter weg ist,
/// fehlt.
Map<T, int> _distances<T>(
  List<T> items,
  String needle,
  List<String> Function(T) texts,
) {
  final tolerance = searchTypoTolerance(needle.length);
  final out = <T, int>{};
  for (final item in items) {
    int? best;
    for (final text in texts(item)) {
      final hay = foldSearchText(text);
      if (hay.contains(needle)) {
        best = 0;
        break;
      }
      if (tolerance < 0) continue;
      final d = nearContainsDistance(needle, hay);
      if (d <= tolerance && (best == null || d < best)) best = d;
    }
    if (best != null) out[item] = best;
  }
  return out;
}

/// Nach [rank], dann nach Entfernung; bei Gleichstand bleibt die
/// Reihenfolge.
List<T> _nearestFirst<T>(
  List<T> items,
  int Function(T) rank,
  double Function(T) meters,
) {
  final keyed =
      [
        for (var i = 0; i < items.length; i++)
          (i: i, r: rank(items[i]), m: meters(items[i])),
      ]..sort(
        (a, b) => a.r != b.r
            ? a.r.compareTo(b.r)
            : a.m != b.m
            ? a.m.compareTo(b.m)
            : a.i.compareTo(b.i),
      );
  return [for (final k in keyed) items[k.i]];
}

/// Der kleinste Abstand eines Punkts der Linie zur Mitte — ein langer
/// Trail, der durchs Bild läuft, ist nah, auch wenn sein Anfang weit weg
/// liegt. Höchstens 200 Punkte, das reicht für eine Reihenfolge.
double _nearestM(List<LatLng> points, LatLng center) {
  if (points.isEmpty) return double.infinity;
  const distance = Distance();
  final step = points.length > 200 ? points.length ~/ 200 : 1;
  var best = double.infinity;
  for (var i = 0; i < points.length; i += step) {
    final d = distance.as(LengthUnit.Meter, center, points[i]);
    if (d < best) best = d;
  }
  return best;
}

/// Die Rasterzellen der Orte, in denen die Suche nachsieht: die der
/// Mitte und ihre acht Nachbarn, etwa 33 × 33 km in Mitteleuropa — so
/// viel, wie man „in der Nähe" nennt, und unter [kPoiMaxCells].
List<PoiCell> mapSearchPoiCells(LatLng center) {
  final parts = poiCellOf(center).split(',');
  final r = int.parse(parts[0]), c = int.parse(parts[1]);
  return [
    for (var dr = -1; dr <= 1; dr++)
      for (var dc = -1; dc <= 1; dc++) '${r + dr},${c + dc}',
  ];
}
