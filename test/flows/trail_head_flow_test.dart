// „Zum Trailkopf" durch die echte Oberfläche (#158 Schritt 4): aus dem
// Trail-Blatt auf die Karte, Standort über den EINEN Fix, Graph aus einem
// gespeicherten Bereich mit erzeugter Kachel, Zusammenfassung, Vorschau
// als Linie der Fassade, Profilwechsel, GPX über den Recorder; und die
// beiden Fälle, in denen nichts gerechnet werden kann (kein Bereich, kein
// Standort) — die sagen es und bieten die Anfahrt an.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/core/gpx_share.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';
import 'package:trailbuddy/features/trails/gpx.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/fake_rides.dart';
import '../fakes/fake_tiles.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

/// Der Trail von `seedTrail` beginnt bei 48,0° N / 9,0° O und läuft nach
/// Norden; der Standort liegt südlich davon in DERSELBEN z13-Kachel.
final _tile = tileAt(48.0, 9.0, 13);
const _n = 1 << 13;
const _lon = 9.0;
final _bounds = tileBounds(13, _tile.x, _tile.y);
final _fromLat = math.max(_bounds.south + 0.0004, 48.0 - 0.003);

/// Grad → Kachel-Pixel der Kachel [_tile].
(int, int) _px(double lat, double lon) {
  final x = ((lon + 180) / 360 * _n - _tile.x) * kTileExtent;
  final r = lat * math.pi / 180;
  final y = ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * _n - _tile.y) * kTileExtent;
  return (x.round(), y.round());
}

