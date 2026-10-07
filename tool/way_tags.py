#!/usr/bin/env python3
"""Way tags in DACH (#211): what OSM says about tracks and paths that our
base map drops — and would a way archive pay for itself?

Our Protomaps tiles carry `kind_detail` (track, path, steps …) and
nothing about the way itself: no tracktype, surface, smoothness,
sac_scale, mtb:scale. Before an archive is built (#212) and routing
prices way quality (#213), this tool answers four questions:

1. coverage — share of length carrying each tag, per highway value and
   country, and per 0.5° cell (thin regions show without borders);
2. values — tracktype grade1–5, smoothness, sac_scale T1–T6, mtb:scale
   0–6 and :uphill, surface in groups;
3. size — a z13 archive of these ways (tags as small integers, geometry
   lightly simplified like the base map) per frame, against the height
   tiles of the same frame, extrapolated to DACH;
4. matching — do the base map's path/track lines find an OSM partner of
   the same class within 3 m / 8 m (and the reverse)? That decides
   between "take the tags over by geometry" and "build path/track edges
   from the way archive".

    python3 tool/way_tags.py stats <pbf> --country DE --out build/de.json
    python3 tool/way_tags.py frames --pbf de=<pbf> --pbf at=<pbf> --pbf ch=<pbf> \\
                                    --out build/frames.json
    python3 tool/way_tags.py report build/*.json [--summary out.md]
    python3 tool/way_tags.py --self-test            # no network, no osmium

Runs on the operator's machine (operator, 2026-10-07: Geofabrik is
blocked from the cloud and every CI round trip is a 4 GB download).
Stdlib plus the `osmium` binary, as poi_extract.py. The ways are read
as a GeoJSON sequence line by line, never all in memory; the frames are
small enough to hold. The report carries numbers and frame names, no
coordinates beyond the three-decimal frame centres below.
"""
from __future__ import annotations

import argparse
import gzip
import json
import math
import os
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import map_tiles  # noqa: E402  (tool/, same directory)
import route_measure  # noqa: E402

HIGHWAYS = ("track", "path", "bridleway", "footway", "cycleway", "steps")
TAGS = ("tracktype", "surface", "smoothness", "sac_scale", "mtb:scale",
        "mtb:scale:uphill", "trail_visibility")
CELL_DEG = 0.5
ZOOM = 13
EXTENT = 4096
SIMPLIFY_UNITS = 1.0      # ~1.2 m at z13 in DACH — about what the base map keeps
SAMPLE_M = 5.0            # matching samples along a line
CORRIDORS = (3.0, 8.0)
EDGE_SHARE = 0.8          # an edge is matched when this share of its samples is

# Four 20 km frames, the regions the base-map check in #211 looked at.
FRAME_KM = 20.0
FRAMES = {
    "Schwarzwald": ("de", 47.87, 8.0),
    "Harz": ("de", 51.78, 10.62),
    "Tirol": ("at", 47.25, 11.4),
    "Berner Oberland": ("ch", 46.62, 8.0),
}

# Base-map class (route_measure.classify) -> the OSM highway values it
# comes from. `pedestrian` is not among our ways; such lines stay unmatched.
CLASS_HIGHWAYS = {
    "forstweg": ("track",),
    "radweg": ("cycleway",),
    "wanderweg": ("path", "bridleway"),
    "fussweg": ("footway",),
    "stufen": ("steps",),
}
HIGHWAY_CLASS = {h: c for c, hs in CLASS_HIGHWAYS.items() for h in hs}

# ------------------------------------------------------------- normalisation

SAC = {"hiking": 1, "mountain_hiking": 2, "demanding_mountain_hiking": 3,
       "alpine_hiking": 4, "demanding_alpine_hiking": 5, "difficult_alpine_hiking": 6}
SMOOTHNESS = ("excellent", "good", "intermediate", "bad", "very_bad",
              "horrible", "very_horrible", "impassable")
VISIBILITY = ("excellent", "good", "intermediate", "bad", "horrible", "no")
SURFACE_GROUPS = {
    "paved": ("asphalt", "paved", "concrete", "concrete:plates", "concrete:lanes",
              "paving_stones", "sett", "cobblestone", "unhewn_cobblestone", "chipseal",
              "metal", "wood", "bricks"),
    "compacted": ("compacted", "fine_gravel"),
    "gravel": ("gravel", "pebblestone", "shells"),
    "natural": ("ground", "dirt", "earth", "grass", "mud", "sand", "unpaved",
                "woodchips", "soil", "forest_floor", "leaves"),
    "rock": ("rock", "stone", "scree"),
    "grass_paver": ("grass_paver",),
}
SURFACE = {v: g for g, vs in SURFACE_GROUPS.items() for v in vs}


def _parts(value):
    return [p.strip().lower() for p in str(value).split(";") if p.strip()]


def _worst(values):
    values = [v for v in values if v is not None]
    return max(values) if values else None


def norm_tracktype(value):
    """'grade2', 'Grade 2', '2' -> 2; several -> the worst; else None."""
    def one(p):
        p = p.replace(" ", "").removeprefix("grade")
        return int(p) if p in ("1", "2", "3", "4", "5") else None
    return _worst(one(p) for p in _parts(value))


