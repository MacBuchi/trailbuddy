// Die Nachrichten an die Uhr (docs/konzept-garmin.md, Abschnitt 2):
// die Route, in Stücken, und die Bestwerte der Erkennung. Pur — kein
// Kanal, kein Riverpod; die Brücke (`garmin_bridge.dart`) schickt, was
// hier entsteht.
//
// Die Form ist die von `garmin/source/NavRoute.mc` und
// `tool/garmin_route.py`: `pts` = [lat0, lon0, dLat1, dLon1, …] in 1e-5°,
// der erste Punkt absolut, jeder weitere gegen den Vorgänger; `ele` je
// Punkt in Metern; `sec` = [[vonPunkt, bisPunkt, sGrad, Name], …]. Ein
// Test vergleicht mit den Zahlen des Werkzeugs.
import 'dart:collection';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../rides/sensor_fusion.dart' show JumpEvent, StoppieEvent, WheelieEvent;
import '../rides/trail_values.dart' show AirtimeLog;
import '../routing/nav_sections.dart';
import '../trails/gpx.dart' show TrackPoint;
import '../trails/trail_elevation.dart' show ElevationProfile;
import '../trails/trail_geometry.dart' show simplify;
import '../../core/geo.dart' as geo;

/// Fassung des Protokolls (`v`); die Uhr lehnt eine andere ab.
const kWatchProtocol = 1;

/// Mehr Punkte trägt die fēnix 5 nicht (Messung 8.1 im Simulator: 2000
/// Punkte 76 KB von 124 KB, ab 3000 „Out of Memory" schon beim Laden).
const kWatchMaxPoints = 2000;

/// Startwert der Vereinfachung (Konzept 2); passt es nicht, verdoppelt.
const kWatchSimplifyM = 5.0;

/// So viele Zahlen (pts und ele zusammen) trägt ein Stück — rund 4 KB
/// serialisiert (5 Byte je Ganzzahl). Startwert bis zur Messung 8.2.
const kWatchPartInts = 800;

/// Namen kürzt die App: Die Uhr zeigt ohnehin nur eine Zeile.
const kWatchNameChars = 24;

/// Art der Nachricht (`t`): ein Stück Route, die Bestwerte, die Antwort
/// der Uhr.
const kWatchRoutePart = 'r';
const kWatchBests = 'b';
const kWatchStored = 'ok';

/// Die Route für die Uhr, noch nicht in Stücken.
class WatchRoute {
  const WatchRoute({required this.id, required this.pts, required this.ele, required this.sec});

  final String id;
  final List<int> pts;
  final List<int>? ele;
  final List<List<Object>> sec;

  int get pointCount => pts.length ~/ 2;

  /// In der Form von `route.json` (für den Vergleich mit dem Werkzeug).
  Map<String, Object> toJson() => {
        'v': kWatchProtocol,
        'id': id,
        'rel': false,
        'pts': pts,
        'ele': ?ele,
        if (sec.isNotEmpty) 'sec': sec,
      };

  /// Die Stücke, wie sie über die Brücke gehen: jedes mit `t`, `id`,
  /// Laufnummer `p` und Anzahl `n`; das erste trägt dazu `v` und `sec`.
  /// Die Uhr hängt `pts` und `ele` in der Reihenfolge der Laufnummer
  /// aneinander und hat dann wieder [toJson].
  List<Map<String, Object>> parts({int maxInts = kWatchPartInts}) {
    final perPoint = ele == null ? 2 : 3;
    final step = math.max(1, maxInts ~/ perPoint);
    final n = (pointCount + step - 1) ~/ step;
    return [
      for (var p = 0; p < n; p++)
        {
          't': kWatchRoutePart,
          'id': id,
          'p': p,
          'n': n,
          if (p == 0) 'v': kWatchProtocol,
          if (p == 0 && sec.isNotEmpty) 'sec': sec,
          'pts': pts.sublist(2 * p * step, 2 * math.min(pointCount, (p + 1) * step)),
          if (ele != null) 'ele': ele!.sublist(p * step, math.min(pointCount, (p + 1) * step)),
        }
    ];
  }
}

