// Das Zerlege-Blatt (#29) einmal durch: aus „Meine Fahrten" auf die
// Karte, ein bekannter Trail vorangehakt, ein Kandidat mit Griffen,
// Name und S-Grad, beides beigesteuert — und was das Blatt sagt, wenn
// es die Wege nicht kennt oder eine GPX-Fahrt hereinkommt.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/features/trails/gpx_files.dart';
import 'package:trailbuddy/features/trails/singletrail_scale.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/features/trails/trail_import_screen.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/fake_rides.dart';
import '../fakes/fake_tiles.dart';
import '../fakes/fake_trails.dart';
import '../fakes/l10n_de.dart';
import '../fakes/test_app.dart';

/// Alles in Kachel-Pixeln der z13-Kachel um 48°/9°, damit Fahrt, Trail
/// und Straßen ohne Umrechnung zueinander passen. Ein Pixel sind hier
/// rund 0,8 m; die Fahrt läuft bei px 2048 von py 3800 (Süden) nach 1300.
final _tile = tileAt(48.0, 9.0, 13);
const _n = 1 << 13;

LatLng ll(num px, num py) {
  final lon = (_tile.x + px / kTileExtent) / _n * 360 - 180;
  final v = math.pi * (1 - 2 * (_tile.y + py / kTileExtent) / _n);
  final lat = math.atan((math.exp(v) - math.exp(-v)) / 2) * 180 / math.pi;
  return LatLng(lat, lon);
}

/// Höhe je py: eben, bis bei 2100 die Abfahrt beginnt (80 Hm bis 1500).
double ele(int py) => py > 2100
    ? 600
    : py > 1500
        ? 600 - (2100 - py) / 600 * 80
        : 520;

final t0 = DateTime.utc(2026, 9, 27, 9);

Ride ride({List<RideMark> marks = const []}) {
  final points = <RidePoint>[];
  var i = 0;
  for (var py = 3800; py >= 1300; py -= 25) {
    final p = ll(2048, py);
    points.add(RidePoint(
        lat: p.latitude, lng: p.longitude, at: t0.add(Duration(seconds: 5 * i++)), accuracyM: 6, altM: ele(py)));
  }
  return Ride(id: 'r1', startedAt: t0, endedAt: points.last.at, points: points, marks: marks);
}

/// Straße auf der Fahrt zwischen den beiden Trailstücken (py 2600–2100)
/// und am Ende (1500–1300); dazwischen, auf der Abfahrt, keine.
Uint8List roadsTile() => mvtTile([
      road([(2048, 2620), (2048, 2100)], 'path', kindDetail: 'track'),
      road([(2048, 1500), (2048, 1200)], 'minor_road'),
      road([(100, 100), (4000, 100)], 'highway'),
    ]);

Future<MemoryAreaStore> areaWithRoads() async {
  final store = MemoryAreaStore();
  await store.putArchive(
      'a',
      writePmTiles(
        tiles: [TileToWrite(13, _tile.x, _tile.y, roadsTile())],
        tileCompression: Compression.none,
        bounds: const TileBounds(west: 8.9, south: 47.9, east: 9.1, north: 48.1),
      ));
  await store.saveIndex([
    StoredArea(
      id: 'a',
      name: 'Hausrunde',
      bounds: const AreaBounds(south: 47.9, west: 8.9, north: 48.1, east: 9.1),
      minZoom: 8,
      maxZoom: 13,
      build: '20260928',
      tiles: 1,
      bytes: 1,
      savedAt: DateTime.utc(2026, 9, 28),
    ),
  ]);
  return store;
}

