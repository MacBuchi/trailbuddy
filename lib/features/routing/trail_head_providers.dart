// Die Nähte zwischen Trail-Blatt, Karte und dem Blatt „Zum Trailkopf"
// (#158 Schritt 4). Das Trail-Blatt stellt den WUNSCH (die Kennung), die
// Karte löst ihn ein — wie der Fokus-Wunsch (`mapFocusTrailProvider`):
// Das Blatt kann über dem Reiter „Trails" offen sein, die Vorschau gehört
// aber auf die Karte, und die rechnet erst, wenn sie zu sehen ist.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../map/map_view/map_view.dart';
import 'loop_planner.dart' show RouteMode;

// Der Stil (Direkt, Spaßig, Bequem) steht seit #356 beim Planer, der ihn
// sich merkt; hier weitergereicht, damit die Blätter ihn wie bisher finden.
export 'loop_planner.dart' show RouteMode;

/// Der Trail, zu dessen Kopf die Karte den Weg zeigen soll, und wie; die
/// Karte nimmt den Wunsch und setzt ihn auf null.
typedef TrailHeadRequest = ({String trailId, RouteMode mode});

final trailHeadRequestProvider = StateProvider<TrailHeadRequest?>((ref) => null);

/// Die Vorschau der Route — gezeichnet vom Blatt, gemalt vom
/// Karten-Screen über der Fahrt und unter dem Netz; ohne Blatt leer.
final trailHeadPreviewProvider = StateProvider<List<MapViewPolyline>>((ref) => const []);
