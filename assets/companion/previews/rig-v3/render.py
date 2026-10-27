#!/usr/bin/env python3
"""Stdlib-only BuddyPiece preview/parity checker. Run from any directory.

Reads actual Swift and Kotlin rig tables, including the original limb helpers.
The BEFORE revision is pinned so previews remain reproducible after committing.
Writes four SVG contact sheets (awake/sleep, before/after, dark/light), a data
report, and optionally PNGs via Quick Look: python3 render.py --png.
No app build, simulator, emulator, or third-party Python package is used.
"""
import argparse
import copy
import math
import html
import json
import re
import subprocess
from pathlib import Path

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[3]
SWIFT = 'iOS/Keyboard/KeyboardBuddy.swift'
KOTLIN = 'android/keyboard/src/main/kotlin/com/viettelex/keyboard/KeyboardBuddy.kt'
BEFORE = '111c61f44a9d87e51f0abebb37b5dda7ff201b8f'
SHARP = None
OLD_NAMES = ('girl', 'boy', 'cat', 'chick')
NEW_NAMES = ('shiba', 'koi', 'panda', 'pig', 'dragon', 'eagle')
NAMES = OLD_NAMES + NEW_NAMES
PARTS = ('tail', 'legL', 'legR', 'body', 'armL', 'armR', 'head', 'sleep')
NUM = r'-?(?:\d*\.)?\d+'


def numbers(s):
    return [float(n) for n in re.findall(NUM, s)]


def split(s):
    """Split top-level comma arguments without evaluating source code."""
    parts, start, depth, quoted = [], 0, 0, False
    for i, ch in enumerate(s):
        if ch == '"':
            quoted = not quoted
        if quoted:
            continue
        if ch in '([':
            depth += 1
        elif ch in ')]':
            depth -= 1
        elif ch == ',' and depth == 0:
            parts.append(s[start:i].strip())
            start = i + 1
    parts.append(s[start:].strip())
    return [p for p in parts if p]


def calls(s):
    pattern = re.compile(r'\b(P|C|E|R|L|limb|BuddyPiece)\(')
    pos = 0
    while match := pattern.search(s, pos):
        start = match.end()
        pos, depth, quoted = start, 1, False
        while depth:
            ch = s[pos]
            if ch == '"':
                quoted = not quoted
            elif not quoted:
                depth += (ch == '(') - (ch == ')')
            pos += 1
        yield match[1], split(s[start:pos - 1])


