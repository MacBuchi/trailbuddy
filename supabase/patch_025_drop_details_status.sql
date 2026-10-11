-- Patch 025: trail_details.status/status_at samt Abgleich entfernen
-- (#154, „entfernen" zu Patch 013).
--
-- Seit 0.49.0 (Patch 013, #101) steht die Meldung in `trail_reports`.
-- Für Clients bis 0.48.0 glichen zwei Trigger in beide Richtungen ab:
-- `reports_from_details` machte aus einem Status am Beitrag eine
-- Meldung, `reports_to_details` schrieb eine bestätigte Meldung an den
-- Beitrag zurück. Patch 023 sperrt diese Clients aus; damit bleibt nur
-- ein Trigger, der Spalten pflegt, die niemand liest.
--
-- Erst die Trigger, dann die Funktionen, dann die Spalten. Ein
-- Ausgangskorb-Auftrag von vor 0.49.0 auf einem Gerät geht weiter als
-- Meldung über report_trail hinaus (DetailsJob.legacyStatus) — nie über
-- diese Spalten.
set search_path = public, extensions;

drop trigger if exists trail_details_reports on public.trail_details;
drop trigger if exists trail_reports_details on public.trail_reports;
drop function if exists app_internal.reports_from_details();
drop function if exists app_internal.reports_to_details();

alter table public.trail_details drop column if exists status;
alter table public.trail_details drop column if exists status_at;
