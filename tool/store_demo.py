#!/usr/bin/env python3
"""Legt die Demo-Welt für die Store-Screenshots an — NUR auf dem lokalen
Supabase-Stack (`supabase start`, Portblock 5452x).

Ein Trail im Store wäre genau die öffentliche Karte, die das Konzept
ausschließt (Konzept 7) — deshalb nie ein echtes Konto, nie eine echte
Fahrt. Die Linien sind öffentliche OSM-Pfade am Rosskopf bei Freiburg
(ODbL, über Overpass), die Höhen aus EU-DEM (OpenTopoData), die Nutzer
erfunden (`<name>@demo.invalid`). Die Basiskarte der App deckt nur DACH ab;
ein Gebiet außerhalb zeigt leere Kacheln.

    supabase start
    SUPABASE_DB_URL=postgresql://postgres:postgres@127.0.0.1:54522/postgres \\
      bash tool/db_migrate.sh
    python3 tool/store_demo.py

Danach als `maxi@demo.invalid` anmelden (Passwort unten). Ein zweiter Lauf
ist harmlos: Er löscht die Demo-Nutzer vorher (Cascade nimmt Fahrten,
Beiträge, Meldungen und Nachrichten mit). Wie die Bilder entstehen:
`docs/play-console.md`, Abschnitt „Grafiken".
"""
import json
import math
import os
import random
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

API = "http://127.0.0.1:54521"
PASSWORD = "demo-demo-123"
CACHE = os.path.join(tempfile.gettempdir(), "trailbuddy-store-demo")
BBOX = "47.97,7.84,48.03,7.95"  # Süd, West, Nord, Ost — Rosskopf/Freiburg

# Der Demo-Nutzer ist maxi; die drei anderen sind seine Buddys.
USERS = ["maxi", "lena", "jonas", "mia_rides"]

# OSM-Name -> Beitragende (der erste benennt), Charakter, Sterne.
PLAN = {
    "Canadian Trail": (["maxi", "lena"], ["flowy", "jumps"], 5),
    "Borderline": (["maxi", "jonas", "mia_rides"], ["flowy", "jumps"], 5),
    "Baden to the Bone": (["lena", "jonas"], ["rocky", "steep"], 5),
    "Hubbelfuchs": (["maxi"], ["flowy"], 4),
    "Kybfelsensteig": (["jonas"], ["natural", "rocky"], 4),
    "Hexenwegle": (["mia_rides", "maxi"], ["natural"], 4),
    "Wichtelpfad": (["mia_rides"], ["flowy"], 4),
    "Kammweg": (["lena"], ["natural"], 3),
    "Häusledobelweg": (["jonas", "lena"], ["rocky"], 4),
    "Husarenwegle": (["maxi"], ["natural"], 3),
    "Schokoladenwegle": (["mia_rides"], ["flowy"], 4),
    "Floh-Trail 2": (["lena", "maxi"], ["jumps", "flowy"], 4),
    "Carl-Mez-Weg": (["jonas"], ["natural"], 3),
    "Rosskopfwegle": (["maxi", "mia_rides"], ["flowy"], 3),
}

# Zustand (1–5) mit Text, von Buddys, die den Trail selbst belegt haben.
REPORTS = [
    ("jonas", "Borderline", 4, 5,
     "Nach dem Regen schon wieder griffig. Unten im letzten Anlieger liegt ein Ast quer."),
    ("lena", "Canadian Trail", 5, 20,
     "Staubtrocken und schnell – die Sprünge laufen super."),
]

# Ein Verlauf maxi <-> lena; die Uhrzeit setzt das Skript auf den Vormittag.
CHAT = [
    ("lena", "Morgen früh Rosskopf? Canadian ist gerade staubtrocken 🤙"),
    ("maxi", "Bin dabei! 9 Uhr am Parkplatz Waldsee?"),
    ("lena", "Passt. Danach noch Borderline runter, Jonas sagt, der läuft wieder."),
    ("maxi", "Perfekt, ich bring Kaffee mit ☕"),
]


