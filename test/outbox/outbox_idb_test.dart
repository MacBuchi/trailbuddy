// Der Ausgangskorb im Browser (#153), auf der VM mit der Speicher-Fassung
// von idb_shim — derselbe Code wie im Browser; den ECHTEN Speicher fährt
// `test/web/outbox_trail_cache_browser_test.dart` unter dart2js.
//
// Der Unterschied zur Kopie des Netzes ist der Punkt dieser Datei: Der
// Korb trägt das ORIGINAL, also wirft `append`, wenn nichts unterkommt.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:trailbuddy/data/browser_db.dart';
import 'package:trailbuddy/data/feedback_repository.dart' show FeedbackType;
import 'package:trailbuddy/data/outbox.dart';
import 'package:trailbuddy/data/outbox_idb.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';

import '../fakes/broken_idb_factory.dart';

void main() {
  final at = DateTime.utc(2026, 10, 8, 12);
  final contribute = ContributeJob(
    id: 'job-1',
    createdAt: at,
    coords: const [11.0, 47.0, 11.001, 47.001, 11.002, 47.002],
    eles: const [900, 890, 880],
    source: RecordingSource.app,
    name: 'Wurzeltrail',
  );
  final feedback = FeedbackJob(id: 'job-2', createdAt: at, type: FeedbackType.bug, message: 'Karte weiß');

  test('Aufträge kommen vollständig zurück, auch aus einer neuen Sitzung, und nur dem eigenen Konto', () async {
    final factory = newIdbFactoryMemory();
    final box = IdbOutbox(BrowserDb(factory), requestDurable: () async => true, checkDurable: () async => true);
    expect(await box.read(uid: 'me'), isEmpty);
    await box.append(contribute, uid: 'me');
    await box.append(feedback, uid: 'me');

    final again = IdbOutbox(BrowserDb(factory));
    final back = await again.read(uid: 'me');
    expect([for (final j in back) j.id], ['job-1', 'job-2']);
    expect((back.first as ContributeJob).coords, contribute.coords);
    expect((back.first as ContributeJob).eles, contribute.eles);
    expect((back.last as FeedbackJob).message, 'Karte weiß');
    expect(await again.read(uid: 'someone'), isEmpty, reason: 'fremde Aufträge gingen sonst im falschen Konto hoch');

    await again.replaceAll([feedback], uid: 'me');
    expect([for (final j in await box.read(uid: 'me')) j.id], ['job-2']);
  });

  test('abgelegt wird derselbe JSON-Text wie in der Datei, kein Objekt', () async {
    final factory = newIdbFactoryMemory();
    final db = BrowserDb(factory);
    await IdbOutbox(db, requestDurable: () async => true).append(contribute, uid: 'me');
    final raw = await db.readStore(kOutboxStore, (s) => s.getObject('jobs'));
    expect(raw, encodeOutbox([contribute], uid: 'me'));
  });

  test('zwei Aufträge zugleich: keiner verliert den anderen', () async {
    final box = IdbOutbox(BrowserDb(newIdbFactoryMemory()), requestDurable: () async => true);
    await Future.wait([box.append(contribute, uid: 'me'), box.append(feedback, uid: 'me')]);
    expect(await box.read(uid: 'me'), hasLength(2));
  });

  group('Der Korb trägt das Original', () {
    final broken = IdbOutbox(BrowserDb(BrokenIdbFactory()), requestDurable: () async => true);

    test('append und replaceAll WERFEN, wenn nichts unterkommt', () async {
      await expectLater(broken.append(contribute, uid: 'me'), throwsA(isA<StateError>()));
      await expectLater(broken.replaceAll([contribute], uid: 'me'), throwsA(isA<StateError>()));
    });

    test('lesen wirft nie', () async {
      await expectLater(broken.read(uid: 'me'), completion(isEmpty));
    });
  });

  group('Die Bitte um Dauer', () {
    test('erst beim ersten Ablegen, einmal je Sitzung — Lesen fragt nicht', () async {
      var asked = 0;
      final box = IdbOutbox(BrowserDb(newIdbFactoryMemory()), requestDurable: () async {
        asked++;
        return true;
      });
      await box.read(uid: 'me');
      expect(asked, 0, reason: 'Firefox fragt nach — beim Start hätte die Frage keinen Anlass');
      await box.append(contribute, uid: 'me');
      await box.append(feedback, uid: 'me');
      expect(asked, 1);
    });

    test('abgelegt wird, auch wenn der Browser ablehnt oder nie antwortet — und der Korb sagt es', () async {
      final factory = newIdbFactoryMemory();
      final never = Completer<bool>();
      final box = IdbOutbox(BrowserDb(factory),
          requestDurable: () => never.future, checkDurable: () async => false);
      await box.append(contribute, uid: 'me');
      expect(await IdbOutbox(BrowserDb(factory)).read(uid: 'me'), hasLength(1),
          reason: 'eine unbeantwortete Nachfrage darf das Ablegen nicht aufhalten');

      final refused = IdbOutbox(BrowserDb(newIdbFactoryMemory()),
          requestDurable: () async => false, checkDurable: () async => false);
      await refused.append(contribute, uid: 'me');
      expect(await refused.read(uid: 'me'), hasLength(1));
      expect(await refused.isDurable(), isFalse);
    });

    test('zugesichert heißt zugesichert; eine werfende Abfrage heißt „nicht"', () async {
      final ok = IdbOutbox(BrowserDb(newIdbFactoryMemory()),
          requestDurable: () async => true, checkDurable: () async => true);
      await ok.append(contribute, uid: 'me');
      expect(await ok.isDurable(), isTrue);
      final failing = IdbOutbox(BrowserDb(newIdbFactoryMemory()),
          requestDurable: () async => throw StateError('kein navigator.storage'),
          checkDurable: () async => throw StateError('kein navigator.storage'));
      await failing.append(contribute, uid: 'me');
      expect(await failing.isDurable(), isFalse);
    });
  });

  group('Welcher Korb zu welcher Plattform gehört', () {
    test('Android: die Datei, die sich nie räumt', () async {
      final box = chooseOutbox(web: false, factory: newIdbFactoryMemory());
      expect(box, isA<FileOutbox>());
      expect(await box.isDurable(), isTrue);
    });

    test('Browser mit IndexedDB: der Korb dort', () {
      expect(chooseOutbox(web: true, factory: newIdbFactoryMemory()), isA<IdbOutbox>());
    });

    test('Browser ohne IndexedDB: keiner, und der wirft', () async {
      final none = chooseOutbox(web: true, factory: null);
      expect(none, isA<NoOutbox>());
      await expectLater(none.append(contribute, uid: 'me'), throwsA(isA<OutboxUnavailable>()));
    });
  });
}
