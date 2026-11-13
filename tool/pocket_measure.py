#!/usr/bin/env python3
"""Tell a phone in the trouser pocket from a fixed mount (issue #491).

The sensor fusion (tool/sensor_fusion.py, docs/recherche-sensorfusion.md)
learns how the phone sits on the bike. In a pocket it moves with the
thigh on every pedal stroke: the fusion then learns a wrong mount, keeps
reporting it as slipped, saves it for the next ride, and the leg makes
wheelies, stoppies and short flights out of pedalling. This tool measures
the rule that recognises the pocket and prints the context of each
flight, so real jumps in the pocket can be told from the leg
(research section 11).

The rule, per 10 s window while riding (GPS > 8 km/h at both ends):

- vibration = standard deviation of |a| (m/s^2) -- on rough ground the
  bike itself rotates a lot, so only CALM windows (vibration under
  CALM_VIB) count;
- rotation = rms of the gyroscope low-passed over 0.15 s (rad/s) -- a
  mounted phone barely rotates on calm ground, a pocket swings with the
  leg;
- pocket = the median rotation of the last CALM_N calm windows is above
  POCKET_RAD.

Per flight of the fused listing (airtime_measure.py --fused --list,
Mahony): speed, grade over +-15 s from the GPS heights, rotation and
vibration in the 6 s before. The leg's flights come on flat ground while
pedalling with soft landings; jumps come downhill on rough ground with
hard ones.

The sensor files carry coordinates and stay on the operator's computer,
NEVER in this repository; the report has times, values and counts only.

    python3 tool/pocket_measure.py --self-test
    python3 tool/pocket_measure.py ride.csv [--windows] [--flights listing.txt]
"""
from __future__ import annotations

import bisect
import math
import re
import statistics
import sys

import sensor_fusion

WINDOW_S = 10.0
RIDING_KMH = 8.0
GYRO_LP_S = 0.15
CALM_VIB = 4.0        # m/s^2: calmer than this, the bike itself barely rotates
CALM_N = 12           # calm windows in the median (120 s of calm riding)
POCKET_RAD = 0.35     # rad/s: mounted 0.12-0.23, pocket 0.64-1.04 (medians, 2026-11)
POCKET_LANDING_G = 3.5  # proposal: in the pocket a flight counts only with this landing


def read(path: str):
    acc, gyro, fixes = [], [], []
    t0 = None
    with open(path) as fh:
        for line in fh:
            c = line[0]
            if c not in "agw":
                continue
            p = line.split(",")
            t = int(p[1]) / 1e6
            if c == "a":
                if t0 is None:
                    t0 = t
                acc.append((t, float(p[2]), float(p[3]), float(p[4])))
            elif c == "w":
                gyro.append((t, float(p[2]), float(p[3]), float(p[4])))
            else:
                alt = float(p[6]) if len(p) > 6 and p[6].strip() else math.nan
                fixes.append((t, float(p[5]), alt))
    t0 = t0 or 0.0
    shift = lambda rows: [(r[0] - t0,) + tuple(r[1:]) for r in rows]
    return shift(acc), shift(gyro), shift(fixes)


class Speed:
    def __init__(self, fixes) -> None:
        self.fixes = fixes
        self.t = [f[0] for f in fixes]

    def at(self, t: float) -> tuple:
        i = max(0, bisect.bisect_right(self.t, t) - 1)
        return self.fixes[i]

    def kmh(self, t: float) -> float:
        return self.at(t)[1] * 3.6 if self.fixes else 0.0


def rotation(gyro) -> float:
    """rms of the gyroscope low-passed over GYRO_LP_S (rad/s)."""
    lp = None
    ta = None
    total = 0.0
    for t, x, y, z in gyro:
        if lp is None:
            lp = [x, y, z]
        else:
            k = min(1.0, max(0.0, t - ta) / GYRO_LP_S)
            lp = [lp[0] + k * (x - lp[0]), lp[1] + k * (y - lp[1]), lp[2] + k * (z - lp[2])]
        ta = t
        total += lp[0] ** 2 + lp[1] ** 2 + lp[2] ** 2
    return math.sqrt(total / len(gyro)) if gyro else math.nan


def vibration(acc) -> float:
    n = [math.sqrt(x * x + y * y + z * z) for _, x, y, z in acc]
    return statistics.pstdev(n) if len(n) > 1 else math.nan


