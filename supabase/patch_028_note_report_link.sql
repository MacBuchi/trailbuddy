-- Patch 028: Hinweis und Meldung werden ein Eintrag (#433,
-- docs/konzept-melden.md; Betreiber 2026-10-31).
--
-- Beide Tabellen bleiben: Der Status braucht Sichtbarkeit und Dauer von
-- trail_reports (alle, die den Trail sehen; bleibt, bis jemand „wieder
-- offen" meldet), Text und Foto die von trail_notes (direkte Buddys,
-- 90 Tage). Neu ist nur die Verbindung:
--
-- - `trail_notes.report_id`: der Text gehört zu dieser Meldung. Fällt die
--   Meldung im Aufräumen weg, bleibt der Text ohne Status stehen (set
--   null); „erledigt" nimmt den Text, der Status bleibt. Die Kennung steht
--   in der Notiz, die ein Fremder nicht lesen darf — nicht in der Meldung.
-- - `trail_notes.client_id`: Ein ReportJob, der zweimal kommt, legt keine
--   zweite Notiz an (wie trail_reports seit Patch 013).
-- - `report_trail(…, note)` schreibt Meldung und Text in EINER
--   Transaktion und gibt die Kennung der Notiz zurück (das Foto hängt sich
--   daran). Text allein geht auch, ohne report_id. Die alte Signatur fällt
--   weg statt daneben zu stehen: Clients bis 0.146 rufen sie ohne `note`
--   auf, der Default nimmt das an, und der Rückgabewert war ihnen egal.
-- - Push: Ein Text zu einer BESTÄTIGTEN Meldung reitet auf deren Zeile im
--   Korb (`push_outbox.status_note_id`) statt eine zweite Push zu machen;
--   push_trail_text setzt ihn als zweite Zeile. „Hinweis" heißt in der
--   Push jetzt „Meldung", wie in der App.
set search_path = public, extensions;

alter table public.trail_notes
  add column report_id uuid references public.trail_reports(id) on delete set null,
  add column client_id uuid;
create index trail_notes_report_idx on public.trail_notes (report_id) where report_id is not null;
create unique index trail_notes_client_id_key
  on public.trail_notes (user_id, client_id)
  where client_id is not null;

-- Direkt einfügen dürfen Clients bis 0.146 weiter; eine report_id nur an
-- die EIGENE Meldung zu diesem Trail.
drop policy notes_insert on public.trail_notes;
create policy notes_insert on public.trail_notes for insert
  with check (user_id = auth.uid()
     and app_internal.can_see_trail(auth.uid(), trail_id)
     and (report_id is null
          or exists (select 1 from public.trail_reports m
                      where m.id = report_id and m.user_id = auth.uid()
                        and m.trail_id = trail_notes.trail_id)));

-- Der Text an der Statuszeile im Push-Korb. Eigene Spalte statt note_id:
-- note_id nimmt seine Zeile per Cascade mit (zurückgezogener Hinweis =
-- keine Push), die Statuszeile muss aber stehen bleiben, wenn jemand den
-- Text vor dem Versand „erledigt".
alter table app_internal.push_outbox
  add column status_note_id uuid references public.trail_notes(id) on delete set null;

drop function public.report_trail(uuid, text, integer, boolean, timestamptz, uuid);

create or replace function public.report_trail(
  trail_id uuid,
  status text default null,
  condition integer default null,
  on_site boolean default false,
  reported_at timestamptz default null,
  client_id uuid default null,
  note text default null)
returns uuid
language plpgsql security definer set search_path = public, app_internal as $$
#variable_conflict use_column
-- Die Parameter heißen wie Spalten (PostgREST ruft mit Namen); im
-- on conflict (…, client_id) gewinnt so die Spalte, die Parameter stehen
-- überall sonst mit report_trail. davor.
declare
  uid uuid := auth.uid();
  conf boolean;
  txt text := nullif(btrim(report_trail.note), '');
  rid uuid;
  nid uuid;
