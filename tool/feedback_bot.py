#!/usr/bin/env python3
"""Feedback bot for TrailBuddy (adapted from PilzBuddy's tool/feedback_bot.py).

Reads unprocessed rows from the Supabase `feedback` table, creates one
public GitHub issue per row (label `enhancement` or `bug`) and stamps the
row with processed_at. On the same tick it deletes `error_reports` older
than 90 days — the privacy policy promises that, so something has to do it.

On the same tick it keeps `public.error_reports` visible: one issue per
ISO week (label `ops`, title `Error reports YYYY-Wnn`), rewritten in place
on every run — no errors, no issue (#40); a closed one stays closed until
new reports arrive. Since the app reports Android's
exit reasons on the next start (ANR, crash, memory kill; context
`App-Ende`), the digest is the one place where a crash in the field
becomes visible without a USB cable.

Differences to PilzBuddy, both on purpose:
- No username in the issue. The issue is public; who wrote it stays in
  the database (user_id), where only the operator reads it. The digest
  shows contexts, types, messages and the top frame — never a user id.
- No species PRs, no feedback photos.

On the same tick it sweeps the photos at trail notes (#37, patch 026):
expired rows first, then every object in the bucket `trail-note-photos`
without a live row — by reconciliation, so rows that went with their note
(cascade) and uploads whose row never came are caught the same way.

@-mentions in the text are defused: a public issue must not ping people
because someone typed their handle into the app.

Required environment: SUPABASE_SERVICE_ROLE_KEY, GH_TOKEN (the workflow
provides both). The project URL comes from lib/core/supabase_config.dart,
the same file the app and tool/schema_check.sh read, so it cannot drift.
BOT_SUPABASE_URL overrides it — only for the Schema Dry Run, which runs
the photo sweep against the local stack (tool/photo_access_check.sh).

Self-tests without any network access:
    python3 tool/feedback_bot.py --self-test
    python3 tool/feedback_bot.py --test-digest

A past week, read-only (rows stay 90 days):
    python3 tool/feedback_bot.py --digest-week 2026-W40

Only the photo sweep (needs SUPABASE_SERVICE_ROLE_KEY):
    python3 tool/feedback_bot.py --sweep-note-photos
"""
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

CONFIG = "lib/core/supabase_config.dart"
ERROR_REPORT_RETENTION_DAYS = 90
TITLE_CHARS = 60
# A stack frame inside our own code looks like this; the digest prefers it
# over framework frames.
APP_FRAME = "package:trailbuddy/"


def supabase_url() -> str:
    override = os.environ.get("BOT_SUPABASE_URL")
    if override:
        return override.rstrip("/")
    with open(CONFIG, encoding="utf-8") as f:
        m = re.search(r"'SUPABASE_URL',\s*defaultValue:\s*'([^']+)'", f.read())
    if not m or not m.group(1).startswith("https://"):
        raise SystemExit(f"No live https URL in {CONFIG}")
    return m.group(1)


