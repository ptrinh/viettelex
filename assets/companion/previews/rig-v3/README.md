# Buddy vector rig v3

Each character sheet shows the original and redrawn **awake and asleep** poses,
side by side on `#1C1C1E` and `#F2F2F7`. PNGs are 1200 px wide. The preview uses
part draw order, rest/dance visibility, outline/ink colors, the silhouette halo,
and the renderer's bottom-aligned sleep offset. Zzz is shown in the sleep panels.

The original data is pinned to `111c61f44a9d87e51f0abebb37b5dda7ff201b8f`
(the task's starting HEAD), so regeneration also works after the redraw is committed.

```sh
python3 assets/companion/previews/rig-v3/render.py
# Also try macOS Quick Look PNG export:
python3 assets/companion/previews/rig-v3/render.py --png
```

`render.py` uses only the Python standard library and reads the actual Swift
and Kotlin tables. It verifies exact piece/metadata parity, unchanged pivots,
viewports, animation styles and Zzz placement, and the 1.5× piece-count limit.
`report.json` records the results and the shared checksum fixture values.

| Character | Before | After | Design |
| --- | ---: | ---: | --- |
| Girl | 43 | 53 | Pink flowing hair, cat ears, shaded hoodie, pleated skirt, socks and sneakers |
| Boy | 42 | 46 | Tousled dark hair, expressive eyes, navy vest, ivory tee and shaded denim |
| Cat | 42 | 50 | Fluffy cheek silhouette, cream muzzle, tabby stripes and pink paw pads |
| Chick | 30 | 36 | Swept crest, butter-yellow down, feathered wings and rounded orange feet |

Seasonal head/neck/hand anchors and face reaction bounds follow the new artwork.
Tết recoloring follows the girl's existing clothing and the boy's vest. Character geometry,
pivots, bounds and animation channels are preserved. Round two adds the seasonal accessories,
holiday props and named vector dance moves described below.

Validation: `swiftc -parse` on the changed Swift sources, Kotlin source review,
Python parity/constraint checks, and visual inspection of all four PNGs. No Xcode
or Gradle tests, simulators or emulators were run.

Quick Look was attempted but its sandbox initialization failed in this workspace.
The checked-in PNGs were exported from the same SVGs using an already installed
Sharp/Node SVG rasterizer, with no Python dependencies or package installation.
An equivalent fallback, when Sharp is available to Node, is:

```sh
node - <<'JS'
const sharp = require('sharp');
(async () => {
  for (const name of ['girl', 'boy', 'cat', 'chick']) {
    const path = `assets/companion/previews/rig-v3/${name}.svg`;
    await sharp(path, { density: 144 }).resize({ width: 1200 }).png().toFile(path + '.png');
  }
})().catch(error => { console.error(error); process.exit(1); });
JS
```

## Seasonal costumes, holiday props and named moves

- `costumes/<character>-<season>.svg.png`: 16 sheets, each with awake/sleep on dark/light.
  Seasons: `tet`, `christmas`, `halloween`, `midAutumn`.
- `props/<character>-<reaction>.svg.png`: 16 sheets, each holding its prop on dark/light.
  Reactions: `luckyMoney`, `gift`, `candy`, `mooncake`.
- `moves/<character>.svg.png`: four sheets, nine named moves × eight labeled phases.
  Samples are offset from uniform eighths so fast waves/flaps do not alias to zero.
- Characters: `girl`, `boy`, `cat`, `chick`. See `preview-paths.txt` for every PNG path.

Costumes use only head/sleep-head, neck and hand anchors. Sleeping bows sit beside the
muzzle; the gold clothing pattern sits on the torso; sleeping lanterns rotate beside the
resting hand. Translucent lantern light does not contribute an opaque silhouette halo.
All accessory tables are checked for exact Swift/Kotlin path, color, opacity and width parity;
each accessory uses at most seven pieces. The normalized tables are lazy in both languages.

Holiday names match year-round; quà/kẹo/bí ngô/cuội/an khang/phát tài require their season.
Quà, kẹo and cuội require accents. Matching keeps the existing sensitive-word priority,
folding, punctuation and repeated-letter rules. Three prior tokens support four-word wishes;
view/driver history supplies the fourth token only when consecutive boundary context agrees.
Date/theme resolution happens at word boundaries. Each 1.5-second reaction constructs and
caches only its requested prop, above the arms and below the head at the heart anchor.

Vector moves are deterministic from character, tier, two-loop group and appearance seed.
Tiers 0–1 use bounce/hipSway/wave/clap; tier 2 uses skip/flossLite/dab/chicken; tier 3 adds spin.
Consecutive groups never repeat. Move and tier changes retain the existing additive blend;
48 samples per loop are cached by (tier, move). Sprite atlases are unchanged. Sleeping/idle
characters add no animation work. Corresponding matcher, gating, budget, neutral-pose,
selection and numeric move fixtures were added to both unit-test suites but **not run**.

Quick Look is attempted with `--png`. In this sandbox it fails with a sandbox-extension error;
the PNGs were produced from the exact SVGs using the existing Sharp installation. To reproduce
with an explicitly selected installed fallback (no package installation):

```sh
python3 assets/companion/previews/rig-v3/render.py --png --sharp-module /path/to/node_modules/sharp
```

The Python script remains stdlib-only. Swift parsing and source/data parity checks were used;
no app build, test suite, simulator or emulator was run.

## Round 3: six vector companions

`new/` contains a dark/light awake-and-sleep PNG, four individual seasonal PNGs,
and one four-season contact sheet for each of Shiba, Koi, Panda, Piggy, Little
dragon and Eagle. The dragon and eagle also have a signature-effect frame. The
PNG extension is `.svg.png` because the Sharp fallback rasterizes each generated
SVG directly. Every source rig has 29–31 pieces, and `render.py` checks exact
Swift/Kotlin geometry, metadata and checksum parity for all ten characters.

Regenerate the SVGs and parity report with `python3 render.py`. To regenerate the
PNGs, use `python3 render.py --png --sharp-module /path/to/sharp` when Quick Look
is unavailable. The shared signature effects use short vector animations only
when triggered; Koi's three sleep bubbles animate while the view is visible.
The new companions have no sprite atlas and always resolve to vector style.

## Round 5: Robot, dances and holiday moments

`r5/robot.svg.png` shows Robot awake and asleep on both backgrounds, and
`r5/robot-seasons.svg.png` shows its four seasonal costumes. The six move strips
in `r5/` show six phases of `robot`, `fanShake`, and `floss` for Girl and Robot.
`r5/holidays/` contains one PNG per requested holiday gesture or detail; the
complete path and caption list is in `r5/preview-paths.txt`. The preview command
above regenerates them from the current rig tables. Robot uses the vector style
and has no sprite atlas. New holiday reactions use lazy vector props in the cell.

For the round-five sheets alone, run `python3 render.py --r5-only --png
--sharp-module /path/to/sharp` from this directory when Quick Look is unavailable.
