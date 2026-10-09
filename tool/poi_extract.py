#!/usr/bin/env python3
"""Places on the map, served from our own host (#12, concept 3.4 way 3).

Turns OSM extracts (Geofabrik `.osm.pbf`) into the small files the app
reads from tiles.mcbuchi.de instead of asking Overpass live: one JSON
file per grid cell and group, plus a manifest that names the current
build and lists the cells that have anything in them (so the app never
asks for a file that does not exist).

Why a file per CELL AND GROUP: the app loads per group, exactly as it did
with Overpass — "Wasser" on and "Einkehr" off must not download the
city's restaurants. The cell is the app's own grid (0.1° x 0.15°,
`poiCellOf` in lib/features/map/poi.dart): same floor() on the same
doubles, so both sides name the same cell.

Why not the vector tiles: Protomaps writes huts, restaurants, drinking
water and the rest into tiles from zoom 15 only (measured in the
basemaps source on 2026-09-28), our archive ends at 13, and a z15
archive would be a multiple of the size for every stored area.

Kinds and their tag rules live in tool/pois/kinds.json — ONE list, read
here and held against `PoiKind` by test/map/poi_test.dart. The first
matching kind wins, so a restaurant with biergarten=yes is a Biergarten.

The heavy lifting (reading a 5 GB extract) is `osmium` (osmium-tool,
apt), the official reader; this file only classifies, places and
writes. Standard library only, deterministic output (sorted, ids as
keys), so two runs over the same extract give the same bytes.

The area is the MAP's area (#73): `--bbox` takes the same
west,south,east,north as the basemap archive and the bundled overview
(map-data.yml `DACH_BBOX`), and every place whose position lies outside
is dropped and counted. The extracts are whole countries (or Geofabrik
regions) and reach further than the map — without the cut, Paris would
be in the build because Alsace is on the map. A place just across the
edge is not a loss: the map shows nothing there either.

Every build also carries the whole region in ONE file (#229, concept
offline maps 8.6): `pois-<build>/bundle.tsv.gz`, a header line and one
`<name>\\t<content>` line per cell file, named in the manifest as
`bundle` with its size and sha256. A phone that stores the whole region
fetches that instead of thousands of cells.

Usage:
  python3 tool/poi_extract.py build --build 20260928 --out build/pois \
      [--bbox W,S,E,N] [--summary summary.md] a.osm.pbf [b.osm.pbf ...]
  python3 tool/poi_extract.py build --build 20260928 --out build/pois \
      --geojsonseq features.geojsonl        # skip osmium (fixtures, tests)
  python3 tool/poi_extract.py filter-expression   # what osmium is asked
  python3 tool/poi_extract.py --self-test
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
KINDS_FILE = os.path.join(HERE, "pois", "kinds.json")

# The app's grid (poi.dart: _cellLat, _cellLon). Change both or neither.
CELL_LAT = 0.1
CELL_LON = 0.15

# Manifest and file format version; the app refuses anything else.
FORMAT = 1

ATTRIBUTION = "© OpenStreetMap contributors (ODbL)"

# The whole region in one file (#229, concept-offline-karten 8.6): every
# cell file as one line `<name>\t<content>` after a header line, gzip with
# a fixed mtime so two runs give the same bytes. It lies INSIDE the dated
# prefix, so pruning a build takes it along, and its name can never be a
# cell file's (`<row>_<col>.<group>.json`). A line per file, not one JSON
# document: the phone splits it while it decompresses, without holding
# 165 MB of text (DACH) in memory at once.
BUNDLE_NAME = "bundle.tsv.gz"


# ------------------------------------------------------------------ kinds

def load_kinds(path=KINDS_FILE):
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    if data.get("format") != FORMAT:
        raise SystemExit(f"{path}: format {data.get('format')} != {FORMAT}")
    kinds = data["kinds"]
    groups = data["groups"]
    for k in kinds:
        if k["group"] not in groups:
            raise SystemExit(f"{path}: kind {k['kind']} in unknown group {k['group']}")
        if not k["rules"]:
            raise SystemExit(f"{path}: kind {k['kind']} without rules")
    return kinds, groups


def kind_of(tags, kinds):
    """The FIRST kind whose rules match — None if none does."""
    for k in kinds:
        excluded = k.get("exclude_access") or ()
        if tags.get("access") in excluded:
            continue
        for rule in k["rules"]:
            if all(tags.get(key) == value for key, value in rule.items()):
                return k
    return None


def filter_expression(kinds):
    """The `osmium tags-filter` selectors: the FIRST tag of every rule.

    Multi-tag rules (charging_station + bicycle=yes) are narrowed here in
    Python; osmium only has to let the candidates through. Access
    exclusions likewise. Deduplicated and sorted, so the command line is
    stable.
    """
    out = set()
    for k in kinds:
        for rule in k["rules"]:
            key, value = next(iter(rule.items()))
            out.add(f"nwr/{key}={value}")
    return sorted(out)


# --------------------------------------------------------------- geometry

def _coords(geometry):
    """Every (lon, lat) pair of a GeoJSON geometry, flattened."""
    kind = geometry.get("type")
    coords = geometry.get("coordinates")
    if kind == "Point":
        return [tuple(coords[:2])]
    if kind in ("LineString", "MultiPoint"):
        return [tuple(c[:2]) for c in coords]
    if kind in ("Polygon", "MultiLineString"):
        return [tuple(c[:2]) for ring in coords for c in ring]
    if kind == "MultiPolygon":
        return [tuple(c[:2]) for poly in coords for ring in poly for c in ring]
    return []


def center_of(geometry):
    """The centre of the bounding box — what Overpass `out center` gave,
    so a Biergarten's pin lands where it used to. None for empty/unknown."""
    pts = _coords(geometry)
    if not pts:
        return None
    lons = [p[0] for p in pts]
    lats = [p[1] for p in pts]
    return ((min(lats) + max(lats)) / 2, (min(lons) + max(lons)) / 2)


