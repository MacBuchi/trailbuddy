import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Test;

//! Der Ablauf der Uhr als Ereignis-Skripte (#508, Prüfleiter S2): Tasten,
//! Menüs, Fristen und Nachrichten gegen [WatchCore] mit einem erfundenen
//! Wirt. Die Uhr des Tests springt, statt zu warten. Alle Fixe liegen
//! erfunden am Äquator.

//! Der Wirt im Test: merkt sich, was der Ablauf tut.
(:test)
class FakeHost {
    var t as Number = 1000;
    var link as Boolean = false;
    var sent as Array<Dictionary>;
    var kinds as Array<Number>;
    var menus as Array<Symbol>;
    var buzz as Number = 0;
    var longBuzz as Number = 0;
    var exited as Boolean = false;
    var gpsOn as Boolean = false;
    var paceMs as Number = 0;
    //! Die Route ohne eine vom Handy; null = freie Fahrt (Store-Bau).
    var fallbackDict as Dictionary?;

    function initialize() {
        sent = [] as Array<Dictionary>;
        kinds = [] as Array<Number>;
        menus = [] as Array<Symbol>;
        fallbackDict = TestRoutes.straight();
    }

    function now() as Number { return t; }
    function pace(ms as Number) as Void { paceMs = ms; }
    function connected() as Boolean { return link; }
    function send(msg as Dictionary, kind as Number) as Void {
        sent.add(msg);
        kinds.add(kind);
    }
    function vibrate(long as Boolean) as Void {
        if (long) { longBuzz++; } else { buzz++; }
    }
    function menu(kind as Symbol) as Void { menus.add(kind); }
    function exit() as Void { exited = true; }
    function gps(on as Boolean, free as Boolean) as Void { gpsOn = on; }
    function fallback() as NavRoute? {
        var d = fallbackDict;
        return d == null ? null : NavRoute.fromDict(d);
    }
    function newView(c as WatchCore) as NavView { return new NavView(c.route, c.stats, c.log); }
    function compass() as Float? { return null; }

    //! Die Arten der gesendeten Nachrichten, zusammen: "hi,rs,rp".
    function types() as String {
        var s = "";
        for (var i = 0; i < sent.size(); i++) { s += (i > 0 ? "," : "") + sent[i]["t"]; }
        return s;
    }

    //! Die letzte gesendete Nachricht der Art [t].
    function last(t as String) as Dictionary? {
        for (var i = sent.size() - 1; i >= 0; i--) {
            if (t.equals(sent[i]["t"])) { return sent[i]; }
        }
        return null;
    }

    function lastMenu() as Symbol? {
        return menus.size() == 0 ? null : menus[menus.size() - 1];
    }
}

(:test)
module TestCore {
//! Ein frischer Ablauf mit leerem Speicher, gestartet.
function fresh(h as FakeHost) as WatchCore {
    TestRoutes.wipe();
    TestRoutes.wipeRides();
    var c = new WatchCore(h);
    c.start();
    return c;
}

//! Die Uhr um [ms] vorstellen, im Takt von 250 ms.
function run(c as WatchCore, h as FakeHost, ms as Number) as Void {
    for (var e = 0; e < ms; e += 250) {
        h.t += 250;
        c.tick();
    }
}

//! Ohne Handy gestartet, die Route ist geladen (wie nach dem Laden der
//! Testroute); danach ist das Handy da.
function loaded(h as FakeHost) as WatchCore {
    var c = fresh(h);
    run(c, h, 500);
    Test.assert(c.route.isReady() && !c.loading && c.wait == 0);
    h.link = true;
    return c;
}

//! Fix [i] einer erfundenen Fahrt nach Norden (55 m je Fix, alle 5 s).
function fix(c as WatchCore, h as FakeHost, i as Number) as Void {
    h.t += 5000;
    c.ownFix(i * 0.0005d, 0.001d, Position.QUALITY_GOOD, null, 5.0, 400.0 + i, null, null, 1000000 + i * 5);
}

function fixes(c as WatchCore, h as FakeHost, from as Number, to as Number) as Void {
    for (var i = from; i < to; i++) { fix(c, h, i); }
}

//! Eine neue Linie [id] vom Handy, ganz (zwei Stücke).
function newLine(c as WatchCore, id as String) as Void {
    var msgs = TestRoutes.parts(TestRoutes.v2(id, false, [0, 0, 0, 300, 0, 300, 0, 300], null, null, null), 2);
    for (var i = 0; i < msgs.size(); i++) { c.handle(msgs[i]); }
}

function done() as Void {
    TestRoutes.wipe();
    TestRoutes.wipeRides();
}
}

