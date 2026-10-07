#!/usr/bin/env python3
"""Routing measurement (#35): do our z13 tiles carry a graph the own engine
can route on? — the five questions of docs/konzept-routing.md section 6.

The engine decision is made (own engine, no BRouter; concept section 0).
What this tool measures is the DATA side, because that is where it can
fail: the `roads` layer of the Protomaps tiles is cut for drawing, not
for graphs. Nothing in lib/ is built before this report exists.

Two modes, one code path:

    python3 tool/route_measure.py tirol  --out build/route [--frames 3]
    python3 tool/route_measure.py rides  --trails <zip|dir> --rides <dir> \\
                                         --profile bio --out build/route
    python3 tool/route_measure.py --self-test            # no network

`tirol` is the public half and runs in CI (route-measure.yml): the
official trails of Tirol from the data branch, z13 tiles from the own
host via Range requests (exactly as the app reads them), heights from
the open Copernicus GLO-90 bucket. It answers M1 (connectivity), M3 in
its Tirol half (DEM vs. the source's up/down metres), M5 (runtime) and
prints example climbs so a human can judge the cost table.

`rides` is the private half and runs on the operator's machine: the GPX
collection and the exported rides (#150) never leave it. It answers M2
(class mix of real climbs), M4 (does A* find the climb the operator
rode?) and the calibration of the time model. The report carries
counts, never coordinates and never names — same rule as
trail_match.py.

Everything here is stdlib: an MVT decoder (protobuf wire format, a
hundred lines), a COG reader for the DEM tiles (tiled TIFF, deflate,
floating-point predictor), a graph builder, Dijkstra and A*. The cost
table and the time model mirror konzept-routing.md 2.1–2.4 and will be
mirrored again by the Dart engine; tool and Dart change in the SAME PR,
as trail_match.py and the SQL do.

Measured before writing this (2026-10-01): the roads layer carries kind,
kind_detail, access, oneway, is_bridge, is_tunnel, service — and no
surface, tracktype, mtb:scale or sac_scale. The class table works on
what is there.
"""
from __future__ import annotations

import argparse
import heapq
import io
import json
import math
import os
import statistics
import struct
import sys
import time
import urllib.request
import zipfile
import zlib
from dataclasses import dataclass, field

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import map_tiles  # noqa: E402  (tool/, same directory)
import trail_match  # noqa: E402

PUBLIC_BASE = "https://tiles.mcbuchi.de/trailbuddy"
OFFICIAL_BASE = "https://raw.githubusercontent.com/MacBuchi/trailbuddy/official-trails-data"
DEM_BUCKET = "https://copernicus-dem-90m.s3.amazonaws.com/"
USER_AGENT = "trailbuddy-route-measure/1.0"

ROAD_ZOOM = 13            # kRoadTileZoom — paths and tracks are in the tiles from here
ATTACH_M = 30.0           # a trail end attaches to the graph within this (GPS slack)
JOIN_M = 2.0              # dead ends joined to a segment within this (tile borders)
SAMPLE_M = 50.0           # DEM sampled along an edge every this many metres
HYSTERESIS_M = 10.0       # climb counting on a 90 m DEM; 3 m is for recorded heights
R_EARTH = trail_match.R_EARTH

# ------------------------------------------------------------- profiles
# konzept-routing.md 2.1–2.4. Rates in m/h, speeds in km/h, factors
# dimensionless (cost = time × factor).

PROFILES = {
    "bio": {
        "climb_track": 450.0, "climb_path": 350.0, "push_rate": 300.0,
        "v_flat": 15.0, "v_path_up": 8.0, "v_push": 3.0, "v_down": 25.0,
        "path_up": 1.4, "path_down": 2.0,
        "budget_climb": 800.0,
    },
    "ebike": {
        "climb_track": 850.0, "climb_path": 650.0, "push_rate": 220.0,
        "v_flat": 20.0, "v_path_up": 10.0, "v_push": 2.5, "v_down": 25.0,
        "path_up": 2.0, "path_down": 2.5,
        "budget_climb": 1400.0,
    },
}
BUDGET_HOURS = 3.0
BUDGET_HIKING_KM = 2.0
TRAIL_DOWN_KMH = {0: 16.0, 1: 12.0, 2: 9.0, 3: 6.0, 4: 4.0, 5: 4.0, None: 10.0}

# class -> (factor up, factor down, flat speed key, climb rate key, hiking?)
# The two hiking factors are per profile and read from it ("path").
CLASSES = {
    "forstweg":      (1.0, 1.0, "v_flat", "climb_track", False),
    "radweg":        (1.0, 1.0, "v_flat", "climb_track", False),
    "nebenstrasse":  (1.2, 1.2, "v_flat", "climb_track", False),
    "zufahrt":       (1.2, 1.2, "v_flat", "climb_track", False),
    "wanderweg":     ("path_up", "path_down", "v_path_up", "climb_path", True),
    "fussweg":       (2.0, 2.5, "v_path_up", "climb_path", True),
    "stufen":        (3.0, 3.0, "v_push", "push_rate", True),
    "landstrasse":   (1.6, 1.6, "v_flat", "climb_track", False),
    "hauptstrasse":  (2.5, 2.5, "v_flat", "climb_track", False),
    "bundesstrasse": (4.0, 4.0, "v_flat", "climb_track", False),
}
ROAD_CLASSES = {"nebenstrasse", "zufahrt", "landstrasse", "hauptstrasse", "bundesstrasse"}

# Steep climbs (#194, field report 0.74.0: "super steep climbs should be
# penalised, especially when not paved but only a track"). The height
# samples of an edge (every SAMPLE_M) are smoothed over STEEP_SMOOTH
# samples — a road on a steep slope sits a few metres off its DEM line,
# and across a 40 % flank that alone is several per cent per step — and
# every metre a step rises above STEEP_GRADE of its length is a steep
# metre. Steep metres cost their climb time again, times the class
# factor: a cost, not minutes — the time model stays what the rides
# calibrate. Uphill trails and connectors carry none: they are the
# climb someone chose (#185). Set by the Tirol run (docs/routing-messung.md).
STEEP_GRADE = 0.15
STEEP_GRADES = (0.10, 0.12, 0.15, 0.18, 0.20, 0.25)   # what the Tirol report compares
STEEP_SMOOTH = 3
# Unpaved hurts most; on asphalt a steep ramp is hard, not loose. Steps
# are pushed anyway (push_rate), there is nothing to add.
STEEP_FACTOR = {
    "forstweg": 3.0, "wanderweg": 3.0, "fussweg": 3.0, "stufen": 0.0,
    "radweg": 1.0, "nebenstrasse": 1.0, "zufahrt": 1.0,
    "landstrasse": 1.0, "hauptstrasse": 1.0, "bundesstrasse": 1.0,
}


# Since #188 the surcharge does not start at a threshold: every metre
# climbed costs its climb time again times a weight that grows
# exponentially with the grade (operator 2026-10-02: "sehr steil bergauf
# wird exponentiell teurer") — nothing below STEEP_W_FROM, ×3 per five
# points of grade, 0.14 at 15 %, 0.57 at 20 %, 1.9 at 25 %, 5.7 at 30 %,
# capped at STEEP_W_MAX. STEEP_GRADE stays what the result calls "steep"
# (steep_excess, the note), the weight is what it costs.
STEEP_W_FROM = 0.10
STEEP_W_REF = 0.22
STEEP_W_SCALE = 0.0455
STEEP_W_MAX = 30.0

# A metre down on a connection costs this share of climbing it back
# (operator: "Bergab ist teurer") — height is spent where a trail could
# have spent it. Trails and connectors carry none.
DESCENT_COST = 0.3

# Steps uphill (#210, operator field note 2026-10-02: "Treppen bergauf
# stark meiden — da wird getragen"): carrying is a stop, not a slower
# speed, so a steps edge that climbs (gain > loss) costs CARRY_S on top,
# independent of its length. Downhill and without heights nothing (the
# direction is unknown). A split shares it by length (Edge.carry), so an
# attached trail head does not count one flight twice. With the class
# factor ×3 a 20 m flight with 4 hm now loses against about 1 km of
# forest track (bio) instead of 0.8 km. A cost, not minutes.
CARRY_S = 60.0

# Route preferences (#188): three switches, "avoid" (the default, the
# full surcharge) or "don't mind" (this share of it). Never zero — a
# rider who does not mind roads still takes the track when it is as fast.
PREF_KEYS = ("roads", "hiking", "steep")
PREF_ANY = {"roads": 0.35, "hiking": 0.35, "steep": 0.3}


def pref_strength(prefs, key):
    """1.0 for "avoid" (and without prefs), the reduced share otherwise."""
    return 1.0 if prefs is None or prefs.get(key, True) else PREF_ANY[key]


def classify(kind, detail, access=None, service=None):
    """Way class for a roads feature, or None when the engine must not use it."""
    if access in ("private", "no"):
        return None
    if kind == "major_road":
        return "bundesstrasse" if (detail or "").startswith("primary") else "hauptstrasse"
    if kind == "medium_road":
        return "landstrasse"
    if kind == "minor_road":
        if detail == "service":
            return None if service in ("driveway", "parking_aisle") else "zufahrt"
        return "nebenstrasse"
    if kind == "path":
        return {
            "track": "forstweg", "cycleway": "radweg",
            "path": "wanderweg", "bridleway": "wanderweg",
            "footway": "fussweg", "pedestrian": "fussweg",
            "steps": "stufen",
        }.get(detail)
    return None   # highway (motorway, trunk), rail, ferry, other


def edge_time_s(profile, cls, length_m, gain_m, loss_m, trail_grade=None):
    """Munter-style: distance term + climb term (konzept-routing.md 2.2)."""
    p = PROFILES[profile]
    if cls == "trail":
        return length_m / (TRAIL_DOWN_KMH.get(trail_grade, 10.0) / 3.6)
    f_up, f_down, v_key, rate_key, _ = CLASSES[cls]
    downhill = loss_m > gain_m
    if cls == "stufen":
        v = p["v_push"]
    elif downhill:
        v = p["v_path_up"] if CLASSES[cls][4] else p["v_down"]
        if cls == "wanderweg":
            v = TRAIL_DOWN_KMH[None]
    else:
        v = p[v_key]
    return length_m / (v / 3.6) + gain_m / (p[rate_key] / 3600.0)


def edge_factor(profile, cls, gain_m, loss_m, prefs=None):
    """The class surcharge; the preferences scale what lies above 1 —
    roads in both directions, hiking paths uphill."""
    p = PROFILES[profile]
    f_up, f_down, _, _, hiking = CLASSES[cls]
    downhill = loss_m > gain_m
    f = f_down if downhill else f_up
    f = p[f] if isinstance(f, str) else f
    if cls in ROAD_CLASSES:
        return 1.0 + pref_strength(prefs, "roads") * (f - 1.0)
    if hiking and cls != "stufen" and not downhill:
        return 1.0 + pref_strength(prefs, "hiking") * (f - 1.0)
    return f


def _climb_rate(profile, cls):
    return PROFILES[profile][CLASSES[cls][3]]


def steep_cost_s(profile, cls, steep_w, strength=1.0):
    """The surcharge for `steep_w` weighted steep metres (steep_weight)."""
    return steep_w / (_climb_rate(profile, cls) / 3600.0) * STEEP_FACTOR[cls] * strength


def descent_cost_s(profile, cls, loss_m):
    """DESCENT_COST of the time to climb `loss_m` back up."""
    return DESCENT_COST * loss_m / (_climb_rate(profile, cls) / 3600.0)


def carry_cost_s(cls, gain_m, loss_m, share=1.0):
    """CARRY_S for a steps edge uphill, its `share` after a split."""
    return CARRY_S * share if CLASSES[cls][2] == "v_push" and gain_m > loss_m else 0.0


def edge_cost_s(profile, cls, length_m, gain_m, loss_m, steep_w=0.0, prefs=None, carry=1.0):
    return (edge_time_s(profile, cls, length_m, gain_m, loss_m) * edge_factor(profile, cls, gain_m, loss_m, prefs)
            + steep_cost_s(profile, cls, steep_w, pref_strength(prefs, "steep"))
            + descent_cost_s(profile, cls, loss_m)
            + carry_cost_s(cls, gain_m, loss_m, carry))


def smooth_heights(heights, window=STEEP_SMOOTH):
    """Centred moving average; at the ends over what is there."""
    half = window // 2
    out = []
    for i in range(len(heights)):
        lo, hi = max(0, i - half), min(len(heights), i + half + 1)
        out.append(sum(heights[lo:hi]) / (hi - lo))
    return out


def steep_weight_at(grade):
    """The weight of one metre climbed at `grade` (see STEEP_W_*)."""
    if grade <= STEEP_W_FROM:
        return 0.0
    w = math.exp((grade - STEEP_W_REF) / STEEP_W_SCALE) - math.exp((STEEP_W_FROM - STEEP_W_REF) / STEEP_W_SCALE)
    return min(STEEP_W_MAX, w)


def steep_weight(heights, steps_m, window=STEEP_SMOOTH):
    """(forward, backward): metres climbed, each times steep_weight_at its
    grade — smoothed like steep_excess, heights AND positions."""
    if len(heights) < 2 or len(steps_m) != len(heights) - 1:
        return 0.0, 0.0
    dist = [0.0]
    for d in steps_m:
        dist.append(dist[-1] + d)
    if window > 1:
        sm, sd = smooth_heights(heights, window), smooth_heights(dist, window)
    else:
        sm, sd = list(heights), dist
    up = down = 0.0
    for i in range(len(sm) - 1):
        rise, d = sm[i + 1] - sm[i], sd[i + 1] - sd[i]
        if d <= 0:
            continue
        if rise > 0:
            up += rise * steep_weight_at(rise / d)
        elif rise < 0:
            down += -rise * steep_weight_at(-rise / d)
    return up, down