def parse(source, name):
    start = source.index(f'static let {name}: BuddyRig = {{')
    block = source[start:source.index('    }()', start)]
    constants = dict(re.findall(r'\b(\w+)(?:: UInt32)? = (0x[0-9A-Fa-f]+)', block))
    constants['ink'] = '0x3A2A2A'

    def value(v):
        v = constants.get(v, v)
        if v == 'nil':
            return None
        if v.startswith('"'):
            return ''.join(re.findall(r'"([^"]*)"', v))
        if v.startswith('('):
            return numbers(v)
        if v.startswith('0x'):
            return int(v, 16)
        if v.startswith('.color('):
            return value(v[7:-1])
        if v.startswith('.'):
            return v[1:]
        return float(v)

    pieces = []
    for kind, args in calls(block[:block.index('return BuddyRig(')]):
        positional, opts = [], {}
        for arg in args:
            named = re.match(r'^(fill|alpha|stroke|width|show|turn):\s*(.*)', arg, re.S)
            if named:
                opts[named[1]] = value(named[2])
            else:
                positional.append(arg)
        part = value(positional.pop(0))
        p = dict(part=part, fill=None, alpha=1., stroke='outline', width=6., show='always', turn=None)
        p.update(opts)
        if kind == 'BuddyPiece':
            sh = re.fullmatch(r'\.(\w+)\((.*)\)', positional[0], re.S)
            p.update(shape=sh[1], args=[value(v) for v in split(sh[2])])
        else:
            vals = [value(v) for v in positional]
            if kind == 'limb':
                d, color, width = vals
                for stroke, w in [('outline', width + 5), (color, width)]:
                    pieces.append(dict(p, shape='path', args=[d], stroke=stroke, width=w))
                continue
            p['shape'] = {'P': 'path', 'L': 'path', 'C': 'circle', 'E': 'ellipse', 'R': 'rrect'}[kind]
            if kind == 'L':
                p.update(args=vals[:1], stroke=vals[1], width=vals[2])
            else:
                p['args'] = vals
        if p['shape'] == 'path':
            assert set(re.findall(r'[A-Za-z]', p['args'][0])) <= set('MLHVQZmlhvqz'), p
        pieces.append(p)
    meta = block[block.index('return BuddyRig('):]
    rig = dict(pieces=pieces)
    for field, default in [('heart', [0, 46, 11]), ('face', [0, -6, 24, 18]),
                           ('hat', [0, -42, 34]), ('sleepHat', [-34, -2, 26]),
                           ('neck', [0, 18]), ('hand', [23, 64]), ('feet', None)]:
        match = re.search(rf'\b{field}: \(([^)]*)\)', meta)
        rig[field] = numbers(match[1]) if match else default
    rig['brows'] = re.search(r'brows: "([^"]*)"', meta)[1] if 'brows:' in meta else 'M-16 -25 L-6 -21 M16 -25 L6 -21'
    rig['full'] = numbers(re.search(r'full: BuddyRect\(([^)]*)\)', meta)[1])
    rig['sleepBottom'] = float(re.search(r'sleepBottom: (' + NUM + ')', meta)[1])
    bb = re.search(r'barBottom: (nil|' + NUM + ')', meta)[1]
    rig['barBottom'] = None if bb == 'nil' else float(bb)
    rig['pivots'] = {p: numbers(v) for p, v in re.findall(r'\.(\w+): \(([^)]*)\)', re.search(r'pivots: \[([^]]*)\]', meta)[1])}
    rig['zzz'] = [numbers(v) for v in re.findall(r'\(([^)]*)\)', re.search(r'zzz: \[([^]]*)\]', meta)[1])]
    rig['style'] = dict(re.findall(r'(\w+): (true|false|' + NUM + ')', re.search(r'style: \.init\(([^)]*)\)', meta)[1]))
    # Normalize numeric strings for Kotlin's explicit .0 literals.
    rig['style'] = {k: v if v in ('true', 'false') else float(v) for k, v in rig['style'].items()}
    return rig


def kotlin_as_swift(source):
    """Normalize only the four declarative tables, then use the same parser."""
    source = re.sub(r'val (GIRL|BOY|CAT|CHICK|SHIBA|KOI|PANDA|PIG|DRAGON|EAGLE): BuddyRig = run \{', lambda m: f'static let {m[1].lower()}: BuddyRig = {{', source)
    for swift, kt in zip(PARTS, ('TAIL', 'LEG_L', 'LEG_R', 'BODY', 'ARM_L', 'ARM_R', 'HEAD', 'SLEEP')):
        source = source.replace('BuddyPart.' + kt, '.' + swift)
    for a, b in [('Stroke.None', '.none'), ('Stroke.Outline', '.outline'), ('Stroke.Ink', '.ink'),
                 ('Stroke.Color', '.color'), ('Show.REST', '.rest'), ('Show.DANCE', '.dance'), ('Show.ALWAYS', '.always')]:
        source = source.replace(a, b)
    source = re.sub(r'\b(fill|alpha|stroke|width|show|turn|pieces|pivots|full|barBottom|feet|sleepBottom|zzz|style|heart|face|brows|hat|sleepHat|neck|hand|armL|armR|armAmp|alternate|kick|bounce|step) = ', r'\1: ', source)
    source = source.replace('null', 'nil').replace('            BuddyRig(\n', '        return BuddyRig(\n')
    source = re.sub(r'\bP[234]\(', '(', source).replace('BuddyDance.Style(', '.init(')
    source = re.sub(r'\.(\w+) to \(', r'.\1: (', source)
    source = re.sub(r'pivots: mapOf\((.*?)\),\n', r'pivots: [\1],\n', source)
    source = re.sub(r'zzz: listOf\((.*?)\),\n', r'zzz: [\1],\n', source)
    source = source.replace('\n        }\n', '\n    }()\n')
    return source


