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
import 'package:trailbuddy/features/offline_areas/area_providers.dart' show areaHeightReaderProvider;
import 'package:trailbuddy/features/offline_areas/height_tiles.dart';
import 'package:trailbuddy/features/trails/elevation_profile_chart.dart';
import 'package:trailbuddy/features/routing/trail_head_providers.dart' show RouteMode;
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';
import 'package:trailbuddy/features/map/pmtiles_tile_provider.dart';
import 'package:trailbuddy/features/profile/profile_providers.dart';
import 'package:trailbuddy/features/routing/graph_input.dart';
import 'package:trailbuddy/features/routing/loop_plan_runner.dart';
import 'package:trailbuddy/features/routing/route_profile.dart' show RiderProfile;
import 'package:trailbuddy/features/routing/loop_planner_controller.dart';
import 'package:trailbuddy/features/routing/loop_planner.dart' show LoopPlan, LoopSearchCache;
import 'package:trailbuddy/features/routing/online_fill.dart';
import 'package:trailbuddy/features/rides/road_index.dart' show RoadCoverage;
import 'package:trailbuddy/features/routing/planning_graph.dart';
import 'package:trailbuddy/features/routing/road_graph_loader.dart' show kPlanMaxTiles;
import 'package:trailbuddy/features/routing/road_graph.dart' show RoadGraph;
import 'package:trailbuddy/features/routing/route_result.dart' show kRouteDirectBudget;
import 'package:trailbuddy/features/trails/gpx.dart';
import 'package:trailbuddy/models/trail.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart' show MapViewMarker;
import 'package:trailbuddy/features/map/poi.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_heights.dart';
import '../fakes/fake_settings.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/fake_pois.dart';
import '../fakes/route_lines.dart';
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

/// Rechnet an Ort und Stelle und merkt sich, was er gefragt wurde.
class _SpyRunner implements LoopPlanRunner {
  final _inline = InlineLoopPlanRunner();
  final requests = <LoopRequest>[];
  LoopPlan? last;

  @override
  Future<GraphReport> build(GraphInput input, {void Function(double value)? onProgress}) =>
      _inline.build(input, onProgress: onProgress);

  @override
  bool get hasGraph => _inline.hasGraph;

  @override
  Future<LoopPlan> plan(LoopRequest request, {void Function(double value)? onProgress}) async {
    requests.add(request);
    return last = await _inline.plan(request, onProgress: onProgress);
  }

  @override
  Future<R> run<R>(GraphJob<R> job) => _inline.run(job);

  @override
  void dispose() => _inline.dispose();
}

/// Ein Runner, der erst antwortet, wenn der Test es sagt — wie der
/// Rechen-Isolate auf dem Telefon, der eine Weile braucht (#188). Gebaut
/// wird sofort, an Ort und Stelle (#356 PR 8); der Test rechnet die
/// gehaltene Anfrage auf DEM Graphen, den der Runner hält.
class _HeldRunner implements LoopPlanRunner {
  final held = <({
    RoadGraph graph,
    LoopRequest request,
    Completer<LoopPlan> done,
    void Function(double value)? onProgress
  })>[];
  var disposed = 0;
  var builds = 0;
  RoadGraph? _graph;

  @override
  Future<GraphReport> build(GraphInput input, {void Function(double value)? onProgress}) async {
    builds++;
    final built = buildGraphFrom(input, builtIn: 'held');
    _graph = built.graph;
    return built.report;
  }

  @override
  bool get hasGraph => _graph != null;

  @override
  Future<LoopPlan> plan(LoopRequest request, {void Function(double value)? onProgress}) {
    final done = Completer<LoopPlan>();
    held.add((graph: _graph!, request: request, done: done, onProgress: onProgress));
    return done.future;
  }

  @override
  Future<R> run<R>(GraphJob<R> job) async => job.runOn(_graph!, LoopSearchCache());

