import Toybox.Application;
import Toybox.Lang;
import Toybox.Test;
import Toybox.WatchUi;

//! Unit-Tests der Uhr-Seite (Konzept-Garmin 6): Dekodierung und die
//! Regeln der Folgeansicht. `tool/garmin_build.sh --test` fährt sie im
//! Simulator. Alle Routen hier sind erfunden und liegen am Äquator.

//! Die Testrouten — ein Modul, damit der Runner sie nicht für Tests hält.
(:test)
module TestRoutes {
//! Eine Route in der Form von `route.json` (Protokoll 2) aus lesbaren
//! Zahlen: [pts] = [lat0, lon0, dLat1, dLon1, …], [ele] je Punkt in Metern,
//! [br] = [Punkt, dLat, dLon, …] — gepackt wie `WatchRoute.toJson`.
function v2(id as String, rel as Boolean, pts as Array<Number>, ele as Array<Number>?,
        sec as Array?, br as Array<Number>?) as Dictionary {
    var np = pts.size() / 2;
    var packed = [0] as Array<Number>;
    for (var i = 1; i < np; i++) { packed.add(PhoneRoute.pack(pts[2 * i], pts[2 * i + 1])); }
    var d = {"v" => PhoneRoute.PROTOCOL, "id" => id, "rel" => rel, "np" => np,
        "o" => [pts[0], pts[1]], "pts" => packed} as Dictionary;
    if (ele != null) {
        d["e0"] = ele[0];
        var pe = [] as Array<Number>;
        for (var i = 0; i < np; i += 2) {
            var a = i == 0 ? 0 : ele[i] - ele[i - 1];
            var b = i + 1 < np ? ele[i + 1] - ele[i] : 0;
            pe.add(PhoneRoute.pack(a, b));
        }
        d["ele"] = pe;
    }
    if (sec != null) { d["sec"] = sec; }
    if (br != null) {
        var pb = [] as Array<Number>;
        for (var k = 0; k + 2 < br.size(); k += 3) { pb.add(br[k]); pb.add(PhoneRoute.pack(br[k + 1], br[k + 2])); }
        d["br"] = pb;
    }
    return d;
}

//! [d] (ein Stück) in Nachrichten zu je [k] Punkten (gerade), wie
//! `WatchRoute.parts`: Kopf im ersten, Stummel mit ihrem Punkt.
function parts(d as Dictionary, k as Number) as Array<Dictionary> {
    var np = d["np"] as Number;
    var n = (np + k - 1) / k;
    var out = [] as Array<Dictionary>;
    for (var p = 0; p < n; p++) {
        var a = p * k;
        var b = a + k < np ? a + k : np;
        var m = {"t" => "r", "id" => d["id"], "p" => p, "n" => n,
            "pts" => (d["pts"] as Array).slice(a, b)} as Dictionary;
        var ele = d["ele"] as Array?;
        if (ele != null) { m["ele"] = ele.slice(a / 2, (b + 1) / 2); }
        var br = d["br"] as Array<Number>?;
        if (br != null) {
            var mine = [] as Array<Number>;
            for (var i = 0; i + 1 < br.size(); i += 2) {
                if (br[i] >= a && br[i] < b) { mine.add(br[i]); mine.add(br[i + 1]); }
            }
            if (mine.size() > 0) { m["br"] = mine; }
        }
        if (p == 0) {
            m["v"] = d["v"];
            m["np"] = np;
            m["o"] = d["o"];
            if (d["e0"] != null) { m["e0"] = d["e0"]; }
            if (d["sec"] != null) { m["sec"] = d["sec"]; }
        }
        out.add(m);
    }
    return out;
}

//! Gerade nach Osten, 900e-5° ≈ 1000,8 m, ein Trail.
function straight() as Dictionary {
    return v2("t", false, [0, 0, 0, 300, 0, 300, 0, 300], [500, 520, 505, 540],
        [[1, 2, 2, "Testtrail"]], [1, 30, 0, 9, 1, 1]);
}

function straightRoute() as NavRoute {
    return NavRoute.decoded(straight());
}

//! Hin und zurück auf derselben Linie: 1 km nach Osten, dann zurück.
function outAndBack() as NavRoute {
    return NavRoute.decoded(v2("oab", false, [0, 0, 0, 450, 0, 450, 0, -450, 0, -450], null, null, null));
}

//! Den Speicher der Uhr für einen Test leeren.
//! Die Fahrten der Tests aus dem Speicher (#484).
function wipeRides() as Void {
    var q = RideLog.queue();
    for (var i = 0; i < q.size(); i++) { RideLog.drop(q[i][0] as String, q[i][1] as Number); }
    var wo = Application.Storage.getValue("wo");
    if (wo instanceof Array && wo.size() == 3 && wo[0] instanceof String && wo[1] instanceof Number) {
        RideLog.drop(wo[0] as String, (wo[1] as Number) + 1);
    }
    Application.Storage.deleteValue("rq");
    Application.Storage.deleteValue("wo");
}

//! [n] Fixe am Äquator (erfunden), alle [dt] s, je 0,0005° nach Norden
//! (55 m), Höhe steigt um 0,5 m, Qualität GOOD. Liefert, wie viele in
//! die Fahrt gingen.
function ride(log as RideLog, t0 as Number, n as Number, dt as Number) as Number {
    var k = 0;
    for (var i = 0; i < n; i++) {
        if (log.add(i * 0.0005d, 0.001d, t0 + i * dt, 400.0 + i * 0.5, 4)) { k++; }
    }
    return k;
}

function wipe() as Void {
    PhoneRoute.drop();
    PhoneRoute.clear("a");
    PhoneRoute.clear("b");
    var keys = ["risk", "bad", "crashId", "crashN", "loading"] as Array<String>;
    for (var i = 0; i < keys.size(); i++) { Application.Storage.deleteValue(keys[i]); }
}
}

