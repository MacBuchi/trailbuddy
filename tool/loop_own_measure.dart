// Messung, kein Test (#516, Konzept-Routing 12.9 Schritte 3–6, die 💻-
// Prüfungen): „Runde vorschlagen" im EIGENEN Netz des Betreibers, gegen
// die Runden, die er wirklich gefahren ist.
//
// Je eigene Runde (Start ≈ Ende) rechnet es den Vorschlag ab ihrem Start,
// mit ihrer Fahrzeit (auf die halbe Stunde des Reglers) und ihrem Rad:
//   A  so wie die App seit 0.175.0 (Vorgabe-Limit, ohne Vorliebe),
//   B  mit Vorliebe (0.176.0): Fahrten je Trail aus den ANDEREN Runden,
//   C  wie B mit dem Limit, das die Fahrten gehoben hätten (0.177.0),
//   D  wie A mit ± 30 min statt einem Viertel der Zeit (nur unter 2 h),
//   E  wie B mit dreifacher Vorliebe (+18 % je Fahrt, höchstens +90 %) —
//      nur zum Vergleich, ab wann sie die Wahl kippt.
// Dazu, wie viel der vorgeschlagenen Trail-Meter auf Trails liegt, die
// diese Runde wirklich fuhr bzw. die irgendeine Fahrt fuhr.
//
// Private Daten, nur am Rechner: die Trail-Sammlung (GPX) und die Fahrten
// (`build/strava_rides/<bio|ebike>/`), die Kacheln um den eigenen Start
// (`tool/routing_tiles.py sample --center-file`):
//   TB_TILES_DIR=build/own_net/tiles/own TB_TRAILS_DIR=build/own_net/trails \
//     TB_RIDES_DIR=build/strava_rides flutter test tool/loop_own_measure.dart
// Ausgabe: Kennzahlen je Runde (L1, L2 …), keine Koordinaten, keine
// Namen — sie darf so nach docs/routing-messung.md („#516 eigenes Netz").
// Liegt unter tool/, nicht test/: Es geht nie ins Binary (Version Guard).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/offline_areas/height_tiles.dart';
import 'package:trailbuddy/features/rides/ride_split.dart' show kSplitSmoothWindow, smoothElevation;
import 'package:trailbuddy/features/routing/graph_input.dart';
import 'package:trailbuddy/features/routing/loop_planner.dart';
import 'package:trailbuddy/features/routing/road_graph_loader.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';
import 'package:trailbuddy/features/routing/routing_tile.dart';
import 'package:trailbuddy/features/routing/trail_head_route.dart' show kTrailHeadMarginM;
import 'package:trailbuddy/features/routing/trail_overlay.dart';
import 'package:trailbuddy/features/trails/gpx.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart' show haversineM;

double _dist(LatLng a, LatLng b) => haversineM(a.latitude, a.longitude, b.latitude, b.longitude);

const _z = 13;

/// Start und Ende einer Runde liegen höchstens so weit auseinander.
const _loopCloseM = 1000.0;

/// Ein Trail gilt als befahren, wenn so viele seiner Punkte …
const _riddenShare = 0.8;

/// … so nah an der Fahrt liegen.
const _riddenNearM = 30.0;

/// Zu kurze Runden sagen über einen Vorschlag nichts.
const _minRideClimbM = 150.0;

class _Ride {
  _Ride(this.profile, this.points, this.movingS, this.climbM, this.lengthM);
  final RiderProfile profile;
  final List<LatLng> points;
  final double movingS;
  final double climbM;
  final double lengthM;
  Set<String> ridden = {};
}

