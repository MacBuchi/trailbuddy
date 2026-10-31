#!/usr/bin/env python3
"""Signal processing for airtime, wheelie and max G (issue #36, step 3).

The architecture of docs/konzept-airtime.md section 3a, researched in
docs/recherche-sensorfusion.md, in three stages that each stand alone:

1. Mount (seconds to minutes): learns how the phone sits on the bike --
   "up" from gravity while riding straight and steadily, "forward" from
   the horizontal force while braking and accelerating (sign from the GPS
   speed) and from the lean in corners (sign from the yaw rate; on the
   rides of 2026-10-30 the corners did most of it), and a slipped mount
   when gravity stays away from "up" while the bike rides on normally
   (braking, accelerating, corners) -- a wheelie ends by turning back
   down instead, however long it lasts. The mount of the last ride can be
   carried over (the app writes it into the head of the file); five quiet
   seconds tilted away from it drop it again.
2. Attitude filter (every sample): an error-state Kalman filter after
   Sola (arXiv:1711.02508) with 6 error states (attitude, gyro bias),
   predicted with the gyroscope on the sensor's own time stamps; the
   accelerometer supports the attitude only after the bike model is
   taken off (along: dv/dt from GPS; across: speed x yaw rate), with an
   adaptive uncertainty (vibration, |f| away from g, innovation gate).
   Mahony's filter with the same correction runs as the comparison; on
   both rides the two agree within a degree (docs/recherche-sensorfusion.md
   section 7).
3. Events on the fused values: wheelie = pitch against the way (the way
   is the pitch low-passed over a few seconds), front up only; flight =
   filtered |f| under a limit, plausible by speed and by an upright bike
   after it; landing = the peak along the bike's up axis.

The filter looks up to one second ahead for dv/dt (GPS comes once a
second): the app runs it on a short buffer, a banner a second later is
fine. Pure Python on purpose -- the same arithmetic is ported to Dart in
step 4 and checked against the same synthetic rides.

Phone axes are Android's (x right, y up the screen, z out of the screen;
the accelerometer reads +g upwards at rest). Bike axes: x forward, y left,
z up. Quaternions are Hamilton (w, x, y, z), q maps phone to world.

    python3 tool/sensor_fusion.py --self-test
    python3 tool/airtime_measure.py ride.csv --fused   (the report)
"""
from __future__ import annotations

import bisect
import math
import statistics
import sys

G = 9.80665
EZ = (0.0, 0.0, 1.0)

# Mount (stage 1), evaluated once per GPS fix over the second before it.
MOUNT_MIN_MPS = 2.2           # ~8 km/h
QUIET_DVDT = 0.3              # m/s^2: "steady"
QUIET_YAW = 0.1               # rad/s: "straight"
QUIET_FORCE = 0.6             # m/s^2: | |f| - g | while steady
UP_TICKS = 5                  # quiet seconds before "up" stands
UP_DECAY = 0.995              # per quiet second, ~200 s memory
LONG_DVDT = 0.8               # m/s^2: braking or accelerating
LONG_YAW = 0.15
LEAN_YAW = 0.15               # rad/s: a corner that teaches "forward" by the lean
FWD_TICKS = 5
FWD_CONSISTENCY = 0.5         # |sum| / sum of |terms|: one direction, not noise
TILTED_RAD = 0.3              # gravity this far from "up" teaches nothing (wheelie)
SLIP_RAD = 0.5                # this far ...
SLIP_TICKS = 5                # ... for this many seconds of braking, accelerating
                              # or corners = slipped (no time limit: a wheelie
                              # can hold 40 deg for minutes, but rides straight)

# Attitude filter (stage 2).
# Swept on both rides of 2026-10-30 against the gyro reference: the phone's
# gyro is far better than the accelerometer on a bike (bias < 0.1 deg/s).
GYRO_NOISE = 0.005            # rad/s/sqrt(Hz)
BIAS_WALK = 1e-6              # rad/s^2/sqrt(Hz)
ACC_NOISE = 6.0               # m/s^2, the floor of the adaptive uncertainty
VIB_S = 0.25                  # window of the vibration estimate
GATE_LOW, GATE_HIGH = 0.6, 1.4  # |f_corr| in g outside this: no update
NIS_GATE = 12.0               # innovation beyond this inflates the noise
MAHONY_KP, MAHONY_KI = 2.0, 0.1    # swept on the synthetic ride
MAHONY_FLOOR = 0.5            # m/s^2: full weight below this much extra noise
MODEL_TRUST = 0.5             # share of the bike model counted as noise

# Events (stage 3).
TICK_S = 0.1
ROAD_S = 3.0                  # pitch low-passed over this is the way
HOLD_DEG = 10.0               # the way holds still while the front is this high
RIDING_KMH = 8.0
RELEASE_DEG = 5.0
FLIGHT_SMOOTH_S = 0.04
LANDING_WINDOW_S = 0.3
PLAUSIBLE_KMH = 10.0
SPEED_WINDOW_S = 3.0
PEAK_MAX_G = 8.0
UPRIGHT_AFTER_S = 1.0
UPRIGHT_PITCH_DEG = 30.0
UPRIGHT_ROLL_DEG = 45.0


# ------------------------------------------------------------ vectors

def add(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def scale(a, k): return (a[0] * k, a[1] * k, a[2] * k)
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def norm(a): return math.sqrt(dot(a, a))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def unit(a):
    n = norm(a)
    return scale(a, 1.0 / n) if n > 1e-12 else (0.0, 0.0, 0.0)


def angle(a, b):
    return math.acos(max(-1.0, min(1.0, dot(unit(a), unit(b)))))


def mv(m, v):
    return (dot(m[0], v), dot(m[1], v), dot(m[2], v))


def mtv(m, v):
    """m^T v."""
    return (m[0][0] * v[0] + m[1][0] * v[1] + m[2][0] * v[2],
            m[0][1] * v[0] + m[1][1] * v[1] + m[2][1] * v[2],
            m[0][2] * v[0] + m[1][2] * v[1] + m[2][2] * v[2])


def mm(a, b):
    return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))


