-- TrailBuddy — Supabase-Schema (Frischinstallation).
-- Komplett im Supabase-Dashboard unter „SQL Editor" einfügen und ausführen,
-- oder per psql (tool/schema_local_test.sh fährt genau das gegen einen
-- nackten Postgres mit tool/auth_shim.sql davor).
--
-- Die Datei muss für sich vollständig sein: Der Schema Dry Run spielt sie
-- auf eine leere Datenbank und danach NICHTS mehr (PilzBuddy-Muster).
-- Ein späterer patch_NNN gehört im selben PR in die Struktur hier UND in
-- die Saat-Liste am Ende; tool/patch_guard.sh erzwingt beides.
--
-- Was hier abgebildet ist, steht in docs/konzept-trails.md: Abschnitt 3
-- (Datenmodell), 4 (Abgleich), 10 (Entscheidungen des Betreibers). Die
-- Schwellen des Abgleichs sind gemessen (docs/trail-abgleich-messung.md)
-- und stehen an EINER Stelle: app_internal.match_params().

-- ============================================================
-- PostGIS
-- ============================================================
-- Supabase-Konvention: Erweiterungen liegen im Schema `extensions`. Auf
-- einem nackten Postgres gibt es das Schema nicht — deshalb zuerst
-- anlegen, dann funktioniert dieselbe Zeile auf beiden. Ist PostGIS im
-- Projekt schon eingeschaltet, tut `if not exists` nichts.
create schema if not exists extensions;
create extension if not exists postgis with schema extensions;
-- Damit Sicht und Funktionsköpfe (Typ `geometry`) PostGIS ohne Präfix
-- finden. Supabase hat `extensions` ohnehin im Suchpfad, psql nicht. Die
-- Funktionsrümpfe verlassen sich NICHT darauf: Jede Funktion trägt ihren
-- eigenen festen search_path (PilzBuddy Patch 036).
set search_path = public, extensions;
grant usage on schema extensions to anon, authenticated;

-- ============================================================
-- Tabellen: Konto und Buddys (aus PilzBuddy übernommen)
-- ============================================================

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  display_name text,
  avatar int not null default 0,               -- Index im Avatar-Katalog
  created_at timestamptz not null default now()
);
-- Einmalig auch über Groß-/Kleinschreibung hinweg (PilzBuddy Patch 013):
-- Die Buddy-Suche matcht per ilike auf das Namens-Präfix, „Trailbiker"
-- und „trailbiker" wären für Suchende dasselbe Konto.
create unique index profiles_username_lower_key
  on public.profiles (lower(username));

