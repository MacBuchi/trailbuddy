import Toybox.Lang;
import Toybox.Math;

//! Die Route auf der Uhr (Konzept-Garmin 2). Kommt als Dictionary — in
//! G1 aus der Ressource `route.json`, ab G2 als Nachricht vom Handy, in
//! derselben Form:
//!
//!   v    Protokollversion (1)
//!   id   Kennung der Route
//!   rel  true: Testroute, am ersten GPS-Fix verankert (G1)
//!   pts  [lat0, lon0, dLat1, dLon1, …] — Ganzzahlen in 1e-5°, der
//!        erste Punkt absolut, jeder weitere gegen den Vorgänger
//!   ele  [m, …] je Punkt, oder fehlt
//!   sec  [[vonPunkt, bisPunkt, sGrad, Name], …] — die Trails der Route;
//!        sGrad 0…3, -1 ohne Grad
//!   br   [Punkt, dLat, dLon, …] — die Abzweigungen: je Kreuzung ein
//!        Stummel des abgehenden Wegs, sein Ende gegen den Punkt der
//!        Route (1e-5°), oder fehlt
//!
//! Gespeichert wird in Metern um den ersten Punkt (x Ost, y Nord): Für
//! die Abstände, um die es geht, reicht die flache Näherung, und Float
//! spart gegenüber Double die Hälfte.
//!
//! Die fēnix 5 bricht jedes Ereignis nach 120 000 Bytecode-Schritten ab
//! (Watchdog, `simulator.json`). Deshalb dekodiert [decodeStep] in
//! Häppchen, und Zeichnen und Suche gehen über Blöcke zu [BLOCK] Punkten
//! mit ihrer Hülle: Was weit weg liegt, kostet einen Vergleich je Block.
class NavRoute {
    //! Meter je Grad Breite (Kugel mit 6371 km, wie `geo.dart`).
    static const K_LAT = 111194.9;
    static const HEADING_LOOK_M = 50.0;
    static const ARRIVE_M = 30.0;
    static const CLIMB_HYSTERESIS_M = 10.0;
    static const BLOCK = 32;

    var id as String;
    var relative as Boolean;
    var lat0 as Double = 0.0d;
    var lon0 as Double = 0.0d;
    var kLon as Float = K_LAT;
    var xs as Array<Float>;
    var ys as Array<Float>;
    var cum as Array<Float>;
    //! Bis zu jedem Punkt gestiegene Höhenmeter (Hysterese 10 m wie
    //! `kClimbHysteresisM`); null ohne Höhen.
    var climb as Array<Float>? = null;
    //! Hülle je Block: Punkte b·BLOCK … b·BLOCK+BLOCK.
    var bMinX as Array<Float> = [] as Array<Float>;
    var bMaxX as Array<Float> = [] as Array<Float>;
    var bMinY as Array<Float> = [] as Array<Float>;
    var bMaxY as Array<Float> = [] as Array<Float>;
    //! Die Abzweigungen: Punkt der Route und Ende des Stummels in Metern.
    var brAt as Array<Number> = [] as Array<Number>;
    var brX as Array<Float> = [] as Array<Float>;
    var brY as Array<Float> = [] as Array<Float>;
    var secFrom as Array<Number> = [] as Array<Number>;
    var secTo as Array<Number> = [] as Array<Number>;
    var secGrade as Array<Number> = [] as Array<Number>;
    var secName as Array<String> = [] as Array<String>;
    var lengthM as Float = 0.0;
    var isLoop as Boolean = false;

    // Stand des Dekodierens: Phase 0 Punkte, 1 Höhen, 2 Blöcke, 3 fertig.
    hidden var _pts as Array<Number>?;
    hidden var _ele as Array<Number>?;
    hidden var _br as Array<Number>?;
    hidden var _phase as Number = 0;
    hidden var _i as Number = 1;
    hidden var _dLat as Number = 0;
    hidden var _dLon as Number = 0;
    hidden var _gain as Float = 0.0;
    hidden var _ref as Float = 0.0;
    hidden var _extreme as Float = 0.0;
    hidden var _dir as Number = 0;

    //! Legt die Route an; fertig ist sie erst, wenn [decodeStep] true
    //! liefert (oder gleich mit [decoded] für kleine Routen und Tests).
    function initialize(d as Dictionary) {
        id = d["id"] as String;
        relative = d["rel"] == true;
        var pts = d["pts"] as Array<Number>;
        _pts = pts;
        var n = pts.size() / 2;
        lat0 = pts[0].toDouble() / 100000.0d;
        lon0 = pts[1].toDouble() / 100000.0d;
        kLon = (K_LAT * Math.cos(Math.toRadians(lat0))).toFloat();
        xs = new Array<Float>[n];
        ys = new Array<Float>[n];
        cum = new Array<Float>[n];
        xs[0] = 0.0;
        ys[0] = 0.0;
        cum[0] = 0.0;
        var ele = d["ele"] as Array<Number>?;
        if (ele != null && ele.size() == n) {
            _ele = ele;
            climb = new Array<Float>[n];
        }
        _br = d["br"] as Array<Number>?;
        var sec = d["sec"] as Array<Array>?;
        if (sec != null) {
            for (var i = 0; i < sec.size(); i++) {
                var s = sec[i];
                secFrom.add(s[0] as Number);
                secTo.add(s[1] as Number);
                secGrade.add(s[2] as Number);
                secName.add(s[3] as String);
            }
        }
    }

