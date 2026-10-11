-- Patch 019: Duplikate zusammenführen (#107, Rework §7; Entscheidungen
-- des Betreibers vom 2026-10-11 in #107, docs/konzept-trails.md 6.1).
--
-- Neu, alles additiv (kein Bruch für Clients ≤ 0.108):
--   - app_internal.trail_aliases  — „B ist ein Duplikat von A", je Nutzer;
--   - app_internal.trail_distinct — „das sind verschiedene", je Nutzer;
--   - public.merge_own_into(duplicate_id, target_id) — eigene
--     Aufzeichnungen, Beitrag, Hinweise und Meldungen ziehen um, nur wenn
--     der Aufrufer beide sieht und sie grob beieinander liegen (≥ 50 % der
--     kürzeren Linie innerhalb von 50 m);
--   - public.unmerge_trail, mark_distinct, unmark_distinct;
--   - public.trail_merges() — was der Aufrufer über Duplikate wissen
--     darf: eigene Zeilen, Vorschläge und stille Zuordnungen aus
--     Erklärungen direkter Buddys, Overlap-Kanten; nur Paare, die er
--     beide sieht.
-- Geändert: contribute_recording
--   - hängt eine Aufzeichnung, die der Abgleich an ein eigenes Duplikat
--     hängen würde, an den behaltenen Trail (nur nach den EIGENEN
--     Erklärungen, Entscheidung E5);
--   - vergleicht neben der Vertreterin je Trail auch mit den eigenen
--     Aufzeichnungen des Aufrufers — sonst legte die nächste Fahrt auf
--     einer umgezogenen B-Linie wieder einen eigenen Trail an. Die
--     Schwellen bleiben; auf einem einzelnen Bestand ändert es nichts
--     (#114, beste-1 = alle).
--
-- Kein Client-Grant auf die neuen Tabellen: Sie liegen in app_internal,
-- gelesen wird nur über trail_merges(), das je Leser filtert.
set search_path = public, extensions;

-- Duplikate zusammenführen (Patch 019, #107; docs/konzept-rework.md §7,
-- Entscheidungen 2026-10-11 in #107): „B ist ein Duplikat von A" ist eine
-- Aussage in MEINEM Beitrag, kein Eingriff am Trail. Eine Zeile je Nutzer
-- und Duplikat; `same_as` ist der behaltene Trail, `reversed` sagt, ob B
-- gegen A läuft (beim Erklären aus den Linien bestimmt, damit umgezogene
-- und spätere Aufzeichnungen ihre Richtung relativ zu A tragen). Eigene
-- Zeilen sind flach: Nie zeigt ein `same_as` auf ein eigenes Duplikat
-- (merge_own_into hält das ein).
--
-- In app_internal und ohne Client-Grant: Gelesen wird nur über
-- trail_merges(), das für jeden Leser filtert — Erklärungen direkter
-- Buddys nur für Paare, die er beide sieht, und nur von Buddys, die an
-- einem der beiden sichtbar beitragen (Konzept 12). Ein direkter
-- Lesezugriff zeigte Kennungen fremder Netze.
create table app_internal.trail_aliases (
  user_id uuid not null references public.profiles(id) on delete cascade,
  trail_id uuid not null references public.trails(id) on delete cascade,
  same_as uuid not null references public.trails(id) on delete cascade,
  reversed boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (user_id, trail_id),
  check (trail_id <> same_as)
);
create index trail_aliases_trail_idx on app_internal.trail_aliases (trail_id);
create index trail_aliases_same_as_idx on app_internal.trail_aliases (same_as);

-- „Das sind verschiedene Trails" (Patch 019): gemerkt je Nutzer, damit ein
-- Vorschlag nicht wiederkommt. Das Paar steht geordnet (a < b). Sagt es
-- ein Buddy, der an einem der beiden beiträgt, hält es das Duplikat für
-- Unbeteiligte stehen: Wer den Trail gefahren ist, zählt mehr als eine
-- fremde Zusammenführung (Betreiber, 2026-10-11).
create table app_internal.trail_distinct (
  user_id uuid not null references public.profiles(id) on delete cascade,
  a uuid not null references public.trails(id) on delete cascade,
  b uuid not null references public.trails(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, a, b),
  check (a < b)
);
create index trail_distinct_pair_idx on app_internal.trail_distinct (a, b);

alter table app_internal.trail_aliases enable row level security;
alter table app_internal.trail_distinct enable row level security;
-- Ausdrücklich gesperrt wie trail_overlaps (Grund dort): Nur Definer-RPCs
-- lesen und schreiben, sie umgehen die RLS als Eigentümer.
create policy trail_aliases_no_client on app_internal.trail_aliases
  for all to anon, authenticated using (false) with check (false);
create policy trail_distinct_no_client on app_internal.trail_distinct
  for all to anon, authenticated using (false) with check (false);
revoke all on app_internal.trail_aliases from anon, authenticated;
revoke all on app_internal.trail_distinct from anon, authenticated;

-- ============================================================
-- Duplikate zusammenführen (Patch 019, #107)
-- ============================================================
-- Die Regel (docs/konzept-trails.md 6.1, Entscheidungen 2026-10-11):
-- Zusammenführen ist eine Aussage in MEINEM Beitrag. Meine Aufzeichnungen,
-- mein Beitrag, meine Hinweise und Meldungen ziehen von B nach A; für die
-- Beiträge anderer an B steht meine Zuordnung B → A. Weitergereicht wird
-- sie an direkte Buddys, die beide Trails sehen: Wer an B selbst etwas
-- hat, bekommt einen Vorschlag; wer an B nichts hat, sieht B einfach
-- unter A. Wer nicht beide sieht, erfährt nichts.

-- Trägt [person] an [trail] sichtbar bei? Eine Aufzeichnung, deren
-- Beitrag nicht privat ist — dieselbe Bedingung, unter der ein Buddy sie
-- sieht. Ein privater Beitrag gibt keine Erklärung weiter, sonst verriete
-- sie, dass es ihn gibt.
create or replace function app_internal.shares_on(person uuid, trail uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from trail_recordings r
                  where r.trail_id = trail and r.user_id = person)
     and app_internal.contributor_shares(person, trail);
$$;
revoke all on function app_internal.shares_on(uuid, uuid) from public, anon, authenticated;

-- Hat [uid] an [trail] einen eigenen Beitrag (Aufzeichnung oder Beitrag,
-- auch privat)? Entscheidet, ob eine fremde Erklärung bei ihm Vorschlag
-- oder stille Zuordnung ist.
create or replace function app_internal.owns_contribution(uid uuid, trail uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from trail_recordings r where r.trail_id = trail and r.user_id = uid)
      or exists (select 1 from trail_details d where d.trail_id = trail and d.user_id = uid);
$$;
revoke all on function app_internal.owns_contribution(uuid, uuid) from public, anon, authenticated;

-- Die beste Aufzeichnung von [trail], die [uid] sieht — dieselbe Wahl wie
-- im Client (höchste Qualität, dann die ältere), metrisch erst beim
-- Vergleich.
create or replace function app_internal.visible_line(uid uuid, trail uuid)
returns table (geom geometry, reversed boolean)
language sql stable security definer set search_path = public, extensions as $$
  select r.geom::geometry, r.reversed
    from trail_recordings r
   where r.trail_id = trail
     and (r.user_id = uid
       or (app_internal.are_friends(r.user_id, uid)
           and app_internal.contributor_shares(r.user_id, trail)))
   order by r.quality desc, r.created_at asc
   limit 1;
$$;
revoke all on function app_internal.visible_line(uuid, uuid) from public, anon, authenticated;

-- „Grob beieinander" (Betreiber, 2026-10-11): Mindestens die Hälfte der
-- kürzeren Linie liegt höchstens 50 m neben der anderen. Bewusst weiter
-- als der 15-m-Korridor des Abgleichs — genau die Paare knapp daneben
-- sollen sich zusammenführen lassen; eine Linie, die durchgehend 20 m
-- parallel läuft, hätte im Korridor die Deckung null. Beide Zahlen sind
-- geschätzt, nicht gemessen; der Client rechnet dieselben für seine
-- Auswahl (lib/features/trails/CLAUDE.md). Die Richtung kommt aus der
-- Reihenfolge der Fußpunkte wie in match_lines; ohne klare Aussage gilt
-- „gleiche Richtung". Beide Linien schon metrisch, gleiche SRID.
create type app_internal.near_result as (
  near boolean,
  share real,
  reversed boolean
);
create or replace function app_internal.merge_near(a geometry, b geometry)
returns app_internal.near_result
language plpgsql stable set search_path = public, extensions as $$
declare
  near_m constant double precision := 50;
  near_share constant double precision := 0.5;
  p app_internal.match_params := app_internal.match_params();
  short geometry;
  other geometry;
  pts geometry[];
  share double precision;
  ups integer;
  diffs integer;
  rev boolean := false;
begin
  if st_length(a) <= st_length(b) then
    short := a; other := b;
  else
    short := b; other := a;
  end if;
  pts := app_internal.resample(short, p.step_m);
  select count(*) filter (where st_dwithin(s, other, near_m))::double precision / count(*)
    into share from unnest(pts) s;
  with near as (
    select o, st_linelocatepoint(other, s) as frac
      from unnest(pts) with ordinality t(s, o)
     where st_dwithin(s, other, near_m)
  ), steps as (
    select frac - lag(frac) over (order by o) as df from near
  )
  select count(*) filter (where df > 0), count(*)
    into ups, diffs from steps where df is not null and df <> 0;
  if diffs >= 3 and ups::double precision / diffs <= p.direction_reversed then
    rev := true;
  end if;
  return row(share >= near_share, share::real, rev)::app_internal.near_result;
end $$;
revoke all on function app_internal.merge_near(geometry, geometry) from public, anon, authenticated;

-- „[duplicate_id] ist ein Duplikat von [target_id]" — für mich. Prüft,
-- dass der Aufrufer BEIDE sieht und dass sie grob beieinander liegen,
-- dann in EINER Transaktion:
--   1. meine Aufzeichnungen ziehen um, ihre Richtung relativ zu A;
--   2. mein Beitrag verschmilzt: A gewinnt, leere Felder füllt B, privat
--      gewinnt (sonst läge eine private Aufzeichnung von B offen an A);
--   3. meine Hinweise und Meldungen ziehen um;
--   4. meine Zuordnung B → A, eigene Ketten (X → B) zeigen auf A;
--   5. ein eigenes „verschieden" für das Paar fällt weg.
-- Hat der Aufrufer A selbst schon als Duplikat erklärt, gilt dessen Ziel.
-- Ein zweiter Aufruf mit derselben Erklärung (Ausgangskorb) antwortet mit
-- dem Ziel, ohne zu prüfen: B kann nach dem ersten unsichtbar sein. Gibt
-- den behaltenen Trail zurück. B selbst bleibt, solange jemand anderes
-- daran etwas hat; sonst holt ihn sweep_orphan_trails.
create or replace function public.merge_own_into(duplicate_id uuid, target_id uuid)
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid := auth.uid();
  target uuid := merge_own_into.target_id;
  dup uuid := merge_own_into.duplicate_id;
  hop record;
  la record;
  lb record;
  srid integer;
  near app_internal.near_result;
  flip boolean;
  da trail_details%rowtype;
  db trail_details%rowtype;
begin
  if uid is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  if dup is null or target is null or dup = target then
    raise exception 'Zwei verschiedene Trails erwartet' using errcode = '22023';
  end if;
  select a.same_as into hop
    from app_internal.trail_aliases a
   where a.user_id = uid and a.trail_id = dup;
  if found then
    return hop.same_as;
  end if;
  -- Ziel selbst schon zugeordnet ⇒ dessen Ziel (eigene Zeilen sind flach).
  select a.same_as, a.reversed into hop
    from app_internal.trail_aliases a
   where a.user_id = uid and a.trail_id = target;
  if found then
    target := hop.same_as;
    if target = dup then
      raise exception 'Zwei verschiedene Trails erwartet' using errcode = '22023';
    end if;
  end if;
  -- Dieselbe Antwort für „gibt es nicht" und „siehst du nicht" (4.6).
  if not (app_internal.can_see_trail(uid, dup) and app_internal.can_see_trail(uid, target)) then
    raise exception 'Trail nicht gefunden' using errcode = 'P0002';
  end if;

  select * into la from app_internal.visible_line(uid, target);
  select * into lb from app_internal.visible_line(uid, dup);
  srid := app_internal.utm_srid(la.geom);
  near := app_internal.merge_near(st_transform(lb.geom, srid), st_transform(la.geom, srid));
  if not near.near then
    raise exception 'Die beiden Trails liegen nicht nah genug beieinander (% %% der kürzeren Linie innerhalb von 50 m)',
      round(near.share * 100) using errcode = '22023';
  end if;
  -- Richtung von B relativ zu A: die der Linien, korrigiert um die
  -- Richtung jeder Vertreterin zu ihrem Trail.
  flip := (near.reversed <> lb.reversed) <> la.reversed;

  -- 1. Aufzeichnungen.
  update trail_recordings r
     set trail_id = target, reversed = r.reversed <> flip
   where r.user_id = uid and r.trail_id = dup;

  -- 2. Beitrag.
  select * into db from trail_details d where d.trail_id = dup and d.user_id = uid;
  if found then
    select * into da from trail_details d where d.trail_id = target and d.user_id = uid;
    if found then
      update trail_details d
         set name = coalesce(da.name, db.name),
             description = coalesce(da.description, db.description),
             grade = coalesce(da.grade, db.grade),
             traits = case when cardinality(da.traits) = 0 then db.traits else da.traits end,
             rating = coalesce(da.rating, db.rating),
             link = coalesce(da.link, db.link),
             two_way = da.two_way or db.two_way,
             visibility = case when 'private' in (da.visibility, db.visibility) then 'private' else 'buddies' end
       where d.trail_id = target and d.user_id = uid;
      delete from trail_details d where d.trail_id = dup and d.user_id = uid;
    else
      update trail_details d set trail_id = target
       where d.trail_id = dup and d.user_id = uid;
    end if;
  end if;

  -- 3. Hinweise und Meldungen (Trigger hängen nur am Insert: kein Push,
  -- kein zweiter Abgleich mit dem Beitrag).
  update trail_notes n set trail_id = target where n.user_id = uid and n.trail_id = dup;
  update trail_reports m set trail_id = target where m.user_id = uid and m.trail_id = dup;

  -- 4. Zuordnungen: eigene Ketten X → B zeigen jetzt auf A.
  update app_internal.trail_aliases a
     set same_as = target, reversed = a.reversed <> flip
   where a.user_id = uid and a.same_as = dup;
  insert into app_internal.trail_aliases (user_id, trail_id, same_as, reversed)
  values (uid, dup, target, flip);

  -- 5. Ein eigenes „verschieden" widerspräche der Erklärung.
  delete from app_internal.trail_distinct d
   where d.user_id = uid and d.a = least(dup, target) and d.b = greatest(dup, target);
  return target;
end $$;
revoke all on function public.merge_own_into(uuid, uuid) from public, anon;
grant execute on function public.merge_own_into(uuid, uuid) to authenticated;

-- Die eigene Zuordnung lösen. B erscheint wieder, wo jemand anderes etwas
-- daran hat; umgezogene eigene Aufzeichnungen bleiben bei A (Rework §7).
create or replace function public.unmerge_trail(duplicate_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  delete from app_internal.trail_aliases a
   where a.user_id = uid and a.trail_id = unmerge_trail.duplicate_id;
end $$;
revoke all on function public.unmerge_trail(uuid) from public, anon;
grant execute on function public.unmerge_trail(uuid) to authenticated;

-- „Das sind verschiedene Trails" — für zwei Trails, die der Aufrufer
-- beide sieht. Hebt eine eigene Zuordnung zwischen ihnen auf (in beide
-- Richtungen); idempotent.
create or replace function public.mark_distinct(trail_a uuid, trail_b uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  if trail_a is null or trail_b is null or trail_a = trail_b then
    raise exception 'Zwei verschiedene Trails erwartet' using errcode = '22023';
  end if;
  if not (app_internal.can_see_trail(uid, trail_a) and app_internal.can_see_trail(uid, trail_b)) then
    raise exception 'Trail nicht gefunden' using errcode = 'P0002';
  end if;
  insert into app_internal.trail_distinct (user_id, a, b)
  values (uid, least(trail_a, trail_b), greatest(trail_a, trail_b))
  on conflict do nothing;
  delete from app_internal.trail_aliases x
   where x.user_id = uid
     and ((x.trail_id = trail_a and x.same_as = trail_b)
       or (x.trail_id = trail_b and x.same_as = trail_a));
end $$;
revoke all on function public.mark_distinct(uuid, uuid) from public, anon;
grant execute on function public.mark_distinct(uuid, uuid) to authenticated;

-- „Verschieden" zurücknehmen.
create or replace function public.unmark_distinct(trail_a uuid, trail_b uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  delete from app_internal.trail_distinct d
   where d.user_id = uid and d.a = least(trail_a, trail_b) and d.b = greatest(trail_a, trail_b);
end $$;
revoke all on function public.unmark_distinct(uuid, uuid) from public, anon;
grant execute on function public.unmark_distinct(uuid, uuid) to authenticated;

-- Was der Aufrufer über Duplikate wissen darf, eine Zeile je Paar, NUR
-- für Paare, die er beide sieht:
--   own      — seine Zuordnung trail_id → same_as;
--   distinct — sein „verschieden" (trail_id < same_as);
--   proposed — direkte Buddys halten trail_id für ein Duplikat von
--              same_as, und er hat an trail_id selbst etwas: Er
--              entscheidet (by_users: wer es sagt);
--   folded   — dasselbe, aber er hat an trail_id nichts: trail_id
--              erscheint bei ihm unter same_as, ohne Frage — es sei
--              denn, ein direkter Buddy, der an einem der beiden
--              beiträgt, hat „verschieden" gesagt;
--   overlap  — eine Kante aus dem Abgleich (Teil, Gabel) zwischen zwei
--              sichtbaren Trails, von denen er einen selbst hat: Vorrat
--              für „Sind das dieselben?" (Konzept 4.4). Ohne Deckung —
--              die gilt der Linie, gegen die damals verglichen wurde,
--              und die kann fremd sein; der Client rechnet selbst.
-- Es zählen nur Erklärungen direkter Buddys, die an einem der beiden
-- Trails sichtbar beitragen — eine private Zeile verrät nichts.
-- Gegenrichtungen und Ketten löst der Client auf (der ältere Trail
-- gewinnt), seine eigenen Zeilen zuerst.
create or replace function public.trail_merges()
returns table (trail_id uuid, same_as uuid, reversed boolean, kind text, by_users uuid[])
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  return query
  with seen as (
    select distinct r.trail_id as id
      from trail_recordings r
     where r.user_id = uid
        or (app_internal.are_friends(r.user_id, uid)
            and app_internal.contributor_shares(r.user_id, r.trail_id))
  ), buddies as (
    select case when f.requester_id = uid then f.addressee_id else f.requester_id end as id
      from friendships f
     where f.status = 'accepted' and uid in (f.requester_id, f.addressee_id)
  ), own as (
    select a.trail_id, a.same_as, a.reversed
      from app_internal.trail_aliases a
     where a.user_id = uid
       and a.trail_id in (select id from seen) and a.same_as in (select id from seen)
  ), own_distinct as (
    select d.a, d.b
      from app_internal.trail_distinct d
     where d.user_id = uid
       and d.a in (select id from seen) and d.b in (select id from seen)
  ), claims as (
    select a.trail_id, a.same_as, a.reversed, a.user_id, a.created_at
      from app_internal.trail_aliases a
      join buddies b on b.id = a.user_id
     where a.trail_id in (select id from seen) and a.same_as in (select id from seen)
       and (app_internal.shares_on(a.user_id, a.trail_id)
         or app_internal.shares_on(a.user_id, a.same_as))
       and not exists (select 1 from own o
                        where o.trail_id = a.trail_id
                           or (o.trail_id = a.same_as and o.same_as = a.trail_id))
       and not exists (select 1 from own_distinct d
                        where d.a = least(a.trail_id, a.same_as)
                          and d.b = greatest(a.trail_id, a.same_as))
  ), vetoes as (
    select d.a, d.b
      from app_internal.trail_distinct d
      join buddies b on b.id = d.user_id
     where app_internal.shares_on(d.user_id, d.a) or app_internal.shares_on(d.user_id, d.b)
  ), judged as (
    select c.trail_id, c.same_as,
           (array_agg(c.reversed order by c.created_at))[1] as reversed,
           case when app_internal.owns_contribution(uid, c.trail_id) then 'proposed' else 'folded' end as kind,
           array_agg(c.user_id order by c.created_at) as by_users
      from claims c
     group by c.trail_id, c.same_as
  )
  select o.trail_id, o.same_as, o.reversed, 'own'::text, null::uuid[] from own o
  union all
  select d.a, d.b, null::boolean, 'distinct'::text, null::uuid[] from own_distinct d
  union all
  select j.trail_id, j.same_as, j.reversed, j.kind, j.by_users
    from judged j
   where j.kind = 'proposed'
      or not exists (select 1 from vetoes v
                      where v.a = least(j.trail_id, j.same_as)
                        and v.b = greatest(j.trail_id, j.same_as))
  union all
  select o.a, o.b, null::boolean, 'overlap'::text, null::uuid[]
    from app_internal.trail_overlaps o
   where o.a in (select id from seen) and o.b in (select id from seen)
     and (app_internal.owns_contribution(uid, o.a) or app_internal.owns_contribution(uid, o.b))
     and not exists (select 1 from own x
                      where (x.trail_id = o.a and x.same_as = o.b)
                         or (x.trail_id = o.b and x.same_as = o.a))
     and not exists (select 1 from own_distinct d
                      where d.a = least(o.a, o.b) and d.b = greatest(o.a, o.b));
end $$;
revoke all on function public.trail_merges() from public, anon;
grant execute on function public.trail_merges() to authenticated;

-- Der EINE Schreibweg für Aufzeichnungen (Abschnitt 4.1). Der Client kann
-- nicht gegen fremde Trails vergleichen, weil er sie nicht sehen darf —
-- also tut es die Datenbank, als Definer. Zurück kommt NUR die
-- Trail-Kennung; ob sie neu ist, sagt die Funktion nicht (4.6).
--
-- coords: flache Liste [lon1, lat1, lon2, lat2, …] in WGS84 — die
-- einfachste Form, die sich aus Dart als JSON-Array übergeben lässt.
--
-- Ablauf:
--   1. Angemeldet? Quelle bekannt? Mindestens zwei Punkte? Länge ≥ 50 m?
--      Tageslimit (4.6)? Sonst Ausnahme mit klarem Text.
--   2. Idempotenz: (user_id, client_id) schon da ⇒ dessen trail_id.
--   3. Vorfilter (GiST): Trails, deren Aufzeichnungen dem Kandidaten
--      näher als der Korridor kommen. Je Trail EINE Vertreterin — die
--      Aufzeichnung mit der höchsten Qualität (4.5: keine gemittelte
--      Linie) —, dazu die eigenen Aufzeichnungen des Aufrufers (Patch
--      019).
--   4. match_lines je Vertreterin. Nur „gleich" hängt an (4.4, v1
--      bewusst konservativ) — bei mehreren Treffern der mit der höchsten
--      beidseitigen Deckung. „gleich-gegen" heißt reversed, RELATIV zur
--      Vertreterin: War die selbst gegen die Trail-Richtung unterwegs,
--      dreht sich das Vorzeichen (XOR).
--   5. Sonst neuer Trail, und je Nachbar mit Deckung ≥ 0,3 in einer
--      Richtung eine Kante in trail_overlaps (Teil, Enthält, Gabel,
--      Nachbar). Hat der AUFRUFER den gefundenen Trail selbst als
--      Duplikat erklärt (trail_aliases, Patch 019, #107), landet die
--      Aufzeichnung gleich am behaltenen Trail — nach seinen eigenen
--      Erklärungen, nie nach fremden (Entscheidung E5).
--   6. Aufzeichnung schreiben. Qualität vorerst nur aus der Quelle
--      (0,6 app / 0,4 import / 0,1 planned): Genauigkeit je Punkt und
--      Lückenprüfung (4.5) kommen, sobald der Client sie mitschickt —
--      dann als weiterer Parameter, nicht als andere Zahl hier.
--   7. Beitrag des Aufrufers anlegen, falls er fehlt.
--   8. Seine Meldung auf „offen" setzen — wer den Trail fährt, hat ihn
--      befahrbar vorgefunden (Abschnitt 3, Entscheidung 6), zum
--      Fahrdatum (Patch 013). Nicht bei `planned` (Patch 011, #100):
--      Eine Datei ohne Fahrzeiten belegt nicht, dass jemand den Trail
--      befahrbar vorgefunden hat — es sei denn, er hat das Fahrdatum
--      eingetragen (`recorded_at`, Patch 015, #120).
create or replace function public.contribute_recording(
  coords double precision[],
  source text,
  recorded_at timestamptz default null,
  client_id uuid default null,
  -- Eine Höhe je Punkt aus `coords`, oder null (Patch 002). Mit Vorgabe,
  -- damit Clients vor 0.3.0 dieselbe Funktion ohne den Namen treffen.
  eles double precision[] default null)
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  p app_internal.match_params := app_internal.match_params();
  uid uuid := auth.uid();
  npts integer;
  line geometry;
  geog geography;
  len double precision;
  srid integer;
  cand geometry;
  existing uuid;
  best_trail uuid;
  best_cov double precision := -1;
  best_reversed boolean := false;
  rec record;
  res app_internal.match_result;
  ov_trails uuid[] := '{}';
  ov_ab real[] := '{}';
  ov_ba real[] := '{}';
  target uuid;
  q real;
  ele_clean real[];
  ride_at timestamptz;
  last_report record;
  alias record;
begin
  if uid is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  if source is null or source not in ('app', 'import', 'planned') then
    raise exception 'Unbekannte Quelle: %', coalesce(source, 'null')
      using errcode = '22023', hint = 'app, import oder planned';
  end if;
  npts := coalesce(array_length(coords, 1), 0);
  if npts < 4 or npts % 2 <> 0 then
    raise exception 'Mindestens zwei Punkte als [lon, lat, lon, lat, …] erwartet'
      using errcode = '22023';
  end if;
  if exists (select 1 from generate_series(1, npts / 2) i
              where coords[2 * i - 1] not between -180 and 180
                 or coords[2 * i] not between -90 and 90) then
    raise exception 'Koordinate außerhalb von WGS84 (lon ±180, lat ±90)'
      using errcode = '22023';
  end if;
  -- Höhen: eine je Punkt oder gar keine. Die App schickt null, sobald
  -- einem Punkt die Höhe fehlt; hier wird nur noch geprüft, nicht geraten.
  if eles is not null then
    if coalesce(array_length(eles, 1), 0) <> npts / 2 then
      raise exception 'Höhen: % Werte für % Punkte', coalesce(array_length(eles, 1), 0), npts / 2
        using errcode = '22023';
    end if;
    if array_position(eles, null) is not null
       or exists (select 1 from unnest(eles) e where e not between -500 and 9000) then
      raise exception 'Höhe fehlt oder liegt außerhalb von −500 bis 9000 m'
        using errcode = '22023';
    end if;
  end if;

  -- 2. Idempotenz (Ausgangskorb): derselbe Auftrag noch einmal ⇒ dieselbe
  -- Antwort, keine zweite Aufzeichnung.
  if contribute_recording.client_id is not null then
    select r.trail_id into existing
      from trail_recordings r
     where r.user_id = uid and r.client_id = contribute_recording.client_id;
    if found then
      return existing;
    end if;
  end if;

  -- Rate (4.6): reicht jedem echten Nutzer, auch für einen Bestandsimport
  -- an einem Abend, und macht das Sondieren als Fläche unattraktiv.
  if (select count(*) from trail_recordings r
       where r.user_id = uid and r.created_at > now() - interval '1 day') >= p.daily_limit then
    raise exception 'Tageslimit von % Aufzeichnungen erreicht', p.daily_limit
      using errcode = '54000';
  end if;

  -- Doppelte Punkte fallen weg (Locus schreibt sie an Pausen) — samt
  -- ihrer Höhe. Bis Patch 002 stand hier st_removerepeatedpoints; das
  -- kürzt nur die Linie, und die Höhen liefen danach um einen Punkt
  -- versetzt neben ihr her.
  select st_setsrid(st_makeline(array_agg(st_makepoint(d.x, d.y) order by d.i)), 4326),
         case when eles is null then null else array_agg(d.z::real order by d.i) end
    into line, ele_clean
    from (
      select r.i, r.x, r.y, r.z,
             lag(r.x) over (order by r.i) as px, lag(r.y) over (order by r.i) as py
        from (select g.i, coords[2 * g.i - 1] as x, coords[2 * g.i] as y, eles[g.i] as z
                from generate_series(1, npts / 2) as g(i)) r
    ) d
   where d.px is null or d.x <> d.px or d.y <> d.py;
  if st_npoints(line) < 2 then
    raise exception 'Mindestens zwei verschiedene Punkte erwartet' using errcode = '22023';
  end if;
  geog := line::geography;
  len := st_length(geog);
  if len < p.min_trail_m then
    raise exception 'Aufzeichnung zu kurz: % m, ein Trail hat mindestens % m',
      round(len), p.min_trail_m::integer using errcode = '22023';
  end if;

  -- 3./4. Abgleich gegen die Vertreterinnen aller Trails in Reichweite.
  srid := app_internal.utm_srid(line);
  cand := st_transform(line, srid);
  -- Dazu jede EIGENE Aufzeichnung in Reichweite (Patch 019): Nach dem
  -- Zusammenführen eigener Duplikate hängt die B-Linie an A, ist dort
  -- aber nicht die Vertreterin — ohne sie legte die nächste Fahrt auf
  -- der B-Linie wieder einen eigenen Trail an. Eigene Linien verraten
  -- nichts; auf einem einzelnen Bestand ändert es nichts (#114: beste-1
  -- = alle, 453 Trails).
  for rec in
    with near as (
      select distinct r.trail_id
        from trail_recordings r
       where st_dwithin(r.geom, geog, p.corridor_m)
    )
    select n.trail_id, b.geom, b.reversed
      from near n
      cross join lateral (
        select r.geom, r.reversed
          from trail_recordings r
         where r.trail_id = n.trail_id
         order by r.quality desc, r.created_at asc
         limit 1) b
    union all
    select r.trail_id, r.geom, r.reversed
      from trail_recordings r
     where r.user_id = uid and st_dwithin(r.geom, geog, p.corridor_m)
  loop
    res := app_internal.match_lines(cand, st_transform(rec.geom::geometry, srid));
    if res.class in ('same', 'same-reversed') then
      if least(res.cov_ab, res.cov_ba) > best_cov then
        best_trail := rec.trail_id;
        best_cov := least(res.cov_ab, res.cov_ba);
        best_reversed := (res.class = 'same-reversed') <> rec.reversed;
      end if;
    elsif greatest(res.cov_ab, res.cov_ba) >= p.overlap_min
          and not rec.trail_id = any(ov_trails) then
      ov_trails := ov_trails || rec.trail_id;
      ov_ab := ov_ab || res.cov_ab;
      ov_ba := ov_ba || res.cov_ba;
    end if;
  end loop;

  -- 5. Anhängen oder neu — nur „gleich" verschmilzt.
  if best_trail is not null then
    target := best_trail;
    -- Eigene Erklärung „das ist ein Duplikat von …" (Patch 019): Die
    -- Fahrt gehört dorthin, wo der Fahrer den Trail führt. Eigene
    -- Zuordnungen sind flach (merge_own_into), ein Schritt genügt;
    -- `reversed` sagt, ob der Duplikat-Trail gegen den behaltenen läuft.
    select a.same_as, a.reversed into alias
      from app_internal.trail_aliases a
     where a.user_id = uid and a.trail_id = best_trail;
    if found then
      target := alias.same_as;
      best_reversed := best_reversed <> alias.reversed;
    end if;
  else
    insert into trails default values returning id into target;
    insert into app_internal.trail_overlaps (a, b, coverage_ab, coverage_ba)
      select target, t, ab, ba
        from unnest(ov_trails, ov_ab, ov_ba) as u(t, ab, ba);
  end if;

  -- 6. Die Aufzeichnung.
  q := case source when 'app' then 0.6 when 'import' then 0.4 else 0.1 end;
  begin
    insert into trail_recordings
      (trail_id, user_id, geom, recorded_at, source, reversed, quality, client_id, ele)
    values
      (target, uid, geog, recorded_at, source, best_reversed, q, contribute_recording.client_id, ele_clean);
  exception when unique_violation then
    -- Wettlauf zweier Wiedervorlagen desselben Auftrags: Die erste hat
    -- gewonnen, ihre Antwort gilt. Ein eben angelegter leerer Trail geht
    -- wieder weg.
    if best_trail is null then
      delete from trails where id = target;
    end if;
    select r.trail_id into existing
      from trail_recordings r
     where r.user_id = uid and r.client_id = contribute_recording.client_id;
    return existing;
  end;

  -- 7. Der Beitrag, falls er fehlt.
  insert into trail_details (trail_id, user_id)
  values (target, uid)
  on conflict (trail_id, user_id) do nothing;

  -- 8. Die eigene Meldung auf „offen" (Patch 013; bis dahin der Status
  -- am Beitrag): Wer den Trail fährt, hat ihn befahrbar vorgefunden —
  -- und zwar AN DEM TAG, an dem er gefahren ist. Eine GPX-Datei von 2024
  -- verdrängt keine Meldung von gestern (Betreiber, 2026-09-30). Nur
  -- wenn der Aufrufer schon etwas gemeldet hat und das nicht schon ein
  -- bestätigtes „offen" ist; nicht bei `planned` (Patch 011) — außer
  -- mit eingetragenem Fahrdatum (Patch 015, #120).
  if contribute_recording.source <> 'planned' or contribute_recording.recorded_at is not null then
    ride_at := least(coalesce(contribute_recording.recorded_at, now()), now());
    select r.status, r.confirmed, r.reported_at into last_report
      from trail_reports r
     where r.trail_id = target and r.user_id = uid and r.kind = 'status'
     order by r.reported_at desc, r.created_at desc
     limit 1;
    if found and ride_at > last_report.reported_at
       and not (last_report.status = 'open' and last_report.confirmed) then
      perform app_internal.put_report(uid, target, 'status', 'open', null, true, ride_at, null);
    end if;
  end if;

  return target;
end $$;

-- Nur für Angemeldete. anon hätte die Funktion sonst über
-- /rest/v1/rpc/contribute_recording (Default-Grant an PUBLIC).
revoke all on function public.contribute_recording(double precision[], text, timestamptz, uuid, double precision[])
  from public, anon;
grant execute on function public.contribute_recording(double precision[], text, timestamptz, uuid, double precision[])
  to authenticated;
