#!/usr/bin/env python3
"""Erzeugt alle App-Symbole aus dem EINEN Logo (Design Turn 1b, Form
seit „Serpentine C3", docs/design/trailbuddy-logo/).

Das Logo ist eine gefüllte FLÄCHE, keine Linie mit Strichstärke: zwei
Kehren (r 13 / r 16) über eine gemeinsame Tangente, die Anlieger werden
nur nach außen breiter, die Strecke wird schmaler (11 → 8), am Ende
auslaufende Striche. Es gibt drei optische Größen — L ab 32 px (zwei
Endstriche), M für 20–28 px (einer), S bis 18 px (keiner, längerer
Auslauf). Die Geometrie steht in `tool/brand/logo_c3.json`: je Größe
Stichproben der Mittellinie `[x, y, nx, ny, halbeBreiteLinks,
halbeBreiteRechts]` im 100er-Raster und die Endstriche `[c0, len, x1, y,
w]`. Die Fläche eines Abschnitts a…b der Strecke ist `outline()` — in
Dart dieselbe Rechnung (`LogoGeometry.range`), daraus Logo, Loader und
Zeichen-Animation.

Geschrieben werden:

- `lib/core/widgets/trailbuddy_logo_geometry.dart` — die Stichproben als
  Dart-Konstanten (Teil von `trailbuddy_logo.dart`).
- `drawable/ic_notification.xml` — das Statusleisten-Symbol für Push UND
  die Dauerbenachrichtigung der Fahrt: Größe M, weiß, nur Alphakanal.
  Ein Vektor statt PNGs je Dichte: dieselbe Form auf jedem Gerät, und
  Android rastert ihn selbst.
- `drawable/ic_launcher_foreground.xml` + `mipmap-anydpi-v26/ic_launcher.xml`
  — das adaptive Symbol (Vordergrund dunkel, Hintergrund Lime aus
  `values/colors.xml`), dazu `monochrome` für Androids Themen-Symbole.
- `drawable/ic_splash.xml` — das Zeichen auf dem Startschirm ab Android
  12, in der Marke des Modus (`@color/brand_mark`), ohne Lime-Scheibe:
  so sieht es aus wie der Splash der App, der danach übernimmt.
- `mipmap-*/ic_launcher.png` — das Symbol für Android vor 8.0.
- `web/icons/Icon-{192,512}.png`, `Icon-maskable-{192,512}.png`,
  `web/favicon.png`, `web/favicon.svg`.
- `garmin/resources/drawables/launcher_icon.png` — das Symbol der
  Uhr-App (40 px, `launcherIcon` der fēnix 5), runde Lime-Scheibe.

Die Textdateien prüft `--check` als Fixpunkt (ohne Werkzeug); die PNGs
braucht `rsvg-convert` (librsvg) und stehen mit Prüfsumme in
`tool/generated_assets.json`. Nach einer Änderung hier:
`python3 tool/brand_icons.py && python3 tool/generated_assets.py --update`.
"""
import argparse
import json
import math
import os
import subprocess
import sys
import tempfile

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join("android", "app", "src", "main", "res")
GEOMETRY_JSON = os.path.join("tool", "brand", "logo_c3.json")
DART_GEOMETRY = os.path.join("lib", "core", "widgets", "trailbuddy_logo_geometry.dart")

BRAND = "#B6F04A"
ON_BRAND = "#0E1411"
MOSS = "#4F8A10"

# Anteil des 100er-Rasters an der Kante, je Ziel — aus dem Handoff
# (docs/design/trailbuddy-logo/README.md). Die Form reicht bei 1,0 von
# x 14…86 und y 16…83; der fernste Punkt liegt 48,5 Einheiten von der
# Mitte (50, 50).
# Adaptiv: sichtbar sind die mittleren 72 von 108 dp, auf einer runden
# Maske ein Kreis mit Radius 36 dp — bei 0,66 bleibt der fernste Punkt
# bei 34,6 dp.
ADAPTIVE_SCALE = 0.66
LEGACY_SCALE = 0.80
WEB_SCALE = 0.90
MASKABLE_SCALE = 0.80  # sicher: Kreis mit 40 % Radius
NOTIFICATION_SCALE = 0.88
# Android 12: 288 dp, sichtbar ist ein Kreis mit 192 dp Durchmesser.
SPLASH_SCALE = 0.60


