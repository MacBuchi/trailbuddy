#!/usr/bin/env python3
"""Height tiles for the stored areas (docs/konzept-routing.md 2.6, way B).

ONE PMTiles archive on our own host, `heights-<build>.pmtiles`, holding
for every z13 tile of the map's area a small grid of heights sampled
from the Copernicus DEM GLO-90 (open, no account; the same source the
routing measurement used, docs/routing-messung.md M3). The app fetches
the tiles of a stored area through the same Range-request reader as the
basemap and keeps them in a second archive next to the area
(lib/features/offline_areas/height_tiles.dart is the reader). A manifest
`heights.json` names the current file, like `dach.json` does for the map.

Why a grid per tile and not PilzBuddy's hex grid: measured. Along the
official trails of Tirol the hex grid (250 m cells, 20 m steps) missed
the source's descent figures by 42 % (median), the DEM read directly by
5 % — the steps make stairs along a line, and the hysteresis cannot
undo them. So: one height per sample point, in whole metres.

The tile format (`FORMAT` 1), mirrored byte for byte in Dart:
  - GRID x GRID = 49 x 49 samples per z13 tile, row-major, row 0 north,
    at tile fractions i/48 — INCLUDING both edges, so neighbouring tiles
    share their border row and a bilinear read is seamless across tiles
    (~70 m between samples at 47° N; the DEM has 90 m).
  - int16 metres, little-endian, delta-coded in reading order (the first
    value absolute, every next one the difference to its predecessor,
    wrapping), then gzip — that is the tile compression the archive
    header states, so the app's reader decompresses it like any other.
    Delta plus gzip measured against plain gzip in the self-test.
  - NODATA (-32768) marks a sample without a height (no DEM there); a
    tile with nothing but NODATA is left out of the archive.

Sampling: bilinear in the DEM cell the point lies in (`floor` of
lat/lon names the 1° cell, like the bucket does), and in the last pixel
strip of a cell the last pixel is held instead of reaching into the
neighbour — one DEM pixel of smear on every 1° border, documented, and
the same rule in the plain and in the numpy path. Heights are rounded
half up to whole metres.

Two implementations of the sampling, by design: plain Python for the
self-test (stdlib only, like every tool here, so CI's "Tool self-tests"
step needs nothing installed) and numpy for `build` — 98 640 tiles times
2 401 samples are 237 million bilinear reads, and the float predictor of
the COG tiles alone would take hours in a byte loop. The self-test
proves the two paths equal whenever numpy is importable, and
height-data.yml runs the self-test WITH numpy before building.

Usage:
  python3 tool/height_tiles.py plan  --bbox W,S,E,N [--sample-cells 2] [--dem-cache DIR]
  python3 tool/height_tiles.py build --bbox W,S,E,N --build 20261001 --out build/heights \\
      [--dem-cache DIR] [--summary summary.md]
  python3 tool/height_tiles.py check --source <file or https URL> [--samples 24] [--all] \\
      [--dem-cache DIR] [--summary summary.md]
  python3 tool/height_tiles.py --self-test
"""
import argparse
import gzip
import hashlib
import json
import math
import os
import random
import struct
import sys
import time
import urllib.error
import urllib.request
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import map_tiles  # noqa: E402
import route_measure as rm  # noqa: E402  (CogTile, dem_tile_name, DEM_BUCKET)

try:
    import numpy as np
except ImportError:  # the self-test and `check` run without it
    np = None

FORMAT = 1
GRID = 49
ZOOM = 13
NODATA = -32768
PUBLIC_BASE = "https://tiles.mcbuchi.de/trailbuddy"
SOURCE_NAME = "Copernicus DEM GLO-90"
ATTRIBUTION = ("Copernicus DEM GLO-90: © DLR e.V. 2010-2014 and © Airbus Defence and Space "
               "GmbH 2014-2018, provided under COPERNICUS by the European Union and ESA; "
               "all rights reserved")
USER_AGENT = "TrailBuddy height-tiles (github.com/MacBuchi/trailbuddy)"


# ------------------------------------------------------------- geometry

def tile_lon(xf, z):
    return xf / (1 << z) * 360.0 - 180.0


def tile_lat(yf, z):
    n = math.pi - 2.0 * math.pi * yf / (1 << z)
    return math.degrees(math.atan(math.sinh(n)))


def sample_lons(x, z):
    return [tile_lon(x + i / (GRID - 1), z) for i in range(GRID)]


def sample_lats(y, z):
    return [tile_lat(y + j / (GRID - 1), z) for j in range(GRID)]


def sample_points(z, x, y):
    """(lat, lon) of every sample, row-major, row 0 north, col 0 west."""
    lons, lats = sample_lons(x, z), sample_lats(y, z)
    return [(lat, lon) for lat in lats for lon in lons]


# ------------------------------------------------------------- tile bytes

def encode_tile(values):
    """GRID*GRID ints -> gzip(delta int16 LE)."""
    if len(values) != GRID * GRID:
        raise ValueError(f"{len(values)} values, expected {GRID * GRID}")
    out = bytearray()
    prev = 0
    for v in values:
        if not (-32768 <= v <= 32767):
            raise ValueError(f"height {v} outside int16")
        out += struct.pack("<H", (v - prev) & 0xFFFF)
        prev = v
    return gzip.compress(bytes(out), compresslevel=9, mtime=0)


