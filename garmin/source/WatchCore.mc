import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Time;
import Toybox.WatchUi;

//! Der Ablauf der Uhr ohne Gerät (#508, Prüfleiter S2 in
//! docs/konzept-garmin.md 12): Tasten, Menüs, Fristen und Nachrichten.
//! Er nimmt Ereignisse an (Taste, Menüpunkt, Fix, Nachricht vom Handy,
//! Ergebnis einer Übertragung, Takt) und wirkt nur über zwei Stellen:
//!
//! - den Wirt [_host] — [TrailBuddyApp] auf der Uhr, `FakeHost` in den
//!   Tests: `now()`, `pace(ms)` (Takt an/aus), `connected()`,
//!   `send(msg, kind)` (0 einfach, [SEND_END], [SEND_RIDE]),
//!   `vibrate(long)`, `menu(sym)` (`:pause`, `:trail`, `:quit`,
//!   `:discard`, `:action`, `:zoom`), `exit()`, `gps(on, free)`, `fallback()` (Testroute,
//!   null = freie Fahrt), `newView(core)`, `compass()`;
//! - die Ansicht [ui] ([NavView]), die der Wirt baut.
//!
//! Kein Timer hier drin: Jede Frist ist ein Zeitpunkt (`…At`), den
//! [tick] gegen [now] vergleicht. Ein Test stellt die Uhr vor, statt zu
//! warten. Der Speicher geht wie bisher über [PhoneRoute] und [RideLog].
//!
//! Gerätregel (garmin/CLAUDE.md, Watchdog): Nichts hier läuft über alle
//! Punkte einer Route; das Dekodieren geht in Häppchen ([DECODE_BUDGET]).
class WatchCore {
    var route as NavRoute;
    var tracker as NavTracker;
    var stats as RideStats;
    var log as RideLog;
    //! Die Ansicht ([NavView]); der Wirt baut sie neu, wenn die Route wechselt.
    var ui;
    hidden var _host;
    //! Die Zeit des laufenden Ereignisses (`System.getTimer` bzw. die Uhr
    //! des Tests).
    var now as Number = 0;
    //! Die Bestwerte vom Handy (#36), bleiben über einen Routenwechsel.
    hidden var _bests as Dictionary? = null;
    //! Eine neue Route ist vollständig im Speicher und wartet auf den
    //! Wechsel um [swapAt] — gleich (im nächsten Takt, nicht im Rückruf)
    //! oder nach der Frage ([ASK_MS]). 0 = nichts wartet.
    var pendingId as String? = null;
    var swapAt as Number = 0;
    //! Die Route wird gerade dekodiert ([loadStep]).
    var loading as Boolean = false;
    //! Eine Minute nach dem Laden ohne Absturz: [CrashGuard.calm].
    hidden var _calmAt as Number = 0;
    //! Die App geht um [exitAt] zu (0: nicht gestellt).
    var exitAt as Number = 0;
    //! Der Start wartet aufs Handy: 0 nein, [WAIT_ANSWER] auf die Antwort
    //! auf „hallo", [WAIT_ROUTE] auf eine angekündigte Route — bis
    //! [_waitUntil], dann die gespeicherte.
    var wait as Number = 0;
    hidden var _waitUntil as Number = 0;
    hidden var _lastFrame as Number = 0;
    //! Die App geht zu ([closeDown]): Es zählt kein Fix mehr, ZURÜCK
    //! schließt sofort.
    var closing as Boolean = false;
    //! Das Ende sagt schon etwas („verworfen", „zu kurz"): nicht überschreiben.
    hidden var _noted as Boolean = false;
    //! Die Fahrt, die gerade ans Handy geht (`[id, Stücke, Punkte]`), die
    //! nächste Nachricht und seit wann.
    var tx as Array? = null;
    var txP as Number = 0;
    hidden var _txAt as Number = 0;
    //! Eine Fahrt wartet, durfte aber nicht gehen, weil eine Route kam
    //! ([startUpload]): Sie geht, sobald die Route geladen ist (#509, Fall
    //! 509.7 — sonst verfiel ein „schick" während des Wartens).
    hidden var _uploadLater as Boolean = false;
    //! Die Testroute ließ sich nicht dekodieren (dann nicht immer wieder).
    hidden var _testFailed as Boolean = false;
    //! Ohne Route: freie Fahrt mit GPS und eigener Spur, bis eine Route
    //! vom Handy kommt (#484).
    var free as Boolean = false;
    //! Die Uhr hat eigenes GPS gehabt: Ab da zählt die Position des Handys
    //! nicht mehr (`p`, Konzept 2).
    hidden var _ownFix as Boolean = false;
    //! Der Stand kam bisher nur vom Handy — mit dem ersten eigenen Fix
    //! beginnt die Verfolgung neu, damit „abseits" am eigenen GPS vibriert.
    hidden var _phoneFixed as Boolean = false;
    hidden var _helloAt as Number = 0;
    hidden var _hellos as Number = 0;
    hidden var _fast as Number = 0;
    hidden var _nudged as Boolean = false;
    //! Der Takt, den der Wirt gerade hält (ms, 0 = keiner).
    hidden var _pace as Number = 0;
    //! Die Klasse des letzten Fixes im Ring (#510), -1 noch keiner.
    hidden var _fixCls as Number = -1;

