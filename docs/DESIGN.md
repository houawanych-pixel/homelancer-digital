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
