import Toybox.Application;
import Toybox.Lang;

//! Der Ereignis-Rekorder (#510, Prüfleiter T4 in docs/konzept-garmin.md
//! 12): Was der Ablaufkern ([WatchCore]) erlebt, als Ring der letzten
//! [SIZE] Ereignisse — damit ein Fehler im Feld ein Skript für den Kern
//! wird (`tool/garmin_events.py`) statt einer zweiten Fahrt.
//!
//! Je Ereignis EINE Zahl: `(Code << 24) | Sekunden seit dem Start der App`
//! (24 Bit); der Code ist `(Art << 3) | Detail`, 5 Bit Art, 3 Bit Detail.
//! **Keine Koordinaten, keine Kennungen, keine Namen (A7)** — ein Fix ist
//! nur „auf der Linie", „abseits" oder „keiner".
//!
//! Die Codes stehen als Zahlen an den Aufrufen (`WatchCore.ev`), nicht als
//! Konstanten: Im Gerätebau kostet jede Konstante dauerhaft Speicher
//! (garmin/CLAUDE.md, „Speicher im Gerätebau"). Die Tabelle steht in
//! `tool/garmin_events.py` (`KINDS`) und `lib/features/garmin/watch_events.dart`;
//! `test/garmin/watch_events_test.dart` hält sie mit dieser Datei zusammen.
//!
//!   0 Start        Detail 1 mit Handy, 0 ohne
//!   1 Taste        0 START, 1 ZURÜCK, 2 langes HOCH
//!   2 Menüpunkt    0 Weiter, 1 Speichern, 2 Verwerfen, 3 Ja, 4 Nein,
//!                  5 Trail behalten, 6 Trail verwerfen, 7 Route beenden
//!   3/4 vom Handy  Art nach [IN_T] (Stelle / 3; ab 8 Art 4, unbekannt 4.7)
//!   5/6 ans Handy  Art nach [OUT_T] (ebenso; ab 8 Art 6, unbekannt 6.7)
//!   7 Übertragung  0 Ende ab, 1 Ende nicht, 2 Fahrt ab, 3 Fahrt nicht
//!   8 Stand        0 bereit, 1 Aufnahme, 2 Pause (nach START), 3 freie
//!                  Fahrt, 4 Route geladen, 5 geht zu, 6 Routenwechsel,
//!                  7 Lader wartet
//!   9 Fix          nur beim Wechsel: 0 keiner/zu ungenau, 1 auf der Linie,
//!                  2 abseits, 3 frei (ohne Route)
//!  10 Frist        0 zu, 1 Wechsel, 2 ruhige Minute, 3 Warten vorbei
//!
//! Geschrieben nach `Application.Storage` („ev"), wenn die App zugeht, bei
//! Start, Taste und Menüpunkt und sonst höchstens alle 5 min — ein Absturz
//! („IQ!") behält den Stand bis dahin.
//! Stand „evr" beim Start noch, ging die App nicht sauber zu: Der alte Ring
//! wird „evc" und reist mit dem nächsten „hallo" (`ev`). Eine Fahrt nimmt
//! beim Speichern den Ring mit („ev_<id>", [keepFor]) und schickt ihn in
//! ihrer ersten Nachricht (`w`, `ev`).
module EventLog {
    const SIZE = 120;
    //! Die Arten der Nachrichten, je drei Zeichen ab Stelle 0.
    const IN_T = " q  wq wk p  n  k  e  r  b  ";
    const OUT_T = " hi x  ok g  d  e  rs re rp rr rt w  ";

    var _ring as Array = [];
    var _head as Number = 0;
    var _n as Number = 0;
    var _t0 as Number = 0;
    var _savedAt as Number = 0;
    var _evOut as Boolean = false;
    //! Alle Ereignisse seit dem Start, auch die herausgefallenen (der
    //! Wiedergabe in den Tests sagt es, wie weit der Kern ist).
    var total as Number = 0;

    //! Beim Start der App, vor allem anderen: ein neuer Ring; der alte wird
    //! zum Absturz-Ring „evc", wenn die App beim letzten Mal nicht zuging.
    function boot(now as Number, phone as Boolean) as Void {
        var s = Application.Storage;
        if (s.getValue("evr") == true) {
            var old = s.getValue("ev");
            if (old instanceof Array && old.size() > 0) { PhoneRoute.store("evc", old); }
        }
        _ring = new [SIZE];
        _head = 0;
        _n = 0;
        _t0 = now;
        _savedAt = now;
        _evOut = false;
        total = 0;
        PhoneRoute.store("evr", true);
        rec(phone ? 1 : 0, now);
    }

    //! Ein Ereignis mit [code] (`Art << 3 | Detail`) in den Ring; der
    //! älteste fällt heraus. In den Speicher bei Start, Taste und Menüpunkt
    //! (Art 0–2: selten, und genau dort stürzt ein Ablauf ab — nur alle
    //! 5 min hätte ein Absturz in den ersten Minuten nichts hinterlassen,
    //! Kettenstand 2026-11-12), sonst höchstens alle 5 min.
    function rec(code as Number, now as Number) as Void {
        var sec = (now - _t0) / 1000;
        _ring[_head] = (code << 24) | (sec > 0 ? sec & 0xFFFFFF : 0);
        _head = (_head + 1) % SIZE;
        if (_n < SIZE) { _n++; }
        total++;
        if (code < 24 || now - _savedAt >= 300000) { save(now); }
    }

    //! Der Code einer Nachricht nach ihrer Art `t`: vom Handy ab 24 (Art
    //! 3), ans Handy ab 40 (Art 5); was nicht in der Liste steht, x.7 der
    //! zweiten Art.
    function msgCode(t as Object?, out as Boolean) as Number {
        var i = t instanceof String ? (out ? OUT_T : IN_T).find(" " + t + " ") : null;
        var base = out ? 40 : 24;
        return i == null ? base + 15 : base + i / 3;
    }

    //! Der Ring, ältestes zuerst.
    function list() as Array<Number> {
        var out = [] as Array<Number>;
        var start = _n < SIZE ? 0 : _head;
        for (var i = 0; i < _n; i++) { out.add(_ring[(start + i) % SIZE] as Number); }
        return out;
    }

    function save(now as Number) as Void {
        _savedAt = now;
        PhoneRoute.store("ev", list());
    }

    //! Die App geht sauber zu: der Ring ist gesichert, kein Absturz.
    function stop(now as Number) as Void {
        save(now);
        PhoneRoute.store("evr", false);
        if (_evOut) { delivered(); }
    }

    //! Eine Fahrt ist gespeichert: Sie nimmt den Ring mit — nach einem
    //! Absturz ([crashed], [RideLog.recover]) den alten.
    function keepFor(id as String, crashed as Boolean) as Void {
        var ev = crashed ? Application.Storage.getValue("evc") : list();
        if (ev instanceof Array && ev.size() > 0) { PhoneRoute.store("ev_" + id, ev); }
    }

    //! Der Absturz-Ring für „hallo", oder null. Geht er an ein Handy
    //! ([phone]), ist er nach dem nächsten sauberen Zugehen weg, auch ohne
    //! Antwort — ein Handy ohne Navigation schweigt auf „hallo".
    function crashed(phone as Boolean) as Array? {
        var c = Application.Storage.getValue("evc");
        if (!(c instanceof Array)) { return null; }
        if (phone) { _evOut = true; }
        return c;
    }

    //! Das Handy hat auf „hallo" geantwortet: Der Absturz-Ring ist da.
    function delivered() as Void {
        Application.Storage.deleteValue("evc");
    }
}
