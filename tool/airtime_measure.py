#!/usr/bin/env python3
"""Measure the airtime and wheelie thresholds from raw sensor logs (issue #36).

The dev app writes accelerometer and gyroscope at 100 Hz plus GPS every
second while a ride is recorded (switch "Sensor-Rohdaten mitschreiben",
lib/features/rides/sensor_log.dart). This tool reads such a file and
measures, BEFORE any detection is built into the app (concept
docs/konzept-airtime.md section 8):

- flight phases: |a| below a g limit for at least a minimum duration,
  swept over the start values of section 2 (0.3 g, 150 ms) and their
  neighbours; per phase the landing peak within 300 ms and whether it is
  plausible (>= 10 km/h by GPS in the 3 s before AND after, peak under
  8 g) -- the four conditions of section 2 without "on the trail line",
  which needs the trail and stays with the app;
- wheelies/manuals: the low-passed gravity vector tilted away from the
  riding position (median over the ride at > 8 km/h) by at least a
  limit for at least a duration at > 8 km/h; length = GPS speed x time.
  The tilt axis is printed in phone coordinates: wheelies should share
  one axis (the bike's lateral axis), a lean in a corner shows another.

The sensor files carry coordinates and stay on the operator's computer,
NEVER in this repository. The report has times (seconds from the start
of the file), durations and counts only -- no coordinates.

    python3 tool/airtime_measure.py --self-test
    python3 tool/airtime_measure.py ride.csv [--from S --to S] [--list]
"""
from __future__ import annotations

import argparse
import bisect
import collections
import math
import statistics
import sys

G = 9.80665
G_LIMITS = (0.2, 0.3, 0.4, 0.5)       # start value 0.3 g (concept 2)
MIN_FLIGHT_MS = (100, 150, 200, 250)  # start value 150 ms
LANDING_WINDOW_S = 0.3
PLAUSIBLE_KMH = 10.0
SPEED_WINDOW_S = 3.0
PEAK_MAX_G = 8.0
TILT_LIMITS_DEG = (10.0, 15.0, 20.0)  # start value 15 deg (concept 2)
MIN_WHEELIE_S = (0.5, 1.0, 2.0)
WHEELIE_KMH = 8.0
LOWPASS_S = 0.5


class Log:
    def __init__(self) -> None:
        self.a: list[tuple[float, float, float, float]] = []  # t_s, x, y, z
        self.w: list[tuple[float, float, float, float]] = []
        self.g: list[tuple[float, float]] = []  # t_s, speed m/s (no position kept)
        self._g_times: list[float] | None = None

    def g_times(self) -> list[float]:
        if self._g_times is None or len(self._g_times) != len(self.g):
            self._g_times = [t for t, _ in self.g]
        return self._g_times


def parse(lines) -> Log:
    log = Log()
    t0 = None
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(",")
        try:
            kind, t = parts[0], int(parts[1]) / 1e6
            values = [float(v) if v else math.nan for v in parts[2:]]
        except (ValueError, IndexError):
            continue
        if t0 is None:
            t0 = t
        t -= t0
        if kind == "a" and len(values) == 3:
            log.a.append((t, *values))
        elif kind == "w" and len(values) == 3:
            log.w.append((t, *values))
        elif kind == "g" and len(values) == 5:
            log.g.append((t, values[3]))  # speed only
    log.a.sort()
    log.g.sort()
    return log


def _speeds_between(log: Log, start: float, end: float) -> list[float]:
    times = log.g_times()
    i = bisect.bisect_left(times, start)
    j = bisect.bisect_right(times, end)
    return [s for _, s in log.g[i:j] if not math.isnan(s)]


def _riding(log: Log, start: float, end: float, kmh: float) -> bool:
    speeds = _speeds_between(log, start, end)
    return bool(speeds) and min(speeds) * 3.6 >= kmh


def flights(log: Log, g_limit: float, min_ms: float) -> list[dict]:
    """Contiguous samples with |a| < g_limit lasting >= min_ms."""
    out = []
    start = None
    a = log.a
    for i, (t, x, y, z) in enumerate(a):
        low = math.sqrt(x * x + y * y + z * z) / G < g_limit
        if low and start is None:
            start = i
        if (not low or i == len(a) - 1) and start is not None:
            end = i if not low else i + 1
            t_start, t_end = a[start][0], a[end - 1][0] if end - 1 > start else a[start][0]
            duration = (a[end][0] if end < len(a) else t_end) - t_start
            if duration * 1000 >= min_ms:
                peak = 0.0
                for pt, px, py, pz in a[end:]:
                    if pt - t_start - duration > LANDING_WINDOW_S:
                        break
                    peak = max(peak, math.sqrt(px * px + py * py + pz * pz) / G)
                before = _riding(log, t_start - SPEED_WINDOW_S, t_start, PLAUSIBLE_KMH)
                after = _riding(log, t_start + duration, t_start + duration + SPEED_WINDOW_S, PLAUSIBLE_KMH)
                out.append({
                    "t": t_start, "duration": duration, "peak_g": peak,
                    "plausible": before and after and peak < PEAK_MAX_G,
                })
            start = None
    return out


