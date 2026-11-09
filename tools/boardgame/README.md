# Homelancer tabletop board (one star system = a 12 x 12 in board cut into six 4 x 6 in cards, 300 dpi)

1. Capture the sun, the worlds and the clouds as the game draws them (on black):
   `env HL_BOARDART=1 HL_SHOT_DIR=<art dir> xvfb-run ... godot --path . -- --autotest` → `art.json` + `art_*.png`
2. Station and jump-gate models as isometric holograms:
   `python3 tools/boardgame/holo.py assets/stations3d/<model>.glb <holo dir>/<name>.png [yaw] [pitch]`
   (Solara: hub = st3d_veranthos_customs_lod1, haven = HL_Station_Unity_Trade_retopo,
   freeport = HL_Station_Liberator_Military_retopo, gate = structures/jump_gate_ring.glb 35 15)
3. `HL_BOARD_ART=<art dir> HL_BOARD_HOLO=<holo dir> python3 tools/boardgame/make_board.py <out dir>`
   → the whole board, the six cards and a print PDF.

Layout numbers in make_board.py's SYS table are the game's own (HL_ORBITS writes solara_layout.json).

## Planet maps
`env HL_PLANETART=1 HL_SHOT_DIR=<dir> ... --autotest` photographs every sector of the start system's worlds from straight
above and writes `planets.json` (sectors, docks, facilities). Then `HL_PLANET_ART=<dir> python3 tools/boardgame/make_planet.py <out>`:
a 3x3 world = two portrait cards side by side (8 x 6 in), a 2x2 world = one landscape card, a 1-sector world = one portrait card.

## Station cards
`python3 tools/boardgame/make_station.py <out>`: one 4 x 6 card per station: its model as a hologram (holo.py), the game description, and its four rooms (assets/rooms/loc pictures) with what each is for. A hidden station says so on the card.

## The card system (owner's handoff, Nov 9)
- **Every card is 4 x 6 in LANDSCAPE** (1800 x 1200 px): left 3.6 in = art, right 2.4 in = info panel (WHERE, SECURITY,
  OBJECTIVE, SPECIAL RULE, REWARD, MAP; any section can grow). `make_refcards.py`.
- **The back of a facility or ship card is its playable interior**, drawn from the game's own layout
  (`HL_DUNGEONS` → `dungeons.json` → `make_dungeon.py`): grid squares = moves, start / objective / exit, red guards,
  ramps; a battleship's three decks side by side, lifts marked on both decks.
- **The strategic maps stay clean**: small markers only (`HL_HOLO_ON_MAP=0`, the default); each facility marker names
  its card (CARD F06 → HL-SOL-F06). Big art lives on the cards.
- **Tokens** (cut-outs, top-down from the models): 1 x 1 in fighters / objectives / guards, 2 x 1 in frigates and
  freighters, 3 x 1 in battleships.

## Interiors v2 (owner: "rooms nest together, like the ship plans; dungeons like Zelda")
`make_interiors.py`: the battleship as a real deck plan (three decks cut through its own top-down hull outline, rooms sharing walls, doors, numbered key, lifts and ramps between decks); each facility as a Zelda-style dungeon on the game's own room grid (rooms touching, doors where the tunnels join, room features from the game: ring, pillars, split, chamfered), floors B1.. banded to the game's level count.
