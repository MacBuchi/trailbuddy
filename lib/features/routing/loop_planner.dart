// Die Trail-zuerst-Runde (#158 Schritt 5, docs/konzept-routing.md 1, 2.3,
// 3): Start, Budget, Pool — und heraus kommt eine Runde, die möglichst
// viele Trails BERGAB in ihrer Richtung mitnimmt, verbunden durch
// Aufstiege aus dem Wegegraphen der gespeicherten Bereiche. Pur: Graph,
// Start, Profil, Budget und Pool rein, die Runde mit Abschnitten, Summen,
// Reihenfolge und den Trails, die NICHT hineingepasst haben, raus.
//
// Der Algorithmus ist Konzept-Routing 3, Punkt für Punkt:
// 1. Aufstiege zwischen allen Trail-Enden: ein begrenzter Dijkstra vom
//    Start und von jedem Trail-Ende (`dijkstra` mit `limit`), die
//    Verbindung je Paar wird erst beim ersten Bedarf zusammengefasst und
//    dann gemerkt — mit einem [LoopSearchCache] auch über die Rechnung
//    hinaus, solange Graph, Profil und Zeitbudget dieselben sind (#188).
// 2. Verkettung: Pflicht-Trails zuerst (an die beste Stelle, nie wieder
//    entfernt), dann greedy einfügen nach „Trail-Meter je Zeitzuwachs",
//    dann lokale Suche (Entfernen und Einfügen, Vertauschen) mit festem
//    Zeitdeckel.
// 3. Zielfunktion: mehr Trail-Meter, bei Gleichstand weniger Aufstieg,
//    dann weniger verschenkte Höhe — alles unter den drei Budgets; auf die
//    Zeit bleibt eine Reserve von 10 % (die Schätzung kennt keine Pausen).
//    Ein Trail zweimal bringt keine Trail-Meter — außer er trägt 4 oder 5
//    Sterne, dann noch 30 % —, kostet aber Zeit und Aufstieg voll und
//    steht höchstens zweimal in der Runde.
// 4. Ergebnis: Linie mit Abschnitten (Aufstieg nach Klasse, Trail),
//    Summen, die Trails in Reihenfolge, die ausgelassenen mit Grund.
//
// Die Engine urteilt nie über Erlaubnis (Konzept 7): Wanderweg zählt gegen
// das Budget und steht im Ergebnis; ob man dort fahren darf, sagt sie
// nicht. Rein, ohne Widgets, ohne Riverpod, ohne Platte.
import 'package:latlong2/latlong.dart';

import '../../models/trail.dart';
import '../trails/gpx.dart';
import '../trails/trail_geometry.dart' show haversineM;
import 'road_graph.dart';
import 'route_profile.dart';
import 'route_search.dart';
import 'route_vias.dart';
import 'trail_head_route.dart' show RouteSection, sectionsOf;
import 'trail_overlay.dart';

/// Reserve auf die Zeit: Geplant wird auf 90 % des Zeitbudgets
/// (Konzept-Routing 2.3) — die Schätzung kennt keine Pausen.
const kLoopTimeReserve = 0.10;

/// Ab dieser Bewertung (Median, wie angezeigt) bringt eine ZWEITE
/// Abfahrt desselben Trails noch Trail-Meter — [kLoopSecondPassShare]
/// davon (Betreiber, 2026-10-01: „vor allem wenn nicht mit 4–5 Sternen
/// bewertet vom Buddy").
const kLoopSecondPassRating = 4;
const kLoopSecondPassShare = 0.3;

/// Wie oft ein Trail höchstens in einer Runde steht.
const kLoopMaxPasses = 2;

/// Wie lange die lokale Suche nach dem greedy Einfügen höchstens läuft
/// (Konzept-Routing 3.2: fester Zeitdeckel). Im Test über [planLoop]s
/// `searchBudget` kürzer.
const kLoopSearchBudget = Duration(milliseconds: 300);

/// Die drei Regler (Konzept-Routing 2.3), in Sekunden, Metern, Metern.
class LoopBudget {
  const LoopBudget({required this.timeS, required this.climbM, required this.hikingM});

  final double timeS;
  final double climbM;
  final double hikingM;

  /// Die Zeit, die die Planung wirklich verplant: Budget minus Reserve.
  double get plannedTimeS => timeS * (1 - kLoopTimeReserve);
}

/// Ein Trail im Pool: Punkte in Trail-Richtung, S-Grad und Sterne wie
/// angezeigt (Median), Höhenmeter entlang des Trails (0, wenn er keine
/// Höhen hat), und ob er auf jeden Fall in die Runde soll.
class PoolTrail {
  const PoolTrail({
    required this.id,
    required this.name,
    required this.points,
    required this.lengthM,
    this.grade,
    this.rating,
    this.gainM = 0,
    this.lossM = 0,
    this.mandatory = false,
  }) : assert(points.length >= 2);

  final String id;
  final String name;
  final List<LatLng> points;
  final double lengthM;
  final int? grade;
  final int? rating;
  final double gainM;
  final double lossM;
  final bool mandatory;

  LatLng get start => points.first;
  LatLng get end => points.last;

  /// Die Zeit bergab, nach S-Grad (Konzept-Routing 2.2).
  double get timeS => trailTimeS(lengthM: lengthM, grade: grade);