begin
  if uid is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  if report_trail.status is null and report_trail.condition is null and txt is null then
    raise exception 'Weder Meldung noch Zustand noch Text' using errcode = '22023';
  end if;
  if report_trail.trail_id is null
     or not app_internal.can_see_trail(uid, report_trail.trail_id) then
    raise exception 'Trail nicht sichtbar' using errcode = '42501';
  end if;
  -- Schutz gegen Fluten, kein gemessener Wert: 200 Zeilen in 24 h liegen
  -- weit über jedem echten Gebrauch (derselbe Code wie das Tageslimit der
  -- Aufzeichnungen, die App kennt ihn schon).
  if (select count(*) from trail_reports m
       where m.user_id = uid and m.created_at > now() - interval '1 day') >= 200 then
    raise exception 'Tageslimit von 200 Meldungen erreicht' using errcode = '54000';
  end if;
  conf := coalesce(report_trail.on_site, false)
          or app_internal.has_ridden(uid, report_trail.trail_id);
  if report_trail.status is not null then
    perform app_internal.put_report(uid, report_trail.trail_id, 'status', report_trail.status,
                                    null, conf, report_trail.reported_at, report_trail.client_id);
    -- Die eben geschriebene (oder beim zweiten Versuch die von damals).
    -- Ohne client_id die jüngste eigene: In dieser Transaktion ist sie
    -- die einzige mit diesem created_at.
    select m.id into rid from trail_reports m
     where m.user_id = uid and m.trail_id = report_trail.trail_id and m.kind = 'status'
       and (report_trail.client_id is null or m.client_id = report_trail.client_id)
     order by m.created_at desc, m.reported_at desc
     limit 1;
  end if;
  if report_trail.condition is not null then
    perform app_internal.put_report(uid, report_trail.trail_id, 'condition', null,
                                    report_trail.condition, conf, report_trail.reported_at,
                                    report_trail.client_id);
  end if;
  if txt is not null then
    insert into trail_notes (trail_id, user_id, body, report_id, client_id)
    values (report_trail.trail_id, uid, txt, rid, report_trail.client_id)
    on conflict (user_id, client_id) where client_id is not null do nothing
    returning id into nid;
    if nid is null then
      select n.id into nid from trail_notes n
       where n.user_id = uid and n.client_id = report_trail.client_id;
    end if;
  end if;
  return nid;
end $$;

revoke all on function public.report_trail(uuid, text, integer, boolean, timestamptz, uuid, text) from public, anon;
grant execute on function public.report_trail(uuid, text, integer, boolean, timestamptz, uuid, text) to authenticated;

