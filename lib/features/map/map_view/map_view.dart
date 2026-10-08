import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'flutter_map_view.dart';
import 'map_hit_test.dart';
// Web darf `package:maplibre` nie sehen — der Stub liefert dieselbe
// Signatur, die Engine-Wahl unten verzweigt dank `!kIsWeb` nie dorthin.
import 'maplibre_view_stub.dart'
    if (dart.library.io) 'maplibre_map_view.dart';

/// Engine-neutrale Fassade der Kartenansicht (#31, PilzBuddy-Muster).
///
/// `MapScreen` beschreibt nur noch, WAS die Karte zeigen soll
/// ([MapViewLayers]) und greift über [MapViewController] auf die Kamera
/// zu. WIE gerendert wird, entscheidet die Engine hinter
/// [mapViewBuilderProvider]: MapLibre auf Android, flutter_map im Web
/// und als Rückfall, im Test eine Fake ohne Kacheln. Alles, was über der
/// Karte liegt (Banner, Knöpfe, Blätter), bleibt gewöhnliche Flutter-UI
/// im Stack von `map_screen.dart` und weiß nichts von der Engine.
///
/// **Zwei Entscheidungen, die von PilzBuddy abweichen:**
///
/// 1. **Tipps löst die Fassade selbst auf** ([MapViewConfig.handleTap],
///    `map_hit_test.dart`), nicht die Engine. TrailBuddys Inhalt sind
///    Linien, und die beiden Engines treffen Linien verschieden
///    (flutter_map über `hitNotifier`, MapLibre über Style-Ebenen ohne
///    eigene Kennung). EINE geometrische Prüfung in Dart gibt auf beiden
///    dieselbe Antwort und lässt sich ohne Engine prüfen. Die Marker
///    tragen deshalb keinen eigenen `GestureDetector` mehr — auch ein
///    Tipp auf eine Nadel kommt hier an, und eine Linie darüber gewinnt.
/// 2. **Marker liegen immer ÜBER den Linien.** MapLibre kann Widgets nur
///    über seinen Style-Ebenen zeichnen; flutter_map folgt, damit beide
///    Engines dasselbe Bild zeigen. Was ein Tipp trifft, entscheidet
///    trotzdem die Prüfung (Linien zuerst), nicht die Zeichenreihenfolge.

/// Sichtfenster in Grad — engine-neutral, damit nichts am maplibre-Typ
/// `LngLatBounds` hängt (Web-Build) und alles ohne Platform-View prüfbar
/// bleibt.
@immutable
class MapViewBounds {
  const MapViewBounds({
    required this.west,
    required this.east,
    required this.south,
    required this.north,
  });

  final double west;
  final double east;
  final double south;
  final double north;

  bool contains(LatLng p) =>
      p.longitude >= west &&
      p.longitude <= east &&
      p.latitude >= south &&
      p.latitude <= north;
}

/// Die Kamera bei Stillstand: Mitte, Sichtfenster und die Pixelgröße der
/// Kartenfläche.
///
/// **Die Zoomstufe wird GERECHNET, nicht gemeldet.** MapLibre zählt Zoom
/// in 512er-Kacheln, flutter_map in 256ern — dieselbe Zahl hieße auf
/// Android und Web zwei Maßstäbe (PilzBuddy, 1.98.0). Aus Fenster und
/// Breite ist sie eindeutig: die 256er-Web-Mercator-Stufe, bei der das
/// Fenster genau die Breite füllt. Orte (ab 12) und offizielle Trails
/// (ab 8) hängen daran, also stimmen ihre Schwellen auf beiden Engines.
@immutable
class MapViewCamera {
  const MapViewCamera({
    required this.center,
    required this.bounds,
    required this.size,
  });

  final LatLng center;
  final MapViewBounds bounds;

  /// Die Kartenfläche in logischen Pixeln.
  final Size size;

  double get zoom => mapZoomFor(bounds, size.width);
}

/// Die 256er-Zoomstufe, bei der [bounds] genau [widthPx] breit ist.
double mapZoomFor(MapViewBounds bounds, double widthPx) {
  final span = bounds.east - bounds.west;
  if (span <= 0 || widthPx <= 0) return 0;
  return math.log(widthPx * 360 / (256 * span)) / math.ln2;
}

/// Ein Tipp auf die Karte: die Stelle, ihr Punkt auf der Kartenfläche
/// (LOKAL, nicht global) und die Kamera dazu — alles, was die
/// Trefferprüfung braucht.
@immutable
class MapTap {
  const MapTap({
    required this.point,
    required this.screenPoint,
    required this.camera,
  });

