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
//! hoch/runter blättern: Karte → Fahrt → Berg, und sobald das Handy
//! Bestwerte schickt (G2), → Sprünge; den Zoom wählt die Uhr selbst
//! ([autoZoom]), von Hand im Aktionsmenü (langes HOCH, #513). Oben
//! auf der Karte (auf den Zahlenseiten unten) steht, was die Aufzeichnung
//! tut ([setRecord]). Kein Kartenbild — nur Route, ihre Trails und deren
//! Schilder.
class NavView extends WatchUi.View {
    //! Meter je Pixel der drei Zoomstufen: nah, mittel, weit.
    static const ZOOM_MPP = [1.0, 1.5, 4.0] as Array<Float>;
    //! Der Zoom von selbst ([autoZoom], #513).
    static const ZOOM_AUTO = -1;
    //! Die eigene Position, und wo die Infofläche beginnt (240er Anzeige;
    //! darunter wird der Kreis zu schmal für zwei Zeilen).
    static const POS_Y = /*L:pos_y*/128;
    static const FIELD_Y = /*L:field_y*/160;
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
    static const COL_X = /*L:col_x*/54;
    //! Die Übersicht ohne GPS: so viele Stücke je Linie höchstens, und der
    //! Radius, in den sie passt (innerhalb TbRing.MAP_R, über dem Text).
    static const OVERVIEW_SEGS = 120;
    static const OVERVIEW_R = /*L:overview_r*/62;
    //! So viele Striche zeichnet ein Bild höchstens (`seg`), dann bricht es
    //! ab — lieber ein unvollständiges Bild als der Watchdog. Die fēnix 5
    //! brach am Gerät schon ab, wo der Simulator noch zeichnete
    //! (CIQ_LOG.YML, 2026-11-05: `seg` ← `strided` ← `drawOverview`).
    static const FRAME_SEGS = 400;
    //! Der Lader (Design 1q, Abschnitt 15): das Logo als Spur, darauf
    //! zeichnet es sich in der Marke ein, steht und springt zurück auf die
    //! Spur — MIP kennt kein Ausblenden. Mitte des Logos und Zeile darunter.
    static const LOADER_DRAW_MS = 850;
    static const LOADER_PERIOD_MS = 1400;
    static const LOGO_Y = /*L:logo_y*/104;
    static const LOADER_TEXT_Y = /*L:loader_text_y*/176;
    //! Zweizeilige Texte des Laders stehen höher: Bei y 176 schnitt der
    //! Kreis die zweite Zeile ab (Simulator fēnix 5, 2026-11-07).
    static const TWO_LINE_TEXT_Y = /*L:two_line_text_y*/150;

    hidden var _route as NavRoute;
    hidden var _state as NavState? = null;
    //! Die Seiten: Karte, Fahrt, Berg — und Sprünge, wenn Bestwerte da sind.
    static const PAGES = 3;

    hidden var _zoom as Number = 1;
    //! [ZOOM_AUTO] oder die Stufe, die man im Menü gewählt hat. Von Hand
    //! gilt sie bis zum nächsten Trailkopf: [_manualNext] ist der Trail,
    //! der beim Wählen voraus lag (-2: noch kein Stand).
    hidden var _zoomMode as Number = ZOOM_AUTO;
    hidden var _manualNext as Number = -2;
    hidden var _page as Number = 0;
    hidden var _speed as Float? = null;
    //! Der Stand kommt von der Position des Handys, nicht vom eigenen GPS:
    //! Der Pfeil ist hohl, darüber steht „Handy-GPS".
    hidden var _phone as Boolean = false;
    hidden var _stats as RideStats;
    hidden var _sep as String;
    //! Die Zeilen der Karte, die in jedem Bild stehen, einmal geladen (die
    //! übrigen Seiten laden ihre wenigen selbst — jede hier gehaltene
    //! Zeichenkette kostet dauerhaft Arbeitsspeicher).
    hidden var _toGoal as String;
    hidden var _offRoute as String;

    // Die Drehung des laufenden Bilds (drawRoute und seine Helfer).
    hidden var _px as Float = 0.0;
    hidden var _py as Float = 0.0;
    hidden var _sin as Float = 0.0;
    hidden var _cos as Float = 1.0;
    hidden var _mpp as Float = 1.5;
    hidden var _cx as Number = 120;
    hidden var _cy as Number = POS_Y;
    hidden var _reach as Float = 400.0;
    hidden var _segLeft as Number = FRAME_SEGS;

    // Die Übersicht ohne Fix, einmal je Route in Bildpunkte gerechnet
    // (#449, 2026-11-05): Sie ändert sich nicht, bis der erste Fix kommt —
    // je Bild nur noch Linien zwischen fertigen Punkten, kein `sx`/`sy`.
    hidden var _ovX as Array<Number>? = null;
    hidden var _ovY as Array<Number>? = null;
    hidden var _ovStride as Number = 1;
    hidden var _ovHeads as Array<Number>? = null;

    //! Der Start wartet aufs Handy: der Text unter dem Lader, sonst null.
    hidden var _wait as String? = null;
    //! Die Navigation ist beendet: das ganze Logo und dieser Text.
    hidden var _ended as String? = null;
    //! Ohne Route die freie Fahrt (#484): die eigene Spur aus [_log], der
    //! Stand aus [setFreeFix], keine Infofläche „bis zum Ziel", kein Ring.
    hidden var _free as Boolean = false;
    hidden var _log as RideLog;
    hidden var _fixed as Boolean = false;
    hidden var _heading as Float = 0.0;
    //! Die Punkte des Logos (`resources/logo`), nur solange der Lader steht.
    hidden var _logo as Array<Number>? = null;
    hidden var _logoT as Number = 1;
    //! Die Aufzeichnung ([RideLog.state]) und ob ein markierter Trail läuft.
    hidden var _rec as Number = RideLog.IDLE;
    hidden var _trail as Boolean = false;
    //! Eine kurze Einblendung („Trail beginnt" …) bis [_toastUntil].
    hidden var _toast as String? = null;
    hidden var _toastUntil as Number = 0;
    //! Das Zeichen vor der Einblendung (#558, TbSym), -1: keins.
    hidden var _toastSym as Number = -1;
    //! #501: Die Frage, ob die Uhr die neue Linie nimmt, bis [_askUntil];
    //! [_askBig]: „START = JA" groß (die erste nach 1.3.x).
    hidden var _askUntil as Number = 0;
    hidden var _askBig as Boolean = false;
    static const TOAST_MS = 2500;
    //! Die Zeile der Aufzeichnung: oben auf der Karte, unten auf den
    //! Zahlenseiten (oben steht dort die Einheit).
    static const STATUS_TOP_Y = /*L:status_top_y*/44;
    static const STATUS_BOTTOM_Y = /*L:status_bottom_y*/214;

    function initialize(route as NavRoute, stats as RideStats, log as RideLog) {
        View.initialize();
        _route = route;
        _stats = stats;
        _log = log;
        _sep = str(Rez.Strings.DecimalSep);
        _toGoal = str(Rez.Strings.ToGoal);
        _offRoute = str(Rez.Strings.OffRoute);
    }

