// Ein Neuladen des Netzes behält, was sich nicht geändert hat — als
// DASSELBE Objekt (Feldbericht 2026-10-02: Hänger nach „Mein Beitrag").
//
// Jeder Abruf baut alle Aufzeichnungen, Beiträge, Hinweise und Meldungen
// neu, auch wenn sich nur ein Stern geändert hat. An der Identität hängen
// aber die teuren Zwischenspeicher: die geglättete Linie und ihre
// MapLibre-Ebene (dieselbe Punktliste ⇒ keine Übertragung), das
// Höhenprofil (`Trail.elevation`), die Deckung mit offiziellen Trails im
// Blatt. Ohne diese Datei rechnete die Karte nach jedem Speichern das
// ganze Netz neu und schickte jede Linie noch einmal als GeoJSON an die
// Engine — gemessen an 600 Trails rund 1 s allein dafür, auf dem
// Haupt-Thread.
//
// „Gleich" heißt: dieselbe Zeile, wie der Zwischenspeicher sie ablegt
// (`trail_cache.dart`) — eine Regel, die schon für den Rundlauf
// Datei ↔ Modell Feld für Feld geprüft ist. Bei den Aufzeichnungen kommen
// die Punkte dazu, ohne den Umweg über JSON.
import 'dart:convert';

import '../models/trail.dart';
import 'trail_cache.dart';

/// [next] mit den Objekten aus [previous], wo sie gleich sind. Was neu
/// oder geändert ist, kommt aus [next]; Reihenfolge und Länge bleiben die
/// von [next].
TrailSnapshot shareSnapshot(TrailSnapshot? previous, TrailSnapshot next) {
  if (previous == null) return next;
  return (
    recordings: _share(previous.recordings, next.recordings, (r) => r.id, sameRecording),
    details: _share(previous.details, next.details, (d) => '${d.trailId}|${d.userId}',
        (a, b) => _sameRow(detailsToRow(a), detailsToRow(b))),
    notes: _share(previous.notes, next.notes, (n) => n.id, (a, b) => _sameRow(noteToRow(a), noteToRow(b))),
    reports: _share(previous.reports, next.reports, (r) => r.id, (a, b) => _sameRow(a.toRow(), b.toRow())),
    merges: _share(previous.merges, next.merges, (m) => '${m.kind.db}|${m.trailId}|${m.sameAs}',
        (a, b) => _sameRow(a.toRow(), b.toRow())),
  );
}

/// Ob [a] und [b] alle fünf Listen mit denselben Objekten tragen — dann
/// hat sich am Netz nichts geändert, und die Kopie auf dem Gerät muss
/// nicht neu geschrieben werden.
bool sameSnapshot(TrailSnapshot a, TrailSnapshot b) =>
    _sameItems(a.recordings, b.recordings) &&
    _sameItems(a.details, b.details) &&
    _sameItems(a.notes, b.notes) &&
    _sameItems(a.reports, b.reports) &&
    _sameItems(a.merges, b.merges);

/// Dieselbe Aufzeichnung, Punkt für Punkt.
bool sameRecording(TrailRecording a, TrailRecording b) {
  if (identical(a, b)) return true;
  if (a.id != b.id ||
      a.trailId != b.trailId ||
      a.userId != b.userId ||
      a.source != b.source ||
      a.recordedAt != b.recordedAt ||
      a.reversed != b.reversed ||
      a.quality != b.quality ||
      a.createdAt != b.createdAt ||
      a.lengthM != b.lengthM ||
      a.points.length != b.points.length) {
    return false;
  }
  for (var i = 0; i < a.points.length; i++) {
    final p = a.points[i], q = b.points[i];
    if (p.latitude != q.latitude || p.longitude != q.longitude) return false;
  }
  final ae = a.ele, be = b.ele;
  if (ae == null || be == null) return ae == null && be == null;
  if (ae.length != be.length) return false;
  for (var i = 0; i < ae.length; i++) {
    if (ae[i] != be[i]) return false;
  }
  return true;
}

List<T> _share<T>(List<T> previous, List<T> next, String Function(T) key, bool Function(T, T) same) {
  if (previous.isEmpty) return next;
  final byKey = {for (final p in previous) key(p): p};
  return [
    for (final n in next)
      if (byKey[key(n)] case final p? when identical(p, n) || same(p, n)) p else n,
  ];
}

bool _sameItems<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i])) return false;
  }
  return true;
}

// Kleine Zeilen: als Text verglichen, damit Listen und Unterobjekte
// (Merkmale, Embed des Namens) ohne eigene Gleichheit mitzählen.
bool _sameRow(Map<String, dynamic> a, Map<String, dynamic> b) => jsonEncode(a) == jsonEncode(b);
