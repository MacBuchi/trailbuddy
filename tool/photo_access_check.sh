#!/usr/bin/env bash
# End-to-end check of the photos at trail notes (#37, patch 026) against
# the real Storage service of the local Supabase stack (Schema Dry Run):
#
#   Anna and Bernd are buddies, Carla is not. Anna writes a note on her
#   trail and attaches a photo the way the app does — objects first, then
#   the row. Then:
#     - before the row exists, nobody reads the objects (not even Anna),
#     - Anna cannot upload into Bernd's folder,
#     - Bernd reads both objects, Carla reads neither,
#     - Bernd marks the note done ⇒ the row goes (cascade), and so does
#       his access to the bytes,
#     - the feedback bot's sweep (tool/feedback_bot.py) removes exactly
#       the orphaned objects and keeps a live photo.
#
# Why its own check: tool/matcher_check.sql proves the table's RLS, but
# locally storage is only a shim (tool/auth_shim.sql). The policies on
# storage.objects, the upload path through the Storage API and the list
# format the bot depends on only exist in the real service.
#
# Users come from GoTrue's admin API (service key, no mail round trip),
# the trail from contribute_recording via psql — the same set_config
# claims trick as matcher_check.sql. Ports: TrailBuddy's block 5452x.
set -euo pipefail

URL="${SUPABASE_URL:-http://127.0.0.1:54521}"
DB="${SUPABASE_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54522/postgres}"
status_json=$(supabase status -o json 2>/dev/null || echo '{}')
ANON="${SUPABASE_KEY:-$(jq -r '.ANON_KEY // empty' <<<"$status_json")}"
SERVICE="${SUPABASE_SERVICE_ROLE_KEY:-$(jq -r '.SERVICE_ROLE_KEY // empty' <<<"$status_json")}"
if [ -z "$ANON" ] || [ -z "$SERVICE" ]; then
  echo "::error::Kein anon- oder Service-Schlüssel — läuft der lokale Stack (supabase start)?"
  exit 1
fi
BUCKET=trail-note-photos
fail() { echo "::error::Hinweis-Foto-Prüfung fehlgeschlagen: $1"; exit 1; }
ok() { echo "  ✓ $1"; }

tag="$RANDOM$RANDOM"
PASS='FotoTrail#2026!'

# Legt einen bestätigten Nutzer an und gibt "id token" aus.
new_user() {
  local name="$1" email="$1-$tag@example.org" id token
  id=$(curl -s -X POST "$URL/auth/v1/admin/users" \
    -H "apikey: $SERVICE" -H "Authorization: Bearer $SERVICE" -H "Content-Type: application/json" \
    -d "{\"email\":\"$email\",\"password\":\"$PASS\",\"email_confirm\":true,\"user_metadata\":{\"username\":\"$name$tag\"}}" \
    | jq -r '.id // empty')
  [ -n "$id" ] || fail "Nutzer $name nicht angelegt"
  token=$(curl -s -X POST "$URL/auth/v1/token?grant_type=password" \
    -H "apikey: $ANON" -H "Content-Type: application/json" \
    -d "{\"email\":\"$email\",\"password\":\"$PASS\"}" | jq -r '.access_token // empty')
  [ -n "$token" ] || fail "Anmeldung $name gescheitert"
  echo "$id $token"
}

read -r A A_TOKEN < <(new_user anna)
read -r B B_TOKEN < <(new_user bernd)
read -r C C_TOKEN < <(new_user carla)

# Buddys und Trail direkt in der Datenbank — das ist nicht, was hier
# geprüft wird. Die Linie liegt weit weg von den synthetischen Linien
# aus matcher_check.sql (48–50° N, 9° O), damit der Abgleich sie nicht
# an einen fremden Trail hängt.
T=$(psql "$DB" -v ON_ERROR_STOP=1 -qAt <<SQL | tail -1
insert into public.friendships (requester_id, addressee_id, status) values ('$A', '$B', 'accepted');
begin;
select set_config('request.jwt.claims', json_build_object('sub', '$A', 'role', 'authenticated')::text, true);
set local role authenticated;
select public.contribute_recording(
  (select array_agg(v order by o) from (
     select 2 * i - 1 as o, 10.5 + i * 0.0001 as v from generate_series(1, 41) i
     union all
     select 2 * i, 47.3 from generate_series(1, 41) i) s),
  'app', null, null);
commit;
SQL
)
[ -n "$T" ] || fail "kein Trail angelegt"

rest() {  # rest <token> <method> <path> [body] — gibt den Rumpf aus
  local token="$1" method="$2" path="$3" body="${4:-}"
  curl -s -X "$method" "$URL/rest/v1/$path" \
    -H "apikey: $ANON" -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" -H "Prefer: return=representation" \
    ${body:+-d "$body"}
}
# HTTP-Code eines Storage-Aufrufs; der Rumpf landet in $SCRATCH/body.
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT
printf '\xff\xd8\xff\xe0 trailbuddy photo check \xff\xd9' > "$SCRATCH/photo.jpg"
upload() {  # upload <token> <path>
  curl -s -o "$SCRATCH/body" -w '%{http_code}' -X POST "$URL/storage/v1/object/$BUCKET/$2" \
    -H "apikey: $ANON" -H "Authorization: Bearer $1" -H "Content-Type: image/jpeg" \
    --data-binary @"$SCRATCH/photo.jpg"
}
fetch() {  # fetch <token> <path>
  curl -s -o "$SCRATCH/body" -w '%{http_code}' "$URL/storage/v1/object/authenticated/$BUCKET/$2" \
    -H "apikey: $ANON" -H "Authorization: Bearer $1"
}