def decode_tile(data):
    """The inverse; raises on anything that is not exactly one tile."""
    raw = gzip.decompress(data)
    if len(raw) != GRID * GRID * 2:
        raise ValueError(f"tile decodes to {len(raw)} bytes, expected {GRID * GRID * 2}")
    values = []
    prev = 0
    for (d,) in struct.iter_unpack("<h", raw):
        prev = ((prev + d + 32768) & 0xFFFF) - 32768
        values.append(prev)
    return values


def fnv1a(data):
    """FNV-1a, 32 bit — the checksum the Dart test compares against."""
    h = 0x811C9DC5
    for b in data:
        h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF
    return h


def fixture_grid():
    """The deterministic grid both sides encode: Dart asserts the same
    delta bytes and FNV over them (test/offline_areas/height_tiles_test.dart)."""
    values = []
    for j in range(GRID):
        for i in range(GRID):
            values.append(1000 + 7 * i - 3 * j + (i * j) % 5)
    values[20 * GRID + 10] = NODATA
    values[0] = -120
    values[GRID * GRID - 1] = 4810
    return values


# ------------------------------------------------------------- DEM cells

class Cell:
    """One 1° DEM cell as the sampler sees it: a pixel reader plus, when
    numpy is there, the whole raster as a float64 array (NaN = nodata)."""

    def __init__(self, width, height, lon0, lat0, sx, sy, pixel, array=None):
        self.width, self.height = width, height
        self.lon0, self.lat0, self.sx, self.sy = lon0, lat0, sx, sy
        self._pixel = pixel
        self.array = array

    def pixel(self, c, r):
        return self._pixel(c, r)

    @classmethod
    def from_cog(cls, cog):
        array = cog_to_array(cog) if np is not None else None
        return cls(cog.width, cog.height, cog.lon0, cog.lat0, cog.sx, cog.sy, cog.pixel, array)


def cog_to_array(cog):
    """The whole COG as float64 (NaN for nodata), decoded with numpy —
    the fast twin of rm.CogTile._tile, proven equal in the self-test."""
    bps = cog.bits // 8
    kind = {(3, 32): "<f4", (2, 16): "<i2", (1, 16): "<u2", (2, 32): "<i4"}[(cog.sample_format, cog.bits)]
    out = np.full((cog.height, cog.width), np.nan, dtype=np.float64)
    for index in range(len(cog.offsets)):
        raw = cog.data[cog.offsets[index]:cog.offsets[index] + cog.counts[index]]
        if cog.compression in (8, 32946):
            raw = zlib.decompress(raw)
        rows = np.frombuffer(raw, dtype=np.uint8).reshape(cog.th, cog.tw * bps)
        if cog.predictor == 3:
            rows = np.cumsum(rows, axis=1, dtype=np.uint8)
            planes = rows.reshape(cog.th, bps, cog.tw)
            le = np.ascontiguousarray(planes[:, ::-1, :].transpose(0, 2, 1))
            vals = le.view(kind).reshape(cog.th, cog.tw)
        else:
            vals = rows.view(("<" if cog.e == "<" else ">") + kind[1:]).reshape(cog.th, cog.tw)
            if cog.predictor == 2:
                vals = np.cumsum(vals, axis=1, dtype=vals.dtype)
        r0 = (index // cog.tiles_across) * cog.th
        c0 = (index % cog.tiles_across) * cog.tw
        h = min(cog.th, cog.height - r0)
        w = min(cog.tw, cog.width - c0)
        out[r0:r0 + h, c0:c0 + w] = vals[:h, :w].astype(np.float64)
    if cog.nodata is not None:
        out[out == cog.nodata] = np.nan
    return out


def fetch_cog(name, cache_dir, fetch=None, listed=None, wait=time.sleep):
    """COG bytes from the cache or the bucket; None when the bucket has no
    such cell (sea). A `.missing` marker remembers the 404 for re-runs.

    A 404 alone is not proof of sea. Measuring Canada (2026-10-08) the
    bucket answered 404 for cells it lists — N53 W108 in Saskatchewan,
    206 on the next try — and the marker turned a flicker into a
    permanent hole in the heights, counted as "sea" in the summary. So a
    404 is checked against the bucket's listing: not listed is sea; listed
    is retried with backoff, and a cell that stays unreadable fails the
    run instead of being left out."""
    os.makedirs(cache_dir, exist_ok=True)
    path = os.path.join(cache_dir, name + ".tif")
    missing = path + ".missing"
    if os.path.exists(path):
        with open(path, "rb") as fh:
            return fh.read()
    if os.path.exists(missing):
        return None
    url = f"{rm.DEM_BUCKET}{name}/{name}.tif"
    if listed is None:
        # An injected fetch is a fixture: its 404 is sea by construction.
        listed = _listed if fetch is None else (lambda _name: False)
    data = None
    for attempt in range(5):
        try:
            data = (fetch or _fetch)(url)
            break
        except urllib.error.HTTPError as e:
            if e.code not in (403, 404):
                raise
            if attempt == 0 and not listed(name):
                with open(missing, "w") as fh:
                    fh.write(url)
                return None
            if attempt == 4:
                raise RuntimeError(f"{name}: listed in the DEM bucket, but {e.code} on "
                                   "every read — not leaving a hole in the heights")
            wait(2 ** (attempt + 1))
    with open(path + ".part", "wb") as fh:
        fh.write(data)
    os.replace(path + ".part", path)
    return data


def _listed(name):
    """Whether the bucket lists the cell's COG — the answer to "sea or a
    flicker" (see fetch_cog). Retried itself: a listing that does not
    come back is no evidence of sea either."""
    url = f"{rm.DEM_BUCKET}?list-type=2&max-keys=1&prefix={name}/{name}.tif"
    for attempt in range(4):
        try:
            body = _fetch(url).decode("utf-8", "replace")
            return f"<Key>{name}/{name}.tif</Key>" in body
        except (urllib.error.URLError, OSError):
            if attempt == 3:
                raise
            time.sleep(2 ** (attempt + 1))
    return False


def _fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=300) as r:
        return r.read()


