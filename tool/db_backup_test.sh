#!/usr/bin/env bash
# Round trip using the disposable Supabase stack from Schema Dry Run.
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."

export BACKUP_TEST_DB_CONTAINER="${BACKUP_TEST_DB_CONTAINER:-supabase_db_TrailBuddy}"
workdir=$(mktemp -d)
db="trailbuddy_backup_test_$$"

sql() {
  docker exec -i --user postgres "$BACKUP_TEST_DB_CONTAINER" \
    psql -X -w -U supabase_admin -v ON_ERROR_STOP=1 "$@"
}

cleanup() {
  sql -d postgres -q -c "drop database if exists $db" >/dev/null || true
  sql -d postgres -q -c "delete from auth.users where id = '00000000-0000-0000-0000-000000000603';
    delete from public.trails where id = '00000000-0000-0000-0000-000000000604';" >/dev/null || true
  rm -rf -- "$workdir"
}
trap cleanup EXIT

sql -d postgres -q <<'SQL'
insert into auth.users (id, email, raw_user_meta_data)
values ('00000000-0000-0000-0000-000000000603', 'backup@example.invalid',
        '{"username": "backup_probe"}');
insert into public.trails (id) values ('00000000-0000-0000-0000-000000000604');
insert into public.trail_details (trail_id, user_id, name)
values ('00000000-0000-0000-0000-000000000604',
        '00000000-0000-0000-0000-000000000603', 'Backup fixture');
SQL

cat > "$workdir/client" <<'CLIENT'
#!/usr/bin/env bash
exec docker exec -i "$BACKUP_TEST_DB_CONTAINER" "$(basename "$0")" "$@"
CLIENT
chmod +x "$workdir/client"
ln -s client "$workdir/pg_dump"
ln -s client "$workdir/psql"

age-keygen -o "$workdir/identity" 2>"$workdir/keygen.log"
export BACKUP_AGE_RECIPIENT
BACKUP_AGE_RECIPIENT=$(age-keygen -y "$workdir/identity")
export SUPABASE_DB_URL='postgresql://postgres:postgres@127.0.0.1:5432/postgres'
export PSQL="$workdir/psql" PG_DUMP="$workdir/pg_dump"
bash tool/db_backup.sh --no-upload "$workdir/backup.sql.age"
age --decrypt --identity "$workdir/identity" --output "$workdir/backup.sql" "$workdir/backup.sql.age"

sql -d postgres -q -c "create database $db template template0"
sql -d "$db" -q --single-transaction \
  -c 'drop schema public' \
  -c 'create schema extensions' \
  -c 'create extension postgis with schema extensions' \
  -c 'create extension pgcrypto with schema extensions' \
  -c 'create extension "uuid-ossp" with schema extensions' \
  -f - < "$workdir/backup.sql" > "$workdir/restore.log"
sql -d "$db" -q <<'SQL'
insert into auth.users (id, email, raw_user_meta_data)
values ('00000000-0000-0000-0000-000000000605', 'restored@example.invalid',
        '{"username": "restored_probe"}');
do $$
begin
  if not exists (
    select from auth.users u
    join public.profiles p on p.id = u.id
    join public.trail_details t on t.user_id = p.id
    where u.email = 'backup@example.invalid' and t.name = 'Backup fixture'
  ) then
    raise exception 'Backup fixture lost during restore';
  end if;
  if not exists (select from public.profiles where username = 'restored_probe') then
    raise exception 'Auth trigger did not create a profile after restore';
  end if;
  if not exists (select from public.applied_patches) then
    raise exception 'Patch history lost during restore';
  end if;
  if has_table_privilege('authenticated', 'public.trails', 'SELECT') then
    raise exception 'Authenticated users can read trails directly after restore';
  end if;
end
$$;
SQL

# A large, syntactically intact dump with the table but without its COPY
# section must fail before any encrypted file is produced.
export BACKUP_TEST_PG_DUMP="$PG_DUMP"
cat > "$workdir/reject" <<'CLIENT'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = --version ]; then
  exec "$BACKUP_TEST_PG_DUMP" "$@"
fi
"$BACKUP_TEST_PG_DUMP" --exclude-table-data=auth.identities "$@"
CLIENT
chmod +x "$workdir/reject"
if PG_DUMP="$workdir/reject" bash tool/db_backup.sh --no-upload "$workdir/rejected.age" \
    > "$workdir/reject.log" 2>&1; then
  echo "The backup accepted an incomplete dump" >&2
  exit 1
fi
grep -Fq 'Missing data section for auth.identities' "$workdir/reject.log"
test ! -e "$workdir/rejected.age"
echo "Encrypted database backup restored and incomplete dump rejected."
