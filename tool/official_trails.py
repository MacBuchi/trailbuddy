#!/usr/bin/env python3
"""Official trails layer: fetch, filter, normalise (issue #13).

Builds the static files behind the map layer "Offizielle Trails"
(docs/konzept-offizielle-trails.md): one GeoJSON FeatureCollection per
region plus index.json. Sources are listed in tool/official/sources.json;
only data that is official AND usable without asking goes in. Today that
is Tirol alone (CC0, 238 singletrails).

Standard library only, like the other tools. The output is deterministic
(sorted, no run timestamp), so the workflow commits only when a source
really changed.

Guards (concept 5.1):
  - a source that cannot be fetched keeps its previous file (--previous)
    and is reported; without a previous file the run fails;
  - a source that suddenly loses more than a third of its trails is NOT
    published — a broken export must not empty a region; the run fails.

Usage:
  python3 tool/official_trails.py --out out/ [--previous data/] \
      [--input tirol=local.json] [--summary summary.md]
  python3 tool/official_trails.py --self-test
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
import urllib.request
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCES = os.path.join(HERE, "official", "sources.json")

# Same as the import (trail_geometry.dart: simplify toleranceM = 3) — an
# official line should look as smooth as a contributed one.
SIMPLIFY_M = 3.0
# Below the matcher's minimum trail length (concept 4.2) a piece is an
# access or a fragment, not a trail.
MIN_TRAIL_M = 50.0
# Losing more than this share of a source's trails blocks publishing.
MAX_DROP = 1 / 3
USER_AGENT = "TrailBuddy official-trails (github.com/MacBuchi/TrailBuddy)"


# ---------------------------------------------------------------- geometry

def haversine_m(a, b):
    lon1, lat1, lon2, lat2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = (math.sin((lat2 - lat1) / 2) ** 2
         + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2)
    return 2 * 6371000.0 * math.asin(math.sqrt(h))


def length_m(line):
    return sum(haversine_m(line[i - 1], line[i]) for i in range(1, len(line)))


def simplify(line, tol_m=SIMPLIFY_M):
    """Douglas-Peucker in a local metric frame; keeps both ends."""
    if len(line) < 3:
        return [list(p[:2]) for p in line]
    lat0 = math.radians(sum(p[1] for p in line) / len(line))
    kx = 6371000.0 * math.cos(lat0) * math.pi / 180
    ky = 6371000.0 * math.pi / 180
    xy = [(p[0] * kx, p[1] * ky) for p in line]
    keep = [False] * len(line)
    keep[0] = keep[-1] = True
    stack = [(0, len(line) - 1)]
    while stack:
        i, j = stack.pop()
        (x1, y1), (x2, y2) = xy[i], xy[j]
        dx, dy = x2 - x1, y2 - y1
        norm = math.hypot(dx, dy)
        best, idx = -1.0, -1
        for k in range(i + 1, j):
            x, y = xy[k]
            d = (abs(dy * x - dx * y + x2 * y1 - y2 * x1) / norm
                 if norm > 0 else math.hypot(x - x1, y - y1))
            if d > best:
                best, idx = d, k
        if idx >= 0 and best > tol_m:
            keep[idx] = True
            stack += [(i, idx), (idx, j)]
    return [[round(p[0], 6), round(p[1], 6)] for p, k in zip(line, keep) if k]


def lines_of(geometry):
    if not geometry:
        return []
    if geometry["type"] == "LineString":
        return [geometry["coordinates"]]
    if geometry["type"] == "MultiLineString":
        return geometry["coordinates"]
    return []


# ----------------------------------------------------------------- readers

LEVELS = {"leicht": "easy", "mittelschwierig": "medium", "schwierig": "hard"}


def _tirol_date(s):
    if not s:
        return None
    try:
        return datetime.strptime(s, "%m/%d/%Y %I:%M:%S %p").date().isoformat()
    except ValueError:
        return None


def read_tirol_wfs(collection, source_id):
    """Land Tirol, "Radrouten in Tirol": one feature per SECTION. Sections
    with the same ROUTENNUMMER are one trail (main route plus variants);
    only ROUTEN_TYP "Single Trail" counts."""
    by_number = {}
    for f in collection.get("features", []):
        p = f.get("properties") or {}
        if p.get("ROUTEN_TYP") != "Single Trail":
            continue
        number = str(p.get("ROUTENNUMMER") or p.get("OBJECTID"))
        by_number.setdefault(number, []).append(f)

    trails = []
    for number, sections in by_number.items():
        sections.sort(key=lambda f: (
            f["properties"].get("ROUTENSEKTION_TYP") != "Hauptroute",
            f["properties"].get("OBJECTID") or 0))
        main = [f for f in sections
                if f["properties"].get("ROUTENSEKTION_TYP") == "Hauptroute"] or sections
        head = main[0]["properties"]
        parts, meta = [], []
        for f in sections:
            closed = f["properties"].get("STATUS") == "gesperrt"
            variant = f not in main
            for line in lines_of(f.get("geometry")):
                if len(line) >= 2:
                    parts.append(line)
                    meta.append({"variant": variant, "closed": closed})
        if not parts:
            continue
        main_closed = [f["properties"].get("STATUS") == "gesperrt" for f in main]
        any_closed = any(m["closed"] for m in meta)
        status = ("closed" if all(main_closed)
                  else "partly_closed" if any_closed else "open")
        dates = [d for d in (_tirol_date(f["properties"].get("UPDATETIMESTAMP"))
                             for f in sections) if d]
        difficulty = head.get("ROUTEN_SCHWIERIGKEIT")
        trails.append({
            "id": f"{source_id}:{number}",
            "parts": parts,
            "sections": meta,
            "properties": {
                "name": head.get("ROUTENNAME") or f"Singletrail {number}",
                "kind": "trail",
                "difficulty": difficulty,
                "level": LEVELS.get(difficulty),
                "status": status,
                "down_m": _int(sum(f["properties"].get("HM_BERGAB") or 0 for f in main)),
                "up_m": _int(sum(f["properties"].get("HM_BERGAUF") or 0 for f in main)),
                "description": (head.get("ROUTENBESCHREIBUNG") or "").strip() or None,
                "updated": max(dates) if dates else None,
            },
        })
    return trails


def _int(v):
    return int(round(v)) if v else 0


READERS = {"tirol_wfs": read_tirol_wfs}


# ---------------------------------------------------------------- building

def build_region(trails, source_id):
    """Simplify, measure, drop what is too short. Returns (features, dropped)."""
    features, dropped = [], 0
    for t in trails:
        parts = [simplify(line) for line in t["parts"]]
        total = sum(length_m(p) for p in parts)
        if total < MIN_TRAIL_M:
            dropped += 1
            continue
        main_len = sum(length_m(p) for p, m in zip(parts, t["sections"])
                       if not m["variant"])
        props = dict(t["properties"])
        props["length_m"] = int(round(main_len or total))
        props["sections"] = t["sections"]
        props["source"] = source_id
        features.append({
            "type": "Feature",
            "id": t["id"],
            "geometry": {"type": "MultiLineString", "coordinates": parts},
            "properties": {k: v for k, v in sorted(props.items()) if v is not None},
        })
    features.sort(key=lambda f: f["id"])
    return features, dropped


def bbox_of(features):
    xs = [p[0] for f in features for line in f["geometry"]["coordinates"] for p in line]
    ys = [p[1] for f in features for line in f["geometry"]["coordinates"] for p in line]
    return [round(min(xs), 4), round(min(ys), 4), round(max(xs), 4), round(max(ys), 4)]


def dump(obj):
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read().decode("utf-8"))


def run(out_dir, previous_dir=None, inputs=None, config=None, fetcher=fetch):
    """Returns (ok, report lines)."""
    config = config or json.load(open(SOURCES, encoding="utf-8"))
    inputs = inputs or {}
    os.makedirs(out_dir, exist_ok=True)
    regions, sources_meta, report, ok = [], {}, [], True

    for sid, src in sorted(config["sources"].items()):
        region = src["region"]
        fname = f"{region}.geojson"
        prev_path = os.path.join(previous_dir, fname) if previous_dir else None
        prev = (json.load(open(prev_path, encoding="utf-8"))
                if prev_path and os.path.exists(prev_path) else None)
        sources_meta[sid] = {k: src[k] for k in
                             ("name", "attribution", "license", "license_url", "url")}
        try:
            raw = (json.load(open(inputs[sid], encoding="utf-8")) if sid in inputs
                   else fetcher(src["fetch"]))
            features, dropped = build_region(READERS[src["reader"]](raw, sid), sid)
        except Exception as e:  # noqa: BLE001 — any failure means "keep the old file"
            if prev is None:
                report.append(f"❌ {sid}: nicht abrufbar ({e}), keine frühere Datei")
                ok = False
                continue
            report.append(f"⚠️ {sid}: nicht abrufbar ({e}) — frühere Datei bleibt")
            features, dropped = prev["features"], 0

        if prev is not None and len(features) < len(prev["features"]) * (1 - MAX_DROP):
            report.append(f"❌ {sid}: {len(features)} statt {len(prev['features'])} Trails "
                          f"— mehr als ein Drittel weg, NICHT veröffentlicht")
            ok = False
            features = prev["features"]
        elif not features:
            report.append(f"❌ {sid}: keine Trails")
            ok = False
            continue
        else:
            closed = sum(1 for f in features if f["properties"].get("status") != "open")
            report.append(f"✓ {sid}: {len(features)} Trails ({closed} ganz oder teilweise "
                          f"gesperrt), {dropped} unter {int(MIN_TRAIL_M)} m weggelassen")

        with open(os.path.join(out_dir, fname), "w", encoding="utf-8") as fh:
            fh.write(dump({"type": "FeatureCollection", "features": features}))
        dates = [f["properties"].get("updated") for f in features if f["properties"].get("updated")]
        regions.append({
            "id": region,
            "file": fname,
            "bbox": bbox_of(features),
            "count": len(features),
            "updated": max(dates) if dates else None,
            "sources": [sid],
        })

    with open(os.path.join(out_dir, "index.json"), "w", encoding="utf-8") as fh:
        fh.write(dump({"version": 1, "regions": regions, "sources": sources_meta}))
    return ok, report


# --------------------------------------------------------------- self-test

def _section(num, kind, status, coords, name="Testtrail", diff="mittelschwierig",
             ts="9/23/2026 11:59:26 PM", typ="Single Trail"):
    return {"type": "Feature",
            "geometry": {"type": "MultiLineString", "coordinates": [coords]},
            "properties": {"ROUTEN_TYP": typ, "ROUTENNUMMER": num, "ROUTENNAME": name,
                           "ROUTENSEKTION_TYP": kind, "STATUS": status,
                           "ROUTEN_SCHWIERIGKEIT": diff, "HM_BERGAB": 120.4,
                           "HM_BERGAUF": 3, "UPDATETIMESTAMP": ts, "OBJECTID": 1}}


def _straight(lon0, n=60, step=1e-4):
    # ~11 m steps east with a tiny wiggle below the tolerance.
    return [[lon0 + i * step, 1.0 + (1e-6 if i % 2 else 0)] for i in range(n)]


def self_test():
    import tempfile

    # simplify: a wiggle below 3 m disappears, a corner stays, ends stay.
    line = _straight(1.0)
    s = simplify(line)
    assert s[0] == [1.0, 1.0] and len(s) == 2, s
    corner = [[1.0, 1.0], [1.0005, 1.0], [1.001, 1.0], [1.001, 1.0005], [1.001, 1.001]]
    assert len(simplify(corner)) == 3

    coll = {"features": [
        _section("1", "Hauptroute", "offen", _straight(1.0)),
        _section("1", "Variante", "gesperrt", _straight(1.01, n=10)),
        _section("2", "Hauptroute", "gesperrt", _straight(1.02), diff="schwierig"),
        _section("3", "Hauptroute", "offen", _straight(1.03, n=5)),      # ~30 m
        _section("9", "Hauptroute", "offen", _straight(1.04), typ="Mountainbikestrecke"),
    ]}
    trails = {t["id"]: t for t in read_tirol_wfs(coll, "tirol")}
    assert set(trails) == {"tirol:1", "tirol:2", "tirol:3"}, "nur Single Trail"
    assert trails["tirol:1"]["properties"]["status"] == "partly_closed"
    assert trails["tirol:1"]["sections"] == [{"variant": False, "closed": False},
                                             {"variant": True, "closed": True}]
    assert trails["tirol:2"]["properties"]["status"] == "closed"
    assert trails["tirol:2"]["properties"]["level"] == "hard"
    assert trails["tirol:1"]["properties"]["updated"] == "2026-09-23"
    assert trails["tirol:1"]["properties"]["down_m"] == 120

    features, dropped = build_region(list(trails.values()), "tirol")
    assert [f["id"] for f in features] == ["tirol:1", "tirol:2"] and dropped == 1
    f1 = features[0]["properties"]
    assert 630 < f1["length_m"] < 680, f1["length_m"]   # main route only, ~656 m

    cfg = {"sources": {"tirol": {"region": "tirol", "name": "n", "attribution": "a",
                                 "license": "l", "license_url": "u", "url": "u",
                                 "reader": "tirol_wfs", "fetch": "unused"}}}
    with tempfile.TemporaryDirectory() as d:
        out1, out2, out3 = (os.path.join(d, x) for x in ("1", "2", "3"))
        ok, rep = run(out1, config=cfg, fetcher=lambda _: coll)
        assert ok, rep
        index = json.load(open(os.path.join(out1, "index.json")))
        assert index["regions"][0]["count"] == 2 and index["regions"][0]["updated"] == "2026-09-23"
        first = open(os.path.join(out1, "tirol.geojson")).read()

        # Deterministic: a second run writes the same bytes.
        run(out2, config=cfg, fetcher=lambda _: coll)
        assert open(os.path.join(out2, "tirol.geojson")).read() == first

        # Unreachable source: the previous file stays, the run is still ok.
        def boom(_):
            raise OSError("offline")
        ok, rep = run(out3, previous_dir=out1, config=cfg, fetcher=boom)
        assert ok and "frühere Datei bleibt" in rep[0], rep
        assert open(os.path.join(out3, "tirol.geojson")).read() == first

        # Losing more than a third: not published, run fails.
        shrunk = {"features": coll["features"][2:3]}
        ok, rep = run(out3, previous_dir=out1, config=cfg, fetcher=lambda _: shrunk)
        assert not ok and "NICHT veröffentlicht" in rep[0], rep
        assert open(os.path.join(out3, "tirol.geojson")).read() == first

        # No previous file and unreachable: fails.
        ok, rep = run(os.path.join(d, "4"), config=cfg, fetcher=boom)
        assert not ok
    print("official_trails self-test: ok")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out")
    ap.add_argument("--previous")
    ap.add_argument("--input", action="append", default=[],
                    help="NAME=PATH: read a source from a local file instead")
    ap.add_argument("--summary", help="append a Markdown report here")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        self_test()
        return 0
    if not a.out:
        ap.error("--out fehlt")
    inputs = dict(s.split("=", 1) for s in a.input)
    ok, report = run(a.out, a.previous, inputs)
    text = "## Offizielle Trails\n\n" + "\n".join(f"- {r}" for r in report) + "\n"
    print(text)
    if a.summary:
        with open(a.summary, "a", encoding="utf-8") as fh:
            fh.write(text)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
