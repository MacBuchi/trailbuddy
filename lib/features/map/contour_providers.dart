// Wann die Höhenlinien rechnen (#271): Schalter, Maßstab, Fenster, Kacheln
// und der Lauf im Isolate. Die Rechnung selbst steht flutter-frei in
// `contour_layer.dart`.
//
// **Beobachten ist laden** (PilzBuddy): Solange der Schalter aus ist,
// liest nichts hier eine Kachel, öffnet kein Archiv und fragt den Host
// nicht — `contourStateProvider` prüft den Schalter vor jedem `watch`
// auf Kacheln, und ein Test zählt die Abrufe.
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connectivity.dart';
import '../../core/errors.dart';
import '../../core/settings.dart';
import '../offline_areas/area_providers.dart' show areaHeightReaderProvider;
import '../offline_areas/height_tiles.dart';
import '../routing/online_fill.dart' show onlineHeightsFactoryProvider;
import 'contour_layer.dart';
import 'map_view/map_view.dart' show MapViewBounds;

/// Der Schalter „Höhenlinien" in „Kartenebenen" (Betreiber, 2026-10-08:
/// kein eigener Knopf), gerätelokal, Vorgabe aus. Aus heißt: keine
/// Rechnung und keine Anfrage.
final contourLayerEnabledProvider = NotifierProvider<RememberedFlag, bool>(
  () => RememberedFlag(
    read: (s) => s.contourLayerEnabled,
    write: (s, v) => s.setContourLayerEnabled(v),
    label: 'Höhenlinien merken',
  ),
);

/// Sichtfenster und Maßstab beim letzten Stillstand der Karte —
/// geschrieben vom Karten-Screen.
final contourViewProvider =
    StateProvider<({MapViewBounds bounds, double metersPerPixel})?>((ref) => null);

/// Der Maßstab, auf Achtelstufen gerastert: Beim Schieben ändert sich die
/// gemessene Zahl mit der Breite ein wenig, und ohne Raster rechnete jeder
/// Stillstand neu, obwohl dieselben Kacheln dieselben Linien geben.
double contourScaleStep(double metersPerPixel) {
  final steps = (math.log(metersPerPixel) / math.ln2 * 8).round();
  return math.pow(2, steps / 8).toDouble();
}

/// Fenster und gerasterter Maßstab — gleich, solange man innerhalb
/// derselben Kacheln schiebt.
typedef ContourInput = ({ContourWindow window, double metersPerPixel});

ContourInput? contourInputOf(({MapViewBounds bounds, double metersPerPixel})? view) {
  if (view == null) return null;
  final b = view.bounds;
  return (
    window: ContourWindow.covering(west: b.west, south: b.south, east: b.east, north: b.north),
    metersPerPixel: contourScaleStep(view.metersPerPixel),
  );
}

/// Was die Ebene gerade zeigt — oder warum nicht.
enum ContourStatus {
  /// Schalter aus.
  off,

  /// Die Karte stand noch nicht still.
  waiting,

  /// Zu weit draußen: zu grob für die Daten, zu viele Kacheln, oder das
  /// Gelände ist für 200 m zu bewegt.
  tooFarOut,

  /// Hier gibt es keine Höhen — kein gespeicherter Bereich und kein
  /// Empfang (oder der Host hat die Gegend nicht).
  noHeights,

  /// Linien liegen auf der Karte (im Flachen auch null Stück).
  shown,
}

class ContourState {
  const ContourState(this.status, [this.contours]);

  final ContourStatus status;
  final TerrainContours? contours;
}

/// Die Rechnung im Hintergrund; im Web und im Test an Ort und Stelle
/// (`compute` rechnet im Web ohnehin inline; ein echter Isolate antwortet
/// in der Test-Zone nie — der Harness ersetzt die Naht).
typedef ContourCompute = Future<({TerrainContours? contours, ContourGap? gap})> Function(ContourJob job);

final contourComputeProvider = Provider<ContourCompute>((ref) => (job) => compute(computeContours, job));

