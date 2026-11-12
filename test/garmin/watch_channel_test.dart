// Die Feldbefunde der Uhr gegen den gemessenen Kanal (#509, Prüfleiter S3,
// T3): Laufzeit je Nachricht, eine geschlossene Uhr-App, Verlust und Abbruch
// (`WatchChannel` in test/fakes/fake_garmin.dart). Jeder Test stellt einen
// Befund aus `docs/konzept-garmin.md` 8 nach; `docs/watch_cases.json` nennt
// ihn unter 509.2–509.6. Die Uhr-App ist hier die einfache am Kanal: Sie
// sagt `ok`, sobald eine Route ganz angekommen ist (`autoStore`).
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/garmin/watch_branches.dart' show WatchBranch;
import 'package:trailbuddy/features/garmin/watch_providers.dart';
import 'package:trailbuddy/features/garmin/watch_ride_inbox.dart' show kWatchRecordCheck;
import 'package:trailbuddy/features/rides/ride_providers.dart' show rideProvider;

import '../fakes/fake_garmin.dart';
import 'watch_phone.dart';

/// Das Handy am Kanal, mit einer Uhr der Zeit, die mit dem Test läuft.
class _Bench {
  _Bench(this.tester, {bool appOpen = true, Future<List<WatchBranch>> Function(List<LatLng>)? branches}) {
    channel = WatchChannel(appOpen: appOpen);
    bridge = FakeGarminBridge.connected(channel: channel, now: () => _t0.add(elapsed))..autoStore = true;
    phone = WatchPhone(bridge: bridge, branches: branches);
  }

  final WidgetTester tester;
  late final WatchChannel channel;
  late final FakeGarminBridge bridge;
  late final WatchPhone phone;
  static final _t0 = DateTime.utc(2026, 11, 12);
  Duration elapsed = Duration.zero;

  /// Die Zeit des Tests seit dem Aufbau.
  DateTime get now => _t0.add(elapsed);

  /// [d] in Schritten zu 100 ms — die Ankunftszeiten in
  /// [FakeGarminBridge.delivered] stimmen so auf 100 ms.
  Future<void> run(Duration d) async {
    const step = Duration(milliseconds: 100);
    for (var t = Duration.zero; t < d; t += step) {
      elapsed += step;
      await tester.pump(step);
    }
  }

  /// Laufen lassen, bis [done] gilt, höchstens [limit].
  Future<bool> until(bool Function() done, {Duration limit = const Duration(minutes: 3)}) async {
    final end = elapsed + limit;
    while (!done() && elapsed < end) {
      await run(const Duration(milliseconds: 500));
    }
    return done();
  }

  WatchSyncState get sync => phone.sync;

  /// Die Stücke der Route [id], die die Uhr-App erreichten (`p`).
  List<int> partsDelivered(String id) =>
      [for (final d in bridge.delivered) if (d.msg['t'] == 'r' && d.msg['id'] == id) d.msg['p'] as int];

  Future<void> close() async {
    phone.c.dispose();
    await run(const Duration(minutes: 3));
  }
}

