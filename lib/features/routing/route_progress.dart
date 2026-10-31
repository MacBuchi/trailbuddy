// Wo auf der Route man ist (#232, Konzept-Routing 9.3) — pur, ohne
// Flutter, damit die Folgeansicht und später der Dienst-Isolate (9.5)
// dieselbe Rechnung fahren.
//
// Die Position wird auf die Linie projiziert, gesucht zuerst nur in einem
// Fenster VORAUS vom letzten Stand: Eine Runde, die denselben Weg hin und
// zurück nimmt, soll nicht auf die Rückfahrt springen. Erst wenn das
// Fenster nichts in [kNavOffRouteM] findet, zählt die ganze Linie.
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../core/geo.dart' as geo;
import '../offline_areas/height_tiles.dart' show hysteresisClimb, kClimbHysteresisM;
import 'nav_sections.dart';

export 'nav_sections.dart';

/// Weiter weg als das heißt „abseits" — dieselben 30 m wie „kein Weg" bei
/// den Zwischenpunkten (Konzept-Routing 4).
const kNavOffRouteM = 30.0;

/// So viele Fixe in Folge abseits, bevor die Ansicht es sagt: Ein
/// einzelner Ausreißer des GPS ist keine Abweichung.
const kNavOffRouteFixes = 2;

/// So weit voraus vom letzten Stand wird zuerst gesucht.
const kNavAheadWindowM = 800.0;

/// So weit darf der Stand zurück, ohne dass die ganze Linie gesucht wird
/// — das GPS zittert auch rückwärts.
const kNavBackSlackM = 30.0;

/// Näher am Ende ist man angekommen.
const kNavArriveM = 30.0;

/// Darunter dreht der GPS-Kurs im Stand zufällig — es gilt der letzte.
const kNavHeadingMinSpeedMps = 2.0;

/// Der Zoom der Folgeansicht beim Start (256er-Stufen der Fassade).
const kNavZoom = 16.0;

/// Der Zoom im Bild-im-Bild (#415, Konzept-Routing 9.6): Das Fenster ist
/// ein Drittel so breit wie der Schirm (132 dp auf dem Pixel XL), 1,5
/// Stufen weniger zeigen darin etwa den Boden der Folgeansicht. Mit
/// [kNavZoom] waren es 200 m — ein Stück Weg ohne Route.
const kNavPipZoom = 14.5;

/// So viel der Fensterhöhe nimmt unten die Zeile (#415) …
const kNavPipBarShare = 0.28;

/// … und so weit liegt die Mitte vor der Position: Sie steht im freien
/// Teil darüber bei 75 % seiner Höhe, knapp unter der Mitte des
/// Fensters — voraus liegt dreimal so viel Route wie dahinter. Ein
/// Sechstel wie im Vollbild hätte sie unter die Zeile geschoben.
double pipAheadPx(double heightPx) => heightPx * (1 - kNavPipBarShare) * 0.75 - heightPx / 2;

/// Nach „Angekommen" endet die Navigation von selbst (9.3) — in der App
/// und, ist die weggewischt, im Dienst (`nav_notice.dart`).
const kNavArrivedLinger = Duration(minutes: 1);

/// Über so viele Meter voraus gilt die Richtung der Linie, solange das
/// GPS keinen Kurs hat.
const kNavHeadingLookM = 50.0;

/// Wohin der Pfeil abseits zeigt: so weit voraus auf der Linie.
const kNavRejoinAheadM = 50.0;

/// „Zurück zur Route" führt so weit voraus auf die Linie (9.3): Der
/// nächste Punkt liegt oft hinter einem, und man führe zurück.
const kNavRejoinTargetM = 200.0;

/// Die Linie, die navigiert wird, mit der Distanz ab Start je Punkt.
class NavRoute {
  NavRoute._(this.points, this.cumM);

