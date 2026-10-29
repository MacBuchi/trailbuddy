// Die Tour im Zerlege-Blatt (#134, Plan `docs/konzept-onboarding.md` 3.4
// und 4.4).
//
// Die Zusagen:
//
//   1. Sie startet EINMAL, im Blatt einer eigenen Aufzeichnung — nicht aus
//      dem GPX-Import und nicht, wenn sie gesehen ist.
//   2. Sie zeigt, was DIESE Fahrt hat: bekannter Trail, Kandidat mit
//      Griffen, ohne Wege der Ersatzschritt, „Stück selbst wählen", der
//      Knopf unten — und lässt weg, was fehlt (Übernahme, Nachfrage).
//   3. Aussparung auf den echten Zeilen, die Blase im Bild und nie darauf.
//   4. Überspringen und „Nicht jetzt" lassen das Blatt stehen und merken
//      „gesehen" (#417).
//   5. Aus der Kurzanleitung: die jüngste Fahrt, die Tour auch wenn schon
//      gesehen; ohne Fahrt ist der Knopf aus und sagt, warum.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/coach/coach.dart';
import 'package:trailbuddy/features/help/split_tour.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/features/trails/gpx_files.dart';
import 'package:trailbuddy/features/trails/trail_import_screen.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_rides.dart';
import '../fakes/fake_settings.dart';
import '../fakes/fake_tiles.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';
import '../fakes/l10n_de.dart';

/// Dieselbe Geometrie wie `ride_split_flow_test.dart`: Kachel-Pixel der
/// z13-Kachel um 48°/9°, die Fahrt läuft bei px 2048 von py 3800 nach 1300.
final _tile = tileAt(48.0, 9.0, 13);
const _n = 1 << 13;

LatLng ll(num px, num py) {
  final lon = (_tile.x + px / kTileExtent) / _n * 360 - 180;
  final v = math.pi * (1 - 2 * (_tile.y + py / kTileExtent) / _n);
  final lat = math.atan((math.exp(v) - math.exp(-v)) / 2) * 180 / math.pi;
  return LatLng(lat, lon);
}

final t0 = DateTime.utc(2026, 9, 27, 9);

/// Eine Fahrt mit einem unterwegs markierten Stück (Punkt 60 bis 80) —
/// so gibt es einen Kandidaten ohne gespeicherten Bereich.
Ride ride() {
  final points = <RidePoint>[];
  var i = 0;
  for (var py = 3800; py >= 1300; py -= 25) {
    final p = ll(2048, py);
    points.add(RidePoint(lat: p.latitude, lng: p.longitude, at: t0.add(Duration(seconds: 5 * i++)), accuracyM: 6));
  }
  return Ride(id: 'r1', startedAt: t0, endedAt: points.last.at, points: points, marks: [
    RideMark(kind: RideMarkKind.start, at: t0.add(const Duration(seconds: 300))),
    RideMark(kind: RideMarkKind.end, at: t0.add(const Duration(seconds: 400))),
  ]);
}

CoachPainter painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((c) => c.painter)
    .whereType<CoachPainter>()
    .single;

