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

import '../rides/pocket_watch.dart' show pocketKeeps;
import '../rides/sensor_fusion.dart'
    show FusionEvent, FusionLive, JumpEvent, StoppieEvent, WheelieEvent;
import '../rides/trail_values.dart' show AirtimeLog;
import '../routing/nav_sections.dart';
import '../routing/route_progress.dart' show climbAfter;
import '../trails/gpx.dart' show TrackPoint;
import '../trails/trail_elevation.dart' show ElevationProfile;
import '../../core/geo.dart' as geo;
import '../offline_areas/height_tiles.dart'
    show hysteresisClimb, kClimbHysteresisM;
import 'watch_branches.dart';

/// Fassung des Protokolls (`v`); die Uhr lehnt eine andere ab. 2 seit
/// dem Packen (#449, 2026-11-05), 3 seit dem Speicher im „hallo", den
/// Werten des Handys (`nv`) und der Antwort „keine Navigation" (#659, #671,
/// #672; 2026-11-28 — die Uhr-App ist eine Entwickler-App, es gibt keine
/// älteren Stände zu bedienen, also auch keine Versionsweichen mehr).
const kWatchProtocol = 3;

/// So weit darf ein Schritt in 1e-5° gehen, damit er in 16 Bit passt —
/// in der Länge bei 47° gut 240 m. Längere Abschnitte teilt [watchRouteOf].
const kWatchMaxDelta = 32767;

/// So viele Byte belegt ein Punkt der Route im Arbeitsspeicher der Uhr
/// (vier Felder `xs/ys/cum/climb` in `NavRoute.mc`), gemessen im
/// Kettenstand (#671, fēnix 5, 2026-11-28: 600 → 800 → 1000 Punkte je
/// +4,1 KB, 20,6 B; `garmin/CLAUDE.md` „Das Budget aus dem hallo").
const kWatchPointBytes = 21;

/// Ein Stummel belegt drei Felder (`brAt/brX/brY`), drei Viertel eines
/// Punkts mit Höhen.
const kWatchBranchBytes = kWatchPointBytes * 3 ~/ 4;

/// So viel muss neben der Route frei bleiben, gemessen ab dem Stand beim
/// „hallo" (Lader mit Platzhalter): Ansicht, Verfolgung, Zahlen und
/// Aufnahme der Fahrt (3,0 KB) und das Stück einer zweiten Route samt der
/// Prüfung in `PhoneRoute.take` (4 KB + 16 B je Zahl, mit Nachricht) — die
/// Uhr nimmt während der Fahrt eine zweite gleich große Route an.
/// Kettenstand (#671, fēnix 5, Stücke zu [kWatchPartInts]): frei beim
/// „hallo" 36,9 KB; 900 Punkte gehen samt Wechsel (frei mit Aufnahme
/// 15,8 KB), 1000 nicht (13,3 KB, `x` mem). Mit 19 KB sind es 830 — 70
/// Punkte Luft.
const kWatchReserveBytes = 19 * 1024;

/// Ohne „hallo" mit Speicher (die Uhr hat sich in diesem Lauf noch nicht
/// gemeldet): so viele Punkte — nicht mehr, als die fēnix 5 im Kettenstand
/// samt Wechsel während der Fahrt nimmt (#671). Mit dem „hallo" geht die
/// Route im Budget der Uhr hinterher.
const kWatchDefaultPoints = 500;

/// Mehr Punkte nimmt die Uhr nie (`PhoneRoute.MAX_POINTS`).
const kWatchPointsCap = 4000;

/// Wenigstens so viele: darunter navigiert keine Linie mehr.
const kWatchMinPoints = 50;

/// Das Budget in Punkten aus dem Speicher, den die Uhr im „hallo" meldet
/// (#671): [freeB] frei jetzt, [loaded] Punkte der geladenen Route (die
/// gibt sie beim Wechsel frei). Null ohne Angabe.
int? watchBudgetOf(int? freeB, int loaded) {
  if (freeB == null) return null;
  final clean = freeB + loaded * kWatchPointBytes - kWatchReserveBytes;
  return (clean ~/ kWatchPointBytes).clamp(kWatchMinPoints, kWatchPointsCap);
}

/// Startwert der Vereinfachung (Konzept 2): Genauer muss die Linie für die
/// Uhr nicht sein — passt sie so ins Budget, bleibt der Rest frei.
const kWatchSimplifyM = 5.0;

