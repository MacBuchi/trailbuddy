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

/// Wie weit die Enden eines Trails des spaßigen Wegs neben der Linie
/// Start–Ziel liegen dürfen — als Umweg gemessen: Start → Ende → Ziel
/// höchstens die Luftlinie plus zweimal das (#468).
const kFunPoolSlackM = 3000.0;

/// Höchstens so viele Trails im Pool des spaßigen Wegs, die mit dem
/// kleinsten Umweg zuerst (#468): Seit der Pool an der ganzen Linie hängt
/// statt an 12 km um den Start, fasst eine lange Route sonst jeden Trail
/// der Gegend — und jeder kostet eine Suche.
const kFunPoolMax = 30;

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

/// Die Abfahrten, die der spaßige Weg mitnehmen darf: beide Enden in
/// einem Korridor um die Linie [from]–[to] (Umweg über das Ende höchstens
/// 2 × [kFunPoolSlackM]), ohne Meldung, die [kFunPoolMax] mit dem kleinsten
/// Umweg — und nie [exceptId] (der Ziel-Trail, den fährt man danach).
///
/// **Gleich, wo an der Linie** (#468): Bis 0.155.1 mussten beide Enden in
/// 12 km um den Start liegen ([loopPoolOf]s Reichweite, gedacht für die
/// Runde). Auf einer längeren Route nahm Spaßig dann Trails abseits des
/// Starts mit, und an der zweiten Hälfte fuhr es an Trails vorbei, die es
/// nie gesehen hatte. Wer gewinnt, entscheidet danach der Planer — nach
/// Trail-Metern je Sekunde Umweg, ohne Blick auf die Lage.
List<Trail> funPoolOf(List<Trail> trails, LatLng from, LatLng to, {String? exceptId}) {
  double d(LatLng a, LatLng b) => haversineM(a.latitude, a.longitude, b.latitude, b.longitude);
  final line = d(from, to);
  double excess(LatLng p) => d(from, p) + d(p, to) - line;
  final scored = <(Trail, double)>[
    for (final t in loopPoolOf(trails, from, reachM: double.infinity).inReach)
      if (t.id != exceptId)
        if (math.max(excess(t.start), excess(t.end)) case final e when e <= 2 * kFunPoolSlackM) (t, e),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final (t, _) in scored.take(kFunPoolMax)) t];
}
