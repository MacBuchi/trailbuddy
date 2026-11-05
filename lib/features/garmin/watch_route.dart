// Die Nachrichten an die Uhr (docs/konzept-garmin.md, Abschnitt 2):
// die Route, in Stücken, und die Bestwerte der Erkennung. Pur — kein
// Kanal, kein Riverpod; die Brücke (`garmin_bridge.dart`) schickt, was
// hier entsteht.
//
// [WatchRoute] hält die Linie lesbar (`pts` = [lat0, lon0, dLat1, dLon1,
// …] in 1e-5°, `ele` je Punkt in Metern, `br` = [Punkt, dLat, dLon, …]).
// Auf den Draht geht Protokoll 2 (#449, 2026-11-05) — GEPACKT, halb so
// viele Zahlen wie vorher: je Punkt eine Zahl `(dLat << 16) | dLon`
// (16 Bit mit Vorzeichen, gegen den Vorgänger, der erste gegen `o`), die
// Höhen als Differenzen zu zweit in einer Zahl (die erste gegen `e0`), je
// Stummel `[Punkt, gepackt(dLat, dLon)]`. Jede Zahl kostet auf dem Draht
// und im Speicher der Uhr ~5 Byte, gleich wie groß — die fēnix 5 hat für
// alles 128 KB. Die Form ist die von `garmin/source/NavRoute.mc` und
// `tool/garmin_route.py`; ein Test vergleicht mit den Zahlen des Werkzeugs.
import 'dart:collection';
import 'dart:convert' show utf8;
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../rides/sensor_fusion.dart' show JumpEvent, StoppieEvent, WheelieEvent;
import '../rides/trail_values.dart' show AirtimeLog;
import '../routing/nav_sections.dart';
import '../trails/gpx.dart' show TrackPoint;
import '../trails/trail_elevation.dart' show ElevationProfile;
import '../trails/trail_geometry.dart' show simplify;
import '../../core/geo.dart' as geo;
import '../offline_areas/height_tiles.dart' show kClimbHysteresisM;
import 'watch_branches.dart';

/// Fassung des Protokolls (`v`); die Uhr lehnt eine andere ab. 2 seit
/// dem Packen (#449, 2026-11-05).
const kWatchProtocol = 2;

/// So weit darf ein Schritt in 1e-5° gehen, damit er in 16 Bit passt —
/// in der Länge bei 47° gut 240 m. Längere Abschnitte teilt [watchRouteOf].
const kWatchMaxDelta = 32767;

/// Mehr Punkte trägt die fēnix 5 nicht (Messung 8.1 im Simulator: 2000
/// Punkte 76 KB von 124 KB, ab 3000 „Out of Memory" schon beim Laden).
const kWatchMaxPoints = 2000;

/// Startwert der Vereinfachung (Konzept 2); passt es nicht, verdoppelt.
const kWatchSimplifyM = 5.0;

/// So viele Zahlen trägt ein Stück — rund 4 KB serialisiert (5 Byte je
/// Ganzzahl), mit Kopf und Trails im ersten. Gepackt sind das gut 500
/// Punkte samt Höhen. Die Uhr hält beim Empfang ein Stück und braucht zum
/// Speichern das Zwei- bis Dreifache frei; je Wert in ihrem Speicher
/// gelten 8 KB.
const kWatchPartInts = 800;

/// Namen kürzt die App: Die Uhr zeigt ohnehin nur eine Zeile.
const kWatchNameChars = 24;

/// Art der Nachricht (`t`): ein Stück Route, die Bestwerte, die Frage
/// „welche Route hast du?" an die Uhr; zurück „gespeichert" und „hallo".
const kWatchRoutePart = 'r';
const kWatchBests = 'b';
const kWatchQuery = 'q';
const kWatchStored = 'ok';
const kWatchHello = 'hi';

/// Die Uhr konnte ein Stück nicht nehmen (`{t: "x", id, c}`): `c` ist
/// [kWatchErrMemory], [kWatchErrStorage], [kWatchErrCrash] oder
/// [kWatchErrBad].
const kWatchError = 'x';

