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

**Source of truth** for the full-resolution atlases is this folder: `girl-eight-source.png`,
`boy-v2-alpha.png`, `cat-v2-source.png`, `chick-v2-source.png` (byte-identical to the
`buddy-<id>-v2.png` files that used to ship). `iOS/Scripts/make-buddy-512.swift` reads them and
writes the companion atlases `iOS/Keyboard/Resources/Buddies/buddy-<id>-v2-512.png`; Android
ships byte-identical copies of those 512-px files in `android/app/src/main/assets/` (checked by
`BuddyPreviewSmokeTests`). Full-size `buddy-girl-v2.png` / `buddy-boy-v2.png` stay in both apps
only for the Night Club dancer (girl or boy); full-size cat and chick ship nowhere. Old 24-frame
girl sources and preview videos are retained only as design history; they are not bundled.

The four 512-px companion atlases total **705,358 bytes**. Each platform keeps one decoded
companion atlas per process (decoded off the main thread, dropped when the companion is off or
the keyboard has been hidden for a while). Neither platform decodes or builds paths per animation
frame. Quiet sleep and low-power mode are static; missing art and seasonal costumes use the
existing vector renderer.

Keep cell boundaries clear: atlas thumbnailing can blend neighboring cells.
The approved girl's alpha is nearly zero at every grid boundary and her
silhouette sits within its own cell. Check both the enlarged picker preview
and the approximately 44-point companion slot when changing artwork.

Set `TEST_RUNNER_VT_BUDDY_SHOTS=/tmp/viettelex-buddy-shots` when running iOS
`KeyboardBuddyTests` to export real renderer previews on light/dark themes.
