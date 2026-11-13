#!/usr/bin/env python3
"""Der Gesprächskatalog der Uhr als Monkey-C-Tests (#509, Prüfleiter S3).

`docs/watch_cases.json` → `gespraeche`: Jedes Gespräch spielt beide Seiten.
Die des Handys spielt `test/garmin/watch_talks_test.dart` gegen den echten
WatchSync; die der Uhr steht hier erzeugt in
`garmin/source/GeneratedTalks.mc` — je Gespräch eine `(:test)`-Funktion
`talk_<id>`, die ihre Schritte dem Spieler `TestTalk` in `CoreTests.mc`
gibt (gegen den Ablaufkern und `FakeHost`, #508).

Die Datei ist ERZEUGT und eingecheckt: `tool/generated_assets.py --check`
(CI) prüft, dass sie ein Fixpunkt dieses Skripts ist — ein Gespräch, das
im Katalog dazukam, ohne neu zu erzeugen, ist rot.

    python3 tool/watch_talks.py              GeneratedTalks.mc neu schreiben
    python3 tool/watch_talks.py --check      nur prüfen (Exit 1, wenn alt)
    python3 tool/watch_talks.py --self-test

Hier wird übersetzt und geprüft, was die Uhr-Seite versteht: Handlungen
werden zu kurzen Kennungen (`ZURÜCK` → `back`), `fixe A-B` zu zwei Zahlen,
und eine unbekannte Handlung oder ein unbekannter Stand der Uhr ist ein
Fehler HIER — nicht erst im Simulator, den CI nicht hat.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CASES = ROOT / "docs" / "watch_cases.json"
OUT = ROOT / "garmin" / "source" / "GeneratedTalks.mc"

# Die Handlungen der Uhr (`gespraeche_form.handlungen_uhr`) → Kennung des
# Spielers in CoreTests.mc (`TestTalk.act`).
ACTIONS = {
    "start": "start",
    "neustart": "restart",
    "START": "startKey",
    "ZURÜCK": "back",
    "Weiter": "resume",
    "Speichern": "save",
    "Verwerfen": "discard",
    "Ja": "discardYes",
    "Behalten": "keep",
    "beenden": "quit",
    "Route beenden": "endRoute",
}
FIXES = re.compile(r"^fixe (\d+)-(\d+)$")

# Die Stände der Uhr (`gespraeche_form.staende_uhr`), die `TestTalk.check`
# kennt; `route:$x` nimmt eine Kennung.
STATES = {"wartet", "route_kommt", "frei", "fragt", "nimmt_auf", "pause", "zu",
          "keine_fahrt", "fahrt_wartet", "bestwerte", "erkennt", "erkennt_nicht", "hinweis"}

# Der Aufbau der Uhr (`gespraeche_form.uhr_aufbau`); `bad:$x` nimmt eine
# Kennung.
SETUPS = {"handy", "geladen", "ohne_route", "fahrt"}


def function_name(talk_id: str) -> str:
    """Wie `talkFunction` in test/garmin/watch_talks_test.dart."""
    return "talk_" + talk_id.replace("-", "_")


def _states(value) -> list[str]:
    if value is None:
        return []
    return value if isinstance(value, list) else [value]


def watch_steps(talk: dict) -> list[dict]:
    """Die Schritte, wie die Uhr sie spielt — übersetzt und geprüft."""
    tid = talk["id"]
    for s in talk.get("uhr", []):
        if s not in SETUPS and not s.startswith("bad:"):
            raise ValueError(f"{tid}: unbekannter Aufbau der Uhr „{s}“")
    out: list[dict] = []
    for n, step in enumerate(talk["schritte"], 1):
        where = f"{tid} Schritt {n}"
        side = step.get("von")
        if side not in ("handy", "uhr"):
            raise ValueError(f"{where}: `von` ist weder handy noch uhr")
        w: dict = {"von": side}
        tu = step.get("tu")
        if side == "uhr" and tu is not None:
            m = FIXES.match(tu)
            if m:
                w["tu"] = "fixes"
                w["fa"], w["fb"] = int(m.group(1)), int(m.group(2))
            elif tu in ACTIONS:
                w["tu"] = ACTIONS[tu]
            else:
                raise ValueError(f"{where}: unbekannte Handlung der Uhr „{tu}“")
        # Die Handlungen des Handys sieht die Uhr nicht, nur die Nachricht.
        if "msg" in step:
            msg = step["msg"]
            if not isinstance(msg, dict) or not isinstance(msg.get("t"), str):
                raise ValueError(f"{where}: `msg` ohne Art `t`")
            w["msg"] = msg
        if step.get("gleich"):
            w["gleich"] = step["gleich"]
        if step.get("verloren"):
            w["verloren"] = True
        if step.get("still"):
            w["still"] = True
        if step.get("nach_ms"):
            w["nach_ms"] = int(step["nach_ms"])
        states = _states((step.get("dann") or {}).get("uhr"))
        for st in states:
            if st not in STATES and not st.startswith("route:"):
                raise ValueError(f"{where}: unbekannter Stand der Uhr „{st}“")
        if states:
            w["dann"] = states
        out.append(w)
    return out


def mc(value) -> str:
    """Ein JSON-Wert als Monkey-C-Literal."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "[" + ", ".join(mc(v) for v in value) + "]"
    if isinstance(value, dict):
        return "{" + ", ".join(f"{json.dumps(k)} => {mc(v)}" for k, v in value.items()) + "}"
    raise ValueError(f"kein Monkey-C-Literal für {value!r}")


