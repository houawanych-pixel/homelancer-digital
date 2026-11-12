# Handover: Ship and Station Interiors (written 12 Nov 2026, game at v13.77)

A new chat owns this job: rebuild every boardable ship and space station interior in Homelancer, using the
tracing method the owner approved this week, so boarding missions work end to end and everything stays
cohesive with the rest of the game.

Owner: Hova (GitHub `houawanych-pixel`). On his phone, often by voice. Short, plain replies. "go" = keep building.

## 0. Rules that never change

- Repo `houawanych-pixel/homelancer-digital`, Godot 4.3, branch **homelancer-v1.2** only. `git pull --rebase` first,
  never force-push, never touch `main`. Commit as `git -c user.name="Claude" -c user.email="noreply@anthropic.com"`.
- Every push: `VERSION = origin's VERSION + 1` (another session also pushes) in `scripts/data.gd` and in
  `web_shell.html` (sed), plus an entry in `docs/V1.2_BUILD.md`. Check the bump applied before pushing.
- No keys in files, no passwords, no Tripo credits or new art unless he asks.
- Repo size is near his limit (about 11 GB with history; target 7 GB). Keep traces small: JPG not PNG for big
  pictures, no zips in the repo, nothing over a few MB per file unless it ships in the game.
- Design: never invent layouts. Trace what he gives you; where you must design, research how AAA games do it
  (SWTOR, Alien: Isolation, Star Citizen, Mass Effect), show him, he decides.
- Plans must be engineering-clean: straight or arced walls of one thickness, one standard door width with frames,
  parallel equal-width hallways, the outer silhouette following every notch. White lines on black, always also laid
  on the original picture. Zoom in big on close-ups.
- He marks plans with **X = close it** and **O = fix / open it**. Circles = look here.
- Show every plan for approval before extruding. Show every graybox before it goes into the game.
- 3D: no plain cubes / cylinders / spheres for finished rooms (graybox is the exception). Build half and mirror.

## 1. Skills to load (they hold the method; use them, don't reinvent)

- `blueprint-wall-trace` - the tracing method (pixel trace, then the clean engineering plan). Its rules list is the
  owner's own words. The skill update shown on 11 Nov adds the engineering rules; check the saved version.
- `homelancer-aaa-room-build` - the room build stages in Blender (graybox, kit pass, hero props, materials), sizes.
- `homelancer-kit-shapes` - building rooms from clean procedural kit shapes.
- `homelancer-dev` - the repo, Godot 4.3 setup, tests, phone web test.
- `homelancer-ship-remodel`, `homelancer-glb-intake`, `tripo-input-prediction` - only when real 3D hull models come in.
- `reuse-proven-code` - extend the scripts below, don't regenerate them.

## 2. What already exists (read these first)

### 2a. Traced reference layouts (the kit of proven rooms) - `tools/trace/`
Each folder: `source.jpg`, upscaled `*_x4.jpg`, `eng/build_*.py` (the clean plan, measured, in shapely),
`eng/*_plan.json` (floor + walls polygons), `eng/*_on_map.jpg`, and `blender/build_graybox.py` + `.glb`.

| Folder | What | Notes |
|---|---|---|
| `hub_hex_01` | Homelancer hex hub | 3 hexagons, spokes, wings; approved |
| `temple_02` | Temple | mirrored top band, round hall, stair halls; approved (the reference build) |
| `ship_tianjin_03` | SWTOR UPP Tianjin | main deck + command tower (the whole upper deck); floor levels noted |
| `ship_kasparov_04` | SWTOR Kasparov / Defender family | 2 decks (deck A, deck B), hull overlay |
| `ship_defender_05` | SWTOR Defender (Jedi ship) | flight deck + lower deck, room names, stairs between decks lined up, red hull |
| `ship_fury_07` | SWTOR Fury interceptor | 1 deck, rooms 1-15, real scale 47.8 x 41 m, red hull; doors per owner's X/O |
| `station_republic_06` | SWTOR Malgus Command Deck | fan wings with raised stages, hub with railing ring, stairs in yellow |
| `station_ring_08` | SWTOR Carrick Station | gear-shaped: 4 wings in polar form rotated x4, cabins as gear teeth, spokes with lifts |

Useful patterns in those scripts: `wall(p0,p1,doors)` (a wall with standard doors), `ring_wall`, `arc_wall`,
`radial_wall`, `sector`, polar unwrap measuring (`cv2.warpPolar`), mirror with `affinity.scale`, close hairline gaps
with `floor.buffer(3).buffer(-3)` (fixes false walls between arc pieces), flood-fill check that every room is reachable.
Shapes the owner liked: round rooms, hex rooms, gear teeth, raised stages with side steps, stair halls, chevron noses,
45-degree lockers, stepped connectors, two-deck ships with stairs lined up between decks.

### 2b. The game's ship interiors today - `scripts/ship_interior.gd` (ShipInterior)
- Built from the owner's HoloDeck plan PNGs (`assets/holodeck/HL_<Faction><Class>_HoloDeck_*.jpg`) via
  `tools/holodeck/` (`auto_seeds.py` OCR first pass, `extract.py` to `assets/holodeck/<id>.json`, `shell.py` for the
  3D walk-through shell). Read `tools/holodeck/README.md`.