/// Ab dieser Abweichung navigiert die Linie nicht mehr (#671): Die Uhr sagt
/// bei 30 m „abseits" (`OFF_ROUTE_M`), mit 25 m Vereinfachung blieben dem
/// GPS 5 m. Braucht eine Route mehr, schneidet das Handy sie ab und sagt
/// es ([WatchRoute.cutM]).
const kWatchMaxTolM = 25.0;

/// So viele Zahlen trägt ein Stück — rund 2 KB serialisiert (5 Byte je
/// Ganzzahl), mit Kopf und Trails im ersten; gepackt gut 250 Punkte samt
/// Höhen. Die Uhr hält beim Empfang ein Stück und verlangt zum Speichern
/// 4 KB + 16 B je Zahl frei (`PhoneRoute.take`). Seit #671 400 statt 800:
/// Das halbiert, was neben einer geladenen Route frei sein muss, und trägt
/// gut 400 Punkte mehr Route (Kettenstand: mit 800 scheiterte schon der
/// Wechsel zweier 600-Punkte-Routen, mit 400 gehen 900) — für ein Stück
/// mehr je Route.
const kWatchPartInts = 400;

/// Namen kürzt die App: Die Uhr zeigt ohnehin nur eine Zeile.
const kWatchNameChars = 24;

/// Art der Nachricht (`t`): ein Stück Route, die Bestwerte, die Frage
/// „welche Route hast du?" an die Uhr; zurück „gespeichert" und „hallo".
const kWatchRoutePart = 'r';
const kWatchBests = 'b';
const kWatchQuery = 'q';
const kWatchStored = 'ok';
const kWatchHello = 'hi';

/// Die Position des Handys als erster Fix der Uhr (`{t: "p", la, lo}` in
/// 1e-5°; Betreiber 2026-11-05): Bis die Uhr selbst GPS hat, zeigt sie
/// damit Position und Wege statt Strichen. Sie bleibt im Speicher der Uhr.
const kWatchPhonePosition = 'p';

/// Die Antwort auf `hi` beim Start der Uhr-App (Betreiber 2026-11-06):
/// `{t: "n", id, np}` — eine neue Route kommt, in `np` Stücken (0: wird
/// noch gerechnet); die Uhr zeigt dann den Lader statt der alten Route.
/// `{t: "k", id}` — die gespeicherte ist aktuell. Ohne Antwort zeigt die
/// Uhr nach 8 s die gespeicherte (gemessen: „hallo" hin und Antwort
/// zurück 5–7 s über Garmin Connect, 2026-11-06). Beides kam neu dazu,
/// ohne neue Fassung: Eine ältere Uhr übergeht unbekannte Arten, eine neue
/// Uhr mit älterer App wartet nur die 8 s.
const kWatchAnnounce = 'n';
const kWatchCurrent = 'k';

/// „Eine neue Route kommt" ([kWatchAnnounce]).
Map<String, Object> watchAnnounceOf(String? id, int parts) => {
  't': kWatchAnnounce,
  'np': parts,
  'id': ?id,
};

/// „Deine Route ist aktuell" ([kWatchCurrent]).
Map<String, Object> watchCurrentOf(String id) => {'t': kWatchCurrent, 'id': id};

/// Die Navigation endet (`{t: "e", id}`, Betreiber 2026-11-06), in beide
/// Richtungen: Endet sie auf dem Handy, schließt sich die Uhr-App; endet
/// sie auf der Uhr, beendet das Handy seine Navigation — nur die, nie die
/// Aufzeichnung (die läuft weiter, gespeichert wird wie bisher von Hand).
/// [id] ist die Route, damit eine alte Nachricht keine andere Navigation
/// beendet.
const kWatchEnd = 'e';

Map<String, Object> watchEndOf(String id) => {'t': kWatchEnd, 'id': id};

/// Die Kennung aus „Navigation beendet" der Uhr, oder null.
String? watchEndedId(Object? message) =>
    message is Map && message['t'] == kWatchEnd && message['id'] is String
    ? message['id'] as String
    : null;

/// Die Uhr hat ihr eigenes GPS (`{t: "g"}`). Seit #500 meldet sie dabei
/// ihren ersten Fix mit (`la`, `lo` in 1e-5°); danach schickt das Handy keine
/// Position mehr. Die Koordinate bleibt im Speicher (A3), nichts wird
/// gespeichert und nichts geht an Garmin.
const kWatchHasGps = 'g';

/// Der Fix der Uhr, oder null, wenn die Nachricht keiner ist — ältere
/// Uhr-Apps sagen nur „habe GPS" (`{t: "g"}` ohne Zahlen).
LatLng? watchFixOf(Object? message) {
  if (message is! Map || message['t'] != kWatchHasGps) return null;
  final la = message['la'], lo = message['lo'];
  if (la is! num || lo is! num) return null;
  return LatLng(la / 1e5, lo / 1e5);
}

