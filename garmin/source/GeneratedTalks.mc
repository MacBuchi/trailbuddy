// ERZEUGT von tool/watch_talks.py aus docs/watch_cases.json (`gespraeche`)
// — nie von Hand ändern: Gespräch im Katalog ändern, dann
// `python3 tool/watch_talks.py` und `python3 tool/generated_assets.py --update`.
// Die Seite der Uhr (#509, Prüfleiter S3); der Spieler ist `TestTalk` in
// CoreTests.mc, die Seite des Handys test/garmin/watch_talks_test.dart.
import Toybox.Lang;
import Toybox.Test;

//! Die Uhr-App startet, das Handy navigiert: Route in Stücken, ok, Bestwerte; nach dem Neustart „deine ist aktuell“; Ende am Handy
(:test)
function talk_hallo_neue_route(logger as Logger) as Boolean {
    return TestTalk.play("hallo-neue-route", ["handy"] as Array<String>, [
        {"von" => "uhr", "tu" => "start", "msg" => {"t" => "hi", "v" => 2, "ver" => "1.3.0"}, "gleich" => ["v"], "dann" => ["wartet"]},
        {"von" => "handy", "msg" => {"t" => "n", "id" => "$a", "np" => 2}, "dann" => ["route_kommt"]},
        {"von" => "handy", "msg" => {"t" => "r", "id" => "$a"}},
        {"von" => "uhr", "msg" => {"t" => "ok", "id" => "$a"}, "nach_ms" => 500, "dann" => ["route:$a"]},
        {"von" => "handy", "msg" => {"t" => "b", "jn" => 1, "ja" => 600}, "dann" => ["bestwerte"]},
        {"von" => "handy", "msg" => {"t" => "p", "la" => 4750090, "lo" => 1150000}},
        {"von" => "uhr", "tu" => "restart", "msg" => {"t" => "hi", "v" => 2, "ver" => "1.3.0", "id" => "$a"}, "dann" => ["wartet"]},
        {"von" => "handy", "msg" => {"t" => "k", "id" => "$a"}, "nach_ms" => 500, "dann" => ["route:$a"]},
        {"von" => "handy", "msg" => {"t" => "e", "id" => "$a"}, "dann" => ["zu"]}
    ] as Array<Dictionary>);
}

//! Ein Stück mit einer anderen Fassung: die Uhr sagt `x ver` mit ihrer
(:test)
function talk_fassung_handy_alt(logger as Logger) as Boolean {
    return TestTalk.play("fassung-handy-alt", ["geladen"] as Array<String>, [
        {"von" => "handy", "msg" => {"t" => "r", "id" => "$a", "v" => 1}},
        {"von" => "uhr", "msg" => {"t" => "x", "id" => "$a", "c" => "ver", "v" => 2}, "gleich" => ["c", "v"], "dann" => ["route:t"]}
    ] as Array<Dictionary>);
}

//! Die Uhr nimmt die Route nicht (zweimal abgestürzt): das Handy schickt sie halb so groß
(:test)
function talk_kleiner_nach_absturz(logger as Logger) as Boolean {
    return TestTalk.play("kleiner-nach-absturz", ["geladen", "bad:$a"] as Array<String>, [
        {"von" => "handy", "msg" => {"t" => "n", "id" => "$a", "np" => 2}},
        {"von" => "handy", "msg" => {"t" => "r", "id" => "$a"}},
        {"von" => "uhr", "msg" => {"t" => "x", "id" => "$a", "c" => "crash"}, "gleich" => ["c"]},
        {"von" => "handy", "msg" => {"t" => "n", "id" => "$b", "np" => 1}},
        {"von" => "handy", "msg" => {"t" => "r", "id" => "$b"}},
        {"von" => "uhr", "msg" => {"t" => "ok", "id" => "$b"}, "dann" => ["fragt"]}
    ] as Array<Dictionary>);
}

