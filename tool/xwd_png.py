#!/usr/bin/env python3
"""Bilder des Simulators im Container (#533): XWD → PNG, nur Standardbibliothek.

Xvfb schreibt mit `-fbdir` seinen Bildschirm als XWD-Datei (`Xvfb_screen0`).
Dieses Skript macht daraus ein PNG — wahlweise nur ein Ausschnitt (die
Anzeige der Uhr) — und kann zwei Bilder vergleichen und eine Übersicht
mehrerer Bilder (Kontaktbogen) bauen. Kein ImageMagick, kein Pillow.

  tool/xwd_png.py frame.xwd out.png [--crop X,Y,B,H] [--round]
  tool/xwd_png.py --diff a.png b.png diff.png      Exit 1, wenn sie abweichen
  tool/xwd_png.py --sheet out.png a.png b.png …     nebeneinander, mit Rand
  tool/xwd_png.py --find frame.xwd geraet.png       Lage des Gerätebilds
  tool/xwd_png.py --self-test

`--round` färbt alles außerhalb des Kreises der Anzeige schwarz (runde
Uhr): Dort zeigt der Simulator das Gehäuse, das zu keinem Bild gehört.
"""
from __future__ import annotations

import struct
import sys
import zlib

Image = tuple  # (Breite, Höhe, bytes RGB)


# --- XWD lesen -------------------------------------------------------------

def read_xwd(data: bytes) -> Image:
    """Liest ein XWD (ZPixmap, 24/32 Bit) als RGB."""
    h = struct.unpack('>25I', data[:100])
    header_size, fmt, depth, width, height = h[0], h[2], h[3], h[4], h[5]
    byte_order, bpp, bpl = h[7], h[11], h[12]
    ncolors = h[19]
    if fmt != 2 or bpp not in (24, 32):
        raise ValueError(f'XWD nicht unterstützt: format={fmt} bpp={bpp} depth={depth}')
    step = bpp // 8
    off = header_size + ncolors * 12
    out = bytearray(width * height * 3)
    for y in range(height):
        row = data[off + y * bpl: off + y * bpl + width * step]
        o = y * width * 3
        if byte_order == 0:  # LSBFirst: B G R (X)
            out[o:o + width * 3:3] = row[2::step]
            out[o + 1:o + width * 3:3] = row[1::step]
            out[o + 2:o + width * 3:3] = row[0::step]
        else:  # MSBFirst: (X) R G B
            s = step - 3
            out[o:o + width * 3:3] = row[s::step]
            out[o + 1:o + width * 3:3] = row[s + 1::step]
            out[o + 2:o + width * 3:3] = row[s + 2::step]
    return width, height, bytes(out)


def make_xwd(width: int, height: int, rgb: bytes) -> bytes:
    """Ein XWD wie von Xvfb (LSBFirst, 32 Bit) — für den Selbsttest."""
    bpl = width * 4
    name = b'Xvfb\0'
    header_size = 100 + len(name)
    fields = [header_size, 7, 2, 24, width, height, 0, 0, 32, 0, 32, 32, bpl,
              4, 0xFF0000, 0xFF00, 0xFF, 8, 256, 0, width, height, 0, 0, 0]
    pix = bytearray()
    for i in range(0, len(rgb), 3):
        r, g, b = rgb[i:i + 3]
        pix += bytes((b, g, r, 0))
    return struct.pack('>25I', *fields) + name + bytes(pix)


# --- PNG schreiben und lesen ----------------------------------------------

def _chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data))


