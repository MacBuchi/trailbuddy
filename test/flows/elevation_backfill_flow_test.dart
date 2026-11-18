// Höhen nachtragen (#16): Dieselbe Datei noch einmal gewählt legt keine
// zweite Aufzeichnung an, sondern trägt der alten die Höhen nach — nicht
// im Tageslimit, und danach zeigt das Blatt das Profil.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/trails/gpx.dart';
import 'package:trailbuddy/features/trails/gpx_files.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';
import 'trail_elevation_flow_test.dart' show gpx, importFiles;

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;

  /// Steuert die Datei bei wie ein Client vor 0.3.0: ohne Höhen.
  Future<void> seedOld(String text) async {
    final track = parseGpx(text, fallbackName: 'x').single;
    final flat = [
      for (final p in track.points) TrackPoint(p.lat, p.lon, time: p.time),
    ];
    final trailId = await trails.contribute(
      coords: flatCoords(simplify(flat)),
      source: RecordingSource.import,
      clientId: 'vor-0-3-0',
    );
    await trails.saveDetails(
      TrailDetails(
        trailId: trailId,
        userId: backend.currentUserId!,
        name: track.name,
      ),
    );
  }

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '');
  });

  testWidgets('dieselbe Datei trägt die Höhen nach, statt zu verdoppeln', (
    tester,
  ) async {
    await seedOld(gpx('Wurzeltrail'));
    // Am Tageslimit: Nachtragen zählt nicht mit.
    trails.dailyLimit = 1;
    await importFiles(
      tester,
      [PickedFile.text('w.gpx', gpx('Wurzeltrail'))],
      backend,
      trails,
    );

    expect(
      find.textContaining('schon beigesteuert — Höhen werden nachgetragen'),
      findsOneWidget,
    );
    await tester.tap(find.text('1 übernehmen'));
    await settle(tester, frames: 20);

    expect(trails.attachCalls, 1);
    expect(trails.contributeCalls, 1, reason: 'nur die alte Aufzeichnung');
    final rec = trails.recordings.single;
    expect(rec.ele, [600, 500]);
    expect(
      find.text('0 beigesteuert, 1 Höhen nachgetragen, 0 fehlgeschlagen.'),
      findsOneWidget,
    );

    await tester.tap(find.byType(BackButton));
    await settle(tester, frames: 20);
    await tester.tap(find.text('Wurzeltrail'));
    await settle(tester);
    expect(find.byKey(const ValueKey('elevation-profile')), findsOneWidget);
    expect(find.textContaining('Keine Höhenangaben'), findsNothing);
  });

  testWidgets('schon mit Höhen beigesteuert: gesperrt, nichts geht raus', (
    tester,
  ) async {
    await importFiles(
      tester,
      [PickedFile.text('w.gpx', gpx('Wurzeltrail'))],
      backend,
      trails,
    );
    await tester.tap(find.text('1 beisteuern'));
    await settle(tester, frames: 20);
    expect(trails.contributeCalls, 1);

    // Dieselbe Datei noch einmal.
    await tester.tap(find.text('GPX- oder Zip-Dateien wählen'));
    await settle(tester);
    expect(find.textContaining('schon beigesteuert'), findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    expect(find.text('0 beisteuern'), findsOneWidget);
    expect(trails.contributeCalls, 1);
    expect(trails.attachCalls, 0);
  });

  testWidgets('ohne Höhen in der Datei: erkannt, aber nichts nachzutragen', (
    tester,
  ) async {
    await seedOld(gpx('Flachland', ele: false));
    await importFiles(
      tester,
      [PickedFile.text('f.gpx', gpx('Flachland', ele: false))],
      backend,
      trails,
    );
    expect(
      find.textContaining('schon beigesteuert, die Datei hat keine Höhen'),
      findsOneWidget,
    );
    expect(find.text('0 beisteuern'), findsOneWidget);
  });
}
