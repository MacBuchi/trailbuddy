-- Patch 029: Airtime unter Buddys (#36 Schritt 6, docs/konzept-airtime.md
-- Abschnitt 4 und 5; Betreiber 2026-11-07: gebaut vor den Abnahmefahrten,
-- geteilt nur über einen eigenen Schalter, ab Werk aus).
--
-- Zwei Tabellen, mehr verlässt das Gerät nicht:
--
-- - `trail_airtime`: der eigene BESTWERT je Trail — die beste Airtime
--   einer Durchfahrt (Summe, Zehntelsekunden), der längste einzelne Sprung
--   und der Monat des Bestwerts. Kein Tag, keine Fahrt, kein Ort am
--   Sprung (A3). Sehen der Fahrer und seine direkten Buddys, die den Trail
--   selbst sehen, nicht bei „privat" — dieselbe Regel wie Hinweise und
--   Meldungen (notes_select, reports_select). Schreiben nur über
--   `set_trail_airtime`: ein Wert wird nur besser (Konzept 4), und die
--   Funktion prüft, dass der Aufrufer den Trail sieht.
-- - `airtime_counters`: je Nutzer EINE Zeile — Airtime und Sprünge der
--   letzten 30 Tage, auf dem Gerät gerechnet, mit dem Tag der Rechnung und
--   den Titeln, die das Gerät vergibt. Tagessummen auf dem Server würden
--   verraten, an welchen Tagen jemand gefahren ist; eine Zahl mit Stand
--   nur, dass er im Fenster gefahren ist. Sehen der Nutzer und seine
--   direkten Buddys.
--
-- Max G und Manual gehen nie hinaus (Konzept 4, Frage 2). Kein Push.
-- Ausschalten in der App löscht beides (`delete_my_airtime`), Rückzug vom
-- Trail den Bestwert dort (`withdraw_contribution`), Zusammenführen nimmt
-- ihn mit (Trigger an `app_internal.trail_aliases`), Kontolöschung per
-- Cascade.
set search_path = public, extensions;

create table public.trail_airtime (
  user_id uuid not null references public.profiles(id) on delete cascade,
  trail_id uuid not null references public.trails(id) on delete cascade,
  -- Zehntelsekunden: bis 10 min Airtime je Durchfahrt, 60 s je Sprung —
  -- weit über allem, was ein Rad fliegt; der Riegel fängt nur Unsinn.
  air_ds integer not null check (air_ds between 1 and 6000),
  longest_ds integer not null check (longest_ds between 1 and 600),
  month date not null check (extract(day from month) = 1),
  updated_at timestamptz not null default now(),
  primary key (user_id, trail_id),
  check (longest_ds <= air_ds)
);
create index trail_airtime_trail_idx on public.trail_airtime (trail_id);
alter table public.trail_airtime enable row level security;

create policy ta_select on public.trail_airtime for select
  using (user_id = auth.uid()
     or (app_internal.are_friends(user_id, auth.uid())
         and app_internal.contributor_shares(user_id, trail_id)
         and app_internal.can_see_trail(auth.uid(), trail_id)));
create policy ta_delete_own on public.trail_airtime for delete
  using (user_id = auth.uid());

create table public.airtime_counters (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  air_ds integer not null check (air_ds between 0 and 360000),
  jumps integer not null check (jumps between 0 and 100000),
  as_of date not null,
  -- Die Titel, die das Gerät aus den EIGENEN Werten vergibt (Konzept 5):
  -- Segelflieger und Bodenpersonal. Vielflieger und Trailkönig rechnet die
  -- App des Betrachters; Bruchpilot kommt erst mit gemessener Max-G-Probe.
  titles text[] not null default '{}'
    constraint airtime_counters_titles_check check (titles <@ array['glider', 'ground_crew']::text[]),
  updated_at timestamptz not null default now()
);
alter table public.airtime_counters enable row level security;

create policy ac_select on public.airtime_counters for select
  using (user_id = auth.uid() or app_internal.are_friends(user_id, auth.uid()));
-- Der Stand darf nicht in der Zukunft liegen (ein Tag Spielraum für
-- Zeitzonen) — sonst altert ein Zähler nie sichtbar.
create policy ac_insert_own on public.airtime_counters for insert
  with check (user_id = auth.uid() and as_of <= current_date + 1);
create policy ac_update_own on public.airtime_counters for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and as_of <= current_date + 1);
create policy ac_delete_own on public.airtime_counters for delete
  using (user_id = auth.uid());

revoke all on public.trail_airtime, public.airtime_counters from anon, authenticated;
grant select, delete on public.trail_airtime to authenticated;          -- schreiben nur per RPC
grant select, insert, update, delete on public.airtime_counters to authenticated;