class DemCells:
    """Cells by (floor(lat), floor(lon)), decoded once, a few kept (LRU):
    a z13 tile touches at most four cells, and `build` walks cell by cell."""

    def __init__(self, cache_dir, fetch=None, keep=24, listed=None):
        self.cache_dir, self.fetch, self.keep, self.listed = cache_dir, fetch, keep, listed
        self.cells = {}
        self.order = []
        self.fetched = 0
        self.missing = set()

    def __call__(self, la, lo):
        key = (la, lo)
        if key in self.missing:
            return None
        if key in self.cells:
            self.order.remove(key)
            self.order.append(key)
            return self.cells[key]
        name = rm.dem_tile_name(la + 0.5, lo + 0.5)
        data = fetch_cog(name, self.cache_dir, self.fetch, self.listed)
        if data is None:
            self.missing.add(key)
            return None
        self.fetched += 1
        cell = Cell.from_cog(rm.CogTile(data))
        self.cells[key] = cell
        self.order.append(key)
        while len(self.order) > self.keep:
            self.cells.pop(self.order.pop(0), None)
        return cell


# ------------------------------------------------------------- sampling

def _round(v):
    return max(-32767, min(32767, int(math.floor(v + 0.5))))


def sample_grid(cell_of, z, x, y):
    """The GRID*GRID heights of a tile, plain Python."""
    out = []
    for lat, lon in sample_points(z, x, y):
        cell = cell_of(int(math.floor(lat)), int(math.floor(lon)))
        if cell is None:
            out.append(NODATA)
            continue
        fc = (lon - cell.lon0) / cell.sx
        fr = (cell.lat0 - lat) / cell.sy
        c0 = min(max(int(math.floor(fc)), 0), cell.width - 2)
        r0 = min(max(int(math.floor(fr)), 0), cell.height - 2)
        tc = min(max(fc - c0, 0.0), 1.0)
        tr = min(max(fr - r0, 0.0), 1.0)
        v00, v01 = cell.pixel(c0, r0), cell.pixel(c0 + 1, r0)
        v10, v11 = cell.pixel(c0, r0 + 1), cell.pixel(c0 + 1, r0 + 1)
        if v00 is None or v01 is None or v10 is None or v11 is None:
            out.append(NODATA)
            continue
        a = v00 * (1 - tc) + v01 * tc
        b = v10 * (1 - tc) + v11 * tc
        out.append(_round(a * (1 - tr) + b * tr))
    return out


def sample_grid_np(cell_of, z, x, y):
    """The same heights, numpy — identical numbers (same float64 ops in
    the same order), checked in the self-test."""
    lons = np.array(sample_lons(x, z), dtype=np.float64)
    lats = np.array(sample_lats(y, z), dtype=np.float64)
    lat_g, lon_g = np.meshgrid(lats, lons, indexing="ij")
    lat_f, lon_f = lat_g.ravel(), lon_g.ravel()
    la, lo = np.floor(lat_f).astype(np.int64), np.floor(lon_f).astype(np.int64)
    out = np.full(GRID * GRID, NODATA, dtype=np.int64)
    for key in {(int(a), int(b)) for a, b in zip(la, lo)}:
        cell = cell_of(*key)
        if cell is None or cell.array is None:
            continue
        m = (la == key[0]) & (lo == key[1])
        fc = (lon_f[m] - cell.lon0) / cell.sx
        fr = (cell.lat0 - lat_f[m]) / cell.sy
        c0 = np.clip(np.floor(fc), 0, cell.width - 2).astype(np.int64)
        r0 = np.clip(np.floor(fr), 0, cell.height - 2).astype(np.int64)
        tc = np.clip(fc - c0, 0.0, 1.0)
        tr = np.clip(fr - r0, 0.0, 1.0)
        arr = cell.array
        v00, v01 = arr[r0, c0], arr[r0, c0 + 1]
        v10, v11 = arr[r0 + 1, c0], arr[r0 + 1, c0 + 1]
        a = v00 * (1 - tc) + v01 * tc
        b = v10 * (1 - tc) + v11 * tc
        v = a * (1 - tr) + b * tr
        good = ~np.isnan(v)
        rounded = np.clip(np.floor(v[good] + 0.5), -32767, 32767).astype(np.int64)
        idx = np.flatnonzero(m)
        out[idx[good]] = rounded
    return out.tolist()


