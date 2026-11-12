#!/usr/bin/env python3
"""Der Ereignis-Ring der Uhr als Liste und als Skript (#510, Prüfleiter T4).

Die Uhr hält die letzten 120 Ereignisse ihres Ablaufkerns
(`garmin/source/EventLog.mc`) und gibt sie mit jeder Fahrt (`w`, `ev`) und
nach einem Absturz mit dem nächsten „hallo" (`hi`, `ev`) ans Handy. Das
Handy hängt sie auf Wunsch an eine Fehlermeldung (Glühbirne) — dort steht
eine Zeile `Uhr-Protokoll (n Schritte): ev1:…`. Dieses Skript macht daraus

  - die lesbare Liste (Vorgabe):  `python3 tool/garmin_events.py DATEI`
  - einen Monkey-C-Test, der den Ring gegen den Ablaufkern spielt
    (`TestReplay.play` in `CoreTests.mc`):
        python3 tool/garmin_events.py DATEI --monkeyc NAME >> garmin/source/CoreTests.mc
    danach `tool/garmin_bench.sh sim-unit` (oder `unit`) — der Test sagt im
    Log, wo der Kern am Ende stand, und wird mit Zusicherungen zum
    Fall, sobald klar ist, was hätte passieren sollen.

DATEI darf alles sein, was den Ring enthält: der Text des Issues (die
Zeile `Uhr-Protokoll (…): ev1:…`, kompakt gepackt), eine JSON-Liste oder
Zahlen mit Kommas; `-` liest von stdin.

    python3 tool/garmin_events.py --self-test

Je Ereignis eine Zahl: `(Art << 27) | (Detail << 24) | Sekunden seit dem
Start der App`. Die Tabelle der Arten steht in EventLog.mc als Kommentar,
hier als KINDS und in `lib/features/garmin/watch_events.dart`;
`test/garmin/watch_events_test.dart` hält Dart und Monkey C zusammen, der
Selbsttest hier Python und Monkey C (die Arten der Nachrichten liest er aus
EventLog.mc). Keine Koordinaten, keine Kennungen (A7) — ein Fix ist nur
seine Klasse.
"""
from __future__ import annotations

import base64
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EVENT_LOG = ROOT / "garmin" / "source" / "EventLog.mc"

KINDS: dict[int, tuple[str, list[str]]] = {
    0: ("Start", ["ohne Handy", "mit Handy"]),
    1: ("Taste", ["START", "ZURÜCK", "langes HOCH"]),
    2: ("Menü", ["Weiter", "Speichern", "Verwerfen", "Ja", "Nein",
                 "Trail behalten", "Trail verwerfen", "Route beenden"]),
    # 3–6: die Arten der Nachrichten, aus EventLog.mc (msg_names).
    7: ("Übertragung", ["Ende abgenommen", "Ende nicht abgenommen",
                        "Fahrt abgenommen", "Fahrt nicht abgenommen"]),
    8: ("Stand", ["bereit", "Aufnahme", "Pause", "freie Fahrt", "Route geladen",
                  "geht zu", "Routenwechsel", "Lader wartet"]),
    9: ("Fix", ["keiner", "auf der Linie", "abseits", "frei"]),
    10: ("Frist", ["zu", "Wechsel", "ruhige Minute", "Warten vorbei"]),
}

# Was die Wiedergabe spielt (Eingaben); der Rest sind Folgen, die sie
# abwartet (`TestReplay.play`).
INPUTS = {1, 2, 3, 4, 7, 9}


def msg_names(source: str | None = None) -> tuple[list[str], list[str]]:
    """Die Arten der Nachrichten vom Handy und ans Handy, wie die Uhr sie
    zählt: je drei Zeichen ab Stelle 0 in `IN_T` und `OUT_T`."""
    text = source if source is not None else EVENT_LOG.read_text(encoding="utf-8")
    out = []
    for name in ("IN_T", "OUT_T"):
        m = re.search(rf'const {name} = "([^"]*)";', text)
        if not m:
            raise SystemExit(f"{name} fehlt in EventLog.mc")
        s = m.group(1)
        out.append([s[i:i + 3].strip() for i in range(0, len(s) - 1, 3)])
    return out[0], out[1]


