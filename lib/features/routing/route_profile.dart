// Das Fahrerprofil und die Wegklassen der Routing-Engine
// (docs/konzept-routing.md 2.1–2.4): zwei Profile — Bio-Bike und E-Bike
// — mit je eigenen Steigraten, Geschwindigkeiten, Aufschlägen und
// Budget-Vorgabe; je Wegklasse Aufschlag bergauf/bergab und ob sie als
// Wanderweg zählt; die Zeit einer Kante nach Munter-Muster (Strecke
// plus Höhe) und ihre Kosten (Zeit × Aufschlag).
//
// Zahl für Zahl der Spiegel von `PROFILES`, `CLASSES`, `classify`,
// `edge_time_s`, `edge_factor`, `edge_cost_s` und — seit #194 —
// `STEEP_*`, `steep_excess` und `steep_cost_s`, seit #188 auch
// `steep_weight`, `descent_cost_s` und der Vorlieben (`PREF_*`), seit
// #213 `WAY_*` und `way_cost_s` in
// `tool/route_measure.py` — das Werkzeug ist die Referenz, mit der die
// Engine gemessen wurde (docs/routing-messung.md), und
// `test/routing/route_profile_test.dart` hält die Zahlen beider Seiten
// zusammen. Wer hier eine Zahl ändert, ändert sie dort im selben PR.
//
// Rein: keine Widgets, kein Riverpod, keine Platte.

import 'dart:math' as math;

/// Die Zahlen, mit denen das Zeitmodell rechnet — das Profil mit seinen
/// Vorgaben ([RiderProfile]) oder das Profil mit gelernten Werten
/// (`CalibratedRider`, Schritt 6). Die Engine fragt nur diese Schnitt-
/// stelle; welches Profil dahintersteht, sagt [profile].
abstract interface class RiderParams {
  RiderProfile get profile;
  double get climbTrackMPerH;
  double get climbPathMPerH;
  double get pushRateMPerH;
  double get vFlatKmh;
  double get vPathUpKmh;
  double get vPushKmh;
  double get vDownKmh;
  double get pathUpFactor;
  double get pathDownFactor;
  double get budgetClimbM;

  /// Die Vorlieben des Fahrers (#188): Straßen, Wanderwege bergauf,
  /// steile Rampen — meiden oder egal. Ab Werk alles meiden.
  RoutePrefs get prefs;
}

/// Die Vorlieben fürs Routing (#188, Betreiber 2026-10-02: „meiden / egal
/// passt für die erste Version", aber „eher bestimmte
/// Bestrafungsfunktionen" statt nur der Zeit). Jede schaltet die STÄRKE
/// einer Strafkurve: meiden heißt der volle Aufschlag, egal ein Teil
/// davon ([kPrefAnyRoads] …) — nie null, sonst nähme die Route bei
/// gleicher Zeit eine Hauptstraße statt des Forstwegs.
class RoutePrefs {
  const RoutePrefs({this.avoidRoads = true, this.avoidHiking = true, this.avoidSteep = true});

  final bool avoidRoads;
  final bool avoidHiking;
  final bool avoidSteep;

  double get roadStrength => avoidRoads ? 1.0 : kPrefAnyRoads;
  double get hikingStrength => avoidHiking ? 1.0 : kPrefAnyHiking;
  double get steepStrength => avoidSteep ? 1.0 : kPrefAnySteep;

  RoutePrefs copyWith({bool? avoidRoads, bool? avoidHiking, bool? avoidSteep}) => RoutePrefs(
        avoidRoads: avoidRoads ?? this.avoidRoads,
        avoidHiking: avoidHiking ?? this.avoidHiking,
        avoidSteep: avoidSteep ?? this.avoidSteep,
      );

  @override
  bool operator ==(Object other) =>
      other is RoutePrefs &&
      other.avoidRoads == avoidRoads &&
      other.avoidHiking == avoidHiking &&
      other.avoidSteep == avoidSteep;

  @override
  int get hashCode => Object.hash(avoidRoads, avoidHiking, avoidSteep);
}

