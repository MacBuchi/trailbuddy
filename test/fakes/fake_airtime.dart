import 'package:trailbuddy/data/airtime_repository.dart';

import 'fake_backend.dart';
import 'fake_trails.dart';

/// Airtime unter Buddys im Speicher (Patch 029). Spiegelt `ta_select`
/// (eigene, sonst Buddy, der den Trail teilt, auf einem Trail, den ich
/// sehe), `ac_select` (eigener und der von Buddys) und `set_trail_airtime`
/// (nur besser, nur sichtbare Trails). Ohne [trails] gilt jeder Trail als
/// sichtbar und geteilt.
class FakeAirtimeRepository implements AirtimeRepository {
  FakeAirtimeRepository(this.backend, {this.trails});

  final FakeBackend backend;
  final FakeTrailRepository? trails;

  final bests = <TrailAirtime>[];
  final counters = <AirtimeCounter>[];
  int uploadCalls = 0;
  int deleteCalls = 0;

  String get _uid => backend.currentUserId!;

  bool _sees(String trailId) => trails?.canSeeTrail(trailId) ?? true;

  @override
  Future<List<TrailAirtime>> fetchBests() async {
    backend.failIfOffline();
    return [
      for (final b in bests)
        if (b.userId == _uid ||
            (backend.areFriends(_uid, b.userId) &&
                (trails?.sharedBy(b.userId, b.trailId) ?? true) &&
                _sees(b.trailId)))
          b,
    ];
  }

  @override
  Future<List<AirtimeCounter>> fetchCounters() async {
    backend.failIfOffline();
    return [for (final c in counters) if (c.userId == _uid || backend.areFriends(_uid, c.userId)) c];
  }

  @override
  Future<int> uploadBests(List<TrailAirtimeUpload> items) async {
    backend.failIfOffline();
    uploadCalls++;
    var n = 0;
    for (final it in items) {
      if (!_sees(it.trailId)) continue;
      final month = DateTime(it.month.year, it.month.month);
      final i = bests.indexWhere((b) => b.userId == _uid && b.trailId == it.trailId);
      if (i < 0) {
        bests.add(TrailAirtime(userId: _uid, trailId: it.trailId, airDs: it.airDs, longestDs: it.longestDs, month: month));
        n++;
        continue;
      }
      final cur = bests[i];
      if (it.airDs <= cur.airDs && it.longestDs <= cur.longestDs) continue;
      bests[i] = TrailAirtime(
        userId: _uid,
        trailId: it.trailId,
        airDs: it.airDs > cur.airDs ? it.airDs : cur.airDs,
        longestDs: it.longestDs > cur.longestDs ? it.longestDs : cur.longestDs,
        month: it.airDs > cur.airDs ? month : cur.month,
      );
      n++;
    }
    return n;
  }

  @override
  Future<void> setCounter({
    required int airDs,
    required int jumps,
    required DateTime asOf,
    required Set<AirtimeTitle> titles,
  }) async {
    backend.failIfOffline();
    counters.removeWhere((c) => c.userId == _uid);
    counters.add(AirtimeCounter(
        userId: _uid, airDs: airDs, jumps: jumps, asOf: DateTime(asOf.year, asOf.month, asOf.day), titles: titles));
  }

  @override
  Future<void> deleteMine() async {
    backend.failIfOffline();
    deleteCalls++;
    bests.removeWhere((b) => b.userId == _uid);
    counters.removeWhere((c) => c.userId == _uid);
  }
}
