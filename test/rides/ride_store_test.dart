// Die Fahrt auf der Platte (#28). Gegen ein Temp-Verzeichnis, kein Netz.
// Geprüft wird der Unterschied zwischen „drei Stunden Fahren sind
// gesichert" und „sind weg" — und dass ein Prozess-Kill mitten im
// Schreiben höchstens den letzten Fix kostet.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/rides/ride_store.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rides_');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  final start = DateTime.utc(2026, 9, 28, 9);
  RidePoint point(int i) => RidePoint(
      lat: 47 + i / 1000, lng: 11, at: start.add(Duration(seconds: i * 5)),
      accuracyM: 6, altM: 900.0 - i);
  File active(Directory d) => File('${d.path}/${FileRideStore.dirName}/active.jsonl');

  test('das Fahrerprofil steht im Kopf der Datei und kommt mit der Fahrt zurück', () async {
    final store = FileRideStore(baseDir: dir);
    await store.begin(uid: 'me', startedAt: start, profile: 'ebike');
    await store.appendPoint(point(0));
    expect(await active(dir).readAsString(), contains('"profile":"ebike"'));
    final ride = await store.finish(uid: 'me', endedAt: start.add(const Duration(minutes: 5)));
    expect(ride!.profile, 'ebike');
    expect((await store.list(uid: 'me')).single.profile, 'ebike');
    // Ohne Profil (vor 0.70.0): kein Feld, kein Fehler.
    await store.begin(uid: 'me', startedAt: start.add(const Duration(hours: 1)));
    expect(await active(dir).readAsString(), isNot(contains('profile')));
    final old = await store.finish(uid: 'me', endedAt: start.add(const Duration(hours: 2)));
    expect(old!.profile, isNull);
  });

  test('eine geplante Fahrt (#158 Schritt 5) liegt als eigene Datei und kommt mit Name zurück', () async {
    final store = FileRideStore(baseDir: dir);
    final pts = [
      for (var i = 0; i < 3; i++) RidePoint(lat: 47 + i / 1000, lng: 11, at: start, accuracyM: 0),
    ];
    final saved = await store.savePlanned(
        uid: 'me', name: 'Runde: Hang', createdAt: start, points: pts,
        duration: const Duration(minutes: 90), profile: 'bio');
    expect(saved, isNotNull);
    expect(saved!.planned, isTrue);
    expect(saved.name, 'Runde: Hang');
    expect(saved.endedAt, start.add(const Duration(minutes: 90)));
    final listed = (await store.list(uid: 'me')).single;
    expect(listed.planned, isTrue);
    expect(listed.name, 'Runde: Hang');
    expect(listed.points, hasLength(3));
    expect(listed.duration, const Duration(minutes: 90));
    expect(listed.profile, 'bio');
    // Kein `.part` bleibt liegen, und eine aufgezeichnete Fahrt daneben
    // ist nicht geplant.
    expect(dir.listSync(recursive: true).where((f) => f.path.endsWith('.part')), isEmpty);
    await store.begin(uid: 'me', startedAt: start.add(const Duration(hours: 1)));
    await store.appendPoint(point(0));
    await store.finish(uid: 'me', endedAt: start.add(const Duration(hours: 2)));
    final rides = await store.list(uid: 'me');
    expect(rides.map((r) => r.planned), [false, true], reason: 'neueste zuerst');
    // Ein fremdes Konto sieht sie nicht.
    expect(await store.list(uid: 'other'), isEmpty);
  });

  test('eine Fahrt aus GPX (#188) liegt mit Profil und Name da, ein zweites Mal nicht', () async {
    final store = FileRideStore(baseDir: dir);
    final pts = [for (var i = 0; i < 4; i++) point(i)];
    expect(await store.saveImported(uid: 'me', name: 'Sonntagsrunde', points: pts, profile: 'ebike'),
        ImportSave.saved);
    final ride = (await store.list(uid: 'me')).single;
    expect(ride.imported, isTrue);
    expect(ride.planned, isFalse);
    expect(ride.name, 'Sonntagsrunde');
    expect(ride.profile, 'ebike');
    expect(ride.startedAt, pts.first.at, reason: 'der Start ist der erste Punkt der Datei');
    expect(ride.endedAt, pts.last.at);
    expect(ride.points.map((p) => p.altM), [900, 899, 898, 897]);
    expect(dir.listSync(recursive: true).where((f) => f.path.endsWith('.part')), isEmpty);
    // Dieselbe Datei noch einmal: nichts geschrieben, nichts überschrieben.
    expect(await store.saveImported(uid: 'me', name: 'anders', points: pts, profile: 'bio'),
        ImportSave.exists);
    expect((await store.list(uid: 'me')).single.name, 'Sonntagsrunde');
    // Eine Aufzeichnung kennt das Feld nicht.
    await store.begin(uid: 'me', startedAt: start.add(const Duration(hours: 3)));
    await store.appendPoint(point(0));
    await store.finish(uid: 'me', endedAt: start.add(const Duration(hours: 4)));
    expect((await store.list(uid: 'me')).map((r) => r.imported), [false, true]);
    expect(await store.list(uid: 'other'), isEmpty);
    expect(await store.saveImported(uid: 'me', name: 'leer', points: const []), ImportSave.failed);
  });

  test('Punkte überstehen Schreiben und Lesen, auch die Höhe', () async {
    final store = FileRideStore(baseDir: dir);
    await store.begin(uid: 'me', startedAt: start);
    for (var i = 0; i < 3; i++) {
      await store.appendPoint(point(i));
    }
    // Eine FRISCHE Instanz: Der Neustart der App ist der Fall, für den
    // es die Datei gibt.
    final ride = await FileRideStore(baseDir: dir).readActive(uid: 'me');
    expect(ride, isNotNull);
    expect(ride!.startedAt, start);
    expect(ride.points, hasLength(3));
    expect(ride.points[2].lat, closeTo(point(2).lat, 1e-9));
    expect(ride.points[2].altM, 898);
    expect(ride.points[2].accuracyM, 6);
  });

  test('eine abgeschnittene letzte Zeile kostet einen Fix, nicht die Fahrt', () async {
    final store = FileRideStore(baseDir: dir);
    await store.begin(uid: 'me', startedAt: start);
    for (var i = 0; i < 3; i++) {
      await store.appendPoint(point(i));
    }
    final file = active(dir);
    await file.writeAsString('${await file.readAsString()}{"lat":47.0,"ln');
    final ride = await FileRideStore(baseDir: dir).readActive(uid: 'me');
    expect(ride!.points, hasLength(3));
  });

  test('fremdes Konto sieht keine laufende und keine gespeicherte Fahrt', () async {
    final store = FileRideStore(baseDir: dir);
    await store.begin(uid: 'me', startedAt: start);
    await store.appendPoint(point(0));
    expect(await store.readActive(uid: 'someone'), isNull);
    await store.finish(uid: 'me', endedAt: start.add(const Duration(minutes: 1)));
    expect(await store.list(uid: 'someone'), isEmpty);
    expect(await store.list(uid: 'me'), hasLength(1));
  });

  test('beenden macht aus der laufenden eine gespeicherte Fahrt — umbenannt, nicht kopiert',
      () async {
    final store = FileRideStore(baseDir: dir);
    await store.begin(uid: 'me', startedAt: start);
    for (var i = 0; i < 4; i++) {
      await store.appendPoint(point(i));
    }
    final ended = start.add(const Duration(minutes: 30));
    final ride = await store.finish(uid: 'me', endedAt: ended);
    expect(ride, isNotNull);
    expect(ride!.id, '20260928T090000Z');
    expect(ride.endedAt, ended);
    expect(ride.points, hasLength(4));
    expect(await active(dir).exists(), isFalse);
    expect(await store.readActive(uid: 'me'), isNull, reason: 'nichts läuft mehr');

    final rides = await FileRideStore(baseDir: dir).list(uid: 'me');
    expect(rides, hasLength(1));
    expect(rides.single.id, ride.id);
    expect(rides.single.endedAt, ended, reason: 'die Ende-Zeile trägt die Dauer');
    expect(rides.single.duration, const Duration(minutes: 30));
    expect(rides.single.lengthM, closeTo(rideLengthM(ride.points), 1e-6));
    expect(rides.single.points.last.altM, 897);
  });

  test('ohne Ende-Zeile gilt der letzte Punkt als Ende', () async {
    final store = FileRideStore(baseDir: dir);
    await store.begin(uid: 'me', startedAt: start);
    await store.appendPoint(point(0));
    await store.appendPoint(point(1));
    // Absturz zwischen Anhängen und Umbenennen nachgestellt: Datei
    // liegt unter ihrem Zielnamen, aber ohne Ende-Zeile.
    await active(dir).rename('${dir.path}/${FileRideStore.dirName}/20260928T090000Z.jsonl');
    final rides = await store.list(uid: 'me');
    expect(rides.single.endedAt, point(1).at);
  });

  test('das Rad nachträglich setzen (#228): nur der Kopf ändert sich, geplante bleiben', () async {
    final store = FileRideStore(baseDir: dir);
    await store.begin(uid: 'me', startedAt: start, profile: 'bio');
    for (var i = 0; i < 3; i++) {
      await store.appendPoint(point(i));
    }
    await store.appendMark(RideMark(kind: RideMarkKind.values.first, at: start.add(const Duration(seconds: 5))));
    final ride = await store.finish(uid: 'me', endedAt: start.add(const Duration(minutes: 5)));
    final file = File('${dir.path}/${FileRideStore.dirName}/${ride!.id}.jsonl');
    final before = await file.readAsString();

    expect(await store.setProfile(ride.id, 'ebike'), isTrue);
    final after = await file.readAsString();
    // Alles nach der ersten Zeile Byte für Byte gleich.
    expect(after.substring(after.indexOf('\n')), before.substring(before.indexOf('\n')));
    final listed = (await store.list(uid: 'me')).single;
    expect(listed.profile, 'ebike');
    expect(listed.points, hasLength(3));
    expect(listed.marks, hasLength(1));
    expect(listed.endedAt, start.add(const Duration(minutes: 5)));
    expect(Directory('${dir.path}/${FileRideStore.dirName}').listSync().where((e) => e.path.endsWith('.part')),
        isEmpty);

    // Eine geplante Fahrt: Dauer ist mit dem Profil gerechnet, sie bleibt.
    final plan = await store.savePlanned(
        uid: 'me', name: 'Runde', createdAt: start.add(const Duration(days: 1)),
        points: [RidePoint(lat: 47, lng: 11, at: start, accuracyM: 0)],
        duration: const Duration(hours: 1), profile: 'bio');
    expect(await store.setProfile(plan!.id, 'ebike'), isFalse);
    expect((await store.list(uid: 'me')).firstWhere((r) => r.planned).profile, 'bio');
    // Kein Pfad, keine fremde Datei.
    expect(await store.setProfile('../${ride.id}', 'bio'), isFalse);
    expect(await store.setProfile('20990101T000000Z', 'bio'), isFalse);
  });

  test('Liste: neueste zuerst, löschen entfernt genau eine', () async {
    final store = FileRideStore(baseDir: dir);
    for (final day in [1, 3, 2]) {
      final s = DateTime.utc(2026, 9, day, 8);
      await store.begin(uid: 'me', startedAt: s);
      await store.appendPoint(RidePoint(lat: 47, lng: 11, at: s, accuracyM: 5));
      await store.finish(uid: 'me', endedAt: s.add(const Duration(minutes: 5)));
    }
    var rides = await store.list(uid: 'me');
    expect(rides.map((r) => r.startedAt.day), [3, 2, 1]);
    await store.delete(rides[1].id);
    rides = await store.list(uid: 'me');
    expect(rides.map((r) => r.startedAt.day), [3, 1]);
    // Kein Pfad als Kennung.
    await store.delete('../active');
    expect(await store.list(uid: 'me'), hasLength(2));
  });

  test('verwerfen löscht die laufende Fahrt; beenden ohne Fahrt ist null', () async {
    final store = FileRideStore(baseDir: dir);
    expect(await store.finish(uid: 'me', endedAt: start), isNull);
    await store.begin(uid: 'me', startedAt: start);
    await store.discardActive();
    expect(await store.readActive(uid: 'me'), isNull);
    expect(await store.list(uid: 'me'), isEmpty);
  });

  test('beginnen wirft, wenn sich nichts anlegen lässt', () async {
    final blocked = File('${dir.path}/blocked');
    await blocked.writeAsString('x');
    final store = FileRideStore(baseDir: Directory('${dir.path}/blocked'));
    expect(store.begin(uid: 'me', startedAt: start), throwsA(isA<FileSystemException>()));
  });

  test('Marken (#105) stehen in der Datei, überstehen den Neustart und das Beenden', () async {
    final store = FileRideStore(baseDir: dir);
    expect(await store.appendMark(RideMark(kind: RideMarkKind.start, at: start)), isFalse,
        reason: 'ohne laufende Fahrt keine Marke');
    await store.begin(uid: 'me', startedAt: start);
    await store.appendPoint(point(0));
    final begin = RideMark(kind: RideMarkKind.start, at: start.add(const Duration(seconds: 5)));
    expect(await store.appendMark(begin), isTrue);
    await store.appendPoint(point(1));
    await store.appendPoint(point(2));

    final restored = await FileRideStore(baseDir: dir).readActive(uid: 'me');
    expect(restored!.points, hasLength(3), reason: 'die Marke ist kein Punkt');
    expect(restored.marks, hasLength(1));
    expect(restored.marks.single.kind, RideMarkKind.start);
    expect(restored.marks.single.at, begin.at);
    expect(markedTrailOpen(restored.marks), isTrue);

    await store.appendMark(RideMark(kind: RideMarkKind.end, at: start.add(const Duration(seconds: 10))));
    final ride = await store.finish(uid: 'me', endedAt: start.add(const Duration(minutes: 1)));
    expect([for (final m in ride!.marks) m.kind], [RideMarkKind.start, RideMarkKind.end]);
    final listed = await FileRideStore(baseDir: dir).list(uid: 'me');
    expect(listed.single.marks, hasLength(2));
    expect(markedTrailOpen(listed.single.marks), isFalse);
  });
}
