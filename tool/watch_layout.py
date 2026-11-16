#!/usr/bin/env python3
"""Die Layoutzahlen der Uhr aus EINER Quelle (#511, Prüfleiter S4).

`tool/watch_layout.json` hält jede Lage, jeden Radius und jede
Schriftstufe der Ansicht (`garmin/source/NavView.mc`, `Ring.mc`) für die
240er Anzeige und sagt, wie sie für andere Größen umgerechnet werden.
In den Monkey-C-Dateien steht vor jeder solchen Zahl eine Marke
`/*L:name*/` (Schriftstufe: `/*F:name*/Graphics.FONT_…`) — der Kommentar
kostet auf der Uhr nichts, eine Konstante mehr dagegen dauerhaft Speicher
im Debug-Bau (garmin/CLAUDE.md, „Speicher im Gerätebau"). Dieses Skript
schreibt die Werte hinter die Marken; das Dart-Abbild
(`test/garmin/watch_twin.dart`) liest dieselbe JSON.

  python3 tool/watch_layout.py            Werte in die .mc-Dateien schreiben
  python3 tool/watch_layout.py --check    nur prüfen (CI): jede Marke = JSON,
                                          jeder Eintrag der JSON hat eine Marke
  python3 tool/watch_layout.py --self-test

Für `tool/watch_fonts.sh` (Schriftmaße aus dem Simulator):
  --fonts-source                          Monkey-C-Test, der misst
  --fonts-parse LOG --device D --out F    seine Ausgabe → tool/watch_fonts/D.json
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LAYOUT = ROOT / "tool" / "watch_layout.json"
FONT_STEPS = ["xtiny", "tiny", "small", "medium", "large", "numberMedium"]
FONT_CONST = {
    "xtiny": "Graphics.FONT_XTINY",
    "tiny": "Graphics.FONT_TINY",
    "small": "Graphics.FONT_SMALL",
    "medium": "Graphics.FONT_MEDIUM",
    "large": "Graphics.FONT_LARGE",
    "numberMedium": "Graphics.FONT_NUMBER_MEDIUM",
}
# Was die Uhr an Zeichen zeigen kann: ASCII, Latin-1 (Trailnamen kommen
# von Nutzern) und die Zeichen, die der Code selbst setzt.
CHARS = (
    "".join(chr(c) for c in range(32, 127))
    + "".join(chr(c) for c in range(0xC0, 0x100))
    + "…·°–’"
)
# Ganze Sätze als Gegenprobe: Ist die Breite des Satzes die Summe seiner
# Zeichen (keine Unterschneidung), reicht die Tabelle je Zeichen.
PROBES = [
    "Schlosswald-Trail",
    "NEBEN DER ROUTE",
    "12,3 km · 45 min",
    "START: AUFNAHME",
    "Route ab deiner Position?",
    "WAVY Tr. Äöüß",
]
MARK = re.compile(r"/\*([LFS]):([A-Za-z0-9_]+)\*/\s*(-?\d+|Graphics\.FONT_[A-Z_]+)")
SYMBOLS_MC = ROOT / "garmin" / "source" / "Symbols.mc"


def load_layout() -> dict:
    return json.loads(LAYOUT.read_text(encoding="utf-8"))


def mc_files(layout: dict) -> list[Path]:
    return [ROOT / f for f in layout["files"]]


def scan(text: str) -> list[tuple[str, str, str, int, int]]:
    """(art, name, wert, start, ende) jeder Marke; start/ende des Werts."""
    out = []
    for m in MARK.finditer(text):
        out.append((m.group(1), m.group(2), m.group(3), m.start(3), m.end(3)))
    return out


def expected(layout: dict, kind: str, name: str) -> str | None:
    if kind == "S":
        names = layout["symbols"]["list"]
        return str(names.index(name)) if name in names else None
    if kind == "L":
        v = layout["values"].get(name)
        return None if v is None else str(v["v"])
    f = layout["fonts"].get(name)
    return None if f is None else FONT_CONST[f]


def apply(layout: dict, write: bool) -> list[str]:
    errors: list[str] = []
    seen: set[tuple[str, str]] = set()
    for path in mc_files(layout):
        text = path.read_text(encoding="utf-8")
        marks = scan(text)
        if not marks:
            errors.append(f"{path.relative_to(ROOT)}: keine Marke /*L:…*/")
        new = text
        for kind, name, value, start, end in reversed(marks):
            seen.add((kind, name))
            want = expected(layout, kind, name)
            if want is None:
                errors.append(f"{path.relative_to(ROOT)}: Marke {kind}:{name} fehlt in watch_layout.json")
                continue
            if value != want:
                if write:
                    new = new[:start] + want + new[end:]
                else:
                    errors.append(
                        f"{path.relative_to(ROOT)}: {kind}:{name} ist {value}, watch_layout.json sagt {want}"
                        " — python3 tool/watch_layout.py")
        if write and new != text:
            path.write_text(new, encoding="utf-8")
            print(f"geschrieben: {path.relative_to(ROOT)}")
    want = symbols_source(layout)
    have = SYMBOLS_MC.read_text(encoding="utf-8") if SYMBOLS_MC.exists() else ""
    if have != want:
        if write:
            SYMBOLS_MC.write_text(want, encoding="utf-8")
            print(f"geschrieben: {SYMBOLS_MC.relative_to(ROOT)}")
        else:
            errors.append(f"{SYMBOLS_MC.relative_to(ROOT)} weicht von watch_layout.json ab — python3 tool/watch_layout.py")
    for name in layout["values"]:
        if ("L", name) not in seen:
            errors.append(f"watch_layout.json: values.{name} hat keine Marke /*L:{name}*/")
    for name in layout["fonts"]:
        if ("F", name) not in seen:
            errors.append(f"watch_layout.json: fonts.{name} hat keine Marke /*F:{name}*/")
    for name, f in layout["fonts"].items():
        if f not in FONT_CONST:
            errors.append(f"watch_layout.json: fonts.{name} = {f}, erlaubt {sorted(FONT_CONST)}")
    return errors


# --- Zeichen (#558) -----------------------------------------------------------

def symbols_source(layout: dict) -> str:
    """`garmin/source/Symbols.mc`: je Zeichen EINE Zeichenkette (Befehl,
    Farbe, Zahlen als Zeichen ab „0“) und ein kleiner Leser. Gerade
    Zeichenbefehle je Zeichen kosteten im Debug-Bau gut 5 KB neben der
    Route — jede Anweisung und jede Konstante bleibt dort dauerhaft im
    Speicher (garmin/CLAUDE.md, „Speicher im Gerätebau"). Die Nummer ist
    die Stelle in `symbols.list`; in NavView steht `/*S:name*/<nummer>`."""
    sy = layout["symbols"]
    names = sy["list"]
    wide = [i for i, n in enumerate(names) if sy["def"][n]["w"] != 16]
    cond = " || ".join(f"id == {i}" for i in wide) or "false"
    wide_w = sy["def"][names[wide[0]]]["w"] if wide else 16
    out = [
        "// ERZEUGT von tool/watch_layout.py aus tool/watch_layout.json (symbols) — nie von Hand (#558).",
        "import Toybox.Graphics;",
        "import Toybox.Lang;",
        "",
        "//! Die Zeichen der Uhr, 16 px hoch, aus Fläche, Kreis, Linie und Vieleck.",
        "//! Je Befehl: Art (p Vieleck, r Rechteck, c Kreis, o Ring, l Linie), Farbe",
        "//! (m die gereichte, r Lime), dann die Zahlen je ein Zeichen, Wert + „0“.",
        "module TbSym {",
        "    //! Breite des Zeichens [id].",
        "    function width(id as Number) as Number {",
        f"        return {cond} ? {wide_w} : 16;",
        "    }",
        "",
        "    function code(id as Number) as String {",
    ]
    for i, n in enumerate(names):
        enc = []
        for op in sy["def"][n]["ops"]:
            kind, col, a = op[0], op[1], op[2:]
            if kind == "p":
                a = [len(a) // 2] + a
            elif kind not in ("r", "c", "o", "l"):
                raise SystemExit(f"watch_layout.json: symbols.{n}: unbekannte Operation {kind}")
            if any(v < 0 or v > 70 for v in a):
                raise SystemExit(f"watch_layout.json: symbols.{n}: Zahl außerhalb 0..70")
            enc.append(kind + col + "".join(chr(48 + v) for v in a))
        text = "".join(enc).replace("\\", "\\\\").replace('"', '\\"')
        out.append(f'        {"if" if i == 0 else "} else if"} (id == {i}) {{  // {n}')
        out.append(f'            return "{text}";')
    out += [
        "        }",
        '        return "";',
        "    }",
        "",
        "    function v(s as Array<Char>, i as Number) as Number {",
        "        return s[i].toNumber() - 48;",
        "    }",
        "",
        "    //! Zeichnet [id] mit der linken oberen Ecke bei [x], [y]; [c] ist die",
        "    //! Farbe der Teile „m“, Lime bleibt Lime.",
        "    function draw(dc as Dc, id as Number, x as Number, y as Number, c as Number) as Void {",
        "        var s = code(id).toCharArray();",
        "        var n = s.size();",
        "        var i = 0;",
        "        while (i < n) {",
        "            var k = s[i];",
        "            dc.setColor(s[i + 1] == 'm' ? c : TbColors.ROUTE, Graphics.COLOR_TRANSPARENT);",
        "            i += 2;",
        "            if (k == 'p') {",
        "                var pts = [] as Array<[Numeric, Numeric]>;",
        "                var cnt = v(s, i);",
        "                i++;",
        "                for (var j = 0; j < cnt; j++) {",
        "                    pts.add([x + v(s, i), y + v(s, i + 1)]);",
        "                    i += 2;",
        "                }",
        "                dc.fillPolygon(pts);",
        "            } else if (k == 'r') {",
        "                dc.fillRectangle(x + v(s, i), y + v(s, i + 1), v(s, i + 2), v(s, i + 3));",
        "                i += 4;",
        "            } else if (k == 'c') {",
        "                dc.fillCircle(x + v(s, i), y + v(s, i + 1), v(s, i + 2));",
        "                i += 3;",
        "            } else if (k == 'o') {",
        "                dc.setPenWidth(v(s, i + 3));",
        "                dc.drawCircle(x + v(s, i), y + v(s, i + 1), v(s, i + 2));",
        "                i += 4;",
        "            } else {",
        "                dc.setPenWidth(v(s, i + 4));",
        "                dc.drawLine(x + v(s, i), y + v(s, i + 1), x + v(s, i + 2), y + v(s, i + 3));",
        "                i += 5;",
        "            }",
        "        }",
        "        dc.setPenWidth(1);",
        "    }",
        "}",
        "",
    ]
    return "\n".join(out)


# --- Schriftmaße -------------------------------------------------------------

def mc_string(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def fonts_source() -> str:
    fonts = ", ".join(FONT_CONST[f] for f in FONT_STEPS)
    names = ", ".join(mc_string(f) for f in FONT_STEPS)
    probes = ", ".join(mc_string(p) for p in PROBES)
    return f"""// Erzeugt von tool/watch_layout.py --fonts-source (tool/watch_fonts.sh), nie im Repo.
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;
import Toybox.WatchUi;

class FontsApp extends Application.AppBase {{
    function initialize() {{ AppBase.initialize(); }}
    function getInitialView() {{ return [new WatchUi.View()]; }}
}}

(:test)
function fontMetrics(logger as Test.Logger) as Boolean {{
    var bmp = null;
    if (Graphics has :createBufferedBitmap) {{
        bmp = Graphics.createBufferedBitmap({{:width => 8, :height => 8}}).get();
    }} else {{
        bmp = new Graphics.BufferedBitmap({{:width => 8, :height => 8}});
    }}
    var dc = (bmp as Graphics.BufferedBitmap).getDc();
    var fonts = [{fonts}];
    var names = [{names}];
    var chars = {mc_string(CHARS)}.toCharArray();
    var probes = [{probes}];
    var screen = System.getDeviceSettings().screenWidth;
    System.println("TBW " + screen);
    for (var i = 0; i < fonts.size(); i++) {{
        var f = fonts[i];
        System.println("TBF " + names[i] + " " + dc.getFontHeight(f) + " "
            + Graphics.getFontAscent(f) + " " + Graphics.getFontDescent(f));
        var line = "TBC " + names[i];
        for (var k = 0; k < chars.size(); k++) {{
            line = line + " " + dc.getTextWidthInPixels(chars[k].toString(), f);
            if (k % 48 == 47) {{
                System.println(line);
                line = "TBC " + names[i];
            }}
        }}
        System.println(line);
        for (var p = 0; p < probes.size(); p++) {{
            System.println("TBS " + names[i] + " " + p + " " + dc.getTextWidthInPixels(probes[p], f));
        }}
    }}
    System.println("TBEND");
    return true;
}}
"""


def fonts_parse(log: Path, device: str, out: Path) -> None:
    lines = log.read_text(encoding="utf-8", errors="replace").splitlines()
    if not any(l.startswith("TBEND") for l in lines):
        sys.exit(f"{log}: keine vollständige Messung (TBEND fehlt) — Simulator bereit?")
    screen = None
    fonts: dict[str, dict] = {}
    for l in lines:
        p = l.split(" ")
        if p[0] == "TBW":
            screen = int(p[1])
        elif p[0] == "TBF":
            fonts[p[1]] = {"height": int(p[2]), "ascent": int(p[3]), "descent": int(p[4]), "w": []}
        elif p[0] == "TBC":
            fonts[p[1]]["w"].extend(int(x) for x in p[2:])
        elif p[0] == "TBS":
            fonts[p[1]].setdefault("probes", {})[int(p[2])] = int(p[3])
    report = []
    for name, f in fonts.items():
        if len(f["w"]) != len(CHARS):
            sys.exit(f"{name}: {len(f['w'])} Breiten, {len(CHARS)} Zeichen erwartet")
        widths = dict(zip(CHARS, f["w"]))
        for i, probe in enumerate(PROBES):
            got = f["probes"][i]
            summed = sum(widths[c] for c in probe)
            if got != summed:
                report.append(f"{name} „{probe}“: Satz {got}, Summe {summed}")
        f["chars"] = {c: w for c, w in widths.items()}
        del f["w"]
        del f["probes"]
    data = {
        "_": "Gemessen von tool/watch_fonts.sh im Connect-IQ-Simulator (#511). Nicht von Hand ändern.",
        "device": device,
        "screen": screen,
        "kerning": report,
        "fonts": fonts,
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    print(f"{device}: {screen} px, {len(fonts)} Schriften → {out.relative_to(ROOT)}")
    for r in report:
        print(f"  Satz ≠ Summe: {r}")


# --- Selbsttest -------------------------------------------------------------

def self_test() -> None:
    text = "a = /*L:pos_y*/128; f = /*F:field_name*/Graphics.FONT_TINY; b = /*L:neg*/-4;"
    marks = scan(text)
    assert [(k, n, v) for k, n, v, _, _ in marks] == [
        ("L", "pos_y", "128"), ("F", "field_name", "Graphics.FONT_TINY"), ("L", "neg", "-4")], marks
    layout = {"values": {"pos_y": {"v": 130}, "neg": {"v": -4}}, "fonts": {"field_name": "xtiny"}}
    assert expected(layout, "L", "pos_y") == "130"
    assert expected(layout, "F", "field_name") == "Graphics.FONT_XTINY"
    assert expected(layout, "L", "nope") is None
    assert len(set(CHARS)) == len(CHARS), "Zeichen doppelt"
    src = fonts_source()
    assert "TBEND" in src and "fontMetrics" in src
    print("watch_layout.py: Selbsttest grün")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--fonts-source", action="store_true")
    ap.add_argument("--fonts-parse", type=Path)
    ap.add_argument("--device")
    ap.add_argument("--out", type=Path)
    a = ap.parse_args()
    if a.self_test:
        self_test()
        return
    if a.fonts_source:
        sys.stdout.write(fonts_source())
        return
    if a.fonts_parse:
        fonts_parse(a.fonts_parse, a.device, a.out)
        return
    errors = apply(load_layout(), write=not a.check)
    for e in errors:
        print(e, file=sys.stderr)
    if errors:
        sys.exit(1)
    if a.check:
        print("watch_layout.json und die Marken in garmin/source stimmen überein")


if __name__ == "__main__":
    main()
