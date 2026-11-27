#!/usr/bin/env bash
# Fahrt im Hintergrund auf dem iOS-Simulator (#644, Paket 3).
#
#   TB_MAIL=… TB_PW=… tool/ios_ride_bench.sh [--notice] <simulator-udid> [sekunden]
#
# Spielt eine erfundene Strecke als Standort ab (einstellige Breite, kein
# Ort von irgendwem), erlaubt den Standort „Beim Benutzen", startet
# `integration_test/ios_ride_background_test.dart`, schickt die App nach
# dem Start der Fahrt in den Hintergrund (Einstellungen-App vorn) und holt
# sie nach N Sekunden (Vorgabe 90) zurück. Der Test prüft die Datei.
# `--notice` (Paket 3b): der Dienst zeigt dazu alle 30 s eine Frage und
# spricht einen Satz (`TB_SERVICE_BENCH`); das Skript schreibt die
# `TB-VOICE`- und `TB-BENCH`-Zeilen des Systemprotokolls mit — dort steht,
# ob die Stimme im Hintergrund die Audio-Sitzung bekam (ios/CLAUDE.md).
# Nur Simulator; ein Gerät braucht die Abnahme in #644.
set -euo pipefail

notice=false
if [[ "${1:-}" == "--notice" ]]; then notice=true; shift; fi
udid="${1:?Simulator-UDID angeben (xcrun simctl list devices booted)}"
seconds="${2:-90}"
: "${TB_MAIL:?TB_MAIL fehlt}" "${TB_PW:?TB_PW fehlt}"
bundle=de.mcbuchi.trailbuddy
root="$(cd "$(dirname "$0")/.." && pwd)"
log="$(mktemp -t ios_ride_bench)"

cleanup() {
  xcrun simctl location "$udid" clear >/dev/null 2>&1 || true
  [[ -n "${test_pid:-}" ]] && kill "$test_pid" >/dev/null 2>&1 || true
  [[ -n "${log_pid:-}" ]] && kill "$log_pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT

xcrun simctl bootstatus "$udid" -b >/dev/null
# Ein Rechteck von gut 2 km bei 5 m/s — erfunden, siehe Kopf.
xcrun simctl location "$udid" start --speed=5 --interval=1 \
  7.000,11.000 7.010,11.000 7.010,11.010 7.000,11.010 7.000,11.000

cd "$root"
syslog="$(mktemp -t ios_ride_bench_syslog)"
if $notice; then
  xcrun simctl spawn "$udid" log stream --style compact \
    --predicate 'eventMessage CONTAINS "TB-VOICE" OR eventMessage CONTAINS "TB-BENCH"' \
    >"$syslog" 2>&1 &
  log_pid=$!
fi
flutter test integration_test/ios_ride_background_test.dart -d "$udid" \
  --dart-define=TB_MAIL="$TB_MAIL" --dart-define=TB_PW="$TB_PW" \
  --dart-define=TB_SERVICE_BENCH="$notice" \
  --dart-define=TB_BG_SECONDS="$seconds" >"$log" 2>&1 &
test_pid=$!

echo "Warte auf den Start der Fahrt … (Protokoll: $log)"
until grep -q 'TB-BENCH ride-started' "$log"; do
  # `flutter test` installiert die App neu, und eine vorher erteilte
  # Erlaubnis kann dabei verfallen — dann wartet die App auf den Dialog
  # des Systems, den kein Dart-Test bedienen kann. Also immer wieder.
  xcrun simctl privacy "$udid" grant location "$bundle" >/dev/null 2>&1 || true
  if ! kill -0 "$test_pid" 2>/dev/null; then
    tail -40 "$log"; echo "Test endete vor dem Start der Fahrt."; exit 1
  fi
  sleep 2
done
echo "Fahrt läuft — App $seconds s im Hintergrund."
xcrun simctl launch "$udid" com.apple.Preferences >/dev/null
sleep "$seconds"
xcrun simctl launch "$udid" "$bundle" >/dev/null
wait "$test_pid" && status=0 || status=$?
grep 'TB-BENCH' "$log" || true
if $notice; then
  echo "Systemprotokoll (Zeit, Zeile):"
  grep -E 'TB-(VOICE|BENCH)' "$syslog" |
    sed -E 's/^([0-9-]+ [0-9:.]+).*(TB-.*)$/\1 \2/' || true
fi
tail -5 "$log"
exit "$status"