  final LatLng point;
  final Offset screenPoint;
  final MapViewCamera camera;
}

/// Was die Karte können muss — unabhängig von der Engine.
class MapViewConfig {
  const MapViewConfig({
    required this.initialCenter,
    required this.initialZoom,
    required this.minZoom,
    required this.maxZoom,
    required this.backgroundColor,
    this.attributions = const [],
    this.bottomLeftInset = 0,
    this.onTap,
    this.onHit,
    this.onLongPress,
    this.onCameraIdle,
  });

  final LatLng initialCenter;
  final double initialZoom;
  final double minZoom;
  final double maxZoom;

  /// Fläche, wo (noch) keine Kachel liegt — Landton statt „kaputtem" Grau.
  final Color backgroundColor;

  /// Die Zeilen des Quellenhinweises (ODbL-Pflicht), über die
  /// Kartenquellen hinaus, die jede Engine selbst nennt: hier die
  /// Behörden hinter den offiziellen Trails.
  final List<String> attributions;

  /// Wie weit Maßstab und Quellenhinweis (unten links) nach rechts
  /// rücken — solange links die Werkzeugleiste steht, neben sie (3e).
  final double bottomLeftInset;

  /// Tipp ins Leere — keine Linie, kein Marker getroffen.
  final void Function(MapTap tap)? onTap;

  /// Tipp auf etwas mit Kennung ([MapViewPolyline.hitValue],
  /// [MapViewMarker.hitValue]). Was die Kennung ist, entscheidet der
  /// Screen (Trail, offizieller Trail, Ort).
  final void Function(Object hitValue, MapTap tap)? onHit;

  /// Langer Druck auf die Karte (#177) — IMMER der Punkt, auch auf einer
  /// Linie: Das Menü daran („Route ab hier", „Route bis hier") gilt dem
  /// Ort, nicht dem, was dort liegt. Beide Engines melden ihn selbst.
  final void Function(MapTap tap)? onLongPress;

  /// Die Karte ist zum Stehen gekommen. BEWUSST nur bei Stillstand: Daran
  /// hängen das Nachladen der Orte und der offiziellen Trails — beides
  /// soll die Geste nicht begleiten, sondern ihr folgen.
  final void Function(MapViewCamera camera)? onCameraIdle;

  /// Der eine Weg, auf dem eine Engine einen Tipp meldet: Die Fassade
  /// prüft ihn gegen [layers] (Linien zuerst, dann Marker, jeweils die
  /// oberste gewinnt) und ruft [onHit] oder [onTap].
  void handleTap(MapTap tap, MapViewLayers layers) {
    final hit = resolveMapTap(layers, tap);
    if (hit != null) {
      onHit?.call(hit, tap);
    } else {
      onTap?.call(tap);
    }
  }
}

/// Ein Marker: Position, Maße, Widget-Kind. Wie er auf die Karte kommt
/// (flutter_map-MarkerLayer, MapLibre-WidgetLayer, Fake-Wrap), entscheidet
/// die Engine. Das Kind fängt keine Tipps — siehe Kopf der Datei.
class MapViewMarker {
  const MapViewMarker({
    this.key,
    required this.point,
    required this.width,
    required this.height,
    this.alignment = Alignment.center,
    required this.child,
    this.hitValue,
  });

  /// Für Tests: der Schlüssel, unter dem das Kind im Baum steht.
  final Key? key;
  final LatLng point;
  final double width;
  final double height;

  /// Wie beim flutter_map-Marker: Wo der Marker relativ zum Punkt hängt.
  /// `topCenter` = der Punkt liegt am unteren Rand (die Nadelspitze sitzt
  /// darauf).
  final Alignment alignment;
  final Widget child;

  /// Was ein Tipp meldet; null heißt nicht antippbar (eigene Position).
  final Object? hitValue;
}

/// Ein Linienzug. Farbe, Breite, Strich und Rand hängen an der LINIE,
/// nicht an einer Ebene — flutter_map kann das je Linie, MapLibre trägt
/// es am Layer und bekommt deshalb eine Ebene je Stil (gruppiert, nicht
/// je Linie: ein Netz kann hunderte Trails haben).
/// Ab dieser (gerechneten, 256er) Zoomstufe stehen Linienbeschriftungen —
/// darunter sind die Trails zu kurz für ihren Namen.
const kLineLabelMinZoom = 14.0;

/// Der weiße Saum um Liniennamen, je Seite in Bildpunkten. Seit 0.74.2
/// steht der Name AUF der Linie (#181), und 1,5 px reichten auf einer
/// schwarzen S3-Linie nicht; MapLibre zeichnet höchstens ein Viertel der
/// Schriftgröße (12 px ⇒ 3 px). Beide Engines lesen diese Zahl.
const kLineLabelHaloWidth = 2.5;

