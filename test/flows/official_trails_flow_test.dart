// Offizielle Trails (#13): eigene Ebene, gestrichelt, an ab Werk, eigenes
// Blatt mit Quelle; ohne Netz gilt, was gemerkt ist; aus heißt: keine
// Anfrage.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/features/official/official_trails.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/fake_official_trails.dart';
import '../fakes/fake_settings.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late FakeOfficialTrailsSource source;
  late MemoryOfficialTrailsCache cache;
  late FakeSettings settings;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    trails = FakeTrailRepository(
        myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    // Ein Trail, damit die Karte von selbst in die Region zoomt.
    trails.seedTrail(anna.id, name: 'Roots');
    source = FakeOfficialTrailsSource({
      'index.json': fakeIndex(),
      'testland.geojson': fakeRegion(),
    });
    cache = MemoryOfficialTrailsCache();
    settings = FakeSettings();
  });

  /// Startet die App; ein zweiter Aufruf stellt einen Neustart nach
  /// (neuer ProviderScope, Gerätespeicher und Einstellungen bleiben).
  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, backend,
        trails: trails, settings: settings, official: source, officialCache: cache);
    await settle(tester, frames: 20);
  }

  /// Die Linien der Ebene, wie der Screen sie der Karte gibt.
  List<MapViewPolyline> lines(WidgetTester tester) => [
        for (final l in fakeMapLayers(tester).polylines)
          if (l.hitValue is OfficialTrail) l,
      ];

  testWidgets('ab Werk an: gestrichelt, gesperrter Teil grau, Blatt mit Quelle',
      (tester) async {
    await start(tester);
    expect(source.asked, ['index.json', 'testland.geojson']);
    final l = lines(tester);
    expect(l, hasLength(2), reason: 'ein Trail, Hauptroute und Variante');
    expect(l.every((p) => p.dash != null), isTrue);
    expect(l[0].color, AppColors.mapLines.official);
    expect(l[1].color, isNot(AppColors.mapLines.official), reason: 'gesperrte Variante');
    expect(l[1].width, lessThan(l[0].width));

    await tapMapAt(tester, const LatLng(48.003, 9.003));
    await settle(tester);
    expect(find.text('Flowline'), findsOneWidget);
    expect(find.text('Offizieller Singletrail'), findsOneWidget);
    expect(find.text('1,2 km · ↓ 180 Hm · ↑ 10 Hm'), findsOneWidget);
    expect(find.text('Schwierigkeit laut Quelle: mittelschwierig'), findsOneWidget);
    expect(find.textContaining('Teilweise gesperrt laut Land Testland'), findsOneWidget);
    expect(find.text('Quelle: Land Testland – Singletrails · CC0 1.0 · Stand 19.05.2026'),
        findsOneWidget);
    expect(find.text('Bei der Quelle ansehen'), findsOneWidget);
    // Kein Beitrag, kein Hinweis: Das ist kein Trail des Netzes.
    expect(find.text('Mein Beitrag'), findsNothing);
  });

  testWidgets('ausschalten: Linien weg, gemerkt — und beim Start keine Anfrage',
      (tester) async {
    await start(tester);
    // Seit 0.75.0 (#190) öffnet der Knopf das Blatt direkt.
    await tester.tap(find.byTooltip('Kartenebenen'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('official-trails-switch')));
    await settle(tester);
    expect(settings.officialTrailsEnabled, isFalse);
    await tester.tapAt(const Offset(400, 20));
    await settle(tester, frames: 20);
    expect(lines(tester), isEmpty);

    source.asked.clear();
    await start(tester);
    expect(lines(tester), isEmpty);
    expect(source.asked, isEmpty, reason: 'aus heißt: kein Abruf');
  });

  testWidgets('ohne Netz: der gemerkte Stand, keine Warnung', (tester) async {
    await start(tester);
    expect(cache.files.keys, containsAll(['index.json', 'testland.geojson']));

    source.failWith = Exception('SocketException: Failed host lookup');
    await start(tester);
    expect(lines(tester), hasLength(2));
    expect(find.text('Offizielle Trails gerade nicht erreichbar'), findsNothing);
  });

  testWidgets('ohne Netz und nichts gemerkt: die Karte sagt es', (tester) async {
    source.failWith = Exception('SocketException: Failed host lookup');
    await start(tester);
    expect(lines(tester), isEmpty);
    expect(find.text('Offizielle Trails gerade nicht erreichbar'), findsOneWidget);
  });

  testWidgets('gleicher Stand: Region vom Gerät; neuer Stand: neu geholt',
      (tester) async {
    await start(tester);
    source.asked.clear();
    await start(tester);
    expect(source.asked, ['index.json'], reason: 'Stand unverändert');

    source.files['index.json'] = fakeIndex(updated: '2026-09-15');
    source.files['testland.geojson'] = fakeRegion(name: 'Flowline neu');
    source.asked.clear();
    await start(tester);
    expect(source.asked, ['index.json', 'testland.geojson']);
    await tapMapAt(tester, const LatLng(48.003, 9.003));
    await settle(tester);
    expect(find.text('Flowline neu'), findsOneWidget);
  });

  testWidgets('Trail-Blatt: auch ausgeschildert als …, mit Sperre und Stand der Quelle',
      (tester) async {
    source.files['testland.geojson'] =
        fakeRegion(extra: [fakeOnRoots(updated: '2026-09-28')]);
    await start(tester);
    await openTab(tester, 'Trails');
    await tester.tap(find.text('Roots'));
    await settle(tester);
    // #41: Die Sperre liegt auf dem Trail — grau, mit Quelle und Stand.
    expect(
        find.text('Auch ausgeschildert als „Wurzelpfad" · '
            'gesperrt laut Land Testland, Stand 28.09.2026'),
        findsOneWidget);
    expect(find.byIcon(Icons.block), findsOneWidget);
    // Flowline liegt daneben, nicht darauf.
    expect(find.textContaining('Flowline'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('official-testland:3')));
    await settle(tester);
    expect(find.text('Schwierigkeit laut Quelle: leicht'), findsOneWidget);
    expect(find.text('Gesperrt laut Land Testland, Stand 28.09.2026.'), findsOneWidget);
  });

  testWidgets('Trail-Blatt aus der Liste lädt die Region nach', (tester) async {
    source.files['testland.geojson'] = fakeRegion(extra: [fakeOnRoots(status: 'open')]);
    // Ein zweiter Trail weit im Norden: Die Karte passt beide ein, bleibt
    // unter Zoom 8 und lädt selbst nichts.
    trails.seedTrail(backend.currentUserId!, name: 'Norden', lat: 53.5, lon: 13.0);
    await start(tester);
    expect(lines(tester), isEmpty);
    expect(source.asked, isNot(contains('testland.geojson')));

    await openTab(tester, 'Trails');
    await tester.tap(find.text('Roots'));
    await settle(tester);
    expect(source.asked, contains('testland.geojson'));
    expect(find.text('Auch ausgeschildert als „Wurzelpfad"'), findsOneWidget);
  });

  testWidgets('Ebene aus: kein Satz, keine Anfrage', (tester) async {
    source.files['testland.geojson'] = fakeRegion(extra: [fakeOnRoots()]);
    settings.officialTrailsEnabled = false;
    await start(tester);
    await openTab(tester, 'Trails');
    await tester.tap(find.text('Roots'));
    await settle(tester);
    expect(find.textContaining('ausgeschildert'), findsNothing);
    expect(source.asked, isEmpty);
  });
}
