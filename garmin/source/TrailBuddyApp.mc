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

//! TrailBuddy auf der Uhr (docs/konzept-garmin.md). Die Route kommt vom
//! Handy (G2, `PhoneRoute`) und liegt danach im Speicher der Uhr; ohne
//! eine gespeicherte im Entwicklerbau die erfundene Testroute aus der
//! Ressource (G1), im Store-Bau der Hinweis, die Navigation in der App zu
//! starten ([fallbackRoute], `tool/garmin_build.sh --store`).
//! Eigenes GPS, keine Garmin-Aktivität (kein ActivityRecording, Konzept
//! 4), kein Netz — an das Handy nur „hallo" (`hi`, mit der Kennung der
//! gespeicherten Route und den wartenden Fahrten), „gespeichert" (`ok`),
//! „ging nicht" (`x`) und die eigene Fahrt (`w`, [RideLog]).
//!
//! Ohne Route (Store-Bau ohne Handy, #484) beginnt die freie Fahrt: GPS,
//! die eigene Spur auf der Karte, die Seiten „Fahrt" und „Berg". Die Uhr
//! zeichnet in jedem Fall auf ([RideLog], Betreiber 2026-11-07); beim
//! Beenden geht die Fahrt ans Handy, sonst wartet sie bis zum nächsten
//! Start mit Handy.
//! Eine Route, die die App abstürzen ließ, kommt nicht zweimal hinein
//! ([CrashGuard]).
//!
//! Ist ein Handy verbunden, zeigt der Start erst das Logo als Lader und
//! wartet auf seine Antwort auf „hallo" (Betreiber 2026-11-06): `n` — eine
//! neue Route kommt, die alte zeigt sie gar nicht erst —, `k` — die
//! gespeicherte ist aktuell. Ohne Antwort in [ANSWER_MS] gilt die
//! gespeicherte; bleibt eine angekündigte Route [INCOMING_MS] ohne neues
//! Stück, auch.
//!
//! Die Aufzeichnung steuert man an der Uhr (Betreiber 2026-11-07, „wie
//! Garmin"): START beginnt sie, START hält an und zeigt das Menü Weiter ·
//! Speichern · Verwerfen, LAP (ZURÜCK) markiert „Trail beginnt" / „Trail
//! endet" und fragt nach dem Ende Behalten · Verwerfen. Das Handy hört
//! davon (`rs`, `rt`, `re`) und nimmt mit auf, wenn die App läuft.
//!
//! Die Navigation endet auf beiden Geräten (`e`, Betreiber 2026-11-06):
//! Beendet das Handy, schließt sich die App; beendet man hier, hört es das
//! Handy, bevor die App zugeht ([quit]). Danach geht die Fahrt ans Handy
//! ([closeDown]).
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
    //! Der Start wartet aufs Handy: 0 nein, [WAIT_ANSWER] auf die Antwort
    //! auf „hallo", [WAIT_ROUTE] auf eine angekündigte Route — bis
    //! [_waitUntil] (`System.getTimer`), dann die gespeicherte. Der Takt
    //! ist der Timer des Dekodierens ([loadStep]), kein eigener: Ältere
    //! Uhren haben nur wenige Timer.
    hidden var _wait as Number = 0;
    hidden var _waitUntil as Number = 0;
    hidden var _lastFrame as Number = 0;
    hidden var _exit as Timer.Timer?;
    //! Die eigene Fahrt (#484): läuft vom ersten eigenen Fix bis zum Ende.
    hidden var _log as RideLog;
    //! Die App geht zu ([closeDown]): Es zählt kein Fix mehr, ZURÜCK
    //! schließt sofort.
    hidden var _closing as Boolean = false;
    //! Das Ende sagt schon etwas („verworfen", „zu kurz"): nicht überschreiben.
    hidden var _noted as Boolean = false;
    //! Die Fahrt, die gerade ans Handy geht (`[id, Stücke, Punkte]`), die
    //! nächste Nachricht und seit wann.
    hidden var _tx as Array? = null;
    hidden var _txP as Number = 0;
    hidden var _txAt as Number = 0;
    static const WAIT_ANSWER = 1;
    static const WAIT_ROUTE = 2;
    //! So lange wartet der Start auf die Antwort auf „hallo". Erst 3 s
    //! (Betreiber 2026-11-06); gemessen brauchen „hallo" hin und Antwort
    //! zurück über Garmin Connect 5–7 s (eine kleine Nachricht 3,5 s je
    //! Richtung), also 8 s (Betreiber, am selben Tag).
    static const ANSWER_MS = 8000;
    //! So lange wartet das Beenden auf der Uhr höchstens darauf, dass
    //! Garmin Connect „beendet" abnimmt, bevor die App zugeht.
    static const END_WAIT_MS = 5000;
    //! So lange steht „Navigation beendet", wenn das Handy beendete.
    static const ENDED_SHOW_MS = 1500;
    //! So lange wartet das Beenden je Nachricht der Fahrt auf Garmin
    //! Connect und nach der letzten auf das `wk` des Handys (eine
    //! Nachricht braucht ~3,5 s, Messung 8.2); dann zu, die Fahrt wartet.
    static const RIDE_WAIT_MS = 20000;
    //! So lange steht „Fahrt gespeichert, wartet aufs Handy".
    static const QUEUED_SHOW_MS = 2500;
    //! So lange darf eine angekündigte Route ohne neues Stück sein (eins
    //! braucht über Garmin Connect ~15 s, Messung 8.2).
    static const INCOMING_MS = 45000;
    //! Ein Bild des Laders höchstens alle so viele ms.
    static const FRAME_MS = 100;
    //! Die Testroute ließ sich nicht dekodieren (dann nicht immer wieder).
    hidden var _testFailed as Boolean = false;
    //! Store-Bau ohne Route: freie Fahrt mit GPS und eigener Spur, bis
    //! eine Route vom Handy kommt ([fallbackRoute], #484).
    hidden var _free as Boolean = false;
    //! Die Uhr hat eigenes GPS gehabt: Ab da zählt die Position des Handys
    //! nicht mehr (`p`, Konzept 2).
    hidden var _ownFix as Boolean = false;
    //! Der Stand kam bisher nur vom Handy — mit dem ersten eigenen Fix
    //! beginnt die Verfolgung neu, damit „abseits" am eigenen GPS vibriert.
    hidden var _phoneFixed as Boolean = false;
    //! So viele Punkte je Häppchen: bleibt weit unter dem Watchdog
    //! (120 000 Schritte je Ereignis, NavRoute).
    static const DECODE_BUDGET = 300;
    //! In der freien Fahrt mit Handy sagt die Uhr so oft wieder „hallo",
    //! höchstens [HELLO_AGAIN_N]-mal: Ging die Antwort beim Start
    //! verloren (sie kam nach [ANSWER_MS]) oder scheiterte das Senden der
    //! Route, schickt das Handy sie dann nach (Feldbefund 2026-11-07:
    //! Runde vom Handy gestartet, die Uhr blieb in der freien Fahrt).
    static const HELLO_AGAIN_MS = 30000;
    static const HELLO_AGAIN_N = 20;
    hidden var _helloAt as Number = 0;
    hidden var _hellos as Number = 0;
    //! Vor START schon in Fahrt: einmal kurz vibrieren und erinnern.
    static const NUDGE_MPS = 2.5;
    static const NUDGE_FIXES = 10;
    hidden var _fast as Number = 0;
    hidden var _nudged as Boolean = false;

    function initialize() {
        AppBase.initialize();
        CrashGuard.atStart();
        // Eine Fahrt, die beim letzten Mal nicht zu Ende kam, wartet.
        RideLog.recover();
        _log = new RideLog();
        if (Storage.getValue("loading") == true) {
            PhoneRoute.drop();
            Storage.deleteValue("loading");
        }
        var r;
        if ((Communications has :registerForPhoneAppMessages) && System.getDeviceSettings().phoneConnected) {
            _wait = WAIT_ANSWER;
            r = placeholder();
        } else {
            r = storedRoute();
        }
        _route = r;
        _tracker = new NavTracker(r);
        _stats = new RideStats(r.secFrom.size());
        _view = new NavView(r, _stats, _log);
        if (_wait != 0) { _view.setWaiting(str(Rez.Strings.Loading)); }
        if (_free) { _view.setFree(); }
    }

    //! Die gespeicherte Route vom Handy, sonst die Testroute. Vorher (in
    //! [initialize]) der Schutz vor Abstürzen: [CrashGuard.atStart]
    //! verwirft eine Route, mit der die App zweimal nicht sauber endete;
    //! brach das Laden der gespeicherten beim letzten Mal ab (Speicher,
    //! Watchdog), steht „loading" noch, dann ist sie sofort weg.
    hidden function storedRoute() as NavRoute {
        _free = false;
        var r = PhoneRoute.route();
        if (r != null) {
            PhoneRoute.store("loading", true);
            CrashGuard.risk(r.id);
            return r;
        }
        return fallbackRoute();
    }

    //! Eine Route aus zwei Punkten, solange keine geladen ist (Warten aufs
    //! Handy, Wechsel): Die Ansicht zeigt dann den Lader.
    hidden function placeholder() as NavRoute {
        return NavRoute.decoded({"v" => PhoneRoute.PROTOCOL, "id" => "-", "np" => 2, "o" => [0, 0], "pts" => [0, 1]});
    }

    hidden function str(id as ResourceId) as String {
        return WatchUi.loadResource(id) as String;
    }

    //! Ohne Route vom Handy, im Entwicklerbau: die erfundene Testroute.
    (:testroute)
    hidden function fallbackRoute() as NavRoute {
        return NavRoute.fromDict(WatchUi.loadResource(Rez.JsonData.Route) as Dictionary);
    }

    //! Ohne Route vom Handy, im Store-Bau: keine erfundene Runde um die
    //! eigene Position, sondern die freie Fahrt (#484). Die Testroute
    //! liegt gar nicht im Paket (`tool/garmin_build.sh --store`).
    (:store)
    hidden function fallbackRoute() as NavRoute {
        _free = true;
        return placeholder();
    }

    //! Route, Verfolgung, Zahlen und Ansicht für [r]; die Bestwerte bleiben.
    hidden function setRoute(r as NavRoute) as Void {
        _route = r;
        _tracker = new NavTracker(r);
        _stats = new RideStats(r.secFrom.size());
        _stats.bests = _bests;
        _stats.counting = _log.state() == RideLog.RECORDING;
        _view = new NavView(r, _stats, _log);
        if (_free) { _view.setFree(); }
        _view.setRecord(_log.state(), _log.trailOpen());
    }

    function onStart(state as Dictionary?) as Void {
        _waitUntil = System.getTimer() + ANSWER_MS;
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
        _helloAt = System.getTimer();
        var msg = {"t" => "hi", "v" => PhoneRoute.PROTOCOL} as Dictionary;
        // Die Fassung der Uhr-App (#500): das Handy sieht daran, ob die Uhr
        // ein Fenster um ihren Stand versteht. Eine alte Uhr sagt nichts —
        // dann geht alles wie bisher.
        msg["ver"] = TbVersion.VERSION;
        var id = PhoneRoute.currentId();
        if (id != null) { msg["id"] = id; }
        var bad = CrashGuard.bad();
        if (bad != null) { msg["bad"] = bad; }
        // Die wartenden Fahrten: Das Handy antwortet mit `wq` („schick").
        var rq = RideLog.queuedIds();
        if (rq.size() > 0) { msg["rq"] = rq; }
        toPhone(msg);
    }

    //! An das Handy — nur, wenn eins verbunden ist: Sonst füllte jede
    //! Nachricht die Warteschlange („transmit queue full"), und der
    //! Simulator meldete bei jedem Start „There is no data connection".
    //! Ein verlorenes „hallo" holt das Handy beim Verbinden mit `q` nach.
    hidden function toPhone(msg as Dictionary) as Void {
        if (!System.getDeviceSettings().phoneConnected) { return; }
        send(msg, new PhoneAck());
    }

    //! Senden ans Handy. Auf der Uhr und im Store-Paket über Garmin Connect.
    (:nosim)
    hidden function send(msg as Dictionary, ack as Communications.ConnectionListener) as Void {
        Communications.transmit(msg, null, ack);
    }

    //! Im Simulator (`--test`, `--demo`, `--run`) nichts: Er meldet ein
    //! verbundenes Handy, und ohne ADB öffnete der erste `transmit` bei
    //! jedem Lauf den Dialog „There is no data connection" (Betreiber
    //! 2026-11-07). Es gilt als gescheitert: Das Beenden wartet dann nicht,
    //! und eine Fahrt bleibt in der Warteschlange. Die Tests rufen das
    //! Senden nicht auf.
    (:sim)
    hidden function send(msg as Dictionary, ack as Communications.ConnectionListener) as Void {
        ack.onError();
    }

    hidden function startLoader() as Void {
        var old = _loader;
        if (old != null) { old.stop(); }
        var t = new Timer.Timer();
        _loader = t;
        t.start(method(:loadStep), 50, true);
    }

    //! Ein Häppchen der Route; ist sie fertig, beginnt die Navigation.
    //! Passte sie nicht ([NavRoute.failed]), ist sie weg — das Handy hört
    //! davon, und die Testroute lädt.
    function loadStep() as Void {
        if (_wait != 0) {
            waitStep();
            return;
        }
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
            setRoute(fallbackRoute());
            WatchUi.switchToView(_view, new NavDelegate(_view), WatchUi.SLIDE_IMMEDIATE);
            startLoader();
            return;
        }
        WatchUi.requestUpdate();
        var c = new Timer.Timer();
        _calm = c;
        c.start(method(:calmDown), CrashGuard.CALM_MS, false);
        // Ohne Route die freie Fahrt: GPS für Spur, Zahlen und Aufzeichnung,
        // aber kein Verfolgen (der Platzhalter läge „abseits").
        if (_free) {
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
            return;
        }
        if (self has :startDemo) {
            startDemo();
            return;
        }
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
    }

    //! Der Start wartet aufs Handy: der Lader im Takt, und ist die Zeit um,
    //! die gespeicherte Route.
    hidden function waitStep() as Void {
        var now = System.getTimer();
        if (now - _waitUntil >= 0) {
            endWait();
            loadStored();
            return;
        }
        if (now - _lastFrame >= FRAME_MS) {
            _lastFrame = now;
            WatchUi.requestUpdate();
        }
    }

    hidden function endWait() as Void {
        _wait = 0;
        _view.setWaiting(null);
    }

    //! Die gespeicherte Route laden (sonst [fallbackRoute]) und dekodieren.
    hidden function loadStored() as Void {
        _free = false;
        var r = PhoneRoute.route();
        if (r == null) { r = fallbackRoute(); } else {
            PhoneRoute.store("loading", true);
            CrashGuard.risk(r.id);
        }
        setRoute(r);
        WatchUi.switchToView(_view, new NavDelegate(_view), WatchUi.SLIDE_IMMEDIATE);
        startLoader();
    }

    //! Der Lader sagt, wie weit die angekündigte Route ist: „Route kommt ·
    //! 1/2" (das Stück, das gerade unterwegs ist).
    hidden function waitForRoute(id as String?, n as Number) as Void {
        _wait = WAIT_ROUTE;
        _waitUntil = System.getTimer() + INCOMING_MS;
        var text = str(Rez.Strings.RouteComing);
        if (n > 0) {
            var k = id == null ? 0 : PhoneRoute.received(id);
            text += " · " + (k < n ? k + 1 : n) + "/" + n;
        }
        _view.setWaiting(text);
        WatchUi.requestUpdate();
    }

    //! „Navigation beenden?" (bzw. „TrailBuddy beenden?") mit Ja, und
    //! „Speichern" im Menü der Pause.
    function quit() as Void {
        closeDown(true, true);
    }

    //! „Fahrt verwerfen?" mit Ja: Die Fahrt ist weg, die App geht zu.
    function discardRide() as Void {
        closeDown(true, false);
    }

    // --- Aufzeichnung an der Uhr (Betreiber 2026-11-07) -----------------------

    //! START: beginnen, anhalten (mit Menü) oder weitermachen.
    function startKey() as Void {
        if (_closing) { return; }
        var st = _log.state();
        if (st == RideLog.IDLE) {
            _log.start();
            _stats.counting = true;
            vibrateShort();
            _view.toast(str(Rez.Strings.RecStarted));
            // Das Handy nimmt mit auf, wenn TrailBuddy dort läuft.
            toPhone({"t" => "rs"});
        } else if (st == RideLog.RECORDING) {
            _log.pause();
            _stats.counting = false;
            vibrateShort();
            pauseMenu();
            // Steht auf dem Handy (#499): die Uhr pausiert.
            toPhone({"t" => "rp"});
        } else {
            _log.resume();
            _stats.counting = true;
            vibrateShort();
            _view.toast(str(Rez.Strings.RecStarted));
            // Und weiter, sagt dem Handy (#499).
            toPhone({"t" => "rr"});
        }
        _view.setRecord(_log.state(), _log.trailOpen());
    }

    //! ZURÜCK/LAP: in der Aufzeichnung eine Trail-Marke, in der Pause das
    //! Menü, vor START die Frage nach dem Beenden.
    function backKey() as Void {
        if (_closing) {
            exitNow();
            return;
        }
        var st = _log.state();
        if (st == RideLog.PAUSED) {
            pauseMenu();
            return;
        }
        if (st == RideLog.IDLE) {
            WatchUi.pushView(
                new WatchUi.Confirmation(str(_view.isFree() ? Rez.Strings.AppQuit : Rez.Strings.Quit)),
                new QuitDelegate(),
                WatchUi.SLIDE_IMMEDIATE);
            return;
        }
        var kind = _log.mark(Time.now().value());
        if (kind < 0) {
            _view.toast(str(Rez.Strings.WaitGps));
            return;
        }
        vibrateShort();
        _view.setRecord(_log.state(), _log.trailOpen());
        if (kind == 0) {
            _view.toast(str(Rez.Strings.TrailStart));
            return;
        }
        var menu = new WatchUi.Menu2({:title => str(Rez.Strings.TrailEnd)});
        menu.addItem(new WatchUi.MenuItem(str(Rez.Strings.Keep), null, :keep, null));
        menu.addItem(new WatchUi.MenuItem(str(Rez.Strings.Discard), null, :drop, null));
        WatchUi.pushView(menu, new TrailMenuDelegate(), WatchUi.SLIDE_IMMEDIATE);
    }

    //! Das Menü der Pause: Weiter · Speichern · Verwerfen.
    hidden function pauseMenu() as Void {
        var menu = new WatchUi.Menu2({:title => str(Rez.Strings.RecPaused)});
        menu.addItem(new WatchUi.MenuItem(str(Rez.Strings.Resume), null, :resume, null));
        menu.addItem(new WatchUi.MenuItem(str(Rez.Strings.Save),
            _view.isFree() ? null : str(Rez.Strings.EndsNav), :save, null));
        menu.addItem(new WatchUi.MenuItem(str(Rez.Strings.Discard), null, :discard, null));
        WatchUi.pushView(menu, new PauseMenuDelegate(), WatchUi.SLIDE_IMMEDIATE);
    }

    //! Ein Punkt des Menüs der Pause.
    function pauseChoice(id as Object?) as Void {
        if (id == :resume) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            startKey();
        } else if (id == :save) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            quit();
        } else if (id == :discard) {
            WatchUi.switchToView(new WatchUi.Confirmation(str(Rez.Strings.DiscardRide)),
                new DiscardDelegate(), WatchUi.SLIDE_IMMEDIATE);
        }
    }

    //! Nach „Trail endet": behalten (das Handy hört davon) oder das Paar weg.
    function trailChoice(keep as Boolean) as Void {
        if (keep) {
            var pair = _log.lastTrail();
            if (pair != null) { toPhone({"t" => "rt", "s" => pair[0], "e" => pair[1]}); }
        } else if (_log.dropLastTrail() != null) {
            _view.toast(str(Rez.Strings.TrailDiscarded));
        }
        _view.setRecord(_log.state(), _log.trailOpen());
    }

    //! Langes HOCH (MENU): die nächste Zoomstufe der Karte.
    function menuKey() as Void {
        _view.zoomStep();
    }

    //! Das Ende, von der Uhr ([tellPhone]) oder vom Handy (`e`): Die Fahrt
    //! kommt in die Warteschlange ([RideLog.finish]). Ist die Route vom
    //! Handy und das Handy verbunden und endet es hier, erst „beendet" ans
    //! Handy — es beendet seine Navigation —, und erst wenn Garmin Connect
    //! das abnahm ([EndAck]), höchstens nach [END_WAIT_MS], geht die Fahrt
    //! hinüber ([afterEnd]). Ging die App sofort zu, verfiele die Nachricht.
    //! [keep] false heißt „Verwerfen": Die offene Fahrt geht ganz weg.
    hidden function closeDown(tellPhone as Boolean, keep as Boolean) as Void {
        if (_closing) { return; }
        _closing = true;
        var t = _loader;
        if (t != null) { t.stop(); _loader = null; }
        var started = _log.state() != RideLog.IDLE;
        var note = null;
        if (keep) {
            _log.finish();
            if (_log.lastShort) { note = str(Rez.Strings.RideTooShort); }
        } else {
            _log.discard();
            note = str(Rez.Strings.RideDiscarded);
        }
        _noted = note != null;
        // Das Handy hört, wie die Fahrt hier endete: Eine Aufzeichnung, die
        // es auf `rs` begann, speichert oder verwirft es genauso.
        if (started) { toPhone({"t" => "re", "k" => keep}); }
        var id = _route.id;
        if (tellPhone && _wait == 0 && System.getDeviceSettings().phoneConnected && id.equals(PhoneRoute.currentId())) {
            showEnd(note != null ? note : str(Rez.Strings.NavEnded));
            send({"t" => "e", "id" => id}, new EndAck());
            armExit(END_WAIT_MS);
            return;
        }
        if (note != null) { showEnd(note); }
        afterEnd();
    }

    //! Nach dem Ende: die wartenden Fahrten ans Handy, sonst kurz sagen,
    //! dass die Fahrt wartet, sonst zu.
    function afterEnd() as Void {
        if (startUpload()) { return; }
        if (RideLog.queue().size() > 0 && !_noted) {
            showEnd(str(Rez.Strings.RideWaits));
            armExit(QUEUED_SHOW_MS);
            return;
        }
        if (_view.isEnded()) {
            armExit(ENDED_SHOW_MS);
            return;
        }
        System.exit();
    }

    hidden function showEnd(text as String) as Void {
        _view.setEnded(text);
        WatchUi.requestUpdate();
    }

    //! Ein Timer für das Zugehen, neu gestellt auf [ms].
    hidden function armExit(ms as Number) as Void {
        var old = _exit;
        if (old != null) { old.stop(); }
        var t = new Timer.Timer();
        _exit = t;
        t.start(method(:exitNow), ms, false);
    }

    //! Geht die App gerade zu? ZURÜCK schließt dann sofort.
    function closing() as Boolean {
        return _closing;
    }

    // --- Die Fahrt ans Handy (#484) -----------------------------------------

    //! Die älteste wartende Fahrt ans Handy, eine Nachricht nach der anderen
    //! ([rideSent]); gelöscht wird sie erst mit `wk`. Nicht, solange eine
    //! Route ankommt — eine Übertragung zur Zeit. false, wenn nichts geht.
    hidden function startUpload() as Boolean {
        if (!System.getDeviceSettings().phoneConnected) { return false; }
        if (_tx != null && System.getTimer() - _txAt < RIDE_WAIT_MS) { return false; }
        _tx = null;
        if (!_closing && (_wait != 0 || _pendingId != null)) { return false; }
        var q = RideLog.queue();
        if (q.size() == 0) { return false; }
        _tx = q[0];
        _txP = 0;
        sendRidePart();
        return true;
    }

    hidden function sendRidePart() as Void {
        var e = _tx as Array;
        _txAt = System.getTimer();
        var n = RideLog.messageCount(e);
        if (_closing) {
            showEnd(str(Rez.Strings.RideSending) + " · " + (_txP + 1) + "/" + n);
            armExit(RIDE_WAIT_MS);
        }
        send(RideLog.message(e, _txP), new RideAck());
    }

    //! Garmin Connect nahm eine Nachricht der Fahrt ab ([ok]) oder nicht.
    function rideSent(ok as Boolean) as Void {
        var e = _tx;
        if (e == null) { return; }
        if (!ok) {
            _tx = null;
            if (_closing) { afterFailedUpload(); }
            return;
        }
        _txP++;
        _txAt = System.getTimer();
        if (_txP < RideLog.messageCount(e)) {
            sendRidePart();
        }
        // Sonst wartet sie auf `wk` — beim Beenden höchstens RIDE_WAIT_MS.
    }

    hidden function afterFailedUpload() as Void {
        showEnd(str(Rez.Strings.RideWaits));
        armExit(QUEUED_SHOW_MS);
    }

    //! Das Handy hat die Fahrt [id] gespeichert (oder hatte sie schon):
    //! weg damit, kurz vibrieren, die nächste.
    hidden function rideAcked(id as String) as Void {
        if (!RideLog.ack(id)) { return; }
        var e = _tx;
        if (e != null && id.equals(e[0])) { _tx = null; }
        vibrateShort();
        if (startUpload()) { return; }
        if (_closing) {
            showEnd(str(Rez.Strings.RideOnPhone));
            armExit(ENDED_SHOW_MS);
        }
    }

    function exitNow() as Void {
        System.exit();
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
        // Ging die App anders zu als über [closeDown], wartet die Fahrt.
        _log.finish();
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
        // Die Fahrt: „schick" (`wq`, die Antwort auf „hallo" mit `rq`) und
        // „gespeichert" (`wk`).
        if ("wq".equals(t)) {
            if (!_closing) { startUpload(); }
            return;
        }
        if ("wk".equals(t)) {
            var wid = d["id"];
            if (wid instanceof String) { rideAcked(wid); }
            return;
        }
        if ("p".equals(t)) {
            phoneFix(d["la"], d["lo"]);
            return;
        }
        // Die Antwort auf „hallo": Eine neue Route kommt (`n`, mit der Zahl
        // der Stücke, 0 = noch gerechnet), oder die gespeicherte ist
        // aktuell (`k`). Nur beim Start — läuft schon eine Route, bleibt
        // sie, bis die neue ganz da ist.
        if ("n".equals(t)) {
            var np = d["np"];
            var nid = d["id"];
            if (_wait != 0) { waitForRoute(nid instanceof String ? nid : null, np instanceof Number ? np : 0); }
            return;
        }
        // Das Handy hat die Navigation beendet: Zeigt die Uhr eine Route
        // davon, geht sie zu.
        if ("e".equals(t)) {
            var eid = d["id"];
            if (eid instanceof String && (eid.equals(_route.id) || eid.equals(PhoneRoute.currentId())
                    || (_pendingId != null && eid.equals(_pendingId)))) {
                showEnd(str(Rez.Strings.NavEnded));
                closeDown(false, true);
            }
            return;
        }
        if ("k".equals(t)) {
            if (_wait != 0) {
                endWait();
                loadStored();
            }
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
                var x = {"t" => "x", "id" => rid, "c" => err} as Dictionary;
            if ("ver".equals(err)) { x["v"] = PhoneRoute.PROTOCOL; }
            toPhone(x);
            }
            return;
        }
        if (id == null) {
            // Ein Stück angenommen, es fehlen noch welche: Der Start wartet
            // weiter, und der Lader zählt mit.
            var n = d["n"];
            if (_wait != 0 && rid instanceof String && n instanceof Number) { waitForRoute(rid, n); }
            return;
        }
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
        _wait = 0;
        var t = _loader;
        if (t != null) { t.stop(); _loader = null; }
        var c = _calm;
        if (c != null) { c.stop(); _calm = null; }
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        _free = false;
        setRoute(placeholder());
        WatchUi.switchToView(_view, new NavDelegate(_view), WatchUi.SLIDE_IMMEDIATE);
        loadStored();
    }

    //! Die Position des Handys als erster Fix (Betreiber 2026-11-05): Bis
    //! die Uhr eigenes GPS hat, zeigt sie damit Position, Weg zum Trail und
    //! zum Ziel statt Strichen. Kein Vibrieren (das Handy kann ein paar
    //! Sekunden alt sein), keine Zahlen der Fahrt; nichts wird gespeichert.
    function phoneFix(la as Object?, lo as Object?) as Void {
        if (_ownFix || _free || _wait != 0 || !_route.isReady() || !(la instanceof Number) || !(lo instanceof Number)) { return; }
        if (la < -9000000 || la > 9000000 || lo < -18000000 || lo > 18000000) { return; }
        var lat = la.toDouble() / 100000.0d;
        var lon = lo.toDouble() / 100000.0d;
        if (_route.relative) {
            _route.anchor(lat, lon);
        }
        var p = _route.toLocal(lat, lon);
        var s = _tracker.update(p[0], p[1], null, null, compass());
        _phoneFixed = true;
        _view.setState(s, null, true);
    }

    hidden function compass() as Float? {
        var sensor = Sensor.getInfo();
        if (sensor has :heading && sensor.heading != null) {
            return sensor.heading;
        }
        return null;
    }

    function onPosition(info as Position.Info) as Void {
        if (_closing || _wait != 0 || !_route.isReady()) { return; }
        // Die freie Fahrt fragt wieder nach einer Route ([HELLO_AGAIN_MS]).
        if (_free && _hellos < HELLO_AGAIN_N && System.getTimer() - _helloAt >= HELLO_AGAIN_MS
                && System.getDeviceSettings().phoneConnected) {
            _hellos++;
            sayHello();
        }
        var loc = info.position;
        if (loc == null || info.accuracy < Position.QUALITY_USABLE) {
            return;
        }
        var deg = loc.toDegrees();
        if (!_ownFix) {
            _ownFix = true;
            // „ich habe GPS" — seit #500 mit diesem Fix, damit das Handy Uhr
            // und eigene Position vergleichen kann. Nur im Speicher (A3),
            // nichts wird gespeichert, nichts geht an Garmin.
            toPhone({"t" => "g",
                "la" => Math.round(deg[0].toDouble() * 100000.0),
                "lo" => Math.round(deg[1].toDouble() * 100000.0)});
        }
        var lat = deg[0].toDouble();
        var lon = deg[1].toDouble();
        var sensor = Sensor.getInfo();
        var compass = null;
        if (sensor has :heading && sensor.heading != null) {
            compass = sensor.heading;
        }
        // Höhe vom Barometer, sonst vom GPS.
        var alt = sensor has :altitude && sensor.altitude != null ? sensor.altitude : info.altitude;
        var hr = sensor has :heartRate ? sensor.heartRate : null;
        // Die Fahrt (#484): jeder eigene Fix nach START, ob mit Route oder
        // ohne; vor START und in der Pause nimmt [RideLog.add] nichts.
        _log.add(lat, lon, Time.now().value(), alt, info.accuracy);
        _stats.counting = _log.state() == RideLog.RECORDING;
        nudgeIdle(info.speed);
        if (_free) {
            var f = _log.toLocal(lat, lon);
            _stats.update(f[0], f[1], System.getTimer(), info.speed, alt, hr, -1);
            _view.setFreeFix(f[0], f[1], info.heading, info.speed, compass);
            return;
        }
        if (_phoneFixed) {
            _phoneFixed = false;
            _tracker = new NavTracker(_route);
        }
        if (_route.relative) {
            _route.anchor(lat, lon);
        }
        var p = _route.toLocal(lat, lon);
        var s = _tracker.update(p[0], p[1], info.heading, info.speed, compass);
        if (s.leftRoute) {
            vibrateOnce();
        }
        _stats.update(p[0], p[1], System.getTimer(), info.speed, alt, hr,
            s.offRoute ? -1 : _route.sectionAt(s.alongM));
        _view.setState(s, info.speed, false);
    }

    //! Schon in Fahrt, aber kein START: einmal kurz vibrieren, oben steht
    //! ohnehin „START: Aufnehmen".
    hidden function nudgeIdle(speed as Float?) as Void {
        if (_nudged || _log.state() != RideLog.IDLE) { return; }
        _fast = speed != null && speed >= NUDGE_MPS ? _fast + 1 : 0;
        if (_fast < NUDGE_FIXES) { return; }
        _nudged = true;
        vibrateShort();
        _view.toast(str(Rez.Strings.RecIdle));
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
        // #498 im Simulator: welche Ansicht die Szene nimmt, sagt die Konsole.
        System.println("demo Szene " + (_demoScene - 1) + ": "
            + (s.offRoute ? "abseits " : "auf der Linie ") + Math.round(s.offM) + " m, Sicht "
            + _view.reachM() + " m → "
            + (NavView.beyondView(s.offM, _view.reachM()) ? "eingepasste Übersicht" : "Kartenausschnitt"));
        // Zahlen für die Seiten: erfundene Höhe (steigt stetig) und Puls.
        _demoMs += 4000;
        var demoAlt = 700.0 + _demoMs / 1000.0 * 0.5;
        _stats.update(x, y, _demoMs, 6.0, demoAlt, 128 + _demoScene % 20,
            s.offRoute ? -1 : _route.sectionAt(s.alongM));
        // Strecke und Fahrzeit wie bis zu dieser Stelle gefahren (die Szenen
        // springen, aus den Fixen käme nichts zusammen).
        _stats.distanceM = sc[0];
        _stats.movingS = sc[0] / 5.0;
        _view.setState(s, 6.0, false);
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
        // #498: weitab von der Linie — zeigt im Simulator die eingefasste
        // Übersicht (weiter als `_reach`, deshalb `drawFit`).
        out.add([r.lengthM * 0.5, 1200.0]);
        return out;
    }
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
        (Application.getApp() as TrailBuddyApp).startKey();
        return true;
    }

    function onMenu() as Boolean {
        (Application.getApp() as TrailBuddyApp).menuKey();
        return true;
    }

    //! Beim Zugehen (die Fahrt geht ans Handy) schließt ZURÜCK sofort, sie
    //! wartet dann ([TrailBuddyApp.backKey]).
    function onBack() as Boolean {
        (Application.getApp() as TrailBuddyApp).backKey();
        return true;
    }
}

