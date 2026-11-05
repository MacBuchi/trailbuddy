#!/usr/bin/env python3
"""Routen für die Uhr-App (`garmin/`, docs/konzept-garmin.md).

Schreibt eine Route in der Form, die `garmin/source/NavRoute.mc` liest —
dieselbe wie ein einziges Stück vom Handy (Protokoll 2, #449,
`lib/features/garmin/watch_route.dart`): `{"v": 2, "id", "rel", "np",
"o": [lat0, lon0], "e0", "sec": [[von, bis, sGrad, Name], …], "pts",
"ele", "br"}` — `pts` je Punkt `(dLat << 16) | dLon` in 1e-5° gegen den
Vorgänger (der erste gegen `o`), `ele` die Differenzen in Metern zu zweit
in einer Zahl (die erste gegen `e0`), `br` je Stummel `[Punkt,
gepackt(dLat, dLon)]`. Schritte über 16 Bit teilt `encode` mit
Zwischenpunkten (nur ohne Abschnitte und Stummel, deren Nummern sonst
verrutschten).

- `--points N`: die ERFUNDENE Testroute von G1 (A7) — eine Runde von gut
  5 km mit vier Test-Trails, N Punkte. `rel: true`: Die Uhr verankert sie
  am ersten GPS-Fix, im Repo steht keine Koordinate. Damit misst G1 den
  Speicher (Konzept 8.1: 500, 1000, 2000, 4000 Punkte).
- `--gpx DATEI`: eine eigene Route (z. B. der GPX-Export der App),
  vereinfacht nach Douglas-Peucker mit 5 m. Ohne Abschnitte — die trägt
  erst das Protokoll von G2. Das Ergebnis enthält Koordinaten und gehört
  NIE ins Repo: `tool/garmin_build.sh --gpx` schreibt es nur unter
  `build/`.
- `--self-test`: Kodierung, Vereinfachung, und dass die Farben in
  `garmin/source/Colors.mc` die nächsten MIP-Farben zu den Kartenfarben
  der App sind.
"""
import argparse
import json
import math
import os
import re
import sys
import xml.etree.ElementTree as ET

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
K_LAT = 111194.9  # m je Grad Breite, wie NavRoute.K_LAT
SIMPLIFY_M = 5.0


BRANCH_M = 40.0  # so lang ist ein Stummel an einer Kreuzung
PROTOCOL = 2
MAX_DELTA = 32767  # ein Schritt in 16 Bit, wie kWatchMaxDelta


def pack(hi, lo):
    """Zwei Werte mit 16 Bit Vorzeichen in einer 32-Bit-Zahl mit Vorzeichen
    (wie `watchPack` in Dart, `PhoneRoute.unpackHi/Lo` auf der Uhr)."""
    v = ((hi & 0xFFFF) << 16) | (lo & 0xFFFF)
    return v - (1 << 32) if v >= 1 << 31 else v


def unpack(v):
    hi, lo = (v >> 16) & 0xFFFF, v & 0xFFFF
    return (hi - 0x10000 if hi >= 0x8000 else hi, lo - 0x10000 if lo >= 0x8000 else lo)