  /// Was die zweite Abfahrt noch an Trail-Metern bringt.
  double get secondPassM =>
      (rating ?? 0) >= kLoopSecondPassRating ? lengthM * kLoopSecondPassShare : 0;
}

enum LoopOutcome {
  ok,

  /// In [kGraphAttachM] um den Start liegt kein Weg aus den Kacheln.
  startOffNetwork,

  /// In [kGraphAttachM] um das Ziel liegt kein Weg aus den Kacheln.
  endOffNetwork,

  /// Kein Trail des Pools passt in die Runde — die Gründe stehen je
  /// Trail in [LoopPlan.excluded].
  empty,

  /// Von Hand getunt ([LoopTune]), aber ein Zwischenpunkt liegt abseits
  /// jedes Wegs, oder durch die Punkte führt kein Weg.
  viaFailed,
}

/// Die Runde von Hand getunt (#234): Die Folge der Trails steht fest
/// ([order], Kennungen, eine zweite Abfahrt zweimal), gesucht werden nur
/// die Teilstücke — durch ihre Zwischenpunkte ([vias]). Budgets prüft
/// niemand: Den Weg hat der Fahrer gewählt, das Blatt sagt die Summen.
class LoopTune {
  const LoopTune({required this.order, this.vias = RouteVias.none});

  /// Aus einer gerechneten Runde: ihre Folge, mit [vias].
  factory LoopTune.of(LoopPlan plan, RouteVias vias) =>
      LoopTune(order: [for (final s in plan.stops) s.trail.id], vias: vias);

  final List<String> order;
  final RouteVias vias;
}

/// Warum ein Trail NICHT in der Runde ist.
enum LoopExclusion {
  /// Nicht im Pool gerechnet: zu weit vom Start (Konzept-Routing 3.4,
  /// „zu weit") — gesetzt vom Aufrufer, der den Pool schneidet.
  tooFar,

  /// Anfang oder Ende hängen an keinem Weg in [kGraphAttachM].
  offNetwork,

  /// Beide Enden hängen am Graphen, aber vom Start oder von den anderen
  /// Trails führt kein Weg im Budget dorthin (Insel, Einbahn).
  unreachable,

  /// Erreichbar, aber mit ihm wäre eines der drei Budgets überschritten.
  budget,
}

/// Ein Stück der Runde: eine Verbindung EINER Wegklasse ([cls]) oder ein
/// Trail ([trail], [cls] null). Die Vorschau zeichnet Trail, Forstweg und
/// Wanderweg verschieden, die Liste zählt den Mix.
class LoopSection {
  const LoopSection({
    required this.points,
    required this.lengthM,
    this.cls,
    this.trail,
    this.secondPass = false,
    this.onTrail,
    this.leg,
  });

  final List<LatLng> points;
  final double lengthM;
  final WayClass? cls;
  final PoolTrail? trail;

  /// Eine Verbindung über einen Uphill-Trail oder Verbinder (#185).
  final EdgeTrail? onTrail;

  /// Dieser Trail steht zum zweiten Mal in der Runde.
  final bool secondPass;

  /// Bei einer Verbindung: das Teilstück (0 = vom Start zum ersten Trail)
  /// — wohin ein Zwischenpunkt gehört, der auf sie getippt wird (#234).
  final int? leg;

  bool get isTrail => trail != null;

  /// Zählt gegen „höchstens Wanderweg" — gestrichelt in der Vorschau.
  bool get hiking => (cls?.hiking ?? false) && !(onTrail?.connector ?? false);
}

/// Die Summen der Runde (Konzept-Routing 3.4).
class LoopSummary {
  const LoopSummary({
    required this.lengthM,
    required this.gainM,
    required this.lossM,
    required this.trailM,
    required this.trailLossM,
    required this.timeS,
    required this.hikingM,
    required this.wastedLossM,
    required this.mix,
    required this.heightsComplete,
    this.trailUpM = 0,
    this.trailUpNames = const [],
    this.steepM = 0,
  });

  final double lengthM;

  /// Meter über Uphill-Trails und Verbinder (#185), und deren Namen.
  final double trailUpM;
  final List<String> trailUpNames;

  /// Höhenmeter über der Steilgrenze auf den Verbindungen (#194).
  final double steepM;

  /// Höhenmeter bergauf — Verbindungen und Gegenanstiege auf Trails.
  final double gainM;
  final double lossM;

  /// Gefahrene Trail-Meter (die Zielfunktion): jede erste Abfahrt voll,
  /// eine zweite nur ihren Anteil.
  final double trailM;

  /// Höhenmeter bergab AUF Trails.
  final double trailLossM;

  /// Geschätzte Zeit ohne Reserve — Verbindungen nach Zeitmodell, Trails
  /// nach S-Grad.
  final double timeS;

  /// Meter auf Wanderweg, Fußweg und Stufen (Verbindungen).
  final double hikingM;

  /// Verschenkte Höhe: bergab auf Verbindungen statt auf einem Trail.
  final double wastedLossM;

  /// Verbindungs-Meter je Wegklasse.
  final Map<WayClass, double> mix;

  /// Falsch, sobald eine Verbindung eine Kante ohne Höhen hatte.
  final bool heightsComplete;
}

/// Ein Trail in der Runde, in Reihenfolge.
typedef LoopStop = ({PoolTrail trail, bool secondPass});

