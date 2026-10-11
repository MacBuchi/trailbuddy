// Duplikate zusammenführen (#107, Patch 019; Regel in
// `docs/konzept-trails.md` 6.1): was `trail_merges()` dem Leser über
// Duplikate sagt, und wie der Client daraus EINE Zuordnung je Trail macht.
//
// Der Server liefert nur Paare, die der Leser beide sieht. Ketten und
// Gegenrichtungen löst er bewusst nicht auf — das tut [resolveMerges],
// eigene Zeilen zuerst, bei Gegenrichtungen gewinnt der ältere Trail.

/// Was eine Zeile aus `trail_merges()` sagt.
enum TrailMergeKind {
  /// Meine Zuordnung: [TrailMerge.trailId] ist für mich ein Duplikat von
  /// [TrailMerge.sameAs].
  own('own'),

  /// Mein „das sind verschiedene" (das Paar geordnet).
  distinct('distinct'),

  /// Direkte Buddys halten [TrailMerge.trailId] für ein Duplikat, und ich
  /// habe daran selbst etwas: Ich entscheide (#107 Schritt 3).
  proposed('proposed'),

  /// Dasselbe, aber ich habe an [TrailMerge.trailId] nichts: Er erscheint
  /// bei mir unter [TrailMerge.sameAs], ohne Frage.
  folded('folded'),

  /// Eine Kante aus dem Abgleich zwischen zwei sichtbaren Trails, von
  /// denen ich einen selbst habe — Vorrat für „Sind das dieselben?".
  overlap('overlap');

  const TrailMergeKind(this.db);
  final String db;

  static TrailMergeKind? fromDb(String? v) => values.where((k) => k.db == v).firstOrNull;
}

/// Eine Zeile aus `trail_merges()` (Patch 019).
class TrailMerge {
  const TrailMerge({
    required this.trailId,
    required this.sameAs,
    required this.kind,
    this.reversed = false,
    this.byUsers = const [],
  });

  final String trailId;
  final String sameAs;
  final TrailMergeKind kind;

  /// Läuft [trailId] gegen [sameAs]? Nur bei Zuordnungen bekannt.
  final bool reversed;

  /// Wer die Zuordnung erklärt hat, die älteste Erklärung zuerst — nur
  /// bei [TrailMergeKind.proposed] und [TrailMergeKind.folded].
  final List<String> byUsers;

  /// null, wenn die Zeile zu diesem Stand nicht passt (unbekannte Art) —
  /// eine neuere Datenbank darf eine ältere App nicht umwerfen.
  static TrailMerge? fromJson(Map<String, dynamic> json) {
    final kind = TrailMergeKind.fromDb(json['kind'] as String?);
    final trailId = json['trail_id'], sameAs = json['same_as'];
    if (kind == null || trailId is! String || sameAs is! String) return null;
    final by = json['by_users'];
    return TrailMerge(
      trailId: trailId,
      sameAs: sameAs,
      kind: kind,
      reversed: json['reversed'] == true,
      byUsers: by is List ? [for (final u in by) if (u is String) u] : const [],
    );
  }

  Map<String, dynamic> toRow() => {
        'trail_id': trailId,
        'same_as': sameAs,
        'reversed': reversed,
        'kind': kind.db,
        'by_users': byUsers.isEmpty ? null : byUsers,
      };
}

/// Wohin ein Duplikat bei mir gehört — Ergebnis von [resolveMerges].
class MergeTarget {
  const MergeTarget({
    required this.to,
    required this.reversed,
    required this.byMe,
    this.byUsers = const [],
  });

  /// Der behaltene Trail, Ketten zu Ende gegangen.
  final String to;

  /// Läuft das Duplikat gegen [to]? Über die ganze Kette gerechnet.
  final bool reversed;

  /// Die erste Zuordnung der Kette ist meine eigene — nur dann lässt sie
  /// sich lösen (`unmerge_trail`).
  final bool byMe;

  /// Wer die erste Zuordnung der Kette erklärt hat, wenn nicht ich.
  final List<String> byUsers;
}

