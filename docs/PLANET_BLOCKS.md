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
  - Sand: the triangle / pyramid look (next section).
  - Dirt and stone: only a light rounding of the skin's edges and corners.
  - Obsidian: sharp crystal shards, earned by fusing with other obsidian (see "Shapes on the skin"); a lone piece stays a block.

## Sand: the pyramid rule
- (refined) The "pyramid" is a soft mound with a BLUNT top, not a sharp point. It only forms while the sand's top is
  open: the moment something lands on it (dirt, a diamond...), the sand under the load squares back to a flat block
  and the thing rests on that flat top.
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
  - always flat where it meets the ground. Shards follow the footprint and point up or diagonal, never down.
- Only the exposed tip points; the body behind stays solid mass. The bigger the fused mass, the more shape it earns:
  more shards and facets top and bottom (a small pair keeps a flat footing, a big mass becomes a faceted crystal
  monument).
- A diamond deposit can look like one grand glowing shard cluster, but it still breaks into separate pickup pieces when
  mined and never re-fuses. Since diamond doesn't fuse, its "one shape" is the deposit / vein the generation places;
  the big adjustable hypernerve sculpts that into a grand cluster of bright glowing shards.
- Example the owner likes (rare, rolled by the seed): a blunt sand mound with a single diamond resting on top, tilted,
  glinting from far off; or a dark obsidian piece crowning a pale mound.

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
  never hurt by the ground. Elsewhere the old rule stays (free under 8 m/s). Mech thrust-digging is NOT built yet: it
  needs real side contact with block walls, which comes with caves.
- Note: over the block patch the ship doesn't hit block walls from the side yet (it pops up onto the step); real side
  collisions come with caves.

## Missiles: regular vs super (owner, call)
- Two missiles: the regular one and the super (heavy) one. The super has a BIGGER explosion, a bigger crater and a
  bigger hitbox, in space dogfights too, not only on the ground. On the block ground it already digs bigger (heavy
  20 m vs missile 12 m blast radius). Owner CONFIRMED the space side too (bigger explosion and hitbox in dogfights);
  not built yet, it is the next job when he says go.

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
3. Border camera hand-off.
4. Fog in the four corners only.
5. Support and collapse, then cave blocks, overhangs, arches; merging and leaning rubble; stretch goals last.
