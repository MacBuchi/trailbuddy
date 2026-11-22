-- Patch 038: Optionaler Glas-Ton für die Goggles. Ohne Feld gilt verspiegelt.
alter table public.profile_avatars
  drop constraint profile_avatars_config_check,
  add constraint profile_avatars_config_check check (
    case when jsonb_typeof(config) = 'object' then (
      (config - array['v', 'skin', 'hair', 'beard', 'expression', 'glasses',
                      'headwear', 'background', 'hairColor', 'gearColor', 'goggleTint']) = '{}'::jsonb
      and config->'v' = '1'::jsonb
      and config->'skin' in ('"porcelain"', '"fair"', '"warm"', '"tan"', '"brown"', '"deep"')
      and config->'hair' in ('"bald"', '"buzz"', '"short"', '"curly"', '"long"', '"braids"',
                             '"sidePart"', '"undercut"', '"fringe"', '"bun"', '"ponytail"', '"mohawk"')
      and config->'beard' in ('"none"', '"stubble"', '"mustache"', '"full"',
                             '"goatee"', '"handlebar"', '"shortBoxed"', '"long"', '"chinstrap"')
      and config->'expression' in ('"smile"', '"grin"', '"focused"', '"wink"', '"laugh"')
      and config->'glasses' in ('"none"', '"clear"', '"shades"', '"goggles"')
      and config->'headwear' in ('"none"', '"trail"', '"fullface"', '"cap"', '"headband"')
      and config->'background' in ('"sand"', '"sky"', '"rose"', '"lavender"', '"slate"')
      and config->'hairColor' in ('"black"', '"brown"', '"blond"', '"auburn"', '"gray"')
      and (not (config ? 'goggleTint')
           or config->'goggleTint' in ('"clear"', '"smoke"', '"mirrored"'))
      and config->'gearColor' in ('"charcoal"', '"blue"', '"red"', '"white"', '"ochre"')
    ) is true else false end
  );