/// Die navigierte Linie für die Uhr: vereinfacht (Douglas-Peucker, erst
/// [kWatchSimplifyM], dann doppelt, bis höchstens [maxPoints] bleiben),
/// Höhen aus dem Profil des Geländemodells (falls da), die Trails der
/// Route als Abschnitte. Der Ziel-Trail hinter dem Ende („Zum
/// Trailkopf") fährt nicht mit — er liegt nicht auf der Linie.
WatchRoute? watchRouteOf(List<LatLng> points, NavSections sections,
    {ElevationProfile? heights, int maxPoints = kWatchMaxPoints}) {
  if (points.length < 2) return null;
  final track = [for (final p in points) TrackPoint(p.latitude, p.longitude)];
  // Lage ab Start je Originalpunkt — die Abschnitte stehen in Metern.
  final cum = <double>[0];
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1], b = points[i];
    cum.add(cum.last + geo.distanceMeters(a.latitude, a.longitude, b.latitude, b.longitude));
  }
  if (!(cum.last > 0)) return null;
  var tol = kWatchSimplifyM;
  var kept = simplify(track, toleranceM: tol);
  while (kept.length > maxPoints) {
    tol *= 2;
    kept = simplify(track, toleranceM: tol);
  }
  final index = LinkedHashMap<TrackPoint, int>.identity();
  for (var i = 0; i < track.length; i++) {
    index[track[i]] = i;
  }
  final along = [for (final p in kept) cum[index[p]!]];

  final pts = <int>[];
  var lat = 0, lon = 0;
  for (var i = 0; i < kept.length; i++) {
    final a = (kept[i].lat * 1e5).round(), b = (kept[i].lon * 1e5).round();
    if (i == 0) {
      pts.addAll([a, b]);
    } else {
      pts.addAll([a - lat, b - lon]);
    }
    lat = a;
    lon = b;
  }

  List<int>? ele;
  if (heights != null) {
    final scale = heights.distM.last / cum.last;
    ele = [for (final m in along) _eleAt(heights, m * scale).round()];
  }

  final sec = <List<Object>>[];
  for (final t in sections.ridden) {
    final from = _nearest(along, t.startM), to = _nearest(along, t.endM);
    if (to <= from) continue;
    sec.add([from, to, watchGrade(t), _short(t.name)]);
  }
  return WatchRoute(id: watchRouteId(pts), pts: pts, ele: ele, sec: sec);
}

/// Der S-Grad, wie die Uhr ihn färbt: 0–3 (ab S3 schwarz wie in der App),
/// -1 ohne Grad. Ein Uphill zählt ohne Grad — die Uhr hat kein Magenta.
int watchGrade(NavTrailSection t) {
  final g = t.grade;
  if (t.uphill || g == null) return -1;
  return g.clamp(0, 3);
}

/// Kennung der Route aus ihren Zahlen (FNV-1a, 32 Bit, hex): Dieselbe
/// Route noch einmal hat dieselbe, die Uhr behält sie dann. Mit `&` statt
/// Überlauf, damit das Web dieselbe Zahl rechnet.
String watchRouteId(List<int> pts) {
  var h = 0x811c9dc5;
  for (final v in pts) {
    for (final byte in [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]) {
      h = ((h ^ byte) * 0x01000193) & 0xffffffff;
    }
  }
  return h.toRadixString(16).padLeft(8, '0');
}

/// Die Bestwerte der Erkennung (#36) für die Seite „Fahrt" und die
/// Zusammenfassung auf der Uhr (Idee des Betreibers, Konzept 9.2): nur
/// Zahlen, keine Spur, nichts, was die Uhr misst. Null ohne Ereignis.
/// Mit „War keiner" Beantwortetes zählt nicht ([AirtimeLog.kept]).
Map<String, Object>? watchBestsOf(AirtimeLog log) {
  var jumps = 0, wheelies = 0, stoppies = 0;
  var airMs = 0, wheelieM = 0.0, wheelieDeg = 0.0;
  for (final e in log.kept) {
    switch (e) {
      case JumpEvent():
        if (!e.plausible) continue;
        jumps++;
        airMs = math.max(airMs, e.duration.inMilliseconds);
      case WheelieEvent():
        wheelies++;
        wheelieM = math.max(wheelieM, e.lengthM);
        wheelieDeg = math.max(wheelieDeg, e.maxTiltDeg);
      case StoppieEvent():
        stoppies++;
    }
  }
  if (jumps + wheelies + stoppies == 0) return null;
  return {
    't': kWatchBests,
    'jn': jumps,
    'ja': airMs,
    'wn': wheelies,
    'wl': wheelieM.round(),
    'wa': wheelieDeg.round(),
    'sn': stoppies,
  };
}

/// Hat die Uhr [routeId] gespeichert? Ihre einzige Antwort (Konzept 2:
/// „sonst nichts").
String? watchStoredId(Object? message) {
  if (message is! Map) return null;
  if (message['t'] != kWatchStored) return null;
  final id = message['id'];
  return id is String ? id : null;
}

int _nearest(List<double> along, double m) {
  var lo = 0, hi = along.length - 1;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (along[mid] < m) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  if (lo > 0 && (m - along[lo - 1]).abs() < (along[lo] - m).abs()) return lo - 1;
  return lo;
}

double _eleAt(ElevationProfile p, double m) {
  final d = p.distM, e = p.eleM;
  if (m <= d.first) return e.first;
  if (m >= d.last) return e.last;
  var lo = 0, hi = d.length - 1;
  while (hi - lo > 1) {
    final mid = (lo + hi) >> 1;
    if (d[mid] <= m) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final span = d[hi] - d[lo];
  return span <= 0 ? e[lo] : e[lo] + (e[hi] - e[lo]) * (m - d[lo]) / span;
}

String _short(String name) =>
    name.length <= kWatchNameChars ? name : '${name.substring(0, kWatchNameChars - 1)}…';
