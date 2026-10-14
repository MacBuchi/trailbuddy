// send-push — verschickt Benachrichtigungen über FCM (#34; Muster
// PilzBuddy #277, dort aus MitFahrBar #101).
//
// **Zwei Aufrufer, zwei Ausweise:**
//
//   1. Der Versand-Job (`app_internal.push_flush`, Patch 008) schickt den
//      Header `x-push-secret` und darf beliebige Nachrichten senden.
//   2. Die App schickt „einmal an dieses Gerät" zum Ausprobieren. Sie hat
//      das Geheimnis NICHT — stattdessen fragt die Function mit dem JWT
//      der Nutzerin, ob das Token ihr gehört. Das beantwortet die RLS auf
//      `push_devices`; eine eigene Prüfung hier wäre eine zweite
//      Wahrheit, die beim ersten Policy-Umbau danebenläge.
//
// `verify_jwt` steht in `config.toml` auf false, weil der Job gar kein
// JWT hat — ein Service-Role-Key ist keines. Die Prüfung passiert deshalb
// hier im Rumpf, beide Wege ausdrücklich.
//
// Das Dienstkonto liegt base64-kodiert in `FCM_SERVICE_ACCOUNT`
// (`supabase secrets set`): Mehrzeiliges JSON scheitert beim Setzen an
// Zeilenumbrüchen und Anführungszeichen.
//
// **Was NIE in eine Nutzlast gehört:** Trailnamen, Benutzernamen,
// Koordinaten, Hinweistexte. Eine Push läuft über Googles Server; der
// Text bleibt neutral, die Einzelheiten holt die App nach dem Antippen
// (Konzept 4: Ein Trail verlässt sein Netz nicht). `route` ist das Ziel
// in der App als FCM-`data` (dort sind nur Zeichenketten erlaubt) — die
// App prüft den Pfad gegen eine Erlaubnisliste.

import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-push-secret',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function respond(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

interface ServiceAccount {
  project_id: string
  client_email: string
  private_key: string
}

function serviceAccount(): ServiceAccount {
  const raw = Deno.env.get('FCM_SERVICE_ACCOUNT')
  if (!raw) throw new Error('missing service account')
  return JSON.parse(new TextDecoder().decode(base64ToBytes(raw)))
}

// Rückgabetyp bewusst mit `<ArrayBuffer>` statt nacktem `Uint8Array`: Das
// ist seit TypeScript 5.7 die Kurzform für `Uint8Array<ArrayBufferLike>`,
// und darin steckt auch `SharedArrayBuffer` — den nimmt
// `crypto.subtle.importKey` nicht an (TS2769).
function base64ToBytes(value: string): Uint8Array<ArrayBuffer> {
  const binary = atob(value.replace(/\s/g, ''))
  return Uint8Array.from(binary, (c) => c.charCodeAt(0))
}

function base64Url(bytes: Uint8Array | string): string {
  const binary = typeof bytes === 'string'
    ? bytes
    : String.fromCharCode(...bytes)
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

// Zugriffstoken für die Laufzeit der Instanz behalten: Sie gelten eine
// Stunde, und ein Signieren je Nachricht wäre reine Rechenzeit.
let cachedToken: { value: string; expires: number } | null = null

async function accessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  if (cachedToken && cachedToken.expires > now + 60) return cachedToken.value

  const header = base64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const claims = base64Url(
    JSON.stringify({
      iss: account.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  )

  // Der private Schlüssel kommt als PEM; für WebCrypto muss der Rumpf raus.
  const pem = account.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
  const key = await crypto.subtle.importKey(
    'pkcs8',
    base64ToBytes(pem),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      'RSASSA-PKCS1-v1_5',
      key,
      new TextEncoder().encode(`${header}.${claims}`),
    ),
  )
  const assertion = `${header}.${claims}.${base64Url(signature)}`

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  })
  if (!response.ok) throw new Error(`token ${response.status}`)
  const payload = await response.json()
  cachedToken = {
    value: payload.access_token,
    expires: now + Number(payload.expires_in ?? 3600),
  }
  return cachedToken.value
}

interface Message {
  token: string
  title: string
  body: string
  /// Wohin ein Tipp führt, `/trail/<id>` oder `/trails` — die App prüft
  /// den Pfad gegen eine Erlaubnisliste, bevor sie ihm folgt.
  route?: string
}

