import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_colors.dart';
import '../coach/coach.dart';
import '../help/map_tour.dart' show MapCoach;
import '../../models/trail.dart';
import '../official/official_trails_source.dart';
import '../trails/trail_filter_chips.dart';
import '../trails/trail_providers.dart';
import 'contour_providers.dart';
import 'map_view/map_view.dart';
import 'poi.dart';
import 'poi_source.dart';
import 'way_layer.dart';

/// Die Orte als Stecknadeln — seit der Kartenfassade (#31) keine Ebene
/// INNERHALB der Engine mehr, sondern zwei pure Schritte, die der
/// Karten-Screen bei Kamera-Stillstand fährt: [poiCellsFor] sagt, welche
/// Rasterzellen der Ausschnitt braucht (der Screen lädt sie kurz
/// verzögert nach, damit ein Wischen nicht zehn Abfragen auslöst), und
/// [poiMarkers] baut aus dem Geladenen die Marker der Fassade.

/// Die Zellen des Ausschnitts — oder null, wenn nichts zu laden ist
/// (keine Gruppe an, Ausschnitt unter [kPoiMinZoom]).
List<PoiCell>? poiCellsFor(MapViewCamera? camera, Set<PoiGroup> groups) {
  if (camera == null || groups.isEmpty || camera.zoom < kPoiMinZoom) return null;
  final b = camera.bounds;
  final cells = poiCellsCovering(b.south, b.west, b.north, b.east);
  // Mehr Zellen heißt, es wird gerade herausgezoomt — dann lieber gar
  // nicht fragen als halb Bayern.
  return cells.length > kPoiMaxCells ? null : cells;
}

/// Die sichtbaren Orte als Marker: geladen, im Ausschnitt, nicht per
/// Detailfilter ausgeblendet. Die Spitze der Nadel sitzt auf dem Ort, der
/// Kopf darüber; ein Tipp meldet den [Poi] (die Fassade prüft, die Nadel
/// selbst fängt nichts).
List<MapViewMarker> poiMarkers(
  PoiState state,
  MapViewCamera camera,
  List<PoiCell> cells,
  Set<PoiGroup> groups,
  Set<PoiKind> hidden,
) =>
    [
      for (final p in state.inCells(cells, groups))
        if (camera.bounds.contains(p.position) && !hidden.contains(p.kind))
          MapViewMarker(
            key: ValueKey('poi-${p.id}'),
            point: p.position,
            width: PoiPin.width,
            height: PoiPin.height,
            alignment: Alignment.topCenter,
            hitValue: p,
            child: PoiPin(kind: p.kind),
          ),
    ];

/// Eine Stecknadel: ein auf dem Kopf stehender Tropfen in der Farbe der
/// Gruppe, darin das Symbol der Art (Kuchen, Bierkrug, Schlüssel …).
class PoiPin extends StatelessWidget {
  const PoiPin({super.key, required this.kind});

  final PoiKind kind;

  static const width = 30.0;
  static const height = 40.0;

  @override
  Widget build(BuildContext context) => Semantics(
        label: kind.label,
        child: SizedBox(
          width: width,
          height: height,
          child: CustomPaint(
            painter: _PinPainter(kind.group.color),
            child: Align(
              alignment: const Alignment(0, -0.45),
              child: PoiGlyph(kind: kind, size: 17, background: kind.group.color),
            ),
          ),
        ),
      );
}

class _PinPainter extends CustomPainter {
  const _PinPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final r = w / 2 - 1.5;
    final c = Offset(w / 2, r + 1.5);
    // Kopf als Kreis, darunter zwei Bögen zur Spitze — der umgedrehte
    // Tropfen. Die Flanken treffen den Kreis tangential, daher die Kurven
    // statt gerader Linien.
    final path = Path()
      ..moveTo(w / 2, h - 1)
      ..quadraticBezierTo(c.dx - r * 0.35, c.dy + r * 1.25, c.dx - r, c.dy)
      ..arcToPoint(Offset(c.dx + r, c.dy),
          radius: Radius.circular(r), clockwise: true)
      ..quadraticBezierTo(c.dx + r * 0.35, c.dy + r * 1.25, w / 2, h - 1)
      ..close();
    canvas.drawShadow(path, Colors.black, 2, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_PinPainter old) => old.color != color;
}

