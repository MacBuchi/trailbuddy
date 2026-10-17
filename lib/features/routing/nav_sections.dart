// Die Abschnitte einer Route für die Navigation (#312, Konzept-Routing
// 9.9): welche Trails auf der Linie liegen und wo. Pur — die Folgeansicht,
// der Dienst-Isolate und die Tests rechnen damit; was ein Trail sonst ist
// (Zustand, Hinweis), hängt hier als Text, nicht als Modell.
//
// Woher die Abschnitte kommen:
// - aus einer geplanten Runde (`LoopPlan.sections`, Trail je Abschnitt),
// - aus dem Weg zum Trailkopf (kein Trail AUF der Linie, der Ziel-Trail
//   steht am Ende — [NavTrailSection.beyondRoute]),
// - aus einer Fahrt, über das Trail-Netz mit der Korridor-Regel des
//   Zerlege-Blatts (`knownTrailSectionsOf`).
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../core/geo.dart' as geo;
import '../../l10n/l10n.dart';
import '../../models/trail.dart';
import '../rides/ride_split.dart' show knownTrailSectionsOf;
import 'loop_planner.dart' show LoopPlan, LoopSection;
import 'route_profile.dart' show WayClass;

/// Näher als das gilt ein Punkt der Linie als „derselbe" wie der Anfang
/// oder das Ende eines Abschnitts.
const kNavSectionSnapM = 5.0;

/// Ein Stück Weg einer Anfahrt: Klasse und Länge, in Reihenfolge.
typedef NavWayLeg = ({WayClass cls, double lengthM});

/// Der jüngste sichtbare Hinweis eines Buddys am Trail.
class NavNote {
  const NavNote({required this.body, required this.author, required this.createdAt});

  final String body;

  /// Benutzername des Autors; null heißt „ein Buddy".
  final String? author;
  final DateTime createdAt;
}

/// Ein Trail AUF der Route: Lage auf der Linie und was die Karten zeigen.
class NavTrailSection {
  const NavTrailSection({
    required this.startM,
    required this.endM,
    required this.trailId,
    required this.name,
    this.grade,
    this.uphill = false,
    this.traits = const [],
    this.lossM,
    this.condition,
    this.conditionAt,
    this.note,
    this.approachWays = const [],
    this.beyondRoute = false,
  }) : assert(endM >= startM);

  /// Lage auf der Linie, Meter ab Start.
  final double startM;
  final double endM;

  final String trailId;
  final String name;
  final int? grade;
  final bool uphill;

  /// Die angezeigten Merkmale (höchstens zwei).
  final List<TrailTrait> traits;

  /// Höhenmeter bergab des Trails; null ohne Höhen.
  final double? lossM;

  /// Der bestätigte Zustand (1–5, Wort über `trailCondition`), mit
  /// seinem Datum.
  final int? condition;
  final DateTime? conditionAt;

  final NavNote? note;

  /// Die Wege der Anfahrt davor, in Reihenfolge („Forstweg, dann 300 m
  /// Pfad"); leer, wenn unbekannt (Fahrt).
  final List<NavWayLeg> approachWays;

  /// Der Trail beginnt erst am Ende der Linie („Zum Trailkopf"): Die
  /// Anfahrt zählt bis zum Kopf, gefahren wird er nicht mehr auf der
  /// Route.
  final bool beyondRoute;

  double get lengthM => endM - startM;

  /// Für den Dienst (9.5): nur, was die Benachrichtigung braucht.
  List<Object?> encode() => [startM, endM, trailId, name, grade, lossM, beyondRoute];

  static NavTrailSection? decode(Object? raw) {
    if (raw is! List || raw.length < 7) return null;
    final s = raw[0], e = raw[1], id = raw[2], n = raw[3], g = raw[4], l = raw[5], b = raw[6];
    if (s is! num || e is! num || id is! String || n is! String || e < s) return null;
    return NavTrailSection(
      startM: s.toDouble(),
      endM: e.toDouble(),
      trailId: id,
      name: n,
      grade: g is num ? g.toInt() : null,
      lossM: l is num ? l.toDouble() : null,
      beyondRoute: b == true,
    );
  }
}

/// Alle Trails einer Route, nach Lage sortiert.
class NavSections {
  NavSections(List<NavTrailSection> trails)
      : trails = List<NavTrailSection>.unmodifiable(
            List<NavTrailSection>.of(trails)..sort((a, b) => a.startM.compareTo(b.startM)));

  const NavSections.empty() : trails = const [];

  static const none = NavSections.empty();

  final List<NavTrailSection> trails;

  bool get isEmpty => trails.isEmpty;

  /// Die Trails, die man wirklich fährt (nicht der Ziel-Trail hinter dem
  /// Ende).
  Iterable<NavTrailSection> get ridden => trails.where((t) => !t.beyondRoute);

  /// Der nächste Trail, dessen Anfang noch vor einem liegt (mit etwas
  /// Luft [slackM] zurück), oder null.
  NavTrailSection? nextFrom(double alongM, {double slackM = 0}) {
    for (final t in trails) {
      if (t.startM >= alongM - slackM) return t;
    }
    return null;
  }

  /// Der Trail, auf dem [alongM] liegt, oder null.
  NavTrailSection? at(double alongM) {
    for (final t in trails) {
      if (!t.beyondRoute && alongM >= t.startM && alongM <= t.endM) return t;
    }
    return null;
  }

  List<Object?> encode() => [for (final t in trails) t.encode()];

  static NavSections decode(Object? raw) {
    if (raw is! List) return none;
    return NavSections([for (final r in raw) ?NavTrailSection.decode(r)]);
  }
}