//! Das Menü der Pause (Weiter · Speichern · Verwerfen). ZURÜCK lässt die
//! Aufzeichnung angehalten; START macht dann weiter.
class PauseMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        (Application.getApp() as TrailBuddyApp).pauseChoice(item.getId());
    }
}

//! Nach „Trail endet": Behalten · Verwerfen. ZURÜCK behält.
class TrailMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        (Application.getApp() as TrailBuddyApp).trailChoice(item.getId() != :drop);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        (Application.getApp() as TrailBuddyApp).trailChoice(true);
    }
}

//! „Fahrt verwerfen?" — Nein lässt sie angehalten.
class DiscardDelegate extends WatchUi.ConfirmationDelegate {
    function initialize() {
        ConfirmationDelegate.initialize();
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            (Application.getApp() as TrailBuddyApp).discardRide();
        }
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
            (Application.getApp() as TrailBuddyApp).quit();
        }
        return true;
    }
}

//! „Beendet" ist beim Handy (oder ging nicht): jetzt die Fahrt.
class EndAck extends Communications.ConnectionListener {
    function initialize() {
        ConnectionListener.initialize();
    }

    function onComplete() as Void {
        (Application.getApp() as TrailBuddyApp).afterEnd();
    }

    function onError() as Void {
        (Application.getApp() as TrailBuddyApp).afterEnd();
    }
}

//! Eine Nachricht der Fahrt ist bei Garmin Connect (oder nicht) — die
//! nächste geht erst dann ([TrailBuddyApp.rideSent]).
class RideAck extends Communications.ConnectionListener {
    function initialize() {
        ConnectionListener.initialize();
    }

    function onComplete() as Void {
        (Application.getApp() as TrailBuddyApp).rideSent(true);
    }

    function onError() as Void {
        (Application.getApp() as TrailBuddyApp).rideSent(false);
    }
}
