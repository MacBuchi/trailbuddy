#!/usr/bin/env python3
"""Routing tiles (#380): sample the inputs the planner builds its graph from.

Today the phone builds the routing graph for every plan from tiles made
for drawing (map layer `roads`, the way archive, the height tiles;
docs/konzept-routing.md 2.7). Section 11 of that concept proposes to bake
the graph per z13 tile once, in a workflow, and to let the phone only
stitch. Before anything is built, the size per tile and the stitch time
are measured — this tool fetches the inputs for that measurement:

    python3 tool/routing_tiles.py sample --out DIR [--frame innsbruck] [--size 11]

For each frame it writes the z13 tiles of a size x size block around a
public town centre, exactly as the app reads them:

    DIR/<frame>/roads/<x>_<y>.mvt     map tile, decompressed (layer `roads`)
    DIR/<frame>/ways/<x>_<y>.mvt      way archive tile (gaps are normal)
    DIR/<frame>/heights/<x>_<y>.bin   height tile, decompressed
    DIR/<frame>/frame.json            tile numbers, sources, byte counts

All three archives are public and named by the manifests on the own host
(`dach.json`, `ways.json`, `heights.json`) — the same range requests an
area download makes, so no new network target. The measurement itself
is Dart, on the real graph code (`tool/routing_tiles_measure.dart`,
`TB_TILES_DIR=DIR`), so the baked format and the phone's builder can
never drift apart.

Frames are town centres, not rides: nothing private goes in (A7).
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import map_tiles  # noqa: E402  (tool/, same directory)

PUBLIC_BASE = "https://tiles.mcbuchi.de/trailbuddy"
USER_AGENT = "trailbuddy-routing-tiles/1 (+https://github.com/MacBuchi/trailbuddy)"
ZOOM = 13

# Public town centres, chosen for different terrain: an Alpine valley with
# steep slopes (Innsbruck), low mountains full of forest tracks (Freiburg),
# a dense Swiss lowland city (Zürich). Two decimals: a z13 tile is 3 km,
# and tool/private_info_check.py flags finer pairs.
FRAMES = {
    "innsbruck": (47.27, 11.40),
    "freiburg": (48.00, 7.84),
    "zuerich": (47.38, 8.54),
}


def tile_of(lat, lon, z=ZOOM):
    n = 1 << z
    x = int((lon + 180.0) / 360.0 * n)
    r = math.radians(lat)
    y = int((1.0 - math.asinh(math.tan(r)) / math.pi) / 2.0 * n)
    return x, y


def block(lat, lon, size):
    """The size x size z13 tiles around (lat, lon), row by row."""
    cx, cy = tile_of(lat, lon)
    lo = size // 2
    return [(x, y) for y in range(cy - lo, cy - lo + size) for x in range(cx - lo, cx - lo + size)]


def fetch_bytes(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=180) as r:
        return r.read()


def host_archive(manifest_name):
    manifest = json.loads(fetch_bytes(f"{PUBLIC_BASE}/{manifest_name}"))
    return manifest["file"], map_tiles.Archive(map_tiles.HttpSource(f"{PUBLIC_BASE}/{manifest['file']}"))


def tile_bytes(archive, x, y):
    entry = archive.find(map_tiles.zxy_to_tile_id(ZOOM, x, y))
    if entry is None:
        return None
    return map_tiles.decompress(archive.tile_bytes(entry), archive.header.tile_compression)


def sample(out, frames, size):
    archives = {
        "roads": host_archive("dach.json"),
        "ways": host_archive("ways.json"),
        "heights": host_archive("heights.json"),
    }
    for name in frames:
        lat, lon = FRAMES[name]
        tiles = block(lat, lon, size)
        base = os.path.join(out, name)
        stats = {}
        t0 = time.time()
        for kind, (_, archive) in archives.items():
            os.makedirs(os.path.join(base, kind), exist_ok=True)
            found = total = 0
            for x, y in tiles:
                path = os.path.join(base, kind, f"{x}_{y}.{'bin' if kind == 'heights' else 'mvt'}")
                if os.path.exists(path):
                    data = open(path, "rb").read()
                else:
                    data = tile_bytes(archive, x, y)
                    if data is None:
                        continue
                    with open(path, "wb") as fh:
                        fh.write(data)
                found += 1
                total += len(data)
            stats[kind] = {"tiles": found, "bytes": total}
        meta = {
            "frame": name,
            "zoom": ZOOM,
            "size": size,
            "tiles": [list(t) for t in tiles],
            "sources": {k: f for k, (f, _) in archives.items()},
            "stats": stats,
        }
        with open(os.path.join(base, "frame.json"), "w", encoding="utf-8") as fh:
            json.dump(meta, fh, indent=1)
        print(f"{name}: {len(tiles)} tiles, " + ", ".join(
            f"{k} {v['tiles']} / {v['bytes'] / 1e6:.1f} MB" for k, v in stats.items())
            + f" ({time.time() - t0:.0f} s)", file=sys.stderr)


def self_test():
    # Innsbruck lies in z13 tile 4355/2872 (same as map_tiles.bbox_tile_ids).
    assert tile_of(*FRAMES["innsbruck"]) == (4355, 2872), tile_of(*FRAMES["innsbruck"])
    b = block(*FRAMES["innsbruck"], 3)
    assert len(b) == 9 and b[0] == (4354, 2871) and b[-1] == (4356, 2873), b
    assert len(set(block(47.0, 11.0, 11))) == 121
    print("routing_tiles self-test ok")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", nargs="?", choices=["sample"])
    ap.add_argument("--out")
    ap.add_argument("--frame", action="append", choices=sorted(FRAMES))
    ap.add_argument("--size", type=int, default=11, help="tiles per side (11 x 11 = 121, the planner's limit)")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args(argv)
    if args.self_test:
        self_test()
        return 0
    if args.mode != "sample" or not args.out:
        ap.error("usage: sample --out DIR (or --self-test)")
    sample(args.out, args.frame or sorted(FRAMES), args.size)
    return 0


if __name__ == "__main__":
    sys.exit(main())
