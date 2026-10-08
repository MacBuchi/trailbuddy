#!/usr/bin/env python3
"""The regions of the map host (docs/konzept-regionen.md, 18c in #156).

`tool/regions.json` is the one source: which regions exist, their box,
how the map is cut (a rectangle, or Natural Earth countries capped at a
latitude), which Geofabrik extracts carry their ways and places, and
whether an overview is published for them. This tool turns a row into
what a data workflow needs and writes the index the app reads:

    python3 tool/regions.py env ca --workflow map --countries ne.geojson \\
        --out-dir build/region >> "$GITHUB_ENV"
    python3 tool/regions.py index --public-base https://… --out regions.json
    python3 tool/regions.py --self-test          # no network

`env` prints KEY=VALUE lines. The workflows keep their old variable
names (`DACH_BBOX`, `POI_BBOX`, `WAYS_BBOX`, `EXTRACTS`): for DACH the
values are the ones the files already carry, so a DACH run stays byte
for byte what it was, and test/release_workflow_test.dart keeps
guarding them. The self-test holds this file and those lines together.

DACH keeps its old paths at the root of the prefix (apps up to 0.103
read `dach.json`, `heights.json`, `ways.json`, `pois.json`); every other
region lives under `<id>/` with the names `map`, `heights`, `ways`,
`pois`, `overview`.

`index` writes only regions whose map manifest is really on the host: a
region that was never published does not exist for the app. Per layer,
a manifest that is missing is null — the app then has no heights (or
ways, or places) there, the same as before a first build.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG = os.path.join(HERE, "regions.json")
ROOT = os.path.dirname(HERE)
LAYERS = ("map", "heights", "ways", "pois", "overview")
WORKFLOWS = {
    "map": "map-data.yml",
    "heights": "height-data.yml",
    "ways": "way-data.yml",
    "pois": "poi-data.yml",
}
ID = re.compile(r"^[a-z]{2,8}$")
INDEX_FORMAT = 1


def load(path=CONFIG):
    with open(path, encoding="utf-8") as fh:
        config = json.load(fh)
    validate(config)
    return config


def validate(config):
    regions = config.get("regions") or []
    if not regions or regions[0].get("id") != "dach":
        raise SystemExit("regions.json: DACH must be the first region (the legacy paths)")
    seen = set()
    for r in regions:
        rid = r.get("id", "")
        if not ID.match(rid) or rid in seen:
            raise SystemExit(f"regions.json: bad or repeated id {rid!r}")
        seen.add(rid)
        w, s, e, n = r["bbox"]
        if not (-180 <= w < e <= 180 and -85.06 <= s < n <= 85.06):
            raise SystemExit(f"regions.json: {rid} bbox {r['bbox']} is empty or outside the world")
        if not r.get("extracts"):
            raise SystemExit(f"regions.json: {rid} has no extracts")
        m = r.get("map") or {}
        if not (m.get("bbox") is True or m.get("select")):
            raise SystemExit(f"regions.json: {rid} map is neither the bbox nor a selection")
        if rid == "dach" and r.get("overview") is not None:
            raise SystemExit("regions.json: the DACH overview ships in the binary")
    for i, a in enumerate(regions):
        for b in regions[i + 1:]:
            if boxes_overlap(a["bbox"], b["bbox"]):
                raise SystemExit(f"regions.json: {a['id']} and {b['id']} overlap — "
                                 "regions never do (concept 2)")


def boxes_overlap(a, b):
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def region(config, rid):
    for r in config["regions"]:
        if r["id"] == rid:
            return r
    raise SystemExit(f"unknown region {rid!r} (regions.json has "
                     f"{', '.join(r['id'] for r in config['regions'])})")


def region_dir(r):
    """'' for DACH (the legacy root), '<id>/' for every other region."""
    return "" if r["id"] == "dach" else f"{r['id']}/"


def manifest_path(r, layer):
    if r["id"] == "dach":
        return {"map": "dach.json", "heights": "heights.json", "ways": "ways.json",
                "pois": "pois.json", "overview": None}[layer]
    return f"{r['id']}/{layer}.json"


def file_stem(r, layer):
    """The dated file's prefix: `dach` / `ca/map`, `heights` / `ca/heights` …"""
    if r["id"] == "dach":
        return {"map": "dach", "heights": "heights", "ways": "ways", "pois": "pois"}[layer]
    return f"{r['id']}/{layer}"


def bbox_text(r):
    return ",".join(_num(v) for v in r["bbox"])


def _num(v):
    return str(int(v)) if float(v).is_integer() else repr(float(v))