-- Ein neuer Hinweis (#7). Der Korb merkt sich den jüngsten; sein Text
-- geht seit Patch 014 mit hinaus (push_flush liest ihn beim Versand).
-- Seit Patch 028: Gehört er zu einer BESTÄTIGTEN Meldung und wartet für
-- einen Empfänger schon eine Statuszeile desselben Absenders (die eben
-- von push_on_report angelegte), hängt er sich dort an — eine Push statt
-- zwei. Eine unbestätigte Meldung macht keine Statuszeile, ihr Text geht
-- also wie bisher als eigene Push.
create or replace function app_internal.push_on_note()
returns trigger
language plpgsql security definer set search_path = public, app_internal as $$
begin
  if new.report_id is not null
     and exists (select 1 from trail_reports m where m.id = new.report_id and m.confirmed) then
    update app_internal.push_outbox o set status_note_id = new.id
     where o.kind = 'trail_status' and o.trail_id = new.trail_id
       and new.user_id = any(o.sender_ids);
  end if;
  insert into app_internal.push_outbox (recipient_id, kind, trail_id, sender_ids, note_id, due_at)
    select r.recipient_id, 'trail_note', new.trail_id, array[new.user_id], new.id,
           app_internal.push_due_at(now())
      from app_internal.push_recipients(new.user_id, new.trail_id) r
     where not exists (select 1 from app_internal.push_outbox o
                        where o.recipient_id = r.recipient_id and o.kind = 'trail_status'
                          and o.trail_id = new.trail_id and o.status_note_id = new.id)
  on conflict (recipient_id, kind, trail_id) do update
    set note_id = excluded.note_id,
        sender_ids = case when new.user_id = any(push_outbox.sender_ids) then push_outbox.sender_ids
                          else push_outbox.sender_ids || new.user_id end,
        events = push_outbox.events + 1,
        due_at = app_internal.push_due_at(push_outbox.created_at);
  return new;
end $$;
revoke all on function app_internal.push_on_note() from public, anon, authenticated;

-- Titel und Text einer Trail-Meldung in der Sprache des Geräts (Patch
-- 027, #209). Eine Funktion statt zweier Fälle mitten im Versand: So
-- liest man beide Sprachen nebeneinander, und push_flush bleibt eine
-- Abfrage. [names] sind die Buddys in der Reihenfolge ihres Anlasses,
-- [trail_name] ist NULL, wenn niemand den Trail benannt hat. Seit Patch
-- 028 heißt alles „Meldung" (in der Zahl zählen Status und Text
-- zusammen), und [note_body] steht auch unter EINER Statusmeldung.
create or replace function app_internal.push_trail_text(
  lang text, statuses integer, notes integer, trails integer, status text,
  trail_name text, names text[], note_body text,
  out title text, out body text)
language plpgsql immutable set search_path = '' as $$
declare
  en boolean := lang = 'en';
  total integer := statuses + notes;
  single boolean := total = 1;
  who text := app_internal.push_join_names(names, lang);
  trail text := '„' || coalesce(trail_name,
                  case when en then 'Unnamed trail' else 'Trail ohne Namen' end) || '“';
  counts text;
begin
  if en then
    trail := '“' || coalesce(trail_name, 'Unnamed trail') || '”';
    counts := case when total = 1 then '1 report' else total || ' reports' end;
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
      else total || ' reports from your buddies'
    end;
    body := case
      when single and note_body is not null then null
      when single then 'Tap to see the trail'
      when trails = 1 then 'from ' || coalesce(who, 'your buddies')
      else 'On ' || trails || ' trails · from ' || coalesce(who, 'your buddies')
    end;
  else
    counts := case when total = 1 then '1 Meldung' else total || ' Meldungen' end;
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
      else total || ' Meldungen von deinen Buddys'
    end;
    body := case
      when single and note_body is not null then null
      when single then 'Tippen zeigt den Trail'
      when trails = 1 then 'von ' || coalesce(who, 'deinen Buddys')
      else 'An ' || trails || ' Trails · von ' || coalesce(who, 'deinen Buddys')
    end;
  end if;
  -- Der Text ist, was der Buddy geschrieben hat — in keiner Sprache
  -- übersetzt, nur gekürzt.
  if body is null then
    body := case when char_length(note_body) > 140
                 then left(note_body, 139) || '…'
                 else note_body end;
  end if;
end $$;
revoke all on function app_internal.push_trail_text(text, integer, integer, integer, text, text, text[], text) from public, anon, authenticated;

-- Der Versand (Patch 008/014/022/027), ersetzt nur für den Text an der
-- Statuszeile (Patch 028): note_body kommt aus note_id (eine
-- Hinweiszeile) oder status_note_id (der Text zur Meldung).
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
    returning recipient_id, kind, trail_id, status, sender_ids, events, note_id, status_note_id
  ),
  grouped as (
    select recipient_id,
           coalesce(sum(events) filter (where kind = 'trail_status'), 0) as statuses,
           coalesce(sum(events) filter (where kind = 'trail_note'), 0) as notes,
           count(distinct trail_id) as trails,
           min(trail_id::text) as trail_id,
           -- Das Statuswort, wenn es genau EINE Statusmeldung ist.
           max(status) filter (where kind = 'trail_status') as status,
           coalesce(max(note_id::text) filter (where kind = 'trail_note'),
                    max(status_note_id::text) filter (where kind = 'trail_status')) as note_id
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