/// Das Symbol einer Art, weiß auf [background]: ein Material-Symbol oder,
/// wo es keins gibt, gezeichnet (das Kuchenstück fürs Café).
class PoiGlyph extends StatelessWidget {
  const PoiGlyph(
      {super.key, required this.kind, required this.size, required this.background});

  final PoiKind kind;
  final double size;

  /// Die Farbe darunter — gezeichnete Symbole brauchen sie für ihre
  /// Binnenlinien (die Sahneschicht im Kuchen).
  final Color background;

  @override
  Widget build(BuildContext context) {
    final icon = kind.icon;
    if (icon != null) return Icon(icon, size: size, color: Colors.white);
    return CustomPaint(
      size: Size.square(size),
      painter: CakeSlicePainter(fill: Colors.white, cut: background),
    );
  }
}

/// Ein Stück Kuchen von der Seite: Keil mit Spitze links und Rand rechts,
/// eine Sahneschicht, oben eine Kirsche. Gezeichnet auf 24 × 24 wie die
/// Material-Symbole, damit es neben ihnen gleich groß wirkt.
class CakeSlicePainter extends CustomPainter {
  const CakeSlicePainter({required this.fill, required this.cut});

  final Color fill;
  final Color cut;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()..color = fill;
    // Der Keil: oben schräg von der Spitze zum Rand, unten gerade.
    canvas.drawPath(
        Path()
          ..moveTo(1.8, 12.8)
          ..lineTo(21, 7.4)
          ..quadraticBezierTo(22.4, 7.4, 22.4, 8.8)
          ..lineTo(22.4, 21.5)
          ..lineTo(1.8, 21.5)
          ..close(),
        paint);
    // Die Sahneschicht als Fuge in der Farbe darunter.
    canvas.drawLine(
        const Offset(3.2, 16.6),
        const Offset(22.4, 16.6),
        Paint()
          ..color = cut
          ..strokeWidth = 1.6);
    // Kirsche mit Stiel.
    canvas.drawCircle(const Offset(14.6, 6.0), 2.5, paint);
    canvas.drawLine(
        const Offset(15.4, 3.7),
        const Offset(17.4, 1.2),
        Paint()
          ..color = fill
          ..strokeWidth = 1.3
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(CakeSlicePainter old) => old.fill != fill || old.cut != cut;
}

/// Was man über einen Ort wissen will: Art, Name, Öffnungszeiten — und
/// der Weg zu allem Weiteren auf openstreetmap.org.
Future<void> showPoiSheet(BuildContext context, Poi poi) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final text = Theme.of(context).textTheme;
        final water = switch ((poi.kind, poi.drinkable)) {
          (_, true) => 'Trinkwasser laut OpenStreetMap.',
          (_, false) => 'Laut OpenStreetMap kein Trinkwasser.',
          (PoiKind.spring || PoiKind.waterPoint, null) =>
            'Ob das Wasser trinkbar ist, steht nicht fest.',
          _ => null,
        };
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  PoiPin(kind: poi.kind),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(poi.name ?? poi.kind.label,
                        style: text.titleLarge),
                  ),
                ]),
                const SizedBox(height: 8),
                if (poi.name != null) Text(poi.kind.label, style: text.bodyMedium),
                if (poi.openingHours != null)
                  Text('Öffnungszeiten: ${poi.openingHours}',
                      style: text.bodyMedium),
                if (water != null) Text(water, style: text.bodyMedium),
                const SizedBox(height: 8),
                TextButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Auf OpenStreetMap ansehen'),
                  onPressed: () => launchUrl(
                      Uri.parse('https://www.openstreetmap.org/${poi.id}'),
                      mode: LaunchMode.externalApplication),
                ),
              ],
            ),
          ),
        );
      },
    );