-- Die Bestwerte des Geräts, alle auf einmal (der Abgleich schickt bei
-- jedem Lauf alles, was er aus den Fahrten kennt — idempotent, der Server
-- behält das Bessere). `items`: [{trail_id, air_ds, longest_ds, month}].
-- Ein Trail, den der Aufrufer in einen anderen geführt hat, schreibt auf
-- den behaltenen; einer, den er nicht (mehr) sieht, fällt still heraus —
-- ein gelöschter Trail ist kein Fehler des Abgleichs. Gibt die Zahl der
-- Zeilen zurück, die neu oder besser wurden.
create or replace function public.set_trail_airtime(items jsonb)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  it jsonb;
  t uuid;
  n integer := 0;
  k integer;
begin
  if uid is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  if jsonb_typeof(items) is distinct from 'array' or jsonb_array_length(items) > 1000 then
    raise exception 'Bis zu 1000 Werte als Liste erwartet' using errcode = '22023';
  end if;
  for it in select * from jsonb_array_elements(items) loop
    select a.same_as into t from app_internal.trail_aliases a
     where a.user_id = uid and a.trail_id = (it->>'trail_id')::uuid;
    t := coalesce(t, (it->>'trail_id')::uuid);
    continue when not exists (select 1 from trails where id = t)
               or not app_internal.can_see_trail(uid, t);
    insert into trail_airtime as cur (user_id, trail_id, air_ds, longest_ds, month)
    values (uid, t, (it->>'air_ds')::integer, (it->>'longest_ds')::integer,
            date_trunc('month', (it->>'month')::date)::date)
    on conflict (user_id, trail_id) do update
      set air_ds = greatest(cur.air_ds, excluded.air_ds),
          longest_ds = greatest(cur.longest_ds, excluded.longest_ds),
          month = case when excluded.air_ds > cur.air_ds then excluded.month else cur.month end,
          updated_at = now()
      where excluded.air_ds > cur.air_ds or excluded.longest_ds > cur.longest_ds;
    get diagnostics k = row_count;
    n := n + k;
  end loop;
  return n;
end $$;
revoke all on function public.set_trail_airtime(jsonb) from public, anon;
grant execute on function public.set_trail_airtime(jsonb) to authenticated;

-- Schalter aus: alles Geteilte weg, in EINER Transaktion. Security
-- INVOKER — die RLS erlaubt beide Löschungen ohnehin.
create or replace function public.delete_my_airtime()
returns void
language plpgsql security invoker set search_path = public as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  delete from trail_airtime where user_id = uid;
  delete from airtime_counters where user_id = uid;
end $$;
revoke all on function public.delete_my_airtime() from public, anon;
grant execute on function public.delete_my_airtime() to authenticated;

-- Zusammenführen (Patch 019) nimmt den Bestwert mit: Der behaltene Trail
-- bekommt den besseren je Nutzer. Ein Trigger statt einer neuen Fassung
-- von merge_own_into — die Zuordnung entsteht nur dort.
create or replace function app_internal.move_airtime_on_alias()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into trail_airtime as cur (user_id, trail_id, air_ds, longest_ds, month)
  select a.user_id, new.same_as, a.air_ds, a.longest_ds, a.month
    from trail_airtime a
   where a.user_id = new.user_id and a.trail_id = new.trail_id
  on conflict (user_id, trail_id) do update
    set air_ds = greatest(cur.air_ds, excluded.air_ds),
        longest_ds = greatest(cur.longest_ds, excluded.longest_ds),
        month = case when excluded.air_ds > cur.air_ds then excluded.month else cur.month end,
        updated_at = now();
  delete from trail_airtime where user_id = new.user_id and trail_id = new.trail_id;
  return new;
end $$;
revoke all on function app_internal.move_airtime_on_alias() from public, anon, authenticated;
create trigger trail_aliases_move_airtime
  after insert on app_internal.trail_aliases
  for each row execute function app_internal.move_airtime_on_alias();

-- Rückzug vom Trail nimmt den eigenen Bestwert dort mit.
create or replace function public.withdraw_contribution(trail_id uuid)
returns integer
language plpgsql security invoker set search_path = public as $$
declare
  uid uuid := auth.uid();
  n integer;
begin
  if uid is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  delete from trail_recordings r
   where r.trail_id = withdraw_contribution.trail_id and r.user_id = uid;
  get diagnostics n = row_count;
  delete from trail_notes t
   where t.trail_id = withdraw_contribution.trail_id and t.user_id = uid;
  delete from trail_reports m
   where m.trail_id = withdraw_contribution.trail_id and m.user_id = uid;
  delete from trail_airtime a
   where a.trail_id = withdraw_contribution.trail_id and a.user_id = uid;
  delete from trail_details d
   where d.trail_id = withdraw_contribution.trail_id and d.user_id = uid;
  return n;
end $$;
