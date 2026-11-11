import Toybox.Application;
import Toybox.Attention;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

//! TrailBuddy auf der Uhr (docs/konzept-garmin.md). Der Ablauf — Route
//! vom Handy, Warten beim Start, die Frage nach einer neuen Linie, die
//! Aufzeichnung an den Tasten, das Beenden und die Fahrt ans Handy — steht
//! in [WatchCore] (#508) und ist dort Unit-Test. Diese Klasse ist nur der
//! Wirt: ein Timer, GPS und Sensoren, Garmin Connect, Vibration, Menüs und
//! die Ansicht.
//!
//! Eigenes GPS, keine Garmin-Aktivität (kein ActivityRecording, Konzept
//! 4), kein Netz. Ohne Route vom Handy im Entwicklerbau die erfundene
//! Testroute aus der Ressource (G1), im Store-Bau die freie Fahrt (#484,
//! `tool/garmin_build.sh --store`).
class TrailBuddyApp extends Application.AppBase {
    var core as WatchCore;
    hidden var _view as NavView?;
    //! Der eine Timer des Ablaufs ([WatchCore.pace]).
    hidden var _timer as Timer.Timer?;
    //! Die erste Ansicht steht: ab da wechselt [newView] sie aus.
    hidden var _shown as Boolean = false;

    function initialize() {
        AppBase.initialize();
        core = new WatchCore(self);
    }

    function onStart(state as Dictionary?) as Void {
        // Der Puls vom Handgelenk für die Seite „Fahrt" (bleibt auf der Uhr).
        if (Sensor has :setEnabledSensors) {
            Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
        }
        if (Communications has :registerForPhoneAppMessages) {
            Communications.registerForPhoneAppMessages(method(:onPhone));
        }
        core.start();
    }

    function onStop(state as Dictionary?) as Void {
        pace(0);
        core.stop();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        _shown = true;
        var v = _view as NavView;
        return [v, new NavDelegate(v)];
    }

    // --- Der Wirt des Ablaufs ([WatchCore]) ---------------------------------

    function now() as Number {
        return System.getTimer();
    }

    //! Der Takt des Ablaufs: alle [ms] ein [WatchCore.tick], 0 = keiner.
    function pace(ms as Number) as Void {
        var t = _timer;
        if (t != null) { t.stop(); }
        _timer = null;
        if (ms <= 0) { return; }
        t = new Timer.Timer();
        _timer = t;
        t.start(method(:onTick), ms, true);
    }

    function onTick() as Void {
        core.tick();
    }

    //! Ein Handy, das Nachrichten nehmen kann: Sonst füllte jede Nachricht
    //! die Warteschlange („transmit queue full").
    function connected() as Boolean {
        return (Communications has :registerForPhoneAppMessages) && System.getDeviceSettings().phoneConnected;
    }

    //! An das Handy: einfach, „beendet" ([WatchCore.SEND_END]) oder ein
    //! Stück der Fahrt ([WatchCore.SEND_RIDE]) — die beiden melden zurück.
    function send(msg as Dictionary, kind as Number) as Void {
        transmit(msg, kind == WatchCore.SEND_END ? new EndAck()
            : (kind == WatchCore.SEND_RIDE ? new RideAck() : new PhoneAck()));
    }

    //! Auf der Uhr und im Store-Paket über Garmin Connect.
    (:nosim)
    hidden function transmit(msg as Dictionary, ack as Communications.ConnectionListener) as Void {
        Communications.transmit(msg, null, ack);
    }

    //! Im Simulator (`--test`, `--demo`, `--run`) nichts: Er meldet ein
    //! verbundenes Handy, und ohne ADB öffnete der erste `transmit` bei
    //! jedem Lauf den Dialog „There is no data connection" (Betreiber
    //! 2026-11-07). Es gilt als gescheitert: Das Beenden wartet dann nicht,
    //! und eine Fahrt bleibt in der Warteschlange.
    (:sim)
    hidden function transmit(msg as Dictionary, ack as Communications.ConnectionListener) as Void {
        ack.onError();
    }

