# Homelancer web loading and scalability (audit, Sept 30 2026)

Measured on commit 9b2028f (live build at the time of the audit) and again after the fixes in this job.
- **Tools:**
  - `tools/perf/measure_web.py` measures cold and warm loads in Chromium with a real disk cache.
  - `tools/perf/web_route.py` runs the full route test inside the web build.
  - `HL_PROFILE=1` prints startup step times and memory.
  - `HL_SOAK=n` runs n round trips: space, planet, sector, sector, orbit.
- **Phone profiles:** CPU slowed 4x plus either LTE (9 Mbit/s, 85 ms) or weak 3G (1.6 Mbit/s, 150 ms). These are estimates; a real phone's GPU and browser differ.

## What a player downloads
| | Before (9b2028f) | After |
|---|---|---|
| Files before the game can start | 6 requests | 6 requests |
| index.wasm (Godot 4.3 engine; gzip on the wire) | 35.4 MB → 8.0 MB | same |
| index.pck (game core) | 14.4 MB | **9.7 MB** |
| **Initial transfer** | **22.4 MB** | **17.8 MB** |
| Optional packs (fetched in background or on demand) | none | mechs 1.85 MB · planets 0.8 MB · lancer 1.4 MB · enemies 0.2 MB · city 0.04 MB |

Biggest files in the core pck (before):
| File | Size | What uses it | Needed at start? |
|---|---|---|---|
| station.glb (44k tris) | 2.16 MB | every station | yes |
| carrier.glb (38k tris) | 1.75 MB | background carrier | yes, it's visible at the start |
| cadet_ship.glb (34k tris) | 1.66 MB | player ship | yes |
| lancer.glb (19k tris) | 0.87 MB + 0.5 MB textures | dealer / owned ship | **no**, moved to a pack |
| station_0..2.jpg (2048 px) | 1.45 MB | station | yes, now 1024 px |
| tan_navy_mecha.glb (17k tris) + textures | 0.71 MB + 0.46 MB | mech enemies | **no**, moved to a pack |
| ground_albedo / ground_normal | 0.78 MB | planet surfaces | **no**, moved to a pack |
| other textures, audio, scripts | ~6 MB | | |

## Load times
| | Before | After |
|---|---|---|
| Desktop cold | 7.6 s | 7.2 s |
| Desktop warm | 5.0 s | 4.7 s |
| Phone LTE cold (est.) | 35 s (download 20 s · engine 2.7 s · system 12 s) | **30 s** (download 15.7 s · engine 3.0 s · system 11.3 s) |
| Phone LTE warm (est.) | 15 s | 14.5 s |
| Phone weak-3G cold (est.) | 127 s | **101 s** |

## Memory
| | Before | After |
|---|---|---|
| GPU textures at start (native) | **125 MB** | **49 MB** (web) |
| GPU mesh buffers at start | 24 MB | 26 MB |
| In play, with planets and mechs loaded | | 64–69 MB textures · 36–40 MB buffers |
| 6 laps of space → planet → 2 sectors → orbit | | flat after lap 1 (81 MB textures, 166 nodes); nothing leaks |

**Why the GPU memory was so high:** model textures are stored small in the download, but they are unpacked to full size in GPU memory. One 2048 px station texture took 22 MB of GPU memory, and the station has three of them.
- Stations are now 1024 px.
- The carrier, enemy ships, cargo ships, mechs and weapons are now 512 px.
- The player ship stays at 1024 px.

## Why the Samsung looked stuck for ~30 minutes
The download itself is about 15–35 s on mobile data, so size alone can't explain 30 minutes. The old loading screen only knew the download percentage and the "engine finished" signal. If anything went wrong after that, it kept showing the moving bar forever with no message. Any of these would do that:
- The browser killed the graphics context. 125 MB of textures went to the GPU at once, on top of the 35 MB engine and the 14 MB pack in RAM. That is exactly the memory pressure that makes Android Chrome or Samsung Internet drop WebGL.
- The download stalled, with no timeout.
- The engine script failed to load, leaving the screen frozen at "Preparing flight deck…".
- The engine crashed or threw an error that only went to the hidden browser console.

