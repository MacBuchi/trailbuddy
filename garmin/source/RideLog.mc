import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;

//! Die Fahrt auf der Uhr (#484, Betreiber 2026-11-07, Konzept-Garmin 0.5
//! und 2a): Die Uhr zeichnet jede Fahrt selbst auf — GPS, Höhe vom
//! Barometer, Zeit, wie ein `RidePoint` der App; kein Puls, keine Sensoren,
//! keine Garmin-Aktivität. Die Fahrt bleibt im Speicher der Uhr, bis das
//! EIGENE Handy sie mit `{t: "wk", id}` quittiert; erst dann ist sie weg.
//!
//! Alle [EVERY_S] s ein Punkt (der Takt der Handy-Fahrt). Gepackt wie
//! Protokoll 2, in Stücken zu höchstens [CHUNK_POINTS] Punkten:
//!
//!   [lat, lon, t, e, acc,  p1, q1,  p2, q2, …]
//!
//! lat/lon des ersten Punkts in 1e-5°, t in Sekunden seit 1970 (UTC), e die
//! Höhe in Dezimetern, acc die Klasse der Genauigkeit (0 gut … 3 schlecht).
//! Danach je Punkt zwei Zahlen gegen den Vorgänger: p = `(dLat << 16) |
//! dLon`, q = `(dt << 16) | (dE << 2) | acc` mit dE in Dezimetern (14 Bit).
//! Passt ein Schritt nicht hinein (Lücke im GPS), beginnt ein neues Stück.
//!
//! Jedes Stück liegt unter `w<id>_<k>` in `Application.Storage`; das
//! offene wird alle [FLUSH_POINTS] Punkte neu geschrieben, dazu `wo` =
//! `[id, k, Punkte]`. Ein Absturz kostet also höchstens eine Minute; der
//! nächste Start nimmt die Fahrt in die Warteschlange ([recover]). Die
//! Warteschlange `rq` = `[[id, Stücke, Punkte], …]`.
class RideLog {
    static const EVERY_S = 5;
    static const CHUNK_POINTS = 60;
    static const FLUSH_POINTS = 12;
    //! So viele Stücke je Nachricht ans Handy: 6 × 123 Zahlen bleiben unter
    //! den 800 einer Nachricht der Route.
    static const CHUNKS_PER_MSG = 6;
    //! Kürzer ist keine Fahrt (ein Start vom Sofa): 2 min, 200 m.
    static const MIN_POINTS = 24;
    static const MIN_M = 200.0;
    //! Mehr Punkte hält die Uhr nicht (Warteschlange und offene Fahrt
    //! zusammen; 6000 sind gut 8 h). Startwert, bis die Grenze von
    //! `Application.Storage` an der fēnix 5 gemessen ist (Konzept 8.6).
    static const MAX_POINTS = 6000;
    static const MAX_RIDES = 20;
    //! So viele Punkte der Spur hält die Ansicht der freien Fahrt (25 min).
    static const TRACK_N = 300;
    static const K_LAT = 111194.9;

    //! Die Warteschlange ist voll: Die Aufzeichnung steht, bis das Handy
    //! Fahrten abnahm — nichts wird still überschrieben.
    var full as Boolean = false;
    //! Strecke der offenen Fahrt in Metern (für [MIN_M]).
    var distanceM as Float = 0.0;

    // Die Spur für die Ansicht der freien Fahrt, in Metern um den ersten
    // Fix dieses Laufs: ein Ring aus [TRACK_N] Punkten.
    var trackX as Array<Float>;
    var trackY as Array<Float>;
    var trackCount as Number = 0;
    var trackHead as Number = 0;
    hidden var _lat0 as Double? = null;
    hidden var _lon0 as Double = 0.0d;
    hidden var _kLon as Float = K_LAT;

    hidden var _id as String? = null;
    hidden var _k as Number = 0;
    hidden var _chunk as Array<Number>? = null;
    hidden var _n as Number = 0;
    hidden var _since as Number = 0;
    hidden var _lastLat as Number = 0;
    hidden var _lastLon as Number = 0;
    hidden var _lastT as Number = 0;
    hidden var _lastE as Number = 0;

    function initialize() {
        trackX = new Array<Float>[TRACK_N];
        trackY = new Array<Float>[TRACK_N];
    }