def steep_excess(heights, steps_m, grade=STEEP_GRADE, window=STEEP_SMOOTH):
    """(forward, backward): metres climbed above `grade` along the samples,
    in sample order and against it. `steps_m[i]` is the distance between
    sample i and i + 1.

    Heights AND positions are averaged over the window: a smoothed point
    sits at the mean distance of its samples. The last step of an edge is
    short (whatever is left after the full 50 m), and smoothing heights
    alone would put a 50 m rise onto a 1 m step there — a linear slope
    must come out exact, whatever the steps."""
    if len(heights) < 2 or len(steps_m) != len(heights) - 1:
        return 0.0, 0.0
    dist = [0.0]
    for d in steps_m:
        dist.append(dist[-1] + d)
    if window > 1:
        sm, sd = smooth_heights(heights, window), smooth_heights(dist, window)
    else:
        sm, sd = list(heights), dist
    up = down = 0.0
    for i in range(len(sm) - 1):
        rise, d = sm[i + 1] - sm[i], sd[i + 1] - sd[i]
        up += max(0.0, rise - grade * d)
        down += max(0.0, -rise - grade * d)
    return up, down


# ------------------------------------------------------------- protobuf / MVT

def _varint(buf, pos):
    result, shift = 0, 0
    while True:
        b = buf[pos]
        pos += 1
        result |= (b & 0x7F) << shift
        if b < 0x80:
            return result, pos
        shift += 7


def _fields(buf):
    """Yields (field number, wire type, value) over a protobuf message."""
    pos, n = 0, len(buf)
    while pos < n:
        key, pos = _varint(buf, pos)
        fno, wt = key >> 3, key & 7
        if wt == 0:
            val, pos = _varint(buf, pos)
        elif wt == 2:
            ln, pos = _varint(buf, pos)
            val = buf[pos:pos + ln]
            pos += ln
        elif wt == 1:
            val = buf[pos:pos + 8]
            pos += 8
        elif wt == 5:
            val = buf[pos:pos + 4]
            pos += 4
        else:
            raise ValueError(f"unsupported wire type {wt}")
        yield fno, wt, val


def _packed(buf):
    out, pos = [], 0
    while pos < len(buf):
        v, pos = _varint(buf, pos)
        out.append(v)
    return out


def _zigzag(v):
    return (v >> 1) ^ -(v & 1)


def _mvt_value(buf):
    for fno, wt, val in _fields(buf):
        if fno == 1:
            return val.decode("utf-8", "replace")
        if fno == 2:
            return struct.unpack("<f", val)[0]
        if fno == 3:
            return struct.unpack("<d", val)[0]
        if fno in (4, 5):
            return val
        if fno == 6:
            return _zigzag(val)
        if fno == 7:
            return bool(val)
    return None


def decode_mvt_lines(tile_bytes, layer_name="roads"):
    """Line features of one layer: [(extent, props, [[(x, y), ...], ...]), ...].

    Coordinates are tile units (0..extent, may run outside: buffer).
    """
    out = []
    for fno, wt, layer in _fields(tile_bytes):
        if fno != 3:
            continue
        name, keys, values, features, extent = None, [], [], [], 4096
        for lf, lw, lv in _fields(layer):
            if lf == 1:
                name = lv.decode("utf-8", "replace")
            elif lf == 2:
                features.append(lv)
            elif lf == 3:
                keys.append(lv.decode("utf-8", "replace"))
            elif lf == 4:
                values.append(_mvt_value(lv))
            elif lf == 5:
                extent = lv
        if name != layer_name:
            continue
        for fbuf in features:
            ftype, tags, geom = None, [], []
            for ff, fw, fv in _fields(fbuf):
                if ff == 2:
                    tags = _packed(fv) if fw == 2 else tags + [fv]
                elif ff == 3:
                    ftype = fv
                elif ff == 4:
                    geom = _packed(fv) if fw == 2 else geom + [fv]
            if ftype != 2:   # LINESTRING
                continue
            props = {keys[k]: values[v] for k, v in zip(tags[::2], tags[1::2])
                     if k < len(keys) and v < len(values)}
            lines, cur, x, y, i = [], [], 0, 0, 0
            while i < len(geom):
                cmd, count = geom[i] & 7, geom[i] >> 3
                i += 1
                if cmd == 1:        # MoveTo
                    if len(cur) >= 2:
                        lines.append(cur)
                    cur = []
                for _ in range(count):
                    if cmd in (1, 2):
                        x += _zigzag(geom[i])
                        y += _zigzag(geom[i + 1])
                        i += 2
                        cur.append((x, y))
            if len(cur) >= 2:
                lines.append(cur)
            if lines:
                out.append((extent, props, lines))
    return out


def _put_varint(out, v):
    while True:
        b = v & 0x7F
        v >>= 7
        if v:
            out.append(b | 0x80)
        else:
            out.append(b)
            return


def _put_field(out, fno, wt, val):
    _put_varint(out, (fno << 3) | wt)
    if wt == 0:
        _put_varint(out, val)
    else:
        _put_varint(out, len(val))
        out.extend(val)


def _zz(v):
    return (v << 1) ^ (v >> 63) if v < 0 else v << 1


def encode_mvt_lines(features, layer_name="roads", extent=4096):
    """The inverse of decode_mvt_lines, for fixtures: [(props, [line, ...])]."""
    keys, values, kidx, vidx = [], [], {}, {}
    feats = []
    for props, lines in features:
        f = bytearray()
        tags = []
        for k, v in props.items():
            if k not in kidx:
                kidx[k] = len(keys)
                keys.append(k)
            if v not in vidx:
                vidx[v] = len(values)
                values.append(v)
            tags += [kidx[k], vidx[v]]
        packed = bytearray()
        for t in tags:
            _put_varint(packed, t)
        _put_field(f, 2, 2, packed)
        _put_field(f, 3, 0, 2)
        geom, x, y = bytearray(), 0, 0
        for line in lines:
            _put_varint(geom, (1 << 3) | 1)
            _put_varint(geom, _zz(line[0][0] - x))
            _put_varint(geom, _zz(line[0][1] - y))
            x, y = line[0]
            _put_varint(geom, (len(line) - 1) << 3 | 2)
            for px, py in line[1:]:
                _put_varint(geom, _zz(px - x))
                _put_varint(geom, _zz(py - y))
                x, y = px, py
        _put_field(f, 4, 2, geom)
        feats.append(f)
    layer = bytearray()
    _put_field(layer, 15, 0, 2)
    _put_field(layer, 1, 2, layer_name.encode())
    for f in feats:
        _put_field(layer, 2, 2, f)
    for k in keys:
        _put_field(layer, 3, 2, k.encode())
    for v in values:
        vb = bytearray()
        _put_field(vb, 1, 2, str(v).encode())
        _put_field(layer, 4, 2, vb)
    _put_field(layer, 5, 0, extent)
    tile = bytearray()
    _put_field(tile, 3, 2, layer)
    return bytes(tile)


# ------------------------------------------------------------- tiles -> lines

def tile_bounds(z, x, y):
    """(west, south, east, north) in degrees."""
    n = 1 << z
    west = x / n * 360 - 180
    east = (x + 1) / n * 360 - 180

    def lat(ty):
        return math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * ty / n))))
    return west, lat(y + 1), east, lat(y)


def tile_to_lonlat(z, x, y, px, py, extent):
    n = 1 << z
    lon = (x + px / extent) / n * 360 - 180
    lat = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * (y + py / extent) / n))))
    return lon, lat


def clip_line(line, extent):
    """Cuts a tile-unit polyline to [0, extent]²; returns the pieces inside.

    Tiles carry a buffer beyond their edge, so a way near a border is in
    BOTH neighbours. Without clipping the graph held it twice; with it,
    both tiles end at the same border point (± quantisation), and the
    dead-end join (JOIN_M) ties them together.
    """
    def inside(p):
        return 0 <= p[0] <= extent and 0 <= p[1] <= extent

    def cross(a, b):
        # Liang–Barsky on the box.
        t0, t1 = 0.0, 1.0
        dx, dy = b[0] - a[0], b[1] - a[1]
        for p, q in ((-dx, a[0]), (dx, extent - a[0]), (-dy, a[1]), (dy, extent - a[1])):
            if p == 0:
                if q < 0:
                    return None
                continue
            r = q / p
            if p < 0:
                if r > t1:
                    return None
                t0 = max(t0, r)
            else:
                if r < t0:
                    return None
                t1 = min(t1, r)
        if t0 > t1:
            return None
        return (a[0] + t0 * dx, a[1] + t0 * dy), (a[0] + t1 * dx, a[1] + t1 * dy)

    pieces, cur = [], []
    for a, b in zip(line, line[1:]):
        seg = cross(a, b)
        if seg is None:
            if len(cur) >= 2:
                pieces.append(cur)
            cur = []
            continue
        p, q = seg
        if not cur or cur[-1] != p:
            if cur and inside(a) and cur[-1] != a:
                cur.append(a)
            if not cur:
                cur = [p]
            elif cur[-1] != p:
                if len(cur) >= 2:
                    pieces.append(cur)
                cur = [p]
        cur.append(q)
    if len(cur) >= 2:
        pieces.append(cur)
    return pieces


def lines_from_tile(tile_bytes, z, x, y):
    """[(cls, oneway, [(lon, lat), ...], level)] for the usable roads of one tile."""
    out = []
    for extent, props, lines in decode_mvt_lines(tile_bytes):
        cls = classify(props.get("kind"), props.get("kind_detail"),
                       props.get("access"), props.get("service"))
        if cls is None:
            continue
        oneway = bool(props.get("oneway")) and cls in ROAD_CLASSES
        # Bridges and tunnels cross other ways without touching them; a
        # geometric crossing is a junction only on the same level.
        level = 1 if props.get("is_bridge") else (-1 if props.get("is_tunnel") else 0)
        for line in lines:
            for piece in clip_line(line, extent):
                pts = [tile_to_lonlat(z, x, y, px, py, extent) for px, py in piece]
                dedup = [pts[0]] + [p for a, p in zip(pts, pts[1:]) if p != a]
                if len(dedup) >= 2:
                    out.append((cls, oneway, dedup, level))
    return out


# ------------------------------------------------------------- DEM (COG)

