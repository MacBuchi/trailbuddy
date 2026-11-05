import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

//! Die Ansicht (Konzept-Garmin 1, Entwürfe „Uhr-Ansicht" und „Ring und
//! Seiten" im Designer, 2026-11-04): wie die Folgeansicht der App helle
//! Karte und dunkle Infofläche (Design 13), oben gedreht in Fahrtrichtung
//! die Route, die eigene Position im unteren Teil der Karte, unten „Was
//! kommt als Nächstes?". Außen herum der Ring (TbRing) auf jeder Seite.
//! START blättert: Karte → Fahrt → Berg, und sobald das Handy Bestwerte
//! schickt (G2), → Sprünge. Kein Kartenbild — nur Route, ihre Trails und
//! deren Schilder.
class NavView extends WatchUi.View {
    //! Meter je Pixel der drei Zoomstufen (hoch/runter).
    static const ZOOM_MPP = [1.0, 2.5, 6.0] as Array<Float>;
    //! Die eigene Position, und wo die Infofläche beginnt (240er Anzeige;
    //! darunter wird der Kreis zu schmal für zwei Zeilen).
    static const POS_Y = 128;
    static const FIELD_Y = 168;
    //! Das Band: Rand in Moos, Lime darin, Trails in S-Farbe darauf, der
    //! gefahrene Teil als dünne Linie in Moos (Design 2, „B+").
    static const EDGE_W = 12;
    static const BAND_W = 8;
    static const TRAIL_W = 4;
    static const DONE_W = 3;
    static const BRANCH_W = 3;
    //! Abstand der zwei Spalten der Zahlenseiten von der Mitte. Mit 36
    //! liefen „HÖHE"/„ZUM TRAIL" ineinander und über den Trennstrich
    //! (fēnix 5, 2026-11-05); bei 54 reicht der Kreis auch unten noch.
    static const COL_X = 54;
    //! Die Übersicht ohne GPS: so viele Stücke je Linie höchstens, und der
    //! Radius, in den sie passt (innerhalb TbRing.MAP_R, über dem Text).
    static const OVERVIEW_SEGS = 200;
    static const OVERVIEW_R = 64;

    hidden var _route as NavRoute;
    hidden var _state as NavState? = null;
    //! Die Seiten: Karte, Fahrt, Berg — und Sprünge, wenn Bestwerte da sind.
    static const PAGES = 3;

    hidden var _zoom as Number = 1;
    hidden var _page as Number = 0;
    hidden var _speed as Float? = null;
    hidden var _stats as RideStats;
    hidden var _sep as String;

    // Die Drehung des laufenden Bilds (drawRoute und seine Helfer).
    hidden var _px as Float = 0.0;
    hidden var _py as Float = 0.0;
    hidden var _sin as Float = 0.0;
    hidden var _cos as Float = 1.0;
    hidden var _mpp as Float = 2.5;
    hidden var _cx as Number = 120;
    hidden var _cy as Number = POS_Y;
    hidden var _reach as Float = 400.0;

    function initialize(route as NavRoute, stats as RideStats) {
        View.initialize();
        _route = route;
        _stats = stats;
        _sep = str(Rez.Strings.DecimalSep);
    }

    //! Beim Abkommen kommt die Karte nach vorn: Dort sieht man den Weg
    //! zurück (Entwurf „Ring und Seiten").
    function setState(s as NavState, speed as Float?) as Void {
        _state = s;
        _speed = speed;
        if (s.leftRoute) { _page = 0; }
        WatchUi.requestUpdate();
    }

    function page() as Number {
        return _page;
    }

    //! hoch: auf der Karte näher heran, sonst eine Seite zurück.
    function up() as Void {
        if (_page != 0) {
            _page = (_page + pages() - 1) % pages();
        } else if (_zoom > 0) {
            _zoom--;
        }
        WatchUi.requestUpdate();
    }

    //! runter: auf der Karte weiter weg, sonst eine Seite weiter.
    function down() as Void {
        if (_page != 0) {
            _page = (_page + 1) % pages();
        } else if (_zoom < ZOOM_MPP.size() - 1) {
            _zoom++;
        }
        WatchUi.requestUpdate();
    }

    //! Wie viele Seiten es gerade gibt.
    function pages() as Number {
        return _stats.bests == null ? PAGES : PAGES + 1;
    }