    //! Für Tests und kleine Routen: alles in einem Zug.
    static function decoded(d as Dictionary) as NavRoute {
        var r = new NavRoute(d);
        while (!r.decodeStep(100000)) {}
        return r;
    }

    function isReady() as Boolean {
        return _phase >= 3;
    }

    //! Wie weit das Dekodieren ist, 0…1.
    function progress() as Float {
        var n = xs.size().toFloat();
        if (_phase >= 3) { return 1.0; }
        return (_phase * n + _i) / (3 * n);
    }

    //! Dekodiert bis zu [budget] Punkte; true, wenn fertig.
    function decodeStep(budget as Number) as Boolean {
        var n = xs.size();
        var end = _i + budget;
        if (_phase == 0) {
            var pts = _pts as Array<Number>;
            var i = _i;
            for (; i < n && i < end; i++) {
                _dLat += pts[2 * i];
                _dLon += pts[2 * i + 1];
                var x = _dLon * kLon / 100000.0;
                var y = _dLat * K_LAT / 100000.0;
                xs[i] = x;
                ys[i] = y;
                var dx = x - xs[i - 1];
                var dy = y - ys[i - 1];
                cum[i] = cum[i - 1] + Math.sqrt(dx * dx + dy * dy).toFloat();
            }
            _i = i;
            if (_i < n) { return false; }
            _pts = null;
            lengthM = cum[n - 1];
            var ex = xs[n - 1];
            var ey = ys[n - 1];
            isLoop = Math.sqrt(ex * ex + ey * ey) <= ARRIVE_M;
            var br = _br;
            if (br != null) {
                for (var k = 0; k + 2 < br.size(); k += 3) {
                    var at = br[k];
                    if (at < 0 || at >= n) { continue; }
                    brAt.add(at);
                    brX.add(xs[at] + br[k + 2] * kLon / 100000.0);
                    brY.add(ys[at] + br[k + 1] * K_LAT / 100000.0);
                }
                _br = null;
            }
            _phase = 1;
            _i = 1;
            var ele = _ele;
            if (ele != null) {
                _ref = ele[0].toFloat();
                _extreme = _ref;
                (climb as Array<Float>)[0] = 0.0;
            }
            return false;
        }
        if (_phase == 1) {
            var ele = _ele;
            if (ele != null) {
                var i = _i;
                for (; i < n && i < end; i++) {
                    climbAt(ele, i);
                }
                _i = i;
                if (_i < n) { return false; }
            }
            _ele = null;
            _phase = 2;
            _i = 0;
            return false;
        }
        if (_phase == 2) {
            var i = _i;
            for (; i < n - 1 && i < end; i += BLOCK) {
                var last = i + BLOCK < n - 1 ? i + BLOCK : n - 1;
                var minX = xs[i];
                var maxX = minX;
                var minY = ys[i];
                var maxY = minY;
                for (var k = i + 1; k <= last; k++) {
                    var x = xs[k];
                    var y = ys[k];
                    if (x < minX) { minX = x; } else if (x > maxX) { maxX = x; }
                    if (y < minY) { minY = y; } else if (y > maxY) { maxY = y; }
                }
                bMinX.add(minX);
                bMaxX.add(maxX);
                bMinY.add(minY);
                bMaxY.add(maxY);
            }
            _i = i;
            if (_i < n - 1) { return false; }
            _phase = 3;
        }
        return true;
    }

    //! Ein Schritt der Hysterese von `hysteresisClimb` (height_tiles.dart);
    //! der laufende Anstieg zählt schon mit, damit die Zahl nie springt.
    hidden function climbAt(ele as Array<Number>, i as Number) as Void {
        var h = ele[i].toFloat();
        var t = CLIMB_HYSTERESIS_M;
        if (_dir == 0) {
            if (h - _ref >= t) {
                _dir = 1;
                _extreme = h;
            } else if (_ref - h >= t) {
                _dir = -1;
                _extreme = h;
            }
        } else if (_dir == 1) {
            if (h > _extreme) {
                _extreme = h;
            } else if (_extreme - h >= t) {
                _gain += _extreme - _ref;
                _ref = _extreme;
                _dir = -1;
                _extreme = h;
            }
        } else {
            if (h < _extreme) {
                _extreme = h;
            } else if (h - _extreme >= t) {
                _ref = _extreme;
                _dir = 1;
                _extreme = h;
            }
        }
        (climb as Array<Float>)[i] = _gain + (_dir == 1 ? _extreme - _ref : 0.0);
    }