def parse_bbox(text):
    """`W,S,E,N` in degrees -> tuple, or SystemExit on anything else."""
    try:
        west, south, east, north = (float(v) for v in text.split(","))
    except ValueError:
        raise SystemExit(f"--bbox wants west,south,east,north, got {text!r}")
    if not (-180 <= west < east <= 180 and -90 <= south < north <= 90):
        raise SystemExit(f"--bbox {text!r} is not a west,south,east,north box")
    return west, south, east, north


def in_bbox(lat, lon, bbox):
    """Edges included: a place exactly on the map's edge is on the map."""
    if bbox is None:
        return True
    west, south, east, north = bbox
    return west <= lon <= east and south <= lat <= north


def cell_of(lat, lon):
    return f"{math.floor(lat / CELL_LAT)},{math.floor(lon / CELL_LON)}"


def cell_file(cell, group):
    """`<row>_<col>.<group>.json` — the comma of the cell key would be
    awkward in a URL; the app builds the same name (poiCellFileName)."""
    return f"{cell.replace(',', '_')}.{group}.json"


# ------------------------------------------------------------------- ids

def osm_id(unique_id):
    """osmium's `--add-unique-id=type_id` ids back to `node/1`, `way/2`,
    `relation/3` — the path on openstreetmap.org the sheet links to.

    Areas come as `a<n>`: an even n is a closed way (n/2), an odd n a
    multipolygon relation ((n-1)/2) — osmium's own encoding.
    """
    if not unique_id or len(unique_id) < 2:
        return None
    prefix, digits = unique_id[0], unique_id[1:]
    if not digits.isdigit():
        return None
    n = int(digits)
    if prefix == "n":
        return f"node/{n}"
    if prefix == "w":
        return f"way/{n}"
    if prefix == "r":
        return f"relation/{n}"
    if prefix == "a":
        return f"way/{n // 2}" if n % 2 == 0 else f"relation/{(n - 1) // 2}"
    return None


