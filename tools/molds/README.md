# Molds from models (v1.7k)

Turn a Blender shape into a block MOLD the game stamps into the ground (rock trees, cliffs, arches: "add";
caves, entrances: "cut").

1. In Blender, model the shape in **metres**, base at height 0, middle at x = z = 0. Each part must be a **closed**
   (watertight) mesh. Overlapping parts are fine if they are **separate objects** (each is filled on its own and the
   results are joined). Parts must **touch** each other and reach the base, or they would fall when stamped in (the
   tool warns about loose cells).
2. Export as **glTF binary (.glb)** (Y up, the default) or **.obj**, into `tools/molds/`.
3. Add a line to `tools/molds/molds.json`:
   `{"name": "my_rock", "file": "my_rock.glb", "op": "add", "mat": "stone", "anchor": "ground", "chance": 0.2}`
   - `op`: "add" (solid) or "cut" (air); `mat`: sand, dirt, stone, obsidian, wood, leaf, leaf2, gold, diamond
   - `anchor`: "ground" (sits a layer into the ground) or "under" (buried below the surface, for caves)
   - `chance`: how often it appears in a 500 m square (0-1); `scale` (optional) multiplies the model's size
4. Run `python3 tools/molds/voxelize.py`. It writes `scripts/mold_library.gd` (the game reads it; do not edit it).

How it works: every 5 m column, a line goes straight up through each part and counts where it crosses the surface
(in, out, in, out); a layer is inside when at least 1.5 m of it is. Where cells touch only at an edge or a corner
(a beam crossing the grid at a slant) the cells between are filled so it stays one joined piece. Tilted beams come
out as stepped diagonals (blocks are a grid).

`make_samples.py` builds the two samples from boxes (the owner's pictures 08 and 09): `beam_tree` (a block trunk with
tilted beams fanning out, obsidian) and `beam_lean` (a beam leaning on a big block, stone).