void main() {
  late FakeBackend backend;
  late String annaId;
  late FakeTrailRepository trails;
  late FakeRideStore store;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    final ben = backend.addUser(username: 'ben');
    backend.signInAs(anna.id);
    backend.addFriendship(anna.id, ben.id);
    annaId = anna.id;
    trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    // Bens Trail liegt 3 px (2,4 m) neben dem ersten Stück der Fahrt.
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
    // Anna hat Roots schon beschrieben (ohne Namen): „wieder gefahren" ist
    // dann ein Beleg ohne Übernahme. Die Übernahme beim ERSTEN Befahren
    // (#102) prüft ihre eigene Gruppe, dort fehlt diese Zeile.
    trails.details.add(TrailDetails(trailId: 'trail-roots', userId: anna.id));
    store = FakeRideStore()..uid = anna.id;
    store.rides.add(ride());
  });

  List<MapViewPolyline> linesOf(WidgetTester tester, Color color) => [
        for (final l in fakeMapLayers(tester).polylines)
          if (l.color.toARGB32() == color.toARGB32()) l,
      ];

  /// Das Blatt ist eine faule Liste in einem halb geöffneten
  /// `DraggableScrollableSheet`: Was unter dem Rand liegt, ist nicht
  /// gebaut — erst hochziehen, dann suchen.
  Future<void> sheetScrollTo(WidgetTester tester, Finder finder) async {
    final list = find
        .descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable))
        .first;
    for (var i = 0; i < 8 && finder.evaluate().isEmpty; i++) {
      await tester.drag(list, const Offset(0, -300));
      await settle(tester, frames: 4);
    }
    await tester.ensureVisible(finder);
    await settle(tester);
  }

  Future<void> openFromRides(WidgetTester tester) async {
    await openTab(tester, 'Profil');
    await tester.tap(find.text('Meine Fahrten'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('ride-split-r1')));
    await settle(tester, frames: 30);
  }

  testWidgets('bekannter Trail vorangehakt, Kandidat mit Name, Grad und Charakter — beides beigesteuert',
      (tester) async {
    final areas = await areaWithRoads();
    await pumpApp(tester, backend, trails: trails, rideStore: store, areaStore: areas);
    await openFromRides(tester);

    expect(find.text('Fahrt zerlegen'), findsOneWidget);
    expect(find.text('Wieder gefahren'), findsOneWidget);
    expect(find.text('Roots'), findsOneWidget);
    expect(find.byKey(const ValueKey('split-no-roads')), findsNothing);
    await sheetScrollTo(tester, find.byKey(const ValueKey('split-candidate-0')));
    expect(find.byKey(const ValueKey('split-candidate-0')), findsOneWidget);
    expect(find.textContaining('Hm · '), findsOneWidget);
    expect(find.textContaining('% abseits von Wegen'), findsOneWidget);
    expect(find.text('2 beisteuern'), findsOneWidget);
    // Die Karte zeichnet mit: das bekannte Stück grün, der Kandidat in
    // seiner Farbe, darunter die blasse Fahrt.
    expect(linesOf(tester, AppColors.mapLines.mine), hasLength(1));
    expect(linesOf(tester, AppColors.mapLines.candidate), hasLength(1));
    final candidatePoints = linesOf(tester, AppColors.mapLines.candidate).single.points.length;

    // Die Griffe: den Kandidaten hinten kürzen — die Linie folgt.
    final slider = find.byKey(const ValueKey('split-candidate-range-0'));
    final box = tester.getRect(slider);
    await tester.dragFrom(Offset(box.right - 24, box.center.dy), const Offset(-60, 0));
    await settle(tester);
    expect(linesOf(tester, AppColors.mapLines.candidate).single.points.length, lessThan(candidatePoints));

    await tester.enterText(find.byKey(const ValueKey('split-candidate-name-0')), 'Neue Linie');
    await tester.tap(find.widgetWithText(DropdownButtonFormField<int?>, 'Keine Angabe'));
    await settle(tester);
    await tester.tap(find.text('S2 · ${singletrailGrade(2).short(l10nDe)}').last);
    await settle(tester);
    // Der Charakter (#72): dieselben Chips wie in „Mein Beitrag".
    for (final t in [TrailTrait.flowy, TrailTrait.jumps]) {
      final chip = find.byKey(ValueKey('split-candidate-trait-0-${t.db}'));
      await sheetScrollTo(tester, chip);
      await tester.tap(chip);
      await settle(tester);
    }

    await tester.tap(find.byKey(const ValueKey('split-submit')));
    await settle(tester, frames: 30);
    expect(trails.contributeCalls, 2);
    expect(trails.recordings.where((r) => r.userId == annaId), hasLength(2));
    for (final r in trails.recordings.where((r) => r.userId == annaId)) {
      expect(r.source, RecordingSource.app);
      expect(r.recordedAt, isNotNull);
      expect(r.ele, isNull, reason: 'GPS-Höhen werden nicht beigesteuert');
    }
    // Der Kandidat trägt Name und Grad; das wieder gefahrene Stück
    // bekommt keinen eigenen Namen (der Trail hat schon einen).
    final named = trails.details.where((d) => d.userId == annaId && d.name == 'Neue Linie').toList();
    expect(named, hasLength(1));
    expect(named.single.grade, 2);
    expect(named.single.traits, {TrailTrait.flowy, TrailTrait.jumps});
    expect(
        trails.details
            .where((d) => d.userId == annaId && d.name == null)
            .every((d) => d.grade == null && d.traits.isEmpty),
        isTrue);
    expect(find.textContaining('2 Abschnitte beigesteuert'), findsOneWidget);
    expect(find.text('Fahrt zerlegen'), findsNothing, reason: 'das Blatt ist zu');
    expect(linesOf(tester, AppColors.mapLines.candidate), isEmpty, reason: 'die Vorschau ist weg');
    expect(store.rides, hasLength(1), reason: 'die Fahrt bleibt auf dem Gerät');
  });

  testWidgets('Kandidat verwerfen, bekannten Trail abwählen: nichts geht raus', (tester) async {
    final areas = await areaWithRoads();
    await pumpApp(tester, backend, trails: trails, rideStore: store, areaStore: areas);
    await openFromRides(tester);
    await sheetScrollTo(tester, find.byKey(const ValueKey('split-candidate-discard-0')));
    await tester.tap(find.byKey(const ValueKey('split-candidate-discard-0')));
    await settle(tester);
    expect(find.byKey(const ValueKey('split-candidate-0')), findsNothing);
    expect(linesOf(tester, AppColors.mapLines.candidate), isEmpty);
    await tester.tap(find.byKey(const ValueKey('split-known-0')));
    await settle(tester);
    expect(find.text('Schließen'), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await settle(tester);
    expect(trails.contributeCalls, 0);
  });

  testWidgets('ohne gespeicherten Bereich kennt das Blatt die Wege nicht und sagt es',
      (tester) async {
    await pumpApp(tester, backend, trails: trails, rideStore: store);
    await openFromRides(tester);
    await sheetScrollTo(tester, find.byKey(const ValueKey('split-no-roads')));
    expect(find.byKey(const ValueKey('split-no-roads')), findsOneWidget);
    expect(find.textContaining('keinen gespeicherten Bereich'), findsOneWidget);
    expect(find.byKey(const ValueKey('split-candidate-0')), findsNothing);
    expect(find.text('Roots'), findsOneWidget, reason: 'bekannte Trails gehen ohne Wege');
    expect(find.text('1 beisteuern'), findsOneWidget);
  });

  testWidgets('Stück selbst wählen (#104): ohne gespeicherten Bereich, ohne Heimzone vorgewählt',
      (tester) async {
    await pumpApp(tester, backend, trails: trails, rideStore: store);
    await openFromRides(tester);
    expect(find.byKey(const ValueKey('split-candidate-0')), findsNothing,
        reason: 'ohne Wege findet die Suche nichts');
    await sheetScrollTo(tester, find.byKey(const ValueKey('split-pick-section')));
    await tester.tap(find.byKey(const ValueKey('split-pick-section')));
    await settle(tester);
    await sheetScrollTo(tester, find.byKey(const ValueKey('split-candidate-0')));
    expect(find.textContaining('selbst gewählt'), findsOneWidget);
    expect(find.textContaining('abseits von Wegen'), findsNothing);
    expect(find.byKey(const ValueKey('split-candidate-home-0')), findsNothing,
        reason: 'vorgewählt ohne die ersten und letzten 300 m');
    expect(linesOf(tester, AppColors.mapLines.candidate), hasLength(1));
    expect(find.text('2 beisteuern'), findsOneWidget, reason: 'Roots und das Stück');

    // Den vorderen Griff an den Anfang der Fahrt ziehen: Der Hinweis kommt.
    final slider = find.byKey(const ValueKey('split-candidate-range-0'));
    final box = tester.getRect(slider);
    await tester.dragFrom(Offset(box.left + 24, box.center.dy), Offset(-box.width, 0));
    await settle(tester);
    expect(find.byKey(const ValueKey('split-candidate-home-0')), findsOneWidget);
    expect(find.text('Beginnt nahe deinem Start.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('split-candidate-name-0')), 'Jump-Line');
    await tester.tap(find.byKey(const ValueKey('split-submit')));
    await settle(tester, frames: 30);
    expect(trails.contributeCalls, 2);
    expect(trails.details.where((d) => d.userId == annaId && d.name == 'Jump-Line'), hasLength(1));
  });

  testWidgets('unterwegs markiert (#105): vorangehakt, ohne gespeicherten Bereich, Griffe über die ganze Fahrt',
      (tester) async {
    // Beginn bei Punkt 60 (py 2300), Ende bei Punkt 80 (py 1800): 400 m
    // hinter Roots, abseits der Heimzone.
    store.rides
      ..clear()
      ..add(ride(marks: [
        RideMark(kind: RideMarkKind.start, at: t0.add(const Duration(seconds: 300))),
        RideMark(kind: RideMarkKind.end, at: t0.add(const Duration(seconds: 400))),
      ]));
    await pumpApp(tester, backend, trails: trails, rideStore: store);
    await openFromRides(tester);
    await sheetScrollTo(tester, find.byKey(const ValueKey('split-candidate-0')));
    expect(find.textContaining('unterwegs markiert'), findsOneWidget);
    expect(find.textContaining('abseits von Wegen'), findsNothing);
    expect(find.byKey(const ValueKey('split-candidate-1')), findsNothing, reason: 'genau ein Paar');
    expect(find.byKey(const ValueKey('split-candidate-home-0')), findsNothing);
    final check = tester.widget<Checkbox>(find.byKey(const ValueKey('split-candidate-check-0')));
    expect(check.value, isTrue, reason: 'vorangehakt');
    final range = tester.widget<RangeSlider>(find.byKey(const ValueKey('split-candidate-range-0')));
    expect((range.min, range.max), (0.0, 100.0), reason: 'die Griffe reichen über die ganze Fahrt');
    expect((range.values.start, range.values.end), (60.0, 80.0), reason: 'vorgewählt ist das Stück');
    expect(linesOf(tester, AppColors.mapLines.candidate).single.points, hasLength(21));
    expect(find.text('2 beisteuern'), findsOneWidget, reason: 'Roots und das markierte Stück');

    await tester.enterText(find.byKey(const ValueKey('split-candidate-name-0')), 'Wurzelweg');
    await tester.tap(find.byKey(const ValueKey('split-submit')));
    await settle(tester, frames: 30);
    expect(trails.contributeCalls, 2);
    expect(trails.details.where((d) => d.userId == annaId && d.name == 'Wurzelweg'), hasLength(1));
  });

  testWidgets('eine GPX-Fahrt geht aus dem Import in dasselbe Blatt', (tester) async {
    // 12 km nach Norden, kaum Gefälle: eine Fahrt (Konzept 5.2).
    final b = StringBuffer('<gpx version="1.1"><trk><name>Sonntagsrunde</name><trkseg>');
    for (var i = 0; i <= 600; i++) {
      final lat = 48.5 + i * 20 / 111320.0;
      b.write('<trkpt lat="$lat" lon="9.5"><ele>${300 + i * 0.03}</ele>'
          '<time>${DateTime.utc(2026, 5, 1, 10).add(Duration(seconds: i * 4)).toIso8601String()}</time></trkpt>');
    }
    b.write('</trkseg></trk></gpx>');
    await pumpApp(tester, backend, trails: trails, rideStore: store, extraOverrides: [
      gpxPickerProvider.overrideWithValue(() async => [PickedFile.text('runde.gpx', b.toString())]),
    ]);
    await openTab(tester, 'Trails');
    await tester.tap(find.byTooltip('GPX importieren'));
    await settle(tester);
    await tester.tap(find.text('GPX- oder Zip-Dateien wählen'));
    await settle(tester);
    expect(find.textContaining('Fahrt — auf der Karte zerlegen'), findsOneWidget);
    await tester.tap(find.byTooltip('Fahrt zerlegen'));
    await settle(tester, frames: 30);
    expect(find.text('Fahrt zerlegen'), findsOneWidget);
    expect(find.textContaining('12,0 km · 601 Punkte'), findsOneWidget);
    expect(find.text('Verwerfen'), findsNothing, reason: 'nur nach einer Aufzeichnung');
    expect(find.text('Schließen'), findsOneWidget);
  });

  group('Frage zu einer unbestätigten Meldung (#116)', () {
    testWidgets('an der Zeile des Trails, zur Zeit der Fahrt — „Trail ist frei" meldet sofort',
        (tester) async {
      final benId = trails.recordings.single.userId;
      // Ben meldete Roots von zu Hause als gesperrt, VOR der Fahrt.
      trails.seedReport(benId, 'trail-roots',
          status: TrailStatus.closed, confirmed: false, at: t0.subtract(const Duration(days: 1)));
      await pumpApp(tester, backend, trails: trails, rideStore: store);
      await openFromRides(tester);
      await sheetScrollTo(tester, find.byKey(const ValueKey('split-confirm-0-free')));
      expect(find.byKey(const ValueKey('split-confirm-0-question')), findsOneWidget);
      expect(find.text('Gemeldet: gesperrt — stimmt das?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('split-confirm-0-free')));
      await settle(tester, frames: 10);
      final mine = trails.reports.where((r) => r.userId == annaId).single;
      expect(mine.status, TrailStatus.open);
      expect(mine.confirmed, isTrue, reason: 'gefahren heißt vor Ort');
      expect(mine.reportedAt.toUtc(), t0, reason: 'die Zeit der Fahrt am Trail, nicht die des Tipps');
      expect(find.byKey(const ValueKey('split-confirm-0-sent')), findsOneWidget);
      expect(trails.contributeCalls, 0, reason: 'die Antwort hängt nicht am Beisteuern');
    });

    testWidgets('„Ändern…" lässt den Wert wählen',
        (tester) async {
      final benId = trails.recordings.single.userId;
      trails.seedReport(benId, 'trail-roots',
          condition: 2, confirmed: false, at: t0.subtract(const Duration(hours: 2)));
      await pumpApp(tester, backend, trails: trails, rideStore: store);
      await openFromRides(tester);
      await sheetScrollTo(tester, find.byKey(const ValueKey('split-confirm-0-change')));
      expect(find.text('Zustand: Abgerockt — stimmt das?'), findsOneWidget);
      expect(find.byKey(const ValueKey('split-confirm-0-free')), findsNothing,
          reason: '„Trail ist frei" gibt es nur zu einer warnenden Meldung');
      await tester.tap(find.byKey(const ValueKey('split-confirm-0-change')));
      await settle(tester);
      await sheetScrollTo(tester, find.byKey(const ValueKey('split-confirm-0-condition-4')));
      await tester.tap(find.byKey(const ValueKey('split-confirm-0-condition-4')));
      await settle(tester);
      await sheetScrollTo(tester, find.byKey(const ValueKey('split-confirm-0-submit')));
      await tester.tap(find.byKey(const ValueKey('split-confirm-0-submit')));
      await settle(tester, frames: 10);
      final mine = trails.reports.where((r) => r.userId == annaId).single;
      expect(mine.kind, ReportKind.condition);
      expect(mine.condition, 4);
      expect(mine.confirmed, isTrue);
    });

    testWidgets('eine Meldung, die erst NACH der Fahrt kam, wird nicht gefragt', (tester) async {
      final benId = trails.recordings.single.userId;
      trails.seedReport(benId, 'trail-roots',
          status: TrailStatus.closed, confirmed: false, at: t0.add(const Duration(days: 2)));
      await pumpApp(tester, backend, trails: trails, rideStore: store);
      await openFromRides(tester);
      await sheetScrollTo(tester, find.text('Kandidaten für neue Trails'));
      expect(find.text('Roots'), findsOneWidget);
      expect(find.byKey(const ValueKey('split-confirm-0-question')), findsNothing);
    });
  });

  group('zum ersten Mal gefahren: übernehmen (#102)', () {
    late String benId;
    setUp(() {
      benId = trails.recordings.single.userId;
      // Anna hat Roots noch nie beschrieben — sie kennt ihn nur über Ben.
      trails.details.removeWhere((d) => d.userId == annaId);
      trails.details
        ..removeWhere((d) => d.userId == benId)
        ..add(TrailDetails(
            trailId: 'trail-roots', userId: benId, name: 'Roots', grade: 2,
            traits: const {TrailTrait.flowy}));
    });

    testWidgets('die Zeile klappt auf, vorbelegt aus dem Netz — ohne Sterne kein Beisteuern',
        (tester) async {
      await pumpApp(tester, backend, trails: trails, rideStore: store);
      await openFromRides(tester);
      final name = find.byKey(const ValueKey('split-takeover-name-0'));
      await sheetScrollTo(tester, name);
      expect(tester.widget<TextField>(name).controller!.text, 'Roots');
      expect(find.text('Vorschlag aus dem Netz'), findsOneWidget, reason: 'der Median-S-Grad');
      final confirm = find.byKey(const ValueKey('split-takeover-confirm-0'));
      await sheetScrollTo(tester, confirm);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull,
          reason: 'Ben hat keine Sterne vergeben — Anna muss selbst bewerten');
      expect(find.byKey(const ValueKey('split-takeover-needs-rating-0')), findsOneWidget);
      expect(find.text('Schließen'), findsOneWidget, reason: 'unbestätigt zählt die Zeile nicht (E2)');

      final star = find.byKey(const ValueKey('split-takeover-rating-0-4'));
      await sheetScrollTo(tester, star);
      await tester.tap(star);
      await settle(tester);
      await sheetScrollTo(tester, confirm);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.tap(confirm);
      await settle(tester);
      expect(find.byKey(const ValueKey('split-takeover-done-0')), findsOneWidget);
      expect(find.text('1 beisteuern'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('split-submit')));
      await settle(tester, frames: 30);
      expect(trails.contributeCalls, 1);
      final mine = trails.details.singleWhere((d) => d.userId == annaId);
      expect(mine.name, 'Roots', reason: 'der Name des Buddys wird ihr eigener');
      expect(mine.grade, 2);
      expect(mine.traits, {TrailTrait.flowy});
      expect(mine.rating, 4);

      // Ben entfreundet und löscht seinen Beitrag: Annas Beitrag trägt
      // den Namen weiter, er hängt an nichts Fremdem mehr.
      trails.details.removeWhere((d) => d.userId == benId);
      final t = buildTrails(
              recordings: trails.recordings.where((r) => r.userId == annaId).toList(),
              details: trails.details,
              myId: annaId)
          .single;
      expect(t.displayName(l10nDe), 'Roots');
    });

    testWidgets('„Alle übernehmen" nimmt Sterne und Zustand aus dem Netz; der Zustand geht als Meldung raus',
        (tester) async {
      trails.details
        ..removeWhere((d) => d.userId == benId)
        ..add(TrailDetails(trailId: 'trail-roots', userId: benId, name: 'Roots', rating: 4));
      trails.seedReport(benId, 'trail-roots',
          condition: 3, confirmed: true, at: DateTime.now().subtract(const Duration(days: 5)));
      await pumpApp(tester, backend, trails: trails, rideStore: store);
      await openFromRides(tester);
      await sheetScrollTo(tester, find.byKey(const ValueKey('split-takeover-all')));
      await tester.tap(find.byKey(const ValueKey('split-takeover-all')));
      await settle(tester);
      expect(find.byKey(const ValueKey('split-takeover-done-0')), findsOneWidget);
      expect(find.textContaining('Ausgefahren'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('split-submit')));
      await settle(tester, frames: 30);
      final mine = trails.details.singleWhere((d) => d.userId == annaId);
      expect(mine.rating, 4);
      final report = trails.reports.singleWhere((r) => r.userId == annaId);
      expect(report.condition, 3);
      expect(report.confirmed, isTrue);
      expect(report.reportedAt.toUtc(), t0, reason: 'die Zeit der Fahrt am Trail');
    });

    testWidgets('wer ihn schon beschrieben hat, wird nicht gefragt', (tester) async {
      trails.details.add(TrailDetails(trailId: 'trail-roots', userId: annaId, rating: 3));
      await pumpApp(tester, backend, trails: trails, rideStore: store);
      await openFromRides(tester);
      expect(find.byKey(const ValueKey('split-takeover-0')), findsNothing);
      expect(find.text('1 beisteuern'), findsOneWidget);
    });
  });
}