# --------------------------------------------------------------- reading

def read_geojsonseq(stream):
    """Features from a GeoJSON text sequence (RFC 8142: one feature per
    line, optionally led by the RS character 0x1e)."""
    for line in stream:
        line = line.strip().lstrip("\x1e").strip()
        if not line:
            continue
        feature = json.loads(line)
        if feature.get("type") == "Feature":
            yield feature


def unique_id_of(feature):
    """osmium writes the `--add-unique-id` as the GeoJSON Feature's own
    `id` member, NOT as a property — the first publish run dropped all
    2.7 million candidates because this read only `properties.id`
    (2026-09-28). Accept the feature member first, the two property
    spellings as fallbacks (a hand-made fixture, `--attributes=id`)."""
    props = feature.get("properties") or {}
    for value in (feature.get("id"), props.get("id"), props.get("@id")):
        if value is not None and str(value) != "":
            return str(value)
    return ""


def place_of(feature, kinds):
    """A feature to the record the app reads — or the reason it is not
    one: `"no_kind"`, `"no_position"`, `"no_id"`."""
    props = feature.get("properties") or {}
    tags = {str(k): str(v) for k, v in props.items() if k not in ("id", "@id")}
    kind = kind_of(tags, kinds)
    if kind is None:
        return "no_kind"
    center = center_of(feature.get("geometry") or {})
    if center is None:
        return "no_position"
    ident = osm_id(unique_id_of(feature))
    if ident is None:
        return "no_id"
    lat, lon = center
    record = {
        "id": ident,
        "kind": kind["kind"],
        "lat": round(lat, 6),
        "lng": round(lon, 6),
    }
    name = tags.get("name")
    if name:
        record["name"] = name
    hours = tags.get("opening_hours")
    if hours:
        record["hours"] = hours
    water = tags.get("drinking_water")
    if water in ("yes", "no"):
        record["water"] = water
    return kind["group"], record


# --------------------------------------------------------------- writing

def dump(obj):
    return json.dumps(obj, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":")) + "\n"


def build(features, kinds, groups, build_id, out_dir, sources=(), bbox=None):
    """Places -> files under out_dir/pois-<build>/ plus out_dir/pois.json.
    With [bbox], places outside it are dropped (`outside`). Returns the
    manifest."""
    if not (build_id.isdigit() and len(build_id) == 8):
        raise SystemExit(f"--build must be YYYYMMDD, got {build_id!r}")
    prefix = f"pois-{build_id}"
    by_file = {}   # (cell, group) -> {id: record}
    counts = {k["kind"]: 0 for k in kinds}
    dropped = {"no_kind": 0, "no_position": 0, "no_id": 0, "outside": 0}
    samples = []   # the first raw features, shown when nothing survives
    for feature in features:
        placed = place_of(feature, kinds)
        if isinstance(placed, str):
            dropped[placed] += 1
            if len(samples) < 3:
                samples.append(feature)
            continue
        group, record = placed
        if not in_bbox(record["lat"], record["lng"], bbox):
            dropped["outside"] += 1
            continue
        cell = cell_of(record["lat"], record["lng"])
        bucket = by_file.setdefault((cell, group), {})
        if record["id"] in bucket:
            continue   # the same object from two extracts (border areas)
        bucket[record["id"]] = record
        counts[record["kind"]] += 1

    target = os.path.join(out_dir, prefix)
    if os.path.isdir(target):
        shutil.rmtree(target)
    os.makedirs(target)
    cells = {g: [] for g in groups}
    total_bytes = 0
    bundle_lines = []
    for (cell, group), records in sorted(by_file.items()):
        payload = {
            "format": FORMAT,
            "build": build_id,
            "cell": cell,
            "group": group,
            "pois": [records[k] for k in sorted(records)],
        }
        text = dump(payload)
        with open(os.path.join(target, cell_file(cell, group)), "w",
                  encoding="utf-8") as handle:
            handle.write(text)
        total_bytes += len(text.encode("utf-8"))
        cells[group].append(cell)
        bundle_lines.append(f"{cell_file(cell, group)}\t{text}")
    bundle = write_bundle(os.path.join(target, BUNDLE_NAME), build_id, bundle_lines)
    manifest = {
        "format": FORMAT,
        "build": build_id,
        "prefix": prefix,
        "bundle": bundle,
        "attribution": ATTRIBUTION,
        "bbox": list(bbox) if bbox is not None else None,
        "sources": sorted(sources),
        "cells": cells,
        "counts": counts,
        "files": len(by_file),
        "bytes": total_bytes,
        "dropped": dropped,
    }
    if not by_file and samples:
        # Nothing survived: say what osmium actually delivered, so the
        # log explains the failure instead of just counting it.
        print("no place survived — the first raw features were:")
        for feature in samples:
            print(json.dumps(feature, ensure_ascii=False)[:600])
    with open(os.path.join(out_dir, "pois.json"), "w", encoding="utf-8") as handle:
        handle.write(json.dumps(manifest, ensure_ascii=False, sort_keys=True,
                                indent=1) + "\n")
    return manifest


