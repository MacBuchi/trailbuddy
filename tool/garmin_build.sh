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
#   tool/garmin_build.sh --store         Store-Paket build/garmin/trailbuddy.iq
#                                        für alle Uhren im Manifest: ohne
#                                        Debug-Infos, ohne Testroute
#   tool/garmin_build.sh --store --run   … und den Store-Zweig (ohne Testroute)
#                                        im Simulator zeigen (GARMIN_DEVICE)
#   tool/garmin_build.sh --bench         Bau für den Kettenstand (S5, #527):
#                                        sendet wirklich (nosim) und nimmt
#                                        Ereignisse über den Kanal (:bench) —
#                                        build/garmin/trailbuddy-bench.prg,
#                                        gestartet von garmin_bench.sh chain
#   tool/garmin_build.sh --prepare-only --demo
#                                        nur die Kopie unter build/garmin/src
#                                        vorbereiten (Version.mc, Testroute,
#                                        excludeAnnotations) und den Plan in
#                                        build/garmin/src/build.env schreiben —
#                                        ohne SDK und ohne Schlüssel; gebaut
#                                        wird im Container (garmin_sim.sh, #533)
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
store=0
prepare=0
# Die erfundene Route ist nur für Prüfungen und Messungen dabei.
demoRoute=0
route_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --points) route_args=(--points "$2"); shift 2 ;;
    --gpx) route_args=(--gpx "$2"); shift 2 ;;
    --test) mode=test; shift ;;
    --run) mode=run; shift ;;
    --demo) mode=demo; shift ;;
    --store) store=1; shift ;;
    --demo-route) demoRoute=1; shift ;;
    --bench) mode=bench; shift ;;
    --prepare-only) prepare=1; shift ;;
    -h|--help) sed -n '2,39p' "$0"; exit 0 ;;
    *) echo "Unbekannt: $1" >&2; exit 2 ;;
  esac
done

