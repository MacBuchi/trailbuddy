// Ansagen, Buddy unterwegs und Gruppenfahrt an der Uhr (#525, #526, #519):
// was das Handy schickt. Die Seite der Uhr prüft der Ablaufkern
// (`CoreTests.mc`, `coreTrailCueShield`, `coreBuddyNearCue`,
// `coreBuddiesOnMap`).
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/garmin/watch_buddies.dart';
import 'package:trailbuddy/features/garmin/watch_providers.dart';
import 'package:trailbuddy/features/garmin/watch_route.dart'
    show kWatchBuddies, kWatchCue;
import 'package:trailbuddy/features/nearby/buddy_map_layer.dart'
    show nearbyBuddyNameProvider;
import 'package:trailbuddy/features/nearby/nearby_core.dart';
import 'package:trailbuddy/features/nearby/nearby_providers.dart'
    show buddySightingsProvider;
import 'package:trailbuddy/features/routing/voice_cues.dart';
import 'package:trailbuddy/features/routing/voice_service.dart' show speakCues;

import 'watch_phone.dart';

BuddyMapEntry _entry(
  String id,
  BuddyMapKind kind, {
  Duration? ago,
  double lat = 47.5,
}) => (
  buddyId: id,
  kind: kind,
  point: (lat: lat, lon: 11.5),
  cell: null,
  seenAgo: ago,
);

