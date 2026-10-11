-- Ersatz für das Supabase-Schema `auth` — NUR für lokale und CI-Läufe des
-- Matcher-Tests (tool/schema_local_test.sh) auf einem nackten Postgres.
-- NIE in ein Supabase-Projekt einspielen: Dort legt GoTrue das Schema an,
-- und dieses hier würde es überschreiben.
--
-- Was schema.sql von `auth` braucht, und nicht mehr:
--   - auth.users(id, email, raw_user_meta_data): Ziel des Fremdschlüssels
--     von profiles, Quelle des Benutzernamens im Trigger handle_new_user
--     (raw_user_meta_data->>'username', wie in PilzBuddy).
--   - auth.uid(): liest `sub` aus den JWT-Claims, die PostgREST als GUC
--     `request.jwt.claims` setzt. Der Test setzt sie mit set_config().
--   - die Rollen anon und authenticated (nologin), auf die Grants und
--     Policies zielen.
--   - storage.buckets, storage.objects und storage.foldername() (Patch 026,
--     Hinweis-Fotos): schema.sql legt einen Bucket und Policies auf
--     storage.objects an. Live und im Dry Run kommt das Schema vom
--     Storage-Dienst; hier nur die Spalten, die Policies und Prüfungen
--     nennen, und foldername() wortgleich zum Dienst.
--
-- Dazu die Vorgabe des Supabase-Stacks, ohne die der Test das Falsche
-- prüfte: `auto_expose_new_tables` gibt anon und authenticated auf JEDER
-- neuen Tabelle in public alle Rechte (Default Privileges). Der Test
-- „trails ist für authenticated nicht lesbar" beweist nur dann etwas,
-- wenn diese Vorgabe hier genauso gilt und schema.sql sie ausdrücklich
-- zurücknimmt.
create schema if not exists auth;

create table if not exists auth.users (
  id uuid primary key,
  email text,
  raw_user_meta_data jsonb not null default '{}'::jsonb
);

create or replace function auth.uid()
returns uuid
language sql stable set search_path = '' as $$
  select (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid;
$$;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  -- Der Feedback-Bot arbeitet als service_role (patch_001).
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin;
  end if;
end $$;

grant usage on schema public to anon, authenticated;
grant usage on schema auth to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
alter default privileges in schema public
  grant all on tables to anon, authenticated;
alter default privileges in schema public
  grant all on sequences to anon, authenticated;
alter default privileges in schema public
  grant execute on functions to anon, authenticated;

-- storage (Patch 026) — nur, was schema.sql und matcher_check.sql brauchen.
create schema if not exists storage;
create table if not exists storage.buckets (
  id text primary key,
  name text not null,
  public boolean default false,
  file_size_limit bigint,
  allowed_mime_types text[]
);
create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets(id),
  name text,
  owner uuid,
  created_at timestamptz default now(),
  unique (bucket_id, name)
);
alter table storage.objects enable row level security;
create or replace function storage.foldername(name text)
returns text[] language plpgsql as $$
declare
  _parts text[];
begin
  select string_to_array(name, '/') into _parts;
  return _parts[1:array_length(_parts, 1) - 1];
end $$;
grant usage on schema storage to anon, authenticated, service_role;
grant select, insert, delete on storage.objects to authenticated;
grant all on storage.objects, storage.buckets to service_role;
