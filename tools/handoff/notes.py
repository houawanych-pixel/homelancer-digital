"""Parts notes (fixed / moving / swappable) and the remodel list, from the inventory + GLB metadata.
usage: python3 notes.py <handoff_dir>"""
import sys, os, json, csv, glob
H = sys.argv[1]
INV = list(csv.DictReader(open(H + '/01_inventory/inventory.csv')))
TEX = list(csv.DictReader(open(H + '/04_textures/texture_maps_by_material.csv')))
meta = {}
for f in glob.glob(H + '/02_models/*/*/meta.json'):
    m = json.load(open(f)); meta[m['model']] = m
tex = {}
for t in TEX: tex.setdefault(t['model'], []).append(t)
parts = []
for r in INV:
    k = r['model']; m = meta.get(k, {}); nodes = [n for n in m.get('node_names', []) if n]
    cat = r['category']
    if cat == 'ship':
        if k == 'elyza_fighter':
            parts.append([k, 'Body', 'fixed', 'separate mesh node'])
            for w in ('WingL', 'WingR'): parts.append([k, w, 'MOVING', 'separate mesh node; the game swings it for the "wings_out" special move (Data ship_wings 0.125)'])
        else:
            parts.append([k, 'whole ship (one merged mesh: %s)' % (nodes[0] if nodes else '?'), 'fixed', 'wings, engines and guns are NOT separate objects in this file'])
        parts.append([k, 'engines / thrusters', 'fixed (effect only)', 'no engine nodes in the file; the game adds the engine glow and trail itself. Engine positions: UNKNOWN (not recorded)'])
        parts.append([k, 'core guns -1 / -5 / -6, wing mounts 0-5', 'SWAPPABLE (added by the game)', 'separate weapon GLBs (02_models/equipments) placed by rule; see 05_.../ship_mount_points_game_metres.csv'])
    elif cat == 'mech':
        if m.get('skins'):
            parts.append([k, 'body (skinned to a humanoid rig: Hips..Head, arms, legs)', 'MOVING (skeleton)', 'animations in file: %s' % ', '.join(m.get('animations', []))])
            parts.append([k, 'arms / hands', 'MOVING', 'LeftUpperArm/LowerArm/Hand and Right..; weapon held in the hand bone'])
            parts.append([k, 'weapons, cannons, boosters', 'mostly fixed into the skinned mesh', 'the rig locks weapons to their bone; not separate objects (red_mecha and white_mecha have 2 meshes)'])
        else:
            parts.append([k, 'whole frame (Godot .scn, baked from the rigged GLB)', 'see the matching *_rigged GLB', 'exported to GLB for this handoff (the game file itself is .scn)'])
        parts.append([k, 'hand-held weapon', 'SWAPPABLE (game)', 'mech weapons from assets/ui/mech_weapons + wing_guns models are placed at the hand joint; joints in 05_.../mech_joints'])
    elif cat == 'station':
        parts.append([k, 'whole station (one mesh)', 'fixed', 'no rotating rings or docking arms as separate objects; the docking ring and lights are code-made'])
    elif cat == 'equipment':
        parts.append([k, 'whole weapon (one mesh)', 'SWAPPABLE item', 'built %.1f m long (WING_GUN_LEN), then scaled to a share of the ship length' % 2.6])
with open(H + '/06_parts_fixed_moving_swappable/parts_notes.csv', 'w', newline='') as f:
    w = csv.writer(f); w.writerow(['model', 'part', 'type', 'notes']); w.writerows(parts)
# remodel list
rem = []
for r in INV:
    k = r['model']; m = meta.get(k, {}); cat = r['category']
    if cat not in ('ship', 'mech', 'station'): continue
    reasons = []; pri = 3
    if k.startswith('placeholder_'): reasons.append('stand-in shape for a faction with no ship of its own'); pri = 1
    if cat == 'ship' and k != 'elyza_fighter': reasons.append('one merged mesh: wings/engines/guns not separate for swaps or animation')
    miss = set()
    for t in tex.get(k, []):
        for x in (t.get('missing_maps') or '').split(', '):
            if x: miss.add(x)
    if miss: reasons.append('missing maps: ' + ', '.join(sorted(miss)))
    if r['used_in_game'] == 'yes' and cat == 'ship' and pri > 1: pri = 2
    if cat == 'station' and r['used_in_game'] == 'yes': pri = min(pri, 2)
    if cat == 'mech' and not m.get('skins'): reasons.append('game uses a baked .scn; rebuild from the rigged GLB')
    tris = int(r.get('triangles') or 0)
    if tris and tris < 3000 and cat == 'ship': reasons.append('low detail (%d triangles)' % tris)
    rem.append([pri, k, cat, r['faction'], r['used_in_game'], r['file_path'], tris or '', '; '.join(reasons)])
rem.sort(key=lambda x: (x[0], x[2], x[1]))
with open(H + '/07_remodel_list/remodel_list.csv', 'w', newline='') as f:
    w = csv.writer(f); w.writerow(['priority (1 = first)', 'model', 'category', 'faction', 'used in game', 'file', 'triangles', 'why']); w.writerows(rem)
print(len(parts), 'part rows;', len(rem), 'remodel rows')