def checksum(r):
    s = 0.
    for p in r['pieces']:
        s += PARTS.index(p['part']) + p['width'] + p['alpha'] + (p['fill'] or 0) / 65536
        st = p['stroke']
        s += 4 + st / 65536 if isinstance(st, int) else {'none': 1, 'outline': 2, 'ink': 3}[st]
        s += {'always': 0, 'rest': 5, 'dance': 7}[p['show']]
        s += sum(p['turn'] or [])
        s += sum(numbers(p['args'][0])) if p['shape'] == 'path' else sum(p['args'])
    for x, y in r['pivots'].values():
        s += x * 3 + y * 5
    s += sum(r['full']) + (r['barBottom'] or 0) + sum(r['feet']) + r['sleepBottom']
    s += sum(sum(z) for z in r['zzz'])
    x, y, size = r['heart']
    s += x + y * 2 + size * 3
    s += sum(r['face']) + sum(numbers(r['brows'])) + sum(r['hat']) + sum(r['sleepHat'])
    s += sum(r['neck']) + sum(r['hand']) * 2
    return f'{s:.4f}'


def color(c):
    return 'none' if c is None else f'#{c:06X}'


def shape(p, dark, halo=False, scale=1):
    a, kind = p['args'], p['shape']
    if kind == 'path':
        tag, attrs = 'path', f'd="{html.escape(a[0], quote=True)}"'
    else:
        keys = {'circle': ('cx', 'cy', 'r'), 'ellipse': ('cx', 'cy', 'rx', 'ry'),
                'rrect': ('x', 'y', 'width', 'height', 'rx')}[kind]
        tag = 'rect' if kind == 'rrect' else kind
        attrs = ' '.join(f'{key}="{val:g}"' for key, val in zip(keys, a))
    if halo:
        stroke = '#F4F4F4' if dark else '#3A2A2A'
        fill = stroke if p['fill'] is not None else 'none'
        width = (6 if p['fill'] is not None else p['width']) + 3.5 / scale
        alpha = 1
    else:
        stroke = p['stroke']
        stroke = color(stroke) if isinstance(stroke, int) else {'none': 'none', 'ink': '#3A2A2A', 'outline': '#4A3A38' if dark else '#3A2A2A'}[stroke]
        fill, width, alpha = color(p['fill']), p['width'], p['alpha']
    turn = '' if not p['turn'] else ' transform="rotate(%s)"' % ' '.join(str(v) for v in p['turn'])
    return f'<{tag} {attrs} fill="{fill}" fill-opacity="{alpha}" stroke="{stroke}" stroke-width="{width:g}"{turn}/>'


def pose(r, dark, sleeping, x, y, w=250, h=280, dance=False, motion=None):
    vx, vy, vw, vh = r['full']
    scale = min((w - 30) / vw, (h - 30) / vh)
    tx, ty = x + (w - vw * scale) / 2 - vx * scale, y + (h - vh * scale) / 2 - vy * scale
    dy = vy + vh - 4 - r['sleepBottom'] if sleeping else 0
    pieces = sorted([p for p in r['pieces'] if (p['part'] == 'sleep') == sleeping], key=lambda p: 5.5 if p.get('prop') else PARTS.index(p['part']))
    out = [f'<g transform="translate({tx:g} {ty:g}) scale({scale:g}) translate(0 {dy:g})" stroke-linecap="round" stroke-linejoin="round">']
    # UIKit halo includes hidden rest/dance shapes; draw the full silhouette first.
    if motion:
        fx, fy = r['feet']
        out.append(f'<g transform="translate({motion["dx"]} {motion["dy"]}) translate({fx} {fy}) rotate({math.degrees(motion["rot"])}) scale({motion["sx"]} 1) translate({-fx} {-fy})">')
    def moving(piece, halo=False):
        drawing = shape(piece, dark, halo, scale)
        if motion and not piece.get('prop') and piece['part'] in r['pivots']:
            px, py = r['pivots'][piece['part']]
            angle = math.degrees(motion.get(piece['part'], 0))
            drawing = f'<g transform="rotate({angle} {px} {py})">{drawing}</g>'
        return drawing
    out += [moving(p, True) for p in pieces if p['alpha'] == 1 and not p.get('prop')]
    out += [moving(p) for p in pieces if p['show'] in ('always', 'dance' if dance else 'rest')]
    if motion:
        out.append('</g>')
    if sleeping:
        for zx, zy, size in r['zzz']:
            out.append(f'<path d="M{zx} {zy} h{size} l{-size} {size} h{size}" fill="none" stroke="#8AA6E8" stroke-width="4.5"/>')
    out.append('</g>')
    return '\n'.join(out)


