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
  The raw rule the app ran in 0.143.0 (the riding position is the median
  of the last 60 s, a wheelie ends 5 deg under its start limit, over 60 s
  is a slipped mount) -- kept as the comparison since the app runs the
  fusion (0.144.0);
- the rider's answers (since 0.143.0): the app shows a banner after each
  wheelie it detects ("Stimmt" / "War keiner") and a button "Wheelie
  verpasst"; the file then holds e/l/m lines, and the report scores each
  threshold: hits, missed, false alarms, unlabelled. Since 0.144.0 (file
  v2) the same for jumps (j/k/n lines), and the head names the mount the
  app carried over from the last ride ("# mount,...", the fusion starts
  from it as the app did) and the sensors' range ("# range,...").

The sensor files carry coordinates and stay on the operator's computer,
NEVER in this repository. The report has times (seconds from the start
of the file), durations and counts only -- no coordinates.

With --fused the same file goes through the signal processing of
tool/sensor_fusion.py (concept section 3a): mount, attitude filter (the
error-state Kalman filter and Mahony side by side) and the events on the
fused values -- wheelies as pitch against the way, front up only, scored
against the same answers; flights with the landing along the bike's up
axis and an upright bike after it; and the probes of research section 6
(braking, corners, riding straight, gyro bias) next to the raw rule.

    python3 tool/airtime_measure.py --self-test
    python3 tool/airtime_measure.py ride.csv [--from S --to S] [--list] [--fused]
