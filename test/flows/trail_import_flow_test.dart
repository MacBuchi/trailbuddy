// Der GPX-Import (Konzept 5.2) einmal durch: Dateien wählen, Einordnung
// lesen, beisteuern, in der Liste wiederfinden. Der Abgleich selbst ist
// Sache der Datenbank (tool/matcher_check.sql); hier zählt, was die App
// aus einer Datei macht und was sie dem Nutzer sagt.
import 'dart:convert';

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/trails/gpx_files.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/features/trails/trail_import_screen.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

/// Eine Spur nach Norden ab 48°/9°: [lengthM] lang, mit Höhe von
/// [eleStart] nach [eleEnd], Zeiten für ~18 km/h wenn [timed].
String gpx(
  String name,
  double lengthM, {
  double eleStart = 600,
  double eleEnd = 500,
  bool timed = true,
}) {
  const step = 20.0;
  final n = (lengthM / step).round();
  final b = StringBuffer(
    '<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">'
    '<trk><name>$name</name><trkseg>',
  );
  for (var i = 0; i <= n; i++) {
    final lat = 48.0 + i * step / 111320.0;
    final ele = eleStart + (eleEnd - eleStart) * i / n;
    final t = DateTime.utc(2026, 5, 1, 10).add(Duration(seconds: i * 4));
    b.write(
      '<trkpt lat="$lat" lon="9.0"><ele>$ele</ele>'
      '${timed ? '<time>${t.toIso8601String()}</time>' : ''}</trkpt>',
    );
  }
  b.write('</trkseg></trk></gpx>');
  return b.toString();
}

