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
    Test.assert(PhoneRoute.take(old) == null);
    Test.assertEqual(PhoneRoute.lastError, "bad");
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