class LoopPlan {
  const LoopPlan(
    this.outcome, {
    this.sections = const [],
    this.summary,
    this.stops = const [],
    this.excluded = const {},
    this.points = const [],
  });

  final LoopOutcome outcome;
  final List<LoopSection> sections;
  final LoopSummary? summary;
  final List<LoopStop> stops;

  /// Je Kennung eines Trails, der nicht in der Runde steht, der Grund.
  final Map<String, LoopExclusion> excluded;

  /// Die ganze Linie: Start → Verbindungen und Trails → Ziel. Wie bei
  /// „Zum Trailkopf" tragen die Verbinder (Start → erster Wegpunkt,
  /// letzter Wegpunkt → Ziel) die Linie, zählen aber nicht.
  final List<LatLng> points;

  bool get isEmpty => stops.isEmpty;
}

/// Eine Verbindung zwischen zwei Knoten, zusammengefasst.
class _Conn {
  _Conn(this.from, this.edges, this.summary);

  final int from;
  final List<int> edges;
  final PathSummary summary;
}

/// Was der Planer von einer Rechnung zur nächsten behält (#188): die
/// begrenzten Suchen je Startknoten und die Verbindungen daraus. Sie sind
/// der teure Teil — eine Suche je Trail-Ende, und mit 40 Trails rechnete
/// der Planer auch die zweite Runde noch 1,6 s. Wer einen Trail ab- und
/// wieder anwählt, das Höhenbudget oder die Pflicht ändert, fragt dieselben
/// Suchen noch einmal.
///
/// Gültig nur für DENSELBEN Graphen im selben Stand
/// ([RoadGraph.revision]: Eine Teilung beim Anheften ließe gemerkte
/// Vorgänger auf eine Kante zeigen, die jetzt woanders endet), dasselbe
/// Profil (Werte, nicht Name — die gelernten zählen mit) und dasselbe
/// Zeitbudget (die Grenze der Suche). Alles andere leert ihn. Er hält nur
/// EINEN Stand — mehr Speicher, als eine Rechnung ohnehin braucht, kostet
/// er nicht.
class LoopSearchCache {
  RoadGraph? _graph;
  var _revision = -1;
  Object? _scope;
  final _searches = <(int, bool), SearchResult>{};
  final _conns = <(int, int, bool), _Conn?>{};

  /// Wie viele Suchen wirklich gelaufen sind (nicht aus dem Speicher) —
  /// für Test und Messung.
  int searchesRun = 0;

  void _bind(RoadGraph g, Object scope) {
    if (identical(g, _graph) && g.revision == _revision && scope == _scope) return;
    _graph = g;
    _revision = g.revision;
    _scope = scope;
    _searches.clear();
    _conns.clear();
  }
}

/// Alles am Profil, wovon Kosten und Zeit einer Kante abhängen.
Object _riderKey(RiderParams p) => (
      p.profile,
      p.climbTrackMPerH,
      p.climbPathMPerH,
      p.pushRateMPerH,
      p.vFlatKmh,
      p.vPathUpKmh,
      p.vPushKmh,
      p.vDownKmh,
      p.pathUpFactor,
      p.pathDownFactor,
      p.prefs,
    );

/// Der Zustand einer Runde als Folge von Pool-Indizes, mit den Summen
/// und der gewählten Verbindung je Abschnitt ([legs]: eine je Halt, dazu
/// die letzte zurück zum Ziel, wenn es eines gibt).
class _Route {
  _Route(this.seq, this.legs, this.timeS, this.climbM, this.hikingM, this.wastedM, this.trailM);

  final List<int> seq;
  final List<_Conn> legs;
  final double timeS;
  final double climbM;
  final double hikingM;
  final double wastedM;
  final double trailM;

  /// Besser im Sinn der Zielfunktion (Konzept-Routing 3.3).
  bool beats(_Route other) {
    if ((trailM - other.trailM).abs() > 0.5) return trailM > other.trailM;
    if ((climbM - other.climbM).abs() > 0.5) return climbM < other.climbM;
    return wastedM < other.wastedM - 0.5;
  }
}