/// Ein Bereich mit der Kachel des Trails (ein Forstweg vom Standort über
/// den Trailkopf hinaus) und ihren acht Nachbarn ohne Wege — der Rahmen
/// mit Rand berührt sie, und `partial` hieße: kein Graph.
Future<MemoryAreaStore> _areaWithTrack() async {
  final store = MemoryAreaStore();
  final tiles = <TileToWrite>[];
  for (var dx = -1; dx <= 1; dx++) {
    for (var dy = -1; dy <= 1; dy++) {
      final own = dx == 0 && dy == 0;
      tiles.add(TileToWrite(
        13,
        _tile.x + dx,
        _tile.y + dy,
        mvtTile(own ? [road([_px(_fromLat - 0.0002, _lon), _px(48.0 + 0.0005, _lon)], 'path', kindDetail: 'track')] : []),
      ));
    }
  }
  final bytes = writePmTiles(
    tiles: tiles,
    tileCompression: Compression.none,
    bounds: const TileBounds(west: 8.9, south: 47.9, east: 9.1, north: 48.1),
  );
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

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late FakeRideStore rides;
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
    trails.seedTrail(anna.id, name: 'Hexentanz', grade: 2);
    rides = FakeRideStore();
  });

  Future<void> start(WidgetTester tester,
      {MemoryAreaStore? areaStore, FakePositionFix? positionFix}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, backend,
        trails: trails,
        areaStore: areaStore,
        rideStore: rides,
        positionFix: positionFix ?? FakePositionFix(fakePosition(_fromLat, _lon)),
        extraOverrides: [gpxShareProvider.overrideWithValue(recorder)]);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    await tester.tap(find.text('Hexentanz'));
    await settle(tester);
  }

  Future<void> tapTrailHead(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('trail-head'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await settle(tester, frames: 30);
  }

  Iterable<dynamic> routeLines(WidgetTester tester) =>
      fakeMapLayers(tester).polylines.where((l) => l.width == 5);

  testWidgets('aus dem Blatt auf die Karte: Weg, Summen, Vorschau, Profil, GPX', (tester) async {
    await start(tester, areaStore: await _areaWithTrack());
    // Im Blatt stehen „Zum Trailkopf" und „Karte" nebeneinander; die
    // Anfahrt ist seit #224 ein Symbol im Kopf, neben dem Namen.
    final head = find.byKey(const ValueKey('trail-head'));
    final navigate = find.byKey(const ValueKey('trail-navigate'));
    final map = find.byKey(const ValueKey('trail-show-on-map'));
    await tester.ensureVisible(map);
    expect(tester.getCenter(head).dy, closeTo(tester.getCenter(map).dy, 1));
    expect(tester.getCenter(navigate).dy,
        closeTo(tester.getCenter(find.byKey(const ValueKey('trail-sheet-title'))).dy, 24));

    await tapTrailHead(tester);
    expect(find.byKey(const ValueKey('trail-head-summary')), findsOneWidget);
    expect(find.textContaining('hm bergauf'), findsOneWidget);
    expect(find.textContaining('Forstweg'), findsOneWidget);
    expect(find.textContaining('Untergrenze'), findsOneWidget, reason: 'der Bereich hat keine Höhen');
    expect(find.textContaining('Wanderweg, Fußweg oder Stufen'), findsNothing);
    expect(find.byKey(const ValueKey('trail-head-notice')), findsNothing);
    // Die Vorschau liegt als Linie der Fassade auf der Karte und beginnt
    // am Standort.
    final lines = routeLines(tester).toList();
    expect(lines, hasLength(1));
    expect(lines.single.dash, isNull, reason: 'Forstweg: durchgezogen');
    final whole = fakeMapLayers(tester).polylines.where((l) => l.width == 2).single;
    expect(whole.points.first.latitude, closeTo(_fromLat, 1e-9));
    expect(whole.points.last.latitude, closeTo(48.0, 1e-9));
    // Eingepasst ÜBER dem Blatt, nicht darunter (Feldbericht 0.73.0).
    expect(fakeMap(tester).lastFitBottomInset, greaterThan(100));

    // Profilwechsel im Blatt rechnet auf dem stehenden Graphen neu. Erst
    // das Blatt hochziehen: Seit „Als Fahrt speichern" (0.72.0) reicht das
    // halbe Blatt nicht mehr, und ein Tipp unter seinem Rand träfe die
    // Sperre dahinter — das Blatt ginge zu.
    final list = find
        .descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable))
        .first;
    await tester.drag(list, const Offset(0, -400));
    await settle(tester, frames: 4);
    final ebike = find.descendant(
        of: find.byKey(const ValueKey('trail-head-profile')), matching: find.text('E-Bike'));
    await tester.ensureVisible(ebike);
    await tester.tap(ebike);
    await settle(tester);
    expect(find.byKey(const ValueKey('trail-head-summary')), findsOneWidget);
    expect(routeLines(tester), hasLength(1));

    await tester.ensureVisible(find.byKey(const ValueKey('trail-head-gpx')));
    await tester.tap(find.byKey(const ValueKey('trail-head-gpx')));
    await settle(tester);
    expect(shared, hasLength(1));
    // Als Fahrt speichern (#158 Schritt 5): eine geplante Fahrt mit dem
    // Weg als Punkten, ohne Höhen.
    await tester.ensureVisible(find.byKey(const ValueKey('trail-head-save')));
    await tester.tap(find.byKey(const ValueKey('trail-head-save')));
    await settle(tester);
    expect(rides.rides, hasLength(1));
    expect(rides.rides.single.planned, isTrue);
    expect(rides.rides.single.name, 'Zum Trailkopf: Hexentanz');
    expect(rides.rides.single.points.first.lat, closeTo(_fromLat, 1e-9));
    expect(rides.rides.single.points.every((p) => p.altM == null), isTrue);
    expect(shared.single.fileName, 'trailbuddy-zum-trailkopf-hexentanz.gpx');
    final track = parseGpx(shared.single.xml).single;
    expect(track.name, 'Zum Trailkopf: Hexentanz');
    expect(track.points.length, greaterThanOrEqualTo(2));
    expect(track.points.first.lat, closeTo(_fromLat, 1e-9));
    expect(track.points.every((p) => p.ele == null), isTrue);

    // Runterziehen schließt NICHT (Feldbericht 0.73.0) — es verkleinert;
    // die Route bleibt auf der Karte.
    final sheetList = find
        .descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable))
        .first;
    for (var i = 0; i < 4; i++) {
      await tester.drag(sheetList, const Offset(0, 1500));
      await settle(tester, frames: 4);
    }
    expect(find.text('Zum Trailkopf'), findsWidgets);
    expect(routeLines(tester), hasLength(1));

    // Blatt zu (X) ⇒ Vorschau weg.
    await tester.tap(find.byKey(const ValueKey('trail-head-close')));
    await settle(tester);
    expect(find.byKey(const ValueKey('trail-head-summary')), findsNothing);
    expect(routeLines(tester), isEmpty);
  });

  testWidgets('ohne gespeicherten Bereich: ein Satz und die Anfahrt, kein GPX', (tester) async {
    await start(tester);
    await tapTrailHead(tester);
    expect(find.textContaining('Kein gespeicherter Bereich'), findsOneWidget);
    expect(find.byKey(const ValueKey('trail-head-navigate')), findsOneWidget);
    expect(find.byKey(const ValueKey('trail-head-gpx')), findsNothing);
    expect(routeLines(tester), isEmpty);
  });

  testWidgets('ohne Standort: ein Satz, gefragt wurde genau einmal', (tester) async {
    final fix = FakePositionFix(null);
    await start(tester, areaStore: await _areaWithTrack(), positionFix: fix);
    await tapTrailHead(tester);
    expect(find.textContaining('Kein Standort'), findsOneWidget);
    expect(fix.calls, 1);
    expect(find.byKey(const ValueKey('trail-head-gpx')), findsNothing);
  });
}
