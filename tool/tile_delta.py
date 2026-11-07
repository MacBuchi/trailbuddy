#!/usr/bin/env python3
"""How many tiles really change between two builds? (#479, measure first)

After every new map build the app counts EVERY stored tile as stale and
„Aktualisieren" fetches all of them again. #479 asks whether a small
delta file per build (the ids whose bytes changed) would let the app
skip the unchanged ones. This tool answers it on two real archives
before anything is built:

    python3 tool/tile_delta.py compare --old <url|path> --new <url|path> \\
        --bbox 5.5,45.5,17.5,55.5 --maxzoom 13 [--samples 600] [--all] \\
        [--json out.json]
    python3 tool/tile_delta.py --self-test       # no network

Two passes, the cheap one first:

1. **Directories only** (a few MB over the network): every tile of the
   area in both builds, with its stored length. A tile that is new, gone
   or of a different length has changed for sure; a tile of the SAME
   length is only a candidate for "unchanged".
2. **Bytes of a sample** per zoom (or of every pair with `--all`, meant
   for two local files): raw bytes equal means unchanged; bytes different
   but the decompressed tile equal is counted on its own line — then the
   build is not byte-stable (e.g. a gzip header with a time), and a delta
   would have to compare content, not bytes.

Reported per zoom: tiles, share changed (exact for new/gone/length,
estimated for equal length), the share by tile size (thirds of the
stored length within the zoom — a dense town tile is large, forest and
field are small; a proxy, not a land-cover map), the bytes a refresh
would fetch with and without a delta, and the size of the delta itself
as sorted varint gaps, gzipped, against a per-tile hash list.

Reading the Protomaps daily builds directly costs no R2 read: the
extract on R2 carries the source's bytes (`map_tiles.py check` proves
that on every publish). The report names zooms, counts and sizes, never
a coordinate (CLAUDE.md: nothing private, and the bbox is the public
region box).

Stdlib only, reader from tool/map_tiles.py.
"""
from __future__ import annotations

import argparse
import bisect
import gzip
import hashlib
import json
import os
import random
import sys
import threading
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import map_tiles as mt  # noqa: E402


# ---------------------------------------------------------------------------
# Pass 1: the directories.
# ---------------------------------------------------------------------------


def area_ranges(args, minzoom, maxzoom):
    """{zoom: sorted inclusive id ranges} for --bbox or --region."""
    if (args.bbox is None) == (args.region is None):
        raise SystemExit("compare wants exactly one of --bbox and --region")
    if args.bbox is not None:
        wanted = mt.bbox_tile_ids(mt.parse_bbox(args.bbox), minzoom, maxzoom)
        return {z: mt.ranges_of(ids) for z, ids in wanted.items()}
    with open(args.region) as handle:
        geojson = json.load(handle)
    select = mt.parse_select(args.select) if args.select else None
    per_zoom, _ = mt.region_ranges(mt.region_rings(geojson, select),
                                   minzoom, maxzoom)
    return per_zoom


def index_area(archive, per_zoom):
    """{tile_id: (offset, length)} for every tile of the area.

    Runs are expanded, but only inside the wanted ranges: a planet build
    holds runs of millions of ocean tiles, the area a few hundred
    thousand ids at most.
    """
    ranges = [r for z in sorted(per_zoom) for r in per_zoom[z]]
    starts = [r[0] for r in ranges]
    found = {}
    for entry in archive.walk(ranges):
        low = entry.tile_id
        high = entry.tile_id + entry.run_length - 1
        index = max(0, bisect.bisect_right(starts, low) - 1)
        while index < len(ranges) and ranges[index][0] <= high:
            start, end = ranges[index]
            for tile_id in range(max(start, low), min(end, high) + 1):
                found[tile_id] = (entry.offset, entry.length)
            index += 1
    return found


def zoom_of(tile_id, bases):
    return bisect.bisect_right(bases, tile_id) - 1


# ---------------------------------------------------------------------------
# Pass 2: the bytes.
# ---------------------------------------------------------------------------


