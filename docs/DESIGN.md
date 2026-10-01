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

## 9. Implementation order (from the master spec)
1. Optimized public build (Job L) ✔
2. Real Samsung loading test — **waiting for the report** (Copy details)
3. Content-pack streaming ✔
4. Planet entry ✔ (two spheres, Job M)
5. Seamless sector borders ✔ (Job M)
6. Corner cloud ✔ (Job M)
7. Warp rule update ✔ (Job M)
8. Mech directional boost (next)
9. Ship/mech damage icon ✔ for the ship (Job M); the mech version comes with the transformation
10. Transformation prototype (next)
11. Basic travel-system data model (after)
12. Star-map UI prototype (after)