def write_bundle(path, build_id, lines):
    """The cell files of a build as one gzip file (BUNDLE_NAME). Each
    content is one line already (`dump` is compact, JSON escapes every
    newline), so `name\\tcontent` per line is unambiguous. Returns what
    the manifest says about it — `file` relative to the prefix."""
    header = dump({"format": FORMAT, "build": build_id, "files": len(lines)})
    raw = (header + "".join(lines)).encode("utf-8")
    buffer = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=buffer, mtime=0,
                       compresslevel=9) as handle:
        handle.write(raw)
    data = buffer.getvalue()
    with open(path, "wb") as handle:
        handle.write(data)
    return {"file": BUNDLE_NAME, "files": len(lines), "bytes": len(data),
            "raw_bytes": len(raw), "sha256": hashlib.sha256(data).hexdigest()}


def read_bundle(path):
    """The bundle back as {name: content} — what the app does, here for
    the self-test and the workflow's check."""
    with gzip.open(path, "rt", encoding="utf-8", newline="\n") as handle:
        header = json.loads(handle.readline())
        files = {}
        for line in handle:
            name, _, content = line.partition("\t")
            files[name] = content
    if header.get("format") != FORMAT or header.get("files") != len(files):
        raise SystemExit(f"{path}: header {header} does not match {len(files)} files")
    return header, files


def summary_md(manifest, kinds):
    lines = [
        f"## Places built: `{manifest['prefix']}`",
        "",
        f"- {manifest['files']} files, {manifest['bytes'] / 1e6:.1f} MB, "
        f"{sum(manifest['counts'].values())} places; dropped: "
        f"{manifest['dropped']['no_kind']} without a kind of ours, "
        f"{manifest['dropped']['no_position']} without a position, "
        f"{manifest['dropped']['no_id']} without an id, "
        f"{manifest['dropped'].get('outside', 0)} outside the map",
        f"- bundle for a whole region: `{manifest['bundle']['file']}`, "
        f"{manifest['bundle']['bytes'] / 1e6:.1f} MB "
        f"({manifest['bundle']['raw_bytes'] / 1e6:.1f} MB unpacked)",
        f"- area: {','.join(str(v) for v in manifest['bbox']) if manifest.get('bbox') else 'unbounded'}",
        f"- sources: {', '.join(manifest['sources']) or '-'}",
        "",
        "| group | cells | kind | places |",
        "|---|---|---|---|",
    ]
    for k in kinds:
        lines.append(f"| {k['group']} | {len(manifest['cells'][k['group']])} "
                     f"| {k['kind']} | {manifest['counts'][k['kind']]} |")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------- osmium

