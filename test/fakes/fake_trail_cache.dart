// Die Kopie des Netzes im Test (#32): im Speicher, mit Zählern.
import 'package:trailbuddy/data/trail_cache.dart';

class FakeTrailCache implements TrailCache {
  String? uid;
  TrailSnapshot? snapshot;
  DateTime? savedAt;
  int writes = 0;
  int clears = 0;

  @override
  Future<({TrailSnapshot snapshot, DateTime savedAt})?> read({
    required String uid,
  }) async {
    if (snapshot == null || this.uid != uid) return null;
    return (snapshot: snapshot!, savedAt: savedAt!);
  }

  @override
  Future<void> write({
    required String uid,
    required TrailSnapshot snapshot,
    required DateTime savedAt,
  }) async {
    writes++;
    this.uid = uid;
    this.snapshot = snapshot;
    this.savedAt = savedAt;
  }

  @override
  Future<void> clear() async {
    clears++;
    snapshot = null;
    savedAt = null;
  }
}
