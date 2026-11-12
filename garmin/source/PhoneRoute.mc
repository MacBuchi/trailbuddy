import Toybox.Application;
import Toybox.Lang;
import Toybox.System;

//! Die Route vom Handy (Konzept-Garmin 2 und 3, G2). Beim Start und auf
//! die Frage `q` meldet sich die Uhr mit `{t: "hi", v, id, bad}` — `id`
//! ist [currentId] (fehlt ohne Route vom Handy), `bad` eine Route, die die
//! App zweimal abstürzen ließ ([CrashGuard]). Die Route kommt in Stücken
//! (`lib/features/garmin/watch_route.dart`, `WatchRoute.parts`),
//! Protokoll 2 (#449, 2026-11-05):
//!
//!   t    "r"
//!   id   Kennung der Route
//!   p, n Laufnummer und Anzahl der Stücke
//!   v, np, o, e0, sec   der Kopf, nur im ersten Stück: Protokoll, Anzahl
//!        der Punkte, erster Punkt [lat, lon] in 1e-5°, erste Höhe (fehlt
//!        ohne Höhen), die Trails [[von, bis, sGrad, Name], …]
//!   pts  je Punkt `(dLat << 16) | dLon` gegen den Vorgänger ([unpackHi],
//!        [unpackLo]); der erste Punkt der Route gegen `o`
//!   ele  die Höhendifferenzen dazu, zwei je Zahl, oder fehlt
//!   br   die Stummel der Punkte dieses Stücks: [Punkt, gepackt(dLat,
//!        dLon), …] (Punktnummern der ganzen Linie), oder fehlt
//!
//! Jedes Stück geht geprüft sofort in den Speicher der Uhr
//! (`Application.Storage`) — nur `[pts, ele, br]`, nicht die ganze
//! Nachricht — und nicht in den Arbeitsspeicher: Die alte Route läuft
//! weiter, bis die neue ganz da ist. Zwei Fächer „a" und „b": Die neue
//! füllt das Fach, das die laufende nicht belegt; erst wenn alle Stücke da
//! sind, zeigt `cur` darauf. Eine abgebrochene Übertragung lässt die
//! gespeicherte Route also heil. `NavRoute` liest später Stück für Stück
//! ([RouteParts]) — die ganze Route liegt nie roh im Arbeitsspeicher. Nur
//! die Route liegt im Speicher, keine Position, keine Fahrt (A3).
//!
//! Geht etwas schief, steht der Grund in [lastError] ("bad", "mem",
//! "store", "crash"), und die App sagt es dem Handy (`{t: "x", id, c}`).
//! `try/catch` fängt nur `Lang.Exception` (dazu gehört
//! `StorageFullException`) — „Out of Memory", Watchdog und ein Index
//! außerhalb beenden die App ohne Fang. Deshalb wird vorher geprüft.
module PhoneRoute {
    //! Fassung des Protokolls (`kWatchProtocol` in Dart; ein Test der App
    //! liest diese Zeile).
    const PROTOCOL = 2;
    //! Mehr Stücke nimmt die Uhr nicht an (800 Punkte gepackt in Stücken
    //! zu 800 Zahlen: 2; Luft für kleinere Stücke).
    const MAX_PARTS = 30;
    //! Mehr Punkte nimmt die Uhr nicht an (die App schickt höchstens 800,
    //! `kWatchMaxPoints`; schon 1750 passen nicht in den Speicher — die
    //! Grenze hier ist nur ein Riegel gegen Unsinn).
    const MAX_POINTS = 4000;
    //! So viele Zahlen je Stück höchstens: Je Wert nimmt der Speicher
    //! 8 KB, eine Zahl sind ~5 Byte (Handy: 800).
    const MAX_PART_INTS = 1400;
    //! So viel Arbeitsspeicher muss frei sein, bevor ein Stück in den
    //! Speicher geht: Grundbetrag plus je Zahl — das Ablegen braucht das
    //! Zwei- bis Dreifache des Werts (Forenberichte, im Simulator nicht
    //! nachzustellen).
    const FREE_BASE = 4096;
    const FREE_PER_INT = 16;