/// Zu wenig Arbeitsspeicher zum Ablegen.
const kWatchErrMemory = 'mem';

/// Der Speicher der Uhr nahm das Stück nicht (voll oder zu groß).
const kWatchErrStorage = 'store';

/// Diese Route ließ die Uhr-App schon zweimal abstürzen; sie nimmt sie
/// nicht mehr (dieselbe Kennung steht in `hi` als `bad`).
const kWatchErrCrash = 'crash';

/// Das Stück passte nicht zur Form.
const kWatchErrBad = 'bad';

/// Packt zwei Werte mit 16 Bit Vorzeichen in eine 32-Bit-Zahl, wie
/// `PhoneRoute.unpackHi/unpackLo` sie auf der Uhr wieder auspacken. Auch
/// im Web (32-Bit-Schieben ohne Vorzeichen) eine Zahl mit Vorzeichen —
/// eine Zahl über 32 Bit käme in Kotlin als `Long` und auf der Uhr als
/// `Long` an.
int watchPack(int hi, int lo) => ((hi & 0xffff) << 16 | (lo & 0xffff)).toSigned(32);

/// Gegenstück zu [watchPack] (Tests).
(int, int) watchUnpack(int v) => (((v >> 16) & 0xffff).toSigned(16), (v & 0xffff).toSigned(16));

/// Die Frage an die Uhr, nach dem Wiederverbinden: Läuft ihre App, meldet
/// sie sich mit `hi` (läuft sie nicht, verfällt die Nachricht still).
const Map<String, Object> watchQuery = {'t': kWatchQuery};

/// Die Route für die Uhr, noch nicht in Stücken.
class WatchRoute {
  const WatchRoute({required this.id, required this.pts, required this.ele, required this.sec, this.br = const []});

  final String id;
  final List<int> pts;
  final List<int>? ele;
  final List<List<Object>> sec;

  /// Die Stummel als `[Punkt, dLat, dLon, …]`, nach Punkt sortiert.
  final List<int> br;

  int get pointCount => pts.length ~/ 2;

  /// Gepackt: je Punkt `(dLat << 16) | dLon` gegen den Vorgänger, der
  /// erste gegen den Ursprung `o` (also 0).
  List<int> packedPts([int from = 0, int? to]) => [
        for (var i = from; i < (to ?? pointCount); i++) i == 0 ? 0 : watchPack(pts[2 * i], pts[2 * i + 1]),
      ];

  /// Die Höhen der Punkte [from] bis [to] als Differenzen gegen den
  /// Vorgänger (der erste Punkt gegen `e0`, also 0), zu zweit in einer Zahl;
  /// eine ungerade Zahl von Punkten füllt mit 0 auf.
  List<int>? packedEle([int from = 0, int? to]) {
    final e = ele;
    if (e == null) return null;
    final end = to ?? pointCount;
    int d(int i) => i == 0 ? 0 : (e[i] - e[i - 1]).clamp(-kWatchMaxDelta, kWatchMaxDelta);
    return [for (var i = from; i < end; i += 2) watchPack(d(i), i + 1 < end ? d(i + 1) : 0)];
  }

  /// Die Stummel `br[from…to)` (Stellen in [br], je drei) als `[Punkt,
  /// gepackt(dLat, dLon)]`.
  List<int> packedBr([int from = 0, int? to]) => [
        for (var k = from; k + 2 < (to ?? br.length); k += 3) ...[
          br[k],
          watchPack(br[k + 1].clamp(-kWatchMaxDelta, kWatchMaxDelta), br[k + 2].clamp(-kWatchMaxDelta, kWatchMaxDelta)),
        ],
      ];

  /// Der Kopf, den das erste Stück trägt.
  Map<String, Object> _head() => {
        'v': kWatchProtocol,
        'np': pointCount,
        'o': [pts[0], pts[1]],
        if (ele case final e?) 'e0': e[0],
        if (sec.isNotEmpty) 'sec': sec,
      };