(:test)
function decodeRoute(logger as Logger) as Boolean {
    var r = TestRoutes.straightRoute();
    Test.assertEqual(r.size(), 4);
    Test.assert(r.lengthM > 1000.0 && r.lengthM < 1001.5);
    Test.assert(r.cum[1] > 333.0 && r.cum[1] < 334.0);
    Test.assert(!r.isLoop);
    Test.assert(TestRoutes.outAndBack().isLoop);
    Test.assertEqual(r.secName[0], "Testtrail");
    Test.assertEqual(r.sectionAt(400.0), 0);
    Test.assertEqual(r.sectionAt(100.0), -1);
    // Ein Stummel 30e-5° nach Norden am zweiten Punkt; der mit Punkt 9
    // liegt außerhalb und fällt weg.
    Test.assertEqual(r.brAt.size(), 1);
    Test.assertEqual(r.brAt[0], 1);
    Test.assert(r.brY[0] > 33.0 && r.brY[0] < 34.0);
    Test.assert(r.brX[0] > 333.0 && r.brX[0] < 334.0);
    return true;
}

(:test)
function climbHysteresis(logger as Logger) as Boolean {
    // 500 → 520 → 505 → 540: 20 + 35 = 55 hm; ab 700 m (nach dem
    // dritten Punkt) nur noch 35.
    var r = TestRoutes.straightRoute();
    var all = r.climbLeft(0.0) as Float;
    Test.assert(all > 54.9 && all < 55.1);
    var late = r.climbLeft(700.0) as Float;
    Test.assert(late > 34.9 && late < 35.1);
    Test.assert(TestRoutes.outAndBack().climbLeft(0.0) == null);
    return true;
}

(:test)
function offRouteNeedsTwoFixes(logger as Logger) as Boolean {
    var t = new NavTracker(TestRoutes.straightRoute());
    var s = t.update(100.0, 0.0, null, 0.0, null);
    Test.assert(!s.offRoute);
    s = t.update(110.0, 40.0, null, 0.0, null);
    Test.assert(!s.offRoute);
    s = t.update(120.0, 40.0, null, 0.0, null);
    Test.assert(s.offRoute);
    Test.assert(s.offM > 39.0 && s.offM < 41.0);
    s = t.update(130.0, 10.0, null, 0.0, null);
    Test.assert(!s.offRoute);
    return true;
}

(:test)
function vibratesOncePerDeparture(logger as Logger) as Boolean {
    var t = new NavTracker(TestRoutes.straightRoute());
    var count = 0;
    var ys = [0.0, 40.0, 45.0, 50.0, 60.0, 0.0, 50.0, 50.0, 50.0] as Array<Float>;
    for (var i = 0; i < ys.size(); i++) {
        if (t.update(100.0 + i * 10, ys[i], null, 0.0, null).leftRoute) {
            count++;
        }
    }
    // Einmal beim ersten Abkommen, einmal nach dem Zurückkommen — nicht
    // bei jedem Fix abseits.
    Test.assertEqual(count, 2);
    return true;
}

(:test)
function arrivesAtEnd(logger as Logger) as Boolean {
    var t = new NavTracker(TestRoutes.straightRoute());
    Test.assert(!t.update(500.0, 0.0, null, 0.0, null).arrived);
    Test.assert(t.update(980.0, 5.0, null, 0.0, null).arrived);
    // Angekommen bleibt — auch wenn man danach weiterrollt.
    var s = t.update(1100.0, 80.0, null, 0.0, null);
    s = t.update(1150.0, 80.0, null, 0.0, null);
    Test.assert(s.arrived);
    Test.assert(!s.leftRoute);
    return true;
}

(:test)
function loopArrivesOnlyOnLastHalf(logger as Logger) as Boolean {
    var t = new NavTracker(TestRoutes.outAndBack());
    // Am Start einer Runde ist man nicht angekommen …
    Test.assert(!t.update(5.0, 0.0, null, 0.0, null).arrived);
    // … und der Stand springt am Wendepunkt nicht auf die Rückfahrt.
    var s = t.update(300.0, 0.0, null, 0.0, null);
    Test.assert(s.alongM < 400.0);
    s = t.update(700.0, 0.0, null, 0.0, null);
    s = t.update(1000.0, 0.0, null, 0.0, null);
    s = t.update(600.0, 0.0, null, 0.0, null);
    Test.assert(s.alongM > 1300.0);
    s = t.update(300.0, 0.0, null, 0.0, null);
    s = t.update(20.0, 0.0, null, 0.0, null);
    Test.assert(s.arrived);
    return true;
}