# ------------------------------------------------------------ polygons

def clip_ring_north(ring, north):
    """The part of a closed ring at or below `north` (Sutherland–Hodgman
    against one horizontal edge). Exact for a half-plane, and all a
    latitude cap needs — no shapely on the runner."""
    out = []
    pts = [tuple(p[:2]) for p in ring]
    if pts and pts[0] == pts[-1]:
        pts = pts[:-1]
    if not pts:
        return []
    for i, cur in enumerate(pts):
        prev = pts[i - 1]
        cur_in, prev_in = cur[1] <= north, prev[1] <= north
        if cur_in != prev_in:
            t = (north - prev[1]) / (cur[1] - prev[1])
            out.append((prev[0] + t * (cur[0] - prev[0]), north))
        if cur_in:
            out.append(cur)
    if len(out) < 3:
        return []
    out.append(out[0])
    return [list(p) for p in out]


def select_polygons(geojson, select):
    """[(outer, holes…), …] of the features whose property matches."""
    key, _, values = select.partition("=")
    wanted = set(values.split(","))
    polys = []
    for f in geojson.get("features") or []:
        if str((f.get("properties") or {}).get(key)) not in wanted:
            continue
        g = f.get("geometry") or {}
        if g.get("type") == "Polygon":
            polys.append(g["coordinates"])
        elif g.get("type") == "MultiPolygon":
            polys.extend(g["coordinates"])
    if not polys:
        raise SystemExit(f"no country with {select} in the border file")
    return polys


def region_geojson(geojson, select, north=None):
    """A MultiPolygon FeatureCollection — what `pmtiles extract --region`
    and `map_tiles.py --region` both read."""
    out = []
    for poly in select_polygons(geojson, select):
        rings = [clip_ring_north(r, north) if north is not None else r for r in poly]
        if not rings or not rings[0]:
            continue  # the outer ring lies north of the cap
        out.append([r for r in rings if r])
    if not out:
        raise SystemExit(f"{select}: nothing left south of {north}")
    return {"type": "FeatureCollection", "features": [{
        "type": "Feature", "properties": {"select": select, "north": north},
        "geometry": {"type": "MultiPolygon", "coordinates": out}}]}


# ------------------------------------------------------------- env

def env_lines(r, workflow, countries=None, out_dir=None):
    """KEY=VALUE lines for $GITHUB_ENV."""
    lines = [f"REGION_ID={r['id']}", f"REGION_NAME={r['name']}", f"REGION_DIR={region_dir(r)}"]
    box = bbox_text(r)
    if workflow == "map":
        lines += [f"DACH_BBOX={box}", f"MAP_STEM={file_stem(r, 'map')}",
                  f"MAP_MANIFEST={manifest_path(r, 'map')}"]
        polygon = overview = ""
        if r["map"].get("select"):
            polygon = _write_polygon(countries, out_dir, "region.geojson",
                                     r["map"]["select"], r["map"].get("north"))
        ov = r.get("overview")
        if ov:
            overview = _write_polygon(countries, out_dir, "overview.geojson", ov["select"], None)
        lines += [f"REGION_POLYGON={polygon}", f"OVERVIEW_POLYGON={overview}",
                  f"OVERVIEW_MAXZOOM={(ov or {}).get('maxzoom', '')}",
                  f"OVERVIEW_STEM={r['id'] + '/overview' if ov else ''}",
                  f"OVERVIEW_MANIFEST={manifest_path(r, 'overview') or ''}"]
    elif workflow == "heights":
        polygon = ""
        if r["map"].get("select"):
            polygon = _write_polygon(countries, out_dir, "region.geojson",
                                     r["map"]["select"], r["map"].get("north"))
        lines += [f"DACH_BBOX={box}", f"HEIGHTS_REGION={polygon}",
                  f"HEIGHTS_STEM={file_stem(r, 'heights')}",
                  f"HEIGHTS_MANIFEST={manifest_path(r, 'heights')}"]
    elif workflow == "ways":
        lines += [f"WAYS_BBOX={box}", f"EXTRACTS={' '.join(r['extracts'])}",
                  f"WAYS_STEM={file_stem(r, 'ways')}",
                  f"WAYS_MANIFEST={manifest_path(r, 'ways')}",
                  f"MIN_WAY_TILES={r['min_way_tiles']}"]
    elif workflow == "pois":
        lines += [f"POI_BBOX={box}", f"EXTRACTS={' '.join(r['extracts'])}",
                  f"POIS_STEM={file_stem(r, 'pois')}",
                  f"POIS_MANIFEST={manifest_path(r, 'pois')}",
                  f"MIN_PLACES={r['min_places']}"]
    else:
        raise SystemExit(f"unknown workflow {workflow!r}")
    return lines


