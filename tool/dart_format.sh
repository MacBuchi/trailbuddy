#!/usr/bin/env bash
# Formatiert den Dart-Code des Repos — oder prüft ihn (`--check`, CI).
#
# Eine Quelle für die Dateiliste, damit lokal und in CI dasselbe gilt:
# lib/, test/, integration_test/, tool/. Ausgenommen sind ERZEUGTE
# Dateien, deren Generator sein eigenes Layout prüft:
#   - lib/core/widgets/trailbuddy_logo_geometry.dart (tool/brand_icons.py
#     --check; der Formatter zerlegte die Stichproben-Tabelle in eine Zahl
#     je Zeile)
# Die Handoff-Kopie unter docs/design/ bleibt, wie sie geliefert wurde.
#
#   tool/dart_format.sh           formatieren
#   tool/dart_format.sh --check   nur prüfen (Exit 1, wenn etwas abweicht)
set -euo pipefail
cd "$(dirname "$0")/.."

# Ohne `mapfile`: Die Bash des Mac ist 3.2. Pfade ohne Leerzeichen
# (Repo-Konvention), deshalb reicht das Aufteilen an Zeilenenden.
IFS=$'\n' read -r -d '' -a files < <(
  git ls-files -- 'lib/*.dart' 'test/*.dart' 'integration_test/*.dart' 'tool/*.dart' |
    grep -v -x -e 'lib/core/widgets/trailbuddy_logo_geometry.dart'
  printf '\0'
) || true

if [[ "${1:-}" == "--check" ]]; then
  if ! dart format --output=none --set-exit-if-changed "${files[@]}"; then
    echo "::error::Dart-Code nicht formatiert — tool/dart_format.sh laufen lassen"
    exit 1
  fi
else
  dart format "${files[@]}"
fi