The phone itself can't be inspected from here, so which of these happened is the most likely explanation, not proven. Two fixes remove both the cause and the silence:
1. GPU memory at start is down 61 %, and three content packs are out of the first download.
2. The new loading screen:
   - shows the stages: CORE (download) → ENGINE → SYSTEM (with the current build step) → READY;
   - warns if the download makes no progress for 30 s;
   - warns if starting takes over 90 s;
   - shows an error on WebGL context loss, a script that fails to load, or any engine error;
   - has Reload and **Copy details** buttons. Copy details produces a report (phase, last step, last error, device, log) that can be pasted to Claude.

## Architecture (how it scales)
- **Core download:** engine + UI + scripts + audio + the starting system's models.
- **Content packs (`scripts/packs.gd`, autoload `Packs`):**
  - Anything not needed to start lives in `packs/<name>.pck` next to the web build.
  - The export plugin `addons/content_packs` writes the packs automatically during the normal export, so the deploy workflow didn't change.
  - `export_presets.cfg` leaves those folders out of the core.
  - Packs download in the background 1.5 s after boot, or when needed. Entering a planet waits for `planets` behind the cloud transition.
  - In the editor and the desktop tests everything is local, so packs count as ready immediately.
- **Star systems:** one is loaded at a time (`_load_system` frees the old one).
- **Planet surfaces:**
  - One sector is loaded at a time. It's procedural (about 1 KB of data per planet) and built when you enter.
  - At most 6 built sectors are kept in memory.
  - The orbital planet is a cheap sphere with a 384x192 generated texture.
- **Scalability test:** 10 extra planets were added, each with 4 MB of its own textures in its own pack (41 MB more content in total). The initial download grew by **2 KB**, which is just the planet list.
- **Rule for new content:** each new star system, planet, or big model set gets its own entry in `Packs.PACKS` and a folder excluded from the core.

## Budgets (from these measurements; Samsung mid-range on LTE)
| | Budget | Now |
|---|---|---|
| Initial transfer | ≤ 18 MB now; target ≤ 12 MB | 17.8 MB |
| Core pck | ≤ 10 MB | 9.7 MB |
| Cold start, phone LTE | ≤ 30 s now; target ≤ 20 s | ~30 s |
| Warm start, phone | ≤ 15 s | ~14.5 s |
| GPU textures at start | ≤ 64 MB | 49 MB |
| GPU textures in play (one system or planet loaded) | ≤ 96 MB | 64–69 MB |
| GPU mesh buffers | ≤ 48 MB | 26–40 MB |
| One content pack | ≤ 3 MB (≈ 3 s on LTE) | 0.8–1.4 MB |
| Planet entry (pack + build, hidden by clouds) | ≤ 2 s phone if the pack is already fetched | ~0.2 s desktop build |
| Sector change | ≤ 1 s phone | 0.2 s desktop, instant if cached |
| Station or town dock (UI only) | ≤ 0.5 s | ~instant |
| Triangles | player ≤ 35k, enemy ≤ 8k, mech ≤ 20k, station ≤ 45k, big background ship ≤ 40k | within all of these |
| Textures | player ship 1024 px; everything else 512 px; terrain detail 1024 px shared | |

## Next steps (biggest remaining costs)
1. **Engine size:** the Godot engine is 8 MB of the 17.8 MB. A custom web export template without unused engine parts (3D physics, navigation, XR, etc.) typically saves 2–3 MB on the wire. That needs a one-time engine build, and the deploy workflow would then download that template instead of the official one.
2. **System build phase** (~11 s on the phone profile): much of it is shader compilation and first frames on software graphics. Measure on the real phone with Copy details before changing anything.
3. **Carrier** (1.75 MB): decimate it to ~12k triangles, or put it in a pack and show it once it arrives.
