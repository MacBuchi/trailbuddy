#!/usr/bin/env python3
"""Reads PMTiles v3 archives: header, per-zoom size plan, extract check.

Copied from PilzBuddy (#496 there), where it answered **how many bytes is
a given area up to a given zoom?** — the number that decided against
raw.githubusercontent.com and its 100 MB per file. TrailBuddy's host is
Cloudflare R2 (`docs/konzept-offline-karten.md`, section 7), which has no
such limit, so `plan` here is a cost estimate rather than a verdict (pass
`--max-bytes` to move the bar). What matters for TrailBuddy is `check`:
after `map-data.yml` uploads an extract, it proves that the PUBLIC copy on
tiles.mcbuchi.de serves the source's bytes over Range requests — the same
path the app takes.

It deliberately does NOT write production archives. Cutting an extract is
`pmtiles extract`, the official Go tool, which is what CLAUDE.md already
names for the bundled DACH overview. A hand-rolled writer would be a
second implementation of a format we do not own, and a subtly malformed
archive fails in the browser, not here. What this tool adds is the part
`pmtiles` has no mode for: measuring before downloading, and proving
afterwards that an extract really carries the source's bytes.

Stdlib only, same reason as tool/rain_grid.py and tool/feedback_bot.py:
this runs in CI, and a pipeline that pip-installs a PMTiles library to
read a header is a pipeline that breaks on a Tuesday. Reading the format
takes `struct`, `gzip` and a varint loop.

Usage:
    python3 tool/map_tiles.py info    --source <url|path>
    python3 tool/map_tiles.py plan    --source <url|path> \\
                                      --bbox 5.5,45.5,17.5,55.5 --maxzoom 12
    python3 tool/map_tiles.py plan    --source <url|path> \\
                                      --region countries.geojson --select ISO_A2_EH=CA \\
                                      --maxzoom 13
    python3 tool/map_tiles.py check   --source <url|path> --extract out.pmtiles
    python3 tool/map_tiles.py --self-test        # no network

THE TRAP THIS TOOL EXISTS FOR: tile bytes per zoom do not grow by 4x, they
grow by whatever the data density does. Measured on the bundled DACH
overview (2026-09-21), z6 -> z7 was **6.4x**, and z7 alone was 77 % of the
file. Extrapolating "one more zoom, four times the bytes" understates the
top level badly, and the top level is the whole cost. Measure, never
estimate.
"""
import argparse
import bisect
import contextlib
import gzip
import hashlib
import http.client
import io
import json
import math
import os
import random
import struct
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request

# PMTiles v3 header: 127 bytes, little endian, no padding.
HEADER_FMT = "<7sB" + "Q" * 11 + "B" * 6 + "iiii" + "B" + "ii"
HEADER_LEN = 127
assert struct.calcsize(HEADER_FMT) == HEADER_LEN

COMPRESSION_NONE = 1
COMPRESSION_GZIP = 2
COMPRESSION_NAMES = {0: "unknown", 1: "none", 2: "gzip", 3: "brotli", 4: "zstd"}
TILE_TYPE_NAMES = {0: "unknown", 1: "mvt", 2: "png", 3: "jpeg", 4: "webp", 5: "avif"}

# raw.githubusercontent.com refuses to serve what git refuses to store.
# Not a soft limit: a push of a bigger blob is rejected outright.
RAW_FILE_LIMIT = 100 * 1024 * 1024


# ---------------------------------------------------------------------------
# Sources: a local file and an HTTP server that honours Range.
# ---------------------------------------------------------------------------


class LocalSource:
    """A PMTiles archive on disk."""

    def __init__(self, path):
        self.name = path
        self._fh = open(path, "rb")
        self.requests = 0
        self.bytes_read = 0

    def read(self, offset, length):
        self.requests += 1
        self.bytes_read += length
        self._fh.seek(offset)
        data = self._fh.read(length)
        if len(data) != length:
            raise IOError(
                f"{self.name}: wanted {length} bytes at {offset}, got {len(data)}"
            )
        return data

    def close(self):
        self._fh.close()


class HttpSource:
    """A PMTiles archive behind a server that answers Range requests.

    A server that ignores `Range` answers 200 with the WHOLE file, and on a
    planet build that is a hundred gigabytes arriving through a pipe nobody
    asked to fill. So a 200 is treated as a hard error, not as something to
    slice locally: the point of this class is that the bytes never travel.
    """

    ATTEMPTS = 5
    BACKOFF = 2.0

    def __init__(self, url):
        self.name = url
        self.url = url
        self.requests = 0
        self.bytes_read = 0

    def read(self, offset, length):
        if length <= 0:
            return b""
        end = offset + length - 1
        request = urllib.request.Request(
            self.url,
            headers={
                "Range": f"bytes={offset}-{end}",
                # GitHub and most CDNs answer differently, or not at all,
                # without one.
                "User-Agent": "trailbuddy-map-tiles/1.0",
            },
        )
        for attempt in range(self.ATTEMPTS):
            try:
                with urllib.request.urlopen(request, timeout=120) as response:
                    status = response.status
                    data = response.read() if status == 206 else b""
                break
            except urllib.error.HTTPError as error:
                # A 4xx is an answer, not a hiccup: asking again gets the
                # same one.
                if error.code < 500 or attempt + 1 == self.ATTEMPTS:
                    raise
            except (urllib.error.URLError, ConnectionError, TimeoutError,
                    http.client.IncompleteRead):
                # Walking a planet build's directories up to z13 is ~300
                # sequential reads; a single dropped TLS session must not
                # throw away the other 299 (measured for #220, 2026-10-08).
                if attempt + 1 == self.ATTEMPTS:
                    raise
            time.sleep(self.BACKOFF * (2 ** attempt))
        if status != 206:
            # Outside the retry: a server that ignores Range ignores it
            # every time.
            raise IOError(
                f"{self.url}: Range request answered {status}, "
                "not 206 — this host cannot serve partial reads, and "
                "fetching the whole archive is not an option here"
            )
        if len(data) != length:
            raise IOError(
                f"{self.url}: wanted {length} bytes at {offset}, got {len(data)}"
            )
        self.requests += 1
        self.bytes_read += len(data)
        return data

    def close(self):
        pass


def open_source(spec):
    if spec.startswith("http://") or spec.startswith("https://"):
        return HttpSource(spec)
    return LocalSource(spec)


# ---------------------------------------------------------------------------
# Varints and directories.
# ---------------------------------------------------------------------------


def read_varint(buf, pos):
    """Returns (value, new position). LEB128, as the spec uses."""
    result = 0
    shift = 0
    while True:
        if pos >= len(buf):
            raise ValueError("varint runs past the end of the directory")
        byte = buf[pos]
        pos += 1
        result |= (byte & 0x7F) << shift
        if byte < 0x80:
            return result, pos
        shift += 7
        if shift > 63:
            raise ValueError("varint wider than 64 bit")


def write_varint(out, value):
    if value < 0:
        raise ValueError("varints are unsigned")
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return


class Entry:
    """One directory entry.

    `run_length == 0` does not mean an empty run — it means this entry
    points at a LEAF directory instead of at tile bytes. Reading it as a
    tile yields a tile made of directory bytes, which decodes to nothing
    and reports no error. Every walk below checks it first.
    """

    __slots__ = ("tile_id", "run_length", "offset", "length")

    def __init__(self, tile_id, run_length, offset, length):
        self.tile_id = tile_id
        self.run_length = run_length
        self.offset = offset
        self.length = length

    def __repr__(self):  # pragma: no cover - debugging aid
        return (
            f"Entry(id={self.tile_id}, run={self.run_length}, "
            f"off={self.offset}, len={self.length})"
        )

    def __eq__(self, other):
        return (
            self.tile_id == other.tile_id
            and self.run_length == other.run_length
            and self.offset == other.offset
            and self.length == other.length
        )


def decompress(data, compression):
    if compression == COMPRESSION_NONE:
        return data
    if compression == COMPRESSION_GZIP:
        return gzip.decompress(data)
    raise ValueError(
        f"internal compression {COMPRESSION_NAMES.get(compression, compression)} "
        "is not supported — stdlib has no brotli and no zstd, and guessing "
        "the bytes is worse than stopping here"
    )


