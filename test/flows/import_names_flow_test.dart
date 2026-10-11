// Namen aus der Datei: URL-kodierte Namen (Locus exportiert Trailforks-
// Spuren als „DREI%20EICHEN%20-%20…") werden dekodiert, zu lange auf 80
// Zeichen gekürzt — vorher scheiterte das Speichern des Namens am Check
// der Datenbank, und die Spur galt als fehlgeschlagen, obwohl die
// Aufzeichnung schon lag. Solche namenlosen Aufzeichnungen bekommen ihren
// Namen beim nächsten Import der Datei.
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/trails/gpx.dart';
import 'package:trailbuddy/features/trails/gpx_files.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';
import 'trail_elevation_flow_test.dart' show gpx, importFiles;

const _encoded =
    'DREI%20EICHEN%20-%20Sponsored%20by%20SIGMA%20-%20RV%20Edelweiss%201924%20Deidesheim%20e.V.';
const _decoded = 'DREI EICHEN - Sponsored by SIGMA - RV Edelweiss 1924 Deidesheim e.V.';

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '');
  });

  String? myName() => trails.details
      .singleWhere((d) => d.userId == backend.currentUserId)
      .name;

  testWidgets('URL-kodierter Name: dekodiert, beigesteuert, kein Fehler',
      (tester) async {
    expect(_encoded.length, greaterThan(kTrailNameMaxLength),
        reason: 'kodiert zu lang für den Server — genau der gemeldete Fall');
    await importFiles(tester, [PickedFile.text('d.gpx', gpx(_encoded))], backend, trails);

    expect(find.text(_decoded), findsOneWidget);
    await tester.tap(find.text('1 beisteuern'));
    await settle(tester, frames: 20);

    expect(find.text('1 beigesteuert, 0 fehlgeschlagen.'), findsOneWidget);
    expect(myName(), _decoded);
  });

  testWidgets('auch dekodiert zu lang: gekürzt statt gescheitert', (tester) async {
    final long = 'Sehr langer Trail ${'mit vielen Wörtern ' * 6}am Ende';
    await importFiles(tester, [PickedFile.text('l.gpx', gpx(long))], backend, trails);
    await tester.tap(find.text('1 beisteuern'));
    await settle(tester, frames: 20);

    expect(find.text('1 beigesteuert, 0 fehlgeschlagen.'), findsOneWidget);
    final name = myName()!;
    expect(name.length, lessThanOrEqualTo(kTrailNameMaxLength));
    expect(name, endsWith('…'));
    expect(name, startsWith('Sehr langer Trail mit vielen Wörtern'));
  });

  testWidgets('schon beigesteuert, aber ohne Namen: der Import holt ihn nach',
      (tester) async {
    // So liegt es nach dem Fehler vor 0.9.1: Aufzeichnung da, Name nicht.
    final track = parseGpx(gpx(_encoded), fallbackName: 'x').single;
    final pts = simplify(track.points);
    await trails.contribute(
        coords: flatCoords(pts),
        eles: trackElevations(pts),
        source: RecordingSource.import,
        clientId: 'vor-0-9-1');
    expect(myName(), isNull);

    await importFiles(tester, [PickedFile.text('d.gpx', gpx(_encoded))], backend, trails);
    expect(find.textContaining('schon beigesteuert — Name wird übernommen'),
        findsOneWidget);
    await tester.tap(find.text('1 übernehmen'));
    await settle(tester, frames: 20);

    expect(trails.contributeCalls, 1, reason: 'keine zweite Aufzeichnung');
    expect(myName(), _decoded);
    expect(find.text('0 beigesteuert, 1 Name übernommen, 0 fehlgeschlagen.'),
        findsOneWidget);
  });
}
