-- Patch 018: Feedback bekommt eine Auftragskennung (#218).
--
-- Feedback ohne Empfang geht seit 0.86.0 in den Ausgangskorb und wird
-- nachgeholt. Der Korb legt jeden Auftrag mit seiner Kennung an, BEVOR er
-- das erste Mal sendet (lib/data/CLAUDE.md, „Ausgangskorb"): Reißt die
-- Antwort nach dem Insert ab, schickt die Wiedervorlage dieselbe Kennung
-- noch einmal, und der Server antwortet mit 23505 statt eine zweite Zeile
-- anzulegen — sonst stünde derselbe Wunsch zweimal als öffentliches Issue
-- da. Die App liest 23505 als „stand schon".
--
-- Nullable: Ältere Clients senden keine Kennung, und `unique` lässt
-- beliebig viele NULL zu. Kein Bruch, kein neuer Grant (Insert und Select
-- sind tabellenweit vergeben).
set search_path = public, extensions;

alter table public.feedback add column if not exists client_id uuid unique;