(:test)
function headingSources(logger as Logger) as Boolean {
    var t = new NavTracker(TestRoutes.straightRoute());
    // Ohne alles: die Richtung der Linie (Osten = π/2).
    var s = t.update(100.0, 0.0, null, 0.0, null);
    Test.assert(s.heading > 1.56 && s.heading < 1.58);
    // Im Stand der Kompass.
    s = t.update(100.0, 0.0, 1.0, 0.5, 0.3);
    Test.assert(s.heading > 0.29 && s.heading < 0.31);
    // In Fahrt der GPS-Kurs.
    s = t.update(110.0, 0.0, 1.2, 5.0, 0.3);
    Test.assert(s.heading > 1.19 && s.heading < 1.21);
    // Danach im Stand ohne Kompass der letzte Kurs.
    s = t.update(110.0, 0.0, null, 0.0, null);
    Test.assert(s.heading > 1.19 && s.heading < 1.21);
    return true;
}

//! Eine lange Linie mit Knick: Die blockweise Suche findet denselben
//! Fußpunkt wie die einfache, auch über Blockgrenzen und weit abseits.
(:test)
function blockSearchFindsNearest(logger as Logger) as Boolean {
    var pts = [0, 0] as Array<Number>;
    for (var i = 0; i < 200; i++) { pts.add(0); pts.add(9); }   // 200 × 10 m nach Osten
    for (var i = 0; i < 200; i++) { pts.add(9); pts.add(0); }   // 200 × 10 m nach Norden
    var r = NavRoute.decoded(TestRoutes.v2("long", false, pts, null, null, null));
    Test.assertEqual(r.blockCount(), 13);
    var t = new NavTracker(r);
    // 100 m neben dem zweiten Schenkel, Stand davor: Fußpunkt bei
    // ~2000 + 1500 m.
    var p = t.progress(2100.0, 1500.0, 3000.0);
    Test.assert(p[1] > 98.0 && p[1] < 102.0);
    Test.assert(p[0] > 3490.0 && p[0] < 3510.0);
    // 50 m neben dem ERSTEN Schenkel, weit hinter dem Fenster: Der Abstand
    // kommt aus der ganzen Linie (über viele Blöcke), der Stand springt
    // nicht zurück.
    p = t.progress(1000.0, 50.0, 3000.0);
    Test.assert(p[1] > 49.0 && p[1] < 51.0);
    Test.assert(p[0] > 2900.0);
    return true;
}

(:test)
function relativeRouteAnchors(logger as Logger) as Boolean {
    var r = NavRoute.decoded(TestRoutes.v2("rel", true, [0, 0, 0, 900], null, null, null));
    Test.assert(r.relative);
    r.anchor(10.0d, 20.0d);
    Test.assert(!r.relative);
    var p = r.toLocal(10.0d, 20.0d);
    Test.assert(p[0] == 0.0 && p[1] == 0.0);
    // Die Form bleibt in Metern: 1 km nach Osten bleibt 1 km.
    Test.assert(r.lengthM > 1000.0 && r.lengthM < 1001.5);
    return true;
}

//! Weiter abseits, als die Karte zeigen kann, passt die ganze Linie in den
//! Kreis (#498). Gegenprobe: den weitesten Zoom auf 1,0 m/px setzen, dann
//! ist die Schwelle 135 m und der Test fällt.
(:test)
function farLineFitsTheView(logger as Logger) as Boolean {
    var reach = NavView.ZOOM_MPP[2] * 135.0;
    Test.assert(reach > 500.0 && reach < 600.0);
    Test.assert(NavView.beyondView(12000.0, reach));
    Test.assert(!NavView.beyondView(400.0, reach));
    return true;
}

(:test)
function rideStatsCountsOnlyWhileMoving(logger as Logger) as Boolean {
    var st = new RideStats(2);
    // Stehen mit GPS-Zittern zählt nicht; dann 10 s lang 10 m je Sekunde.
    st.update(0.0, 0.0, 0, 0.2, null, null, -1);
    st.update(3.0, 0.0, 1000, 0.3, null, null, -1);
    for (var i = 1; i <= 10; i++) {
        st.update(3.0 + 10 * i, 0.0, 1000 + 1000 * i, 10.0, null, 140, 1);
    }
    Test.assert(st.distanceM > 99.0 && st.distanceM < 101.0);
    Test.assert(st.movingS > 9.9 && st.movingS < 10.1);
    // Ein Sprung über 100 m (GPS wacht auf) zählt nicht.
    st.update(1000.0, 0.0, 12000, 10.0, null, 141, -1);
    Test.assert(st.distanceM < 101.0);
    Test.assertEqual(st.heartRate, 141);
    Test.assert(!st.ridden[0] && st.ridden[1]);
    Test.assertEqual(st.riddenCount(), 1);
    return true;
}

(:test)
function rideStatsClimbAndGrade(logger as Logger) as Boolean {
    var st = new RideStats(0);
    // 100 m mit 8 % Steigung in Schritten zu 5 m, dann 2 m Rauschen.
    for (var i = 0; i <= 20; i++) {
        st.update(5.0 * i, 0.0, 1000 * i, 5.0, 500.0 + 0.4 * i, null, -1);
    }
    Test.assert(st.climbM > 5.9 && st.climbM <= 8.0);
    Test.assertEqual(st.grade(), 8);
    var before = st.climbM;
    st.update(105.0, 0.0, 21000, 5.0, 506.0, null, -1);
    st.update(110.0, 0.0, 22000, 5.0, 508.0, null, -1);
    Test.assertEqual(st.climbM, before); // unter der Hysterese von 3 m
    // Zu kurz für eine Steigung: null.
    var fresh = new RideStats(0);
    fresh.update(0.0, 0.0, 0, 5.0, 500.0, null, -1);
    fresh.update(5.0, 0.0, 1000, 5.0, 501.0, null, -1);
    Test.assert(fresh.grade() == null);
    return true;
}

