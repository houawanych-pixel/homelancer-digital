# Wall traces (owner-approved method, 11 Nov 2026)

`wall_trace.py` turns a game-map / blueprint screenshot into a wall-only trace: the outer silhouette is a hard wall
line, open courts are holes, every asset inside (furniture, pillars, consoles, labels) is dropped. White lines on
black for the owner to approve, a red overlay on the source to check against, and `walls_px.json` (polygons in
crop pixels) to extrude into a graybox later.

| Folder | Source | Mode | Status |
| --- | --- | --- | --- |
| `hub_hex_01` | hex hub with four rooms (owner, via GPT) | `--mode glow --crop 655:1745,0:1080` | approved 11 Nov |
| `temple_02` | Temple Marché / Cantina level | `--mode line` (default) | shown 11 Nov |

Not yet: the real-world size (metres per pixel) for each one, doors, and inner walls between rooms. Ask the owner
for one size (whole width or one door) before extruding.