def mt(a):
    return tuple(tuple(a[j][i] for j in range(3)) for i in range(3))


def madd(a, b, k=1.0):
    return tuple(tuple(a[i][j] + k * b[i][j] for j in range(3)) for i in range(3))


def skew(v):
    return ((0.0, -v[2], v[1]), (v[2], 0.0, -v[0]), (-v[1], v[0], 0.0))


def diag(d):
    return ((d, 0.0, 0.0), (0.0, d, 0.0), (0.0, 0.0, d))


def inv3(m):
    a, b, c = m[0]
    d, e, f = m[1]
    g, h, i = m[2]
    det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    k = 1.0 / det
    return (((e * i - f * h) * k, (c * h - b * i) * k, (b * f - c * e) * k),
            ((f * g - d * i) * k, (a * i - c * g) * k, (c * d - a * f) * k),
            ((d * h - e * g) * k, (b * g - a * h) * k, (a * e - b * d) * k))


ZERO3 = diag(0.0)


def _symmetric(m):
    return tuple(tuple((m[i][j] + m[j][i]) / 2 for j in range(3)) for i in range(3))


# --------------------------------------------------------- quaternions

def qmul(p, q):
    pw, px, py, pz = p
    qw, qx, qy, qz = q
    return (pw * qw - px * qx - py * qy - pz * qz,
            pw * qx + px * qw + py * qz - pz * qy,
            pw * qy - px * qz + py * qw + pz * qx,
            pw * qz + px * qy - py * qx + pz * qw)


def qexp(v):
    """The rotation by the vector v (axis * angle) as a quaternion."""
    a = norm(v)
    if a < 1e-12:
        return (1.0, v[0] / 2, v[1] / 2, v[2] / 2)
    s = math.sin(a / 2) / a
    return (math.cos(a / 2), v[0] * s, v[1] * s, v[2] * s)


def qnorm(q):
    n = math.sqrt(sum(c * c for c in q))
    return tuple(c / n for c in q)


def qrot(q):
    w, x, y, z = q
    return ((1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)),
            (2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)),
            (2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)))


def q_from_gravity(f):
    """The attitude whose world z is the measured up f (yaw left at 0)."""
    u = unit(f)
    # Shortest rotation taking the phone's u to world z.
    axis = cross(u, EZ)
    s = norm(axis)
    if s < 1e-9:
        return (1.0, 0.0, 0.0, 0.0) if u[2] > 0 else (0.0, 1.0, 0.0, 0.0)
    return qexp(scale(axis, math.atan2(s, dot(u, EZ)) / s))


def rot_between(a, b):
    """Rotation matrix taking direction a to direction b."""
    axis = cross(unit(a), unit(b))
    s = norm(axis)
    if s < 1e-12:
        return diag(1.0)
    return qrot(qexp(scale(axis, math.atan2(s, dot(unit(a), unit(b))) / s)))


# ------------------------------------------------------ stage 1: mount