void main() {
  testWidgets('8.2 die geschlossene App schluckt die Route, nur ok zählt', (tester) async {
    final b = _Bench(tester, appOpen: false);
    await b.phone.open();
    b.phone.navigate();
    // Garmin Connect nimmt alles mit SUCCESS ab — angekommen ist nichts.
    expect(await b.until(() => b.sync.phase == WatchSyncPhase.sent), isTrue, reason: 'die Route ging nicht hinaus');
    final id = b.sync.routeId!;
    expect(b.bridge.delivered, isEmpty);
    expect(b.partsDelivered(id), isEmpty);
    // Ohne `ok` gilt sie nicht als gespeichert: Das Handy wartet und fragt nach.
    await b.run(kWatchAckWait + const Duration(seconds: 1));
    expect(b.sync.phase, WatchSyncPhase.unconfirmed);
    final queries = b.bridge.queries;
    await b.run(kWatchNudges.first + const Duration(seconds: 1));
    expect(b.bridge.queries, greaterThan(queries), reason: 'kein Nachfragen nach der verfallenen Route');
    // Die App geht auf und meldet sich ohne Route: Jetzt kommt sie an.
    b.channel.appOpen = true;
    b.bridge.fromWatch({'t': 'hi', 'v': 2, 'ver': '1.3.0'});
    expect(await b.until(() => b.sync.phase == WatchSyncPhase.stored), isTrue, reason: 'nach dem hallo nie gespeichert');
    expect(b.partsDelivered(id), isNotEmpty);
    await b.close();
  });

  testWidgets('8.8 die Antwort auf hallo kommt nach den 8 s, die Runde kommt trotzdem an', (tester) async {
    // Das Handy rechnet noch (die Abzweigungen brauchen 12 s), als die Uhr-App
    // startet und „hallo" sagt — die Uhr wartet darauf 8 s (ANSWER_MS).
    final b = _Bench(tester, branches: (line) async {
      await Future<void>.delayed(const Duration(seconds: 12));
      return const <WatchBranch>[];
    });
    await b.phone.open();
    b.phone.navigate();
    await b.run(const Duration(milliseconds: 500));
    final hiSent = b.now;
    b.bridge.fromWatch({'t': 'hi', 'v': 2, 'ver': '1.3.0'});
    // Innerhalb der 8 s hört die Uhr „es kommt eine" (`n`) — hin und zurück
    // je 3,5 s.
    await b.run(const Duration(seconds: 8));
    final first = b.bridge.delivered.firstOrNull;
    expect(first?.msg['t'], 'n', reason: 'in den 8 s der Uhr kam keine Antwort');
    expect(first!.at.difference(hiSent), lessThan(const Duration(seconds: 8)));
    // Die Runde kommt trotzdem an.
    expect(await b.until(() => b.sync.phase == WatchSyncPhase.stored), isTrue, reason: 'die Runde kam nie an');
    expect(b.partsDelivered(b.sync.routeId!), isNotEmpty);
    await b.close();
  });

  testWidgets('8.7 rs kommt an, kein Fix in 45 s, die Aufzeichnung wird zurückgenommen', (tester) async {
    final b = _Bench(tester);
    await b.phone.open();
    // Im Hintergrund startet Android den Dienst mit Standort nicht: kein Fix.
    b.phone.fix.next = null;
    b.bridge.fromWatch({'t': 'rs'});
    await b.run(const Duration(seconds: 5));
    expect(b.phone.c.read(rideProvider), isNotNull, reason: 'rs startete die Aufzeichnung nicht');
    await b.run(kWatchRecordCheck);
    expect(b.phone.c.read(rideProvider), isNull, reason: 'die Aufzeichnung ohne Punkt blieb stehen');
    await b.close();
  });

  testWidgets('ein Abbruch mitten in den Stücken schickt nur den Rest', (tester) async {
    final b = _Bench(tester);
    b.channel.failRouteAfter = 1;
    await b.phone.open();
    b.phone.navigate(route: longPhoneRoute());
    expect(await b.until(() => b.sync.phase == WatchSyncPhase.stored), isTrue, reason: 'nach dem Abbruch nie gespeichert');
    final id = b.sync.routeId!;
    final n = b.bridge.routeParts.firstWhere((m) => m['id'] == id)['n'] as int;
    expect(n, greaterThan(1), reason: 'die Route braucht zwei Stücke, sonst bricht nichts mittendrin ab');
    // Jedes Stück genau einmal: Das erste ging vor dem Abbruch durch.
    expect(b.partsDelivered(id), [for (var p = 0; p < n; p++) p]);
    await b.close();
  });

  testWidgets('ein verlorenes Stück holt das Nachfragen nach', (tester) async {
    final b = _Bench(tester);
    // Nachricht 0 ist die Ankündigung `n`, 1 und 2 die beiden Stücke.
    b.channel.lose.add(2);
    await b.phone.open();
    b.phone.navigate(route: longPhoneRoute());
    expect(await b.until(() => b.sync.phase == WatchSyncPhase.unconfirmed), isTrue);
    // Die Uhr hat nur einen Teil — auf das `q` sagt sie „hallo" ohne Route.
    expect(await b.until(() => b.bridge.queries > 0), isTrue, reason: 'kein Nachfragen');
    b.bridge.fromWatch({'t': 'hi', 'v': 2, 'ver': '1.3.0'});
    expect(await b.until(() => b.sync.phase == WatchSyncPhase.stored), isTrue, reason: 'das hallo holte sie nicht');
    final id = b.sync.routeId!;
    expect(b.partsDelivered(id).toSet(), containsAll([0, 1]));
    await b.close();
  });

  testWidgets('ein spätes ok der alten Route zählt nicht für die neue', (tester) async {
    final b = _Bench(tester)..bridge.autoStore = false;
    await b.phone.open();
    b.phone.navigate();
    expect(await b.until(() => b.sync.phase == WatchSyncPhase.sent), isTrue);
    final old = b.sync.routeId!;
    // Eine andere Route (Runde neu geplant), dann kommt das `ok` der alten.
    b.phone.endNavigation();
    b.phone.navigate(route: [phoneM(0, 0), phoneM(60, 400), phoneM(0, 900), phoneM(60, 1300), phoneM(0, 1800)]);
    expect(await b.until(() => b.sync.routeId != old && b.sync.phase == WatchSyncPhase.sent), isTrue);
    b.bridge.fromWatch({'t': 'ok', 'id': old});
    await b.run(const Duration(seconds: 5));
    expect(b.sync.phase, isNot(WatchSyncPhase.stored), reason: 'das ok der alten Route galt für die neue');
    await b.close();
  });
}