def osmium_features(pbf_paths, kinds, workdir, runner=subprocess.run):
    """Filter each extract to the candidate objects and export them as
    GeoJSON features (points, and areas for closed ways/multipolygons —
    a Biergarten is usually an area). Yields features across all inputs."""
    expression = filter_expression(kinds)
    for index, pbf in enumerate(pbf_paths):
        filtered = os.path.join(workdir, f"filtered-{index}.osm.pbf")
        exported = os.path.join(workdir, f"features-{index}.geojsonl")
        # tags-filter keeps the nodes a matching way needs (default), so
        # export can build the area afterwards.
        runner(["osmium", "tags-filter", "--overwrite", "-o", filtered, pbf]
               + expression, check=True)
        runner(["osmium", "export", "--overwrite", "-f", "geojsonseq",
                "--add-unique-id=type_id", "-o", exported, filtered], check=True)
        with open(exported, encoding="utf-8") as handle:
            yield from read_geojsonseq(handle)
        os.remove(filtered)
        os.remove(exported)


# ------------------------------------------------------------- self-test

_FIXTURE = "\n".join([
    # A named spring, a node.
    '\x1e{"type":"Feature","id":"n1","properties":{"natural":"spring",'
    '"name":"Kalte Quelle","drinking_water":"no"},'
    '"geometry":{"type":"Point","coordinates":[9.01,47.51]}}',
    # A Biergarten as a closed way (area, even a-id) with opening hours;
    # the tag says restaurant, biergarten=yes wins.
    '{"type":"Feature","id":"a4","properties":{"amenity":"restaurant",'
    '"biergarten":"yes","opening_hours":"Mo-Su 11:00-22:00"},'
    '"geometry":{"type":"Polygon","coordinates":[[[9.02,47.52],[9.04,47.52],'
    '[9.04,47.54],[9.02,47.54],[9.02,47.52]]]}}',
    # A multipolygon relation (odd a-id): parking, public.
    '{"type":"Feature","id":"a7","properties":{"amenity":"parking"},'
    '"geometry":{"type":"MultiPolygon","coordinates":[[[[9.1,47.6],[9.2,47.6],'
    '[9.2,47.7],[9.1,47.7],[9.1,47.6]]]]}}',
    # Private parking: dropped.
    '{"type":"Feature","properties":{"id":"n8","amenity":"parking",'
    '"access":"private"},"geometry":{"type":"Point","coordinates":[9.11,47.61]}}',
    # A charging station without bicycle=yes: dropped; with: kept.
    '{"type":"Feature","properties":{"id":"n9","amenity":"charging_station"},'
    '"geometry":{"type":"Point","coordinates":[9.12,47.62]}}',
    '{"type":"Feature","id":"n10","properties":{"amenity":"charging_station",'
    '"bicycle":"yes"},"geometry":{"type":"Point","coordinates":[9.12,47.62]}}',
    # A bench: not one of ours.
    '{"type":"Feature","properties":{"id":"n11","amenity":"bench"},'
    '"geometry":{"type":"Point","coordinates":[9.13,47.63]}}',
    # A drinking water node in a different cell.
    '{"type":"Feature","properties":{"id":"n12","amenity":"drinking_water"},'
    '"geometry":{"type":"Point","coordinates":[11.3,47.2]}}',
    # A cafe without any id: dropped, counted as such.
    '{"type":"Feature","properties":{"amenity":"cafe"},'
    '"geometry":{"type":"Point","coordinates":[9.14,47.64]}}',
    # The spring again, as a second extract would deliver it: deduplicated.
    '{"type":"Feature","id":"n1","properties":{"natural":"spring",'
    '"name":"Kalte Quelle","drinking_water":"no"},'
    '"geometry":{"type":"Point","coordinates":[9.01,47.51]}}',
    "",
])


