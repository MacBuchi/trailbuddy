-- Patch 032: Gruppenfahrt (#519, E4; docs/konzept-geraete.md 6.1/6.3,
-- Betreiber 2026-11-17/18).
--
-- Zwei Stufen über dem, was Patch 031 schon teilt (die grobe Zelle im
-- Kanal `nearby:<uid>`):
--
-- 1. **Genau und live, nur in der Nähe.** Wer in einer Fahrt „Live mit
--    Buddys" einschaltet, legt seine GENAUE Position als Presence in einen
--    Paarkanal `live:<a>:<b>` (die beiden Kennungen sortiert, also genau
--    ein Kanal je Paar). Hinein dürfen nur die beiden, nur als direkte
--    Buddys und nur, wenn keiner den anderen über „sieht mich"
--    ausgeschlossen hat. WEM die Position geht, entscheidet das Gerät des
--    Senders: nur Buddys in derselben oder einer Nachbarzelle, die Live
--    selbst eingeschaltet haben. Realtime prüft die Rechte beim Beitritt,
--    nicht je Nachricht — „nur in der Nähe" kann der Server deshalb nicht
--    prüfen, ohne Orte zu speichern. Bewusst in Kauf genommen (Betreiber
--    2026-11-18): Ein Buddy, der seine Zelle fälscht, bekäme die genaue
--    Position — nur ein direkter Buddy, und nur während einer Fahrt mit
--    eingeschaltetem Live.
--
-- 2. **Grob, nicht live, nur „Homies".** Jeder wählt unter seinen
--    direkten Buddys Homies (`buddy_nearby_prefs.homie`). Ein Homie sieht
--    die Zelle aus Patch 031 auf der Karte, auch wenn er nicht in der Nähe
--    ist. Ehrlich benannt (Betreiber 2026-11-18): Die Zelle EMPFANGEN alle
--    direkten Buddys schon seit Patch 031 (sonst ginge die Meldung „in der
--    Nähe" nicht); die Stufe entscheidet, wem die App sie ZEIGT.
--    `nearby_homie_owners()` sagt mir, wer mich gewählt hat — ohne die
--    übrigen Schalter der anderen preiszugeben.
--
-- Keine Tabelle für Orte, kein Verlauf (A3): Presence lebt nur im
-- Speicher des Realtime-Dienstes und verschwindet mit dem Kanal.
set search_path = public, extensions;

alter table public.buddy_nearby_prefs
  add column homie boolean not null default false;

-- Darf der Aufrufer im Paarkanal [topic] lesen und Presence setzen? Nur
-- genau `live:<a>:<b>` mit a < b, der Aufrufer ist einer der beiden, beide
-- sind direkte Buddys, und keiner hat den anderen ausgeschlossen. Alles
-- andere ist nein — ohne Cast-Fehler.
create or replace function app_internal.may_live(topic text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  a uuid;
  b uuid;
  me uuid := auth.uid();
  uuid_re constant text := '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
begin
  if me is null or topic is null
     or topic !~ ('^live:' || uuid_re || ':' || uuid_re || '$') then
    return false;
  end if;
  a := substr(topic, 6, 36)::uuid;
  b := substr(topic, 43, 36)::uuid;
  if not (a::text < b::text) or me not in (a, b) then
    return false;
  end if;
  return app_internal.are_friends(a, b)
    and not exists (select 1 from buddy_nearby_prefs p
                    where p.hidden
                      and ((p.user_id = a and p.buddy_id = b)
                        or (p.user_id = b and p.buddy_id = a)));
end;
$$;
revoke all on function app_internal.may_live(text) from public, anon;
grant execute on function app_internal.may_live(text) to authenticated;

create policy live_presence_read on realtime.messages for select
  to authenticated
  using (realtime.messages.extension = 'presence'
    and app_internal.may_live((select realtime.topic())));
create policy live_presence_track on realtime.messages for insert
  to authenticated
  with check (realtime.messages.extension = 'presence'
    and app_internal.may_live((select realtime.topic())));

-- Wer hat MICH als Homie gewählt? Nur direkte Buddys, die mich nicht
-- ausgeschlossen haben — sonst bekäme ich ihre Zelle ohnehin nicht.
create or replace function public.nearby_homie_owners()
returns setof uuid language sql stable security definer set search_path = public as $$
  select p.user_id
  from buddy_nearby_prefs p
  where p.buddy_id = auth.uid()
    and p.homie
    and not p.hidden
    and app_internal.are_friends(p.user_id, p.buddy_id);
$$;
revoke all on function public.nearby_homie_owners() from public, anon;
grant execute on function public.nearby_homie_owners() to authenticated;