(:test)
function ringAngles(logger as Logger) as Boolean {
    // 0 rechts neben der Lücke oben, 1 links daneben, 0,25 bei 3 Uhr.
    Test.assertEqual(TbRing.deg(0.0), 88);
    Test.assertEqual(TbRing.deg(1.0), -268);
    Test.assertEqual(TbRing.deg(0.25), -1);
    Test.assertEqual(TbRing.deg(2.0), -268);
    Test.assert(TbRing.share(500.0, 1000.0) == 0.5);
    Test.assert(TbRing.share(1500.0, 1000.0) == 1.0);
    Test.assert(TbRing.share(5.0, 0.0) == 0.0);
    return true;
}

//! Packen hin und zurück, auch an den Rändern von 16 Bit.
(:test)
function packRoundTrip(logger as Logger) as Boolean {
    var cases = [[0, 0], [1, -1], [-1, 1], [32767, -32768], [-32768, 32767], [-300, 450]] as Array<Array<Number>>;
    for (var i = 0; i < cases.size(); i++) {
        var v = PhoneRoute.pack(cases[i][0], cases[i][1]);
        Test.assertEqual(PhoneRoute.unpackHi(v), cases[i][0]);
        Test.assertEqual(PhoneRoute.unpackLo(v), cases[i][1]);
    }
    // Dieselbe Zahl wie `watchPack(1, 300)` in Dart und `pack` im Werkzeug.
    Test.assertEqual(PhoneRoute.pack(1, 300), 65836);
    Test.assertEqual(PhoneRoute.pack(-1, 300), -65236);
    return true;
}

//! Drei Stücke vom Handy dekodieren zur selben Route wie eines — die
//! Stummel aller Stücke hängen aneinander, die Nummern sind die der ganzen
//! Linie, die Höhen laufen über die Grenzen weiter.
(:test)
function decodeFromParts(logger as Logger) as Boolean {
    var d = TestRoutes.v2("j", false, [0, 0, 0, 300, 0, 300, 0, 300, 10, 0, 10, 0],
        [500, 520, 505, 540, 530, 560], [[1, 2, 2, "Testtrail"]], [1, 30, 0, 2, 0, -30, 5, 30, 0]);
    var one = NavRoute.decoded(d);
    var msgs = TestRoutes.parts(d, 2);
    Test.assertEqual(msgs.size(), 3);
    var list = [] as Array<Array>;
    for (var i = 0; i < msgs.size(); i++) { list.add(PhoneRoute.partOf(msgs[i]) as Array); }
    var r = new NavRoute("j", false, PhoneRoute.headOf(msgs[0]) as Array, new RouteParts(null, list, 3));
    while (!r.decodeStep(1)) {} // Punkt für Punkt, über jede Grenze
    Test.assert(r.isReady());
    Test.assertEqual(r.size(), 6);
    Test.assert(r.lengthM == one.lengthM);
    Test.assert(r.xs[5] == one.xs[5] && r.ys[5] == one.ys[5]);
    Test.assert(r.climbLeft(0.0) == one.climbLeft(0.0));
    Test.assertEqual(r.brAt.size(), 3);
    Test.assertEqual(r.brAt[2], 5);
    Test.assert(r.brX[1] == one.brX[1]);
    Test.assertEqual(r.secName[0], "Testtrail");
    return true;
}

//! Was nicht passt, macht die Route unbrauchbar statt die App kaputt: zu
//! wenige oder zu viele Punkte für `np`, ein fehlendes Stück, Höhen zu kurz.
(:test)
function decodeFailsOnMismatch(logger as Logger) as Boolean {
    var d = TestRoutes.straight();
    d["np"] = 5;
    Test.assert(NavRoute.decoded(d).failed);
    d = TestRoutes.straight();
    d["np"] = 3;
    Test.assert(NavRoute.decoded(d).failed);
    var head = PhoneRoute.headOf(TestRoutes.straight()) as Array;
    var part = PhoneRoute.partOf(TestRoutes.straight()) as Array;
    var gap = new NavRoute("g", false, head, new RouteParts(null, [part, part], 2));
    while (!gap.decodeStep(100)) {}
    Test.assert(gap.failed && !gap.isReady());
    var shortEle = new NavRoute("e", false, head,
        new RouteParts(null, [[part[0], [part[1][0]], part[2]]], 1));
    while (!shortEle.decodeStep(100)) {}
    Test.assert(shortEle.failed);
    // Ein Wörterbuch in falscher Form gibt eine unbrauchbare Route, keinen Absturz.
    Test.assert(NavRoute.fromDict({"id" => "x"}).failed);
    return true;
}

