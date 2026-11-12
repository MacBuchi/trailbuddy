#!/usr/bin/env bash
# Der Simulator der Uhr im Container (#533, Konzept-Garmin 12, Stufe S1c):
# bauen, starten, Tasten drücken und das Bild ansehen — ohne Bildschirm,
# ohne das SDK des Betreibers, ohne seinen Schlüssel, auch bei gesperrtem
# Mac. Das Bild kommt direkt aus dem Bildspeicher von Xvfb.
#
#   tool/garmin_sim.sh up [gerät] [--lang deu|eng]
#                                   Container `tb-garmin-sim` starten (Bild
#                                   beim ersten Mal bauen), Xvfb, Simulator;
#                                   Vorgabe fenix5, Deutsch
#   tool/garmin_sim.sh build [--demo|--test|--run|--store|--points N|--gpx D]
#                                   wie garmin_build.sh, aber monkeyc läuft
#                                   im Container (Wegwerf-Schlüssel)
#   tool/garmin_sim.sh run [prg] [--fresh]
#                                   App laden (Vorgabe: der letzte Bau);
#                                   Konsole nach build/garmin/sim/app.log;
#                                   --fresh leert vorher den App-Speicher
#   tool/garmin_sim.sh wait "<Muster>" [s]
#                                   warten, bis die Konsole das Muster zeigt
#                                   (grep -E; Vorgabe 60 s), sonst Exit 1
#   tool/garmin_sim.sh shot [name] [--full|--screen]
#                                   Bild der Anzeige (rund ausgeschnitten)
#                                   nach build/garmin/sim/<name>.png;
#                                   --full mit Gehäuse und Menüleiste,
#                                   --screen der ganze Bildschirm (Dialoge
#                                   aus `menu` liegen außerhalb)
#   tool/garmin_sim.sh press <start|back|up|down> [--long]
#                                   Klick auf die Taste im Gerätebild; lang
#                                   = gedrückt halten (langes HOCH = Menü)
#   tool/garmin_sim.sh menu "<Menü>" "<Eintrag>"
#                                   ein Eintrag der Menüleiste des Simulators
#                                   (ohne Untermenüs, Liste: menu --list)
#   tool/garmin_sim.sh lang <deu|eng>
#                                   Sprache der Uhr (Simulator startet neu)
#   tool/garmin_sim.sh unit         Monkey-C-Unit-Tests; Ergebnis aus der
#                                   letzten Zeile (PASSED/FAILED)
#   tool/garmin_sim.sh shots [--lang deu|eng|all] [--check|--update]
#                                   alle Zustände der Ansicht als Bilder:
#                                   build/garmin/sim/shots/<gerät>/<sprache>/
#                                   samt Übersicht sheet.png; --check
#                                   vergleicht mit den Referenzen, --update
#                                   schreibt sie (nur von der Testroute)
#   tool/garmin_sim.sh down         Container beenden
#
# Umgebung: GARMIN_SIM_IMAGE (anderes Grundbild statt des Digests in
# tool/garmin_sim.Dockerfile), GARMIN_SHOTS_REF (Ordner der Referenzen,
# Vorgabe garmin/shots), HOLD_S (Sekunden für --long, Vorgabe 2).
#
# Das Bild ist von einem Dritten, nicht von Garmin, mit SDK 9.2.0 (der Mac
# hat ein neueres): Ein Unterschied zwischen beiden Simulatoren ist ein
# Befund, kein Rauschen. Unter Apple silicon läuft es über Rosetta.

# Deutsche Anführungszeichen in Meldungen sind gewollt.
# shellcheck disable=SC1111
set -euo pipefail

C=tb-garmin-sim
STATE=/tmp/tbsim
TB=/tb

# ---------------------------------------------------------------------------
# Im Container (`garmin_sim.sh _in …`): Xvfb auf :1, Simulator, xdotool.
# ---------------------------------------------------------------------------

in_device() { cat "$STATE/device" 2>/dev/null || echo fenix5; }
in_devdir() { echo "/root/.Garmin/ConnectIQ/Devices/$(in_device)"; }