//! 489.1: START beginnt die Aufzeichnung, erst dann zählen die Zahlen; das
//! Handy hört `rs`.
(:test)
function coreStartBeginsRecording(logger as Logger) as Boolean {
    var h = new FakeHost();
    var c = TestCore.loaded(h);
    Test.assert(!c.stats.counting);
    TestCore.fixes(c, h, 0, 3);
    Test.assertEqual(c.log.state(), RideLog.IDLE);
    Test.assert(!c.stats.counting);
    c.startKey();
    Test.assertEqual(c.log.state(), RideLog.RECORDING);
    Test.assert(c.stats.counting);
    Test.assert(h.last("rs") != null);
    Test.assertEqual(h.buzz, 1);
    TestCore.done();
    return true;
}

//! 489.2: LAP vor dem ersten Fix setzt keine Marke und fragt nichts.
(:test)
function coreLapWaitsForGps(logger as Logger) as Boolean {
    var h = new FakeHost();
    var c = TestCore.loaded(h);
    c.startKey();
    c.backKey();
    Test.assert(!c.log.trailOpen());
    Test.assertEqual(h.menus.size(), 0);
    Test.assertEqual(h.buzz, 1); // nur START
    TestCore.done();
    return true;
}

//! 489.3 und 489.4: LAP markiert Beginn und Ende, dann das Menü; Behalten
//! lässt das Paar stehen und sagt es dem Handy (`rt`), Verwerfen nimmt
//! genau das letzte Paar.
(:test)
function coreLapMarksTrail(logger as Logger) as Boolean {
    var h = new FakeHost();
    var c = TestCore.loaded(h);
    c.startKey();
    TestCore.fixes(c, h, 0, 10);
    c.backKey();
    Test.assert(c.log.trailOpen());
    Test.assertEqual(h.menus.size(), 0);
    TestCore.fixes(c, h, 10, 20);
    c.backKey();
    Test.assert(!c.log.trailOpen());
    Test.assert(h.lastMenu() == :trail);
    c.trailChoice(false);
    Test.assert(c.log.lastTrail() == null);
    Test.assert(h.last("rt") == null);
    TestCore.fixes(c, h, 20, 30);
    c.backKey();
    TestCore.fixes(c, h, 30, 40);
    c.backKey();
    c.trailChoice(true);
    Test.assert(c.log.lastTrail() != null);
    Test.assert(h.last("rt") != null);
    TestCore.done();
    return true;
}

//! 489.5: START in der Aufzeichnung hält an und zeigt das Menü (`rp`);
//! Weiter zeichnet und zählt wieder (`rr`); ZURÜCK in der Pause zeigt das
//! Menü noch einmal, statt eine Marke zu setzen.
(:test)
function corePauseAndResume(logger as Logger) as Boolean {
    var h = new FakeHost();
    var c = TestCore.loaded(h);
    c.startKey();
    TestCore.fixes(c, h, 0, 5);
    c.startKey();
    Test.assertEqual(c.log.state(), RideLog.PAUSED);
    Test.assert(!c.stats.counting);
    Test.assert(h.lastMenu() == :pause);
    Test.assert(h.last("rp") != null);
    c.backKey();
    Test.assertEqual(h.menus.size(), 2);
    Test.assert(h.lastMenu() == :pause);
    Test.assert(!c.log.trailOpen());
    c.pauseChoice(:resume);
    Test.assertEqual(c.log.state(), RideLog.RECORDING);
    Test.assert(c.stats.counting);
    Test.assert(h.last("rr") != null);
    TestCore.done();
    return true;
}