def render(name, before, after):
    title = f'{name.title()} / vector rig v3'
    out = ['<svg xmlns="http://www.w3.org/2000/svg" width="1100" height="740" viewBox="0 0 1100 740">', f'<title>{title}: before and after, awake and asleep, on dark and light backgrounds</title>']
    for theme, dark in enumerate((True, False)):
        x = theme * 550
        fg = '#F2F2F7' if dark else '#302C38'
        out += [f'<rect x="{x}" width="550" height="740" fill="{ "#1C1C1E" if dark else "#F2F2F7"}"/>',
                f'<g fill="{fg}" font-family="Helvetica,Arial,sans-serif"><text x="{x+25}" y="36" font-size="20" font-weight="bold">{title}</text>',
                f'<text x="{x+25}" y="62" font-size="12">{ "DARK · #1C1C1E" if dark else "LIGHT · #F2F2F7"} · actual piece data + renderer halo</text>']
        for col, (label, r) in enumerate((('BEFORE', before), ('AFTER', after))):
            xx = x + 25 + col * 260
            out.append(f'<text x="{xx+125}" y="92" font-size="13" text-anchor="middle">{label} · {len(r["pieces"])} pieces</text>')
        out.append('</g>')
        for row, sleeping in enumerate((False, True)):
            yy = 112 + row * 302
            for col, r in enumerate((before, after)):
                xx = x + 25 + col * 260
                out.append(pose(r, dark, sleeping, xx, yy))
            out.append(f'<text x="{x+275}" y="{yy+292}" fill="{fg}" font-family="Helvetica,Arial,sans-serif" text-anchor="middle" font-size="12">{"ASLEEP · bottom aligned + Zzz" if sleeping else "AWAKE · neutral pivots"}</text>')
    out.append('</svg>')
    path = OUT / f'{name}.svg'
    path.write_text('\n'.join(out) + '\n')
    return path



SEASONS = ('tet', 'christmas', 'halloween', 'midAutumn')
PROPS = ('luckyMoney', 'gift', 'candy', 'mooncake')
MOVES = ('bounce', 'hipSway', 'wave', 'clap', 'dab', 'skip', 'flossLite', 'spin', 'chicken')


def accessories(source, kotlin=False):
    start = source.index('object BuddyAccessory' if kotlin else 'enum BuddyAccessory')
    block = source[start:source.index('fun place(' if kotlin else 'static func place(', start)]
    if kotlin:
        block = re.sub(r'val (\w+): List<BuddyPiece> by lazy \{ listOf\(', r'static let \1: [BuddyPiece] = [', block)
        block = block.replace(') }', ']')
        block = block.replace('BuddyPart.BODY', '.body').replace('Shape.Path', '.path').replace('null', 'nil')
        block = block.replace('Stroke.Outline', '.outline').replace('Stroke.None', '.none').replace('Stroke.Color', '.color')
    out = {}
    for name, rows in re.findall(r'static let (\w+): \[BuddyPiece\] = \[(.*?)\n    \]', block, re.S):
        ps = []
        for kind, args in calls(rows):
            assert kind == 'BuddyPiece'
            args = [re.sub(r'^(fill|alpha|stroke|width): ', '', a) for a in args]
            part, path, fill, alpha, stroke, width = args
            stroke = int(stroke[7:-1], 16) if stroke.startswith('.color') else stroke[1:]
            ps.append(dict(part='body', shape='path', args=[path[7:-2]],
                           fill=None if fill == 'nil' else int(fill, 16), alpha=float(alpha),
                           stroke=stroke, width=float(width), show='always', turn=None))
        assert 0 < len(ps) <= 8, name
        out[name] = ps
    assert len(out) == 13
    return out


