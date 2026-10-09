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
gives light-red sand and dark-red obsidian, an ice world pale to dark ice), so no planet needs its own setup.
| Tier | Tone | Hits (light gun) | Behaviour |
|---|---|---|---|
| Sand | lightest | 1 | loose: pours, slumps, runs downhill, fills the crater back in; merges with sand |
| Dirt | light-medium | 2 | sticks: holds a rough edge; blown dirt flies and sticks where it lands; dirt on dirt merges |
| Stone | medium | 4 | holds its shape, carves, load-bearing; sticks and merges with stone when it settles |
| Obsidian | darkest | 8 | chips but keeps its shape; when it finally gives it sheds ONE solid chunk (no split into four); never fuses, the chunk stays a landmark |
Mostly stone, a little sand, obsidian as the backbone (deep core, big supports). Heavier weapons do more per hit
(missiles, the SPECIAL cut through faster).

## Target direction: start from strange interlocking shapes (ambitious, later)
- Instead of a tidy grid of squares that only looks natural once it's shot up, the world LOADS already made of
  strange, irregular, interlocking rock shapes: squares AND slanted pieces, triangles, wedges.
- The pieces lean on and lock into each other, so:
  - it looks like real rugged rock from the moment it loads (no Minecraft grid, it was never a grid);
  - support, collapse and leaning slabs are built in from the start (knock one out, its neighbours lose their prop);
  - destruction just carries on what's already there.
- Deep down this gives the big strange obsidian "Tetris" masses (obsidian holds whatever shape it's in and chips
  rather than fusing), wrapped round the lava pockets and the gold and diamond.
- Harder to generate than a grid. Order: AFTER the fused-blocks look is approved and craters work. The current
  step-1 fused-blocks terrain stays as it is for now.

## Obsidian gradient by depth
- Obsidian gets MORE common the deeper you go and concentrates in the bottom layers, nearest the heat (the heat is
  what forms and hardens it).
- So the planet has a toughness gradient: soft sand and dirt on top, stone in the middle, obsidian-heavy at the
  bottom, right above the destroy boundary.
- The deep planet is the toughest and most dangerous place to dig (heavier weapons, the SPECIAL).
- The thick deep obsidian seals the deep lava pockets best (containers are thickest where the lava is) and holds the
  deep gold and diamond.

## Underground (layered by depth, always separate breakable blocks)
- Top: the thin skin, smaller soft blocks (sand, dirt) where craters and digging happen.
- Middle: medium rock blocks.
- Deep: big rock blocks packed together (never one solid slab), getting bigger the deeper you go.
- Scattered through the deep rock, irregularly: big hard-rock boulders (darkest; go round or bring the big gun),
  sand pockets that ooze and pour out when breached (half-filling the tunnel), sticky dirt pockets that clump and
  cling, and (later) water pockets that flood when breached.

## Names (owner, voice call): sand, dirt, STONE, OBSIDIAN
The four solid tiers are now called sand, dirt, stone (was "rock") and obsidian (was "hard rock"). Same tiers, same
1 / 2 / 4 / 8 hit counts, same rule: four tones of each planet's own colour, lightest sand to darkest obsidian.
Older sections below may still say "rock" / "hard rock": read them as stone / obsidian. Lava + water makes obsidian.

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
- Underneath it is still a square block like every material; its property is what makes it flow.
- The pool reads as one level body with a flat top; as more flows in, the level rises and it spreads square by square.
- Spills go to the next pocket DOWN, so water fills and spills its way down a slope.
- Blast out the floor or wall holding a pool: it loses support and pours away to the next place that can hold it (like
  collapse, but it flows instead of falling as rubble). Then the settle-and-check above finds its new level.
- Water pockets in the rock flood out when blasted into: pour into the tunnel, run downhill, pool in the lowest
  supported pocket.

## Lava (notes only)
- Same rules as water (flow, fill flush, grow, spill pocket to pocket, settle until supported, fuse into one shape),
  but slower; glows (gives off its own light); burns / damages anything that touches it.
- Eats sand for free: the sand vanishes, the lava loses nothing. Sand is no barrier.
- Eats dirt as a trade, one for one: the dirt goes, and so does a piece of the lava. Enough dirt slows a flow and can
  stop it (a partial barrier).
- Stone stops lava: it holds it off, and shapes and channels the flow.
- Lava + water: where they meet, both are used up at the boundary and turn into obsidian. Pour water on lava and it
  walls itself off in obsidian; lava reaching an underground water pocket plugs itself solid. This is where obsidian
  comes from.
- Look: slightly transparent, red and orange. The transparency is what says "fluid"; every solid is opaque.
- Maybe (open): lava doing its own conversion to what it touches (baking, melting).
- Lava pockets (the Minecraft "uh oh" moment): lava sits sealed deep down, held in by obsidian (obsidian can hold
  lava). Break the container and the lava pours out into the gap you opened, runs downhill, fills the low spots,
  burns whatever is in the way. Gold and diamond can be container walls too.
- DORMANT UNTIL EXPOSED (owner confirmed; a key performance and correctness rule): a lava or water pocket that is
  still sealed and out of sight is frozen and inert. It does not flow, does not eat sand, does not trade with or
  convert dirt, burns nothing. It is one still shape plus a "lava here" label: a tiny bit of memory, no processing.
  Flowing, eating, trading, converting and burning switch ON only when the player breaks into the pocket and it is
  exposed. So the map never quietly eats itself in the dark, and thousands of buried pockets stay cheap.