# Ein Wert aus simulator.json des Geräts (Python, weil jq fehlt).
in_json() {
  python3 - "$(in_devdir)/simulator.json" "$@" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
what = sys.argv[2]
if what == 'display':
    l = d['display']['location']
    print(l['x'], l['y'], l['width'], l['height'], d['display'].get('shape', 'rect'))
elif what == 'key':
    want = sys.argv[3]
    for k in d['keys']:
        if k['id'] == want:
            l = k['location']
            print(l['x'] + l['width'] // 2, l['y'] + l['height'] // 2)
            break
    else:
        sys.exit(1)
elif what == 'keys':
    print(' '.join(k['id'] for k in d['keys']))
elif what == 'image':
    print(d['image'])
PY
}

in_sim_listening() {
  # Ports 1234–1238 (0x04D2–0x04D6), Zustand LISTEN (0A): monkeydo kann
  # sich verbinden. Ist 1234 vom letzten Simulator noch belegt, nimmt der
  # neue den nächsten (gesehen 2026-11-12).
  awk 'NR > 1 && $4 == "0A" && $2 ~ /:04D[2-6]$/ {f = 1} END {exit !f}' /proc/net/tcp /proc/net/tcp6 2>/dev/null
}

in_stop_app() {
  { pkill -f MonkeyDoDeux; pkill -f "bin/monkeydo"; } > /dev/null 2>&1 || true
}

in_start_sim() {
  in_stop_app
  pkill -x simulator 2>/dev/null || true
  local i
  for i in $(seq 1 20); do pgrep -x simulator > /dev/null || break; sleep 0.5; done
  rm -f "$STATE/offset"
  # Der Simulator behält den Speicher der App über Läufe (z. B. `askSeen`:
  # „START = JA" groß nur bei der ersten Frage). --fresh leert ihn.
  if [ "${FRESH:-0}" = 1 ]; then rm -rf /tmp/com.garmin.connectiq/GARMIN/APPS/DATA; fi
  ( cd /tmp && DISPLAY=:1 simulator > "$TB/sim/simulator.log" 2>&1 & )
  for i in $(seq 1 120); do
    if in_sim_listening; then return 0; fi
    sleep 0.5
  done
  echo "Der Simulator lauscht nach 60 s auf keinem Port 1234–1238 ($TB/sim/simulator.log)" >&2
  return 1
}

in_set_lang() {
  local ini=/root/.Garmin/ConnectIQ/simulator.ini code
  case "$1" in
    deu) code=7 ;;
    eng) code=4 ;;
    *) echo "Sprache: deu oder eng" >&2; return 2 ;;
  esac
  mkdir -p "$(dirname "$ini")"
  touch "$ini"
  if grep -q '^Language=' "$ini"; then sed -i "s/^Language=.*/Language=$code/" "$ini"
  else echo "Language=$code" >> "$ini"; fi
  echo "$1" > "$STATE/lang"
}

in_up() {
  local device="$1" lang="$2"
  mkdir -p "$STATE/fb" "$STATE/k" "$TB/sim"
  [ -d "/root/.Garmin/ConnectIQ/Devices/$device" ] || { echo "Gerät $device gibt es im Bild nicht" >&2; return 2; }
  echo "$device" > "$STATE/device"
  rm -f "$STATE"/key-*
  # Der Schlüssel ist ein Wegwerf-Schlüssel des Containers; der des
  # Betreibers kommt nie hierher (garmin/CLAUDE.md).
  if [ ! -f "$STATE/k/key.der" ]; then
    openssl genrsa -out "$STATE/k/key.pem" 4096 2> /dev/null
    openssl pkcs8 -topk8 -inform PEM -outform DER -in "$STATE/k/key.pem" -out "$STATE/k/key.der" -nocrypt
  fi
  if ! pgrep -x Xvfb > /dev/null; then
    # 1200 hoch: Das Menü „Settings" passt sonst nicht unter die Leiste
    # und rutscht nach oben (Zeilen für `menu` stimmen dann nicht).
    ( Xvfb :1 -screen 0 800x1200x24 -fbdir "$STATE/fb" > /dev/null 2>&1 & )
    sleep 1
  fi
  in_set_lang "$lang"
  in_start_sim
  echo "Simulator bereit: $device, $lang"
}

