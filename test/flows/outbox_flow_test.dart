// Der Ausgangskorb (#30) von außen: Ohne Netz wartet ein Import als
// gestrichelter Trail, ein Beitrag als Vermerk; mit Netz geht beides
// raus. Ein Serverfehler landet NICHT im Korb, und ein Korb, der nicht
// schreiben kann, lässt den Netzfehler durch.
import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/data/outbox.dart';
import 'package:trailbuddy/features/trails/gpx_files.dart';
import 'package:trailbuddy/models/trail.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/features/trails/trail_import_screen.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/fake_outbox.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

/// Eine Spur nach Norden ab 48°/9°, 1 200 m, bergab — ein Trail nach der
/// Importregel.
String gpx(String name) {
  final b = StringBuffer('<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">'
      '<trk><name>$name</name><trkseg>');
  for (var i = 0; i <= 60; i++) {
    final t = DateTime.utc(2026, 5, 1, 10).add(Duration(seconds: i * 4));
    b.write('<trkpt lat="${48.0 + i * 20 / 111320.0}" lon="9.0">'
        '<ele>${600 - 100 * i / 60}</ele><time>${t.toIso8601String()}</time></trkpt>');
  }
  b.write('</trkseg></trk></gpx>');
  return b.toString();
}

List<double> line(int n, {double lon = 11.0}) =>
    [for (var i = 0; i < n; i++) ...[lon, 47.0 + i * 100 / 111195.0]];

