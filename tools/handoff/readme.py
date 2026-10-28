"""Writes 00_README.md (found vs missing) for the handoff. usage: python3 readme.py <handoff_dir>"""
import sys, csv, json, glob, os, collections
H = sys.argv[1]
INV = list(csv.DictReader(open(H + '/01_inventory/inventory.csv')))
DRV = list(csv.DictReader(open(H + '/01_inventory/drive_originals_tripo_exports.csv')))
TEX = list(csv.DictReader(open(H + '/04_textures/texture_maps_by_material.csv')))
cnt = collections.Counter((r['category'], r['used_in_game']) for r in INV)
sheets = len(glob.glob(H + '/08_reference_sheets/*/*.png'))
blend = [p for p in glob.glob('/home/claude/homelancer-digital/**/*.blend', recursive=True)]
objs = [p for p in glob.glob('/home/claude/homelancer-digital/**/*.obj', recursive=True)]
drv_ext = collections.Counter(os.path.splitext(r.get('title', r.get('name', '')))[1].lower() for r in DRV)
miss = collections.Counter()
for t in TEX:
    for x in (t.get('missing_maps') or '').split(', '):
        if x: miss[x] += 1
def c(cat): return '%d (%d used in the game, %d not)' % (cnt[(cat, 'yes')] + cnt[(cat, 'no')], cnt[(cat, 'yes')], cnt[(cat, 'no')])
txt = f"""# Homelancer asset handoff -- ships, mechs, stations

Made from COPIES of the game repo (houawanych-pixel/homelancer-digital, branch homelancer-v1.2, game v8.6).
Nothing in the repo or on Google Drive was changed or overwritten.

## What is in each folder

| Folder | What it holds |
|---|---|
| 01_inventory | inventory.csv: every ship, mech, station and equipment model: name, category, faction, file path, format, triangles, file size, used in the game or not, what uses it. drive_originals_tripo_exports.csv: the original Tripo exports found on Google Drive, with links |
| 02_models | Copies of the game models (GLB). Each model has its own folder with the GLB, a textures/ folder (images pulled out of the GLB), textures_external/ when the game keeps textures beside the file, and meta.json (nodes, materials, bounds, triangles) |
| 03_concepts_previews | Mech concept art per faction, kaiju mech concepts, hangar bay art, the game's ship/mech card previews, and station exterior concepts (Drive links) |
| 04_textures | texture_maps_by_material.csv: per material, which maps exist (base colour, normal, roughness/metallic, AO, emissive) and which are missing |
| 05_scale_axes_pivots_mounts | scale_axes_pivots.csv, ship_mount_points_game_metres.csv, mech_joints/ (joint positions of each rigged mech) |
| 06_parts_fixed_moving_swappable | parts_notes.csv: fixed, moving and swappable parts per model |
| 07_remodel_list | remodel_list.csv (priority order) and FIRST_TRIAL_SHIP.md |
| 08_reference_sheets | One sheet per model: FRONT, SIDE, BACK across the top, TOP under SIDE. Same geometry, same orthographic scale, alignment guides |
| 09_maps_layouts | Every station, planet, gate, asteroid field, nebula and patrol point in every system, with sizes and the distance to the tile border; a top-down picture per system; the 11 x 11 galaxy board; planet surface tiles; boundaries_and_sizes.json |

## Counts (found)

- Ships: {c('ship')}
- Mechs: {c('mech')}  (12 game frames are Godot .scn files, exported to GLB here; 13 rigged GLB sources with Walk/Idle)
- Stations and structures: {c('station')}
- Equipment (wing guns, weapons): {c('equipment')}
- Props: {c('prop')}
- Reference sheets: {sheets}
- Original exports listed on Google Drive: {len(DRV)} files (by type: {', '.join('%s %d' % (k or '?', v) for k, v in drv_ext.most_common(8))})

## Scale, axes and pivots (what is known)

- glTF units are metres; +Y is up. The Tripo files are normalised (about 0.5-1 unit long), so the file size is NOT the real size.
- The game sets each ship's real size: it scales the model so its LONGEST side equals the length in the model table (game_length_m), then moves the pivot to the centre of the bounds. So the in-game pivot = bounds centre, whatever the file origin is.
- Forward: the nose points to -Z after the yaw in the table (yaw_correction_deg). The reference sheets already apply that yaw.
- Stations: 170 m wide x style scale (Capital 1.6, Military 1.15, Trade 1.3, Outpost 0.9; a few named ones have their own). Their front (-Z in the file) faces the docking approach.
- Mount points: worked out by rule from the ship's width and length (shoulder 30% out on top, mid 62% on top, tip 92% underneath, 0.5 m above/below; core guns under the nose). Listed per ship in metres.

## Missing or unknown (please do not guess these)

- Ship concept images: NOT in the repo. Drive has only a few ship pictures (modular cargo hauler, tanker hull, ship-dealer page, WIP blanks); listed in 03_concepts_previews/drive_concept_links.csv.
- Blender source files: {'none found in the repo' if not blend else ', '.join(blend)}.
- OBJ + MTL exports: none for any ship, mech or station (the repo's only OBJ files are two tree molds). The Drive originals are GLB or ZIP, no OBJ found.
- Original Tripo GLBs: most are 20-60 MB on Drive, too large for this tool to download. They are linked (with IDs) in drive_originals_tripo_exports.csv instead of copied.
- Texture maps missing across materials: {', '.join('%s missing in %d' % (k, v) for k, v in miss.most_common())}. Stations have base colour + normal only (no roughness/metal/AO). Almost nothing has an emissive map (glow comes from the game's effects).
- Real-world intended dimensions beyond the game lengths: unknown.
- Engine / thruster positions: not recorded anywhere (engines are effects added by the game).
- Separate parts: only elyza_fighter has separate Body / WingL / WingR. Every other ship and station is one merged mesh. Mech weapons are part of the skinned mesh.
- Equipment attachment points on stations: none (stations have no hardpoints).
- Planet surface layouts: placements on surface tiles are generated at run time; only tile size and types are listed.

## Map space for planning

- Each system is a 1,000 km square tile: 500,000 m each way from the centre (SPACE_EDGE). Crossing it moves you to the neighbouring board square (the board wraps).
- Everything placed in a system today sits within about 4-22 km of the centre (median 8.7 km), so every object has at least 477 km to the border. See margin_to_tile_border_m in the placements CSV.
- Planet surface tile: 5,000 m square (2,500 m each way).
"""
open(H + '/00_README.md', 'w').write(txt)
open(H + '/07_remodel_list/FIRST_TRIAL_SHIP.md', 'w').write("""# First ship for a trial rebuild: cadet (Cadet, the player's starting ship)

File: 02_models/ships/cadet/cadet_ship.glb  (game copy of assets/ships/player/cadet_ship.glb)
Reference sheet: 08_reference_sheets/ships/cadet_reference_sheet.png

Why this one:
- Every new player flies it first, so it is the ship seen the most.
- It is small and simple (4,400 triangles, one material), so a rebuild is quick to judge.
- It uses all the equipment rules: core guns, shoulder / mid / tip wing mounts, missile and mine bays, so the rebuild tests swapping.
- Today it is one merged mesh, so the trial shows the value of separate parts.

Suggested split for the rebuild (keep as separate objects in one GLB):
- Hull (fixed)
- Left wing, right wing (separate, so they can move or carry mounts)
- Engines / nozzles (separate, so glow and thrust effects attach to them)
- Empty mount nodes: gun_front, gun_front_2, gun_belly, wing_L_shoulder, wing_L_mid, wing_L_tip, wing_R_shoulder, wing_R_mid, wing_R_tip
- Nose at -Z, +Y up, origin at the centre of the bounds, built at real size: the game makes the Cadet 9 m on its longest side (model table), yaw 0.
- Game stats to respect: 2 core guns ("twin cannons on top" in its description), 100 missiles, 20 mines.
""")
print('readme ok')
