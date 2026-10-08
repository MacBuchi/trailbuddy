import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/map/map_view/map_hit_test.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';

/// Karten-Fake für Widget-Tests: rendert die Marker-Kinder in einem
/// `Wrap` — nicht überlappend, damit `find.byKey(...)`-Taps das richtige
/// Widget treffen — und simuliert die Kamera synchron. Keine Kacheln,
/// kein Netz, keine Engine.
///
/// `pumpApp` hängt sie standardmäßig hinter die [mapViewBuilderProvider]-
/// Fassade; Tests, die flutter_map-Interna beweisen, pumpen mit
/// `useRealMap: true`.
///
/// **Tipps gehen denselben Weg wie in den echten Engines:** Ein Tipp auf
/// ein Marker-Kind wird zu einem [MapTap] an der Stelle des Markers und
/// durch [MapViewConfig.handleTap] aufgelöst — die Trefferprüfung der
/// Fassade läuft also mit, samt ihrer Regel „Linie vor Nadel".
class FakeMapView extends StatefulWidget {
  const FakeMapView({
    super.key,
    required this.config,
    required this.controller,
    required this.layers,
  });

  final MapViewConfig config;
  final MapViewController controller;
  final MapViewLayers layers;

  @override
  State<FakeMapView> createState() => FakeMapViewState();
}