/// Was von einem Aufschlag bleibt, wenn er „egal" ist — `PREF_ANY` im
/// Werkzeug. Straßen und Wanderwege: der Teil über 1; steile Rampen: das
/// Gewicht.
const kPrefAnyRoads = 0.35;
const kPrefAnyHiking = 0.35;
const kPrefAnySteep = 0.3;

/// Die Profilwerte mit anderen Vorlieben — was der Planer und „Zum
/// Trailkopf" aus dem Profil (samt Kalibrierung) und den gemerkten
/// Schaltern machen.
extension RiderParamsPrefs on RiderParams {
  RiderParams withPrefs(RoutePrefs prefs) => prefs == this.prefs ? this : _PreferringRider(this, prefs);
}

class _PreferringRider implements RiderParams {
  const _PreferringRider(this._base, this.prefs);

  final RiderParams _base;
  @override
  final RoutePrefs prefs;

  @override
  RiderProfile get profile => _base.profile;
  @override
  double get climbTrackMPerH => _base.climbTrackMPerH;
  @override
  double get climbPathMPerH => _base.climbPathMPerH;
  @override
  double get pushRateMPerH => _base.pushRateMPerH;
  @override
  double get vFlatKmh => _base.vFlatKmh;
  @override
  double get vPathUpKmh => _base.vPathUpKmh;
  @override
  double get vPushKmh => _base.vPushKmh;
  @override
  double get vDownKmh => _base.vDownKmh;
  @override
  double get pathUpFactor => _base.pathUpFactor;
  @override
  double get pathDownFactor => _base.pathDownFactor;
  @override
  double get budgetClimbM => _base.budgetClimbM;
}

/// Bio-Bike oder E-Bike (Konzept-Routing 2.1). Das Profil ändert drei
/// Dinge und sonst nichts: Steigraten, Aufschlag Wanderweg bergauf,
/// Budget-Vorgabe. Wegerechte und die Trail-Seite bleiben gleich.
enum RiderProfile implements RiderParams {
  bio(
    label: 'Bio-Bike',
    climbTrackMPerH: 450,
    climbPathMPerH: 350,
    pushRateMPerH: 300,
    vFlatKmh: 15,
    vPathUpKmh: 8,
    vPushKmh: 3,
    vDownKmh: 25,
    pathUpFactor: 1.4,
    pathDownFactor: 2.0,
    budgetClimbM: 800,
  ),
  ebike(
    label: 'E-Bike',
    climbTrackMPerH: 850,
    climbPathMPerH: 650,
    pushRateMPerH: 220,
    vFlatKmh: 20,
    vPathUpKmh: 10,
    vPushKmh: 2.5,
    vDownKmh: 25,
    pathUpFactor: 2.0,
    pathDownFactor: 2.5,
    budgetClimbM: 1400,
  );

  const RiderProfile({
    required this.label,
    required this.climbTrackMPerH,
    required this.climbPathMPerH,
    required this.pushRateMPerH,
    required this.vFlatKmh,
    required this.vPathUpKmh,
    required this.vPushKmh,
    required this.vDownKmh,
    required this.pathUpFactor,
    required this.pathDownFactor,
    required this.budgetClimbM,
  });

  final String label;

  @override
  RiderProfile get profile => this;

  @override
  RoutePrefs get prefs => const RoutePrefs();

  /// Steigrate auf Forstweg und Straße, auf Pfaden (fahrend) und beim
  /// Schieben (Steig, Stufen), in Höhenmetern je Stunde.
  @override
  final double climbTrackMPerH;
  @override
  final double climbPathMPerH;
  @override
  final double pushRateMPerH;

  /// Geschwindigkeiten: flach auf Forstweg/Straße, Pfad bergauf
  /// (fahrend), schiebend, Straße/Forstweg bergab.
  @override
  final double vFlatKmh;
  @override
  final double vPathUpKmh;
  @override
  final double vPushKmh;
  @override
  final double vDownKmh;

  /// Aufschlag Wanderweg bergauf und bergab.
  @override
  final double pathUpFactor;
  @override
  final double pathDownFactor;

  /// Vorgabe „höchstens Höhenmeter bergauf" (Konzept-Routing 2.3).
  @override
  final double budgetClimbM;