//! 489.6: Verwerfen in der Pause fragt erst; Nein lässt die Fahrt
//! angehalten stehen, Ja verwirft sie — sie liegt nicht in der
//! Warteschlange, das Handy hört `re` mit k false.
(:test)
function corePauseDiscard(logger as Logger) as Boolean {
    var h = new FakeHost();
    var c = TestCore.loaded(h);
    c.startKey();
    TestCore.fixes(c, h, 0, 30);
    c.startKey();
    c.pauseChoice(:discard);
    Test.assert(h.lastMenu() == :discard);
    // „Fahrt verwerfen?" Nein: nichts geschieht.
    Test.assertEqual(c.log.state(), RideLog.PAUSED);
    Test.assert(!c.closing);
    Test.assertEqual(RideLog.queue().size(), 0);
    // Ja.
    c.discardRide();
    Test.assert(c.closing);
    Test.assertEqual(RideLog.queue().size(), 0);
    var re = h.last("re");
    Test.assert(re != null && re["k"] == false);
    TestCore.done();
    return true;
}

//! 489.6, Gegenstück: Speichern in der Pause legt die Fahrt in die
//! Warteschlange, und ohne Handy-Navigation geht sie gleich hinüber.
(:test)
function corePauseSave(logger as Logger) as Boolean {
    var h = new FakeHost();
    var c = TestCore.loaded(h);
    c.startKey();
    TestCore.fixes(c, h, 0, 30);
    c.startKey();
    c.pauseChoice(:save);
    Test.assert(c.closing);
    Test.assertEqual(RideLog.queue().size(), 1);
    var re = h.last("re");
    Test.assert(re != null && re["k"] == true);
    Test.assert(h.last("w") != null);
    TestCore.done();
    return true;
}

//! 501.1 und 501.4: Eine neue Linie während der Fahrt fragt; wer nichts
//! tut, nimmt sie nach ASK_MS, vorher bleibt die alte.
(:test)
function coreAsksThenTakesAfterDeadline(logger as Logger) as Boolean {
    var h = new FakeHost();
    var c = TestCore.loaded(h);
    TestCore.newLine(c, "neu");
    Test.assert("neu".equals(c.pendingId));
    Test.assert(c.ui.asking());
    Test.assertEqual(h.buzz, 1);
    Test.assert(h.last("ok") != null);
    TestCore.run(c, h, WatchCore.ASK_MS - 500);
    Test.assert("t".equals(c.route.id));
    while (c.pendingId != null) { TestCore.run(c, h, 250); }
    Test.assert("neu".equals(c.route.id));
    // Im Takt des Wechsels wird noch nicht dekodiert: Die alte Ansicht hält
    // bis zum nächsten die alte Route (sonst Out of Memory, 2026-11-11).
    Test.assert(c.loading && c.route.progress() == 0.0);
    TestCore.run(c, h, 500);
    Test.assert(c.route.isReady());
    Test.assert(h.gpsOn);
    TestCore.done();
    return true;
}

//! 513.1: START heißt bei der Frage ja (#513, E2) — die neue Linie kommt
//! gleich, nicht erst nach der Frist, und START beginnt dabei KEINE
//! Aufzeichnung.
(:test)
function coreStartTakesNewLine(logger as Logger) as Boolean {
    var h = new FakeHost();
    var c = TestCore.loaded(h);
    TestCore.newLine(c, "neu");
    Test.assert(c.asking());
    c.startKey();
    Test.assert(!c.asking() && !c.ui.asking());
    Test.assertEqual(c.log.state(), RideLog.IDLE);
    Test.assert(h.last("rs") == null);
    TestCore.run(c, h, 250);
    Test.assert("neu".equals(c.route.id));
    TestCore.run(c, h, 500);
    Test.assert(c.route.isReady());
    Test.assertEqual(c.log.state(), RideLog.IDLE);
    TestCore.done();
    return true;
}

//! 501.3: ZURÜCK heißt nein — die alte Linie bleibt, die neue liegt nicht
//! im Speicher, und es fragt nicht nach dem Beenden.
(:test)
function coreBackDeclinesNewLine(logger as Logger) as Boolean {
    var h = new FakeHost();
    var c = TestCore.loaded(h);
    TestCore.newLine(c, "neu");
    c.backKey();
    Test.assert(c.pendingId == null && c.swapAt == 0);
    Test.assert(PhoneRoute.currentId() == null);
    Test.assertEqual(h.menus.size(), 0);
    TestCore.run(c, h, WatchCore.ASK_MS + 1000);
    Test.assert("t".equals(c.route.id));
    Test.assertEqual(c.log.state(), RideLog.IDLE);
    TestCore.done();
    return true;
}

