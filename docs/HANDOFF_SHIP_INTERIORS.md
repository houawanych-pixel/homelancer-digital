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

---

# PART 2: The Fleet Interiors Programme (the full job)

## 6. Scope: 64 ships

Every faction fleet ship gets a boardable interior **mini-game** (a graybox stage you walk with keys, guards, a
mission and doors), **except Bombers and fighters**. 8 factions x 8 classes = 64 ships
(Capital, Cruiser, Destroyer, Resupply, Troop Transport, Frigate, Escort, Scout). Ids are `faction_class`
(`imperium_trooptransport`), from `scripts/fleet_catalog.gd`.

Status on 12 Nov 2026 (v13.77). "plan + stage" = a HoloDeck plan and an old auto-extracted stage exist; the owner
says these are **not acceptable** (no proper doors, not extruded properly, black on his phone). Every ship is rebuilt.

| Faction | Capital | Cruiser | Destroyer | Resupply | TroopTransport | Frigate | Escort | Scout |
|---|---|---|---|---|---|---|---|---|
| Unity | plan + stage | plan + stage | plan + stage | plan + stage | plan + stage | plan + stage | plan + stage | plan + stage |
| Elyza | plan + stage | plan + stage | plan + stage | plan + stage | **needs plan** | plan + stage | **needs plan** | **needs plan** |
| Solarion | **needs plan** | **needs plan** | **needs plan** | **needs plan** | **needs plan** | **needs plan** | **needs plan** | **needs plan** |
| Covenant | plan + stage | plan + stage | plan + stage | plan + stage | plan + stage | **needs plan** | **needs plan** | **needs plan** |
| Savagers | **needs plan** | **needs plan** | **needs plan** | **needs plan** | **needs plan** | **needs plan** | **needs plan** | **needs plan** |
| Imperium | plan + stage | plan + stage | plan + stage | plan + stage | plan + stage | **needs plan** | **needs plan** | **needs plan** |
| Orion | **needs plan** | **needs plan** | **needs plan** | **needs plan** | **needs plan** | **needs plan** | **needs plan** | **needs plan** |
| Liberator | **needs plan** | **needs plan** | **needs plan** | **needs plan** | **needs plan** | **needs plan** | **needs plan** | **needs plan** |

23 ships have the owner's HoloDeck plan picture (`assets/holodeck/HL_<Faction><Class>_HoloDeck_*.jpg`). 41 have none.

**For ships with no plan, ask the owner which way:** (a) he makes the HoloDeck picture (his usual GPT sheet, same
style as the others), or (b) you compose one from the traced kit (section 2a) inside the ship's silhouette
(its fleet token in `assets/fleet_tokens/`), following the class rules below, and show it for approval. Never
skip the approval.

## 7. Class rules (so every ship of a class plays alike across factions; the faction changes the look)

Room sizes from Homelancer metrics: corridors 2 m wide, doors 1.2 x 2.2 m, decks 3.5 m apart (4.4 m storey in
`ship_interior.gd` today; keep one number per ship), lifts between decks lined up exactly.

| Class | Decks | Must have | Size feel |
|---|---|---|---|
| Capital | 3 | bridge, CIC, hangar (you board here), reactor, barracks, brig, captain's quarters, cargo | biggest, long spine corridor |
| Cruiser | 2-3 | bridge, gunnery, reactor, crew quarters, med bay, cargo | big |
| Destroyer | 2 | bridge, weapons bay, engine room, crew, armoury | long and narrow |
| Resupply | 2 | cargo holds (big open rooms), loading bay, bridge, fuel/reactor | wide holds |
| Troop Transport | 2 | barracks, drop bay, armoury, med bay, bridge | barracks rows |
| Frigate | 1-2 | bridge, engine, crew, gun deck | medium |
| Escort | 1 | bridge, engine, gun room, crew | small |
| Scout | 1 | cockpit, sensors, engine, bunk | smallest, like the Fury / Defender |

Learn proportions from the traced SWTOR ships: Fury (1 deck, cross hallway, hatches at both ends), Defender
(2 decks around a round heart room, ramp down), Tianjin (long spine, round CIC, command tower).

