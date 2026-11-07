// „Route umplanen" (#464, Konzept-Routing 9.3a): Wer weiter als die
// Schwelle neben der Route fährt, bekommt den Rest der Route ab dem
// Standort neu — nicht zurück auf die alte Linie wie bei „Zurück zur
// Route", sondern zum nächsten Trailkopf voraus (ohne Trail voraus: zum
// Ziel). Die Trails der Route bleiben alle drin, frei wird nur die
// Anfahrt. Ist der alte Weg zum Kopf ab irgendeiner Stelle der günstigste,
// nimmt die Suche ihn von selbst wieder auf — er liegt auf demselben
// Graphen.
//
// Umkehren ist teuer, aber möglich: zwei Suchen, eine ohne die Kanten,
// die am Standort gegen den GPS-Kurs führen, eine frei; die freie gewinnt
// nur, wenn sie um mehr als [kNavReplanTurnBackS] günstiger ist.
//
// Pur: Graph, Standort, Kurs, Ziel und Profil rein, die Linie raus. Die
// neue Route setzt [spliceReplan] aus dem neuen Stück und dem Rest der
// alten zusammen.
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../core/geo.dart' as geo;
import 'graph_input.dart' show GraphJob;
import 'loop_planner.dart' show LoopSearchCache;
import 'road_graph.dart';
import 'route_profile.dart';
import 'route_progress.dart';
import 'route_search.dart';

/// Ab so viel Abstand zur Route bietet die Ansicht „Route umplanen" an
/// (Vorgabe; einstellbar in „Navigation", Betreiber 2026-11-05).
const kNavReplanOfferM = 100;

/// Ab so viel Abstand endet die Navigation von selbst (Vorgabe; 0 = nie).
const kNavLeaveM = 500;

/// Die Wahl der Seite „Navigation" (#464).
const kNavReplanOfferChoices = [50, 100, 200, 300, 500];
const kNavLeaveChoices = [200, 500, 1000, 2000, 0];

/// Was Umkehren am Standort kostet, in Sekunden der Kosten: „sehr
/// unattraktiv, aber nicht unmöglich" (#464). Startwert wie alle Zahlen
/// der Navigation (9.7).
const kNavReplanTurnBackS = 180.0;

/// Weicht die Richtung einer Kante am Standort um mehr als das vom Kurs
/// ab, führt sie zurück.
const kNavReplanBackDeg = 100.0;

/// Über so viele Meter der Kante wird ihre Richtung am Standort gemessen
/// — der erste Punkt allein läge oft im Rauschen des Anheftens.
const kNavReplanBearingM = 15.0;

/// Geht der Weg zum nächsten Trailkopf nicht (zu weit, keine Kacheln,
/// keine Verbindung), trifft das neue Stück so weit voraus auf die Linie —
/// nie hinter dem Kopf.
const kNavReplanFallbackM = 1000.0;

/// Wo das neue Stück die alte Route wieder trifft, in Reihenfolge der
/// Versuche: der Kopf des nächsten Trails voraus (ohne: das Ende), dann
/// [kNavReplanFallbackM] voraus, wenn das davor liegt. Meter ab Start.
List<double> replanTargetsOf(NavRoute route, NavSections sections, double alongM) {
  final next = sections.nextFrom(alongM);
  final head = math.min(next?.startM ?? route.lengthM, route.lengthM);
  final out = <double>[head];
  final near = alongM + kNavReplanFallbackM;
  // Erst ab 200 m vor dem Kopf lohnt ein zweiter Versuch.
  if (near < head - kNavRejoinTargetM) out.add(near);
  return out;
}

class ReplanPlan {
  const ReplanPlan(this.outcome, {this.points, this.turnedBack = false});

  final ReplanOutcome outcome;

  /// Vom Standort über die Wege zum Ziel, mit den Anschlüssen an beiden
  /// Enden (wie „Zum Trailkopf").
  final List<LatLng>? points;

  /// Der Weg kehrt am Standort um — die freie Suche war so viel günstiger.
  final bool turnedBack;
}

enum ReplanOutcome { ok, startOffNetwork, targetOffNetwork, noPath }