/// Öffentlich, damit Tests die simulierte Kamera abfragen können
/// (`tester.state<FakeMapViewState>(...)`).
class FakeMapViewState extends State<FakeMapView>
    implements MapViewCameraDelegate {
  late LatLng _center = widget.config.initialCenter;
  late double _zoom = widget.config.initialZoom;
  Size _size = const Size(800, 600);

  /// Der verdeckte Rand unten beim letzten Einpassen — ein Blatt über der
  /// Karte; Tests prüfen damit, dass die Route ÜBER dem Blatt landet.
  double lastFitBottomInset = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.attach(this);
    // Wie die echten Engines: Nach dem Aufbau steht die Kamera einmal.
    _idleAfterFrame();
  }

  @override
  void dispose() {
    widget.controller.detach(this);
    super.dispose();
  }

  void _idleAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.config.onCameraIdle?.call(camera);
    });
    // Ohne angeforderten Frame läuft der Rückruf erst, wenn zufällig
    // etwas anderes neu zeichnet — ein Test, der die Kamera bewegt,
    // prüfte sonst den alten Ausschnitt (so gefunden: die Gegenprobe zur
    // zoomfesten Hervorhebung blieb grün).
    WidgetsBinding.instance.scheduleFrame();
  }

  // ---- MapViewCameraDelegate ----
  @override
  void move(LatLng center, double zoom, {double bearing = 0}) {
    _center = center;
    this.bearing = bearing;
    // Wie die echte Karte: Zoom-Grenzen gelten auch für programmatische
    // Bewegungen.
    _zoom = zoom.clamp(widget.config.minZoom, widget.config.maxZoom);
    _idleAfterFrame();
  }

  @override
  void fit(List<LatLng> points, {required double padding, required double maxZoom, double bottomInset = 0}) {
    // DIESELBE Rechnung wie die MapLibre-Engine (#68) — der Fake prüft
    // sie damit bei jedem Einpassen mit.
    lastFitBottomInset = bottomInset;
    bearing = 0;
    final cam = cameraToFit(points, _size,
        padding: padding, maxZoom: maxZoom, minZoom: widget.config.minZoom, bottomInset: bottomInset);
    _center = cam.center;
    _zoom = cam.zoom.clamp(widget.config.minZoom, widget.config.maxZoom);
    _idleAfterFrame();
  }

  /// Die Drehung der letzten Bewegung (#232) — die Fake zeichnet sie
  /// nicht, Tests lesen sie hier.
  double bearing = 0;

  @override
  LatLng get center => _center;

  @override
  double get zoom => _zoom;

  static double _mercY(double latDeg) {
    final lat = latDeg.clamp(-kMercatorMaxLat, kMercatorMaxLat) * math.pi / 180;
    return math.log(math.tan(math.pi / 4 + lat / 2));
  }

  /// Die Kamera, wie eine echte Engine sie bei Stillstand meldet —
  /// Web-Mercator mit 256er-Kacheln, gerechnet aus Mitte, Zoom und der
  /// Fläche des Fakes.
  MapViewCamera get camera {
    final scale = 256 * math.pow(2, _zoom) / (2 * math.pi);
    final cx = _center.longitude * math.pi / 180 * scale;
    final cy = _mercY(_center.latitude) * scale;
    final halfW = _size.width / 2, halfH = _size.height / 2;
    double lonOf(double x) => x / scale * 180 / math.pi;
    double latOf(double y) => (2 * math.atan(math.exp(y / scale)) - math.pi / 2) * 180 / math.pi;
    return MapViewCamera(
      center: _center,
      bounds: MapViewBounds(
        west: lonOf(cx - halfW),
        east: lonOf(cx + halfW),
        south: latOf(cy - halfH),
        north: latOf(cy + halfH),
      ),
      size: _size,
    );
  }

  /// Ein Tipp auf die Stelle [point] — aufgelöst wie in den Engines.
  void tapAt(LatLng point) {
    final cam = camera;
    widget.config.handleTap(
      MapTap(point: point, screenPoint: projectToScreen(cam, point), camera: cam),
      widget.layers,
    );
  }

  /// Ein langer Druck auf [point] — wie die Engines: immer der Punkt.
  void longPressAt(LatLng point) {
    final cam = camera;
    widget.config.onLongPress?.call(MapTap(point: point, screenPoint: projectToScreen(cam, point), camera: cam));
  }

  void _tapMarker(MapViewMarker m) {
    final cam = camera;
    // Die Mitte der Markerfläche, nicht der Punkt: Bei `topCenter` liegt
    // der Punkt am unteren Rand der Nadel.
    final at = projectToScreen(cam, m.point) +
        Offset(0.5 * m.width * m.alignment.x, 0.5 * m.height * m.alignment.y);
    widget.config.handleTap(
      MapTap(point: m.point, screenPoint: at, camera: cam),
      widget.layers,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        if (constraints.hasBoundedWidth && constraints.hasBoundedHeight) {
          _size = constraints.biggest;
        }
        final l = widget.layers;
        return ColoredBox(
          color: widget.config.backgroundColor,
          child: Wrap(
            children: [
              // Linien als schlichte Kästchen: Der Fake zeichnet keine
              // Geometrie, aber eine Linie, die hier fehlt, wäre im Test
              // unsichtbar — genau der blinde Fleck, den er nicht haben
              // darf.
              for (final polygon in l.polygons)
                SizedBox(
                    width: 1,
                    height: 1,
                    child: ColoredBox(color: polygon.fillColor)),
              for (final line in l.polylines)
                SizedBox(
                    width: 1,
                    height: 1,
                    child: ColoredBox(color: line.color)),
              for (final marker in l.markers)
                GestureDetector(
                  onTap: () => _tapMarker(marker),
                  child: SizedBox(
                      width: marker.width,
                      height: marker.height,
                      child: KeyedSubtree(key: marker.key, child: marker.child)),
                ),
            ],
          ),
        );
      });
}

/// Die Ebenen, wie der Screen sie der Karte gerade gibt.
MapViewLayers fakeMapLayers(WidgetTester tester) =>
    tester.widget<FakeMapView>(find.byType(FakeMapView)).layers;

/// Die simulierte Kamera des Fakes.
FakeMapViewState fakeMap(WidgetTester tester) =>
    tester.state<FakeMapViewState>(find.byType(FakeMapView));

/// Ein Tipp auf die Karte an der Stelle [point], aufgelöst durch die
/// Trefferprüfung der Fassade — Linie vor Nadel, oberste zuerst.
Future<void> tapMapAt(WidgetTester tester, LatLng point) async {
  fakeMap(tester).tapAt(point);
  await tester.pump();
}

/// Ein langer Druck auf die Karte an der Stelle [point] (#177).
Future<void> longPressMapAt(WidgetTester tester, LatLng point) async {
  fakeMap(tester).longPressAt(point);
  await tester.pump();
}