//! Erst mit dem letzten Stück gilt die neue Route; eine fremde Fassung,
//! eine unvollständige Übertragung und ein Stück außerhalb fallen weg, die
//! gespeicherte bleibt dabei heil. (`assertEqual` mit null wirft: Es ruft
//! `equals` auf dem Wert.)
(:test)
function phoneRouteStoresOnlyWhenComplete(logger as Logger) as Boolean {
    TestRoutes.wipe();
    var msgs = TestRoutes.parts(TestRoutes.v2("x1", false, [0, 0, 0, 300, 0, 300], null, null, null), 2);
    Test.assertEqual(msgs.size(), 2);
    var old = {"t" => "r", "id" => "x1", "p" => 0, "n" => 2, "v" => 1, "np" => 3, "o" => [0, 0], "pts" => [0, 0]};
    // Eine andere Fassung heißt `ver`, nicht `bad`: Das Handy nennt dann
    // die veraltete Seite (#449). Älter wie neuer.
    Test.assert(PhoneRoute.take(old) == null);
    Test.assertEqual(PhoneRoute.lastError, "ver");
    old["v"] = PhoneRoute.PROTOCOL + 1;
    Test.assert(PhoneRoute.take(old) == null);
    Test.assertEqual(PhoneRoute.lastError, "ver");
    Test.assert(PhoneRoute.take({"t" => "r", "id" => "x1", "p" => 2, "n" => 2, "pts" => [0]}) == null);
    Test.assert(PhoneRoute.take(msgs[0]) == null);
    Test.assert(PhoneRoute.lastError == null);
    Test.assert(PhoneRoute.route() == null);
    Test.assert(PhoneRoute.currentId() == null); // „hallo" ohne Kennung
    Test.assertEqual(PhoneRoute.take(msgs[1]), "x1");
    Test.assertEqual(PhoneRoute.currentId(), "x1");
    var r = PhoneRoute.route() as NavRoute;
    while (!r.decodeStep(300)) {}
    Test.assert(r.isReady());
    Test.assertEqual(r.size(), 3);
    Test.assertEqual(r.id, "x1");
    // Eine zweite Route kommt nur halb: Die erste bleibt die gespeicherte.
    var next = TestRoutes.parts(TestRoutes.v2("x2", false, [0, 0, 0, 300, 0, 300, 0, 300, 0, 300], null, null, null), 2);
    PhoneRoute.take(next[0]);
    Test.assertEqual(PhoneRoute.currentId(), "x1");
    Test.assertEqual((PhoneRoute.route() as NavRoute).id, "x1");
    TestRoutes.wipe();
    Test.assert(PhoneRoute.route() == null);
    return true;
}

//! Der Empfang nimmt nur Stücke in der richtigen Form, und Trails, die über
//! die Linie hinausreichen, fallen weg (ein `von` hinter dem Ende hieße in
//! jedem Bild ein Index außerhalb).
(:test)
function takeRejectsMalformed(logger as Logger) as Boolean {
    TestRoutes.wipe();
    var good = TestRoutes.parts(TestRoutes.straight(), 4)[0];
    var bad = [
        {"pts" => "x"},
        {"pts" => [0, "a"]},
        {"pts" => []},
        {"ele" => [1]},          // zu kurz für vier Punkte
        {"br" => [1]},           // ungerade
        {"np" => 1},
        {"o" => [0]},
        {"e0" => "x"}
    ] as Array<Dictionary>;
    for (var i = 0; i < bad.size(); i++) {
        var m = {} as Dictionary;
        var keys = good.keys();
        for (var k = 0; k < keys.size(); k++) { m[keys[k]] = good[keys[k]]; }
        var change = bad[i].keys();
        m[change[0]] = bad[i][change[0]];
        Test.assert(PhoneRoute.take(m) == null);
        Test.assertEqual(PhoneRoute.lastError, "bad");
    }
    Test.assert(PhoneRoute.currentId() == null);
    var head = PhoneRoute.headOf({"v" => PhoneRoute.PROTOCOL, "np" => 4, "o" => [0, 0],
        "sec" => [[1, 2, 2, "ok"], [2, 9, 1, "zu lang"], [3, 2, 0, "rückwärts"], [0, 1, 1], "kein Array"]}) as Array;
    Test.assertEqual((head[5] as Array).size(), 1);
    Test.assertEqual(PhoneRoute.take(good), "t");
    TestRoutes.wipe();
    return true;
}

//! Zweimal nicht sauber beendet, während dieselbe Route neu war: Sie ist
//! weg, als `bad` gemerkt, und kommt nicht wieder herein. Ein sauberes Ende
//! dazwischen zählt nicht.
(:test)
function crashGuardDropsAfterTwo(logger as Logger) as Boolean {
    TestRoutes.wipe();
    var msgs = TestRoutes.parts(TestRoutes.straight(), 4);
    Test.assertEqual(PhoneRoute.take(msgs[0]), "t");
    // Erster Absturz: gezählt, die Route bleibt.
    CrashGuard.risk("t");
    CrashGuard.atStart();
    Test.assertEqual(PhoneRoute.currentId(), "t");
    Test.assert(CrashGuard.bad() == null);
    // Ein sauberer Lauf dazwischen setzt den Zähler zurück …
    CrashGuard.atStart();
    CrashGuard.risk("t");
    CrashGuard.atStart();
    Test.assertEqual(PhoneRoute.currentId(), "t");
    // … zwei Abstürze nacheinander verwerfen sie.
    CrashGuard.risk("t");
    CrashGuard.atStart();
    Test.assert(PhoneRoute.currentId() == null);
    Test.assertEqual(CrashGuard.bad(), "t");
    Test.assert(PhoneRoute.take(msgs[0]) == null);
    Test.assertEqual(PhoneRoute.lastError, "crash");
    // Eine andere Route geht weiter.
    var other = TestRoutes.parts(TestRoutes.v2("u", false, [0, 0, 0, 300], null, null, null), 4);
    Test.assertEqual(PhoneRoute.take(other[0]), "u");
    // Ohne „risk" beim Start zählt nichts.
    CrashGuard.calm();
    CrashGuard.atStart();
    Test.assertEqual(PhoneRoute.currentId(), "u");
    TestRoutes.wipe();
    return true;
}