def place(art, part, x, y, size):
    out = copy.deepcopy(art)
    for p in out:
        p['part'] = part
        i = 0
        def coordinate(m):
            nonlocal i
            origin = x if i % 2 == 0 else y
            i += 1
            return f'{origin + float(m[0]) * size / 32:.2f}'
        p['args'][0] = re.sub(NUM, coordinate, p['args'][0])
    return out


def costume(r, name, season, art):
    r = copy.deepcopy(r)
    h, sh = r['hat'], r['sleepHat']
    sn = [sh[0] + sh[2] * 1.15, sh[1] + sh[2] * 1.8]
    recolor, extra = {}, []
    def at(key, part, a): return place(art[key], part, *a)
    if season == 'tet':
        if name == 'girl':
            recolor = {0xFFB3C7: 0xDE5263, 0xDF8EAB: 0xB93650, 0xFF6F91: 0xF8D77B, 0xFFF0F4: 0xF8D77B}
            extra = at('pattern', 'body', [r['neck'][0], r['neck'][1] + 10, h[2]]) + at('pattern', 'sleep', [sh[0] + sh[2] * 2.4, sh[1] + sh[2] * 1.4, sh[2] * .6])
        elif name == 'boy':
            recolor = {0x304563: 0xDE5263, 0x536B8C: 0xF18B95}
            extra = at('khanDong', 'head', h) + at('khanDong', 'sleep', sh)
        else:
            extra = at('bow', 'head', r['neck'] + [22]) + at('bow', 'sleep', sn + [22])
    elif season == 'christmas' and name == 'koi':
        extra = at('bow', 'head', r['neck'] + [22]) + at('bow', 'sleep', sn + [22])
    elif season in ('christmas', 'halloween'):
        key = 'santa' if season == 'christmas' else 'witch' if name == 'girl' else 'pumpkin'
        extra = at(key, 'head', h) + at(key, 'sleep', sh)
    else:
        x = sh[0] + sh[2] * (2.3 if name == 'chick' else .9)
        y = sh[1] + sh[2] * (1.6 if name == 'chick' else 2.1)
        sleeping = at('lantern', 'sleep', [x, y, 24])
        for piece in sleeping: piece['turn'] = [-70, x, y]
        extra = at('lantern', 'armR', r['hand'] + [24]) + sleeping
    for sleeping in (False, True):
        assert sum((p['part'] == 'sleep') == sleeping for p in extra) <= 8
    for p in r['pieces']:
        p['fill'] = recolor.get(p['fill'], p['fill'])
        if isinstance(p['stroke'], int): p['stroke'] = recolor.get(p['stroke'], p['stroke'])
    r['pieces'] += extra
    return r


