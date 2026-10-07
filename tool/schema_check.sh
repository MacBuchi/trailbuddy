#!/usr/bin/env bash
# Schema smoke test: runs the exact PostgREST queries the app uses against
# a Supabase project (the local stack in the Schema Dry Run; later the live
# project). Uses only the public publishable key — RLS keeps all data
# private, but schema errors (missing columns, renamed FK embeds, changed
# RPC signatures) surface regardless of RLS.
#
# Taken over from PilzBuddy (guard for the bug class behind its issue #27:
# app code that expects schema the DB does not have). The check list below
# is TrailBuddy's; extend it whenever a repository in lib/data/ starts using
# new columns/embeds/RPCs.
#
# Target: SUPABASE_URL/SUPABASE_KEY, else the defaults in
# lib/core/supabase_config.dart (works for both a const and a
# `String.fromEnvironment(..., defaultValue: '…')`: the first quoted
# https-URL and the first quoted sb_publishable_ key in the file). In CI
# (CI=true) a missing target is an error; locally only a warning — there
# is no live project yet (concept, decision 9).
#
# Two kinds of checks, and the difference matters:
#   check_get           — anon MAY read (app_config): a JSON list is success.
#   check_get_protected — anon has NO grant: 42501 is success. That is the
#     case for almost every table here, because schema.sql revokes all and
#     grants only to authenticated. Postgres resolves the columns BEFORE the
#     privilege check (measured in PilzBuddy on the local stack: complete
#     query ⇒ 42501, missing column ⇒ 42703, missing table ⇒ PGRST205, bad
#     embed ⇒ PGRST200), so a 42501 still proves table, columns and embeds
#     exist. The same code is expected for `trails` (no grant for anyone)
#     and for the view recordings_visible (grant only to authenticated) —
#     NOT re-measured against PostgREST in this repo yet; the first Dry Run
#     will confirm or correct it.
set -euo pipefail

CONFIG=lib/core/supabase_config.dart
URL="${SUPABASE_URL:-}"
KEY="${SUPABASE_KEY:-}"
if [ -z "$URL" ] && [ -f "$CONFIG" ]; then
  # `|| true`: grep ohne Treffer gäbe unter pipefail einen stillen Abbruch.
  URL=$(grep -o "['\"]https\{0,1\}://[^'\"]*['\"]" "$CONFIG" | head -1 | tr -d "'\"" || true)
fi
if [ -z "$KEY" ] && [ -f "$CONFIG" ]; then
  KEY=$(grep -o "['\"]sb_publishable_[^'\"]*['\"]" "$CONFIG" | head -1 | tr -d "'\"" || true)
fi
if [ "${1:-}" != "--self-test" ] && { [ -z "$URL" ] || [ -z "$KEY" ]; }; then
  if [ -n "${CI:-}" ]; then
    echo "::error::Kein Ziel: SUPABASE_URL/SUPABASE_KEY setzen (Dry Run: aus \`supabase status -o json\`) oder Defaults in $CONFIG hinterlegen."
    exit 1
  fi
  echo "::warning::Kein Ziel (weder SUPABASE_URL/SUPABASE_KEY noch Defaults in $CONFIG) — es gibt noch kein Live-Projekt, nichts zu prüfen."
  exit 0
fi

fail=0
# Getrennt gezählt: „wir konnten nicht fragen" ist keine Aussage über
# das Schema. Siehe [response_diagnosis].
transport_fail=0

check_get() {
  local name="$1" path="$2" out
  out=$(curl -s --max-time 20 "$URL$path" -H "apikey: $KEY" || echo '{"code":"curl","message":"Verbindung fehlgeschlagen"}')
  verdict "$name" "$out"
}

