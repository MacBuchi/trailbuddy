import Toybox.Application;
import Toybox.Lang;
import Toybox.Test;

//! Unit-Tests der Uhr-Seite (Konzept-Garmin 6): Dekodierung und die
//! Regeln der Folgeansicht. `tool/garmin_build.sh --test` fährt sie im
//! Simulator. Alle Routen hier sind erfunden und liegen am Äquator.

//! Die Testrouten — ein Modul, damit der Runner sie nicht für Tests hält.
(:test)
module TestRoutes {
//! Gerade nach Osten, 900e-5° ≈ 1000,8 m, ein Trail.
function straightRoute() as NavRoute {
    return NavRoute.decoded({
        "v" => 1, "id" => "t", "rel" => false,
        "pts" => [0, 0, 0, 300, 0, 300, 0, 300],
        "ele" => [500, 520, 505, 540],
        "sec" => [[1, 2, 2, "Testtrail"]],
        "br" => [1, 30, 0, 9, 1, 1]
    });
}

//! Hin und zurück auf derselben Linie: 1 km nach Osten, dann zurück.
function outAndBack() as NavRoute {
    return NavRoute.decoded({
        "v" => 1, "id" => "oab", "rel" => false,
        "pts" => [0, 0, 0, 450, 0, 450, 0, -450, 0, -450]
    });
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
    var r = NavRoute.decoded({ "v" => 1, "id" => "long", "rel" => false, "pts" => pts });
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
    var r = NavRoute.decoded({ "v" => 1, "id" => "rel", "rel" => true, "pts" => [0, 0, 0, 900] });
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

//! Zwei Stücke vom Handy (`WatchRoute.parts`) setzen sich zur selben
//! Route zusammen wie `straightRoute` in einem Stück.
(:test)
function phoneRouteJoinsParts(logger as Logger) as Boolean {
    var acc = {} as Dictionary;
    PhoneRoute.append(acc, {"t" => "r", "id" => "t", "p" => 0, "n" => 2, "v" => 1,
        "sec" => [[1, 2, 2, "Testtrail"]], "pts" => [0, 0, 0, 300], "ele" => [500, 520],
        "br" => [1, 30, 0]});
    PhoneRoute.append(acc, {"t" => "r", "id" => "t", "p" => 1, "n" => 2,
        "pts" => [0, 300, 0, 300], "ele" => [505, 540], "br" => [2, 0, -30, 3, 30, 0]});
    var r = NavRoute.decoded(acc);
    Test.assertEqual(r.size(), 4);
    Test.assert(r.lengthM > 1000.0 && r.lengthM < 1001.5);
    Test.assertEqual(r.secName[0], "Testtrail");
    Test.assert(!r.relative);
    Test.assertEqual((acc["ele"] as Array).size(), 4);
    // Die Stummel aller Stücke hängen aneinander, die Nummern sind die der
    // ganzen Linie.
    Test.assertEqual(r.brAt.size(), 3);
    Test.assertEqual(r.brAt[1], 2);
    Test.assert(r.brY[0] > 33.0 && r.brY[0] < 34.0);
    return true;
}

//! Erst mit dem letzten Stück gilt die neue Route; eine fremde Fassung,
//! eine unvollständige Übertragung und ein Stück außerhalb fallen weg, die
//! gespeicherte bleibt dabei heil. (`assertEqual` mit null wirft: Es ruft
//! `equals` auf dem Wert.)
(:test)
function phoneRouteStoresOnlyWhenComplete(logger as Logger) as Boolean {
    PhoneRoute.drop();
    Application.Storage.deleteValue("a" + "id");
    Application.Storage.deleteValue("b" + "id");
    var p0 = {"t" => "r", "id" => "x1", "p" => 0, "n" => 2, "v" => 1, "pts" => [0, 0, 0, 300]};
    var p1 = {"t" => "r", "id" => "x1", "p" => 1, "n" => 2, "pts" => [0, 300]};
    Test.assert(PhoneRoute.take({"t" => "r", "id" => "x1", "p" => 0, "n" => 2, "v" => 9, "pts" => [0, 0]}) == null);
    Test.assert(PhoneRoute.take({"t" => "r", "id" => "x1", "p" => 2, "n" => 2, "pts" => [0, 0]}) == null);
    Test.assert(PhoneRoute.take(p0) == null);
    Test.assert(PhoneRoute.load() == null);
    Test.assert(PhoneRoute.currentId() == null); // „hallo" ohne Kennung
    Test.assertEqual(PhoneRoute.take(p1), "x1");
    Test.assertEqual(PhoneRoute.currentId(), "x1");
    var d = PhoneRoute.load() as Dictionary;
    Test.assertEqual((d["pts"] as Array).size(), 6);
    Test.assertEqual(d["id"], "x1");
    // Eine zweite Route kommt nur halb: Die erste bleibt die gespeicherte.
    PhoneRoute.take({"t" => "r", "id" => "x2", "p" => 0, "n" => 3, "v" => 1, "pts" => [0, 0]});
    Test.assertEqual((PhoneRoute.load() as Dictionary)["id"], "x1");
    Test.assertEqual(PhoneRoute.currentId(), "x1");
    PhoneRoute.drop();
    Test.assert(PhoneRoute.load() == null);
    return true;
}
