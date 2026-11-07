// Airtime unter Buddys (#36 Schritt 6; docs/konzept-airtime.md 4/5) — pur.
//
// Zwei Richtungen:
// - **Was das Gerät schickt** ([computeAirtimeShare]): aus den EIGENEN
//   Fahrten der Bestwert je Trail und der Zähler der letzten 30 Tage samt
//   den Titeln, die das Gerät vergibt. Gezählt wird nur auf Trails, nach
//   derselben Regel wie „bekannt" im Zerlege-Blatt
//   (`knownTrailSectionsOf`), und nur, was die Erkennung als plausibel
//   behält (`TrailValues.of` über `AirtimeLog.kept`).
// - **Was der Betrachter daraus macht** ([trailAirtimeRanking],
//   [trailKingCounts], [frequentFlyers]): Platz je Trail, Trailkönig,
//   Vielflieger — gerechnet aus dem, was die RLS ihm zeigt. Der Server
//   vergleicht nie über Nutzer hinweg (Konzept 12).
import 'package:latlong2/latlong.dart';

import '../../data/airtime_repository.dart';
import '../../models/trail.dart';
import 'ride_split.dart' show knownTrailSectionsOf;
import 'ride_track.dart';
import 'trail_values.dart';

/// Das Fenster des Zählers (Betreiber 2026-10-16: „rollender Monat").
const kAirtimeWindow = Duration(days: 30);

/// Ab dieser Länge eines Sprungs ist man Segelflieger (Konzept 5,
/// Startwert; Schwellen nach der Messung).
const kGliderJumpS = 1.0;

/// Die Riegel des Servers (`trail_airtime`, Patch 029), in Zehntelsekunden.
const kAirtimeMaxDs = 6000;
const kJumpMaxDs = 600;

/// Eine gemessene Fahrt mit dem, was die Erkennung darauf fand.
/// [measured]: Es gibt Sensordaten — ohne sie sagt eine leere Liste
/// nichts (kein Bodenpersonal aus einer Fahrt ohne Test-Schalter).
typedef MeasuredRide = ({Ride ride, AirtimeLog log, bool measured});

/// Was das Gerät hochlädt.
class AirtimeShare {
  const AirtimeShare({
    required this.bests,
    required this.airDs,
    required this.jumps,
    required this.titles,
  });

  final List<TrailAirtimeUpload> bests;

  /// Airtime und Sprünge der letzten 30 Tage, nur auf Trails.
  final int airDs;
  final int jumps;
  final Set<AirtimeTitle> titles;
}

int _ds(double s) => (s * 10).round();

/// Rechnet aus den eigenen Fahrten, was geteilt wird. [trails] ist das
/// Netz, das ich sehe — nur darauf gibt es einen Bestwert.
AirtimeShare computeAirtimeShare({
  required List<MeasuredRide> rides,
  required List<Trail> trails,
  required DateTime now,
}) {
  final best = <String, ({int air, int longest, DateTime month})>{};
  var windowAir = 0.0;
  var windowJumps = 0;
  var windowMeasured = false;
  var glider = false;
  final since = now.subtract(kAirtimeWindow);
  for (final (:ride, :log, :measured) in rides) {
    if (ride.planned || ride.imported || !measured || ride.points.length < 2) continue;
    final inWindow = ride.startedAt.isAfter(since) && !ride.startedAt.isAfter(now);
    if (inWindow) windowMeasured = true;
    if (log.isEmpty) continue;
    final latLng = [for (final p in ride.points) LatLng(p.lat, p.lng)];
    for (final s in knownTrailSectionsOf(latLng, trails)) {
      final v = TrailValues.of(log.kept,
          fromUs: ride.points[s.start].at.microsecondsSinceEpoch,
          toUs: ride.points[s.end].at.microsecondsSinceEpoch);
      if (v.jumps == 0) continue;
      if (inWindow) {
        windowAir += v.airS;
        windowJumps += v.jumps;
        if (v.longestJumpS >= kGliderJumpS) glider = true;
      }
      final air = _ds(v.airS).clamp(1, kAirtimeMaxDs);
      final longest = _ds(v.longestJumpS).clamp(1, kJumpMaxDs).clamp(1, air);
      final month = DateTime(ride.startedAt.year, ride.startedAt.month);
      final old = best[s.trail.id];
      if (old == null) {
        best[s.trail.id] = (air: air, longest: longest, month: month);
      } else {
        best[s.trail.id] = (
          air: air > old.air ? air : old.air,
          longest: longest > old.longest ? longest : old.longest,
          month: air > old.air ? month : old.month,
        );
      }
    }
  }
  return AirtimeShare(
    bests: [
      for (final e in best.entries)
        TrailAirtimeUpload(trailId: e.key, airDs: e.value.air, longestDs: e.value.longest, month: e.value.month),
    ],
    airDs: _ds(windowAir),
    jumps: windowJumps,
    titles: {
      if (glider) AirtimeTitle.glider,
      if (windowMeasured && windowJumps == 0) AirtimeTitle.groundCrew,
    },
  );
}