def sample_tile(cell_of, z, x, y):
    return (sample_grid_np if np is not None else sample_grid)(cell_of, z, x, y)


# ------------------------------------------------------------- build

def cells_for_bbox(bbox):
    west, south, east, north = bbox
    return [(la, lo)
            for la in range(int(math.floor(south)), int(math.ceil(north)))
            for lo in range(int(math.floor(west)), int(math.ceil(east)))]


def region_filter(path, zoom=ZOOM):
    """A test (x, y) -> bool for the tiles of a polygon region (#220, 18c),
    or None for the whole bbox. Rasterised like the map's plan: a tile
    belongs when its z10 ancestor touches the polygon, so the heights
    reach up to one z10 tile beyond the border (~25 km in Canada) —
    where the map is cut exactly. Too much at the border is the harmless
    direction; rasterising the polygon at z13 instead would scan 3 800
    rows against every edge of a coastline, minutes for nothing."""
    if not path:
        return None
    with open(path, encoding="utf-8") as fh:
        rings = map_tiles.region_rings(json.load(fh))
    cz = min(map_tiles.REGION_COVER_ZOOM, zoom)
    cover = map_tiles.region_cover(rings, cz)
    shift = zoom - cz
    return lambda x, y: (x >> shift, y >> shift) in cover


def tiles_by_cell(bbox, zoom=ZOOM, inside=None):
    """{(la, lo): [(x, y), …]} — every tile of the bbox (and of the region,
    if `inside` is given), filed under the cell its centre lies in (so
    each tile is built exactly once and the cell cache stays small)."""
    ids = map_tiles.bbox_tile_ids(bbox, zoom, zoom)[zoom]
    out = {}
    for tile_id in ids:
        _, x, y = map_tiles.tile_id_to_zxy(tile_id)
        if inside is not None and not inside(x, y):
            continue
        lat = tile_lat(y + 0.5, zoom)
        lon = tile_lon(x + 0.5, zoom)
        out.setdefault((int(math.floor(lat)), int(math.floor(lon))), []).append((x, y))
    for v in out.values():
        v.sort(key=lambda t: (t[1], t[0]))
    return out


def build_tiles(bbox, cell_of, zoom=ZOOM, cells=None, log=None, inside=None):
    """{(z, x, y): bytes} for the bbox (or only `cells`), plus stats."""
    by_cell = tiles_by_cell(bbox, zoom, inside)
    todo = sorted(by_cell) if cells is None else [c for c in sorted(by_cell) if c in cells]
    tiles = {}
    stats = {"tiles": 0, "empty": 0, "cells": len(todo), "cells_missing": 0, "bytes": 0,
             "sizes": [], "seconds": 0.0, "zoom": zoom}
    started = time.time()
    for n, key in enumerate(todo, 1):
        cell_started = time.time()
        if cell_of(*key) is None:
            stats["cells_missing"] += 1
        for x, y in by_cell[key]:
            values = sample_tile(cell_of, zoom, x, y)
            if all(v == NODATA for v in values):
                stats["empty"] += 1
                continue
            data = encode_tile(values)
            tiles[(zoom, x, y)] = data
            stats["tiles"] += 1
            stats["bytes"] += len(data)
            stats["sizes"].append(len(data))
        if log:
            log(f"  cell {n}/{len(todo)} {rm.dem_tile_name(key[0] + 0.5, key[1] + 0.5)}: "
                f"{len(by_cell[key])} tiles, {time.time() - cell_started:.1f} s")
    stats["seconds"] = time.time() - started
    stats["tiles_in_bbox"] = sum(len(v) for v in by_cell.values())
    return tiles, stats


def archive_metadata(build, bbox, stats):
    return {
        "format": FORMAT,
        "name": f"TrailBuddy heights {build}",
        "grid": GRID,
        "zoom": stats["zoom"],
        "nodata": NODATA,
        "unit": "m",
        "bbox": list(bbox),
        "build": build,
        "source": SOURCE_NAME,
        "attribution": ATTRIBUTION,
    }


