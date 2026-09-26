#!/usr/bin/env python3
"""Regenerate the Windows icons from the macOS artwork (run on macOS; uses sips only).

    python3 windows/installer/icons/make_icons.py

  App icon  windows/ime/res/viettelex.ico  (16 20 24 32 40 48 64 256)
            from App/Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png — sizes the
            set has are copied byte-for-byte, the others (20 24 40 48) are sips
            downscales of the next larger PNG. No redraw.
  Glyphs    windows/ime/res/glyph_<style>_<state>_<theme>.ico  (16 20 24 32 40 48)
            from the macOS menu-bar glyphs App/Resources/MenuIcon{1,2,3}.pdf
            (MenuIconSwitcher.swift: vt = MenuIcon1, star = MenuIcon2, flag = MenuIcon3),
            rasterised by sips at each size (vector, no scaling blur).
              theme  dark  = white glyph, for the dark taskbar
                     light = near-black glyph, for the light taskbar
              state  v = Vietnamese (full glyph)
                     e = English: the same glyph at 40% opacity. macOS has no English
                         state of its own glyph (the system shows the other input
                         source's icon), so "off" is the dimmed glyph.
  Profile   windows/ime/res/profile_<vt|star|flag|logo|vi>.ico  (16..48) — the
            static keyboard-profile icon: white glyph + dark outline (theme-neutral);
            vi is a simple vector "VI" drawn here, logo is the app icon.
Every ICO entry is a PNG (supported by Windows Vista+ LoadImage/LoadIconWithScaleDown).
"""
import os
import struct
import subprocess
import tempfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
RES = os.path.join(REPO, 'windows', 'ime', 'res')
APPICONS = os.path.join(REPO, 'App', 'Resources', 'Assets.xcassets', 'AppIcon.appiconset')
MENU = {'vt': 'MenuIcon1.pdf', 'star': 'MenuIcon2.pdf', 'flag': 'MenuIcon3.pdf'}
APP_SIZES = [16, 20, 24, 32, 40, 48, 64, 256]
GLYPH_SIZES = [16, 20, 24, 32, 40, 48]
THEMES = {'dark': (255, 255, 255), 'light': (0x1B, 0x1B, 0x1B)}
STATES = {'v': 1.0, 'e': 0.4}


def sips(src, out, size):
    subprocess.run(['sips', '-s', 'format', 'png', '-z', str(size), str(size), src, '--out', out],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def png_decode(data):
    i, idat = 8, b''
    while i < len(data):
        ln, typ = struct.unpack('>I4s', data[i:i + 8])
        chunk = data[i + 8:i + 8 + ln]
        i += 12 + ln
        if typ == b'IHDR':
            w, h, bd, ct = struct.unpack('>IIBB', chunk[:10])
        elif typ == b'IDAT':
            idat += chunk
    assert bd == 8 and ct == 6, 'expected 8-bit RGBA'
    raw, bpp = zlib.decompress(idat), 4
    stride, rows, prev, k = w * bpp, [], bytearray(w * 4), 0
    for _ in range(h):
        f = raw[k]
        k += 1
        line = bytearray(raw[k:k + stride])
        k += stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if f == 1:
                line[x] = (line[x] + a) & 255
            elif f == 2:
                line[x] = (line[x] + b) & 255
            elif f == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line)
        prev = line
    return w, h, rows


def png_encode(w, h, rows):
    raw = b''.join(b'\x00' + bytes(r) for r in rows)

    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def write_ico(path, entries):  # entries: [(size, png bytes)]
    out = struct.pack('<HHH', 0, 1, len(entries))
    off = 6 + 16 * len(entries)
    body = b''
    for size, png in entries:
        w = 0 if size >= 256 else size
        out += struct.pack('<BBBBHHII', w, w, 0, 0, 1, 32, len(png), off + len(body))
        body += png
    with open(path, 'wb') as f:
        f.write(out + body)


