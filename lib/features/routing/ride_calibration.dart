// Die Kalibrierung des Zeitmodells aus den eigenen Fahrten (#158 Schritt
// 6, Konzept-Routing 2.1): Steigrate je Wegklasse und Flachgeschwindig-
// keit, je Profil, aus Zeit und GPS-Höhe der aufgezeichneten Punkte.
// Spiegel von `ride_sections` und `class_mix_along` in
// `tool/route_measure.py` (Modus `rides`, die Kalibrierungs-Hälfte):
// Aufstiegsabschnitte ab 100 hm am Stück aus den median-geglätteten
// Höhen (Fenster 7, Ende nach 15 m Abfall), je Abschnitt die dominante
// Wegklasse unter der Spur (alle 5 m der nächste Weg in 15 m, sonst
// „abseits"), die Rate hm/h nur für Abschnitte über fünf Minuten, der
// Median je Klassengruppe. Dazu, über das Werkzeug hinaus: die
// Flachgeschwindigkeit aus Stücken zwischen den Aufstiegen, die kaum
// Höhe machen und auf Forstweg oder Straße liegen.
//
// Drei Dinge, die man wissen muss:
// - **Nie aus Fahrten anderer**, nie vom Server: Es rechnet nur, was auf
//   dem Gerät liegt (Konzept 12).
// - **Eine Zahl ersetzt die Vorgabe erst ab [kCalibMinSections]
//   Abschnitten** und nur in einer plausiblen Spanne — eine einzelne
//   Fahrt mit hängendem GPS wäre sonst die neue Wahrheit.
// - **Fahrten ohne Profil (vor 0.70.0) lernen nichts**; welche Fahrt zu
//   welchem Profil gehört, steht in ihrem Kopf (`Ride.profile`).
// Rein: keine Widgets, kein Riverpod, keine Platte.
import 'dart:convert';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../rides/ride_split.dart' show smoothElevation;
import '../rides/ride_track.dart';
import 'graph_input.dart' show GraphJob;
import 'loop_planner.dart' show LoopSearchCache;
import 'road_graph.dart';
import 'route_profile.dart';

/// Spiegel der Werkzeug-Vorgaben: `min_gain`, `drop_end`, `window`.
const kCalibMinGainM = 100.0;
const kCalibDropEndM = 15.0;
const kCalibWindow = 7;

/// Höchstens so viele Fahrten ordnet EIN Lernlauf ein (#356 PR 9,
/// Konzept-Routing 10.6), die jüngsten zuerst: Jede Fahrt liest ihre
/// Kacheln und baut einen Graphen; mit 100 Fahrten stand der Knopf
/// minutenlang. Was älter ist, hat das Profil ohnehin schon gelernt, als
/// es neu war — und der Satz danach sagt, wie viele außen vor blieben.
const kCalibMaxRides = 20;

/// Ein Abschnitt zählt als Rate erst ab dieser Dauer (Werkzeug: 300 s).
const kCalibMinSectionS = 300.0;

/// Der nächste Weg in dieser Entfernung ordnet einen Punkt ein (Werkzeug:
/// `corridor=15.0`), abgetastet alle [kCalibSampleM].
const kCalibCorridorM = 15.0;
const kCalibSampleM = 5.0;

/// So viele Abschnitte braucht eine Zahl, bevor sie die Vorgabe ersetzt.
const kCalibMinSections = 3;

/// Flache Stücke: mindestens so lang, Anstieg UND Abstieg unter diesem
/// Anteil der Länge — dann ist die Geschwindigkeit eine Flachgeschwindigkeit.
const kCalibFlatMinM = 500.0;
const kCalibFlatMaxGrade = 0.02;

/// Plausible Spannen; was draußen liegt, ist ein Messfehler, kein Fahrer.
const kCalibClimbRange = (150.0, 1500.0);
const kCalibFlatRange = (8.0, 30.0);

/// Ein Aufstieg: von Index [start] bis zum Gipfel [top], [gainM] Höhe.
typedef AscentSection = ({int start, int top, double gainM});