def write_png(img: Image) -> bytes:
    w, h, rgb = img
    rows = b''.join(b'\0' + rgb[y * w * 3:(y + 1) * w * 3] for y in range(h))
    return (b'\x89PNG\r\n\x1a\n'
            + _chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
            + _chunk(b'IDAT', zlib.compress(rows, 9))
            + _chunk(b'IEND', b''))


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def read_png(data: bytes) -> Image:
    """Liest 8-Bit-PNG (Graustufen, RGB, Palette, mit/ohne Alpha) als RGB.

    Alpha wird auf Weiß gelegt — so sieht der Simulator das Gerätebild nicht,
    aber für die Suche nach der Lage reichen die deckenden Bildpunkte.
    """
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('kein PNG')
    pos, idat, plte, trns = 8, b'', None, None
    w = h = depth = ctype = interlace = 0
    while pos < len(data):
        (n,) = struct.unpack('>I', data[pos:pos + 4])
        tag, body = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + n]
        pos += 12 + n
        if tag == b'IHDR':
            w, h, depth, ctype, _, _, interlace = struct.unpack('>IIBBBBB', body)
        elif tag == b'PLTE':
            plte = body
        elif tag == b'tRNS':
            trns = body
        elif tag == b'IDAT':
            idat += body
    if depth != 8 or interlace:
        raise ValueError(f'PNG nicht unterstützt: Tiefe {depth}, Interlace {interlace}')
    chans = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    raw = zlib.decompress(idat)
    stride = w * chans
    prev = bytearray(stride)
    out = bytearray(w * h * 3)
    p = 0
    for y in range(h):
        f = raw[p]
        line = bytearray(raw[p + 1:p + 1 + stride])
        p += 1 + stride
        for i in range(stride):
            a = line[i - chans] if i >= chans else 0
            b = prev[i]
            c = prev[i - chans] if i >= chans else 0
            if f == 1:
                line[i] = (line[i] + a) & 255
            elif f == 2:
                line[i] = (line[i] + b) & 255
            elif f == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif f == 4:
                line[i] = (line[i] + _paeth(a, b, c)) & 255
        prev = line
        for x in range(w):
            q = x * chans
            if ctype == 0:
                r = g = bl = line[q]; al = 255
            elif ctype == 4:
                r = g = bl = line[q]; al = line[q + 1]
            elif ctype == 2:
                r, g, bl = line[q:q + 3]; al = 255
            elif ctype == 6:
                r, g, bl, al = line[q:q + 4]
            else:
                k = line[q]
                r, g, bl = plte[k * 3:k * 3 + 3]
                al = trns[k] if trns is not None and k < len(trns) else 255
            if al < 255:
                r = (r * al + 255 * (255 - al)) // 255
                g = (g * al + 255 * (255 - al)) // 255
                bl = (bl * al + 255 * (255 - al)) // 255
            o = (y * w + x) * 3
            out[o:o + 3] = bytes((r, g, bl))
    return w, h, bytes(out)


# --- Ausschnitt, Kreis, Vergleich, Bogen ---------------------------------

def crop(img: Image, x: int, y: int, cw: int, ch: int) -> Image:
    w, h, rgb = img
    if x < 0 or y < 0 or x + cw > w or y + ch > h:
        raise ValueError(f'Ausschnitt {x},{y},{cw},{ch} liegt nicht im Bild {w}x{h}')
    rows = [rgb[((y + r) * w + x) * 3:((y + r) * w + x + cw) * 3] for r in range(ch)]
    return cw, ch, b''.join(rows)


def mask_round(img: Image) -> Image:
    w, h, rgb = img
    out = bytearray(rgb)
    cx, cy, rr = (w - 1) / 2, (h - 1) / 2, (min(w, h) / 2) ** 2
    for y in range(h):
        for x in range(w):
            if (x - cx) ** 2 + (y - cy) ** 2 > rr:
                o = (y * w + x) * 3
                out[o:o + 3] = b'\0\0\0'
    return w, h, bytes(out)


def diff(a: Image, b: Image) -> tuple[int, Image]:
    """Zahl der abweichenden Bildpunkte und ein Bild: grau = gleich, rot = anders."""
    if a[:2] != b[:2]:
        w, h = max(a[0], b[0]), max(a[1], b[1])
        return w * h, (w, h, b'\xff\0\0' * (w * h))
    w, h, ra = a
    rb = b[2]
    out = bytearray(w * h * 3)
    n = 0
    for i in range(0, len(ra), 3):
        if ra[i:i + 3] != rb[i:i + 3]:
            n += 1
            out[i:i + 3] = b'\xff\0\0'
        else:
            v = (ra[i] + ra[i + 1] + ra[i + 2]) // 9 + 170
            out[i:i + 3] = bytes((v, v, v))
    return n, (w, h, bytes(out))