//! 513.2: Die erste Frage nach dem Update sagt groß „START = JA", die
//! nächste nicht mehr.
(:test)
function coreAskHintOnce(logger as Logger) as Boolean {
    var h = new FakeHost();
    var c = TestCore.loaded(h);
    Application.Storage.deleteValue("askSeen");
    TestCore.newLine(c, "neu");
    Test.assert(c.ui.askBig());
    c.backKey();
    TestCore.newLine(c, "neu2");
    Test.assert(c.asking());
    Test.assert(!c.ui.askBig());
    Application.Storage.deleteValue("askSeen");
    TestCore.done();
    return true;
}

//! 513.3: Langes HOCH öffnet das Aktionsmenü — nicht, solange eine Frage
//! steht (die Frage bleibt), und nicht im Lader.
(:test)
function coreMenuKeyOpensActions(logger as Logger) as Boolean {
    var h = new FakeHost();
    var c = TestCore.loaded(h);
    c.menuKey();
    Test.assert(h.lastMenu() == :action);
    TestCore.newLine(c, "neu");
    c.menuKey();
    Test.assertEqual(h.menus.size(), 1);
    Test.assert(c.asking());
    c.actionChoice(:zoom);
    Test.assert(h.lastMenu() == :zoom);
    c.actionChoice(2);
    Test.assertEqual(c.ui.zoomMode(), 2);
    Test.assertEqual(c.ui.zoom(), 2);
    c.actionChoice(NavView.ZOOM_AUTO);
    Test.assertEqual(c.ui.zoomMode(), NavView.ZOOM_AUTO);
    TestCore.done();
    return true;
}

//! 513.4: Im Aktionsmenü steht nur, was gerade geht: mit Route Zoom und
//! „Route beenden", in der freien Fahrt nur Zoom.
(:test)
function coreActionsOnlyWhatWorks(logger as Logger) as Boolean {
    var h = new FakeHost();
    var c = TestCore.loaded(h);
    var a = c.actions();
    Test.assertEqual(a.size(), 2);
    Test.assert(a[0] == :zoom && a[1] == :endRoute);
    h = new FakeHost();
    h.fallbackDict = null;
    c = TestCore.fresh(h);
    TestCore.run(c, h, 250);
    Test.assert(c.free);
    a = c.actions();
    Test.assertEqual(a.size(), 1);
    Test.assert(a[0] == :zoom);
    TestCore.done();
    return true;
}

//! 513.5: „Route beenden" — die Navigation endet (das Handy hört `e`, die
//! gespeicherte Route ist weg), die Aufzeichnung läuft weiter, die Uhr
//! fährt frei, und Strecke und Zeit bleiben.
(:test)
function coreEndRouteKeepsRecording(logger as Logger) as Boolean {
    var h = new FakeHost();
    var c = TestCore.loaded(h);
    TestCore.newLine(c, "neu");
    c.startKey();
    TestCore.run(c, h, 1000);
    Test.assert("neu".equals(c.route.id) && c.route.isReady());
    c.startKey();
    Test.assertEqual(c.log.state(), RideLog.RECORDING);
    TestCore.fixes(c, h, 0, 6);
    var km = c.stats.distanceM;
    Test.assert(km > 100.0);
    c.actionChoice(:endRoute);
    Test.assert(c.free && !c.closing);
    Test.assertEqual(c.log.state(), RideLog.RECORDING);
    var e = h.last("e");
    Test.assert(e != null && "neu".equals(e["id"]));
    Test.assert(h.last("re") == null);
    Test.assert(PhoneRoute.currentId() == null);
    Test.assert(h.gpsOn);
    Test.assertEqual(c.stats.distanceM, km);
    Test.assertEqual(c.actions().size(), 1);
    TestCore.fixes(c, h, 6, 9);
    Test.assert(c.stats.distanceM > km);
    Test.assert(!h.exited);
    TestCore.done();
    return true;
}

//! 501.11: Dieselbe Linie noch einmal — keine Frage, nichts bereit.
(:test)
function coreSameLineStaysQuiet(logger as Logger) as Boolean {
    var h = new FakeHost();
    var c = TestCore.loaded(h);
    var msgs = TestRoutes.parts(TestRoutes.straight(), 2);
    for (var i = 0; i < msgs.size(); i++) { c.handle(msgs[i]); }
    Test.assert(h.last("ok") != null);
    Test.assert(c.pendingId == null && c.swapAt == 0);
    Test.assert(!c.ui.asking());
    Test.assertEqual(h.buzz, 0);
    TestCore.done();
    return true;
}