/// Die Aufstiegsabschnitte in [ele] — Spiegel von `ride_sections`.
List<AscentSection> ascentSections(List<double> ele,
    {double minGainM = kCalibMinGainM, double dropEndM = kCalibDropEndM, int window = kCalibWindow}) {
  if (ele.length < window) return const [];
  final sm = smoothElevation(ele, window);
  final out = <AscentSection>[];
  var i = 0;
  while (i < sm.length - 1) {
    if (sm[i + 1] <= sm[i]) {
      i++;
      continue;
    }
    final start = i;
    var top = sm[i], topI = i;
    var j = i + 1;
    while (j < sm.length) {
      if (sm[j] > top) {
        top = sm[j];
        topI = j;
      } else if (top - sm[j] >= dropEndM) {
        break;
      }
      j++;
    }
    final gain = top - sm[start];
    if (gain >= minGainM) out.add((start: start, top: topI, gainM: gain));
    i = j > i ? math.max(topI, j) : i + 1;
  }
  return out;
}

/// Länge je nächster Wegklasse entlang [pts] (null = abseits) — Spiegel
/// von `class_mix_along`: alle [kCalibSampleM] eine Probe, der nächste
/// Weg in [kCalibCorridorM].
Map<WayClass?, double> classMixAlong(RoadGraph g, List<LatLng> pts) {
  final mix = <WayClass?, double>{};
  if (pts.length < 2) return mix;
  final xy = g.proj.line(pts);
  var carry = 0.0;
  for (var i = 1; i < xy.length; i++) {
    final a = xy[i - 1], b = xy[i];
    final seg = a.distanceTo(b);
    var d = carry;
    while (d <= seg) {
      final t = seg == 0 ? 0.0 : d / seg;
      final p = g.proj.latLng(math.Point(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y)));
      final hit = g.nearest(p, kCalibCorridorM);
      final cls = hit == null ? null : g.edges[hit.edge].cls;
      mix[cls] = (mix[cls] ?? 0) + kCalibSampleM;
      d += kCalibSampleM;
    }
    carry = d - seg;
  }
  return mix;
}

/// Welche Zahl des Profils eine Klasse kalibriert.
enum CalibGroup { track, path, push }

CalibGroup? calibGroupOf(WayClass? cls) => switch (cls) {
      null => null,
      WayClass.stufen => CalibGroup.push,
      WayClass.wanderweg || WayClass.fussweg => CalibGroup.path,
      _ => CalibGroup.track,
    };

/// Eine Messung aus einer Fahrt: ein Aufstieg (Rate) oder ein flaches
/// Stück (Geschwindigkeit), schon einer Gruppe zugeordnet.
class CalibSample {
  const CalibSample.climb(this.group, this.value) : flat = false;
  const CalibSample.flat(this.value)
      : group = CalibGroup.track,
        flat = true;

  final CalibGroup group;

  /// hm/h beim Aufstieg, km/h im Flachen.
  final double value;
  final bool flat;
}

/// Alle Messungen einer Fahrt. [g] ordnet die Wegklasse zu; ohne Graphen
/// (kein Bereich) gibt es keine Zuordnung und damit keine Messung — eine
/// Rate ohne Klasse kalibrierte die falsche Zahl.
List<CalibSample> calibSamplesOf(Ride ride, RoadGraph? g) {
  final pts = ride.points;
  if (g == null || pts.length < kCalibWindow) return const [];
  final ele = [for (final p in pts) p.altM];
  if (ele.any((e) => e == null)) return const [];
  final heights = ele.cast<double>();
  final out = <CalibSample>[];
  final sections = ascentSections(heights);
  for (final s in sections) {
    final secs = pts[s.top].at.difference(pts[s.start].at).inSeconds.toDouble();
    if (secs <= kCalibMinSectionS) continue;
    final mix = classMixAlong(g, [for (var i = s.start; i <= s.top; i++) LatLng(pts[i].lat, pts[i].lng)]);
    final group = calibGroupOf(_dominant(mix));
    if (group == null) continue;
    out.add(CalibSample.climb(group, s.gainM / (secs / 3600)));
  }
  // Flache Stücke zwischen den Aufstiegen.
  final sm = smoothElevation(heights, kCalibWindow);
  final bounds = <int>[0, for (final s in sections) ...[s.start, s.top], pts.length - 1];
  for (var k = 0; k + 1 < bounds.length; k += 2) {
    final a = bounds[k], b = bounds[k + 1];
    if (b - a < 2) continue;
    var length = 0.0, gain = 0.0, loss = 0.0;
    for (var i = a + 1; i <= b; i++) {
      length += g.proj.xy(LatLng(pts[i - 1].lat, pts[i - 1].lng)).distanceTo(g.proj.xy(LatLng(pts[i].lat, pts[i].lng)));
      final d = sm[i] - sm[i - 1];
      if (d > 0) {
        gain += d;
      } else {
        loss -= d;
      }
    }
    if (length < kCalibFlatMinM || gain > kCalibFlatMaxGrade * length || loss > kCalibFlatMaxGrade * length) continue;
    final secs = pts[b].at.difference(pts[a].at).inSeconds.toDouble();
    if (secs <= 60) continue;
    final mix = classMixAlong(g, [for (var i = a; i <= b; i++) LatLng(pts[i].lat, pts[i].lng)]);
    if (calibGroupOf(_dominant(mix)) != CalibGroup.track) continue;
    out.add(CalibSample.flat(length / 1000 / (secs / 3600)));
  }
  return out;
}