    //! Der Grund, warum das letzte [take] nichts nahm, oder null.
    var lastError as String? = null;

    //! Die oberen 16 Bit mit Vorzeichen (`watchPack` in Dart). Mit Maske,
    //! damit es nicht darauf ankommt, ob `>>` das Vorzeichen mitnimmt.
    function unpackHi(v as Number) as Number {
        var h = (v >> 16) & 0xFFFF;
        return h >= 0x8000 ? h - 0x10000 : h;
    }

    function unpackLo(v as Number) as Number {
        var l = v & 0xFFFF;
        return l >= 0x8000 ? l - 0x10000 : l;
    }

    //! Gegenstück (für die Tests und den Vorführmodus).
    function pack(hi as Number, lo as Number) as Number {
        return ((hi & 0xFFFF) << 16) | (lo & 0xFFFF);
    }

    //! Ein Stück aus [msg] ablegen. Liefert die Kennung, sobald die Route
    //! vollständig ist (und damit gilt), sonst null — dann steht in
    //! [lastError], ob etwas schiefging (null: Stück angenommen, es fehlen
    //! noch welche).
    function take(msg as Dictionary) as String? {
        lastError = null;
        var id = msg["id"];
        var p = msg["p"];
        var n = msg["n"];
        if (!(id instanceof String) || !(p instanceof Number) || !(n instanceof Number)
                || n < 1 || n > MAX_PARTS || p < 0 || p >= n) {
            return fail("bad");
        }
        // Eine andere Fassung sagt die Uhr als solche (`ver`), damit das
        // Handy die veraltete Seite nennen kann (#449, 2026-11-05).
        if (p == 0 && msg["v"] != PROTOCOL) { return fail("ver"); }
        var bad = Storage.getValue("bad");
        if (bad instanceof String && bad.equals(id)) { return fail("crash"); }
        var part = partOf(msg);
        // Je Wert nimmt der Speicher nur ~8 KB — die Grenze gilt für
        // Stücke vom Handy, nicht für die Testroute aus der Ressource.
        if (part == null || (part[0] as Array).size() + (part[1] as Array).size()
                + (part[2] as Array).size() > MAX_PART_INTS) {
            return fail("bad");
        }
        var head = null;
        if (p == 0) {
            head = headOf(msg);
            if (head == null) { return fail("bad"); }
        }
        var slot = freeSlot();
        // Eine neue Kennung (oder eine andere Länge) beginnt das Fach von vorn.
        // Zeichenketten mit `equals`: `==` vergleicht in Monkey C die Objekte.
        if (!id.equals(Storage.getValue(slot + "id")) || Storage.getValue(slot + "n") != n) {
            clear(slot);
            if (!store(slot + "id", id) || !store(slot + "n", n) || !store(slot + "mask", 0)) {
                clear(slot);
                return fail("store");
            }
        }
        var ints = (part[0] as Array).size() + (part[1] as Array).size() + (part[2] as Array).size();
        if (System.getSystemStats().freeMemory < FREE_BASE + FREE_PER_INT * ints) {
            clear(slot);
            return fail("mem");
        }
        if ((head != null && !store(slot + "h", head)) || !store(slot + p, part)) {
            clear(slot);
            return fail("store");
        }
        var mask = (Storage.getValue(slot + "mask") as Number) | (1 << p);
        if (!store(slot + "mask", mask)) {
            clear(slot);
            return fail("store");
        }
        if (mask != (1 << n) - 1) { return null; }
        var old = Storage.getValue("cur") as String?;
        if (!store("cur", slot)) {
            clear(slot);
            return fail("store");
        }
        if (old != null) { clear(old); }
        return id;
    }

    function fail(why as String) as Null {
        lastError = why;
        return null;
    }

    //! Ein Wert in den Speicher; false, wenn der ihn nicht nahm.
    function store(key as String, value as Application.PropertyValueType) as Boolean {
        try {
            Storage.setValue(key, value);
        } catch (e instanceof Lang.Exception) {
            return false;
        }
        return true;
    }