/// Plant die Runde auf [g]: von [start] über Trails aus [pool] zurück
/// zum Start ([returnToStart]), zu einem Ziel [end] (der „spaßige" Weg zu
/// einem Trail oder Punkt, #176/#177) oder mit offenem Ende. Trails, deren
/// Kennung in [excluded] steht, hat der Aufrufer schon ausgeschlossen
/// (zu weit); sie kommen so ins Ergebnis.
///
/// Die Trails des Netzes liegen vorher schon auf [g] (`applyTrails`):
/// Richtung und Verbinder kennt die Suche dann von selbst.
///
/// Mit [cache] behält der Planer seine Suchen für die nächste Rechnung auf
/// demselben Graphen (der Rechen-Isolate, #188); ohne rechnet er alles neu.
LoopPlan planLoop(
  RoadGraph g, {
  required LatLng start,
  required RiderParams profile,
  required LoopBudget budget,
  required List<PoolTrail> pool,
  bool returnToStart = true,
  LatLng? end,
  Map<String, LoopExclusion> excluded = const {},
  Duration searchBudget = kLoopSearchBudget,
  LoopSearchCache? cache,
  LoopTune? tune,
}) {
  final out = Map<String, LoopExclusion>.of(excluded);
  final src = g.attach(start);
  if (src == null) {
    for (final t in pool) {
      out.putIfAbsent(t.id, () => LoopExclusion.unreachable);
    }
    return LoopPlan(LoopOutcome.startOffNetwork, excluded: out);
  }
  int? dst = returnToStart ? src : null;
  if (end != null) {
    dst = g.attach(end);
    if (dst == null) {
      for (final t in pool) {
        out.putIfAbsent(t.id, () => LoopExclusion.unreachable);
      }
      return LoopPlan(LoopOutcome.endOffNetwork, excluded: out);
    }
  }
  // Jeder Trail an den Graphen — ein Ende ohne Weg heißt „nicht
  // erreichbar", und zwar bevor irgendetwas gesucht wird.
  final heads = <int?>[], tails = <int?>[];
  for (final t in pool) {
    if (out.containsKey(t.id)) {
      heads.add(null);
      tails.add(null);
      continue;
    }
    final h = g.attach(t.start), e = g.attach(t.end);
    if (h == null || e == null) out[t.id] = LoopExclusion.offNetwork;
    heads.add(h);
    tails.add(e);
  }
  // Erst NACH dem Anheften: Hat es eine Kante geteilt, gilt nichts
  // Gemerktes mehr.
  final searches = (cache ?? LoopSearchCache()).._bind(g, (_riderKey(profile), budget.timeS));
  final planner =
      _Planner(g, start, src, dst, end ?? start, profile, budget, pool, heads, tails, out, searches);
  return tune == null ? planner.run(searchBudget) : planner.runTuned(tune);
}

class _Planner {
  _Planner(this.g, this.start, this.src, this.dst, this.finish, this.p, this.budget, this.pool, this.heads,
      this.tails, this.excluded, this.cache);

  final RoadGraph g;
  final LatLng start;
  final int src;
  final int? dst;

  /// Wo die Linie endet, wenn es ein Ziel gibt: der Start oder [planLoop]s
  /// `end`.
  final LatLng finish;
  final RiderParams p;
  final LoopBudget budget;
  final List<PoolTrail> pool;
  final List<int?> heads;
  final List<int?> tails;
  final Map<String, LoopExclusion> excluded;

  /// Je Startknoten zwei Suchen: die günstigste, und die ohne Wanderweg,
  /// Fußweg und Stufen — die zweite nur, wenn die erste das Budget
  /// „höchstens Wanderweg" sprengt. Gemerkt im [LoopSearchCache], mit den
  /// Verbindungen daraus.
  final LoopSearchCache cache;

  bool usable(int i) => heads[i] != null && tails[i] != null && !excluded.containsKey(pool[i].id);

  SearchResult _search(int from, {required bool noHiking}) => cache._searches.putIfAbsent((from, noHiking), () {
        cache.searchesRun++;
        return dijkstra(g, from, p, limit: budget.timeS, allow: noHiking ? (e) => !e.hiking : null);
      });

  /// Die Verbindung [from] → [to], oder null, wenn keine im Budget liegt.
  _Conn? conn(int from, int to, {bool noHiking = false}) => cache._conns.putIfAbsent((from, to, noHiking), () {
        if (from == to) return _Conn(from, const [], summarizePath(g, const [], from, p));
        final path = _search(from, noHiking: noHiking).pathTo(to);
        if (path == null) return null;
        return _Conn(from, path, summarizePath(g, path, from, p));
      });

  /// Die Summen einer Folge, oder null, wenn eine Verbindung fehlt.
  ///
  /// Zuerst mit den günstigsten Verbindungen; liegt damit mehr Wanderweg
  /// in der Runde, als das Budget erlaubt, bekommt die Verbindung mit dem
  /// meisten Wanderweg ihre Fassung OHNE — so lange, bis es passt oder
  /// keine Fassung mehr da ist. Eine Verbindung, die nur über Wanderweg
  /// geht, bleibt dann stehen, und die Runde scheitert am Budget.
  _Route? evaluate(List<int> seq) {
    final froms = <int>[], tos = <int>[];
    var at = src;
    for (final i in seq) {
      froms.add(at);
      tos.add(heads[i]!);
      at = tails[i]!;
    }
    final end = dst;
    if (end != null) {
      froms.add(at);
      tos.add(end);
    }
    final legs = <_Conn>[];
    for (var k = 0; k < froms.length; k++) {
      final c = conn(froms[k], tos[k]);
      if (c == null) return null;
      legs.add(c);
    }
    double hikingOf(List<_Conn> l) => l.fold(0.0, (s, c) => s + c.summary.hikingM);
    final tried = <int>{};
    while (hikingOf(legs) > budget.hikingM + 1e-6) {
      var worst = -1;
      for (var k = 0; k < legs.length; k++) {
        if (tried.contains(k) || legs[k].summary.hikingM <= 0) continue;
        if (worst < 0 || legs[k].summary.hikingM > legs[worst].summary.hikingM) worst = k;
      }
      if (worst < 0) break;
      tried.add(worst);
      final alt = conn(froms[worst], tos[worst], noHiking: true);
      if (alt != null) legs[worst] = alt;
    }
    var time = 0.0, climb = 0.0, hiking = 0.0, wasted = 0.0, trailM = 0.0;
    final seen = <int>{};
    for (var k = 0; k < seq.length; k++) {
      final t = pool[seq[k]];
      time += t.timeS;
      climb += t.gainM;
      trailM += seen.add(seq[k]) ? t.lengthM : t.secondPassM;
    }
    for (final c in legs) {
      time += c.summary.timeS;
      climb += c.summary.gainM;
      hiking += c.summary.hikingM;
      wasted += c.summary.lossM;
    }
    return _Route(seq, legs, time, climb, hiking, wasted, trailM);
  }