def move_pose(style, move, phase, tier=3):
    # Same pure formulas as BuddyDance; no renderer-specific motion adjustments.
    p = phase % 1
    o = dict.fromkeys(('dx', 'dy', 'rot', 'head', 'armL', 'armR', 'legL', 'legR', 'tail'), 0.)
    o['sx'] = 1.
    if p == 0: return o
    e = (.35, .6, .85, 1)[tier]
    two = math.tau; wave = math.sin(two * p); fast = math.sin(two * p * 4)
    beat = p * 4; bf = beat % 1; hop = abs(math.sin(math.pi * bf))
    gate = min(1, p / .08, (1 - p) / .08)
    s = style
    if move in ('bounce', 'spin'):
        s2 = math.sin(two * p * 2)
        o.update(dy=-s['bounce'] * e * hop, dx=s['step'] * e * wave, rot=.1 * e * s2,
                 head=.12 * e * s2, armL=s['armL'] * e + s['armAmp'] * e * s2,
                 armR=-(s['armR'] * e + s['armAmp'] * e * math.sin(two * p * 2 + (math.pi if s['alternate'] == 'true' else 0))),
                 legL=s['kick'] * e * max(0, s2), legR=-s['kick'] * e * max(0, -s2), tail=.35 * e * fast)
        if move == 'spin' and tier == 3 and int(beat) == 3: o['sx'] = math.cos(two * bf)
    elif move == 'hipSway': o.update(dx=s['step'] * e * wave, rot=.18 * e * wave, armL=-.45 * e, armR=.45 * e, head=-.10 * e * wave)
    elif move == 'wave': o.update(dy=-s['bounce'] * .35 * e * hop, armR=(-2.1 + .4 * fast) * e, armL=.25 * e, head=.12 * e * wave)
    elif move == 'clap':
        hit = hop if int(beat) % 2 == 1 else 0
        o.update(dy=-s['bounce'] * .25 * e * hop, armL=(-.2 - .85 * hit) * e, armR=(.2 + .85 * hit) * e, head=.08 * e * hit)
    elif move == 'dab':
        hit = hop if beat >= 3 else 0
        o.update(dy=-s['bounce'] * .3 * e * hop, rot=-.18 * e * hit, head=.65 * e * hit, armL=2.5 * e * hit, armR=.9 * e * hit)
    elif move == 'skip': o.update(dx=s['step'] * .6 * e * wave, dy=-s['bounce'] * 1.5 * e * hop,
        legL=.9 * e * max(0, wave), legR=-.9 * e * max(0, -wave), armL=.6 * e * wave, armR=.6 * e * wave, rot=.08 * e * wave)
    elif move == 'flossLite': o.update(dx=-s['step'] * e * wave, rot=-.14 * e * wave, armL=.85 * e * wave, armR=.85 * e * wave, head=.12 * e * wave)
    elif move == 'chicken': o.update(dy=-s['bounce'] * .65 * e * hop, armL=(.9 + .55 * fast) * e, armR=-(.9 + .55 * fast) * e, head=.25 * e * hop, tail=.3 * e * fast)
    for key in o:
        if key != 'sx': o[key] *= gate
    return o


def sheet(path, r, label, sleeps=True, motion=None):
    height = 650 if sleeps else 360
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="600" height="{height}" viewBox="0 0 600 {height}">']
    for col, dark in enumerate((True, False)):
        x = col * 300; fg = '#F2F2F7' if dark else '#302C38'
        out += [f'<rect x="{x}" width="300" height="{height}" fill="{"#1C1C1E" if dark else "#F2F2F7"}"/>',
                f'<text x="{x+150}" y="28" text-anchor="middle" fill="{fg}" font-family="Helvetica" font-size="16">{label}</text>']
        for row, sleeping in enumerate((False, True) if sleeps else (False,)):
            out.append(pose(r, dark, sleeping, x+25, 40+row*295, motion=motion if not sleeping else None))
            out.append(f'<text x="{x+150}" y="{325+row*295}" text-anchor="middle" fill="{fg}" font-family="Helvetica" font-size="12">{"sleep" if sleeping else "awake"}</text>')
    out.append('</svg>'); path.write_text('\n'.join(out))


def move_sheet(path, r, name):
    w, h = 1440, 2080
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">',
           f'<rect width="{w}" height="{h}" fill="#1C1C1E"/>']
    for row, move in enumerate(MOVES):
        y = row * 230
        out.append(f'<text x="20" y="{y+24}" fill="#F2F2F7" font-family="Helvetica" font-size="17">{name} · {move} · tier 3</text>')
        # Offset samples expose the fast waving/flapping channels instead of aliasing their zero crossings.
        for i, phase in enumerate((0, .09375, .21875, .34375, .46875, .59375, .78125, .875)):
            out.append(pose(r, True, False, i*180, y+30, 180, 185, True, move_pose(r['style'], move, phase)))
            out.append(f'<text x="{i*180+90}" y="{y+226}" fill="#AAAABC" text-anchor="middle" font-family="Helvetica" font-size="11">p={phase:g}</text>')
    out.append('</svg>'); path.write_text('\n'.join(out))


def png(path, size=1200):
    result = subprocess.run(['qlmanage', '-t', '-s', str(size), '-o', str(path.parent), str(path)], text=True, capture_output=True, timeout=45)
    if result.returncode:
        if not SHARP: raise RuntimeError('Quick Look failed: ' + result.stderr.strip())
        print('Quick Look blocked; using explicit Sharp fallback:', path.name)
        js = "require(process.argv[1])(process.argv[2], {density:144}).resize({width:Number(process.argv[3])}).png().toFile(process.argv[2]+'.png').catch(e=>{console.error(e);process.exit(1)})"
        subprocess.run(['node', '-e', js, SHARP, str(path), str(size)], check=True)
    result = path.with_suffix('.svg.png')
    assert result.exists(), result
    print(result)


