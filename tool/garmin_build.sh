#!/usr/bin/env bash
# Baut die Uhr-App aus garmin/ (docs/konzept-garmin.md, Abschnitt 6).
#
#   tool/garmin_build.sh                 baut build/garmin/trailbuddy.prg
#   tool/garmin_build.sh --points 4000   … mit einer erfundenen Testroute
#                                        aus N Punkten (Messung 8.1)
#   tool/garmin_build.sh --gpx DATEI     … mit einer eigenen Route (GPX der
#                                        App); bleibt unter build/, nie im Repo
#   tool/garmin_build.sh --test          Monkey-C-Unit-Tests im Simulator
#   tool/garmin_build.sh --run           im Simulator starten
#   tool/garmin_build.sh --demo          im Simulator, ohne GPS: spielt die
#                                        Zustände der Ansicht durch
#
# Gebaut wird aus einer Kopie unter build/garmin/src — so ersetzt eine
# eigene Route nie die Testroute im Repo. Auf die Uhr: die .prg per USB
# nach GARMIN/APPS/ kopieren (Konzept 5.1).
#
# Umgebung: GARMIN_SDK (Vorgabe: das aktuelle SDK des SDK-Managers),
# GARMIN_DEV_KEY (Vorgabe: ~/.connectiq/developer_key.der — der Schlüssel
# bleibt beim Betreiber, nie im Repo), GARMIN_DEVICE (Vorgabe: fenix5).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CIQ="$HOME/Library/Application Support/Garmin/ConnectIQ"
SDK="${GARMIN_SDK:-}"
if [ -z "$SDK" ] && [ -f "$CIQ/current-sdk.cfg" ]; then
  SDK=$(tr -d '\n' < "$CIQ/current-sdk.cfg")
fi
KEY="${GARMIN_DEV_KEY:-$HOME/.connectiq/developer_key.der}"
DEVICE="${GARMIN_DEVICE:-fenix5}"
OUT="$ROOT/build/garmin"

mode=build
route_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --points) route_args=(--points "$2"); shift 2 ;;
    --gpx) route_args=(--gpx "$2"); shift 2 ;;
    --test) mode=test; shift ;;
    --run) mode=run; shift ;;
    --demo) mode=demo; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "Unbekannt: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$SDK" ] || [ ! -x "$SDK/bin/monkeyc" ]; then
  echo "Kein Connect-IQ-SDK gefunden — SDK-Manager installieren oder GARMIN_SDK setzen." >&2
  exit 1
fi
if [ ! -f "$KEY" ]; then
  echo "Kein Entwicklerschlüssel unter $KEY — GARMIN_DEV_KEY setzen." >&2
  exit 1
fi

rm -rf "$OUT/src"
mkdir -p "$OUT/src"
cp -R "$ROOT/garmin/." "$OUT/src/"
# Der Build-Stempel für die Übersicht ohne GPS: Commit, „+" mit
# ungespeicherten Änderungen unter garmin/, Datum und Uhrzeit des Builds —
# so sieht man auf der Uhr, ob die neue .prg wirklich drauf ist.
stamp="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo dev)"
if ! git -C "$ROOT" diff --quiet HEAD -- garmin 2>/dev/null; then stamp="$stamp+"; fi
stamp="$stamp · $(date '+%d.%m. %H:%M')"
cat > "$OUT/src/resources/strings/build.xml" <<STAMP
<strings>
    <string id="BuildStamp">$stamp</string>
</strings>
STAMP
if [ ${#route_args[@]} -gt 0 ]; then
  python3 "$ROOT/tool/garmin_route.py" ${route_args[@]+"${route_args[@]}"} --out "$OUT/src/resources/route/route.json"
fi

prg="$OUT/trailbuddy.prg"
extra=()
if [ "$mode" = demo ]; then
  prg="$OUT/trailbuddy-demo.prg"
  echo "base.excludeAnnotations = nodemo" >> "$OUT/src/monkey.jungle"
fi
if [ "$mode" = test ]; then
  prg="$OUT/trailbuddy-test.prg"
  extra=(--unit-test)
fi
"$SDK/bin/monkeyc" -d "$DEVICE" -f "$OUT/src/monkey.jungle" -o "$prg" -y "$KEY" -w ${extra[@]+"${extra[@]}"}
echo "gebaut: ${prg#"$ROOT"/}"

if [ "$mode" = build ]; then
  exit 0
fi
# Simulator: läuft er nicht, starten und kurz warten.
if ! pgrep -f "ConnectIQ.app" > /dev/null; then
  open "$SDK/bin/ConnectIQ.app"
  sleep 5
fi
if [ "$mode" = test ]; then
  "$SDK/bin/monkeydo" "$prg" "$DEVICE" -t
else
  "$SDK/bin/monkeydo" "$prg" "$DEVICE"
fi
