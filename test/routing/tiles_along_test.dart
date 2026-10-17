// Der Korridor einer Fahrt (#356 PR 9): Die Kalibrierung liest nur die
// Kacheln, die die Linie berührt — nicht den Rahmen, den sie aufspannt.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/road_graph_loader.dart';

void main() {
  // Bei 47° N ist eine z13-Kachel rund 0,044° breit und 0,03° hoch.
  const a = LatLng(47.0, 11.0), b = LatLng(47.3, 11.44);

  test('eine Diagonale berührt viel weniger Kacheln als ihr Rahmen', () {
    final along = tilesAlong([a, b], 30);
    final frame = tilesCovering(roadGraphBounds(LatBox.of([a, b]), 30), minZoom: kRoadGraphZoom, maxZoom: kRoadGraphZoom);
    expect(frame.length, greaterThan(80));
    expect(along.length, lessThan(frame.length / 3));
    // Die Kacheln der Enden sind dabei, und jede liegt im Rahmen.
    final ta = tileAt(a.latitude, a.longitude, kRoadGraphZoom), tb = tileAt(b.latitude, b.longitude, kRoadGraphZoom);
    expect(along, contains((ta.x, ta.y)));
    expect(along, contains((tb.x, tb.y)));
    final inFrame = {for (final t in frame) (t.x, t.y)};
    expect(along.every(inFrame.contains), isTrue);
  });

  test('zwei Punkte weit auseinander: die Strecke dazwischen wird abgetastet', () {
    final along = tilesAlong([a, b], 30);
    // Jede Kachelspalte zwischen den Enden kommt vor — kein Sprung.
    final xs = along.map((t) => t.$1).toSet();
    final ta = tileAt(a.latitude, a.longitude, kRoadGraphZoom), tb = tileAt(b.latitude, b.longitude, kRoadGraphZoom);
    for (var x = ta.x; x <= tb.x; x++) {
      expect(xs, contains(x));
    }
  });

  test('der Rand zählt: nah an der Kachelgrenze kommt die Nachbarkachel dazu', () {
    final t = tileAt(47.0, 11.0, kRoadGraphZoom);
    final bounds = tileBounds(kRoadGraphZoom, t.x, t.y);
    // 10 m östlich der Westkante: mit 30 m Rand liegt die westliche
    // Nachbarin mit drin, ohne Rand nicht.
    final p = LatLng((bounds.north + bounds.south) / 2, bounds.west + 10 / (111320 * 0.68));
    expect(tilesAlong([p], 0), {(t.x, t.y)});
    expect(tilesAlong([p], 30), containsAll([(t.x, t.y), (t.x - 1, t.y)]));
    expect(tilesAlong(const [], 30), isEmpty);
  });
}
