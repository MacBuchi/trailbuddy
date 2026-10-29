// Das Höhenprofil einer geplanten Linie im Ergebnis (#234, Feldwunsch:
// „das Höhenmeterprofil über die Distanz kompakt im unteren Bereich").
// Eine Stelle für das Blatt „Runde" und das Blatt „Zum Trailkopf" /
// „Route hierher": dieselbe Zeichnung wie im Trail-Blatt, kompakt, aus
// dem Geländemodell entlang der Linie (`lineProfileProvider`) — die Engine
// kennt Höhen je Kante, nicht je Punkt.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../core/app_colors.dart';
import '../trails/elevation_profile_chart.dart';
import '../trails/terrain_heights.dart';
import 'route_progress.dart' show NavRoute;

/// Die Stelle, die im Profil gewählt ist (#332): Meter ab Start im
/// Profil und derselbe Ort auf der Linie. Die Karte setzt dort das
/// Symbol ([RouteCursorSymbol]); null ohne Wahl.
///
/// Die Kamera folgt NICHT (Betreiber, 2026-10-15: „zentrieren ist
/// vielleicht nicht ideal und zu viel Unruhe") — die ganze Strecke bleibt
/// im Bild, nur das Symbol wandert.
typedef RouteProfileCursor = ({double alongM, LatLng point});

final routeProfileCursorProvider = StateProvider<RouteProfileCursor?>((ref) => null);

class RouteElevationProfile extends ConsumerStatefulWidget {
  const RouteElevationProfile(this.points, {super.key});

  /// Die Linie in Fahrtrichtung — dieselbe Liste, die die Karte zeichnet.
  final List<LatLng> points;

  @override
  ConsumerState<RouteElevationProfile> createState() => _RouteElevationProfileState();
}

class _RouteElevationProfileState extends ConsumerState<RouteElevationProfile> {
  // In initState geholt: Beim Abbau darf `ref` nicht mehr gelesen werden.
  late final StateController<RouteProfileCursor?> _cursor;
  NavRoute? _line;

  @override
  void initState() {
    super.initState();
    _cursor = ref.read(routeProfileCursorProvider.notifier);
  }

  @override
  void didUpdateWidget(RouteElevationProfile old) {
    super.didUpdateWidget(old);
    // Eine neue Linie (neu gerechnet, Zwischenpunkt gezogen): Die alte
    // Stelle läge irgendwo daneben.
    if (!identical(old.points, widget.points)) {
      _line = null;
      _clearLater();
    }
  }

  @override
  void dispose() {
    _clearLater();
    super.dispose();
  }

  /// Nicht während des Aufbaus oder Abbaus in einen Provider schreiben —
  /// Riverpod verbietet das; einen Mikrotakt später ist es erlaubt.
  void _clearLater() {
    final c = _cursor;
    scheduleMicrotask(() {
      if (c.mounted) c.state = null;
    });
  }

  void _scrub(double alongM, double profileLengthM) {
    final line = _line ??= NavRoute.of(widget.points);
    if (line == null || !(profileLengthM > 0) || !alongM.isFinite) return;
    // Das Profil misst entlang seiner Proben, die Linie entlang ihrer
    // Punkte — anteilig umgerechnet treffen beide dieselbe Stelle.
    _cursor.state = (alongM: alongM, point: line.pointAt(alongM / profileLengthM * line.lengthM));
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(lineProfileProvider(widget.points));
    final cursor = ref.watch(routeProfileCursorProvider);
    return switch (profile) {
      // Während gelesen wird, steht der Platz schon da — sonst rutschten
      // die Knöpfe darunter, sobald das Profil kommt.
      AsyncLoading() => const SizedBox(height: ElevationProfileChart.compactHeight + 24),
      AsyncData(value: final p?) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ElevationProfileChart(
            p,
            compact: true,
            cursorM: cursor?.alongM,
            onScrub: (m) => _scrub(m, p.lengthM),
          ),
        ),
      // Ohne Höhen (eine Kachel fehlt) kein Profil — die Summe sagt dann
      // schon, dass die Höhenmeter eine Untergrenze sind. Ein Lesefehler
      // nimmt nur das Bild weg, nie das Ergebnis.
      _ => const SizedBox.shrink(),
    };
  }
}

/// Das Symbol der gewählten Stelle auf der Karte (#332): Lime-Scheibe mit
/// dunklem Rand und Mountainbike — wie die Startfahne Lime mit Kontur,
/// damit es auf der immer hellen Karte und auf der Lime-Route steht.
class RouteCursorSymbol extends StatelessWidget {
  const RouteCursorSymbol({super.key});

  static const size = 30.0;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.brand,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.onBrand, width: 2),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 4)],
        ),
        child: const CustomPaint(size: Size.square(20), painter: MtbGlyphPainter(AppColors.onBrand)),
      );
}

/// Ein Mountainbike in 20 × 20 (Betreiber, 2026-10-29: das Rad „ein wenig
/// MTB-mäßiger"): dicke Reifen, abfallendes Oberrohr, Federgabel, breiter
/// Lenker. Material kennt nur Stadt- und E-Rad (`directions_bike`,
/// `pedal_bike`), deshalb gezeichnet. Maße in Zwanzigsteln der Kante.
class MtbGlyphPainter extends CustomPainter {
  const MtbGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.shortestSide / 20;
    Offset p(double x, double y) => Offset(x * k, y * k);
    Paint stroke(double w) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Reifen: breiter Strich als Stollenreifen.
    final tyre = stroke(2.2);
    canvas.drawCircle(p(4.9, 14), 3.6 * k, tyre);
    canvas.drawCircle(p(15.1, 14), 3.6 * k, tyre);
    final rear = p(4.9, 14), bb = p(9.4, 14), seat = p(8.0, 9.0), head = p(13.2, 7.4), headLow = p(13.7, 9.4);
    final frame = Path()
      ..moveTo(rear.dx, rear.dy)
      ..lineTo(bb.dx, bb.dy)
      ..lineTo(seat.dx, seat.dy)
      ..close()
      ..moveTo(bb.dx, bb.dy)
      ..lineTo(headLow.dx, headLow.dy)
      ..lineTo(head.dx, head.dy)
      // Oberrohr fällt nach hinten ab.
      ..lineTo(seat.dx, seat.dy);
    canvas.drawPath(frame, stroke(1.5));
    // Federgabel: dicker als der Rahmen.
    canvas.drawLine(headLow, p(15.1, 14), stroke(2.1));
    // Sattelstütze und Sattel.
    canvas.drawLine(seat, p(7.6, 7.0), stroke(1.5));
    canvas.drawLine(p(6.2, 6.8), p(8.8, 6.8), stroke(1.6));
    // Vorbau und breiter Lenker.
    canvas.drawLine(head, p(13.6, 5.6), stroke(1.5));
    canvas.drawLine(p(12.0, 5.4), p(16.2, 5.0), stroke(1.6));
  }

  @override
  bool shouldRepaint(MtbGlyphPainter old) => old.color != color;
}
