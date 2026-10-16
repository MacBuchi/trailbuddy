-- Gibt es schon Daten, an denen sich #106 messen lässt? (Fahrplan #156,
-- Punkt 8.) #114 hat `contribute_recording` bei `limit 1` gelassen, bis
-- Trails MEHRERE Aufzeichnungen tragen — Versionen von Buddys oder wieder
-- gefahrene Stücke aus dem Zerlege-Blatt. Diese Zählung sagt, ob es so
-- weit ist; sie misst den Abgleich nicht selbst (das tut
-- `tool/trail_match.py --simulate` auf Dateien).
--
-- Nur Summen: keine Kennungen, keine Namen, keine Koordinaten — die
-- Ausgabe landet in der Run-Summary eines öffentlichen Repos. Läuft in
-- einer Nur-Lese-Transaktion (`matcher-stats.yml` gegen live, der Dry Run
-- in ci.yml gegen die Wegwerf-Datenbank, damit die Abfrage nicht still
-- veraltet). Ausgabe: Markdown-Tabellenzeilen, mit `psql -At` zu lesen.
\set ON_ERROR_STOP on
\set QUIET on
begin transaction read only;

with per_trail as (
  select trail_id,
         count(*) as n,
         count(distinct user_id) as users,
         count(*) filter (where source = 'app') as app
    from public.trail_recordings
   group by trail_id
),
-- Kanten zwischen zwei Trails, die beide noch Aufzeichnungen tragen.
edges as (
  select o.a, o.b, least(o.coverage_ab, o.coverage_ba) as low,
         greatest(o.coverage_ab, o.coverage_ba) as high
    from app_internal.trail_overlaps o
   where exists (select 1 from per_trail p where p.trail_id = o.a)
     and exists (select 1 from per_trail p where p.trail_id = o.b)
),
rows (ord, label, value) as (values
  (1,  'Nutzer mit Aufzeichnungen',
       (select count(distinct user_id) from public.trail_recordings)),
  (2,  'Aufzeichnungen',
       (select count(*) from public.trail_recordings)),
  (3,  '… davon aus der App (Fahrt)',
       (select count(*) from public.trail_recordings where source = 'app')),
  (4,  '… davon Import mit Zeiten',
       (select count(*) from public.trail_recordings where source = 'import')),
  (5,  '… davon geplant (ohne Zeiten)',
       (select count(*) from public.trail_recordings where source = 'planned')),
  (6,  'Trails mit Aufzeichnungen',
       (select count(*) from per_trail)),
  (7,  'Trails mit genau 1 Aufzeichnung',
       (select count(*) from per_trail where n = 1)),
  (8,  'Trails mit 2 Aufzeichnungen',
       (select count(*) from per_trail where n = 2)),
  (9,  'Trails mit 3 und mehr Aufzeichnungen',
       (select count(*) from per_trail where n >= 3)),
  (10, 'Trails mit Aufzeichnungen von 2+ Nutzern',
       (select count(*) from per_trail where users >= 2)),
  (11, 'Trails mit 2+ Aufzeichnungen, davon 1+ aus der App',
       (select count(*) from per_trail where n >= 2 and app >= 1)),
  (12, 'Höchste Zahl Aufzeichnungen an einem Trail',
       (select coalesce(max(n), 0) from per_trail)),
  (13, 'Kanten (Teil, Enthält, Gabel) zwischen lebenden Trails',
       (select count(*) from edges)),
  (14, '… davon beidseitig ≥ 0,5 gedeckt (Zwillings-Verdacht)',
       (select count(*) from edges where low >= 0.5)),
  (15, '… davon an einem Trail mit 2+ Aufzeichnungen',
       (select count(*) from edges e
         where exists (select 1 from per_trail p
                        where p.trail_id in (e.a, e.b) and p.n >= 2))),
  (16, 'Zusammengeführte Paare (trail_aliases)',
       (select count(*) from app_internal.trail_aliases)),
  (17, 'Als verschieden erklärte Paare (trail_distinct)',
       (select count(*) from app_internal.trail_distinct))
)
select '| ' || label || ' | ' || value || ' |' from rows order by ord;

rollback;