def extras(swift, kotlin, make_png):
    # Source-only validation (does not compile or execute either app/test suite).
    sw_pose = swift.split('static func pose(_ s: Style, tier: Int, p: Double, move:', 1)[1].split('private static func bounceBase', 1)[0]
    kt_pose = kotlin.split('fun pose(s: Style, tier: Int, p: Double, out:', 1)[1].split('private fun bounceBase', 1)[0]
    assert numbers(sw_pose) == numbers(kt_pose), 'named move numeric constants differ'
    art = accessories(swift)
    assert art == accessories(kotlin, True), 'accessory Swift/Kotlin parity mismatch'
    for folder in ('costumes', 'props', 'moves'): (OUT/folder).mkdir(exist_ok=True)
    for name in OLD_NAMES:
        r = parse(swift, name)
        for season in SEASONS:
            path = OUT/'costumes'/f'{name}-{season}.svg'
            sheet(path, costume(r, name, season, art), f'{name} · {season}')
            if make_png: png(path)
        for prop in PROPS:
            held = copy.deepcopy(r)
            x, y, size = r['heart']
            # Props sit above the arms and below the head, matching both platform renderers.
            prop_pieces = place(art[prop], 'body', x, y, size*2)
            for piece in prop_pieces: piece['prop'] = True
            held['pieces'] += prop_pieces
            motion = dict.fromkeys(('dx','dy','rot','head','armL','armR','legL','legR','tail'), 0.)
            motion.update(sx=1., armL=-.55, armR=.55)
            path = OUT/'props'/f'{name}-{prop}.svg'
            sheet(path, held, f'{name} · {prop}', False, motion)
            if make_png: png(path)
        path = OUT/'moves'/f'{name}.svg'
        move_sheet(path, r, name)
        if make_png: png(path, 2400)



