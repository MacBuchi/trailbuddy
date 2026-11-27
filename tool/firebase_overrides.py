#!/usr/bin/env python3
"""Firebase ohne iOS (#668): schreibt `packages/overrides/<paket>`.

Push gibt es auf dem iPhone nicht (`pushPlatformSupported`, #644), trotzdem
holte Xcode `firebase-ios-sdk` samt gut einem Dutzend Google-Paketen und
kompilierte Core und Messaging — Flutter nimmt jedes Plugin, dessen
`pubspec.yaml` die Plattform nennt; abschalten kann die App das nicht.

Das Skript kopiert die Fassung aus `pubspec.lock` aus dem Pub-Cache, nur
`lib/`, `android/`, `LICENSE` und die `pubspec.yaml` — ohne die Plattformen
`ios`, `macos` und `windows`. `pubspec.yaml` der App zeigt per
`dependency_overrides` darauf. Android und Web bleiben Byte für Byte die
des Pakets (`test/firebase_overrides_test.dart` prüft Fassung und Plattformen).

Nach jedem Firebase-Update: `flutter pub get` (die neue Fassung muss im
Cache liegen), dann `python3 tool/firebase_overrides.py`, dann noch einmal
`flutter pub get`. Kommt Push aufs iPhone, fällt das alles wieder weg.

    python3 tool/firebase_overrides.py          # schreiben
    python3 tool/firebase_overrides.py --check  # nur prüfen (CI)
"""

from __future__ import annotations

import filecmp
import os
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACKAGES = ("firebase_core", "firebase_messaging")
DROP_PLATFORMS = ("ios", "macos", "windows")
KEEP = ("lib", "android", "LICENSE")
OUT = ROOT / "packages" / "overrides"


def locked_versions() -> dict[str, str]:
    """Die Fassungen aus `pubspec.lock` — dort steht bei einem Override
    die des Overrides, also lesen wir sie aus dessen `pubspec.yaml`, wenn
    es schon existiert, sonst aus dem Lock."""
    lock = (ROOT / "pubspec.lock").read_text()
    out: dict[str, str] = {}
    for name in PACKAGES:
        m = re.search(
            rf"^  {name}:\n(?:    .*\n|      .*\n)*?    version: \"([^\"]+)\"",
            lock,
            re.M,
        )
        if not m:
            sys.exit(f"{name} fehlt in pubspec.lock")
        out[name] = m.group(1)
    return out


def pub_cache() -> Path:
    env = os.environ.get("PUB_CACHE")
    base = Path(env) if env else Path.home() / ".pub-cache"
    return base / "hosted" / "pub.dev"


def strip_platforms(pubspec: str) -> str:
    """Entfernt die Blöcke `ios:`, `macos:`, `windows:` unter
    `flutter.plugin.platforms` (je Block: die Zeile und alles tiefer
    Eingerückte)."""
    lines = pubspec.splitlines(keepends=True)
    out: list[str] = []
    skip_indent: int | None = None
    for line in lines:
        indent = len(line) - len(line.lstrip(" "))
        if skip_indent is not None:
            if line.strip() and indent > skip_indent:
                continue
            skip_indent = None
        m = re.match(r"^(\s+)(\w+):\s*$", line)
        if m and m.group(2) in DROP_PLATFORMS and len(m.group(1)) == 6:
            skip_indent = len(m.group(1))
            continue
        out.append(line)
    return "".join(out)


HEADER = (
    "# ERZEUGT von tool/firebase_overrides.py (#668) — nicht von Hand ändern.\n"
    "# Kopie aus dem Pub-Cache ohne die Plattformen ios, macos, windows.\n"
)


def build(name: str, version: str, dest: Path) -> None:
    src = pub_cache() / f"{name}-{version}"
    if not src.is_dir():
        sys.exit(f"{src} fehlt — erst `flutter pub get`")
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    for item in KEEP:
        s = src / item
        if s.is_dir():
            shutil.copytree(s, dest / item)
        else:
            shutil.copy2(s, dest / item)
    pubspec = strip_platforms((src / "pubspec.yaml").read_text())
    (dest / "pubspec.yaml").write_text(HEADER + pubspec)


def same_tree(a: Path, b: Path) -> bool:
    cmp = filecmp.dircmp(a, b)
    if cmp.left_only or cmp.right_only or cmp.diff_files or cmp.funny_files:
        return False
    return all(same_tree(a / d, b / d) for d in cmp.common_dirs)


def main() -> None:
    check = "--check" in sys.argv
    versions = locked_versions()
    bad = []
    for name in PACKAGES:
        dest = OUT / name
        if check:
            tmp = ROOT / "build" / "firebase_overrides_check" / name
            build(name, versions[name], tmp)
            if not dest.is_dir() or not same_tree(tmp, dest):
                bad.append(name)
        else:
            build(name, versions[name], dest)
            print(f"{name} {versions[name]} → {dest.relative_to(ROOT)}")
    if bad:
        sys.exit(
            "Veraltet: " + ", ".join(bad) + " — python3 tool/firebase_overrides.py"
        )
    if check:
        print("firebase_overrides ok")


if __name__ == "__main__":
    main()