    //! Die Zahlen eines Stücks, geprüft: `[pts, ele, br]` (fehlende als
    //! leeres Array), oder null, wenn etwas nicht passt.
    function partOf(msg as Dictionary) as Array? {
        var pts = msg["pts"];
        var ele = msg["ele"];
        var br = msg["br"];
        if (!(pts instanceof Array) || pts.size() < 1) { return null; }
        if (ele == null) {
            ele = [] as Array<Number>;
        } else if (!(ele instanceof Array) || ele.size() != (pts.size() + 1) / 2) {
            return null;
        }
        if (br == null) {
            br = [] as Array<Number>;
        } else if (!(br instanceof Array) || br.size() % 2 != 0) {
            return null;
        }
        if (!numbers(pts) || !numbers(ele) || !numbers(br)) { return null; }
        return [pts, ele, br];
    }

    function numbers(a as Array) as Boolean {
        for (var i = 0; i < a.size(); i++) {
            if (!(a[i] instanceof Number)) { return false; }
        }
        return true;
    }

    //! Der Kopf aus dem ersten Stück (oder `route.json`), geprüft:
    //! `[np, lat0, lon0, mitHöhen, e0, sec]`, oder null. Trails außerhalb
    //! der Linie oder in falscher Form fallen still weg — ein `von`
    //! hinter dem Ende hieße in jedem Bild ein Index außerhalb.
    function headOf(msg as Dictionary) as Array? {
        var np = msg["np"];
        var o = msg["o"];
        var e0 = msg["e0"];
        if (msg["v"] != PROTOCOL || !(np instanceof Number) || np < 2 || np > MAX_POINTS) { return null; }
        if (!(o instanceof Array) || o.size() != 2 || !(o[0] instanceof Number) || !(o[1] instanceof Number)) {
            return null;
        }
        if (e0 != null && !(e0 instanceof Number)) { return null; }
        var sec = [] as Array<Array>;
        var raw = msg["sec"];
        if (raw instanceof Array) {
            for (var i = 0; i < raw.size(); i++) {
                var s = raw[i];
                if (s instanceof Array && s.size() >= 4 && s[0] instanceof Number && s[1] instanceof Number
                        && s[2] instanceof Number && s[3] instanceof String
                        && s[0] >= 0 && s[0] < s[1] && s[1] < np) {
                    sec.add([s[0], s[1], s[2], s[3]]);
                }
            }
        }
        return [np, o[0], o[1], e0 != null, e0 == null ? 0 : e0, sec];
    }

    //! Die gespeicherte Route, bereit zum Dekodieren (Stück für Stück aus
    //! dem Speicher), oder null. Was nicht lesbar ist — etwa eine Route
    //! aus Protokoll 1 ohne Kopf —, wird weggeräumt, statt Platz zu belegen.
    function route() as NavRoute? {
        var slot = Storage.getValue("cur");
        if (!(slot instanceof String)) { return null; }
        var id = Storage.getValue(slot + "id");
        var n = Storage.getValue(slot + "n");
        var head = Storage.getValue(slot + "h");
        if (!(id instanceof String) || !(n instanceof Number) || !(head instanceof Array) || head.size() != 6) {
            drop();
            return null;
        }
        return new NavRoute(id, false, head, new RouteParts(slot, null, n));
    }

    //! So viele Stücke der Route [id] liegen schon im freien Fach (für
    //! „Route kommt · 1/2" im Lader).
    function received(id as String) as Number {
        var slot = freeSlot();
        if (!id.equals(Storage.getValue(slot + "id"))) { return 0; }
        var mask = Storage.getValue(slot + "mask");
        var k = 0;
        if (mask instanceof Number) {
            for (var m = mask; m != 0; m = m >> 1) { k += m & 1; }
        }
        return k;
    }

