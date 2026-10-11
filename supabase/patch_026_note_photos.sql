-- Patch 026: ein Foto am Hinweis (#37, Fahrplan #156 Punkt 20).
--
-- > „Baum liegt quer" — und das Bild dazu.
--
-- Entscheidung des Betreibers (2026-10-11): Das Foto hängt am HINWEIS
-- (#7), nicht am Beitrag, und es gibt EINES je Hinweis. Der Hinweis ist
-- das, was sich ändert; ein Bild dazu sagt, wie es dort gerade aussieht.
-- Vorlage ist PilzBuddy Patch 026 (Fundfotos, #532).
--
-- DIE BYTES LIEGEN NICHT IN DIESER TABELLE. Sie gehen in den privaten
-- Bucket `trail-note-photos` (Supabase Storage, eigenes Kontingent —
-- 1 GB auf dem Free-Plan): je Foto ein JPEG mit 1024er Kante (~150 KB)
-- und eine Vorschau mit 200er Kante (~12 KB). Hier steht je Foto eine
-- Zeile mit Schlüssel, Hinweis und Ablauf, rund 200 Byte.
--
-- DIE SICHTBARKEIT WIRD GEERBT. Die Policy für Fremde fragt nur, ob der
-- Hinweis für den Betrachter lesbar ist (`exists (select 1 from
-- trail_notes …)` — `notes_select` aus Patch 005 greift im Subselect);
-- die Storage-Policy fragt nur, ob eine Foto-Zeile lesbar ist. Keine
-- zweite Freigabe, die neben der ersten driften könnte: Wer den Hinweis
-- sieht, sieht das Foto; „privat" am Beitrag, ein beendeter Buddy-Status
-- oder ein entfernter Hinweis („erledigt", Rückzug, Aufräumen) nehmen es
-- mit. Das Zusammenführen (Patch 019) zieht den Hinweis um, das Foto
-- hängt an dessen Kennung und zieht mit.
--
-- DIE FRIST GEHÖRT DER DATENBANK: 90 Tage wie die Hinweise, als Default
-- UND Constraint — ein veränderter Client kann sie nicht verlängern. Der
-- jüngste Hinweis je Autor und Trail überlebt `sweep_old_notes`, sein
-- Foto nicht: Sonst wüchse der Bucket mit der Zahl der Trails statt
-- konstant zu bleiben. Ein Bild vom umgestürzten Baum ist nach drei
-- Monaten ohnehin keine Auskunft mehr.
--
-- Abgeräumt wird vom Feedback-Bot (tool/feedback_bot.py, alle zwei
-- Stunden) per ABGLEICH: abgelaufene Zeilen weg, dann jedes Objekt ohne
-- lebende Zeile — das fängt auch die Zeilen, die per Cascade mit ihrem
-- Hinweis gegangen sind, und Uploads, deren Zeile nie kam.
--
-- DER SCHLÜSSEL BEGINNT MIT DEM NUTZER (`<user_id>/<id>`): Hochladen darf
-- man nur in den eigenen Ordner, und der Constraint sorgt dafür, dass
-- die Zeile keinen fremden Pfad behaupten kann.
--
-- KEIN Bump von minimum_supported_version: rein additiv.
create table public.trail_note_photos (
  id uuid primary key default gen_random_uuid(),
  -- unique: EIN Foto je Hinweis (Betreiber, 2026-10-11).
  note_id uuid not null unique references public.trail_notes(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  -- Pfad im Bucket ohne Endung; Bild unter `<key>.jpg`, Vorschau unter
  -- `<key>_s.jpg`.
  key text not null unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '90 days'),
  constraint trail_note_photos_frist
    check (expires_at <= created_at + interval '90 days'),
  constraint trail_note_photos_key_owner
    check (key like (user_id::text || '/%'))
);
-- Die Policy für Fremde filtert über expires_at, der Bot räumt darüber.
create index trail_note_photos_expires_idx on public.trail_note_photos (expires_at);

alter table public.trail_note_photos enable row level security;
-- Erst alles weg: Die Vorgabe des Stacks gibt anon und authenticated auf
-- jeder neuen Tabelle alle Rechte (im Bestandsweg gemessen: ohne diese
-- Zeile hätte anon hier GRANT ALL, die Frischinstallation nicht).
revoke all on public.trail_note_photos from anon, authenticated;
grant select, insert, delete on public.trail_note_photos to authenticated;
-- Der Feedback-Bot räumt mit dem Service-Schlüssel ab (abgelaufene Zeilen
-- löschen, lebende Schlüssel lesen).
grant select, delete on public.trail_note_photos to service_role;

-- Eigene Zeilen voll verwalten — anlegen nur am EIGENEN Hinweis. Das
-- Foto sagt „so sah es aus, als ICH das schrieb".
create policy tnp_owner_all on public.trail_note_photos for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid()
    and exists (select 1 from public.trail_notes n
                where n.id = note_id and n.user_id = auth.uid()));
-- Fremde Zeilen: solange sie nicht abgelaufen sind und der HINWEIS für
-- mich lesbar ist. Die Freigabe steht nicht hier, sondern in
-- notes_select — das ist der Punkt.
create policy tnp_friend_select on public.trail_note_photos for select
  using (user_id <> auth.uid()
     and expires_at > now()
     and exists (select 1 from public.trail_notes n where n.id = note_id));

-- ---------------------------------------------------------------------------
-- Der Bucket und seine Policies. Privat: Es gibt keine öffentliche URL,
-- jeder Abruf läuft mit Token durch die Policies unten.
-- ---------------------------------------------------------------------------
-- Größe und Typ als Riegel des Servers: Der Client schickt zwei JPEGs
-- (≤ 1024 px bei Qualität 80, ~150 KB); ein Client, der etwas anderes
-- schickt, ist nicht unserer.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('trail-note-photos', 'trail-note-photos', false, 600000, array['image/jpeg'])
on conflict (id) do nothing;

-- Hochladen: nur in den eigenen Ordner. `storage.foldername` zerlegt den
-- Pfad; das erste Glied ist die Nutzer-id.
create policy note_photos_upload on storage.objects for insert
  to authenticated
  with check (bucket_id = 'trail-note-photos'
    and (storage.foldername(name))[1] = auth.uid()::text);
-- Lesen: genau die Objekte, zu denen ich eine Zeile sehe — eigene immer,
-- fremde nur mit lesbarem Hinweis und vor dem Ablauf. Ein Objekt ohne
-- Zeile ist für niemanden lesbar, auch nicht für den, der es hochlud;
-- deshalb erst die Objekte, dann die Zeile.
create policy note_photos_read on storage.objects for select
  to authenticated
  using (bucket_id = 'trail-note-photos'
    and exists (select 1 from public.trail_note_photos p
                where name in (p.key || '.jpg', p.key || '_s.jpg')));
-- Löschen: eigener Ordner. Der Bot löscht mit dem Service-Schlüssel,
-- an den Policies vorbei.
create policy note_photos_remove on storage.objects for delete
  to authenticated
  using (bucket_id = 'trail-note-photos'
    and (storage.foldername(name))[1] = auth.uid()::text);
