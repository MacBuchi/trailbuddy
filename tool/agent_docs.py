#!/usr/bin/env python3
"""Hält die verteilten Agenten-Regeln zusammen.

Der Kern steht in CLAUDE.md, die Technik-Notizen je Ordner in einer eigenen
CLAUDE.md neben dem Code (2026-10-06, #237; übernommen aus PilzBuddy #670).
Vorher waren es 141 KB in EINER Datei, die jede Sitzung ganz geladen hat.

Zwei Dinge halten das nur, wenn etwas sie prüft:
- Der Index in CLAUDE.md ist der einzige Weg, auf dem Codex (und ein Agent,
  der den Ordner noch nicht geöffnet hat) eine Teildatei findet. Eine
  Teildatei ohne Index-Zeile ist für sie unsichtbar, eine Index-Zeile ohne
  Datei ein Verweis ins Leere.
- Die Root-Datei wächst sonst still zurück: Neues Wissen landet dort, wo
  man gerade schreibt.

Absichtlich in tool/ und nicht als Dart-Test: Eine Datei unter test/ löste
den Version Guard aus, und eine reine Doku-Änderung bräuchte dann einen
Versions-Bump samt Changelog-Eintrag.

    python3 tool/agent_docs.py              # prüft das Repo
    python3 tool/agent_docs.py --self-test  # prüft den Prüfer
"""
import pathlib
import re
import subprocess
import sys

# Bei der Aufteilung waren es rund 14 KB. Wer anhebt, prüft vorher, ob das
# Neue nicht in die CLAUDE.md des Ordners gehört, in dem der Code liegt.
ROOT_LIMIT_BYTES = 32 * 1024

INDEX_ROW = re.compile(r"^\| `([^`]+/CLAUDE\.md)` \|", re.MULTILINE)


def indexed(text):
    return set(INDEX_ROW.findall(text))


def problems(root_text, root_size, parts, exists):
    out = []
    idx = indexed(root_text)
    if not idx:
        out.append("Index in CLAUDE.md nicht gefunden")
    for p in sorted(idx):
        if not exists(p):
            out.append(f"Index-Zeile ohne Datei: {p}")
    for p in sorted(parts):
        if p not in idx:
            out.append(f"Teildatei ohne Zeile im Index von CLAUDE.md: {p}")
    if root_size >= ROOT_LIMIT_BYTES:
        out.append(f"CLAUDE.md hat {root_size} Bytes (Grenze "
                   f"{ROOT_LIMIT_BYTES}). Technik-Notizen gehören in die "
                   "CLAUDE.md des Ordners, in dem der Code liegt.")
    return out


def self_test():
    sample = ("| Datei | Themen |\n|---|---|\n"
              "| `lib/x/CLAUDE.md` | A · B |\n"
              "Fließtext mit `lib/y/CLAUDE.md` mitten im Satz.\n")
    assert indexed(sample) == {"lib/x/CLAUDE.md"}, indexed(sample)
    ok = problems(sample, 100, ["lib/x/CLAUDE.md"], lambda p: True)
    assert ok == [], ok
    # Gegenproben: jede der drei Regeln muss anschlagen können.
    assert any("ohne Datei" in m for m in
               problems(sample, 100, ["lib/x/CLAUDE.md"], lambda p: False))
    assert any("ohne Zeile" in m for m in
               problems(sample, 100, ["lib/x/CLAUDE.md", "lib/z/CLAUDE.md"],
                        lambda p: True))
    assert any("Bytes" in m for m in
               problems(sample, ROOT_LIMIT_BYTES, ["lib/x/CLAUDE.md"],
                        lambda p: True))
    print("agent_docs self-test ok")


def main():
    if "--self-test" in sys.argv:
        self_test()
        return
    files = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard"],
        check=True, capture_output=True, text=True).stdout.split("\n")
    parts = [f for f in files if f.endswith("/CLAUDE.md")]
    root = pathlib.Path("CLAUDE.md")
    found = problems(root.read_text(encoding="utf-8"), root.stat().st_size,
                     parts, lambda p: pathlib.Path(p).is_file())
    for m in found:
        print(f"::error::{m}")
    if found:
        sys.exit(1)
    print(f"agent_docs ok: {len(parts)} Teildateien, CLAUDE.md "
          f"{root.stat().st_size} Bytes")


if __name__ == "__main__":
    main()