def unpack(v: int) -> tuple[int, int, int]:
    v &= 0xFFFFFFFF
    return (v >> 27) & 0x1F, (v >> 24) & 7, v & 0xFFFFFF


def pack(kind: int, detail: int, sec: int) -> int:
    v = (kind << 27) | ((detail & 7) << 24) | (sec & 0xFFFFFF)
    # Die Uhr rechnet mit 32 Bit Vorzeichen.
    return v - (1 << 32) if v >= 1 << 31 else v


def describe(v: int, names: tuple[list[str], list[str]] | None = None) -> str:
    kind, detail, _ = unpack(v)
    ins, outs = names if names is not None else msg_names()
    if kind in (3, 4, 5, 6):
        table = ins if kind in (3, 4) else outs
        i = detail + (8 if kind in (4, 6) else 0)
        what = "vom Handy" if kind in (3, 4) else "ans Handy"
        # x.7 der zweiten Art: eine Art, die nicht in der Liste steht.
        unknown = kind in (4, 6) and detail == 7
        return f"{what} {'?' if unknown or i >= len(table) else table[i]}"
    if kind not in KINDS:
        return f"Art {kind}.{detail}"
    name, details = KINDS[kind]
    return f"{name}: {details[detail] if detail < len(details) else detail}"


def encode(events: list[int]) -> str:
    """Die Form im Feedback-Text (`encodeWatchEvents` in
    watch_events.dart): je Ereignis ein Byte Code, die Sekunden seit dem
    vorigen als Varint, base64url ohne `=`, `ev1:` davor."""
    out = bytearray()
    last = 0
    for v in events:
        kind, detail, sec = unpack(v)
        out.append((kind << 3) | detail)
        d = max(sec - last, 0)
        last = sec
        while d >= 0x80:
            out.append((d & 0x7F) | 0x80)
            d >>= 7
        out.append(d)
    return "ev1:" + base64.urlsafe_b64encode(bytes(out)).decode().rstrip("=")


def decode(s: str) -> list[int]:
    s += "=" * (-len(s) % 4)
    data = base64.urlsafe_b64decode(s)
    out, sec, p = [], 0, 0
    while p < len(data):
        code = data[p]
        p += 1
        d = shift = 0
        while True:
            if p >= len(data):
                raise ValueError("ev1: abgeschnitten")
            b = data[p]
            p += 1
            d |= (b & 0x7F) << shift
            shift += 7
            if b < 0x80:
                break
        sec += d
        out.append(pack(code >> 3, code & 7, sec))
    return out


def parse(text: str) -> list[int]:
    m = re.search(r"ev1:([A-Za-z0-9_-]+)", text)
    if m:
        return decode(m.group(1))
    m = re.search(r"\bev:\s*([-\d,\s]+)", text)
    if m:
        text = m.group(1)
    try:
        data = json.loads(text)
        if isinstance(data, list) and all(isinstance(x, int) for x in data):
            return data
    except ValueError:
        pass
    return [int(x) for x in re.findall(r"-?\d+", text)]


def listing(events: list[int], names=None) -> list[str]:
    lines = []
    for v in events:
        _, _, sec = unpack(v)
        mark = "▸" if unpack(v)[0] in INPUTS else " "
        lines.append(f"{sec:>7} s {mark} {describe(v, names)}")
    return lines


