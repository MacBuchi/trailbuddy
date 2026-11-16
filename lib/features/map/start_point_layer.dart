// Die Ebene „Startpunkte" (#543, `docs/konzept-startpunkte.md` 5.2):
// gemerkte Punkte als Pins über den Orten, eigene und die direkter
// Buddys. Wie bei den Orten zwei pure Schritte, die der Karten-Screen
// fährt: [shownStartPoints] wendet die 30-m-Regel an (Konzept 9.3: der
// eigene Punkt verdeckt einen fremden am selben Platz), und
// [startPointMarkers] baut die Marker der Fassade. Getippt wird über die
// Trefferprüfung der Fassade, der Pin fängt nichts.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/settings.dart';
import '../../l10n/l10n.dart';
import '../../models/start_point.dart';
import '../trails/trail_geometry.dart' show haversineM;
import 'map_view/map_view.dart';

/// Ab dieser (gerechneten) Zoomstufe stehen die Pins — darunter wäre ein
/// Parkplatz ein Fleck auf halb Bayern. Dieselbe Stufe, ab der die Orte
/// laden ([kPoiMinZoom] ist 12) wäre zu spät: Wer eine Runde im Tal plant,
/// soll seinen Parkplatz schon in der Talübersicht sehen.
const kStartPointMinZoom = 10.0;

/// Wie nah ein fremder Punkt an einem eigenen liegen darf, bevor der
/// eigene ihn verdeckt (Konzept 1 und 9.3) — keine Zusammenführung, kein
/// Zähler, nur ein Pin weniger.
const kStartPointSamePlaceM = 30.0;

/// Ist die Ebene an (Blatt „Ebenen")? Gerätelokal wie die übrigen Ebenen.
final startPointLayerEnabledProvider = NotifierProvider<RememberedFlag, bool>(
  () => RememberedFlag(
    read: (s) => s.startPointLayerEnabled,
    write: (s, v) => s.setStartPointLayerEnabled(v),
    label: 'Ebene Startpunkte merken',
  ),
);

/// Die Punkte, die gezeigt werden: alle eigenen, dazu jeder fremde, der
/// nicht innerhalb von [kStartPointSamePlaceM] an einem eigenen liegt.
/// Zwei fremde am selben Platz bleiben beide — sie gehören verschiedenen
/// Buddys, und zählen soll die Karte nicht (A1).
List<StartPoint> shownStartPoints(List<StartPoint> points, String? myId) {
  if (myId == null) return points;
  final own = [for (final p in points) if (p.isMine(myId)) p];
  if (own.isEmpty) return points;
  return [
    for (final p in points)
      if (p.isMine(myId) ||
          !own.any((o) => haversineM(o.lat, o.lon, p.lat, p.lon) <= kStartPointSamePlaceM))
        p,
  ];
}

/// Die Pins im Ausschnitt — leer unter [kStartPointMinZoom]. Ein Tipp
/// meldet den [StartPoint].
List<MapViewMarker> startPointMarkers(List<StartPoint> points, MapViewCamera? camera, String? myId) {
  if (camera == null || camera.zoom < kStartPointMinZoom) return const [];
  return [
    for (final p in points)
      if (camera.bounds.contains(p.position))
        MapViewMarker(
          key: ValueKey('start-point-${p.key}'),
          point: p.position,
          width: StartPointPin.size,
          height: StartPointPin.size,
          hitValue: p,
          child: StartPointPin(own: myId != null && p.isMine(myId), pending: p.pending),
        ),
  ];
}

/// Der Pin eines Startpunkts: eine Fahne auf einer Scheibe — nicht die
/// Nadel der Orte, nicht das „P" der Parkplätze, damit er nicht wie ein
/// Ort der Karte aussieht. Eigene gefüllt in der Marke, fremde als Ring
/// in der Buddy-Farbe: Die Form trägt den Unterschied, nicht nur die
/// Farbe (A13). Die Karte ist immer hell ([AppColors.mapLines]).
/// Ein wartender Punkt (Ausgangskorb) steht halb durchsichtig.
class StartPointPin extends StatelessWidget {
  const StartPointPin({super.key, required this.own, this.pending = false});

  final bool own;
  final bool pending;

  static const size = 30.0;

  @override
  Widget build(BuildContext context) {
    const map = AppColors.mapLines;
    final color = own ? map.mine : map.buddy;
    return Semantics(
      label: own ? context.l10n.startPointOwn : context.l10n.startPointBuddy,
      child: Opacity(
        opacity: pending ? 0.55 : 1,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: own ? color : Colors.white,
            border: own ? Border.all(color: Colors.white, width: 2) : Border.all(color: color, width: 3.5),
            boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 3, offset: Offset(0, 1))],
          ),
          alignment: Alignment.center,
          child: Icon(own ? Icons.flag : Icons.outlined_flag, size: size * 0.55, color: own ? Colors.white : color),
        ),
      ),
    );
  }
}
