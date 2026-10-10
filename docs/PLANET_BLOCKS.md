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
| Obsidian | darkest | 8 | chips but keeps its shape; when it finally gives it breaks off whole, in half (no split into four); fuses only with obsidian; the chunks stay landmarks |
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

## The deep world: an obsidian root structure (long-term vision)
- The kill boundary is CAPPED by obsidian so the planet doesn't drain into it (without the cap everything would just
  fall down). The kill boundary only catches what gets blasted all the way through.
- The cap is not a plain flat floor: the deep obsidian is a branching TREE-ROOT / skeleton structure, dark glassy
  roots forking and twisting up from the base and holding the planet up. Between them: self-carved caves, loose sand
  and dirt settled into the crooks and low pockets, lava glowing between the branches, gold and diamond in the forks.
- Nobody hand-places it: the world carves it from the simple material rules (sand pours and settles, dirt clumps,
  the unsupported collapses, obsidian holds its strange shapes), so every dig is different. The bottom of the world
  becomes a sight worth digging to, not a boring boundary.
- The branches must CATCH AND HOLD: thick and frequent enough that loose material bridges the forks, wedges between
  branches and fills the crooks, instead of falling straight through the gaps and hollowing the planet. Balance: airy
  enough to read as roots, solid enough to carry the load.

## Radius of exposure: the firm anti-crash cap (the most important performance rule)
- However huge or carved-out the exposed world is, ONLY what's within a set radius of the player is ever active
  (falling, flowing, settling, cascading, calculating). Everything outside it stays frozen as still shapes, even if
  it's wide open, and costs almost nothing.
- The radius moves with the player. Pushing forward exposes new structure ahead and sets off chain reactions just in
  front of you (sand pouring, dirt sliding, branches shedding, lava seeping); behind you, what you passed settles and
  freezes again. Chaos ahead, stillness behind: dramatic where you are, cheap everywhere else.
- The radius is the dial: tune it to what a phone handles comfortably.
- Together with: freeze-on-settle, a hard cap on how many pieces are active at once, and kill-floor clean-up, so
  counts never pile up and the full vision can't crash the game.
- Open (owner, call): "we want to pull that first, then put the kill zone in", i.e. remove the old ground first.
  Not settled whether that means a separate stripped-down test world (kill floor plus blocks, live game untouched)
  or the live planet. Current written order stays: the old ground keeps working until the blocks are ready to replace
  it. Confirm before doing either.

## Underground lighting (long-term vision): you're never just travelling in the dark
- Ship flashlight / headlamp: casts ahead as you dig and fills the plain dark gaps. Just ONE light among many.
- Real light sources that light their surroundings on their own (not only reflecting your beam):
  - Lava: warm glow, lights everything near it.
  - Diamond: bright, cold, sparkling glow that lights its pocket of the cave.
  - Gold: warm, rich gleam that lights the nearby rock. (Warm gold vs cold diamond, so they read differently.)
  - The kill zone: glows VERY bright and lights everything from below (the underside of the obsidian roots
    silhouetted against it, the deepest caverns). Doubles as the danger warning: the glow through the gaps as you
    near the bottom.
- The flashlight makes whatever it hits light up MORE, on top of its own glow: sweep the beam onto diamond or obsidian
  and it flares / gleams brighter; hit water and that whole area lights up as the light carries through the clear water.
