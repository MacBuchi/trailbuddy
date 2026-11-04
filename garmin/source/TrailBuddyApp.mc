import Toybox.Application;
import Toybox.Attention;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! TrailBuddy auf der Uhr (docs/konzept-garmin.md). Die Route kommt vom
//! Handy (G2, `PhoneRoute`) und liegt danach im Speicher der Uhr; ohne
//! eine gespeicherte die erfundene Testroute aus der Ressource (G1).
//! Eigenes GPS, keine Garmin-Aktivität (kein ActivityRecording, Konzept
//! 4), kein Netz — an das Handy nur „hallo" (`hi`, mit der Kennung der
//! gespeicherten Route) und „gespeichert" (`ok`).
class TrailBuddyApp extends Application.AppBase {
    hidden var _route as NavRoute;
    hidden var _tracker as NavTracker;
    hidden var _view as NavView;
    hidden var _stats as RideStats;
    hidden var _loader as Timer.Timer?;
    //! Die Bestwerte vom Handy (#36), bleiben über einen Routenwechsel.
    hidden var _bests as Dictionary? = null;
    //! Eine neue Route ist vollständig im Speicher und wartet auf den
    //! Wechsel (der läuft im nächsten Ereignis, nicht im Rückruf).
    hidden var _pendingId as String? = null;
    hidden var _swap as Timer.Timer?;
    //! So viele Punkte je Häppchen: bleibt weit unter dem Watchdog
    //! (120 000 Schritte je Ereignis, NavRoute).
    static const DECODE_BUDGET = 300;

    function initialize() {
        AppBase.initialize();
        _route = new NavRoute(startRoute());
        _tracker = new NavTracker(_route);
        _stats = new RideStats(_route.secFrom.size());
        _view = new NavView(_route, _stats);
    }

    //! Die gespeicherte Route vom Handy, sonst die Testroute. Brach das
    //! Laden der gespeicherten beim letzten Mal ab (Speicher, Watchdog),
    //! steht „loading" noch: Dann ist sie weg, sonst stürzte die App bei
    //! jedem Start wieder ab.
    hidden function startRoute() as Dictionary {
        if (Storage.getValue("loading") == true) {
            PhoneRoute.drop();
            Storage.deleteValue("loading");
        }
        var d = PhoneRoute.load();
        if (d != null) {
            Storage.setValue("loading", true);
            return d;
        }
        return WatchUi.loadResource(Rez.JsonData.Route) as Dictionary;
    }

    function onStart(state as Dictionary?) as Void {
        startLoader();
        // Der Puls vom Handgelenk für die Seite „Fahrt" (bleibt auf der Uhr).
        if (Sensor has :setEnabledSensors) {
            Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
        }
        if (Communications has :registerForPhoneAppMessages) {
            Communications.registerForPhoneAppMessages(method(:onPhone));
            sayHello();
        }
    }

    //! „Hallo" an das Handy, beim Start und auf seine Frage `q`: die
    //! Kennung der gespeicherten Route (Betreiber 2026-11-04). Weicht sie
    //! von der Navigation auf dem Handy ab, schickt es die aktuelle; folgt
    //! die Uhr keiner Navigation, bleibt die Nachricht ohne Antwort.
    hidden function sayHello() as Void {
        var msg = {"t" => "hi", "v" => PhoneRoute.PROTOCOL} as Dictionary;
        var id = PhoneRoute.currentId();
        if (id != null) { msg["id"] = id; }
        Communications.transmit(msg, null, new PhoneAck());
    }