def norm_sac(value):
    """sac_scale name or 'T3' -> 1..6; several -> the worst."""
    def one(p):
        if p in SAC:
            return SAC[p]
        if len(p) == 2 and p[0] == "t" and p[1] in "123456":
            return int(p[1])
        return None
    return _worst(one(p) for p in _parts(value))


def norm_mtb(value, top=6):
    """'1+', '2-', 'S3', '3' -> int; several -> the worst."""
    def one(p):
        p = p.removeprefix("s").rstrip("+-")
        return int(p) if p.isdigit() and int(p) <= top else None
    return _worst(one(p) for p in _parts(value))


def norm_rank(value, order):
    """Index into an ordered scale (smoothness, visibility); worst of several."""
    return _worst((order.index(p) if p in order else None) for p in _parts(value))


def norm_surface(value):
    parts = _parts(value)
    return SURFACE.get(parts[0], "other") if parts else None


def normalise(props):
    """{tag: normalised value or 'other'} for the tags a way carries."""
    out = {}
    for tag, fn in (("tracktype", norm_tracktype), ("sac_scale", norm_sac),
                    ("mtb:scale", norm_mtb), ("mtb:scale:uphill", lambda v: norm_mtb(v, 5)),
                    ("smoothness", lambda v: norm_rank(v, SMOOTHNESS)),
                    ("trail_visibility", lambda v: norm_rank(v, VISIBILITY)),
                    ("surface", norm_surface)):
        raw = props.get(tag)
        if raw is None or raw == "":
            continue
        v = fn(raw)
        out[tag] = "other" if v is None else v
    return out


def label(tag, v):
    if v == "other":
        return "other"
    if tag == "tracktype":
        return f"grade{v}"
    if tag == "sac_scale":
        return f"T{v}"
    if tag == "smoothness":
        return SMOOTHNESS[v]
    if tag == "trail_visibility":
        return VISIBILITY[v]
    return str(v)


# ------------------------------------------------------------- geometry

def line_parts(geometry):
    kind = geometry.get("type")
    coords = geometry.get("coordinates") or []
    if kind == "LineString":
        return [coords]
    if kind == "MultiLineString":
        return coords
    return []


def seg_m(lon1, lat1, lon2, lat2):
    return route_measure.trail_match.haversine(lat1, lon1, lat2, lon2)


def line_length(pts):
    return sum(seg_m(*a[:2], *b[:2]) for a, b in zip(pts, pts[1:]))


def cell_key(lon, lat):
    return f"{math.floor(lat / CELL_DEG) * CELL_DEG:.1f},{math.floor(lon / CELL_DEG) * CELL_DEG:.1f}"


# ------------------------------------------------------------- 1+2: stats

def new_stats():
    return {"ways": 0, "km": {}, "tagged_km": {}, "values_km": {}, "cells": {}}


def _add(d, key, v):
    d[key] = d.get(key, 0.0) + v


def add_way(stats, props, geometry):
    """Counts one way into stats; lengths split by cell at segment midpoints."""
    hw = props.get("highway")
    if hw not in HIGHWAYS:
        return
    tags = normalise(props)
    stats["ways"] += 1
    total = 0.0
    for pts in line_parts(geometry):
        for a, b in zip(pts, pts[1:]):
            m = seg_m(a[0], a[1], b[0], b[1])
            total += m
            cell = stats["cells"].setdefault(cell_key((a[0] + b[0]) / 2, (a[1] + b[1]) / 2), {})
            _add(cell, f"{hw}", m / 1000)
            for tag in ("tracktype", "sac_scale", "mtb:scale"):
                if tag in tags:
                    _add(cell, f"{hw}|{tag}", m / 1000)
    km = total / 1000
    _add(stats["km"], hw, km)
    any_quality = False
    for tag, v in tags.items():
        _add(stats["tagged_km"].setdefault(hw, {}), tag, km)
        _add(stats["values_km"].setdefault(hw, {}).setdefault(tag, {}), label(tag, v), km)
        any_quality = any_quality or tag != "surface"
    if tags:
        _add(stats["tagged_km"].setdefault(hw, {}), "any", km)
    if any_quality:
        _add(stats["tagged_km"].setdefault(hw, {}), "any_but_surface", km)


def merge(into, other):
    into["ways"] += other["ways"]
    for key in ("km",):
        for k, v in other[key].items():
            _add(into[key], k, v)
    for hw, tags in other["tagged_km"].items():
        for t, v in tags.items():
            _add(into["tagged_km"].setdefault(hw, {}), t, v)
    for hw, tags in other["values_km"].items():
        for t, vals in tags.items():
            for k, v in vals.items():
                _add(into["values_km"].setdefault(hw, {}).setdefault(t, {}), k, v)
    for c, vals in other["cells"].items():
        for k, v in vals.items():
            _add(into["cells"].setdefault(c, {}), k, v)
    return into


