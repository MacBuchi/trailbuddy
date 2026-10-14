#!/usr/bin/env bash
# Ruft app_internal.push_flush() auf dem Wegwerf-Stack des Schema Dry
# Run WIRKLICH auf und prüft Auslöser, Empfänger und die Nutzlast, die an
# `send-push` ginge (Patch 008, #34; Muster PilzBuddy #564). Seit Patch 014
# Wort für Wort mit Inhalt: Alias des Empfängers (nie der Gegenseite),
# sein Trailname, Hinweistext gekürzt — und nie eine Koordinate.
#
# **Warum es das braucht:** PL/pgSQL prüft den Rumpf einer Funktion beim
# Anlegen kaum — ein falscher Spaltenname fällt erst beim AUFRUF auf.
# push_flush ruft in CI sonst niemand auf, live aber jede Minute der
# Cron-Job; ein Fehler darin legte ALLE Benachrichtigungen lautlos still
# (der Job scheitert in cron.job_run_details, die App merkt nichts).
#
# **Es geht nichts hinaus.** Alles läuft in EINER Transaktion, die am Ende
# zurückgerollt wird; pg_net verschickt nur, was committet ist. Die
# Geheimnisse sind Platzhalter, die Adresse zeigt ins Leere.
#
# Braucht SUPABASE_DB_URL (lokaler Stack) und jq.
set -euo pipefail

DB="${SUPABASE_DB_URL:?SUPABASE_DB_URL fehlt}"
A=aaaaaaaa-0000-0000-0000-00000000000a   # Anna: meldet und schreibt
B=bbbbbbbb-0000-0000-0000-00000000000b   # Bert: Buddy von Anna, mit Gerät
C=cccccccc-0000-0000-0000-00000000000c   # Carl: Buddy von Anna, OHNE Gerät
D=dddddddd-0000-0000-0000-00000000000d   # Dave: nur eine offene Anfrage
T1=11111111-0000-0000-0000-000000000001
T2=11111111-0000-0000-0000-000000000002

