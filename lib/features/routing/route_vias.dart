// Zwischenpunkte („Gummipunkte", #234, Konzept-Routing 4.6): Wer die
// Route von Hand tunen will, tippt auf die Verbindungslinie, zieht den
// Punkt dorthin, wo der Weg langgehen soll, und die Suche läuft über ihn.
// Pur: die Punkte je Teilstück und der Weg durch sie.
//
// Ein TEILSTÜCK (leg) ist eine Verbindung zwischen zwei festen Halten:
// Start → erster Trail, Trail-Ende → nächster Trail, letztes Ende → Ziel.
// „Zum Trailkopf" hat genau eines (0). Die Zwischenpunkte eines
// Teilstücks liegen in Fahrtrichtung; ein neuer kommt dorthin, wo er auf
// der bisherigen Linie liegt ([RouteVias.insert]).
import 'package:latlong2/latlong.dart';

import 'road_graph.dart';
import 'route_profile.dart';
import 'route_search.dart';

/// Welcher Zwischenpunkt: Teilstück und Stelle darin.
typedef ViaRef = ({int leg, int index});

/// Die Zwischenpunkte einer Route, je Teilstück in Fahrtrichtung.
class RouteVias {
  const RouteVias([this.byLeg = const {}]);

  final Map<int, List<LatLng>> byLeg;

  static const none = RouteVias();

  bool get isEmpty => byLeg.values.every((l) => l.isEmpty);
  int get count => byLeg.values.fold(0, (s, l) => s + l.length);

  List<LatLng> of(int leg) => byLeg[leg] ?? const [];

  /// Alle Punkte mit ihrer Stelle — für Marker und Griffe.
  List<(ViaRef, LatLng)> get all => [
        for (final e in byLeg.entries)
          for (var i = 0; i < e.value.length; i++) ((leg: e.key, index: i), e.value[i]),
      ];

  /// [p] ins Teilstück [leg], an die Stelle, an der es auf [legLine]
  /// (der bisher gezeichneten Linie des Teilstücks) liegt.
  (RouteVias, ViaRef) insert(int leg, LatLng p, List<LatLng> legLine) {
    final list = [...of(leg)];
    final at = nearestIndexOn(legLine, p);
    var pos = 0;
    while (pos < list.length && nearestIndexOn(legLine, list[pos]) <= at) {
      pos++;
    }
    list.insert(pos, p);
    return (RouteVias({...byLeg, leg: list}), (leg: leg, index: pos));
  }

  RouteVias move(ViaRef ref, LatLng p) {
    final list = [...of(ref.leg)];
    if (ref.index >= list.length) return this;
    list[ref.index] = p;
    return RouteVias({...byLeg, ref.leg: list});
  }

  RouteVias remove(ViaRef ref) {
    final list = [...of(ref.leg)];
    if (ref.index >= list.length) return this;
    list.removeAt(ref.index);
    return RouteVias({...byLeg, ref.leg: list}..removeWhere((_, l) => l.isEmpty));
  }

  @override
  bool operator ==(Object other) {
    if (other is! RouteVias || other.count != count) return false;
    for (final e in byLeg.entries) {
      final o = other.of(e.key);
      if (o.length != e.value.length) return false;
      for (var i = 0; i < o.length; i++) {
        if (o[i] != e.value[i]) return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll([for (final (r, p) in all) (r.leg, r.index, p)]);
}

/// Der Index des Linienpunkts, der [p] am nächsten liegt — in Grad,
/// das reicht für die Reihenfolge auf wenigen Kilometern.
int nearestIndexOn(List<LatLng> line, LatLng p) {
  var best = 0;
  var bestD = double.infinity;
  for (var i = 0; i < line.length; i++) {
    final dy = line[i].latitude - p.latitude, dx = line[i].longitude - p.longitude;
    final d = dx * dx + dy * dy;
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}

/// Was ein Tipp auf eine Verbindungslinie trifft: das Teilstück und seine
/// ganze Linie (für die Reihenfolge eines neuen Punkts).
class RouteLegHit {
  const RouteLegHit(this.leg, this.line);

  final int leg;
  final List<LatLng> line;
}

/// Die ganze Linie je Teilstück aus seinen Abschnitten (in Reihenfolge)
/// — der Treffer eines Tipps trägt sie mit.
Map<int, List<LatLng>> legLinesOf(Iterable<(int, List<LatLng>)> sections) {
  final out = <int, List<LatLng>>{};
  for (final (leg, pts) in sections) {
    (out[leg] ??= []).addAll(pts);
  }
  return out;
}

/// Warum ein Weg durch Zwischenpunkte nicht geht.
enum ViaFailure {
  /// In [kGraphAttachM] um einen Zwischenpunkt liegt kein Weg.
  offNetwork,

  /// Kein Weg führt durch die Punkte (Einbahn, Insel, Trail gegen die
  /// Richtung).
  noPath,
}

/// Der Weg von [src] nach [dst] durch [via] (in dieser Reihenfolge): je
/// Abschnitt A*, die Kanten aneinander. Heftet die Punkte an [g] — das
/// teilt Kanten, wie bei jedem Anheften.
({List<int>? edges, ViaFailure? failure}) pathThrough(
    RoadGraph g, int src, int dst, List<LatLng> via, RiderParams p) {
  final stops = <int>[src];
  for (final v in via) {
    final n = g.attach(v);
    if (n == null) return (edges: null, failure: ViaFailure.offNetwork);
    stops.add(n);
  }
  stops.add(dst);
  final edges = <int>[];
  for (var k = 1; k < stops.length; k++) {
    if (stops[k - 1] == stops[k]) continue;
    final r = shortestPath(g, stops[k - 1], stops[k], p);
    if (r == null) return (edges: null, failure: ViaFailure.noPath);
    edges.addAll(r.edges);
  }
  return (edges: edges, failure: null);
}