def self_test():
    kinds, groups = load_kinds()
    assert [k["kind"] for k in kinds][:2] == ["biergarten", "cafe"], "order is the rule"
    assert groups == ["food", "water", "bikeService", "other"]

    # Classification: first match wins, exclusions, multi-tag rules.
    assert kind_of({"amenity": "restaurant", "biergarten": "yes"}, kinds)["kind"] == "biergarten"
    assert kind_of({"amenity": "restaurant"}, kinds)["kind"] == "restaurant"
    assert kind_of({"amenity": "parking", "access": "private"}, kinds) is None
    assert kind_of({"amenity": "parking", "access": "customers"}, kinds)["kind"] == "parking"
    assert kind_of({"amenity": "charging_station"}, kinds) is None
    assert kind_of({"amenity": "charging_station", "bicycle": "yes"}, kinds)["kind"] == "eBikeCharging"
    assert kind_of({"highway": "track"}, kinds) is None

    # The osmium expression: one selector per first tag, no duplicates.
    expr = filter_expression(kinds)
    assert "nwr/amenity=charging_station" in expr and "nwr/bicycle=yes" not in expr
    assert "nwr/biergarten=yes" in expr and "nwr/amenity=parking" in expr
    assert len(expr) == len(set(expr)) and expr == sorted(expr)

    # Ids: osmium's area encoding back to OSM paths.
    assert osm_id("n1") == "node/1" and osm_id("w2") == "way/2"
    assert osm_id("r3") == "relation/3"
    assert osm_id("a4") == "way/2" and osm_id("a7") == "relation/3"
    assert osm_id("x1") is None and osm_id("n") is None and osm_id("nx") is None

    # Cells: the app's floor() on the same doubles.
    assert cell_of(47.55, 9.05) == "475,60"
    assert cell_of(-0.05, -0.1) == "-1,-1"
    assert cell_file("475,60", "water") == "475_60.water.json"

    # Centre: bbox centre, as Overpass `out center` gave it.
    assert center_of({"type": "Point", "coordinates": [9.0, 47.0]}) == (47.0, 9.0)
    c = center_of({"type": "Polygon", "coordinates": [[[9.0, 47.0], [9.2, 47.0], [9.2, 47.4], [9.0, 47.0]]]})
    assert abs(c[0] - 47.2) < 1e-9 and abs(c[1] - 9.1) < 1e-9
    assert center_of({"type": "Polygon", "coordinates": []}) is None

    with tempfile.TemporaryDirectory() as tmp:
        features = list(read_geojsonseq(io.StringIO(_FIXTURE)))
        assert len(features) == 10
        # The id: feature member (osmium), property (fixtures), or none.
        assert unique_id_of(features[0]) == "n1" and unique_id_of(features[7]) == "n12"
        assert unique_id_of(features[8]) == ""
        assert place_of(features[8], kinds) == "no_id"
        assert place_of(features[6], kinds) == "no_kind"
        manifest = build(features, kinds, groups, "20260928", tmp, ["dach"])
        prefix = os.path.join(tmp, "pois-20260928")
        names = sorted(os.listdir(prefix))
        assert names == ["472_75.water.json", "475_60.food.json",
                         "475_60.water.json", "476_60.bikeService.json",
                         "476_61.other.json", BUNDLE_NAME], names
        # The bundle holds every cell file, byte for byte, and nothing else.
        header, bundled = read_bundle(os.path.join(prefix, BUNDLE_NAME))
        assert header == {"format": 1, "build": "20260928", "files": 5}, header
        assert sorted(bundled) == names[:-1], sorted(bundled)
        for n, content in bundled.items():
            with open(os.path.join(prefix, n), encoding="utf-8") as h:
                assert content == h.read(), n
        with open(os.path.join(prefix, BUNDLE_NAME), "rb") as h:
            raw = h.read()
        assert manifest["bundle"] == {"file": BUNDLE_NAME, "files": 5, "bytes": len(raw),
                                      "raw_bytes": manifest["bundle"]["raw_bytes"],
                                      "sha256": hashlib.sha256(raw).hexdigest()}, manifest["bundle"]
        assert manifest["files"] == 5, "the bundle is not a cell file"
        # What the app reads, field for field.
        with open(os.path.join(prefix, "475_60.food.json"), encoding="utf-8") as h:
            food = json.load(h)
        assert food["format"] == 1 and food["cell"] == "475,60" and food["group"] == "food"
        assert food["pois"] == [{"id": "way/2", "kind": "biergarten", "lat": 47.53,
                                 "lng": 9.03, "hours": "Mo-Su 11:00-22:00"}], food
        with open(os.path.join(prefix, "475_60.water.json"), encoding="utf-8") as h:
            water = json.load(h)["pois"]
        assert water == [{"id": "node/1", "kind": "spring", "lat": 47.51, "lng": 9.01,
                          "name": "Kalte Quelle", "water": "no"}], water
        with open(os.path.join(prefix, "476_61.other.json"), encoding="utf-8") as h:
            other = json.load(h)["pois"]
        assert [p["id"] for p in other] == ["relation/3"], other
        with open(os.path.join(prefix, "476_60.bikeService.json"), encoding="utf-8") as h:
            bikes = json.load(h)["pois"]
        assert [p["id"] for p in bikes] == ["node/10"], bikes
        # The manifest: cells per group, counts, and the dropped ones.
        assert manifest["cells"] == {"food": ["475,60"], "water": ["472,75", "475,60"],
                                     "bikeService": ["476,60"], "other": ["476,61"]}, manifest["cells"]
        assert manifest["counts"]["parking"] == 1 and manifest["counts"]["spring"] == 1
        assert manifest["counts"]["eBikeCharging"] == 1
        assert manifest["dropped"] == {"no_kind": 3, "no_position": 0, "no_id": 1,
                                       "outside": 0}, manifest["dropped"]
        assert manifest["bbox"] is None
        assert manifest["files"] == 5 and manifest["prefix"] == "pois-20260928"
        with open(os.path.join(tmp, "pois.json"), encoding="utf-8") as h:
            assert json.load(h) == manifest
        # Deterministic: the same input gives the same bytes.
        first = {n: open(os.path.join(prefix, n), "rb").read() for n in names}
        build(list(read_geojsonseq(io.StringIO(_FIXTURE))), kinds, groups, "20260928", tmp, ["dach"])
        second = {n: open(os.path.join(prefix, n), "rb").read() for n in names}
        assert first == second
        md = summary_md(manifest, kinds)
        assert "| water | 2 | spring | 1 |" in md, md
        assert f"- bundle for a whole region: `{BUNDLE_NAME}`" in md, md

    # The map's area (#73): outside is dropped and counted, the edge
    # itself is inside. A box that ends at 11.0 E keeps everything at
    # 9.x E and loses the drinking water at 11.3 E.
    assert parse_bbox("5.5,45.5,17.5,55.5") == (5.5, 45.5, 17.5, 55.5)
    for bad in ("5.5,45.5,17.5", "17.5,45.5,5.5,55.5", "a,b,c,d"):
        try:
            parse_bbox(bad)
        except SystemExit:
            pass
        else:
            raise AssertionError(f"--bbox {bad!r} must be refused")
    assert in_bbox(45.5, 5.5, (5.5, 45.5, 17.5, 55.5)), "the edge is on the map"
    assert not in_bbox(45.49, 9.0, (5.5, 45.5, 17.5, 55.5))
    assert glue_bbox(["build", "--bbox", "-141.1,41.6,-52.5,83.2", "a.pbf"]) == \
        ["build", "--bbox=-141.1,41.6,-52.5,83.2", "a.pbf"], "a box west of Greenwich"
    with tempfile.TemporaryDirectory() as tmp:
        clipped = build(list(read_geojsonseq(io.StringIO(_FIXTURE))), kinds, groups,
                        "20260928", tmp, ["dach"], bbox=(5.5, 45.5, 11.0, 55.5))
        assert clipped["dropped"]["outside"] == 1, clipped["dropped"]
        assert clipped["cells"]["water"] == ["475,60"], clipped["cells"]
        assert clipped["bbox"] == [5.5, 45.5, 11.0, 55.5]
        assert "1 outside the map" in summary_md(clipped, kinds)

    # A bad build id never becomes a prefix (it turns into a path).
    try:
        build([], kinds, groups, "latest", tempfile.gettempdir())
    except SystemExit:
        pass
    else:
        raise AssertionError("build id must be YYYYMMDD")

    # The osmium runner is called per extract with the expression.
    calls = []

    def fake_runner(cmd, check):
        calls.append(cmd)
        if cmd[1] == "export":
            with open(cmd[cmd.index("-o") + 1], "w", encoding="utf-8") as h:
                h.write(_FIXTURE)
        else:
            open(cmd[cmd.index("-o") + 1], "w").close()
    with tempfile.TemporaryDirectory() as tmp:
        got = list(osmium_features(["a.osm.pbf", "b.osm.pbf"], kinds, tmp, runner=fake_runner))
    assert len(got) == 20 and len(calls) == 4
    assert calls[0][:2] == ["osmium", "tags-filter"] and calls[0][-len(expr):] == expr
    assert calls[1][:2] == ["osmium", "export"] and "--add-unique-id=type_id" in calls[1]
    print("poi_extract self-test: ok")