create table public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted')),
  created_at timestamptz not null default now(),
  check (requester_id <> addressee_id)
);
-- verhindert doppelte Paare in beiden Richtungen
create unique index friendships_pair_uidx on public.friendships
  (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
-- RLS-Policies und are_friends filtern über diese Spalten
create index friendships_requester_idx on public.friendships (requester_id);
create index friendships_addressee_idx on public.friendships (addressee_id);

-- Aliase für Buddys (PilzBuddy Patch 032): eine private Notiz je Buddy,
-- nur für den, der sie vergibt; nur für bestätigte Buddys; Ende der
-- Freundschaft löscht sie (Trigger unten). Beide Personen auf auth.users,
-- nicht auf profiles — sonst hielte PostgREST die Tabelle für eine
-- Verbindungstabelle und Embeds auf profiles würden mehrdeutig (PGRST201).
create table public.friend_aliases (
  owner_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  friend_id uuid not null references auth.users(id) on delete cascade,
  alias text not null check (char_length(btrim(alias)) between 1 and 40),
  updated_at timestamptz not null default now(),
  primary key (owner_id, friend_id),
  check (owner_id <> friend_id)
);
create index friend_aliases_friend_idx on public.friend_aliases (friend_id);

-- Feedback aus der App. Ohne Bilder und ohne Arten (das war PilzBuddy);
-- `processed_at` setzt der Feedback-Bot, wenn er daraus ein Issue macht.
create table public.feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null default 'feature' check (type in ('feature', 'bug')),
  message text not null check (char_length(message) between 3 and 2000),
  app_version text check (char_length(app_version) <= 40),
  -- Kennung des Auftrags im Ausgangskorb (#218, Patch 018): ein
  -- Wiederholversuch nach abgerissener Antwort legt keine zweite Zeile an.
  client_id uuid unique,
  processed_at timestamptz,
  created_at timestamptz not null default now()
);

-- Gefangene Fehler aus dem Feld (PilzBuddy Patch 009). Android Vitals
-- sieht nur harte Abstürze auf Play-Installationen — die abgefangenen
-- Fehler, bei denen die App mit einer SnackBar weiterläuft, landen hier.
-- Absichtlich ohne Nutzdaten: kein Standort, keine Namen, keine Linie.
create table public.error_reports (
  id uuid primary key default gen_random_uuid(),
  -- Nullable: die wertvollsten Fehler passieren vor der Anmeldung.
  user_id uuid references public.profiles(id) on delete cascade,
  context text not null check (char_length(context) between 1 and 100),
  error_type text not null check (char_length(error_type) <= 100),
  message text check (char_length(message) <= 1000),
  stack text check (char_length(stack) <= 4000),
  app_version text check (char_length(app_version) <= 40),
  platform text check (char_length(platform) <= 20),
  created_at timestamptz not null default now()
);
create index error_reports_created_idx
  on public.error_reports (created_at desc);

-- Server-seitige App-Konfiguration (PilzBuddy Patch 012). Einzeilige
-- Tabelle: der check lässt nur id = true zu. minimum_supported_version
-- sperrt Clients aus, die zu alt für das aktuelle Schema sind — jede
-- Breaking-Migration setzt den Wert im selben PR hoch, per Patch, nie von
-- Hand. Der Wert darf nie über dem STABILEN Stand liegen
-- (tool/schema_check.sh wacht darüber).
create table public.app_config (
  id boolean primary key default true check (id),
  minimum_supported_version text not null default '0.0.0'
    check (minimum_supported_version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
  updated_at timestamptz not null default now()
);
insert into public.app_config (id) values (true);

-- ============================================================
-- Tabellen: Trails (Konzept Abschnitt 3)
-- ============================================================

-- Die Kennung. Bewusst ohne Name, ohne Besitzer, ohne created_at: Nichts
-- in dieser Zeile darf verraten, dass jemand anderes den Trail schon
-- hatte. Der Client liest diese Tabelle NIE — er fragt „welche
-- Aufzeichnungen und Beiträge sehe ich" und gruppiert nach trail_id.
-- Deshalb weiter unten: RLS an, keine Grants für anon und authenticated.
create table public.trails (
  id uuid primary key default gen_random_uuid()
);

-- Ein Beleg: „ich bin das gefahren". Geometrie in WGS84 als geography,
-- damit ST_DWithin in Metern rechnet und der GiST-Index den Vorfilter des
-- Abgleichs trägt (Abschnitt 4.2, Stufe 1).
create table public.trail_recordings (
  id uuid primary key default gen_random_uuid(),
  trail_id uuid not null references public.trails(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  geom geography(LineString, 4326) not null,
  -- Wann gefahren. Leer bei `planned` — außer der Fahrer hat das Datum
  -- beim Import eingetragen (Patch 015, #120): Dann ist die Linie
  -- gezeichnet (Qualität bleibt 0,1), die Fahrt aber belegt.
  recorded_at timestamptz,
  -- 'planned': importierte Datei ohne Zeiten oder mit unplausiblen
  -- Geschwindigkeiten — eine geplante Route, keine Fahrt. Zählt als
  -- Beitrag (Entscheidung 2), mit Qualität nahe null.
  source text not null check (source in ('app', 'import', 'planned')),
  reversed boolean not null default false,  -- gegen die Trail-Richtung gefahren (4.3)
  quality real not null check (quality between 0 and 1),  -- 0..1, siehe 4.5
  created_at timestamptz not null default now(),
  -- Vom Gerät vergebene Kennung des Auftrags aus dem Ausgangskorb
  -- (PilzBuddy Patch 016): macht die Wiedervorlage nach einem
  -- abgerissenen Aufruf idempotent. Leer bei allem, was nicht über den
  -- Korb kam.
  client_id uuid,
  -- Höhe in Metern je Punkt der Linie, in derselben Reihenfolge (Patch
  -- 002, Issue #14). Leer, wenn die Datei keine Höhen hatte — und zwar
  -- ganz: Eine halbe Reihe ergäbe eine erfundene Zahl. Bewusst kein
  -- LineStringZ: Der Abgleich rechnet flach und ist so gemessen.
  -- Anstieg, Abstieg und Profil rechnet der Client (trail_elevation.dart).
  ele real[],
  constraint trail_recordings_ele_check check (
    ele is null or (
      array_length(ele, 1) = st_npoints(geom::geometry)
      and array_position(ele, null) is null
      and -500 <= all(ele) and 9000 >= all(ele)))
);
create index trail_recordings_geom_gix on public.trail_recordings using gist (geom);
create index trail_recordings_trail_idx on public.trail_recordings (trail_id);
create index trail_recordings_user_idx on public.trail_recordings (user_id);
-- Zweimal derselbe Auftrag ⇒ derselbe Trail statt Dublette. Partiell,
-- weil die Spalte für Aufzeichnungen ohne Korb leer bleibt.
create unique index trail_recordings_user_client_id_key
  on public.trail_recordings (user_id, client_id)
  where client_id is not null;

-- Was ein Nutzer über einen Trail sagt. Genau eine Zeile je Nutzer und
-- Trail. Entsteht mit der ersten Aufzeichnung (contribute_recording).
create table public.trail_details (
  trail_id uuid not null references public.trails(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text check (name is null or char_length(name) between 1 and 80),
  description text check (description is null or char_length(description) <= 2000),
  grade smallint check (grade between 0 and 5),   -- Singletrail-Skala S0–S5
  -- Veraltet seit Patch 009: nur für Clients bis 0.33.0, ersetzt durch
  -- traits (erweitern → ausliefern → entfernen).
  kind text check (kind in ('natural', 'flow', 'tech', 'jump', 'connection')),
  -- Der Charakter (Patch 009, Issue #72): Mehrfachwahl je Beitrag.
  traits text[] not null default '{}'
    constraint trail_details_traits_check check (
      traits <@ array['flowy', 'jumps', 'rocky', 'steep', 'uphill', 'natural', 'connection']::text[]
      and cardinality(traits) <= 7),
  -- Die Bewertung (Patch 013, #101): 1–5 Sterne, wie gut einem der Trail
  -- gefällt. Leer = noch nicht bewertet. Angezeigt als Median der
  -- sichtbaren Beiträge, auf dem Gerät gerechnet (Konzept 12).
  rating smallint constraint trail_details_rating_check check (rating between 1 and 5),
  -- In beide Richtungen fahrbar (Patch 016, #174): Ohne diese Angabe
  -- fährt der Planer den Trail nie gegen seine Richtung. Vorgabe aus.
  two_way boolean not null default false,
  visibility text not null default 'buddies' check (visibility in ('buddies', 'private')),
  -- Veraltet seit Patch 013: Die Meldung steht in trail_reports. status
  -- und status_at bleiben für Clients bis 0.48.0 und werden in beide
  -- Richtungen abgeglichen (reports_from_details, reports_to_details) —
  -- erweitern → ausliefern → entfernen.
  status text not null default 'open' check (status in ('open', 'closed', 'destroyed', 'changed')),
  status_at timestamptz,
  -- Verweis auf die Quelle (Patch 012, #103): eine Vereinsseite o. Ä.,
  -- vorgeschlagen aus dem <link> der GPX-Datei. Nur https, ohne Query
  -- und Fragment — Freigabelinks von Tourenportalen tragen dort Tokens.
  link text constraint trail_details_link_check check (link is null or (link ~ '^https://[^[:space:]/?#]+(/[^[:space:]?#]*)?$' and char_length(link) <= 500)),
  -- Nicht in der Skizze des Konzepts, aber von ihr verlangt: „Name =
  -- eigener Name, sonst der Name des ÄLTESTEN sichtbaren Beitrags"
  -- (Abschnitt 3) braucht das Alter des Beitrags, und updated_at ändert
  -- sich mit jeder Korrektur.
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (trail_id, user_id)
);
create index trail_details_user_idx on public.trail_details (user_id);
comment on column public.trail_details.kind is
  'Veraltet seit Patch 009 (Issue #72): nur noch für Clients bis 0.33.0; ersetzt durch traits.';
comment on column public.trail_details.two_way is
  'Patch 016 (#174): in beide Richtungen fahrbar — der Planer fährt den Trail sonst nie gegen seine Richtung.';
comment on column public.trail_details.status is
  'Veraltet seit Patch 013: die Meldung steht in trail_reports; bleibt für Clients bis 0.48.0 und wird abgeglichen.';

-- Hinweise zu einem Trail für Buddys (Patch 004/005, Issue #7): „Baum
-- liegt quer". Schreiben darf jeder, der den Trail sieht; mehrere je
-- Person, ohne Bearbeiten (das Alter soll stimmen). Nach 90 Tagen räumt
-- sweep_old_notes() auf, der jüngste je Autor und Trail bleibt.
create table public.trail_notes (
  id uuid primary key default gen_random_uuid(),
  trail_id uuid not null,
  user_id uuid not null,
  body text not null check (char_length(btrim(body)) between 1 and 500),
  created_at timestamptz not null default now(),
  constraint trail_notes_user_id_fkey foreign key (user_id)
    references public.profiles(id) on delete cascade,
  constraint trail_notes_trail_id_fkey foreign key (trail_id)
    references public.trails(id) on delete cascade
);
create index trail_notes_trail_idx on public.trail_notes (trail_id);
create index trail_notes_user_idx on public.trail_notes (trail_id, user_id);

-- Meldungen und Zustände (Patch 013, #101; docs/konzept-rework.md,
-- Abschnitt 9): „gesperrt", „offen" … (kind 'status', in der App
-- „Meldung") und der Zustand 1–5 (kind 'condition'). Ein VERLAUF, eine
-- Zeile je Angabe. Schreiben darf jeder, der den Trail sieht — nur über
-- report_trail(), weil `confirmed` der Server festlegt: bestätigt ist
-- eine Angabe, wenn der Meldende den Trail zu diesem Zeitpunkt selbst
-- gefahren hat (eine Aufzeichnung, die nicht `planned` ist) ODER die App
-- ihn vor Ort gesehen hat (≤ 200 m, auf dem Gerät geprüft). Das „vor
-- Ort" selbst wird NICHT gespeichert, nur das Ergebnis; die Position
-- verlässt das Gerät nie.
--
-- Aufbewahrt werden 90 Tage (sweep_old_reports); die jüngste Angabe je
-- Person, Trail, Art und Bestätigung bleibt darüber hinaus — die
-- angezeigte Meldung ist die jüngste bestätigte, und die muss auch nach
-- einem Jahr noch da sein. Je Person, nicht über alle: „die jüngste über
-- alle Netze" wäre eine Rechnung über Netzgrenzen (Konzept 12).
create table public.trail_reports (
  id uuid primary key default gen_random_uuid(),
  trail_id uuid not null,
  user_id uuid not null,
  kind text not null check (kind in ('status', 'condition')),
  status text check (status in ('open', 'closed', 'destroyed', 'changed')),
  condition smallint check (condition between 1 and 5),
  confirmed boolean not null,
  -- Wann die Angabe gemacht wurde — vom Gerät, damit eine Meldung aus
  -- dem Ausgangskorb ihre echte Zeit behält; der Server kappt auf now().
  reported_at timestamptz not null,
  created_at timestamptz not null default now(),
  -- Ausgangskorb: derselbe Auftrag zweimal legt keine zweite Zeile an.
  client_id uuid,
  constraint trail_reports_value_check check (
    (kind = 'status') = (status is not null)
    and (kind = 'condition') = (condition is not null)),
  constraint trail_reports_user_id_fkey foreign key (user_id)
    references public.profiles(id) on delete cascade,
  constraint trail_reports_trail_id_fkey foreign key (trail_id)
    references public.trails(id) on delete cascade
);
create index trail_reports_trail_idx on public.trail_reports (trail_id);
create index trail_reports_latest_idx
  on public.trail_reports (trail_id, user_id, kind, confirmed, reported_at desc);
create index trail_reports_user_idx on public.trail_reports (user_id);
create unique index trail_reports_client_id_key
  on public.trail_reports (user_id, client_id, kind)
  where client_id is not null;

-- Geräteregister für Push (Patch 008, #34): eine Zeile je Gerät, der
-- Token ist der Schlüssel und gehört zu genau EINEM Konto (der Upsert
-- der App zieht die Zeile beim Kontowechsel um). Eine Zeile IST die
-- Zustimmung dieses Geräts, ihr Fehlen der Widerruf — kein zweites
-- „aktiv"-Flag.
create table public.push_devices (
  token text primary key,
  user_id uuid not null default auth.uid()
    references public.profiles(id) on delete cascade,
  platform text not null check (platform in ('android', 'web')),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index push_devices_user_idx on public.push_devices (user_id);

-- ============================================================
-- Profil automatisch bei Registrierung anlegen
-- (Username kommt aus den Signup-Metadaten der App)
-- ============================================================

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'username',
                   'trailbuddy_' || substr(new.id::text, 1, 8)));
  return new;
end $$;

-- Nur der Trigger ruft die Funktion — die Default-Grants an die API-Rollen
-- sind unnötig (EXECUTE wird beim Anlegen des Triggers geprüft, nicht beim
-- Feuern).
revoke all on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- ============================================================
-- app_internal: Hilfsfunktionen, Matcher, unsichtbare Nachbarschaft
--
-- Bewusst NICHT in public: PostgREST exponiert jede Funktion im
-- public-Schema als /rest/v1/rpc/-Endpunkt für anon+authenticated.
-- EXECUTE entziehen geht bei Policy-Helfern nicht — die Policies werten
-- die Funktionen mit den Rechten der anfragenden Rolle aus. Deshalb liegen
-- sie in app_internal, das die API nie sieht (PilzBuddy Patch 011).
-- ============================================================

create schema if not exists app_internal;
grant usage on schema app_internal to anon, authenticated;

-- Unsichtbare Nachbarschaft (Abschnitt 4.4): „Trail A überlappt Trail B
-- zu 45 %". Der Vorrat für ein späteres „Sind das dieselben?" zwischen
-- zwei Buddys, die beide Linien sehen. KEIN Client liest diese Tabelle —
-- ein Zähler oder eine Kante nach außen verriete, dass jemand anderes
-- den Nachbarn kennt (4.6).
create table app_internal.trail_overlaps (
  a uuid not null references public.trails(id) on delete cascade,
  b uuid not null references public.trails(id) on delete cascade,
  coverage_ab real,   -- Anteil von A im Korridor von B
  coverage_ba real,   -- Anteil von B im Korridor von A
  created_at timestamptz not null default now(),
  primary key (a, b)
);
create index trail_overlaps_b_idx on app_internal.trail_overlaps (b);

-- Der entprellte Push-Korb (Patch 008): je Empfänger, Art und Trail eine
-- Zeile, die Fälligkeit schiebt jeder weitere Anlass vor sich her
-- (push_due_at). Hier und nicht in public: In public hielte PostgREST
-- die Tabelle wegen ihrer Fremdschlüssel für eine Verbindungstabelle
-- (PilzBuddy Patch 018), und der Client hat hier nichts zu suchen.
create table app_internal.push_outbox (
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('trail_status', 'trail_note')),
  trail_id uuid not null references public.trails(id) on delete cascade,
  status text check (status is null or status in ('open', 'closed', 'destroyed', 'changed')),
  due_at timestamptz not null,
  created_at timestamptz not null default now(),
  -- Seit Patch 014: wer (in der Reihenfolge des ersten Anlasses), wie
  -- viele Anlässe diese Zeile zusammenfasst und — bei einem Hinweis —
  -- welcher der jüngste ist. Wird der Hinweis gelöscht, entfällt die
  -- Zeile (zurückgezogen heißt: keine Meldung).
  sender_ids uuid[] not null default '{}',
  events integer not null default 1,
  note_id uuid references public.trail_notes(id) on delete cascade,
  primary key (recipient_id, kind, trail_id)
);
create index push_outbox_due_idx on app_internal.push_outbox (due_at);

create or replace function app_internal.are_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from friendships
    where status = 'accepted'
      and ((requester_id = a and addressee_id = b)
        or (requester_id = b and addressee_id = a)));
$$;

-- Auch offene Anfragen zählen — nötig, damit man den Namen des
-- Absenders einer Freundschaftsanfrage sehen kann.
create or replace function app_internal.involved_in_friendship(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from friendships
    where (requester_id = a and addressee_id = b)
       or (requester_id = b and addressee_id = a));
$$;

-- Teilt [contributor] seinen Beitrag zu [trail] mit Buddys? Die
-- Sichtbarkeit steht am BEITRAG (trail_details.visibility). Fehlt die
-- Zeile noch, gilt die Vorgabe `buddies` — dieselbe Antwort, die die
-- Zeile mit ihrem Default gäbe, wenn sie schon da wäre.
create or replace function app_internal.contributor_shares(contributor uuid, trail uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(
    (select d.visibility = 'buddies'
       from trail_details d
      where d.trail_id = trail and d.user_id = contributor),
    true);
$$;

-- Sieht [uid] den Trail? Dieselbe Regel wie recordings_select, als
-- Definer, damit die Policies der Hinweise sie direkt fragen können.
create or replace function app_internal.can_see_trail(uid uuid, trail uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from trail_recordings r
     where r.trail_id = trail
       and (r.user_id = uid
         or (app_internal.are_friends(r.user_id, uid)
             and app_internal.contributor_shares(r.user_id, trail))));
$$;

-- Hat [uid] den Trail selbst GEFAHREN? Eine eigene Aufzeichnung, die
-- nicht `planned` ist — eine Datei ohne Fahrzeiten belegt keine Fahrt
-- (Patch 011, 013) —, oder eine geplante MIT eingetragenem Fahrdatum
-- (Patch 015, #120: der Fahrer sagt ausdrücklich, dass er dort war). Die
-- Grundlage von „bestätigt" (trail_reports).
create or replace function app_internal.has_ridden(uid uuid, trail uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from trail_recordings r
     where r.trail_id = trail and r.user_id = uid
       and (r.source <> 'planned' or r.recorded_at is not null));
$$;
revoke all on function app_internal.has_ridden(uuid, uuid) from public, anon, authenticated;

-- Die EINE Schreibstelle für Meldungen und Zustände (Patch 013): der
-- RPC report_trail, der Abgleich aus trail_details (alte Clients) und
-- contribute_recording schreiben hierüber. Eine bekannte client_id ist
-- ein zweiter Versuch desselben Auftrags und legt nichts an. Gibt zurück,
-- ob eine Zeile entstanden ist.
create or replace function app_internal.put_report(
  p_user uuid, p_trail uuid, p_kind text, p_status text, p_condition integer,
  p_confirmed boolean, p_at timestamptz, p_client_id uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  insert into trail_reports (trail_id, user_id, kind, status, condition, confirmed, reported_at, client_id)
  values (p_trail, p_user, p_kind, p_status, p_condition, p_confirmed,
          least(coalesce(p_at, now()), now()), p_client_id)
  on conflict (user_id, client_id, kind) where client_id is not null do nothing;
  return found;
end $$;
revoke all on function app_internal.put_report(uuid, uuid, text, text, integer, boolean, timestamptz, uuid)
  from public, anon, authenticated;

-- ------------------------------------------------------------
-- Der Abgleich (Abschnitt 4). Spiegel von tool/trail_match.py —
-- dieselbe Pipeline, dieselben Schwellen. Wer hier eine Zahl ändert,
-- misst sie dort nach und ändert beide im selben PR.
-- ------------------------------------------------------------

-- Alle Schwellen an EINER Stelle. Gemessen am 2026-09-27 an 584 Tracks
-- (docs/trail-abgleich-messung.md); Begründung je Wert in Abschnitt 4.2:
--   corridor_m        15   GPS unter Blätterdach liegt 10–20 m daneben
--   coverage_same     0.8  Lücke in der Verteilung zwischen 0,7 und 0,9
--   frechet_factor    2    „gleich" ≤ 2·d; alle Gleichen ≤ 19,4 m, der
--                          nächste Wert 84 m
--   min_trail_m       50   darunter Zufahrt oder Fragment (Patch 017,
--                          Betreiber 2026-10-04; bis dahin 150)
--   step_m            5    Kehren mit 10 m Radius bleiben sichtbar
--   frechet_max_points 400 Kappe für die O(n·m)-DP in PL/pgSQL (unten)
--   overlap_min       0.3  ab hier eine Kante in trail_overlaps (Gabel)
--   direction_same / direction_reversed: Anteil steigender Schritte
--                          entlang der anderen Linie (≥ 0,7 / ≤ 0,3)
--   daily_limit       500  Aufzeichnungen je Nutzer in 24 h (4.6, „Rate";
--                          Patch 006: ein ganzer Bestand am Stück, gemessen
--                          in docs/trail-abgleich-messung.md, „Tageslimit")
create type app_internal.match_params as (
  corridor_m double precision,
  coverage_same double precision,
  frechet_factor double precision,
  min_trail_m double precision,
  step_m double precision,
  frechet_max_points integer,
  overlap_min double precision,
  direction_same double precision,
  direction_reversed double precision,
  daily_limit integer
);

create or replace function app_internal.match_params()
returns app_internal.match_params
language sql immutable set search_path = '' as $$
  select row(15.0, 0.8, 2.0, 50.0, 5.0, 400, 0.3, 0.7, 0.3, 500)::app_internal.match_params;
$$;

-- Ergebnis eines Vergleichs Kandidat (a) gegen Bestand (b). `class` ist
-- das Wort aus PairResult.classify(): same, same-reversed, neighbour,
-- a-in-b, b-in-a, fork, different.
create type app_internal.match_result as (
  cov_ab real,
  cov_ba real,
  direction text,
  frechet_m real,
  class text
);

-- Metrische Projektion: die UTM-Zone des Schwerpunkts. Beide Linien eines
-- Paars werden in DIESELBE Zone projiziert, damit Abstände vergleichbar
-- sind; ein Paar am Zonenrand bleibt auf wenige Promille genau — mehr
-- braucht ein 15-m-Korridor nicht. (trail_match.py nimmt eine
-- äquirektanguläre Näherung um die mittlere Breite; dieselbe Klasse
-- Genauigkeit.)
create or replace function app_internal.utm_srid(g geometry)
returns integer
language sql immutable set search_path = public, extensions as $$
  select (case when st_y(c) >= 0 then 32600 else 32700 end)
       + least(60, greatest(1, floor((st_x(c) + 180) / 6)::int + 1))
    from (select st_centroid(g) as c) s;
$$;

-- Punkte alle `step` Meter entlang der Linie, Anfang und Ende dabei — wie
-- resample() im Werkzeug. Locus-Exporte sind auf ~13 m gedünnt und
-- gezeichnete Routen haben 100-m-Schenkel; ein Korridortest auf den
-- Stützpunkten allein übersähe die Linie dazwischen.
create or replace function app_internal.resample(g geometry, step double precision)
returns geometry[]
language plpgsql immutable set search_path = public, extensions as $$
declare
  len double precision := st_length(g);
  pts geometry[];
begin
  if len <= step then
    return array[st_startpoint(g), st_endpoint(g)];
  end if;
  select array_agg(d.geom order by d.path)
    into pts
    from st_dumppoints(st_lineinterpolatepoints(g, step / len, true)) d;
  pts := array[st_startpoint(g)] || pts;
  if st_distance(pts[array_upper(pts, 1)], st_endpoint(g)) > 0.01 then
    pts := pts || st_endpoint(g);
  end if;
  return pts;
end $$;

-- Diskrete Fréchet-Distanz, Zwei-Zeilen-DP — Zeile für Zeile frechet()
-- aus trail_match.py. O(n·m): Deshalb kappt match_lines die Punktzahl
-- je Linie auf frechet_max_points (400 ⇒ höchstens 160 000 Zellen; auf
-- dem lokalen Postgres gemessen im Bereich von Zehntelsekunden). Das
-- Werkzeug rechnet mit 1200, hat aber Python-Zeit statt Datenbankzeit.
-- PostGIS hätte ST_FrechetDistance in C; die eigene DP steht hier, damit
-- Werkzeug und Datenbank nachweislich denselben Algorithmus fahren
-- (tool/matcher_check.sql vergleicht beide an einem Beispiel).
create or replace function app_internal.frechet(p geometry[], q geometry[])
returns double precision
language plpgsql immutable set search_path = public, extensions as $$
declare
  n integer := coalesce(array_length(p, 1), 0);
  m integer := coalesce(array_length(q, 1), 0);
  px double precision[]; py double precision[];
  qx double precision[]; qy double precision[];
  prev double precision[];
  cur double precision[];
  d double precision;
  best double precision;
  i integer; j integer;
begin
  if n < 2 or m < 2 then
    return 'infinity'::double precision;
  end if;
  select array_agg(st_x(g) order by o), array_agg(st_y(g) order by o)
    into px, py from unnest(p) with ordinality t(g, o);
  select array_agg(st_x(g) order by o), array_agg(st_y(g) order by o)
    into qx, qy from unnest(q) with ordinality t(g, o);
  prev := array_fill('infinity'::double precision, array[m]);
  for i in 1..n loop
    cur := array_fill('infinity'::double precision, array[m]);
    for j in 1..m loop
      d := sqrt((px[i] - qx[j]) * (px[i] - qx[j]) + (py[i] - qy[j]) * (py[i] - qy[j]));
      if i = 1 and j = 1 then
        cur[1] := d;
      else
        best := 'infinity'::double precision;
        if i > 1 then best := least(best, prev[j]); end if;
        if j > 1 then best := least(best, cur[j - 1]); end if;
        if i > 1 and j > 1 then best := least(best, prev[j - 1]); end if;
        cur[j] := greatest(best, d);
      end if;
    end loop;
    prev := cur;
  end loop;
  return prev[m];
end $$;

-- Ein Paar vergleichen: a = Kandidat, b = beste Aufzeichnung eines
-- bestehenden Trails, beide schon metrisch projiziert (gleiche SRID).
-- Stufen wie compare() im Werkzeug:
--   2. Deckung beidseitig auf 5-m-Abtastung, Abstand zum nächsten
--      SEGMENT (ST_DWithin gegen die Linie, nicht gegen Stützpunkte);
--   3. Richtung aus der Reihenfolge der Fußpunkte auf b
--      (ST_LineLocatePoint steigt monoton mit der Bogenlänge);
--   4. Fréchet NUR auf den Punkten im Korridor, beide Seiten vorher
--      beschnitten, bei Gegenrichtung auf der umgedrehten Linie — der
--      Test, der einen Serpentinen-Trail von seinem um eine Kehre
--      versetzten Nachbarn trennt, was Deckung allein nicht kann.
create or replace function app_internal.match_lines(a geometry, b geometry)
returns app_internal.match_result
language plpgsql stable set search_path = public, extensions as $$
declare
  p app_internal.match_params := app_internal.match_params();
  sa geometry[] := app_internal.resample(a, p.step_m);
  sb geometry[] := app_internal.resample(b, p.step_m);
  cov_ab double precision;
  cov_ba double precision;
  ups integer;
  diffs integer;
  direction text := 'mixed';
  fstep double precision;
  fa geometry[];
  fb geometry[];
  fr double precision;
  cls text;
begin
  select count(*) filter (where st_dwithin(s, b, p.corridor_m))::double precision / count(*)
    into cov_ab from unnest(sa) s;
  select count(*) filter (where st_dwithin(s, a, p.corridor_m))::double precision / count(*)
    into cov_ba from unnest(sb) s;

  -- Richtung: Anteil der Schritte, bei denen der Fußpunkt auf b weiter
  -- vorn liegt als beim vorigen Punkt. Unter drei Schritten keine Aussage.
  with near as (
    select o, st_linelocatepoint(b, s) as frac
      from unnest(sa) with ordinality t(s, o)
     where st_dwithin(s, b, p.corridor_m)
  ), steps as (
    select frac - lag(frac) over (order by o) as df from near
  )
  select count(*) filter (where df > 0), count(*)
    into ups, diffs from steps where df is not null;
  if diffs >= 3 then
    if ups::double precision / diffs >= p.direction_same then
      direction := 'same';
    elsif ups::double precision / diffs <= p.direction_reversed then
      direction := 'reversed';
    end if;
  end if;

  -- Fréchet nur, wo es die Entscheidung ändern kann: bei beidseitiger
  -- Deckung. Schrittweite so, dass je Linie höchstens frechet_max_points
  -- bleiben (Kappe, siehe frechet()).
  if cov_ab >= p.coverage_same and cov_ba >= p.coverage_same then
    fstep := greatest(p.step_m, greatest(st_length(a), st_length(b)) / p.frechet_max_points);
    select array_agg(s order by o) into fa
      from unnest(app_internal.resample(a, fstep)) with ordinality t(s, o)
     where st_dwithin(s, b, p.corridor_m);
    select array_agg(s order by case when direction = 'reversed' then -o else o end) into fb
      from unnest(app_internal.resample(b, fstep)) with ordinality t(s, o)
     where st_dwithin(s, a, p.corridor_m);
    fr := app_internal.frechet(fa, fb);
  end if;

  -- Einordnung — Spiegel von PairResult.classify().
  if cov_ab >= p.coverage_same and cov_ba >= p.coverage_same then
    if fr is not null and fr > p.frechet_factor * p.corridor_m then
      cls := 'neighbour';        -- deckt sich, aber die Reihenfolge folgt nicht
    elsif direction = 'reversed' then
      cls := 'same-reversed';
    else
      cls := 'same';
    end if;
  elsif cov_ab >= p.coverage_same then
    cls := 'a-in-b';
  elsif cov_ba >= p.coverage_same then
    cls := 'b-in-a';
  elsif greatest(cov_ab, cov_ba) >= p.overlap_min then
    cls := 'fork';
  else
    cls := 'different';
  end if;

  return row(cov_ab::real, cov_ba::real, direction,
             case when fr is null or fr = 'infinity'::double precision then null else fr::real end,
             cls)::app_internal.match_result;
end $$;

-- Nur der Definer-RPC ruft die Matcher-Funktionen; er läuft als
-- Eigentümer. Die API sieht app_internal ohnehin nicht — der Entzug ist
-- Gürtel zum Hosenträger.
revoke all on function app_internal.match_params() from public, anon, authenticated;
revoke all on function app_internal.utm_srid(geometry) from public, anon, authenticated;
revoke all on function app_internal.resample(geometry, double precision) from public, anon, authenticated;
revoke all on function app_internal.frechet(geometry[], geometry[]) from public, anon, authenticated;
revoke all on function app_internal.match_lines(geometry, geometry) from public, anon, authenticated;

-- Trails ohne jeden Beitrag verschwinden (Abschnitt 3, „Löschen und
-- DSGVO": kein Cascade vom Beitrag zur Kennung, sondern ein Aufräumjob).
-- Overlap-Kanten fallen per Cascade mit. Eingeplant unten per pg_cron,
-- wo es das gibt.
create or replace function app_internal.sweep_orphan_trails()
returns integer
language plpgsql security definer set search_path = public as $$
declare
  n integer;
begin
  delete from trails t
   where not exists (select 1 from trail_recordings r where r.trail_id = t.id)
     and not exists (select 1 from trail_details d where d.trail_id = t.id);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function app_internal.sweep_orphan_trails() from public, anon, authenticated;

-- Hinweise älter als 90 Tage verschwinden (Entscheidung 2026-09-28),
-- außer dem jüngsten eines Autors zu einem Trail: der bleibt, bis ihn
-- jemand entfernt. Je Autor statt je Trail, weil „der jüngste über alle
-- Netze" eine Rechnung über Netzgrenzen wäre (Konzept 12); jeder Leser
-- behält so trotzdem seinen jüngsten sichtbaren Hinweis.
create or replace function app_internal.sweep_old_notes()
returns integer
language plpgsql security definer set search_path = public as $$
declare
  n integer;
begin
  delete from trail_notes old
   where old.created_at < now() - interval '90 days'
     and exists (select 1 from trail_notes newer
                  where newer.trail_id = old.trail_id
                    and newer.user_id = old.user_id
                    and newer.created_at > old.created_at);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function app_internal.sweep_old_notes() from public, anon, authenticated;

-- Meldungen und Zustände älter als 90 Tage verschwinden (Patch 013,
-- Betreiber 2026-09-30: „zur Nachvollziehbarkeit 90 Tage"), außer der
-- jüngsten je Person, Trail, Art und Bestätigung — die angezeigte
-- Meldung ist die jüngste bestätigte, wie alt sie auch ist.
create or replace function app_internal.sweep_old_reports()
returns integer
language plpgsql security definer set search_path = public as $$
declare
  n integer;
begin
  delete from trail_reports old
   where old.reported_at < now() - interval '90 days'
     and exists (select 1 from trail_reports newer
                  where newer.trail_id = old.trail_id
                    and newer.user_id = old.user_id
                    and newer.kind = old.kind
                    and newer.confirmed = old.confirmed
                    and (newer.reported_at, newer.created_at, newer.id)
                      > (old.reported_at, old.created_at, old.id));
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function app_internal.sweep_old_reports() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Meldung ↔ trail_details.status (Patch 013): Clients bis 0.48.0 lesen
-- und schreiben die Meldung nur am Beitrag. Beide Richtungen, damit
-- keiner etwas verpasst — erweitern → ausliefern → entfernen.
-- ---------------------------------------------------------------------

-- Alt → neu: Ändert jemand status oder status_at am Beitrag (ein alter
-- Client), entsteht eine Meldung. `pg_trigger_depth() > 1` heißt: Die
-- Änderung kam selbst aus reports_to_details — dann gibt es die Meldung
-- schon, und ohne die Sperre liefen die beiden Trigger im Kreis.
create or replace function app_internal.reports_from_details()
returns trigger
language plpgsql security definer set search_path = public, app_internal as $$
begin
  if pg_trigger_depth() > 1 then return new; end if;
  if new.status = 'open' and new.status_at is null then return new; end if;
  if tg_op = 'UPDATE'
     and new.status is not distinct from old.status
     and new.status_at is not distinct from old.status_at then
    return new;
  end if;
  perform app_internal.put_report(new.user_id, new.trail_id, 'status', new.status, null,
                                  app_internal.has_ridden(new.user_id, new.trail_id),
                                  coalesce(new.status_at, now()), null);
  return new;
end $$;
revoke all on function app_internal.reports_from_details() from public, anon, authenticated;

-- Neu → alt: Eine BESTÄTIGTE Meldung landet am Beitrag des Meldenden,
-- wenn er einen hat und sie jünger ist. Unbestätigte nicht — ein alter
-- Client kennt kein „zu bestätigen" und zeigte sie als Tatsache.
create or replace function app_internal.reports_to_details()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind = 'status' and new.confirmed then
    update trail_details d
       set status = new.status, status_at = new.reported_at
     where d.trail_id = new.trail_id and d.user_id = new.user_id
       and new.reported_at > coalesce(d.status_at, '-infinity'::timestamptz);
  end if;
  return new;
end $$;
revoke all on function app_internal.reports_to_details() from public, anon, authenticated;

-- updated_at am Beitrag pflegt die Datenbank, nicht der Client.
create or replace function app_internal.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;
revoke all on function app_internal.touch_updated_at() from public, anon, authenticated;
create trigger trail_details_touch
  before update on public.trail_details
  for each row execute function app_internal.touch_updated_at();
create trigger trail_details_reports
  after insert or update of status, status_at on public.trail_details
  for each row execute function app_internal.reports_from_details();
create trigger trail_reports_details
  after insert on public.trail_reports
  for each row execute function app_internal.reports_to_details();

-- Aliase: Ende der Freundschaft löscht sie beider Seiten (PilzBuddy
-- Patch 032; Definer, weil die delete-Policy jedem nur die EIGENEN gibt).
create or replace function app_internal.aliases_on_unfriend()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from friend_aliases a
  where (a.owner_id = old.requester_id and a.friend_id = old.addressee_id)
     or (a.owner_id = old.addressee_id and a.friend_id = old.requester_id);
  return old;
end;
$$;
revoke all on function app_internal.aliases_on_unfriend() from public, anon, authenticated;
create trigger friendships_delete_aliases
  after delete on public.friendships
  for each row execute function app_internal.aliases_on_unfriend();

-- ============================================================
-- Push (Patch 008, #34): Fälligkeit, Empfänger, Auslöser, Versand
-- ============================================================
-- Die Meldung trägt seit Patch 014 den Trailnamen, den Namen (Alias) des
-- Buddys, das Statuswort und den Hinweistext — so, wie der Empfänger sie
-- in der App sieht; nie eine Koordinate, nie den Zustand. Ziel ist die
-- opake Trail-Kennung. Empfänger sind die direkten Buddys des Autors,
-- die den Trail und seinen Beitrag sehen (Spiegel von td_friend_select
-- und notes_select, Konzept 12). Die drei Geheimnisse des Versands
-- liegen im Vault (Anleitung in patch_008); fehlen sie, räumt push_flush
-- nur ab. tool/push_flush_check.sh ruft den Versand im Dry Run auf.

-- --------------------------------------------------------- Die Fälligkeit
--
-- Fünf Minuten Ruhe, gedeckelt auf eine halbe Stunde ab dem ersten
-- Anlass. An EINER Stelle, damit die Auslöser nicht auseinanderlaufen.
create or replace function app_internal.push_due_at(first_seen timestamptz)
returns timestamptz
language sql stable set search_path = '' as $$
  select least(now() + interval '5 minutes', first_seen + interval '30 minutes');
$$;
revoke all on function app_internal.push_due_at(timestamptz) from public, anon, authenticated;

-- ---------------------------------------------------------- Die Empfänger
--
-- Die direkten Buddys des Autors, die seinen Beitrag zu diesem Trail
-- sehen dürfen: Spiegel von td_friend_select / notes_select — Buddy UND
-- der Autor teilt den Trail (`contributor_shares`: nicht „privat") UND
-- der Buddy sieht den Trail überhaupt (`can_see_trail`). Der Autor
-- selbst ist nie dabei.
create or replace function app_internal.push_recipients(author uuid, trail uuid)
returns table (recipient_id uuid)
language sql stable security definer set search_path = public as $$
  select f.friend_id
    from (
      select case when requester_id = author then addressee_id else requester_id end as friend_id
        from friendships
       where status = 'accepted'
         and (requester_id = author or addressee_id = author)
    ) f
   where app_internal.contributor_shares(author, trail)
     and app_internal.can_see_trail(f.friend_id, trail);
$$;
revoke all on function app_internal.push_recipients(uuid, uuid) from public, anon, authenticated;

-- ------------------------------------------------ Namen in der Meldung
--
-- Seit Patch 014 (#116, Betreiber 2026-09-30: „anonym genug") trägt eine
-- Meldung den Trailnamen, den Namen des Buddys und den Hinweistext —
-- jeweils so, wie der EMPFÄNGER sie in der App sieht. Nie eine
-- Koordinate, nie der Zustand.

-- Der Name des Trails für [recipient]: Spiegel von `Trail.displayName`
-- — der eigene Name, sonst der des ältesten für ihn sichtbaren Beitrags
-- (eigene Zeile oder eine geteilte eines Buddys, td_friend_select), sonst
-- „Trail ohne Namen".
create or replace function app_internal.trail_name_for(recipient uuid, trail uuid)
returns text
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select d.name from trail_details d
      where d.trail_id = trail and d.user_id = recipient
        and nullif(btrim(d.name), '') is not null),
    (select d.name from trail_details d
      where d.trail_id = trail and d.user_id <> recipient
        and d.visibility = 'buddies'
        and app_internal.are_friends(d.user_id, recipient)
        and nullif(btrim(d.name), '') is not null
      order by (select min(r.created_at) from trail_recordings r
                 where r.trail_id = trail and r.user_id = d.user_id) nulls last
      limit 1),
    'Trail ohne Namen');
$$;
revoke all on function app_internal.trail_name_for(uuid, uuid) from public, anon, authenticated;

-- Der Name des Buddys [sender] für [recipient]: der Alias, den der
-- EMPFÄNGER vergeben hat (friend_aliases, Besitzer = Empfänger), sonst
-- der Benutzername. Den Alias der Gegenseite sieht nie jemand.
create or replace function app_internal.push_name_for(recipient uuid, sender uuid)
returns text
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select nullif(btrim(a.alias), '') from friend_aliases a
      where a.owner_id = recipient and a.friend_id = sender),
    (select p.username from profiles p where p.id = sender));
$$;
revoke all on function app_internal.push_name_for(uuid, uuid) from public, anon, authenticated;

-- „Anna", „Anna und Ben", „Anna, Ben und Carl", „Anna, Ben und 2 weitere".
create or replace function app_internal.push_join_names(names text[])
returns text
language sql immutable set search_path = '' as $$
  select case
    when coalesce(array_length(names, 1), 0) = 0 then null
    when array_length(names, 1) = 1 then names[1]
    when array_length(names, 1) <= 3 then
      array_to_string(names[1:array_length(names, 1) - 1], ', ')
        || ' und ' || names[array_length(names, 1)]
    else names[1] || ', ' || names[2] || ' und '
      || (array_length(names, 1) - 2) || ' weitere'
  end;
$$;
revoke all on function app_internal.push_join_names(text[]) from public, anon, authenticated;

-- ----------------------------------------------------------- Die Auslöser

-- Eine BESTÄTIGTE Meldung (Patch 013, trail_reports; bis dahin der
-- Status am Beitrag), die sich von der vorigen bestätigten desselben
-- Meldenden unterscheidet (Konzept 10, Punkt 6: alle vier Werte, auch
-- zurück auf „offen" — das ist die gute Nachricht). Dieselbe Meldung
-- noch einmal löst NICHTS aus, eine erste Meldung „offen" auch nicht.
-- Unbestätigte Meldungen nie (Betreiber, 2026-09-30): Wer von zu Hause
-- meldet, soll keine Buddys aufscheuchen. Der Zustand nie (Rework 3.2).
-- Eine Meldung, die verspätet aus dem Ausgangskorb kommt und älter ist
-- als eine schon da stehende, sagt nichts Neues — auch keine Meldung.
create or replace function app_internal.push_on_report()
returns trigger
language plpgsql security definer set search_path = public, app_internal as $$
declare
  prev text;
begin
  if new.kind <> 'status' or not new.confirmed then return new; end if;
  if exists (select 1 from trail_reports r
              where r.trail_id = new.trail_id and r.user_id = new.user_id
                and r.kind = 'status' and r.confirmed and r.id <> new.id
                and r.reported_at > new.reported_at) then
    return new;
  end if;
  select r.status into prev
    from trail_reports r
   where r.trail_id = new.trail_id and r.user_id = new.user_id
     and r.kind = 'status' and r.confirmed and r.id <> new.id
   order by r.reported_at desc, r.created_at desc
   limit 1;
  if not found and new.status = 'open' then return new; end if;
  if found and prev = new.status then return new; end if;
  insert into app_internal.push_outbox (recipient_id, kind, trail_id, status, sender_ids, due_at)
    select r.recipient_id, 'trail_status', new.trail_id, new.status, array[new.user_id],
           app_internal.push_due_at(now())
      from app_internal.push_recipients(new.user_id, new.trail_id) r
  on conflict (recipient_id, kind, trail_id) do update
    set status = excluded.status,
        sender_ids = case when new.user_id = any(push_outbox.sender_ids) then push_outbox.sender_ids
                          else push_outbox.sender_ids || new.user_id end,
        events = push_outbox.events + 1,
        due_at = app_internal.push_due_at(push_outbox.created_at);
  return new;
end $$;
revoke all on function app_internal.push_on_report() from public, anon, authenticated;

-- Ein neuer Hinweis (#7). Der Korb merkt sich den jüngsten; sein Text
-- geht seit Patch 014 mit hinaus (push_flush liest ihn beim Versand).
create or replace function app_internal.push_on_note()
returns trigger
language plpgsql security definer set search_path = public, app_internal as $$
begin
  insert into app_internal.push_outbox (recipient_id, kind, trail_id, sender_ids, note_id, due_at)
    select r.recipient_id, 'trail_note', new.trail_id, array[new.user_id], new.id,
           app_internal.push_due_at(now())
      from app_internal.push_recipients(new.user_id, new.trail_id) r
  on conflict (recipient_id, kind, trail_id) do update
    set note_id = excluded.note_id,
        sender_ids = case when new.user_id = any(push_outbox.sender_ids) then push_outbox.sender_ids
                          else push_outbox.sender_ids || new.user_id end,
        events = push_outbox.events + 1,
        due_at = app_internal.push_due_at(push_outbox.created_at);
  return new;
end $$;
revoke all on function app_internal.push_on_note() from public, anon, authenticated;

create trigger push_on_report_trg after insert on public.trail_reports
  for each row execute function app_internal.push_on_report();
create trigger push_on_note_trg after insert on public.trail_notes
  for each row execute function app_internal.push_on_note();

-- ------------------------------------------------------------ Der Versand
--
-- Die drei Geheimnisse stehen im VAULT und nicht hier — ein Patch liegt
-- öffentlich im Repo. Einmalig von Hand im SQL-Editor des Dashboards:
--
--   select vault.create_secret('https://<ref>.supabase.co/functions/v1',
--                              'push_functions_url');
--   select vault.create_secret('<PUSH_JOB_SECRET>', 'push_job_secret');
--   select vault.create_secret('<SERVICE_ROLE_KEY>', 'push_service_key');
--
-- Je Empfänger EINE Meldung, auch wenn mehrere Trails fällig sind.
-- Genau ein Trail ⇒ das Ziel ist der Trail (`/trail/<id>`), sonst die
-- Liste (`/trails`); die App prüft den Pfad gegen eine Erlaubnisliste.
-- tool/push_flush_check.sh ruft diese Funktion im Schema Dry Run
-- WIRKLICH auf (zurückgerollt): PL/pgSQL prüft den Rumpf erst beim
-- Aufruf, und ein Fehler hier legte live jede Minute still alles lahm.
create or replace function app_internal.push_flush()
returns integer
language plpgsql security definer
set search_path = public, app_internal, vault, net as $$
declare
  base_url text;
  job_secret text;
  service_key text;
  payload jsonb;
  sent integer;
begin
  select decrypted_secret into base_url
    from vault.decrypted_secrets where name = 'push_functions_url';
  select decrypted_secret into job_secret
    from vault.decrypted_secrets where name = 'push_job_secret';
  select decrypted_secret into service_key
    from vault.decrypted_secrets where name = 'push_service_key';

  -- Nicht eingerichtet: Fällige Zeilen trotzdem wegräumen und still
  -- zurück — sonst wüchse der Korb bis zur Einrichtung, und der erste
  -- Lauf feuerte einen Schwall über Meldungen von vorgestern ab.
  if base_url is null or job_secret is null or service_key is null then
    delete from app_internal.push_outbox where due_at <= now();
    return 0;
  end if;

  with due as (
    delete from app_internal.push_outbox
     where due_at <= now()
    returning recipient_id, kind, trail_id, status, sender_ids, events, note_id
  ),
  grouped as (
    select recipient_id,
           coalesce(sum(events) filter (where kind = 'trail_status'), 0) as statuses,
           coalesce(sum(events) filter (where kind = 'trail_note'), 0) as notes,
           count(distinct trail_id) as trails,
           min(trail_id::text) as trail_id,
           -- Das Statuswort, wenn es genau EINE Statusmeldung ist.
           max(status) filter (where kind = 'trail_status') as status,
           max(note_id::text) filter (where kind = 'trail_note') as note_id
      from due group by recipient_id
  ),
  named as (
    select g.*,
           g.statuses + g.notes = 1 as single,
           app_internal.trail_name_for(g.recipient_id, g.trail_id::uuid) as trail_name,
           -- Die Buddys dieses Empfängers, in der Reihenfolge ihres
           -- ersten Anlasses; ein gelöschtes Konto fällt heraus.
           app_internal.push_join_names(array(
             select q.nm from (
               select app_internal.push_name_for(g.recipient_id, u.sender) as nm,
                      min(u.ord) as ord
                 from due x
                 cross join lateral unnest(x.sender_ids) with ordinality as u(sender, ord)
                where x.recipient_id = g.recipient_id
                group by u.sender) q
              where q.nm is not null
              order by q.ord, q.nm)) as names,
           (select n.body from public.trail_notes n where n.id = g.note_id::uuid) as note_body,
           concat_ws(' und ',
             case when g.statuses = 1 then '1 Meldung'
                  when g.statuses > 1 then g.statuses || ' Meldungen' end,
             case when g.notes = 1 then '1 Hinweis'
                  when g.notes > 1 then g.notes || ' Hinweise' end) as counts
      from grouped g
  )
  select jsonb_agg(jsonb_build_object(
           'token', d.token,
           'title', case
             when m.single and m.statuses = 1 and m.status = 'open'
               then coalesce(m.names, 'Ein Buddy') || ': „' || m.trail_name || '“ ist wieder frei'
             when m.single and m.statuses = 1
               then coalesce(m.names, 'Ein Buddy') || ' meldet „' || m.trail_name || '“ als '
                    || case m.status
                         when 'closed' then 'gesperrt'
                         when 'destroyed' then 'zerstört'
                         else 'verändert' end
             when m.single
               then coalesce(m.names, 'Ein Buddy') || ' zu „' || m.trail_name || '“'
             when m.trails = 1
               then '„' || m.trail_name || '“: ' || m.counts
             when m.statuses > 0 and m.notes > 0
               then 'Deine Buddys haben etwas gemeldet'
             when m.statuses > 1
               then m.statuses || ' Meldungen von deinen Buddys'
             else m.notes || ' neue Hinweise von deinen Buddys'
           end,
           'body', case
             when m.single and m.notes = 1 and m.note_body is not null
               then case when char_length(m.note_body) > 140
                         then left(m.note_body, 139) || '…'
                         else m.note_body end
             when m.single then 'Tippen zeigt den Trail'
             when m.trails = 1 then 'von ' || coalesce(m.names, 'deinen Buddys')
             when m.statuses > 0 and m.notes > 0
               then m.counts || ' an ' || m.trails || ' Trails · von '
                    || coalesce(m.names, 'deinen Buddys')
             else 'An ' || m.trails || ' Trails · von ' || coalesce(m.names, 'deinen Buddys')
           end,
           'route', case
             when m.trails = 1 then '/trail/' || m.trail_id
             else '/trails'
           end))
    into payload
    from named m
    join public.push_devices d on d.user_id = m.recipient_id;

  if payload is null then return 0; end if;
  select jsonb_array_length(payload) into sent;

  -- Asynchron (pg_net): Die Antwort landet in net._http_response, der
  -- Cron-Lauf wartet nicht. Ein fehlgeschlagener Versand ist verloren —
  -- eine Wiedervorlage brächte im Zweifel dieselbe Meldung zweimal.
  perform net.http_post(
    url := base_url || '/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || service_key,
      'x-push-secret', job_secret),
    body := jsonb_build_object('messages', payload));
  return sent;
end $$;
revoke all on function app_internal.push_flush() from public, anon, authenticated;


-- ============================================================
-- RPCs in public (API-Endpunkte)
-- ============================================================

-- Der EINE Schreibweg für Aufzeichnungen (Abschnitt 4.1). Der Client kann
-- nicht gegen fremde Trails vergleichen, weil er sie nicht sehen darf —
-- also tut es die Datenbank, als Definer. Zurück kommt NUR die
-- Trail-Kennung; ob sie neu ist, sagt die Funktion nicht (4.6).
--
-- coords: flache Liste [lon1, lat1, lon2, lat2, …] in WGS84 — die
-- einfachste Form, die sich aus Dart als JSON-Array übergeben lässt.
--
-- Ablauf:
--   1. Angemeldet? Quelle bekannt? Mindestens zwei Punkte? Länge ≥ 50 m?
--      Tageslimit (4.6)? Sonst Ausnahme mit klarem Text.
--   2. Idempotenz: (user_id, client_id) schon da ⇒ dessen trail_id.
--   3. Vorfilter (GiST): Trails, deren Aufzeichnungen dem Kandidaten
--      näher als der Korridor kommen. Je Trail EINE Vertreterin — die
--      Aufzeichnung mit der höchsten Qualität (4.5: keine gemittelte
--      Linie).
--   4. match_lines je Vertreterin. Nur „gleich" hängt an (4.4, v1
--      bewusst konservativ) — bei mehreren Treffern der mit der höchsten
--      beidseitigen Deckung. „gleich-gegen" heißt reversed, RELATIV zur
--      Vertreterin: War die selbst gegen die Trail-Richtung unterwegs,
--      dreht sich das Vorzeichen (XOR).
--   5. Sonst neuer Trail, und je Nachbar mit Deckung ≥ 0,3 in einer
--      Richtung eine Kante in trail_overlaps (Teil, Enthält, Gabel,
--      Nachbar).
--   6. Aufzeichnung schreiben. Qualität vorerst nur aus der Quelle
--      (0,6 app / 0,4 import / 0,1 planned): Genauigkeit je Punkt und
--      Lückenprüfung (4.5) kommen, sobald der Client sie mitschickt —
--      dann als weiterer Parameter, nicht als andere Zahl hier.
--   7. Beitrag des Aufrufers anlegen, falls er fehlt.
--   8. Seine Meldung auf „offen" setzen — wer den Trail fährt, hat ihn
--      befahrbar vorgefunden (Abschnitt 3, Entscheidung 6), zum
--      Fahrdatum (Patch 013). Nicht bei `planned` (Patch 011, #100):
--      Eine Datei ohne Fahrzeiten belegt nicht, dass jemand den Trail
--      befahrbar vorgefunden hat — es sei denn, er hat das Fahrdatum
--      eingetragen (`recorded_at`, Patch 015, #120).
create or replace function public.contribute_recording(
  coords double precision[],
  source text,
  recorded_at timestamptz default null,
  client_id uuid default null,
  -- Eine Höhe je Punkt aus `coords`, oder null (Patch 002). Mit Vorgabe,
  -- damit Clients vor 0.3.0 dieselbe Funktion ohne den Namen treffen.
  eles double precision[] default null)
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  p app_internal.match_params := app_internal.match_params();
  uid uuid := auth.uid();
  npts integer;
  line geometry;
  geog geography;
  len double precision;
  srid integer;
  cand geometry;
  existing uuid;
  best_trail uuid;
  best_cov double precision := -1;
  best_reversed boolean := false;
  rec record;
  res app_internal.match_result;
  ov_trails uuid[] := '{}';
  ov_ab real[] := '{}';
  ov_ba real[] := '{}';
  target uuid;
  q real;
  ele_clean real[];
  ride_at timestamptz;
  last_report record;
begin
  if uid is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  if source is null or source not in ('app', 'import', 'planned') then
    raise exception 'Unbekannte Quelle: %', coalesce(source, 'null')
      using errcode = '22023', hint = 'app, import oder planned';
  end if;
  npts := coalesce(array_length(coords, 1), 0);
  if npts < 4 or npts % 2 <> 0 then
    raise exception 'Mindestens zwei Punkte als [lon, lat, lon, lat, …] erwartet'
      using errcode = '22023';
  end if;
  if exists (select 1 from generate_series(1, npts / 2) i
              where coords[2 * i - 1] not between -180 and 180
                 or coords[2 * i] not between -90 and 90) then
    raise exception 'Koordinate außerhalb von WGS84 (lon ±180, lat ±90)'
      using errcode = '22023';
  end if;
  -- Höhen: eine je Punkt oder gar keine. Die App schickt null, sobald
  -- einem Punkt die Höhe fehlt; hier wird nur noch geprüft, nicht geraten.
  if eles is not null then
    if coalesce(array_length(eles, 1), 0) <> npts / 2 then
      raise exception 'Höhen: % Werte für % Punkte', coalesce(array_length(eles, 1), 0), npts / 2
        using errcode = '22023';
    end if;
    if array_position(eles, null) is not null
       or exists (select 1 from unnest(eles) e where e not between -500 and 9000) then
      raise exception 'Höhe fehlt oder liegt außerhalb von −500 bis 9000 m'
        using errcode = '22023';
    end if;
  end if;

  -- 2. Idempotenz (Ausgangskorb): derselbe Auftrag noch einmal ⇒ dieselbe
  -- Antwort, keine zweite Aufzeichnung.
  if contribute_recording.client_id is not null then
    select r.trail_id into existing
      from trail_recordings r
     where r.user_id = uid and r.client_id = contribute_recording.client_id;
    if found then
      return existing;
    end if;
  end if;

  -- Rate (4.6): reicht jedem echten Nutzer, auch für einen Bestandsimport
  -- an einem Abend, und macht das Sondieren als Fläche unattraktiv.
  if (select count(*) from trail_recordings r
       where r.user_id = uid and r.created_at > now() - interval '1 day') >= p.daily_limit then
    raise exception 'Tageslimit von % Aufzeichnungen erreicht', p.daily_limit
      using errcode = '54000';
  end if;

  -- Doppelte Punkte fallen weg (Locus schreibt sie an Pausen) — samt
  -- ihrer Höhe. Bis Patch 002 stand hier st_removerepeatedpoints; das
  -- kürzt nur die Linie, und die Höhen liefen danach um einen Punkt
  -- versetzt neben ihr her.
  select st_setsrid(st_makeline(array_agg(st_makepoint(d.x, d.y) order by d.i)), 4326),
         case when eles is null then null else array_agg(d.z::real order by d.i) end
    into line, ele_clean
    from (
      select r.i, r.x, r.y, r.z,
             lag(r.x) over (order by r.i) as px, lag(r.y) over (order by r.i) as py
        from (select g.i, coords[2 * g.i - 1] as x, coords[2 * g.i] as y, eles[g.i] as z
                from generate_series(1, npts / 2) as g(i)) r
    ) d
   where d.px is null or d.x <> d.px or d.y <> d.py;
  if st_npoints(line) < 2 then
    raise exception 'Mindestens zwei verschiedene Punkte erwartet' using errcode = '22023';
  end if;
  geog := line::geography;
  len := st_length(geog);
  if len < p.min_trail_m then
    raise exception 'Aufzeichnung zu kurz: % m, ein Trail hat mindestens % m',
      round(len), p.min_trail_m::integer using errcode = '22023';
  end if;

  -- 3./4. Abgleich gegen die Vertreterinnen aller Trails in Reichweite.
  srid := app_internal.utm_srid(line);
  cand := st_transform(line, srid);
  for rec in
    with near as (
      select distinct r.trail_id
        from trail_recordings r
       where st_dwithin(r.geom, geog, p.corridor_m)
    )
    select n.trail_id, b.geom, b.reversed
      from near n
      cross join lateral (
        select r.geom, r.reversed
          from trail_recordings r
         where r.trail_id = n.trail_id
         order by r.quality desc, r.created_at asc
         limit 1) b
  loop
    res := app_internal.match_lines(cand, st_transform(rec.geom::geometry, srid));
    if res.class in ('same', 'same-reversed') then
      if least(res.cov_ab, res.cov_ba) > best_cov then
        best_trail := rec.trail_id;
        best_cov := least(res.cov_ab, res.cov_ba);
        best_reversed := (res.class = 'same-reversed') <> rec.reversed;
      end if;
    elsif greatest(res.cov_ab, res.cov_ba) >= p.overlap_min then
      ov_trails := ov_trails || rec.trail_id;
      ov_ab := ov_ab || res.cov_ab;
      ov_ba := ov_ba || res.cov_ba;
    end if;
  end loop;

  -- 5. Anhängen oder neu — nur „gleich" verschmilzt.
  if best_trail is not null then
    target := best_trail;
  else
    insert into trails default values returning id into target;
    insert into app_internal.trail_overlaps (a, b, coverage_ab, coverage_ba)
      select target, t, ab, ba
        from unnest(ov_trails, ov_ab, ov_ba) as u(t, ab, ba);
  end if;

  -- 6. Die Aufzeichnung.
  q := case source when 'app' then 0.6 when 'import' then 0.4 else 0.1 end;
  begin
    insert into trail_recordings
      (trail_id, user_id, geom, recorded_at, source, reversed, quality, client_id, ele)
    values
      (target, uid, geog, recorded_at, source, best_reversed, q, contribute_recording.client_id, ele_clean);
  exception when unique_violation then
    -- Wettlauf zweier Wiedervorlagen desselben Auftrags: Die erste hat
    -- gewonnen, ihre Antwort gilt. Ein eben angelegter leerer Trail geht
    -- wieder weg.
    if best_trail is null then
      delete from trails where id = target;
    end if;
    select r.trail_id into existing
      from trail_recordings r
     where r.user_id = uid and r.client_id = contribute_recording.client_id;
    return existing;
  end;

  -- 7. Der Beitrag, falls er fehlt.
  insert into trail_details (trail_id, user_id)
  values (target, uid)
  on conflict (trail_id, user_id) do nothing;

  -- 8. Die eigene Meldung auf „offen" (Patch 013; bis dahin der Status
  -- am Beitrag): Wer den Trail fährt, hat ihn befahrbar vorgefunden —
  -- und zwar AN DEM TAG, an dem er gefahren ist. Eine GPX-Datei von 2024
  -- verdrängt keine Meldung von gestern (Betreiber, 2026-09-30). Nur
  -- wenn der Aufrufer schon etwas gemeldet hat und das nicht schon ein
  -- bestätigtes „offen" ist; nicht bei `planned` (Patch 011) — außer
  -- mit eingetragenem Fahrdatum (Patch 015, #120).
  if contribute_recording.source <> 'planned' or contribute_recording.recorded_at is not null then
    ride_at := least(coalesce(contribute_recording.recorded_at, now()), now());
    select r.status, r.confirmed, r.reported_at into last_report
      from trail_reports r
     where r.trail_id = target and r.user_id = uid and r.kind = 'status'
     order by r.reported_at desc, r.created_at desc
     limit 1;
    if found and ride_at > last_report.reported_at
       and not (last_report.status = 'open' and last_report.confirmed) then
      perform app_internal.put_report(uid, target, 'status', 'open', null, true, ride_at, null);
    end if;
  end if;

  return target;
end $$;

-- Nur für Angemeldete. anon hätte die Funktion sonst über
-- /rest/v1/rpc/contribute_recording (Default-Grant an PUBLIC).
revoke all on function public.contribute_recording(double precision[], text, timestamptz, uuid, double precision[])
  from public, anon;
grant execute on function public.contribute_recording(double precision[], text, timestamptz, uuid, double precision[])
  to authenticated;

-- Höhen nachtragen (Patch 003, Issue #16): Eine eigene Aufzeichnung
-- ohne Höhen bekommt sie aus der Originaldatei, statt dass ein zweiter
-- Import eine zweite Aufzeichnung anlegt. Kein Abgleich, kein neuer
-- Trail, keine Kante, nicht im Tageslimit.
--
-- Der Client schickt die GESPEICHERTE Linie zurück — deren Punkte sind
-- Originalpunkte der Datei, er findet sie dort samt Höhe — und hier muss
-- sie Punkt für Punkt dieselbe sein (≤ 5 cm; `st_asgeojson` rundet auf
-- neun Stellen). Nicht „eine Linie in der Nähe": sonst ließen sich
-- beliebige Höhen an fremde Stellen hängen. Neu vereinfachen ginge
-- nicht, weil 0.3.0 die Vereinfachung dreidimensional gemacht hat.
--
-- Gibt true zurück, wenn geschrieben wurde, false, wenn die Aufzeichnung
-- schon Höhen hat (Wiederholung nach einem Abriss: kein Fehler, aber
-- auch kein Überschreiben).
create or replace function public.attach_elevation(
  recording_id uuid,
  coords double precision[],
  eles double precision[])
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid := auth.uid();
  stored geometry;
  stored_ele real[];
  npts integer;
begin
  if uid is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  select r.geom::geometry, r.ele into stored, stored_ele
    from trail_recordings r
   where r.id = attach_elevation.recording_id and r.user_id = uid
     for update;
  if not found then
    -- Fremd oder gelöscht: dieselbe Antwort, damit die Funktion nicht
    -- verrät, ob es eine fremde Aufzeichnung mit dieser Kennung gibt.
    raise exception 'Keine eigene Aufzeichnung' using errcode = 'P0002';
  end if;
  if stored_ele is not null then
    return false;
  end if;
  npts := coalesce(array_length(coords, 1), 0);
  if npts % 2 <> 0 or npts / 2 <> st_npoints(stored) then
    raise exception 'Linie passt nicht: % Punkte für % gespeicherte', npts / 2, st_npoints(stored)
      using errcode = '22023';
  end if;
  if coalesce(array_length(eles, 1), 0) <> npts / 2
     or array_position(eles, null) is not null
     or exists (select 1 from unnest(eles) e where e not between -500 and 9000) then
    raise exception 'Höhen: eine je Punkt, zwischen −500 und 9000 m' using errcode = '22023';
  end if;
  if exists (
    select 1 from generate_series(1, npts / 2) i
     where not st_dwithin(st_pointn(stored, i)::geography,
                          st_setsrid(st_makepoint(coords[2 * i - 1], coords[2 * i]), 4326)::geography,
                          0.05)) then
    raise exception 'Die Linie ist nicht die gespeicherte' using errcode = '22023';
  end if;
  update trail_recordings r
     set ele = array(select e::real from unnest(eles) with ordinality u(e, o) order by o)
   where r.id = attach_elevation.recording_id;
  return true;
end $$;

revoke all on function public.attach_elevation(uuid, double precision[], double precision[])
  from public, anon;
grant execute on function public.attach_elevation(uuid, double precision[], double precision[])
  to authenticated;

-- Buddy-Suche: exakte E-Mail oder Username-Präfix; gibt nie E-Mails zurück.
create or replace function public.search_profiles(query text)
returns table (id uuid, username text, display_name text, avatar int)
language sql stable security definer set search_path = public as $$
  select p.id, p.username, p.display_name, p.avatar
  from profiles p
  left join auth.users u on u.id = p.id
  where p.id <> auth.uid()
    and (lower(u.email) = lower(query) or p.username ilike query || '%')
  limit 10;
$$;
-- Nur für Angemeldete: für anon wäre der exakte E-Mail-Vergleich ein
-- E-Mail-Orakel (verrät ohne Konto, ob eine Adresse registriert ist).
revoke all on function public.search_profiles(text) from public, anon;
grant execute on function public.search_profiles(text) to authenticated;

-- Konto-Löschung durch den Nutzer selbst (Play-Anforderung). Alle Tabellen
-- hängen per `on delete cascade` an profiles und profiles an auth.users —
-- das Löschen des Auth-Users räumt daher alles mit ab. Trails ohne
-- verbleibenden Beitrag holt sweep_orphan_trails.
-- Kein Parameter: auth.uid() kommt aus dem JWT, eine übergebene id wäre eine
-- Einladung, fremde Konten zu löschen.
create or replace function public.delete_own_account()
returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;
revoke all on function public.delete_own_account() from public, anon;
grant execute on function public.delete_own_account() to authenticated;

-- Den eigenen Beitrag zu einem Trail zurückziehen (Konzept 4, „Löschen
-- und DSGVO"): eigene Aufzeichnungen, eigene Hinweise, eigene
-- Meldungen (seit Patch 013) und der eigene Beitrag, in EINER
-- Transaktion. Einzeln aus der App wäre es nicht
-- dasselbe: Fällt zuerst der Beitrag, steht „privat" nicht mehr da
-- (`contributor_shares` sagt ohne Zeile „teilt"), und die eigenen
-- Aufzeichnungen und Hinweise wären bis zum nächsten Schritt für Buddys
-- sichtbar; bricht es mittendrin ab, bliebe ein halber Beitrag stehen.
-- Der Trail selbst bleibt, solange ein anderer ihn belegt; ohne jeden
-- Beleg holt ihn `sweep_orphan_trails` (nächtlich).
--
-- Security INVOKER: Die RLS erlaubt jede der Löschungen ohnehin
-- (recordings_delete_own, td_owner_all, notes_delete,
-- reports_delete_own) — die Funktion
-- braucht keine Rechte darüber hinaus, nur die gemeinsame Transaktion.
-- Gibt die Zahl der gelöschten Aufzeichnungen zurück.
create or replace function public.withdraw_contribution(trail_id uuid)
returns integer
language plpgsql security invoker set search_path = public as $$
declare
  uid uuid := auth.uid();
  n integer;
begin
  if uid is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  delete from trail_recordings r
   where r.trail_id = withdraw_contribution.trail_id and r.user_id = uid;
  get diagnostics n = row_count;
  delete from trail_notes t
   where t.trail_id = withdraw_contribution.trail_id and t.user_id = uid;
  delete from trail_reports m
   where m.trail_id = withdraw_contribution.trail_id and m.user_id = uid;
  delete from trail_details d
   where d.trail_id = withdraw_contribution.trail_id and d.user_id = uid;
  return n;
end $$;

revoke all on function public.withdraw_contribution(uuid) from public, anon;
grant execute on function public.withdraw_contribution(uuid) to authenticated;

-- Melden (Patch 013, #101): eine Meldung („offen", „gesperrt" …) und/oder
-- einen Zustand 1–5 zu einem Trail, den der Aufrufer SIEHT — gefahren
-- haben muss er ihn nicht (Rework, Abschnitt 9: wer die Hausrunde nie
-- aufgezeichnet hat, soll trotzdem melden können). Bestätigt ist die
-- Angabe, wenn er ihn gefahren hat (has_ridden) oder die App ihn vor Ort
-- sah ([on_site], ≤ 200 m zur Linie, auf dem Gerät geprüft). Vom „vor
-- Ort" bleibt nur das Ergebnis — keine Position, kein Merkmal.
--
-- Definer, weil `confirmed` sonst der Client setzen könnte; darum auch
-- kein insert-Grant auf trail_reports. [reported_at] kommt vom Gerät
-- (Ausgangskorb) und wird auf now() gekappt — eine Zeit in der Zukunft
-- gewönne sonst jeden Vergleich. [client_id] macht die Wiedervorlage
-- idempotent.
create or replace function public.report_trail(
  trail_id uuid,
  status text default null,
  condition integer default null,
  on_site boolean default false,
  reported_at timestamptz default null,
  client_id uuid default null)
returns void
language plpgsql security definer set search_path = public, app_internal as $$
declare
  uid uuid := auth.uid();
  conf boolean;
begin
  if uid is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  if report_trail.status is null and report_trail.condition is null then
    raise exception 'Weder Meldung noch Zustand' using errcode = '22023';
  end if;
  if report_trail.trail_id is null
     or not app_internal.can_see_trail(uid, report_trail.trail_id) then
    raise exception 'Trail nicht sichtbar' using errcode = '42501';
  end if;
  -- Schutz gegen Fluten, kein gemessener Wert: 200 Zeilen in 24 h liegen
  -- weit über jedem echten Gebrauch (derselbe Code wie das Tageslimit der
  -- Aufzeichnungen, die App kennt ihn schon).
  if (select count(*) from trail_reports m
       where m.user_id = uid and m.created_at > now() - interval '1 day') >= 200 then
    raise exception 'Tageslimit von 200 Meldungen erreicht' using errcode = '54000';
  end if;
  conf := coalesce(report_trail.on_site, false)
          or app_internal.has_ridden(uid, report_trail.trail_id);
  if report_trail.status is not null then
    perform app_internal.put_report(uid, report_trail.trail_id, 'status', report_trail.status,
                                    null, conf, report_trail.reported_at, report_trail.client_id);
  end if;
  if report_trail.condition is not null then
    perform app_internal.put_report(uid, report_trail.trail_id, 'condition', null,
                                    report_trail.condition, conf, report_trail.reported_at,
                                    report_trail.client_id);
  end if;
end $$;

revoke all on function public.report_trail(uuid, text, integer, boolean, timestamptz, uuid) from public, anon;
grant execute on function public.report_trail(uuid, text, integer, boolean, timestamptz, uuid) to authenticated;

-- ============================================================
-- Sicht für den Client: Aufzeichnungen als GeoJSON
-- ============================================================
-- PostgREST gäbe die geography als WKB-Hex zurück; die App will GeoJSON
-- und die Länge. `security_invoker`: Die RLS der Tabelle gilt weiter, die
-- Sicht öffnet nichts. Was auf der Karte steht, rechnet der Client aus
-- dieser Liste (beste sichtbare Aufzeichnung je trail_id, Abschnitt 3).
create view public.recordings_visible
with (security_invoker = true) as
  select id, trail_id, user_id, source, recorded_at, reversed, quality, created_at,
         st_asgeojson(geom::geometry) as geojson,
         st_length(geom) as length_m,
         ele
    from public.trail_recordings;

-- ============================================================
-- Row Level Security
-- ============================================================

alter table public.profiles          enable row level security;
alter table public.friendships       enable row level security;
alter table public.friend_aliases    enable row level security;
alter table public.feedback          enable row level security;
alter table public.error_reports     enable row level security;
alter table public.app_config        enable row level security;
alter table public.trails            enable row level security;
alter table public.trail_recordings  enable row level security;
alter table public.trail_details     enable row level security;
alter table public.trail_notes       enable row level security;
alter table public.trail_reports     enable row level security;
alter table app_internal.trail_overlaps enable row level security;
alter table public.push_devices      enable row level security;
alter table app_internal.push_outbox    enable row level security;

-- Ausdrücklich gesperrt (PilzBuddy Patch 037): RLS ohne Policy verweigert
-- ohnehin alles, aber der Security Advisor meldet es dauerhaft, und
-- dismissen lässt es sich im Dashboard nicht. Benutzt wird beides nur vom
-- Eigentümer (Definer-RPC, Aufräumjob), der RLS umgeht.
create policy trails_no_client on public.trails
  for all to anon, authenticated using (false) with check (false);
create policy trail_overlaps_no_client on app_internal.trail_overlaps
  for all to anon, authenticated using (false) with check (false);
create policy push_outbox_no_client on app_internal.push_outbox
  for all to anon, authenticated using (false) with check (false);

-- push_devices (Patch 008): nur die eigenen Geräte, in beide Richtungen —
-- ohne das `with check` könnte jemand ein Token auf ein fremdes Konto
-- schreiben und dessen Meldungen mitbekommen. Für den Versender keine
-- Policy: Er liest mit service_role und umgeht RLS.
create policy push_devices_own_all on public.push_devices for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- profiles: ich selbst + alle, mit denen eine (auch offene) Freundschaft
-- besteht (Suche läuft über search_profiles)
create policy profiles_select on public.profiles for select
  using (id = auth.uid() or app_internal.involved_in_friendship(id, auth.uid()));
create policy profiles_update on public.profiles for update
  using (id = auth.uid()) with check (id = auth.uid());

-- friendships
create policy fr_select on public.friendships for select
  using (requester_id = auth.uid() or addressee_id = auth.uid());
create policy fr_insert on public.friendships for insert
  with check (requester_id = auth.uid() and status = 'pending');
create policy fr_accept on public.friendships for update
  using (addressee_id = auth.uid() and status = 'pending')
  with check (status = 'accepted');
create policy fr_delete on public.friendships for delete   -- ablehnen / zurückziehen / entfreunden
  using (requester_id = auth.uid() or addressee_id = auth.uid());

-- friend_aliases: alles nur für den Besitzer; anlegen und ändern nur für
-- bestätigte Buddys.
create policy fa_select on public.friend_aliases for select
  using (owner_id = auth.uid());
create policy fa_insert on public.friend_aliases for insert
  with check (owner_id = auth.uid()
    and app_internal.are_friends(owner_id, friend_id));
create policy fa_update on public.friend_aliases for update
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid()
    and app_internal.are_friends(owner_id, friend_id));
create policy fa_delete on public.friend_aliases for delete
  using (owner_id = auth.uid());

-- feedback: eigene Wünsche einreichen und nachlesen
create policy feedback_insert on public.feedback for insert
  with check (user_id = auth.uid());
create policy feedback_select_own on public.feedback for select
  using (user_id = auth.uid());

-- error_reports: schreiben darf jeder, auch anon — sonst fehlen genau die
-- Fehler aus Login und Registrierung. Eine fremde user_id lässt sich nicht
-- unterschieben. LESEN darf niemand über die API: es gibt bewusst keine
-- select-Policy, die Auswertung läuft über das Dashboard.
create policy er_insert on public.error_reports for insert
  with check (user_id is null or user_id = auth.uid());

-- app_config: lesen darf jeder, auch anon — die Mindestversion wird beim
-- Start und damit vor der Anmeldung geprüft. Geändert wird der Wert über
-- einen Patch, deshalb kein insert/update/delete-Grant.
create policy app_config_read on public.app_config for select using (true);

-- trail_recordings — DIE Sichtbarkeitsregel (Abschnitt 3), formal:
-- „U sieht T, wenn es eine Aufzeichnung zu T von U gibt, oder eine von
-- einem Buddy B, dessen Beitrag zu T die Sichtbarkeit `buddies` hat."
-- Kein insert und kein update über die API: Schreiben geht nur durch
-- contribute_recording, denn nur dort läuft der Abgleich. Löschen darf
-- man die eigenen (Abschnitt 3, „Löschen und DSGVO").
create policy recordings_select on public.trail_recordings for select
  using (user_id = auth.uid()
     or (app_internal.are_friends(user_id, auth.uid())
         and app_internal.contributor_shares(user_id, trail_id)));
create policy recordings_delete_own on public.trail_recordings for delete
  using (user_id = auth.uid());

-- trail_details: der eigene Beitrag ganz; fremde nur von Buddys und nur,
-- wenn sie ihn teilen. `visibility = 'private'` nimmt damit BEIDES aus
-- der Sicht des Buddys: die Aufzeichnungen (über contributor_shares) und
-- den Beitrag selbst.
create policy td_owner_all on public.trail_details for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy td_friend_select on public.trail_details for select
  using (user_id <> auth.uid()
     and visibility = 'buddies'
     and app_internal.are_friends(user_id, auth.uid()));

-- trail_notes (Patch 005): sehen der Autor und seine direkten Buddys,
-- die den Trail selbst sehen (nicht, wenn der Autor dort „privat" steht);
-- schreiben jeder, der den Trail sieht; entfernen jeder, der den Hinweis
-- sieht — wer am Trail steht, soll „erledigt" sagen können. Kein update:
-- ein korrigierter Hinweis ist ein neuer, sonst stimmte sein Alter nicht.
create policy notes_select on public.trail_notes for select
  using (user_id = auth.uid()
     or (app_internal.are_friends(user_id, auth.uid())
         and app_internal.contributor_shares(user_id, trail_id)
         and app_internal.can_see_trail(auth.uid(), trail_id)));
create policy notes_insert on public.trail_notes for insert
  with check (user_id = auth.uid()
     and app_internal.can_see_trail(auth.uid(), trail_id));
create policy notes_delete on public.trail_notes for delete
  using (user_id = auth.uid()
     or (app_internal.are_friends(user_id, auth.uid())
         and app_internal.contributor_shares(user_id, trail_id)
         and app_internal.can_see_trail(auth.uid(), trail_id)));

-- trail_reports (Patch 013): sehen wie die Hinweise — der Meldende und
-- seine direkten Buddys, die den Trail selbst sehen, nicht bei „privat".
-- Schreiben nur über report_trail() (kein insert-Grant), löschen die
-- eigenen (withdraw_contribution, Kontolöschung per Cascade).
create policy reports_select on public.trail_reports for select
  using (user_id = auth.uid()
     or (app_internal.are_friends(user_id, auth.uid())
         and app_internal.contributor_shares(user_id, trail_id)
         and app_internal.can_see_trail(auth.uid(), trail_id)));
create policy reports_delete_own on public.trail_reports for delete
  using (user_id = auth.uid());

-- ============================================================
-- Grants — ausdrücklich, nicht über auto_expose
-- ============================================================
-- Die Legacy-Vorgabe `auto_expose_new_tables` (config.toml, fällt am
-- 2026-10-30) gäbe anon und authenticated auf jeder Tabelle alle Rechte.
-- Deshalb ERST alles weg, dann gezielt zurück. anon bekommt genau zwei
-- Dinge: app_config lesen und error_reports schreiben — beides läuft vor
-- der Anmeldung. Alles andere ist für Angemeldete, und `trails` sowie
-- app_internal.* für niemanden (4.6: ein Wächter-Test in
-- tool/schema_check.sh prüft das über die API).
revoke all on all tables in schema public from anon, authenticated;
revoke all on all tables in schema app_internal from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.friendships to authenticated;
grant select, insert, update, delete on public.friend_aliases to authenticated;
grant select on public.app_config to anon, authenticated;
grant insert on public.error_reports to anon, authenticated;
grant insert, select on public.feedback to authenticated;
grant select, delete on public.trail_recordings to authenticated;   -- insert nur per RPC
grant select, insert, update, delete on public.trail_details to authenticated;
grant select, insert, delete on public.trail_notes to authenticated;
grant select, delete on public.trail_reports to authenticated;       -- insert nur per RPC
grant select on public.recordings_visible to authenticated;
grant select, insert, update, delete on public.push_devices to authenticated;
-- KEIN Grant auf public.trails, KEINER auf app_internal.trail_overlaps.

-- Der Feedback-Bot (tool/feedback_bot.py, patch_001) arbeitet mit dem
-- Service-Schlüssel: Feedback lesen und abstempeln, Fehlerberichte nach
-- 90 Tagen löschen. service_role umgeht RLS, aber NICHT fehlende Grants —
-- und ein Projekt ohne automatische Tabellenfreigabe gibt ihm keine von
-- selbst. Ausdrücklich, damit der Bot nicht an einer Vorgabe hängt.
grant select, update on public.feedback to service_role;
grant select, delete on public.error_reports to service_role;
-- send-push (Patch 008) räumt tote Token mit dem Service-Schlüssel ab.
grant select, delete on public.push_devices to service_role;

-- ============================================================
-- Aufräumjobs und Push-Versand (nur wo pg_cron verfügbar ist)
-- ============================================================
-- Supabase hat pg_cron; der nackte Postgres des Matcher-Tests nicht. Ein
-- hartes `create extension pg_cron` bräche dort die Frischinstallation,
-- die diese Datei beweisen soll — deshalb der Umweg über
-- pg_available_extensions und dynamisches SQL (die Referenz auf
-- cron.schedule wird nur aufgelöst, wenn es das Schema gibt).
do $$
begin
  -- pg_net trägt den Push-Versand (Patch 008); auch das nur, wo es das gibt.
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_net;
  end if;
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    execute $cron$select cron.schedule('trails-sweep', '23 3 * * *',
              'select app_internal.sweep_orphan_trails()')$cron$;
    execute $cron$select cron.schedule('notes-sweep', '37 3 * * *',
              'select app_internal.sweep_old_notes()')$cron$;
    execute $cron$select cron.schedule('reports-sweep', '41 3 * * *',
              'select app_internal.sweep_old_reports()')$cron$;
    -- Jede Minute; ohne fällige Zeilen passiert nichts (Patch 008).
    execute $cron$select cron.schedule('push-flush', '* * * * *',
              'select app_internal.push_flush()')$cron$;
  else
    raise notice 'pg_cron nicht verfügbar — sweep_orphan_trails(), sweep_old_notes(), sweep_old_reports() und push_flush() sind nicht eingeplant (lokaler Testlauf).';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Patch-Buchführung
-- ---------------------------------------------------------------------------
-- Dieselbe Tabelle legt auch tool/db_migrate.sh an (`if not exists`) — sie
-- muss dort stehen, weil die Live-Datenbank diese Datei nie im Ganzen sieht.
create table if not exists public.applied_patches (
  filename text primary key,
  applied_at timestamptz not null default now()
);
alter table public.applied_patches enable row level security;
revoke all on table public.applied_patches from anon, authenticated;
-- Sperr-Policy (PilzBuddy Patch 037, Grund siehe trails oben).
create policy applied_patches_no_client on public.applied_patches
  for all to anon, authenticated using (false) with check (false);

-- Saat-Liste. Diese Datei bildet den Stand NACH allen Patches ab, die
-- hier stehen; sie werden bei einer Frischinstallation nur EINGETRAGEN,
-- nicht ausgeführt. Grund (PilzBuddy-Lehre): Ein erneuter Lauf über ein
-- Schema, das ihr Ergebnis schon enthält, verlangte von jedem alten Patch
-- auf Dauer Idempotenz und zwang dazu, alte Patches nachträglich zu
-- ändern — live läuft ein eingespielter Patch aber nie wieder, die
-- Änderung landete also nur in Frischinstallationen, und beide Welten
-- drifteten still auseinander.
--
-- Regel: Ein neuer supabase/patch_NNN_*.sql gehört im selben PR (1) als
-- Datei, (2) in die Struktur oben und (3) HIER in die Liste.
-- tool/patch_guard.sh vergleicht Liste und Dateien und lässt keinen
-- Unterschied durch.
insert into public.applied_patches (filename) values
  ('patch_001_feedback_bot_grants.sql'),
  ('patch_002_recording_elevation.sql'),
  ('patch_003_attach_elevation.sql'),
  ('patch_004_trail_notes.sql'),
  ('patch_005_trail_notes_open.sql'),
  ('patch_006_daily_limit_500.sql'),
  ('patch_007_decode_trail_names.sql'),
  ('patch_008_push.sql'),
  ('patch_009_trail_traits.sql'),
  ('patch_010_withdraw_contribution.sql'),
  ('patch_011_planned_keeps_status.sql'),
  ('patch_012_contribution_link.sql'),
  ('patch_013_rating_reports.sql'),
  ('patch_014_push_content.sql'),
  ('patch_015_planned_ride_date.sql'),
  ('patch_016_two_way.sql'),
  ('patch_017_min_trail_50.sql'),
  ('patch_018_feedback_client_id.sql')
on conflict do nothing;
