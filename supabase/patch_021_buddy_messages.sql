-- Patch 021: Nachrichten zwischen Buddys (#34, Stufe 1 — ohne Push).
-- Vorlage PilzBuddy Patch 030 (#564), Regeln unverändert übernommen
-- (Betreiber, 2026-10-11: „Ja, höchstens 3" bei offener Anfrage).
--
-- WER MIT WEM. Nur wer eine Zeile in `friendships` teilt: angenommen ⇒
-- unbegrenzt; offen (in welcher Richtung auch immer) ⇒ höchstens DREI
-- eigene Nachrichten an diese Person. Ohne Anfrage keine Nachricht —
-- sonst wäre die Namenssuche ein Weg, jedem zu schreiben. Das Limit steht
-- HIER und nicht in der App: Eine Grenze, die nur die Oberfläche zieht,
-- umgeht jeder mit einem eigenen Client.
--
-- ENDE DES KONTAKTS ENDET DEN VERLAUF. Wer ablehnt, zurückzieht oder
-- einen Buddy entfernt, löscht die Freundschaftszeile — und ein Trigger
-- nimmt die Nachrichten beider Seiten mit (Muster `aliases_on_unfriend`).
-- Er läuft als Definer: Die delete-Policy erlaubt jedem nur die EIGENEN.
--
-- 30 TAGE, UND ZWAR ERZWUNGEN. `expires_at` hat einen Default, einen
-- Check gegen `created_at` — und vor allem SPALTEN-Grants: Ein Client
-- darf beim Anlegen nur Empfänger und Text setzen, beim Ändern nur
-- `read_at`. Ohne die Spalten-Grants könnte er `created_at` in die
-- Zukunft legen und den Check damit aushebeln. Abgelaufenes sieht
-- niemand mehr (select-Policy), und ein Cron-Job räumt es täglich.
--
-- NICHT ENDE-ZU-ENDE-VERSCHLÜSSELT: geschützt durch RLS wie Hinweise
-- und Meldungen, für den Betreiber technisch lesbar. Die
-- Datenschutzerklärung sagt das ausdrücklich. Konzept 12 bleibt offen:
-- Eine Nachricht gehört zu genau einer Buddy-Beziehung, der Server
-- rechnet nichts über Nutzer hinweg.
--
-- Beide Personen-Spalten verweisen auf auth.users, nicht auf profiles —
-- dieselbe Vorsicht wie bei `friend_aliases`: sonst hielte PostgREST die
-- Tabelle für eine Verbindungstabelle, und Embeds auf profiles würden
-- mehrdeutig (PGRST201).
--
-- KEIN Bump von minimum_supported_version: rein additiv.
set search_path = public, extensions;

create table public.buddy_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 500),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '30 days',
  read_at timestamptz,
  check (sender_id <> recipient_id),
  check (expires_at <= created_at + interval '30 days')
);
-- Ein Verlauf ist ein Paar; gezählt wird je Absender und Empfänger.
create index buddy_messages_pair_idx
  on public.buddy_messages (sender_id, recipient_id, created_at);
create index buddy_messages_recipient_idx
  on public.buddy_messages (recipient_id);
create index buddy_messages_expires_idx
  on public.buddy_messages (expires_at);

-- Darf ich [other] schreiben? Angenommen ⇒ ja; offen ⇒ solange ich
-- weniger als drei Nachrichten an [other] geschickt habe; sonst nein.
-- Definer wie `are_friends`: Die Zählung soll nicht an einer
-- select-Policy hängen, die sich später ändert.
create or replace function app_internal.may_message(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when app_internal.are_friends(auth.uid(), other) then true
    when app_internal.involved_in_friendship(auth.uid(), other)
      then (select count(*) from buddy_messages m
             where m.sender_id = auth.uid() and m.recipient_id = other) < 3
    else false
  end;
$$;

alter table public.buddy_messages enable row level security;
-- ERST alles weg: `auto_expose_new_tables` (Legacy bis 2026-10-30) gibt
-- neuen Tabellen ALLE Rechte. Ein Tabellen-INSERT schlüge jeden
-- Spalten-Grant — die Zeitsperre oben wäre dann nur Deko.
revoke all on public.buddy_messages from anon, authenticated;
grant select, delete on public.buddy_messages to authenticated;
grant insert (recipient_id, body) on public.buddy_messages to authenticated;
grant update (read_at) on public.buddy_messages to authenticated;

create policy bm_select on public.buddy_messages for select
  using ((sender_id = auth.uid() or recipient_id = auth.uid())
     and expires_at > now());
create policy bm_insert on public.buddy_messages for insert
  with check (sender_id = auth.uid()
    and app_internal.may_message(recipient_id));
-- Gelesen markieren: nur, was an MICH ging.
create policy bm_read on public.buddy_messages for update
  using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());
-- Zurücknehmen: nur die eigenen.
create policy bm_delete on public.buddy_messages for delete
  using (sender_id = auth.uid());

create or replace function app_internal.messages_on_unfriend()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from buddy_messages m
  where (m.sender_id = old.requester_id and m.recipient_id = old.addressee_id)
     or (m.sender_id = old.addressee_id and m.recipient_id = old.requester_id);
  return old;
end;
$$;
revoke all on function app_internal.messages_on_unfriend() from public, anon, authenticated;
create trigger friendships_delete_messages
  after delete on public.friendships
  for each row execute function app_internal.messages_on_unfriend();

-- Abgelaufenes löschen. Die select-Policy blendet es schon vorher aus;
-- der Job hält nur die Tabelle klein.
create or replace function app_internal.sweep_expired_messages()
returns integer
language plpgsql security definer set search_path = public as $$
declare
  n integer;
begin
  delete from buddy_messages where expires_at < now();
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function app_internal.sweep_expired_messages() from public, anon, authenticated;

-- Täglich um 03:47 UTC, wo es pg_cron gibt (Muster Patch 013).
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $cron$select cron.schedule('messages-sweep', '47 3 * * *',
              'select app_internal.sweep_expired_messages()')$cron$;
  else
    raise notice 'pg_cron nicht verfügbar — sweep_expired_messages() ist nicht eingeplant (lokaler Testlauf).';
  end if;
end $$;
