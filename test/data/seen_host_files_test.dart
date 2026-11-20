// Die Ablage gesehener kleiner Host-Dateien (#596 H4): Deckel, älteste
// zuerst, Alter, und dieselbe Regel im Ordner (Android) und in IndexedDB
// (Browser, hier die Speicher-Fassung von idb_shim).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:trailbuddy/data/seen_host_files.dart';
import 'package:trailbuddy/data/seen_host_files_io.dart';

void main() {
  group('Regeln', () {
    test('über dem Deckel geht die älteste zuerst', () async {
      var now = DateTime(2026, 11, 20);
      final s = MemorySeenHostFiles(capBytes: 100, now: () => now);
      for (final k in ['a', 'b', 'c']) {
        await s.write(k, 'x' * 40);
        now = now.add(const Duration(minutes: 1));
      }
      expect(await s.read('a'), isNull, reason: 'die älteste ging');
      expect((await s.read('c'))?.text, 'x' * 40);
      expect(s.totalBytes, lessThanOrEqualTo(90));
    });

    test(
      'readSeen mit Alter: jünger gilt, älter nicht, ohne Alter alles',
      () async {
        var now = DateTime(2026, 11, 20, 8);
        final s = MemorySeenHostFiles(now: () => now);
        await s.write('pois.json', '{}');
        now = now.add(const Duration(hours: 25));
        expect(
          await readSeen(
            s,
            'pois.json',
            maxAge: kHostManifestMaxAge,
            now: () => now,
          ),
          isNull,
        );
        expect(await readSeen(s, 'pois.json'), '{}');
        expect(await readSeen(null, 'pois.json'), isNull);
      },
    );
  });

  test(
    'im Ordner: liegt nach einem Neustart noch, Schlüssel mit / flach',
    () async {
      final dir = await Directory.systemTemp.createTemp('seen_host');
      addTearDown(() => dir.delete(recursive: true));
      final key = 'pois-20261120/names/ho.json';
      await DirSeenHostFiles(() async => dir).write(key, 'Hörnle');
      final again = DirSeenHostFiles(() async => dir);
      expect((await again.read(key))?.text, 'Hörnle');
      expect(dir.listSync().whereType<Directory>(), isEmpty);
      expect(await again.read('fehlt'), isNull);
    },
  );

  test('ein Ordner, der nicht aufgeht: still leer', () async {
    final s = DirSeenHostFiles(
      () async => throw const FileSystemException('x'),
    );
    await s.write('a', 'b');
    expect(await s.read('a'), isNull);
  });

  test('in IndexedDB: liegt nach einem Neustart noch, Index mit', () async {
    final factory = newIdbFactoryMemory();
    await IdbSeenHostFiles(factory).write('pois.json', '{"a":1}');
    final again = IdbSeenHostFiles(factory);
    expect((await again.read('pois.json'))?.text, '{"a":1}');
    expect(again.totalBytes, 7);
  });

  test('chooseSeenHostFiles: Browser ohne IndexedDB hat keine Ablage', () {
    expect(chooseSeenHostFiles(web: true), isNull);
    expect(
      chooseSeenHostFiles(web: true, factory: newIdbFactoryMemory()),
      isA<IdbSeenHostFiles>(),
    );
    expect(chooseSeenHostFiles(web: false), isA<DirSeenHostFiles>());
  });
}
