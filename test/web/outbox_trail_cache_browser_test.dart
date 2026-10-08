// Ausgangskorb und Kopie des Netzes (#153) in einer ECHTEN IndexedDB —
// läuft nur mit `flutter test --platform chrome` (CI: Schritt „Web-Test
// auf dart2js"). Die Speicher-Fassung von idb_shim gibt Werte anders
// zurück als der Browser (PilzBuddy #385); die Logik prüfen
// `test/outbox/outbox_idb_test.dart` und `test/trails/trail_cache_idb_test.dart`.
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/data/browser_db.dart';
import 'package:trailbuddy/data/browser_storage.dart';
import 'package:trailbuddy/data/outbox.dart';
import 'package:trailbuddy/data/outbox_idb.dart';
import 'package:trailbuddy/data/trail_cache_idb.dart';
import 'package:trailbuddy/features/map/seen_tiles.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/trail.dart';

void main() {
  final at = DateTime.utc(2026, 10, 8, 12);

  test('der Zugang ist das ECHTE IndexedDB, nie die vergessliche Speicher-Fassung', () {
    // Ein grüner Lauf allein bewiese nichts — fiele der Zugang still auf
    // den Speicher zurück, sähe er genauso aus.
    final factory = browserIdbFactory();
    expect(factory, isNotNull);
    expect(factory!.persistent, isTrue);
  });

  test('die Abfrage der Zusicherung antwortet im Browser, ohne zu werfen', () async {
    // Die Antwort selbst hängt vom Browser ab und wird nicht behauptet.
    expect(await isStorageDurable(), isA<bool>());
  });

  test('der Korb übersteht eine neue Sitzung', () async {
    final factory = browserIdbFactory()!;
    final job = ContributeJob(
      id: 'job-1',
      createdAt: at,
      coords: const [11.0, 47.0, 11.001, 47.001],
      eles: const [900, 890],
      source: RecordingSource.app,
      name: 'Wurzeltrail',
    );
    await IdbOutbox(BrowserDb(factory)).replaceAll(const [], uid: 'me');
    await IdbOutbox(BrowserDb(factory)).append(job, uid: 'me');
    final back = await IdbOutbox(BrowserDb(factory)).read(uid: 'me');
    expect(back.single, isA<ContributeJob>());
    expect((back.single as ContributeJob).coords, job.coords);
    expect((back.single as ContributeJob).eles, job.eles);
  });

  test('die Kopie des Netzes übersteht eine neue Sitzung und wird beim Abmelden geräumt', () async {
    final factory = browserIdbFactory()!;
    final recording = TrailRecording(
      id: 'rec-1', trailId: 'trail-1', userId: 'me', source: RecordingSource.app,
      recordedAt: null, reversed: false, quality: 0.6, createdAt: at.toLocal(),
      points: const [LatLng(47.0, 11.0), LatLng(47.001, 11.001)], lengthM: 140,
    );
    final snapshot = (
      recordings: [recording],
      details: [TrailDetails(trailId: 'trail-1', userId: 'me', name: 'Roots', updatedAt: at.toLocal())],
      notes: const <TrailNote>[],
      reports: const <TrailReport>[],
    );
    await IdbTrailCache(BrowserDb(factory)).write(uid: 'me', snapshot: snapshot, savedAt: at);
    final back = await IdbTrailCache(BrowserDb(factory)).read(uid: 'me');
    expect(back, isNotNull);
    expect(back!.snapshot.recordings.single.points, recording.points);
    expect(back.snapshot.details.single.name, 'Roots');
    await IdbTrailCache(BrowserDb(factory)).clear();
    expect(await IdbTrailCache(BrowserDb(factory)).read(uid: 'me'), isNull);
  });

  test('neben den gesehenen Kacheln in derselben Datenbank, gleiche Version', () async {
    // Zwei Speicher mit verschiedenen Versionen blockierten den Upgrade
    // im selben Tab, dauerhaft und stumm — deshalb besitzt browser_db.dart
    // Name und Version.
    final factory = browserIdbFactory()!;
    final db = await BrowserDb(factory).open();
    expect(db.version, kBrowserDbVersion);
    expect(db.objectStoreNames, containsAll([kOutboxStore, kTrailCacheStore, kSeenTileStore]));
    expect(await IdbSeenTileStore(factory).read('t/13/9/9'), isNull);
  });
}
