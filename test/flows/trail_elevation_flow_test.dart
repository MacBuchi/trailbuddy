// Höhenmeter von der Datei bis ins Blatt (Issue #14): Der Import schickt
// eine Höhe je hochgeladenem Punkt mit, das Import-Blatt nennt dieselbe
// Zahl wie später das Trail-Blatt, und ein Trail ohne Höhen sagt das,
// statt „0 Hm" zu behaupten.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/trails/gpx_files.dart';
import 'package:trailbuddy/features/trails/trail_import_screen.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

/// Eine Spur nach Norden ab 48°/9°, 1 200 m, mit Zeiten; mit [ele] eine
/// gleichmäßige Abfahrt von 600 auf 500 m, sonst ohne `<ele>`.
String gpx(String name, {bool ele = true}) {
  const step = 20.0;
  const n = 60;
  final b = StringBuffer('<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">'
      '<trk><name>$name</name><trkseg>');
  for (var i = 0; i <= n; i++) {
    final lat = 48.0 + i * step / 111320.0;
    final t = DateTime.utc(2026, 5, 1, 10).add(Duration(seconds: i * 4));
    b.write('<trkpt lat="$lat" lon="9.0">'
        '${ele ? '<ele>${600 - 100 * i / n}</ele>' : ''}'
        '<time>${t.toIso8601String()}</time></trkpt>');
  }
  b.write('</trkseg></trk></gpx>');
  return b.toString();
}

Future<void> importFiles(WidgetTester tester, List<PickedFile> files,
    FakeBackend backend, FakeTrailRepository trails) async {
  await pumpApp(tester, backend, trails: trails, extraOverrides: [
    gpxPickerProvider.overrideWithValue(() async => files),
  ]);
  await openTab(tester, 'Trails');
  await tester.tap(find.byTooltip('GPX importieren'));
  await settle(tester);
  await tester.tap(find.text('GPX- oder Zip-Dateien wählen'));
  await settle(tester);
}

void main() {
  testWidgets('Höhen gehen mit hoch und stehen im Blatt', (tester) async {
    final backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    final trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '');
    await importFiles(tester, [PickedFile.text('w.gpx', gpx('Wurzeltrail'))], backend, trails);

    expect(find.textContaining('↓ 100 Hm · ↑ 0 Hm'), findsOneWidget,
        reason: 'das Import-Blatt nennt die Höhenmeter');
    await tester.tap(find.text('1 beisteuern'));
    await settle(tester, frames: 20);

    final rec = trails.recordings.single;
    expect(trails.lastEles, isNotNull);
    expect(rec.ele!.length, rec.points.length, reason: 'eine Höhe je hochgeladenem Punkt');
    expect(rec.ele!.first, 600);
    expect(rec.ele!.last, 500);

    await tester.tap(find.byType(BackButton));
    await settle(tester, frames: 20);
    expect(find.textContaining('↓ 100 Hm'), findsOneWidget, reason: 'auch in der Liste');
    await tester.tap(find.text('Wurzeltrail'));
    await settle(tester);

    expect(findLabel('↓ 100 Hm · ↑ 0 Hm'), findsOneWidget);
    expect(find.textContaining('Ø 8 % Gefälle'), findsOneWidget);
    expect(find.byKey(const ValueKey('elevation-profile')), findsOneWidget);
    expect(find.text('600 m'), findsOneWidget);
    expect(find.text('500 m'), findsOneWidget);
    expect(find.textContaining('In Trail-Richtung'), findsOneWidget);
    expect(find.textContaining('Keine Höhenangaben'), findsNothing);
  });

  testWidgets('ohne Höhen in der Datei: nichts erfunden, und das Blatt sagt es',
      (tester) async {
    final backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    final trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '');
    await importFiles(
        tester, [PickedFile.text('f.gpx', gpx('Flachland', ele: false))], backend, trails);

    expect(find.textContaining('Hm'), findsNothing);
    await tester.tap(find.text('1 beisteuern'));
    await settle(tester, frames: 20);
    expect(trails.contributeCalls, 1);
    expect(trails.lastEles, isNull);

    await tester.tap(find.byType(BackButton));
    await settle(tester, frames: 20);
    await tester.tap(find.text('Flachland'));
    await settle(tester);
    expect(find.textContaining('Keine Höhenangaben. Hat deine GPX-Datei welche'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('elevation-profile')), findsNothing);
    expect(find.textContaining('Hm'), findsNothing);
  });

  testWidgets('Blatt mit Profil passt auf ein kleines Telefon quer', (tester) async {
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    final trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '');
    trails.seedTrail(anna.id, name: 'Kurzer', ele: [700, 640, 590]);
    await pumpApp(tester, backend, trails: trails);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    // Quer liegen Suche und Filter-Chips über dem ersten Trail; die Liste
    // scrollt, geprüft wird hier das Blatt. Die faule Liste baut die Zeile
    // erst beim Scrollen (die Chips sind in der Testschrift breit).
    await tester.scrollUntilVisible(find.text('Kurzer'), 100,
        scrollable: find.byType(Scrollable).hitTestable().first);
    await settle(tester);
    await tester.tap(find.text('Kurzer'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'kein Überlauf');
    expect(find.byKey(const ValueKey('elevation-profile')), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Mein Beitrag'), 50,
        scrollable: find.descendant(
            of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first);
    expect(find.text('Mein Beitrag'), findsOneWidget);
  });
}