class Mount:
    """Phone -> bike axes, learned while riding (concept 3a, research 3)."""

    def __init__(self, carried: tuple | None = None) -> None:
        self.up = None   # bike up in phone axes
        self.fwd = None  # bike forward in phone axes
        self.left = None
        self.up_at = self.fwd_at = None
        self.slips: list[float] = []
        self.carried = False      # started from the last ride's mount
        self.dropped_at = None    # ... and when that turned out wrong
        self._confirming = False
        self._reset()
        if carried:
            self._carry(*carried)

    def _carry(self, up: tuple, fwd: tuple) -> None:
        """Start from the last ride's mount (up, forward in phone axes),
        weighted like the first seconds of learning, so a few quiet
        seconds and corners of this ride already move it."""
        self.up = unit(up)
        self._up_sum = scale(self.up, UP_TICKS)
        self._up_n = UP_TICKS
        self._fwd_sum = scale(unit(sub(fwd, scale(self.up, dot(fwd, self.up)))), FWD_TICKS)
        self._fwd_abs = float(FWD_TICKS)
        self._fwd_n = FWD_TICKS
        self._orthogonalise()
        self.carried = self._confirming = True
        self._unconfirmed = 0

    def _reset(self) -> None:
        self._up_sum = (0.0, 0.0, 0.0)
        self._up_n = 0
        self._fwd_sum = (0.0, 0.0, 0.0)
        self._fwd_abs = 0.0
        self._fwd_n = 0
        self._slip_n = 0

    def ready(self) -> bool:
        return self.fwd is not None

    def step(self, t: float, f: tuple, w: tuple, v0: float, v1: float, dt: float,
             u: tuple | None = None) -> bool:
        """One GPS interval: f, w and the filter's world up u (phone axes)
        are the means over it. True = slipped."""
        speed = (v0 + v1) / 2
        dvdt = (v1 - v0) / dt
        yaw = abs(dot(w, self.up)) if self.up else norm(w)
        if self.up and u and dot(u, self.up) < 0:
            u = None
        if speed < MOUNT_MIN_MPS:
            return False
        tilt = angle(f, self.up) if self.up else 0.0
        quiet = abs(dvdt) < QUIET_DVDT and yaw < QUIET_YAW and abs(norm(f) - G) < QUIET_FORCE
        if self._confirming and quiet:
            # The carried mount holds if quiet riding agrees with it.
            if tilt <= TILTED_RAD:
                self._confirming = False
            else:
                self._unconfirmed += 1
                if self._unconfirmed >= UP_TICKS:
                    self.dropped_at = t
                    self._confirming = False
                    self.up = self.fwd = self.left = None
                    self._reset()
                    return True
                return False
        if tilt > SLIP_RAD:
            # A wheelie may hold 40 deg for minutes and ends by turning
            # back down; a slipped mount stays tilted while the bike rides
            # on normally. Riding straight and steady tells nothing -- a
            # long wheelie looks the same.
            if (abs(dvdt) > LONG_DVDT and norm(w) < LONG_YAW) or yaw > LEAN_YAW:
                self._slip_n += 1
                if self._slip_n >= SLIP_TICKS:
                    self.slips.append(t)
                    self.up = self.fwd = self.left = None
                    self._reset()
                    return True
            return False
        if tilt > TILTED_RAD:
            return False
        if quiet:
            self._slip_n = 0
            self._up_sum = add(scale(self._up_sum, UP_DECAY), unit(f))
            self._up_n += 1
            if self._up_n >= UP_TICKS:
                if self.up_at is None:
                    self.up_at = t  # the first time; a slip does not reset it
                self.up = unit(self._up_sum)
                self._orthogonalise()
        elif self.up and abs(dvdt) > LONG_DVDT and norm(w) < LONG_YAW:
            # Braking points backwards. Any rotation spoils it, not only
            # yaw: on rough ground the bike pitches and rolls while braking.
            h = sub(f, scale(self.up, dot(f, self.up)))
            self._learn(t, scale(h, dvdt), abs(dvdt) * norm(h))
        elif self.up and u and yaw > LEAN_YAW:
            # A corner: the bike leans into it, so the world's up seen from
            # the phone tips to the outside -- to the right in a left turn
            # (yaw > 0). Lean x speed x yaw rate points forward; in the
            # same units as braking (g sin(lean) ~ speed x yaw rate).
            h = sub(u, scale(self.up, dot(u, self.up)))
            turn = speed * dot(w, self.up)
            self._learn(t, scale(cross(self.up, h), turn * G), abs(turn) * G * norm(h))
        return False

    def _learn(self, t: float, term: tuple, size: float) -> None:
        self._fwd_sum = add(self._fwd_sum, term)
        self._fwd_abs += size
        self._fwd_n += 1
        if self._fwd_n >= FWD_TICKS and norm(self._fwd_sum) > FWD_CONSISTENCY * self._fwd_abs:
            if self.fwd_at is None:
                self.fwd_at = t
            self._orthogonalise()
        return False

    def _orthogonalise(self) -> None:
        if self._fwd_n < FWD_TICKS or norm(self._fwd_sum) <= FWD_CONSISTENCY * self._fwd_abs:
            return
        h = sub(self._fwd_sum, scale(self.up, dot(self._fwd_sum, self.up)))
        self.fwd = unit(h)
        self.left = cross(self.up, self.fwd)


# ------------------------------------------- stage 2: attitude filters

class Eskf:
    """Error-state Kalman filter, nominal q and gyro bias b; the error
    state (dtheta, db) has the covariance P in 3x3 blocks A, B; B^T, C."""

    name = "eskf"

    def __init__(self, f0) -> None:
        self.reset(f0)
        self.b = (0.0, 0.0, 0.0)
        self.C = diag(0.01 ** 2)

    def reset(self, f) -> None:
        self.q = q_from_gravity(f)
        self.A = diag(0.1 ** 2)
        self.B = ZERO3

    def predict(self, w, dt) -> None:
        u = sub(w, self.b)
        dth = scale(u, dt)
        self.q = qnorm(qmul(self.q, qexp(dth)))
        rt = mt(qrot(qexp(dth)))  # R{w dt}^T
        rb = mm(rt, self.B)
        a = mm(mm(rt, self.A), mt(rt))
        a = madd(a, madd(rb, mt(rb)), -dt)
        a = madd(a, self.C, dt * dt)
        self.A = madd(a, diag(GYRO_NOISE ** 2 * dt))
        self.B = madd(rb, self.C, -dt)
        self.C = madd(self.C, diag(BIAS_WALK ** 2 * dt))

    def rot(self):
        return qrot(self.q)

    def update(self, f, r_var) -> None:
        h = mtv(self.rot(), (0.0, 0.0, G))
        y = sub(f, h)
        hs = skew(h)
        pht_top = mm(self.A, mt(hs))              # A H^T
        pht_bot = mm(mt(self.B), mt(hs))          # B^T H^T
        s0 = mm(hs, pht_top)
        s = madd(s0, diag(r_var))
        si = inv3(s)
        nis = dot(y, mv(si, y))
        if nis > NIS_GATE:
            s = madd(s0, diag(r_var * nis / NIS_GATE))
            si = inv3(s)
        k_top = mm(pht_top, si)
        k_bot = mm(pht_bot, si)
        dth = mv(k_top, y)
        db = mv(k_bot, y)
        self.q = qnorm(qmul(self.q, qexp(dth)))
        self.b = add(self.b, db)
        self.A = _symmetric(madd(self.A, mm(k_top, mt(pht_top)), -1.0))
        self.B = madd(self.B, mm(k_top, mt(pht_bot)), -1.0)
        self.C = _symmetric(madd(self.C, mm(k_bot, mt(pht_bot)), -1.0))


