#!/usr/bin/env bash
# Monkey-C-Unit-Tests auf jeder Uhr, die das Manifest nennt (Konzept 5.1:
# die 240er-Familie). Nach einem Gerätewechsel schreibt monkeydo sonst
# nichts (garmin/CLAUDE.md) — deshalb startet der Simulator je Uhr neu.
#
#   tool/garmin_devices.sh                 alle Uhren des Manifests
#   tool/garmin_devices.sh fenix5 fr945    nur diese
#
# Der Simulator wird dafür beendet und neu geöffnet. Protokoll je Uhr:
# build/garmin/test_<uhr>.log. Exit 0, wenn alle Uhren grün sind.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${GARMIN_SDK:-}"
if [ -z "$SDK" ] && [ -f "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg" ]; then
  SDK=$(tr -d '\n' < "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")
fi
if [ -z "$SDK" ] || [ ! -x "$SDK/bin/monkeyc" ]; then
  echo "Kein Connect-IQ-SDK gefunden — GARMIN_SDK setzen." >&2
  exit 1
fi

devices="$(grep -o 'iq:product id="[a-z0-9]*"' "$ROOT/garmin/manifest.xml" | sed 's/.*id="//;s/"//' | sort -u)"
if [ $# -gt 0 ]; then devices="$*"; fi

fail=0
for d in $devices; do
  pkill -f "MacOS/simulator" 2>/dev/null || true
  pkill -f monkeydo 2>/dev/null || true
  sleep 5
  log="$ROOT/build/garmin/test_${d}.log"
  GARMIN_DEVICE="$d" "$ROOT/tool/garmin_build.sh" --test > "$log" 2>&1 || true
  # monkeydo kann mit einer Warnung nicht null zurückgehen — entschieden wird
  # über die Zeilen im Protokoll.
  if ! grep -q "BUILD SUCCESSFUL" "$log"; then
    echo "BAUFEHLER $d — ${log#"$ROOT"/}"
    fail=1
    continue
  fi
  res="$(grep -o "passed=[0-9]*, failed=[0-9]*, errors=[0-9]*" "$log" | tail -1)"
  if grep -q "PASSED (passed=[0-9]*, failed=0, errors=0)" "$log"; then
    echo "OK    $d  ($res)"
  else
    echo "FEHLT $d  (${res:-kein Ergebnis}) — ${log#"$ROOT"/}"
    fail=1
  fi
done
if [ $fail -eq 0 ]; then echo "Alle Uhren grün."; fi
exit $fail
