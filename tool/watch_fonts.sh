#!/usr/bin/env bash
# Misst die Systemschriften einer Uhr im Connect-IQ-Simulator (#511, S4):
# Höhe je Schriftstufe und Breite jedes Zeichens, das die Uhr-App zeigt,
# dazu ganze Sätze als Gegenprobe (Breite des Satzes = Summe der Zeichen?).
# Das Ergebnis steht in tool/watch_fonts/<gerät>.json und ist die Grundlage
# des Dart-Abbilds (test/garmin/watch_twin.dart) — CI hat weder SDK noch
# die Schriften der Uhr (.cft, Garmins eigenes Format).
#
#   tool/watch_fonts.sh [gerät …]      Vorgabe: fenix5s fenix5 fenix6 fenix6xpro
#
# Ein eigenes kleines Projekt unter build/watch_fonts (nur ein Test, keine
# App-Teile) — die Uhr-App bleibt unberührt, ihr Speicher auch.
# Braucht das SDK und den Entwicklerschlüssel wie tool/garmin_build.sh;
# der Simulator muss bereit sein, bevor monkeydo startet (garmin/CLAUDE.md).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CIQ="$HOME/Library/Application Support/Garmin/ConnectIQ"
SDK="${GARMIN_SDK:-}"
if [ -z "$SDK" ] && [ -f "$CIQ/current-sdk.cfg" ]; then
  SDK=$(tr -d '\n' < "$CIQ/current-sdk.cfg")
fi
KEY="${GARMIN_DEV_KEY:-$HOME/.connectiq/developer_key.der}"
OUT="$ROOT/build/watch_fonts"
devices=("$@")
if [ ${#devices[@]} -eq 0 ]; then devices=(fenix5s fenix5 fenix6 fenix6xpro); fi

if [ -z "$SDK" ] || [ ! -x "$SDK/bin/monkeyc" ]; then
  echo "Kein Connect-IQ-SDK gefunden — SDK-Manager installieren oder GARMIN_SDK setzen." >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT/source" "$OUT/resources/strings" "$OUT/log"
products=""
for d in "${devices[@]}"; do products="$products<iq:product id=\"$d\"/>"; done
cat > "$OUT/manifest.xml" <<XML
<?xml version="1.0"?>
<iq:manifest xmlns:iq="http://www.garmin.com/xml/connectiq" version="3">
  <iq:application id="5b0c3a3e9d2f4f6c8a1e7d2b4c6f8a10" type="watch-app" name="@Strings.AppName"
      entry="FontsApp" launcherIcon="@Drawables.LauncherIcon" minApiLevel="3.1.0">
    <iq:products>$products</iq:products>
    <iq:permissions/>
    <iq:languages/>
    <iq:barrels/>
  </iq:application>
</iq:manifest>
XML
cat > "$OUT/monkey.jungle" <<'J'
project.manifest = manifest.xml
J
cat > "$OUT/resources/strings/strings.xml" <<'X'
<strings><string id="AppName">Fonts</string></strings>
X
mkdir -p "$OUT/resources/drawables"
cp "$ROOT/garmin/resources/drawables/launcher_icon.png" "$OUT/resources/drawables/"
cat > "$OUT/resources/drawables/drawables.xml" <<'X'
<drawables><bitmap id="LauncherIcon" filename="launcher_icon.png"/></drawables>
X
python3 "$ROOT/tool/watch_layout.py" --fonts-source > "$OUT/source/Fonts.mc"

for d in "${devices[@]}"; do
  prg="$OUT/fonts-$d.prg"
  "$SDK/bin/monkeyc" -d "$d" -f "$OUT/monkey.jungle" -o "$prg" -y "$KEY" -w --unit-test > "$OUT/log/build-$d.txt" 2>&1 \
    || { cat "$OUT/log/build-$d.txt" >&2; exit 1; }
  # Nach einem Gerätewechsel schrieb monkeydo sonst nichts (garmin/CLAUDE.md).
  pkill -f "ConnectIQ.app" 2>/dev/null || true
  pkill -f monkeydo 2>/dev/null || true
  sleep 2
  open "$SDK/bin/ConnectIQ.app"
  sleep 12
  "$SDK/bin/monkeydo" "$prg" "$d" -t > "$OUT/log/run-$d.txt" 2>&1 || true
  python3 "$ROOT/tool/watch_layout.py" --fonts-parse "$OUT/log/run-$d.txt" --device "$d" \
    --out "$ROOT/tool/watch_fonts/$d.json"
done
pkill -f "ConnectIQ.app" 2>/dev/null || true