//! Die Testroute aus der Ressource (1000 Punkte, ein Stück mit 1560
//! Zahlen) dekodiert — die Grenze je Stück vom Handy gilt für sie nicht.
//! Ohne diesen Test hing die App am Gerät bei „Lade Route 0 %" (2026-11-05).
(:test)
function resourceRouteDecodes(logger as Logger) as Boolean {
    var r = NavRoute.decoded(WatchUi.loadResource(Rez.JsonData.Route) as Dictionary);
    Test.assert(!r.failed);
    Test.assert(r.isReady());
    Test.assert(r.size() >= 1000);
    return true;
}

//! Eine Route aus Protokoll 1 im Speicher (Stücke ohne Kopf) wird beim
//! Laden weggeräumt, statt Platz zu belegen.
(:test)
function oldStoredRouteIsCleared(logger as Logger) as Boolean {
    TestRoutes.wipe();
    Application.Storage.setValue("cur", "a");
    Application.Storage.setValue("aid", "alt");
    Application.Storage.setValue("an", 1);
    Application.Storage.setValue("a0", {"t" => "r", "pts" => [0, 0, 0, 300]});
    Test.assert(PhoneRoute.route() == null);
    Test.assert(PhoneRoute.currentId() == null);
    Test.assert(Application.Storage.getValue("a0") == null);
    TestRoutes.wipe();
    return true;
}

//! „Route kommt · 1/2": [PhoneRoute.received] zählt die Stücke der
//! ankommenden Route im freien Fach, nicht die einer anderen (#449,
//! 2026-11-06).
(:test)
function receivedCountsArrivingParts(logger as Logger) as Boolean {
    TestRoutes.wipe();
    var msgs = TestRoutes.parts(TestRoutes.straight(), 1);
    var id = msgs[0]["id"] as String;
    Test.assert(PhoneRoute.take(msgs[0]) == null);
    Test.assertEqual(PhoneRoute.received(id), 1);
    Test.assertEqual(PhoneRoute.received("andere"), 0);
    Test.assert(PhoneRoute.take(msgs[1]) == null);
    Test.assertEqual(PhoneRoute.received(id), 2);
    TestRoutes.wipe();
    return true;
}

//! Das Logo des Laders (`tool/brand_icons.py`): Punkte paarweise, der Weg
//! steigt (der Lader bricht beim ersten Punkt hinter dem Takt ab), Radien
//! um 8 px, alles innerhalb des Kreises der Anzeige.
(:test)
function loaderLogoIsOrdered(logger as Logger) as Boolean {
    var d = WatchUi.loadResource(Rez.JsonData.Logo) as Dictionary;
    var dots = d["d"] as Array<Number>;
    var total = d["t"] as Number;
    Test.assert(dots.size() > 40 && dots.size() % 2 == 0);
    var last = -1;
    for (var i = 0; i < dots.size(); i += 2) {
        var c = PhoneRoute.unpackLo(dots[i + 1]);
        var r = PhoneRoute.unpackHi(dots[i + 1]);
        var x = PhoneRoute.unpackHi(dots[i]) / 10;
        var y = NavView.LOGO_Y + PhoneRoute.unpackLo(dots[i]) / 10;
        Test.assert(c >= last && c <= total);
        // Radius in Zehntel px: der dickste Punkt des erzeugten Logos misst
        // 12,8 px (die Anlieger), die Grenze ist nur ein Plausibilitätsrahmen.
        Test.assert(r >= 20 && r <= 140);
        Test.assert(x * x + (y - 120) * (y - 120) < 110 * 110);
        last = c;
    }
    return true;
}

