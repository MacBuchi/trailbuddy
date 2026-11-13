import Toybox.Lang;
import Toybox.Math;

//! Die Zahlen der Seiten „Fahrt" und „Berg" und der Zusammenfassung bei
//! der Ankunft (Entwurf „Ring und Seiten", Betreiber 2026-11-04). Nur im
//! Speicher der laufenden App: Die Uhr ist Anzeige (Entscheidung 1), es
//! wird nichts gespeichert und nichts verschickt (A3) — beim Beenden ist
//! alles weg.
class RideStats {
    //! Ab diesem Tempo zählt Fahrzeit und Strecke (darunter ist es
    //! GPS-Zittern im Stand).
    static const MOVING_MPS = 1.0;
    //! Ein Sprung zwischen zwei Fixen, der weiter ist, zählt nicht (GPS
    //! wacht nach einem Tunnel auf).
    static const MAX_STEP_M = 100.0;
    //! Bergauf mit Hysterese wie `hysteresisClimb` der App — das
    //! Barometer rauscht weniger als ein Höhenmodell, daher 3 statt 10 m.
    static const CLIMB_HYSTERESIS_M = 3.0;
    //! Die Steigung über mindestens so viel Strecke; Stützpunkte alle
    //! 5 m, höchstens 16.
    static const GRADE_OVER_M = 30.0;
    static const GRADE_STEP_M = 5.0;
    static const GRADE_SLOTS = 16;

    var distanceM as Float = 0.0;
    var movingS as Float = 0.0;
    var climbM as Float = 0.0;
    var altitude as Float? = null;
    var heartRate as Number? = null;
    //! Je Abschnitt der Route: befahren?
    var ridden as Array<Boolean>;
    //! Die Bestwerte der Erkennung vom Handy (#36, Idee des Betreibers
    //! 2026-11-04; `watchBestsOf` in der App): `jn` Sprünge, `ja` längste
    //! Flugzeit in ms, `wn` Wheelies, `wl` längster in m, `wa` größter
    //! Winkel in Grad, `sn` Stoppies. Gemessen wird auf dem Handy, die Uhr
    //! zeigt nur (Entscheidung 1). Null, solange keiner kam.
    var bests as Dictionary? = null;
    //! Zählen Strecke, Fahrzeit und bergauf mit? Nur, solange die Uhr
    //! aufzeichnet (vor START und in der Pause nicht, wie bei Garmin);
    //! Höhe, Steigung und Puls stehen trotzdem.
    var counting as Boolean = true;

    hidden var _lastX as Float? = null;
    hidden var _lastY as Float? = null;
    hidden var _lastMs as Number? = null;
    hidden var _ref as Float? = null;
    hidden var _gDist as Array<Float> = [] as Array<Float>;
    hidden var _gAlt as Array<Float> = [] as Array<Float>;

    function initialize(sections as Number) {
        ridden = new Array<Boolean>[sections];
        for (var i = 0; i < sections; i++) { ridden[i] = false; }
    }

    //! Ein Fix: Ort in Metern (NavRoute.toLocal), Zeit in ms, Tempo in m/s,
    //! Höhe vom Barometer, Puls; [section] der Abschnitt, auf dem man
    //! gerade ist (-1 = keiner).
    function update(x as Float, y as Float, ms as Number, speed as Float?, alt as Float?,
                    hr as Number?, section as Number) as Void {
        var moving = counting && speed != null && speed >= MOVING_MPS;
        var lx = _lastX;
        var ly = _lastY;
        var lm = _lastMs;
        if (lx != null && ly != null && lm != null && moving) {
            var dx = x - lx;
            var dy = y - ly;
            var step = Math.sqrt(dx * dx + dy * dy).toFloat();
            if (step <= MAX_STEP_M) {
                distanceM += step;
                movingS += (ms - lm) / 1000.0;
            }
        }
        _lastX = x;
        _lastY = y;
        _lastMs = ms;
        heartRate = hr;
        if (section >= 0 && section < ridden.size()) { ridden[section] = true; }
        if (alt == null) { return; }
        altitude = alt;
        // In der Pause beginnt der Anstieg danach am dann tiefsten Punkt.
        if (!counting) {
            _ref = alt;
        } else {
            climb(alt);
        }
        sampleGrade(alt);
    }

    //! Der Anstieg zählt erst, wenn die Höhe um die Hysterese über dem
    //! tiefsten Punkt seit dem letzten Zählen liegt.
    hidden function climb(alt as Float) as Void {
        var ref = _ref;
        if (ref == null || alt < ref) {
            _ref = alt;
        } else if (alt - ref >= CLIMB_HYSTERESIS_M) {
            climbM += alt - ref;
            _ref = alt;
        }
    }

    hidden function sampleGrade(alt as Float) as Void {
        var n = _gDist.size();
        if (n > 0 && distanceM - _gDist[n - 1] < GRADE_STEP_M) { return; }
        _gDist.add(distanceM);
        _gAlt.add(alt);
        if (_gDist.size() > GRADE_SLOTS) {
            _gDist = _gDist.slice(1, null);
            _gAlt = _gAlt.slice(1, null);
        }
    }

    //! Steigung in Prozent über die letzten 30 bis 80 m, oder null, solange
    //! noch nicht genug Strecke da ist.
    function grade() as Number? {
        var n = _gDist.size();
        if (n < 2) { return null; }
        var dLast = _gDist[n - 1];
        for (var i = n - 2; i >= 0; i--) {
            var run = dLast - _gDist[i];
            if (run >= GRADE_OVER_M) {
                return Math.round((_gAlt[n - 1] - _gAlt[i]) / run * 100).toNumber();
            }
        }
        return null;
    }

    //! Die Fahrt geht weiter, die Route nicht (#513: Wechsel oder „Route
    //! beenden"): Strecke, Fahrzeit, bergauf, Höhe und Puls bleiben. Der
    //! letzte Ort nicht — die neue Route rechnet in anderen Metern.
    function carryFrom(old as RideStats) as Void {
        distanceM = old.distanceM;
        movingS = old.movingS;
        climbM = old.climbM;
        altitude = old.altitude;
        heartRate = old.heartRate;
    }

    //! Gibt es Bestwerte zu zeigen? `on` allein (#514) ist keiner.
    function hasBests() as Boolean {
        return best("jn") + best("wn") + best("sn") > 0;
    }

    //! Eine Zahl der Bestwerte, oder 0.
    function best(key as String) as Number {
        var b = bests;
        if (b == null) { return 0; }
        var v = b[key];
        return v instanceof Number ? v : 0;
    }

    function riddenCount() as Number {
        var c = 0;
        for (var i = 0; i < ridden.size(); i++) { if (ridden[i]) { c++; } }
        return c;
    }
}