out=$(psql "$DB" -v ON_ERROR_STOP=1 -q -At <<SQL
begin;
-- Sauberer Korb: matcher_check.sql läuft davor in derselben Datenbank
-- und hinterlässt eigene Statuswechsel und Hinweise (also Zeilen).
delete from app_internal.push_outbox;
delete from app_internal.push_messages;
select vault.create_secret('http://127.0.0.1:9/functions/v1', 'push_functions_url');
select vault.create_secret('dry-run', 'push_job_secret');
select vault.create_secret('dry-run', 'push_service_key');
insert into auth.users (id, email, aud, role, instance_id) values
  ('$A', 'a@push.check', 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
  ('$B', 'b@push.check', 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
  ('$C', 'c@push.check', 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
  ('$D', 'd@push.check', 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000');
-- Eigene Namen: matcher_check.sql lässt seine Nutzer (anna, bernd …)
-- in derselben Datenbank stehen, und username ist eindeutig.
insert into public.profiles (id, username) values
  ('$A', 'push_anna'), ('$B', 'push_bert'), ('$C', 'push_carl'), ('$D', 'push_dave')
  on conflict (id) do update set username = excluded.username;
insert into public.friendships (requester_id, addressee_id, status)
  values ('$A', '$B', 'accepted'), ('$C', '$A', 'accepted'), ('$D', '$A', 'pending');
insert into public.push_devices (token, user_id, platform)
  values ('tok-bert', '$B', 'android'), ('tok-anna', '$A', 'web'), ('tok-dave', '$D', 'android');
-- Zwei Trails von Anna, geteilt (Beitrag mit „buddies"); Bert, Carl
-- und Dave haben selbst nichts gefahren — sie sehen die Trails nur
-- über die Freundschaft mit Anna.
insert into public.trails (id) values ('$T1'), ('$T2');
insert into public.trail_recordings (trail_id, user_id, geom, source, quality) values
  ('$T1', '$A', 'SRID=4326;LINESTRING(9 48, 9.01 48)', 'app', 0.5),
  ('$T2', '$A', 'SRID=4326;LINESTRING(9 48.1, 9.01 48.1)', 'app', 0.5);
insert into public.trail_details (trail_id, user_id, name, visibility) values
  ('$T1', '$A', 'Hang', 'buddies'),
  ('$T2', '$A', 'Kamm', 'buddies'),
  -- Bert hat T1 selbst benannt: SEIN Name steht in seiner Meldung
  -- (Patch 014, wie Trail.displayName in der App).
  ('$T1', '$B', 'Mein Hang', 'buddies');
-- Annas Meldungen gehen über die EINE Schreibstelle (put_report), wie
-- report_trail sie für jemanden schreibt, der den Trail gefahren ist:
-- bestätigt. Bis Patch 025 kamen sie hier über trail_details.status.
-- Aliase (Patch 014): Bert nennt Anna „Anni", Carl nennt sie „Chefin".
-- In Berts Meldung steht „Anni" — nie Carls Alias.
insert into public.friend_aliases (owner_id, friend_id, alias) values
  ('$B', '$A', 'Anni'), ('$C', '$A', 'Chefin');
select 'OUTBOX_AFTER_SEED=' || count(*) from app_internal.push_outbox;

-- 1. Anna meldet T1 gesperrt: Bert und Carl bekommen eine Zeile, Anna
--    selbst und Dave nicht.
select app_internal.put_report('$A', '$T1', 'status', 'closed', null, true, now(), null);
select 'OUTBOX_AFTER_STATUS=' || string_agg(recipient_id::text || ':' || kind || ':' || coalesce(status, '-'), ',' order by recipient_id)
  from app_internal.push_outbox;
-- Dieselbe Meldung noch einmal: keine neue Zeile im Korb.
select app_internal.put_report('$A', '$T1', 'status', 'closed', null, true, now(), null);
select 'OUTBOX_AFTER_REPEAT=' || count(*) from app_internal.push_outbox;
-- Entprellt: Vor der Frist geht nichts hinaus.
select 'SENT_EARLY=' || app_internal.push_flush();
select 'OUTBOX_EARLY=' || count(*) from app_internal.push_outbox;
-- Frist um.
update app_internal.push_outbox set due_at = now() - interval '1 minute';
select 'SENT1=' || app_internal.push_flush();
select 'BODY1=' || convert_from(body, 'utf8') from net.http_request_queue order by id desc limit 1;
select 'OUTBOX_AFTER_FLUSH1=' || count(*) from app_internal.push_outbox;

-- 2. Zwei Hinweise an zwei Trails: EINE Meldung, Ziel die Liste.
insert into public.trail_notes (trail_id, user_id, body) values
  ('$T1', '$A', 'Baum liegt quer'), ('$T2', '$A', 'Kehre ausgewaschen');
update app_internal.push_outbox set due_at = now() - interval '1 minute';
select 'SENT2=' || app_internal.push_flush();
select 'BODY2=' || convert_from(body, 'utf8') from net.http_request_queue order by id desc limit 1;

-- 3. Status UND Hinweis am selben Trail, fällig zugleich.
select app_internal.put_report('$A', '$T1', 'status', 'open', null, true, now(), null);
insert into public.trail_notes (trail_id, user_id, body) values ('$T1', '$A', 'wieder frei');
update app_internal.push_outbox set due_at = now() - interval '1 minute';
select 'SENT3=' || app_internal.push_flush();
select 'BODY3=' || convert_from(body, 'utf8') from net.http_request_queue order by id desc limit 1;

-- 3c. EIN Hinweis: Alias, Trailname (Annas, Bert hat T2 nicht benannt)
--     und der Text, gekürzt auf 140 Zeichen.
insert into public.trail_notes (trail_id, user_id, body) values
  ('$T2', '$A', 'Kehre ausgewaschen ' || repeat('x', 200));
update app_internal.push_outbox set due_at = now() - interval '1 minute';
select 'SENT4=' || app_internal.push_flush();
select 'BODY4=' || convert_from(body, 'utf8') from net.http_request_queue order by id desc limit 1;

-- 3d. Ohne Alias steht der Benutzername.
delete from public.friend_aliases where owner_id = '$B';
select app_internal.put_report('$A', '$T2', 'status', 'destroyed', null, true, now(), null);
update app_internal.push_outbox set due_at = now() - interval '1 minute';
select 'SENT5=' || app_internal.push_flush();
select 'BODY5=' || convert_from(body, 'utf8') from net.http_request_queue order by id desc limit 1;
-- Zurück, damit Fall 4 von „zerstört" auf „zerstört" nichts auslöst.
select app_internal.put_report('$A', '$T2', 'status', 'open', null, true, now(), null);
delete from app_internal.push_outbox;

-- 3e. Ein zurückgezogener Hinweis nimmt seine Meldung mit.
insert into public.trail_notes (id, trail_id, user_id, body) values
  ('22222222-0000-0000-0000-000000000001', '$T1', '$A', 'gleich wieder weg');
select 'OUTBOX_NOTE=' || count(*) from app_internal.push_outbox;
delete from public.trail_notes where id = '22222222-0000-0000-0000-000000000001';
select 'OUTBOX_NOTE_WITHDRAWN=' || count(*) from app_internal.push_outbox;

-- 3b. Meldungen über report_trail (Patch 013): Bert hat T1 nie gefahren.
--     Von zu Hause gemeldet ist unbestätigt und bleibt still; vor Ort
--     gemeldet ist bestätigt und geht an Anna.
delete from app_internal.push_outbox;
select set_config('request.jwt.claims', '{"sub":"$B","role":"authenticated"}', true);
set local role authenticated;
select public.report_trail('$T1', 'closed', null, false, null, null);
reset role;
select 'OUTBOX_UNCONFIRMED=' || count(*) from app_internal.push_outbox;
set local role authenticated;
select public.report_trail('$T1', 'closed', 2, true, null, null);
reset role;
select 'OUTBOX_ONSITE=' || coalesce(string_agg(recipient_id::text || ':' || kind || ':' || coalesce(status, '-'), ',' order by recipient_id), '')
  from app_internal.push_outbox;
delete from app_internal.push_outbox;

-- 7. Englisch (Patch 027): Berts Gerät läuft auf Englisch. Seit 3d hat
--    Bert keinen Alias für Anna mehr, also steht ihr Benutzername.
update public.push_devices set locale = 'en' where token = 'tok-bert';
-- T2, nicht T1: An T1 hat Bert in 3b selbst „gesperrt" gemeldet.
select app_internal.put_report('$A', '$T2', 'status', 'closed', null, true, now(), null);
update app_internal.push_outbox set due_at = now() - interval '1 minute';
select 'SENT_EN1=' || app_internal.push_flush();
select 'BODY_EN1=' || convert_from(body, 'utf8') from net.http_request_queue order by id desc limit 1;
insert into public.trail_notes (trail_id, user_id, body) values
  ('$T1', '$A', 'Baum'), ('$T2', '$A', 'Kehre');
update app_internal.push_outbox set due_at = now() - interval '1 minute';
select 'SENT_EN2=' || app_internal.push_flush();
select 'BODY_EN2=' || convert_from(body, 'utf8') from net.http_request_queue order by id desc limit 1;
update public.push_devices set locale = 'de' where token = 'tok-bert';
delete from app_internal.push_outbox;
-- Die Bausteine ohne Versand: Namensliste und Trail ohne Namen.
select 'JOIN_EN=' || app_internal.push_join_names(array['A', 'B', 'C', 'D'], 'en');
select 'JOIN_DE=' || app_internal.push_join_names(array['A', 'B', 'C'], 'de');
select 'NONAME_EN=' || (app_internal.push_trail_text('en', 1, 0, 1, 'destroyed', null, array[]::text[], null)).title;
select 'NONAME_DE=' || (app_internal.push_trail_text('de', 1, 0, 1, 'destroyed', null, array[]::text[], null)).title;
select 'COUNTS_EN=' || (app_internal.push_trail_text('en', 2, 1, 1, null, 'Kamm', array['Anni'], null)).title;

-- 6. Nachrichten (Patch 022): Bert schreibt Anna zweimal, Dave (nur eine
--    offene Anfrage) einmal. Anna nennt Bert „Bertl". Keine Frist: der
--    nächste Lauf schickt; je Absender EINE Meldung, Text die jüngste.
delete from app_internal.push_outbox;
insert into public.friend_aliases (owner_id, friend_id, alias) values ('$A', '$B', 'Bertl');
-- Die ältere eine Minute früher (eine Transaktion hat nur EIN now());
-- expires_at mit, sonst verböte der 30-Tage-Check die Zeile.
insert into public.buddy_messages (sender_id, recipient_id, body, created_at, expires_at) values
  ('$B', '$A', 'erste', now() - interval '1 minute', now() + interval '29 days'),
  ('$B', '$A', 'Morgen Hang? ' || repeat('y', 300), now(), now() + interval '30 days'),
  ('$D', '$A', 'Ich bin Dave', now(), now() + interval '30 days');
select 'MSG_QUEUE=' || count(*) from app_internal.push_messages;
select 'SENT_MSG=' || app_internal.push_flush();
select 'BODY_MSG=' || convert_from(body, 'utf8') from net.http_request_queue order by id desc limit 1;
select 'MSG_QUEUE_AFTER=' || count(*) from app_internal.push_messages;
-- Zurückgenommen, bevor der Lauf kam: keine Meldung.
insert into public.buddy_messages (id, sender_id, recipient_id, body) values
  ('33333333-0000-0000-0000-000000000001', '$B', '$A', 'doch nicht');
select 'MSG_QUEUED=' || count(*) from app_internal.push_messages;
delete from public.buddy_messages where id = '33333333-0000-0000-0000-000000000001';
select 'MSG_WITHDRAWN=' || count(*) from app_internal.push_messages;
-- Annas Gerät auf Englisch: dieselbe Meldung, englisch gesetzt.
update public.push_devices set locale = 'en' where token = 'tok-anna';
insert into public.buddy_messages (sender_id, recipient_id, body) values
  ('$B', '$A', 'one'), ('$B', '$A', 'two');
select 'SENT_MSG_EN=' || app_internal.push_flush();
select 'BODY_MSG_EN=' || convert_from(body, 'utf8') from net.http_request_queue order by id desc limit 1;
update public.push_devices set locale = 'de' where token = 'tok-anna';

-- 4. Privat: Kein Buddy sieht den Beitrag, also erfährt keiner etwas.
update public.trail_details set visibility = 'private'
  where trail_id = '$T2' and user_id = '$A';
select app_internal.put_report('$A', '$T2', 'status', 'destroyed', null, true, now(), null);
insert into public.trail_notes (trail_id, user_id, body) values ('$T2', '$A', 'privat');
select 'OUTBOX_PRIVATE=' || count(*) from app_internal.push_outbox;

-- 5. Ohne Geheimnisse räumt der Versand nur ab.
update public.trail_details set visibility = 'buddies'
  where trail_id = '$T2' and user_id = '$A';
select app_internal.put_report('$A', '$T2', 'status', 'changed', null, true, now(), null);
delete from vault.secrets where name = 'push_job_secret';
update app_internal.push_outbox set due_at = now() - interval '1 minute';
insert into public.buddy_messages (sender_id, recipient_id, body) values ('$B', '$A', 'ohne Versand');
select 'SENT_NOSECRET=' || app_internal.push_flush();
select 'OUTBOX_NOSECRET=' || count(*) from app_internal.push_outbox;
select 'MSG_NOSECRET=' || count(*) from app_internal.push_messages;
rollback;
SQL
)
# ACHTUNG: Der Heredoc oben ist absichtlich NICHT gequotet (\$A, \$B
# werden eingesetzt) — Backticks in SQL-Kommentaren führte die Shell
# deshalb als Befehle aus. Keine Backticks dort.

value() { printf '%s\n' "$out" | sed -n "s/^$1=//p" | head -1; }

fail=0
expect() {
  if [ "$2" != "$3" ]; then
    echo "::error::push_flush: $1 — erwartet '$3', bekommen '$2'"
    fail=1
  else
    echo "✓ $1"
  fi
}

expect "Anlegen eines Beitrags löst nichts aus" "$(value OUTBOX_AFTER_SEED)" "0"
expect "Statuswechsel: Bert und Carl bekommen eine Zeile, Anna und Dave nicht" \
  "$(value OUTBOX_AFTER_STATUS)" "$B:trail_status:closed,$C:trail_status:closed"
expect "erneutes Melden desselben Status legt keine Zeile an" "$(value OUTBOX_AFTER_REPEAT)" "2"
expect "vor der Frist geht nichts hinaus" "$(value SENT_EARLY)" "0"
expect "und der Korb bleibt voll" "$(value OUTBOX_EARLY)" "2"
expect "eine Meldung (Carl hat kein Gerät)" "$(value SENT1)" "1"
body1=$(value BODY1)
msg1=$(printf '%s' "$body1" | jq -c '.messages[0]')
expect "an Berts Gerät" "$(jq -r .token <<<"$msg1")" "tok-bert"
expect "Titel: Alias des Empfängers, SEIN Trailname, Statuswort" "$(jq -r .title <<<"$msg1")" "Anni meldet „Mein Hang“ als gesperrt"
expect "Text: der Tipp" "$(jq -r .body <<<"$msg1")" "Tippen zeigt den Trail"
expect "Ziel: der Trail" "$(jq -r .route <<<"$msg1")" "/trail/$T1"
expect "genau eine Nachricht in der Nutzlast" "$(jq -r '.messages | length' <<<"$body1")" "1"
expect "Korb nach dem Versand leer" "$(value OUTBOX_AFTER_FLUSH1)" "0"
case "$body1" in *Chefin*|*push_anna*|*LINESTRING*|*48.*|*9.01*) echo "::error::push_flush: fremder Alias, Nutzername statt Alias oder Koordinate in der Nutzlast: $body1"; fail=1;;
  *) echo "✓ kein fremder Alias, kein Nutzername statt Alias, keine Koordinate in der Nutzlast";; esac

expect "zwei Hinweise an zwei Trails: eine Meldung" "$(value SENT2)" "1"
msg2=$(value BODY2 | jq -c '.messages[0]')
expect "Titel: die Anzahl" "$(jq -r .title <<<"$msg2")" "2 neue Hinweise von deinen Buddys"
expect "Text: die Trails und wer" "$(jq -r .body <<<"$msg2")" "An 2 Trails · von Anni"
expect "Ziel: die Liste" "$(jq -r .route <<<"$msg2")" "/trails"

expect "Status und Hinweis zugleich: eine Meldung" "$(value SENT3)" "1"
msg3=$(value BODY3 | jq -c '.messages[0]')
expect "Titel: der Trail und die Zahlen" "$(jq -r .title <<<"$msg3")" "„Mein Hang“: 1 Meldung und 1 Hinweis"
expect "Text: wer" "$(jq -r .body <<<"$msg3")" "von Anni"
expect "Ziel: der eine Trail" "$(jq -r .route <<<"$msg3")" "/trail/$T1"

expect "ein Hinweis: eine Meldung" "$(value SENT4)" "1"
msg4=$(value BODY4 | jq -c '.messages[0]')
expect "Titel: Alias und Trailname" "$(jq -r .title <<<"$msg4")" "Anni zu „Kamm“"
body4=$(jq -r .body <<<"$msg4")
expect "Text: der Hinweis, auf 140 Zeichen gekürzt" "$(jq -r '.body | length' <<<"$msg4")" "140"
case "$body4" in "Kehre ausgewaschen "*…) echo "✓ der Hinweistext steht vorn, das Ende trägt …";;
  *) echo "::error::push_flush: Hinweistext fehlt oder ist falsch gekürzt: $body4"; fail=1;; esac

expect "ohne Alias: eine Meldung" "$(value SENT5)" "1"
msg5=$(value BODY5 | jq -c '.messages[0]')
expect "Titel: der Benutzername" "$(jq -r .title <<<"$msg5")" "push_anna meldet „Kamm“ als zerstört"

expect "ein Hinweis legt eine Zeile an" "$(value OUTBOX_NOTE)" "2"
expect "zurückgezogen: keine Meldung mehr" "$(value OUTBOX_NOTE_WITHDRAWN)" "0"

expect "unbestätigte Meldung (von zu Hause): keine Push" "$(value OUTBOX_UNCONFIRMED)" "0"
expect "vor Ort bestätigt: Anna bekommt eine Zeile, der Zustand keine" "$(value OUTBOX_ONSITE)" "$A:trail_status:closed"
expect "Englisch: eine Meldung" "$(value SENT_EN1)" "1"
msg_en1=$(value BODY_EN1 | jq -c '.messages[0]')
expect "Englisch: an Berts Gerät" "$(jq -r .token <<<"$msg_en1")" "tok-bert"
expect "Englisch: Titel mit Statuswort" "$(jq -r .title <<<"$msg_en1")" "push_anna reports “Kamm” as closed"
expect "Englisch: Text der Tipp" "$(jq -r .body <<<"$msg_en1")" "Tap to see the trail"
msg_en2=$(value BODY_EN2 | jq -c '.messages[0]')
expect "Englisch: zwei Hinweise, Titel" "$(jq -r .title <<<"$msg_en2")" "2 new notes from your buddies"
expect "Englisch: zwei Hinweise, Text" "$(jq -r .body <<<"$msg_en2")" "On 2 trails · from push_anna"
expect "Englisch: Namensliste" "$(value JOIN_EN)" "A, B and 2 others"
expect "Deutsch: Namensliste" "$(value JOIN_DE)" "A, B und C"
expect "Englisch: Trail ohne Namen" "$(value NONAME_EN)" "A buddy reports “Unnamed trail” as destroyed"
expect "Deutsch: Trail ohne Namen" "$(value NONAME_DE)" "Ein Buddy meldet „Trail ohne Namen“ als zerstört"
expect "Englisch: Zahlen an einem Trail" "$(value COUNTS_EN)" "“Kamm”: 2 reports and 1 note"
expect "eine Nachricht wartet je Zeile in der Schlange" "$(value MSG_QUEUE)" "3"
expect "Nachrichten: eine Meldung je Absender" "$(value SENT_MSG)" "2"
body_msg=$(value BODY_MSG)
msg_b=$(printf '%s' "$body_msg" | jq -c --arg r "/friends/chat/$B" '.messages[] | select(.route == $r)')
msg_d=$(printf '%s' "$body_msg" | jq -c --arg r "/friends/chat/$D" '.messages[] | select(.route == $r)')
expect "an Annas Gerät" "$(jq -r .token <<<"$msg_b")" "tok-anna"
expect "Titel: Annas Alias für Bert und die Zahl" "$(jq -r .title <<<"$msg_b")" "Bertl · 2 Nachrichten"
expect "Text: die jüngste, auf 180 Zeichen gekürzt" "$(jq -r '.body | length' <<<"$msg_b")" "180"
case "$(jq -r .body <<<"$msg_b")" in "Morgen Hang? "*…) echo "✓ die jüngste Nachricht steht vorn, das Ende trägt …";;
  *) echo "::error::push_flush: Nachrichtentext fehlt oder ist falsch gekürzt: $msg_b"; fail=1;; esac
