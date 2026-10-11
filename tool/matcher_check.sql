-- Matcher- und RLS-Prüfung gegen eine Datenbank, auf der supabase/schema.sql
-- liegt — lokal mit tool/auth_shim.sql davor (tool/schema_local_test.sh),
-- oder auf dem lokalen Supabase-Stack, wo `auth` echt ist.
--
-- Jede Prüfung ist ein DO-Block, der bei Abweichung RAISE EXCEPTION wirft;
-- psql läuft mit ON_ERROR_STOP, der erste Fehler beendet den Lauf rot.
-- Die Linien entstehen synthetisch um 48° N / 9° O wie im Selbsttest von
-- tool/trail_match.py; die Fälle sind dieselben, dazu die Sichtbarkeit
-- (Abschnitt 3) und die Grant-Sperre auf `trails` (4.6).
--
-- Alles Test-Eigene liegt im Schema tb_test und wird am Ende NICHT
-- gelöscht — der Lauf ist auf einer Wegwerf-Datenbank gedacht.
\set ON_ERROR_STOP on
\set QUIET on
-- PostGIS liegt in `extensions` (schema.sql); die Test-Helfer nennen den
-- Typ geometry ohne Präfix, wie die Funktionsköpfe dort.
set search_path = public, extensions;

create schema tb_test;
-- Die Helfer laufen teils als authenticated (nach dem Rollenwechsel) —
-- ohne USAGE fände die Rolle weder coords() noch as_owner().
grant usage on schema tb_test to anon, authenticated;

-- xy in Metern um 48° N / 9° O ⇒ flache [lon, lat, …]-Liste, wie sie die
-- App an contribute_recording übergibt (Umkehrung von _synthetic()).
create or replace function tb_test.coords(xy double precision[])
returns double precision[] language sql immutable as $$
  select array_agg(v order by o) from (
    select 2 * i - 1 as o,
           9.0 + degrees(xy[2 * i - 1] / (6371000.0 * cos(radians(48.0)))) as v
      from generate_series(1, array_length(xy, 1) / 2) i
    union all
    select 2 * i,
           48.0 + degrees(xy[2 * i] / 6371000.0)
      from generate_series(1, array_length(xy, 1) / 2) i
  ) s;
$$;

-- Gerade: n = length/step Schritte ab (x0, y0) in Richtung (dx, dy).
create or replace function tb_test.line(length double precision, step double precision default 10.0,
                                        x0 double precision default 0, y0 double precision default 0,
                                        dx double precision default 1, dy double precision default 0)
returns double precision[] language sql immutable as $$
  select array_agg(v order by o) from (
    select 2 * i + 1 as o, x0 + i * step * dx as v from generate_series(0, floor(length / step)::int) i
    union all
    select 2 * i + 2, y0 + i * step * dy from generate_series(0, floor(length / step)::int) i
  ) s;
$$;

-- Erster Punkt weg (für Verkettungen wie in _line(...)[1:]).
create or replace function tb_test.tail(xy double precision[])
returns double precision[] language sql immutable as $$
  select xy[3:array_length(xy, 1)];
$$;

create or replace function tb_test.reverse_xy(xy double precision[])
returns double precision[] language sql immutable as $$
  select array_agg(v order by o) from (
    select 2 * (n - i) + 1 as o, xy[2 * i + 1] as v
      from (select array_length(xy, 1) / 2 - 1 as n) k, generate_series(0, array_length(xy, 1) / 2 - 1) i
    union all
    select 2 * (n - i) + 2, xy[2 * i + 2]
      from (select array_length(xy, 1) / 2 - 1 as n) k, generate_series(0, array_length(xy, 1) / 2 - 1) i
  ) s;
$$;

create or replace function tb_test.shift(xy double precision[], dx double precision, dy double precision)
returns double precision[] language sql immutable as $$
  select array_agg(case when i % 2 = 1 then xy[i] + dx else xy[i] + dy end order by i)
    from generate_series(1, array_length(xy, 1)) i;
$$;

-- Gauß-Rauschen (Box-Muller) je Koordinate, reproduzierbar über seed.
create or replace function tb_test.jitter(xy double precision[], sigma double precision, seed double precision)
returns double precision[] language plpgsql volatile as $$
declare
  out double precision[] := '{}';
  i integer;
  u1 double precision; u2 double precision;
begin
  perform setseed(seed);
  for i in 1..array_length(xy, 1) loop
    u1 := greatest(random(), 1e-12);
    u2 := random();
    out := out || (xy[i] + sigma * sqrt(-2 * ln(u1)) * cos(2 * pi() * u2));
  end loop;
  return out;
end $$;

-- Zickzack: `legs` Schenkel von `leg` Metern, abwechselnd hin und zurück,
-- `gap` Meter untereinander — wie _switchbacks() im Werkzeug.
create or replace function tb_test.switchbacks(legs integer default 6, leg double precision default 80,
                                               gap double precision default 15, step double precision default 5,
                                               x0 double precision default 0)
returns double precision[] language plpgsql immutable as $$
declare
  out double precision[] := '{}';
  k integer; x double precision; y double precision := 0;
begin
  for k in 0..legs - 1 loop
    x := 0;
    while x <= leg + 1e-9 loop
      out := out || array[x0 + case when k % 2 = 0 then x else leg - x end, y];
      x := x + step;
    end loop;
    y := y - gap;
  end loop;
  return out;
end $$;

