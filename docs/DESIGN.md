# Homelancer — authoritative design (living document)

This file holds the current design rules. When a rule changes, the old one stays here marked **SUPERSEDED**, so
older notes and chats can't be mistaken for the current rule. Build notes are in `V1.2_BUILD.md`, and loading and
budgets are in `PERFORMANCE.md`.

## 1. Loading architecture (keep)
- **Loading order:** BOOT/CORE, then the current star system, then local content. Planet entry loads the current planet, then the current surface sector.
- **What's optional:** distant systems, planets, stations, cities, mechs and big model sets live in content packs (`scripts/packs.gd`). They're never part of the first download.
- **Budgets:**
  - initial transfer ≤ ~18 MB;
  - core pck ≤ ~10 MB;
  - startup GPU textures ≤ 64 MB;
  - one pack ≤ ~3 MB;
  - player ship textures 1024 px, most other models 512 px, shared terrain detail 1024 px.
- **No custom engine build** (it would save 2–3 MB) until a real Samsung report says it's needed.
  The loading screen shows CORE / ENGINE / SYSTEM / READY, with errors, Reload and Copy details.

## 2. Planets in space (game scale, not astronomical)
- **Size:** planets are big and close enough to feel substantial: New Terra has radius 1000, Eden Prime 880.
- **Zones** ("sphere within a sphere"):
  - **Upper-atmosphere glow** (1.12× radius) is visible from far away.
  - **Outer atmosphere** (`Data.ATMO_OUTER` = 1.3× radius): haze thickens, the nose glows (more at speed), a rumble plays, the camera shakes slightly, and the planet pack starts downloading.
  - **Entry sphere** (`Data.ATMO_INNER` = 1.02× radius, from any direction) commits you to the surface. You keep your heading and roughly your speed, and come out over the part of the planet you flew into.
