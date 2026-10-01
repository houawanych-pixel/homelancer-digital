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
  08 B-01 command tower blockout (40×40 m footprint, roof 100 m, spire to 120 m, wings at deck height for platforms).
- **One test block** in New Terra's city sector, ~1 km north-west of Port Meridian, on its own flattened ground.
  The rest of New Terra keeps all its biomes (the canyon/desert references are ONE biome).
- **One material family:** one shader, five settings (white armour, dark structure, blue glass, amber, road). Panel
  seams, grooves, bolts, vents and window cells come from one 512 px normal map + mask, tiled in world space.
- **Cost:** ~840 instanced parts, ~9.7k triangles, 11 draw calls up close / 8 at range (small parts drop out past
  1.1 km), 201 collision boxes. `city` pack 37 KB, +1.8 MB GPU on the planet, nothing in the core download.
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