def _lowpassed(log: Log) -> list[tuple[float, tuple[float, float, float]]]:
    """Mean gravity vector over LOWPASS_S windows, one per window step of 0.1 s."""
    out = []
    sx = sy = sz = 0.0
    n = 0
    queue: collections.deque[tuple[float, float, float, float]] = collections.deque()
    next_t = 0.0
    for sample in log.a:
        queue.append(sample)
        sx += sample[1]; sy += sample[2]; sz += sample[3]; n += 1
        while queue and sample[0] - queue[0][0] > LOWPASS_S:
            old = queue.popleft()
            sx -= old[1]; sy -= old[2]; sz -= old[3]; n -= 1
        if sample[0] >= next_t and n:
            out.append((sample[0], (sx / n, sy / n, sz / n)))
            next_t = sample[0] + 0.1
    return out


def _unit(v):
    norm = math.sqrt(sum(c * c for c in v))
    return tuple(c / norm for c in v) if norm else (0.0, 0.0, 0.0)


def _speed_at(log: Log, t: float) -> float:
    times = log.g_times()
    i = bisect.bisect_left(times, t)
    best = [log.g[k] for k in (i - 1, i) if 0 <= k < len(log.g)]
    if not best:
        return math.nan
    return min(best, key=lambda e: abs(e[0] - t))[1]