/// Das Einordnen EINER Fahrt auf dem Graphen drüben (#356 PR 9): hinüber
/// geht die Fahrt (Punkte mit Zeit und Höhe), zurück kommen ihre Messungen.
class CalibJob implements GraphJob<List<CalibSample>> {
  const CalibJob(this.ride);

  final Ride ride;

  @override
  List<CalibSample> runOn(RoadGraph g, LoopSearchCache cache) => calibSamplesOf(ride, g);
}

WayClass? _dominant(Map<WayClass?, double> mix) {
  WayClass? best;
  var bestLen = -1.0;
  for (final e in mix.entries) {
    if (e.value > bestLen) {
      bestLen = e.value;
      best = e.key;
    }
  }
  return best;
}

/// Die gelernten Werte EINES Profils. Null heißt: die Vorgabe gilt.
class RiderCalibration {
  const RiderCalibration({
    this.climbTrackMPerH,
    this.climbPathMPerH,
    this.pushRateMPerH,
    this.vFlatKmh,
    this.rides = 0,
    this.sections = 0,
    this.at,
  });

  static const none = RiderCalibration();

  final double? climbTrackMPerH;
  final double? climbPathMPerH;
  final double? pushRateMPerH;
  final double? vFlatKmh;

  /// Wie viele Fahrten und Abschnitte dahinterstehen — die Anzeige nennt
  /// sie („aus 14 Fahrten").
  final int rides;
  final int sections;
  final DateTime? at;

  bool get isEmpty => climbTrackMPerH == null && climbPathMPerH == null && pushRateMPerH == null && vFlatKmh == null;

  Map<String, dynamic> toJson() => {
        if (climbTrackMPerH != null) 'track': climbTrackMPerH,
        if (climbPathMPerH != null) 'path': climbPathMPerH,
        if (pushRateMPerH != null) 'push': pushRateMPerH,
        if (vFlatKmh != null) 'flat': vFlatKmh,
        'rides': rides,
        'sections': sections,
        if (at != null) 'at': at!.toUtc().toIso8601String(),
      };

  /// Was außerhalb der plausiblen Spanne steht, gilt als nicht gelernt
  /// (#356): Eine gespeicherte 0 teilte im Zeitmodell durch null, die
  /// Zeit wurde unendlich, und `.round()` warf beim Bauen des Blatts.
  static RiderCalibration fromJson(Map<String, dynamic> json) => RiderCalibration(
        climbTrackMPerH: _inRange(json['track'], kCalibClimbRange),
        climbPathMPerH: _inRange(json['path'], kCalibClimbRange),
        pushRateMPerH: _inRange(json['push'], kCalibClimbRange),
        vFlatKmh: _inRange(json['flat'], kCalibFlatRange),
        rides: (json['rides'] as num?)?.toInt() ?? 0,
        sections: (json['sections'] as num?)?.toInt() ?? 0,
        at: DateTime.tryParse(json['at'] as String? ?? ''),
      );

