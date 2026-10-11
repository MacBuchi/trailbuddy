// Messung, kein Test im normalen Lauf (kein `_test.dart`): Was kostet es
// den Haupt-Thread, wenn nach einem gespeicherten Stern das Netz neu
// geladen wird — vor und nach dem Umbau vom 2026-10-02 (Feldbericht
// „abgestürzt beim Eintragen von Trail-Details", ANR aus 0.82.0)?
//
//   flutter test test/perf/network_reload_measure.dart
//
// Gemessen auf dem Rechner im Debug-Modus; ein Telefon ist langsamer. Die
// Linien sind ein Zufallsweg und damit ecken­reicher als echte Trails —
// die Glättung legt hier mehr Punkte an als im Feld.
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart' as ml;
import 'package:trailbuddy/data/trail_cache.dart';
import 'package:trailbuddy/data/trail_sharing.dart';
import 'package:trailbuddy/features/map/line_smoothing.dart';
import 'package:trailbuddy/features/map/map_view/keyed_layers.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/map/map_view/maplibre_map_view.dart';
import 'package:trailbuddy/models/trail.dart';
import 'package:trailbuddy/models/trail_merge.dart';

List<Map<String, dynamic>> rows(int trails, int pts) {
  final rnd = Random(1);
  final out = <Map<String, dynamic>>[];
  for (var t = 0; t < trails; t++) {
    for (var k = 0; k < 1 + t % 2; k++) {
      var lat = 47 + rnd.nextDouble(), lon = 11 + rnd.nextDouble();
      final coords = <List<double>>[];
      final ele = <double>[];
      for (var i = 0; i < pts; i++) {
        lat += (rnd.nextDouble() - 0.5) * 1e-4;
        lon += (rnd.nextDouble() - 0.5) * 1e-4;
        coords.add([lon, lat]);
        ele.add(1000 - i * 0.5 + rnd.nextDouble());
      }
      out.add({
        'id': 'r$t-$k', 'trail_id': 't$t', 'user_id': 'u$k', 'source': 'import',
        'recorded_at': '2026-09-01T10:00:00Z', 'reversed': false, 'quality': 1.0,
        'created_at': '2026-09-01T10:00:00Z',
        'geojson': jsonEncode({'type': 'LineString', 'coordinates': coords}),
        'length_m': 2000.0, 'ele': ele,
      });
    }
  }
  return out;
}

const _colors = [Colors.green, Colors.blue, Colors.red, Colors.black];

List<MapViewPolyline> linesOf(List<Trail> trails, List<LatLng> Function(Trail) smoothed) => [
      for (final t in trails)
        MapViewPolyline(points: smoothed(t), color: _colors[(t.grade ?? 0) % 4], label: t.displayName),
    ];

int textBytes(Iterable<ml.Layer> layers) =>
    layers.fold(0, (n, l) => n + ml.FeatureCollection(l.list).toText().length);

