# TrailBuddy — Arbeitsregeln für `lib/features/auth/`

Teil der Root-`CLAUDE.md` (dort der Index aller Teildateien).

## Anmelden über Google & Co. (#398)

Sieben Anbieter neben E-Mail und Passwort (Betreiber 2026-10-27: Google,
Microsoft, GitHub, Apple; 2026-10-29: Facebook, Discord, LinkedIn) —
`SignInProvider` in `lib/data/auth_repository.dart`, Knöpfe in
`provider_buttons.dart` unter Login UND Registrierung.

- **Die App zeigt nur, was das Projekt freigibt.** `enabledProviders()`
  liest GoTrues öffentliches `/auth/v1/settings` (`external.<key>`).
  Ab Werk ist live alles aus, der Screen sieht dann aus wie vor #398.
  Einen Anbieter freischalten heißt: Dashboard → Authentication →
  Providers, kein App-Update. Ohne Netz: keine Knöpfe, nur E-Mail.
- **GoTrues Namen ≠ Marken:** Microsoft ist `azure`, LinkedIn
  `linkedin_oidc` (das alte `linkedin` ist abgeschaltet).
  `tool/auth_reset_check.sh` liest die Namen aus dem Enum und verlangt
  jeden in `/settings` des lokalen GoTrue — ein umbenannter Anbieter
  fiele sonst still weg.
- **Rücksprung:** Android `<applicationId>://login-callback` (Manifest:
  Intent-Filter mit `${applicationId}`, also eigene Adresse für die
  Dev-App; `android_manifest_test`), Web die Adresse der App ohne Anfrage
  (`Uri.base.origin + path`), damit Pages und Vorschau je ihr Ziel haben.
  Den Code tauscht `supabase_flutter` selbst (PKCE, `detectSessionInUri`,
  über `app_links`); der Router folgt dem `signedIn`. Android öffnet
  den externen Browser — Google lässt keine Web-Ansicht in der App zu.
- **Dieselbe Adresse = dasselbe Konto:** GoTrue verknüpft eine BESTÄTIGTE
  Adresse automatisch mit dem bestehenden Konto. Microsoft meldet die
  Bestätigung nur mit dem optionalen Claim `xms_edov` (Entra-App →
  Token configuration); ohne ihn entstünde ein zweites Konto oder die
  Anmeldung scheiterte. Microsoft braucht außerdem den Scope `email`
  (setzt `signInWithProvider`).
- **Ein Konto über einen Anbieter hat kein Passwort.** Im Konto stehen
  statt „E-Mail ändern"/„Passwort ändern" (beide verlangen das aktuelle)
  „Angemeldet über …" und der Weg zu einem Passwort („Passwort
  vergessen" — der Code geht an jede Adresse). `externalProvider` gilt
  als E-Mail-Konto, sobald `app_metadata.providers` `email` enthält.
- **Benutzername:** Der Trigger `handle_new_user` nimmt
  `raw_user_meta_data.username` — den setzt kein Anbieter, also
  `trailbuddy_<8 Zeichen>`. `UsernameHint` (in der Hülle) sagt das
  EINMAL je Gerät (`Settings.usernameHintSeen`) mit „Ändern" ins Konto.
  Eine Namenswahl vor der Karte ist vorgemerkt (#422, #156 Stufe 8).
- **Zeichen:** `assets/auth/<name>.svg`, Pfade aus Simple Icons (CC0),
  Google und Microsoft nach ihren Vorgaben. Apple und GitHub einfarbig in
  der Textfarbe (sonst im Dunkeln unsichtbar). Als Reihe aus
  Zeichen-Knöpfen (48 dp hoch, Name im Tooltip und in der Semantik) —
  sieben Knöpfe untereinander schöben das Formular aus dem Bild.
- **Was der Betreiber einrichtet** (je Anbieter eine App beim Anbieter,
  Callback dort immer `https://<projekt>.supabase.co/auth/v1/callback`,
  Client-ID und Secret ins Dashboard):
  - Google Cloud: OAuth-Client „Web application" (Supabase ist der
    Empfänger, nicht die App — keine Android-SHA nötig für diesen Weg);
    Zustimmungsbildschirm mit Datenschutz-Link.
  - Apple: Services ID + Sign-in-with-Apple-Schlüssel (kostenpflichtiges
    Developer-Konto); das Secret läuft nach höchstens 6 Monaten ab.
  - Microsoft Entra: App-Registrierung „persönliche und Organisations-
    konten", Claim `xms_edov`.
  - Facebook (Meta for Developers): App mit „Facebook Login", Prüfung
    durch Meta für `email`; GitHub: OAuth App; Discord: Application →
    OAuth2; LinkedIn: App mit „Sign In with LinkedIn using OpenID
    Connect".
  - Supabase → Authentication → URL Configuration → Redirect URLs:
    `de.mcbuchi.trailbuddy://login-callback`,
    `de.mcbuchi.trailbuddy.dev://login-callback`,
    `https://macbuchi.github.io/trailbuddy/`,
    `https://macbuchi.github.io/trailbuddy-preview/`. Fehlt eine, schickt
    GoTrue still auf die Site URL — die App bliebe auf dem Login.
- **Geprüft wird hier nur die App** (`provider_sign_in_flow_test`,
  `auth_providers_test`): welche Knöpfe, welcher Anbieter, wie das Konto
  danach aussieht. Der echte Durchlauf (Browser, Anbieter, Rücksprung)
  braucht die Anbieter-Apps — 📱 am Gerät und im Browser.