    function blockCount() as Number {
        return bMinX.size();
    }

    //! Quadrat der kleinsten Entfernung von (px, py) zur Hülle des Blocks.
    function blockDist2(b as Number, px as Float, py as Float) as Float {
        var dx = bMinX[b] - px;
        if (dx < 0) { dx = px - bMaxX[b]; if (dx < 0) { dx = 0.0; } }
        var dy = bMinY[b] - py;
        if (dy < 0) { dy = py - bMaxY[b]; if (dy < 0) { dy = 0.0; } }
        return dx * dx + dy * dy;
    }

    function size() as Number {
        return xs.size();
    }

    //! Verankert eine Testroute (rel) an der ersten Position: Ab da ist
    //! sie eine Route wie jede andere.
    function anchor(latDeg as Double, lonDeg as Double) as Void {
        lat0 = latDeg;
        lon0 = lonDeg;
        kLon = (K_LAT * Math.cos(Math.toRadians(lat0))).toFloat();
        relative = false;
    }

    //! Eine GPS-Position in Meter um den ersten Punkt.
    function toLocal(latDeg as Double, lonDeg as Double) as [Float, Float] {
        return [((lonDeg - lon0) * kLon).toFloat(), ((latDeg - lat0) * K_LAT).toFloat()];
    }

    //! Der Index des Abschnitts, in dem [m] liegt (sein Anfang).
    function segmentAt(m as Float) as Number {
        var lo = 0;
        var hi = cum.size() - 2;
        while (lo < hi) {
            var mid = (lo + hi + 1) / 2;
            if (cum[mid] <= m) {
                lo = mid;
            } else {
                hi = mid - 1;
            }
        }
        while (lo < cum.size() - 2 && cum[lo + 1] - cum[lo] <= 0) {
            lo++;
        }
        return lo;
    }

    //! Der Punkt [m] Meter ab Start, auf die Linie geklemmt.
    function pointAt(m as Float) as [Float, Float] {
        var n = xs.size();
        if (m <= 0) { return [xs[0], ys[0]]; }
        if (m >= lengthM) { return [xs[n - 1], ys[n - 1]]; }
        var i = segmentAt(m);
        var seg = cum[i + 1] - cum[i];
        var t = seg <= 0 ? 0.0 : (m - cum[i]) / seg;
        return [xs[i] + (xs[i + 1] - xs[i]) * t, ys[i] + (ys[i + 1] - ys[i]) * t];
    }

    //! Die Richtung der Linie bei [m] in Bogenmaß ab Norden, über 50 m
    //! voraus gemessen (wie `NavRoute.bearingAt` der App).
    function bearingAt(m as Float) as Float {
        var from = m < 0 ? 0.0 : (m > lengthM ? lengthM : m);
        var a = pointAt(from);
        var b = pointAt(from + HEADING_LOOK_M);
        if (from + HEADING_LOOK_M > lengthM) {
            a = pointAt(lengthM - HEADING_LOOK_M);
            b = pointAt(lengthM);
        }
        return Math.atan2(b[0] - a[0], b[1] - a[1]).toFloat();
    }

    //! Höhenmeter bergauf ab [m] bis zum Ende; null ohne Höhen.
    function climbLeft(m as Float) as Float? {
        var c = climb;
        if (c == null) { return null; }
        var i = segmentAt(m);
        var left = c[c.size() - 1] - c[i];
        return left < 0 ? 0.0 : left;
    }

    //! Höhenmeter bergauf zwischen [fromM] und [toM]; null ohne Höhen.
    function climbBetween(fromM as Float, toM as Float) as Float? {
        var c = climb;
        if (c == null) { return null; }
        var d = c[segmentAt(toM)] - c[segmentAt(fromM)];
        return d < 0 ? 0.0 : d;
    }

    //! Der nächste Trail, dessen Kopf voraus liegt; -1 ohne.
    function nextSection(m as Float) as Number {
        var best = -1;
        for (var k = 0; k < secFrom.size(); k++) {
            var head = cum[secFrom[k]];
            if (head > m && (best < 0 || head < cum[secFrom[best]])) { best = k; }
        }
        return best;
    }

    //! Der Trail (Index in sec*), auf dem [m] liegt; -1 dazwischen.
    function sectionAt(m as Float) as Number {
        var i = segmentAt(m);
        for (var k = 0; k < secFrom.size(); k++) {
            if (i >= secFrom[k] && i < secTo[k]) { return k; }
        }
        return -1;
    }
}