void main() {
  final dir = Platform.environment['TB_TILES_DIR'],
      trailsDir = Platform.environment['TB_TRAILS_DIR'],
      ridesDir = Platform.environment['TB_RIDES_DIR'];
  test('Runde vorschlagen: eigenes Netz gegen eigene Runden', () {
    if (dir == null || trailsDir == null || ridesDir == null) {
      // ignore: avoid_print
      print('TB_TILES_DIR / TB_TRAILS_DIR / TB_RIDES_DIR fehlen — siehe Kopf der Datei.');
      return;
    }
    final meta = jsonDecode(File('$dir/frame.json').readAsStringSync()) as Map<String, dynamic>;
    final tiles = [for (final t in meta['tiles'] as List) ((t as List)[0] as int, t[1] as int)];
    Uint8List? bytes(String kind, (int, int) t, String ext) {
      final f = File('$dir/$kind/${t.$1}_${t.$2}.$ext');
      return f.existsSync() ? f.readAsBytesSync() : null;
    }

    final heights = HeightTiles({
      for (final t in tiles)
        if (bytes('heights', t, 'bin') case final b?) HeightTiles.keyOf(t.$1, t.$2): HeightTile.decode(b),
    });
    final pieces = {
      for (final p in bakeTiles(
        roads: [
          for (final t in tiles)
            if (bytes('roads', t, 'mvt') case final b?) (tile: (z: _z, x: t.$1, y: t.$2), bytes: b),
        ],
        ways: [
          for (final t in tiles)
            if (bytes('ways', t, 'mvt') case final b?) (tile: (z: _z, x: t.$1, y: t.$2), bytes: b),
        ],
        heights: heights,
      ))
        (p.x, p.y): p,
    };

    final trails = _trails(trailsDir, heights);
    final rides = _rides(ridesDir);
    for (final r in rides) {
      r.ridden = _riddenBy(r.points, trails);
    }
    final trailM = {for (final t in trails) t.id: t.lengthM};
    // Das Limit, das die Fahrten je Rad gehoben hätten (12.5a, 0.177.0):
    // die höchste Fahrt, abgerundet auf den Schritt, nie unter der Vorgabe.
    double raised(RiderProfile p) => rides
        .where((r) => r.profile == p)
        .map((r) => (r.climbM / LoopPrefs.climbStep).floor() * LoopPrefs.climbStep)
        .fold(p.budgetClimbM, math.max)
        .clamp(LoopPrefs.minClimb, LoopPrefs.maxClimb)
        .toDouble();
    // ignore: avoid_print
    print('Trails ${trails.length}, Fahrten ${rides.length}, Limit Bio ${RiderProfile.bio.budgetClimbM.round()} → '
        '${raised(RiderProfile.bio).round()}, E ${RiderProfile.ebike.budgetClimbM.round()} → '
        '${raised(RiderProfile.ebike).round()}');

    final loops = [
      for (final r in rides)
        if (_dist(r.points.first, r.points.last) <= _loopCloseM && r.climbM >= _minRideClimbM) r,
    ];
    // ignore: avoid_print
    print('| Runde | Rad | gefahren: Zeit, hm, Trail-Anteil | Fall | Pool | Trails | Schätzung | Anteil | hm / Limit '
        '| davon in dieser Runde | davon je gefahren | anders als A |');
    var n = 0;
    for (final ride in loops) {
      final start = ride.points.first;
      final hours = ((ride.movingS / 3600) / LoopPrefs.hoursStep).round() * LoopPrefs.hoursStep;
      final h = hours.clamp(LoopPrefs.minHours, LoopPrefs.maxHours).toDouble();
      final reachM = loopSuggestReachM(h);
      final inReach = [
        for (final t in trails)
          if (_dist(start, t.points.first) <= reachM && _dist(start, t.points.last) <= reachM) t,
      ];
      final box = LatBox.of([start, for (final t in inReach) ...t.points]);
      final frame = roadGraphTiles(box, kTrailHeadMarginM);
      final missing = frame.where((t) => !pieces.containsKey((t.x, t.y))).length;
      n++;
      if (missing > 0) {
        // ignore: avoid_print
        print('| L$n | – | Rahmen nicht geladen ($missing Kacheln fehlen) |');
        continue;
      }
      final built = buildGraphFrom(GraphInput(
        roads: const [],
        pieces: [for (final t in frame) ?pieces[(t.x, t.y)]],
        bake: true,
        trails: [
          for (final t in inReach) GraphTrail(id: t.id, name: t.name, points: t.points, role: TrailRole.downhill),
        ],
        lat0: start.latitude,
      ));
      // Fahrten je Trail aus den anderen Fahrten (die Runde selbst kennt
      // der Planer vor ihr nicht).
      final counts = <String, int>{};
      for (final r in rides) {
        if (identical(r, ride)) continue;
        for (final id in r.ridden) {
          counts[id] = (counts[id] ?? 0) + 1;
        }
      }
      final weighted = [
        for (final t in inReach)
          PoolTrail(
            id: t.id,
            name: t.name,
            points: t.points,
            lengthM: t.lengthM,
            gainM: t.gainM,
            lossM: t.lossM,
            weight: loopPreferenceWeight(rides: counts[t.id] ?? 0),
          ),
      ];
      final strong = [
        for (final t in weighted)
          PoolTrail(
            id: t.id,
            name: t.name,
            points: t.points,
            lengthM: t.lengthM,
            gainM: t.gainM,
            lossM: t.lossM,
            weight: 1 + 3 * (t.weight - 1),
          ),
      ];
      double suggestClimb(double limit) =>
          ((limit * math.min(h, kBudgetHours) / kBudgetHours / LoopPrefs.climbStep).round() * LoopPrefs.climbStep)
              .clamp(LoopPrefs.minClimb, math.max(LoopPrefs.minClimb, limit))
              .toDouble();
      final rideTrailM = ride.ridden.fold(0.0, (s, id) => s + trailM[id]!);
      String hm(double sec) => '${sec ~/ 3600} h ${((sec % 3600) / 60).round().toString().padLeft(2, '0')}';
      Set<String>? baseIds;
      for (final (label, pool, limit, windowS) in [
        ('A', inReach, ride.profile.budgetClimbM, loopWindowFor(h * 3600)),
        ('B', weighted, ride.profile.budgetClimbM, loopWindowFor(h * 3600)),
        ('C', weighted, raised(ride.profile), loopWindowFor(h * 3600)),
        if (h < 2) ('D', inReach, ride.profile.budgetClimbM, kLoopTimeWindowS),
        ('E', strong, ride.profile.budgetClimbM, loopWindowFor(h * 3600)),
      ]) {
        final climb = suggestClimb(limit);
        final plan = planLoop(built.graph,
            start: start,
            profile: ride.profile,
            budget: LoopBudget(timeS: h * 3600, climbM: climb, hikingM: kBudgetHikingKm * 1000, windowS: windowS),
            pool: pool);
        final s = plan.summary;
        final ids = {for (final st in plan.stops) st.trail.id};
        baseIds ??= ids;
        double metresOn(bool Function(String) f) =>
            plan.stops.where((st) => f(st.trail.id)).fold(0.0, (a, st) => a + st.trail.lengthM);
        final all = metresOn((_) => true);
        String pct(double x) => all == 0 ? '–' : '${(x / all * 100).round()} %';
        final why = <LoopExclusion, int>{};
        for (final e in plan.excluded.values) {
          why[e] = (why[e] ?? 0) + 1;
        }
        final share = s == null || s.lengthM == 0 ? null : s.trailM / s.lengthM;
        // ignore: avoid_print
        print('| ${label == 'A' ? 'L$n' : ''} | ${label == 'A' ? ride.profile.name : ''} '
            '| ${label == 'A' ? '${hm(ride.movingS)} · ${ride.climbM.round()} hm · ${(rideTrailM / ride.lengthM * 100).round()} %' : ''} '
            '| $label | ${inReach.length} | ${plan.stops.length} '
            '| ${s == null ? '${plan.outcome.name} (${why.entries.map((e) => '${e.key.name} ${e.value}').join(', ')})' : hm(s.timeS)} | ${share == null ? '–' : '${(share * 100).round()} %'} '
            '| ${s == null ? '–' : '${s.gainM.round()} / ${climb.round()}'} '
            '| ${pct(metresOn(ride.ridden.contains))} | ${pct(metresOn((id) => (counts[id] ?? 0) > 0))} '
            '| ${label == 'A' ? '' : '${ids.difference(baseIds).length + baseIds.difference(ids).length}'} |');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}

/// Die Trail-Sammlung als Pool: jede GPX-Spur bergab gedreht (Höhe aus den
/// Höhenkacheln, sonst aus der Datei), Höhenmeter entlang, ohne Grad und
/// Sterne (die Sammlung trägt keine).
List<PoolTrail> _trails(String dir, HeightTiles heights) {
  final files = Directory(dir).listSync().whereType<File>().where((f) => f.path.endsWith('.gpx')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final out = <PoolTrail>[];
  for (final f in files) {
    final List<GpxTrack> tracks;
    try {
      tracks = parseGpx(f.readAsStringSync());
    } on GpxFormatException {
      continue;
    }
    for (final t in tracks) {
      var pts = [for (final p in t.points) LatLng(p.lat, p.lon)];
      if (pts.length < 2) continue;
      var ele = [
        for (final (i, p) in pts.indexed) heights.heightAt(p) ?? t.points[i].ele ?? double.nan,
      ];
      if (ele.first.isFinite && ele.last.isFinite && ele.last > ele.first) {
        pts = pts.reversed.toList();
        ele = ele.reversed.toList();
      }
      var len = 0.0;
      for (var i = 1; i < pts.length; i++) {
        len += _dist(pts[i - 1], pts[i]);
      }
      final finite = ele.every((e) => e.isFinite);
      final gain = finite ? hysteresisClimb(ele, kClimbHysteresisM).$1 : 0.0;
      final loss = finite ? hysteresisClimb(ele.reversed.toList(), kClimbHysteresisM).$1 : 0.0;
      final k = out.length;
      out.add(PoolTrail(id: 't$k', name: 't$k', points: pts, lengthM: len, gainM: gain, lossM: loss));
    }
  }
  return out;
}

/// Die Fahrten, Rad aus dem Ordner (`bio`, `ebike`): Fahrzeit ohne
/// Stand (Abschnitte unter 1 m/s oder Lücken über einer Minute zählen
/// nicht), Anstieg wie am Ende der Fahrt (Median, Hysterese).
List<_Ride> _rides(String dir) {
  final out = <_Ride>[];
  for (final (sub, profile) in [('bio', RiderProfile.bio), ('ebike', RiderProfile.ebike)]) {
    final d = Directory('$dir/$sub');
    if (!d.existsSync()) continue;
    final files = d.listSync().whereType<File>().where((f) => f.path.endsWith('.gpx')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final tracks = parseGpx(f.readAsStringSync());
      final tp = [for (final t in tracks) ...t.points];
      if (tp.length < 2 || tp.any((p) => p.ele == null)) continue;
      final pts = [for (final p in tp) LatLng(p.lat, p.lon)];
      var moving = 0.0, len = 0.0;
      for (var i = 1; i < tp.length; i++) {
        final dm = _dist(pts[i - 1], pts[i]);
        len += dm;
        final a = tp[i - 1].time, b = tp[i].time;
        if (a == null || b == null) continue;
        final dt = b.difference(a).inMilliseconds / 1000;
        if (dt > 0 && dt <= 60 && dm / dt >= 1.0) moving += dt;
      }
      final climb = hysteresisClimb(smoothElevation([for (final p in tp) p.ele!], kSplitSmoothWindow), kClimbHysteresisM).$1;
      out.add(_Ride(profile, pts, moving, climb, len));
    }
  }
  return out;
}

/// Die Trails, die eine Fahrt befährt: [_riddenShare] ihrer Punkte in
/// [_riddenNearM] um die Spur (Raster aus 50-m-Zellen).
Set<String> _riddenBy(List<LatLng> ride, List<PoolTrail> trails) {
  const cell = 50.0;
  final lat0 = ride.first.latitude;
  final kx = 111320 * math.cos(lat0 * math.pi / 180), ky = 111320.0;
  (int, int) key(LatLng p) => ((p.longitude * kx / cell).floor(), (p.latitude * ky / cell).floor());
  final grid = <(int, int), List<LatLng>>{};
  for (final p in ride) {
    (grid[key(p)] ??= []).add(p);
  }
  bool near(LatLng p) {
    final (cx, cy) = key(p);
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        for (final q in grid[(cx + dx, cy + dy)] ?? const <LatLng>[]) {
          if (_dist(p, q) <= _riddenNearM) return true;
        }
      }
    }
    return false;
  }

  return {
    for (final t in trails)
      if (t.points.where(near).length >= _riddenShare * t.points.length) t.id,
  };
}