in_build() {
  local env="$TB/src/build.env" mode prg extra route
  [ -f "$env" ] || { echo "Nichts vorbereitet ($env fehlt)" >&2; return 1; }
  # shellcheck disable=SC1090
  . "$env"
  rm -rf /tmp/work
  cp -R "$TB/src" /tmp/work
  # shellcheck disable=SC2086
  monkeyc -d "$(in_device)" -f /tmp/work/monkey.jungle -o "$TB/$prg" -y "$STATE/k/key.der" -w $extra
  echo "$prg" > "$TB/sim/last.prg"
  echo "gebaut: build/garmin/$prg ($(in_device), Modus $mode, Route $route)"
}

in_run() {
  local prg="" flag="" a
  for a in "$@"; do
    case "$a" in
      --fresh) FRESH=1 ;;
      -t) flag=-t ;;
      *) prg="$a" ;;
    esac
  done
  [ -n "$prg" ] || prg="$(cat "$TB/sim/last.prg" 2>/dev/null || true)"
  [ -n "$prg" ] && [ -f "$TB/$prg" ] || { echo "Keine .prg: $prg — erst build" >&2; return 1; }
  in_start_sim
  : > "$TB/sim/app.log"
  # shellcheck disable=SC2086
  ( cd /tmp && DISPLAY=:1 monkeydo "$TB/$prg" "$(in_device)" $flag > "$TB/sim/app.log" 2>&1 & )
  echo "läuft: $prg auf $(in_device) — Konsole build/garmin/sim/app.log"
}

# Der Titel des Fensters („CIQ Simulator - fēnix® 5 …" mit geladenem
# Gerät). `xdotool search --name` sieht nur den Anfang (WM_NAME ohne
# Unicode), deshalb über getwindowname.
in_window_name() {
  local w
  for w in $(DISPLAY=:1 xdotool search --name "CIQ Simulator" 2>/dev/null); do
    DISPLAY=:1 xdotool getwindowname "$w"
  done
}

# Wo liegt das Gerätebild im Bildschirm? Einmal je Start des Simulators.
in_offset() {
  if [ ! -s "$STATE/offset" ]; then
    # Erst wenn eine App läuft, zeigt das Fenster das Gerät (Titel
    # „CIQ Simulator - <Gerät>"); vorher gäbe die Suche Unsinn.
    if ! in_window_name | grep -q "CIQ Simulator - "; then
      echo "Im Simulator ist noch kein Gerät zu sehen — erst run, dann warten (wait)" >&2
      return 1
    fi
    cp "$STATE/fb/Xvfb_screen0" "$STATE/offset.xwd"
    python3 /repo/tool/xwd_png.py --find "$STATE/offset.xwd" "$(in_devdir)/$(in_json image 2>/dev/null || echo "$(in_device).png")" > "$STATE/offset"
  fi
  cat "$STATE/offset"
}