def sheet(imgs: list[Image], cols: int = 4, gap: int = 8) -> Image:
    cw = max(i[0] for i in imgs)
    ch = max(i[1] for i in imgs)
    rows = (len(imgs) + cols - 1) // cols
    ncols = min(cols, len(imgs))
    w, h = ncols * cw + (ncols + 1) * gap, rows * ch + (rows + 1) * gap
    out = bytearray(b'\x60' * (w * h * 3))
    for k, (iw, ih, rgb) in enumerate(imgs):
        ox = gap + (k % cols) * (cw + gap)
        oy = gap + (k // cols) * (ch + gap)
        for y in range(ih):
            o = ((oy + y) * w + ox) * 3
            out[o:o + iw * 3] = rgb[y * iw * 3:(y + 1) * iw * 3]
    return w, h, bytes(out)


def find(frame: Image, needle: Image, step: int = 7) -> tuple[int, int]:
    """Wo liegt `needle` (das Gerätebild) im Bildschirm? Lage der linken oberen Ecke.

    Verglichen wird ein Raster von Stichproben aus dem Gerätebild; reines
    Weiß (durchsichtig) zählt nicht. Exakter Treffer ist nicht nötig — der
    Simulator kann das Bild glätten —, es gewinnt die kleinste Abweichung.
    """
    fw, fh, fr = frame
    nw, nh, nr = needle
    pts = []
    for y in range(0, nh, step):
        for x in range(0, nw, step):
            o = (y * nw + x) * 3
            px = nr[o:o + 3]
            if px != b'\xff\xff\xff':
                pts.append((x, y, px))
    if not pts:
        raise ValueError('Gerätebild ohne deckende Bildpunkte')
    best, where = None, (0, 0)
    sample = pts[::max(1, len(pts) // 60)]
    for oy in range(0, fh - nh + 1):
        for ox in range(0, fw - nw + 1):
            s = 0
            for x, y, px in sample:
                o = ((oy + y) * fw + ox + x) * 3
                s += abs(fr[o] - px[0]) + abs(fr[o + 1] - px[1]) + abs(fr[o + 2] - px[2])
                if best is not None and s >= best:
                    break
            if best is None or s < best:
                best, where = s, (ox, oy)
    # Genauer nachrechnen mit allen Stichproben um den Treffer.
    best2, where2 = None, where
    for oy in range(max(0, where[1] - 2), min(fh - nh, where[1] + 2) + 1):
        for ox in range(max(0, where[0] - 2), min(fw - nw, where[0] + 2) + 1):
            s = 0
            for x, y, px in pts:
                o = ((oy + y) * fw + ox + x) * 3
                s += abs(fr[o] - px[0]) + abs(fr[o + 1] - px[1]) + abs(fr[o + 2] - px[2])
            if best2 is None or s < best2:
                best2, where2 = s, (ox, oy)
    return where2


# --- Kommandozeile --------------------------------------------------------

def _load(path: str) -> Image:
    data = open(path, 'rb').read()
    return read_png(data) if data[:4] == b'\x89PNG' else read_xwd(data)


def _save(path: str, img: Image) -> None:
    with open(path, 'wb') as f:
        f.write(write_png(img))


def self_test() -> int:
    w, h = 6, 4
    rgb = b''.join(bytes((x * 40, y * 60, (x + y) * 10)) for y in range(h) for x in range(w))
    img = read_xwd(make_xwd(w, h, rgb))
    assert img == (w, h, rgb), 'XWD → RGB stimmt nicht'
    back = read_png(write_png(img))
    assert back == img, 'PNG hin und zurück stimmt nicht'
    c = crop(img, 2, 1, 3, 2)
    assert c[2][:3] == bytes((80, 60, 30)), c[2][:3]
    n, _ = diff(img, img)
    assert n == 0
    other = bytearray(rgb)
    other[0] ^= 1
    n, d = diff(img, (w, h, bytes(other)))
    assert n == 1 and d[2][:3] == b'\xff\0\0', 'ein Bildpunkt anders muss zählen'
    m = mask_round((5, 5, b'\x80' * 75))
    assert m[2][:3] == b'\0\0\0' and m[2][(2 * 5 + 2) * 3] == 0x80, 'Kreis'
    s = sheet([img, c], cols=2, gap=1)
    assert s[0] == 1 + 6 + 1 + 6 + 1 and s[1] == 1 + 4 + 1
    big = bytearray(b'\xff' * (20 * 15 * 3))
    for y in range(4):
        for x in range(6):
            o = ((5 + y) * 20 + 9 + x) * 3
            big[o:o + 3] = rgb[(y * 6 + x) * 3:(y * 6 + x) * 3 + 3]
    assert find((20, 15, bytes(big)), img, step=1) == (9, 5), 'Lage des Gerätebilds'
    print('xwd_png: Selbsttest grün')
    return 0


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ('-h', '--help'):
        print(__doc__)
        return 0
    if argv[0] == '--self-test':
        return self_test()
    if argv[0] == '--diff':
        a, b, out = argv[1:4]
        n, d = diff(_load(a), _load(b))
        if n:
            _save(out, d)
            print(f'{n} Bildpunkte anders — {out}')
            return 1
        return 0
    if argv[0] == '--sheet':
        cols = 4
        rest = argv[1:]
        if rest[0] == '--cols':
            cols, rest = int(rest[1]), rest[2:]
        out, files = rest[0], rest[1:]
        _save(out, sheet([_load(f) for f in files], cols=cols))
        return 0
    if argv[0] == '--find':
        x, y = find(_load(argv[1]), _load(argv[2]))
        print(x, y)
        return 0
    src, out = argv[0], argv[1]
    img = _load(src)
    rest = argv[2:]
    rnd = '--round' in rest
    if '--crop' in rest:
        x, y, cw, ch = (int(v) for v in rest[rest.index('--crop') + 1].split(','))
        img = crop(img, x, y, cw, ch)
    if rnd:
        img = mask_round(img)
    _save(out, img)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
