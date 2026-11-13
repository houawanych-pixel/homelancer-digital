# Handover: fleet interiors for Covenant, Unity, Solarion, Savagers (13 Nov 2026, v13.121)

The owner moved this work to the other builder (who has Imperium / Elyza / Orion / Liberator). Everything here
is pushed on homelancer-v1.2. All decks are PROPOSED (waiting for the owner's OK).

## State
- **Main decks.**
  - Covenant (capital, cruiser, destroyer, resupply, troop transport) and all 8 Unity ships are traced from the HoloDeck sheets.
  - The 16 Solarion and Savagers ships have no sheet. Their main decks were composed inside the fleet token (`token_source.py`, then `fleetmain.py`).
  - All of them pass HL_FLEETBOARD 16/16.
  - The 16 composed ships can be boarded in the game through `FleetCatalog.COMPOSED` in `scripts/fleet_catalog.gd`. Their map pictures are `assets/holodeck/<id>_plan.jpg`.
- **Extra decks** follow the v13.118 class rule:
  - scout, escort, resupply: main deck only;
  - troop transport: main deck only, **except** Covenant and Unity, which have one short upper deck (see "Open" below);
  - frigate: one short upper deck;
  - destroyer: upper and lower;
  - cruiser: upper, lower and lower2 (reserve);
  - capital: upper2 (crew), upper, lower and lower2.
- **Every deck passes `decklib.check` with 0 failures.**
- **Floor grows with class in all four factions** (m², all decks together):

| Class | Covenant | Unity | Solarion | Savagers |
|---|---|---|---|---|
| Scout | - | 1954 | 570 | 516 |
| Escort | - | 2523 | 1198 | 910 |
| Frigate | - | 3465 | 1938 | 2058 |
| Resupply | 3871 | 3583 | 2636 | 2305 |
| Troop transport | 4158 | 3699 | 2793 | 2448 |
| Destroyer | 4520 | 4228 | 4088 | 3994 |
| Cruiser | 6064 | 5097 | 4746 | 4703 |
| Capital | 9766 | 8476 | 8655 | 8735 |

## Tools (tools/trace/)
- `fleetdecks.py`: the proven Covenant Destroyer upper and lower decks as a template, placed on any ship's lift.
  - Options: `s` (scale), `names`, `move`, `size`, `drop`, `decks=("upper","lower")`, `tag="2"` (the upper2 / lower2 files).
  - Name sets: `DECK2` (crew and reserve names) and `SHORT_UPPER` (the frigate's short upper deck).
- `fleetfit.py`: fits the template into a new hull by trying moves, then shrinks, then drops, and prints the result.
- `fleetmain.py`: composed main decks.
  - Built in bands along a spine, following the class recipes `RECIPES`.
  - Card levels per class in `CARDS`.
  - Widths per class in `WIDE` / `WIDE_SHIP`.
  - Writes `plan.json` and `gameplay.json`.
- `token_source.py`: turns a fleet token into a 1024 x 1536 `source.jpg` plus `source_mask.png`. `decklib.hull` reads the mask when it is there.
- Per ship, in `eng/`:
  - `build_plan.py` and `build_decks.py`;
  - `build_decks2.py` for capitals and cruisers.
  - Retired `build_decks.py` scripts (the classes that have only a main deck now) say RETIRED at the top. Their outputs were removed.

## Commands
```
python3 -I tools/trace/fleet_<id>/eng/build_plan.py            # main deck (+ gameplay.json for composed ships)
python3 -I tools/trace/gameplay_check.py tools/trace/fleet_<id>
python3 -I tools/trace/to_deck_json.py tools/trace/fleet_<id>  # game json (main deck)
python3 -I tools/trace/fleet_<id>/eng/build_decks.py           # extra decks + check
HL_FLEETBOARD=<id> xvfb-run -a $GODOT ... -- --autotest --quit-after-test   # 16 checks
```

## Open (for the owner)
- The Covenant and Unity troop transports have one short upper deck. Their traced main decks are smaller than the resupply ship's, so without the extra deck they would break the size order. The owner still has to OK this.
- The Solarion and Savagers totals are smaller than the other builder's (capital about 8.7k m² against 10.4-11.5k). To match, scale them up: `token_source.py` LONG / MAXW, `fleetmain.py` WIDE, and `s` in `build_decks*.py`.
- A full autotest run had 11 failures, all in the call/log screens and warp. They look unrelated to the decks.
- Stacked decks in the engine (`to_deck_json --decks`, the 3-stop lift) have not been tested.