  bool fits(_Route r) =>
      r.timeS <= budget.plannedTimeS + 1e-6 &&
      r.climbM <= budget.climbM + 1e-6 &&
      r.hikingM <= budget.hikingM + 1e-6;

  int passes(List<int> seq, int i) => seq.where((x) => x == i).length;

  /// Die beste Stelle für [i] in [base]: der kleinste Zeitzuwachs, der
  /// in die Budgets passt. Null, wenn keine passt.
  ({_Route route, double dt})? bestInsertion(_Route base, int i, {bool mustFit = true}) {
    ({_Route route, double dt})? best;
    for (var pos = 0; pos <= base.seq.length; pos++) {
      final seq = [...base.seq]..insert(pos, i);
      final r = evaluate(seq);
      if (r == null || (mustFit && !fits(r))) continue;
      final dt = r.timeS - base.timeS;
      if (best == null || dt < best.dt) best = (route: r, dt: dt);
    }
    return best;
  }

  LoopPlan run(Duration searchBudget) {
    // Ohne Trail muss schon der Weg zum Ziel gehen — sonst gibt es nichts
    // zu planen, und jeder Trail hieße „nicht erreichbar".
    final bare = evaluate(const []);
    if (bare == null) {
      for (final t in pool) {
        excluded.putIfAbsent(t.id, () => LoopExclusion.unreachable);
      }
      return LoopPlan(LoopOutcome.empty, excluded: excluded);
    }
    var route = bare;
    // 1. Pflicht-Trails, in Pool-Reihenfolge, je an die beste Stelle. Was
    //    nicht passt, bleibt draußen — mit seinem Grund.
    for (var i = 0; i < pool.length; i++) {
      if (!pool[i].mandatory || !usable(i)) continue;
      final ins = bestInsertion(route, i);
      if (ins == null) {
        excluded[pool[i].id] = bestInsertion(route, i, mustFit: false) == null
            ? LoopExclusion.unreachable
            : LoopExclusion.budget;
        continue;
      }
      route = ins.route;
    }
    final fixed = {...route.seq};
    // 2. Greedy: der Kandidat mit den meisten Trail-Metern je Sekunde
    //    Zuwachs; zweite Abfahrten nur, wenn sie etwas bringen.
    while (true) {
      ({int i, _Route route, double ratio})? best;
      for (var i = 0; i < pool.length; i++) {
        if (!usable(i)) continue;
        final n = passes(route.seq, i);
        if (n >= kLoopMaxPasses) continue;
        final gain = n == 0 ? pool[i].lengthM : pool[i].secondPassM;
        if (gain <= 0) continue;
        final ins = bestInsertion(route, i);
        if (ins == null) continue;
        final ratio = gain / (ins.dt <= 1 ? 1 : ins.dt);
        if (best == null || ratio > best.ratio) best = (i: i, route: ins.route, ratio: ratio);
      }
      if (best == null) break;
      route = best.route;
    }
    // 3. Lokale Suche mit Zeitdeckel: einen Halt gegen einen anderen
    //    tauschen oder herausnehmen und etwas Besseres einfügen; zwei
    //    Halte vertauschen. Nur Verbesserungen im Sinn der Zielfunktion.
    final clock = Stopwatch()..start();
    var improved = true;
    while (improved && clock.elapsed < searchBudget) {
      improved = false;
      for (var a = 0; a < route.seq.length && !improved; a++) {
        if (fixed.contains(route.seq[a]) && passes(route.seq, route.seq[a]) == 1) continue;
        final without = evaluate([...route.seq]..removeAt(a));
        if (without == null) continue;
        for (var i = 0; i < pool.length; i++) {
          if (!usable(i) || i == route.seq[a]) continue;
          if (passes(without.seq, i) >= kLoopMaxPasses) continue;
          final ins = bestInsertion(without, i);
          if (ins != null && ins.route.beats(route)) {
            route = ins.route;
            improved = true;
            break;
          }
        }
        if (!improved && without.beats(route) && fits(without)) {
          route = without;
          improved = true;
        }
      }
      for (var a = 0; a < route.seq.length && !improved; a++) {
        for (var b = a + 1; b < route.seq.length; b++) {
          final seq = [...route.seq];
          final t = seq[a];
          seq[a] = seq[b];
          seq[b] = t;
          final r = evaluate(seq);
          if (r != null && fits(r) && r.beats(route)) {
            route = r;
            improved = true;
            break;
          }
        }
      }
    }
    // 4. Die Gründe für alles, was nicht drin ist.
    for (var i = 0; i < pool.length; i++) {
      final t = pool[i];
      if (excluded.containsKey(t.id) || route.seq.contains(i)) continue;
      excluded[t.id] = bestInsertion(route, i, mustFit: false) == null
          ? LoopExclusion.unreachable
          : LoopExclusion.budget;
    }
    return _assemble(route);
  }

