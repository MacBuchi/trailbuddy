#!/usr/bin/env bash
# #501 am Simulator, ohne draußen zu stehen (Konzept 2): eine neue Linie
# während einer laufenden Fahrt fragt die Uhr. START oder ZURÜCK lehnen;
# wer nichts tut, nimmt sie nach ASK_MS. Der Vorführmodus spielt die Runde,
# die Konsole wird gegen die erwarteten Zeilen geprüft. Exit 0, wenn alles
# so lief — dasselbe Bild, jedes Mal, ohne Gerät am Arm.
#
#   tool/garmin_scenario.sh                  (fenix5)
#   GARMIN_DEVICE=fenix9 tool/garmin_scenario.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$ROOT/build/garmin/scenario.log"
POINTS="${POINTS:-300}"
DEADLINE="${DEADLINE:-180}"

need=(
  "demo 501 ablehnen: Frage weg true"
  "Speicher leer"
  "demo 501 annehmen"
  "Frage nach neuer Linie steht"
  "demo 501 dieselbe nochmal: Frage nein"
  "nichts bereit"
)

allThere() {
  local w
  for w in "${need[@]}"; do grep -q "$w" "$LOG" || return 1; done
  return 0
}

# Nach der Annahme muss der Rahmen eine andere Linie zeigen als vorher.
swapped() {
  awk '
    /demo 501 annehmen/ {
      if (match($0, /Linie [A-Za-z0-9-]+/)) id = substr($0, RSTART + 6, RLENGTH - 6)
      seen = 1; next
    }
    seen && /demo frame/ {
      if (match($0, /Linie [A-Za-z0-9-]+/)) {
        cur = substr($0, RSTART + 6, RLENGTH - 6)
        if (cur != id) { print cur; exit }
      }
    }' "$LOG"
}

done_() { allThere && [ -n "$(swapped)" ]; }

# Der Simulator muss laufen; ein kalter Start dauert länger als die fünf
# Sekunden in garmin_build.sh.
SDK="${GARMIN_SDK:-$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks}"
app="$(find "$SDK" -maxdepth 4 -name ConnectIQ.app 2>/dev/null | head -1)"
for i in 1 2 3 4 5 6 7 8; do
  pgrep -f "MacOS/simulator" > /dev/null && break
  [ -n "$app" ] && open "$app"
  sleep 5
done

run() {
  tool/garmin_build.sh --demo --points "$POINTS" > "$LOG" 2>&1 &
  pid=$!
  end=$((SECONDS + DEADLINE))
  while [ $SECONDS -lt $end ]; do
    if done_; then break; fi
    sleep 5
  done
  kill -9 "$pid" 2>/dev/null || true
  pkill -f monkeydo 2>/dev/null || true
}

run
if grep -q "Unable to connect to simulator" "$LOG"; then
  echo "zweiter Versuch — der Simulator war noch nicht bereit"
  sleep 15
  run
fi
if ! done_; then
  echo "Szenario lief, aber die erwarteten Zeilen fehlen noch" >&2
fi

echo "--- Szenario #501 (Simulator ${GARMIN_DEVICE:-fenix5}, ${POINTS} Punkte) ---"
grep -E "demo 501|Frage nach neuer Linie|Linie (test|demo)-" "$LOG" | tail -14
n=0
for w in "${need[@]}"; do
  if grep -q "$w" "$LOG"; then echo "OK    $w"; else echo "FEHLT $w"; n=$((n + 1)); fi
done
new="$(swapped)"
if [ -n "$new" ]; then
  echo "OK    genommen nach der Frist: Linie $new"
else
  echo "FEHLT genommen nach der Frist (Linie bleibt dieselbe)"; n=$((n + 1))
fi
if [ $n -eq 0 ]; then echo "Szenario grün."; else
  echo "Szenario fehlt: $n Punkt(en) — Protokoll: ${LOG#"$ROOT"/}"
fi
exit $n
