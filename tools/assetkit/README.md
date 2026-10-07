# assetkit: intake of the owner's big ship-set GLBs

Work tools (never exported with the game). Order of use, one faction set at a time:

1. `node decode.js meshopt_decoder.js ORIGINAL.glb work/X/raw` (the sets use meshopt compression; Godot cannot read them)
2. `python3 split.py work/X` : one preview GLB per connected piece, biggest first
3. `python3 orient.py work/X/prev/cNN.glb work/X/ori/cNN.glb [ops]` : finds a ship's mirror plane in 3D and levels it
   (ops: `fz` swap nose/tail, `fy` upside down, `rx` quarter turn, `free` for wide ships). Look at the result:
   `tools/shipkit/views3.gd` renders top / side / two three-quarter views, `sheet.py` puts them on one sheet.
4. `python3 build.py work/X names.json` : light copy per piece (names.json: `{"0": [name, triangles, texture px, R]}`,
   R = the 3x3 turn that orient.py saved beside its output, optional)
5. `python3 mirror_x.py IN OUT` : symmetry repair for a levelled ship (`symmetrize.py` is the older yaw-only version)
6. `python3 rear_swap.py SHIP DONOR OUT ship_cut_z donor_cut_z [scale dy overlap]` : thruster repair. Cuts an upright
   tail cannon off and grafts on the rear end of another ship of the set. `profile.py` prints the cross-sections to pick
   the two cut positions; `crop.py` cuts a region out to look at it; `DONOR_BOX` drops fin tips that would float.
7. `python3 shrink_tex.py IN OUT 768` : the copy that goes into `assets/ships/enemy/`
8. `tools/shipkit/topview.gd` on the final file: the nose must point UP. Then the ship table, the route test, the
   asset library.

Originals are never written to. Every step writes a NEW file.