//! Die Fahrt auf der Uhr (#484): Punkte nur alle 5 s, gepackt und wieder
//! entpackt dieselben Zahlen, Stücke zu 60 Punkten, die Nachricht ans
//! Handy trägt sie alle.
(:test)
function rideLogPacksAndQueues(logger as Logger) as Boolean {
    TestRoutes.wipeRides();
    var log = new RideLog();
    log.start();
    // Jede Sekunde ein Fix, nur jeder fünfte zählt: 70 Punkte.
    Test.assertEqual(TestRoutes.ride(log, 1700000000, 350, 1), 70);
    Test.assert(log.recording());
    var id = log.finish() as String;
    Test.assertEqual(id, "1700000000");
    Test.assert(!log.recording());
    var q = RideLog.queue();
    Test.assertEqual(q.size(), 1);
    Test.assertEqual(q[0][1], 2); // 60 + 10
    Test.assertEqual(q[0][2], 70);
    Test.assertEqual(RideLog.queuedIds()[0], id);
    Test.assertEqual(RideLog.messageCount(q[0]), 1);
    var m = RideLog.message(q[0], 0);
    Test.assertEqual(m["t"], "w");
    Test.assertEqual(m["n"], 1);
    var c = m["c"] as Array<Array<Number>>;
    Test.assertEqual(c.size(), 2);
    var a = RideLog.unpack(c[0]);
    var b = RideLog.unpack(c[1]);
    Test.assertEqual(a.size(), 60);
    Test.assertEqual(b.size(), 10);
    // Punkt 61 = Fix 300 (0,15° Nord): Lage in 1e-5°, Zeit, Höhe in dm.
    Test.assertEqual(b[0][0], 15000);
    Test.assertEqual(b[0][1], 100);
    Test.assertEqual(b[0][2], 1700000300);
    Test.assertEqual(b[0][3], 5500);
    Test.assertEqual(a[59][2], 1700000295);
    Test.assertEqual(a[59][3], 5475);
    Test.assertEqual(a[59][4], 0);
    TestRoutes.wipeRides();
    return true;
}

//! Eine Lücke im GPS (mehr als 32 767 · 1e-5° in einem Schritt) beginnt
//! ein neues Stück mit eigenem Ursprung, statt falsch zu packen; eine
//! sinkende Höhe kommt mit Vorzeichen zurück.
(:test)
function rideLogSplitsOnGap(logger as Logger) as Boolean {
    TestRoutes.wipeRides();
    var log = new RideLog();
    log.start();
    TestRoutes.ride(log, 1700000000, 30, 5);
    Test.assert(log.add(1.0d, 0.001d, 1700000200, 380.0, 3));
    TestRoutes.ride(log, 1700000205, 30, 5);
    log.finish();
    var q = RideLog.queue();
    Test.assertEqual(q[0][1], 3);
    var c = RideLog.message(q[0], 0)["c"] as Array<Array<Number>>;
    Test.assertEqual(c[1][0], 100000);
    Test.assertEqual(c[1][4], 1); // USABLE
    var last = RideLog.unpack(c[0]);
    Test.assertEqual(last.size(), 30);
    Test.assert(RideLog.fits(32767, -32767, 5, -8191));
    Test.assert(!RideLog.fits(32768, 0, 5, 0));
    Test.assert(!RideLog.fits(0, 0, 5, 8192));
    TestRoutes.wipeRides();
    return true;
}

//! Kurz ist keine Fahrt: unter 2 min oder 200 m bleibt nichts liegen.
(:test)
function rideLogDropsShortRide(logger as Logger) as Boolean {
    TestRoutes.wipeRides();
    var log = new RideLog();
    log.start();
    TestRoutes.ride(log, 1700000000, 10, 5);
    Test.assert(log.finish() == null);
    Test.assertEqual(RideLog.queue().size(), 0);
    Test.assert(Application.Storage.getValue(RideLog.key("1700000000", 0)) == null);
    // Lange genug, aber im Stand: auch nichts.
    var still = new RideLog();
    still.start();
    for (var i = 0; i < 40; i++) { still.add(0.0d, 0.0d, 1700001000 + i * 5, 400.0, 4); }
    Test.assert(still.finish() == null);
    Test.assertEqual(RideLog.queue().size(), 0);
    return true;
}

//! Gelöscht wird nur, was das Handy quittiert — eine andere Kennung lässt
//! die Fahrt liegen (Kennungen mit `equals`, nicht `==`).
(:test)
function rideLogDeletesOnlyOnAck(logger as Logger) as Boolean {
    TestRoutes.wipeRides();
    var log = new RideLog();
    log.start();
    TestRoutes.ride(log, 1700000000, 40, 5);
    var id = log.finish() as String;
    Test.assert(!RideLog.ack("1700000001"));
    Test.assertEqual(RideLog.queue().size(), 1);
    // Dieselbe Kennung als neues Objekt, wie aus einer Nachricht.
    Test.assert(RideLog.ack("170000" + "0000"));
    Test.assertEqual(RideLog.queue().size(), 0);
    Test.assert(Application.Storage.getValue(RideLog.key(id, 0)) == null);
    Test.assert(!RideLog.ack(id));
    return true;
}

//! Ist die Warteschlange voll, steht die Aufzeichnung — nichts Wartendes
//! wird überschrieben.
(:test)
function rideLogStopsWhenFull(logger as Logger) as Boolean {
    TestRoutes.wipeRides();
    RideLog.enqueue("1600000000", 0, RideLog.MAX_POINTS);
    var log = new RideLog();
    log.start();
    Test.assertEqual(TestRoutes.ride(log, 1700000000, 30, 5), 0);
    Test.assert(log.full);
    Test.assert(!log.recording());
    Test.assertEqual(RideLog.queue().size(), 1);
    TestRoutes.wipeRides();
    return true;
}