    function nextPage() as Void {
        _page = (_page + 1) % pages();
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        if (_page != 0 || (_state != null && (_state as NavState).arrived)) {
            dc.setColor(TbColors.TEXT_ON_FIELD, TbColors.FIELD);
            dc.clear();
            if (_page == 1) {
                drawRide(dc, w);
            } else if (_page == 2) {
                drawMountain(dc, w);
            } else if (_page == 3) {
                drawBests(dc, w);
            } else {
                drawArrived(dc, w);
            }
            drawRing(dc, w, _state);
            return;
        }
        dc.setColor(TbColors.TEXT, TbColors.GROUND);
        dc.clear();
        if (!_route.isReady()) {
            dc.setColor(TbColors.TEXT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, dc.getHeight() / 2, Graphics.FONT_SMALL,
                str(Rez.Strings.Loading) + " " + (_route.progress() * 100).toNumber() + " %",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var s = _state;
        if (s == null) {
            drawOverview(dc, w);
            drawRing(dc, w, null);
            return;
        }
        _cx = w / 2;
        _cy = POS_Y;
        _px = s.x;
        _py = s.y;
        _mpp = ZOOM_MPP[_zoom];
        // Der Kreis der Anzeige hat Radius 120 um (120, 120), die Position
        // steht 8 px darunter: Weiter als 135 px reicht kein Strich.
        _reach = 135 * _mpp;
        _sin = Math.sin(s.heading).toFloat();
        _cos = Math.cos(s.heading).toFloat();

        drawRoute(dc, s);
        if (s.offRoute) {
            drawRejoin(dc, s);
        }
        drawNorth(dc, s, w);
        drawMe(dc);
        if (s.offRoute) {
            drawOffField(dc, s, w);
        } else {
            drawNextField(dc, s, w);
        }
        // Der schwarze Rand, auf dem der Ring liegt (Karte innen bis MAP_R).
        dc.setColor(TbColors.FIELD, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(w / 2 - TbRing.MAP_R + 2);
        dc.drawCircle(w / 2, w / 2, (w / 2 + TbRing.MAP_R) / 2 + 1);
        dc.setPenWidth(1);
        drawRing(dc, w, s);
    }

    // --- Ring --------------------------------------------------------------

    //! Grau die ganze Route, darauf die Trails, darüber der gefahrene Teil
    //! (abseits in Warnfarbe), zuletzt die Marke.
    hidden function drawRing(dc as Dc, w as Number, s as NavState?) as Void {
        var c = w / 2;
        var len = _route.lengthM;
        dc.setPenWidth(TbRing.RING_W);
        arc(dc, c, 0.0, 1.0, TbColors.MUTED_DARK);
        if (_route.isReady()) {
            var cum = _route.cum;
            for (var k = 0; k < _route.secFrom.size(); k++) {
                arc(dc, c, TbRing.share(cum[_route.secFrom[k]], len), TbRing.share(cum[_route.secTo[k]], len),
                    TbColors.gradeOnDark(_route.secGrade[k]));
            }
        }
        dc.setPenWidth(1);
        if (s == null) { return; }
        var at = s.arrived ? 1.0 : TbRing.share(s.alongM, len);
        dc.setPenWidth(TbRing.RING_W);
        arc(dc, c, 0.0, at, s.offRoute ? TbColors.WARNING : TbColors.ROUTE);
        dc.setPenWidth(1);
        var a = Math.toRadians(TbRing.deg(at));
        var ux = Math.cos(a).toFloat();
        var uy = -Math.sin(a).toFloat();
        for (var layer = 0; layer < 2; layer++) {
            var g = layer == 0 ? 2 : 0;
            var half = 6 + g;
            var outer = c + 1 + g;
            var inner = TbRing.RING_R - 11 - g;
            dc.setColor(layer == 0 ? TbColors.FIELD : TbColors.TEXT_ON_FIELD, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([
                [(c + ux * outer - uy * half).toNumber(), (c + uy * outer + ux * half).toNumber()],
                [(c + ux * outer + uy * half).toNumber(), (c + uy * outer - ux * half).toNumber()],
                [(c + ux * inner).toNumber(), (c + uy * inner).toNumber()]
            ]);
        }
    }

    hidden function arc(dc as Dc, c as Number, f0 as Float, f1 as Float, color as Number) as Void {
        var a = TbRing.deg(f0);
        var b = TbRing.deg(f1);
        if (a == b) { return; }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(c, c, TbRing.RING_R, Graphics.ARC_CLOCKWISE, (a + 360) % 360, (b + 360) % 360);
    }

    // --- Karte -------------------------------------------------------------

    hidden function sx(x as Float, y as Float) as Number {
        return _cx + (((x - _px) * _cos - (y - _py) * _sin) / _mpp).toNumber();
    }

    hidden function sy(x as Float, y as Float) as Number {
        return _cy - (((x - _px) * _sin + (y - _py) * _cos) / _mpp).toNumber();
    }

    //! Ein Stück a→b, wenn seine Hülle das Quadrat ±reach um die Position
    //! schneidet — auch eines, dessen Enden beide draußen liegen. [joint]:
    //! ein Kreis am Ende, damit dicke Striche an Knicken nicht klaffen
    //! (MIP zeichnet ohne Glättung, die Enden sind eckig).
    hidden function seg(dc as Dc, ax as Float, ay as Float, bx as Float, by as Float, joint as Number) as Void {
        var minX = (ax < bx ? ax : bx) - _px;
        var maxX = (ax < bx ? bx : ax) - _px;
        var minY = (ay < by ? ay : by) - _py;
        var maxY = (ay < by ? by : ay) - _py;
        if (minX > _reach || maxX < -_reach || minY > _reach || maxY < -_reach) { return; }
        var x1 = sx(ax, ay);
        var y1 = sy(ax, ay);
        var x2 = sx(bx, by);
        var y2 = sy(bx, by);
        dc.drawLine(x1, y1, x2, y2);
        if (joint > 0) { dc.fillCircle(x2, y2, joint); }
    }

    //! Ohne GPS-Fix die ganze Route, genordet und eingepasst, mit Start
    //! und den Trailköpfen, darunter „Warte auf GPS" (#449, Feldbefund
    //! 2026-11-05: bis zum ersten Fix sah man nichts). Je Linie höchstens
    //! [OVERVIEW_SEGS] Stücke — jeder [stride]-te Punkt (Watchdog).
    //! Eine Testroute (rel) liegt um ihren ersten Punkt wie jede andere.
    hidden function drawOverview(dc as Dc, w as Number) as Void {
        var nb = _route.blockCount();
        if (nb == 0) { return; }
        var minX = _route.bMinX[0];
        var maxX = _route.bMaxX[0];
        var minY = _route.bMinY[0];
        var maxY = _route.bMaxY[0];
        for (var b = 1; b < nb; b++) {
            if (_route.bMinX[b] < minX) { minX = _route.bMinX[b]; }
            if (_route.bMaxX[b] > maxX) { maxX = _route.bMaxX[b]; }
            if (_route.bMinY[b] < minY) { minY = _route.bMinY[b]; }
            if (_route.bMaxY[b] > maxY) { maxY = _route.bMaxY[b]; }
        }
        var span = maxX - minX > maxY - minY ? maxX - minX : maxY - minY;
        _px = (minX + maxX) / 2;
        _py = (minY + maxY) / 2;
        _mpp = span / (2.0 * OVERVIEW_R);
        if (_mpp < 0.5) { _mpp = 0.5; }
        _sin = 0.0;
        _cos = 1.0;
        _cx = w / 2;
        _cy = w / 2 - 20;
        _reach = span + 1.0;
        var n = _route.size();
        var stride = (n + OVERVIEW_SEGS - 1) / OVERVIEW_SEGS;
        if (stride < 1) { stride = 1; }
        for (var pass = 0; pass < 2; pass++) {
            var width = pass == 0 ? BAND_W : BAND_W - 4;
            dc.setColor(pass == 0 ? TbColors.ROUTE_EDGE : TbColors.ROUTE, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(width);
            strided(dc, 0, n - 1, stride, width / 2);
        }
        dc.setPenWidth(TRAIL_W - 1);
        var k;
        for (k = 0; k < _route.secFrom.size(); k++) {
            dc.setColor(TbColors.grade(_route.secGrade[k]), Graphics.COLOR_TRANSPARENT);
            strided(dc, _route.secFrom[k], _route.secTo[k] < n - 1 ? _route.secTo[k] : n - 1, stride, 0);
        }
        dc.setPenWidth(1);
        var xs = _route.xs;
        var ys = _route.ys;
        for (k = 0; k < _route.secFrom.size(); k++) {
            var head = _route.secFrom[k];
            drawShield(dc, sx(xs[head], ys[head]), sy(xs[head], ys[head]), _route.secGrade[k], 4, true, TbColors.GROUND);
        }
        // Der Start: ein schwarzer Punkt mit weißem Saum.
        var x0 = sx(xs[0], ys[0]);
        var y0 = sy(xs[0], ys[0]);
        dc.setColor(TbColors.GROUND, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x0, y0, 7);
        dc.setColor(TbColors.TEXT, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x0, y0, 5);
        field(dc, w, FIELD_Y, TbColors.FIELD);
        dc.setColor(TbColors.MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, FIELD_Y + 2, Graphics.FONT_XTINY, str(Rez.Strings.WaitGps), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(TbColors.TEXT_ON_FIELD, Graphics.COLOR_TRANSPARENT);
        numberLine(dc, w / 2, FIELD_Y + 28, meters(_route.lengthM), _route.climbLeft(0.0));
        // Der schwarze Rand, auf dem der Ring liegt.
        dc.setColor(TbColors.FIELD, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(w / 2 - TbRing.MAP_R + 2);
        dc.drawCircle(w / 2, w / 2, (w / 2 + TbRing.MAP_R) / 2 + 1);
        dc.setPenWidth(1);
    }

    //! Die Linie [lo, hi] über jeden [stride]-ten Punkt, das Ende immer.
    hidden function strided(dc as Dc, lo as Number, hi as Number, stride as Number, joint as Number) as Void {
        if (hi <= lo) { return; }
        var xs = _route.xs;
        var ys = _route.ys;
        var a = lo;
        while (a < hi) {
            var b = a + stride < hi ? a + stride : hi;
            seg(dc, xs[a], ys[a], xs[b], ys[b], joint);
            a = b;
        }
    }

    //! Die Stücke i in [lo, hi) — nur aus Blöcken, deren Hülle das
    //! Quadrat ±reach um die Position schneidet, und Punkte, die näher als
    //! 4 px am zuletzt gezeichneten liegen, übersprungen (Watchdog,
    //! NavRoute; bei 6 m Punktabstand und 2,5 m/px sonst jeder zweite
    //! Strich unsichtbar kurz).
    hidden function range(dc as Dc, lo as Number, hi as Number, joint as Number) as Void {
        if (hi <= lo) { return; }
        var xs = _route.xs;
        var ys = _route.ys;
        var bs = NavRoute.BLOCK;
        var r = _reach;
        var step = 4 * _mpp;
        var have = false;
        var ax = 0.0;
        var ay = 0.0;
        for (var b = lo / bs; b < _route.blockCount(); b++) {
            var first = b * bs;
            if (first >= hi) { break; }
            if (_route.bMinX[b] - _px > r || _route.bMaxX[b] - _px < -r
                || _route.bMinY[b] - _py > r || _route.bMaxY[b] - _py < -r) {
                have = false;
                continue;
            }
            var i = first < lo ? lo : first;
            var last = first + bs < hi ? first + bs : hi;
            if (!have) {
                ax = xs[i];
                ay = ys[i];
                have = true;
            }
            for (i = i + 1; i <= last; i++) {
                var x = xs[i];
                var y = ys[i];
                var d = (x > ax ? x - ax : ax - x) + (y > ay ? y - ay : ay - y);
                if (d < step && i < hi) { continue; }
                seg(dc, ax, ay, x, y, joint);
                ax = x;
                ay = y;
            }
        }
    }

    //! Zuerst die Abzweigungen voraus (Stummel in Grau, unter allem), dann
    //! der gefahrene Teil dünn, voraus Rand, Band und die Trails der Route;
    //! zuletzt die Schilder an den Trailköpfen voraus.
    hidden function drawRoute(dc as Dc, s as NavState) as Void {
        var xs = _route.xs;
        var ys = _route.ys;
        var n = xs.size();
        var at = _route.segmentAt(s.alongM);
        var split = _route.pointAt(s.alongM);
        var mx = split[0];
        var my = split[1];

        dc.setColor(TbColors.BRANCH, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(BRANCH_W);
        var brAt = _route.brAt;
        for (var k = 0; k < brAt.size(); k++) {
            var j = brAt[k];
            if (j <= at) { continue; }
            seg(dc, xs[j], ys[j], _route.brX[k], _route.brY[k], 0);
        }

        dc.setColor(TbColors.ROUTE_EDGE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(DONE_W);
        range(dc, 0, at, 0);
        seg(dc, xs[at], ys[at], mx, my, 0);

        for (var pass = 0; pass < 2; pass++) {
            var width = pass == 0 ? EDGE_W : BAND_W;
            dc.setColor(pass == 0 ? TbColors.ROUTE_EDGE : TbColors.ROUTE, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(width);
            seg(dc, mx, my, xs[at + 1], ys[at + 1], width / 2);
            range(dc, at + 1, n - 1, width / 2);
        }

        dc.setPenWidth(TRAIL_W);
        var k;
        for (k = 0; k < _route.secFrom.size(); k++) {
            var to = _route.secTo[k];
            if (to <= at) { continue; }
            dc.setColor(TbColors.grade(_route.secGrade[k]), Graphics.COLOR_TRANSPARENT);
            var from = _route.secFrom[k];
            if (from <= at) {
                seg(dc, mx, my, xs[at + 1], ys[at + 1], 0);
                from = at + 1;
            }
            range(dc, from, to < n - 1 ? to : n - 1, 0);
        }
        dc.setPenWidth(1);

        for (k = 0; k < _route.secFrom.size(); k++) {
            var head = _route.secFrom[k];
            if (head <= at) { continue; }
            var hx = sx(xs[head], ys[head]);
            var hy = sy(xs[head], ys[head]);
            var dx = hx - 120;
            var dy = hy - 120;
            if (hy < FIELD_Y - 8 && dx * dx + dy * dy < (TbRing.MAP_R - 9) * (TbRing.MAP_R - 9)) {
                drawShield(dc, hx, hy, _route.secGrade[k], 6, true, TbColors.GROUND);
            }
        }
    }

    //! Der S-Grad als Form (Design 6): ○ S0, ● S1, ■ S2, ◆ S3, ohne Grad
    //! ein grauer Punkt. [onMap]: Farbe des hellen Satzes mit weißem Saum,
    //! sonst die des dunklen Satzes für die schwarze Infofläche.
    hidden function drawShield(dc as Dc, x as Number, y as Number, g as Number, r as Number, onMap as Boolean, seam as Number) as Void {
        var c = onMap ? TbColors.grade(g) : TbColors.gradeOnDark(g);
        for (var layer = 0; layer < 2; layer++) {
            var rr = layer == 0 ? r + 2 : r;
            dc.setColor(layer == 0 ? seam : c, Graphics.COLOR_TRANSPARENT);
            if (g == 2) {
                dc.fillRectangle(x - rr, y - rr, 2 * rr + 1, 2 * rr + 1);
            } else if (g == 3) {
                var d = rr + 2;
                dc.fillPolygon([[x, y - d], [x + d, y], [x, y + d], [x - d, y]]);
            } else {
                dc.fillCircle(x, y, rr);
            }
        }
        if (g == 0) {
            dc.setColor(seam, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, y, r - 3);
        }
    }

    //! Die eigene Position: ein Pfeil nach oben (die Ansicht dreht mit),
    //! schwarz mit weißem Saum.
    hidden function drawMe(dc as Dc) as Void {
        var cx = _cx;
        var cy = _cy;
        dc.setColor(TbColors.GROUND, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx, cy - 18], [cx + 14, cy + 14], [cx, cy + 7], [cx - 14, cy + 14]]);
        dc.setColor(TbColors.TEXT, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx, cy - 13], [cx + 11, cy + 11], [cx, cy + 5], [cx - 11, cy + 11]]);
    }

    //! Norden am Rand — die Karte dreht mit der Fahrt, so bleibt die
    //! Himmelsrichtung lesbar.
    hidden function drawNorth(dc as Dc, s as NavState, w as Number) as Void {
        var r = TbRing.MAP_R - 14;
        var x = (w / 2 - r * Math.sin(s.heading)).toNumber();
        var y = (w / 2 - r * Math.cos(s.heading)).toNumber();
        if (y > FIELD_Y - 14) { return; }
        dc.setColor(TbColors.TEXT, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, 12);
        dc.setColor(TbColors.GROUND, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, "N", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Abseits: ein gestrichelter Strich zum Punkt der Linie 50 m voraus
    //! und ein Pfeil darauf (wie 9.3), beides in Warnfarbe.
    hidden function drawRejoin(dc as Dc, s as NavState) as Void {
        var tx = sx(s.rejoinX, s.rejoinY);
        var ty = sy(s.rejoinX, s.rejoinY);
        var dx = (tx - _cx).toFloat();
        var dy = (ty - _cy).toFloat();
        var len = Math.sqrt(dx * dx + dy * dy).toFloat();
        if (len < 1) { return; }
        var ux = dx / len;
        var uy = dy / len;
        var reach = len < 95 ? len : 95.0;
        dc.setColor(TbColors.WARNING, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        for (var d = 20.0; d < reach; d += 11) {
            var e = d + 6 < reach ? d + 6 : reach;
            dc.drawLine(_cx + (ux * d).toNumber(), _cy + (uy * d).toNumber(), _cx + (ux * e).toNumber(), _cy + (uy * e).toNumber());
        }
        dc.setPenWidth(1);
        var tip = 44;
        var base = 24;
        for (var layer = 0; layer < 2; layer++) {
            var grow = layer == 0 ? 4 : 0;
            dc.setColor(layer == 0 ? TbColors.GROUND : TbColors.WARNING, Graphics.COLOR_TRANSPARENT);
            var bx = _cx + ux * (base - grow);
            var by = _cy + uy * (base - grow);
            var half = 11 + grow;
            dc.fillPolygon([
                [(_cx + ux * (tip + grow)).toNumber(), (_cy + uy * (tip + grow)).toNumber()],
                [(bx - uy * half).toNumber(), (by + ux * half).toNumber()],
                [(bx + uy * half).toNumber(), (by - ux * half).toNumber()]
            ]);
        }
    }

    // --- Infofläche --------------------------------------------------------

    hidden function field(dc as Dc, w as Number, top as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, top, w, dc.getHeight() - top);
    }

    //! „Was kommt als Nächstes?" (Design 13): auf einem Trail Schild,
    //! Name und der Rest (den Anteil zeigt der Ring);
    //! davor Schild und Name des nächsten Trails mit Weg und Anstieg bis
    //! dorthin; ohne Trail voraus „Bis zum Ziel".
    hidden function drawNextField(dc as Dc, s as NavState, w as Number) as Void {
        field(dc, w, FIELD_Y, TbColors.FIELD);
        var cx = w / 2;
        var cum = _route.cum;
        var on = _route.sectionAt(s.alongM);
        if (on >= 0) {
            var b = cum[_route.secTo[on]];
            shieldLine(dc, cx, FIELD_Y + 2, _route.secGrade[on], _route.secName[on]);
            numberLine(dc, cx, FIELD_Y + 28, meters(b - s.alongM), null);
            return;
        }
        var next = _route.nextSection(s.alongM);
        if (next >= 0) {
            var head = cum[_route.secFrom[next]];
            shieldLine(dc, cx, FIELD_Y + 2, _route.secGrade[next], _route.secName[next]);
            numberLine(dc, cx, FIELD_Y + 28, meters(head - s.alongM), _route.climbBetween(s.alongM, head));
            return;
        }
        dc.setColor(TbColors.MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, FIELD_Y + 2, Graphics.FONT_XTINY, str(Rez.Strings.ToGoal), Graphics.TEXT_JUSTIFY_CENTER);
        numberLine(dc, cx, FIELD_Y + 28, meters(s.remainingM), _route.climbLeft(s.alongM));
    }

    //! Schild und Name, zusammen mittig. Ist der Name für die Breite des
    //! Kreises auf dieser Höhe zu lang, nimmt er die kleinere Schrift und
    //! erst dann ein „…" (Feldbefund 2026-11-05: „Schlosswald-Trai…" schnitt
    //! der runde Rand ab).
    hidden function shieldLine(dc as Dc, cx as Number, y as Number, g as Number, name as String) as Void {
        var font = Graphics.FONT_TINY;
        var fh = dc.getFontHeight(font);
        var room = chord(cx, y + fh) - 26;
        var tw = dc.getTextWidthInPixels(name, font);
        if (tw > room) {
            font = Graphics.FONT_XTINY;
            fh = dc.getFontHeight(font);
            room = chord(cx, y + fh) - 26;
            tw = dc.getTextWidthInPixels(name, font);
        }
        if (tw > room) {
            var cut = name.length();
            var shown = name;
            while (cut > 1 && tw > room) {
                cut--;
                shown = name.substring(0, cut) + "…";
                tw = dc.getTextWidthInPixels(shown, font);
            }
            name = shown;
        }
        var x = cx - (tw + 20) / 2;
        drawShield(dc, x + 6, y + fh / 2, g, 5, false, TbColors.FIELD);
        dc.setColor(TbColors.TEXT_ON_FIELD, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 20, y, font, name, Graphics.TEXT_JUSTIFY_LEFT);
    }

    //! Die Breite des Kreises (Radius [r] = [cx]) auf der Höhe [y].
    hidden function chord(r as Number, y as Number) as Number {
        var d = y > r ? y - r : r - y;
        if (d >= r) { return 0; }
        return (2 * Math.sqrt(r * r - d * d)).toNumber();
    }

    //! „1,2 km ▲80": der Weg weiß, der Anstieg in Lime mit gezeichnetem
    //! Pfeil (die Systemschrift hat keinen).
    hidden function numberLine(dc as Dc, cx as Number, y as Number, dist as String, climb as Float?) as Void {
        var font = Graphics.FONT_SMALL;
        var up = climb != null && climb >= 1 ? (climb as Float).toNumber().toString() : null;
        var dw = dc.getTextWidthInPixels(dist, font);
        var uw = up == null ? 0 : dc.getTextWidthInPixels(up, font) + 22;
        var x = cx - (dw + uw) / 2;
        dc.setColor(TbColors.TEXT_ON_FIELD, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, dist, Graphics.TEXT_JUSTIFY_LEFT);
        if (up != null) {
            var ax = x + dw + 14;
            var my = y + dc.getFontHeight(font) / 2;
            dc.setColor(TbColors.ROUTE, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[ax, my - 7], [ax + 6, my + 4], [ax - 6, my + 4]]);
            dc.drawText(ax + 8, y, font, up, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    //! Abseits schlägt alles: die Fläche in Warnfarbe, der Abstand groß.
    hidden function drawOffField(dc as Dc, s as NavState, w as Number) as Void {
        field(dc, w, FIELD_Y, TbColors.WARNING);
        dc.setColor(TbColors.TEXT_ON_FIELD, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, FIELD_Y + 2, Graphics.FONT_TINY, str(Rez.Strings.OffRoute), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, FIELD_Y + 28, Graphics.FONT_SMALL, meters(s.offM), Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Angekommen: die Runde in Zahlen — Strecke, Fahrzeit, bergauf und
    //! die befahrenen Trails als Schilder (Betreiber 2026-11-04: „Ja").
    hidden function drawArrived(dc as Dc, w as Number) as Void {
        var cx = w / 2;
        dc.setColor(TbColors.ROUTE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 30, Graphics.FONT_TINY, str(Rez.Strings.Arrived), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(TbColors.TEXT_ON_FIELD, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 60, Graphics.FONT_LARGE, km(_stats.distanceM) + " km", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx - 36, 112, Graphics.FONT_SMALL, clock(_stats.movingS) + " h", Graphics.TEXT_JUSTIFY_CENTER);
        climbText(dc, cx + 40, 112, _stats.climbM, TbColors.TEXT_ON_FIELD);
        var n = _stats.riddenCount();
        dc.setColor(TbColors.MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 148, Graphics.FONT_XTINY, n + " " + str(Rez.Strings.Trails), Graphics.TEXT_JUSTIFY_CENTER);
        var x = cx - (n - 1) * 10;
        for (var k = 0; k < _stats.ridden.size(); k++) {
            if (!_stats.ridden[k]) { continue; }
            drawShield(dc, x, 186, _route.secGrade[k], 5, false, TbColors.FIELD);
            x += 20;
        }
        if (_stats.bests != null) {
            dc.setColor(TbColors.MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 202, Graphics.FONT_XTINY,
                str(Rez.Strings.AirShort) + " " + seconds(_stats.best("ja")) + " · "
                    + str(Rez.Strings.WheelieShort) + " " + _stats.best("wl") + " m",
                Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    //! „Sprünge": die Bestwerte der Erkennung vom Handy (#36, Konzept 9.2)
    //! — längster Wheelie groß, darunter längste Flugzeit, größter Winkel
    //! und die Anzahlen. Die Uhr misst nichts davon (Entscheidung 1).
    hidden function drawBests(dc as Dc, w as Number) as Void {
        big(dc, w, str(Rez.Strings.WheelieM), _stats.best("wl").toString());
        cell(dc, w, 0, 104, str(Rez.Strings.Airtime), seconds(_stats.best("ja")), TbColors.TEXT_ON_FIELD);
        cell(dc, w, 1, 104, str(Rez.Strings.Angle), _stats.best("wa") + "°", TbColors.TEXT_ON_FIELD);
        cell(dc, w, 0, 150, str(Rez.Strings.Jumps), _stats.best("jn").toString(), TbColors.TEXT_ON_FIELD);
        cell(dc, w, 1, 150, str(Rez.Strings.Wheelies), _stats.best("wn").toString(), TbColors.TEXT_ON_FIELD);
    }

    // --- Zahlenseiten ------------------------------------------------------

    //! „Fahrt": Tempo groß, darunter Fahrzeit, Strecke, bergauf und der
    //! Puls — dezent in Grau (Betreiber 2026-11-04: „Ja, aber dezent").
    hidden function drawRide(dc as Dc, w as Number) as Void {
        var speed = _speed;
        big(dc, w, str(Rez.Strings.Speed), speed == null ? "--" : (speed * 3.6).format("%.0f"));
        var hr = _stats.heartRate;
        cell(dc, w, 0, 104, str(Rez.Strings.Time), clock(_stats.movingS), TbColors.TEXT_ON_FIELD);
        cell(dc, w, 1, 104, str(Rez.Strings.Distance), km(_stats.distanceM) + " km", TbColors.TEXT_ON_FIELD);
        label(dc, w, 0, 150, str(Rez.Strings.Climbed));
        climbText(dc, w / 2 - COL_X, 168, _stats.climbM, TbColors.TEXT_ON_FIELD);
        cell(dc, w, 1, 150, str(Rez.Strings.Pulse), hr == null ? "--" : hr.toString(), TbColors.MUTED);
    }

    //! „Berg": Steigung groß (Barometer über die letzten 30 m), Höhe, was
    //! bis zum nächsten Trailkopf und bis zum Ziel noch hoch geht, Uhrzeit.
    hidden function drawMountain(dc as Dc, w as Number) as Void {
        var g = _stats.grade();
        big(dc, w, str(Rez.Strings.Grade), g == null ? "--" : g.toString());
        var alt = _stats.altitude;
        cell(dc, w, 0, 104, str(Rez.Strings.Altitude), alt == null ? "--" : alt.toNumber() + " m", TbColors.TEXT_ON_FIELD);
        var s = _state;
        var toTrail = null;
        var toGoal = null;
        if (s != null && _route.isReady()) {
            var next = _route.nextSection(s.alongM);
            if (next >= 0) { toTrail = _route.climbBetween(s.alongM, _route.cum[_route.secFrom[next]]); }
            toGoal = _route.climbLeft(s.alongM);
        }
        label(dc, w, 1, 104, str(Rez.Strings.ToTrail));
        climbText(dc, w / 2 + COL_X, 122, toTrail, TbColors.TEXT_ON_FIELD);
        label(dc, w, 0, 150, str(Rez.Strings.ToFinish));
        climbText(dc, w / 2 - COL_X, 168, toGoal, TbColors.TEXT_ON_FIELD);
        var t = System.getClockTime();
        cell(dc, w, 1, 150, str(Rez.Strings.Clock), t.hour + ":" + t.min.format("%02d"), TbColors.TEXT_ON_FIELD);
        drawMeasure(dc, w);
    }

    //! Akku und Speicher für die Messungen (Konzept-Garmin 8) — nur im
    //! Vorführmodus; auf der Uhr stand die Zeile mitten in der Seite.
    (:demo)
    hidden function drawMeasure(dc as Dc, w as Number) as Void {
        var stats = System.getSystemStats();
        dc.setColor(TbColors.MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 198, Graphics.FONT_XTINY,
            stats.battery.format("%.0f") + " % · " + (stats.usedMemory / 1024) + " KB", Graphics.TEXT_JUSTIFY_CENTER);
    }

    (:nodemo)
    hidden function drawMeasure(dc as Dc, w as Number) as Void {}

    //! Oben die Einheit klein, darunter die Zahl groß, ein Strich.
    hidden function big(dc as Dc, w as Number, unit as String, value as String) as Void {
        var cx = w / 2;
        dc.setColor(TbColors.MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 20, Graphics.FONT_XTINY, unit, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(TbColors.TEXT_ON_FIELD, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 40, Graphics.FONT_NUMBER_MEDIUM, value, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(TbColors.MUTED_DARK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(36, 100, w - 36, 100);
        dc.drawLine(cx, 108, cx, 196);
        dc.setPenWidth(1);
    }

    //! Eine von vier Zellen: [col] 0 links, 1 rechts.
    hidden function cell(dc as Dc, w as Number, col as Number, y as Number, name as String, value as String, color as Number) as Void {
        label(dc, w, col, y, name);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2 + (col == 0 ? -COL_X : COL_X), y + 18, Graphics.FONT_SMALL, value, Graphics.TEXT_JUSTIFY_CENTER);
    }

    hidden function label(dc as Dc, w as Number, col as Number, y as Number, name as String) as Void {
        dc.setColor(TbColors.MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2 + (col == 0 ? -COL_X : COL_X), y, Graphics.FONT_XTINY, name, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! „▲120 m", mittig um [cx]: der Pfeil gezeichnet in Lime (die
    //! Systemschrift hat keinen), die Zahl in [color]; ohne Wert „--".
    hidden function climbText(dc as Dc, cx as Number, y as Number, m as Float?, color as Number) as Void {
        var font = Graphics.FONT_SMALL;
        if (m == null) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y, font, "--", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        var text = (m as Float).toNumber() + " m";
        var tw = dc.getTextWidthInPixels(text, font);
        var x = cx - (tw + 14) / 2;
        var my = y + dc.getFontHeight(font) / 2;
        dc.setColor(TbColors.ROUTE, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[x + 5, my - 7], [x + 11, my + 4], [x - 1, my + 4]]);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 14, y, font, text, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // --- Zahlen ------------------------------------------------------------

    //! „1,2" km mit dem Dezimalzeichen der Sprache.
    hidden function km(m as Float) as String {
        var tenths = (m / 100.0 + 0.5).toNumber();
        return (tenths / 10) + _sep + (tenths % 10);
    }

    //! Flugzeit „0,6 s" aus Millisekunden.
    hidden function seconds(ms as Number) as String {
        var tenths = (ms + 50) / 100;
        return (tenths / 10) + _sep + (tenths % 10) + " s";
    }

    //! Fahrzeit „1:12" (Stunden:Minuten).
    hidden function clock(secs as Float) as String {
        var m = secs.toNumber() / 60;
        return (m / 60) + ":" + (m % 60).format("%02d");
    }

    hidden function meters(m as Float) as String {
        return m < 1000 ? ((m + 0.5).toNumber() + " m") : (km(m) + " km");
    }

    hidden function str(id as ResourceId) as String {
        return WatchUi.loadResource(id) as String;
    }
}