in_shot() {
  local name="${1:-shot}" full="${2:-}" src="${3:-}" ox oy dx dy dw dh shape
  if [ -z "$src" ]; then
    src="$STATE/shot.xwd"
    cp "$STATE/fb/Xvfb_screen0" "$src"
  fi
  local off
  off=$(in_offset) || return 1
  read -r ox oy <<< "$off"
  if [ "$full" = --screen ]; then
    python3 /repo/tool/xwd_png.py "$src" "$TB/sim/$name.png"
  elif [ "$full" = --full ]; then
    local g w h
    g=$(DISPLAY=:1 xdotool search --name "CIQ Simulator" getwindowgeometry 2>/dev/null | awk '/Geometry/ {print $2}' | head -1)
    w=${g%x*}; h=${g#*x}
    python3 /repo/tool/xwd_png.py "$src" "$TB/sim/$name.png" --crop "0,0,${w:-800},${h:-900}"
  else
    read -r dx dy dw dh shape < <(in_json display)
    if [ "$shape" = round ]; then
      python3 /repo/tool/xwd_png.py "$src" "$TB/sim/$name.png" --crop "$((ox + dx)),$((oy + dy)),$dw,$dh" --round
    else
      python3 /repo/tool/xwd_png.py "$src" "$TB/sim/$name.png" --crop "$((ox + dx)),$((oy + dy)),$dw,$dh"
    fi
  fi
  echo "build/garmin/sim/$name.png"
}

in_press() {
  local key="$1" long="${2:-}" id xy x y ox oy
  case "$key" in
    start) id=enter ;;
    back) id=esc ;;
    up) id=up ;;
    down) id=down ;;
    light) id=light ;;
    *) echo "Taste: start, back, up, down, light" >&2; return 2 ;;
  esac
  # Langes HOCH ist bei Garmin die Taste MENU (eigener Eintrag, isHold).
  if [ "$long" = --long ] && [ "$id" = up ] && { [ -f "$STATE/key-menu" ] || in_json key menu > /dev/null 2>&1; }; then id=menu; fi
  # Lage je Taste einmal je Start aus simulator.json (Python kostet unter
  # Rosetta fast eine Sekunde je Aufruf — zu lang im Takt der Szenen).
  local off
  off=$(in_offset) || return 1
  read -r ox oy <<< "$off"
  if [ ! -f "$STATE/key-$id" ]; then
    if ! xy=$(in_json key "$id"); then
      echo "Taste $key ($id) gibt es auf $(in_device) nicht — da: $(in_json keys)" >&2
      return 2
    fi
    echo "$xy" > "$STATE/key-$id"
  fi
  xy=$(cat "$STATE/key-$id")
  x=$(( ${xy% *} + ox )); y=$(( ${xy#* } + oy ))
  if [ "$long" = --long ]; then
    DISPLAY=:1 xdotool mousemove "$x" "$y" mousedown 1
    sleep "${HOLD_S:-2}"
    DISPLAY=:1 xdotool mouseup 1
  else
    DISPLAY=:1 xdotool mousemove "$x" "$y" click 1
  fi
  # Die Maus vom Gerät nehmen, sonst steht sie im nächsten Bild.
  DISPLAY=:1 xdotool mousemove 790 1190
}

# Die Menüleiste des Simulators (SDK 9.2.0 im festgenagelten Bild): Lage
# der Titel und die Einträge in ihrer Reihenfolge. Zeilen 25 px, die erste
# bei y 37 — gemessen 2026-11-12. Untermenüs (▸) gehen hier nicht.
# shellcheck disable=SC2034  # gelesen über ${!list}
MENU_TITLES="File:20 Settings:70 Simulation:150 Data_Fields:238 adb_Connection:342"
# shellcheck disable=SC2034
MENU_File="Save Screen Capture|Kill App|Kill Device|View Memory|View HTTP Traffic|View Profiler|View Watchface Diagnostics|Edit Watch Face|View Screen Heat Map|>Edit Persistent Storage|Clear Persisted Content|Reset All App Data|Delete All Apps|Reset Simulator|Quit"
# shellcheck disable=SC2034
MENU_Settings=">Time Display|>Units Display|>Language|>Connection Type|>Constellation Configurations|>Flashlight Configurations|>Media Mode|>Audio Provider|>First Day of Week|>Push Notifications|>Review Requests|Tones|Vibrate|Sleep Mode|Active App|Activity Tracking|Do Not Disturb|>Color Mode|Enhanced Readability Mode|Flashlight Available|>Glance Launch Mode|Night Mode|Toggle Touch Screen|Use Device HTTPS Requirements|Wheelchair Mode|Font Scale|Set User Profile|Set Battery Status|Set GPS Quality|Set Alarm Count|Set Phone Notifications|>Set Phone Operating System|Set Training Status|Manage Sensors"
# shellcheck disable=SC2034
MENU_Simulation="Activity Audio Prompts|Activity Data|>Activity Monitoring|Activity Select|Set Navigation Data|Background Events|Complications|Time Simulation|Push Notification|Phone App Message|App Lock Enabled"
# shellcheck disable=SC2034
MENU_Data_Fields=">Layout|>Background Color|Enable Alert|Timeout Alert"
# shellcheck disable=SC2034
MENU_adb_Connection="Start|Release"

in_menu() {
  local menu="$1" item="${2:-}" key tx="" t list i=0 found=-1 e
  if [ "$menu" = --list ]; then
    for t in $MENU_TITLES; do
      key=${t%:*}; list="MENU_$key"
      echo "${key//_/ }:"
      IFS='|' read -r -a arr <<< "${!list}"
      for e in "${arr[@]}"; do
        case "$e" in ">"*) echo "    ${e#>}   (Untermenü — geht nicht)" ;; *) echo "    $e" ;; esac
      done
    done
    return 0
  fi
  key=${menu// /_}
  for t in $MENU_TITLES; do [ "${t%:*}" = "$key" ] && tx=${t#*:}; done
  [ -n "$tx" ] || { echo "Menü „$menu“ unbekannt — menu --list" >&2; return 2; }
  list="MENU_$key"
  IFS='|' read -r -a arr <<< "${!list}"
  for e in "${arr[@]}"; do
    if [ "$e" = "$item" ]; then found=$i; fi
    if [ "$e" = ">$item" ]; then echo "„$item“ ist ein Untermenü — geht hier nicht" >&2; return 2; fi
    i=$((i + 1))
  done
  [ $found -ge 0 ] || { echo "„$item“ steht nicht im Menü „$menu“ — menu --list" >&2; return 2; }
  DISPLAY=:1 xdotool mousemove "$tx" 12 click 1
  sleep 1
  DISPLAY=:1 xdotool mousemove "$((tx + 60))" "$((37 + 25 * found))"
  sleep 0.5
  DISPLAY=:1 xdotool click 1
  DISPLAY=:1 xdotool mousemove 790 1190
}

in_waitline() { # muster sekunden [ab-zeile]
  local pat="$1" t="$2" from="${3:-0}" end=$((SECONDS + $2))
  while [ $SECONDS -lt $end ]; do
    if tail -n +"$((from + 1))" "$TB/sim/app.log" | grep -q -E "$pat"; then return 0; fi
    sleep 0.3
  done
  echo "nach ${t}s nicht in der Konsole: $pat" >&2
  return 1
}

in_unit() {
  local log="$TB/sim/unit.log" end
  in_run "${1:-trailbuddy-test.prg}" -t > /dev/null
  end=$((SECONDS + ${UNIT_WAIT:-300}))
  while [ $SECONDS -lt $end ]; do
    grep -q -E "^(PASSED|FAILED)" "$TB/sim/app.log" && break
    sleep 1
  done
  cp "$TB/sim/app.log" "$log"
  in_stop_app
  grep -E "FAIL|ERROR" "$log" | head -20 || true
  # monkeydo endet auch bei grünen Tests mit 1 — es zählt die Zeile.
  if grep -q -E "^PASSED" "$log"; then grep -E "^PASSED" "$log"; return 0; fi
  if grep -q -E "^FAILED" "$log"; then grep -E "^FAILED" "$log"; return 1; fi
  echo "kein Ergebnis nach ${UNIT_WAIT:-300} s (build/garmin/sim/unit.log)" >&2
  return 1
}

# Die Zustände der Ansicht, in dieser Reihenfolge im Bogen. Mit „~" nur
# zum Ansehen, nicht verglichen: der Lader bewegt sich, „berg" zeigt die
# Uhrzeit, bei „frage" läuft die Frist als Balken. „weitab" ist Szene 4 (1200 m neben der Linie): Nach
# „angekommen" bleibt die Zusammenfassung stehen, die eingepasste
# Übersicht zeigt der Vorführmodus deshalb nicht.
SCENES="~lader uebersicht anfahrt trail abseits angekommen weitab ~frage zahlen ~berg aktion zoom beenden aufnahme pause verwerfen frei"

in_shots() {
  local lang="$1" dev out ring k found=-1 tseen t loader=-1 i n
  dev=$(in_device)
  out="$TB/sim/shots/$dev/$lang"
  rm -rf "$out"; mkdir -p "$out"
  # Im Moment nur den Bildspeicher kopieren, umgewandelt wird am Ende:
  # Eine Umwandlung dauert unter Rosetta gut eine Sekunde, so lange
  # stünde die Szene nicht mehr.
  local raw="$STATE/raw"
  rm -rf "$raw"; mkdir -p "$raw"
  shot() {
    if [ -n "${2:-}" ]; then cp "$2" "$raw/$1.xwd"; else cp "$STATE/fb/Xvfb_screen0" "$raw/$1.xwd"; fi
    echo "  $1"
  }
  in_set_lang "$lang"

  # Lauf 1 — die Szenen ohne Taste. Lader und Übersicht: Bilder im Takt,
  # bis der Vorführmodus die erste Zeile schreibt. Die Übersicht ohne Fix
  # steht einen Takt (4 s) davor, der Lader davor — genommen wird das
  # letzte Bild vor der Zeile und eines gut sechs Sekunden davor.
  in_run trailbuddy-demo.prg --fresh > /dev/null
  ring="$STATE/ring"; rm -rf "$ring"; mkdir -p "$ring"
  k=0
  local end=$((SECONDS + 120))
  while [ $SECONDS -lt $end ]; do
    cp "$STATE/fb/Xvfb_screen0" "$ring/$k.xwd"
    date +%s%3N > "$ring/$k.t"
    if grep -q "^demo Linie jetzt" "$TB/sim/app.log"; then found=$k; break; fi
    k=$((k + 1))
    sleep 0.4
  done
  [ $found -ge 1 ] || { echo "Die App kam nicht bis zur ersten Szene (build/garmin/sim/app.log)" >&2; return 1; }
  tseen=$(cat "$ring/$found.t")
  for i in $(seq 0 $((found - 1))); do
    t=$(cat "$ring/$i.t")
    if [ $((tseen - t)) -ge 6500 ]; then loader=$i; fi
  done
  if [ $loader -ge 0 ]; then shot lader "$ring/$loader.xwd"; else echo "  (lader: zu kurz, kein Bild)"; fi
  shot uebersicht "$ring/$((found - 1)).xwd"
  for n in 0 1 2 3 4; do
    in_waitline "^demo Szene $n:" 30 || return 1
    sleep 1
    case $n in
      0) shot anfahrt ;; 1) shot trail ;; 2) shot abseits ;; 3) shot angekommen ;; 4) shot weitab ;;
    esac
  done
  in_waitline "^demo 501 Frage steht" 60 && { sleep 1; shot frage; }

  # Lauf 2 — Seiten und Menüs, ab der Anfahrt (Szene 0): Die nächste
  # Szene liegt auf dem Trail; „abseits" (Szene 2) holte die Karte nach
  # vorn (`leftRoute` → Seite 0).
  in_run trailbuddy-demo.prg --fresh > /dev/null
  in_waitline "^demo Szene 0:" 90 || return 1
  sleep 0.5
  in_press down; sleep 0.7; shot zahlen
  in_press down; sleep 0.7; shot berg
  in_press up; sleep 0.3; in_press up; sleep 0.5
  in_press up --long; sleep 1.5; shot aktion
  in_press start; sleep 1.5; shot zoom
  in_press back; sleep 1
  in_press back; sleep 1.5; shot beenden
  in_press back; sleep 0.5

  # Lauf 3 — die Aufnahme, ab der Szene auf dem Trail.
  in_run trailbuddy-demo.prg --fresh > /dev/null
  in_waitline "^demo Szene 1:" 90 || return 1
  sleep 0.5
  in_press start; sleep 1.5; shot aufnahme
  in_press start; sleep 1.5; shot pause
  in_press down; sleep 0.5; in_press down; sleep 0.5
  in_press start; sleep 1.5; shot verwerfen
  in_press back; sleep 0.5
  in_stop_app

  # Lauf 4 — freie Fahrt: der Store-Zweig ohne Route, ohne GPS.
  in_run trailbuddy-store.prg --fresh > /dev/null
  in_waitline "freie Fahrt" 60 && { sleep 4; shot frei; }
  in_stop_app

  local files=()
  for n in $SCENES; do
    n=${n#\~}
    [ -f "$raw/$n.xwd" ] || continue
    in_shot "shots/$dev/$lang/$n" "" "$raw/$n.xwd" > /dev/null
    files+=("$out/$n.png")
  done
  python3 /repo/tool/xwd_png.py --sheet --cols 6 "$out/sheet.png" "${files[@]}"
  echo "Bogen: build/garmin/sim/shots/$dev/$lang/sheet.png (${#files[@]} Bilder)"
}