/// Ergebnis je Token: 'ok', 'unregistered' (die Zeile ist tot und gehört
/// weggeräumt) oder 'error'.
async function send(
  account: ServiceAccount,
  bearer: string,
  message: Message,
): Promise<string> {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${bearer}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token: message.token,
          notification: { title: message.title, body: message.body },
          ...(message.route ? { data: { route: message.route } } : {}),
          android: { priority: 'high' },
          // Kein `webpush.fcmOptions.link`: Wohin ein Tipp im Browser
          // führt, weiß nur der Worker — er kennt seine eigene App,
          // Freigabe ODER Vorschau, und nimmt das Ziel aus `route`. Ein
          // fester Link öffnete aus der Vorschau heraus die Freigabe
          // (PilzBuddy 1.203.0).
        },
      }),
    },
  )
  if (response.ok) return 'ok'
  // 404 UNREGISTERED = App deinstalliert oder Token abgelaufen.
  if (response.status === 404) return 'unregistered'
  console.error('fcm', response.status)
  return 'error'
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'POST') return respond(405, { error: 'method not allowed' })

  let payload: { messages?: Message[]; test?: string }
  try {
    payload = await req.json()
  } catch {
    return respond(400, { error: 'invalid json' })
  }

  const expected = Deno.env.get('PUSH_JOB_SECRET')
  const isJob = !!expected && req.headers.get('x-push-secret') === expected

  let messages: Message[]
  if (isJob) {
    messages = payload.messages ?? []
  } else if (payload.test) {
    // Nur an ein EIGENES Gerät. Wir fragen mit dem JWT der Nutzerin, nicht
    // mit service_role — findet die Abfrage nichts, gehört das Token
    // jemand anderem (oder gar niemandem), und die RLS hat das
    // entschieden, nicht dieser Code.
    const authorization = req.headers.get('Authorization')
    if (!authorization) return respond(401, { error: 'unauthorized' })
    const client = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authorization } } },
    )
    const { data } = await client
      .from('push_devices')
      .select('token, locale')
      .eq('token', payload.test)
      .maybeSingle()
    if (!data) return respond(403, { error: 'unknown device' })
    // In der Sprache dieses Geräts (Patch 027, #209), wie push_flush.
    messages = [
      {
        token: payload.test,
        title: 'TrailBuddy',
        body: data.locale === 'en'
          ? 'Test — this is what a notification looks like.'
          : 'Test — so sieht eine Benachrichtigung aus.',
      },
    ]
  } else {
    return respond(401, { error: 'unauthorized' })
  }

  if (messages.length === 0) return respond(200, { results: [] })

  let account: ServiceAccount
  let bearer: string
  try {
    account = serviceAccount()
    bearer = await accessToken(account)
  } catch (error) {
    console.error('fcm auth', (error as Error).message)
    return respond(500, { error: 'fcm auth failed' })
  }

  // Nacheinander statt parallel: Es geht um eine Handvoll Nachrichten je
  // Lauf, und FCM quittiert Bursts aus einer Edge Function mit 429.
  const results: { token: string; status: string }[] = []
  for (const message of messages) {
    results.push({
      token: message.token,
      status: await send(account, bearer, message),
    })
  }

  // Tote Geräte wegräumen. FCM sagt „unregistered", wenn ein Abo
  // erloschen ist (App deinstalliert, Browserdaten gelöscht, Token
  // erneuert). Der Versand-Job wartet die Antwort nicht ab (pg_net ist
  // asynchron) — geschieht es nicht HIER, geschieht es nie (PilzBuddy,
  // 2026-09-24: sieben von neun Einträgen tot, jeder Lauf schickte an
  // alle). Mit dem Service-Schlüssel, weil ein Buddy-Gerät nicht der
  // anfragenden Nutzerin gehört; die Grants dafür stehen in Patch 008.
  const dead = results
    .filter((r) => r.status === 'unregistered')
    .map((r) => r.token)
  if (dead.length > 0) {
    const { error } = await createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )
      .from('push_devices')
      .delete()
      .in('token', dead)
    if (error) console.error('cleanup', error.message)
  }
  return respond(200, { results })
})