//! Navigation an der Uhr beendet: das Handy beendet seine auch
(:test)
function talk_ende_an_der_uhr(logger as Logger) as Boolean {
    return TestTalk.play("ende-an-der-uhr", ["handy"] as Array<String>, [
        {"von" => "uhr", "tu" => "start", "msg" => {"t" => "hi", "v" => 2, "ver" => "1.3.0"}},
        {"von" => "handy", "msg" => {"t" => "n", "id" => "$a", "np" => 2}},
        {"von" => "handy", "msg" => {"t" => "r", "id" => "$a"}},
        {"von" => "uhr", "msg" => {"t" => "ok", "id" => "$a"}, "nach_ms" => 500, "dann" => ["route:$a"]},
        {"von" => "uhr", "tu" => "quit", "msg" => {"t" => "e", "id" => "$a"}, "dann" => ["zu"]}
    ] as Array<Dictionary>);
}

//! START an der Uhr: das Handy nimmt mit auf; Trail behalten, Pause, Weiter, Speichern, die Fahrt hinüber
(:test)
function talk_aufzeichnung(logger as Logger) as Boolean {
    return TestTalk.play("aufzeichnung", ["geladen"] as Array<String>, [
        {"von" => "uhr", "tu" => "startKey", "msg" => {"t" => "rs"}, "dann" => ["nimmt_auf"]},
        {"von" => "uhr", "tu" => "fixes", "fa" => 0, "fb" => 10, "msg" => {"t" => "g", "la" => 0, "lo" => 100}},
        {"von" => "uhr", "tu" => "back"},
        {"von" => "uhr", "tu" => "fixes", "fa" => 10, "fb" => 20},
        {"von" => "uhr", "tu" => "back"},
        {"von" => "uhr", "tu" => "keep", "msg" => {"t" => "rt", "s" => 1700000050, "e" => 1700000100}},
        {"von" => "uhr", "tu" => "startKey", "msg" => {"t" => "rp"}, "dann" => ["pause"]},
        {"von" => "uhr", "tu" => "resume", "msg" => {"t" => "rr"}, "dann" => ["nimmt_auf"]},
        {"von" => "uhr", "tu" => "fixes", "fa" => 20, "fb" => 30},
        {"von" => "uhr", "tu" => "startKey", "msg" => {"t" => "rp"}},
        {"von" => "uhr", "tu" => "save", "msg" => {"t" => "re", "k" => true}, "gleich" => ["k"], "dann" => ["zu"]},
        {"von" => "uhr", "msg" => {"t" => "w", "id" => "$f", "p" => 0, "n" => 1, "c" => "*"}},
        {"von" => "handy", "msg" => {"t" => "wk", "id" => "$f"}, "dann" => ["keine_fahrt"]}
    ] as Array<Dictionary>);
}

//! Eine Fahrt wartet auf der Uhr: hallo mit `rq`, das Handy sagt „schick“, die Fahrt geht nach dem Warten hinüber
(:test)
function talk_fahrt_wartet(logger as Logger) as Boolean {
    return TestTalk.play("fahrt-wartet", ["handy", "fahrt"] as Array<String>, [
        {"von" => "uhr", "tu" => "start", "msg" => {"t" => "hi", "v" => 2, "ver" => "1.3.0", "rq" => ["$f"]}, "dann" => ["wartet", "fahrt_wartet"]},
        {"von" => "handy", "msg" => {"t" => "wq"}, "nach_ms" => 9000},
        {"von" => "uhr", "msg" => {"t" => "w", "id" => "$f", "p" => 0, "n" => 1, "c" => "*"}},
        {"von" => "handy", "msg" => {"t" => "wk", "id" => "$f"}, "dann" => ["keine_fahrt"]}
    ] as Array<Dictionary>);
}

//! Freie Fahrt: der erste eigene Fix geht ans Handy, es schickt den Trail in Reichweite, die Uhr nimmt ihn still
(:test)
function talk_freie_fahrt_linie(logger as Logger) as Boolean {
    return TestTalk.play("freie-fahrt-linie", ["handy", "ohne_route"] as Array<String>, [
        {"von" => "uhr", "tu" => "start", "msg" => {"t" => "hi", "v" => 2, "ver" => "1.3.0"}, "nach_ms" => 9000, "dann" => ["frei"]},
        {"von" => "uhr", "tu" => "fixes", "fa" => 0, "fb" => 3, "msg" => {"t" => "g", "la" => 4800500, "lo" => 900010}},
        {"von" => "handy", "msg" => {"t" => "n", "id" => "$a", "np" => 1}},
        {"von" => "handy", "msg" => {"t" => "r", "id" => "$a"}},
        {"von" => "uhr", "msg" => {"t" => "ok", "id" => "$a"}, "nach_ms" => 500, "dann" => ["route:$a"]}
    ] as Array<Dictionary>);
}