def windows(acc, gyro, fixes):
    """(start s, rotation rad/s, vibration m/s^2, km/h) per riding window."""
    speed = Speed(fixes)
    out = []
    end = max(acc[-1][0], gyro[-1][0]) if acc and gyro else 0.0
    at, wt = [a[0] for a in acc], [w[0] for w in gyro]
    t = 0.0
    while t + WINDOW_S <= end:
        a = acc[bisect.bisect_left(at, t):bisect.bisect_left(at, t + WINDOW_S)]
        w = gyro[bisect.bisect_left(wt, t):bisect.bisect_left(wt, t + WINDOW_S)]
        if (len(a) > 100 and len(w) > 100 and speed.kmh(t) > RIDING_KMH
                and speed.kmh(t + WINDOW_S) > RIDING_KMH):
            out.append((t, rotation(w), vibration(a), speed.kmh(t + WINDOW_S / 2)))
        t += WINDOW_S
    return out


def classify(rows):
    """Per riding window: True = pocket, False = mounted, None = not yet known."""
    calm = []
    out = []
    for _, rot, vib, _ in rows:
        if vib < CALM_VIB:
            calm.append(rot)
        out.append(statistics.median(calm[-CALM_N:]) > POCKET_RAD if len(calm) >= CALM_N else None)
    return out


def report(rows) -> list[str]:
    calm = [r[1] for r in rows if r[2] < CALM_VIB]
    states = classify(rows)
    known = [s for s in states if s is not None]
    first = next((rows[i][0] for i, s in enumerate(states) if s), None)
    lines = [f"{len(rows)} riding windows of {WINDOW_S:.0f} s, {len(calm)} calm (vibration < {CALM_VIB} m/s2)"]
    if calm:
        q = statistics.quantiles(calm, n=4) if len(calm) > 1 else [calm[0]] * 3
        lines.append(f"rotation in calm windows: p25 {q[0]:.2f}  median {q[1]:.2f}  p75 {q[2]:.2f} rad/s")
    if known:
        lines.append(f"pocket in {sum(known)}/{len(known)} windows with a decision"
                     + (f", first at {first:.0f} s" if first is not None else ""))
    else:
        lines.append(f"no decision: fewer than {CALM_N} calm windows")
    return lines


def flight_context(listing: str, acc, gyro, fixes) -> list[str]:
    """Context of each flight in an airtime_measure.py --fused --list output (Mahony)."""
    flights = []
    inside = False
    for line in open(listing):
        if line.startswith("flights (mahony)"):
            inside = True
            continue
        if inside and not line.startswith("  t="):
            break
        if inside:
            m = re.match(r"\s+t=\s*([\d.]+)\s+([\d.]+) s\s+landing ([\d.]+) g\s+(plausible|NOT plausible)\s*(.*)", line)
            if m:
                flights.append((float(m.group(1)), float(m.group(2)), float(m.group(3)),
                                m.group(4) == "plausible", m.group(5).strip(" ,")))
    speed = Speed(fixes)
    at, wt, ft = [a[0] for a in acc], [w[0] for w in gyro], [f[0] for f in fixes]
    lines = ["| t s | s | landing g | plausible | km/h | grade % | rotation | vibration | kept | answer |",
             "|---|---|---|---|---|---|---|---|---|---|"]
    for t, dur, land, plausible, answer in flights:
        a0, a1 = speed.at(t - 15)[2], speed.at(t + 15)[2]
        dist = sum(f[1] for f in fixes[bisect.bisect_left(ft, t - 15):bisect.bisect_left(ft, t + 15)])
        grade = (a1 - a0) / dist * 100 if dist > 20 else math.nan
        w = gyro[bisect.bisect_left(wt, t - 6):bisect.bisect_left(wt, t - 0.5)]
        a = acc[bisect.bisect_left(at, t - 6):bisect.bisect_left(at, t - 0.5)]
        kept = plausible and land >= POCKET_LANDING_G
        lines.append(f"| {t:.0f} | {dur:.2f} | {land:.1f} | {'yes' if plausible else 'no'} | "
                     f"{speed.kmh(t):.1f} | {grade:.1f} | {rotation(w):.2f} | {vibration(a):.1f} | "
                     f"{'yes' if kept else 'no'} | {answer} |")
    return lines


# ----------------------------------------------------------------- self-test