  /// So viele Zahlen kostet der Kopf auf dem Draht (Namen nach Bytes, eine
  /// Zahl je 5): Er zählt in die Grenze des ersten Stücks.
  int _headInts() {
    var n = 8;
    for (final s in sec) {
      n += 4 + (utf8.encode('${s[3]}').length + 4) ~/ 5;
    }
    return n;
  }

  /// In der Form von `route.json`, ein einziges Stück (für den Vergleich
  /// mit dem Werkzeug).
  Map<String, Object> toJson() => {
        ..._head(),
        'id': id,
        'rel': false,
        'pts': packedPts(),
        'ele': ?packedEle(),
        if (br.isNotEmpty) 'br': packedBr(),
      };

  /// Die Stücke, wie sie über die Brücke gehen: jedes mit `t`, `id`,
  /// Laufnummer `p` und Anzahl `n`; das erste trägt dazu den Kopf (`v`,
  /// `np`, `o`, `e0`, `sec`). Die Stummel gehen mit dem Stück ihres Punkts
  /// (die Nummer bleibt die der ganzen Linie). Jedes Stück hält [maxInts]
  /// Zahlen samt Kopf ein — außer, ein einzelner Punkt passt nicht (dann
  /// trägt das Stück genau ihn). Die Uhr dekodiert Stück für Stück.
  List<Map<String, Object>> parts({int maxInts = kWatchPartInts}) {
    final withEle = ele != null;
    // Stummel je Punkt, in gepackten Zahlen.
    final brInts = List<int>.filled(pointCount, 0);
    for (var k = 0; k + 2 < br.length; k += 3) {
      brInts[br[k]] += 2;
    }
    final head = _headInts();
    int cost(int points, int brUsed, bool first) =>
        points + (withEle ? (points + 1) ~/ 2 : 0) + brUsed + (first ? head : 0);
    // Grenzen der Stücke: so viele Punkte, wie samt Stummeln passen.
    final bounds = <int>[0];
    var points = 0, brUsed = 0;
    for (var i = 0; i < pointCount; i++) {
      if (points > 0 && cost(points + 1, brUsed + brInts[i], bounds.length == 1) > maxInts) {
        bounds.add(i);
        points = 0;
        brUsed = 0;
      }
      points++;
      brUsed += brInts[i];
    }
    bounds.add(pointCount);
    final n = bounds.length - 1;
    // Je Stück die Stummel seiner Punkte (Stellen in [br]).
    final brAt = <int>[0];
    for (var p = 0; p < n; p++) {
      var k = brAt.last;
      while (k + 2 < br.length && br[k] < bounds[p + 1]) {
        k += 3;
      }
      brAt.add(k);
    }
    return [
      for (var p = 0; p < n; p++)
        {
          't': kWatchRoutePart,
          'id': id,
          'p': p,
          'n': n,
          if (p == 0) ..._head(),
          'pts': packedPts(bounds[p], bounds[p + 1]),
          'ele': ?packedEle(bounds[p], bounds[p + 1]),
          if (brAt[p + 1] > brAt[p]) 'br': packedBr(brAt[p], brAt[p + 1]),
        }
    ];
  }
}