## 8. The mini-game on every ship (same rules everywhere, like the regular missions)

- **Entry:** you board at the airlock / hangar (BOARD button at the hull, v13.69). Same start point every time.
- **Missions:** one of sabotage (blow the generator), capture (take the captain), rescue (free the hostage), from
  the Mission Board job (`boarding_jobs.gd`). The target room is fixed per ship and marked on the plan.
- **Key-card doors:** GREEN (open), YELLOW, ORANGE, RED, in that order deeper into the ship. Each card is carried by
  one named guard; beating that guard drops it. The mission target is behind the last colour the ship uses
  (small ships: YELLOW only; Capitals: up to RED). One card colour per deck section, never a dead end.
- **Doors:** every doorway has a real sliding door that opens as you walk up and closes behind you; locked doors
  show the card colour; sealed doors are red. Same door model and timing as the breakout (`board_doors`).
- **Lifts:** a platform that carries you between decks (like `board_lifts` / `ship_interior.gd` `ride`), lined up
  with the floor plans.
- **Short cuts:** at least one orange wreckage block per ship that the CUTTER can open (v13.73), never on the only
  way to the target.
- **Enemies:** guards on patrol routes per room (sneak like the breakout), the key carriers, the boss next to the
  target on big ships.
- **Exit:** finish the mission, get back to the airlock / hangar, LEAVE SHIP; paid by the job.
- **Camera and controls:** the pilot over the right shoulder, COCKPIT = first person, RUSH on WARP, jump attack,
  CUTTER. Same HUD as the breakout.

## 9. Per-ship pipeline and checklist (do not skip a step; each step has an owner approval)

1. Plan picture in hand (his, or composed and approved).
2. Trace to a clean plan (`tools/trace/fleet_<id>/eng/build_plan.py`), on the original + white on black.
   APPROVAL 1 (he marks X / O; fix; repeat).
3. Gameplay overlay on the plan: entry, key doors by colour, card carriers, guard routes, lifts, wreckage short cut,
   mission target, way out. APPROVAL 2.
4. Blender graybox (`tools/trace/fleet_<id>/blender/build_graybox.py`, the Defender/Fury pattern): walls 3 m, slab,
   doors as openings with frames, lift shafts, red hull guide. Check renders. APPROVAL 3.
5. Into the game: write `assets/holodeck/<id>.json` in the schema `ship_interior.gd` reads (keys today: rooms, walls,
   doors, door_open, lifts, start, decks, shell{walls,doors,links}, objectives, key_guards, room_floor, corridor,
   sealed). Prefer one new converter, `tools/trace/to_deck_json.py`, that turns an approved `eng/*_plan.json` +
   gameplay overlay into that JSON, so all 64 go through the same code. Extend `ship_interior.gd` only where the
   new plans need it (real sliding doors, card colours from the overlay).
6. Test group per ship in `scripts/autotest.gd` (`HL_DECK_<ID>`): builds, every room reachable, each card door opens
   only with its card, every lift reaches its decks, the mission completes, LEAVE SHIP returns to space, frame time OK
   on the web build. xvfb screenshots of each room checked by you before he sees them.
7. Phone check by the owner, then version bump and push. Update the status table above.

Track the 64 ships in a task list; mark each step. Report to him per ship with one picture and one line.

## 10. Order of work

1. Fix the black interior on the phone (section 2b). Nothing else counts until boarding shows the ship.
2. Build the converter (step 5) on the first ship.
3. First ship end to end: **Imperium Troop Transport** (he boarded it). Get every approval, then use it as the
   template for the rest.
4. The 22 other ships that have plans, faction by faction (Imperium, Unity, Elyza, Covenant), biggest first.
5. Ask him for the 41 missing plans (or approval to compose them), faction by faction.
6. Space stations afterwards with the same method (breakout station, Carrick-style ring, Malgus Command Deck).

## 11. Size budget

The repo is near the owner's limit. Per ship keep: the plan JPG, the `eng/` script + JSON, one plan-on-map JPG, the
`.glb` graybox (under 2 MB). No PNG copies, no upscales over ~3 MB, no `.blend1`. Big source art goes to Drive
("HL Ship Interior References" / "HL Ship Traces"), not the repo.