/// Distanz ab Start je Punkt der Linie.
List<double> cumulativeM(List<LatLng> points) {
  final cum = <double>[0];
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1], b = points[i];
    cum.add(cum.last + geo.distanceMeters(a.latitude, a.longitude, b.latitude, b.longitude));
  }
  return cum;
}

/// Wo [target] auf der Linie liegt: der nächste Punkt ab Index [from],
/// als (Index, Meter). Gesucht wird vorwärts, damit eine Runde, die eine
/// Stelle zweimal berührt, die zweite nicht mit der ersten verwechselt.
(int, double) _locate(List<LatLng> points, List<double> cum, LatLng target, int from) {
  var best = from;
  var bestD = double.infinity;
  for (var i = from; i < points.length; i++) {
    final d = geo.distanceMeters(points[i].latitude, points[i].longitude, target.latitude, target.longitude);
    if (d < bestD) {
      bestD = d;
      best = i;
      if (d <= kNavSectionSnapM) break;
    }
  }
  return (best, cum[best]);
}

/// Was die Karten über einen Trail wissen wollen — aus dem Netz, wenn er
/// dort liegt; sonst nur, was der Planer mitbringt.
NavTrailSection _sectionOf(AppLocalizations l, {
  required double startM,
  required double endM,
  required String id,
  required String name,
  int? grade,
  double? lossM,
  Trail? trail,
  List<NavWayLeg> approachWays = const [],
  bool beyondRoute = false,
}) {
  final traits = trail?.topTraits ?? const <TrailTrait>[];
  final condition = trail?.shownCondition.confirmed;
  final note = trail == null ? null : _latestNote(trail);
  return NavTrailSection(
    startM: startM,
    endM: endM,
    trailId: id,
    name: trail?.displayName(l) ?? name,
    grade: trail?.grade ?? grade,
    uphill: traits.contains(TrailTrait.uphill),
    traits: traits,
    lossM: trail?.elevation?.lossM ?? lossM,
    condition: condition?.condition,
    conditionAt: condition?.condition == null ? null : condition!.reportedAt,
    note: note,
    approachWays: approachWays,
    beyondRoute: beyondRoute,
  );
}

NavNote? _latestNote(Trail trail) {
  TrailNote? latest;
  for (final n in trail.notes) {
    if (latest == null || n.createdAt.isAfter(latest.createdAt)) latest = n;
  }
  if (latest == null) return null;
  return NavNote(body: latest.body, author: latest.username, createdAt: latest.createdAt);
}

/// Die Wege zwischen zwei Trails, aufeinanderfolgende gleiche Klassen
/// zusammengefasst.
List<NavWayLeg> _legsOf(Iterable<({WayClass? cls, double lengthM})> parts) {
  final out = <NavWayLeg>[];
  for (final p in parts) {
    final cls = p.cls;
    if (cls == null || p.lengthM <= 0) continue;
    if (out.isNotEmpty && out.last.cls == cls) {
      out[out.length - 1] = (cls: cls, lengthM: out.last.lengthM + p.lengthM);
    } else {
      out.add((cls: cls, lengthM: p.lengthM));
    }
  }
  return out;
}

/// Die Abschnitte einer geplanten Runde oder Route (auch des spaßigen Wegs
/// zum Trailkopf). [trailById] holt den Trail aus dem Netz — null, wenn er
/// dort nicht liegt, dann gelten die Werte des Planers. Mit [beyond] (das
/// Ziel ist sein Kopf, #356 PR 7) steht dieser Trail hinter dem Ende, wie
/// bis 0.129 im Blatt „Route" (`navSectionsOfTrailHead`).
NavSections navSectionsOfLoop(AppLocalizations l, LoopPlan plan,
    {required Trail? Function(String id) trailById, Trail? beyond}) {
  final points = plan.points;
  if (points.length < 2) return NavSections.none;
  final cum = cumulativeM(points);
  final out = <NavTrailSection>[];
  var from = 0;
  var legs = <({WayClass? cls, double lengthM})>[];
  for (final LoopSection s in plan.sections) {
    if (s.points.isEmpty) continue;
    final trail = s.trail;
    if (trail == null) {
      legs.add((cls: s.cls, lengthM: s.lengthM));
      continue;
    }
    final (i0, startM) = _locate(points, cum, s.points.first, from);
    final (i1, endM) = _locate(points, cum, s.points.last, i0);
    from = i1;
    out.add(_sectionOf(l,
      startM: startM,
      endM: math.max(endM, startM),
      id: trail.id,
      name: trail.name,
      grade: trail.grade,
      lossM: trail.lossM,
      trail: trailById(trail.id),
      approachWays: _legsOf(legs),
    ));
    legs = [];
  }
  if (beyond != null) {
    final lengthM = cum.last;
    out.add(_sectionOf(l,
      startM: lengthM,
      endM: lengthM,
      id: beyond.id,
      name: beyond.displayName(l),
      trail: beyond,
      approachWays: _legsOf(legs),
      beyondRoute: true,
    ));
  }
  return NavSections(out);
}

/// Die Abschnitte einer Fahrt: die Trails des Netzes, die die Linie deckt
/// (dieselbe Regel wie „bekannt" im Zerlege-Blatt).
NavSections navSectionsOfLine(AppLocalizations l, List<LatLng> points, List<Trail> trails) {
  if (points.length < 2 || trails.isEmpty) return NavSections.none;
  final cum = cumulativeM(points);
  final known = knownTrailSectionsOf(points, trails);
  return NavSections([
    for (final k in known)
      _sectionOf(l,
        startM: cum[k.start],
        endM: math.max(cum[k.end], cum[k.start]),
        id: k.trail.id,
        name: k.trail.displayName(l),
        trail: k.trail,
      ),
  ]);
}