    //! Die Kennung der gespeicherten Route, oder null (für „hallo").
    function currentId() as String? {
        var slot = Storage.getValue("cur");
        if (!(slot instanceof String)) { return null; }
        var id = Storage.getValue(slot + "id");
        return id instanceof String ? id : null;
    }

    //! Die gespeicherte Route verwerfen (sie ließ die App abstürzen).
    function drop() as Void {
        var slot = Storage.getValue("cur") as String?;
        Storage.deleteValue("cur");
        if (slot != null) { clear(slot); }
    }

    function freeSlot() as String {
        return "a".equals(Storage.getValue("cur")) ? "b" : "a";
    }

    function clear(slot as String) as Void {
        var n = Storage.getValue(slot + "n");
        if (n instanceof Number) {
            for (var p = 0; p < n && p < MAX_PARTS; p++) { Storage.deleteValue(slot + p); }
        }
        Storage.deleteValue(slot + "id");
        Storage.deleteValue(slot + "n");
        Storage.deleteValue(slot + "mask");
        Storage.deleteValue(slot + "h");
    }
}

//! Die Stücke einer Route für [NavRoute]: aus dem Speicher der Uhr (Fach
//! [slot]) oder, für die Testroute und die Tests, aus einer Liste. Immer
//! nur ein Stück zugleich im Arbeitsspeicher.
class RouteParts {
    hidden var _slot as String?;
    hidden var _list as Array<Array>?;
    hidden var _n as Number;

    function initialize(slot as String?, list as Array<Array>?, n as Number) {
        _slot = slot;
        _list = list;
        _n = n;
    }

    function size() as Number {
        return _n;
    }

    //! Stück [k] als `[pts, ele, br]`, oder null.
    function get(k as Number) as Array? {
        if (k < 0 || k >= _n) { return null; }
        var l = _list;
        if (l != null) { return l[k]; }
        var v = Storage.getValue((_slot as String) + k);
        return v instanceof Array ? v : null;
    }
}

//! Kein Absturz zweimal mit derselben Route (#449, 2026-11-05). Solange
//! eine Route neu ist — sie kommt gerade an, oder sie lädt und läuft noch
//! keine [CALM_MS] —, steht ihre Kennung unter „risk"; `onStop` und die
//! ruhige Minute löschen sie. Steht sie beim nächsten Start noch, endete
//! der Lauf nicht sauber. Beim [LIMIT]. Mal mit derselben Route wird sie
//! verworfen und als `bad` gemerkt: Die Uhr nimmt sie nicht mehr, „hallo"
//! nennt sie, und das Handy schickt sie mit halb so vielen Punkten.
module CrashGuard {
    const LIMIT = 2;
    const CALM_MS = 60000;

    //! Beim Start, vor dem Laden der Route.
    function atStart() as Void {
        var risk = Storage.getValue("risk");
        Storage.deleteValue("risk");
        if (!(risk instanceof String)) {
            // Der letzte Lauf endete sauber: Frühere Abstürze zählen nicht mehr.
            Storage.deleteValue("crashId");
            Storage.deleteValue("crashN");
            return;
        }
        var n = Storage.getValue("crashN");
        var c = risk.equals(Storage.getValue("crashId")) && n instanceof Number ? n + 1 : 1;
        if (c < LIMIT) {
            PhoneRoute.store("crashId", risk);
            PhoneRoute.store("crashN", c);
            return;
        }
        PhoneRoute.store("bad", risk);
        Storage.deleteValue("crashId");
        Storage.deleteValue("crashN");
        if (risk.equals(PhoneRoute.currentId())) { PhoneRoute.drop(); }
    }

    //! Die Route [id] ist neu (kommt an oder lädt).
    function risk(id as String) as Void {
        if (!id.equals(Storage.getValue("risk"))) { PhoneRoute.store("risk", id); }
    }

    //! Sauber beendet, oder eine Minute ruhig gelaufen.
    function calm() as Void {
        Storage.deleteValue("risk");
    }

    //! Die verworfene Route, oder null (für „hallo").
    function bad() as String? {
        var b = Storage.getValue("bad");
        return b instanceof String ? b : null;
    }
}