  /// Null, wenn die Linie keine Länge hat.
  static NavRoute? of(List<LatLng> points) {
    if (points.length < 2) return null;
    final cum = <double>[0];
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      cum.add(cum.last + geo.distanceMeters(a.latitude, a.longitude, b.latitude, b.longitude));
    }
    if (cum.last <= 0) return null;
    return NavRoute._(List.unmodifiable(points), cum);
  }

  final List<LatLng> points;

  /// Distanz ab Start in Metern, je Punkt.
  final List<double> cumM;

  double get lengthM => cumM.last;

  /// Beginnt und endet die Linie am selben Ort? Dann ist „am Ende" erst
  /// gemeint, wenn der letzte Abschnitt erreicht ist (9.3).
  bool get isLoop {
    final a = points.first, b = points.last;
    return geo.distanceMeters(a.latitude, a.longitude, b.latitude, b.longitude) <= kNavArriveM;
  }

  /// Der Punkt [alongM] Meter ab Start, auf die Linie geklemmt.
  LatLng pointAt(double alongM) {
    if (alongM <= 0) return points.first;
    if (alongM >= lengthM) return points.last;
    final i = _segmentAt(alongM);
    final seg = cumM[i + 1] - cumM[i];
    final t = seg <= 0 ? 0.0 : (alongM - cumM[i]) / seg;
    final a = points[i], b = points[i + 1];
    return LatLng(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t);
  }

  /// Die Linie geteilt bei [alongM]: das Gefahrene und der Rest, beide mit
  /// dem Punkt am Stand — so stoßen sie auf der Karte ohne Lücke an.
  (List<LatLng> done, List<LatLng> rest) splitAt(double alongM) {
    final at = pointAt(alongM);
    final done = <LatLng>[], rest = <LatLng>[at];
    for (var i = 0; i < points.length; i++) {
      (cumM[i] < alongM ? done : rest).add(points[i]);
    }
    done.add(at);
    return (done, rest);
  }

  /// Die Richtung der Linie bei [alongM], in Grad ab Norden — gemessen
  /// über [kNavHeadingLookM] voraus, nicht am einzelnen Abschnitt: Ein
  /// Anschluss von ein paar Metern zurück an den Weg drehte die Karte
  /// sonst auf den Kopf (im Flow-Test gefunden). Am Ende das letzte Stück.
  double bearingAt(double alongM) {
    final from = alongM.clamp(0.0, lengthM).toDouble();
    var a = pointAt(from), b = pointAt(from + kNavHeadingLookM);
    if (from + kNavHeadingLookM > lengthM) {
      a = pointAt(lengthM - kNavHeadingLookM);
      b = points.last;
    }
    return geo.bearingDegrees(a.latitude, a.longitude, b.latitude, b.longitude);
  }

  /// Der Abschnitt, in dem [alongM] liegt (Index seines Anfangs), ohne
  /// Abschnitte der Länge null.
  int _segmentAt(double alongM) {
    var lo = 0, hi = cumM.length - 2;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (cumM[mid] <= alongM) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    // Ein doppelter Punkt hat keine Richtung — der nächste echte Abschnitt.
    while (lo < cumM.length - 2 && cumM[lo + 1] - cumM[lo] <= 0) {
      lo++;
    }
    return lo;
  }
}

/// Die Projektion einer Position auf die Linie.
class RouteFix {
  const RouteFix({required this.alongM, required this.offM});

  /// Distanz ab Start bis zum Fußpunkt.
  final double alongM;

  /// Abstand der Position zur Linie.
  final double offM;
}

/// Projiziert [p] auf [route] und sucht zuerst im Fenster ab
/// [lastAlongM] (zurück [kNavBackSlackM], voraus [kNavAheadWindowM]).
/// Findet das Fenster nichts in [kNavOffRouteM], gilt die ganze Linie —
/// liegt auch dort nichts so nah, ist man abseits: Dann bleibt der Stand
/// des Fensters (kein Sprung auf die Rückfahrt), der Abstand aber ist der
/// zur ganzen Linie.
RouteFix routeProgress(NavRoute route, LatLng p, {double lastAlongM = 0}) {
  final window = _nearest(route, p, from: lastAlongM - kNavBackSlackM, to: lastAlongM + kNavAheadWindowM);
  if (window != null && window.offM <= kNavOffRouteM) return window;
  final all = _nearest(route, p, from: double.negativeInfinity, to: double.infinity)!;
  if (all.offM <= kNavOffRouteM || window == null) return all;
  return RouteFix(alongM: window.alongM, offM: all.offM);
}

