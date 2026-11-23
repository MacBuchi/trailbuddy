# iOS map probe

`tool/ios_map_bench.sh <booted-simulator-udid>` runs a small, disposable
Flutter app on an already booted iOS simulator. It needs Flutter, Xcode,
CocoaPods, Python 3 and network access to resolve the pinned packages.
List simulators with `xcrun simctl list devices booted`.

The probe generates synthetic raster and vector MBTiles, renders each local
file with MapLibre 0.3.7+1, and checks a screenshot for a red tile. It repeats
each case with the tile removed and expects the blue background. The style has
no network sources. The script checks pixels, but does not count network
requests. It creates a temporary project and a temporary copy of the iOS plugin;
that copy excludes the bundled generated header from CocoaPods to work around a
header collision. This is a diagnostic workaround, not a production fix.
Temporary files are removed on exit; the simulator app remains installed.

A pass proves only these synthetic local tiles render in the selected simulator.
It does not prove the TrailBuddy app's styles, saved-area lifecycle, network
silence, iOS 16 compatibility, hardware performance or background behaviour.
