// Die Suche auf dem Wegegraphen (docs/konzept-routing.md 3.1): ein
// begrenzter Dijkstra (abgebrochen, sobald die Kosten das Budget
// übersteigen) von einem Knoten zu allen, als A* mit Luftlinien-Heuristik
// für die Einzelanfrage „zum Trailkopf", und die Zusammenfassung eines
// Pfads — Länge, Anstieg, Abstieg, Zeit, Wanderweg-Meter, Klassenmix,
// Linie. Port von `dijkstra`, `astar` und `path_summary` in
// `tool/route_measure.py`.
//
// Kosten einer Kante = Zeit × Aufschlag plus Steilaufschlag (`edgeCostS`,
// #194), in Kantenrichtung mit Anstieg/Abstieg vertauscht; eine Einbahn (nur Straßenklassen) nur
// vorwärts. Rein, ohne Widgets.
import 'package:latlong2/latlong.dart';

import 'road_graph.dart';
import 'route_profile.dart';

/// Kosten, Anstieg und Vorgänger je erreichtem Knoten.
class SearchResult {
  SearchResult(this.src);

  final int src;
  final dist = <int, double>{};
  final climb = <int, double>{};
  final prev = <int, ({int node, int edge})>{};

  bool reached(int n) => dist.containsKey(n);

  /// Die Kanten vom Start zu [n], oder null, wenn [n] nicht erreicht ist.
  List<int>? pathTo(int n) {
    if (!reached(n)) return null;
    final out = <int>[];
    var cur = n;
    while (cur != src) {
      final p = prev[cur]!;
      out.add(p.edge);
      cur = p.node;
    }
    return out.reversed.toList();
  }
}

/// Kosten, Anstieg (in Kantenrichtung von [from]) einer Kante. Auf einem
/// Uphill-Trail oder Verbinder (#185) gilt statt des Aufschlags der Klasse
/// [kTrailConnectorFactor] — die Zeit bleibt die der Klasse — und kein
/// Steilaufschlag (#194): Wer ihn eingetragen hat, will genau da hinauf.
/// [steep] sind die Höhenmeter über [kSteepGrade], die dabei zählen;
/// gekostet wird das Gewicht ([GraphEdge.steepWUp]). Bergab auf einem
/// Trail kostet keine verschenkte Höhe (#188) — dafür ist er da.
({double cost, double gain, double loss, double steep}) edgeCostFrom(RoadGraph g, int ei, int from, RiderParams p) {
  final e = g.edges[ei];
  final forward = e.a == from;
  final gain = forward ? e.gain : e.loss;
  final loss = forward ? e.loss : e.gain;
  if (e.connector) {
    final cost = edgeTimeS(p, e.cls, lengthM: e.length, gainM: gain, lossM: loss) * kTrailConnectorFactor;
    return (cost: cost, gain: gain, loss: loss, steep: 0.0);
  }
  final steep = forward ? e.steepUp : e.steepDown;
  final cost = edgeCostS(p, e.cls,
      lengthM: e.length,
      gainM: gain,
      lossM: loss,
      steepW: forward ? e.steepWUp : e.steepWDown,
      descent: e.trail == null,
      carry: e.carry,
      way: e.way,
      uphill: e.uphill);
  return (cost: cost, gain: gain, loss: loss, steep: steep);
}

/// Darf die Kante [e] von Knoten [from] aus befahren werden? Einbahn
/// (nur Straßen) und Trail-Richtung (#174) sperren je eine Richtung.
bool edgeOpenFrom(GraphEdge e, int from) {
  final forward = e.a == from;
  if (e.oneway && !forward) return false;
  return forward ? !e.blockForward : !e.blockBackward;
}

/// Begrenzter Dijkstra (mit [heuristic] ein A*): alle Knoten, die mit
/// Kosten ≤ [limit] erreichbar sind; mit [target] endet die Suche dort.
/// [allow] lässt Kanten aus — der Planer sucht damit die Verbindung OHNE
/// Wanderweg, wenn das Budget „höchstens Wanderweg" sonst nicht hält.
SearchResult dijkstra(RoadGraph g, int src, RiderParams p,
    {double limit = double.infinity,
    int? target,
    double Function(int node)? heuristic,
    bool Function(GraphEdge edge)? allow}) {
  final r = SearchResult(src);
  r.dist[src] = 0;
  r.climb[src] = 0;
  final heap = _Heap();
  heap.push(0, src);
  final seen = <int>{};
  while (heap.isNotEmpty) {
    final n = heap.pop();
    if (!seen.add(n)) continue;
    if (n == target) break;
    for (final ei in g.adj[n]) {
      final e = g.edges[ei];
      final forward = e.a == n;
      if (!edgeOpenFrom(e, n)) continue;
      if (allow != null && !allow(e)) continue;
      final m = forward ? e.b : e.a;
      final c = edgeCostFrom(g, ei, n, p);
      final nd = r.dist[n]! + c.cost;
      if (nd > limit) continue;
      if (nd < (r.dist[m] ?? double.infinity)) {
        r.dist[m] = nd;
        r.climb[m] = r.climb[n]! + c.gain;
        r.prev[m] = (node: n, edge: ei);
        heap.push(nd + (heuristic?.call(m) ?? 0), m);
      }
    }
  }
  return r;
}