//! 484.22: Ohne Route die freie Fahrt — Spur und Zahlen laufen ohne START,
//! gespeichert wird nichts. Eine Linie vom Handy nimmt sie still (#502).
(:test)
function coreFreeRide(logger as Logger) as Boolean {
    var h = new FakeHost();
    h.fallbackDict = null;
    var c = TestCore.fresh(h);
    TestCore.run(c, h, 250);
    Test.assert(c.free && h.gpsOn);
    TestCore.fixes(c, h, 0, 6);
    Test.assertEqual(c.log.trackCount, 6);
    Test.assert(c.stats.counting);
    Test.assertEqual(c.log.state(), RideLog.IDLE);
    Test.assertEqual(RideLog.queue().size(), 0);
    h.link = true;
    TestCore.newLine(c, "nah-1");
    Test.assert(!c.ui.asking());
    TestCore.run(c, h, 500);
    Test.assert("nah-1".equals(c.route.id));
    Test.assert(!c.free);
    TestCore.done();
    return true;
}

//! Mit Handy wartet der Start auf dessen Antwort; ohne Antwort in
//! ANSWER_MS lädt er die gespeicherte Route.
(:test)
function coreNoAnswerLoadsStored(logger as Logger) as Boolean {
    var h = new FakeHost();
    TestRoutes.wipe();
    TestRoutes.wipeRides();
    var msgs = TestRoutes.parts(TestRoutes.v2("alt", false, [0, 0, 0, 300, 0, 300], null, null, null), 2);
    for (var i = 0; i < msgs.size(); i++) { PhoneRoute.take(msgs[i]); }
    Test.assert("alt".equals(PhoneRoute.currentId()));
    h.link = true;
    var c = new WatchCore(h);
    c.start();
    Test.assertEqual(c.wait, WatchCore.WAIT_ANSWER);
    Test.assert(h.last("hi") != null && "alt".equals(h.last("hi")["id"]));
    TestCore.run(c, h, WatchCore.ANSWER_MS - 500);
    Test.assertEqual(c.wait, WatchCore.WAIT_ANSWER);
    TestCore.run(c, h, 1000);
    Test.assertEqual(c.wait, 0);
    Test.assert("alt".equals(c.route.id));
    TestCore.run(c, h, 500);
    Test.assert(c.route.isReady());
    TestCore.done();
    return true;
}

//! Ohne Handy kein Lader: Die gespeicherte Route lädt gleich (F2).
(:test)
function coreWithoutPhoneLoadsStored(logger as Logger) as Boolean {
    var h = new FakeHost();
    TestRoutes.wipe();
    TestRoutes.wipeRides();
    var msgs = TestRoutes.parts(TestRoutes.v2("alt", false, [0, 0, 0, 300, 0, 300], null, null, null), 2);
    for (var i = 0; i < msgs.size(); i++) { PhoneRoute.take(msgs[i]); }
    var c = new WatchCore(h);
    c.start();
    Test.assertEqual(c.wait, 0);
    Test.assert("alt".equals(c.route.id));
    Test.assert(h.sent.size() == 0);
    TestCore.run(c, h, 500);
    Test.assert(c.route.isReady() && h.gpsOn);
    TestCore.done();
    return true;
}

//! `n` (eine Route kommt) verlängert das Warten auf INCOMING_MS; kommt
//! kein Stück, gilt danach die gespeicherte. `k` lädt sie sofort.
(:test)
function coreAnnouncedRouteTimesOut(logger as Logger) as Boolean {
    var h = new FakeHost();
    h.link = true;
    var c = TestCore.fresh(h);
    c.handle({"t" => "n", "id" => "kommt", "np" => 2});
    Test.assertEqual(c.wait, WatchCore.WAIT_ROUTE);
    TestCore.run(c, h, WatchCore.INCOMING_MS - 500);
    Test.assertEqual(c.wait, WatchCore.WAIT_ROUTE);
    TestCore.run(c, h, 1000);
    Test.assertEqual(c.wait, 0);
    Test.assert("t".equals(c.route.id));
    // `k` beim Start: sofort die gespeicherte.
    var h2 = new FakeHost();
    h2.link = true;
    var c2 = TestCore.fresh(h2);
    c2.handle({"t" => "k"});
    Test.assertEqual(c2.wait, 0);
    Test.assert(c2.loading);
    TestCore.done();
    return true;
}

