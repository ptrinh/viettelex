# Companion sprite artwork

All four companions now use one 4 × 2 atlas and the same eight-frame state
mapping on iOS and Android. Girl source: `girl-eight-source.png`, copied
byte-for-byte from the user's approved eight-pose sheet. It already has genuine
alpha transparency; the dark gradient visible in some viewers is RGB data
under alpha zero, not an opaque background. AI background-extraction attempts
lost the alpha and were rejected. The approved original was not redrawn.

Frames in row-major order: 0 front/rest, 1 paw jump, 2 three-quarter turn,
3 right profile, 4 back, 5 left profile, 6 three-quarter return, 7 curled
sleep. Gentle dance uses 0–1–0–6. Fast dance uses
0–1–0–1–2–3–4–5–6–0. Sleep switches directly to frame 7, exactly like the
boy; there is no stand-to-sleep transition or separate sleep atlas.

Production resources are `iOS/Keyboard/Resources/Buddies/buddy-<id>-v2-512.png` (iOS companion,
pre-scaled by `iOS/Scripts/make-buddy-512.swift`; full-size `buddy-girl-v2.png` / `buddy-boy-v2.png`
stay in the iOS bundle only for the Night Club dancer)
and byte-identical copies under `android/app/src/main/assets/`. The other
production sources are `boy-v2-alpha.png`, `cat-v2-source.png`, and
`chick-v2-source.png`. Old 24-frame girl sources and preview videos are retained
only as design history; they are not bundled.

The four production PNGs total **6,834,269 bytes** before app packaging.
Each atlas is decoded once, cached with a 3 MiB per-process limit, and shared
between visible views. iOS caps decode at a 512-pixel long edge. Android uses
sampled decode with a 512-pixel target. Neither platform decodes or builds
paths per animation frame. Quiet sleep and low-power mode are static; missing
art and seasonal costumes use the existing vector renderer.

Keep cell boundaries clear: atlas thumbnailing can blend neighboring cells.
The approved girl's alpha is nearly zero at every grid boundary and her
silhouette sits within its own cell. Check both the enlarged picker preview
and the approximately 44-point companion slot when changing artwork.

Set `TEST_RUNNER_VT_BUDDY_SHOTS=/tmp/viettelex-buddy-shots` when running iOS
`KeyboardBuddyTests` to export real renderer previews on light/dark themes.
