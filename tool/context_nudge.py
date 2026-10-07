#!/usr/bin/env python3
"""Sagt dem Betreiber, wann /clear oder /compact sich lohnt (Claude-Code-Hook).

Der Agent kann /clear und /compact nicht selbst auslösen, kein Hook kann
es (Claude-Code-Doku, Stand 2026-10-06). Was geht: im richtigen Moment
sagen, dass es Zeit ist — mit der ECHTEN Kontextgröße statt einer
Schätzung. Jede Anfrage schickt den ganzen bisherigen Verlauf mit; am
2026-10-06 stand eine Sitzung hier bei 352 000 Tokens, und auch eine
Ein-Zeilen-Frage las sie komplett.

Zwei Einhängepunkte in `.claude/settings.json`:

- `prompt` (UserPromptSubmit): liest aus dem Transkript, wie groß der
  Kontext beim letzten Aufruf war und wie lange er her ist. Meldet sich,
  wenn der Kontext eine neue 100k-Stufe ab KONTEXT_WARN erreicht, oder
  nach einer Pause über PAUSE_MIN (dann ist der Cache kalt, und die
  nächste Anfrage verarbeitet alles neu). Höchstens einmal je Stufe bzw.
  Pause — ein Hinweis bei jeder Eingabe wäre Lärm.
- `pr` (PostToolUse, Bash): nach `gh pr create`. Ein fertiger PR ist der
  natürliche Schnitt: Die Ordner-CLAUDE.md und das Lagebild bringen beim
  nächsten Mal den nötigen Kontext von selbst mit.

`systemMessage` sieht der Betreiber, `additionalContext` der Agent — so
kann er den Rat am Ende seiner Antwort wiederholen, wenn die Aufgabe
wirklich abgeschlossen ist. Das Skript wirft nie und endet immer mit 0.

    python3 tool/context_nudge.py prompt < hook-input.json
    python3 tool/context_nudge.py pr     < hook-input.json
    python3 tool/context_nudge.py --self-test

Übernommen aus PilzBuddy (#671), für TrailBuddy #237.
"""
import datetime as dt
import json
import os
import pathlib
import sys
import tempfile

KONTEXT_WARN = 200_000   # ab hier je 100k-Stufe ein Hinweis
KONTEXT_STUFE = 100_000
PAUSE_MIN = 60           # Cache-Lebensdauer im Abo: eine Stunde
PAUSE_KONTEXT = 60_000   # kleiner Kontext nach Pause ist kein Thema


def context_state(transcript_lines):
    """(Kontext-Tokens, Zeitpunkt) des letzten Agenten-Aufrufs oder None."""
    last = None
    for line in transcript_lines:
        try:
            d = json.loads(line)
        except ValueError:
            continue
        usage = (d.get("message") or {}).get("usage") if isinstance(d, dict) else None
        if d.get("type") == "assistant" and usage:
            last = d
    if last is None:
        return None
    u = last["message"]["usage"]
    tokens = sum(u.get(k) or 0 for k in (
        "input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
    when = None
    ts = last.get("timestamp")
    if ts:
        try:
            when = dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))
        except ValueError:
            pass
    return tokens, when


def prompt_advice(tokens, idle_min, last_level):
    """(Text für den Betreiber, Text für den Agenten, neue Stufe) oder None."""
    k = tokens // 1000
    if idle_min is not None and idle_min >= PAUSE_MIN and tokens >= PAUSE_KONTEXT:
        user = (f"Kontext {k}k nach {int(idle_min)} min Pause: Der Cache ist kalt, "
                "diese Anfrage verarbeitet alles neu. Neue Aufgabe? Dann zuerst "
                "/clear. Geht es weiter: /compact.")
        agent = (f"Kontext {k}k, {int(idle_min)} min Pause. Ist die Anfrage eine "
                 "neue Aufgabe, dem Betreiber in einem Satz /clear empfehlen.")
        return user, agent, None
    level = tokens // KONTEXT_STUFE
    if tokens >= KONTEXT_WARN and level > (last_level or 0):
        user = (f"Kontext jetzt {k}k Tokens — jede Anfrage liest das komplett. "
                "Aufgabe fertig: /clear. Gleiche Aufgabe: /compact.")
        agent = (f"Kontext {k}k. Wenn die laufende Aufgabe mit dieser Antwort "
                 "abgeschlossen ist, am Ende /clear empfehlen; "
                 "läuft sie weiter, /compact.")
        return user, agent, level
    return None


