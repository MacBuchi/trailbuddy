// Profil, Wegklassen und Kosten der Routing-Engine — Zahl für Zahl gegen
// `tool/route_measure.py` (die Zahlen hier sind dort gerechnet, am
// 2026-10-01, mit denselben Aufrufen; seit #188 mit dem Preis der
// verschenkten Höhe und den Vorlieben, gerechnet am 2026-10-02).
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';

void main() {
  test('classify: dieselben Antworten wie das Werkzeug', () {
    expect(classifyWay(kind: 'path', kindDetail: 'track'), WayClass.forstweg);
    expect(classifyWay(kind: 'path', kindDetail: 'path'), WayClass.wanderweg);
    expect(classifyWay(kind: 'path', kindDetail: 'bridleway'), WayClass.wanderweg);
    expect(classifyWay(kind: 'path', kindDetail: 'cycleway'), WayClass.radweg);
    expect(classifyWay(kind: 'path', kindDetail: 'footway'), WayClass.fussweg);
    expect(classifyWay(kind: 'path', kindDetail: 'steps'), WayClass.stufen);
    expect(classifyWay(kind: 'major_road', kindDetail: 'primary_link'), WayClass.bundesstrasse,
        reason: 'primary links count as primary');
    expect(classifyWay(kind: 'major_road', kindDetail: 'secondary'), WayClass.hauptstrasse);
    expect(classifyWay(kind: 'medium_road', kindDetail: 'tertiary'), WayClass.landstrasse);
    expect(classifyWay(kind: 'minor_road', kindDetail: 'residential'), WayClass.nebenstrasse);
    expect(classifyWay(kind: 'minor_road', kindDetail: 'service'), WayClass.zufahrt);
    expect(classifyWay(kind: 'minor_road', kindDetail: 'service', service: 'driveway'), isNull);
    expect(classifyWay(kind: 'minor_road', kindDetail: 'service', service: 'parking_aisle'), isNull);
    expect(classifyWay(kind: 'highway', kindDetail: 'motorway'), isNull);
    expect(classifyWay(kind: 'path', kindDetail: 'track', access: 'private'), isNull);
    expect(classifyWay(kind: 'path', kindDetail: 'track', access: 'no'), isNull);
    expect(classifyWay(kind: 'rail', kindDetail: null), isNull);
    expect(classifyWay(kind: 'other', kindDetail: 'raceway'), isNull);
    expect(classifyWay(kind: null, kindDetail: null), isNull);
  });

  test('Einbahn gilt nur auf Straßenklassen', () {
    for (final c in WayClass.values) {
      expect(c.isRoad, [WayClass.nebenstrasse, WayClass.zufahrt, WayClass.landstrasse, WayClass.hauptstrasse, WayClass.bundesstrasse].contains(c),
          reason: c.name);
    }
    expect(WayClass.values.where((c) => c.hiking).toList(), [WayClass.wanderweg, WayClass.fussweg, WayClass.stufen]);
  });

  test('Zeit und Kosten: die Zahlen des Werkzeugs', () {
    double t(RiderProfile p, WayClass c, double l, double g, double v) =>
        edgeTimeS(p, c, lengthM: l, gainM: g, lossM: v);
    double k(RiderProfile p, WayClass c, double l, double g, double v) =>
        edgeCostS(p, c, lengthM: l, gainM: g, lossM: v);
    const bio = RiderProfile.bio, e = RiderProfile.ebike;
    expect(t(bio, WayClass.forstweg, 1000, 100, 0), closeTo(1040.0, 1e-6));
    expect(k(bio, WayClass.forstweg, 1000, 100, 0), closeTo(1040.0, 1e-6));
    expect(t(bio, WayClass.wanderweg, 1000, 100, 0), closeTo(1478.571429, 1e-5));
    expect(k(bio, WayClass.wanderweg, 1000, 100, 0), closeTo(2070.0, 1e-5));
    expect(t(e, WayClass.wanderweg, 1000, 100, 0), closeTo(913.846154, 1e-5));
    expect(k(e, WayClass.wanderweg, 1000, 100, 0), closeTo(1827.692308, 1e-5));
    expect(k(e, WayClass.forstweg, 1000, 100, 0), closeTo(603.529412, 1e-5));
    expect(t(bio, WayClass.bundesstrasse, 1000, 0, 0), closeTo(240.0, 1e-6));
    expect(k(bio, WayClass.bundesstrasse, 1000, 0, 0), closeTo(960.0, 1e-6));
    expect(k(bio, WayClass.forstweg, 1000, 0, 100), closeTo(384.0, 1e-6),
        reason: 'bergab 25 km/h, dazu 0,3 der Steigzeit für die verschenkten 100 hm');
    expect(t(bio, WayClass.wanderweg, 1000, 0, 100), closeTo(360.0, 1e-6), reason: 'bergab wie Trail ohne Grad');
    expect(k(bio, WayClass.wanderweg, 1000, 0, 100), closeTo(1028.571429, 1e-5));
    expect(k(bio, WayClass.stufen, 200, 50, 0), closeTo(2580.0, 1e-6), reason: 'mit dem Trage-Aufschlag (#210)');
    expect(k(e, WayClass.stufen, 200, 50, 0), closeTo(3378.545455, 1e-5));
    expect(k(bio, WayClass.fussweg, 500, 0, 30), closeTo(655.071429, 1e-5));
    expect(k(bio, WayClass.nebenstrasse, 2000, 150, 20), closeTo(2064.0, 1e-6));
    // Trails bergab nach Grad.
    expect(trailTimeS(lengthM: 1800, grade: 2), closeTo(720.0, 1e-6));
    expect(trailTimeS(lengthM: 1800, grade: null), closeTo(648.0, 1e-6));
    expect(trailDownKmh(5), trailDownKmh(4));
    // Die Regeln, in Worten: Wanderweg bergauf kostet mehr als ×1,4 Forstweg,
    // das E-Bike steigt schneller, der E-Bike-Aufschlag ist 2,0.
    expect(k(bio, WayClass.wanderweg, 1000, 100, 0), greaterThan(1040.0 * 1.4));
    expect(k(e, WayClass.forstweg, 1000, 100, 0), lessThan(1040.0));
    expect(k(e, WayClass.wanderweg, 1000, 100, 0) / t(e, WayClass.wanderweg, 1000, 100, 0), closeTo(2.0, 1e-9));
  });

  test('Steilaufschlag: dieselben Vektoren wie das Werkzeug (#194)', () {
    // 30 % alle 50 m.
    final ramp = [for (var i = 0; i < 9; i++) 100.0 + 15.0 * i];
    final steps = List.filled(8, 50.0);
    expect(steepExcess(ramp, steps, window: 1), (up: 60.0, down: 0.0), reason: 'roh: 7,5 m über 15 % je Schritt');
    final smooth = steepExcess(ramp, steps);
    expect(smooth.up, closeTo(52.5, 1e-9), reason: 'geglättet: an den Enden fehlt je ein halber Schritt');
    expect(smooth.down, 0);
    expect(steepExcess([for (var i = 0; i < 9; i++) 100.0 + 5.0 * i], steps), (up: 0.0, down: 0.0),
        reason: '10 % ist nicht steil');
    expect(steepExcess(ramp.reversed.toList(), steps).down, smooth.up, reason: 'rückwärts die andere Richtung');
    expect(steepExcess([100, 130], [50]), (up: 0.0, down: 0.0), reason: 'zwei Proben glätten zu einem Wert');
    expect(steepExcess([100, 110, 100], [50, 50], window: 1), (up: 2.5, down: 2.5));
    expect(smoothHeights([0, 30, 0, 30]), [15.0, 10.0, 20.0, 15.0]);
    // Ein kurzer letzter Schritt (der Rest der Kante) bleibt bei seiner Steigung.
    final shortEnd = [for (var i = 0; i < 67; i++) 100.0 + 7.27 * i, 100.0 + 7.27 * 66 + 0.163];
    expect(steepExcess(shortEnd, [...List.filled(66, 50.0), 1.12]), (up: 0.0, down: 0.0));
    expect(steepExcess([100, 110], [50, 50]), (up: 0.0, down: 0.0), reason: 'Schritte passen nicht ⇒ nichts');

    const bio = RiderProfile.bio, e = RiderProfile.ebike;
    expect(steepCostS(bio, WayClass.forstweg, 10), closeTo(240.0, 1e-9), reason: 'unbefestigt: 3× die Steigzeit');
    expect(steepCostS(e, WayClass.nebenstrasse, 10), closeTo(10 * 3600 / 850, 1e-9), reason: 'Asphalt: 1×');
    expect(steepCostS(bio, WayClass.wanderweg, 10), closeTo(10 * 3600 / 350 * 3, 1e-9), reason: 'Pfad-Steigrate');
    expect(steepCostS(bio, WayClass.stufen, 10), 0, reason: 'Stufen werden ohnehin geschoben');
    expect(
        edgeCostS(bio, WayClass.forstweg, lengthM: 1000, gainM: 100, lossM: 0, steepW: 10) -
            edgeCostS(bio, WayClass.forstweg, lengthM: 1000, gainM: 100, lossM: 0),
        closeTo(240.0, 1e-9),
        reason: 'der Aufschlag kommt zu den Kosten, nicht zur Zeit');
    for (final c in WayClass.values) {
      expect(c.steep, c == WayClass.stufen ? 0 : c.isRoad || c == WayClass.radweg ? kSteepFactorPaved : kSteepFactorUnpaved,
          reason: c.label);
    }
  });

  test('Stufen bergauf werden getragen: dieselben Zahlen wie das Werkzeug (#210)', () {
    const bio = RiderProfile.bio, e = RiderProfile.ebike;
    expect(kCarryCostS, 60.0);
    expect(carryCostS(WayClass.stufen, gainM: 4, lossM: 0), 60.0, reason: 'eine Treppe hinauf');
    expect(carryCostS(WayClass.stufen, gainM: 0, lossM: 4), 0, reason: 'hinunter nicht');
    expect(carryCostS(WayClass.stufen, gainM: 0, lossM: 0), 0, reason: 'ohne Höhen ist die Richtung unbekannt');
    for (final c in WayClass.values.where((c) => c != WayClass.stufen)) {
      expect(carryCostS(c, gainM: 4, lossM: 0), 0, reason: c.label);
    }
    expect(edgeCostS(bio, WayClass.stufen, lengthM: 20, gainM: 4, lossM: 0), closeTo(276.0, 1e-6),
        reason: '216 s plus der Aufschlag, unabhängig von der Länge');
    expect(edgeCostS(e, WayClass.stufen, lengthM: 20, gainM: 4, lossM: 0), closeTo(342.763636, 1e-5));
    expect(edgeCostS(bio, WayClass.stufen, lengthM: 20, gainM: 0, lossM: 4), closeTo(86.4, 1e-6));
    expect(edgeCostS(bio, WayClass.stufen, lengthM: 20, gainM: 4, lossM: 0, carry: 0.25), closeTo(231.0, 1e-6),
        reason: 'ein geteiltes Stück trägt seinen Anteil');
    expect(edgeCostS(bio.withPrefs(const RoutePrefs(avoidHiking: false)), WayClass.stufen, lengthM: 20, gainM: 4, lossM: 0),
        closeTo(276.0, 1e-6), reason: '„Wanderwege: egal" macht das Tragen nicht billiger');
    expect(edgeTimeS(bio, WayClass.stufen, lengthM: 20, gainM: 4, lossM: 0), closeTo(72.0, 1e-6),
        reason: 'Kosten, keine Minuten');
  });

  test('Wegegüte: dieselben Zahlen wie das Werkzeug (#213)', () {
    // (Klasse, Länge, Gewinn, Verlust, way, uphill) → (way_cost_s, edge_cost_s)
    // für Bio und E-Bike, gerechnet in tool/route_measure.py am 2026-10-08.
    const cases = <(WayClass, double, double, double, int?, int?, double, double, double, double)>[
      (WayClass.forstweg, 1000, 100, 0, 7, null, 872.0, 1912.0, 477.529412, 1081.058824),
      (WayClass.forstweg, 1000, 100, 0, 3, null, 276.0, 1316.0, 154.058824, 757.588235),
      (WayClass.forstweg, 1000, 0, 0, 7, null, 72.0, 312.0, 54.0, 234.0),
      (WayClass.forstweg, 800, 0, 60, 7, null, 0.0, 259.2, 0.0, 191.435294),
      (WayClass.wanderweg, 1000, 100, 0, 6, null, 921.428571, 2991.428571, 2162.517483, 3990.20979),
      (WayClass.wanderweg, 1000, 100, 0, 8, null, 3321.428571, 5391.428571, 5238.881119, 7066.573427),
      (WayClass.wanderweg, 1000, 100, 0, null, 2, 514.285714, 2584.285714, 276.923077, 2104.615385),
      (WayClass.wanderweg, 500, 60, 0, 4, 3, 477.857143, 1656.857143, 1189.51049, 2214.125874),
      (WayClass.wanderweg, 1000, 100, 0, 8, 1, 0.0, 2070.0, 0.0, 1827.692308),
      (WayClass.wanderweg, 300, 10, 0, 8, null, 722.142857, 1055.142857, 1027.888112, 1354.657343),
    ];
    for (final (cls, l, g, ls, way, up, wBio, cBio, wE, cE) in cases) {
      for (final (p, w, c) in [(RiderProfile.bio, wBio, cBio), (RiderProfile.ebike, wE, cE)]) {
        final why = '${p.name} ${cls.name} $l/$g/$ls way $way u $up';
        expect(wayCostS(p, cls, lengthM: l, gainM: g, lossM: ls, way: way, uphill: up), closeTo(w, 1e-5), reason: why);
        expect(edgeCostS(p, cls, lengthM: l, gainM: g, lossM: ls, way: way, uphill: up), closeTo(c, 1e-5), reason: why);
      }
    }
    // Unbekannt, gut und die falsche Wegart kosten, was sie immer kosteten.
    for (final (cls, way) in [(WayClass.forstweg, null), (WayClass.forstweg, 1), (WayClass.forstweg, 6),
      (WayClass.fussweg, 8), (WayClass.nebenstrasse, 7)]) {
      expect(wayCostS(RiderProfile.bio, cls, lengthM: 1000, gainM: 100, lossM: 0, way: way), 0, reason: '$cls $way');
    }
  });

  test('Gewichtete Steilmeter: dieselben Vektoren wie das Werkzeug (#188)', () {
    expect(steepWeightAt(0.05), 0);
    expect(steepWeightAt(0.10), 0, reason: 'bis 10 % nichts');
    expect(steepWeightAt(0.15), closeTo(0.14316, 1e-4));
    expect(steepWeightAt(0.20), closeTo(0.57277, 1e-4));
    expect(steepWeightAt(0.25), closeTo(1.86197, 1e-4));
    expect(steepWeightAt(0.30), closeTo(5.73068, 1e-4));
    expect(steepWeightAt(0.5), kSteepWeightMax, reason: 'gedeckelt');
    expect(steepWeightAt(0.20) / steepWeightAt(0.15), closeTo(4.0, 0.1), reason: 'fünf Punkte mehr, etwa ×4');
    final ramp = [for (var i = 0; i < 9; i++) 100.0 + 15.0 * i];
    final steps = List.filled(8, 50.0);
    final raw = steepWeight(ramp, steps, window: 1);
    expect(raw.up, closeTo(120 * steepWeightAt(0.30), 1e-9), reason: 'roh: jeder Meter einer 30-%-Rampe');
    expect(raw.down, 0);
    expect(steepWeight([for (var i = 0; i < 9; i++) 100.0 + 5.0 * i], steps), (up: 0.0, down: 0.0));
    expect(steepWeight(ramp.reversed.toList(), steps).down, steepWeight(ramp, steps).up);
    final shortEnd = [for (var i = 0; i < 67; i++) 100.0 + 7.27 * i, 100.0 + 7.27 * 66 + 0.163];
    expect(steepWeight(shortEnd, [...List.filled(66, 50.0), 1.12]).up, closeTo(58.350125, 1e-5),
        reason: 'ein kurzer letzter Schritt bleibt bei seiner Steigung');
  });

  test('Vorlieben: die Zahlen des Werkzeugs (#188)', () {
    const bio = RiderProfile.bio, e = RiderProfile.ebike;
    final roadsAny = bio.withPrefs(const RoutePrefs(avoidRoads: false));
    final hikingAny = e.withPrefs(const RoutePrefs(avoidHiking: false));
    final steepAny = bio.withPrefs(const RoutePrefs(avoidSteep: false));
    expect(edgeCostS(roadsAny, WayClass.hauptstrasse, lengthM: 1000, gainM: 0, lossM: 0), closeTo(366.0, 1e-6),
        reason: 'Straßen egal: 35 % des Aufschlags über 1');
    expect(edgeCostS(roadsAny, WayClass.hauptstrasse, lengthM: 1000, gainM: 0, lossM: 100), closeTo(459.6, 1e-6));
    expect(edgeFactor(roadsAny, WayClass.radweg, gainM: 0, lossM: 0), 1.0, reason: 'ein Radweg ist keine Straße');
    expect(edgeCostS(hikingAny, WayClass.wanderweg, lengthM: 1000, gainM: 100, lossM: 0), closeTo(1233.692308, 1e-5),
        reason: 'Wanderweg bergauf egal');
    expect(edgeFactor(hikingAny, WayClass.wanderweg, gainM: 0, lossM: 10), 2.5, reason: 'bergab bleibt');
    expect(edgeFactor(bio.withPrefs(const RoutePrefs(avoidHiking: false)), WayClass.stufen, gainM: 10, lossM: 0), 3.0,
        reason: 'Stufen bleiben');
    expect(edgeCostS(steepAny, WayClass.forstweg, lengthM: 1000, gainM: 100, lossM: 0, steepW: 20), closeTo(1184.0, 1e-6));
    expect(edgeCostS(bio, WayClass.forstweg, lengthM: 1000, gainM: 100, lossM: 0, steepW: 20), closeTo(1520.0, 1e-6));
    expect(edgeCostS(bio, WayClass.forstweg, lengthM: 1000, gainM: 0, lossM: 100, descent: false),
        closeTo(144.0, 1e-6), reason: 'ohne den Preis der Höhe (Trail)');
    expect(bio.withPrefs(const RoutePrefs()), same(bio), reason: 'meiden ist die Vorgabe');
    expect(roadsAny.profile, bio);
    expect(roadsAny.climbTrackMPerH, bio.climbTrackMPerH);
  });

  test('Profile: Vorgaben und Lesen aus der Einstellung', () {
    expect(RiderProfile.bio.budgetClimbM, 800);
    expect(RiderProfile.ebike.budgetClimbM, 1400);
    expect(RiderProfile.parse('ebike'), RiderProfile.ebike);
    expect(RiderProfile.parse('bio'), RiderProfile.bio);
    expect(RiderProfile.parse(null), RiderProfile.bio);
    expect(RiderProfile.parse('rakete'), RiderProfile.bio);
    expect(kBudgetHours, 3.0);
    expect(kBudgetHikingKm, 2.0);
  });
}
