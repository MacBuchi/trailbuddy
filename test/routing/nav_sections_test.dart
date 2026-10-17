// Die Abschnitte einer Route und die Phasen der Navigation (#312,
// Konzept-Routing 9.9), ohne Flutter: aus einer geplanten Runde, aus einer
// Fahrt über das Netz, aus dem Weg zum Trailkopf — und was die Folgeansicht
// daraus je Stand fragt.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/routing/loop_planner.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart' show RecordingSource;
import 'package:trailbuddy/features/routing/route_progress.dart';
import 'package:trailbuddy/models/trail.dart';
import '../fakes/l10n_de.dart';

/// Eine Linie nach Norden auf 11° Ost: Punkt i liegt i · 0,001° (≈ 111 m)
/// nördlich von 47°.
LatLng _n(double i) => LatLng(47 + i / 1000, 11);
List<LatLng> _line(double from, double to, [double step = 1]) =>
    [for (var i = from; i <= to + 1e-9; i += step) _n(i)];

Trail _trail(String id, String name, List<LatLng> points, {int? grade, List<TrailNote> notes = const []}) => Trail(
      id: id,
      myId: 'me',
      recordings: [
        TrailRecording(
          id: 'r-$id',
          trailId: id,
          userId: 'me',
          source: RecordingSource.import,
          recordedAt: null,
          reversed: false,
          quality: 0.5,
          createdAt: DateTime.utc(2026, 1, 1),
          points: points,
          lengthM: 0,
        ),
      ],
      details: [
        TrailDetails(trailId: id, userId: 'me', name: name, grade: grade, traits: const {TrailTrait.flowy}),
      ],
      notes: notes,
    );

NavState _state(double alongM, {bool moving = true, bool arrived = false}) => NavState(
      alongM: alongM,
      remainingM: 0,
      offM: 0,
      offRoute: false,
      arrived: arrived,
      headingDeg: 0,
      position: _n(0),
      rejoin: _n(0),
      moving: moving,
    );