def load_geometry(root=REPO_ROOT):
    with open(os.path.join(root, GEOMETRY_JSON), encoding="utf-8") as f:
        data = json.load(f)
    return {k: data[k] for k in ("L", "M", "S")}


GEO = load_geometry()


def _fmt(x):
    return f"{x:.2f}".rstrip("0").rstrip(".")


def outline(geo, a=0.0, b=None, k=1.0, tx=0.0, ty=0.0):
    """Die Fläche des Abschnitts a…b als SVG-Pfad (Android kennt dieselbe
    Syntax): linker Rand vorwärts, runde Kappe, rechter Rand zurück, runde
    Kappe — dazu die Endstriche im Abschnitt als Pillen. Spiegel von
    `LogoGeometry.range` in Dart."""
    if b is None:
        b = geo["total"]
    s = geo["samples"]
    n = len(s) - 1
    length = geo["length"]
    ds = length / n

    def pt(x, y):
        return f"{_fmt(x * k + tx)} {_fmt(y * k + ty)}"

    def left(i):
        x, y, nx, ny, hl, _ = s[i]
        return pt(x + nx * hl, y + ny * hl)

    def right(i):
        x, y, nx, ny, _, hr = s[i]
        return pt(x - nx * hr, y - ny * hr)

    def w(i):
        return _fmt((s[i][4] + s[i][5]) / 2 * k)

    d = ""
    if b > 0 and a < length:
        i0 = min(max(round(max(0.0, a) / ds), 0), n - 1)
        i1 = max(i0 + 1, min(max(round(min(length, b) / ds), 0), n))
        d += "M" + left(i0)
        d += "".join("L" + left(i) for i in range(i0 + 1, i1 + 1))
        d += f"A{w(i1)} {w(i1)} 0 0 0 {right(i1)}"
        d += "".join("L" + right(i) for i in range(i1 - 1, i0 - 1, -1))
        d += f"A{w(i0)} {w(i0)} 0 0 0 {left(i0)}Z"
    for c0, ln, x1, y, wd in geo["dashes"]:
        lo, hi = max(a, c0), min(b, c0 + ln)
        if hi < lo:
            continue
        r = wd / 2
        xa, xb = x1 + lo - c0, x1 + hi - c0
        rk = _fmt(r * k)
        d += (f"M{pt(xa, y - r)}H{_fmt(xb * k + tx)}"
              f"A{rk} {rk} 0 0 1 {pt(xb, y + r)}H{_fmt(xa * k + tx)}"
              f"A{rk} {rk} 0 0 1 {pt(xa, y - r)}Z")
    return d


def far_radius(geo):
    """Der größte Abstand eines Randpunkts von der Mitte (50, 50)."""
    far = 0.0
    for x, y, nx, ny, hl, hr in geo["samples"]:
        for px, py in ((x + nx * hl, y + ny * hl), (x - nx * hr, y - ny * hr)):
            far = max(far, math.hypot(px - 50, py - 50))
    for c0, ln, x1, y, wd in geo["dashes"]:
        far = max(far, math.hypot(x1 + ln + wd / 2 - 50, y + wd / 2 - 50))
    return far


def _place(size, scale):
    """Maßstab und Verschiebung: das 100er-Raster mit [scale] mittig auf
    eine Kante [size]."""
    k = size * scale / 100
    t = size / 2 - 50 * k
    return k, t


def _android_vector(size_dp, viewport, d, color, comment):
    return f"""<?xml version="1.0" encoding="utf-8"?>
<!-- ERZEUGT von tool/brand_icons.py — nicht von Hand ändern.
{comment} -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="{size_dp}dp"
    android:height="{size_dp}dp"
    android:viewportWidth="{viewport}"
    android:viewportHeight="{viewport}">
    <path
        android:fillColor="{color}"
        android:pathData="{d}" />
</vector>
"""


def notification_xml():
    k, t = _place(100, NOTIFICATION_SCALE)
    return _android_vector(24, 100, outline(GEO["M"], k=k, tx=t, ty=t), "#FFFFFFFF", """
     Das Symbol in der Statusleiste, für Push (#34) und die
     Dauerbenachrichtigung der Fahrt (#28): die Serpentine in Größe M
     (ein Endstrich). Android wertet ein Statusleisten-Symbol NUR über den
     Alphakanal aus (jedes nicht durchsichtige Pixel wird weiß), deshalb
     weiß, eine Farbe, 12 % Rand.""")