- **Exit:** climb above 2,600 m on the surface. A cloud transition takes you to orbit just outside the outer atmosphere, above the same spot.
- **Warp hazard:**
  - At warp within 1.8× the outer atmosphere you get **PLANETARY MASS DETECTED / DROP WARP**.
  - Reaching the outer atmosphere at warp **destroys the ship** (you're towed to the station).
  - Autopilot never warps through an atmosphere.

## 3. Surface sectors
- **Shape:** a planet is a grid of flat sectors, 1×1 (moon), 2×2 or 3×3. They wrap like a torus, Pac-Man style. Only one sector is loaded at a time.
- **SUPERSEDED (Sept 30):** ~~a storm or cloud transition on every sector border.~~
- **NEW:** normal borders are **seamless**.
  - The ground is continuous across every border, including the wrap; the step is measured at 0.00 m.
  - The next sector is built a few rows per frame while you approach (within 1.6 km of an edge).
  - Crossing just continues the ground. Nearby ships, shots and loot come along, and the sky and fog colours drift to the new biome over 3 s.
  - A quick cloud pass is used only if you get there before the next sector is ready.
- **Wrap corner:** one cloud bank sits on the planet's wrap corner, the single point where east/west and north/south wrapping meet. Because of the wrap it shows up as pieces in up to four corners.
  - It's cheap: 46 billboards in one MultiMesh, plus a screen haze near the player.
  - It's tinted by the biome: dust, sand, snow, ash or mist.
- **Look:** biomes blend across borders. The ground texture and bump detail are tiled in world space. The red canyon, mountains, ocean, city and other sectors are in `scripts/surface.gd`.

## 4. Ship rules
- **SUPERSEDED (Sept 30):** ~~warp requires a complete stop.~~
- **NEW warp:**
  - The drive **spools for 5 s while you keep flying**: thrust, steer, run.
  - During the spool you see a bright energy bulge behind the ship, particles, a rising sound and a 5-4-3-2-1 countdown.
  - Then **WARP** and the ship shoots forward. Tap WARP during the spool to cancel.
  - **Weapons lock** from the start of the spool until you drop out. You can't fire guns, missiles or mines.
  - **Enemies see the charge.** Hostiles within 1.6 km turn on you, fly 40 % faster during the spool, and may call you.
  - The warp drive doesn't work inside an atmosphere.
- **Engine kill** keeps drift and momentum while the nose turns freely. It's allowed during the spool, not during warp.
- **Ships fly forward** (thrust, boost, engine-kill drift, warp). They can't side-dash or reverse-boost.

## 5. Mech rules (next phase)
- **No warp.** Boost works in any direction: stick direction + BOOST gives forward, back, left, right or a diagonal.
  The direction sectors are forgiving for touch.
- **Animation:** upright at idle, slight lean moving forward, a stronger lean when boosting, and the body reacts to back and side boosts. A small set of poses, blended.
- **Ship ↔ mech transformation:** about 3 s, with M / S controls. The pose folds, panels lock and an energy flash covers the swap. The sound is four beats, *clack, chunk, lock, thoom*.
- **Damage maps between forms:** left wing = left arm, right wing = right arm, hull = core. Transforming doesn't repair anything.

## 6. Damage display
- **Three sections:** LEFT, CORE and RIGHT for every unit (`scripts/sections.gd`). A lost side hides that part and disables its weapon.
- **Circular status icon** (top, left of the status bars):
  - It's split like a "Y" into HULL (top wedge, between the arms), LEFT and RIGHT. A ship or mech silhouette sits on top.
  - Colours: green, yellow, red, and dark grey when destroyed.
  - It adds to the hull bars and doesn't replace them.

## 7. Travel hierarchy (planned)
| Tier | What | Notes |
|---|---|---|
| Normal flight | local maneuvering | |
| Thrust / boost | fast local movement | |
| **Spaceway** | fast travel across an inhabited system | rings and lane markers, station ↔ planet ↔ gate; a freeway, not a teleport |
| **Warp** | the ship's own high-speed travel | 5 s spool, weapons locked, deadly near planets |
| **Warp gate** | built, system to system | faction architecture; the gate is the loading boundary |
| **Jump gate** | natural corridor between systems | nebula vortex, gravitational distortion; discovered, sometimes hidden or unstable; Homelancer's own look, not Freelancer's |
| **Rift gate** | extreme long-distance travel | rare, important, like controlled spacetime rupture |
| Planet entry | space → surface game area | |
| Docking | space → station, city or interior | |
The current "Aquila / Solara Jump Gate" objects are technically warp gates (built rings). They'll be renamed when the travel data model lands.

## 8. Galaxy map and identity (planned)
- **Look:** a white background with blues (pale, sky, medium, deep, navy accents) and no outer glow, like a technical blueprint or constellation.
- **Panoramic:** you look *through* the network as if with the ship's sensors. Pan left and right (and a little up and down), select a system, then zoom or expand it.
- **Levels:**
  - The galactic level shows systems, connections, territories and rift routes.
  - An expanded system shows planets, stations, spaceways, warp gates, jump phenomena and destinations.
- **The map is data only.** A node is just id, name, position, faction, connections, discovery state and type. 1,000 systems on the map doesn't mean loading 1,000 systems.
- **Startup screen:** the same white-and-blue network slowly pans, the HOMELANCER letters resolve in, then a strong START.
- **Creator space (idea only, not approved):** a white abstract world of blue networks, for simulation, training or system construction. Kept here; nothing to build until it's approved.

## 9. Generic enemy pilots (Job O)
- **Hierarchy:** every patrol is led by a NAMED squad leader (Scar Jackal, Ember Wraith, Iron Revenant, Frost Banshee;
  bosses Shade and Hoard above them). The other ships and mechs in the group are GENERIC pilots AX-01..06 (Standard,
  Recon, Desert, Arctic, Jungle, Elite) "in that leader's wing". Named leaders keep their portraits, lines and hails.
- **Two portrait states:** NORMAL (intact mask) above 50 % total health, DAMAGED (cracked mask) at or below 50 %.
  The switch is latched for the encounter, so it never flickers around 50 %.
- **Chatter** on the same radio window, 3.5 s lines: target acquired, taking fire, shields failing, wing / arm damaged,
  regroup, retreat (alone and below 25 %: falls back for 6 s), missile incoming, leader down, reinforcements, enemy
  transforming, enemy entering warp, critical damage. A generic line never cuts off a named leader mid-sentence.
- **Loading:** portraits are the `enemies` pack (0.2 MB), fetched in the background after start. Until it's there,
  the radio shows the waveform instead of a face.

## 10. Capital city prototype (Job O) — review before building more
- **Built with Godot primitives** (no Blender in this environment): `scripts/city.gd`. Proves scale, connections,
  gameplay and performance, not final art.
- **Modular grid:** 40 m cells. Every elevated road / platform surface is at 20 m; every road and platform connection
  is 24 m wide (2 mech lanes of 12 m) with 3 m parapets. 17.5 m clear under decks, 15 m under the mega bridge's truss.
  Mechs are 11 m tall and 6.6 m wide: one per lane, two abreast per road, groups pass underneath.
  Pedestrian stairs are 4 m wide and separate (too narrow for a mech).
- **Kit (8 modules):** 01 straight road · 02 four-way intersection · 03 merge / on-ramp (2×4 cells, ramp from the
  plaza) · 04 mega bridge (1×3, 120 m span) · 05 square platform · 06 rectangular platform · 07 stair bridge ·
  08 B-01 command tower.
- **B-01 is the first Blender-built asset (Job R).** Built on the owner's laptop in Blender from the blueprint and
  exported as `B01_tower_textured_v2.glb` (source kept in `art/models/`): ONE mesh, 1,048 triangles, UV-mapped, with
  its own baked colour, normal (bump), roughness/metal and glow maps. `tools/city/bake_glb.py in.glb out.glb 2.0`
  scales it to game metres (77 × 61 m foot, 119 m to the mast tips) and strips the embedded images; the four maps
  ship as separate files (colour + normal 1024 px, the other two 512 px). All of it is in the `city` pack. One draw
  call. Its front faces the platform; a deck-height gangway joins it to the platform. Collision is 8 boxes; until
  the pack is in, those boxes are drawn as a plain stand-in. Texture detail is ~4 px per game metre: good from
  flying distance, soft right against a wall.
- **H-01 hangar (second Blender asset).** `H01_hangar_v3.glb`: 100 triangles, 44 × 47 m, 26 m tall, built from one
  isometric concept picture with the saved scripts. Placed on the plaza west of the tower with `City.add_prop()`
  (any further Blender asset goes into `City.PROPS` and is placed the same way). One draw call, one collision box.
- **Pipeline for the next building:** export GLB from Blender → put it in Drive "Home Lancer Models" → bake →
  add to `assets/city/` → place in the block.
- **One test block** in New Terra's city sector, ~1 km north-west of Port Meridian, on its own flattened ground.
  The rest of New Terra keeps all its biomes (the canyon/desert references are ONE biome).
- **One material family:** one shader, five settings (white armour, dark structure, blue glass, amber, road). Panel
  seams, grooves, bolts, vents and window cells come from one 512 px normal map + mask, tiled in world space.
- **Cost:** ~815 instanced parts + the tower, ~11.5k triangles, 14 draw calls up close / 8 at range (small parts drop out past
  1.1 km), 203 collision boxes. `city` pack 0.5 MB (tower maps add ~11 MB GPU while on the planet), +1.8 MB GPU on the planet, nothing in the core download.
- **Not done on purpose:** no more buildings, no hangar/comms/defence modules, no villain art. Waiting for review.

## 12. Owner requests, Oct 1 voice call
**BUILT in Job P:** default cruise (centred stick = 55 % speed; full back = stop and hold; autopilot stops on arrival),
full loops, STOP removed / TRANSFORM in its spot, cockpit view with the owner's cockpit art (cockpit pack, 0.1 MB) +
ring crosshair, heading tape, SPD and ALT/RNG bars, radar on the centre dash screen; side-screen comms (enemy left,
friendly right, both at once, line under the face on white glass, END on calls you placed); comms console from LOG or
by tapping a screen (contacts — only in-system ones answer —, chat log, TYPE, VOICE).
**BUILT in Job Q:** cockpit art 1.3x bigger and lower; free-look (the aim stick turns your head up to ~29 deg left/right,
~13 deg up/down, the cockpit slides the other way) with the crosshair on the nose; the radar is a button (tap = map;
tap empty map space = your own waypoint; SET COURSE flies there); sticks only grab in the bottom corners; town
buildings are solid; start screen = the owner's white network picture panning; galaxy map: the front system nearest
the middle lights up with an outline + its name, the network picture as a far layer; hangar ship inspector (tap the
ship or VIEW: drag to turn, pinch/scroll to zoom, full stats).
**Still planned:** missions + capture, dynamic music, Kokoro voices, new ship models, 360-degree panorama rooms
(hangar etc., owner to supply panoramas), a character in the hangar, scanning other ships' loadouts, more city assets.

**Flight controls**
- **Full loops:** remove the pitch cap so the ship can loop continuously over the top and under; roll follows so
  upside-down doesn't feel flipped. Check it in mech form too.
- **Default cruise:** a centred left stick holds a default cruise speed (Freelancer style). Push = faster, pull = slower
  or reverse. It no longer slows to a stop.
- **STOP button removed.** The TRANSFORM button (MECH / SHIP) takes its place: top-left, second row, beside WARP.
  The MECH pill in the centre row goes away.

**Missions (Freelancer-style)**
- **Mission board, two types:** SEEK AND DESTROY (clear every wave) and BOUNTY (one wave hides a named face).
- **Waypoints:** taking a mission spawns a waypoint. Arriving spawns a wave of 10–15 enemies. Clearing it lights the
  next waypoint. Each mission sets its own wave count, wave size, and whether a bounty face is in it.
- **Bounty targets are the named faces** (Scar Jackal etc.); the generic helmet pilots are the escort.
- **Capture, not kill:** wear a named target down and force a surrender. Turn them in for ransom.
  Delivered to a station they escape after ~30 min; to a planet, ~60 min. Then they're back on the board, so
  the bounty cycle keeps turning.

**Interface**
- **Radar:** tap it to open the map; tap the map to set your own waypoint.
- **Cockpit view toggle:** one button goes into the cockpit, tap again for third person. The owner will make a cockpit
  overlay image (PNG, transparent glass, landscape phone size). Chosen: `art/cockpit/cockpit_B.png` (wider glass);
  `cockpit_A.png` is the spare. The dashboard screens are blank on purpose: the game draws radar, weapons and
  shield/hull on them (concept: `art/reference/cockpit_hud_concept.png`).
- **Cockpit view crosshair:** like the concept image: a circle reticle with a centre dot, a heading tape across the
  top (240 · 250 · 260 …), SPEED and ALTITUDE bars either side of the reticle.
- **Comms redesign: side holo screens** (replaces the bottom call panel, so it stops covering the view):
  - Screens slide in from the sides: **enemies on the LEFT, friendlies on the RIGHT**. Two people can talk at once
    (for example an enemy taunt and a friendly reply).
  - Each screen: the portrait, with the line written UNDER it on a white, see-through panel, so you still see the fight.
  - Tap to pull up the comms console; tap again and it drops back down. It holds the chat log (what's been said) and
    a box to type a message.
  - Calling works like Metal Gear's codec, but with a CONTACT LIST instead of a frequency number. You can only call
    someone who is in the same star system.
- **Dynamic music:** the owner has 28 tracks (WAV). They play only for big moments — entering faction space, missions,
  epic and boss fights — with fades between moods. Convert to OGG and put them in a music pack. Needs the files and a
  rough mood for each.
- **Character voices:** real per-character voices made ahead of time with Kokoro (free, 54 voices, commercial use OK),
  shipped as a voices pack. Live speech isn't possible without a server.

**Galaxy map — immersive (replaces the flat look in §8)**
- **Style:** the white background with blue nodes and lines (reference: `art/reference/galaxy_map_white_network.png`).
- **You are INSIDE it:** the network surrounds you like flying in space. The points are real 3D nodes close around the
  viewer, not a far-away skybox, so they move with parallax as you look around. The reference image can be a faint
  far backdrop behind them.
- **Tap a star:** it highlights, shows its name, and lights the routes branching out to the next systems.
- **Zoom in:** a system zooms in and opens up as its own blueprint.
- **Story frame (idea):** the game may begin in this white "waiting room" (the Creator space in §8). A cinematic takes
  you from the white into your first system. The same white space could be the final battle: flying in to fight the
  Creator.

## 13. Ship models to replace (owner will make new ones)
| Priority | In game as | Now | Notes |
|---|---|---|---|
| 1 | Ranger (player ship #2, bought at the hub) | NO model: boxes built in code | player ship: textures up to 1024 px |
| 2 | Raider (Solara enemies, Shade's side) | enemy_fleet.glb, 6k tris, shared with Corsair | 512 px textures |
| 3 | Corsair (Vega enemies, Hoard's side) | same enemy_fleet.glb as Raider | needs its own look |
| 4 | Cargo hauler (traffic) | cargo_ship.glb, 10k tris | keep or replace |
| — | Cadet (starter), Lancer, carrier, station, mechs | real models | keep |
Every new ship: GLB, nose clearly at the front, left/right symmetric (wings split automatically for damage),
about 10–30k triangles.

## 14. Implementation order (from the master spec)
1. Optimized public build (Job L) ✔
2. Real Samsung loading test — **waiting for the report** (Copy details)
3. Content-pack streaming ✔
4. Planet entry ✔ (two spheres, Job M)
5. Seamless sector borders ✔ (Job M)
6. Corner cloud ✔ (Job M)
7. Warp rule update ✔ (Job M)
8. Mech directional boost ✔ (Job N): stick + BOOST, 8 forgiving sectors, hold to keep pushing; no warp, no engine kill
9. Ship/mech damage icon ✔ (ship Job M, mech silhouette Job N)
10. Transformation prototype ✔ (Job N): MECH/SHIP pill or T key. 3 s: the old form tucks/compresses, an energy flash
    covers the swap at 1.4 s, the new form unfolds and locks at 3 s; the 4-beat sound (`transform`) lines up. Weapons are
    locked and warp is refused while transforming. Damage carries over and isn't repaired. The player mech is the
    black/gold mech (mechs pack); the camera sits higher and further back in mech form.
11. Basic travel-system data model ✔ (Job N): `scripts/galaxy.gd`. 56 systems in 6 regions, 81 links (warp, jump and
    rift gates), spaceways for Solara/Vega. Data only; Solara and Vega are flyable. The existing gates are renamed
    "warp gates".
12. Star-map UI prototype ✔ (Job N): `scripts/galaxymap.gd`, opened with MAP then GALAXY. It's panoramic: drag to look
    around, tap a system, EXPAND for its blueprint (orbits, bodies, warp gate, spaceways, routes out). White and blues
    only. The route test checks that opening it loads nothing (+0 resources, packs untouched).
- Startup screen ✔ (Job N): white field, the blue network panning, the HOMELANCER letters resolving one by one, then START.
  The web loading page now uses the same white and blue.

## 14. NPC chat brain (built, no AI model)

`scripts/brain.gd`. Type to a contact in the comms console and they answer in character.
- **Persona** per contact (`Brain.PERSONAS`): who they are, temper, greed, warmth, what they know.
- **Understanding:** the typed line becomes an intent (greet, help, place, work, trade, who, status, thanks, apology,
  insult, threat, surrender, bribe, bye) plus a topic (station, gate, belt, nebula, planet, raiders, corsairs).
- **Memory** (`GS.memory`, this session): talks, trust, insults, threats. Trust changes the tone (warm / cool / cold).
- **Context:** system, hostiles near you, hull, kills.
- **Reply step is swappable:** `Brain.responder` can be pointed at a relay + language model later; `Brain.payload()`
  is what it would send (persona, memory, context, the pilot's line). No key in the game. Offline always works.
- **Not yet:** replies change words only, not gameplay (no real tribute payment, no calling off attackers), memory is
  not saved between sessions, generic pilots cannot be typed to.

## 15. Galaxy foundation: the checkerboard (owner + Grok notes, Oct 1) — PLAN, the next galaxy job

Source: the end of the Drive doc "HOMELANCER — Master Game + Galaxy Bible" (Sun & Star Map), plus the owner's voice notes.
This replaces the clustered node network of §7–8 as the foundation. Marked EARLY where the owner said so.

**The board**
- The star map is a checkerboard grid. Each tile is one star system. Some tiles are VOID (no star).
- Tiles are named like a board: column letter + row number (A1 .. e.g. A12).
- **Full Pac-Man wrap on every edge.** Fly off the bottom of A12 and you arrive at the top of A1, same column; the same
  left to right. No walls anywhere. This is the wrap the planet surface tiles already use, applied to the whole board.
- Tile to tile takes about an hour of plain flying. Warp speed tiers shorten it.
- Jump gates link system A to system B. Some systems have NO gate: warp is the only way in.
- Beyond the grid is the void buffer, about an hour out.

**Each system**
- Its own painted 360 sky (BUILT, see below).
- A sun: a billboard glow that always faces the player, held in place by an invisible sphere. It sits FAR out, near the
  edge of the system but NOT on the border (space remains beyond it). It looks bigger only because you get closer; cap the
  size so it never looks cartoon-huge at normal range. The flare blooms harder the closer and more head-on you fly.
  Touching the sphere destroys the ship (exact kill distance to tune in game). The sun is separate from the sky picture.
- EARLY: with a heat-shield upgrade the sun stops killing you and becomes a place: entering loads a small, self-looping
  magma tile (wavy heat haze, rolling magma floor, yellow atmosphere glow = your heat shield working). Light on content.

**The void (EARLY)**
- Two opposite hidden systems (spooky/shadow and beautiful "god" system), in opposite corners or anywhere in void tiles.
- Breadcrumbs: nebula gets thicker the closer you are; golden ring-shaped formations replace asteroids near secrets.

**Build order**
1. Grid data: tiles, void tiles, wrap, gate links (replaces Galaxy.CLUSTERS); galaxy map draws the board.
2. Sun: sphere + billboard, bloom by angle and distance, kill on contact. ✔ built
3. Travel between neighbouring tiles by warp, with the wrap.
4. Void breadcrumbs and the hidden systems.
5. Sun interior (needs the heat shield item).

**BUILT: the sun (Job T).** A sphere 5.5x a planet (5,500 m radius) 40,000 m from the system centre, opposite the gate side (its picture is drawn at most 11 km away, scaled, so the camera range stays short),
with a bright core and a billboard glow on it. The view blooms the closer and more head-on you look at it and clears
when you look away. Inside 1.5 radii: HEAT WARNING. Flying into the sphere at normal speed ENTERS THE STAR (at warp it is a crash). Numbers are `Data.SUN_*`, easy to tune.

**BUILT: the star's surface (Job T).** The sun is a planet you can enter: `Surface.PLANETS["<system>_sun"]`, one small
tile of the new "sun" biome (glowing magma sea, dark crust islands, yellow sky and haze) that wraps onto itself. Nothing
on it yet. Without a heat shield the heat takes the shields in 3 s, then the hull in 8 s (`Data.SUN_SHIELD_SECS`,
`SUN_HULL_SECS`); shield cells and repairs do not work there; the ship is lost and towed home. With `GS.heat_shield`
(the special item: nothing sells it yet) there is no damage and the HUD shows HEAT SHIELD HOLDING. Climbing past the
ceiling returns you to space just outside the star's heat zone.

**BUILT now: a painted sky per system.** `assets/sky/<system>.jpg` (the `sky` pack, 2048 x 1024, ~8 MB GPU each, only the
current system's is loaded). Solara = the owner's magenta nebula, Vega = the teal and coral one; the existing warp gate
jumps between them. The code-made star sky shows until the pack arrives. Tools: `tools/sky/portrait_to_pano.py` (portrait
picture -> 360) then `tools/sky/fix_pano.py` (poles).

## 16. Station interiors: panorama rooms (owner + Grok "Design Notes 1-4", Oct 2) — first build

`scripts/rooms.gd`, pictures in the `rooms` pack (`assets/rooms/<id>.jpg`, ~0.43 MB each, ~6 MB GPU, one loaded at a time).
- **A room is one strip:** the owner's 16:9 picture has the FRONT view on the top half and the BACK view on the bottom
  half; `tools/rooms/make_strip.py in.png out.jpg --preview joins.png` joins them into ONE long strip, front | bridge | back | bridge (3664 x 464). The two
  views are separate paintings, so each join gets a 160 px bridge: lighting matched, each side continued by its
  mirror image, cut where the two differ least, and blended (owner-approved; mirrored lettering at a join is accepted).
  Pictures WITHOUT the split (information sheets) are not rooms.
- **Looking around:** drag sideways, it scrolls forever (wraps); drag up/down tilts a little. No floor or ceiling.
- **Markers:** tap a sign, door or person. Doors zoom in, swap the picture while zoomed, zoom out (no loading screen).
  Dealer signs open the existing dealer screens; their STATION button returns to the room you left.
- **Built for Liberty Hub (Unity):** Main Hub H-01, Docking Bay H-06 (LAUNCH), Mission Center, Trade Market, Unity Bar,
  Hangar (inspect your ship), Apartment A-721. Stations without rooms keep the old hub page. Until the pack arrives the
  old page shows.
- **People:** Cmdr. Vale in the Mission Center answers from the chat brain (§14); other people say a fixed line.
- **Not yet (needs art or a decision):** walking NPC sprites (6 s loops, mirrored), three face stills per character and
  moods, typing/voice to people in rooms, sticks for look/pan, hotspots that pull the view closer, contracts, cargo
  trading, renting the room, marker positions tuned by the owner.

## 17. Intro screen: the looping collage (Oct 2)

The start screen pans slowly through the owner's faction collage and loops for as long as the player waits (one loop
is about 6 minutes at `Title.PAN_SPEED = 14`). The collage is one 16:9 picture, front on top and back on the bottom.
`tools/rooms/make_overlap_strip.py collage.png out.jpg 44 521 537 1.274` joins them the owner's way: at each join the
next view is laid over the previous one for 160 px and faded in with a transparency ramp. No mirroring. (The two
halves have different heights, so the back is scaled and the front's top trimmed until the trooper lines meet.)
It is the small `intro` pack (`assets/intro/title_collage.jpg`, 2920 x 400), requested at once; the old white network
strip from the core download shows for the first moment and the collage fades in over it. The logo and START sit on a
soft dark band. (The white-network intro strip and the white secret system were tried and discarded.)

## 18. Station rooms: look stick + green "ready" (Job Y), and the arm tablet (PLAN, owner voice notes Oct 2)

**Built (Job Y):** a LOOK stick bottom right in every room (big left-right sweep, gentle up-down; drag still works).
The marker nearest the middle of the view lights up GREEN (same green as docking = ready) and a green button appears
at the bottom: one tap uses it. Tapping a marker directly still works.

**Planned next: the arm tablet (Freelancer-style menu).**
- A button (the tablet on your arm). Push it: the tablet activates and slides out on the LEFT side. Push again: it drops away.
- Smoked glass: tinted enough to read, the room still shows through. You can keep looking around while it is open.
- On it: a map of the station with all rooms highlighted (jump straight to one), the menu, contacts and the call log.
- Markers behind the tablet do NOT light up and cannot be tapped (the tablet is in front); markers in the clear work as usual.
- Calls: your friend list comes with the game. You call them, they call you (also in flight, before docking, and
  during fights: allies, not enemies). Reach = your current star system. Calls guide missions ("dock here, I'll meet
  you") and the caller is then waiting in that room.

## 19. Music by mood (Job Z, owner's 28 tracks)

`scripts/music.gd` (autoload `Music`). Tracks are used by MOOD, not by place (64+ worlds, 28 tracks). The owner's own
descriptions (full guide in Drive: "HOMELANCER — Music Guide"):
- **Homelancer game** = the intro (start screen). **Homelancer game 1** = confusion / puzzles (HELD, no puzzles yet).
- **Spaceways** = relaxed space travel; **Gate of Veranthos** = drifting and flying through space (one pool, "space").
- **Interstellar** = exploration, the search (planet surfaces today).
- **Rift Gate Collapse** = epic, battles and chases. **Bloodwater Corridor** = dark faction territory, high-level danger (Vega today).
- **Void Drift** = unknown areas, lost, alone (nebula, and beyond 9 km from the system centre).
- **Stars Remember Us** = heart moments, self-reflection, calm after a victory (26 s after a won fight; the apartment).
- **Architect Ruins** = spooky exploration / horror missions (SOS on an abandoned carrier or station, underground
  ruins). HELD until those exist. Do not use it as general planet music.
- A random take per mood, the next take when one ends, 2 s cross-fades, MUSIC ON/OFF on the start screen.
- Each track is its own pack (`mus_<id>`, 1.2-2.3 MB, Ogg q1) fetched on first use. Station rooms are quiet for now.
- The owner's MP3s are the masters; the repo holds only the shrunken Ogg copies.

## 20. Jump gate ring, jump rings, station model, sky library, galaxy draft (v1.3a)

- **Jump gate ring.** The owner's Tripo jump gate (`art/models` keeps the spare arch piece as
  `jump_gate_extra_section.glb`) is cut to the ring only, 336,876 -> 5,316 triangles, 512 px maps:
  `assets/structures/jump_gate_ring.glb` (the `structures` pack). Hole along Z, clear opening radius 1.0, drawn at
  `GATE_RING_SCALE` 44. The code-made ring is the stand-in until the pack arrives. Tool: `tools/gate/make_gate.py`.
- **Jump rings.** `space.show_jump_rings()` puts 6 glowing rings behind the gate; the ship flies on through them as
  the warp effect builds (`main.jump`). One shared torus, unshaded additive: nearly free on a phone.
- **Station model.** The owner's wheel station, 473,334 -> 14,900 triangles: `assets/structures/wheel_station.glb`.
  A station wears it when its data has `"model": "wheel_station"` (Liberty Hub does; Vega keeps the old one for a
  second look). Tool: `tools/gate/make_station.py`.
- **Sky library.** `art/sky_library`: 122 seamless skies from the owner's pictures, one per tile and realm plus
  spares. Not in the build; copy one into `assets/sky/<system>.jpg` when its system is built.
- **Galaxy draft.** `docs/galaxy`: the 11 x 11 map (script, tile list, gate list, picture). PLAN, not built.

## 21. The whole map as real systems (v1.3b)

- **One generator.** `tools/galaxy/build_game_data.py` turns the map (`docs/galaxy/*.csv`, made by
  `docs/galaxy/galaxy_draft.py`) into `scripts/galaxy_data.gd`: a tile table and a gate table. `SystemBuilder`
  (`scripts/system_builder.gd`) builds every system from them when the game starts: star, ONE station, ONE planet,
  asteroid field, nebula, patrols, and one gate per link on the map. `Data.SYSTEMS` = the hand-made systems
  (`Data.CORE_SYSTEMS`: Solara, Vega) + all generated ones: 67 systems. Change the map, run both scripts, done.
- **Gates.** `sys["gates"]` lists every gate; `sys["gate"]` is the first. Each gate sits in the direction its
  destination lies on the map. Portal colour = type: green jump, blue warp, purple rift. JUMP uses the nearest gate;
  you arrive at the gate that leads back (`"gate:<from>"`). Solara (tile F3) links to Veranthos; Vega (F2) to Solara.
- **Suns.** Every system has a sun you can fly into (`<id>_sun`, added to `Surface.PLANETS` by `SystemBuilder.suns`).
  Void systems have a small sun (`small_sun`, 35 % size) and a dead planet.
- **Skies.** Each generated system has its own small download, `sky_<id>` (`assets/skies/<id>.jpg`), fetched when
  you arrive. The start-up download does not grow.
- **Planet looks.** `PLANET_LOOKS` in space.gd: 12 types (terran, jungle, ocean, ice, desert, lava, dead, gas, city,
  crystal, toxic, machine), each planet seeded by its own id.
- **Not built yet:** more than one station/planet per system, landing on generated planets (they dock from orbit),
  open-space tiles and edge crossings (turbulence + blur), realms, per-system characters and missions, a flat grid
  galaxy screen (the galaxy screen shows the real systems and links in its old look-around style).
- **Ships (v1.3b, owner).** Enemy ships use the owner's new fighter (piece 3 of the four-ship sheet, 103,998 ->
  3,540 triangles, `assets/ships/enemy/enemy_fleet.glb`); the other three on the sheet were discarded. The Ranger
  (a code-made stand-in) is off sale: the dealer lists Cadet and Lancer. `shipkit.py export --yaw-fit` straightens a
  ship that lies flat but turned at an angle.

## 22. Real planets, docking gate, the owner's player ships (v1.3c)

- **Planet maps.** `assets/worlds/<map>.jpg` (the `worlds` pack, 12 maps + clouds, about 1.4 MB): NASA's public
  planet maps (from github.com/nasa/NASA-3D-Resources, sources kept in `art/planet_maps`), made game-ready by
  `tools/planets/make_worlds.py`. A planet map is equirectangular: 2:1, left edge = right edge, top row = north pole.
  To add a world: drop a 2:1 picture in `art/planet_maps`, add it to `MAPS` in the tool, run it, name it in
  `PLANET_MAPS` (space.gd). No other code changes.
- **One map, many worlds.** `PLANET_MAPS` gives each planet type its maps with a colour tint and saturation; a planet
  picks a variant, a longitude roll and a mirror from its own id. So 12 maps cover every system.
- **Fixed day and night.** The sun and planet never move, so `PLANET_SHADER` lights the map with one dot product
  against a fixed sun direction (no lights). The atmosphere glows inside the edge of the disc on the lit side; the
  outer haze shell is thin (1.035 r, was 1.12: the glass ball). Worlds with weather get a slow cloud sphere.
  The code-made texture is the stand-in until the pack arrives.
- **Planet docking gate.** At the dock point: the owner's ring with four arch pieces round it (the spare piece of the
  jump gate model, `assets/structures/dock_arch.glb`, 2,264 triangles each), feet toward the planet.
- **Player ships.** Cadet, Ranger and Lancer are the owner's three ships with the sheet's cannons mounted
  (`tools/shipkit/make_fleet3.py`): Cadet two on top; Ranger a long cannon on top and one on each wing (3 guns);
  Lancer a long cannon on each wing and a short one each side of the nose joining the loose pods (4 guns).
  Spare weapons: `art/models/fleet3_weapon_*.glb`.
- **Transports (owner's sheet of three).** The big one is the carrier (`carrier.glb`), the long thin one the cargo
  hauler (`cargo_ship.glb`), the middle one a second hauler (`freighter.glb`, key `fleet2`); traffic uses both haulers.
- **Corsair ship (owner's lopsided ship, mirrored).** `tools/shipkit/mirror_ship.py` cuts a ship in half along its
  length and mirrors each half: two symmetrical ships. The one with two tall fins is the Corsair
  (`assets/ships/enemy/corsair.glb`, key `enemy2`); the other is kept in `art/models/mirror_ship_low.glb`.
- **Tankers (v1.3d).** From the owner's second transport sheet (two of its ships): the long thin one is a liquid
  tanker on the traffic run (`tanker.glb`, key `fleet3`); the big one holds station by each planet (`big_tanker.glb`,
  key `tanker`). Water, fuel and other liquids.
- **Desktop keyboard + mouse controls (v1.4f, Job J).** Freelancer-style scheme for desktop players only
  (`scripts/controls.gd`, Settings screen `scripts/settings.gd`, numbers and default keys in the Job J block of
  `scripts/data.gd`). Control mode is auto-detected (touch device -> touch, otherwise keyboard + mouse) with an
  Auto / Touch / Keyboard + mouse override. Right-click fires (owner correction), left-click selects, left-drag steers,
  mouse flight on Space. Bindings and mode are stored in a new file `user://settings.cfg` (section `controls`).
  Phone touch controls are unchanged.
- **Jump-gate docking + warp tunnel (v1.4g, Job K).** In range of a gate the HUD gate prompt (or the Dock key F3)
  docks you to it: the docking screen (`scripts/gatedock.gd`) names the destination system with ACTIVATE JUMP and
  UNDOCK. Activate: layered star streaks drawn in code, shake and blur build over 0.5 s while the ship pushes through
  the gate, hold at full while the next system loads, then snap clear in 0.3 s as the ship is launched out. All gate
  kinds use it for now. Reduced motion (Settings) swaps the tunnel for a short fade (`settings.cfg`, section
  `effects`, key `reduced`). Numbers in the Job K block of `scripts/data.gd`. Nothing is saved mid-jump.
- **Collision damage (v1.4h, Job L).** The player ship takes hull damage when it hits something solid: asteroids,
  the ground (planet surface, or a planet with no surface), town/city buildings and the space station. Damage =
  (impact speed into the surface - 8 m/s) x 0.9, straight to the core hull; below 8 m/s contact is free. 0.5 s grace
  window after a hit. Flash, shake and sound scale with the hit; zero hull = the normal "ship disabled" flow.
  Existing collision shapes and responses (asteroid/station bounce, ground/building stop) are unchanged. Numbers in
  the Job L block of `scripts/data.gd`. Enemy ships don't take collision damage yet.
- **v1.3e (owner's third transport sheet).** The long skinny tanker is gone; the tanker on the traffic run is the
  new one (`tanker.glb`, 9,282 triangles). Loot pods are the owner's cargo containers (`assets/cargo/crate_a/b/c.glb`,
  about 300 triangles each). The other cargo pieces are kept in `art/models/cargo/`.
- **Hauler (v1.3e).** The owner's cargo ship, buyable (2,500 cr, toughest hull, slow). The box hanging under its
  nose was cut away. Loot pods: `crate_a` (single emblem crate) and `crate_c` (four-crate block) come from its sheet.
- **Bulk Freighter (v1.3f).** The owner's big cargo ship, buyable (6,000 cr, key `bulk`). Its loose guns and
  containers are spares in `art/models/cargo/freighter_part_*.glb`. The dealer list now scrolls.
- **Frame Freighter (v1.3f).** The Bulk Freighter with its crates removed, leaving the cargo frame (key
  `bulk_empty`, 4,500 cr). How it was cut: `tools/shipkit/empty_cargo.md`. Carrying chosen crates in the frame is
  not built yet.
- **Every catalog planet and station (placeholders).** `tools/galaxy/build_game_data.py` now holds the full
  contents of each system from the Star System Catalog v2 (`SYS`): 172 planets and 102 stations across the 67 systems
  (count sheet: `docs/galaxy/system_contents.csv`). The first planet and station of a system are the dockable ones;
  the rest are `GalaxyData.EXTRAS` -> `sys["more_planets"]` / `sys["more_stations"]`, built by `space._build_extras()`
  as landmarks: visible, solid, targetable, on the system map, reachable by GO TO, no docking yet. Planets use the
  NASA solar-system maps with their type's temporary tint; stations are a small stand-in in the faction colour.


## 23. Lead box, missile locks and dodging (Job M, v1.4j)
All numbers are in the "Job M" block of `scripts/data.gd`. Phone buttons are unchanged.

- **Cadet** model turned round (yaw 180 in `ShipFactory.GLB`): the nose now points away from the chase camera.
- **Lead box**: a small box ahead of the targeted enemy (`space.lead_point`). Put the reticle on it and the guns
  hit; it turns green when you are on it. It uses the enemy's speed relative to yours.
- **Missile locks**: keep the target in front (15 degree cone, 800 m). One lock every 0.5 s, shown as pips over the
  target and "LOCK 2/3" on the button. Press the button to fire one missile per lock; no lock still fires one.
- **Three missile types**: HEAVY (one lock, at least 60 % of the target's hull), the **Triple Rack** on the LIGHT
  button (3 locks, comes with every ship) and the **Swarm Rack** (5 locks, each missile 60 % strength, 1800 cr at
  Equipment). Racks are owned once and swapped for free. `GS.rack`, `GS.owned_racks` are new fields with defaults.
- **Dodging**: a missile inside 250 m loses its lock when the target moves sideways across its path faster than
  1.15 x its normal top speed. For the player that means a boost across the missile's path, or an engine-kill slide
  after a boost. Boosting too early just makes it follow. Enemies try a side-boost 30 % of the time.
- **Enemy missiles**: Corsairs and Assault Mechs fire one every 12-20 s inside 600 m (22 damage). The HUD flashes
  "MISSILE 320 m" and then "BOOST SIDEWAYS NOW". Raiders carry none, so the first system stays gentle.
- SIMPLEST CHOICES (open to change): all locks go on one target; racks are a one-time purchase, not ammo types;
  version v1.4j was used because this job was built first, so the panorama jobs move to v1.4k and v1.4l.


## 24. Concept-art map and Lockon's signature attack (Job N, v1.4k)
Follows the owner's Concept-Art-First standard: Bible-locked lore, then concept sheets, then exteriors, interiors,
characters. Nothing is drawn or invented in the game where the art does not exist yet.

- **Art map**: `tools/art/build_art_refs.py` holds one table and writes `scripts/art_refs.gd` and `docs/ART_MAP.md`.
  Each station gets `art` (exterior + eight hub rooms: main hub, shipyard, dealer, weapons dealer, supplies, bar,
  mission board, bedroom); each planet gets `art` (concept sheet, locations with aerial and first-person views,
  scenes). `ArtRefs.apply()` writes them onto the system data by name; `ArtRefs.missing()` lists what has no art.
- The pictures stay in Drive (concept-art). The game stores the file name and Drive id only. Turning a picture into
  a walkable room strip still needs the picture file itself (homelancer-panorama skill).
- Mapped: Aurelion (3 stations x exterior + 8 rooms = 27 pictures; Aurelion Prime A01-A09; Alisa temple throne).
  No art yet: Scavaris (Scavaris, Husk, Salvage Hulk) and Crystara (Crystara, Geode, Prism, Crystal Refinery).
- Elyza guard rules ride on the system (`art_guards`): paladin or Dark Knight armor, mixed gunblade loadouts, no
  recycled characters, no guards in the bedroom.
- **Signature attacks**: `Data.SIGNATURES` (block "Job N"). A unit with `"signature"` in its ENEMIES entry fires it in
  place of the plain missile. Lockon (Cybermorph): three charcoal darts with crimson slits, red needle trail with
  dotted hex sparks, one kink when the lock hardens (inside the dodge range), impact = punch, then a cyan-white
  bloom, a red hex-shard ring and a pulsing lock-brand on the hull for 4 s. Grey machine debris only.
- SIMPLEST CHOICES: "Elyria station hubs" was read as the three Aurelion stations (the Drive folder Planets/Elyria is
  empty). Lockon is in the data but in no system: there is no Lockon sheet or model, so the prow-split launch is a
  data note and the tests use the existing mech body as a stand-in.


## 25. Trade lanes, a surface on every planet, faction music, combat feel, Aurelion hub (Job O, v1.4l)
All numbers are in the "Job O" block of `scripts/data.gd`.

- **Trade lanes** (Freelancer style, `space.gd` "trade lanes"): rows of four-bracket rings inside one system, from the
  main station to the main planet and to each jump gate (a run is skipped when it is short or would cross the sun
  or a planet). Rings come in pairs, one above the other: the upper row runs out, the lower row runs back. The
  green lamp marks the mouth. Near a ring the prompt reads TRADE LANE; docking locks controls and weapons and
  carries the ship ring to ring at 650 m/s with a ramp up and a slow-down before the last ring. The warp look is an
  energy tunnel that rides ON THE SHIP (a shader on a short tube parented to the ship) plus a glow and splash at
  each ring: there is no tube between rings. All rings of a system are one MultiMesh (one draw call). Tap the
  prompt again to leave part-way. Nothing is solid while riding. NOT BUILT: shooting a bracket to disrupt a lane.
- **A surface on every planet**: `SystemBuilder.planets()` gives every planet without one a single tile that wraps
  onto itself (the same wrap the stars use, so the ground meets itself at the edges). The biome follows the planet
  type (`Data.PLANET_BIOME`; new biomes barren, clouds, crystal, toxic, machine). The system's other planets can be
  entered too; climbing out returns you beside that planet (`orbit:<tile>:<planet id>`).
- **Music by faction** (owner): in flight the track is the one for the faction whose space you are in
  (`Music.FACTION_TRACK`, 13 factions, one track each) and stays until you cross into another faction's space.
  Battle music still cuts in during a fight. "Stars Remember Us" (the love song) no longer plays after a kill or in
  the apartment: it is HELD for later, with the ruins set and the puzzle track. SUPERSEDES the mood list in §19 for
  flight.
- **Guns forward**: the Cadet and Ranger models were built tail-first, so their cannons pointed backwards. Both are
  rebuilt nose-first (`make_fleet3.py`), and the Cadet's 180 degree turn from v1.4j is removed. The Lancer was
  already right.
- **Lead box**: red, Freelancer style, shown for any targeted enemy on screen (was gold and short range).
- **Missiles**: a white ribbon trail (flat strip, bright at the missile, wider and fainter toward the end, 2.2 s
  long) and a weaving path that straightens near the target. The Six Rack (6 locks) comes fitted; every ship
  carries twice the light missiles.
- **FIRE button** (new, in the empty corner beside THRUST): tap = guns fire nonstop, tap again = stop.
- **Collisions** take the shield first, then the hull (SUPERSEDES Job L's "straight to the hull").
- **Explosions**: `_blast()` = flash, fireball cloud, shock ring, debris, later pops. Used when a wing is lost (on
  that side), when any unit dies, and when the player's ship is destroyed (both sides and the core, ship hidden).
- **Aurelion Citadel hub**: eight rooms from the owner's Drive pictures (pack `rooms_aurelion`). These pictures are
  one view each, not front + back, so `"single": true` rooms pan inside the picture and stop at its edges.
  The other two Aurelion stations and all other hubs still use the plain station menu.


## 26. Spread-out planets, flat fog-of-war galaxy map, radar zoom, first person in a room (Job P, v1.4m)
Numbers: the "Job P" block of `scripts/data.gd` (and the PH_ planet constants).

- **Planets farther apart**: catalog planets now start 4.3 km from the system centre and step out 1.9 km each, with
  at least 900 m of open space between any two planets (`PH_CLEARANCE`; stations keep the old 260 m,
  `PH_STATION_CLEARANCE`).
- **Bigger small print**: HUD and system-map text under 17 px gains 2 px and is never under 13 px; room markers,
  the title line and the galaxy map use larger sizes too.
- **Missiles**: firing one turns the target and every hostile within 700 m of it on you. A missile whose target is
  gone picks the nearest hostile within 900 m (not after it was dodged).
- **Title screen**: MUSIC and SETTINGS are two big grey buttons under START (they were small, top right).
- **Galaxy map** (`galaxymap.gd`, `_draw_flat`): opens as the flat 11 x 11 chart of the owner's map: each system in
  its tile (A-K, 1-11), each gate a line (jump solid, warp long dashes, rift short dashes). FOG OF WAR: systems you
  have been to are lit in their faction colour with their name; systems one gate beyond show as "?" contacts;
  everything else is dark. "3D VIEW" switches to the old look-around view. SUPERSEDES the look-around as the default.
- **Radar**: 1.6 km near things; when the nearest place is farther than that it zooms out until the station, planets
  and gates all fit (the range is printed under it), and shows the other planets and the sun too.
- **Rooms**: MAIN HUB and LAUNCH buttons on the top bar of every room.
- **Dealer screens**: Equipment, Repair and Ship Dealer show a room of that station behind the lists, dimmed
  (`Rooms.SCREEN_BG`).
- **First person in a room (TRIAL)**: `scripts/npc.gd`. Deck Marshal Orrin in Liberty Hub's main hub is the rigged
  "future soldier" model drawn live in a small transparent viewport and placed over the room picture. He strolls
  left and right, is waist-up when close and thigh-up (smaller) when he walks back, speaks first when you look his
  way, and waves or nods and answers when tapped. Gestures are posed on the bones, so any humanoid rig works.
  Pack `npc` (3 MB). NOT DONE YET, waiting on the owner's verdict: more people, a standing dealer on the
  Equipment / Repair screens, typed or spoken chat with them.

## 27. Split comms console, big racks, one-tap restock and repair, burst thrust (Job Q, v1.4n)

All numbers are in the "Job Q" block of `scripts/data.gd`.

- **Comms console (LOG).** No longer a block in the middle of the screen. It is two panels at the screen
  edges: CONTACTS flush against the right edge (face against the edge, name beside it, tap a row to call) and
  the message LOG flush against the left edge, with TYPE and VOICE under it. The middle stays clear, and
  touching the middle no longer closes the console: you keep flying. LOG closes it, or it tucks itself away after
  `COMMS_IDLE_CLOSE` seconds. A caller's screen floats in next to the panel (`hud.side_rect`).
  The owner's note said both "faces to the right" and "the right is just the log"; we took contacts right, log left.
- **Racks.** Every ship carries `MISSILE_LOAD` (100) light and `HEAVY_LOAD` (50) heavy missiles. The heavy does
  85 % of the target's hull (was 60 %). Prices were cut so a full load is payable: light 10 cr, heavy 50 cr.
- **RESTOCK ALL and REPAIR.** Two buttons at the top of Equipment (and on the Repair page). RESTOCK fills light,
  heavy and mines and bills the total in one tap (`GS.restock_all`); short of credits it loads what you can
  afford. REPAIR restores hull, wings and repair kits, free (`GS.repair_all`). Because these buttons would
  otherwise have nothing to do, **docking no longer refills ammo or repairs the hull by itself**
  (`GS.dock_service` restores shields and energy only). New game and the rescue tug still restore everything.
- **Throttle.** Holding the left stick forward builds gradually (`FORWARD_RATE`) to `FORWARD_MULT` x ship speed
  (Cadet: 100 m/s); letting go settles back to cruise. The autopilot keeps its old top speed.
- **THRUST.** An instant burst at `BURST_MULT` x ship speed (Cadet: 120 m/s) in the stick's direction
  (8 sectors). With the stick centred the burst goes straight UP, in ship form and mech form alike
  (`Space.burst_dir`). Holding the button keeps you moving that way and drains energy as before.

## 28. Build-server test fixes (Job R, v1.4o)

No game change. v1.4m and v1.4n never went live because two route checks failed on GitHub (which runs the test
with no screen: 198 checks) while passing here on a screen (201 checks). Both were test weaknesses:
- the enemy-missile damage check could be hit by a passing raider's guns (27 instead of 22): other enemies are
  now parked while it measures;
- the radar zoom check waited a fixed time: it now waits for the zoom to settle.
From now on every job is also run with `--headless` here before it is packaged.

## 29. GPS-style navigation map and radar (Job S, v1.4p)

All numbers are in the "Job S" block of `scripts/data.gd`. The shared view is `scripts/navgrid.gd` (class
`NavGrid`); the map is `scripts/navmap.gd`; the radar is `hud._radar`.

- **Grid.** World-space lines in three layers: bold major lines, minor lines at a fifth of that, micro-ticks
  (ruler marks along the major lines) at a twenty-fifth. Major lines are always 110 to 550 px apart, so zooming
  in turns minors into majors without a jump (`NavGrid.levels`). A pair of lines is drawn through every planet,
  station, gate and the star, so each sits on a crossing. Coordinates are written where major lines meet the edge.
- **Views.** `NavGrid.orient` = "north" (default, never rotates) or "heading" (you are the arrow at lower-centre,
  the map turns round you). `NavGrid.tilt` = "angled" (26 degree lean with perspective) or "flat". One projection
  (`to_screen`) and its exact inverse (`to_world`) serve drawing, taps and panning in every mode. The choice is
  saved in the settings file, section "nav" (new fields only). Buttons on the map; keys N and B (rebindable); the
  radar follows the same setting. A compass (map) and an N marker (radar rim) always show true north.
- **Zoom and pan.** Pinch, mouse wheel, + / - and FIT; drag to pan in north-up.
- **Shapes.** Polygon circles with straight edges (12 to 20 sides, `NAV_SIDES`): planets and the star are two
  rings of flat facets lit from the upper left with a rim light and a shadow cast on the grid; stations and gates
  are rings with a wall for thickness; rocks, the nebula and ships are faceted too. Orbit paths, the belt and the
  range rings are polygons laid on the map plane.
- **Tap to identify.** `navmap.tap` then `pick` use this frame's projected positions, so they work rotated.
  Brackets mark the selection and `navmap.info(key)` fills the card: picture, name, type, distance; faction and
  services for a station; destination for a gate. Pictures: a planet shows its own world map (when the worlds pack
  is in), Liberty-type stations their wheel model; everything else its type picture in `assets/nav/` (rendered
  from the game's own models). A missing type picture gives a drawn token (`NavGrid.picture`). X or a tap outside
  closes the card. There are no moons in the data yet; the "moon" type picture is ready for when there are.
- **Set course.** Unchanged flow (tap, SET COURSE, autopilot). The course is drawn as a thick glowing line with
  running chevrons and a pulsing pin, with distance on the line and speed and ETA by your arrow, on the map and
  (shorter) on the radar. Belts, the nebula and the star can be set as a course too (a waypoint at their middle).
- **Radar.** Same view, small: a tap on a blip opens the map with that object's card; a tap elsewhere on the
  radar opens the map as before.

## 30. The true Savagers: ships, pilots, the rank rule and bounties (Job U, v1.4q)

**Ships.** The owner's Savagers ship set (one file, 17 objects) was split into separate light copies. The original file
is kept untouched outside the game for printing; nothing was saved over it.

- **Raider** now flies the Savagers skirmish craft, **Corsair** the Savagers twin gunboat (`assets/ships/enemy/savager_*`).
  The old `enemy_fleet` and `corsair` models are removed. Raider and corsair are the enemy in every faction's space, so
  the new models show up wherever those two fly.
- **Raider Cruiser** (new enemy kind `cruiser`) is the boss ship.
- **Savagers systems** show the salvaged carrier instead of the fleet carrier (`SpaceSystem.carrier_key`).
- The other 13 objects of the set (station, frigates, fighters, gunboats, turrets, outpost) are ready as light copies but
  not placed yet. The owner is making a station for each Savagers system.

**Pilots (Savagers space only).** Six portraits from the owner's Savagers sheet, each clean and battle-damaged
(`assets/enemy_pilots/sv01..sv06_normal/_damaged.jpg`). The face switches to battle-damaged at half health, same as the
AX pilots. `Data.ROSTERS["Savagers"]`; `Data.roster(system)` returns a roster only for Savagers systems.

- 01 Thug, 02 Raider (hyena), 05 Lieutenant = **soldiers**: they fly the patrol ships in Savagers space.
- 03 Thug (mohawk), 04 Ace Pilot, 06 Gannon (gang boss) = **bounties**.

**The rule (for every roster to come: each faction, each star system, each planet).** Six pilots numbered 1 to 6. The
higher the number, the stronger: hull, wings and shield x (1 + 0.3 per step), gun damage x (1 + 0.18 per step), speed
x (1 + 0.03 per step), reward x (1 + 0.5 per step), and a bigger ship (`RANK_KIND`: 1-2 skirmish craft, 3-5 gunboat,
6 cruiser). All numbers are in the Job U block of `data.gd`. A test checks that every step up is tougher and hits harder.

**Bounties.** Every station has a BOUNTIES page (left menu). ACCEPT one target; they hide in a Savagers system
(03 Plundros, 04 Scavaris, 06 Raptian Major). Destroy the ship: the pilot drifts out in a space suit (stand-in model:
the future soldier, `assets/cargo/spacesuit_pilot.glb`). TRACTOR them in, dock at any station, and the reward
(600 cr x number) is paid once. One bounty at a time. `GS.bounty`, `GS.bounties_done` (new fields, empty by default).

Simplest choices made: any station pays; leaving the system before the pickup puts the target back; stations with
panorama rooms (Liberty Hub) reach BOUNTIES from the left menu of any dealer screen.

## 31. Faction population phase 1: Savagers + reputation (Job V, v1.4r)

Source of truth for the Savagers: the owner's document "SAVAGERS - Faction Roster, Voice Personas & Fighter Assignments v1"
and the brief "Faction Population Update, Phase 1". Only the Savagers are filled in. Other factions keep their
placeholder patrols until their pack arrives; nothing of theirs was removed.

**The cast (`Data.ROSTERS["Savagers"]`).** Six persistent people, linked by `character_id`: 01 Soldier (the common
troop, many at once), 02 Jackal, 03 Razor, 04 Veil, 05 Brakk, 06 Dreadmaw (named, never two of the same at once). Each
record carries slot, rank, sex, species, persona, voice fields (`voice_id`, `voice_sex`, `voice_persona`,
`normal_emotion`, `damaged_emotion`, `critical_emotion`), a clean and a damaged portrait
(`assets/enemy_pilots/savagers_0N_clean.jpg` / `_damaged.jpg`), a primary fighter and alternates, a spawn weight.
Sex, name, voice and ship are read from the data, never guessed from the picture. Voice chat itself is not built.
This replaces the v1.4q names (Thug / Raider / Gannon) and roles.

**Fighters (`Data.ENEMIES`).** Scrapfang Light Fighter, Redclaw Interceptor, Ironhowl Heavy Fighter, Warboar Command
Fighter, each tougher than the last. Strike craft only: the cruiser and carrier are never a pilot's ride. The models
are stand-ins picked from the owner's Savagers ship set until each named fighter design is delivered (Scrapfang and
Redclaw = the two small X-wing darts, Ironhowl = the skirmish craft, Warboar = the twin gunboat). The rank rule from
v1.4q still applies on top (higher slot = tougher, harder guns, bigger reward).

**Who you meet.** In Savagers space patrols fly in threes and are picked by spawn weight: mostly Soldiers, sometimes
Jackal, Razor, Veil or Brakk, rarely Dreadmaw. A named pilot you shoot down gets away and stays out for that visit
(`GS.cast` keeps alive / current_system / custody). A pilot handed in as a bounty is in custody and no longer flies.

**Raids.** The Savagers' rival is set to the Liberators (their neighbour on the map; one line in `factions.gd` to
change). On 40 % of visits to a Liberator system one two-ship Savagers party is there: Soldiers, now and then led by
Jackal. Never the whole cast.

**Reputation (`scripts/factions.gd`, `GS.rep`).** Eight major factions in four rival pairs; each pair shares ONE
number, so hurting one side helps the other by the same amount. Standing reads as a colour: purple TRUSTED, blue
FRIENDLY, green ACCEPTED, yellow CAUTIOUS (does not attack), orange HOSTILE (attacks on sight), red HUNTED (attacks
and sends a hunter group of three when you enter their space). Cybermorph is a GRAY permanent enemy outside the
spectrum. Savagers start orange, everyone else green. Destroying a faction ship costs 1.5 x the pilot's slot;
handing in a bounty costs 6 more. Shown on the station hub page and the BOUNTIES page, in colour.
What reputation does NOT do yet: discounts, blocked docking, allies fighting beside you, special missions.
The pairs other than Savagers / Liberators (Unity / Imperium, Elyza / Covenant, Solarion / Orion) are a first guess.

**Stations.** The five Savagers systems wear the owner's Savagers cross station (`assets/structures`). The light
beacon station sits in the middle of the nebula in each Savagers system and in Solara's Violet Reach. Its lamp is a
real light (colour, range 1100, energy, breathing: the `BEACON_*` block in `data.gd`) with a bright star, a halo and
lit cloud puffs; close to it the nebula haze on screen thins and warms and the sensors get most of their range back.
You can target it; you cannot dock at it yet.

**Bounties** now list Razor, Veil and Dreadmaw, each in her or his own fighter.

**Assets saved outside the game, untouched, for printing:** the five original files (Savagers ship set, Savagers
cross station, light beacon station, Liberator ship set, World's End station). The Liberator set is split into 18
light copies but not placed: their pack is not this phase.

Not done in this phase (said plainly): desert-world and underground Savagers settlements, cargo-theft / convoy /
checkpoint encounter types (only patrols, raids, hunters and bounties exist), story encounters.

## 32. Hub reset: static faction backgrounds, panorama rooms removed (Job W, v1.4s)

Owner decision: a hub is a fast 2D interface, not a room. Dock, the faction's picture appears, a see-through menu
sits over it, buy / equip / repair / missions, launch. No panning, no dragging, no hotspots.

- **One picture per station visit.** `Factions.hub_background(station, system)` picks it: the station's own picture
  (`"ui_background"` on the station record) > its owner faction's (`"ui_background"` in `Factions.DEFS`) > none, in
  which case the hub draws its plain code-made backdrop. Nothing is hard-coded per screen: Hub, Equipment, Ship
  Dealer, Repair, Bounties and Faction all sit over the same picture.
- **The pictures** are the owner's 14 "Faction Interface Background" images from Drive (`assets/hub_bg/<faction>.jpg`,
  1280 x 720, about 300 KB each): Unity, Elyza, Solarion, Imperium, Covenant, Orion, Savagers, Liberator and the
  enemy factions Solrath, Gadversee, Arctides, Cybermorphs, Phenom, Kaijurai. Each is its own small pack
  (`hubbg_<faction>`): only the picture for the station you dock at is fetched, and it is let go when you leave.
- **See-through interface.** Panel 50 %, buttons 72 %, a 38 % dark wash and a darker strip behind the title
  (`HUB_*` in `data.gd`).
- **FACTION page** (new menu button): who runs the station, your standing, their rival.
- **Enemy factions** Solrath, Gadversee, Arctides, Phenom, Kaijurai were added to `Factions.DEFS` as gray permanent
  enemies (with Cybermorph): interface art, no place in the rival pairs.
- **Panorama removed from the game.** `rooms.gd`, `npc.gd`, the room pictures and the room person's model moved to
  `art/archive_panorama/` (kept in the repo, never exported); the `rooms`, `rooms_aurelion` and `npc` packs are gone
  (12.8 MB no longer built or downloaded). Ten route checks that tested the rooms were removed with them.
  The title screen's slow collage is not a hub and is unchanged. `ArtRefs` (the concept-art map) still lists room art.
- Not built here: Cargo, Trade, a Weapons / Armor split, a mission board beyond bounties (the old Job T brief).

Two of the Drive pictures (Covenant, Liberator) are ship reference sheets rather than scenes; they are used as filed.

**Symmetry repair (same job).** The four Savagers models the game flies or stages (skirmish craft, twin gunboat,
salvaged carrier, raider cruiser) were replaced by their mirrored copies: exactly the same left and right. The skirmish
craft, which sat 10 degrees askew in the owner's set, is now straight (`SAVAGER_SKIRMISH_YAW` 180). 50 ships in the
library have a mirrored copy; see `docs/ASSET_LIBRARY.md` for the list and for what was left alone and why.

## 33. Voice ON by default (Job X, v1.4t)

What was already there: the comms console has a VOICE button. It used to start on the Star Fox style radio blips
("mumble") and could be switched to "read", which made the device's own text-to-speech read the line. The choice was
not remembered. There were no recorded voices and no way to play one.

Now:
- **Voice is ON by default** (`Data.VOICE_DEFAULT`). The VOICE button shows ON / OFF. OFF gives the radio blips.
  The choice is remembered (settings file, new section "audio").
- **ON plays the character's own recorded line when there is one**: `assets/voices/<voice_id>/<line key>.ogg`, where
  the line key is the line in lower case with words joined by `_` (`Sfx.clip_path`). The voice id comes from the data
  (`voice_id` on roster characters, the character key for Vale, Shade and the others), never from the picture.
- **No recording for that line:** the device reads it aloud if it can; a device that cannot keeps the blips.
- Honest state today: NO real voice clips are in the game yet (only a half-second test tone). Until the owner's
  generated or recorded lines are added, "ON" means the phone's or browser's built-in reader, which varies by
  device. Each character's clips should go in as their own small pack when they arrive.

## 34. More room, one prompt, the lane tunnel pulled back (Job Y, v1.4u)

- **More room.** Every system is spread out: the planet, gates, asteroid belt, nebula, patrol points and the
  placeholder planets and stations all sit `SYSTEM_SPREAD` (1.4) times farther from the main station. Sizes are
  unchanged. One step (`SystemBuilder.spread`) does it for the hand-made and the generated systems alike.
  Flights are longer by the same factor; trade lanes and warp already cover the distance.
- **Docking needs you closer.** DOCK shows inside 190 m of a station (was 260) and 240 m of a planet's surface
  (was 300).
- **One prompt at a time.** `SpaceSystem.prompt()` decides DOCK, GATE or TRADE LANE. Where a station and a lane ring
  are both in reach the nearer one wins, so the two no longer fight.
- **Trade-lane tunnel.** The energy tunnel that rides on the ship is now 640 m long and 92 m wide, with 42 % of it
  trailing behind the ship and the rear end flared. The chase camera sits well inside it, so its round rim is never
  on screen; the streaks are finer.

Still to do (owner's brief, next job): one core warp effect, skinned three ways: the Freelancer-style gate tunnel,
the cloud "anomaly" warp for the warp gates, and the rift gate as a rotating oval tear in the sky with layers of sky
and coloured mist rushing past (slow at first, then fast, holding at full speed while the next system loads, easing
out with no white flash).

## 35. Named stations (Job Z, v1.4v)

The owner's 68 station names, each with one line of lore, are laid over the map catalog (`scripts/station_names.gd`).
Every name fitted a station that was already on the map under a role name ("Smuggler Den" is now Blackbilge Den,
"Last Stop Station" is World's End Emporium, and so on), so nothing had to be invented or moved. Station ids are
unchanged, so saves are safe. The lore shows on the docking screen and the map card. Stations that share a model
still have their own name, system, owner and lore. Elyria (Grovecrown) is on the planet, so it is told on Aurelion
Prime's line, not placed in orbit.

Three stations wear the owner's finished models: World's End Emporium (Omega, with its glass domes), the Hollow
Requiem (Shadow: the dead liner from the ghost ship set, a discovery, no faction), and Greywhistle Beacon (Foggiest:
the light beacon station). Greywhistle and Hushmark Beacon (Nullpoint) carry the lamp themselves; Foggiest's cloud
is grey and wraps the beacon, so the lamp burns in the fog and thins it as you come close.

Not yet named by the owner and left as they were: Cybernet, the capitals' extra stations except Synthari's, the Void
beacons, Vega and Solara.

## 36. Seven more faction casts (Job AA, v1.4w)

Source: the owner's roster documents in Drive ("<FACTION> - Character Roster, Personas, Voice IDs & Image Pairing v1";
Orion's text is v2.0) and the matching roster pictures. Document and picture are a pair: names, sex, species, voice
type, rank and persona come from the document, never from the picture.

- **Data** (`scripts/roster_data.gd`, merged into `Data.ROSTERS`): six people each for Covenant, Imperium, Solarion,
  Unity, Elyza, Orion and Liberator. Slot 01 = common masked soldier, slot 05 = elite masked soldier (both may appear
  many times); slots 02, 03, 04, 06 = named, persistent people. Voice fields are kept ready (voice id, sex, type,
  normal / combat / damaged / critical delivery). No dialogue was invented.
- **Faces:** 84 portraits (42 clean, 42 battle-damaged) cut from the seven roster pictures. Each picture is laid out
  differently (two halves, or two rows of six); the cuts were checked by eye against the slot numbers.
- **Who flies:** only a faction with a fighter model in the game. Imperium and Liberator have two each, stand-ins from
  the owner's own ship sets (light for slots 1-3, heavier for 4-6), mirrored and checked from above for facing. Each
  keeps a guard wing of two near its main station. They obey reputation: peaceful and shown as a gold patrol contact
  (kind "patrol", not "enemy"), they answer a hail with their own face, and turn hostile only if you shoot or your
  standing is orange or red. The placeholder raiders in those systems are unchanged.
- **Known but not flying yet:** Covenant (its fighters lie on edge in the set; nose not clear), Unity, Elyza,
  Solarion, Orion (no ship set yet). Their six show on the station FACTION page.
- **FACTION page:** the owner faction's six faces and names.

Open points for the owner: the Covenant picture labels slot 05 "Hierarch Orin" and Solarion's labels slot 06 "Emperor
Valen"; the documents say "Hierarch Guard" and "Valen Aurex", and the documents were followed. The Orion roster
describes explorers (Pathfinder Nations) while the station list describes Orion as the reptilian Venom war clan.
The newer rosters say slot 05 is an unnamed elite soldier "retroactively"; the Savagers' Brakk was left named.

## 37. One warp effect, three looks (Job AB, v1.4x)

The owner's brief (voice): match the Freelancer jump-gate feel, give warp gates a gas "anomaly" jump, and make the
rift gate a tear in the fabric of space built from the sky pictures. All three are the same effect with a different
look; the kind of gate picks the look (`Data.WARP_SKINS`). Every number is in the Job AB block of `scripts/data.gd`.

- **How it runs** (`main.jump`, unchanged order from Job K): build -> hold at full speed while the next system loads
  -> clear. `fx.pace` is the speed (layers per second from `WARP_PACE_SLOW` to `WARP_PACE_FAST`) and `fx.spin` the
  turn rate, so the cloud and the tear start with slow passes, each with a boom, then run fast, hold, and ease out.
- **Tunnel (jump gate):** a corkscrewing tube of light toward a bright far end, with the old star streaks on top.
  Same timing as before (0.5 s in, 0.3 s out) and it keeps its launch flash.
- **Cloud (warp gate):** layers of gas in the colours of the two skies rushing past. No white flash.
- **Tear (rift gate):** `RIFT_LAYERS` sheets (10; up to 12) made from the sky picture of the system you leave and the
  one you reach. Each sheet has a ragged oval rip; you fly through the rips. Sheets turn opposite ways, one after the
  other, slowly at first and then fast. Each rip has coloured mist on its edge; the twelve mist colours are taken from
  the two sky pictures and no two in a row are alike (`RIFT_TINT_MIN_HUE`). No rings to fly through first: the rift
  opens where the ship is. No white flash; it eases out.
- **Drawn by** one small screen shader in `scripts/fx.gd` (one pass, no extra 3D, no particles). With REDUCED EFFECTS
  on, every jump is still the plain fade from Job K.
- Planet tile changes keep their plain streaks (`fx.jumping` is false there).

Simplest choices made, to confirm: the jump tunnel is a close match in feel to Freelancer's, not a copy of its art;
the tunnel keeps its flash while the other two have none; the tear's colours fall back to the two systems' star and
nebula colours when a sky picture cannot be read.

## 38. Kaijurai and Phenom ships (Job AC, v1.4y)

- Seven ships from the owner's two sets are in the game, as light mirrored copies, all nose first (extra yaw 0):
  Kaijurai dart fighter, heavy fighter and gunship; Phenom fighter, interceptor, scout and heavy fighter.
- Owner edits: the Kaijurai dart got wider wings, a barrel-booster on each side of the tail and a shorter nose (it
  looked like a missile); the Phenom fighter and interceptor were shortened to one cockpit each (`graft.py`, `segment_cut.py`).
- Thruster repair: the Phenom interceptor and scout came with a cannon standing upright at the tail. It was cut off
  and the twin thrusters of another Phenom fighter were grafted on (`tools/assetkit/rear_swap.py`).
- Where they fly: the patrols of the two enemy home systems, Genesis (Kaijurai) and Noctyra (Phenom). `Data.HOME_FLEETS`
  maps the map's role text to a list of ship kinds; a patrol takes its ships from the list in turn (`sys["enemy_ships"]`).
  Every other system keeps `sys["enemy"]`.
- They are permanent enemies: no roster, no reputation, always hostile. Their pilots are the generic masked pilots, shown
  as that faction's wing; no named raider or corsair leader flies them. No lore was invented.
- Numbers (lengths, the fleet lists) are in the "Job AC" block of `scripts/data.gd`. No save key changed.

Simplest choices made, to confirm: which ship of each set is the "fighter", "heavy" and so on are guesses from the
shapes; the stats copy the Imperium and Liberator fighters of the same class; the capital ships, turrets and missiles of
both sets are saved in the asset library and not placed.

## 39. The six enemy casts (Job AD, v1.4z)

- Source: the owner's roster documents of 7 Oct 2026 ("<FACTION> - Character Roster, Personas, Voice IDs & Image
  Pairing v1") and their matched pictures, for Phenom, Kaijurai, Cybermorphs, Solrath, Gadversee and Arctides. Names,
  sex, species, voice type, rank and persona are copied from the DOCUMENT, never read off the picture. Where a
  document gives no text for a field (several have no "critical" voice line; the Cybermorph frames 02-06 only have a
  voice variant) the field is left empty: nothing was invented. `tools/rosterkit/gen_rosters.py` holds the typed data.
- Cybermorphs are machines: sex "none", one neutral machine voice family; the game says "It", not "He" or "She".
- Portraits: 72 pictures (clean and battle-damaged for each of the 36), cut from the six roster sheets by
  `tools/rosterkit/crop.py`, in `assets/enemy_pilots/` (the "enemies" pack, not the core download).
- All six are permanent enemies (gray band, always hostile, outside the reputation ladder), as the documents say.
  The Arctides document does not use the words "permanent hostile"; it was left as the enemy faction the map and
  the Bible make it.
- Who flies: only Phenom and Kaijurai have ships in the game. Their people fly the patrols of Noctyra and Genesis
  (`Data.HOME_FACTION`), each in a ship of their own set, with the usual rank rule (higher slot = stronger ship). The
  ship lists of v1.4y (`Data.HOME_FLEETS`) remain as the fallback. The other four casts are known (faces, names) but
  do not fly until their ship sets are processed.
- Ship assignments are NOT in the documents ("future ship assignments"). Simplest choice made, to confirm: slots 1-3
  light, 4-6 heavier. Phenom: 01 fighter, 02 Vyrela interceptor, 03 and 04 scout, 05 and 06 heavy fighter.
  Kaijurai: 01 and 02 dart, 03 and 04 heavy fighter, 05 and 06 gunship.
- Two Job AA checks counted "8 rosters" and "three factions fly"; they now count the eight main factions only. The
  Job AC patrol check now accepts the faction's own roster people as the pilots.

## 40. Full screen, mission waypoints, title movie (Job AE, v1.5a)

- Full screen: the web page asks the browser for full screen (and landscape lock) on the first tap and again on
  START (`window.__hlFullscreen` in `web_shell.html`, called from `main.start_game`). A browser only allows this
  after a tap, never on page load. If the player leaves full screen on purpose, taps no longer force it back; START
  asks again. Browsers that refuse (some in-app browsers, iPhone Safari) simply stay as they were.
- Mission waypoint: accepting a mission sets a waypoint by itself. Today the only missions are bounties.
  `space.mission_waypoint()` gives the next thing to fly to: the jump gate on the shortest route
  (`Data.gate_route`, breadth-first over the gates) while the target is in another system, then the target ship,
  then its pilot pod, then the station to hand the pilot in. The HUD shows it as a gold MISSION diamond with the
  distance (an arrow on the screen edge when it is off screen), the waypoint box names it, the objective line says
  "MISSION: ...", and GO TO flies it when nothing else is picked. No save fields were added.
- Title movie: the panning collage is gone (picture kept in `art/archive_title/`, outside the game). The start
  screen plays `assets/intro/title_movie.ogv` on repeat (640x352, 20 pictures a second, 1 min 42 s, about 9.5 MB,
  in the intro pack, so START never waits for it). It plays picture only; the main theme stays the sound.
- Smaller main download: the textures of the seven Kaijurai / Phenom ships (v1.4y) were imported uncompressed;
  they are now lossy (0.8), which takes about 5 MB off the core.
- Tests: the start-screen check now checks the movie; five new Job AE checks (`HL_AE=1`).

## 41. New Cybermorph faces; the game is for a mature audience (Job AF, v1.5b)

- The owner sent a new Cybermorph roster picture. The twelve portraits (six clean, six battle-damaged) in
  `assets/enemy_pilots/cybermorph_0N_*.jpg` were cut again from it, same file names, slot numbers as printed on it.
- The new picture prints other names and roles than the roster document (01 Scout Verid, 02 Specialist / Raider
  Drakos, 03 Hunter Kael, 04 Commander Aegis, 05 Assassin Nyx, 06 Titan Korvex; the document has UNIT-01, VX-RAID,
  ORION-K, NEX-M7, AX-9, PRIME-NEXUS with the command frame in slot 6). The document is the authority, so names,
  ranks and voices were NOT changed. Open question for the owner.
- Owner's decision (7 Oct 2026): Homelancer is for a mature audience, 17 and up. This replaces the earlier
  "kid-friendly game page" rule. The title movie stays as sent.

## 42. Covenant, Cybermorph and Solrath fly; Liberator and Imperium rebuilt (Job AG, v1.5c)

- Fourteen fighters from the owner's ship sets (see `docs/ASSET_LIBRARY.md`, Job AG). Covenant is a main faction, so
  its people now fly its patrols like the other main factions with ships. Cybermorph and Solrath are permanent
  enemies: Cybernet and the Void System fly their home fleets (`Data.HOME_FLEETS`, `Data.HOME_FACTION`), flown by
  their own six, like Genesis and Noctyra.
- Ship per pilot (simplest choice, the documents give none; to confirm): slots 1-3 light, 4-6 heavier.
- Capital ships (the Covenant battleship, Liberator carrier, Imperium warships, Solrath flagship, Cybermorph big
  frames) are the next job: the owner wants the vessels, not the repeated turrets and missiles.
- Tests: five Job AG checks (`HL_AG=1`); the Job AC "no other system flies a home fleet" check now excludes every
  system whose role is in `HOME_FLEETS`.

## 43. The warp keeps moving while the next system loads (v1.5d)

- The jump's load used to be one long frame, so the cloud and the tear froze for about a second and then jumped
  forward. Now `space.setup_staged()` builds the next system one step a frame (station, planet, gate, nebula, ship,
  patrols, traffic), with the scene's own processing off until the last step, and `fx` advances the warp by at most
  `WARP_MAX_STEP` (0.05 s) a frame, so a long build frame never jumps the layers. The HUD lets go of the old scene
  while the new one is being built.
- Owner's audit answers (7 Oct): jump gates and freeways are good as they are. Still open from the brief: a longer
  exit dissolve, dock / gate / lane nearest-wins, rift slow-layer count and rift-only spin, system spread.

## 44. The map opens on you (v1.5e)

- In flight the navigation map is centred on your ship and zoomed out until the whole system fits round you (the
  fit is worked out from your position, not the system's middle); FIT returns to that. Docked, it still fits the
  system. The mission waypoint is drawn on it as the gold MISSION diamond.

## 45. Missions (Job AI, v1.5f)

- `scripts/missions.gd`. A station's MISSIONS page offers three jobs for the visit (seeded by the station and the
  number of jobs done): PATROL threats (slot-01 soldiers), ELITE threats (the slot-05 elite leads, `MISSION_HARD_MULT`
  the pay) and an escort. The enemy is the faction that raids the owner (`Factions.raider_of`), else the first of
  `MISSION_FALLBACK_ENEMIES` with ships. One job at a time; YOUR SHIP can drop it.
- Accepting a job says what to do and sets the gold mission waypoint; at launch the station's dispatch repeats the brief
  on the comms panel. Threats: fly to point 1 (3.2-5.2 km from the station, clear of the planet), the wave appears when
  you are within `MISSION_ARRIVE`, the waypoint moves to the nearest of them; wave cleared, the waypoint moves to point
  2; second wave cleared, paid on the spot.
- Bounties from the BOUNTY BOARD now run the same chain in the target's system: point 1 is the escort wing, point 2 the
  target's own wing with the target in it. Rank under `BOUNTY_ALIVE_RANK` (4) = wanted dead: the kill pays on the spot,
  no pod. Rank 4 and up = wanted alive: the pilot bails out, TRACTOR puts them in the hold (`GS.cargo`), the waypoint
  leads back to the station that gave the job (through the gates if needed) and only that station pays. An old-style
  bounty (GS.bounty with no mission) still pays anywhere, as before.
- Escort: a freighter leaves the station's dock point for the planet at `ESCORT_SPEED`; at a third and two thirds of
  the way a wave appears `ESCORT_AMBUSH` off it. Simplest model of "under attack": while a mission ship is within
  `ESCORT_RANGE` the freighter loses `ESCORT_FIRE` hull a second per attacker (sparks show it); kill them and it stops.
  Arrival pays; the freighter lost fails the job. (Enemies still only shoot at the player; a real freighter-targeting AI
  is a later job.)
- The hold: `GS.cargo` (`CARGO_HOLD` 8) lists what you carry; today only bounty prisoners. YOUR SHIP shows guns,
  racks and the hold. No save fields: there is no save system yet.
- Open for the owner: pay numbers; whether a bounty's dead / alive should be chosen per target instead of by rank;
  mission givers on planets (only stations have the page).

## 46. Ship scan (Job AJ, v1.5g)

- Tap a ship where it is drawn (enemies, traffic, the escort freighter; within `SHIP_TAP_RADIUS` px, not on the sticks)
  and it becomes the target. With a ship targeted the waypoint box says TAP = SCAN: tap it and the scan runs for
  `SCAN_TIME` (a sweep on the ship), if it is within `SCAN_RANGE`. Then a panel shows pilot (name, role, slot),
  ship and class, hull and shield, weapons (each wing / arm gun, or DESTROYED once shot off; chest cannon; missile
  rack), cargo, bounty price and whether it is your mission's target. It refreshes live while open, and closes with its
  X or when you pick another target.
- Cargo is made up from the ship's name, so the same ship always carries the same: civilian goods for haulers
  (`SCAN_GOODS`), faction goods for enemy ships (`SCAN_ENEMY_GOODS`), plus the credits it would drop.

## 47. Lower mountains, real water (Job AK, v1.5h)

- Mountains were up to about 2.5 km of needle peaks (amplitude 1350 and sharp ridges at 0.8, nearly the 2.6 km
  ceiling). Now: mountains amplitude 760, volcanic 640, ridges squared (rounded crests) at `TERRAIN_RIDGE_HIGH` 0.55
  for country from `TERRAIN_RIDGE_AMP` 700 up (0.25 elsewhere), and above `TERRAIN_PEAK_EASE` 85 % of the amplitude the
  ground rises at under half the rate, so peaks broaden. The highest ground sampled is now under 1 km (the check allows up to 1.45 km).
- Water: a shader (no textures, gl_compatibility) on a 64 x 64 grid per tile whose vertex colour holds the sea depth
  below it (from the same height field as the terrain): rolling waves (moving sines, gentler in the shallows),
  deep water darker, turquoise shallows, breathing white foam on the shoreline, the horizon colour reflected at low
  angles and a sun glint. Magma seas (stars) keep their flat glow. Numbers in the Job AK block.
- `HL_TERRAIN=1` (with `HL_SHOT_DIR`) takes pictures of New Terra's tiles from low altitude and a low pass over the
  coast's water: a work tool, no checks.

## 48. GPS, stage 1: destinations, A -> B, distance and ETA (Job AL, v1.5i)

Audit of what was there (owner's GPS brief, section 1):
- Destination selection: `scripts/navmap.gd` (tap an object, its card, SET COURSE -> `main._on_course` sets
  `space.autopilot` and `space.target`). Objects register by `navmap._collect()` reading the system data plus the live
  nodes (station, planet, gates, extra planets / stations, belt, nebula, star, beacon, ships, traffic).
- Distance: straight line, `space.distance_to(node)` (surface to surface for planets).
- Markers: HUD `_draw` labels station / planet / gate; the gold MISSION diamond (v1.5a); radar blips (`hud._radar`).
- Route lines existed only for a SET COURSE (a green line on the map and the radar), ETA from current speed.
- Freeways = trade lanes: rings from the station to the planet and to each gate (`space._build_lanes`), entered at a
  ring (`lane_candidate`). Jump / warp / rift gates = ring nodes with `info.gkind`; `Data.gate_route` finds the
  shortest gate path between systems (v1.5a).
- Limits: the map pauses the game while open (so "watch the icon move" happens on the HUD strip, not the map); no
  waypoint list; lanes are straight lines (they can cross the asteroid field); systems use one spread factor (1.4).

Stage 1 (this version):
- `space.nav_dest` is the GPS destination (point B); it stays set when you take the stick and clears within
  `GPS_ARRIVE`. SET COURSE sets it too. ETA = distance / `space.eff_speed()` (the one place to tune it: lane speed in a
  lane, warp speed at warp, otherwise current speed but never under cruise).
- Map: with nothing picked, the right panel is GPS · DESTINATIONS: the system's known places nearest first (mission
  first), with kind and distance; tap one to make it the destination (no autopilot). The route is blue, A and B
  marked, distance and ETA on it.
- HUD: above the dashboard a GPS strip: A -> B on a blue line, your marker sliding toward B as the distance closes
  (and back if you fly away), name, distance, ETA.

GPS stage 2 (same version): ADD WAYPOINT.
- `space.nav_route` holds up to `GPS_MAX_STOPS` (3) stops in order; the last one is the final destination (the brief's
  "stop 1 / 2 / 3" structure). `nav_dest` is always stop 1. Reaching a stop (`GPS_ARRIVE`) drops it and the GPS aims
  at the next one by itself; the last one ends the route.
- Map, right panel: ROUTE (total distance and ETA, CLEAR) with each stop's leg and up / down / remove buttons; tap a
  stop's name, then a place below, to replace it. In the list: tap a place = go there (the route becomes that one
  stop); its + = ADD WAYPOINT (no fourth stop, no repeats; changing the final destination = replace or reorder). The
  map joins the stops in order with numbered blue dots.
- HUD strip: STOP 1/N, the leg's distance and ETA, and ROUTE total distance and time.
- Zones (asteroid field, nebula) get a GPS marker node of their own per stop, removed with the stop.

## 49. Voice system, stage 1: phone voices with profiles, hold-to-talk (Job AM, v1.5j)

What was there: every spoken line already went through one place, `Sfx.speak` (called by `hud.open_comms`, and the
VOICE button's replay). It played a recorded clip if one existed (`assets/voices/<voice_id>/<line>.ogg`, none yet),
else the device's text-to-speech with "voice 2 = female", else radio blips. Talking back was TYPE only.

Now (owner's voice brief, stage 1; stages 2 and 3 not built):
- `scripts/voice.gd` holds the voice PROFILES and the device-voice choice; `Sfx.play_character_voice(character_id,
  dialogue_id, text)` is the one call that speaks (the old `Sfx.speak` forwards to it; no text-to-speech call anywhere
  else). Providers in order: PRELOADED_AUDIO (a recorded file for that line) -> LIVE_API (off: `VOICE_LIVE_API`
  false, needs a secure server, never a key here) -> PHONE_TTS -> radio blips. VOICE OFF = blips.
- Profile: character_id, persona_id (the roster documents' voice_persona), preferred_voice, voice_type
  (male / female / machine), pitch, speaking_rate, volume, fallback_voice, effect (radio / robot / alien). Defaults per
  persona in `Data.VOICE_PERSONAS`, one character's changes in `Data.VOICE_PROFILES`; pitch and rate kept readable
  (`VOICE_PITCH_RANGE`, `VOICE_RATE_RANGE`). Machines use the masculine voice family (owner's Cybermorph rule).
- Device voice: chosen from the voices the device has, by name (Zira, Samantha, "Female"... vs David, Daniel,
  "Male"...), English first, varied per character; remembered per character in the settings file (new section
  "voice_pick"). If it is gone, another is picked; if the device has no voice of that sex the pitch is nudged
  (`VOICE_SEX_PITCH_NUDGE`) instead.
- Effects around the line, no live processing: robot = beep chatter before and after plus a quiet hum behind;
  alien = clicks and warble before and after; radio = a static burst before (new synthesized sounds, made by
  `tools/sfx/make_voice_fx.py`).
- The same line for the same character asked twice within `VOICE_SAME_LINE_GUARD` is spoken once.
- Rolled out to four test characters only (`VOICE_PROFILE_ROLLOUT`): Capt. Rennick (male human), Cmdr. Vale (female
  human), UNIT-01 (Cybermorph), the Kaijurai Containment Trooper (alien). Everyone else keeps the old voice path
  until the owner approves the four.
- HOLD TO TALK (comms console, between TYPE and VOICE): while held the browser's speech recognition listens (Chrome
  on Android, Chrome / Edge on desktop; `window.__hlListenStart/Stop` in `web_shell.html`); on release the words go
  where typed words go (`hud.typed` -> `main._on_typed` -> the character's brain answers -> the voice speaks it).
  No speech recognition, or nothing heard: typing opens instead. Typing is always there.
- Not checked on a real phone from here: which voices an Android phone offers (many Android voices have no name that
  says male or female; then the pitch nudge decides), and the microphone permission prompt in Chrome.

## 50. Test-flow foundation (Job AN, v1.5k): LAUNCH, the MISSION BOARD, the opening enemies, voices

Owner's brief of 8 Oct ("fix this test flow before deploying the full character roster"). Nothing of the bigger
character deployment was done; only the foundation.
- LAUNCH: v1.5f's two new menu entries pushed the LAUNCH entry off the bottom of the screen. Now LAUNCH is its own
  green button in the upper right (under the credits, `HUB_LAUNCH_SIZE`), the hub's last child so nothing covers it,
  on every page. The menu has one MISSION BOARD entry instead of MISSIONS + BOUNTIES.
- MISSION BOARD: tabs MISSIONS | BOUNTIES (it reopens the tab last used); the lists scroll. Tap a job or a bounty =
  tracked (gold frame, TRACKING, the waypoint is set at once); tap it again = cleared; tap another = switched (the old
  one is dropped). Only one thing is tracked at a time. The only thing that blocks a switch: a prisoner in your hold
  (hand them in first). A "Tracking:" line says what is tracked and where its waypoint leads (system, jumps, first gate).
- Bounty targets: characters 2, 3, 4 and 6 of the Savagers (Jackal, Razor, Veil, Dreadmaw). Jackal is new (hides in
  Derelicta). Not female-only: Razor and Veil happen to be women.
- Opening enemies: the start system (Solara, Unity space) is raided by its RIVAL NATION, the Imperium
  (`OPENING_SYSTEMS`): slot 01 Imperium Trooper (male) and slot 02 Vexa Drak (female) in Imperium fighters, always
  hostile. The placeholder raider leaders (Scar Jackal, Ember Wraith) no longer fly there, and Shade (the hooded raider
  lieutenant) no longer calls in after the first kill there. They are kept for corsair / raider space elsewhere.
  Mission jobs in Solara are against the Imperium too.
- Major characters reserved: patrols never fly a faction's slot 06 leader (`PATROL_MAX_SLOT` 5); leaders appear only
  through their own story roles (and as bounty targets, like Dreadmaw).
- Voices: every character is on a voice profile now (`VOICE_PROFILE_ROLLOUT` "*"): story cast by its own sex, roster
  people by their documents' voice persona and sex, generic wingmen by their entry's sex. No single default woman's
  voice for everyone.
- Planets: no planet NPCs were added (the brief: leader + coordinator + local NPCs for now, later more). Today planets
  have their story contact (Oduya on New Terra, Amari at Frontier Exchange) and nothing else; nothing to remove.
- `HL_AN=1` runs the owner's exact flow as checks: opening Imperium troops and their voices -> dock -> MISSION BOARD
  select / deselect / switch -> BOUNTIES select Jackal, clear, select Veil, select Razor (waypoint switches) -> LAUNCH
  visible on every page -> LAUNCH -> follow the waypoint 5 jumps to Plundros -> beat the escort wing -> Razor herself
  in her Redclaw, targetable, a woman's voice.

## 51. The roster deployed across the game (Job AO, v1.5l)

Owner, after the v1.5k test flow passed: "push it to all".
- Bounties: characters 2, 3, 4 and 6 (`BOUNTY_SLOTS`) of every faction with ships (`BOUNTY_FACTIONS`: Savagers,
  Imperium, Liberator, Covenant, Phenom, Kaijurai, Cybermorph, Solrath) are wanted: 32 targets. Each hides in a system
  of their own faction (`Data.faction_systems`, spread by slot; the Savagers keep their own hideouts). A station posts
  its owner's enemies' targets only (`Data.bounties_for`): its rival nation, the permanent enemies and the outlaw
  Savagers; never its own people. Rank 4 and up wanted alive, as before.
- People at stations (`Factions.people_at`): every station of a main faction has its coordinator (the named slot
  02-04 whose role reads like handing out work, `COORDINATOR_HINTS`: Lena Torres for the Liberators, Korvax for
  Orion, Kael Varis for the Covenant; else slot 03: Rowan Hale for Unity, Garrik Rend for the Imperium...). The
  faction's capital also has its leader (slot 06: Commander Elara Voss at Veranthos, Lord Kraeg at Malachar...).
  The station page shows them (AT THIS STATION: face, name, role, TALK in their own voice). The lines they say are
  plain functional lines (who they are, "I have work for you on the Mission Board"), not invented lore. Enemy stations
  have none. The coordinator gives the job brief on the radio at launch, with face and voice.
- Factions without ships yet (Unity, Elyza, Solarion, Orion, Gadversee, Arctides) are not bounty targets: their
  people cannot fly until their ship sets are in.

## 52. GPS stage 3: freeways clear of the rocks, more room, fastest route, GO (Job AP, v1.5m)

- Rocks off the freeways: `SystemBuilder.clear_lanes` moves each system's asteroid field sideways (level) until every
  trade-lane line (station -> planet, station -> each gate) passes at least its radius + `LANE_BELT_CLEAR` (350 m)
  away. Lanes stay straight and engineered; the field moves. Checked for all 67 systems, and rock by rock for the
  system you fly in.
- More room: `SYSTEM_SPREAD` 1.4 -> 1.8 (everything 1.8x farther from the main station; sizes unchanged). Docking
  ranges, gate ranges and lane mechanics did not change; the autopilot warps on long legs and the lanes carry you.
- Fastest route: `space.nav_plan()` compares flying direct (warp on legs over `GPS_WARP_FROM`) with every trade lane
  (fly to its mouth, ride it at `LANE_SPEED`, fly on) and takes the lane when it is at least `GPS_LANE_GAIN` faster.
  The map draws it (blue to the mouth, the lane, blue on), the route panel says "Fastest: by trade lane ...", the HUD
  strip says VIA TRADE LANE and rings the lane mouth with its distance; the ETA is the plan's time.
- GO (route panel): the autopilot flies the whole waypoint route, stop after stop; taking the stick cancels GO but
  keeps the GPS route. (The autopilot itself still flies direct at warp; it does not ride the lanes.)
- Not done yet: routes across several systems on the galaxy map (the mission waypoint already leads gate by gate).

## 53. Thrust arc (Job AQ, v1.5n)

- Owner (by voice): when you push THRUST and fly up, the ship should arc up so it looks more impressive. While THRUST
  is on, the ship model's nose rears up into an arc: `THRUST_ARC_BASE` (45 %) of `THRUST_ARC_DEG` (22 deg) on a level
  boost, the full arc when climbing or pulling up; it rises at `THRUST_ARC_IN` and settles back to level at
  `THRUST_ARC_OUT` after you let go. Looks only: the flight path, speed and controls are unchanged; not at warp, not
  as a mech.

## 54. Special lock-on super move (Job AR, v1.5o)
- Owner's spec: docs/SPECIAL_MOVE.md. Built now with the single launcher the ship has today; the twin-launcher rule
  is one number (`SPECIAL_LAUNCHERS`) for when the hangar mounts a second identical launcher.
- Earned: at half hull (`SPECIAL_ARM_AT[0]`), once more at critical (`SPECIAL_ARM_AT[1]`). Each is spent once;
  repairing past `SPECIAL_RESET_AT` (75 %) earns them back (`GS.special_used`, a new save-safe field).
- SPECIAL button: the free corner of the top-left block (next to WARP), F on a keyboard. Locked (sub line "AT HALF
  HULL") until earned, then pulses gold. Hold it on a target inside `SPECIAL_CONE_DEG` / `SPECIAL_RANGE`: the ship
  (or mech) barrel-rolls, energy builds round the guns, a gold ring closes on the target over `SPECIAL_LOCK_TIME`.
  The target tries to break the lock (a sideways jink each second, `SPECIAL_BREAK_CHANCE`); out of the cone =
  "LOCK BROKEN"; letting go before the ring closes = "charge lost". Neither spends the special.
- Release after the lock: the cut-in (a slanted band over the view for `SPECIAL_CUTIN_TIME`: the pilot large,
  "SPECIAL ATTACK", "LOCK CONFIRMED" / "LAST STAND" at critical). Bars and buttons stay visible round it. The pilot is
  a helmeted silhouette until the owner gives a player pilot portrait (`PLAYER_PILOT_FACE`).
- Then the beam (can't be dodged once locked): strips the shield, `SPECIAL_BEAM_OVERFLOW` of the target's hull goes
  through, the shield stays down a while, a side-on hit (`SPECIAL_SIDE_HIT`) takes that wing off.
- Then the swarm: your real light missiles, locks x launchers (6 x 1 today), never more than you carry. No missiles =
  the beam only. Swarm missiles steer harder and are harder to dodge.
- Every missile (yours and theirs) bursts in a round explosion when its life runs out (`MISSILE_EXPIRE_BLAST`). A mine
  in an incoming missile's path decoys it (`DECOY_RADIUS`): both go off.
- Not yet: heavy torpedo timed lock, twin launchers (needs the hangar), a player pilot portrait.

## 55. The Elyza fighter and the hangar (Job AS, v1.5p)
- Owner: one ship for the whole Elyza faction for now ("one ship perfection"). His file held two forms of it; the
  closed one was uneven, so the game uses the clean open form, mirrored, and folds its wings in itself
  (`SHIP_WINGS`): it flies folded. The model is Body + WingL + WingR (`tools/assetkit/split_wings.py`).
- Per-ship special (`SHIP_SPECIAL_MOVE`): the Elyza fighter swings its wings out while it barrel-rolls through the
  special (lock, cut-in, beam) and folds them back after; any ship without its own move just rolls. The Elyza fighter
  is also on sale at the ship dealer (3500 cr) so the player can fly it.
- The hangar (YOUR SHIP -> ENTER HANGAR), from the owner's 3D parts, in its own "hangar" pack (not in the first
  download). Four walls, each a continuous backing of panels in two rows, each row stretched a few percent so it fills
  its wall exactly (no gaps); the big parts stand in front: the launch pad in the middle with a solid plate filling
  the back of its open frame (the owner: that panel must not be see-through), a mech bay each side, gantries between,
  two wall bays (lockers + walkway) on each side wall, pipes and a valve, the tall door in a corridor arch with a
  window strip on the front wall. Floor: steel plates with a hazard frame and guide lines (shader). Ceiling,
  generated: a dark deck, a grid of deep beams, light strips, a cornice round the walls; four lamps and a key light on
  the pad. Laid out in plan units (pad 20 tall) and scaled by `HANGAR_SCALE` so the player's mech fits the pad.
- Your mech stands on the pad, your ship is parked in front of it; SHIP / MECH switches, WINGS opens folding wings,
  drag looks around, pinch zooms; the camera stays on the open floor. Weapon mounts and the three paint channels come
  next on this screen.
- Budget: about 50 parts and 0.7 M triangles (the gantry and wall bays would not decimate below 64-73 k each).

## 56. Clean-up and placeholder fighters (Job AT, v1.5q)
- Owner: clean the game up, no loose assets. Removed: the title screen's blue network picture (the screen is dark until
  the intro movie arrives; the galaxy map lost it too), the 3D hangar (§55; the owner will provide something better),
  and the planet surface towns: Port Meridian's capital test block (the owner's tower and hangar buildings, the city
  kit, scripts/city.gd, the "city" pack) and the box-building towns round every landing site (the landing pads stay).
  The sweep for files nothing loads found none besides these (portraits, pilot pictures, skies and music are looked up
  by name). The ghost ship stays saved for later.
- The owner's placeholder fighter set: 14 of its fighters, one per faction, each tinted in its own colour
  (`PLACEHOLDER_SHIPS`, `ph_<faction>` in ENEMIES). Factions with no ships of their own (Unity, Solarion, Orion,
  Gadversee, Arctides) now fly theirs, so every faction's six pilots have a ship and a voice; factions that already fly
  the owner's real ships keep them (each placeholder is one line away).
- SPECIAL cut-in: the character's picture big in the middle (placeholder `PLAYER_PILOT_FACE` = the Unity trooper).
- The GitHub build's time limit went from 15 to 25 minutes (the test run had reached 14).
- Every roster pilot of the five ship-less factions flies its faction's placeholder; Elyza's pilots fly the Elyza
  fighter. The opening system (Solara) gets no guard wing, so the owner's test flow stays as it was.

## EXPERIMENT (branch planet-blocks-test): big-block destructible ground, step 1
- The owner's Bible "HL Minecraft-Style World Elements", light version (no voxel engine: Voxel Tools needs Godot
  4.4.1+ and has no web build). One test patch (800 m, `BLOCK_TEST`) on New Terra's mountains tile is built from big
  20 m blocks following the planet's own noise shape in 5 m steps (`BLOCK_BIG`, `BLOCK_MIN` = half a mech), plain
  colours, one MultiMesh. The smooth sheet under the patch is sunk out of sight; the ship lands on the block tops.
  Saved state = seed + deltas (none yet). Next: a hit splits a block into four smaller ones down to 5 m; then the
  border camera hand-off and fog in the four corners only.
- v1.5s (step 1b): drawn as ONE fused surface (walls only where the ground steps), not a box per block.
- v1.5t (step 2, craters, still only with ?blocks): the ground is 5 m cells grouped into aligned 20/10/5 m blocks.
  A blast (`BLOCK_BLAST` by weapon: gun / missile / heavy / special) hits every block in its radius; a block only partly
  inside splits into four, so only the hit part goes; 5 m layers break after `BLOCK_HITS` by material (sand 1, dirt 2,
  stone 4, obsidian 8; obsidian never splits). Materials are layered by depth from the planet seed, toned from the
  planet's ground colour (`BLOCK_TONES`). Rubble by material (`BLOCK_BREAK_PIECES` 2/3/4/5, obsidian cleaves again on
  a hard landing), capped (`BLOCK_RUBBLE_PER_BLAST`, `BLOCK_RUBBLE_LIVE`). Shots, missiles and the special's beam dig
  it; with no target over the patch a missile fires straight. Kept: seed + one note per blast (`GS.block_deltas`,
  session only until the game has a save file). Only changed squares redraw (`BLOCK_CHUNK`). Full design and the
  owner's later rules: docs/PLANET_BLOCKS.md.
- v1.5u: over the block ground a bump is free up to cruising speed (`BLOCK_SAFE_BUMP` 40 m/s) and while braking;
  only the speed past it hurts; the mech is never hurt by the ground. Normal planets keep the old rule.
- v1.5v: the mech pushing into a block wall digs it by the shot rules (`MECH_DIG_*`, "thrust" blasts): plows sand and
  dirt, breaks stone a hit per push with a bounce-back, only bounces off obsidian; never hurt.
- v1.5w (normal play, owner's request): the super (heavy) missile has a bigger hitbox (14 m vs 9 m) and a big
  explosion in space fights; on the block ground it already dug a bigger crater (20 m vs 12 m). Damage unchanged.
- v1.5x (normal play, owner): the super (heavy) missile hits as hard as 3.5 regular missiles (`HEAVY_MISSILE_MULT`)
  and locks slowly (`HEAVY_LOCK_STEP` 2.5 s a lock, up to 2; it won't fire without a lock, except straight down at
  the block ground with nobody around). Mines hit as hard as a super missile, falling off over their blast radius.
  Two kinds of mine (switch at Equipment, `GS.mine_kind`): BLAST, and MAGNETIC (blue light) which also pulls the
  ships it hits in to the blast point and holds them for `MAG_MINE_HOLD` 3.5 s.
- v1.5y (step 5, support and collapse, ?blocks only): each 5 m cell keeps air pockets under its top (`holes`), so blasts
  dig into walls: tunnels, overhangs, caves. Every layer inside the blast sphere takes the weapon's hits. Floating pieces
  must be joined sideways to grounded ground within `BLOCK_REACH` (sand 0 / dirt 1 / stone 3 / obsidian 5 cells) or they
  fall (`_settle`). Ship and mech use tunnel floors and roofs; the mech digs a tunnel its own size by pushing.
- v1.5z (step 6, settling, ?blocks only): landed rubble merges into the ground as its own material (`mats` per layer,
  `fill` for part-layers, `BLOCK_MERGE_DELAY`); dirt sticks to walls in flight; sand slumps to 45-degree piles
  (`BLOCK_SAND_STEP`); collapsing pieces keep their material. Merges are kept as "dep:" notes and replayed.
- v1.6a (?blocks only): a look-only skin over the blocks: sand tops ease into blunt mounds, dirt/stone edges round
  off, fused obsidian tops point into shard tips (`BLOCK_SKIN`, `_skin_top`). Collision unchanged.
- v1.6b (?blocks only): water and lava (`fluid` per cell/layer): sealed seed pockets, asleep until opened, flow near
  the player only, react with sand / dirt / each other, drawn see-through; lava burns. See docs/PLANET_BLOCKS.md 2f.
- v1.6c (?blocks only): gold / diamond veins from the seed (`_place_veins`), tough layers; breaking one emits `mined`
  and the game drops pickup gems (fewer with bigger weapons, `MINING_KEEP`) for the tractor beam (`MINE_VALUE` credits).
- v1.6d (?blocks only): world generation 1: seeded sealed cave pockets (`_carve_caves`, `CAVE_*`); an obsidian cap
  (`KILL_CAP`) over a kill floor that glows when dug open and destroys the ship, fluids and rubble.
- v1.6e (?blocks only): world generation 2: seeded arches and Pride Rock promontories (`_build_landmarks`), held by
  `reach_bonus` so blasting a leg drops what hung from it.
- v1.6f (?blocks only): world generation 3: spire limit (`SPIRE_MAX`), a seeded winding canyon (`_carve_canyon`),
  obsidian roots piercing the surface (`_raise_roots`).
- v1.6g (normal play, owner bug): on a job your target was the mission marker / GPS stop, and auto-targeting never
  left it, so the job's enemies got no red brackets, no aim box and no missile lock. Now a waypoint, GPS stop or
  mission marker hands the target over to the nearest hostile when one is near (a station or planet you picked
  yourself does too once hostiles turn on you). Bounty targets from the old bounty board are always hostile too.
- v1.6h (?blocks only): the deep world: seeded root halls over the obsidian cap (`_carve_root_halls`, `HALL_*`).
- v1.7a (?blocks only): step 9 part 1, the whole planet as blocks: 500 m regions built round the player from the seed (`BlockField.build(pid, tile, region)`, space `_update_regions` / `_fields` / `_block_field_at` / `_ray_blocks`), the smooth sheet cut out under them in the terrain shader, flat blocks round cities (`BLOCK_REGION*`, `BLOCK_SITE_FLAT`).
- v1.7b: block ground on for everyone (`BlockField.enabled()` true unless the web address has ?noblocks); the smooth sheet is the far view only.
- v1.7c: landing pads on floating block islands (`Surface.pad_top` / `island_at` / `_pad_island`, `PAD_ISLAND_*`); the ground under cities is no longer flattened when blocks are on.
- v1.7d: seams: `_blast_blocks` digs every region a blast reaches; regions keyed `Vector4i(tile dx, tile dz, rx, rz)` so neighbour tiles' regions are built in this frame (`build(..., frame)`, notes in own-tile frame) and carried over a border crossing (`reframe`).
- v1.7e: slanted outer form (look only): `_slant` / `_corner_h` / `_slant_ok` / `_slant_top` lean natural tops into slabs and wedges, per-corner so neighbours always meet (`BLOCK_SLANT_MAX`).
- v1.7f: leaning slabs and A-frames (`_build_slabs`, drawn whole by `_draw_slabs`, `_slab_lo` hides their blocks while whole, `_slab_check` drops the look once hit).
- v1.7g: owner's look: grass cap + brown dirt (`BLOCK_GRASS_BAND`, `DIRT_BROWN`), `_join_columns` (`BLOCK_SHAPES`), slant patches (`BLOCK_SLANT_ZONE`).
- v1.7h: molds (`_stamp` cut/add of [dx, dz, klo, khi] runs, `_runs_of`) and the first cave mold (`_carve_cave_mold`, `MOLD_*`).
- v1.7i: alien trees (`_grow_trees` / `_grow_tree` / `_grow_cave_tree`, wood + leaf + leaf2) and fire (`ignite`, `_fire_update`, `_draw_fire`, `FIRE_*`); `_stamp` "add" now also sets the material of layers already solid.
