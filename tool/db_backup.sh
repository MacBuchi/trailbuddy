#!/usr/bin/env bash
set -euo pipefail
umask 077

fail() {
  echo "::error::$*" >&2
  exit 1
}

upload=true
output=
case ${1:-} in
  --no-upload)
    [ "$#" -le 2 ] || fail "Usage: $0 [--no-upload [encrypted-output]]"
    upload=false
    output=${2:-}
    ;;
  "") [ "$#" -eq 0 ] || fail "Unexpected empty argument" ;;
  *) fail "Usage: $0 [--no-upload [encrypted-output]]" ;;
esac

: "${SUPABASE_DB_URL:?Set SUPABASE_DB_URL to the session pooler URI}"
: "${BACKUP_AGE_RECIPIENT:?Set BACKUP_AGE_RECIPIENT to the public TrailBuddy age recipient}"
[[ $BACKUP_AGE_RECIPIENT =~ ^age1[0-9a-z]+$ ]] || fail "Expected a public age recipient"

repo=MacBuchi/trailbuddy-backups
marker="TrailBuddy automated database backup"
stamp=$(date -u +%F)
tag="backup-$stamp"
filename="trailbuddy-$stamp.sql.age"

managed_releases() {
  gh api --paginate "repos/$repo/releases?per_page=100" --jq '
    .[] | select(.draft == false and .body == "TrailBuddy automated database backup")
    | select(.tag_name | test("^backup-[0-9]{4}-[0-9]{2}-[0-9]{2}$"))
    | select(.assets | length == 1)
    | select(.assets[0].name == ("trailbuddy-" + .tag_name[7:] + ".sql.age"))
    | select(.assets[0].state == "uploaded" and .assets[0].size > 0)
    | .tag_name
  '
}

if $upload; then
  : "${GH_TOKEN:?Set GH_TOKEN to the token scoped to the private TrailBuddy backup repository}"
  visibility=$(gh api "repos/$repo" --jq '.visibility')
  [ "$visibility" = private ] || fail "Backup repository must be private"
  releases=$(managed_releases)
fi

# The workflow pins the client major. Query the server before writing any dump
# so an upgrade fails visibly, even on a client that supports older servers.
server_version=$("${PSQL:-psql}" --dbname="$SUPABASE_DB_URL" -XAtwqc 'show server_version_num')
[[ $server_version =~ ^[0-9]{6}$ ]] || fail "Cannot determine the PostgreSQL server version"
server_major=$((server_version / 10000))
client_version=$("${PG_DUMP:-pg_dump}" --version)
[[ $client_version =~ PostgreSQL\)\ ([0-9]+)\. ]] || fail "Cannot determine the pg_dump version"
[ "${BASH_REMATCH[1]}" = "$server_major" ] ||
  fail "Server is PostgreSQL $server_major. Install a matching pg_dump client."
echo "PostgreSQL $server_major"

workdir=$(mktemp -d)
trap 'rm -rf -- "$workdir"' EXIT
dump="$workdir/trailbuddy.sql"
encrypted="$workdir/$filename"

if ! $upload || ! grep -Fxq "$tag" <<< "$releases"; then
  "${PG_DUMP:-pg_dump}" --dbname="$SUPABASE_DB_URL" --no-password \
    --schema=public --schema=app_internal --schema=auth \
    --format=plain --quote-all-identifiers --no-comments > "$dump"

  dump_bytes=$(wc -c < "$dump")
  [ "$dump_bytes" -ge 10240 ] || fail "Dump is smaller than 10 KiB"

  # Match DDL and COPY statements, never data values. Empty tables still have
  # a COPY statement. Guard the account, trail and patch history boundaries.
  for table in auth.users auth.identities public.profiles public.trails \
      public.trail_details public.friendships public.applied_patches; do
    qualified="\"${table%%.*}\".\"${table#*.}\""
    grep -Fq "CREATE TABLE $qualified (" "$dump" ||
      fail "Missing table definition for $table"
    grep -Fq "COPY $qualified (" "$dump" ||
      fail "Missing data section for $table"
  done
  grep -Fq 'CREATE SCHEMA "app_internal";' "$dump" ||
    fail "Missing app_internal schema"
  grep -Fxq -- '-- PostgreSQL database dump complete' "$dump" ||
    fail "Missing pg_dump completion marker"

  age -r "$BACKUP_AGE_RECIPIENT" -o "$encrypted" "$dump"
  rm -- "$dump"
  IFS= read -r header < "$encrypted"
  [ "$header" = 'age-encryption.org/v1' ] || fail "Invalid age output"
  encrypted_bytes=$(wc -c < "$encrypted")
  echo "Archive checked and encrypted ($((encrypted_bytes)) bytes)"
fi

if ! $upload; then
  if [ -n "$output" ]; then
    (set -o noclobber; cat "$encrypted" > "$output")
  fi
  result="Dry run passed. No upload."
else
  if grep -Fxq "$tag" <<< "$releases"; then
    echo "Keeping the existing complete backup for $stamp"
  else
    gh release create "$tag" "$encrypted" --repo "$repo" \
      --title "Backup $stamp" --notes "$marker" --latest=false
  fi

  releases=$(managed_releases)
  grep -Fxq "$tag" <<< "$releases" || fail "Uploaded backup could not be verified"
  old_releases=$(printf '%s\n' "$releases" | LC_ALL=C sort -r | tail -n +13)
  while IFS= read -r old_tag; do
    [ -n "$old_tag" ] || continue
    gh release delete "$old_tag" --repo "$repo" --yes --cleanup-tag
  done <<< "$old_releases"
  result="Backup $tag verified in the private repository."
fi

echo "$result"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '### TrailBuddy database backup\n\n%s PostgreSQL %s.\n' "$result" "$server_major" >> "$GITHUB_STEP_SUMMARY"
fi
