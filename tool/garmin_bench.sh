#!/usr/bin/env bash
# Die Prüfleiter der Uhr an einer Stelle (docs/konzept-garmin.md 12).
#
#   tool/garmin_bench.sh cases      Feldszenarien F1–F8 gegen den Fallkatalog
#                                   und die Dart-Tests der Uhr (S0)
#   tool/garmin_bench.sh unit       Monkey-C-Unit-Tests im Simulator (S1)
#   tool/garmin_bench.sh scenario   Vorführmodus: Rückfrage, freie Fahrt, Tasten
#   tool/garmin_bench.sh chain      Kettenstand Emulator + Simulator (S5, #527):
#                                   die echte Brücke gegen die echte Uhr-App
#   tool/garmin_bench.sh chain --break   … mit gewolltem Bruch (muss rot werden)
#   tool/garmin_bench.sh device     Tischabnahme am Pixel mit der fēnix 5 (S6):
#                                   sagt jeden Schritt an und liest Logcat
#   tool/garmin_bench.sh all        cases, unit, scenario — was ohne Gerät geht
#
# Umgebung: GARMIN_DEVICE (Vorgabe fenix5), ANDROID_SERIAL bei zwei Geräten,
# ADB (Vorgabe: adb im PATH, sonst die Homebrew-Kommandozeilenwerkzeuge),
# STEP_WAIT (Sekunden je Schritt der Tischabnahme, Vorgabe 90), UNIT_SILENT
# (so lange darf der Simulator nach dem Bau schweigen, Vorgabe 60),
# CHAIN_ROUNDS (Runden „Route → ok", Vorgabe 5), CHAIN_AVD (sonst der erste).
#
# Nichts hier schreibt Koordinaten oder Gerätekennungen in eine Datei des
# Repos (A7); das Logcat der Tischabnahme liegt unter build/.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

say() { printf '%s\n' "$*"; }
ok() { say "OK    $*"; }
miss() { say "FEHLT $*"; }

# Ein hängender monkeydo oder ein Simulator mit einer alten App-Instanz
# lässt den nächsten Lauf ohne Ausgabe warten (garmin/CLAUDE.md).
cleanup_sim() {
  pkill -f monkeydo 2>/dev/null || true
  pkill -f MonkeyDoDeux 2>/dev/null || true
}

find_adb() {
  if [ -n "${ADB:-}" ] && [ -x "$ADB" ]; then echo "$ADB"; return; fi
  if command -v adb > /dev/null 2>&1; then command -v adb; return; fi
  local c
  for c in /opt/homebrew/share/android-commandlinetools/platform-tools/adb \
           "$HOME/Library/Android/sdk/platform-tools/adb"; do
    [ -x "$c" ] && { echo "$c"; return; }
  done
  echo ""
}

run_cases() {
  say "--- Feldszenarien gegen den Fallkatalog ---"
  local online=""
  command -v gh > /dev/null 2>&1 && online="--online"
  python3 tool/watch_scenarios_check.py $online || return 1
  # Die Seite der Uhr des Gesprächskatalogs (#509) ist erzeugt.
  python3 tool/watch_talks.py --check || return 1
  say "--- Dart-Tests der Uhr (S0) ---"
  flutter test test/garmin
}

# Ein Simulator, der schon mit einer alten App-Instanz läuft, nimmt die
# .prg still: Der Bau gelingt, monkeydo schreibt nichts mehr (garmin/CLAUDE.md,
# wieder gesehen 2026-11-11). Dann hilft nur ein frischer Simulator.
restart_sim() {
  local sdk app
  cleanup_sim
  pkill -f "MacOS/simulator" 2>/dev/null || true
  sleep 5
  sdk="${GARMIN_SDK:-$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks}"
  app="$(find "$sdk" -maxdepth 4 -name ConnectIQ.app 2>/dev/null | head -1)"
  [ -n "$app" ] && open "$app"
  sleep 15
}

