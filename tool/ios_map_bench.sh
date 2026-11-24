#!/usr/bin/env bash
# A disposable simulator probe. Usage: tool/ios_map_bench.sh <booted-simulator-udid>
set -euo pipefail
if [[ $# -ne 1 ]]; then
  echo 'Usage: tool/ios_map_bench.sh <booted-simulator-udid>' >&2
  exit 2
fi
simulator="$1"
root="$(cd "$(dirname "$0")/.." && pwd)"
fixture="$root/tool/ios_map_probe/fixture.py"
work="$(mktemp -d "${TMPDIR:-/tmp}/tb-ios-map-bench.XXXXXX")"
trap 'rm -rf "$work"' EXIT

xcrun simctl list devices booted --json | python3 -c 'import json,sys; d=json.load(sys.stdin); wanted=sys.argv[1]; sys.exit(0 if any(x["udid"] == wanted for devices in d["devices"].values() for x in devices) else 1)' "$simulator" || {
  echo 'The requested simulator must already be booted.' >&2
  exit 1
}

flutter create --empty --no-pub --platforms=ios --project-name tb_ios_map_bench --org org.example "$work/app" >/dev/null
cd "$work/app"
cat > pubspec.yaml <<'YAML'
name: tb_ios_map_bench
version: 0.0.1+1
publish_to: none
environment:
  sdk: '>=3.11.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  maplibre: 0.3.7+1
  path_provider: 2.1.6
flutter:
  config:
    enable-swift-package-manager: false
  uses-material-design: true
  assets:
    - assets/
YAML
flutter pub get >/dev/null
# Copy only this plugin: never edit the shared pub cache. This is a diagnostic
# workaround for its generated Swift header collision, not a production fix.
python3 - "$work/plugin" <<'PY'
import json, pathlib, shutil, sys, urllib.parse
config = json.loads(pathlib.Path('.dart_tool/package_config.json').read_text())
pkg = next(p for p in config['packages'] if p['name'] == 'maplibre_ios')
uri = urllib.parse.urlparse(pkg['rootUri'])
if uri.scheme != 'file':
    raise SystemExit('Expected a local maplibre_ios package')
shutil.copytree(urllib.parse.unquote(uri.path), sys.argv[1])
podspec = pathlib.Path(sys.argv[1]) / 'ios/maplibre_ios.podspec'
text = podspec.read_text()
needle = "  s.dependency 'Flutter'"
if text.count(needle) != 1:
    raise SystemExit('MapLibre podspec has changed; review the diagnostic workaround')
podspec.write_text(text.replace(needle, "  s.exclude_files = 'maplibre_ios/Sources/maplibre_ios/MapLibreIos.h'\n" + needle))
PY
printf 'dependency_overrides:\n  maplibre_ios:\n    path: %s/plugin\n' "$work" > pubspec_overrides.yaml
cp "$root/tool/ios_map_probe/main.dart.template" lib/main.dart
python3 "$fixture" generate assets
flutter pub get >/dev/null

for kind in raster vector; do
  for case_name in tile empty; do
    mode="${kind}_${case_name}"
    expected=red
    [[ "$case_name" == empty ]] && expected=blue
    echo "Checking $mode (expected $expected)..."
    flutter run -d "$simulator" --debug --no-resident --dart-define="BENCH_MODE=$mode" >/dev/null
    passed=false
    for _ in {1..15}; do
      xcrun simctl io "$simulator" screenshot "$work/screen.png" >/dev/null 2>&1
      sips -s format bmp "$work/screen.png" --out "$work/screen.bmp" >/dev/null
      if python3 "$fixture" check "$work/screen.bmp" "$expected" 2>/dev/null; then
        passed=true
        break
      fi
      sleep 1
    done
    if [[ "$passed" != true ]]; then
      echo "$mode did not display the expected colour" >&2
      exit 1
    fi
  done
done
echo 'All synthetic MBTiles checks passed. Real offline areas and iOS devices remain untested.'
