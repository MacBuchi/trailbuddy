// Die Folgeansicht der Navigation (#232, Konzept-Routing 9) durch die
// echte Oberfläche: aus „Meine Fahrten" auf die Karte, Start-Dialog mit
// Aufzeichnen und Bildschirm, die Karte dreht nach dem Kurs, die Leiste
// zählt herunter, abseits wird gewarnt, „Norden" nordet, am Ziel endet die
// Navigation nach einer Minute — die Aufzeichnung läuft weiter. „Zurück
// zur Route" über einen gespeicherten Bereich (Muster
// `trail_head_flow_test`), ohne Bereich ein Satz; „zuletzt navigiert" in
// „Meine Fahrten" geht weiter. Der Dienst (9.5): Melder am Koordinator
// mit Knopf, „Navigation beenden" aus der Benachrichtigung, Zurückholen
// nach einem Neustart der App. Das Bild-im-Bild (9.6): nur bei laufender
// Navigation erlaubt, klein nur die Zahlen, „Beenden" im Fenster.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/core/picture_in_picture.dart';
import 'package:trailbuddy/core/screen_awake.dart';
import 'package:trailbuddy/features/garmin/garmin_bridge.dart' show WatchOpen, WatchSendResult;
import 'package:trailbuddy/features/garmin/watch_providers.dart' show kWatchAckWait, kWatchNudges, kWatchPositionEvery, kWatchPositionFor, watchBranchesLoaderProvider, watchSyncProvider;
import 'package:trailbuddy/features/garmin/watch_branches.dart' show WatchBranch;
import 'package:trailbuddy/features/garmin/watch_route.dart' show kWatchProtocol, watchUnpack;
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';
import 'package:trailbuddy/features/keep_alive/keep_alive.dart';
import 'package:trailbuddy/features/rides/airtime_live.dart';
import 'package:trailbuddy/features/rides/airtime_message.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/features/rides/sensor_fusion.dart';
import 'package:trailbuddy/features/routing/nav_notice.dart';
import 'package:trailbuddy/features/routing/route_band.dart' show kRouteFollowOpacity;
import 'package:trailbuddy/features/routing/nav_providers.dart' show kNavArrivedLinger, kNavTrailDoneLinger, lastNavProvider, navigationProvider;
import 'package:trailbuddy/features/routing/route_progress.dart' show kNavPipBarShare, kNavPipZoom, pipAheadPx;
import 'package:trailbuddy/features/trails/grade_shield.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_garmin.dart';
import '../fakes/fake_keep_alive.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/route_lines.dart';
import '../fakes/fake_rides.dart';
import '../fakes/fake_tiles.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

class _FakeScreenAwake implements ScreenAwake {
  final calls = <bool>[];

  @override
  bool get supported => true;

  @override
  Future<void> keepOn(bool on) async => calls.add(on);
}

/// Spielt das Fenster: merkt, was erlaubt wird, und meldet wie der Kanal.
class _FakePip implements PictureInPicture {
  final allowed = <bool>[];
  var enters = 0;
  void Function(bool inPip)? _onMode;
  VoidCallback? _onStop;

  /// Das System macht die App klein bzw. wieder groß.
  void shrink() => _onMode!(true);
  void grow() => _onMode!(false);
  void tapStop() => _onStop!();

  @override
  Future<void> allow(bool on) async => allowed.add(on);

  @override
  Future<bool> supported() async => true;

  @override
  Future<void> enter() async => enters++;

  @override
  void listen({required void Function(bool inPip) onMode, required VoidCallback onStop}) {
    _onMode = onMode;
    _onStop = onStop;
  }
}

/// Eine geplante Runde nach Osten: 20 Abschnitte à 0,001° Länge.
const _lat = 47.0;
double _lng(int i) => 11 + i / 1000;

/// Für „Zurück zur Route": ein Forstweg nach Norden in EINER z13-Kachel
/// (wie in `trail_head_flow_test`), die Route liegt auf seinem nördlichen
/// Teil, der Standort 67 m südlich davon auf demselben Weg.
final _tile = tileAt(48.0, 9.0, 13);
const _n = 1 << 13;
const _wayLng = 9.0;
final _bounds = tileBounds(13, _tile.x, _tile.y);
final _southLat = math.max(_bounds.south + 0.0004, 48.0 - 0.003);
final _routeStartLat = _southLat + 0.0006;

(int, int) _px(double lat, double lon) {
  final x = ((lon + 180) / 360 * _n - _tile.x) * kTileExtent;
  final r = lat * math.pi / 180;
  final y = ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * _n - _tile.y) * kTileExtent;
  return (x.round(), y.round());
}

