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