/// Der neue Weg von [from] nach [target] auf [g]. [courseDeg] ist der
/// letzte GPS-Kurs (null: unbekannt — dann gibt es kein „zurück").
ReplanPlan planReplanRoute(RoadGraph g, LatLng from, double? courseDeg, LatLng target, RiderParams p) {
  final src = g.attach(from);
  if (src == null) return const ReplanPlan(ReplanOutcome.startOffNetwork);
  final dst = g.attach(target);
  if (dst == null) return const ReplanPlan(ReplanOutcome.targetOffNetwork);
  if (src == dst) return ReplanPlan(ReplanOutcome.ok, points: [from, target]);
  final back = courseDeg == null ? const <int>{} : backEdgesAt(g, src, courseDeg);
  final t = g.nodes[dst];
  final vMax = p.vDownKmh / 3.6;
  // Mal [kTrailConnectorFactor]: Ein Verbinder ist billiger als seine Zeit.
  double h(int n) => g.nodeDistance(n, t.x, t.y) / vMax * kTrailConnectorFactor;
  final free = dijkstra(g, src, p, target: dst, heuristic: h);
  var path = free.pathTo(dst);
  var turnedBack = path != null && path.isNotEmpty && back.contains(path.first);
  if (turnedBack) {
    final ahead = dijkstra(g, src, p, target: dst, heuristic: h, allow: (e) => !back.contains(e.index));
    final aheadPath = ahead.pathTo(dst);
    if (aheadPath != null && ahead.costTo(dst)! <= free.costTo(dst)! + kNavReplanTurnBackS) {
      path = aheadPath;
      turnedBack = false;
    }
  }
  if (path == null) return const ReplanPlan(ReplanOutcome.noPath);
  final summary = summarizePath(g, path, src, p);
  final line = summary.points.isEmpty ? [g.nodeLatLng[src]] : summary.points;
  return ReplanPlan(ReplanOutcome.ok, points: [from, ...line, target], turnedBack: turnedBack);
}

/// Die Kanten an [node], die gegen [courseDeg] führen — gemessen über
/// [kNavReplanBearingM] der Kante, nicht am ersten Punkt.
Set<int> backEdgesAt(RoadGraph g, int node, double courseDeg) {
  final out = <int>{};
  final at = g.nodeLatLng[node];
  for (var s = g.adjFirst(node); s >= 0; s = g.adjNext(s)) {
    final ei = s >> 1;
    final e = g.edges[ei];
    final pts = e.a == node ? e.points.toList() : e.points.toList().reversed.toList();
    var probe = pts.last;
    var walked = 0.0;
    for (var i = 1; i < pts.length; i++) {
      walked += geo.distanceMeters(pts[i - 1].latitude, pts[i - 1].longitude, pts[i].latitude, pts[i].longitude);
      if (walked >= kNavReplanBearingM) {
        probe = pts[i];
        break;
      }
    }
    final bearing = geo.bearingDegrees(at.latitude, at.longitude, probe.latitude, probe.longitude);
    final diff = ((bearing - courseDeg) % 360 + 360) % 360;
    if (math.min(diff, 360 - diff) > kNavReplanBackDeg) out.add(ei);
  }
  return out;
}

/// [planReplanRoute] auf dem Graphen drüben (wie `TrailHeadJob`).
class ReplanJob implements GraphJob<ReplanPlan> {
  const ReplanJob(this.from, this.courseDeg, this.target, this.profile);

  final LatLng from;
  final double? courseDeg;
  final LatLng target;
  final RiderParams profile;

  @override
  ReplanPlan runOn(RoadGraph g, LoopSearchCache cache) => planReplanRoute(g, from, courseDeg, target, profile);
}

/// Die neue Route: [line] (vom Standort bis zum Punkt [targetAlongM] der
/// alten Route), danach der Rest von [route] ab dort. Die Trails ab dem
/// Ziel rücken mit, die davor fallen weg — gefahren werden sie auf dieser
/// Route nicht mehr.
({List<LatLng> points, NavSections sections}) spliceReplan(
    NavRoute route, NavSections sections, List<LatLng> line, double targetAlongM) {
  final (_, rest) = route.splitAt(targetAlongM);
  final points = <LatLng>[...line];
  // Das Ziel steht am Ende der Linie und am Anfang des Rests: einmal.
  for (final p in rest.skip(points.isNotEmpty && rest.isNotEmpty && points.last == rest.first ? 1 : 0)) {
    points.add(p);
  }
  final lineM = cumulativeM(line).last;
  final shift = lineM - targetAlongM;
  final kept = [
    for (final t in sections.trails)
      if (t.startM >= targetAlongM - kNavSectionSnapM) t,
  ];
  return (
    points: points,
    sections: NavSections([
      for (var i = 0; i < kept.length; i++) kept[i].shifted(shift, newApproach: i == 0),
    ]),
  );
}
