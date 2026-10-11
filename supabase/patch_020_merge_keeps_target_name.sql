-- Patch 020: Beim Zusammenführen gilt der Name des behaltenen Trails
-- (#107 Schritt 3; Betreiber 2026-10-11: „A's name and grade win, empty
-- fields are filled from B").
--
-- Patch 019 zog meinen Beitrag von B samt Namen nach A, wenn ich an A
-- noch keinen hatte — und weil der eigene Name in der Anzeige vor jedem
-- anderen steht, hieß A bei mir danach wieder wie B. Ebenso füllte ein
-- eigener, aber unbenannter Beitrag an A seinen Namen aus B. Jetzt:
--   - mein Name an A bleibt, wenn es einen gibt;
--   - sonst fällt der Name von B weg, wenn A für mich schon einen Namen
--     trägt (eigener Beitrag oder der eines direkten Buddys, den ich sehe);
--   - nur wenn A für mich namenlos ist, füllt ihn B.
-- S-Grad, Charakter, Sterne, Link und „beide Richtungen" bleiben, wie
-- Patch 019 sie zusammenführt — das ist meine Einschätzung, kein Name.
--
-- Ersetzt nur die Funktion (Signatur und Rechte gleich) und legt eine
-- Hilfsfunktion in app_internal an, ohne Client-Grant. Additiv: Clients
-- bis 0.109 rufen dieselbe RPC.
set search_path = public, extensions;

-- Trägt [trail] für [uid] schon einen Namen aus einem Beitrag, den er
-- sieht — einem eigenen oder dem eines direkten Buddys, der nicht privat
-- ist (dieselbe Regel wie `td_friend_select`)? Dann gilt beim
-- Zusammenführen dieser Name, nicht der des Duplikats (Patch 020).
create or replace function app_internal.named_for(uid uuid, trail uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from trail_details d
     where d.trail_id = trail
       and nullif(btrim(d.name), '') is not null
       and (d.user_id = uid
         or (d.visibility = 'buddies' and app_internal.are_friends(d.user_id, uid))));
$$;
revoke all on function app_internal.named_for(uuid, uuid) from public, anon, authenticated;

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
         set name = case
               when nullif(btrim(da.name), '') is not null then da.name
               when app_internal.named_for(uid, target) then null
               else db.name
             end,
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
      update trail_details d
         set trail_id = target,
             name = case when app_internal.named_for(uid, target) then null else d.name end
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
