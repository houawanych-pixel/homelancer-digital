# Fleet decks handover: Imperium Troop Transport (and the deck tools)

Written 13 Nov 2026 (v13.104) when the owner moved the fleet deck work to a new session. Nothing below the main deck
is in the game yet: the composed upper / lower decks are PLANS waiting for the owner's approval.

## OWNER'S LATEST WORD (13 Nov 2026, 01:58): "That look bad. The last one better."
He prefers the FIRST pass 2 plans (commit b7102f4a) over the pass 2 review fixes in this push (commit 2001c192,
the current `eng/build_decks.py` output). The preferred version is kept in `eng/pass2a_owner_preferred/`:
`decks_plan.jpg`, `decks_on_map.jpg`, `decks_sources.jpg`, its `build_decks.py`, both deck jsons and the decklib it
ran with (`decklib_at_pass2a.py`). To rebuild it exactly: `git worktree add /tmp/pass2a b7102f4a` and run
`python3 -I /tmp/pass2a/tools/trace/fleet_imperium_trooptransport/eng/build_decks.py` there.
Next step: start from pass2a's look (its room sizes, layout and fuller rooms) and apply the review fixes to it one at a
time, showing the owner each change, instead of the automatic fit() swap that changed the look.

## Where things stand

| Part | State |
|---|---|
| Main deck (traced from the owner's HoloDeck sheet) | Approved programme template. In the game as a regular boarding run. |
| Upper deck (COMMAND) and lower deck (HOLD), composed | Pass 2 plans, automatic check 0 failures on both. NOT approved, NOT in the game. |
| Room shape library (171 traced rooms) | Done, tagged by hand. |
| Stacked decks in the boarding engine | Code written (inert unless a ship's board has `fleet.elev`), NOT tested. |
| Other 22 traced ships (main decks) | Traced + boarding run tested locally 16/16 each (`HL_FLEETBOARD`), waiting for owner OKs; no upper / lower decks yet. |

## Files

### tools/trace/ (shared)
- `planlib.py`: engineering plan code (rooms, hallways = centre line + width, doors, walls, flood-fill reach, drawing). One wall 0.4 m (T = 4 px), doors 1.6 m (16 px), 10 px = 1 m.
- `decklib.py`: the composed decks.
  - `hull(src, ax)`: the ship's hull silhouette from its HoloDeck picture (glow filled, mirrored, fins opened away).
  - `lib(id, cx, cy, w, h, rot, flip)`: a traced room from the library, placed in plan px.
  - `fit(tags, cx, cy, w, h)`: picks the library room for a function that best fits a w x h metre box, aspect changed by at most 1.3x, min width 3.2 m.
  - `clean()` / `tidy()` / `dedupe()`: no nubs, near-straight edges snapped, no edges under 0.5 m.
  - `settle()`: rooms meet corridors / each other on ONE wall (gaps under 1 m closed); "whole" rooms (round, lift, brig) are never cut; starboard = port mirrored.
  - `finalize()`: last pass against everything (whole pixels, no overlaps, gaps closed).
  - `check()`: the owner's automatic check (below).
  - `run()`: build + check + draw one deck.
  - `source_sheet()`: the "where each room's shape comes from" sheet.
- `shape_library.py`: cuts the traced plans into rooms at the door gaps (shrink by half a door, grow back inside the floor), measures them in metres and writes `shape_library.json` + `shape_library_sheet.jpg`.
  - Function tags come from `shape_tags.json`, set by hand from the reference pictures.
  - Scale: `px_per_m` where the plan has it (Fury 40). Otherwise a GUESS from the door, door = 1.4 m (Defender flight 96 px, Defender lower 152 px, Kasparov / Malgus / Carrick 56-60 px). Defender sizes are the least sure.
  - Sources: ship_fury_07, ship_defender_05 (flight + lower), ship_kasparov_04 (deck a + b), station_republic_06 (Malgus), station_ring_08 (Carrick), ship_tianjin_03 (main).
  - Not used yet: hub_hex_01 and temple_02 (their traces are wall lines, not floor / walls JSON).
- `to_deck_json.py`: plan.json + gameplay.json -> `assets/holodeck/<id>.json` (ShipInterior shell + the "board" layout the regular boarding engine plays). `--decks` also merges `eng/deck_upper.json` / `deck_lower.json` (stacked at y +80 / -80, lifts from gameplay "elevators"). Leave `--decks` off until the owner approves the decks.
- `gameplay_check.py`: card order check + gameplay picture for a main deck.

### tools/trace/fleet_imperium_trooptransport/
- `source.jpg`: the owner's HoloDeck sheet.
- `eng/build_plan.py` -> `eng/plan.json`, `plan.png`, `plan_on_map.jpg`: the main deck.
- `eng/gameplay.json`, `eng/build_gameplay.py` -> `gameplay.png`, `gameplay_on_map.jpg`: entry, locks, card guards, targets, wreck.
  - The `decks` / `elevators` / `capture` / `rescue` entries point at the PASS 1 room names. Redo them for pass 2 when the plans are approved.
- `eng/build_decks.py` (PASS 2, current) -> both decks:
  - `deck_upper.json`, `deck_upper.png`, `deck_upper_on_map.jpg`
  - `deck_lower.json`, `deck_lower.png`, `deck_lower_on_map.jpg`
  - `decks_plan.jpg` (both decks, white on black), `decks_on_map.jpg` (both on the original picture)
  - `decks_sources.jpg` (each room next to the traced room it came from)
  - Each deck json also holds `check_failures`, `rooms_cover`, `from_library`, `service`, `outline`, `features`, `lifts`.
- `eng/build_decks_v1.py`: pass 1 (rooms by function, no service space). History only.
- `eng/pass2a_owner_preferred/`: the first pass 2 version, which the owner liked better (see the top of this file).
- `HANDOVER.md`: this file.

## Commands (from the repo root)
```
python3 -I tools/trace/shape_library.py                                  # library json + sheet
python3 -I tools/trace/fleet_imperium_trooptransport/eng/build_plan.py   # main deck plan
python3 -I tools/trace/gameplay_check.py tools/trace/fleet_imperium_trooptransport   # card order check
python3 -I tools/trace/fleet_imperium_trooptransport/eng/build_decks.py  # both decks + check (exit 1 if any failure)
python3 -I tools/trace/to_deck_json.py tools/trace/fleet_imperium_trooptransport           # game json (main deck)
python3 -I tools/trace/to_deck_json.py tools/trace/fleet_imperium_trooptransport --decks   # ... with the decks (after approval)
export GODOT=/home/claude/godot/Godot_v4.3-stable_linux.x86_64
HL_FLEETBOARD=imperium_trooptransport timeout 590 xvfb-run -a $GODOT --audio-driver Dummy --rendering-driver opengl3 \
  --resolution 1280x600 --path . -- --autotest --quit-after-test                # the boarding run test (16 checks)
```

## The automatic check (decklib.check, printed with every plan; the owner sees a plan only at 0 failures)
1. No room overlaps another room or a corridor / lift (touching along a shared wall is fine).
2. Every room inside the hull shrunk by the wall.
3. Every room reachable through doors from the lift (flood fill).
4. Furniture lines at least 0.3 m inside their room.
5. Every label inside its room.
6. No double walls: two things either share one wall or stand at least 1 m apart (service space).
7. Lifts lined up: the deck's lift is the main deck's Lift A shaft. `build_decks.py` also prints `LIFTS: ... LINED UP` (upper = lower = main).
8. Every traced room's aspect changed by at most 1.4x.
9. Every room at least 3 m wide.
10. Clean edges: straight within 3 degrees, none under 0.5 m (round rooms exempt).
11. Doors only between walkable spaces; niches (room-side recesses) wholly inside their room.
12. Rooms cover 55-65 % of the deck (the rest is service space: conduit, duct, power trunk, coolant loop, crawlspace, machinery, structure).

Last run: upper 0 failures, 58 % rooms; lower 0 failures, 56 % rooms.

## Owner's open fixes (pass 2 review, 13 Nov 2026) and where each stands
| Fix | State in this push (owner has NOT reviewed it yet) |
|---|---|
| Lifts aligned between decks | Both decks use the main deck's Lift A shaft at (459, 490); checked (7). The engine still treats a lift as two decks; a 3-stop car (main / upper / lower in one shaft) is NOT written. |
| No heavy warping (Lounge P/S, Star Chart P/S, Cabins A/B, Brig, Officers A/B: aspect within 1.4x) | Rooms now come from `fit()` (max 1.3x, a different traced room when none fits); checked (8). |
| One wall line (no double lines) | `settle` / `finalize` close gaps under 1 m; checked (6). |
| Door bumps / nubs on outlines | `clean` / `tidy`; checked (10). |
| Slivers (Turret P/S, Gunnery, pods arc: min 3 m) | Turrets are angled rooms at the turret corridor ends; Gunnery a proper room; pod arc 3 m wide with 3 pod hatches; checked (9). |
| Green niches drawn like doors into service space | Niches are now recesses on the room side only (green box + letter C/L/M/F/W/S/P), walls whole; doors checked to open only between walkable spaces (11). |

## Not done
- Owner approval of the pass 2 plans (approval 1), then gameplay on the decks (approval 2: card doors, captain on the upper deck, hostage in the brig), graybox, phone check.
- Engine: stacked decks (`boarding.gd` STACKED: deck-aware `room_at` / `joint` / `keep_in`, open lift shafts; `space.gd` `_fleet_decks` / `_fleet_elev` lift cars with shaft walls, only the current deck drawn; `hud.gd` per-deck map; `main.gd` deck map pictures; autotest rides every lift). Written, never run: test with `HL_FLEETBOARD` after `to_deck_json.py --decks`. A 3-stop lift for the single shaft is still to write.
- Upper / lower decks for the other 22 traced ships (use the same decklib / fit / check).
- The 41 fleet ships with no plan (ask the owner, one faction at a time); stations last.