    //! Ein Fix. [t] Sekunden seit 1970, [ele] Meter oder null, [quality]
    //! `Position.QUALITY_*`. Liefert true, wenn der Punkt in die Fahrt ging.
    function add(latDeg as Double, lonDeg as Double, t as Number, ele as Float?, quality as Number) as Boolean {
        if (full) { return false; }
        if (_id != null && t - _lastT < EVERY_S) { return false; }
        var la = Math.round(latDeg * 100000.0d).toNumber();
        var lo = Math.round(lonDeg * 100000.0d).toNumber();
        var e = ele == null ? _lastE : Math.round(ele * 10.0).toNumber();
        var acc = quality >= 4 ? 0 : (quality == 3 ? 1 : (quality == 2 ? 2 : 3));
        var stored = RideLog.queuedPoints();
        if (_id == null) {
            if (stored >= MAX_POINTS || RideLog.queue().size() >= MAX_RIDES) {
                full = true;
                return false;
            }
            begin(t);
        } else if (stored + _n >= MAX_POINTS) {
            full = true;
            flush();
            return false;
        }
        var c = _chunk;
        var dLat = la - _lastLat;
        var dLon = lo - _lastLon;
        var dt = t - _lastT;
        var dE = e - _lastE;
        if (_n > 0) {
            var dy = dLat * K_LAT / 100000.0;
            var dx = dLon * K_LAT * Math.cos(Math.toRadians(la / 100000.0)) / 100000.0;
            distanceM += Math.sqrt(dx * dx + dy * dy).toFloat();
        }
        if (c == null || c.size() >= 5 + 2 * (CHUNK_POINTS - 1) || !fits(dLat, dLon, dt, dE)) {
            if (c != null) {
                if (!flush()) { return false; }
                _k++;
            }
            c = [la, lo, t, e, acc] as Array<Number>;
            _chunk = c;
        } else {
            c.add(PhoneRoute.pack(dLat, dLon));
            c.add(PhoneRoute.pack(dt, ((dE & 0x3FFF) << 2) | acc));
        }
        _n++;
        _lastLat = la;
        _lastLon = lo;
        _lastT = t;
        _lastE = e;
        _since++;
        if (_since >= FLUSH_POINTS) { flush(); }
        addTrack(latDeg, lonDeg);
        return true;
    }

    //! Passt ein Schritt in die gepackten Felder?
    static function fits(dLat as Number, dLon as Number, dt as Number, dE as Number) as Boolean {
        return dLat >= -32767 && dLat <= 32767 && dLon >= -32767 && dLon <= 32767
            && dt >= 0 && dt <= 32767 && dE >= -8191 && dE <= 8191;
    }

    //! Ein Ort in Metern um den ersten Fix dieses Laufs (für die Ansicht).
    function toLocal(latDeg as Double, lonDeg as Double) as [Float, Float] {
        if (_lat0 == null) {
            _lat0 = latDeg;
            _lon0 = lonDeg;
            _kLon = (K_LAT * Math.cos(Math.toRadians(latDeg))).toFloat();
        }
        return [((lonDeg - _lon0) * _kLon).toFloat(), ((latDeg - (_lat0 as Double)) * K_LAT).toFloat()];
    }

    hidden function addTrack(latDeg as Double, lonDeg as Double) as Void {
        var p = toLocal(latDeg, lonDeg);
        trackX[trackHead] = p[0];
        trackY[trackHead] = p[1];
        trackHead = (trackHead + 1) % TRACK_N;
        if (trackCount < TRACK_N) { trackCount++; }
    }

    //! Läuft eine Fahrt?
    function recording() as Boolean {
        return _id != null;
    }

    hidden function begin(t as Number) as Void {
        _id = t.toString();
        _k = 0;
        _n = 0;
        _since = 0;
        _chunk = null;
        distanceM = 0.0;
    }

    //! Das offene Stück und den Stand in den Speicher; false, wenn er voll ist.
    hidden function flush() as Boolean {
        var id = _id;
        var c = _chunk;
        _since = 0;
        if (id == null || c == null) { return true; }
        if (!PhoneRoute.store(RideLog.key(id, _k), c) || !PhoneRoute.store("wo", [id, _k, _n])) {
            full = true;
            return false;
        }
        return true;
    }

    //! Die Fahrt endet: in die Warteschlange, oder weg, wenn sie zu kurz
    //! war. Liefert die Kennung, wenn sie wartet, sonst null.
    function finish() as String? {
        var id = _id;
        if (id == null) { return null; }
        flush();
        var keep = _n >= MIN_POINTS && distanceM >= MIN_M;
        var chunks = _k + 1;
        var n = _n;
        _id = null;
        _chunk = null;
        _n = 0;
        Storage.deleteValue("wo");
        if (!keep) {
            RideLog.drop(id, chunks);
            return null;
        }
        return RideLog.enqueue(id, chunks, n) ? id : null;
    }

