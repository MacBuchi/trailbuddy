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
//! gespeicherten Route), „gespeichert" (`ok`) und „ging nicht" (`x`).
//! Eine Route, die die App abstürzen ließ, kommt nicht zweimal hinein
//! ([CrashGuard]).
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
    //! Läuft eine Minute nach dem Laden ohne Absturz: [CrashGuard.calm].
    hidden var _calm as Timer.Timer?;
    //! Die Testroute ließ sich nicht dekodieren (dann nicht immer wieder).
    hidden var _testFailed as Boolean = false;
    //! So viele Punkte je Häppchen: bleibt weit unter dem Watchdog
    //! (120 000 Schritte je Ereignis, NavRoute).
    static const DECODE_BUDGET = 300;

    function initialize() {
        AppBase.initialize();
        var r = startRoute();
        _route = r;
        _tracker = new NavTracker(r);
        _stats = new RideStats(r.secFrom.size());
        _view = new NavView(r, _stats);
    }

    //! Die gespeicherte Route vom Handy, sonst die Testroute. Erst der
    //! Schutz vor Abstürzen ([CrashGuard.atStart] verwirft eine Route, mit
    //! der die App zweimal nicht sauber endete); brach das Laden der
    //! gespeicherten beim letzten Mal ab (Speicher, Watchdog), steht
    //! „loading" noch: Dann ist sie sofort weg.
    hidden function startRoute() as NavRoute {
        CrashGuard.atStart();
        if (Storage.getValue("loading") == true) {
            PhoneRoute.drop();
            Storage.deleteValue("loading");
        }
        var r = PhoneRoute.route();
        if (r != null) {
            PhoneRoute.store("loading", true);
            CrashGuard.risk(r.id);
            return r;
        }
        return testRoute();
    }

    hidden function testRoute() as NavRoute {
        return NavRoute.fromDict(WatchUi.loadResource(Rez.JsonData.Route) as Dictionary);
    }

    //! Route, Verfolgung, Zahlen und Ansicht für [r]; die Bestwerte bleiben.
    hidden function setRoute(r as NavRoute) as Void {
        _route = r;
        _tracker = new NavTracker(r);
        _stats = new RideStats(r.secFrom.size());
        _stats.bests = _bests;
        _view = new NavView(r, _stats);
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
        var bad = CrashGuard.bad();
        if (bad != null) { msg["bad"] = bad; }
        toPhone(msg);
    }

    //! An das Handy — nur, wenn eins verbunden ist: Sonst füllte jede
    //! Nachricht die Warteschlange („transmit queue full"), und der
    //! Simulator meldete bei jedem Start „There is no data connection".
    //! Ein verlorenes „hallo" holt das Handy beim Verbinden mit `q` nach.
    hidden function toPhone(msg as Dictionary) as Void {
        if (!System.getDeviceSettings().phoneConnected) { return; }
        Communications.transmit(msg, null, new PhoneAck());
    }

    hidden function startLoader() as Void {
        var t = new Timer.Timer();
        _loader = t;
        t.start(method(:loadStep), 50, true);
    }

    //! Ein Häppchen der Route; ist sie fertig, beginnt die Navigation.
    //! Passte sie nicht ([NavRoute.failed]), ist sie weg — das Handy hört
    //! davon, und die Testroute lädt.
    function loadStep() as Void {
        if (!_route.decodeStep(DECODE_BUDGET)) {
            WatchUi.requestUpdate();
            return;
        }
        (_loader as Timer.Timer).stop();
        _loader = null;
        Storage.deleteValue("loading");
        if (_route.failed) {
            var id = _route.id;
            // Die Testroute selbst passte nicht: nicht noch einmal laden —
            // das war eine Schleife alle 50 ms („Lade Route 0 %", fēnix 5,
            // 2026-11-05). Die Ansicht sagt es.
            if (!id.equals(PhoneRoute.currentId()) && _testFailed) {
                WatchUi.requestUpdate();
                return;
            }
            if (!id.equals(PhoneRoute.currentId())) { _testFailed = true; }
            if (id.equals(PhoneRoute.currentId())) {
                PhoneRoute.drop();
                toPhone({"t" => "x", "id" => id, "c" => "bad"});
            }
            CrashGuard.calm();
            setRoute(testRoute());
            WatchUi.switchToView(_view, new NavDelegate(_view), WatchUi.SLIDE_IMMEDIATE);
            startLoader();
            return;
        }
        WatchUi.requestUpdate();
        var c = new Timer.Timer();
        _calm = c;
        c.start(method(:calmDown), CrashGuard.CALM_MS, false);
        if (self has :startDemo) {
            startDemo();
            return;
        }
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
    }

    //! Eine Minute ohne Absturz: Die Route gilt als sicher — außer, gerade
    //! kommt eine neue an.
    function calmDown() as Void {
        _calm = null;
        if (_pendingId == null) { CrashGuard.calm(); }
    }

    function onStop(state as Dictionary?) as Void {
        var t = _loader;
        if (t != null) { t.stop(); }
        // Sauber beendet: Kein Absturz zählt gegen die Route.
        CrashGuard.calm();
        if (self has :startDemo) { return; }
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [_view, new NavDelegate(_view)];
    }

    //! Eine Nachricht vom Handy: ein Stück Route oder die Bestwerte.
    function onPhone(msg as Communications.PhoneAppMessage) as Void {
        var d = msg.data;
        if (d instanceof Dictionary) { handle(d); }
    }

    //! Eine Nachricht vom Handy (auch aus dem Vorführmodus, ohne Bluetooth).
    function handle(d as Dictionary) as Void {
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
        var rid = d["id"];
        // Kommt eine Route an, ist sie neu — stürzt die App dabei ab, zählt
        // es gegen sie (CrashGuard).
        if (rid instanceof String) { CrashGuard.risk(rid); }
        var id = PhoneRoute.take(d);
        var err = PhoneRoute.lastError;
        if (err != null) {
            if (rid instanceof String) {
                toPhone({"t" => "x", "id" => rid, "c" => err});
            }
            return;
        }
        if (id == null) { return; }
        // Die Antwort auf eine vollständige Route (Konzept 2): gespeichert.
        toPhone({"t" => "ok", "id" => id});
        if (id.equals(_route.id) && _route.isReady()) {
            CrashGuard.calm();
            return;
        }
        // Kurz am Handgelenk: Die neue Route ist da (#449, 2026-11-05) —
        // dieselbe noch einmal bleibt still.
        vibrateShort();
        _pendingId = id;
        var timer = new Timer.Timer();
        _swap = timer;
        timer.start(method(:swapRoute), 50, false);
    }

    //! Die neue Route: GPS aus, die alte loslassen, die neue laden. Die
    //! alte geht zuerst — beide zugleich passten nicht in den Speicher
    //! (Messung 8.1). Die neue liest ihre Stücke einzeln aus dem Speicher.
    function swapRoute() as Void {
        _swap = null;
        if (_pendingId == null) { return; }
        _pendingId = null;
        var t = _loader;
        if (t != null) { t.stop(); _loader = null; }
        var c = _calm;
        if (c != null) { c.stop(); _calm = null; }
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        setRoute(NavRoute.decoded({"v" => PhoneRoute.PROTOCOL, "id" => "-", "np" => 2, "o" => [0, 0], "pts" => [0, 1]}));
        WatchUi.switchToView(_view, new NavDelegate(_view), WatchUi.SLIDE_IMMEDIATE);
        var r = PhoneRoute.route();
        if (r == null) { r = testRoute(); } else {
            PhoneRoute.store("loading", true);
            CrashGuard.risk(r.id);
        }
        setRoute(r);
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

    //! Der Empfang im Vorführmodus: nächstes Stück, -1 ohne Empfang.
    (:demo) hidden var _demoRx as Number = -1;
    (:demo) hidden var _demoRound as Number = 0;
    //! So viele Punkte je Stück (gerade, damit die Höhen-Paare aufgehen;
    //! mit Höhen gut 750 Zahlen wie die 800 der App).
    (:demo) static const DEMO_PART_POINTS = 500;

    (:demo)
    function startDemo() as Void {
        if (_demoTimer != null) { return; } // nach einem Wechsel läuft er schon
        _demoTimer = new Timer.Timer();
        // Das erste Bild ohne Fix: die Übersicht, wie am Gerät vor dem GPS
        // (dort brach sie den Watchdog, CIQ_LOG.YML 2026-11-05).
        (_demoTimer as Timer.Timer).start(method(:demoTick), 4000, true);
    }

    (:demo)
    function demoTick() as Void {
        if (_demoRx >= 0) {
            demoFeed();
            return;
        }
        if (!_route.isReady()) { return; } // lädt gerade (nach dem Wechsel)
        System.println("demo frame " + _route.size() + " pts");
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
        // Nach jeder Runde der Szenen kommt dieselbe Route noch einmal „vom
        // Handy", mit neuer Kennung: Empfang, Ablegen, Wechsel, Dekodieren
        // aus dem Speicher — ohne Bluetooth, mit den Grenzen der fēnix 5.
        if (_demoScene % scenes.size() == 0) {
            _demoRx = 0;
            _demoRound++;
        }
    }

    //! Ein Stück der Testroute, wie `WatchRoute.parts` es schickte. Die
    //! Ressource liegt dabei kurz ganz im Speicher — die Messung ist also
    //! strenger als der echte Empfang.
    (:demo)
    function demoFeed() as Void {
        var d = WatchUi.loadResource(Rez.JsonData.Route) as Dictionary;
        var np = d["np"] as Number;
        var k = DEMO_PART_POINTS;
        var n = (np + k - 1) / k;
        var a = _demoRx * k;
        var b = a + k < np ? a + k : np;
        var msg = {"t" => "r", "id" => "demo-" + _demoRound, "p" => _demoRx, "n" => n,
            "pts" => (d["pts"] as Array).slice(a, b)} as Dictionary;
        var ele = d["ele"] as Array?;
        if (ele != null) { msg["ele"] = ele.slice(a / 2, (b + 1) / 2); }
        var br = d["br"] as Array<Number>?;
        if (br != null) {
            var mine = [] as Array<Number>;
            for (var i = 0; i + 1 < br.size(); i += 2) {
                if (br[i] >= a && br[i] < b) { mine.add(br[i]); mine.add(br[i + 1]); }
            }
            if (mine.size() > 0) { msg["br"] = mine; }
        }
        if (_demoRx == 0) {
            msg["v"] = d["v"];
            msg["np"] = np;
            msg["o"] = d["o"];
            if (d["e0"] != null) { msg["e0"] = d["e0"]; }
            if (d["sec"] != null) { msg["sec"] = d["sec"]; }
        }
        d = null;
        ele = null;
        br = null;
        var p = _demoRx;
        _demoRx = p + 1 < n ? p + 1 : -1;
        handle(msg);
        var st = System.getSystemStats();
        System.println("demo rx " + p + "/" + n + " err " + PhoneRoute.lastError
            + " used " + st.usedMemory + " total " + st.totalMemory);
    }

    //! Ein kurzer Stoß für „neue Route da" — deutlich kürzer und schwächer
    //! als das Abkommen, damit beides nicht zu verwechseln ist.
    hidden function vibrateShort() as Void {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(50, 200)]);
        }
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
