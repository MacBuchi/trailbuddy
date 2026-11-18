// Ansagen übers Ohr (#525): je Moment ein Test, dazu „nie zweimal für
// denselben Trail" — die Momente sind reine Funktionen des Stands.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/features/rides/trail_values.dart';
import 'package:trailbuddy/features/routing/nav_notice.dart';
import 'package:trailbuddy/features/routing/route_progress.dart';
import 'package:trailbuddy/features/routing/voice_cues.dart';

import '../fakes/l10n_de.dart';

const _p = LatLng(47.0, 11.0);

NavState _at(
  double along, {
  double off = 3,
  bool offRoute = false,
  bool arrived = false,
}) => NavState(
  alongM: along,
  remainingM: 5000 - along,
  offM: off,
  offRoute: offRoute,
  arrived: arrived,
  headingDeg: 0,
  position: _p,
  rejoin: _p,
);

final _now = DateTime(2026, 11, 17, 10);

final _note = NavNote(
  body: 'Baum quer',
  author: 'Max',
  createdAt: DateTime(2026, 11, 14, 9),
  authorId: 'max',
);

NavSections _sections({NavNote? note}) => NavSections([
  NavTrailSection(
    startM: 1000,
    endM: 1800,
    trailId: 'a',
    name: 'Rosskopf Süd',
    grade: 2,
    note: note,
  ),
  const NavTrailSection(
    startM: 3000,
    endM: 3500,
    trailId: 'b',
    name: 'Eck',
    grade: 1,
  ),
]);

List<VoiceCueKind> _kinds(List<VoiceCue> cues) => [
  for (final c in cues) c.kind,
];

