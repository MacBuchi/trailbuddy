-- Patch 031: Buddy in der Nähe (#526, E8; docs/konzept-geraete.md 6.1,
-- Betreiber 2026-11-17/18).
--
-- Wer „Buddys unterwegs" eingeschaltet hat und unterwegs ist, legt seine
-- GROBE Zelle (rund 5 km, nie eine Position) als Presence in seinen
-- eigenen privaten Realtime-Kanal `nearby:<user_id>`. Seine direkten
-- Buddys hören dort zu und vergleichen auf IHREM Gerät mit der eigenen
-- Zelle — in der Nähe heißt: dieselbe oder eine Nachbarzelle.
--
-- Keine Tabelle für Orte, kein Verlauf (A3): Presence lebt nur im
-- Speicher des Realtime-Dienstes und verschwindet mit dem Kanal. Bewusst
-- in Kauf genommen (Betreiber 2026-11-18, „Realtime je Nutzer"): Ein
-- zuhörender Buddy sieht die Zelle, auch wenn er weit weg ist. Eine Zelle
-- je Kanal (statt je Nutzer) ginge nicht — Realtime prüft die Rechte beim
-- Beitritt, nicht je Nachricht, und jeder in der Zelle sähe jeden.
--
-- Rechte (Realtime Authorization, Policies auf realtime.messages):
--   - Presence SETZEN nur im eigenen Kanal.
--   - Presence LESEN im eigenen Kanal und in dem eines direkten Buddys,
--     der einen nicht über „sieht mich" ausgeschlossen hat.
--   Realtime prüft das beim Beitritt und bei jedem neuen JWT (≤ 1 h);
--   ein zurückgenommenes „sieht mich" wirkt also spätestens dann.
--
-- Je Buddy zwei Schalter (`buddy_nearby_prefs`, eine Zeile nur bei
-- Abweichung von der Vorgabe): `hidden` — er sieht mich nicht; `muted` —
-- keine Meldung von ihm. Lesen und schreiben nur der Besitzer; die
-- Policy auf realtime.messages liest `hidden` über eine Definer-Funktion.
-- Entfreunden löscht beide Richtungen (Trigger, wie die Aliase).
--
-- Lokal (tool/schema_local_test.sh) gibt es realtime.messages und
-- realtime.topic() aus tool/auth_shim.sql; im Dry Run und live vom
-- Realtime-Dienst.
set search_path = public, extensions;

create table public.buddy_nearby_prefs (
  user_id uuid not null references public.profiles(id) on delete cascade,
  buddy_id uuid not null references public.profiles(id) on delete cascade,
  hidden boolean not null default false,
  muted boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, buddy_id),
  check (user_id <> buddy_id)
);
alter table public.buddy_nearby_prefs enable row level security;

create policy bnp_select_own on public.buddy_nearby_prefs for select
  using (user_id = auth.uid());
create policy bnp_insert_own on public.buddy_nearby_prefs for insert
  with check (user_id = auth.uid() and app_internal.are_friends(user_id, buddy_id));
create policy bnp_update_own on public.buddy_nearby_prefs for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and app_internal.are_friends(user_id, buddy_id));
create policy bnp_delete_own on public.buddy_nearby_prefs for delete
  using (user_id = auth.uid());

revoke all on public.buddy_nearby_prefs from anon, authenticated;
grant select, insert, update, delete on public.buddy_nearby_prefs to authenticated;

create trigger buddy_nearby_prefs_touch
  before update on public.buddy_nearby_prefs
  for each row execute function app_internal.touch_updated_at();

create or replace function app_internal.nearby_prefs_on_unfriend()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from buddy_nearby_prefs p
  where (p.user_id = old.requester_id and p.buddy_id = old.addressee_id)
     or (p.user_id = old.addressee_id and p.buddy_id = old.requester_id);
  return old;
end;
$$;
revoke all on function app_internal.nearby_prefs_on_unfriend() from public, anon, authenticated;
create trigger friendships_delete_nearby_prefs
  after delete on public.friendships
  for each row execute function app_internal.nearby_prefs_on_unfriend();

-- Darf der Aufrufer die Presence im Kanal [topic] lesen? Der eigene
-- Kanal immer; der eines anderen nur als direkter Buddy, den der Besitzer
-- nicht ausgeschlossen hat. Alles, was nicht genau `nearby:<uuid>` ist,
-- ist nein — ohne Cast-Fehler.
create or replace function app_internal.may_read_nearby(topic text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  owner uuid;
  me uuid := auth.uid();
begin
  if me is null or topic is null
     or topic !~ '^nearby:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  owner := substr(topic, 8)::uuid;
  if owner = me then
    return true;
  end if;
  return app_internal.are_friends(owner, me)
    and not exists (select 1 from buddy_nearby_prefs p
                    where p.user_id = owner and p.buddy_id = me and p.hidden);
end;
$$;
revoke all on function app_internal.may_read_nearby(text) from public, anon;
grant execute on function app_internal.may_read_nearby(text) to authenticated;

create policy nearby_presence_read on realtime.messages for select
  to authenticated
  using (realtime.messages.extension = 'presence'
    and app_internal.may_read_nearby((select realtime.topic())));
create policy nearby_presence_track on realtime.messages for insert
  to authenticated
  with check (realtime.messages.extension = 'presence'
    and (select realtime.topic()) = 'nearby:' || (select auth.uid())::text);
