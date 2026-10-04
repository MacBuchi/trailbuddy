import 'dart:math' as math;

import 'gpx.dart';

/// Erdradius für Haversine, in Metern.
const double kEarthRadiusM = 6371000.0;

/// Ab hier ist eine Datei eine FAHRT, kein Trail (Konzept 5.2, gemessen
/// in docs/trail-abgleich-messung.md: alpine Trails sind 3 bis 8 km lang,
/// Fahrten beginnen im Bestand bei 8 km).
const double kTrailMaxLengthM = 8000;

/// Kürzer ist eine Zufahrt oder ein Fragment (Konzept 4.2).
const double kTrailMinLengthM = 50;

/// Schneller fährt kein Fahrrad im Median: eine gezeichnete Route mit
/// erfundenen Zeiten. Dieselbe Grenze wie in tool/trail_match.py.
const double kPlannedSpeedKmh = 60;

/// Was aus einer Spur wird, wenn sie als Datei hereinkommt.
enum TrackKind {
  /// Kurz und überwiegend bergab: direkt ein Trail-Kandidat.
  trail,

  /// Alles andere: eine Fahrt, die zerlegt werden muss (Phase 2) —
  /// in Phase 1 kann sie als Ganzes NICHT beigesteuert werden.
  ride,

  /// Unter der Mindestlänge: kein Trail.
  fragment,
}

/// Quelle einer Aufzeichnung, wie sie die Datenbank kennt.
enum RecordingSource { app, import, planned }

double haversineM(double lat1, double lon1, double lat2, double lon2) {
  final p1 = lat1 * math.pi / 180;
  final p2 = lat2 * math.pi / 180;
  final dp = p2 - p1;
  final dl = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dp / 2) * math.sin(dp / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return 2 * kEarthRadiusM * math.asin(math.sqrt(a));
}

double trackLengthM(List<TrackPoint> pts) {
  var sum = 0.0;
  for (var i = 1; i < pts.length; i++) {
    sum += haversineM(pts[i - 1].lat, pts[i - 1].lon, pts[i].lat, pts[i].lon);
  }
  return sum;
}

/// Ab dieser Änderung zählt eine Höhe als Anstieg oder Abstieg
/// (Hysterese). GPS- und Barometerhöhen rauschen: Wer jeden Schritt
/// aufsummiert, findet auf einem reinen Downhill Dutzende Meter „bergauf",
/// die niemand getreten hat. Gemessen mit `tool/elevation_measure.py` an
/// echten Aufzeichnungen (docs/trail-abgleich-messung.md, Abschnitt
/// Höhen): Ab 3 m fällt der Anstieg auf Trails im Median auf 0 und der
/// Abstieg auf das Nettogefälle, Fahrten behalten 88 % ihres Anstiegs
/// (5 m: 82 %). Werkzeug und Dart im selben PR ändern, die Testvektoren
/// sind dieselben.
const double kElevationThresholdM = 3;

/// Senkrechte Toleranz der Vereinfachung vor dem Hochladen: Ein Punkt
/// bleibt auch, wenn seine Höhe so weit neben der Geraden liegt. Ohne sie
/// verlöre ein gerades, aber welliges Stück seine Wellen — die Linie
/// bliebe richtig, die Höhenmeter nicht. Gemessen wie oben: Bei 2 m
/// weichen Anstieg und Abstieg im p90 um 2 m ab (ohne: 3 m), und der
/// Wert liegt unter der Schwelle — eine gezählte Welle geht nicht verloren.
const double kSimplifyVerticalM = 2;

/// Über diese Strecke wird das steilste Stück gemessen. Von Punkt zu
/// Punkt wäre es Rauschen: 3 m Höhe auf 5 m Weg sind „60 %".
const double kSteepestWindowM = 50;