    static const WAIT_ANSWER = 1;
    static const WAIT_ROUTE = 2;
    static const SEND_END = 1;
    static const SEND_RIDE = 2;
    //! So lange wartet der Start auf die Antwort auf „hallo". Erst 3 s
    //! (Betreiber 2026-11-06); gemessen brauchen „hallo" hin und Antwort
    //! zurück über Garmin Connect 5–7 s (eine kleine Nachricht 3,5 s je
    //! Richtung), also 8 s (Betreiber, am selben Tag).
    static const ANSWER_MS = 8000;
    //! Wie lange die Uhr fragt, ob sie eine neue Linie nehmen soll (#501,
    //! Konzept 2). Wer nichts tut, nimmt sie; START nimmt sie sofort,
    //! ZURÜCK lässt sie liegen (#513, Entscheidung E2 vom 2026-11-12).
    static const ASK_MS = 8000;
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
    //! Vor START schon in Fahrt: einmal kurz vibrieren und erinnern.
    static const NUDGE_MPS = 2.5;
    static const NUDGE_FIXES = 10;

    //! Der Schutz vor Abstürzen ([CrashGuard.atStart]), eine abgebrochene
    //! Fahrt in die Warteschlange; brach das Laden der gespeicherten Route
    //! beim letzten Mal ab (Speicher, Watchdog), steht „loading" noch, dann
    //! ist sie sofort weg. Mit verbundenem Handy wartet der Start auf
    //! dessen Antwort (Betreiber 2026-11-06), sonst die gespeicherte Route.
    function initialize(host) {
        _host = host;
        now = host.now();
        // Zuerst: Der alte Ring wird nach einem Absturz „evc", und eine
        // abgebrochene Fahrt nimmt ihn mit (#510).
        EventLog.boot(now, host.connected());
        CrashGuard.atStart();
        RideLog.recover();
        log = new RideLog();
        if (Application.Storage.getValue("loading") == true) {
            PhoneRoute.drop();
            Application.Storage.deleteValue("loading");
        }
        var r;
        if (host.connected()) {
            wait = WAIT_ANSWER;
            r = placeholder();
        } else {
            r = stored();
        }
        // Für den Typprüfer: setRoute legt alle drei neu an.
        route = r;
        tracker = new NavTracker(r);
        stats = new RideStats(0);
        setRoute(r);
        if (wait != 0) {
            ui.setWaiting(str(Rez.Strings.Loading));
            ev(71); // Stand: Lader wartet
        }
    }

    //! Eine Route aus zwei Punkten, solange keine geladen ist (Warten aufs
    //! Handy, Wechsel, freie Fahrt).
    static function placeholder() as NavRoute {
        return NavRoute.decoded({"v" => PhoneRoute.PROTOCOL, "id" => "-", "np" => 2, "o" => [0, 0], "pts" => [0, 1]});
    }

    hidden function str(id as ResourceId) as String {
        return WatchUi.loadResource(id) as String;
    }

    //! Die gespeicherte Route vom Handy; ohne sie die Testroute des Wirts,
    //! im Store-Bau die freie Fahrt (#484).
    hidden function stored() as NavRoute {
        free = false;
        var r = PhoneRoute.route();
        if (r != null) {
            PhoneRoute.store("loading", true);
            CrashGuard.risk(r.id);
            return r;
        }
        return fallback();
    }

    hidden function fallback() as NavRoute {
        var r = _host.fallback();
        if (r == null) {
            free = true;
            return placeholder();
        }
        return r;
    }

    //! Route, Verfolgung, Zahlen und Ansicht für [r]; die Bestwerte bleiben.
    hidden function setRoute(r as NavRoute) as Void {
        route = r;
        tracker = new NavTracker(r);
        var old = stats;
        stats = new RideStats(r.secFrom.size());
        // Die Fahrt geht weiter, auch wenn die Route wechselt oder endet
        // (#513: Navigation ist eine Ebene, kein Modus).
        stats.carryFrom(old);
        stats.bests = _bests;
        stats.counting = log.state() == RideLog.RECORDING;
        ui = _host.newView(self);
        if (free) { ui.setFree(); }
        ui.setRecord(log.state(), log.trailOpen());
    }

    //! Den Takt des Wirts nachziehen: schnell, solange geladen oder
    //! gewartet wird (Bild des Laders, Häppchen), langsam für eine Frist,
    //! sonst keiner. Ein Timer für alles — ältere Uhren haben nur wenige.
    hidden function pace() as Void {
        var p = loading || wait != 0 ? 50 : (swapAt != 0 || exitAt != 0 || _calmAt != 0 ? 250 : 0);
        if (p != _pace) {
            _pace = p;
            _host.pace(p);
        }
    }

    // --- Ereignisse -----------------------------------------------------------