class Mahony:
    """Mahony et al. 2008 with the bias integral; the correction weight
    comes from the same adaptive uncertainty as the Kalman filter's."""

    name = "mahony"

    def __init__(self, f0) -> None:
        self.reset(f0)
        self.b = (0.0, 0.0, 0.0)
        self._e = (0.0, 0.0, 0.0)
        self._k = 0.0

    def reset(self, f) -> None:
        self.q = q_from_gravity(f)

    def predict(self, w, dt) -> None:
        u = add(sub(w, self.b), scale(self._e, MAHONY_KP * self._k))
        self.b = sub(self.b, scale(self._e, MAHONY_KI * self._k * dt))
        self.q = qnorm(qmul(self.q, qexp(scale(u, dt))))

    def rot(self):
        return qrot(self.q)

    def update(self, f, r_var) -> None:
        v = mtv(self.rot(), EZ)  # estimated up in phone axes
        self._e = cross(unit(f), v)
        extra = max(0.0, r_var - ACC_NOISE ** 2)
        self._k = MAHONY_FLOOR ** 2 / (MAHONY_FLOOR ** 2 + extra)


# --------------------------------------------------------------- fusion

class Gps:
    """Speeds from the fixes, interpolated; dv/dt looks one second ahead."""

    def __init__(self, fixes) -> None:
        self.fixes = [(t, s) for t, s in fixes if not math.isnan(s)]
        self.times = [t for t, _ in self.fixes]

    def speed(self, t: float) -> float:
        i = bisect.bisect_right(self.times, t)
        if i == 0:
            return self.fixes[0][1] if self.fixes else math.nan
        if i == len(self.fixes):
            return self.fixes[-1][1]
        (t0, s0), (t1, s1) = self.fixes[i - 1], self.fixes[i]
        return s0 + (s1 - s0) * (t - t0) / (t1 - t0) if t1 > t0 else s1

    def dvdt(self, t: float) -> float:
        return (self.speed(t + 1.0) - self.speed(t - 1.0)) / 2.0

    def dvdt_change(self, t: float) -> float:
        return self.dvdt(t + 0.5) - self.dvdt(t - 0.5)

    def riding(self, start: float, end: float, kmh: float) -> bool:
        i = bisect.bisect_left(self.times, start)
        j = bisect.bisect_right(self.times, end)
        speeds = [s for _, s in self.fixes[i:j]]
        return bool(speeds) and min(speeds) * 3.6 >= kmh


class Fused:
    def __init__(self, method: str) -> None:
        self.method = method
        self.samples: list[tuple[float, float, float]] = []  # t, |f| g, f along bike up g
        # Every TICK_S: t, pitch, roll, raw pitch, raw roll, speed, dv/dt, yaw rate (deg, m/s, rad/s)
        self.ticks: list[tuple] = []
        self.mount: Mount | None = None
        self.bias: list[tuple[float, tuple]] = []
        # Per tick: the filter's attitude and the gyro alone integrated --
        # the short-term reference of the probes.
        self.quats: list[tuple] = []  # q filter, q gyro, forward, left
        self.updates = self.rejected = 0
        self.gps: Gps | None = None


def fuse(acc, gyro, fixes, method: str = "eskf", model: str = "full",
         gps_lag: float = 0.0, carried: tuple | None = None) -> Fused:
    """acc and gyro: (t s, x, y, z) sorted; fixes: (t s, speed m/s).
    model: "full" (along and across), "along", "none" -- for comparison;
    gps_lag: seconds the GPS time stamps come late; carried: (up, forward)
    of the last ride's mount in phone axes."""
    if gps_lag:
        fixes = [(t - gps_lag, v) for t, v in fixes]
    out = Fused(method)
    gps = Gps(fixes)
    out.gps = gps
    mount = Mount(carried)
    out.mount = mount
    filt = None
    fix_i = 0
    sum_f, sum_w, sum_u, n_f, n_w = (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), 0, 0
    w_last = (0.0, 0.0, 0.0)
    t_w = None
    q_gyro = (1.0, 0.0, 0.0, 0.0)
    vib_mean, vib_var, t_a = G, 0.0, None
    lp_f = None
    next_tick = None
    ai = wi = 0
    while ai < len(acc) or wi < len(gyro):
        take_gyro = wi < len(gyro) and (ai >= len(acc) or gyro[wi][0] <= acc[ai][0])
        t = gyro[wi][0] if take_gyro else acc[ai][0]
        # Stage 1 once per GPS fix, over the second before it.
        while fix_i < len(gps.fixes) and gps.fixes[fix_i][0] <= t:
            if fix_i > 0 and n_f and n_w:
                (t0, v0), (t1, v1) = gps.fixes[fix_i - 1], gps.fixes[fix_i]
                if 0 < t1 - t0 <= 3.0 and mount.step(
                        t1, scale(sum_f, 1 / n_f), scale(sum_w, 1 / n_w), v0, v1, t1 - t0,
                        unit(sum_u) if filt else None):
                    if filt:
                        filt.reset(scale(sum_f, 1 / n_f))
            sum_f, sum_w, sum_u, n_f, n_w = (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), 0, 0
            fix_i += 1
        if take_gyro:
            _, x, y, z = gyro[wi]
            wi += 1
            w_last = (x, y, z)
            sum_w = add(sum_w, w_last)
            n_w += 1
            if filt and t_w is not None:
                dt = t - t_w
                if 0 < dt < 0.1:
                    filt.predict(w_last, dt)
                    q_gyro = qnorm(qmul(q_gyro, qexp(scale(w_last, dt))))
            t_w = t
            continue
        _, x, y, z = acc[ai]
        ai += 1
        f = (x, y, z)
        sum_f = add(sum_f, f)
        n_f += 1
        fn = norm(f)
        dt = 0.0 if t_a is None else min(max(t - t_a, 0.0), 0.1)
        t_a = t
        k = min(1.0, dt / VIB_S)
        vib_mean += k * (fn - vib_mean)
        vib_var += k * ((fn - vib_mean) ** 2 - vib_var)
        lp_f = f if lp_f is None else add(lp_f, scale(sub(f, lp_f), min(1.0, dt / 0.5)))
        if filt is None:
            filt = (Eskf if method == "eskf" else Mahony)(f)
            next_tick = t
        r = filt.rot()
        sum_u = add(sum_u, r[2])
        speed = gps.speed(t)
        dvdt = gps.dvdt(t)
        yaw = dot(sub(w_last, filt.b), r[2])
        a_p = (0.0, 0.0, 0.0)
        # Without "forward" the model cannot be taken off, but its size is
        # known: count it all as noise until then.
        unknown = 0.0 if mount.ready() or math.isnan(speed) else dvdt ** 2 + (speed * yaw) ** 2
        if mount.ready() and not math.isnan(speed):
            fw = mv(r, mount.fwd)
            fh = unit((fw[0], fw[1], 0.0))
            if fh != (0.0, 0.0, 0.0):
                a_w = scale(fh, dvdt) if model != "none" else (0.0, 0.0, 0.0)
                if model == "full":
                    a_w = add(a_w, scale((-fh[1], fh[0], 0.0), speed * yaw))
                a_p = mtv(r, a_w)
        fc = sub(f, a_p)
        fcn = norm(fc) / G
        if GATE_LOW < fcn < GATE_HIGH:
            res = norm(fc) - G
            # The model itself is uncertain: GPS dv/dt is smoothed over two
            # seconds, so where it changes (brake -> accelerate) it is late,
            # and some share of what it takes off may be wrong.
            filt.update(fc, ACC_NOISE ** 2 + vib_var + (2 * res) ** 2
                        + (MODEL_TRUST * norm(a_p)) ** 2 + gps.dvdt_change(t) ** 2 + unknown)
            out.updates += 1
        else:
            out.rejected += 1
            if isinstance(filt, Mahony):
                filt._k = 0.0
        up = mount.up
        out.samples.append((t, fn / G, (dot(f, up) if up else fn) / G))
        if t >= next_tick:
            next_tick = t + TICK_S
            pitch = roll = raw_pitch = raw_roll = math.nan
            if mount.ready():
                r = filt.rot()
                pitch = math.degrees(math.asin(max(-1.0, min(1.0, mv(r, mount.fwd)[2]))))
                roll = math.degrees(math.asin(max(-1.0, min(1.0, mv(r, mount.left)[2]))))
                g = unit(lp_f)
                raw_pitch = math.degrees(math.asin(max(-1.0, min(1.0, dot(g, mount.fwd)))))
                raw_roll = math.degrees(math.asin(max(-1.0, min(1.0, -dot(g, mount.left)))))
            out.ticks.append((t, pitch, roll, raw_pitch, raw_roll, speed, dvdt, yaw))
            out.quats.append((filt.q, q_gyro, mount.fwd, mount.left))
            if len(out.ticks) % 100 == 0:
                out.bias.append((t, filt.b))
    return out


