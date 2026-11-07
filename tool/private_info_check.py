#!/usr/bin/env python3
"""Nothing private in this public repository (rule from PilzBuddy).

Fails on absolute paths of the operator's machines, private mail domains,
and on GPX or zip files, which here are always somebody's rides. The
measurement input lives outside the repo (TRAIL_GPX); the reports name
ids and counts only. Extend the patterns before they are needed, not
after.
"""
import os
import re
import subprocess
import sys

PATTERNS = [
    (re.compile(r"/Users/|/Volumes/|/root/\.claude/|/home/[a-z]+/"), "absolute path of a machine"),
    (re.compile(r"@(web\.de|gmx\.\w+|gmail\.com|t-online\.de|icloud\.com)"), "private mail address"),
    (re.compile(r"\b\d{2}\.\d{4,},\s*\d{1,2}\.\d{4,}\b"), "coordinate pair"),
]
# Addresses that MUST be public (imprint, privacy policy, store contact) —
# the operator's app contact since 2026-11-07. Only these exact addresses;
# any other address on a private domain still fails.
PUBLIC_ADDRESSES = ("macbuchi.apps@gmail.com",)
FORBIDDEN_EXT = (".gpx", ".zip", ".kml", ".fit")
ALLOW_SELF = os.path.relpath(__file__)


def main() -> int:
    files = subprocess.run(["git", "ls-files"], capture_output=True, text=True, check=True).stdout.split()
    bad = 0
    for f in files:
        if f.lower().endswith(FORBIDDEN_EXT):
            print(f"{f}: ride data does not belong in the repo")
            bad += 1
            continue
        if f == ALLOW_SELF:
            continue
        try:
            text = open(f, encoding="utf-8").read()
        except (UnicodeDecodeError, OSError):
            continue
        for n, line in enumerate(text.splitlines(), 1):
            for addr in PUBLIC_ADDRESSES:
                line = line.replace(addr, "")
            for pat, why in PATTERNS:
                if pat.search(line):
                    print(f"{f}:{n}: {why}")
                    bad += 1
    print("private-info check:", "clean" if not bad else f"{bad} finding(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