RouteFix? _nearest(NavRoute route, LatLng p, {required double from, required double to}) {
  // Flach um die Position: auf ein paar Kilometer genau genug, und die
  // Abstände, um die es geht, sind Meter.
  const r = 6371000.0;
  final kLat = r * math.pi / 180;
  final kLng = kLat * math.cos(p.latitude * math.pi / 180);
  double x(LatLng q) => (q.longitude - p.longitude) * kLng;
  double y(LatLng q) => (q.latitude - p.latitude) * kLat;

  RouteFix? best;
  final pts = route.points, cum = route.cumM;
  for (var i = 0; i < pts.length - 1; i++) {
    if (cum[i + 1] < from || cum[i] > to) continue;
    final ax = x(pts[i]), ay = y(pts[i]);
    final dx = x(pts[i + 1]) - ax, dy = y(pts[i + 1]) - ay;
    final len2 = dx * dx + dy * dy;
    var t = len2 <= 0 ? 0.0 : -(ax * dx + ay * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final along = cum[i] + t * (cum[i + 1] - cum[i]);
    if (along < from || along > to) continue;
    final cx = ax + t * dx, cy = ay + t * dy;
    final off = math.sqrt(cx * cx + cy * cy);
    if (best == null || off < best.offM) best = RouteFix(alongM: along, offM: off);
  }
  return best;
}

/// Höhenmeter bergauf ab [alongM] — aus den Proben eines Profils entlang
/// der Linie ([distM]/[eleM], dieselbe Hysterese wie im Ergebnis), bis
/// [untilM] (ohne: bis zum Ende). Null ohne Profil.
double? climbAfter(List<double>? distM, List<double>? eleM, double alongM, {double? untilM}) =>
    climbBetween(distM, eleM, alongM, untilM ?? double.infinity)?.gain;

/// Anstieg und Abstieg zwischen [fromM] und [toM] auf dem Profil. Null
/// ohne Profil.
({double gain, double loss})? climbBetween(List<double>? distM, List<double>? eleM, double fromM, double toM) {
  final part = profilePart(distM, eleM, fromM, toM);
  if (part == null) return null;
  if (part.length < 2) return (gain: 0, loss: 0);
  final (gain, loss) = hysteresisClimb(part, kClimbHysteresisM);
  return (gain: gain, loss: loss);
}

/// Die Höhen des Profils zwischen [fromM] und [toM], an beiden Enden
/// zwischen den Proben gelesen. Null ohne Profil, leer außerhalb.
List<double>? profilePart(List<double>? distM, List<double>? eleM, double fromM, double toM) {
  if (distM == null || eleM == null || distM.length < 2 || distM.length != eleM.length) return null;
  if (fromM >= distM.last || toM <= fromM) return const [];
  double at(double m) {
    for (var i = 1; i < distM.length; i++) {
      if (distM[i] >= m) {
        final span = distM[i] - distM[i - 1];
        final t = span <= 0 ? 0.0 : ((m - distM[i - 1]) / span).clamp(0.0, 1.0);
        return eleM[i - 1] + (eleM[i] - eleM[i - 1]) * t;
      }
    }
    return eleM.last;
  }

  final out = <double>[at(fromM)];
  for (var i = 0; i < distM.length; i++) {
    if (distM[i] <= fromM || distM[i] >= toM) continue;
    out.add(eleM[i]);
  }
  out.add(toM >= distM.last ? eleM.last : at(toM));
  return out;
}

/// Ab dieser Steigung heißt ein Stück „Rampe" (Entwurf 2026-10-12: orange
/// ab 12 %).
const kNavRampGrade = 0.12;

/// Die erste Rampe voraus zwischen [fromM] und [toM]: ihre Steigung und
/// wie weit sie entfernt beginnt. Null ohne Profil oder ohne Rampe.
({double grade, double inM})? rampAhead(List<double>? distM, List<double>? eleM, double fromM, double toM) {
  if (distM == null || eleM == null || distM.length < 2 || distM.length != eleM.length) return null;
  for (var i = 1; i < distM.length; i++) {
    if (distM[i] <= fromM || distM[i - 1] >= toM) continue;
    final span = distM[i] - distM[i - 1];
    if (span <= 0) continue;
    final grade = (eleM[i] - eleM[i - 1]) / span;
    if (grade >= kNavRampGrade) return (grade: grade, inM: math.max(0.0, distM[i - 1] - fromM));
  }
  return null;
}

/// Was die Folgeansicht zeigt — der Stand nach einem Fix.
class NavState {
  const NavState({
    required this.alongM,
    required this.remainingM,
    required this.offM,
    required this.offRoute,
    required this.arrived,
    required this.headingDeg,
    required this.position,
    required this.rejoin,
    this.moving = false,
  });

  final double alongM;
  final double remainingM;
  final double offM;

  /// Abseits — erst nach [kNavOffRouteFixes] Fixen in Folge.
  final bool offRoute;
  final bool arrived;

  /// Wohin die Karte zeigt, in Grad ab Norden.
  final double headingDeg;
  final LatLng position;

  /// Der Punkt der Linie voraus, auf den der Pfeil abseits zeigt.
  final LatLng rejoin;

  /// In Fahrt (ab [kNavHeadingMinSpeedMps]) — am Trailkopf heißt stehen
  /// „am Kopf", rollen „auf dem Trail" (9.9).
  final bool moving;
}

/// Führt den Stand von Fix zu Fix: Fenster, Zähler für „abseits", der
/// letzte gültige Kurs. Eine Instanz je Navigation.
class NavTracker {
  /// [startAlongM]: wo der Stand anfängt — „zuletzt navigiert" geht dort
  /// weiter, wo die Navigation endete, sonst spränge eine Runde hin und
  /// zurück womöglich auf die Hinfahrt.
  NavTracker(this.route, {double startAlongM = 0}) : _along = startAlongM.clamp(0, route.lengthM).toDouble();

  final NavRoute route;
  double _along;
  int _offCount = 0;
  double? _heading;
  bool _arrived = false;

  /// [headingDeg] und [speedMps] wie vom GPS (negativ = unbekannt). Der
  /// Kurs gilt erst ab [kNavHeadingMinSpeedMps]; vorher und ohne Kurs die
  /// Richtung der Linie am Stand.
  NavState update(LatLng p, {double? headingDeg, double? speedMps}) {
    final fix = routeProgress(route, p, lastAlongM: _along);
    _along = fix.alongM;
    _offCount = fix.offM > kNavOffRouteM ? _offCount + 1 : 0;
    final moving = speedMps != null && speedMps >= kNavHeadingMinSpeedMps;
    if (moving && headingDeg != null && headingDeg >= 0 && headingDeg.isFinite) {
      _heading = headingDeg % 360;
    }
    final remaining = math.max(0.0, route.lengthM - _along);
    final end = route.points.last;
    final nearEnd = geo.distanceMeters(p.latitude, p.longitude, end.latitude, end.longitude) <= kNavArriveM;
    // Bei einer Runde liegt der Start am Ziel: angekommen erst, wenn der
    // Stand auf dem letzten Stück ist.
    _arrived = _arrived ||
        (fix.offM <= kNavOffRouteM && remaining <= kNavArriveM) ||
        (nearEnd && (!route.isLoop || _along >= route.lengthM / 2));
    return NavState(
      alongM: _along,
      remainingM: remaining,
      offM: fix.offM,
      offRoute: _offCount >= kNavOffRouteFixes,
      arrived: _arrived,
      headingDeg: _heading ?? route.bearingAt(_along),
      position: p,
      rejoin: route.pointAt(_along + kNavRejoinAheadM),
      moving: moving,
    );
  }
}

/// Wohin die Kamera muss, damit [position] im unteren Drittel einer
/// Fläche von [heightPx] steht, wenn die Karte nach [bearingDeg] zeigt:
/// die Mitte ein Sechstel der Höhe VORAUS (256er-Web-Mercator) — oder
/// [aheadPx], wo die Fläche anders geteilt ist (Bild-im-Bild, #415).
LatLng followCenter(LatLng position, double bearingDeg, double zoom, double heightPx, {double? aheadPx}) {
  final mPerPx = 156543.03392 * math.cos(position.latitude * math.pi / 180) / math.pow(2, zoom);
  final ahead = (aheadPx ?? heightPx / 6) * mPerPx;
  if (ahead == 0 || ahead.isNaN) return position;
  // Negativ: die Mitte hinter der Position (sie steht dann darüber).
  return const Distance().offset(position, ahead.abs(), ahead > 0 ? bearingDeg : bearingDeg + 180);
}

/// So weit vor dem Trailkopf beginnt „am Trailkopf" (9.9) …
const kNavHeadBeforeM = 100.0;

/// … und so weit dahinter endet es, solange man steht.
const kNavHeadAfterM = 30.0;

/// Was die Folgeansicht gerade fragt (9.9): die Anfahrt zum nächsten
/// Trail (oder zum Ziel), der Moment am Trailkopf, der Trail selbst,
/// angekommen.
enum NavPhaseKind { approach, atHead, onTrail, arrived }

/// Der Abschnitt, in dem man ist, mit den Zahlen dazu.
class NavPhase {
  const NavPhase({
    required this.kind,
    this.section,
    required this.distM,
    this.climbM,
    this.lossM,
    this.ramp,
  });

  final NavPhaseKind kind;

  /// Der Trail der Phase: bei der Anfahrt der nächste (null heißt: das
  /// Ziel), am Kopf und auf dem Trail dieser.
  final NavTrailSection? section;

  /// Anfahrt: Meter bis zum Trailkopf bzw. Ziel. Auf dem Trail: der Rest
  /// des Trails. Sonst 0.
  final double distM;

  /// Anfahrt: Höhenmeter bergauf bis dorthin; null ohne Profil.
  final double? climbM;

  /// Auf dem Trail: Höhenmeter bergab, die noch kommen; null ohne Profil.
  final double? lossM;

  /// Anfahrt: die erste Rampe voraus.
  final ({double grade, double inM})? ramp;

  bool get toGoal => kind == NavPhaseKind.approach && section == null;
}

/// Die Phase zum Stand [state] auf einer Route der Länge [routeLengthM]
/// mit [sections]; [climbDistM]/[climbEleM] das Profil entlang der Linie.
NavPhase navPhaseOf(
  NavState state,
  NavSections sections, {
  required double routeLengthM,
  List<double>? climbDistM,
  List<double>? climbEleM,
}) {
  final along = state.alongM;
  if (state.arrived) {
    // Am Ziel ein Trail (Weg zum Trailkopf): der Moment vor dem Droppen.
    final head = sections.trails.where((t) => t.beyondRoute).firstOrNull;
    return NavPhase(kind: head == null ? NavPhaseKind.arrived : NavPhaseKind.atHead, section: head, distM: 0);
  }
  final on = sections.at(along);
  if (on != null && on.lengthM > 0) {
    final nearHead = along <= on.startM + kNavHeadAfterM && !state.moving;
    if (!nearHead) {
      return NavPhase(
        kind: NavPhaseKind.onTrail,
        section: on,
        distM: math.max(0.0, on.endM - along),
        lossM: climbBetween(climbDistM, climbEleM, along, on.endM)?.loss,
      );
    }
  }
  final next = sections.nextFrom(along, slackM: on == null ? 0 : kNavHeadAfterM);
  if (next != null && !next.beyondRoute && along >= next.startM - kNavHeadBeforeM && !state.moving) {
    return NavPhase(kind: NavPhaseKind.atHead, section: next, distM: math.max(0.0, next.startM - along));
  }
  final toM = next?.startM ?? routeLengthM;
  final dist = math.max(0.0, toM - along);
  return NavPhase(
    kind: NavPhaseKind.approach,
    section: next,
    distM: dist,
    climbM: climbAfter(climbDistM, climbEleM, along, untilM: toM),
    ramp: rampAhead(climbDistM, climbEleM, along, toM),
  );
}

/// So viel eines Trails muss zwischen Einfahrt und Ende gefahren sein,
/// damit sein Ende eine Bilanz bekommt (9.9) — wer mitten auf dem Trail
/// die Navigation startet, hat ihn nicht „geschafft".
const kNavTrailDoneShare = 0.5;

/// So nah am Ende gilt der Trail als zu Ende gefahren (die Fixe kommen
/// je Sekunde, das letzte Stück fehlt sonst oft).
const kNavTrailEndM = 10.0;

/// So lange steht das Blatt „Trail geschafft", dann geht es von selbst.
const kNavTrailDoneLinger = Duration(seconds: 20);

/// Die Bilanz eines gefahrenen Trails (9.9, ohne Sensoren — die kommen
/// mit #36).
class NavTrailDone {
  const NavTrailDone({
    required this.section,
    required this.duration,
    required this.endedAt,
    this.maxSpeedMps,
    this.lossM,
  });

  final NavTrailSection section;

  /// Von der Einfahrt bis zum Ende.
  final Duration duration;

  /// Wann das Ende kam — die Zeit der Zustandsmeldung.
  final DateTime endedAt;

  /// Das höchste Tempo der Fixe auf dem Trail; null, wenn keiner eines
  /// trug.
  final double? maxSpeedMps;

  /// Höhenmeter bergab auf dem gefahrenen Stück; null ohne Profil und
  /// ohne Wert des Trails.
  final double? lossM;
}

/// Folgt der Fahrt über die Trails einer Route und meldet das Ende eines
/// Trails, der wirklich gefahren wurde. Eine Instanz je Navigation.
class NavTrailWatch {
  NavTrailSection? _section;
  DateTime? _enteredAt;
  double _enteredAlongM = 0;
  double? _maxSpeed;

  /// Seit wann man auf dem laufenden Trail ist (Zeit des Fixes); null
  /// abseits — die Trail-Werte der Folgeansicht zählen ab hier (#36).
  DateTime? get enteredAt => _section == null ? null : _enteredAt;

  /// Ein neuer Stand zur Zeit [at]; die Bilanz, wenn damit ein Trail zu
  /// Ende ist, sonst null.
  NavTrailDone? update(
    NavState state,
    NavSections sections,
    DateTime at, {
    double? speedMps,
    List<double>? climbDistM,
    List<double>? climbEleM,
  }) {
    final along = state.alongM;
    final run = _section;
    if (run != null && along < run.startM) {
      // Zurück vor den Kopf: Das zählt nicht als Fahrt.
      _section = null;
    } else if (run != null && (along >= run.endM - kNavTrailEndM || state.arrived || sections.at(along) != run)) {
      _section = null;
      final from = _enteredAlongM;
      final to = math.min(along, run.endM);
      if (to - from < run.lengthM * kNavTrailDoneShare) return null;
      return NavTrailDone(
        section: run,
        duration: at.difference(_enteredAt!),
        endedAt: at,
        maxSpeedMps: _maxSpeed,
        lossM: climbBetween(climbDistM, climbEleM, from, to)?.loss ?? run.lossM,
      );
    }
    final on = sections.at(along);
    if (_section == null && on != null && on.lengthM > 0 && !state.arrived && along < on.endM - kNavTrailEndM) {
      _section = on;
      _enteredAt = at;
      _enteredAlongM = along;
      _maxSpeed = null;
    }
    if (_section != null && speedMps != null && speedMps >= 0 && speedMps.isFinite) {
      _maxSpeed = math.max(_maxSpeed ?? 0, speedMps);
    }
    return null;
  }
}
