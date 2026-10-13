// Das Band der Route (#295, „B+"): doppelt Gefahrenes liegt dichter, weil
// es ein zweites Mal gezeichnet wird; Pfeile in Fahrtrichtung, auf
// doppelten Stücken nach rechts versetzt. Ohne Pixel geprüft.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/features/routing/route_band.dart';

LatLng _p(int i) => LatLng(48, 9 + i * 0.001);

void main() {
  // Start 0 → 3, dort eine kleine Schleife über 4 und 5 zurück auf 3, dann
  // denselben Weg zurück nach 0: 0–1–2–3 liegt doppelt.
  final outAndBack = [_p(0), _p(1), _p(2), _p(3), const LatLng(48.001, 9.004), const LatLng(48.002, 9.003), _p(3), _p(2), _p(1), _p(0)];

  test('Wiederholungen erkennt die Linie an ihren Punkten, in jeder Richtung', () {
    expect(repeatedSegments(outAndBack), [false, false, false, false, false, false, true, true, true]);
    expect(doubledSegments(outAndBack), [true, true, true, false, false, false, true, true, true]);
    // Ein Rundkurs ohne gemeinsames Stück: nichts doppelt.
    expect(doubledSegments([_p(0), _p(1), const LatLng(48.001, 9.001), _p(0)]), everyElement(isFalse));
  });

  test('erst jede Stelle einmal, dann das Doppelte als zweite Zeichnung', () {
    final lines = routeBandLines(outAndBack, opacity: kRoutePreviewOpacity);
    final band = lines.where((l) => l.width == kRouteBandWidth).toList();
    final first = band.where((l) => l.pass == 0).toList();
    final again = band.where((l) => l.pass == 1).toList();
    expect(first, hasLength(1));
    expect(first.single.points, outAndBack.sublist(0, 7), reason: 'die Rückfahrt fehlt — sie liegt schon da');
    expect(again.single.points, outAndBack.sublist(6), reason: 'die Rückfahrt noch einmal');
    expect(lines.indexOf(again.single), greaterThan(lines.indexOf(first.single)));
    for (final l in band) {
      expect(l.color, AppColors.routeBand);
      expect(l.borderColor, AppColors.routeEdge);
      expect(l.borderWidth, kRouteEdgeWidth);
      expect(l.opacity, kRoutePreviewOpacity);
    }
  });

  test('Pfeile decken die Route lückenlos, versetzt nur, wo es hin und zurück geht', () {
    final arrows = [for (final l in routeBandLines(outAndBack, opacity: 0.8)) if (l.arrows != null) l];
    expect(arrows.map((l) => l.width), everyElement(0), reason: 'die Pfeil-Linien zeichnen keinen Strich');
    expect([for (final l in arrows) l.arrows!.offset], [kRouteArrowOffset, 0, kRouteArrowOffset]);
    expect({for (final l in arrows) ...l.points}, outAndBack.toSet());
    expect(arrows.first.points.first, outAndBack.first);
    expect(arrows.last.points.last, outAndBack.last);
    expect(arrows.first.arrows!.color, AppColors.routeArrow);
  });

  test('Wanderweg gestrichelt in der Mitte, Tippziele unsichtbar', () {
    const hit = 'leg-0';
    final lines = routeBandLines(outAndBack, opacity: 0.55, pieces: [
      (points: outAndBack.sublist(0, 4), hiking: true, hitValue: hit),
      (points: outAndBack.sublist(3, 7), hiking: false, hitValue: null),
    ]);
    final hiking = lines.where((l) => l.dash != null).single;
    expect(hiking.points, outAndBack.sublist(0, 4));
    expect(hiking.color, AppColors.routeEdge);
    final hits = lines.where((l) => l.hitValue != null).toList();
    expect(hits.single.hitValue, hit);
    expect(hits.single.width, 0);
    expect(lines.last, hits.single, reason: 'zuoberst — der Tipp trifft die Route, nicht das Band');
  });

  test('weniger als zwei Punkte: nichts', () {
    expect(routeBandLines([_p(0)], opacity: 0.55), isEmpty);
  });
}