void main() {
  test('Neuladen nach einem Stern messen', () {
    const n = 600, p = 400;
    final raw = jsonEncode(rows(n, p));
    List<TrailDetails> details(int ratingOf0) => [
          for (var t = 0; t < n; t++)
            TrailDetails(trailId: 't$t', userId: 'u0', name: 'Trail $t', grade: t % 4, rating: t == 0 ? ratingOf0 : null),
        ];
    TrailSnapshot fetch(int rating) => (
          recordings: [for (final r in (jsonDecode(raw) as List).cast<Map<String, dynamic>>()) TrailRecording.fromJson(r)],
          details: details(rating),
          notes: <TrailNote>[],
          reports: <TrailReport>[],
          merges: <TrailMerge>[],
        );
    final sw = Stopwatch()..start();
    int lap() {
      final ms = sw.elapsedMilliseconds;
      sw.reset();
      return ms;
    }

    // Erster Stand: so wie die App ihn beim Start hat.
    final s1 = fetch(3);
    final t1 = buildTrails(recordings: s1.recordings, details: s1.details, myId: 'u0');
    final smooth = Expando<List<LatLng>>();
    List<LatLng> smoothed(Trail t) => smooth[t.points] ??= chaikinSmooth(t.points);
    final cache = MapLibreLineCache();
    final onMap = <String, ({int slot, ml.Layer layer})>{};
    var slots = 0;
    planLayerOps(onMap, mapLibreKeyedLayers(MapViewLayers(polylines: linesOf(t1, smoothed)), cache), () => slots++);
    lap();

    // BIS 0.82.0: das ganze Netz neu, neue Objekte, alles neu geglättet,
    // jede Linie neu als Text (der positionsweise Abgleich des Pakets).
    final s2 = fetch(5);
    final tFetch = lap();
    final t2 = buildTrails(recordings: s2.recordings, details: s2.details, myId: 'u0');
    for (final t in t2) {
      t.elevation;
    }
    final oldSmooth = Expando<List<LatLng>>();
    final oldLines = [
      for (final t in t2)
        MapViewPolyline(points: oldSmooth[t] ??= chaikinSmooth(t.points), color: _colors[(t.grade ?? 0) % 4], label: t.displayName),
    ];
    final oldLayers = mapLibrePolylineLayers(oldLines);
    final oldBytes = textBytes(oldLayers);
    final tOldMap = lap();
    encodeTrailCache(uid: 'u0', snapshot: s2, savedAt: DateTime.now());
    final tOldCache = lap();

    // AB 0.82.1: nur die Beiträge nachgelesen, der Rest geteilt; der
    // Abgleich nach Kennung überträgt nur, was sich geändert hat.
    final s3 = shareSnapshot(s1, (recordings: s1.recordings, details: details(5), notes: s1.notes, reports: s1.reports, merges: s1.merges));
    final t3 = buildTrails(recordings: s3.recordings, details: s3.details, myId: 'u0', previous: t1);
    for (final t in t3) {
      t.elevation;
    }
    final ops = planLayerOps(onMap, mapLibreKeyedLayers(MapViewLayers(polylines: linesOf(t3, smoothed)), cache), () => slots++);
    final newBytes = textBytes([for (final o in ops) if (o is! RemoveLayerOp) o.layer]);
    final tNewMap = lap();

    // Und ein S-Grad, der die Farbe der Linie ändert: zwei Fächer neu.
    final graded = [for (final d in s3.details) d.trailId == 't0' ? d.copyWith(grade: 3) : d];
    final s4 = shareSnapshot(s3, (recordings: s3.recordings, details: graded, notes: s3.notes, reports: s3.reports, merges: s3.merges));
    final t4 = buildTrails(recordings: s4.recordings, details: s4.details, myId: 'u0', previous: t3);
    final gradeOps = planLayerOps(onMap, mapLibreKeyedLayers(MapViewLayers(polylines: linesOf(t4, smoothed)), cache), () => slots++);
    final gradeBytes = textBytes([for (final o in gradeOps) if (o is! RemoveLayerOp) o.layer]);
    final tGrade = lap();

    // ignore: avoid_print
    print('$n Trails × $p Punkte, ein Stern gespeichert:\n'
        '  bis 0.82.0: Netz ${(raw.length / 1e6).toStringAsFixed(1)} MB holen+lesen $tFetch ms · '
        'Trails+Karte $tOldMap ms, ${(oldBytes / 1e6).toStringAsFixed(1)} MB an MapLibre · Kopie am Stück $tOldCache ms\n'
        '  ab 0.82.1: Trails+Karte $tNewMap ms, ${ops.length} Schritte, '
        '${(newBytes / 1e3).toStringAsFixed(0)} KB an MapLibre · Kopie in Häppchen, nicht abgewartet\n'
        '  ab 0.82.1, S-Grad statt Stern (andere Linienfarbe): $tGrade ms, ${gradeOps.length} Schritte, '
        '${(gradeBytes / 1e3).toStringAsFixed(0)} KB an MapLibre');
  });
}
