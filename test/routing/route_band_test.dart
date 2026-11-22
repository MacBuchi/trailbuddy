import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/features/routing/nav_providers.dart';
import 'package:trailbuddy/features/routing/nav_view.dart';
import 'package:trailbuddy/features/routing/route_progress.dart';
import 'package:trailbuddy/features/routing/route_band_geometry.dart';
import 'package:trailbuddy/features/routing/route_band.dart';

LatLng _p(int i) => LatLng(48, 9 + i * 0.001);

void main() {
  // Start 0 → 3, dort eine kleine Schleife über 4 und 5 zurück auf 3, dann
  // denselben Weg zurück nach 0: 0–1–2–3 liegt doppelt.
  final outAndBack = [
    _p(0),
    _p(1),
    _p(2),
    _p(3),
    const LatLng(48.001, 9.004),
    const LatLng(48.002, 9.003),
    _p(3),
    _p(2),
    _p(1),
    _p(0),
  ];

  test('versetzte Pfeile nur solange beide Durchfahrten ausstehen', () {
    final g = RouteBandGeometry.of(outAndBack)!;
    expect(g.sharedAhead(0), hasLength(2));
    expect(g.sharedAhead(g.route.cumM[6]), isEmpty);
  });

  test('gemeinsamer Rückweg hat genau ein Band', () {
    final lines = routeBandLines(outAndBack, opacity: kRoutePreviewOpacity);
    final band = lines.where((l) => l.width == kRouteBandWidth);
    expect(band.first.points.first, outAndBack.first);
    expect(band.expand((l) => l.points).where((p) => p == _p(1)), hasLength(1));
    expect(band.every((l) => l.opacity == kRoutePreviewOpacity), isTrue);
  });

  test(
    'X zwischen Stützpunkten wechselt Vorrang nach der ersten Durchfahrt',
    () {
      const points = [
        LatLng(1, 1),
        LatLng(1.002, 1.002),
        LatLng(1.002, 1),
        LatLng(1, 1.002),
      ];
      final g = RouteBandGeometry.of(points)!;
      expect(RouteBandGeometry.of(points), same(g));
      final later = (g.route.cumM[2] + g.route.lengthM) / 2;
      final gaps = g.hidden(0, 16);
      expect(gaps, hasLength(1));
      expect(gaps.single.start, lessThan(later));
      expect(gaps.single.end, greaterThan(later));
      expect(g.hidden(g.route.cumM[1], 16), isEmpty);
      expect(g.hidden(0, 15).single.start, lessThan(gaps.single.start));
    },
  );

  test('Folgeansicht: zwei GPS-Anfahrten auf dieselbe abbiegende Kreuzung', () {
    const centre = LatLng(1, 1);
    const points = [
      LatLng(0.998, 1),
      centre,
      LatLng(1, 1.002),
      LatLng(1.002, 1.002),
      LatLng(1.002, 1),
      centre,
      LatLng(1, 0.998),
    ];
    final route = NavRoute.of(points)!;
    final tracker = NavTracker(route);
    for (final leg in [0, 1, 2, 3, 4]) {
      final state = tracker.update(route.pointAt(route.cumM[leg] + 45));
      if (leg != 0 && leg != 4) continue;
      final lines = navRouteLines(
        NavSession(title: 'Acht', route: route, state: state),
      );
      final bright = lines.where(
        (l) => l.width == kRouteBandWidth && l.opacity > 0.60,
      );
      final outgoing = [for (final l in bright) ...l.points];
      if (leg == 0) {
        expect(
          outgoing.any((p) => p.longitude > centre.longitude + 0.0001),
          isTrue,
        );
        expect(
          outgoing.any((p) => p.longitude < centre.longitude - 0.0001),
          isFalse,
        );
      } else {
        expect(
          outgoing.any((p) => p.longitude < centre.longitude - 0.0001),
          isTrue,
        );
        expect(
          outgoing.any((p) => p.longitude > centre.longitude + 0.0001),
          isFalse,
        );
      }
    }
  });

  test('drei Besuche: erster, zweiter und dritter Ast rücken nach', () {
    const points = [
      LatLng(1, 1),
      LatLng(1.002, 1.002),
      LatLng(1.002, 1),
      LatLng(1, 1.002),
      LatLng(1, 1.001),
      LatLng(1.002, 1.001),
    ];
    final geometry = RouteBandGeometry.of(points)!;
    final metres = geometry.route.cumM;
    double middle(int i) => (metres[i] + metres[i + 1]) / 2;
    bool masked(double position, double at) =>
        geometry.hidden(position, 17).any((g) => g.start < at && g.end > at);
    expect(masked(0, middle(0)), isFalse);
    expect(masked(0, middle(2)), isTrue);
    expect(masked(0, middle(4)), isTrue);
    expect(masked(metres[1], middle(2)), isFalse);
    expect(masked(metres[1], middle(4)), isTrue);
    expect(masked(metres[3], middle(4)), isFalse);
  });

  test('Rundung behält Umkehrpunkt, Endpunkte und die Originalmeter', () {
    const points = [
      LatLng(1, 1),
      LatLng(1, 1),
      LatLng(1, 1.002),
      LatLng(1.002, 1.002),
      LatLng(1, 1.002),
    ];
    final g = RouteBandGeometry.of(points)!;
    final line = g.slice(0, g.route.lengthM);
    expect(line.first, points.first);
    expect(line.last, points.last);
    expect(line, contains(points[3]));
    expect(line.length, greaterThan(points.length));
    final m = g.route.cumM[1];
    final a = g.slice(0, m), b = g.slice(m, g.route.lengthM);
    expect(a.last, b.first);
    expect(const Distance()(a.last, points[2]), lessThan(3));
  });

  test('500 Routenmeter, auch mitten auf einer langen Kante', () {
    const points = [LatLng(1, 1), LatLng(1, 1.030)];
    final g = RouteBandGeometry.of(points)!;
    final lines = routeBandLines(
      points,
      opacity: kRouteFollowOpacity,
      alongM: 100,
    ).where((l) => l.width == kRouteBandWidth).toList();
    expect(lines.first.points.first, g.route.pointAt(100));
    expect(lines.first.opacity, 0.9);
    expect(routeOpacityAt(250), closeTo(0.625, 1e-9));
    expect(lines.last.opacity, 0.35);
    expect(
      lines.firstWhere((l) => l.points.first == g.route.pointAt(600)).opacity,
      0.35,
    );
    expect(lines.last.points.last, points.last);
    final next = routeBandLines(
      points,
      opacity: kRouteFollowOpacity,
      alongM: 120,
    ).where((l) => l.width == kRouteBandWidth);
    expect(next.last.points, same(lines.last.points));
    expect(
      routeBandLines(
        points,
        opacity: kRouteFollowOpacity,
        alongM: g.route.lengthM,
      ).where((l) => l.width == kRouteBandWidth),
      isEmpty,
    );
  });

  test(
    'Pfeile decken die Route lückenlos, versetzt nur, wo es hin und zurück geht',
    () {
      final arrows = [
        for (final l in routeBandLines(outAndBack, opacity: 0.8))
          if (l.arrows != null) l,
      ];
      expect(
        arrows.map((l) => l.width),
        everyElement(0),
        reason: 'die Pfeil-Linien zeichnen keinen Strich',
      );
      expect(
        [for (final l in arrows) l.arrows!.offset],
        [kRouteArrowOffset, 0, kRouteArrowOffset],
      );
      expect(
        arrows.expand((l) => l.points).length,
        greaterThan(outAndBack.length),
      );
      expect(arrows.first.points.first, outAndBack.first);
      expect(arrows.last.points.last, outAndBack.last);
      expect(arrows.first.arrows!.color, AppColors.routeArrow);
    },
  );

  test('Wanderweg gestrichelt in der Mitte, Tippziele unsichtbar', () {
    const hit = 'leg-0';
    final lines = routeBandLines(
      outAndBack,
      opacity: 0.55,
      pieces: [
        (points: outAndBack.sublist(0, 4), hiking: true, hitValue: hit),
        (points: outAndBack.sublist(3, 7), hiking: false, hitValue: null),
      ],
    );
    final hiking = lines.where((l) => l.dash != null).single;
    expect(hiking.points.first, outAndBack.first);
    expect(hiking.points, contains(_p(1)));
    expect(hiking.color, AppColors.routeEdge);
    final hits = lines.where((l) => l.hitValue != null).toList();
    expect(hits.single.hitValue, hit);
    expect(hits.single.width, 0);
    expect(
      lines.last,
      hits.single,
      reason: 'zuoberst — der Tipp trifft die Route, nicht das Band',
    );
  });

  test('weniger als zwei Punkte: nichts', () {
    expect(routeBandLines([_p(0)], opacity: 0.55), isEmpty);
  });
}
