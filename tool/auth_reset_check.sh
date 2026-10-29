#!/usr/bin/env bash
# End-to-end check of the auth flows against a real GoTrue in the local
# Supabase stack (started by the Schema Dry Run job):
#   sign up → confirm the address with the code from the mail
#           → request a reset code → redeem it → sign in with the new one
#           → change the password from a signed-in session
#           → change the e-mail address (two codes, two mailboxes).
#
# Why this exists as its own check: the widget tests run against fakes and
# can only prove the app's own logic. Everything that makes this flow
# fragile lives outside them — that the recovery mail carries a six-digit
# token and no link, that verifyOTP accepts it, and above all that
# updateUser is allowed immediately afterwards even though
# "Secure password change" is on (supabase/config.toml mirrors that
# dashboard setting, so this runs under production's rules). That last one
# is the reason the flow could quietly stop working after a Supabase
# upgrade, and nothing else in CI would notice.
#
# The mail template is supabase/templates/recovery.html — the versioned
# copy of the dashboard template. If someone changes the dashboard back to
# a link, this check keeps passing (it only sees the local copy); that
# blind spot is the operator's, not CI's, and is noted in CLAUDE.md.
#
# Taken over from PilzBuddy unchanged in logic: it depends only on GoTrue,
# Mailpit, the ports from supabase/config.toml and the mail subjects there.
# Ports: TrailBuddy's block 5452x.
set -euo pipefail

URL="${SUPABASE_URL:-http://127.0.0.1:54521}"
MAIL="${MAILPIT_URL:-http://127.0.0.1:54524}"
KEY="${SUPABASE_KEY:-$(supabase status -o json 2>/dev/null | jq -r '.ANON_KEY')}"
if [ -z "$KEY" ] || [ "$KEY" = "null" ]; then
  echo "::error::Kein anon-Key — läuft der lokale Stack (supabase start)?"
  exit 1
fi

EMAIL="resettest-$RANDOM$RANDOM@example.org"
USERNAME="resettest$RANDOM"
OLD='AlterTrail#2026!'
NEW='NeuerTrail#2026!'
hdr=(-H "apikey: $KEY" -H "Content-Type: application/json")

fail() { echo "::error::Passwort-Reset-Prüfung fehlgeschlagen: $1"; exit 1; }

# Holt eine Mail an den Empfänger (Vorgabe: $EMAIL), deren Betreff das
# Muster enthält. Nach Betreff statt „die neueste": Mit Bestätigungspflicht
# liegen mehrere Mails im Postfach, und die falsche zu nehmen macht den
# Test zum Zufallsspiel. Der Empfänger ist ein Parameter, weil der
# E-Mail-Wechsel an die NEUE Adresse schreibt.
fetch_mail() {
  local pattern="$1" recipient="${2:-$EMAIL}" id=""
  for _ in $(seq 1 30); do
    id=$(curl -s "$MAIL/api/v1/search?query=to:$recipient" \
      | jq -r --arg p "$pattern" \
        '[.messages[] | select(.Subject | test($p))] | .[0].ID // empty')
    [ -n "$id" ] && break
    sleep 1
  done
  [ -n "$id" ] || return 1
  curl -s "$MAIL/api/v1/message/$id" | jq -r '.HTML'
}

# Prüft, dass eine Mail den Code zeigt und keinen Link — der wäre an das
# anfordernde Gerät gebunden (PKCE) und stürbe im Browser.
code_from() {
  local body="$1" what="$2" code
  code=$(printf '%s' "$body" | grep -oE '[0-9]{6}' | head -1)
  [ -n "$code" ] || fail "kein sechsstelliger Code in der $what — zeigt die Vorlage {{ .Token }}?"
  if printf '%s' "$body" | grep -qi 'auth/v1/verify'; then
    fail "die $what enthält einen Link — die Vorlage darf nur den Code zeigen"
  fi
  printf '%s' "$code"
}

