-- Was kostet ein Bestandsimport am Stück? Messung für das Tageslimit
-- (Issue #23, Konzept 4.6 „Rate"). Läuft NUR auf einer Wegwerf-Datenbank
-- mit supabase/schema.sql (lokal: `supabase db start`, dann dieses Skript
-- per psql) — es hebt dort das Limit auf und legt Testkonten an.
--
-- Die Last ist synthetisch, aber nach dem Bestand geformt, der gemessen
-- wurde (docs/trail-abgleich-messung.md): 150 verschiedene Trails von
-- 1 bis 6 km, dicht auf 8 × 8 km (ein Hausrevier, damit der Vorfilter
-- viele Nachbarn findet), Punkte alle 10 m — mehr, als die Vereinfachung
-- des Clients übrig lässt, also eher zu teuer als zu billig.
--   1. Ein Buddy hat die 150 Trails schon beigesteuert (Bestand).
--   2. Der Import: dieselben 150 dreimal verrauscht (σ 4 m, jede Kopie
--      gleich ⇒ der teure Weg mit Fréchet) — 450 Aufzeichnungen am Stück,
--      so viele Trails hat der gemessene Bestand (454).
-- Ausgabe: Summe, Median, p95 und Maximum je Aufzeichnung, getrennt nach
-- Bestand und Import. Keine Koordinaten, keine Ortsnamen.
\set ON_ERROR_STOP on
\set QUIET on
set search_path = public, extensions;

create or replace function app_internal.match_params()
returns app_internal.match_params
language sql immutable set search_path = '' as $$
  select row(15.0, 0.8, 2.0, 50.0, 5.0, 400, 0.3, 0.7, 0.3, 100000)::app_internal.match_params;
$$;

create schema lm;
create table lm.timing (phase text, n integer, ms double precision);

-- Kurvige Linie in Metern: Zufallsweg mit begrenzter Richtungsänderung.
create function lm.walk(seed double precision, x0 double precision, y0 double precision,
                        len double precision, step double precision default 10)
returns double precision[] language plpgsql volatile as $$
declare
  out double precision[] := '{}';
  x double precision := x0; y double precision := y0;
  h double precision;
  i integer;
begin
  perform setseed(seed);
  h := random() * 2 * pi();
  for i in 0..floor(len / step)::int loop
    out := out || array[x, y];
    h := h + (random() - 0.5) * 0.6;
    x := x + step * cos(h);
    y := y + step * sin(h);
  end loop;
  return out;
end $$;

create function lm.jitter(xy double precision[], sigma double precision, seed double precision)
returns double precision[] language plpgsql volatile as $$
declare
  out double precision[] := '{}';
  i integer;
begin
  perform setseed(seed);
  for i in 1..array_length(xy, 1) loop
    out := out || (xy[i] + sigma * sqrt(-2 * ln(greatest(random(), 1e-12))) * cos(2 * pi() * random()));
  end loop;
  return out;
end $$;

-- Meter um einen festen Ursprung ⇒ [lon, lat, …] wie aus der App.
create function lm.coords(xy double precision[])
returns double precision[] language sql immutable as $$
  select array_agg(v order by o) from (
    select 2 * i - 1 as o, 9.0 + degrees(xy[2 * i - 1] / (6371000.0 * cos(radians(48.0)))) as v
      from generate_series(1, array_length(xy, 1) / 2) i
    union all
    select 2 * i, 48.0 + degrees(xy[2 * i] / 6371000.0)
      from generate_series(1, array_length(xy, 1) / 2) i
  ) s;
$$;

create table lm.trail as
  select k,
         lm.walk(k::double precision / 1000, (k * 7919 % 8000)::double precision,
                 (k * 104729 % 8000)::double precision, 1000 + (k * 37 % 5000)) as xy
    from generate_series(1, 150) k;

insert into auth.users (id, email, raw_user_meta_data) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'buddy@example.org', '{"username":"lm_buddy"}'),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'import@example.org', '{"username":"lm_import"}');

create function lm.run(phase text, uid uuid, copies integer)
returns void language plpgsql as $$
declare
  t record; c integer; n integer := 0; t0 timestamptz;
  line double precision[];
begin
  for c in 1..copies loop
    for t in select * from lm.trail order by k loop
      n := n + 1;
      -- Linie vorher, als Eigentümer: gemessen wird nur die RPC.
      line := lm.coords(lm.jitter(t.xy, 4.0, (c * 1000 + t.k)::double precision / 100000));
      perform set_config('request.jwt.claims',
                         json_build_object('sub', uid, 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
      t0 := clock_timestamp();
      perform public.contribute_recording(line, 'import', null, null);
      execute 'reset role';
      insert into lm.timing values (phase, n,
        extract(epoch from clock_timestamp() - t0) * 1000);
    end loop;
  end loop;
end $$;

select lm.run('bestand', 'aaaaaaaa-0000-4000-8000-000000000001', 1);
select lm.run('import', 'aaaaaaaa-0000-4000-8000-000000000002', 3);

\set QUIET off
select phase,
       count(*) as aufzeichnungen,
       round(sum(ms)::numeric / 1000, 1) as summe_s,
       round(percentile_cont(0.5) within group (order by ms)::numeric) as median_ms,
       round(percentile_cont(0.95) within group (order by ms)::numeric) as p95_ms,
       round(max(ms)::numeric) as max_ms
  from lm.timing group by phase order by phase;
select count(*) as trails from public.trails;
select round(avg(array_length(xy, 1) / 2)) as punkte_je_linie from lm.trail;