    //! Beim Abkommen kommt die Karte nach vorn: Dort sieht man den Weg
    //! zurück (Entwurf „Ring und Seiten").
    function setState(s as NavState, speed as Float?, phone as Boolean) as Void {
        _state = s;
        _phone = phone;
        // Mit dem ersten Fix braucht es die Übersicht nicht mehr — außer man
        // steht weiter abseits, als die Karte zeigen kann: dann passt die
        // ganze Linie in den Kreis (#498), und die ändert sich nicht.
        if (!beyondView(s.offM, _reach)) {
            _ovX = null;
            _ovY = null;
            _ovHeads = null;
        }
        _speed = speed;
        if (s.leftRoute) { _page = 0; }
        var next = _route.nextSection(s.alongM);
        var head = null;
        if (next >= 0 && !s.offRoute) { head = _route.cum[_route.secFrom[next]] - s.alongM; }
        followZoom(speed, head, next);
        WatchUi.requestUpdate();
    }

    //! Der Zoom von selbst ([autoZoom]), oder die Stufe von Hand, bis der
    //! Trail voraus ein anderer ist ([next], -1 ohne).
    hidden function followZoom(speed as Float?, head as Float?, next as Number) as Void {
        if (_zoomMode != ZOOM_AUTO) {
            if (_manualNext == -2) {
                _manualNext = next;
            } else if (next != _manualNext) {
                _zoomMode = ZOOM_AUTO;
            }
        }
        if (_zoomMode == ZOOM_AUTO) { _zoom = autoZoom(_zoom, speed, head); }
    }

    //! Die Zoomstufe von selbst (#513, Konzept-Garmin 11) aus der jetzigen
    //! [cur], dem Tempo (m/s) und dem Weg zum nächsten Trailkopf (null:
    //! keiner voraus): nah ab 150 m vor einem Trailkopf (hinaus erst ab
    //! 250 m), weit ab 7 m/s = 25 km/h (zurück erst unter 5,5 m/s), sonst
    //! mittel — je eine Schwelle hinein und eine hinaus, damit die Karte an
    //! der Grenze nicht springt. Die Zahlen stehen hier statt als
    //! Konstanten: Im Gerätebau kostet jede Konstante Speicher neben der
    //! Route (Vorführmodus 2026-11-12).
    static function autoZoom(cur as Number, speed as Float?, headM as Float?) as Number {
        if (headM != null && (headM < 150.0 || (cur == 0 && headM < 250.0))) { return 0; }
        var v = speed == null ? 0.0 : speed;
        if (v >= 7.0 || (cur == 2 && v >= 5.5)) { return 2; }
        return 1;
    }

    //! Die alte Ansicht lässt ihre Route los, bevor die neue lädt (#513):
    //! WatchUi gibt sie erst nach dem nächsten Bild frei, und bis dahin
    //! lagen alte Route und Logo des Laders zusammen über dem Speicher
    //! (Vorführmodus 2026-11-12, Out of Memory in `drawLoader` bei 1000
    //! Punkten). Bis dahin zeichnet sie [r], den Platzhalter.
    function forget(r as NavRoute) as Void {
        _route = r;
        _state = null;
        _ovX = null;
        _ovY = null;
        _ovHeads = null;
    }

    //! Der Start wartet aufs Handy: Statt einer Route steht der Lader mit
    //! [text]; null beendet das Warten.
    function setWaiting(text as String?) as Void {
        _wait = text;
    }

    function setEnded(text as String) as Void {
        _ended = text;
    }

    function isEnded() as Boolean {
        return _ended != null;
    }

    //! Keine Route da (Store-Bau): die freie Fahrt, bis eine Route kommt.
    function setFree() as Void {
        _free = true;
    }

    function isFree() as Boolean {
        return _free;
    }

    //! Ein Fix der freien Fahrt in Metern ([RideLog.toLocal]). Gedreht wird
    //! wie in der Navigation: in Fahrt nach dem GPS-Kurs, im Stand nach dem
    //! Kompass, sonst bleibt die letzte Richtung.
    function setFreeFix(x as Float, y as Float, gpsHeading as Float?, speed as Float?, compass as Float?) as Void {
        _fixed = true;
        _px = x;
        _py = y;
        _speed = speed;
        var moving = speed != null && speed >= NavTracker.HEADING_MIN_SPEED_MPS;
        if (moving && gpsHeading != null) {
            _heading = gpsHeading;
        } else if (!moving && compass != null) {
            _heading = compass;
        }
        followZoom(speed, null, -1);
        WatchUi.requestUpdate();
    }

    function page() as Number {
        return _page;
    }

    function zoom() as Number {
        return _zoom;
    }

    //! Die Wahl im Aktionsmenü (#513): [mode] [ZOOM_AUTO] oder eine Stufe;
    //! die Karte kommt nach vorn.
    function setZoomMode(mode as Number) as Void {
        _zoomMode = mode;
        if (mode != ZOOM_AUTO) {
            _zoom = mode;
            _manualNext = _state == null || _free ? -2 : _route.nextSection((_state as NavState).alongM);
        }
        _page = 0;
        WatchUi.requestUpdate();
    }

    function zoomMode() as Number {
        return _zoomMode;
    }

    //! Der Stand der Aufzeichnung für die Zeile oben bzw. unten.
    function setRecord(state as Number, trailOpen as Boolean) as Void {
        _rec = state;
        _trail = trailOpen;
        WatchUi.requestUpdate();
    }

    //! Eine kurze Einblendung für [TOAST_MS].
    function toast(text as String) as Void {
        _toast = text;
        _toastSym = -1;
        _toastUntil = System.getTimer() + TOAST_MS;
        WatchUi.requestUpdate();
    }

    //! #514: ein Ereignis der Erkennung vom Handy für 3 s — [k] "air"
    //! (Flugzeit), "wh" (Wheelie, [v] Meter) oder "st" (Stoppie), [v] in
    //! ms. Unbekanntes bleibt still.
    function cue(k as Object?, v as Object?) as Void {
        if (!(v instanceof Number)) { return; }
        // Zeichen und Zahl statt Wort (#558): Flugzeug, Wheelie, Stoppie.
        var air = "air".equals(k);
        var wh = "wh".equals(k);
        if (!air && !wh && !"st".equals(k)) { return; }
        _toast = wh ? v + " m" : seconds(v);
        _toastSym = air ? /*S:plane*/10 : wh ? /*S:wheelie*/11 : /*S:stoppie*/12;
        _toastUntil = System.getTimer() + 3000;
        WatchUi.requestUpdate();
    }

    //! Die Einblendung, solange sie steht (Tests).
    function toastText() as String? {
        return System.getTimer() - _toastUntil >= 0 ? null : _toast;
    }

    //! #501 (Konzept 2): Die Uhr fragt, ob sie die neue Linie nimmt. Wer
    //! nichts tut, nimmt sie, wenn [ms] um sind; START sagt ja, ZURÜCK nein
    //! (#513). [big]: „START = JA" groß, die erste Frage nach dem Update.
    function askRoute(ms as Number, big as Boolean) as Void {
        _askUntil = System.getTimer() + ms;
        _askBig = big;
        _page = 0;
        WatchUi.requestUpdate();
    }

    function askBig() as Boolean {
        return _askBig;
    }

    //! Die Frage ist beantwortet.
    function clearAsk() as Void {
        _askUntil = 0;
    }

    //! Steht die Frage noch?
    function asking() as Boolean {
        return _askUntil > 0 && System.getTimer() < _askUntil;
    }

