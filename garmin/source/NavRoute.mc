import Toybox.Lang;
import Toybox.Math;

//! Die Route auf der Uhr (Konzept-Garmin 2). Kommt in Stücken
//! ([RouteParts]) mit einem Kopf (`PhoneRoute.headOf`): vom Handy aus dem
//! Speicher der Uhr, die Testroute (G1) als ein Stück aus `route.json` —
//! dieselbe Form, Protokoll 2 (`PhoneRoute`): je Punkt eine gepackte Zahl
//! `(dLat << 16) | dLon` in 1e-5° gegen den Vorgänger, Höhendifferenzen
//! zu zweit in einer Zahl, je Stummel `[Punkt, gepackt(dLat, dLon)]`.
//!
//! Gespeichert wird in Metern um den ersten Punkt (x Ost, y Nord): Für
//! die Abstände, um die es geht, reicht die flache Näherung, und Float
//! spart gegenüber Double die Hälfte.
//!
//! **Speicher** (#449, 2026-11-05): Die Felder `xs/ys/cum/climb` stehen
//! von Anfang an in voller Länge (`np` aus dem Kopf), und [decodeStep]
//! holt die Stücke einzeln — die rohe Route liegt nie ganz im
//! Arbeitsspeicher, nur ein Stück. Vorher lagen rohe Daten und Felder
//! kurz zusammen; ab 3000 Punkten hieß das „Out of Memory" beim Laden.
//! Passt ein Stück nicht (fehlt, falsche Form, mehr oder weniger Punkte als
//! `np`), steht [failed] — die App nimmt dann die Testroute, statt
//! abzustürzen.
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

    //! Ein Stück passte nicht: Die Route ist unbrauchbar (nie [isReady]).
    var failed as Boolean = false;

    // Stand des Dekodierens: Phase 0 Punkte samt Höhen und Stummeln, 2
    // Blöcke, 3 fertig.
    hidden var _parts as RouteParts?;
    hidden var _part as Array?;
    hidden var _k as Number = 0;
    hidden var _j as Number = 0;
    hidden var _hasEle as Boolean = false;
    hidden var _h as Number = 0;
    hidden var _phase as Number = 0;
    hidden var _i as Number = 0;
    hidden var _dLat as Number = 0;
    hidden var _dLon as Number = 0;
    hidden var _gain as Float = 0.0;
    hidden var _ref as Float = 0.0;
    hidden var _extreme as Float = 0.0;
    hidden var _dir as Number = 0;

    //! Legt die Route an: [head] wie `PhoneRoute.headOf` (`[np, lat0, lon0,
    //! mitHöhen, e0, sec]`, geprüft), [parts] die Stücke. Fertig ist sie erst,
    //! wenn [decodeStep] true liefert (oder gleich mit [decoded]).
    function initialize(routeId as String, rel as Boolean, head as Array, parts as RouteParts) {
        id = routeId;
        relative = rel;
        var n = head[0] as Number;
        lat0 = (head[1] as Number).toDouble() / 100000.0d;
        lon0 = (head[2] as Number).toDouble() / 100000.0d;
        kLon = (K_LAT * Math.cos(Math.toRadians(lat0))).toFloat();
        xs = new Array<Float>[n];
        ys = new Array<Float>[n];
        cum = new Array<Float>[n];
        _hasEle = head[3] == true;
        _h = head[4] as Number;
        if (_hasEle) {
            climb = new Array<Float>[n];
        }
        var sec = head[5] as Array<Array>;
        for (var i = 0; i < sec.size(); i++) {
            var s = sec[i];
            secFrom.add(s[0] as Number);
            secTo.add(s[1] as Number);
            secGrade.add(s[2] as Number);
            secName.add(s[3] as String);
        }
        _parts = parts;
    }

    //! Aus einem Dictionary in der Form von `route.json` (ein Stück): die
    //! Testroute und die Tests. Passt es nicht, eine Route, die gleich
    //! [failed] ist.
    static function fromDict(d as Dictionary) as NavRoute {
        var head = PhoneRoute.headOf(d);
        var part = PhoneRoute.partOf(d);
        var id = d["id"] instanceof String ? d["id"] as String : "-";
        if (head == null || part == null) {
            var r = new NavRoute(id, false, [2, 0, 0, false, 0, []], new RouteParts(null, [], 0));
            r.failed = true;
            return r;
        }
        return new NavRoute(id, d["rel"] == true, head, new RouteParts(null, [part], 1));
    }

    //! Für Tests und kleine Routen: alles in einem Zug.
    static function decoded(d as Dictionary) as NavRoute {
        var r = fromDict(d);
        while (!r.decodeStep(100000)) {}
        return r;
    }

    function isReady() as Boolean {
        return _phase >= 3 && !failed;
    }

    //! Wie weit das Dekodieren ist, 0…1.
    function progress() as Float {
        var n = xs.size().toFloat();
        if (_phase >= 3) { return 1.0; }
        return ((_phase == 0 ? 0 : n) + _i) / (2 * n);
    }

    //! Dekodiert bis zu [budget] Punkte; true, wenn fertig (oder [failed]).
    function decodeStep(budget as Number) as Boolean {
        if (failed) { return true; }
        var n = xs.size();
        if (_phase == 0) {
            var done = 0;
            while (done < budget && _i < n) {
                var part = _part;
                if (part == null) {
                    part = (_parts as RouteParts).get(_k);
                    if (!partFits(part)) { return fail(); }
                    _part = part;
                    _j = 0;
                }
                var p = part as Array;
                var pts = p[0] as Array<Number>;
                var ele = p[1] as Array<Number>;
                var m = pts.size();
                var j = _j;
                var i = _i;
                while (j < m && i < n && done < budget) {
                    var v = pts[j];
                    // Ausgepackt wie PhoneRoute.unpackHi/Lo, hier ohne Aufruf.
                    var hi = (v >> 16) & 0xFFFF;
                    var lo = v & 0xFFFF;
                    _dLat += hi >= 0x8000 ? hi - 0x10000 : hi;
                    _dLon += lo >= 0x8000 ? lo - 0x10000 : lo;
                    var x = _dLon * kLon / 100000.0;
                    var y = _dLat * K_LAT / 100000.0;
                    xs[i] = x;
                    ys[i] = y;
                    if (i == 0) {
                        cum[0] = 0.0;
                    } else {
                        var dx = x - xs[i - 1];
                        var dy = y - ys[i - 1];
                        cum[i] = cum[i - 1] + Math.sqrt(dx * dx + dy * dy).toFloat();
                    }
                    if (_hasEle) {
                        var e = ele[j / 2];
                        var d = j % 2 == 0 ? (e >> 16) & 0xFFFF : e & 0xFFFF;
                        _h += d >= 0x8000 ? d - 0x10000 : d;
                        climbAt(_h.toFloat(), i);
                    }
                    j++;
                    i++;
                    done++;
                }
                _j = j;
                _i = i;
                if (j < m) {
                    // Mehr Punkte im Stück als `np`: Die Route passt nicht.
                    if (i >= n) { return fail(); }
                    return false;
                }
                // Das Stück ist durch: seine Stummel, dann das nächste.
                branchesOf(p[2] as Array<Number>, i);
                _part = null;
                _k++;
            }
            if (_i < n) { return false; }
            if (_k != (_parts as RouteParts).size()) { return fail(); }
            _parts = null;
            lengthM = cum[n - 1];
            var ex = xs[n - 1];
            var ey = ys[n - 1];
            isLoop = Math.sqrt(ex * ex + ey * ey) <= ARRIVE_M;
            _phase = 2;
            _i = 0;
            return false;
        }
        if (_phase == 2) {
            var end = _i + budget;
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

    //! Hat [p] die Form `[pts, ele, br]`, mit Höhen für jeden Punkt, wenn
    //! der Kopf welche ankündigt? Die Zahlen selbst prüfte `PhoneRoute`
    //! beim Empfang (die Testroute schreibt das Werkzeug).
    hidden function partFits(p as Array?) as Boolean {
        if (p == null || p.size() != 3) { return false; }
        var pts = p[0];
        var ele = p[1];
        if (!(pts instanceof Array) || pts.size() == 0 || !(ele instanceof Array) || !(p[2] instanceof Array)) {
            return false;
        }
        return !_hasEle || ele.size() >= (pts.size() + 1) / 2;
    }

    //! Die Stummel eines Stücks: nur an schon dekodierten Punkten (`< n`).
    hidden function branchesOf(br as Array<Number>, n as Number) as Void {
        for (var k = 0; k + 1 < br.size(); k += 2) {
            var at = br[k];
            if (at < 0 || at >= n) { continue; }
            var v = br[k + 1];
            brAt.add(at);
            brX.add(xs[at] + PhoneRoute.unpackLo(v) * kLon / 100000.0);
            brY.add(ys[at] + PhoneRoute.unpackHi(v) * K_LAT / 100000.0);
        }
    }

    hidden function fail() as Boolean {
        failed = true;
        _parts = null;
        _part = null;
        return true;
    }

    //! Ein Schritt der Hysterese von `hysteresisClimb` (height_tiles.dart);
    //! der laufende Anstieg zählt schon mit, damit die Zahl nie springt.
    hidden function climbAt(h as Float, i as Number) as Void {
        if (i == 0) {
            _ref = h;
            _extreme = h;
            (climb as Array<Float>)[0] = 0.0;
            return;
        }
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