class Reader:
    """Tile bytes of one archive, one source per worker thread.

    `LocalSource` shares a file handle, and urllib is happier without a
    shared counter; a source per thread avoids both.
    """

    def __init__(self, spec, header):
        self.spec = spec
        self.header = header
        self._local = threading.local()
        self.requests = 0
        self.bytes_read = 0
        self._lock = threading.Lock()

    def read(self, offset, length):
        source = getattr(self._local, "source", None)
        if source is None:
            source = self._local.source = mt.open_source(self.spec)
        data = source.read(self.header.tile_data_offset + offset, length)
        with self._lock:
            self.requests += 1
            self.bytes_read += length
        return data


def tile_content(data, compression):
    try:
        return mt.decompress(data, compression)
    except Exception:  # noqa: BLE001 - an unreadable tile is "changed"
        return None


def compare_pair(old_reader, new_reader, old_loc, new_loc):
    """'same', 'content' (bytes differ, decompressed equal) or 'changed'."""
    old = old_reader.read(*old_loc)
    new = new_reader.read(*new_loc)
    if old == new:
        return "same"
    a = tile_content(old, old_reader.header.tile_compression)
    b = tile_content(new, new_reader.header.tile_compression)
    if a is not None and a == b:
        return "content"
    return "changed"


# ---------------------------------------------------------------------------
# The delta file.
# ---------------------------------------------------------------------------


def delta_bytes(ids):
    """Sorted ids as varint gaps, gzip -9: the id-list form of #479."""
    out = bytearray()
    previous = 0
    for tile_id in sorted(ids):
        mt.write_varint(out, tile_id - previous)
        previous = tile_id
    return len(gzip.compress(bytes(out), 9, mtime=0)), len(out)


def hash_list_bytes(count, width=8):
    """Per-tile hash list: id gaps plus a truncated hash, gzipped.

    A hash does not compress; the ids do. Estimated, not built: the
    alternative only needs its size to be compared.
    """
    return count * width


# ---------------------------------------------------------------------------
# The comparison.
# ---------------------------------------------------------------------------


def size_third(length, cuts):
    if length <= cuts[0]:
        return 0
    if length <= cuts[1]:
        return 1
    return 2


