import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

//! Die eine Ansicht (Konzept-Garmin 1, Entwurf „Uhr-Ansicht" im
//! Designer, 2026-11-04): wie die Folgeansicht der App helle Karte und
//! dunkle Infofläche (Design 13), oben gedreht in Fahrtrichtung die
//! Route, die eigene Position im unteren Teil der Karte, unten „Was kommt
//! als Nächstes?". START schaltet auf die Zahlenseite. Kein Kartenbild —
//! nur Route, ihre Trails und deren Schilder.
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

    hidden var _route as NavRoute;
    hidden var _state as NavState? = null;
    hidden var _zoom as Number = 1;
    hidden var _numbers as Boolean = false;
    hidden var _speed as Float? = null;
    hidden var _altitude as Float? = null;
    hidden var _startedAt as Number;
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

    function initialize(route as NavRoute) {
        View.initialize();
        _route = route;
        _startedAt = System.getTimer();
        _sep = str(Rez.Strings.DecimalSep);
    }

    function setState(s as NavState, speed as Float?, altitude as Float?) as Void {
        _state = s;
        _speed = speed;
        _altitude = altitude;
        WatchUi.requestUpdate();
    }

    function zoomIn() as Void {
        if (_zoom > 0) { _zoom--; WatchUi.requestUpdate(); }
    }

    function zoomOut() as Void {
        if (_zoom < ZOOM_MPP.size() - 1) { _zoom++; WatchUi.requestUpdate(); }
    }

    function togglePage() as Void {
        _numbers = !_numbers;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        if (_numbers) {
            drawNumbers(dc, w);
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
            dc.setColor(TbColors.TEXT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, dc.getHeight() / 2, Graphics.FONT_SMALL, str(Rez.Strings.WaitGps),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        _cx = w / 2;
        _cy = s.arrived ? POS_Y - 30 : POS_Y;
        _px = s.x;
        _py = s.y;
        _mpp = ZOOM_MPP[_zoom];
        // Der Kreis der Anzeige hat Radius 120 um (120, 120), die Position
        // steht 8 px darunter: Weiter als 135 px reicht kein Strich.
        _reach = 135 * _mpp;
        _sin = Math.sin(s.heading).toFloat();
        _cos = Math.cos(s.heading).toFloat();

        drawRoute(dc, s);
        if (s.offRoute && !s.arrived) {
            drawRejoin(dc, s);
        }
        drawNorth(dc, s, w);
        drawMe(dc);
        if (s.arrived) {
            drawArrived(dc, w);
        } else if (s.offRoute) {
            drawOffField(dc, s, w);
        } else {
            drawNextField(dc, s, w);
        }
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
            if (hy < FIELD_Y - 8 && dx * dx + dy * dy < 110 * 110) {
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
        var r = w / 2 - 16;
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
        var reach = len < 110 ? len : 110.0;
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
    //! Name, ein Balken des gefahrenen Anteils in S-Farbe und der Rest;
    //! davor Schild und Name des nächsten Trails mit Weg und Anstieg bis
    //! dorthin; ohne Trail voraus „Bis zum Ziel".
    hidden function drawNextField(dc as Dc, s as NavState, w as Number) as Void {
        field(dc, w, FIELD_Y, TbColors.FIELD);
        var cx = w / 2;
        var cum = _route.cum;
        var on = _route.sectionAt(s.alongM);
        if (on >= 0) {
            var a = cum[_route.secFrom[on]];
            var b = cum[_route.secTo[on]];
            var share = b > a ? (s.alongM - a) / (b - a) : 0.0;
            dc.setColor(TbColors.MUTED_DARK, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(20, FIELD_Y, w - 40, 4);
            dc.setColor(TbColors.gradeOnDark(_route.secGrade[on]), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(20, FIELD_Y, ((w - 40) * share).toNumber(), 4);
            shieldLine(dc, cx, FIELD_Y + 4, _route.secGrade[on], _route.secName[on]);
            numberLine(dc, cx, FIELD_Y + 30, meters(b - s.alongM), null);
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

    //! Schild und Name, zusammen mittig.
    hidden function shieldLine(dc as Dc, cx as Number, y as Number, g as Number, name as String) as Void {
        var font = Graphics.FONT_TINY;
        var tw = dc.getTextWidthInPixels(name, font);
        var x = cx - (tw + 20) / 2;
        var fh = dc.getFontHeight(font);
        drawShield(dc, x + 6, y + fh / 2, g, 5, false, TbColors.FIELD);
        dc.setColor(TbColors.TEXT_ON_FIELD, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 20, y, font, name, Graphics.TEXT_JUSTIFY_LEFT);
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

    //! Angekommen: Haken in Lime, darunter die Runde in Zahlen.
    hidden function drawArrived(dc as Dc, w as Number) as Void {
        var top = FIELD_Y - 30;
        field(dc, w, top, TbColors.FIELD);
        var cx = w / 2;
        dc.setColor(TbColors.ROUTE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, top + 18, 13);
        dc.setColor(TbColors.FIELD, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawLine(cx - 6, top + 18, cx - 2, top + 23);
        dc.drawLine(cx - 2, top + 23, cx + 7, top + 12);
        dc.setPenWidth(1);
        dc.setColor(TbColors.ROUTE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, top + 32, Graphics.FONT_TINY, str(Rez.Strings.Arrived), Graphics.TEXT_JUSTIFY_CENTER);
        var total = km(_route.lengthM) + " km";
        var climb = _route.climbLeft(0.0);
        if (climb != null) { total += " · " + climb.toNumber() + " hm"; }
        dc.setColor(TbColors.TEXT_ON_FIELD, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, top + 58, Graphics.FONT_XTINY, total, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // --- Zahlenseite -------------------------------------------------------

    //! Dunkel wie die Infofläche: Tempo groß, darunter Zeit, Höhe und der
    //! Rest der Route, klein Akku und Speicher für die Messungen 1 und 3
    //! (Konzept-Garmin 8).
    hidden function drawNumbers(dc as Dc, w as Number) as Void {
        dc.setColor(TbColors.TEXT_ON_FIELD, TbColors.FIELD);
        dc.clear();
        var cx = w / 2;
        var speed = _speed;
        dc.drawText(cx, 22, Graphics.FONT_NUMBER_HOT, speed == null ? "--" : (speed * 3.6).format("%.0f"), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(TbColors.MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 74, Graphics.FONT_XTINY, str(Rez.Strings.Speed), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(TbColors.MUTED_DARK, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(30, 104, w - 30, 104);

        var secs = (System.getTimer() - _startedAt) / 1000;
        var time = (secs / 3600) + ":" + ((secs / 60) % 60).format("%02d") + ":" + (secs % 60).format("%02d");
        var alt = _altitude;
        row(dc, w, 108, str(Rez.Strings.Time), time);
        row(dc, w, 136, str(Rez.Strings.Altitude), alt == null ? "--" : alt.toNumber() + " m");
        var s = _state;
        if (s != null) {
            row(dc, w, 164, str(Rez.Strings.Left), km(s.remainingM) + " km");
        }

        var stats = System.getSystemStats();
        dc.setColor(TbColors.MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 196, Graphics.FONT_XTINY,
            stats.battery.format("%.0f") + " % · " + (stats.usedMemory / 1024) + "/" + (stats.totalMemory / 1024) + " KB",
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    hidden function row(dc as Dc, w as Number, y as Number, label as String, value as String) as Void {
        dc.setColor(TbColors.MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(38, y + 3, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(TbColors.TEXT_ON_FIELD, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w - 38, y, Graphics.FONT_SMALL, value, Graphics.TEXT_JUSTIFY_RIGHT);
    }

    // --- Zahlen ------------------------------------------------------------

    //! „1,2" km mit dem Dezimalzeichen der Sprache.
    hidden function km(m as Float) as String {
        var tenths = (m / 100.0 + 0.5).toNumber();
        return (tenths / 10) + _sep + (tenths % 10);
    }

    hidden function meters(m as Float) as String {
        return m < 1000 ? ((m + 0.5).toNumber() + " m") : (km(m) + " km");
    }

    hidden function str(id as ResourceId) as String {
        return WatchUi.loadResource(id) as String;
    }
}
