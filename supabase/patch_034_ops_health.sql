-- Patch 034: ops_health() – Statusabfrage für den Betreiber.
--
-- Wozu: Ein Monitoring des Betreibers außerhalb dieses Repos fragt ab, ob
-- die App gesund ist. Dafür braucht es ein paar ZÄHLWERTE aus der
-- Datenbank – keine Zeile, keinen Text, keine ID.
--
-- Wie geschützt: Die Funktion ist für anon ausführbar (das Monitoring
-- hat nur den Publishable Key), verlangt aber einen Token. In der Datenbank
-- liegt nur dessen sha256 in app_internal.ops_config (Schema über die API
-- nicht erreichbar, RLS mit Sperr-Policy, keine Grants). Falscher oder
-- fehlender Token ⇒ 42501, ohne zu verraten, ob schon ein Hash gesetzt ist.
-- Den Hash setzt der Betreiber einmal im SQL-Editor (nicht über ein Repo):
--   insert into app_internal.ops_config (id, token_sha256)
--   values (true, encode(sha256(convert_to('<TOKEN>', 'UTF8')), 'hex'))
--   on conflict (id) do update set token_sha256 = excluded.token_sha256,
--                                  updated_at = now();
--
-- Security Advisor: „anon kann eine SECURITY-DEFINER-Funktion ausführen“
-- bleibt für ops_health bewusst stehen (Entscheidung Betreiber 2026-11-20);
-- der Token ist die Grenze, die Antwort enthält nur Zahlen.
-- Fester, leerer search_path: alles ist ausgeschrieben.
-- Kein neues Recht für die App, kein Bump von minimum_supported_version.

create table if not exists app_internal.ops_config (
  id boolean primary key default true check (id),
  token_sha256 text not null check (token_sha256 ~ '^[0-9a-f]{64}$'),
  updated_at timestamptz not null default now()
);
alter table app_internal.ops_config enable row level security;
create policy ops_config_no_client on app_internal.ops_config
  for all to anon, authenticated using (false) with check (false);
revoke all on table app_internal.ops_config from public, anon, authenticated;

create or replace function public.ops_health(p_token text)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_hash text;
begin
  select c.token_sha256 into v_hash from app_internal.ops_config c where c.id;
  if v_hash is null or p_token is null
     or encode(sha256(convert_to(p_token, 'UTF8')), 'hex') <> v_hash then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'db_size_mb', pg_database_size(current_database()) / 1048576,
    'errors_24h', (select count(*) from public.error_reports
                    where created_at > now() - interval '24 hours'),
    'errors_7d', (select count(*) from public.error_reports
                   where created_at > now() - interval '7 days'),
    'feedback_open', (select count(*) from public.feedback where processed_at is null),
    'feedback_7d', (select count(*) from public.feedback
                     where created_at > now() - interval '7 days'),
    'devices_active_7d', (select count(*) from public.push_devices
                           where last_seen_at > now() - interval '7 days'),
    'push_stuck', (select count(*) from app_internal.push_outbox
                    where due_at < now() - interval '1 hour'),
    'push_last_at', null,
    'min_version', (select minimum_supported_version from public.app_config where id),
    'extra', jsonb_build_array(
      jsonb_build_array('Nutzer', (select count(*) from public.profiles)),
      jsonb_build_array('Trails', (select count(*) from public.trails)),
      jsonb_build_array('Aufzeichnungen (7 Tage)', (select count(*) from public.trail_recordings
                                                     where created_at > now() - interval '7 days')),
      jsonb_build_array('Meldungen (7 Tage)', (select count(*) from public.trail_reports
                                                where created_at > now() - interval '7 days')))
  );
end;
$$;
revoke all on function public.ops_health(text) from public;
grant execute on function public.ops_health(text) to anon;