void main() {
  testWidgets('kurze Abfahrt wird beigesteuert, Fahrt bleibt liegen', (
    tester,
  ) async {
    final backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    final trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '');
    final files = [
      PickedFile.text('wurzel.gpx', gpx('Wurzeltrail', 1200)),
      PickedFile.text(
        'runde.gpx',
        gpx('Sonntagsrunde', 12000, eleStart: 300, eleEnd: 320),
      ),
      PickedFile.text('kaputt.gpx', '<kml/>'),
    ];
    await pumpApp(
      tester,
      backend,
      trails: trails,
      extraOverrides: [gpxPickerProvider.overrideWithValue(() async => files)],
    );

    await openTab(tester, 'Trails');
    await tester.tap(find.byTooltip('GPX importieren'));
    await settle(tester);
    expect(find.text('GPX importieren'), findsWidgets);

    await tester.tap(find.text('GPX- oder Zip-Dateien wählen'));
    await settle(tester);

    // Zwei Spuren gefunden, eine davon als Trail; die Fahrt ist erklärt, die
    // kaputte Datei benannt.
    expect(find.text('2 Spuren gefunden, 1 davon als Trail'), findsOneWidget);
    expect(find.text('Wurzeltrail'), findsOneWidget);
    expect(
      find.textContaining('Fahrt — auf der Karte zerlegen'),
      findsOneWidget,
    );
    expect(find.textContaining('kaputt.gpx:'), findsOneWidget);
    expect(find.textContaining('aufgezeichnet'), findsWidgets);

    await tester.tap(find.text('1 beisteuern'));
    await settle(tester, frames: 20);

    expect(trails.contributeCalls, 1);
    expect(trails.recordings.single.source, RecordingSource.import);
    expect(trails.recordings.single.recordedAt, isNotNull);
    expect(trails.details.single.name, 'Wurzeltrail');
    expect(find.textContaining('1 Trail beigesteuert'), findsOneWidget);
    expect(find.text('1 beigesteuert, 0 fehlgeschlagen.'), findsOneWidget);

    // Zurück in die Liste: der Trail steht unter „Meine Trails".
    await tester.tap(find.byType(BackButton));
    await settle(tester, frames: 20);
    expect(find.text('Meine Trails (1)'), findsOneWidget);
    expect(find.text('Wurzeltrail'), findsOneWidget);
  });

  testWidgets('ohne Zeiten wird es „geplant", ein Fehlschlag wird benannt', (
    tester,
  ) async {
    final backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    final trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '');
    final files = [
      PickedFile.text('plan.gpx', gpx('Geplante Linie', 900, timed: false)),
      PickedFile.text('zwei.gpx', gpx('Zweiter', 800)),
    ];
    await pumpApp(
      tester,
      backend,
      trails: trails,
      extraOverrides: [gpxPickerProvider.overrideWithValue(() async => files)],
    );
    await openTab(tester, 'Trails');
    await tester.tap(find.byTooltip('GPX importieren'));
    await settle(tester);
    await tester.tap(find.text('GPX- oder Zip-Dateien wählen'));
    await settle(tester);
    expect(find.textContaining('geplant (keine Fahrzeiten)'), findsOneWidget);

    trails.failNextContribute = Exception('Datenbank nicht erreichbar');
    // Die Zeile „Gefahren am …" (#120) schiebt den Knopf nach unten.
    await tester.ensureVisible(find.text('2 beisteuern'));
    await settle(tester);
    await tester.tap(find.text('2 beisteuern'));
    await settle(tester, frames: 20);

    expect(find.text('1 beigesteuert, 1 fehlgeschlagen.'), findsOneWidget);
    expect(find.textContaining('Geplante Linie:'), findsOneWidget);
    expect(trails.recordings.single.source, RecordingSource.import);
    // Der gescheiterte Kandidat bleibt in der Liste, der andere ist weg.
    expect(find.byType(CheckboxListTile), findsOneWidget);
  });

  testWidgets(
    'Fahrdatum für eine Datei ohne Zeiten (#120): bleibt geplant, zählt als gefahren',
    (tester) async {
      final backend = FakeBackend();
      final anna = backend.addUser(username: 'anna');
      backend.signInAs(anna.id);
      final trails = FakeTrailRepository(
        myId: () => backend.currentUserId ?? '',
      );
      final files = [
        PickedFile.text('plan.gpx', gpx('Vereinslinie', 900, timed: false)),
      ];
      await pumpApp(
        tester,
        backend,
        trails: trails,
        extraOverrides: [
          gpxPickerProvider.overrideWithValue(() async => files),
        ],
      );
      await openTab(tester, 'Trails');
      await tester.tap(find.byTooltip('GPX importieren'));
      await settle(tester);
      await tester.tap(find.text('GPX- oder Zip-Dateien wählen'));
      await settle(tester);
      expect(find.textContaining('geplant (keine Fahrzeiten)'), findsOneWidget);
      expect(find.text('Gefahren am …'), findsOneWidget);

      // Der Wähler steht auf heute, später geht nicht; „OK" nimmt heute.
      await tester.tap(find.text('Gefahren am …'));
      await settle(tester);
      expect(find.text('Wann bist du ihn gefahren?'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await settle(tester);
      final today = DateTime.now();
      expect(
        find.textContaining('gezeichnet, gefahren am ${formatRideDate(today)}'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Gefahren am ${formatRideDate(today)} · ändern'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('1 beisteuern'));
      await settle(tester);
      await tester.tap(find.text('1 beisteuern'));
      await settle(tester, frames: 20);
      final rec = trails.recordings.single;
      expect(
        rec.source,
        RecordingSource.planned,
        reason: 'die Linie bleibt gezeichnet',
      );
      expect(rec.quality, 0.1);
      expect(
        rec.recordedAt,
        DateTime(today.year, today.month, today.day, 12).toUtc(),
        reason: 'der Tag, 12 Uhr Ortszeit',
      );
      expect(rec.ridden, isTrue);
    },
  );

  testWidgets('ein Locus-Zip wird ausgepackt, ein Foto daneben benannt', (
    tester,
  ) async {
    // Der Feldbefund zu v0.1.0: Auf Android waren GPX und Zip in der
    // Auswahl ausgegraut. Die Auswahl filtert dort jetzt nicht mehr, also
    // kommt auch Fremdes an — und muss mit Namen abgewiesen werden.
    final backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    final trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '');
    final zip = Archive()
      ..addFile(ArchiveFile.string('Tracks/eins.gpx', gpx('Erster', 700)))
      ..addFile(ArchiveFile.string('Tracks/zwei.gpx', gpx('Zweiter', 900)))
      ..addFile(
        ArchiveFile.string('__MACOSX/Tracks/._eins.gpx', 'Ressourcengabel'),
      )
      ..addFile(ArchiveFile.string('Tracks/liesmich.txt', 'hallo'));
    final files = [
      PickedFile(
        name: 'Trails.zip',
        bytes: Uint8List.fromList(ZipEncoder().encode(zip)!),
      ),
      PickedFile.text('foto.jpg', 'kein xml'),
    ];
    await pumpApp(
      tester,
      backend,
      trails: trails,
      extraOverrides: [gpxPickerProvider.overrideWithValue(() async => files)],
    );
    await openTab(tester, 'Trails');
    await tester.tap(find.byTooltip('GPX importieren'));
    await settle(tester);
    await tester.tap(find.text('GPX- oder Zip-Dateien wählen'));
    await settle(tester);

    expect(find.text('2 Spuren gefunden, 2 davon als Trail'), findsOneWidget);
    expect(find.text('Erster'), findsOneWidget);
    expect(find.text('Zweiter'), findsOneWidget);
    expect(find.text('foto.jpg: weder GPX noch Zip.'), findsOneWidget);
    // Die Ressourcengabel ist kein Fehler, sie fällt still weg.
    expect(find.textContaining('._eins'), findsNothing);
    expect(utf8.decode(files.last.bytes), 'kein xml');
  });

  testWidgets('am Tageslimit hält der Import an, der Rest bleibt für morgen', (
    tester,
  ) async {
    final backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    final trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '')
      ..dailyLimit = 2;
    final files = [
      for (var i = 1; i <= 4; i++)
        PickedFile.text('t$i.gpx', gpx('Trail $i', 600 + i * 50)),
    ];
    await pumpApp(
      tester,
      backend,
      trails: trails,
      extraOverrides: [gpxPickerProvider.overrideWithValue(() async => files)],
    );
    await openTab(tester, 'Trails');
    await tester.tap(find.byTooltip('GPX importieren'));
    await settle(tester);
    await tester.tap(find.text('GPX- oder Zip-Dateien wählen'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('4 beisteuern'), 200);
    await tester.tap(find.text('4 beisteuern'));
    await settle(tester, frames: 20);

    expect(trails.recordings, hasLength(2));
    // Nach dem ersten „nein" kein weiterer Versuch: 3 Aufrufe, nicht 4.
    expect(trails.contributeCalls, 3);
    expect(find.text('2 beisteuern'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    await tester.scrollUntilVisible(
      find.text('2 beigesteuert, 0 fehlgeschlagen.'),
      -200,
    );
    expect(
      find.textContaining('Für heute ist das Limit erreicht'),
      findsOneWidget,
    );
  });
}
