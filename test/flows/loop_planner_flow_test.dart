// Der Rundenplaner durch die echte Oberfläche (#158 Schritt 5, seit
// 0.74.0 ein Modus mit Leiste links): Trails auf der Karte an- und
// abwählen, über die Liste mit Radius oder ein umfahrenes Gebiet, die
// Parameter im Blatt, Rechnen — Summen, Reihenfolge, Vorschau, „Als Fahrt
// speichern", „Als GPX"; der getippte Start, und die Fälle, in denen
// nichts gerechnet werden kann (kein Bereich, kein Standort).
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/core/gpx_share.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/routing/trail_head_providers.dart' show RouteMode;
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';
import 'package:trailbuddy/features/map/pmtiles_tile_provider.dart';
import 'package:trailbuddy/features/routing/loop_plan_runner.dart';
import 'package:trailbuddy/features/routing/loop_planner_controller.dart';
import 'package:trailbuddy/features/routing/loop_planner.dart' show LoopPlan;
import 'package:trailbuddy/features/routing/online_fill.dart';
import 'package:trailbuddy/features/routing/road_graph.dart' show RoadGraph;
import 'package:trailbuddy/features/trails/gpx.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/fake_map_view.dart';
import 'package:trailbuddy/features/map/map_view/map_hit_test.dart' show projectToScreen;
import 'package:trailbuddy/features/routing/loop_planner_sheet.dart' show LoopStartFlag, kLoopPickWidth;
import '../fakes/fake_rides.dart';
import '../fakes/fake_tiles.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

/// Der Trail von `seedTrail` läuft von 48,0° N / 9,0° O 1 km nach Norden;
/// der Standort liegt südlich davon. Ein Forstweg entlang 9,0° O verbindet
/// Standort, Trailkopf und Trailende — die Runde ist Weg hinauf, Trail
/// hinunter … nein: Trail hinauf (er läuft nach Norden) und Weg zurück.
final _tile = tileAt(48.0, 9.0, 13);
const _n = 1 << 13;
const _lon = 9.0;
final _bounds = tileBounds(13, _tile.x, _tile.y);
final _fromLat = math.max(_bounds.south + 0.0004, 48.0 - 0.003);

/// Grad → Kachel-Pixel der Kachel [x]/[y]; außerhalb der Kachel darf das
/// Ergebnis liegen — `wayLinesFromTile` schneidet die Linie zu.
(int, int) _px(double lat, double lon, int x, int y) {
  final px = ((lon + 180) / 360 * _n - x) * kTileExtent;
  final r = lat * math.pi / 180;
  final py = ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * _n - y) * kTileExtent;
  return (px.round(), py.round());
}

/// Ein Bereich mit der Kachel des Trails und ihren acht Nachbarn; der
/// Forstweg liegt in jeder Kachel, die er berührt (die Schere je Kachel).
/// [onlyCenter]: nur die Kachel des Trails — wie ein Bereich „Entlang
/// meiner Trails", der das Rechteck um die Runde nie ganz deckt.
Future<MemoryAreaStore> _areaWithTrack({bool onlyCenter = false}) async {
  final store = MemoryAreaStore();
  final (:tiles, :bytes) = _trackArchive(onlyCenter: onlyCenter);
  await store.putArchive('a', bytes);
  await store.saveIndex([
    StoredArea(
      id: 'a',
      name: 'Hausrunde',
      bounds: const AreaBounds(south: 47.9, west: 8.9, north: 48.1, east: 9.1),
      minZoom: 13,
      maxZoom: 13,
      build: '20260928',
      tiles: tiles.length,
      bytes: bytes.length,
      savedAt: DateTime.utc(2026, 9, 28),
    ),
  ]);
  return store;
}