if [ "${1:-}" = _in ]; then
  shift
  cmd="$1"; shift
  case "$cmd" in
    up) in_up "$@" ;;
    build) in_build ;;
    run) in_run "$@" ;;
    shot) in_shot "$@" ;;
    press) in_press "$@" ;;
    menu) in_menu "$@" ;;
    lang) in_set_lang "$1"; in_start_sim ;;
    unit) in_unit "$@" ;;
    shots) in_shots "$@" ;;
    wait) in_waitline "$1" "${2:-60}" ;;
    device) in_device ;;
    *) echo "unbekannt im Container: $cmd" >&2; exit 2 ;;
  esac
  exit $?
fi

# ---------------------------------------------------------------------------
# Auf dem Rechner: Docker, Bau vorbereiten, alles Weitere im Container.
# ---------------------------------------------------------------------------

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/garmin"
REF="${GARMIN_SHOTS_REF:-$ROOT/garmin/shots}"
DOCKERFILE="$ROOT/tool/garmin_sim.Dockerfile"

have_docker() { command -v docker > /dev/null 2>&1 && docker info > /dev/null 2>&1; }
running() { [ "$(docker inspect -f '{{.State.Running}}' "$C" 2>/dev/null)" = true ]; }
inside() { docker exec "$C" /repo/tool/garmin_sim.sh _in "$@"; }