def compress(data, compression):
    if compression == COMPRESSION_NONE:
        return data
    if compression == COMPRESSION_GZIP:
        # mtime=0: the same directory must serialise to the same bytes, or
        # a checksum over an archive means nothing.
        return gzip.compress(data, mtime=0)
    raise ValueError(f"cannot write compression {compression}")


def deserialize_directory(buf):
    """Decodes an uncompressed directory blob into entries."""
    pos = 0
    count, pos = read_varint(buf, pos)
    entries = [Entry(0, 0, 0, 0) for _ in range(count)]

    last_id = 0
    for i in range(count):
        delta, pos = read_varint(buf, pos)
        last_id += delta
        entries[i].tile_id = last_id
    for i in range(count):
        entries[i].run_length, pos = read_varint(buf, pos)
    for i in range(count):
        entries[i].length, pos = read_varint(buf, pos)
    for i in range(count):
        value, pos = read_varint(buf, pos)
        if value == 0 and i > 0:
            # Zero means "directly behind the previous one". The `i > 0` is
            # not reachable with a conforming archive — offsets are stored
            # as offset+1, so the first entry can never encode 0 — but it
            # mirrors the reference implementation, and without it a
            # malformed directory would take its first offset from
            # entries[-1], i.e. the LAST entry. Wrapping around silently is
            # exactly the kind of answer this tool must never give.
            entries[i].offset = entries[i - 1].offset + entries[i - 1].length
        else:
            entries[i].offset = value - 1
    return entries


def serialize_directory(entries):
    """Encodes entries into an uncompressed directory blob."""
    out = bytearray()
    write_varint(out, len(entries))

    last_id = 0
    for entry in entries:
        write_varint(out, entry.tile_id - last_id)
        last_id = entry.tile_id
    for entry in entries:
        write_varint(out, entry.run_length)
    for entry in entries:
        write_varint(out, entry.length)
    for i, entry in enumerate(entries):
        if i > 0 and entry.offset == entries[i - 1].offset + entries[i - 1].length:
            write_varint(out, 0)
        else:
            write_varint(out, entry.offset + 1)
    return bytes(out)


# ---------------------------------------------------------------------------
# Tile ids: the Hilbert curve, per zoom level.
# ---------------------------------------------------------------------------


def zoom_base(z):
    """Number of tile ids below zoom z: (4^z - 1) / 3."""
    return ((1 << (2 * z)) - 1) // 3


def zxy_to_tile_id(z, x, y):
    n = 1 << z
    if not (0 <= x < n and 0 <= y < n):
        raise ValueError(f"tile {z}/{x}/{y} is outside the zoom level")
    d = 0
    s = n >> 1
    while s > 0:
        rx = 1 if (x & s) > 0 else 0
        ry = 1 if (y & s) > 0 else 0
        d += s * s * ((3 * rx) ^ ry)
        # rotate
        if ry == 0:
            if rx == 1:
                x = s - 1 - x
                y = s - 1 - y
            x, y = y, x
        s >>= 1
    return zoom_base(z) + d


def tile_id_to_zxy(tile_id):
    z = 0
    while zoom_base(z + 1) <= tile_id:
        z += 1
    d = tile_id - zoom_base(z)
    n = 1 << z
    x = y = 0
    s = 1
    while s < n:
        rx = 1 & (d >> 1)
        ry = 1 & (d ^ rx)
        if ry == 0:
            if rx == 1:
                x = s - 1 - x
                y = s - 1 - y
            x, y = y, x
        x += s * rx
        y += s * ry
        d >>= 2
        s <<= 1
    return z, x, y


def zoom_of(tile_id):
    z = 0
    while zoom_base(z + 1) <= tile_id:
        z += 1
    return z


def lonlat_to_tile(lon, lat, z):
    """Slippy map tile containing a coordinate, clamped to the level."""
    n = 1 << z
    x = int((lon + 180.0) / 360.0 * n)
    lat = max(-85.05112878, min(85.05112878, lat))
    lat_rad = math.radians(lat)
    y = int((1.0 - math.log(math.tan(lat_rad) + 1.0 / math.cos(lat_rad)) / math.pi)
            / 2.0 * n)
    return max(0, min(n - 1, x)), max(0, min(n - 1, y))


def bbox_tile_ids(bbox, minzoom, maxzoom):
    """Every tile id covering the bbox, per zoom.

    Returns {zoom: set of ids}. A bbox is a rectangle in x/y but scattered
    along the Hilbert curve, which is exactly why the walk below needs the
    ranges as well — see `ranges_of`.
    """
    west, south, east, north = bbox
    per_zoom = {}
    for z in range(minzoom, maxzoom + 1):
        x0, y0 = lonlat_to_tile(west, north, z)
        x1, y1 = lonlat_to_tile(east, south, z)
        ids = set()
        for x in range(min(x0, x1), max(x0, x1) + 1):
            for y in range(min(y0, y1), max(y0, y1) + 1):
                ids.add(zxy_to_tile_id(z, x, y))
        per_zoom[z] = ids
    return per_zoom


def ranges_of(ids):
    """Merges a set of ids into sorted [start, end] ranges, inclusive."""
    if not ids:
        return []
    ordered = sorted(ids)
    ranges = []
    start = previous = ordered[0]
    for value in ordered[1:]:
        if value == previous + 1:
            previous = value
            continue
        ranges.append((start, previous))
        start = previous = value
    ranges.append((start, previous))
    return ranges


def ranges_intersect(ranges, low, high):
    """Does any range overlap [low, high]? Binary search, ranges sorted."""
    lo, hi = 0, len(ranges) - 1
    while lo <= hi:
        mid = (lo + hi) // 2
        start, end = ranges[mid]
        if end < low:
            lo = mid + 1
        elif start > high:
            hi = mid - 1
        else:
            return True
    return False


# ---------------------------------------------------------------------------
# Regions: country-shaped areas instead of a rectangle (#220).
# ---------------------------------------------------------------------------

# The zoom at which a region is rasterised. Every deeper tile belongs to
# the region exactly when its ancestor here does — on the Hilbert curve
# the descendants of one tile are ONE contiguous id range per zoom, so a
# z13 region of Canada is ~60 000 ranges instead of 5 million ids. The
# price is a margin of at most one z10 tile (39 km at the equator, 15 km
# at 67° N) along the border: a plan over a region errs towards too big,
# which is the harmless direction for a size estimate.
REGION_COVER_ZOOM = 10