  /// Die festgelegte Folge, jedes Teilstück durch seine Zwischenpunkte.
  /// Die Suchen laufen frisch (A* je Abschnitt): Das Anheften der Punkte
  /// teilt Kanten, und der Speicher gilt danach ohnehin nicht mehr.
  LoopPlan runTuned(LoopTune tune) {
    final index = {for (var i = 0; i < pool.length; i++) pool[i].id: i};
    final seq = [
      for (final id in tune.order)
        if (index[id] case final i? when usable(i)) i,
    ];
    if (seq.isEmpty) return LoopPlan(LoopOutcome.empty, excluded: excluded);
    final froms = <int>[], tos = <int>[];
    var at = src;
    for (final i in seq) {
      froms.add(at);
      tos.add(heads[i]!);
      at = tails[i]!;
    }
    if (dst != null) {
      froms.add(at);
      tos.add(dst!);
    }
    final legs = <_Conn>[];
    for (var k = 0; k < froms.length; k++) {
      final r = pathThrough(g, froms[k], tos[k], tune.vias.of(k), p);
      if (r.edges == null) return LoopPlan(LoopOutcome.viaFailed, excluded: excluded);
      legs.add(_Conn(froms[k], r.edges!, summarizePath(g, r.edges!, froms[k], p)));
    }
    var time = 0.0, climb = 0.0, hiking = 0.0, wasted = 0.0, trailM = 0.0;
    final seen = <int>{};
    for (final i in seq) {
      final t = pool[i];
      time += t.timeS;
      climb += t.gainM;
      trailM += seen.add(i) ? t.lengthM : t.secondPassM;
    }
    for (final c in legs) {
      time += c.summary.timeS;
      climb += c.summary.gainM;
      hiking += c.summary.hikingM;
      wasted += c.summary.lossM;
    }
    for (var i = 0; i < pool.length; i++) {
      if (!seq.contains(i)) excluded.putIfAbsent(pool[i].id, () => LoopExclusion.budget);
    }
    return _assemble(_Route(seq, legs, time, climb, hiking, wasted, trailM));
  }

  LoopPlan _assemble(_Route route) {
    if (route.seq.isEmpty) return LoopPlan(LoopOutcome.empty, excluded: excluded);
    final sections = <LoopSection>[];
    // Die Linie beginnt am Start selbst, nicht am Anschlussknoten — wie
    // bei „Zum Trailkopf" trägt der Verbinder die Linie, zählt aber nicht.
    final points = <LatLng>[start, g.nodeLatLng[src]];
    final mix = <WayClass, double>{};
    final upNames = <String>[];
    var length = 0.0, gain = 0.0, loss = 0.0, trailLoss = 0.0, trailUp = 0.0, steep = 0.0;
    var complete = true;
    final seen = <int>{};
    final stops = <LoopStop>[];
    var leg = 0;
    void connect(int from) {
      final k = leg++;
      final c = route.legs[k];
      for (final s in sectionsOf(g, c.edges, from)) {
        sections.add(LoopSection(points: s.points, lengthM: s.lengthM, cls: s.cls, onTrail: s.trail, leg: k));
        final up = s.trail;
        if (up != null && up.connector) {
          // Uphill-Trails und Verbinder stehen für sich, nicht unter der
          // Kartenklasse („Wanderweg"), die sie in OSM tragen.
          trailUp += s.lengthM;
          if (!upNames.contains(up.name)) upNames.add(up.name);
        } else {
          mix[s.cls] = (mix[s.cls] ?? 0) + s.lengthM;
        }
      }
      if (c.summary.points.isNotEmpty) points.addAll(c.summary.points.skip(1));
      length += c.summary.lengthM;
      gain += c.summary.gainM;
      loss += c.summary.lossM;
      steep += c.summary.steepM;
      if (!c.summary.heightsComplete) complete = false;
    }

    var at = src;
    for (final i in route.seq) {
      final t = pool[i];
      connect(at);
      final second = !seen.add(i);
      sections.add(LoopSection(points: t.points, lengthM: t.lengthM, trail: t, secondPass: second));
      stops.add((trail: t, secondPass: second));
      points.addAll(t.points);
      length += t.lengthM;
      gain += t.gainM;
      loss += t.lossM;
      trailLoss += t.lossM;
      at = tails[i]!;
      points.add(g.nodeLatLng[at]);
    }
    final end = dst;
    if (end != null) {
      connect(at);
      points.add(finish);
    }
    return LoopPlan(
      LoopOutcome.ok,
      sections: sections,
      summary: LoopSummary(
        lengthM: length,
        gainM: gain,
        lossM: loss,
        trailM: route.trailM,
        trailLossM: trailLoss,
        timeS: route.timeS,
        hikingM: route.hikingM,
        wastedLossM: route.wastedM,
        mix: mix,
        heightsComplete: complete,
        trailUpM: trailUp,
        trailUpNames: upNames,
        steepM: steep,
      ),
      stops: stops,
      excluded: excluded,
      points: points,
    );
  }
}

/// Die Vorschau-Abschnitte einer Verbindung als [RouteSection] — damit
/// das Blatt dieselbe Zeichenregel wie „Zum Trailkopf" nehmen kann.
List<RouteSection> connectionSections(LoopPlan plan) => [
      for (final s in plan.sections)
        if (s.cls != null) RouteSection(cls: s.cls!, points: s.points, lengthM: s.lengthM, trail: s.onTrail),
    ];