/// Zeigt die App einen Zähler noch? Nach 30 Tagen ohne neuen Stand nicht
/// mehr (Konzept 4: das Fenster rückt nicht ohne sein Gerät weiter).
bool airtimeCounterFresh(AirtimeCounter c, DateTime now) =>
    // Im Kalender gerechnet, nicht mit `subtract`: über die Zeitumstellung
    // läge die Grenze sonst eine Stunde neben Mitternacht.
    !c.asOf.isBefore(DateTime(now.year, now.month, now.day - kAirtimeWindow.inDays));

/// Ein Platz in der Rangliste eines Trails.
class AirtimeRank {
  const AirtimeRank({required this.place, required this.best});

  /// 1-basiert; gleiche Airtime, gleicher Platz.
  final int place;
  final TrailAirtime best;
}

/// Die Rangliste eines Trails, beste Airtime je Durchfahrt zuerst (Konzept
/// 5: gewertet wird die Summe, nicht der längste Sprung). Bei Gleichstand
/// steht der frühere Monat vorn — wer es zuerst schaffte.
List<AirtimeRank> trailAirtimeRanking(Iterable<TrailAirtime> bests, String trailId) {
  final rows = [for (final b in bests) if (b.trailId == trailId) b]
    ..sort((a, b) {
      final c = b.airDs.compareTo(a.airDs);
      return c != 0 ? c : a.month.compareTo(b.month);
    });
  final out = <AirtimeRank>[];
  for (var i = 0; i < rows.length; i++) {
    final place = i > 0 && rows[i].airDs == rows[i - 1].airDs ? out[i - 1].place : i + 1;
    out.add(AirtimeRank(place: place, best: rows[i]));
  }
  return out;
}

/// Was die Zeile im Trail-Blatt zeigt: die ersten drei und, wenn er
/// dahinter liegt, der eigene Platz (Konzept 5).
List<AirtimeRank> airtimeRankingShown(List<AirtimeRank> ranking, String myId) {
  final top = ranking.take(3).toList();
  final mine = ranking.where((r) => r.best.userId == myId).firstOrNull;
  if (mine != null && !top.contains(mine)) top.add(mine);
  return top;
}

/// Trailkönig: je Nutzer die Zahl der Trails, auf denen er vorn liegt —
/// nur, wo mindestens zwei Werte stehen (allein ist man kein König).
Map<String, int> trailKingCounts(Iterable<TrailAirtime> bests) {
  final byTrail = <String, List<TrailAirtime>>{};
  for (final b in bests) {
    (byTrail[b.trailId] ??= []).add(b);
  }
  final out = <String, int>{};
  for (final e in byTrail.entries) {
    if (e.value.length < 2) continue;
    for (final r in trailAirtimeRanking(e.value, e.key)) {
      if (r.place != 1) break;
      out[r.best.userId] = (out[r.best.userId] ?? 0) + 1;
    }
  }
  return out;
}

/// Vielflieger: wer unter den gezeigten Zählern die meisten Sprünge hat
/// (mindestens einen, mindestens zwei Zähler im Vergleich).
Set<String> frequentFlyers(Iterable<AirtimeCounter> counters, DateTime now) {
  final fresh = [for (final c in counters) if (airtimeCounterFresh(c, now)) c];
  if (fresh.length < 2) return const {};
  final most = fresh.map((c) => c.jumps).reduce((a, b) => a > b ? a : b);
  if (most == 0) return const {};
  return {for (final c in fresh) if (c.jumps == most) c.userId};
}