  /// Der gespeicherte Name (`Settings.riderProfile`); unbekannt ⇒ Bio.
  static RiderProfile parse(String? name) =>
      values.where((p) => p.name == name).firstOrNull ?? RiderProfile.bio;
}

/// Vorgabe „höchstens Zeit" und „höchstens Wanderweg" (Konzept-Routing
/// 2.3) — für beide Profile gleich.
const kBudgetHours = 3.0;
const kBudgetHikingKm = 2.0;

/// Abfahrt auf einem Trail nach S-Grad (Median, wie das Schild), km/h;
/// ohne Einschätzung 10 km/h. Für beide Profile gleich: Bergab ist ein
/// S2 ein S2.
double trailDownKmh(int? grade) => switch (grade) {
      0 => 16,
      1 => 12,
      2 => 9,
      3 => 6,
      4 || 5 => 4,
      _ => 10,
    };

/// Die Wegklassen (Konzept-Routing 2.4): Aufschlag bergauf/bergab, ob
/// die Klasse als Wanderweg zählt (Regler „höchstens Wanderweg"), und
/// welche Geschwindigkeit und Steigrate des Profils sie nimmt. Ein
/// Aufschlag `null` heißt: der des Profils (`pathUpFactor`/`pathDownFactor`).
enum WayClass {
  forstweg('Forstweg', up: 1.0, down: 1.0, steep: kSteepFactorUnpaved),
  radweg('Radweg', up: 1.0, down: 1.0, steep: kSteepFactorPaved),
  nebenstrasse('Nebenstraße', up: 1.2, down: 1.2, steep: kSteepFactorPaved),
  zufahrt('Zufahrt', up: 1.2, down: 1.2, steep: kSteepFactorPaved),
  wanderweg('Wanderweg',
      up: null, down: null, hiking: true, pathSpeed: true, pathRate: true, steep: kSteepFactorUnpaved),
  fussweg('Fußweg', up: 2.0, down: 2.5, hiking: true, pathSpeed: true, pathRate: true, steep: kSteepFactorUnpaved),
  stufen('Stufen', up: 3.0, down: 3.0, hiking: true, pushing: true, steep: 0),
  landstrasse('Landstraße', up: 1.6, down: 1.6, steep: kSteepFactorPaved),
  hauptstrasse('Hauptstraße', up: 2.5, down: 2.5, steep: kSteepFactorPaved),
  bundesstrasse('Bundesstraße', up: 4.0, down: 4.0, steep: kSteepFactorPaved);

  const WayClass(this.label,
      {required this.up,
      required this.down,
      required this.steep,
      this.hiking = false,
      this.pathSpeed = false,
      this.pathRate = false,
      this.pushing = false});

  final String label;
  final double? up;
  final double? down;

  /// Der Steilaufschlag (#194): Wie oft die Höhenmeter über
  /// [kSteepGrade] ihre Steigzeit NOCH EINMAL kosten — unbefestigt
  /// [kSteepFactorUnpaved], Asphalt [kSteepFactorPaved], Stufen nichts
  /// (dort wird ohnehin geschoben).
  final double steep;

  /// Zählt gegen „höchstens Wanderweg", in beide Richtungen.
  final bool hiking;

  /// Nimmt bergauf die Pfad-Geschwindigkeit und -Steigrate.
  final bool pathSpeed;
  final bool pathRate;

  /// Wird geschoben (Steig, Stufen): Schiebe-Tempo und -Rate.
  final bool pushing;

  /// Straßenklassen: Nur hier gilt `oneway` — Forstwege und Pfade sind
  /// in beide Richtungen befahrbar.
  bool get isRoad => switch (this) {
        nebenstrasse || zufahrt || landstrasse || hauptstrasse || bundesstrasse => true,
        _ => false,
      };

  double upFactor(RiderParams p) => up ?? p.pathUpFactor;
  double downFactor(RiderParams p) => down ?? p.pathDownFactor;
}