-- Als Nutzer handeln: Claims setzen, Rolle wechseln, SQL ausführen,
-- Rolle zurück. Beides transaktionslokal — ein DO-Block ist eine
-- Transaktion, danach ist alles wieder wie vorher.
create or replace function tb_test.as_user(uid uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
                     json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

create or replace function tb_test.as_owner()
returns void language plpgsql as $$
begin
  execute 'reset role';
end $$;

create or replace function tb_test.contribute(uid uuid, xy double precision[],
                                              src text default 'app', cid uuid default null,
                                              at timestamptz default null)
returns uuid language plpgsql as $$
declare
  t uuid;
begin
  perform tb_test.as_user(uid);
  t := public.contribute_recording(tb_test.coords(xy), src, at, cid);
  perform tb_test.as_owner();
  return t;
end $$;

create or replace function tb_test.count_as(uid uuid, sql text)
returns bigint language plpgsql as $$
declare
  n bigint;
begin
  perform tb_test.as_user(uid);
  execute sql into n;
  perform tb_test.as_owner();
  return n;
end $$;

create or replace function tb_test.exec_as(uid uuid, sql text)
returns void language plpgsql as $$
begin
  perform tb_test.as_user(uid);
  execute sql;
  perform tb_test.as_owner();
end $$;

create or replace function tb_test.check(cond boolean, msg text)
returns void language plpgsql as $$
begin
  if cond is distinct from true then
    raise exception 'PRÜFUNG FEHLGESCHLAGEN: %', msg;
  end if;
  raise notice '  ✓ %', msg;
end $$;

-- Merkzettel für Trail-Kennungen zwischen den Blöcken.
create table tb_test.trail (key text primary key, id uuid not null);

create or replace function tb_test.t(key text) returns uuid language sql stable as $$
  select id from tb_test.trail where trail.key = t.key;
$$;

-- Drei Testkonten; der Trigger handle_new_user legt die Profile an.
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-4111-8111-111111111111', 'a@example.org', '{"username":"anna"}'),
  ('22222222-2222-4222-8222-222222222222', 'b@example.org', '{"username":"bernd"}'),
  ('33333333-3333-4333-8333-333333333333', 'c@example.org', '{"username":"carla"}');

\set QUIET off
\echo -- Vorbereitung
do $$
begin
  perform tb_test.check((select count(*) from public.profiles) = 3, 'drei Profile aus dem Signup-Trigger');
  perform tb_test.check((select username from public.profiles where id = '11111111-1111-4111-8111-111111111111') = 'anna',
                        'Benutzername kommt aus den Signup-Metadaten');
end $$;

\echo -- 1. Erste Aufzeichnung: neuer Trail, Beitrag mit Vorgaben
do $$
declare
  ua uuid := '11111111-1111-4111-8111-111111111111';
  t uuid;
begin
  t := tb_test.contribute(ua, tb_test.line(1000));
  insert into tb_test.trail values ('base', t);
  perform tb_test.check(t is not null, '1 km Gerade ergibt eine Trail-Kennung');
  perform tb_test.check((select count(*) from public.trail_recordings where trail_id = t) = 1, 'genau eine Aufzeichnung');
  perform tb_test.check((select quality from public.trail_recordings where trail_id = t) = 0.6::real, 'Qualität 0,6 für source=app');
  perform tb_test.check(exists (select 1 from public.trail_details where trail_id = t and user_id = ua
                                  and visibility = 'buddies' and status = 'open'),
                        'Beitrag angelegt: buddies, offen');
  -- Die Testpunkte entstehen auf der Kugel (wie im Werkzeug), die Sicht
  -- misst auf dem Sphäroid: bei 48° N rund 0,3 % Unterschied.
  perform tb_test.check((select abs(length_m - 1000) < 10 from public.recordings_visible where trail_id = t),
                        'Länge in der Sicht ≈ 1000 m (Sphäroid gegen Kugel < 1 %)');
end $$;

\echo -- 2. Verrauschte Kopie (σ = 5 m) hängt an
do $$
declare
  ua uuid := '11111111-1111-4111-8111-111111111111';
  t uuid;
begin
  t := tb_test.contribute(ua, tb_test.jitter(tb_test.line(1000), 5.0, 0.7));
  perform tb_test.check(t = tb_test.t('base'), 'verrauschte Kopie ⇒ derselbe Trail');
  perform tb_test.check((select count(*) from public.trail_recordings where trail_id = t) = 2, 'zwei Aufzeichnungen am Trail');
  perform tb_test.check(not exists (select 1 from public.trail_recordings where trail_id = t and reversed), 'beide in Trail-Richtung');
  perform tb_test.check((select count(*) from public.trail_details where trail_id = t) = 1, 'weiter genau ein Beitrag von A');
end $$;

\echo -- 3. Gegenrichtung (anderer Nutzer) hängt an, reversed = true
do $$
declare
  uc uuid := '33333333-3333-4333-8333-333333333333';
  t uuid;
begin
  t := tb_test.contribute(uc, tb_test.jitter(tb_test.reverse_xy(tb_test.line(1000)), 5.0, 0.3));
  perform tb_test.check(t = tb_test.t('base'), 'umgedrehte Kopie ⇒ derselbe Trail — auch über Nutzergrenzen');
  perform tb_test.check((select reversed from public.trail_recordings where trail_id = t and user_id = uc),
                        'Aufzeichnung von C trägt reversed = true');
  perform tb_test.check(exists (select 1 from public.trail_details where trail_id = t and user_id = uc),
                        'C bekommt beim Anhängen einen eigenen Beitrag');
end $$;

\echo -- 4. Parallele in 40 m: neuer Trail, keine Kante
do $$
declare
  uc uuid := '33333333-3333-4333-8333-333333333333';
  t uuid;
begin
  t := tb_test.contribute(uc, tb_test.line(1000, y0 => 40.0));
  insert into tb_test.trail values ('parallel', t);
  perform tb_test.check(t <> tb_test.t('base'), 'Parallele 40 m daneben ⇒ neuer Trail');
  perform tb_test.check(not exists (select 1 from app_internal.trail_overlaps
                                     where (a = t and b = tb_test.t('base')) or (a = tb_test.t('base') and b = t)),
                        'keine Overlap-Kante zur Parallele');
end $$;

\echo -- 5. Hälfte (500 m): neuer Trail + Kante (Teil)
do $$
declare
  ua uuid := '11111111-1111-4111-8111-111111111111';
  t uuid; ov app_internal.trail_overlaps;
begin
  t := tb_test.contribute(ua, tb_test.jitter(tb_test.line(500), 3.0, 0.5));
  insert into tb_test.trail values ('half', t);
  perform tb_test.check(t <> tb_test.t('base'), 'halber Trail ⇒ neuer Trail (v1: kein Teilbeleg)');
  select * into ov from app_internal.trail_overlaps where a = t and b = tb_test.t('base');
  perform tb_test.check(ov.a is not null, 'Overlap-Kante Hälfte → Basis vorhanden');
  perform tb_test.check(ov.coverage_ab >= 0.8, format('Hälfte liegt zu %s in der Basis (≥ 0,8)', ov.coverage_ab));
  perform tb_test.check(ov.coverage_ba between 0.4 and 0.6, format('Basis liegt zu %s in der Hälfte (≈ 0,5)', ov.coverage_ba));
end $$;

\echo -- 6. Fahrt (2,4 km), die den Trail enthält: neuer Trail + Kante
do $$
declare
  ua uuid := '11111111-1111-4111-8111-111111111111';
  t uuid; ov app_internal.trail_overlaps;
  ride double precision[];
begin
  ride := tb_test.line(600, x0 => -600) || tb_test.tail(tb_test.line(1000)) || tb_test.tail(tb_test.line(800, x0 => 1000));
  t := tb_test.contribute(ua, ride);
  insert into tb_test.trail values ('ride', t);
  perform tb_test.check(t <> tb_test.t('base') and t <> tb_test.t('half'), 'Fahrt mit Trail darin ⇒ neuer Trail');
  select * into ov from app_internal.trail_overlaps where a = t and b = tb_test.t('base');
  perform tb_test.check(ov.a is not null, 'Overlap-Kante Fahrt → Basis vorhanden');
  perform tb_test.check(ov.coverage_ba >= 0.8, format('Basis liegt zu %s in der Fahrt (≥ 0,8)', ov.coverage_ba));
  perform tb_test.check(ov.coverage_ab between 0.35 and 0.5, format('Fahrt liegt zu %s in der Basis (≈ 0,42)', ov.coverage_ab));
  perform tb_test.check(exists (select 1 from app_internal.trail_overlaps where a = t and b = tb_test.t('half')),
                        'auch Fahrt → Hälfte hat eine Kante');
end $$;

\echo -- 7. Gabel: neuer Trail + Kante
do $$
declare
  ua uuid := '11111111-1111-4111-8111-111111111111';
  t uuid; ov app_internal.trail_overlaps;
begin
  t := tb_test.contribute(ua, tb_test.line(500) || tb_test.tail(tb_test.line(500, x0 => 500, dx => 0.6, dy => 0.8)));
  insert into tb_test.trail values ('fork', t);
  perform tb_test.check(t <> tb_test.t('base'), 'Gabel ⇒ neuer Trail');
  select * into ov from app_internal.trail_overlaps where a = t and b = tb_test.t('base');
  perform tb_test.check(ov.a is not null, 'Overlap-Kante Gabel → Basis vorhanden');
  perform tb_test.check(ov.coverage_ab between 0.4 and 0.6 and ov.coverage_ba between 0.4 and 0.6,
                        format('Gabel deckt sich beidseitig ≈ 0,5 (%s / %s)', ov.coverage_ab, ov.coverage_ba));
end $$;

\echo -- 8. Idempotenz: dieselbe client_id zweimal
do $$
declare
  ub uuid := '22222222-2222-4222-8222-222222222222';
  cid uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
  t1 uuid; t2 uuid;
begin
  t1 := tb_test.contribute(ub, tb_test.line(700, y0 => 5000), 'import', cid);
  t2 := tb_test.contribute(ub, tb_test.line(700, y0 => 5000), 'import', cid);
  insert into tb_test.trail values ('far', t1);
  perform tb_test.check(t1 = t2, 'gleiche client_id ⇒ gleiche Trail-Kennung');
  perform tb_test.check((select count(*) from public.trail_recordings where user_id = ub and client_id = cid) = 1,
                        'genau eine Aufzeichnung für diese client_id');
  perform tb_test.check((select count(*) from public.trail_recordings where trail_id = t1) = 1, 'genau eine Aufzeichnung am Trail');
  perform tb_test.check((select quality from public.trail_recordings where trail_id = t1) = 0.4::real, 'Qualität 0,4 für source=import');
end $$;

\echo -- 9. Zu kurz und ungültig
do $$
declare
  ua uuid := '11111111-1111-4111-8111-111111111111';
  code text; msg text; ok boolean := false;
begin
  begin
    perform tb_test.contribute(ua, tb_test.line(40));
  exception when others then
    get stacked diagnostics code = returned_sqlstate, msg = message_text;
    ok := code = '22023' and msg like '%zu kurz%';
  end;
  perform tb_test.check(ok, format('40 m werden abgelehnt (SQLSTATE %s: %s)', code, msg));
  ok := false;
  begin
    perform tb_test.contribute(ua, tb_test.line(1000), 'gpx');
  exception when others then
    get stacked diagnostics code = returned_sqlstate;
    ok := code = '22023';
  end;
  perform tb_test.check(ok, 'unbekannte Quelle wird abgelehnt (22023)');
  ok := false;
  begin
    perform tb_test.contribute(ua, array[0.0, 0.0]);
  exception when others then
    get stacked diagnostics code = returned_sqlstate;
    ok := code = '22023';
  end;
  perform tb_test.check(ok, 'ein einzelner Punkt wird abgelehnt (22023)');
  ok := false;
  begin
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role authenticated';
    perform public.contribute_recording(tb_test.coords(tb_test.line(1000)), 'app', null, null);
  exception when others then
    get stacked diagnostics code = returned_sqlstate;
    ok := code = '28000';
  end;
  execute 'reset role';
  perform tb_test.check(ok, 'ohne Anmeldung: 28000');
end $$;

\echo -- 10. Sichtbarkeit (Abschnitt 3)
do $$
declare
  ua uuid := '11111111-1111-4111-8111-111111111111';
  ub uuid := '22222222-2222-4222-8222-222222222222';
  uc uuid := '33333333-3333-4333-8333-333333333333';
  base uuid := tb_test.t('base');
  n bigint;
begin
  perform tb_test.check(tb_test.count_as(ub, format('select count(*) from public.recordings_visible where user_id = %L', ua)) = 0,
                        'B (kein Buddy) sieht keine Aufzeichnung von A');
  perform tb_test.check(tb_test.count_as(ub, 'select count(*) from public.recordings_visible') = 1,
                        'B sieht nur seine eigene Aufzeichnung');
  perform tb_test.check(tb_test.count_as(ub, format('select count(*) from public.trail_details where user_id = %L', ua)) = 0,
                        'B sieht keinen Beitrag von A');

  -- Freundschaft A → B, von B angenommen — über die RLS-Policies, nicht als Eigentümer.
  perform tb_test.exec_as(ua, format('insert into public.friendships (requester_id, addressee_id) values (%L, %L)', ua, ub));
  perform tb_test.exec_as(ub, format('update public.friendships set status = %L where addressee_id = %L', 'accepted', ub));
  perform tb_test.check(app_internal.are_friends(ua, ub), 'Freundschaft A–B ist angenommen');

  n := tb_test.count_as(ub, format('select count(*) from public.recordings_visible where user_id = %L', ua));
  perform tb_test.check(n = 5, format('B sieht jetzt alle 5 Aufzeichnungen von A (%s)', n));
  perform tb_test.check(tb_test.count_as(ub, format('select count(*) from public.recordings_visible where trail_id = %L and user_id = %L', base, ua)) = 2,
                        'B sieht beide Aufzeichnungen von A am Basis-Trail');
  perform tb_test.check(tb_test.count_as(ub, format('select count(*) from public.recordings_visible where user_id = %L', uc)) = 0,
                        'B sieht weiterhin nichts von C (kein Buddy) — auch nicht am gemeinsamen Trail');
  perform tb_test.check(tb_test.count_as(ub, format('select count(*) from public.recordings_visible where trail_id = %L', base)) = 2,
                        'am Basis-Trail sieht B genau 2 von 3 Aufzeichnungen');
  perform tb_test.check(tb_test.count_as(ub, format('select count(*) from public.trail_details where user_id = %L', ua)) = 4,
                        'B sieht die 4 Beiträge von A (Basis, Hälfte, Fahrt, Gabel)');
  perform tb_test.check(tb_test.count_as(ub, format('select count(*) from public.recordings_visible where geojson like %L', '{"type":"LineString"%')) = 6,
                        'GeoJSON in der Sicht ist eine LineString je Zeile');

  -- A stellt den Basis-Trail auf privat.
  perform tb_test.exec_as(ua, format('update public.trail_details set visibility = %L where trail_id = %L and user_id = %L', 'private', base, ua));
  perform tb_test.check(tb_test.count_as(ub, format('select count(*) from public.recordings_visible where trail_id = %L', base)) = 0,
                        'privat: B sieht am Basis-Trail nichts mehr');
  perform tb_test.check(tb_test.count_as(ub, format('select count(*) from public.recordings_visible where user_id = %L', ua)) = 3,
                        'privat: die anderen 3 Aufzeichnungen von A bleiben sichtbar');
  perform tb_test.check(tb_test.count_as(ub, format('select count(*) from public.trail_details where trail_id = %L', base)) = 0,
                        'privat: auch der Beitrag ist für B weg');
  perform tb_test.check((select updated_at > created_at from public.trail_details where trail_id = base and user_id = ua),
                        'updated_at wird vom Trigger gesetzt');
  -- A darf fremde Aufzeichnungen nicht löschen, eigene schon.
  perform tb_test.exec_as(ua, format('delete from public.trail_recordings where trail_id = %L and user_id = %L', base, uc));
  perform tb_test.check((select count(*) from public.trail_recordings where trail_id = base) = 3,
                        'A kann die Aufzeichnung von C nicht löschen (RLS filtert still)');
end $$;

\echo -- 11. Keine Grants auf trails und trail_overlaps
do $$
declare
  ua uuid := '11111111-1111-4111-8111-111111111111';
  code text; ok boolean := false;
begin
  begin
    perform tb_test.count_as(ua, 'select count(*) from public.trails');
  exception when others then
    get stacked diagnostics code = returned_sqlstate;
    ok := code = '42501';
  end;
  perform tb_test.check(ok, format('trails ist für authenticated nicht lesbar (%s)', code));
  ok := false;
  begin
    perform tb_test.count_as(ua, 'select count(*) from app_internal.trail_overlaps');
  exception when others then
    get stacked diagnostics code = returned_sqlstate;
    ok := code = '42501';
  end;
  perform tb_test.check(ok, format('trail_overlaps ist für authenticated nicht lesbar (%s)', code));
  ok := false;
  begin
    perform tb_test.exec_as(ua, format('insert into public.trail_recordings (trail_id, user_id, geom, source, quality) values (%L, %L, %L, %L, 0.5)',
                                       tb_test.t('base'), ua, 'SRID=4326;LINESTRING(9 48, 9.01 48)', 'app'));
  exception when others then
    get stacked diagnostics code = returned_sqlstate;
    ok := code = '42501';
  end;
  perform tb_test.check(ok, format('direktes Insert in trail_recordings ist gesperrt (%s)', code));
  ok := false;
  begin
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    perform count(*) from public.profiles;
  exception when others then
    get stacked diagnostics code = returned_sqlstate;
    ok := code = '42501';
  end;
  execute 'reset role';
  perform tb_test.check(ok, format('anon hat keinen Grant auf profiles (%s)', code));
  perform tb_test.check(tb_test.count_as(ua, 'select count(*) from public.app_config') = 1, 'app_config ist lesbar');
end $$;

\echo -- 12. Serpentinen: Kopie hängt an, um eine Kehre versetzt nicht (Fréchet)
do $$
declare
  ua uuid := '11111111-1111-4111-8111-111111111111';
  uc uuid := '33333333-3333-4333-8333-333333333333';
  zz uuid; zz2 uuid; shifted uuid;
  zz_xy double precision[] := tb_test.switchbacks(x0 => 3000);
  r app_internal.match_result;
  srid integer; ga geometry; gb geometry;
begin
  zz := tb_test.contribute(uc, zz_xy);
  zz2 := tb_test.contribute(ua, tb_test.jitter(zz_xy, 3.0, 0.11));
  perform tb_test.check(zz2 = zz, 'neu aufgezeichnete Serpentinen ⇒ derselbe Trail');
  shifted := tb_test.contribute(ua, tb_test.shift(zz_xy, 0, -15.0));
  perform tb_test.check(shifted <> zz, 'um eine Kehre versetzte Serpentinen ⇒ NICHT derselbe Trail');
  perform tb_test.check(exists (select 1 from app_internal.trail_overlaps where a = shifted and b = zz),
                        'aber eine Overlap-Kante (Nachbar)');
  -- Direkt am Matcher: Der Korridor allein hätte sie für gleich gehalten.
  ga := st_setsrid(st_makeline(array(select st_makepoint(c[2*i-1], c[2*i]) from tb_test.coords(zz_xy) c, generate_series(1, array_length(c,1)/2) i)), 4326);
  gb := st_setsrid(st_makeline(array(select st_makepoint(c[2*i-1], c[2*i]) from tb_test.coords(tb_test.shift(zz_xy, 0, -15.0)) c, generate_series(1, array_length(c,1)/2) i)), 4326);
  srid := app_internal.utm_srid(ga);
  r := app_internal.match_lines(st_transform(ga, srid), st_transform(gb, srid));
  perform tb_test.check(least(r.cov_ab, r.cov_ba) >= 0.7,
                        format('Korridor allein deckt sich (%s / %s)', r.cov_ab, r.cov_ba));
  perform tb_test.check(r.class = 'neighbour' and r.frechet_m > 30,
                        format('Fréchet erkennt den Nachbarn: %s, %s m', r.class, r.frechet_m));
end $$;

\echo -- 13. Fréchet-DP gegen PostGIS, Vorzeichen der Richtung
do $$
declare
  a geometry[] := array[st_makepoint(0, 0), st_makepoint(1, 0)];
  b geometry[] := array[st_makepoint(0, 1), st_makepoint(1, 1)];
  la geometry; lb geometry; srid integer;
  sa geometry[]; sb geometry[];
  dp double precision; gis double precision;
begin
  perform tb_test.check(abs(app_internal.frechet(a, b) - 1.0) < 1e-9, 'Fréchet paralleler Einheitslinien ist 1');
  perform tb_test.check(app_internal.frechet(a, array[st_makepoint(0, 0)]) = 'infinity', 'unter zwei Punkten: unendlich');
  la := st_setsrid(st_makeline(array(select st_makepoint(c[2*i-1], c[2*i]) from tb_test.coords(tb_test.line(1000)) c, generate_series(1, array_length(c,1)/2) i)), 4326);
  lb := st_setsrid(st_makeline(array(select st_makepoint(c[2*i-1], c[2*i]) from tb_test.coords(tb_test.jitter(tb_test.line(1000), 5.0, 0.7)) c, generate_series(1, array_length(c,1)/2) i)), 4326);
  -- Abtastung auf einer planaren Linie (die projizierte Testlinie ist
  -- ~1003 m lang, siehe Block 1, und gäbe 202 Punkte).
  sa := app_internal.resample(st_makeline(st_makepoint(0, 0), st_makepoint(1000, 0)), 5.0);
  perform tb_test.check(array_length(sa, 1) = 201 and st_length(st_makeline(sa)) = 1000,
                        format('Abtastung 1000 m / 5 m ⇒ 201 Punkte, Länge erhalten (%s)', array_length(sa, 1)));
  perform tb_test.check(array_length(app_internal.resample(st_makeline(st_makepoint(0, 0), st_makepoint(3, 0)), 5.0), 1) = 2,
                        'kürzer als ein Schritt ⇒ Anfang und Ende');
  srid := app_internal.utm_srid(la);
  sa := app_internal.resample(st_transform(la, srid), 5.0);
  sb := app_internal.resample(st_transform(lb, srid), 5.0);
  dp := app_internal.frechet(sa, sb);
  gis := st_frechetdistance(st_makeline(sa), st_makeline(sb));
  perform tb_test.check(abs(dp - gis) < 1e-6, format('eigene DP = ST_FrechetDistance (%s m)', round(dp::numeric, 2)));
  perform tb_test.check(dp < 30, 'Fréchet der verrauschten Kopie < 30 m');
end $$;

\echo -- 14. reversed ist relativ zur Trail-Richtung, nicht zur Vertreterin
do $$
declare
  ua uuid := '11111111-1111-4111-8111-111111111111';
  ub uuid := '22222222-2222-4222-8222-222222222222';
  uc uuid := '33333333-3333-4333-8333-333333333333';
  xy double precision[] := tb_test.line(800, y0 => 8000);
  t1 uuid; t2 uuid; t3 uuid;
begin
  -- C legt den Trail mit einer GEPLANTEN Route an (Qualität 0,1) …
  t1 := tb_test.contribute(uc, xy, 'planned');
  -- … A fährt ihn rückwärts mit der App (0,6) — ab jetzt ist A's
  -- Aufzeichnung die Vertreterin, und die ist selbst reversed …
  t2 := tb_test.contribute(ua, tb_test.jitter(tb_test.reverse_xy(xy), 4.0, 0.2));
  perform tb_test.check(t2 = t1 and (select reversed from public.trail_recordings where trail_id = t1 and user_id = ua),
                        'A gegen die geplante Richtung ⇒ reversed = true');
  -- … B fährt ihn vorwärts: relativ zur Vertreterin „gegen", relativ zum
  -- Trail „mit". Ohne das XOR stünde hier reversed = true.
  t3 := tb_test.contribute(ub, tb_test.jitter(xy, 4.0, 0.9));
  perform tb_test.check(t3 = t1 and not (select reversed from public.trail_recordings where trail_id = t1 and user_id = ub),
                        'B in Trail-Richtung ⇒ reversed = false, obwohl die Vertreterin umgedreht war');
  perform tb_test.check((select count(*) from public.trail_recordings where trail_id = t1) = 3, 'drei Aufzeichnungen, ein Trail');
end $$;

\echo -- 15. Status: neue Aufzeichnung setzt den eigenen Beitrag auf offen, eine geplante nicht (Patch 011)
do $$
declare
  ua uuid := '11111111-1111-4111-8111-111111111111';
  t uuid := tb_test.t('half');
begin
  -- Seit Patch 013 zählt eine Fahrt zu IHREM Datum und nur, wenn sie
  -- jünger ist als die Meldung. In einem DO-Block ist now() überall
  -- gleich, deshalb stehen die Zeiten hier ausdrücklich da.
  perform tb_test.exec_as(ua, format('update public.trail_details set status = %L, status_at = now() - interval ''3 minutes'' where trail_id = %L and user_id = %L', 'closed', t, ua));
  perform tb_test.check((select status from public.trail_details where trail_id = t and user_id = ua) = 'closed', 'Beitrag auf gesperrt gesetzt');
  perform tb_test.check(tb_test.contribute(ua, tb_test.jitter(tb_test.line(500), 3.0, 0.42), at => now() - interval '2 minutes') = t,
                        'Hälfte erneut gefahren ⇒ derselbe Trail');
  perform tb_test.check((select status from public.trail_details where trail_id = t and user_id = ua) = 'open',
                        'wer fährt, hat offen vorgefunden: Status wieder offen (Entscheidung 6)');

  -- Patch 011 (#100): Eine Datei ohne Fahrzeiten belegt keine Fahrt.
  perform tb_test.exec_as(ua, format('update public.trail_details set status = %L, status_at = now() - interval ''1 minute'' where trail_id = %L and user_id = %L', 'closed', t, ua));
  perform tb_test.check(tb_test.contribute(ua, tb_test.jitter(tb_test.line(500), 3.0, 0.43), 'planned') = t,
                        'geplanter Import derselben Hälfte ⇒ derselbe Trail');
  perform tb_test.check((select status from public.trail_details where trail_id = t and user_id = ua) = 'closed',
                        'geplant ist nicht gefahren: Status bleibt gesperrt (Patch 011)');
  perform tb_test.check(tb_test.contribute(ua, tb_test.jitter(tb_test.line(500), 3.0, 0.44), 'import', at => now()) = t,
                        'Import mit Fahrzeiten ⇒ derselbe Trail');
  perform tb_test.check((select status from public.trail_details where trail_id = t and user_id = ua) = 'open',
                        'Import mit Fahrzeiten ist eine Fahrt: Status wieder offen');
end $$;

\echo -- 16. Höhen je Punkt (Patch 002, Issue #14)
do $$
declare
  ua uuid := '11111111-1111-4111-8111-111111111111';
  xy double precision[] := tb_test.line(300, y0 => 12000);
  c double precision[];
  n integer; t uuid; e real[]; code text; ok boolean;
begin
  c := tb_test.coords(xy);
  n := array_length(c, 1) / 2;
  -- Punkt 3 doppelt, mit eigener (falscher) Höhe: Er fällt weg, und die
  -- Höhen danach dürfen NICHT um einen Punkt verrutschen.
  c := c[1:6] || c[5:6] || c[7:array_length(c, 1)];
  perform tb_test.as_user(ua);
  t := public.contribute_recording(c, 'import', null, null,
         array(select 1000.0 - i from generate_series(1, 3) i)
         || array[555.0]
         || array(select 1000.0 - i from generate_series(4, n) i));
  perform tb_test.as_owner();
  select r.ele into e from public.trail_recordings r where r.trail_id = t and r.user_id = ua;
  perform tb_test.check(array_length(e, 1) = n, format('doppelter Punkt samt Höhe entfernt: %s Höhen für %s Punkte', array_length(e, 1), n));
  perform tb_test.check(e[3] = 997 and e[4] = 996 and e[n] = 1000 - n,
                        format('Höhen bleiben bei ihren Punkten (%s, %s … %s)', e[3], e[4], e[n]));
  perform tb_test.check(tb_test.count_as(ua, format('select count(*) from public.recordings_visible where trail_id = %L and array_length(ele, 1) = %s', t, n)) = 1,
                        'die Sicht liefert die Höhen mit');

  -- Ohne Höhen (Clients vor 0.3.0, Dateien ohne <ele>): Spalte leer.
  t := tb_test.contribute(ua, tb_test.line(300, y0 => 13000));
  perform tb_test.check((select r.ele is null from public.trail_recordings r where r.trail_id = t), 'ohne eles: ele ist null');

  -- Falsche Anzahl, eine Lücke, Unsinn: abgelehnt, nicht geraten.
  foreach code in array array['kurz', 'luecke', 'hoch'] loop
    ok := false;
    begin
      perform tb_test.as_user(ua);
      perform public.contribute_recording(tb_test.coords(tb_test.line(300, y0 => 14000)), 'import', null, null,
        case code
          when 'kurz' then array(select 500.0 from generate_series(1, n - 1))
          when 'luecke' then array(select case when i = 5 then null else 500.0 end from generate_series(1, n) i)
          else array(select 12000.0 from generate_series(1, n))
        end);
    exception when others then
      ok := sqlstate = '22023';
    end;
    perform tb_test.as_owner();
    perform tb_test.check(ok, format('Höhen „%s" ⇒ 22023', code));
  end loop;

  -- Der Check hält auch ohne die Funktion: Direkt als Eigentümer eine
  -- zu kurze Reihe schreiben scheitert.
  ok := false;
  begin
    update public.trail_recordings set ele = array[1.0, 2.0] where trail_id = t;
  exception when check_violation then
    ok := true;
  end;
  perform tb_test.check(ok, 'trail_recordings_ele_check verlangt eine Höhe je Punkt');
  perform tb_test.check((select count(*) from pg_proc where proname = 'contribute_recording') = 1,
                        'genau eine contribute_recording (keine alte Signatur daneben)');
end $$;

\echo -- 17. Aufräumjob und Kontolöschung
do $$
declare
  uc uuid := '33333333-3333-4333-8333-333333333333';
  parallel uuid := tb_test.t('parallel');
  n integer;
begin
  perform tb_test.check(app_internal.sweep_orphan_trails() = 0, 'nichts zu fegen, solange jeder Trail einen Beitrag hat');
  -- C löscht sein Konto (RPC als C). Sein einziger eigener Trail ist die Parallele.
  perform tb_test.exec_as(uc, 'select public.delete_own_account()');
  perform tb_test.check(not exists (select 1 from public.profiles where id = uc), 'Konto samt Profil gelöscht');
  perform tb_test.check(not exists (select 1 from public.trail_recordings where user_id = uc), 'Aufzeichnungen von C kaskadiert');
  perform tb_test.check(exists (select 1 from public.trails where id = parallel), 'der Trail bleibt zunächst (kein Cascade vom Beitrag)');
  n := app_internal.sweep_orphan_trails();
  perform tb_test.check(n = 1 and not exists (select 1 from public.trails where id = parallel),
                        format('Aufräumjob entfernt %s verwaisten Trail', n));
  perform tb_test.check(exists (select 1 from public.trails where id = tb_test.t('base')), 'der Basis-Trail bleibt (A hat Beiträge)');
end $$;

\echo -- 18. Tageslimit
do $$
declare
  ub uuid := '22222222-2222-4222-8222-222222222222';
  lim integer := (app_internal.match_params()).daily_limit;
  have integer; i integer; code text; ok boolean := false;
begin
  -- Die Zahl kommt aus match_params, nicht aus diesem Test (Patch 006:
  -- 500); Block 19 erwartet Bernds Linie bei y0 = 25000 (i = 50).
  perform tb_test.check(lim = 500, format('Tageslimit ist 500 (%s)', lim));
  select count(*) into have from public.trail_recordings where user_id = ub;
  for i in have + 1..lim loop
    perform tb_test.contribute(ub, tb_test.line(200, y0 => 20000 + i * 100));
  end loop;
  begin
    perform tb_test.contribute(ub, tb_test.line(200, y0 => 20000 + (lim + 1) * 100));
  exception when others then
    get stacked diagnostics code = returned_sqlstate;
    ok := code = '54000';
  end;
  perform tb_test.check(ok, format('die %s. Aufzeichnung in 24 h wird abgelehnt (%s)', lim + 1, code));
end $$;

\echo -- 19. Höhen nachtragen (Patch 003, Issue #16)
do $$
declare
  ua uuid := '11111111-1111-4111-8111-111111111111';
  ub uuid := '22222222-2222-4222-8222-222222222222';
  c double precision[] := tb_test.coords(tb_test.line(200, y0 => 25000));
  n integer := array_length(c, 1) / 2;
  h double precision[] := array(select (700.0 - i)::double precision from generate_series(1, n) i);
  rid uuid; recs bigint; trails bigint; code text; ok boolean; wrote boolean;
begin
  -- Bernd steht nach Block 18 am Tageslimit: Nachtragen muss trotzdem gehen.
  select r.id into rid from public.trail_recordings r
   where r.user_id = ub and r.ele is null
     and st_dwithin(r.geom, st_setsrid(st_makepoint(c[1], c[2]), 4326)::geography, 0.01);
  perform tb_test.check(rid is not null, 'Bernds Aufzeichnung ohne Höhen gefunden');
  select count(*) into recs from public.trail_recordings;
  select count(*) into trails from public.trails;

  -- Abgelehnt: fremde Aufzeichnung, verschobene Linie, falsche Anzahl.
  foreach code in array array['fremd', 'versetzt', 'kurz'] loop
    ok := false;
    begin
      perform tb_test.as_user(case code when 'fremd' then ua else ub end);
      perform public.attach_elevation(rid,
        case code
          when 'versetzt' then tb_test.coords(tb_test.shift(tb_test.line(200, y0 => 25000), 0, 1))
          when 'kurz' then c[1:array_length(c, 1) - 2]
          else c
        end,
        case code when 'kurz' then h[1:n - 1] else h end);
    exception when others then
      ok := sqlstate = case code when 'fremd' then 'P0002' else '22023' end;
    end;
    perform tb_test.as_owner();
    perform tb_test.check(ok, format('nachtragen „%s" abgelehnt', code));
  end loop;
  perform tb_test.check((select ele is null from public.trail_recordings where id = rid), 'nach den Ablehnungen noch ohne Höhen');

  perform tb_test.as_user(ub);
  wrote := public.attach_elevation(rid, c, h);
  perform tb_test.as_owner();
  perform tb_test.check(wrote, 'dieselbe Linie: Höhen eingetragen, trotz Tageslimit');
  perform tb_test.check((select ele[1] = 699 and ele[n] = 700 - n and array_length(ele, 1) = n
                           from public.trail_recordings where id = rid), 'eine Höhe je Punkt, in Reihenfolge');
  perform tb_test.check((select count(*) from public.trail_recordings) = recs
                        and (select count(*) from public.trails) = trails,
                        'keine neue Aufzeichnung, kein neuer Trail');

  -- Wiederholung: kein Fehler, aber auch kein Überschreiben.
  perform tb_test.as_user(ub);
  wrote := public.attach_elevation(rid, c, array(select 100.0::double precision from generate_series(1, n)));
  perform tb_test.as_owner();
  perform tb_test.check(not wrote and (select ele[1] = 699 from public.trail_recordings where id = rid),
                        'hat sie schon Höhen: false, nichts überschrieben');
end $$;

\echo -- 20. Hinweise für Buddys (Patch 004/005, Issue #7)
do $$
declare
  ua uuid := '11111111-1111-4111-8111-111111111111';
  ub uuid := '22222222-2222-4222-8222-222222222222';
  uc uuid := '33333333-3333-4333-8333-333333333333';
  t uuid;
  note uuid;
  code text; ok boolean;
  cnt text := 'select count(*) from public.trail_notes where trail_id = %L';
begin
  -- Ein Trail, den Anna mit Bernd teilt, den Bernd nicht selbst belegt
  -- hat und von dem Carla nichts weiß.
  select d.trail_id into t from public.trail_details d
   where d.user_id = ua and d.visibility = 'buddies'
     and not exists (select 1 from public.trail_recordings r
                      where r.trail_id = d.trail_id and r.user_id <> ua)
   limit 1;
  perform tb_test.check(t is not null, 'geteilter Trail nur von Anna');
  perform tb_test.check(app_internal.can_see_trail(ub, t) and not app_internal.can_see_trail(uc, t),
                        'Bernd sieht ihn über Anna, Carla nicht');

  perform tb_test.exec_as(ua, format('insert into public.trail_notes (trail_id, user_id, body) values (%L, %L, %L)',
                                     t, ua, 'Baum liegt quer'));
  -- Bernd hat keinen eigenen Beleg, sieht den Trail aber: Er darf schreiben.
  perform tb_test.exec_as(ub, format('insert into public.trail_notes (trail_id, user_id, body) values (%L, %L, %L)',
                                     t, ub, 'Umfahrung links'));
  perform tb_test.check(tb_test.count_as(ua, format(cnt, t)) = 2, 'Anna sieht beide Hinweise');
  perform tb_test.check(tb_test.count_as(ub, format(cnt, t)) = 2, 'Bernd sieht beide Hinweise');
  perform tb_test.check(tb_test.count_as(uc, format(cnt, t)) = 0, 'Carla (kein Buddy, sieht den Trail nicht) sieht keinen');

  -- Abgelehnt: wer den Trail nicht sieht, im Namen eines anderen, leer, zu lang.
  foreach code in array array['sieht den Trail nicht', 'fremder Name', 'leer', 'zu lang'] loop
    ok := false;
    begin
      perform tb_test.exec_as(case code when 'sieht den Trail nicht' then uc else ua end,
        format('insert into public.trail_notes (trail_id, user_id, body) values (%L, %L, %L)',
               t,
               case code when 'sieht den Trail nicht' then uc when 'fremder Name' then ub else ua end,
               case code when 'leer' then '   ' when 'zu lang' then repeat('x', 501) else 'Hinweis' end));
    exception when others then
      ok := sqlstate = case when code in ('leer', 'zu lang') then '23514' else '42501' end;
    end;
    perform tb_test.as_owner();
    perform tb_test.check(ok, format('Hinweis „%s" abgelehnt', code));
  end loop;

  ok := false;
  begin
    perform tb_test.exec_as(ua, format('update public.trail_notes set body = %L where trail_id = %L', 'anders', t));
  exception when others then
    ok := sqlstate = '42501';
  end;
  perform tb_test.as_owner();
  perform tb_test.check(ok, 'Hinweise lassen sich nicht bearbeiten (42501)');

  -- Privat nimmt Annas Hinweis aus Bernds Sicht (und den Trail gleich mit).
  perform tb_test.exec_as(ua, format('update public.trail_details set visibility = %L where trail_id = %L and user_id = %L', 'private', t, ua));
  perform tb_test.check(tb_test.count_as(ub, format(cnt || ' and user_id = %L', t, ua)) = 0,
                        'privat: Bernd sieht Annas Hinweis nicht mehr');
  perform tb_test.check(tb_test.count_as(ub, format(cnt || ' and user_id = %L', t, ub)) = 1,
                        'seinen eigenen sieht Bernd weiter');
  perform tb_test.exec_as(ua, format('update public.trail_details set visibility = %L where trail_id = %L and user_id = %L', 'buddies', t, ua));

  -- Entfernen: Carla (sieht nichts) filtert still, Bernd darf Annas „erledigt" machen.
  perform tb_test.exec_as(uc, format('delete from public.trail_notes where trail_id = %L', t));
  perform tb_test.check((select count(*) from public.trail_notes where trail_id = t) = 2,
                        'Carla kann nichts entfernen');
  perform tb_test.exec_as(ub, format('delete from public.trail_notes where trail_id = %L and user_id = %L', t, ua));
  perform tb_test.check((select count(*) from public.trail_notes where trail_id = t and user_id = ua) = 0,
                        'Bernd entfernt Annas Hinweis (erledigt)');

  ok := false;
  begin
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    perform count(*) from public.trail_notes;
  exception when others then
    ok := sqlstate = '42501';
  end;
  execute 'reset role';
  perform tb_test.check(ok, 'anon hat keinen Grant auf trail_notes');

  -- Aufbewahrung: nach 90 Tagen weg, der jüngste je Autor und Trail bleibt.
  delete from public.trail_notes where trail_id = t;
  insert into public.trail_notes (trail_id, user_id, body, created_at) values
    (t, ua, 'a-alt-1', now() - interval '120 days'),
    (t, ua, 'a-alt-2', now() - interval '100 days'),
    (t, ua, 'a-neu', now() - interval '1 day'),
    (t, ub, 'b-alt-1', now() - interval '200 days'),
    (t, ub, 'b-alt-2', now() - interval '150 days');
  perform tb_test.check(app_internal.sweep_old_notes() = 3, 'drei alte Hinweise aufgeräumt');
  perform tb_test.check((select array_agg(body order by body) from public.trail_notes where trail_id = t)
                        = array['a-neu', 'b-alt-2'],
                        'es bleiben Annas neuer und Bernds jüngster, obwohl alt');
  perform tb_test.check(app_internal.sweep_old_notes() = 0, 'zweiter Lauf räumt nichts mehr');
end $$;

\echo -- 21. Eigenen Beitrag zurückziehen (Patch 010)
do $$
declare
  ua uuid := '11111111-1111-4111-8111-111111111111';
  ub uuid := '22222222-2222-4222-8222-222222222222';
  xy double precision[] := tb_test.line(400, y0 => 60000);
  t uuid; t2 uuid; n integer; ok boolean := false;
  mine text := 'select count(*) from public.%I where trail_id = %L and user_id = %L';
begin
  -- Bernd steht seit Block 18 am Tageslimit; seine Zeilen altern hier.
  update public.trail_recordings set created_at = now() - interval '2 days' where user_id = ub;
  t := tb_test.contribute(ua, xy);
  t2 := tb_test.contribute(ub, xy);
  perform tb_test.check(t = t2, 'Anna und Bernd belegen denselben Trail');
  -- Den Beitrag legt contribute_recording schon an (Block 15).
  perform tb_test.exec_as(ua, format(
    'update public.trail_details set name = %L, visibility = %L where trail_id = %L and user_id = %L',
    'Rückzug', 'private', t, ua));
  perform tb_test.exec_as(ua, format('insert into public.trail_notes (trail_id, user_id, body) values (%L, %L, %L)',
                                     t, ua, 'Annas Hinweis'));
  perform tb_test.exec_as(ub, format('insert into public.trail_notes (trail_id, user_id, body) values (%L, %L, %L)',
                                     t, ub, 'Bernds Hinweis'));

  -- Bernd zieht zurück: nur seine Zeilen, Annas bleiben, der Trail auch.
  perform tb_test.as_user(ub);
  n := public.withdraw_contribution(t);
  perform tb_test.as_owner();
  perform tb_test.check(n = 1, format('Bernd: eine Aufzeichnung gelöscht (%s)', n));
  perform tb_test.check(tb_test.count_as(ub, format(mine, 'trail_recordings', t, ub)) = 0
                        and (select count(*) from public.trail_notes where trail_id = t and user_id = ub) = 0,
                        'Bernds Aufzeichnung und Hinweis sind weg');
  perform tb_test.check((select count(*) from public.trail_recordings where trail_id = t and user_id = ua) = 1
                        and (select count(*) from public.trail_notes where trail_id = t and user_id = ua) = 1
                        and (select count(*) from public.trail_details where trail_id = t and user_id = ua) = 1,
                        'Annas Aufzeichnung, Hinweis und Beitrag bleiben');
  perform tb_test.check(app_internal.sweep_orphan_trails() = 0 and exists (select 1 from public.trails where id = t),
                        'der Trail bleibt, solange Anna ihn belegt');
  perform tb_test.check(not app_internal.can_see_trail(ub, t),
                        'Annas Beitrag ist privat: Bernd sieht den Trail nicht mehr');

  -- Anna zieht zurück: alles weg, der Aufräumjob holt den Trail.
  perform tb_test.as_user(ua);
  n := public.withdraw_contribution(t);
  perform tb_test.as_owner();
  perform tb_test.check(n = 1
                        and not exists (select 1 from public.trail_recordings where trail_id = t)
                        and not exists (select 1 from public.trail_notes where trail_id = t)
                        and not exists (select 1 from public.trail_details where trail_id = t),
                        'Anna: Aufzeichnung, Hinweis und Beitrag in einem Aufruf weg');
  n := app_internal.sweep_orphan_trails();
  perform tb_test.check(n = 1 and not exists (select 1 from public.trails where id = t),
                        format('Aufräumjob entfernt den leeren Trail (%s)', n));

  -- Ein zweiter Aufruf ist kein Fehler, nur 0.
  perform tb_test.as_user(ua);
  n := public.withdraw_contribution(t);
  perform tb_test.as_owner();
  perform tb_test.check(n = 0, 'nochmal zurückziehen: 0, kein Fehler');

  begin
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    perform public.withdraw_contribution(t);
  exception when others then
    ok := sqlstate = '42501';
  end;
  execute 'reset role';
  perform tb_test.check(ok, 'anon darf withdraw_contribution nicht ausführen');
end $$;

\echo -- 22. Link zur Quelle im Beitrag (Patch 012, #103)
do $$
declare
  ua uuid := '11111111-1111-4111-8111-111111111111';
  t uuid := tb_test.t('half');
  bad text;
  code text;
  upd text := 'update public.trail_details set link = %L where trail_id = %L and user_id = %L';
begin
  perform tb_test.exec_as(ua, format(upd, 'https://verein.example/strecken/roots', t, ua));
  perform tb_test.check((select link from public.trail_details where trail_id = t and user_id = ua)
                          = 'https://verein.example/strecken/roots', 'https-Link ohne Query wird gespeichert');
  foreach bad in array array['http://verein.example', 'https://verein.example/a?token=x',
                             'https://verein.example/#karte', 'https://verein.example/mit leer',
                             'https://verein.example/' || repeat('a', 500)] loop
    code := null;
    begin
      perform tb_test.exec_as(ua, format(upd, bad, t, ua));
    exception when others then
      get stacked diagnostics code = returned_sqlstate;
    end;
    perform tb_test.check(code = '23514', format('abgelehnt: %s… (%s)', left(bad, 40), code));
  end loop;
  perform tb_test.exec_as(ua, format('update public.trail_details set link = null where trail_id = %L and user_id = %L', t, ua));
end $$;

\echo -- 23. Bewertung, Meldungen und Zustände (Patch 013, #101)
do $$
declare
  ua uuid := '11111111-1111-4111-8111-111111111111';
  ub uuid := '22222222-2222-4222-8222-222222222222';
  uc uuid := '33333333-3333-4333-8333-333333333333';
  t uuid;
  code text;
  n integer;
  rep text := 'select public.report_trail(%L::uuid, %L::text, %L::integer, %L::boolean, %L::timestamptz, %L::uuid)';
  mine text := 'select count(*) from public.trail_reports where trail_id = %L';
begin
  -- Ein frischer Trail von Anna, geteilt; Bernd sieht ihn über Anna,
  -- ohne ihn gefahren zu sein, Carla sieht ihn nicht.
  t := tb_test.contribute(ua, tb_test.line(400, y0 => 80000));
  perform tb_test.check(app_internal.can_see_trail(ub, t) and not app_internal.can_see_trail(uc, t),
                        'Bernd sieht den Trail über Anna, Carla nicht');

  -- Bewertung am Beitrag: 1–5 oder leer.
  perform tb_test.exec_as(ua, format('update public.trail_details set rating = 4 where trail_id = %L and user_id = %L', t, ua));
  perform tb_test.check((select rating from public.trail_details where trail_id = t and user_id = ua) = 4,
                        'Bewertung 4 gespeichert');
  foreach n in array array[0, 6] loop
    code := null;
    begin
      perform tb_test.exec_as(ua, format('update public.trail_details set rating = %s where trail_id = %L and user_id = %L', n, t, ua));
    exception when others then
      get stacked diagnostics code = returned_sqlstate;
    end;
    perform tb_test.check(code = '23514', format('Bewertung %s abgelehnt (%s)', n, code));
  end loop;
  -- Ein alter Client schreibt per upsert nur seine Spalten: die Bewertung bleibt.
  perform tb_test.exec_as(ua, format(
    'insert into public.trail_details (trail_id, user_id, name, grade, traits, link, visibility, status, status_at) '
    'values (%L, %L, %L, 2, %L, null, %L, %L, null) '
    'on conflict (trail_id, user_id) do update set name = excluded.name, grade = excluded.grade, '
    'traits = excluded.traits, link = excluded.link, visibility = excluded.visibility, '
    'status = excluded.status, status_at = excluded.status_at',
    t, ua, 'Alter Client', '{flowy}', 'buddies', 'open'));
  perform tb_test.check((select rating from public.trail_details where trail_id = t and user_id = ua) = 4,
                        'Upsert eines alten Clients (ohne rating) lässt die Bewertung stehen');

  -- Bernd meldet von zu Hause: erlaubt, aber unbestätigt.
  perform tb_test.exec_as(ub, format(rep, t, 'closed', null, false, null, null));
  perform tb_test.check((select confirmed from public.trail_reports where trail_id = t and user_id = ub) = false,
                        'ohne Beleg und nicht vor Ort: unbestätigt');
  perform tb_test.check(not exists (select 1 from app_internal.push_outbox where trail_id = t),
                        'eine unbestätigte Meldung löst keine Push aus');
  -- Vor Ort: bestätigt, Zustand zugleich.
  perform tb_test.exec_as(ub, format(rep, t, 'closed', 2, true, null, null));
  perform tb_test.check((select count(*) from public.trail_reports where trail_id = t and user_id = ub and confirmed) = 2,
                        'vor Ort: Meldung und Zustand bestätigt, je eine Zeile');
  perform tb_test.check(exists (select 1 from app_internal.push_outbox where trail_id = t and recipient_id = ua and kind = 'trail_status'),
                        'eine bestätigte Meldung „gesperrt" geht an Anna');
  -- Bernd hat keinen Beitrag: Der Abgleich zum alten Status legt keinen an.
  perform tb_test.check(not exists (select 1 from public.trail_details where trail_id = t and user_id = ub),
                        'Melden legt keinen Beitrag an');

  -- Anna ist gefahren: bestätigt auch von zu Hause, und am Beitrag steht
  -- der alte Status für Clients bis 0.48.0.
  perform tb_test.exec_as(ua, format(rep, t, 'changed', null, false, null, null));
  perform tb_test.check((select confirmed from public.trail_reports where trail_id = t and user_id = ua and kind = 'status'),
                        'gefahren: bestätigt, auch ohne vor Ort');
  perform tb_test.check((select status from public.trail_details where trail_id = t and user_id = ua) = 'changed',
                        'bestätigte Meldung landet am Beitrag (alte Clients)');
  -- Ein alter Client meldet am Beitrag: Es entsteht eine Meldung.
  perform tb_test.exec_as(ua, format('update public.trail_details set status = %L, status_at = now() + interval ''1 hour'' where trail_id = %L and user_id = %L',
                                     'destroyed', t, ua));
  perform tb_test.check((select count(*) from public.trail_reports where trail_id = t and user_id = ua and status = 'destroyed') = 1,
                        'Status am Beitrag (alter Client) wird zur Meldung');
  perform tb_test.check((select reported_at <= now() from public.trail_reports where trail_id = t and user_id = ua and status = 'destroyed'),
                        'eine Zeit in der Zukunft wird auf jetzt gekappt');
  -- Eine Fahrt von vor zwei Jahren verdrängt keine Meldung von heute.
  perform tb_test.check(tb_test.contribute(ua, tb_test.jitter(tb_test.line(400, y0 => 80000), 3.0, 0.5), 'import',
                                           at => now() - interval '2 years') = t, 'alte Datei ⇒ derselbe Trail');
  perform tb_test.check(not exists (select 1 from public.trail_reports where trail_id = t and user_id = ua and status = 'open'),
                        'eine alte Fahrt setzt die Meldung nicht auf offen');

  -- Idempotenz: derselbe Auftrag zweimal ⇒ eine Zeile.
  perform tb_test.exec_as(ub, format(rep, t, null, 3, false, null, '00000000-0000-4000-8000-0000000000aa'));
  perform tb_test.exec_as(ub, format(rep, t, null, 3, false, null, '00000000-0000-4000-8000-0000000000aa'));
  perform tb_test.check((select count(*) from public.trail_reports
                          where user_id = ub and client_id = '00000000-0000-4000-8000-0000000000aa') = 1,
                        'Wiedervorlage desselben Auftrags legt keine zweite Zeile an');

  -- Abgelehnt: wer den Trail nicht sieht, nichts gemeldet, Werte außerhalb.
  foreach code in array array['carla', 'leer', 'zustand', 'status', 'direkt'] loop
    declare got text := null; want text;
    begin
      want := case code when 'carla' then '42501' when 'leer' then '22023'
                        when 'direkt' then '42501' else '23514' end;
      begin
        case code
          when 'carla' then perform tb_test.exec_as(uc, format(rep, t, 'closed', null, true, null, null));
          when 'leer' then perform tb_test.exec_as(ub, format(rep, t, null, null, false, null, null));
          when 'zustand' then perform tb_test.exec_as(ub, format(rep, t, null, 6, false, null, null));
          when 'status' then perform tb_test.exec_as(ub, format(rep, t, 'kaputt', null, false, null, null));
          else perform tb_test.exec_as(ub, format(
            'insert into public.trail_reports (trail_id, user_id, kind, status, confirmed, reported_at) values (%L, %L, %L, %L, true, now())',
            t, ub, 'status', 'open'));
        end case;
      exception when others then
        get stacked diagnostics got = returned_sqlstate;
      end;
      perform tb_test.as_owner();
      perform tb_test.check(got = want, format('abgelehnt: %s (%s)', code, got));
    end;
  end loop;

  -- Schutz gegen Fluten: ab 200 Zeilen in 24 h ist Schluss (54000).
  insert into public.trail_reports (trail_id, user_id, kind, status, confirmed, reported_at)
    select t, ub, 'status', 'open', false, now() - interval '100 days' from generate_series(1, 200);
  code := null;
  begin
    perform tb_test.exec_as(ub, format(rep, t, 'open', null, false, null, null));
  exception when others then
    get stacked diagnostics code = returned_sqlstate;
  end;
  perform tb_test.as_owner();
  perform tb_test.check(code = '54000', format('Tageslimit der Meldungen (%s)', code));
  delete from public.trail_reports where trail_id = t and user_id = ub
     and reported_at < now() - interval '99 days' and status = 'open' and not confirmed;

  -- Sichtbar: Anna und Bernd sehen alles, Carla nichts.
  perform tb_test.check(tb_test.count_as(ub, format(mine, t)) = tb_test.count_as(ua, format(mine, t))
                        and tb_test.count_as(ua, format(mine, t)) = (select count(*) from public.trail_reports where trail_id = t),
                        'Anna und Bernd sehen alle Meldungen');
  perform tb_test.check(tb_test.count_as(uc, format(mine, t)) = 0, 'Carla sieht keine');
  -- Privat: Annas Meldungen verschwinden aus Bernds Sicht, seine bleiben.
  perform tb_test.exec_as(ua, format('update public.trail_details set visibility = %L where trail_id = %L and user_id = %L', 'private', t, ua));
  perform tb_test.check(tb_test.count_as(ub, format(mine || ' and user_id = %L', t, ua)) = 0,
                        'privat: Annas Meldungen sieht Bernd nicht mehr');
  perform tb_test.exec_as(ua, format('update public.trail_details set visibility = %L where trail_id = %L and user_id = %L', 'buddies', t, ua));

  -- Aufräumen nach 90 Tagen: die jüngste je Person, Art und Bestätigung bleibt.
  update public.trail_reports set reported_at = reported_at - interval '100 days'
   where trail_id = t and user_id = ub;
  n := app_internal.sweep_old_reports();
  perform tb_test.check(n = 0, format('jede alte Angabe ist die jüngste ihrer Art: nichts entfernt (%s)', n));
  perform tb_test.exec_as(ub, format(rep, t, 'open', null, false, null, null));
  n := app_internal.sweep_old_reports();
  perform tb_test.check(n = 1, format('eine neuere unbestätigte Meldung: die alte fällt weg (%s)', n));
  perform tb_test.check((select count(*) from public.trail_reports where trail_id = t and user_id = ub) = 4
                        and exists (select 1 from public.trail_reports where trail_id = t and user_id = ub
                                     and confirmed and status = 'closed'),
                        'die alte bestätigte Meldung bleibt — sie ist Bernds jüngste bestätigte');

  -- Zurückziehen nimmt die eigenen Meldungen mit, fremde bleiben.
  perform tb_test.as_user(ua);
  perform public.withdraw_contribution(t);
  perform tb_test.as_owner();
  perform tb_test.check(not exists (select 1 from public.trail_reports where trail_id = t and user_id = ua),
                        'withdraw_contribution löscht Annas Meldungen');

  code := null;
  begin
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    perform public.report_trail(t, 'open');
  exception when others then
    code := sqlstate;
  end;
  execute 'reset role';
  perform tb_test.check(code = '42501', 'anon darf report_trail nicht ausführen');
end $$;

\echo -- 24. Fahrdatum für eine geplante Datei (Patch 015, #120)
do $$
declare
  ua uuid := '11111111-1111-4111-8111-111111111111';
  t uuid;
  rep text := 'select public.report_trail(%L::uuid, %L::text, %L::integer, %L::boolean, %L::timestamptz, %L::uuid)';
begin
  -- Geplant ohne Datum: kein Beleg einer Fahrt, Meldungen unbestätigt.
  t := tb_test.contribute(ua, tb_test.line(400, y0 => 90000), 'planned');
  perform tb_test.check(not app_internal.has_ridden(ua, t), 'geplant ohne Datum: nicht gefahren');
  perform tb_test.exec_as(ua, format(rep, t, 'closed', null, false, now() - interval '3 minutes', null));
  perform tb_test.check(not (select confirmed from public.trail_reports where trail_id = t and user_id = ua),
                        'geplant ohne Datum: Meldung unbestätigt');

  -- Dieselbe Linie noch einmal geplant, jetzt MIT eingetragenem Datum.
  perform tb_test.check(tb_test.contribute(ua, tb_test.jitter(tb_test.line(400, y0 => 90000), 3.0, 0.45), 'planned',
                                           at => now() - interval '1 minute') = t,
                        'geplant mit Datum ⇒ derselbe Trail');
  perform tb_test.check(app_internal.has_ridden(ua, t), 'geplant mit Datum: gefahren');
  perform tb_test.check((select max(quality) from public.trail_recordings where trail_id = t) < 0.2,
                        'die Linie bleibt gezeichnet: Qualität 0,1');
  perform tb_test.check(exists (select 1 from public.trail_reports
                                 where trail_id = t and user_id = ua and status = 'open' and confirmed
                                   and reported_at = now() - interval '1 minute'),
                        'Schritt 8: die eigene Meldung steht zum Fahrdatum auf offen');
  perform tb_test.exec_as(ua, format(rep, t, null, 2, false, null, null));
  perform tb_test.check((select confirmed from public.trail_reports where trail_id = t and user_id = ua and kind = 'condition'),
                        'wer mit Datum gefahren ist, meldet bestätigt');
end $$;

\echo -- 25. Duplikate zusammenführen (Patch 019, #107)
-- Eigene Konten, weit weg von den Linien oben: Dora (D), Emil (E) und
-- Fritz (F) sind untereinander Buddys; Gina (G) kennt niemanden.
insert into auth.users (id, email, raw_user_meta_data) values
  ('44444444-4444-4444-8444-444444444444', 'd@example.org', '{"username":"dora"}'),
  ('55555555-5555-4555-8555-555555555555', 'e@example.org', '{"username":"emil"}'),
  ('66666666-6666-4666-8666-666666666666', 'f@example.org', '{"username":"fritz"}'),
  ('77777777-7777-4777-8777-777777777777', 'g@example.org', '{"username":"gina"}');
insert into public.friendships (requester_id, addressee_id, status) values
  ('44444444-4444-4444-8444-444444444444', '55555555-5555-4555-8555-555555555555', 'accepted'),
  ('44444444-4444-4444-8444-444444444444', '66666666-6666-4666-8666-666666666666', 'accepted'),
  ('55555555-5555-4555-8555-555555555555', '66666666-6666-4666-8666-666666666666', 'accepted');

create or replace function tb_test.merges_as(uid uuid)
returns table (trail_id uuid, same_as uuid, reversed boolean, kind text, by_users uuid[])
language plpgsql as $$
begin
  perform tb_test.as_user(uid);
  return query select * from public.trail_merges();
  perform tb_test.as_owner();
end $$;

create or replace function tb_test.merge_as(uid uuid, dup uuid, keep uuid)
returns uuid language plpgsql as $$
declare
  t uuid;
begin
  perform tb_test.as_user(uid);
  t := public.merge_own_into(dup, keep);
  perform tb_test.as_owner();
  return t;
end $$;

-- Wirft die RPC, kommt der SQLSTATE zurück, sonst null.
create or replace function tb_test.state_of(uid uuid, sql text)
returns text language plpgsql as $$
declare
  code text;
begin
  begin
    perform tb_test.exec_as(uid, sql);
  exception when others then
    get stacked diagnostics code = returned_sqlstate;
    execute 'reset role';
  end;
  return code;
end $$;

do $$
declare
  ud uuid := '44444444-4444-4444-8444-444444444444';
  ue uuid := '55555555-5555-4555-8555-555555555555';
  uf uuid := '66666666-6666-4666-8666-666666666666';
  ug uuid := '77777777-7777-4777-8777-777777777777';
  l1 double precision[] := tb_test.line(800, y0 => 120000);
  l2 double precision[] := tb_test.shift(tb_test.line(800, y0 => 120000), 0, 25);
  t1 uuid; t2 uuid; t uuid;
  n bigint;
  code text;
  m record;
begin
  -- Zwei eigene Importe derselben Strecke, 25 m auseinander: zwei Trails.
  t1 := tb_test.contribute(ud, l1, 'import');
  t2 := tb_test.contribute(ud, l2, 'import');
  perform tb_test.check(t1 <> t2, '25 m parallel: zwei Trails (außerhalb des Korridors)');
  perform tb_test.exec_as(ud, format('update public.trail_details set name = %L where trail_id = %L and user_id = %L', 'Hexentanz', t1, ud));
  perform tb_test.exec_as(ud, format('update public.trail_details set name = %L, grade = 3, traits = %L where trail_id = %L and user_id = %L',
                                     'Roots', '{flowy}', t2, ud));
  perform tb_test.exec_as(ud, format('insert into public.trail_notes (trail_id, user_id, body) values (%L, %L, %L)', t2, ud, 'Baum quer'));
  perform tb_test.exec_as(ud, format('select public.report_trail(%L::uuid, %L::text)', t2, 'closed'));
  -- Fritz fährt die B-Linie, Emil die A-Linie.
  perform tb_test.check(tb_test.contribute(uf, tb_test.jitter(l2, 3.0, 0.31)) = t2, 'Fritz fährt B: hängt an B');
  perform tb_test.check(tb_test.contribute(ue, tb_test.jitter(l1, 3.0, 0.32)) = t1, 'Emil fährt A: hängt an A');

  -- Gina sieht keinen der beiden: dieselbe Antwort wie für eine erfundene Kennung.
  code := tb_test.state_of(ug, format('select public.merge_own_into(%L, %L)', t2, t1));
  perform tb_test.check(code = 'P0002', format('Fremde: merge_own_into antwortet „nicht gefunden" (%s)', code));
  code := tb_test.state_of(ug, format('select public.merge_own_into(%L, %L)', gen_random_uuid(), t1));
  perform tb_test.check(code = 'P0002', format('erfundene Kennung: dieselbe Antwort (%s)', code));
  perform tb_test.check((select count(*) from tb_test.merges_as(ug)) = 0, 'Fremde: trail_merges sagt nichts');
  code := tb_test.state_of(ud, format('select public.merge_own_into(%L, %L)', t1, t1));
  perform tb_test.check(code = '22023', format('derselbe Trail zweimal: abgelehnt (%s)', code));

  -- Dora: „B ist ein Duplikat von A".
  perform tb_test.check(tb_test.merge_as(ud, t2, t1) = t1, 'merge_own_into gibt den behaltenen Trail zurück');
  perform tb_test.check(not exists (select 1 from public.trail_recordings where trail_id = t2 and user_id = ud)
                        and (select count(*) from public.trail_recordings where trail_id = t1 and user_id = ud) = 2,
                        'Doras Aufzeichnungen hängen jetzt an A');
  perform tb_test.check((select count(*) from public.trail_recordings where trail_id = t2) = 1,
                        'Fritz behält seine Aufzeichnung an B (niemand ändert fremde Daten)');
  perform tb_test.check(not exists (select 1 from public.trail_details where trail_id = t2 and user_id = ud),
                        'Doras Beitrag an B ist weg');
  select * into m from public.trail_details where trail_id = t1 and user_id = ud;
  perform tb_test.check(m.name = 'Hexentanz' and m.grade = 3 and m.traits = '{flowy}',
                        'Beitrag verschmolzen: A gewinnt den Namen, B füllt Grad und Charakter');
  perform tb_test.check(exists (select 1 from public.trail_notes where trail_id = t1 and user_id = ud and body = 'Baum quer')
                        and exists (select 1 from public.trail_reports where trail_id = t1 and user_id = ud and status = 'closed'),
                        'Hinweis und Meldung sind mit umgezogen');
  perform tb_test.check(tb_test.merge_as(ud, t2, t1) = t1, 'zweiter Aufruf (Ausgangskorb): dieselbe Antwort');

  -- Was jeder darüber erfährt.
  perform tb_test.check((select count(*) from tb_test.merges_as(ud) x where x.kind = 'own' and x.trail_id = t2 and x.same_as = t1) = 1
                        and (select count(*) from tb_test.merges_as(ud)) = 1,
                        'Dora: genau ihre eigene Zuordnung');
  perform tb_test.check((select count(*) from tb_test.merges_as(uf) x
                          where x.kind = 'proposed' and x.trail_id = t2 and x.same_as = t1 and x.by_users = array[ud]) = 1,
                        'Fritz (hat an B selbst etwas): Vorschlag von Dora');
  perform tb_test.check((select count(*) from tb_test.merges_as(ue) x
                          where x.kind = 'folded' and x.trail_id = t2 and x.same_as = t1 and not x.reversed) = 1,
                        'Emil (sieht beide, hat an B nichts): B verschwindet unter A');
  perform tb_test.check((select count(*) from tb_test.merges_as(ug)) = 0, 'Gina: weiterhin nichts');

  -- Privat: Doras Erklärung zählt nicht, solange ihre Beiträge privat sind.
  perform tb_test.exec_as(ud, format('update public.trail_details set visibility = %L where trail_id = %L and user_id = %L', 'private', t1, ud));
  perform tb_test.check((select count(*) from tb_test.merges_as(ue)) = 0,
                        'privat: Emil sieht A weiter (eigene Fahrt), erfährt aber nichts von Doras Erklärung');
  perform tb_test.exec_as(ud, format('update public.trail_details set visibility = %L where trail_id = %L and user_id = %L', 'buddies', t1, ud));

  -- Einspruch: Fritz (Besitzer von B) sagt „verschieden" — B bleibt für Emil stehen.
  perform tb_test.exec_as(uf, format('select public.mark_distinct(%L, %L)', t1, t2));
  perform tb_test.check((select count(*) from tb_test.merges_as(ue)) = 0, 'Einspruch des Besitzers: bei Emil faltet nichts');
  perform tb_test.check((select count(*) from tb_test.merges_as(uf) x where x.kind = 'distinct') = 1
                        and (select count(*) from tb_test.merges_as(uf) x where x.kind = 'proposed') = 0,
                        'Fritz: sein „verschieden" steht, der Vorschlag ist weg');
  perform tb_test.exec_as(uf, format('select public.unmark_distinct(%L, %L)', t2, t1));
  perform tb_test.check((select count(*) from tb_test.merges_as(ue) x where x.kind = 'folded') = 1, 'Einspruch zurückgenommen: B faltet wieder');

  -- Doras spätere Fahrt auf der B-Linie landet an A — nach ihrer eigenen Erklärung.
  t := tb_test.contribute(ud, tb_test.jitter(l2, 3.0, 0.33));
  perform tb_test.check(t = t1, 'Doras neue Fahrt auf der B-Linie hängt an A');
  -- Fritz nicht: Seine Fahrt auf der B-Linie bleibt an B (keine Umleitung für alle, E5).
  perform tb_test.check(tb_test.contribute(uf, tb_test.jitter(l2, 3.0, 0.34)) = t2, 'Fritz’ neue Fahrt bleibt an B');

  -- Emil erklärt B selbst zum Duplikat, ohne daran etwas zu haben: Es zieht
  -- nichts um, aber seine erste Fahrt auf der B-Linie landet an A — über
  -- die Zuordnung, denn eine eigene Linie dort hat er nicht.
  perform tb_test.check(tb_test.merge_as(ue, t2, t1) = t1, 'Emil erklärt B zum Duplikat');
  perform tb_test.check((select count(*) from tb_test.merges_as(ue) x where x.kind = 'own') = 1
                        and (select count(*) from tb_test.merges_as(ue) x where x.kind = 'folded') = 0,
                        'Emil: die eigene Zeile ersetzt die stille Zuordnung');
  perform tb_test.check(tb_test.contribute(ue, tb_test.jitter(l2, 3.0, 0.37)) = t1, 'Emils Fahrt auf der B-Linie hängt an A');

  -- Fritz nimmt den Vorschlag an: B ist leer und geht mit dem Aufräumjob.
  perform tb_test.check(tb_test.merge_as(uf, t2, t1) = t1, 'Fritz führt zusammen');
  perform tb_test.check(not exists (select 1 from public.trail_recordings where trail_id = t2)
                        and not exists (select 1 from public.trail_details where trail_id = t2),
                        'an B hängt nichts mehr');
  perform app_internal.sweep_orphan_trails();
  perform tb_test.check(not exists (select 1 from public.trails where id = t2)
                        and not exists (select 1 from app_internal.trail_aliases where trail_id = t2),
                        'B ist weg, die Zuordnungen mit ihm');
  perform tb_test.check((select count(*) from tb_test.merges_as(ue)) = 0, 'Emil: nichts mehr zu falten');
  perform tb_test.check(tb_test.contribute(uf, tb_test.jitter(l2, 3.0, 0.35)) = t1,
                        'Fritz’ nächste Fahrt auf der B-Linie trifft seine eigene umgezogene Linie an A');
end $$;

do $$
declare
  ud uuid := '44444444-4444-4444-8444-444444444444';
  ue uuid := '55555555-5555-4555-8555-555555555555';
  l5 double precision[] := tb_test.line(600, y0 => 140000);
  t3 uuid; t4 uuid; t5 uuid; t6 uuid; t7 uuid; t8 uuid;
  code text;
begin
  -- Zu weit auseinander (200 m): kein Zusammenführen.
  t3 := tb_test.contribute(ud, tb_test.line(800, y0 => 130000), 'import');
  t4 := tb_test.contribute(ud, tb_test.line(800, y0 => 130200), 'import');
  code := tb_test.state_of(ud, format('select public.merge_own_into(%L, %L)', t4, t3));
  perform tb_test.check(code = '22023', format('200 m auseinander: abgelehnt (%s)', code));
  perform tb_test.check(exists (select 1 from public.trail_recordings where trail_id = t4 and user_id = ud),
                        'nach der Ablehnung ist nichts umgezogen');

  -- Gegenrichtung: B läuft 25 m daneben andersherum.
  t5 := tb_test.contribute(ud, l5, 'import');
  t6 := tb_test.contribute(ud, tb_test.reverse_xy(tb_test.shift(l5, 0, 25)), 'import');
  perform tb_test.check(tb_test.merge_as(ud, t6, t5) = t5, 'Gegenrichtung: zusammengeführt');
  perform tb_test.check((select bool_and(reversed) from app_internal.trail_aliases where user_id = ud and trail_id = t6)
                        and exists (select 1 from public.trail_recordings where trail_id = t5 and user_id = ud and reversed),
                        'Zuordnung und umgezogene Aufzeichnung tragen „gegen A"');
  perform tb_test.check(tb_test.contribute(ud, tb_test.jitter(tb_test.reverse_xy(tb_test.shift(l5, 0, 25)), 3.0, 0.36)) = t5,
                        'neue Fahrt auf der B-Linie: an A');
  -- Die Importe tragen `import`, die neue Fahrt `app` (created_at ist im
  -- Block für alle gleich).
  perform tb_test.check((select reversed from public.trail_recordings where trail_id = t5 and user_id = ud and source = 'app'),
                        'die neue Fahrt läuft gegen A');

  -- Overlap-Kante zwischen zwei eigenen Trails (Teil): Vorrat für „Sind das dieselben?".
  t7 := tb_test.contribute(ud, tb_test.line(800, y0 => 150000));
  t8 := tb_test.contribute(ud, tb_test.line(400, y0 => 150000));
  perform tb_test.check(t7 <> t8, 'die Hälfte wird ein eigener Trail');
  perform tb_test.check((select count(*) from tb_test.merges_as(ud) x where x.kind = 'overlap' and x.trail_id = t8 and x.same_as = t7) = 1,
                        'Dora: die Kante als Vorschlag');
  perform tb_test.check((select count(*) from tb_test.merges_as(ue) x where x.kind = 'overlap') = 0,
                        'Emil (an keinem der beiden beteiligt): keine Kante');
  perform tb_test.exec_as(ud, format('select public.mark_distinct(%L, %L)', t8, t7));
  perform tb_test.check((select count(*) from tb_test.merges_as(ud) x where x.kind = 'overlap') = 0,
                        '„verschieden" nimmt die Kante aus dem Vorschlag');
end $$;

do $$
declare
  ud uuid := '44444444-4444-4444-8444-444444444444';
  code text;
begin
  code := tb_test.state_of(ud, 'select count(*) from app_internal.trail_aliases');
  perform tb_test.check(code = '42501', format('trail_aliases ist für authenticated nicht lesbar (%s)', code));
  code := tb_test.state_of(ud, 'select count(*) from app_internal.trail_distinct');
  perform tb_test.check(code = '42501', format('trail_distinct ist für authenticated nicht lesbar (%s)', code));
  code := null;
  begin
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    perform * from public.trail_merges();
  exception when others then
    code := sqlstate;
  end;
  execute 'reset role';
  perform tb_test.check(code = '42501', format('anon darf trail_merges nicht ausführen (%s)', code));
end $$;

\echo -- 26. Beim Zusammenführen gilt der Name des behaltenen Trails (Patch 020, #107)
-- Dora und Emil aus Block 25 sind Buddys. Dora hat an A keinen eigenen
-- Beitrag: Ihr Name von B darf A bei ihr nicht umbenennen, wenn A schon
-- einen Namen trägt, den sie sieht — ihre Einschätzung zieht trotzdem mit.
do $$
declare
  ud uuid := '44444444-4444-4444-8444-444444444444';
  ue uuid := '55555555-5555-4555-8555-555555555555';
  a uuid; b uuid;
  m record;
begin
  -- (1) A heißt für Dora schon „Wald" (Emils Beitrag).
  a := tb_test.contribute(ue, tb_test.line(800, y0 => 160000), 'import');
  perform tb_test.exec_as(ue, format('update public.trail_details set name = %L where trail_id = %L and user_id = %L', 'Wald', a, ue));
  b := tb_test.contribute(ud, tb_test.shift(tb_test.line(800, y0 => 160000), 0, 25), 'import');
  perform tb_test.exec_as(ud, format('update public.trail_details set name = %L, grade = 2 where trail_id = %L and user_id = %L', 'Wald unten', b, ud));
  perform tb_test.check(tb_test.merge_as(ud, b, a) = a, 'Patch 020: zusammengeführt');
  select * into m from public.trail_details where trail_id = a and user_id = ud;
  perform tb_test.check(m.name is null and m.grade = 2,
                        'A trägt schon einen sichtbaren Namen: Doras Name fällt weg, ihr Grad zieht mit');

  -- (2) A ist für Dora namenlos: Ihr Name von B füllt ihn.
  a := tb_test.contribute(ue, tb_test.line(800, y0 => 170000), 'import');
  b := tb_test.contribute(ud, tb_test.shift(tb_test.line(800, y0 => 170000), 0, 25), 'import');
  perform tb_test.exec_as(ud, format('update public.trail_details set name = %L where trail_id = %L and user_id = %L', 'Stück', b, ud));
  perform tb_test.merge_as(ud, b, a);
  select * into m from public.trail_details where trail_id = a and user_id = ud;
  perform tb_test.check(m.name = 'Stück', 'A ist namenlos: Doras Name von B füllt ihn');

  -- (3) Emils Name an A ist privat — Dora sieht ihn nicht, also zählt er nicht.
  a := tb_test.contribute(ue, tb_test.line(800, y0 => 180000), 'import');
  perform tb_test.exec_as(ue, format('update public.trail_details set name = %L, visibility = %L where trail_id = %L and user_id = %L',
                                     'Geheim', 'private', a, ue));
  -- Dora sieht A nur über eine eigene Aufzeichnung (Emils ist privat).
  perform tb_test.contribute(ud, tb_test.jitter(tb_test.line(800, y0 => 180000), 3.0, 0.61), 'import');
  b := tb_test.contribute(ud, tb_test.shift(tb_test.line(800, y0 => 180000), 0, 25), 'import');
  perform tb_test.exec_as(ud, format('update public.trail_details set name = %L where trail_id = %L and user_id = %L', 'Offen', b, ud));
  perform tb_test.merge_as(ud, b, a);
  select * into m from public.trail_details where trail_id = a and user_id = ud;
  perform tb_test.check(m.name = 'Offen', 'ein privater Name an A zählt nicht: Doras Name füllt ihren leeren Beitrag');
end $$;

\echo -- 27. Nachrichten zwischen Buddys (Patch 021, #34)
-- Hanna (H) hat Ivo (I) angefragt, offen; Jana (J) kennt keinen der
-- beiden. Die Grenzen stehen nur hier — die App zeigt sie bloß vorab.
insert into auth.users (id, email, raw_user_meta_data) values
  ('88888888-8888-4888-8888-888888888888', 'h@example.org', '{"username":"hanna"}'),
  ('99999999-9999-4999-8999-999999999999', 'i@example.org', '{"username":"ivo"}'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'j@example.org', '{"username":"jana"}');
insert into public.friendships (requester_id, addressee_id, status) values
  ('88888888-8888-4888-8888-888888888888', '99999999-9999-4999-8999-999999999999', 'pending');

-- Wie viele Zeilen sieht [uid] mit [sql] (ein select count(*))?
create or replace function tb_test.count_as(uid uuid, sql text)
returns bigint language plpgsql as $$
declare
  n bigint;
begin
  perform tb_test.as_user(uid);
  execute sql into n;
  perform tb_test.as_owner();
  return n;
end $$;

do $$
declare
  uh uuid := '88888888-8888-4888-8888-888888888888';
  ui uuid := '99999999-9999-4999-8999-999999999999';
  uj uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  send text := 'insert into public.buddy_messages (recipient_id, body) values (%L, %L)';
  code text;
  m uuid;
begin
  -- (1) Offene Anfrage: drei Nachrichten je Absender, die vierte nicht.
  perform tb_test.exec_as(uh, format(send, ui, 'Ich bin die vom Bikepark'));
  perform tb_test.exec_as(uh, format(send, ui, 'zwei'));
  perform tb_test.exec_as(uh, format(send, ui, 'drei'));
  code := tb_test.state_of(uh, format(send, ui, 'vier'));
  perform tb_test.check(code = '42501', format('offene Anfrage: die vierte Nachricht wird abgelehnt (%s)', code));
  -- Die Grenze gilt je Absender: Ivo darf trotzdem antworten.
  perform tb_test.exec_as(ui, format(send, uh, 'Hallo Hanna'));
  perform tb_test.check(tb_test.count_as(uh, 'select count(*) from public.buddy_messages') = 4,
                        'Hanna sieht ihre drei und Ivos Antwort');

  -- (2) Ohne Anfrage keine Nachricht, und fremde Verläufe sieht niemand.
  code := tb_test.state_of(uj, format(send, uh, 'Hallo?'));
  perform tb_test.check(code = '42501', format('ohne Anfrage keine Nachricht (%s)', code));
  perform tb_test.check(tb_test.count_as(uj, 'select count(*) from public.buddy_messages') = 0,
                        'Jana sieht keine fremden Nachrichten');

  -- (3) Spalten-Grants: Anlegen nur mit Empfänger und Text, ändern nur read_at.
  -- Ivo darf noch schreiben (eine von drei) — sonst verwehrte schon die
  -- Policy, und der Fall prüfte den Grant nicht.
  code := tb_test.state_of(ui, format('insert into public.buddy_messages (recipient_id, body, created_at) values (%L, %L, now() + interval ''1 year'')', uh, 'später'));
  perform tb_test.check(code = '42501', format('created_at lässt sich nicht setzen (%s)', code));
  code := tb_test.state_of(ui, format('update public.buddy_messages set body = %L where recipient_id = %L', 'anders', ui));
  perform tb_test.check(code = '42501', format('den Text ändert niemand (%s)', code));

  -- (4) Gelesen markieren nur, was an mich ging.
  perform tb_test.exec_as(uh, 'update public.buddy_messages set read_at = now()');
  perform tb_test.check(not exists (select 1 from public.buddy_messages where sender_id = uh and read_at is not null),
                        'Hanna markiert ihre eigenen nicht als gelesen …');
  perform tb_test.check((select read_at from public.buddy_messages where sender_id = ui) is not null,
                        '… wohl aber Ivos Antwort an sie');
  perform tb_test.exec_as(uj, 'update public.buddy_messages set read_at = now()');
  perform tb_test.check((select count(*) from public.buddy_messages where read_at is not null) = 1,
                        'Jana markiert nichts');
  perform tb_test.exec_as(ui, format('update public.buddy_messages set read_at = now() where recipient_id = %L', ui));
  perform tb_test.check((select count(*) from public.buddy_messages where recipient_id = ui and read_at is not null) = 3,
                        'Ivo markiert seine drei als gelesen');

  -- (5) Löschen nur die eigenen.
  select id into m from public.buddy_messages where sender_id = uh order by created_at limit 1;
  perform tb_test.exec_as(ui, format('delete from public.buddy_messages where id = %L', m));
  perform tb_test.check(exists (select 1 from public.buddy_messages where id = m), 'Ivo löscht Hannas Nachricht nicht');
  perform tb_test.exec_as(uh, format('delete from public.buddy_messages where id = %L', m));
  perform tb_test.check(not exists (select 1 from public.buddy_messages where id = m), 'Hanna nimmt ihre eigene zurück');
  -- Zurückgenommen zählt nicht mehr: Wieder Platz für eine.
  perform tb_test.exec_as(uh, format(send, ui, 'noch mal drei'));

  -- (6) Angenommen ⇒ unbegrenzt.
  perform tb_test.exec_as(ui, format('update public.friendships set status = %L where addressee_id = %L', 'accepted', ui));
  perform tb_test.exec_as(uh, format(send, ui, 'vier'));
  perform tb_test.exec_as(uh, format(send, ui, 'fünf'));
  perform tb_test.check(tb_test.count_as(ui, format('select count(*) from public.buddy_messages where sender_id = %L', uh)) = 5,
                        'als Buddys gilt keine Grenze');

  -- (7) 30 Tage: Abgelaufenes sieht niemand, der Job räumt es.
  insert into public.buddy_messages (sender_id, recipient_id, body, created_at, expires_at)
    values (uh, ui, 'alt', now() - interval '31 days', now() - interval '1 day');
  perform tb_test.check(tb_test.count_as(ui, format('select count(*) from public.buddy_messages where body = %L', 'alt')) = 0,
                        'eine abgelaufene Nachricht ist unsichtbar');
  perform tb_test.check(app_internal.sweep_expired_messages() = 1, 'der Aufräumjob löscht genau die abgelaufene');
  code := null;
  begin
    insert into public.buddy_messages (sender_id, recipient_id, body, created_at, expires_at)
      values (uh, ui, 'ewig', now(), now() + interval '31 days');
  exception when check_violation then
    code := '23514';
  end;
  perform tb_test.check(code = '23514', 'länger als 30 Tage verbietet der Check');

  -- (8) Ende der Freundschaft löscht beide Seiten.
  perform tb_test.exec_as(ui, format('delete from public.friendships where addressee_id = %L', ui));
  perform tb_test.check(not exists (select 1 from public.buddy_messages
                                     where (sender_id = uh and recipient_id = ui) or (sender_id = ui and recipient_id = uh)),
                        'entfreundet: der Verlauf ist auf beiden Seiten weg');
end $$;

\echo -- 28. Nachrichten warten auf den Push (Patch 022, #34)
-- push_flush selbst braucht Vault und pg_net — das prüft
-- tool/push_flush_check.sh im Dry Run. Hier die Schlange: Jede neue
-- Nachricht legt eine Zeile an, Zurücknehmen und Entfreunden nehmen sie mit.
do $$
declare
  uh uuid := '88888888-8888-4888-8888-888888888888';
  ui uuid := '99999999-9999-4999-8999-999999999999';
  m uuid;
begin
  delete from app_internal.push_messages;
  insert into public.friendships (requester_id, addressee_id, status) values (uh, ui, 'accepted');
  perform tb_test.exec_as(uh, format('insert into public.buddy_messages (recipient_id, body) values (%L, %L)', ui, 'eins'));
  perform tb_test.exec_as(uh, format('insert into public.buddy_messages (recipient_id, body) values (%L, %L)', ui, 'zwei'));
  perform tb_test.check((select count(*) from app_internal.push_messages) = 2, 'jede Nachricht wartet in der Schlange');
  select id into m from public.buddy_messages where body = 'eins';
  perform tb_test.exec_as(uh, format('delete from public.buddy_messages where id = %L', m));
  perform tb_test.check((select count(*) from app_internal.push_messages) = 1, 'zurückgenommen: ihre Zeile ist weg');
  perform tb_test.exec_as(ui, format('delete from public.friendships where addressee_id = %L', ui));
  perform tb_test.check((select count(*) from app_internal.push_messages) = 0, 'entfreundet: nichts wartet mehr');
  perform tb_test.check(tb_test.state_of(uh, 'select count(*) from app_internal.push_messages') = '42501',
                        'die Schlange ist für authenticated nicht lesbar');
end $$;

\echo -- Alle Prüfungen bestanden.