/// „Ich fahre hinaus" (#500): Die Uhr meldet ihren Stand, sobald er über die
/// Sicht ihrer Ansicht hinaus von der Linie abseits liegt, und erst 300 m
/// weiter als die letzte Meldung (`garmin/source/NavTracker.mc`, `driftM`).
/// Kein Takt, das Handy fragt nie nach.
const kWatchDrift = 'd';

/// Der Stand aus einer Drift-Meldung — Stand und Abstand zur Linie — oder
/// null, wenn die Nachricht keine ist.
({LatLng at, double offM})? watchDriftOf(Object? message) {
  if (message is! Map || message['t'] != kWatchDrift) return null;
  final la = message['la'], lo = message['lo'], off = message['off'];
  if (la is! num || lo is! num || off is! num) return null;
  return (at: LatLng(la / 1e5, lo / 1e5), offM: off.toDouble());
}

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

/// Das Stück hatte eine andere Fassung (`v` steht in der Antwort).
const kWatchErrVersion = 'ver';

/// Packt zwei Werte mit 16 Bit Vorzeichen in eine 32-Bit-Zahl, wie
/// `PhoneRoute.unpackHi/unpackLo` sie auf der Uhr wieder auspacken. Auch
/// im Web (32-Bit-Schieben ohne Vorzeichen) eine Zahl mit Vorzeichen —
/// eine Zahl über 32 Bit käme in Kotlin als `Long` und auf der Uhr als
/// `Long` an.
int watchPack(int hi, int lo) =>
    ((hi & 0xffff) << 16 | (lo & 0xffff)).toSigned(32);

/// Gegenstück zu [watchPack] (Tests).
(int, int) watchUnpack(int v) =>
    (((v >> 16) & 0xffff).toSigned(16), (v & 0xffff).toSigned(16));

/// Die Frage an die Uhr, nach dem Wiederverbinden: Läuft ihre App, meldet
/// sie sich mit `hi` (läuft sie nicht, verfällt die Nachricht still).
const Map<String, Object> watchQuery = {'t': kWatchQuery};

/// Die Position des Handys für die Uhr ([kWatchPhonePosition]).
Map<String, Object> watchPositionOf(LatLng p) => {
  't': kWatchPhonePosition,
  'la': (p.latitude * 1e5).round(),
  'lo': (p.longitude * 1e5).round(),
};

/// Meldet die Uhr ihr eigenes GPS ([kWatchHasGps])?
bool watchHasGps(Object? message) =>
    message is Map && message['t'] == kWatchHasGps;

/// Welche Seite ist veraltet, wenn die Uhr mit Fassung [v] spricht? Null,
/// wenn sie passt; ohne Fassung gilt die Uhr als veraltet.
WatchOutdated? watchOutdatedOf(int? v) {
  if (v == kWatchProtocol) return null;
  if (v == null || v < kWatchProtocol) return WatchOutdated.watch;
  return WatchOutdated.phone;
}

enum WatchOutdated { watch, phone }

/// Die Route für die Uhr, noch nicht in Stücken.
class WatchRoute {
  const WatchRoute({
    required this.id,
    required this.pts,
    required this.ele,
    required this.sec,
    this.br = const [],
    this.tolM = kWatchSimplifyM,
    this.name = '',
    this.lengthM = 0,
    this.climbM = 0,
    this.cutM,
    this.secOf = const [],
  });

  final String id;
  final List<int> pts;
  final List<int>? ele;
  final List<List<Object>> sec;

  /// Die Stummel als `[Punkt, dLat, dLon, …]`, nach Punkt sortiert.
  final List<int> br;

  /// So weit weicht die vereinfachte Linie höchstens ab (m): mehr als
  /// [kWatchSimplifyM] heißt, die Linie war fürs Budget zu lang (#515: die
  /// Ablage sagt es, wenn es viel war).
  final double tolM;

  /// Name, Länge (m) und bergauf (hm) im Kopf (`nm`, `len`, `hm`): Das
  /// Startmenü der Uhr nennt die letzte Route damit (#672).
  final String name;
  final int lengthM;
  final int climbM;

  /// Passte die Linie nur verkürzt aufs Budget ([kWatchMaxTolM]), endet sie
  /// hier (m der ganzen Linie) — sonst null (#671).
  final double? cutM;

