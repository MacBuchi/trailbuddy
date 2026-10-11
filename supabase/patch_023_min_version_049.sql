-- Patch 023: minimum_supported_version 0.0.0 → 0.49.0 (#154).
--
-- Clients bis 0.48.0 lesen und schreiben trail_details.kind und
-- trail_details.status/status_at; Patch 024 und 025 entfernen beides.
-- Ohne diese Sperre bekäme ein solcher Client nach dem Entfernen nur
-- noch einen Fehler beim Laden der Trails — mit ihr sieht er „bitte
-- aktualisieren". Ab 0.49.0 liest und schreibt kein Client eine der
-- drei Spalten (kDetailsColumns und TrailDetails.toRow in v0.49.0,
-- v0.60.0, v0.82.1 nachgesehen).
--
-- Der Wert liegt unter dem stabilen Stand (0.82.1); tool/schema_check.sh
-- wacht darüber. Feldprüfung: kein Weg von der Cloud aus, die Digests
-- nennen nur 0.108.x; der Betreiber hat am 2026-10-11 entschieden, die
-- Sperre für Nachzügler auf 0.11.0/0.46.0 in Kauf zu nehmen.
--
-- Nur nach oben: ein höherer Wert, den ein späterer Patch setzt, bleibt.
set search_path = public, extensions;

update public.app_config
   set minimum_supported_version = '0.49.0', updated_at = now()
 where string_to_array(minimum_supported_version, '.')::int[] < array[0, 49, 0];