//! Endete der Lauf mitten in der Fahrt (Absturz), wartet beim nächsten
//! Start, was gespeichert war.
(:test)
function rideLogRecoversAfterCrash(logger as Logger) as Boolean {
    TestRoutes.wipeRides();
    var log = new RideLog();
    log.start();
    TestRoutes.ride(log, 1700000000, 37, 5); // gespeichert bis Punkt 36
    RideLog.recover();
    var q = RideLog.queue();
    Test.assertEqual(q.size(), 1);
    Test.assertEqual(q[0][0], "1700000000");
    Test.assertEqual(q[0][2], 36);
    Test.assert(Application.Storage.getValue("wo") == null);
    var c = RideLog.message(q[0], 0)["c"] as Array<Array<Number>>;
    Test.assertEqual(RideLog.unpack(c[0]).size(), 36);
    TestRoutes.wipeRides();
    return true;
}

//! Aufgezeichnet wird erst nach START (Betreiber 2026-11-07, „wie
//! Garmin"); in der Pause nichts, und der Sprung über die Pause zählt
//! nicht als Strecke.
(:test)
function rideLogWaitsForStartAndPauses(logger as Logger) as Boolean {
    TestRoutes.wipeRides();
    var log = new RideLog();
    Test.assertEqual(log.state(), RideLog.IDLE);
    Test.assertEqual(TestRoutes.ride(log, 1700000000, 10, 5), 0);
    Test.assert(!log.recording());
    log.start();
    Test.assertEqual(log.state(), RideLog.RECORDING);
    Test.assertEqual(TestRoutes.ride(log, 1700000000, 30, 5), 30);
    var before = log.distanceM;
    log.pause();
    Test.assertEqual(log.state(), RideLog.PAUSED);
    Test.assert(!log.add(0.5d, 0.001d, 1700000400, 400.0, 4));
    log.resume();
    // 0,48° weiter nördlich, gut 50 km: kein Teil der Strecke.
    Test.assert(log.add(0.5d, 0.001d, 1700000500, 400.0, 4));
    Test.assert(log.distanceM - before < 1.0);
    Test.assert(log.add(0.5005d, 0.001d, 1700000505, 400.0, 4));
    Test.assert(log.distanceM - before > 50.0);
    Test.assert(log.finish() != null);
    Test.assertEqual(log.state(), RideLog.IDLE);
    TestRoutes.wipeRides();
    return true;
}

//! Trail-Marken: LAP setzt Beginn und Ende im Wechsel, „Verwerfen" nimmt
//! das letzte Paar zurück, die übrigen reisen mit der ersten Nachricht
//! (`m`); Verwerfen der Fahrt räumt alles weg. Gegenprobe: ohne
//! `storeMarks` fehlt `m` in der Nachricht.
(:test)
function rideLogCarriesTrailMarks(logger as Logger) as Boolean {
    TestRoutes.wipeRides();
    var log = new RideLog();
    log.start();
    Test.assertEqual(log.mark(1700000000), -1); // noch kein Punkt
    TestRoutes.ride(log, 1700000000, 30, 5);
    Test.assertEqual(log.mark(1700000050), 0);
    Test.assert(log.trailOpen());
    Test.assertEqual(log.mark(1700000100), 1);
    Test.assert(!log.trailOpen());
    Test.assertEqual(log.lastTrail()[1], 1700000100);
    Test.assertEqual(log.mark(1700000110), 0);
    Test.assertEqual(log.mark(1700000120), 1);
    Test.assertEqual(log.dropLastTrail()[0], 1700000110);
    var id = log.finish() as String;
    var m = RideLog.message(RideLog.queue()[0], 0)["m"] as Array<Number>;
    Test.assertEqual(m.size(), 4);
    Test.assertEqual(m[0], 0);
    Test.assertEqual(m[1], 1700000050);
    Test.assertEqual(m[2], 1);
    Test.assertEqual(m[3], 1700000100);
    Test.assert(RideLog.ack(id));
    Test.assert(Application.Storage.getValue(RideLog.markKey(id)) == null);
    // Verwerfen: nichts wartet, nichts bleibt liegen.
    var gone = new RideLog();
    gone.start();
    TestRoutes.ride(gone, 1700010000, 40, 5);
    gone.mark(1700010050);
    gone.discard();
    Test.assertEqual(RideLog.queue().size(), 0);
    Test.assert(Application.Storage.getValue("wo") == null);
    Test.assert(Application.Storage.getValue(RideLog.key("1700010000", 0)) == null);
    Test.assert(Application.Storage.getValue(RideLog.markKey("1700010000")) == null);
    TestRoutes.wipeRides();
    return true;
}

//! In der Pause zählen Strecke und Fahrzeit nicht (RideStats.counting).
(:test)
function rideStatsStopsWhenNotCounting(logger as Logger) as Boolean {
    var st = new RideStats(0);
    st.update(0.0, 0.0, 0, 5.0, 400.0, null, -1);
    st.update(0.0, 50.0, 10000, 5.0, 410.0, null, -1);
    var d = st.distanceM;
    Test.assert(d > 49.0);
    st.counting = false;
    st.update(0.0, 100.0, 20000, 5.0, 420.0, null, -1);
    Test.assertEqual(st.distanceM, d);
    var climbed = st.climbM;
    st.counting = true;
    st.update(0.0, 150.0, 30000, 5.0, 421.0, null, -1);
    // Der Anstieg in der Pause (410 → 420) zählt nicht nach.
    Test.assert(st.climbM - climbed < 3.0);
    return true;
}
