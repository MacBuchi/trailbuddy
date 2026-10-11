// Bestätigen durch Fahren (#116): die reinen Regeln — welche Trails
// gefragt werden, wann gefragt wird, was die Benachrichtigung sagt und
// was aus den Antworten hinausgeht. Dazu die Datei (Fragen und Antworten
// in der Fahrt, die Ziel-Liste) und der Weg einer Antwort vom Knopf in
// die Fahrt.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/rides/ride_confirm.dart';
import 'package:trailbuddy/features/rides/ride_confirm_notify.dart';
import 'package:trailbuddy/features/rides/ride_store.dart';
import 'package:trailbuddy/features/rides/ride_task_handler.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart' show RecordingSource;
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_rides.dart';
import '../fakes/l10n_de.dart';

void main() {
  final t0 = DateTime.utc(2026, 9, 30, 10);
  const mPerDegLat = 111195.0;

  /// Ein Trail nach Norden ab 47,2° N / 11,4° O, 1 km lang.
  List<LatLng> northLine({double lng = 11.4}) =>
      [LatLng(47.2, lng), LatLng(47.2 + 500 / mPerDegLat, lng), LatLng(47.2 + 1000 / mPerDegLat, lng)];

  RidePoint fix(double northM, {double eastM = 0, double acc = 5, int s = 0}) => RidePoint(
      lat: 47.2 + northM / mPerDegLat,
      lng: 11.4 + eastM / (mPerDegLat * 0.679),
      at: t0.add(Duration(seconds: s)),
      accuracyM: acc);

  ConfirmTarget target({String id = 't1', TrailStatus? status = TrailStatus.closed, int? condition, double lng = 11.4}) =>
      ConfirmTarget(trailId: id, name: 'Hexenkessel', line: northLine(lng: lng), status: status, condition: condition);

  group('welche Trails', () {
    TrailRecording rec(String trail, String user) => TrailRecording(
        id: 'r-$trail-$user', trailId: trail, userId: user, source: RecordingSource.import,
        recordedAt: null, reversed: false, quality: 0.4, createdAt: DateTime.utc(2026),
        points: northLine(), lengthM: 1000);
    TrailReport rep(String trail, {TrailStatus? status, int? condition, required bool confirmed, required int day}) =>
        TrailReport(
            id: 'x-$trail-$day-$confirmed', trailId: trail, userId: 'bob',
            kind: status != null ? ReportKind.status : ReportKind.condition,
            status: status, condition: condition, confirmed: confirmed,
            reportedAt: DateTime.utc(2026, 9, day));

    test('nur, was unbestätigt ANGEZEIGT wird — Meldung und Zustand', () {
      final trails = buildTrails(
        recordings: [rec('a', 'bob'), rec('b', 'bob'), rec('c', 'bob'), rec('d', 'bob')],
        details: [
          const TrailDetails(trailId: 'a', userId: 'bob', name: 'A'),
          const TrailDetails(trailId: 'b', userId: 'bob', name: 'B'),
        ],
        myId: 'me',
        reports: [
          // a: unbestätigt „gesperrt", jünger als das bestätigte „offen".
          rep('a', status: TrailStatus.open, confirmed: true, day: 1),
          rep('a', status: TrailStatus.closed, confirmed: false, day: 2),
          // b: unbestätigt ÄLTER als bestätigt — überholt, keine Frage.
          rep('b', status: TrailStatus.closed, confirmed: false, day: 1),
          rep('b', status: TrailStatus.open, confirmed: true, day: 2),
          // c: nur bestätigt.
          rep('c', status: TrailStatus.closed, confirmed: true, day: 1),
          // d: unbestätigter Zustand.
          rep('d', condition: 2, confirmed: false, day: 3),
        ],
      );
      final targets = {for (final t in confirmTargetsOf(trails)) t.trailId: t};
      expect(targets.keys.toSet(), {'a', 'd'});
      expect(targets['a']!.status, TrailStatus.closed);
      expect(targets['a']!.condition, isNull);
      expect(targets['a']!.name, 'A');
      expect(targets['d']!.status, isNull);
      expect(targets['d']!.condition, 2);
    });

    test('die Datei hält Konto und Werte, ein fremdes Konto liest nichts', () {
      final text = encodeConfirmTargets(uid: 'me', targets: [target(condition: 3)]);
      final back = decodeConfirmTargets(text, uid: 'me').single;
      expect(back.trailId, 't1');
      expect(back.name, 'Hexenkessel');
      expect(back.status, TrailStatus.closed);
      expect(back.condition, 3);
      expect(back.line, hasLength(3));
      expect(back.line[1].latitude, closeTo(northLine()[1].latitude, 1e-9));
      expect(decodeConfirmTargets(text, uid: 'someone'), isEmpty);
      expect(decodeConfirmTargets('{kaputt', uid: 'me'), isEmpty);
    });
  });

  group('wann gefragt wird', () {
    ConfirmTarget? ask(RidePoint? prev, RidePoint cur, {List<ConfirmTarget>? targets, Set<String> asked = const {}}) =>
        confirmPromptFor(targets: targets ?? [target()], previous: prev, current: cur, asked: asked);

    test('zwei scharfe Fixe AUF der Linie, in Fahrtrichtung', () {
      expect(ask(fix(100, eastM: 8), fix(140, eastM: -6, s: 5))?.trailId, 't1');
    });

    test('wer quert, wird nicht gefragt', () {
      // Einer auf der Linie, einer 30 m daneben.
      expect(ask(fix(300, eastM: -30), fix(300, eastM: 2, s: 5)), isNull);
      expect(ask(fix(300, eastM: 2), fix(300, eastM: 30, s: 5)), isNull);
    });

    test('wer steht, wird nicht gefragt (weniger als 25 m zwischen den Fixen)', () {
      expect(ask(fix(100), fix(120, s: 5)), isNull);
    });

    test('unscharfe Fixe zählen nicht, ohne Vorgänger auch nicht', () {
      expect(ask(fix(100, acc: 40), fix(140, s: 5)), isNull);
      expect(ask(fix(100), fix(140, acc: 31, s: 5)), isNull);
      expect(ask(null, fix(140)), isNull);
    });

    test('je Trail und Fahrt einmal; liegen zwei im Korridor, der nähere', () {
      expect(ask(fix(100), fix(140, s: 5), asked: {'t1'}), isNull);
      final near = target(id: 'near', lng: 11.4 + 5 / (mPerDegLat * 0.679));
      final far = target(id: 'far', lng: 11.4 - 15 / (mPerDegLat * 0.679));
      expect(ask(fix(100), fix(140, eastM: 3, s: 5), targets: [far, near])?.trailId, 'near');
    });
  });

  group('was die Benachrichtigung sagt', () {
    test('gesperrt mit Zustand: drei Knöpfe, der Name ist der Titel', () {
      final n = confirmNoticeOf(l10nDe, target(condition: 2));
      expect(n.title, 'Hexenkessel');
      expect(n.body, 'Gemeldet: gesperrt · Zustand: Abgerockt — stimmt das?');
      expect(n.actions.map((a) => a.$2), ['Stimmt', 'Trail ist frei', 'Ändern…']);
    });

    test('„wieder frei" braucht kein „Trail ist frei"; Zustand allein auch nicht', () {
      final open = confirmNoticeOf(l10nDe, target(status: TrailStatus.open));
      expect(open.body, 'Wieder frei gemeldet — stimmt das?');
      expect(open.actions.map((a) => a.$1), [ConfirmChoice.confirm, ConfirmChoice.change]);
      final cond = confirmNoticeOf(l10nDe, target(status: null, condition: 5));
      expect(cond.body, 'Zustand: Top gepflegt — stimmt das?');
      expect(cond.actions.map((a) => a.$1), [ConfirmChoice.confirm, ConfirmChoice.change]);
    });
  });

  group('was hinausgeht', () {
    final asked = ConfirmAsked.of(target(condition: 2), at: t0);
    ConfirmAnswered answer(ConfirmChoice c, int min, {String id = 't1'}) =>
        ConfirmAnswered(trailId: id, at: t0.add(Duration(minutes: min)), choice: c);

    test('„Stimmt" bestätigt beides mit der Zeit der Antwort', () {
      final r = confirmReportsOf([asked, answer(ConfirmChoice.confirm, 2)]).single;
      expect(r.trailId, 't1');
      expect(r.status, TrailStatus.closed);
      expect(r.condition, 2);
      expect(r.at, t0.add(const Duration(minutes: 2)));
    });

    test('„Trail ist frei" meldet offen und lässt den Zustand offen', () {
      final r = confirmReportsOf([asked, answer(ConfirmChoice.free, 1)]).single;
      expect(r.status, TrailStatus.open);
      expect(r.condition, isNull);
    });

    test('„Ändern…", keine Antwort und eine Antwort ohne Frage schreiben nichts', () {
      expect(confirmReportsOf([asked, answer(ConfirmChoice.change, 1)]), isEmpty);
      expect(confirmReportsOf([asked]), isEmpty);
      expect(confirmReportsOf([answer(ConfirmChoice.confirm, 1, id: 'fremd')]), isEmpty);
    });

    test('die letzte Antwort gilt', () {
      final r = confirmReportsOf(
          [asked, answer(ConfirmChoice.free, 1), answer(ConfirmChoice.confirm, 3)]).single;
      expect(r.status, TrailStatus.closed);
    });
  });

  group('Datei und Antwortweg', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('ride_confirm_'));
    tearDown(() async => dir.delete(recursive: true));

    test('Fragen und Antworten stehen in der Fahrt und überstehen das Beenden', () async {
      final store = FileRideStore(baseDir: dir);
      await store.begin(uid: 'me', startedAt: t0);
      await store.appendPoint(fix(0));
      expect(await store.appendConfirmEvent(ConfirmAsked.of(target(), at: t0)), isTrue);
      await store.appendPoint(fix(40, s: 5));
      expect(
          await store.appendConfirmEvent(
              ConfirmAnswered(trailId: 't1', at: t0, choice: ConfirmChoice.confirm),
              rideStartedAt: t0),
          isTrue);
      final events = await FileRideStore(baseDir: dir).activeConfirmEvents(uid: 'me');
      expect(events, hasLength(2));
      expect((await store.readActive(uid: 'me'))!.points, hasLength(2),
          reason: 'eine Frage ist kein Messpunkt');
      final ride = await store.finish(uid: 'me', endedAt: t0.add(const Duration(minutes: 5)));
      expect(ride!.events.map((e) => e.runtimeType), [ConfirmAsked, ConfirmAnswered]);
      expect((await store.list(uid: 'me')).single.events, hasLength(2));
    });

    test('eine späte Antwort landet nie in einer anderen Fahrt', () async {
      final store = FileRideStore(baseDir: dir);
      await store.begin(uid: 'me', startedAt: t0.add(const Duration(hours: 2)));
      expect(
          await store.appendConfirmEvent(
              ConfirmAnswered(trailId: 't1', at: t0, choice: ConfirmChoice.confirm),
              rideStartedAt: t0),
          isFalse);
      expect(await store.activeConfirmEvents(uid: 'me'), isEmpty);
    });

    test('der Knopf schreibt die Antwort, der Tipp nur das Ziel', () async {
      final store = FileRideStore(baseDir: dir);
      await store.begin(uid: 'me', startedAt: t0);
      final payload = encodeConfirmPayload((dir: dir.path, uid: 'me', rideStartedAt: t0, trailId: 't1'));
      expect(decodeConfirmPayload(payload)?.trailId, 't1');
      expect(await handleConfirmResponse(actionId: null, payload: payload), 't1');
      expect(await store.activeConfirmEvents(uid: 'me'), isEmpty);
      expect(await handleConfirmResponse(actionId: 'free', payload: payload, now: t0), 't1');
      final answer = (await store.activeConfirmEvents(uid: 'me')).single as ConfirmAnswered;
      expect(answer.choice, ConfirmChoice.free);
      expect(await handleConfirmResponse(actionId: 'free', payload: 'kaputt'), isNull);
    });

    test('die Ziel-Liste überlebt den Weg über die Platte, gilt nur für ihr Konto', () async {
      final store = FileRideStore(baseDir: dir);
      await store.writeConfirmTargets(uid: 'me', targets: [target()]);
      expect((await FileRideStore(baseDir: dir).readConfirmTargets(uid: 'me')).single.trailId, 't1');
      expect(await store.readConfirmTargets(uid: 'other'), isEmpty);
      expect(await store.confirmTargetsModified(), isNotNull);
    });

    test('die Kennung der Benachrichtigung ist fest und positiv', () {
      final id = confirmNotificationId('0f8fad5b-d9cb-469f-a165-70867728950e');
      expect(id, confirmNotificationId('0f8fad5b-d9cb-469f-a165-70867728950e'));
      expect(id, greaterThanOrEqualTo(0));
      expect(id, isNot(confirmNotificationId('0f8fad5b-d9cb-469f-a165-70867728950f')));
    });
  });

  group('der Wächter im Service', () {
    test('fragt einmal, merkt es sich in der Fahrt — auch über einen Neustart', () async {
      final store = FakeRideStore();
      await store.begin(uid: 'me', startedAt: t0);
      await store.writeConfirmTargets(uid: 'me', targets: [target()]);
      final shown = <(String, String)>[];
      Future<void> notify(ConfirmTarget t, {required String payload}) async =>
          shown.add((t.trailId, payload));

      var watcher = RideConfirmWatcher(uid: 'me', rideStartedAt: t0, dir: '/d');
      await watcher.onPoint(fix(100), store: store, notify: notify);
      expect(shown, isEmpty, reason: 'ein Fix allein fragt nicht');
      await watcher.onPoint(fix(140, s: 5), store: store, notify: notify);
      await watcher.onPoint(fix(180, s: 10), store: store, notify: notify);
      expect(shown, hasLength(1));
      expect(decodeConfirmPayload(shown.single.$2)?.rideStartedAt, t0);
      expect(store.events.single, isA<ConfirmAsked>());

      // Das Isolate startet neu: Der neue Wächter liest die Frage aus der
      // Datei und fragt nicht noch einmal.
      watcher = RideConfirmWatcher(uid: 'me', rideStartedAt: t0, dir: '/d');
      await watcher.onPoint(fix(300, s: 15), store: store, notify: notify);
      await watcher.onPoint(fix(340, s: 20), store: store, notify: notify);
      expect(shown, hasLength(1));
    });

    test('ohne Ziele wird nichts gelesen und nichts gefragt', () async {
      final store = FakeRideStore();
      await store.begin(uid: 'me', startedAt: t0);
      var calls = 0;
      final watcher = RideConfirmWatcher(uid: 'me', rideStartedAt: t0, dir: '/d');
      for (var i = 0; i < 4; i++) {
        await watcher.onPoint(fix(100.0 + 40 * i, s: 5 * i), store: store,
            notify: (t, {required payload}) async => calls++);
      }
      expect(calls, 0);
      expect(store.events, isEmpty);
    });
  });

  group('Frage im Zerlege-Blatt', () {
    Trail trailWith(List<TrailReport> reports) => buildTrails(
          recordings: [
            TrailRecording(
                id: 'r', trailId: 't', userId: 'bob', source: RecordingSource.import,
                recordedAt: null, reversed: false, quality: 0.4, createdAt: DateTime.utc(2026),
                points: northLine(), lengthM: 1000),
          ],
          details: const [],
          myId: 'me',
          reports: reports,
        ).single;
    TrailReport unconfirmed(DateTime at, {TrailStatus? status, int? condition}) => TrailReport(
        id: 'u-$at-$condition', trailId: 't', userId: 'bob',
        kind: status != null ? ReportKind.status : ReportKind.condition,
        status: status, condition: condition, confirmed: false, reportedAt: at);

    test('nur, was VOR der Fahrt gemeldet war — und nur mit Zeit', () {
      final t = trailWith([
        unconfirmed(t0.subtract(const Duration(days: 1)), status: TrailStatus.closed),
        unconfirmed(t0.add(const Duration(hours: 1)), condition: 2),
      ]);
      final q = splitQuestionFor(t, t0)!;
      expect(q.status, TrailStatus.closed);
      expect(q.condition, isNull, reason: 'der Zustand kam nach der Fahrt');
      expect(splitQuestionFor(t, null), isNull, reason: 'ohne Zeit war niemand nachweislich dort');
      expect(splitQuestionFor(t, t0.subtract(const Duration(days: 2))), isNull);
    });
  });
}
