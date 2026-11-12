# Wall traces (owner-approved method, 11 Nov 2026)

`wall_trace.py` turns a game-map / blueprint screenshot into a wall-only trace: the outer silhouette is a hard wall
line, open courts are holes, every asset inside (furniture, pillars, consoles, labels) is dropped. White lines on
black for the owner to approve, a red overlay on the source to check against, and `walls_px.json` (polygons in
crop pixels) to extrude into a graybox later.

| Folder | Source | Mode | Status |
| --- | --- | --- | --- |
| `hub_hex_01` | hex hub with four rooms (owner, via GPT) | `--mode glow --crop 655:1745,0:1080` | approved 11 Nov |
| `temple_02` | Temple Marché / Cantina level | `--mode line` (default) | outer silhouette into every notch, approved 11 Nov |

Not yet: the real-world size (metres per pixel) for each one, doors, and inner walls between rooms. Ask the owner
for one size (whole width or one door) before extruding.

Owner rules learned on `temple_02`: the outline must step INTO every notch between rooms and back out (never bridge
across); only the outer white line is used for extruding (inner face lines were too messy). Corridor diagonals with
tread lines are stairs: the two mirrored pairs lead up to a second floor.

`ship_tianjin_03` (UPP Tianjin sheet): the top-right inset is the ship's EXTERIOR, seen from above (owner). Its outline,
`eng/exterior_silhouette.json`, is the true hull; it has two levels: the main deck (`eng/build_main_deck.py`,
the centre of the sheet) and the command tower, the whole upper deck (`eng/build_command_tower.py`, the top-left
inset), which sits in the square-and-round block at the stern centre. Floor levels inside rooms: `eng/main_levels.json`.
| ship_defender_05 | SWTOR Defender (Jedi ship) in-game minimaps, flight + lower deck clean plans, rooms named from the labelled fan sheet the owner sent (sheet itself not stored) |
| ship_fury_07 | Fury-class Interceptor (Sith ship), one deck, rooms 1-15, real size 47.8 x 41 m |
| station_republic_06 | Darth Malgus space station, Command Deck (flashpoint The False Emperor): two fan wings around a round hub, north/south spines; fans mirrored about the hub centre |
| station_ring_08 | Carrick Station (Republic Fleet) main floor, round gear station: four wings (cabins, ring corridor, islands) around a hub, four spokes; one wing drawn in polar and rotated |