/// Die navigierte Linie für die Uhr: vereinfacht (Douglas-Peucker, erst
/// [kWatchSimplifyM], dann doppelt, bis höchstens [maxPoints] bleiben),
/// Höhen aus dem Profil des Geländemodells (falls da), die Trails der
/// Route als Abschnitte. Der Ziel-Trail hinter dem Ende („Zum
/// Trailkopf") fährt nicht mit — er liegt nicht auf der Linie.
///
/// Die Punkte der [branches] (Nummern in [points]) bleiben beim
/// Vereinfachen stehen: Die Uhr zeichnet einen Stummel vom Punkt der
/// Linie aus — fiele die Kreuzung weg, begänne er am nächsten Knick.
WatchRoute? watchRouteOf(List<LatLng> points, NavSections sections,
    {ElevationProfile? heights, List<WatchBranch> branches = const [], int maxPoints = kWatchMaxPoints}) {
  if (points.length < 2) return null;
  final track = [for (final p in points) TrackPoint(p.latitude, p.longitude)];
  // Lage ab Start je Originalpunkt — die Abschnitte stehen in Metern.
  final cum = <double>[0];
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1], b = points[i];
    cum.add(cum.last + geo.distanceMeters(a.latitude, a.longitude, b.latitude, b.longitude));
  }
  if (!(cum.last > 0)) return null;
  final fixed = {
    for (final b in branches)
      if (b.index >= 0 && b.index < points.length) b.index,
    // Die Wendepunkte der Höhe bleiben auch: Douglas-Peucker sieht nur die
    // Lage, und auf einem geraden Forstweg über eine Kuppe fiel der Gipfel
    // weg — die Uhr zählte bergauf 198 statt 461 hm (fēnix 5, 2026-11-05).
    if (heights != null) ...climbTurnIndices(cum, heights),
  };
  final index = LinkedHashMap<TrackPoint, int>.identity();
  for (var i = 0; i < track.length; i++) {
    index[track[i]] = i;
  }
  var tol = kWatchSimplifyM;
  var line = _packable(_simplifyKeeping(track, fixed, tol), index, cum);
  // Die Stummel sind auf [kWatchMaxBranches] gekappt, es bleibt also
  // immer genug für die Linie; die Grenze der Toleranz ist nur ein Riegel.
  while (line.e5.length > maxPoints && tol < 1e5) {
    tol *= 2;
    line = _packable(_simplifyKeeping(track, fixed, tol), index, cum);
  }
  final along = line.along;

  final pts = <int>[];
  var lat = 0, lon = 0;
  for (var i = 0; i < line.e5.length; i++) {
    final (a, b) = line.e5[i];
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
  // Die Stummel an ihren Punkt der vereinfachten Linie, das Ende als
  // Versatz gegen die Kreuzung.
  final keptAt = {
    for (var i = 0; i < line.orig.length; i++)
      ?line.orig[i]: i,
  };
  final sorted = [
    for (final b in branches)
      if (keptAt[b.index] case final i?) (i: i, b: b),
  ]..sort((x, y) => x.i.compareTo(y.i));
  final br = <int>[];
  for (final (:i, :b) in sorted) {
    br.addAll([
      i,
      ((b.end.latitude - b.at.latitude) * 1e5).round(),
      ((b.end.longitude - b.at.longitude) * 1e5).round(),
    ]);
  }
  return WatchRoute(id: watchRouteId(pts), pts: pts, ele: ele, sec: sec, br: br);
}

/// Die vereinfachte Linie in 1e-5°, so dicht, dass jeder Schritt in 16 Bit
/// passt ([kWatchMaxDelta]): Ein längerer Abschnitt (ein gerader Forstweg,
/// stark vereinfacht) bekommt Zwischenpunkte auf der Geraden. [along] ist
/// die Lage ab Start (Meter der Originallinie), [orig] die Nummer in der
/// Originallinie, null für einen Zwischenpunkt.
({List<(int, int)> e5, List<double> along, List<int?> orig}) _packable(
    List<TrackPoint> kept, Map<TrackPoint, int> index, List<double> cum) {
  final e5 = <(int, int)>[];
  final along = <double>[];
  final orig = <int?>[];
  for (var i = 0; i < kept.length; i++) {
    final o = index[kept[i]]!;
    final p = ((kept[i].lat * 1e5).round(), (kept[i].lon * 1e5).round());
    if (e5.isNotEmpty) {
      final (a, b) = e5.last;
      final steps = (math.max((p.$1 - a).abs(), (p.$2 - b).abs()) / kWatchMaxDelta).ceil();
      final m0 = along.last;
      for (var k = 1; k < steps; k++) {
        final t = k / steps;
        e5.add(((a + (p.$1 - a) * t).round(), (b + (p.$2 - b) * t).round()));
        along.add(m0 + (cum[o] - m0) * t);
        orig.add(null);
      }
    }
    e5.add(p);
    along.add(cum[o]);
    orig.add(o);
  }
  return (e5: e5, along: along, orig: orig);
}

