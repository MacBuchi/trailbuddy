// Nähte zwischen den Routen-Blättern und der Karte. Der Planer selbst hat
// seit 0.74.0 einen Controller (`loop_planner_controller.dart`); hier
// bleibt, was beide Blätter (Runde, Route) brauchen.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

/// Ein Blatt bittet die Karte, diese Punkte einzupassen — in die Fläche
/// ÜBER dem Blatt (`mapPanelInsetProvider`). Die Karte nimmt den Wunsch und
/// setzt ihn auf null. Seit 0.74.0 statt „einpassen, sobald die Vorschau
/// zum ersten Mal Linien hat": Das Blatt weiß, wann es soweit ist — nach
/// dem Einklappen, sonst läge die Route wieder darunter.
final mapFitRequestProvider = StateProvider<List<LatLng>?>((ref) => null);

/// Der Trailkopf als Start oder Ziel des Planers (#331 Schritt 2): ein
/// Wunsch des Trail-Blatts an die Karte, wie „Zum Trailkopf" — das Blatt
/// kann über dem Reiter „Trails" offen sein, der Planer gehört auf die
/// Karte. Die Karte nimmt den Wunsch und setzt ihn auf null.
typedef LoopTrailHeadRequest = ({String trailId, bool asTarget});

final loopTrailHeadRequestProvider = StateProvider<LoopTrailHeadRequest?>((ref) => null);