# Für Prüfungen und Messungen bleibt die erfundene Route im Paket.
case "$mode" in test|demo|run|bench) demoRoute=1 ;; esac
if [ ${#route_args[@]} -gt 0 ]; then demoRoute=1; fi
if [ "$store" = 1 ]; then demoRoute=0; fi

if [ "$prepare" = 1 ]; then
  :
elif [ -z "$SDK" ] || [ ! -x "$SDK/bin/monkeyc" ]; then
  echo "Kein Connect-IQ-SDK gefunden — SDK-Manager installieren oder GARMIN_SDK setzen." >&2
  exit 1
fi
if [ "$prepare" = 0 ] && [ ! -f "$KEY" ]; then
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
stamp="$stamp $(date '+%d%m %H:%M')"
# Ein fester Stempel (GARMIN_STAMP) macht die Bilder des Containers
# zwischen zwei Bauten vergleichbar (garmin_sim.sh shots --check, #533).
if [ -n "${GARMIN_STAMP:-}" ]; then stamp="$GARMIN_STAMP"; fi
# Die Fassung steht auf der Uhr (kurz, kein Stempel) und im „hallo" ans
# Handy: nur eine Uhr, die `ver` meldet, bekommt später das Fenster.
version="$(cat "$ROOT/garmin/VERSION" 2>/dev/null || echo 0.0.0)"
if [ "$store" != 1 ]; then version="$version-dev"; fi
cat > "$OUT/src/source/Version.mc" <<VER
//! Von tool/garmin_build.sh gebaut, nie von Hand: die Fassung der Uhr-App
//! (garmin/VERSION), im Simulator- und Gerätebau mit „-dev". Sie steht
//! klein oben in der Übersicht und im „hallo" ans Handy (#500).
class TbVersion {
    static const VERSION = "$version";
    static const STAMP = "$stamp";
}
VER
echo "Fassung $version (Stempel $stamp)" 
if [ "$store" = 1 ]; then
  if [ "$mode" = test ] || [ "$mode" = demo ] || [ "$mode" = bench ] || [ ${#route_args[@]} -gt 0 ]; then
    echo "--store geht nur allein oder mit --run." >&2
    exit 2
  fi
  # Ohne Testroute (garmin/CLAUDE.md, „Die Testroute"): Die Ressource fehlt
  # im Paket, der Zweig (:testroute) auch — ohne Route vom Handy zeigt die
  # Uhr den Hinweis auf die App.
fi
# Kein Build mit der erfundenen Route trägt sie auch im Paket.
if [ "$demoRoute" = 0 ]; then rm -rf "$OUT/src/resources/route"; fi
if [ ${#route_args[@]} -gt 0 ]; then
  python3 "$ROOT/tool/garmin_route.py" ${route_args[@]+"${route_args[@]}"} --out "$OUT/src/resources/route/route.json"
fi

prg="$OUT/trailbuddy.prg"
extra=()
# Welche Zweige wegfallen (die letzte Zeile in monkey.jungle gilt):
# Vorführmodus (demo/nodemo), Testroute oder Store-Hinweis
# (testroute/store), Senden über Garmin Connect oder stumm im Simulator
# (nosim/sim — sonst öffnet der Simulator ohne ADB bei jedem Lauf den
# Dialog „There is no data connection"), Kettenstand (bench/nobench: nur
# --bench nimmt Ereignisse über den Kanal, #527).
excl="demo;bench"
if [ "$mode" = demo ]; then excl="nodemo;bench"; prg="$OUT/trailbuddy-demo.prg"; fi
if [ "$mode" = bench ]; then excl="demo;nobench"; prg="$OUT/trailbuddy-bench.prg"; fi
if [ "$demoRoute" = 1 ]; then excl="$excl;store"; else excl="$excl;testroute"; fi
if [ "$mode" = build ] || [ "$mode" = bench ]; then excl="$excl;sim"; else excl="$excl;nosim"; fi
echo "base.excludeAnnotations = $excl" >> "$OUT/src/monkey.jungle"

if [ "$mode" = test ]; then
  prg="$OUT/trailbuddy-test.prg"
  extra=(--unit-test)
fi
if [ "$prepare" = 1 ]; then
  # Der Plan für den Bau im Container: welcher Modus, welche Datei.
  if [ "$store" = 1 ] && [ "$mode" = build ]; then
    echo "--prepare-only baut kein Store-Paket (.iq) — das bleibt beim Betreiber." >&2
    exit 2
  fi
  if [ "$store" = 1 ]; then prg="$OUT/trailbuddy-store.prg"; extra=(-r); fi
  {
    echo "mode=$mode"
    echo "prg=$(basename "$prg")"
    echo "extra=\"${extra[*]+"${extra[*]}"}\""
    echo "route=$([ ${#route_args[@]} -gt 0 ] && echo "${route_args[0]#--}" || echo testroute)"
  } > "$OUT/src/build.env"
  echo "vorbereitet: ${OUT#"$ROOT"/}/src ($excl)"
  exit 0
fi
if [ "$store" = 1 ] && [ "$mode" = build ]; then
  # Das Paket für den Connect-IQ-Store: alle Uhren aus dem Manifest, ohne
  # Debug-Infos. Signiert mit DEMSELBEN Schlüssel wie jede spätere Fassung —
  # mit einem anderen nimmt der Store kein Update an.
  iq="$OUT/trailbuddy.iq"
  "$SDK/bin/monkeyc" -e -r -O 2 -f "$OUT/src/monkey.jungle" -o "$iq" -y "$KEY" -w
  echo "gebaut: ${iq#"$ROOT"/} (Stempel $stamp)"
  exit 0
fi
if [ "$store" = 1 ]; then prg="$OUT/trailbuddy-store.prg"; extra=(-r); fi
"$SDK/bin/monkeyc" -d "$DEVICE" -f "$OUT/src/monkey.jungle" -o "$prg" -y "$KEY" -w ${extra[@]+"${extra[@]}"}
echo "gebaut: ${prg#"$ROOT"/}"
if [ "$mode" = build ] && [ "$demoRoute" = 0 ]; then
  echo "ohne Route: auf der Uhr öffnen, START für die freie Fahrt (#484)"
fi

if [ "$mode" = build ] || [ "$mode" = bench ]; then
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
