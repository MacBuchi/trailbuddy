// Die Hülle der Karte (Design Turn 3, Spezifikation 3e): rechts die
// Knöpfe, oben rechts die Glühbirne neben den Bannern (#180), links die
// Leiste nur mit offenem Menü — Maße, Markierung des offenen Menüs,
// aktives Werkzeug und Speichern, hell und dunkel.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/features/map/map_buttons.dart';
import 'package:trailbuddy/features/map/map_screen.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/offline_areas/area_draw.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/offline_tool_rail.dart';
import 'package:trailbuddy/features/trails/trail_list.dart';
import 'package:trailbuddy/features/trails/trail_providers.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

/// Der IconButton zu einem Knopf — unter dem Schlüssel (am Rahmen) oder
/// über dem Tooltip (den der IconButton selbst einzieht).
Finder _button(Finder f) {
  final below = find.descendant(of: f, matching: find.byType(IconButton));
  return below.evaluate().isNotEmpty ? below.first : find.ancestor(of: f, matching: find.byType(IconButton)).first;
}

ButtonStyle _style(WidgetTester tester, Finder f) => tester.widget<IconButton>(_button(f)).style!;

ButtonStyle _railStyle(WidgetTester tester, String key) =>
    tester.widget<IconButton>(find.byKey(ValueKey(key))).style!;

void main() {
  for (final (mode, palette) in [('light', AppColors.light), ('dark', AppColors.dark)]) {
    testWidgets('Knöpfe und Leiste ($mode)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2220);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final backend = FakeBackend();
      backend.signInAs(backend.addUser(username: 'anna').id);
      await pumpApp(tester, backend, settings: FakeSettings(appearance: mode));
      await settle(tester);

      // Rechts (seit #190): Kartenebenen, Offline-Karten, Position
      // übereinander (44), unten die Aufnahme (60), in dieser Reihenfolge.
      final idea = find.byTooltip('Idee oder Fehler melden');
      final layers = find.byKey(const ValueKey('layers-button'));
      final offline = find.byKey(const ValueKey('offline-button'));
      final locate = find.byTooltip('Meine Position');
      final record = find.byKey(const ValueKey('ride-button'));
      for (final f in [idea, layers, offline, locate]) {
        expect(tester.getSize(_button(f)), const Size.square(kMapButtonSize));
      }
      expect(tester.getSize(_button(record)), const Size.square(kRecordButtonSize));
      final ys = [layers, offline, locate, record].map((f) => tester.getCenter(f).dy).toList();
      expect(ys, orderedEquals([...ys]..sort()));
      expect(_style(tester, record).backgroundColor!.resolve({}), AppColors.brand);
      expect(find.byKey(const ValueKey('offline-tool-rail')), findsNothing);
      expect(tester.widget<MapView>(find.byType(MapView)).config.bottomLeftInset, 0);

      // Die Glühbirne oben rechts (#180), abgesetzt von der Spalte.
      final map = tester.getRect(find.byType(MapScreen));
      final bulb = tester.getRect(_button(idea));
      expect(bulb.right, moreOrLessEquals(map.right - 12));
      expect(bulb.top, lessThan(map.top + 60));
      expect(bulb.bottom, lessThan(tester.getRect(_button(layers)).top - 100));

      // Ein Banner oben hält Abstand zu ihr: Das X des Filters bleibt
      // frei, mit mindestens 8 dp Luft.
      ProviderScope.containerOf(tester.element(find.byType(MapScreen)))
          .read(trailListFilterProvider.notifier)
          .state = const TrailListFilter(maxGrade: 2);
      await settle(tester);
      // Die Fläche der Karte, nicht das Widget samt Rand (`margin`).
      final banner = tester.getRect(find
          .descendant(of: find.byKey(const ValueKey('map-filter-banner')), matching: find.byType(Material))
          .first);
      final reset = tester.getRect(find.byKey(const ValueKey('map-filter-reset')));
      expect(banner.top, lessThan(bulb.bottom), reason: 'nebeneinander, nicht untereinander');
      expect(bulb.left - banner.right, greaterThanOrEqualTo(8));
      expect(bulb.left - reset.right, greaterThanOrEqualTo(8));
      ProviderScope.containerOf(tester.element(find.byType(MapScreen)))
          .read(trailListFilterProvider.notifier)
          .state = const TrailListFilter();
      await settle(tester);

      // Kartenebenen: das Blatt direkt, keine Leiste (#190).
      await tester.tap(layers);
      await settle(tester);
      expect(find.byKey(const ValueKey('official-trails-switch')), findsOneWidget);
      expect(find.byKey(const ValueKey('offline-tool-rail')), findsNothing);
      await tester.tapAt(Offset(map.center.dx, map.top + 20)); // Blatt schließen
      await settle(tester);
      expect(find.byKey(const ValueKey('official-trails-switch')), findsNothing);

      // Offline-Karten auf: links die Leiste, der Knopf rechts trägt die Marke.
      await tester.tap(offline);
      await settle(tester);
      expect(_style(tester, offline).side!.resolve({})!.color, palette.brandMark);
      final rail = tester.getRect(find.byKey(const ValueKey('offline-tool-rail')));
      expect(rail.width, kRailWidth);
      expect(tester.getSize(find.byKey(const ValueKey('area-draw-add'))), const Size.square(kMapButtonSize));
      // Maßstab und Quelle rücken neben die Leiste.
      expect(tester.widget<MapView>(find.byType(MapView)).config.bottomLeftInset,
          greaterThanOrEqualTo(kRailWidth));

      // Nichts im Entwurf: Speichern ist aus, nicht Lime.
      expect(_railStyle(tester, 'area-draw-save').backgroundColor?.resolve({WidgetState.disabled}), isNot(AppColors.brand));

      // Ein Werkzeug scharf: helle Fläche (Gegenhelligkeit der Leiste)
      // und oben die Zeile, was der Strich tut.
      await tester.tap(find.byKey(const ValueKey('area-draw-add')));
      await settle(tester);
      expect(_railStyle(tester, 'area-draw-add').backgroundColor!.resolve({WidgetState.selected}), palette.text);
      expect(_railStyle(tester, 'area-draw-add').foregroundColor!.resolve({WidgetState.selected}), palette.ground);
      expect(find.byKey(const ValueKey('area-draw-hint')), findsOneWidget);

      // Etwas im Entwurf: Speichern wird Lime, der Zähler steht darunter.
      ProviderScope.containerOf(tester.element(find.byType(MapScreen)))
          .read(areaDraftProvider.notifier)
          .addAll(tilesInBounds(const AreaBounds(south: 48, west: 9, north: 48.01, east: 9.01))!);
      await settle(tester);
      expect(_railStyle(tester, 'area-draw-save').backgroundColor!.resolve({}), AppColors.brand);
      final save = tester.getRect(find.byKey(const ValueKey('area-draw-save')));
      final count = tester.getRect(find.byKey(const ValueKey('area-draw-count')));
      expect(count.top, greaterThanOrEqualTo(save.bottom));
      expect(count.top - save.bottom, lessThan(8));
      expect((tester.widget(find.byKey(const ValueKey('area-draw-count'))) as Text).data, startsWith('+'));
    });
  }
}
