-- Patch 033: Nutzer blockieren und Inhalte melden (#584, Google-Play-
-- Richtlinie „User Generated Content“; Betreiber 2026-11-19: schlank —
-- Person und Nachricht melden, Meldungen nur in einer privaten Tabelle,
-- gelesen im Dashboard).
--
-- 1. **Blockieren** (`user_blocks`, `block_user`). Alles, was man von
--    jemandem sieht, hängt an der direkten Buddy-Beziehung (A2): Trails,
--    Hinweise, Fotos, Airtime, Nachrichten, „Buddys unterwegs“,
--    Gruppenfahrt. Blockieren löscht deshalb die Beziehung (die Trigger
--    räumen Aliase, Nachrichten und Schalter ab) und verwirft danach jede
--    neue Anfrage zwischen den beiden STILL — in beide Richtungen. Der
--    Blockierte sieht dasselbe wie nach einem Ablehnen: Die Anfrage ist
--    weg. Dass er blockiert ist, erfährt er nicht. Lesen und wieder
--    freigeben kann nur, wer blockiert hat.
--
-- 2. **Melden** (`content_reports`, `report_content`). Eine Person oder
--    eine Nachricht, die sie mir geschickt hat. Die Tabelle hat KEINEN
--    Client-Grant: geschrieben wird nur über die RPC, gelesen nur mit dem
--    Service-Schlüssel (Dashboard). Den Text einer gemeldeten Nachricht
--    kopiert der Server selbst — eine Meldung kann keinen erfundenen Text
--    tragen, und sie bleibt prüfbar, wenn die Nachricht abläuft. Nach
--    180 Tagen weg (`sweep_content_reports`, Datenschutzerklärung).
set search_path = public, extensions;

