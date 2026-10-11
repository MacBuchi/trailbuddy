-- Patch 024: trail_details.kind entfernen (#154, „entfernen" zu Patch 009).
--
-- Seit 0.34.0 (Patch 009, #72) steht der Charakter in `traits`; `kind`
-- lasen und schrieben nur noch Clients bis 0.33.0, die Patch 023
-- aussperrt. Patch 009 hat die alten Werte nach `traits` übernommen —
-- es geht nichts verloren. Kopien und Ausgangskörbe von vor 0.34.0 auf
-- einem Gerät liest `_traitsFromJson` weiter (lokale Daten, nicht diese
-- Spalte).
--
-- Keine Funktion, Sicht oder Policy nennt die Spalte; der Check fällt
-- mit ihr.
set search_path = public, extensions;

alter table public.trail_details drop column if exists kind;