/// Die Höhen einer Spur — nur wenn JEDER Punkt eine plausible trägt,
/// sonst null. Eine halbe Höhenreihe ergäbe eine erfundene Zahl, und
/// ein Gerät, das „keine Höhe" als −32768 schreibt, soll die Aufzeichnung
/// nicht an `trail_recordings_ele_check` scheitern lassen: lieber ohne
/// Höhen beigesteuert als gar nicht. Dieselben Grenzen wie in der RPC.
List<double>? trackElevations(List<TrackPoint> pts) {
  if (pts.isEmpty) return null;
  final out = <double>[];
  for (final p in pts) {
    final e = p.ele;
    if (e == null || e < kMinElevationM || e > kMaxElevationM) return null;
    out.add(e);
  }
  return out;
}

/// Plausible Höhen, wie `contribute_recording` sie annimmt.
const double kMinElevationM = -500;
const double kMaxElevationM = 9000;

/// Meter bergauf und bergab mit Hysterese: Eine Änderung zählt erst, wenn
/// sie [thresholdM] gegenüber der zuletzt gezählten Höhe erreicht. Der
/// Rest am Ende wird mitgebucht, deshalb ist `loss - gain` bei JEDER
/// Schwelle genau `ele.first - ele.last` — das Nettogefälle hängt nie an
/// der Schwelle, nur das Rauschen drumherum.
///
/// Spiegel von `gain_loss` in `tool/elevation_measure.py`.
({double gain, double loss}) gainLoss(List<double> ele, double thresholdM) {
  if (ele.length < 2) return (gain: 0, loss: 0);
  var ref = ele.first;
  var gain = 0.0;
  var loss = 0.0;
  for (final e in ele.skip(1)) {
    final d = e - ref;
    if (d > 0 && d >= thresholdM) {
      gain += d;
      ref = e;
    } else if (d < 0 && -d >= thresholdM) {
      loss -= d;
      ref = e;
    }
  }
  final rest = ele.last - ref;
  if (rest > 0) {
    gain += rest;
  } else {
    loss -= rest;
  }
  return (gain: gain, loss: loss);
}

/// (Anstieg, Abstieg) einer Spur, null ohne vollständige Höhen. Die
/// Vorgabe ist die Schwelle der Anzeige; die Importregel rechnet roh
/// ([classifyTrack]), so ist sie gemessen.
({double gain, double loss})? elevationGainLoss(List<TrackPoint> pts,
    {double thresholdM = kElevationThresholdM}) {
  final ele = trackElevations(pts);
  return ele == null ? null : gainLoss(ele, thresholdM);
}

/// Das steilste Gefälle in Prozent über mindestens [windowM] Meter
/// (Distanzen aufsteigend, je Punkt). Null, wenn die Strecke kürzer ist.
/// Ein Anstieg ergibt einen negativen Wert — auf einem Trail, der ganz
/// bergauf läuft, ist das die ehrliche Antwort.
///
/// Spiegel von `steepest` in `tool/elevation_measure.py`.
double? steepestDescentPct(List<double> distM, List<double> ele,
    {double windowM = kSteepestWindowM}) {
  double? best;
  var j = 0;
  for (var i = 0; i < distM.length; i++) {
    if (j < i) j = i;
    while (j < distM.length && distM[j] - distM[i] < windowM) {
      j++;
    }
    if (j >= distM.length) break;
    final g = (ele[i] - ele[j]) / (distM[j] - distM[i]) * 100;
    if (best == null || g > best) best = g;
  }
  return best;
}

/// Ohne verwertbare Zeiten oder mit Fahrradfremden Geschwindigkeiten:
/// eine gezeichnete Route, keine Fahrt (Entscheidung 2 im Konzept).
bool looksPlanned(List<TrackPoint> pts) {
  final stamps = pts.map((p) => p.time).whereType<DateTime>().toSet();
  if (stamps.length < 2) return true;
  final speeds = <double>[];
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1].time;
    final b = pts[i].time;
    if (a == null || b == null) continue;
    final dt = b.difference(a).inMilliseconds / 1000;
    if (dt <= 0) continue;
    final d = haversineM(pts[i - 1].lat, pts[i - 1].lon, pts[i].lat, pts[i].lon);
    speeds.add(d / dt * 3.6);
  }
  if (speeds.isEmpty) return true;
  speeds.sort();
  return speeds[speeds.length ~/ 2] > kPlannedSpeedKmh;
}