    //! Kurz für „neue Route da", Tasten und Marken; lang einmal beim
    //! Abkommen (Entscheidung 3) — deutlich verschieden, kein Ton.
    function vibrate(long as Boolean) as Void {
        if (Attention has :vibrate) {
            Attention.vibrate([long ? new Attention.VibeProfile(100, 700) : new Attention.VibeProfile(50, 200)]);
        }
    }

    hidden function str(id as ResourceId) as String {
        return WatchUi.loadResource(id) as String;
    }

    //! Die Menüs: `:pause` Weiter · Speichern · Verwerfen, `:trail` nach
    //! „Trail endet" Behalten · Verwerfen, `:quit` beenden?, `:discard`
    //! Fahrt verwerfen? (ersetzt das Menü der Pause).
    function menu(kind as Symbol) as Void {
        if (kind == :discard) {
            WatchUi.switchToView(new WatchUi.Confirmation(str(Rez.Strings.DiscardRide)),
                new DiscardDelegate(), WatchUi.SLIDE_IMMEDIATE);
            return;
        }
        if (kind == :quit) {
            WatchUi.pushView(new WatchUi.Confirmation(str(core.free ? Rez.Strings.AppQuit : Rez.Strings.Quit)),
                new QuitDelegate(), WatchUi.SLIDE_IMMEDIATE);
            return;
        }
        var m;
        if (kind == :trail) {
            m = new WatchUi.Menu2({:title => str(Rez.Strings.TrailEnd)});
            m.addItem(new WatchUi.MenuItem(str(Rez.Strings.Keep), null, :keep, null));
            m.addItem(new WatchUi.MenuItem(str(Rez.Strings.Discard), null, :drop, null));
            WatchUi.pushView(m, new TrailMenuDelegate(), WatchUi.SLIDE_IMMEDIATE);
            return;
        }
        m = new WatchUi.Menu2({:title => str(Rez.Strings.RecPaused)});
        m.addItem(new WatchUi.MenuItem(str(Rez.Strings.Resume), null, :resume, null));
        m.addItem(new WatchUi.MenuItem(str(Rez.Strings.Save), core.free ? null : str(Rez.Strings.EndsNav), :save, null));
        m.addItem(new WatchUi.MenuItem(str(Rez.Strings.Discard), null, :discard, null));
        WatchUi.pushView(m, new PauseMenuDelegate(), WatchUi.SLIDE_IMMEDIATE);
    }

    function exit() as Void {
        System.exit();
    }

    //! GPS an (Route fertig geladen, auch in der freien Fahrt) oder aus
    //! (Wechsel, Ende). Der Vorführmodus spielt statt GPS seine Szenen.
    function gps(on as Boolean, free as Boolean) as Void {
        if ((self has :startDemo) && !free) {
            if (on) { startDemo(); }
            return;
        }
        Position.enableLocationEvents(on ? Position.LOCATION_CONTINUOUS : Position.LOCATION_DISABLE,
            method(:onPosition));
    }

    //! Ohne Route vom Handy, im Entwicklerbau: die erfundene Testroute.
    (:testroute)
    function fallback() as NavRoute? {
        return NavRoute.fromDict(WatchUi.loadResource(Rez.JsonData.Route) as Dictionary);
    }

    //! Ohne Route vom Handy, im Store-Bau: keine erfundene Runde um die
    //! eigene Position, sondern die freie Fahrt (#484). Die Testroute
    //! liegt gar nicht im Paket (`tool/garmin_build.sh --store`).
    (:store)
    function fallback() as NavRoute? {
        // Nur für den Simulator: am Gerät ist die Konsole still.
        System.println("Store-Bau: freie Fahrt, keine Route im Paket (#484)");
        return null;
    }

