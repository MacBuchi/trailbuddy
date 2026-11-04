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