def _write_polygon(countries, out_dir, name, select, north):
    if not countries or not out_dir:
        raise SystemExit("this region is cut by a polygon: --countries and --out-dir are needed")
    with open(countries, encoding="utf-8") as fh:
        geo = json.load(fh)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, name)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(region_geojson(geo, select, north), fh)
    return path


# ------------------------------------------------------------- index

def fetch_json(url):
    """The manifest, or None for a 404 (never built). Anything else raises:
    an index written from a host that did not answer would drop regions."""
    # Our own User-Agent: Cloudflare's Browser Integrity Check answers
    # Python's default one with 403 (poi-data.yml, 2026-09-28). And only a
    # 404 means "not built" — a 403 is a zone setting, and reading it as
    # missing would drop a published region from the index.
    req = urllib.request.Request(url, headers={
        "User-Agent": "TrailBuddy regions index (github.com/MacBuchi/trailbuddy)"})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def build_index(config, fetch):
    regions = []
    for r in config["regions"]:
        paths = {layer: manifest_path(r, layer) for layer in LAYERS}
        present = {layer: (p if p and fetch(p) is not None else None) for layer, p in paths.items()}
        if present["map"] is None:
            continue
        regions.append({"id": r["id"], "name": r["name"], "bbox": r["bbox"],
                        "dir": region_dir(r), **present})
    return {"format": INDEX_FORMAT, "regions": regions}


# ------------------------------------------------------------- self-test

def _expect(cond, what):
    if not cond:
        raise AssertionError(what)


def _workflow(name):
    with open(os.path.join(ROOT, ".github", "workflows", name), encoding="utf-8") as fh:
        return fh.read()