    //! Die Ansicht zur Route des Ablaufs; nach dem Start tritt sie an die
    //! Stelle der alten.
    function newView(c as WatchCore) as NavView {
        var v = new NavView(c.route, c.stats, c.log);
        _view = v;
        if (_shown) { WatchUi.switchToView(v, new NavDelegate(v), WatchUi.SLIDE_IMMEDIATE); }
        return v;
    }

    function compass() as Float? {
        var sensor = Sensor.getInfo();
        return sensor has :heading ? sensor.heading : null;
    }

    // --- Ereignisse an den Ablauf -------------------------------------------

    //! Eine Nachricht vom Handy.
    function onPhone(msg as Communications.PhoneAppMessage) as Void {
        var d = msg.data;
        if (d instanceof Dictionary) { core.handle(d); }
    }

    //! Ein eigener Fix: Höhe vom Barometer, sonst vom GPS; Kompass und Puls.
    function onPosition(info as Position.Info) as Void {
        var loc = info.position;
        var deg = loc != null ? loc.toDegrees() : null;
        var sensor = Sensor.getInfo();
        var alt = sensor has :altitude && sensor.altitude != null ? sensor.altitude : info.altitude;
        core.ownFix(deg != null ? deg[0].toDouble() : null, deg != null ? deg[1].toDouble() : 0.0d,
            info.accuracy, info.heading, info.speed, alt,
            sensor has :heartRate ? sensor.heartRate : null, compass(), Time.now().value());
    }

    (:demo) hidden var _demoTimer as Timer.Timer?;
    (:demo) hidden var _demoScene as Number = 0;
    (:demo) hidden var _demoMs as Number = 0;
    (:demo) hidden var _demoLastId as String = "";
    (:demo) hidden var _demoAsked as String = "";

    //! Der Empfang im Vorführmodus: nächstes Stück, -1 ohne Empfang.
    (:demo) hidden var _demoRx as Number = -1;
    (:demo) hidden var _demoRound as Number = 0;
    //! So viele Punkte je Stück (gerade, damit die Höhen-Paare aufgehen;
    //! mit Höhen gut 750 Zahlen wie die 800 der App).
    (:demo) static const DEMO_PART_POINTS = 500;

    //! Der Simulator behält seinen Speicher zwischen Läufen: ohne diese
    //! Runde sähe das Szenario die Routen und Fahrten des letzten.
    (:demo)
    function demoWipe() as Void {
        PhoneRoute.clear("a");
        PhoneRoute.clear("b");
        Application.Storage.deleteValue("cur");
        Application.Storage.deleteValue("bad");
        Application.Storage.deleteValue("risk");
        var q = RideLog.queue();
        for (var i = 0; i < q.size(); i++) { RideLog.drop(q[i][0] as String, q[i][1] as Number); }
        var wo = Application.Storage.getValue("wo");
        if (wo instanceof Array && wo.size() == 3 && wo[0] instanceof String && wo[1] instanceof Number) {
            RideLog.drop(wo[0] as String, (wo[1] as Number) + 1);
        }
        Application.Storage.deleteValue("rq");
        Application.Storage.deleteValue("wo");
    }

    (:demo)
    function startDemo() as Void {
        if (_demoTimer != null) { return; } // nach einem Wechsel läuft er schon
        demoWipe();
        _demoTimer = new Timer.Timer();
        // Das erste Bild ohne Fix: die Übersicht, wie am Gerät vor dem GPS
        // (dort brach sie den Watchdog, CIQ_LOG.YML 2026-11-05).
        (_demoTimer as Timer.Timer).start(method(:demoTick), 4000, true);
    }

