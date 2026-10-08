// Die Kopie des Netzes im Browser (#153), auf der VM mit der
// Speicher-Fassung von idb_shim; den echten Speicher fährt
// `test/web/outbox_trail_cache_browser_test.dart`.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/data/browser_db.dart';
import 'package:trailbuddy/data/trail_cache.dart';
import 'package:trailbuddy/data/trail_cache_idb.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/broken_idb_factory.dart';

void main() {
  final at = DateTime.utc(2026, 10, 8, 10);
  final recording = TrailRecording(
    id: 'rec-1', trailId: 'trail-1', userId: 'me', source: RecordingSource.app,
    recordedAt: null, reversed: false, quality: 0.6, createdAt: at.toLocal(),
    points: const [LatLng(47.0, 11.0), LatLng(47.001, 11.001), LatLng(47.002, 11.0)],
    lengthM: 250.5, ele: const [900, 890, 880],
  );
  final details = TrailDetails(
    trailId: 'trail-1', userId: 'me', name: 'Roots', grade: 3, traits: const {TrailTrait.rocky},
    updatedAt: at.toLocal(),
  );
  final TrailSnapshot snapshot = (recordings: [recording], details: [details], notes: const [], reports: const []);

  test('schreiben, in neuer Sitzung lesen, nur fürs eigene Konto, löschen', () async {
    final factory = newIdbFactoryMemory();
    final cache = IdbTrailCache(BrowserDb(factory));
    expect(await cache.read(uid: 'me'), isNull);
    await cache.write(uid: 'me', snapshot: snapshot, savedAt: at);

    final again = IdbTrailCache(BrowserDb(factory));
    final back = await again.read(uid: 'me');
    expect(back!.savedAt, at.toLocal());
    expect(back.snapshot.recordings.single.points, recording.points);
    expect(back.snapshot.recordings.single.ele, recording.ele);
    expect(back.snapshot.details.single.name, 'Roots');
    expect(await again.read(uid: 'someone'), isNull, reason: 'ein fremdes Netz taucht nie in einer anderen Sitzung auf');

    await again.clear();
    expect(await cache.read(uid: 'me'), isNull);
  });

  test('abgelegt wird derselbe JSON-Text wie in der Datei', () async {
    final db = BrowserDb(newIdbFactoryMemory());
    await IdbTrailCache(db).write(uid: 'me', snapshot: snapshot, savedAt: at);
    expect(await db.readStore(kTrailCacheStore, (s) => s.getObject('network')),
        encodeTrailCache(uid: 'me', snapshot: snapshot, savedAt: at));
  });

  test('nacheinander: ein Löschen beim Abmelden gewinnt gegen ein laufendes Schreiben', () async {
    final cache = IdbTrailCache(BrowserDb(newIdbFactoryMemory()));
    unawaited(cache.write(uid: 'me', snapshot: snapshot, savedAt: at));
    await cache.clear();
    expect(await cache.read(uid: 'me'), isNull);
  });

  test('eine Kopie wirft nie — auch wenn kein IndexedDB da ist', () async {
    final broken = IdbTrailCache(BrowserDb(BrokenIdbFactory()));
    await expectLater(broken.write(uid: 'me', snapshot: snapshot, savedAt: at), completes);
    await expectLater(broken.read(uid: 'me'), completion(isNull));
    await expectLater(broken.clear(), completes);
  });

  group('Welche Kopie zu welcher Plattform gehört', () {
    test('Android: die Datei', () {
      expect(chooseTrailCache(web: false, factory: newIdbFactoryMemory()), isA<FileTrailCache>());
    });

    test('Browser mit IndexedDB: dort', () {
      expect(chooseTrailCache(web: true, factory: newIdbFactoryMemory()), isA<IdbTrailCache>());
    });

    test('Browser ohne IndexedDB: keine, nie die vergessliche Speicher-Fassung', () {
      expect(chooseTrailCache(web: true, factory: null), isA<NoTrailCache>());
    });
  });
}
