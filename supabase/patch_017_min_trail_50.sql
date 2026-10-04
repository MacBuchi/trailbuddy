-- Patch 017: Mindestlänge eines Trails 150 → 50 m.
--
-- 150 m schnitten kurze Stücke ab, die echte Trails sind — eine
-- Jump-Line, ein Northshore-Stück, eine kurze Steilpassage zwischen zwei
-- Forstwegen. Die Messung (docs/trail-abgleich-messung.md) nannte 150 m
-- „eher zu niedrig als zu hoch" mit Blick auf Fragmente; der Betreiber
-- hat am 2026-10-04 entschieden: Trails ab 50 m. Ein Fragment mit dem
-- Namen eines echten Trails (das kürzeste im Bestand: 13 m) bleibt
-- darunter.
--
-- Nur die eine Zahl; alles andere wie in schema.sql. Kein Bruch: Ältere
-- Clients lehnen 50–150 m weiter auf dem Gerät ab, der Server nimmt
-- mehr an als vorher.
set search_path = public, extensions;

create or replace function app_internal.match_params()
returns app_internal.match_params
language sql immutable set search_path = '' as $$
  select row(15.0, 0.8, 2.0, 50.0, 5.0, 400, 0.3, 0.7, 0.3, 500)::app_internal.match_params;
$$;
