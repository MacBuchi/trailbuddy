#!/bin/sh
# Startet den offiziellen Dart- und Flutter-MCP-Server für Agenten
# (`.mcp.json`, #237). Die EINE Stelle für die Auswahl der Werkzeuge:
#
#   --enable run_tests   gehört zur Kategorie `cli` und ist ab Werk AUS
#                        (gemessen an Server 1.1.3 mit `tools/list`).
#   dart_format          AUS — CLAUDE.md verbietet `dart format`; der
#                        Formatter bricht hier Dutzende Dateien anders um.
#   dart_fix             AUS — schreibt Code um, ohne dass jemand hinsieht.
#   create_project       AUS — es gibt nichts anzulegen.
#   widget_inspector, flutter_driver_command, hot_reload, hot_restart
#                        AUS — brauchen eine laufende App auf einem Gerät;
#                        in einer Cloud-Sitzung gibt es keins.
#
# Übrig bleiben analyze_files, lsp, run_tests, pub, pub_dev_search, roots,
# read_package_uris, rip_grep_packages, get_runtime_errors, dtd, vm_service.
#
# Das SDK: erst `dart` auf dem PATH (lokal), dann $FLUTTER_ROOT, dann das
# Flutter des Cloud-Images. Ohne SDK endet das Skript mit einer Meldung
# statt mit einem Server, der still nicht antwortet.

set -eu

DART=""
if command -v dart >/dev/null 2>&1; then
  DART=$(command -v dart)
elif [ -n "${FLUTTER_ROOT:-}" ] && [ -x "$FLUTTER_ROOT/bin/dart" ]; then
  DART="$FLUTTER_ROOT/bin/dart"
elif [ -x /opt/flutter/bin/dart ]; then
  FLUTTER_ROOT=/opt/flutter
  export FLUTTER_ROOT
  DART=/opt/flutter/bin/dart
fi

if [ -z "$DART" ]; then
  echo "dart_mcp.sh: kein Dart-SDK gefunden (PATH, FLUTTER_ROOT)." >&2
  exit 1
fi

exec "$DART" mcp-server \
  --enable run_tests \
  --disable dart_format,dart_fix,create_project,widget_inspector,flutter_driver_command,hot_reload,hot_restart