def synthetic(pocket: bool, seed: int):
    """A 25 min ride at 118 Hz: calm road, a rough descent in the middle.
    Mounted: small rotation, on the descent a lot. Pocket: the thigh swings
    at the cadence (1.3 Hz) while pedalling, everywhere but the descent.

    Drawn with sensor_fusion.Noise and whole microseconds, so the Dart test
    (test/rides/pocket_watch_test.dart) builds this very ride."""
    rnd = sensor_fusion.Noise(seed)
    acc, gyro, fixes = [], [], []
    n = 25 * 60 * 118
    for i in range(n):
        t = (i * 1000000 // 118) / 1e6
        rough = 600 <= t < 900
        pedalling = not rough
        vib = 6.0 if rough else 1.2
        a = 9.81 + rnd.gauss(vib)
        acc.append((t, 0.0, 0.0, a))
        # The bike's own rotation is slow (steering, pitching over roots),
        # so it survives the low pass; sensor noise on top does not.
        bike = (1.2 * math.sin(2 * math.pi * 0.7 * t), 1.0 * math.sin(2 * math.pi * 1.1 * t + 1),
                0.8 * math.sin(2 * math.pi * 0.4 * t + 2)) if rough else (
                0.1 * math.sin(2 * math.pi * 0.3 * t), 0.05 * math.sin(2 * math.pi * 0.5 * t), 0.0)
        swing = 1.4 * math.sin(2 * math.pi * 1.3 * t) if pocket and pedalling else 0.0
        gx = bike[0] + swing + rnd.gauss(0.3)
        gy = bike[1] + rnd.gauss(0.3)
        gz = bike[2] + rnd.gauss(0.3)
        gyro.append((t, gx, gy, gz))
    for s in range(25 * 60 + 1):
        fixes.append((float(s), 6.0 if s >= 5 else 0.0, 500.0 - (s * 0.6 if 600 <= s < 900 else 0)))
    return acc, gyro, fixes


def fingerprint(pocket: bool) -> list[str]:
    """What the Dart test compares: windows, first decision, a few values."""
    acc, gyro, fixes = synthetic(pocket, seed=491)
    rows = windows(acc, gyro, fixes)
    states = classify(rows)
    first = next((i for i, s in enumerate(states) if s is not None), None)
    lines = [f"{'pocket' if pocket else 'mounted'}: {len(rows)} windows, first decision at window {first} "
             f"({rows[first][0]:.0f} s) = {states[first]}, pocket in {sum(1 for s in states if s)}"]
    for i in (0, 1, 60, 70, len(rows) - 1):
        lines.append(f"  window {i}: start {rows[i][0]:.1f} rotation {rows[i][1]:.9f} vibration {rows[i][2]:.9f}")
    return lines


def _self_test() -> None:
    for pocket in (False, True):
        acc, gyro, fixes = synthetic(pocket, seed=491)
        rows = windows(acc, gyro, fixes)
        states = [s for s in classify(rows) if s is not None]
        assert states, "no decision"
        share = sum(states) / len(states)
        if pocket:
            assert share > 0.95, f"pocket recognised in only {share:.0%}"
        else:
            assert share == 0.0, f"mounted taken for a pocket in {share:.0%}"
        # Counter-probe: without the calm filter the rough descent alone
        # (~1.6 rad/s on the mount) would look like a pocket.
        rough = [r[1] for r in rows if r[2] >= CALM_VIB]
        if not pocket:
            assert rough and statistics.median(rough) > POCKET_RAD, "counter-probe: descent too calm"
    print("self-test ok")


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        _self_test()
        return 0
    if "--fingerprint" in argv:
        for pocket in (False, True):
            print("\n".join(fingerprint(pocket)))
        return 0
    paths = [a for a in argv if not a.startswith("--")]
    if not paths:
        print(__doc__)
        return 0
    acc, gyro, fixes = read(paths[0])
    rows = windows(acc, gyro, fixes)
    print("\n".join(report(rows)))
    if "--windows" in argv:
        for (t, rot, vib, kmh), s in zip(rows, classify(rows)):
            print(f"  {t:6.0f} s  rotation {rot:.2f}  vibration {vib:4.1f}  {kmh:4.1f} km/h  "
                  f"{'-' if s is None else ('pocket' if s else 'mounted')}")
    if "--flights" in argv:
        listing = argv[argv.index("--flights") + 1]
        print()
        print("\n".join(flight_context(listing, acc, gyro, fixes)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