def main():
    tmp = tempfile.mkdtemp()
    have = {int(n[5:-4]): os.path.join(APPICONS, n) for n in os.listdir(APPICONS)
            if n.startswith('icon_') and n.endswith('.png')}
    entries = []
    for s in APP_SIZES:
        if s in have:
            entries.append((s, open(have[s], 'rb').read()))
        else:
            src = have[min(k for k in have if k > s)]
            out = os.path.join(tmp, f'app{s}.png')
            sips(src, out, s)
            entries.append((s, open(out, 'rb').read()))
    write_ico(os.path.join(RES, 'viettelex.ico'), entries)
    print('viettelex.ico', [s for s, _ in entries])

    for style, pdf in MENU.items():
        rasters = {}
        for s in GLYPH_SIZES:
            out = os.path.join(tmp, f'{style}{s}.png')
            sips(os.path.join(REPO, 'App', 'Resources', pdf), out, s)
            rasters[s] = png_decode(open(out, 'rb').read())
        for theme, rgb in THEMES.items():
            for state, opacity in STATES.items():
                ents = []
                for s, (w, h, rows) in rasters.items():
                    tinted = []
                    for r in rows:
                        line = bytearray(len(r))
                        for x in range(0, len(r), 4):
                            line[x:x + 3] = bytes(rgb)
                            line[x + 3] = int(r[x + 3] * opacity + 0.5)
                        tinted.append(line)
                    ents.append((s, png_encode(w, h, tinted)))
                name = f'glyph_{style}_{state}_{theme}.ico'
                write_ico(os.path.join(RES, name), ents)
                print(name)
    make_profile_icons(tmp)


# ---------------------------------------------------------------- profile icons
# The static keyboard-profile icon (Win+Space list, taskbar indicator where the TIP is not
# active) is one registry value, so it cannot follow the taskbar theme. These variants are
# a WHITE glyph with a 1-px dark outline: readable on both the light and the dark flyout.
PROFILE_CHOICES = ['vt', 'star', 'flag', 'logo', 'vi']


def polys_vi():  # "VI"
    return [[(0.06, 0.18), (0.22, 0.18), (0.37, 0.64), (0.52, 0.18), (0.68, 0.18), (0.45, 0.84), (0.29, 0.84)],
            [(0.76, 0.18), (0.91, 0.18), (0.91, 0.84), (0.76, 0.84)]]


def inside(poly, x, y):
    c = False
    for i in range(len(poly)):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % len(poly)]
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            c = not c
    return c


def raster_polys(polys, size, ss=4):
    rows = []
    for py in range(size):
        line = bytearray(size * 4)
        for px in range(size):
            hit = sum(1 for sy in range(ss) for sx in range(ss)
                      if any(inside(p, (px + (sx + .5) / ss) / size, (py + (sy + .5) / ss) / size) for p in polys))
            line[px * 4 + 3] = round(255 * hit / (ss * ss))
        rows.append(line)
    return rows


def outlined(rows, size):
    """White glyph over a 1-px near-black outline (alpha dilated by one pixel)."""
    a = [[rows[y][x * 4 + 3] for x in range(size)] for y in range(size)]
    out = []
    for y in range(size):
        line = bytearray(size * 4)
        for x in range(size):
            ring = max(a[yy][xx] for yy in range(max(0, y - 1), min(size, y + 2))
                       for xx in range(max(0, x - 1), min(size, x + 2)))
            g = a[y][x] / 255.0
            o = ring / 255.0 * 0.85
            alpha = g + o * (1 - g)
            v = int(255 * g / alpha) if alpha > 0 else 0          # white over dark outline
            line[x * 4:x * 4 + 4] = bytes((v, v, v, int(alpha * 255 + 0.5)))
        out.append(line)
    return out


def make_profile_icons(tmp):
    app_png = {s: open(os.path.join(APPICONS, f'icon_{s}.png'), 'rb').read() for s in (16, 32, 64)}
    for choice in PROFILE_CHOICES:
        ents = []
        for s in GLYPH_SIZES:
            if choice == 'logo':
                src = os.path.join(APPICONS, 'icon_64.png')
                out = os.path.join(tmp, f'logo{s}.png')
                if s in app_png:
                    ents.append((s, app_png[s]))
                    continue
                sips(src, out, s)
                ents.append((s, open(out, 'rb').read()))
                continue
            if choice in MENU:
                out = os.path.join(tmp, f'p{choice}{s}.png')
                sips(os.path.join(REPO, 'App', 'Resources', MENU[choice]), out, s)
                w, h, rows = png_decode(open(out, 'rb').read())
            else:
                rows = raster_polys(polys_vi(), s)
                w = h = s
            ents.append((s, png_encode(w, h, outlined(rows, s))))
        write_ico(os.path.join(RES, f'profile_{choice}.ico'), ents)
        print(f'profile_{choice}.ico')


if __name__ == '__main__':
    main()