    //! Was nur die Ansicht zeigen kann: die Szenen (Anfahrt, Trail,
    //! abseits, angekommen, weitab), der Speicher je Bild, der Empfang in
    //! Stücken und die Frage nach der neuen Linie. Die Abläufe selbst
    //! prüfen die Unit-Tests des Ablaufkerns (#508).
    (:demo)
    function demoTick() as Void {
        var c = core;
        var route = c.route;
        // Jeder Wechsel auf die Konsole: ohne ihn sähe man ihn nur, wenn
        // zufällig ein Rahmen dazwischen fällt.
        if (route.isReady() && !route.id.equals(_demoLastId)) {
            _demoLastId = route.id;
            System.println("demo Linie jetzt " + route.id + ", " + route.size() + " pts");
        }
        var pid = c.pendingId;
        if (pid != null && c.ui.asking() && !pid.equals(_demoAsked)) {
            _demoAsked = pid;
            System.println("demo 501 Frage steht, Linie " + route.id + ", neue wartet als " + pid);
        }
        if (_demoRx >= 0) {
            demoFeed();
            return;
        }
        if (!route.isReady()) { return; } // lädt gerade (nach dem Wechsel)
        System.println("demo frame " + route.size() + " pts, Linie " + route.id
            + (c.ui.asking() ? ", Frage nach neuer Linie steht" : ""));
        var scenes = DemoScenes.scenes(route);
        var sc = scenes[_demoScene % scenes.size()];
        _demoScene++;
        if (_demoScene % scenes.size() == 1) {
            c.tracker = new NavTracker(route); // „angekommen" bleibt sonst stehen
        }
        var tracker = c.tracker;
        var stats = c.stats;
        // Vor jeder Szene auf der Linie ein Fix mitten im Trail davor, damit
        // die Zusammenfassung befahrene Trails hat.
        if (route.secFrom.size() > 0) {
            var k = route.nextSection(sc[0]);
            k = k < 0 ? route.secFrom.size() - 1 : (k > 0 ? k - 1 : 0);
            var cum = route.cum;
            var q = route.pointAt((cum[route.secFrom[k]] + cum[route.secTo[k]]) / 2);
            stats.update(q[0], q[1], _demoMs, 0.0, null, null, k);
        }
        var along = sc[0];
        var h = route.bearingAt(along);
        var p = route.pointAt(along);
        // Quer nach rechts der Fahrtrichtung.
        var x = p[0] + sc[1] * Math.cos(h).toFloat();
        var y = p[1] - sc[1] * Math.sin(h).toFloat();
        var s = tracker.update(x - 3 * Math.sin(h).toFloat(), y - 3 * Math.cos(h).toFloat(), h, 6.0, null);
        s = tracker.update(x, y, h, 6.0, null);
        var view = _view as NavView;
        // #498 und #500 im Simulator: welche Ansicht die Szene nimmt und ob
        // die Uhr dem Handy ihren Stand melden würde, sagt die Konsole.
        var drift = tracker.driftM(view.reachM());
        System.println("demo Szene " + (_demoScene - 1) + ": "
            + (s.offRoute ? "abseits " : "auf der Linie ") + Math.round(s.offM) + " m, Sicht "
            + view.reachM() + " m → "
            + (NavView.beyondView(s.offM, view.reachM()) ? "eingepasste Übersicht" : "Kartenausschnitt")
            + (drift == null ? ", keine Meldung" : ", Meldung d " + Math.round(drift) + " m"));
        // Zahlen für die Seiten: erfundene Höhe (steigt stetig) und Puls.
        _demoMs += 4000;
        var demoAlt = 700.0 + _demoMs / 1000.0 * 0.5;
        stats.update(x, y, _demoMs, 6.0, demoAlt, 128 + _demoScene % 20,
            s.offRoute ? -1 : route.sectionAt(s.alongM));
        // Strecke und Fahrzeit wie bis zu dieser Stelle gefahren (die Szenen
        // springen, aus den Fixen käme nichts zusammen).
        stats.distanceM = sc[0];
        stats.movingS = sc[0] / 5.0;
        view.setState(s, 6.0, false);
        // Für die Messung 8.1: Speicher nach jedem Bild in die Konsole.
        var st = System.getSystemStats();
        System.println("demo " + route.size() + " pts scene " + (_demoScene - 1) % scenes.size()
            + " used " + st.usedMemory + " total " + st.totalMemory);
        // Nach den ersten beiden Runden der Szenen kommt dieselbe Route noch
        // einmal „vom Handy", mit neuer Kennung: Empfang, Ablegen, Frage,
        // Wechsel, Dekodieren aus dem Speicher — ohne Bluetooth, mit den
        // Grenzen der fēnix 5.
        if (_demoScene % scenes.size() == 0 && _demoRound < 2) {
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
        core.handle(msg);
        var st = System.getSystemStats();
        System.println("demo rx " + p + "/" + n + " err " + PhoneRoute.lastError
            + " used " + st.usedMemory + " total " + st.totalMemory);
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
        // #498: weitab von der Linie — zeigt im Simulator die eingefasste
        // Übersicht (weiter als `_reach`, deshalb `drawFit`).
        out.add([r.lengthM * 0.5, 1200.0]);
        return out;
    }
}

//! Der Ablauf hinter den Tasten und Menüs ([WatchCore]).
function watchCore() as WatchCore {
    return (Application.getApp() as TrailBuddyApp).core;
}

//! Die Tasten wie bei Garmin (Betreiber 2026-11-07, Konzept-Garmin 1):
//! START beginnt die Aufzeichnung bzw. hält sie an (Menü), ZURÜCK ist LAP
//! (Trail beginnt / endet; vor START beenden), hoch/runter blättern die
//! Seiten, langes HOCH (MENU) zoomt die Karte.
class NavDelegate extends WatchUi.BehaviorDelegate {
    hidden var _view as NavView;

