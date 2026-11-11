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

//! 501.3: START lehnt die neue Linie ab — die alte bleibt, die neue liegt
//! nicht im Speicher, und START beginnt dabei KEINE Aufzeichnung. ZURÜCK
//! genauso, ohne nach dem Beenden zu fragen.
(:test)
function coreDeclinesNewLine(logger as Logger) as Boolean {
    var h = new FakeHost();
    var c = TestCore.loaded(h);
    TestCore.newLine(c, "neu");
    c.startKey();
    Test.assert(c.pendingId == null && c.swapAt == 0);
    Test.assert(PhoneRoute.currentId() == null);
    Test.assertEqual(c.log.state(), RideLog.IDLE);
    TestCore.run(c, h, WatchCore.ASK_MS + 1000);
    Test.assert("t".equals(c.route.id));
    TestCore.newLine(c, "neu2");
    c.backKey();
    Test.assert(c.pendingId == null);
    Test.assertEqual(h.menus.size(), 0);
    TestCore.run(c, h, WatchCore.ASK_MS + 1000);
    Test.assert("t".equals(c.route.id));
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
