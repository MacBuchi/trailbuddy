// Die Legende auf der Karte (#182): zu eine schmale Lasche links am Rand,
// ein Tipp klappt sie auf, ein zweiter zu; das Gerät merkt es sich. Eine
// offene Leiste hat den Platz für sich.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/features/map/map_buttons.dart';
import 'package:trailbuddy/features/map/map_legend.dart';
import 'package:trailbuddy/features/map/map_screen.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;

  setUp(() {
    backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'anna').id);
  });

  final tab = find.byKey(const ValueKey('map-legend-tab'));
  final panel = find.byKey(const ValueKey('map-legend-panel'));

  testWidgets('zu eine Lasche am Rand, ein Tipp auf, einer zu — und gemerkt', (tester) async {
    final settings = FakeSettings();
    await pumpApp(tester, backend, settings: settings);
    await settle(tester, frames: 20);

    expect(panel, findsNothing, reason: 'ab Werk zu');
    expect(tab, findsOneWidget);
    final map = tester.getRect(find.byType(MapScreen));
    final hit = tester.getRect(tab);
    expect(hit.left, map.left, reason: 'am linken Rand');
    expect(hit.width, greaterThanOrEqualTo(kMapButtonSize), reason: 'Trefferfläche wie ein Kartenknopf');
    expect(hit.height, greaterThanOrEqualTo(kMapButtonSize));
    // Sichtbar ist nur ein schmaler Streifen.
    final visible = tester.getRect(find.descendant(of: tab, matching: find.byType(Container)).first);
    expect(visible.width, lessThanOrEqualTo(16));

    await tester.tap(tab);
    await settle(tester);
    expect(panel, findsOneWidget);
    expect(settings.mapLegendOpen, isTrue, reason: 'gemerkt');
    for (final s in legendSamples()) {
      expect(find.descendant(of: panel, matching: find.text(s.label)), findsOneWidget, reason: s.label);
    }
    // Die Gruppen tragen Überschriften (#231): dass „abgerockt" ein
    // Zustand ist, steht da, statt erraten zu werden.
    for (final title in ['SCHWIERIGKEIT', 'ZUSTAND', 'AM TRAIL', 'FORSTWEG', 'PFAD']) {
      expect(find.descendant(of: panel, matching: find.text(title)), findsOneWidget, reason: title);
    }
    expect(tester.getRect(panel).width, kMapLegendWidth);

    await tester.tap(find.byKey(const ValueKey('map-legend-close')));
    await settle(tester);
    expect(panel, findsNothing);
    expect(tab, findsOneWidget);
    expect(settings.mapLegendOpen, isFalse);
  });

  testWidgets('die Wege (#212) stehen nur in der Legende, solange ihre Ebene an ist', (tester) async {
    final settings = FakeSettings(mapLegendOpen: true, wayLayerEnabled: false);
    await pumpApp(tester, backend, settings: settings);
    await settle(tester, frames: 20);
    expect(find.descendant(of: panel, matching: find.text('FORSTWEG')), findsNothing);
    expect(find.descendant(of: panel, matching: find.text('S0')), findsOneWidget);

    // Eingeschaltet im Blatt „Kartenebenen" — dieselbe Einstellung.
    await tester.tap(find.byTooltip('Kartenebenen'));
    await settle(tester);
    final toggle = find.byKey(const ValueKey('way-layer-switch'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await settle(tester);
    expect(settings.wayLayerEnabled, isTrue);
    await tester.tapAt(const Offset(200, 40));
    await settle(tester);
    for (final title in ['FORSTWEG', 'PFAD']) {
      expect(find.descendant(of: panel, matching: find.text(title)), findsOneWidget, reason: title);
    }
  });

  testWidgets('offen gemerkt ⇒ beim Start offen', (tester) async {
    await pumpApp(tester, backend, settings: FakeSettings(mapLegendOpen: true));
    await settle(tester, frames: 20);
    expect(panel, findsOneWidget);
    expect(tab, findsNothing);
  });

  testWidgets('die Leiste „Offline-Karten" hat den Platz für sich', (tester) async {
    await pumpApp(tester, backend, settings: FakeSettings(mapLegendOpen: true));
    await settle(tester, frames: 20);
    await tester.tap(find.byTooltip('Offline-Karten'));
    await settle(tester);
    expect(find.byKey(const ValueKey('offline-tool-rail')), findsOneWidget);
    expect(panel, findsNothing);
    expect(tab, findsNothing);

    await tester.tap(find.byTooltip('Offline-Karten'));
    await settle(tester);
    expect(find.byKey(const ValueKey('offline-tool-rail')), findsNothing);
    expect(panel, findsOneWidget, reason: 'danach wieder so, wie sie war');
  });

  for (final (mode, size) in [('light', const Size(360, 640)), ('dark', const Size(640, 360))]) {
    testWidgets('aufgeklappt im Bild, frei von Knöpfen, auf dem Landton ($mode, $size)', (tester) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pumpApp(tester, backend, settings: FakeSettings(appearance: mode, mapLegendOpen: true));
      await settle(tester, frames: 20);

      final map = tester.getRect(find.byType(MapScreen));
      final legend = tester.getRect(panel);
      expect(map.contains(legend.topLeft) && map.contains(legend.bottomRight - const Offset(1, 1)), isTrue,
          reason: 'ganz im Bild');
      for (final key in ['layers-button', 'offline-button', 'feedback-button', 'ride-button']) {
        final f = find.byKey(ValueKey(key));
        if (f.evaluate().isEmpty) continue;
        expect(legend.overlaps(tester.getRect(f)), isFalse, reason: key);
      }
      final box = tester.widget<Container>(panel).decoration! as BoxDecoration;
      expect(box.color, AppColors.mapBackground, reason: 'auch in der dunklen App der Landton');
      expect(tester.takeException(), isNull, reason: 'kein Überlauf');
    });
  }
}