# --------------------------------------------------------------- stage 3

def pitch_against_way(fused: Fused, raw: bool = False) -> list[tuple[float, float]]:
    """(t, pitch - way) per tick; the way follows the pitch over ROAD_S
    while riding and holds still while the front is up (HOLD_DEG), as long
    as it is up: the gyro keeps the pitch within ~2 deg a minute, and a
    slipped mount ends it (NaN) instead of a time limit. It holds only
    from a settled way (the pitch within HOLD_DEG of it for ROAD_S): after
    a nose-down the way lags below, and the front coming back is no
    wheelie -- without the time limit such a hold would never let go."""
    out = []
    road = None
    calm = 0.0
    holding = False
    col = 3 if raw else 1
    for tick in fused.ticks:
        t, p, speed = tick[0], tick[col], tick[5]
        if math.isnan(p):
            road = None
            calm, holding = 0.0, False
            out.append((t, math.nan))
            continue
        if road is None:
            road = p
        rel = p - road
        holding = rel >= HOLD_DEG and (holding or calm >= ROAD_S)
        calm = calm + TICK_S if abs(rel) < HOLD_DEG else 0.0
        if speed * 3.6 > RIDING_KMH and not holding:
            road += (p - road) * TICK_S / ROAD_S
        out.append((t, rel))
    return out


def wheelies(fused: Fused, tilt_deg: float, min_s: float, raw: bool = False) -> list[dict]:
    """Front up against the way by tilt_deg, at > RIDING_KMH, for min_s;
    ends when the front comes down (tilt_deg - RELEASE_DEG under), however
    long it lasted. Slowing down with the front up does not end it, it
    only stops counting: a wheelie ends by turning back down, and a mount
    that went meanwhile (NaN) was no wheelie -- reported early, a slipped
    mount would show as a wheelie each time the rider brakes."""
    release = tilt_deg - RELEASE_DEG
    out = []
    start = None
    rel = pitch_against_way(fused, raw)
    for (t, p), tick in zip(rel, fused.ticks):
        speed = tick[5]
        riding = not math.isnan(speed) and speed * 3.6 > RIDING_KMH
        if start is not None:
            if math.isnan(p):
                start = None
                continue
            if p >= release:
                if riding:
                    last = t
                    peak = max(peak, p)
                    speeds.append(speed)
                continue
            if min_s <= last - start:
                out.append({"t": start, "duration": last - start,
                            "length_m": statistics.fmean(speeds) * (last - start),
                            "max_deg": peak})
            start = None
            continue
        if riding and not math.isnan(p) and p >= tilt_deg:
            start = last = t
            peak = p
            speeds = [speed]
    return out