/// Ab dieser Steigung ist ein Anstieg „sehr steil" (#194, Feldbericht
/// 0.74.0: „Super steile Anstiege sollten bestraft werden, insbesondere
/// wenn kein Asphalt"). Gemessen an den Höhen alle 50 m, geglättet über
/// [kSteepSmooth] Proben — siehe [steepExcess]. Gesetzt mit dem
/// Tirol-Lauf des Werkzeugs (docs/routing-messung.md).
const kSteepGrade = 0.15;

/// Über wie viele Höhenproben vor der Steigung gemittelt wird: Ein Weg
/// liegt ein paar Meter neben seiner Linie im 90-m-Modell, und quer zu
/// einer 40-%-Flanke sind das allein schon einige Prozent je Schritt.
const kSteepSmooth = 3;

/// Steilaufschlag unbefestigt (Forstweg, Wanderweg, Fußweg) und auf
/// Asphalt (Radweg, Straßen) — die Protomaps-Kacheln kennen keinen
/// Belag, die Klasse ist die beste Näherung.
const kSteepFactorUnpaved = 3.0;
const kSteepFactorPaved = 1.0;

/// Seit #188 beginnt der Steilaufschlag nicht an einer Schwelle: Jeder
/// Höhenmeter kostet seine Steigzeit noch einmal mal ein Gewicht, das mit
/// der Steigung EXPONENTIELL wächst (Betreiber 2026-10-02: „sehr steil
/// bergauf wird exponentiell teurer") — unter [kSteepWeightFrom] nichts,
/// je fünf Prozentpunkte etwa ×3 bis ×4: 0,14 bei 15 %, 0,57 bei 20 %,
/// 1,9 bei 25 %, 5,7 bei 30 %, höchstens [kSteepWeightMax].
/// [kSteepGrade] bleibt, was das Ergebnis „steil" nennt ([steepExcess],
/// [steepNote]); das Gewicht ist, was es kostet.
const kSteepWeightFrom = 0.10;
const kSteepWeightRef = 0.22;
const kSteepWeightScale = 0.0455;
const kSteepWeightMax = 30.0;

/// Ein Höhenmeter bergab auf einer Verbindung kostet diesen Teil dessen,
/// ihn wieder hinaufzufahren (Betreiber: „Bergab ist teurer") — die Höhe
/// ist verschenkt, wo ein Trail sie hätte nutzen können. Trails und
/// Verbinder tragen nichts.
const kDescentCost = 0.3;

/// Stufen bergauf (#210, Feldnotiz des Betreibers 2026-10-02: „Treppen
/// bergauf stark meiden — da wird getragen"): Tragen ist ein Halt, kein
/// langsameres Tempo. Eine Stufen-Kante, die steigt (Gewinn > Verlust),
/// kostet deshalb diese Sekunden obendrauf, unabhängig von ihrer Länge;
/// bergab und ohne Höhen nichts (die Richtung ist dann unbekannt). Eine
/// Teilung gibt ihn nach Länge weiter ([GraphEdge.carry]), damit ein
/// angehefteter Trailkopf eine Treppe nicht doppelt zählt. Kosten, keine
/// Minuten. Mit dem Aufschlag ×3 verliert eine 20-m-Treppe mit 4 hm
/// (Bio) jetzt gegen rund 1 km Forstweg statt gegen 0,8 km.
const kCarryCostS = 60.0;

/// Wegegüte (#213, Vorschlag des Betreibers 2026-10-02: „schlechte
/// Forstwege deutlich teurer, z. B. doppelte Steigung"; abgestuft, nie
/// ein Schalter). Die Klassen sind die des Wege-Archivs, Format 2
/// (`kWaysFormat`): 3 Forstweg schlecht (grade4), 7 sehr schlecht
/// (grade5, holprig, Matsch), 6 Pfad schwer (S3/T3), 8 sehr schwer
/// (ab S4/T4); an Pfaden `u` = `mtb:scale:uphill` ([GraphEdge.uphill]).
/// Wie der Steilaufschlag Kosten, keine Minuten. Bergab nichts, unbekannt
/// kostet, was es immer kostete. Spiegel von `WAY_*` und `way_cost_s`.
///
/// Forstweg: (Faktor auf den Steigteil, Faktor auf den Streckenteil)
/// bergauf und in der Ebene; der Aufschlag ist (Faktor − 1) × Teil.
const kWayTrack = <int, (double, double)>{3: (1.3, 1.15), 7: (2.0, 1.3)};