    //! Die App startet: laden bzw. auf das Handy warten, „hallo" sagen.
    function start() as Void {
        now = _host.now();
        _waitUntil = now + ANSWER_MS;
        loading = true;
        pace();
        sayHello();
    }

    //! Der Takt: Fristen, Lader, Häppchen der Route.
    function tick() as Void {
        now = _host.now();
        // Die Frist der Frage läuft sichtbar ab (#513).
        if (swapAt != 0 && ui.asking()) { WatchUi.requestUpdate(); }
        if (exitAt != 0 && now - exitAt >= 0) {
            exitAt = 0;
            ev(80); // Frist: zu
            _host.exit();
            return;
        }
        if (!closing) {
            if (swapAt != 0 && now - swapAt >= 0) {
                // Erst im nächsten Takt dekodieren: Bis dahin hält die alte
                // Ansicht die alte Route, und beide zusammen passen nicht in
                // den Speicher (Out of Memory bei 1000 Punkten, Vorführmodus
                // 2026-11-11).
                ev(81); // Frist: Wechsel
                swapRoute();
                pace();
                return;
            }
            if (_calmAt != 0 && now - _calmAt >= 0) {
                // Eine Minute ohne Absturz: Die Route gilt als sicher —
                // außer, gerade kommt eine neue an.
                _calmAt = 0;
                ev(82); // Frist: ruhige Minute
                if (pendingId == null) { CrashGuard.calm(); }
            }
            if (wait != 0) {
                waitStep();
            } else if (loading) {
                loadStep();
            }
        }
        pace();
    }

    //! Die App ging zu (auch anders als über [closeDown]): Die Fahrt wartet,
    //! kein Absturz zählt gegen die Route.
    function stop() as Void {
        log.finish();
        EventLog.stop(_host.now());
        CrashGuard.calm();
        _host.gps(false, false);
    }

    //! „Hallo" an das Handy, beim Start und auf seine Frage `q`: die
    //! Kennung der gespeicherten Route (Betreiber 2026-11-04). Weicht sie
    //! von der Navigation auf dem Handy ab, schickt es die aktuelle; folgt
    //! die Uhr keiner Navigation, bleibt die Nachricht ohne Antwort.
    hidden function sayHello() as Void {
        _helloAt = now;
        // `ver` (#500): das Handy sieht daran, ob die Uhr ein Fenster um
        // ihren Stand versteht.
        var msg = {"t" => "hi", "v" => PhoneRoute.PROTOCOL, "ver" => TbVersion.VERSION} as Dictionary;
        var id = PhoneRoute.currentId();
        if (id != null) { msg["id"] = id; }
        var bad = CrashGuard.bad();
        if (bad != null) { msg["bad"] = bad; }
        // Die wartenden Fahrten: Das Handy antwortet mit `wq` („schick").
        var rq = RideLog.queuedIds();
        if (rq.size() > 0) { msg["rq"] = rq; }
        // Ging die App beim letzten Mal nicht zu, reist der alte Ring mit
        // (#510); ein älteres Handy übersieht den Schlüssel.
        var crash = EventLog.crashed(_host.connected());
        if (crash != null) { msg["ev"] = crash; }
        toPhone(msg);
    }

    //! An das Handy — nur, wenn eins verbunden ist: Sonst füllte jede
    //! Nachricht die Warteschlange („transmit queue full"). Ein verlorenes
    //! „hallo" holt das Handy beim Verbinden mit `q` nach.
    hidden function toPhone(msg as Dictionary) as Void {
        if (_host.connected()) { send(msg, 0); }
    }

    //! Ein Ereignis in den Ring (#510): [code] = `Art << 3 | Detail`, die
    //! Tabelle steht in [EventLog]. Zahlen statt Konstanten, des Speichers
    //! wegen.
    hidden function ev(code as Number) as Void {
        EventLog.rec(code, now);
    }

    //! Ein Fix nach seiner Klasse (Art 9) — nur, wenn sie wechselt.
    hidden function fixEv(cls as Number) as Void {
        if (cls == _fixCls) { return; }
        _fixCls = cls;
        ev(72 + cls);
    }

    //! Alles ans Handy geht hier durch — der Ring merkt sich die Art.
    hidden function send(msg as Dictionary, kind as Number) as Void {
        ev(EventLog.msgCode(msg["t"], true));
        _host.send(msg, kind);
    }

