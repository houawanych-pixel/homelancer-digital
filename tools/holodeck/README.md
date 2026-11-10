# HoloDeck plans -> walkable ship decks

The owner's deck plans (`HL_<Faction><Class>_HoloDeck_YYYYMMDD_vN.png`, Drive: Homelancer Art) are the official
top-down map of one main deck. This turns one into `assets/holodeck/<faction>_<class>.json`, which
`scripts/ship_interior.gd` builds as an on-foot stage (basic shapes only).

How the plan is read
- white outer line = hull (everything outside it is ignored)
- bright cyan lines = walls (dim lines and small icons are floor markings, not walls)
- green squares = doors; the opening is widened so it cuts through the wall; on the hull = AIRLOCK
- the room names come from the labels on the plan

Steps
1. `python3 auto_seeds.py <plan.png> seeds/<id>.json` - first pass: finds the labels with OCR (tesseract).
   Unknown words are dropped, never guessed. Then fix the file by eye against the plan: names, a `box`
   (the room's drawn walls, plan pixels) per room, `open` for drawn passages with no green square (stairs, ramps).
2. `python3 extract.py <plan.png> seeds/<id>.json assets/holodeck/<id>.json debug.png`
   prints each room's size; the debug image shows rooms in colour, walls grey, doors green, and anything the
   player can't reach from `start` in RED. Every room must be reachable before it goes in the game.
3. Copy the plan into `assets/holodeck/` as a .jpg (same name) and add it to `FleetCatalog.HOLODECK_FILES`.
   The stage then shows up by itself (FleetCatalog `stage`), with a DECK PLAN button at the station dealer.

Doors on thick or double walls tunnel straight through to open floor. A labelled room the walls still cut off
(equipment drawn as solid lines) gets an AUTO-LINK: the shortest way in through the fewest wall cells; every link is
listed in the output ("links") so it can be checked against the plan.

Status (2026-11-10)
- Built and in the game (13): Unity Capital, Cruiser, Destroyer, Resupply, Troop Transport, Frigate, Escort, Scout,
  Bomber; Elyza Capital, Cruiser, Destroyer, Resupply. Every labelled room reachable on foot.
- Unity / Elyza Capital seeds made fully by hand; the other 11 from the OCR first pass, names and boxes fixed by eye.
- No plan yet: Elyza Troop Transport, Frigate, Escort, Scout, Bomber; all 9 for Solarion, Covenant, Savagers,
  Imperium, Orion, Liberator.