# Ein Lauf der Unit-Tests mit Wächter: 0 = Ergebnis da, 3 = der Simulator
# schweigt (nach dem Bau UNIT_SILENT Sekunden keine neue Zeile).
unit_once() {
  local log="$1" pid built=0 lines last=0 quiet=0 end
  : > "$log"
  tool/garmin_build.sh --test > "$log" 2>&1 &
  pid=$!
  end=$((SECONDS + ${UNIT_WAIT:-600}))
  while [ $SECONDS -lt $end ]; do
    if grep -q -E "^(PASSED|FAILED)" "$log"; then break; fi
    kill -0 "$pid" 2>/dev/null || break
    if grep -q "^gebaut:" "$log"; then
      lines=$(wc -l < "$log")
      if [ $built -eq 1 ] && [ "$lines" -eq "$last" ]; then quiet=$((quiet + 2)); else quiet=0; fi
      built=1; last=$lines
      if [ $quiet -ge "${UNIT_SILENT:-60}" ]; then
        { kill "$pid"; wait "$pid"; } 2>/dev/null
        cleanup_sim
        return 3
      fi
    fi
    sleep 2
  done
  { kill "$pid"; wait "$pid"; } 2>/dev/null
  cleanup_sim
  return 0
}

run_unit() {
  local log="build/garmin/unit.log" rc
  say "--- Monkey-C-Unit-Tests (S1, ${GARMIN_DEVICE:-fenix5}) ---"
  mkdir -p build/garmin
  cleanup_sim
  unit_once "$log"; rc=$?
  if [ $rc -eq 3 ]; then
    say "der Simulator schweigt — neu gestartet, zweiter Versuch"
    restart_sim
    unit_once "$log"; rc=$?
  fi
  if [ $rc -eq 3 ]; then
    miss "Unit-Tests: der Simulator antwortet auch nach dem Neustart nicht ($log)"
    return 1
  fi
  grep -E "FAIL|ERROR" "$log" | head -20
  grep -E "^(Ran |PASSED|FAILED)" "$log"
  if grep -q "^PASSED" "$log"; then ok "Unit-Tests ($log)"; return 0; fi
  miss "Unit-Tests ($log)"
  return 1
}

run_scenario() {
  say "--- Vorführmodus im Simulator ---"
  cleanup_sim
  tool/garmin_scenario.sh
}

# S5 (#527): Emulator und Simulator, verbunden über adb. Die Reihenfolge
# zählt (Konzept 12.3): erst der Treiber bis „sdk-up" (das SDK lauscht),
# dann im Simulator „adb Connection → Start", dann die Uhr-App laden —
# ein sendender Bau ohne Verbindung öffnet sonst einen Dialog, und der
# Simulator nimmt keine App mehr an. `chain --break` baut den gewollten
# Bruch ein (die Uhr sendet nie `ok`) und ist grün, wenn die Kette rot wird.
emu_serial() {
  "$1" devices 2>/dev/null | awk '/^emulator-[0-9]+[[:space:]]+device$/ {print $1; exit}'
}

