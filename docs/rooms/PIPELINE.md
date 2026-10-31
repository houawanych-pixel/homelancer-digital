# Homelancer – 360 room pipeline (one faction at a time)

Every image and video prompt starts with the STYLE block in `docs/rooms/STYLE_PROMPT.md`.
Nothing gets animated until the owner has approved the exact frames that will be animated: animation costs credits,
so every mistake is caught on a still picture first.

## The four STOP points (the owner says "approved" before the next step)

| Stop | What the owner sees | What it costs if skipped |
|---|---|---|
| 1. PICTURES | the 10 room pictures (front on top, back below, white line between) | everything after |
| 2. PARTS | for each room: the 360 strip with the 3 red cut lines, and the 3 extended parts (bands painted) that will be animated, each with a one-line ANIMATION PLAN | all the clips |
| 3. FIRST CLIP | one 15 s clip (the faction's main_hub part 2) | the other clips |
| 4. IN GAME | the joined moving rooms, pushed and live | – |

Only after STOP 3 is approved may the rest of the faction's clips be made, and only from parts approved at STOP 2.

## How to draw (STOP 1)

- One image per room, 1672x941: the FRONT view on top, the BACK view below (the opposite way in the same room),
  a thin white line between them, no border. Same camera height and horizon in both halves.
- STYLE block. Faction colours, its emblem, its station and system names (site.json).
- People: busy and multi-race where it fits, ALL kept back: full body, feet on the floor, the nearest at most about
  40% of the picture's height, most smaller. Nobody standing in a row or posing for the camera: groups talking,
  people working, carrying, walking, facing different ways. The lower third mostly open floor.
- The back view is a different side of the room, never a copy of the front. No mirroring.
- No readable text signs (they warp when animated): use the faction emblem.
- private_quarters: no people, and no bed in the back view.
- Level horizon lines; the corners turn correctly.
- Check your own pictures before sending: redo any that are photoreal, 3D-rendered, dark, too close, or not split.

## Joins, stitch, cut (between STOP 1 and STOP 2; no credits)

- `python3 tools/rooms/make_joins.py`, fill ONLY the white gaps (the two gaps different), paste the original back
  outside the gaps; `python3 tools/rooms/v2_room.py <f> <room>`; `python3 tools/rooms/v2_cut3.py <f> <room>`
  (crowded room: `--span 0.15`, or `--cuts x1,x2,x3` by eye).
- Paint the white bands of each part (ceiling above, floor below) with the image tool; keep the strip untouched.

## STOP 2 – what to send for each room

1. the cuts preview (no red line through a person or creature),
2. the 3 extended parts exactly as they will be animated,
3. an ANIMATION PLAN of one line per part: who moves and how (e.g. "the two pilots at left talk and gesture, the
   cart glides right to left behind them, ships drift past the window, screens flicker").

## How to animate (after STOP 2; the first clip is STOP 3)

- One 15-second clip per part, 1080p, 24 fps, camera locked (no pan, zoom or shake).
- STYLE block: every frame stays Epic Seven anime; no switch to realistic motion or textures.
- People move ON THE SPOT, as in the plan: talking, gesturing, working, hair and coats moving. Nobody walks off the
  left or right edge, nobody walks toward the camera, nobody appears or vanishes.
- The outer 70 px at the left and right edges stay calm (that is where the parts join).
- Life: screens flicker, lights pulse, drones and carts glide, ships move outside the windows.
- Ambient MP3 per part. MP4 + MP3 only, never WAV. Each part's sound is its own (what that part of the room sounds
  like), because the game plays them by where you look: the part you face at 75%, both parts at a join at 50%,
  a part turned out of view silent (owner's standing rule for every 360 room; Data.ROOM_SND_FRONT / ROOM_SND_SEAM).
- Make the faction's FIRST clip only (main_hub part 2), send it, and wait for STOP 3. Then the rest.

## After animating (no more stops until the game)

- Upload each room's clips as a GitHub release (`rooms-<faction>-<system>-<station>-<room>`), join them with
  `python3 tools/rooms/v2_animate3.py <f> <room> <clip folder>` (check any "weak match" warning by eye),
  commit only `art/rooms_v2/<f>/`, `assets/rooms/<f>/` and `scripts/room_seams.gd`, pull --rebase, push to
  homelancer-v1.2, and wait for the "Homelancer web playtest" run to pass. Report to the owner (STOP 4).