# Für RPCs, die anon NICHT aufrufen darf (Konto-Löschung, Buddy-Suche,
# Aufzeichnung beisteuern). Ein Fehler ist hier der Erfolgsfall — aber
# nur der richtige: PGRST202 hieße „Funktion fehlt" (Patch nicht
# eingespielt), und eine erfolgreiche Antwort hieße, dass anon die
# Funktion ausführen darf. Beides muss auffallen. Der Body muss zur
# Signatur passen, sonst antwortet PostgREST mit PGRST202 statt mit dem
# erwarteten Rechte-Fehler.
check_rpc_protected() {
  local name="$1" fn="$2" body="$3" out
  out=$(curl -s --max-time 20 -X POST "$URL/rest/v1/rpc/$fn" \
    -H "apikey: $KEY" -H "Content-Type: application/json" -d "$body" \
    || echo '{"code":"curl","message":"Verbindung fehlgeschlagen"}')
  # **Zuerst die Leitung.** Die Ersatzantwort eines gescheiterten curl
  # trägt selbst ein `"code"` — ohne diese Prüfung hieße ein Netzaussetzer
  # „vorhanden und für anon gesperrt": ein grünes Häkchen auf einer
  # RECHTE-Prüfung. Ein erfundener Erfolg kostet die Prüfung.
  if [ "$(response_diagnosis "$out")" = transport ]; then
    echo "::error::Schema-Check unentschieden: $name — der Dienst war nicht erreichbar. Über die Rechte sagt dieser Lauf NICHTS; wiederholen. Antwort: ${out:-<leer>}"
    transport_fail=1
  elif printf '%s' "$out" | grep -q 'PGRST202'; then
    echo "::error::Schema-Check fehlgeschlagen: $name — Funktion fehlt in der DB: $out"
    fail=1
  elif printf '%s' "$out" | grep -q '"code"'; then
    echo "✓ $name (vorhanden und für anon gesperrt)"
  else
    echo "::error::Schema-Check fehlgeschlagen: $name — anon darf die Funktion ausführen!"
    fail=1
  fi
}

# Für Tabellen und Sichten, die anon GAR NICHT lesen darf (kein Grant,
# nicht nur RLS). Nur 42501 ist der Erfolgsfall; eine Liste hieße, dass
# anon lesen darf; jeder andere Code ist ein Schemafehler (42703 fehlende
# Spalte, PGRST200 kaputter Embed, PGRST205 fehlende Tabelle).
check_get_protected() {
  local name="$1" path="$2" out
  out=$(curl -s --max-time 20 "$URL$path" -H "apikey: $KEY" || echo '{"code":"curl","message":"Verbindung fehlgeschlagen"}')
  if [ "$(response_diagnosis "$out")" = transport ]; then
    echo "::error::Schema-Check unentschieden: $name — der Dienst war nicht erreichbar. Über die Rechte sagt dieser Lauf NICHTS; wiederholen. Antwort: ${out:-<leer>}"
    transport_fail=1
  elif printf '%s' "$out" | grep -q '"code":"42501"'; then
    echo "✓ $name (vorhanden und für anon gesperrt)"
  elif printf '%s' "$out" | grep -q '"code"'; then
    echo "::error::Schema-Check fehlgeschlagen: $name — $out"
    fail=1
  else
    echo "::error::Schema-Check fehlgeschlagen: $name — anon darf lesen: $out"
    fail=1
  fi
}

# Die Mindestversion aus der Antwort — LEER, wenn sie nicht drinsteht.
#
# Eigene Funktion, damit sich die drei Fälle (Dienst antwortet nicht /
# Tabelle leer / Zeile ohne Feld) ohne laufende Datenbank prüfen lassen:
# `tool/schema_check.sh --self-test`.
app_config_version() {
  local status="$1" body="$2"
  [ "$status" = "200" ] || return 0
  printf '%s' "$body" \
    | sed -n 's/.*"minimum_supported_version":"\([^"]*\)".*/\1/p'
}

# Was sagt eine Antwort — und worüber?
#
# `transport` heißt: Wir haben den Dienst NICHT erreicht. Das ist eine
# Aussage über die Leitung, nicht über das Schema, und darf deshalb auch
# keine über das Schema auslösen. Ein LEERER Rumpf zählt mit dazu:
# PostgREST antwortet auf die Abfragen hier immer mit etwas (und sei es
# `[]`). Nichts zu bekommen heißt, dass wir nichts erfahren haben.
response_diagnosis() {
  local body="$1"
  if [ -z "$body" ] || printf '%s' "$body" | grep -q '"code":"curl"'; then
    echo transport
  elif printf '%s' "$body" | grep -q '"code"'; then
    echo schema
  else
    echo ok
  fi
}

app_config_diagnosis() {
  local status="$1" body="$2"
  if [ "$status" != "200" ]; then
    echo "dienst"
  elif [ "$body" = "[]" ]; then
    echo "leer"
  elif [ -z "$(app_config_version "$status" "$body")" ]; then
    echo "feld"
  else
    echo "ok"
  fi
}

