#!/usr/bin/env python3
"""Measure how well two GPX lines can be told to be "the same trail".

Phase 0 of TrailBuddy (docs/konzept-trails.md, section 4 and 11): before
any threshold is cast into SQL, the matching rules are run against real
recordings and the numbers are written down. Standard library only, like
the tools in PilzBuddy.

Input is a zip or a directory of GPX files. It is NEVER part of the
repository -- a ride starts at someone's front door. The path comes from
the command line or from TRAIL_GPX (environment). Everything the tool
prints to stdout or writes with --report is aggregated: track ids, counts,
distances, ratios. Names and coordinates go only into the file named by
--private-out, which the operator keeps next to the zip.

    python3 tool/trail_match.py --self-test
    TRAIL_GPX=~/somewhere/Trails.zip python3 tool/trail_match.py --report out.md

Pipeline per pair of tracks (see concept 4.2):
  1. bounding boxes must come closer than the widest corridor;
  2. both lines are resampled every STEP metres and, for every sample of
     A, the distance to the nearest segment of B is recorded (grid index);
     coverage(A->B, d) is the share of samples closer than d;
  3. direction: are the nearest points on B visited in increasing arc
     order (same direction), decreasing (reversed) or neither;
  4. for pairs that cover each other, the discrete Frechet distance on
     the (possibly reversed) samples THAT LIE IN THE CORRIDOR -- the test
     that tells a hairpin trail from its parallel neighbour, which
     coverage alone cannot. Samples outside the corridor are dropped on
     both sides first: a single GPS spur or a coarsely drawn corner
     would otherwise push the maximum, and the first run against real
     files showed exactly that (same-named trails at 40-90 m Frechet,
     coverage 0.85-1.0).
"""
from __future__ import annotations

import argparse
import math
import os
import statistics
import sys
import zipfile
from urllib.parse import unquote
from dataclasses import dataclass, field
from datetime import datetime
from xml.etree import ElementTree as ET

R_EARTH = 6371000.0
STEP = 5.0                # resampling step in metres
CORRIDORS = (10.0, 15.0, 20.0, 25.0)
COVERAGES = (0.7, 0.8, 0.9)
DEFAULT_D = 15.0
DEFAULT_COV = 0.8
FRECHET_FACTOR = 2.0      # "same" needs frechet <= factor * d
FRECHET_D = DEFAULT_D      # corridor used to trim samples before Frechet
FRECHET_MAX_POINTS = 1200  # cap for the O(n*m) DP
MIN_TRAIL_M = 50.0
PLANNED_SPEED_KMH = 60.0  # faster than this on a bike: not a recording


# ----------------------------------------------------------------- parsing

@dataclass
class Track:
    tid: str
    name: str
    lat: list[float]
    lon: list[float]
    ele: list[float | None]
    time: list[datetime | None]
    length_m: float = 0.0
    gain_m: float = 0.0
    loss_m: float = 0.0
    hairpins: int = 0
    source: str = "import"   # 'import' | 'planned'
    xy: list[tuple[float, float]] = field(default_factory=list, repr=False)
    bbox: tuple[float, float, float, float] = (0, 0, 0, 0)

    @property
    def n(self) -> int:
        return len(self.lat)


def _parse_time(text: str | None) -> datetime | None:
    if not text:
        return None
    text = text.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(text)
    except ValueError:
        return None


def parse_gpx(raw: bytes, tid: str, fallback_name: str) -> Track | None:
    try:
        root = ET.fromstring(raw)
    except ET.ParseError:
        return None
    ns = root.tag.split("}")[0].strip("{") if root.tag.startswith("{") else ""
    q = (lambda t: f"{{{ns}}}{t}") if ns else (lambda t: t)
    name_el = root.find(f".//{q('trk')}/{q('name')}")
    name = (name_el.text or "").strip() if name_el is not None else ""
    pts = root.findall(f".//{q('trkpt')}") or root.findall(f".//{q('rtept')}")
    if len(pts) < 2:
        return None
    lat, lon, ele, tim = [], [], [], []
    for p in pts:
        try:
            la, lo = float(p.get("lat")), float(p.get("lon"))
        except (TypeError, ValueError):
            continue
        if lat and abs(la - lat[-1]) < 1e-9 and abs(lo - lon[-1]) < 1e-9:
            continue  # duplicate point (Locus writes them at pauses)
        lat.append(la)
        lon.append(lo)
        e = p.find(q("ele"))
        ele.append(float(e.text) if e is not None and e.text else None)
        t = p.find(q("time"))
        tim.append(_parse_time(t.text if t is not None else None))
    if len(lat) < 2:
        return None
    tr = Track(tid, unquote(name or fallback_name), lat, lon, ele, tim)
    _derive(tr)
    return tr