void main() {
  group('NavVoiceWatcher', () {
    test(
      'Trail voraus: einmal bei 200 m, mit Name, Grad und frischer Meldung',
      () {
        final w = NavVoiceWatcher(selfId: 'me');
        final s = _sections(note: _note);
        expect(w.update(_at(700), s, now: _now), isEmpty);
        final cues = w.update(_at(810), s, now: _now);
        expect(_kinds(cues), [VoiceCueKind.trailAhead]);
        expect(
          voiceCuesText(l10nDe, cues, now: _now),
          'Trail Rosskopf Süd, S2, in 200 Metern. Max, vor 3 Tagen: Baum quer.',
        );
        // Näher heran: nichts mehr voraus.
        expect(w.update(_at(900), s, now: _now), isEmpty);
      },
    );

    test(
      'am Kopf schon zu nah für „voraus": gleich die Ansage beim Einfahren, mit Meldung',
      () {
        final w = NavVoiceWatcher(selfId: 'me');
        final s = _sections(note: _note);
        expect(w.update(_at(980), s, now: _now), isEmpty);
        final cues = w.update(_at(1010), s, now: _now);
        expect(_kinds(cues), [VoiceCueKind.trailStart]);
        expect(
          voiceCuesText(l10nDe, cues, now: _now),
          'Trail Rosskopf Süd, S2. Max, vor 3 Tagen: Baum quer.',
        );
      },
    );

    test('Trail beginnt nach „voraus": ohne die Meldung ein zweites Mal', () {
      final w = NavVoiceWatcher(selfId: 'me');
      final s = _sections(note: _note);
      w.update(_at(810), s, now: _now);
      final cues = w.update(_at(1005), s, now: _now);
      expect(voiceCuesText(l10nDe, cues, now: _now), 'Trail Rosskopf Süd, S2.');
    });

    test('Trail geschafft: Zeit und — mit Erkennung — Airtime', () {
      final w = NavVoiceWatcher();
      final s = _sections();
      w.update(_at(1005), s, now: _now);
      w.update(_at(1500), s, now: _now.add(const Duration(minutes: 2)));
      DateTime? asked;
      final cues = w.update(
        _at(1830),
        s,
        now: _now.add(const Duration(minutes: 3, seconds: 12)),
        values: (since) {
          asked = since;
          return const TrailValues(jumps: 3, airS: 2.4);
        },
      );
      expect(_kinds(cues), [VoiceCueKind.trailDone]);
      expect(asked, _now, reason: 'die Werte zählen ab dem Einfahren');
      expect(
        voiceCuesText(l10nDe, cues, now: _now),
        'Rosskopf Süd geschafft, 3 Minuten 12. Airtime 2,4 Sekunden, 3 Sprünge.',
      );
    });

    test(
      'nie zweimal für denselben Trail — auch nicht nach Hin und Zurück oder Umplanen',
      () {
        final w = NavVoiceWatcher();
        final s = _sections();
        final all = <VoiceCueKind>[];
        for (final along in <double>[
          810,
          1005,
          1500,
          1830,
          1500,
          1830,
          810,
          1005,
        ]) {
          all.addAll(_kinds(w.update(_at(along), s, now: _now)));
        }
        // Die neue Linie nach „Route umplanen": derselbe Trail woanders.
        final moved = NavSections([
          const NavTrailSection(
            startM: 2000,
            endM: 2800,
            trailId: 'a',
            name: 'Rosskopf Süd',
            grade: 2,
          ),
        ]);
        for (final along in <double>[1810, 2005, 2830]) {
          all.addAll(_kinds(w.update(_at(along), moved, now: _now)));
        }
        expect(all, [
          VoiceCueKind.trailAhead,
          VoiceCueKind.trailStart,
          VoiceCueKind.trailDone,
        ]);
      },
    );

    test(
      'Route verlassen und zurück: je einmal — aber erst, nachdem man auf der Route war',
      () {
        final w = NavVoiceWatcher();
        final s = _sections();
        // Start 600 m vor der Haustür: abseits, aber nie auf der Route ⇒ still.
        expect(
          w.update(_at(0, off: 600, offRoute: true), s, now: _now),
          isEmpty,
        );
        expect(w.update(_at(0, off: 10), s, now: _now), isEmpty);
        expect(
          _kinds(w.update(_at(100, off: 60, offRoute: true), s, now: _now)),
          [VoiceCueKind.offRoute],
        );
        expect(
          w.update(_at(100, off: 80, offRoute: true), s, now: _now),
          isEmpty,
        );
        final back = w.update(_at(120, off: 5), s, now: _now);
        expect(_kinds(back), [VoiceCueKind.backOnRoute]);
        expect(voiceCuesText(l10nDe, back, now: _now), 'Wieder auf der Route.');
        expect(
          voiceCueText(
            l10nDe,
            const VoiceCue(VoiceCueKind.offRoute),
            now: _now,
          ),
          'Du hast die Route verlassen.',
        );
      },
    );

    test(
      'abseits keine Trail-Momente — der Stand auf der Linie ist dann geraten',
      () {
        final w = NavVoiceWatcher();
        w.update(_at(100), _sections(), now: _now);
        expect(
          _kinds(
            w.update(_at(810, off: 50, offRoute: true), _sections(), now: _now),
          ),
          [VoiceCueKind.offRoute],
        );
      },
    );

    test(
      'angekommen: einmal, nach „geschafft", wenn die Route auf dem Trail endet',
      () {
        final w = NavVoiceWatcher();
        final s = NavSections([
          const NavTrailSection(
            startM: 4000,
            endM: 5000,
            trailId: 'c',
            name: 'Ende',
          ),
        ]);
        w.update(_at(4005), s, now: _now);
        final cues = w.update(
          _at(5000, arrived: true),
          s,
          now: _now.add(const Duration(seconds: 48)),
        );
        expect(_kinds(cues), [VoiceCueKind.trailDone, VoiceCueKind.arrived]);
        expect(
          voiceCuesText(l10nDe, cues, now: _now),
          'Ende geschafft, 48 Sekunden. Angekommen.',
        );
        expect(w.update(_at(5000, arrived: true), s, now: _now), isEmpty);
      },
    );

    test('Meldung: die eigene nicht, eine alte nicht', () {
      final mine = NavNote(
        body: 'x',
        author: 'Ich',
        createdAt: _now,
        authorId: 'me',
      );
      final old = NavNote(
        body: 'x',
        author: 'Max',
        createdAt: _now.subtract(const Duration(days: 15)),
        authorId: 'max',
      );
      expect(voiceNoteFresh(mine, now: _now, selfId: 'me'), isFalse);
      expect(voiceNoteFresh(old, now: _now, selfId: 'me'), isFalse);
      expect(voiceNoteFresh(_note, now: _now, selfId: 'me'), isTrue);
      final w = NavVoiceWatcher(selfId: 'me');
      expect(
        w.update(_at(810), _sections(note: mine), now: _now).single.note,
        isNull,
      );
    });
  });

  group('FreeVoiceWatcher (F7)', () {
    final line = [const LatLng(47.0, 11.0), const LatLng(47.0, 11.01)];
    final trails = [
      VoiceTrail(trailId: 't', name: 'Hangweg', grade: 3, line: line),
    ];
    RidePoint pt(double lng, {double lat = 47.0, double acc = 5}) =>
        RidePoint(lat: lat, lng: lng, at: _now, accuracyM: acc);

    test(
      'einfahren: zwei Fixe auf der Linie, 25 m auseinander — Name und Grad, einmal',
      () {
        final w = FreeVoiceWatcher();
        expect(
          w.update(pt(11.001), trails, now: _now),
          isNull,
          reason: 'erst ein Fix',
        );
        final cue = w.update(pt(11.002), trails, now: _now);
        expect(voiceCueText(l10nDe, cue!, now: _now), 'Trail Hangweg, S3.');
        expect(
          w.update(pt(11.003), trails, now: _now),
          isNull,
          reason: 'je Trail und Fahrt einmal',
        );
      },
    );

    test('queren oder unscharf: still', () {
      final w = FreeVoiceWatcher();
      w.update(pt(11.005, lat: 46.999), trails, now: _now);
      expect(w.update(pt(11.005, lat: 47.001), trails, now: _now), isNull);
      final blurry = FreeVoiceWatcher();
      blurry.update(pt(11.001, acc: 40), trails, now: _now);
      expect(blurry.update(pt(11.002, acc: 40), trails, now: _now), isNull);
    });

    test('Datei: Rundlauf mit Konto, fremdes Konto liest nichts', () {
      final withNote = [
        VoiceTrail(
          trailId: 't',
          name: 'Hangweg',
          grade: 3,
          line: line,
          note: _note,
        ),
      ];
      final text = encodeVoiceTrails(uid: 'u', trails: withNote);
      final back = decodeVoiceTrails(text, uid: 'u').single;
      expect(
        (back.trailId, back.name, back.grade, back.line.length),
        ('t', 'Hangweg', 3, 2),
      );
      expect(
        (back.note!.body, back.note!.author, back.note!.authorId),
        ('Baum quer', 'Max', 'max'),
      );
      expect(decodeVoiceTrails(text, uid: 'other'), isEmpty);
    });
  });

  test('Routen-Datei trägt Meldung und Konto für den Dienst', () {
    final data = NavRouteData(
      points: const [_p, LatLng(47.0, 11.01)],
      title: 'x',
      sections: _sections(note: _note),
      selfId: 'me',
    );
    final back = NavRouteData.decode(data.encode())!;
    expect(back.selfId, 'me');
    expect(back.sections.trails.first.note!.body, 'Baum quer');
    expect(back.sections.trails.last.note, isNull);
  });

  test('Zahlen fürs Ohr', () {
    expect(voiceRoundMeters(190), 200);
    expect(voiceRoundMeters(60), 50);
    expect(voiceRoundMeters(10), 50);
    expect(
      voiceDurationText(l10nDe, const Duration(seconds: 61)),
      'eine Minute 1',
    );
    expect(
      voiceNoteText(
        l10nDe,
        NavNote(body: 'nass', author: null, createdAt: _now),
        now: _now,
      ),
      'Ein Buddy, heute: nass',
    );
  });
}