    hidden function startLoader() as Void {
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
        Storage.deleteValue("loading");
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

    //! Eine Nachricht vom Handy: ein Stück Route oder die Bestwerte.
    function onPhone(msg as Communications.PhoneAppMessage) as Void {
        var d = msg.data;
        if (!(d instanceof Dictionary)) { return; }
        var t = d["t"];
        if ("q".equals(t)) {
            sayHello();
            return;
        }
        if ("b".equals(t)) {
            _bests = d;
            _stats.bests = d;
            WatchUi.requestUpdate();
            return;
        }
        if (!"r".equals(t)) { return; }
        var id = PhoneRoute.take(d);
        if (id == null) { return; }
        // Die Antwort auf eine vollständige Route (Konzept 2): gespeichert.
        Communications.transmit({"t" => "ok", "id" => id}, null, new PhoneAck());
        if (id.equals(_route.id) && _route.isReady()) { return; }
        _pendingId = id;
        var timer = new Timer.Timer();
        _swap = timer;
        timer.start(method(:swapRoute), 50, false);
    }

    //! Die neue Route: GPS aus, die alte loslassen, die neue laden. Die
    //! alte geht zuerst — beide zugleich passten nicht in den Speicher
    //! (Messung 8.1).
    function swapRoute() as Void {
        _swap = null;
        if (_pendingId == null) { return; }
        _pendingId = null;
        var t = _loader;
        if (t != null) { t.stop(); _loader = null; }
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        var tiny = {"id" => "-", "pts" => [0, 0, 0, 1]} as Dictionary;
        _route = NavRoute.decoded(tiny);
        _tracker = new NavTracker(_route);
        _view = new NavView(_route, _stats);
        WatchUi.switchToView(_view, new NavDelegate(_view), WatchUi.SLIDE_IMMEDIATE);
        var d = PhoneRoute.load();
        if (d == null) { return; }
        Storage.setValue("loading", true);
        _route = new NavRoute(d);
        d = null;
        _tracker = new NavTracker(_route);
        _stats = new RideStats(_route.secFrom.size());
        _stats.bests = _bests;
        _view = new NavView(_route, _stats);
        WatchUi.switchToView(_view, new NavDelegate(_view), WatchUi.SLIDE_IMMEDIATE);
        startLoader();
    }

    function onPosition(info as Position.Info) as Void {
        if (!_route.isReady()) { return; }
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
        // Höhe vom Barometer, sonst vom GPS.
        var alt = sensor has :altitude && sensor.altitude != null ? sensor.altitude : info.altitude;
        var hr = sensor has :heartRate ? sensor.heartRate : null;
        _stats.update(p[0], p[1], System.getTimer(), info.speed, alt, hr,
            s.offRoute ? -1 : _route.sectionAt(s.alongM));
        _view.setState(s, info.speed);
    }

    (:demo) hidden var _demoTimer as Timer.Timer?;
    (:demo) hidden var _demoScene as Number = 0;
    (:demo) hidden var _demoMs as Number = 0;

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
        // Vor jeder Szene auf der Linie ein Fix mitten im Trail davor, damit
        // die Zusammenfassung befahrene Trails hat.
        if (_route.secFrom.size() > 0) {
            var k = _route.nextSection(sc[0]);
            k = k < 0 ? _route.secFrom.size() - 1 : (k > 0 ? k - 1 : 0);
            var c = _route.cum;
            var q = _route.pointAt((c[_route.secFrom[k]] + c[_route.secTo[k]]) / 2);
            _stats.update(q[0], q[1], _demoMs, 0.0, null, null, k);
        }
        var along = sc[0];
        var h = _route.bearingAt(along);
        var p = _route.pointAt(along);
        // Quer nach rechts der Fahrtrichtung.
        var x = p[0] + sc[1] * Math.cos(h).toFloat();
        var y = p[1] - sc[1] * Math.sin(h).toFloat();
        var s = _tracker.update(x - 3 * Math.sin(h).toFloat(), y - 3 * Math.cos(h).toFloat(), h, 6.0, null);
        s = _tracker.update(x, y, h, 6.0, null);
        // Zahlen für die Seiten: erfundene Höhe (steigt stetig) und Puls.
        _demoMs += 4000;
        var demoAlt = 700.0 + _demoMs / 1000.0 * 0.5;
        _stats.update(x, y, _demoMs, 6.0, demoAlt, 128 + _demoScene % 20,
            s.offRoute ? -1 : _route.sectionAt(s.alongM));
        // Strecke und Fahrzeit wie bis zu dieser Stelle gefahren (die Szenen
        // springen, aus den Fixen käme nichts zusammen).
        _stats.distanceM = sc[0];
        _stats.movingS = sc[0] / 5.0;
        _view.setState(s, 6.0);
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

//! START blättert (Karte → Fahrt → Berg), hoch/runter zoomt auf der Karte
//! und blättert auf den Zahlenseiten, ZURÜCK beendet nach Rückfrage
//! (Konzept-Garmin 1).
class NavDelegate extends WatchUi.BehaviorDelegate {
    hidden var _view as NavView;

    function initialize(view as NavView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onPreviousPage() as Boolean {
        _view.up();
        return true;
    }

    function onNextPage() as Boolean {
        _view.down();
        return true;
    }

    function onSelect() as Boolean {
        _view.nextPage();
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

//! Die Antwort an das Handy: Ob sie ankommt, ändert nichts — die Route
//! liegt ohnehin auf der Uhr; ein verlorenes „hallo" holt die nächste
//! Frage `q` nach.
class PhoneAck extends Communications.ConnectionListener {
    function initialize() {
        ConnectionListener.initialize();
    }

    function onComplete() as Void {}

    function onError() as Void {}
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
