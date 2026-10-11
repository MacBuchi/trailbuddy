// Geländehöhen durch die echte Oberfläche (#186): Ein Trail ohne
// aufgezeichnete Höhen zeigt sein Profil aus dem Geländemodell (aus einem
// Bereich oder mit Empfang vom Host) und sagt es; der Export trägt die
// Modellhöhen markiert, und dieselbe Datei wieder importiert trägt NICHTS
// nach; eine Datei, deren Höhen weit neben dem Gelände liegen, bietet das
// Verwerfen an — und dann geht sie ohne Höhen hinauf.
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/core/gpx_share.dart';
import 'package:trailbuddy/features/offline_areas/area_providers.dart' show areaHeightReaderProvider;
import 'package:trailbuddy/features/offline_areas/height_tiles.dart';
import 'package:trailbuddy/features/routing/online_fill.dart';
import 'package:trailbuddy/features/trails/gpx_files.dart';
import 'package:trailbuddy/features/trails/gpx_writer.dart';
import 'package:trailbuddy/features/trails/trail_import_screen.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_heights.dart';
import '../fakes/l10n_de.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

Finder discard() => find.byWidgetPredicate(
    (w) => w is CheckboxListTile && (w.key as ValueKey?)?.value.toString().startsWith('import-discard-heights-') == true);

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late String annaId;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    annaId = anna.id;
    trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '');
  });

  final areaHeights =
      areaHeightReaderProvider.overrideWith((ref) async => HeightReader([MemoryHeightSource(slopeHeightTiles())]));

  Future<void> openSheet(WidgetTester tester, String name, {List<Override> extra = const [], Stream<List<ConnectivityResult>>? connectivity}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, backend, trails: trails, connectivity: connectivity, extraOverrides: [...extra]);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    await tester.tap(find.text(name));
    await settle(tester, frames: 20);
  }

  group('Blatt', () {
    testWidgets('ohne aufgezeichnete Höhen: Profil aus dem Bereich, beschriftet', (tester) async {
      trails.seedTrail(annaId, name: 'Hang');
      await openSheet(tester, 'Hang', extra: [areaHeights]);

      expect(find.byKey(const ValueKey('elevation-profile')), findsOneWidget);
      expect(find.textContaining(l10nDe.heightsTerrainLabel), findsOneWidget);
      expect(find.textContaining('≈↓'), findsOneWidget, reason: 'die Kachel sagt, dass es geschätzt ist');
      expect(find.textContaining('Hat deine GPX-Datei Höhen'), findsOneWidget, reason: 'eigener Trail: echte nachtragen');
      expect(find.textContaining('Keine Höhenangaben'), findsNothing);
      expect(find.textContaining('steilstes Stück'), findsNothing);
    });

    testWidgets('aufgezeichnete Höhen gewinnen — kein Geländemodell', (tester) async {
      trails.seedTrail(annaId, name: 'Gemessen', ele: [700, 640, 590]);
      await openSheet(tester, 'Gemessen', extra: [areaHeights]);
      expect(find.byKey(const ValueKey('elevation-profile')), findsOneWidget);
      expect(find.textContaining(l10nDe.heightsTerrainLabel), findsNothing);
      expect(find.textContaining('≈'), findsNothing);
    });

    testWidgets('ohne Bereich mit Empfang vom Host; ohne Empfang keine Anfrage', (tester) async {
      var opens = 0;
      final online = onlineHeightsFactoryProvider.overrideWithValue(() => OnlineHeights(
            open: () async {
              opens++;
              return PmTilesArchive.fromBytes(slopeHeightsArchive());
            },
            cache: OnlineTileCache(),
          ));
      trails.seedTrail(annaId, name: 'Hang');
      await openSheet(tester, 'Hang', extra: [online]);
      expect(find.textContaining(l10nDe.heightsTerrainLabel), findsOneWidget);
      expect(opens, 1);

      await tester.pumpWidget(const SizedBox());
      opens = 0;
      await openSheet(tester, 'Hang',
          extra: [online], connectivity: Stream.value(const [ConnectivityResult.none]));
      expect(find.textContaining(l10nDe.heightsTerrainLabel), findsNothing);
      expect(find.textContaining('Keine Höhenangaben'), findsOneWidget);
      expect(opens, 0, reason: 'ohne Empfang fragt das Blatt den Host nicht');
    });
  });

  testWidgets('Export trägt Modellhöhen markiert; dieselbe Datei importiert trägt nichts nach', (tester) async {
    final shared = <String>[];
    trails.seedTrail(annaId, name: 'Hang');
    await openSheet(tester, 'Hang', extra: [
      areaHeights,
      gpxShareProvider.overrideWithValue(({required String fileName, required String xml}) async {
        shared.add(xml);
        return GpxShareOutcome.shared;
      }),
    ]);
    await tester.ensureVisible(find.byKey(const ValueKey('trail-export')));
    await tester.tap(find.byKey(const ValueKey('trail-export')));
    await settle(tester, frames: 20);
    expect(shared, hasLength(1));
    expect(shared.single, contains(kTrailBuddyGpxNamespace));
    expect(shared.single, contains('<ele>'));

    // Dieselbe Datei wieder importieren — ein neuer Start der App.
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, backend, trails: trails, extraOverrides: [
      areaHeights,
      gpxPickerProvider.overrideWithValue(() async => [PickedFile.text('hang.gpx', shared.single)]),
    ]);
    await openTab(tester, 'Trails');
    await tester.tap(find.byTooltip('GPX importieren'));
    await settle(tester);
    await tester.tap(find.text('GPX- oder Zip-Dateien wählen'));
    await settle(tester, frames: 20);
    expect(find.textContaining('schon beigesteuert, die Datei hat keine Höhen'), findsOneWidget,
        reason: 'markierte Höhen werden nicht gelesen');
    expect(discard(), findsNothing);
    expect(trails.attachCalls, 0);
    expect(trails.recordings.single.ele, isNull);
  });

  group('Import prüft die Höhen der Datei', () {
    /// 1 200 m nach Norden ab 48°/9° mit Zeiten; Höhen = Gelände + [offset].
    Future<String> file(double offset) async {
      final b = StringBuffer('<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">'
          '<trk><name>Versatz</name><trkseg>');
      for (var i = 0; i <= 60; i++) {
        final lat = 48.0 + i * 20.0 / 111320.0;
        final t = DateTime.utc(2026, 5, 1, 10).add(Duration(seconds: i * 4));
        final ele = await slopeHeightAt(LatLng(lat, 9.0)) + offset;
        b.write('<trkpt lat="$lat" lon="9.0"><ele>$ele</ele><time>${t.toIso8601String()}</time></trkpt>');
      }
      b.write('</trkseg></trk></gpx>');
      return b.toString();
    }

    Future<void> import(WidgetTester tester, String text) async {
      await pumpApp(tester, backend, trails: trails, extraOverrides: [
        areaHeights,
        gpxPickerProvider.overrideWithValue(() async => [PickedFile.text('v.gpx', text)]),
      ]);
      await openTab(tester, 'Trails');
      await tester.tap(find.byTooltip('GPX importieren'));
      await settle(tester);
      await tester.tap(find.text('GPX- oder Zip-Dateien wählen'));
      await settle(tester, frames: 20);
    }

    testWidgets('weit daneben: verwerfen vorgewählt, und es geht ohne Höhen hinauf', (tester) async {
      await import(tester, await file(150));
      expect(discard(), findsOneWidget);
      expect(tester.widget<CheckboxListTile>(discard()).value, isTrue);
      expect(find.textContaining('liegen im Mittel 150 m über dem Gelände'), findsOneWidget);
      expect(find.textContaining('ohne Höhen der Datei'), findsOneWidget);

      await tester.tap(find.text('1 beisteuern'));
      await settle(tester, frames: 20);
      expect(trails.contributeCalls, 1);
      expect(trails.lastEles, isNull, reason: 'schlechte Höhen erreichen das Netz nie');
    });

    testWidgets('wer tippt, bevor der Vergleich fertig ist, wartet auf ihn', (tester) async {
      final gate = Completer<HeightReader>();
      final text = await file(150);
      await pumpApp(tester, backend, trails: trails, extraOverrides: [
        areaHeightReaderProvider.overrideWith((ref) => gate.future),
        gpxPickerProvider.overrideWithValue(() async => [PickedFile.text('v.gpx', text)]),
      ]);
      await openTab(tester, 'Trails');
      await tester.tap(find.byTooltip('GPX importieren'));
      await settle(tester);
      await tester.tap(find.text('GPX- oder Zip-Dateien wählen'));
      await settle(tester, frames: 20);
      expect(discard(), findsNothing, reason: 'der Vergleich läuft noch');
      await tester.tap(find.text('1 beisteuern'));
      await settle(tester);
      expect(trails.contributeCalls, 0, reason: 'erst der Vergleich, dann das Netz');
      gate.complete(HeightReader([MemoryHeightSource(slopeHeightTiles())]));
      await settle(tester, frames: 20);
      expect(trails.contributeCalls, 1);
      expect(trails.lastEles, isNull);
    });

    testWidgets('abgewählt gehen die Höhen der Datei mit', (tester) async {
      await import(tester, await file(150));
      await tester.tap(discard());
      await settle(tester);
      await tester.tap(find.text('1 beisteuern'));
      await settle(tester, frames: 20);
      expect(trails.lastEles, isNotNull);
    });

    testWidgets('Höhen nah am Gelände: nichts angeboten', (tester) async {
      await import(tester, await file(8));
      expect(discard(), findsNothing);
      await tester.tap(find.text('1 beisteuern'));
      await settle(tester, frames: 20);
      expect(trails.lastEles, isNotNull);
    });
  });
}
