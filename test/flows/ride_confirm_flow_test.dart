// Bestätigen durch Fahren (#116): Beim Start der Fahrt legt die App die
// Trails mit unbestätigter Meldung für den Service ab; die Antworten
// unterwegs gehen beim Beenden als BESTÄTIGTE Meldungen hinaus — mit der
// Zeit der Antwort, ohne Netz über den Ausgangskorb.
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/data/outbox.dart';
import 'package:trailbuddy/features/rides/ride_confirm.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_outbox.dart';
import '../fakes/fake_rides.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

const _portName = 'flutter_foreground_task/isolateComPort';

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late String annaId;
  late String bobId;
  late String roots;
  late FakeRideStore store;
  late FakeRideFix fix;

  final t0 = DateTime.utc(2026, 9, 30, 10);

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    final bob = backend.addUser(username: 'bob');
    backend.addFriendship(anna.id, bob.id);
    backend.signInAs(anna.id);
    annaId = anna.id;
    bobId = bob.id;
    trails = FakeTrailRepository(
      myId: () => backend.currentUserId ?? '',
      areFriends: backend.areFriends,
    );
    trails.usernames[bob.id] = 'bob';
    // Bob ist Roots gefahren; seine Meldung „gesperrt" kam von zu Hause,
    // unbestätigt. Bobs Flow trägt nur Bestätigtes — dazu wird nie gefragt.
    roots = trails.seedTrail(bob.id, name: 'Roots');
    trails.seedReport(
      bob.id,
      roots,
      status: TrailStatus.closed,
      confirmed: false,
      at: DateTime.utc(2026, 9, 29),
    );
    trails.seedTrail(
      bob.id,
      name: 'Bobs Flow',
      lat: 48.1,
      status: TrailStatus.closed,
    );
    store = FakeRideStore();
    fix = FakeRideFix()
      ..next = RidePoint(lat: 47.2, lng: 11.4, at: t0, accuracyM: 5);
  });

  tearDown(() => IsolateNameServer.removePortNameMapping(_portName));

  Future<void> pump(WidgetTester tester, {FakeOutbox? outbox}) => pumpApp(
    tester,
    backend,
    trails: trails,
    rideStore: store,
    rideFix: fix,
    rideBridge: FakeRideServiceBridge(),
    rideService: FakeRideService(),
    outbox: outbox,
  );

  final button = find.byKey(const ValueKey('ride-button'));

  /// Der Service hat gefragt, Anna hat geantwortet — so stünde es in der
  /// Fahrt-Datei.
  void answered(
    ConfirmChoice choice, {
    Duration after = const Duration(minutes: 12),
  }) {
    final target = store.targets.singleWhere((t) => t.trailId == roots);
    store.events
      ..add(
        ConfirmAsked.of(target, at: t0.add(after - const Duration(minutes: 1))),
      )
      ..add(ConfirmAnswered(trailId: roots, at: t0.add(after), choice: choice));
  }

  Future<void> startAndStop(
    WidgetTester tester,
    void Function() whileRiding,
  ) async {
    await tester.tap(button);
    await settle(tester);
    whileRiding();
    await drainSnackbars(tester);
    await tester.tap(button);
    await settle(tester);
  }

  testWidgets(
    'die App legt NUR die unbestätigten Trails ab — samt Name und Wert',
    (tester) async {
      await pump(tester);
      await tester.tap(button);
      await settle(tester);
      expect(store.targetsUid, annaId);
      final target = store.targets.single;
      expect(target.trailId, roots);
      expect(target.name, 'Roots');
      expect(target.status, TrailStatus.closed);
      expect(target.line, hasLength(3));
    },
  );

  testWidgets(
    '„Stimmt" wird beim Beenden eine BESTÄTIGTE Meldung von Anna, zur Zeit der Antwort',
    (tester) async {
      await pump(tester);
      await startAndStop(tester, () => answered(ConfirmChoice.confirm));
      final mine = trails.reports.where((r) => r.userId == annaId).single;
      expect(mine.trailId, roots);
      expect(mine.status, TrailStatus.closed);
      expect(
        mine.confirmed,
        isTrue,
        reason: 'vor Ort: der Dienst sah sie auf der Linie',
      );
      expect(mine.reportedAt.toUtc(), t0.add(const Duration(minutes: 12)));
      expect(
        store.targets,
        isEmpty,
        reason: 'beim Beenden geleert — die nächste Fahrt erbt nichts',
      );
      // Bobs unbestätigte Meldung ist damit überholt: angezeigt wird Annas.
      expect(
        trails.reports.where((r) => r.userId == bobId && r.trailId == roots),
        hasLength(1),
      );
    },
  );

  testWidgets(
    '„Trail ist frei" meldet offen — und danach gibt es zu dem Trail nichts mehr zu fragen',
    (tester) async {
      await pump(tester);
      await startAndStop(tester, () => answered(ConfirmChoice.free));
      final mine = trails.reports.where((r) => r.userId == annaId).single;
      expect(mine.status, TrailStatus.open);
      expect(mine.confirmed, isTrue);
      // Bobs unbestätigtes „gesperrt" ist jetzt überholt (älter als Annas
      // bestätigte Meldung): Die nächste Fahrt fragt dazu nicht mehr. Ein
      // Fix allein ist keine Fahrt, also kam kein Blatt dazwischen.
      await drainSnackbars(tester);
      await tester.tap(button);
      await settle(tester);
      expect(store.targets, isEmpty);
    },
  );

  testWidgets('„Ändern…" und keine Antwort schreiben nichts', (tester) async {
    await pump(tester);
    await startAndStop(tester, () => answered(ConfirmChoice.change));
    await drainSnackbars(tester);
    await startAndStop(tester, () {});
    expect(trails.reportCalls, 0);
    expect(trails.reports.where((r) => r.userId == annaId), isEmpty);
  });

  testWidgets(
    'ohne Netz wartet die Bestätigung im Ausgangskorb, mit der Zeit der Antwort',
    (tester) async {
      final outbox = FakeOutbox();
      await pump(tester, outbox: outbox);
      trails.failNextReport = const SocketException('Funkloch');
      await startAndStop(tester, () => answered(ConfirmChoice.confirm));
      final job = outbox.jobs.whereType<ReportJob>().single;
      expect(job.trailId, roots);
      expect(job.status, TrailStatus.closed);
      expect(job.onSite, isTrue);
      expect(job.createdAt, t0.add(const Duration(minutes: 12)));
    },
  );
}