    //! Beim Start: Endete der letzte Lauf mitten in einer Fahrt (Absturz,
    //! Akku), kommt sie mit dem Gespeicherten in die Warteschlange.
    static function recover() as Void {
        var wo = Storage.getValue("wo");
        Storage.deleteValue("wo");
        if (!(wo instanceof Array) || wo.size() != 3 || !(wo[0] instanceof String)
                || !(wo[1] instanceof Number) || !(wo[2] instanceof Number)) { return; }
        var id = wo[0] as String;
        var chunks = (wo[1] as Number) + 1;
        var n = wo[2] as Number;
        if (n < MIN_POINTS) {
            drop(id, chunks);
            return;
        }
        enqueue(id, chunks, n);
    }

    static function enqueue(id as String, chunks as Number, n as Number) as Boolean {
        var q = queue();
        for (var i = 0; i < q.size(); i++) {
            if (id.equals(q[i][0])) { return true; }
        }
        q.add([id, chunks, n]);
        return PhoneRoute.store("rq", q);
    }

    static function key(id as String, k as Number) as String {
        return "w" + id + "_" + k;
    }

    //! Die wartenden Fahrten `[[id, Stücke, Punkte], …]`, ältere zuerst.
    static function queue() as Array<Array> {
        var q = Storage.getValue("rq");
        var out = [] as Array<Array>;
        if (!(q instanceof Array)) { return out; }
        for (var i = 0; i < q.size(); i++) {
            var e = q[i];
            if (e instanceof Array && e.size() == 3 && e[0] instanceof String
                    && e[1] instanceof Number && e[2] instanceof Number) {
                out.add(e);
            }
        }
        return out;
    }

    //! Die Kennungen der wartenden Fahrten (für „hallo").
    static function queuedIds() as Array<String> {
        var q = queue();
        var out = [] as Array<String>;
        for (var i = 0; i < q.size(); i++) { out.add(q[i][0] as String); }
        return out;
    }

    static function queuedPoints() as Number {
        var q = queue();
        var n = 0;
        for (var i = 0; i < q.size(); i++) { n += q[i][2] as Number; }
        return n;
    }

    //! So viele Nachrichten braucht die wartende Fahrt [entry].
    static function messageCount(entry as Array) as Number {
        var chunks = entry[1] as Number;
        return (chunks + CHUNKS_PER_MSG - 1) / CHUNKS_PER_MSG;
    }

    //! Nachricht [p] der wartenden Fahrt [entry]: `{t: "w", id, p, n, c}`,
    //! `c` die Stücke `[[lat, lon, t, e, acc, …], …]`. Ein fehlendes Stück
    //! fällt weg — der Rest der Fahrt ist mehr wert als nichts.
    static function message(entry as Array, p as Number) as Dictionary {
        var id = entry[0] as String;
        var chunks = entry[1] as Number;
        var c = [] as Array<Array>;
        for (var k = p * CHUNKS_PER_MSG; k < (p + 1) * CHUNKS_PER_MSG && k < chunks; k++) {
            var v = Storage.getValue(key(id, k));
            if (v instanceof Array) { c.add(v); }
        }
        return {"t" => "w", "id" => id, "p" => p, "n" => messageCount(entry), "c" => c} as Dictionary;
    }

    //! Das Handy hat die Fahrt [id] (`wk`): aus der Warteschlange und dem
    //! Speicher. false, wenn sie nicht (mehr) wartet.
    static function ack(id as String) as Boolean {
        var q = queue();
        for (var i = 0; i < q.size(); i++) {
            var e = q[i];
            if (id.equals(e[0])) {
                q.remove(e);
                PhoneRoute.store("rq", q);
                drop(id, e[1] as Number);
                return true;
            }
        }
        return false;
    }

    static function drop(id as String, chunks as Number) as Void {
        for (var k = 0; k < chunks; k++) { Storage.deleteValue(key(id, k)); }
    }

    //! Ein Stück entpackt in `[[lat, lon, t, e, acc], …]` (für die Tests;
    //! das Gegenstück in der App ist `decodeWatchRide`).
    static function unpack(c as Array<Number>) as Array<Array<Number>> {
        var out = [[c[0], c[1], c[2], c[3], c[4]]] as Array<Array<Number>>;
        var la = c[0];
        var lo = c[1];
        var t = c[2];
        var e = c[3];
        for (var i = 5; i + 1 < c.size(); i += 2) {
            la += PhoneRoute.unpackHi(c[i]);
            lo += PhoneRoute.unpackLo(c[i]);
            t += PhoneRoute.unpackHi(c[i + 1]);
            var l = c[i + 1] & 0xFFFF;
            var de = (l >> 2) & 0x3FFF;
            if (de >= 0x2000) { de -= 0x4000; }
            e += de;
            out.add([la, lo, t, e, l & 3]);
        }
        return out;
    }
}
