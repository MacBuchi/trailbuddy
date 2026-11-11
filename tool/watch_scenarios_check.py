#!/usr/bin/env python3
"""Feldszenarien der Uhr gegen den Fallkatalog (konzept-garmin 12.5).

`docs/watch_cases.json` hat neben den Fällen die Szenarien F1–F8 — was
ein Fahrer im Feld tut (`docs/konzept-geraete.md` 9). Jeder Schritt muss
sagen, womit er geprüft ist:

- `faelle`: Kennungen aus `faelle` (deren Prüfung hält
  `test/garmin/watch_cases_test.dart`),
- `geraet`: eine Messung oder Abnahme, die nur am Gerät geht,
- `offen`: die Issues, die den Schritt noch schulden.

Ohne eines davon ist der Lauf rot — eine Lücke soll einen Namen haben,
nicht unbemerkt bleiben. Gedruckt wird je Szenario, wie viele Schritte
geprüft, am Gerät zu messen und offen sind.

    python3 tool/watch_scenarios_check.py            (CI, ohne Netz)
    python3 tool/watch_scenarios_check.py --online   (fragt gh, ob die
                                                      genannten Issues
                                                      noch offen sind)
    python3 tool/watch_scenarios_check.py --self-test
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CASES = ROOT / "docs" / "watch_cases.json"


def problems(doc: dict) -> list[str]:
    """Was an den Szenarien nicht stimmt — leer heißt: in Ordnung."""
    out: list[str] = []
    known = {f.get("id") for f in doc.get("faelle", [])}
    scenarios = doc.get("szenarien")
    if not isinstance(scenarios, list) or not scenarios:
        return ["keine Szenarien in der Falldatei"]
    seen: set[str] = set()
    for sc in scenarios:
        sid = sc.get("id")
        if not isinstance(sid, str) or not sid:
            out.append("ein Szenario ohne Kennung")
            continue
        if sid in seen:
            out.append(f"{sid}: Kennung zweimal")
        seen.add(sid)
        if not sc.get("titel"):
            out.append(f"{sid}: ohne Titel")
        steps = sc.get("schritte")
        if not isinstance(steps, list) or not steps:
            out.append(f"{sid}: ohne Schritte")
            continue
        for n, step in enumerate(steps, 1):
            where = f"{sid} Schritt {n}"
            if not step.get("was"):
                out.append(f"{where}: sagt nicht, was der Fahrer tut")
            cases = step.get("faelle", [])
            open_ = step.get("offen", [])
            device = step.get("geraet")
            if not cases and not open_ and not device:
                out.append(f"{where}: weder Fall noch Messung noch offenes Issue")
            for c in cases:
                if c not in known:
                    out.append(f"{where}: den Fall {c} gibt es nicht")
            for i in open_:
                if not isinstance(i, int) or i <= 0:
                    out.append(f"{where}: `offen` nennt kein Issue ({i!r})")
            if device is not None and (not isinstance(device, str) or not device.strip()):
                out.append(f"{where}: `geraet` ist leer")
    return out


def summary(doc: dict) -> list[str]:
    lines: list[str] = []
    used: set[str] = set()
    for sc in doc["szenarien"]:
        steps = sc["schritte"]
        checked = sum(1 for s in steps if s.get("faelle") and not s.get("offen"))
        open_ = sum(1 for s in steps if s.get("offen"))
        device = sum(1 for s in steps if s.get("geraet"))
        for s in steps:
            used.update(s.get("faelle", []))
        issues = sorted({i for s in steps for i in s.get("offen", [])})
        tail = " (" + ", ".join(f"#{i}" for i in issues) + ")" if issues else ""
        lines.append(
            f"{sc['id']}  {len(steps)} Schritte: {checked} geprüft, "
            f"{open_} offen{tail}, {device} mit Messung am Gerät — {sc['titel']}"
        )
    loose = [f["id"] for f in doc["faelle"] if f["id"] not in used]
    lines.append(
        f"{len(doc['faelle']) - len(loose)} von {len(doc['faelle'])} Fällen hängen an einem Szenario"
        + (f"; ohne Szenario (Bausteine): {', '.join(loose)}" if loose else "")
    )
    return lines


def closed_issues(doc: dict) -> list[str]:
    """Issues, die ein Schritt als offen nennt, die es aber nicht mehr sind."""
    numbers = sorted({i for sc in doc["szenarien"] for s in sc["schritte"] for i in s.get("offen", [])})
    out: list[str] = []
    for n in numbers:
        try:
            state = subprocess.run(
                ["gh", "issue", "view", str(n), "--json", "state", "--jq", ".state"],
                capture_output=True, text=True, timeout=30, check=True, cwd=ROOT,
            ).stdout.strip()
        except (OSError, subprocess.SubprocessError) as e:
            out.append(f"#{n}: gh antwortet nicht ({type(e).__name__})")
            continue
        if state != "OPEN":
            out.append(f"#{n} ist {state} — der Schritt braucht jetzt einen Fall statt `offen`")
    return out


def self_test() -> int:
    good = {
        "faelle": [{"id": "1.1"}],
        "szenarien": [{"id": "F1", "titel": "t", "schritte": [
            {"was": "a", "faelle": ["1.1"]},
            {"was": "b", "offen": [7]},
            {"was": "c", "geraet": "Messung 8.3"},
        ]}],
    }
    assert problems(good) == [], problems(good)
    bad = json.loads(json.dumps(good))
    bad["szenarien"][0]["schritte"].append({"was": "d"})
    assert any("weder Fall" in p for p in problems(bad))
    bad = json.loads(json.dumps(good))
    bad["szenarien"][0]["schritte"][0]["faelle"] = ["9.9"]
    assert any("gibt es nicht" in p for p in problems(bad))
    bad = json.loads(json.dumps(good))
    bad["szenarien"][0]["schritte"][1]["offen"] = ["#7"]
    assert any("kein Issue" in p for p in problems(bad))
    bad = json.loads(json.dumps(good))
    bad["szenarien"].append(dict(bad["szenarien"][0]))
    assert any("zweimal" in p for p in problems(bad))
    assert problems({"faelle": []}) == ["keine Szenarien in der Falldatei"]
    assert "1 von 1 Fällen" in summary(good)[-1]
    print("watch_scenarios_check: Selbsttest in Ordnung")
    return 0


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()
    doc = json.loads(CASES.read_text(encoding="utf-8"))
    bad = problems(doc)
    if not bad and "--online" in argv:
        bad = closed_issues(doc)
    if bad:
        for p in bad:
            print(f"FEHLT {p}", file=sys.stderr)
        return 1
    for line in summary(doc):
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