signup=$(curl -s "$URL/auth/v1/signup" "${hdr[@]}" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$OLD\",\"data\":{\"username\":\"$USERNAME\"}}")
grep -q '"id"' <<<"$signup" || fail "Konto konnte nicht angelegt werden: $signup"
# Mit Bestätigungspflicht darf signUp KEINE Sitzung liefern — genau darauf
# stützt sich der Registrieren-Screen (Muster PilzBuddy).
grep -q '"access_token"' <<<"$signup" \
  && fail "signUp lieferte eine Sitzung — ist enable_confirmations aus? Der Registrieren-Screen erwartet die Bestätigung."
echo "✓ Testkonto angelegt, noch ohne Sitzung"

confirm_body=$(fetch_mail 'bestätige|Willkommen') \
  || fail "keine Bestätigungsmail eingetroffen (Mailpit unter $MAIL)"
confirm_code=$(code_from "$confirm_body" "Bestätigungsmail")
echo "✓ Bestätigungsmail enthält einen Code und keinen Link"

confirmed=$(curl -s "$URL/auth/v1/verify" "${hdr[@]}" \
  -d "{\"type\":\"signup\",\"email\":\"$EMAIL\",\"token\":\"$confirm_code\"}" \
  | jq -r '.access_token // empty')
[ -n "$confirmed" ] || fail "Bestätigungs-Code wurde nicht akzeptiert"
echo "✓ Adresse bestätigt, Sitzung kam direkt mit"

status=$(curl -s -o /dev/null -w '%{http_code}' "$URL/auth/v1/recover" "${hdr[@]}" \
  -d "{\"email\":\"$EMAIL\"}")
[ "$status" = "200" ] || fail "recover antwortete mit HTTP $status"
echo "✓ Reset-Code angefordert"

body=$(fetch_mail 'zurücksetzen|Zurücksetzen') \
  || fail "keine Reset-Mail eingetroffen (Mailpit unter $MAIL)"
code=$(code_from "$body" "Reset-Mail")
echo "✓ Reset-Mail enthält einen Code und keinen Link"

verify=$(curl -s "$URL/auth/v1/verify" "${hdr[@]}" \
  -d "{\"type\":\"recovery\",\"email\":\"$EMAIL\",\"token\":\"$code\"}")
token=$(jq -r '.access_token // empty' <<<"$verify")
[ -n "$token" ] || fail "Code wurde nicht akzeptiert: $verify"
echo "✓ Code eingelöst"

reset_out=$(mktemp)
status=$(curl -s -o "$reset_out" -w '%{http_code}' -X PUT "$URL/auth/v1/user" \
  "${hdr[@]}" -H "Authorization: Bearer $token" -d "{\"password\":\"$NEW\"}")
[ "$status" = "200" ] \
  || fail "neues Passwort abgelehnt (HTTP $status): $(cat "$reset_out"). Gilt die Recovery-Sitzung nicht mehr als frische Anmeldung? Dann braucht die App reauthenticate()."
echo "✓ Neues Passwort gesetzt, obwohl secure_password_change an ist"

new=$(curl -s "$URL/auth/v1/token?grant_type=password" "${hdr[@]}" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$NEW\"}" | jq -r '.access_token // empty')
[ -n "$new" ] || fail "Anmeldung mit dem neuen Passwort schlug fehl"
old=$(curl -s "$URL/auth/v1/token?grant_type=password" "${hdr[@]}" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$OLD\"}" | jq -r '.error_code // empty')
[ "$old" = "invalid_credentials" ] || fail "das alte Passwort gilt noch ($old)"
echo "✓ Neues Passwort gilt, altes nicht mehr"

# Der Fehlercode, auf den resetErrorMessage() in lib/core/errors.dart baut.
bad=$(curl -s "$URL/auth/v1/verify" "${hdr[@]}" \
  -d "{\"type\":\"recovery\",\"email\":\"$EMAIL\",\"token\":\"000000\"}" \
  | jq -r '.error_code // empty')
[ "$bad" = "otp_expired" ] \
  || fail "falscher Code liefert '$bad' statt 'otp_expired' — die Meldung in lib/core/errors.dart passt dann nicht mehr"
echo "✓ Falscher Code wird als otp_expired abgelehnt"

