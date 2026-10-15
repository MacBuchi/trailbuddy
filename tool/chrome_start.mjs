// Startet einen Headless-Chrome für die Browser-Prüfungen der CI
// (`check_service_worker.mjs`, `check_push_worker.mjs`) und wartet, bis
// sein Debug-Port antwortet.
//
// **Chrome hängt auf dem CI-Rechner gelegentlich schon beim Start**: kein
// Debug-Port, keine Ausgabe, kein Ende (PR #344, 2026-10-15 — derselbe
// Stand lief davor und danach grün). Dann wird er abgeschossen und mit
// frischem Profil neu gestartet, höchstens [starts] Mal. Das gilt NUR für
// den Start: Was danach scheitert, ist ein Befund über die App.
import {spawn} from 'node:child_process';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Gibt `{chrome, answer, stop}` zurück: den Prozess (mit `chrome.log`,
 * Chromes eigener Ausgabe), die erste Antwort von [endpoint] und das
 * Aufräumen (Prozess beenden, Profile löschen — scheitert nie).
 */
export async function startChrome({binary, port, args, endpoint = '/json/list', prefix = 'trailbuddy-chrome-',
  starts = 3}) {
  const profiles = [];
  let chrome = null;

  const stop = async () => {
    chrome?.kill('SIGKILL');
    await sleep(500); // Chrome die Handles schließen lassen
    for (const profile of profiles) {
      await rm(profile, {recursive: true, force: true, maxRetries: 5})
          .catch(() => { /* ein Rest im Temp-Verzeichnis ist kein Fehlschlag */ });
    }
  };

  const launch = async () => {
    const profile = await mkdtemp(join(tmpdir(), prefix));
    profiles.push(profile);
    const proc = spawn(binary, [
      '--headless=new',
      '--no-first-run',
      '--no-default-browser-check',
      // Auf CI-Rechnern läuft alles als root und ohne die üblichen
      // Kernel-Namespaces; ohne diese beiden startet Chrome dort gar nicht.
      '--no-sandbox',
      '--disable-dev-shm-usage',
      ...args,
      `--remote-debugging-port=${port}`,
      `--user-data-dir=${profile}`,
      'about:blank',
    ], {stdio: ['ignore', 'pipe', 'pipe']});
    // Chromes eigene Meldungen aufheben: Startet er nicht, ist DAS die
    // Auskunft — „antwortet nicht auf dem Debug-Port" allein sagt nichts.
    proc.log = '';
    const append = (d) => { proc.log += d; };
    proc.stdout.on('data', append);
    proc.stderr.on('data', append);
    proc.on('error', (error) => append(`spawn: ${error.message}\n`));
    proc.on('exit', (code, signal) => append(`Chrome beendet (code ${code}, signal ${signal})\n`));
    return proc;
  };

  // 30 s je Start, wie vor dem Neustart.
  const ask = async () => {
    for (let attempt = 0; attempt < 60; attempt++) {
      try {
        return await (await fetch(`http://127.0.0.1:${port}${endpoint}`)).json();
      } catch (_) {
        await sleep(500);
      }
    }
    return null;
  };

  const output = () => `--- Ausgabe von Chrome ---\n${chrome.log.trim() || '(nichts)'}`;
  for (let start = 1; start <= starts; start++) {
    if (chrome) {
      console.log(`Chrome hing beim Start (Versuch ${start - 1} von ${starts}) — neu gestartet.\n${output()}`);
      chrome.kill('SIGKILL');
      await sleep(500);
    }
    chrome = await launch();
    const answer = await ask();
    if (answer) return {chrome, answer, stop};
  }
  const error = new Error(`Chrome antwortet nicht auf dem Debug-Port, auch nach ${starts} Starts.\n${output()}`);
  await stop();
  throw error;
}