def launcher_foreground_xml(color, what):
    k, t = _place(108, ADAPTIVE_SCALE)
    return _android_vector(108, 108, outline(GEO["L"], k=k, tx=t, ty=t), color, f"""
     {what} des adaptiven App-Symbols: die Serpentine in Größe L,
     mittig in den sichtbaren 72 von 108 dp, ganz im Kreis einer runden
     Maske.""")


def splash_xml():
    k, t = _place(100, SPLASH_SCALE)
    return _android_vector(288, 100, outline(GEO["L"], k=k, tx=t, ty=t), "@color/brand_mark", """
     Das Zeichen auf dem Startschirm ab Android 12 (values-v31/styles.xml):
     in der Marke des Modus, ohne Scheibe, im sichtbaren Kreis von 192 dp.
     Danach zeichnet der Splash der App dasselbe Zeichen.""")


ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<!-- ERZEUGT von tool/brand_icons.py — nicht von Hand ändern. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
"""


def favicon_svg():
    # Größe S (Tab: 16 px), Moos auf Hell, Lime auf Dunkel.
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
        f'<style>path{{fill:{MOSS}}}@media (prefers-color-scheme:dark)'
        f'{{path{{fill:{BRAND}}}}}</style>'
        f'<path d="{outline(GEO["S"])}"/></svg>\n'
    )


def _dart_list(values):
    return ", ".join(repr(float(v)) for v in values)


def dart_geometry():
    out = [
        "// ERZEUGT von tool/brand_icons.py aus tool/brand/logo_c3.json —",
        "// nicht von Hand ändern.",
        "part of 'trailbuddy_logo.dart';",
        "",
    ]
    for key in ("L", "M", "S"):
        g = GEO[key]
        out.append(f"const _logo{key} = LogoGeometry._(")
        out.append(f"  length: {float(g['length'])!r},")
        out.append(f"  total: {float(g['total'])!r},")
        out.append("  dashes: [")
        for c0, ln, x1, y, w in g["dashes"]:
            out.append(f"    (c0: {float(c0)!r}, len: {float(ln)!r}, x1: {float(x1)!r}, "
                       f"y: {float(y)!r}, w: {float(w)!r}),")
        out.append("  ],")
        out.append("  samples: <double>[")
        for smp in g["samples"]:
            out.append(f"    {_dart_list(smp)},")
        out.append("  ],")
        out.append(");")
        out.append("")
    return "\n".join(out)


def text_files():
    return {
        DART_GEOMETRY: dart_geometry(),
        os.path.join(RES, "drawable", "ic_notification.xml"): notification_xml(),
        os.path.join(RES, "drawable", "ic_launcher_foreground.xml"):
            launcher_foreground_xml("#FF0E1411", "Vordergrund"),
        os.path.join(RES, "drawable", "ic_launcher_monochrome.xml"):
            launcher_foreground_xml("#FFFFFFFF", "Themen-Variante (nur Alpha)"),
        os.path.join(RES, "drawable", "ic_splash.xml"): splash_xml(),
        os.path.join(RES, "mipmap-anydpi-v26", "ic_launcher.xml"): ADAPTIVE_XML,
        os.path.join("web", "favicon.svg"): favicon_svg(),
    }


def symbol_svg(px, scale, background, radius_ratio, color=ON_BRAND, size="L"):
    k, t = _place(100, scale)
    bg = ""
    if background:
        r = 100 * radius_ratio
        bg = f'<rect width="100" height="100" rx="{_fmt(r)}" fill="{background}"/>'
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{px}" height="{px}" '
        f'viewBox="0 0 100 100">{bg}'
        f'<path fill="{color}" d="{outline(GEO[size], k=k, tx=t, ty=t)}"/></svg>'
    )


def png_targets():
    t = {}
    for density, px in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                         ("xxhdpi", 144), ("xxxhdpi", 192)]:
        t[os.path.join(RES, f"mipmap-{density}", "ic_launcher.png")] = \
            symbol_svg(px, LEGACY_SCALE, BRAND, 0.22)
    for px in (192, 512):
        t[f"web/icons/Icon-{px}.png"] = symbol_svg(px, WEB_SCALE, BRAND, 0.22)
        t[f"web/icons/Icon-maskable-{px}.png"] = symbol_svg(px, MASKABLE_SCALE, BRAND, 0)
    # Die PNG ist der Rückfall für Browser ohne SVG-Favicon: eine Farbe.
    t["web/favicon.png"] = symbol_svg(32, 1.0, None, 0, color=MOSS, size="S")
    # Die Uhr (docs/konzept-garmin.md): 40 px, die Liste der Apps ist rund
    # und dunkel — eine volle Scheibe, Größe L (ab 32 px).
    t[os.path.join("garmin", "resources", "drawables", "launcher_icon.png")] = \
        symbol_svg(40, LEGACY_SCALE, BRAND, 0.5)
    return t


def write_all(root):
    for rel, text in text_files().items():
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
    with tempfile.TemporaryDirectory() as tmp:
        for rel, svg in png_targets().items():
            src = os.path.join(tmp, "icon.svg")
            with open(src, "w", encoding="utf-8") as f:
                f.write(svg)
            subprocess.run(["rsvg-convert", src, "-o", os.path.join(root, rel)],
                           check=True)


def check(root):
    """Die Textdateien sind ein Fixpunkt dieses Skripts."""
    stale = []
    for rel, text in text_files().items():
        path = os.path.join(root, rel)
        try:
            with open(path, encoding="utf-8") as f:
                if f.read() == text:
                    continue
        except FileNotFoundError:
            pass
        stale.append(rel)
    for rel in stale:
        print(f"{rel}: nicht aus tool/brand_icons.py erzeugt — "
              f"python3 tool/brand_icons.py laufen lassen", file=sys.stderr)
    return not stale


def self_test():
    # Drei Größen, je 241 Stichproben, L zwei Endstriche, M einer, S keiner.
    assert [len(GEO[k]["dashes"]) for k in "LMS"] == [2, 1, 0]
    for k in "LMS":
        g = GEO[k]
        assert len(g["samples"]) == 241 and all(len(s) == 6 for s in g["samples"]), k
        # Die Strecke wird schmaler (11 → 8 in L), nie breiter am Ende.
        w0 = sum(g["samples"][0][4:]); w1 = sum(g["samples"][-1][4:])
        assert w1 < w0, (k, w0, w1)
        # Die Endstriche liegen hinter der Strecke, der letzte am Ende.
        for c0, ln, *_ in g["dashes"]:
            assert g["length"] < c0 and c0 + ln <= g["total"] + 1e-9, k
    assert abs(sum(GEO["L"]["samples"][0][4:]) - 11) < 1e-9
    assert abs(sum(GEO["L"]["samples"][-1][4:]) - 8) < 1e-9
    # Adaptiv: der fernste Punkt bleibt im Kreis mit Radius 36 dp.
    k, _ = _place(108, ADAPTIVE_SCALE)
    assert far_radius(GEO["L"]) * k <= 36, far_radius(GEO["L"]) * k
    # Maskable: im Kreis mit 40 % Radius.
    assert far_radius(GEO["L"]) * MASKABLE_SCALE <= 40
    # Android 12: im sichtbaren Kreis von 192 dp auf 288 dp.
    assert far_radius(GEO["L"]) * SPLASH_SCALE / 100 * 288 <= 96
    # Ein Abschnitt ist eine geschlossene Fläche mit zwei Kappen; die
    # Endstriche kommen als eigene Pillen dazu.
    d = outline(GEO["L"])
    assert d.count("Z") == 1 + 2 and d.count("M") == 3, d[:80]
    assert outline(GEO["S"]).count("Z") == 1
    assert outline(GEO["L"], 0, 10).count("Z") == 1  # nur die Strecke
    assert outline(GEO["L"], 170, 176.52).count("Z") == 1  # nur der letzte Strich
    xml = notification_xml()
    assert "#FFFFFFFF" in xml and "0E1411" not in xml and "strokeColor" not in xml
    assert xml.count("<path") == 1
    svg = symbol_svg(48, LEGACY_SCALE, BRAND, 0.22)
    assert 'width="48"' in svg and svg.count("<path") == 1 and "stroke" not in svg
    assert "part of 'trailbuddy_logo.dart';" in dart_geometry()
    print("brand_icons self-test ok")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        self_test()
        return
    if args.check:
        sys.exit(0 if check(REPO_ROOT) else 1)
    write_all(REPO_ROOT)


if __name__ == "__main__":
    main()
