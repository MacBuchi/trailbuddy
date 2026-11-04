import Toybox.Lang;
import Toybox.Math;

//! Der Stand nach einem Fix — was die Ansicht zeigt.
class NavState {
    var x as Float = 0.0;
    var y as Float = 0.0;
    var alongM as Float = 0.0;
    var remainingM as Float = 0.0;
    var offM as Float = 0.0;
    //! Abseits — erst nach zwei Fixen in Folge über 30 m.
    var offRoute as Boolean = false;
    //! Genau der Fix, an dem „abseits" beginnt: dann vibriert die Uhr
    //! (Konzept-Garmin, Entscheidung 3). Einmal, bis man wieder auf der
    //! Linie war.
    var leftRoute as Boolean = false;
    var arrived as Boolean = false;
    //! Wohin die Ansicht zeigt, Bogenmaß ab Norden.
    var heading as Float = 0.0;
    var moving as Boolean = false;
    //! Der Punkt der Linie voraus, auf den der Pfeil abseits zeigt.
    var rejoinX as Float = 0.0;
    var rejoinY as Float = 0.0;

    function initialize() {}
}

//! Führt den Stand von Fix zu Fix — dieselben Regeln und Werte wie
//! `NavTracker` in `lib/features/routing/route_progress.dart`
//! (Folgeansicht 9.3): Fenster ab dem letzten Stand, „abseits" nach zwei
//! Fixen über 30 m, angekommen unter 30 m vom Ende bzw. auf dem letzten
//! Stück einer Runde. Anders als die App dreht die Uhr im Stand nach dem
//! Kompass (Konzept-Garmin 1).
class NavTracker {
    static const OFF_ROUTE_M = 30.0;
    static const OFF_ROUTE_FIXES = 2;
    static const AHEAD_WINDOW_M = 800.0;
    static const BACK_SLACK_M = 30.0;
    static const ARRIVE_M = 30.0;
    static const HEADING_MIN_SPEED_MPS = 2.0;
    static const REJOIN_AHEAD_M = 50.0;

    var route as NavRoute;
    hidden var _along as Float = 0.0;
    hidden var _offCount as Number = 0;
    hidden var _gpsHeading as Float? = null;
    hidden var _arrived as Boolean = false;
    hidden var _wasOff as Boolean = false;

    function initialize(r as NavRoute) {
        route = r;
    }

    //! [gpsHeading]/[compass] in Bogenmaß, null wenn unbekannt; [speed]
    //! in m/s. In Fahrt zählt der GPS-Kurs, im Stand der Kompass, ohne
    //! beides der letzte Kurs, sonst die Richtung der Linie.
    function update(x as Float, y as Float, gpsHeading as Float?, speed as Float?, compass as Float?) as NavState {
        var fix = progress(x, y, _along);
        _along = fix[0];
        var off = fix[1];
        _offCount = off > OFF_ROUTE_M ? _offCount + 1 : 0;
        var moving = speed != null && speed >= HEADING_MIN_SPEED_MPS;
        if (moving && gpsHeading != null) {
            _gpsHeading = gpsHeading;
        }
        var remaining = route.lengthM - _along;
        if (remaining < 0) { remaining = 0.0; }
        var n = route.size();
        var ex = route.xs[n - 1] - x;
        var ey = route.ys[n - 1] - y;
        var nearEnd = Math.sqrt(ex * ex + ey * ey) <= ARRIVE_M;
        _arrived = _arrived
            || (off <= OFF_ROUTE_M && remaining <= ARRIVE_M)
            || (nearEnd && (!route.isLoop || _along >= route.lengthM / 2));

        var s = new NavState();
        s.x = x;
        s.y = y;
        s.alongM = _along;
        s.remainingM = remaining;
        s.offM = off;
        s.offRoute = _offCount >= OFF_ROUTE_FIXES;
        s.leftRoute = s.offRoute && !_wasOff && !_arrived;
        _wasOff = s.offRoute;
        s.arrived = _arrived;
        s.moving = moving;
        if (moving && gpsHeading != null) {
            s.heading = gpsHeading;
        } else if (!moving && compass != null) {
            s.heading = compass;
        } else if (_gpsHeading != null) {
            s.heading = _gpsHeading;
        } else {
            s.heading = route.bearingAt(_along);
        }
        var r = route.pointAt(_along + REJOIN_AHEAD_M);
        s.rejoinX = r[0];
        s.rejoinY = r[1];
        return s;
    }

