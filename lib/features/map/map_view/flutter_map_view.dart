import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;

import '../../../core/connectivity.dart';
import '../../offline_areas/area_providers.dart';
import '../base_map_providers.dart';
import '../finite_camera_constraint.dart';
import '../online_map.dart';
import '../way_layer.dart';
import 'line_labels.dart';
import 'map_view.dart';

/// Die flutter_map-Engine: der Web-Pfad und der Rückfall auf Android,
/// wenn der MapLibre-Style nicht baut. Online die Vektorkarte vom Host
/// (`online_map.dart`, kachelweise per Range-Anfrage); darunter die
/// mitgelieferte Übersicht, sobald kein Empfang besteht oder die
/// Online-Karte nicht aufgeht.
class FlutterMapView extends ConsumerStatefulWidget {
  const FlutterMapView({
    super.key,
    required this.config,
    required this.controller,
    required this.layers,
  });

  final MapViewConfig config;
  final MapViewController controller;
  final MapViewLayers layers;

  @override
  ConsumerState<FlutterMapView> createState() => _FlutterMapViewState();
}

class _FlutterMapViewState extends ConsumerState<FlutterMapView>
    implements MapViewCameraDelegate {
  final _mapController = MapController();

  MapViewCamera _cameraOf(MapCamera camera) {
    final b = camera.visibleBounds;
    return MapViewCamera(
      center: camera.center,
      bounds: MapViewBounds(
          west: b.west, east: b.east, south: b.south, north: b.north),
      size: camera.nonRotatedSize,
    );
  }

  void _reportIdle(MapCamera camera) =>
      widget.config.onCameraIdle?.call(_cameraOf(camera));

  @override
  void initState() {
    super.initState();
    widget.controller.attach(this);
  }

  @override
  void didUpdateWidget(covariant FlutterMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.detach(this);
      widget.controller.attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller.detach(this);
    _mapController.dispose();
    super.dispose();
  }

  // ---- MapViewCameraDelegate ----
  @override
  void move(LatLng center, double zoom) => _mapController.move(center, zoom);

  @override
  void fit(List<LatLng> points, {required double padding, required double maxZoom, double bottomInset = 0}) {
    _mapController.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(points),
      padding: EdgeInsets.fromLTRB(padding, padding, padding, padding + bottomInset),
      maxZoom: maxZoom,
    ));
  }

  @override
  LatLng get center => _mapController.camera.center;

  @override
  double get zoom => _mapController.camera.zoom;

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final layers = widget.layers;
    // Die Online-Karte — null, solange kein Manifest da ist oder das
    // Archiv nicht aufgeht (dann bleibt die Übersicht die Karte).
    final online = ref.watch(onlineMapStyleProvider).valueOrNull;
    // Die Übersicht nur, wenn sie gebraucht wird: ohne Empfang oder ohne
    // Online-Karte — siehe base_map_providers.dart. Dieselbe Regel wie in
    // der MapLibre-Engine (maplibre_style_provider.dart).
    final showBaseMap = online == null || ref.watch(noConnectivityProvider);
    final baseStyle =
        showBaseMap ? ref.watch(baseMapStyleProvider).valueOrNull : null;
    // Die gespeicherten Bereiche IMMER, zuoberst (#82) — dieselbe Regel
    // wie in der MapLibre-Engine, Begründung in area_providers.dart.
    final areas = ref.watch(areaMapStyleProvider).valueOrNull;
    // Die Wege (#212) über allen Kartenschichten, unter den Trails —
    // dieselbe Reihenfolge wie im MapLibre-Stil.
    final ways = ref.watch(onlineWaysStyleProvider).valueOrNull;
    // Darüber die Wege der gespeicherten Bereiche, mit und ohne Empfang.
    final areaWays = ref.watch(areaWaysStyleProvider).valueOrNull;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: config.initialCenter,
        initialZoom: config.initialZoom,
        minZoom: config.minZoom,
        maxZoom: config.maxZoom,
        backgroundColor: config.backgroundColor,
        // Norden bleibt oben: Eine gedrehte Karte passiert beim Zoomen
        // mit zwei Fingern aus Versehen, und zurückdrehen kann man sie
        // ohne Kompass nicht.
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        // NaN-/Infinity-Kamerazustände aus Gesten-Grenzfällen verwerfen
        // (PilzBuddy #141/#151) — Details am Wächter.
        cameraConstraint: const FiniteCameraConstraint(),
        onTap: (tapPosition, latLng) {
          final camera = _mapController.camera;
          config.handleTap(
            MapTap(
              point: latLng,
              screenPoint: tapPosition.relative ??
                  camera.latLngToScreenOffset(latLng),
              camera: _cameraOf(camera),
            ),
            layers,
          );
        },
        onLongPress: (tapPosition, latLng) {
          final camera = _mapController.camera;
          config.onLongPress?.call(MapTap(
            point: latLng,
            screenPoint: tapPosition.relative ?? camera.latLngToScreenOffset(latLng),
            camera: _cameraOf(camera),
          ));
        },
        onMapReady: () => _reportIdle(_mapController.camera),
        onMapEvent: (event) {
          // „Zum Stehen gekommen": Gesten- und Animationsenden, nicht
          // jede Bewegung. Das Mausrad hat kein Ende-Ereignis, sein
          // Einzelschritt IST der Stillstand.
          if (event is MapEventMoveEnd ||
              event is MapEventFlingAnimationEnd ||
              event is MapEventDoubleTapZoomEnd ||
              event is MapEventScrollWheelZoom) {
            _reportIdle(event.camera);
          }
        },
      ),
      children: [
        if (baseStyle != null)
          vmt.VectorTileLayer(
            key: const ValueKey('base-map'),
            tileProviders: baseStyle.tileProviders,
            theme: baseStyle.theme,
            // Raster, nicht Vektor (PilzBuddy #119): Der Vektor-Modus
            // rendert bei jeder Zwischen-Zoomstufe neu, und diese Schicht
            // endet bei Zoom 7 — es gibt keine Schärfe zu verlieren.
            layerMode: vmt.VectorTileLayerMode.raster,
            maximumTileSubstitutionDifference: 1,
          ),
        if (online != null)
          vmt.VectorTileLayer(
            // Der Schlüssel hängt an der QUELLE (PilzBuddy #144): Ein
            // neues Archiv (neues Manifest) bekommt einen frischen Layer
            // mit frischen Caches, statt Kacheln aus dem geschlossenen
            // alten zu verlangen.
            key: ValueKey(online.tileProviders),
            tileProviders: online.tileProviders,
            theme: online.theme,
            // Vektor-Modus rendert scharf in jeder Zoomstufe; die Daten
            // enden bei Zoom 13, darüber wird skaliert.
            layerMode: vmt.VectorTileLayerMode.vector,
            maximumZoom: 19,
            maximumTileSubstitutionDifference: 1,
          ),
        if (areas != null)
          vmt.VectorTileLayer(
            key: ValueKey(areas.tileProviders),
            tileProviders: areas.tileProviders,
            theme: areas.theme,
            layerMode: vmt.VectorTileLayerMode.vector,
            maximumZoom: 19,
            // Keine Ersatzkachel: Eine Kachel außerhalb des Bereichs fehlt
            // mit Absicht, und ihre gröbere Elternkachel aus dem Bereich
            // läge sonst über der schärferen Online-Kachel darunter.
            maximumTileSubstitutionDifference: 0,
          ),
        if (ways != null)
          vmt.VectorTileLayer(
            key: ValueKey(ways.tileProviders),
            tileProviders: ways.tileProviders,
            theme: ways.theme,
            layerMode: vmt.VectorTileLayerMode.vector,
            maximumZoom: 19,
            // Unter Zoom 13 gibt es keine Kachel; eine Ersatzkachel aus
            // einer anderen Stufe gibt es also auch nicht.
            maximumTileSubstitutionDifference: 0,
          ),
        if (areaWays != null)
          vmt.VectorTileLayer(
            key: ValueKey(areaWays.tileProviders),
            tileProviders: areaWays.tileProviders,
            theme: areaWays.theme,
            layerMode: vmt.VectorTileLayerMode.vector,
            maximumZoom: 19,
            maximumTileSubstitutionDifference: 0,
          ),
        if (layers.polygons.isNotEmpty)
          PolygonLayer(polygons: [
            for (final p in layers.polygons)
              Polygon(
                points: p.points,
                holePointsList: p.holes.isEmpty ? null : p.holes,
                color: p.fillColor,
                borderColor: p.borderColor ?? Colors.transparent,
                borderStrokeWidth: p.borderWidth,
                // Kein Rand um die Löcher: Die gespeicherten Kacheln
                // sollen hell sein, nicht umrahmt.
                disableHolesBorder: true,
              ),
          ]),
        if (layers.circles.isNotEmpty)
          CircleLayer(circles: [
            for (final c in layers.circles)
              CircleMarker(
                point: c.center,
                radius: c.radiusM,
                useRadiusInMeter: true,
                color: c.fillColor,
                borderColor: c.borderColor ?? Colors.transparent,
                borderStrokeWidth: c.borderWidth,
              ),
          ]),
        if (layers.polylines.isNotEmpty)
          PolylineLayer(
            polylines: [
              for (final line in layers.polylines)
                // Ein Rand mit eigenem Muster (S4/S5, #101) ist eine eigene,
                // breitere Linie darunter — flutter_maps Rand teilt sonst
                // das Muster der Linie.
                if (line.borderDash != null && line.borderColor != null && line.borderWidth > 0) ...[
                  Polyline(
                    points: line.points,
                    color: line.borderColor!,
                    strokeWidth: line.width + 2 * line.borderWidth,
                    pattern: StrokePattern.dashed(segments: line.borderDash!),
                  ),
                  Polyline(
                    points: line.points,
                    color: line.color,
                    strokeWidth: line.width,
                    pattern: line.dash == null
                        ? const StrokePattern.solid()
                        : StrokePattern.dashed(segments: line.dash!),
                  ),
                ] else
                  Polyline(
                    points: line.points,
                    color: line.color,
                    strokeWidth: line.width,
                    pattern: line.dash == null
                        ? const StrokePattern.solid()
                        : StrokePattern.dashed(segments: line.dash!),
                    borderStrokeWidth: line.borderWidth,
                    borderColor: line.borderColor ?? Colors.transparent,
                  ),
            ],
          ),
        // Namen der Linien — flutter_map kann keinen Text entlang eines
        // Pfads, also einmal in der Mitte, gedreht (`lineLabelAnchor`).
        if (layers.polylines.any((l) => l.label != null))
          IgnorePointer(child: _LineLabels(layers.polylines)),
        if (layers.markers.isNotEmpty)
          // Kein Tipp am Marker: Die Fassade löst Tipps auf (map_view.dart).
          IgnorePointer(
            child: MarkerLayer(markers: [
              for (final m in layers.markers)
                Marker(
                  key: m.key,
                  point: m.point,
                  width: m.width,
                  height: m.height,
                  alignment: m.alignment,
                  child: m.child,
                ),
            ]),
          ),
        // Steht links die Werkzeugleiste, rückt der Hinweis neben sie.
        Padding(
          padding: EdgeInsets.only(left: config.bottomLeftInset),
          child: RichAttributionWidget(
            // Links wie bei MapLibre: rechts stehen die Knöpfe (seit 0.27.0).
            alignment: AttributionAlignment.bottomLeft,
            animationConfig: const ScaleRAWA(),
            attributions: [
              const TextSourceAttribution('OpenStreetMap-Mitwirkende'),
              const TextSourceAttribution('Protomaps', prependCopyright: false),
              for (final text in config.attributions)
                TextSourceAttribution(text, prependCopyright: false),
            ],
          ),
        ),
      ],
    );
  }
}


