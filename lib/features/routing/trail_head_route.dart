// „Zum Trailkopf" (Konzept-Routing 4, #158 Schritt 4): vom eigenen
// Standort zum Anfang EINES Trails über den Wegegraphen der gespeicherten
// Bereiche — der Sonderfall des Planers mit einem Ziel (Konzept-Routing
// 3.1: A* mit Luftlinien-Heuristik). Pur: Graph, Start, Trailkopf und
// Profil rein, die Linie mit Abschnitten je Wegklasse raus.
//
// Was NICHT geht, sagt der Ausgang einzeln (`TrailHeadOutcome`), und das
// Blatt macht daraus je einen Satz: kein Weg in 30 m um den Standort, kein
// Weg in 30 m um den Trailkopf, keine Verbindung. Ob ein Bereich den Weg
// deckt, entscheidet davor `loadRoadGraph` — hier kommt ein fertiger Graph
// an. Die Engine urteilt nie über Erlaubnis (Konzept 7): Führt der Weg über
// Wanderweg, steht es im Ergebnis (`hikingM`), und das Blatt sagt es.
import 'package:latlong2/latlong.dart';

import '../trails/gpx.dart';
import 'road_graph.dart';
import 'route_profile.dart';
import 'route_search.dart';
import 'route_vias.dart';

/// Rand um den Rahmen aus Standort und Trailkopf, in dem Kacheln gelesen
/// werden: Ein Umweg um einen Hang liegt selten im engen Rechteck der
/// beiden Punkte, und ein Rahmen ohne Rand ist bei Standort und Kopf auf
/// einer Linie null Meter breit.
const kTrailHeadMarginM = 500.0;

enum TrailHeadOutcome {
  ok,

  /// In [kGraphAttachM] um den Standort liegt kein Weg aus den Kacheln.
  startOffNetwork,

  /// In [kGraphAttachM] um den Trailkopf liegt kein Weg aus den Kacheln.
  headOffNetwork,

  /// Beide hängen am Graphen, aber nicht aneinander (Einbahn, Insel).
  noPath,

  /// In [kGraphAttachM] um einen Zwischenpunkt (#234) liegt kein Weg.
  viaOffNetwork,
}

/// Ein Stück der Route mit EINER Wegklasse — die Vorschau zeichnet
/// Wanderweg anders als Forstweg, und die Liste nennt den Mix.
class RouteSection {
  const RouteSection({required this.cls, required this.points, required this.lengthM, this.trail});

  final WayClass cls;
  final List<LatLng> points;
  final double lengthM;

  /// Der Trail, auf dem das Stück liegt (#185: ein Uphill-Trail oder
  /// Verbinder) — die Vorschau zeichnet es dann nicht als Wanderweg.
  final EdgeTrail? trail;

  /// Zählt gegen „höchstens Wanderweg" und wird gestrichelt gezeichnet.
  bool get hiking => cls.hiking && !(trail?.connector ?? false);
}

class TrailHeadRoute {
  const TrailHeadRoute({
    required this.profile,
    required this.summary,
    required this.sections,
    required this.points,
  });

  final RiderParams profile;
  final PathSummary summary;
  final List<RouteSection> sections;

  /// Die ganze Linie: vom Standort über die Wege zum Trailkopf. Die beiden
  /// Verbinder (Standort → erster Wegpunkt, letzter Wegpunkt → Trailkopf)
  /// zählen nicht in Länge und Zeit — sie sind der Anschluss, keine
  /// Strecke; die Linie trägt sie, damit sie am Punkt beginnt, an dem
  /// man steht.
  final List<LatLng> points;
}

class TrailHeadPlan {
  const TrailHeadPlan(this.outcome, [this.route]);

  final TrailHeadOutcome outcome;
  final TrailHeadRoute? route;
}

/// Plant den Weg von [from] zum Trailkopf [head] auf [g] mit [profile],
/// mit [via] durch die Zwischenpunkte des einen Teilstücks (#234).
TrailHeadPlan planTrailHeadRoute(RoadGraph g, LatLng from, LatLng head, RiderParams profile,
    {List<LatLng> via = const []}) {
  final src = g.attach(from);
  if (src == null) return const TrailHeadPlan(TrailHeadOutcome.startOffNetwork);
  final dst = g.attach(head);
  if (dst == null) return const TrailHeadPlan(TrailHeadOutcome.headOffNetwork);
  final List<int> edges;
  if (via.isNotEmpty) {
    final r = pathThrough(g, src, dst, via, profile);
    if (r.edges == null) {
      return TrailHeadPlan(
          r.failure == ViaFailure.offNetwork ? TrailHeadOutcome.viaOffNetwork : TrailHeadOutcome.noPath);
    }
    edges = r.edges!;
  } else if (src == dst) {
    edges = const [];
  } else {
    final r = shortestPath(g, src, dst, profile);
    if (r == null) return const TrailHeadPlan(TrailHeadOutcome.noPath);
    edges = r.edges;
  }
  final summary = summarizePath(g, edges, src, profile);
  final line = summary.points.isEmpty ? [g.nodeLatLng[src]] : summary.points;
  return TrailHeadPlan(
    TrailHeadOutcome.ok,
    TrailHeadRoute(
      profile: profile,
      summary: summary,
      sections: sectionsOf(g, edges, src),
      points: [from, ...line, head],
    ),
  );
}

/// Die Kanten [path] ab [src] zu Abschnitten je Wegklasse: aufeinander-
/// folgende Kanten derselben Klasse und desselben Trails werden EIN Abschnitt, die Punkte
/// hängen aneinander (der gemeinsame Knoten steht einmal).
List<RouteSection> sectionsOf(RoadGraph g, List<int> path, int src) {
  final out = <RouteSection>[];
  var n = src;
  WayClass? cls;
  EdgeTrail? trail;
  var pts = <LatLng>[];
  var length = 0.0;
  void flush() {
    if (cls != null && pts.length >= 2) {
      out.add(RouteSection(cls: cls, points: pts, lengthM: length, trail: trail));
    }
  }

  for (final ei in path) {
    final e = g.edges[ei];
    final forward = e.a == n;
    final ep = forward ? e.points : e.points.reversed.toList();
    if (e.cls != cls || e.trail?.id != trail?.id) {
      flush();
      cls = e.cls;
      trail = e.trail;
      pts = [ep.first];
      length = 0;
    }
    pts.addAll(ep.skip(1));
    length += e.length;
    n = forward ? e.b : e.a;
  }
  flush();
  return out;
}

/// „45 min", „1 h 20 min" — die geschätzte Zeit, auf fünf Minuten
/// gerundet: Das Zeitmodell ist ohne Kalibrierung ±30 % (Konzept-Routing
/// 7), eine Minute genau wäre eine erfundene Genauigkeit.
String routeTimeLabel(double seconds) {
  final min = ((seconds / 60) / 5).round() * 5;
  if (min < 5) return 'unter 5 min';
  if (min < 60) return '$min min';
  final h = min ~/ 60, m = min % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// Die Route als GPX-Spur (#150): nur die Linie, der Name nennt den
/// Trail. Keine Höhen — die Engine kennt sie je Kante, nicht je Punkt,
/// und erfundene Punkt-Höhen wären eine Behauptung.
GpxTrack trailHeadToGpx(TrailHeadRoute route, {required String trailName}) => GpxTrack(
      name: 'Zum Trailkopf: $trailName',
      points: [for (final p in route.points) TrackPoint(p.latitude, p.longitude)],
    );