def write_archive(tiles, bbox, build, out_dir, stats):
    """heights-<build>.pmtiles and heights.json; returns the manifest."""
    if not tiles:
        raise ValueError("no height tiles — nothing to write")
    os.makedirs(out_dir, exist_ok=True)
    data = map_tiles._build_archive(
        tiles, tile_compression=map_tiles.COMPRESSION_GZIP, tile_type=0,
        bounds=bbox, metadata=archive_metadata(build, bbox, stats))
    name = f"heights-{build}.pmtiles"
    path = os.path.join(out_dir, name)
    with open(path, "wb") as fh:
        fh.write(data)
    manifest = {
        "format": FORMAT,
        "file": name,
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "zoom": stats["zoom"],
        "grid": GRID,
        "nodata": NODATA,
        "bbox": list(bbox),
        "build": build,
        "tiles": stats["tiles"],
        "source": SOURCE_NAME,
        "attribution": ATTRIBUTION,
    }
    with open(os.path.join(out_dir, "heights.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2, sort_keys=True)
        fh.write("\n")
    return manifest


def _median(values):
    if not values:
        return 0
    s = sorted(values)
    return s[len(s) // 2]


def summary_md(stats, manifest=None, projected=None):
    lines = ["## Height tiles", ""]
    if manifest:
        lines.append(f"- `{manifest['file']}`: {map_tiles.human(manifest['bytes'])}, "
                     f"{manifest['tiles']} tiles at z{manifest['zoom']}, grid {manifest['grid']}×{manifest['grid']}")
    lines += [
        f"- cells: {stats['cells']} read, {stats['cells_missing']} not in the bucket (sea)",
        f"- tiles: {stats['tiles']} with heights, {stats['empty']} empty (left out), "
        f"of {stats.get('tiles_in_bbox', stats['tiles'] + stats['empty'])} in the box",
        f"- bytes per tile: median {_median(stats['sizes'])}, min {min(stats['sizes']) if stats['sizes'] else 0}, "
        f"max {max(stats['sizes']) if stats['sizes'] else 0}, mean "
        f"{(stats['bytes'] // stats['tiles']) if stats['tiles'] else 0}",
        f"- time: {stats['seconds']:.0f} s",
    ]
    if projected:
        lines += ["", f"Projected for the whole box: {projected['tiles']} tiles, "
                      f"about {map_tiles.human(projected['bytes'])}, about {projected['minutes']:.0f} min."]
    return "\n".join(lines) + "\n"


# ------------------------------------------------------------- check

def check_archive(source, cell_of, samples=24, seed=20261001, decode_all=False, log=None):
    """Opens the archive the way the app does and proves it: header and
    metadata say what the reader expects, every tile is z13, sampled
    tiles decode and equal a fresh read of the DEM, sample for sample.
    Raises on the first contradiction; returns a small report."""
    archive = map_tiles.Archive(map_tiles.open_source(source))
    try:
        h = archive.header
        if h.tile_type != 0:
            raise ValueError(f"tile type {h.tile_type}, expected 0 (unknown)")
        if h.tile_compression != map_tiles.COMPRESSION_GZIP:
            raise ValueError("tile compression is not gzip")
        meta = archive.metadata()
        for key, want in (("format", FORMAT), ("grid", GRID), ("nodata", NODATA)):
            if meta.get(key) != want:
                raise ValueError(f"metadata {key} = {meta.get(key)!r}, expected {want!r}")
        zoom = meta.get("zoom")
        if h.min_zoom != zoom or h.max_zoom != zoom:
            raise ValueError(f"zoom range {h.min_zoom}–{h.max_zoom}, expected only {zoom}")
        ids = []
        for entry in archive.walk():
            ids.extend(range(entry.tile_id, entry.tile_id + entry.run_length))
        if not ids:
            raise ValueError("the archive has no tiles")
        rng = random.Random(seed)
        chosen = ids if decode_all else sorted(rng.sample(ids, min(samples, len(ids))))
        compared = 0
        for n, tile_id in enumerate(chosen, 1):
            z, x, y = map_tiles.tile_id_to_zxy(tile_id)
            if z != zoom:
                raise ValueError(f"tile {z}/{x}/{y} is not at zoom {zoom}")
            entry = archive.find(tile_id)
            values = decode_tile(archive.tile_bytes(entry))
            if decode_all and n > samples and tile_id not in set(chosen[:samples]):
                continue
            fresh = sample_tile(cell_of, z, x, y)
            if fresh != values:
                diff = max(abs(a - b) for a, b in zip(fresh, values))
                raise ValueError(f"tile {z}/{x}/{y} differs from the DEM (max {diff} m)")
            compared += 1
            if log:
                log(f"  tile {z}/{x}/{y} ok ({n}/{len(chosen)})")
        return {"tiles": len(ids), "decoded": len(chosen), "compared": compared, "build": meta.get("build")}
    finally:
        archive.close()


# ------------------------------------------------------------- self-test

class FnCell(Cell):
    """A synthetic 1° cell from a function of (lat, lon), pixel-is-point
    like the bucket's tiles: first pixel centre at (lat0, lon0)."""

    def __init__(self, la, lo, fn, width=120, height=120, nodata_at=()):
        sx = 1.0 / width
        sy = 1.0 / height
        lon0, lat0 = float(lo), float(la + 1)
        self.fn, self.nodata_at = fn, set(nodata_at)
        grid = [[fn(lat0 - r * sy, lon0 + c * sx) for c in range(width)] for r in range(height)]
        for c, r in self.nodata_at:
            grid[r][c] = None
        self.grid = grid
        array = None
        if np is not None:
            array = np.array([[np.nan if v is None else v for v in row] for row in grid], dtype=np.float64)
        super().__init__(width, height, lon0, lat0, sx, sy, self._px, array)

    def _px(self, c, r):
        if not (0 <= c < self.width and 0 <= r < self.height):
            return None
        return self.grid[r][c]


def _expect(cond, what):
    if not cond:
        raise AssertionError(what)


def _of(cells):
    """A `cell_of` over a dict keyed by (floor(lat), floor(lon))."""
    return lambda la, lo: cells.get((la, lo))


def self_test():
    # 1. tile bytes: round trip, NODATA, extremes, wrapping deltas.
    grid = fixture_grid()
    data = encode_tile(grid)
    _expect(decode_tile(data) == grid, "encode/decode round trip")
    _expect(len(data) < GRID * GRID * 2 // 3, f"delta+gzip compresses the fixture ({len(data)} B)")
    raw = gzip.decompress(data)
    _expect(len(raw) == 4802, "a tile is 4802 bytes before gzip")
    # The constants the Dart test holds against the same fixture.
    _expect(raw[:8] == bytes.fromhex("88ff670407000700"), f"first delta bytes {raw[:8].hex()}")
    _expect(fnv1a(raw) == 0x20E77837, f"fixture FNV-1a {fnv1a(raw):#x}")
    extremes = [NODATA, 32767, -32767, 0] * (GRID * GRID // 4) + [NODATA]
    _expect(decode_tile(encode_tile(extremes)) == extremes, "wrapping deltas survive")
    try:
        decode_tile(gzip.compress(b"\x00" * 100))
        _expect(False, "a short tile must be rejected")
    except ValueError:
        pass
    for bad in ([1] * 10, [40000] + [0] * (GRID * GRID - 1)):
        try:
            encode_tile(bad)
            _expect(False, "wrong length / out of range must be rejected")
        except ValueError:
            pass

    # 2. sample positions: 49 per axis, both edges, row 0 north.
    pts = sample_points(ZOOM, 4300, 2900)
    _expect(len(pts) == GRID * GRID, "49x49 samples")
    _expect(pts[0][1] == tile_lon(4300, ZOOM) and pts[GRID - 1][1] == tile_lon(4301, ZOOM),
            "first row spans the tile's west to east edge inclusive")
    _expect(pts[0][0] == tile_lat(2900, ZOOM) and pts[-1][0] == tile_lat(2901, ZOOM),
            "row 0 is the north edge, the last row the south edge")
    _expect(pts[0][0] > pts[-1][0], "rows go north to south")
    # Neighbouring tiles share their border samples exactly.
    _expect(sample_lons(4300, ZOOM)[-1] == sample_lons(4301, ZOOM)[0], "shared east/west border")
    _expect(sample_lats(2900, ZOOM)[-1] == sample_lats(2901, ZOOM)[0], "shared north/south border")

    # 3. sampling against a synthetic cell: a plane is bilinear-exact.
    def plane(lat, lon):
        return 500.0 + (lon - 11.0) * 1200.0 + (48.0 - lat) * 600.0
    cell = FnCell(47, 11, plane)
    cells = {(47, 11): cell}
    x, y = map_tiles.lonlat_to_tile(11.4, 47.6, ZOOM)
    got = sample_grid(_of(cells), ZOOM, x, y)
    want = [_round(plane(lat, lon)) for lat, lon in sample_points(ZOOM, x, y)]
    _expect(got == want, "a plane is sampled exactly (plain path)")
    # A tile across the cell border: the other half is NODATA without the
    # neighbour cell, and present with it.
    bx, by = map_tiles.lonlat_to_tile(12.0, 47.6, ZOOM)
    half = sample_grid(_of(cells), ZOOM, bx, by)
    _expect(NODATA in half and any(v != NODATA for v in half), "border tile: half NODATA without the neighbour")
    cells[(47, 12)] = FnCell(47, 12, plane)
    full = sample_grid(_of(cells), ZOOM, bx, by)
    _expect(NODATA not in full, "border tile: complete with the neighbour")
    # The last pixel strip holds the last pixel (no reach into the neighbour).
    edge_lat, edge_lon = 47.6, 12.0 - 0.3 / 120
    fc = (edge_lon - cell.lon0) / cell.sx
    _expect(fc > cell.width - 1, "the probe lies in the last strip")
    strip = sample_grid(_of(cells), 20, *map_tiles.lonlat_to_tile(edge_lon, edge_lat, 20))
    _expect(all(v != NODATA for v in strip), "the last strip has heights")
    # Nodata in the DEM makes the sample NODATA, nothing else.
    holed = {(47, 11): FnCell(47, 11, plane, nodata_at=[(60, 60)])}
    hx, hy = map_tiles.lonlat_to_tile(11.5, 47.5, ZOOM)
    with_hole = sample_grid(_of(holed), ZOOM, hx, hy)
    _expect(NODATA in with_hole and with_hole.count(NODATA) < GRID * GRID // 2, "a DEM hole becomes NODATA locally")

    # 4. the numpy path equals the plain path, number for number.
    if np is not None:
        for (tx, ty), store in (((x, y), cells), ((bx, by), cells), ((hx, hy), holed)):
            _expect(sample_grid_np(_of(store), ZOOM, tx, ty) == sample_grid(_of(store), ZOOM, tx, ty),
                    f"numpy == plain on tile {tx}/{ty}")
        bumpy = {(47, 11): FnCell(47, 11, lambda la, lo: 800 + 300 * math.sin(lo * 40) * math.cos(la * 70))}
        _expect(sample_grid_np(_of(bumpy), ZOOM, x, y) == sample_grid(_of(bumpy), ZOOM, x, y),
                "numpy == plain on rough terrain")
        # The COG decoder: predictor 3 and 1 against the byte-loop reader.
        for pred in (3, 1):
            cog = rm.CogTile(rm._synthetic_cog(predictor=pred))
            arr = cog_to_array(cog)
            for r in range(cog.height):
                for c in range(cog.width):
                    _expect(arr[r, c] == cog.pixel(c, r), f"COG decode predictor {pred} at {c},{r}")
        cc = Cell.from_cog(rm.CogTile(rm._synthetic_cog()))
        _expect(cc.array is not None and cc.array.shape == (8, 8), "a cell from a COG carries its array")

    # 5. build → archive → read back like the app → check.
    import tempfile
    bbox = (11.3, 47.3, 11.5, 47.45)
    tiles, stats = build_tiles(bbox, _of(cells))
    _expect(stats["tiles"] > 10 and stats["empty"] == 0, f"tiles built: {stats}")
    _expect(stats["tiles"] == stats["tiles_in_bbox"], "every tile of the box has heights")
    with tempfile.TemporaryDirectory() as tmp:
        manifest = write_archive(tiles, bbox, "20261001", tmp, stats)
        _expect(manifest["file"] == "heights-20261001.pmtiles" and manifest["tiles"] == stats["tiles"],
                "manifest names the file and counts")
        path = os.path.join(tmp, manifest["file"])
        _expect(os.path.getsize(path) == manifest["bytes"], "manifest bytes")
        archive = map_tiles.Archive(map_tiles.open_source(path))
        for (z, tx, ty), data in tiles.items():
            entry = archive.find(map_tiles.zxy_to_tile_id(z, tx, ty))
            _expect(entry is not None and archive.tile_bytes(entry) == data, "every tile comes back byte for byte")
            _expect(decode_tile(archive.tile_bytes(entry)) == sample_grid(_of(cells), z, tx, ty),
                    "and decodes to the DEM")
        meta = archive.metadata()
        _expect(meta["format"] == FORMAT and meta["grid"] == GRID and meta["zoom"] == ZOOM, "archive metadata")
        _expect(archive.header.tile_compression == map_tiles.COMPRESSION_GZIP and archive.header.tile_type == 0,
                "header: gzip tiles of unknown type")
        _expect(archive.header.min_zoom == ZOOM == archive.header.max_zoom, "header zoom range")
        _expect(abs(archive.header.bounds[0] - bbox[0]) < 1e-6, "header bounds")
        archive.close()
        report = check_archive(path, _of(cells), samples=5, decode_all=True)
        _expect(report["tiles"] == stats["tiles"] and report["compared"] == 5, f"check report {report}")
        md = summary_md(stats, manifest)
        _expect("tiles" in md and manifest["file"] in md, "summary names the file")
        # A tile that no longer matches the DEM fails the check.
        other = {(47, 11): FnCell(47, 11, lambda la, lo: plane(la, lo) + 3)}
        try:
            check_archive(path, _of(other), samples=3)
            _expect(False, "a changed DEM must fail the check")
        except ValueError as e:
            _expect("differs" in str(e), f"wrong failure: {e}")
        # A tampered manifest field fails too.
        bad = dict(tiles)
        first = next(iter(bad))
        bad[first] = encode_tile([0] * (GRID * GRID))
        bad_manifest = write_archive(bad, bbox, "20261002", tmp, stats)
        try:
            check_archive(os.path.join(tmp, bad_manifest["file"]), _of(cells), decode_all=True)
            _expect(False, "a tampered tile must fail the check")
        except ValueError:
            pass
    # A box with no DEM at all: nothing to write, and that is said.
    none, s2 = build_tiles((20.0, 40.0, 20.1, 40.1), lambda la, lo: None)
    _expect(not none and s2["cells_missing"] >= 1 and s2["empty"] == s2["tiles_in_bbox"], "sea: empty tiles, missing cell")
    try:
        write_archive(none, bbox, "x", "/nonexistent", s2)
        _expect(False, "no tiles must not write")
    except ValueError:
        pass
    # A region (#220, 18c): only tiles whose z10 ancestor touches the
    # polygon, the rest of the bbox is not built. A western strip of the
    # box keeps the western tiles and none east of its z10 margin.
    box = (10.0, 47.0, 12.0, 47.5)
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "west.geojson")
        with open(path, "w") as fh:
            json.dump({"type": "Polygon", "coordinates": [[[10.0, 47.0], [10.3, 47.0],
                       [10.3, 47.5], [10.0, 47.5], [10.0, 47.0]]]}, fh)
        inside = region_filter(path)
        whole = sum(len(v) for v in tiles_by_cell(box).values())
        part = tiles_by_cell(box, inside=inside)
        kept = [t for v in part.values() for t in v]
        _expect(0 < len(kept) < whole / 2, f"region keeps {len(kept)} of {whole}")
        margin = 360.0 / (1 << map_tiles.REGION_COVER_ZOOM)
        _expect(all(tile_lon(x, ZOOM) < 10.3 + margin for x, _ in kept), "nothing east of the margin")
        _expect(region_filter(None) is None, "no region, no filter")
    # A 404 for a listed cell is a flicker, not sea: retried, and never
    # remembered as missing; an unlisted 404 is sea at once.
    with tempfile.TemporaryDirectory() as tmp:
        calls = []

        def flicker(url):
            calls.append(url)
            if len(calls) < 3:
                raise urllib.error.HTTPError(url, 404, "flicker", None, None)
            return b"COG"
        got = fetch_cog("cellA", tmp, flicker, listed=lambda n: True, wait=lambda s: None)
        _expect(got == b"COG" and len(calls) == 3, f"listed cell retried: {calls}")
        _expect(not os.path.exists(os.path.join(tmp, "cellA.tif.missing")), "no marker for a flicker")

        def gone(url):
            raise urllib.error.HTTPError(url, 404, "nope", None, None)
        _expect(fetch_cog("cellB", tmp, gone, listed=lambda n: False) is None, "unlisted 404 is sea")
        _expect(os.path.exists(os.path.join(tmp, "cellB.tif.missing")), "sea is remembered")
        try:
            fetch_cog("cellC", tmp, gone, listed=lambda n: True, wait=lambda s: None)
            _expect(False, "a listed cell that never reads must fail")
        except RuntimeError:
            pass
    _expect(glue_bbox(["build", "--bbox", "-133.2,41.6,-52.6,55", "--build", "x"])
            == ["build", "--bbox=-133.2,41.6,-52.6,55", "--build", "x"], "a box west of Greenwich")
    print("self-test ok" + ("" if np is not None else " (plain path only, numpy not installed)"))


# ------------------------------------------------------------- main

def parse_bbox(text):
    parts = [float(v) for v in text.split(",")]
    if len(parts) != 4 or parts[0] >= parts[2] or parts[1] >= parts[3]:
        raise argparse.ArgumentTypeError("bbox is west,south,east,north")
    return tuple(parts)


def glue_bbox(argv):
    """`--bbox W,S,E,N` -> `--bbox=W,S,E,N`. argparse reads a value with a
    leading minus as an option, and every box west of Greenwich has one
    (Canada, 18c); height-data.yml keeps the plain spelling. The same
    helper as in way_archive.py and poi_extract.py."""
    out = list(argv)
    for i in range(len(out) - 1):
        if out[i] == "--bbox":
            out[i:i + 2] = [f"--bbox={out[i + 1]}", None]
    return [a for a in out if a is not None]


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--self-test", action="store_true")
    sub = parser.add_subparsers(dest="cmd")
    for name in ("plan", "build"):
        p = sub.add_parser(name)
        p.add_argument("--bbox", type=parse_bbox, required=True, help="west,south,east,north")
        p.add_argument("--region", help="GeoJSON polygon: only the tiles inside it (#220)")
        p.add_argument("--dem-cache", default="build/dem")
        p.add_argument("--summary")
        p.add_argument("--zoom", type=int, default=ZOOM)
        if name == "plan":
            p.add_argument("--sample-cells", type=int, default=2)
        else:
            p.add_argument("--build", required=True, help="JJJJMMTT")
            p.add_argument("--out", default="build/heights")
    c = sub.add_parser("check")
    c.add_argument("--source", required=True, help="path or https URL of the archive")
    c.add_argument("--dem-cache", default="build/dem")
    c.add_argument("--samples", type=int, default=24)
    c.add_argument("--seed", type=int, default=20261001)
    c.add_argument("--all", action="store_true", help="decode every tile (local archives)")
    c.add_argument("--summary")
    args = parser.parse_args(glue_bbox(sys.argv[1:]))

    if args.self_test:
        self_test()
        return
    if args.cmd in ("plan", "build") and np is None:
        sys.exit("numpy is needed for plan/build (pip install numpy); the self-test and check run without it")
    log = lambda s: print(s, flush=True)  # noqa: E731
    if args.cmd == "plan":
        cells = DemCells(args.dem_cache)
        inside = region_filter(args.region, args.zoom)
        by_cell = tiles_by_cell(args.bbox, args.zoom, inside)
        total = sum(len(v) for v in by_cell.values())
        # The sample cells: the densest ones in tiles, from the middle of
        # the box, so a coastal cell does not make the projection cheap.
        ordered = sorted(by_cell, key=lambda k: (-len(by_cell[k]), abs(k[0] - (args.bbox[1] + args.bbox[3]) / 2)))
        chosen = set(ordered[:args.sample_cells])
        log(f"{total} tiles at z{args.zoom} in {len(by_cell)} cells; sampling {sorted(chosen)}")
        tiles, stats = build_tiles(args.bbox, cells, args.zoom, cells=chosen, log=log, inside=inside)
        per_tile = stats["bytes"] / max(1, stats["tiles"])
        per_cell_s = stats["seconds"] / max(1, stats["cells"])
        projected = {"tiles": total, "bytes": int(total * per_tile),
                     "minutes": per_cell_s * len(by_cell) / 60}
        md = summary_md(stats, projected=projected)
    elif args.cmd == "build":
        cells = DemCells(args.dem_cache)
        tiles, stats = build_tiles(args.bbox, cells, args.zoom, log=log,
                                   inside=region_filter(args.region, args.zoom))
        manifest = write_archive(tiles, args.bbox, args.build, args.out, stats)
        md = summary_md(stats, manifest)
    else:
        cells = DemCells(args.dem_cache)
        report = check_archive(args.source, cells, samples=args.samples, seed=args.seed,
                               decode_all=args.all, log=log)
        md = (f"## Height tiles checked\n\n- `{args.source}`: {report['tiles']} tiles, build {report['build']}\n"
              f"- {report['decoded']} decoded, {report['compared']} compared with a fresh DEM read: all equal\n")
    print(md)
    if args.summary:
        with open(args.summary, "a", encoding="utf-8") as fh:
            fh.write(md)


if __name__ == "__main__":
    main()