- 24 decks exist as JSON (Unity x9, Elyza x5, Imperium x5, Covenant x5). Plans missing for Solarion, Savagers,
  Orion, Liberator and several classes.
- Systems already in it (keep them, wire new decks into them):
  - doors that open and close; key-card gates: GREEN / YELLOW / ORANGE / RED (`KEY_COL`, `_gates`, `_gate_tick`)
  - key guards that drop the cards (`_key_guards`, `_dress_guard`, `give_key`)
  - lifts between decks (`_lifts`, `_more_decks`, `lift_stops`, `ride`), deck titles, `DECK_GAP` 11 m
  - missions: sabotage (generator), capture (captain), rescue (hostage) (`start_mission`, `_next_step`, `_mission_tick`)
  - minimap from the plan, room labels, LEAVE SHIP, over-the-shoulder pilot camera
- **Owner's complaints to fix first:**
  1. On his phone the boarded interior is **black** (only the HUD text and the minimap show). It runs in a
     SubViewport. The breakout had the same web bug (v12.34 `_reshow`, v12.44 `_merge_static`). Find and fix.
  2. "None of the ships are even made": rebuild the decks with the new tracing method and approve each one.

### 2c. The other interior systems (make them all feel like one game)
- `scripts/boarding.gd` + `space.gd` boarding code: mech-scale battleship and station decks (generated deck plans,
  `Boarding.deckplan`), sliding doors (`board_doors`, green/red stripe), lifts (`board_lifts`), the station
  BREAKOUT with guards, the lockdown console, cuttable WRECKAGE short cuts (v13.73, `_make_wreck`, CUTTER).
- `scripts/boarding_jobs.gd` + `main.gd` `_board_job_*`: Mission Board BOARDING jobs. Target ship in space, shoot it to
  50% power, its hull is solid, BOARD button at the hull (v13.69), then `open_ship_interior` with the job's mission.
- `scripts/fleet_catalog.gd`: the 72 faction ships (8 factions x 9 classes). In space they are flat placeholder
  tokens (no 3D models yet). `HOLODECK_FILES` lists which have plans; `with_stage()` which are walkable.
- Player tools that must work inside: CUTTER (cuts orange wreckage, two points across it), RUSH (WARP on foot / mech),
  jump attack, laser shield, over-the-shoulder camera, COCKPIT = first person.

## 3. The job, in order

1. **Fix the black interior** on the phone web build. Prove it with a screenshot from a web-like run.
2. **Pick the first ship with him** (suggest the Imperium Troop Transport: he boarded it and found it black).
3. For each ship: get the plan (his HoloDeck PNG, or a reference he sends) -> trace it with `blueprint-wall-trace`
   into `tools/trace/<ship>/eng/` -> show the plan on the original -> he marks X/O -> fix -> approve.
4. **Gameplay pass on the approved plan, shown before building:** where the key-card doors go (GREEN, YELLOW, ORANGE,
   RED), which guard or enemy carries each card, where the mission target is (generator / captain / hostage), the
   lifts between decks, wreckage short cuts the CUTTER can open, the airlock / hangar you board through. Draw it on
   the plan (colour per key) and get his OK.
5. Extrude: Blender graybox first (`tools/trace/*/blender/build_graybox.py` pattern) for his approval, then convert
   the approved plan into the game's deck format (`assets/holodeck/<id>.json` schema that `ship_interior.gd` reads:
   walls, rooms, doors, lifts, start) so the game builds it. Doors open and close, lifts go up and down, cards unlock.
6. Test in Godot (headless and xvfb screenshots), then on the phone build. Push with the version bump.
7. Repeat ship by ship, then stations (the breakout station and the Carrick-style ring as kit pieces).

## 4. Testing

- Headless: `HL_<GROUP>=1 godot --headless --path . -- --autotest` (see `scripts/autotest.gd`; e.g. HL_INTERIOR,
  HL_BOARDJOB, HL_BREAKOUT, HL_CUTTER, HL_SMOKE).
- Screenshots: `HL_SHOT_DIR=/dir xvfb-run -a godot --audio-driver Dummy --rendering-driver opengl3 --resolution 2400x1080 --path . -- --autotest`.
  Look at them before showing him. Real taps only register under xvfb, not headless.
- Add one test group per new ship: deck builds, every room reachable, each key door opens only with its card,
  lifts reach every deck, the mission finishes, LEAVE SHIP returns you to space.

## 5. References he likes

- Google Drive "HL Ship Interior References" (id 1-uxZqusF9QDyHabbAA-mzybK1NwWd7hC): SWTOR maps doc, Alien: Isolation
  (Sevastopol) doc, folder "HL Ship Traces".
- SWTOR (PC, Steam, free): ship and station layouts. Alien: Isolation (PS4/PC): station decks.
- Grok finds in-game screenshots for him; write him a Grok block when you need shots of an area.