def osmium_ways(pbf, workdir, bbox=None, runner=subprocess.run):
    """Our ways of one extract as GeoJSON features, streamed from a file.

    Every way is a line (area_tags false): a closed footway around a
    square is a way to ride, not an area."""
    src = pbf
    if bbox:
        src = os.path.join(workdir, "frame.osm.pbf")
        w, s, e, n = bbox
        runner(["osmium", "extract", "--overwrite", "-b", f"{w},{s},{e},{n}",
                "-o", src, pbf], check=True)
    filtered = os.path.join(workdir, "ways.osm.pbf")
    exported = os.path.join(workdir, "ways.geojsonl")
    config = os.path.join(workdir, "export.json")
    with open(config, "w", encoding="utf-8") as handle:
        json.dump({"linear_tags": True, "area_tags": False,
                   "include_tags": ["highway", "access"] + list(TAGS)}, handle)
    runner(["osmium", "tags-filter", "--overwrite", "-o", filtered, src,
            "w/highway=" + ",".join(HIGHWAYS)], check=True)
    runner(["osmium", "export", "--overwrite", "-f", "geojsonseq", "-c", config,
            "--geometry-types=linestring", "-o", exported, filtered], check=True)
    try:
        with open(exported, encoding="utf-8") as handle:
            yield from route_measure_features(handle)
    finally:
        for path in (filtered, exported) + ((src,) if bbox else ()):
            if os.path.exists(path):
                os.remove(path)


def route_measure_features(stream):
    for line in stream:
        line = line.strip().lstrip("\x1e").strip()
        if line:
            f = json.loads(line)
            if f.get("type") == "Feature":
                yield f


def stats_of(features):
    stats = new_stats()
    for f in features:
        add_way(stats, f.get("properties") or {}, f.get("geometry") or {})
    return stats


# ------------------------------------------------------------- 3: size

def frame_bbox(lat, lon, size_km=FRAME_KM):
    dlat = size_km / 2 / 111.32
    dlon = dlat / math.cos(math.radians(lat))
    return (lon - dlon, lat - dlat, lon + dlon, lat + dlat)


def simplify(pts, tol):
    """Douglas–Peucker on tile units."""
    if len(pts) < 3:
        return pts
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        i, j = stack.pop()
        (ax, ay), (bx, by) = pts[i], pts[j]
        dx, dy = bx - ax, by - ay
        norm = math.hypot(dx, dy)
        best, idx = -1.0, -1
        for k in range(i + 1, j):
            px, py = pts[k]
            d = (abs(dy * (px - ax) - dx * (py - ay)) / norm) if norm else math.hypot(px - ax, py - ay)
            if d > best:
                best, idx = d, k
        if best > tol:
            keep[idx] = True
            stack += [(i, idx), (idx, j)]
    return [p for p, k in zip(pts, keep) if k]


def lonlat_to_px(lon, lat, z, x, y, extent=EXTENT):
    n = 1 << z
    fx = (lon + 180) / 360 * n
    lr = math.radians(lat)
    fy = (1 - math.log(math.tan(lr) + 1 / math.cos(lr)) / math.pi) / 2 * n
    return (fx - x) * extent, (fy - y) * extent


def packed_props(hw, tags, with_class):
    """Small integers, the way an archive would carry them."""
    props = {}
    if with_class:
        props["c"] = HIGHWAYS.index(hw)
    for key, tag in (("t", "tracktype"), ("s", "sac_scale"), ("m", "mtb:scale"),
                     ("u", "mtb:scale:uphill"), ("q", "smoothness"),
                     ("v", "trail_visibility")):
        v = tags.get(tag)
        if isinstance(v, int):
            props[key] = v
    if tags.get("surface") not in (None, "other"):
        props["f"] = list(SURFACE_GROUPS).index(tags["surface"])
    return props


def build_tiles(features, bbox, with_class):
    """{(z, x, y): gzip bytes} of the ways in bbox at ZOOM.

    Variant a (with_class False): ways with a quality tag only, tags
    alone — the archive that annotates the base map. Variant b: every
    way with its class too — enough to build path/track edges from it.
    """
    w, s, e, n = bbox
    x0, y1 = map_tiles.lonlat_to_tile(w, s, ZOOM)
    x1, y0 = map_tiles.lonlat_to_tile(e, n, ZOOM)
    per_tile = {}
    for f in features:
        props = f.get("properties") or {}
        hw = props.get("highway")
        if hw not in HIGHWAYS:
            continue
        p = packed_props(hw, normalise(props), with_class)
        if not with_class and not p:
            continue
        key = tuple(sorted(p.items()))
        for pts in line_parts(f.get("geometry") or {}):
            lons = [q[0] for q in pts]
            lats = [q[1] for q in pts]
            tx0, ty1 = map_tiles.lonlat_to_tile(min(lons), min(lats), ZOOM)
            tx1, ty0 = map_tiles.lonlat_to_tile(max(lons), max(lats), ZOOM)
            for tx in range(max(tx0, x0), min(tx1, x1) + 1):
                for ty in range(max(ty0, y0), min(ty1, y1) + 1):
                    px = [lonlat_to_px(lo, la, ZOOM, tx, ty) for lo, la in (q[:2] for q in pts)]
                    for piece in route_measure.clip_line(px, EXTENT):
                        piece = simplify(piece, SIMPLIFY_UNITS)
                        q = [(int(round(a)), int(round(b))) for a, b in piece]
                        q = [q[0]] + [b for a, b in zip(q, q[1:]) if b != a]
                        if len(q) >= 2:
                            per_tile.setdefault((tx, ty), {}).setdefault(key, []).append(q)
    tiles = {}
    for (tx, ty), groups in per_tile.items():
        feats = [(dict(k), lines) for k, lines in groups.items()]
        raw = route_measure.encode_mvt_lines(feats, layer_name="ways", extent=EXTENT)
        tiles[(ZOOM, tx, ty)] = gzip.compress(raw, 9, mtime=0)
    return tiles


