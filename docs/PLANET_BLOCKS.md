# Destructible planet ground: the owner's design (experiment, branch planet-blocks-test)

Source: the owner's Bible ("HL Minecraft-Style World Elements"), his talk-through by voice, and the notes relayed from
those calls. Light version built into the existing planet ground: Godot 4.3, web, no engine change, no Zylann Voxel
Tools (that needs Godot 4.4.1+ and has no web build; if smooth arches ever become a must-have, trial it in a separate
throwaway project, never here). Everything is tried on ONE test planet first (New Terra), live game untouched.

## The idea in one line
An interesting noise surface on top, huge solid blocks underneath, fine detail only where you shoot.

## Blocks
- Big blocks (chunks) about ship-sized: `BLOCK_BIG` 20 m. Any box shape: cubes, slabs, rectangles ("a rectangle is
  still a block").
- The smallest block is half a mech: `BLOCK_MIN` 5 m. Nothing ever goes smaller (we are not building Minecraft).
- The surface follows the planet's own noise shape, in 5 m steps (DONE, step 1).

## Materials (properties), shown by TONE
Every planet keeps its own palette; toughness reads by how dark the block is, same rule everywhere ("darker =
stronger"). The tones are made from the planet's own base colour (light / medium / dark versions of it: a red world
gives light-red sand and dark-red hard rock, an ice world pale to dark ice), so no planet needs its own setup.
| Tier | Tone | Hits (light gun) | Behaviour |
|---|---|---|---|
| Sand | lightest | 1 | loose: pours, slumps, runs downhill, fills the crater back in; merges with sand |
| Dirt | light-medium | 2 | sticks: holds a rough edge; blown dirt flies and sticks where it lands; dirt on dirt merges |
| Rock | medium | 4 | holds its shape, carves, load-bearing; sticks and merges with rock when it settles |
| Hard rock | darkest | 8 | chips but keeps its shape; when it finally gives it sheds ONE solid chunk (no split into four); never fuses, the chunk stays a landmark |
Mostly rock, a little sand, hard rock as the backbone (deep core, big supports). Heavier weapons do more per hit
(missiles, the SPECIAL cut through faster).

## Underground (layered by depth, always separate breakable blocks)
- Top: the thin skin, smaller soft blocks (sand, dirt) where craters and digging happen.
- Middle: medium rock blocks.
- Deep: big rock blocks packed together (never one solid slab), getting bigger the deeper you go.
- Scattered through the deep rock, irregularly: big hard-rock boulders (darkest; go round or bring the big gun),
  sand pockets that ooze and pour out when breached (half-filling the tunnel), sticky dirt pockets that clump and
  cling, and (later) water pockets that flood when breached.

## Names (owner, voice call): sand, dirt, STONE, OBSIDIAN
The four solid tiers are now called sand, dirt, stone (was "rock") and obsidian (was "hard rock"). The table above
keeps the old words until the code uses the new ones; same tiers, same hit counts, same rules. Lava + water makes
obsidian (below).

## Two layers: solid blocks underneath, smoothed skin on top (notes only, not built)
- Underneath: square blocks, always solid. They hold the data: material, toughness, hits taken, neighbours, support.
  This layer is what splits, falls, settles and gets saved. Nothing about the look changes it.
- After touching same-material blocks fuse (DONE in v1.5s for the ground), a cheap smoothing pass (the owner's
  "hypernerve") runs over the OUTER SKIN only, and only when the shape changes (a hit, a collapse, a settle), never
  every frame. It changes the look only; collision and the block data stay square.
- Per material:
  - Sand: the triangle / pyramid look (next section).
  - Dirt and stone: only a light rounding of the skin's edges and corners.
  - Obsidian: stays sharp (it never fuses; its chunk is a landmark).

## Sand: the pyramid rule
- A lone sand block on open ground reads as a pyramid / cone, not a cube.
- Falling sand forms that slope as it lands (it piles, it doesn't stack).
- Poured into a corner it banks against the walls as a half-pyramid.
- Filling an enclosed empty square it fills solid and flush to the top.
- It is NOT water: it doesn't run flat or spill pocket to pocket.
- Sand touching sand fuses into one solid mass, even in an odd Tetris shape.

## Water (notes only)
- Flows to the lowest open space and fills supported empty squares flush.
- The pool grows as it fills, then spills over the lip into the next pocket, pocket to pocket.
- After settling, wherever water sits on nothing it drops a layer, again, until all of it is supported (water can't
  sit on air).
- After settling, sand it touches turns into dirt.
- Settled water fuses into ONE flush shape (one water block shaped like the space it filled); break the edge and it
  flows out and re-forms.
- Look: transparent, blue tint.

## Lava (notes only)
- Same flow as water, but slower; glows; burns (hurts the ship / mech).
- Eats sand for free; trades one-for-one with dirt (both lose a piece); stopped by stone.
- Lava + water = obsidian.
- Look: slightly transparent, red and orange. The transparency is what says "fluid"; every solid is opaque.

## Fluids stay cheap
Water, lava and sand only flow when disturbed AND near the player. Otherwise each one sits as one still, fused shape
and costs nothing.

## Whole planet, later
- The end goal: the whole planet is blocks and the smooth terrain is retired.
- Possible cheap version: smooth look in the distance, turning into blocks up close.

## Bottom of the world: the destroy boundary
- A kill layer at the bottom. Sand, water and rubble that reach it vanish (deleted); the ship blows up if it touches it.
- Its look (optional): a raging, rippling, sun-like lava surface over the kill layer, a cheap shader (like the Star Fox
  sun stage). It is only a look; it isn't a lava fluid.
- A real lava core underneath is for later, not now.

## Flowing materials (earlier notes, kept)
- Sand piles into a cone at its own slope angle; past that it slumps; the pile merges up into bigger blocks as it grows.
- Water flows to the lowest place and fills it level, then becomes ONE water block shaped like the space it filled;
  break the edge and it flows out and re-forms. Lava: the same, slower, glowing, burns.

## Hits and blasts
- A blast has a radius (the weapons' own blast / hitbox): every block inside it is hit, not just one. Bigger weapon,
  bigger bite: light gun small, missile bigger, the SPECIAL huge (a crater you can fly into).
- Blocks show damage each hit (cracks, chips) before they give; hit counts by tier are in the table (1 / 2 / 4 / 8,
  the owner's final numbers; easy to tune). Heavier weapons do more per hit.
- A hit block splits into FOUR smaller blocks at the spot (carve only where hit: a corner shot takes a corner, the rest
  stays one big block). Again into four on later hits, down to the 5 m floor.
- The blast does not just erase: about half the material flies out as rubble (tune how much flies versus vanishes).
- Debris is a mix of sizes: big chunks at the edge of the blast, little pieces only in its centre (ten pieces flying,
  not thirty).

## Settling
- Split when hit, merge when settled: rubble that comes to rest merges with its own kind into bigger blocks, so the
  piece count drops back down (hard rock excepted).
- Pieces can come to rest at an angle (leaning, diagonal, wedged across a gap), not snapped to a grid; two leaning
  slabs make a natural A-frame arch. A leaning slab is propped by a support: shoot that out and it falls flat, then
  settles and merges by type (dismantle a formation stage by stage). Safe gear first: a few tilt angles. Ambitious gear
  later: free-angle leaning and wedging anywhere (risky on a phone, same group as the rubble-holds-shape goal).
- Stretch goal (the risky part, tried last, after craters, collapse and merging work): rubble that catches and sticks
  against the side of a neighbouring block and stacks, so debris can grow ledges, bridges and arches and the ground keeps
  dramatic shapes instead of melting into a flat pile. Hardest to keep cheap on a phone. Safe version first: sticky
  dirt (it clings where it lands). Fallback if it's too heavy: rubble falls, settles and merges by type.

## Support, collapse, caves, arches (after craters)
- Each block knows the block underneath it (its support). Destroy the support and the blocks above lose it: they fall
  (or are eradicated). Knock out the bottom and the top comes down.
- Cave / hollow blocks: underground blocks flagged hollow; break through and they open into a cave.
- Overhang blocks: flagged "depends on the block under me".
- Arches: a curved run of blocks resting on each other over flagged-hollow space; the supports are rock or hard rock
  (load-bearing, tougher). Shoot out the base and it collapses. Chunkier than a smooth voxel arch, by design.

## Saving
Only the seed plus the changes (what broke, what opened, where rubble settled). The planet regrows from the seed and
the changes are re-applied. A hundred craters are a hundred small notes, not a field of blocks.

## Tile border and corners
- Crossing a tile edge: instead of the instant Pac-Man snap, the camera eases across so there is no visible jump.
- Fog only in the four corners (where four tiles and their different terrains meet and seam lines cross); the edges
  stay clear.

## Later
Water and lava (flow when a wall breaks), trees (shoot the trunk, the top falls), Continue / New World on landing.

## Build order (a preview to the owner after each)
Status: the owner asked to HOLD (more discussion first). Nothing past 1b gets built until he says go.
1. DONE: the big-block test terrain on New Terra's mountains (800 m patch, 20 m blocks, 5 m steps).
1b. DONE (v1.5s, behind ?blocks): same-material ground fused into one solid surface, no cube seams.
2. Craters: blast radius, split into four, hit counts by tier, tones by tier, half the material as rubble (chunks at
   the edge), seed + deltas saved and re-applied.
3. Border camera hand-off.
4. Fog in the four corners only.
5. Support and collapse, then cave blocks, overhangs, arches; merging and leaning rubble; stretch goals last.