if [ "${1:-}" = "--self-test" ]; then
  fehler=0
  probe() {
    local erwartet="$1" status="$2" body="$3"
    local ist
    ist=$(app_config_diagnosis "$status" "$body")
    if [ "$ist" = "$erwartet" ]; then
      echo "  ✓ $status ${body:-<leer>} → $ist"
    else
      echo "  ✗ $status ${body:-<leer>} → $ist statt $erwartet"
      fehler=1
    fi
  }
  echo "app_config-Diagnose:"
  probe dienst 000 ""
  probe dienst 503 ""
  probe dienst 500 '{"code":"XX000"}'
  probe leer   200 '[]'
  probe feld   200 '[{"id":true}]'
  probe ok     200 '[{"id":true,"minimum_supported_version":"1.2.3"}]'
  [ "$(app_config_version 200 '[{"minimum_supported_version":"1.2.3"}]')" \
    = "1.2.3" ] || { echo "  ✗ Version wird nicht gelesen"; fehler=1; }
  # Ohne 200 gibt es keine Version — auch wenn im Rumpf eine steht.
  [ -z "$(app_config_version 500 '[{"minimum_supported_version":"9.9.9"}]')" ] \
    || { echo "  ✗ Version aus einer Fehlantwort gelesen"; fehler=1; }
  echo "Antwort-Diagnose:"
  probe_response() {
    local erwartet="$1" body="$2" ist
    ist=$(response_diagnosis "$body")
    if [ "$ist" = "$erwartet" ]; then
      echo "  ✓ ${body:-<leer>} → $ist"
    else
      echo "  ✗ ${body:-<leer>} → $ist statt $erwartet"
      fehler=1
    fi
  }
  # Genau die Antwort, die ein gescheiterter curl einsetzt.
  probe_response transport '{"code":"curl","message":"Verbindung fehlgeschlagen"}'
  probe_response transport ""
  # Ein echter PostgREST-Fehler bleibt einer.
  probe_response schema '{"code":"42703","message":"column does not exist"}'
  probe_response schema '{"code":"PGRST202"}'
  probe_response ok '[]'
  probe_response ok '[{"id":"x"}]'
  [ "$fehler" = 0 ] && echo "schema_check self-test: ok"
  exit "$fehler"
fi

verdict() {
  local name="$1" out="$2"
  case "$(response_diagnosis "$out")" in
  transport)
    echo "::error::Schema-Check unentschieden: $name — der Dienst war nicht erreichbar. Das ist eine Aussage über die LEITUNG, nicht über das Schema; den Lauf wiederholen. Antwort: ${out:-<leer>}"
    transport_fail=1
    ;;
  schema)
    echo "::error::Schema-Check fehlgeschlagen: $name — $out"
    fail=1
    ;;
  *)
    echo "✓ $name"
    ;;
  esac
}

# profiles: die Spalten aus ProfileRepository. anon hat keinen Grant.
check_get_protected "profiles-Spalten" \
  "/rest/v1/profiles?select=id,username,display_name,avatar,created_at&limit=1"

# friendships: exakt die Query aus FriendRepository.fetchFriendships, mit
# den beiden Embeds über den Constraint-NAMEN. Benennt jemand den
# Fremdschlüssel um, fällt es HIER auf (PGRST200) und nicht im Feld.
check_get_protected "friendships-Embed" \
  "/rest/v1/friendships?select=id,status,requester_id,addressee_id,created_at,requester:profiles!friendships_requester_id_fkey(username,avatar),addressee:profiles!friendships_addressee_id_fkey(username,avatar)&limit=1"

# friend_aliases: die Spalten aus FriendRepository.aliasColumns.
check_get_protected "friend_aliases-Spalten (Aliase)" \
  "/rest/v1/friend_aliases?select=owner_id,friend_id,alias,updated_at&limit=1"

# recordings_visible: die Sicht, aus der die App die Linien liest
# (GeoJSON + Länge, Konzept Abschnitt 3). Grant nur für authenticated.
check_get_protected "recordings_visible-Spalten (Aufzeichnungen)" \
  "/rest/v1/recordings_visible?select=id,trail_id,user_id,source,recorded_at,reversed,quality,created_at,geojson,length_m,ele&limit=1"

# trail_details: die Spalten des Beitrags (TrailRepository). status und
# status_at liest die App seit Patch 013 nicht mehr, Clients bis 0.48.0
# schon — deshalb stehen sie weiter hier.
check_get_protected "trail_details-Spalten (Beiträge)" \
  "/rest/v1/trail_details?select=trail_id,user_id,name,description,grade,traits,rating,two_way,link,visibility,status,status_at,created_at,updated_at&limit=1"