/// Die Liniennamen ab [kLineLabelMinZoom] — liest Zoom und Linien aus dem
/// Karten-Kontext, damit ein Herauszoomen sie ohne Neuaufbau der Karte
/// wegnimmt.
class _LineLabels extends StatelessWidget {
  const _LineLabels(this.lines);

  final List<MapViewPolyline> lines;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    if (camera.zoom < kLineLabelMinZoom) return const SizedBox.shrink();
    return MarkerLayer(markers: [
      for (final l in lines)
        if (l.label != null)
          if (lineLabelAnchor(l.points) case final a?)
            Marker(
              point: a.point,
              width: 12.0 * l.label!.length * 0.62 + 12,
              height: 36,
              child: Transform.rotate(
                angle: a.angle,
                // AUF der Mittellinie wie bei MapLibre (#181).
                child: Center(child: _HaloText(l.label!)),
              ),
            ),
    ]);
  }
}

/// Dunkle Schrift mit weißem Saum — die Karte ist immer hell.
class _HaloText extends StatelessWidget {
  const _HaloText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1);
    return Stack(children: [
      Text(text,
          maxLines: 1,
          style: base.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                // Der Strich liegt zur Hälfte unter der Schrift.
                ..strokeWidth = 2 * kLineLabelHaloWidth
                ..color = Colors.white)),
      Text(text, maxLines: 1, style: base.copyWith(color: const Color(0xFF131A16))),
    ]);
  }
}