- EXPOSURE SPREADS (a cascade): activation starts at the spot where the player breaks in or opens a cave or hole.
  From there it rolls outward: the exposed lava wakes, flows and eats; as it eats into new space it exposes more lava
  and pockets, which wake in turn, and so on. Only the active, exposed front does any work; everything still sealed
  beyond it stays frozen and cheap until the flow actually reaches and opens it. One breach can set off an unfolding
  chain, but nothing wakes ahead in the sealed dark.
- SAME FOR WATER (owner: "same as water"): both rules above, dormant-until-exposed and the exposure cascade, apply to
  water exactly as to lava. A sealed water pocket is frozen and costs nothing until broken into; once exposed it
  pours and floods, and as it flows into new space it wakes the next pocket, cascading from the breach. Only the
  open, moving front costs anything.
- Pockets are placed only inside solid sealing materials: obsidian, stone, diamond, gold. Never in sand (loose sand
  can't hold lava). Sand that ends up next to active, exposed lava just gets eaten.

## Mining: gold and diamond (notes only)
- Two valuables, separate from the ground tiers: gold and diamond. Rare, deep, often near the lava.
- Both can hold lava, like obsidian (they can be the walls of a lava pocket).
- You blow them up to get them: your weapons are the mining tools. Blast them loose, collect the pieces.
- You only get about half: the blast destroys the rest. Careful mining (light gun) keeps more, a big weapon loses more,
  so precision pays.
- A piece has to be broken small enough to pick up before you can collect it: the same split-into-four breakdown,
  keep breaking until the chunks are pickup-size, then collect.
- Very tough (they can hold lava).
- Cashed in for money or upgrades (owner: yes; which one, or both, still to decide).
- Open: how tough each one is (diamond tougher than obsidian?), how rare, what they're worth.

## Transparency = fluid
- Rule of thumb: see-through means it flows.
- Water: clearly transparent, tinted its own colour (blue), so you see the ground, rocks and pockets under a pool.
- Lava: only a little transparency, glowing red-orange, so it looks molten and alive, not solid.
- Sand, dirt, stone, obsidian: opaque.
- Kept cheap and colour-only: a simple translucent material, no heavy textures.

## Fluids stay cheap
Water, lava and sand only flow when disturbed AND near the player. Otherwise each one sits as one still, fused shape
and costs nothing.

## Whole planet, later
- The end goal: the whole planet is blocks and the smooth terrain is retired.
- Owner decision: GO ALL BLOCKS. The blocks become the one and only ground system on the whole planet; the old smooth
  terrain is NOT kept as a layer underneath. "Smooth" survives only as the cheap far-distance look of these same
  blocks. Order: get the look approved on the test patch first, then roll out planet-wide and remove the old
  smooth-terrain system (a bigger job, after approval).
- Possible cheap version: smooth look in the distance, turning into blocks up close.
- How they fit (detail on demand): the blocks ARE the ground, not cubes sitting on top of the smooth sheet. Wherever
  blocks are active, the smooth sheet is hidden underneath.
- Level of detail by distance, to stay cheap on phone and web: far away, a smooth, cheap version of the same ground;
  as you fly closer it turns into the real fused, destructible blocks. Detail only where the player is and can shoot.
  Same ground, swapped by distance, so there is no blocky-near / smooth-far mismatch.
- Today (prototype): only the 800 m test patch is blocks (smooth sheet sunk out of sight there); the rest of the
  planet is still smooth, which is why smooth hills show in the distance. Expected for now; the distance swap above is
  how it gets resolved later.

## Bottom of the world: the destroy boundary
- DECIDED: the very bottom layer of the world is this destroy boundary, NOT a lava core.
- A kill layer at the bottom. Sand, water and rubble that reach it vanish (deleted); the ship blows up if it touches it.
- Anything that crosses it is simply destroyed: no mixing, no pooling, no pile-up. Water that pours all the way down
  vanishes; sand, dirt, rubble, any material is deleted too.
- It doubles as automatic clean-up: whatever drains or tumbles to the bottom is removed, so fluid and piece counts
  never grow out of control.
- Hazard: the player's ship hitting it is destroyed (death floor).
- Cheap: just a check against one bottom depth, no simulation.
- Its look (optional): a raging, rippling, sun-like lava surface over the kill layer, a cheap shader (like the Star Fox
  sun stage). It is only a look; it isn't a lava fluid.
- A real lava core underneath is for later, not now.
- The lava core idea (relayed later): the very bottom layer is molten lava. Digging down goes sand, dirt, stone,
  obsidian, then breaks into lava at the base, which floods up glowing and burning; the deeper you dig, the more
  dangerous. Water pockets near the base crust into obsidian (lava + water). NOTE: on the call the owner also said
  "we can put that later, we don't need a lava layer underneath", so for now the bottom stays the destroy boundary
  (with the lava LOOK); the real lava core is the later version.
- REPLACED by the destroy boundary above. Kept only as a possible later look: the lava core was DEFERRED
  (nice-to-have, not needed for the prototype). If it's ever done it is NOT a
  simulated fluid: one flat sheet drawn like the Star Fox "sun" lava stage, a constantly rippling, raging surface
  (wave animation in the shader on the GPU, plus glow and flares). Cheap, because every point just follows a wave
  formula over time: no per-square flow, no neighbour checks. It still counts as REAL lava: it burns / damages, and
  can well up if dug into.
- Big lava or water seas elsewhere can use the same cheap animated-surface look.

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
