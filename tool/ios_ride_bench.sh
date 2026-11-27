#!/usr/bin/env bash
# Fahrt im Hintergrund auf dem iOS-Simulator (#644, Paket 3).
#
#   TB_MAIL=… TB_PW=… tool/ios_ride_bench.sh <simulator-udid> [sekunden]
#
# Spielt eine erfundene Strecke als Standort ab (einstellige Breite, kein
# Ort von irgendwem), erlaubt den Standort „Beim Benutzen", startet
# `integration_test/ios_ride_background_test.dart`, schickt die App nach
# dem Start der Fahrt in den Hintergrund (Einstellungen-App vorn) und holt
# sie nach N Sekunden (Vorgabe 90) zurück. Der Test prüft die Datei.
# Nur Simulator; ein Gerät braucht die Abnahme in #644.
set -euo pipefail

udid="${1:?Simulator-UDID angeben (xcrun simctl list devices booted)}"
seconds="${2:-90}"
: "${TB_MAIL:?TB_MAIL fehlt}" "${TB_PW:?TB_PW fehlt}"
bundle=de.mcbuchi.trailbuddy
root="$(cd "$(dirname "$0")/.." && pwd)"
log="$(mktemp -t ios_ride_bench)"

cleanup() {
  xcrun simctl location "$udid" clear >/dev/null 2>&1 || true
  [[ -n "${test_pid:-}" ]] && kill "$test_pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT

xcrun simctl bootstatus "$udid" -b >/dev/null
# Ein Rechteck von gut 2 km bei 5 m/s — erfunden, siehe Kopf.
xcrun simctl location "$udid" start --speed=5 --interval=1 \
  7.000,11.000 7.010,11.000 7.010,11.010 7.000,11.010 7.000,11.000

cd "$root"
flutter test integration_test/ios_ride_background_test.dart -d "$udid" \
  --dart-define=TB_MAIL="$TB_MAIL" --dart-define=TB_PW="$TB_PW" \
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
tail -5 "$log"
exit "$status"