    function prevPage() as Void {
        _page = (_page + pages() - 1) % pages();
        WatchUi.requestUpdate();
    }

    //! Wie viele Seiten es gerade gibt.
    function pages() as Number {
        return _stats.hasBests() ? PAGES + 1 : PAGES;
    }

    function nextPage() as Void {
        _page = (_page + 1) % pages();
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        _segLeft = FRAME_SEGS;
        var done = _ended;
        if (done != null) {
            drawLoader(dc, w, done, true, done.find("\n") != null ? TWO_LINE_TEXT_Y : LOADER_TEXT_Y);
            return;
        }
        var waiting = _wait;
        if (waiting != null || (!_route.isReady() && !_route.failed)) {
            drawLoader(dc, w, waiting != null ? waiting
                : str(Rez.Strings.Loading) + " " + (_route.progress() * 100).toNumber() + " %", false, LOADER_TEXT_Y);
            return;
        }
        _logo = null;
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
            if (!_free) { drawRing(dc, w, _state); }
            drawStatus(dc, w, STATUS_BOTTOM_Y);
            return;
        }
        if (_free) {
            drawFree(dc, w);
            drawDetect(dc, w);
            drawStatus(dc, w, STATUS_TOP_Y);
            return;
        }
        dc.setColor(TbColors.TEXT, TbColors.GROUND);
        dc.clear();
        if (_route.failed) {
            dc.setColor(TbColors.TEXT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, dc.getHeight() / 2, /*F:route_broken*/Graphics.FONT_SMALL, str(Rez.Strings.RouteBroken),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var s = _state;
        if (s == null) {
            drawOverview(dc, w);
            drawRing(dc, w, null);
            drawStatus(dc, w, STATUS_TOP_Y);
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
        // Weiter, als die Karte je zeigen kann (#498, fēnix 5 2026-11-08:
        // „12 km neben der Route“ und ein leeres Blatt): die ganze Linie
        // eingepasst, sonst sieht man keinen Strich.
        if (s.offRoute && beyondView(s.offM, _reach)) {
            drawFit(dc, w, s);
            mapBorder(dc, w);
            drawRing(dc, w, s);
            drawDetect(dc, w);
            drawStatus(dc, w, STATUS_TOP_Y);
            return;
        }
        _sin = Math.sin(s.heading).toFloat();
        _cos = Math.cos(s.heading).toFloat();

        drawRoute(dc, s);
        if (s.offRoute) {
            drawRejoin(dc, s);
        }
        drawNorth(dc, s.heading, w);
        drawMe(dc);
        if (s.offRoute) {
            drawOffField(dc, s, w);
        } else {
            drawNextField(dc, s, w);
        }
        mapBorder(dc, w);
        drawRing(dc, w, s);
        drawDetect(dc, w);
        drawStatus(dc, w, STATUS_TOP_Y);
    }

    //! #514: Das Handy erkennt Sprünge und Wheelies mit gelernter
    //! Halterung (`on` in den Bestwerten) — ein Punkt in Marke mit Bogen
    //! links am Rand der Karte. Ohne `on` nichts: Die Uhr behauptet keine
    //! Erkennung, die nicht läuft.
    hidden function drawDetect(dc as Dc, w as Number) as Void {
        if (_stats.best("on") != 1) { return; }
        var x = w / 2 - TbRing.MAP_R + 12;
        var y = w / 2;
        dc.setColor(TbColors.FIELD, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, 8);
        dc.setColor(TbColors.ROUTE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y + 2, 3);
        dc.setPenWidth(2);
        dc.drawArc(x, y + 2, 6, Graphics.ARC_COUNTER_CLOCKWISE, 30, 150);
        dc.setPenWidth(1);
    }

    //! Der schwarze Rand, auf dem der Ring liegt (Karte innen bis MAP_R).
    hidden function mapBorder(dc as Dc, w as Number) as Void {
        dc.setColor(TbColors.FIELD, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(w / 2 - TbRing.MAP_R + 2);
        dc.drawCircle(w / 2, w / 2, (w / 2 + TbRing.MAP_R) / 2 + 1);
        dc.setPenWidth(1);
    }

    //! Ist die Linie weiter entfernt, als die Karte zeigen kann? Der
    //! weiteste Zoom (4 m/px) reacht 135 px, also 540 m (#498).
    static function beyondView(offM as Float, reachM as Float) as Boolean {
        return offM > reachM;
    }

    //! Wie weit die Karte um die Position zeigt (#498, #500): 135 px je
    //! Zoomstufe. Der Vorführmodus (#498) sieht darin, welche Ansicht eine
    //! Szene nimmt.
    function reachM() as Float {
        return _reach;
    }

    //! Die ganze Linie eingepasst, wenn man weiter abseits steht, als die
    //! Karte je zeigen kann (#498): genordet, der nächste Punkt der Linie
    //! als Warnpunkt, ein gestrichelter Strich in die Richtung, in der man
    //! steht. Ohne eigenen Fix weiß man hier nichts von der Fahrtrichtung.
    hidden function drawFit(dc as Dc, w as Number, s as NavState) as Void {
        if (!overviewLine(dc, w)) { return; }
        var ax = sx(s.rejoinX, s.rejoinY);
        var ay = sy(s.rejoinX, s.rejoinY);
        var dx = (s.x - s.rejoinX).toFloat();
        var dy = (s.y - s.rejoinY).toFloat();
        var len = Math.sqrt(dx * dx + dy * dy).toFloat();
        dc.setColor(TbColors.WARNING, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.fillCircle(ax, ay, 4);
        if (len > 1.0) {
            var ux = (dx / len).toFloat();
            var uy = (-dy / len).toFloat();  // auf dem Bildschirm läuft y nach unten
            var lim = (TbRing.MAP_R - 4).toFloat();
            lim = lim * lim;
            for (var d = 8.0; d < 44.0; d += 9.0) {
                var x2 = ax + ux * (d + 5);
                var y2 = ay + uy * (d + 5);
                var ex = x2 - w / 2;
                var ey = y2 - w / 2;
                if (ex * ex + ey * ey > lim) { break; }
                dc.drawLine(ax + ux * d, ay + uy * d, x2, y2);
            }
        }
        dc.setPenWidth(1);
        drawOffField(dc, s, w);
    }

    // --- Aufzeichnung --------------------------------------------------------

    //! Was die Aufzeichnung tut (#558: Zeichen statt Wörter): vor START
    //! ein Dreieck in Lime rechts oben an der START-Taste, in der Pause
    //! zwei Balken auf der Warnfarbe bei [y], auf einem markierten Trail
    //! Lime mit „Trail"; sonst nur ein roter Punkt. Darüber die
    //! Einblendung, solange sie gilt.
    hidden function drawStatus(dc as Dc, w as Number, y as Number) as Void {
        var cx = w / 2;
        var text = null;
        var bg = TbColors.FIELD;
        var fg = TbColors.ROUTE;
        var idle = _rec == RideLog.IDLE;
        var asked = asking();
        if (idle) {
            // Vor START nur das Dreieck an der Taste (#558): rechts oben,
            // dort wo bei einer Frage „JA" steht — auf der Karte und den
            // Zahlenseiten gleich; die Frage hat den Platz selbst.
            if (!asked) {
                dc.setColor(TbColors.FIELD, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(/*L:ask_yes_x*/198 - 17, /*L:ask_yes_y*/64 - 11, 34, 22, 11);
                TbSym.draw(dc, /*S:play*/8, /*L:ask_yes_x*/198 - 8, /*L:ask_yes_y*/64 - 8, fg);
            }
        } else if (_rec == RideLog.PAUSED) {
            // Zwei Balken auf der Warnfarbe statt „PAUSE".
            dc.setColor(TbColors.WARNING, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(cx - 18, y - 11, 36, 22, 11);
            TbSym.draw(dc, /*S:pause*/9, cx - 8, y - 8, TbColors.TEXT_ON_FIELD);
        } else if (_trail) {
            text = str(Rez.Strings.RecTrail);
            bg = TbColors.ROUTE;
            fg = TbColors.TEXT;
        }
        if (_rec == RideLog.PAUSED) {
            // schon gezeichnet
        } else if (text == null) {
            if (!idle) {
                dc.setColor(TbColors.GROUND, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(cx, y, 6);
                dc.setColor(TbColors.S2, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(cx, y, 4);
            }
        } else {
            pill(dc, cx, y, text, /*F:status*/Graphics.FONT_XTINY, bg, fg);
        }
        if (asked) {
            drawAsk(dc, w, y == STATUS_TOP_Y ? /*L:ask_y_map*/86 : /*L:ask_y_page*/150);
            return;
        }
        var t = _toast;
        if (t == null) { return; }
        if (System.getTimer() - _toastUntil >= 0) {
            _toast = null;
            return;
        }
        var ty = y == STATUS_TOP_Y ? /*L:toast_y_map*/82 : /*L:toast_y_page*/176;
        if (_toastSym < 0) {
            pill(dc, cx, ty, t, /*F:toast*/Graphics.FONT_SMALL, TbColors.FIELD, TbColors.TEXT_ON_FIELD);
            return;
        }
        // Zeichen und Zahl (#558): das Schild so breit wie beide zusammen.
        var font = /*F:toast*/Graphics.FONT_SMALL;
        var sw = TbSym.width(_toastSym);
        var tw = dc.getTextWidthInPixels(t, font);
        var h = dc.getFontHeight(font);
        var x = cx - (sw + 5 + tw) / 2;
        dc.setColor(TbColors.FIELD, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x - 8, ty - h / 2 - 1, sw + 5 + tw + 16, h + 2, (h + 2) / 2);
        TbSym.draw(dc, _toastSym, x, ty - 8, TbColors.TEXT_ON_FIELD);
        dc.setColor(TbColors.TEXT_ON_FIELD, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + sw + 5, ty, font, t, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Eine Frage sieht immer gleich aus (#513, Konzept-Garmin 11): ein
    //! Schild mit der Frage und darunter ihre ablaufende Frist, „JA" neben
    //! START (rechts oben), „NEIN" neben ZURÜCK (rechts unten). Nach der
    //! Frist gilt ja. Die erste Frage nach dem Update sagt an START groß
    //! „START = JA".
    hidden function drawAsk(dc as Dc, w as Number, y as Number) as Void {
        pill(dc, w / 2, y, str(Rez.Strings.AskReplan), /*F:ask*/Graphics.FONT_XTINY, TbColors.FIELD, TbColors.TEXT_ON_FIELD);
        // Die Frist als Balken darunter, der kürzer wird.
        var left = _askUntil - System.getTimer();
        dc.setColor(TbColors.ROUTE, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(/*L:ask_bar_x*/40, y + /*L:ask_bar_dy*/16, left > 0 ? /*L:ask_bar_w*/128 * left / WatchCore.ASK_MS : 0, 4);
        // An den Tasten: START rechts oben, ZURÜCK rechts unten (fēnix 5).
        var yes = str(Rez.Strings.AskYes);
        pill(dc, _askBig ? /*L:ask_yes_big_x*/156 : /*L:ask_yes_x*/198, /*L:ask_yes_y*/64, _askBig ? "START = " + yes : yes,
            _askBig ? /*F:ask_yes_big*/Graphics.FONT_SMALL : /*F:ask_yes*/Graphics.FONT_XTINY, TbColors.ROUTE, TbColors.TEXT);
        pill(dc, /*L:ask_no_x*/194, /*L:ask_no_y*/176, str(Rez.Strings.AskNo), /*F:ask_no*/Graphics.FONT_XTINY, TbColors.MUTED_DARK, TbColors.TEXT_ON_FIELD);
    }

    hidden function pill(dc as Dc, cx as Number, y as Number, text as String, font as Graphics.FontType,
                         bg as Number, fg as Number) as Void {
        var tw = dc.getTextWidthInPixels(text, font);
        var h = dc.getFontHeight(font);
        dc.setColor(bg, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - tw / 2 - 8, y - h / 2 - 1, tw + 16, h + 2, (h + 2) / 2);
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, font, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
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
        if (_segLeft <= 0) { return; }
        _segLeft--;
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
        if (!overviewLine(dc, w)) { return; }
        field(dc, w, FIELD_Y, TbColors.FIELD);
        dc.setColor(TbColors.MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, FIELD_Y + /*L:field_line1_dy*/2, /*F:field_note*/Graphics.FONT_XTINY, str(Rez.Strings.WaitGps), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(TbColors.TEXT_ON_FIELD, Graphics.COLOR_TRANSPARENT);
        numberLine(dc, w / 2, FIELD_Y + /*L:field_line2_dy*/24, meters(_route.lengthM), _route.climbLeft(0.0));
        // Oben klein die Fassung der Uhr-App (Betreiber 2026-11-09): kurz
        // statt Commit und Datum — der Stempel steht in der Konsole beim
        // Bau, auf der Uhr steht, welche Fassung läuft (#500, #8).
        dc.setColor(TbColors.MUTED_DARK, Graphics.COLOR_TRANSPARENT);
        // Bei y 18 war der Kreis zu schmal (fēnix 5, 2026-11-05: halb
        // abgeschnitten) — tiefer und kurz (`tool/garmin_build.sh`).
        dc.drawText(w / 2, /*L:version_y*/56, /*F:version*/Graphics.FONT_XTINY, 'v' + TbVersion.VERSION, Graphics.TEXT_JUSTIFY_CENTER);
        mapBorder(dc, w);
    }

    //! Die Linie der Übersicht: Band, Trails, Schilder, Startpunkt. true,
    //! wenn etwas da ist. [overviewPoints] hat die Bildpunkte einmal je
    //! Route gerechnet; gezeichnet werden höchstens [OVERVIEW_SEGS] Striche.
    hidden function overviewLine(dc as Dc, w as Number) as Boolean {
        if (_ovX == null) { overviewPoints(w); }
        var ox = _ovX as Array<Number>;
        var oy = _ovY as Array<Number>;
        var m = ox.size();
        if (m < 2) { return false; }
        for (var pass = 0; pass < 2; pass++) {
            var width = pass == 0 ? BAND_W : BAND_W - 4;
            dc.setColor(pass == 0 ? TbColors.ROUTE_EDGE : TbColors.ROUTE, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(width);
            polyline(dc, ox, oy, 0, m - 1, width / 2);
        }
        dc.setPenWidth(TRAIL_W - 1);
        var n = _route.size();
        var k;
        for (k = 0; k < _route.secFrom.size(); k++) {
            dc.setColor(TbColors.grade(_route.secGrade[k]), Graphics.COLOR_TRANSPARENT);
            var to = _route.secTo[k] < n - 1 ? _route.secTo[k] : n - 1;
            var j1 = (to + _ovStride - 1) / _ovStride;
            polyline(dc, ox, oy, _route.secFrom[k] / _ovStride, j1 < m - 1 ? j1 : m - 1, 0);
        }
        dc.setPenWidth(1);
        var heads = _ovHeads as Array<Number>;
        for (k = 0; k < _route.secFrom.size(); k++) {
            drawShield(dc, heads[2 * k], heads[2 * k + 1], _route.secGrade[k], 4, true, TbColors.GROUND);
        }
        var x0 = ox[0];
        var y0 = oy[0];
        // Der Start: ein schwarzer Punkt mit weißem Saum.
        dc.setColor(TbColors.GROUND, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x0, y0, 7);
        dc.setColor(TbColors.TEXT, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x0, y0, 5);
        return true;
    }

    //! Die Übersicht in Bildpunkten: Rahmen aus den Hüllen der Blöcke
    //! (≤ 63 Vergleiche), genordet und eingepasst, jeder [_ovStride]-te
    //! Punkt (höchstens [OVERVIEW_SEGS] Stücke), das Ende immer; dazu die
    //! Trailköpfe. Einmal je Route, nicht je Bild.
    hidden function overviewPoints(w as Number) as Void {
        _ovX = [] as Array<Number>;
        _ovY = [] as Array<Number>;
        _ovHeads = [] as Array<Number>;
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
        _cy = w / 2 - 16;
        var xs = _route.xs;
        var ys = _route.ys;
        var n = xs.size();
        var stride = (n + OVERVIEW_SEGS - 1) / OVERVIEW_SEGS;
        if (stride < 1) { stride = 1; }
        _ovStride = stride;
        var ox = _ovX as Array<Number>;
        var oy = _ovY as Array<Number>;
        for (var i = 0; i < n - 1; i += stride) {
            ox.add(sx(xs[i], ys[i]));
            oy.add(sy(xs[i], ys[i]));
        }
        ox.add(sx(xs[n - 1], ys[n - 1]));
        oy.add(sy(xs[n - 1], ys[n - 1]));
        var heads = _ovHeads as Array<Number>;
        for (var k = 0; k < _route.secFrom.size(); k++) {
            var head = _route.secFrom[k];
            heads.add(sx(xs[head], ys[head]));
            heads.add(sy(xs[head], ys[head]));
        }
    }

    //! Linien zwischen den fertigen Punkten [lo, hi] der Übersicht.
    hidden function polyline(dc as Dc, ox as Array<Number>, oy as Array<Number>, lo as Number, hi as Number,
            joint as Number) as Void {
        for (var j = lo; j < hi; j++) {
            dc.drawLine(ox[j], oy[j], ox[j + 1], oy[j + 1]);
            if (joint > 0) { dc.fillCircle(ox[j + 1], oy[j + 1], joint); }
        }
    }

    //! Die Stücke i in [lo, hi) — nur aus Blöcken, deren Hülle das
    //! Quadrat ±reach um die Position schneidet, und Punkte, die näher als
    //! 4 px am zuletzt gezeichneten liegen, übersprungen (Watchdog,
    //! NavRoute; bei 6 m Punktabstand und 4 m/px sonst jeder zweite
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
    //! schwarz mit weißem Saum. Vom Handy (vor dem eigenen GPS) hohl, mit
    //! „Handy-GPS" darüber.
    hidden function drawMe(dc as Dc) as Void {
        var cx = _cx;
        var cy = _cy;
        dc.setColor(TbColors.GROUND, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx, cy - 18], [cx + 14, cy + 14], [cx, cy + 7], [cx - 14, cy + 14]]);
        dc.setColor(TbColors.TEXT, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx, cy - 13], [cx + 11, cy + 11], [cx, cy + 5], [cx - 11, cy + 11]]);
        if (!_phone) { return; }
        dc.setColor(TbColors.GROUND, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx, cy - 7], [cx + 6, cy + 6], [cx, cy + 3], [cx - 6, cy + 6]]);
        dc.setColor(TbColors.TEXT, TbColors.GROUND);
        dc.drawText(cx, cy - /*L:phone_gps_dy*/22, /*F:phone_gps*/Graphics.FONT_XTINY, str(Rez.Strings.PhoneGps),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Norden am Rand — die Karte dreht mit der Fahrt, so bleibt die
    //! Himmelsrichtung lesbar.
    hidden function drawNorth(dc as Dc, heading as Float, w as Number) as Void {
        var r = TbRing.MAP_R - 14;
        var x = (w / 2 - r * Math.sin(heading)).toNumber();
        var y = (w / 2 - r * Math.cos(heading)).toNumber();
        // Vor START steht rechts oben das Dreieck an der Taste (#558), bei
        // einer Frage „JA" — auf demselben Radius wie das „N". Läge es
        // darunter, weicht es nach innen aus.
        var dx = x - /*L:ask_yes_x*/198;
        var dy = y - /*L:ask_yes_y*/64;
        if ((_rec == RideLog.IDLE || asking()) && dx > -29 && dx < 29 && dy > -23 && dy < 23) {
            r -= 34;
            x = (w / 2 - r * Math.sin(heading)).toNumber();
            y = (w / 2 - r * Math.cos(heading)).toNumber();
        }
        if (y > FIELD_Y - 14) { return; }
        dc.setColor(TbColors.TEXT, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, 12);
        dc.setColor(TbColors.GROUND, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, /*F:north*/Graphics.FONT_XTINY, "N", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
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

    //! Die freie Fahrt (#484): helle Karte mit der eigenen Spur dünn in
    //! Moos (wie der gefahrene Teil einer Route), Norden, die Position;
    //! unten „Freie Fahrt" mit Strecke und bergauf. Vor dem ersten Fix
    //! „Warte auf GPS". Die Spur sind höchstens [RideLog.TRACK_N] Punkte,
    //! und `seg` zeichnet höchstens [FRAME_SEGS] Striche (Watchdog).
    hidden function drawFree(dc as Dc, w as Number) as Void {
        dc.setColor(TbColors.TEXT, TbColors.GROUND);
        dc.clear();
        _cx = w / 2;
        _cy = POS_Y;
        _mpp = ZOOM_MPP[_zoom];
        _reach = 135 * _mpp;
        _sin = Math.sin(_heading).toFloat();
        _cos = Math.cos(_heading).toFloat();
        if (_fixed) {
            var log = _log;
            var n = log.trackCount;
            var start = (log.trackHead - n + RideLog.TRACK_N) % RideLog.TRACK_N;
            dc.setColor(TbColors.ROUTE_EDGE, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(DONE_W);
            for (var i = 1; i < n; i++) {
                var a = (start + i - 1) % RideLog.TRACK_N;
                var b = (start + i) % RideLog.TRACK_N;
                seg(dc, log.trackX[a], log.trackY[a], log.trackX[b], log.trackY[b], 0);
            }
            if (n > 0) {
                var l = (start + n - 1) % RideLog.TRACK_N;
                seg(dc, log.trackX[l], log.trackY[l], _px, _py, 0);
            }
            dc.setPenWidth(1);
            drawNorth(dc, _heading, w);
            drawMe(dc);
        }
        field(dc, w, FIELD_Y, TbColors.FIELD);
        var cx = w / 2;
        dc.setColor(TbColors.MUTED, Graphics.COLOR_TRANSPARENT);
        if (!_fixed) {
            dc.drawText(cx, FIELD_Y + /*L:field_line1_dy*/2, /*F:field_note*/Graphics.FONT_XTINY, str(Rez.Strings.WaitGps), Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            // Die Fahrzeit in Zeile 1, unten nur Strecke und bergauf — die
            // untere Zeile hat am runden Rand keinen Platz für drei Werte;
            // „Speicher voll" geht vor und steht allein (#555).
            var note = str(_log.full ? Rez.Strings.StorageFull : Rez.Strings.FreeRide);
            if (!_log.full && _stats.movingS >= 60.0) { note = note + " · " + clock(_stats.movingS) + " h"; }
            dc.drawText(cx, FIELD_Y + /*L:field_line1_dy*/2, /*F:field_note*/Graphics.FONT_XTINY, note, Graphics.TEXT_JUSTIFY_CENTER);
            numberLine(dc, cx, FIELD_Y + /*L:field_line2_dy*/24, meters(_stats.distanceM), _stats.climbM);
        }
        dc.setColor(TbColors.FIELD, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(w / 2 - TbRing.MAP_R + 2);
        dc.drawCircle(w / 2, w / 2, (w / 2 + TbRing.MAP_R) / 2 + 1);
        dc.setPenWidth(1);
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
            shieldLine(dc, cx, FIELD_Y + /*L:field_line1_dy*/2, _route.secGrade[on], _route.secName[on]);
            numberLine(dc, cx, FIELD_Y + /*L:field_line2_dy*/24, meters(b - s.alongM), null);
            return;
        }
        var next = _route.nextSection(s.alongM);
        if (next >= 0) {
            var head = cum[_route.secFrom[next]];
            shieldLine(dc, cx, FIELD_Y + /*L:field_line1_dy*/2, _route.secGrade[next], _route.secName[next]);
            numberLine(dc, cx, FIELD_Y + /*L:field_line2_dy*/24, meters(head - s.alongM), _route.climbBetween(s.alongM, head));
            return;
        }
        dc.setColor(TbColors.MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, FIELD_Y + /*L:field_line1_dy*/2, /*F:field_note*/Graphics.FONT_XTINY, _toGoal, Graphics.TEXT_JUSTIFY_CENTER);
        numberLine(dc, cx, FIELD_Y + /*L:field_line2_dy*/24, meters(s.remainingM), _route.climbLeft(s.alongM));
    }

    //! Schild und Name, zusammen mittig. Ist der Name für die Breite des
    //! Kreises auf dieser Höhe zu lang, nimmt er die kleinere Schrift und
    //! erst dann ein „…" (Feldbefund 2026-11-05: „Schlosswald-Trai…" schnitt
    //! der runde Rand ab). Gemessen gegen die Karte (MAP_R), nicht die
    //! Anzeige: Darüber liegt der schwarze Rand mit dem Ring — gegen den
    //! Kreis der Anzeige lief der Name weiter darunter (#511, Abbild).
    //! Auf Höhe der Grundlinie (dort enden die Buchstaben); Schild und
    //! Abstand brauchen 20 px, 2 px Luft.
    hidden function shieldLine(dc as Dc, cx as Number, y as Number, g as Number, name as String) as Void {
        var font = /*F:field_name*/Graphics.FONT_TINY;
        var fh = dc.getFontHeight(font);
        var room = chordAround(cx, TbRing.MAP_R, y + Graphics.getFontAscent(font)) - 22;
        var tw = dc.getTextWidthInPixels(name, font);
        if (tw > room) {
            font = /*F:field_name_small*/Graphics.FONT_XTINY;
            fh = dc.getFontHeight(font);
            room = chordAround(cx, TbRing.MAP_R, y + Graphics.getFontAscent(font)) - 22;
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

    //! Breite des Kreises mit Radius [r] um die Mitte der Anzeige ([c], [c])
    //! auf Höhe [y].
    hidden function chordAround(c as Number, r as Number, y as Number) as Number {
        var d = y > c ? y - c : c - y;
        if (d >= r) { return 0; }
        return (2 * Math.sqrt(r * r - d * d)).toNumber();
    }

    //! „1,2 km ▲80": der Weg weiß, der Anstieg in Lime mit gezeichnetem
    //! Pfeil (die Systemschrift hat keinen).
    //! Unten wird der Kreis schmal: Passt die Zeile nicht in die Breite
    //! innerhalb des Rings auf Höhe ihrer Unterkante, eine kleinere Schrift
    //! („5,6 km ▲149" lief am Gerät rechts hinaus, 2026-11-05).
    hidden function numberLine(dc as Dc, cx as Number, y as Number, dist as String, climb as Float?) as Void {
        var up = climb != null && climb >= 1 ? (climb as Float).toNumber().toString() : null;
        var fonts = [/*F:number_line*/Graphics.FONT_SMALL, /*F:number_line_2*/Graphics.FONT_TINY, /*F:number_line_3*/Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>;
        var font = Graphics.FONT_XTINY;
        var dw = 0;
        var uw = 0;
        for (var i = 0; i < fonts.size(); i++) {
            font = fonts[i];
            dw = dc.getTextWidthInPixels(dist, font);
            uw = up == null ? 0 : dc.getTextWidthInPixels(up, font) + 22;
            var bottom = y + dc.getFontHeight(font) - 4;
            if (dw + uw <= chordAround(cx, TbRing.MAP_R - 4, bottom)) { break; }
        }
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
        dc.drawText(w / 2, FIELD_Y + /*L:field_line1_dy*/2, /*F:off_title*/Graphics.FONT_TINY, _offRoute, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, FIELD_Y + /*L:field_line2_dy*/24, /*F:off_value*/Graphics.FONT_SMALL, meters(s.offM), Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Angekommen: die Runde in Zahlen — Strecke, Fahrzeit, bergauf und
    //! die befahrenen Trails als Schilder (Betreiber 2026-11-04: „Ja").
    hidden function drawArrived(dc as Dc, w as Number) as Void {
        var cx = w / 2;
        dc.setColor(TbColors.ROUTE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, /*L:arrived_title_y*/30, /*F:arrived_title*/Graphics.FONT_TINY, str(Rez.Strings.Arrived), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(TbColors.TEXT_ON_FIELD, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, /*L:arrived_km_y*/60, /*F:arrived_km*/Graphics.FONT_LARGE, km(_stats.distanceM) + " km", Graphics.TEXT_JUSTIFY_CENTER);
        symText(dc, cx - /*L:arrived_time_dx*/40, /*L:arrived_row_y*/112, /*F:arrived_time*/Graphics.FONT_SMALL, /*S:stopwatch*/0, clock(_stats.movingS), TbColors.MUTED, TbColors.TEXT_ON_FIELD);
        climbText(dc, cx + /*L:arrived_climb_dx*/40, /*L:arrived_row_y*/112, _stats.climbM, TbColors.TEXT_ON_FIELD);
        // Die Schilder zählen die Trails selbst; die Zeile „8 Trails" ist
        // für die Bestwerte gewichen (#555).
        var n = _stats.riddenCount();
        var x = cx - (n - 1) * 10;
        for (var k = 0; k < _stats.ridden.size(); k++) {
            if (!_stats.ridden[k]) { continue; }
            drawShield(dc, x, /*L:arrived_shields_y*/150, _route.secGrade[k], 5, false, TbColors.FIELD);
            x += 20;
        }
        if (_stats.hasBests()) {
            // Flugzeug und Wheelie in einer Zeile, weiß (#558).
            var font = /*F:arrived_bests*/Graphics.FONT_SMALL;
            var a = seconds(_stats.best("ja"));
            var b = _stats.best("wl") + " m";
            var aw = 16 + 4 + dc.getTextWidthInPixels(a, font);
            var bw = 22 + 4 + dc.getTextWidthInPixels(b, font);
            var x0 = cx - (aw + 10 + bw) / 2;
            symText(dc, x0 + aw / 2, /*L:arrived_bests_y*/168, font, /*S:plane*/10, a, TbColors.MUTED, TbColors.TEXT_ON_FIELD);
            symText(dc, x0 + aw + 10 + bw / 2, /*L:arrived_bests_y*/168, font, /*S:wheelie*/11, b, TbColors.MUTED, TbColors.TEXT_ON_FIELD);
        }
    }

    //! „Sprünge": die Bestwerte der Erkennung vom Handy (#36, Konzept 9.2)
    //! — längster Wheelie groß, darunter links der Sprung (Flugzeit,
    //! Anzahl), rechts der Wheelie (Winkel, Anzahl). Zeichen statt Wörter
    //! (#558). Die Uhr misst nichts davon (Entscheidung 1).
    hidden function drawBests(dc as Dc, w as Number) as Void {
        big(dc, w, /*S:wheelie*/11, "m", _stats.best("wl").toString());
        var cx = w / 2;
        symCell(dc, cx - COL_X, /*L:cell_row1_y*/106, /*S:plane*/10, false, tenths(_stats.best("ja")), "s", TbColors.TEXT_ON_FIELD);
        symCell(dc, cx + COL_X, /*L:cell_row1_y*/106, /*S:wheelie*/11, false, _stats.best("wa") + "°", null, TbColors.TEXT_ON_FIELD);
        count(dc, cx - COL_X, _stats.best("jn"));
        count(dc, cx + COL_X, _stats.best("wn"));
    }

    //! „7 ×", klein und grau unter dem Wert.
    hidden function count(dc as Dc, cx as Number, n as Number) as Void {
        dc.setColor(TbColors.MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, /*L:cell_row2_y*/150, /*F:cell_count*/Graphics.FONT_SMALL, n + " ×", Graphics.TEXT_JUSTIFY_CENTER);
    }

    // --- Zahlenseiten ------------------------------------------------------

    //! „Fahrt": Tempo groß, darunter Fahrzeit, Strecke, bergauf und der
    //! Puls — dezent in Grau (Betreiber 2026-11-04: „Ja, aber dezent").
    //! Zeichen vor großen Werten, die Einheit klein dahinter (#558).
    hidden function drawRide(dc as Dc, w as Number) as Void {
        var speed = _speed;
        var cx = w / 2;
        bigText(dc, w, str(Rez.Strings.Speed), speed == null ? "--" : (speed * 3.6).format("%.0f"));
        var hr = _stats.heartRate;
        symCell(dc, cx - COL_X, /*L:cell_row1_y*/106, /*S:stopwatch*/0, false, clock(_stats.movingS), null, TbColors.TEXT_ON_FIELD);
        symCell(dc, cx + COL_X, /*L:cell_row1_y*/106, /*S:distance*/2, false, km(_stats.distanceM), "km", TbColors.TEXT_ON_FIELD);
        climbCell(dc, cx - COL_X, /*L:cell_row2_y*/150, -1, _stats.climbM, "m");
        symCell(dc, cx + COL_X, /*L:cell_row2_y*/150, /*S:heart*/3, false, hr == null ? "--" : hr.toString(), null, TbColors.MUTED);
        // „Speicher voll" (#484) sagt die Karte in Zeile 1 — hier unten
        // passt es nicht in den runden Rand (#555).
    }

    //! „Berg": Steigung groß (Barometer über die letzten 30 m), Höhe, was
    //! bis zum nächsten Trailkopf und bis zum Ziel noch hoch geht, Uhrzeit.
    hidden function drawMountain(dc as Dc, w as Number) as Void {
        var g = _stats.grade();
        var cx = w / 2;
        big(dc, w, /*S:angle*/7, "%", g == null ? "--" : g.toString());
        var alt = _stats.altitude;
        var altText = alt == null ? "--" : alt.toNumber().toString();
        // Ab vier Stellen ohne „m": sonst reicht der Wert über den Mittelstrich.
        symCell(dc, cx - COL_X, /*L:cell_row1_y*/106, /*S:peaks*/4, false, altText, altText.length() >= 4 ? null : "m", TbColors.TEXT_ON_FIELD);
        var s = _state;
        var toTrail = null;
        var toGoal = null;
        if (s != null && _route.isReady()) {
            var next = _route.nextSection(s.alongM);
            if (next >= 0) { toTrail = _route.climbBetween(s.alongM, _route.cum[_route.secFrom[next]]); }
            toGoal = _route.climbLeft(s.alongM);
        }
        climbCell(dc, cx + COL_X, /*L:cell_row1_y*/106, /*S:signpost*/5, toTrail, null);
        climbCell(dc, cx - COL_X, /*L:cell_row2_y*/150, /*S:flag*/6, toGoal, null);
        var t = System.getClockTime();
        symCell(dc, cx + COL_X, /*L:cell_row2_y*/150, /*S:clock*/1, false, t.hour + ":" + t.min.format("%02d"), null, TbColors.TEXT_ON_FIELD);
        drawMeasure(dc, w);
    }

    //! Akku und Speicher für die Messungen (Konzept-Garmin 8) — nur im
    //! Vorführmodus; auf der Uhr stand die Zeile mitten in der Seite.
    (:demo)
    hidden function drawMeasure(dc as Dc, w as Number) as Void {
        var stats = System.getSystemStats();
        dc.setColor(TbColors.MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, /*L:page_note_y*/198, /*F:page_note*/Graphics.FONT_XTINY,
            stats.battery.format("%.0f") + " % · " + (stats.usedMemory / 1024) + " KB", Graphics.TEXT_JUSTIFY_CENTER);
    }

    (:nodemo)
    hidden function drawMeasure(dc as Dc, w as Number) as Void {}

    //! Oben die Einheit klein, darunter die Zahl groß, ein Strich — mit
    //! einem Zeichen vor der Einheit, wenn [sym] ≥ 0 (#558).
    hidden function big(dc as Dc, w as Number, sym as Number, unit as String, value as String) as Void {
        symText(dc, w / 2, /*L:big_unit_y*/20, /*F:big_unit*/Graphics.FONT_XTINY, sym, unit, TbColors.MUTED, TbColors.MUTED);
        bigValue(dc, w, value);
    }

    //! Wie [big], die Einheit als Wort („KM/H" bleibt ein Wort).
    hidden function bigText(dc as Dc, w as Number, unit as String, value as String) as Void {
        dc.setColor(TbColors.MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, /*L:big_unit_y*/20, /*F:big_unit*/Graphics.FONT_XTINY, unit, Graphics.TEXT_JUSTIFY_CENTER);
        bigValue(dc, w, value);
    }

    hidden function bigValue(dc as Dc, w as Number, value as String) as Void {
        var cx = w / 2;
        dc.setColor(TbColors.TEXT_ON_FIELD, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, /*L:big_value_y*/40, /*F:big_value*/Graphics.FONT_NUMBER_MEDIUM, value, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(TbColors.MUTED_DARK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(/*L:big_rule_x*/36, /*L:big_rule_y*/100, w - /*L:big_rule_x*/36, /*L:big_rule_y*/100);
        dc.drawLine(cx, /*L:col_rule_top*/108, cx, /*L:col_rule_bottom*/196);
        dc.setPenWidth(1);
    }

    //! Eine Zeile aus Zeichen [sym] (graue Teile in [symColor]) und [text],
    //! mittig um [cx], Oberkante der Schrift bei [y] (#558). [sym] < 0: nur
    //! der Text.
    hidden function symText(dc as Dc, cx as Number, y as Number, font as Graphics.FontType, sym as Number,
                            text as String, symColor as Number, color as Number) as Void {
        var tw = dc.getTextWidthInPixels(text, font);
        if (sym < 0) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        var sw = TbSym.width(sym);
        var x = cx - (sw + 4 + tw) / 2;
        TbSym.draw(dc, sym, x, y + (dc.getFontHeight(font) - 16) / 2, symColor);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + sw + 4, y, font, text, Graphics.TEXT_JUSTIFY_LEFT);
    }

    //! Eine Zelle der Zahlenseiten (#558): Zeichen, Wert groß, Einheit klein
    //! und grau auf derselben Grundlinie, eine Zeile, mittig um [cx].
    //! [arrow]: der Anstiegspfeil in Lime zwischen Zeichen und Wert.
    hidden function symCell(dc as Dc, cx as Number, y as Number, sym as Number, arrow as Boolean,
                            value as String, unit as String?, color as Number) as Void {
        var vf = /*F:cell_value*/Graphics.FONT_MEDIUM;
        var uf = /*F:cell_unit*/Graphics.FONT_XTINY;
        var sw = sym < 0 ? 0 : TbSym.width(sym) + 2;
        var aw = arrow ? 13 : 0;
        var vw = dc.getTextWidthInPixels(value, vf);
        var uw = unit == null ? 0 : 3 + dc.getTextWidthInPixels(unit, uf);
        var x = cx - (sw + aw + vw + uw) / 2;
        if (sym >= 0) {
            TbSym.draw(dc, sym, x, y + (dc.getFontHeight(vf) - 16) / 2, TbColors.MUTED);
        }
        x += sw;
        if (arrow) {
            var my = y + dc.getFontHeight(vf) / 2;
            dc.setColor(TbColors.ROUTE, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[x + 5, my - 5], [x + 10, my + 4], [x, my + 4]]);
            x += aw;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, vf, value, Graphics.TEXT_JUSTIFY_LEFT);
        if (unit != null) {
            dc.setColor(TbColors.MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + vw + 3, y + Graphics.getFontAscent(vf) - Graphics.getFontAscent(uf), uf, unit, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    //! Eine Zelle „bergauf" (#558): [sym] davor (-1: keins), der Pfeil, die
    //! Meter; ohne Wert „--". Hinter dem Pfeil entfällt das „m" meist (wie in
    //! der Zahlenzeile der Karte), [unit] sagt es.
    hidden function climbCell(dc as Dc, cx as Number, y as Number, sym as Number, m as Float?, unit as String?) as Void {
        if (m == null) {
            symCell(dc, cx, y, sym, false, "--", null, TbColors.TEXT_ON_FIELD);
            return;
        }
        symCell(dc, cx, y, sym, true, (m as Float).toNumber().toString(), unit, TbColors.TEXT_ON_FIELD);
    }

    //! „▲120 m", mittig um [cx]: der Pfeil gezeichnet in Lime (die
    //! Systemschrift hat keinen), die Zahl in [color]; ohne Wert „--".
    hidden function climbText(dc as Dc, cx as Number, y as Number, m as Float?, color as Number) as Void {
        var font = /*F:climb_value*/Graphics.FONT_SMALL;
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
        return tenths(ms) + " s";
    }

    //! „0,6" ohne Einheit.
    hidden function tenths(ms as Number) as String {
        var t = (ms + 50) / 100;
        return (t / 10) + _sep + (t % 10);
    }

    //! Fahrzeit „1:12" (Stunden:Minuten).
    hidden function clock(secs as Float) as String {
        var m = secs.toNumber() / 60;
        return (m / 60) + ":" + (m % 60).format("%02d");
    }

    //! Ab 10 km ohne Nachkomma (#555: „123,5 km ▲2345" passt am runden
    //! Rand nicht in die untere Zeile).
    hidden function meters(m as Float) as String {
        if (m < 1000) { return (m + 0.5).toNumber() + " m"; }
        return m < 10000 ? (km(m) + " km") : ((m / 1000.0 + 0.5).toNumber() + " km");
    }

    //! Der Lader: schwarz, das Logo als Spur in Grau, darüber im Takt in
    //! Lime, darunter [text]. Die Punkte kommen aus `tool/brand_icons.py`
    //! (je zwei Zahlen: x/y und Radius/Weg in Zehntel, gepackt wie die
    //! Route) — volle Kreise entlang der Mittellinie statt eines Polygons.
    //! [full]: das ganze Zeichen in Lime, ohne Takt (Navigation beendet,
    //! keine Route). [textY]: Oberkante des Texts.
    hidden function drawLoader(dc as Dc, w as Number, text as String, full as Boolean, textY as Number) as Void {
        dc.setColor(TbColors.TEXT_ON_FIELD, TbColors.FIELD);
        dc.clear();
        var dots = _logo;
        if (dots == null) {
            var d = WatchUi.loadResource(Rez.JsonData.Logo) as Dictionary;
            dots = d["d"] as Array<Number>;
            _logo = dots;
            _logoT = d["t"] as Number;
        }
        // Takt wie `loaderAt` in der App: einzeichnen (weich ein und aus),
        // stehen, zurück.
        var ms = System.getTimer() % LOADER_PERIOD_MS;
        var x = ms >= LOADER_DRAW_MS ? 1.0 : ms.toFloat() / LOADER_DRAW_MS;
        var to = full ? -1 : (_logoT * x * x * (3 - 2 * x)).toNumber();
        var cx = w / 2;
        if (!full) {
            dc.setColor(TbColors.MUTED_DARK, Graphics.COLOR_TRANSPARENT);
            logoDots(dc, dots, cx, -1);
        }
        dc.setColor(TbColors.ROUTE, Graphics.COLOR_TRANSPARENT);
        logoDots(dc, dots, cx, to);
        dc.setColor(TbColors.MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, textY, /*F:loader_text*/Graphics.FONT_XTINY, text, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Die Punkte bis zum Weg [to] (-1: alle).
    hidden function logoDots(dc as Dc, dots as Array<Number>, cx as Number, to as Number) as Void {
        for (var i = 0; i + 1 < dots.size(); i += 2) {
            var rc = dots[i + 1];
            if (to >= 0 && PhoneRoute.unpackLo(rc) > to) { return; }
            var xy = dots[i];
            dc.fillCircle(cx + PhoneRoute.unpackHi(xy) / 10, LOGO_Y + PhoneRoute.unpackLo(xy) / 10,
                PhoneRoute.unpackHi(rc) / 10);
        }
    }

    hidden function str(id as ResourceId) as String {
        return WatchUi.loadResource(id) as String;
    }
}