def render(doc: dict) -> str:
    lines = [
        "// ERZEUGT von tool/watch_talks.py aus docs/watch_cases.json (`gespraeche`)",
        "// — nie von Hand ändern: Gespräch im Katalog ändern, dann",
        "// `python3 tool/watch_talks.py` und `python3 tool/generated_assets.py --update`.",
        "// Die Seite der Uhr (#509, Prüfleiter S3); der Spieler ist `TestTalk` in",
        "// CoreTests.mc, die Seite des Handys test/garmin/watch_talks_test.dart.",
        "import Toybox.Lang;",
        "import Toybox.Test;",
        "",
    ]
    for talk in doc.get("gespraeche", []):
        if talk.get("nur") == "handy":
            continue
        steps = watch_steps(talk)
        lines.append(f"//! {talk['titel']}")
        lines.append("(:test)")
        lines.append(f"function {function_name(talk['id'])}(logger as Logger) as Boolean {{")
        lines.append(f"    return TestTalk.play({mc(talk['id'])}, {mc(talk.get('uhr', []))} as Array<String>, [")
        for i, s in enumerate(steps):
            comma = "," if i + 1 < len(steps) else ""
            lines.append(f"        {mc(s)}{comma}")
        lines.append("    ] as Array<Dictionary>);")
        lines.append("}")
        lines.append("")
    return "\n".join(lines)


def self_test() -> int:
    doc = {"gespraeche": [
        {"id": "a-b", "titel": "T", "uhr": ["handy"], "schritte": [
            {"von": "uhr", "tu": "start", "msg": {"t": "hi", "v": 2}, "gleich": ["v"], "dann": {"uhr": "wartet"}},
            {"von": "handy", "tu": "navigation", "msg": {"t": "n", "id": "$a", "np": 2}, "nach_ms": 500},
            {"von": "uhr", "tu": "fixe 0-10", "dann": {"uhr": ["route:$a", "frei"]}},
        ]},
        {"id": "nur", "titel": "N", "nur": "handy", "uhr": ["handy"], "schritte": [{"von": "handy", "tu": "x"}]},
    ]}
    out = render(doc)
    assert "function talk_a_b(logger as Logger) as Boolean {" in out, out
    assert "talk_nur" not in out
    assert '"tu" => "fixes", "fa" => 0, "fb" => 10' in out, out
    assert '"dann" => ["wartet"]' in out
    assert '"msg" => {"t" => "n", "id" => "$a", "np" => 2}, "nach_ms" => 500' in out, out
    # Die Handlung des Handys geht nicht hinüber.
    assert "navigation" not in out
    for bad in ({"tu": "Tanzen"}, {"dann": {"uhr": "schläft"}}):
        broken = json.loads(json.dumps(doc))
        broken["gespraeche"][0]["schritte"][0].update(bad)
        try:
            render(broken)
        except ValueError:
            continue
        raise AssertionError(f"{bad} nicht beanstandet")
    assert mc(True) == "true" and mc("ä") == '"ä"' and mc([1, "x"]) == '[1, "x"]'
    print("watch_talks: Selbsttest in Ordnung")
    return 0


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()
    try:
        text = render(json.loads(CASES.read_text(encoding="utf-8")))
    except ValueError as e:
        print(f"watch_talks: {e}", file=sys.stderr)
        return 1
    if "--check" in argv:
        if not OUT.exists() or OUT.read_text(encoding="utf-8") != text:
            print(f"{OUT.relative_to(ROOT)} ist nicht aktuell: python3 tool/watch_talks.py", file=sys.stderr)
            return 1
        return 0
    OUT.write_text(text, encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)} geschrieben")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