final intro = find.byKey(const ValueKey('coach-intro'));
final bubble = find.byKey(const ValueKey('coach-bubble'));

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late FakeRideStore store;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    final ben = backend.addUser(username: 'ben');
    backend.signInAs(anna.id);
    backend.addFriendship(anna.id, ben.id);
    trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    // Bens Trail neben dem ersten Stück der Fahrt; Anna hat ihn schon
    // beschrieben — also „wieder gefahren", keine Übernahme.
    trails.recordings.add(TrailRecording(
      id: 'rec-roots',
      trailId: 'trail-roots',
      userId: ben.id,
      source: RecordingSource.import,
      recordedAt: null,
      reversed: false,
      quality: 0.5,
      createdAt: DateTime.utc(2026, 1, 1),
      points: [for (var py = 3800; py >= 2600; py -= 40) ll(2051, py)],
      lengthM: 960,
    ));
    trails.details.add(TrailDetails(trailId: 'trail-roots', userId: ben.id, name: 'Roots'));
    trails.details.add(TrailDetails(trailId: 'trail-roots', userId: anna.id));
    store = FakeRideStore()..uid = anna.id;
    store.rides.add(ride());
  });

  FakeSettings fresh() => FakeSettings(seenCoachTours: const {'trails', 'buddys'});

  Future<void> openFromRides(WidgetTester tester) async {
    await openProfilePage(tester, 'rides');
    await tester.tap(find.byKey(const ValueKey('ride-split-r1')));
    await settle(tester, frames: 30);
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.descendant(of: bubble, matching: find.text('Weiter')));
    await settle(tester);
  }

  String shownTitle(WidgetTester tester) => tester
      .widgetList<Text>(find.descendant(of: bubble, matching: find.byType(Text)))
      .first
      .data!;

  testWidgets('nach der Aufzeichnung: Startseite, dann was DIESE Fahrt hat', (tester) async {
    final settings = fresh();
    await pumpApp(tester, backend, trails: trails, rideStore: store, settings: settings);
    await openFromRides(tester);

    expect(intro, findsOneWidget);
    expect(find.text('Deine erste Fahrt zerlegen'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('coach-intro-start')));
    await settle(tester);

    final seen = <String>[];
    for (var i = 0; i < 10 && bubble.evaluate().isNotEmpty; i++) {
      seen.add(shownTitle(tester));
      final last = find.descendant(of: bubble, matching: find.text('Los geht\'s'));
      await tester.tap(last.evaluate().isNotEmpty
          ? last
          : find.descendant(of: bubble, matching: find.text('Weiter')));
      await settle(tester);
    }
    expect(seen, [
      'Schon bekannt',
      'Ein Kandidat',
      'Erst einen Bereich speichern',
      'Was die Suche nicht findet',
      'Was zu Buddys geht',
    ], reason: 'ohne Übernahme, Nachfrage und Heimzone — die hat diese Fahrt nicht');
    expect(settings.seenCoachTours, contains('split'));
    expect(find.byKey(const ValueKey('split-submit')), findsOneWidget, reason: 'das Blatt bleibt offen');
  });

  testWidgets('Aussparung auf den echten Zeilen, die Blase im Bild und nie '
      'darauf', (tester) async {
    tester.view.physicalSize = const Size(360, 740) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, backend, trails: trails, rideStore: store, settings: fresh());
    await openFromRides(tester);
    await tester.tap(find.byKey(const ValueKey('coach-intro-start')));
    await settle(tester, frames: 12);

    final targets = {
      'Schon bekannt': find.byKey(const ValueKey('split-known-0')),
      'Ein Kandidat': find.byKey(const ValueKey('split-candidate-range-0')),
      'Erst einen Bereich speichern': find.byKey(const ValueKey('split-no-roads')),
      'Was die Suche nicht findet': find.byKey(const ValueKey('split-pick-section')),
      'Was zu Buddys geht': find.byKey(const ValueKey('split-submit')),
    };
    for (final MapEntry(key: title, value: target) in targets.entries) {
      expect(shownTitle(tester), title);
      expect(tester.takeException(), isNull, reason: 'Überlauf vor „$title"');
      final lit = painter(tester).lit.single;
      final r = tester.getRect(target);
      expect(lit.inflate(0.5).contains(r.center), isTrue, reason: '$title: $lit gegen $r');
      final b = tester.getRect(bubble);
      final screen = Offset.zero & const Size(360, 740);
      expect(screen.contains(b.topLeft) && screen.contains(b.bottomRight - const Offset(1, 1)), isTrue,
          reason: '$title: Blase $b außerhalb');
      for (final x in [...painter(tester).lit, ...painter(tester).ring]) {
        expect(b.overlaps(x), isFalse, reason: '$title: Blase $b deckt $x zu');
      }
      if (title == 'Was zu Buddys geht') break;
      await next(tester);
      await settle(tester, frames: 6);
    }
  });

  testWidgets('Überspringen lässt das Blatt stehen und merkt die Tour', (tester) async {
    final settings = fresh();
    await pumpApp(tester, backend, trails: trails, rideStore: store, settings: settings);
    await openFromRides(tester);
    await tester.tap(find.byKey(const ValueKey('coach-intro-start')));
    await settle(tester);
    await tester.tap(find.descendant(of: bubble, matching: find.text('Überspringen')));
    await settle(tester);
    expect(bubble, findsNothing);
    expect(settings.seenCoachTours, contains('split'));
    expect(find.byKey(const ValueKey('split-submit')), findsOneWidget, reason: 'das Blatt bleibt');
  });

  testWidgets('„Nicht jetzt" lässt das Blatt stehen und merkt die Tour (#417)', (tester) async {
    final settings = fresh();
    await pumpApp(tester, backend, trails: trails, rideStore: store, settings: settings);
    await openFromRides(tester);
    await tester.tap(find.byKey(const ValueKey('coach-intro-later')));
    await settle(tester);
    expect(intro, findsNothing);
    expect(settings.seenCoachTours, contains('split'), reason: '„Nicht jetzt" ist gemerkt');
    expect(find.byKey(const ValueKey('split-submit')), findsOneWidget);

    // Blatt zu (Zurück), dann dieselbe Fahrt noch einmal aus der Liste.
    await tester.binding.handlePopRoute();
    await settle(tester, frames: 12);
    expect(find.byKey(const ValueKey('split-submit')), findsNothing);
    await openTab(tester, 'Profil');
    await tester.tap(find.byKey(const ValueKey('ride-split-r1')));
    await settle(tester, frames: 30);
    expect(intro, findsNothing, reason: 'beim nächsten Blatt fragt sie nicht wieder');
    expect(find.byKey(const ValueKey('split-submit')), findsOneWidget, reason: 'das Blatt steht');
  });

  testWidgets('aus dem GPX-Import: keine Tour — sie gehört zur Aufzeichnung', (tester) async {
    final b = StringBuffer('<gpx version="1.1"><trk><name>Sonntagsrunde</name><trkseg>');
    for (var i = 0; i <= 600; i++) {
      final lat = 48.5 + i * 20 / 111320.0;
      b.write('<trkpt lat="$lat" lon="9.5"><ele>${300 + i * 0.03}</ele>'
          '<time>${DateTime.utc(2026, 5, 1, 10).add(Duration(seconds: i * 4)).toIso8601String()}</time></trkpt>');
    }
    b.write('</trkseg></trk></gpx>');
    await pumpApp(tester, backend, trails: trails, rideStore: store, settings: fresh(), extraOverrides: [
      gpxPickerProvider.overrideWithValue(() async => [PickedFile.text('runde.gpx', b.toString())]),
    ]);
    await openTab(tester, 'Trails');
    await tester.tap(find.byTooltip('GPX importieren'));
    await settle(tester);
    await tester.tap(find.text('GPX- oder Zip-Dateien wählen'));
    await settle(tester);
    await tester.tap(find.byTooltip('Fahrt zerlegen'));
    await settle(tester, frames: 30);
    expect(find.text('Fahrt zerlegen'), findsOneWidget, reason: 'das Blatt ist offen');
    expect(intro, findsNothing);
  });

  testWidgets('gesehen: keine Tour mehr', (tester) async {
    await pumpApp(tester, backend, trails: trails, rideStore: store);
    await openFromRides(tester);
    expect(find.byKey(const ValueKey('split-submit')), findsOneWidget);
    expect(intro, findsNothing);
  });

  testWidgets('aus der Kurzanleitung: die jüngste Fahrt, auch wenn schon gesehen', (tester) async {
    await pumpApp(tester, backend, trails: trails, rideStore: store);
    await openProfilePage(tester, 'help');
    final start = find.byKey(const ValueKey('help-split-tour'));
    await tester.scrollUntilVisible(start, 300,
        scrollable: find.descendant(of: find.byKey(const ValueKey('help-list')), matching: find.byType(Scrollable)));
    await settle(tester);
    await tester.tap(start);
    await settle(tester, frames: 30);
    expect(find.byKey(const ValueKey('split-submit')), findsOneWidget, reason: 'das Blatt der Fahrt');
    expect(find.text('Deine erste Fahrt zerlegen'), findsOneWidget);
  });

  testWidgets('ohne Fahrt ist der Knopf aus und sagt, warum', (tester) async {
    store.rides.clear();
    await pumpApp(tester, backend, trails: trails, rideStore: store);
    await openProfilePage(tester, 'help');
    final start = find.byKey(const ValueKey('help-split-tour'));
    await tester.scrollUntilVisible(start, 300,
        scrollable: find.descendant(of: find.byKey(const ValueKey('help-list')), matching: find.byType(Scrollable)));
    await settle(tester);
    expect(tester.widget<ButtonStyleButton>(start).onPressed, isNull);
    expect(find.byKey(const ValueKey('help-split-tour-hint')), findsOneWidget);
  });

  test('die Tour hat eine Startseite und ihre Kennung', () {
    expect(splitTourScript(l10nDe).id, 'split');
    expect(splitTourScript(l10nDe).steps.first.isIntro, isTrue);
  });
}
