-- Patch 036 (#615): Gezeichnete Profilavatare für bestätigte Buddys.
-- Die Profile selbst bleiben auch für offene Anfragen lesbar. Deshalb
-- steht die Konfiguration in einer eigenen Tabelle mit engerer RLS.
create table public.profile_avatars (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  config jsonb not null,
  -- Nur die V1-Katalogwerte; kein Freitext und keine Bild-URLs. IS TRUE
  -- weist auch fehlende Felder ab (ein CHECK allein lässt NULL durch).
  constraint profile_avatars_config_check check (
    case when jsonb_typeof(config) = 'object' then (
      (config - array['v', 'skin', 'hair', 'beard', 'expression', 'glasses',
                      'headwear', 'background', 'hairColor', 'gearColor']) = '{}'::jsonb
      and config->'v' = '1'::jsonb
      and config->'skin' in ('"porcelain"', '"fair"', '"warm"', '"tan"', '"brown"', '"deep"')
      and config->'hair' in ('"bald"', '"buzz"', '"short"', '"curly"', '"long"', '"braids"')
      and config->'beard' in ('"none"', '"stubble"', '"mustache"', '"full"')
      and config->'expression' in ('"smile"', '"grin"', '"focused"', '"wink"', '"laugh"')
      and config->'glasses' in ('"none"', '"clear"', '"shades"', '"goggles"')
      and config->'headwear' in ('"none"', '"trail"', '"fullface"', '"cap"', '"headband"')
      and config->'background' in ('"sand"', '"sky"', '"rose"', '"lavender"', '"slate"')
      and config->'hairColor' in ('"black"', '"brown"', '"blond"', '"auburn"', '"gray"')
      and config->'gearColor' in ('"charcoal"', '"blue"', '"red"', '"white"', '"ochre"')
    ) is true else false end
  )
);
alter table public.profile_avatars enable row level security;

create policy profile_avatars_select on public.profile_avatars for select to authenticated
  using (profile_id = (select auth.uid()) or app_internal.are_friends(profile_id, (select auth.uid())));
create policy profile_avatars_insert on public.profile_avatars for insert to authenticated
  with check (profile_id = (select auth.uid()));
create policy profile_avatars_update on public.profile_avatars for update to authenticated
  using (profile_id = (select auth.uid())) with check (profile_id = (select auth.uid()));
create policy profile_avatars_delete on public.profile_avatars for delete to authenticated
  using (profile_id = (select auth.uid()));

revoke all on table public.profile_avatars from public, anon, authenticated, service_role;
grant select, insert, update, delete on table public.profile_avatars to authenticated;
