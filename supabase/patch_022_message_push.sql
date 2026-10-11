-- Patch 022: Benachrichtigung bei einer neuen Nachricht (#34, Stufe 2;
-- Vorlage PilzBuddy Patch 031 und 032). Betreiber, 2026-10-11: „Name +
-- Text" — Titel ist der Name, den der EMPFÄNGER dem Absender gegeben hat
-- (sonst dessen Benutzername), der Text die jüngste Nachricht, gekürzt
-- auf 180 Zeichen. Wie bei Hinweisen seit Patch 014 läuft das über
-- Google (FCM); die Datenschutzerklärung sagt es.
--
-- EIGENE WARTESCHLANGE statt `push_outbox`: Deren Schlüssel ist
-- (Empfänger, Art, Trail) mit `trail_id not null` — eine Nachricht hat
-- keinen Trail. `push_messages` hängt per Cascade an der Nachricht:
-- Zurückgenommen oder mit dem Ende der Freundschaft gelöscht, geht auch
-- keine Benachrichtigung mehr hinaus.
--
-- NICHT ENTPRELLT: Eine Nachricht ist kein Statuswechsel, auf den noch
-- drei weitere folgen — sie ist beim nächsten Cron-Lauf (jede Minute)
-- fällig. Mehrere vom selben Absender in diesem Fenster werden EINE
-- Meldung („Anni · 3 Nachrichten", Text die jüngste).
--
-- `push_flush` wird ersetzt; der Teil für Trails ist wörtlich der aus
-- Patch 014. Additiv: Clients bis 0.111 kennen das Ziel
-- `/friends/chat/<id>` nicht, ihre Erlaubnisliste (`pushRouteOf`) lässt
-- es fallen — die Benachrichtigung erscheint, der Tipp öffnet die App.
set search_path = public, extensions;

create table app_internal.push_messages (
  message_id uuid primary key
    references public.buddy_messages(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table app_internal.push_messages enable row level security;
revoke all on app_internal.push_messages from anon, authenticated;
-- Sperr-Policy wie bei push_outbox (PilzBuddy Patch 037): RLS ohne
-- Policy verweigert ohnehin, aber der Security Advisor meldet es sonst.
create policy push_messages_no_client on app_internal.push_messages
  for all to anon, authenticated using (false) with check (false);

create or replace function app_internal.push_on_message()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into app_internal.push_messages (message_id) values (new.id)
    on conflict do nothing;
  return new;
end;
$$;
revoke all on function app_internal.push_on_message() from public, anon, authenticated;
create trigger push_on_message_trg
  after insert on public.buddy_messages
  for each row execute function app_internal.push_on_message();

-- push_flush (Patch 014) mit dem Teil für Nachrichten. Nicht
-- eingerichtet ⇒ auch die Nachrichten-Schlange wird geleert.
create or replace function app_internal.push_flush()
returns integer
language plpgsql security definer
set search_path = public, app_internal, vault, net as $$
declare
  base_url text;
  job_secret text;
  service_key text;
  payload jsonb;
  sent integer;
begin
  select decrypted_secret into base_url
    from vault.decrypted_secrets where name = 'push_functions_url';
  select decrypted_secret into job_secret
    from vault.decrypted_secrets where name = 'push_job_secret';
  select decrypted_secret into service_key
    from vault.decrypted_secrets where name = 'push_service_key';

  -- Nicht eingerichtet: Fällige Zeilen trotzdem wegräumen und still
  -- zurück — sonst wüchse der Korb bis zur Einrichtung, und der erste
  -- Lauf feuerte einen Schwall über Meldungen von vorgestern ab.
  if base_url is null or job_secret is null or service_key is null then
    delete from app_internal.push_outbox where due_at <= now();
    delete from app_internal.push_messages;
    return 0;
  end if;

  with due as (
    delete from app_internal.push_outbox
     where due_at <= now()
    returning recipient_id, kind, trail_id, status, sender_ids, events, note_id
  ),
  grouped as (
    select recipient_id,
           coalesce(sum(events) filter (where kind = 'trail_status'), 0) as statuses,
           coalesce(sum(events) filter (where kind = 'trail_note'), 0) as notes,
           count(distinct trail_id) as trails,
           min(trail_id::text) as trail_id,
           -- Das Statuswort, wenn es genau EINE Statusmeldung ist.
           max(status) filter (where kind = 'trail_status') as status,
           max(note_id::text) filter (where kind = 'trail_note') as note_id
      from due group by recipient_id
  ),
  named as (
    select g.*,
           g.statuses + g.notes = 1 as single,
           app_internal.trail_name_for(g.recipient_id, g.trail_id::uuid) as trail_name,
           -- Die Buddys dieses Empfängers, in der Reihenfolge ihres
           -- ersten Anlasses; ein gelöschtes Konto fällt heraus.
           app_internal.push_join_names(array(
             select q.nm from (
               select app_internal.push_name_for(g.recipient_id, u.sender) as nm,
                      min(u.ord) as ord
                 from due x
                 cross join lateral unnest(x.sender_ids) with ordinality as u(sender, ord)
                where x.recipient_id = g.recipient_id
                group by u.sender) q
              where q.nm is not null
              order by q.ord, q.nm)) as names,
           (select n.body from public.trail_notes n where n.id = g.note_id::uuid) as note_body,
           concat_ws(' und ',
             case when g.statuses = 1 then '1 Meldung'
                  when g.statuses > 1 then g.statuses || ' Meldungen' end,
             case when g.notes = 1 then '1 Hinweis'
                  when g.notes > 1 then g.notes || ' Hinweise' end) as counts
      from grouped g
  )
  select jsonb_agg(jsonb_build_object(
           'token', d.token,
           'title', case
             when m.single and m.statuses = 1 and m.status = 'open'
               then coalesce(m.names, 'Ein Buddy') || ': „' || m.trail_name || '“ ist wieder frei'
             when m.single and m.statuses = 1
               then coalesce(m.names, 'Ein Buddy') || ' meldet „' || m.trail_name || '“ als '
                    || case m.status
                         when 'closed' then 'gesperrt'
                         when 'destroyed' then 'zerstört'
                         else 'verändert' end
             when m.single
               then coalesce(m.names, 'Ein Buddy') || ' zu „' || m.trail_name || '“'
             when m.trails = 1
               then '„' || m.trail_name || '“: ' || m.counts
             when m.statuses > 0 and m.notes > 0
               then 'Deine Buddys haben etwas gemeldet'
             when m.statuses > 1
               then m.statuses || ' Meldungen von deinen Buddys'
             else m.notes || ' neue Hinweise von deinen Buddys'
           end,
           'body', case
             when m.single and m.notes = 1 and m.note_body is not null
               then case when char_length(m.note_body) > 140
                         then left(m.note_body, 139) || '…'
                         else m.note_body end
             when m.single then 'Tippen zeigt den Trail'
             when m.trails = 1 then 'von ' || coalesce(m.names, 'deinen Buddys')
             when m.statuses > 0 and m.notes > 0
               then m.counts || ' an ' || m.trails || ' Trails · von '
                    || coalesce(m.names, 'deinen Buddys')
             else 'An ' || m.trails || ' Trails · von ' || coalesce(m.names, 'deinen Buddys')
           end,
           'route', case
             when m.trails = 1 then '/trail/' || m.trail_id
             else '/trails'
           end))
    into payload
    from named m
    join public.push_devices d on d.user_id = m.recipient_id;

  -- Nachrichten (Patch 022): je Empfänger und Absender EINE Meldung,
  -- ohne Frist. Titel der Name, den der Empfänger dem Absender gegeben
  -- hat (sonst dessen Benutzername), bei mehreren mit der Zahl; Text die
  -- jüngste Nachricht, gekürzt auf 180 Zeichen; Ziel der Verlauf.
  with due_msgs as (
    delete from app_internal.push_messages q
     using public.buddy_messages b
     where b.id = q.message_id
    returning b.sender_id, b.recipient_id, b.body, b.created_at
  ),
  per_sender as (
    select recipient_id, sender_id, count(*) as n,
           (array_agg(body order by created_at desc))[1] as newest
      from due_msgs group by recipient_id, sender_id
  )
  select coalesce(payload, '[]'::jsonb) || coalesce(jsonb_agg(jsonb_build_object(
           'token', d.token,
           'title', coalesce(app_internal.push_name_for(s.recipient_id, s.sender_id), 'Ein Buddy')
                    || case when s.n > 1 then ' · ' || s.n || ' Nachrichten' else '' end,
           'body', case when char_length(s.newest) > 180
                        then left(s.newest, 179) || '…'
                        else s.newest end,
           'route', '/friends/chat/' || s.sender_id)), '[]'::jsonb)
    into payload
    from per_sender s
    join public.push_devices d on d.user_id = s.recipient_id;

  sent := jsonb_array_length(payload);
  if sent = 0 then return 0; end if;

  -- Asynchron (pg_net): Die Antwort landet in net._http_response, der
  -- Cron-Lauf wartet nicht. Ein fehlgeschlagener Versand ist verloren —
  -- eine Wiedervorlage brächte im Zweifel dieselbe Meldung zweimal.
  perform net.http_post(
    url := base_url || '/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || service_key,
      'x-push-secret', job_secret),
    body := jsonb_build_object('messages', payload));
  return sent;
end $$;
revoke all on function app_internal.push_flush() from public, anon, authenticated;