def flights(fused: Fused, g_limit: float, min_ms: float) -> list[dict]:
    """Filtered |f| under g_limit for min_ms; the landing is the peak along
    the bike's up axis within LANDING_WINDOW_S; plausible = riding before
    and after, peak under PEAK_MAX_G, the bike upright a second later."""
    times = [x[0] for x in fused.ticks]
    rel = [p for _, p in pitch_against_way(fused)]
    s = fused.samples
    out = []
    start = None
    acc = 0.0
    lo = 0
    for i, (t, fn, _) in enumerate(s):
        acc += fn
        while s[i][0] - s[lo][0] > FLIGHT_SMOOTH_S:
            acc -= s[lo][1]
            lo += 1
        mean = acc / (i - lo + 1)
        low = mean < g_limit
        if low and start is None:
            start = i
        if (not low or i == len(s) - 1) and start is not None:
            t0, t1 = s[start][0], s[i][0]
            if (t1 - t0) * 1000 >= min_ms:
                peak = 0.0
                for pt, _, fz in s[i:]:
                    if pt - t1 > LANDING_WINDOW_S:
                        break
                    peak = max(peak, fz)
                gps = fused.gps
                before = gps.riding(t0 - SPEED_WINDOW_S, t0, PLAUSIBLE_KMH)
                after = gps.riding(t1, t1 + SPEED_WINDOW_S, PLAUSIBLE_KMH)
                k = min(bisect.bisect_left(times, t1 + UPRIGHT_AFTER_S), len(times) - 1)
                upright = True
                if times and not math.isnan(rel[k]):
                    upright = (abs(rel[k]) < UPRIGHT_PITCH_DEG
                               and abs(fused.ticks[k][2]) < UPRIGHT_ROLL_DEG)
                out.append({"t": t0, "duration": t1 - t0, "peak_g": peak, "upright": upright,
                            "plausible": before and after and peak < PEAK_MAX_G and upright})
            start = None
    return out


def _p95(values) -> float:
    v = sorted(abs(x) for x in values if not math.isnan(x))
    return v[int(0.95 * (len(v) - 1))] if v else math.nan


GYRO_REF_S = 3.0


def gyro_reference(fused: Fused) -> list[tuple[float, float]]:
    """Per tick (pitch, roll) as the gyro alone tells it: the filter's
    attitude GYRO_REF_S earlier, turned on by the integrated gyro since.
    The phone's gyro drifts well under 0.1 deg/s (both rides, 2026-10-30),
    so over three seconds this is the truth for every fast change -- and
    braking, corners and wheelies are fast. NaN where there is none."""
    back = int(round(GYRO_REF_S / TICK_S))
    out = []
    for k, tick in enumerate(fused.ticks):
        if k < back or math.isnan(tick[1]) or math.isnan(fused.ticks[k - back][1]):
            out.append((math.nan, math.nan))
            continue
        qf0, qg0, _, _ = fused.quats[k - back]
        _, qg1, fwd, left = fused.quats[k]
        r = mm(qrot(qf0), mm(mt(qrot(qg0)), qrot(qg1)))
        out.append((math.degrees(math.asin(max(-1.0, min(1.0, mv(r, fwd)[2])))),
                    math.degrees(math.asin(max(-1.0, min(1.0, mv(r, left)[2]))))))
    return out


def probes(fused: Fused) -> dict:
    """The checks of research section 6 on any ride: hard braking and
    accelerating bring no pitch, corners bring roll and no pitch (both
    against the gyro reference, which a filter that ignored the
    accelerometer would also pass), riding straight stays near the way
    (which it would not), the gyro bias settles."""
    rel = [p for _, p in pitch_against_way(fused)]
    raw = [p for _, p in pitch_against_way(fused, raw=True)]
    up = [(w["t"], w["t"] + w["duration"]) for w in wheelies(fused, 10.0, 0.5)]
    brake, curve, straight = [], [], []
    for k, tick in enumerate(fused.ticks):
        _, p, roll, _, raw_roll, speed, dvdt, yaw = tick
        if math.isnan(p) or math.isnan(speed) or speed < MOUNT_MIN_MPS:
            continue
        if abs(dvdt) > 1.5 and abs(yaw) < LONG_YAW:
            brake.append(k)
        elif abs(yaw) > 0.25:
            curve.append(k)
        elif (abs(dvdt) < QUIET_DVDT and abs(yaw) < QUIET_YAW
              and not any(a <= tick[0] <= b for a, b in up)):
            straight.append(k)
    ref = gyro_reference(fused)
    def off(ks, col, ref_col):
        return _p95(fused.ticks[k][col] - ref[k][ref_col] for k in ks)
    riding = brake + curve + straight
    m = fused.mount
    late = [b for t, b in fused.bias if fused.bias and t >= fused.bias[-1][0] / 2]
    drift = max((math.degrees(norm(sub(b, late[0]))) for b in late), default=math.nan)
    return {
        "up_s": m.up_at, "fwd_s": m.fwd_at, "slips": len(m.slips),
        "brake_n": len(brake),
        "brake_pitch": _p95(rel[k] for k in brake), "brake_raw": _p95(raw[k] for k in brake),
        "curve_n": len(curve),
        "curve_pitch": _p95(rel[k] for k in curve), "curve_raw": _p95(raw[k] for k in curve),
        "curve_roll": _p95(fused.ticks[k][2] for k in curve),
        "straight_pitch": _p95(rel[k] for k in straight),
        # Against the gyro reference: fused and raw pitch, roll in corners.
        "brake_gyro": off(brake, 1, 0), "brake_gyro_raw": off(brake, 3, 0),
        "curve_gyro": off(curve, 1, 0), "curve_gyro_raw": off(curve, 3, 0),
        "curve_roll_gyro": off(curve, 2, 1), "curve_roll_gyro_raw": off(curve, 4, 1),
        "riding_gyro": off(riding, 1, 0), "riding_gyro_raw": off(riding, 3, 0),
        "bias_dps": math.degrees(norm(fused.bias[-1][1])) if fused.bias else math.nan,
        "bias_drift_dps": drift,
        "rejected": fused.rejected / max(1, fused.updates + fused.rejected),
    }


# -------------------------------------------------------------- self-test