def name_key(name: str) -> str:
    """Names as ground truth for duplicates: case, spaces, punctuation folded."""
    base = name.lower().replace(".gpx", "")
    return "".join(ch for ch in base if ch.isalnum())


def haversine(la1, lo1, la2, lo2) -> float:
    p1, p2 = math.radians(la1), math.radians(la2)
    dphi = p2 - p1
    dl = math.radians(lo2 - lo1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R_EARTH * math.asin(math.sqrt(a))


def _derive(tr: Track) -> None:
    tr.length_m = sum(haversine(tr.lat[i], tr.lon[i], tr.lat[i + 1], tr.lon[i + 1])
                      for i in range(tr.n - 1))
    eles = [e for e in tr.ele if e is not None]
    if len(eles) == tr.n:
        tr.gain_m = sum(max(0.0, tr.ele[i + 1] - tr.ele[i]) for i in range(tr.n - 1))
        tr.loss_m = sum(max(0.0, tr.ele[i] - tr.ele[i + 1]) for i in range(tr.n - 1))
    tr.bbox = (min(tr.lat), min(tr.lon), max(tr.lat), max(tr.lon))
    tr.source = "planned" if looks_planned(tr) else "import"
    tr.xy = project(tr, statistics.fmean(tr.lat))
    tr.hairpins = count_hairpins(resample(tr.xy, 10.0))


def looks_planned(tr: Track) -> bool:
    """No usable timestamps, or speeds no bicycle reaches: a drawn route."""
    stamps = [t for t in tr.time if t is not None]
    if len(set(stamps)) < 2:
        return True
    speeds = []
    for i in range(tr.n - 1):
        a, b = tr.time[i], tr.time[i + 1]
        if a is None or b is None:
            continue
        dt = (b - a).total_seconds()
        if dt <= 0:
            continue
        speeds.append(haversine(tr.lat[i], tr.lon[i], tr.lat[i + 1], tr.lon[i + 1]) / dt * 3.6)
    if not speeds:
        return True
    return statistics.median(speeds) > PLANNED_SPEED_KMH


# ---------------------------------------------------------------- geometry

def project(tr: Track, lat0: float) -> list[tuple[float, float]]:
    """Equirectangular metres around lat0; exact enough within one pair."""
    k = math.cos(math.radians(lat0))
    return [(math.radians(lo) * R_EARTH * k, math.radians(la) * R_EARTH) for la, lo in zip(tr.lat, tr.lon)]


def resample(xy: list[tuple[float, float]], step: float) -> list[tuple[float, float]]:
    """Points every `step` metres along the polyline, first and last kept.

    Locus exports are thinned to ~13 m and drawn routes have 100 m legs;
    a corridor test on the raw vertices would miss the line between them.
    """
    if len(xy) < 2:
        return list(xy)
    out = [xy[0]]
    carry = 0.0
    for (x1, y1), (x2, y2) in zip(xy, xy[1:]):
        seg = math.hypot(x2 - x1, y2 - y1)
        if seg == 0:
            continue
        pos = step - carry
        while pos <= seg:
            t = pos / seg
            out.append((x1 + t * (x2 - x1), y1 + t * (y2 - y1)))
            pos += step
        carry = seg - (pos - step)
    if out[-1] != xy[-1]:
        out.append(xy[-1])
    return out


def polyline_length(xy) -> float:
    return sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(xy, xy[1:]))


def count_hairpins(xy, turn_deg: float = 150.0, window_m: float = 30.0) -> int:
    """Heading reversals within a short window: switchbacks."""
    if len(xy) < 3:
        return 0
    headings = [math.atan2(b[1] - a[1], b[0] - a[0]) for a, b in zip(xy, xy[1:])]
    step = polyline_length(xy) / max(1, len(xy) - 1)
    span = max(1, int(window_m / max(step, 1e-9)))
    count, i = 0, 0
    while i + span < len(headings):
        d = abs((headings[i + span] - headings[i] + math.pi) % (2 * math.pi) - math.pi)
        if math.degrees(d) >= turn_deg:
            count += 1
            i += span
        else:
            i += 1
    return count