expect "offene Anfrage: der Benutzername" "$(jq -r .title <<<"$msg_d")" "push_dave"
expect "eine einzelne Nachricht steht ganz da" "$(jq -r .body <<<"$msg_d")" "Ich bin Dave"
case "$body_msg" in *erste*) echo "::error::push_flush: eine ältere Nachricht steht in der Nutzlast: $body_msg"; fail=1;;
  *) echo "✓ nur die jüngste Nachricht je Absender in der Nutzlast";; esac
expect "die Schlange ist danach leer" "$(value MSG_QUEUE_AFTER)" "0"
expect "eine neue Nachricht wartet" "$(value MSG_QUEUED)" "1"
expect "zurückgenommen: keine Meldung mehr" "$(value MSG_WITHDRAWN)" "0"
msg_en=$(value BODY_MSG_EN | jq -c '.messages[0]')
expect "Englisch: Nachrichten an Annas Gerät" "$(jq -r .token <<<"$msg_en")" "tok-anna"
expect "Englisch: Alias und Zahl" "$(jq -r .title <<<"$msg_en")" "Bertl · 2 messages"
expect "privater Beitrag: niemand erfährt etwas" "$(value OUTBOX_PRIVATE)" "0"
expect "ohne Geheimnisse wird nichts verschickt" "$(value SENT_NOSECRET)" "0"
expect "aber abgeräumt" "$(value OUTBOX_NOSECRET)" "0"
expect "auch die Nachrichten-Schlange" "$(value MSG_NOSECRET)" "0"

exit $fail