def archive_bytes(tiles, bbox):
    if not tiles:
        return 0
    return len(map_tiles._build_archive(tiles, tile_compression=map_tiles.COMPRESSION_GZIP,
                                        tile_type=1, bounds=bbox))


def height_bytes(bbox, archive=None):
    """Bytes the height archive spends on bbox at z13 (directory reads only)."""
    if archive is None:
        manifest = json.loads(route_measure.fetch_bytes(f"{route_measure.PUBLIC_BASE}/heights.json"))
        archive = map_tiles.Archive(map_tiles.HttpSource(
            f"{route_measure.PUBLIC_BASE}/{manifest['file']}"))
    _, byte_count, _ = map_tiles.plan_extract(archive, bbox, ZOOM, ZOOM)
    return byte_count[ZOOM]


# ------------------------------------------------------------- 4: matching

class SegIndex:
    """Segments in local metres on a grid, nearest distance per class."""

    def __init__(self, lat0, cell=25.0):
        self.k = math.cos(math.radians(lat0))
        self.cell = cell
        self.grid = {}

    def xy(self, lon, lat):
        r = route_measure.R_EARTH
        return math.radians(lon) * r * self.k, math.radians(lat) * r

    def add(self, cls, lonlat):
        xy = [self.xy(lo, la) for lo, la in lonlat]
        for a, b in zip(xy, xy[1:]):
            for c in self._cells(a, b):
                self.grid.setdefault(c, []).append((cls, a, b))

    def _cells(self, a, b):
        c = self.cell
        for gx in range(int(min(a[0], b[0]) // c), int(max(a[0], b[0]) // c) + 1):
            for gy in range(int(min(a[1], b[1]) // c), int(max(a[1], b[1]) // c) + 1):
                yield gx, gy

    def near(self, cls, p, radius):
        c = self.cell
        reach = int(math.ceil(radius / c))
        gx, gy = int(p[0] // c), int(p[1] // c)
        for dx in range(-reach, reach + 1):
            for dy in range(-reach, reach + 1):
                for scls, a, b in self.grid.get((gx + dx, gy + dy), ()):
                    if scls == cls and _dist(p, a, b) <= radius:
                        return True
        return False


def _dist(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    L = dx * dx + dy * dy
    t = 0.0 if L == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / L))
    return math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy)


def samples(index, lonlat, step=SAMPLE_M, bbox=None):
    """[(xy, weight)] every `step` metres; with bbox only the samples
    inside it — the base map's tiles reach past the frame, the OSM ways
    of a frame do not, and outside it nothing could match."""
    xy = [index.xy(lo, la) for lo, la in lonlat]
    out = []
    for (a, b), (la, lb) in zip(zip(xy, xy[1:]), zip(lonlat, lonlat[1:])):
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        n = max(1, int(L // step))
        for i in range(n):
            t = (i + 0.5) / n
            if bbox is not None:
                lon, lat = la[0] + t * (lb[0] - la[0]), la[1] + t * (lb[1] - la[1])
                if not (bbox[0] <= lon <= bbox[2] and bbox[1] <= lat <= bbox[3]):
                    continue
            out.append(((a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])), L / n))
    return out


def match_share(index, lines, corridors=CORRIDORS, bbox=None):
    """{cls: {'m': length, corridor: matched length}} over [(cls, lonlat)]."""
    out = {}
    for cls, lonlat in lines:
        row = out.setdefault(cls, {"m": 0.0, **{r: 0.0 for r in corridors}})
        for p, w in samples(index, lonlat, bbox=bbox):
            row["m"] += w
            for r in corridors:
                if index.near(cls, p, r):
                    row[r] += w
    return out


def edge_match(index, edges, corridors=CORRIDORS, share=EDGE_SHARE, bbox=None):
    """{corridor: (matched edges, edges)} — an edge counts when `share`
    of its sampled length lies within the corridor of a same-class way."""
    out = {r: [0, 0] for r in corridors}
    for cls, lonlat in edges:
        ss = samples(index, lonlat, bbox=bbox)
        if not ss:
            continue
        total = sum(w for _, w in ss)
        for r in corridors:
            out[r][1] += 1
            if sum(w for p, w in ss if index.near(cls, p, r)) / total >= share:
                out[r][0] += 1
    return {r: tuple(v) for r, v in out.items()}


def osm_lines(features):
    out = []
    for f in features:
        cls = HIGHWAY_CLASS.get((f.get("properties") or {}).get("highway"))
        if cls is None:
            continue
        for pts in line_parts(f.get("geometry") or {}):
            out.append((cls, [tuple(q[:2]) for q in pts]))
    return out


def measure_matching(osm, base_lines, lat0, bbox=None):
    """osm: [(cls, lonlat)], base_lines: route_measure.load_lines output."""
    base = [(cls, pts) for cls, _, pts, _ in base_lines if cls in CLASS_HIGHWAYS]
    osm_index = SegIndex(lat0)
    for cls, pts in osm:
        osm_index.add(cls, pts)
    base_index = SegIndex(lat0)
    for cls, pts in base:
        base_index.add(cls, pts)
    g, _, _ = route_measure.build_graph(base_lines, lat0, split_crossings=True)
    edges = [(e.cls, [(lo, la) for la, lo in e.latlon]) for e in g.edges
             if e.cls in CLASS_HIGHWAYS and e.length > 0]
    return {
        "base_to_osm": match_share(osm_index, base, bbox=bbox),
        "osm_to_base": match_share(base_index, osm, bbox=bbox),
        "edges": edge_match(osm_index, edges, bbox=bbox),
    }


def measure_frames(pbfs, frames=FRAMES, base_archive=None, height_archive=None,
                   ways_fn=None, log=print):
    out = {}
    base_archive = base_archive or route_measure.host_archive()
    for name, (country, lat, lon) in frames.items():
        started = time.time()
        bbox = frame_bbox(lat, lon)
        if ways_fn is not None:
            feats = list(ways_fn(country, bbox))
        else:
            with tempfile.TemporaryDirectory() as workdir:
                feats = list(osmium_ways(pbfs[country], workdir, bbox=bbox))
        st = stats_of(feats)
        sizes = {v: archive_bytes(build_tiles(feats, bbox, v == "b"), bbox) for v in ("a", "b")}
        heights = height_bytes(bbox, height_archive)
        base_lines, _ = route_measure.load_lines(base_archive, bbox)
        match = measure_matching(osm_lines(feats), base_lines, lat, bbox)
        out[name] = {"stats": st, "bytes": sizes, "height_bytes": heights,
                     "km": sum(st["km"].values()), "match": _jsonable(match)}
        log(f"{name}: {len(feats)} ways, a {sizes['a']} B, b {sizes['b']} B, "
            f"heights {heights} B, {time.time() - started:.0f} s")
    return out


def _jsonable(match):
    def keys(d):
        return {str(k): (keys(v) if isinstance(v, dict) else list(v) if isinstance(v, tuple) else v)
                for k, v in d.items()}
    return keys(match)


# ------------------------------------------------------------- report

def pct(part, whole):
    return f"{100 * part / whole:.0f} %" if whole else "–"


def mib(b):
    return f"{b / 2**20:.1f} MiB"


def render(countries, frames=None, dach_height_bytes=None):
    out = ["## #211 — Wege-Tags in DACH", ""]
    total = new_stats()
    for st in countries.values():
        merge(total, st)
    columns = list(countries) + ["alle"]
    rows = dict(countries, alle=total)

    out += ["### Länge je Wegart (km)", "",
            "| highway | " + " | ".join(columns) + " |",
            "|---|" + "---:|" * len(columns)]
    for hw in HIGHWAYS:
        out.append(f"| {hw} | " + " | ".join(f"{rows[c]['km'].get(hw, 0):,.0f}" for c in columns) + " |")
    out.append("")

    for hw, tags in (("track", ("tracktype", "surface", "smoothness", "mtb:scale")),
                     ("path", ("sac_scale", "mtb:scale", "mtb:scale:uphill", "surface",
                               "smoothness", "trail_visibility")),
                     ("bridleway", ("sac_scale", "mtb:scale", "surface")),
                     ("footway", ("sac_scale", "mtb:scale", "surface")),
                     ("cycleway", ("surface", "smoothness")),
                     ("steps", ("surface",))):
        out += [f"### Abdeckung `{hw}` (Anteil der Länge)", "",
                "| Tag | " + " | ".join(columns) + " |", "|---|" + "---:|" * len(columns)]
        for tag in tags + ("any_but_surface", "any"):
            out.append(f"| {tag} | " + " | ".join(
                pct(rows[c]["tagged_km"].get(hw, {}).get(tag, 0), rows[c]["km"].get(hw, 0))
                for c in columns) + " |")
        out.append("")

    out += ["### Werteverteilung (alle Länder, Anteil der getaggten Länge)", ""]
    for hw, tag in (("track", "tracktype"), ("track", "smoothness"), ("track", "surface"),
                    ("path", "sac_scale"), ("path", "mtb:scale"), ("path", "mtb:scale:uphill"),
                    ("path", "surface"), ("track", "mtb:scale")):
        vals = total["values_km"].get(hw, {}).get(tag, {})
        whole = sum(vals.values())
        order = sorted(vals, key=lambda k: (k == "other", _sort_key(tag, k)))
        out.append(f"- `{hw}` · `{tag}` ({whole:,.0f} km): " + ", ".join(
            f"{k} {pct(vals[k], whole)}" for k in order))
    out.append("")

    out += ["### Zellen (0,5°): wie ungleich ist die Abdeckung?", "",
            "Anteil der Länge je Zelle mit mindestens 50 km Weg dieser Art; "
            "Quartile über die Zellen.", "",
            "| Maß | Zellen | Min | 25 % | Median | 75 % | Max |", "|---|---:|---:|---:|---:|---:|---:|"]
    for hw, tag in (("track", "tracktype"), ("path", "sac_scale"), ("path", "mtb:scale")):
        shares = sorted(v.get(f"{hw}|{tag}", 0) / v[hw] for v in total["cells"].values()
                        if v.get(hw, 0) >= 50)
        if shares:
            q = [shares[int(round(p * (len(shares) - 1)))] for p in (0, .25, .5, .75, 1)]
            out.append(f"| `{hw}` · `{tag}` | {len(shares)} | " + " | ".join(f"{100 * x:.0f} %" for x in q) + " |")
    out.append("")

    if frames:
        out += ["### Größe je 20-km-Rahmen (z13, gzip)", "",
                "a = nur Wege mit Qualitäts-Tag, nur die Tags; b = alle Wege mit Klasse. "
                "Höhen = die Höhenkacheln desselben Rahmens.", "",
                "| Rahmen | Weg-km | a | b | Höhen | a/Höhen | b/Höhen |",
                "|---|---:|---:|---:|---:|---:|---:|"]
        ra = rb = kms = hs = 0
        for name, fr in frames.items():
            a, b, h = fr["bytes"]["a"], fr["bytes"]["b"], fr["height_bytes"]
            ra, rb, kms, hs = ra + a, rb + b, kms + fr["km"], hs + h
            out.append(f"| {name} | {fr['km']:,.0f} | {mib(a)} | {mib(b)} | {mib(h)} | "
                       f"{pct(a, h)} | {pct(b, h)} |")
        out.append("")
        dach_km = sum(total["km"].values())
        lines = [f"Hochgerechnet über Bytes je Weg-km ({dach_km:,.0f} km in den Auszügen): "
                 f"a ≈ {mib(ra / kms * dach_km)}, b ≈ {mib(rb / kms * dach_km)}."]
        if dach_height_bytes:
            lines.append(f"Über das Verhältnis zu den Höhen ({mib(dach_height_bytes)}): "
                         f"a ≈ {mib(ra / hs * dach_height_bytes)}, b ≈ {mib(rb / hs * dach_height_bytes)}.")
        out += lines + [""]

        out += ["### Abgleich mit der Grundkarte", "",
                "Anteil der Länge (Proben alle 5 m), der innerhalb 3 m / 8 m einen Weg derselben "
                "Klasse findet. Kanten: Graph aus `build_graph`, eine Kante zählt bei "
                f"{EDGE_SHARE:.0%} ihrer Länge im Korridor.", "",
                "| Rahmen | Klasse | Karte km | Karte→OSM 3 m | 8 m | OSM km | OSM→Karte 3 m | 8 m |",
                "|---|---|---:|---:|---:|---:|---:|---:|"]
        for name, fr in frames.items():
            b2o, o2b = fr["match"]["base_to_osm"], fr["match"]["osm_to_base"]
            for cls in CLASS_HIGHWAYS:
                b, o = b2o.get(cls), o2b.get(cls)
                if not b and not o:
                    continue
                b = b or {"m": 0, "3.0": 0, "8.0": 0}
                o = o or {"m": 0, "3.0": 0, "8.0": 0}
                out.append(f"| {name} | {cls} | {b['m'] / 1000:,.0f} | {pct(b['3.0'], b['m'])} | "
                           f"{pct(b['8.0'], b['m'])} | {o['m'] / 1000:,.0f} | {pct(o['3.0'], o['m'])} | "
                           f"{pct(o['8.0'], o['m'])} |")
        out += ["", "| Rahmen | Kanten | Treffer 3 m | 8 m |", "|---|---:|---:|---:|"]
        for name, fr in frames.items():
            e = fr["match"]["edges"]
            out.append(f"| {name} | {e['3.0'][1]:,} | {pct(*e['3.0'])} | {pct(*e['8.0'])} |")
        out.append("")
    return "\n".join(out)


def _sort_key(tag, k):
    if tag == "surface":
        return list(SURFACE_GROUPS).index(k) if k in SURFACE_GROUPS else 99
    if tag == "smoothness":
        return SMOOTHNESS.index(k) if k in SMOOTHNESS else 99
    return k


# ------------------------------------------------------------- self-test

def _feature(hw, coords, **tags):
    return {"type": "Feature", "properties": {"highway": hw, **tags},
            "geometry": {"type": "LineString", "coordinates": coords}}


def self_test():
    ok = True

    def check(cond, what):
        nonlocal ok
        print(("ok   " if cond else "FAIL ") + what)
        ok = ok and cond

    # Normalisation.
    check(norm_tracktype("grade 2") == 2 and norm_tracktype("Grade5") == 5
          and norm_tracktype("grade1;grade3") == 3 and norm_tracktype("grade6") is None,
          "tracktype: spaces, case, worst of several, nonsense")
    check(norm_sac("T3;T4") == 4 and norm_sac("demanding_mountain_hiking") == 3
          and norm_sac("mountain_hiking;hiking") == 2 and norm_sac("T7") is None,
          "sac_scale: names, T-form, worst of several")
    check(norm_mtb("1+") == 1 and norm_mtb("2-") == 2 and norm_mtb("S3") == 3
          and norm_mtb("0;1") == 1 and norm_mtb("7") is None and norm_mtb("6", 5) is None,
          "mtb:scale: +/-, S-prefix, worst, range")
    check(norm_surface("asphalt") == "paved" and norm_surface("fine_gravel") == "compacted"
          and norm_surface("lava") == "other" and norm_rank("very_bad", SMOOTHNESS) == 4,
          "surface groups and smoothness rank")
    check(normalise({"tracktype": "grade9", "sac_scale": ""}) == {"tracktype": "other"},
          "unknown value counts as tagged 'other', empty as untagged")

    # Lengths and shares: 1 km of track along a meridian (about 0.009°).
    dlat = 1000 / 111195.0
    track = _feature("track", [[9.0, 47.9], [9.0, 47.9 + dlat / 2], [9.0, 47.9 + dlat]],
                     tracktype="grade3")
    path = _feature("path", [[9.1, 47.9], [9.1, 47.9 + dlat]], sac_scale="T2", surface="ground")
    bare = _feature("track", [[9.2, 47.9], [9.2, 47.9 + 3 * dlat]])
    foot = {"type": "Feature", "properties": {"highway": "residential"},
            "geometry": {"type": "LineString", "coordinates": [[9, 47], [9, 48]]}}
    st = stats_of([track, path, bare, foot])
    check(abs(st["km"]["track"] - 4.0) < 0.01 and abs(st["km"]["path"] - 1.0) < 0.01
          and "residential" not in st["km"], "lengths per highway, other highways ignored")
    check(abs(st["tagged_km"]["track"]["tracktype"] / st["km"]["track"] - 0.25) < 0.01,
          "share of tagged track length is 1 of 4 km")
    check(abs(st["tagged_km"]["path"]["any_but_surface"] - 1.0) < 0.01
          and abs(st["values_km"]["path"]["sac_scale"]["T2"] - 1.0) < 0.01,
          "value distribution in km")

    # Cells: a track crossing the 48.0° line splits between two cells.
    cross = _feature("track", [[9.3, 47.99], [9.3, 48.0], [9.3, 48.01]], tracktype="grade1")
    st2 = stats_of([cross])
    check(set(st2["cells"]) == {"47.5,9.0", "48.0,9.0"}
          and abs(st2["cells"]["47.5,9.0"]["track"] - st2["cells"]["48.0,9.0"]["track"]) < 1e-6,
          "cell split at segment midpoints")
    merged = merge(merge(new_stats(), st), st2)
    check(merged["ways"] == 4 and abs(merged["km"]["track"] - st["km"]["track"] - st2["km"]["track"]) < 1e-9,
          "merge sums ways and lengths")

    # Size build: round trip through the MVT decoder.
    bbox = frame_bbox(47.9, 9.0, 2.0)
    feats = [_feature("track", [[8.995, 47.9], [9.005, 47.9]], tracktype="grade4", surface="gravel"),
             _feature("path", [[9.0, 47.895], [9.0, 47.905]])]
    tiles_a = build_tiles(feats, bbox, with_class=False)
    tiles_b = build_tiles(feats, bbox, with_class=True)
    dec = [p for t in tiles_a.values() for _, p, _ in route_measure.decode_mvt_lines(gzip.decompress(t), "ways")]
    check(dec and all(p == {"t": "4", "f": "2"} for p in dec), "variant a: tagged ways only, tags as integers")
    dec_b = [p for t in tiles_b.values() for _, p, _ in route_measure.decode_mvt_lines(gzip.decompress(t), "ways")]
    check({p.get("c") for p in dec_b} == {"0", "1"}, "variant b: every way with its class")
    check(archive_bytes(tiles_b, bbox) > archive_bytes(tiles_a, bbox) > 0, "b is larger than a")
    straight = [(0, 0), (1, 0.2), (2, -0.2), (3, 0), (3, 10)]
    check(simplify(straight, 1.0) == [(0, 0), (3, 0), (3, 10)], "simplify keeps the corner only")

    # Matching on synthetic lines: a base line 2 m off its OSM twin, one
    # 5 m off, one with no twin; one OSM path of another class on top.
    lat0 = 47.9
    off = lambda m: m / 111195.0  # noqa: E731
    osm = [("forstweg", [(9.0, lat0), (9.01, lat0)]),
           ("wanderweg", [(9.0, lat0 + off(100)), (9.01, lat0 + off(100))]),
           ("fussweg", [(9.0, lat0 + off(300)), (9.01, lat0 + off(300))])]
    base = [("forstweg", False, [(9.0, lat0 + off(2)), (9.01, lat0 + off(2))], 0),
            ("wanderweg", False, [(9.0, lat0 + off(105)), (9.01, lat0 + off(105))], 0),
            ("forstweg", False, [(9.0, lat0 + off(200)), (9.01, lat0 + off(200))], 0),
            ("wanderweg", False, [(9.0, lat0 + off(301)), (9.01, lat0 + off(301))], 0)]
    m = measure_matching(osm, base, lat0)
    f, w = m["base_to_osm"]["forstweg"], m["base_to_osm"]["wanderweg"]
    check(abs(f[3.0] / f["m"] - 0.5) < 0.02 and abs(f[8.0] / f["m"] - 0.5) < 0.02,
          "forstweg: 2 m twin matches, lone line does not")
    check(w[3.0] < 0.55 * w["m"] and abs(w[8.0] / w["m"] - 0.5) < 0.02,
          "wanderweg: 5 m off matches at 8 m only; another class never")
    check(m["osm_to_base"]["fussweg"][8.0] == 0, "reverse: footway has no same-class partner")
    check(m["edges"][8.0] == (2, 4) and m["edges"][3.0] == (1, 4), "edges matched per corridor")
    # Clipped to the western half: lengths halve, shares stay.
    half = (8.99, lat0 - off(50), 9.005, lat0 + off(400))
    mh = measure_matching(osm, base, lat0, half)
    fh = mh["base_to_osm"]["forstweg"]
    check(abs(fh["m"] / f["m"] - 0.5) < 0.02 and abs(fh[8.0] / fh["m"] - 0.5) < 0.02,
          "frame bbox: only samples inside count")

    # The osmium runner, faked: argument shape, cleanup, streaming.
    calls = []

    def fake(cmd, check):
        calls.append(cmd)
        if cmd[1] == "export":
            with open(cmd[cmd.index("-o") + 1], "w", encoding="utf-8") as h:
                h.write("\x1e" + json.dumps(track) + "\n\n" + json.dumps(path) + "\n")
        else:
            open(cmd[cmd.index("-o") + 1], "w").close()

    with tempfile.TemporaryDirectory() as wd:
        got = list(osmium_ways("x.osm.pbf", wd, bbox=(9.0, 47.0, 9.5, 47.5), runner=fake))
        left = sorted(os.listdir(wd))
    check(len(got) == 2 and [c[1] for c in calls] == ["extract", "tags-filter", "export"],
          "osmium: extract, tags-filter, export in that order")
    check(calls[1][-1] == "w/highway=" + ",".join(HIGHWAYS) and "-c" in calls[2],
          "osmium: way filter and export config")
    check(left == ["export.json"], "osmium: intermediate files removed")

    # The report renders from both inputs.
    md = render({"DE": st, "AT": st2}, {"T": {"stats": st, "bytes": {"a": 10, "b": 20},
                                              "height_bytes": 40, "km": 5.0, "match": _jsonable(m)}},
                dach_height_bytes=400)
    check("| track | 4 | 2 | 6 |" in md and "a ≈ 0.0 MiB" in md and "| T | forstweg |" in md,
          "report renders countries and frames")
    if not ok:
        sys.exit(1)
    print("self-test passed")


# ------------------------------------------------------------- main

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--self-test", action="store_true")
    sub = parser.add_subparsers(dest="command")
    s = sub.add_parser("stats", help="coverage and values of one extract")
    s.add_argument("pbf")
    s.add_argument("--country", required=True)
    s.add_argument("--out", required=True)
    f = sub.add_parser("frames", help="size and matching in the four frames")
    f.add_argument("--pbf", action="append", default=[], help="country=path, e.g. de=germany.osm.pbf")
    f.add_argument("--out", required=True)
    r = sub.add_parser("report", help="Markdown from stats and frames files")
    r.add_argument("files", nargs="+")
    r.add_argument("--summary")
    args = parser.parse_args(argv)

    if args.self_test:
        self_test()
        return
    started = time.time()
    if args.command == "stats":
        with tempfile.TemporaryDirectory() as workdir:
            st = stats_of(osmium_ways(args.pbf, workdir))
        st["country"] = args.country
        with open(args.out, "w", encoding="utf-8") as h:
            json.dump(st, h)
        print(f"{args.country}: {st['ways']} ways, {sum(st['km'].values()):,.0f} km, "
              f"{time.time() - started:.0f} s")
    elif args.command == "frames":
        pbfs = dict(p.split("=", 1) for p in args.pbf)
        fr = measure_frames(pbfs)
        with open(args.out, "w", encoding="utf-8") as h:
            json.dump({"frames": fr}, h)
    elif args.command == "report":
        countries, frames = {}, None
        for path in args.files:
            with open(path, encoding="utf-8") as h:
                data = json.load(h)
            if "frames" in data:
                frames = data["frames"]
            else:
                countries[data.pop("country")] = data
        manifest = json.loads(route_measure.fetch_bytes(f"{route_measure.PUBLIC_BASE}/heights.json"))
        md = render(countries, frames, manifest.get("bytes"))
        print(md)
        if args.summary:
            with open(args.summary, "w", encoding="utf-8") as h:
                h.write(md)
    else:
        parser.print_help()
        sys.exit(2)


if __name__ == "__main__":
    main()