def local_keys():
    out = subprocess.run(["supabase", "status", "-o", "json"], check=True,
                         capture_output=True, text=True).stdout
    status = json.loads(out[out.index("{"):out.rindex("}") + 1])
    if not status["API_URL"].startswith(("http://127.0.0.1", "http://localhost")):
        sys.exit(f"Kein lokaler Stack: {status['API_URL']}")
    return status["ANON_KEY"], status["SERVICE_ROLE_KEY"], status["DB_URL"]


ANON = SERVICE = DB_URL = None


def req(method, path, body=None, token=None, key=None, prefer=None):
    key = key or ANON
    h = {"apikey": key, "Content-Type": "application/json",
         "Authorization": f"Bearer {token or key}"}
    if prefer:
        h["Prefer"] = prefer
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(API + path, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(r) as resp:
            t = resp.read()
            return json.loads(t) if t else None
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path}: {e.code} {e.read().decode()[:400]}")


def fetch(url, data=None, name=None):
    path = os.path.join(CACHE, name) if name else None
    if path and os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    r = urllib.request.Request(url, data=data, headers={"User-Agent": "trailbuddy-store-demo"})
    with urllib.request.urlopen(r, timeout=90) as resp:
        res = json.load(resp)
    if path:
        os.makedirs(CACHE, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(res, f)
    return res


def dist(a, b):
    lat = math.radians((a[1] + b[1]) / 2)
    return math.hypot((a[0] - b[0]) * 111320 * math.cos(lat), (a[1] - b[1]) * 110540)


def length(line):
    return sum(dist(a, b) for a, b in zip(line, line[1:]))


def chain(ways):
    """Wege gleichen Namens zur längsten Kette verbinden (Lücke < 40 m)."""
    segs = [[(p["lon"], p["lat"]) for p in w["geometry"]] for w in ways]
    best = []
    for start in range(len(segs)):
        line, rest = list(segs[start]), segs[:start] + segs[start + 1:]
        grown = True
        while grown and rest:
            grown = False
            for i, s in enumerate(rest):
                for cand in (s, s[::-1]):
                    if dist(line[-1], cand[0]) < 40:
                        line += cand[1:]
                    elif dist(cand[-1], line[0]) < 40:
                        line = cand[:-1] + line
                    else:
                        continue
                    rest.pop(i)
                    grown = True
                    break
                if grown:
                    break
        if length(line) > length(best):
            best = line
    return best


def elevations(pts):
    path = os.path.join(CACHE, "ele.json")
    cache = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            cache = json.load(f)
    keys = [f"{p[1]:.5f},{p[0]:.5f}" for p in pts]
    todo = [k for k in dict.fromkeys(keys) if k not in cache]
    for i in range(0, len(todo), 100):  # 100 Punkte je Anfrage, 1 Anfrage/s
        part = todo[i:i + 100]
        res = fetch("https://api.opentopodata.org/v1/eudem25m?locations=" + "|".join(part))
        for k, v in zip(part, res["results"]):
            cache[k] = v["elevation"]
        os.makedirs(CACHE, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(cache, f)
        time.sleep(1.1)
    return [cache[k] for k in keys]


def jitter(pts, metres):
    """Die Aufzeichnung eines Buddys: derselbe Trail mit GPS-Rauschen."""
    out, dx, dy = [], 0.0, 0.0
    for lon, lat in pts:
        dx = 0.7 * dx + random.gauss(0, metres * 0.5)
        dy = 0.7 * dy + random.gauss(0, metres * 0.5)
        out.append((lon + dx / (111320 * math.cos(math.radians(lat))), lat + dy / 110540))
    return out


def psql(sql):
    subprocess.run(["psql", DB_URL, "-q", "-v", "ON_ERROR_STOP=1", "-c", sql], check=True)


def main():
    global ANON, SERVICE, DB_URL
    ANON, SERVICE, DB_URL = local_keys()
    random.seed(7)

    query = f'[out:json][timeout:60];way["highway"~"path|track"]["mtb:scale"]({BBOX});out geom tags;'
    osm = fetch("https://overpass-api.de/api/interpreter",
                urllib.parse.urlencode({"data": query}).encode(), "osm.json")["elements"]
    by_name = {}
    for w in osm:
        n = w["tags"].get("name") or ""
        if n.startswith("Borderline"):  # in OSM in Abschnitten
            n = "Borderline"
        if n in PLAN:
            by_name.setdefault(n, []).append(w)

    psql("delete from auth.users where email like '%@demo.invalid'")
    tokens, ids = {}, {}
    for i, u in enumerate(USERS):
        email = f"{u}@demo.invalid"
        req("POST", "/auth/v1/admin/users", {"email": email, "password": PASSWORD,
            "email_confirm": True, "user_metadata": {"username": u}},
            token=SERVICE, key=SERVICE)
        t = req("POST", "/auth/v1/token?grant_type=password",
                {"email": email, "password": PASSWORD})
        tokens[u], ids[u] = t["access_token"], t["user"]["id"]
        req("PATCH", f"/rest/v1/profiles?id=eq.{ids[u]}", {"avatar": i + 2},
            token=tokens[u])
    for b in USERS[1:]:
        req("POST", "/rest/v1/friendships", {"requester_id": ids["maxi"],
            "addressee_id": ids[b]}, token=tokens["maxi"])
        req("PATCH", f"/rest/v1/friendships?requester_id=eq.{ids['maxi']}"
            f"&addressee_id=eq.{ids[b]}", {"status": "accepted"}, token=tokens[b])

    trail_ids, n = {}, 0
    for name, (who, traits, rating) in PLAN.items():
        ways = by_name.get(name)
        if not ways:
            print(f"nicht in OSM: {name}")
            continue
        line = chain(ways)
        ele = elevations(line)
        if ele[0] < ele[-1]:  # bergab aufgezeichnet
            line, ele = line[::-1], ele[::-1]
        grade = max(int(w["tags"]["mtb:scale"][0]) for w in ways)
        for i, u in enumerate(who):
            n += 1
            at = time.strftime("%Y-%m-%dT10:00:00Z", time.gmtime(time.time() - n * 3 * 86400))
            trail_ids[name] = req("POST", "/rest/v1/rpc/contribute_recording", {
                "coords": [c for p in (line if i == 0 else jitter(line, 3)) for c in p],
                "source": "app", "recorded_at": at,
                "eles": [round(e, 1) for e in ele]}, token=tokens[u])
            req("POST", "/rest/v1/trail_details", {
                "trail_id": trail_ids[name], "user_id": ids[u],
                "name": name if i == 0 else None,
                "grade": min(5, max(0, grade + (0 if i == 0 else random.choice([0, 0, 1, -1])))),
                "traits": traits,
                "rating": max(1, rating - (0 if i == 0 else random.choice([0, 1]))),
            }, token=tokens[u], prefer="resolution=merge-duplicates")
        print(f"{name}: {length(line) / 1000:.1f} km, S{grade}, {', '.join(who)}")
    if len(set(trail_ids.values())) != len(trail_ids):
        sys.exit("Zwei Trails sind im Abgleich verschmolzen — PLAN prüfen")

    for u, name, cond, hours, note in REPORTS:
        at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - hours * 3600))
        req("POST", "/rest/v1/rpc/report_trail", {"trail_id": trail_ids[name],
            "condition": cond, "on_site": True, "reported_at": at, "note": note},
            token=tokens[u])

    for u, body in CHAT:
        other = "maxi" if u == "lena" else "lena"
        req("POST", "/rest/v1/buddy_messages", {"recipient_id": ids[other], "body": body},
            token=tokens[u], prefer="return=minimal")
        time.sleep(0.05)
    # Heute zwischen 9 und 10 Uhr Ortszeit — passend zur Uhr der Statusleiste.
    psql("with m as (select id, row_number() over (order by created_at) k "
         "from buddy_messages where sender_id in "
         "(select id from auth.users where email like '%@demo.invalid')) "
         "update buddy_messages b set created_at = date_trunc('day', now()) "
         "+ interval '8 hours' + m.k * interval '7 minutes' from m where m.id = b.id")

    print(f"\n{len(trail_ids)} Trails. Anmelden: maxi@demo.invalid / {PASSWORD}")


if __name__ == "__main__":
    main()