    //! [alongM, offM]: zuerst im Fenster ab [last] (zurück 30 m, voraus
    //! 800 m); liegt dort nichts in 30 m, die ganze Linie — und liegt auch
    //! dort nichts so nah, bleibt der Stand des Fensters (kein Sprung auf
    //! die Rückfahrt), der Abstand aber ist der zur ganzen Linie.
    function progress(x as Float, y as Float, last as Float) as [Float, Float] {
        var w = nearest(x, y, last - BACK_SLACK_M, last + AHEAD_WINDOW_M);
        if (w != null && w[1] <= OFF_ROUTE_M) { return w; }
        var all = nearest(x, y, -1.0e9, 1.0e9) as [Float, Float];
        if (all[1] <= OFF_ROUTE_M || w == null) { return all; }
        return [w[0], all[1]];
    }

    //! Der nächste Fußpunkt zwischen [from] und [to] Metern ab Start —
    //! blockweise: zuerst der Block mit der nächsten Hülle, danach kostet
    //! jeder Block, dessen Hülle weiter weg ist als der beste Fund, nur
    //! einen Vergleich (Watchdog, NavRoute).
    hidden function nearest(px as Float, py as Float, from as Float, to as Float) as [Float, Float]? {
        var cum = route.cum;
        var n = route.xs.size();
        var nb = route.blockCount();
        var bs = NavRoute.BLOCK;
        var seed = -1;
        var seedD = 0.0;
        for (var b = 0; b < nb; b++) {
            var first = b * bs;
            var last = first + bs < n - 1 ? first + bs : n - 1;
            if (cum[first] > to) { break; }
            if (cum[last] < from) { continue; }
            var d = route.blockDist2(b, px, py);
            if (seed < 0 || d < seedD) {
                seed = b;
                seedD = d;
            }
        }
        if (seed < 0) { return null; }
        _bestOff = -1.0;
        _bestAlong = 0.0;
        searchBlock(seed, px, py, from, to);
        for (var b = 0; b < nb; b++) {
            if (b == seed) { continue; }
            var first = b * bs;
            var last = first + bs < n - 1 ? first + bs : n - 1;
            if (cum[first] > to) { break; }
            if (cum[last] < from) { continue; }
            if (_bestOff >= 0 && route.blockDist2(b, px, py) > _bestOff * _bestOff) { continue; }
            searchBlock(b, px, py, from, to);
        }
        return _bestOff < 0 ? null : [_bestAlong, _bestOff];
    }

    hidden var _bestOff as Float = -1.0;
    hidden var _bestAlong as Float = 0.0;

    hidden function searchBlock(b as Number, px as Float, py as Float, from as Float, to as Float) as Void {
        var xs = route.xs;
        var ys = route.ys;
        var cum = route.cum;
        var n = xs.size();
        var first = b * NavRoute.BLOCK;
        var last = first + NavRoute.BLOCK < n - 1 ? first + NavRoute.BLOCK : n - 1;
        for (var i = first; i < last; i++) {
            if (cum[i + 1] < from) { continue; }
            if (cum[i] > to) { break; }
            var ax = xs[i] - px;
            var ay = ys[i] - py;
            var dx = xs[i + 1] - xs[i];
            var dy = ys[i + 1] - ys[i];
            var len2 = dx * dx + dy * dy;
            var t = len2 <= 0 ? 0.0 : -(ax * dx + ay * dy) / len2;
            if (t < 0) { t = 0.0; } else if (t > 1) { t = 1.0; }
            var along = cum[i] + t * (cum[i + 1] - cum[i]);
            if (along < from || along > to) { continue; }
            var cx = ax + t * dx;
            var cy = ay + t * dy;
            var off = Math.sqrt(cx * cx + cy * cy).toFloat();
            if (_bestOff < 0 || off < _bestOff) {
                _bestOff = off;
                _bestAlong = along;
            }
        }
    }
}