/// Die Kacheln mit dem Forstweg als Archiv — für einen Bereich oder als
/// Archiv des Kartenhosts (#187).
({List<TileToWrite> tiles, Uint8List bytes}) _trackArchive({bool onlyCenter = false}) {
  final tiles = <TileToWrite>[];
  final reach = onlyCenter ? 0 : 1;
  for (var dx = -reach; dx <= reach; dx++) {
    for (var dy = -reach; dy <= reach; dy++) {
      final x = _tile.x + dx, y = _tile.y + dy;
      tiles.add(TileToWrite(
        13,
        x,
        y,
        mvtTile([road([_px(_fromLat - 0.0002, _lon, x, y), _px(48.0 + 0.0095, _lon, x, y)], 'path', kindDetail: 'track')]),
      ));
    }
  }
  final bytes = writePmTiles(
    tiles: tiles,
    tileCompression: Compression.none,
    bounds: const TileBounds(west: 8.9, south: 47.9, east: 9.1, north: 48.1),
  );
  return (tiles: tiles, bytes: bytes);
}

/// Ein Runner, der erst antwortet, wenn der Test es sagt — wie der
/// Rechen-Isolate auf dem Telefon, der eine Weile braucht (#188).
class _HeldRunner implements LoopPlanRunner {
  final held = <({RoadGraph graph, LoopRequest request, Completer<LoopPlan> done})>[];
  var disposed = 0;

  @override
  Future<LoopPlan> plan(RoadGraph graph, LoopRequest request) {
    final done = Completer<LoopPlan>();
    held.add((graph: graph, request: request, done: done));
    return done.future;
  }