def creates_pr(command):
    """`gh pr create` oder — in Cloud-Sitzungen, wo `gh` nur `gh api` kennt —
    ein POST auf `…/pulls`."""
    c = command or ""
    if "gh pr create" in c:
        return True
    return ("gh api" in c and "/pulls" in c
            and ("-X POST" in c or "--method POST" in c))


def pr_advice(command):
    if not creates_pr(command):
        return None
    return ("PR angelegt. Ist die Aufgabe damit fertig: /clear — "
            "Ordner-CLAUDE.md und Lagebild bringen den Kontext beim "
            "nächsten Mal mit. /compact nur, wenn es mit derselben Aufgabe "
            "weitergeht.")


def _state_file(session_id):
    safe = "".join(c for c in (session_id or "x") if c.isalnum() or c == "-")
    return pathlib.Path(tempfile.gettempdir()) / f"trailbuddy-context-nudge-{safe}"


def _emit(event, user, agent=None):
    out = {"systemMessage": user}
    if agent:
        out["hookSpecificOutput"] = {"hookEventName": event,
                                     "additionalContext": agent}
    print(json.dumps(out, ensure_ascii=False))


def run_prompt(data):
    path = data.get("transcript_path")
    if not path or not os.path.isfile(path):
        return
    with open(path, encoding="utf-8", errors="ignore") as f:
        state = context_state(f)
    if state is None:
        return
    tokens, when = state
    idle = None
    if when is not None:
        idle = (dt.datetime.now(dt.timezone.utc) - when).total_seconds() / 60
    sf = _state_file(data.get("session_id"))
    try:
        last_level = int(sf.read_text())
    except (OSError, ValueError):
        last_level = 0
    advice = prompt_advice(tokens, idle, last_level)
    if advice is None:
        return
    user, agent, level = advice
    if level is not None:
        try:
            sf.write_text(str(level))
        except OSError:
            pass
    _emit("UserPromptSubmit", user, agent)


def run_pr(data):
    text = pr_advice((data.get("tool_input") or {}).get("command"))
    if text:
        _emit("PostToolUse", text)


def self_test():
    now = dt.datetime(2026, 10, 6, 20, 0, tzinfo=dt.timezone.utc)
    line = lambda t, ts: json.dumps({"type": "assistant", "timestamp": ts,
        "message": {"usage": {"input_tokens": 2, "cache_read_input_tokens": t,
                              "cache_creation_input_tokens": 1000}}})
    st = context_state(["kaputt", line(5000, "2026-10-06T18:00:00Z"),
                        json.dumps({"type": "user"}),
                        line(250000, "2026-10-06T19:50:00Z")])
    assert st[0] == 251002 and st[1] == now - dt.timedelta(minutes=10), st
    assert context_state([json.dumps({"type": "user"})]) is None
    # kleine Sitzung, kurze Pause: still
    assert prompt_advice(50_000, 5, 0) is None
    # Schwelle überschritten: einmal je Stufe
    a = prompt_advice(251_002, 5, 0)
    assert a and "251k" in a[0] and a[2] == 2, a
    assert prompt_advice(260_000, 5, 2) is None
    assert prompt_advice(310_000, 5, 2)[2] == 3
    # unter der Schwelle trotz Stufe 1: still
    assert prompt_advice(150_000, 5, 0) is None
    # Pause mit nennenswertem Kontext: immer, ohne Stufe zu verbrauchen
    p = prompt_advice(80_000, 75, 0)
    assert p and "Pause" in p[0] and p[2] is None, p
    assert prompt_advice(30_000, 300, 0) is None
    # PR
    assert "PR angelegt" in pr_advice("git push && gh pr create --title x")
    assert pr_advice("gh pr view 12") is None and pr_advice(None) is None
    assert pr_advice("gh api -X POST repos/o/r/pulls --input pr.json")
    assert pr_advice("gh api repos/o/r/pulls/12") is None
    # Kein /rename im Rat: In Cloud-Sitzungen gibt es kein /resume, und
    # nach /clear trüge die NÄCHSTE Aufgabe den Namen der alten.
    texts = [pr_advice("gh pr create")]
    for adv in (prompt_advice(251_002, 5, 0), prompt_advice(80_000, 75, 0)):
        texts += [adv[0], adv[1]]
    assert all("/rename" not in t for t in texts), texts
    print("context_nudge self-test ok")


def main():
    if "--self-test" in sys.argv:
        self_test()
        return
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return
    if mode == "prompt":
        run_prompt(data)
    elif mode == "pr":
        run_pr(data)


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        self_test()
    else:
        try:
            main()
        except Exception:  # noqa: BLE001 — ein Hook darf nie scheitern
            pass