class SegmentGrid:
    """Uniform grid over the segments of a polyline for nearest-segment queries."""

    def __init__(self, xy: list[tuple[float, float]], cell: float):
        self.xy = xy
        self.cell = cell
        self.cells: dict[tuple[int, int], list[int]] = {}
        self.arc = [0.0]
        for i, (a, b) in enumerate(zip(xy, xy[1:])):
            self.arc.append(self.arc[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
            for cx in range(int(min(a[0], b[0]) // cell), int(max(a[0], b[0]) // cell) + 1):
                for cy in range(int(min(a[1], b[1]) // cell), int(max(a[1], b[1]) // cell) + 1):
                    self.cells.setdefault((cx, cy), []).append(i)

    def nearest(self, p: tuple[float, float], radius: float) -> tuple[float, float]:
        """(distance, arc position of the nearest point) or (inf, nan)."""
        cx, cy = int(p[0] // self.cell), int(p[1] // self.cell)
        reach = int(math.ceil(radius / self.cell))
        best, best_arc = math.inf, math.nan
        for dx in range(-reach, reach + 1):
            for dy in range(-reach, reach + 1):
                for i in self.cells.get((cx + dx, cy + dy), ()):
                    d, t = _point_segment(p, self.xy[i], self.xy[i + 1])
                    if d < best:
                        best = d
                        best_arc = self.arc[i] + t * (self.arc[i + 1] - self.arc[i])
        return best, best_arc


def _point_segment(p, a, b) -> tuple[float, float]:
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    if l2 == 0:
        return math.hypot(p[0] - ax, p[1] - ay), 0.0
    t = max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / l2))
    return math.hypot(p[0] - (ax + t * dx), p[1] - (ay + t * dy)), t


def frechet(P, Q) -> float:
    """Discrete Frechet distance, two-row DP."""
    n, m = len(P), len(Q)
    prev = [math.inf] * m
    for i in range(n):
        cur = [math.inf] * m
        for j in range(m):
            d = math.hypot(P[i][0] - Q[j][0], P[i][1] - Q[j][1])
            if i == 0 and j == 0:
                cur[j] = d
            else:
                best = math.inf
                if i > 0:
                    best = min(best, prev[j])
                if j > 0:
                    best = min(best, cur[j - 1])
                if i > 0 and j > 0:
                    best = min(best, prev[j - 1])
                cur[j] = max(best, d)
        prev = cur
    return prev[-1]


# ---------------------------------------------------------------- matching

@dataclass
class PairResult:
    a: Track
    b: Track
    dists_ab: list[float]     # per sample of A: distance to B
    dists_ba: list[float]
    direction: str            # 'same' | 'reversed' | 'mixed'
    frechet_m: float | None   # only for candidates of "same"

    def coverage(self, d: float) -> tuple[float, float]:
        ab = sum(1 for x in self.dists_ab if x <= d) / len(self.dists_ab)
        ba = sum(1 for x in self.dists_ba if x <= d) / len(self.dists_ba)
        return ab, ba

    def classify(self, d: float = DEFAULT_D, cov: float = DEFAULT_COV) -> str:
        ab, ba = self.coverage(d)
        if ab >= cov and ba >= cov:
            if self.frechet_m is not None and self.frechet_m > FRECHET_FACTOR * d:
                return "neighbour"      # covers, but the sequence does not follow
            return "same" if self.direction != "reversed" else "same-reversed"
        if ab >= cov:
            return "a-in-b"
        if ba >= cov:
            return "b-in-a"
        if max(ab, ba) >= 0.3:
            return "fork"
        return "different"


def bbox_close(a: Track, b: Track, margin_m: float) -> bool:
    dlat = margin_m / 111_320.0
    dlon = margin_m / (111_320.0 * math.cos(math.radians((a.bbox[0] + a.bbox[2]) / 2)))
    return not (a.bbox[2] + dlat < b.bbox[0] or b.bbox[2] + dlat < a.bbox[0]
                or a.bbox[3] + dlon < b.bbox[1] or b.bbox[3] + dlon < a.bbox[1])


def _direction(arcs: list[float]) -> str:
    diffs = [b - a for a, b in zip(arcs, arcs[1:]) if not (math.isnan(a) or math.isnan(b))]
    if len(diffs) < 3:
        return "mixed"
    up = sum(1 for x in diffs if x > 0) / len(diffs)
    if up >= 0.7:
        return "same"
    if up <= 0.3:
        return "reversed"
    return "mixed"


def compare(a: Track, b: Track, max_d: float = max(CORRIDORS)) -> PairResult | None:
    if not bbox_close(a, b, max_d):
        return None
    lat0 = (statistics.fmean(a.lat) + statistics.fmean(b.lat)) / 2
    axy, bxy = project(a, lat0), project(b, lat0)
    ra, rb = resample(axy, STEP), resample(bxy, STEP)
    ga, gb = SegmentGrid(axy, max_d), SegmentGrid(bxy, max_d)
    near_ab = [gb.nearest(p, max_d) for p in ra]
    near_ba = [ga.nearest(p, max_d) for p in rb]
    dists_ab = [d for d, _ in near_ab]
    dists_ba = [d for d, _ in near_ba]
    if min(dists_ab) > max_d and min(dists_ba) > max_d:
        return None
    arcs = [arc for d, arc in near_ab if d <= max_d]
    direction = _direction(arcs)
    fr = None
    ab = sum(1 for x in dists_ab if x <= max_d) / len(dists_ab)
    ba = sum(1 for x in dists_ba if x <= max_d) / len(dists_ba)
    if ab >= min(COVERAGES) and ba >= min(COVERAGES):
        step = max(STEP, max(polyline_length(axy), polyline_length(bxy)) / FRECHET_MAX_POINTS)
        pa = [p for p in resample(axy, step) if gb.nearest(p, FRECHET_D)[0] <= FRECHET_D]
        pb = [p for p in resample(bxy, step) if ga.nearest(p, FRECHET_D)[0] <= FRECHET_D]
        if direction == "reversed":
            pb = pb[::-1]
        fr = frechet(pa, pb) if len(pa) >= 2 and len(pb) >= 2 else math.inf
    return PairResult(a, b, dists_ab, dists_ba, direction, fr)


# ----------------------------------------------------------------- loading

def load_tracks(path: str) -> list[Track]:
    tracks: list[Track] = []
    if os.path.isdir(path):
        names = sorted(f for f in os.listdir(path) if f.lower().endswith(".gpx"))
        blobs = [(n, open(os.path.join(path, n), "rb").read()) for n in names]
    else:
        with zipfile.ZipFile(path) as z:
            names = [n for n in z.namelist() if n.lower().endswith(".gpx")]
            blobs = [(n, z.read(n)) for n in names]
    for i, (n, raw) in enumerate(blobs):
        tr = parse_gpx(raw, f"T{i + 1:03d}", os.path.basename(n))
        if tr is not None:
            tracks.append(tr)
    return tracks


# ------------------------------------------------------------------ report

def fmt_pct(x: float) -> str:
    return f"{100 * x:.0f} %"


def run(tracks: list[Track], report_path: str | None, private_path: str | None) -> str:
    pairs: list[PairResult] = []
    for i in range(len(tracks)):
        for j in range(i + 1, len(tracks)):
            r = compare(tracks[i], tracks[j])
            if r is not None:
                pairs.append(r)

    lines: list[str] = []
    w = lines.append
    w("## Bestand")
    w("")
    n = len(tracks)
    lens = sorted(t.length_m for t in tracks)
    w(f"- Tracks: {n}, davon ohne verwertbare Zeiten oder mit Fahrradfremden Geschwindigkeiten (`planned`): "
      f"{sum(1 for t in tracks if t.source == 'planned')}")
    w(f"- Länge: Median {statistics.median(lens):.0f} m, kürzeste {lens[0]:.0f} m, längste {lens[-1] / 1000:.1f} km")
    for th in (MIN_TRAIL_M, 500, 1000, 3000, 10000):
        w(f"  - bis {th:.0f} m: {sum(1 for l in lens if l <= th)}")
    w(f"- Punktabstand (Median je Track, Median darüber): "
      f"{statistics.median(t.length_m / max(1, t.n - 1) for t in tracks):.1f} m")
    w(f"- Höhen: {sum(1 for t in tracks if all(e is not None for e in t.ele))} Tracks vollständig")
    desc = sum(1 for t in tracks if t.loss_m > 2 * t.gain_m)
    w(f"- Abfahrtsdominiert (Verlust > 2 × Gewinn): {desc} ({fmt_pct(desc / n)})")
    short_desc = sum(1 for t in tracks if t.length_m < 3000 and t.loss_m > 2 * t.gain_m)
    w(f"- „Kurz und bergab“ (< 3 km und Verlust > 2 × Gewinn, Importregel 5.2): {short_desc} ({fmt_pct(short_desc / n)})")
    w(f"- Tracks mit Kehren (Richtungsumkehr ≥ 150° binnen 30 m): {sum(1 for t in tracks if t.hairpins > 0)}, "
      f"Kehren insgesamt: {sum(t.hairpins for t in tracks)}")
    w("")
    w("Abfahrtsdominierte Tracks nach Länge (wo endet „Trail“, wo beginnt „Fahrt“?):")
    w("")
    w("| Länge | abfahrtsdominiert | übrige |")
    w("|---|---|---|")
    edges = [(0, 1000), (1000, 3000), (3000, 5000), (5000, 8000), (8000, 15000), (15000, 1e9)]
    for lo, hi in edges:
        sel = [t for t in tracks if lo <= t.length_m < hi]
        label = f"{lo / 1000:g}–{hi / 1000:g} km" if hi < 1e8 else f"ab {lo / 1000:g} km"
        w(f"| {label} | {sum(1 for t in sel if t.loss_m > 2 * t.gain_m)} | {sum(1 for t in sel if not t.loss_m > 2 * t.gain_m)} |")
    w("")
    w("## Paare")
    w("")
    w(f"- Paare mit sich berührenden Hüllen (Rand {max(CORRIDORS):.0f} m) und mindestens einem Punkt im Korridor: {len(pairs)}")
    w("")
    w("### Einordnung nach Korridor und Deckungsschwelle")
    w("")
    w("Zeile = Korridor `d`, Spalte = Deckung; Zelle = gleich / gleich-gegen / Nachbar (deckt, Fréchet scheitert) / Teil / Gabel.")
    w("")
    w("| d | " + " | ".join(f"cov ≥ {c}" for c in COVERAGES) + " |")
    w("|---|" + "---|" * len(COVERAGES))
    for d in CORRIDORS:
        cells = []
        for c in COVERAGES:
            cls = [p.classify(d, c) for p in pairs]
            cells.append(f"{cls.count('same')} / {cls.count('same-reversed')} / {cls.count('neighbour')} / "
                         f"{cls.count('a-in-b') + cls.count('b-in-a')} / {cls.count('fork')}")
        w(f"| {d:.0f} m | " + " | ".join(cells) + " |")
    w("")
    same = [p for p in pairs if p.classify().startswith("same")]
    w(f"### Bei den Startwerten (d = {DEFAULT_D:.0f} m, Deckung ≥ {DEFAULT_COV})")
    w("")
    w(f"- gleich: {sum(1 for p in same if p.classify() == 'same')}, "
      f"gleich in Gegenrichtung: {sum(1 for p in same if p.classify() == 'same-reversed')}, "
      f"Nachbar: {sum(1 for p in pairs if p.classify() == 'neighbour')}, "
      f"Teil: {sum(1 for p in pairs if p.classify() in ('a-in-b', 'b-in-a'))}, "
      f"Gabel: {sum(1 for p in pairs if p.classify() == 'fork')}")
    if same:
        frs = sorted(p.frechet_m for p in same if p.frechet_m is not None)
        w(f"- Fréchet der Gleichen: Median {statistics.median(frs):.1f} m, 90. Perzentil {frs[int(0.9 * (len(frs) - 1))]:.1f} m, Maximum {frs[-1]:.1f} m")
        hp = sum(1 for p in same if p.a.hairpins > 0 or p.b.hairpins > 0)
        w(f"- Gleiche Paare, an denen ein Track mit Kehren beteiligt ist: {hp}")
        lr = sorted(max(p.a.length_m, p.b.length_m) / max(1.0, min(p.a.length_m, p.b.length_m)) for p in same)
        w(f"- Längenverhältnis der Gleichen: Median {statistics.median(lr):.2f}, Maximum {lr[-1]:.2f}")
    nb = [p for p in pairs if p.classify() == "neighbour"]
    if nb:
        w(f"- Nachbar-Paare: Fréchet {', '.join(f'{p.frechet_m:.0f}' for p in nb[:12])} m")
    # Frechet threshold sensitivity for pairs covering both ways at default d/cov
    cover = [p for p in pairs if all(x >= DEFAULT_COV for x in p.coverage(DEFAULT_D)) and p.frechet_m is not None]
    if cover:
        w("")
        w("### Fréchet-Schwelle bei beidseitiger Deckung (d = 15 m, ≥ 0,8)")
        w("")
        w("| Fréchet ≤ | Paare |")
        w("|---|---|")
        for f in (15, 20, 30, 45, 60, 100, 1e9):
            w(f"| {('∞' if f > 1e8 else f'{f:.0f} m')} | {sum(1 for p in cover if p.frechet_m <= f)} |")
    # Distribution of mutual coverage: is there a natural gap?
    w("")
    w("### Verteilung der beidseitigen Deckung (min(cov_ab, cov_ba) bei d = 15 m)")
    w("")
    w("| min. Deckung | Paare |")
    w("|---|---|")
    mins = [min(p.coverage(DEFAULT_D)) for p in pairs]
    for lo, hi in ((0.3, 0.5), (0.5, 0.7), (0.7, 0.8), (0.8, 0.9), (0.9, 1.01)):
        w(f"| {lo:.1f} – {min(hi, 1.0):.1f} | {sum(1 for m in mins if lo <= m < hi)} |")
    # Names as ground truth: same folded name means the operator meant
    # the same trail (URL-encoded copies, re-exports).
    w("")
    w("### Namensgleiche Paare als Bodenwahrheit")
    w("")
    keys: dict[str, list[Track]] = {}
    for t in tracks:
        keys.setdefault(name_key(t.name), []).append(t)
    name_pairs = {(x.tid, y.tid) for group in keys.values() for i, x in enumerate(group) for y in group[i + 1:]}
    by_pair = {(p.a.tid, p.b.tid): p for p in pairs}
    found = {k: by_pair[k].classify() for k in name_pairs if k in by_pair}
    w(f"- Paare mit gleichem gefaltetem Namen: {len(name_pairs)}; davon geometrisch überhaupt benachbart: {len(found)}")
    for cls in ("same", "same-reversed", "neighbour", "a-in-b", "b-in-a", "fork", "different"):
        c = sum(1 for v in found.values() if v == cls)
        if c:
            w(f"  - eingeordnet als {cls}: {c}")
    diff_name_same = sum(1 for p in same if name_key(p.a.name) != name_key(p.b.name))
    w(f"- Als gleich erkannte Paare mit VERSCHIEDENEN Namen: {diff_name_same} (der Fall „ein Trail, zwei Namen“ aus dem Konzept)")
    # tracks involved in duplicates
    dup_ids = {p.a.tid for p in same} | {p.b.tid for p in same}
    w("")
    w(f"- Tracks, die in mindestens einem Gleich-Paar stecken: {len(dup_ids)} von {n} ({fmt_pct(len(dup_ids) / n)})")
    text = "\n".join(lines) + "\n"
    if report_path:
        with open(report_path, "w", encoding="utf-8") as f:
            f.write(text)
    if private_path:
        with open(private_path, "w", encoding="utf-8") as f:
            f.write("klasse\tid_a\tid_b\tname_a\tname_b\tcov_ab\tcov_ba\trichtung\tfrechet_m\tlen_a\tlen_b\n")
            for p in sorted(pairs, key=lambda p: p.classify()):
                ab, ba = p.coverage(DEFAULT_D)
                cls = p.classify()
                if cls == "different":
                    continue
                f.write(f"{cls}\t{p.a.tid}\t{p.b.tid}\t{p.a.name}\t{p.b.name}\t{ab:.2f}\t{ba:.2f}\t{p.direction}\t"
                        f"{'' if p.frechet_m is None else f'{p.frechet_m:.0f}'}\t{p.a.length_m:.0f}\t{p.b.length_m:.0f}\n")
            f.write("\n# tracks\nid\tname\tlen_m\tsource\thairpins\n")
            for t in tracks:
                f.write(f"{t.tid}\t{t.name}\t{t.length_m:.0f}\t{t.source}\t{t.hairpins}\n")
    return text


# --------------------------------------------------------------- self-test

def _synthetic(points_xy, lat0=48.0, lon0=9.0, jitter=0.0, seed=1, name="", tid="S") -> Track:
    import random
    rnd = random.Random(seed)
    k = math.cos(math.radians(lat0))
    lat, lon = [], []
    for x, y in points_xy:
        jx = rnd.gauss(0, jitter) if jitter else 0.0
        jy = rnd.gauss(0, jitter) if jitter else 0.0
        lat.append(lat0 + math.degrees((y + jy) / R_EARTH))
        lon.append(lon0 + math.degrees((x + jx) / (R_EARTH * k)))
    tr = Track(tid, name, lat, lon, [500.0 - 0.1 * i for i in range(len(lat))], [None] * len(lat))
    _derive(tr)
    return tr


def _line(length, step=10.0, x0=0.0, y0=0.0, dx=1.0, dy=0.0):
    n = int(length / step)
    return [(x0 + i * step * dx, y0 + i * step * dy) for i in range(n + 1)]


def _switchbacks(legs=6, leg=80.0, gap=15.0, step=5.0, x0=0.0):
    """Zig-zag: legs of `leg` metres, alternating direction, `gap` apart."""
    pts = []
    y = 0.0
    for k in range(legs):
        xs = [x0 + i for i in _frange(0, leg, step)] if k % 2 == 0 else [x0 + leg - i for i in _frange(0, leg, step)]
        pts += [(x, y) for x in xs]
        y -= gap
    return pts


def _frange(a, b, s):
    out, v = [], a
    while v <= b + 1e-9:
        out.append(v)
        v += s
    return out


def self_test() -> int:
    fails = []

    def expect(cond, msg):
        if not cond:
            fails.append(msg)

    base = _synthetic(_line(1000), name="base")
    again = _synthetic(_line(1000), jitter=5.0, seed=7, name="again")
    rev = _synthetic(_line(1000)[::-1], jitter=5.0, seed=3, name="rev")
    parallel = _synthetic(_line(1000, y0=40.0), name="parallel40")
    half = _synthetic(_line(500), jitter=3.0, seed=5, name="half")
    ride = _synthetic(_line(600, x0=-600) + _line(1000)[1:] + _line(800, x0=1000)[1:], name="ride")
    fork = _synthetic(_line(500) + _line(500, x0=500, dx=0.6, dy=0.8)[1:], name="fork")
    far = _synthetic(_line(1000, y0=5000), name="far")

    r = compare(base, again)
    expect(r is not None and r.classify() == "same", f"jittered copy should be same, got {r and r.classify()}")
    expect(r is not None and r.frechet_m is not None and r.frechet_m < 30, f"frechet of jittered copy too large: {r and r.frechet_m}")
    r = compare(base, rev)
    expect(r is not None and r.classify() == "same-reversed", f"reversed copy should be same-reversed, got {r and r.classify()}")
    r = compare(base, parallel)
    expect(r is None or r.classify() == "different", f"parallel 40 m must not match, got {r and r.classify()}")
    r = compare(base, half)
    expect(r is not None and r.classify() == "b-in-a", f"half should be b-in-a, got {r and r.classify()}")
    r = compare(base, ride)
    expect(r is not None and r.classify() == "a-in-b", f"trail inside ride should be a-in-b, got {r and r.classify()}")
    r = compare(base, fork)
    expect(r is not None and r.classify() == "fork", f"fork should be fork, got {r and r.classify()}")
    expect(compare(base, far) is None, "far track must be filtered by bbox")

    # Switchbacks: the same zig-zag re-recorded must match; the zig-zag
    # shifted by one leg (parallel legs 15 m apart) covers but must be
    # caught by Frechet as a neighbour, not the same trail.
    zz = _synthetic(_switchbacks(), name="zz")
    expect(zz.hairpins >= 4, f"hairpin counter sees {zz.hairpins} on a 6-leg zig-zag")
    zz2 = _synthetic(_switchbacks(), jitter=3.0, seed=11, name="zz2")
    r = compare(zz, zz2)
    expect(r is not None and r.classify() == "same", f"re-recorded switchbacks should be same, got {r and r.classify()}")
    shifted = _synthetic([(x, y - 15.0) for x, y in _switchbacks()], name="zz-shifted")
    r = compare(zz, shifted)
    ab, ba = r.coverage(DEFAULT_D) if r else (0, 0)
    expect(r is not None and min(ab, ba) >= 0.7, f"shifted switchbacks should cover by corridor alone (got {ab:.2f}/{ba:.2f})")
    expect(r is not None and r.classify() == "neighbour", f"shifted switchbacks must be neighbour by Frechet, got {r and r.classify()}")

    # Planned-route detection
    expect(base.source == "planned", "track without times must be planned")
    timed = _synthetic(_line(1000), name="timed")
    from datetime import timedelta, timezone
    t0 = datetime(2026, 1, 1, tzinfo=timezone.utc)
    timed.time = [t0 + timedelta(seconds=2 * i) for i in range(timed.n)]  # 10 m / 2 s = 18 km/h
    expect(not looks_planned(timed), "18 km/h ride must not be planned")
    timed.time = [t0 + timedelta(milliseconds=100 * i) for i in range(timed.n)]  # 360 km/h
    expect(looks_planned(timed), "360 km/h must be planned")

    # Resampling keeps length and endpoints
    rs = resample(_line(1000, step=100.0), 5.0)
    expect(abs(polyline_length(rs) - 1000) < 1e-6 and len(rs) == 201, f"resample: {len(rs)} points, {polyline_length(rs):.1f} m")

    # Frechet sanity
    expect(abs(frechet([(0, 0), (1, 0)], [(0, 1), (1, 1)]) - 1.0) < 1e-9, "frechet of parallel unit lines is 1")

    # Simulation (#106): "same" is not transitive. X and Y overlap 900 m
    # of 1000, Y and C 850 m, X and C only 750 m. Compared with the best
    # recording alone (X, the older of equal quality), C starts a second
    # trail; compared with every recording, it joins Y's trail.
    sx = _synthetic(_line(1000), name="x", tid="S1")
    sy = _synthetic(_line(1000, x0=100.0), name="y", tid="S2")
    sc = _synthetic(_line(1000, x0=250.0), name="c", tid="S3")
    expect(import_kind(sx) == "trail", f"a short downhill line is a trail, got {import_kind(sx)}")
    one, every = simulate([sx, sy, sc], 1), simulate([sx, sy, sc], None)
    expect((one.trails, one.attached) == (2, 1), f"best-1: 2 trails, 1 attached, got {one.trails}/{one.attached}")
    expect((every.trails, every.attached) == (1, 2), f"all: 1 trail, 2 attached, got {every.trails}/{every.attached}")

    if fails:
        for f in fails:
            print("FAIL:", f, file=sys.stderr)
        return 1
    print("self-test ok")
    return 0


# -------------------------------------------------------------------- main

# -------------------------------------------------------------- simulate

TRAIL_MAX_M = 8000.0       # import rule (concept 5.2): shorter and mostly
                           # downhill is a trail, the rest is a ride
QUALITY = {"app": 0.6, "import": 0.4, "planned": 0.1}


def import_kind(tr: Track) -> str:
    """The app's import rule (classifyTrack): fragment, trail or ride."""
    if tr.length_m < MIN_TRAIL_M:
        return "fragment"
    if tr.length_m >= TRAIL_MAX_M:
        return "ride"
    if tr.gain_m == 0 and tr.loss_m == 0 and any(e is None for e in tr.ele):
        return "trail"      # without elevation the length decides
    return "trail" if tr.loss_m > 2 * tr.gain_m else "ride"


@dataclass
class SimResult:
    reps: int | None       # representatives per trail; None = all
    contributed: int
    trails: int
    attached: int
    twin_events: int       # candidate "same" as two or more trails
    twin_pairs: int        # distinct trail pairs seen as twins
    name_groups: int       # names that occur on 2+ trail-like files
    name_split: int        # of those: files that ended on another trail
                           # than the first file of their name


def simulate(tracks: list[Track], reps: int | None) -> SimResult:
    """Contribute the trail-like files one after another, the way
    contribute_recording does: compare against the best `reps`
    recordings of every trail in reach (quality desc, older first),
    attach on "same" to the trail with the highest two-sided coverage,
    else a new trail. Order: first timestamp, files without one last.

    Duplicates are measured by name: files with the same folded name are
    meant as the same trail by the operator; each one that ends on a
    different trail than the first of its name is a duplicate the
    matcher did not see (an upper bound -- same names can be variants).
    """
    cands = [t for t in tracks if import_kind(t) == "trail"]
    cands.sort(key=lambda t: (min((x for x in t.time if x is not None), default=None) is None,
                              min((x for x in t.time if x is not None), default=datetime.max)
                              if any(x is not None for x in t.time) else datetime.max, t.tid))
    trails: list[list[Track]] = []      # recordings per trail, in contribution order
    trail_of: dict[str, int] = {}
    attached = twin_events = 0
    twin_pairs: set[tuple[int, int]] = set()
    for c in cands:
        matches: dict[int, float] = {}
        for i, recs in enumerate(trails):
            ranked = sorted(recs, key=lambda r: -QUALITY[r.source])  # stable: older first
            pool = ranked if reps is None else ranked[:reps]
            best = -1.0
            for r in pool:
                res = compare(c, r)
                if res is None:
                    continue
                if res.classify().startswith("same"):
                    best = max(best, min(res.coverage(DEFAULT_D)))
            if best >= 0:
                matches[i] = best
        if matches:
            target = max(matches, key=lambda k: matches[k])
            trails[target].append(c)
            attached += 1
            if len(matches) > 1:
                twin_events += 1
                ids = sorted(matches)
                for x in range(len(ids)):
                    for y in range(x + 1, len(ids)):
                        twin_pairs.add((ids[x], ids[y]))
        else:
            target = len(trails)
            trails.append([c])
        trail_of[c.tid] = target
    groups: dict[str, list[Track]] = {}
    for c in cands:
        groups.setdefault(name_key(c.name), []).append(c)
    multi = [g for g in groups.values() if len(g) > 1]
    split = sum(1 for g in multi for t in g[1:] if trail_of[t.tid] != trail_of[g[0].tid])
    return SimResult(reps, len(cands), len(trails), attached, twin_events, len(twin_pairs),
                     len(multi), split)


def simulate_report(tracks: list[Track], reps_list: list[int | None]) -> str:
    rows = [simulate(tracks, r) for r in reps_list]
    out = ["| Vertreter je Trail | beigesteuert | Trails | angehängt | Zwillings-Ereignisse | "
           "Zwillings-Paare | Namen mehrfach | davon auf anderem Trail |",
           "|---|---|---|---|---|---|---|---|"]
    for r in rows:
        out.append(f"| {'alle' if r.reps is None else r.reps} | {r.contributed} | {r.trails} | "
                   f"{r.attached} | {r.twin_events} | {r.twin_pairs} | {r.name_groups} | {r.name_split} |")
    return "\n".join(out)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("path", nargs="?", default=os.environ.get("TRAIL_GPX"),
                    help="zip or directory of GPX files (default: $TRAIL_GPX)")
    ap.add_argument("--report", help="write the aggregated markdown report here")
    ap.add_argument("--private-out", help="write the pair table WITH names here (never into the repo)")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--simulate", metavar="N,N,…",
                    help="contribute the trail-like files in order like contribute_recording, "
                         "comparing against the best N recordings per trail ('all' = every one); "
                         "prints an aggregated table")
    args = ap.parse_args(argv)
    if args.self_test:
        return self_test()
    if not args.path:
        ap.error("no input: pass a path or set TRAIL_GPX")
    tracks = load_tracks(args.path)
    if not tracks:
        print("no tracks found", file=sys.stderr)
        return 1
    if args.simulate:
        reps = [None if x.strip() == "all" else int(x) for x in args.simulate.split(",")]
        print(simulate_report(tracks, reps))
        return 0
    print(run(tracks, args.report, args.private_out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