- Reflection / shine on top: obsidian is volcanic glass, so it's glossy; the flashlight and the glows glint off the
  roots (highlights slide as you move), and off water. The owner stressed the difference: a glow is a real light
  source (lights things even when your beam isn't on them), reflection just bounces your beam. Do both.
- Feel: a living, glittering underworld; treasure announces itself by its own light (the sparkle doubles as a "dig
  here" cue); danger glows from below. Beyond the radius bubble it's black.
- Keep it cheap on phone and web: fake most of these as emissive glows (and cheap glossy highlights), only a few real
  dynamic lights. Same look.

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
  - Sand: a soft mound with a blunt top (next section).
  - Dirt and stone: only a light rounding of the skin's edges and corners.
  - Obsidian: sharp crystal shards, earned by fusing with other obsidian (see "Shapes on the skin"); a lone piece stays a block.

## Sand: the mound rule
- (refined) The "pyramid" is a soft mound with a BLUNT top, not a sharp point. It only forms while the sand's top is
  open: the moment something lands on it (dirt, a diamond...), the sand under the load squares back to a flat block
  and the thing rests on that flat top.
- A lone sand block on open ground reads as a soft, blunt-topped mound, not a cube (never a sharp point).
- Falling sand forms that slope as it lands (it piles, it doesn't stack).
- Poured into a corner it banks against the walls as a half-mound.
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
- Two valuables, separate from the ground tiers: gold and diamond. Rare; deep (often near the lava) OR right out in
  the open surface landscape, depending on the planet (see below).
- Both can hold lava, like obsidian (they can be the walls of a lava pocket).
- You blow them up to get them: your weapons are the mining tools. Blast them loose, collect the pieces.
- You only get about half: the blast destroys the rest. Careful mining (light gun) keeps more, a big weapon loses more,
  so precision pays.
- A piece has to be broken small enough to pick up before you can collect it: the same split-into-four breakdown,
  keep breaking until the chunks are pickup-size, then collect.
- Very tough (they can hold lava).
- Collected with the tractor beam the game ALREADY has: break the vein down to pickup size, then pull the pieces in.
  The mining step hooks into it, nothing new to build. Only pickup-size chunks get drawn in; bigger pieces must be
  broken down first. The blast loses about half; the beam collects the surviving pickup-size pieces.
- Treasure isn't only deep: some worlds have gold and diamond right out in the open (piercing out of arches, rock faces,
  outcrops). How much and where is rolled by each planet's seed: some worlds easy surface pickings, some deep only.
- A loose single diamond comes to rest TILTED (sideways, at an angle), so it glints off its faces.
- They NEVER fuse (the one exception to "everything fuses with its own kind"), so a vein can be broken down small
  enough to pick up; if they fused they'd merge back and could never be extracted.
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
- EACH MATERIAL BREAKS ITS OWN WAY (owner, call; refines the generic "into four" for the flying pieces): harder =
  fewer, bigger pieces. You can read the material by how it comes apart.
  | Material | Pieces | When the pieces land |
  |---|---|---|
  | Obsidian | 2 (breaks in half) | a hard landing cleaves it in half once more; big glassy black chunks that hold their shape (landmarks) |
  | Stone | 3 | big chunks that come down heavy and hold their shape |
  | Dirt | 4 | sticks: wherever it hits (wall, block, ground) it sticks and fuses on |
  | Sand | 5 | disperses: scatters loose and settles into a pile |
  Example (owner): blast an obsidian mountain and big whole blocks calve off like a glacier, tumble down and break in
  half on impact, landing as black glass boulders: far more dramatic than sand or dirt crumbling.
- The ground blocks themselves still split into four where hit (20 -> 10 -> 5 m), except obsidian, which never splits.

## Settling
- Stone in detail: it breaks into 3 heavy pieces that come down hard and hold their shape, then fuse with the stone
  around where they land into a NEW stone shape (the terrain reshapes itself in solid stone).
- Obsidian fuses too, but ONLY with other obsidian: big chunks that break off, fall and land near obsidian fuse into a
  bigger obsidian shape (the strange Tetris-like black-glass masses); that is what grows the deep root structures.
  It still breaks into 2 and cleaves in half on a hard landing. Every material fuses only with its own kind:
  obsidian (2 pieces), stone (3, a new shape on settle), dirt (4, sticks where it hits), sand (5, disperses, settles
  into its pile).
- EVERYTHING FUSES WITH ITS OWN KIND, nothing mixes (owner's corrected rule): obsidian with obsidian (that is how
  the big strange obsidian shapes and roots grow), stone with stone (fallen pieces merge into a new rocky shape),
  dirt with dirt (it sticks where it hits), sand with sand (it settles into its pile). The one exception: gold and
  diamond never fuse (so they can be mined). This replaces the older "hard rock never fuses".
- Split when hit, merge when settled: rubble that comes to rest merges with its own kind into bigger blocks, so the
  piece count drops back down.
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
- v1.5t: each blast is one note [x, y, z, weapon]; the patch regrown from the seed plus the notes is the same ground,
  block for block. The game has no save file yet, so for now the notes last while you play (leave and come back and
  the craters are still there); a reload starts fresh. A real save will just keep the notes.

## Shapes on the skin: shards, tips and the "hypernerve" (owner, call; notes only)
- The hypernerve skin is PER MATERIAL: sand eases into soft blunt mounds, dirt and stone get a light rounding,
  obsidian and diamond crisp into sharp, faceted crystal shards (reference: Superman's Fortress of Solitude, big
  diagonal crystal shards leaning on and crossing each other). Blocks underneath for the logic, shapes for the eyes.
- (Scale detail: a small obsidian poke gets one sharp tip; a big exposed mass a crown of a few big points of varied
  height across its top, scaled to the mass. "One shape in, one smooth form out" is what fully kills the blocky look.)
- It works on the WHOLE fused shape as one, at an adjustable scale: a big fused mass becomes one grand coherent form
  (grand shards, a sweeping ridge, a smooth dune), not per-block detail. Any outline, even a plain rectangle or an odd
  Tetris shape, comes out smooth and sculpted, never boxy.
- Obsidian and diamond shards are EARNED BY FUSING: a lone piece stays a plain block; two or more fused get the shape.
  The two-block rules (same for both, obsidian big / dark / glossy, diamond smaller / bright / glowing):
  - side by side flat on the floor: the points jut out sideways, along the ground;
  - stacked upright: the top becomes the point;
  - tilted: the highest end becomes the point;
  - always rooted where it meets the ground. Shards follow the footprint and point up or diagonal, never down (a
    wide low pair points sideways along the ground, per the owner's two-block rule).
- Only the exposed tip points; the body behind stays solid mass. The bigger the fused mass, the more shape it earns:
  more shards and facets top and bottom (a small pair keeps a flat footing, a big mass becomes a faceted crystal
  monument; its base is faceted with angled planes too, not one dead-flat slab, just rooted enough to sit).
- A diamond deposit can look like one grand glowing shard cluster, but it still breaks into separate pickup pieces when
  mined and never re-fuses. Since diamond doesn't fuse, its "one shape" is the deposit / vein the generation places;
  the big adjustable hypernerve sculpts that into a grand cluster of bright glowing shards.
- Example the owner likes (rare, rolled by the seed): a blunt sand mound with a single diamond resting on top, tilted,
  glinting from far off, a "come get me" landmark you fly straight toward; or a dark obsidian piece crowning a pale
  mound, which tumbles down if blasted off. (Per the owner's later refinements the mound's top is blunt, not a tip,
  and a lone piece on it rests tilted as a plain block; shards only come from fused pieces.)

## World generation wish list (owner, call; the ambitious later step)
- From arrival the world should look amazing: big interlocking slanted shapes (above; plain square blocks still
  tracked underneath for material, support and destruction, this is the generated outer form), obsidian roots and
  shards PIERCING up out of the ground ("the planet's bones piercing its skin"), visible from the air as you
  descend; they connect down to the deep roots, so they tell you where the root system, lava and treasure are,
  Pride Rock style promontories (big jutting overhangs held up by what's under them: blast the support and the whole
  thing comes down; bold silhouettes you see from far off and fly toward, not just rolling hills), rock arches AND obsidian arches big enough to fly under or through (load-bearing: take a leg out
  and the span drops), deep winding CANYONS to fly down into with the layers showing in their walls.
- Everything rolled by the seed per planet: treasure amount and place (surface or deep), arches, where roots
  pierce, where bluffs stand, layout. Nothing hand-placed; every world a surprise (some lucky with surface gold, some
  stingy and deep, some full of arches, some bare and jagged), so exploration never runs out.
- Method is the builder's choice; one standard way is a heightmap (a grey picture the seed paints: dark = low,
  canyons and hollows; light = high, peaks), possibly a few layered maps (shape, treasure, roots). New seed = new
  map = new world; a planet could even be hand-made later by painting its map.
- Canyons are for flying: a canyon run at speed, treasure in the walls, roots piercing through, arches overhead,
  bluffs towering above.
- REALISTIC HEIGHTS: believable slopes and proportions, no thin "Eiffel Tower" spikes; clamp the noise's extremes.
  Drama from scale and bold shape, not impossible spikes.
- CAVES: carved by 3D noise (Minecraft's cheap trick) so they're organic and winding, not boxy Tetris rooms or one big
  empty chamber; the hypernerve rounds their walls. But in SECTIONS: little self-contained pockets of "ant farm"
  (branching tunnels and caverns), solid rock between them, never one planet-wide warren. Unlike Minecraft, our blocks
  know their support, so a cave roof can come down; each pocket sleeps until broken into.
- Caves are beautiful and are where fights happen too: dogfighting through a pocket with an enemy on your tail, shots
  tearing up the rock; bring a roof down on a pursuer, shoot an arch leg to block one. The terrain becomes a weapon.

## Bumping walls underground (owner, call)
- Underground you'll touch walls constantly. SETTLED (owner, call): at normal cruising speed and below (and while
  braking) a wall bump does NO damage; only when you pass cruise speed does a crash hurt. Ship and mech both, and
  the mech gets a higher safe speed than the ship. Lava and enemy fire stay as dangerous as ever.
- The mech can thrust full force against a wall ("boom") and take no damage: it's the underground workhorse that
  muscles through where the ship has to finesse. Owner: YES, thrusting into rock and dirt breaks it, just like
  shooting: the thrust counts as hits on the blocks it pushes against, with the same carving and the same tier hit
  counts. Owner refinement: no lawnmower. Sand and dirt: the mech plows straight through. Stone: it fights back
  with a BOUNCE-BACK, but still breaks (chip, bounce, chip). Obsidian: NOT by thrust, guns only; it just stops /
  bounces the mech. SETTLED: the mech is NEVER hurt by thrusting into terrain, any material ("we don't get hurt,
  at all"); the stone bounce is the only resistance.
- BUILT (v1.5u, over the block ground only): a ground bump is free up to 40 m/s (`BLOCK_SAFE_BUMP`, owner's number;
  50 still hurts) and always while braking; above it only the speed past 40 counts (0.9 hull per m/s). The mech is
  never hurt by the ground. Elsewhere the old rule stays (free under 8 m/s).
- BUILT (v1.5v, block ground only): the mech meets a wall ahead (higher than a 5 m step) and can't walk into it;
  pushing digs it by the shot rules ("thrust" blasts, kept as crater notes like any other). Sand and dirt: no
  bounce, it eats its way on (a 5 m dirt layer every 0.12 s while you push). Stone: one hit per push, then a 14 m/s
  shove back (4 pushes a 5 m layer). Obsidian: never breaks, only bounces. No damage, ever. Because the blocks only
  carve from the top, a tall wall crumbles from its top down as you push until it's low enough to walk over (real
  tunnels sideways come with caves). The ship still pops up onto steps.
- Note: over the block patch the ship doesn't hit block walls from the side yet (it pops up onto the step); real side
  collisions come with caves.

## Missiles: regular vs super (owner, call)
- Two missiles: the regular one and the super (heavy) one. The super has a BIGGER explosion, a bigger crater and a
  bigger hitbox, in space dogfights too, not only on the ground. On the block ground it already digs bigger (heavy
  20 m vs missile 12 m blast radius). BUILT (v1.5w), the space side too, in normal play as the owner asked: the super
  missile goes off within 14 m of its target (regular 9 m, `HEAVY_MISSILE_HIT_RADIUS` / `MISSILE_HIT_RADIUS`) with a
  big explosion (`BLAST_HEAVY_MISSILE`). v1.5x: it hits as hard as 3.5 regular missiles and locks slowly (2.5 s a
  lock, 1 or 2 at a time). Mines are as strong as a super missile; two kinds: blast and magnetic (pulls in and holds
  3.5 s). Details in docs/DESIGN.md.

## Arches (generation step, later)
- Natural arches: big chunky spans curving over open space on a leg at each end (Arches National Park style).
  Both STONE (rough) and OBSIDIAN (dark, glassy, catching the light; can be a root breaking the surface and curving
  over).
- Flyable: big enough to fly under or through (a threading moment).
- Load-bearing: blast out a leg and the whole span crashes down; a bit tougher, so a stray graze won't drop one.
- Some have diamond or gold piercing out of the span, glowing from far off: blast it out carefully without bringing
  the arch down. Landmark, reward and mining challenge in one.

## Polish for the very end (owner, call)
- Cracked, sun-baked earth on the UPWARD-facing top of big fused dirt shapes only (sides and underside plain); a cheap
  texture or shader, not cut geometry. It follows the top of the whole fused shape, however irregular; a shader can
  shade the cracks so they look slightly recessed. Texturing the skin is the cheap part of the hypernerve, reshaping
  geometry the costly part. Could extend the same cheap way to sand ripples and stone strata / fracture lines.
  Parked: do not prioritise.
- Water with gentle animated ripples and shimmer, lava a slow glowing churn: the same cheap GPU surface-wave trick,
  no fluid simulation.

## Generating and loading a planet (owner, call)
- When you arrive you descend through the atmosphere and the cloud layer, and that descent hides the work: the world
  generates from its seed behind the cloud, and you break through to a finished planet. No load screen; the descent
  IS the loading, and it feels like flying. A bigger generation can stretch the cloud descent a little.
- It can start far and low-detail and sharpen as you drop closer (the smooth-far / blocks-near swap), and the planet
  is fully built and revealed as you break out of the bottom of the cloud. No spinner, no visible wait.
- We never store the world: one seed regrows exactly the same planet every time (all layers, roots, pockets), plus
  the list of the player's changes (the craters step already keeps seed + one note per blast).
- Load flow: load the seed -> regrow the planet during the descent -> re-apply your saved changes -> come out below to
  the planet exactly as you left it, every crater and tunnel there. Tiny saves, hidden loading.

## Tile border and corners
- Crossing a tile edge: instead of the instant Pac-Man snap, the camera eases across so there is no visible jump.
- Fog only in the four corners (where four tiles and their different terrains meet and seam lines cross); the edges
  stay clear.

## Later
Water and lava (flow when a wall breaks), trees (shoot the trunk, the top falls), Continue / New World on landing.

## The owner's look pictures (Oct 10, docs/blocks_look/) and the voxel notes
- 01-05: blocky canyons, an arch and a Pride Rock overhang, big and small blocks mixed (long rectangles and big solid
  cubes, not one size of square), dirt with a thin grass cap in the planet's colour, an obsidian tree with pointed
  tips, an obsidian cave with shard stalactites. Slants: "a few" (mostly square steps).
- 06: alien trees and waterfalls. New block materials: WOOD (the trunk and branches, grey-brown, chunky and twisting)
  and LEAF (the canopy: big flat blocks in two colours, teal and purple). Waterfalls pour off cliff edges into pools.
  Wood CATCHES FIRE (owner, confirmed): lava, explosions and shots can set wood (and leaves) burning; the fire spreads
  to touching wood and leaves, burns them away, and dies out (keep it near the player only, like the fluids, for phones).
- 07-09 (isometric molds): a cave layout to carve (a big chamber, four tunnels, side rooms, stairs); a straight beam
  leaning on a big block; a tree of tilted beams.
- "Minecraft Cave Technique" (owner's Drive notes): seeded terrain + designed shapes; noise caves (chambers, winding
  tunnels, narrow passages) found by digging; molds stamped in (add: trees, roots, cliffs; subtract: caves with a
  surface entrance), cut as filled volumes; check clearance, connection and ceiling thickness after carving; carve the
  cave first, then the roots that should show in it. First prototype: one chamber, two tunnels, a surface entrance,
  one tree whose roots reach into the chamber.
- Plan: v1.7g the look (grass cap, big/long blocks, a few slants) -> v1.7h molds + the first cave -> v1.7i alien trees
  (wood + leaf blocks, roots into the cave) -> v1.7j winding tunnels, a Blender-to-mold tool, waterfalls, phone check.

## Build order (a preview to the owner after each)
Status: the owner said go for step 2 (craters), step by step. Each next step waits for his go after the preview.
1. DONE: the big-block test terrain on New Terra's mountains (800 m patch, 20 m blocks, 5 m steps).
1b. DONE (v1.5s, behind ?blocks): same-material ground fused into one solid surface, no cube seams.
2. DONE (v1.5t, behind ?blocks): craters. Blast radius by weapon (light gun 2.4 m, missile 12 m, heavy 20 m, SPECIAL
   40 m); blocks split into four only where hit, down to 5 m; hits by tier (sand 1 / dirt 2 / stone 4 / obsidian 8),
   cracked blocks darken; tones by tier from the planet's colour; layers by depth (sand/dirt skin, dirt and stone,
   then stone with obsidian growing deeper); rubble by material (obsidian 2 halves that cleave again on a hard
   landing, stone 3, dirt 4, sand 5; at most 10 pieces a blast, 60 alive; landed pieces sink away after 25 s);
   the ship's shots and missiles hit the block ground (no target over the patch: missiles fire straight, to dig);
   seed + one note per blast, re-applied on return. Not yet: dirt sticking, sand piling, fusing of rubble (step 5).
2b. DONE (v1.5u / v1.5v, behind ?blocks): free wall bumps up to 40 m/s (mech never hurt); the mech digs by pushing.
2c. DONE (v1.5y, behind ?blocks): support and collapse. Shots, missiles and the mech dig INTO walls (tunnels,
   overhangs, holes under the top) instead of only from the top: each 5 m cell keeps its air pockets. A piece over a
   hole stays up only if it is joined sideways to grounded ground within its material's reach (`BLOCK_REACH` in cells:
   sand 0, dirt 1, stone 3, obsidian 5); otherwise it falls and lands on what's under it (a few rubble pieces fly).
   So a stone overhang holds, a sand one caves in, a pillar shot through its middle comes down. Tunnel roofs hold the
   ship and mech down; tunnel floors carry them. Kept as the same notes (the collapses replay from the blasts).
   Simplified for now: a fallen piece takes the material of where it lands (by depth), and it drops in one go.