image_tag() {
  local h
  h=$( { cat "$DOCKERFILE"; echo "${GARMIN_SIM_IMAGE:-}"; } | shasum -a 256 | cut -c1-12)
  echo "tb-garmin-sim:$h"
}

ensure_image() {
  local tag
  tag=$(image_tag)
  if ! docker image inspect "$tag" > /dev/null 2>&1; then
    echo "Bild $tag bauen (einmal; das Grundbild hat 4,5 GB) …" >&2
    local args=(--platform linux/amd64 -t "$tag")
    [ -n "${GARMIN_SIM_IMAGE:-}" ] && args+=(--build-arg "BASE=$GARMIN_SIM_IMAGE")
    docker build -q "${args[@]}" - < "$DOCKERFILE" > /dev/null
  fi
  echo "$tag"
}

cmd_up() {
  local device=fenix5 lang=deu tag
  while [ $# -gt 0 ]; do
    case "$1" in
      --lang) lang="$2"; shift 2 ;;
      -*) echo "unbekannt: $1" >&2; exit 2 ;;
      *) device="$1"; shift ;;
    esac
  done
  have_docker || { echo "Docker läuft nicht (open -a Docker, dann docker info)." >&2; exit 1; }
  tag=$(ensure_image)
  if running && [ "$(docker inspect -f '{{.Config.Image}}' "$C")" != "$tag" ]; then
    docker rm -f "$C" > /dev/null
  fi
  if ! running; then
    docker rm -f "$C" > /dev/null 2>&1 || true
    mkdir -p "$OUT/sim"
    docker run -d --name "$C" --platform linux/amd64 \
      -v "$ROOT:/repo:ro" -v "$OUT:/tb" \
      --entrypoint /bin/bash "$tag" -c 'sleep infinity' > /dev/null
  fi
  inside up "$device" "$lang"
}