# --- Passwort ändern durch Angemeldete ---------------------------------------
# AuthRepository.changePassword meldet sich zuerst mit dem aktuellen Passwort
# neu an und ändert danach — genau diese Reihenfolge steht hier. Sie ist der
# ganze Trick: „Secure password change" verlangt eine frische
# Authentifizierung, und die frische Anmeldung liefert sie. Kürzt jemand den
# Schritt weg, fällt es live als 403 auf und sonst nirgends.
#
# Bewusst NICHT geprüft: dass eine „alte" Sitzung abgelehnt wird. Jede
# Sitzung, die dieses Skript erzeugen kann, ist frisch — der Test wäre ein
# Zufallsgenerator.
THIRD='DritterTrail#2026!'
change_out=$(mktemp)
status=$(curl -s -o "$change_out" -w '%{http_code}' -X PUT "$URL/auth/v1/user" \
  "${hdr[@]}" -H "Authorization: Bearer $new" -d "{\"password\":\"$THIRD\"}")
[ "$status" = "200" ] \
  || fail "Passwortwechsel nach frischer Anmeldung abgelehnt (HTTP $status): $(cat "$change_out"). Dann reicht signInWithPassword nicht mehr als frische Authentifizierung und AuthRepository.changePassword braucht reauthenticate()."
echo "✓ Passwortwechsel nach frischer Anmeldung angenommen"

third=$(curl -s "$URL/auth/v1/token?grant_type=password" "${hdr[@]}" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$THIRD\"}" | jq -r '.access_token // empty')
[ -n "$third" ] || fail "Anmeldung mit dem geänderten Passwort schlug fehl"
gone=$(curl -s "$URL/auth/v1/token?grant_type=password" "${hdr[@]}" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$NEW\"}" | jq -r '.error_code // empty')
[ "$gone" = "invalid_credentials" ] \
  || fail "das vorige Passwort gilt nach dem Wechsel noch ($gone)"
echo "✓ Geändertes Passwort gilt, das vorige nicht mehr"

# Nur zur Information: Ob GoTrue ein unverändertes Passwort mit
# `same_password` ablehnt, hängt an der Plattform-Einstellung. Die App bildet
# den Code ab (changePasswordErrorMessage) — hier nur protokollieren, statt
# einen Lauf daran scheitern zu lassen.
same=$(curl -s -X PUT "$URL/auth/v1/user" "${hdr[@]}" \
  -H "Authorization: Bearer $third" -d "{\"password\":\"$THIRD\"}" \
  | jq -r '.error_code // "akzeptiert"')
echo "ℹ Unverändertes Passwort meldet: $same (App erwartet same_password)"

# --- E-Mail ändern -----------------------------------------------------------
# Gemessen 2026-08-05 gegen echtes GoTrue: updateUser(email) verschickt mit
# double_confirm_changes ZWEI Mails mit je eigenem Code (alte und neue
# Adresse, beide aus der email_change-Vorlage). Der erste eingelöste Code
# wird nur quittiert („proceed to confirm … other email"), die Adresse
# bleibt; erst der zweite vollzieht den Wechsel und liefert eine FRISCHE
# Sitzung. AuthRepository.changeEmail baut exakt auf diese Reihenfolge —
# ändert eine GoTrue-Version sie, fällt es hier auf und nicht live.
NEWMAIL="gewechselt-$RANDOM$RANDOM@example.org"
email_out=$(mktemp)
status=$(curl -s -o "$email_out" -w '%{http_code}' -X PUT "$URL/auth/v1/user" \
  "${hdr[@]}" -H "Authorization: Bearer $third" -d "{\"email\":\"$NEWMAIL\"}")
[ "$status" = "200" ] \
  || fail "E-Mail-Wechsel nicht angestoßen (HTTP $status): $(cat "$email_out")"
echo "✓ E-Mail-Wechsel angestoßen"

old_body=$(fetch_mail 'neue Adresse' "$EMAIL") \
  || fail "keine Wechsel-Mail an die ALTE Adresse (double_confirm_changes aus?)"
old_code=$(code_from "$old_body" "Wechsel-Mail an die alte Adresse")
new_body=$(fetch_mail 'neue Adresse' "$NEWMAIL") \
  || fail "keine Wechsel-Mail an die NEUE Adresse"