def _rz(a):
    c, s = math.cos(a), math.sin(a)
    return ((c, -s, 0.0), (s, c, 0.0), (0.0, 0.0, 1.0))


def _ry(a):
    c, s = math.cos(a), math.sin(a)
    return ((c, 0.0, s), (0.0, 1.0, 0.0), (-s, 0.0, c))


def _rx(a):
    c, s = math.cos(a), math.sin(a)
    return ((1.0, 0.0, 0.0), (0.0, c, -s), (0.0, s, c))


def _ramp(t, t0, t1, rise=0.3):
    """0 -> 1 -> 0 over [t0, t1] with linear flanks of `rise` seconds."""
    if t <= t0 or t >= t1:
        return 0.0
    return min(1.0, (t - t0) / rise, (t1 - t) / rise)


class Noise:
    """Gaussian noise the Dart test draws identically (xorshift32, the sum
    of four uniforms scaled to unit variance): integer steps and plain sums
    give the same numbers in both languages, so the Dart port of the
    fusion (lib/features/rides/sensor_fusion.dart) sees this very ride."""

    def __init__(self, seed: int) -> None:
        self.x = (seed & 0xFFFFFFFF) or 1

    def uniform(self) -> float:
        x = self.x
        x ^= (x << 13) & 0xFFFFFFFF
        x ^= x >> 17
        x ^= (x << 5) & 0xFFFFFFFF
        self.x = x
        return x / 4294967296.0

    def gauss(self, sigma: float) -> float:
        u = self.uniform() + self.uniform() + self.uniform() + self.uniform()
        return sigma * (u - 2.0) * math.sqrt(3.0)


def synthetic(seed: int = 1, slip_pitch: bool = False):
    """A 420 s ride with known truth. The phone sits rotated on the bike
    (screen tilted back, top pointing to the rear right), the gyro has a
    bias, both sensors are noisy. Timeline: steady riding 0-20 s (learn
    up); brake/accelerate at 20, 30, 40 s (learn forward); hard braking
    60-64 s (NO pitch); left curve 70-80 s with its lean; wheelie 25 deg
    at 90 s; a 0.5 s jump at 100 s landing with 3 g; nose down 20 deg at
    110 s (no wheelie); a 10 deg climb from 128 s with a 18 deg wheelie on
    top at 135 s; the mount slips by 60 deg at 150 s (seen at the braking
    from 215 s, riding straight tells nothing); braking again at 230/240/
    250 s; a wheelie at 280 s; a 90 s wheelie at 40 deg from 310 s (no
    slip: it rides straight). slip_pitch: the mount tips 40 deg front up
    instead -- a wheelie until the braking shows the slip, and then none.
    Times as in the Dart test."""
    rnd = Noise(seed)
    hz = 120.0
    bias = (0.02, -0.012, 0.015)
    mount0 = mm(_rz(math.radians(140)), _rx(math.radians(-35)))  # bike -> phone
    mount1 = mm(mount0, _ry(math.radians(40))) if slip_pitch else mm(_rx(math.radians(60)), mount0)

    def speed(t):
        v = 6.0
        for t0 in (20, 30, 40, 215, 230, 240, 250):
            if t0 <= t < t0 + 2:
                v -= 2.0 * (t - t0)
            elif t0 + 2 <= t < t0 + 4:
                v -= 4.0 - 2.0 * (t - t0 - 2)
        if 60 <= t < 62:
            v -= 3.0 * (t - 60)
        elif 62 <= t < 64:
            v -= 6.0 - 3.0 * (t - 62)
        return v

    def attitude(t):
        yaw_rate = 0.6 * min(1.0, max(0.0, min(t - 70, 80 - t)))
        yaw = 0.6 * (max(0.0, min(t, 80) - 70) - 0.5) if t > 70 else 0.0
        v = speed(t)
        roll = -math.atan2(v * yaw_rate, G)
        pitch = (math.radians(25) * _ramp(t, 90, 92) - math.radians(20) * _ramp(t, 110, 112.5)
                 + math.radians(10) * _ramp(t, 128, 145, rise=3.0)
                 + math.radians(18) * _ramp(t, 135, 137) + math.radians(22) * _ramp(t, 280, 282)
                 + math.radians(40) * _ramp(t, 310, 400, rise=1.0))
        return mm(mm(_rz(yaw), _ry(-pitch)), _rx(roll)), v, yaw, yaw_rate

    acc, gyro, fixes = [], [], []
    dt = 1 / hz
    n = int(420 * hz)
    prev = attitude(0.0)[0]
    for i in range(1, n):
        t = i * dt
        r_wb, v, yaw, yaw_rate = attitude(t)
        dv = (speed(t + dt) - speed(t - dt)) / (2 * dt)
        a_w = (dv * math.cos(yaw) - v * yaw_rate * math.sin(yaw),
               dv * math.sin(yaw) + v * yaw_rate * math.cos(yaw), 0.0)
        f_w = add(a_w, (0.0, 0.0, G))
        if 100.0 <= t < 100.5:
            f_w = (0.0, 0.0, 0.0)
        elif 100.5 <= t < 100.55:
            f_w = mv(r_wb, (0.0, 0.0, 3 * G))
        m = mount1 if t >= 150 else mount0
        f_p = mv(m, mtv(r_wb, f_w))
        rel = mm(mt(prev), r_wb)  # body rotation over dt
        w_b = (rel[2][1] - rel[1][2], rel[0][2] - rel[2][0], rel[1][0] - rel[0][1])
        w_b = scale(w_b, 0.5 / dt)
        w_p = add(mv(m, w_b), bias)
        prev = r_wb
        noise = 1.0 if not 100.0 <= t < 100.5 else 0.05
        acc.append((t, *(c + rnd.gauss(noise) for c in f_p)))
        gyro.append((t + 0.002, *(c + rnd.gauss(0.01) for c in w_p)))
        if i % int(hz) == 0:
            fixes.append((t, v))
    return acc, gyro, fixes, {"bias": bias, "mount0": mount0, "mount1": mount1}