# ------------------------------------------------------------------ main

def glue_bbox(argv):
    """`--bbox W,S,E,N` -> `--bbox=W,S,E,N`. argparse reads a value with a
    leading minus as an option, and every box west of Greenwich has one
    (Canada for #220); the workflows keep the plain spelling."""
    out = list(argv)
    for i in range(len(out) - 1):
        if out[i] == "--bbox":
            out[i:i + 2] = [f"--bbox={out[i + 1]}", None]
    return [a for a in out if a is not None]


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--self-test", action="store_true")
    sub = parser.add_subparsers(dest="command")
    b = sub.add_parser("build", help="extracts -> cell files + manifest")
    b.add_argument("--build", required=True, help="YYYYMMDD, becomes the prefix")
    b.add_argument("--out", required=True)
    b.add_argument("--summary", help="write a Markdown summary here")
    b.add_argument("--bbox", help="west,south,east,north — the map's area; places outside are dropped")
    b.add_argument("--geojsonseq", help="read features from this file instead of running osmium")
    b.add_argument("pbf", nargs="*", help="Geofabrik .osm.pbf extracts")
    sub.add_parser("filter-expression", help="print the osmium tags-filter selectors")
    args = parser.parse_args(glue_bbox(sys.argv[1:]))

    if args.self_test:
        self_test()
        return
    kinds, groups = load_kinds()
    if args.command == "filter-expression":
        print(" ".join(filter_expression(kinds)))
        return
    if args.command != "build":
        parser.print_help()
        sys.exit(2)
    started = time.time()
    bbox = parse_bbox(args.bbox) if args.bbox else None
    if args.geojsonseq:
        with open(args.geojsonseq, encoding="utf-8") as handle:
            manifest = build(read_geojsonseq(handle), kinds, groups, args.build,
                             args.out, [os.path.basename(args.geojsonseq)], bbox=bbox)
    elif args.pbf:
        with tempfile.TemporaryDirectory() as workdir:
            manifest = build(osmium_features(args.pbf, kinds, workdir), kinds, groups,
                             args.build, args.out, [os.path.basename(p) for p in args.pbf],
                             bbox=bbox)
    else:
        raise SystemExit("build needs extracts or --geojsonseq")
    md = summary_md(manifest, kinds)
    print(md)
    print(f"built in {time.time() - started:.0f} s")
    if args.summary:
        with open(args.summary, "w", encoding="utf-8") as handle:
            handle.write(md)


if __name__ == "__main__":
    main()