  /// Je Eintrag in [sec] der Trail der Navigation, aus dem er kam — die
  /// Werte des Handys (`nv`, #659) nennen Trails mit dieser Stelle.
  final List<NavTrailSection> secOf;

  int get pointCount => pts.length ~/ 2;

  /// Gepackt: je Punkt `(dLat << 16) | dLon` gegen den Vorgänger, der
  /// erste gegen den Ursprung `o` (also 0).
  List<int> packedPts([int from = 0, int? to]) => [
    for (var i = from; i < (to ?? pointCount); i++)
      i == 0 ? 0 : watchPack(pts[2 * i], pts[2 * i + 1]),
  ];

  /// Die Höhen der Punkte [from] bis [to] als Differenzen gegen den
  /// Vorgänger (der erste Punkt gegen `e0`, also 0), zu zweit in einer Zahl;
  /// eine ungerade Zahl von Punkten füllt mit 0 auf.
  List<int>? packedEle([int from = 0, int? to]) {
    final e = ele;
    if (e == null) return null;
    final end = to ?? pointCount;
    int d(int i) =>
        i == 0 ? 0 : (e[i] - e[i - 1]).clamp(-kWatchMaxDelta, kWatchMaxDelta);
    return [
      for (var i = from; i < end; i += 2)
        watchPack(d(i), i + 1 < end ? d(i + 1) : 0),
    ];
  }

  /// Die Stummel `br[from…to)` (Stellen in [br], je drei) als `[Punkt,
  /// gepackt(dLat, dLon)]`.
  List<int> packedBr([int from = 0, int? to]) => [
    for (var k = from; k + 2 < (to ?? br.length); k += 3) ...[
      br[k],
      watchPack(
        br[k + 1].clamp(-kWatchMaxDelta, kWatchMaxDelta),
        br[k + 2].clamp(-kWatchMaxDelta, kWatchMaxDelta),
      ),
    ],
  ];

  /// Der Kopf, den das erste Stück trägt.
  Map<String, Object> _head() => {
    'v': kWatchProtocol,
    'np': pointCount,
    'o': [pts[0], pts[1]],
    if (ele case final e?) 'e0': e[0],
    if (sec.isNotEmpty) 'sec': sec,
    'nm': name,
    'len': lengthM,
    'hm': climbM,
  };

  /// So viele Zahlen kostet der Kopf auf dem Draht (Namen nach Bytes, eine
  /// Zahl je 5): Er zählt in die Grenze des ersten Stücks.
  int _headInts() {
    var n = 11 + (utf8.encode(name).length + 4) ~/ 5;
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
        points +
        (withEle ? (points + 1) ~/ 2 : 0) +
        brUsed +
        (first ? head : 0);
    // Grenzen der Stücke: so viele Punkte, wie samt Stummeln passen.
    final bounds = <int>[0];
    var points = 0, brUsed = 0;
    for (var i = 0; i < pointCount; i++) {
      if (points > 0 &&
          cost(points + 1, brUsed + brInts[i], bounds.length == 1) > maxInts) {
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
        },
    ];
  }
}

