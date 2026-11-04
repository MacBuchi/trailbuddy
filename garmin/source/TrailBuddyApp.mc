import Toybox.Application;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! TrailBuddy auf der Uhr (docs/konzept-garmin.md). G1: eine feste
//! Testroute aus der Ressource, eigenes GPS, keine Garmin-Aktivität
//! (kein ActivityRecording, Konzept 4), kein Netz.
class TrailBuddyApp extends Application.AppBase {
    hidden var _route as NavRoute;
    hidden var _tracker as NavTracker;
    hidden var _view as NavView;
    hidden var _loader as Timer.Timer?;
    //! So viele Punkte je Häppchen: bleibt weit unter dem Watchdog
    //! (120 000 Schritte je Ereignis, NavRoute).
    static const DECODE_BUDGET = 300;

    function initialize() {
        AppBase.initialize();
        _route = new NavRoute(WatchUi.loadResource(Rez.JsonData.Route) as Dictionary);
        _tracker = new NavTracker(_route);
        _view = new NavView(_route);
    }

    function onStart(state as Dictionary?) as Void {
        var t = new Timer.Timer();
        _loader = t;
        t.start(method(:loadStep), 50, true);
    }

    //! Ein Häppchen der Route; ist sie fertig, beginnt die Navigation.
    function loadStep() as Void {
        if (!_route.decodeStep(DECODE_BUDGET)) {
            WatchUi.requestUpdate();
            return;
        }
        (_loader as Timer.Timer).stop();
        _loader = null;
        WatchUi.requestUpdate();
        if (self has :startDemo) {
            startDemo();
            return;
        }
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
    }

    function onStop(state as Dictionary?) as Void {
        var t = _loader;
        if (t != null) { t.stop(); }
        if (self has :startDemo) { return; }
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [_view, new NavDelegate(_view)];
    }

    function onPosition(info as Position.Info) as Void {
        var loc = info.position;
        if (loc == null || info.accuracy < Position.QUALITY_USABLE) {
            return;
        }
        var deg = loc.toDegrees();
        var lat = deg[0].toDouble();
        var lon = deg[1].toDouble();
        if (_route.relative) {
            _route.anchor(lat, lon);
        }
        var p = _route.toLocal(lat, lon);
        var compass = null;
        var sensor = Sensor.getInfo();
        if (sensor has :heading && sensor.heading != null) {
            compass = sensor.heading;
        }
        var s = _tracker.update(p[0], p[1], info.heading, info.speed, compass);
        if (s.leftRoute) {
            vibrateOnce();
        }
        _view.setState(s, info.speed, info.altitude);
    }

    (:demo) hidden var _demoTimer as Timer.Timer?;
    (:demo) hidden var _demoScene as Number = 0;

    (:demo)
    function startDemo() as Void {
        _demoTimer = new Timer.Timer();
        (_demoTimer as Timer.Timer).start(method(:demoTick), 4000, true);
        demoTick();
    }

    (:demo)
    function demoTick() as Void {
        var scenes = DemoScenes.scenes(_route);
        var sc = scenes[_demoScene % scenes.size()];
        _demoScene++;
        if (_demoScene % scenes.size() == 1) {
            _tracker = new NavTracker(_route); // „angekommen" bleibt sonst stehen
        }
        var along = sc[0];
        var h = _route.bearingAt(along);
        var p = _route.pointAt(along);
        // Quer nach rechts der Fahrtrichtung.
        var x = p[0] + sc[1] * Math.cos(h).toFloat();
        var y = p[1] - sc[1] * Math.sin(h).toFloat();
        var s = _tracker.update(x - 3 * Math.sin(h).toFloat(), y - 3 * Math.cos(h).toFloat(), h, 6.0, null);
        s = _tracker.update(x, y, h, 6.0, null);
        _view.setState(s, 6.0, 812.0);
        // Für die Messung 8.1: Speicher nach jedem Bild in die Konsole.
        var st = System.getSystemStats();
        System.println("demo " + _route.size() + " pts scene " + (_demoScene - 1) % scenes.size()
            + " used " + st.usedMemory + " total " + st.totalMemory);
    }

    //! Einmal beim Abkommen (Entscheidung 3) — kein Ton, nichts vor
    //! Abzweigen.
    hidden function vibrateOnce() as Void {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(100, 700)]);
        }
    }
}

//! Der Vorführmodus (`tool/garmin_build.sh --demo`, nur Simulator): statt
//! GPS spielt er reihum die Zustände der Ansicht durch — Anfahrt, auf dem
//! Trail, abseits, angekommen —, je zwei Fixe, alle 4 s ein Bild. Im
//! normalen Build schließt monkey.jungle `(:demo)` aus.
(:demo)
class DemoScenes {
    //! [Meter ab Start, Abstand quer zur Linie]
    static function scenes(r as NavRoute) as Array<[Float, Float]> {
        var out = [] as Array<[Float, Float]>;
        var c = r.cum;
        if (r.secFrom.size() > 1) {
            out.add([c[r.secFrom[0]] - 250.0, 0.0]);
            var mid = (c[r.secFrom[1]] + c[r.secTo[1]]) / 2;
            out.add([mid, 0.0]);
            out.add([(c[r.secTo[1]] + c[r.secFrom[r.secFrom.size() > 2 ? 2 : 1]]) / 2, 55.0]);
        } else {
            out.add([r.lengthM * 0.3, 0.0]);
            out.add([r.lengthM * 0.5, 55.0]);
        }
        out.add([r.lengthM - 5.0, 0.0]);
        return out;
    }
}

//! hoch/runter zoomt, START schaltet die Seite, ZURÜCK beendet nach
//! Rückfrage (Konzept-Garmin 1).
class NavDelegate extends WatchUi.BehaviorDelegate {
    hidden var _view as NavView;

    function initialize(view as NavView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onPreviousPage() as Boolean {
        _view.zoomIn();
        return true;
    }

    function onNextPage() as Boolean {
        _view.zoomOut();
        return true;
    }

    function onSelect() as Boolean {
        _view.togglePage();
        return true;
    }

    function onBack() as Boolean {
        WatchUi.pushView(
            new WatchUi.Confirmation(WatchUi.loadResource(Rez.Strings.Quit) as String),
            new QuitDelegate(),
            WatchUi.SLIDE_IMMEDIATE);
        return true;
    }
}

class QuitDelegate extends WatchUi.ConfirmationDelegate {
    function initialize() {
        ConfirmationDelegate.initialize();
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            System.exit();
        }
        return true;
    }
}
