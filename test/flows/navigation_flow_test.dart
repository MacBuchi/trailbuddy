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
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';
import 'package:trailbuddy/features/keep_alive/keep_alive.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/features/routing/nav_notice.dart';
import 'package:trailbuddy/features/routing/route_band.dart' show kRouteFollowOpacity;
import 'package:trailbuddy/features/routing/nav_providers.dart' show kNavArrivedLinger, kNavTrailDoneLinger, lastNavProvider;
import 'package:trailbuddy/features/routing/route_progress.dart' show kNavPipBarShare, kNavPipZoom, pipAheadPx;
import 'package:trailbuddy/features/trails/grade_shield.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
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
        mvtTile(own
            ? [road([_px(_southLat - 0.0002, _wayLng), _px(48.0 + 0.0005, _wayLng)], 'path', kindDetail: 'track')]
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
        rideFix: FakeRideFix()
          ..next = RidePoint(lat: start.latitude, lng: start.longitude, at: DateTime.now().toUtc(), accuracyM: 5),
        positionStream: fixes.stream,
        positionFix: positionFix ?? FakePositionFix(fakePosition(start.latitude, start.longitude, heading: 90, speed: 0)),
        extraOverrides: [
          screenAwakeProvider.overrideWithValue(screen),
          if (pip != null) pictureInPictureProvider.overrideWithValue(pip),
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