  @override
  void dispose() {
    disposed++;
    _graph = null;
  }
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
      LoopPlanRunner Function()? runner,
      FakePoiSource? pois,
      List<Override> extra = const []}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, backend,
        trails: trails,
        areaStore: areaStore,
        rideStore: rides,
        positionFix: positionFix ?? FakePositionFix(fakePosition(_fromLat, _lon)),
        settings: settings,
        pois: pois,
        extraOverrides: [
          gpxShareProvider.overrideWithValue(recorder),
          if (onlineFill != null) onlineFillFactoryProvider.overrideWithValue((_) => onlineFill()),
          if (runner != null) loopPlanRunnerFactoryProvider.overrideWithValue(runner),
          ...extra,
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

  // Verbindungen tragen ein Tippziel; was doppelt gefahren wird, liegt als
  // zweite Zeichnung im Band (#295).
  Iterable<dynamic> connectionLines(WidgetTester tester) => routeHits(tester);
  Iterable<dynamic> picked(WidgetTester tester) =>
      fakeMapLayers(tester).polylines.where((l) => l.width == kLoopPickWidth && l.opacity == 1);

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
    expect(find.byKey(const ValueKey('elevation-profile')), findsNothing,
        reason: 'der Bereich hat keine Höhen — kein Profil, kein erfundenes (#234)');
    // Hexentanz trägt 4 Sterne: Die zweite Abfahrt bringt noch 30 %, und
    // das Budget reicht — also zweimal, 1,3 km Trail-Meter, „noch einmal".
    expect(find.textContaining('1,3 km Trail'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('loop-stop-0')), matching: find.text('Hexentanz')),
        findsOneWidget);
    expect(routeBand(tester).where((l) => l.pass == 1), isNotEmpty,
        reason: 'Hexentanz zweimal: das Stück liegt dichter');
    expect(connectionLines(tester), isNotEmpty);
    expect(picked(tester), isEmpty, reason: 'die Runde zeigt, was dabei ist');
    final whole = routeWhole(tester);
    expect(whole.first.latitude, closeTo(_fromLat, 1e-9));
    expect(whole.last.latitude, closeTo(_fromLat, 1e-9));
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
    expect(routeBand(tester), isEmpty);
    expect(find.byKey(const ValueKey('loop-tool-rail')), findsOneWidget);
    expect(picked(tester), hasLength(1));

    // Planer zu: Leiste weg, nichts leuchtet; ein Tipp wählt wieder aus.
    await tapRail(tester, 'loop-rail-close');
    expect(find.byKey(const ValueKey('loop-tool-rail')), findsNothing);
    expect(picked(tester), isEmpty);
  });

  group('Höhenprofil (#234)', () {
    final areaHeights =
        areaHeightReaderProvider.overrideWith((ref) async => HeightReader([MemoryHeightSource(slopeHeightTiles())]));

    ElevationProfileChart chartIn(WidgetTester tester, String key) => tester.widget<ElevationProfileChart>(
        find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(ElevationProfileChart)));

    testWidgets('die Runde: kompakt unter der Summe, über den Knöpfen, entlang der ganzen Linie', (tester) async {
      await start(tester, areaStore: await _areaWithTrack(), extra: [areaHeights]);
      await openPlanner(tester);
      await zoomToTrails(tester);
      await tapMapAt(tester, const LatLng(48.004, _lon));
      await settle(tester);
      await tapRail(tester, 'loop-rail-compute');
      await settle(tester, frames: 10);

      final chart = chartIn(tester, 'loop-elevation');
      expect(chart.compact, isTrue);
      expect(find.descendant(of: find.byKey(const ValueKey('loop-elevation')), matching: find.text('Start')), findsNothing,
          reason: 'kompakt: keine zweite Länge unter der Summe');
      // Die Runde endet, wo sie beginnt — das Profil auch.
      expect(chart.profile.startM, closeTo(chart.profile.endM, 1));
      expect(chart.profile.startM, closeTo(await slopeHeightAt(LatLng(_fromLat, _lon)), 1));
      expect(chart.profile.maxM - chart.profile.minM, greaterThan(50), reason: 'der Hang ist darin');
      // Unter der Summe, über den Knöpfen.
      final profileTop = tester.getTopLeft(find.byKey(const ValueKey('loop-elevation'))).dy;
      expect(profileTop, greaterThan(tester.getTopLeft(find.byKey(const ValueKey('loop-summary'))).dy));
      expect(profileTop, lessThan(tester.getTopLeft(find.byKey(const ValueKey('loop-save'))).dy));
    });

    testWidgets('Ziehen im Profil (#332): das Rad wandert auf der Linie, die Karte bleibt stehen', (tester) async {
      await start(tester, areaStore: await _areaWithTrack(), extra: [areaHeights]);
      await openPlanner(tester);
      await zoomToTrails(tester);
      await tapMapAt(tester, const LatLng(48.004, _lon));
      await settle(tester);
      await tapRail(tester, 'loop-rail-compute');
      await settle(tester, frames: 10);
      final plan = ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(loopPlannerProvider).plan!;
      MapViewMarker? cursor() =>
          fakeMapLayers(tester).markers.where((m) => m.key == const ValueKey('route-profile-cursor')).firstOrNull;
      expect(cursor(), isNull, reason: 'ohne Wahl kein Symbol');
      expect(find.descendant(of: find.byKey(const ValueKey('loop-elevation')), matching: find.byKey(const ValueKey('elevation-axis'))),
          findsOneWidget, reason: 'kompakt mit km-Skala');
      final camera = fakeMap(tester).center;

      final scrub = find.descendant(of: find.byKey(const ValueKey('loop-elevation')), matching: find.byKey(const ValueKey('elevation-scrub')));
      final box = tester.getRect(scrub);
      final gesture = await tester.startGesture(box.centerLeft + const Offset(4, 0));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      final first = cursor()!.point;
      await gesture.moveTo(box.center);
      await tester.pump();
      final mid = cursor()!.point;
      await gesture.up();
      await settle(tester);

      expect(mid, isNot(first), reason: 'das Symbol folgt dem Finger');
      // Auf der gezeichneten Linie: nah an einem ihrer Abschnitte.
      double offLine(LatLng p) => plan.points
          .map((q) => const Distance().as(LengthUnit.Meter, p, q))
          .reduce((a, b) => a < b ? a : b);
      expect(offLine(mid), lessThan(60), reason: 'auf der Route, nicht daneben');
      expect(cursor(), isNotNull, reason: 'nach dem Loslassen bleibt die Stelle stehen');
      expect(find.byKey(const ValueKey('elevation-cursor-label')), findsOneWidget);
      expect(fakeMap(tester).center, camera, reason: 'keine Kamerafahrt — die ganze Strecke bleibt im Bild');

      await tester.tap(find.byKey(const ValueKey('loop-close')));
      await settle(tester, frames: 30);
      expect(find.byKey(const ValueKey('loop-elevation')), findsNothing);
      expect(cursor(), isNull, reason: 'Planer zu, Symbol weg');
    });

    testWidgets('„Route hierher": dasselbe Profil, in Fahrtrichtung', (tester) async {
      await start(tester, areaStore: await _areaWithTrack(), extra: [areaHeights]);
      await longPressMapAt(tester, const LatLng(48.009, _lon));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('map-menu-to')));
      await settle(tester, frames: 30);
      expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);
      final chart = chartIn(tester, 'loop-elevation');
      expect(chart.compact, isTrue);
      // Vom Standort im Süden nach Norden: der Hang fällt nach Norden.
      expect(chart.profile.startM, greaterThan(chart.profile.endM + 30));
    });
  });

  testWidgets('Zwischenpunkt in der Runde (#234): feste Folge, getunt, zurück, frei gerechnet', (tester) async {
    await start(tester, areaStore: await _areaWithTrack());
    await openPlanner(tester);
    await zoomToTrails(tester);
    await tapMapAt(tester, const LatLng(48.004, _lon));
    await settle(tester);
    await tapRail(tester, 'loop-rail-compute');
    await settle(tester, frames: 10);
    expect(find.byKey(const ValueKey('loop-tune-hint')), findsOneWidget);
    Iterable<MapViewMarker> viaMarks() =>
        fakeMapLayers(tester).markers.where((m) => '${m.key}'.contains("'via-"));
    final stops = ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(loopPlannerProvider).plan!.stops.map((s) => s.trail.id).toList();

    // Ein Tipp auf die Verbindung zwischen Start und Trail. Hin- und
    // Rückweg liegen hier auf demselben Forstweg (zwei Abfahrten, drei
    // Teilstücke): Die oberste Linie gewinnt — der Rückweg, Teilstück 2.
    final mid = LatLng((_fromLat + 48.0) / 2, _lon);
    await tapMapAt(tester, mid);
    await settle(tester);
    expect(viaMarks().single.key, const ValueKey('via-2-0'));
    const handle = ValueKey('via-handle-2-0');
    final session = ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(loopPlannerProvider);
    expect(session.tuned, isTrue);
    expect(session.plan!.stops.map((s) => s.trail.id), stops, reason: 'die Folge steht fest');
    expect(find.byKey(const ValueKey('loop-tuned')), findsOneWidget);
    expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);

    // Neben jeden Weg gezogen: zurück, mit Satz; die Runde bleibt.
    await tester.drag(find.byKey(handle), const Offset(300, 0));
    await settle(tester);
    expect(find.byKey(const ValueKey('via-rejected')), findsOneWidget);
    expect(viaMarks().single.point, mid);
    expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);

    // Zurücksetzen rechnet frei: keine Punkte, nicht mehr getunt. Erst
    // das Blatt hochziehen — eingeklappt liegt die Zeile unter dem Rand.
    await tester.drag(
        find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable)).first,
        const Offset(0, -400));
    await settle(tester, frames: 4);
    await tester.ensureVisible(find.byKey(const ValueKey('loop-tune-reset')));
    await tester.tap(find.byKey(const ValueKey('loop-tune-reset')));
    await settle(tester, frames: 10);
    expect(viaMarks(), isEmpty);
    expect(ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(loopPlannerProvider).tuned, isFalse);
    expect(find.byKey(const ValueKey('loop-tune-hint')), findsOneWidget);

    // Blatt zu: Die Punkte fallen weg.
    await tapMapAt(tester, mid);
    await settle(tester);
    expect(viaMarks(), hasLength(1));
    await tester.scrollUntilVisible(find.byKey(const ValueKey('loop-close')), -200,
        scrollable:
            find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable)).first);
    await tester.tap(find.byKey(const ValueKey('loop-close')));
    await settle(tester);
    expect(viaMarks(), isEmpty);
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
    // Der Ladebalken (#356): erst unbestimmt, dann mit dem Anteil, den
    // der Runner meldet.
    expect(find.byKey(const ValueKey('loop-progress')), findsOneWidget);
    expect(find.text('40 %'), findsNothing);
    first.onProgress!(0.4);
    await tester.pump();
    expect(find.text('40 %'), findsOneWidget);
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
    expect(routeBand(tester), isEmpty, reason: 'keine Runde auf der Karte ohne Blatt');
    expect(find.byKey(const ValueKey('loop-tool-rail')), findsOneWidget, reason: 'der Planer bleibt offen');
    expect(runner.disposed, 0);

    // Dritte Rechnung, und Zurück schließt den Planer: Der Runner wird
    // freigegeben. Scheitert die Rechnung daran, ist das weder ein Grund
    // im Planer noch ein Fehlerbericht.
    await tapRail(tester, 'loop-rail-compute');
    expect(runner.held, hasLength(3));
    // Zurück stufenweise (10.5): erst das Ergebnis, dann der Planer.
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byKey(const ValueKey('loop-tool-rail')), findsOneWidget);
    expect(find.byKey(const ValueKey('loop-close')), findsNothing);
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

  group('Ändern, Zurück, Schließen (#356, Konzept-Routing 10.4/10.5)', () {
    LoopPlannerNotifier planner(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(loopPlannerProvider.notifier);
    LoopSession session(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(loopPlannerProvider);

    Future<void> computeHex(WidgetTester tester) async {
      await openPlanner(tester);
      planner(tester).setSelected([hex], true);
      await settle(tester);
      await tapRail(tester, 'loop-rail-compute');
    }

    testWidgets('eine Änderung bei offenem Ergebnis: Linie weg, „Auswahl geändert", „Neu rechnen" rechnet',
        (tester) async {
      await start(tester, areaStore: await _areaWithTrack());
      await computeHex(tester);
      expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);
      expect(routeBand(tester), isNotEmpty);

      // Ein Regler — oder ein Trail, ein Start, ein Punkt: dasselbe.
      planner(tester).setPrefs(session(tester).prefs.copyWith(hours: 2));
      await settle(tester);
      expect(find.byKey(const ValueKey('loop-changed')), findsOneWidget);
      expect(find.byKey(const ValueKey('loop-blocker')), findsNothing,
          reason: 'bis 0.127.4: „Die Runde ließ sich nicht rechnen — ein Fehler, der gemeldet ist"');
      expect(find.byKey(const ValueKey('loop-summary')), findsNothing);
      expect(routeBand(tester), isEmpty, reason: 'keine Linie vom letzten Mal');

      await tester.tap(find.byKey(const ValueKey('loop-recompute')));
      await settle(tester, frames: 30);
      expect(find.byKey(const ValueKey('loop-changed')), findsNothing);
      expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);
    });

    testWidgets('eine Änderung während der Rechnung: das späte Ergebnis schreibt nichts', (tester) async {
      final runner = _HeldRunner();
      await start(tester, areaStore: await _areaWithTrack(), runner: () => runner);
      await computeHex(tester);
      final held = runner.held.single;
      planner(tester).toggleMandatory(hex);
      await settle(tester);
      held.done.complete(held.request.planOn(held.graph));
      await settle(tester, frames: 30);
      expect(session(tester).plan, isNull);
      expect(find.byKey(const ValueKey('loop-changed')), findsOneWidget);
      expect(routeBand(tester), isEmpty);
    });

    testWidgets('das Fahrerprofil der Einstellungen erreicht den offenen Planer', (tester) async {
      await start(tester, areaStore: await _areaWithTrack());
      await computeHex(tester);
      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      expect(session(tester).profile, RiderProfile.bio);
      container.read(riderProfileProvider.notifier).set(RiderProfile.ebike);
      await settle(tester);
      expect(session(tester).profile, RiderProfile.ebike);
      expect(find.byKey(const ValueKey('loop-changed')), findsOneWidget);
    });

    testWidgets('Zurück stufenweise: Tippen abbrechen, Ergebnis zu, Planer zu, dann die normale Karte',
        (tester) async {
      await start(tester, areaStore: await _areaWithTrack());
      await computeHex(tester);
      planner(tester).armWaypointPick();
      await settle(tester);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(session(tester).picking, isFalse);
      expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget, reason: 'das Ergebnis bleibt');

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byKey(const ValueKey('loop-close')), findsNothing);
      expect(find.byKey(const ValueKey('loop-tool-rail')), findsOneWidget, reason: 'der Planer bleibt');
      expect(picked(tester), hasLength(1));

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byKey(const ValueKey('loop-tool-rail')), findsNothing);
      expect(find.byKey(const ValueKey('loop-button')), findsOneWidget, reason: 'die Knopfspalte steht wieder');
      expect(picked(tester), isEmpty);
      expect(session(tester).selected, isEmpty, reason: 'zu heißt aufgeräumt');
    });

    testWidgets('Zu mit Auswahl: „Rückgängig" holt Auswahl und Ergebnis zurück, ohne zu rechnen', (tester) async {
      final runner = _HeldRunner();
      await start(tester, areaStore: await _areaWithTrack(), runner: () => runner);
      await computeHex(tester);
      final held = runner.held.single;
      held.done.complete(held.request.planOn(held.graph));
      await settle(tester, frames: 30);
      planner(tester).takeWaypoint(const LatLng(48.0, _lon));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('loop-recompute')));
      await settle(tester, frames: 30);
      runner.held[1].done.complete(runner.held[1].request.planOn(runner.held[1].graph));
      await settle(tester, frames: 30);
      expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);

      // Blatt eingeklappt, dann das X der Leiste — mit offenem Ergebnis.
      final sheetList =
          find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable)).first;
      await tester.drag(sheetList, const Offset(0, 1500));
      await settle(tester, frames: 4);
      expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);
      await tapRail(tester, 'loop-rail-close');
      expect(find.byKey(const ValueKey('loop-tool-rail')), findsNothing);
      expect(find.byKey(const ValueKey('loop-summary')), findsNothing);
      expect(session(tester).waypoints, isEmpty);
      expect(find.byKey(const ValueKey('loop-closed')), findsOneWidget);

      await tester.tap(find.text('Rückgängig'));
      await settle(tester, frames: 30);
      expect(find.byKey(const ValueKey('loop-tool-rail')), findsOneWidget);
      expect(session(tester).selected, {hex});
      expect(session(tester).waypoints, hasLength(1));
      expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);
      expect(routeBand(tester), isNotEmpty);
      expect(runner.held, hasLength(2), reason: 'nichts neu gerechnet');
    });

    testWidgets('Zu ohne etwas Gesetztes: keine Meldung', (tester) async {
      await start(tester, areaStore: await _areaWithTrack());
      await openPlanner(tester);
      await tapRail(tester, 'loop-rail-close');
      expect(find.byKey(const ValueKey('loop-tool-rail')), findsNothing);
      expect(find.byKey(const ValueKey('loop-closed')), findsNothing);
    });

    testWidgets('ein Reiterwechsel beendet nichts: Planer und Ergebnis stehen bei der Rückkehr', (tester) async {
      await start(tester, areaStore: await _areaWithTrack());
      await computeHex(tester);
      await openTab(tester, 'Trails');
      await settle(tester);
      await openTab(tester, 'Karte');
      await settle(tester);
      expect(find.byKey(const ValueKey('loop-tool-rail')), findsOneWidget);
      expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);
      expect(session(tester).selected, {hex});
    });
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

  testWidgets('Ein neuer Fix im Rahmen baut den Graphen nicht neu, einer weit daneben schon (#370)', (tester) async {
    final fix = FakePositionFix(fakePosition(_fromLat, _lon));
    final runner = _HeldRunner();
    await start(tester, areaStore: await _areaWithTrack(), positionFix: fix, runner: () => runner);
    await openPlanner(tester);
    final planner = ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(loopPlannerProvider.notifier);
    planner.setSelected([hex], true);
    await settle(tester);

    Future<void> computeOnce() async {
      await tapRail(tester, 'loop-rail-compute');
      final held = runner.held.last;
      held.done.complete(held.request.planOn(held.graph));
      await settle(tester, frames: 30);
      await tester.tap(find.byKey(const ValueKey('loop-close')));
      await settle(tester);
    }

    await computeOnce();
    expect(runner.builds, 1);

    // Ein paar Meter weiter, wie jeder neue Fix des Standorts.
    fix.next = fakePosition(_fromLat + 0.00007, _lon + 0.00005);
    await computeOnce();
    expect(fix.calls, 2, reason: 'jede Rechnung holt einen Fix');
    expect(runner.held[1].request.start, LatLng(_fromLat + 0.00007, _lon + 0.00005), reason: 'mit dem neuen Start');
    expect(runner.builds, 1, reason: 'der Start liegt im Rahmen — derselbe Graph');
    expect(identical(runner.held[1].graph, runner.held[0].graph), isTrue);

    // 450 m westlich, über die Toleranz hinaus: neu bauen.
    fix.next = fakePosition(_fromLat, _lon - 0.006);
    await computeOnce();
    expect(runner.builds, 2, reason: 'der Start hat den Rahmen verlassen');
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

  testWidgets('„Gebiet zu groß" (#356 PR 8): der Lader zählt, das Blatt sagt die Zahlen und den Rat', (tester) async {
    await start(tester, areaStore: await _areaWithTrack(), extra: [
      planningGraphLoaderProvider.overrideWithValue((box, {fillOnline = true}) async =>
          const PlanningGraph(coverage: RoadCoverage.none, tilesFound: 0, tilesNeeded: 999, tooLarge: true)),
    ]);
    await openPlanner(tester);
    final planner = ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(loopPlannerProvider.notifier);
    planner.setSelected([hex], true);
    await settle(tester);
    await tapRail(tester, 'loop-rail-compute');
    await settle(tester, frames: 30);
    expect(find.byKey(const ValueKey('loop-blocker')), findsOneWidget);
    expect(find.textContaining('zu groß: 999 Kacheln, mehr als $kPlanMaxTiles'), findsOneWidget);
    expect(find.textContaining('Verkleinere den Radius'), findsOneWidget);
    expect(find.byKey(const ValueKey('loop-summary')), findsNothing);
  });

  testWidgets('Verbinder weit draußen vergrößern den Rahmen nicht mehr (#356 PR 8)', (tester) async {
    // Ein Uphill-Trail 17 km nördlich, im Radius der Liste (30 km) — bis
    // 0.131.0 zog er den Rahmen des Graphen bis zu sich (rund 30 Kacheln).
    trails.seedTrail(backend.currentUserId!, name: 'Fernauffahrt', lat: 48.15, lon: 9.0, traits: {TrailTrait.uphill});
    final settings = FakeSettings()..loopPlannerPrefs = 'h=3.0;c=800.0;w=1.0;r=1;k=30.0;o=0';
    await start(tester, areaStore: await _areaWithTrack(), settings: settings);
    await openPlanner(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    container.read(loopPlannerProvider.notifier).setSelected([hex], true);
    await settle(tester);
    await tapRail(tester, 'loop-rail-compute');
    await settle(tester, frames: 30);
    expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);
    final coverage = container.read(loopPlannerProvider).coverage!;
    expect(coverage.tilesNeeded, lessThan(6), reason: 'nur der Rahmen um Standort und Hexentanz');
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

  group('Ende der Fahrt (#331)', () {
    /// Zwischen Standort und Trailkopf, am Forstweg.
    final target = LatLng(_fromLat + 0.0015, _lon);

    Future<void> chooseEnd(WidgetTester tester, String key) async {
      await tapRail(tester, 'loop-rail-params');
      final sheetList =
          find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.byKey(ValueKey(key)), 200, scrollable: sheetList);
      await settle(tester, frames: 2);
      await tester.tap(find.byKey(ValueKey(key)));
      await settle(tester, frames: 10);
    }

    testWidgets('„Zum Ziel": Ziel tippen, Route endet dort, Zielfahne, heißt „Route", gemerkt', (tester) async {
      final settings = FakeSettings();
      await start(tester, areaStore: await _areaWithTrack(), settings: settings);
      await openPlanner(tester);
      expect(find.byKey(const ValueKey('loop-rail-target')), findsNothing, reason: 'ab Werk eine Runde');
      await zoomToTrails(tester);
      await tapMapAt(tester, const LatLng(48.004, _lon));
      await settle(tester);

      // Die Wahl ohne Ziel geht gleich auf die Karte.
      await chooseEnd(tester, 'loop-end-target');
      expect(settings.loopPlannerPrefs, contains('r=2'), reason: 'das Gerät merkt sich den Modus');
      expect(find.byKey(const ValueKey('loop-pick-banner')), findsOneWidget);
      expect(find.textContaining('wo die Route enden soll'), findsOneWidget);
      expect(find.byKey(const ValueKey('loop-rail-target')), findsOneWidget);
      fakeMap(tester).move(target, 15);
      await settle(tester, frames: 4);
      await tapMapAt(tester, target);
      await settle(tester);
      expect(find.byKey(const ValueKey('loop-pick-banner')), findsNothing);
      expect(picked(tester), hasLength(1), reason: 'der Tipp war das Ziel, keine Auswahl');
      final pin = find.byKey(const ValueKey('loop-end-pin'));
      expect(pin, findsOneWidget);
      expect(tester.widget<LoopStartFlag>(find.descendant(of: pin, matching: find.byType(LoopStartFlag))).finish,
          isTrue);
      expect(find.byKey(const ValueKey('loop-start-pin')), findsNothing, reason: 'Start ist der Standort');

      await tapRail(tester, 'loop-rail-compute');
      expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);
      expect(find.text('Route'), findsOneWidget, reason: 'endet nicht am Start: keine „Runde"');
      expect(find.text('Runde'), findsNothing);
      final whole = routeWhole(tester);
      expect(whole.first.latitude, closeTo(_fromLat, 1e-9));
      expect(whole.last.latitude, closeTo(target.latitude, 1e-9), reason: 'die Linie endet am Ziel');
      // Mit Ergebnis tragen beide Enden ihre Fahne — auch der Standort.
      expect(find.byKey(const ValueKey('loop-start-pin')), findsOneWidget);
      expect(find.byKey(const ValueKey('loop-end-pin')), findsOneWidget);
      // Ab Werk Direkt: Hexentanz ohne Stern bleibt liegen (#356 PR 7b);
      // Spaßig nimmt ihn mit.
      expect(find.byKey(const ValueKey('loop-stop-0')), findsNothing);
      final fun = find.descendant(of: find.byKey(const ValueKey('loop-route-mode')), matching: find.text('Spaßig'));
      await tester.ensureVisible(fun);
      await settle(tester, frames: 2);
      await tester.tap(fun);
      await settle(tester, frames: 30);
      expect(routeWhole(tester).last.latitude, closeTo(target.latitude, 1e-9));

      await tester.ensureVisible(find.byKey(const ValueKey('loop-save')));
      await settle(tester, frames: 2);
      await tester.tap(find.byKey(const ValueKey('loop-save')));
      await settle(tester);
      expect(rides.rides.single.name, 'Route: Hexentanz');
    });

    /// Aus der Liste ins Trail-Blatt und dort auf [key].
    Future<void> fromTrailSheet(WidgetTester tester, String key) async {
      await openTab(tester, 'Trails');
      await settle(tester, frames: 20);
      final row = find.text('Hexentanz');
      await tester.scrollUntilVisible(row, 100, scrollable: find.byType(Scrollable).hitTestable().first);
      await settle(tester);
      await tester.tap(row);
      await settle(tester);
      final button = find.byKey(ValueKey(key));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await settle(tester, frames: 30);
    }

    testWidgets('Trailkopf als Start (Schritt 2): Planer auf, Fahne am Kopf, Trail gewählt, Runde ab dort',
        (tester) async {
      await start(tester, areaStore: await _areaWithTrack());
      await fromTrailSheet(tester, 'trail-plan-from');
      expect(find.byKey(const ValueKey('loop-tool-rail')), findsOneWidget, reason: 'der Planer ist auf der Karte');
      expect(find.byKey(const ValueKey('loop-pick-banner')), findsNothing);
      expect(find.byKey(const ValueKey('loop-start-pin')), findsOneWidget);
      expect(picked(tester), hasLength(1), reason: 'wer am Kopf startet, will den Trail fahren');

      await tapRail(tester, 'loop-rail-compute');
      expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);
      expect(find.text('Runde'), findsOneWidget);
      final whole = routeWhole(tester);
      expect(whole.first.latitude, closeTo(48.0, 1e-9), reason: 'Start am Trailkopf, nicht am Standort');
      expect(whole.last.latitude, closeTo(48.0, 1e-9));
    });

    testWidgets('Trailkopf als Ziel (Schritt 2): Modus „Zum Ziel", Zielfahne, Route endet am Kopf', (tester) async {
      final settings = FakeSettings();
      await start(tester, areaStore: await _areaWithTrack(), settings: settings);
      await fromTrailSheet(tester, 'trail-plan-to');
      expect(find.byKey(const ValueKey('loop-tool-rail')), findsOneWidget);
      expect(settings.loopPlannerPrefs, contains('r=2'), reason: 'das Ziel schaltet auf „Zum Ziel"');
      expect(find.byKey(const ValueKey('loop-pick-banner')), findsNothing, reason: 'das Ziel steht schon');
      expect(find.byKey(const ValueKey('loop-rail-target')), findsOneWidget);
      expect(find.byKey(const ValueKey('loop-end-pin')), findsOneWidget);
      expect(picked(tester), isEmpty, reason: 'am Kopf endet die Fahrt — der Trail bleibt, wie er war');

      await zoomToTrails(tester);
      await tapMapAt(tester, const LatLng(48.004, _lon));
      await settle(tester);
      await tapRail(tester, 'loop-rail-compute');
      expect(find.text('Route'), findsOneWidget);
      final whole = routeWhole(tester);
      expect(whole.first.latitude, closeTo(_fromLat, 1e-9));
      expect(whole.last.latitude, closeTo(48.0, 1e-9), reason: 'die Route endet am Trailkopf');
    });

    // Ein Brunnen am Forstweg zwischen Standort und Trailkopf (#331
    // Schritt 3) — Trinkwasser zeigt die Karte ab Werk.
    final spring = Poi(id: 'node/7', kind: PoiKind.drinkingWater, position: LatLng(_fromLat + 0.0015, _lon), name: 'Hangbrunnen');
    final springPin = find.byKey(const ValueKey('poi-node/7'));

    /// Nah heran; die Orte kommen bei Stillstand der Kamera.
    Future<void> zoomToSpring(WidgetTester tester) async {
      await zoomToTrails(tester);
      await settle(tester, frames: 20);
      expect(springPin, findsOneWidget);
    }

    Future<void> fromPlaceSheet(WidgetTester tester, String key) async {
      await zoomToSpring(tester);
      await tapMapAt(tester, spring.position);
      await settle(tester);
      expect(find.text('Hangbrunnen'), findsOneWidget);
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await settle(tester, frames: 2);
      await tester.tap(find.byKey(ValueKey(key)));
      await settle(tester, frames: 30);
    }

    testWidgets('Ort als Start (Schritt 3): aus seinem Blatt, Planer auf, Runde ab dem Ort', (tester) async {
      await start(tester, areaStore: await _areaWithTrack(), pois: FakePoiSource([spring]));
      await fromPlaceSheet(tester, 'poi-plan-from');
      expect(find.byKey(const ValueKey('loop-tool-rail')), findsOneWidget, reason: 'der Planer ist auf der Karte');
      expect(find.byKey(const ValueKey('loop-start-pin')), findsOneWidget);
      expect(picked(tester), isEmpty, reason: 'ein Ort wählt keinen Trail');

      await tapMapAt(tester, const LatLng(48.004, _lon));
      await settle(tester);
      await tapRail(tester, 'loop-rail-compute');
      expect(find.text('Runde'), findsOneWidget);
      final whole = routeWhole(tester);
      expect(whole.first.latitude, closeTo(spring.position.latitude, 1e-9), reason: 'Start am Ort, nicht am Standort');
      expect(whole.last.latitude, closeTo(spring.position.latitude, 1e-9));
    });

    testWidgets('Ort als Ziel (Schritt 3): Modus „Zum Ziel", Route endet am Ort', (tester) async {
      final settings = FakeSettings();
      await start(tester, areaStore: await _areaWithTrack(), settings: settings, pois: FakePoiSource([spring]));
      await openPlanner(tester);
      await fromPlaceSheet(tester, 'poi-plan-to');
      expect(settings.loopPlannerPrefs, contains('r=2'), reason: 'das Ziel schaltet auf „Zum Ziel"');
      expect(find.byKey(const ValueKey('loop-pick-banner')), findsNothing, reason: 'das Ziel steht schon');
      expect(find.byKey(const ValueKey('loop-end-pin')), findsOneWidget);

      await tapMapAt(tester, const LatLng(48.004, _lon));
      await settle(tester);
      await tapRail(tester, 'loop-rail-compute');
      expect(find.text('Route'), findsOneWidget);
      final whole = routeWhole(tester);
      expect(whole.first.latitude, closeTo(_fromLat, 1e-9));
      expect(whole.last.latitude, closeTo(spring.position.latitude, 1e-9), reason: 'die Route endet am Ort');
    });

    testWidgets('#356: „Route hierher" im Ort-Blatt rechnet sofort, Zurück führt zur normalen Karte', (tester) async {
      await start(tester, areaStore: await _areaWithTrack(), pois: FakePoiSource([spring]));
      await fromPlaceSheet(tester, 'poi-route');
      expect(find.byKey(const ValueKey('loop-tool-rail')), findsOneWidget, reason: 'derselbe Planer');
      expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget, reason: 'gerechnet ohne weiteren Tipp');
      expect(find.text('Route'), findsOneWidget);
      final whole = routeWhole(tester);
      expect(whole.first.latitude, closeTo(_fromLat, 1e-9), reason: 'Start am Standort');
      expect(whole.last.latitude, closeTo(spring.position.latitude, 1e-9), reason: 'die Route endet am Ort');

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byKey(const ValueKey('loop-tool-rail')), findsNothing);
      expect(find.byKey(const ValueKey('loop-closed')), findsNothing, reason: 'nichts gebaut, nichts rückgängig zu machen');
      expect(connectionLines(tester), isEmpty);
    });

    testWidgets('#356: ein neuer Auftrag ersetzt eine Planung mit Auswahl erst nach Rückfrage', (tester) async {
      await start(tester, areaStore: await _areaWithTrack());
      await openPlanner(tester);
      await zoomToTrails(tester);
      await tapMapAt(tester, const LatLng(48.004, _lon));
      await settle(tester);
      expect(picked(tester), hasLength(1));

      // „Zum Trailkopf" — gefragt, abgebrochen: alles bleibt.
      await fromTrailSheet(tester, 'trail-head');
      expect(find.byKey(const ValueKey('loop-replace')), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await settle(tester, frames: 10);
      expect(find.byKey(const ValueKey('loop-summary')), findsNothing);
      expect(picked(tester), hasLength(1), reason: 'die Auswahl bleibt');

      // Noch einmal, ersetzt: die Route zum Trailkopf, ohne Auswahl.
      await fromTrailSheet(tester, 'trail-head');
      await tester.tap(find.byKey(const ValueKey('loop-replace-ok')));
      await settle(tester, frames: 30);
      expect(find.text('Zum Trailkopf: Hexentanz'), findsOneWidget);
      expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);
      expect(routeWhole(tester).last.latitude, closeTo(48.0, 1e-9));
    });

    testWidgets('Start tippen auf einen Ort: der Punkt ist der Ort, nicht der Finger, kein Blatt', (tester) async {
      await start(tester, areaStore: await _areaWithTrack(), pois: FakePoiSource([spring]));
      await openPlanner(tester);
      await tapRail(tester, 'loop-rail-params');
      await tester.tap(find.byKey(const ValueKey('loop-pick')));
      await settle(tester, frames: 10);
      await zoomToSpring(tester);
      // Ein paar Meter daneben — der Finger trifft nie genau.
      await tapMapAt(tester, LatLng(spring.position.latitude + 0.00006, _lon + 0.00006));
      await settle(tester);
      expect(find.text('Hangbrunnen'), findsNothing, reason: 'der Tipp war der Start');
      expect(find.byKey(const ValueKey('loop-start-pin')), findsOneWidget);

      await tapMapAt(tester, const LatLng(48.004, _lon));
      await settle(tester);
      await tapRail(tester, 'loop-rail-compute');
      expect(routeWhole(tester).first.latitude, closeTo(spring.position.latitude, 1e-9));
    });

    // Über dem Trailende, noch am Forstweg: frei kehrt die Runde dort um.
    const via = LatLng(48.0093, _lon);
    final viaPin = find.byKey(const ValueKey('loop-waypoint-0'));
    double northmost(WidgetTester tester) => routeWhole(tester).map((p) => p.latitude).reduce(math.max);

    testWidgets('Zwischenpunkt vorab (Schritt 4): tippen, wegtippen, zurück, Runde führt hindurch', (tester) async {
      await start(tester, areaStore: await _areaWithTrack());
      await openPlanner(tester);
      await zoomToTrails(tester);
      await tapMapAt(tester, const LatLng(48.004, _lon));
      await settle(tester);
      await tapRail(tester, 'loop-rail-compute');
      expect(northmost(tester), lessThan(48.0091), reason: 'frei kehrt die Runde am Trailende um');
      await tester.tap(find.byKey(const ValueKey('loop-close')));
      await settle(tester);

      await tapRail(tester, 'loop-rail-waypoint');
      expect(find.byKey(const ValueKey('loop-pick-banner')), findsOneWidget);
      expect(find.textContaining('vorbeiführen soll'), findsOneWidget);
      fakeMap(tester).move(via, 16);
      await settle(tester, frames: 4);
      await tapMapAt(tester, via);
      await settle(tester);
      expect(find.byKey(const ValueKey('loop-pick-banner')), findsNothing);
      expect(viaPin, findsOneWidget);
      expect(picked(tester), hasLength(1), reason: 'der Tipp war der Punkt, keine Auswahl');

      // Ein Tipp auf die Nadel nimmt sie weg, Rückgängig bringt sie zurück.
      await tapMapAt(tester, via);
      await settle(tester);
      expect(viaPin, findsNothing);
      expect(find.byKey(const ValueKey('loop-waypoint-removed')), findsOneWidget);
      await tester.tap(find.text('Rückgängig'));
      await settle(tester);
      expect(viaPin, findsOneWidget);

      await tapRail(tester, 'loop-rail-compute');
      expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);
      expect(find.text('Runde'), findsOneWidget);
      // Angeheftet wird am nächsten Knoten — hier das Ende des Forstwegs.
      expect(northmost(tester), greaterThan(via.latitude - 1e-6), reason: 'die Runde führt durch den Punkt');
      expect(routeWhole(tester).last.latitude, closeTo(_fromLat, 1e-9), reason: 'und zurück zum Start');
      expect(viaPin, findsOneWidget, reason: 'die Nadel bleibt beim Ergebnis');
    });

    testWidgets('Zwischenpunkt vorab aus dem Ort-Blatt und aus den Parametern; „Alle entfernen"', (tester) async {
      await start(tester, areaStore: await _areaWithTrack(), pois: FakePoiSource([spring]));
      await fromPlaceSheet(tester, 'poi-plan-via');
      expect(find.byKey(const ValueKey('loop-tool-rail')), findsOneWidget, reason: 'der Planer ist auf der Karte');
      expect(viaPin, findsOneWidget);
      expect(find.byKey(const ValueKey('loop-start-pin')), findsNothing, reason: 'der Start bleibt der Standort');

      await tapRail(tester, 'loop-rail-params');
      final sheetList = find.byType(Scrollable).hitTestable().last;
      await tester.scrollUntilVisible(find.byKey(const ValueKey('loop-pick-waypoint')), 200, scrollable: sheetList);
      expect(find.textContaining('über 1 Punkt'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('loop-pick-waypoint')));
      await settle(tester, frames: 10);
      expect(find.textContaining('vorbeiführen soll'), findsOneWidget);
      fakeMap(tester).move(via, 16);
      await settle(tester, frames: 4);
      await tapMapAt(tester, via);
      await settle(tester);
      expect(find.byKey(const ValueKey('loop-waypoint-1')), findsOneWidget);

      await tapRail(tester, 'loop-rail-params');
      final list = find.byType(Scrollable).hitTestable().last;
      await tester.scrollUntilVisible(find.byKey(const ValueKey('loop-waypoints-clear')), 200, scrollable: list);
      expect(find.textContaining('über 2 Punkte'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('loop-waypoints-clear')));
      await settle(tester, frames: 2);
      await tester.tap(find.byKey(const ValueKey('loop-waypoints-clear')));
      await settle(tester);
      // Die Liste ist dabei über den Hinweis hinaus gescrollt.
      expect(find.textContaining('nirgends vorbei', skipOffstage: false), findsOneWidget);
      expect(viaPin, findsNothing);
    });

    testWidgets('„Zum Ziel" ohne Ziel: der Grund steht im Blatt; „Letzter Trail" endet am Trail', (tester) async {
      await start(tester, areaStore: await _areaWithTrack());
      await openPlanner(tester);
      await zoomToTrails(tester);
      await tapMapAt(tester, const LatLng(48.004, _lon));
      await settle(tester);
      await chooseEnd(tester, 'loop-end-target');
      // Zurück bricht den Tipp ab, der Modus bleibt.
      await tapRail(tester, 'loop-rail-target');
      expect(find.byKey(const ValueKey('loop-pick-banner')), findsNothing);
      await tapRail(tester, 'loop-rail-compute');
      expect(find.byKey(const ValueKey('loop-blocker')), findsOneWidget);
      expect(find.textContaining('Kein Ziel gesetzt'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('loop-close')));
      await settle(tester);

      await chooseEnd(tester, 'loop-end-last');
      expect(find.byKey(const ValueKey('loop-pick-banner')), findsNothing);
      expect(find.byKey(const ValueKey('loop-rail-target')), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await settle(tester, frames: 10);
      await tapRail(tester, 'loop-rail-compute');
      expect(find.text('Route'), findsOneWidget);
      final whole = routeWhole(tester);
      expect(whole.last.latitude, greaterThan(48.008), reason: 'Ende am Ende des Trails, nicht am Start');
      expect(find.byKey(const ValueKey('loop-end-pin')), findsOneWidget);
    });

    testWidgets('Route ohne Trail (#356): Ziel tippen, rechnen; Stil und Rad rechnen sofort, Spaßig nimmt den Trail mit',
        (tester) async {
      final settings = FakeSettings();
      // 150 m neben jedem Weg: im Pool des Umwegs, aber nie erreichbar.
      final abseits = trails.seedTrail(backend.currentUserId!, name: 'Abseits', grade: 1, lat: 48.003, lon: 9.002);
      final runner = _SpyRunner();
      await start(tester, areaStore: await _areaWithTrack(), settings: settings, runner: () => runner);
      await openPlanner(tester);
      await chooseEnd(tester, 'loop-end-target');
      // Nördlich des Trailendes, am Forstweg: Der direkte Weg führt am
      // Hexentanz entlang, der spaßige über ihn.
      const finish = LatLng(48.0092, _lon);
      fakeMap(tester).move(const LatLng(48.004, _lon), 15);
      await settle(tester, frames: 4);
      await tapMapAt(tester, finish);
      await settle(tester);
      expect(picked(tester), isEmpty);
      expect(find.textContaining('rechne gleich die Route zum Ziel'), findsOneWidget, reason: 'der Hinweis sagt es');
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('loop-rail-compute'))).onPressed, isNotNull,
          reason: 'zum Ziel geht es ohne Trail');

      await tapRail(tester, 'loop-rail-compute');
      expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);
      expect(find.textContaining('hm bergab'), findsOneWidget, reason: 'die Zeile der Route, ohne Trail-Meter');
      expect(find.byKey(const ValueKey('loop-route-mode')), findsOneWidget);
      expect(find.byKey(const ValueKey('loop-stop-0')), findsNothing);
      expect(find.text('Route'), findsOneWidget);
      final whole = routeWhole(tester);
      expect(whole.first.latitude, closeTo(_fromLat, 1e-9));
      expect(whole.last.latitude, closeTo(finish.latitude, 1e-9));
      expect(routeHits(tester), isNotEmpty, reason: 'ziehbare Punkte wie bei der Runde');

      await tester.ensureVisible(find.byKey(const ValueKey('loop-save')));
      await settle(tester, frames: 2);
      await tester.tap(find.byKey(const ValueKey('loop-save')));
      await settle(tester);
      expect(rides.rides.single.name, 'Route');

      Future<void> segment(String key, String label) async {
        final f = find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(label));
        await tester.ensureVisible(f);
        await settle(tester, frames: 2);
        await tester.tap(f);
        await settle(tester, frames: 30);
      }

      await segment('loop-route-mode', 'Bequem');
      expect(find.byKey(const ValueKey('loop-changed')), findsNothing, reason: 'der Stil rechnet sofort (D3)');
      expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);
      expect(find.byKey(const ValueKey('loop-easy-note')), findsOneWidget);
      expect(settings.loopPlannerPrefs, contains('y=e'), reason: 'der Stil wird gemerkt');
      expect(runner.requests.last.profile.prefs.easy, isTrue, reason: 'gerechnet mit den Kosten des Stils');
      expect(runner.requests.last.bare, isTrue);

      await segment('loop-route-mode', 'Spaßig');
      expect(find.descendant(of: find.byKey(const ValueKey('loop-stop-0')), matching: find.text('Hexentanz')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('loop-fun-empty')), findsNothing);
      expect(runner.requests.last.pool.map((t) => t.id), contains(abseits), reason: 'im Pool des Umwegs');
      expect(runner.last!.excluded.keys, contains(abseits));
      expect(find.byKey(ValueKey('loop-excluded-$abseits')), findsNothing,
          reason: 'was der Umweg nicht nahm, hat niemand gewählt');
      expect(runner.requests.last.profile.prefs.easy, isFalse);

      await segment('loop-result-profile', 'E-Bike');
      expect(find.byKey(const ValueKey('loop-changed')), findsNothing, reason: 'das Rad rechnet sofort (D3)');
      expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);
      final session = ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(loopPlannerProvider);
      expect(session.profile, RiderProfile.ebike);
      expect(session.planBare, isTrue);
    });

    testWidgets('Route mit Auswahl (#356 PR 7b): Direkt nur mit Stern, Bequem und Spaßig nehmen die Auswahl mit',
        (tester) async {
      final runner = _SpyRunner();
      await start(tester, areaStore: await _areaWithTrack(), runner: () => runner);
      await openPlanner(tester);
      await chooseEnd(tester, 'loop-end-target');
      const finish = LatLng(48.0092, _lon);
      fakeMap(tester).move(const LatLng(48.004, _lon), 15);
      await settle(tester, frames: 4);
      await tapMapAt(tester, finish);
      await settle(tester);
      await tapMapAt(tester, const LatLng(48.004, _lon));
      await settle(tester);
      expect(picked(tester), hasLength(1));

      Future<void> segment(String label) async {
        final f = find.descendant(of: find.byKey(const ValueKey('loop-route-mode')), matching: find.text(label));
        await tester.ensureVisible(f);
        await settle(tester, frames: 2);
        await tester.tap(f);
        await settle(tester, frames: 30);
      }

      // Ab Werk Direkt: Hexentanz hat keinen Stern, also bleibt er liegen.
      await tapRail(tester, 'loop-rail-compute');
      expect(find.byKey(const ValueKey('loop-route-mode')), findsOneWidget, reason: 'der Stil auch mit Auswahl');
      expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);
      expect(runner.requests.last.pool, isEmpty, reason: 'Direkt nimmt nur Pflicht-Trails');
      expect(runner.requests.last.bare, isTrue);
      expect(runner.requests.last.budget.timeS, kRouteDirectBudget.timeS, reason: 'ohne Budget');
      expect(find.byKey(const ValueKey('loop-stop-0')), findsNothing);
      expect(find.byKey(const ValueKey('loop-direct-note')), findsOneWidget);

      await segment('Bequem');
      expect(find.byKey(const ValueKey('loop-changed')), findsNothing, reason: 'der Stil rechnet sofort (D3)');
      expect(runner.requests.last.pool.map((t) => t.id), [hex]);
      expect(runner.requests.last.profile.prefs.easy, isTrue, reason: 'Verbindungen mit den Kosten des Stils');
      expect(runner.requests.last.bare, isFalse);
      expect(runner.requests.last.budget.timeS, isNot(kRouteDirectBudget.timeS), reason: 'Budgets des Planers');
      expect(find.descendant(of: find.byKey(const ValueKey('loop-stop-0')), matching: find.text('Hexentanz')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('loop-easy-note')), findsOneWidget);
      expect(find.byKey(const ValueKey('loop-direct-note')), findsNothing);

      await segment('Spaßig');
      expect(runner.requests.last.pool.map((t) => t.id), [hex]);
      expect(runner.requests.last.profile.prefs.easy, isFalse);
      expect(find.byKey(const ValueKey('loop-easy-note')), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('loop-stop-0')), matching: find.text('Hexentanz')),
          findsOneWidget);

      // Mit Stern nimmt auch Direkt ihn mit.
      final notifier =
          ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(loopPlannerProvider.notifier);
      notifier.toggleMandatory(hex);
      await settle(tester);
      await segment('Direkt');
      expect(runner.requests.last.pool.map((t) => t.id), [hex]);
      expect(runner.requests.last.pool.single.mandatory, isTrue);
      expect(runner.requests.last.bare, isTrue);
      expect(find.descendant(of: find.byKey(const ValueKey('loop-stop-0')), matching: find.text('Hexentanz')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('loop-direct-note')), findsNothing, reason: 'nichts liegen geblieben');
    });

    testWidgets('„Bergauf bequem" (#356 PR 7b): Schalter der Runde, gemerkt, rechnet mit den Kosten des Stils',
        (tester) async {
      final settings = FakeSettings();
      final runner = _SpyRunner();
      await start(tester, areaStore: await _areaWithTrack(), settings: settings, runner: () => runner);
      await openPlanner(tester);
      await zoomToTrails(tester);
      await tapMapAt(tester, const LatLng(48.004, _lon));
      await settle(tester);
      await tapRail(tester, 'loop-rail-compute');
      expect(runner.requests.last.profile.prefs.easy, isFalse, reason: 'ab Werk aus');
      expect(find.byKey(const ValueKey('loop-easy-note')), findsNothing);
      expect(find.byKey(const ValueKey('loop-route-mode')), findsNothing, reason: 'die Runde hat keinen Stil');

      await chooseEnd(tester, 'loop-easy-up');
      expect(settings.loopPlannerPrefs, contains('u=1'));
      await tester.tapAt(const Offset(10, 10));
      await settle(tester);
      expect(find.byKey(const ValueKey('loop-changed')), findsOneWidget, reason: 'ein Regler, kein Stil (D3)');
      await tester.tap(find.byKey(const ValueKey('loop-recompute')));
      await settle(tester, frames: 30);
      expect(runner.requests.last.profile.prefs.easy, isTrue);
      expect(runner.requests.last.pool.map((t) => t.id), [hex], reason: 'die Trails bleiben');
      expect(find.byKey(const ValueKey('loop-easy-note')), findsOneWidget);
    });
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
    expect(routeBand(tester), isEmpty);
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

  testWidgets('#371: „Planer geschlossen · Rückgängig" geht nach seiner Dauer von selbst', (tester) async {
    await start(tester, areaStore: await _areaWithTrack());
    await longPressMapAt(tester, LatLng(_fromLat + 0.001, _lon));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('map-menu-from')));
    await settle(tester, frames: 20);
    await tapRail(tester, 'loop-rail-close');
    expect(find.byKey(const ValueKey('loop-closed')), findsOneWidget);
    // Seit Flutter 3.47 bliebe eine Leiste mit Aktion ohne `persist: false`
    // für immer stehen — auf dem Pixel über „Navigation starten".
    await settle(tester, frames: 50);
    await settle(tester);
    expect(find.byKey(const ValueKey('loop-closed')), findsNothing);
  });

  testWidgets('#177/#356: langer Druck — „Start hier", „Zwischenpunkt hier" und „Route bis hier" im Planer',
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
    // Der Start war gesetzt: Zu kommt mit „Rückgängig" (10.5) — weg damit,
    // die Meldung läge über dem Menü.
    expect(find.byKey(const ValueKey('loop-closed')), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byKey(const ValueKey('loop-closed')))).removeCurrentSnackBar();
    await settle(tester);

    // „Zwischenpunkt hier": der Planer mit einem Punkt, der Start bleibt
    // der Standort.
    await longPressMapAt(tester, point);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('map-menu-via')));
    await settle(tester, frames: 20);
    expect(find.byKey(const ValueKey('loop-tool-rail')), findsOneWidget);
    expect(find.byKey(const ValueKey('loop-waypoint-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('loop-start-pin')), findsNothing);
    await tapRail(tester, 'loop-rail-close');
    ScaffoldMessenger.of(tester.element(find.byKey(const ValueKey('loop-closed')))).removeCurrentSnackBar();
    await settle(tester);

    // „Route bis hier" rechnet sofort, im Planer (Konzept-Routing 10.3);
    // Zurück führt mit einem Schritt zur normalen Karte (10.5).
    await longPressMapAt(tester, const LatLng(48.009, _lon));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('map-menu-to')));
    await settle(tester, frames: 30);
    expect(find.text('Route'), findsOneWidget);
    expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);
    expect(find.byKey(const ValueKey('loop-external')), findsOneWidget);
    expect(connectionLines(tester), isNotEmpty);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byKey(const ValueKey('loop-tool-rail')), findsNothing);
    expect(find.byKey(const ValueKey('loop-summary')), findsNothing);
    expect(connectionLines(tester), isEmpty);
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
    expect(find.text('Zum Trailkopf: Hexentanz'), findsOneWidget);
    final mode = tester.widget<SegmentedButton<RouteMode>>(find.byKey(const ValueKey('loop-route-mode')));
    expect(mode.selected.single, RouteMode.fun);
    await tester.tap(find.byKey(const ValueKey('loop-close')));
    await settle(tester);
    expect(find.byKey(const ValueKey('loop-tool-rail')), findsNothing, reason: 'Schnell zu (10.4)');

    // Mit Standard fragt es nicht mehr.
    await openTab(tester, 'Trails');
    await settle(tester, frames: 10);
    await tapNav(tester);
    await settle(tester, frames: 30);
    expect(find.byKey(const ValueKey('nav-choice-external')), findsNothing);
    expect(find.text('Zum Trailkopf: Hexentanz'), findsOneWidget);
  });
}