def _self_test() -> None:
    acc, gyro, fixes, truth = synthetic()
    for method in ("eskf", "mahony"):
        fused = fuse(acc, gyro, fixes, method)
        m = fused.mount
        assert len(m.slips) == 1 and 215 <= m.slips[0] <= 235, (method, m.slips)
        up1 = mv(truth["mount1"], EZ)
        fwd1 = mv(truth["mount1"], (1.0, 0.0, 0.0))
        assert math.degrees(angle(m.up, up1)) < 4, (method, "up after the slip")
        assert math.degrees(angle(m.fwd, fwd1)) < 8, (method, "forward after the slip")
        assert m.up_at is not None and m.up_at <= 20 and m.fwd_at is not None and m.fwd_at <= 45, \
            (method, m.up_at, m.fwd_at)
        rel = dict(pitch_against_way(fused))
        raw = dict(pitch_against_way(fused, raw=True))
        brake = [t for t in rel if 60.5 <= t <= 63.5]
        assert max(abs(rel[t]) for t in brake) < 5, (method, "braking tilts the fused pitch")
        assert max(abs(raw[t]) for t in brake) > 10, "the probe must catch the raw rule"
        curve = [k for k, x in enumerate(fused.ticks) if 72 <= x[0] <= 78]
        assert max(abs(rel[fused.ticks[k][0]]) for k in curve) < 5, (method, "curve as pitch")
        rolls = [abs(fused.ticks[k][2]) for k in curve]
        assert 16 < statistics.median(rolls) < 24, (method, "lean", statistics.median(rolls))
        found = wheelies(fused, 15.0, 1.0)
        starts = sorted(round(w["t"]) for w in found)
        assert len(starts) == 4 and abs(starts[0] - 90) <= 1 and abs(starts[1] - 135) <= 1 \
            and abs(starts[2] - 280) <= 1 and abs(starts[3] - 310) <= 1, (method, found)
        assert found[3]["duration"] > 85, (method, "the long wheelie is cut", found[3])
        fl = flights(fused, 0.3, 150)
        assert len(fl) == 1 and abs(fl[0]["t"] - 100.0) < 0.05, (method, fl)
        assert fl[0]["plausible"] and 2.5 < fl[0]["peak_g"] < 3.5, (method, fl)
        # Only the bias across "up" is observable from gravity; the part
        # about the vertical stays where the gyro left it. Checked before
        # the slip: afterwards a new part becomes observable and settles anew.
        b = [b for t, b in fused.bias if t < 150][-1]
        up0 = mv(truth["mount0"], EZ)
        err = sub(b, truth["bias"])
        err = sub(err, scale(up0, dot(err, up0)))
        assert norm(err) < 0.004, (method, "bias", b)
        p = probes(fused)
        assert p["brake_n"] > 0 and p["curve_n"] > 0 and p["slips"] == 1, p
        assert p["brake_pitch"] < 5 < p["brake_raw"], p
    # A slip that looks like a wheelie: the way holds, the front stays up
    # from 150 s -- until the braking from 215 s drops the mount, and with
    # it the "wheelie".
    acc2, gyro2, fixes2, _ = synthetic(slip_pitch=True)
    fused = fuse(acc2, gyro2, fixes2, "mahony")
    rel = dict(pitch_against_way(fused))
    assert max(rel[t] for t in rel if 160 <= t <= 210) > 30, "the slip must look like a wheelie"
    assert len(fused.mount.slips) == 1, fused.mount.slips
    assert not [w for w in wheelies(fused, 15.0, 1.0) if 140 <= w["t"] <= 235], "slip as wheelie"
    # The last ride's mount: right, it stands from the first second and
    # holds; wrong (the phone turned a quarter on the bar), five quiet
    # seconds drop it and the ride learns anew.
    up0, fwd0 = mv(truth["mount0"], EZ), mv(truth["mount0"], (1.0, 0.0, 0.0))
    fused = fuse(acc, gyro, fixes, "mahony", carried=(up0, fwd0))
    m = fused.mount
    assert m.carried and m.dropped_at is None and m.ready(), "the right mount holds"
    assert fused.ticks[5][1] == fused.ticks[5][1], "pitch from the start"
    assert len(wheelies(fused, 15.0, 1.0)) == 4
    turned = mm(_rx(math.radians(90)), truth["mount0"])
    fused = fuse(acc, gyro, fixes, "mahony",
                 carried=(mv(turned, EZ), mv(turned, (1.0, 0.0, 0.0))))
    m = fused.mount
    assert m.dropped_at is not None and m.dropped_at <= 10, ("the wrong mount stays", m.dropped_at)
    assert m.fwd_at is not None and m.fwd_at <= 45 and len(m.slips) == 1, (m.fwd_at, m.slips)
    assert len(wheelies(fused, 15.0, 1.0)) == 4
    # The pieces on their own.
    q = q_from_gravity((0.0, G, 0.0))
    assert norm(sub(mv(qrot(q), (0.0, 1.0, 0.0)), EZ)) < 1e-9
    assert norm(sub(mv(inv3(((2.0, 1.0, 0.0), (0.0, 3.0, 1.0), (1.0, 0.0, 1.0))),
                       mv(((2.0, 1.0, 0.0), (0.0, 3.0, 1.0), (1.0, 0.0, 1.0)), (1.0, 2.0, 3.0))),
                    (1.0, 2.0, 3.0))) < 1e-9
    print("sensor_fusion self-test: ok")


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        _self_test()
        sys.exit(0)
    print(__doc__)
    sys.exit(0)