void main() {
  late FakeBackend backend;
  late String annaId;
  late FakeTrailRepository trails;
  late FakeOutbox outbox;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    annaId = anna.id;
    trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '');
    outbox = FakeOutbox();
  });

  Future<void> importOffline(WidgetTester tester,
      {Stream<List<ConnectivityResult>>? connectivity}) async {
    await pumpApp(tester, backend, trails: trails, outbox: outbox, connectivity: connectivity,
        extraOverrides: [
          gpxPickerProvider.overrideWithValue(
              () async => [PickedFile.text('w.gpx', gpx('Wurzeltrail'))]),
        ]);
    await openTab(tester, 'Trails');
    await tester.tap(find.byTooltip('GPX importieren'));
    await settle(tester);
    await tester.tap(find.text('GPX- oder Zip-Dateien wählen'));
    await settle(tester);
    trails.failNextContribute = const SocketException('offline');
    await tester.tap(find.text('1 beisteuern'));
    await settle(tester, frames: 20);
  }

  final banner = find.byKey(const ValueKey('outbox-banner'));

  testWidgets('Import ohne Netz: wartet gestrichelt, geht mit einem Tipp raus',
      (tester) async {
    await importOffline(tester);
    expect(find.textContaining('1 wartet im Ausgangskorb auf Netz'), findsOneWidget);
    expect(outbox.jobs, hasLength(1));
    final job = outbox.jobs.single as ContributeJob;
    expect(job.name, 'Wurzeltrail');
    expect(job.eles, isNotNull);
    expect(trails.recordings, isEmpty);

    await drainSnackbars(tester);
    await tester.tap(find.byType(BackButton));
    await settle(tester, frames: 20);
    expect(find.text('Wartet auf Übertragung (1)'), findsOneWidget);
    expect(find.text('Wurzeltrail'), findsOneWidget);
    expect(find.textContaining('WARTET AUF ÜBERTRAGUNG'), findsOneWidget);

    // Das Blatt sagt es — und bietet keinen Beitrag an.
    await tester.tap(find.text('Wurzeltrail'));
    await settle(tester);
    expect(find.byKey(const ValueKey('pending-notice')), findsOneWidget);
    expect(find.text('Mein Beitrag'), findsNothing);
    expect(find.text('Deine Einschätzung'), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);

    // Auf der Karte gestrichelt, dazu das Banner.
    await openTab(tester, 'Karte');
    await settle(tester, frames: 12);
    expect(banner, findsOneWidget);
    expect(find.text('1 wartet auf Übertragung'), findsOneWidget);
    final drawn = fakeMapLayers(tester)
        .polylines
        .singleWhere((p) => p.hitValue is Trail && (p.hitValue as Trail).id == job.id);
    expect(drawn.dash, isNotNull, reason: 'gestrichelt');

    // Tipp auf das Banner: jetzt ist Netz da.
    await tester.tap(banner);
    await settle(tester, frames: 20);
    expect(trails.recordings, hasLength(1));
    expect(trails.recordings.single.id, 'rec-${job.id}', reason: 'dieselbe client_id');
    expect(outbox.jobs, isEmpty);
    expect(banner, findsNothing);
    expect(find.text('1 übertragen'), findsOneWidget);
    await drainSnackbars(tester);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 12);
    expect(find.text('Meine Trails (1)'), findsOneWidget);
    expect(find.text('Wartet auf Übertragung (1)'), findsNothing);
    expect(trails.details.single.name, 'Wurzeltrail', reason: 'der Name aus der Datei');
  });

  testWidgets('Verbindung zurück ⇒ der Korb geht von selbst raus', (tester) async {
    final net = StreamController<List<ConnectivityResult>>();
    addTearDown(net.close);
    outbox.uid = annaId;
    outbox.jobs.add(ContributeJob(
        id: 'job-x',
        createdAt: DateTime.now().toUtc(),
        coords: line(5),
        source: RecordingSource.import,
        name: 'Offline-Trail'));
    // Der Start schickt schon — und scheitert hier noch am Netz. Geprüft
    // wird der WECHSEL danach.
    trails.failNextContribute = const SocketException('offline');
    await pumpApp(tester, backend, trails: trails, outbox: outbox, connectivity: net.stream);
    await settle(tester, frames: 12);
    expect(trails.contributeCalls, 1, reason: 'der Startversuch');
    expect(outbox.jobs, hasLength(1));
    net.add(const [ConnectivityResult.none]);
    await settle(tester, frames: 6);
    expect(trails.contributeCalls, 1, reason: 'kein Netz ist kein Anlass');
    net.add(const [ConnectivityResult.mobile]);
    await settle(tester, frames: 20);
    expect(trails.contributeCalls, 2);
    expect(outbox.jobs, isEmpty);
    expect(trails.recordings.single.id, 'rec-job-x');
  });

  testWidgets('Beitrag ohne Netz: wartet mit Vermerk, ersetzt einen älteren', (tester) async {
    trails.seedTrail(annaId, name: 'Roots');
    await pumpApp(tester, backend, trails: trails, outbox: outbox);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    await tester.tap(find.text('Roots'));
    await settle(tester);
    trails.failNextSaveDetails = const SocketException('offline');
    await tester.ensureVisible(find.byKey(const ValueKey('own-grade-3')));
    await tester.tap(find.byKey(const ValueKey('own-grade-3')));
    await settle(tester, frames: 20);
    expect(find.textContaining('Kein Netz — liegt im Ausgangskorb'), findsOneWidget);
    expect(find.byKey(const ValueKey('pending-details')), findsOneWidget);
    expect(findLabel('S3 · 1 Einschätzung'), findsOneWidget, reason: 'die wartende Fassung zählt');
    expect(outbox.jobs.single, isA<DetailsJob>());

    // Noch einmal ändern: EIN Auftrag je Trail.
    trails.failNextSaveDetails = const SocketException('offline');
    await tester.tap(find.byKey(const ValueKey('own-grade-4')));
    await settle(tester, frames: 20);
    expect(outbox.jobs, hasLength(1));
    expect((outbox.jobs.single as DetailsJob).details.grade, 4);
    await drainSnackbars(tester);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(find.textContaining('BEITRAG WARTET AUF ÜBERTRAGUNG'), findsOneWidget);

    await openTab(tester, 'Karte');
    await settle(tester, frames: 8);
    await tester.tap(banner);
    await settle(tester, frames: 20);
    expect(outbox.jobs, isEmpty);
    expect(trails.details.singleWhere((d) => d.userId == annaId).grade, 4);
    await drainSnackbars(tester);
  });

  testWidgets('abgelehnt vom Server: steht mit Grund da, bis jemand entscheidet',
      (tester) async {
    outbox.uid = annaId;
    // Zu kurz für einen Trail: Das Fake lehnt wie die RPC ab.
    outbox.jobs.add(ContributeJob(
        id: 'job-short',
        createdAt: DateTime.now().toUtc(),
        coords: const [11.0, 47.0, 11.0, 47.0003], // 33 m
        source: RecordingSource.import,
        name: 'Stummel'));
    await pumpApp(tester, backend, trails: trails, outbox: outbox);
    await settle(tester, frames: 12);
    // Fünf Anläufe bis „abgelehnt": Banner antippen, bis es so weit ist.
    for (var i = 0; i < 5 && outbox.jobs.single.failure == null; i++) {
      await tester.tap(banner);
      await settle(tester, frames: 12);
      await drainSnackbars(tester);
    }
    expect(outbox.jobs.single.failure, isNotNull);
    expect(find.text('1 abgelehnt'), findsOneWidget);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 12);
    expect(find.textContaining('Stummel'), findsOneWidget);
    await tester.tap(find.text('Stummel'));
    await settle(tester);
    expect(find.textContaining('Konnte nicht beigesteuert werden'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    await tester.tap(find.text('Aus dem Ausgangskorb entfernen'));
    await settle(tester, frames: 12);
    expect(outbox.jobs, isEmpty);
    expect(find.textContaining('Stummel'), findsNothing);
  });

  testWidgets('ein Serverfehler landet NICHT im Korb', (tester) async {
    await pumpApp(tester, backend, trails: trails, outbox: outbox, extraOverrides: [
      gpxPickerProvider.overrideWithValue(
          () async => [PickedFile.text('w.gpx', gpx('Wurzeltrail'))]),
    ]);
    await openTab(tester, 'Trails');
    await tester.tap(find.byTooltip('GPX importieren'));
    await settle(tester);
    await tester.tap(find.text('GPX- oder Zip-Dateien wählen'));
    await settle(tester);
    trails.failNextContribute = StateError('42501: nein');
    await tester.tap(find.text('1 beisteuern'));
    await settle(tester, frames: 20);
    expect(outbox.jobs, isEmpty);
    expect(find.textContaining('1 fehlgeschlagen'), findsWidgets);
    await drainSnackbars(tester);
  });

  testWidgets('kann der Korb nicht schreiben, kommt der Netzfehler durch', (tester) async {
    outbox.failOnAppend = true;
    await importOffline(tester);
    expect(outbox.jobs, isEmpty);
    expect(find.textContaining('Ausgangskorb'), findsNothing);
    expect(find.textContaining('1 fehlgeschlagen'), findsWidgets);
    await drainSnackbars(tester);
  });
}
