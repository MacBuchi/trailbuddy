import Toybox.Application;
import Toybox.Lang;

//! Die Route vom Handy (Konzept-Garmin 2 und 3, G2). Beim Start und auf
//! die Frage `q` meldet sich die Uhr mit `{t: "hi", v, id}` — `id` ist
//! [currentId], fehlt ohne Route vom Handy. Die Route kommt in Stücken
//! (`lib/features/garmin/watch_route.dart`, `WatchRoute.parts`):
//!
//!   t    "r"
//!   id   Kennung der Route
//!   p, n Laufnummer und Anzahl der Stücke
//!   v    Protokollversion (nur im ersten Stück)
//!   sec  die Trails (nur im ersten Stück)
//!   pts  ein Stück von `pts` (das erste beginnt mit dem absoluten Punkt)
//!   ele  das Stück von `ele` dazu, oder fehlt
//!   br   die Stummel der Punkte dieses Stücks (Punktnummern der ganzen
//!        Linie), oder fehlt
//!
//! Jedes Stück geht sofort in den Speicher der Uhr (`Application.Storage`)
//! und nicht in den Arbeitsspeicher: Die alte Route läuft weiter, bis die
//! neue ganz da ist. Zwei Fächer „a" und „b": Die neue füllt das Fach, das
//! die laufende nicht belegt; erst wenn alle Stücke da sind, zeigt `cur`
//! darauf. Eine abgebrochene Übertragung lässt die gespeicherte Route also
//! heil. Nur die Route liegt im Speicher, keine Position, keine Fahrt (A3).
module PhoneRoute {
    //! Fassung des Protokolls (`kWatchProtocol` in Dart; ein Test der App
    //! liest diese Zeile).
    const PROTOCOL = 1;
    //! Mehr Stücke nimmt die Uhr nicht an (2000 Punkte zu je drei Zahlen,
    //! 800 Zahlen je Stück: 8; Luft für kleinere Stücke).
    const MAX_PARTS = 30;

    //! Ein Stück aus [msg] ablegen. Liefert die Kennung, sobald die Route
    //! vollständig ist (und damit gilt), sonst null. Fremdes und
    //! Unpassendes fällt still weg.
    function take(msg as Dictionary) as String? {
        var id = msg["id"];
        var p = msg["p"];
        var n = msg["n"];
        if (!(id instanceof String) || !(p instanceof Number) || !(n instanceof Number)) { return null; }
        if (n < 1 || n > MAX_PARTS || p < 0 || p >= n) { return null; }
        if (p == 0 && msg["v"] != PROTOCOL) { return null; }
        var slot = freeSlot();
        // Eine neue Kennung (oder eine andere Länge) beginnt das Fach von vorn.
        // Zeichenketten mit `equals`: `==` vergleicht in Monkey C die Objekte.
        if (!id.equals(Storage.getValue(slot + "id")) || Storage.getValue(slot + "n") != n) {
            clear(slot);
            Storage.setValue(slot + "id", id);
            Storage.setValue(slot + "n", n);
            Storage.setValue(slot + "mask", 0);
        }
        Storage.setValue(slot + p, msg);
        var mask = (Storage.getValue(slot + "mask") as Number) | (1 << p);
        Storage.setValue(slot + "mask", mask);
        if (mask != (1 << n) - 1) { return null; }
        var old = Storage.getValue("cur") as String?;
        Storage.setValue("cur", slot);
        if (old != null) { clear(old); }
        return id;
    }

    //! Die gespeicherte Route als Dictionary in der Form von `route.json`,
    //! oder null. Stück für Stück aus dem Speicher — nie alle zugleich.
    function load() as Dictionary? {
        var slot = Storage.getValue("cur") as String?;
        if (slot == null) { return null; }
        var n = Storage.getValue(slot + "n") as Number?;
        if (n == null) { return null; }
        var acc = {} as Dictionary;
        for (var p = 0; p < n; p++) {
            var part = Storage.getValue(slot + p) as Dictionary?;
            if (part == null) { return null; }
            append(acc, part);
        }
        return acc;
    }

    //! Hängt [part] an [acc] (pur, für die Tests).
    function append(acc as Dictionary, part as Dictionary) as Void {
        if (part["p"] == 0) {
            acc["v"] = part["v"];
            acc["id"] = part["id"];
            acc["rel"] = false;
            acc["pts"] = [] as Array<Number>;
            if (part["sec"] != null) { acc["sec"] = part["sec"]; }
            if (part["ele"] != null) { acc["ele"] = [] as Array<Number>; }
        }
        (acc["pts"] as Array<Number>).addAll(part["pts"] as Array<Number>);
        var ele = acc["ele"] as Array<Number>?;
        if (ele != null && part["ele"] != null) {
            ele.addAll(part["ele"] as Array<Number>);
        }
        var br = part["br"] as Array<Number>?;
        if (br != null) {
            if (acc["br"] == null) { acc["br"] = [] as Array<Number>; }
            (acc["br"] as Array<Number>).addAll(br);
        }
    }

    //! Die Kennung der gespeicherten Route, oder null (für „hallo").
    function currentId() as String? {
        var slot = Storage.getValue("cur") as String?;
        if (slot == null) { return null; }
        return Storage.getValue(slot + "id") as String?;
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
        var n = Storage.getValue(slot + "n") as Number?;
        if (n != null) {
            for (var p = 0; p < n; p++) { Storage.deleteValue(slot + p); }
        }
        Storage.deleteValue(slot + "id");
        Storage.deleteValue(slot + "n");
        Storage.deleteValue(slot + "mask");
    }
}