create table public.user_blocks (
  blocker_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index user_blocks_blocked_idx on public.user_blocks (blocked_id);
alter table public.user_blocks enable row level security;

create policy ub_select_own on public.user_blocks for select
  using (blocker_id = auth.uid());
create policy ub_delete_own on public.user_blocks for delete
  using (blocker_id = auth.uid());

revoke all on public.user_blocks from anon, authenticated;
grant select, delete on public.user_blocks to authenticated;   -- anlegen nur per RPC

create or replace function app_internal.blocked_between(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from user_blocks
    where (blocker_id = a and blocked_id = b)
       or (blocker_id = b and blocked_id = a));
$$;
revoke all on function app_internal.blocked_between(uuid, uuid) from public, anon, authenticated;

-- Eine Anfrage zwischen zwei, von denen einer den anderen blockiert hat,
-- entsteht nicht — ohne Fehler, sonst wäre der Fehler das Orakel.
create or replace function app_internal.friendships_skip_blocked()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if app_internal.blocked_between(new.requester_id, new.addressee_id) then
    return null;
  end if;
  return new;
end;
$$;
revoke all on function app_internal.friendships_skip_blocked() from public, anon, authenticated;
create trigger friendships_skip_blocked
  before insert on public.friendships
  for each row execute function app_internal.friendships_skip_blocked();

-- Blockiert [other] und beendet, was zwischen uns besteht (auch eine
-- offene Anfrage). Nur jemanden, mit dem ich verbunden bin oder eine
-- Anfrage habe — sonst verriete `my_blocks` den Namen zu jeder Kennung.
create or replace function public.block_user(other uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
begin
  if me is null or other is null or other = me then
    raise exception 'block_user: ungültig' using errcode = '22023';
  end if;
  if not app_internal.involved_in_friendship(me, other)
     and not exists (select 1 from user_blocks where blocker_id = me and blocked_id = other) then
    raise exception 'block_user: keine Verbindung' using errcode = '42501';
  end if;
  insert into user_blocks (blocker_id, blocked_id) values (me, other)
    on conflict do nothing;
  delete from friendships
   where (requester_id = me and addressee_id = other)
      or (requester_id = other and addressee_id = me);
end;
$$;
revoke all on function public.block_user(uuid) from public, anon;
grant execute on function public.block_user(uuid) to authenticated;

-- Wen habe ICH blockiert, mit Namen — die Profile sind nach dem
-- Blockieren für mich nicht mehr lesbar (profiles_select).
create or replace function public.my_blocks()
returns table (blocked_id uuid, username text, avatar int, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select b.blocked_id, p.username, p.avatar, b.created_at
  from user_blocks b
  join profiles p on p.id = b.blocked_id
  where b.blocker_id = auth.uid()
  order by b.created_at desc;
$$;
revoke all on function public.my_blocks() from public, anon;
grant execute on function public.my_blocks() to authenticated;

create table public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reported_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('user', 'message')),
  -- Kein Fremdschlüssel: Die Nachricht läuft nach 30 Tagen ab, die
  -- Meldung soll bleiben.
  message_id uuid,
  reported_username text,
  excerpt text check (excerpt is null or char_length(excerpt) <= 500),
  reason text not null check (reason in ('spam', 'abuse', 'inappropriate', 'other')),
  note text check (note is null or char_length(note) <= 500),
  created_at timestamptz not null default now(),
  -- Setzt der Betreiber im Dashboard, wenn er die Meldung bearbeitet hat.
  handled_at timestamptz,
  check (reporter_id <> reported_id),
  check ((kind = 'message') = (message_id is not null))
);
create index content_reports_created_idx on public.content_reports (created_at desc);
create index content_reports_reporter_idx on public.content_reports (reporter_id, created_at);
alter table public.content_reports enable row level security;
-- Keine Policy für Clients: ohne Grant ohnehin zu. Der Service-Schlüssel
-- umgeht RLS, braucht aber die Grants.
revoke all on public.content_reports from anon, authenticated;
grant select, update, delete on public.content_reports to service_role;

-- Meldet [reported] (kind 'user') oder eine Nachricht, die [reported] MIR
-- geschickt hat (kind 'message', [message]). Melden darf ich, mit wem ich
-- verbunden bin, eine Anfrage habe oder wen ich blockiert habe. Höchstens
-- 20 Meldungen je Tag und Person.
create or replace function public.report_content(
  reported uuid, kind text, message uuid, reason text, note text)
returns void language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  body_copy text;
  name_copy text;
  clean_note text := nullif(btrim(coalesce(note, '')), '');
begin
  if me is null or reported is null or reported = me then
    raise exception 'report_content: ungültig' using errcode = '22023';
  end if;
  if not app_internal.involved_in_friendship(me, reported)
     and not exists (select 1 from user_blocks where blocker_id = me and blocked_id = reported) then
    raise exception 'report_content: keine Verbindung' using errcode = '42501';
  end if;
  if (select count(*) from content_reports r
       where r.reporter_id = me and r.created_at > now() - interval '1 day') >= 20 then
    raise exception 'report_content: zu viele Meldungen' using errcode = '42501';
  end if;
  if kind = 'message' then
    select m.body into body_copy from buddy_messages m
     where m.id = message and m.sender_id = reported and m.recipient_id = me;
    if body_copy is null then
      raise exception 'report_content: keine solche Nachricht' using errcode = '42501';
    end if;
  elsif kind <> 'user' or message is not null then
    raise exception 'report_content: ungültig' using errcode = '22023';
  end if;
  select p.username into name_copy from profiles p where p.id = reported;
  insert into content_reports
    (reporter_id, reported_id, kind, message_id, reported_username, excerpt, reason, note)
  values (me, reported, kind, message, name_copy, body_copy, reason, left(clean_note, 500));
end;
$$;
revoke all on function public.report_content(uuid, text, uuid, text, text) from public, anon;
grant execute on function public.report_content(uuid, text, uuid, text, text) to authenticated;

create or replace function app_internal.sweep_content_reports()
returns integer language plpgsql security definer set search_path = public as $$
declare
  n integer;
begin
  delete from content_reports where created_at < now() - interval '180 days';
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function app_internal.sweep_content_reports() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $cron$select cron.schedule('content-reports-sweep', '53 3 * * *',
              'select app_internal.sweep_content_reports()')$cron$;
  end if;
end $$;