def wheelies(log: Log, tilt_deg: float, min_s: float) -> list[dict]:
    lp = _lowpassed(log)
    riding = [v for t, v in lp if _speed_at(log, t) * 3.6 > WHEELIE_KMH]
    if not riding:
        return []
    base = _unit(tuple(statistics.median(v[k] for v in riding) for k in range(3)))
    out = []
    start = None
    for i, (t, v) in enumerate(lp):
        u = _unit(v)
        angle = math.degrees(math.acos(max(-1.0, min(1.0, sum(p * q for p, q in zip(u, base))))))
        tilted = angle >= tilt_deg and _speed_at(log, t) * 3.6 > WHEELIE_KMH
        if tilted and start is None:
            start = i
        if (not tilted or i == len(lp) - 1) and start is not None:
            end = i if not tilted else i + 1
            t0, t1 = lp[start][0], lp[end - 1][0]
            if t1 - t0 >= min_s:
                mid = _unit(lp[(start + end - 1) // 2][1])
                axis = _unit((base[1] * mid[2] - base[2] * mid[1],
                              base[2] * mid[0] - base[0] * mid[2],
                              base[0] * mid[1] - base[1] * mid[0]))
                speeds = [_speed_at(log, lp[k][0]) for k in range(start, end)]
                length = statistics.fmean(s for s in speeds if not math.isnan(s)) * (t1 - t0)
                out.append({"t": t0, "duration": t1 - t0, "length_m": length, "axis": axis})
            start = None
    return out


def window(log: Log, start: float | None, end: float | None) -> Log:
    lo = -math.inf if start is None else start
    hi = math.inf if end is None else end
    cut = Log()
    # Keep SPEED_WINDOW_S of GPS around the window for the plausibility check.
    cut.a = [s for s in log.a if lo <= s[0] <= hi]
    cut.w = [s for s in log.w if lo <= s[0] <= hi]
    cut.g = [s for s in log.g if lo - SPEED_WINDOW_S <= s[0] <= hi + SPEED_WINDOW_S]
    return cut


def report(log: Log, listing: bool) -> str:
    lines = []
    span = log.a[-1][0] - log.a[0][0] if log.a else 0.0
    rate = len(log.a) / span if span else 0.0
    lines.append(f"accelerometer {len(log.a)} samples over {span:.0f} s ({rate:.0f} Hz), "
                 f"gyroscope {len(log.w)}, GPS {len(log.g)}")
    gaps = sum(1 for p, q in zip(log.a, log.a[1:]) if q[0] - p[0] > 0.1)
    lines.append(f"gaps > 100 ms in the accelerometer: {gaps}")
    lines.append("")
    lines.append("| g limit | min ms | flights | plausible | airtime s | longest s |")
    lines.append("|---|---|---|---|---|---|")
    for g_limit in G_LIMITS:
        for min_ms in MIN_FLIGHT_MS:
            found = flights(log, g_limit, min_ms)
            ok = [f for f in found if f["plausible"]]
            lines.append(f"| {g_limit} | {min_ms} | {len(found)} | {len(ok)} | "
                         f"{sum(f['duration'] for f in ok):.2f} | "
                         f"{max((f['duration'] for f in ok), default=0):.2f} |")
    lines.append("")
    lines.append("| tilt deg | min s | wheelies | longest m |")
    lines.append("|---|---|---|---|")
    for tilt in TILT_LIMITS_DEG:
        for min_s in MIN_WHEELIE_S:
            found = wheelies(log, tilt, min_s)
            lines.append(f"| {tilt:.0f} | {min_s} | {len(found)} | "
                         f"{max((w['length_m'] for w in found), default=0):.1f} |")
    if listing:
        lines.append("")
        lines.append("flights at 0.3 g / 150 ms (t = s from the start of the file):")
        for f in flights(log, 0.3, 150):
            lines.append(f"  t={f['t']:8.2f}  {f['duration']:.2f} s  landing {f['peak_g']:.1f} g"
                         f"  {'plausible' if f['plausible'] else 'NOT plausible'}")
        lines.append("wheelies at 15 deg / 1 s:")
        for w in wheelies(log, 15.0, 1.0):
            axis = ", ".join(f"{c:+.2f}" for c in w["axis"])
            lines.append(f"  t={w['t']:8.2f}  {w['duration']:.1f} s  {w['length_m']:.1f} m  axis ({axis})")
    return "\n".join(lines)


# -------------------------------------------------------------- self-test

def _synthetic() -> list[str]:
    """60 s at 100 Hz, phone flat (gravity on z), riding 5 m/s except where noted:
    a 0.5 s jump at 10 s landing with 3 g; a 2 s wheelie (25 deg about x) at 20 s;
    a phone dropped at 45 s while standing (speed 0 from 40 s); the bike leant
    against a tree at 50 s (25 deg while standing) -- no wheelie."""
    rows = ["# trailbuddy sensor log v1"]
    base_us = 1_700_000_000_000_000
    for i in range(6000):
        t = i / 100
        x, y, z = 0.0, 0.0, G
        if 10.0 <= t < 10.5 or 45.0 <= t < 45.4:
            x, y, z = 0.1, 0.0, 0.5
        elif 10.5 <= t < 10.55:
            z = 3 * G
        elif 45.4 <= t < 45.45:
            z = 4 * G
        elif 20.0 <= t < 22.0 or 50.0 <= t < 53.0:
            angle = math.radians(25)
            y, z = G * math.sin(angle), G * math.cos(angle)
        rows.append(f"a,{base_us + int(t * 1e6)},{x:.4f},{y:.4f},{z:.4f}")
        rows.append(f"w,{base_us + int(t * 1e6) + 500},0.0,0.0,0.0")
    for s in range(61):
        speed = 0.0 if s >= 40 else 5.0
        rows.append(f"g,{base_us + s * 1_000_000},7.0,9.0,4.0,{speed},800.0")
    return rows


def _self_test() -> None:
    log = parse(_synthetic())
    assert len(log.a) == 6000 and len(log.g) == 61
    found = flights(log, 0.3, 150)
    assert len(found) == 2, found
    jump, drop = found
    assert abs(jump["t"] - 10.0) < 0.02 and abs(jump["duration"] - 0.5) < 0.02, jump
    assert abs(jump["peak_g"] - 3.0) < 0.01 and jump["plausible"], jump
    assert not drop["plausible"], "a phone dropped while standing is no landing"
    assert not flights(log, 0.3, 600), "min duration filters"
    assert len(flights(log, 0.05, 150)) == 0, "g limit filters (0.5 m/s^2 is above 0.05 g)"
    w = wheelies(log, 15.0, 1.0)
    assert len(w) == 1, w
    assert abs(w[0]["t"] - 20.0) < 0.6 and 1.0 <= w[0]["duration"] <= 2.2, w
    assert abs(w[0]["length_m"] - 5.0 * w[0]["duration"]) < 0.5, w
    assert abs(abs(w[0]["axis"][0]) - 1.0) < 0.05, "tilt about the phone's x axis"
    assert not wheelies(log, 30.0, 1.0), "25 deg stays under 30"
    # Only one: the tilt at 50 s is standing still.
    cut = window(log, 0, 30)
    assert len(flights(cut, 0.3, 150)) == 1
    text = report(log, listing=True)
    assert "7.0," not in text and "9.0," not in text, "no coordinates in the report"
    print("airtime_measure self-test: ok")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("file", nargs="?")
    ap.add_argument("--from", dest="start", type=float, help="seconds from the start of the file")
    ap.add_argument("--to", dest="end", type=float)
    ap.add_argument("--list", action="store_true", help="list each flight and wheelie")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        _self_test()
        return 0
    if not args.file:
        ap.error("a sensor log file is needed (or --self-test)")
    with open(args.file, encoding="utf-8") as f:
        log = parse(f)
    print(report(window(log, args.start, args.end), args.list))
    return 0


if __name__ == "__main__":
    sys.exit(main())