  @override
  void dispose() => disposed++;
}

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late FakeRideStore rides;
  late String hex, sperr;
  late List<({String fileName, String xml})> shared;

  Future<GpxShareOutcome> recorder({required String fileName, required String xml}) async {
    shared.add((fileName: fileName, xml: xml));
    return GpxShareOutcome.shared;
  }

  setUp(() {
    shared = [];
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    hex = trails.seedTrail(anna.id, name: 'Hexentanz', grade: 2, rating: 4);
    // Gemeldet: steht abseits, nur einzeln. Zu weit für 12 km: 22 km nördlich.
    sperr = trails.seedTrail(anna.id, name: 'Sperrgebiet', grade: 1, status: TrailStatus.closed, lat: 48.0, lon: 9.004);
    trails.seedTrail(anna.id, name: 'Fernweh', grade: 1, lat: 48.2);
    rides = FakeRideStore();
  });

  Future<void> start(WidgetTester tester,
      {MemoryAreaStore? areaStore,
      FakePositionFix? positionFix,
      FakeSettings? settings,
      OnlineFill Function()? onlineFill,
      LoopPlanRunner Function()? runner}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, backend,
        trails: trails,
        areaStore: areaStore,
        rideStore: rides,
        positionFix: positionFix ?? FakePositionFix(fakePosition(_fromLat, _lon)),
        settings: settings,
        extraOverrides: [
          gpxShareProvider.overrideWithValue(recorder),
          if (onlineFill != null) onlineFillFactoryProvider.overrideWithValue(onlineFill),
          if (runner != null) loopPlanRunnerFactoryProvider.overrideWithValue(runner),
        ]);
    await settle(tester, frames: 20);
  }

  /// Das Navi-Symbol der Zeile — die Zeile steht tief (in der Testschrift
  /// nehmen die Filter-Chips viele Zeilen), also erst hinscrollen.
  Future<void> tapNav(WidgetTester tester) async {
    final nav = find.byKey(ValueKey('trail-nav-$hex'));
    await tester.scrollUntilVisible(nav, 100, scrollable: find.byType(Scrollable).hitTestable().first);
    await settle(tester);
    final rect = tester.getRect(nav);
    await tester.tapAt(rect.topCenter + const Offset(0, 8));
  }

  Future<void> openPlanner(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('loop-button')));
    await settle(tester, frames: 10);
    expect(find.byKey(const ValueKey('loop-tool-rail')), findsOneWidget);
  }

  /// Nah an den Trail, damit ein Tipp genau ihn trifft.
  Future<void> zoomToTrails(WidgetTester tester) async {
    fakeMap(tester).move(const LatLng(48.004, _lon), 15);
    await settle(tester, frames: 4);
  }

  Future<void> tapRail(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await settle(tester, frames: 30);
  }

  Iterable<dynamic> connectionLines(WidgetTester tester) =>
      fakeMapLayers(tester).polylines.where((l) => l.width == 5);
  Iterable<dynamic> trailLines(WidgetTester tester) =>
      fakeMapLayers(tester).polylines.where((l) => l.width == 9);
  Iterable<dynamic> picked(WidgetTester tester) =>
      fakeMapLayers(tester).polylines.where((l) => l.width == kLoopPickWidth);

  testWidgets('Planer-Modus: Trail antippen, rechnen, Ergebnis über der Karte, Fahrt, GPX', (tester) async {
    await start(tester, areaStore: await _areaWithTrack());
    await openPlanner(tester);
    expect(find.byKey(const ValueKey('loop-hint')), findsOneWidget, reason: 'nichts gewählt: wie es geht');
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('loop-rail-compute'))).onPressed, isNull);

    // Einmal antippen: hervorgehoben und dabei; noch einmal: ab.
    await zoomToTrails(tester);
    await tapMapAt(tester, const LatLng(48.004, _lon));
    await settle(tester);
    expect(picked(tester), hasLength(1));
    expect(find.text('HEXENTANZ'), findsNothing, reason: 'im Planer öffnet ein Tipp kein Blatt');
    await tapMapAt(tester, const LatLng(48.004, _lon));
    await settle(tester);
    expect(picked(tester), isEmpty);
    await tapMapAt(tester, const LatLng(48.004, _lon));
    await settle(tester);
    expect(find.byKey(const ValueKey('loop-hint')), findsNothing);
    expect(find.text('1'), findsWidgets, reason: 'der Zähler unter „Rechnen"');

    await tapRail(tester, 'loop-rail-compute');
    expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);
    // Hexentanz trägt 4 Sterne: Die zweite Abfahrt bringt noch 30 %, und
    // das Budget reicht — also zweimal, 1,3 km Trail-Meter, „noch einmal".
    expect(find.textContaining('1,3 km Trail'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('loop-stop-0')), matching: find.text('Hexentanz')),
        findsOneWidget);
    expect(trailLines(tester), hasLength(2));
    expect(connectionLines(tester), isNotEmpty);
    expect(picked(tester), isEmpty, reason: 'die Runde zeigt, was dabei ist');
    final whole = fakeMapLayers(tester).polylines.where((l) => l.width == 2).single;
    expect(whole.points.first.latitude, closeTo(_fromLat, 1e-9));
    expect(whole.points.last.latitude, closeTo(_fromLat, 1e-9));
    // Über dem eingeklappten Blatt eingepasst.
    expect(fakeMap(tester).lastFitBottomInset, greaterThan(100));

    await tester.ensureVisible(find.byKey(const ValueKey('loop-save')));
    await settle(tester, frames: 2);
    await tester.tap(find.byKey(const ValueKey('loop-save')));
    await settle(tester);
    expect(rides.rides.single.planned, isTrue);
    expect(rides.rides.single.name, 'Runde: Hexentanz');
    await tester.ensureVisible(find.byKey(const ValueKey('loop-gpx')));
    await tester.tap(find.byKey(const ValueKey('loop-gpx')));
    await settle(tester);
    expect(shared.single.fileName, 'trailbuddy-runde-hexentanz.gpx');
    expect(parseGpx(shared.single.xml).single.points.every((p) => p.ele == null && p.time == null), isTrue);

    // Runterziehen verkleinert, schließt nie.
    final sheetList = find
        .descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable))
        .first;
    for (var i = 0; i < 4; i++) {
      await tester.drag(sheetList, const Offset(0, 1500));
      await settle(tester, frames: 4);
    }
    expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);

    // Ergebnis zu: Runde weg, der Planer und die Auswahl bleiben.
    await tester.tap(find.byKey(const ValueKey('loop-close')));
    await settle(tester);
    expect(trailLines(tester), isEmpty);
    expect(find.byKey(const ValueKey('loop-tool-rail')), findsOneWidget);
    expect(picked(tester), hasLength(1));

    // Planer zu: Leiste weg, nichts leuchtet; ein Tipp wählt wieder aus.
    await tapRail(tester, 'loop-rail-close');
    expect(find.byKey(const ValueKey('loop-tool-rail')), findsNothing);
    expect(picked(tester), isEmpty);
  });

  testWidgets('Rechnen wartet auf den Runner; Schließen gibt ihn frei, und ein spätes Ergebnis zählt nicht',
      (tester) async {
    final runner = _HeldRunner();
    await start(tester, areaStore: await _areaWithTrack(), runner: () => runner);
    await openPlanner(tester);
    await zoomToTrails(tester);
    await tapMapAt(tester, const LatLng(48.004, _lon));
    await settle(tester);

    // Erste Rechnung: Das Ergebnis kommt erst, wenn der Runner antwortet.
    await tapRail(tester, 'loop-rail-compute');
    expect(runner.held, hasLength(1));
    expect(find.byKey(const ValueKey('loop-summary')), findsNothing);
    final first = runner.held.single;
    expect(first.request.pool.map((t) => t.name), ['Hexentanz']);
    first.done.complete(first.request.planOn(first.graph));
    await settle(tester, frames: 30);
    expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);

    // Zweite Rechnung auf demselben Graphen, mit demselben Runner. Das X
    // schließt das Ergebnis-Blatt, während gerechnet wird — die Runde,
    // die danach kommt, öffnet nichts mehr.
    await tester.tap(find.byKey(const ValueKey('loop-close')));
    await settle(tester);
    await tapRail(tester, 'loop-rail-compute');
    expect(runner.held, hasLength(2));
    expect(identical(runner.held[1].graph, first.graph), isTrue, reason: 'der Graph wird nicht neu geladen');
    await tester.tap(find.byKey(const ValueKey('loop-close')));
    await settle(tester);
    final second = runner.held[1];
    second.done.complete(second.request.planOn(second.graph));
    await settle(tester, frames: 30);
    expect(find.byKey(const ValueKey('loop-summary')), findsNothing);
    expect(trailLines(tester), isEmpty, reason: 'keine Runde auf der Karte ohne Blatt');
    expect(find.byKey(const ValueKey('loop-tool-rail')), findsOneWidget, reason: 'der Planer bleibt offen');
    expect(runner.disposed, 0);

    // Dritte Rechnung, und Zurück schließt den Planer: Der Runner wird
    // freigegeben. Scheitert die Rechnung daran, ist das weder ein Grund
    // im Planer noch ein Fehlerbericht.
    await tapRail(tester, 'loop-rail-compute');
    expect(runner.held, hasLength(3));
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byKey(const ValueKey('loop-tool-rail')), findsNothing);
    expect(runner.disposed, 1);
    runner.held[2].done.completeError(StateError('Planer geschlossen'));
    await settle(tester, frames: 30);
    final session = ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(loopPlannerProvider);
    expect((session.phase, session.blocker), (LoopPhase.idle, null));
    await openPlanner(tester);
    expect(find.byKey(const ValueKey('loop-blocker')), findsNothing);
    expect(find.byKey(const ValueKey('loop-summary')), findsNothing);
  });

  testWidgets('Ein Trail im geladenen Rahmen braucht keinen neuen Graphen, einer außerhalb schon (#188)',
      (tester) async {
    // Neben dem Hexentanz, im Rahmen aus Standort und Hexentanz; seine
    // Enden liegen 55 m von jedem Knoten — ohne vorheriges Anheften
    // teilte die zweite Rechnung eine Kante.
    final innen = trails.seedTrail(backend.currentUserId!, name: 'Innen', grade: 1, lat: 47.9995);
    final runner = _HeldRunner();
    await start(tester, areaStore: await _areaWithTrack(), runner: () => runner);
    await openPlanner(tester);
    final planner = ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(loopPlannerProvider.notifier);
    planner.setSelected([hex], true);
    await settle(tester);
    await tapRail(tester, 'loop-rail-compute');
    final first = runner.held.single;
    first.done.complete(first.request.planOn(first.graph));
    await settle(tester, frames: 30);
    final revision = first.graph.revision;

    await tester.tap(find.byKey(const ValueKey('loop-close')));
    await settle(tester);
    planner.setSelected([innen], true);
    await settle(tester);
    await tapRail(tester, 'loop-rail-compute');
    final second = runner.held[1];
    expect(identical(second.graph, first.graph), isTrue, reason: 'der Trail liegt schon auf dem Graphen');
    expect(second.request.pool.map((t) => t.name), unorderedEquals(['Hexentanz', 'Innen']));
    second.done.complete(second.request.planOn(second.graph));
    await settle(tester, frames: 30);
    expect(second.graph.revision, revision, reason: 'seine Enden sind schon angeheftet — keine Teilung');

    // Das Sperrgebiet liegt 300 m östlich, außerhalb des Rahmens.
    await tester.tap(find.byKey(const ValueKey('loop-close')));
    await settle(tester);
    planner.setSelected([sperr], true);
    await settle(tester);
    await tapRail(tester, 'loop-rail-compute');
    expect(identical(runner.held[2].graph, first.graph), isFalse, reason: 'neu geladen');
    runner.held[2].done.complete(runner.held[2].request.planOn(runner.held[2].graph));
    await settle(tester, frames: 30);
  });

  testWidgets('Uphill-Trails und Verbinder sind nicht wählbar — die Karte sagt es', (tester) async {
    trails.seedTrail(backend.currentUserId!, name: 'Auffahrt', lat: 48.0, lon: 9.008, traits: {TrailTrait.uphill});
    await start(tester, areaStore: await _areaWithTrack());
    await openPlanner(tester);
    await zoomToTrails(tester);
    await tapMapAt(tester, const LatLng(48.004, 9.008));
    await settle(tester);
    expect(find.byKey(const ValueKey('loop-not-pickable')), findsOneWidget);
    expect(picked(tester), isEmpty);
  });

  testWidgets('Parameter: Regler, Radius, Start auf der Karte und zurück zum Standort', (tester) async {
    final settings = FakeSettings();
    await start(tester, areaStore: await _areaWithTrack(), settings: settings);
    await openPlanner(tester);
    await tapRail(tester, 'loop-rail-params');
    expect(find.text('Parameter der Runde'), findsOneWidget);
    expect(find.textContaining('mein Standort'), findsOneWidget);
    expect(find.byKey(const ValueKey('loop-radius')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('loop-pick')));
    await settle(tester, frames: 10);
    expect(find.byKey(const ValueKey('loop-pick-banner')), findsOneWidget);
    await zoomToTrails(tester);
    // Ein Tipp — auch auf eine Linie — ist jetzt der Start, keine Auswahl.
    await tapMapAt(tester, const LatLng(48.004, _lon));
    await settle(tester);
    expect(find.byKey(const ValueKey('loop-pick-banner')), findsNothing);
    expect(find.byKey(const ValueKey('loop-start-pin')), findsOneWidget);
    expect(picked(tester), isEmpty);
    // Die Fahne trägt eine dunkle Kontur (#233) — Lime allein ging im
    // hellen Kartengrund unter.
    final flag = tester.widget<Icon>(
        find.descendant(of: find.byKey(const ValueKey('loop-start-pin')), matching: find.byType(Icon)));
    expect(find.descendant(of: find.byKey(const ValueKey('loop-start-pin')), matching: find.byType(LoopStartFlag)),
        findsOneWidget);
    expect(flag.shadows, isNotEmpty);
    expect(flag.shadows!.every((s) => s.color.computeLuminance() < 0.05), isTrue);
    await tapRail(tester, 'loop-rail-params');
    expect(find.textContaining('getippter Punkt'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('loop-start-me')));
    await settle(tester);
    expect(find.textContaining('mein Standort'), findsOneWidget);
  });

  testWidgets('Liste: nur im Radius, „Alle wählen", Stern; ein größerer Radius holt mehr', (tester) async {
    await start(tester, areaStore: await _areaWithTrack());
    await openPlanner(tester);
    await tapRail(tester, 'loop-rail-list');
    expect(find.text('Trails in 12 km'), findsOneWidget);
    expect(find.byKey(ValueKey('loop-trail-$hex')), findsOneWidget);
    expect(find.text('Fernweh'), findsNothing, reason: '22 km weg');
    expect(find.text('Gemeldet (1)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('loop-list-all')));
    await settle(tester);
    expect(tester.widget<CheckboxListTile>(find.byKey(ValueKey('loop-trail-$hex'))).value, isTrue);
    expect(tester.widget<CheckboxListTile>(find.byKey(ValueKey('loop-trail-$sperr'))).value, isFalse,
        reason: 'gemeldete nur einzeln');
    await tester.tap(find.byKey(ValueKey('loop-must-$hex')));
    await settle(tester);
    expect(find.descendant(of: find.byKey(ValueKey('loop-must-$hex')), matching: find.byIcon(Icons.star)),
        findsOneWidget);
    // Blatt zu, Radius auf 30 km: Fernweh kommt in die Liste.
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(picked(tester), hasLength(1));
    await tapRail(tester, 'loop-rail-params');
    final slider = find.descendant(of: find.byKey(const ValueKey('loop-radius')), matching: find.byType(Slider));
    await tester.ensureVisible(slider);
    await settle(tester, frames: 4);
    await tester.drag(slider, const Offset(400, 0));
    await settle(tester);
    expect(find.textContaining('30 km um den Start'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    await tapRail(tester, 'loop-rail-list');
    expect(find.text('Fernweh'), findsOneWidget);
  });

  testWidgets('Gebiet umfahren: die Trails darin kommen dazu, mit „weg" fallen sie heraus', (tester) async {
    await start(tester, areaStore: await _areaWithTrack());
    await openPlanner(tester);
    await zoomToTrails(tester);
    Future<void> drawAround() async {
      final cam = fakeMap(tester).camera;
      Offset at(double lat, double lon) => projectToScreen(cam, LatLng(lat, lon));
      final g = await tester.startGesture(at(47.999, 8.998));
      for (final p in [at(48.011, 8.998), at(48.011, 9.002), at(47.999, 9.002), at(47.999, 8.998)]) {
        await g.moveTo(p);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await settle(tester);
    }

    await tapRail(tester, 'loop-rail-area-add');
    expect(find.byKey(const ValueKey('loop-draw')), findsOneWidget);
    await drawAround();
    expect(find.byKey(const ValueKey('loop-draw')), findsNothing, reason: 'ein Strich, dann ist die Karte frei');
    expect(picked(tester), hasLength(1), reason: 'Hexentanz liegt drin, Sperrgebiet (300 m östlich) nicht');
    // Sichtbar auf hellem Grund (#233): deckendes Lime mit dunkler Kontur,
    // nicht 55 % ohne Rand, das im weißen Saum des Trails verschwand.
    final glow = picked(tester).single;
    expect(glow.color.a, 1.0);
    expect(glow.borderWidth, greaterThan(0));
    expect(glow.borderColor.computeLuminance(), lessThan(0.05));
    await tapRail(tester, 'loop-rail-area-remove');
    await drawAround();
    expect(picked(tester), isEmpty);
  });

  testWidgets('ohne gespeicherten Bereich: der Grund steht im Blatt, keine Runde', (tester) async {
    await start(tester);
    await openPlanner(tester);
    await zoomToTrails(tester);
    await tapMapAt(tester, const LatLng(48.004, _lon));
    await settle(tester);
    await tapRail(tester, 'loop-rail-compute');
    expect(find.byKey(const ValueKey('loop-blocker')), findsOneWidget);
    expect(find.textContaining('Kein gespeicherter Bereich'), findsOneWidget);
    expect(trailLines(tester), isEmpty);
  });

  testWidgets('#187: ohne Bereich, aber mit Empfang — die Wege kommen vom Host, und das Blatt sagt es',
      (tester) async {
    final host = _trackArchive().bytes;
    var opened = 0;
    final cache = OnlineTileCache();
    OnlineFill fill() => OnlineFill(
          openRoads: () async {
            opened++;
            return PmTilesVectorTileProvider.openBytes(host);
          },
          openHeights: () async => null,
          cache: cache,
        );
    await start(tester, onlineFill: fill);
    await openPlanner(tester);
    await zoomToTrails(tester);
    await tapMapAt(tester, const LatLng(48.004, _lon));
    await settle(tester);
    await tapRail(tester, 'loop-rail-compute');
    // Der Host liest echte Bytes; das Rechnen braucht ein paar Bilder mehr.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(tester, frames: 30);
    expect(find.byKey(const ValueKey('loop-blocker')), findsNothing);
    expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);
    expect(opened, 1);
    final list = find
        .descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable))
        .first;
    await tester.drag(list, const Offset(0, -500));
    await settle(tester);
    expect(find.textContaining('online nachgeladen'), findsOneWidget);
    expect(cache.length, greaterThan(0), reason: 'die Kacheln bleiben für die Sitzung');
  });

  testWidgets('#187: „Fehlende Wege online ergänzen" aus — gerechnet wird wie ohne Empfang', (tester) async {
    var opened = 0;
    OnlineFill fill() => OnlineFill(
          openRoads: () async {
            opened++;
            return PmTilesVectorTileProvider.openBytes(_trackArchive().bytes);
          },
          openHeights: () async => null,
          cache: OnlineTileCache(),
        );
    final settings = FakeSettings();
    await start(tester, onlineFill: fill, settings: settings);
    await openPlanner(tester);
    await tapRail(tester, 'loop-rail-params');
    final toggle = find.byKey(const ValueKey('loop-fill-online'));
    await tester.scrollUntilVisible(toggle, 200,
        scrollable: find
            .descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable))
            .first);
    await settle(tester, frames: 2);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue, reason: 'ab Werk an');
    await tester.tap(toggle);
    await settle(tester);
    expect(settings.loopPlannerPrefs, contains('o=0'), reason: 'das Gerät merkt es sich');
    await tester.tapAt(const Offset(10, 10));
    await settle(tester, frames: 20);
    await zoomToTrails(tester);
    await tapMapAt(tester, const LatLng(48.004, _lon));
    await settle(tester);
    await tapRail(tester, 'loop-rail-compute');
    expect(find.byKey(const ValueKey('loop-blocker')), findsOneWidget);
    expect(opened, 0, reason: 'aus heißt: keine Anfrage an den Host');
  });

  testWidgets('#188: die Vorlieben stehen in den Parametern, ab Werk meiden, gemerkt', (tester) async {
    final settings = FakeSettings();
    await start(tester, settings: settings);
    await openPlanner(tester);
    await tapRail(tester, 'loop-rail-params');
    final sheetList =
        find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable)).first;
    for (final (key, field) in const [('loop-pref-roads', 'sr'), ('loop-pref-hiking', 'sw'), ('loop-pref-steep', 'ss')]) {
      final toggle = find.byKey(ValueKey(key));
      await tester.scrollUntilVisible(toggle, 200, scrollable: sheetList);
      await settle(tester, frames: 2);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue, reason: '$key ab Werk meiden');
      await tester.tap(toggle);
      await settle(tester);
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(settings.loopPlannerPrefs, contains('$field=0'), reason: 'das Gerät merkt sich $key');
      if (key == 'loop-pref-roads') {
        expect(find.descendant(of: toggle, matching: find.textContaining('Straßen sind fast so gut wie Forstwege')),
            findsOneWidget,
            reason: 'der Satz sagt, was „egal" bewirkt');
      }
    }
  });

  testWidgets('ohne Standort: der Grund steht im Blatt, gefragt wurde einmal', (tester) async {
    final fix = FakePositionFix(null);
    await start(tester, areaStore: await _areaWithTrack(), positionFix: fix);
    await openPlanner(tester);
    expect(fix.calls, 0, reason: 'der Planer fragt nicht beim Öffnen');
    await zoomToTrails(tester);
    await tapMapAt(tester, const LatLng(48.004, _lon));
    await settle(tester);
    await tapRail(tester, 'loop-rail-compute');
    expect(find.textContaining('Kein Standort'), findsOneWidget);
    expect(fix.calls, 1);
  });

  testWidgets('Bereich deckt das Rechteck nur zum Teil: trotzdem eine Runde, mit Satz', (tester) async {
    await start(tester, areaStore: await _areaWithTrack(onlyCenter: true));
    await openPlanner(tester);
    await zoomToTrails(tester);
    await tapMapAt(tester, const LatLng(48.004, _lon));
    await settle(tester);
    await tapRail(tester, 'loop-rail-compute');
    expect(find.byKey(const ValueKey('loop-blocker')), findsNothing);
    expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);
    final list = find
        .descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable))
        .first;
    await tester.drag(list, const Offset(0, -500));
    await settle(tester);
    expect(find.byKey(const ValueKey('loop-partial')), findsOneWidget);
  });

  testWidgets('#177: langer Druck — „Route ab hier" öffnet den Planer mit Start, „Route bis hier" den Weg',
      (tester) async {
    await start(tester, areaStore: await _areaWithTrack());
    final point = LatLng(_fromLat + 0.001, _lon);
    await longPressMapAt(tester, point);
    await settle(tester);
    expect(find.byKey(const ValueKey('map-press-pin')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('map-menu-from')));
    await settle(tester, frames: 20);
    expect(find.byKey(const ValueKey('loop-tool-rail')), findsOneWidget);
    expect(find.byKey(const ValueKey('loop-start-pin')), findsOneWidget);
    expect(find.byKey(const ValueKey('map-press-pin')), findsNothing);
    await tapRail(tester, 'loop-rail-close');

    await longPressMapAt(tester, const LatLng(48.009, _lon));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('map-menu-to')));
    await settle(tester, frames: 30);
    expect(find.text('Route hierher'), findsOneWidget);
    expect(find.byKey(const ValueKey('trail-head-summary')), findsOneWidget);
    expect(connectionLines(tester), isNotEmpty);
  });

  testWidgets('#176: das Navi-Symbol fragt, merkt sich den Standard, „spaßig" öffnet den Weg auf der Karte',
      (tester) async {
    final settings = FakeSettings();
    await start(tester, areaStore: await _areaWithTrack(), settings: settings);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 10);
    await tapNav(tester);
    await settle(tester);
    expect(find.byKey(const ValueKey('nav-choice-external')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-remember')));
    await settle(tester, frames: 2);
    await tester.tap(find.byKey(const ValueKey('nav-choice-fun')));
    await settle(tester, frames: 30);
    expect(settings.navDefault, 'fun');
    expect(find.text('Zum Trailkopf'), findsOneWidget);
    final mode = tester.widget<SegmentedButton<RouteMode>>(find.byKey(const ValueKey('route-mode')));
    expect(mode.selected.single, RouteMode.fun);
    await tester.tap(find.byKey(const ValueKey('trail-head-close')));
    await settle(tester);

    // Mit Standard fragt es nicht mehr.
    await openTab(tester, 'Trails');
    await settle(tester, frames: 10);
    await tapNav(tester);
    await settle(tester, frames: 30);
    expect(find.byKey(const ValueKey('nav-choice-external')), findsNothing);
    expect(find.text('Zum Trailkopf'), findsOneWidget);
  });
}
