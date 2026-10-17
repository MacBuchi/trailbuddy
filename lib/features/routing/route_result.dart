// Die Route von A nach B im Planer (#356, Konzept-Routing 10.2): ohne
// gewählten Trail ist sie der günstigste Weg im gewählten Stil — Direkt,
// Bequem oder Spaßig. Pur: was der Controller zum Rechnen braucht, ohne
// Riverpod; gerechnet wird mit `planLoop(bare: true)` im Rechen-Isolate
// wie die Runde, also auch mit ziehbaren Punkten (#234).
//
// Drei Dinge, die man wissen muss:
// - **Direkt und Bequem sind EINE Rechnung** ohne Pool, mit
//   [kRouteDirectBudget]: Budgets prüft dabei niemand (keine Trails), das
//   Zeitbudget ist nur die Grenze der Suche — eine Verbindung darüber
//   gilt als unerreichbar.
// - **Spaßig sind ZWEI**: erst der direkte Weg, dann die Planung mit den
//   Trails auf dem Weg ([funPoolOf]) im Budget [funBudgetOf] aus dessen
//   Summen. Nimmt sie keinen mit, steht der direkte da, und das Blatt
//   sagt es — wie im Blatt „Route" seit #176.
// - **Die Zahlen sind die des Blatts „Route"** (`kFun*`, Startwerte, nicht
//   gemessen); es liest sie von hier.
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../models/trail.dart';
import '../trails/trail_geometry.dart' show haversineM;
import 'loop_planner.dart';

/// Spaßig darf so viel länger dauern als direkt — und mindestens so viel
/// mehr (sonst hätte ein 10-Minuten-Weg keinen Platz für einen Trail).
/// Startwerte, nicht gemessen.
const kFunTimeFactor = 1.6;
const kFunExtraS = 20 * 60.0;
const kFunClimbFactor = 1.5;
const kFunExtraClimbM = 200.0;

/// Wie weit die Trails des spaßigen Wegs vom Ziel liegen dürfen — weiter
/// als der Start selbst plus das.
const kFunPoolSlackM = 3000.0;

/// Das „Budget" des direkten Wegs: nur die Grenze der Suchen, geprüft wird
/// es nie (kein Trail im Pool, Zwischenpunkte zählen ohnehin nicht).
const kRouteDirectBudget = LoopBudget(timeS: 24 * 3600, climbM: 1e5, hikingM: 1e7);

/// Das Budget des spaßigen Wegs aus den Summen des direkten.
LoopBudget funBudgetOf({required double timeS, required double gainM, required double hikingM, required double hikingKm}) =>
    LoopBudget(
      timeS: math.max(timeS * kFunTimeFactor, timeS + kFunExtraS) / (1 - kLoopTimeReserve),
      climbM: math.max(gainM * kFunClimbFactor, gainM + kFunExtraClimbM),
      hikingM: math.max(hikingKm * 1000, hikingM),
    );

/// Die Abfahrten, die der spaßige Weg mitnehmen darf: in Reichweite des
/// Starts, beide Enden nicht weiter vom Ziel als der Start selbst plus
/// [kFunPoolSlackM], ohne Meldung — und nie [exceptId] (der Ziel-Trail,
/// den fährt man danach).
List<Trail> funPoolOf(List<Trail> trails, LatLng from, LatLng to, {String? exceptId}) {
  double toTarget(LatLng p) => haversineM(p.latitude, p.longitude, to.latitude, to.longitude);
  final reach = toTarget(from) + kFunPoolSlackM;
  return [
    for (final t in loopPoolOf(trails, from).inReach)
      if (t.id != exceptId && toTarget(t.start) <= reach && toTarget(t.end) <= reach) t,
  ];
}
