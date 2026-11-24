#!/usr/bin/env python3
"""Generate synthetic MBTiles fixtures and check simulator screenshots."""
import gzip
import sqlite3
import struct
import sys
import zlib
from pathlib import Path


def varint(value):
    result = bytearray()
    while value >= 128:
        result.append((value & 127) | 128)
        value >>= 7
    result.append(value)
    return bytes(result)


def field(number, payload):
    return varint(number * 8 + 2) + varint(len(payload)) + payload


def vector_tile():
    # A synthetic square in tile coordinates, not a real location or route.
    def zigzag(value):
        return (value << 1) ^ (value >> 63)

    commands = [9, zigzag(0), zigzag(0), 26, zigzag(4096), zigzag(0),
                zigzag(0), zigzag(4096), zigzag(-4096), zigzag(0), 15]
    geometry = b''.join(varint(value) for value in commands)
    feature = varint(8) + varint(1) + varint(24) + varint(3) + field(4, geometry)
    layer = field(1, b'test') + field(2, feature) + varint(40) + varint(4096) + varint(120) + varint(2)
    return gzip.compress(field(3, layer), mtime=0)


def raster_tile():
    def chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data) & 0xffffffff)

    pixels = (b'\0' + bytes([220, 35, 50, 255]) * 256) * 256
    header = struct.pack('!IIBBBBB', 256, 256, 8, 6, 0, 0, 0)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')


def make_fixture(path, vector, include_tile):
    db = sqlite3.connect(path)
    try:
        db.executescript('CREATE TABLE metadata (name TEXT, value TEXT); CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB);')
        meta = [('name', 'synthetic'), ('format', 'pbf' if vector else 'png'),
                ('type', 'baselayer'), ('version', '1'), ('minzoom', '0'), ('maxzoom', '0'),
                ('bounds', '-180,-85,180,85')]
        if vector:
            meta.append(('json', '{"vector_layers":[{"id":"test","fields":{},"minzoom":0,"maxzoom":0}]}'))
        db.executemany('INSERT INTO metadata VALUES (?, ?)', meta)
        if include_tile:
            db.execute('INSERT INTO tiles VALUES (0, 0, 0, ?)', (vector_tile() if vector else raster_tile(),))
        db.commit()
    finally:
        db.close()


def check_bmp(path, expected):
    data = Path(path).read_bytes()
    if data[:2] != b'BM':
        raise ValueError('Expected a BMP screenshot')
    offset = struct.unpack_from('<I', data, 10)[0]
    width, height, planes, bits = struct.unpack_from('<iiHH', data, 18)
    if width <= 0 or height == 0 or planes != 1 or bits != 32:
        raise ValueError('Unsupported screenshot BMP format')
    height = abs(height)
    pos = offset + (height // 2 * width + width // 2) * 4
    blue, green, red = data[pos:pos + 3]
    ok = red > 150 and blue < 100 and green < 100 if expected == 'red' else blue > 150 and red < 100 and green < 150
    if not ok:
        raise ValueError(f'Expected {expected} at screen centre, got RGB {red},{green},{blue}')
    print(f'{expected}: centre RGB {red},{green},{blue}')


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == 'generate':
        directory = Path(sys.argv[2])
        directory.mkdir(parents=True, exist_ok=True)
        for kind in ('raster', 'vector'):
            for suffix, include in (('tile', True), ('empty', False)):
                make_fixture(directory / f'{kind}_{suffix}.mbtiles', kind == 'vector', include)
    elif len(sys.argv) == 4 and sys.argv[1] == 'check' and sys.argv[3] in ('red', 'blue'):
        check_bmp(sys.argv[2], sys.argv[3])
    else:
        raise SystemExit('Usage: fixture.py generate DIR | check SCREENSHOT.bmp red|blue')