/// Die Höhenkacheln eines Fensters: erst die gespeicherten Bereiche, mit
/// Empfang dahinter der Host über den Sitzungsspeicher (`OnlineHeights`,
/// dieselbe Quelle wie Planer und Trail-Profil). Jede Kachel kostet online
/// höchstens EINEN Abruf je Sitzung.
final contourTilesProvider =
    FutureProvider.autoDispose.family<Map<({int x, int y}), HeightTile?>, ContourWindow>((ref, window) async {
  HeightReader? areas;
  try {
    areas = await ref.watch(areaHeightReaderProvider.future);
  } catch (e, s) {
    logError('Höhen der Bereiche öffnen', e, s);
  }
  final online = ref.watch(noConnectivityProvider) ? null : ref.read(onlineHeightsFactoryProvider)();
  // Die Quellen der Bereiche gehören ihrem Provider und bleiben offen;
  // geschlossen wird nur, was hier geöffnet wurde.
  final reader = HeightReader([...?areas?.sources, ?online]);
  try {
    final entries = await Future.wait([
      for (final t in window.tiles) reader.tileAt(t.x, t.y).then((tile) => MapEntry(t, tile)),
    ]);
    return Map.fromEntries(entries);
  } finally {
    await online?.close();
  }
});

/// Die Höhenlinien — oder warum es keine gibt. Die Reihenfolge der
/// Prüfungen IST die Zusage: erst der Schalter, dann die billigen
/// Grenzen, erst dann die Kacheln.
final contourStateProvider = FutureProvider<ContourState>((ref) async {
  if (!ref.watch(contourLayerEnabledProvider)) return const ContourState(ContourStatus.off);
  final input = ref.watch(contourViewProvider.select(contourInputOf));
  if (input == null) return const ContourState(ContourStatus.waiting);
  if (input.metersPerPixel > kContourMaxMetersPerPixel || input.window.tileCount > kContourMaxTiles) {
    return const ContourState(ContourStatus.tooFarOut);
  }
  final tiles = await ref.watch(contourTilesProvider(input.window).future);
  if (tiles.values.every((t) => t == null)) return const ContourState(ContourStatus.noHeights);
  final field = contourFieldFrom(input.window, (x, y) => tiles[(x: x, y: y)]);
  final result = await ref.read(contourComputeProvider)(ContourJob(
    field: field,
    metersPerPixel: input.metersPerPixel,
    key: '${input.window.key}|${field.factor}',
  ));
  return switch (result.gap) {
    ContourGap.noHeights => const ContourState(ContourStatus.noHeights),
    ContourGap.tooFarOut => const ContourState(ContourStatus.tooFarOut),
    null => ContourState(ContourStatus.shown, result.contours),
  };
});

/// Die Zahlen an den Hauptlinien für flutter_map — auf dem Haupt-Thread,
/// es sind ein paar Dutzend Punkte.
final contourLabelsProvider = Provider<List<ContourLabel>>((ref) {
  final contours = ref.watch(contourStateProvider).valueOrNull?.contours;
  if (contours == null) return const [];
  return contourLabels(contours.lines, metersPerPixel: contours.metersPerPixel);
});

/// Der Satz unter dem Schalter und in der Legende — eine Stelle, damit
/// beide dasselbe sagen.
String contourStatusText(AsyncValue<ContourState> state) {
  final s = state.valueOrNull;
  if (s == null) return state.isLoading ? 'Wird berechnet …' : 'Aus dem Geländemodell, dezent unter den Wegen';
  return switch (s.status) {
    ContourStatus.off || ContourStatus.waiting => 'Aus dem Geländemodell, dezent unter den Wegen',
    ContourStatus.tooFarOut => 'Erst näher heranzoomen',
    ContourStatus.noHeights => 'Hier keine Höhen — Bereich speichern oder mit Empfang ansehen',
    ContourStatus.shown => 'Alle ${s.contours!.equidistanceM} m, beschriftet alle '
        '${contourIndexStepM(s.contours!.equidistanceM)} m',
  };
}
