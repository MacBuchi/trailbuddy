// Der Bau des Graphen hat keinen Weg zurück in den UI-Isolate (#356 PR 8,
// Konzept-Routing 10.6) — strukturell, am Quelltext: Wer den Planer,
// seinen Lader, die Kalibrierung oder „Zurück zur Route" (PR 9) wieder
// bauen lässt, wird hier rot, bevor es ein ANR wird (#354). Dass der Bau wirklich drüben läuft, prüft
// `loop_plan_runner_test.dart` am Namen des Isolates.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('Planer, Lader, Kalibrierung und Navigation dekodieren und bauen nichts — sie sammeln Bytes', () {
    for (final path in const [
      'lib/features/routing/loop_planner_controller.dart',
      'lib/features/routing/planning_graph.dart',
      // Seit #356 PR 9 auch die Kalibrierung und „Zurück zur Route".
      'lib/features/routing/ride_calibrator.dart',
      'lib/features/routing/nav_providers.dart',
    ]) {
      final src = read(path);
      for (final symbol in const [
        'buildGraphFrom(',
        'buildRoadGraphFrom(',
        'buildRoadGraph(',
        'loadRoadGraph(',
        'applyTrails(',
        'addClimbs',
        'addWayQuality(',
        'wayLinesFromTile(',
        'RoadGraph?',
        'RoadGraph ',
      ]) {
        expect(src.contains(symbol), isFalse, reason: '$path ruft $symbol — das gehört in den Rechen-Isolate');
      }
    }
  });

  test('die Naht ist rein: keine Widgets, kein Riverpod, kein Isolate, kein Speicher', () {
    final src = read('lib/features/routing/graph_input.dart');
    for (final import in const [
      'package:flutter/',
      'package:flutter_riverpod/',
      'dart:isolate',
      'dart:io',
      'dart:ui',
      '../offline_areas/area_providers.dart',
      '../offline_areas/tile_store',
      'online_fill.dart',
    ]) {
      expect(src.contains("import '$import"), isFalse, reason: 'graph_input.dart importiert $import');
    }
  });
}
