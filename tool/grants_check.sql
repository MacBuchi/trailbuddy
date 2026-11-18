-- Rechte, die ein Wächter über die API NICHT sieht, weil er mit dem
-- Publishable Key fragt: die des Service-Schlüssels (Feedback-Bot,
-- patch_001) und die Gegenprobe, dass anon an Feedback nicht herankommt.
-- Läuft im Schema Dry Run nach beiden Wegen.
do $$
declare
  missing text := '';
begin
  if not has_table_privilege('service_role', 'public.feedback', 'select') then
    missing := missing || ' feedback:select'; end if;
  if not has_table_privilege('service_role', 'public.feedback', 'update') then
    missing := missing || ' feedback:update'; end if;
  if not has_table_privilege('service_role', 'public.error_reports', 'select') then
    missing := missing || ' error_reports:select'; end if;
  if not has_table_privilege('service_role', 'public.error_reports', 'delete') then
    missing := missing || ' error_reports:delete'; end if;
  if missing <> '' then
    raise exception 'service_role fehlen Rechte für den Feedback-Bot:%', missing;
  end if;
  if has_table_privilege('anon', 'public.feedback', 'select') then
    raise exception 'anon darf feedback lesen — das Feedback anderer wäre offen';
  end if;
  raise notice 'grants_check: ok';
end $$;

-- Push (patch_008): send-push räumt tote Token mit dem Service-Schlüssel
-- ab — ohne diese Grants bliebe jede tote Zeile für immer, und jeder
-- Lauf schickte weiter an sie (PilzBuddy, 2026-09-24: sieben von neun
-- Einträgen tot). anon darf das Register nicht lesen.
do $$
declare
  missing text := '';
begin
  if not has_table_privilege('service_role', 'public.push_devices', 'select') then
    missing := missing || ' push_devices:select'; end if;
  if not has_table_privilege('service_role', 'public.push_devices', 'delete') then
    missing := missing || ' push_devices:delete'; end if;
  if missing <> '' then
    raise exception 'service_role fehlen Rechte für send-push:%', missing;
  end if;
  if has_table_privilege('anon', 'public.push_devices', 'select') then
    raise exception 'anon darf push_devices lesen — fremde Gerätekennungen wären offen';
  end if;
  if has_table_privilege('authenticated', 'app_internal.push_outbox', 'select') then
    raise exception 'authenticated darf push_outbox lesen — der Korb verriete, wer wessen Trails sieht';
  end if;
  raise notice 'grants_check push: ok';
end $$;

-- Meldungen (patch_013): `confirmed` legt der Server fest. Ein
-- insert- oder update-Grant ließe jeden Client sich selbst bestätigen.
do $$
begin
  if has_table_privilege('authenticated', 'public.trail_reports', 'insert')
     or has_table_privilege('authenticated', 'public.trail_reports', 'update') then
    raise exception 'authenticated darf trail_reports direkt schreiben — „bestätigt" wäre frei wählbar';
  end if;
  if has_table_privilege('anon', 'public.trail_reports', 'select') then
    raise exception 'anon darf trail_reports lesen';
  end if;
  if not has_table_privilege('authenticated', 'public.trail_reports', 'select') then
    raise exception 'authenticated fehlt select auf trail_reports';
  end if;
  raise notice 'grants_check reports: ok';
end $$;

-- Nachrichten (patch_021): anon bekommt nichts, und authenticated nur die
-- Spalten, die die 30 Tage nicht aushebeln — ein Tabellen-INSERT oder
-- -UPDATE schlüge jeden Spalten-Grant (auto_expose_new_tables).
do $$
begin
  if has_table_privilege('anon', 'public.buddy_messages', 'select')
     or has_table_privilege('anon', 'public.buddy_messages', 'insert') then
    raise exception 'anon darf an buddy_messages — Nachrichten wären offen';
  end if;
  if has_table_privilege('authenticated', 'public.buddy_messages', 'insert')
     or has_column_privilege('authenticated', 'public.buddy_messages', 'created_at', 'insert')
     or has_column_privilege('authenticated', 'public.buddy_messages', 'expires_at', 'insert')
     or has_column_privilege('authenticated', 'public.buddy_messages', 'sender_id', 'insert') then
    raise exception 'authenticated darf buddy_messages mit eigener Frist oder fremdem Absender anlegen';
  end if;
  if has_table_privilege('authenticated', 'public.buddy_messages', 'update')
     or has_column_privilege('authenticated', 'public.buddy_messages', 'body', 'update') then
    raise exception 'authenticated darf an buddy_messages mehr als read_at ändern';
  end if;
  if not (has_column_privilege('authenticated', 'public.buddy_messages', 'recipient_id', 'insert')
          and has_column_privilege('authenticated', 'public.buddy_messages', 'body', 'insert')
          and has_column_privilege('authenticated', 'public.buddy_messages', 'read_at', 'update')) then
    raise exception 'authenticated fehlen die Spalten-Grants für Nachrichten';
  end if;
  raise notice 'grants_check messages: ok';