  static double? _inRange(Object? raw, (double, double) range) {
    if (raw is! num) return null;
    final v = raw.toDouble();
    return v >= range.$1 && v <= range.$2 ? v : null;
  }
}

/// Rechnet aus den Messungen eines Profils die gelernten Werte: Median je
/// Gruppe, nur ab [kCalibMinSections] Messungen und in der plausiblen
/// Spanne; [rides] ist die Zahl der Fahrten, die Messungen geliefert haben.
RiderCalibration calibrateFrom(List<CalibSample> samples, {required int rides, DateTime? now}) {
  double? median(Iterable<double> values, (double, double) range) {
    final v = values.where((x) => x >= range.$1 && x <= range.$2).toList()..sort();
    if (v.length < kCalibMinSections) return null;
    final m = v.length ~/ 2;
    return v.length.isOdd ? v[m] : (v[m - 1] + v[m]) / 2;
  }

  Iterable<double> climbs(CalibGroup g) => samples.where((s) => !s.flat && s.group == g).map((s) => s.value);
  return RiderCalibration(
    climbTrackMPerH: median(climbs(CalibGroup.track), kCalibClimbRange),
    climbPathMPerH: median(climbs(CalibGroup.path), kCalibClimbRange),
    pushRateMPerH: median(climbs(CalibGroup.push), kCalibClimbRange),
    vFlatKmh: median(samples.where((s) => s.flat).map((s) => s.value), kCalibFlatRange),
    rides: rides,
    sections: samples.where((s) => !s.flat).length,
    at: now ?? DateTime.now().toUtc(),
  );
}

/// Die gelernten Werte beider Profile, als EINE Zeichenkette für
/// `Settings.riderCalibration`. Unlesbares heißt: nichts gelernt.
class RiderCalibrations {
  const RiderCalibrations([this._byProfile = const {}]);

  final Map<RiderProfile, RiderCalibration> _byProfile;

  RiderCalibration of(RiderProfile p) => _byProfile[p] ?? RiderCalibration.none;

  RiderCalibrations withProfile(RiderProfile p, RiderCalibration c) =>
      RiderCalibrations({..._byProfile, p: c});

  RiderCalibrations without(RiderProfile p) => RiderCalibrations({..._byProfile}..remove(p));

  bool get isEmpty => _byProfile.values.every((c) => c.isEmpty);

  String encode() => jsonEncode({for (final e in _byProfile.entries) e.key.name: e.value.toJson()});

  static RiderCalibrations parse(String? raw) {
    if (raw == null || raw.isEmpty) return const RiderCalibrations();
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return const RiderCalibrations();
      final out = <RiderProfile, RiderCalibration>{};
      for (final p in RiderProfile.values) {
        final entry = json[p.name];
        if (entry is Map<String, dynamic>) out[p] = RiderCalibration.fromJson(entry);
      }
      return RiderCalibrations(out);
    } catch (_) {
      // Ein kaputter Eintrag ist kein Grund für einen Bericht je Start:
      // Die Vorgaben gelten, bis jemand neu lernt.
      return const RiderCalibrations();
    }
  }
}

/// Das Profil mit seinen gelernten Werten — was fehlt, ist die Vorgabe.
class CalibratedRider implements RiderParams {
  const CalibratedRider(this.profile, this.calibration);

  @override
  final RiderProfile profile;
  final RiderCalibration calibration;

  @override
  RoutePrefs get prefs => const RoutePrefs();

  @override
  double get climbTrackMPerH => calibration.climbTrackMPerH ?? profile.climbTrackMPerH;
  @override
  double get climbPathMPerH => calibration.climbPathMPerH ?? profile.climbPathMPerH;
  @override
  double get pushRateMPerH => calibration.pushRateMPerH ?? profile.pushRateMPerH;
  @override
  double get vFlatKmh => calibration.vFlatKmh ?? profile.vFlatKmh;
  @override
  double get vPathUpKmh => profile.vPathUpKmh;
  @override
  double get vPushKmh => profile.vPushKmh;
  @override
  double get vDownKmh => profile.vDownKmh;
  @override
  double get pathUpFactor => profile.pathUpFactor;
  @override
  double get pathDownFactor => profile.pathDownFactor;
  @override
  double get budgetClimbM => profile.budgetClimbM;
}
