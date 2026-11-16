-- Patch 030: Gemerkte Startpunkte (#543, docs/konzept-startpunkte.md;
-- Betreiber 2026-11-16).
--
-- Ein Startpunkt ist ein benannter Punkt, den jemand bewusst anlegt — ein
-- Parkplatz, der Eingang eines Trailcenters. Name, Lage, Sichtbarkeit,
-- mehr nicht. Er gehört dem, der ihn anlegt: keine besitzerlose Kennung,
-- kein Abgleich, keine Zusammenführung (A1). Nie aus Fahrten abgeleitet
-- (A3) — er entsteht nur durch einen Tipp auf „Merken".
--
-- Sehen: der Besitzer und, wenn nicht „privat", seine DIREKTEN Buddys
-- (A2). Endet die Freundschaft, sind die Punkte sofort weg — die Regel
-- fragt are_friends bei jedem Lesen.
--
-- Schreiben: nur der Besitzer, direkt über die Tabelle. Die App kennt
-- einen Punkt unter seiner `client_id` (eindeutig je Nutzer): Anlegen,
-- Umbenennen und Umschalten sind ein Upsert auf (user_id, client_id),
-- Löschen ein Delete auf dieselbe Kennung — so ist jeder Auftrag aus dem
-- Ausgangskorb beliebig oft wiederholbar, auch für einen Punkt, der ohne
-- Netz angelegt UND umbenannt wurde.
--
-- Obergrenze 100 je Konto (Trigger, SQLSTATE 54000): schützt vor einem
-- Korb in einer Schleife. Ein Upsert auf einen VORHANDENEN Punkt zählt
-- nicht — BEFORE-INSERT-Trigger laufen auch dann, wenn der Konflikt
-- danach ein Update daraus macht, und am Limit ließe sich sonst nichts
-- mehr umbenennen.
--
-- Kontolöschung: per Cascade über profiles (delete_own_account).
set search_path = public, extensions;

create table public.start_points (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  client_id uuid not null,
  name text not null check (char_length(btrim(name)) between 1 and 60),
  lat double precision not null check (lat between -90 and 90),
  lon double precision not null check (lon between -180 and 180),
  visibility text not null default 'buddies' check (visibility in ('buddies', 'private')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint start_points_user_id_fkey foreign key (user_id)
    references public.profiles(id) on delete cascade,
  constraint start_points_client_id_key unique (user_id, client_id)
);
alter table public.start_points enable row level security;

create policy sp_select on public.start_points for select
  using (user_id = auth.uid()
     or (visibility = 'buddies' and app_internal.are_friends(user_id, auth.uid())));
create policy sp_insert_own on public.start_points for insert
  with check (user_id = auth.uid());
create policy sp_update_own on public.start_points for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
create policy sp_delete_own on public.start_points for delete
  using (user_id = auth.uid());

revoke all on public.start_points from anon, authenticated;
grant select, insert, update, delete on public.start_points to authenticated;

create trigger start_points_touch
  before update on public.start_points
  for each row execute function app_internal.touch_updated_at();

create or replace function app_internal.start_points_limit()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from start_points
       where user_id = new.user_id and client_id <> new.client_id) >= 100 then
    raise exception 'Höchstens 100 Startpunkte je Konto' using errcode = '54000';
  end if;
  return new;
end $$;
revoke all on function app_internal.start_points_limit() from public, anon, authenticated;
create trigger start_points_limit
  before insert on public.start_points
  for each row execute function app_internal.start_points_limit();