def new_previews(name, rig, art, make_png):
    folder = OUT / 'new'
    folder.mkdir(exist_ok=True)
    # Two themes, each with awake and asleep. The geometry comes from the same
    # parsed tables used by the application, including the sleep offset.
    out = ['<svg xmlns="http://www.w3.org/2000/svg" width="1100" height="360" viewBox="0 0 1100 360">']
    for theme, dark in enumerate((True, False)):
        x = theme * 550
        bg, fg = ('#1C1C1E', '#F2F2F7') if dark else ('#F2F2F7', '#302C38')
        out += [f'<rect x="{x}" width="550" height="360" fill="{bg}"/>',
                f'<text x="{x+275}" y="34" fill="{fg}" text-anchor="middle" font-family="Helvetica" font-size="21">{name.title()} · {"dark" if dark else "light"}</text>',
                pose(rig, dark, False, x+20, 55), pose(rig, dark, True, x+280, 55)]
    out.append('</svg>')
    path = folder / f'{name}.svg'
    path.write_text('\n'.join(out) + '\n')
    if make_png: png(path)
    for season in SEASONS:
        target = folder / f'{name}-{season}.svg'
        sheet(target, costume(rig, name, season, art), f'{name} · {season}')
        if make_png: png(target)
    # A single four-season sheet remains quick to scan on a phone.
    tiles = []
    for i, season in enumerate(SEASONS):
        dressed = costume(rig, name, season, art)
        for dark in (True, False):
            x = i * 260
            y = 0 if dark else 300
            tiles += [f'<rect x="{x}" y="{y}" width="260" height="300" fill="{"#1C1C1E" if dark else "#F2F2F7"}"/>',
                      pose(dressed, dark, False, x+5, y+22, 250, 250)]
    target = folder / f'{name}-seasons.svg'
    target.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="1040" height="600">\n' + '\n'.join(tiles) + '\n</svg>')
    if make_png: png(target)
    if name in ('dragon', 'eagle'):
        x0, y0 = 380, 210
        if name == 'dragon':
            effect = '<path d="M365 170 Q413 145 482 169 Q447 172 480 188 Q418 188 365 170Z" fill="#FF5A36"/><path d="M368 170 Q418 157 466 170 Q442 176 468 181 Q415 180 368 170Z" fill="#FFAA3D"/><path d="M371 170 Q412 163 451 172 Q413 177 371 170Z" fill="#FFE479"/>'
        else:
            effect = '<path d="M345 132 L140 20 M387 132 L160 26" stroke="#F34B81" stroke-width="13" stroke-opacity=".35"/><path d="M345 132 L140 20 M387 132 L160 26" stroke="#FF5480" stroke-width="5"/><path d="M345 132 L140 20 M387 132 L160 26" stroke="#FFFFFF" stroke-width="2"/>'
        target = folder / f'{name}-effect.svg'
        target.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="520" height="350"><rect width="520" height="350" fill="#1C1C1E"/>' + pose(rig, True, False, 240, 35, 250, 280) + effect + '</svg>')
        if make_png: png(target)

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--before', default=BEFORE, help='git revision for the original Swift tables')
    ap.add_argument('--png', action='store_true', help='also ask qlmanage for 1200 px PNGs')
    ap.add_argument('--sharp-module', help='optional installed Sharp module fallback if Quick Look is sandbox-blocked')
    args = ap.parse_args()
    global SHARP
    SHARP = args.sharp_module
    original = subprocess.check_output(['git', 'show', f'{args.before}:{SWIFT}'], cwd=ROOT, text=True)
    swift = (ROOT / SWIFT).read_text()
    kotlin = kotlin_as_swift((ROOT / KOTLIN).read_text())
    report = {'before_revision': args.before, 'characters': {}}
    for name in OLD_NAMES:
        before, after, android = parse(original, name), parse(swift, name), parse(kotlin, name)
        assert after == android, f'{name}: Swift/Kotlin data differs'
        for field in ('pivots', 'full', 'barBottom', 'feet', 'sleepBottom', 'zzz', 'style'):
            assert before[field] == after[field], f'{name}: changed {field}'
        assert {p['part'] for p in before['pieces']} == {p['part'] for p in after['pieces']}
        assert len(after['pieces']) <= len(before['pieces']) * 1.5, f'{name}: piece budget exceeded'
        info = dict(before_pieces=len(before['pieces']), after_pieces=len(after['pieces']), checksum=checksum(after), parity='exact', pivots='unchanged', bounds='unchanged')
        report['characters'][name] = info
        path = render(name, before, after)
        print(name, json.dumps(info))
        if args.png:
            result = subprocess.run(['qlmanage', '-t', '-s', '1200', '-o', str(OUT), str(path)], text=True, capture_output=True, timeout=45)
            if result.returncode:
                print('Quick Look unavailable:', result.stderr.strip())
            else:
                print(path.with_suffix('.svg.png'))
    for name in NEW_NAMES:
        after, android = parse(swift, name), parse(kotlin, name)
        assert after == android, f'{name}: Swift/Kotlin data differs'
        assert len(after['pieces']) <= 55, f'{name}: piece budget exceeded'
        report['characters'][name] = dict(after_pieces=len(after['pieces']), checksum=checksum(after), parity='exact')
        new_previews(name, after, accessories(swift), args.png)
    expected = ['0.0000'] + [report['characters'][n]['checksum'] for n in NAMES]
    for fixture in ('iOS/KeyboardTests/KeyboardBuddyTests.swift',
                    'android/keyboard/src/test/kotlin/com/viettelex/keyboard/KeyboardBuddyTests.kt'):
        text = (ROOT / fixture).read_text()
        actual = re.search(r'\"0\.0000\"(?:, \"[0-9.]+\"){10}', text)
        assert actual and re.findall(r'\"([0-9.]+)\"', actual[0]) == expected, f'{fixture}: stale checksums'
    extras(swift, (ROOT / KOTLIN).read_text(), args.png)
    report['move_numeric_constants'] = 'exact Swift/Kotlin parity'
    report['accessories'] = '13 exact Swift/Kotlin tables; <=8 pieces per pose/prop'
    (OUT / 'report.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