# trail_reports (Patch 013): Meldungen und Zustände, exakt die Query aus
# TrailRepository.fetchReports samt Embed über den Constraint-NAMEN.
check_get_protected "trail_reports-Embed (Meldungen)" \
  "/rest/v1/trail_reports?select=id,trail_id,user_id,kind,status,condition,confirmed,reported_at,reporter:profiles!trail_reports_user_id_fkey(username)&limit=1"

# trail_notes: Hinweise für Buddys (Patch 004), exakt die Query aus
# TrailRepository.fetchNotes samt Embed über den Constraint-NAMEN.
check_get_protected "trail_notes-Embed (Hinweise)" \
  "/rest/v1/trail_notes?select=id,trail_id,user_id,body,created_at,author:profiles!trail_notes_user_id_fkey(username)&limit=1"

# trails: für NIEMANDEN lesbar (Konzept 4.6) — nicht einmal mit Konto.
# Hier lässt sich nur anon prüfen; dass auch authenticated 42501 bekommt,
# beweist tool/matcher_check.sql direkt in SQL.
check_get_protected "trails ist gesperrt" \
  "/rest/v1/trails?select=id&limit=1"

# feedback: Spalten, die App (Insert) und ein späterer Bot (Select) nutzen.
check_get_protected "feedback-Spalten" \
  "/rest/v1/feedback?select=id,user_id,type,message,app_version,client_id,processed_at,created_at&limit=1"

# error_reports: die Spalten, die ErrorReportRepository schreibt. anon darf
# INSERT, aber nicht SELECT — also ebenfalls 42501 auf die Leseabfrage.
check_get_protected "error_reports-Spalten" \
  "/rest/v1/error_reports?select=id,user_id,context,error_type,message,stack,app_version,platform,created_at&limit=1"

# push_devices (Patch 008): die Spalten, die PushRepository schreibt. Kein
# Grant für anon, also 42501 — und der `on conflict (token)` des Upserts
# hängt am Primärschlüssel; bricht der weg, scheitert das Registrieren
# erst am Gerät.
check_get_protected "push_devices-Spalten (Push)" \
  "/rest/v1/push_devices?select=token,user_id,platform,created_at,last_seen_at&limit=1"

# app_config: die Zeile, aus der die App die Mindestversion liest. Anders
# als bei den anderen Tabellen darf anon hier tatsächlich lesen — ein
# leeres Ergebnis wäre also ein echter Befund: ohne Zeile erfährt die App
# nie, dass sie zu alt ist. Der HTTP-Status wird mitgelesen, damit
# „Dienst antwortet nicht" nicht als „Tabelle leer" erscheint — ein
# Wächter darf sich irren, er darf nicht die Ursache erfinden.
app_config_body=$(mktemp)
app_config_status=$(curl -s --max-time 20 -o "$app_config_body" \
  -w '%{http_code}' \
  "$URL/rest/v1/app_config?select=id,minimum_supported_version,updated_at&limit=1" \
  -H "apikey: $KEY" || echo "000")
app_config=$(cat "$app_config_body")
rm -f "$app_config_body"
min_version=$(app_config_version "$app_config_status" "$app_config")
case "$(app_config_diagnosis "$app_config_status" "$app_config")" in
dienst)
  echo "::error::Schema-Check fehlgeschlagen: app_config nicht abrufbar (HTTP $app_config_status). Das ist eine Aussage über den DIENST, nicht über die Tabelle — bei 000/5xx den Lauf wiederholen. Antwort: ${app_config:-<leer>}"
  fail=1
  ;;
leer)
  echo "::error::Schema-Check fehlgeschlagen: app_config ist LEER — ohne Zeile erfährt die App nie, dass sie zu alt ist."
  fail=1
  ;;
feld)
  echo "::error::Schema-Check fehlgeschlagen: app_config antwortet ohne minimum_supported_version. Antwort: $app_config"
  fail=1
  ;;
