// Die Zusammenfassung nach dem Annehmen einer Buddy-Anfrage (Konzept 6,
// #33 Teil 1): „14 Trails gemeinsam, 8 neu von Jan, 5 neu für Jan".
//
// NACH dem Annehmen, nie davor: Vorher wäre die Zahl ein Orakel über den
// Bestand eines Fremden. Gerechnet auf dem Gerät aus den zwei sichtbaren
// Ständen — dem vor und dem nach dem Neuladen —, nicht auf dem Server:
// Eine Aggregation über Netzgrenzen darf es nicht geben (Konzept 12),
// und was ICH sehe, darf ich zählen.
//
// Pur: Trails rein, Zahlen raus.
import '../../l10n/l10n.dart';
import '../../models/trail.dart';

class ConnectSummary {
  const ConnectSummary({
    required this.shared,
    required this.newFromBuddy,
    required this.newForBuddy,
  });

  /// Trails, die beide belegt haben — EIN Trail auf beiden Karten.
  final int shared;

  /// Trails, die erst mit dem Buddy sichtbar wurden.
  final int newFromBuddy;

  /// Eigene Trails, die der Buddy noch nicht belegt hat und jetzt sieht
  /// — soweit von hier aus erkennbar: Was er über ANDERE Buddys schon
  /// sah, wissen wir nicht (keine Transitivität, kein Blick in sein Netz).
  final int newForBuddy;

  bool get isEmpty => shared == 0 && newFromBuddy == 0 && newForBuddy == 0;

  /// „Mit Jan verbunden: 14 Trails gemeinsam, 8 neu von Jan, 5 neu für Jan."
  String sentence(AppLocalizations l, String buddyName) => isEmpty
      ? l.buddysConnectSummaryEmpty(buddyName)
      : l.buddysConnectSummary(buddyName, shared, newFromBuddy, newForBuddy);
}

ConnectSummary summarizeConnection({
  required List<Trail> before,
  required List<Trail> after,
  required String myId,
  required String buddyId,
}) {
  final knownBefore = {for (final t in before) t.id};
  var shared = 0, fromBuddy = 0, forBuddy = 0;
  for (final t in after) {
    if (t.pending) continue;
    final mine = t.recordings.any((r) => r.userId == myId);
    final theirs = t.recordings.any((r) => r.userId == buddyId);
    if (mine && theirs) {
      shared++;
    } else if (theirs && !knownBefore.contains(t.id)) {
      fromBuddy++;
    } else if (mine && !theirs && t.myDetails?.visibility != TrailVisibility.private) {
      forBuddy++;
    }
  }
  return ConnectSummary(shared: shared, newFromBuddy: fromBuddy, newForBuddy: forBuddy);
}

/// „14 gemeinsam" je Buddy (Design 1k): Trails, die ich UND er belegt
/// haben — dieselbe Regel wie [ConnectSummary.shared], gezählt aus dem,
/// was ich ohnehin sehe. Wartende zählen nicht, sie haben noch keinen
/// Trail.
Map<String, int> sharedTrailCounts(List<Trail> trails, String myId) {
  final counts = <String, int>{};
  for (final t in trails) {
    if (t.pending || !t.recordings.any((r) => r.userId == myId)) continue;
    for (final u in {for (final r in t.recordings) r.userId}) {
      if (u != myId) counts[u] = (counts[u] ?? 0) + 1;
    }
  }
  return counts;
}