/// Pfad bergauf: geschoben — die Zeit des Schiebens mal Faktor statt der
/// des Fahrens.
const kWayPathPush = <int, double>{6: 1.0, 8: 2.0};

/// `mtb:scale:uphill` sagt es besser, wo es steht: 0–1 wie jeder Pfad,
/// 2 die Steigzeit halb noch einmal, 3 schieben, ab 4 doppelt schieben.
const kWayUphillClimb = <int, double>{2: 1.5};
const kWayUphillPush = <int, double>{3: 1.0, 4: 2.0, 5: 2.0};

/// Der Aufschlag für die Wegegüte einer Kante in einer Richtung (#213)
/// — `way_cost_s`.
double wayCostS(RiderParams p, WayClass cls,
    {required double lengthM, required double gainM, required double lossM, int? way, int? uphill}) {
  if (lossM > gainM) return 0;
  if (cls == WayClass.forstweg) {
    final f = kWayTrack[way];
    if (f == null) return 0;
    final climb = gainM / (p.climbTrackMPerH / 3600.0);
    final dist = lengthM / (p.vFlatKmh / 3.6);
    return (f.$1 - 1) * climb + (f.$2 - 1) * dist;
  }
  if (cls == WayClass.wanderweg && gainM > lossM) {
    final double? push;
    if (uphill != null) {
      final c = kWayUphillClimb[uphill];
      if (c != null) return (c - 1) * gainM / (p.climbPathMPerH / 3600.0);
      push = kWayUphillPush[uphill];
    } else {
      push = kWayPathPush[way];
    }
    if (push != null && push > 0) {
      final pushed = lengthM / (p.vPushKmh / 3.6) + gainM / (p.pushRateMPerH / 3600.0);
      final extra = push * pushed - edgeTimeS(p, cls, lengthM: lengthM, gainM: gainM, lossM: lossM);
      return extra > 0 ? extra : 0;
    }
  }
  return 0;
}

/// Das Gewicht eines Höhenmeters bei [grade] — `steep_weight_at`.
double steepWeightAt(double grade) {
  if (grade <= kSteepWeightFrom) return 0;
  final w = math.exp((grade - kSteepWeightRef) / kSteepWeightScale) -
      math.exp((kSteepWeightFrom - kSteepWeightRef) / kSteepWeightScale);
  return w > kSteepWeightMax ? kSteepWeightMax : w;
}

/// Die gewichteten Steilmeter entlang der Proben, in Probenrichtung und
/// dagegen: je Schritt der Anstieg mal [steepWeightAt] seiner Steigung,
/// geglättet wie [steepExcess] (Höhen UND Positionen). Spiegel von
/// `steep_weight` im Werkzeug, mit dessen Testvektoren.
({double up, double down}) steepWeight(List<double> heights, List<double> stepsM, {int window = kSteepSmooth}) {
  if (heights.length < 2 || stepsM.length != heights.length - 1) return (up: 0.0, down: 0.0);
  final dist = <double>[0];
  for (final d in stepsM) {
    dist.add(dist.last + d);
  }
  final sm = window > 1 ? smoothHeights(heights, window: window) : heights;
  final sd = window > 1 ? smoothHeights(dist, window: window) : dist;
  var up = 0.0, down = 0.0;
  for (var i = 0; i < sm.length - 1; i++) {
    final rise = sm[i + 1] - sm[i];
    final d = sd[i + 1] - sd[i];
    if (d <= 0) continue;
    if (rise > 0) {
      up += rise * steepWeightAt(rise / d);
    } else if (rise < 0) {
      down += -rise * steepWeightAt(-rise / d);
    }
  }
  return (up: up, down: down);
}

