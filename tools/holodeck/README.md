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

Status (2026-11-09)
- Done by hand and in the game: unity_capital, elyza_capital.
- Plans in hand, not built yet (auto first pass only): Unity Cruiser, Destroyer, Resupply, TroopTransport,
  Frigate, Escort, Scout, Bomber; Elyza Cruiser, Destroyer, Resupply.