def _split_long(e5, ele):
    """Zwischenpunkte, bis jeder Schritt in 16 Bit passt."""
    out, out_ele = [e5[0]], [ele[0]] if ele is not None else None
    for i in range(1, len(e5)):
        (a, b), (c, d) = out[-1], e5[i]
        steps = max(1, -(-max(abs(c - a), abs(d - b)) // MAX_DELTA))
        for k in range(1, steps + 1):
            t = k / steps
            out.append((round(a + (c - a) * t), round(b + (d - b) * t)) if k < steps else (c, d))
            if out_ele is not None:
                h0 = ele[i - 1]
                out_ele.append(h0 + (ele[i] - h0) * t)
    return out, out_ele


def encode(latlon, ele=None, sections=(), rel=False, route_id="test", branches=()):
    """[(lat, lon)] in Grad → das Dictionary der Uhr (ein Stück). [branches]:
    [(Punkt, (lat, lon) des Stummel-Endes)]."""
    e5 = [(round(lat * 1e5), round(lon * 1e5)) for lat, lon in latlon]
    if any(max(abs(c - a), abs(d - b)) > MAX_DELTA for (a, b), (c, d) in zip(e5, e5[1:])):
        if sections or branches:
            raise ValueError("Schritt über 16 Bit: mit Abschnitten oder Stummeln nicht teilbar")
        e5, ele = _split_long(e5, ele)
    pts = [0] + [pack(c - a, d - b) for (a, b), (c, d) in zip(e5, e5[1:])]
    out = {"v": PROTOCOL, "id": route_id, "rel": rel, "np": len(e5), "o": list(e5[0]), "pts": pts}
    if ele is not None:
        m = [round(h) for h in ele]
        out["e0"] = m[0]
        deltas = [0] + [b - a for a, b in zip(m, m[1:])]
        if len(deltas) % 2:
            deltas.append(0)
        out["ele"] = [pack(deltas[i], deltas[i + 1]) for i in range(0, len(deltas), 2)]
    if sections:
        out["sec"] = [list(s) for s in sections]
    if branches:
        br = []
        for i, (lat, lon) in branches:
            br += [i, pack(round(lat * 1e5) - e5[i][0], round(lon * 1e5) - e5[i][1])]
        out["br"] = br
    return out


def decode(d):
    """Gegenstück zu encode, für den Self-Test (wie NavRoute.decodeStep)."""
    lat, lon = d["o"]
    out = []
    for v in d["pts"]:
        a, b = unpack(v)
        lat += a
        lon += b
        out.append((lat / 1e5, lon / 1e5))
    return out


def decode_ele(d):
    h, out = d["e0"], []
    for v in d["ele"]:
        for x in unpack(v):
            h += x
            out.append(h)
    return out[:d["np"]]


def _local(latlon):
    lat0 = latlon[0][0]
    k_lon = K_LAT * math.cos(math.radians(lat0))
    return [((lon - latlon[0][1]) * k_lon, (lat - lat0) * K_LAT) for lat, lon in latlon]


def simplify(latlon, tol_m=SIMPLIFY_M):
    """Douglas-Peucker in Metern; die Indizes der behaltenen Punkte."""
    xy = _local(latlon)
    keep = {0, len(xy) - 1}
    stack = [(0, len(xy) - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = xy[a]
        bx, by = xy[b]
        dx, dy = bx - ax, by - ay
        l2 = dx * dx + dy * dy
        best, far = -1.0, -1
        for i in range(a + 1, b):
            px, py = xy[i]
            t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / l2))
            d = math.hypot(px - ax - t * dx, py - ay - t * dy)
            if d > best:
                best, far = d, i
        if best > tol_m:
            keep.add(far)
            stack += [(a, far), (far, b)]
    return sorted(keep)


def synthetic(n):
    """Die erfundene Testrunde: gut 5 km, Start = Ziel = erster Fix, in
    Metern um (0, 0) und am Äquator in Grad umgerechnet (dort ist 1e-5°
    in beiden Richtungen gleich lang). Vier Test-Trails, einer je S-Grad."""
    xy, ele = [], []
    for i in range(n):
        t = 2 * math.pi * i / (n - 1)
        x = 900 * math.sin(t) + 120 * math.sin(5 * t)
        y = 600 * (1 - math.cos(t)) + 80 * math.sin(7 * t)
        xy.append((x, y))
        ele.append(500 + 60 * math.sin(t) + 20 * math.sin(3 * t))
    latlon = [(y / K_LAT, x / K_LAT) for x, y in xy]
    sections = []
    for (a, b), grade, name in [((0.12, 0.22), 1, "Testtrail Kehre"),
                                ((0.38, 0.47), 2, "Testtrail Wurzel"),
                                ((0.58, 0.66), 0, "Testtrail Wiese"),
                                ((0.80, 0.85), 3, "Testtrail Stufe")]:
        sections.append([round(a * (n - 1)), round(b * (n - 1)), grade, name])
    # Alle ~180 m eine Kreuzung, der Stummel abwechselnd links und rechts,
    # 55…115° gegen die Fahrtrichtung gedreht.
    branches = []
    length = sum(math.dist(p, q) for p, q in zip(xy, xy[1:]))
    step = max(2, round((n - 1) * 180 / length))
    for k, i in enumerate(range(step, n - step, step)):
        (x0, y0), (x1, y1) = xy[i - 1], xy[i + 1]
        h = math.atan2(x1 - x0, y1 - y0)
        turn = math.radians(55 + (k * 37) % 60) * (1 if k % 2 else -1)
        ex = xy[i][0] + BRANCH_M * math.sin(h + turn)
        ey = xy[i][1] + BRANCH_M * math.cos(h + turn)
        branches.append((i, (ey / K_LAT, ex / K_LAT)))
    return encode(latlon, ele, sections, rel=True, route_id=f"test-{n}", branches=branches)


def from_gpx(path):
    root = ET.parse(path).getroot()
    pts, ele = [], []
    for el in root.iter():
        if el.tag.split("}")[-1] in ("trkpt", "rtept"):
            pts.append((float(el.get("lat")), float(el.get("lon"))))
            h = next((c.text for c in el if c.tag.split("}")[-1] == "ele"), None)
            ele.append(float(h) if h else None)
    if len(pts) < 2:
        raise SystemExit(f"{path}: keine Spur mit mindestens zwei Punkten")
    keep = simplify(pts)
    has_ele = all(ele[i] is not None for i in keep)
    rid = os.path.splitext(os.path.basename(path))[0][:24]
    return encode([pts[i] for i in keep], [ele[i] for i in keep] if has_ele else None,
                  rel=False, route_id=rid)


# --- Farben ---------------------------------------------------------------

def _lab(rgb):
    def lin(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (lin(c) for c in rgb)
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
    f = lambda t: t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    return 116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))


def nearest_mip(hex6):
    """Die nächste der 64 Farben eines 8-Bit-MIP-Displays (je Kanal 00, 55,
    AA, FF), gemessen in CIELAB."""
    c = tuple(int(hex6[i:i + 2], 16) for i in (0, 2, 4))
    lv = (0, 0x55, 0xAA, 0xFF)
    target = _lab(c)
    best = min(((r, g, b) for r in lv for g in lv for b in lv),
               key=lambda p: sum((u - v) ** 2 for u, v in zip(_lab(p), target)))
    return "%02X%02X%02X" % best


def check_colors(root=REPO_ROOT):
    """Jede Konstante in Colors.mc nennt im Kommentar ihre App-Farbe
    (`// name HEX`); sie muss deren nächste MIP-Farbe sein, und HEX muss
    in app_colors.dart stehen."""
    mc = open(os.path.join(root, "garmin", "source", "Colors.mc"), encoding="utf-8").read()
    dart = open(os.path.join(root, "lib", "core", "app_colors.dart"), encoding="utf-8").read().upper()
    problems = []
    rows = re.findall(r"const (\w+) = 0x([0-9A-Fa-f]{6});\s*// .*?([0-9A-F]{6})\b", mc)
    if len(rows) < 9:
        problems.append(f"Colors.mc: nur {len(rows)} Farben mit App-Farbe gefunden")
    for name, mip, app in rows:
        if f"0XFF{app}" not in dart:
            problems.append(f"Colors.mc {name}: {app} steht nicht in app_colors.dart")
        want = nearest_mip(app)
        if mip.upper() != want:
            problems.append(f"Colors.mc {name}: 0x{mip} statt 0x{want} (nächste MIP-Farbe zu {app})")
    return problems


def self_test():
    route = [(0.0, 0.0), (0.0, 0.003), (0.00001, 0.006), (0.0, 0.009)]
    d = encode(route, [500, 510, 505, 540], [[1, 2, 2, "T"]])
    assert d["pts"] == [0, 300, 65836, -65236], d["pts"]
    assert d["np"] == 4 and d["o"] == [0, 0] and d["e0"] == 500
    assert decode(d) == route
    assert decode_ele(d) == [500, 510, 505, 540]
    assert unpack(pack(-32768, 32767)) == (-32768, 32767) and unpack(pack(-1, -1)) == (-1, -1)
    # Ein Schritt über 16 Bit (1 km nach Osten) bekommt Zwischenpunkte.
    far = encode([(0.0, 0.0), (0.0, 0.9)], [500, 600])
    assert far["np"] == 4 and abs(decode(far)[-1][1] - 0.9) < 1e-9, far
    assert decode_ele(far)[-1] == 600
    # Ein Knick von gut 1 m fällt bei 5 m weg, einer von 50 m bleibt.
    assert simplify(route) == [0, 3], simplify(route)
    bent = [(0.0, 0.0), (0.00045, 0.0045), (0.0, 0.009)]
    assert simplify(bent) == [0, 1, 2]
    s = synthetic(1000)
    assert s["rel"] is True and len(s["pts"]) == 1000 and len(s["ele"]) == 500 and s["np"] == 1000
    assert s["o"] == [0, 0] and s["pts"][0] == 0
    end = decode(s)[-1]
    assert abs(end[0]) < 2e-5 and abs(end[1]) < 2e-5, end  # Runde
    assert [x[2] for x in s["sec"]] == [1, 2, 0, 3]
    # Abzweigungen: Dreiergruppen, Stummel ~40 m lang.
    br = s["br"]
    assert len(br) % 2 == 0 and 20 < len(br) // 2 < 60, len(br)
    stub = math.hypot(*unpack(br[1])) / 1e5 * K_LAT
    assert 38 < stub < 42, stub
    d2 = encode(route, branches=[(1, (0.0003, 0.003))])
    assert d2["br"] == [1, pack(30, 0)], d2["br"]
    xy = _local(decode(s))
    length = sum(math.dist(a, b) for a, b in zip(xy, xy[1:]))
    assert 5000 < length < 7000, length
    assert nearest_mip("B6F04A") == "AAFF55" and nearest_mip("131A16") == "000000"
    problems = check_colors()
    assert not problems, problems
    print("garmin_route self-test ok")


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--points", type=int)
    g.add_argument("--gpx")
    g.add_argument("--self-test", action="store_true")
    ap.add_argument("--out", help="Zieldatei (sonst stdout)")
    args = ap.parse_args()
    if args.self_test:
        self_test()
        return
    d = synthetic(args.points) if args.points else from_gpx(args.gpx)
    text = json.dumps(d, separators=(",", ":"), ensure_ascii=False)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(text + "\n")
        print(f"{args.out}: {d['np']} Punkte, {len(text)} Bytes", file=sys.stderr)
    else:
        print(text)


if __name__ == "__main__":
    main()