/// Gleitender Mittelwert über [window] Werte, an den Enden über die, die
/// da sind — `smooth_heights` im Werkzeug.
List<double> smoothHeights(List<double> heights, {int window = kSteepSmooth}) {
  final half = window ~/ 2;
  return [
    for (var i = 0; i < heights.length; i++)
      () {
        final lo = i - half < 0 ? 0 : i - half;
        final hi = i + half + 1 > heights.length ? heights.length : i + half + 1;
        var sum = 0.0;
        for (var j = lo; j < hi; j++) {
          sum += heights[j];
        }
        return sum / (hi - lo);
      }(),
  ];
}

/// Die Höhenmeter über [grade] entlang der Proben (#194), in Proben-
/// richtung und dagegen: je Schritt, was die geglättete Höhe mehr steigt
/// als [grade] × Schrittlänge. [stepsM] sind die Abstände zwischen
/// aufeinanderfolgenden Proben. Geglättet werden Höhen UND Positionen —
/// der letzte Schritt einer Kante ist kurz (der Rest nach den vollen
/// 50 m), und nur die Höhen zu glätten legte dort einen 50-m-Anstieg auf
/// einen Meter. Eine gleichmäßige Steigung kommt so immer genau heraus.
/// Spiegel von `steep_excess` im Werkzeug, mit dessen Testvektoren.
({double up, double down}) steepExcess(List<double> heights, List<double> stepsM,
    {double grade = kSteepGrade, int window = kSteepSmooth}) {
  if (heights.length < 2 || stepsM.length != heights.length - 1) return (up: 0.0, down: 0.0);
  final dist = <double>[0];
  for (final d in stepsM) {
    dist.add(dist.last + d);
  }
  final sm = window > 1 ? smoothHeights(heights, window: window) : heights;
  final sd = window > 1 ? smoothHeights(dist, window: window) : dist;
  var up = 0.0, down = 0.0;
  for (var i = 0; i < sm.length - 1; i++) {
    final rise = sm[i + 1] - sm[i];
    final allowed = grade * (sd[i + 1] - sd[i]);
    if (rise > allowed) up += rise - allowed;
    if (-rise > allowed) down += -rise - allowed;
  }
  return (up: up, down: down);
}

/// Die Klasse eines `roads`-Features der Kacheln, oder null, wenn die
/// Engine es nicht benutzen darf: Autobahn und Schnellstraße (`highway`),
/// Schienen, Fähren, `other` (Rennstrecken, Pisten), Privatzufahrten,
/// `access` private/no. `primary_link` zählt als Bundesstraße.
WayClass? classifyWay({
  required String? kind,
  required String? kindDetail,
  String? access,
  String? service,
}) {
  if (access == 'private' || access == 'no') return null;
  switch (kind) {
    case 'major_road':
      return (kindDetail ?? '').startsWith('primary') ? WayClass.bundesstrasse : WayClass.hauptstrasse;
    case 'medium_road':
      return WayClass.landstrasse;
    case 'minor_road':
      if (kindDetail == 'service') {
        return service == 'driveway' || service == 'parking_aisle' ? null : WayClass.zufahrt;
      }
      return WayClass.nebenstrasse;
    case 'path':
      return switch (kindDetail) {
        'track' => WayClass.forstweg,
        'cycleway' => WayClass.radweg,
        'path' || 'bridleway' => WayClass.wanderweg,
        'footway' || 'pedestrian' => WayClass.fussweg,
        'steps' => WayClass.stufen,
        _ => null,
      };
    default:
      return null;
  }
}

/// Die Zeit einer Wegekante in Sekunden (Konzept-Routing 2.2):
/// Strecke / v(Klasse, Richtung) + Anstieg / Steigrate(Profil, Klasse).
/// Bergab (mehr Verlust als Gewinn) zählt nur die Strecke — mit der
/// Abfahrtsgeschwindigkeit, auf einem Wanderweg wie auf einem Trail ohne
/// Einschätzung, auf Stufen schiebend.
double edgeTimeS(RiderParams p, WayClass cls,
    {required double lengthM, required double gainM, required double lossM}) {
  final downhill = lossM > gainM;
  final double vKmh;
  if (cls.pushing) {
    vKmh = p.vPushKmh;
  } else if (downhill) {
    vKmh = cls == WayClass.wanderweg
        ? trailDownKmh(null)
        : cls.hiking
            ? p.vPathUpKmh
            : p.vDownKmh;
  } else {
    vKmh = cls.pathSpeed ? p.vPathUpKmh : p.vFlatKmh;
  }
  return lengthM / (vKmh / 3.6) + gainM / (_climbRate(p, cls) / 3600.0);
}