def compare(old_spec, new_spec, per_zoom, samples, take_all, workers, seed,
            open_archive=None):
    """The whole measurement as data; printing is separate (and tested)."""
    open_archive = open_archive or (lambda spec: mt.Archive(mt.open_source(spec)))
    old_archive = open_archive(old_spec)
    new_archive = open_archive(new_spec)
    old_index = index_area(old_archive, per_zoom)
    new_index = index_area(new_archive, per_zoom)
    directory_cost = (old_archive.source.bytes_read
                      + new_archive.source.bytes_read)
    zooms = sorted(per_zoom)
    bases = [mt.zoom_base(z) for z in range(0, zooms[-1] + 2)]
    rng = random.Random(seed)

    old_reader = getattr(old_archive, "reader", None) or Reader(
        old_spec, old_archive.header)
    new_reader = getattr(new_archive, "reader", None) or Reader(
        new_spec, new_archive.header)

    report = {"zooms": [], "directory_bytes": directory_cost}
    exact_changed = set()     # new, or of another length: changed for sure
    gone = set()
    sampled_changed = set()
    estimated_changed_total = 0.0
    content_only_total = 0.0
    bytes_full = 0            # a refresh without delta: every new tile
    bytes_delta = 0.0         # with a delta: only the changed ones
    jobs = []                 # (zoom, kind, third, old_loc, new_loc, id)
    rows = {}

    for z in zooms:
        ids_old = {i for i in old_index if zoom_of(i, bases) == z}
        ids_new = {i for i in new_index if zoom_of(i, bases) == z}
        both = ids_old & ids_new
        added = ids_new - ids_old
        removed = ids_old - ids_new
        same_len = [i for i in both if old_index[i][1] == new_index[i][1]]
        diff_len = [i for i in both if old_index[i][1] != new_index[i][1]]
        lengths = sorted(new_index[i][1] for i in both) or [0]
        cuts = (lengths[len(lengths) // 3], lengths[(2 * len(lengths)) // 3])
        thirds = [{"tiles": 0, "diff_len": 0, "same_len": 0} for _ in range(3)]
        for i in both:
            t = thirds[size_third(new_index[i][1], cuts)]
            t["tiles"] += 1
            t["diff_len" if old_index[i][1] != new_index[i][1] else "same_len"] += 1
        rows[z] = {
            "zoom": z, "tiles_old": len(ids_old), "tiles_new": len(ids_new),
            "added": len(added), "removed": len(removed),
            "same_len": len(same_len), "diff_len": len(diff_len),
            "cuts": list(cuts), "thirds": thirds,
            "sample_same": {"n": 0, "same": 0, "content": 0, "changed": 0},
            "sample_diff": {"n": 0, "same": 0, "content": 0, "changed": 0},
            "third_sample": [{"n": 0, "changed": 0} for _ in range(3)],
            "bytes_new": 0, "bytes_same_len": 0, "bytes_diff_len": 0,
            "bytes_added": 0,
        }
        exact_changed |= added | set(diff_len)
        gone |= removed
        seen = set()
        for i in ids_new:
            loc = new_index[i]
            if loc[0] in seen:
                continue  # stored once, fetched once
            seen.add(loc[0])
            rows[z]["bytes_new"] += loc[1]
            key = ("bytes_added" if i in added else
                   "bytes_same_len" if i in both and old_index[i][1] == loc[1]
                   else "bytes_diff_len")
            rows[z][key] += loc[1]
        pick_same = same_len if take_all else rng.sample(
            same_len, min(samples, len(same_len)))
        pick_diff = diff_len if take_all else rng.sample(
            diff_len, min(max(1, samples // 5), len(diff_len)))
        for i in pick_same:
            jobs.append((z, "sample_same", size_third(new_index[i][1], cuts),
                         old_index[i], new_index[i], i))
        for i in pick_diff:
            jobs.append((z, "sample_diff", size_third(new_index[i][1], cuts),
                         old_index[i], new_index[i], i))

    # Shared contents (ocean, forest fill) are compared once.
    cache = {}
    lock = threading.Lock()

    def run(job):
        _, _, _, old_loc, new_loc, _ = job
        key = (old_loc, new_loc)
        with lock:
            if key in cache:
                return cache[key]
        verdict = compare_pair(old_reader, new_reader, old_loc, new_loc)
        with lock:
            cache[key] = verdict
        return verdict

    with ThreadPoolExecutor(max_workers=max(1, workers)) as pool:
        verdicts = list(pool.map(run, jobs))

    for job, verdict in zip(jobs, verdicts):
        z, kind, third, _, _, tile_id = job
        bucket = rows[z][kind]
        bucket["n"] += 1
        bucket[verdict] += 1
        if kind == "sample_same":
            rows[z]["third_sample"][third]["n"] += 1
            if verdict != "same":
                rows[z]["third_sample"][third]["changed"] += 1
            if verdict == "changed":
                sampled_changed.add(tile_id)

    for z in zooms:
        row = rows[z]
        s, d = row["sample_same"], row["sample_diff"]
        rate_same = (s["changed"] / s["n"]) if s["n"] else 0.0
        rate_same_content = (s["content"] / s["n"]) if s["n"] else 0.0
        rate_diff_content = (d["content"] / d["n"]) if d["n"] else 0.0
        changed = (row["added"] + row["diff_len"] * (1 - rate_diff_content)
                   + row["same_len"] * rate_same)
        content_only = (row["same_len"] * rate_same_content
                        + row["diff_len"] * rate_diff_content)
        row["changed_estimate"] = changed
        row["content_only_estimate"] = content_only
        row["changed_share"] = changed / row["tiles_new"] if row["tiles_new"] else 0.0
        # Bytes a refresh with a delta fetches: new tiles, changed ones,
        # and (if the build is not byte-stable) the content-only ones too
        # unless the delta compares content.
        fetch = (row["bytes_added"]
                 + row["bytes_diff_len"] * (1 - rate_diff_content)
                 + row["bytes_same_len"] * rate_same)
        row["bytes_delta"] = fetch
        bytes_full += row["bytes_new"]
        bytes_delta += fetch
        estimated_changed_total += changed
        content_only_total += content_only
        report["zooms"].append(row)

    tiles_new = len(new_index)
    # The id list as it would be written: every changed id. The exact part
    # is known; for the equal-length part only the sample is, so the list
    # is scaled by the estimated count (gap sizes grow, the byte count per
    # id barely does — stated as an estimate).
    exact_gz, exact_raw = delta_bytes(exact_changed | gone)
    known = len(exact_changed | gone)
    per_id = exact_gz / known if known else 0.0
    report.update({
        "tiles_old": len(old_index), "tiles_new": tiles_new,
        "changed_exact": len(exact_changed), "gone": len(gone),
        "changed_estimate": estimated_changed_total,
        "content_only_estimate": content_only_total,
        "bytes_full": bytes_full, "bytes_delta": bytes_delta,
        "delta_exact_gz": exact_gz, "delta_exact_raw": exact_raw,
        "delta_estimate_gz": per_id * (estimated_changed_total + len(gone)),
        "hash_list_bytes": hash_list_bytes(tiles_new),
        "pairs_read": len(cache),
        "tile_bytes_read": old_reader.bytes_read + new_reader.bytes_read,
        "tile_requests": old_reader.requests + new_reader.requests,
        "sampled": not take_all,
    })
    old_archive.close()
    new_archive.close()
    return report


def pct(value):
    return f"{100 * value:.1f} %"


def render(report, old_name, new_name):
    lines = [
        f"## Tile delta `{old_name}` → `{new_name}`",
        "",
        ("Sample of equal-length pairs per zoom; new/gone/other length are "
         "exact." if report["sampled"] else "Every pair compared."),
        "",
        "| zoom | tiles | new | gone | other length | equal length: changed (sample) | bytes differ, content equal | changed (est.) | changed by size third (small / mid / large) |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for row in report["zooms"]:
        s = row["sample_same"]
        thirds = []
        for t, ts in zip(row["thirds"], row["third_sample"]):
            if not t["tiles"]:
                thirds.append("–")
                continue
            rate = ts["changed"] / ts["n"] if ts["n"] else 0.0
            thirds.append(pct((t["diff_len"] + t["same_len"] * rate) / t["tiles"]))
        content = s["content"] + row["sample_diff"]["content"]
        lines.append(
            f"| z{row['zoom']} | {row['tiles_new']} | {row['added']} | "
            f"{row['removed']} | {row['diff_len']} | "
            f"{s['changed']}/{s['n']} | {content} | "
            f"{pct(row['changed_share'])} | {' / '.join(thirds)} |")
    full, delta = report["bytes_full"], report["bytes_delta"]
    lines += [
        "",
        f"- tiles: {report['tiles_old']} → {report['tiles_new']}; changed "
        f"exactly (new or other length) {report['changed_exact']}, gone "
        f"{report['gone']}, changed in total (est.) "
        f"{report['changed_estimate']:.0f} "
        f"({pct(report['changed_estimate'] / max(1, report['tiles_new']))})",
        f"- bytes differ but content equal (est.): "
        f"{report['content_only_estimate']:.0f}",
        f"- refresh without delta: {mt.human(full)}; with delta (est.): "
        f"{mt.human(int(delta))} ({pct(delta / full if full else 0)})",
        f"- delta as id list (varint gaps, gzip): exact part "
        f"{mt.human(report['delta_exact_gz'])} (raw "
        f"{mt.human(report['delta_exact_raw'])}), whole list est. "
        f"{mt.human(int(report['delta_estimate_gz']))}; a per-tile hash list "
        f"would be ≥ {mt.human(report['hash_list_bytes'])}",
        f"- cost: directories {mt.human(report['directory_bytes'])}, "
        f"{report['pairs_read']} pairs = {mt.human(report['tile_bytes_read'])} "
        f"in {report['tile_requests']} requests",
    ]
    return "\n".join(lines) + "\n"


def command_compare(args):
    minzoom, maxzoom = args.minzoom, args.maxzoom
    per_zoom = area_ranges(args, minzoom, maxzoom)
    report = compare(args.old, args.new, per_zoom, args.samples, args.all,
                     args.workers, args.seed)
    text = render(report, os.path.basename(args.old), os.path.basename(args.new))
    print(text)
    if args.json:
        with open(args.json, "w") as handle:
            json.dump(report, handle, indent=1)
    return 0


# ---------------------------------------------------------------------------
# Self-test: two fixture archives with a known delta.
# ---------------------------------------------------------------------------


class _MemArchive(mt.Archive):
    def __init__(self, data):
        super().__init__(mt._BytesSource(data))
        archive = self

        class _R:
            header = archive.header
            requests = 0
            bytes_read = 0

            def read(self, offset, length):
                self.requests += 1
                self.bytes_read += length
                return data[archive.header.tile_data_offset + offset:
                            archive.header.tile_data_offset + offset + length]

        self.reader = _R()


def _fixture():
    old, new = {}, {}
    for z in range(0, 5):
        n = 1 << z
        for x in range(n):
            for y in range(n):
                body = f"tile {z}/{x}/{y}".encode()
                old[(z, x, y)] = gzip.compress(body, mtime=0)
                new[(z, x, y)] = gzip.compress(body, mtime=0)
    # z4: one changed with a new length, one changed with the same length,
    # one only re-gzipped (content equal), one gone, one new.
    new[(4, 1, 1)] = gzip.compress(b"tile 4/1/1 with a new path", mtime=0)
    new[(4, 2, 2)] = gzip.compress(b"tile 4/2/X", mtime=0)
    assert len(new[(4, 2, 2)]) == len(old[(4, 2, 2)])
    new[(4, 3, 3)] = gzip.compress(b"tile 4/3/3", mtime=12345)
    del new[(4, 5, 5)]
    old.pop((4, 6, 6))
    return old, new


def self_test():
    old_tiles, new_tiles = _fixture()
    blobs = {
        "old": mt._build_archive(old_tiles, tile_compression=mt.COMPRESSION_GZIP),
        "new": mt._build_archive(new_tiles, tile_compression=mt.COMPRESSION_GZIP),
    }
    per_zoom = {z: [(mt.zoom_base(z), mt.zoom_base(z + 1) - 1)]
                for z in range(0, 5)}
    report = compare("old", "new", per_zoom, samples=10_000, take_all=True,
                     workers=2, seed=1,
                     open_archive=lambda spec: _MemArchive(blobs[spec]))
    z4 = report["zooms"][4]
    assert z4["tiles_new"] == 255 and z4["tiles_old"] == 255, z4
    assert z4["added"] == 1 and z4["removed"] == 1, z4
    assert z4["diff_len"] == 1, z4
    s = z4["sample_same"]
    # 4/2/2 changed at equal length; 4/3/3 only re-gzipped.
    assert s["changed"] == 1 and s["content"] == 1, s
    assert abs(z4["changed_estimate"] - 3) < 1e-9, z4
    for row in report["zooms"][:4]:
        assert row["changed_estimate"] == 0, row
    assert report["changed_exact"] == 2 and report["gone"] == 1, report
    # Gegenprobe: the same archive against itself has no delta at all.
    same = compare("old", "old", per_zoom, samples=10_000, take_all=True,
                   workers=1, seed=1,
                   open_archive=lambda spec: _MemArchive(blobs[spec]))
    assert same["changed_estimate"] == 0 and same["bytes_delta"] == 0, same
    assert same["content_only_estimate"] == 0, same
    # A delta id list of gaps stays small and is deterministic.
    gz, raw = delta_bytes({10, 11, 12, 1000})
    # 10, 1, 1, 988 — the last gap takes two varint bytes.
    assert raw == 5 and gz == delta_bytes({1000, 12, 11, 10})[0]
    text = render(report, "old", "new")
    assert "| z4 | 255 | 1 | 1 | 1 | 1/" in text, text
    print("tile_delta self-test: ok")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--self-test", action="store_true")
    sub = parser.add_subparsers(dest="command")
    c = sub.add_parser("compare", help="tile delta between two builds")
    c.add_argument("--old", required=True)
    c.add_argument("--new", required=True)
    c.add_argument("--bbox")
    c.add_argument("--region")
    c.add_argument("--select")
    c.add_argument("--minzoom", type=int, default=0)
    c.add_argument("--maxzoom", type=int, default=13)
    c.add_argument("--samples", type=int, default=600,
                   help="equal-length pairs read per zoom")
    c.add_argument("--all", action="store_true",
                   help="read every pair (two local files)")
    c.add_argument("--workers", type=int, default=16)
    c.add_argument("--seed", type=int, default=479)
    c.add_argument("--json")
    args = parser.parse_args(argv)
    if args.self_test:
        self_test()
        return 0
    if args.command == "compare":
        return command_compare(args)
    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