void main() {
  group('pur', () {
    test(
      'Trail voraus, beginnt, geschafft gehen hin — abseits, zurück, angekommen nicht',
      () {
        for (final k in [
          VoiceCueKind.trailAhead,
          VoiceCueKind.trailStart,
          VoiceCueKind.trailDone,
        ]) {
          expect(watchVoiceCueOf(VoiceCue(k, name: ' Talweg ', grade: 2)), {
            't': kWatchCue,
            'k': 'tr',
            'n': 'Talweg',
            'g': 2,
          }, reason: '$k');
        }
        expect(
          watchVoiceCueOf(
            const VoiceCue(VoiceCueKind.trailStart, name: 'Ohne'),
          ),
          {'t': kWatchCue, 'k': 'tr', 'n': 'Ohne'},
        );
        expect(
          watchVoiceCueOf(const VoiceCue(VoiceCueKind.trailAhead, name: '  ')),
          isNull,
        );
        // Die erkennt die Uhr selbst — doppelt vibrieren wäre falsch.
        for (final k in [
          VoiceCueKind.offRoute,
          VoiceCueKind.backOnRoute,
          VoiceCueKind.arrived,
        ]) {
          expect(watchVoiceCueOf(VoiceCue(k, name: 'x')), isNull, reason: '$k');
        }
      },
    );

    test('Dienst → App: hin und zurück, Fremdes bleibt leer', () {
      final text = encodeVoiceWatch(const [
        VoiceCue(VoiceCueKind.offRoute),
        VoiceCue(VoiceCueKind.trailAhead, name: 'Talweg', grade: 1, inM: 180),
      ])!;
      expect(text, startsWith(kVoiceWatchMessagePrefix));
      expect(decodeVoiceWatch(text), [
        {'t': kWatchCue, 'k': 'tr', 'n': 'Talweg', 'g': 1},
      ]);
      expect(encodeVoiceWatch(const [VoiceCue(VoiceCueKind.arrived)]), isNull);
      expect(decodeVoiceWatch('air:live:{}'), isEmpty);
      expect(decodeVoiceWatch('${kVoiceWatchMessagePrefix}kaputt'), isEmpty);
      expect(decodeVoiceWatch(42), isEmpty);
    });

    test(
      'speakCues schickt die Momente an die App, auch wenn die Stimme fehlt',
      () async {
        final toApp = <Object>[];
        await speakCues(
          const [VoiceCue(VoiceCueKind.trailStart, name: 'Talweg', grade: 3)],
          speak: (_, _) async {},
          now: DateTime(2026, 11, 18),
          toApp: toApp.add,
        );
        expect(toApp, hasLength(1));
        expect(decodeVoiceWatch(toApp.single), [
          {'t': kWatchCue, 'k': 'tr', 'n': 'Talweg', 'g': 3},
        ]);
        toApp.clear();
        await speakCues(
          const [VoiceCue(VoiceCueKind.offRoute)],
          speak: (_, _) async {},
          now: DateTime(2026, 11, 18),
          toApp: toApp.add,
        );
        expect(toApp, isEmpty, reason: 'abseits vibriert die Uhr von selbst');
      },
    );

    test('Buddy unterwegs: Name, ohne Namen nichts', () {
      expect(watchBuddyNearOf(' Max '), {
        't': kWatchCue,
        'k': 'bn',
        'n': 'Max',
      });
      expect(watchBuddyNearOf(''), isNull);
    });

    test(
      'Buddys an die Uhr: nur genaue, frischeste zuerst, höchstens fünf, mit Buchstabe und Alter',
      () {
        final names = {'a': 'anna', 'b': 'Ben', 'h': 'Homie'};
        final msg = watchBuddiesOf([
          _entry('a', BuddyMapKind.live, ago: const Duration(minutes: 3)),
          _entry('h', BuddyMapKind.cell),
          _entry('b', BuddyMapKind.live, lat: 47.51234),
        ], (id) => names[id] ?? '?');
        expect(msg, {
          't': kWatchBuddies,
          'l': [
            [4751234, 1150000, 'B', 0],
            [4750000, 1150000, 'A', 180],
          ],
        });
        final many = watchBuddiesOf([
          for (var i = 0; i < 8; i++)
            _entry('$i', BuddyMapKind.live, ago: Duration(seconds: i)),
        ], (_) => 'x');
        expect(many['l'], hasLength(kWatchBuddiesMax));
      },
    );
  });

  group('WatchSync', () {
    late WatchPhone phone;

    setUp(() async {
      phone = WatchPhone(
        overrides: [nearbyBuddyNameProvider.overrideWithValue((_) => 'Max')],
      );
      await phone.open();
    });

    List<Map<String, Object>> sentOf(String t, [String? k]) => [
      for (final batch in phone.bridge.sent)
        for (final m in batch)
          if (m['t'] == t && (k == null || m['k'] == k)) m,
    ];

    void sight(double lat) =>
        phone.c.read(buddySightingsProvider.notifier).set([
          BuddySighting(
            buddyId: 'b',
            live: true,
            position: (lat: lat, lon: 11.5),
            positionAt: DateTime.now(),
            positionPresent: true,
          ),
        ]);

    test('vor dem ersten „hallo" der Uhr geht nichts hin, danach ja', () async {
      final sync = phone.c.read(watchSyncProvider.notifier);
      sync.sendCues([
        {'t': kWatchCue, 'k': 'tr', 'n': 'Talweg'},
      ]);
      sync.buddyNear('Max');
      sight(47.5);
      await Future<void>.delayed(Duration.zero);
      expect(sentOf(kWatchCue), isEmpty);
      expect(sentOf(kWatchBuddies), isEmpty);

      phone.bridge.answer({
        't': 'hi',
        'v': 3,
        'm': 40000,
        'tm': 126784,
        'ver': '1.8.0',
      });
      await Future<void>.delayed(Duration.zero);
      // Was schon da war, geht mit dem „hallo".
      expect(sentOf(kWatchBuddies).single['l'], [
        [4750000, 1150000, 'M', 0],
      ]);
      sync.sendCues([
        {'t': kWatchCue, 'k': 'tr', 'n': 'Talweg'},
      ]);
      sync.buddyNear('Max');
      expect(sentOf(kWatchCue, 'tr'), hasLength(1));
      expect(sentOf(kWatchCue, 'bn').single['n'], 'Max');
    });

    test(
      'dieselbe Lage geht nicht noch einmal; schneller als alle 15 s auch nicht',
      () async {
        phone.bridge.answer({
          't': 'hi',
          'v': 3,
          'm': 40000,
          'tm': 126784,
          'ver': '1.8.0',
        });
        await Future<void>.delayed(Duration.zero);
        sight(47.5);
        expect(sentOf(kWatchBuddies), hasLength(1));
        sight(47.5);
        sight(47.6);
        expect(sentOf(kWatchBuddies), hasLength(1), reason: 'gedrosselt');
      },
    );
  });
}