/// Die Steigrate der Klasse: schiebend, Pfad oder Forstweg/Straße.
double _climbRate(RiderParams p, WayClass cls) => cls.pushing
    ? p.pushRateMPerH
    : cls.pathRate
        ? p.climbPathMPerH
        : p.climbTrackMPerH;

/// Der Steilaufschlag (#194, seit #188 gewichtet) für [steepW]
/// gewichtete Steilmeter ([steepWeight]): ihre Steigzeit noch einmal,
/// mal [WayClass.steep] und der Stärke aus den Vorlieben. Kosten, keine
/// Minuten — die Zeit bleibt, was die Fahrten kalibrieren.
double steepCostS(RiderParams p, WayClass cls, double steepW) =>
    steepW / (_climbRate(p, cls) / 3600.0) * cls.steep * p.prefs.steepStrength;

/// Was [lossM] Höhenmeter bergab auf einer Verbindung kosten:
/// [kDescentCost] der Zeit, sie wieder hinaufzufahren.
double descentCostS(RiderParams p, WayClass cls, double lossM) => kDescentCost * lossM / (_climbRate(p, cls) / 3600.0);

/// Der Trage-Aufschlag ([kCarryCostS]) einer Stufen-Kante bergauf, nach
/// einer Teilung ihr Anteil [share] — `carry_cost_s`.
double carryCostS(WayClass cls, {required double gainM, required double lossM, double share = 1}) =>
    cls.pushing && gainM > lossM ? kCarryCostS * share : 0;

/// Die Zeit auf einem Trail bergab, nach S-Grad.
double trailTimeS({required double lengthM, required int? grade}) =>
    lengthM / (trailDownKmh(grade) / 3.6);

/// Der Aufschlag der Kante — bergab der Abstiegs-, sonst der
/// Anstiegsaufschlag. Die Vorlieben (#188) skalieren den Teil über 1:
/// Straßen in beide Richtungen, Wanderwege nur bergauf, Stufen nie.
double edgeFactor(RiderParams p, WayClass cls, {required double gainM, required double lossM}) {
  final downhill = lossM > gainM;
  final f = downhill ? cls.downFactor(p) : cls.upFactor(p);
  if (cls.isRoad) return 1 + p.prefs.roadStrength * (f - 1);
  if (cls.hiking && !cls.pushing && !downhill) return 1 + p.prefs.hikingStrength * (f - 1);
  return f;
}

/// Kosten = Zeit × Aufschlag (Konzept-Routing 2.4): Der Aufschlag sagt,
/// was die Zeit nicht sagt — eine Bundesstraße ist nicht langsam, sie
/// ist falsch. Dazu der Steilaufschlag für [steepW] gewichtete
/// Steilmeter (#194), mit [descent] der Preis der verschenkten Höhe
/// (#188), auf Stufen bergauf der Anteil [carry] des Trage-Aufschlags
/// (#210) und die Wegegüte [way]/[uphill] (#213, [wayCostS]).
double edgeCostS(RiderParams p, WayClass cls,
        {required double lengthM,
        required double gainM,
        required double lossM,
        double steepW = 0,
        bool descent = true,
        double carry = 1,
        int? way,
        int? uphill}) =>
    edgeTimeS(p, cls, lengthM: lengthM, gainM: gainM, lossM: lossM) *
        edgeFactor(p, cls, gainM: gainM, lossM: lossM) +
    steepCostS(p, cls, steepW) +
    (descent ? descentCostS(p, cls, lossM) : 0) +
    carryCostS(cls, gainM: gainM, lossM: lossM, share: carry) +
    wayCostS(p, cls, lengthM: lengthM, gainM: gainM, lossM: lossM, way: way, uphill: uphill);
