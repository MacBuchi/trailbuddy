#!/usr/bin/env python3
"""The way archive (#212): track grade and path difficulty from OSM, as
ONE PMTiles archive next to the base map and the height tiles.

Our Protomaps base map carries `kind_detail` (track, path …) and nothing
about the way itself. #211 measured what OSM has (docs/routing-messung.md,
section "#211"): `tracktype` on 83 % of the track length in DACH,
`sac_scale`/`mtb:scale` on a fifth of the paths, and the base map's lines
lie within 3 m of their OSM way. So the archive carries only the ways
that HAVE a grade, and only the grade — the base map draws the way, the
app lays the grade over it by geometry; routing (#213) reads the same
archive.

The tile format (`FORMAT` 2, since #213; 1 had six classes and no `u`),
mirrored in Dart (`kWaysFormat` …):
  - Mapbox Vector Tiles, gzip, ONE zoom (`ZOOM`), extent 4096, a
    `BUFFER` of tile units beyond the edge so line caps do not show
    seams; one layer `ways`.
  - one feature per class (and uphill grade) per tile, a MultiLineString
    with the property `k` (unsigned int), the class:
      1 track good       tracktype grade1–2
      2 track medium     tracktype grade3
      3 track poor       tracktype grade4
      7 track very poor  tracktype grade5, or smoothness bad or worse,
                         or surface mud — whatever the tracktype says
      4 path easy        mtb:scale 0–1, else sac_scale T1
      5 path medium      mtb:scale 2,   else sac_scale T2
      6 path hard        mtb:scale 3,   else sac_scale T3
      8 path very hard   mtb:scale ≥ 4, else sac_scale ≥ T4
    and, on paths that carry it, `u` (unsigned int 0–5), the
    `mtb:scale:uphill` — the best signal for riding a path up (#213).
    The codes 1–6 kept their numbers from format 1; 3 and 6 lost their
    worst part to 7 and 8. Routing (#213) prices 7 and 8 apart, the map
    draws them rougher still.
    `mtb:scale` wins over `sac_scale` where both are set: it is the
    rating for bikes. Several values (`grade2;grade4`) count the worst
    (way_tags.py normalises). Paths are `path` and `bridleway`;
    `footway` never carries either tag (#211: 0 %).
  - geometry simplified (Douglas–Peucker) by `SIMPLIFY` tile units on
    the whole way before it is cut into tiles, so neighbouring tiles
    agree on the shared border.

A manifest `ways.json` names the current file, like `heights.json` does.

Usage:
  python3 tool/way_archive.py build --pbf <pbf> [--pbf <pbf> …] --build 20261101 \\
      --out build/ways [--bbox W,S,E,N] [--zoom 13] [--simplify 1.5] [--summary out.md]
  python3 tool/way_archive.py check --source <file or https URL> [--samples 24]
  python3 tool/way_archive.py --self-test        # no network, no osmium

Stdlib plus the `osmium` binary, as way_tags.py. Ways are streamed as a
GeoJSON sequence and encoded into per-tile byte buffers right away; the
whole of DACH never sits in memory as coordinates.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import math
import os
import random
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import map_tiles  # noqa: E402  (tool/, same directory)
import route_measure as rm  # noqa: E402  (MVT varints, clip_line, decoder)
import way_tags  # noqa: E402  (normalisation)

FORMAT = 2
ZOOM = 13
EXTENT = 4096
BUFFER = 16
SIMPLIFY = 1.5
LAYER = "ways"
KEY = "k"
UPHILL_KEY = "u"
CLASSES = {
    1: "track_good", 2: "track_medium", 3: "track_poor", 7: "track_very_poor",
    4: "path_easy", 5: "path_medium", 6: "path_hard", 8: "path_very_hard",
}
UPHILL_MAX = 5
PATH_HIGHWAYS = ("path", "bridleway")
TAG_KEYS = ("tracktype", "sac_scale", "mtb:scale", "mtb:scale:uphill", "smoothness")
# A track with smoothness from here on is very poor (way_tags.SMOOTHNESS:
# excellent, good, intermediate, bad …). `surface=mud` is the third way
# in; only that one value is filtered, surface itself is on half the tracks.
ROUGH_SMOOTHNESS = way_tags.SMOOTHNESS.index("bad")
MUD = "mud"
# The map's area — the SAME box as DACH_BBOX in map-data.yml and
# height-data.yml; test/release_workflow_test.dart holds them together.
DACH_BBOX = (5.5, 45.5, 17.5, 55.5)
SOURCE_NAME = "OpenStreetMap"
ATTRIBUTION = "© OpenStreetMap contributors (ODbL)"


# ------------------------------------------------------------- classes

def way_class(props):
    """The class (CLASSES) of one OSM way, or None when it carries no grade."""
    hw = props.get("highway")
    if hw == "track":
        grade = way_tags.norm_tracktype(props.get("tracktype") or "")
        smooth = way_tags.norm_rank(props.get("smoothness") or "", way_tags.SMOOTHNESS)
        mud = MUD in way_tags._parts(props.get("surface") or "")
        if grade == 5 or mud or (smooth is not None and smooth >= ROUGH_SMOOTHNESS):
            return 7
        if grade is None:
            return None
        return 1 if grade <= 2 else 2 if grade == 3 else 3
    if hw in PATH_HIGHWAYS:
        mtb = way_tags.norm_mtb(props.get("mtb:scale") or "")
        if mtb is not None:
            return 4 if mtb <= 1 else 5 if mtb == 2 else 6 if mtb == 3 else 8
        sac = way_tags.norm_sac(props.get("sac_scale") or "")
        if sac is not None:
            return 4 if sac == 1 else 5 if sac == 2 else 6 if sac == 3 else 8
    return None


def way_uphill(props):
    """`mtb:scale:uphill` 0–5 of a path, else None (tracks never)."""
    if props.get("highway") not in PATH_HIGHWAYS:
        return None
    return way_tags.norm_mtb(props.get("mtb:scale:uphill") or "", UPHILL_MAX)


# ------------------------------------------------------------- osmium

def prefilter(pbf, out, workdir, runner=subprocess.run):
    """The graded ways of one extract (with their nodes) into `out`.

    Two chained filters are an AND: the highway values, then any of the
    grade keys or `surface=mud`. What is left is a few percent of the extract —
    way-data.yml runs this right after each download and deletes the
    original, so the runner's disk holds one country at a time."""
    by_highway = os.path.join(workdir, "highway.osm.pbf")
    try:
        runner(["osmium", "tags-filter", "--overwrite", "-o", by_highway, pbf,
                "w/highway=" + ",".join(("track",) + PATH_HIGHWAYS)], check=True)
        runner(["osmium", "tags-filter", "--overwrite", "-o", out, by_highway,
                *(f"w/{k}" for k in TAG_KEYS), f"w/surface={MUD}"], check=True)
    finally:
        if os.path.exists(by_highway):
            os.remove(by_highway)


