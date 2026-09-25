#!/usr/bin/env python3
"""Generate viettelex.ico (16/20/24/32/48/64/256 px) with no third-party deps.

Glyph: a bold "V" with a small "T" at the lower right (the Vᴛ mark), dark blue on
transparent. Rasterised by 4x4 supersampling of simple polygons. Run from this
directory: python3 make_icon.py  -> viettelex.ico
"""
import struct
import zlib

SIZES = [16, 20, 24, 32, 48, 64, 256]
COLOR = (0x1F, 0x4E, 0x9C)  # RGB


def inside(poly, x, y):
    c = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            xi = x1 + (y - y1) * (x2 - x1) / (y2 - y1)
            if x < xi:
                c = not c
    return c


def shapes():
    # Unit square coordinates (0..1), y down.
    v_left = [(0.04, 0.10), (0.22, 0.10), (0.42, 0.72), (0.34, 0.92)]
    v_right = [(0.62, 0.10), (0.80, 0.10), (0.50, 0.92), (0.34, 0.92), (0.42, 0.72)]
    t_bar = [(0.60, 0.52), (0.98, 0.52), (0.98, 0.64), (0.60, 0.64)]
    t_stem = [(0.73, 0.52), (0.85, 0.52), (0.85, 0.92), (0.73, 0.92)]
    return [v_left, v_right, t_bar, t_stem]


def render(size):
    ss = 4
    polys = shapes()
    rows = []
    for py in range(size):
        row = []
        for px in range(size):
            hit = 0
            for sy in range(ss):
                for sx in range(ss):
                    x = (px + (sx + 0.5) / ss) / size
                    y = (py + (sy + 0.5) / ss) / size
                    if any(inside(p, x, y) for p in polys):
                        hit += 1
            row.append(round(255 * hit / (ss * ss)))
        rows.append(row)
    return rows


def png(size, alpha):
    raw = b""
    for row in alpha:
        raw += b"\x00" + b"".join(struct.pack("BBBB", *COLOR, a) for a in row)

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)) +
            chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def bmp_entry(size, alpha):
    # 32-bit BI_RGB DIB, bottom-up, height doubled (XOR + AND mask).
    hdr = struct.pack("<IiiHHIIiiII", 40, size, size * 2, 1, 32, 0, 0, 0, 0, 0, 0)
    xor = b""
    for row in reversed(alpha):
        xor += b"".join(struct.pack("BBBB", COLOR[2], COLOR[1], COLOR[0], a) for a in row)
    stride = ((size + 31) // 32) * 4
    andmask = b"\x00" * (stride * size)
    return hdr + xor + andmask


def main():
    images = []
    for s in SIZES:
        a = render(s)
        images.append((s, png(s, a) if s >= 64 else bmp_entry(s, a)))
    out = struct.pack("<HHH", 0, 1, len(images))
    offset = 6 + 16 * len(images)
    body = b""
    for s, data in images:
        w = 0 if s >= 256 else s
        out += struct.pack("<BBBBHHII", w, w, 0, 0, 1, 32, len(data), offset + len(body))
        body += data
    with open("viettelex.ico", "wb") as f:
        f.write(out + body)


if __name__ == "__main__":
    main()