2d. DONE (v1.5z, behind ?blocks): settling. Rubble that comes to rest (1 s) merges into the ground as ITS OWN material
   (its volume in 5 m layers, `fill` until a whole layer builds up; nothing mixes). Dirt that hits a wall in flight
   sticks to it (a dirt ledge, held up by the wall like any overhang). Sand slumps: a sand top more than one layer
   over a neighbour pours onto the lowest one, so piles end with 45-degree sides. Pieces that fall in a collapse now
   keep their own material. Each merge is kept as a small note ("dep:<material>:<amount>"), so the ground regrows the
   same. Not yet: leaning slabs / A-frames (stretch), the smoothed look (sand mounds, crystal shards: next).
2e. DONE (v1.6a, behind ?blocks): the skin (first cut, look only, collision stays square). Where a block's top
   steps down on a side: sand eases into a soft blunt mound (inset 1.8 m, down 4 m), dirt gets a rounded edge (1 m),
   stone a light one (0.7 m); obsidian joined to obsidian points up into a faceted shard tip (up to 8 m, leaning away
   from the obsidian it's joined to); a lone obsidian block stays a block (`BLOCK_SKIN`, `BLOCK_SHARD_HEIGHT`).
   Not yet: the big adjustable hypernerve over whole fused shapes (grand dunes, sweeping ridges, shard clusters),
   the full two-block orientation rules, diamond (no diamond in the ground yet).
2f. DONE (v1.6b, behind ?blocks): water and lava. Sealed pockets from the seed (`FLUID_POCKETS`: 8 water in stone
   20-60 m down, 5 lava in obsidian 60-150 m down; never in sand, not in the middle of the patch). They sleep: a
   sealed pocket never moves. Break in and it pours: each 5 m unit falls if it can, spills over a lip, spreads when
   there's more on top, so a pool fills flush and finds its level. Only within 250 m of the player does anything
   flow (`FLUID_RADIUS`, the radius of exposure); lava moves 3x slower. Water turns sand it touches into dirt; lava
   eats sand, trades one-for-one with dirt, is stopped by stone; lava meeting water becomes obsidian. Water is clear
   blue, lava a little see-through and glowing. Lava burns the ship and mech (`LAVA_DPS`). Rock changes from all
   this are kept as notes ("set:" / "cut"). Simplified for now: where water and lava flowed to isn't saved; a pocket
   that was opened before is gone (empty) when you come back. Water doesn't slow you yet.
2g. DONE (v1.6c, behind ?blocks): mining. Gold and diamond veins from the seed (`MINE_VEINS`: gold 25-120 m down,
   diamond 80-170 m; half the lava pockets have diamond in the obsidian over them; 60% of worlds also wear a few right
   out on the surface). Bright fixed colours on any world. Tough: gold 6 light-gun hits, diamond 12 (tougher than
   obsidian, the owner's open question answered for now). Breaking a layer drops pickup pieces (gold 4, diamond 3), but
   the blast destroys the rest (`MINING_KEEP`: light gun / mech 3 in 4, missile half, heavy a third, special a fifth),
   so careful digging pays. The pieces never turn to rubble or fuse back. The tractor beam the game already has pulls
   them in: gold 40 cr, diamond 120 cr a piece (`MINE_VALUE`; upgrades instead of money is still open).
   Not yet: real glow / light from them (the lighting step); breaking big pieces down to pickup size (every piece is
   pickup size for now).
2h. DONE (v1.6d, behind ?blocks): world generation, part 1. Caves: 5 self-contained pockets of winding tunnels and
   chambers (3D noise in a rounded 70 x 40 m box, 45-110 m down, never in the middle), sealed with rock over them,
   settled once at build so every roof left stands (`CAVE_*`). The kill floor: the bottom of the diggable ground
   (`BLOCK_DEPTH_FLOOR` down) under a 30 m obsidian cap (`KILL_CAP`); dug open it blazes (`KILL_COLOR`, a warning seen
   from above); water, lava and rubble that reach it are gone; the ship (or mech) touching it is destroyed.
   Known: on the test patch the tile's old sea plane (y = 0) and the sunk smooth sheet still show in very deep holes
   near the patch edge; they go when the whole planet becomes blocks (step 9).
   Next parts: arches and overhangs (Pride Rock), then canyons and obsidian roots / shards piercing the surface, the
   interlocking slanted shapes, realistic heights.
2i. DONE (v1.6e, behind ?blocks): world generation, part 2: landmarks. 3 natural arches (`ARCH_*`: 30-55 m of open
   air between two solid legs, 25-45 m headroom, 10 m of rock over it; about a third obsidian; some with gold or
   diamond glinting in the span) you can fly under; 2 Pride Rock promontories (`OVERHANG_*`: a block of rock 35-60 m
   high with a 15-25 m slab jutting out over open air). Built only on fairly even ground (`LANDMARK_FLAT`), never in
   the middle. Load-bearing (`reach_bonus`): each half of an arch hangs from its own leg, the slab from its block;
   blast a leg out and what hung from it comes down (where an arch end rests against the hillside, that bit stays).
2j. DONE (v1.6f, behind ?blocks): world generation, part 3. Realistic heights: no column may stand more than 15 m
   over all its neighbours (`SPIRE_MAX`; New Terra's test patch had none, but other ground will). A winding canyon
   (`CANYON_*`: 40-70 m deep, about 30 m wide, wandering across the patch by noise, kept off the patch edge, never into
   the obsidian cap), its walls showing the layers, a little gold glinting in them. 6 obsidian roots piercing the
   surface (`ROOT_*`): small crowns of black glass 12-35 m out of the ground, joined so the skin points them into
   shards, each with its root running 80 m down into the rock.
   Still to come in generation: the interlocking slanted shapes (big leaning slabs, wedges), the deep obsidian root
   structure at the bottom, canyons on every world, and it all becoming the whole planet (step 9).
2k. DONE (v1.6h, behind ?blocks): the deep world, first version. 3 great root halls (`HALL_*`: 120 m across, 50 m
   tall) right on top of the obsidian cap, their floor following the cap: obsidian trunks every ~25 m stand from floor
   to roof and fork into slanting branches between them; the rock above hangs from the trunks; lava pools glow in the
   low spots of the floor (they lie still). Sealed and asleep under 30 m+ of rock until you dig down. In sections,
   not the whole planet, to stay light on a phone.
   Still to come: the interlocking slanted shapes over the whole ground; sand and dirt settled in the root crooks.
2l. DONE (v1.7a, behind ?blocks): step 9, part 1: the whole planet as blocks. Every tile of every planet is cut into
   500 m regions (`BLOCK_REGION`, 10 x 10 per tile, 100 x 100 cells each). The 3 x 3 regions round you are built
   from the seed as you fly, one at a time and a little each frame (a few rows, one feature or one mesh chunk per
   frame, so flying never stalls), nearest first (`BLOCK_REGION_REACH`), and freed once you are more
   than 2 squares away (`BLOCK_REGION_KEEP`). Each region has its own seed (planet|tile|rx|rz) and keeps its own
   blast notes, so a crater is still there when you come back. The smooth ground stays as the far view and the
   terrain shader cuts it out under every standing region (`cuts`). Landmarks, caves, pockets, veins and halls come
   at the region's share by area (`BLOCK_REGION_FEATURES`); a canyon runs through about 1 region in 5. (v1.7a
   flattened the blocks round cities; v1.7c replaced that with floating pad islands, below.)
   The old 800 m test patch is now only for the route test. Known for now: a blast right on a region edge only
   digs its own region (fixed v1.7d); blocks stop at the tile border until you cross it (fixed v1.7d); the sea plane
   shows in very deep holes.
   Next (v1.7b, after the owner tries it): on for everyone, the old ground removed.
2m. DONE (v1.7b, owner: "Ok go"): block ground ON for everyone, no link needed. Wherever you fly or walk on any
   planet you are on blocks; the smooth sheet is only the far view now (cut out under every region). `?noblocks` in
   the address turns it off on the web, in case a phone struggles. `?blocks` still works (it is simply on).
2n. DONE (v1.7c, owner idea): landing pads float. Every pad stands on a floating island of blocks (`PAD_ISLAND_*`:
   120 m across the top, ground-coloured, its rock underside hanging deepest in the middle, ragged), its top 70 m over
   the highest ground under it. So the block ground runs natural right under every city (nothing flattened, world
   building never steps round a site) and can be as big and deep as it likes. You land on the island from above;
   flying under it, its rock is a roof. Later: the owner's buildings up on the islands.
2o. DONE (v1.7d): the seams. A blast reaches every region it touches (one right on a region edge digs both sides).
   The blocks run on over a tile border: the next tile's regions near you are built in this tile's frame (keyed by
   tile -1/0/1 each way plus square; their notes kept in their own tile's frame), and when you cross, the regions
   round you come along (`BlockField.reframe`), the same blocks with nothing rebuilt. No blocks on a star's surface.
2p. DONE (v1.7e): the slanted outer form, first version (look only; the square blocks stay underneath for material,
   support, digging and collision). Natural ground where the top steps down leans into slanted slabs and wedges
   instead of square stairs: each top corner drops toward lower ground (at most `BLOCK_SLANT_MAX`, 10 m), worked
   out from the four cells round that corner the same way for every block sharing it, so slabs always meet edge to
   edge with no gaps. Where something stands higher, or the rock is obsidian, dug or rubble, the block stays square,
   so slabs and steps interlock. Still to come: big leaning slabs and A-frames as landmarks, free-angle pieces.
2q. DONE (v1.7f): leaning slabs and A-frames (`SLAB_*`, `AFRAME_COUNT`), in the regions (the old test patch is left
   as the tests know it). A lean-to is a 15 m wide, 10 m thick slab rising 20-35 m from the ground onto a stone
   pillar (its prop); an A-frame is two slabs rising toward each other until they meet, with air under them to fly
   through. Blocks underneath (a staircase of cells over air, may hang about half the slab's length from support),
   one straight tilted slab for the eyes while it is whole. Hit any part and it shows as its blocks; knock out the prop
   (or one foot of an A-frame) and the far part has nothing to hold it and comes down as rubble.
2r. DONE (v1.7g, the owner's pictures): dirt is earthy brown (`DIRT_BROWN`) under a thin grass cap (`BLOCK_GRASS_BAND`,
   1.2 m) in the planet's own colour; neighbouring columns on even ground join into long rectangles and big solid
   blocks (`BLOCK_SHAPES`: 1x1 up to 3x2 columns of 20 m), some big ones standing a step or two proud
   (`BLOCK_BIG_RISE`); slants only in patches ("a few slants": `BLOCK_SLANT_ZONE` on one planet-wide noise), the
   rest square steps like the pictures.
2s. DONE (v1.7h): MOLDS, first version (the owner's voxel notes and picture 07). A mold is a filled volume of 5 m
   cells given as runs [dx, dz, klo, khi], stamped in by `_stamp`: "cut" makes those layers air from the top down (a cut
   that reaches the surface opens an entrance), "add" makes them solid (for trees and roots next). The first mold is a
   cave system in about 1 region in 3 (`MOLD_*`): a domed chamber 80-100 m across and 35 m tall, 20 m tunnels out to
   three side rooms whose floors sit at other heights (the tunnels step), and one tunnel climbing to a 20 m shaft that
   opens to the sky. At least 15 m of rock over the chamber and rooms; its ceiling may hang further than plain rock;
   never under the sea. The test walks the air from the chamber floor: every room and the sky must be reachable,
   20 m of room all the way out, rock overhead, floor and roof solid. Still to come: a Blender-model-to-mold tool,
   more mold shapes, winding tunnels linking caves.
2t. DONE (v1.7i): ALIEN TREES and FIRE (the owner's picture 06). New materials: WOOD (grey-brown) and LEAF in two
   colours (teal "leaf", purple "leaf2"). Trees (`TREES_PER_TILE`: forests many, deserts / ice / volcanic none) are
   grown as an "add" mold: a chunky 10-15 m trunk 30-50 m tall on root buttresses, 3-5 branches stepping up and out,
   big flat leaf slabs at their ends and a crown on top (you can fly under them), roots running down and out
   underground (wood through the rock). Beside every mold cave one tree sends a root down into the chamber, hanging
   from the roof to the floor (cave carved first, roots added after). They hold together (take the trunk and the rest
   falls). FIRE: missiles always and the light gun sometimes set wood and leaves alight, lava beside them too; each
   tick a burning layer may catch its touching wood and leaves (leaves faster), burns away after a few seconds (kept as
   a note) and the fire dies out when nothing is left; water beside it puts it out; it only runs near the player
   (`FIRE_*`), glowing orange blocks over what burns.
2u. DONE (v1.7j): WINDING TUNNELS (the notes' "spaghetti caves"). From a mold cave's side rooms, up to two tunnels
   (`LINK_*`, about 20 m across) wander by noise out to the nearest sealed caves, always steering home, always under
   the ground (2+ layers of rock over them), ending in a junction room and a chimney up or down into the cave; the
   rock over them and the cave they open holds. The test walks the air from the chamber into each linked cave. Tree
   roots underground now only turn rock to wood ("paint"); they never fill a cave or tunnel. Missiles set wood alight
   round the crater, not only in it.
2v. DONE (v1.7k): MODELS INTO MOLDS. `tools/molds/voxelize.py` (plain Python + numpy; reads .glb and .obj) turns closed
   models into molds and writes `scripts/mold_library.gd`; `tools/molds/README.md` says how to make one in Blender.
   Each library mold appears in a region by its chance on fairly even ground (`_place_library`, `_place_mold`), in
   its material, held together. Tilted beams come out as stepped diagonals; cells touching only at an edge or corner
   are joined up so nothing falls. Samples from the owner's pictures 08 and 09: `beam_tree` (obsidian, its tips point
   into shards) and `beam_lean` (stone).
2w. DONE (v1.7l): WATERFALLS (the owner's picture 06). Where a natural column drops 20 m+ to its neighbour
   (`FALLS_PER_TILE`, `FALL_*`), a pool is cut into the top behind a one-cell rock lip and a pool at the cliff's foot,
   both real water; between them a moving sheet of water (a scrolling shader) and white foam blocks where it lands.
   Blast the lip and the fall stops. The slab and waterfall drawings now move with a tile crossing too.
2x. DONE (v1.7m): UNDERGROUND LIGHT, first version (the notes' lighting section). The block ground has its own shader:
   each face carries how much sun and sky reach it (covered faces: a floor under a roof, a roof, a wall facing into a
   hole get `CAVE_DARK`), its own glow (gold warm, diamond cold: emissive) and its gloss (obsidian glassy, gold and
   diamond shiny: a highlight from every light). The ship's FLASHLIGHT comes on under a roof (`FLASHLIGHT`). A few
   real lights (`GLOW_LIGHTS`, the nearest to you) sit on glowing things: lava, fire, exposed gold and diamond, the
   kill floor where it is dug open, so they light their surroundings. Still to come: the flashlight making what it
   hits flare brighter, light carrying through water.
3. DONE (already from earlier work): the ground blends across tile edges and the next area is built before you reach
   it, so crossing has no jump.
4. DONE (already): no seam lines at ordinary corners (the ground blends); the planet's wrap corner sits in a cloud bank.
(Old 3.) Border camera hand-off.
4. Fog in the four corners only.
5. Support and collapse, then cave blocks, overhangs, arches; merging and leaning rubble; stretch goals last.