    //! Ein Häppchen der Route; ist sie fertig, beginnt die Navigation.
    //! Passte sie nicht ([NavRoute.failed]), ist sie weg — das Handy hört
    //! davon, und die Testroute lädt.
    hidden function loadStep() as Void {
        if (!route.decodeStep(DECODE_BUDGET)) {
            WatchUi.requestUpdate();
            return;
        }
        loading = false;
        Application.Storage.deleteValue("loading");
        if (route.failed) {
            var id = route.id;
            var mine = id.equals(PhoneRoute.currentId());
            // Die Testroute selbst passte nicht: nicht noch einmal laden —
            // das war eine Schleife alle 50 ms („Lade Route 0 %", fēnix 5,
            // 2026-11-05). Die Ansicht sagt es.
            if (!mine && _testFailed) {
                WatchUi.requestUpdate();
                return;
            }
            if (mine) {
                PhoneRoute.drop();
                toPhone({"t" => "x", "id" => id, "c" => "bad"});
            } else {
                _testFailed = true;
            }
            CrashGuard.calm();
            free = false;
            setRoute(fallback());
            loading = true;
            return;
        }
        WatchUi.requestUpdate();
        ev(free ? 67 : 68); // Stand: frei / Route geladen
        _calmAt = now + CrashGuard.CALM_MS;
        if (_uploadLater) {
            _uploadLater = false;
            startUpload();
        }
        // Ohne Route die freie Fahrt: GPS für Spur, Zahlen und Aufzeichnung,
        // aber kein Verfolgen (der Platzhalter läge „abseits").
        _host.gps(true, free);
    }

