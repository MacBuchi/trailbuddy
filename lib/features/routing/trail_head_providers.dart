// Die Naht zwischen Trail-Blatt (oder Navi-Symbol) und Karte für „Zum
// Trailkopf" (#158 Schritt 4). Das Blatt stellt den WUNSCH (die Kennung),
// die Karte löst ihn ein — wie der Fokus-Wunsch (`mapFocusTrailProvider`):
// Das Blatt kann über dem Reiter „Trails" offen sein, das Ergebnis gehört
// aber auf die Karte, und die rechnet erst, wenn sie zu sehen ist. Seit
// #356 PR 7 ist das der Planer mit dem Trailkopf als Ziel.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'loop_planner.dart' show RouteMode;

// Der Stil (Direkt, Spaßig, Bequem) steht seit #356 beim Planer, der ihn
// sich merkt; hier weitergereicht, damit die Blätter ihn wie bisher finden.
export 'loop_planner.dart' show RouteMode;

/// Der Trail, zu dessen Kopf die Karte den Weg zeigen soll, und in welchem
/// Stil — null heißt der gemerkte des Planers. Die Karte nimmt den Wunsch
/// und setzt ihn auf null.
typedef TrailHeadRequest = ({String trailId, RouteMode? mode});

final trailHeadRequestProvider = StateProvider<TrailHeadRequest?>((ref) => null);