run_chain() {
  local brk=0 adb emu avd serial sdk ciq prg log flog fpid mpid rc end
  [ "${1:-}" = "--break" ] && brk=1
  say "--- Kettenstand (S5)$([ $brk = 1 ] && echo ' — gewollter Bruch: die Uhr sagt nie ok') ---"
  adb="$(find_adb)"
  [ -n "$adb" ] || { miss "adb (ADB setzen)"; return 1; }
  emu="$(dirname "$(dirname "$adb")")/emulator/emulator"
  ciq="$HOME/Library/Application Support/Garmin/ConnectIQ"
  sdk="${GARMIN_SDK:-$(tr -d '\n' < "$ciq/current-sdk.cfg" 2>/dev/null)}"
  [ -x "$sdk/bin/monkeydo" ] || { miss "Connect-IQ-SDK (GARMIN_SDK)"; return 1; }
  mkdir -p build/garmin
  log="build/garmin/chain.log"
  flog="build/garmin/chain-sim.log"

  # Das Handy: ein laufender Emulator, sonst der erste AVD ohne Fenster.
  # Nie ein echtes Telefon (das Pixel mit dem echten Konto wird nur gemessen).
  serial="$(emu_serial "$adb")"
  if [ -z "$serial" ]; then
    avd="${CHAIN_AVD:-$("$emu" -list-avds 2>/dev/null | head -1)}"
    [ -n "$avd" ] || { miss "ein AVD (avdmanager create avd …)"; return 1; }
    say "Emulator $avd startet (ohne Fenster) …"
    "$emu" -avd "$avd" -no-window -no-audio -no-boot-anim -no-snapshot-save > build/garmin/emulator.log 2>&1 &
    end=$((SECONDS + 240))
    while [ $SECONDS -lt $end ]; do
      serial="$(emu_serial "$adb")"
      if [ -n "$serial" ] && [ "$("$adb" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then break; fi
      serial=""
      sleep 3
    done
    [ -n "$serial" ] || { miss "Emulator bootet nicht (build/garmin/emulator.log)"; return 1; }
  fi
  ok "Handy: $serial"
  export ANDROID_SERIAL="$serial"

  say "Uhr-App für den Kettenstand bauen …"
  tool/garmin_build.sh --bench > build/garmin/chain-build.log 2>&1 || { miss "Bau der Uhr (build/garmin/chain-build.log)"; return 1; }
  prg="build/garmin/trailbuddy-bench.prg"
  ok "Uhr gebaut ($(grep -o 'Stempel [^)]*' build/garmin/chain-build.log | head -1))"

  # Ein frischer Simulator: einer mit alter App oder alter adb-Verbindung
  # nimmt die neue still nicht an.
  restart_sim
  "$adb" forward tcp:7381 tcp:7381 > /dev/null || { miss "adb forward tcp:7381"; return 1; }

  : > "$log"
  local defs=(--dart-define=GARMIN_TETHERED=true --dart-define=ROUNDS="${CHAIN_ROUNDS:-5}")
  [ $brk = 1 ] && defs+=(--dart-define=BREAK_OK=true)
  say "Treiber auf dem Emulator (baut beim ersten Mal ein paar Minuten) …"
  flutter test integration_test/watch_bench_test.dart -d "$serial" --flavor dev "${defs[@]}" > "$log" 2>&1 &
  fpid=$!
  trap 'kill "$fpid" 2>/dev/null; cleanup_sim' RETURN

  end=$((SECONDS + ${CHAIN_BUILD_WAIT:-900}))
  while [ $SECONDS -lt $end ] && ! grep -q "BENCH sdk-up" "$log"; do
    kill -0 "$fpid" 2>/dev/null || break
    sleep 2
  done
  if ! grep -q "BENCH sdk-up" "$log"; then
    tail -20 "$log"
    miss "der Treiber kam nicht bis zum SDK ($log)"
    return 1
  fi
  ok "SDK lauscht"

  if ! osascript -e 'tell application "System Events" to tell process "simulator" to click menu item "Start" of menu 1 of menu bar item "adb Connection" of menu bar 1' > /dev/null 2>&1; then
    miss "Klick „adb Connection → Start“ (Bedienungshilfen für das Terminal erlauben)"
    return 1
  fi
  sleep 3
  "$sdk/bin/monkeydo" "$prg" "${GARMIN_DEVICE:-fenix5}" > "$flog" 2>&1 &
  mpid=$!

  wait "$fpid"; rc=$?
  { kill "$mpid"; wait "$mpid"; } 2>/dev/null
  grep -E "BENCH (step|hallo|route median|Fahrt|result)" "$log" | sed 's/^.*BENCH /  /'
  if [ $brk = 1 ]; then
    if [ $rc -ne 0 ] && grep -q "BENCH step Route in Stücken → ok (1/.* FEHLT" "$log"; then
      ok "gewollter Bruch: die Kette wird rot, wo sie soll ($log)"; return 0
    fi
    miss "gewollter Bruch: die Kette blieb grün oder brach woanders ($log)"; return 1
  fi
  if [ $rc -eq 0 ] && grep -q "BENCH result grün" "$log"; then ok "Kettenstand ($log)"; return 0; fi
  miss "Kettenstand ($log, Uhr: $flog)"
  return 1
}

# S6: Die Schritte kommen der Reihe nach; je Schritt wird im Logcat auf die
# Zeile gewartet, die GarminBridge.kt dafür schreibt (Marke TB-GARMIN).
run_device() {
  local adb log wait pid n=0
  adb="$(find_adb)"
  [ -n "$adb" ] || { miss "adb (ADB setzen)"; return 1; }
  if [ "$("$adb" get-state 2>/dev/null)" != "device" ]; then
    miss "kein Telefon an adb (bei zweien ANDROID_SERIAL setzen)"; return 1
  fi
  wait="${STEP_WAIT:-90}"
  mkdir -p build/garmin
  log="build/garmin/desk.log"
  : > "$log"
  "$adb" logcat -c 2>/dev/null || true
  "$adb" logcat -v time 2>/dev/null | grep --line-buffered "TB-GARMIN" > "$log" &
  pid=$!
  trap 'kill "$pid" 2>/dev/null; pkill -P "$pid" 2>/dev/null' RETURN

  say "--- Tischabnahme (S6) — Release-Bau am Telefon, Uhr daneben ---"
  say "Vorher von Hand: Der Build-Stempel oben in der Übersicht der Uhr"
  say "(vor dem ersten Fix) ist der Stand, den du prüfen willst — sonst ist"
  say "die neue .prg nicht drauf. Je Schritt ${wait} s."
  say ""

  # step "<Ansage>" "<Muster im Logcat>"
  step() {
    local from end
    from=$(wc -l < "$log")
    say "→ $1"
    end=$((SECONDS + wait))
    while [ $SECONDS -lt $end ]; do
      if tail -n +"$((from + 1))" "$log" | grep -q -E "$2"; then ok "$1"; return 0; fi
      sleep 1
    done
    miss "$1   (erwartet im Logcat: $2)"
    n=$((n + 1))
  }

  step "Am Handy: Trail wählen, Navigation — Startblatt öffnen, Schalter „Auf der Uhr zeigen“ an, Los" "open "
  step "An der Uhr: TrailBuddy öffnen (oder die Frage bestätigen)" "receive hi"
  step "Warten: die Route geht in Stücken hinüber" "send SUCCESS after [0-9]+ of [0-9]+"
  step "Warten: die Uhr vibriert kurz und bestätigt" "receive ok"
  step "An der Uhr: START drücken" "receive rs"
  step "An der Uhr: START (Pause), dann „Weiter“" "receive rr"
  say "→ Bildschirm des Handys ausschalten und 10 min liegen lassen (#524)."
  say "  Weiter mit Enter, wenn die Zeit um ist — oder gleich, um den Schritt zu überspringen."
  read -r _ || true
  step "An der Uhr: LAP (Trail beginnt), kurz warten, LAP (Trail endet), „Behalten“" "receive rt"
  step "An der Uhr: START, „Speichern“ — die Fahrt geht ans Handy" "receive (re|w)"

  say ""
  if [ $n -eq 0 ]; then say "Tischabnahme grün. Protokoll: $log"
  else say "Tischabnahme: $n Schritt(e) fehlen. Protokoll: $log"; fi
  say "Von Hand noch ansehen: „Meine Fahrten“ zeigt die Fahrt des Handys"
  say "(die der Uhr fällt wegen der Überdeckung weg), mit den Trail-Marken."
  return $n
}

case "${1:-}" in
  cases) run_cases ;;
  unit) run_unit ;;
  scenario) run_scenario ;;
  chain) shift; run_chain "$@" ;;
  device) run_device ;;
  all)
    rc=0
    run_cases || rc=1
    run_unit || rc=1
    run_scenario || rc=1
    exit $rc
    ;;
  *)
    sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'
    exit 64
    ;;
esac