class MapViewPolyline {
  const MapViewPolyline({
    required this.points,
    required this.color,
    this.width = 4,
    this.dash,
    this.borderColor,
    this.borderWidth = 0,
    this.borderDash,
    this.hitValue,
    this.label,
  });

  final List<LatLng> points;
  final Color color;
  final double width;

  /// Ein Name, der ENTLANG der Linie steht (der Trailname) — ab
  /// [kLineLabelMinZoom]. MapLibre setzt ihn wie einen Straßennamen und
  /// lässt ihn bei Platzmangel weg; flutter_map stellt ihn einmal in die
  /// Mitte, gedreht nach der Linie (`lineLabelAnchor`).
  final String? label;

  /// Strichmuster in Bildpunkten (Strich, Lücke, …); null = durchgezogen.
  final List<double>? dash;

  /// Ein Rand um die Linie (der gelbe Leuchtrand eines frischen
  /// Hinweises, #7). [borderWidth] ist die Breite JE SEITE.
  final Color? borderColor;
  final double borderWidth;

  /// Strichmuster des RANDS in Bildpunkten; null = durchgezogen. Eigenes
  /// Muster, weil der Saum seit #101 S4/S5 trägt, während die Linie den
  /// Zustand zeigt (Rework E9). Auf beiden Engines eine eigene Ebene
  /// unter der Linie.
  final List<double>? borderDash;

  /// Was ein Tipp meldet; null heißt nicht antippbar (die Fahrt).
  final Object? hitValue;

  /// Der Stil ohne Geometrie — MapLibre gruppiert danach.
  String get styleKey =>
      '${color.toARGB32()}|$width|${dash?.join(',') ?? ''}|'
      '${borderColor?.toARGB32() ?? ''}|$borderWidth|${borderDash?.join(',') ?? ''}';
}

/// Eine Fläche mit Löchern — die Abdunkelung außerhalb der gespeicherten
/// Kacheln (Offline-Karten, Stufe B): EIN Polygon über dem Ausschnitt,
/// die gespeicherten Kacheln sind die Löcher. Beide Engines können
/// Löcher (flutter_map `holePointsList`, MapLibre innere Ringe).
class MapViewPolygon {
  const MapViewPolygon({
    required this.points,
    this.holes = const [],
    required this.fillColor,
    this.borderColor,
    this.borderWidth = 0,
  });

  final List<LatLng> points;
  final List<List<LatLng>> holes;
  final Color fillColor;
  final Color? borderColor;
  final double borderWidth;
}

/// Eine Kreisfläche in METERN (der Genauigkeitskreis der Position).
/// Kein Pixelradius: Der Kreis soll mit der Karte wachsen.
class MapViewCircle {
  const MapViewCircle({
    required this.center,
    required this.radiusM,
    required this.fillColor,
    this.borderColor,
    this.borderWidth = 0,
  });

  final LatLng center;
  final double radiusM;
  final Color fillColor;
  final Color? borderColor;
  final double borderWidth;
}

/// Alles, was über der Karte liegt, in fester Zeichenreihenfolge (unten →
/// oben): Polygone < Kreise < Linien < Marker. Innerhalb jeder Liste gilt
/// die Reihenfolge der Liste — der Screen legt offizielle Trails vor das
/// Netz, damit das Netz obenauf liegt, und die Orte vor die eigene
/// Position. Die Abdunkelung liegt ganz unten: Linien und Marker bleiben
/// darüber lesbar.
class MapViewLayers {
  const MapViewLayers({
    this.polygons = const [],
    this.circles = const [],
    this.polylines = const [],
    this.markers = const [],
  });

  final List<MapViewPolygon> polygons;
  final List<MapViewCircle> circles;
  final List<MapViewPolyline> polylines;
  final List<MapViewMarker> markers;
}

/// Kamerazugriff der Engine — sie hängt sich beim Einbau per
/// [MapViewController.attach] ein.
abstract class MapViewCameraDelegate {
  /// [bearing]: wohin oben zeigt, in Grad ab Norden. Nur die Folgeansicht
  /// der Navigation dreht (#232, Konzept-Routing 9.2); jede andere
  /// Bewegung nordet die Karte wieder ein, und Gesten drehen nie.
  void move(LatLng center, double zoom, {double bearing = 0});