//! Die Fahrt beim Beenden: Garmin Connect nimmt die Nachricht ab, aber
//! das `wk` des Handys bleibt aus — nach RIDE_WAIT_MS geht die App zu, die
//! Fahrt wartet. Mit `wk` ist sie weg.
(:test)
function coreRideUploadWaitsForAck(logger as Logger) as Boolean {
    var h = new FakeHost();
    var c = TestCore.loaded(h);
    c.startKey();
    TestCore.fixes(c, h, 0, 30);
    c.quit();
    Test.assertEqual(RideLog.queue().size(), 1);
    Test.assert(h.kinds[h.kinds.size() - 1] == WatchCore.SEND_RIDE);
    c.rideSent(true);
    TestCore.run(c, h, WatchCore.RIDE_WAIT_MS - 500);
    Test.assert(!h.exited);
    TestCore.run(c, h, 1000);
    Test.assert(h.exited);
    Test.assertEqual(RideLog.queue().size(), 1);
    // Ein später `wk` löscht sie.
    c.handle({"t" => "wk", "id" => RideLog.queuedIds()[0]});
    Test.assertEqual(RideLog.queue().size(), 0);
    TestCore.done();
    return true;
}

//! `e` vom Handy für eine fremde Kennung ändert nichts; für die eigene
//! Route endet die App.
(:test)
function coreEndOnlyForOwnRoute(logger as Logger) as Boolean {
    var h = new FakeHost();
    var c = TestCore.loaded(h);
    c.handle({"t" => "e", "id" => "fremd"});
    Test.assert(!c.closing);
    c.handle({"t" => "e", "id" => "t"});
    Test.assert(c.closing);
    TestCore.done();
    return true;
}

