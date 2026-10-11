// „Sind das dieselben?" (#107 Schritt 3, Konzept 6.1): welche Paare die
// App mir vorschlägt. Pur, ohne Widgets.
//
// Zwei Quellen, beide nur für Paare, die ich ohnehin beide sehe:
//
// - **Erklärt**: Ein direkter Buddy hält einen Trail, an dem ich selbst
//   etwas habe, für ein Duplikat eines anderen (`trail_merges()`,
//   `proposed`). Er hat beim Erklären „grob beieinander" bestanden — der
//   Vorschlag steht ohne weitere Prüfung.
// - **Aus dem Abgleich**: eine Overlap-Kante zwischen zwei sichtbaren
//   Trails, von denen ich einen habe (`overlap`). Gezeigt nur, wenn die
//   beiden auch grob beieinander liegen (Betreiber, 2026-10-11) — Gabeln
//   und Nachbarn mit 30 % Deckung sind keine Duplikate.
//
// Dazu der Sonderfall „liegt ganz in meinem" (Rework §7): Deckt meine
// längere Linie die andere im Korridor des Abgleichs, ist meine meist die
// Fassung mit Anfahrt — dann ist „auf den gemeinsamen Teil kürzen" der
// bessere Weg als Zusammenführen.
import 'package:latlong2/latlong.dart';

import '../../core/line_geometry.dart';
import '../../models/trail.dart';
import '../../models/trail_merge.dart';
import 'trail_merge_candidates.dart';

/// Woher ein Vorschlag kommt.
enum ProposalSource { declared, overlap }

/// Ein Paar „Sind das dieselben?".
class MergeProposal {
  const MergeProposal({
    required this.duplicate,
    required this.target,
    required this.source,
    required this.share,
    this.byUsers = const [],
    this.trimmable,
  });

  /// Der, der wegginge — bei einer Erklärung der, den der Buddy für das
  /// Duplikat hält; aus dem Abgleich der, den [defaultKeep] nicht wählt.
  final Trail duplicate;

  /// Der, der bliebe.
  final Trail target;

  final ProposalSource source;

  /// [mergeNearShare] der beiden — für die Anzeige.
  final double share;

  /// Wer es erklärt hat, die älteste Erklärung zuerst (nur [ProposalSource.declared]).
  final List<String> byUsers;

  /// Mein eigener Trail, der den anderen ganz enthält — dann bietet die
  /// App „auf gemeinsamen Teil kürzen" an.
  final Trail? trimmable;

  /// Das Paar, unabhängig von der Richtung.
  String get key => pairKey(duplicate.id, target.id);

  /// Gehört [trailId] zu diesem Paar — auch als Kennung von früher?
  bool involves(String trailId) => duplicate.answersTo(trailId) || target.answersTo(trailId);

  /// Der andere aus Sicht von [trailId].
  Trail otherThan(String trailId) => duplicate.answersTo(trailId) ? target : duplicate;
}

/// Ein Paar als Schlüssel, geordnet wie in `trail_distinct`.
String pairKey(String a, String b) => a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';

/// Die Vorschläge aus [rows] über [trails] (dem angezeigten Netz, nach den
/// Zuordnungen): erklärte zuerst, dann nach Anteil. Je Paar einer.
List<MergeProposal> mergeProposals(Iterable<Trail> trails, Iterable<TrailMerge> rows) {
  final list = [for (final t in trails) if (!t.pending) t];
  final byId = {for (final t in list) t.id: t};
  Trail? find(String id) => byId[id] ?? list.where((t) => t.answersTo(id)).firstOrNull;

  final out = <String, MergeProposal>{};
  for (final r in rows) {
    if (r.kind != TrailMergeKind.proposed) continue;
    final dup = find(r.trailId), target = find(r.sameAs);
    if (dup == null || target == null || identical(dup, target) || dup.id == target.id) continue;
    final key = pairKey(dup.id, target.id);
    final prev = out[key];
    out[key] = MergeProposal(
      duplicate: dup,
      target: target,
      source: ProposalSource.declared,
      share: prev?.share ?? mergeNearShare(dup.points, target.points),
      byUsers: [...?prev?.byUsers, ...r.byUsers.where((u) => !(prev?.byUsers.contains(u) ?? false))],
      trimmable: prev?.trimmable ?? trimmableOf(dup, target),
    );
  }
  for (final r in rows) {
    if (r.kind != TrailMergeKind.overlap) continue;
    final a = find(r.trailId), b = find(r.sameAs);
    if (a == null || b == null || a.id == b.id) continue;
    final key = pairKey(a.id, b.id);
    if (out.containsKey(key)) continue;
    final share = mergeNearShare(a.points, b.points);
    if (share < kMergeNearShare) continue;
    final keep = defaultKeep(a, b);
    out[key] = MergeProposal(
      duplicate: identical(keep, a) ? b : a,
      target: keep,
      source: ProposalSource.overlap,
      share: share,
      trimmable: trimmableOf(a, b),
    );
  }
  return out.values.toList()
    ..sort((x, y) {
      if (x.source != y.source) return x.source.index.compareTo(y.source.index);
      final c = y.share.compareTo(x.share);
      return c != 0 ? c : x.key.compareTo(y.key);
    });
}

/// Mein Trail von [a] und [b], der den anderen GANZ enthält und selbst
/// deutlich mehr ist — die lange Fassung mit Anfahrt. Mit den Schwellen
/// des Abgleichs (`kMatchCorridorM`, `kMatchCoverage`): Deckt er die
/// andere so, dass der Server ein abgeschnittenes Stück von ihm mit ihr
/// verschmelzen würde, ist Kürzen der Weg. null, wenn keiner das ist.
Trail? trimmableOf(Trail a, Trail b) {
  for (final (outer, inner) in [(a, b), (b, a)]) {
    if (!outer.recordings.any((r) => r.userId == outer.myId)) continue;
    if (lineCovers(outer.points, inner.points) && !lineCovers(inner.points, outer.points)) {
      return outer;
    }
  }
  return null;
}

/// Liegt [inner] zu mindestens [kMatchCoverage] im Korridor
/// [kMatchCorridorM] um [outer]?
bool lineCovers(List<LatLng> outer, List<LatLng> inner) {
  if (outer.length < 2 || inner.length < 2) return false;
  final proj = FlatProjection.around([...outer, ...inner]);
  final samples = resampleXy(proj.line(inner), kMatchSampleStepM);
  final grid = SegmentGrid([proj.line(outer)], kMatchCorridorM);
  return coverageWithin(samples, grid, kMatchCorridorM) >= kMatchCoverage;
}
