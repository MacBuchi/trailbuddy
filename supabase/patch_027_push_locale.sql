-- Patch 027: Benachrichtigungen in der Sprache des Geräts (#209,
-- Betreiber 2026-10-13: „bin mit deinem Vorschlag einverstanden" — je
-- Gerät die Sprache, in der die App dort läuft).
--
-- `push_devices.locale` ('de' | 'en'): Die App schreibt sie mit dem
-- Token und noch einmal, wenn im Profil die Sprache wechselt. Vorgabe
-- 'de': Geräte, die vor diesem Patch eingetragen wurden, bekamen bisher
-- Deutsch und bekommen es weiter, bis ihre App die Zeile auffrischt.
-- Clients bis 0.118 schreiben die Spalte nicht — ihr Upsert lässt sie
-- stehen (on conflict update setzt nur, was mitkommt).
--
-- Die Texte setzt `push_trail_text` je Sprache; `push_flush` wird
-- ersetzt, Gruppierung und Ziele sind die aus Patch 022.
-- `push_join_names` bekommt die Sprache als zweites Argument, die alte
-- Fassung fällt weg; `trail_name_for` gibt ohne Namen NULL zurück, der
-- Rückfall kommt in der Sprache des Geräts. Beide nutzte nur push_flush.
set search_path = public, extensions;

alter table public.push_devices
  add column locale text not null default 'de' check (locale in ('de', 'en'));

drop function app_internal.push_join_names(text[]);

-- Der Name des Trails für [recipient]: Spiegel von `Trail.displayName`
-- — der eigene Name, sonst der des ältesten für ihn sichtbaren Beitrags
-- (eigene Zeile oder eine geteilte eines Buddys, td_friend_select), sonst
-- NULL. Den Rückfall („Trail ohne Namen" / „Unnamed trail") setzt seit
-- Patch 027 push_trail_text in der Sprache des Geräts.
create or replace function app_internal.trail_name_for(recipient uuid, trail uuid)
returns text
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select d.name from trail_details d
      where d.trail_id = trail and d.user_id = recipient
        and nullif(btrim(d.name), '') is not null),
    (select d.name from trail_details d
      where d.trail_id = trail and d.user_id <> recipient
        and d.visibility = 'buddies'
        and app_internal.are_friends(d.user_id, recipient)
        and nullif(btrim(d.name), '') is not null
      order by (select min(r.created_at) from trail_recordings r
                 where r.trail_id = trail and r.user_id = d.user_id) nulls last
      limit 1));
$$;
revoke all on function app_internal.trail_name_for(uuid, uuid) from public, anon, authenticated;

-- „Anna", „Anna und Ben", „Anna, Ben und Carl", „Anna, Ben und 2 weitere"
-- — auf Englisch „and" und „others" (Patch 027, Sprache des Geräts).
create or replace function app_internal.push_join_names(names text[], lang text)
returns text
language sql immutable set search_path = '' as $$
  select case
    when coalesce(array_length(names, 1), 0) = 0 then null
    when array_length(names, 1) = 1 then names[1]
    when array_length(names, 1) <= 3 then
      array_to_string(names[1:array_length(names, 1) - 1], ', ')
        || case when lang = 'en' then ' and ' else ' und ' end
        || names[array_length(names, 1)]
    else names[1] || ', ' || names[2]
      || case when lang = 'en' then ' and ' else ' und ' end
      || (array_length(names, 1) - 2)
      || case when lang = 'en' then ' others' else ' weitere' end
  end;
$$;
revoke all on function app_internal.push_join_names(text[], text) from public, anon, authenticated;