//! Der Spieler des Gesprächskatalogs (#509, Prüfleiter S3): spielt die
//! Seite der Uhr eines Gesprächs aus `docs/watch_cases.json` gegen den
//! Ablaufkern. Die Gespräche stehen erzeugt in GeneratedTalks.mc
//! (`tool/watch_talks.py`); die Form in `gespraeche_form` der Falldatei.
//! Schritt der Uhr: Handlung [act], dann muss die Nachricht unter dem
//! stehen, was die Uhr seit dem letzten Treffer schickte. Schritt des
//! Handys: Die Nachricht kommt an ([deliver]), außer sie ging verloren.
(:test)
module TestTalk {
var _h as FakeHost?;
var _c as WatchCore?;
var _vars as Dictionary = {};
var _np as Dictionary = {};
var _cursor as Number = 0;
var _where as String = "";

function play(id as String, setup as Array<String>, steps as Array<Dictionary>) as Boolean {
    TestRoutes.wipe();
    TestRoutes.wipeRides();
    _vars = {};
    _np = {};
    _cursor = 0;
    _where = id;
    var h = new FakeHost();
    _h = h;
    // Erst was vor dem Start im Speicher liegt, dann die Uhr.
    if (inList(setup, "fahrt")) {
        var log = new RideLog();
        log.start();
        TestRoutes.ride(log, 1700000000, 30, 5);
        log.finish();
    }
    if (inList(setup, "ohne_route")) { h.fallbackDict = null; }
    if (inList(setup, "geladen")) {
        var c = new WatchCore(h);
        c.start();
        TestCore.run(c, h, 500);
        Test.assertMessage(c.route.isReady() && c.wait == 0, id + ": die Testroute lud nicht");
        h.link = true;
        _c = c;
    } else {
        h.link = inList(setup, "handy");
        _c = new WatchCore(h);
    }
    for (var i = 0; i < setup.size(); i++) {
        var s = setup[i];
        if (s.find("bad:") == 0) { Application.Storage.setValue("bad", value(s.substring(4, s.length()))); }
    }
    for (var n = 0; n < steps.size(); n++) {
        _where = id + " Schritt " + (n + 1);
        step(steps[n]);
    }
    TestCore.done();
    return true;
}

function inList(a as Array<String>, s as String) as Boolean {
    for (var i = 0; i < a.size(); i++) {
        if (s.equals(a[i])) { return true; }
    }
    return false;
}

function step(s as Dictionary) as Void {
    var h = _h as FakeHost;
    var msg = s["msg"] as Dictionary?;
    var wait = s["nach_ms"] instanceof Number ? s["nach_ms"] as Number : 0;
    if ("uhr".equals(s["von"])) {
        var before = h.sent.size();
        if (s["tu"] != null) { act(s); }
        if (msg != null) { expectSent(msg, s["gleich"] as Array?); }
        run(wait);
        if (s["still"] == true) { Test.assertMessage(h.sent.size() == before, _where + ": die Uhr sollte still sein"); }
    } else {
        if (msg != null && s["verloren"] != true && s["still"] != true) { deliver(msg); }
        run(wait);
    }
    var dann = s["dann"] as Array?;
    if (dann != null) {
        for (var i = 0; i < dann.size(); i++) { check(dann[i] as String); }
    }
}

//! Die Uhr um [ms] vorstellen, im Takt, den der Kern beim Wirt verlangt
//! (50 ms beim Laden und Warten, 250 ms für eine Frist, sonst keiner) —
//! wie auf der Uhr. Feste 250 ms ließen eine Route länger halb geladen.
function run(ms as Number) as Void {
    var h = _h as FakeHost;
    var end = h.t + ms;
    while (end - h.t > 0) {
        var p = h.paceMs;
        if (p <= 0) {
            h.t = end;
            return;
        }
        h.t += end - h.t < p ? end - h.t : p;
        (_c as WatchCore).tick();
    }
}

//! Eine Handlung an der Uhr (Kennungen aus `tool/watch_talks.py`).
function act(s as Dictionary) as Void {
    var h = _h as FakeHost;
    var c = _c as WatchCore;
    var tu = s["tu"] as String;
    if ("start".equals(tu)) {
        c.start();
    } else if ("restart".equals(tu)) {
        c.stop();
        c = new WatchCore(h);
        _c = c;
        c.start();
    } else if ("startKey".equals(tu)) {
        c.startKey();
    } else if ("back".equals(tu)) {
        c.backKey();
    } else if ("resume".equals(tu)) {
        c.pauseChoice(:resume);
    } else if ("save".equals(tu)) {
        c.pauseChoice(:save);
    } else if ("discard".equals(tu)) {
        c.pauseChoice(:discard);
    } else if ("discardYes".equals(tu)) {
        c.discardRide();
    } else if ("keep".equals(tu)) {
        c.trailChoice(true);
    } else if ("quit".equals(tu)) {
        c.quit();
    } else if ("endRoute".equals(tu)) {
        c.actionChoice(:endRoute);
    } else if ("fixes".equals(tu)) {
        TestCore.fixes(c, h, s["fa"] as Number, s["fb"] as Number);
    } else {
        Test.assertMessage(false, _where + ": unbekannte Handlung " + tu);
    }
}

//! `$name`: was eine Seite festlegte, ungebunden der Name selbst.
function value(v as Object?) as Object? {
    if (v instanceof String && v.find("$") == 0) {
        var name = v.substring(1, v.length());
        var bound = _vars[name];
        return bound != null ? bound : name;
    }
    if (v instanceof Array) {
        var out = [] as Array;
        for (var i = 0; i < v.size(); i++) { out.add(value(v[i])); }
        return out;
    }
    return v;
}

function same(a as Object?, b as Object?) as Boolean {
    if (a == null || b == null) { return a == b; }
    if (a instanceof String) { return a.equals(b); }
    return a == b;
}

//! Passen die gebundenen Platzhalter von [want] zu [got]?
function fits(want as Dictionary, got as Dictionary) as Boolean {
    var keys = want.keys();
    for (var i = 0; i < keys.size(); i++) {
        var v = want[keys[i]];
        if (v instanceof String && v.find("$") == 0) {
            var bound = _vars[v.substring(1, v.length())];
            if (bound != null && !same(bound, got[keys[i]])) { return false; }
        }
    }
    return true;
}

//! Die Platzhalter von [want] an die Werte der gesendeten Nachricht binden
//! (auch der erste einer Liste, `rq`).
function bind(want as Dictionary, got as Dictionary) as Void {
    var keys = want.keys();
    for (var i = 0; i < keys.size(); i++) {
        var v = want[keys[i]];
        var g = got[keys[i]];
        if (v instanceof Array && v.size() > 0 && g instanceof Array && g.size() > 0) {
            v = v[0];
            g = g[0];
        }
        if (v instanceof String && v.find("$") == 0 && g != null) {
            var name = v.substring(1, v.length());
            if (_vars[name] == null) { _vars[name] = g; }
        }
    }
}

//! Die Uhr muss [want] gesendet haben — gesucht ab dem letzten Treffer.
function expectSent(want as Dictionary, gleich as Array?) as Void {
    var h = _h as FakeHost;
    var t = want["t"] as String;
    for (var i = _cursor; i < h.sent.size(); i++) {
        var got = h.sent[i];
        if (!t.equals(got["t"]) || !fits(want, got)) { continue; }
        var keys = want.keys();
        for (var k = 0; k < keys.size(); k++) {
            Test.assertMessage(got.hasKey(keys[k]), _where + ": `" + t + "` ohne Schlüssel `" + keys[k] + "`");
        }
        if (gleich != null) {
            for (var k = 0; k < gleich.size(); k++) {
                var key = gleich[k];
                Test.assertMessage(same(got[key], want[key]), _where + ": `" + t + "." + key + "` ist " + got[key]);
            }
        }
        bind(want, got);
        _cursor = i + 1;
        return;
    }
    var c = _c as WatchCore;
    Test.assertMessage(false, _where + ": die Uhr sendete kein `" + t + "` " + want + " — gesendet: " + h.types()
        + ", zuletzt " + h.last(t) + "; Kern: route " + c.route.id + " bereit " + c.route.isReady()
        + " wait " + c.wait + " frei " + c.free + " zu " + c.closing);
}

//! Eine Nachricht des Handys kommt an. `r` heißt: die ganze Route in den
//! Stücken, die das `n` davor ankündigte (sonst zwei); die übrigen
//! Schlüssel des Schritts (`v`) gelten für jedes Stück.
function deliver(want as Dictionary) as Void {
    var c = _c as WatchCore;
    var m = {} as Dictionary;
    var keys = want.keys();
    for (var i = 0; i < keys.size(); i++) { m[keys[i]] = value(want[keys[i]]); }
    bind(want, m);
    var t = m["t"] as String;
    if ("n".equals(t) && m["id"] != null) { _np[m["id"]] = m["np"]; }
    if (!"r".equals(t)) {
        c.handle(m);
        return;
    }
    var id = m["id"] as String;
    var np = _np[id] instanceof Number && (_np[id] as Number) > 0 ? _np[id] as Number : 2;
    var parts = TestRoutes.parts(TestRoutes.v2(id, false, [0, 0, 0, 300, 0, 300, 0, 300], null, null, null), (4 + np - 1) / np);
    for (var p = 0; p < parts.size(); p++) {
        var part = parts[p];
        for (var i = 0; i < keys.size(); i++) {
            var k = keys[i];
            if (!"t".equals(k) && !"id".equals(k)) { part[k] = m[k]; }
        }
        c.handle(part);
    }
}

//! Ein Stand der Uhr (`gespraeche_form.staende_uhr`).
function check(st as String) as Void {
    var c = _c as WatchCore;
    var ok;
    if (st.find("route:") == 0) {
        var id = value(st.substring(6, st.length()));
        ok = same(c.route.id, id);
        st += " (ist " + c.route.id + ")";
    } else if ("wartet".equals(st)) {
        ok = c.wait == WatchCore.WAIT_ANSWER;
    } else if ("route_kommt".equals(st)) {
        ok = c.wait == WatchCore.WAIT_ROUTE;
    } else if ("frei".equals(st)) {
        ok = c.free;
    } else if ("fragt".equals(st)) {
        ok = c.ui.asking();
    } else if ("nimmt_auf".equals(st)) {
        ok = c.log.state() == RideLog.RECORDING;
    } else if ("pause".equals(st)) {
        ok = c.log.state() == RideLog.PAUSED;
    } else if ("zu".equals(st)) {
        ok = c.closing;
    } else if ("keine_fahrt".equals(st)) {
        ok = RideLog.queue().size() == 0;
    } else if ("fahrt_wartet".equals(st)) {
        ok = RideLog.queue().size() > 0;
    } else if ("bestwerte".equals(st)) {
        ok = c.stats.bests != null;
    } else {
        ok = false;
        st = "unbekannt: " + st;
    }
    Test.assertMessage(ok, _where + ": Stand der Uhr " + st);
}
}