"""
from __future__ import annotations

import argparse
import bisect
import collections
import math
import statistics
import sys

import sensor_fusion

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
RELEASE_DEG = 5.0    # ends 5 deg under the start limit (15 -> 10)
BASE_WINDOW_S = 60.0
WARM_UP_S = 10.0
MAX_WHEELIE_S = 60.0
MISSED_WINDOW_S = 20.0  # "Wheelie verpasst" refers to the last 20 s
LOWPASS_S = 0.5


class Log:
    def __init__(self) -> None:
        self.a: list[tuple[float, float, float, float]] = []  # t_s, x, y, z
        self.w: list[tuple[float, float, float, float]] = []
        self.g: list[tuple[float, float]] = []  # t_s, speed m/s (no position kept)
        # What the app detected and what the rider answered (wheelie_notify.dart):
        self.events: list[tuple[float, float]] = []  # start s, duration s
        self.answers: dict[float, bool] = {}  # start s -> "Stimmt"
        self.missed: list[float] = []  # "Wheelie verpasst" pressed at s
        self.jumps: list[tuple[float, float]] = []  # the app's jumps, same shape
        self.jump_answers: dict[float, bool] = {}
        self.jump_missed: list[float] = []
        self.carried: tuple | None = None  # (up, forward) from "# mount,"
        self.range: tuple[float, float] | None = None  # accelerometer m/s^2, gyroscope rad/s
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
        if line.startswith("# mount,") or line.startswith("# range,"):
            try:
                values = [float(v) for v in line[8:].split(",")]
            except ValueError:
                continue
            if line[2] == "m" and len(values) == 6:
                log.carried = (tuple(values[:3]), tuple(values[3:]))
            elif line[2] == "r" and len(values) == 2:
                log.range = (values[0], values[1])
            continue
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
        elif kind == "e" and len(values) == 3:
            log.events.append((t, values[0]))
        elif kind == "l" and len(values) == 2:
            log.answers[round(values[0] / 1e6 - t0, 3)] = values[1] == 1
        elif kind == "m":
            log.missed.append(t)
        elif kind == "j" and len(values) == 3:
            log.jumps.append((t, values[0]))
        elif kind == "k" and len(values) == 2:
            log.jump_answers[round(values[0] / 1e6 - t0, 3)] = values[1] == 1
        elif kind == "n":
            log.jump_missed.append(t)
    log.a.sort()
    log.g.sort()
    log.events = [(round(t, 3), d) for t, d in log.events]
    log.jumps = [(round(t, 3), d) for t, d in log.jumps]
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


def _speed_before(log: Log, t: float) -> float:
    """The last GPS speed at or before t -- what the app knows at that moment."""
    i = bisect.bisect_right(log.g_times(), t) - 1
    return log.g[i][1] if i >= 0 else math.nan


def wheelies(log: Log, tilt_deg: float, min_s: float) -> list[dict]:
    """The raw rule of the app until 0.143.0, step by step:
    the riding position is the median gravity of the last BASE_WINDOW_S
    while riding and not tilted (none before WARM_UP_S of it); a wheelie
    starts at tilt_deg, ends below tilt_deg - RELEASE_DEG or below the
    speed, counts from min_s; longer than MAX_WHEELIE_S is a slipped
    mount (relearn, no wheelie)."""
    release = tilt_deg - RELEASE_DEG
    cap = int(BASE_WINDOW_S / 0.1)
    warm = int(WARM_UP_S / 0.1)
    base_samples: collections.deque = collections.deque(maxlen=cap)
    base = None
    since = 0
    out = []
    start = None
    for t, v in _lowpassed(log):
        speed = _speed_before(log, t)
        riding = not math.isnan(speed) and speed * 3.6 > WHEELIE_KMH
        u = _unit(v)
        angle = 0.0 if base is None else math.degrees(
            math.acos(max(-1.0, min(1.0, sum(p * q for p, q in zip(u, base))))))
        if start is not None:
            if riding and angle >= release:
                last = t
                peak = max(peak, angle)
                speeds.append(speed)
                axes.append(u)
                if t - start > MAX_WHEELIE_S:
                    start = None
                    base_samples.clear()
                    base = None
                continue
            if last - start >= min_s:
                mid = axes[len(axes) // 2]
                axis = _unit((ref[1] * mid[2] - ref[2] * mid[1],
                              ref[2] * mid[0] - ref[0] * mid[2],
                              ref[0] * mid[1] - ref[1] * mid[0]))
                out.append({"t": start, "duration": last - start,
                            "length_m": statistics.fmean(speeds) * (last - start),
                            "max_deg": peak, "axis": axis})
            start = None
            continue
        if riding and base is not None and angle >= tilt_deg:
            start = last = t
            peak = angle
            speeds = [speed]
            axes = [u]
            ref = base
            continue
        if riding and angle < release:
            base_samples.append(v)
            if len(base_samples) >= warm:
                since += 1
                if base is None or since >= 10:
                    since = 0
                    base = _unit(tuple(statistics.median(s[k] for s in base_samples) for k in range(3)))
    return out


def window(log: Log, start: float | None, end: float | None) -> Log:
    lo = -math.inf if start is None else start
    hi = math.inf if end is None else end
    cut = Log()
    # Keep SPEED_WINDOW_S of GPS around the window for the plausibility check.
    cut.a = [s for s in log.a if lo <= s[0] <= hi]
    cut.w = [s for s in log.w if lo <= s[0] <= hi]
    cut.g = [s for s in log.g if lo - SPEED_WINDOW_S <= s[0] <= hi + SPEED_WINDOW_S]
    cut.events = [e for e in log.events if lo <= e[0] <= hi]
    cut.answers = {t: v for t, v in log.answers.items() if lo <= t <= hi}
    cut.missed = [t for t in log.missed if lo <= t <= hi + MISSED_WINDOW_S]
    cut.jumps = [e for e in log.jumps if lo <= e[0] <= hi]
    cut.jump_answers = {t: v for t, v in log.jump_answers.items() if lo <= t <= hi}
    cut.jump_missed = [t for t in log.jump_missed if lo <= t <= hi + MISSED_WINDOW_S]
    cut.carried, cut.range = log.carried, log.range
    return cut


def feedback(log: Log, found: list[dict], jumps: bool = False) -> dict:
    """Score detected wheelies (or jumps) against the rider's answers in
    the app: an answered "Stimmt" is one, "War keiner" is none, and each
    press of "... verpasst" stands for one that ended in the
    MISSED_WINDOW_S before it. Unanswered app events count for nothing."""
    events, answers = (log.jumps, log.jump_answers) if jumps else (log.events, log.answers)
    marks = log.jump_missed if jumps else log.missed
    yes = [(t, t + d) for t, d in events if answers.get(t) is True]
    no = [(t, t + d) for t, d in events if answers.get(t) is False]
    def overlaps(w, iv):
        return w["t"] <= iv[1] and iv[0] <= w["t"] + w["duration"]
    hits = false_alarms = unlabelled = 0
    used_yes, used_marks = set(), set()
    for w in found:
        k = next((k for k, iv in enumerate(yes) if overlaps(w, iv) and k not in used_yes), None)
        if k is not None:
            used_yes.add(k); hits += 1; continue
        if any(overlaps(w, iv) for iv in no):
            false_alarms += 1; continue
        end = w["t"] + w["duration"]
        m = next((m for m, at in enumerate(marks)
                  if at - MISSED_WINDOW_S <= end <= at and m not in used_marks), None)
        if m is not None:
            used_marks.add(m); hits += 1
        else:
            unlabelled += 1
    missed = len(yes) - len(used_yes) + len(marks) - len(used_marks)
    return {"hits": hits, "missed": missed, "false_alarms": false_alarms, "unlabelled": unlabelled}


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
    if log.events or log.missed:
        answered = [t for t, _ in log.events if t in log.answers]
        lines.append("")
        lines.append(f"in the app: {len(log.events)} wheelies shown, "
                     f"{sum(1 for t in answered if log.answers[t])} \"Stimmt\", "
                     f"{sum(1 for t in answered if not log.answers[t])} \"War keiner\", "
                     f"{len(log.events) - len(answered)} unanswered; "
                     f"\"Wheelie verpasst\" pressed {len(log.missed)} times")
        lines.append("")
        lines.append("| tilt deg | min s | hits | missed | false alarms | unlabelled |")
        lines.append("|---|---|---|---|---|---|")
        for tilt in TILT_LIMITS_DEG:
            for min_s in MIN_WHEELIE_S:
                f = feedback(log, wheelies(log, tilt, min_s))
                lines.append(f"| {tilt:.0f} | {min_s} | {f['hits']} | {f['missed']} | "
                             f"{f['false_alarms']} | {f['unlabelled']} |")
    if listing:
        lines.append("")
        lines.append("flights at 0.3 g / 150 ms (t = s from the start of the file):")
        for f in flights(log, 0.3, 150):
            lines.append(f"  t={f['t']:8.2f}  {f['duration']:.2f} s  landing {f['peak_g']:.1f} g"
                         f"  {'plausible' if f['plausible'] else 'NOT plausible'}")
        lines.append("wheelies at 15 deg / 1 s:")
        for w in wheelies(log, 15.0, 1.0):
            axis = ", ".join(f"{c:+.2f}" for c in w["axis"])
            lines.append(f"  t={w['t']:8.2f}  {w['duration']:.1f} s  {w['length_m']:.1f} m  "
                         f"{w['max_deg']:.0f} deg  axis ({axis})")
    return "\n".join(lines)


def report_fused(log: Log, listing: bool) -> str:
    lines = []
    for method in ("eskf", "mahony"):
        fused = sensor_fusion.fuse(log.a, log.w, log.g, method, carried=log.carried)
        p = sensor_fusion.probes(fused)
        lines.append("")
        lines.append(f"fused ({method}):")
        def at(v):
            return "never" if v is None else f"{v:.0f} s"
        m = fused.mount
        carried = ("" if not m.carried else
                   f"carried over from the last ride, dropped at {at(m.dropped_at)}; ")
        lines.append(f"mount: {carried}up at {at(p['up_s'])}, forward at {at(p['fwd_s'])}, "
                     f"slips {p['slips']}; accelerometer left out {p['rejected']:.0%}")
        if log.range:
            lines.append(f"sensor range: accelerometer {log.range[0] / G:.1f} g, "
                         f"gyroscope {math.degrees(log.range[1]):.0f} deg/s")
        lines.append(f"gyro bias at the end {p['bias_dps']:.2f} deg/s, "
                     f"moved {p['bias_drift_dps']:.2f} deg/s in the second half")
        lines.append("")
        lines.append("p95 in degrees; \"gyro\" = off the gyro reference (3 s), \"way\" = off the way")
        lines.append("")
        lines.append("| probe | ticks | fused vs gyro | raw vs gyro | fused vs way | raw vs way |")
        lines.append("|---|---|---|---|---|---|")
        lines.append(f"| pitch, braking/accelerating | {p['brake_n']} | {p['brake_gyro']:.1f} | "
                     f"{p['brake_gyro_raw']:.1f} | {p['brake_pitch']:.1f} | {p['brake_raw']:.1f} |")
        lines.append(f"| pitch, corners | {p['curve_n']} | {p['curve_gyro']:.1f} | "
                     f"{p['curve_gyro_raw']:.1f} | {p['curve_pitch']:.1f} | {p['curve_raw']:.1f} |")
        lines.append(f"| roll, corners | {p['curve_n']} | {p['curve_roll_gyro']:.1f} | "
                     f"{p['curve_roll_gyro_raw']:.1f} | | |")
        lines.append(f"| pitch, all riding | | {p['riding_gyro']:.1f} | {p['riding_gyro_raw']:.1f} | "
                     f"{p['straight_pitch']:.1f} (straight) | |")
        lines.append("")
        scored = bool(log.events or log.missed)
        head = "| tilt deg | min s | wheelies | longest m |"
        lines.append(head + (" hits | missed | false alarms | unlabelled |" if scored else ""))
        lines.append("|---" * (4 + (4 if scored else 0)) + "|")
        for tilt in TILT_LIMITS_DEG:
            for min_s in MIN_WHEELIE_S:
                found = sensor_fusion.wheelies(fused, tilt, min_s)
                row = (f"| {tilt:.0f} | {min_s} | {len(found)} | "
                       f"{max((w['length_m'] for w in found), default=0):.1f} |")
                if scored:
                    f = feedback(log, found)
                    row += f" {f['hits']} | {f['missed']} | {f['false_alarms']} | {f['unlabelled']} |"
                lines.append(row)
        lines.append("")
        jumps = bool(log.jumps or log.jump_missed)
        if jumps:
            answered = [t for t, _ in log.jumps if t in log.jump_answers]
            lines.append(f"in the app: {len(log.jumps)} jumps shown, "
                         f"{sum(1 for t in answered if log.jump_answers[t])} \"Stimmt\", "
                         f"{sum(1 for t in answered if not log.jump_answers[t])} \"War keiner\", "
                         f"{len(log.jumps) - len(answered)} unanswered; "
                         f"\"Sprung verpasst\" pressed {len(log.jump_missed)} times")
            lines.append("")
        lines.append("| g limit | min ms | flights | plausible | upright | airtime s | longest s |"
                     + (" hits | missed | false alarms | unlabelled |" if jumps else ""))
        lines.append("|---" * (7 + (4 if jumps else 0)) + "|")
        for g_limit in G_LIMITS:
            for min_ms in MIN_FLIGHT_MS:
                found = sensor_fusion.flights(fused, g_limit, min_ms)
                ok = [f for f in found if f["plausible"]]
                row = (f"| {g_limit} | {min_ms} | {len(found)} | {len(ok)} | "
                       f"{sum(1 for f in found if f['upright'])} | "
                       f"{sum(f['duration'] for f in ok):.2f} | "
                       f"{max((f['duration'] for f in ok), default=0):.2f} |")
                if jumps:
                    f = feedback(log, found, jumps=True)
                    row += f" {f['hits']} | {f['missed']} | {f['false_alarms']} | {f['unlabelled']} |"
                lines.append(row)
        if listing:
            lines.append(f"wheelies ({method}) at 15 deg / 1 s against the way:")
            for w in sensor_fusion.wheelies(fused, 15.0, 1.0):
                answer = next((log.answers.get(t) for t, d in log.events
                               if w["t"] <= t + d and t <= w["t"] + w["duration"]), None)
                label = {True: "Stimmt", False: "War keiner", None: ""}[answer]
                lines.append(f"  t={w['t']:8.2f}  {w['duration']:.1f} s  {w['length_m']:.1f} m  "
                             f"{w['max_deg']:.0f} deg  {label}")
            lines.append(f"flights ({method}) at 0.3 g / 150 ms:")
            for f in sensor_fusion.flights(fused, 0.3, 150):
                answer = next((log.jump_answers.get(t) for t, d in log.jumps
                               if f["t"] <= t + d and t <= f["t"] + f["duration"]), None)
                label = {True: "  Stimmt", False: "  War keiner", None: ""}[answer]
                lines.append(f"  t={f['t']:8.2f}  {f['duration']:.2f} s  landing {f['peak_g']:.1f} g"
                             f"  {'plausible' if f['plausible'] else 'NOT plausible'}"
                             f"{'' if f['upright'] else ', not upright'}{label}")
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
    # The app's lines: the wheelie at 20 s answered "Stimmt", a made-up one
    # at 30 s answered "War keiner", one unanswered at 33 s, and "Wheelie
    # verpasst" pressed at 58 s (nothing the detector finds).
    rows.append(f"e,{base_us + 20_000_000},2.0,10.0,25.0")
    rows.append(f"l,{base_us + 25_000_000},{base_us + 20_000_000},1")
    rows.append(f"e,{base_us + 30_000_000},1.5,7.5,18.0")
    rows.append(f"l,{base_us + 31_000_000},{base_us + 30_000_000},0")
    rows.append(f"e,{base_us + 33_000_000},1.2,6.0,16.0")
    rows.append(f"m,{base_us + 58_000_000}")
    # File v2 (0.144.0): the jump at 10 s answered "Stimmt", "Sprung
    # verpasst" once, the mount carried over and the sensors' range.
    rows.insert(1, "# mount,0.0000,0.0000,1.0000,0.0000,1.0000,0.0000")
    rows.insert(2, "# range,78.453,34.907")
    rows.append(f"j,{base_us + 10_000_000},0.50,3.0,1")
    rows.append(f"k,{base_us + 12_000_000},{base_us + 10_000_000},1")
    rows.append(f"n,{base_us + 30_000_000}")
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
    assert w[0]["max_deg"] > 20, w
    assert len(log.events) == 3 and len(log.answers) == 2 and log.missed == [58.0]
    assert feedback(log, w) == {"hits": 1, "missed": 1, "false_alarms": 0, "unlabelled": 0}
    fake = {"t": 30.2, "duration": 1.0}
    assert feedback(log, [fake])["false_alarms"] == 1, "inside a \"War keiner\""
    late = {"t": 45.0, "duration": 1.0}
    assert feedback(log, [late])["hits"] == 1, "ends in the 20 s before \"verpasst\""
    assert feedback(log, [{"t": 33.0, "duration": 1.0}])["unlabelled"] == 1
    assert log.carried == ((0.0, 0.0, 1.0), (0.0, 1.0, 0.0)) and log.range == (78.453, 34.907)
    assert log.jumps == [(10.0, 0.5)] and log.jump_answers == {10.0: True} and log.jump_missed == [30.0]
    assert feedback(log, flights(log, 0.3, 150), jumps=True) == \
        {"hits": 1, "missed": 1, "false_alarms": 0, "unlabelled": 1}, "jump scored, the drop unlabelled"
    # Only one: the tilt at 50 s is standing still.
    cut = window(log, 0, 30)
    assert len(flights(cut, 0.3, 150)) == 1
    text = report(log, listing=True)
    assert "3 wheelies shown, 1 \"Stimmt\", 1 \"War keiner\", 1 unanswered" in text, text
    assert "7.0," not in text and "9.0," not in text, "no coordinates in the report"
    fused = report_fused(log, listing=True)
    assert "fused (eskf):" in fused and "fused (mahony):" in fused, fused
    assert "| pitch, braking/accelerating |" in fused and "hits |" in fused, fused
    assert "carried over from the last ride" in fused and "1 jumps shown, 1 \"Stimmt\"" in fused, fused
    assert "sensor range: accelerometer 8.0 g, gyroscope 2000 deg/s" in fused, fused
    print("airtime_measure self-test: ok")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("file", nargs="?")
    ap.add_argument("--from", dest="start", type=float, help="seconds from the start of the file")
    ap.add_argument("--to", dest="end", type=float)
    ap.add_argument("--list", action="store_true", help="list each flight and wheelie")
    ap.add_argument("--fused", action="store_true",
                    help="add the signal processing of tool/sensor_fusion.py")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        _self_test()
        return 0
    if not args.file:
        ap.error("a sensor log file is needed (or --self-test)")
    with open(args.file, encoding="utf-8") as f:
        log = parse(f)
    cut = window(log, args.start, args.end)
    print(report(cut, args.list))
    if args.fused:
        print(report_fused(cut, args.list))
    return 0


if __name__ == "__main__":
    sys.exit(main())