end $$;

-- Airtime (patch_029): anon bekommt nichts; den Bestwert schreibt nur
-- set_trail_airtime — ein Tabellen-INSERT oder -UPDATE hebelte „nur
-- besser" und die Sichtbarkeitsprüfung aus.
do $$
begin
  if has_table_privilege('anon', 'public.trail_airtime', 'select')
     or has_table_privilege('anon', 'public.airtime_counters', 'select') then
    raise exception 'anon darf Airtime lesen';
  end if;
  if has_table_privilege('authenticated', 'public.trail_airtime', 'insert')
     or has_table_privilege('authenticated', 'public.trail_airtime', 'update') then
    raise exception 'authenticated darf trail_airtime direkt schreiben';
  end if;
  if has_function_privilege('anon', 'public.set_trail_airtime(jsonb)', 'execute')
     or has_function_privilege('anon', 'public.delete_my_airtime()', 'execute') then
    raise exception 'anon darf die Airtime-Funktionen aufrufen';
  end if;
  raise notice 'grants_check airtime: ok';
end $$;

-- Gemerkte Startpunkte (patch_030): anon bekommt nichts, die Grenze
-- je Konto ruft niemand von außen.
do $$
begin
  if has_table_privilege('anon', 'public.start_points', 'select')
     or has_table_privilege('anon', 'public.start_points', 'insert') then
    raise exception 'anon darf start_points lesen oder schreiben';
  end if;
  if not (has_table_privilege('authenticated', 'public.start_points', 'select')
          and has_table_privilege('authenticated', 'public.start_points', 'insert')
          and has_table_privilege('authenticated', 'public.start_points', 'update')
          and has_table_privilege('authenticated', 'public.start_points', 'delete')) then
    raise exception 'authenticated fehlen die Grants auf start_points';
  end if;
  if has_function_privilege('authenticated', 'app_internal.start_points_limit()', 'execute') then
    raise exception 'authenticated darf start_points_limit aufrufen';
  end if;
  raise notice 'grants_check start_points: ok';
end $$;

-- Buddy in der Nähe (patch_031): anon bekommt nichts; die Prüffunktion
-- der Kanäle darf nur authenticated (Realtime ruft sie als Nutzer).
do $$
begin
  if has_table_privilege('anon', 'public.buddy_nearby_prefs', 'select')
     or has_table_privilege('anon', 'public.buddy_nearby_prefs', 'insert') then
    raise exception 'anon darf buddy_nearby_prefs lesen oder schreiben';
  end if;
  if not (has_table_privilege('authenticated', 'public.buddy_nearby_prefs', 'select')
          and has_table_privilege('authenticated', 'public.buddy_nearby_prefs', 'insert')
          and has_table_privilege('authenticated', 'public.buddy_nearby_prefs', 'update')
          and has_table_privilege('authenticated', 'public.buddy_nearby_prefs', 'delete')) then
    raise exception 'authenticated fehlen die Grants auf buddy_nearby_prefs';
  end if;
  if has_function_privilege('anon', 'app_internal.may_read_nearby(text)', 'execute') then
    raise exception 'anon darf may_read_nearby aufrufen';
  end if;
  if has_function_privilege('authenticated', 'app_internal.nearby_prefs_on_unfriend()', 'execute') then
    raise exception 'authenticated darf nearby_prefs_on_unfriend aufrufen';
  end if;
  if has_function_privilege('anon', 'app_internal.may_live(text)', 'execute') then
    raise exception 'anon darf may_live aufrufen';
  end if;
  if has_function_privilege('anon', 'public.nearby_homie_owners()', 'execute')
     or not has_function_privilege('authenticated', 'public.nearby_homie_owners()', 'execute') then
    raise exception 'nearby_homie_owners: falsche Rechte';
  end if;
  raise notice 'grants_check buddy_nearby: ok';
end $$;