/// Macht aus den Zeilen von `trail_merges()` EINE Zuordnung je Duplikat:
/// Nur `own` und `folded` verschieben etwas (ein Vorschlag wartet auf
/// meine Entscheidung). Regeln (Konzept 6.1):
///
/// - Meine eigene Zuordnung geht jeder fremden vor.
/// - Mehrere fremde Ziele für dasselbe Duplikat: das mit mehr
///   Erklärenden, bei Gleichstand der ältere Trail.
/// - Ketten (B → A → C) gehen bis zum Ende, die Richtung mit.
/// - Ein Kreis (B → A und A → B): Von den Trails im Kreis mit FREMDER
///   Zuordnung bleibt der älteste stehen — seine Zuordnung fällt weg.
///   Eine eigene fällt nie (eigene Zeilen allein bilden keinen Kreis,
///   `merge_own_into` hält sie flach).
///
/// [ageOf] sagt, wann ein Trail angelegt wurde (die älteste sichtbare
/// Aufzeichnung); unbekannt zählt als jüngster.
Map<String, MergeTarget> resolveMerges(Iterable<TrailMerge> merges,
    {required DateTime? Function(String trailId) ageOf}) {
  // Eine Kante je Duplikat.
  final edges = <String, ({TrailMerge row, bool own})>{};
  final folded = <String, List<TrailMerge>>{};
  for (final m in merges) {
    if (m.trailId == m.sameAs) continue;
    switch (m.kind) {
      case TrailMergeKind.own:
        edges[m.trailId] = (row: m, own: true);
      case TrailMergeKind.folded:
        (folded[m.trailId] ??= []).add(m);
      case TrailMergeKind.distinct || TrailMergeKind.proposed || TrailMergeKind.overlap:
        break;
    }
  }
  int byAge(String a, String b) {
    final x = ageOf(a), y = ageOf(b);
    if (x == null || y == null) return x == null ? (y == null ? a.compareTo(b) : 1) : -1;
    final c = x.compareTo(y);
    return c != 0 ? c : a.compareTo(b);
  }

  for (final e in folded.entries) {
    if (edges.containsKey(e.key)) continue;
    final rows = List.of(e.value)
      ..sort((a, b) {
        final c = b.byUsers.length.compareTo(a.byUsers.length);
        return c != 0 ? c : byAge(a.sameAs, b.sameAs);
      });
    edges[e.key] = (row: rows.first, own: false);
  }

  // Kreise brechen: je Kreis fällt die fremde Kante des ältesten Trails,
  // der eine hat. Wiederholt, bis keiner mehr da ist.
  var changed = true;
  while (changed) {
    changed = false;
    final done = <String>{};
    for (final start in edges.keys.toList()) {
      if (done.contains(start)) continue;
      final path = <String>[];
      final onPath = <String>{};
      var at = start;
      while (edges.containsKey(at) && !done.contains(at) && onPath.add(at)) {
        path.add(at);
        at = edges[at]!.row.sameAs;
      }
      done.addAll(path);
      if (!onPath.contains(at)) continue;
      final cycle = path.sublist(path.indexOf(at));
      final breakable = [for (final t in cycle) if (!edges[t]!.own) t]..sort(byAge);
      final drop = breakable.isNotEmpty ? breakable.first : (List.of(cycle)..sort(byAge)).first;
      edges.remove(drop);
      changed = true;
      break;
    }
  }

  final out = <String, MergeTarget>{};
  for (final e in edges.entries) {
    var to = e.value.row.sameAs;
    var reversed = e.value.row.reversed;
    final seen = {e.key};
    while (seen.add(to)) {
      final next = edges[to];
      if (next == null) break;
      reversed = reversed != next.row.reversed;
      to = next.row.sameAs;
    }
    out[e.key] = MergeTarget(
      to: to,
      reversed: reversed,
      byMe: e.value.own,
      byUsers: e.value.own ? const [] : e.value.row.byUsers,
    );
  }
  return out;
}
