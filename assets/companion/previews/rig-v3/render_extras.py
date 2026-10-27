#!/usr/bin/env python3
"""Render the round-4 extras from the checked-in vector rig and accessory data."""
import copy
import html
from pathlib import Path
import render

root = Path(__file__).resolve().parent
outdir = root / 'extras'
outdir.mkdir(exist_ok=True)
swift = (render.ROOT / render.SWIFT).read_text()
art = render.accessories(swift)
assert art['cake'] and art['nightcap']


def picture(name, effect):
    rig = render.parse(swift, name)
    r = copy.deepcopy(rig)
    overlay = ''
    motion = None
    if effect == 'nightcap':
        hx, hy, hs = r['hat']
        r['pieces'] += render.place(art['nightcap'], 'head', hx, hy, hs)
        title = '23:00 · nightcap'
    elif effect in ('cake', 'confetti'):
        x, y, size = r['heart']
        pieces = render.place(art['cake'], 'body', x, y, size * 2)
        for p in pieces: p['prop'] = True
        r['pieces'] += pieces
        title = 'birthday cake' if effect == 'cake' else 'birthday confetti · 8 pieces'
        if effect == 'confetti':
            colors = ('#F8D77B', '#F7A7B9', '#83B9A4', '#A48AC0')
            points = ((90,95),(120,70),(180,75),(211,105),(76,143),(223,151),(107,170),(195,174))
            overlay = ''.join(f'<rect x="{x}" y="{y}" width="5" height="5" transform="rotate({i*17} {x} {y})" fill="{colors[i%4]}"/>' for i,(x,y) in enumerate(points))
    elif effect == 'speech':
        title = 'Mướp chào bạn!'
        overlay = '<rect x="40" y="18" width="220" height="32" rx="11" fill="#FFF7ED" stroke="#4A3A38" stroke-width="2"/><text x="150" y="39" text-anchor="middle" font-family="Helvetica,Arial" font-size="15" fill="#3A2A2A">Mướp chào bạn!</text>'
    elif effect == 'tickle':
        title = 'tickle · giggle + 3 sparks'
        motion = dict.fromkeys(('dx','dy','rot','head','armL','armR','legL','legR','tail'), 0.)
        motion.update(sx=1., dx=2.5, dy=-3, head=.14, armL=-.9, armR=.9)
        overlay = '<text x="65" y="115" fill="#F8D77B" font-size="24">✦</text><text x="218" y="130" fill="#F7A7B9" font-size="15">hi</text><text x="200" y="86" fill="#83B9A4" font-size="20">✦</text>'
    body = render.pose(r, True, False, 0, 25, 300, 330, motion=motion)
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="300" height="380" viewBox="0 0 300 380">
<title>{html.escape(name)} {html.escape(effect)}</title>
<rect width="300" height="380" fill="#1C1C1E"/>
{body}
{overlay}
<text x="150" y="369" text-anchor="middle" fill="#F2F2F7" font-family="Helvetica,Arial" font-size="13">{html.escape(name.title())} · {html.escape(title)}</text>
</svg>'''
    path = outdir / f'{name}-{effect}.svg'
    path.write_text(svg + '\n')
    print(path)

for name in ('cat', 'girl'):
    for effect in ('nightcap', 'cake', 'confetti', 'speech', 'tickle'):
        picture(name, effect)