/// Die Punkte der Linie (Nummern in [cum]) an den Wendepunkten des
/// Profils, wie die Hysterese der Uhr sie zählt (`climbAt` in
/// `garmin/source/NavRoute.mc`, [kClimbHysteresisM]): jeder bestätigte
/// Gipfel und jede bestätigte Senke, dazu der letzte Kandidat. Bleiben sie
/// beim Vereinfachen stehen, zählt die Uhr aus den Höhen ihrer Punkte
/// dieselben Höhenmeter wie das Handy aus dem Profil.
Set<int> climbTurnIndices(List<double> cum, ElevationProfile heights, {double threshold = kClimbHysteresisM}) {
  final d = heights.distM, e = heights.eleM;
  if (d.length < 2 || !(cum.last > 0)) return const {};
  final turns = <int>[];
  var dir = 0, ref = e[0], extreme = e[0], at = 0;
  for (var i = 1; i < e.length; i++) {
    final h = e[i];
    if (dir == 0) {
      if ((h - ref).abs() >= threshold) {
        dir = h > ref ? 1 : -1;
        extreme = h;
        at = i;
      }
    } else if (dir * (h - extreme) > 0) {
      extreme = h;
      at = i;
    } else if (dir * (extreme - h) >= threshold) {
      turns.add(at);
      ref = extreme;
      dir = -dir;
      extreme = h;
      at = i;
    }
  }
  if (dir != 0) turns.add(at);
  // Profil-Meter auf Linien-Meter (wie beim Lesen der Höhen), dann der
  // nächste Punkt der Linie.
  final scale = cum.last / d.last;
  return {for (final i in turns) _nearest(cum, d[i] * scale)};
}

/// Douglas-Peucker je Stück zwischen den Punkten in [fixed] — die bleiben.
List<TrackPoint> _simplifyKeeping(List<TrackPoint> track, Set<int> fixed, double tol) {
  if (fixed.isEmpty) return simplify(track, toleranceM: tol);
  final cuts = {0, ...fixed, track.length - 1}.toList()..sort();
  final out = <TrackPoint>[];
  for (var k = 0; k + 1 < cuts.length; k++) {
    final piece = simplify(track.sublist(cuts[k], cuts[k + 1] + 1), toleranceM: tol);
    out.addAll(k == 0 ? piece : piece.skip(1));
  }
  return out;
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

/// Die Uhr-App meldet sich (beim Start und auf [watchQuery]) mit der
/// Kennung der Route, die sie gespeichert hat: `(hello: true, id: …)`,
/// `id` null ohne Route vom Handy. `bad` ist eine Route, die die Uhr-App
/// zweimal abstürzen ließ und die sie deshalb verworfen hat. Keine
/// Meldung: `hello` false.
({bool hello, String? id, String? bad}) watchHelloOf(Object? message) {
  if (message is! Map || message['t'] != kWatchHello) return (hello: false, id: null, bad: null);
  final id = message['id'], bad = message['bad'];
  return (hello: true, id: id is String ? id : null, bad: bad is String ? bad : null);
}

/// Die Uhr konnte ein Stück der Route [id] nicht nehmen: `(id, code)`
/// mit `code` aus [kWatchErrMemory] …, sonst null.
({String id, String code})? watchErrorOf(Object? message) {
  if (message is! Map || message['t'] != kWatchError) return null;
  final id = message['id'], code = message['c'];
  if (id is! String || code is! String) return null;
  return (id: id, code: code);
}

/// Hilft eine Route mit weniger Punkten? Bei Speicher und Absturz ja; ein
/// Stück in falscher Form wird auch kleiner nicht richtig.
bool watchErrorWantsSmaller(String code) => code != kWatchErrBad;

/// Hat die Uhr [routeId] gespeichert? Ihre Antwort auf eine vollständige
/// Route (Konzept 2).
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