def self_test():
    config = load()
    dach = region(config, "dach")
    box = bbox_text(dach)

    # DACH stays what the workflows and the bundled overview say.
    for wf, key in (("map-data.yml", "DACH_BBOX"), ("height-data.yml", "DACH_BBOX"),
                    ("way-data.yml", "WAYS_BBOX"), ("poi-data.yml", "POI_BBOX")):
        m = re.search(rf'^  {key}: "([^"]+)"', _workflow(wf), re.M)
        _expect(m and m.group(1) == box, f"{wf}: {key} is not the DACH box {box} of regions.json")
    for wf in ("way-data.yml", "poi-data.yml"):
        m = re.search(r"^  EXTRACTS: >-\n((?:    .*\n)+)", _workflow(wf), re.M)
        _expect(m and m.group(1).split() == dach["extracts"],
                f"{wf}: EXTRACTS is not the DACH list of regions.json")
    # Every workflow offers every region, and picks it with this tool.
    for layer, wf in WORKFLOWS.items():
        text = _workflow(wf)
        m = re.search(r"region:\n(?:.*\n)*?\s+options: \[([^\]]*)\]", text)
        _expect(m, f"{wf}: no `region` input")
        options = [o.strip().strip('"') for o in m.group(1).split(",")]
        _expect(options == [r["id"] for r in config["regions"]],
                f"{wf}: region options {options} are not the ids of regions.json")
        _expect(f"tool/regions.py env \"$REGION\" --workflow {layer}" in text,
                f"{wf}: does not take its region from tool/regions.py")

    # Legacy paths for DACH, `<id>/` for the rest.
    _expect(manifest_path(dach, "map") == "dach.json", "DACH map manifest")
    _expect(file_stem(dach, "pois") == "pois", "DACH places stem")
    ca = region(config, "ca")
    _expect(manifest_path(ca, "heights") == "ca/heights.json", "ca heights manifest")
    _expect(file_stem(ca, "map") == "ca/map", "ca map stem")
    env = dict(line.split("=", 1) for line in env_lines(dach, "ways"))
    _expect(env["WAYS_BBOX"] == box and env["REGION_DIR"] == "", "DACH env for ways")
    _expect(env["EXTRACTS"].split() == dach["extracts"], "DACH extracts in env")
    _expect(bbox_text(ca) == "-133.2,41.6,-52.6,55", bbox_text(ca))

    # The latitude cap: a square from 50 to 60 N cut at 55 is 50..55.
    square = [[-10, 50], [10, 50], [10, 60], [-10, 60], [-10, 50]]
    cut = clip_ring_north(square, 55)
    _expect(max(p[1] for p in cut) == 55 and min(p[1] for p in cut) == 50, cut)
    _expect(cut[0] == cut[-1] and len(cut) == 5, cut)
    _expect(clip_ring_north([[0, 60], [1, 60], [1, 61], [0, 60]], 55) == [], "north of the cap")
    geo = {"type": "FeatureCollection", "features": [
        {"type": "Feature", "properties": {"ISO_A2_EH": "XX"},
         "geometry": {"type": "MultiPolygon", "coordinates": [[square], [[[0, 70], [1, 70], [1, 71], [0, 70]]]]}},
        {"type": "Feature", "properties": {"ISO_A2_EH": "YY"},
         "geometry": {"type": "Polygon", "coordinates": [square]}}]}
    out = region_geojson(geo, "ISO_A2_EH=XX", 55)
    polys = out["features"][0]["geometry"]["coordinates"]
    _expect(len(polys) == 1, "the polygon north of the cap is dropped, the other country not taken")
    try:
        region_geojson(geo, "ISO_A2_EH=ZZ", 55)
        _expect(False, "an empty selection is an error")
    except SystemExit:
        pass
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "ne.geojson")
        with open(src, "w") as fh:
            json.dump(geo, fh)
        fake = dict(ca, map={"select": "ISO_A2_EH=XX", "north": 55}, overview={"select": "ISO_A2_EH=XX", "maxzoom": 7})
        env = dict(line.split("=", 1) for line in env_lines(fake, "map", src, tmp))
        _expect(env["MAP_STEM"] == "ca/map" and env["MAP_MANIFEST"] == "ca/map.json", env)
        _expect(env["OVERVIEW_STEM"] == "ca/overview" and env["OVERVIEW_MAXZOOM"] == "7", env)
        _expect(os.path.exists(env["REGION_POLYGON"]) and os.path.exists(env["OVERVIEW_POLYGON"]), env)
        env = dict(line.split("=", 1) for line in env_lines(dach, "map"))
        _expect(env["REGION_POLYGON"] == "" and env["OVERVIEW_STEM"] == "", "DACH is a box, no overview")

    # Overlapping regions are refused.
    bad = {"regions": [dach, dict(ca, bbox=[10, 50, 20, 60])]}
    try:
        validate(bad)
        _expect(False, "overlap must be refused")
    except SystemExit:
        pass

    # The index: only regions with a map, null for a missing layer.
    host = {"dach.json": {}, "heights.json": {}, "ways.json": {}, "pois.json": {},
            "ca/map.json": {}, "ca/pois.json": {}}
    index = build_index(config, lambda p: host.get(p))
    _expect([r["id"] for r in index["regions"]] == ["dach", "ca"], index)
    _expect(index["regions"][1]["heights"] is None and index["regions"][1]["pois"] == "ca/pois.json", index)
    _expect(index["regions"][0]["overview"] is None and index["regions"][0]["dir"] == "", index)
    index = build_index(config, lambda p: host.get(p) if not p.startswith("ca/map") else None)
    _expect([r["id"] for r in index["regions"]] == ["dach"], "a region without a map is not listed")
    print("regions self-test ok")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--self-test", action="store_true")
    sub = parser.add_subparsers(dest="cmd")
    e = sub.add_parser("env", help="KEY=VALUE lines for $GITHUB_ENV")
    e.add_argument("region")
    e.add_argument("--workflow", required=True, choices=sorted(WORKFLOWS))
    e.add_argument("--countries", help="Natural Earth countries (GeoJSON), for polygon regions")
    e.add_argument("--out-dir", help="where the region polygons are written")
    i = sub.add_parser("index", help="write regions.json from what the host holds")
    i.add_argument("--public-base", required=True)
    i.add_argument("--out", required=True)
    sub.add_parser("ids", help="the region ids, one per line")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    config = load()
    if args.cmd == "env":
        for line in env_lines(region(config, args.region), args.workflow, args.countries, args.out_dir):
            print(line)
    elif args.cmd == "index":
        base = args.public_base.rstrip("/")
        # A query string past the edge cache: a manifest uploaded a minute
        # ago is up to 300 s old there, and a cached 404 would drop it.
        stamp = int(time.time())
        index = build_index(config, lambda p: fetch_json(f"{base}/{p}?index={stamp}"))
        with open(args.out, "w", encoding="utf-8") as fh:
            json.dump(index, fh, indent=2)
            fh.write("\n")
        print(json.dumps(index, indent=2))
    elif args.cmd == "ids":
        print("\n".join(r["id"] for r in config["regions"]))
    else:
        parser.print_help()
        sys.exit(2)


if __name__ == "__main__":
    main()