    function initialize(view as NavView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onPreviousPage() as Boolean {
        _view.prevPage();
        return true;
    }

    function onNextPage() as Boolean {
        _view.nextPage();
        return true;
    }

    function onSelect() as Boolean {
        watchCore().startKey();
        return true;
    }

    function onMenu() as Boolean {
        _view.zoomStep();
        return true;
    }

    //! Beim Zugehen (die Fahrt geht ans Handy) schließt ZURÜCK sofort, sie
    //! wartet dann ([WatchCore.backKey]).
    function onBack() as Boolean {
        watchCore().backKey();
        return true;
    }
}

//! Das Menü der Pause (Weiter · Speichern · Verwerfen). ZURÜCK lässt die
//! Aufzeichnung angehalten; START macht dann weiter. Verwerfen ersetzt das
//! Menü durch die Rückfrage.
class PauseMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id != :discard) { WatchUi.popView(WatchUi.SLIDE_IMMEDIATE); }
        watchCore().pauseChoice(id);
    }
}

//! Nach „Trail endet": Behalten · Verwerfen. ZURÜCK behält.
class TrailMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        watchCore().trailChoice(item.getId() != :drop);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        watchCore().trailChoice(true);
    }
}

//! „Fahrt verwerfen?" — Nein lässt sie angehalten.
class DiscardDelegate extends WatchUi.ConfirmationDelegate {
    function initialize() {
        ConfirmationDelegate.initialize();
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) { watchCore().discardRide(); }
        return true;
    }
}

class QuitDelegate extends WatchUi.ConfirmationDelegate {
    function initialize() {
        ConfirmationDelegate.initialize();
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) { watchCore().quit(); }
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

//! „Beendet" ist beim Handy (oder ging nicht): jetzt die Fahrt.
class EndAck extends Communications.ConnectionListener {
    function initialize() {
        ConnectionListener.initialize();
    }

    function onComplete() as Void {
        watchCore().endSent();
    }

    function onError() as Void {
        watchCore().endSent();
    }
}

//! Eine Nachricht der Fahrt ist bei Garmin Connect (oder nicht) — die
//! nächste geht erst dann ([WatchCore.rideSent]).
class RideAck extends Communications.ConnectionListener {
    function initialize() {
        ConnectionListener.initialize();
    }

    function onComplete() as Void {
        watchCore().rideSent(true);
    }

    function onError() as Void {
        watchCore().rideSent(false);
    }
}