need_up() {
  running || cmd_up
}

cmd_build() {
  need_up
  "$ROOT/tool/garmin_build.sh" --prepare-only "$@"
  inside build
}

cmd_shots() {
  local langs="deu eng" check=0 update=0 dev lang bad=0 n f
  while [ $# -gt 0 ]; do
    case "$1" in
      --lang) [ "$2" = all ] && langs="deu eng" || langs="$2"; shift 2 ;;
      --check) check=1; shift ;;
      --update) update=1; shift ;;
      *) echo "unbekannt: $1" >&2; exit 2 ;;
    esac
  done
  need_up
  dev=$(inside device)
  # Fester Stempel, damit zwei Bauten dasselbe Bild zeichnen; nur die
  # erfundene Testroute (eine eigene Route gehört nie in ein Referenzbild).
  GARMIN_STAMP="sim" "$ROOT/tool/garmin_build.sh" --prepare-only --store --run > /dev/null
  inside build
  GARMIN_STAMP="sim" "$ROOT/tool/garmin_build.sh" --prepare-only --demo > /dev/null
  grep -q '^route=testroute$' "$OUT/src/build.env" || { echo "shots nur mit der Testroute" >&2; exit 2; }
  inside build
  for lang in $langs; do
    echo "--- $dev, $lang ---"
    inside shots "$lang" || bad=1
  done
  [ $check = 1 ] || [ $update = 1 ] || exit $bad
  for lang in $langs; do
    local got="$OUT/sim/shots/$dev/$lang" want="$REF/$dev/$lang"
    if [ $update = 1 ]; then
      mkdir -p "$want"
      rm -f "$want"/*.png
      for n in $SCENES; do
        case "$n" in "~"*) continue ;; esac
        [ -f "$got/$n.png" ] && cp "$got/$n.png" "$want/"
      done
      echo "Referenzen: ${want#"$ROOT"/} ($(ls "$want" | wc -l | tr -d ' ') Bilder)"
      continue
    fi
    if [ ! -d "$want" ]; then
      echo "FEHLT Referenzen ${want#"$ROOT"/} — erst shots --update"; bad=1; continue
    fi
    for n in $SCENES; do
      case "$n" in "~"*) continue ;; esac
      f="$got/$n.png"
      if [ ! -f "$want/$n.png" ]; then echo "FEHLT Referenz $lang/$n"; bad=1; continue; fi
      if [ ! -f "$f" ]; then echo "FEHLT Bild $lang/$n"; bad=1; continue; fi
      if python3 "$ROOT/tool/xwd_png.py" --diff "$want/$n.png" "$f" "$got/diff-$n.png" > /dev/null; then
        echo "OK    $lang/$n"
      else
        echo "ANDERS $lang/$n — ${got#"$ROOT"/}/diff-$n.png"; bad=1
      fi
    done
  done
  exit $bad
}

case "${1:-}" in
  up) shift; cmd_up "$@" ;;
  build) shift; cmd_build "$@" ;;
  run) shift; need_up; inside run "$@" ;;
  shot) shift; need_up; inside shot "$@" ;;
  press) shift; need_up; inside press "$@" ;;
  menu)
    shift
    if [ "${1:-}" = --list ]; then in_menu --list; exit 0; fi
    need_up; inside menu "$@" ;;
  lang) shift; need_up; inside lang "$@" ;;
  wait) shift; need_up; inside wait "$@" ;;
  unit)
    shift
    need_up
    "$ROOT/tool/garmin_build.sh" --prepare-only --test > /dev/null
    inside build
    inside unit
    ;;
  shots) shift; cmd_shots "$@" ;;
  down) docker rm -f "$C" > /dev/null 2>&1 || true; echo "Container weg." ;;
  *)
    sed -n '2,51p' "$0" | sed 's/^# \{0,1\}//'
    exit 64
    ;;
esac