//! Die Uhr fährt weit neben ihrer Linie: `d`, das Handy rechnet ab ihr um, die Uhr fragt vor der neuen
(:test)
function talk_abseits_umplanen(logger as Logger) as Boolean {
    return TestTalk.play("abseits-umplanen", ["handy"] as Array<String>, [
        {"von" => "uhr", "tu" => "start", "msg" => {"t" => "hi", "v" => 2, "ver" => "1.3.0"}},
        {"von" => "handy", "msg" => {"t" => "n", "id" => "$a", "np" => 2}},
        {"von" => "handy", "msg" => {"t" => "r", "id" => "$a"}},
        {"von" => "uhr", "msg" => {"t" => "ok", "id" => "$a"}, "nach_ms" => 500, "dann" => ["route:$a"]},
        {"von" => "uhr", "tu" => "fixes", "fa" => 0, "fb" => 1, "msg" => {"t" => "g", "la" => 4750090, "lo" => 1150000}},
        {"von" => "uhr", "tu" => "fixes", "fa" => 1, "fb" => 40, "msg" => {"t" => "d", "la" => 4750630, "lo" => 1150399, "off" => 300}},
        {"von" => "handy", "msg" => {"t" => "n", "id" => "$b", "np" => 2}},
        {"von" => "handy", "msg" => {"t" => "r", "id" => "$b"}},
        {"von" => "uhr", "msg" => {"t" => "ok", "id" => "$b"}, "dann" => ["fragt"]}
    ] as Array<Dictionary>);
}

//! Die Route geht verloren: kein ok, das Handy fragt nach (`q`), das hallo holt sie
(:test)
function talk_nachfragen(logger as Logger) as Boolean {
    return TestTalk.play("nachfragen", ["geladen"] as Array<String>, [
        {"von" => "handy", "msg" => {"t" => "n", "id" => "$a", "np" => 2}},
        {"von" => "handy", "msg" => {"t" => "r", "id" => "$a"}, "verloren" => true},
        {"von" => "handy", "msg" => {"t" => "q"}},
        {"von" => "uhr", "msg" => {"t" => "hi", "v" => 2, "ver" => "1.3.0"}},
        {"von" => "handy", "msg" => {"t" => "n", "id" => "$a", "np" => 2}},
        {"von" => "handy", "msg" => {"t" => "r", "id" => "$a"}},
        {"von" => "uhr", "msg" => {"t" => "ok", "id" => "$a"}, "dann" => ["fragt"]}
    ] as Array<Dictionary>);
}

//! Die Route geht in der freien Fahrt verloren: nach 30 s fragt die Uhr wieder (`hi`), dann kommt sie an
(:test)
function talk_frei_fragt_wieder(logger as Logger) as Boolean {
    return TestTalk.play("frei-fragt-wieder", ["handy", "ohne_route"] as Array<String>, [
        {"von" => "uhr", "tu" => "start", "msg" => {"t" => "hi", "v" => 2, "ver" => "1.3.0"}, "nach_ms" => 9000, "dann" => ["frei"]},
        {"von" => "handy", "msg" => {"t" => "n", "id" => "$a", "np" => 2}, "verloren" => true},
        {"von" => "handy", "msg" => {"t" => "r", "id" => "$a"}, "verloren" => true},
        {"von" => "uhr", "tu" => "fixes", "fa" => 0, "fb" => 7, "msg" => {"t" => "g", "la" => 0, "lo" => 100}},
        {"von" => "uhr", "msg" => {"t" => "hi", "v" => 2, "ver" => "1.3.0"}},
        {"von" => "handy", "msg" => {"t" => "n", "id" => "$a", "np" => 2}},
        {"von" => "handy", "msg" => {"t" => "r", "id" => "$a"}},
        {"von" => "uhr", "msg" => {"t" => "ok", "id" => "$a"}, "nach_ms" => 500, "dann" => ["route:$a"]}
    ] as Array<Dictionary>);
}