new_code=$(code_from "$new_body" "Wechsel-Mail an die neue Adresse")
[ "$old_code" != "$new_code" ] \
  || fail "beide Wechsel-Mails tragen denselben Code — dann schützt die zweite nichts"
echo "✓ Zwei Wechsel-Mails, verschiedene Codes, ohne Link"

first=$(curl -s "$URL/auth/v1/verify" "${hdr[@]}" \
  -d "{\"type\":\"email_change\",\"email\":\"$EMAIL\",\"token\":\"$old_code\"}")
grep -qi 'proceed' <<<"$first" \
  || fail "erster Wechsel-Code nicht angenommen: $first"
mid=$(curl -s "$URL/auth/v1/user" "${hdr[@]}" -H "Authorization: Bearer $third" \
  | jq -r '.email')
[ "$mid" = "$EMAIL" ] \
  || fail "Adresse schon nach EINEM Code umgestellt — ein gestohlenes Postfach dürfte das Konto so allein umziehen"
echo "✓ Ein Code allein ändert nichts"

changed=$(curl -s "$URL/auth/v1/verify" "${hdr[@]}" \
  -d "{\"type\":\"email_change\",\"email\":\"$NEWMAIL\",\"token\":\"$new_code\"}" \
  | jq -r '.access_token // empty')
[ -n "$changed" ] || fail "zweiter Wechsel-Code wurde nicht akzeptiert"
final=$(curl -s "$URL/auth/v1/user" "${hdr[@]}" -H "Authorization: Bearer $changed" \
  | jq -r '.email')
[ "$final" = "$NEWMAIL" ] \
  || fail "Adresse nach beiden Codes nicht umgestellt ($final)"
echo "✓ Beide Codes zusammen vollziehen den Wechsel, Sitzung kommt frisch"

# Der typisierte Fehler, auf den emailChangeErrorMessage() baut.
OTHER="belegt-$RANDOM$RANDOM@example.org"
curl -s "$URL/auth/v1/signup" "${hdr[@]}" \
  -d "{\"email\":\"$OTHER\",\"password\":\"$THIRD\",\"data\":{\"username\":\"belegt$RANDOM\"}}" \
  > /dev/null
exists=$(curl -s -X PUT "$URL/auth/v1/user" "${hdr[@]}" \
  -H "Authorization: Bearer $changed" -d "{\"email\":\"$OTHER\"}" \
  | jq -r '.error_code // empty')
[ "$exists" = "email_exists" ] \
  || fail "vergebene Adresse liefert '$exists' statt 'email_exists' — die Meldung in lib/core/errors.dart passt dann nicht mehr"
echo "✓ Vergebene Adresse wird als email_exists abgelehnt"

# Anmelden über Google & Co. (#398): Die App liest `/settings` und zeigt
# je `external.<name>: true` einen Knopf. Die Namen stehen in
# `SignInProvider.key` (lib/data/auth_repository.dart) — benennt GoTrue
# einen um (wie einst linkedin → linkedin_oidc), verschwände der Knopf
# still. Lokal ist jeder Anbieter aus (supabase/config.toml), gemeldet
# werden müssen sie trotzdem.
settings=$(curl -s "$URL/auth/v1/settings" "${hdr[@]}")
for key in $(sed -n "s/^  [a-z]*('\([a-z_]*\)', OAuthProvider\..*/\1/p" lib/data/auth_repository.dart); do
  val=$(echo "$settings" | jq -r --arg k "$key" '.external[$k] | if . == null then "fehlt" else tostring end')
  [ "$val" != "fehlt" ] || fail "GoTrue meldet keinen Anbieter '$key' in /settings — Name in SignInProvider prüfen"
  [ "$val" = "false" ] || fail "Anbieter '$key' ist lokal an ($val) — supabase/config.toml lässt alle aus"
done
[ -n "${key:-}" ] || fail "keine Anbieter aus lib/data/auth_repository.dart gelesen"
echo "✓ /settings meldet jeden Anbieter der App unter seinem Namen"

echo "Registrierung, Passwort-Reset, Passwortwechsel, E-Mail-Wechsel und die Anbieterliste laufen end-to-end gegen echtes GoTrue."
