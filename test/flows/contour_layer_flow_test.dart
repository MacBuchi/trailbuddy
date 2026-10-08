// Die Höhenlinien (#271) durch die echte App: Schalter in „Kartenebenen",
// ab Werk aus — und aus heißt, keine Höhenkachel wird gelesen. An: Linien
// an der Fassade, der Abstand im Untertitel und in der Legende; weit
// draußen und ohne Höhen sagt der Untertitel, warum nichts liegt.
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/offline_areas/area_providers.dart';
import 'package:trailbuddy/features/offline_areas/height_tiles.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_heights.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

/// Zählt, wie oft eine Kachel gelesen wird.
class _CountingSource implements HeightTileSource {
  _CountingSource(this._inner);
  final HeightTileSource _inner;
  int reads = 0;

  @override
  Future<HeightTile?> tile(int x, int y) {
    reads++;
    return _inner.tile(x, y);
  }

  @override
  Future<void> close() async {}
}

void main() {
  late FakeBackend backend;
  late _CountingSource source;

  setUp(() {
    backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'anna').id);
    source = _CountingSource(MemoryHeightSource(slopeHeightTiles()));
  });

  List<Override> areas() => [areaHeightReaderProvider.overrideWith((ref) async => HeightReader([source]))];

  final toggle = find.byKey(const ValueKey('contour-layer-switch'));
  final status = find.byKey(const ValueKey('contour-layer-status'));

  Future<void> start(WidgetTester tester, FakeSettings settings,
      {List<Override> extra = const [], Stream<List<ConnectivityResult>>? connectivity}) async {
    await pumpApp(tester, backend, settings: settings, connectivity: connectivity, extraOverrides: [...areas(), ...extra]);
    await settle(tester, frames: 20);
    // Über den Hang der Test-Kacheln, nah dran.
    fakeMap(tester).move(const LatLng(48.0, 9.0), 14);
    await settle(tester, frames: 20);
  }

  Future<void> openLayers(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Kartenebenen'));
    await settle(tester);
    await tester.ensureVisible(toggle);
    await settle(tester);
  }

  String statusText(WidgetTester tester) => tester.widget<Text>(status).data!;

  testWidgets('ab Werk aus: keine Kachel gelesen, keine Linien', (tester) async {
    await start(tester, FakeSettings());
    expect(fakeMapLayers(tester).contours, isNull);
    expect(source.reads, 0, reason: 'beobachten ist laden — aus heißt: nichts lesen');
    await openLayers(tester);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
  });

  testWidgets('an: Linien auf der Karte, Abstand im Untertitel und in der Legende', (tester) async {
    final settings = FakeSettings(mapLegendOpen: true);
    await start(tester, settings);
    await openLayers(tester);
    await tester.tap(toggle);
    await settle(tester, frames: 20);
    expect(settings.contourLayerEnabled, isTrue, reason: 'gemerkt');
    expect(source.reads, greaterThan(0));
    expect(statusText(tester), 'Alle 10 m, beschriftet alle 100 m');

    await tester.tapAt(const Offset(200, 40));
    await settle(tester);
    final contours = fakeMapLayers(tester).contours;
    expect(contours, isNotNull);
    expect(contours!.lines, isNotEmpty);
    expect(contours.lines.any((l) => l.index), isTrue, reason: 'Hauptlinien alle 100 m');
    final panel = find.byKey(const ValueKey('map-legend-panel'));
    expect(find.descendant(of: panel, matching: find.text('HÖHENLINIEN')), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.text('alle 10 m')), findsOneWidget);

    // Schieben innerhalb derselben Kacheln liest nichts neu.
    final reads = source.reads;
    fakeMap(tester).move(const LatLng(48.0, 9.0005), 14);
    await settle(tester, frames: 20);
    expect(source.reads, reads, reason: 'dasselbe Fenster, dieselben Linien');

    // Aus: Linien weg, Legende ohne Probe.
    await openLayers(tester);
    await tester.tap(toggle);
    await settle(tester, frames: 20);
    await tester.tapAt(const Offset(200, 40));
    await settle(tester);
    expect(fakeMapLayers(tester).contours, isNull);
    expect(find.descendant(of: panel, matching: find.text('HÖHENLINIEN')), findsNothing);
  });

  testWidgets('weit draußen: „Erst näher heranzoomen", ohne eine Kachel zu lesen', (tester) async {
    await start(tester, FakeSettings(contourLayerEnabled: true));
    fakeMap(tester).move(const LatLng(48.0, 9.0), 10);
    await settle(tester, frames: 20);
    source.reads = 0;
    fakeMap(tester).move(const LatLng(48.1, 9.1), 10);
    await settle(tester, frames: 20);
    expect(source.reads, 0, reason: 'die Grenzen kommen vor den Kacheln');
    await openLayers(tester);
    expect(statusText(tester), 'Erst näher heranzoomen');
    expect(fakeMapLayers(tester).contours, isNull);
  });

  testWidgets('keine Höhen hier: der Untertitel sagt es', (tester) async {
    await start(tester, FakeSettings(contourLayerEnabled: true),
        extra: [areaHeightReaderProvider.overrideWith((ref) async => HeightReader(const []))]);
    await openLayers(tester);
    expect(statusText(tester), startsWith('Hier keine Höhen'));
    expect(fakeMapLayers(tester).contours, isNull);
  });
}