-- Titel und Text einer Trail-Meldung in der Sprache des Geräts (Patch
-- 027, #209). Eine Funktion statt zweier Fälle mitten im Versand: So
-- liest man beide Sprachen nebeneinander, und push_flush bleibt eine
-- Abfrage. [names] sind die Buddys in der Reihenfolge ihres Anlasses,
-- [trail_name] ist NULL, wenn niemand den Trail benannt hat.
create or replace function app_internal.push_trail_text(
  lang text, statuses integer, notes integer, trails integer, status text,
  trail_name text, names text[], note_body text,
  out title text, out body text)
language plpgsql immutable set search_path = '' as $$
declare
  en boolean := lang = 'en';
  single boolean := statuses + notes = 1;
  who text := app_internal.push_join_names(names, lang);
  trail text := '„' || coalesce(trail_name,
                  case when en then 'Unnamed trail' else 'Trail ohne Namen' end) || '“';
  counts text;
begin
  if en then
    trail := '“' || coalesce(trail_name, 'Unnamed trail') || '”';
    counts := concat_ws(' and ',
      case when statuses = 1 then '1 report'
           when statuses > 1 then statuses || ' reports' end,
      case when notes = 1 then '1 note'
           when notes > 1 then notes || ' notes' end);
    title := case
      when single and statuses = 1 and status = 'open'
        then coalesce(who, 'A buddy') || ': ' || trail || ' is open again'
      when single and statuses = 1
        then coalesce(who, 'A buddy') || ' reports ' || trail || ' as '
             || case status
                  when 'closed' then 'closed'
                  when 'destroyed' then 'destroyed'
                  else 'changed' end
      when single then coalesce(who, 'A buddy') || ' on ' || trail
      when trails = 1 then trail || ': ' || counts
      when statuses > 0 and notes > 0 then 'Your buddies reported something'
      when statuses > 1 then statuses || ' reports from your buddies'
      else notes || ' new notes from your buddies'
    end;
    body := case
      when single and notes = 1 and note_body is not null then null
      when single then 'Tap to see the trail'
      when trails = 1 then 'from ' || coalesce(who, 'your buddies')
      when statuses > 0 and notes > 0
        then counts || ' on ' || trails || ' trails · from ' || coalesce(who, 'your buddies')
      else 'On ' || trails || ' trails · from ' || coalesce(who, 'your buddies')
    end;
  else
    counts := concat_ws(' und ',
      case when statuses = 1 then '1 Meldung'
           when statuses > 1 then statuses || ' Meldungen' end,
      case when notes = 1 then '1 Hinweis'
           when notes > 1 then notes || ' Hinweise' end);
    title := case
      when single and statuses = 1 and status = 'open'
        then coalesce(who, 'Ein Buddy') || ': ' || trail || ' ist wieder frei'
      when single and statuses = 1
        then coalesce(who, 'Ein Buddy') || ' meldet ' || trail || ' als '
             || case status
                  when 'closed' then 'gesperrt'
                  when 'destroyed' then 'zerstört'
                  else 'verändert' end
      when single then coalesce(who, 'Ein Buddy') || ' zu ' || trail
      when trails = 1 then trail || ': ' || counts
      when statuses > 0 and notes > 0 then 'Deine Buddys haben etwas gemeldet'
      when statuses > 1 then statuses || ' Meldungen von deinen Buddys'
      else notes || ' neue Hinweise von deinen Buddys'
    end;
    body := case
      when single and notes = 1 and note_body is not null then null
      when single then 'Tippen zeigt den Trail'
      when trails = 1 then 'von ' || coalesce(who, 'deinen Buddys')
      when statuses > 0 and notes > 0
        then counts || ' an ' || trails || ' Trails · von ' || coalesce(who, 'deinen Buddys')
      else 'An ' || trails || ' Trails · von ' || coalesce(who, 'deinen Buddys')
    end;
  end if;
  -- Der Hinweistext ist, was der Buddy geschrieben hat — in keiner
  -- Sprache übersetzt, nur gekürzt.
  if body is null then
    body := case when char_length(note_body) > 140
                 then left(note_body, 139) || '…'
                 else note_body end;
  end if;
end $$;
revoke all on function app_internal.push_trail_text(text, integer, integer, integer, text, text, text[], text) from public, anon, authenticated;

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
           app_internal.trail_name_for(g.recipient_id, g.trail_id::uuid) as trail_name,
           -- Die Buddys dieses Empfängers, in der Reihenfolge ihres
           -- ersten Anlasses; ein gelöschtes Konto fällt heraus.
           array(
             select q.nm from (
               select app_internal.push_name_for(g.recipient_id, u.sender) as nm,
                      min(u.ord) as ord
                 from due x
                 cross join lateral unnest(x.sender_ids) with ordinality as u(sender, ord)
                where x.recipient_id = g.recipient_id
                group by u.sender) q
              where q.nm is not null
              order by q.ord, q.nm) as names,
           (select n.body from public.trail_notes n where n.id = g.note_id::uuid) as note_body
      from grouped g
  )
  -- Je GERÄT in seiner Sprache (Patch 027): Wer zwei Geräte hat, eins
  -- auf Englisch, bekommt dieselbe Meldung zweimal verschieden gesetzt.
  select jsonb_agg(jsonb_build_object(
           'token', d.token,
           'title', t.title,
           'body', t.body,
           'route', case
             when m.trails = 1 then '/trail/' || m.trail_id
             else '/trails'
           end))
    into payload
    from named m
    join public.push_devices d on d.user_id = m.recipient_id
    cross join lateral app_internal.push_trail_text(
      d.locale, m.statuses::integer, m.notes::integer, m.trails::integer,
      m.status, m.trail_name, m.names, m.note_body) t;

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
           'title', coalesce(app_internal.push_name_for(s.recipient_id, s.sender_id),
                             case when d.locale = 'en' then 'A buddy' else 'Ein Buddy' end)
                    || case when s.n <= 1 then ''
                            when d.locale = 'en' then ' · ' || s.n || ' messages'
                            else ' · ' || s.n || ' Nachrichten' end,
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