class CogTile:
    """One Copernicus GLO-90 tile: tiled GeoTIFF, deflate, float predictor.

    Only what the bucket actually serves is supported (checked
    2026-10-01 on N47 E011): one band, float32 or int16, tiled, deflate
    or uncompressed, predictor 1/2/3, pixel-is-point. Anything else raises
    instead of returning numbers that look right.
    """

    def __init__(self, data):
        self.data = data
        e = {b"II": "<", b"MM": ">"}[data[:2]]
        self.e = e
        off = struct.unpack(e + "I", data[4:8])[0]
        n = struct.unpack(e + "H", data[off:off + 2])[0]
        sizes = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 11: 4, 12: 8, 16: 8}
        fmt = {3: "H", 4: "I", 12: "d", 11: "f", 16: "Q"}
        tags = {}
        for i in range(n):
            t, ty, c, v = struct.unpack(e + "HHII", data[off + 2 + 12 * i:off + 14 + 12 * i])
            sz = sizes[ty] * c
            raw = data[off + 10 + 12 * i:off + 10 + 12 * i + sz] if sz <= 4 else data[v:v + sz]
            tags[t] = raw if ty in (1, 2) else struct.unpack(e + fmt[ty] * c, raw)
        self.width, self.height = tags[256][0], tags[257][0]
        self.bits = tags[258][0]
        self.compression = tags.get(259, (1,))[0]
        self.predictor = tags.get(317, (1,))[0]
        self.tw, self.th = tags[322][0], tags[323][0]
        self.offsets, self.counts = tags[324], tags[325]
        self.sample_format = tags.get(339, (1,))[0]
        if tags.get(277, (1,))[0] != 1:
            raise ValueError("DEM tile with more than one band")
        if self.compression not in (1, 8, 32946):
            raise ValueError(f"DEM tile compression {self.compression} unsupported")
        sx, sy = tags[33550][0], tags[33550][1]
        tp = tags[33922]
        self.lon0, self.lat0 = tp[3] - tp[0] * sx, tp[4] + tp[1] * sy
        self.sx, self.sy = sx, sy
        keys = tags.get(34735, ())
        raster_type = 1
        for i in range(4, len(keys), 4):
            if keys[i] == 1025:
                raster_type = keys[i + 3]
        if raster_type == 1:   # pixel is area: shift to centres
            self.lon0 += sx / 2
            self.lat0 -= sy / 2
        nd = tags.get(42113)
        self.nodata = float(nd.split(b"\x00")[0]) if nd else None
        self._tiles = {}
        self.tiles_across = (self.width + self.tw - 1) // self.tw

    def _tile(self, index):
        if index in self._tiles:
            return self._tiles[index]
        raw = self.data[self.offsets[index]:self.offsets[index] + self.counts[index]]
        if self.compression in (8, 32946):
            raw = zlib.decompress(raw)
        bps = self.bits // 8
        fmt = {(3, 32): "f", (2, 16): "h", (1, 16): "H", (2, 32): "i"}[(self.sample_format, self.bits)]
        row_bytes = self.tw * bps
        out = bytearray(len(raw))
        for r in range(self.th):
            row = bytearray(raw[r * row_bytes:(r + 1) * row_bytes])
            if self.predictor == 3:
                for i in range(1, len(row)):
                    row[i] = (row[i] + row[i - 1]) & 0xFF
                v = bytearray(row_bytes)
                for k in range(bps):           # planes are big-endian order
                    v[(bps - 1 - k)::bps] = row[k * self.tw:(k + 1) * self.tw]
                row = v
                vals = list(struct.unpack("<" + fmt * self.tw, bytes(row)))
                out[r * row_bytes:(r + 1) * row_bytes] = struct.pack("<" + fmt * self.tw, *vals)
                continue
            vals = list(struct.unpack(self.e + fmt * self.tw, bytes(row)))
            if self.predictor == 2:
                for i in range(1, len(vals)):
                    vals[i] += vals[i - 1]
            out[r * row_bytes:(r + 1) * row_bytes] = struct.pack("<" + fmt * self.tw, *vals)
        values = struct.unpack("<" + fmt * (self.tw * self.th), bytes(out))
        self._tiles[index] = values
        return values

    def pixel(self, col, row):
        if not (0 <= col < self.width and 0 <= row < self.height):
            return None
        ti = (row // self.th) * self.tiles_across + col // self.tw
        v = self._tile(ti)[(row % self.th) * self.tw + col % self.tw]
        if self.nodata is not None and v == self.nodata:
            return None
        return float(v)

    def at(self, lat, lon):
        """Bilinear sample; None outside or on nodata."""
        fc = (lon - self.lon0) / self.sx
        fr = (self.lat0 - lat) / self.sy
        c0, r0 = int(math.floor(fc)), int(math.floor(fr))
        tc, tr = fc - c0, fr - r0
        vals = [self.pixel(c0, r0), self.pixel(c0 + 1, r0), self.pixel(c0, r0 + 1), self.pixel(c0 + 1, r0 + 1)]
        if any(v is None for v in vals):
            good = [v for v in vals if v is not None]
            return good[0] if good else None
        a = vals[0] * (1 - tc) + vals[1] * tc
        b = vals[2] * (1 - tc) + vals[3] * tc
        return a * (1 - tr) + b * tr


def dem_tile_name(lat, lon):
    la, lo = int(math.floor(lat)), int(math.floor(lon))
    ns = f"N{la:02d}" if la >= 0 else f"S{-la:02d}"
    ew = f"E{lo:03d}" if lo >= 0 else f"W{-lo:03d}"
    return f"Copernicus_DSM_COG_30_{ns}_00_{ew}_00_DEM"


class DemStore:
    """Copernicus GLO-90 tiles, fetched once into a cache directory."""

    def __init__(self, cache_dir, fetch_fn=None):
        self.cache_dir = cache_dir
        self.fetch_fn = fetch_fn or fetch_bytes
        self.tiles = {}
        self.fetched = 0
        os.makedirs(cache_dir, exist_ok=True)

    def _tile(self, lat, lon):
        name = dem_tile_name(lat, lon)
        if name in self.tiles:
            return self.tiles[name]
        path = os.path.join(self.cache_dir, name + ".tif")
        if not os.path.exists(path):
            data = self.fetch_fn(f"{DEM_BUCKET}{name}/{name}.tif")
            with open(path, "wb") as fh:
                fh.write(data)
            self.fetched += 1
        with open(path, "rb") as fh:
            tile = CogTile(fh.read())
        self.tiles[name] = tile
        return tile

    def at(self, lat, lon):
        return self._tile(lat, lon).at(lat, lon)


class FnDem:
    """Synthetic terrain for the self-test."""

    def __init__(self, fn):
        self.fn = fn

    def at(self, lat, lon):
        return self.fn(lat, lon)


class GridSim:
    """Simulates option A of konzept-routing.md 2.6: the PilzBuddy grid.

    Mean height over a 250 m hex cell, quantised to 20 m steps. The hex
    lattice here is laid out in local metres, not in PilzBuddy's warped
    raster — the resolution is what the measurement is about, not the
    exact cell borders.
    """

    def __init__(self, dem, lat0, cell_m=250.0, step_m=20.0):
        self.dem = dem
        self.cell = cell_m
        self.step = step_m
        self.k = math.cos(math.radians(lat0))
        self.cache = {}
        self.w = cell_m * math.sqrt(2 / math.sqrt(3))
        self.r = self.w / math.sqrt(3)

    def _xy(self, lat, lon):
        return math.radians(lon) * R_EARTH * self.k, math.radians(lat) * R_EARTH

    def _latlon(self, x, y):
        return math.degrees(y / R_EARTH), math.degrees(x / (R_EARTH * self.k))

    def _cell(self, x, y):
        hy = int(round((y - self.r) / (1.5 * self.r)))
        best = None
        for cy in (hy - 1, hy, hy + 1):
            odd = 0.5 * (cy & 1)
            hx0 = int(round(x / self.w - 0.5 - odd))
            for cx in (hx0 - 1, hx0, hx0 + 1):
                px = self.w * (cx + 0.5 + odd)
                py = self.r + cy * 1.5 * self.r
                d = (x - px) ** 2 + (y - py) ** 2
                if best is None or d < best[0]:
                    best = (d, cx, cy, px, py)
        return best[1:]

    def at(self, lat, lon):
        x, y = self._xy(lat, lon)
        cx, cy, px, py = self._cell(x, y)
        key = (cx, cy)
        if key not in self.cache:
            vals = []
            for i in range(4):
                for j in range(4):
                    sx = px + (i - 1.5) * self.w / 4
                    sy = py + (j - 1.5) * self.r * 1.5 / 4
                    la, lo = self._latlon(sx, sy)
                    v = self.dem.at(la, lo)
                    if v is not None:
                        vals.append(v)
            mean = statistics.fmean(vals) if vals else None
            self.cache[key] = None if mean is None else round(mean / self.step) * self.step
        return self.cache[key]


def profile_along(dem, latlon, step_m=SAMPLE_M):
    """Heights every `step_m` along a lat/lon polyline and the distances
    between consecutive samples (chords, in the projection of the first
    point). Samples without a height are dropped; `steps` is then None —
    a grade across a gap would be invented."""
    if len(latlon) < 2:
        return [], []
    lat0 = latlon[0][0]
    k = math.cos(math.radians(lat0))
    xy = [(math.radians(lo) * R_EARTH * k, math.radians(la) * R_EARTH) for la, lo in latlon]
    samples = trail_match.resample(xy, step_m)
    heights = []
    complete = True
    for x, y in samples:
        la, lo = math.degrees(y / R_EARTH), math.degrees(x / (R_EARTH * k))
        h = dem.at(la, lo)
        if h is not None:
            heights.append(h)
        else:
            complete = False
    steps = [math.dist(a, b) for a, b in zip(samples, samples[1:])] if complete else None
    return heights, steps


def climb_along(dem, latlon, step_m=SAMPLE_M, hysteresis_m=HYSTERESIS_M):
    """(gain, loss) along a lat/lon polyline, sampled and hysteresis-filtered."""
    if len(latlon) < 2:
        return 0.0, 0.0
    heights, _ = profile_along(dem, latlon, step_m)
    return hysteresis_climb(heights, hysteresis_m)


def hysteresis_climb(heights, threshold):
    """Sums rises and falls, ignoring wiggles smaller than the threshold."""
    if len(heights) < 2:
        return 0.0, 0.0
    gain = loss = 0.0
    ref = heights[0]        # last confirmed turning point
    extreme = ref           # candidate for the next one
    direction = 0           # 0 undecided, 1 climbing, -1 descending
    for h in heights[1:]:
        if direction == 0:
            if h - ref >= threshold:
                direction, extreme = 1, h
            elif ref - h >= threshold:
                direction, extreme = -1, h
        elif direction == 1:
            if h > extreme:
                extreme = h
            elif extreme - h >= threshold:
                gain += extreme - ref
                ref, extreme, direction = extreme, h, -1
        else:
            if h < extreme:
                extreme = h
            elif h - extreme >= threshold:
                loss += ref - extreme
                ref, extreme, direction = extreme, h, 1
    if direction == 1:
        gain += extreme - ref
    elif direction == -1:
        loss += ref - extreme
    return gain, loss


# ------------------------------------------------------------- graph

@dataclass
class Edge:
    a: int
    b: int
    cls: str
    oneway: bool
    length: float
    gain: float = 0.0
    loss: float = 0.0
    latlon: list = field(default_factory=list)   # a -> b
    level: int = 0                               # 1 bridge, -1 tunnel
    steep_up: float = 0.0                        # metres above STEEP_GRADE, a -> b (#194)
    steep_down: float = 0.0                      # the same, b -> a
    steep_w_up: float = 0.0                      # weighted steep metres (steep_weight), a -> b
    steep_w_down: float = 0.0                    # the same, b -> a
    carry: float = 1.0                           # share of CARRY_S after splits (#210)
    heights: list = field(default_factory=list)  # samples a -> b, for the Tirol report
    steps: list = None


GRID_CELL_M = 50.0   # spatial index cell; every query radius here is <= 30 m


class Graph:
    """Undirected graph with per-edge class and climb; metric coordinates.

    Nodes and edge segments sit in a uniform grid (GRID_CELL_M) so that
    the joins and the trail attachments are local queries. The first
    version scanned every edge per dead end — with 20 000 edges and a few
    thousand dead ends that was minutes in CI, not seconds.
    """

    def __init__(self, lat0):
        self.k = math.cos(math.radians(lat0))
        self.nodes = []        # (x, y)
        self.latlon = []
        self.edges = []
        self.adj = []          # node -> [edge index]
        self._key = {}
        self._node_cells = {}  # cell -> [node]
        self._seg_cells = {}   # cell -> [(edge, segment)]

    def xy(self, lat, lon):
        return math.radians(lon) * R_EARTH * self.k, math.radians(lat) * R_EARTH

    @staticmethod
    def _cell(x, y):
        return int(x // GRID_CELL_M), int(y // GRID_CELL_M)

    def node(self, lat, lon):
        key = (round(lon * 1e6), round(lat * 1e6))
        i = self._key.get(key)
        if i is None:
            i = len(self.nodes)
            self._key[key] = i
            x, y = self.xy(lat, lon)
            self.nodes.append((x, y))
            self.latlon.append((lat, lon))
            self.adj.append([])
            self._node_cells.setdefault(self._cell(x, y), []).append(i)
        return i

    def _index_segments(self, ei, first=0):
        pts = [self.xy(*p) for p in self.edges[ei].latlon]
        for i in range(first, len(pts) - 1):
            (ax, ay), (bx, by) = pts[i], pts[i + 1]
            for cx in range(int(min(ax, bx) // GRID_CELL_M), int(max(ax, bx) // GRID_CELL_M) + 1):
                for cy in range(int(min(ay, by) // GRID_CELL_M), int(max(ay, by) // GRID_CELL_M) + 1):
                    self._seg_cells.setdefault((cx, cy), []).append((ei, i))

    def add_edge(self, a, b, cls, oneway, latlon, level=0):
        xy = [self.xy(la, lo) for la, lo in latlon]
        e = Edge(a, b, cls, oneway, trail_match.polyline_length(xy), latlon=latlon, level=level)
        self.edges.append(e)
        ei = len(self.edges) - 1
        self.adj[a].append(ei)
        self.adj[b].append(ei)
        self._index_segments(ei)
        return ei

    def degree(self, n):
        return len(self.adj[n])

    def split_edge(self, ei, t, lat, lon):
        """Splits edge `ei` at polyline position (segment i, t); the first
        part keeps `ei` (its index entries stay valid — segment `seg` is
        only shortened), the rest becomes a new edge."""
        e = self.edges[ei]
        seg, frac = t
        mid = self.node(lat, lon)
        if mid in (e.a, e.b):
            return mid
        first = e.latlon[:seg + 1] + [(lat, lon)]
        second = [(lat, lon)] + e.latlon[seg + 1:]
        old_b = e.b
        self.adj[old_b].remove(ei)
        e.latlon = first
        e.b = mid
        e.length = trail_match.polyline_length([self.xy(*p) for p in first])
        self.adj[mid].append(ei)
        ni = self.add_edge(mid, old_b, e.cls, e.oneway, second, e.level)
        # Heights by length share, as the app does (splitEdge).
        n = self.edges[ni]
        share = n.length / (e.length + n.length) if e.length + n.length > 0 else 0.0
        for attr in ("gain", "loss", "steep_up", "steep_down", "steep_w_up", "steep_w_down", "carry"):
            v = getattr(e, attr)
            setattr(n, attr, v * share)
            setattr(e, attr, v * (1 - share))
        e.heights, e.steps = [], None
        return mid

    def components(self):
        parent = list(range(len(self.nodes)))

        def find(i):
            while parent[i] != i:
                parent[i] = parent[parent[i]]
                i = parent[i]
            return i
        for e in self.edges:
            ra, rb = find(e.a), find(e.b)
            if ra != rb:
                parent[ra] = rb
        comp = {}
        for e in self.edges:
            comp.setdefault(find(e.a), []).append(e)
        return sorted(comp.values(), key=lambda es: -sum(x.length for x in es))

    def nearest_node(self, x, y, radius, exclude=-1):
        cx, cy = self._cell(x, y)
        reach = int(math.ceil(radius / GRID_CELL_M))
        best, best_d = None, radius
        for dx in range(-reach, reach + 1):
            for dy in range(-reach, reach + 1):
                for n in self._node_cells.get((cx + dx, cy + dy), ()):
                    if n == exclude:
                        continue
                    nx, ny = self.nodes[n]
                    d = math.hypot(nx - x, ny - y)
                    if d <= best_d:
                        best, best_d = n, d
        return best

    def nearest(self, lat, lon, radius, exclude_edges=()):
        """(distance, edge index, (segment, t), lat, lon) of the nearest
        edge point within radius, or None."""
        x, y = self.xy(lat, lon)
        cx, cy = self._cell(x, y)
        reach = int(math.ceil(radius / GRID_CELL_M))
        best = None
        seen = set()
        for dx in range(-reach, reach + 1):
            for dy in range(-reach, reach + 1):
                for ei, i in self._seg_cells.get((cx + dx, cy + dy), ()):
                    if (ei, i) in seen or ei in exclude_edges:
                        continue
                    seen.add((ei, i))
                    pts = self.edges[ei].latlon
                    if i + 1 >= len(pts):
                        continue   # stale after a split
                    a, b = self.xy(*pts[i]), self.xy(*pts[i + 1])
                    d, tt = trail_match._point_segment((x, y), a, b)
                    if d <= radius and (best is None or d < best[0]):
                        px, py = a[0] + tt * (b[0] - a[0]), a[1] + tt * (b[1] - a[1])
                        best = (d, ei, (i, tt), math.degrees(py / R_EARTH), math.degrees(px / (R_EARTH * self.k)))
        return best

    def attach(self, lat, lon, radius=ATTACH_M):
        """Node for a trail end: an existing node within radius, else a new
        node on the nearest edge within radius, else None."""
        x, y = self.xy(lat, lon)
        n = self.nearest_node(x, y, radius)
        if n is not None:
            return n
        hit = self.nearest(lat, lon, radius)
        if hit is None:
            return None
        _, ei, t, la, lo = hit
        return self.split_edge(ei, t, la, lo)


def build_graph(lines, lat0, join_m=JOIN_M, split_crossings=False):
    """Graph from [(cls, oneway, [(lon, lat), ...], level)].

    Pass 1 (strict): a node wherever two lines share a vertex, plus line
    ends. Pass 2 (join): every dead end within join_m of another line is
    tied to it — tile borders, and junctions the tile simplification
    pulled apart. Pass 3 (optional): two ways on the same level that
    CROSS without a shared vertex get a node at the crossing — the
    junction the simplification dropped from both. The report counts
    every pass so M1 can say which one it was. Returns (graph, joins,
    crossings).
    """
    counts = {}
    for _, _, pts, _ in lines:
        for lon, lat in pts:
            key = (round(lon * 1e6), round(lat * 1e6))
            counts[key] = counts.get(key, 0) + 1
    g = Graph(lat0)
    for cls, oneway, pts, level in lines:
        cut = [0]
        for i in range(1, len(pts) - 1):
            lon, lat = pts[i]
            if counts[(round(lon * 1e6), round(lat * 1e6))] >= 2:
                cut.append(i)
        cut.append(len(pts) - 1)
        for s, e in zip(cut, cut[1:]):
            piece = [(lat, lon) for lon, lat in pts[s:e + 1]]
            a = g.node(*piece[0])
            b = g.node(*piece[-1])
            if a == b and len(piece) < 3:
                continue
            g.add_edge(a, b, cls, oneway, piece, level)
    joins = 0
    if join_m > 0:
        for n in range(len(g.nodes)):
            if g.degree(n) != 1:
                continue
            lat, lon = g.latlon[n]
            x, y = g.nodes[n]
            target = g.nearest_node(x, y, join_m, exclude=n)
            if target is None:
                # Its own edge is at distance 0 — exclude it, or every
                # T-junction without a vertex is skipped (the first CI
                # run joined 554 ends where 11 000 lay within 2 m).
                hit = g.nearest(lat, lon, join_m, exclude_edges=set(g.adj[n]))
                if hit is None:
                    continue
                _, ei, t, la, lo = hit
                target = g.split_edge(ei, t, la, lo)
            if target != n:
                g.add_edge(n, target, g.edges[g.adj[n][0]].cls, False, [g.latlon[n], g.latlon[target]])
                joins += 1
    crossings = 0
    if split_crossings:
        for lat, lon, ea, eb in find_crossings(g):
            # Split the first edge (attach makes the node), then the other
            # one at the same point — the node key makes them one node.
            mid = g.attach(lat, lon, radius=0.5)
            if mid is None:
                continue
            hit = g.nearest(lat, lon, 0.5, exclude_edges=set(g.adj[mid]))
            if hit is None:
                continue
            _, ei, t, la, lo = hit
            g.split_edge(ei, t, lat, lon)
            crossings += 1
    return g, joins, crossings


def _proper_crossing(a, b, c, d):
    """Intersection point of segments ab and cd when they cross in their
    interiors, else None. Collinear overlaps count as no crossing."""
    r = (b[0] - a[0], b[1] - a[1])
    q = (d[0] - c[0], d[1] - c[1])
    den = r[0] * q[1] - r[1] * q[0]
    if abs(den) < 1e-9:
        return None
    ac = (c[0] - a[0], c[1] - a[1])
    t = (ac[0] * q[1] - ac[1] * q[0]) / den
    u = (ac[0] * r[1] - ac[1] * r[0]) / den
    eps = 1e-3
    if eps < t < 1 - eps and eps < u < 1 - eps:
        return a[0] + t * r[0], a[1] + t * r[1]
    return None


def find_crossings(g):
    """[(lat, lon, edge a, edge b)] for same-level ways that cross without
    a shared node. Walks the segment grid, so it is linear in practice."""
    out = []
    seen = set()
    for cell, segs in g._seg_cells.items():
        for i in range(len(segs)):
            ea, ia = segs[i]
            pa = g.edges[ea].latlon
            if ia + 1 >= len(pa):
                continue
            a, b = g.xy(*pa[ia]), g.xy(*pa[ia + 1])
            for j in range(i + 1, len(segs)):
                eb, ib = segs[j]
                if eb == ea:
                    continue
                pb = g.edges[eb].latlon
                if ib + 1 >= len(pb) or g.edges[ea].level != g.edges[eb].level:
                    continue
                key = (min((ea, ia), (eb, ib)), max((ea, ia), (eb, ib)))
                if key in seen:
                    continue
                seen.add(key)
                hit = _proper_crossing(a, b, g.xy(*pb[ib]), g.xy(*pb[ib + 1]))
                if hit is None:
                    continue
                out.append((math.degrees(hit[1] / R_EARTH), math.degrees(hit[0] / (R_EARTH * g.k)), ea, eb))
    return out


def add_climbs(g, dem):
    for e in g.edges:
        heights, steps = profile_along(dem, e.latlon)
        e.gain, e.loss = hysteresis_climb(heights, HYSTERESIS_M)
        e.heights, e.steps = heights, steps
        e.steep_up, e.steep_down = steep_excess(heights, steps) if steps is not None else (0.0, 0.0)
        e.steep_w_up, e.steep_w_down = steep_weight(heights, steps) if steps is not None else (0.0, 0.0)


def edge_cost(profile, e, forward, steep=True, prefs=None):
    gain, loss = (e.gain, e.loss) if forward else (e.loss, e.gain)
    steep_w = (e.steep_w_up if forward else e.steep_w_down) if steep else 0.0
    return edge_cost_s(profile, e.cls, e.length, gain, loss, steep_w, prefs, e.carry), gain, loss


def dijkstra(g, src, profile, limit=math.inf, target=None, heuristic=None, steep=True, keep=None, prefs=None):
    """Bounded Dijkstra (A* with `heuristic`): cost, climb, prev per node.

    `keep` (a set of edge indices) makes every other edge OFF_KEEP_FACTOR
    times as expensive — the search then follows those edges wherever it
    can (M4: the ride itself on the graph)."""
    dist = {src: 0.0}
    climb = {src: 0.0}
    prev = {}
    heap = [(0.0, src)]
    seen = set()
    while heap:
        f, n = heapq.heappop(heap)
        if n in seen:
            continue
        seen.add(n)
        if n == target:
            break
        for ei in g.adj[n]:
            e = g.edges[ei]
            forward = e.a == n
            if e.oneway and not forward:
                continue
            m = e.b if forward else e.a
            c, gain, _ = edge_cost(profile, e, forward, steep, prefs)
            if keep is not None and ei not in keep:
                c *= OFF_KEEP_FACTOR
            nd = dist[n] + c
            if nd > limit:
                continue
            if nd < dist.get(m, math.inf):
                dist[m] = nd
                climb[m] = climb[n] + gain
                prev[m] = (n, ei)
                h = heuristic(m) if heuristic else 0.0
                heapq.heappush(heap, (nd + h, m))
    return dist, climb, prev


def astar(g, src, dst, profile, steep=True, keep=None, prefs=None):
    tx, ty = g.nodes[dst]
    vmax = PROFILES[profile]["v_down"] / 3.6

    def h(n):
        x, y = g.nodes[n]
        return math.hypot(x - tx, y - ty) / vmax
    dist, climb, prev = dijkstra(g, src, profile, target=dst, heuristic=h, steep=steep, keep=keep, prefs=prefs)
    if dst not in dist:
        return None
    path = []
    n = dst
    while n != src:
        p, ei = prev[n]
        path.append(ei)
        n = p
    path.reverse()
    return dist[dst], climb[dst], path


OFF_KEEP_FACTOR = 1000.0
RIDDEN_CORRIDOR_M = 25.0   # an edge is "ridden" when all its points lie this close to the ride


def ridden_edges(g, track, lat0, corridor=RIDDEN_CORRIDOR_M):
    """Indices of the edges the ride ran along: every point within `corridor`."""
    grid = trail_match.SegmentGrid(trail_match.project(track, lat0), corridor)
    k = math.cos(math.radians(lat0))

    def near(la, lo):
        return not math.isnan(grid.nearest((math.radians(lo) * R_EARTH * k, math.radians(la) * R_EARTH), corridor)[1])
    return {i for i, e in enumerate(g.edges) if all(near(la, lo) for la, lo in e.latlon)}


def path_time_s(g, path, src, profile):
    """Model time along a path (edge_time_s, no cost factors)."""
    n, t = src, 0.0
    for ei in path:
        e = g.edges[ei]
        forward = e.a == n
        gn, ls = (e.gain, e.loss) if forward else (e.loss, e.gain)
        t += edge_time_s(profile, e.cls, e.length, gn, ls)
        n = e.b if forward else e.a
    return t


def path_summary(g, path, src):
    """Length, gain, loss, class mix, hiking km, wasted descent along a path."""
    n = src
    length = gain = loss = hiking = steep = 0.0
    mix = {}
    latlon = []
    for ei in path:
        e = g.edges[ei]
        forward = e.a == n
        pts = e.latlon if forward else e.latlon[::-1]
        latlon.extend(pts if not latlon else pts[1:])
        gn, ls = (e.gain, e.loss) if forward else (e.loss, e.gain)
        length += e.length
        gain += gn
        loss += ls
        steep += e.steep_up if forward else e.steep_down
        mix[e.cls] = mix.get(e.cls, 0.0) + e.length
        if CLASSES[e.cls][4]:
            hiking += e.length
        n = e.b if forward else e.a
    return {"length_m": length, "gain_m": gain, "loss_m": loss, "mix": mix,
            "hiking_m": hiking, "steep_m": steep, "latlon": latlon}


# ------------------------------------------------------------- fetching

def fetch_bytes(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=180) as r:
        return r.read()


def host_archive(source=None):
    """The archive the app reads: dach.json names the dated file."""
    if source:
        return map_tiles.Archive(map_tiles.open_source(source))
    manifest = json.loads(fetch_bytes(f"{PUBLIC_BASE}/dach.json"))
    return map_tiles.Archive(map_tiles.HttpSource(f"{PUBLIC_BASE}/{manifest['file']}"))


def tiles_for_bbox(archive, bbox, z=ROAD_ZOOM):
    """Yields (z, x, y, bytes) for every tile of the archive inside bbox."""
    ids = sorted(map_tiles.bbox_tile_ids(bbox, z, z)[z])
    for tile_id in ids:
        entry = archive.find(tile_id)
        if entry is None:
            continue
        zz, x, y = map_tiles.tile_id_to_zxy(tile_id)
        raw = archive.tile_bytes(entry)
        yield zz, x, y, map_tiles.decompress(raw, archive.header.tile_compression)


def load_lines(archive, bbox):
    lines, tiles = [], 0
    for z, x, y, data in tiles_for_bbox(archive, bbox):
        tiles += 1
        lines.extend(lines_from_tile(data, z, x, y))
    return lines, tiles


# ------------------------------------------------------------- official trails

@dataclass
class OfficialTrail:
    name: str
    parts: list              # [[(lat, lon), ...], ...]
    up_m: float
    down_m: float
    length_m: float

    @property
    def start(self):
        return self.parts[0][0]

    @property
    def end(self):
        return self.parts[-1][-1]


def load_official(region="tirol", fetch_fn=fetch_bytes):
    data = json.loads(fetch_fn(f"{OFFICIAL_BASE}/{region}.geojson"))
    out = []
    for f in data["features"]:
        p = f["properties"]
        geom = f["geometry"]
        coords = geom["coordinates"] if geom["type"] == "MultiLineString" else [geom["coordinates"]]
        parts = [[(la, lo) for lo, la in part] for part in coords if len(part) >= 2]
        if not parts:
            continue
        out.append(OfficialTrail(p.get("name", ""), parts, float(p.get("up_m") or 0),
                                 float(p.get("down_m") or 0), float(p.get("length_m") or 0)))
    return out


def frames_for(trails, size_km, count):
    """Greedy: frames of size_km around the densest clusters of trail starts."""
    rest = list(trails)
    frames = []
    half_lat = size_km / 2 / 111.32
    while rest and len(frames) < count:
        best, best_n = None, -1
        for t in rest:
            la, lo = t.start
            half_lon = half_lat / math.cos(math.radians(la))
            n = sum(1 for o in rest if abs(o.start[0] - la) <= half_lat and abs(o.start[1] - lo) <= half_lon)
            if n > best_n:
                best, best_n = t, n
        la, lo = best.start
        half_lon = half_lat / math.cos(math.radians(la))
        inside = [o for o in rest if abs(o.start[0] - la) <= half_lat and abs(o.start[1] - lo) <= half_lon]
        lats = [o.start[0] for o in inside]
        lons = [o.start[1] for o in inside]
        cla, clo = statistics.fmean(lats), statistics.fmean(lons)
        half_lon = half_lat / math.cos(math.radians(cla))
        bbox = (clo - half_lon, cla - half_lat, clo + half_lon, cla + half_lat)
        members = [o for o in rest if bbox[1] <= o.start[0] <= bbox[3] and bbox[0] <= o.start[1] <= bbox[2]]
        frames.append((bbox, members))
        rest = [o for o in rest if o not in members]
    return frames


# ------------------------------------------------------------- reports

def pct(x):
    return f"{100 * x:.0f} %"


def km(m):
    return f"{m / 1000:.1f} km"


def measure_frame(bbox, trails, archive, dem, profile="bio", budget_h=BUDGET_HOURS):
    """All measurements for one frame; returns a dict for the report."""
    t0 = time.perf_counter()
    lines, tiles = load_lines(archive, bbox)
    t_tiles = time.perf_counter() - t0
    lat0 = (bbox[1] + bbox[3]) / 2

    t0 = time.perf_counter()
    strict, _, _ = build_graph(lines, lat0, join_m=0)
    joined, joins, _ = build_graph(lines, lat0)
    t_graph = time.perf_counter() - t0
    variants = {
        "join5": build_graph(lines, lat0, join_m=5.0),
        "join10": build_graph(lines, lat0, join_m=10.0),
        "cross": build_graph(lines, lat0, split_crossings=True),
        "cross10": build_graph(lines, lat0, join_m=10.0, split_crossings=True),
    }

    def connectivity(g):
        comps = g.components()
        total = sum(e.length for e in g.edges)
        largest = sum(e.length for e in comps[0]) if comps else 0.0
        big_nodes = set()
        if comps:
            for e in comps[0]:
                big_nodes.add(e.a)
                big_nodes.add(e.b)
        attached = attached_big = 0
        ends = 0
        for t in trails:
            for lat, lon in (t.start, t.end):
                ends += 1
                hit = g.nearest(lat, lon, ATTACH_M)
                if hit is None:
                    continue
                attached += 1
                e = g.edges[hit[1]]
                if e.a in big_nodes or e.b in big_nodes:
                    attached_big += 1
        small = [sum(e.length for e in c) for c in comps if sum(e.length for e in c) < 200]
        # Ends off the largest component: a real neighbouring valley (its
        # roads leave the frame before they meet) or a fragment?
        comp_of = {}
        comp_len = []
        for ci, c in enumerate(comps):
            comp_len.append(sum(e.length for e in c))
            for e in c:
                comp_of[e.a] = ci
                comp_of[e.b] = ci
        off = []
        for t in trails:
            for lat, lon in (t.start, t.end):
                hit = g.nearest(lat, lon, ATTACH_M)
                if hit is None:
                    continue
                ci = comp_of.get(g.edges[hit[1]].a)
                if ci not in (None, 0):
                    off.append(comp_len[ci])
        return {"edges": len(g.edges), "nodes": len(g.nodes), "components": len(comps),
                "largest_share": largest / total if total else 0.0,
                "ends": ends, "attached": attached, "attached_largest": attached_big,
                "small": len(small), "small_share": sum(small) / total if total else 0.0,
                "off_lengths": sorted(off)}

    m1 = {"strict": connectivity(strict), "joined": connectivity(joined), "joins": joins}
    for key, (g, j, c) in variants.items():
        m1[key] = connectivity(g)
        m1[key]["joins"] = j
        m1[key]["crossings"] = c
    # Why does it fall apart? Dead ends of the strict graph and how far the
    # nearest OTHER way is: a histogram says whether a bigger join radius
    # would heal it or whether the gaps are real.
    gaps = {"≤ 2 m": 0, "≤ 5 m": 0, "≤ 10 m": 0, "≤ 30 m": 0, "> 30 m": 0}
    dead_ends = 0
    for n in range(len(strict.nodes)):
        if strict.degree(n) != 1:
            continue
        dead_ends += 1
        lat, lon = strict.latlon[n]
        hit = strict.nearest(lat, lon, 30.0, exclude_edges=set(strict.adj[n]))
        d = hit[0] if hit else math.inf
        for label, lim in (("≤ 2 m", 2), ("≤ 5 m", 5), ("≤ 10 m", 10), ("≤ 30 m", 30)):
            if d <= lim:
                gaps[label] += 1
                break
        else:
            gaps["> 30 m"] += 1
    m1["dead_ends"] = dead_ends
    m1["gaps"] = gaps

    t0 = time.perf_counter()
    add_climbs(joined, dem)
    t_dem = time.perf_counter() - t0

    # M3, Tirol half: DEM along the official geometry vs. the source's numbers.
    grid = GridSim(dem, lat0)
    m3 = []
    for t in trails:
        if t.down_m <= 0:
            continue
        pts = [p for part in t.parts for p in part]
        g_dem, l_dem = climb_along(dem, pts)
        g_grid, l_grid = climb_along(grid, pts)
        m3.append({"down_src": t.down_m, "down_dem": l_dem, "down_grid": l_grid,
                   "up_src": t.up_m, "up_dem": g_dem, "up_grid": g_grid})

    # M5: from every trail bottom, how far does the budget reach?
    p = PROFILES[profile]
    limit = budget_h * 3600 * 1.0
    bottoms = []
    for t in trails:
        n = joined.attach(*t.end)
        if n is not None:
            bottoms.append((t, n))
    tops = [(t, joined.attach(*t.start)) for t in trails]
    tops = [(t, n) for t, n in tops if n is not None]
    t0 = time.perf_counter()
    reach = []
    for t, n in bottoms:
        dist, climb, _ = dijkstra(joined, n, profile, limit=limit)
        reached = sum(1 for o, m in tops if o is not t and m in dist and climb[m] <= p["budget_climb"])
        reach.append(reached)
    t_dijkstra = time.perf_counter() - t0

    steep = steep_stats(joined)

    # Examples: three climbs bottom -> nearest other top, with class mix.
    # Each one is also searched WITHOUT the steep surcharge (#194): how
    # often does it change the way, and what does that cost in length?
    examples = []
    steep_pairs = []
    for t, n in bottoms[:40]:
        best = None
        for o, m in tops:
            if o is t:
                continue
            d = math.dist(joined.nodes[n], joined.nodes[m])
            if best is None or d < best[0]:
                best = (d, o, m)
        if best is None:
            continue
        if best[0] < 50:
            continue   # the next trail starts where this one ends — no climb to look at
        res = astar(joined, n, best[2], profile)
        if res is None:
            continue
        cost, climb, path = res
        s = path_summary(joined, path, n)
        s["time_min"] = sum(edge_time_s(profile, joined.edges[ei].cls, joined.edges[ei].length,
                                        *( (joined.edges[ei].gain, joined.edges[ei].loss)
                                           if joined.edges[ei].a == a else (joined.edges[ei].loss, joined.edges[ei].gain)))
                            for ei, a in zip(path, _path_nodes(joined, path, n))) / 60
        s["air_m"] = best[0]
        plain = astar(joined, n, best[2], profile, steep=False)
        if plain is not None:
            ps = path_summary(joined, plain[2], n)
            s["plain"] = {"length_m": ps["length_m"], "gain_m": ps["gain_m"], "steep_m": ps["steep_m"],
                          "mix": ps["mix"]}
            steep_pairs.append({"changed": plain[2] != path, "length_m": s["length_m"], "plain_length_m": ps["length_m"],
                                "steep_m": s["steep_m"], "plain_steep_m": ps["steep_m"]})
        if len(examples) < 5:
            examples.append(s)

    return {"bbox": bbox, "tiles": tiles, "lines": len(lines), "trails": len(trails),
            "m1": m1, "m3": m3, "reach": reach, "examples": examples,
            "steep": steep, "steep_pairs": steep_pairs,
            "timing": {"tiles_s": t_tiles, "graph_s": t_graph, "dem_s": t_dem,
                       "dijkstra_s": t_dijkstra, "dijkstra_runs": len(bottoms)},
            "dem_fetched": getattr(dem, "fetched", 0)}


STEEP_REPORT_CLASSES = ("forstweg", "radweg", "zufahrt", "nebenstrasse", "landstrasse", "wanderweg", "fussweg")


def steep_stats(g):
    """#194: per class, the edges in their uphill direction — length, gain,
    the share of the gain above each of STEEP_GRADES (raw samples and
    smoothed over STEEP_SMOOTH) and the length-weighted grades of the
    smoothed steps. Edges without complete heights are left out."""
    acc = {}
    for e in g.edges:
        if e.cls not in STEEP_REPORT_CLASSES or e.steps is None or len(e.heights) < 2:
            continue
        hs, st = e.heights, e.steps
        if hs[-1] < hs[0]:
            hs, st = hs[::-1], st[::-1]
        gain, _ = hysteresis_climb(hs, HYSTERESIS_M)
        if gain <= 0:
            continue
        a = acc.setdefault(e.cls, {"length_m": 0.0, "gain_m": 0.0, "edges": 0,
                                   "raw": [0.0] * len(STEEP_GRADES), "smooth": [0.0] * len(STEEP_GRADES),
                                   "grades": []})
        a["length_m"] += e.length
        a["gain_m"] += gain
        a["edges"] += 1
        for i, gr in enumerate(STEEP_GRADES):
            a["raw"][i] += steep_excess(hs, st, gr, window=1)[0]
            a["smooth"][i] += steep_excess(hs, st, gr)[0]
        sm = smooth_heights(hs)
        a["grades"] += [((sm[i + 1] - sm[i]) / d, d) for i, d in enumerate(st) if d > 0]
    out = {}
    for cls, a in acc.items():
        gs = sorted(a.pop("grades"))
        total = sum(d for _, d in gs)

        def q(p):
            run = 0.0
            for gr, d in gs:
                run += d
                if run >= p * total:
                    return gr
            return gs[-1][0] if gs else 0.0
        a["p50"], a["p90"], a["p99"] = q(0.5), q(0.9), q(0.99)
        out[cls] = a
    return out


def _path_nodes(g, path, src):
    n = src
    for ei in path:
        yield n
        e = g.edges[ei]
        n = e.b if e.a == n else e.a


def _err_stats(pairs):
    """Relative errors of (measured, reference) pairs: median, p90, share ±10 %."""
    rel = [abs(m - r) / r for m, r in pairs if r > 0]
    if not rel:
        return "—"
    rel.sort()
    p90 = rel[min(len(rel) - 1, int(0.9 * len(rel)))]
    within = sum(1 for x in rel if x <= 0.10) / len(rel)
    return f"Median {pct(statistics.median(rel))}, 90. Perzentil {pct(p90)}, innerhalb ±10 %: {pct(within)} (n = {len(rel)})"


def render_report(frames, profile, source_name, note=""):
    out = [f"# Routing-Messung (#35): Tirol, {time.strftime('%Y-%m-%d')}", ""]
    out.append(f"*`tool/route_measure.py tirol`, Profil `{profile}`, Kacheln aus `{source_name}`, "
               f"Höhen Copernicus GLO-90. Schwellen aus `docs/konzept-routing.md` Abschnitt 6.*")
    if note:
        out.append("")
        out.append(note)
    for i, fr in enumerate(frames, 1):
        b = fr["bbox"]
        out += ["", f"## Rahmen {i} — {fr['trails']} offizielle Trails, {fr['tiles']} Kacheln, {fr['lines']} Wegstücke",
                "", f"Rahmen {b[0]:.2f}–{b[2]:.2f}° O, {b[1]:.2f}–{b[3]:.2f}° N (der Rahmen ist eine Gegend, kein Trail)."]
        m1 = fr["m1"]
        out += ["", "### M1 — Zusammenhang", "",
                "| Graph | Kanten | Knoten | Komponenten | größte (Länge) | Trail-Enden ≤ 30 m | davon an der größten |",
                "|---|---|---|---|---|---|---|"]
        for label, key in (("nur geteilte Knoten", "strict"), ("+ Enden verbunden (≤ 2 m)", "joined"),
                           ("+ Enden verbunden (≤ 5 m)", "join5"), ("+ Enden verbunden (≤ 10 m)", "join10"),
                           ("≤ 2 m + Kreuzungen geteilt", "cross"), ("≤ 10 m + Kreuzungen geteilt", "cross10")):
            c = m1[key]
            out.append(f"| {label} | {c['edges']} | {c['nodes']} | {c['components']} | {pct(c['largest_share'])} "
                       f"| {c['attached']} / {c['ends']} ({pct(c['attached'] / c['ends']) if c['ends'] else '—'}) "
                       f"| {c['attached_largest']} / {c['ends']} ({pct(c['attached_largest'] / c['ends']) if c['ends'] else '—'}) |")
        out.append(f"\nVerbundene Enden bei 2 m: {m1['joins']}; Kreuzungen ohne gemeinsamen Knoten (gleiche Ebene, "
                   f"keine Brücke/Tunnel): {m1['cross']['crossings']}. Schwelle: ≥ 90 % der Trail-Enden an der "
                   f"größten Komponente, größte Komponente ≥ 95 % der Kantenlänge.")
        g = m1["gaps"]
        out.append(f"\nTote Enden im strengen Graphen: {m1['dead_ends']}; Abstand zum nächsten anderen Weg: "
                   + ", ".join(f"{k} {v}" for k, v in g.items()) + ".")
        c = m1["cross10"]
        out.append(f"Kleinstteile (< 200 m) nach ≤ 10 m + Kreuzungen: {c['small']} Komponenten, "
                   f"{pct(c['small_share'])} der Kantenlänge.")
        if c["off_lengths"]:
            out.append("Trail-Enden abseits der größten Komponente (≤ 10 m + Kreuzungen): Länge ihrer Komponente "
                       + ", ".join(km(l) for l in c["off_lengths"]) + " — ab einigen km ist das ein Nachbartal, "
                       "dessen Straßen den Rahmen verlassen, kein Bruchstück.")
        m3 = fr["m3"]
        out += ["", "### M3 — Höhen (Tirol-Hälfte)", ""]
        if m3:
            out.append("Abstieg entlang der offiziellen Linie, DEM gegen die Zahl der Quelle "
                       "(die ist selbst gerechnet, keine Bodenwahrheit — die eigene Hälfte liefert der lokale Lauf):")
            out.append("")
            out.append(f"- DEM direkt (90 m, 50-m-Abtastung, 10 m Hysterese): {_err_stats([(x['down_dem'], x['down_src']) for x in m3])}")
            out.append(f"- Gitter A simuliert (250-m-Waben, 20-m-Stufen): {_err_stats([(x['down_grid'], x['down_src']) for x in m3])}")
            ups = [(x["up_dem"], x["up_src"]) for x in m3 if x["up_src"] >= 50]
            if ups:
                out.append(f"- Anstieg DEM direkt, wo die Quelle ≥ 50 hm nennt: {_err_stats(ups)}")
            out.append("\nSchwelle: Aufstiegssumme ±10 % (Median). Fällt das Gitter durch und das DEM nicht, ist Weg B dran.")
        else:
            out.append("Keine Trails mit Abstiegsangabe im Rahmen.")
        out += ["", "### M5 — Laufzeit", ""]
        t = fr["timing"]
        out.append(f"- Kacheln lesen: {t['tiles_s']:.1f} s ({fr['tiles']} Kacheln, Range-Anfragen an den Host)")
        out.append(f"- Graph bauen (zweimal, streng und verbunden): {t['graph_s']:.2f} s")
        out.append(f"- Höhen je Kante: {t['dem_s']:.1f} s ({fr['dem_fetched']} DEM-Kacheln geholt)")
        out.append(f"- Dijkstra von {t['dijkstra_runs']} Trail-Enden mit Budget {BUDGET_HOURS:.0f} h: {t['dijkstra_s']:.2f} s")
        if fr["reach"]:
            out.append(f"- Erreichbare Trail-Anfänge je Ende (Zeit- und Höhenbudget): Median {statistics.median(fr['reach']):.0f}, "
                       f"Maximum {max(fr['reach'])}, kein einziger bei {sum(1 for r in fr['reach'] if r == 0)} Enden")
        out.append("\nSchwelle: < 2 s auf dem Rechner (Graph + Dijkstra), < 5 s auf dem Telefon (nach Schritt 3).")
        if fr["examples"]:
            out += ["", "### Beispiel-Aufstiege (Ende eines Trails → nächster Anfang eines anderen)", "",
                    "| Luftlinie | Weg | bergauf | bergab | Wanderweg | Zeit | Klassenmix |", "|---|---|---|---|---|---|---|"]
            for s in fr["examples"]:
                mix = ", ".join(f"{c} {km(l)}" for c, l in sorted(s["mix"].items(), key=lambda kv: -kv[1]))
                out.append(f"| {km(s['air_m'])} | {km(s['length_m'])} | {s['gain_m']:.0f} hm | {s['loss_m']:.0f} hm "
                           f"| {km(s['hiking_m'])} | {s['time_min']:.0f} min | {mix} |")
            out.append("\nZum Ansehen, nicht zum Messen: Sieht der Weg aus wie einer, den man fahren würde?")
        out += render_steep(fr)
    return "\n".join(out) + "\n"


def render_steep(fr):
    """#194: how steep the classes are on the DEM, and what the surcharge does."""
    out = ["", "### #194 — Steile Anstiege", "",
           f"Kanten in ihrer Aufwärtsrichtung, Höhen alle {SAMPLE_M:.0f} m. Spalten: Anteil der Höhenmeter über der "
           f"Steilgrenze, roh und über {STEEP_SMOOTH} Proben geglättet (g = geglättet); Steigung der geglätteten "
           "Schritte nach Länge gewichtet.", "",
           "| Klasse | Kanten | km | hm | " + " | ".join(f"> {gr * 100:.0f} % roh / g" for gr in STEEP_GRADES)
           + " | Median | 90. | 99. |",
           "|---|---|---|---|" + "---|" * len(STEEP_GRADES) + "---|---|---|"]
    for cls in STEEP_REPORT_CLASSES:
        a = fr["steep"].get(cls)
        if not a:
            continue
        cells = " | ".join(f"{pct(r / a['gain_m'])} / {pct(m / a['gain_m'])}" for r, m in zip(a["raw"], a["smooth"]))
        out.append(f"| {cls} | {a['edges']} | {a['length_m'] / 1000:.0f} | {a['gain_m']:.0f} | {cells} "
                   f"| {pct(a['p50'])} | {pct(a['p90'])} | {pct(a['p99'])} |")
    pairs = fr["steep_pairs"]
    if pairs:
        changed = [x for x in pairs if x["changed"]]
        out.append("")
        out.append(f"Aufschlag ab {STEEP_GRADE * 100:.0f} % (Faktor unbefestigt "
                   f"{STEEP_FACTOR['forstweg']:g}, Straße {STEEP_FACTOR['nebenstrasse']:g}): "
                   f"{len(changed)} von {len(pairs)} Aufstiegen nehmen einen anderen Weg; steile hm "
                   f"{sum(x['plain_steep_m'] for x in pairs):.0f} → {sum(x['steep_m'] for x in pairs):.0f}.")
        if changed:
            longer = sorted(x["length_m"] / x["plain_length_m"] - 1 for x in changed if x["plain_length_m"] > 0)
            out.append(f"Wo sich der Weg ändert, wird er im Median {pct(statistics.median(longer))} länger, "
                       f"höchstens {pct(longer[-1])}.")
    if fr["examples"]:
        out += ["", "| Beispiel | ohne Aufschlag | mit Aufschlag |", "|---|---|---|"]
        for i, s in enumerate(fr["examples"], 1):
            p = s.get("plain")
            if not p:
                continue
            out.append(f"| {i} | {km(p['length_m'])}, {p['gain_m']:.0f} hm, {p['steep_m']:.0f} steil "
                       f"| {km(s['length_m'])}, {s['gain_m']:.0f} hm, {s['steep_m']:.0f} steil |")
    return out


# ------------------------------------------------------------- rides mode

def ride_sections(track, min_gain=100.0, drop_end=15.0, window=7):
    """Ascent sections of a ride from smoothed recorded heights: list of
    (start index, end index, gain)."""
    ele = [e if e is not None else 0.0 for e in track.ele]
    if len(ele) < window:
        return []
    half = window // 2
    sm = [statistics.median(ele[max(0, i - half):i + half + 1]) for i in range(len(ele))]
    sections, i = [], 0
    while i < len(sm) - 1:
        if sm[i + 1] <= sm[i]:
            i += 1
            continue
        start, top, top_i = i, sm[i], i
        j = i + 1
        while j < len(sm):
            if sm[j] > top:
                top, top_i = sm[j], j
            elif top - sm[j] >= drop_end:
                break
            j += 1
        gain = top - sm[start]
        if gain >= min_gain:
            sections.append((start, top_i, gain))
        i = max(top_i, j) if j > i else i + 1
    return sections


def class_mix_along(g, track, lat0, corridor=15.0):
    """Length of a track per nearest road class (or 'abseits')."""
    xy = trail_match.project(track, lat0)
    samples = trail_match.resample(xy, 5.0)
    mix = {}
    for x, y in samples:
        la, lo = math.degrees(y / R_EARTH), math.degrees(x / (R_EARTH * math.cos(math.radians(lat0))))
        hit = g.nearest(la, lo, corridor)
        cls = g.edges[hit[1]].cls if hit else "abseits"
        mix[cls] = mix.get(cls, 0.0) + 5.0
    return mix


def measure_rides(trail_tracks, ride_tracks, archive, dem, profile):
    """M2, M4 and the calibration — counts only."""
    report = ["# Routing-Messung (#35): eigene Fahrten", "",
              f"*`tool/route_measure.py rides`, Profil `{profile}`, {len(ride_tracks)} Fahrten, "
              f"{len(trail_tracks)} Trails der Sammlung. Kennzahlen, keine Orte.*", ""]
    mix_total, rates = {}, {}
    m4 = {"tried": 0, "found": 0, "same": 0, "shorter": 0, "longer": 0, "no_graph": 0}
    m4_ratio, m4_gaps, m4_longer = [], 0, []
    mix_ridden, mix_planned = {}, {}
    sections_n = 0
    for ride in ride_tracks:
        if ride.n < 10:
            continue
        lat0 = statistics.fmean(ride.lat)
        margin = 0.02
        bbox = (min(ride.lon) - margin, min(ride.lat) - margin, max(ride.lon) + margin, max(ride.lat) + margin)
        lines, tiles = load_lines(archive, bbox)
        if not lines:
            m4["no_graph"] += 1
            continue
        g, _, _ = build_graph(lines, lat0, split_crossings=True)
        add_climbs(g, dem)
        # M2 + calibration on the ascent sections
        for s, e, gain in ride_sections(ride):
            sections_n += 1
            sub = trail_match.Track("s", "", ride.lat[s:e + 1], ride.lon[s:e + 1], ride.ele[s:e + 1], ride.time[s:e + 1])
            mix = class_mix_along(g, sub, lat0)
            for c, l in mix.items():
                mix_total[c] = mix_total.get(c, 0.0) + l
            t0, t1 = ride.time[s], ride.time[e]
            if t0 and t1 and (t1 - t0).total_seconds() > 300:
                dominant = max(mix.items(), key=lambda kv: kv[1])[0]
                rates.setdefault(dominant, []).append(gain / ((t1 - t0).total_seconds() / 3600))
        # M4: ride start -> head of the first known trail
        known = []
        for t in trail_tracks:
            pr = trail_match.compare(t, ride, 15.0)
            if pr is None:
                continue
            cov_t, cov_r = pr.coverage(15.0)
            if cov_t >= 0.8:
                known.append((t, pr))
        if not known:
            continue
        # the trail whose start the ride reaches first (by arc along the ride)
        ride_xy = trail_match.project(ride, lat0)
        grid_r = trail_match.SegmentGrid(ride_xy, 15.0)

        def arc_of(latlon):
            k = math.cos(math.radians(lat0))
            p = (math.radians(latlon[1]) * R_EARTH * k, math.radians(latlon[0]) * R_EARTH)
            return grid_r.nearest(p, 15.0)[1]
        firsts = sorted(((arc_of((t.lat[0], t.lon[0])), t) for t, _ in known), key=lambda x: (math.isnan(x[0]), x[0]))
        arc, trail = firsts[0]
        if math.isnan(arc) or arc < 300:
            continue
        m4["tried"] += 1
        src = g.attach(ride.lat[0], ride.lon[0])
        dst = g.attach(trail.lat[0], trail.lon[0])
        if src is None or dst is None:
            continue
        res = astar(g, src, dst, profile)
        if res is None:
            continue
        m4["found"] += 1
        cost, climb, path = res
        s = path_summary(g, path, src)
        # the ride's own climb: its points up to the arrival at the trail head
        cum, idx = 0.0, 0
        for i, (a, b) in enumerate(zip(ride_xy, ride_xy[1:])):
            cum += math.hypot(b[0] - a[0], b[1] - a[1])
            if cum >= arc:
                idx = i + 1
                break
        ridden = trail_match.Track("r", "", ride.lat[:idx + 1], ride.lon[:idx + 1], ride.ele[:idx + 1], ride.time[:idx + 1])
        planned = trail_match.Track("p", "", [p[0] for p in s["latlon"]], [p[1] for p in s["latlon"]],
                                    [None] * len(s["latlon"]), [None] * len(s["latlon"]))
        trail_match._derive(ridden)
        trail_match._derive(planned)
        # The ride is not the optimum either: put it on the graph (the
        # cheapest way along its own edges) and compare model times.
        keep = ridden_edges(g, ridden, lat0)
        own = astar(g, src, dst, profile, keep=keep)
        if own is not None:
            t_plan = path_time_s(g, path, src, profile)
            if t_plan > 0:
                m4_ratio.append(path_time_s(g, own[2], src, profile) / t_plan)
            if sum(g.edges[i].length for i in own[2] if i not in keep) > 1.0:
                m4_gaps += 1
            own_len = sum(g.edges[i].length for i in own[2])
            if own_len > 0:
                m4_longer.append(s["length_m"] / own_len)
        for c, l in class_mix_along(g, ridden, lat0).items():
            mix_ridden[c] = mix_ridden.get(c, 0.0) + l
        for c, l in class_mix_along(g, planned, lat0).items():
            mix_planned[c] = mix_planned.get(c, 0.0) + l
        pr = trail_match.compare(ridden, planned, 15.0)
        if pr is not None:
            a, b = pr.coverage(15.0)
            if a >= 0.8 and b >= 0.8:
                m4["same"] += 1
                continue
        if s["length_m"] < 0.9 * ridden.length_m:
            m4["shorter"] += 1
        else:
            m4["longer"] += 1
    report += ["## M2 — Klassenmix der eigenen Aufstiege", "",
               f"{sections_n} Aufstiegsabschnitte (≥ 100 hm am Stück) in {len(ride_tracks)} Fahrten:", ""]
    total = sum(mix_total.values()) or 1.0
    for c, l in sorted(mix_total.items(), key=lambda kv: -kv[1]):
        report.append(f"- {c}: {km(l)} ({pct(l / total)})")
    report += ["", "## Kalibrierung — Steigrate je dominanter Klasse", ""]
    for c, rs in sorted(rates.items()):
        report.append(f"- {c}: Median {statistics.median(rs):.0f} hm/h aus {len(rs)} Abschnitten")
    report += ["", "## M4 — Aufstiegstreue (Fahrtstart → erster bekannter Trailkopf)", "",
               f"- geprüft: {m4['tried']}, Weg gefunden: {m4['found']}, gleich (15 m, 0,8 beidseitig): {m4['same']}, "
               f"Planer kürzer: {m4['shorter']}, Planer länger: {m4['longer']}, Fahrten ohne Kacheln: {m4['no_graph']}",
               "", "Schwelle: ≥ 70 % gleich, Rest erklärbar."]
    if m4_ratio:
        report += ["", "### Die Fahrt auf dem Graphen (Modellzeit gefahren / geplant)", "",
                   f"- Median {statistics.median(m4_ratio):.2f}, kleinster {min(m4_ratio):.2f}, größter {max(m4_ratio):.2f}; "
                   f"≤ 1,10: {sum(r <= 1.10 for r in m4_ratio)}, ≤ 1,20: {sum(r <= 1.20 for r in m4_ratio)} "
                   f"von {len(m4_ratio)}",
                   f"- Planer länger als die Fahrt auf dem Graphen: höchstens {pct(max(m4_longer) - 1) if m4_longer and max(m4_longer) > 1 else '0 %'}",
                   f"- Fahrten mit Stücken außerhalb des Graphen ({RIDDEN_CORRIDOR_M:.0f} m): {m4_gaps}", "",
                   "Klassenmix gefahren / geplant:", ""]
        tr, tp = sum(mix_ridden.values()) or 1.0, sum(mix_planned.values()) or 1.0
        for c in sorted(set(mix_ridden) | set(mix_planned), key=lambda c: -mix_ridden.get(c, 0.0)):
            report.append(f"- {c}: {pct(mix_ridden.get(c, 0.0) / tr)} / {pct(mix_planned.get(c, 0.0) / tp)}")
    return "\n".join(report) + "\n"


def load_gpx_dir(path):
    if os.path.isdir(path):
        tracks = []
        for name in sorted(os.listdir(path)):
            if name.lower().endswith(".gpx"):
                with open(os.path.join(path, name), "rb") as fh:
                    tr = trail_match.parse_gpx(fh.read(), name, name)
                if tr:
                    tracks.append(tr)
        return tracks
    return trail_match.load_tracks(path)


# ------------------------------------------------------------- self-test

def _synthetic_tiles():
    """Two neighbouring z13 tiles with a small road net, in tile units.

    Tile A (x, y) and tile B (x+1, y). A track runs across the border; a
    primary road crosses a track WITHOUT a shared vertex (the
    simplification case); a private road and a motorway must be dropped;
    a path (hiking) offers a shortcut.
    """
    z, x, y = 13, 4372, 2869   # somewhere in Tirol
    ext = 4096
    tile_a = [
        ({"kind": "path", "kind_detail": "track"}, [[(100, 2000), (2000, 2000), (4096 + 200, 2000)]]),   # into the buffer
        ({"kind": "major_road", "kind_detail": "primary"}, [[(2000, 100), (2000, 3900)]]),            # crosses, no vertex
        ({"kind": "path", "kind_detail": "track"}, [[(2000, 2000), (2000, 3000), (3000, 3000)]]),    # shares (2000,2000)
        ({"kind": "path", "kind_detail": "path"}, [[(100, 2000), (100, 500), (2000, 100)]]),         # hiking shortcut
        ({"kind": "minor_road", "kind_detail": "service", "access": "private"}, [[(100, 2000), (100, 3000)]]),
        ({"kind": "highway", "kind_detail": "motorway"}, [[(0, 3500), (4096, 3500)]]),
        # crosses the primary at (2000, 3200) without a shared vertex
        ({"kind": "path", "kind_detail": "track"}, [[(500, 3200), (3500, 3200)]]),
        # a bridge over the primary: crosses geometrically, must NOT join
        ({"kind": "path", "kind_detail": "track", "is_bridge": True}, [[(1500, 3300), (2500, 3300)]]),
        # a T-junction the simplification lost: ends 1 unit (~1.2 m) off the
        # interior of the track (2000,3000)-(3000,3000), no node nearby
        ({"kind": "path", "kind_detail": "track"}, [[(2600, 2500), (2600, 2999)]]),
    ]
    tile_b = [
        # Slightly sloped: the two border points differ by ~1 m, as real
        # neighbours do after quantisation — strict pass apart, join ties.
        ({"kind": "path", "kind_detail": "track"}, [[(-200, 2001), (1500, 2000), (3000, 1000)]]),
    ]
    return z, x, y, encode_mvt_lines(tile_a, extent=ext), encode_mvt_lines(tile_b, extent=ext)


def _synthetic_cog(width=8, height=8, tw=4, th=4, values=None, predictor=3):
    """A tiny tiled float32 GeoTIFF with the Copernicus layout."""
    import array as _array
    vals = values or [float(r * 10 + c) for r in range(height) for c in range(width)]
    tiles = []
    for ty in range(0, height, th):
        for tx in range(0, width, tw):
            raw = bytearray()
            for r in range(th):
                row = [vals[(ty + r) * width + tx + c] if ty + r < height and tx + c < width else 0.0 for c in range(tw)]
                packed = struct.pack("<" + "f" * tw, *row)
                if predictor == 3:
                    planes = bytearray(len(packed))
                    for k in range(4):
                        planes[k * tw:(k + 1) * tw] = packed[(3 - k)::4]
                    diff = bytearray(planes)
                    for i in range(len(diff) - 1, 0, -1):
                        diff[i] = (planes[i] - planes[i - 1]) & 0xFF
                    raw += diff
                else:
                    raw += packed
            tiles.append(zlib.compress(bytes(raw)))
    entries = []

    def tag(t, ty, vals_):
        entries.append((t, ty, vals_))
    tag(256, 3, [width]); tag(257, 3, [height]); tag(258, 3, [32]); tag(259, 3, [8])
    tag(262, 3, [1]); tag(277, 3, [1]); tag(317, 3, [predictor]); tag(322, 3, [tw]); tag(323, 3, [th])
    tag(324, 4, [0] * len(tiles)); tag(325, 4, [len(t) for t in tiles]); tag(339, 3, [3])
    tag(33550, 12, [1 / 1200, 1 / 1200, 0.0]); tag(33922, 12, [0.0, 0.0, 0.0, 11.0, 48.0, 0.0])
    tag(34735, 3, [1, 1, 0, 2, 1024, 0, 1, 2, 1025, 0, 1, 2])
    # layout: header(8) + IFD + extra data + tiles
    sizes = {3: 2, 4: 4, 12: 8}
    fmt = {3: "H", 4: "I", 12: "d"}
    ifd_len = 2 + 12 * len(entries) + 4
    extra = bytearray()
    extra_off = 8 + ifd_len
    tile_off = extra_off + sum(sizes[ty] * len(v) for _, ty, v in entries if sizes[ty] * len(v) > 4)
    offs, cur = [], tile_off
    for t in tiles:
        offs.append(cur)
        cur += len(t)
    ifd = bytearray(struct.pack("<H", len(entries)))
    for t, ty, v in sorted(entries):
        if t == 324:
            v = offs
        packed = struct.pack("<" + fmt[ty] * len(v), *v)
        if len(packed) <= 4:
            ifd += struct.pack("<HHI", t, ty, len(v)) + packed.ljust(4, b"\x00")
        else:
            ifd += struct.pack("<HHII", t, ty, len(v), extra_off + len(extra))
            extra += packed
    ifd += struct.pack("<I", 0)
    return b"II*\x00" + struct.pack("<I", 8) + bytes(ifd) + bytes(extra) + b"".join(tiles)


def self_test():
    def expect(cond, msg):
        if not cond:
            raise SystemExit(f"self-test failed: {msg}")

    # classes
    expect(classify("path", "track") == "forstweg", "track is the baseline")
    expect(classify("path", "path") == "wanderweg", "path is hiking")
    expect(classify("major_road", "primary_link") == "bundesstrasse", "primary links count as primary")
    expect(classify("minor_road", "service", service="driveway") is None, "driveways are out")
    expect(classify("highway", "motorway") is None, "motorways are out")
    expect(classify("path", "track", access="private") is None, "private is out")
    expect(classify("rail", None) is None, "rails are out")

    # time model and costs
    bio_track = edge_cost_s("bio", "forstweg", 1000, 100, 0)
    expect(abs(bio_track - (1000 / (15 / 3.6) + 100 / (450 / 3600))) < 1e-6, "track cost = time")
    expect(edge_cost_s("bio", "wanderweg", 1000, 100, 0) > bio_track * 1.4, "hiking climbs cost more")
    expect(edge_cost_s("ebike", "wanderweg", 1000, 100, 0) / edge_time_s("ebike", "wanderweg", 1000, 100, 0) == 2.0, "e-bike surcharge")
    expect(edge_cost_s("ebike", "forstweg", 1000, 100, 0) < bio_track, "e-bike climbs faster")
    expect(edge_cost_s("bio", "bundesstrasse", 1000, 0, 0) == 4.0 * edge_time_s("bio", "bundesstrasse", 1000, 0, 0), "primary ×4")
    expect(edge_factor("bio", "wanderweg", 0, 50) == 2.0 and edge_factor("ebike", "wanderweg", 0, 50) == 2.5, "hiking downhill factors")
    expect(abs(edge_time_s("bio", "trail", 1800, 0, 300, trail_grade=2) - 1800 / (9 / 3.6)) < 1e-6, "trail time by grade")

    # steep climbs (#194) — the vectors are mirrored in route_profile_test.dart
    ramp = [100.0 + 15.0 * i for i in range(9)]          # 30 % every 50 m
    expect(steep_excess(ramp, [50.0] * 8, window=1) == (60.0, 0.0), "raw: 7.5 m above 15 % per step")
    up, down = steep_excess(ramp, [50.0] * 8)
    expect(abs(up - 52.5) < 1e-9 and down == 0.0, f"smoothed: the ends lose half a step: {up}")
    short_end = [100.0 + 7.27 * i for i in range(67)] + [100.0 + 7.27 * 66 + 0.163]
    expect(steep_excess(short_end, [50.0] * 66 + [1.12]) == (0.0, 0.0), "a short last step stays at its grade")
    expect(steep_excess([100.0 + 5.0 * i for i in range(9)], [50.0] * 8) == (0.0, 0.0), "10 % is not steep")
    expect(steep_excess(ramp[::-1], [50.0] * 8)[1] == up, "backwards it is the other direction")
    expect(steep_excess([100.0, 130.0], [50.0]) == (0.0, 0.0), "two samples smooth to one value")
    expect(steep_excess([100.0, 110.0, 100.0], [50.0, 50.0], window=1) == (2.5, 2.5), "both directions")
    expect(smooth_heights([0.0, 30.0, 0.0, 30.0]) == [15.0, 10.0, 20.0, 15.0], "moving average")
    expect(abs(steep_cost_s("bio", "forstweg", 10.0) - 10 * 8 * 3.0) < 1e-9, "unpaved: 3× the climb time")
    expect(abs(steep_cost_s("ebike", "nebenstrasse", 10.0) - 10 * 3600 / 850) < 1e-9, "paved: 1× (e-bike rate)")
    expect(steep_cost_s("bio", "stufen", 10.0) == 0.0, "steps are pushed anyway")
    expect(abs(edge_cost_s("bio", "forstweg", 1000, 100, 0, 10) - (bio_track_plain := edge_cost_s("bio", "forstweg", 1000, 100, 0)) - 240) < 1e-9,
           "the surcharge adds to the cost")
    expect(edge_time_s("bio", "forstweg", 1000, 100, 0) == bio_track_plain, "and not to the time")

    # a steep shortcut loses against a gentler detour, without the surcharge it wins
    g3 = Graph(47.0)
    s0, s1, s2 = g3.node(47.0, 11.0), g3.node(47.005, 11.0), g3.node(47.0025, 11.004)
    short = g3.add_edge(s0, s1, "forstweg", False, [(47.0, 11.0), (47.005, 11.0)])
    g3.edges[short].gain, g3.edges[short].steep_up, g3.edges[short].steep_w_up = 140.0, 60.0, 60.0
    for a_, b_ in ((s0, s2), (s2, s1)):
        ei = g3.add_edge(a_, b_, "forstweg", False, [g3.latlon[a_], g3.latlon[b_]])
        g3.edges[ei].gain = 70.0
    expect(astar(g3, s0, s1, "bio")[2] != [short], "the steep shortcut is avoided")
    expect(astar(g3, s0, s1, "bio", steep=False)[2] == [short], "without the surcharge it is taken")
    expect(astar(g3, s1, s0, "bio")[2] == [short], "downhill the steep edge costs nothing extra")
    mid3 = g3.split_edge(short, (0, 0.5), 47.0025, 11.0)
    halves = [e for e in g3.edges if e.cls == "forstweg" and mid3 in (e.a, e.b) and e.a != s2 and e.b != s2]
    expect(len(halves) == 2 and abs(sum(e.steep_up for e in halves) - 60.0) < 1e-9
           and abs(halves[0].steep_up - halves[1].steep_up) < 0.5, "a split shares the steep metres by length")
    expect(abs(sum(e.steep_w_up for e in halves) - 60.0) < 1e-9, "and the weighted ones")

    # weighted steep metres (#188) — mirrored in route_profile_test.dart
    expect(steep_weight_at(0.10) == 0.0 and steep_weight_at(0.05) == 0.0, "nothing up to 10 %")
    expect(abs(steep_weight_at(0.15) - 0.14316) < 1e-4 and abs(steep_weight_at(0.20) - 0.57277) < 1e-4
           and abs(steep_weight_at(0.25) - 1.86197) < 1e-4 and abs(steep_weight_at(0.30) - 5.73068) < 1e-4,
           f"the weights: {[round(steep_weight_at(g), 5) for g in (0.15, 0.20, 0.25, 0.30)]}")
    expect(steep_weight_at(0.5) == STEEP_W_MAX, "capped")
    expect(abs(steep_weight_at(0.20) / steep_weight_at(0.15) - 4.0) < 0.1, "five points more, about ×3–4")
    wu, wd = steep_weight(ramp, [50.0] * 8, window=1)
    expect(abs(wu - 120.0 * steep_weight_at(0.30)) < 1e-9 and wd == 0.0, "raw: every metre of a 30 % ramp")
    expect(steep_weight([100.0 + 5.0 * i for i in range(9)], [50.0] * 8) == (0.0, 0.0), "10 % weighs nothing")
    expect(steep_weight(ramp[::-1], [50.0] * 8)[1] == steep_weight(ramp, [50.0] * 8)[0], "backwards is the other way")
    se_up = steep_weight(short_end, [50.0] * 66 + [1.12])[0]
    se_rise = short_end[-1] - short_end[0]
    expect(abs(se_up / (se_rise * steep_weight_at(7.27 / 50)) - 1) < 0.01, f"a short last step keeps its grade: {se_up}")

    # descent and preferences (#188)
    expect(abs(edge_cost_s("bio", "forstweg", 1000, 0, 100) - edge_time_s("bio", "forstweg", 1000, 0, 100)
               - 0.3 * 100 * 8) < 1e-9, "a metre down costs 0.3 of climbing it")
    expect(abs(edge_factor("bio", "hauptstrasse", 0, 0, {"roads": False}) - 1.525) < 1e-12, "roads, don't mind: 35 % of 2.5")
    expect(edge_factor("bio", "radweg", 0, 0, {"roads": False}) == 1.0, "a cycleway is no road")
    expect(abs(edge_factor("ebike", "wanderweg", 10, 0, {"hiking": False}) - 1.35) < 1e-12, "hiking up, don't mind")
    expect(edge_factor("ebike", "wanderweg", 0, 10, {"hiking": False}) == 2.5, "downhill stays")
    expect(edge_factor("bio", "stufen", 10, 0, {"hiking": False}) == 3.0, "steps stay")
    expect(abs(steep_cost_s("bio", "forstweg", 10.0, pref_strength({"steep": False}, "steep")) - 10 * 8 * 3.0 * 0.3) < 1e-9,
           "steep, don't mind: 30 %")
    expect(edge_factor("bio", "hauptstrasse", 0, 0, {"roads": True}) == edge_factor("bio", "hauptstrasse", 0, 0) == 2.5,
           "avoid is the default")

    # steps uphill are carried (#210) — mirrored in route_profile_test.dart
    expect(carry_cost_s("stufen", 4, 0) == CARRY_S == 60.0, "a flight up costs the carry")
    expect(carry_cost_s("stufen", 0, 4) == 0.0 and carry_cost_s("stufen", 0, 0) == 0.0, "down or without heights: none")
    expect(carry_cost_s("forstweg", 4, 0) == 0.0 and carry_cost_s("fussweg", 4, 0) == 0.0, "only steps")
    expect(abs(edge_cost_s("bio", "stufen", 20, 4, 0) - 276.0) < 1e-9, "20 m with 4 hm: 216 s plus the carry")
    expect(abs(edge_cost_s("bio", "stufen", 20, 4, 0, carry=0.25) - 231.0) < 1e-9, "a split part carries its share")
    expect(edge_cost_s("bio", "stufen", 20, 4, 0, prefs={"hiking": False}) == edge_cost_s("bio", "stufen", 20, 4, 0),
           "not cheapened by \"hiking: don't mind\"")
    g5 = Graph(47.0)
    c0, c1, c2 = g5.node(47.0, 11.0), g5.node(47.00018, 11.0), g5.node(47.00009, 11.0 + 0.005933)
    flight = g5.add_edge(c0, c1, "stufen", False, [(47.0, 11.0), (47.00018, 11.0)])
    g5.edges[flight].gain = 4.0
    for a_, b_ in ((c0, c2), (c2, c1)):
        ei = g5.add_edge(a_, b_, "forstweg", False, [g5.latlon[a_], g5.latlon[b_]])
        g5.edges[ei].gain = 2.0
    expect(astar(g5, c0, c1, "bio")[2] != [flight], "a short flight up loses against 900 m of track")
    saved_carry = CARRY_S
    globals()["CARRY_S"] = 0.0
    expect(astar(g5, c0, c1, "bio")[2] == [flight], "without the carry the flight is taken")
    globals()["CARRY_S"] = saved_carry
    mid5 = g5.split_edge(flight, (0, 0.5), 47.00009, 11.0)
    parts = [e for e in g5.edges if e.cls == "stufen"]
    expect(len(parts) == 2 and abs(sum(e.carry for e in parts) - 1.0) < 1e-9, "a split shares the carry by length")
    expect(mid5 not in (c0, c1) and all(g5.edges[ei].cls == "forstweg" for ei in astar(g5, c0, c1, "bio")[2]),
           "and the flight is still avoided")

    # hysteresis
    expect(hysteresis_climb([100, 105, 100, 105, 100, 150, 140, 200], 10) == (110.0, 10.0), "wiggles under 10 m vanish")
    expect(hysteresis_climb([200, 100], 10) == (0.0, 100.0), "pure descent")
    expect(hysteresis_climb([100, 200, 100], 10) == (100.0, 100.0), "up and down")

    # MVT round trip
    z, x, y, ta, tb = _synthetic_tiles()
    decoded = decode_mvt_lines(ta)
    expect(len(decoded) == 9, f"9 features decoded, got {len(decoded)}")
    expect(decoded[0][2][0] == [(100, 2000), (2000, 2000), (4296, 2000)], "geometry round trip")
    expect(decoded[1][1]["kind_detail"] == "primary", "properties round trip")
    expect(decode_mvt_lines(b"\x00\x01\x02" * 3) == [] or True, "garbage does not crash (or raises)")

    # clipping: the buffered track ends on the tile edge
    pieces = clip_line([(100, 2000), (2000, 2000), (4296, 2000)], 4096)
    expect(pieces == [[(100, 2000), (2000, 2000), (4096.0, 2000.0)]], f"clip to the edge: {pieces}")
    expect(clip_line([(-50, 10), (-10, 10)], 4096) == [], "wholly outside is dropped")

    # lines from tiles: dropped classes
    la = lines_from_tile(ta, z, x, y)
    lb = lines_from_tile(tb, z, x + 1, y)
    expect(sorted(c for c, *_ in la) == ["bundesstrasse", "forstweg", "forstweg", "forstweg", "forstweg", "forstweg", "wanderweg"],
           f"classes in A: {[c for c, *_ in la]}")
    expect([lv for c, o, p, lv in la].count(1) == 1, "the bridge carries its level")
    expect(len(lb) == 1, "one track in B")

    # graph: strict vs joined
    lat0 = tile_bounds(z, x, y)[1]
    strict, _, _ = build_graph(la + lb, lat0, join_m=0)
    joined, joins, _ = build_graph(la + lb, lat0)
    comps_s = strict.components()
    comps_j = joined.components()
    expect(len(comps_s) >= 4, f"strict graph is split at the border, the crossings and the T: {len(comps_s)}")
    expect(len(comps_j) == 3, f"joined graph: net (with the T-track), crossing track, bridge — got {len(comps_j)}")
    expect(joins >= 2, f"the border AND the T-junction were joined, got {joins}")
    crossed, _, ncross = build_graph(la + lb, lat0, split_crossings=True)
    expect(ncross == 1, f"exactly the one same-level crossing is split, got {ncross}")
    expect(len(crossed.components()) == 2, f"crossing joins the track, the bridge stays apart: {len(crossed.components())}")
    expect(_proper_crossing((0, 0), (10, 0), (5, -1), (5, 1)) == (5.0, 0.0), "proper crossing")
    expect(_proper_crossing((0, 0), (10, 0), (10, -1), (10, 1)) is None, "touching at an end is not a crossing")
    expect(_proper_crossing((0, 0), (10, 0), (2, 0), (8, 0)) is None, "collinear overlap is not a crossing")
    # the crossing without a shared vertex stays unjoined (no dead end there) —
    # that is exactly what M1 must show, not hide.
    crossing = joined.nearest(*tile_to_lonlat(z, x, y, 2000, 2000, 4096)[::-1], 1.0)
    expect(crossing is not None, "crossing point lies on an edge")

    # climbs on synthetic terrain: height rises to the east
    west = tile_bounds(z, x, y)[0]
    dem = FnDem(lambda lat, lon: 500 + (lon - west) * 111000 * math.cos(math.radians(lat)) * 0.1)  # 10 % slope
    add_climbs(joined, dem)
    track = [e for e in joined.edges if e.cls == "forstweg" and e.length > 1000][0]
    expect(abs(track.gain - track.length * 0.1 * (1 if track.latlon[-1][1] > track.latlon[0][1] else 0)) < track.length * 0.02
           or abs(track.loss - track.length * 0.1) < track.length * 0.02, f"10 % slope measured: {track.gain}/{track.loss}/{track.length}")

    # Dijkstra: the track beats the hiking shortcut at ×1.4 only when shorter enough
    a = joined.attach(*tile_to_lonlat(z, x, y, 100, 2000, 4096)[::-1])
    b = joined.attach(*tile_to_lonlat(z, x, y, 2000, 100, 4096)[::-1])
    expect(a is not None and b is not None, "attach finds nodes")
    res = astar(joined, a, b, "bio")
    expect(res is not None, "a route exists")
    cost, climb, path = res
    s = path_summary(joined, path, a)
    expect(set(s["mix"]) <= {"forstweg", "bundesstrasse", "wanderweg"}, f"only usable classes: {s['mix']}")
    dist, _, _ = dijkstra(joined, a, "bio", limit=cost - 1)
    expect(b not in dist, "the budget bound holds")
    dist_full, _, _ = dijkstra(joined, a, "bio")
    expect(abs(dist_full[b] - cost) < 1e-6, "A* equals Dijkstra")

    # oneway: a one-way road is passable forward only
    g1 = Graph(47.0)
    n0, n1 = g1.node(47.0, 11.0), g1.node(47.0, 11.01)
    g1.add_edge(n0, n1, "nebenstrasse", True, [(47.0, 11.0), (47.0, 11.01)])
    expect(n1 in dijkstra(g1, n0, "bio")[0] and n0 not in dijkstra(g1, n1, "bio")[0], "oneway respected")

    # attach splits an edge when no node is near
    g2 = Graph(47.0)
    p, q = g2.node(47.0, 11.0), g2.node(47.0, 11.02)
    g2.add_edge(p, q, "forstweg", False, [(47.0, 11.0), (47.0, 11.02)])
    mid = g2.attach(47.0001, 11.01)
    expect(mid not in (p, q) and len(g2.edges) == 2, "attach splits the edge")
    expect(g2.attach(47.01, 11.01) is None, "nothing within 30 m")

    # COG reader round trip, with and without the float predictor
    for pred in (3, 1):
        cog = CogTile(_synthetic_cog(predictor=pred))
        expect(cog.pixel(3, 2) == 23.0, f"pixel read (predictor {pred})")
        expect(cog.pixel(7, 7) == 77.0 and cog.pixel(8, 0) is None, "edges")
        expect(abs(cog.at(48.0 - 2 / 1200, 11.0 + 3 / 1200) - 23.0) < 1e-9, "pixel-is-point sampling")
        expect(abs(cog.at(48.0 - 2.5 / 1200, 11.0 + 3.5 / 1200) - 28.5) < 1e-9, "bilinear")
    expect(dem_tile_name(47.3, 11.9) == "Copernicus_DSM_COG_30_N47_00_E011_00_DEM", "tile name")
    expect(dem_tile_name(-1.5, -0.5) == "Copernicus_DSM_COG_30_S02_00_W001_00_DEM", "southern/western names")

    # grid simulation quantises
    grid = GridSim(dem, lat0)
    v = grid.at(lat0, west + 0.01)
    expect(v is not None and v % 20 == 0, "grid values are 20 m steps")

    # frames and official loading
    trails = [OfficialTrail(f"t{i}", [[(47.0 + i * 0.001, 11.0), (47.0 + i * 0.001, 11.01)]], 10, 300, 1000) for i in range(5)]
    trails.append(OfficialTrail("far", [[(47.5, 12.5), (47.5, 12.51)]], 0, 200, 800))
    fr = frames_for(trails, 20, 2)
    expect(len(fr) == 2 and len(fr[0][1]) == 5 and len(fr[1][1]) == 1, "frames cluster the trails")
    geo = json.dumps({"features": [{"properties": {"name": "x", "up_m": 1, "down_m": 2, "length_m": 3},
                                    "geometry": {"type": "MultiLineString", "coordinates": [[[11.0, 47.0], [11.01, 47.0]]]}}]}).encode()
    off = load_official("t", fetch_fn=lambda url: geo)
    expect(off[0].start == (47.0, 11.0) and off[0].end == (47.0, 11.01), "official geometry")

    # ride sections
    tr = trail_match.Track("r", "", [47.0] * 40, [11.0 + i * 0.001 for i in range(40)],
                           [500 + i * 10 for i in range(20)] + [700 - i * 10 for i in range(20)], [None] * 40)
    secs = ride_sections(tr)
    expect(len(secs) == 1 and secs[0][2] >= 150, f"one ascent section: {secs}")

    # a frame end to end on the synthetic data, without network
    class _Archive:
        header = type("H", (), {"tile_compression": map_tiles.COMPRESSION_NONE})()

        def find(self, tile_id):
            zz, xx, yy = map_tiles.tile_id_to_zxy(tile_id)
            return (xx, yy) if (zz, xx, yy) in {(z, x, y), (z, x + 1, y)} else None

        def tile_bytes(self, entry):
            return ta if entry == (x, y) else tb
    w, s_, e_, n_ = tile_bounds(z, x, y)
    bbox = (w, s_, tile_bounds(z, x + 1, y)[2], n_)
    ot = [OfficialTrail("a", [[tile_to_lonlat(z, x, y, 2000, 3000, 4096)[::-1], tile_to_lonlat(z, x, y, 3000, 3000, 4096)[::-1]]], 0, 50, 300),
          OfficialTrail("b", [[tile_to_lonlat(z, x + 1, y, 3000, 1000, 4096)[::-1], tile_to_lonlat(z, x + 1, y, 1500, 2000, 4096)[::-1]]], 0, 80, 500)]
    fr = measure_frame(bbox, ot, _Archive(), dem)
    expect(fr["tiles"] == 2 and fr["m1"]["joined"]["attached"] == 4, f"frame measured: {fr['m1']}")
    expect(fr["m1"]["cross"]["crossings"] == 1 and fr["m1"]["dead_ends"] > 0, "diagnostics present")
    text = render_report([fr], "bio", "synthetic")
    expect("M1" in text and "M5" in text and "Beispiel" in text, "report renders")

    # rides mode end to end on the same synthetic net: a ride along the
    # track, a "trail" on the branch it reaches, timestamps for the rates.
    from datetime import datetime, timedelta, timezone

    def track(points_tile, name, with_time=True, climb=True):
        lat, lon, ele, tim = [], [], [], []
        t0 = datetime(2026, 9, 1, 9, 0, tzinfo=timezone.utc)
        for i, (px, py) in enumerate(points_tile):
            lo, la = tile_to_lonlat(z, x, y, px, py, 4096)
            lat.append(la)
            lon.append(lo)
            ele.append(600 + i * 12 if climb else 800 - i * 12)
            tim.append(t0 + timedelta(seconds=i * 60) if with_time else None)
        tr = trail_match.Track(name, name, lat, lon, ele, tim)
        trail_match._derive(tr)
        return tr
    ride_pts = [(100 + i * 95, 2000) for i in range(21)] + [(2000, 2000 + i * 100) for i in range(1, 11)] + \
               [(2000 + i * 100, 3000) for i in range(1, 11)]
    ride = track(ride_pts, "ride")
    trail = track([(2000, 3000 + 0), (2200, 3000), (2400, 3000), (2600, 3000), (2800, 3000), (3000, 3000)], "trail",
                  with_time=False, climb=False)
    rides_text = measure_rides([trail], [ride], _Archive(), dem, "bio")
    expect("M2" in rides_text and "M4" in rides_text and "Kalibrierung" in rides_text, "rides report renders")
    expect("geprüft: 1" in rides_text and "Weg gefunden: 1" in rides_text, f"the climb is tried: {rides_text}")
    expect("forstweg" in rides_text, "class mix names the track")
    expect("Modellzeit gefahren / geplant" in rides_text and "Median 1.00" in rides_text,
           f"the ride on the graph is the planned way here: {rides_text}")
    print("ok")


# ------------------------------------------------------------- main

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("mode", nargs="?", choices=["tirol", "rides"])
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--out", default="build/route", help="report and DEM cache directory")
    ap.add_argument("--source", help="PMTiles archive (path or URL); default: the host via dach.json")
    ap.add_argument("--frames", type=int, default=3, help="tirol: how many 20 km frames")
    ap.add_argument("--frame-km", type=float, default=20.0)
    ap.add_argument("--profile", choices=sorted(PROFILES), default="bio")
    ap.add_argument("--trails", help="rides: GPX collection (zip or directory)")
    ap.add_argument("--rides", help="rides: directory of exported ride GPX files")
    ap.add_argument("--summary", help="append the report to this file (GITHUB_STEP_SUMMARY)")
    args = ap.parse_args(argv)
    if args.self_test:
        self_test()
        return 0
    if not args.mode:
        ap.error("mode required: tirol | rides (or --self-test)")
    os.makedirs(args.out, exist_ok=True)
    dem = DemStore(os.path.join(args.out, "dem"))
    archive = host_archive(args.source)
    if args.mode == "tirol":
        trails = load_official("tirol")
        frames = frames_for(trails, args.frame_km, args.frames)
        results = []
        for bbox, members in frames:
            print(f"frame {bbox}: {len(members)} trails", file=sys.stderr)
            results.append(measure_frame(bbox, members, archive, dem, args.profile))
        text = render_report(results, args.profile, archive.source.name)
        with open(os.path.join(args.out, "tirol.json"), "w") as fh:
            json.dump([{k: v for k, v in r.items() if k != "examples"} | {"examples": [
                {k2: v2 for k2, v2 in ex.items() if k2 != "latlon"} for ex in r["examples"]]} for r in results], fh, indent=1)
    else:
        if not args.trails or not args.rides:
            ap.error("rides mode needs --trails and --rides")
        text = measure_rides(load_gpx_dir(args.trails), load_gpx_dir(args.rides), archive, dem, args.profile)
    path = os.path.join(args.out, f"{args.mode}.md")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    if args.summary:
        with open(args.summary, "a", encoding="utf-8") as fh:
            fh.write(text)
    print(text)
    archive.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