/// [crossing]: dazu ein Querweg nach Osten und Westen bei 48,0° (#449,
/// die Abzweigungen für die Uhr).
Future<MemoryAreaStore> _areaWithTrack({bool crossing = false}) async {
  final store = MemoryAreaStore();
  final tiles = <TileToWrite>[];
  for (var dx = -1; dx <= 1; dx++) {
    for (var dy = -1; dy <= 1; dy++) {
      final own = dx == 0 && dy == 0;
      tiles.add(TileToWrite(
        13,
        _tile.x + dx,
        _tile.y + dy,
        mvtTile(own
            ? [
                road([_px(_southLat - 0.0002, _wayLng), _px(48.0 + 0.0005, _wayLng)], 'path', kindDetail: 'track'),
                if (crossing)
                  road([_px(48.0, _wayLng - 0.002), _px(48.0, _wayLng + 0.002)], 'path', kindDetail: 'track'),
              ]
            : []),
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
  late FakeRideStore store;
  late FakeRideService service;
  late _FakeScreenAwake screen;
  late StreamController<Position?> fixes;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    store = FakeRideStore()..uid = anna.id;
    final t0 = DateTime.utc(2026, 10, 8, 9);
    store.rides.add(Ride(
      id: '20261008T090000Z',
      startedAt: t0,
      endedAt: t0.add(const Duration(hours: 1)),
      points: [for (var i = 0; i <= 20; i++) RidePoint(lat: _lat, lng: _lng(i), at: t0, accuracyM: 0)],
      planned: true,
      name: 'Hausrunde',
    ));
    service = FakeRideService();
    screen = _FakeScreenAwake();
    fixes = StreamController<Position?>.broadcast();
    addTearDown(fixes.close);
  });

  Future<void> fix(WidgetTester tester, double lat, double lng,
      {double heading = 90, double speed = 5, DateTime? at}) async {
    fixes.add(fakePosition(lat, lng, heading: heading, speed: speed, at: at));
    await settle(tester, frames: 2);
  }

  Future<void> startFromRides(WidgetTester tester,
      {bool phone = false,
      MemoryAreaStore? areaStore,
      LatLng start = const LatLng(_lat, 11),
      FakeKeepAlive? keepAlive,
      FakeNavServiceBridge? navBridge,
      FakeTrailRepository? trails,
      FakePositionFix? positionFix,
      FakeGarminBridge? garmin,
      List<Override> overrides = const [],
      _FakePip? pip}) async {
    if (phone) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }
    // Standardgröße wie `ride_flow_test`: In der Testschrift ist die Karte
    // „Fahrt läuft …" auf 360 dp breiter als der Schirm.
    await pumpApp(tester, backend,
        trails: trails,
        rideStore: store,
        rideService: service,
        areaStore: areaStore,
        keepAlive: keepAlive,
        navBridge: navBridge,
        garmin: garmin,
        rideFix: FakeRideFix()
          ..next = RidePoint(lat: start.latitude, lng: start.longitude, at: DateTime.now().toUtc(), accuracyM: 5),
        positionStream: fixes.stream,
        positionFix: positionFix ?? FakePositionFix(fakePosition(start.latitude, start.longitude, heading: 90, speed: 0)),
        extraOverrides: [
          screenAwakeProvider.overrideWithValue(screen),
          if (pip != null) pictureInPictureProvider.overrideWithValue(pip),
          ...overrides,
        ]);
    await openProfilePage(tester, 'rides');
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('ride-menu-20261008T090000Z')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('ride-navigate-20261008T090000Z')));
    await settle(tester);
  }

  String textIn(String key) => [
        for (final t in find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)).evaluate())
          (t.widget as Text).data ?? (t.widget as Text).textSpan?.toPlainText() ?? ''
      ].join(' ');

  /// Die eine Zahl im Fenster (#415): der Schlüssel sitzt am Text selbst.
  String pipNumber() => (find.byKey(const ValueKey('nav-pip-number')).evaluate().single.widget as Text).data!;

  testWidgets('from „Meine Fahrten": turns with the course, counts down, warns off the route, ends at the goal',
      (tester) async {
    await startFromRides(tester);
    // Der Start-Dialog: beide Schalter an (Betreiber, 2026-10-08).
    expect(find.byKey(const ValueKey('nav-go')), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('nav-record'))).value, isTrue);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('nav-screen'))).value, isTrue);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester);

    // Auf der Karte: die Anfahrt-Karte statt Knöpfen, unten das Band, keine
    // Reiterleiste (Vollbild, Design 13); die Aufzeichnung läuft, der
    // Bildschirm bleibt an. Ohne Trail auf der Linie zählt die Karte bis
    // zum Ziel.
    expect(find.byKey(const ValueKey('nav-approach')), findsOneWidget);
    expect(textIn('nav-approach'), contains('BIS ZUM ZIEL'));
    expect(find.byKey(const ValueKey('nav-band')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const ValueKey('layers-button')), findsNothing);
    expect(find.byKey(const ValueKey('feedback-button')), findsNothing);
    expect(service.starts, 1);
    expect(screen.calls, [true]);
    expect(textIn('nav-remaining'), contains('1,5 km'));
    expect(textIn('nav-dist'), contains('1,5'));
    // Im Stand gilt die Richtung der Linie: nach Osten, also Osten oben.
    expect(fakeMap(tester).bearing, closeTo(90, 1));
    expect(fakeMap(tester).zoom, 16);
    // Die Position steht im unteren Drittel: Die Mitte liegt östlich davon.
    expect(fakeMap(tester).center.longitude, greaterThan(_lng(0)));
    // Die Route liegt unter dem Netz in der Farbe des Ergebnisses.
    expect(routeBand(tester), isNotEmpty);
    expect(routeBand(tester).every((l) => l.opacity == kRouteFollowOpacity), isTrue);

    // Fahren: der Rest schrumpft, der gefahrene Teil wird blass.
    await fix(tester, _lat, _lng(10));
    expect(textIn('nav-remaining'), contains('758 m'));
    expect(textIn('nav-dist'), contains('758'));
    expect(fakeMapLayers(tester).polylines.where((l) => l.width == 4), hasLength(1));
    // Der GPS-Kurs gilt in Fahrt.
    await fix(tester, _lat, _lng(11), heading: 80);
    expect(fakeMap(tester).bearing, 80);

    // Abseits: ein Ausreißer zählt nicht, der zweite Fix in Folge schon —
    // dann schlägt die Abseits-Karte alles.
    await fix(tester, _lat + 0.0006, _lng(12));
    expect(find.byKey(const ValueKey('nav-off')), findsNothing);
    expect(find.byKey(const ValueKey('nav-approach')), findsOneWidget);
    await fix(tester, _lat + 0.0006, _lng(12));
    expect(find.byKey(const ValueKey('nav-approach')), findsNothing);
    expect(textIn('nav-off'), contains('NEBEN DER ROUTE'));
    expect(textIn('nav-off'), contains('67 m'));
    expect(find.byKey(const ValueKey('nav-off-arrow')), findsOneWidget);
    // „Zurück zur Route" ohne Bereich: ein Satz unter der Karte, der Knopf
    // bleibt für einen zweiten Versuch.
    expect(find.byKey(const ValueKey('nav-rejoin-note')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('nav-rejoin')));
    await settle(tester);
    expect(textIn('nav-rejoin-note'), contains('Hier kennt die App keine Wege'));
    expect(find.byKey(const ValueKey('nav-rejoin')), findsOneWidget);

    // „Norden": genordet, sofort.
    await tester.tap(find.byKey(const ValueKey('nav-north')));
    await settle(tester, frames: 2);
    expect(fakeMap(tester).bearing, 0);

    // Der Bildschirm-Schalter in der Ansicht merkt sich, was er tut.
    await tester.tap(find.byKey(const ValueKey('nav-screen-toggle')));
    await settle(tester, frames: 2);
    expect(screen.calls.last, isFalse);

    // Am Ziel: „Angekommen", nach einer Minute ist die Ansicht weg.
    await fix(tester, _lat, _lng(20));
    expect(find.byKey(const ValueKey('nav-arrived')), findsOneWidget);
    await tester.pump(kNavArrivedLinger);
    await settle(tester);
    expect(find.byKey(const ValueKey('nav-arrived')), findsNothing);
    expect(find.byKey(const ValueKey('layers-button')), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(fakeMap(tester).bearing, 0);
    // Die Aufzeichnung endet nicht mit der Navigation (9.4).
    expect(service.running, isTrue);

    // „Zuletzt navigiert": nach der Ankunft wieder ab Start.
    // „Meine Fahrten" liegt noch offen im Reiter „Profil".
    await openTab(tester, 'Profil');
    await settle(tester);
    expect(find.byKey(const ValueKey('nav-last')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-last-resume')));
    await settle(tester);
    expect(find.byKey(const ValueKey('nav-go')), findsOneWidget);
  });

  testWidgets('by section (#312): a ride over a trail of the network — approach, head with the buddy note, trail, goal',
      (tester) async {
    // Der Trail des Netzes liegt auf 9° Ost von 48,000 bis 48,009; die
    // Fahrt fährt von 47,997 nach 48,012 darüber hinweg. Jan hat einen
    // Hinweis geschrieben.
    final trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    final anna = backend.currentUserId!;
    final jan = backend.addUser(username: 'jan');
    backend.addFriendship(anna, jan.id);
    final id = trails.seedTrail(anna, name: 'Rosskopf Süd', grade: 2, lat: 48.0, lon: 9.0);
    trails.usernames[jan.id] = 'jan';
    trails.notes.add(TrailNote(
        id: 'n1', trailId: id, userId: jan.id, body: 'Nach der 2. Kehre liegt ein Baum quer.', createdAt: DateTime.now()));
    final t0 = DateTime.utc(2026, 10, 8, 9);
    store.rides
      ..clear()
      ..add(Ride(
        id: '20261008T090000Z',
        startedAt: t0,
        endedAt: t0.add(const Duration(hours: 1)),
        points: [
          for (var lat = 47.997; lat <= 48.0121; lat += 0.0002) RidePoint(lat: lat, lng: 9.0, at: t0, accuracyM: 0),
        ],
        planned: true,
        name: 'Hausrunde',
      ));
    await startFromRides(tester, trails: trails, start: const LatLng(47.997, 9.0));
    // Das Start-Blatt nennt die Trails auf der Linie.
    expect(textIn('nav-summary'), contains('1 Trail'));
    await tester.tap(find.byKey(const ValueKey('nav-record')));
    await settle(tester, frames: 2);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester);

    // Anfahrt: bis zum Trailkopf, mit Namen; das Band trägt den Trail.
    expect(textIn('nav-approach'), contains('BIS ZUM TRAILKOPF'));
    expect(textIn('nav-approach'), contains('ROSSKOPF SÜD'));
    expect(textIn('nav-dist'), contains('3'));
    expect(textIn('nav-band'), contains('Rosskopf Süd'));
    expect(textIn('nav-band'), contains('ROUTE · 1 TRAIL'));

    // Am Trailkopf, stehend: Stufe, Hinweis von Jan.
    await fix(tester, 47.9995, 9.0, heading: 0, speed: 0);
    expect(find.byKey(const ValueKey('nav-head')), findsOneWidget);
    expect(textIn('nav-head'), contains('AM TRAILKOPF'));
    expect(textIn('nav-head'), contains('ROSSKOPF SÜD'));
    expect(textIn('nav-head-note'), contains('MELDUNG · JAN'));
    expect(textIn('nav-head-note'), contains('Baum quer'));

    // Auf dem Trail, rollend: die schmale Leiste mit dem Rest und dem Hinweis.
    final t = DateTime.utc(2026, 10, 13, 10);
    await fix(tester, 48.003, 9.0, heading: 0, speed: 5, at: t);
    expect(find.byKey(const ValueKey('nav-trail')), findsOneWidget);
    expect(textIn('nav-trail'), contains('ROSSKOPF SÜD'));
    expect(textIn('nav-trail-rest'), contains('m'));
    expect(textIn('nav-trail-note'), contains('jan: Nach der 2. Kehre'));
    expect(find.byKey(const ValueKey('nav-done')), findsNothing);
    await fix(tester, 48.006, 9.0, heading: 0, speed: 11.4, at: t.add(const Duration(seconds: 50)));

    // Dahinter: kein Trail mehr, bis zum Ziel — und die Bilanz (#312 N2):
    // Zeit ab der Einfahrt, Top-Speed aus dem GPS, Länge.
    await fix(tester, 48.011, 9.0, heading: 0, speed: 5, at: t.add(const Duration(seconds: 102)));
    expect(textIn('nav-approach'), contains('BIS ZUM ZIEL'));
    expect(find.byKey(const ValueKey('nav-trail')), findsNothing);
    expect(textIn('nav-done'), contains('TRAIL GESCHAFFT'));
    expect(textIn('nav-done'), contains('ROSSKOPF SÜD'));
    expect(tester.widget<Text>(find.byKey(const ValueKey('nav-done-time'))).data, '1:42 min');
    expect(textIn('nav-done-speed'), contains('41'));
    expect(textIn('nav-done-length'), contains('km'));
    expect(textIn('nav-done-next'), startsWith('WEITER · '));
    // Der Tipp meldet den Zustand vor Ort, zur Zeit des Trail-Endes.
    await tester.tap(find.byKey(const ValueKey('nav-done-condition-4')));
    await settle(tester, frames: 2);
    final report = trails.reports.single;
    expect(report.trailId, id);
    expect(report.condition, 4);
    expect(report.confirmed, isTrue);
    expect(tester.widget<Text>(find.byKey(const ValueKey('nav-done-sent'))).data, 'Gemeldet — danke.');
    // „Weiter" schließt; Band und Knöpfe sind wieder da.
    await tester.tap(find.byKey(const ValueKey('nav-done-next')));
    await settle(tester, frames: 2);
    expect(find.byKey(const ValueKey('nav-done')), findsNothing);
    expect(find.byKey(const ValueKey('nav-band')), findsOneWidget);
  });

  testWidgets('#36 Schritt 5: Trail-Werte auf dem Trail, AIR-Toast und in „Trail geschafft" — nur mit Erkennung',
      (tester) async {
    final trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    trails.seedTrail(backend.currentUserId!, name: 'Rosskopf Süd', grade: 2, lat: 48.0, lon: 9.0);
    final t0 = DateTime.utc(2026, 10, 8, 9);
    store.rides
      ..clear()
      ..add(Ride(
        id: '20261008T090000Z',
        startedAt: t0,
        endedAt: t0.add(const Duration(hours: 1)),
        points: [
          for (var lat = 47.997; lat <= 48.0121; lat += 0.0002) RidePoint(lat: lat, lng: 9.0, at: t0, accuracyM: 0),
        ],
        planned: true,
        name: 'Hausrunde',
      ));
    await startFromRides(tester, phone: true, trails: trails, start: const LatLng(47.997, 9.0));
    await tester.tap(find.byKey(const ValueKey('nav-record')));
    await settle(tester, frames: 2);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester);
    final container = ProviderScope.containerOf(tester.element(find.byKey(const ValueKey('nav-stop'))));
    int us(DateTime at) => at.microsecondsSinceEpoch;
    const file = '/rides/sensors/20261013T095000Z.csv';
    Future<void> send(FusionEvent e) async {
      container.read(airtimeLiveProvider.notifier).accept(encodeAirtimeEvent(file, e));
      await settle(tester, frames: 2);
    }

    // Ohne Erkennung (Schalter aus): keine Kacheln, auch keine Nullen.
    final t = DateTime.utc(2026, 10, 13, 10);
    await fix(tester, 48.003, 9.0, heading: 0, speed: 5, at: t);
    expect(find.byKey(const ValueKey('nav-trail')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-air-time')), findsNothing);

    // Ein Sprung VOR der Einfahrt zählt nicht; einer auf dem Trail schon,
    // ein unplausibler nie.
    await send(JumpEvent(
        startUs: us(t) - 5000000, duration: const Duration(milliseconds: 900), landingG: 2, upright: true, plausible: true));
    expect(textIn('nav-air-time'), contains('0,0'));
    expect(find.byKey(const ValueKey('nav-air-toast')), findsOneWidget, reason: 'der Toast sagt jeden Sprung an');
    await tester.pump(const Duration(seconds: 2));
    await settle(tester, frames: 2);
    expect(find.byKey(const ValueKey('nav-air-toast')), findsNothing, reason: 'nach 2 s weg');
    await send(JumpEvent(
        startUs: us(t) + 10000000, duration: const Duration(milliseconds: 600), landingG: 2.9, upright: true, plausible: true));
    expect(textIn('nav-air-toast'), 'AIR 0,6 s · 2,9 G');
    await send(JumpEvent(
        startUs: us(t) + 20000000, duration: const Duration(milliseconds: 800), landingG: 9, upright: false, plausible: false));
    await send(StoppieEvent(
        startUs: us(t) + 30000000, duration: const Duration(milliseconds: 700), maxTiltDeg: 17, decel: 2, landingG: 1.6));
    await send(WheelieEvent(startUs: us(t) + 40000000, duration: const Duration(seconds: 2), lengthM: 7.6, maxTiltDeg: 25));
    expect(textIn('nav-air-time'), contains('0,6'));
    expect(textIn('nav-air-time'), contains('1×'));
    expect(textIn('nav-air-g'), contains('2,9'));
    expect(textIn('nav-air-wheelie'), contains('bis 8 m'));
    expect(textIn('nav-air-stoppie'), contains('bis 17°'));
    await tester.pump(const Duration(seconds: 2));

    // Am Ende: dieselben Werte in der Bilanz.
    await fix(tester, 48.011, 9.0, heading: 0, speed: 5, at: t.add(const Duration(seconds: 102)));
    expect(find.byKey(const ValueKey('nav-done')), findsOneWidget);
    expect(textIn('nav-done-air-time'), contains('0,6'));
    expect(textIn('nav-done-air-g'), contains('2,9'));
    expect(textIn('nav-done-air-stoppie'), contains('1'));
    expect(find.byKey(const ValueKey('nav-air-time')), findsNothing, reason: 'abseits keine Kacheln');
    await tester.pump(kNavTrailDoneLinger);
    await settle(tester, frames: 2);
  });

  testWidgets('Trail geschafft closes by itself after 20 s; half a trail gets none (#312 N2)', (tester) async {
    final trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    trails.seedTrail(backend.currentUserId!, name: 'Rosskopf Süd', grade: 2, lat: 48.0, lon: 9.0);
    final t0 = DateTime.utc(2026, 10, 8, 9);
    store.rides
      ..clear()
      ..add(Ride(
        id: '20261008T090000Z',
        startedAt: t0,
        endedAt: t0.add(const Duration(hours: 1)),
        points: [
          for (var lat = 47.997; lat <= 48.0121; lat += 0.0002) RidePoint(lat: lat, lng: 9.0, at: t0, accuracyM: 0),
        ],
        planned: true,
        name: 'Hausrunde',
      ));
    // Auf dem Telefon (360 dp): Das Blatt passt mit allen Knöpfen.
    final pip = _FakePip();
    await startFromRides(tester, phone: true, trails: trails, start: const LatLng(47.997, 9.0), pip: pip);
    await tester.tap(find.byKey(const ValueKey('nav-record')));
    await settle(tester, frames: 2);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester);

    // Erst nach zwei Dritteln eingestiegen: keine Bilanz.
    await fix(tester, 48.007, 9.0, heading: 0, speed: 5);
    expect(find.byKey(const ValueKey('nav-trail')), findsOneWidget);
    // Im kleinen Fenster (#312 N3): der Trail mit Rest, ohne Überlauf.
    tester.view.physicalSize = const Size(450, 600);
    pip.shrink();
    await settle(tester);
    // Nur Schild und Rest (#415): Der Name steht in der Benachrichtigung.
    expect(find.descendant(of: find.byKey(const ValueKey('nav-pip')), matching: find.byType(GradeShield)), findsOneWidget);
    expect(textIn('nav-pip'), isNot(contains('ROSSKOPF')));
    expect(pipNumber(), endsWith('m'));
    tester.view.physicalSize = const Size(1080, 2400);
    pip.grow();
    await settle(tester);
    await fix(tester, 48.011, 9.0, heading: 0, speed: 5);
    expect(find.byKey(const ValueKey('nav-done')), findsNothing);

    // Zurück an den Anfang und ganz gefahren: die Bilanz, die von selbst geht.
    await fix(tester, 48.0005, 9.0, heading: 0, speed: 5);
    await fix(tester, 48.011, 9.0, heading: 0, speed: 5);
    expect(find.byKey(const ValueKey('nav-done')), findsOneWidget);
    expect(tester.getBottomRight(find.byKey(const ValueKey('nav-done-condition-2'))).dx, lessThanOrEqualTo(360));
    expect(tester.getSize(find.byKey(const ValueKey('nav-done-condition-2'))).height, greaterThanOrEqualTo(44));
    await tester.pump(kNavTrailDoneLinger - const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('nav-done')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await settle(tester, frames: 2);
    expect(find.byKey(const ValueKey('nav-done')), findsNothing);
  });

  testWidgets('#449 G2: ohne Uhr kein Schalter „Auf der Uhr zeigen", nichts gesendet',
      (tester) async {
    // Ohne Uhr (ab Werk im Harness) kein Schalter, nichts gesendet.
    final none = FakeGarminBridge();
    await startFromRides(tester, garmin: none);
    expect(find.byKey(const ValueKey('nav-go')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-watch')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester);
    expect(none.sent, isEmpty);
  });

  testWidgets('#449: die Route an die Uhr trägt die Abzweigungen aus dem Bereich unter der Linie', (tester) async {
    store.rides
      ..clear()
      ..add(Ride(
        id: '20261008T090000Z',
        startedAt: DateTime.utc(2026, 10, 8, 9),
        endedAt: DateTime.utc(2026, 10, 8, 10),
        points: [
          for (var lat = _routeStartLat; lat <= 48.0004; lat += 0.0002)
            RidePoint(lat: lat, lng: _wayLng, at: DateTime.utc(2026, 10, 8, 9), accuracyM: 0),
        ],
        planned: true,
        name: 'Hausrunde',
      ));
    final watch = FakeGarminBridge.connected();
    await startFromRides(tester,
        garmin: watch, areaStore: await _areaWithTrack(crossing: true), start: LatLng(_routeStartLat, _wayLng));
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester, frames: 20);
    final parts = watch.routeParts;
    expect(parts, isNotEmpty);
    // Auf dem Draht gepackt (Protokoll 2): [Punkt, (dLat << 16) | dLon].
    final packed = [for (final p in parts) ...?(p['br'] as List?)].cast<int>();
    expect(packed, hasLength(4), reason: 'zwei Stummel an der einen Kreuzung, Osten und Westen');
    final br = <int>[];
    for (var k = 0; k < packed.length; k += 2) {
      final (a, b) = watchUnpack(packed[k + 1]);
      br.addAll([packed[k], a, b]);
    }
    // 40 m nach Osten und Westen, quer zur Route nach Norden.
    final dLon = (40 / (111194.93 * math.cos(48.0 * math.pi / 180)) * 1e5);
    expect([br[2], br[5]].map((v) => v.abs()).toSet().single, closeTo(dLon, 2));
    expect(br[1].abs() + br[4].abs(), lessThanOrEqualTo(2));
    // Der Punkt der Kreuzung ist ein Punkt der Linie an 48,0°.
    final pts = [for (final p in parts) ...(p['pts'] as List).cast<int>()];
    var lat = (parts.first['o'] as List<int>)[0];
    for (var i = 0; i <= br[0]; i++) {
      lat += watchUnpack(pts[i]).$1;
    }
    expect(lat / 1e5, closeTo(48.0, 0.0002));
  });

  testWidgets('#449: kann die Uhr die Route nicht nehmen, geht sie einmal kleiner — dann sagt die Leiste es', (tester) async {
    // Zickzack mit 33 m Ausschlag: Bei 5 m bleibt jeder Punkt, halb so
    // viele gibt es erst stärker vereinfacht — eine andere Route.
    final t0 = DateTime.utc(2026, 10, 8, 9);
    store.rides[0] = Ride(
      id: '20261008T090000Z',
      startedAt: t0,
      endedAt: t0.add(const Duration(hours: 1)),
      points: [
        for (var i = 0; i <= 20; i++) RidePoint(lat: _lat + (i.isEven ? 0 : 0.0003), lng: _lng(i), at: t0, accuracyM: 0)
      ],
      planned: true,
      name: 'Hausrunde',
    );
    final watch = FakeGarminBridge.connected();
    await startFromRides(tester, garmin: watch);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester, frames: 10);
    final first = watch.routeParts;
    final firstPoints = first.first['np'] as int;
    watch.answer({'t': 'x', 'id': first.first['id'], 'c': 'mem'});
    await settle(tester, frames: 10);
    final second = [...watch.sent.last.where((m) => m['t'] == 'r')];
    expect(second, isNotEmpty);
    expect(second.first['id'], isNot(first.first['id']), reason: 'eine neue, kleinere Route');
    expect(second.first['np'] as int, lessThanOrEqualTo((firstPoints / 2).ceil()));
    expect(find.byKey(const ValueKey('map-watch-too-big')), findsNothing);
    // Auch die kleinere geht nicht: kein drittes Mal, die Leiste sagt es.
    final sends = watch.sent.length;
    watch.answer({'t': 'x', 'id': second.first['id'], 'c': 'crash'});
    await settle(tester, frames: 10);
    expect(watch.sent.length, sends);
    expect(find.byKey(const ValueKey('map-watch-too-big')), findsOneWidget);
    // Eine Meldung zu einer fremden Route ändert nichts.
    watch.answer({'t': 'x', 'id': 'fremd', 'c': 'mem'});
    await settle(tester, frames: 4);
    expect(watch.sent.length, sends);
  });

  testWidgets('#449 G2: mit verbundener Uhr geht die Route hin, die Antwort der Uhr sagt die Leiste', (tester) async {
    final watch = FakeGarminBridge.connected();
    await startFromRides(tester, garmin: watch);
    expect(find.byKey(const ValueKey('nav-watch')), findsOneWidget);
    expect(find.textContaining('fēnix 5'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester, frames: 10);
    final parts = watch.routeParts;
    expect(parts, isNotEmpty);
    expect(parts.first['v'], kWatchProtocol);
    expect(parts.first['o'], [(_lat * 1e5).round(), (_lng(0) * 1e5).round()]);
    expect(find.byKey(const ValueKey('map-watch-stored')), findsNothing, reason: 'die Uhr hat noch nicht geantwortet');
    expect(find.byKey(const ValueKey('nav-watch-status-sent')), findsOneWidget, reason: 'das Symbol steht schon, grau');
    watch.answer({'t': 'ok', 'id': parts.first['id']});
    await settle(tester, frames: 4);
    expect(find.byKey(const ValueKey('map-watch-stored')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-approach')), findsOneWidget, reason: 'die Navigation hier läuft');
    // Die Leiste geht, das Symbol bleibt (#449, 2026-11-05) und sagt auf
    // Tipp den Stand.
    ScaffoldMessenger.of(tester.element(find.byKey(const ValueKey('nav-approach')))).hideCurrentSnackBar();
    await settle(tester, frames: 4);
    expect(find.byKey(const ValueKey('map-watch-stored')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('nav-watch-status-stored')));
    await settle(tester, frames: 4);
    expect(find.descendant(of: find.byKey(const ValueKey('nav-watch-status-note')), matching: find.text('Route auf der Uhr')),
        findsOneWidget);
  });

  testWidgets('#449 G2: Schalter aus heißt nichts an die Uhr', (tester) async {
    final watch = FakeGarminBridge.connected();
    await startFromRides(tester, garmin: watch);
    await tester.tap(find.byKey(const ValueKey('nav-watch')));
    await settle(tester, frames: 2);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester, frames: 10);
    expect(watch.sent, isEmpty);
    expect(find.byKey(const ValueKey('nav-watch-status-idle')), findsNothing, reason: 'ohne Uhr kein Uhr-Symbol');
    expect(find.byKey(const ValueKey('nav-stop')), findsOneWidget);
  });

  testWidgets('#449 G2: kommt die Route nicht an, sagt es die Leiste', (tester) async {
    final watch = FakeGarminBridge.connected(result: const WatchSendResult('FAILURE_DEVICE_NOT_CONNECTED', 0));
    await startFromRides(tester, garmin: watch);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester, frames: 10);
    expect(watch.routeParts, isNotEmpty);
    expect(find.byKey(const ValueKey('map-watch-failed')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-approach')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-watch-status-failed')), findsOneWidget);
  });

  testWidgets('#449: läuft die Uhr-App nicht, fragt die Uhr — die Route geht erst mit ihrem „hi"', (tester) async {
    final watch = FakeGarminBridge.connected()..openResult = WatchOpen.prompted;
    await startFromRides(tester, garmin: watch);
    // Kein Anstoßen beim Öffnen der App oder des Blatts (Entscheidung 2).
    expect(watch.opens, 0);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester, frames: 10);
    expect(watch.opens, 1);
    expect(watch.sent, isEmpty, reason: 'die Uhr-App ist noch zu — Garmin Connect verwürfe es still');
    expect(find.byKey(const ValueKey('map-watch-prompted')), findsOneWidget);
    // Bestätigt auf der Uhr: Die App meldet sich ohne Route vom Handy.
    watch.hello(null);
    await settle(tester, frames: 4);
    final parts = watch.routeParts;
    expect(parts, isNotEmpty);
    expect(find.byKey(const ValueKey('map-watch-stored')), findsNothing);
    watch.answer({'t': 'ok', 'id': parts.first['id']});
    await settle(tester, frames: 4);
    expect(find.byKey(const ValueKey('map-watch-stored')), findsOneWidget);
  });

  testWidgets('#449: hat die Uhr die Route schon, geht nichts noch einmal', (tester) async {
    final watch = FakeGarminBridge.connected()..autoStore = true;
    await startFromRides(tester, garmin: watch);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester, frames: 10);
    final id = watch.routeParts.first['id'] as String;
    final batches = watch.sent.length;
    // Die Uhr-App startet neu (oder die Uhr verbindet wieder) und hat sie.
    watch.reconnect();
    await settle(tester, frames: 2);
    expect(watch.queries, 1, reason: 'nach dem Wiederverbinden fragt das Handy, statt blind zu senden');
    watch.hello(id);
    await settle(tester, frames: 4);
    expect(watch.routeParts.where((m) => m['p'] == 0), hasLength(1));
    expect(watch.sent.length, batches + 2, reason: 'nur die Frage und „deine ist aktuell"');
    // Die startende Uhr wartet auf eine Antwort (Betreiber 2026-11-06): Sie
    // zeigt dann gleich ihre gespeicherte.
    expect(watch.sent.last, [
      {'t': 'k', 'id': id}
    ]);
    // Eine andere Kennung: Die aktuelle geht, angekündigt vor den Stücken.
    watch.hello('00000000');
    await settle(tester, frames: 4);
    expect(watch.routeParts.where((m) => m['p'] == 0), hasLength(2));
    final announce = watch.sent.indexWhere((b) => b.length == 1 && b.single['t'] == 'n', batches + 2);
    final parts = watch.sent.indexWhere((b) => b.isNotEmpty && b.first['t'] == 'r', batches + 2);
    expect(announce, greaterThanOrEqualTo(0), reason: 'die Uhr zeigt den Lader statt der alten Route');
    expect(announce, lessThan(parts));
    expect(watch.sent[announce].single, {'t': 'n', 'np': watch.sent[parts].length, 'id': id});
  });

  testWidgets('#449: meldet sich die Uhr, während die Route noch rechnet, hört sie gleich „es kommt eine"',
      (tester) async {
    final watch = FakeGarminBridge.connected();
    final branches = Completer<List<WatchBranch>>();
    await startFromRides(tester, garmin: watch, overrides: [
      watchBranchesLoaderProvider.overrideWithValue((_) => branches.future),
    ]);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester, frames: 4);
    expect(watch.routeParts, isEmpty, reason: 'die Abzweigungen rechnen noch');
    watch.hello(null);
    await settle(tester, frames: 2);
    expect(watch.sent.last, [
      {'t': 'n', 'np': 0}
    ]);
    branches.complete(const []);
    await settle(tester, frames: 10);
    expect(watch.routeParts, isNotEmpty, reason: 'danach gehen die Stücke wie gewohnt');
  });

  testWidgets('#449: spricht die Uhr-App eine andere Fassung, geht nichts hin — die Leiste nennt die veraltete Seite',
      (tester) async {
    final watch = FakeGarminBridge.connected()..openResult = WatchOpen.prompted;
    await startFromRides(tester, garmin: watch);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester, frames: 10);
    watch.hello(null, v: kWatchProtocol - 1);
    await settle(tester, frames: 4);
    expect(watch.routeParts, isEmpty, reason: 'eine alte Uhr-App verwürfe sie');
    expect(find.byKey(const ValueKey('map-watch-outdated-watch')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-watch-status-failed')), findsOneWidget);
    watch.hello(null, v: null); // ganz alte Uhr-App ohne Fassung
    await settle(tester, frames: 4);
    expect(watch.routeParts, isEmpty);
    // Die Uhr-App ist neuer als die App auf dem Handy.
    watch.hello(null, v: kWatchProtocol + 1);
    await settle(tester, frames: 4);
    expect(watch.routeParts, isEmpty);
    expect(find.byKey(const ValueKey('map-watch-outdated-phone')), findsOneWidget);
    // Neu aufgespielt: Die Route geht.
    watch.hello(null);
    await settle(tester, frames: 4);
    expect(watch.routeParts, isNotEmpty);
    // Kommt die andere Fassung erst als Antwort auf ein Stück, ebenso.
    watch.answer({'t': 'x', 'id': watch.routeParts.first['id'], 'c': 'ver', 'v': kWatchProtocol - 1});
    await settle(tester, frames: 4);
    expect(find.byKey(const ValueKey('map-watch-outdated-watch')), findsOneWidget);
    final sends = watch.sent.length;
    watch.reconnect();
    await settle(tester, frames: 4);
    expect(watch.routeParts.where((m) => m['p'] == 0), hasLength(1), reason: 'nichts geht noch einmal hin');
    expect(watch.sent.length, lessThanOrEqualTo(sends + 1));
  });

  testWidgets('#449: nach dem „gespeichert" geht die Position des Handys, bis die Uhr eigenes GPS meldet',
      (tester) async {
    final watch = FakeGarminBridge.connected()..autoStore = true;
    await startFromRides(tester, garmin: watch);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester, frames: 10);
    expect(watch.positions, hasLength(1), reason: 'gleich mit dem „gespeichert"');
    final p = watch.positions.first;
    expect((p['la']! as int) / 1e5, closeTo(_lat, 0.01));
    await tester.pump(kWatchPositionEvery);
    expect(watch.positions, hasLength(2));
    // Die Uhr hat eigenes GPS: keine weitere.
    watch.answer({'t': 'g'});
    await settle(tester, frames: 2);
    await tester.pump(kWatchPositionEvery * 3);
    expect(watch.positions, hasLength(2));
    // Die Uhr-App startet neu: Sie hat ihr GPS noch nicht, der Takt beginnt
    // wieder — und endet nach [kWatchPositionFor].
    watch.hello(watch.routeParts.first['id'] as String);
    await settle(tester, frames: 4);
    expect(watch.positions, hasLength(3));
    for (var t = Duration.zero; t < kWatchPositionFor * 2; t += kWatchPositionEvery) {
      await tester.pump(kWatchPositionEvery);
    }
    final most = kWatchPositionFor.inSeconds ~/ kWatchPositionEvery.inSeconds;
    expect(watch.positions.length - 3, lessThanOrEqualTo(most));
    expect(watch.positions.length - 3, greaterThanOrEqualTo(most - 1));
  });

  testWidgets('#449: mit dem Ende der Navigation geht keine Position mehr an die Uhr', (tester) async {
    final watch = FakeGarminBridge.connected()..autoStore = true;
    await startFromRides(tester, garmin: watch);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester, frames: 10);
    final container = ProviderScope.containerOf(tester.element(find.byKey(const ValueKey('nav-stop'))));
    container.read(navigationProvider.notifier).stop();
    await settle(tester);
    final n = watch.positions.length;
    await tester.pump(kWatchPositionEvery * 3);
    expect(watch.positions, hasLength(n));
  });

  testWidgets('#449: eine neue Route der Navigation geht von selbst an die Uhr; nach dem Ende nichts mehr',
      (tester) async {
    final watch = FakeGarminBridge.connected()..autoStore = true;
    await startFromRides(tester, garmin: watch);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester, frames: 10);
    final first = watch.routeParts.first['id'];
    final container = ProviderScope.containerOf(tester.element(find.byKey(const ValueKey('nav-stop'))));
    expect(container.read(navigationProvider.notifier)
        .start([for (var i = 0; i <= 10; i++) LatLng(_lat + 0.001 * i, 11)], 'Neu geplant'), isTrue);
    await settle(tester, frames: 10);
    final starts = watch.routeParts.where((m) => m['p'] == 0).toList();
    expect(starts, hasLength(2));
    expect(starts.last['id'], isNot(first));
    expect(watch.opens, 2, reason: 'die Uhr-App könnte inzwischen zu sein');
    expect(find.byKey(const ValueKey('nav-go')), findsNothing, reason: 'kein neues Startblatt');

    container.read(navigationProvider.notifier).stop(); // der Knopf liegt unter der Leiste
    await settle(tester);
    final batches = watch.sent.length;
    watch.hello(null);
    watch.reconnect();
    await settle(tester, frames: 4);
    expect(watch.sent.length, batches, reason: 'ohne Navigation folgt die Uhr nichts mehr');
  });

  testWidgets('#449: endet die Navigation auf dem Handy, hört es die Uhr — und beendet man auf der Uhr, endet sie hier',
      (tester) async {
    final watch = FakeGarminBridge.connected()..autoStore = true;
    await startFromRides(tester, garmin: watch);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester, frames: 10);
    final id = watch.routeParts.first['id'] as String;
    // Eine fremde Kennung (eine alte Route auf der Uhr) beendet nichts.
    watch.answer({'t': 'e', 'id': '00000000'});
    await settle(tester, frames: 4);
    expect(find.byKey(const ValueKey('nav-stop')), findsOneWidget);
    // Auf der Uhr beendet: Die Navigation des Handys endet auch, und es
    // geht kein „beendet" zurück.
    final batches = watch.sent.length;
    watch.answer({'t': 'e', 'id': id});
    await settle(tester, frames: 4);
    expect(find.byKey(const ValueKey('nav-stop')), findsNothing);
    expect(watch.sent.skip(batches).expand((b) => b).where((m) => m['t'] == 'e'), isEmpty);

    // Noch einmal, diesmal endet sie auf dem Handy: Die Uhr hört es.
    await startFromRides(tester, garmin: watch);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester, frames: 10);
    final second = watch.routeParts.last['id'] as String;
    final container = ProviderScope.containerOf(tester.element(find.byKey(const ValueKey('nav-stop'))));
    container.read(navigationProvider.notifier).stop();
    await settle(tester);
    expect(watch.sent.last, [
      {'t': 'e', 'id': second}
    ]);
  });

  testWidgets('#449: ein „hallo", während die Route hinübergeht, schickt sie nicht noch einmal', (tester) async {
    final gate = Completer<void>();
    final watch = FakeGarminBridge.connected()
      ..autoStore = true
      ..sendGate = gate;
    await startFromRides(tester, garmin: watch);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester, frames: 10);
    expect(watch.routeParts.where((m) => m['p'] == 0), hasLength(1));
    // Die Uhr-App antwortet auf das Nachfassen, die Route ist noch unterwegs.
    watch.hello(null);
    await settle(tester, frames: 4);
    gate.complete();
    await settle(tester, frames: 10);
    expect(watch.routeParts.where((m) => m['p'] == 0), hasLength(1), reason: 'gemessen: 13 s umsonst');
    expect(find.byKey(const ValueKey('map-watch-stored')), findsOneWidget);
  });

  testWidgets('#449: eine neue Route während einer laufenden Übertragung geht danach, nie zwei zugleich',
      (tester) async {
    final gate = Completer<void>();
    final watch = FakeGarminBridge.connected()
      ..autoStore = true
      ..sendGate = gate;
    await startFromRides(tester, garmin: watch);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester, frames: 10);
    expect(watch.routeParts.where((m) => m['p'] == 0), hasLength(1), reason: 'die erste läuft noch');
    final container = ProviderScope.containerOf(tester.element(find.byKey(const ValueKey('nav-stop'))));
    container
        .read(navigationProvider.notifier)
        .start([for (var i = 0; i <= 10; i++) LatLng(_lat + 0.001 * i, 11)], 'Neu geplant');
    await settle(tester, frames: 10);
    expect(watch.routeParts.where((m) => m['p'] == 0), hasLength(1), reason: 'wartet auf die erste');
    gate.complete();
    await settle(tester, frames: 10);
    final starts = watch.routeParts.where((m) => m['p'] == 0).toList();
    expect(starts, hasLength(2), reason: 'die neue ging hinterher, statt verschluckt zu werden');
    expect(starts.first['id'], isNot(starts.last['id']));
    expect(watch.maxRouteSends, 1);
    expect(find.byKey(const ValueKey('map-watch-stored')), findsOneWidget);
  });

  testWidgets('#449: wartet das Handy auf die Uhr, fragt es drei Mal nach — nicht öfter', (tester) async {
    final watch = FakeGarminBridge.connected()..openResult = WatchOpen.prompted;
    await startFromRides(tester, garmin: watch);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester, frames: 10);
    expect(watch.queries, 0);
    for (final (i, wait) in kWatchNudges.indexed) {
      await tester.pump(wait);
      await settle(tester, frames: 2);
      expect(watch.queries, i + 1);
    }
    await tester.pump(const Duration(minutes: 5));
    await settle(tester, frames: 2);
    expect(watch.queries, kWatchNudges.length, reason: 'kein Abfragen im Takt');
    // Ein spätes „hallo" holt die Route trotzdem.
    watch.hello(null);
    await settle(tester, frames: 4);
    expect(watch.routeParts, isNotEmpty);
  });

  testWidgets('#449: hat die Uhr bestätigt, fragt das Handy nicht nach', (tester) async {
    final watch = FakeGarminBridge.connected()..autoStore = true;
    await startFromRides(tester, garmin: watch);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester, frames: 10);
    await tester.pump(const Duration(minutes: 2));
    await settle(tester, frames: 2);
    expect(watch.queries, 0);
  });

  testWidgets('#449: Höhen und Abzweigungen rechnen schon, während das Startblatt offen ist', (tester) async {
    final watch = FakeGarminBridge.connected()..autoStore = true;
    final branches = Completer<List<WatchBranch>>();
    var calls = 0;
    await startFromRides(tester, garmin: watch, overrides: [
      watchBranchesLoaderProvider.overrideWithValue((_) {
        calls++;
        return branches.future;
      }),
    ]);
    await settle(tester, frames: 4);
    expect(calls, 1, reason: 'die Uhr ist gefunden, das Blatt noch offen');
    expect(watch.routeParts, isEmpty, reason: 'gesendet wird erst mit „Los"');
    branches.complete(const []);
    await settle(tester, frames: 2);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester, frames: 10);
    expect(watch.routeParts, isNotEmpty);
    expect(calls, 1, reason: '„Los" rechnet nicht noch einmal');
    final container = ProviderScope.containerOf(tester.element(find.byKey(const ValueKey('nav-stop'))));
    expect(container.read(watchSyncProvider.notifier).loads, 1);
    expect(find.byKey(const ValueKey('map-watch-stored')), findsOneWidget);
  });

  testWidgets('#449: ein Startblatt ohne „Los" lässt nichts Vorbereitetes liegen', (tester) async {
    final watch = FakeGarminBridge.connected()..autoStore = true;
    var calls = 0;
    await startFromRides(tester, garmin: watch, overrides: [
      watchBranchesLoaderProvider.overrideWithValue((_) async {
        calls++;
        return const <WatchBranch>[];
      }),
    ]);
    await settle(tester, frames: 4);
    expect(calls, 1);
    final container = ProviderScope.containerOf(tester.element(find.byKey(const ValueKey('nav-go'))));
    await tester.tapAt(const Offset(10, 10)); // Blatt zu, ohne „Los"
    await settle(tester, frames: 4);
    expect(find.byKey(const ValueKey('nav-go')), findsNothing);
    expect(watch.routeParts, isEmpty);
    // Eine Navigation derselben Linie ohne Startblatt rechnet selbst.
    final sync = container.read(watchSyncProvider.notifier)..follow(true);
    final before = sync.loads;
    container.read(navigationProvider.notifier).start([for (var i = 0; i <= 20; i++) LatLng(_lat, _lng(i))], 'Hausrunde');
    await settle(tester, frames: 10);
    expect(sync.loads, before + 1, reason: 'das Verworfene zählt nicht');
    expect(calls, 2);
    expect(watch.routeParts, isNotEmpty);
  });

  testWidgets('#449: solange die Uhr gesucht wird, sagt es das Startblatt', (tester) async {
    final gate = Completer<void>();
    final watch = FakeGarminBridge.connected()..statusGate = gate;
    await startFromRides(tester, garmin: watch);
    expect(find.byKey(const ValueKey('nav-watch-searching')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-watch')), findsNothing);
    gate.complete();
    await settle(tester, frames: 4);
    expect(find.byKey(const ValueKey('nav-watch-searching')), findsNothing);
    expect(find.byKey(const ValueKey('nav-watch')), findsOneWidget);
  });

  testWidgets('#449: ohne „gespeichert" sagt die Leiste, dass die Uhr nicht antwortet', (tester) async {
    final watch = FakeGarminBridge.connected();
    await startFromRides(tester, garmin: watch);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester, frames: 10);
    expect(watch.routeParts, isNotEmpty);
    expect(find.byKey(const ValueKey('map-watch-unconfirmed')), findsNothing);
    await tester.pump(kWatchAckWait);
    await settle(tester, frames: 2);
    expect(find.byKey(const ValueKey('map-watch-unconfirmed')), findsOneWidget);
    expect(find.byKey(const ValueKey('map-watch-stored')), findsNothing);
    // Jemand öffnet die Uhr-App: Sie meldet sich, die Route geht noch einmal.
    watch.hello(null);
    await settle(tester, frames: 4);
    expect(watch.routeParts.where((m) => m['p'] == 0), hasLength(2));
  });

  testWidgets('#449: fehlt die Uhr-App, geht nichts hin und die Leiste sagt es', (tester) async {
    final watch = FakeGarminBridge.connected()..openResult = WatchOpen.notInstalled;
    await startFromRides(tester, garmin: watch);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester, frames: 10);
    expect(watch.sent, isEmpty);
    expect(find.byKey(const ValueKey('map-watch-missing')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-approach')), findsOneWidget);
  });

  testWidgets('taps on the map do nothing while navigating; Beenden asks nothing', (tester) async {
    // Auf dem Telefon (360 dp): Leiste und Knöpfe passen, ohne Aufzeichnung.
    await startFromRides(tester, phone: true);
    await tester.tap(find.byKey(const ValueKey('nav-record')));
    await settle(tester, frames: 2);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester);
    expect(service.starts, 0, reason: 'Aufzeichnen war aus');
    expect(tester.getSize(find.byKey(const ValueKey('nav-stop'))).height, greaterThanOrEqualTo(44));
    expect(tester.getBottomRight(find.byKey(const ValueKey('nav-stop'))).dx, lessThanOrEqualTo(360));
    // Ein langer Druck öffnete sonst „Route ab hier" (#177).
    await longPressMapAt(tester, const LatLng(_lat, 11.005));
    await settle(tester);
    expect(find.text('Route ab hier'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('nav-stop')));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const ValueKey('nav-approach')), findsNothing);
    expect(screen.calls, [true, false]);
  });

  testWidgets('#356 PR 9: „Suche Standort …" stands until the first fix arrives', (tester) async {
    final gate = Completer<Position?>();
    await startFromRides(tester, positionFix: FakePositionFix()..gate = gate);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester);
    expect(find.byKey(const ValueKey('nav-searching')), findsOneWidget);
    expect(find.textContaining('Suche Standort'), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-approach')), findsNothing);
    gate.complete(fakePosition(_lat, 11, heading: 90, speed: 0));
    await settle(tester, frames: 20);
    expect(find.byKey(const ValueKey('nav-searching')), findsNothing);
    expect(find.byKey(const ValueKey('nav-approach')), findsOneWidget);
  });

  testWidgets('Zurück zur Route: a dashed way onto the route ahead, gone once back on it', (tester) async {
    store.rides
      ..clear()
      ..add(Ride(
        id: '20261008T090000Z',
        startedAt: DateTime.utc(2026, 10, 8, 9),
        endedAt: DateTime.utc(2026, 10, 8, 10),
        points: [
          for (var lat = _routeStartLat; lat <= 48.0004; lat += 0.0002)
            RidePoint(lat: lat, lng: _wayLng, at: DateTime.utc(2026, 10, 8, 9), accuracyM: 0),
        ],
        planned: true,
        name: 'Hausrunde',
      ));
    await startFromRides(tester, areaStore: await _areaWithTrack(), start: LatLng(_southLat, _wayLng));
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester);
    // Erst der zweite Fix daneben macht abseits — dann kommt der Knopf.
    expect(find.byKey(const ValueKey('nav-rejoin')), findsNothing);
    await fix(tester, _southLat, _wayLng, heading: 0);
    expect(textIn('nav-off'), contains('NEBEN DER ROUTE'));

    List<MapViewPolyline> dashed() =>
        [for (final l in fakeMapLayers(tester).polylines) if (l.dash != null) l];
    expect(dashed(), isEmpty);
    await tester.tap(find.byKey(const ValueKey('nav-rejoin')));
    await settle(tester, frames: 20);
    expect(find.byKey(const ValueKey('nav-rejoin-note')), findsNothing);
    // Vom Standort über den Weg nach Norden auf die Route, 200 m voraus.
    final back = dashed().single.points;
    expect(back.first.latitude, closeTo(_southLat, 1e-6));
    expect(back.last.latitude, greaterThan(_routeStartLat + 0.001));
    expect(back.every((p) => (p.longitude - _wayLng).abs() < 1e-4), isTrue);
    // Ein Stück liegt — der Knopf ist weg.
    expect(find.byKey(const ValueKey('nav-rejoin')), findsNothing);

    // Wieder auf der Route: Das Stück fällt weg.
    await fix(tester, _routeStartLat + 0.0002, _wayLng, heading: 0);
    expect(dashed(), isEmpty);
    expect(find.byKey(const ValueKey('nav-off')), findsNothing);
    expect(find.byKey(const ValueKey('nav-approach')), findsOneWidget);
  });

  testWidgets('#464: „Route umplanen" from 100 m, the navigation ends from 500 m, „Weiter navigieren" brings it back',
      (tester) async {
    await startFromRides(tester);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester);
    await fix(tester, _lat, _lng(2));
    // 60 m daneben: abseits, nur „Zurück zur Route".
    await fix(tester, _lat + 0.00055, _lng(3));
    await fix(tester, _lat + 0.00055, _lng(3));
    expect(find.byKey(const ValueKey('nav-rejoin')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-replan')), findsNothing);
    // 300 m daneben: beide Knöpfe nebeneinander, groß genug für Handschuhe.
    await fix(tester, _lat + 0.0027, _lng(4));
    expect(find.byKey(const ValueKey('nav-replan')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-rejoin')), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('nav-replan'))).height, greaterThanOrEqualTo(44));
    // Kein Bereich im Harness: Der Satz sagt es, die Route bleibt.
    await tester.tap(find.byKey(const ValueKey('nav-replan')));
    await settle(tester, frames: 10);
    expect(textIn('nav-rejoin-note'), contains('umplanen geht erst wieder'));
    expect(find.byKey(const ValueKey('nav-replan')), findsOneWidget);

    // 700 m daneben, zwei Fixe: Die Navigation endet von selbst.
    await fix(tester, _lat + 0.0063, _lng(5));
    expect(find.byKey(const ValueKey('nav-off')), findsOneWidget);
    await fix(tester, _lat + 0.0063, _lng(5));
    expect(find.byKey(const ValueKey('nav-off')), findsNothing);
    expect(find.byKey(const ValueKey('nav-stop')), findsNothing);
    expect(find.byKey(const ValueKey('nav-left')), findsOneWidget);
    expect(textIn('nav-left'), matches(RegExp(r'Navigation beendet: 70\d m neben der Route')));
    // Aufzeichnen war an (Vorgabe des Start-Blatts) — nur dann sagt es die Leiste.
    expect(textIn('nav-left'), contains('Die Aufzeichnung läuft weiter'));
    // Die Leiste fährt noch herein.
    await settle(tester, frames: 20);
    await tester.tap(find.byKey(const ValueKey('nav-left-resume')));
    await settle(tester);
    expect(find.byKey(const ValueKey('nav-go')), findsOneWidget, reason: 'die Route kommt mit dem Start-Blatt zurück');
  });

  testWidgets('a follow view stuck on country zoom goes back to 16 with the next fix (device check 2026-11-07)',
      (tester) async {
    await startFromRides(tester);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester);
    expect(fakeMap(tester).zoom, 16);
    // Wie am Pixel: Die Kamera steht noch auf der Länderansicht von vorher.
    fakeMap(tester).move(fakeMap(tester).center, 5);
    await fix(tester, _lat, _lng(2));
    expect(fakeMap(tester).zoom, 16);
    // Zwei Finger, die nur etwas weiter weg zoomen, bleiben stehen.
    fakeMap(tester).move(fakeMap(tester).center, 13.5);
    await fix(tester, _lat, _lng(3));
    expect(fakeMap(tester).zoom, 13.5);
  });

  testWidgets('#464: without a recording the leave bar does not claim one (device check 2026-11-07)', (tester) async {
    await startFromRides(tester);
    await tester.tap(find.byKey(const ValueKey('nav-record')));
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester);
    expect(service.starts, 0);
    await fix(tester, _lat, _lng(2));
    await fix(tester, _lat + 0.0063, _lng(5));
    await fix(tester, _lat + 0.0063, _lng(5));
    expect(textIn('nav-left'), matches(RegExp(r'^Navigation beendet: 70\d m neben der Route\.')));
    expect(textIn('nav-left'), isNot(contains('Aufzeichnung')));
    // Sie steht lange genug, um auf dem Rad hinzuschauen.
    expect(tester.widget<SnackBar>(find.byKey(const ValueKey('nav-left'))).duration, const Duration(seconds: 30));
  });

  testWidgets('zuletzt navigiert goes on where Beenden left off', (tester) async {
    await startFromRides(tester);
    await tester.tap(find.byKey(const ValueKey('nav-record')));
    await settle(tester, frames: 2);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester);
    await fix(tester, _lat, _lng(10));
    expect(textIn('nav-remaining'), contains('758 m'));
    await tester.tap(find.byKey(const ValueKey('nav-stop')));
    await settle(tester);

    // „Meine Fahrten" liegt noch offen im Reiter „Profil".
    await openTab(tester, 'Profil');
    await settle(tester);
    expect(find.byKey(const ValueKey('nav-last')), findsOneWidget);
    expect(textIn('nav-last'), contains('Hausrunde'));
    // Gemerkt ist der Stand beim Beenden — dort geht es weiter (auf einer
    // geraden Linie sähe man es nicht, die ganze Linie fände ihn auch;
    // hin und zurück zeigt es `route_progress_test`).
    final container = ProviderScope.containerOf(tester.element(find.byKey(const ValueKey('nav-last'))));
    expect(container.read(lastNavProvider)!.startAlongM, closeTo(758, 5));
    await tester.tap(find.byKey(const ValueKey('nav-last-resume')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester);
    expect(find.byKey(const ValueKey('nav-approach')), findsOneWidget);
    await fix(tester, _lat, _lng(12));
    expect(textIn('nav-remaining'), contains('607 m'));
    // Solange navigiert wird, gibt es keine Reiterleiste (Vollbild) — und
    // die Karte steht nicht in der Liste: Nach „Beenden" ist sie wieder da,
    // ab dem neuen Stand.
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byKey(const ValueKey('nav-stop')));
    await settle(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    await openTab(tester, 'Profil');
    await settle(tester);
    expect(find.byKey(const ValueKey('nav-last')), findsOneWidget);
    expect(container.read(lastNavProvider)!.startAlongM, closeTo(910, 5));
  });

  testWidgets('the service carries the navigation: location, a stop button, and Beenden from the notification',
      (tester) async {
    final keepAlive = FakeKeepAlive();
    final bridge = FakeNavServiceBridge();
    await startFromRides(tester, keepAlive: keepAlive, navBridge: bridge);
    await tester.tap(find.byKey(const ValueKey('nav-record')));
    await settle(tester, frames: 2);
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester);

    // Ohne Aufzeichnung läuft der Dienst für die Navigation allein (9.5).
    expect(service.starts, 0);
    expect(keepAlive.running, isTrue);
    expect(keepAlive.types, {KeepAliveType.location});
    expect(keepAlive.repeat, const Duration(seconds: 5));
    expect(keepAlive.buttons.map((b) => b.id), [kNavStopButton]);
    expect(bridge.active, isTrue);
    expect(bridge.armed!.points, hasLength(21));
    expect(bridge.armed!.title, 'Hausrunde');

    // „Navigation beenden" in der Benachrichtigung: Der Dienst meldet es,
    // die App beendet wie mit dem Knopf.
    for (final callback in FlutterForegroundTask.dataCallbacks.toList()) {
      callback(kNavMessageStop);
    }
    await settle(tester);
    expect(find.byKey(const ValueKey('nav-approach')), findsNothing);
    expect(find.byKey(const ValueKey('layers-button')), findsOneWidget);
    expect(keepAlive.running, isFalse);
    expect(bridge.active, isFalse);
  });

  testWidgets('a navigation the service kept going comes back after the app restarts', (tester) async {
    final keepAlive = FakeKeepAlive();
    final points = [for (var i = 0; i <= 20; i++) LatLng(_lat, _lng(i))];
    final bridge = FakeNavServiceBridge(
        pending: NavRouteData(points: points, title: 'Hausrunde', startAlongM: 600));
    await pumpApp(tester, backend,
        rideStore: store,
        rideService: service,
        keepAlive: keepAlive,
        navBridge: bridge,
        positionStream: fixes.stream,
        extraOverrides: [screenAwakeProvider.overrideWithValue(screen)]);
    await settle(tester);

    // Ohne Rückfrage — sie lief ja.
    expect(find.byKey(const ValueKey('nav-go')), findsNothing);
    expect(find.byKey(const ValueKey('nav-approach')), findsOneWidget);
    expect(keepAlive.running, isTrue);
    expect(bridge.armed!.startAlongM, 600);
    await fix(tester, _lat, _lng(10));
    expect(textIn('nav-remaining'), contains('758 m'));
  });

  testWidgets('picture-in-picture: allowed only while navigating, small shows the numbers, Beenden in the window',
      (tester) async {
    final pip = _FakePip();
    await startFromRides(tester, pip: pip);
    expect(pip.allowed, isEmpty, reason: 'ohne Navigation kein Fenster');
    await tester.tap(find.byKey(const ValueKey('nav-go')));
    await settle(tester);
    expect(pip.allowed, [true]);
    // „Minimieren" (#312 N3): ins Fenster, ohne nach Hause zu wischen.
    await tester.tap(find.byKey(const ValueKey('nav-minimize')));
    await settle(tester, frames: 2);
    expect(pip.enters, 1);

    // Klein: keine Leiste, keine Knöpfe, keine Reiterleiste — unten der
    // Abschnitt und das Band, und der Bildschirm darf aus (9.4). Das
    // Fenster ist 3:4 und ~150 dp breit: nichts läuft über. Wie auf dem
    // Gerät erst der Modus, dann die Größe (#415).
    await fix(tester, _lat, _lng(5));
    pip.shrink();
    await settle(tester);
    tester.view.physicalSize = const Size(450, 600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await settle(tester);
    // Die Kamera des Fensters, ohne neuen Fix: weiter draußen, und die
    // Position im freien Teil über der Zeile — bis 0.138 lag sie ein
    // Sechstel der alten Vollbildhöhe voraus, also unter dem Fenster.
    expect(fakeMap(tester).zoom, kNavPipZoom);
    final mPerPx = 156543.03392 * math.cos(_lat * math.pi / 180) / math.pow(2, kNavPipZoom);
    final ahead = const Distance().as(LengthUnit.Meter, const LatLng(_lat, 11.005), fakeMap(tester).center) / mPerPx;
    expect(ahead, closeTo(pipAheadPx(200), 0.5));
    expect(find.byKey(const ValueKey('nav-pip')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-approach')), findsNothing);
    expect(find.byKey(const ValueKey('nav-stop')), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    // Ein Zeichen und eine Zahl (#415): die Zielflagge, die km — keine
    // Beschriftung, die im Fenster keiner liest.
    expect(find.descendant(of: find.byKey(const ValueKey('nav-pip')), matching: find.byIcon(Icons.sports_score)),
        findsOneWidget);
    expect(pipNumber(), endsWith('km'));
    expect(textIn('nav-pip'), isNot(contains('BIS ZUM ZIEL')));
    expect(tester.getBottomLeft(find.byKey(const ValueKey('nav-pip'))).dy, 200, reason: 'unten im Fenster');
    expect(tester.getSize(find.byKey(const ValueKey('nav-pip'))).height, closeTo(200 * kNavPipBarShare, 0.01));
    expect(screen.calls.last, isFalse);
    await fix(tester, _lat + 0.0006, _lng(12));
    await fix(tester, _lat + 0.0006, _lng(12));
    expect(pipNumber(), '67 m');
    expect(find.byKey(const ValueKey('nav-pip-off-arrow')), findsOneWidget);

    // Wieder groß: alles zurück, der Bildschirm wieder an, der Zoom von
    // vorher.
    tester.view.reset();
    pip.grow();
    await settle(tester);
    expect(find.byKey(const ValueKey('nav-off')), findsOneWidget);
    expect(fakeMap(tester).zoom, 16);
    // Groß und navigierend: weiter ohne Reiterleiste (Vollbild).
    expect(find.byType(NavigationBar), findsNothing);
    expect(screen.calls.last, isTrue);

    // „Beenden" im Fenster beendet wie der Knopf, und das Fenster ist
    // danach nicht mehr erlaubt.
    pip.shrink();
    await settle(tester);
    pip.tapStop();
    await settle(tester);
    expect(find.byKey(const ValueKey('nav-pip')), findsNothing);
    expect(pip.allowed, [true, false]);
  });
}