def osmium_ways(pbf, workdir, runner=subprocess.run):
    """The graded ways of one extract as GeoJSON features, streamed.
    Filtering an already filtered file again is cheap and harmless."""
    graded = os.path.join(workdir, "graded.osm.pbf")
    exported = os.path.join(workdir, "ways.geojsonl")
    config = os.path.join(workdir, "export.json")
    with open(config, "w", encoding="utf-8") as handle:
        json.dump({"linear_tags": True, "area_tags": False,
                   "include_tags": ["highway", *TAG_KEYS, "surface"]}, handle)
    prefilter(pbf, graded, workdir, runner)
    runner(["osmium", "export", "--overwrite", "-f", "geojsonseq", "-c", config,
            "--geometry-types=linestring", "-o", exported, graded], check=True)
    try:
        with open(exported, encoding="utf-8") as handle:
            yield from way_tags.route_measure_features(handle)
    finally:
        for path in (graded, exported):
            if os.path.exists(path):
                os.remove(path)


# ------------------------------------------------------------- tiles

def world_units(lon, lat, zoom):
    """Web Mercator in tile units of `zoom` (EXTENT per tile)."""
    n = (1 << zoom) * EXTENT
    lat = max(-85.0511, min(85.0511, lat))
    r = math.radians(lat)
    return ((lon + 180) / 360 * n,
            (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n)


class TileBuilder:
    """Per-tile, per-class MVT geometry, encoded as it comes in.

    The geometry of a feature is a run of commands with a cursor; each
    (tile, class, uphill grade) keeps its own buffer and cursor, so a way
    is written once and forgotten. A key is `(k, u)`, `u` None where the
    way has no uphill grade."""

    def __init__(self, zoom=ZOOM, simplify=SIMPLIFY, bbox=DACH_BBOX):
        self.zoom = zoom
        self.tol = simplify
        self.buf = {}       # (x, y) -> {(cls, u): [bytearray, cx, cy]}
        self.ways = 0
        self.skipped = 0
        self.points = 0
        x0, y1 = map_tiles.lonlat_to_tile(bbox[0], bbox[1], zoom)
        x1, y0 = map_tiles.lonlat_to_tile(bbox[2], bbox[3], zoom)
        self.range = (x0, y0, x1, y1)

    def add(self, props, geometry):
        cls = way_class(props)
        if cls is None:
            self.skipped += 1
            return
        self.ways += 1
        key = (cls, way_uphill(props))
        for pts in way_tags.line_parts(geometry):
            if len(pts) >= 2:
                self.add_line(key, [world_units(p[0], p[1], self.zoom) for p in pts])

    def add_line(self, key, world):
        world = way_tags.simplify(world, self.tol)
        xs = [p[0] for p in world]
        ys = [p[1] for p in world]
        b = BUFFER
        tx0 = max(int((min(xs) - b) // EXTENT), self.range[0])
        tx1 = min(int((max(xs) + b) // EXTENT), self.range[2])
        ty0 = max(int((min(ys) - b) // EXTENT), self.range[1])
        ty1 = min(int((max(ys) + b) // EXTENT), self.range[3])
        for tx in range(tx0, tx1 + 1):
            for ty in range(ty0, ty1 + 1):
                ox, oy = tx * EXTENT - b, ty * EXTENT - b
                local = [(x - ox, y - oy) for x, y in world]
                for piece in rm.clip_line(local, EXTENT + 2 * b):
                    q = [(int(round(x)) - b, int(round(y)) - b) for x, y in piece]
                    q = [q[0]] + [p for a, p in zip(q, q[1:]) if p != a]
                    if len(q) >= 2:
                        self._write(tx, ty, key, q)

    def _write(self, tx, ty, key, line):
        slot = self.buf.setdefault((tx, ty), {}).get(key)
        if slot is None:
            slot = self.buf[(tx, ty)][key] = [bytearray(), 0, 0]
        geom, x, y = slot
        rm._put_varint(geom, (1 << 3) | 1)
        rm._put_varint(geom, rm._zz(line[0][0] - x))
        rm._put_varint(geom, rm._zz(line[0][1] - y))
        x, y = line[0]
        rm._put_varint(geom, (len(line) - 1) << 3 | 2)
        for px, py in line[1:]:
            rm._put_varint(geom, rm._zz(px - x))
            rm._put_varint(geom, rm._zz(py - y))
            x, y = px, py
        slot[1], slot[2] = x, y
        self.points += len(line)

    def tiles(self):
        """{(z, x, y): gzip(mvt)}; the buffers are released as it goes."""
        out = {}
        for (tx, ty) in sorted(self.buf):
            out[(self.zoom, tx, ty)] = gzip.compress(encode_tile(self.buf.pop((tx, ty))), 9, mtime=0)
        return out


def encode_tile(by_key):
    """One MVT layer `ways`: a feature per (class, uphill grade), `k` and
    `u` as uint values; one value entry per distinct number."""
    keys = sorted(by_key, key=lambda ku: (ku[0], -1 if ku[1] is None else ku[1]))
    numbers = sorted({n for ku in keys for n in ku if n is not None})
    index = {n: i for i, n in enumerate(numbers)}
    layer = bytearray()
    rm._put_field(layer, 15, 0, 2)
    rm._put_field(layer, 1, 2, LAYER.encode())
    for ku in keys:
        cls, uphill = ku
        f = bytearray()
        tags = bytearray()
        rm._put_varint(tags, 0)
        rm._put_varint(tags, index[cls])
        if uphill is not None:
            rm._put_varint(tags, 1)
            rm._put_varint(tags, index[uphill])
        rm._put_field(f, 2, 2, tags)
        rm._put_field(f, 3, 0, 2)               # LINESTRING
        rm._put_field(f, 4, 2, by_key[ku][0])
        rm._put_field(layer, 2, 2, f)
    rm._put_field(layer, 3, 2, KEY.encode())
    rm._put_field(layer, 3, 2, UPHILL_KEY.encode())
    for n in numbers:
        value = bytearray()
        rm._put_field(value, 5, 0, n)           # uint_value
        rm._put_field(layer, 4, 2, value)
    rm._put_field(layer, 5, 0, EXTENT)
    tile = bytearray()
    rm._put_field(tile, 3, 2, layer)
    return bytes(tile)


# ------------------------------------------------------------- archive

def archive_metadata(build, bbox, zoom):
    return {
        "format": FORMAT,
        "name": f"TrailBuddy ways {build}",
        "zoom": zoom,
        "classes": {str(k): v for k, v in CLASSES.items()},
        "bbox": list(bbox),
        "build": build,
        "source": SOURCE_NAME,
        "attribution": ATTRIBUTION,
        "vector_layers": [{"id": LAYER, "fields": {KEY: "Number", UPHILL_KEY: "Number"},
                           "minzoom": zoom, "maxzoom": zoom}],
    }


def write_archive(tiles, bbox, build, out_dir, zoom):
    """ways-<build>.pmtiles and ways.json; returns the manifest."""
    if not tiles:
        raise ValueError("no way tiles — nothing to write")
    os.makedirs(out_dir, exist_ok=True)
    data = map_tiles._build_archive(
        tiles, tile_compression=map_tiles.COMPRESSION_GZIP, tile_type=1,
        bounds=bbox, metadata=archive_metadata(build, bbox, zoom))
    name = f"ways-{build}.pmtiles"
    with open(os.path.join(out_dir, name), "wb") as fh:
        fh.write(data)
    manifest = {
        "format": FORMAT,
        "file": name,
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "zoom": zoom,
        "bbox": list(bbox),
        "build": build,
        "tiles": len(tiles),
        "source": SOURCE_NAME,
        "attribution": ATTRIBUTION,
    }
    with open(os.path.join(out_dir, "ways.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2, sort_keys=True)
        fh.write("\n")
    return manifest


def check_archive(source, samples=24, seed=20261101, log=None):
    """Opens the archive the way the app does and proves it: header and
    metadata say what the reader expects, every tile is at the one zoom,
    sampled tiles decode to line features of known classes inside the
    buffered tile. Raises on the first contradiction."""
    archive = map_tiles.Archive(map_tiles.open_source(source))
    try:
        h = archive.header
        if h.tile_type != 1:
            raise ValueError(f"tile type {h.tile_type}, expected 1 (mvt)")
        if h.tile_compression != map_tiles.COMPRESSION_GZIP:
            raise ValueError("tile compression is not gzip")
        meta = archive.metadata()
        if meta.get("format") != FORMAT:
            raise ValueError(f"metadata format = {meta.get('format')!r}, expected {FORMAT}")
        zoom = meta.get("zoom")
        if h.min_zoom != zoom or h.max_zoom != zoom:
            raise ValueError(f"zoom range {h.min_zoom}–{h.max_zoom}, expected only {zoom}")
        ids = []
        for entry in archive.walk():
            ids.extend(range(entry.tile_id, entry.tile_id + entry.run_length))
        if not ids:
            raise ValueError("the archive has no tiles")
        rng = random.Random(seed)
        chosen = sorted(rng.sample(ids, min(samples, len(ids))))
        counts = {}
        for n, tile_id in enumerate(chosen, 1):
            z, x, y = map_tiles.tile_id_to_zxy(tile_id)
            if z != zoom:
                raise ValueError(f"tile {z}/{x}/{y} is not at zoom {zoom}")
            raw = gzip.decompress(archive.tile_bytes(archive.find(tile_id)))
            feats = rm.decode_mvt_lines(raw, LAYER)
            if not feats:
                raise ValueError(f"tile {z}/{x}/{y} has no `{LAYER}` lines")
            for extent, props, lines in feats:
                cls = props.get(KEY)
                if extent != EXTENT or cls not in CLASSES:
                    raise ValueError(f"tile {z}/{x}/{y}: extent {extent}, class {cls!r}")
                uphill = props.get(UPHILL_KEY)
                if uphill is not None and (cls not in (4, 5, 6, 8) or not 0 <= uphill <= UPHILL_MAX):
                    raise ValueError(f"tile {z}/{x}/{y}: uphill {uphill!r} on class {cls}")
                for line in lines:
                    for px, py in line:
                        if not (-BUFFER <= px <= EXTENT + BUFFER and -BUFFER <= py <= EXTENT + BUFFER):
                            raise ValueError(f"tile {z}/{x}/{y}: point {px},{py} beyond the buffer")
                counts[cls] = counts.get(cls, 0) + 1
            if log:
                log(f"  tile {z}/{x}/{y} ok ({n}/{len(chosen)})")
        return {"tiles": len(ids), "decoded": len(chosen), "classes": counts, "build": meta.get("build")}
    finally:
        archive.close()


# ------------------------------------------------------------- summary

def summary_md(manifest, builder, seconds, height_bytes=None):
    lines = ["## Way archive", "",
             f"- `{manifest['file']}`: {map_tiles.human(manifest['bytes'])}, "
             f"{manifest['tiles']} tiles at z{manifest['zoom']}",
             f"- ways: {builder.ways:,} graded, {builder.skipped:,} without a usable grade",
             f"- points written: {builder.points:,}",
             f"- time: {seconds:.0f} s"]
    if height_bytes:
        lines.append(f"- against the height tiles ({map_tiles.human(height_bytes)}): "
                     f"{100 * manifest['bytes'] / height_bytes:.0f} %")
    return "\n".join(lines) + "\n"


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

    # Classes.
    check([way_class({"highway": "track", "tracktype": t})
           for t in ("grade1", "grade2", "grade3", "grade4", "grade5", "grade2;grade4", "")]
          == [1, 1, 2, 3, 7, 3, None], "track: grade1–2 good, 3 medium, 4 poor, 5 very poor, worst of several")
    check([way_class({"highway": "track", **t}) for t in (
              {"tracktype": "grade1", "smoothness": "bad"}, {"smoothness": "very_horrible"},
              {"tracktype": "grade2", "smoothness": "intermediate"}, {"surface": "mud"},
              {"tracktype": "grade3", "surface": "gravel;mud"}, {"surface": "gravel"})]
          == [7, 7, 1, 7, 7, None], "track: smoothness bad or worse and mud are very poor, whatever the grade")
    check([way_class({"highway": "path", "sac_scale": s})
           for s in ("hiking", "T2", "demanding_mountain_hiking", "alpine_hiking", "T6", "x")]
          == [4, 5, 6, 8, 8, None], "path by sac_scale: T1 easy, T2 medium, T3 hard, T4+ very hard")
    check([way_class({"highway": "path", "mtb:scale": m}) for m in ("0", "1+", "2", "3", "4", "5")]
          == [4, 4, 5, 6, 8, 8], "path by mtb:scale: 0–1 easy, 2 medium, 3 hard, 4+ very hard")
    check([way_uphill({"highway": h, "mtb:scale:uphill": u}) for h, u in (
              ("path", "2"), ("bridleway", "5"), ("path", "6"), ("track", "1"), ("path", ""))]
          == [2, 5, None, None, None], "uphill: 0–5 on paths only")
    check(way_class({"highway": "path", "mtb:scale": "1", "sac_scale": "T4"}) == 4,
          "mtb:scale wins over sac_scale")
    check(way_class({"highway": "bridleway", "sac_scale": "T1"}) == 4
          and way_class({"highway": "footway", "sac_scale": "T1"}) is None
          and way_class({"highway": "track", "sac_scale": "T5"}) is None,
          "bridleway counts as path; footway and a track's sac_scale do not")

    # A grade4 track across the border of two z13 tiles, and a path.
    z = ZOOM
    lon_edge = 9.0
    x_edge = math.floor(world_units(lon_edge, 47.9, z)[0] / EXTENT) * EXTENT
    lon_b = (x_edge / ((1 << z) * EXTENT)) * 360 - 180    # exactly on a tile border
    track = _feature("track", [[lon_b - 0.004, 47.9], [lon_b + 0.004, 47.9001]], tracktype="grade4")
    path = _feature("path", [[lon_b - 0.002, 47.899], [lon_b - 0.002, 47.901]],
                    **{"mtb:scale": "3", "mtb:scale:uphill": "4"})
    bare = _feature("track", [[lon_b - 0.003, 47.898], [lon_b + 0.003, 47.898]])
    builder = TileBuilder(bbox=(lon_b - 0.01, 47.89, lon_b + 0.01, 47.91))
    for f in (track, path, bare):
        builder.add(f["properties"], f["geometry"])
    check(builder.ways == 2 and builder.skipped == 1, "ungraded ways are left out")
    tiles = builder.tiles()
    check(len(tiles) == 2 and not builder.buf, "the track lands in both tiles at the border; buffers released")
    decoded = {k: rm.decode_mvt_lines(gzip.decompress(v), LAYER) for k, v in tiles.items()}
    classes = {k: sorted((p[KEY], p.get(UPHILL_KEY)) for _, p, _ in fs) for k, fs in decoded.items()}
    check(sorted(classes.values()) == [[(3, None)], [(3, None), (6, 4)]],
          "one feature per class per tile, k as integer, u only where tagged")
    west, east = sorted(decoded)
    reach_w = max(px for _, _, ls in decoded[west] for line in ls for px, _ in line)
    reach_e = min(px for _, _, ls in decoded[east] for line in ls for px, _ in line)
    check(reach_w == EXTENT + BUFFER and reach_e == -BUFFER,
          "lines run exactly BUFFER units past the edge on both sides")

    # Several lines of one class in one tile share a feature; the cursor
    # carries over between parts (decoded positions are absolute).
    b2 = TileBuilder(bbox=(8.99, 47.89, 9.01, 47.91))
    b2._write(0, 0, (1, None), [(10, 10), (20, 10)])
    b2._write(0, 0, (1, None), [(30, 30), (40, 35)])
    b2.zoom = 0
    one = rm.decode_mvt_lines(gzip.decompress(b2.tiles()[(0, 0, 0)]), LAYER)
    check(len(one) == 1 and one[0][2] == [[(10, 10), (20, 10)], [(30, 30), (40, 35)]],
          "a class is one MultiLineString, cursor continues across parts")

    # Simplification before cutting: a wiggle below the tolerance goes.
    b3 = TileBuilder(simplify=1.5, bbox=(0, 0, 0.01, 0.01))
    b3.zoom = 0
    b3.range = (0, 0, 0, 0)
    b3.add_line((1, None), [(100, 100), (200, 101), (300, 100), (300, 400)])
    pts = rm.decode_mvt_lines(gzip.decompress(b3.tiles()[(0, 0, 0)]), LAYER)[0][2]
    check(pts == [[(100, 100), (300, 100), (300, 400)]], "sub-tolerance wiggle removed, corner kept")

    # Archive: header, metadata, check.
    with tempfile.TemporaryDirectory() as wd:
        bbox = (lon_b - 0.01, 47.89, lon_b + 0.01, 47.91)
        manifest = write_archive(tiles, bbox, "20261101", wd, ZOOM)
        check(manifest["file"] == "ways-20261101.pmtiles" and manifest["tiles"] == 2
              and manifest["format"] == FORMAT and manifest["zoom"] == ZOOM,
              "manifest names file, tiles, format, zoom")
        with open(os.path.join(wd, "ways.json"), encoding="utf-8") as h:
            check(json.load(h) == manifest, "ways.json is the manifest")
        report = check_archive(os.path.join(wd, manifest["file"]))
        check(report["tiles"] == 2 and report["classes"] == {3: 2, 6: 1},
              "check reads the archive back: tiles and classes")
        # A wrong class must not pass the check.
        bad = {(ZOOM, 0, 0): gzip.compress(encode_tile({(9, None): [bytearray(b"\x09\x00\x00\x0a\x02\x02")]}))}
        write_archive(bad, bbox, "bad", wd, ZOOM)
        try:
            check_archive(os.path.join(wd, "ways-bad.pmtiles"))
            check(False, "check rejects an unknown class")
        except ValueError as e:
            check("class 9" in str(e), "check rejects an unknown class")

    # The osmium runner, faked: two chained filters (AND), then export.
    calls = []

    def fake(cmd, check):
        calls.append(cmd)
        out = cmd[cmd.index("-o") + 1]
        if cmd[1] == "export":
            with open(out, "w", encoding="utf-8") as h:
                h.write("\x1e" + json.dumps(track) + "\n" + json.dumps(path) + "\n")
        else:
            open(out, "w").close()

    with tempfile.TemporaryDirectory() as wd:
        got = list(osmium_ways("x.osm.pbf", wd, runner=fake))
        left = sorted(os.listdir(wd))
    check(len(got) == 2 and [c[1] for c in calls] == ["tags-filter", "tags-filter", "export"],
          "osmium: highway filter, grade filter, export")
    check(calls[0][-1] == "w/highway=track,path,bridleway"
          and calls[1][-6:] == ["w/tracktype", "w/sac_scale", "w/mtb:scale", "w/mtb:scale:uphill",
                                "w/smoothness", "w/surface=mud"]
          and calls[1][-7] == calls[0][calls[0].index("-o") + 1],
          "osmium: the grade filter reads the highway filter's output")
    check(left == ["export.json"], "osmium: intermediate files removed")
    check(glue_bbox(["build", "--bbox", "-141.1,41.6,-52.5,83.2", "--out", "x"])
          == ["build", "--bbox=-141.1,41.6,-52.5,83.2", "--out", "x"],
          "a box west of Greenwich reaches argparse as a value (#220)")

    if not ok:
        sys.exit(1)
    print("self-test passed")


# ------------------------------------------------------------- main

def glue_bbox(argv):
    """`--bbox W,S,E,N` -> `--bbox=W,S,E,N`. argparse reads a value with a
    leading minus as an option, and every box west of Greenwich has one
    (Canada for #220); the workflows keep the plain spelling."""
    out = list(argv)
    for i in range(len(out) - 1):
        if out[i] == "--bbox":
            out[i:i + 2] = [f"--bbox={out[i + 1]}", None]
    return [a for a in out if a is not None]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--self-test", action="store_true")
    sub = parser.add_subparsers(dest="command")
    b = sub.add_parser("build", help="build ways-<build>.pmtiles and ways.json")
    b.add_argument("--pbf", action="append", required=True)
    b.add_argument("--build", required=True)
    b.add_argument("--out", required=True)
    b.add_argument("--bbox", default=",".join(str(v) for v in DACH_BBOX))
    b.add_argument("--zoom", type=int, default=ZOOM)
    b.add_argument("--simplify", type=float, default=SIMPLIFY)
    b.add_argument("--height-bytes", type=int, help="size of the height archive, for the comparison")
    b.add_argument("--summary")
    p = sub.add_parser("prefilter", help="keep only the graded ways of one extract")
    p.add_argument("pbf")
    p.add_argument("out")
    c = sub.add_parser("check", help="read an archive back the way the app does")
    c.add_argument("--source", required=True)
    c.add_argument("--samples", type=int, default=24)
    args = parser.parse_args(glue_bbox(sys.argv[1:] if argv is None else argv))

    if args.self_test:
        self_test()
        return
    if args.command == "build":
        started = time.time()
        bbox = tuple(float(v) for v in args.bbox.split(","))
        builder = TileBuilder(args.zoom, args.simplify, bbox)
        for pbf in args.pbf:
            t = time.time()
            with tempfile.TemporaryDirectory() as workdir:
                for f in osmium_ways(pbf, workdir):
                    builder.add(f.get("properties") or {}, f.get("geometry") or {})
            print(f"{os.path.basename(pbf)}: {builder.ways:,} ways so far, "
                  f"{len(builder.buf):,} tiles, {time.time() - t:.0f} s", flush=True)
        manifest = write_archive(builder.tiles(), bbox, args.build, args.out, args.zoom)
        md = summary_md(manifest, builder, time.time() - started, args.height_bytes)
        print(md)
        if args.summary:
            with open(args.summary, "a", encoding="utf-8") as h:
                h.write(md)
    elif args.command == "prefilter":
        with tempfile.TemporaryDirectory() as workdir:
            prefilter(args.pbf, args.out, workdir)
    elif args.command == "check":
        report = check_archive(args.source, args.samples, log=print)
        print(json.dumps(report, sort_keys=True))
    else:
        parser.print_help()
        sys.exit(2)


if __name__ == "__main__":
    main()