  /// Alle Punkte ins Bild — mit Rand und einer Obergrenze für den Zoom,
  /// damit ein 200-m-Trail nicht auf Hausnummern-Maßstab landet.
  /// [bottomInset]: so viele Pixel unten sind verdeckt (ein Blatt über
  /// der Karte) — eingepasst wird in die Fläche darüber (`cameraToFit`).
  void fit(List<LatLng> points, {required double padding, required double maxZoom, double bottomInset = 0});
  LatLng get center;
  double get zoom;
}

/// Engine-unabhängiger Griff an die Kamera für `MapScreen` („Meine
/// Position", Zoom auf das Netz oder einen Trail).
///
/// Vor dem Einbau der Engine antworten [center]/[zoom] mit den Startwerten
/// — dieselbe Semantik wie eine noch nicht bewegte Karte; ein [fit] vorher
/// wird beim Einbau nachgeholt.
class MapViewController {
  MapViewController({
    required LatLng initialCenter,
    required double initialZoom,
  })  : _center = initialCenter,
        _zoom = initialZoom;

  MapViewCameraDelegate? _delegate;
  LatLng _center;
  double _zoom;
  ({List<LatLng> points, double padding, double maxZoom, double bottomInset})? _pendingFit;

  void attach(MapViewCameraDelegate delegate) {
    _delegate = delegate;
    final fit = _pendingFit;
    if (fit != null) {
      _pendingFit = null;
      delegate.fit(fit.points, padding: fit.padding, maxZoom: fit.maxZoom, bottomInset: fit.bottomInset);
    }
  }

  /// Nur der aktuell eingehängte Delegate darf sich lösen — beim Wechsel
  /// der Engine läuft `attach` des Neuen vor `dispose` des Alten.
  void detach(MapViewCameraDelegate delegate) {
    if (identical(_delegate, delegate)) _delegate = null;
  }

  void move(LatLng center, double zoom, {double bearing = 0}) {
    final delegate = _delegate;
    if (delegate == null) {
      // Karte noch nicht da: Wunsch als neuen „Startzustand" merken.
      // Die Drehung nicht — bis zum ersten Fix der Folgeansicht ist das
      // eine Sekunde, und der nächste Fix dreht ohnehin.
      _center = center;
      _zoom = zoom;
      _pendingFit = null;
      return;
    }
    delegate.move(center, zoom, bearing: bearing);
  }

  void fit(List<LatLng> points, {double padding = 40, double maxZoom = 15, double bottomInset = 0}) {
    if (points.isEmpty) return;
    final delegate = _delegate;
    if (delegate == null) {
      _pendingFit = (points: points, padding: padding, maxZoom: maxZoom, bottomInset: bottomInset);
      return;
    }
    delegate.fit(points, padding: padding, maxZoom: maxZoom, bottomInset: bottomInset);
  }

  LatLng get center => _delegate?.center ?? _center;
  double get zoom => _delegate?.zoom ?? _zoom;
}

/// Baut die Kartenansicht einer konkreten Engine.
typedef MapViewBuilder = Widget Function(
  MapViewConfig config,
  MapViewController controller,
  MapViewLayers layers,
);

/// Die Engine-Wahl: **Android MapLibre, Web flutter_map.** `kIsWeb` ist
/// eine Kompilierzeit-Konstante, die Verzweigung also in jedem Build
/// schon entschieden — kein Schalter dazwischen (PilzBuddy hatte einen
/// und hat ihn nach zehn stillen Wochendigests wieder ausgebaut, #433).
///
/// `flutter_map_view.dart` bleibt trotzdem im Android-Build:
/// `maplibre_map_view.dart` fällt selbst darauf zurück, wenn der Style
/// nicht baut — ohne Style lieber die alte Karte als gar keine.
///
/// Tests überschreiben diesen Provider mit der Fake
/// (`test/fakes/fake_map_view.dart`) oder, wo flutter_map-Interna geprüft
/// werden, direkt mit [FlutterMapView] — die MapLibre-Platform-View ist
/// im Widget-Test nicht renderbar, ihr Gate ist das Gerät.
final mapViewBuilderProvider = Provider<MapViewBuilder>((ref) {
  if (!kIsWeb) {
    return (config, controller, layers) => createMapLibreMapView(
        config: config, controller: controller, layers: layers);
  }
  return (config, controller, layers) =>
      FlutterMapView(config: config, controller: controller, layers: layers);
});

/// Das Fassaden-Widget, das `MapScreen` einbaut.
class MapView extends ConsumerWidget {
  const MapView({
    super.key,
    required this.config,
    required this.controller,
    required this.layers,
  });

  final MapViewConfig config;
  final MapViewController controller;
  final MapViewLayers layers;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(mapViewBuilderProvider)(config, controller, layers);
}