/// Der günstigste Weg von [src] nach [dst] (A* mit Luftlinie durch die
/// Abfahrtsgeschwindigkeit — nie überschätzt), oder null.
({double costS, double climbM, List<int> edges})? shortestPath(RoadGraph g, int src, int dst, RiderParams p) {
  final t = g.nodes[dst];
  final vMax = p.vDownKmh / 3.6;
  final r = dijkstra(g, src, p, target: dst, heuristic: (n) => g.nodes[n].distanceTo(t) / vMax);
  final path = r.pathTo(dst);
  if (path == null) return null;
  return (costS: r.dist[dst]!, climbM: r.climb[dst]!, edges: path);
}

/// Was ein Pfad ist, in Zahlen und als Linie.
class PathSummary {
  const PathSummary({
    required this.lengthM,
    required this.gainM,
    required this.lossM,
    required this.timeS,
    required this.hikingM,
    required this.mix,
    required this.points,
    required this.heightsComplete,
    this.trailUpM = 0,
    this.steepM = 0,
  });

  final double lengthM;
  final double gainM;
  final double lossM;

  /// Geschätzte Zeit ohne Aufschläge (die Aufschläge sind Kosten, keine
  /// Minuten).
  final double timeS;

  /// Meter auf Wanderweg, Fußweg und Stufen — gegen „höchstens Wanderweg".
  final double hikingM;
  final Map<WayClass, double> mix;
  final List<LatLng> points;

  /// Falsch, sobald eine Kante ohne Höhen dabei war: Dann ist der Anstieg
  /// eine Untergrenze, und das Blatt sagt es.
  final bool heightsComplete;

  /// Meter auf Uphill-Trails und Verbindern (#185) — im Klassenmix stehen
  /// sie unter ihrer Kartenklasse, das Blatt nennt sie extra.
  final double trailUpM;

  /// Höhenmeter über [kSteepGrade] abseits der Uphill-Trails (#194) —
  /// was der Steilaufschlag nicht vermeiden konnte.
  final double steepM;
}

/// Ab so vielen Höhenmetern über [kSteepGrade] sagt das Blatt, dass die
/// Route steile Stücke hat (#194) — darunter ist es Rauschen im Modell.
const kSteepNoteMinM = 5.0;

/// Der Satz dazu, oder null. Keine Zahl: Gezählt ist nur, was ÜBER der
/// Grenze steigt, und „12 hm steil" läse sich wie die Länge der Rampe.
String? steepNote(double steepM) => steepM < kSteepNoteMinM
    ? null
    : 'Mit steilen Stücken über ${(kSteepGrade * 100).round()} % — wo es flacher ging, ist der flachere Weg gewählt.';

/// Fasst die Kanten [path] ab Knoten [src] zusammen.
PathSummary summarizePath(RoadGraph g, List<int> path, int src, RiderParams p) {
  var n = src;
  var length = 0.0, gain = 0.0, loss = 0.0, time = 0.0, hiking = 0.0, trailUp = 0.0, steep = 0.0;
  var complete = true;
  final mix = <WayClass, double>{};
  final points = <LatLng>[];
  for (final ei in path) {
    final e = g.edges[ei];
    final forward = e.a == n;
    final pts = forward ? e.points : e.points.reversed.toList();
    points.addAll(points.isEmpty ? pts : pts.skip(1));
    final c = edgeCostFrom(g, ei, n, p);
    length += e.length;
    gain += c.gain;
    loss += c.loss;
    steep += c.steep;
    time += edgeTimeS(p, e.cls, lengthM: e.length, gainM: c.gain, lossM: c.loss);
    mix[e.cls] = (mix[e.cls] ?? 0) + e.length;
    if (e.hiking) hiking += e.length;
    if (e.connector) trailUp += e.length;
    if (!e.hasHeights) complete = false;
    n = forward ? e.b : e.a;
  }
  return PathSummary(
    lengthM: length,
    gainM: gain,
    lossM: loss,
    timeS: time,
    hikingM: hiking,
    mix: mix,
    points: points,
    heightsComplete: complete,
    trailUpM: trailUp,
    steepM: steep,
  );
}

/// Ein kleiner binärer Heap über (Priorität, Knoten) — `dart:collection`
/// hat keinen, und eine sortierte Liste wäre bei 20 000 Kanten je Lauf
/// quadratisch.
class _Heap {
  final _items = <(double, int)>[];

  bool get isNotEmpty => _items.isNotEmpty;

  void push(double priority, int node) {
    _items.add((priority, node));
    var i = _items.length - 1;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_items[parent].$1 <= _items[i].$1) break;
      final t = _items[parent];
      _items[parent] = _items[i];
      _items[i] = t;
      i = parent;
    }
  }

  int pop() {
    final top = _items.first.$2;
    final last = _items.removeLast();
    if (_items.isNotEmpty) {
      _items[0] = last;
      var i = 0;
      while (true) {
        final l = 2 * i + 1, r = l + 1;
        var m = i;
        if (l < _items.length && _items[l].$1 < _items[m].$1) m = l;
        if (r < _items.length && _items[r].$1 < _items[m].$1) m = r;
        if (m == i) break;
        final t = _items[m];
        _items[m] = _items[i];
        _items[i] = t;
        i = m;
      }
    }
    return top;
  }
}