note_body=$(rest "$A_TOKEN" POST trail_notes "{\"trail_id\":\"$T\",\"user_id\":\"$A\",\"body\":\"Baum liegt quer\"}")
N=$(jq -r '.[0].id // empty' <<<"$note_body")
[ -n "$N" ] || fail "Hinweis nicht angelegt: $note_body"
ok "Anna schreibt einen Hinweis an ihren Trail"

K="$A/$(cat /proc/sys/kernel/random/uuid)"
for f in "$K.jpg" "${K}_s.jpg"; do
  code=$(upload "$A_TOKEN" "$f")
  [ "$code" = 200 ] || fail "Upload $f: HTTP $code $(cat "$SCRATCH/body")"
done
ok "Anna lädt Bild und Vorschau in ihren Ordner"

code=$(upload "$A_TOKEN" "$B/fremd.jpg")
[ "$code" != 200 ] || fail "Anna durfte in Bernds Ordner hochladen"
ok "Anna kann nicht in Bernds Ordner hochladen (HTTP $code)"

code=$(fetch "$A_TOKEN" "$K.jpg")
[ "$code" != 200 ] || fail "ein Objekt ohne Zeile war lesbar"
ok "ohne Zeile liest niemand das Objekt, auch Anna nicht (HTTP $code)"

row=$(rest "$A_TOKEN" POST trail_note_photos "{\"note_id\":\"$N\",\"user_id\":\"$A\",\"key\":\"$K\"}")
[ "$(jq -r '.[0].key // empty' <<<"$row")" = "$K" ] || fail "Foto-Zeile nicht angelegt: $row"
ok "Anna legt die Zeile an"

for f in "$K.jpg" "${K}_s.jpg"; do
  code=$(fetch "$B_TOKEN" "$f")
  [ "$code" = 200 ] || fail "Bernd liest $f nicht: HTTP $code $(cat "$SCRATCH/body")"
  cmp -s "$SCRATCH/body" "$SCRATCH/photo.jpg" || fail "Bernd bekommt andere Bytes für $f"
done
ok "Bernd (Buddy) liest Bild und Vorschau"
code=$(fetch "$C_TOKEN" "$K.jpg")
[ "$code" != 200 ] || fail "Carla (kein Buddy) liest Annas Foto"
ok "Carla liest es nicht (HTTP $code)"

# Ein zweites Foto, das lebt — der Bot darf es nicht anfassen.
note2=$(rest "$A_TOKEN" POST trail_notes "{\"trail_id\":\"$T\",\"user_id\":\"$A\",\"body\":\"Sprung frisch geshapt\"}")
N2=$(jq -r '.[0].id // empty' <<<"$note2")
K2="$A/$(cat /proc/sys/kernel/random/uuid)"
[ "$(upload "$A_TOKEN" "$K2.jpg")" = 200 ] || fail "Upload des zweiten Fotos"
rest "$A_TOKEN" POST trail_note_photos "{\"note_id\":\"$N2\",\"user_id\":\"$A\",\"key\":\"$K2\"}" >/dev/null

# „Erledigt": Bernd entfernt den ersten Hinweis.
rest "$B_TOKEN" DELETE "trail_notes?id=eq.$N" >/dev/null
[ "$(rest "$A_TOKEN" GET "trail_note_photos?note_id=eq.$N&select=key" | jq length)" = 0 ] \
  || fail "die Foto-Zeile überlebt den Hinweis"
code=$(fetch "$B_TOKEN" "$K.jpg")
[ "$code" != 200 ] || fail "nach „erledigt“ liest Bernd das Foto noch"
ok "Hinweis erledigt: Zeile weg, Bernd liest das Foto nicht mehr (HTTP $code)"

# Der Bot räumt ab: die beiden Waisen weg, das lebende Foto bleibt.
BOT_SUPABASE_URL="$URL" SUPABASE_SERVICE_ROLE_KEY="$SERVICE" PHOTO_GRACE_SECONDS=0 \
  python3 tool/feedback_bot.py --sweep-note-photos
listed=$(curl -s -X POST "$URL/storage/v1/object/list/$BUCKET" \
  -H "apikey: $SERVICE" -H "Authorization: Bearer $SERVICE" -H "Content-Type: application/json" \
  -d "{\"prefix\":\"$A\",\"limit\":100,\"offset\":0}" | jq -r '.[].name' | sort | tr '\n' ' ')
[ "$listed" = "${K2#"$A/"}.jpg " ] || fail "nach dem Abräumen liegt in Annas Ordner: '$listed'"
[ "$(fetch "$B_TOKEN" "$K2.jpg")" = 200 ] || fail "das lebende Foto ist nach dem Abräumen nicht mehr lesbar"
ok "der Bot räumt die Waisen ab und lässt das lebende Foto liegen"

echo "photo_access_check: ok"