*)
  verdict "app_config-Spalten" "$app_config"
  # Aussperr-Schutz: Die Mindestversion darf nie über dem Stand liegen,
  # den die Nutzer bekommen können. Maßstab ist der STABILE Stand (das
  # jüngste nicht-Prerelease), nicht pubspec.yaml — Migrationen spielen
  # beim Merge ein, der Client kommt erst mit der Beförderung.
  app_version=$(sed -n 's/^version: \([0-9][0-9.]*\).*/\1/p' pubspec.yaml)
  stable_version=$(curl -s --max-time 20 \
    -H "Accept: application/vnd.github+json" \
    ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
    "https://api.github.com/repos/${GITHUB_REPOSITORY:-MacBuchi/TrailBuddy}/releases/latest" \
    | sed -n 's/.*"tag_name": *"v\{0,1\}\([0-9][0-9.]*\)".*/\1/p' | head -1)
  if [ -z "$stable_version" ]; then
    # Kein stabiles Release (frisches Repo) oder GitHub nicht erreichbar:
    # Dann gilt der alte Maßstab. Ein wackeliger API-Aufruf darf keinen
    # Merge blockieren.
    echo "::warning::Kein stabiles Release gefunden — prüfe gegen pubspec.yaml ($app_version)."
    stable_version="$app_version"
    scale="App-Version"
  else
    scale="stabile Version"
  fi
  if [ "$min_version" = "$stable_version" ] || \
     [ "$(printf '%s\n%s\n' "$min_version" "$stable_version" | sort -V | head -1)" = "$min_version" ]; then
    echo "✓ Mindestversion $min_version ≤ $scale $stable_version"
  else
    echo "::error::Schema-Check fehlgeschlagen: Mindestversion $min_version liegt ÜBER der $scale $stable_version — das würde alle aussperren, die auf stabil sind."
    fail=1
  fi
  ;;
esac

# Buddy-Suche: muss existieren, ist aber für anon gesperrt — sonst wäre
# der exakte E-Mail-Vergleich ein E-Mail-Orakel.
check_rpc_protected "search_profiles-RPC" "search_profiles" '{"query":"schema-check"}'

# Konto-Löschung: muss existieren und darf nur für Angemeldete aufrufbar
# sein.
check_rpc_protected "delete_own_account-RPC" "delete_own_account" '{}'

# Der Schreibweg für Aufzeichnungen (Konzept 4.1): Signatur
# (coords double precision[], source text, recorded_at timestamptz,
# client_id uuid, eles double precision[] — seit Patch 002, mit Vorgabe).
# Der Body trägt alle Namen, sonst hieße PGRST202 „Signatur passt nicht"
# statt „fehlt".
check_rpc_protected "contribute_recording-RPC" "contribute_recording" \
  '{"coords":[9.0,48.0,9.002,48.0],"source":"app","recorded_at":null,"client_id":null}'
# Seit Patch 002 mit Höhen. Beide Aufrufe müssen die Funktion treffen: der
# obere ist der Aufruf der Clients vor 0.3.0, dieser der heutige.
check_rpc_protected "contribute_recording-RPC mit Höhen" "contribute_recording" \
  '{"coords":[9.0,48.0,9.002,48.0],"source":"app","recorded_at":null,"client_id":null,"eles":[500,490]}'
# Höhen nachtragen (Patch 003): nur die eigene Aufzeichnung, nur für
# Angemeldete.
check_rpc_protected "attach_elevation-RPC" "attach_elevation" \
  '{"recording_id":"00000000-0000-4000-8000-000000000000","coords":[9.0,48.0,9.002,48.0],"eles":[500,490]}'
# Den eigenen Beitrag zurückziehen (Patch 010): nur für Angemeldete.
check_rpc_protected "withdraw_contribution-RPC" "withdraw_contribution" \
  '{"trail_id":"00000000-0000-4000-8000-000000000000"}'
# Melden (Patch 013): nur für Angemeldete, alle Namen im Body.
check_rpc_protected "report_trail-RPC" "report_trail" \
  '{"trail_id":"00000000-0000-4000-8000-000000000000","status":"closed","condition":null,"on_site":false,"reported_at":null,"client_id":null}'

if [ "$fail" -ne 0 ]; then
  echo "::error::Schema passt nicht zu den App-Queries. Fehlt ein supabase/patch_NNN_*.sql bzw. wurde er noch nicht eingespielt (tool/db_migrate.sh, Secret SUPABASE_DB_URL)?"
  exit 1
fi
if [ "$transport_fail" -ne 0 ]; then
  echo "::error::Schema-Check unentschieden: Mindestens eine Abfrage hat den Dienst nicht erreicht. Über das Schema sagt dieser Lauf NICHTS — Lauf wiederholen."
  exit 1
fi
echo "Schema passt zu allen App-Queries."
