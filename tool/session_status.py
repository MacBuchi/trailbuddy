#!/usr/bin/env python3
"""Lagebild zu Beginn einer Agenten-Sitzung (SessionStart-Hook).

Eingehängt in `.claude/settings.json`. Was dieses Skript ausgibt, steht im
Kontext, bevor die erste Anfrage kommt. Es beantwortet die Fragen, an denen
bisher Schleifen entstanden sind, BEVOR jemand Code schreibt:

- Liegt der Branch hinter `origin/main`? Dann zuerst neu aufsetzen — nach
  einem Squash-Merge trägt ein alter Branch den gemergten Commit doppelt.
- Liegt Unkommittiertes herum? Dann nichts per `git checkout` zurücknehmen.
- Welche offenen PRs bumpen ebenfalls die Version? Zwei Bump-PRs
  kollidieren zwangsläufig — der zweite muss nach dem Merge des ersten neu
  zählen (`BUILD` steigt nie zurück).

Übernommen aus PilzBuddy (#671), für TrailBuddy #237.

Jeder Netzschritt hat eine harte Grenze; ohne Netz oder ohne `gh` fällt die
betroffene Zeile weg, die Sitzung startet trotzdem. Das Skript wirft nie
und endet immer mit 0 — ein Hook, der scheitert, wäre ein Hindernis statt
einer Auskunft.

    python3 tool/session_status.py              # Lagebild
    python3 tool/session_status.py --self-test  # prüft die Auswertung
"""
import re
import subprocess
import sys

NET_TIMEOUT_S = 5


def run(args, timeout=NET_TIMEOUT_S):
    """stdout eines Befehls oder None bei Fehler/Zeitüberschreitung."""
    try:
        r = subprocess.run(args, capture_output=True, text=True,
                           timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout if r.returncode == 0 else None


def version_of(pubspec_text):
    m = re.search(r"^version:\s*(\S+)", pubspec_text or "", re.MULTILINE)
    return m.group(1) if m else None


def bump_prs(prs_json_lines):
    """Zeilen 'nummer<TAB>branch<TAB>1/0' -> Liste 'nummer (branch)'."""
    out = []
    for line in prs_json_lines:
        parts = line.split("\t")
        if len(parts) == 3 and parts[2] == "1":
            out.append(f"#{parts[0]} ({parts[1]})")
    return out


def prs_via_api(limit=10):
    """Dieselben Zeilen wie `gh pr list`, nur über `gh api`.

    In Cloud-Sitzungen ist `gh` ein eingebauter Client, der nur `gh api`
    kennt; ohne diesen Weg fehlte dort die Zeile zu den Bump-PRs still.
    `{owner}/{repo}` setzt `gh api` aus dem Remote ein.
    """
    heads = run(["gh", "api", "repos/{owner}/{repo}/pulls?state=open",
                 "--jq", r'.[] | "\(.number)\t\(.head.ref)"'])
    if heads is None:
        return None
    out = []
    for line in heads.splitlines()[:limit]:
        parts = line.split("\t")
        if len(parts) != 2:
            continue
        files = run(["gh", "api",
                     f"repos/{{owner}}/{{repo}}/pulls/{parts[0]}/files",
                     "--jq", '[.[].filename] | index("pubspec.yaml") != null'])
        if files is None:
            return None
        out.append(f"{parts[0]}\t{parts[1]}\t"
                   f"{'1' if files.strip() == 'true' else '0'}")
    return "\n".join(out)


def report(branch, fetched, behind, ahead, dirty, main_version, bumps):
    lines = ["Lagebild (tool/session_status.py)"]
    if branch is None:
        return "\n".join(lines + ["Kein Git-Repository erkannt."])
    state = f"Branch: {branch}"
    if not fetched:
        state += " — fetch übersprungen (kein Netz?), Stand ggf. alt"
    if behind:
        state += f" — {behind} Commit(s) hinter origin/main"
        if branch != "main":
            state += " → vor dem Coden neu aufsetzen (rebase/neu abzweigen)"
        else:
            state += " → git pull --ff-only"
    if ahead and branch == "main":
        state += f" — {ahead} lokale Commit(s) auf main (main ist geschützt!)"
    lines.append(state)
    if dirty:
        lines.append(f"Unkommittiert: {dirty} Datei(en) — nichts per "
                     "git checkout zurücknehmen, erst ansehen")
    if main_version:
        lines.append(f"Version auf origin/main: {main_version}")
    if bumps is not None:
        lines.append("Offene PRs mit Versions-Bump: "
                     + (", ".join(bumps) if bumps else "keine"))
    return "\n".join(lines)


def main():
    branch = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], timeout=2)
    if branch is None:
        print(report(None, False, 0, 0, 0, None, None))
        return
    branch = branch.strip()
    fetched = run(["git", "fetch", "--quiet", "origin", "main"]) is not None
    counts = run(["git", "rev-list", "--left-right", "--count",
                  "origin/main...HEAD"], timeout=2) or "0 0"
    behind, ahead = (int(x) for x in counts.split()[:2])
    status = run(["git", "status", "--porcelain"], timeout=3) or ""
    dirty = len([l for l in status.splitlines() if l.strip()])
    main_version = version_of(run(["git", "show", "origin/main:pubspec.yaml"],
                                  timeout=2))
    prs = run(["gh", "pr", "list", "--state", "open", "--json",
               "number,headRefName,files", "--jq",
               '.[] | "\\(.number)\\t\\(.headRefName)\\t'
               '\\(if ([.files[].path] | index("pubspec.yaml")) '
               'then 1 else 0 end)"'])
    if prs is None:
        prs = prs_via_api()
    bumps = bump_prs(prs.splitlines()) if prs is not None else None
    print(report(branch, fetched, behind, ahead, dirty, main_version, bumps))


def self_test():
    assert version_of("name: x\nversion: 1.2.3+4\n") == "1.2.3+4"
    assert version_of("") is None
    assert bump_prs(["12\tfeat/a\t1", "13\tfix/b\t0", "kaputt"]) == \
        ["#12 (feat/a)"]
    r = report("feat/x", True, 3, 1, 2, "1.2.3+4", ["#12 (feat/a)"])
    assert "3 Commit(s) hinter origin/main" in r and "neu aufsetzen" in r, r
    assert "Unkommittiert: 2" in r and "#12 (feat/a)" in r, r
    r = report("main", False, 0, 2, 0, None, None)
    assert "fetch übersprungen" in r and "main ist geschützt" in r, r
    assert "Offene PRs" not in r, r
    r = report("feat/y", True, 0, 0, 0, "1.0.0+1", [])
    assert "hinter" not in r and "Bump: keine" in r, r
    print("session_status self-test ok")


if __name__ == "__main__":
    try:
        if "--self-test" in sys.argv:
            self_test()
        else:
            main()
    except AssertionError:
        raise
    except Exception as e:  # noqa: BLE001 — ein Hook darf nie scheitern
        print(f"Lagebild nicht verfügbar: {e}")