    //! Der Start wartet aufs Handy: der Lader im Takt, und ist die Zeit um,
    //! die gespeicherte Route.
    hidden function waitStep() as Void {
        if (now - _waitUntil >= 0) {
            ev(83); // Frist: Warten vorbei
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
        wait = 0;
        ui.setWaiting(null);
    }

    //! Die gespeicherte Route laden (sonst die Testroute bzw. die freie
    //! Fahrt) und dekodieren.
    hidden function loadStored() as Void {
        setRoute(stored());
        loading = true;
        pace();
    }

    //! Der Lader sagt, wie weit die angekündigte Route ist: „Route kommt ·
    //! 1/2" (das Stück, das gerade unterwegs ist).
    hidden function waitForRoute(id as String?, n as Number) as Void {
        wait = WAIT_ROUTE;
        _waitUntil = now + INCOMING_MS;
        var text = str(Rez.Strings.RouteComing);
        if (n > 0) {
            var k = id == null ? 0 : PhoneRoute.received(id);
            text += " · " + (k < n ? k + 1 : n) + "/" + n;
        }
        ui.setWaiting(text);
        WatchUi.requestUpdate();
    }

    // --- Aufzeichnung an der Uhr (Betreiber 2026-11-07) -----------------------

    //! START: beginnen, anhalten (mit Menü) oder weitermachen.
    function startKey() as Void {
        now = _host.now();
        ev(8); // Taste START
        if (closing || answerAsk(true)) { return; }
        var st = log.state();
        if (st == RideLog.RECORDING) {
            log.pause();
            // Steht auf dem Handy (#499): die Uhr pausiert.
            toPhone({"t" => "rp"});
        } else {
            if (st == RideLog.IDLE) {
                log.start();
                // Das Handy nimmt mit auf, wenn TrailBuddy dort läuft.
                toPhone({"t" => "rs"});
            } else {
                log.resume();
                // Und weiter, sagt dem Handy (#499).
                toPhone({"t" => "rr"});
            }
            ui.toast(str(Rez.Strings.RecStarted));
        }
        stats.counting = st != RideLog.RECORDING;
        ev(64 + log.state()); // Stand der Aufnahme
        _host.vibrate(false);
        if (st == RideLog.RECORDING) { _host.menu(:pause); }
        ui.setRecord(log.state(), log.trailOpen());
    }

    //! ZURÜCK/LAP: in der Aufzeichnung eine Trail-Marke, in der Pause das
    //! Menü, vor START die Frage nach dem Beenden; beim Zugehen sofort zu.
    function backKey() as Void {
        now = _host.now();
        ev(9); // Taste ZURÜCK
        if (closing) {
            _host.exit();
            return;
        }
        if (answerAsk(false)) { return; }
        var st = log.state();
        if (st != RideLog.RECORDING) {
            _host.menu(st == RideLog.PAUSED ? :pause : :quit);
            return;
        }
        var kind = log.mark(Time.now().value());
        if (kind < 0) {
            ui.toast(str(Rez.Strings.WaitGps));
            return;
        }
        _host.vibrate(false);
        ui.setRecord(log.state(), log.trailOpen());
        if (kind == 0) {
            ui.toast(str(Rez.Strings.TrailStart));
        } else {
            _host.menu(:trail);
        }
    }

    //! Steht die Frage nach einer neuen Linie (#501)?
    function asking() as Boolean {
        return pendingId != null && swapAt != 0 && ui.asking();
    }

    //! Eine Taste während der Frage nach einer neuen Linie (#513, E2:
    //! START heißt überall ja). [yes]: im nächsten Takt wechseln, wie nach
    //! der Frist. Nein (ZURÜCK): sie bleibt liegen — die Stücke liegen schon
    //! im Speicher der Uhr, weg damit, sonst läge beim nächsten Start die
    //! abgelehnte Linie vor der alten. false, wenn keine Frage steht.
    hidden function answerAsk(yes as Boolean) as Boolean {
        if (!asking()) { return false; }
        ui.clearAsk();
        if (yes) {
            swapAt = now;
        } else {
            swapAt = 0;
            pendingId = null;
            PhoneRoute.drop();
        }
        WatchUi.requestUpdate();
        return true;
    }

    // --- Das Aktionsmenü (#513, langes HOCH) ---------------------------------

    //! Langes HOCH: das Aktionsmenü. Nicht, solange eine Frage steht (die
    //! Frage bleibt), im Lader oder beim Zugehen.
    function menuKey() as Void {
        now = _host.now();
        ev(10); // langes HOCH
        if (closing || wait != 0 || asking() || !route.isReady()) { return; }
        _host.menu(:action);
    }

    //! Die Punkte des Aktionsmenüs — nur, was gerade gehen kann (#513):
    //! Zoom immer, „Route beenden" nur mit einer Route. Die Punkte anderer
    //! Issues (Trails in der Nähe, Routenablage, Aufträge, Buddys) kommen
    //! mit ihnen.
    function actions() as Array<Symbol> {
        var a = [:zoom] as Array<Symbol>;
        if (!free && !route.failed) { a.add(:endRoute); }
        return a;
    }

    //! Ein Punkt des Aktionsmenüs — oder eine Zoomstufe aus dessen
    //! Untermenü (eine Zahl: [NavView.ZOOM_AUTO] oder die Stufe in
    //! [NavView.ZOOM_MPP]; von Hand gilt sie bis zum nächsten Trailkopf).
    function actionChoice(id as Object?) as Void {
        now = _host.now();
        if (id == :zoom) {
            _host.menu(:zoom);
        } else if (id == :endRoute) {
            endRoute();
        } else if (id instanceof Number) {
            ui.setZoomMode(id);
        }
    }

    //! „Route beenden" (#513): Die Navigation endet, die Aufzeichnung läuft
    //! weiter — die Uhr fährt frei weiter, mit Strecke und Zeit. Das Handy
    //! hört es wie ein Beenden an der Uhr (`e`) und beendet seine
    //! Navigation; seine Aufzeichnung läuft auch dort weiter (G2d). Die
    //! gespeicherte Route ist weg, sonst käme sie beim nächsten Start wieder.
    function endRoute() as Void {
        now = _host.now();
        if (closing || free) { return; }
        ev(23); // Menü: Route beenden
        var id = route.id;
        if (id.equals(PhoneRoute.currentId())) {
            toPhone({"t" => "e", "id" => id});
            PhoneRoute.drop();
        }
        swapAt = 0;
        pendingId = null;
        loading = false;
        _calmAt = 0;
        CrashGuard.calm();
        free = true;
        var p = placeholder();
        ui.forget(p);
        setRoute(p);
        ui.toast(str(Rez.Strings.NavEnded));
        _host.gps(true, true);
        pace();
    }

    //! Ein Punkt des Menüs der Pause: Weiter · Speichern · Verwerfen (fragt
    //! erst, [discardRide]).
    function pauseChoice(id as Object?) as Void {
        now = _host.now();
        if (id == :resume) {
            ev(16); // Menü: Weiter
            startKey();
        } else if (id == :save) {
            ev(17); // Menü: Speichern
            closeDown(true, true);
        } else if (id == :discard) {
            ev(18); // Menü: Verwerfen
            _host.menu(:discard);
        }
    }

    //! Nach „Trail endet": behalten (das Handy hört davon) oder das Paar weg.
    function trailChoice(keep as Boolean) as Void {
        now = _host.now();
        ev(keep ? 21 : 22); // Menü: Trail behalten / verwerfen
        if (keep) {
            var pair = log.lastTrail();
            if (pair != null) { toPhone({"t" => "rt", "s" => pair[0], "e" => pair[1]}); }
        } else if (log.dropLastTrail() != null) {
            ui.toast(str(Rez.Strings.TrailDiscarded));
        }
        ui.setRecord(log.state(), log.trailOpen());
    }

    //! „Navigation beenden?" (bzw. „TrailBuddy beenden?") mit Ja, und
    //! „Speichern" im Menü der Pause.
    function quit() as Void {
        now = _host.now();
        ev(19); // Menü: Ja
        closeDown(true, true);
    }

    //! „Nein" auf „Fahrt verwerfen?" oder „… beenden?": Am Ablauf ändert
    //! sich nichts, aber der Ring weiß es (#510).
    function confirmNo() as Void {
        now = _host.now();
        ev(20); // Menü: Nein
    }

    //! „Fahrt verwerfen?" mit Ja: Die Fahrt ist weg, die App geht zu.
    function discardRide() as Void {
        now = _host.now();
        ev(19); // Menü: Ja
        closeDown(true, false);
    }

    //! Das Ende, von der Uhr ([tellPhone]) oder vom Handy (`e`): Die Fahrt
    //! kommt in die Warteschlange ([RideLog.finish]). Ist die Route vom
    //! Handy und das Handy verbunden und endet es hier, erst „beendet" ans
    //! Handy — es beendet seine Navigation —, und erst wenn Garmin Connect
    //! das abnahm ([endSent]), höchstens nach [END_WAIT_MS], geht die Fahrt
    //! hinüber. Ging die App sofort zu, verfiele die Nachricht.
    //! [keep] false heißt „Verwerfen": Die offene Fahrt geht ganz weg.
    hidden function closeDown(tellPhone as Boolean, keep as Boolean) as Void {
        if (closing) { return; }
        closing = true;
        loading = false;
        ev(69); // Stand: geht zu
        var started = log.state() != RideLog.IDLE;
        var note = null;
        if (keep) {
            log.finish();
            if (log.lastShort) { note = str(Rez.Strings.RideTooShort); }
        } else {
            log.discard();
            note = str(Rez.Strings.RideDiscarded);
        }
        _noted = note != null;
        // Das Handy hört, wie die Fahrt hier endete: Eine Aufzeichnung, die
        // es auf `rs` begann, speichert oder verwirft es genauso.
        if (started) { toPhone({"t" => "re", "k" => keep}); }
        var id = route.id;
        if (tellPhone && wait == 0 && _host.connected() && id.equals(PhoneRoute.currentId())) {
            showEnd(note != null ? note : str(Rez.Strings.NavEnded));
            armExit(END_WAIT_MS);
            send({"t" => "e", "id" => id}, SEND_END);
            return;
        }
        if (note != null) { showEnd(note); }
        endSent();
    }

    //! Nach dem Ende („beendet" ist beim Handy oder ging nicht): die
    //! wartenden Fahrten ans Handy, sonst kurz sagen, dass die Fahrt
    //! wartet, sonst zu.
    //! Garmin Connect hat das „beendet" abgenommen ([ok]) oder nicht.
    function endAcked(ok as Boolean) as Void {
        now = _host.now();
        ev(ok ? 56 : 57); // Übertragung: Ende
        endSent();
    }

    function endSent() as Void {
        now = _host.now();
        if (startUpload()) { return; }
        if (RideLog.queue().size() > 0 && !_noted) {
            showEnd(str(Rez.Strings.RideWaits));
            armExit(QUEUED_SHOW_MS);
            return;
        }
        if (ui.isEnded()) {
            armExit(ENDED_SHOW_MS);
            return;
        }
        _host.exit();
    }

    hidden function showEnd(text as String) as Void {
        ui.setEnded(text);
        WatchUi.requestUpdate();
    }

    //! Die Frist für das Zugehen, neu gestellt auf [ms].
    hidden function armExit(ms as Number) as Void {
        exitAt = now + ms;
        pace();
    }

    // --- Die Fahrt ans Handy (#484) -----------------------------------------

    //! Die älteste wartende Fahrt ans Handy, eine Nachricht nach der anderen
    //! ([rideSent]); gelöscht wird sie erst mit `wk`. Nicht, solange eine
    //! Route ankommt — eine Übertragung zur Zeit. false, wenn nichts geht.
    hidden function startUpload() as Boolean {
        if (!_host.connected()) { return false; }
        if (tx != null && now - _txAt < RIDE_WAIT_MS) { return false; }
        tx = null;
        var q = RideLog.queue();
        if (q.size() == 0) { return false; }
        if (!closing && (wait != 0 || pendingId != null)) {
            _uploadLater = true;
            return false;
        }
        tx = q[0];
        txP = 0;
        sendRidePart();
        return true;
    }

    hidden function sendRidePart() as Void {
        var e = tx as Array;
        _txAt = now;
        if (closing) {
            showEnd(str(Rez.Strings.RideSending) + " · " + (txP + 1) + "/" + RideLog.messageCount(e));
            armExit(RIDE_WAIT_MS);
        }
        send(RideLog.message(e, txP), SEND_RIDE);
    }

    //! Garmin Connect nahm eine Nachricht der Fahrt ab ([ok]) oder nicht.
    function rideSent(ok as Boolean) as Void {
        now = _host.now();
        var e = tx;
        if (e == null) { return; }
        ev(ok ? 58 : 59); // Übertragung: Fahrt
        if (!ok) {
            tx = null;
            if (closing) {
                showEnd(str(Rez.Strings.RideWaits));
                armExit(QUEUED_SHOW_MS);
            }
            return;
        }
        txP++;
        _txAt = now;
        // Sonst wartet sie auf `wk` — beim Beenden höchstens RIDE_WAIT_MS.
        if (txP < RideLog.messageCount(e)) { sendRidePart(); }
    }

    //! Das Handy hat die Fahrt [id] gespeichert (oder hatte sie schon):
    //! weg damit, kurz vibrieren, die nächste.
    hidden function rideAcked(id as String) as Void {
        if (!RideLog.ack(id)) { return; }
        var e = tx;
        if (e != null && id.equals(e[0])) { tx = null; }
        _host.vibrate(false);
        if (startUpload()) { return; }
        if (closing) {
            showEnd(str(Rez.Strings.RideOnPhone));
            armExit(ENDED_SHOW_MS);
        }
    }

    // --- Nachrichten vom Handy ---------------------------------------------

    //! #501 (Konzept 2): Eine neue Linie während einer laufenden Fahrt will
    //! gefragt sein. Beim Start, im Lader [wait] und in der freien Fahrt
    //! [free] nimmt sie still; dieselbe Linie kommt nie hier an, sie kehrt
    //! schon vorher zurück (gleiche Kennung).
    static function asksBeforeSwap(waiting as Number, free as Boolean, ready as Boolean) as Boolean {
        return waiting == 0 && !free && ready;
    }

    //! Eine Nachricht vom Handy (auch aus dem Vorführmodus, ohne Bluetooth).
    function handle(d as Dictionary) as Void {
        now = _host.now();
        var t = d["t"];
        ev(EventLog.msgCode(t, false));
        var id = d["id"];
        if (!(id instanceof String)) { id = null; }
        if ("q".equals(t)) {
            sayHello();
        } else if ("wq".equals(t)) {
            // Eine Antwort auf „hallo": Der Absturz-Ring kam mit an.
            EventLog.delivered();
            // Die Fahrt: „schick" (die Antwort auf „hallo" mit `rq`) …
            if (!closing) { startUpload(); }
        } else if ("wk".equals(t)) {
            // … und „gespeichert".
            if (id != null) { rideAcked(id); }
        } else if ("p".equals(t)) {
            phoneFix(d["la"], d["lo"]);
        } else if ("n".equals(t)) {
            EventLog.delivered();
            // Die Antwort auf „hallo": Eine neue Route kommt (mit der Zahl
            // der Stücke, 0 = noch gerechnet). Nur beim Start — läuft schon
            // eine Route, bleibt sie, bis die neue ganz da ist.
            var np = d["np"];
            if (wait != 0) { waitForRoute(id, np instanceof Number ? np : 0); }
        } else if ("k".equals(t)) {
            EventLog.delivered();
            // … oder die gespeicherte ist aktuell.
            if (wait != 0) {
                endWait();
                loadStored();
            }
        } else if ("e".equals(t)) {
            // Das Handy hat die Navigation beendet: Zeigt die Uhr eine Route
            // davon, geht sie zu.
            if (id != null && (id.equals(route.id) || id.equals(PhoneRoute.currentId())
                    || id.equals(pendingId))) {
                showEnd(str(Rez.Strings.NavEnded));
                closeDown(false, true);
            }
        } else if ("b".equals(t)) {
            // Bestwerte samt `on` (#514): Das Handy erkennt mit gelernter
            // Halterung — die Karte zeigt ihr Zeichen am Rand.
            _bests = d;
            stats.bests = d;
            WatchUi.requestUpdate();
        } else if ("c".equals(t)) {
            // Ein Sprung, Wheelie oder Stoppie vom Handy, 3 s an der Stelle
            // der Frage (#514); eine Frage geht vor, der Hinweis verfällt.
            if (!ui.asking()) { ui.cue(d["k"], d["v"]); }
        } else if ("r".equals(t)) {
            routePart(d, id);
        }
        pace();
    }

    //! Ein Stück Route. Kommt eine Route an, ist sie neu — stürzt die App
    //! dabei ab, zählt es gegen sie ([CrashGuard]).
    hidden function routePart(d as Dictionary, rid as String?) as Void {
        if (rid != null) { CrashGuard.risk(rid); }
        var id = PhoneRoute.take(d);
        var err = PhoneRoute.lastError;
        if (err != null) {
            if (rid != null) {
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
            if (wait != 0 && rid != null && n instanceof Number) { waitForRoute(rid, n); }
            return;
        }
        // Die Antwort auf eine vollständige Route (Konzept 2): gespeichert.
        toPhone({"t" => "ok", "id" => id});
        if (id.equals(route.id) && route.isReady()) {
            CrashGuard.calm();
            return;
        }
        // Kurz am Handgelenk: Die neue Route ist da (#449, 2026-11-05).
        // Läuft schon eine Fahrt, fragt die Uhr erst (#501, Konzept 2):
        // Route ab deiner Position? Wer nichts tut, nimmt sie nach ASK_MS;
        // START nimmt sie gleich, ZURÜCK lässt sie liegen (#513). Beim Start, im Lader und in
        // der freien Fahrt nimmt sie still, im nächsten Takt.
        pendingId = id;
        _host.vibrate(false);
        if (asksBeforeSwap(wait, free, route.isReady())) {
            // Groß „START = JA" nur bei der ersten Frage nach dem Update
            // (#513: START lehnte bis 1.3.x ab), danach klein.
            var first = Application.Storage.getValue("askSeen") != true;
            if (first) { PhoneRoute.store("askSeen", true); }
            ui.askRoute(ASK_MS, first);
            swapAt = now + ASK_MS;
        } else {
            swapAt = now + 1;
        }
    }

    //! Die neue Route: GPS aus, die alte loslassen, die neue laden. Die
    //! alte geht zuerst — beide zugleich passten nicht in den Speicher
    //! (Messung 8.1). Die neue liest ihre Stücke einzeln aus dem Speicher.
    function swapRoute() as Void {
        swapAt = 0;
        if (pendingId == null) { return; }
        ev(70); // Stand: Routenwechsel
        pendingId = null;
        wait = 0;
        loading = false;
        _calmAt = 0;
        _host.gps(false, false);
        free = false;
        var p = placeholder();
        ui.forget(p);
        setRoute(p);
        loadStored();
    }

    //! Die Position des Handys als erster Fix (Betreiber 2026-11-05): Bis
    //! die Uhr eigenes GPS hat, zeigt sie damit Position, Weg zum Trail und
    //! zum Ziel statt Strichen. Kein Vibrieren (das Handy kann ein paar
    //! Sekunden alt sein), keine Zahlen der Fahrt; nichts wird gespeichert.
    hidden function phoneFix(la as Object?, lo as Object?) as Void {
        if (_ownFix || free || wait != 0 || !route.isReady() || !(la instanceof Number) || !(lo instanceof Number)) { return; }
        if (la < -9000000 || la > 9000000 || lo < -18000000 || lo > 18000000) { return; }
        var lat = la.toDouble() / 100000.0d;
        var lon = lo.toDouble() / 100000.0d;
        if (route.relative) { route.anchor(lat, lon); }
        var p = route.toLocal(lat, lon);
        var s = tracker.update(p[0], p[1], null, null, _host.compass());
        _phoneFixed = true;
        ui.setState(s, null, true);
    }

    //! Ein eigener Fix ([lat] null: keine Position). [t] Sekunden seit 1970
    //! für die Fahrt, [alt] vom Barometer oder GPS.
    function ownFix(lat as Double?, lon as Double, accuracy as Number, heading as Float?, speed as Float?,
            alt as Float?, hr as Number?, compass as Float?, t as Number) as Void {
        now = _host.now();
        if (closing || wait != 0 || !route.isReady()) { return; }
        // Die freie Fahrt fragt wieder nach einer Route ([HELLO_AGAIN_MS]).
        if (free && _hellos < HELLO_AGAIN_N && now - _helloAt >= HELLO_AGAIN_MS && _host.connected()) {
            _hellos++;
            sayHello();
        }
        if (lat == null || accuracy < Position.QUALITY_USABLE) {
            fixEv(0);
            return;
        }
        if (!_ownFix) {
            _ownFix = true;
            // „ich habe GPS" — seit #500 mit diesem Fix, damit das Handy Uhr
            // und eigene Position vergleichen kann. Nur im Speicher (A3).
            toPhone({"t" => "g", "la" => Math.round(lat * 100000.0), "lo" => Math.round(lon * 100000.0)});
        }
        // Die Fahrt (#484): jeder eigene Fix nach START, ob mit Route oder
        // ohne; vor START und in der Pause nimmt [RideLog.add] nichts.
        log.add(lat, lon, t, alt, accuracy);
        // In der freien Fahrt zählt die Uhr von selbst (ohne START), sonst
        // wie Garmin: nur während der Aufzeichnung.
        stats.counting = log.state() == RideLog.RECORDING || (free && log.state() == RideLog.IDLE);
        nudgeIdle(speed);
        if (free) {
            var f = log.toLocal(lat, lon);
            stats.update(f[0], f[1], now, speed, alt, hr, -1);
            ui.setFreeFix(f[0], f[1], heading, speed, compass);
            fixEv(3);
            return;
        }
        if (_phoneFixed) {
            _phoneFixed = false;
            tracker = new NavTracker(route);
        }
        if (route.relative) { route.anchor(lat, lon); }
        var p = route.toLocal(lat, lon);
        var s = tracker.update(p[0], p[1], heading, speed, compass);
        // Einmal beim Abkommen (Entscheidung 3) — kein Ton, nichts vor
        // Abzweigen.
        if (s.leftRoute) { _host.vibrate(true); }
        fixEv(s.offRoute ? 2 : 1);
        stats.update(p[0], p[1], now, speed, alt, hr, s.offRoute ? -1 : route.sectionAt(s.alongM));
        ui.setState(s, speed, false);
        // #500: Die Uhr meldet ihren Stand, wenn sie ihn braucht — jenseits
        // ihrer Sicht, und erst 300 m weiter als zuletzt (Konzept 2).
        var drift = tracker.driftM(ui.reachM());
        if (drift != null) {
            toPhone({"t" => "d", "la" => Math.round(lat * 100000.0), "lo" => Math.round(lon * 100000.0),
                "off" => Math.round(drift)});
        }
    }

    //! Schon in Fahrt, aber kein START: einmal kurz vibrieren, oben steht
    //! ohnehin „START: Aufnehmen".
    hidden function nudgeIdle(speed as Float?) as Void {
        if (_nudged || log.state() != RideLog.IDLE) { return; }
        _fast = speed != null && speed >= NUDGE_MPS ? _fast + 1 : 0;
        if (_fast < NUDGE_FIXES) { return; }
        _nudged = true;
        _host.vibrate(false);
        ui.toast(str(Rez.Strings.RecIdle));
    }
}