// ─── Pool, Vorgaben, Name und GPX ──────────────────────────────────────

/// Vorgabe für den Radius der Trail-Liste (Konzept-Routing 3.4, „zu
/// weit"): Bei 3 h Budget wäre schon die Anfahrt die halbe Runde, und der
/// Graph bliebe handlich (Konzept-Routing 2.7: ein 20-km-Rahmen sind rund
/// 70 Kacheln). Seit 0.74.0 einstellbar (`LoopPrefs.radiusKm`) — und er
/// begrenzt nur die LISTE: Was auf der Karte angetippt ist, gehört dazu.
const kLoopReachM = 12000.0;

/// Ein Trail der Karte als Pool-Eintrag: Punkte in Trail-Richtung, Grad
/// und Sterne wie angezeigt, Höhenmeter aus seinem Profil (0 ohne Höhen).
PoolTrail poolTrailOf(Trail t, {bool mandatory = false}) => PoolTrail(
      id: t.id,
      name: t.displayName,
      points: t.directedPoints,
      lengthM: t.lengthM,
      grade: t.grade,
      rating: t.rating,
      gainM: t.elevation?.gainM ?? 0,
      lossM: t.elevation?.lossM ?? 0,
      mandatory: mandatory,
    );

/// Was vom sichtbaren Netz für eine Runde ab [start] in Frage kommt:
/// [inReach] mit beiden Enden in [kLoopReachM], davon getrennt die mit
/// warnender Meldung ([warned], Entscheidung 8.8: raus aus dem Pool,
/// einzeln hineinholbar), die Uphill-Trails und Verbinder ([connectors],
/// #185: keine Abfahrt, sondern Weg bergauf — sie liegen auf dem Graphen,
/// nicht im Pool), und wie viele zu weit liegen. Wartende Trails
/// (Ausgangskorb) zählen nicht — sie haben noch keine Kennung.
({List<Trail> inReach, List<Trail> warned, List<Trail> connectors, int tooFar}) loopPoolOf(
    Iterable<Trail> trails, LatLng start, {double reachM = kLoopReachM}) {
  final inReach = <Trail>[], warned = <Trail>[], connectors = <Trail>[];
  var tooFar = 0;
  for (final t in trails) {
    if (t.pending || t.points.length < 2) continue;
    final a = start.distanceToM(t.start), b = start.distanceToM(t.end);
    if (a > reachM || b > reachM) {
      tooFar++;
      continue;
    }
    if (trailRoleOf(t) != TrailRole.downhill) {
      connectors.add(t);
      continue;
    }
    (t.status.warns ? warned : inReach).add(t);
  }
  return (inReach: inReach, warned: warned, connectors: connectors, tooFar: tooFar);
}

/// Die Trails, die ein gezeichnetes Gebiet [ring] fasst (#178): die
/// Mehrheit ihrer Punkte liegt darin (gerade-ungerade, eben genug für
/// ein Gebiet von ein paar Kilometern). Ein Trail, der nur angeschnitten
/// ist, zählt nicht — sonst wählte ein Strich am Rand Trails, die
/// niemand gemeint hat.
Set<String> trailsInRing(Iterable<Trail> trails, List<LatLng> ring) {
  if (ring.length < 3) return const {};
  bool inside(LatLng p) {
    var c = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i], b = ring[j];
      if ((a.latitude > p.latitude) != (b.latitude > p.latitude) &&
          p.longitude <
              (b.longitude - a.longitude) * (p.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude) {
        c = !c;
      }
    }
    return c;
  }

  return {
    for (final t in trails)
      if (t.points.isNotEmpty && t.points.where(inside).length * 2 > t.points.length) t.id,
  };
}

/// Die Rolle eines Trails im Graphen (#185) — nach den ANGEZEIGTEN
/// Merkmalen (`Trail.topTraits`), dieselbe Regel wie die Farbe: Steht
/// Uphill darunter, ist er ein Uphill-Trail (das schlägt Verbindung, wie
/// es die Stufe schlägt); sonst Verbindung; sonst eine Abfahrt.
TrailRole trailRoleOf(Trail t) {
  final top = t.topTraits;
  if (top.contains(TrailTrait.uphill)) return TrailRole.uphill;
  if (top.contains(TrailTrait.connection)) return TrailRole.connector;
  return TrailRole.downhill;
}

/// Die Trails des Netzes für [applyTrails]: alle mit Linie, außer den
/// wartenden (noch ohne Kennung) und denen mit warnender Meldung, die
/// als Verbinder dienen würden — ein gesperrter Uphill ist kein Weg.
/// Gesperrte ABFAHRTEN bleiben drin: Ihre Richtung gilt weiter.
List<GraphTrail> graphTrailsOf(Iterable<Trail> trails) => [
      for (final t in trails)
        if (!t.pending && t.points.length >= 2 && !(trailRoleOf(t) != TrailRole.downhill && t.status.warns))
          GraphTrail(
            id: t.id,
            name: t.displayName,
            points: t.directedPoints,
            role: trailRoleOf(t),
            twoWay: t.twoWay,
            gainM: t.elevation?.gainM,
            lossM: t.elevation?.lossM,
          ),
    ];

extension on LatLng {
  double distanceToM(LatLng o) => haversineM(latitude, longitude, o.latitude, o.longitude);
}