def api(method: str, path: str, body=None):
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    headers = {"apikey": key, "Content-Type": "application/json"}
    # Legacy service_role keys are JWTs and also go into Authorization;
    # the new sb_secret_* keys must only use apikey.
    if key.startswith("eyJ"):
        headers["Authorization"] = f"Bearer {key}"
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(supabase_url() + path, data=data,
                                     headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            text = response.read().decode()
            return json.loads(text) if text else None
    except urllib.error.HTTPError as e:
        # PostgREST sagt im Rumpf, WAS nicht stimmt ("invalid input syntax
        # for type timestamp …") — ohne ihn stand im Log nur „400". Der
        # Rumpf enthält keine Daten, nur die Fehlermeldung.
        raise SystemExit(f"{method} {path.split('?')[0]} → HTTP {e.code}: "
                         f"{e.read().decode(errors='replace')[:500]}") from None


def run(*cmd: str) -> str:
    return subprocess.run(cmd, check=True, capture_output=True,
                          text=True).stdout.strip()


def defuse(text: str) -> str:
    """No pings from a public issue: `@name` → `@​name`."""
    return re.sub(r"@(?=[A-Za-z0-9])", "@​", text)


def issue_title(row: dict) -> str:
    prefix = "Bug report: " if row["type"] == "bug" else "Feature request: "
    text = " ".join(defuse(row["message"]).split())
    return prefix + text[:TITLE_CHARS] + ("…" if len(text) > TITLE_CHARS else "")


def issue_body(row: dict) -> str:
    """Quoted text, version and date — and nothing about the person."""
    quoted = "\n".join("> " + line if line.strip() else ">"
                       for line in defuse(row["message"].strip()).splitlines())
    version = row.get("app_version")
    aus = f" aus Version {version}" if version else ""
    return (
        f"{quoted}\n\n"
        f"Eingereicht in der App{aus} am {row['created_at'][:10]}.\n\n"
        f"_Automatisch erstellt vom Feedback-Bot._"
    )


def issue_label(row: dict) -> str:
    return "bug" if row["type"] == "bug" else "enhancement"


def issue_exists(title: str) -> bool:
    out = run("gh", "issue", "list", "--state", "all", "--limit", "100",
              "--search", title, "--json", "title")
    return any(item["title"] == title for item in json.loads(out or "[]"))


def ensure_labels() -> None:
    # New repositories usually have both; a missing label would fail every
    # `gh issue create` below, so make sure instead of assuming.
    for name, color in (("bug", "d73a4a"), ("enhancement", "a2eeef"), ("ops", "5319E7")):
        subprocess.run(["gh", "label", "create", name, "--color", color, "--force"],
                       check=False, capture_output=True)


# --- the weekly error digest (#40, PilzBuddy's tool/feedback_bot.py) ---

def top_frame(stack: str | None) -> str | None:
    """The one line of a stack trace worth putting in the digest.

    Prefers the topmost frame inside our own code: a Dart stack almost
    always starts in the framework, and `#0 List.reduce` says nothing about
    which of our widgets got there. Without such a frame the topmost of any
    kind will do — an ANR thread dump or a tombstone has no other kind.
    (PilzBuddy: 61 rows of `Infinity or NaN toInt` in one week, and nobody
    could name the file — the stack was in the table all along.)
    """
    if not stack:
        return None
    lines = [line.strip() for line in stack.splitlines() if line.strip()]
    for line in lines:
        if APP_FRAME in line:
            return line[:200]
    for line in lines:
        if line.startswith("#") or " pc " in line:
            return line[:200]
    return None


def stack_phase(stack: str | None) -> str | None:
    """The framework phase the app wrote above a Flutter error's stack.

    Since 0.74.1 `flutterErrorStack` puts `Phase: <library> · <context>`
    on the first line ("scheduler library · during a scheduler callback").
    A ticker callback carries no frame of our own code, so this line is
    the only hint at where it happened (2026-W40: five rows of a null
    check in `AnimationController.stop` and nothing else to go on).
    """
    if not stack:
        return None
    first = stack.lstrip().splitlines()[0] if stack.strip() else ""
    if not first.startswith("Phase: "):
        return None
    return first[len("Phase: "):].strip()[:200] or None


def digest_body(rows: list[dict], week: str) -> str:
    """Group error reports by (context, error_type) into an issue body.

    Grouped here rather than in the query because PostgREST has no GROUP
    BY. Nothing about a person goes in: no user id, no username.
    """
    groups: dict[tuple[str, str], dict] = {}
    for row in rows:
        key = (row.get("context") or "?", row.get("error_type") or "?")
        group = groups.setdefault(key, {
            "count": 0, "versions": set(), "platforms": set(), "example": "",
            "frame": "", "phase": "",
        })
        group["count"] += 1
        if row.get("app_version"):
            group["versions"].add(row["app_version"])
        if row.get("platform"):
            group["platforms"].add(row["platform"])
        if not group["example"] and row.get("message"):
            group["example"] = defuse(row["message"].strip().replace("\n", " ")[:200])
        phase = stack_phase(row.get("stack"))
        if phase and not group["phase"]:
            group["phase"] = defuse(phase)
        frame = top_frame(row.get("stack"))
        # A frame from our code beats one from the framework, even if it
        # comes later: of ten rows in a group often only one carries a
        # stack that reaches us.
        if frame and (not group["frame"] or (APP_FRAME in frame
                                             and APP_FRAME not in group["frame"])):
            group["frame"] = defuse(frame)

    ranked = sorted(groups.items(), key=lambda kv: -kv[1]["count"])
    lines = [
        f"{len(rows)} error reports reached `public.error_reports` in {week}.",
        "",
        "Caught errors the app **survived** (the user saw a snackbar and "
        "carried on) and, under `App-Ende`, the reasons Android ended the "
        "process last time (ANR, crash, memory kill) — reported on the next "
        "start. Android Vitals sees neither for the GitHub APK.",
        "",
        "Each group shows its message and, where the stack reaches our own "
        f"code, the topmost frame in it. Rows stay {ERROR_REPORT_RETENTION_DAYS} "
        "days, so any past week can be re-rendered: "
        "`python3 tool/feedback_bot.py --digest-week " + week + "`.",
        "",
        "| # | Context | Type | Versions | Platforms |",
        "|--:|---|---|---|---|",
    ]
    for (context, error_type), group in ranked:
        lines.append(
            f"| {group['count']} | {context} | `{error_type}` | "
            f"{', '.join(sorted(group['versions'])) or '–'} | "
            f"{', '.join(sorted(group['platforms'])) or '–'} |"
        )
    lines.append("")
    for (context, error_type), group in ranked:
        if not group["example"] and not group["frame"]:
            continue
        lines.append(f"**{context} · {error_type}**")
        if group["example"]:
            lines.append(f"> {group['example']}")
        if group["phase"]:
            lines.append("")
            lines.append(f"Phase: {group['phase']}")
        if group["frame"]:
            lines.append("")
            lines.append(f"`{group['frame']}`")
        lines.append("")
    lines.append("_Automatically created by the feedback bot; "
                 "updated in place while the week runs. Close when triaged._")
    return "\n".join(lines)


def _stamp(when: datetime) -> str:
    # A literal Z, not isoformat(): its "+00:00" reads as a space in a query.
    return when.strftime("%Y-%m-%dT%H:%M:%SZ")


def week_bounds(week: str) -> tuple[datetime, datetime]:
    """Monday 00:00 UTC and the Monday after, for an ISO week label."""
    match = re.fullmatch(r"(\d{4})-W(\d{1,2})", week)
    if not match:
        raise SystemExit(f"Not an ISO week label: {week} (expected 2026-W40)")
    start = datetime.fromisocalendar(
        int(match.group(1)), int(match.group(2)), 1).replace(tzinfo=timezone.utc)
    return start, start + timedelta(days=7)


def fetch_error_rows(start: datetime, end: datetime) -> list[dict]:
    return api(
        "GET",
        f"/rest/v1/error_reports?created_at=gte.{_stamp(start)}"
        f"&created_at=lt.{_stamp(end)}"
        "&select=context,error_type,message,stack,app_version,platform,created_at"
        "&order=created_at",
    ) or []


def print_past_digest(week: str) -> None:
    """Render a past week to stdout. Reads only — touches no issue."""
    start, end = week_bounds(week)
    rows = fetch_error_rows(start, end)
    if not rows:
        print(f"No error reports in {week} "
              f"(rows older than {ERROR_REPORT_RETENTION_DAYS} days are purged).")
        return
    print(digest_body(rows, week))


def reported_count(body: str | None) -> int | None:
    """The report count in a digest body's first line, None if absent."""
    match = re.match(r"(\d+) error reports? reached", body or "")
    return int(match.group(1)) if match else None


def digest_action(existing: list[dict], title: str, count: int) -> tuple[str, int | None]:
    """What to do with this week's issue: create, edit, reopen or skip.

    Looks at closed issues too. Searching only the open ones turned every
    "close when triaged" during the week into a fresh copy two hours later
    (W41: #293 closed by the fix, #298 with the very same two reports;
    PilzBuddy had nine such copies). A closed digest stays closed while
    the count is the same — the reports in it are triaged — and is
    reopened when new ones arrived, because those are not. Rows only grow
    within a week (the purge takes rows older than 90 days), so a higher
    count means new reports; the count rather than the whole body, which
    GitHub may store with other line endings.
    """
    matches = [i for i in existing if i["title"] == title]
    open_match = next((i for i in matches if i.get("state", "OPEN").upper() == "OPEN"), None)
    if open_match:
        return "edit", open_match["number"]
    if not matches:
        return "create", None
    newest = max(matches, key=lambda i: i["number"])
    if reported_count(newest.get("body")) == count:
        return "skip", newest["number"]
    return "reopen", newest["number"]


def report_error_digest() -> None:
    """One issue per ISO week, rewritten in place on every two-hourly tick.

    Rewritten rather than commented on: 84 comments a week would bury the
    numbers instead of showing them. No errors means no issue.
    """
    year, week_no, _ = datetime.now(timezone.utc).isocalendar()
    week = f"{year}-W{week_no:02d}"
    rows = fetch_error_rows(*week_bounds(week))
    if not rows:
        print(f"No error reports in {week}.")
        return
    title = f"Error reports {week}"
    body = digest_body(rows, week)
    ensure_labels()
    existing = json.loads(run("gh", "issue", "list", "--state", "all",
                              "--label", "ops", "--limit", "50",
                              "--json", "number,title,state,body") or "[]")
    action, number = digest_action(existing, title, len(rows))
    if action == "create":
        run("gh", "issue", "create", "--title", title, "--body", body,
            "--label", "ops")
        print(f"Error digest created: {title} ({len(rows)} reports)")
    elif action == "skip":
        print(f"Error digest #{number} closed as triaged, no new reports: {title}")
    else:
        run("gh", "issue", "edit", str(number), "--body", body)
        if action == "reopen":
            run("gh", "issue", "reopen", str(number))
        print(f"Error digest {action}ed: {title} ({len(rows)} reports)")


def retention_cutoff(now: datetime) -> str:
    # UTC mit „Z", nicht isoformat(): dessen „+00:00" steht sonst roh in
    # der Adresse, und ein „+" in einer Query heißt Leerzeichen — PostgREST
    # bekam ein ungültiges Datum und antwortete 400 (erster Live-Lauf).
    cutoff = now.astimezone(timezone.utc) - timedelta(days=ERROR_REPORT_RETENTION_DAYS)
    return cutoff.strftime("%Y-%m-%dT%H:%M:%SZ")


def purge_path(cutoff: str) -> str:
    return "/rest/v1/error_reports?created_at=lt." + urllib.parse.quote(cutoff, safe="")


def purge_error_reports() -> None:
    api("DELETE", purge_path(retention_cutoff(datetime.now(timezone.utc))))
    print(f"error_reports older than {ERROR_REPORT_RETENTION_DAYS} days deleted.")


# Fotos am Hinweis (#37, Patch 026): Zeilen laufen nach 90 Tagen ab oder
# gehen mit ihrem Hinweis (Cascade), die Bytes liegen im Bucket. Beides
# räumt derselbe Tick ab — per ABGLEICH, nicht per Reihenfolge: Jedes
# Objekt, zu dem keine lebende Zeile mehr gehört, fliegt. Das fängt drei
# Fälle mit einem Griff: abgelaufene Zeilen, gelöschte Zeilen („erledigt",
# Rückzug, Aufräumen, Konto) und Uploads, deren Zeile nie geschrieben
# wurde (Netz weg zwischen Objekt und Zeile). Übernommen aus PilzBuddy
# (Fundfotos, #532).
NOTE_PHOTO_BUCKET = "trail-note-photos"
# Ein Objekt, das jünger ist als das, gilt als „im Aufbau": hochgeladen,
# die Zeile folgt gleich. Ohne die Schonfrist löschte ein Tick, der
# zwischen die beiden Schritte fällt, ein Foto mitten im Teilen.
PHOTO_ORPHAN_GRACE = timedelta(hours=1)


def photo_key_of(path: str) -> str:
    """`<uid>/<id>.jpg` und `<uid>/<id>_s.jpg` gehören zum Schlüssel `<uid>/<id>`."""
    if path.endswith("_s.jpg"):
        return path[:-6]
    if path.endswith(".jpg"):
        return path[:-4]
    return path


def photo_sweep_plan(live_keys: set[str], objects: list[tuple[str, datetime | None]],
                     now: datetime, grace: timedelta = PHOTO_ORPHAN_GRACE) -> list[str]:
    """Welche Objekte weg müssen: ohne lebende Zeile — und nicht ganz frisch.

    Rein, damit der Selbsttest sie ohne Netz prüfen kann. `created` ist
    None, wenn der Dienst keine Zeit meldet; dann gilt das Objekt als alt —
    ein Objekt ohne Zeile UND ohne Alter ist keines, das jemand gerade
    hochlädt."""
    doomed = []
    for path, created in objects:
        if photo_key_of(path) in live_keys:
            continue
        if created is not None and now - created < grace:
            continue
        doomed.append(path)
    return doomed


def _parse_ts(value) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


def _storage_list(bucket: str, prefix: str) -> list[dict]:
    return api("POST", f"/storage/v1/object/list/{bucket}",
               {"prefix": prefix, "limit": 1000, "offset": 0}) or []


def list_bucket_objects(bucket: str) -> list[tuple[str, datetime | None]]:
    """Alle Objekte mit Pfad und Erstellzeit.

    Die Liste antwortet je EBENE: Auf der obersten stehen die Ordner (ein
    Eintrag ohne `id`), darin die Dateien mit ihrem Namen ohne Ordner. Ein
    Ordner je Nutzer, also ein Aufruf je Nutzer plus einer."""
    out: list[tuple[str, datetime | None]] = []
    for entry in _storage_list(bucket, ""):
        if entry.get("id") is None:
            folder = entry["name"]
            for obj in _storage_list(bucket, folder):
                if obj.get("id") is None:
                    continue
                out.append((f"{folder}/{obj['name']}", _parse_ts(obj.get("created_at"))))
        else:
            out.append((entry["name"], _parse_ts(entry.get("created_at"))))
    return out


def expired_photos_path(now: datetime) -> str:
    # Wie bei purge_path: „Z" statt „+00:00", sonst hieße das „+" in der
    # Adresse Leerzeichen, und PostgREST antwortete 400.
    stamp = now.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return "/rest/v1/trail_note_photos?expires_at=lt." + urllib.parse.quote(stamp, safe="")


def sweep_note_photos(grace: timedelta = PHOTO_ORPHAN_GRACE) -> None:
    now = datetime.now(timezone.utc)
    api("DELETE", expired_photos_path(now))
    live = {row["key"] for row in (api("GET", "/rest/v1/trail_note_photos?select=key") or [])}
    objects = list_bucket_objects(NOTE_PHOTO_BUCKET)
    doomed = photo_sweep_plan(live, objects, now, grace)
    if doomed:
        api("DELETE", f"/storage/v1/object/{NOTE_PHOTO_BUCKET}", {"prefixes": doomed})
    print(f"Hinweis-Fotos: {len(live)} Zeilen, {len(objects)} Objekte, {len(doomed)} entfernt.")


def main() -> None:
    # Before the early return below — otherwise digest and purge would
    # only run on the rare tick that also has unprocessed feedback.
    report_error_digest()
    purge_error_reports()
    # Ein Aussetzer des Storage-Dienstes darf die Issues nicht aufhalten:
    # Der nächste Tick räumt nach, und abgelaufene Fotos liest schon jetzt
    # niemand mehr (tnp_friend_select). SystemExit gehört dazu — so meldet
    # api() einen HTTP-Fehler.
    try:
        sweep_note_photos()
    except (Exception, SystemExit) as e:  # noqa: BLE001 — jede Ursache ist hier gleich
        print(f"::warning::Hinweis-Fotos nicht abgeräumt: {e}")

    rows = api("GET", "/rest/v1/feedback?processed_at=is.null&order=created_at"
                      "&select=id,type,message,created_at,app_version")
    if not rows:
        print("No unprocessed feedback.")
        return
    ensure_labels()
    for row in rows:
        title = issue_title(row)
        if issue_exists(title):
            print(f"Skip (issue already exists): {title}")
        else:
            run("gh", "issue", "create", "--title", title,
                "--body", issue_body(row), "--label", issue_label(row))
            print(f"Issue created [{issue_label(row)}]: {title}")
        # Stamp each row right away so a later crash never duplicates it.
        now = datetime.now(timezone.utc).isoformat()
        api("PATCH", f"/rest/v1/feedback?id=eq.{row['id']}", {"processed_at": now})
    print("Done.")


def self_test() -> None:
    row = {"id": "x", "type": "feature", "created_at": "2026-09-27T18:00:00Z",
           "app_version": "0.2.0",
           "message": "Offline-Karten wären toll, frag mal @someone\n\nDanke!"}
    title = issue_title(row)
    assert title == "Feature request: Offline-Karten wären toll, frag mal @​someone Danke!", title
    body = issue_body(row)
    assert body.startswith("> Offline-Karten wären toll, frag mal @​someone\n>\n> Danke!"), body
    assert "aus Version 0.2.0 am 2026-09-27" in body, body
    assert "user" not in body.lower() and "von **" not in body, "no person in a public issue"
    assert issue_label(row) == "enhancement"

    bug = dict(row, type="bug", app_version=None, message="x" * 100)
    assert issue_title(bug) == "Bug report: " + "x" * 60 + "…"
    assert issue_label(bug) == "bug"
    assert "aus Version" not in issue_body(bug), "no invented version"

    cutoff = retention_cutoff(datetime(2026, 9, 27, 18, 0, tzinfo=timezone.utc))
    assert cutoff == "2026-06-29T18:00:00Z", cutoff
    # Kein rohes „+" in der Adresse — das war der 400 im ersten Live-Lauf.
    path = purge_path(cutoff)
    assert "+" not in path and path.endswith("lt.2026-06-29T18%3A00%3A00Z"), path

    assert supabase_url().startswith("https://") and supabase_url().endswith(".supabase.co")

    # Fotos am Hinweis: Abgleich statt Reihenfolge, Schonfrist für Uploads.
    now = datetime(2026, 10, 11, 12, 0, tzinfo=timezone.utc)
    old, fresh = now - timedelta(hours=3), now - timedelta(minutes=5)
    assert photo_key_of("u1/a.jpg") == "u1/a" and photo_key_of("u1/a_s.jpg") == "u1/a"
    objects = [("u1/a.jpg", old), ("u1/a_s.jpg", old),     # lebende Zeile
               ("u1/b.jpg", old), ("u1/b_s.jpg", old),     # Zeile weg (Hinweis erledigt)
               ("u2/c.jpg", fresh),                        # Upload im Aufbau
               ("u2/d.jpg", None)]                         # ohne Zeit, ohne Zeile
    plan = photo_sweep_plan({"u1/a"}, objects, now)
    assert plan == ["u1/b.jpg", "u1/b_s.jpg", "u2/d.jpg"], plan
    assert photo_sweep_plan({"u1/a"}, objects, now, timedelta(0)) == plan[:2] + ["u2/c.jpg", "u2/d.jpg"]
    path = expired_photos_path(now)
    assert "+" not in path and path.endswith("lt.2026-10-11T12%3A00%3A00Z"), path
    print("feedback_bot self-test: ok")


def self_test_digest() -> None:
    """Grouping and body rendering without any network access."""
    framework_stack = (
        "#0      List.reduce (dart:core/list.dart:120:5)\n"
        "#1      _Chart.build (package:flutter/src/widgets/framework.dart:12:3)")
    app_stack = (
        "#0      List.reduce (dart:core/list.dart:120:5)\n"
        "#1      _TrailSheet.build "
        "(package:trailbuddy/features/trails/trail_sheet.dart:707:38)")
    rows = [
        {"context": "Trails laden", "error_type": "PostgrestException",
         "message": "column trails.foo does not exist", "stack": framework_stack,
         "app_version": "0.20.0", "platform": "android"},
        {"context": "Trails laden", "error_type": "PostgrestException",
         "message": "column trails.foo does not exist", "stack": app_stack,
         "app_version": "0.21.0", "platform": "web"},
        {"context": "App-Ende", "error_type": "ANR",
         "message": "RSS 1900 MB · PSS 1000 MB · importance 100 @someone",
         "stack": '"main" prio=5 tid=1 Native\n'
                  "  native: #00 pc 00984478  base.apk (offset 9c0000)",
         "app_version": "0.21.0", "platform": "android"},
    ]
    body = digest_body(rows, "2026-W40")
    assert "3 error reports" in body, body
    # Most frequent group first — otherwise one reads the table to see
    # what hurts most.
    assert body.index("| 2 | Trails laden") < body.index("| 1 | App-Ende"), body
    assert "0.20.0, 0.21.0" in body, body
    assert "android, web" in body, body
    # The frame from our code wins over the framework one, although the
    # framework line comes first — that is the whole point.
    assert "trail_sheet.dart:707:38" in body, body
    assert "framework.dart:12:3" not in body, body
    # An exit reason carries the memory line and the top native frame.
    assert "RSS 1900 MB" in body, body
    assert "native: #00 pc 00984478" in body, body
    # A public issue pings nobody, whatever a message carries.
    assert "@someone" not in body and "@\u200bsomeone" in body, body
    assert "user_id" not in body and "username" not in body, "no person in a public issue"

    assert top_frame("Error\n    at Object.wl (main.dart.js:1:2)") is None
    assert top_frame(None) is None and top_frame("") is None

    # The phase line of a Flutter error (since 0.74.1) shows in the
    # digest and never counts as a frame.
    ticker_stack = (
        "Phase: scheduler library · during a scheduler callback\n"
        "#0      AnimationController.stop "
        "(package:flutter/src/animation/animation_controller.dart:894:13)")
    assert stack_phase(ticker_stack) == "scheduler library · during a scheduler callback"
    assert stack_phase(framework_stack) is None and stack_phase(None) is None
    assert top_frame(ticker_stack).startswith("#0      AnimationController.stop")
    ticker_body = digest_body([{"context": "Flutter-Fehler", "error_type": "_TypeError",
                                "message": "Null check operator used on a null value",
                                "stack": ticker_stack, "app_version": "0.74.1",
                                "platform": "android"}], "2026-W41")
    assert "Phase: scheduler library · during a scheduler callback" in ticker_body, ticker_body

    # Week bounds: 2026-W40 starts Monday, 28 September.
    start, end = week_bounds("2026-W40")
    assert (start.year, start.month, start.day) == (2026, 9, 28), start
    assert (end - start).days == 7, (start, end)
    assert _stamp(start) == "2026-09-28T00:00:00Z", _stamp(start)
    # The week's issue: an open one is rewritten; a closed one stays
    # closed while nothing new came in and is reopened when it did —
    # never a second issue for the same week (#298, a copy of #293).
    assert reported_count(body) == 3, reported_count(body)
    assert reported_count(ticker_body) == 1 and reported_count("") is None
    title = "Error reports 2026-W41"
    closed = {"number": 293, "title": title, "state": "CLOSED", "body": body}
    other = {"number": 290, "title": "Error reports 2026-W40", "state": "OPEN", "body": body}
    assert digest_action([], title, 3) == ("create", None)
    assert digest_action([other], title, 3) == ("create", None)
    assert digest_action([closed, other], title, 3) == ("skip", 293)
    assert digest_action([closed], title, 4) == ("reopen", 293)
    assert digest_action([dict(closed, state="OPEN")], title, 4) == ("edit", 293)
    copy = {"number": 298, "title": title, "state": "OPEN", "body": body}
    assert digest_action([copy, closed], title, 3) == ("edit", 298)
    assert digest_action([dict(copy, state="CLOSED"), closed], title, 3) == ("skip", 298)
    print("feedback_bot digest self-test: ok")


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        self_test()
    elif sys.argv[1:] == ["--test-digest"]:
        self_test_digest()
    elif len(sys.argv) == 3 and sys.argv[1] == "--digest-week":
        print_past_digest(sys.argv[2])
    elif sys.argv[1:] == ["--sweep-note-photos"]:
        # PHOTO_GRACE_SECONDS nur für den Dry Run: Dort ist jedes Objekt
        # Sekunden alt, und ohne 0 bewiese der Lauf nichts.
        sweep_note_photos(timedelta(seconds=int(os.environ.get(
            "PHOTO_GRACE_SECONDS", PHOTO_ORPHAN_GRACE.total_seconds()))))
    elif not sys.argv[1:]:
        main()
    else:
        raise SystemExit(__doc__)