/// Die navigierte Linie für die Uhr (#671): vereinfacht auf höchstens
/// [maxPoints] Punkte — das Budget aus dem „hallo" ([watchBudgetOf]) —, mit
/// Vorrang die größte Abweichung zuerst ([watchSimplify]), und nicht
/// genauer als [kWatchSimplifyM]. Bliebe dabei mehr Abweichung als
/// [kWatchMaxTolM], endet die Route dort, wo das Budget noch reicht
/// ([WatchRoute.cutM]). Höhen aus dem Profil des Geländemodells (falls da),
/// die Trails der Route als Abschnitte. Der Ziel-Trail hinter dem Ende
/// („Zum Trailkopf") fährt nicht mit — er liegt nicht auf der Linie.
///
/// Die Punkte der [branches] (Nummern in [points]) bleiben beim
/// Vereinfachen stehen: Die Uhr zeichnet einen Stummel vom Punkt der
/// Linie aus — fiele die Kreuzung weg, begänne er am nächsten Knick.
WatchRoute? watchRouteOf(
  List<LatLng> points,
  NavSections sections, {
  ElevationProfile? heights,
  List<WatchBranch> branches = const [],
  int maxPoints = kWatchDefaultPoints,
  String name = '',
}) {
  if (points.length < 2) return null;
  final track = [for (final p in points) TrackPoint(p.latitude, p.longitude)];
  // Lage ab Start je Originalpunkt — die Abschnitte stehen in Metern.
  final cum = <double>[0];
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1], b = points[i];
    cum.add(
      cum.last +
          geo.distanceMeters(a.latitude, a.longitude, b.latitude, b.longitude),
    );
  }
  if (!(cum.last > 0)) return null;
  // Die Stummel kosten mit: Was sie belegen, fehlt der Linie.
  final budget = math.max(
    2,
    maxPoints - branches.length * kWatchBranchBytes ~/ kWatchPointBytes,
  );
  final allFixed = {
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

  // Auf das Budget, samt der Zwischenpunkte langer Geraden (16 Bit).
  ({_Packed line, double tol}) fit(int last) {
    final fixed = {
      for (final i in allFixed)
        if (i < last) i,
    };
    var target = budget;
    while (true) {
      final s = watchSimplify(points, fixed, maxPoints: target, last: last);
      final line = _packable([for (final i in s.kept) track[i]], index, cum);
      final over = line.e5.length - budget;
      if (over <= 0 || target <= fixed.length + 2) {
        return (line: line, tol: s.tolM);
      }
      target -= over;
    }
  }

  var last = points.length - 1;
  var fitted = fit(last);
  double? cutM;
  if (fitted.tol > kWatchMaxTolM) {
    // Die längste Anfangsstrecke, die mit höchstens kWatchMaxTolM passt.
    var lo = 1, hi = last;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (fit(mid).tol <= kWatchMaxTolM) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    last = lo;
    fitted = fit(last);
    cutM = cum[last];
  }
  final line = fitted.line;
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
  final secOf = <NavTrailSection>[];
  for (final t in sections.ridden) {
    if (cutM != null && t.startM >= cutM) continue;
    final from = _nearest(along, t.startM), to = _nearest(along, t.endM);
    if (to <= from) continue;
    sec.add([from, to, watchGrade(t), _short(t.name)]);
    secOf.add(t);
  }
  // Die Stummel an ihren Punkt der vereinfachten Linie, das Ende als
  // Versatz gegen die Kreuzung.
  final keptAt = {for (var i = 0; i < line.orig.length; i++) ?line.orig[i]: i};
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
  return WatchRoute(
    id: watchRouteId(pts),
    pts: pts,
    ele: ele,
    sec: sec,
    br: br,
    tolM: math.max(kWatchSimplifyM, fitted.tol),
    name: _short(name),
    lengthM: along.last.round(),
    climbM: ele == null
        ? 0
        : hysteresisClimb([
            for (final e in ele) e.toDouble(),
          ], kClimbHysteresisM).$1.round(),
    cutM: cutM,
    secOf: secOf,
  );
}

/// Douglas-Peucker mit Vorrang (#671): Die Punkte [fixed], Anfang und Ende
/// ([last], ohne: der letzte Punkt) bleiben; dann kommt immer der Punkt
/// mit der größten Abweichung von der bisherigen Linie dazu, bis
/// [maxPoints] erreicht sind oder keiner mehr als [minTolM] abweicht. So
/// nutzt eine lange Route das Budget ganz, statt die Toleranz zu
/// verdoppeln und im Mittel ein Viertel liegen zu lassen. Douglas-Peucker
/// statt Visvalingam: Es begrenzt genau die Größe, nach der die Uhr
/// „abseits" sagt — den Abstand zur Linie —, Visvalingam nur eine Fläche,
/// und an einer Serpentine wiegt eine schmale, lange Kehre wenig Fläche.
/// [tolM]: die größte Abweichung, die bleibt.
({List<int> kept, double tolM}) watchSimplify(
  List<LatLng> points,
  Set<int> fixed, {
  required int maxPoints,
  double minTolM = kWatchSimplifyM,
  int? last,
}) {
  final end = last ?? points.length - 1;
  if (end < 1) return (kept: [0], tolM: 0);
  final kx = 111194.9 * math.cos(points.first.latitude * math.pi / 180);
  const ky = 111194.9;
  final xs = [for (var i = 0; i <= end; i++) points[i].longitude * kx];
  final ys = [for (var i = 0; i <= end; i++) points[i].latitude * ky];
  // Die schlimmste Stelle zwischen a und b: (Abstand, Stelle).
  (double, int) worst(int a, int b) {
    final ax = xs[a], ay = ys[a];
    final dx = xs[b] - ax, dy = ys[b] - ay;
    final l2 = dx * dx + dy * dy;
    var d2 = -1.0, at = -1;
    for (var i = a + 1; i < b; i++) {
      final px = xs[i] - ax, py = ys[i] - ay;
      final t = l2 == 0 ? 0.0 : ((px * dx + py * dy) / l2).clamp(0.0, 1.0);
      final ex = px - t * dx, ey = py - t * dy;
      final e = ex * ex + ey * ey;
      if (e > d2) {
        d2 = e;
        at = i;
      }
    }
    return (d2 < 0 ? 0.0 : math.sqrt(d2), at);
  }

  final keep = {
    0,
    end,
    for (final i in fixed)
      if (i > 0 && i < end) i,
  };
  final cuts = keep.toList()..sort();
  // Größte Abweichung zuerst; die Stelle trennt gleiche Abstände.
  final queue = SplayTreeSet<(double, int, int, int)>((x, y) {
    final c = y.$1.compareTo(x.$1);
    return c != 0 ? c : x.$2.compareTo(y.$2);
  });
  void push(int a, int b) {
    if (b - a < 2) return;
    final (d, i) = worst(a, b);
    queue.add((d, i, a, b));
  }

  for (var k = 0; k + 1 < cuts.length; k++) {
    push(cuts[k], cuts[k + 1]);
  }
  while (queue.isNotEmpty && keep.length < maxPoints) {
    final top = queue.first;
    if (top.$1 <= minTolM) break;
    queue.remove(top);
    keep.add(top.$2);
    push(top.$3, top.$2);
    push(top.$2, top.$4);
  }
  final tol = queue.isEmpty ? 0.0 : queue.first.$1;
  return (kept: keep.toList()..sort(), tolM: tol);
}