/// Der Filter: oben die Ebene „Offizielle Trails" (#13), darunter vier
/// Gruppen von Orten zum An- und Ausschalten, je Gruppe ihre Arten als
/// Chips (Detailfilter). Er sagt dazu, ab wann Orte erscheinen und wohin
/// der Ausschnitt dafür geht.
/// Seit 0.75.0 (#190) das Blatt „Kartenebenen", direkt vom Knopf rechts
/// geöffnet — bis 0.74.x lag es hinter dem ersten Knopf der Leiste mit
/// den Offline-Werkzeugen, drei Ebenen tief. Es liegt über jeder Leiste
/// und ändert an ihr nichts.
Future<void> showMapLayersSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // Nicht bildschirmhoch: Oben bleibt Karte sichtbar (und zum
      // Schließen antippbar); was nicht passt, scrollt im Blatt.
      builder: (_) => const _PoiFilterSheet(),
    );

class _PoiFilterSheet extends ConsumerWidget {
  const _PoiFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(poiGroupsProvider);
    final hidden = ref.watch(poiHiddenKindsProvider);
    final official = ref.watch(officialTrailsEnabledProvider);
    final ways = ref.watch(wayLayerEnabledProvider);
    final contours = ref.watch(contourLayerEnabledProvider);
    final trails = ref.watch(trailsProvider).valueOrNull ?? const <Trail>[];
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Derselbe Filter wie in der Trail-Liste (#66): hier gesetzt,
            // gilt er auch dort — und umgekehrt.
            if (trails.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Text('Trails', style: text.titleLarge),
              ),
              CoachAnchor(
                id: MapCoach.filterTrails,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: TrailFilterChips(
                    keyPrefix: 'map-trail',
                    showOwner: trails.any((t) => t.isOwn) && trails.any((t) => !t.isOwn),
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Text('Ebenen', style: text.titleLarge),
            ),
            // Die Anker der Karten-Tour (#132): der Schalter und die
            // Gruppen der Orte, jeweils mit Überschrift.
            CoachAnchor(
              id: MapCoach.filterOfficial,
              child: SwitchListTile(
              key: const ValueKey('official-trails-switch'),
              secondary: CircleAvatar(
                backgroundColor: AppPalette.of(context).map.official,
                child: const Icon(Icons.verified_outlined, color: Colors.white, size: 20),
              ),
              title: const Text('Offizielle Trails'),
              subtitle: const Text('Vom Land ausgewiesene Singletrails, '
                  'gestrichelt — bisher Tirol'),
              value: official,
              onChanged: (v) => ref.read(officialTrailsEnabledProvider.notifier).set(v),
            )),
            // Die Wege (#212): Güte der Forstwege, Schwierigkeit der Pfade —
            // aus OSM, über der Basiskarte. Ab Werk an.
            CoachAnchor(
              id: MapCoach.filterWays,
              child: SwitchListTile(
                key: const ValueKey('way-layer-switch'),
                secondary: const CircleAvatar(
                  backgroundColor: AppColors.mapBackground,
                  child: SizedBox(width: 26, height: 20, child: CustomPaint(painter: WaySwatchPainter())),
                ),
                title: const Text('Wege'),
                subtitle: const Text('Forstwege nach Güte, Pfade nach Schwierigkeit — '
                    'aus OpenStreetMap, ab Zoomstufe $kWaysZoom'),
                value: ways,
                onChanged: (v) => ref.read(wayLayerEnabledProvider.notifier).set(v),
              ),
            ),
            // Die Höhenlinien (#271, Betreiber: „pack es in die Ebenen") —
            // aus den Höhenkacheln, dezent unter den Wegen. Ab Werk aus.
            // Der Untertitel sagt, was die Karte gerade zeigt oder warum
            // nicht (zu weit draußen, keine Höhen hier).
            CoachAnchor(
              id: MapCoach.filterContours,
              child: SwitchListTile(
                key: const ValueKey('contour-layer-switch'),
                secondary: const CircleAvatar(
                  backgroundColor: AppColors.mapBackground,
                  child: SizedBox(width: 26, height: 20, child: CustomPaint(painter: ContourSwatchPainter())),
                ),
                title: const Text('Höhenlinien'),
                subtitle: Text(
                  contours ? contourStatusText(ref.watch(contourStateProvider)) : 'Aus dem Geländemodell, dezent unter den Wegen',
                  key: const ValueKey('contour-layer-status'),
                ),
                value: contours,
                onChanged: (v) => ref.read(contourLayerEnabledProvider.notifier).set(v),
              ),
            ),
            CoachAnchor(
              id: MapCoach.filterPois,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Text('Orte auf der Karte', style: text.titleLarge),
            ),
            for (final g in PoiGroup.values) ...[
              SwitchListTile(
                key: ValueKey('poi-group-${g.name}'),
                secondary: CircleAvatar(
                  backgroundColor: g.color,
                  child: PoiGlyph(
                      kind: PoiKind.values.firstWhere((k) => k.group == g),
                      size: 20,
                      background: g.color),
                ),
                title: Text(g.label),
                subtitle: Text(g.examples),
                value: groups.contains(g),
                onChanged: (_) => ref.read(poiGroupsProvider.notifier).toggle(g),
              ),
              // Die Arten nur unter eingeschalteten Gruppen — unter einer
              // ausgeschalteten wären es Schalter ohne Wirkung.
              if (groups.contains(g))
                Padding(
                  padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final k in PoiKind.values)
                        if (k.group == g)
                          FilterChip(
                            key: ValueKey('poi-kind-${k.name}'),
                            // Abgewählt: grau, damit man es ohne Hinsehen
                            // auf den Chip-Hintergrund erkennt.
                            avatar: CircleAvatar(
                              backgroundColor:
                                  hidden.contains(k) ? Colors.grey : g.color,
                              child: PoiGlyph(
                                  kind: k,
                                  size: 14,
                                  background:
                                      hidden.contains(k) ? Colors.grey : g.color),
                            ),
                            label: Text(k.label),
                            selected: !hidden.contains(k),
                            showCheckmark: false,
                            onSelected: (_) =>
                                ref.read(poiHiddenKindsProvider.notifier).toggle(k),
                          ),
                    ],
                  ),
                ),
            ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(
                'Orte erscheinen ab Zoomstufe ${kPoiMinZoom.round()}. Sie kommen '
                'aus OpenStreetMap, als fertige Dateien vom Kartenspeicher der '
                'App (tiles.mcbuchi.de): Dafür gehen die Rasterzellen des '
                'Ausschnitts dorthin — keine Trails, keine Fahrten, kein Konto.',
                style: text.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Das Bild am Schalter „Höhenlinien": drei Linien übereinander, die
/// mittlere kräftiger — wie auf der Karte.
class ContourSwatchPainter extends CustomPainter {
  const ContourSwatchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    for (final (i, y) in [0.22, 0.5, 0.78].indexed) {
      final index = i == 1;
      final paint = Paint()
        ..color = AppColors.contourLine.withValues(alpha: index ? 0.9 : 0.6)
        ..strokeWidth = index ? 1.6 : 1.0
        ..style = PaintingStyle.stroke;
      final path = Path()
        ..moveTo(1, size.height * y + 2)
        ..quadraticBezierTo(size.width / 2, size.height * y - 4, size.width - 1, size.height * y + 1);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(ContourSwatchPainter oldDelegate) => false;
}
