// Der Stand der Uhr auf dem Handy (#499): verbunden, und ob sie aufnimmt.
// Die Uhr sagt es selbst (`rs`, `rp`, `rr`, `re`); kein Netz, keine echte Uhr.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/garmin/garmin_bridge.dart';
import 'package:trailbuddy/features/garmin/watch_presence.dart';

import '../fakes/fake_garmin.dart';

void main() {
  late FakeGarminBridge bridge;
  late ProviderContainer container;

  ProviderContainer make() {
    final c = ProviderContainer(overrides: [garminBridgeProvider.overrideWithValue(bridge)]);
    addTearDown(c.dispose);
    return c;
  }

  /// Eine Nachricht der Uhr, dann der Stand lesen. Der Hörer entsteht erst
  /// mit dem ersten Lesen des Standes — vorher fällt eine Nachricht ins Leere.
  WatchPresence ask() => container.read(watchPresenceProvider);

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    bridge = FakeGarminBridge();
    container = make();
    ask();
  });

  test('keine Uhr, kein Stand', () async {
    await settle();
    expect(ask(), WatchPresence.none);
    expect(ask().shows, isFalse);
  });

  test('eine verbundene Uhr steht da, auch ohne Sendung', () async {
    bridge = FakeGarminBridge.connected();
    container = make();
    ask();
    expect(ask().shows, isFalse, reason: 'die erste Frage ans SDK läuft noch');
    await settle();
    expect(ask().connected, isTrue);
    expect(ask().record, WatchRecord.idle);
    // Garmin Connect meldet die Uhr später erneut: derselbe Stand.
    bridge.reconnect();
    await settle();
    expect(ask().connected, isTrue);
  });

  test('START, Pause, Weiter, Speichern — der Stand folgt der Uhr', () async {
    bridge = FakeGarminBridge.connected();
    container = make();
    ask();
    await settle();
    bridge.answer({'t': 'rs'});
    await settle();
    expect(ask().record, WatchRecord.running);
    bridge.answer({'t': 'rp'});
    await settle();
    expect(ask().record, WatchRecord.paused);
    bridge.answer({'t': 'rr'});
    await settle();
    expect(ask().record, WatchRecord.running);
    // Ein behaltener Trail gehört zur Aufzeichnung, ändert den Stand nicht.
    bridge.answer({'t': 'rt', 's': 1700000005, 'e': 1700000010});
    await settle();
    expect(ask().record, WatchRecord.running);
    bridge.answer({'t': 're', 'k': true});
    await settle();
    expect(ask().record, WatchRecord.idle);
    expect(ask().connected, isTrue);
  });

  test('was die Uhr sendet, sagt: sie ist da', () async {
    bridge = FakeGarminBridge(status_: WatchStatus.none);
    container = make();
    ask();
    await settle();
    expect(ask().shows, isFalse);
    bridge.answer({'t': 'hi', 'v': 2});
    await settle();
    expect(ask().connected, isTrue);
    bridge.answer({'t': 'w', 'id': '17', 'p': 0, 'n': 1, 'c': []});
    await settle();
    expect(ask().record, WatchRecord.idle);
  });

  test('die Uhr meldet ihren ersten eigenen Fix (#500)', () async {
    bridge = FakeGarminBridge.connected();
    container = make();
    ask();
    await settle();
    bridge.answer({'t': 'g', 'la': 4712346, 'lo': 1150000});
    await settle();
    expect(ask().watchFix, const LatLng(47.12346, 11.5), reason: 'die Uhr sendet 1e-5 Grad');
    expect(ask().record, WatchRecord.idle, reason: '„habe GPS" ist keine Aufzeichnung');
    // Eine alte Uhr-App sendet keine Zahlen: der Stand bleibt, wie er ist.
    bridge.answer({'t': 'rs'});
    bridge.answer({'t': 'g'});
    await settle();
    expect(ask().watchFix, const LatLng(47.12346, 11.5));
    expect(ask().record, WatchRecord.running);
  });

  test('die Uhr meldet ihren Stand, wenn sie abseits fährt (#500)', () async {
    bridge = FakeGarminBridge.connected();
    container = make();
    ask();
    await settle();
    bridge.answer({'t': 'g', 'la': 4712346, 'lo': 1150000});
    await settle();
    expect(ask().watchOffM, isNull, reason: 'der erste Fix ist keine Drift');
    bridge.answer({'t': 'd', 'la': 4713000, 'lo': 1151000, 'off': 620});
    await settle();
    expect(ask().watchFix, const LatLng(47.13, 11.51));
    expect(ask().watchOffM, 620.0);
    expect(ask().record, WatchRecord.idle, reason: 'ein Stand ist keine Aufzeichnung');
    // Ohne Abstand ist die Meldung unlesbar und fällt weg.
    bridge.answer({'t': 'd', 'la': 4713000, 'lo': 1151000});
    await settle();
    expect(ask().watchOffM, 620.0);
  });

  test('eine Plattform ohne Uhr fragt niemand', () {
    bridge = FakeGarminBridge()..unsupported = true;
    container = make();
    expect(ask(), WatchPresence.none);
  });
}