/// Die vereinfachte Linie in 1e-5°, so dicht, dass jeder Schritt in 16 Bit
/// passt ([kWatchMaxDelta]): Ein längerer Abschnitt (ein gerader Forstweg,
/// stark vereinfacht) bekommt Zwischenpunkte auf der Geraden. [along] ist
/// die Lage ab Start (Meter der Originallinie), [orig] die Nummer in der
/// Originallinie, null für einen Zwischenpunkt.
typedef _Packed = ({List<(int, int)> e5, List<double> along, List<int?> orig});

_Packed _packable(
  List<TrackPoint> kept,
  Map<TrackPoint, int> index,
  List<double> cum,
) {
  final e5 = <(int, int)>[];
  final along = <double>[];
  final orig = <int?>[];
  for (var i = 0; i < kept.length; i++) {
    final o = index[kept[i]]!;
    final p = ((kept[i].lat * 1e5).round(), (kept[i].lon * 1e5).round());
    if (e5.isNotEmpty) {
      final (a, b) = e5.last;
      final steps =
          (math.max((p.$1 - a).abs(), (p.$2 - b).abs()) / kWatchMaxDelta)
              .ceil();
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
Set<int> climbTurnIndices(
  List<double> cum,
  ElevationProfile heights, {
  double threshold = kClimbHysteresisM,
}) {
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
    for (final byte in [
      v & 0xff,
      (v >> 8) & 0xff,
      (v >> 16) & 0xff,
      (v >> 24) & 0xff,
    ]) {
      h = ((h ^ byte) * 0x01000193) & 0xffffffff;
    }
  }
  return h.toRadixString(16).padLeft(8, '0');
}

/// Die Bestwerte der Erkennung (#36) für die Seite „Fahrt" und die
/// Zusammenfassung auf der Uhr (Idee des Betreibers, Konzept 9.2): nur
/// Zahlen, keine Spur, nichts, was die Uhr misst. Mit „War keiner"
/// Beantwortetes zählt nicht ([AirtimeLog.kept]).
///
/// `on` (#514): Das Handy erkennt gerade UND kennt seine Halterung
/// ([watchDetecting]) — dann zeigt die Uhr ihr Zeichen am Rand der Karte.
/// Null nur ohne Ereignis und ohne Erkennung; das „aus" nach einem „an"
/// schickt [WatchSync] trotzdem, mit lauter Nullen.
Map<String, Object>? watchBestsOf(AirtimeLog log, {bool on = false}) {
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
  if (jumps + wheelies + stoppies == 0 && !on) return null;
  return {
    't': kWatchBests,
    'on': on ? 1 : 0,
    'jn': jumps,
    'ja': airMs,
    'wn': wheelies,
    'wl': wheelieM.round(),
    'wa': wheelieDeg.round(),
    'sn': stoppies,
  };
}

/// Ein Ereignis der Erkennung als kurzer Hinweis im Fußfeld der Uhr
/// (#514): `{t: "c", k: "air"|"wh"|"st", v}` — Flugzeit und Stoppie in
/// ms, Wheelie in Metern. Eine ältere Uhr übergeht die Art.
const kWatchCue = 'c';

/// Antwort auf einen Sensorhinweis: `s` gibt den Ereignisbeginn als
/// Dezimaltext unverändert zurück (Unix-µs > 32 Bit).
const kWatchCueAnswer = 'ca';

String watchSensorKind(FusionEvent event) => switch (event) {
  JumpEvent() => 'air',
  WheelieEvent() => 'wh',
  StoppieEvent() => 'st',
};

({int startUs, String kind, bool yes})? watchCueAnswerOf(Object? msg) {
  if (msg case {
    't': kWatchCueAnswer,
    's': final String start,
    'k': final String kind,
    'y': final int yes,
  }) {
    final startUs = int.tryParse(start);
    if (startUs != null && startUs > 0 && (yes == 0 || yes == 1)) {
      return (startUs: startUs, kind: kind, yes: yes == 1);
    }
  }
  return null;
}

/// Die Buddys mit genauer Position an die Uhr (#519, `watch_buddies.dart`):
/// `{t: "u", l: [[la, lo, Buchstabe, Alter s], …]}`.
const kWatchBuddies = 'u';

/// Höchstens ein Hinweis je [kWatchCueEvery]: Eine Nachricht braucht über
/// Garmin Connect ~3,5 s (8.2) — dazwischen gehen nur die Bestwerte.
const kWatchCueEvery = Duration(seconds: 10);

/// Ein Ereignis, das beim Absenden länger als [kWatchCueMaxAge] vorbei
/// ist, geht nicht mehr hin: Die Uhr zeigt „gerade eben", keine
/// Geschichte. Gemessen wird am Handy — eine gemeinsame Uhrzeit mit der
/// Uhr gibt es nicht. Ein Ereignis kommt 2–4 s nach der Landung aus der
/// Erkennung (`lib/features/rides/CLAUDE.md`).
const kWatchCueMaxAge = Duration(seconds: 8);

/// Bis so lange nach dem letzten Takt der Erkennung gilt sie als laufend.
/// Die Takte kommen je GPS-Punkt (1 s), die Lage jetzt alle 100 ms.
const kWatchDetectFresh = Duration(seconds: 5);

/// Erkennt das Handy gerade? [latest] ist der
/// jüngste Takt (Unix-µs, die Achse der Sensoren), [nowUs] die Uhrzeit.
bool watchDetecting(FusionLive? latest, int nowUs) =>
    latest != null && nowUs - latest.tUs <= kWatchDetectFresh.inMicroseconds;

/// Der Hinweis zu [e], oder null für ein zu altes Ereignis. In der
/// Tasche liefert der Dienst ausschließlich Sprünge nach `pocketKeeps`;
/// dort soll man auch einen als unplausibel eingestuften Sprung bewerten.
Map<String, Object>? watchCueOf(
  FusionEvent e,
  int nowUs, {
  bool pocket = false,
}) {
  final endUs = e.startUs + e.duration.inMicroseconds;
  if (nowUs - endUs > kWatchCueMaxAge.inMicroseconds) return null;
  if (pocket ? !pocketKeeps(e) : e is JumpEvent && !e.plausible) return null;
  return {
    't': kWatchCue,
    'k': watchSensorKind(e),
    'v': e is WheelieEvent ? e.lengthM.round() : e.duration.inMilliseconds,
    's': e.startUs.toString(),
  };
}

/// Die Uhr-App meldet sich (beim Start und auf [watchQuery]) mit der
/// Kennung der Route, die sie gespeichert hat: `(hello: true, id: …)`,
/// `id` null ohne Route vom Handy. `bad` ist eine Route, die die Uhr-App
/// zweimal abstürzen ließ und die sie deshalb verworfen hat. Keine
/// Meldung: `hello` false.
///
/// `v` ist die Fassung des Protokolls der Uhr-App (null, wenn sie fehlt),
/// `ver` die der Uhr-App selbst. `rides` sind die Fahrten, die auf der Uhr
/// auf das Handy warten (`rq`, #484, `watch_ride.dart`). Seit Protokoll 3
/// (#671) der Speicher: `m` frei in Byte, `tm` gesamt, `lp` die Punkte der
/// geladenen Route — daraus [budget] ([watchBudgetOf]); null ohne Angabe.
typedef WatchHello = ({
  bool hello,
  String? id,
  String? bad,
  int? v,
  String? ver,
  List<String> rides,
  int? budget,
  int? totalB,
});

WatchHello watchHelloOf(Object? message) {
  if (message is! Map || message['t'] != kWatchHello) {
    return (
      hello: false,
      id: null,
      bad: null,
      v: null,
      ver: null,
      rides: const [],
      budget: null,
      totalB: null,
    );
  }
  final id = message['id'],
      bad = message['bad'],
      v = message['v'],
      ver = message['ver'],
      rq = message['rq'],
      m = message['m'],
      tm = message['tm'],
      lp = message['lp'];
  return (
    hello: true,
    id: id is String ? id : null,
    bad: bad is String ? bad : null,
    v: v is int ? v : null,
    ver: ver is String ? ver : null,
    rides: rq is List
        ? [
            for (final r in rq)
              if (r is String) r,
          ]
        : const <String>[],
    budget: watchBudgetOf(m is int ? m : null, lp is int ? lp : 0),
    totalB: tm is int ? tm : null,
  );
}

/// Die Antwort auf `hi`, wenn das Handy nicht navigiert (#672): Die Uhr
/// zeigt gleich ihr Startmenü, statt 8 s auf nichts zu warten.
const kWatchNoNav = 'nn';
const Map<String, Object> watchNoNav = {'t': kWatchNoNav};

/// Die Werte des Handys, solange es verbunden ist (#659): `{t: "nv", id,
/// k, o, d, c, r, g}` — `k` der nächste Trailkopf und `o` der Trail, auf
/// dem man ist (Stellen in `sec` der Route, -1 ohne), `d` Meter bis zum
/// Ende dieses Trails bzw. zum Kopf bzw. zum Ziel, `c` Höhenmeter bis zum
/// Kopf, `r` Meter und `g` Höhenmeter bis zum Ziel (-1 ohne Profil). Die
/// Uhr nimmt sie, solange sie frisch sind und ihr eigener Stand denselben
/// Trail nennt; sonst rechnet sie selbst.
const kWatchNavValues = 'nv';

/// Alle so viele Sekunden die Werte, dazu sofort bei einem neuen Abschnitt.
const kWatchNavValuesEvery = Duration(seconds: 10);

/// Die Werte des Handys ([kWatchNavValues], #659) beim Stand [alongM] der
/// Navigation auf einer Linie von [lengthM] — die Trails nach ihrer Stelle
/// in [WatchRoute.sec], die Höhenmeter aus dem Profil des Geländemodells
/// (`climbAfter`, dieselbe Hysterese wie das Ergebnis).
Map<String, Object> watchNavValuesOf(
  WatchRoute route,
  double alongM,
  double lengthM, {
  List<double>? climbDistM,
  List<double>? climbEleM,
}) {
  final secs = route.secOf;
  var o = -1, k = -1;
  for (var i = 0; i < secs.length; i++) {
    final t = secs[i];
    if (alongM >= t.startM && alongM < t.endM) o = i;
    if (t.startM > alongM && (k < 0 || t.startM < secs[k].startM)) k = i;
  }
  final d = o >= 0
      ? secs[o].endM - alongM
      : (k >= 0 ? secs[k].startM - alongM : lengthM - alongM);
  final c = k < 0
      ? null
      : climbAfter(climbDistM, climbEleM, alongM, untilM: secs[k].startM);
  final g = climbAfter(climbDistM, climbEleM, alongM);
  return {
    't': kWatchNavValues,
    'id': route.id,
    'k': k,
    'o': o,
    'd': math.max(0.0, d).round(),
    'c': c?.round() ?? -1,
    'r': math.max(0.0, lengthM - alongM).round(),
    'g': g?.round() ?? -1,
  };
}

/// Die Uhr konnte ein Stück der Route [id] nicht nehmen: `(id, code)`
/// mit `code` aus [kWatchErrMemory] …, sonst null.
/// Bei [kWatchErrVersion] trägt `v` die Fassung der Uhr-App.
({String id, String code, int? v})? watchErrorOf(Object? message) {
  if (message is! Map || message['t'] != kWatchError) return null;
  final id = message['id'], code = message['c'], v = message['v'];
  if (id is! String || code is! String) return null;
  return (id: id, code: code, v: v is int ? v : null);
}

/// Hilft eine Route mit weniger Punkten? Bei Speicher und Absturz ja; ein
/// Stück in falscher Form oder Fassung wird auch kleiner nicht richtig.
bool watchErrorWantsSmaller(String code) =>
    code != kWatchErrBad && code != kWatchErrVersion;

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
  if (lo > 0 && (m - along[lo - 1]).abs() < (along[lo] - m).abs()) {
    return lo - 1;
  }
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

String _short(String name) => name.length <= kWatchNameChars
    ? name
    : '${name.substring(0, kWatchNameChars - 1)}…';