/// Die Regler der letzten Planung (Konzept-Routing 2.3: „die Vorgaben
/// merkt sich das Gerät mit der letzten Planung"), kodiert als EINE
/// Zeichenkette für `Settings.loopPlannerPrefs`.
class LoopPrefs {
  const LoopPrefs({
    required this.hours,
    required this.climbM,
    required this.hikingKm,
    required this.returnToStart,
    this.radiusKm = kLoopReachM / 1000,
    this.fillOnline = true,
    this.route = const RoutePrefs(),
  });

  final double hours;
  final double climbM;
  final double hikingKm;
  final bool returnToStart;

  /// Der Radius der Trail-Liste um den Start (seit 0.74.0).
  final double radiusKm;

  /// Fehlende Wege mit Empfang vom Host ergänzen (#187, seit 0.78.0) —
  /// gilt für die Runde UND den Weg zum Trail. Aus heißt: gerechnet wird,
  /// was die Bereiche tragen, wie ohne Empfang — so lässt sich die
  /// Offline-Lage zu Hause prüfen.
  final bool fillOnline;

  /// Die Vorlieben fürs Routing (#188) — Straßen, Wanderwege bergauf,
  /// steile Rampen, je meiden oder egal. Gelten wie [fillOnline] für die
  /// Runde UND den Weg zum Trail.
  final RoutePrefs route;

  static const minHours = 1.0, maxHours = 6.0, hoursStep = 0.5;
  static const minClimb = 200.0, maxClimb = 2500.0, climbStep = 100.0;
  static const minHikingKm = 0.0, maxHikingKm = 10.0, hikingStep = 0.5;
  static const minRadiusKm = 2.0, maxRadiusKm = 30.0, radiusStep = 1.0;

  /// Die Vorgaben je Profil (die Höhenmeter hängen am Profil).
  static LoopPrefs defaults(RiderProfile p) =>
      LoopPrefs(hours: kBudgetHours, climbM: p.budgetClimbM, hikingKm: kBudgetHikingKm, returnToStart: true);

  /// Liest, was gespeichert ist; Unlesbares oder Fehlendes ergibt die
  /// Vorgabe, jeder Wert einzeln auf seine Spanne geklemmt.
  static LoopPrefs parse(String? raw, RiderProfile p) {
    final d = defaults(p);
    if (raw == null) return d;
    final fields = <String, String>{};
    for (final part in raw.split(';')) {
      final i = part.indexOf('=');
      if (i > 0) fields[part.substring(0, i)] = part.substring(i + 1);
    }
    double clamp(String key, double fallback, double lo, double hi) =>
        (double.tryParse(fields[key] ?? '') ?? fallback).clamp(lo, hi).toDouble();
    return LoopPrefs(
      hours: clamp('h', d.hours, minHours, maxHours),
      climbM: clamp('c', d.climbM, minClimb, maxClimb),
      hikingKm: clamp('w', d.hikingKm, minHikingKm, maxHikingKm),
      returnToStart: fields['r'] != '0',
      radiusKm: clamp('k', d.radiusKm, minRadiusKm, maxRadiusKm),
      fillOnline: fields['o'] != '0',
      route: RoutePrefs(
        avoidRoads: fields['sr'] != '0',
        avoidHiking: fields['sw'] != '0',
        avoidSteep: fields['ss'] != '0',
      ),
    );
  }

  String encode() => 'h=$hours;c=$climbM;w=$hikingKm;r=${returnToStart ? 1 : 0};k=$radiusKm;o=${fillOnline ? 1 : 0}'
      ';sr=${route.avoidRoads ? 1 : 0};sw=${route.avoidHiking ? 1 : 0};ss=${route.avoidSteep ? 1 : 0}';

  LoopBudget get budget => LoopBudget(timeS: hours * 3600, climbM: climbM, hikingM: hikingKm * 1000);

  LoopPrefs copyWith(
          {double? hours,
          double? climbM,
          double? hikingKm,
          bool? returnToStart,
          double? radiusKm,
          bool? fillOnline,
          RoutePrefs? route}) =>
      LoopPrefs(
        hours: hours ?? this.hours,
        climbM: climbM ?? this.climbM,
        hikingKm: hikingKm ?? this.hikingKm,
        returnToStart: returnToStart ?? this.returnToStart,
        radiusKm: radiusKm ?? this.radiusKm,
        fillOnline: fillOnline ?? this.fillOnline,
        route: route ?? this.route,
      );
}

/// „Runde: Hexentanz, Steinbruch" — höchstens drei Namen, dann „und n
/// weitere"; ein Trail, der zweimal drin ist, steht einmal.
String loopName(LoopPlan plan) {
  final names = <String>[];
  for (final s in plan.stops) {
    if (!names.contains(s.trail.name)) names.add(s.trail.name);
  }
  if (names.isEmpty) return 'Runde';
  final shown = names.take(3).join(', ');
  final rest = names.length - 3;
  return rest > 0 ? 'Runde: $shown und $rest weitere' : 'Runde: $shown';
}

/// Die Runde als GPX-Spur (#150): nur die Linie, keine Höhen — wie bei
/// „Zum Trailkopf" kennt die Engine Höhen je Kante, nicht je Punkt.
GpxTrack loopToGpx(LoopPlan plan) => GpxTrack(
      name: loopName(plan),
      points: [for (final p in plan.points) TrackPoint(p.latitude, p.longitude)],
    );