RecordingSource sourceOf(List<TrackPoint> pts) =>
    looksPlanned(pts) ? RecordingSource.planned : RecordingSource.import;

/// Die Importregel aus Konzept 5.2: kurz und überwiegend bergab ⇒ Trail.
/// Ohne Höhen entscheidet die Länge allein — lieber ein Trail zu viel im
/// Kandidatenblatt als eine Fahrt, die niemand zerlegen kann.
TrackKind classifyTrack(List<TrackPoint> pts) {
  final length = trackLengthM(pts);
  if (length < kTrailMinLengthM) return TrackKind.fragment;
  if (length >= kTrailMaxLengthM) return TrackKind.ride;
  // Roh (Schwelle 0): so ist die Regel an 584 Tracks gemessen.
  final el = elevationGainLoss(pts, thresholdM: 0);
  if (el == null) return TrackKind.trail;
  return el.loss > 2 * el.gain ? TrackKind.trail : TrackKind.ride;
}

/// Douglas-Peucker in Metern — damit ein 6 894-Punkte-Track nicht als
/// 14 000 Zahlen an die RPC geht. 3 m Toleranz liegt unter jedem
/// GPS-Rauschen und weit unter dem 15-m-Korridor des Abgleichs.
///
/// Tragen ALLE Punkte eine Höhe, zählt auch die senkrechte Abweichung
/// ([verticalToleranceM], gegen die Höhe an derselben Stelle der Sehne):
/// Ein Punkt bleibt, sobald er waagerecht ODER senkrecht zu weit
/// danebenliegt. Spiegel von `simplify_3d` in `tool/elevation_measure.py`.
List<TrackPoint> simplify(List<TrackPoint> pts,
    {double toleranceM = 3, double verticalToleranceM = kSimplifyVerticalM}) {
  if (pts.length <= 2) return List.of(pts);
  final withEle = pts.every((p) => p.ele != null);
  final keep = List<bool>.filled(pts.length, false);
  keep[0] = true;
  keep[pts.length - 1] = true;
  final stack = <(int, int)>[(0, pts.length - 1)];
  final lat0 = pts.first.lat * math.pi / 180;
  final kx = kEarthRadiusM * math.cos(lat0) * math.pi / 180;
  const ky = kEarthRadiusM * math.pi / 180;
  double x(TrackPoint p) => p.lon * kx;
  double y(TrackPoint p) => p.lat * ky;
  while (stack.isNotEmpty) {
    final (a, b) = stack.removeLast();
    if (b - a < 2) continue;
    final ax = x(pts[a]), ay = y(pts[a]), bx = x(pts[b]), by = y(pts[b]);
    final dx = bx - ax, dy = by - ay;
    final l2 = dx * dx + dy * dy;
    var worst = -1.0;
    var worstI = -1;
    for (var i = a + 1; i < b; i++) {
      final px = x(pts[i]), py = y(pts[i]);
      double d;
      var t = 0.0;
      if (l2 == 0) {
        d = math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay));
      } else {
        t = (((px - ax) * dx + (py - ay) * dy) / l2).clamp(0.0, 1.0);
        final cx = ax + t * dx, cy = ay + t * dy;
        d = math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
      }
      // Beide Abweichungen in Vielfachen ihrer Toleranz: > 1 heißt behalten.
      var score = d / toleranceM;
      if (withEle) {
        final ea = pts[a].ele!, eb = pts[b].ele!;
        final dv = (pts[i].ele! - (ea + t * (eb - ea))).abs();
        score = math.max(score, dv / verticalToleranceM);
      }
      if (score > worst) {
        worst = score;
        worstI = i;
      }
    }
    if (worst > 1) {
      keep[worstI] = true;
      stack.add((a, worstI));
      stack.add((worstI, b));
    }
  }
  return [for (var i = 0; i < pts.length; i++) if (keep[i]) pts[i]];
}

/// Flache Koordinatenliste [lon, lat, lon, lat, …] für die RPC.
List<double> flatCoords(List<TrackPoint> pts) =>
    [for (final p in pts) ...[p.lon, p.lat]];