def monkeyc(events: list[int], name: str, names=None) -> str:
    ident = re.sub(r"\W", "_", name)
    if not ident or ident[0].isdigit():
        ident = "r_" + ident
    head = [f"//! Aus dem Feld (#510): {len(events)} Ereignisse, ▸ = gespielt.",
            "//! Erzeugt von tool/garmin_events.py — Zusicherungen von Hand dazu."]
    head += [f"//!  {line}" for line in listing(events, names)]
    nums = ", ".join(str(v) for v in events)
    body = f"""(:test)
function replay_{ident}(logger as Logger) as Boolean {{
    var h = new FakeHost();
    var c = TestReplay.play(h, [{nums}] as Array<Number>);
    logger.debug("Ende: Aufnahme " + c.log.state() + ", zu " + c.closing + ", frei " + c.free
        + ", ans Handy " + h.types() + ", Menü " + h.lastMenu());
    TestCore.done();
    return true;
}}
"""
    return "\n" + "\n".join(head) + "\n" + body


def self_test() -> None:
    names = msg_names()
    ins, outs = names
    assert ins[:3] == ["q", "wq", "wk"] and "b" in ins, ins
    assert outs[0] == "hi" and outs[11] == "w", outs
    # Dieselben Codes wie eventsMessageCodes in CoreTests.mc.
    assert ins.index("k") == 5 and outs.index("re") == 7
    for k, d, s in [(0, 1, 0), (10, 3, 0xFFFFFF), (31, 7, 5)]:
        assert unpack(pack(k, d, s)) == (k, d, s)
    # Pause → Verwerfen → Nein, wie eventsReplayPauseDiscardNo.
    ring = [pack(0, 0, 0), pack(8, 4, 0), pack(1, 0, 1), pack(8, 1, 1), pack(9, 1, 6),
            pack(1, 0, 31), pack(8, 2, 31), pack(6, 0, 31), pack(2, 2, 32), pack(2, 4, 33),
            pack(5, 1, 31), pack(3, 7, 40), pack(4, 0, 41), pack(4, 7, 42)]
    text = "\n".join(listing(ring, names))
    for want in ["Start: ohne Handy", "Taste: START", "Stand: Pause", "Menü: Verwerfen",
                 "Menü: Nein", "Fix: auf der Linie", "ans Handy x", "ans Handy rp",
                 "vom Handy r", "vom Handy b", "vom Handy ?"]:
        assert want in text, (want, text)
    assert parse("Uhr-Protokoll\nev: 1, 2,3\n") == [1, 2, 3]
    # Dieselbe Probe wie test/garmin/watch_events_test.dart (kSample).
    sample = ring[:10]
    assert encode(sample) == "ev1:AABEAAgBQQBJBQgZQgAwABIBFAE", encode(sample)
    assert parse("Uhr-Protokoll (10 Schritte): ev1:AABEAAgBQQBJBQgZQgAwABIBFAE") == sample
    long = [pack(i % 11, i % 8, i * 600) for i in range(120)]
    assert decode(encode(long)[4:]) == long
    assert parse("[134217728, -5]") == [134217728, -5]
    mc = monkeyc(ring, "2026-11-12 pause", names)
    assert "function replay_2026_11_12_pause" not in mc and "replay_r_2026_11_12_pause" in mc
    assert "TestReplay.play(h, [" in mc and "Menü: Nein" in mc
    print("garmin_events: Selbsttest ok")


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        self_test()
        return 0
    args = [a for a in argv if not a.startswith("--")]
    name = None
    if "--monkeyc" in argv:
        i = argv.index("--monkeyc")
        if i + 1 >= len(argv):
            print("--monkeyc braucht einen Namen", file=sys.stderr)
            return 2
        name = argv[i + 1]
        args = [a for a in args if a != name]
    if len(args) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    text = sys.stdin.read() if args[0] == "-" else Path(args[0]).read_text(encoding="utf-8")
    events = parse(text)
    if not events:
        print("keine Ereignisse gefunden", file=sys.stderr)
        return 1
    print(monkeyc(events, name) if name else "\n".join(listing(events)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
