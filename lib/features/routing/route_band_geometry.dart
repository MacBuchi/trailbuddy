// Display geometry in original route metres. All navigation calculations
// continue to use NavRoute's unsmoothed points.
import 'dart:math' as math;
import 'dart:ui';

import 'package:latlong2/latlong.dart';

import '../../core/line_geometry.dart';
import 'route_progress.dart';

typedef BandRange = ({double start, double end});

double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;
double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;
LatLng _lerp(LatLng a, LatLng b, double t) => LatLng(
  a.latitude + (b.latitude - a.latitude) * t,
  a.longitude + (b.longitude - a.longitude) * t,
);

class _Overlap {
  const _Overlap(this.a, this.b, this.c, this.d, this.sine);
  // a..b on the first visit corresponds to c..d on the later visit.
  // c can exceed d when traversing a shared segment in reverse.
  final double a, b, c, d, sine;
}

class RouteBandGeometry {
  RouteBandGeometry._(this.route) {
    _prepare();
  }

  static final _cache = Expando<RouteBandGeometry>();
  static RouteBandGeometry? of(List<LatLng> points) {
    final known = _cache[points];
    if (known != null) return known;
    final route = NavRoute.of([
      for (var i = 0; i < points.length; i++)
        if (i == 0 || points[i] != points[i - 1]) points[i],
    ]);
    return route == null ? null : _cache[points] = RouteBandGeometry._(route);
  }

  final NavRoute route;
  final _points = <LatLng>[];
  final _metres = <double>[];
  final _overlaps = <_Overlap>[];
  final _slices = <(double, double), List<LatLng>>{};