void main() {
  group('navSectionsOfLoop', () {
    test('findet die Lage jedes Trails auf der Linie — gesucht, nicht aufsummiert', () {
      // Start (0) → Anschluss → Forstweg 0..3 → Trail A 3..5 → Wanderweg 5..6 → Trail B 6..8 → Ziel 8.
      final a = PoolTrail(
          id: 'a', name: 'Alpha', points: _line(3, 5), lengthM: 222, grade: 2, rating: 4, gainM: 0, lossM: 80);
      final b = PoolTrail(
          id: 'b', name: 'Beta', points: _line(6, 8), lengthM: 222, grade: 1, rating: 3, gainM: 0, lossM: 60);
      final plan = LoopPlan(
        LoopOutcome.ok,
        // Ein Anschlussstück vor dem ersten Abschnitt, wie `_assemble` es legt.
        points: [_n(-0.2), ..._line(0, 8)],
        sections: [
          LoopSection(points: _line(0, 3), lengthM: 333, cls: WayClass.forstweg, leg: 0),
          LoopSection(points: _line(3, 5), lengthM: 222, trail: a),
          LoopSection(points: _line(5, 5.5), lengthM: 55, cls: WayClass.wanderweg, leg: 1),
          LoopSection(points: _line(5.5, 6, 0.5), lengthM: 55, cls: WayClass.wanderweg, leg: 1),
          LoopSection(points: _line(6, 8), lengthM: 222, trail: b),
        ],
        stops: [(trail: a, secondPass: false), (trail: b, secondPass: false)],
      );
      final s = navSectionsOfLoop(l10nDe, plan, trailById: (_) => null);
      expect(s.trails.map((t) => t.name), ['Alpha', 'Beta']);
      final m = 111.2;
      expect(s.trails[0].startM, closeTo(3.2 * m, 2));
      expect(s.trails[0].endM, closeTo(5.2 * m, 2));
      expect(s.trails[1].startM, closeTo(6.2 * m, 2));
      expect(s.trails[0].lossM, 80);
      expect(s.trails[0].grade, 2);
      // Die Wege der Anfahrt, zusammengefasst: ein Forstweg, dann ein Wanderweg.
      expect(s.trails[0].approachWays.map((w) => w.cls), [WayClass.forstweg]);
      expect(s.trails[1].approachWays.map((w) => w.cls), [WayClass.wanderweg]);
      expect(s.trails[1].approachWays.single.lengthM, 110);
    });

    test('aus dem Netz kommen Charakter, Zustand und der jüngste Hinweis', () {
      final a = PoolTrail(
          id: 'a', name: 'alt', points: _line(1, 2), lengthM: 111, grade: 2, rating: 4, gainM: 0, lossM: 0);
      final plan = LoopPlan(
        LoopOutcome.ok,
        points: _line(0, 3),
        sections: [LoopSection(points: _line(1, 2), lengthM: 111, trail: a)],
        stops: [(trail: a, secondPass: false)],
      );
      final net = _trail('a', 'Rosskopf Süd', _line(1, 2), grade: 3, notes: [
        TrailNote(id: 'n1', trailId: 'a', userId: 'u', body: 'alt', createdAt: DateTime.utc(2026, 10, 1), username: 'jan'),
        TrailNote(id: 'n2', trailId: 'a', userId: 'u', body: 'Baum quer', createdAt: DateTime.utc(2026, 10, 9), username: 'jan'),
      ]);
      final s = navSectionsOfLoop(l10nDe, plan, trailById: (id) => id == 'a' ? net : null);
      final t = s.trails.single;
      expect(t.name, 'Rosskopf Süd');
      expect(t.grade, 3);
      expect(t.traits, [TrailTrait.flowy]);
      expect(t.note!.body, 'Baum quer');
      expect(t.note!.author, 'jan');
    });
  });

  group('navSectionsOfLine', () {
    test('eine Fahrt über einen Trail des Netzes: der gedeckte Trail zählt, ein halb gedeckter nicht', () {
      final ride = _line(0, 10, 0.1);
      final covered = _trail('c', 'Gedeckt', _line(3, 5, 0.1));
      // Nur zur Hälfte auf der Fahrt: 60 % Deckung des Trails — unter 80 %.
      final half = _trail('h', 'Halb', [..._line(8, 10, 0.1), ..._line(10.1, 11.5, 0.1)]);
      final s = navSectionsOfLine(l10nDe, ride, [covered, half]);
      expect(s.trails.map((t) => t.name), ['Gedeckt']);
      // Der Korridor nimmt den Fahrtpunkt kurz vor dem Anfang mit (11 m).
      expect(s.trails.single.startM, closeTo(3 * 111.2, 15));
      expect(s.trails.single.endM, closeTo(5 * 111.2, 15));
    });
  });

  group('navSectionsOfLoop(beyond:)', () {
    test('zum Trailkopf (#356 PR 7): der Ziel-Trail steht hinter dem Ende der Linie', () {
      final target = _trail('t', 'Ziel', _line(5, 7), grade: 2);
      final plan = LoopPlan(
        LoopOutcome.ok,
        points: _line(0, 5),
        sections: [LoopSection(points: _line(0, 5), lengthM: 556, cls: WayClass.forstweg, leg: 0)],
      );
      final s = navSectionsOfLoop(l10nDe, plan, trailById: (_) => null, beyond: target);
      final t = s.trails.single;
      expect(t.beyondRoute, isTrue);
      expect(t.startM, closeTo(5 * 111.2, 2));
      expect(t.endM, t.startM);
      expect(s.ridden, isEmpty);
      expect(t.approachWays.single.cls, WayClass.forstweg);
    });
  });

  group('navPhaseOf', () {
    final sections = NavSections([
      const NavTrailSection(startM: 1000, endM: 1800, trailId: 'a', name: 'Alpha', grade: 2),
      const NavTrailSection(startM: 2500, endM: 3000, trailId: 'b', name: 'Beta', grade: 1),
    ]);
    // Ein Profil alle 50 m: flach, dann eine Rampe mit 16 % zwischen 400 und 500 m, dann wieder sanft.
    final dist = [for (var i = 0; i <= 70; i++) i * 50.0];
    final ele = [
      for (var i = 0; i <= 70; i++)
        600.0 + (i * 50 <= 400 ? i : (i * 50 <= 500 ? 8 + (i - 8) * 8 : 24 + (i - 10)))
    ];

    test('Anfahrt → am Trailkopf → auf dem Trail → nächste Anfahrt → Ziel', () {
      final p0 = navPhaseOf(_state(0), sections, routeLengthM: 3500, climbDistM: dist, climbEleM: ele);
      expect(p0.kind, NavPhaseKind.approach);
      expect(p0.section!.name, 'Alpha');
      expect(p0.distM, 1000);
      // Bis zum Kopf: 8 + 16 + 10 = 34 m bergauf, Rampe 16 % in 400 m.
      expect(p0.climbM, closeTo(34, 0.5));
      expect(p0.ramp!.grade, closeTo(0.16, 1e-9));
      expect(p0.ramp!.inM, 400);

      // 80 m vor dem Kopf, stehend: am Trailkopf. Rollend: noch Anfahrt.
      expect(navPhaseOf(_state(920, moving: false), sections, routeLengthM: 3500).kind, NavPhaseKind.atHead);
      expect(navPhaseOf(_state(920), sections, routeLengthM: 3500).kind, NavPhaseKind.approach);
      // 20 m hinter dem Kopf, stehend: noch am Kopf; rollend: auf dem Trail.
      expect(navPhaseOf(_state(1020, moving: false), sections, routeLengthM: 3500).kind, NavPhaseKind.atHead);
      final on = navPhaseOf(_state(1020), sections, routeLengthM: 3500, climbDistM: dist, climbEleM: ele);
      expect(on.kind, NavPhaseKind.onTrail);
      expect(on.section!.name, 'Alpha');
      expect(on.distM, 780);
      expect(on.lossM, 0);
      // 50 m hinter dem Kopf, stehend: auf dem Trail — die 30 m sind vorbei.
      expect(navPhaseOf(_state(1050, moving: false), sections, routeLengthM: 3500).kind, NavPhaseKind.onTrail);

      // Nach Alpha: die Anfahrt zu Beta.
      final next = navPhaseOf(_state(2000), sections, routeLengthM: 3500);
      expect(next.kind, NavPhaseKind.approach);
      expect(next.section!.name, 'Beta');
      expect(next.distM, 500);

      // Nach Beta: bis zum Ziel, ohne Trail.
      final goal = navPhaseOf(_state(3200), sections, routeLengthM: 3500);
      expect(goal.kind, NavPhaseKind.approach);
      expect(goal.toGoal, isTrue);
      expect(goal.distM, 300);

      expect(navPhaseOf(_state(3500, arrived: true), sections, routeLengthM: 3500).kind, NavPhaseKind.arrived);
    });

    test('am Ziel des Trailkopf-Wegs steht die Trailkopf-Karte', () {
      final head = NavSections([
        const NavTrailSection(startM: 3500, endM: 3500, trailId: 'z', name: 'Ziel', beyondRoute: true),
      ]);
      final before = navPhaseOf(_state(3000), head, routeLengthM: 3500);
      expect(before.kind, NavPhaseKind.approach);
      expect(before.section!.name, 'Ziel');
      expect(before.distM, 500);
      final at = navPhaseOf(_state(3500, arrived: true), head, routeLengthM: 3500);
      expect(at.kind, NavPhaseKind.atHead);
      expect(at.section!.name, 'Ziel');
    });

    test('ohne Abschnitte zählt die Anfahrt bis zum Ziel', () {
      final p = navPhaseOf(_state(100), NavSections.none, routeLengthM: 1500);
      expect(p.kind, NavPhaseKind.approach);
      expect(p.section, isNull);
      expect(p.distM, 1400);
    });
  });

  group('NavTrailWatch (Trail geschafft)', () {
    // Trail A von 300 bis 1100 m, 400 hm bergab laut Netz; das Profil
    // fällt auf ihm 0,5 m je Meter.
    final a = const NavTrailSection(startM: 300, endM: 1100, trailId: 'a', name: 'Rosskopf Süd', lossM: 400);
    final sections = NavSections([a]);
    final t0 = DateTime.utc(2026, 10, 13, 10);
    final dist = [for (var m = 0.0; m <= 1500; m += 50) m];
    final ele = [for (final m in dist) 1000 - 0.5 * (m.clamp(300, 1100) - 300)];

    NavTrailDone? ride(NavTrailWatch w, List<(double, int, double)> fixes) {
      NavTrailDone? done;
      for (final (along, s, speed) in fixes) {
        done = w.update(_state(along), sections, t0.add(Duration(seconds: s)),
                speedMps: speed, climbDistM: dist, climbEleM: ele) ??
            done;
      }
      return done;
    }

    test('ganz gefahren: Zeit ab der Einfahrt, Top-Speed, bergab aus dem Profil', () {
      final w = NavTrailWatch();
      final done = ride(w, [(100, 0, 4), (310, 30, 3), (700, 100, 12.5), (1000, 200, 8), (1095, 240, 6)])!;
      expect(done.section, same(a));
      expect(done.duration, const Duration(seconds: 210));
      expect(done.endedAt, t0.add(const Duration(seconds: 240)));
      expect(done.maxSpeedMps, 12.5, reason: 'das Tempo VOR dem Trail zählt nicht');
      expect(done.lossM, closeTo(392.5, 30), reason: 'aus dem Profil, ab der Einfahrt');
      // Nur einmal.
      expect(w.update(_state(1200), sections, t0.add(const Duration(seconds: 260))), isNull);
    });

    test('mitten auf dem Trail eingestiegen: weniger als die Hälfte, keine Bilanz', () {
      expect(ride(NavTrailWatch(), [(800, 0, 5), (1000, 30, 5), (1200, 60, 5)]), isNull);
      // Genau ab der Hälfte zählt es.
      expect(ride(NavTrailWatch(), [(700, 0, 5), (1200, 60, 5)]), isNotNull);
    });

    test('zurück vor den Kopf zählt nicht; ohne Profil gilt der Wert des Netzes', () {
      expect(ride(NavTrailWatch(), [(400, 0, 5), (200, 30, 5), (1200, 60, 5)]), isNull);
      final w = NavTrailWatch();
      w.update(_state(320), sections, t0);
      final done = w.update(_state(1150), sections, t0.add(const Duration(minutes: 5)))!;
      expect(done.lossM, 400);
      expect(done.maxSpeedMps, isNull);
    });

    test('endet der Trail am Ziel, kommt die Bilanz mit der Ankunft', () {
      final w = NavTrailWatch();
      w.update(_state(320), sections, t0);
      expect(w.update(_state(900), sections, t0.add(const Duration(minutes: 2))), isNull);
      expect(w.update(_state(1000, arrived: true), sections, t0.add(const Duration(minutes: 3))), isNotNull);
    });
  });

  group('Profil-Helfer', () {
    final dist = <double>[0, 50, 100, 150, 200];
    final ele = <double>[600, 620, 610, 640, 630];

    test('climbAfter mit untilM zählt nur bis dorthin', () {
      expect(climbAfter(dist, ele, 0), closeTo(50, 1e-9));
      expect(climbAfter(dist, ele, 0, untilM: 100), closeTo(20, 1e-9));
      expect(climbBetween(dist, ele, 100, 200)!.loss, closeTo(10, 1e-9));
      expect(climbBetween(dist, ele, 100, 200)!.gain, closeTo(30, 1e-9));
    });

    test('rampAhead nennt die erste Rampe ab 12 % und wo sie beginnt', () {
      // 20 m auf 50 m = 40 % gleich zu Beginn; ab 50 m fällt es.
      expect(rampAhead(dist, ele, 0, 200)!.inM, 0);
      final later = rampAhead(dist, ele, 60, 200)!;
      expect(later.grade, closeTo(0.6, 1e-9));
      expect(later.inM, closeTo(40, 1e-9));
      expect(rampAhead([0.0, 100], [600.0, 605], 0, 100), isNull);
    });
  });
}
