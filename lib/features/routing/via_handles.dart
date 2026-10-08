// Die Zwischenpunkte auf der Karte (#234): der Punkt selbst ist ein
// Marker der Engine (er wandert mit der Karte), angefasst wird er über
// einen Griff in einer Fläche ÜBER der Karte. Marker nehmen auf beiden
// Engines keine Gesten an (die Fassade löst Tipps auf, `map_view.dart`) —
// und eine ganze Zeichenfläche wie beim Gebiet hielte die Karte fest.
//
// Drei Dinge, die man wissen muss:
// - **Nur die Griffe fangen Berührungen**, je 44 dp um einen Punkt; der
//   Rest der Fläche lässt alles zur Karte durch (ein `Stack` ohne
//   Hintergrund trifft nur seine Kinder). Schieben und Zoomen bleiben frei.
// - **Die Lage kommt von der Kamera des letzten Stillstands**, wie beim
//   Zeichnen (`area_draw_overlay.dart`). Während die Karte gleitet, liegen
//   die Griffe kurz daneben; beim nächsten Stillstand stimmen sie wieder.
// - **Gezogen wird ein Abbild**: Der Marker bleibt an der alten Stelle,
//   bis die Route neu gerechnet ist — man sieht, woher der Punkt kommt.
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../map/map_view/map_hit_test.dart';
import '../map/map_view/map_view.dart';
import 'route_vias.dart';

/// Kantenlänge eines Griffs — die Mindestgröße einer Berührfläche.
const kViaHandleSize = 44.0;

/// Durchmesser des sichtbaren Punkts.
const kViaDotSize = 18.0;

/// Der Punkt: weiß mit einem Rand in der Farbe der Route — er gehört zu
/// ihr. Die Karte ist immer hell, also kein Modus.
class ViaDot extends StatelessWidget {
  const ViaDot({super.key, this.lifted = false});

  /// Wird gerade gezogen: etwas größer, mit Schatten.
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final size = lifted ? kViaDotSize + 6 : kViaDotSize;
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.mapLines.ride, width: 4),
          boxShadow: const [BoxShadow(blurRadius: 4, offset: Offset(0, 1), color: Color(0x55000000))],
        ),
      ),
    );
  }
}

/// Die Marker der Punkte für die Karte.
List<MapViewMarker> viaMarkers(RouteVias vias) => [
      for (final (ref, p) in vias.all)
        MapViewMarker(
          key: ValueKey('via-${ref.leg}-${ref.index}'),
          point: p,
          width: kViaDotSize + 6,
          height: kViaDotSize + 6,
          child: const ViaDot(),
        ),
    ];

class ViaHandles extends StatefulWidget {
  const ViaHandles({
    super.key,
    required this.camera,
    required this.vias,
    required this.onMove,
    required this.onRemove,
  });

  final MapViewCamera camera;
  final RouteVias vias;
  final void Function(ViaRef ref, LatLng to) onMove;
  final void Function(ViaRef ref) onRemove;

  @override
  State<ViaHandles> createState() => _ViaHandlesState();
}

class _ViaHandlesState extends State<ViaHandles> {
  ViaRef? _dragging;
  Offset? _at;

  void _end() {
    final ref = _dragging, at = _at;
    setState(() {
      _dragging = null;
      _at = null;
    });
    if (ref != null && at != null) widget.onMove(ref, unprojectFromScreen(widget.camera, at));
  }

  @override
  Widget build(BuildContext context) {
    final half = kViaHandleSize / 2;
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final (ref, p) in widget.vias.all)
          if (projectToScreen(widget.camera, p) case final pt)
            Positioned(
              left: pt.dx - half,
              top: pt.dy - half,
              width: kViaHandleSize,
              height: kViaHandleSize,
              child: GestureDetector(
                key: ValueKey('via-handle-${ref.leg}-${ref.index}'),
                behavior: HitTestBehavior.opaque,
                // Ab dem ersten Kontakt: Der Punkt bleibt unter dem Finger,
                // die Schwelle der Geste geht nicht verloren.
                dragStartBehavior: DragStartBehavior.down,
                onTap: () => widget.onRemove(ref),
                onPanStart: (d) => setState(() {
                  _dragging = ref;
                  _at = pt;
                }),
                onPanUpdate: (d) => setState(() => _at = (_at ?? pt) + d.delta),
                onPanEnd: (_) => _end(),
                onPanCancel: () => setState(() {
                  _dragging = null;
                  _at = null;
                }),
              ),
            ),
        if (_at case final at?)
          Positioned(
            left: at.dx - half,
            top: at.dy - half,
            width: kViaHandleSize,
            height: kViaHandleSize,
            child: const IgnorePointer(child: ViaDot(key: ValueKey('via-lifted'), lifted: true)),
          ),
      ],
    );
  }
}

/// Die Zeile im Ergebnis-Blatt: wie man tunt — oder, wenn getunt ist,
/// dass es so ist, mit „Zurücksetzen".
class RouteTuneNote extends StatelessWidget {
  const RouteTuneNote({super.key, required this.tuned, required this.onReset, required this.keyPrefix});

  final bool tuned;
  final VoidCallback onReset;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(color: theme.hintColor);
    if (!tuned) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          key: ValueKey('$keyPrefix-tune-hint'),
          'Tipp auf die Linie setzt einen Zwischenpunkt — ziehen verschiebt ihn, ein Tipp nimmt ihn weg.',
          style: style,
        ),
      );
    }
    return Row(
      children: [
        Expanded(child: Text('Von Hand angepasst', key: ValueKey('$keyPrefix-tuned'), style: style)),
        TextButton(
          key: ValueKey('$keyPrefix-tune-reset'),
          onPressed: onReset,
          child: const Text('Zurücksetzen'),
        ),
      ],
    );
  }
}