  void _prepare() {
    final pts = route.points, m = route.cumM;
    final xy = FlatProjection.around(
      pts,
    ).line(pts).map((p) => Offset(p.x, p.y)).toList();
    void add(LatLng point, double metre) {
      _points.add(point);
      _metres.add(metre);
    }

    add(pts.first, 0);
    for (var i = 1; i < pts.length - 1; i++) {
      final before = xy[i] - xy[i - 1], after = xy[i + 1] - xy[i];
      final cosine = _dot(before, after) / (before.distance * after.distance);
      if (!cosine.isFinite || cosine > 0.99 || cosine < -0.995) {
        add(pts[i], m[i]);
        continue;
      }
      final cut = math.min(3.0, math.min(m[i] - m[i - 1], m[i + 1] - m[i]) / 4);
      final a = _lerp(pts[i], pts[i - 1], cut / (m[i] - m[i - 1]));
      final b = _lerp(pts[i], pts[i + 1], cut / (m[i + 1] - m[i]));
      for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        add(
          _lerp(_lerp(a, pts[i], t), _lerp(pts[i], b, t), t),
          m[i] + (2 * t - 1) * cut,
        );
      }
    }
    add(pts.last, m.last);
    // Walk the segment through cells. Even a long diagonal GPX leg costs
    // linear space rather than the area of its bounding rectangle.
    const cell = 128.0;
    final grid = <(int, int), List<int>>{};
    for (var j = 0; j < xy.length - 1; j++) {
      final v = xy[j + 1] - xy[j];
      final steps = math.max(1, (v.distance / cell).ceil());
      final cells = <(int, int)>{};
      final candidates = <int>{};
      for (var k = 0; k <= steps; k++) {
        final p = xy[j] + v * (k / steps);
        final key = ((p.dx / cell).floor(), (p.dy / cell).floor());
        if (!cells.add(key)) continue;
        for (var x = -1; x <= 1; x++) {
          for (var y = -1; y <= 1; y++) {
            candidates.addAll(grid[(key.$1 + x, key.$2 + y)] ?? const []);
          }
        }
      }
      for (final i in candidates) {
        final u = xy[i + 1] - xy[i], delta = xy[j] - xy[i];
        final determinant = _cross(u, v);
        final len = u.distance * v.distance;
        if (len == 0) continue;
        double at(int index, double t) =>
            m[index] + (m[index + 1] - m[index]) * t;
        if (determinant.abs() > len * 1e-8) {
          if (i + 1 == j ||
              (i == 0 && j == xy.length - 2 && pts.first == pts.last)) {
            continue;
          }
          final s = _cross(delta, v) / determinant,
              t = _cross(delta, u) / determinant;
          if (s < 0 || s > 1 || t < 0 || t > 1) continue;
          final a = at(i, s), b = at(j, t);
          _overlaps.add(_Overlap(a, a, b, b, determinant.abs() / len));
        } else if (_cross(delta, u).abs() / u.distance < 0.10) {
          final u2 = _dot(u, u), v2 = _dot(v, v);
          final s = _dot(delta, u) / u2, t = _dot(delta + v, u) / u2;
          final lo = math.max(0.0, math.min(s, t)),
              hi = math.min(1.0, math.max(s, t));
          if (hi <= lo) continue;
          _overlaps.add(
            _Overlap(
              at(i, lo),
              at(i, hi),
              at(j, _dot(u * lo - delta, v) / v2),
              at(j, _dot(u * hi - delta, v) / v2),
              0,
            ),
          );
        }
      }
      for (final key in cells) {
        (grid[key] ??= []).add(j);
      }
    }
    // Two traversals of the same bending road also meet at each bend.
    // Those contacts belong to the shared road, not to an X crossing.
    (int, int) contact(double first, double later) =>
        ((first * 100).round(), (later * 100).round());
    final sharedEnds = {
      for (final o in _overlaps.where((o) => o.a != o.b)) ...[
        contact(o.a, o.c),
        contact(o.b, o.d),
      ],
    };
    _overlaps.removeWhere(
      (o) => o.a == o.b && sharedEnds.contains(contact(o.a, o.c)),
    );
  }

  /// Ranges to omit from the lower visit. The gap scales with map zoom
  /// and crossing angle. Switch priority when the earlier visit is behind.
  List<BandRange> hidden(
    double progress,
    double zoom, {
    bool shared = true,
    bool history = false,
  }) {
    final mPerPx =
        156543.03392 *
        math.cos(route.points.first.latitude * math.pi / 180) /
        math.pow(2, zoom);
    final gaps = <BandRange>[];
    void hide(double a, double b) {
      gaps.add((
        start: a.clamp(0.0, route.lengthM),
        end: b.clamp(0.0, route.lengthM),
      ));
    }

    for (final o in _overlaps) {
      if (o.a == o.b) {
        // Only mask the lower upcoming crossing. The thin history is
        // painted below the whole route.
        if (history ? o.a < progress && progress <= o.c : progress <= o.a) {
          final radius = 8 * mPerPx / math.max(0.1, o.sine);
          // Near a switchback, a mask cannot reach the upper visit.
          final half = math.min(radius, (o.c - o.a) / 2);
          final centre = history ? o.a : o.c;
          hide(centre - half, centre + half);
        }
      } else if (history) {
        final f = ((progress - o.c) / (o.d - o.c)).clamp(0.0, 1.0);
        final at = o.a + (o.b - o.a) * f;
        if (o.c < o.d && progress < o.d) hide(at, o.b);
        if (o.c > o.d && progress < o.c) hide(o.a, at);
      } else if (shared && progress < o.b) {
        final f = ((progress - o.a) / (o.b - o.a)).clamp(0.0, 1.0);
        final c = o.c + (o.d - o.c) * f;
        hide(math.min(c, o.d), math.max(c, o.d));
      }
    }
    return _merge(gaps);
  }

  /// Both directions get offset arrows only while both passes are ahead.
  List<BandRange> sharedAhead(double progress) {
    final ranges = <BandRange>[];
    for (final o in _overlaps) {
      if (o.a == o.b || progress >= o.b) continue;
      final start = math.max(progress, o.a);
      final c = o.c + (o.d - o.c) * (start - o.a) / (o.b - o.a);
      ranges.add((start: start, end: o.b));
      ranges.add((start: math.min(c, o.d), end: math.max(c, o.d)));
    }
    return _merge(ranges);
  }

  static List<BandRange> _merge(List<BandRange> gaps) {
    gaps.sort((a, b) => a.start.compareTo(b.start));
    final merged = <BandRange>[];
    for (final g in gaps) {
      if (merged.isEmpty || merged.last.end < g.start) {
        merged.add(g);
      } else if (g.end > merged.last.end) {
        merged.last = (start: merged.last.start, end: g.end);
      }
    }
    return merged;
  }

  List<LatLng> slice(double from, double to, {bool cache = false}) {
    final key = (from, to);
    if (cache && _slices.containsKey(key)) return _slices[key]!;
    int above(double m) {
      var lo = 0, hi = _metres.length;
      while (lo < hi) {
        final mid = (lo + hi) ~/ 2;
        if (_metres[mid] <= m) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      return lo;
    }

    LatLng point(double m, int hi) {
      if (hi == 0) return _points.first;
      if (hi == _points.length) return _points.last;
      return _lerp(
        _points[hi - 1],
        _points[hi],
        (m - _metres[hi - 1]) / (_metres[hi] - _metres[hi - 1]),
      );
    }

    final i = above(from), j = above(to);
    final line = [
      point(from, i),
      for (var k = i; k < j && _metres[k] < to; k++) _points[k],
      point(to, j),
    ];
    if (cache) {
      if (_slices.length >= 512) _slices.remove(_slices.keys.first);
      _slices[key] = line;
    }
    return line;
  }
}