def _merc_y(lat, n):
    lat = max(-85.0511, min(85.0511, lat))
    return (1.0 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2.0 * n


def region_rings(geojson, select=None):
    """Every ring of the (Multi)Polygons in a GeoJSON document.

    `select` is (key, {values}): only features whose property matches.
    A selection that matches nothing is an error, not an empty region —
    an empty region plans to zero bytes, and zero looks like an answer.
    """
    if geojson.get("type") == "FeatureCollection":
        features = geojson.get("features") or []
    elif geojson.get("type") == "Feature":
        features = [geojson]
    else:
        features = [{"type": "Feature", "properties": {}, "geometry": geojson}]
    if select is not None:
        key, values = select
        features = [f for f in features
                    if str((f.get("properties") or {}).get(key)) in values]
    rings = []
    for feature in features:
        geometry = feature.get("geometry") or {}
        kind = geometry.get("type")
        if kind == "Polygon":
            polygons = [geometry["coordinates"]]
        elif kind == "MultiPolygon":
            polygons = geometry["coordinates"]
        else:
            continue
        for polygon in polygons:
            rings.extend(ring for ring in polygon if len(ring) >= 4)
    if not rings:
        raise SystemExit("--region: no polygon "
                         + (f"with {select[0]} in {sorted(select[1])}" if select else "in the file"))
    return rings


def region_cover(rings, z):
    """{(x, y)} at zoom z: every tile the polygons touch.

    Two passes. Each edge is walked densely, so a fjord or an island
    narrower than a tile still claims its tile; then a scanline through
    each tile row fills the interior by the even-odd rule (holes stay
    holes). Rings are in degrees, as GeoJSON has them; a polygon that
    crosses the antimeridian is expected split there, as Natural Earth
    and Geofabrik ship them.
    """
    n = 1 << z
    tiles = set()
    edges = []
    for ring in rings:
        points = [((lon + 180.0) / 360.0 * n, _merc_y(lat, n))
                  for lon, lat in (pt[:2] for pt in ring)]
        for (x0, y0), (x1, y1) in zip(points, points[1:]):
            edges.append((x0, y0, x1, y1))
            steps = int(max(abs(x1 - x0), abs(y1 - y0)) * 4) + 1
            for i in range(steps + 1):
                f = i / steps
                tiles.add((min(n - 1, int(x0 + (x1 - x0) * f)),
                           min(n - 1, int(y0 + (y1 - y0) * f))))
    if not tiles:
        return tiles
    rows = [ty for _, ty in tiles]
    for ty in range(min(rows), max(rows) + 1):
        y = ty + 0.5
        xs = sorted(x0 + (y - y0) * (x1 - x0) / (y1 - y0)
                    for x0, y0, x1, y1 in edges
                    if (y0 <= y < y1) or (y1 <= y < y0))
        for left, right in zip(xs[0::2], xs[1::2]):
            for tx in range(max(0, int(left)), min(n - 1, int(right)) + 1):
                tiles.add((tx, ty))
    return tiles


def _merge_ranges(ranges):
    merged = []
    for start, end in sorted(ranges):
        if merged and merged[-1][1] + 1 >= start:
            if end > merged[-1][1]:
                merged[-1] = (merged[-1][0], end)
        else:
            merged.append((start, end))
    return merged


def region_ranges(rings, minzoom, maxzoom, cover_zoom=REGION_COVER_ZOOM):
    """({zoom: sorted inclusive id ranges}, tiles in the cover)."""
    cover_zoom = min(cover_zoom, maxzoom)
    cover = region_cover(rings, cover_zoom)
    base_cover = zoom_base(cover_zoom)
    hilbert = sorted(zxy_to_tile_id(cover_zoom, x, y) - base_cover
                     for x, y in cover)
    per_zoom = {}
    for z in range(minzoom, maxzoom + 1):
        base = zoom_base(z)
        if z >= cover_zoom:
            k = 4 ** (z - cover_zoom)
            per_zoom[z] = _merge_ranges(
                (base + h * k, base + (h + 1) * k - 1) for h in hilbert)
        else:
            k = 4 ** (cover_zoom - z)
            per_zoom[z] = _merge_ranges(
                (base + p, base + p) for p in {h // k for h in hilbert})
    return per_zoom, len(cover)


def ranges_overlap(ranges, starts, low, high):
    """How many ids of [low, high] lie in the ranges (sorted, disjoint)."""
    index = bisect.bisect_right(starts, high) - 1
    total = 0
    while index >= 0 and ranges[index][1] >= low:
        start, end = ranges[index]
        total += min(end, high) - max(start, low) + 1
        index -= 1
    return total


# ---------------------------------------------------------------------------
# The archive.
# ---------------------------------------------------------------------------


class Header:
    __slots__ = (
        "root_offset", "root_length", "metadata_offset", "metadata_length",
        "leaf_offset", "leaf_length", "tile_data_offset", "tile_data_length",
        "addressed_tiles", "tile_entries", "tile_contents", "clustered",
        "internal_compression", "tile_compression", "tile_type",
        "min_zoom", "max_zoom", "min_lon", "min_lat", "max_lon", "max_lat",
        "center_zoom", "center_lon", "center_lat",
    )

    @classmethod
    def parse(cls, raw):
        if len(raw) < HEADER_LEN:
            raise ValueError("file is shorter than a PMTiles header")
        fields = struct.unpack(HEADER_FMT, raw[:HEADER_LEN])
        if fields[0] != b"PMTiles":
            raise ValueError("not a PMTiles archive (magic bytes missing)")
        if fields[1] != 3:
            raise ValueError(f"PMTiles version {fields[1]}, only 3 is supported")
        header = cls()
        names = [
            "root_offset", "root_length", "metadata_offset", "metadata_length",
            "leaf_offset", "leaf_length", "tile_data_offset",
            "tile_data_length", "addressed_tiles", "tile_entries",
            "tile_contents", "clustered", "internal_compression",
            "tile_compression", "tile_type", "min_zoom", "max_zoom",
            "min_lon", "min_lat", "max_lon", "max_lat", "center_zoom",
            "center_lon", "center_lat",
        ]
        for name, value in zip(names, fields[2:]):
            setattr(header, name, value)
        return header

    def pack(self):
        return struct.pack(
            HEADER_FMT, b"PMTiles", 3,
            self.root_offset, self.root_length,
            self.metadata_offset, self.metadata_length,
            self.leaf_offset, self.leaf_length,
            self.tile_data_offset, self.tile_data_length,
            self.addressed_tiles, self.tile_entries, self.tile_contents,
            self.clustered, self.internal_compression, self.tile_compression,
            self.tile_type, self.min_zoom, self.max_zoom,
            self.min_lon, self.min_lat, self.max_lon, self.max_lat,
            self.center_zoom, self.center_lon, self.center_lat,
        )

    @property
    def bounds(self):
        return (self.min_lon / 1e7, self.min_lat / 1e7,
                self.max_lon / 1e7, self.max_lat / 1e7)


class Archive:
    """A PMTiles v3 archive, read lazily through a source."""

    def __init__(self, source):
        self.source = source
        self.header = Header.parse(source.read(0, HEADER_LEN))
        self._root = None

    @property
    def root(self):
        if self._root is None:
            raw = self.source.read(
                self.header.root_offset, self.header.root_length)
            self._root = deserialize_directory(
                decompress(raw, self.header.internal_compression))
        return self._root

    def metadata(self):
        raw = self.source.read(
            self.header.metadata_offset, self.header.metadata_length)
        text = decompress(raw, self.header.internal_compression)
        try:
            return json.loads(text)
        except ValueError:
            return {}

    def _leaf(self, entry):
        raw = self.source.read(
            self.header.leaf_offset + entry.offset, entry.length)
        return deserialize_directory(
            decompress(raw, self.header.internal_compression))

    def walk(self, wanted_ranges=None):
        """Yields every tile entry, skipping leaves that cannot match.

        `wanted_ranges` is a sorted list of inclusive id ranges. Without it
        the whole tree is read, which on a planet build means every leaf
        directory — fine locally, expensive over the network. With it, a
        leaf is fetched only when its id span overlaps something wanted.
        """
        yield from self._walk_directory(self.root, wanted_ranges)

    def _walk_directory(self, entries, wanted_ranges):
        for index, entry in enumerate(entries):
            if entry.run_length != 0:
                if wanted_ranges is not None and not ranges_intersect(
                        wanted_ranges, entry.tile_id,
                        entry.tile_id + entry.run_length - 1):
                    continue
                yield entry
                continue
            # A leaf pointer. Its span reaches to the next sibling's first
            # id; for the last sibling it is open-ended.
            span_end = (entries[index + 1].tile_id - 1
                        if index + 1 < len(entries) else (1 << 62))
            if wanted_ranges is not None and not ranges_intersect(
                    wanted_ranges, entry.tile_id, span_end):
                continue
            yield from self._walk_directory(self._leaf(entry), wanted_ranges)

    def find(self, tile_id):
        """Returns the entry holding a tile id, or None."""
        entries = self.root
        for _ in range(4):  # root plus at most a few leaf levels
            index = _search(entries, tile_id)
            if index < 0:
                return None
            entry = entries[index]
            if entry.run_length == 0:
                entries = self._leaf(entry)
                continue
            if tile_id < entry.tile_id + entry.run_length:
                return entry
            return None
        raise ValueError("directory nesting deeper than expected")

    def tile_bytes(self, entry):
        return self.source.read(
            self.header.tile_data_offset + entry.offset, entry.length)

    def close(self):
        self.source.close()


def _search(entries, tile_id):
    """Index of the last entry whose id is <= tile_id, or -1."""
    lo, hi = 0, len(entries) - 1
    found = -1
    while lo <= hi:
        mid = (lo + hi) // 2
        if entries[mid].tile_id <= tile_id:
            found = mid
            lo = mid + 1
        else:
            hi = mid - 1
    return found


# ---------------------------------------------------------------------------
# Commands.
# ---------------------------------------------------------------------------


def human(size):
    if size >= 1 << 30:
        return f"{size / (1 << 30):.2f} GB"
    if size >= 1 << 20:
        return f"{size / (1 << 20):.1f} MB"
    if size >= 1 << 10:
        return f"{size / (1 << 10):.1f} KB"
    return f"{size} B"


def command_info(args):
    archive = Archive(open_source(args.source))
    header = archive.header
    west, south, east, north = header.bounds
    print(f"source              {archive.source.name}")
    print(f"zoom                z{header.min_zoom}-z{header.max_zoom}")
    print(f"bounds              {west:.4f},{south:.4f},{east:.4f},{north:.4f}")
    print(f"tile type           {TILE_TYPE_NAMES.get(header.tile_type, '?')}")
    print("tile compression    "
          f"{COMPRESSION_NAMES.get(header.tile_compression, '?')}")
    print("directory compr.    "
          f"{COMPRESSION_NAMES.get(header.internal_compression, '?')}")
    print(f"clustered           {'yes' if header.clustered else 'no'}")
    print(f"addressed tiles     {header.addressed_tiles}")
    print(f"directory entries   {header.tile_entries}")
    print(f"distinct contents   {header.tile_contents}")
    print(f"tile data           {human(header.tile_data_length)}")
    try:
        meta = archive.metadata()
    except Exception as error:  # noqa: BLE001 - metadata is optional
        print(f"metadata            unreadable ({error})")
    else:
        layers = meta.get("vector_layers") or []
        if layers:
            names = ", ".join(sorted(layer.get("id", "?") for layer in layers))
            print(f"vector layers       {len(layers)}: {names}")
    archive.close()
    return 0


def plan_extract(archive, bbox, minzoom, maxzoom):
    """Counts tiles and bytes per zoom for a bbox.

    Separate from the printing so it can be tested against a known
    fixture: the one number this whole tool exists to produce must not be
    checkable only by reading a table.
    """
    wanted = bbox_tile_ids(bbox, minzoom, maxzoom)
    per_zoom = {z: ranges_of(ids) for z, ids in wanted.items()}
    tiles, byte_count = plan_ranges(archive, per_zoom)
    possible = {z: len(ids) for z, ids in wanted.items()}
    return tiles, byte_count, possible


def plan_ranges(archive, per_zoom):
    """Tiles and bytes per zoom for {zoom: sorted inclusive id ranges}.

    Counted by range arithmetic, never tile by tile: a planet build holds
    runs of millions of identical ocean tiles, and a region of Canada at
    z13 is five million ids — a set of them costs gigabytes, a loop over
    them minutes (#220).
    """
    zooms = sorted(per_zoom)
    ranges = [r for z in zooms for r in per_zoom[z]]
    starts = [r[0] for r in ranges]
    bases = [zoom_base(z) for z in range(0, zooms[-1] + 2)]
    tiles = {z: 0 for z in zooms}
    byte_count = {z: 0 for z in zooms}
    counted = set()

    for entry in archive.walk(ranges):
        last = entry.tile_id + entry.run_length - 1
        low = entry.tile_id
        z = bisect.bisect_right(bases, low) - 1
        while low <= last and z <= zooms[-1]:
            high = min(last, bases[z + 1] - 1)
            inside = ranges_overlap(ranges, starts, low, high)
            if inside:
                tiles[z] += inside
                # Contents are shared: a run of identical tiles is stored
                # once, and so is a tile repeated elsewhere. Counting the
                # bytes per occurrence would inflate the estimate above
                # what an extract actually costs — and this estimate is
                # the whole point.
                if entry.offset not in counted:
                    counted.add(entry.offset)
                    byte_count[z] += entry.length
            low = high + 1
            z += 1
    return tiles, byte_count


def parse_select(text):
    """`KEY=V1,V2` -> (key, {values})."""
    key, sep, values = text.partition("=")
    if not sep or not key or not values:
        raise SystemExit(f"--select wants KEY=VALUE[,VALUE…], got {text!r}")
    return key, set(values.split(","))


def command_plan(args):
    """Measures bytes per zoom for a bbox. The number that decides #496."""
    if (args.bbox is None) == (args.region is None):
        raise SystemExit("plan wants exactly one of --bbox and --region")
    if args.select and not args.region:
        raise SystemExit("--select picks features of --region")
    archive = Archive(open_source(args.source))
    header = archive.header
    minzoom = max(args.minzoom, header.min_zoom)
    maxzoom = min(args.maxzoom, header.max_zoom)
    if minzoom > maxzoom:
        raise SystemExit(
            f"archive holds z{header.min_zoom}-z{header.max_zoom}, "
            f"asked for z{args.minzoom}-z{args.maxzoom}")

    if args.bbox is not None:
        bbox = parse_bbox(args.bbox)
        tiles, byte_count, possible_per_zoom = plan_extract(
            archive, bbox, minzoom, maxzoom)
        west, south, east, north = bbox
        area = f"bbox       {west},{south},{east},{north}"
    else:
        with open(args.region) as handle:
            geojson = json.load(handle)
        select = parse_select(args.select) if args.select else None
        per_zoom, cover = region_ranges(
            region_rings(geojson, select), minzoom, maxzoom)
        tiles, byte_count = plan_ranges(archive, per_zoom)
        possible_per_zoom = {z: sum(e - s + 1 for s, e in r)
                             for z, r in per_zoom.items()}
        cover_zoom = min(REGION_COVER_ZOOM, maxzoom)
        area = (f"region     {args.region}"
                + (f" ({args.select})" if args.select else "")
                + f", {cover} tiles at z{cover_zoom}")

    total = sum(byte_count.values())
    possible = sum(possible_per_zoom.values())
    present = sum(tiles.values())
    missing = possible - present

    print(f"source     {archive.source.name}")
    print(area)
    print(f"zoom       z{minzoom}-z{maxzoom}")
    print()
    print("  zoom    tiles        bytes   step   cumulative")
    running = 0
    previous = None
    for z in range(minzoom, maxzoom + 1):
        running += byte_count[z]
        step = "" if previous in (None, 0) else f"{byte_count[z] / previous:.1f}x"
        print(f"  z{z:<4d} {tiles[z]:8d} {human(byte_count[z]):>12} "
              f"{step:>6}   {human(running):>10}")
        previous = byte_count[z]
    print()
    print(f"total tile bytes       {human(total)}")
    print(f"tiles present/possible {present}/{possible}"
          f" ({missing} empty in the source)")
    # Directories and metadata ride along in the extract. A tenth is
    # generous for a clustered archive and keeps the verdict honest.
    estimate = int(total * 1.1)
    print(f"estimated file size    {human(estimate)} (tiles + ~10 % overhead)")
    budget = args.max_bytes
    print(f"budget                 {human(budget)}")
    if estimate > budget:
        over = estimate / budget
        print(f"VERDICT                over budget by {over:.1f}x — "
              "lower --maxzoom or cut the bbox into smaller areas")
    else:
        print(f"VERDICT                fits ({estimate / budget:.0%} of budget)")
    print()
    print(f"read {archive.source.bytes_read} bytes in "
          f"{archive.source.requests} requests")
    archive.close()
    return 0 if estimate <= budget else 2


def coverage_sample(bbox, minzoom, maxzoom, budget, rng):
    """Tile ids spread over the AREA and over the ZOOMS, corners first.

    Two biases have to be defeated here, and both of them make a sample
    look thorough while it is blind:

    A draw proportional to tile count is a draw from the top zoom alone —
    z12 holds 4096 times as many tiles as z6, so the coarse levels, which
    are exactly the ones an overview needs, are never looked at. Hence a
    fixed budget PER ZOOM.

    And a wrong cut loses its EDGES first: a bbox short by half a degree
    is complete everywhere except along one side. A uniform interior draw
    almost never lands there, so the four corners go in before anything
    random does.
    """
    zooms = list(range(minzoom, maxzoom + 1))
    if not zooms:
        return []
    per_zoom = max(1, budget // len(zooms))
    west, south, east, north = bbox
    picked = []
    for z in zooms:
        x0, y0 = lonlat_to_tile(west, north, z)
        x1, y1 = lonlat_to_tile(east, south, z)
        x_lo, x_hi = min(x0, x1), max(x0, x1)
        y_lo, y_hi = min(y0, y1), max(y0, y1)
        corners = [(x_lo, y_lo), (x_hi, y_lo), (x_lo, y_hi), (x_hi, y_hi)]
        # Reicht das Budget nur für eine Ecke je Zoom, nähme man sonst
        # dreizehnmal dieselbe Nordwestecke und sähe die anderen drei
        # Ränder nie. Durchrotieren kostet nichts und deckt sie ab.
        shift = z % 4
        chosen = corners[shift:] + corners[:shift]
        del chosen[per_zoom:]
        while len(chosen) < per_zoom:
            chosen.append((rng.randint(x_lo, x_hi), rng.randint(y_lo, y_hi)))
        for x, y in dict.fromkeys(chosen):  # ordered, deduplicated
            picked.append(zxy_to_tile_id(z, x, y))
    return picked


def command_check(args):
    """Proves an extract carries the source's bytes for the area it claims.

    `pmtiles extract` is trustworthy; a workflow around it is not. A wrong
    bbox, a stale source or a truncated upload all produce a valid archive
    that simply holds the wrong tiles, and every one of those reaches the
    browser as "the map is blank here" with no error anywhere.

    That takes BOTH directions, and only one of them is obvious:

    - inclusion — everything the extract holds really is the source's
      bytes. Catches a stale or corrupted cut.
    - coverage — everything the source holds INSIDE THE BBOX really is in
      the extract. Catches the wrong cut.

    Inclusion alone is the trap this function was rewritten out of: it
    samples from what the extract contains, so an extract of the wrong
    region passes it with every single sample matching. The one failure
    the docstring above promises to catch — a wrong bbox — was the one it
    could not see.
    """
    bbox = parse_bbox(args.bbox)
    extract = Archive(open_source(args.extract))
    source = Archive(open_source(args.source))
    rng = random.Random(args.seed)
    mismatches = []

    # --- Einschluss: was drin ist, stammt aus der Quelle ---------------
    entries = [e for e in extract.walk() if e.run_length > 0]
    if not entries:
        raise SystemExit("the extract holds no tiles at all")
    ids = []
    for entry in entries:
        ids.extend(range(entry.tile_id, entry.tile_id + entry.run_length))
    inclusion = rng.sample(ids, min(args.samples, len(ids)))
    for tile_id in sorted(inclusion):
        z, x, y = tile_id_to_zxy(tile_id)
        theirs = source.find(tile_id)
        if theirs is None:
            mismatches.append(f"z{z}/{x}/{y} is in the extract but not the source")
            continue
        if extract.tile_bytes(extract.find(tile_id)) != source.tile_bytes(theirs):
            mismatches.append(f"z{z}/{x}/{y} differs from the source")

    # --- Abdeckung: was die Quelle im Gebiet hat, ist auch drin --------
    # Gemessen wird gegen die Zoomspanne, die VERLANGT wurde, nicht gegen
    # die, die der Auszug behauptet. Andersherum verstoppte ein bei z10
    # abgebrochener Auszug seine eigene Prüfung: Er sagt „ich gehe bis
    # z10", und danach befragt, fehlte ihm nichts.
    top = min(args.maxzoom, source.header.max_zoom)
    bottom = max(0, source.header.min_zoom)
    wanted = coverage_sample(bbox, bottom, top, args.samples, rng)
    empty = 0
    for tile_id in wanted:
        z, x, y = tile_id_to_zxy(tile_id)
        theirs = source.find(tile_id)
        if theirs is None:
            # Die Quelle hat dort selbst nichts — offenes Meer, leeres
            # Gebiet. Das ist kein Befund, aber es zählt auch nicht als
            # Beweis, deshalb wird es gezählt und nicht verschwiegen.
            empty += 1
            continue
        mine = extract.find(tile_id)
        if mine is None:
            mismatches.append(
                f"z{z}/{x}/{y} is in the source inside the bbox but MISSING "
                "from the extract")
            continue
        if extract.tile_bytes(mine) != source.tile_bytes(theirs):
            mismatches.append(f"z{z}/{x}/{y} differs from the source")
    proven = len(wanted) - empty

    print(f"extract   {extract.source.name}")
    print(f"source    {source.source.name}")
    print(f"bbox      {','.join(str(v) for v in bbox)} z{bottom}-z{top}")
    print(f"inclusion {len(ids)} addressed, {len(inclusion)} sampled")
    print(f"coverage  {len(wanted)} sampled, {proven} present in the source"
          f" ({empty} empty there)")
    for line in mismatches:
        print(f"MISMATCH  {line}")
    extract.close()
    source.close()

    if mismatches:
        print(f"FAILED    {len(mismatches)} mismatches")
        return 1
    if proven == 0:
        # Ohne eine einzige belegte Kachel hat die Abdeckungsprüfung
        # nichts geprüft, und ein grünes Häkchen darauf wäre schlimmer
        # als gar keins — dieselbe Linie wie bei den Transport-Fehlern
        # im Schema Check: lieber „unentschieden" als erfundener Erfolg.
        print("FAILED    the source holds none of the sampled tiles in this "
              "bbox — wrong area, wrong source, or a zoom range that does "
              "not overlap")
        return 1
    print("ok        every sampled tile matches the source byte for byte, "
          f"and all {proven} tiles the source has inside the bbox are present")
    return 0


def parse_bbox(text):
    parts = text.split(",")
    if len(parts) != 4:
        raise SystemExit("--bbox wants west,south,east,north")
    try:
        west, south, east, north = (float(p) for p in parts)
    except ValueError:
        raise SystemExit(f"--bbox {text} is not four numbers")
    if west >= east or south >= north:
        raise SystemExit(f"--bbox {text} is empty or inverted")
    # Ohne Bereichsprüfung klemmt `lonlat_to_tile` eine vertippte Bbox
    # still an den Weltrand: aus `500,600,700,800` wird ein Streifen von
    # einer Kachel, und `plan` meldet dafür ein völlig plausibles
    # „fits (1 % of budget)". Eine Zahl, die wie eine Antwort aussieht und
    # keine ist, ist hier der teuerste Fehler überhaupt — sie entscheidet
    # den Zuschnitt, und der entscheidet, wo die Karte später leer ist.
    # Die Klemmung selbst bleibt richtig und nötig (Web Mercator kennt den
    # 90. Breitengrad nicht, siehe `_test_bbox_clamps_to_the_projection`);
    # was hier abgewiesen wird, ist der Tippfehler davor.
    if west < -180.0 or east > 180.0:
        raise SystemExit(
            f"--bbox {text}: longitude outside -180..180 — a typo here is "
            "clamped to the edge of the world and still reports a size")
    if south < -90.0 or north > 90.0:
        raise SystemExit(
            f"--bbox {text}: latitude outside -90..90 — a typo here is "
            "clamped to the edge of the world and still reports a size")
    return west, south, east, north


# ---------------------------------------------------------------------------
# Self-test. Builds a synthetic archive — for the test only, never for
# production; cutting real extracts is `pmtiles extract`.
# ---------------------------------------------------------------------------


def _build_archive(tiles, leaf_size=None, max_root_bytes=16384,
                   compression=COMPRESSION_GZIP, tile_compression=COMPRESSION_NONE,
                   tile_type=1, bounds=(-10.0, 35.0, 30.0, 60.0), metadata=None):
    """Serialises {(z, x, y): bytes} into a PMTiles v3 archive.

    `leaf_size` forces leaf directories of that many entries. The fixtures
    need them, and a byte budget cannot reliably produce them: a synthetic
    directory is so regular that gzip takes 341 entries down to 57 bytes,
    so any threshold low enough to split is also low enough to be absurd.
    Stating the intent beats tuning a number against a compressor.

    `tile_compression`, `tile_type`, `bounds` (west, south, east, north)
    and `metadata` are what the header and the metadata blob state about
    the tiles; the tile bytes themselves are written as given. Since the
    height tiles (tool/height_tiles.py) this is also a real writer, not
    only a fixture: that archive is read by the app over the same reader
    as the basemap, and `pmtiles verify` checks it in CI.
    """
    by_id = sorted((zxy_to_tile_id(z, x, y), data)
                   for (z, x, y), data in tiles.items())

    blob = bytearray()
    offsets = {}
    entries = []
    for tile_id, data in by_id:
        digest = hashlib.sha256(data).digest()
        if digest in offsets:
            offset = offsets[digest]
        else:
            offset = len(blob)
            offsets[digest] = offset
            blob += data
        if (entries and entries[-1].offset == offset
                and entries[-1].length == len(data)
                and entries[-1].tile_id + entries[-1].run_length == tile_id):
            entries[-1].run_length += 1
            continue
        entries.append(Entry(tile_id, 1, offset, len(data)))

    root_raw = compress(serialize_directory(entries), compression)
    leaf_blob = b""
    if leaf_size is not None or len(root_raw) > max_root_bytes:
        # Leaves start at 4096 entries like go-pmtiles' optimiser and grow
        # until the root fits. Starting at 2 (as until 2026-10-01) found the
        # SMALLEST leaf size whose root fits — 43 641 leaves of two entries
        # for the height archive, a leaf fetch for nearly every tile read.
        size = leaf_size or 4096
        while True:
            leaf_blob = bytearray()
            root_entries = []
            for start in range(0, len(entries), size):
                chunk = entries[start:start + size]
                serialised = compress(serialize_directory(chunk), compression)
                root_entries.append(
                    Entry(chunk[0].tile_id, 0, len(leaf_blob), len(serialised)))
                leaf_blob += serialised
            root_raw = compress(serialize_directory(root_entries), compression)
            if leaf_size is not None or len(root_raw) <= max_root_bytes:
                leaf_blob = bytes(leaf_blob)
                break
            size *= 2
            if size > len(entries):
                raise ValueError("cannot fit a root directory")

    metadata = compress(json.dumps(metadata if metadata is not None
                                   else {"vector_layers": []}).encode(), compression)

    root_offset = HEADER_LEN
    metadata_offset = root_offset + len(root_raw)
    leaf_offset = metadata_offset + len(metadata)
    tile_offset = leaf_offset + len(leaf_blob)

    zooms = [z for (z, _, _) in tiles]
    header = Header()
    header.root_offset = root_offset
    header.root_length = len(root_raw)
    header.metadata_offset = metadata_offset
    header.metadata_length = len(metadata)
    header.leaf_offset = leaf_offset
    header.leaf_length = len(leaf_blob)
    header.tile_data_offset = tile_offset
    header.tile_data_length = len(blob)
    header.addressed_tiles = sum(e.run_length for e in entries)
    # Tile entries are the entries with a run length (root or leaf); the
    # root's pointers to leaves are not among them. Counting them in was
    # the bug `pmtiles verify` caught on the first height build:
    # "header TileEntriesCount=130922 but 87281 tile entries".
    header.tile_entries = len(entries)
    header.tile_contents = len(offsets)
    header.clustered = 1
    header.internal_compression = compression
    header.tile_compression = tile_compression
    header.tile_type = tile_type
    header.min_zoom = min(zooms)
    header.max_zoom = max(zooms)
    west, south, east, north = bounds
    header.min_lon = int(round(west * 1e7))
    header.min_lat = int(round(south * 1e7))
    header.max_lon = int(round(east * 1e7))
    header.max_lat = int(round(north * 1e7))
    header.center_zoom = min(zooms)
    header.center_lon = int(round((west + east) / 2 * 1e7))
    header.center_lat = int(round((south + north) / 2 * 1e7))

    return header.pack() + root_raw + metadata + leaf_blob + bytes(blob)


class _BytesSource:
    def __init__(self, data):
        self.name = "<memory>"
        self._data = data
        self.requests = 0
        self.bytes_read = 0

    def read(self, offset, length):
        self.requests += 1
        self.bytes_read += length
        chunk = self._data[offset:offset + length]
        if len(chunk) != length:
            raise IOError("short read")
        return chunk

    def close(self):
        pass


def self_test():
    _test_varints()
    _test_hilbert()
    _test_bbox_clamps_to_the_projection()
    _test_directory_roundtrip()
    _test_ranges()
    _test_archive_roundtrip()
    _test_plan_counts_shared_content_once()
    _test_region_matches_an_aligned_bbox()
    _test_region_keeps_holes_and_refuses_empty_selections()
    _test_plan_counts_part_of_a_run()
    _test_leaf_pointer_is_not_a_tile()
    _test_check_fails_on_a_wrong_tile()
    _test_check_fails_on_the_wrong_region()
    _test_bbox_rejects_nonsense()
    _test_http_source_insists_on_range()
    print("map_tiles self-test: ok")


def _test_varints():
    for value in [0, 1, 127, 128, 300, 1 << 20, (1 << 63) - 1]:
        out = bytearray()
        write_varint(out, value)
        back, pos = read_varint(bytes(out), 0)
        assert back == value, (value, back)
        assert pos == len(out)


def _test_hilbert():
    # Known anchors from the PMTiles v3 spec.
    assert zxy_to_tile_id(0, 0, 0) == 0
    assert zxy_to_tile_id(1, 0, 0) == 1
    assert zxy_to_tile_id(1, 0, 1) == 2
    assert zxy_to_tile_id(1, 1, 1) == 3
    assert zxy_to_tile_id(1, 1, 0) == 4
    for z in range(0, 9):
        n = 1 << z
        step = max(1, n // 7)
        for x in range(0, n, step):
            for y in range(0, n, step):
                tile_id = zxy_to_tile_id(z, x, y)
                assert tile_id_to_zxy(tile_id) == (z, x, y), (z, x, y)
                assert zoom_of(tile_id) == z
    # Every id of a zoom is used exactly once.
    for z in range(0, 6):
        n = 1 << z
        ids = {zxy_to_tile_id(z, x, y) for x in range(n) for y in range(n)}
        assert len(ids) == n * n
        assert min(ids) == zoom_base(z)
        assert max(ids) == zoom_base(z + 1) - 1


def _test_directory_roundtrip():
    entries = [
        Entry(0, 1, 0, 10),
        Entry(1, 1, 10, 20),      # contiguous, encodes offset 0
        Entry(5, 3, 100, 7),
        Entry(9, 0, 30, 40),      # a leaf pointer
    ]
    blob = serialize_directory(entries)
    back = deserialize_directory(blob)
    assert back == entries, back

    # An archive whose first tile sits at offset 0 has to survive a round
    # trip, and the encoded first offset must not be 0: that is the
    # invariant which makes the reader's `i > 0` guard unreachable. Assert
    # the invariant rather than the guard — a test for unreachable code
    # would only be a test of the test.
    single = [Entry(0, 1, 0, 5)]
    encoded = serialize_directory(single)
    assert deserialize_directory(encoded) == single
    position = 0
    _, position = read_varint(encoded, position)          # count
    for _ in range(3):                                     # ids, runs, lengths
        _, position = read_varint(encoded, position)
    first_offset, _ = read_varint(encoded, position)
    assert first_offset != 0, "offset 0 must encode as 1, never as 0"


def _test_bbox_clamps_to_the_projection():
    """`--bbox` takes whatever a caller types, including the poles.

    Web Mercator has no 90th parallel: `tan(90°)` is infinite, so an
    unclamped latitude either raises deep inside a size estimate or
    produces a tile row that does not exist. Both are worse than quietly
    stopping at the projection's edge, which is what every tile server
    does anyway.
    """
    for z in (0, 5, 14):
        n = 1 << z
        _, y_north = lonlat_to_tile(0.0, 90.0, z)
        _, y_south = lonlat_to_tile(0.0, -90.0, z)
        assert y_north == 0, (z, y_north)
        assert y_south == n - 1, (z, y_south)
    # A bbox spanning the whole world must still enumerate a full level.
    ids = bbox_tile_ids((-180.0, -90.0, 180.0, 90.0), 3, 3)
    assert len(ids[3]) == 64, len(ids[3])


def _test_ranges():
    assert ranges_of(set()) == []
    assert ranges_of({5}) == [(5, 5)]
    assert ranges_of({1, 2, 3, 7, 8, 20}) == [(1, 3), (7, 8), (20, 20)]
    ranges = [(1, 3), (7, 8), (20, 20)]
    assert ranges_intersect(ranges, 0, 1)
    assert ranges_intersect(ranges, 8, 19)
    assert ranges_intersect(ranges, 0, 100)
    assert not ranges_intersect(ranges, 4, 6)
    assert not ranges_intersect(ranges, 21, 30)
    assert not ranges_intersect([], 0, 5)


def _test_archive_roundtrip():
    tiles = _fixture_tiles()
    # Leaf directories forced: that path is the one that breaks silently,
    # so every fixture here has to take it.
    raw = _build_archive(tiles, leaf_size=16)
    archive = Archive(_BytesSource(raw))
    assert archive.header.min_zoom == 0
    assert archive.header.max_zoom == 4
    assert archive.header.leaf_length > 0, "fixture must exercise leaf directories"

    walked = [e for e in archive.walk() if e.run_length > 0]
    addressed = sum(e.run_length for e in walked)
    assert addressed == len(tiles), (addressed, len(tiles))
    # The header counts tile entries the way `pmtiles verify` does: the
    # entries with a run length, not the root's pointers to leaves.
    assert archive.header.tile_entries == len(walked), (archive.header.tile_entries, len(walked))
    assert archive.header.addressed_tiles == addressed

    for (z, x, y), data in tiles.items():
        entry = archive.find(zxy_to_tile_id(z, x, y))
        assert entry is not None, (z, x, y)
        assert archive.tile_bytes(entry) == data, (z, x, y)

    # A tile the archive does not hold must answer None, not a neighbour's
    # bytes: `find` walks to the last entry at or below the id, and without
    # the run-length check that is silently the wrong tile.
    assert archive.find(zxy_to_tile_id(6, 0, 0)) is None

    # Walking with ranges must find exactly the same tiles as filtering by
    # hand — the leaf-skipping is an optimisation and may never lose one.
    wanted = bbox_tile_ids((-5.0, 40.0, 20.0, 55.0), 0, 4)
    all_ids = set().union(*wanted.values())
    by_walk = set()
    for entry in archive.walk(ranges_of(all_ids)):
        for tile_id in range(entry.tile_id, entry.tile_id + entry.run_length):
            if tile_id in all_ids:
                by_walk.add(tile_id)
    by_hand = {tile_id for tile_id in all_ids if archive.find(tile_id)}
    assert by_walk == by_hand, (len(by_walk), len(by_hand))
    assert by_walk, "the fixture bbox must select something"


def _test_plan_counts_shared_content_once():
    """Identical tiles are stored once, so they must be counted once.

    An archive stores four identical neighbouring tiles as one run over
    one copy of the bytes. A plan that adds them up per occurrence
    promises a download four times too big — and the whole tool exists to
    produce that one number.
    """
    shared = b"same-bytes-repeated"
    other = b"a different tile"
    tiles = {(2, x, 0): shared for x in range(4)}
    tiles[(2, 0, 1)] = other
    archive = Archive(_BytesSource(_build_archive(tiles)))

    entries = [e for e in archive.walk() if e.run_length > 0]
    assert len({e.offset for e in entries}) == 2
    assert sum(e.run_length for e in entries) == 5

    # The whole world at z2 — every fixture tile is inside it.
    counts, byte_count, possible = plan_extract(
        archive, (-179.0, -85.0, 179.0, 85.0), 2, 2)
    assert counts[2] == 5, counts
    assert possible[2] == 16, possible
    assert byte_count[2] == len(shared) + len(other), (
        byte_count[2], len(shared) + len(other))


def _square(west, south, east, north):
    return [[west, south], [east, south], [east, north], [west, north],
            [west, south]]


def _test_region_matches_an_aligned_bbox():
    """A region that IS a tile-aligned rectangle plans like that bbox.

    The two paths share nothing but the archive walk: the bbox enumerates
    ids, the region rasterises and expands Hilbert ranges. If the range
    expansion were off by one tile, or ancestors were missed below the
    cover zoom, the totals would part here.
    """
    archive = Archive(_BytesSource(_build_archive(_fixture_tiles(), leaf_size=16)))
    box = (-89.9, -66.4, 89.9, 66.4)  # z2 tiles x1..2, y1..2, shrunk inside
    rings = [_square(*box)]
    per_zoom, cover = region_ranges(rings, 0, 4)
    assert cover == 64, cover  # rasterised at z4 = min(cover zoom, maxzoom)
    by_region = plan_ranges(archive, per_zoom)
    tiles, byte_count, possible = plan_extract(archive, box, 0, 4)
    assert by_region == (tiles, byte_count), (by_region, tiles, byte_count)
    assert {z: sum(e - s + 1 for s, e in r) for z, r in per_zoom.items()} == possible

    # Rasterised coarser than asked, the deeper zooms are the cover's
    # descendants — one contiguous range per cover tile.
    per_zoom, cover = region_ranges(rings, 0, 4, cover_zoom=2)
    assert cover == 4, cover
    assert sum(e - s + 1 for s, e in per_zoom[4]) == 64
    expected = bbox_tile_ids(box, 4, 4)[4]
    covered = {i for s, e in per_zoom[4] for i in range(s, e + 1)}
    assert covered == expected


def _test_region_keeps_holes_and_refuses_empty_selections():
    outer = _square(-179.9, -84.9, 179.9, 84.9)
    hole = _square(-89.9, -66.4, 89.9, 66.4)  # z3 tiles 2..5 touched by the edges
    cover = region_cover([outer, hole], 3)
    # The hole's edges claim their tiles; only the four tiles strictly
    # inside it (3..4 x 3..4) drop out.
    assert len(cover) == 60, len(cover)
    assert (3, 3) not in cover and (2, 2) in cover

    collection = {"type": "FeatureCollection", "features": [
        {"type": "Feature", "properties": {"ISO": "CA"},
         "geometry": {"type": "Polygon", "coordinates": [outer]}},
        {"type": "Feature", "properties": {"ISO": "US"},
         "geometry": {"type": "MultiPolygon", "coordinates": [[hole]]}},
    ]}
    assert region_rings(collection, ("ISO", {"US"})) == [hole]
    assert len(region_rings(collection)) == 2
    try:
        region_rings(collection, ("ISO", {"XX"}))
    except SystemExit as error:
        assert "XX" in str(error), error
    else:
        raise AssertionError("an empty selection must not plan to zero bytes")


def _test_plan_counts_part_of_a_run():
    """A run reaching out of the region counts only the tiles inside it.

    A planet build stores the open ocean as runs of millions of identical
    tiles; counting a whole run because one tile touches the region would
    make every coastal region the size of an ocean.
    """
    tiles = {(2, x, y): b"ocean" for x in range(4) for y in range(4)}
    archive = Archive(_BytesSource(_build_archive(tiles)))
    runs = [e for e in archive.walk() if e.run_length > 0]
    assert [e.run_length for e in runs] == [16], runs
    base = zoom_base(2)
    counted, byte_count = plan_ranges(archive, {2: [(base + 3, base + 6)]})
    assert counted == {2: 4}, counted
    assert byte_count == {2: len(b"ocean")}, byte_count


def _test_leaf_pointer_is_not_a_tile():
    # Guards the rule in Entry's docstring: run_length 0 is a leaf, and the
    # walk must never hand one out as a tile.
    tiles = {(z, 0, 0): bytes([z]) * 64 for z in range(0, 8)}
    raw = _build_archive(tiles, leaf_size=2)
    archive = Archive(_BytesSource(raw))
    assert archive.header.leaf_length > 0
    assert all(entry.run_length > 0 for entry in archive.walk())
    for z in range(0, 8):
        entry = archive.find(zxy_to_tile_id(z, 0, 0))
        assert entry is not None and archive.tile_bytes(entry) == bytes([z]) * 64


def _fixture_tiles(z_range=range(0, 5)):
    tiles = {}
    for z in z_range:
        n = 1 << z
        for x in range(n):
            for y in range(n):
                tiles[(z, x, y)] = f"tile {z}/{x}/{y}".encode()
    return tiles


def _test_check_fails_on_a_wrong_tile():
    """A check that cannot fail is not a check.

    Both directions matter: a faithful extract has to pass, and one with a
    single wrong tile has to be caught. The second is the one worth having
    — a wrong bbox or a stale source yields a perfectly valid archive that
    simply holds other bytes, and in the browser that reads as "the map is
    blank here", with no error anywhere.
    """
    source_tiles = _fixture_tiles()
    subset = {key: value for key, value in source_tiles.items() if key[0] <= 3}

    with tempfile.TemporaryDirectory() as folder:
        source_path = os.path.join(folder, "source.pmtiles")
        good_path = os.path.join(folder, "good.pmtiles")
        bad_path = os.path.join(folder, "bad.pmtiles")
        with open(source_path, "wb") as handle:
            handle.write(_build_archive(source_tiles, leaf_size=16))
        with open(good_path, "wb") as handle:
            handle.write(_build_archive(subset, leaf_size=8))

        spoiled = dict(subset)
        spoiled[(3, 4, 4)] = b"bytes the source never held"
        with open(bad_path, "wb") as handle:
            handle.write(_build_archive(spoiled, leaf_size=8))

        def run(extract):
            args = argparse.Namespace(
                source=source_path, extract=extract, samples=1000, seed=1,
                bbox="-180,-85,180,85", maxzoom=3)
            with contextlib.redirect_stdout(io.StringIO()) as captured:
                code = command_check(args)
            return code, captured.getvalue()

        code, _ = run(good_path)
        assert code == 0, "a faithful extract must pass"
        code, output = run(bad_path)
        assert code == 1, "a spoiled extract must fail"
        assert "z3/4/4" in output, output


def _test_check_fails_on_the_wrong_region():
    """The failure the old `check` could not see — and the reason for #496.

    Every tile in this extract is the source's own byte string; nothing in
    it is stale, truncated or corrupt. It is simply the WRONG HALF of the
    world. Sampling from what the extract holds — the only direction the
    first version had — passes it with every single sample matching, and
    the browser then shows a map that is blank exactly where somebody
    walks.

    Two guards in one: the eastern half must fail against a western bbox,
    and the full extract must still pass, so the coverage check cannot be
    satisfied by simply always failing.
    """
    source_tiles = _fixture_tiles()
    west_only = {key: value for key, value in source_tiles.items()
                 if key[0] <= 3 and key[1] < (1 << key[0]) / 2}
    everything = {key: value for key, value in source_tiles.items()
                  if key[0] <= 3}

    with tempfile.TemporaryDirectory() as folder:
        source_path = os.path.join(folder, "source.pmtiles")
        half_path = os.path.join(folder, "half.pmtiles")
        full_path = os.path.join(folder, "full.pmtiles")
        with open(source_path, "wb") as handle:
            handle.write(_build_archive(source_tiles, leaf_size=16))
        with open(half_path, "wb") as handle:
            handle.write(_build_archive(west_only, leaf_size=8))
        with open(full_path, "wb") as handle:
            handle.write(_build_archive(everything, leaf_size=8))

        def run(extract, bbox):
            args = argparse.Namespace(
                source=source_path, extract=extract, samples=400, seed=7,
                bbox=bbox, maxzoom=3)
            with contextlib.redirect_stdout(io.StringIO()) as captured:
                code = command_check(args)
            return code, captured.getvalue()

        # Asked for the whole world, given the western half.
        code, output = run(half_path, "-180,-85,180,85")
        assert code == 1, f"a half extract must fail coverage:\n{output}"
        assert "MISSING" in output, output
        # The same archive is correct for the area it really covers.
        code, output = run(half_path, "-180,-85,-1,85")
        assert code == 0, f"the western half must pass a western bbox:\n{output}"
        # And a complete extract must not be failed by the new direction.
        code, output = run(full_path, "-180,-85,180,85")
        assert code == 0, f"a complete extract must pass:\n{output}"


def _test_bbox_rejects_nonsense():
    """A typo must stop the run, not produce a plausible size.

    `lonlat_to_tile` clamps, and clamping is right — Web Mercator has no
    90th parallel. But clamping a TYPO turns `500,600,700,800` into a
    one-tile sliver at the edge of the world, for which `plan` reports a
    perfectly believable "fits (1 % of budget)". That number then decides
    the cut, and the cut decides where the map is blank.
    """
    assert parse_bbox("5.5,45.5,17.5,55.5") == (5.5, 45.5, 17.5, 55.5)
    for bad in ("500,600,700,800", "-181,45,17,55", "5,45,181,55",
                "5,-91,17,55", "5,45,17,91", "5,45,17", "a,b,c,d",
                "17.5,45.5,5.5,55.5"):
        try:
            parse_bbox(bad)
        except SystemExit:
            continue
        raise AssertionError(f"--bbox {bad} was accepted")


def _test_http_source_insists_on_range():
    """A server that ignores Range answers 200 with the whole file.

    Slicing that locally would look like success while pulling a hundred
    gigabytes through the pipe. The class must refuse instead, so this
    serves the same archive twice — once honouring Range, once ignoring it.
    """
    import http.server

    payload = _build_archive(_fixture_tiles(range(0, 3)), leaf_size=2)

    class Handler(http.server.BaseHTTPRequestHandler):
        honour_range = True

        def do_GET(self):  # noqa: N802 - named by the base class
            span = self.headers.get("Range")
            if span and self.honour_range:
                start, end = span.split("=", 1)[1].split("-")
                start, end = int(start), int(end)
                chunk = payload[start:end + 1]
                self.send_response(206)
                self.send_header("Content-Range",
                                 f"bytes {start}-{end}/{len(payload)}")
            else:
                chunk = payload
                self.send_response(200)
            self.send_header("Content-Length", str(len(chunk)))
            self.end_headers()
            self.wfile.write(chunk)

        def log_message(self, *_args):
            pass

    class Ignoring(Handler):
        honour_range = False

    def serve(handler):
        server = http.server.HTTPServer(("127.0.0.1", 0), handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        return server, f"http://127.0.0.1:{server.server_port}/a.pmtiles"

    server, url = serve(Handler)
    try:
        archive = Archive(HttpSource(url))
        assert archive.header.max_zoom == 2
        entry = archive.find(zxy_to_tile_id(2, 1, 1))
        assert archive.tile_bytes(entry) == b"tile 2/1/1"
        assert archive.source.bytes_read < len(payload), \
            "a Range read must not pull the whole archive"
    finally:
        server.shutdown()

    server, url = serve(Ignoring)
    try:
        try:
            Archive(HttpSource(url))
        except IOError as error:
            assert "206" in str(error), error
        else:
            raise AssertionError("a 200 answer must be refused, not sliced")
    finally:
        server.shutdown()


def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--self-test", action="store_true",
                        help="run the offline checks and exit")
    sub = parser.add_subparsers(dest="command")

    info = sub.add_parser("info", help="header, zoom range, bounds, layers")
    info.add_argument("--source", required=True)

    plan = sub.add_parser("plan", help="bytes per zoom for a bbox or region")
    plan.add_argument("--source", required=True)
    plan.add_argument("--bbox", help="west,south,east,north in degrees")
    plan.add_argument("--region",
                      help="GeoJSON with (Multi)Polygons, e.g. country borders")
    plan.add_argument("--select",
                      help="KEY=V1,V2: only the region's features with that property")
    plan.add_argument("--minzoom", type=int, default=0)
    plan.add_argument("--maxzoom", type=int, required=True)
    plan.add_argument("--max-bytes", type=int, default=RAW_FILE_LIMIT,
                      help=f"size budget per file (default {RAW_FILE_LIMIT})")

    check = sub.add_parser("check", help="compare an extract against its source")
    check.add_argument("--source", required=True)
    check.add_argument("--extract", required=True)
    # Beide sind Pflicht, obwohl der Auszug seine Bbox im Header trägt.
    # Genau den zu glauben hieße, den Verdächtigen nach seinem Alibi zu
    # fragen: Ein bei der falschen Bbox geschnittenes Archiv behauptet
    # widerspruchsfrei die falsche Bbox. Geprüft wird gegen das, was
    # bestellt war — `tool/map_areas.json`.
    check.add_argument("--bbox", required=True,
                       help="west,south,east,north the extract should cover")
    check.add_argument("--maxzoom", type=int, required=True,
                       help="highest zoom the extract was asked for")
    check.add_argument("--samples", type=int, default=24)
    check.add_argument("--seed", type=int, default=20260921)

    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if not args.command:
        parser.error("give a command, or --self-test")
    return {"info": command_info, "plan": command_plan,
            "check": command_check}[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
