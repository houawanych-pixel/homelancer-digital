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

## Station deck plans (v13.166, PROPOSED)
`station_plans.py` builds five-deck plans for every station model in the game (`stations/stations.json`: 49):
the model's own silhouette sliced into decks (HANGAR, ENGINEERING, MAIN HUB, HABITAT, COMMAND), a main hub with
fast travel at the lift axis, ring + spokes along the station's arms, rooms in the sectors, mech (red) and pilot-only
(blue) rooms, doors keyed OPEN / YELLOW / ORANGE / RED / PURPLE. Output per model: `stations/<model>/plan.json`
(metres) and `plan.jpg`. Needs `pip install trimesh shapely opencv-python-headless`. Nothing goes into the game until
the owner approves a station; his marks get fixed by rerunning the script with per-station changes.

## Station walkways (v13.167, step 1, PROPOSED)
`station_walkways.py`: the halls only for every station's five decks (owner: "design the walkways first"), on the
fleet-ship rules (centre line + width, 45-degree spines, octagon ring and junctions, mirrored), red mech / blue pilot /
yellow lifts. Output `stations/<model>/walkways.json` (metres from the lift axis, +y front) and `walkways.jpg`.
Step 2 fits the traced library rooms along them. The v13.166 room plans (`plan.*`) are superseded.
