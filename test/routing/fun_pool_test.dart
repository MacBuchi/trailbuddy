// „Spaßig" nimmt Trails entlang der GANZEN Route (#468): Der Pool hing
// am Start (beide Enden ≤ 12 km), auf einer längeren Route fehlten die
// Trails der zweiten Hälfte, auch wenn die Route direkt an ihnen vorbeiführt.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/routing/route_result.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart' show RecordingSource;
import 'package:trailbuddy/models/trail.dart';

/// Punkt [km] Kilometer östlich und [northM] Meter nördlich eines Ursprungs.
LatLng _p(double km, [double northM = 0]) => LatLng(47 + northM / 111195, 11 + km / 75.2);

Trail _trail(String id, LatLng from, LatLng to) => Trail(
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
          points: [from, to],
          lengthM: 0,
        ),
      ],
      details: [TrailDetails(trailId: id, userId: 'me', name: id, grade: 2, traits: const {TrailTrait.flowy})],
    );

void main() {
  final start = _p(0), target = _p(20);

  test('ein Trail nah an der Linie zählt am Anfang wie am Ende', () {
    final early = _trail('early', _p(2, 500), _p(2.5)); // 500 m neben der Linie, nah am Start
    final late = _trail('late', _p(16, 300), _p(16.5)); // 300 m neben der Linie, 16 km vom Start
    final ids = funPoolOf([early, late], start, target).map((t) => t.id).toSet();
    expect(ids, {'early', 'late'});
  });

  test('weit abseits der Linie bleibt draußen, auch nah am Start', () {
    final aside = _trail('aside', _p(1, 7000), _p(1.5, 6500)); // 7 km neben dem Start
    final behind = _trail('behind', _p(-4), _p(-3.5)); // hinter dem Start
    expect(funPoolOf([aside, behind], start, target), isEmpty);
  });

  test('höchstens kFunPoolMax, die mit dem kleinsten Umweg zuerst', () {
    final trails = [
      for (var i = 0; i < kFunPoolMax + 5; i++) _trail('t$i', _p(1 + i * 0.5, 100.0 + i * 50), _p(1.2 + i * 0.5)),
    ];
    final pool = funPoolOf(trails.reversed.toList(), start, target);
    expect(pool, hasLength(kFunPoolMax));
    expect(pool.first.id, 't0', reason: 'der nächste an der Linie');
    expect(pool.map((t) => t.id), isNot(contains('t${kFunPoolMax + 4}')));
  });

  test('der Ziel-Trail fährt man danach, nicht davor', () {
    final t = _trail('goal', _p(10, 200), _p(10.5));
    expect(funPoolOf([t], start, target, exceptId: 'goal'), isEmpty);
  });
}
